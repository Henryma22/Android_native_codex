# Android APK verification

`verify-android-apk.ps1` is a read-only delivery check for the independent
`codex` APK. It verifies the APK signature, extracts the application identity
and version with Android build-tools, inventories the independent Codex ARM64
native assets, and emits a JSON artifact record with the APK SHA-256 and
certificate digest.

The default artifact is the local release build:

```powershell
.\tools\verify-android-apk.ps1
```

For the full local Codex release packaging gate, require all four immutable
ARM64 native assets explicitly:

```powershell
.\tools\verify-android-apk.ps1 -RequireCodexNativeAssets
```

The ordinary local release build is intentionally installable with the Android
debug certificate when no production signing variables are configured. Use
`-RequireReleaseSigning` for a store-delivery gate; it fails closed if the APK
is debug-key signed. `-RequireCodexNativeAssets` fails closed if PRoot, its
loader, host trampoline, or worker guard is absent. The independent App does
not package the obsolete fixed-scope root-read broker; Root/PRoot commands use
the selected Root worker directly. This verifier does not upload, install, or
modify the APK.
