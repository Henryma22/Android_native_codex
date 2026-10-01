#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# Build the single ARM64 PRoot executable shipped by the Android APK.  The
# source and the allocator dependency are pinned here so a developer cannot
# accidentally put a mutable/latest binary into the app.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PROOT_VERSION="5.1.107.94"
PROOT_COMMIT="58c3b42849fac502c6c60a45c4d2a82da9e9f8d4"
PROOT_REPOSITORY="https://github.com/termux/proot.git"
TALLOC_VERSION="2.4.2"
TALLOC_URL="https://www.samba.org/ftp/talloc/talloc-${TALLOC_VERSION}.tar.gz"
TALLOC_SHA256="85ecf9e465e20f98f9950a52e9a411e14320bc555fa257d87697b7e7a9b1d8a6"
DEFAULT_NDK_VERSION="29.0.13846066"
ANDROID_API="24"
OUTPUT=""
WORK=""
CACHE=""
NDK=""
OFFLINE=0

die() { printf 'build-proot-android: ERROR: %s\n' "$*" >&2; exit 1; }
log() { printf 'build-proot-android: %s\n' "$*"; }

usage() {
  cat <<'USAGE'
Usage:
  build-proot-android.sh --output DIR [options]

Required:
  --output DIR       output directory containing PRoot and its static loader

Options:
  --ndk DIR          Android NDK directory (defaults to ANDROID_NDK_ROOT or
                     $ANDROID_SDK_ROOT/ndk/29.0.13846066)
  --api N            Android API level (default: 24)
  --cache DIR        source/tarball cache (default: output/cache)
  --work-dir DIR     temporary build directory (default: output/work)
  --offline          do not clone or download; require cache inputs
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
    --cache) CACHE=$(take_value "$@"); shift 2 ;;
    --work-dir) WORK=$(take_value "$@"); shift 2 ;;
    --offline) OFFLINE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

[[ -n "$OUTPUT" ]] || die "--output is required"
[[ "$OUTPUT" != / ]] || die "refusing filesystem root as output"
mkdir -p -- "$OUTPUT"
OUTPUT=$(cd -- "$OUTPUT" && pwd -P)
CACHE=${CACHE:-"$OUTPUT/cache"}
WORK=${WORK:-"$OUTPUT/work"}
mkdir -p -- "$CACHE"
CACHE=$(cd -- "$CACHE" && pwd -P)
[[ ! -e "$WORK" ]] || die "work directory already exists; choose a fresh --work-dir"
mkdir -p -- "$WORK"
trap 'if [[ "${KEEP_WORK:-0}" != 1 ]]; then rm -rf -- "$WORK"; fi' EXIT

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
      # WSL can use a Windows-hosted NDK, but Windows clang cannot consume
      # native WSL paths such as /tmp/... or /mnt/c/... in compiler flags.
      # Keep the build on a mounted Windows volume and wrap only the NDK
      # executables so every mounted path is translated to C:/... before the
      # Windows process is launched.
      HOST_TAG="windows-x86_64"
      WINDOWS_NDK_WRAPPER=1
    else
      die "NDK toolchain is unavailable for this Linux host; install linux-x86_64 or use a Windows NDK from WSL with /mnt paths"
    fi
    ;;
  *) die "unsupported build host" ;;
esac
TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/$HOST_TAG"
[[ -d "$TOOLCHAIN" ]] || die "NDK toolchain is unavailable"
CC="$TOOLCHAIN/bin/aarch64-linux-android${ANDROID_API}-clang"
CXX="$TOOLCHAIN/bin/aarch64-linux-android${ANDROID_API}-clang++"
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
AR=$(resolve_ndk_tool llvm-ar)
STRIP=$(resolve_ndk_tool llvm-strip)
OBJCOPY=$(resolve_ndk_tool llvm-objcopy)
OBJDUMP=$(resolve_ndk_tool llvm-objdump)
for tool in "$CC" "$CXX" "$AR" "$STRIP" "$OBJCOPY" "$OBJDUMP"; do
  [[ -x "$tool" ]] || die "missing NDK tool: $tool"
done

if (( WINDOWS_NDK_WRAPPER )); then
  case "$OUTPUT:$CACHE:$WORK" in
    /mnt/*:/mnt/*:/mnt/*) ;;
    *) die "Windows-hosted NDK under WSL requires --output, --cache, and --work-dir on /mnt/..." ;;
  esac

  make_windows_ndk_wrapper() {
    local wrapper=$1 original=$2 original_quoted
    printf -v original_quoted '%q' "$original"
    cat > "$wrapper" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
original=$original_quoted
to_windows_path() {
  wslpath -m -- "\$1"
}
convert_arg() {
  local value=\$1 prefix path
  case "\$value" in
    /mnt/*)
      to_windows_path "\$value"
      ;;
    -I/mnt/*)
      prefix=-I; path=\${value:2}
      printf '%s%s' "\$prefix" "\$(to_windows_path "\$path")"
      ;;
    -L/mnt/*)
      prefix=-L; path=\${value:2}
      printf '%s%s' "\$prefix" "\$(to_windows_path "\$path")"
      ;;
    --sysroot=/mnt/*)
      printf '%s%s' '--sysroot=' "\$(to_windows_path "\${value#--sysroot=}")"
      ;;
    -MF/mnt/*)
      printf '%s%s' '-MF' "\$(to_windows_path "\${value#-MF}")"
      ;;
    -o/mnt/*)
      printf '%s%s' '-o' "\$(to_windows_path "\${value#-o}")"
      ;;
    *)
      printf '%s' "\$value"
      ;;
  esac
}
args=()
for value in "\$@"; do
  args+=("\$(convert_arg "\$value")")
done
exec "\$original" "\${args[@]}"
EOF
    chmod 0755 "$wrapper"
  }

  CC_WRAPPED="$WORK/ndk-clang"
  CXX_WRAPPED="$WORK/ndk-clang++"
  AR_WRAPPED="$WORK/ndk-ar"
  STRIP_WRAPPED="$WORK/ndk-strip"
  OBJCOPY_WRAPPED="$WORK/ndk-objcopy"
  OBJDUMP_WRAPPED="$WORK/ndk-objdump"
  make_windows_ndk_wrapper "$CC_WRAPPED" "$CC"
  make_windows_ndk_wrapper "$CXX_WRAPPED" "$CXX"
  make_windows_ndk_wrapper "$AR_WRAPPED" "$AR"
  make_windows_ndk_wrapper "$STRIP_WRAPPED" "$STRIP"
  make_windows_ndk_wrapper "$OBJCOPY_WRAPPED" "$OBJCOPY"
  make_windows_ndk_wrapper "$OBJDUMP_WRAPPED" "$OBJDUMP"
  CC="$CC_WRAPPED"
  CXX="$CXX_WRAPPED"
  AR="$AR_WRAPPED"
  STRIP="$STRIP_WRAPPED"
  OBJCOPY="$OBJCOPY_WRAPPED"
  OBJDUMP="$OBJDUMP_WRAPPED"
fi

PROOT_SOURCE="$CACHE/proot-${PROOT_VERSION}"
if [[ ! -d "$PROOT_SOURCE/.git" ]]; then
  ((OFFLINE == 0)) || die "offline mode requires cached PRoot source"
  rm -rf -- "$PROOT_SOURCE"
  git clone --depth 1 --branch "v${PROOT_VERSION}" "$PROOT_REPOSITORY" "$PROOT_SOURCE"
fi
[[ "$(git -c "safe.directory=$PROOT_SOURCE" -C "$PROOT_SOURCE" rev-parse HEAD)" == "$PROOT_COMMIT" ]] || \
  die "PRoot source commit does not match the pinned revision"

TALLOC_ARCHIVE="$CACHE/talloc-${TALLOC_VERSION}.tar.gz"
if [[ ! -f "$TALLOC_ARCHIVE" ]]; then
  ((OFFLINE == 0)) || die "offline mode requires the cached talloc archive"
  curl --fail --location --retry 3 --output "$TALLOC_ARCHIVE" "$TALLOC_URL"
fi
[[ "$(shasum -a 256 "$TALLOC_ARCHIVE" | awk '{print $1}')" == "$TALLOC_SHA256" ]] || \
  die "talloc archive SHA-256 does not match the pin"

TALLOC_SOURCE="$WORK/talloc"
mkdir -p -- "$TALLOC_SOURCE"
tar -xzf "$TALLOC_ARCHIVE" --strip-components=1 -C "$TALLOC_SOURCE"
TALLOC_BUILD="$WORK/talloc-build"
mkdir -p -- "$TALLOC_BUILD"

# PRoot only needs libtalloc; building the one translation unit directly keeps
# the cross build independent from target execution (waf's feature probes
# otherwise try to run ARM64 test programs on macOS/WSL).  The talloc source
# includes libreplace headers, but its Android API 24 call sites use native
# memmove/strnlen/vsnprintf implementations.  Do not compile libreplace's
# replace.c here: it is generated/configured by waf, and compiling it without
# that generated config enables incompatible fallback declarations (including
# socklen_t, timespec, and readlink) on Bionic.
TALLOC_OBJECT="$TALLOC_BUILD/talloc.o"
TALLOC_LIBRARY="$TALLOC_BUILD/libtalloc.a"
"$CC" \
  -DNO_CONFIG_H \
  -D__STDC_WANT_LIB_EXT1__=1 \
  -DTALLOC_BUILD_VERSION_MAJOR=2 \
  -DTALLOC_BUILD_VERSION_MINOR=4 \
  -DTALLOC_BUILD_VERSION_RELEASE=2 \
  -DHAVE_STDINT_H=1 -DHAVE_INTTYPES_H=1 -DHAVE_SYS_TYPES_H=1 \
  -DHAVE_STDBOOL_H=1 -DHAVE_BOOL=1 -DHAVE_INTPTR_T=1 \
  -DHAVE_UINTPTR_T=1 -DHAVE_PTRDIFF_T=1 -DHAVE_USECONDS_T=1 \
  -DHAVE_USLEEP=1 -DHAVE_DLFCN_H=1 -DHAVE_DLOPEN=1 -DHAVE_DLSYM=1 \
  -DHAVE_DLERROR=1 -DHAVE_DLCLOSE=1 -DHAVE_UNISTD_H=1 -DHAVE_STDLIB_H=1 -DHAVE_STRING_H=1 \
  -DHAVE_MEMMOVE=1 -DHAVE_STRNLEN=1 -DHAVE_VSNPRINTF=1 -DHAVE_C99_VSNPRINTF=1 \
  -I"$TALLOC_SOURCE" -I"$TALLOC_SOURCE/lib/replace" \
  -O2 -fPIC -c "$TALLOC_SOURCE/talloc.c" -o "$TALLOC_OBJECT"
"$AR" rcs "$TALLOC_LIBRARY" "$TALLOC_OBJECT"

PROOT_BUILD="$WORK/proot-build"
mkdir -p -- "$PROOT_BUILD"
cp -R -- "$PROOT_SOURCE"/. "$PROOT_BUILD"/
# The pinned Termux ashmem extension calls strcmp/memset on Android but omits
# their standard declaration; NDK 29 diagnoses that as an error. Keep the
# compatibility include local to the disposable build copy.
ASHMEM_EXTENSION="$PROOT_BUILD/src/extension/ashmem_memfd/ashmem_memfd.c"
if ! grep -q '^#include <string.h>' "$ASHMEM_EXTENSION"; then
  grep -q '^#include <stdlib.h>' "$ASHMEM_EXTENSION" || die "unexpected ashmem extension source"
  sed -i '/^#include <stdlib.h>/a #include <string.h>' "$ASHMEM_EXTENSION"
fi
# Windows Git may check out the source with CRLF; GNU make treats CR on an
# `ifdef` line as part of the variable name, silently selecting the bundled
# loader path. Normalize this build-only makefile before invoking make.
sed -i 's/\r$//' "$PROOT_BUILD/src/GNUmakefile"
# lld's legacy -Ttext form leaves the ARM64 loader's PT_LOAD segment starting
# at a low address while placing .text at LOADER_ADDRESS.  That produces a
# multi-gigabyte sparse intermediate which llvm-objcopy scans linearly on
# macOS.  --image-base keeps the same runtime virtual address with a compact
# file-backed segment.  Termux's static loader target is loader/loader.
sed -i.bak 's/-Ttext=/--image-base=/' "$PROOT_BUILD/src/GNUmakefile"
log "building PRoot ${PROOT_VERSION} for arm64-v8a"
make -C "$PROOT_BUILD/src" -f GNUmakefile \
  V=1 \
  VERSION= \
  CC="$CC" LD="$CC" STRIP=: OBJCOPY="$OBJCOPY" OBJDUMP="$OBJDUMP" \
  CPPFLAGS="-D_FILE_OFFSET_BITS=64 -D_GNU_SOURCE -D__STDC_WANT_LIB_EXT1__=1 -I$PROOT_BUILD/src -I$PROOT_BUILD/lib/uthash/include -I$TALLOC_SOURCE" \
  CFLAGS="-O2 -fPIE -fno-ident -fno-asynchronous-unwind-tables -Wno-unused-parameter" \
  LDFLAGS="-fPIE -pie -Wl,-z,noexecstack -L$TALLOC_BUILD -ltalloc -ldl" \
  proot

BUILT="$PROOT_BUILD/src/proot"
[[ -f "$BUILT" ]] || die "PRoot build did not produce an executable"
LOADER_BUILT="$PROOT_BUILD/src/loader/loader"
[[ -f "$LOADER_BUILT" ]] || die "PRoot build did not preserve the ARM64 loader"
"$STRIP" --strip-all "$BUILT"
mkdir -p -- "$OUTPUT"
cp -- "$BUILT" "$OUTPUT/libcodex_proot.so"
chmod 0555 "$OUTPUT/libcodex_proot.so"
cp -- "$LOADER_BUILT" "$OUTPUT/libcodex_proot_loader.so"
chmod 0555 "$OUTPUT/libcodex_proot_loader.so"

sha256=$(shasum -a 256 "$OUTPUT/libcodex_proot.so" | awk '{print $1}')
cat > "$OUTPUT/proot.manifest.json" <<EOF
{
  "schemaVersion": 1,
  "component": "codex-proot",
  "version": "${PROOT_VERSION}",
  "source": "${PROOT_REPOSITORY}",
  "commit": "${PROOT_COMMIT}",
  "target": "arm64-v8a",
  "androidApi": ${ANDROID_API},
  "ndk": "29.0.13846066",
  "sha256": "${sha256}",
  "filename": "libcodex_proot.so"
}
EOF
log "wrote $OUTPUT/libcodex_proot.so"
log "sha256=$sha256"

loader_sha256=$(shasum -a 256 "$OUTPUT/libcodex_proot_loader.so" | awk '{print $1}')
cat > "$OUTPUT/proot-loader.manifest.json" <<EOF
{
  "schemaVersion": 1,
  "component": "codex-proot-loader",
  "version": "${PROOT_VERSION}",
  "source": "${PROOT_REPOSITORY}",
  "commit": "${PROOT_COMMIT}",
  "target": "arm64-v8a",
  "androidApi": ${ANDROID_API},
  "ndk": "29.0.13846066",
  "sha256": "${loader_sha256}",
  "filename": "libcodex_proot_loader.so"
}
EOF
log "wrote $OUTPUT/libcodex_proot_loader.so"
log "loader_sha256=$loader_sha256"
