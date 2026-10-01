#!/usr/bin/env python3
"""Produce a deterministic digest for a directory tree.

The digest includes relative POSIX paths, entry kinds, symlink targets and
regular-file bytes.  It is intentionally independent of owners, modes and
mtimes, which are controlled separately by the rootfs archive hardening step.
"""

from __future__ import annotations

import argparse
import hashlib
import os
import stat
import sys


def digest_tree(root: str) -> tuple[str, int, int]:
    root = os.path.abspath(root)
    if not os.path.isdir(root):
        raise ValueError("not a directory: %s" % root)
    entries: list[str] = []
    for current, directories, files in os.walk(root, followlinks=False):
        directories.sort()
        files.sort()
        for name in directories + files:
            full = os.path.join(current, name)
            relative = os.path.relpath(full, root).replace(os.sep, "/")
            entries.append(relative)
    entries.sort()
    digest = hashlib.sha256()
    regular_files = 0
    total_bytes = 0
    for relative in entries:
        full = os.path.join(root, relative.replace("/", os.sep))
        info = os.lstat(full)
        if stat.S_ISDIR(info.st_mode):
            kind = "d"
            payload = b""
        elif stat.S_ISREG(info.st_mode):
            kind = "f"
            regular_files += 1
            total_bytes += info.st_size
            header = (kind + "\0" + relative + "\0" + str(info.st_size) + "\0").encode("utf-8")
            digest.update(header)
            with open(full, "rb") as handle:
                for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                    digest.update(chunk)
            digest.update(b"\0")
            continue
        elif stat.S_ISLNK(info.st_mode):
            kind = "l"
            payload = os.readlink(full).encode("utf-8", "surrogateescape")
        else:
            raise ValueError("unsupported entry type: %s" % relative)
        header = (kind + "\0" + relative + "\0" + str(len(payload)) + "\0").encode("utf-8")
        digest.update(header)
        digest.update(payload)
        digest.update(b"\0")
    return digest.hexdigest(), regular_files, total_bytes


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root")
    args = parser.parse_args(argv)
    try:
        digest, regular_files, total_bytes = digest_tree(args.root)
    except (OSError, ValueError) as error:
        print("tree-digest: ERROR: %s" % error, file=sys.stderr)
        return 1
    print(digest)
    print("regular_files=%d" % regular_files, file=sys.stderr)
    print("bytes=%d" % total_bytes, file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
