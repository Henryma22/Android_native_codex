#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# Run the canonical ARM64 foreign-rootfs builder in an x86_64 Linux container.
# The Mac host only supplies a read-only checkout and explicit host output/cache
# directories; the builder's temporary rootfs tree stays on the container's
# Linux filesystem so APFS case-folding cannot alter the foreign tree.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
SOURCE_ROOT="$(cd -- "$SCRIPT_DIR/../../.." && pwd -P)"
BUILDER="/src/tools/android-local-runtime/builder/build-rootfs.sh"
DEFAULT_IMAGE="debian:bookworm-slim@sha256:abd67ffcfa541b485a3dff59865ab629aa048a6c613e639d36e7456b0b229241"
OUTPUT=""
CACHE=""
IMAGE="${CCPOCKET_ROOTFS_DOCKER_IMAGE:-$DEFAULT_IMAGE}"

die() {
  printf 'build-rootfs-docker: ERROR: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'USAGE'
Usage:
  build-rootfs-docker.sh --output DIR --cache DIR [--image IMAGE] [-- BUILDER-OPTIONS...]

Required:
  --output DIR       host directory for the generated archive and manifest
  --cache DIR        host directory for debootstrap/npm/local archive caches

Options:
  --image IMAGE      Docker image (default is pinned Debian bookworm-slim)
  --                 end wrapper options and pass the remaining options to
                     builder/build-rootfs.sh inside the container

The checkout is mounted read-only at /src, output at /out, and cache at
/cache. The builder's temporary --work-dir is /work inside the container.
Pass local archives using their container paths, for example
--node-tarball /cache/node-v24.19.0-linux-arm64.tar.xz.
USAGE
}

take_value() {
  (($# >= 2)) || die "$1 needs a value"
  printf '%s' "$2"
}

BUILDER_ARGS=()
while (($#)); do
  case "$1" in
    --output) OUTPUT=$(take_value "$@"); shift 2 ;;
    --cache) CACHE=$(take_value "$@"); shift 2 ;;
    --image) IMAGE=$(take_value "$@"); shift 2 ;;
    --) shift; BUILDER_ARGS=("$@"); break ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown wrapper option: $1 (use -- before builder options)" ;;
  esac
done

[[ -n "$OUTPUT" ]] || die "--output is required"
[[ -n "$CACHE" ]] || die "--cache is required"
[[ "$OUTPUT" != / && "$CACHE" != / ]] || die "refusing filesystem root as output/cache"
command -v docker >/dev/null 2>&1 || die "docker is required"
[[ -d "$SOURCE_ROOT/.git" ]] || die "source checkout is not a git directory: $SOURCE_ROOT"

mkdir -p -- "$OUTPUT" "$CACHE"
OUTPUT=$(cd -- "$OUTPUT" && pwd -P)
CACHE=$(cd -- "$CACHE" && pwd -P)
case "$OUTPUT" in
  "$SOURCE_ROOT"|"$SOURCE_ROOT"/*) die "output must be outside the source checkout" ;;
esac
case "$CACHE" in
  "$SOURCE_ROOT"|"$SOURCE_ROOT"/*) die "cache must be outside the source checkout" ;;
esac

docker run --rm --pull=missing --platform linux/amd64 \
  --mount "type=bind,src=$SOURCE_ROOT,dst=/src,readonly" \
  --mount "type=bind,src=$OUTPUT,dst=/out" \
  --mount "type=bind,src=$CACHE,dst=/cache" \
  "$IMAGE" \
  bash -c '
    set -Eeuo pipefail
    export DEBIAN_FRONTEND=noninteractive
    offline=0
    for arg in "$@"; do
      if [[ "$arg" == "--offline" ]]; then
        offline=1
        break
      fi
    done
    if (( offline )); then
      # An offline build must not contact Debian mirrors just to bootstrap
      # the ephemeral container. The caller supplies a base rootfs and local
      # Node/Codex archives; use an image that already contains the builder
      # tools (for example node:24-bookworm).
      for command_name in bash node npm python3 sha256sum tar gzip find cp install git; do
        command -v "$command_name" >/dev/null 2>&1 || {
          echo "build-rootfs-docker: ERROR: offline image lacks $command_name" >&2
          exit 1
        }
      done
    else
      apt-get update
      builder_packages=(
        ca-certificates curl debootstrap debian-archive-keyring dpkg-dev
        git gzip python3 tar xz-utils
      )
      # The recommended Node builder image already contains a newer Node/npm
      # pair.  Do not ask apt to install Debian nodejs/npm as well: that pulls
      # hundreds of unrelated Debian JavaScript packages into every ephemeral
      # container.  The fallback keeps the wrapper usable with the pinned slim
      # Debian image for builders that do not provide Node.
      command -v node >/dev/null 2>&1 || builder_packages+=(nodejs)
      command -v npm >/dev/null 2>&1 || builder_packages+=(npm)
      apt-get install --yes --no-install-recommends "${builder_packages[@]}"
    fi
    exec bash "$1" --source-root /src --output /out --cache /cache \
      --work-dir /work "${@:2}"
  ' container "$BUILDER" "${BUILDER_ARGS[@]}"
