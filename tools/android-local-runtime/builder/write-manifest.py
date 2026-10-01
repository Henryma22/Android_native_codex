#!/usr/bin/env python3
"""Write the deterministic Phase 2 rootfs manifest."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path


def read_json(path: str) -> dict:
    with open(path, encoding="utf-8") as handle:
        value = json.load(handle)
    if not isinstance(value, dict):
        raise ValueError("expected JSON object: %s" % path)
    return value


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True)
    parser.add_argument("--artifact", required=True)
    parser.add_argument("--archive-json", required=True)
    parser.add_argument("--node-version", required=True)
    parser.add_argument("--node-url", required=True)
    parser.add_argument("--node-sha256", required=True)
    parser.add_argument("--codex-version", required=True)
    parser.add_argument("--codex-resolved-version", required=True)
    parser.add_argument("--codex-url", required=True)
    parser.add_argument("--codex-sha256", required=True)
    parser.add_argument("--codex-integrity", required=True)
    parser.add_argument("--debian-suite", required=True)
    parser.add_argument("--debian-snapshot", required=True)
    parser.add_argument("--debian-mirror", required=True)
    parser.add_argument("--debian-keyring-sha256")
    args = parser.parse_args(argv)
    try:
        archive = read_json(args.archive_json)
        artifact = {
            "filename": os.path.basename(args.artifact),
            "format": "tar.gz",
            "sha256": archive["sha256"],
            "bytes": os.path.getsize(args.artifact),
            "members": archive["members"],
            "regular_files": archive["regular_files"],
            "unpacked_bytes": archive["unpacked_bytes"],
        }
        if "/" in artifact["filename"] or "\\" in artifact["filename"]:
            raise ValueError("artifact must be a basename")
        if args.debian_keyring_sha256 and not re.fullmatch(r"[0-9a-fA-F]{64}", args.debian_keyring_sha256):
            raise ValueError("invalid Debian keyring hash")
        manifest = {
            "schema": {"name": "codex-android-local-rootfs", "version": 1},
            "artifact": artifact,
            "target": {
                "os": "linux",
                "arch": "arm64",
                "android_abi": "arm64-v8a",
                "host_build": "linux-x86_64",
                "execution_verification": "deferred-to-arm64-device",
            },
            "debian": {
                "suite": args.debian_suite,
                "snapshot": args.debian_snapshot,
                "mirror": args.debian_mirror,
                "arch": "arm64",
                "variant": "minbase",
                "foreign_second_stage": True,
            },
            "components": {
                "node": {
                    "version": args.node_version,
                    "platform": "linux",
                    "arch": "arm64",
                    "source_url": args.node_url,
                    "sha256": args.node_sha256,
                    "install_prefix": "/opt/node",
                },
                "codex": {
                    "package": "@openai/codex",
                    "requested_version": args.codex_version,
                    "resolved_version": args.codex_resolved_version,
                    "platform": "linux",
                    "arch": "arm64",
                    "source_url": args.codex_url,
                    "sha256": args.codex_sha256,
                    "integrity": args.codex_integrity,
                    "install_prefix": "/opt/codex",
                    "bin": "codex",
                },
            },
            "sources": [
                {
                    "name": "Debian snapshot",
                    "url": args.debian_mirror,
                    "immutable": args.debian_snapshot,
                },
                {
                    "name": "Node.js official ARM64 tarball",
                    "url": args.node_url,
                    "immutable": args.node_version,
                    "sha256": args.node_sha256,
                },
                {
                    "name": "OpenAI Codex npm package",
                    "url": args.codex_url,
                    "immutable": args.codex_version,
                    "sha256": args.codex_sha256,
                },
            ],
            "reproducibility": {
                "archive_mtime": "1970-01-01T00:00:00Z",
                "numeric_owner": "0:0",
                "production_install": "direct-verified-tarballs",
                "versions_independent": True,
            },
            "security": {
                "archive_check": "archive_safety.py",
                "rejected": [
                    "absolute-or-traversal-paths",
                    "special-files",
                    "setuid-setgid",
                    "capability-xattrs",
                    "world-writable",
                ],
            },
            "device_finalize": {
                "script": "device/proot-finalize-rootfs.sh",
                "second_stage": "/debootstrap/debootstrap --second-stage",
                "checks": ["node-version", "codex-version", "rootfs-policy"],
            },
        }
        if args.debian_keyring_sha256:
            manifest["debian"]["keyring_sha256"] = args.debian_keyring_sha256
        output = Path(args.output)
        output.parent.mkdir(parents=True, exist_ok=True)
        with output.open("w", encoding="utf-8", newline="\n") as handle:
            json.dump(manifest, handle, ensure_ascii=False, indent=2, sort_keys=True)
            handle.write("\n")
        print("manifest written: %s" % output)
        return 0
    except (OSError, KeyError, json.JSONDecodeError, ValueError) as error:
        print("write-manifest: ERROR: %s" % error, file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
