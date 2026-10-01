#!/usr/bin/env python3
"""Safely convert a builder archive into the device staging contract.

The builder archive and the device manifest intentionally have different
identities.  The archive SHA-256 authenticates the downloaded tarball; the
SHA-256 of the generated ``rootfs.manifest`` is the canonical runtime digest
used for the device version directory and the Android install API.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import posixpath
import shutil
import stat
import sys
import tarfile
from pathlib import Path, PurePosixPath


RUNTIME_VERSION = "2"


def fail(message: str) -> None:
    raise ValueError(message)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def safe_member_name(name: str) -> str:
    if not name or "\x00" in name or "\\" in name or name.startswith("/"):
        fail(f"archive contains an unsafe member path: {name!r}")
    while name.startswith("./"):
        name = name[2:]
    if not name:
        return "."
    if name == ".":
        return name
    normalized = posixpath.normpath(name)
    if normalized in ("", ".") or normalized != name:
        fail(f"archive member is not normalized: {name!r}")
    parts = PurePosixPath(name).parts
    if any(part in ("", ".", "..") for part in parts):
        fail(f"archive contains traversal path: {name!r}")
    return name


def ensure_parent(root: Path, relative: str) -> Path:
    parent = root.joinpath(*PurePosixPath(relative).parts).parent
    parent_real = parent.resolve(strict=False)
    root_real = root.resolve()
    if os.path.commonpath((str(root_real), str(parent_real))) != str(root_real):
        fail(f"archive member parent escapes staging root: {relative!r}")
    cursor = root
    for part in PurePosixPath(relative).parts[:-1]:
        cursor = cursor / part
        if cursor.is_symlink():
            fail(f"archive member traverses a symlinked directory: {relative!r}")
    parent.mkdir(parents=True, exist_ok=True)
    return root.joinpath(*PurePosixPath(relative).parts)


def resolve_chroot_path(root: Path, relative: str) -> Path:
    """Resolve a member using rootfs (rather than host) path semantics.

    ``Path.resolve`` interprets an absolute symlink target against the host
    filesystem.  That is wrong for a chroot archive: ``/etc/localtime`` means
    ``<root>/etc/localtime`` and that target may itself be an absolute chroot
    symlink.  Resolve each path component explicitly so the staging check
    agrees with the device-side validator and never follows a link out of the
    extracted root.
    """

    pending = list(PurePosixPath(relative).parts)
    resolved: list[str] = []
    seen: set[tuple[tuple[str, ...], tuple[str, ...]]] = set()
    for _ in range(256):
        if not pending:
            candidate = root.joinpath(*resolved)
            if not candidate.exists():
                fail(f"archive contains a dangling symlink: {relative}")
            return candidate

        part = pending.pop(0)
        if part in ("", "."):
            continue
        if part == "..":
            if not resolved:
                fail(f"archive symlink escapes staging root: {relative}")
            resolved.pop()
            continue
        resolved.append(part)
        candidate = root.joinpath(*resolved)
        if not candidate.is_symlink():
            continue

        state = (tuple(resolved), tuple(pending))
        if state in seen:
            fail(f"archive contains a symlink cycle: {relative}")
        seen.add(state)
        link_target = os.readlink(candidate)
        if not link_target or "\x00" in link_target or "\\" in link_target:
            fail(f"archive contains an unsafe symlink target: {relative}")
        resolved.pop()
        if link_target.startswith("/"):
            # An absolute target is rooted at the chroot, not at the
            # symlink's parent (which is how a host Path would interpret it).
            resolved.clear()
            target_parts = list(PurePosixPath(link_target.lstrip("/")).parts)
            if not target_parts:
                fail(f"archive symlink escapes staging root: {relative}")
        else:
            target_parts = list(PurePosixPath(link_target).parts)
        pending = target_parts + pending
    fail(f"archive contains too many symlink indirections: {relative}")


def extract_archive(archive: Path, root: Path) -> None:
    with tarfile.open(archive, mode="r:gz") as stream:
        members = stream.getmembers()
        for member in members:
            name = safe_member_name(member.name)
            if name == ".":
                if not member.isdir():
                    fail("archive root entry is not a directory")
                continue
            if member.islnk():
                fail(f"archive hard links are not accepted: {name}")
            if not (member.isdir() or member.isfile() or member.issym()):
                fail(f"archive contains a special file: {name}")
            mode = member.mode
            if not member.issym() and mode & 0o002:
                fail(f"archive member is world-writable: {name}")
            if not member.issym() and mode & 0o6000:
                fail(f"archive member has setuid/setgid bits: {name}")
            target = ensure_parent(root, name)
            if member.isdir():
                if target.exists() and not target.is_dir():
                    fail(f"archive directory collides with a file: {name}")
                target.mkdir(parents=True, exist_ok=True)
                os.chmod(target, mode & 0o7777)
            elif member.issym():
                if target.exists() or target.is_symlink():
                    fail(f"archive member is duplicated: {name}")
                os.symlink(member.linkname, target)
            else:
                if target.exists() or target.is_symlink():
                    fail(f"archive member is duplicated: {name}")
                source = stream.extractfile(member)
                if source is None:
                    fail(f"archive regular file has no payload: {name}")
                with target.open("wb") as destination:
                    shutil.copyfileobj(source, destination, length=1024 * 1024)
                os.chmod(target, mode & 0o7777)

    for path in sorted(root.rglob("*")):
        if not path.is_symlink():
            continue
        resolve_chroot_path(root, path.relative_to(root).as_posix())


def write_manifest(root: Path, path: Path) -> str:
    lines: list[str] = []
    for candidate in sorted(root.rglob("*")):
        if candidate.is_symlink() or not candidate.is_file():
            continue
        relative = candidate.relative_to(root).as_posix()
        lines.append(f"{sha256_file(candidate)}  {relative}\n")
    if not lines:
        fail("staged rootfs contains no regular files")
    with path.open("w", encoding="utf-8", newline="\n") as handle:
        handle.write("".join(lines))
    return sha256_file(path)


def require_case_sensitive_directory(directory: Path) -> None:
    """Reject NTFS/other case-folding output before extracting the image.

    Debian rootfs images legitimately contain names that differ only by case
    (for example ``PAM.7.gz`` and the ``pam.7.gz`` symlink).  Extracting such
    an image into WSL's ``/mnt/<drive>`` silently aliases the entries and can
    either fail late or produce a tree that is not the ARM64 artifact that
    was verified.  Keep the check local and recoverable; no caller data is
    removed if a stale probe is found.
    """
    if not directory.is_dir() or directory.is_symlink():
        fail(f"staging filesystem probe requires a real directory: {directory}")
    probe = directory / f".ccpocket-case-probe-{os.getpid()}"
    if probe.exists() or probe.is_symlink():
        fail(f"staging filesystem probe already exists: {probe}")
    # The two names must differ only by case. Using words such as "lower" and
    # "upper" would be distinct on a case-insensitive APFS volume and would
    # let the later PAM.7.gz/pam.7.gz collision fail much deeper in extraction.
    lower = probe / "ccpocket-case-probe"
    upper = probe / "CCPOCKET-CASE-PROBE"
    try:
        probe.mkdir()
        lower.mkdir()
        if upper.exists() or upper.is_symlink():
            fail(
                "staging output must be on a case-sensitive filesystem; "
                "use a WSL-native path such as /home/<user>/ccpocket-staging "
                "instead of /mnt/<drive>"
            )
        upper.mkdir()
    except FileExistsError as error:
        fail(
            "staging output must be on a case-sensitive filesystem; "
            "use a WSL-native path such as /home/<user>/ccpocket-staging "
            "instead of /mnt/<drive>"
        )
    finally:
        shutil.rmtree(probe, ignore_errors=True)


def semver(value: object, label: str) -> str:
    if not isinstance(value, str) or not __import__("re").fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", value):
        fail(f"{label} is not numeric semver")
    return value


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--artifact", required=True, type=Path)
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args(argv)
    try:
        manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
        artifact_meta = manifest["artifact"]
        expected_archive_sha = artifact_meta["sha256"]
        if not isinstance(expected_archive_sha, str) or len(expected_archive_sha) != 64:
            fail("manifest artifact SHA-256 is invalid")
        actual_archive_sha = sha256_file(args.artifact)
        if actual_archive_sha != expected_archive_sha.lower():
            fail("artifact SHA-256 does not match the builder manifest")

        components = manifest["components"]
        node_version = semver(components["node"]["version"], "Node version")
        codex_version = components["codex"]["resolved_version"]
        if isinstance(codex_version, str) and codex_version.endswith("-linux-arm64"):
            codex_version = codex_version[: -len("-linux-arm64")]
        codex_version = semver(codex_version, "Codex version")

        output = args.output.absolute()
        if output.exists():
            if any(output.iterdir()):
                fail(f"output directory must be new or empty: {output}")
        else:
            output.parent.mkdir(parents=True, exist_ok=True)
        require_case_sensitive_directory(output if output.exists() else output.parent)
        temporary = output.parent / f".{output.name}.stage-{os.getpid()}"
        if temporary.exists():
            fail(f"temporary staging directory already exists: {temporary}")
        temporary.mkdir()
        try:
            root = temporary / "rootfs"
            root.mkdir()
            extract_archive(args.artifact, root)
            manifest_path = temporary / "rootfs.manifest"
            runtime_digest = write_manifest(root, manifest_path)
            metadata = (
                f"runtime_version={RUNTIME_VERSION}\n"
                f"manifest_sha256={runtime_digest}\n"
                f"artifact_sha256={actual_archive_sha}\n"
                f"node_version={node_version}\n"
                f"codex_version={codex_version}\n"
            )
            with (temporary / "runtime.metadata").open(
                "w", encoding="utf-8", newline="\n"
            ) as handle:
                handle.write(metadata)
            shutil.copyfile(args.manifest, temporary / "builder.manifest.json")
            if output.exists():
                output.rmdir()
            os.replace(temporary, output)
        except Exception:
            shutil.rmtree(temporary, ignore_errors=True)
            raise
        print(f"staging directory: {output}")
        print(f"runtime digest: {runtime_digest}")
        print(f"archive digest: {actual_archive_sha}")
        return 0
    except (OSError, KeyError, json.JSONDecodeError, tarfile.TarError, ValueError) as error:
        print(f"stage-for-device: ERROR: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
