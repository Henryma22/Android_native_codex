#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# Build a Debian ARM64 foreign rootfs on Linux x86_64 (WSL2 is supported).
# The script intentionally requires --output so a build cannot silently fill
# the Windows C: drive. It never invokes ARM64 binaries; final execution
# checks are performed by device/proot-finalize-rootfs.sh on a rooted ARM64
# device through the independent app installer.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
DEFAULT_SOURCE_ROOT="$(cd -- "$SCRIPT_DIR/../../.." && pwd -P)"

OUTPUT=""
CACHE=""
WORK=""
SOURCE_ROOT="$DEFAULT_SOURCE_ROOT"
BASE_ROOTFS=""
OFFLINE=0
NODE_VERSION="24.19.0"
NODE_URL=""
NODE_TARBALL=""
NODE_SHA256="01443c1e1a29e531ccad5a46fefa6df490d2189c49f7955904aecdbb0fe86fdc"
CODEX_VERSION="0.157.1-linux-arm64"
CODEX_URL=""
CODEX_TARBALL=""
CODEX_SHA256=""
CODEX_INTEGRITY="sha512-nEaBZT3ldrtqUNaBlvI+Y+fg+LbNCTsQjbUnl7Q45rl9vSSqHU2vRj1l6iJDwupZkrpeIJ/ClHIwxgMKv1SKHg=="
DEBIAN_SUITE="bookworm"
DEBIAN_SNAPSHOT="20260821T000000Z"
DEBIAN_MIRROR=""
DEBIAN_KEYRING=""
KEEP_WORK=0

die() { echo "build-rootfs: ERROR: $*" >&2; exit 1; }
log() { echo "build-rootfs: $*"; }

usage() {
  cat <<'USAGE'
Usage:
  build-rootfs.sh --output DIR [options]

Builds a reproducible Debian ARM64 foreign rootfs artifact for a rooted
Android ARM64 device. The command must run on Linux x86_64 (including WSL2),
and must never be used to execute the ARM64 rootfs on the x86_64 host.

Required:
  --output DIR                  Artifact directory (explicit; no C: default)
  --codex-sha256 HEX            SHA-256 of @openai/codex tarball

Inputs and paths:
  --source-root DIR             android_codex checkout (default: detected checkout)
  --cache DIR                   npm/download cache (default: OUTPUT/cache)
  --work-dir DIR                temporary build directory (default: OUTPUT/work)
  --base-rootfs DIR             existing foreign rootfs; useful with --offline
  --offline                     no network; requires local tarballs and base rootfs
  --keep-work                   retain the temporary build directory

Pinned components:
  --node-version V              Node version >=20.18.1 (default: 24.19.0)
  --node-sha256 HEX             Node official tarball SHA-256
  --node-url URL                official nodejs.org URL (derived by default)
  --node-tarball FILE           local Node tarball (hash is still required)
  --codex-version V             exact @openai/codex linux-arm64 version
                                (default: 0.157.1-linux-arm64)
  --codex-url URL               npm registry tarball URL (derived by default)
  --codex-tarball FILE          local Codex tarball (hash/integrity still required)
  --codex-integrity VALUE       npm sha512-... integrity (pinned default supplied)

Debian:
  --debian-suite SUITE          Debian suite (default: bookworm)
  --debian-snapshot TIMESTAMP   immutable snapshot YYYYMMDDThhmmssZ
                                (default: 20260821T000000Z)
  --debian-mirror URL           snapshot mirror (derived and checked)
  --debian-keyring FILE         explicit Debian archive keyring

The normal path runs debootstrap --foreign --arch=arm64 --variant=minbase and
does not run its second stage. Use device/proot-finalize-rootfs.sh after
extraction on an
ARM64 rooted device to run the second stage and verify the Node/Codex runtime.
USAGE
}

take_value() {
  (($# >= 2)) || die "$1 needs a value"
  printf '%s' "$2"
}

while (($#)); do
  case "$1" in
    --output) OUTPUT=$(take_value "$@"); shift 2 ;;
    --source-root) SOURCE_ROOT=$(take_value "$@"); shift 2 ;;
    --cache) CACHE=$(take_value "$@"); shift 2 ;;
    --work-dir) WORK=$(take_value "$@"); shift 2 ;;
    --base-rootfs) BASE_ROOTFS=$(take_value "$@"); shift 2 ;;
    --offline) OFFLINE=1; shift ;;
    --keep-work) KEEP_WORK=1; shift ;;
    --node-version) NODE_VERSION=$(take_value "$@"); shift 2 ;;
    --node-sha256) NODE_SHA256=$(take_value "$@"); shift 2 ;;
    --node-url) NODE_URL=$(take_value "$@"); shift 2 ;;
    --node-tarball) NODE_TARBALL=$(take_value "$@"); shift 2 ;;
    --codex-version) CODEX_VERSION=$(take_value "$@"); shift 2 ;;
    --codex-sha256) CODEX_SHA256=$(take_value "$@"); shift 2 ;;
    --codex-url) CODEX_URL=$(take_value "$@"); shift 2 ;;
    --codex-tarball) CODEX_TARBALL=$(take_value "$@"); shift 2 ;;
    --codex-integrity) CODEX_INTEGRITY=$(take_value "$@"); shift 2 ;;
    --debian-suite) DEBIAN_SUITE=$(take_value "$@"); shift 2 ;;
    --debian-snapshot) DEBIAN_SNAPSHOT=$(take_value "$@"); shift 2 ;;
    --debian-mirror) DEBIAN_MIRROR=$(take_value "$@"); shift 2 ;;
    --debian-keyring) DEBIAN_KEYRING=$(take_value "$@"); shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

[[ "$(uname -s)" == "Linux" ]] || die "builder must run on Linux/WSL2; refusing non-Linux host"
case "$(uname -m)" in
  x86_64|amd64) ;;
  *) die "builder must run on Linux x86_64; ARM64 execution belongs on the device" ;;
esac
[[ -n "$OUTPUT" ]] || die "--output is required; choose a D: or other large filesystem path"
[[ "$OUTPUT" != / ]] || die "refusing filesystem root as output"
mkdir -p -- "$OUTPUT"
OUTPUT=$(cd -- "$OUTPUT" && pwd -P)
[[ -d "$SOURCE_ROOT" ]] || die "source checkout does not exist: $SOURCE_ROOT"
SOURCE_ROOT=$(cd -- "$SOURCE_ROOT" && pwd -P)
case "$OUTPUT" in
  "$SOURCE_ROOT"|"$SOURCE_ROOT"/*) die "--output must be outside the source checkout" ;;
esac
CACHE=${CACHE:-"$OUTPUT/cache"}
WORK=${WORK:-"$OUTPUT/work"}
mkdir -p -- "$CACHE"
CACHE=$(cd -- "$CACHE" && pwd -P)
[[ "$CACHE" != / ]] || die "refusing filesystem root as cache"
case "$CACHE" in
  "$SOURCE_ROOT"|"$SOURCE_ROOT"/*) die "--cache must be outside the source checkout" ;;
esac
case "$WORK" in
  /|"$SOURCE_ROOT"|"$SOURCE_ROOT"/*) die "unsafe work directory" ;;
esac
[[ ! -e "$WORK" ]] || die "work directory already exists; choose --work-dir or remove only that build directory"
mkdir -p -- "$WORK"
WORK=$(cd -- "$WORK" && pwd -P)

cleanup_work() {
  local status=$?
  if (( status == 0 && KEEP_WORK == 0 )); then
    # WORK was required to be a newly-created exact directory, never a broad
    # path. Keep failed work for diagnosis; remove only successful scratch.
    rm -rf -- "$WORK"
  else
    log "work retained at $WORK"
  fi
  exit "$status"
}
trap cleanup_work EXIT

validate_sha() {
  local label=$1 value=$2
  [[ "$value" =~ ^[0-9a-fA-F]{64}$ ]] || die "$label must be a 64-character SHA-256; refusing an unpinned input"
  [[ "$value" != 0000000000000000000000000000000000000000000000000000000000000000 ]] \
    || die "$label cannot be all zeroes"
}

validate_semver() {
  [[ "$2" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "$1 must be strict numeric semver"
}

validate_sha node-sha256 "$NODE_SHA256"
validate_sha codex-sha256 "$CODEX_SHA256"
[[ "$CODEX_INTEGRITY" =~ ^sha512-[A-Za-z0-9+/]+={0,2}$ ]] \
  || die "codex-integrity must be a pinned npm sha512-... value"
validate_semver node-version "$NODE_VERSION"
python3 - "$NODE_VERSION" <<'PY'
import sys
parts = tuple(int(x) for x in sys.argv[1].split('.'))
if parts < (20, 18, 1):
    raise SystemExit('Node must be >=20.18.1')
PY
[[ "$CODEX_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+-linux-arm64$ ]] \
  || die "Codex version must be an exact linux-arm64 npm package version"
[[ "$DEBIAN_SUITE" =~ ^[a-z0-9][a-z0-9-]+$ ]] || die "invalid Debian suite"
[[ "$DEBIAN_SNAPSHOT" =~ ^[0-9]{8}T[0-9]{6}Z$ ]] || die "Debian snapshot must be YYYYMMDDThhmmssZ"

NODE_URL=${NODE_URL:-"https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-arm64.tar.xz"}
CODEX_URL=${CODEX_URL:-"https://registry.npmjs.org/@openai/codex/-/codex-${CODEX_VERSION}.tgz"}
DEBIAN_MIRROR=${DEBIAN_MIRROR:-"https://snapshot.debian.org/archive/debian/${DEBIAN_SNAPSHOT}/"}
CODEX_BASE_VERSION="${CODEX_VERSION%-linux-arm64}"
[[ "$NODE_URL" == "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-arm64.tar.xz" ]] \
  || die "Node URL must be the official exact linux-arm64 tarball URL"
if [[ "$CODEX_URL" != "https://registry.npmjs.org/@openai/codex/-/codex-${CODEX_VERSION}.tgz" \
   && "$CODEX_URL" != "https://registry.npmjs.org/@openai/codex/-/codex-${CODEX_BASE_VERSION}.tgz" ]]; then
  die "Codex URL must be an exact npm registry tarball URL for the requested package"
fi
[[ "$DEBIAN_MIRROR" == "https://snapshot.debian.org/archive/debian/${DEBIAN_SNAPSHOT}/" ]] \
  || die "Debian mirror must be the exact pinned snapshot URL"

if [[ -n "$BASE_ROOTFS" ]]; then
  [[ -d "$BASE_ROOTFS" && ! -L "$BASE_ROOTFS" ]] || die "--base-rootfs is not a real directory"
  BASE_ROOTFS=$(cd -- "$BASE_ROOTFS" && pwd -P)
fi
if (( OFFLINE )); then
  [[ -n "$BASE_ROOTFS" ]] || die "--offline requires --base-rootfs; debootstrap has no safe implicit offline package cache"
  [[ -n "$NODE_TARBALL" && -n "$CODEX_TARBALL" ]] || die "--offline requires --node-tarball and --codex-tarball"
fi

if [[ -z "$DEBIAN_KEYRING" && -f /usr/share/keyrings/debian-archive-keyring.gpg ]]; then
  DEBIAN_KEYRING=/usr/share/keyrings/debian-archive-keyring.gpg
fi
[[ -n "$DEBIAN_KEYRING" ]] || die "Debian archive keyring is required; pass --debian-keyring with a verified keyring file"
KEYRING_SHA256=""
if [[ -n "$DEBIAN_KEYRING" ]]; then
  [[ -f "$DEBIAN_KEYRING" ]] || die "Debian keyring does not exist: $DEBIAN_KEYRING"
  KEYRING_SHA256=$(sha256sum -- "$DEBIAN_KEYRING" | awk '{print $1}')
  validate_sha debian-keyring-sha256 "$KEYRING_SHA256"
fi

for command_name in python3 sha256sum tar gzip find cp install; do
  command -v "$command_name" >/dev/null 2>&1 || die "required command missing: $command_name"
done
if (( ! OFFLINE )); then
  command -v debootstrap >/dev/null 2>&1 || die "debootstrap is required (install it in WSL/Linux; no ARM execution is attempted)"
  command -v curl >/dev/null 2>&1 || die "curl is required for pinned downloads"
  [[ "$(id -u)" == 0 ]] || die "normal debootstrap build must run as root (use sudo in WSL); no partial rootfs is produced"
fi

materialize() {
  local label=$1 url=$2 local_file=$3 destination=$4 expected_sha=$5
  if [[ -n "$local_file" ]]; then
    [[ -f "$local_file" ]] || die "$label local archive is missing: $local_file"
    cp -- "$local_file" "$destination"
  else
    (( OFFLINE == 0 )) || die "--offline forbids downloading $label"
    log "downloading pinned $label"
    curl --fail --location --proto '=https' --tlsv1.2 --retry 3 --retry-delay 2 --output "$destination" "$url"
  fi
  printf '%s  %s\n' "$expected_sha" "$destination" | sha256sum --check --status - \
    || die "$label SHA-256 verification failed"
}

NODE_ARCHIVE="$WORK/node.tar.xz"
CODEX_ARCHIVE="$WORK/codex.tgz"
materialize Node "$NODE_URL" "$NODE_TARBALL" "$NODE_ARCHIVE" "$NODE_SHA256"
materialize Codex "$CODEX_URL" "$CODEX_TARBALL" "$CODEX_ARCHIVE" "$CODEX_SHA256"
python3 "$SCRIPT_DIR/verify-integrity.py" "$CODEX_ARCHIVE" "$CODEX_INTEGRITY"

python3 "$SCRIPT_DIR/archive_safety.py" --archive "$NODE_ARCHIVE" --expected-sha256 "$NODE_SHA256" --json > "$WORK/node-archive.json"
python3 "$SCRIPT_DIR/archive_safety.py" --archive "$CODEX_ARCHIVE" --expected-sha256 "$CODEX_SHA256" --json > "$WORK/codex-archive.json"

ROOTFS="$WORK/rootfs"
mkdir -p -- "$ROOTFS"
if [[ -n "$BASE_ROOTFS" ]]; then
  log "copying supplied foreign rootfs"
  cp -a -- "$BASE_ROOTFS/." "$ROOTFS/"
else
  log "running debootstrap --foreign for Debian $DEBIAN_SUITE arm64 at $DEBIAN_SNAPSHOT"
  mkdir -p -- "$CACHE/debootstrap"
  # util-linux supplies the complete setpriv contract used by the root
  # supervisor (UID/GID, supplementary groups, capability sets, securebits,
  # and no_new_privs).  tini is the PID-1 reaper inside the private namespace.
  # libcap2-bin supplies getcap for the device-side post-second-stage
  # capability check.  Keep these names explicit: changing the package set
  # changes the rootfs contract and must be reviewable in the manifest diff.
  # python-is-python3 supplies the conventional `python` command used by
  # coding tools while keeping Debian's Python 3 package as the implementation.
  # Keep jq explicit: Codex-side diagnostics and JSON tooling use it, and
  # relying on the retired Android/Bionic toolchain fallback would violate the
  # independent PRoot guest contract.
  # Keep libkeyutils1 explicit: the Debian curl/GSSAPI runtime can load it,
  # while a minimal foreign rootfs may omit the optional dependency otherwise.
  DEBOOTSTRAP_ARGS=(
    --arch=arm64
    --variant=minbase
    --foreign
    --cache-dir="$CACHE/debootstrap"
    --include=ca-certificates,git,python3,python-is-python3,bash,coreutils,curl,jq,libkeyutils1,util-linux,tini,libcap2-bin
  )
  if [[ -n "$DEBIAN_KEYRING" ]]; then
    DEBOOTSTRAP_ARGS+=(--keyring="$DEBIAN_KEYRING")
  fi
  debootstrap "${DEBOOTSTRAP_ARGS[@]}" "$DEBIAN_SUITE" "$ROOTFS" "$DEBIAN_MIRROR"
fi

required_runtime_file="$ROOTFS/usr/bin/setpriv"
[[ -f "$required_runtime_file" && ! -L "$required_runtime_file" && -x "$required_runtime_file" ]] \
  || die "foreign rootfs is missing required executable: $required_runtime_file"

# debootstrap --foreign downloads non-Essential --include packages for the
# device-side second stage but intentionally leaves some of them in
# var/cache/apt/archives.  In particular, Debian's tini package is present as
# a verified .deb here and is unpacked only by the device finalizer. Validate
# that archive now instead of incorrectly requiring /usr/bin/tini before the
# foreign second stage has run; the device finalizer still requires the actual
# executable after second-stage configuration.
if [[ ! -f "$ROOTFS/usr/bin/tini" ]]; then
  TINI_DEB=$(find "$ROOTFS/var/cache/apt/archives" -maxdepth 1 -type f -name 'tini_*.deb' -print -quit)
  [[ -n "$TINI_DEB" ]] || die "foreign rootfs is missing both /usr/bin/tini and its cached Debian package"
  command -v dpkg-deb >/dev/null 2>&1 || die "dpkg-deb is required to inspect the cached tini package"
  TINI_CONTENTS=$(dpkg-deb --contents "$TINI_DEB") \
    || die "cached tini package cannot be inspected"
  printf '%s\n' "$TINI_CONTENTS" | grep -E '[[:space:]]\./usr/bin/tini$' >/dev/null \
    || die "cached tini package does not contain /usr/bin/tini"
fi

mkdir -p -- "$ROOTFS/opt/node" "$ROOTFS/opt/codex/lib/node_modules/@openai" "$ROOTFS/usr/local/bin"
# These directories are mount targets for the device-side supervisor.  They
# are intentionally ordinary empty directories in the immutable image; the
# live home/workspace/tmp/run/proc/dev contents are supplied in its private
# mount namespace.
if [[ -L "$ROOTFS/proc" ]]; then
  # Debian's usr-is-merged foreign layer can leave the proc mountpoint as the
  # self-referential `/proc -> /proc` link. It is harmless during package
  # extraction but is a symlink cycle for the device staging resolver and is
  # not a valid mount target. Only replace this exact known link.
  [[ "$(readlink -- "$ROOTFS/proc")" == /proc ]] || die "unexpected proc mountpoint symlink"
  rm -f -- "$ROOTFS/proc"
fi
mkdir -p -- "$ROOTFS/home/codex" "$ROOTFS/workspaces/current" "$ROOTFS/tmp" "$ROOTFS/run" "$ROOTFS/proc" "$ROOTFS/dev"
tar --extract --file "$NODE_ARCHIVE" --strip-components=1 --directory "$ROOTFS/opt/node"

# The official Node archive stores npm and npx as relative symlinks.  A
# rootfs assembled on a case-insensitive or symlink-limited staging volume can
# silently turn those links into zero-byte mode-000 files.  That failure is
# only noticed on the ARM64 device as `npm: exit 127`, after the expensive APK
# build.  Keep Node itself from the pinned archive, but use small regular
# launchers for these two entry points so the runtime survives that staging
# boundary.  The target CLI files are part of the same verified Node archive.
materialize_node_cli() {
  local name=$1 cli=$2 launcher="$ROOTFS/opt/node/bin/$1"
  local target="$ROOTFS/opt/node/lib/node_modules/npm/bin/$cli"
  [[ -f "$target" && ! -L "$target" && -r "$target" ]] \
    || die "Node archive is missing npm CLI target: $cli"
  rm -f -- "$launcher"
  printf '%s\n' \
    '#!/bin/sh' \
    "exec /opt/node/bin/node /opt/node/lib/node_modules/npm/bin/$cli \"\$@\"" \
    > "$launcher"
  chmod 0755 -- "$launcher"
}
materialize_node_cli npm npm-cli.js
materialize_node_cli npx npx-cli.js
[[ -f "$ROOTFS/opt/node/bin/npm" && -x "$ROOTFS/opt/node/bin/npm" ]] \
  || die "materialized npm launcher is not executable"
[[ -f "$ROOTFS/opt/node/bin/npx" && -x "$ROOTFS/opt/node/bin/npx" ]] \
  || die "materialized npx launcher is not executable"
ln -sfn -- ../../../opt/node/bin/node "$ROOTFS/usr/local/bin/node"
ln -sfn -- ../../../opt/node/bin/npm "$ROOTFS/usr/local/bin/npm"
ln -sfn -- ../../../opt/node/bin/npx "$ROOTFS/usr/local/bin/npx"

CODEX_TARGET="$ROOTFS/opt/codex/lib/node_modules/@openai/codex"
mkdir -p -- "$CODEX_TARGET"
tar --extract --file "$CODEX_ARCHIVE" --strip-components=1 --directory "$CODEX_TARGET"
CODEX_INFO=$(python3 "$SCRIPT_DIR/codex-package-info.py" "$CODEX_TARGET/package.json" "$CODEX_VERSION")
CODEX_RESOLVED_VERSION=$(printf '%s\n' "$CODEX_INFO" | sed -n '1p')
CODEX_BIN=$(printf '%s\n' "$CODEX_INFO" | sed -n '2p')
[[ -n "$CODEX_RESOLVED_VERSION" && -n "$CODEX_BIN" ]] || die "Codex package metadata is incomplete"
[[ "$CODEX_BIN" != /* && "$CODEX_BIN" != *'\\'* ]] || die "unexpected Codex bin path: $CODEX_BIN"
ln -sfn -- "../../../opt/codex/lib/node_modules/@openai/codex/$CODEX_BIN" "$ROOTFS/usr/local/bin/codex"

# Debian commonly creates /tmp as 01777. This runtime is root-owned during
# the PoC and intentionally removes world-write permission so the archive
# policy has one unambiguous answer.
for temporary in "$ROOTFS/tmp" "$ROOTFS/var/tmp"; do
  if [[ -d "$temporary" ]]; then
    chmod 0755 -- "$temporary"
  fi
done
# debootstrap may leave a package-owned device node such as /dev/console in
# the foreign tree.  The Android supervisor mounts a fresh minimal /dev in
# its private namespace, so no host/device node belongs in the immutable
# archive.  Remove every pre-existing entry while retaining the mountpoint;
# archive_safety.py below remains the fail-closed guard for any future change.
if [[ -d "$ROOTFS/dev" ]]; then
  find "$ROOTFS/dev" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
fi
# The minimal Debian package set leaves the optional `rmt` compatibility link
# at /etc/rmt without its /usr/sbin/rmt target.  It is not used by the runtime
# and the device staging contract rejects dangling links, so remove this
# known harmless link while retaining it if a future package set supplies the
# target.
if [[ -L "$ROOTFS/etc/rmt" ]]; then
  RMT_TARGET=$(readlink -- "$ROOTFS/etc/rmt")
  case "$RMT_TARGET" in
    /*) RMT_TARGET_PATH="$ROOTFS$RMT_TARGET" ;;
    *) RMT_TARGET_PATH="$ROOTFS/etc/$RMT_TARGET" ;;
  esac
  if [[ ! -e "$RMT_TARGET_PATH" ]]; then
    rm -f -- "$ROOTFS/etc/rmt"
  fi
fi
# The foreign minimal layer does not run Debian's timezone postinst.  It can
# therefore contain the package's ``zoneinfo/localtime -> /etc/localtime``
# link without the usual /etc/localtime target.  Keep the deterministic UTC
# default, but make the target explicit so the device staging contract never
# has to accept a dangling link.
LOCALTIME_LINK="$ROOTFS/usr/share/zoneinfo/localtime"
if [[ -L "$LOCALTIME_LINK" ]]; then
  LOCALTIME_TARGET=$(readlink -- "$LOCALTIME_LINK")
  if [[ "$LOCALTIME_TARGET" == "/etc/localtime" &&
        ! -e "$ROOTFS/etc/localtime" && ! -L "$ROOTFS/etc/localtime" ]]; then
    ln -s -- /usr/share/zoneinfo/UTC "$ROOTFS/etc/localtime"
  fi
fi
rm -f -- "$ROOTFS/etc/machine-id"

# Debian packages can legitimately carry setuid/setgid bits.  The Android
# runtime policy cannot permit them, so clear the bits only after all trusted
# package extraction/install work has completed and then fail closed if any
# remain.  Special files, capabilities/xattrs, and world-writable entries are
# still rejected by archive_safety.py below; they are never normalized here.
find "$ROOTFS" -xdev \( -type f -o -type d \) -perm /6000 -exec chmod ug-s {} +
if [[ -n "$(find "$ROOTFS" -xdev \( -type f -o -type d \) -perm /6000 -print -quit)" ]]; then
  die "setuid/setgid bit remains after rootfs normalization"
fi
# Debian's base image also contains a few traditionally world-writable lock
# directories (for example /var/lock).  The live runtime mounts its writable
# areas separately, so the immutable tree must not retain those defaults.
# Remove group/world write from every ordinary entry before the final scan.
find "$ROOTFS" -xdev \( -type f -o -type d \) -perm /002 -exec chmod go-w {} +

python3 "$SCRIPT_DIR/archive_safety.py" --root "$ROOTFS" --allow-internal-absolute-links --json > "$WORK/rootfs-tree.json"

ARTIFACT="$OUTPUT/codex-rootfs-${DEBIAN_SUITE}-${DEBIAN_SNAPSHOT}-node-${NODE_VERSION}-codex-${CODEX_VERSION}-arm64.tar.gz"
MANIFEST_PATH="${ARTIFACT%.tar.gz}.manifest.json"
[[ ! -e "$ARTIFACT" && ! -e "$MANIFEST_PATH" ]] || die "artifact already exists; use a new --output or remove only the exact old artifact"
log "creating deterministic rootfs archive"
(
  cd -- "$ROOTFS"
  tar --sort=name --hard-dereference --mtime='UTC 1970-01-01' --owner=0 --group=0 --numeric-owner --format=posix --create --file=- . \
    | gzip --no-name --best > "$ARTIFACT"
)
ARCHIVE_JSON="$WORK/final-archive.json"
python3 "$SCRIPT_DIR/archive_safety.py" --archive "$ARTIFACT" --allow-internal-absolute-links --json > "$ARCHIVE_JSON"

MANIFEST_ARGS=(
  --output "$MANIFEST_PATH"
  --artifact "$ARTIFACT"
  --archive-json "$ARCHIVE_JSON"
  --node-version "$NODE_VERSION" --node-url "$NODE_URL" --node-sha256 "$NODE_SHA256"
  --codex-version "$CODEX_VERSION" --codex-resolved-version "$CODEX_RESOLVED_VERSION"
  --codex-url "$CODEX_URL" --codex-sha256 "$CODEX_SHA256" --codex-integrity "$CODEX_INTEGRITY"
  --debian-suite "$DEBIAN_SUITE" --debian-snapshot "$DEBIAN_SNAPSHOT" --debian-mirror "$DEBIAN_MIRROR"
)
if [[ -n "$KEYRING_SHA256" ]]; then
  MANIFEST_ARGS+=(--debian-keyring-sha256 "$KEYRING_SHA256")
fi
python3 "$SCRIPT_DIR/write-manifest.py" "${MANIFEST_ARGS[@]}"
python3 "$SCRIPT_DIR/validate-manifest.py" "$MANIFEST_PATH" --schema "$SCRIPT_DIR/rootfs-manifest.schema.json"

log "rootfs artifact: $ARTIFACT"
log "manifest: $MANIFEST_PATH"
log "host did not execute Node/Codex ARM64 code; run device/proot-finalize-rootfs.sh after extraction"
