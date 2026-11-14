"""Standalone entry point for the one-click CatQuest Hybrid client."""

from __future__ import annotations

import sys

from catquest_client import main


COMMANDS = {"sync", "request", "watch", "companion", "hybrid", "auto"}
HELP_FLAGS = {"-h", "--help", "--version"}


def run() -> int:
    argv = list(sys.argv[1:])
    if not argv:
        argv = ["hybrid"]
    elif argv[0] not in COMMANDS and argv[0] not in HELP_FLAGS:
        argv.insert(0, "hybrid")
    return main(argv)


if __name__ == "__main__":
    raise SystemExit(run())
