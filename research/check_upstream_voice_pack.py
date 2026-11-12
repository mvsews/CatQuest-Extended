#!/usr/bin/env python3
"""Check the published CatQuest Voices archive without downloading it.

The check uses the archive headers exposed by CurseForge's CDN.  It is meant
for a quick periodic check: a changed size, ETag, or Last-Modified header is a
signal to download the archive and rerun ``voice_inventory.py``.  The full
SHA-256 is recorded only after the archive has been downloaded and inspected.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import datetime, timezone
from email.utils import format_datetime, parsedate_to_datetime
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_HISTORY = ROOT / "docs" / "voice" / "upstream-history.json"
DEFAULT_URL = (
    "https://edge.forgecdn.net/files/9559/250/"
    "CatQuest_Voices-1.3.0.zip"
)


def remote_headers(url: str) -> dict[str, object]:
    request = Request(url, method="HEAD", headers={"User-Agent": "CatQuestExtended-upstream-check/1"})
    try:
        response = urlopen(request, timeout=30)
    except HTTPError as error:
        if error.code not in {405, 501}:
            raise
        request = Request(
            url,
            method="GET",
            headers={
                "Range": "bytes=0-0",
                "User-Agent": "CatQuestExtended-upstream-check/1",
            },
        )
        response = urlopen(request, timeout=30)

    with response:
        headers = response.headers
        content_length = headers.get("Content-Length")
        content_range = headers.get("Content-Range", "")
        if content_range:
            match = re.search(r"/([0-9]+)$", content_range)
            if match:
                content_length = match.group(1)
        return {
            "sizeBytes": int(content_length) if content_length else None,
            "etag": headers.get("ETag"),
            "lastModified": normalize_date(headers.get("Last-Modified")),
        }


def normalize_date(value: str | None) -> str | None:
    if not value:
        return None
    try:
        parsed = parsedate_to_datetime(value)
    except (TypeError, ValueError):
        try:
            parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError:
            return value
    return format_datetime(parsed.astimezone(timezone.utc), usegmt=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--history", type=Path, default=DEFAULT_HISTORY)
    parser.add_argument("--url", default=None, help="CDN URL; defaults to the latest history entry")
    args = parser.parse_args()

    history = json.loads(args.history.read_text(encoding="utf-8"))
    latest = history["releases"][-1]
    url = args.url or latest.get("downloadUrl") or DEFAULT_URL
    current = remote_headers(url)
    expected = {
        "sizeBytes": latest.get("sizeBytes"),
        "etag": latest.get("etag"),
        "lastModified": normalize_date(latest.get("lastModified")),
    }
    changed = [
        key
        for key in ("sizeBytes", "etag", "lastModified")
        if expected.get(key) and current.get(key) != expected.get(key)
    ]
    result = {
        "checkedAt": datetime.now(timezone.utc).isoformat(),
        "url": url,
        "release": latest.get("version"),
        "expected": expected,
        "current": current,
        "changed": changed,
        "action": "download-and-inventory" if changed else "unchanged",
    }
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 2 if changed else 0


if __name__ == "__main__":
    sys.exit(main())
