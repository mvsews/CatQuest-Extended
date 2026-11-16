"""Build an addon archive with the verified original dungeon recordings."""
import hashlib
import json
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
addon = ROOT / "CatQuest"
version = next(line.split(":", 1)[1].strip() for line in
               (addon / "CatQuest.toc").read_text().splitlines() if line.startswith("## Version:"))
stage = ROOT / "dist/dungeon-audio"
manifest = json.loads((stage / "manifest.json").read_text(encoding="utf-8"))
out = ROOT / f"dist/release/CatQuest-{version}.zip"
out.parent.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(out, "w", compression=zipfile.ZIP_DEFLATED) as z:
    for path in sorted(addon.iterdir()):
        if path.is_file():
            z.write(path, f"CatQuest/{path.name}")
    for key, meta in manifest.items():
        path = stage / f"{key}.ogg"
        assert hashlib.sha256(path.read_bytes()).hexdigest() == meta["sha256"], key
        z.write(path, f"CatQuest/Sounds/dungeon/{key}.ogg")
with zipfile.ZipFile(out) as z:
    assert z.testzip() is None
    assert len([p for p in z.namelist() if p.endswith('.ogg')]) == len(manifest)
print(f"{out.name}: {out.stat().st_size} bytes, sha256={hashlib.sha256(out.read_bytes()).hexdigest()}")
