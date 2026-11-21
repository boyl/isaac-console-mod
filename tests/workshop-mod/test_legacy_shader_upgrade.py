"""隔离的旧 Shader 升级/回退契约；不触及真实游戏。"""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SHADER = Path(__file__).with_name("fixtures") / "legacy-console-shaders.xml"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def main():
    with tempfile.TemporaryDirectory(prefix="shader-upgrade-", dir=ROOT / "dist") as temporary:
        root = Path(temporary)
        target = root / "game/mods/example"
        candidate, baseline, recovery = root / "candidate", root / "baseline", root / "recovery"
        target.mkdir(parents=True)
        candidate.mkdir()
        (target.parents[1] / "isaac-ng.exe").write_bytes(b"test fixture only")
        identity = b"<metadata><name>Fixture</name><directory>example</directory><id>123</id></metadata>"
        for folder in (target, candidate):
            (folder / "metadata.xml").write_bytes(identity)
            (folder / "main.lua").write_bytes(b"same Lua")
        (target / "content").mkdir()
        shutil.copyfile(SHADER, target / "content/shaders.xml")
        (target / "disable.it").write_bytes(b"")
        (target / "save1.dat").write_bytes(b"user data")
        (target / "content/custom.xml").write_bytes(b"unrelated")
        baseline.mkdir()
        shutil.copytree(target, baseline / "installed-en")
        original = {p.relative_to(target).as_posix(): sha(p) for p in target.rglob("*") if p.is_file()}
        manifest = {"sets": [{"name": "installed-en", "path": str(target)}], "files": [
            {"set": "installed-en", "path": path, "sha256": digest} for path, digest in original.items()]}
        (baseline / "baseline.json").write_text(json.dumps(manifest), encoding="utf-8")
        arguments = ["-Candidate", str(candidate), "-Target", str(target), "-Baseline", str(baseline / "baseline.json"),
                     "-BaselineSet", "installed-en", "-RecoveryDirectory", str(recovery)]

        def install(apply=False, success=True):
            # Stub ONLY the process check in this isolated filesystem fixture.
            command = "function Get-Process { param($Name) }; & '" + str(ROOT / "tools/install-hd-menu.ps1") + "'"
            result = subprocess.run(["pwsh", "-NoProfile", "-Command", command, *arguments, *(["-Apply"] if apply else [])], capture_output=True)
            assert (result.returncode == 0) == success, result.stdout + result.stderr
            return result.stdout.decode("utf-8")

        preview = install()
        assert "content/shaders.xml" in preview, "upgrade did not plan removal of known stale shader"
        assert (target / "content/shaders.xml").exists()
        print("PASS preview plans known shader removal without mutation")
        (target / "content/shaders.xml").write_bytes(b"user shader")
        install(True, False)
        assert not recovery.exists()
        print("PASS unknown/user-modified shader blocks transaction")
        shutil.copyfile(SHADER, target / "content/shaders.xml")
        install(True)
        assert not (target / "content/shaders.xml").exists()
        assert sha(recovery / "before/content/shaders.xml") == sha(SHADER)
        for relative, digest in original.items():
            if relative != "content/shaders.xml":
                assert sha(target / relative) == digest
        print("PASS known shader backed up and removed; disable/save/unrelated files preserved")
        result = subprocess.run(["pwsh", "-NoProfile", "-Command", "function Get-Process { param($Name) }; & '" + str(ROOT / "tools/restore-hd-menu.ps1") + "'",
                                 "-Manifest", str(recovery / "rollback.json"), "-Apply"], capture_output=True)
        assert result.returncode == 0, result.stdout + result.stderr
        assert {p.relative_to(target).as_posix(): sha(p) for p in target.rglob("*") if p.is_file()} == original
        print("PASS rollback restores exact original file tree")


if __name__ == "__main__":
    main()
