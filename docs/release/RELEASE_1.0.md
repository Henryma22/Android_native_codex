# Android Codex 1.0.0 release notes

## Scope

This release is the standalone Android Codex application. The repository is no longer published as, or identified with, K9i-0/ccpocket; CC Pocket code is retained only as a local UI component source. PC Bridge, remote-machine routing, Claude Code entry points and the retired Android/Bionic Codex path are not release dependencies.

## Runtime

- Android ARM64 device.
- KernelSU-managed Root execution with the local Linux/PRoot guest as the preferred compatibility environment.
- Official Linux ARM64 Codex CLI/app-server can be replaced independently of the Flutter UI.
- OpenAI authentication and OpenAI-compatible third-party provider configuration are selected in-app and remain local to the device.

## Verification baseline

- Flutter tests: 379/379 passed in the last recorded full run.
- APK package: io.henry.codex.
- Version: 1.0.0 (versionCode=1).
- Release build is non-debuggable when verified by tools/verify-android-apk.ps1.
- The local QA artifact was debug-certificate signed; this is not a public-store signing credential.

## Signing and distribution

The build accepts a maintainer-owned keystore through these environment variables:

CODEX_RELEASE_STORE_FILE, CODEX_RELEASE_STORE_PASSWORD, CODEX_RELEASE_KEY_ALIAS, CODEX_RELEASE_KEY_PASSWORD.

No keystore, password, API key, session export or device data is included in this repository. A public GitHub Release must be rebuilt with the maintainer's production key, run the APK verifier and publish the resulting SHA-256 alongside the APK.

## Screenshots

The repository README includes two real-device screenshots: the workspace/session home screen and the current session capability/status view. They are stored under `docs/release/screenshots/` and contain no credentials or signing material.

## Known limits

- ARM64 Android and a working KernelSU/PRoot environment are required for the full local runtime.
- A QA-signed APK is suitable for local installation but must not be presented as a store-signed artifact.
- Real Root, long-running parallel session and provider behavior remain device/runtime acceptance concerns; Flutter tests do not replace those checks.
- The project intentionally does not promise compatibility with every future Codex CLI version without a runtime probe.
