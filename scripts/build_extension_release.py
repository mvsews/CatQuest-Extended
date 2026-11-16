"""Build the unpacked browser extension distribution with its manifest version."""
import hashlib
import json
import zipfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
source = root / 'lasthavens-addon-manager'
version = json.loads((source / 'manifest.json').read_text(encoding='utf-8'))['version']
out = root / 'dist/release' / f'CatQuest-Lasthavens-{version}.zip'
out.parent.mkdir(parents=True,exist_ok=True)
with zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED) as archive:
    for path in sorted(source.rglob('*')):
        if path.is_file() and not any(part in {'.git','__pycache__'} for part in path.relative_to(source).parts):
            archive.write(path,Path(source.name)/path.relative_to(source))
with zipfile.ZipFile(out) as archive:
    assert archive.testzip() is None
    assert json.loads(archive.read('lasthavens-addon-manager/manifest.json'))['version']==version
print(f'{out.name}: {out.stat().st_size} bytes, sha256={hashlib.sha256(out.read_bytes()).hexdigest()}')
