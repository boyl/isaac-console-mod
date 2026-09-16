"""在临时目录演练回退，绝不使用实际游戏目录。"""
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tools/restore-hd-menu.ps1"


def sha(value):
    return hashlib.sha256(value).hexdigest().upper()


def main():
    with tempfile.TemporaryDirectory(prefix="hd-rollback-", dir=ROOT / "dist") as tmp:
        root = Path(tmp)
        target, before = root / "example_mod", root / "before"
        target.mkdir()
        before.mkdir()
        identity = b"<metadata><name>HD test</name><directory>example_mod</directory><id>123</id></metadata>"
        (target / "metadata.xml").write_bytes(identity)
        (target / "main.lua").write_bytes(b"new")
        (target / "new.fnt").write_bytes(b"new-font")
        (target / "save1.dat").write_bytes(b"user-favorites")
        (before / "main.lua").write_bytes(b"old")
        manifest = {"schemaVersion": 1, "name": "HD test", "directory": "example_mod", "workshopId": "123", "target": str(target), "files": [
            {"path": "main.lua", "beforeHash": sha(b"old"), "afterHash": sha(b"new")},
            {"path": "new.fnt", "beforeHash": None, "afterHash": sha(b"new-font")}]}
        path = root / "rollback.json"

        def run(apply=False, success=True):
            path.write_text(json.dumps(manifest), encoding="utf-8")
            result = subprocess.run(["pwsh", "-NoProfile", "-File", str(SCRIPT), "-Manifest", str(path)] + (["-Apply"] if apply else []), capture_output=True)
            assert (result.returncode == 0) == success, result.stdout + result.stderr

        run()
        assert (target / "main.lua").read_bytes() == b"new"
        print("PASS preview does not write")
        (target / "main.lua").write_bytes(b"user-edit")
        run(apply=True, success=False)
        assert (target / "new.fnt").exists()
        (target / "main.lua").write_bytes(b"new")
        print("PASS post-install edits block all mutations")
        (target / "new.fnt").unlink()
        run(apply=True, success=False)
        assert (target / "main.lua").read_bytes() == b"new"
        (target / "new.fnt").write_bytes(b"new-font")
        print("PASS manually removed candidate file blocks restoration")
        (before / "main.lua").write_bytes(b"corrupt")
        run(apply=True, success=False)
        (before / "main.lua").write_bytes(b"old")
        print("PASS corrupt backup blocks restoration")
        manifest["files"][0]["path"] = "../outside.lua"
        run(apply=True, success=False)
        manifest["files"][0]["path"] = "main.lua"
        print("PASS traversal rejected")
        run(apply=True)
        assert (target / "main.lua").read_bytes() == b"old"
        assert not (target / "new.fnt").exists()
        assert (target / "save1.dat").read_bytes() == b"user-favorites"
        run(apply=True)
        print("PASS restore old / remove added / preserve save / idempotence")


if __name__ == "__main__":
    main()
