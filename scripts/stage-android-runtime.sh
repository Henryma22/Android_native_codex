#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# Phase 2 host-driven staging.  This is deliberately a setup tool, not a
# runtime launcher: it only replaces the fixed package-private staging slot
# and never starts, stops, or repairs a runtime process.

usage() {
  cat >&2 <<'USAGE'
Usage:
  stage-android-runtime.sh --staging DIR [--serial SERIAL] [--user-id ID]
    [--package-name PACKAGE]

DIR must be the output of builder/stage-for-device.py and contain exactly the
device staging inputs rootfs/, rootfs.manifest, and runtime.metadata.  The
device path is derived from the installed package's user unless --user-id is
provided explicitly:

  /data/user/<ID>/<PACKAGE>/no_backup/ccpocket-local-codex-v2/staging

PACKAGE is one of the explicitly supported application IDs:
com.k9i.ccpocket, com.k9i.ccpocket.local, or com.k9i.ccpocket.perf. When either --user-id or
--package-name is omitted, the script resolves the unique installed
user/package pair and refuses ambiguity instead of using the foreground-user
value. The operation requires a rooted device (`adb shell su`) and refuses to
run while the runtime has an authenticated instance state.
USAGE
  exit 2
}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
ADB_BIN="${ADB:-adb}"
SERIAL=""
USER_ID=""
PACKAGE_NAME=""
STAGING=""

die() {
  printf 'stage-android-runtime: ERROR: %s\n' "$*" >&2
  exit 1
}

is_sha256() {
  [[ "$1" =~ ^[0-9a-f]{64}$ ]]
}

is_semver() {
  [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

is_supported_package_name() {
  [[ "$1" == com.k9i.ccpocket || "$1" == com.k9i.ccpocket.local || "$1" == com.k9i.ccpocket.perf ]]
}

shell_quote() {
  local value=$1
  printf "'%s'" "${value//\'/\'\\\'\'}"
}

while (($#)); do
  case "$1" in
    --staging)
      (($# >= 2)) || usage
      STAGING=$2
      shift 2
      ;;
    --serial)
      (($# >= 2)) || usage
      SERIAL=$2
      shift 2
      ;;
    --user-id)
      (($# >= 2)) || usage
      USER_ID=$2
      shift 2
      ;;
    --package-name)
      (($# >= 2)) || usage
      PACKAGE_NAME=$2
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      usage
      ;;
  esac
done

[[ -n "$STAGING" ]] || usage
if [[ -n "$PACKAGE_NAME" ]] && ! is_supported_package_name "$PACKAGE_NAME"; then
  die "unsupported package name: $PACKAGE_NAME"
fi
STAGING="$(cd -- "$STAGING" && pwd -P)"
[[ -d "$STAGING" ]] || die "staging directory is missing: $STAGING"
[[ ! -L "$STAGING" ]] || die 'staging directory must not be a symlink'
[[ -d "$STAGING/rootfs" && ! -L "$STAGING/rootfs" ]] || die 'staging rootfs is missing or symlinked'
[[ -f "$STAGING/rootfs.manifest" && ! -L "$STAGING/rootfs.manifest" ]] || die 'staging manifest is missing or symlinked'
[[ -f "$STAGING/runtime.metadata" && ! -L "$STAGING/runtime.metadata" ]] || die 'staging metadata is missing or symlinked'

manifest_sha256="$(sha256sum "$STAGING/rootfs.manifest" | awk '{print $1}')"
is_sha256 "$manifest_sha256" || die 'staging manifest hash is invalid'
(
  cd -- "$STAGING/rootfs"
  sha256sum -c ../rootfs.manifest >/dev/null
) || die 'staging rootfs does not match rootfs.manifest'

metadata_value() {
  local key=$1
  local value
  value="$(awk -F= -v wanted="$key" '$1 == wanted { if (++count > 1) exit 2; print substr($0, index($0, "=") + 1) } END { if (count != 1) exit 3 }' "$STAGING/runtime.metadata")" \
    || die "runtime.metadata has an invalid $key field"
  printf '%s' "$value"
}

runtime_version="$(metadata_value runtime_version)"
node_version="$(metadata_value node_version)"
codex_version="$(metadata_value codex_version)"
bridge_version="$(metadata_value bridge_version)"
metadata_manifest="$(metadata_value manifest_sha256)"
[[ "$runtime_version" == 2 ]] || die 'runtime.metadata runtime_version must be 2'
is_sha256 "$metadata_manifest" && [[ "$metadata_manifest" == "$manifest_sha256" ]] \
  || die 'runtime.metadata manifest_sha256 does not match rootfs.manifest'
is_semver "$node_version" || die 'runtime.metadata node_version is not numeric semver'
is_semver "$codex_version" || die 'runtime.metadata codex_version is not numeric semver'
is_semver "$bridge_version" || die 'runtime.metadata bridge_version is not numeric semver'

command -v "$ADB_BIN" >/dev/null 2>&1 || die "adb is not available: $ADB_BIN"
adb_args=()
[[ -n "$SERIAL" ]] && adb_args=(-s "$SERIAL")
"$ADB_BIN" "${adb_args[@]}" get-state 2>/dev/null | tr -d '\r\n' | grep -qx device \
  || die 'adb device is not in the device state'

if [[ -z "$USER_ID" ]]; then
  # Do not infer the app data owner from the foreground user. A work profile
  # or secondary Android user may be installed while adb's current foreground
  # user points elsewhere. Resolve the actual installed user/package pair and
  # fail closed if the pair is ambiguous.
  mapfile -t installed_users < <(
    "$ADB_BIN" "${adb_args[@]}" shell cmd user list 2>/dev/null |
      tr -d '\r' |
      sed -n 's/.*UserInfo{\([0-9][0-9]*\):.*/\1/p'
  )
else
  [[ "$USER_ID" == 0 || "$USER_ID" =~ ^[1-9][0-9]*$ ]] || \
    die "Android user id must be canonical decimal digits: $USER_ID"
  installed_users=("$USER_ID")
fi

matching_pairs=()
for candidate in "${installed_users[@]}"; do
  if [[ -n "$PACKAGE_NAME" ]]; then
    candidate_packages=("$PACKAGE_NAME")
  else
    candidate_packages=(com.k9i.ccpocket com.k9i.ccpocket.local com.k9i.ccpocket.perf)
  fi
  for candidate_package in "${candidate_packages[@]}"; do
    # Consume the complete package-list stream. With `set -o pipefail`, grep
    # -q can make adb observe a closed pipe after the first match and turn a
    # valid package into a false negative.
    if "$ADB_BIN" "${adb_args[@]}" shell cmd package list packages --user "$candidate" 2>/dev/null |
      tr -d '\r' | grep -Fx "package:$candidate_package" >/dev/null; then
      matching_pairs+=("$candidate:$candidate_package")
    fi
  done
done
if (( ${#matching_pairs[@]} == 1 )); then
  IFS=: read -r USER_ID PACKAGE_NAME <<< "${matching_pairs[0]}"
elif (( ${#matching_pairs[@]} > 1 )); then
  die "supported package is installed for multiple user/package pairs (${matching_pairs[*]}); pass --user-id and --package-name explicitly"
else
  die 'could not resolve a supported installed package; pass --user-id and --package-name explicitly'
fi

base="/data/user/$USER_ID/$PACKAGE_NAME/no_backup/ccpocket-local-codex-v2"
remote_script=$(cat <<REMOTE
set -eu
base=$(shell_quote "$base")
staging="\$base/staging"
run_dir="\$base/run"
if [ -e "\$run_dir/instance" ]; then
  printf '%s\n' 'active runtime state exists; stop it before staging' >&2
  exit 2
fi
[ -e "\$base" ] && [ ! -L "\$base" ] && [ -d "\$base" ] || exit 2
[ -e "\$staging" ] && [ ! -L "\$staging" ] && [ -d "\$staging" ] || true
new="\$base/.staging.\$\$.new"
old="\$base/.staging.\$\$.old"
[ ! -e "\$new" ] && [ ! -e "\$old" ] || exit 2
mkdir "\$new"
cleanup() { rm -rf "\$new"; }
trap cleanup 0 1 2 3 15
tar -xf - -C "\$new"
[ -d "\$new/rootfs" ] && [ ! -L "\$new/rootfs" ] || exit 2
[ -f "\$new/rootfs.manifest" ] && [ ! -L "\$new/rootfs.manifest" ] || exit 2
[ -f "\$new/runtime.metadata" ] && [ ! -L "\$new/runtime.metadata" ] || exit 2
chown -R 0:0 "\$new"
chmod 700 "\$new"
chmod -R go-w "\$new/rootfs"
chmod 444 "\$new/rootfs.manifest" "\$new/runtime.metadata"
if [ -e "\$staging" ]; then
  mv "\$staging" "\$old"
fi
if ! mv "\$new" "\$staging"; then
  [ ! -e "\$staging" ] || exit 2
  [ -e "\$old" ] && mv "\$old" "\$staging"
  exit 2
fi
rm -rf "\$old"
trap - 0 1 2 3 15
printf '%s\n' 'staged'
REMOTE
)

printf 'staging %s (manifest %s) on %s...\n' "$STAGING" "$manifest_sha256" "$base"
tar --numeric-owner --owner=0 --group=0 --format=posix \
  -cf - -C "$STAGING" rootfs rootfs.manifest runtime.metadata |
  # The staging payload is a binary tar stream.  Explicitly disable the shell
  # PTY so Windows adb.exe (when called from WSL) cannot translate or truncate
  # the stream; the same flag is harmless on native Linux adb.
  "$ADB_BIN" "${adb_args[@]}" shell -T su -c "$remote_script" >/dev/null
status=$?
if ((status != 0)); then
  die 'root staging operation failed; no runtime was started'
fi
printf 'stage-android-runtime: staged manifest %s (Node %s, Codex %s, Bridge %s)\n' \
  "$manifest_sha256" "$node_version" "$codex_version" "$bridge_version"
