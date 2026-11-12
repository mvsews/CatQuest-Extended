"""Measure technical quest complexity from the local TrinityCore database dump.

This is intentionally evidence-based and conservative. It counts direct
quest-linked SmartAI rows, area triggers and their scripts, conditions, and
multi-objective structure. It does not infer complexity from popularity or
from a quest title.
"""

from __future__ import annotations

import json
import os
import re
import sqlite3
from collections import defaultdict
from pathlib import Path
from typing import Iterator


ROOT = Path(__file__).resolve().parents[2]
SQL_DUMP = Path(os.environ.get("CATQUEST_TRINITY_SQL", "TDB_full_world_335.sql"))
QUEST_DB = Path(os.environ.get("CATQUEST_QUEST_DB", "quests.sqlite3"))
GUIDE = ROOT / "CatQuest" / "QuestGuideData.lua"
OUTPUT = Path(__file__).resolve().parent / "technical_complexity.json"

ENTRY_RE = re.compile(
    r"^\s*\[(?P<zone>\d+)\]\s*=\s*\{\s*\n.*?"
    r"\s*quests\s*=\s*\{\s*(?P<quests>[^}]*)\},\s*\n\s*\},",
    re.MULTILINE | re.DOTALL,
)
QUEST_EVENTS = {19, 20, 47, 48, 49, 50, 51}
QUEST_ACTIONS = {6, 7, 15, 26}
QUEST_CONDITION_TYPES = {8, 9, 14, 28, 47, 48}


def parse_values(payload: str) -> Iterator[list[str]]:
    """Yield SQL VALUES tuples without requiring a MySQL client."""
    index = 0
    length = len(payload)
    while index < length:
        if payload[index] != "(":
            index += 1
            continue
        index += 1
        row: list[str] = []
        token: list[str] = []
        quoted = False
        escaped = False
        while index < length:
            char = payload[index]
            if quoted:
                token.append(char)
                if escaped:
                    escaped = False
                elif char == "\\":
                    escaped = True
                elif char == "'":
                    if index + 1 < length and payload[index + 1] == "'":
                        token.append(payload[index + 1])
                        index += 1
                    else:
                        quoted = False
            elif char == "'":
                quoted = True
                token.append(char)
            elif char == ",":
                row.append("".join(token).strip())
                token = []
            elif char == ")":
                row.append("".join(token).strip())
                yield row
                break
            else:
                token.append(char)
            index += 1
        index += 1


def sql_int(value: str) -> int:
    value = value.strip()
    if value.upper() == "NULL" or value.startswith("'"):
        return 0
    try:
        return int(value)
    except ValueError:
        match = re.search(r"-?\d+", value)
        return int(match.group()) if match else 0


def rows_for(table: str) -> Iterator[list[str]]:
    marker = "INSERT INTO " + chr(96) + table + chr(96) + " VALUES"
    with SQL_DUMP.open(encoding="utf-8", errors="ignore") as handle:
        for line in handle:
            if marker in line:
                yield from parse_values(line.split("VALUES", 1)[1].rstrip(";\n"))


def guide_quest_ids() -> set[int]:
    text = GUIDE.read_text(encoding="utf-8")
    values: set[int] = set()
    for match in ENTRY_RE.finditer(text):
        values.update(int(value) for value in re.findall(r"\d+", match.group("quests")))
    if not values:
        raise SystemExit("no quest IDs found in QuestGuideData.lua")
    return values


def all_quest_ids() -> set[int]:
    with sqlite3.connect(QUEST_DB) as connection:
        return {
            int(row[0])
            for row in connection.execute(
                "select quest_id from quests where core = 'trinitycore'"
            )
        }


def empty_record() -> dict[str, object]:
    return {
        "smart_rows": 0,
        "smart_containers": set(),
        "smart_links": 0,
        "smart_event_types": set(),
        "smart_action_types": set(),
        "condition_rows": 0,
        "area_triggers": set(),
        "area_trigger_scripts": set(),
        "objective_slots": 0,
        "addon_features": 0,
    }


def analyze() -> tuple[dict[int, dict[str, object]], float, int]:
    quest_ids = all_quest_ids()
    selected = guide_quest_ids()
    records: defaultdict[int, dict[str, object]] = defaultdict(empty_record)

    trigger_to_quests: defaultdict[int, set[int]] = defaultdict(set)
    for row in rows_for("areatrigger_involvedrelation"):
        if len(row) >= 2 and sql_int(row[1]) in quest_ids:
            trigger_to_quests[sql_int(row[1])].add(sql_int(row[0]))
    trigger_scripts: dict[int, str] = {}
    for row in rows_for("areatrigger_scripts"):
        if len(row) >= 2:
            trigger_scripts[sql_int(row[0])] = row[1].strip("'")
    for quest_id, triggers in trigger_to_quests.items():
        records[quest_id]["area_triggers"].update(triggers)
        records[quest_id]["area_trigger_scripts"].update(
            trigger_scripts[trigger] for trigger in triggers if trigger in trigger_scripts
        )

    for row in rows_for("smart_scripts"):
        if len(row) < 21:
            continue
        event_type = sql_int(row[4])
        event_quest = sql_int(row[8])
        action_type = sql_int(row[13])
        action_quest = sql_int(row[14])
        references: set[int] = set()
        if event_type in QUEST_EVENTS and event_quest in quest_ids:
            references.add(event_quest)
        if action_type in QUEST_ACTIONS and action_quest in quest_ids:
            references.add(action_quest)
        for quest_id in references:
            record = records[quest_id]
            record["smart_rows"] = int(record["smart_rows"]) + 1
            record["smart_containers"].add((sql_int(row[0]), sql_int(row[1])))
            record["smart_event_types"].add(event_type)
            record["smart_action_types"].add(action_type)
            if sql_int(row[3]) > 0:
                record["smart_links"] = int(record["smart_links"]) + 1

    for row in rows_for("conditions"):
        if len(row) < 10:
            continue
        source_type = sql_int(row[0])
        source_entry = sql_int(row[2])
        condition_type = sql_int(row[5])
        values = {sql_int(row[7]), sql_int(row[8]), sql_int(row[9])}
        references: set[int] = set()
        if source_type == 19 and source_entry in quest_ids:
            references.add(source_entry)
        if source_type == 22:
            references.update(values.intersection(quest_ids) if condition_type in QUEST_CONDITION_TYPES else ())
        for quest_id in references:
            records[quest_id]["condition_rows"] = int(records[quest_id]["condition_rows"]) + 1

    for row in rows_for("quest_template_addon"):
        if len(row) < 18:
            continue
        quest_id = sql_int(row[0])
        if quest_id not in quest_ids:
            continue
        addon_values = [sql_int(value) for value in row]
        feature_indices = (3, 4, 5, 6, 7, 8, 10, 11, 12, 13, 14, 15, 16, 17)
        records[quest_id]["addon_features"] = sum(
            1 for index in feature_indices if addon_values[index] != 0
        )

    # The local quest catalog contains objective text but not normalized
    # objective columns. Count objective sentences as a safe lower bound.
    with sqlite3.connect(QUEST_DB) as connection:
        for quest_id, objectives in connection.execute(
            "select quest_id, objectives from quests where core = 'trinitycore'"
        ):
            if int(quest_id) not in quest_ids:
                continue
            text = (objectives or "").strip()
            records[int(quest_id)]["objective_slots"] = (
                len([part for part in re.split(r"[.;\n]+", text) if part.strip()])
                if text
                else 0
            )

    raw_values: list[float] = []
    for record in records.values():
        record["smart_container_count"] = len(record.pop("smart_containers"))
        record["area_trigger_count"] = len(record.pop("area_triggers"))
        record["area_trigger_script_count"] = len(record.pop("area_trigger_scripts"))
        record["smart_event_type_count"] = len(record.pop("smart_event_types"))
        record["smart_action_type_count"] = len(record.pop("smart_action_types"))
        raw = (
            int(record["smart_rows"]) * 4
            + int(record["smart_container_count"]) * 2
            + int(record["smart_links"]) * 2
            + int(record["condition_rows"])
            + int(record["area_trigger_count"]) * 5
            + int(record["area_trigger_script_count"]) * 7
            + int(record["objective_slots"]) * 0.5
            + int(record["addon_features"]) * 2
        )
        record["raw"] = round(raw, 2)
        raw_values.append(raw)
    p99_index = min(len(raw_values) - 1, max(0, int(len(raw_values) * 0.99) - 1))
    p99 = sorted(raw_values)[p99_index] if raw_values else 1.0
    return dict(records), float(p99 or 1.0), len(selected)


def main() -> None:
    records, p99, selected_count = analyze()
    output = {
        "source": "TrinityCore TDB 3.3.5a (local input; source file not included)",
        "selected_chain_quests": selected_count,
        "normalization": "100 * log1p(raw) / log1p(P99), clamped to 100",
        "raw_p99": p99,
        "quests": {str(quest_id): record for quest_id, record in records.items()},
    }
    OUTPUT.write_text(
        json.dumps(output, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    nonzero = sum(1 for record in records.values() if record["raw"])
    print(f"analyzed {len(records)} quests with evidence; {nonzero} non-zero; raw P99={p99:g}")


if __name__ == "__main__":
    main()
