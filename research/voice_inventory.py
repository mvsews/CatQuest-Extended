#!/usr/bin/env python3
"""Build a complete, audio-free inventory of CatQuest voice tracks.

The report joins four sources:

* the physical OGG files and Index.lua inside a voice-pack archive;
* the read-only quest catalog (AzerothCore or TrinityCore);
* the derived public progress database;
* an optional sanitized export of production voice.sqlite3.

It never opens or copies audio data into the report. Server exports must contain
track metadata only; quest text, accounts, telemetry, and server paths are not
needed for this inventory.

Example:

    python research/voice_inventory.py \
      --pack dist/CatQuestExtended_Voices-1.3.0-full.zip \
      --server-export .tmp/production-voice-export.json \
      --output docs/voice/track-inventory.json \
      --markdown docs/voice/INVENTORY.md
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
import sqlite3
import zipfile
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_PACK = ROOT / "dist" / "CatQuestExtended_Voices-1.3.0-full.zip"
DEFAULT_QUEST_DB = ROOT / "backend" / "quest_db" / "quests.sqlite3"
DEFAULT_PROGRESS_DB = ROOT / "backend" / "progress.sqlite3"
DEFAULT_SERVER_EXPORT = ROOT / ".tmp" / "production-voice-export.json"
DEFAULT_OUTPUT = ROOT / "docs" / "voice" / "track-inventory.json"
DEFAULT_MARKDOWN = ROOT / "docs" / "voice" / "INVENTORY.md"

TRACK_RE = re.compile(
    r"^(?P<id>\d+)(?P<turnin>_t)?(?:_n(?P<npc>\d+))?(?P<gender>_[mf])?\.ogg$",
    re.IGNORECASE,
)
RECORD_RE = re.compile(r"^\s*\[(?P<id>\d+)\]\s*=\s*\{")
VOICE_RE = re.compile(r'\bv\s*=\s*"((?:\\.|[^"\\])*)"')
TYPE_NAMES = ("DETAIL", "COMPLETE")


def clean_text(value: Any) -> Any:
    """Replace malformed surrogate characters from old DB exports."""
    if isinstance(value, str):
        return value.encode("utf-8", "replace").decode("utf-8")
    if isinstance(value, list):
        return [clean_text(item) for item in value]
    if isinstance(value, dict):
        return {str(key): clean_text(item) for key, item in value.items()}
    return value


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(8 * 1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def parse_voice_index(data: str) -> dict[int, dict[str, Any]]:
    """Read the stable one-record-per-line metadata emitted by CatQuest packs."""
    result: dict[int, dict[str, Any]] = {}
    for line in data.splitlines():
        match = RECORD_RE.match(line)
        if not match:
            continue
        quest_id = int(match.group("id"))
        turnin = re.search(r"\bt\s*=\s*\{", line)
        detail_part = line[: turnin.start()] if turnin else line
        complete_part = line[turnin.start() :] if turnin else ""
        detail_voice = VOICE_RE.search(detail_part)
        complete_voice = VOICE_RE.search(complete_part)
        result[quest_id] = {
            "detail_voice": detail_voice.group(1) if detail_voice else None,
            "complete_voice": complete_voice.group(1) if complete_voice else None,
        }
    return result


def read_pack(path: Path) -> tuple[dict[int, dict[str, Any]], dict[str, Any]]:
    """Inventory OGG names and Index.lua metadata without extracting audio."""
    tracks: dict[int, list[dict[str, Any]]] = defaultdict(list)
    index_meta: dict[int, dict[str, Any]] = {}
    root_name = ""
    with zipfile.ZipFile(path) as archive:
        index_name = next((name for name in archive.namelist() if name.endswith("/Index.lua")), "")
        if not index_name:
            raise ValueError("voice-pack has no Index.lua")
        root_name = index_name.split("/", 1)[0]
        index_meta = parse_voice_index(archive.read(index_name).decode("utf-8", "replace"))
        for info in archive.infolist():
            if info.is_dir() or not info.filename.lower().endswith(".ogg"):
                continue
            if not info.filename.startswith(root_name + "/Sounds/q/"):
                continue
            filename = info.filename.rsplit("/", 1)[-1]
            match = TRACK_RE.match(filename)
            if not match:
                continue
            quest_id = int(match.group("id"))
            track_type = "COMPLETE" if match.group("turnin") else "DETAIL"
            gender = match.group("gender")
            voice = index_meta.get(quest_id, {}).get(
                "complete_voice" if track_type == "COMPLETE" else "detail_voice"
            )
            tracks[quest_id].append({
                "file": info.filename,
                "type": track_type,
                "gender": gender[1:] if gender else None,
                "npc_id": int(match.group("npc")) if match.group("npc") else None,
                "voice": voice,
                "size_bytes": info.file_size,
            })

    all_tracks = [track for rows in tracks.values() for track in rows]
    type_counts = Counter(track["type"] for track in all_tracks)
    voice_counts = Counter(track["voice"] or "unknown" for track in all_tracks)
    return tracks, {
        "archive": path.name,
        "root": root_name,
        "size_bytes": path.stat().st_size,
        "sha256": sha256(path),
        "track_files": len(all_tracks),
        "quest_ids": len(tracks),
        "detail_files": type_counts["DETAIL"],
        "complete_files": type_counts["COMPLETE"],
        "gender_variant_files": sum(bool(track["gender"]) for track in all_tracks),
        "npc_variant_files": sum(bool(track["npc_id"]) for track in all_tracks),
        "voices": [
            {"id": voice, "tracks": count}
            for voice, count in sorted(voice_counts.items(), key=lambda item: (-item[1], item[0]))
        ],
    }


def track_signatures(tracks: dict[int, list[dict[str, Any]]]) -> set[tuple[int, str, str | None, int | None]]:
    return {
        (quest_id, track["type"], track.get("gender"), track.get("npc_id"))
        for quest_id, rows in tracks.items()
        for track in rows
    }


def compare_packs(
    current: dict[int, list[dict[str, Any]]],
    upstream: dict[int, list[dict[str, Any]]],
) -> dict[str, Any]:
    current_signatures = track_signatures(current)
    upstream_signatures = track_signatures(upstream)
    current_ids = set(current)
    upstream_ids = set(upstream)
    added = upstream_signatures - current_signatures
    removed = current_signatures - upstream_signatures
    return {
        "current_track_signatures": len(current_signatures),
        "upstream_track_signatures": len(upstream_signatures),
        "added_track_signatures": len(added),
        "removed_track_signatures": len(removed),
        "common_track_signatures": len(current_signatures & upstream_signatures),
        "added_quest_ids": len(upstream_ids - current_ids),
        "removed_quest_ids": len(current_ids - upstream_ids),
        "added_quest_id_sample": sorted(upstream_ids - current_ids)[:100],
        "removed_quest_id_sample": sorted(current_ids - upstream_ids)[:100],
    }


def load_catalog(path: Path, core: str) -> tuple[dict[int, dict[str, Any]], dict[str, int]]:
    db = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    db.row_factory = sqlite3.Row
    try:
        rows = db.execute(
            "SELECT core, quest_id, title, zone_id, flags, special_flags, prev_quest_id, next_quest_id "
            "FROM quests WHERE core = ? ORDER BY quest_id",
            (core,),
        ).fetchall()
        locale_rows = db.execute(
            "SELECT quest_id, locale, title FROM quest_locales "
            "WHERE core = ? AND locale IN ('ruRU', 'enUS')",
            (core,),
        ).fetchall()
    finally:
        db.close()
    locales: dict[int, dict[str, str]] = defaultdict(dict)
    for row in locale_rows:
        locales[int(row["quest_id"])] [row["locale"]] = clean_text(row["title"] or "")
    catalog = {
        int(row["quest_id"]): {
            "core": row["core"],
            "quest_id": int(row["quest_id"]),
            "title": clean_text(row["title"] or ""),
            "titles": locales.get(int(row["quest_id"]), {}),
            "zone_id": int(row["zone_id"] or 0),
            "flags": int(row["flags"] or 0),
            "special_flags": int(row["special_flags"] or 0),
            "prev_quest_id": int(row["prev_quest_id"] or 0),
            "next_quest_id": int(row["next_quest_id"] or 0),
        }
        for row in rows
    }
    return catalog, {"core": core, "quests": len(catalog)}


def load_progress(path: Path, core: str) -> dict[int, dict[str, Any]]:
    if not path.is_file():
        return {}
    db = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    db.row_factory = sqlite3.Row
    try:
        rows = db.execute("SELECT * FROM quest_progress WHERE core = ?", (core,)).fetchall()
    finally:
        db.close()
    result = {}
    for row in rows:
        result[int(row["quest_id"])] = {
            "sector_id": row["sector_id"],
            "sector_en": row["sector_en"],
            "sector_ru": row["sector_ru"],
            "zone_id": int(row["zone_id"] or 0),
            "zone_en": row["zone_en"],
            "category": row["category"],
            "story_line": int(row["story_line"] or 0),
            "status": row["status"],
            "priority_score": float(row["priority_score"] or 0),
            "voiced_locales": [
                item for item in str(row["voiced_locales"] or "").split(",") if item
            ],
        }
    return result


def load_server_export(path: Path | None) -> dict[int, list[dict[str, Any]]]:
    if not path or not path.is_file():
        return defaultdict(list)
    payload = json.loads(path.read_text(encoding="utf-8"))
    rows = payload.get("rows", []) if isinstance(payload, dict) else []
    result: dict[int, list[dict[str, Any]]] = defaultdict(list)
    keep = {
        "quest_type", "locale", "client_version", "title", "source", "text_hash",
        "updated_at", "tts_model", "tts_voice", "translate_model", "generated_at",
        "npc_id", "npc_name", "gender", "duration_s", "size_bytes", "track_status", "note",
    }
    for raw in rows:
        if not isinstance(raw, dict) or not str(raw.get("quest_id", "")).isdigit():
            continue
        quest_id = int(raw["quest_id"])
        result[quest_id].append({key: clean_text(raw.get(key)) for key in keep if key in raw})
    return result


def availability(tracks: list[dict[str, Any]]) -> str:
    types = {track["type"] for track in tracks}
    if types == {"DETAIL", "COMPLETE"}:
        return "detail-and-complete"
    if types == {"DETAIL"}:
        return "detail-only"
    if types == {"COMPLETE"}:
        return "complete-only"
    return "none"


def build_report(
    pack_tracks: dict[int, list[dict[str, Any]]],
    pack_info: dict[str, Any],
    catalog: dict[int, dict[str, Any]],
    catalog_info: dict[str, int],
    progress: dict[int, dict[str, Any]],
    server_tracks: dict[int, list[dict[str, Any]]],
    core: str,
    upstream_tracks: dict[int, list[dict[str, Any]]] | None = None,
    upstream_info: dict[str, Any] | None = None,
) -> dict[str, Any]:
    all_ids = sorted(set(pack_tracks) | set(catalog) | set(progress) | set(server_tracks))
    records = []
    for quest_id in all_ids:
        original = pack_tracks.get(quest_id, [])
        generated = server_tracks.get(quest_id, [])
        catalog_row = catalog.get(quest_id)
        progress_row = progress.get(quest_id)
        record = {
            "quest_id": quest_id,
            "catalog": catalog_row,
            "progress": progress_row,
            "original_pack": {
                "availability": availability(original),
                "track_count": len(original),
                "tracks": sorted(original, key=lambda item: (item["type"], item["file"])),
            },
            "server_tracks": sorted(
                generated,
                key=lambda item: (str(item.get("locale", "")), str(item.get("quest_type", ""))),
            ),
            "sync": {
                "in_catalog": catalog_row is not None,
                "in_original_pack": bool(original),
                "has_server_track": any(item.get("track_status") == "ready" for item in generated),
                "progress_says_voiced": bool(progress_row and progress_row.get("status") == "voiced"),
            },
        }
        record["sync"]["effective_audio"] = (
            bool(original)
            or any(item.get("track_status") == "ready" for item in generated)
        )
        record["sync"]["progress_matches_original_pack"] = (
            not catalog_row
            or bool(original) == bool(progress_row and progress_row.get("status") == "voiced")
        )
        record["sync"]["progress_matches_effective_audio"] = (
            not catalog_row
            or record["sync"]["effective_audio"] == bool(progress_row and progress_row.get("status") == "voiced")
        )
        records.append(record)

    catalog_ids = set(catalog)
    pack_ids = set(pack_tracks)
    progress_voiced = {quest_id for quest_id, row in progress.items() if row.get("status") == "voiced"}
    server_ready = [
        item
        for rows in server_tracks.values()
        for item in rows
        if item.get("track_status") == "ready"
    ]
    by_locale = Counter(str(item.get("locale") or "unknown") for item in server_ready)
    by_type = Counter(str(item.get("quest_type") or "unknown") for item in server_ready)
    mismatches = sorted(
        quest_id
        for quest_id in catalog_ids
        if (quest_id in pack_ids) != (quest_id in progress_voiced)
    )
    server_ready_ids = {
        quest_id
        for quest_id, rows in server_tracks.items()
        if any(item.get("track_status") == "ready" for item in rows)
    }
    effective_ids = pack_ids | server_ready_ids
    effective_mismatches = sorted(
        quest_id
        for quest_id in catalog_ids
        if (quest_id in effective_ids) != (quest_id in progress_voiced)
    )
    report = {
        "schema_version": 1,
        "generated_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
        "content_version": "3.3.5a",
        "catalog": catalog_info,
        "pack": pack_info,
        "upstream": (
            {**(upstream_info or {}), "comparison": compare_packs(pack_tracks, upstream_tracks)}
            if upstream_tracks is not None
            else None
        ),
        "server": {
            "exported_rows": sum(len(rows) for rows in server_tracks.values()),
            "ready_rows": len(server_ready),
            "ready_quest_ids": len({int(item["quest_id"]) for item in []}),
            "by_locale": dict(sorted(by_locale.items())),
            "by_type": dict(sorted(by_type.items())),
        },
        "sync": {
            "catalog_quest_ids": len(catalog_ids),
            "original_pack_quest_ids": len(pack_ids),
            "original_pack_ids_in_catalog": len(pack_ids & catalog_ids),
            "original_pack_ids_outside_catalog": len(pack_ids - catalog_ids),
            "server_ready_quest_ids": len(server_ready_ids),
            "server_only_ids_in_catalog": len((server_ready_ids - pack_ids) & catalog_ids),
            "effective_audio_ids_in_catalog": len(effective_ids & catalog_ids),
            "catalog_ids_without_effective_audio": len(catalog_ids - effective_ids),
            "progress_voiced_ids": len(progress_voiced),
            "progress_original_pack_mismatches": len(mismatches),
            "progress_original_pack_mismatch_ids": mismatches,
            "progress_effective_audio_mismatches": len(effective_mismatches),
            "progress_effective_audio_mismatch_ids": effective_mismatches,
        },
        "records": records,
    }
    report["server"]["ready_quest_ids"] = len({
        quest_id
        for quest_id, rows in server_tracks.items()
        if any(item.get("track_status") == "ready" for item in rows)
    })
    return clean_text(report)


def markdown_report(report: dict[str, Any]) -> str:
    pack = report["pack"]
    server = report["server"]
    sync = report["sync"]
    voices = pack.get("voices", [])[:20]
    lines = [
        "# Voice track inventory",
        "",
        f"Generated: `{report['generated_at']}`",
        f"Content profile: `{report['content_version']}`",
        f"Archive: `{pack['archive']}`",
        f"SHA-256: `{pack['sha256']}`",
        "",
        "## Physical voice-pack coverage",
        "",
        f"- OGG files: **{pack['track_files']:,}**",
        f"- Quest IDs in the archive: **{pack['quest_ids']:,}**",
        f"- Detail tracks: **{pack['detail_files']:,}**",
        f"- Turn-in tracks: **{pack['complete_files']:,}**",
        f"- Gender variants: **{pack['gender_variant_files']:,}**",
        f"- NPC-specific variants: **{pack['npc_variant_files']:,}**",
        f"- Archive size: **{pack['size_bytes']:,} bytes**",
        "",
    ]
    upstream = report.get("upstream")
    if upstream:
        comparison = upstream.get("comparison", {})
        lines.extend([
            "## Upstream CatQuest Voices check",
            "",
            f"- Release: **{upstream.get('version', 'unknown')}**",
            f"- CurseForge file ID: `{upstream.get('file_id', 'unknown')}`",
            f"- Upstream archive: `{upstream.get('archive', 'unknown')}`",
            f"- Upstream size: **{upstream.get('size_bytes', 0):,} bytes**",
            f"- Upstream OGG files: **{upstream.get('track_files', 0):,}**",
            f"- Upstream quest IDs: **{upstream.get('quest_ids', 0):,}**",
            f"- Upstream-only track signatures: **{comparison.get('added_track_signatures', 0):,}**",
            f"- Upstream-only quest IDs: **{comparison.get('added_quest_ids', 0):,}**",
            f"- Published-only track signatures (including community tracks): **{comparison.get('removed_track_signatures', 0):,}**",
            "",
        ])
    lines.extend([
        "## Sync with the quest catalog",
        "",
        f"- Catalog quests (`{report['catalog']['core']}`): **{sync['catalog_quest_ids']:,}**",
        f"- Pack quest IDs found in catalog: **{sync['original_pack_ids_in_catalog']:,}**",
        f"- Pack IDs outside catalog: **{sync['original_pack_ids_outside_catalog']:,}**",
        f"- Server-generated quest IDs: **{sync['server_ready_quest_ids']:,}**",
        f"- Server-only IDs in catalog: **{sync['server_only_ids_in_catalog']:,}**",
        f"- Effective audio IDs in catalog (pack + server): **{sync['effective_audio_ids_in_catalog']:,}**",
        f"- Catalog quests without effective audio: **{sync['catalog_ids_without_effective_audio']:,}**",
        f"- Progress snapshot marked voiced: **{sync['progress_voiced_ids']:,}**",
        f"- Progress/original-pack mismatches: **{sync['progress_original_pack_mismatches']:,}**",
        f"- Progress/effective-audio mismatches: **{sync['progress_effective_audio_mismatches']:,}**",
        "",
        "The effective-audio check combines the original local pack and ready "
        "server-generated tracks. This is the number that should drive public coverage.",
        "",
        "## Server-generated tracks",
        "",
        f"- Exported rows: **{server['exported_rows']:,}**",
        f"- Ready rows: **{server['ready_rows']:,}**",
        f"- Quest IDs with a ready server track: **{server['ready_quest_ids']:,}**",
        f"- By locale: `{json.dumps(server['by_locale'], ensure_ascii=False, sort_keys=True)}`",
        f"- By type: `{json.dumps(server['by_type'], ensure_ascii=False, sort_keys=True)}`",
        "",
        "## Most common original voices",
        "",
        "| Voice ID | Track files |",
        "| --- | ---: |",
    ])
    lines.extend(f"| `{row['id']}` | {row['tracks']:,} |" for row in voices)
    lines.extend([
        "",
        "The detailed per-quest and per-file inventory is in "
        "[`track-inventory.json`](track-inventory.json). It contains metadata only; "
        "no audio, quest text, account data, or server paths are published.",
        "",
    ])
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--pack", type=Path, default=DEFAULT_PACK)
    parser.add_argument("--quest-db", type=Path, default=DEFAULT_QUEST_DB)
    parser.add_argument("--progress-db", type=Path, default=DEFAULT_PROGRESS_DB)
    parser.add_argument("--server-export", type=Path, default=DEFAULT_SERVER_EXPORT)
    parser.add_argument("--upstream-pack", type=Path)
    parser.add_argument("--upstream-version", default="")
    parser.add_argument("--upstream-file-id", type=int)
    parser.add_argument("--upstream-last-modified", default="")
    parser.add_argument("--core", default="azerothcore")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--markdown", type=Path, default=DEFAULT_MARKDOWN)
    args = parser.parse_args()

    pack_tracks, pack_info = read_pack(args.pack)
    catalog, catalog_info = load_catalog(args.quest_db, args.core)
    progress = load_progress(args.progress_db, args.core)
    server_tracks = load_server_export(args.server_export)
    upstream_tracks = None
    upstream_info = None
    if args.upstream_pack:
        upstream_tracks, upstream_info = read_pack(args.upstream_pack)
        upstream_info.update({
            "version": args.upstream_version or None,
            "file_id": args.upstream_file_id,
            "last_modified": args.upstream_last_modified or None,
        })
    report = build_report(
        pack_tracks, pack_info, catalog, catalog_info, progress, server_tracks, args.core,
        upstream_tracks, upstream_info,
    )

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    args.markdown.parent.mkdir(parents=True, exist_ok=True)
    args.markdown.write_text(markdown_report(report), encoding="utf-8")

    print(json.dumps({
        "output": str(args.output),
        "markdown": str(args.markdown),
        "pack_tracks": report["pack"]["track_files"],
        "pack_quest_ids": report["pack"]["quest_ids"],
        "catalog_quests": report["sync"]["catalog_quest_ids"],
        "progress_effective_audio_mismatches": report["sync"]["progress_effective_audio_mismatches"],
        "server_ready_rows": report["server"]["ready_rows"],
    }, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
