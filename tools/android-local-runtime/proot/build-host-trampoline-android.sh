#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# Build the static ARM64 first-exec trampoline used by the PRoot worker. It is
# intentionally freestanding: no Android Bionic linker or library tree is
# exposed to the guest before PRoot can translate the first guest execve.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
DEFAULT_NDK_VERSION="29.0.13846066"
ANDROID_API="24"
OUTPUT=""
NDK=""

die() { printf 'build-host-trampoline-android: ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'USAGE'
Usage:
  build-host-trampoline-android.sh --output DIR [options]

Required:
  --output DIR       output directory containing the trampoline asset

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
    elif [[ -d "$NDK/toolchains/llvm/prebuilt/windows-x86_64" &&
            -n "$(command -v wslpath || true)" ]]; then
      HOST_TAG="windows-x86_64"
      WINDOWS_NDK_WRAPPER=1
    else
      die "NDK toolchain is unavailable for this Linux host"
    fi
    ;;
  *) die "unsupported build host" ;;
esac

TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/$HOST_TAG"
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
CLANG=$(resolve_ndk_tool clang)
LLD=$(resolve_ndk_tool ld.lld)
STRIP=$(resolve_ndk_tool llvm-strip)
READELF=$(resolve_ndk_tool llvm-readelf)
for tool in "$CLANG" "$LLD" "$STRIP" "$READELF"; do
  [[ -x "$tool" ]] || die "missing NDK tool: $tool"
done

if (( WINDOWS_NDK_WRAPPER )); then
  case "$OUTPUT" in
    /mnt/*) ;;
    *) die "Windows-hosted NDK under WSL requires --output on /mnt/..." ;;
  esac

  WORK=$(mktemp -d "$OUTPUT/.codex-host-trampoline.XXXXXX")
  trap 'rm -rf -- "$WORK"' EXIT
  make_windows_ndk_wrapper() {
    local wrapper=$1 original=$2 original_quoted
    printf -v original_quoted '%q' "$original"
    cat > "$wrapper" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
original=$original_quoted
to_windows_path() { wslpath -m -- "\$1"; }
convert_arg() {
  local value=\$1
  case "\$value" in
    /mnt/*) to_windows_path "\$value" ;;
    -I/mnt/*) printf '%s%s' '-I' "\$(to_windows_path "\${value#-I}")" ;;
    -L/mnt/*) printf '%s%s' '-L' "\$(to_windows_path "\${value#-L}")" ;;
    --sysroot=/mnt/*) printf '%s%s' '--sysroot=' "\$(to_windows_path "\${value#--sysroot=}")" ;;
    -MF/mnt/*) printf '%s%s' '-MF' "\$(to_windows_path "\${value#-MF}")" ;;
    -o/mnt/*) printf '%s%s' '-o' "\$(to_windows_path "\${value#-o}")" ;;
    *) printf '%s' "\$value" ;;
  esac
}
args=()
for value in "\$@"; do args+=("\$(convert_arg "\$value")"); done
exec "\$original" "\${args[@]}"
EOF
    chmod 0755 "$wrapper"
  }
  CLANG_WRAPPED="$WORK/ndk-clang"
  LLD_WRAPPED="$WORK/ndk-ld"
  STRIP_WRAPPED="$WORK/ndk-strip"
  READELF_WRAPPED="$WORK/ndk-readelf"
  make_windows_ndk_wrapper "$CLANG_WRAPPED" "$CLANG"
  make_windows_ndk_wrapper "$LLD_WRAPPED" "$LLD"
  make_windows_ndk_wrapper "$STRIP_WRAPPED" "$STRIP"
  make_windows_ndk_wrapper "$READELF_WRAPPED" "$READELF"
  CLANG="$CLANG_WRAPPED"
  LLD="$LLD_WRAPPED"
  STRIP="$STRIP_WRAPPED"
  READELF="$READELF_WRAPPED"
fi

if [[ -z "${WORK:-}" ]]; then
  WORK=$(mktemp -d "${TMPDIR:-/tmp}/codex-host-trampoline.XXXXXX")
  trap 'rm -rf -- "$WORK"' EXIT
fi

TARGET="aarch64-linux-android$ANDROID_API"
"$CLANG" --target="$TARGET" -c -fPIE -ffreestanding -fno-stack-protector \
  -nostdlib "$SCRIPT_DIR/host-trampoline.S" -o "$WORK/host-trampoline.o"
"$LLD" -flavor gnu -m aarch64linux -pie -static -e _start \
  -o "$OUTPUT/libcodex_host_trampoline.so" "$WORK/host-trampoline.o"
"$STRIP" --strip-all "$OUTPUT/libcodex_host_trampoline.so"
chmod 0555 "$OUTPUT/libcodex_host_trampoline.so"

header="$("$READELF" -h "$OUTPUT/libcodex_host_trampoline.so")"
printf '%s\n' "$header" | grep -Eq 'Class:[[:space:]]+ELF64' || die "trampoline is not ELF64"
printf '%s\n' "$header" | grep -Eq 'Machine:[[:space:]]+AArch64' || die "trampoline is not ARM64"
printf '%s\n' "$header" | grep -Eq 'Type:[[:space:]]+DYN' || die "trampoline is not a static PIE"

sha256=$(shasum -a 256 "$OUTPUT/libcodex_host_trampoline.so" | awk '{print $1}')
cat > "$OUTPUT/host-trampoline.manifest.json" <<EOF
{
  "schemaVersion": 1,
  "component": "codex-proot-host-trampoline",
  "target": "arm64-v8a",
  "androidApi": ${ANDROID_API},
  "ndk": "29.0.13846066",
  "static": true,
  "sha256": "${sha256}",
  "filename": "libcodex_host_trampoline.so"
}
EOF
printf 'build-host-trampoline-android: wrote %s\n' "$OUTPUT/libcodex_host_trampoline.so"
printf 'build-host-trampoline-android: sha256=%s\n' "$sha256"
