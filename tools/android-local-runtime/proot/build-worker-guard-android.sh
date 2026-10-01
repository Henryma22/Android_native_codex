#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# Build the tiny host-side lifecycle guard used only around the fixed
# KernelSU-assisted PRoot launcher. It runs outside the Linux guest, so a
# normal Android PIE is sufficient; unlike the guest trampoline it does not
# need to be statically freestanding.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
DEFAULT_NDK_VERSION="29.0.13846066"
ANDROID_API="24"
OUTPUT=""
NDK=""

die() { printf 'build-worker-guard-android: ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'USAGE'
Usage:
  build-worker-guard-android.sh --output DIR [options]

Required:
  --output DIR       output directory containing the guard asset

Options:
  --ndk DIR          Android NDK directory (defaults to ANDROID_NDK_ROOT or
                     $ANDROID_SDK_ROOT/ndk/29.0.13846066)
  --api N            Android API level (default: 24)
USAGE
}

take_value() {
  (($# >= 2)) || die "$1 needs a value"
  printf '%s' "$2"
}

while (($#)); do
  case "$1" in
    --output) OUTPUT=$(take_value "$@"); shift 2 ;;
    --ndk) NDK=$(take_value "$@"); shift 2 ;;
    --api) ANDROID_API=$(take_value "$@"); shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

[[ -n "$OUTPUT" ]] || die "--output is required"
[[ "$OUTPUT" != / ]] || die "refusing filesystem root as output"
mkdir -p -- "$OUTPUT"
OUTPUT=$(cd -- "$OUTPUT" && pwd -P)

if [[ -z "$NDK" ]]; then
  NDK=${ANDROID_NDK_ROOT:-}
  if [[ -z "$NDK" && -n "${ANDROID_SDK_ROOT:-}" ]]; then
    NDK="$ANDROID_SDK_ROOT/ndk/$DEFAULT_NDK_VERSION"
  fi
fi
[[ -n "$NDK" && -d "$NDK" ]] || die "Android NDK 29 is required; pass --ndk"
NDK=$(cd -- "$NDK" && pwd -P)

WINDOWS_NDK_WRAPPER=0
case "$(uname -s)" in
  Darwin)
    HOST_TAG=""
    for candidate in "darwin-$(uname -m)" darwin-arm64 darwin-x86_64; do
      if [[ -d "$NDK/toolchains/llvm/prebuilt/$candidate" ]]; then
        HOST_TAG="$candidate"
        break
      fi
    done
    [[ -n "$HOST_TAG" ]] || die "NDK toolchain is unavailable for this Mac"
    ;;
  Linux)
    if [[ -d "$NDK/toolchains/llvm/prebuilt/linux-x86_64" ]]; then
      HOST_TAG="linux-x86_64"
    elif [[ -d "$NDK/toolchains/llvm/prebuilt/windows-x86_64" && -n "$(command -v wslpath || true)" ]]; then
      HOST_TAG="windows-x86_64"
      WINDOWS_NDK_WRAPPER=1
    else
      die "NDK toolchain is unavailable for this Linux host"
    fi
    ;;
  MINGW*|MSYS*|CYGWIN*) HOST_TAG="windows-x86_64" ;;
  *) die "unsupported build host" ;;
esac

TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/$HOST_TAG"
CC="$TOOLCHAIN/bin/aarch64-linux-android${ANDROID_API}-clang"
resolve_ndk_tool() {
  local name=$1 candidate
  for candidate in "$TOOLCHAIN/bin/$name" "$TOOLCHAIN/bin/$name.exe"; do
    if [[ -x "$candidate" ]]; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  die "missing NDK tool: $TOOLCHAIN/bin/$name"
}
READELF=$(resolve_ndk_tool llvm-readelf)
STRIP=$(resolve_ndk_tool llvm-strip)
for tool in "$CC" "$READELF" "$STRIP"; do
  [[ -x "$tool" ]] || die "missing NDK tool: $tool"
done

WORK=$(mktemp -d "${TMPDIR:-/tmp}/codex-worker-guard.XXXXXX")
trap 'rm -rf -- "$WORK"' EXIT

if (( WINDOWS_NDK_WRAPPER )); then
  [[ "$OUTPUT" == /mnt/* ]] || die "Windows-hosted NDK under WSL requires --output on /mnt/..."

  make_windows_ndk_wrapper() {
    local wrapper=$1 original=$2 original_quoted
    printf -v original_quoted '%q' "$original"
    cat > "$wrapper" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
original=$original_quoted
convert_arg() {
  local value=\$1
  case "\$value" in
    /mnt/*) wslpath -m -- "\$value" ;;
    -I/mnt/*) printf '%s%s' '-I' "\$(wslpath -m -- "\${value#-I}")" ;;
    -L/mnt/*) printf '%s%s' '-L' "\$(wslpath -m -- "\${value#-L}")" ;;
    --sysroot=/mnt/*) printf '%s%s' '--sysroot=' "\$(wslpath -m -- "\${value#--sysroot=}")" ;;
    -MF/mnt/*) printf '%s%s' '-MF' "\$(wslpath -m -- "\${value#-MF}")" ;;
    -o/mnt/*) printf '%s%s' '-o' "\$(wslpath -m -- "\${value#-o}")" ;;
    *) printf '%s' "\$value" ;;
  esac
}
args=()
for value in "\$@"; do args+=("\$(convert_arg "\$value")"); done
exec "\$original" "\${args[@]}"
EOF
    chmod 0755 "$wrapper"
  }

  CC_WRAPPED="$WORK/ndk-clang"
  READELF_WRAPPED="$WORK/ndk-readelf"
  STRIP_WRAPPED="$WORK/ndk-strip"
  make_windows_ndk_wrapper "$CC_WRAPPED" "$CC"
  make_windows_ndk_wrapper "$READELF_WRAPPED" "$READELF"
  make_windows_ndk_wrapper "$STRIP_WRAPPED" "$STRIP"
  CC="$CC_WRAPPED"
  READELF="$READELF_WRAPPED"
  STRIP="$STRIP_WRAPPED"
fi

"$CC" --target="aarch64-linux-android${ANDROID_API}" \
  -D_POSIX_C_SOURCE=200809L -O2 -fPIE -fstack-protector-strong \
  -Wl,-z,noexecstack -Wl,-z,relro -Wl,-z,now -pie \
  "$SCRIPT_DIR/worker-guard.c" -o "$OUTPUT/libcodex_worker_guard.so"
"$STRIP" --strip-all "$OUTPUT/libcodex_worker_guard.so"
chmod 0555 "$OUTPUT/libcodex_worker_guard.so"

header="$($READELF -h "$OUTPUT/libcodex_worker_guard.so")"
printf '%s\n' "$header" | grep -Eq 'Class:\s+ELF64' || die "guard is not ELF64"
printf '%s\n' "$header" | grep -Eq 'Machine:\s+AArch64' || die "guard is not ARM64"
printf '%s\n' "$header" | grep -Eq 'Type:\s+DYN' || die "guard is not a PIE"

if command -v sha256sum >/dev/null 2>&1; then
  sha256=$(sha256sum "$OUTPUT/libcodex_worker_guard.so" | awk '{print $1}')
elif command -v shasum >/dev/null 2>&1; then
  sha256=$(shasum -a 256 "$OUTPUT/libcodex_worker_guard.so" | awk '{print $1}')
else
  die "neither sha256sum nor shasum is available to write the asset manifest"
fi
cat > "$OUTPUT/worker-guard.manifest.json" <<EOF
{
  "schemaVersion": 1,
  "component": "codex-proot-worker-guard",
  "target": "arm64-v8a",
  "androidApi": ${ANDROID_API},
  "ndk": "29.0.13846066",
  "sha256": "${sha256}",
  "filename": "libcodex_worker_guard.so"
}
EOF
printf 'build-worker-guard-android: wrote %s\n' "$OUTPUT/libcodex_worker_guard.so"
printf 'build-worker-guard-android: sha256=%s\n' "$sha256"
