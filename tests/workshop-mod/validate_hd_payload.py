"""校验高清负载清单与哈希，返回限定的包内资源路径。"""
import hashlib
import json
import re


def validate_hd_payload(root):
    folder = root / 'resources/font/hd'
    manifest = json.loads((folder / 'manifest.json').read_text(encoding='utf-8'))
    allowed = {'scripts/typography.lua', 'resources/font/hd/manifest.json'}
    pattern = r'(?:hd_(?:title|body|caption)(?:_\d{3}\.png|\.fnt)|coverage\.lua|LICENSE-OFL\.txt)'
    for name, expected in manifest['files'].items():
        assert re.fullmatch(pattern, name), f'Unexpected HD resource: {name}'
        assert hashlib.sha256((folder / name).read_bytes()).hexdigest() == expected.lower(), name
        allowed.add('resources/font/hd/' + name)
    for role, size in [('title', 12), ('body', 10), ('caption', 10)]:
        profile = manifest['profiles'][role]
        assert profile['logicalSize'] == size and profile['atlasSize'] == size * 2
        assert profile['scale'] == 0.5
        assert f'resources/font/hd/hd_{role}.fnt' in allowed
    assert 'resources/font/hd/coverage.lua' in allowed
    assert 'resources/font/hd/LICENSE-OFL.txt' in allowed
    return allowed
