"""Decode the compact Wowhead Pop snapshot captured by the browser.

The compact file stores sorted quest IDs as base-36 deltas and Pop values as
base-36 integers. Keeping this small source artifact makes the collection
reproducible without re-crawling Wowhead every time.
"""

from __future__ import annotations

import csv
import argparse
from datetime import date
from pathlib import Path


ROOT = Path(__file__).resolve().parent
DEFAULT_COMPACT = ROOT / "wowhead_popularity.compact"
DEFAULT_OUTPUT = ROOT / "wowhead_popularity.csv"
SOURCE_URL = "https://www.wowhead.com/wotlk/quests"


def decode(text: str) -> list[tuple[int, int]]:
    values: list[tuple[int, int]] = []
    quest_id = 0
    chunks = text.splitlines()
    # The browser output was copied in fixed-width slices. A few slice
    # boundaries split a token; repair only those known boundary artifacts
    # before removing line whitespace.
    if chunks and chunks[0].endswith(":"):
        chunks[0] = chunks[0][:-1]
    for index in (2, 3, 4, 5, 6, 8, 9, 10, 11):
        if index < len(chunks) and chunks[index].startswith(":"):
            chunks[index] = chunks[index][1:]
    for item in "".join(chunks).split(","):
        if not item:
            continue
        delta_text, pop_text = item.split(":", 1)
        quest_id += int(delta_text, 36)
        values.append((quest_id, int(pop_text, 36)))
    return values


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--input",
        dest="input_path",
        type=Path,
        default=DEFAULT_COMPACT,
        help="local snapshot file; it is intentionally not stored in the public repository",
    )
    parser.add_argument(
        "--output",
        dest="output_path",
        type=Path,
        default=DEFAULT_OUTPUT,
        help="CSV path to create",
    )
    args = parser.parse_args()
    if not args.input_path.is_file():
        raise SystemExit(
            "local popularity snapshot is not included; pass --input with a permitted local file"
        )

    values = decode(args.input_path.read_text(encoding="utf-8"))
    if not values:
        raise SystemExit("snapshot is empty")
    if any(left[0] >= right[0] for left, right in zip(values, values[1:])):
        raise SystemExit("quest IDs are not strictly increasing")

    snapshot_date = date(2026, 11, 10).isoformat()
    with args.output_path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(["quest_id", "pop", "source_url", "snapshot_date", "notes"])
        for quest_id, popularity in values:
            writer.writerow(
                [quest_id, popularity, SOURCE_URL, snapshot_date, "browser zone-list collection"]
            )
    print(f"decoded {len(values)} quests to {args.output_path}")


if __name__ == "__main__":
    main()
