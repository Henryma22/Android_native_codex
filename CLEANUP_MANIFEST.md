# Android Codex workspace cleanup

Cleanup checkpoint: 2026-09-28

This repository contains the Android-local Codex product under `apps/codex`.
The entries below are the retained product files and the generated paths that
are safe to recreate.

## Project locations

- Android Codex: `C:\Users\Henry\Documents\个人项目\android_codex`
- Codex Bridge is a separate sibling project at
  `C:\Users\Henry\Documents\个人项目\codex_bridge`; it is not part of this
  repository or the Android app runtime.
- The Android native Codex source snapshot is retained at
  `vendor/codex-upstream-android-native`. It is not part of the active build;
  the nested Git checkout contains local changes, so it is preserved rather
  than treated as disposable cleanup.

## Retained

- `apps/codex/lib/` and `apps/codex/test/`: Flutter UI, session logic, and tests.
- `apps/codex/assets/fonts/`: locally bundled CC Pocket theme fonts; the app no
  longer needs a network font fetch during startup.
- `apps/codex/android/app/src/main/`: Android host implementation and the
  required PRoot launcher/loader, host trampoline, and worker-guard assets.
  No Android/Bionic Codex executable, Android ABI toolchain, or Root Read
  Broker is part of the active runtime.
- `packages/ccpocket_ui/`: local CC Pocket UI source used by the Android app.
- `artifacts/`: QA screenshots and device evidence; these are evidence files,
  not build caches.
- `artifacts/release/android-codex-1.0.0-arm64-release.apk`: the last verified
  release-variant APK, rebuilt and installed on AVD `emulator-5651` on
  2026-09-28. Size: 31,379,607 bytes. SHA-256:
  `32B02CF9B28D61E8F4D8B02F3E3B7FD742747D33034442E53FBB9920EFDDE1E6`.
  It is locally installable and signed with the Android debug certificate; it
  is not a store-distribution signature. Device/data-plane limits are recorded
  in `docs/android-local-codex/UI_PERFORMANCE_ACCEPTANCE_2026-09-28.md`.

The old `packages/bridge/`, desktop smoke service, and legacy device Bridge
control scripts were removed from this repository. The sibling `codex_bridge`
checkout remains independent and is not an Android Codex dependency.

The old Android/Bionic Codex import, update, rollback, package, and passive
probe paths are removed. Codex CLI/app-server and developer tools run in the
local Linux/PRoot guest; Android host commands use the Android OS binaries.
Existing app data and cached conversation records are not deleted. The old
The untracked Android ABI toolchain source/bundles were moved out of the
repository to `C:\Users\Henry\AppData\Local\Temp\android-codex-obsolete-native-toolchain-20260928`;
no active app, build, or runtime path consumes them. The quarantine has not
been purged yet. `packages/ccpocket_ui/` remains because
its session/composer widgets are active. Its generated localization contract
still contains unreachable upstream Bridge/Claude strings; they do not expose
a page or runtime route in this app.

## Removed generated data

- `apps/codex/build/`
- `apps/codex/.dart_tool/` and `.flutter-plugins-dependencies`
- `apps/codex/android/build/`, `.gradle/`, and `.kotlin/`
- `apps/mobile/build/` and `.dart_tool/` (Android Codex source checkout)
- `packages/bridge/dist/` and `packages/bridge/node_modules/` (legacy Bridge
  generated data)
- `apps/codex/tmp/`
- `codex_bridge/apps/mobile/build/` and `.dart_tool/`
- the root `tmp/` directory, including the upstream Rust `target/` cache,
  APK inspection copies, old native binary copies, and UI probe dumps
- temporary `C:\android_codex`, `C:\ccpocket-src`, and `X:` path aliases used
  only for Windows build-path workarounds
- old root-level `C:\ccpocket-build` and `C:\ccpocket-runtime-*` artifacts;
  the active Bridge source was moved from `C:\ccpocket_latest` rather than
  deleted
- the duplicate `android_codex_latest` checkout and its heap dump
- `C:\gradle-cache`, old Gradle 8.13/9.3.1 caches, stale NDK/toolchain
  installers, Android SDK package-operation temp data, npm/pnpm caches, and
  stale Codex/Rust/Flutter temporary build directories
- rebuildable `target/`/`.next`/`dist` directories in the QQ and LLM projects;
  their source and runtime data were retained
- stale Bridge pairing QR files and stray native `.tmp` files
- the unused `tools/android-local-runtime/device/runtime.sh` Bridge control
  surface, wrappers, fixture tests, and `tools/ssh-jump-smoke`
- the obsolete `tools/android-local-runtime/builder/finalize-on-device.sh`
  mount-based finalizer; the manifest-backed
  `device/proot-finalize-rootfs.sh` is now the only supported rootfs finalizer

All listed generated directories can be recreated with the normal Flutter and
Gradle build commands. Authentication, workspaces, session history, source
files, and packaged runtime assets are not part of this cleanup.

## 2026-10-01 standalone repository reset

The old remote `https://github.com/K9i-0/ccpocket.git` and its local Git
history were intentionally removed. This checkout was initialized as a new
repository on branch `main` with no remote configured. Android Codex is
standalone; `packages/ccpocket_ui` is only a local UI component source.

The exact generated/history paths removed were root `tmp`, root `artifacts`,
Flutter/Gradle build caches, the old `.git` directory, and the sibling
`android_codex-runtime-artifacts` directory. No APK, screenshot, device dump,
API key, keystore, session data, or workspace data remains in this checkout as
a release input.

The retained release inputs are source, tests, Android host code, runtime
scripts/assets, project configuration, and Android-local-Codex documents.
Run `tools/secret-scan.ps1` before every public release.
