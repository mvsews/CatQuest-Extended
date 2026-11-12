"""Print the next high-Pop quests for manual community review.

This intentionally does not fetch anything or change scores. A human reviews
the queue, adds a verdict and pop_trust_weight to community_validation.json,
then runs recalculate_quest_guides.py.
"""

from __future__ import annotations

import argparse
import csv
import json
import sqlite3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
GUIDE_REPORT = Path(__file__).resolve().parent / "recalculated_quest_guides.json"
COMMUNITY_REPORT = Path(__file__).resolve().parent / "community_validation.json"
QUEST_DB = ROOT / "backend" / "quest_db" / "quests.sqlite3"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--limit", type=int, default=20)
    parser.add_argument(
        "--popularity-csv",
        type=Path,
        required=True,
        help="local popularity CSV; it is intentionally not stored in the public repository",
    )
    args = parser.parse_args()
    if not args.popularity_csv.is_file():
        raise SystemExit(f"popularity CSV not found: {args.popularity_csv}")

    guide = json.loads(GUIDE_REPORT.read_text(encoding="utf-8"))
    community = json.loads(COMMUNITY_REPORT.read_text(encoding="utf-8"))
    reviewed = {int(entry["zone"]) for entry in community.get("verdicts", [])}
    with args.popularity_csv.open(encoding="utf-8", newline="") as handle:
        popularity = {int(row["quest_id"]): int(row["pop"]) for row in csv.DictReader(handle)}
    with sqlite3.connect(QUEST_DB) as connection:
        titles = dict(connection.execute("select quest_id, title from quests where core = 'trinitycore'"))

    queue = []
    for zone in guide["zones"]:
        if int(zone["zone"]) in reviewed:
            continue
        for quest_id in zone["quests"]:
            if int(quest_id) in popularity:
                queue.append(
                    (
                        popularity[int(quest_id)],
                        int(zone["zone"]),
                        int(quest_id),
                        titles.get(int(quest_id), ""),
                        zone["pop_score"],
                        zone["base_score"],
                        zone["technical_score"],
                    )
                )

    print("raw_pop\tzone\tquest_id\ttitle\tchain_pop\tbase\ttech")
    for row in sorted(queue, reverse=True)[: max(0, args.limit)]:
        print("\t".join(str(value) for value in row))


if __name__ == "__main__":
    main()
