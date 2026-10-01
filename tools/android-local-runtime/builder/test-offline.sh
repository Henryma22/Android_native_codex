#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/codex-rootfs-test.XXXXXX")"
trap 'rm -rf -- "$TMP_DIR"' EXIT
PYTHON_BIN="${PYTHON_BIN:-python3}"

die() { echo "test-offline: ERROR: $*" >&2; exit 1; }
pass() { echo "test-offline: $*"; }
expect_fail() {
  if "$@" >/dev/null 2>&1; then
    die "command unexpectedly succeeded: $*"
  fi
}

# macOS ships BSD tar, while the deterministic fixture flags below are GNU
# tar-specific. Prefer Homebrew's gtar when available and keep the fixture
# test runnable on a clean macOS installation by falling back to the native
# tar without those optional flags.
TAR_BIN="$(command -v gtar || command -v tar || true)"
[ -n "$TAR_BIN" ] || die "tar is required"
TAR_FIXTURE_ARGS=()
if "$TAR_BIN" --version 2>/dev/null | grep -q 'GNU tar'; then
  TAR_FIXTURE_ARGS=(
    --sort=name
    --mtime='UTC 1970-01-01'
    --owner=0
    --group=0
    --numeric-owner
    --mode=0755
  )
fi

for script in "$SCRIPT_DIR"/*.sh; do
  bash -n "$script"
done
bash -n "$SCRIPT_DIR/../device/proot-finalize-rootfs.sh"
bash -n "$SCRIPT_DIR/../../../scripts/stage-android-runtime.sh"
pass "bash syntax"

mkdir -p "$TMP_DIR/root/bin" "$TMP_DIR/root/usr/bin" "$TMP_DIR/root/tmp"
printf '%s\n' 'fixture' > "$TMP_DIR/root/bin/hello"
chmod 0755 "$TMP_DIR/root/bin/hello"
ln -s ../../bin/hello "$TMP_DIR/root/usr/bin/hello"
chmod 0755 "$TMP_DIR/root/tmp"
# Explicit archive modes keep this fixture deterministic on Windows-mounted
# D: workspaces, whose drvfs metadata may expose every host path as 0777.
"$TAR_BIN" "${TAR_FIXTURE_ARGS[@]}" --create --file=- -C "$TMP_DIR/root" . \
  | gzip --no-name --best > "$TMP_DIR/safe.tar.gz"
SAFE_SHA=$(sha256sum "$TMP_DIR/safe.tar.gz" | awk '{print $1}')
"$PYTHON_BIN" "$SCRIPT_DIR/archive_safety.py" --archive "$TMP_DIR/safe.tar.gz" --expected-sha256 "$SAFE_SHA" --json > "$TMP_DIR/safe.json"
pass "safe archive and pinned hash"
expect_fail "$PYTHON_BIN" "$SCRIPT_DIR/archive_safety.py" --archive "$TMP_DIR/safe.tar.gz" --expected-sha256 "$(printf '%064d' 1)"
# Windows Git Bash normally cannot create an absolute symlink without
# developer-mode privilege. The same archive-policy rejection is covered by
# the Python tar fixtures below; skip only this host-filesystem construction.
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    pass "Windows host cannot create the absolute-link fixture"
    ;;
  *)
    # Some Unix tar/permission combinations can drop an empty directory while
    # normalizing the first archive fixture. Reassert the exact parent before
    # adding the deliberately unsafe absolute link.
    mkdir -p "$TMP_DIR/root/usr/bin"
    ln -s /bin/hello "$TMP_DIR/root/usr/bin/absolute"
    "$TAR_BIN" "${TAR_FIXTURE_ARGS[@]}" --create --file=- -C "$TMP_DIR/root" . \
      | gzip --no-name --best > "$TMP_DIR/absolute-link.tar.gz"
    expect_fail "$PYTHON_BIN" "$SCRIPT_DIR/archive_safety.py" --archive "$TMP_DIR/absolute-link.tar.gz"
    "$PYTHON_BIN" "$SCRIPT_DIR/archive_safety.py" --archive "$TMP_DIR/absolute-link.tar.gz" --allow-internal-absolute-links >/dev/null
    rm -f "$TMP_DIR/root/usr/bin/absolute"
    ;;
esac

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    pass "Windows host cannot create the absolute-link chain fixture"
    ;;
  *)
    # Staging resolves absolute links in chroot coordinates, including a
    # chain such as Debian's zoneinfo/localtime -> /etc/localtime ->
    # /usr/share/... . This must not be interpreted against the host FS.
    mkdir -p "$TMP_DIR/chroot/etc" "$TMP_DIR/chroot/usr/share/zoneinfo/Etc"
    printf '%s' 'utc-fixture' > "$TMP_DIR/chroot/usr/share/zoneinfo/Etc/UTC"
    ln -s Etc/UTC "$TMP_DIR/chroot/usr/share/zoneinfo/UTC"
    ln -s /usr/share/zoneinfo/UTC "$TMP_DIR/chroot/etc/localtime"
    ln -s /etc/localtime "$TMP_DIR/chroot/usr/share/zoneinfo/localtime"
"$PYTHON_BIN" - "$SCRIPT_DIR/stage-for-device.py" "$TMP_DIR/chroot" <<'PY'
import importlib.util
import pathlib
import sys

spec = importlib.util.spec_from_file_location("stage_for_device", sys.argv[1])
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)
root = pathlib.Path(sys.argv[2])
for member in ("etc/localtime", "usr/share/zoneinfo/localtime"):
    resolved = module.resolve_chroot_path(root, member)
    assert resolved == root / "usr/share/zoneinfo/Etc/UTC", (member, resolved)
PY
    pass "chroot absolute symlink chain resolution"
    ;;
esac

printf '%s' 'integrity-fixture' > "$TMP_DIR/integrity.bin"
CODEX_TEST_INTEGRITY=$("$PYTHON_BIN" - "$TMP_DIR/integrity.bin" <<'PY'
import base64
import hashlib
import sys
with open(sys.argv[1], 'rb') as handle:
    print('sha512-' + base64.b64encode(hashlib.sha512(handle.read()).digest()).decode())
PY
)
"$PYTHON_BIN" "$SCRIPT_DIR/verify-integrity.py" "$TMP_DIR/integrity.bin" "$CODEX_TEST_INTEGRITY" >/dev/null
expect_fail "$PYTHON_BIN" "$SCRIPT_DIR/verify-integrity.py" "$TMP_DIR/integrity.bin" "sha512-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=="
pass "npm sha512 integrity"

mkdir -p "$TMP_DIR/codex-package"
printf '%s\n' '{"name":"@openai/codex","version":"0.154.0-linux-arm64","os":["linux"],"cpu":["arm64"]}' > "$TMP_DIR/codex-package/package.json"
mkdir -p "$TMP_DIR/codex-package/vendor/aarch64-unknown-linux-musl/bin"
printf '%s' 'native-fixture' > "$TMP_DIR/codex-package/vendor/aarch64-unknown-linux-musl/bin/codex"
chmod 0755 "$TMP_DIR/codex-package/vendor/aarch64-unknown-linux-musl/bin/codex"
CODEX_INFO=$("$PYTHON_BIN" "$SCRIPT_DIR/codex-package-info.py" "$TMP_DIR/codex-package/package.json" 0.154.0-linux-arm64)
[ "$(printf '%s\n' "$CODEX_INFO" | sed -n '2p')" = vendor/aarch64-unknown-linux-musl/bin/codex ] \
  || die "platform Codex executable was not detected"
pass "linux/arm64 Codex platform package detection"

"$PYTHON_BIN" - "$TMP_DIR" <<'PY'
import io
import os
import sys
import tarfile

root = sys.argv[1]

def make(name, member):
    path = os.path.join(root, name)
    with tarfile.open(path, 'w:gz') as archive:
        archive.addfile(member, io.BytesIO(b'x'))

traversal = tarfile.TarInfo('../escape')
traversal.size = 1
make('traversal.tar.gz', traversal)

setuid = tarfile.TarInfo('setuid')
setuid.mode = 0o4755
setuid.size = 1
make('setuid.tar.gz', setuid)

world = tarfile.TarInfo('world-writable')
world.mode = 0o666
world.size = 1
make('world-writable.tar.gz', world)

special = tarfile.TarInfo('device')
special.type = tarfile.CHRTYPE
special.devmajor = 1
special.devminor = 3
make('special.tar.gz', special)

hardlink = tarfile.TarInfo('hardlink')
hardlink.type = tarfile.LNKTYPE
hardlink.linkname = 'target'
make('hardlink.tar.gz', hardlink)

xattr = tarfile.TarInfo('capability')
xattr.size = 1
xattr.pax_headers = {'SCHILY.xattr.security.capability': 'AQAA'}
make('xattr.tar.gz', xattr)
PY
for bad in traversal setuid world-writable special hardlink xattr; do
    expect_fail "$PYTHON_BIN" "$SCRIPT_DIR/archive_safety.py" --archive "$TMP_DIR/$bad.tar.gz"
done
pass "archive traversal/special/setuid/xattr/world-writable rejection"

"$PYTHON_BIN" "$SCRIPT_DIR/write-manifest.py" \
  --output "$TMP_DIR/fixture.manifest.json" \
  --artifact "$TMP_DIR/safe.tar.gz" \
  --archive-json "$TMP_DIR/safe.json" \
  --node-version 24.19.0 \
  --node-url https://nodejs.org/dist/v24.19.0/node-v24.19.0-linux-arm64.tar.xz \
  --node-sha256 01443c1e1a29e531ccad5a46fefa6df490d2189c49f7955904aecdbb0fe86fdc \
  --codex-version 0.154.0-linux-arm64 \
  --codex-resolved-version 0.154.0 \
  --codex-url https://registry.npmjs.org/@openai/codex/-/codex-0.154.0-linux-arm64.tgz \
  --codex-sha256 1111111111111111111111111111111111111111111111111111111111111111 \
  --codex-integrity sha512-KmTCB6ST484zeYlPpKP/K5P/gRaYmt6TihVD+zotoe6O9q0JSBP+FYvCz4A/zZXR7xDOHURTSjHp0sD8wWS0YQ== \
  --debian-suite bookworm \
  --debian-snapshot 20260821T000000Z \
  --debian-mirror https://snapshot.debian.org/archive/debian/20260821T000000Z/ \
  --debian-keyring-sha256 5555555555555555555555555555555555555555555555555555555555555555
"$SCRIPT_DIR/validate-manifest.sh" "$TMP_DIR/fixture.manifest.json"
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    pass "Windows host skips case-sensitive device staging"
    ;;
  *)
    "$PYTHON_BIN" "$SCRIPT_DIR/stage-for-device.py" \
      --artifact "$TMP_DIR/safe.tar.gz" \
      --manifest "$TMP_DIR/fixture.manifest.json" \
      --output "$TMP_DIR/device-staging" >/dev/null
    test -s "$TMP_DIR/device-staging/rootfs.manifest"
    test -s "$TMP_DIR/device-staging/runtime.metadata"
    grep -Fq 'runtime_version=2' "$TMP_DIR/device-staging/runtime.metadata"
    pass "archive-to-device staging and canonical runtime digest"
    ;;
esac
cp "$TMP_DIR/fixture.manifest.json" "$TMP_DIR/invalid.manifest.json"
"$PYTHON_BIN" - "$TMP_DIR/invalid.manifest.json" <<'PY'
import json
import sys
path = sys.argv[1]
with open(path, encoding='utf-8') as handle:
    value = json.load(handle)
value['components']['node']['sha256'] = 'not-pinned'
with open(path, 'w', encoding='utf-8') as handle:
    json.dump(value, handle)
PY
expect_fail "$SCRIPT_DIR/validate-manifest.sh" "$TMP_DIR/invalid.manifest.json"
cp "$TMP_DIR/fixture.manifest.json" "$TMP_DIR/extra.manifest.json"
"$PYTHON_BIN" - "$TMP_DIR/extra.manifest.json" <<'PY'
import json
import sys
path = sys.argv[1]
with open(path, encoding='utf-8') as handle:
    value = json.load(handle)
value['unexpected'] = True
with open(path, 'w', encoding='utf-8') as handle:
    json.dump(value, handle)
PY
expect_fail "$SCRIPT_DIR/validate-manifest.sh" "$TMP_DIR/extra.manifest.json"
pass "manifest schema and unpinned hash rejection"

# Android/toybox commonly reports every symlink as mode 0777.  A broad
# `find -perm -0002` therefore falsely rejects Debian's ordinary internal
# links (for example /bin -> /usr/bin); the finalizer must inspect only
# regular files and directories.  Keep both a behavioral fixture and a source
# guard here so a future refactor cannot silently restore the broad scan.
SYMLINK_POLICY_ROOT="$TMP_DIR/symlink-policy/root"
mkdir -p "$SYMLINK_POLICY_ROOT/usr/bin"
printf '%s\n' 'target' > "$SYMLINK_POLICY_ROOT/usr/bin/target"
chmod 0644 "$SYMLINK_POLICY_ROOT/usr/bin/target"
ln -s target "$SYMLINK_POLICY_ROOT/usr/bin/link"
SYMLINK_POLICY_LINK="$SYMLINK_POLICY_ROOT/usr/bin/link"
legacy_unsafe=$(find "$SYMLINK_POLICY_LINK" -xdev -perm -0002 -print -quit 2>/dev/null || true)
case "$(uname -s)" in
  Darwin|MINGW*|MSYS*|CYGWIN*)
    # BSD and Windows find implementations do not expose Android/toybox's
    # synthetic 0777 symlink mode, so the historical false-positive probe is
    # not observable on these hosts. The source guard and ordinary-file policy
    # checks remain authoritative.
    pass "host find does not expose the legacy symlink mode probe"
    ;;
  *)
    [ -n "$legacy_unsafe" ] || die 'symlink fixture did not exercise the legacy broad writable scan'
    ;;
esac
ordinary_unsafe=$(find "$SYMLINK_POLICY_LINK" -xdev \( -type f -o -type d \) -perm -0002 -print -quit 2>/dev/null || true)
[ -z "$ordinary_unsafe" ] || die "legal symlink was reported as writable: $ordinary_unsafe"
grep -Fq 'find "$policy_root" -xdev \( -type f -o -type d \) -perm -0002' \
  "$SCRIPT_DIR/../device/proot-finalize-rootfs.sh" \
  || die 'finalizer does not restrict writable scan to ordinary files/directories'
if grep -Fq 'find "$ROOTFS" -xdev -perm -0002' "$SCRIPT_DIR/../device/proot-finalize-rootfs.sh"; then
  die 'finalizer still contains a broad symlink-sensitive writable scan'
fi
pass "finalizer writable policy ignores legal symlinks"

# The independent app path must not silently regain the retired Bridge/MCP
# contract.  Keep this guard close to the offline runtime checks so a renamed
# or copied finalizer cannot reintroduce those inputs.
INDEPENDENT_FINALIZER="$SCRIPT_DIR/../device/proot-finalize-rootfs.sh"
if grep -Eiq 'bridge|websocket|ccpocket|ccpocket-android-mcp' "$INDEPENDENT_FINALIZER"; then
  die 'independent Codex finalizer still contains the retired Bridge contract'
fi
grep -Fq 'MARKER=/var/lib/codex/rootfs-finalized-proot-v1' "$INDEPENDENT_FINALIZER" \
  || die 'independent Codex finalizer does not publish the Codex marker'
grep -Fq 'for required_tool in curl git jq python python3 npm npx; do' "$INDEPENDENT_FINALIZER" \
  || die 'independent Codex finalizer does not enumerate the required development tools'
grep -Fq '"$required_tool" --version' "$INDEPENDENT_FINALIZER" \
  || die 'independent Codex finalizer does not execute the required development tools'
grep -Fq '[ -s /etc/ssl/certs/ca-certificates.crt ]' "$INDEPENDENT_FINALIZER" \
  || die 'independent Codex finalizer does not verify the TLS CA bundle'
grep -Fq 'unsupported-skip-usrmerge-conversion' "$INDEPENDENT_FINALIZER" \
  || die 'independent Codex finalizer does not preserve Debian usr-merge dependency metadata'
if grep -Fq 'remove-usr-is-merged' "$INDEPENDENT_FINALIZER"; then
  die 'independent Codex finalizer still removes the usr-is-merged package'
fi
grep -Fq -- '--include=ca-certificates,git,python3,python-is-python3,bash,coreutils,curl,jq,libkeyutils1,util-linux,tini,libcap2-bin' \
  "$SCRIPT_DIR/build-rootfs.sh" \
  || die 'rootfs package set is missing a required command or curl library dependency'
grep -Fq 'codex-android-local-rootfs' "$SCRIPT_DIR/rootfs-manifest.schema.json" \
  || die 'rootfs schema is not in the independent Codex namespace'
GUEST_ADMIN_SCRIPT="$SCRIPT_DIR/../../../apps/codex/android/app/src/main/assets/codex-guest-admin/sudo"
root_sudo_probe=$(sed 's|/usr/bin/id -u 2>/dev/null|printf 0|' "$GUEST_ADMIN_SCRIPT" \
  | bash -s -- printf codex-root-sudo-pass-through)
[ "$root_sudo_probe" = 'codex-root-sudo-pass-through' ] \
  || die 'Root PRoot sudo does not transparently execute as the existing Root identity'
INDEPENDENT_INSTALLER="$SCRIPT_DIR/../install-independent-compatibility-rootfs.ps1"
if grep -Eiq 'bridge|websocket|ccpocket|ccpocket-android-mcp' "$INDEPENDENT_INSTALLER"; then
  die 'independent compatibility installer still contains the retired Bridge contract'
fi
grep -Fq 'cp -a "$base/home/." "$home/"' "$INDEPENDENT_INSTALLER" \
  || die 'independent compatibility installer does not preserve the existing guest home during rootfs updates'
grep -Fq 'existing guest home is not a real directory; refusing to replace it' "$INDEPENDENT_INSTALLER" \
  || die 'independent compatibility installer can replace a non-directory guest home'
CODEX_APP_ROOT="$SCRIPT_DIR/../../.."
if command -v rg >/dev/null 2>&1; then
  retired_app_names=$(rg -n -i 'libccpocket|ccpocket-host|var/lib/ccpocket|ccpocket-android-mcp' \
    "$CODEX_APP_ROOT/apps/codex/android/app/src/main" || true)
else
  retired_app_names=$(grep -R -n -E -i 'libccpocket|ccpocket-host|var/lib/ccpocket|ccpocket-android-mcp' \
    "$CODEX_APP_ROOT/apps/codex/android/app/src/main" || true)
fi
if [ -n "$retired_app_names" ]; then
  die 'independent Android app still contains retired runtime asset names'
fi
for installer in \
  "$SCRIPT_DIR/../install-independent-compatibility-rootfs.ps1"; do
  [ -f "$installer" ] || die "independent installer is missing: $installer"
  if grep -Fq 'wait-for-device' "$installer"; then
    die "independent installer still has an unbounded adb wait: $installer"
  fi
  grep -Fq 'DeviceWaitSeconds' "$installer" \
    || die "independent installer has no bounded device wait: $installer"
  grep -Fq 'Wait-ForAdbDevice' "$installer" \
    || die "independent installer has no device readiness helper: $installer"
done
pass "independent Codex runtime excludes retired Bridge inputs"

expect_fail "$SCRIPT_DIR/build-rootfs.sh"
expect_fail "$SCRIPT_DIR/build-rootfs.sh" --output "$TMP_DIR/no-codex-hash" --node-tarball "$TMP_DIR/safe.tar.gz"
"$SCRIPT_DIR/build-rootfs.sh" --help >/dev/null

grep -Fq 'util-linux,tini' "$SCRIPT_DIR/build-rootfs.sh" || die 'build script does not pin util-linux,tini'
pass "parameter/path guards, runtime contract, and no-network help paths"

echo "test-offline: all checks passed"
