#!/usr/bin/env python3
"""Verify a file against an npm Subresource Integrity value."""

from __future__ import annotations

import argparse
import base64
import hashlib
import re
import sys


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("file")
    parser.add_argument("integrity")
    args = parser.parse_args(argv)
    if not re.fullmatch(r"sha512-[A-Za-z0-9+/]+={0,2}", args.integrity):
        print("integrity must be a pinned sha512 value", file=sys.stderr)
        return 1
    expected_algorithm, expected_value = args.integrity.split("-", 1)
    digest = hashlib.sha512()
    try:
        with open(args.file, "rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
    except OSError as error:
        print("integrity: ERROR: %s" % error, file=sys.stderr)
        return 1
    actual = base64.b64encode(digest.digest()).decode("ascii")
    if actual != expected_value:
        print("integrity mismatch: expected %s, got %s-%s" % (args.integrity, expected_algorithm, actual), file=sys.stderr)
        return 1
    print("integrity valid: %s" % args.file)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
