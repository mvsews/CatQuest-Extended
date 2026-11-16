"""Run with PYTHONPATH=.tmp/lua-runtime (lupa), using the client's Lua 5.1."""
from pathlib import Path
import json
import shutil
import subprocess
import sys
import zipfile
from concurrent.futures import ThreadPoolExecutor
from lupa.lua51 import LuaRuntime

root = Path(__file__).resolve().parents[1]
lua = LuaRuntime(unpack_returned_tuples=True)
compile_lua = lua.eval("function(s,n) local f,e=loadstring(s,n); assert(f,e) end")
for path in (root / "CatQuest").glob("*.lua"):
    compile_lua(path.read_text(encoding="utf-8-sig"), str(path))
lua.globals().ROOT = root.as_posix()
lua.execute((root / "validation/dungeons-all.lua").read_text(encoding="utf-8"))
print("Lua 5.1: all addon files compile; dungeon regressions passed", flush=True)
source = root / ".tmp-catquest-original/CatQuest_Books-1.2.0.zip"
if source.exists():
    with zipfile.ZipFile(source) as archive:
        lua.execute(archive.read("CatQuest_Books/DungeonData.lua").decode("utf-8-sig"))
    total = 0
    for map_id, generated in lua.globals().CatQuest335.DungeonData.items():
        original = lua.globals().CatQuestDungeonData[map_id]
        source_events = {e.id: e for e in original.ev.values()}
        imported = {e.id: e for e in generated.events.values()}
        assert source_events.keys() == imported.keys(), map_id
        for key, old in source_events.items():
            new = imported[key]
            assert old.text == new.track.text, key
            for field, value in old.items():
                if field == "text":
                    continue
                if hasattr(value, "values"):
                    assert list(value.values()) == list(new[field].values()), (key, field)
                else:
                    assert value == new[field], (key, field)
            total += 1
    print(f"Official source parity: all {total} events retain original text and trigger conditions", flush=True)
stage = root / "dist/dungeon-audio"
if "--no-audio" not in sys.argv and shutil.which("ffprobe") and (stage / "manifest.json").exists():
    manifest = json.loads((stage / "manifest.json").read_text(encoding="utf-8"))
    def probe(entry):
        key, meta = entry
        result = subprocess.check_output(["ffprobe", "-v", "error", "-show_entries",
            "format=duration", "-of", "csv=p=0", str(stage / f"{key}.ogg")], text=True)
        assert abs(float(result.strip()) - meta["duration"]) < 1, key
    with ThreadPoolExecutor(max_workers=8) as pool:
        list(pool.map(probe, manifest.items()))
    print(f"ffprobe: all {len(manifest)} OGG files decode; duration matches subtitles")
