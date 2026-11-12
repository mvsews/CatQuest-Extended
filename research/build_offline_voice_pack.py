#!/usr/bin/env python3
"""Merge approved server-generated quest audio into an offline voice pack.

The server export is a sanitized metadata file.  Audio is read from a local
normalized cache, while the base archive remains the original CatQuest Voices
release.  Only ready ruRU tracks for quest IDs absent from the base index are
added; existing original recordings are never overwritten.
"""

from __future__ import annotations

import argparse
import json
import re
import zipfile
from collections import defaultdict
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_BASE = ROOT / "dist" / "CatQuestExtended_Voices-1.3.0-full.zip"
DEFAULT_CACHE = ROOT / ".tmp" / "server-normalized"
DEFAULT_EXPORT = ROOT / ".tmp" / "production-voice-export.json"
DEFAULT_OUTPUT = ROOT / "dist" / "CatQuestExtended_Voices-1.3.0-full-with-community.zip"
DEFAULT_METADATA_ROOT = ROOT / "CatQuestExtended_Voices"
INDEX_RECORD_RE = re.compile(r"(?m)^\s*\[(\d+)\]\s*=\s*\{")
TRACK_FILE_RE = re.compile(
    r"(?:^|/)Sounds/q/(?P<id>\d+)(?P<turnin>_t)?"
    r"(?:_n\d+)?(?:_[mf])?\.ogg$",
    re.IGNORECASE,
)


def read_ready_rows(path: Path) -> dict[tuple[int, str], dict[str, Any]]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    rows = payload.get("rows", payload) if isinstance(payload, dict) else payload
    result: dict[tuple[int, str], dict[str, Any]] = {}
    for row in rows:
        if not isinstance(row, dict) or row.get("track_status") != "ready":
            continue
        if str(row.get("locale", "")) != "ruRU":
            continue
        try:
            quest_id = int(row["quest_id"])
            quest_type = str(row["quest_type"]).upper()
        except (KeyError, TypeError, ValueError):
            continue
        if quest_id <= 0 or quest_type not in {"DETAIL", "COMPLETE"}:
            continue
        key = (quest_id, quest_type)
        if key in result:
            raise ValueError(f"duplicate ready track in export: {quest_id} {quest_type}")
        result[key] = row
    return result


def base_quest_ids(index_text: str) -> set[int]:
    return {int(match.group(1)) for match in INDEX_RECORD_RE.finditer(index_text)}


def base_track_keys(names: list[str]) -> set[tuple[int, str]]:
    result: set[tuple[int, str]] = set()
    for name in names:
        match = TRACK_FILE_RE.search(name)
        if match:
            result.add((int(match.group("id")), "COMPLETE" if match.group("turnin") else "DETAIL"))
    return result


def source_for(cache: Path, quest_id: int, quest_type: str) -> Path | None:
    filename = f"{quest_type}.ogg"
    candidates = [
        cache / "ruRU" / "3.3.5a" / str(quest_id) / filename,
        cache / "legacy" / str(quest_id) / filename,
    ]
    return next((path for path in candidates if path.is_file()), None)


def lua_duration(row: dict[str, Any]) -> str:
    try:
        duration = float(row.get("duration_s", 0))
    except (TypeError, ValueError):
        duration = 0
    return f"{max(duration, 0.1):.1f}"


def lua_track(row: dict[str, Any]) -> str:
    return f'{{ d = {lua_duration(row)}, v = "CatQuest Extended", c = {{ x = {{}} }} }}'


def append_records(
    index_text: str,
    tracks: dict[tuple[int, str], dict[str, Any]],
    existing_ids: set[int],
) -> str:
    grouped: dict[int, dict[str, dict[str, Any]]] = defaultdict(dict)
    for (quest_id, quest_type), row in sorted(tracks.items()):
        grouped[quest_id][quest_type] = row

    lines: list[str] = []
    additions_by_existing_id = {quest_id: types for quest_id, types in grouped.items() if quest_id in existing_ids}
    additions_for_new_id = {quest_id: types for quest_id, types in grouped.items() if quest_id not in existing_ids}

    updated_lines: list[str] = []
    for line in index_text.splitlines(keepends=True):
        match = re.match(r"\s*\[(\d+)\]\s*=\s*\{", line)
        quest_id = int(match.group(1)) if match else None
        types = additions_by_existing_id.get(quest_id)
        if types:
            additions = []
            if "DETAIL" in types:
                additions.append(f"d = {lua_duration(types['DETAIL'])}, v = \"CatQuest Extended\", c = {{ x = {{}} }}")
            if "COMPLETE" in types:
                additions.append(f"t = {lua_track(types['COMPLETE'])}")
            position = line.rfind("}")
            if position < 0:
                raise ValueError(f"could not extend Index.lua record for quest {quest_id}")
            line = line[:position] + ", " + ", ".join(additions) + line[position:]
        updated_lines.append(line)

    for quest_id, types in additions_for_new_id.items():
        fields: list[str] = []
        if "DETAIL" in types:
            fields.append(f"d = {lua_duration(types['DETAIL'])}, v = \"CatQuest Extended\", c = {{ x = {{}} }}")
        if "COMPLETE" in types:
            fields.append(f"t = {lua_track(types['COMPLETE'])}")
        lines.append(f"    [{quest_id}] = {{ {', '.join(fields)} }},")

    updated_text = "".join(updated_lines)
    marker = "\n}"
    position = updated_text.rfind(marker)
    if position < 0:
        raise ValueError("could not find the end of CatQuestExtendedVoicePack.quests")
    return updated_text[:position] + "\n" + "\n".join(lines) + updated_text[position:]


def build(base: Path, cache: Path, export: Path, output: Path, metadata_root: Path) -> dict[str, Any]:
    ready = read_ready_rows(export)
    with zipfile.ZipFile(base) as source:
        index_name = next(
            name for name in source.namelist() if name.endswith("/Index.lua")
        )
        root = index_name[: -len("Index.lua")]
        index_text = source.read(index_name).decode("utf-8")
        existing_ids = base_quest_ids(index_text)
        existing_tracks = base_track_keys(source.namelist())
        selected: dict[tuple[int, str], tuple[dict[str, Any], Path]] = {}
        missing: list[str] = []
        for key, row in ready.items():
            quest_id, quest_type = key
            if quest_type not in {"DETAIL", "COMPLETE"}:
                continue
            path = source_for(cache, quest_id, quest_type)
            if path is None:
                missing.append(f"{quest_id} {quest_type}")
                continue
            if (quest_id, quest_type) in existing_tracks:
                continue
            # The export size is the source/generated asset size.  The
            # normalized OGG is loudness-normalized and re-encoded, so its
            # byte size is expected to differ.
            if path.stat().st_size <= 0:
                raise ValueError(f"normalized audio is empty: {quest_id} {quest_type}")
            selected[key] = (row, path)

        merged_index = append_records(
            index_text,
            {key: row for key, (row, _) in selected.items()},
            existing_ids,
        )
        output.parent.mkdir(parents=True, exist_ok=True)
        metadata = {
            f"{root}CatQuestExtended_Voices.toc": (metadata_root / "CatQuestExtended_Voices.toc").read_bytes(),
            f"{root}ATTRIBUTION.md": (metadata_root / "ATTRIBUTION.md").read_bytes(),
        }
        with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as target:
            for info in source.infolist():
                data = merged_index.encode("utf-8") if info.filename == index_name else metadata.get(info.filename, source.read(info))
                target.writestr(info, data)
            for (quest_id, quest_type), (_, path) in selected.items():
                suffix = "_t" if quest_type == "COMPLETE" else ""
                target.writestr(
                    f"{root}Sounds/q/{quest_id}{suffix}.ogg",
                    path.read_bytes(),
                    compress_type=zipfile.ZIP_DEFLATED,
                )

    return {
        "base_quest_ids": len(existing_ids),
        "added_tracks": len(selected),
        "added_quest_ids": len({quest_id for quest_id, _ in selected if quest_id not in existing_ids}),
        "missing_ready_tracks": len(missing),
        "missing_ready_samples": missing[:20],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--base", type=Path, default=DEFAULT_BASE)
    parser.add_argument("--cache", type=Path, default=DEFAULT_CACHE)
    parser.add_argument("--server-export", type=Path, default=DEFAULT_EXPORT)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--metadata-root", type=Path, default=DEFAULT_METADATA_ROOT)
    args = parser.parse_args()
    result = build(args.base, args.cache, args.server_export, args.output, args.metadata_root)
    result["output_bytes"] = args.output.stat().st_size
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
