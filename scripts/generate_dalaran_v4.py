"""Generate Dalaran place lore with the approved ElevenLabs v4 narrator."""
from __future__ import annotations

import copy
import hashlib
import json
import os
import subprocess
import tempfile
import time
from pathlib import Path

ROOT = Path(os.environ.get("CATQUEST_ROOT", "/srv/CatQuest"))
SOURCE = ROOT / "docs/places/zones/dalaran.json"
MANIFEST = ROOT / "docs/places/voiced.json"
OUT = ROOT / "packs/places"
VOICE = "dOUm985NbbVxZK8gyh24"
MODEL = "eleven_v4"
MODEL_ID = "elevenlabs/eleven-v4"


def text_hash(text: str) -> str:
    return hashlib.md5(text.encode("utf-8")).hexdigest()[:8]


def cues(text: str, duration: float) -> list[list[float | str]]:
    import re

    parts = [p.strip() for p in re.split(r"(?<=[.!?…])\s+(?=[«\"A-ZА-ЯЁ—-])", text) if p.strip()]
    total = sum(len(p) for p in parts) or 1
    result = []
    done = 0
    for index, part in enumerate(parts):
        result.append([round(duration * done / total, 2), part])
        done += len(part)
    if result:
        result[0][0] = 0.0
    return result


def main() -> int:
    import sys

    env_file = ROOT / ".env"
    if env_file.is_file():
        for line in env_file.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))
    sys.path.insert(0, str(ROOT))
    from backend.elevenlabs_tts import synthesize

    source = json.loads(SOURCE.read_text(encoding="utf-8"))
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8")) if MANIFEST.exists() else {}
    places = []
    for raw in source.get("places", []):
        text = " ".join(str(raw.get("text") or "").split())
        if not text:
            continue
        item = dict(raw)
        item["text"] = text
        item["hash"] = text_hash(text)
        places.append(item)

    # One request per unique text; repeated AreaTable IDs share one narration.
    unique = {}
    for place in places:
        unique.setdefault(place["hash"], place)
    OUT.mkdir(parents=True, exist_ok=True)
    policy = json.loads((ROOT / "backend/voice_priority.json").read_text(encoding="utf-8"))
    policy = copy.deepcopy(policy)
    policy["enabled"] = True
    policy["model_overrides"] = {str(p["area_id"]): MODEL for p in places if p.get("area_id")}
    registry = json.loads((ROOT / "backend/elevenlabs_voices.json").read_text(encoding="utf-8"))

    with tempfile.TemporaryDirectory(prefix="catquest-dalaran-") as tmp_name:
        tmp = Path(tmp_name)
        for index, place in enumerate(unique.values(), start=1):
            digest = place["hash"]
            mp3 = tmp / f"{digest}.mp3"
            ogg = OUT / f"{digest}.ogg"
            data = {
                "id": int(place.get("area_id") or 0),
                "type": "DETAIL",
                "locale": "ruRU",
                "wow_version": "3.3.5a",
                "npc_id": 0,
            }
            print(f"[{index}/{len(unique)}] {place['subzone']} ({digest})", flush=True)
            result = synthesize(data, place["text"], "objectives", mp3, root=ROOT,
                                policy=policy, registry=registry)
            if not result or not mp3.is_file():
                raise RuntimeError(f"ElevenLabs did not return audio for {place['subzone']}")
            subprocess.run([
                "ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", str(mp3),
                "-af", "loudnorm=I=-17.5:LRA=3:TP=-1.5", "-ar", "24000", "-ac", "1",
                "-c:a", "libvorbis", "-q:a", "5", str(ogg.with_suffix('.tmp.ogg')),
            ], check=True)
            ogg.with_suffix(".tmp.ogg").replace(ogg)
            duration = float(subprocess.check_output([
                "ffprobe", "-v", "error", "-show_entries", "format=duration",
                "-of", "default=noprint_wrappers=1:nokey=1", str(ogg),
            ], text=True).strip())
            model, voice, _ = result
            manifest[digest] = {
                "zone": source["zone"],
                "subzone": place["subzone"],
                "area_id": place.get("area_id"),
                "d": round(duration, 1),
                "cues": cues(place["text"], duration),
                "tts_model": model,
                "tts_voice": voice,
                "generated_at": time.strftime("%Y-%m-%d %H:%M:%S"),
                "audio": ogg.name,
                "content_version": source.get("content_version", "shared"),
                "content_scope": source.get("content_scope", ""),
                "content_events": source.get("content_events", []),
                "kind": "place",
            }
            MANIFEST.write_text(json.dumps(dict(sorted(manifest.items())), ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(f"generated {len(unique)} Dalaran tracks with {MODEL_ID}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
