#!/usr/bin/env python3
"""Read and constrain the platform-specific @openai/codex package."""

from __future__ import annotations

import argparse
import json
import os
import posixpath
import re
import sys
from pathlib import PurePosixPath


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("package_json")
    parser.add_argument("requested_version")
    args = parser.parse_args(argv)
    try:
        with open(args.package_json, encoding="utf-8") as handle:
            package = json.load(handle)
        if package.get("name") != "@openai/codex":
            raise ValueError("package name is not @openai/codex")
        version = package.get("version")
        if not isinstance(version, str) or not version:
            raise ValueError("package version is missing")
        package_os = package.get("os")
        package_cpu = package.get("cpu")
        if package_os != ["linux"] or package_cpu != ["arm64"]:
            raise ValueError("package is not explicitly linux/arm64: os=%r cpu=%r" % (package_os, package_cpu))
        bin_value = package.get("bin")
        if isinstance(bin_value, str):
            bin_path = bin_value
        elif isinstance(bin_value, dict) and isinstance(bin_value.get("codex"), str):
            bin_path = bin_value["codex"]
        else:
            # The platform-specific npm package intentionally has no npm `bin`
            # field.  Current Codex ARM64 archives carry the native launcher
            # under the target triple's vendor directory; retain the older
            # root/bin layouts for already-pinned package revisions.
            candidates = [
                "vendor/aarch64-unknown-linux-musl/bin/codex",
                "codex",
                "bin/codex",
                "codex.js",
            ]
            package_dir = os.path.dirname(args.package_json)
            bin_path = next(
                (
                    candidate
                    for candidate in candidates
                    if os.path.isfile(os.path.join(package_dir, candidate))
                    and os.access(os.path.join(package_dir, candidate), os.X_OK)
                ),
                None,
            )
            if bin_path is None:
                raise ValueError("package does not expose a codex bin or native executable")
        if (
            not bin_path
            or bin_path.startswith("/")
            or "\\" in bin_path
            or not re.fullmatch(r"[A-Za-z0-9._+@/-]+", bin_path)
            or posixpath.normpath(bin_path) != bin_path
            or any(part in ("", ".", "..") for part in PurePosixPath(bin_path).parts)
        ):
            raise ValueError("codex bin path is not a normalized package-relative path")
        package_dir = os.path.dirname(args.package_json)
        package_real = os.path.realpath(package_dir)
        bin_real = os.path.realpath(os.path.join(package_dir, *PurePosixPath(bin_path).parts))
        if os.path.commonpath((package_real, bin_real)) != package_real:
            raise ValueError("codex bin path escapes the package")
        if not os.path.isfile(bin_real) or not os.access(bin_real, os.X_OK):
            raise ValueError("codex bin path is not an executable package file")
        dependencies = package.get("dependencies") or {}
        optional = package.get("optionalDependencies") or {}
        if dependencies or optional:
            names = sorted(set(dependencies) | set(optional))
            raise ValueError("package has unresolved dependencies: %s" % ",".join(names))
        if not (version == args.requested_version or version == args.requested_version.removesuffix("-linux-arm64")):
            raise ValueError("resolved package version %s does not match requested %s" % (version, args.requested_version))
        print(version)
        print(bin_path)
        return 0
    except (OSError, json.JSONDecodeError, ValueError) as error:
        print("codex-package-info: ERROR: %s" % error, file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
