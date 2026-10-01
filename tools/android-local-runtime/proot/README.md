# PRoot ARM64 APK asset

The product baseline is a single APK PRoot worker.  `build-proot-android.sh`
builds the executable for `arm64-v8a` with NDK 29 and writes:

```text
<output>/libcodex_proot.so
<output>/libcodex_proot_loader.so
<output>/proot.manifest.json
<output>/proot-loader.manifest.json
```

The source pin is Termux PRoot `v5.1.107.94`
(`58c3b42849fac502c6c60a45c4d2a82da9e9f8d4`).  This Android-maintained fork
handles seccomp-generated `SIGSYS` events from traced guest processes; the
previous upstream `v5.4.0` build did not, and the app-UID device probe exited
with signal 31.  The build packages the static loader as a separate immutable
APK asset, and the runtime supplies its path through `PROOT_LOADER`.  The only
build dependency is the pinned `talloc-2.4.2` source archive.  The build script
does not execute an ARM binary on the host and does not use QEMU/binfmt.  Host
ELF inspection can prove the target architecture; device execution/smoke
testing remains a separate ARM64 acceptance step and must not be claimed from
the host build.

Example on the migration Mac:

```sh
export ANDROID_SDK_ROOT="$HOME/Library/Android/sdk"
export ANDROID_NDK_ROOT="$ANDROID_SDK_ROOT/ndk/29.0.13846066"

tools/android-local-runtime/proot/build-proot-android.sh \
  --output "$HOME/Library/Caches/codex-proot-arm64" \
  --cache "$HOME/Library/Caches/codex-proot-sources"
```

The generated file must be supplied to the Android build as the immutable
`arm64-v8a` native asset.  It must not be copied into writable app data and
executed from there.  The Kotlin worker checks `ApplicationInfo.nativeLibraryDir`
and the exact asset filename before it starts PRoot.

The build scripts also support a Windows-hosted NDK when invoked from WSL. Pass
the NDK through its `/mnt/<drive>/...` path; the scripts create small argument-
normalizing wrappers for the Windows `.exe` tools and keep compiler temporary
files under the output volume so the Windows toolchain can read them. This is a
build-host convenience only and does not change the target ABI.

The other fixed ARM64 assets use the same output directory and pinned NDK:

```sh
tools/android-local-runtime/proot/build-host-trampoline-android.sh \
  --output "$HOME/Library/Caches/codex-proot-arm64" \
  --ndk "$ANDROID_NDK_ROOT"

tools/android-local-runtime/proot/build-worker-guard-android.sh \
  --output "$HOME/Library/Caches/codex-proot-arm64" \
  --ndk "$ANDROID_NDK_ROOT"

```

These outputs are optional native entry points with separate manifests. They
are not a network bridge, daemon, WebSocket transport, or source of Android
root by themselves. The app starts a Root worker through the user's normal
KernelSU `su` profile and checks real UID 0; it does not require a custom
`codex_agent` domain, fixed supplementary groups, or a capability mask.

The companion static loader is also packaged in `ApplicationInfo.nativeLibraryDir`
and passed to PRoot through the fixed `PROOT_LOADER` environment variable. This
avoids PRoot extracting `prooted-*` into the app-private `app_data_file` label;
Android's `untrusted_app` domain rejects executing that generated file even
though the same path can work under the separate `runas_app` domain. The loader
is immutable APK input, not a writable runtime file.

PRoot is a Linux ABI/path compatibility layer, not a kernel security sandbox.
The normal Root worker is launched through the user's KernelSU `su` profile and
keeps the real Android UID 0; App-UID workers are an explicit non-Root mode.
The Root worker binds the Android host root below guest `/android` while the
guest `/` remains the Debian filesystem. `--root-id` only maps the guest Linux
identity and never grants Android privileges by itself.

## Optional Root worker guard

`build-worker-guard-android.sh` produces the optional immutable
`libcodex_worker_guard.so` asset. Root PRoot launches through the normal
KernelSU `su` profile after the profile probe, and the guard verifies the
worker's real UID 0. It leaves KernelSU-granted capabilities, supplementary
groups, SELinux context, and Linux `NoNewPrivs` unchanged; these are reported
for diagnostics and are not fixed project gates. PRoot's guest `--root-id` is
not what grants Android identity. App-UID PRoot remains a separate execution
mode, and a Root launch failure does not silently downgrade the selected Root
session.

The Root worker requests the Android host root at guest `/android`, so the
Linux guest can address the full host tree when the configured KernelSU/SELinux
profile permits it. This is visibility, not a second security sandbox: the
device kernel remains authoritative and representative reads must be verified
on the actual device. Boot-chain and raw-block changes use the documented soft
route and concrete user authorization; an optional reversible KernelSU module
is preferred when it fits, but it is not the only legal path.

Every extracted rootfs, guest home, and temporary directory entry must carry
the app's `app_data_file` SELinux category. Symlinks need the label applied to
the link itself (`chcon -h`/`-Rh`); labeling only the symlink target can make
the dynamic loader fail with an Android AVC denial even when the target file
looks correctly labeled.

## talloc portability boundary

The first version of this script compiled talloc's `lib/replace/replace.c`
without the `config.h` generated by waf.  On Android NDK 29 that enabled
fallback declarations and failed with `timespec`/`socklen_t` redefinitions,
missing `ftruncate`/`open` declarations, and `rep_readlink`/`gettimeofday`
signature conflicts.  PRoot only consumes talloc's public allocation library;
the pinned talloc 2.4.2 translation unit needs the native Android
`memmove`, `strnlen`, `vsnprintf`, and C99 `vsnprintf` behavior.  The build now
defines those four capabilities and archives only `talloc.o`; it deliberately
does not compile `replace.c` or invent a partial waf configuration.

The generated `libcodex_proot.so` is an executable ARM64 native asset, not
a library to load with `System.loadLibrary`.  Package the exact filename under
the immutable `arm64-v8a` native-asset location expected by the Android worker;
do not commit the generated binary or copy it to writable app data.  The
companion `proot.manifest.json` should travel with the build output for the
source pin, target ABI, and SHA-256 record.
