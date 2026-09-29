#!/usr/bin/env python3
"""Print a file's cryptographic hash."""

import argparse
import hashlib
from pathlib import Path


def file_hash(path: Path, algorithm: str = "sha256", chunk_size: int = 1024 * 1024) -> str:
    """Return the digest for *path* using a bounded read buffer."""
    digest = hashlib.new(algorithm)
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(chunk_size), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path", type=Path)
    parser.add_argument("-a", "--algorithm", default="sha256", choices=sorted(hashlib.algorithms_available))
    args = parser.parse_args()
    print(file_hash(args.path, args.algorithm))


if __name__ == "__main__":
    main()
