#!/system/bin/sh
set -eu

# Installs a manifest-verified Debian ARM64 rootfs into the app's fixed
# compatibility slot. The caller copies both assets here and invokes this
# script through the user's normal KernelSU su profile.
base=${1-}
stage=${2-}
uid=${3-}
native_dir=${4-}
digest=${5-}
runtime_version=${6-}
expected_node=${7-}
expected_codex=${8-}
install_id=${9-}

die() {
  printf '%s\n' "codex-rootfs-installer: error: $*" >&2
  exit 1
}

[ "$#" -eq 9 ] || die 'fixed argument count is invalid'
case "$base" in
  /data/user/[0-9]*/io.henry.codex/no_backup/codex-compatibility-v1) ;;
  *) die 'runtime base is outside the fixed app-private path' ;;
esac
case "$stage" in
  /data/user/[0-9]*/io.henry.codex/cache/codex-rootfs-install-*) ;;
  *) die 'staging directory is outside the app-private cache' ;;
esac
case "$uid" in ''|*[!0-9]*) die 'app uid is invalid' ;; esac
case "$digest" in
  ????????*) : ;;
  *) die 'archive digest is invalid' ;;
esac
[ "${#digest}" -eq 64 ] || die 'archive digest length is invalid'
case "$digest" in *[!0123456789abcdef]*) die 'archive digest is invalid' ;; esac
case "$runtime_version$expected_node$expected_codex" in
  *[!A-Za-z0-9._+-]*) die 'runtime version contains unsafe characters' ;;
esac
case "$install_id" in ''|*[!0123456789abcdef]*) die 'install id is invalid' ;; esac
[ "${#install_id}" -eq 32 ] || die 'install id length is invalid'

no_backup=${base%/codex-compatibility-v1}
data=${no_backup%/no_backup}
slots="$base/rootfs-slots"
new="$slots/$install_id"
rootfs="$new/rootfs"
home="$base/home"
temp="$new/proot-tmp"
finalizer_bin="$temp/finalizer-bin"
finalizer_lib="$temp/finalizer-lib"
finalizer_sbin="$temp/finalizer-sbin"
finalizer="$stage/proot-finalize-rootfs.sh"
active_slot="$base/active-rootfs-slot"
active_slot_tmp="$base/.active-rootfs-slot-$install_id"

cleanup_install() {
  status=$?
  trap - 0 1 2 3 15
  if [ "$status" -ne 0 ]; then
    if [ -d "$new" ] && [ ! -L "$new" ]; then rm -rf "$new" || :; fi
    rm -f "$active_slot_tmp" || :
  fi
  exit "$status"
}
trap cleanup_install 0 1 2 3 15

[ -d "$stage" ] && [ ! -L "$stage" ] || die 'staging directory is missing or unsafe'
[ -f "$stage/rootfs.tar.gz" ] && [ ! -L "$stage/rootfs.tar.gz" ] || die 'rootfs archive is missing'
[ -f "$stage/runtime.manifest.json" ] && [ ! -L "$stage/runtime.manifest.json" ] || die 'runtime manifest is missing'
[ -f "$finalizer" ] && [ ! -L "$finalizer" ] || die 'ARM64 finalizer asset is missing'
[ -f "$stage/install-proot-rootfs.sh" ] && [ ! -L "$stage/install-proot-rootfs.sh" ] || die 'installer asset is missing'
[ -d "$no_backup" ] && [ ! -L "$no_backup" ] || die 'app-private runtime parent is missing or unsafe'
[ ! -e "$base" ] && mkdir -m 700 "$base" || :
[ -d "$base" ] && [ ! -L "$base" ] || die 'compatibility runtime base is not a real directory'
[ -d "$slots" ] || mkdir -m 700 "$slots"
[ ! -L "$slots" ] || die 'rootfs slots directory is a symlink'
[ ! -e "$new" ] && [ ! -L "$new" ] || die 'staging runtime slot already exists'
[ ! -e "$active_slot_tmp" ] && [ ! -L "$active_slot_tmp" ] || die 'active rootfs pointer staging file already exists'
[ -e "$home" ] || mkdir -m 700 "$home"
[ -d "$home" ] && [ ! -L "$home" ] || die 'guest home is not a real directory'
[ ! -L "$active_slot" ] || die 'active rootfs pointer is a symlink'

if [ -d "$native_dir/arm64" ]; then native_dir="$native_dir/arm64"; fi
proot="$native_dir/libcodex_proot.so"
loader="$native_dir/libcodex_proot_loader.so"
trampoline="$native_dir/libcodex_host_trampoline.so"
[ -f "$proot" ] && [ -f "$loader" ] && [ -f "$trampoline" ] || die 'packaged PRoot assets are missing'

label=$(ls -Zd "$no_backup" | awk '{print $1}')
case "$label" in u:object_r:app_data_file:s0*) : ;; *) die 'app-private SELinux label is unavailable' ;; esac

mkdir -m 700 "$new"
mkdir -p "$rootfs" "$home" "$temp"
tar -xzf "$stage/rootfs.tar.gz" -C "$rootfs"
[ ! -L "$rootfs" ] || die 'rootfs directory is unsafe'
[ -f "$rootfs/usr/bin/dash" ] || die 'rootfs shell is missing'
[ -f "$rootfs/usr/bin/true" ] || die 'rootfs probe utility is missing'
[ -f "$rootfs/usr/lib/aarch64-linux-gnu/ld-linux-aarch64.so.1" ] || die 'ARM64 Linux loader is missing'
[ -f "$rootfs/opt/node/bin/node" ] || die 'Node.js is missing'
[ -d "$rootfs/opt/codex/lib/node_modules/@openai/codex" ] || die 'Codex package is missing'
[ -e "$rootfs/usr/local/bin/codex" ] || die 'Codex launcher is missing'

cp "$finalizer" "$rootfs/.codex-proot-finalize-v1"
chmod 700 "$rootfs/.codex-proot-finalize-v1"
chcon "$label" "$base" "$slots" "$new"
chcon -Rh "$label" "$rootfs" "$home" "$temp"
chmod 700 "$home" "$temp"
chown "$uid:$uid" "$base" "$slots" "$new" "$home" "$temp"

# Debian's foreign archive uses merged-/usr aliases. Build temporary FHS
# projections for the second stage, then remove them before activation.
mkdir -p "$finalizer_bin" "$finalizer_lib" "$finalizer_sbin"
cp -a "$rootfs/usr/bin/." "$finalizer_bin/"
rm -f "$finalizer_bin/sh"
cp "$finalizer_bin/dash" "$finalizer_bin/sh"
cp -a "$rootfs/usr/lib/." "$finalizer_lib/"
cp -a "$rootfs/usr/sbin/." "$finalizer_sbin/"
chcon -Rh "$label" "$finalizer_bin" "$finalizer_lib" "$finalizer_sbin"

export PATH=/opt/node/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export HOME=/home/codex TMPDIR=/tmp PROOT_NO_SECCOMP=1
export PROOT_LOADER="$loader" PROOT_TMP_DIR="$temp"

run_guest() {
  "$proot" --link2symlink --kill-on-exit --rootfs="$rootfs" \
    --bind="$rootfs/usr/bin:/bin!" \
    --bind="$rootfs/usr/bin/dash:/bin/sh!" \
    --bind="$rootfs/usr/lib:/lib!" \
    --bind="$rootfs/usr/lib/aarch64-linux-gnu:/lib/aarch64-linux-gnu!" \
    --bind="$rootfs/usr/lib/aarch64-linux-gnu/ld-linux-aarch64.so.1:/lib/ld-linux-aarch64.so.1!" \
    --bind="$rootfs/usr/sbin:/sbin!" \
    --bind="$trampoline:/codex-host-trampoline" \
    --bind=/proc:/proc --bind="$home:/home/codex!" --bind="$temp:/tmp!" \
    --cwd=/home/codex --root-id /codex-host-trampoline "$@"
}

run_finalizer() {
  "$proot" --kill-on-exit --rootfs="$rootfs" \
    --bind="$finalizer_bin:/bin!" --bind="$finalizer_sbin:/sbin!" \
    --bind="$finalizer_lib:/lib!" --bind="$trampoline:/codex-host-trampoline" \
    --bind=/proc:/proc --bind="$home:/home/codex!" --bind="$temp:/tmp!" \
    --cwd=/home/codex --root-id /codex-host-trampoline \
    /.codex-proot-finalize-v1 "$expected_node" "$expected_codex" "$base" "$digest"
}

if ! finalizer_output=$(run_finalizer 2>&1); then
  printf '%s\n' 'ARM64 PRoot rootfs finalization failed' >&2
  printf '%s\n' "$finalizer_output" >&2
  exit 30
fi
[ -f "$rootfs/var/lib/codex/rootfs-finalized-proot-v1" ] || die 'finalizer did not write its success marker'
rm -f "$rootfs/.codex-proot-finalize-v1"
rm -rf "$finalizer_bin" "$finalizer_lib" "$finalizer_sbin"

chcon -Rh "$label" "$rootfs" "$home" "$temp" || die 'post-finalization SELinux relabel failed'
run_guest /usr/bin/true >/dev/null || die 'PRoot guest probe failed'
node_output=$(run_guest /opt/node/bin/node --version 2>&1) || die 'Node.js guest probe failed'
case "$node_output" in *"$expected_node"*) : ;; *) die 'Node.js guest version does not match the manifest' ;; esac
codex_output=$(run_guest /usr/local/bin/codex --version 2>&1) || die 'Codex guest probe failed'
case "$codex_output" in *"${expected_codex%%-linux-arm64}"*) : ;; *) die 'Codex guest version does not match the manifest' ;; esac

cp "$stage/runtime.manifest.json" "$new/runtime.manifest.json"
chcon "$label" "$new/runtime.manifest.json"
chown "$uid:$uid" "$new/runtime.manifest.json"
chmod 644 "$new/runtime.manifest.json"

# Publish only a tiny pointer after the new immutable slot has passed every
# guest probe. Existing workers already hold the previous absolute rootfs
# path, so they continue using it while future launches resolve this slot.
printf '%s\n' "$install_id" > "$active_slot_tmp"
chcon "$label" "$active_slot_tmp"
chown "$uid:$uid" "$active_slot_tmp"
chmod 644 "$active_slot_tmp"
mv -f "$active_slot_tmp" "$active_slot" || die 'verified compatibility rootfs could not be activated'
printf '%s\n' 'state=verified' "runtime=$runtime_version" "node=$node_output" "codex=$codex_output"
