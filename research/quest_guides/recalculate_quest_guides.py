"""Recalculate quest-chain distinctiveness with a bounded Wowhead Pop signal.

The existing guide score remains the primary research judgment. Wowhead Pop is
an auxiliary signal with an explicit 20% weight:

    final = round(
        0.80 * base_distinctiveness
        + 0.20 * effective_pop_score
        + 0.10 * chain_technical_score
    )

Pop is log-normalized against the 99th percentile of the collected snapshot,
so one exceptionally popular quest cannot dominate a whole chain.
"""

from __future__ import annotations

import csv
import argparse
import json
import math
import re
from datetime import date
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / "CatQuest" / "QuestGuideData.lua"
TECH_JSON = Path(__file__).resolve().parent / "technical_complexity.json"
COMMUNITY_JSON = Path(__file__).resolve().parent / "community_validation.json"
REPORT = Path(__file__).resolve().parent / "recalculated_quest_guides.json"
REPORT_MD = Path(__file__).resolve().parent / "recalculated_quest_guides.ru.md"
BASE_WEIGHT = 0.80
POP_WEIGHT = 0.20
TECH_BONUS_WEIGHT = 0.10

ENTRY_RE = re.compile(
    r"""
    ^        \s*\[(?P<zone>\d+)\]\s*=\s*\{\s*\n
    \s*(?:base_score|score)\s*=\s*(?P<score>\d+),\s*\n.*?
    \s*quests\s*=\s*\{\s*(?P<quests>[^}]*)\},\s*\n
    \s*\},\s*$
    """,
    re.MULTILINE | re.DOTALL | re.VERBOSE,
)


def read_popularity(pop_csv: Path) -> dict[int, int]:
    with pop_csv.open(encoding="utf-8", newline="") as handle:
        return {int(row["quest_id"]): int(row["pop"]) for row in csv.DictReader(handle)}


def read_technical() -> tuple[dict[int, dict[str, object]], float]:
    payload = json.loads(TECH_JSON.read_text(encoding="utf-8"))
    return (
        {int(quest_id): record for quest_id, record in payload["quests"].items()},
        float(payload["raw_p99"] or 1.0),
    )


def read_pop_trust_weights() -> dict[int, float]:
    """Read manually curated trust in Pop for reviewed chains."""
    if not COMMUNITY_JSON.exists():
        return {}
    payload = json.loads(COMMUNITY_JSON.read_text(encoding="utf-8"))
    weights: dict[int, float] = {}
    for entry in payload.get("verdicts", []):
        zone = int(entry["zone"])
        weight = float(entry["pop_trust_weight"])
        if not 0.0 <= weight <= 1.0:
            raise ValueError(f"pop_trust_weight for zone {zone} must be between 0 and 1")
        weights[zone] = weight
    return weights


def percentile(values: list[int], fraction: float) -> float:
    ordered = sorted(values)
    if not ordered:
        return 1.0
    index = min(len(ordered) - 1, max(0, math.ceil(fraction * len(ordered)) - 1))
    return float(ordered[index])


def parse_entries(text: str) -> list[dict[str, object]]:
    entries: list[dict[str, object]] = []
    for match in ENTRY_RE.finditer(text):
        quests = [int(value) for value in re.findall(r"\d+", match.group("quests"))]
        entries.append(
            {
                "zone": int(match.group("zone")),
                "base_score": int(match.group("score")),
                "quests": quests,
            }
        )
    if not entries:
        raise SystemExit(f"no quest-guide entries found in {DATA}")
    return entries


def score_entry(
    entry: dict[str, object],
    popularity: dict[int, int],
    pop_denominator: float,
    technical: dict[int, dict[str, object]],
    technical_denominator: float,
    pop_trust_weights: dict[int, float],
) -> None:
    quests = entry["quests"]
    assert isinstance(quests, list)
    matched = [popularity[q] for q in quests if q in popularity]
    normalized = [
        min(100.0, 100.0 * math.log1p(pop) / math.log1p(pop_denominator))
        for pop in matched
    ]
    pop_score = sum(normalized) / len(normalized) if normalized else 0.0
    zone = int(entry["zone"])
    pop_trust_weight = pop_trust_weights.get(zone, 1.0)
    effective_pop_score = pop_score * pop_trust_weight
    technical_values = [
        min(
            100.0,
            100.0
            * math.log1p(float(technical.get(q, {}).get("raw", 0)))
            / math.log1p(technical_denominator),
        )
        for q in quests
    ]
    technical_score = (
        sum(technical_values) / len(technical_values) if technical_values else 0.0
    )
    base_score = int(entry["base_score"])
    final_score = min(
        100,
        round(
            BASE_WEIGHT * base_score
            + POP_WEIGHT * effective_pop_score
            + TECH_BONUS_WEIGHT * technical_score
        ),
    )
    entry["pop_score"] = round(pop_score, 2)
    entry["pop_effective_score"] = round(effective_pop_score, 2)
    entry["pop_trust_weight"] = round(pop_trust_weight, 2)
    entry["pop_trust_source"] = "manual" if zone in pop_trust_weights else "raw_default"
    entry["pop_coverage"] = len(matched)
    entry["technical_score"] = round(technical_score, 2)
    entry["technical_coverage"] = sum(
        1 for quest_id in quests if float(technical.get(quest_id, {}).get("raw", 0)) > 0
    )
    entry["quest_count"] = len(quests)
    entry["score"] = final_score


def render(entries: list[dict[str, object]]) -> str:
    lines = [
        "-- Generated by research/quest_guides/recalculate_quest_guides.py. Do not edit.",
        "-- score = 80% research distinctiveness + 20% normalized Wowhead Pop + technical bonus up to +10.",
        "-- Pop is a supporting signal and is log-normalized at the snapshot P99.",
        "-- pop_effective_score = pop_score * manually curated pop_trust_weight.",
        "-- Technical complexity is a supporting signal from direct TrinityCore evidence.",
        "CatQuest335QuestGuide = {",
        "    zones = {",
    ]
    for entry in entries:
        lines.extend(
            [
                f"        [{entry['zone']}] = {{",
                f"            base_score = {entry['base_score']},",
                f"            pop_score = {entry['pop_score']},",
                f"            pop_effective_score = {entry['pop_effective_score']},",
                f"            pop_trust_weight = {entry['pop_trust_weight']},",
                f"            pop_coverage = {entry['pop_coverage']},",
                f"            technical_score = {entry['technical_score']},",
                f"            technical_coverage = {entry['technical_coverage']},",
                f"            score = {entry['score']},",
                "            quests = { " + ", ".join(str(q) for q in entry["quests"]) + " },",
                "        },",
            ]
        )
    lines.extend(["    },", "}", ""])
    return "\n".join(lines)


def write_report(
    entries: list[dict[str, object]],
    pop_denominator: float,
    technical_denominator: float,
) -> None:
    payload = {
        "snapshot_date": date(2026, 11, 10).isoformat(),
        "base_weight": BASE_WEIGHT,
        "pop_weight": POP_WEIGHT,
        "pop_trust_source": "community_validation.json; unreviewed zones use raw_default=1.0",
        "technical_bonus_max": TECH_BONUS_WEIGHT * 100,
        "normalization": "100 * log1p(signal) / log1p(P99), clamped to 100",
        "pop_p99": pop_denominator,
        "technical_p99": technical_denominator,
        "zones": entries,
    }
    REPORT.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    total_quests = sum(int(entry["quest_count"]) for entry in entries)
    covered_quests = sum(int(entry["pop_coverage"]) for entry in entries)
    changed = sum(int(entry["score"]) != int(entry["base_score"]) for entry in entries)
    lines = [
        "# Пересчёт уникальности цепочек",
        "",
        "Формула: score = min(100, round(0.80 × base_score + 0.20 × pop_effective_score + 0.10 × technical_score)).",
        "Pop нормализован логарифмически по 99-му перцентилю снимка; влияние "
        "ограничено 20% итоговой 100-балльной шкалы. Для проверенных цепочек "
        "Pop дополнительно умножается на ручной pop_trust_weight. Техническая сложность "
        "основана на прямых связях с TrinityCore SmartAI, triggers и conditions.",
        "",
        f"- Цепочек: {len(entries)}",
        f"- Квестов в выбранных цепочках: {total_quests}",
        f"- Квестов с Pop: {covered_quests}",
        f"- P99 технической сложности: {technical_denominator:g}",
        f"- Цепочек, где итоговый score отличается от base_score: {changed}",
        f"- P99 Pop: {pop_denominator:g}",
        "",
        "| Зона | Base | Pop raw | Pop eff. | Trust | Tech | Итог | Покрытие |",
        "|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for entry in entries:
        lines.append(
            f"| {entry['zone']} | {entry['base_score']} | {entry['pop_score']}"
            f" | {entry['pop_effective_score']} | {entry['pop_trust_weight']}"
            f" | {entry['technical_score']} | {entry['score']}"
            f" | Pop {entry['pop_coverage']}/{entry['quest_count']}; "
            f"Tech {entry['technical_coverage']}/{entry['quest_count']} |"
        )
    REPORT_MD.write_text("\n".join(lines) + "\n", encoding="utf-8")


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

    popularity = read_popularity(args.popularity_csv)
    pop_denominator = percentile(list(popularity.values()), 0.99)
    technical, technical_denominator = read_technical()
    pop_trust_weights = read_pop_trust_weights()
    entries = parse_entries(DATA.read_text(encoding="utf-8"))
    for entry in entries:
        score_entry(
            entry,
            popularity,
            pop_denominator,
            technical,
            technical_denominator,
            pop_trust_weights,
        )
    DATA.write_text(render(entries), encoding="utf-8", newline="\n")
    write_report(entries, pop_denominator, technical_denominator)
    print(
        f"recalculated {len(entries)} chains; "
        f"Pop P99={pop_denominator:g}; Tech P99={technical_denominator:g}"
    )


if __name__ == "__main__":
    main()
