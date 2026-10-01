# Android local Codex rootfs builder

This directory builds the optional Linux compatibility rootfs used by the
independent `io.henry.codex` Android app. The image contains only the pinned
Debian userland, Node.js ARM64, and the official Linux/ARM64 Codex package.
It does not provide a network service, a desktop host, or a transport layer.

The builder runs on WSL2/Linux x86_64 and never executes ARM64 code on the
build host. Device finalization is performed later by the app's guarded
installer on an ARM64 Android device.

## Pinned inputs

- Debian `bookworm`, `debootstrap --foreign`, snapshot
  `20260821T000000Z`, `minbase`, and the Debian archive keyring;
- Node.js Linux ARM64 `24.19.0` from the official tarball;
- `@openai/codex@0.157.1-linux-arm64` from the npm registry (override the
  exact version and pinned integrity when intentionally building another CLI release);
- Debian guest tools `git`, `jq`, `python`, `bash`, `curl`, `coreutils`,
  `util-linux` (including `setpriv`), `tini`, and `libcap2-bin` inside the
  foreign image. `npm` and `npx` come from the pinned Node archive.

Every downloaded input is checked by SHA-256 or npm integrity. The generated
manifest records the exact artifact, versions, sources, and device checks.
Node and Codex versions remain independent.

## Build

Use a case-sensitive WSL-native output directory for any extracted staging
tree. The compressed artifact and download cache may be on a larger mounted
volume.

```bash
builder=/path/to/android_codex/tools/android-local-runtime/builder
out=/mnt/d/codex-runtime-artifacts
cache=/mnt/d/codex-runtime-cache

npm pack --ignore-scripts --json \
  --pack-destination "$cache" @openai/codex@0.157.1-linux-arm64
codex_tgz="$cache/<exact-npm-pack-output>.tgz"
codex_sha256=$(sha256sum "$codex_tgz" | awk '{print $1}')

sudo "$builder/build-rootfs.sh" \
  --output "$out" \
  --cache "$cache" \
  --codex-tarball "$codex_tgz" \
  --codex-sha256 "$codex_sha256"
```

For an offline retry, provide `--offline`, a prepared `--base-rootfs`, and
the pinned Node/Codex tarballs. No mutable latest/tag URL is accepted.

The result is named like:

```text
codex-rootfs-bookworm-20260821T000000Z-node-24.19.0-codex-0.157.1-linux-arm64-arm64.tar.gz
```

## Independent app installation

The current app path is:

```text
tools/android-local-runtime/install-independent-compatibility-rootfs.ps1
```

It validates the archive and manifest, resolves the installed
`io.henry.codex` data/native-library paths, and invokes
`device/proot-finalize-rootfs.sh` on the ARM64 device. The finalizer runs the
foreign Debian second stage, checks Node/Codex entrypoints and the rootfs
policy, then writes a digest-bound marker. Finalization is setup work; each
Codex session can then run with either of the app's explicit identities:

- **App identity:** Android keeps the PRoot worker at the app UID. PRoot's
  guest `--root-id` is only a Linux guest mapping and does not grant Android
  host root access.
- **Root identity (normal KernelSU path):** the app launches the worker through
  the user's configured KernelSU `su` profile, verifies real Android UID 0,
  and does not silently fall back to App identity. The PRoot worker stays UID 0
  and exposes the Android host root at guest `/android`, while guest `/` stays
  the Debian filesystem. The app does not require a custom SELinux domain,
  fixed group list, or capability mask.

The installed rootfs remains app-private. Root identity is a per-session
execution choice, not a setup-only capability or a universal broker path.

The finalized runtime is kept below the app-private path:

```text
/data/user/<user-id>/io.henry.codex/no_backup/codex-compatibility-v1/
```

The app accepts a runtime only when the marker, digest, versions, fixed
rootfs layout, and ARM64 PRoot guest probe all agree. A missing or failed
runtime stays visibly unavailable in the UI.

Rootfs replacement preserves the existing `home/` tree (including hidden
files and user-prefix package data such as `/home/codex/.local/codex-pkgs`)
in the new runtime slot before activation.
If the existing guest home is not a real directory, installation stops rather
than discarding it.

The independent installers use a bounded ADB readiness poll (60 seconds by
default). Use `-DeviceWaitSeconds` to adjust that limit; they fail closed when
the selected device never reaches the `device` state instead of waiting forever.

## Archive and manifest checks

```bash
bash tools/android-local-runtime/builder/test-offline.sh
```

The suite uses `python3` by default. On Windows Git Bash, where the Python
Store alias may shadow the real interpreter, set `PYTHON_BIN` to an explicit
Python executable path before running it.

The offline suite checks shell syntax, lockfile pins, archive traversal and
special-file rejection, symlink policy, manifest validation, canonical device
paths, and missing-parameter guards. It does not download large artifacts or
claim ARM64 execution from the host.

`stage-for-device.py` is retained for the older host-driven staging contract;
the independent `io.henry.codex` installer does not depend on that staging
transport.
