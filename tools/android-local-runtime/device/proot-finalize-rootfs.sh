#!/bin/sh
set -eu

# This script runs inside the verified ARM64 PRoot view as Linux fake-root.
# It is the only supported device finalizer: it never mounts an Android path,
# never calls KernelSU, and never accepts a host shell command.
# The host runner supplies only the pinned component versions, the canonical
# v3 runtime base, and the already verified archive digest as argv values.

EXPECTED_NODE=${1-}
EXPECTED_CODEX=${2-}
RUNTIME_BASE=${3-}
DIGEST=${4-}
FINALIZER_STAGE=1

die() {
  printf '%s\n' "codex-proot-finalizer: error: $*" >&2
  exit "$FINALIZER_STAGE"
}

is_semver() {
  value=$1
  case "$value" in
    ''|*[!0-9.]*|*.*.*.*|.*|*.|*..*) return 1 ;;
  esac
  old_ifs=$IFS
  IFS=.
  set -- $value
  IFS=$old_ifs
  [ "$#" -eq 3 ] || return 1
  for component in "$@"; do
    case "$component" in
      ''|*[!0-9]*) return 1 ;;
    esac
  done
  return 0
}

is_codex_version() {
  value=$1
  case "$value" in
    *-linux-arm64)
      is_semver "${value%-linux-arm64}"
      ;;
    *)
      is_semver "$value"
      ;;
  esac
}

[ "$#" -eq 4 ] || die 'fixed argument count is invalid'
is_semver "$EXPECTED_NODE" || die 'Node version is invalid'
is_codex_version "$EXPECTED_CODEX" || die 'Codex version is invalid'
case "$DIGEST" in
  ????????*) : ;;
  *) die 'rootfs digest is invalid' ;;
esac
[ "${#DIGEST}" -eq 64 ] || die 'rootfs digest length is invalid'
case "$DIGEST" in
  *[!0123456789abcdef]*) die 'rootfs digest is not lowercase hexadecimal' ;;
esac

case "$RUNTIME_BASE" in
  /data/user/*/io.henry.codex/no_backup/codex-compatibility-v1) ;;
  *) die 'runtime base is not a fixed package-private path' ;;
esac

require_file() {
  path=$1
  [ -f "$path" ] || die "required rootfs file is missing"
  [ ! -L "$path" ] || die 'required rootfs file is a symlink'
}

require_executable() {
  path=$1
  [ -e "$path" ] || die 'required rootfs executable is missing'
  resolved=$path
  if [ -L "$path" ]; then
    link_target=$(readlink "$path" 2>/dev/null) || die 'required rootfs executable link cannot be read'
    # The bundled Codex launcher is intentionally a relative symlink.  PRoot
    # can execute it, but readlink -f can report a false negative for the
    # root-owned target in Android app-private storage.  Accept only this
    # exact immutable target; all other links still use the normal resolver.
    if [ "$path:$link_target" = \
      "/usr/local/bin/codex:../../../opt/codex/lib/node_modules/@openai/codex/vendor/aarch64-unknown-linux-musl/bin/codex" ]; then
      return 0
    fi
    resolved=$(readlink -f "$path" 2>/dev/null) || die 'required rootfs executable link cannot be resolved'
    case "$resolved" in
      /proc/*|/dev/*|/sys/*|/run/*|/tmp/*|/home/*|/workspaces/*) \
        die 'required rootfs executable link escapes immutable rootfs' ;;
    esac
  fi
  [ -f "$resolved" ] || die 'required rootfs executable target is not a regular file'
  # PRoot on Android app-private storage can report a false negative for
  # access(2)/stat execute checks on root-owned guest files even when execve
  # succeeds.  The callers below perform the actual version/help/second-stage
  # invocation, so keep the type and symlink checks here and let execution be
  # the compatibility proof instead of rejecting a runnable file.
}

has_executable_mode() {
  path=$1
  [ -f "$path" ] || return 1
  mode=$(stat -c '%A' "$path" 2>/dev/null) || return 1
  case "$mode" in
    *x*) return 0 ;;
    *) return 1 ;;
  esac
}

require_executable /opt/node/bin/node
root_uid=$(/opt/node/bin/node -e 'process.stdout.write(String(process.getuid()))' 2>/dev/null) || \
  die 'PRoot fake-root identity is unavailable'
[ "$root_uid" = 0 ] || die 'PRoot fake-root identity is unavailable'

FINALIZER_STAGE=10
require_executable /debootstrap/debootstrap
FINALIZER_STAGE=11
require_executable /opt/node/bin/node
FINALIZER_STAGE=12
require_executable /usr/local/bin/codex
FINALIZER_STAGE=13
require_executable /usr/bin/env
FINALIZER_STAGE=14
require_executable /usr/bin/setpriv

# Let debootstrap consume the foreign package set and verify `/usr/bin/tini`
# after its second stage. A host-side archive preflight is redundant and can
# disagree with the Android PRoot mount view.
FINALIZER_STAGE=20
for marker_parent in /var /var/lib /var/lib/codex; do
  [ ! -L "$marker_parent" ] || die 'marker parent is a symlink'
done
MARKER=/var/lib/codex/rootfs-finalized-proot-v1
MARKER_TMP=${MARKER}.tmp.$$
MARKER_CLEANUP_ARMED=1
DEBOOTSTRAP_COMPAT_DIR=/.codex-debootstrap-compat-v1
cleanup() {
  status=$?
  trap - 0 1 2 3 15
  if [ -d "$DEBOOTSTRAP_COMPAT_DIR" ] && [ ! -L "$DEBOOTSTRAP_COMPAT_DIR" ]; then
    rm -rf "$DEBOOTSTRAP_COMPAT_DIR" 2>/dev/null || true
  fi
  if [ "$MARKER_CLEANUP_ARMED" -eq 1 ] && [ "$status" -ne 0 ]; then
    rm -f "$MARKER" "$MARKER_TMP" 2>/dev/null || true
  fi
  exit "$status"
}
trap cleanup 0
if [ -e "$MARKER" ] || [ -L "$MARKER" ]; then
  rm -f "$MARKER" || die 'cannot remove the old compatibility marker'
fi

# The archive is a Debian foreign first stage. PRoot supplies the Linux view
# and fake root identity; no Android mount or privileged helper is needed for
# the package second stage.
if [ -e "$DEBOOTSTRAP_COMPAT_DIR" ] || [ -L "$DEBOOTSTRAP_COMPAT_DIR" ]; then
  FINALIZER_STAGE=24
  [ ! -L "$DEBOOTSTRAP_COMPAT_DIR" ] || die 'debootstrap compatibility directory is a symlink'
  rm -rf "$DEBOOTSTRAP_COMPAT_DIR" || die 'cannot clear debootstrap compatibility directory'
fi
FINALIZER_STAGE=25
mkdir "$DEBOOTSTRAP_COMPAT_DIR" || die 'cannot create debootstrap compatibility directory'
FINALIZER_STAGE=26
cp -a /debootstrap/. "$DEBOOTSTRAP_COMPAT_DIR/" || die 'cannot copy debootstrap helper files'

rewrite_debootstrap_text() {
  operation=$1
  shift
  /opt/node/bin/node - "$operation" "$@" <<'NODE'
const fs = require('fs');

const operation = process.argv[2];
const paths = process.argv.slice(3);
const operations = new Set(['path-exec', 'sbin']);
if (!operations.has(operation) || paths.length === 0) process.exit(2);

for (const path of paths) {
  const original = fs.readFileSync(path, 'utf8');
  let updated;
  if (operation === 'path-exec') {
    updated = original.split('[ -x "$dir/').join('[ -f "$dir/');
  } else {
    updated = original.split('$TARGET/sbin/').join('$TARGET/usr/sbin/');
  }
  fs.writeFileSync(path, updated);
}
NODE
}

FINALIZER_STAGE=27
# PRoot reports a false negative for access(2) execute checks on root-owned
# guest files.  The original `in_path` function is used while `functions`
# is being sourced to initialize `PKGDETAILS`, so appending an override after
# the file has been sourced is too late.  Patch the copied helper before
# launching debootstrap; this keeps every PATH probe on the same
# file-existence rule and lets debootstrap define its in-tree
# `pkgdetails_perl` implementation.
rewrite_debootstrap_text path-exec "$DEBOOTSTRAP_COMPAT_DIR/functions" || \
  die 'debootstrap PATH probe compatibility patch failed'
FINALIZER_STAGE=28
patched_in_path=0
while IFS= read -r debootstrap_function_line; do
  case "$debootstrap_function_line" in
    *'if [ -f "$dir/$1" ]; then'*) patched_in_path=1; break ;;
  esac
done < "$DEBOOTSTRAP_COMPAT_DIR/functions"
[ "$patched_in_path" -eq 1 ] || die 'debootstrap PATH probe patch was not applied'
# PRoot presents the verified app-private rootfs as the guest root, but it
# cannot create Android device nodes or change the host mount flags. Skip only
# debootstrap's host-mount sanity probe; no mount or device operation is
# enabled by this compatibility finalizer.
FINALIZER_STAGE=29
printf '%s\n' 'check_sane_mount() { return 0; }' >> "$DEBOOTSTRAP_COMPAT_DIR/functions" || \
  die 'debootstrap mount probe compatibility patch was not applied'
# The foreign image already has Debian's merged-/usr layout.  Bookworm still
# requires the `usr-is-merged` marker package to satisfy dependencies such as
# `init-system-helpers`; omitting it leaves dpkg in a permanently broken state
# and makes an ordinary guest `apt install` fail.  Debian's supported way to
# keep an already-merged image from running the conversion helper is the same
# marker used by debootstrap/mmdebstrap.  Keep the package in the second-stage
# set, but explicitly tell its maintainer logic that conversion is unnecessary.
USR_MERGE_SKIP=/etc/unsupported-skip-usrmerge-conversion
if [ -e "$USR_MERGE_SKIP" ] || [ -L "$USR_MERGE_SKIP" ]; then
  [ -f "$USR_MERGE_SKIP" ] && [ ! -L "$USR_MERGE_SKIP" ] || \
    die 'usr-merge skip marker is not a regular file'
fi
printf '%s\n' 'this system will not be supported in the future' > "$USR_MERGE_SKIP" || \
  die 'cannot write usr-merge skip marker'
chmod 0644 "$USR_MERGE_SKIP" || die 'cannot set usr-merge skip marker mode'
# The extracted image keeps Debian's recorded `minbase` variant, while this
# compatibility runner must use debootstrap's fakechroot path. The
# `--variant` command-line value is not consulted during --second-stage when
# the recorded variant file exists, so update only the copied compatibility
# metadata, never the verified rootfs archive.
FINALIZER_STAGE=29
printf '%s\n' 'fakechroot' > "$DEBOOTSTRAP_COMPAT_DIR/variant" || \
  die 'cannot select fakechroot compatibility variant'
# The installer replaces the merged-/usr /sbin symlink with an empty regular
# mountpoint so PRoot does not traverse Android app-data symlinks. Debian's
# fakechroot helper still addresses two files through $TARGET/sbin; redirect
# only those fixed target paths to their canonical /usr/sbin locations.
# Android app-data SELinux can deny the guest `sed` dynamic loader while the
# same PRoot view is preparing debootstrap. Node is already required and
# verified above, so use its fixed filesystem API for this literal rewrite.
rewrite_debootstrap_text sbin \
  "$DEBOOTSTRAP_COMPAT_DIR/functions" "$DEBOOTSTRAP_COMPAT_DIR/debian-common" || \
  die 'debootstrap sbin compatibility patch failed'
DEBOOTSTRAP_DIR="$DEBOOTSTRAP_COMPAT_DIR"
export DEBOOTSTRAP_DIR
# The PRoot view supplies the fake-root/path behavior itself. Debian's
# fakechroot variant still requires this explicit environment marker before
# it will enter the second-stage package configuration path.
FAKECHROOT=true
export FAKECHROOT
# The bundled foreign image contains the first-stage bootstrap transcript.
# Clear it so the bounded diagnostic classifier below describes this
# second-stage run instead of stale asset text.
FINALIZER_STAGE=29
: > /debootstrap/debootstrap.log || die 'cannot reset debootstrap log'
# The foreign first stage leaves base-passwd's unregistered helper in place.
# dpkg must make a backup link before replacing it, but Android app-data does
# not support that link operation through PRoot. Remove only this known file;
# the pinned base-passwd package immediately restores it during second stage.
FINALIZER_STAGE=30
rm -f /usr/sbin/update-passwd || die 'cannot clear base-passwd helper'
if ! /debootstrap/debootstrap --second-stage --variant=fakechroot; then
  # debootstrap intentionally records its full output in its guest log.
  # Emit only fixed categories into the already-discarded native diagnostic
  # pipe; never forward the log text or package names.
  debootstrap_log_found=0
  for debootstrap_log in \
    /debootstrap/debootstrap.log \
    /var/log/bootstrap.log \
    /var/log/debootstrap/debootstrap.log; do
    if [ -f "$debootstrap_log" ]; then
      debootstrap_log_found=1
      printf '%s\n' 'codex-debootstrap-log-present' >&2
      if grep -Eiq 'status-old|hard link|permission denied' "$debootstrap_log"; then
        printf '%s\n' 'codex-dpkg-hardlink-permission-denied' >&2
      fi
      if grep -Eiq 'not found|pkgdetails' "$debootstrap_log"; then
        printf '%s\n' 'codex-debootstrap-command-not-found' >&2
      fi
      if grep -Eiq 'usr-is-merged|self-referential' "$debootstrap_log"; then
        printf '%s\n' 'codex-debootstrap-usr-layout-error' >&2
      fi
      break
    fi
  done
  if [ "$debootstrap_log_found" -eq 0 ]; then
    printf '%s\n' 'codex-debootstrap-log-missing' >&2
  fi
  die 'Debian second stage failed'
fi
rm -rf "$DEBOOTSTRAP_COMPAT_DIR" || die 'cannot remove debootstrap compatibility directory'
DEBOOTSTRAP_COMPAT_DIR=

FINALIZER_STAGE=31
require_executable /usr/bin/setpriv
FINALIZER_STAGE=32
require_executable /usr/bin/tini

# `/run` and `/tmp` are fixed writable PRoot runtime binds, not immutable
# archive content.  Scanning them from inside the guest can report a missing
# host-side bind entry and incorrectly fail the rootfs policy check.
ROOTFS_POLICY_ROOTS='/boot /etc /opt /root /srv /usr /var'

clear_privilege_bits() {
  for policy_root in $ROOTFS_POLICY_ROOTS; do
    [ -e "$policy_root" ] || continue
    find "$policy_root" -xdev \( -type f -o -type d \) -perm /6000 -exec chmod ug-s {} + 2>/dev/null || return 1
  done
}

find_unsafe_privilege() {
  for policy_root in $ROOTFS_POLICY_ROOTS; do
    [ -e "$policy_root" ] || continue
    unsafe=$(find "$policy_root" -xdev \( -type f -o -type d \) -perm /6000 -print -quit 2>/dev/null) || return 1
    [ -z "$unsafe" ] || {
      printf '%s\n' "$unsafe"
      return 0
    }
  done
}

find_unsafe_writable() {
  for policy_root in $ROOTFS_POLICY_ROOTS; do
    [ -e "$policy_root" ] || continue
    unsafe=$(find "$policy_root" -xdev \( -type f -o -type d \) -perm -0002 -print -quit 2>/dev/null) || return 1
    [ -z "$unsafe" ] || {
      printf '%s\n' "$unsafe"
      return 0
    }
  done
}

find_unsafe_special() {
  for policy_root in $ROOTFS_POLICY_ROOTS; do
    [ -e "$policy_root" ] || continue
    unsafe=$(find "$policy_root" -xdev \( -type b -o -type c -o -type p -o -type s \) -print -quit 2>/dev/null) || return 1
    [ -z "$unsafe" ] || {
      printf '%s\n' "$unsafe"
      return 0
    }
  done
}

# Apply the same immutable-image policy as the rooted finalizer. PRoot maps
# these operations into the app-private pending slot, not into Android system
# paths.
clear_privilege_bits || \
  die 'cannot clear privilege bits'
unsafe=$(find_unsafe_privilege) || \
  die 'cannot inspect privilege bits'
[ -z "$unsafe" ] || die 'privilege bit remains in rootfs'
for policy_root in $ROOTFS_POLICY_ROOTS; do
  [ -e "$policy_root" ] || continue
  find "$policy_root" -xdev \( -type f -o -type d \) -perm /002 -exec chmod go-w {} + 2>/dev/null || \
    die 'cannot normalize writable bits'
done
unsafe=$(find_unsafe_writable) || \
  die 'cannot inspect writable bits'
[ -z "$unsafe" ] || die 'world-writable rootfs entry remains'
unsafe=$(find_unsafe_special) || \
  die 'cannot inspect rootfs special files'
[ -z "$unsafe" ] || die 'rootfs contains a special file'

if has_executable_mode /sbin/getcap; then
  getcap=/sbin/getcap
elif has_executable_mode /usr/sbin/getcap; then
  getcap=/usr/sbin/getcap
else
  die 'rootfs getcap is missing'
fi
# The PRoot view intentionally binds Android /proc, /dev and /sys. A recursive
# scan from `/` would walk those host trees and can remain busy indefinitely;
# scan only the immutable rootfs subtrees.
capabilities=
for capability_root in $ROOTFS_POLICY_ROOTS /debootstrap; do
  [ -e "$capability_root" ] || continue
  found=$($getcap -r "$capability_root" 2>/dev/null) || die 'rootfs capability inspection failed'
  [ -z "$found" ] || capabilities=${capabilities}${found}
done
[ -z "$capabilities" ] || die 'rootfs contains Linux capabilities'

setpriv_help=$(/usr/bin/setpriv --help 2>&1) || die 'setpriv could not execute'
for required_flag in --reuid --regid --clear-groups --inh-caps --ambient-caps \
  --bounding-set --securebits --no-new-privs; do
  case "$setpriv_help" in
    *"$required_flag"*) ;;
    *) die 'setpriv lacks a required privilege-drop flag' ;;
  esac
done

node_version=$(/opt/node/bin/node --version 2>/dev/null) || die 'Node version probe failed'
[ "$node_version" = "v$EXPECTED_NODE" ] || die 'Node version does not match the manifest'

codex_output=$(/usr/local/bin/codex --version 2>/dev/null) || die 'Codex version probe failed'
[ -n "$codex_output" ] || die 'Codex version output is empty'
codex_expected_semver=${EXPECTED_CODEX%%-linux-arm64}
case "$codex_output" in
  *"$codex_expected_semver"*) ;;
  *) die 'Codex version does not match the manifest' ;;
esac

# These commands are part of the user-visible Android guest contract, not
# merely packages downloaded into the foreign first-stage cache.  Probe them
# after Debian's second stage so missing package configuration or shared
# libraries is reported during installation instead of surfacing later as a
# generic network/tool failure in a session.
for required_tool in curl git jq python python3 npm npx; do
  command -v "$required_tool" >/dev/null 2>&1 || die 'a required development tool is missing'
  "$required_tool" --version >/dev/null 2>&1 || die 'a required development tool could not start'
done
[ -s /etc/ssl/certs/ca-certificates.crt ] || die 'TLS CA bundle is missing'

debian_snapshot=
for source in /etc/apt/sources.list /etc/apt/sources.list.d/* /debootstrap/debootstrap; do
  [ -f "$source" ] || continue
  candidate=$(/opt/node/bin/node - "$source" <<'NODE'
const fs = require('fs');
const text = fs.readFileSync(process.argv[2], 'utf8');
const match = text.match(/snapshot\.debian\.org\/archive\/debian\/([0-9]{8}T[0-9]{6}Z)/);
if (match) process.stdout.write(match[1]);
NODE
  ) || die 'Debian snapshot could not be read'
  [ -n "$candidate" ] || continue
  if [ -n "$debian_snapshot" ] && [ "$candidate" != "$debian_snapshot" ]; then
    die 'rootfs contains conflicting Debian snapshots'
  fi
  debian_snapshot=$candidate
done
case "$debian_snapshot" in
  [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]T[0-9][0-9][0-9][0-9][0-9][0-9]Z) ;;
  *) die 'Debian snapshot is missing' ;;
esac

if [ -e /var/lib/codex ] || [ -L /var/lib/codex ]; then
  [ -d /var/lib/codex ] && [ ! -L /var/lib/codex ] || die 'marker directory is unsafe'
else
  mkdir -p /var/lib/codex || die 'cannot create marker directory'
fi
rm -f "$MARKER_TMP" || die 'cannot clear marker temporary path'
umask 022
{
  printf 'status=finalized\n'
  printf 'node_actual_version=%s\n' "${node_version#v}"
  printf 'codex_actual_version=%s\n' "$EXPECTED_CODEX"
  printf 'debian_foreign_snapshot=%s\n' "$debian_snapshot"
  printf 'runtime_base=%s\n' "$RUNTIME_BASE"
  printf 'digest=%s\n' "$DIGEST"
} > "$MARKER_TMP" || die 'cannot write compatibility marker'
chmod 0444 "$MARKER_TMP" || die 'cannot protect compatibility marker'
mv -f "$MARKER_TMP" "$MARKER" || die 'cannot publish compatibility marker'
MARKER_CLEANUP_ARMED=0
trap - 0 1 2 3 15
exit 0
