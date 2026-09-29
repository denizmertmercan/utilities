#!/usr/bin/env python3
"""Count lines in one or more text files."""

import argparse
from pathlib import Path


def line_count(path: Path, encoding: str = "utf-8") -> int:
    """Return the number of lines in *path*."""
    with path.open("r", encoding=encoding, newline="") as source:
        return sum(1 for _ in source)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", type=Path, nargs="+")
    args = parser.parse_args()
    for path in args.paths:
        print(f"{line_count(path)}\t{path}")


if __name__ == "__main__":
    main()
