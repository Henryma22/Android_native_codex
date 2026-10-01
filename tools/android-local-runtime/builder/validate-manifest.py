#!/usr/bin/env python3
"""Validate the Phase 2 manifest with no third-party JSON-schema package."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path


SHA256 = re.compile(r"^[0-9a-fA-F]{64}$")
NODE_VERSION = re.compile(r"^\d+\.\d+\.\d+$")
SNAPSHOT = re.compile(r"^\d{8}T\d{6}Z$")


class ManifestError(ValueError):
    pass


def required(value: object, name: str) -> object:
    if value is None:
        raise ManifestError("missing required field: %s" % name)
    return value


def obj(value: object, name: str) -> dict:
    if not isinstance(value, dict):
        raise ManifestError("%s must be an object" % name)
    return value


def string(value: object, name: str) -> str:
    if not isinstance(value, str) or not value:
        raise ManifestError("%s must be a non-empty string" % name)
    return value


def exact(value: object, expected: object, name: str) -> None:
    if value != expected:
        raise ManifestError("%s must be %r, got %r" % (name, expected, value))


def sha(value: object, name: str) -> None:
    if not isinstance(value, str) or not SHA256.fullmatch(value) or int(value, 16) == 0:
        raise ManifestError("%s must be a non-zero 64-character SHA-256" % name)


def positive_int(value: object, name: str) -> None:
    if not isinstance(value, int) or isinstance(value, bool) or value < 1:
        raise ManifestError("%s must be a positive integer" % name)


def no_unknown(value: dict, allowed: set[str], name: str) -> None:
    unknown = sorted(set(value) - allowed)
    if unknown:
        raise ManifestError("unknown field(s) in %s: %s" % (name, ", ".join(unknown)))


def validate_manifest(data: object) -> None:
    root = obj(data, "manifest")
    no_unknown(root, {"schema", "artifact", "target", "debian", "components", "sources", "reproducibility", "security", "device_finalize"}, "manifest")
    schema = obj(required(root.get("schema"), "schema"), "schema")
    no_unknown(schema, {"name", "version"}, "schema")
    exact(schema.get("name"), "codex-android-local-rootfs", "schema.name")
    exact(schema.get("version"), 1, "schema.version")

    artifact = obj(required(root.get("artifact"), "artifact"), "artifact")
    no_unknown(artifact, {"filename", "format", "sha256", "bytes", "members", "regular_files", "unpacked_bytes"}, "artifact")
    filename = string(required(artifact.get("filename"), "artifact.filename"), "artifact.filename")
    if "/" in filename or "\\" in filename or not filename.endswith(".tar.gz"):
        raise ManifestError("artifact.filename must be a single .tar.gz basename")
    exact(artifact.get("format"), "tar.gz", "artifact.format")
    sha(required(artifact.get("sha256"), "artifact.sha256"), "artifact.sha256")
    for field in ("bytes", "members", "regular_files", "unpacked_bytes"):
        positive_int(required(artifact.get(field), "artifact." + field), "artifact." + field)

    target = obj(required(root.get("target"), "target"), "target")
    no_unknown(target, {"os", "arch", "android_abi", "host_build", "execution_verification"}, "target")
    exact(target.get("os"), "linux", "target.os")
    exact(target.get("arch"), "arm64", "target.arch")
    exact(target.get("android_abi"), "arm64-v8a", "target.android_abi")
    exact(target.get("host_build"), "linux-x86_64", "target.host_build")
    exact(target.get("execution_verification"), "deferred-to-arm64-device", "target.execution_verification")

    debian = obj(required(root.get("debian"), "debian"), "debian")
    no_unknown(debian, {"suite", "snapshot", "mirror", "arch", "variant", "foreign_second_stage", "keyring_sha256"}, "debian")
    suite = string(required(debian.get("suite"), "debian.suite"), "debian.suite")
    if not re.fullmatch(r"[a-z0-9][a-z0-9-]+", suite):
        raise ManifestError("invalid Debian suite")
    snapshot = string(required(debian.get("snapshot"), "debian.snapshot"), "debian.snapshot")
    if not SNAPSHOT.fullmatch(snapshot):
        raise ManifestError("debian.snapshot must be an immutable snapshot timestamp")
    mirror = string(required(debian.get("mirror"), "debian.mirror"), "debian.mirror")
    expected_mirror = "https://snapshot.debian.org/archive/debian/%s/" % snapshot
    if mirror.rstrip("/") != expected_mirror.rstrip("/"):
        raise ManifestError("debian.mirror must match the pinned snapshot")
    exact(debian.get("arch"), "arm64", "debian.arch")
    exact(debian.get("variant"), "minbase", "debian.variant")
    exact(debian.get("foreign_second_stage"), True, "debian.foreign_second_stage")
    sha(required(debian.get("keyring_sha256"), "debian.keyring_sha256"), "debian.keyring_sha256")

    components = obj(required(root.get("components"), "components"), "components")
    no_unknown(components, {"node", "codex"}, "components")
    node = obj(required(components.get("node"), "components.node"), "components.node")
    no_unknown(node, {"version", "platform", "arch", "source_url", "sha256", "install_prefix"}, "components.node")
    node_version = string(required(node.get("version"), "components.node.version"), "components.node.version")
    if not NODE_VERSION.fullmatch(node_version):
        raise ManifestError("components.node.version must be semver")
    if tuple(int(part) for part in node_version.split(".")) < (20, 18, 1):
        raise ManifestError("Node must be >= 20.18.1")
    exact(node.get("platform"), "linux", "components.node.platform")
    exact(node.get("arch"), "arm64", "components.node.arch")
    node_url = string(required(node.get("source_url"), "components.node.source_url"), "components.node.source_url")
    if not node_url.startswith("https://nodejs.org/dist/v"):
        raise ManifestError("Node must come from the official nodejs.org tarball")
    sha(required(node.get("sha256"), "components.node.sha256"), "components.node.sha256")
    exact(node.get("install_prefix"), "/opt/node", "components.node.install_prefix")

    codex = obj(required(components.get("codex"), "components.codex"), "components.codex")
    no_unknown(codex, {"package", "requested_version", "resolved_version", "platform", "arch", "source_url", "sha256", "integrity", "install_prefix", "bin"}, "components.codex")
    exact(codex.get("package"), "@openai/codex", "components.codex.package")
    requested = string(required(codex.get("requested_version"), "components.codex.requested_version"), "components.codex.requested_version")
    if not re.fullmatch(r"\d+\.\d+\.\d+-linux-arm64", requested):
        raise ManifestError("Codex must be an exact linux-arm64 package version")
    string(required(codex.get("resolved_version"), "components.codex.resolved_version"), "components.codex.resolved_version")
    exact(codex.get("platform"), "linux", "components.codex.platform")
    exact(codex.get("arch"), "arm64", "components.codex.arch")
    codex_url = string(required(codex.get("source_url"), "components.codex.source_url"), "components.codex.source_url")
    if not codex_url.startswith("https://registry.npmjs.org/"):
        raise ManifestError("Codex must come from the npm registry")
    sha(required(codex.get("sha256"), "components.codex.sha256"), "components.codex.sha256")
    integrity = string(required(codex.get("integrity"), "components.codex.integrity"), "components.codex.integrity")
    if not re.fullmatch(r"sha512-[A-Za-z0-9+/]+={0,2}", integrity):
        raise ManifestError("components.codex.integrity must be a pinned npm sha512 integrity")
    exact(codex.get("install_prefix"), "/opt/codex", "components.codex.install_prefix")
    exact(codex.get("bin"), "codex", "components.codex.bin")

    sources = required(root.get("sources"), "sources")
    if not isinstance(sources, list) or len(sources) < 3:
        raise ManifestError("sources must contain Debian, Node and Codex entries")
    for index, source in enumerate(sources):
        source_obj = obj(source, "sources[%d]" % index)
        no_unknown(source_obj, {"name", "url", "immutable", "sha256"}, "sources[%d]" % index)
        string(required(source_obj.get("name"), "sources[%d].name" % index), "sources[%d].name" % index)
        string(required(source_obj.get("url"), "sources[%d].url" % index), "sources[%d].url" % index)
        string(required(source_obj.get("immutable"), "sources[%d].immutable" % index), "sources[%d].immutable" % index)
        if "sha256" in source_obj:
            sha(source_obj["sha256"], "sources[%d].sha256" % index)

    reproducibility = obj(required(root.get("reproducibility"), "reproducibility"), "reproducibility")
    no_unknown(reproducibility, {"archive_mtime", "numeric_owner", "production_install", "versions_independent"}, "reproducibility")
    exact(reproducibility.get("archive_mtime"), "1970-01-01T00:00:00Z", "reproducibility.archive_mtime")
    exact(reproducibility.get("numeric_owner"), "0:0", "reproducibility.numeric_owner")
    exact(reproducibility.get("production_install"), "direct-verified-tarballs", "reproducibility.production_install")
    exact(reproducibility.get("versions_independent"), True, "reproducibility.versions_independent")

    security = obj(required(root.get("security"), "security"), "security")
    no_unknown(security, {"archive_check", "rejected"}, "security")
    exact(security.get("archive_check"), "archive_safety.py", "security.archive_check")
    exact(security.get("rejected"), ["absolute-or-traversal-paths", "special-files", "setuid-setgid", "capability-xattrs", "world-writable"], "security.rejected")

    finalize = obj(required(root.get("device_finalize"), "device_finalize"), "device_finalize")
    no_unknown(finalize, {"script", "second_stage", "checks"}, "device_finalize")
    exact(finalize.get("script"), "device/proot-finalize-rootfs.sh", "device_finalize.script")
    exact(finalize.get("second_stage"), "/debootstrap/debootstrap --second-stage", "device_finalize.second_stage")
    exact(finalize.get("checks"), ["node-version", "codex-version", "rootfs-policy"], "device_finalize.checks")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest")
    parser.add_argument("--schema", help="schema file to require alongside the manifest")
    args = parser.parse_args(argv)
    try:
        path = Path(args.manifest)
        with path.open("r", encoding="utf-8") as handle:
            data = json.load(handle)
        validate_manifest(data)
        if args.schema:
            schema_path = Path(args.schema)
            with schema_path.open("r", encoding="utf-8") as handle:
                schema = json.load(handle)
            if schema.get("$id") != "https://codex.local/schemas/android-local-rootfs-manifest-1.json":
                raise ManifestError("unexpected manifest schema $id")
        print("manifest valid: %s" % path)
        return 0
    except (OSError, json.JSONDecodeError, ManifestError) as error:
        print("manifest-validator: ERROR: %s" % error, file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
