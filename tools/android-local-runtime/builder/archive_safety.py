#!/usr/bin/env python3
"""Inspect a rootfs tree or tar archive without extracting it.

The Phase 2 runtime is unpacked by a privileged Android helper.  This small
standard-library-only checker is deliberately conservative: paths may not
escape the archive root, special files and privilege bits are forbidden, and
PAX xattrs (including Linux capabilities) are rejected.  It is used both for
downloaded component archives and for the final rootfs archive.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import posixpath
import stat
import sys
import tarfile
from typing import Any


class SafetyError(RuntimeError):
    """Raised when an input cannot be safely used as a runtime artifact."""


def fail(message: str) -> None:
    raise SafetyError(message)


def safe_member_name(name: str) -> str:
    if not name:
        fail("archive contains an empty member name")
    if "\x00" in name:
        fail("archive member contains NUL: %r" % name)
    # Tar names are POSIX paths even when the builder is run under WSL.
    if name.startswith("/") or name.startswith("//"):
        fail("archive contains an absolute path: %s" % name)
    normalized = posixpath.normpath(name)
    if normalized in ("", ".", "..") or normalized.startswith("../"):
        # A single `.` root entry is harmless, but allowing `..` or an empty
        # path makes it too easy for extraction behavior to vary by tar.
        if normalized != ".":
            fail("archive path escapes its root: %s" % name)
    # Backslashes are ordinary Linux filename bytes, but accepting them here
    # makes a Windows-created archive needlessly hard to reason about.
    if "\\" in name:
        fail("archive member contains a backslash: %s" % name)
    return normalized


def safe_link_target(member_name: str, linkname: str, allow_internal_absolute: bool = False) -> None:
    if not linkname:
        fail("empty link target for %s" % member_name)
    if "\x00" in linkname or "\\" in linkname:
        fail("unsafe link target for %s: %s" % (member_name, linkname))
    if linkname.startswith("/"):
        if not allow_internal_absolute:
            fail("absolute link target is forbidden: %s -> %s" % (member_name, linkname))
        target = posixpath.normpath(linkname.lstrip("/"))
        if target in ("", ".", "..") or target.startswith("../"):
            fail("absolute link target is not internal: %s -> %s" % (member_name, linkname))
        return
    target = posixpath.normpath(posixpath.join(posixpath.dirname(member_name), linkname))
    if target in ("..", "") or target.startswith("../"):
        fail("link escapes archive root: %s -> %s" % (member_name, linkname))


def check_mode(mode: int, name: str) -> None:
    if mode & (stat.S_ISUID | stat.S_ISGID):
        fail("setuid/setgid mode is forbidden: %s (%o)" % (name, mode))
    if mode & stat.S_IWOTH:
        fail("world-writable mode is forbidden: %s (%o)" % (name, mode))


def check_pax_headers(headers: dict[str, str], name: str) -> None:
    for key in headers:
        lowered = key.lower()
        # GNU tar and bsdtar use several spellings for xattrs.  Rejecting all
        # xattrs is intentional: a future capability spelling must not slip
        # through an allow-list.
        if "xattr" in lowered or "capability" in lowered or lowered.startswith("security."):
            fail("extended attribute/capability metadata is forbidden: %s (%s)" % (name, key))


def digest_file(path: str) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        while True:
            chunk = handle.read(1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def inspect_archive(path: str, expected_sha256: str | None, allow_internal_absolute: bool) -> dict[str, Any]:
    if expected_sha256:
        actual = digest_file(path)
        if actual.lower() != expected_sha256.lower():
            fail("sha256 mismatch for %s: expected %s, got %s" % (path, expected_sha256, actual))
    members = 0
    regular_files = 0
    unpacked_bytes = 0
    seen: set[str] = set()
    with tarfile.open(path, mode="r:*") as archive:
        for member in archive.getmembers():
            name = safe_member_name(member.name)
            if name in seen and name != ".":
                fail("duplicate archive member: %s" % name)
            seen.add(name)
            members += 1
            # Symlink mode is conventionally 0777 and is not an enforceable
            # permission bit on Linux; the link target itself is checked.
            if not member.issym():
                check_mode(member.mode, name)
            check_pax_headers(member.pax_headers or {}, name)
            if member.isdev() or member.isfifo():
                fail("special file is forbidden: %s" % name)
            if member.islnk():
                fail("hard link is forbidden: %s" % name)
            if member.issym():
                safe_link_target(name, member.linkname, allow_internal_absolute)
            elif not (member.isdir() or member.isreg()):
                fail("unsupported tar member type for %s" % name)
            if member.isreg():
                regular_files += 1
                unpacked_bytes += member.size
    return {
        "members": members,
        "regular_files": regular_files,
        "unpacked_bytes": unpacked_bytes,
        "sha256": digest_file(path),
    }


def check_xattrs(path: str) -> None:
    try:
        names = os.listxattr(path, follow_symlinks=False)
    except (AttributeError, OSError) as error:
        # Some WSL filesystems do not expose xattrs.  The tar archive check
        # still rejects PAX xattrs; do not turn an unsupported read into a
        # false claim that the filesystem has none.
        if isinstance(error, AttributeError):
            return
        if getattr(error, "errno", None) == 95:  # EOPNOTSUPP
            return
        raise
    if names:
        fail("extended attributes are forbidden: %s (%s)" % (path, ",".join(names)))


def inspect_tree(path: str, allow_internal_absolute: bool) -> dict[str, Any]:
    root = os.path.abspath(path)
    if not os.path.isdir(root) or os.path.islink(root):
        fail("rootfs tree must be a real directory: %s" % path)
    members = 0
    regular_files = 0
    unpacked_bytes = 0
    for current, directories, files in os.walk(root, topdown=True, followlinks=False):
        directories[:] = sorted(directories)
        files[:] = sorted(files)
        entries = directories + files
        for basename in entries:
            full = os.path.join(current, basename)
            relative = os.path.relpath(full, root).replace(os.sep, "/")
            if relative == ".":
                continue
            safe_member_name(relative)
            info = os.lstat(full)
            members += 1
            if not stat.S_ISLNK(info.st_mode):
                check_mode(info.st_mode, relative)
            check_xattrs(full)
            if stat.S_ISLNK(info.st_mode):
                safe_link_target(relative, os.readlink(full), allow_internal_absolute)
            elif stat.S_ISREG(info.st_mode):
                regular_files += 1
                unpacked_bytes += info.st_size
            elif stat.S_ISDIR(info.st_mode):
                continue
            else:
                fail("special file is forbidden: %s" % relative)
    return {
        "members": members,
        "regular_files": regular_files,
        "unpacked_bytes": unpacked_bytes,
    }


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--archive", help="tar/tar.gz/tar.xz archive to inspect")
    source.add_argument("--root", help="already extracted rootfs directory to inspect")
    parser.add_argument("--expected-sha256", help="required SHA-256 for --archive")
    parser.add_argument(
        "--allow-internal-absolute-links",
        action="store_true",
        help="allow /target symlinks only when the target remains inside a chroot (rootfs final check)",
    )
    parser.add_argument("--json", action="store_true", help="emit machine-readable result")
    args = parser.parse_args(argv)
    try:
        if args.expected_sha256 and not args.archive:
            fail("--expected-sha256 is valid only with --archive")
        if args.expected_sha256 and (
            len(args.expected_sha256) != 64
            or any(character not in "0123456789abcdefABCDEF" for character in args.expected_sha256)
        ):
            fail("--expected-sha256 must be 64 hexadecimal characters")
        if args.expected_sha256 and int(args.expected_sha256, 16) == 0:
            fail("--expected-sha256 cannot be all zeroes")
        if args.archive:
            result = inspect_archive(args.archive, args.expected_sha256, args.allow_internal_absolute_links)
            result["kind"] = "archive"
            result["path"] = os.path.abspath(args.archive)
        else:
            result = inspect_tree(args.root, args.allow_internal_absolute_links)
            result["kind"] = "tree"
            result["path"] = os.path.abspath(args.root)
        if args.json:
            print(json.dumps(result, sort_keys=True))
        else:
            print("safe: %s" % result["path"])
            print("members=%d regular_files=%d unpacked_bytes=%d" % (
                result["members"], result["regular_files"], result["unpacked_bytes"]
            ))
            if "sha256" in result:
                print("sha256=%s" % result["sha256"])
        return 0
    except (OSError, tarfile.TarError, SafetyError) as error:
        print("archive-safety: ERROR: %s" % error, file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
