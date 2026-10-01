# ARM64 native runtime inputs

The `arm64-v8a/` directory contains the small, cross-compiled native assets
used by the local PRoot compatibility path:

- `libcodex_proot.so` and `libcodex_proot_loader.so`;
- `libcodex_host_trampoline.so`;
- `libcodex_worker_guard.so`.

The independent App does not package a fixed-scope root-read broker or an
Android/Bionic Codex executable. Root sessions execute through the selected
KernelSU Root worker and expose the Android host view directly; Codex itself
runs from the separately installed official Linux ARM64 rootfs in PRoot.

Each asset is built from the pinned source/toolchain scripts under
`tools/android-local-runtime/proot/` and is checked as an ELF64 AArch64
artifact before packaging. The Codex CLI and verified Linux rootfs are
installed separately; they are not embedded in the APK. Android ABI assets
here are only the PRoot launcher, loader, host trampoline, and worker guard.

Do not put auth data, a PRoot rootfs, or arbitrary scripts in this directory.
