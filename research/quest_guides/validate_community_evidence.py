"""Validate the manually curated community cross-check against local quest data."""

from __future__ import annotations

import csv
import argparse
import json
from collections import Counter
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
REPORT = Path(__file__).resolve().parent / "community_validation.json"
RECALCULATED = Path(__file__).resolve().parent / "recalculated_quest_guides.json"
def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--popularity-csv",
        type=Path,
        required=True,
        help="local popularity CSV; it is intentionally not stored in the public repository",
    )
    args = parser.parse_args()
    if not args.popularity_csv.is_file():
        raise SystemExit(f"popularity CSV not found: {args.popularity_csv}")

    report = json.loads(REPORT.read_text(encoding="utf-8"))
    recalculated = json.loads(RECALCULATED.read_text(encoding="utf-8"))
    zones = {int(zone["zone"]): zone for zone in recalculated["zones"]}
    with args.popularity_csv.open(encoding="utf-8", newline="") as handle:
        popularity = {int(row["quest_id"]): int(row["pop"]) for row in csv.DictReader(handle)}

    verdicts = report["verdicts"]
    for entry in verdicts:
        zone_id = int(entry["zone"])
        trust_weight = float(entry["pop_trust_weight"])
        if not 0.0 <= trust_weight <= 1.0:
            raise ValueError(f"Invalid pop_trust_weight for zone {zone_id}: {trust_weight}")
        if zone_id not in zones:
            raise ValueError(f"Unknown zone in community report: {zone_id}")

        zone = zones[zone_id]
        expected_ids = {int(quest_id) for quest_id in zone["quests"]}
        actual_ids = {int(quest_id) for quest_id in entry["quest_ids"]}
        if not actual_ids.issubset(expected_ids):
            missing = sorted(actual_ids - expected_ids)
            raise ValueError(f"Zone {zone_id} contains quests outside the selected chain: {missing}")

        if abs(float(entry["chain_pop_score"]) - float(zone["pop_score"])) > 0.02:
            raise ValueError(f"Stale chain Pop score for zone {zone_id}")

        max_pop = max(popularity.get(quest_id, 0) for quest_id in actual_ids)
        if int(entry["max_raw_pop"]) != max_pop:
            raise ValueError(f"Stale max raw Pop for zone {zone_id}: {entry['max_raw_pop']} != {max_pop}")

    counts = Counter(entry["verdict"] for entry in verdicts)
    print(f"validated={len(verdicts)}")
    print(f"manual_pop_weights={len(verdicts)}")
    for verdict, count in sorted(counts.items()):
        print(f"{verdict}={count}")


if __name__ == "__main__":
    main()
