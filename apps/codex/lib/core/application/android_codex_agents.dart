/// Android-specific operational instructions injected into each Codex thread.
/// Keep this synchronous and small so session startup does not depend on an
/// asynchronous asset read before the app-server handshake.
const String androidCodexAgentInstructions = r'''
# Android Codex device operations

These rules apply when Codex runs from the Android app. Follow the selected
Linux/PRoot execution path and the permissions actually granted by Android;
never describe a PRoot guest identity as Android root. Codex CLI/app-server
does not run as an Android/Bionic executable in this project.

## Reading and identity

- A Root worker starts through the normal KernelSU profile configured for this
  app and must have real Android UID 0. The app does not require a custom
  `codex_agent` SELinux domain, a fixed supplementary-group list, a capability
  mask, or Linux `NoNewPrivs`. The profile probe reports context, groups,
  capabilities, and representative paths as diagnostics; they are not a
  project-specific launch gate. If KernelSU does not return UID 0, report that
  concrete failure instead of pretending that PRoot's guest uid is Android
  root.
- Under Linux compatibility with App identity, PRoot and its guest `--root-id`
  do not grant Android-host root access; the worker remains the Android App UID.
- Under Linux compatibility with Root identity, the launcher starts the
  PRoot worker without a UID drop. If KernelSU returns no UID 0, report Root as
  unavailable; never silently retry a Root session as App identity. The
  current Root guest requests the complete Android host root bind at `/android`
  and keeps the Debian guest `/` distinct; conventional Android paths may also
  appear at their original names. This establishes the intended full-host
  view, but a profile probe is not proof of every read/write edge, so verify
  actual paths and denials on the device rather than inferring them from guest
  `id` output.
- Ordinary Root commands and files are direct execution paths. KernelSU's
  configured profile and Android itself remain the authority; the app does not
  insert a universal privilege broker between Codex and the host.
- Report actual OS, SELinux, mount, or helper denials accurately. A Root
  selection does not prove that every path is readable, and a PRoot `uid=0`
  is only a guest identity.
- A Root grant belongs to the named session and is reused for later Root
  operations in that session. Do not ask again just because a new turn starts
  or the user navigates away and back; a different session needs its own grant.
- Do not expose credentials or unrelated private data in output, summaries,
  or logs. Read only what the task needs and redact secrets.
- For a custom model provider, its API key is present in that session's Codex
  app-server environment. Child shell commands apply Codex's default
  KEY/SECRET/TOKEN environment exclusions, but this is not an OS security
  boundary: a same-UID or Root process may be able to inspect the app-server's
  environment. Never inspect or disclose the parent process environment; treat
  provider keys as credentials and use them only through Codex's provider.

## Writes and approvals

- Ordinary resolved absolute paths, including Android app-private data and
  configuration, are intended to be directly writable in Root mode without a
  per-command prompt. The current app policy auto-accepts recognized ordinary
  targets; keep the app-server approval channel enabled and do not ask the user
  again just because a normal write was requested.
- Do not add a generic app-level approval only because a command or path was
  not recognized. Ordinary and unclassified Root operations remain direct;
  ordinary `/system`, `/vendor`, and app-configuration files are not boot-risk
  targets. Resolve relative paths from the active workspace/working directory
  where practical. If the user's selected Codex approval policy requests
  approval, show the exact target and intended change. Whole-root, boot-critical
  init/fstab/SELinux/module paths, raw blocks, boot images, and KernelSU-control
  targets use the soft route below.
- Boot, raw block-device, init, recovery, and KernelSU control changes use soft
  routing: identify the real target, validate the device/image/slot and a
  realistic recovery path, then obtain concrete user authorization for the
  specific change. Prefer a reversible KernelSU module when it fits, but do not
  turn this guidance into a permanent hard denial of an explicitly authorized
  legitimate operation.
- A Root grant is session-scoped for UI state and should be reused for later
  Root operations in that session. It does not create a second approval prompt
  for every ordinary command.
- RootAccessPolicy and UI approvals are guidance and coordination, not kernel
  write isolation. A UID-0 worker can bypass app-side classification; never
  claim that a soft route is an absolute no-brick guarantee.
- KernelSU's `NO_NEW_PRIVS` profile flag is distinct from Linux `/proc`
  `NoNewPrivs`. This app does not set or require the Linux bit; the probe only
  reports it. SELinux and the protected-path checks remain separate.

## Android host commands

- In a Root Linux Compatibility session, the launcher binds Android host
  directories such as `/system`, `/vendor`, and `/data` at their conventional
  guest paths, and exposes the complete host filesystem below `/android`.
  Use `/android/<host-path>` for host files; use the real Android executable
  path for Android framework commands rather than installing a Debian lookalike.
- Invoke host commands directly through their Android paths:
  ```sh
  /system/bin/getprop ro.product.device
  /system/bin/pm list packages -3
  /system/bin/settings list system
  /system/bin/cmd package list packages -3
  /system/bin/dumpsys package <package>
  /system/bin/logcat -d -t 100
  ```
  They execute in the active Root worker's Android identity through the
  existing PRoot host binds; Android services and SELinux remain authoritative.
  Confirm the returned status/output instead of assuming every subcommand is
  permitted.
- Prefer the smallest relevant query; do not dump unrelated package, account,
  notification, or system state. Ordinary authorized host operations use the
  normal Root path; apply the boot soft-route only when the concrete target
  actually touches the startup chain.

## Linux guest tools and packages

- In Linux Compatibility sessions, prefer the Debian ARM64 guest's `/opt/node`
  and system/package paths for `git`, `node`, `npm`, `npx`, and `python`.
  The Android/Bionic developer-toolchain was retired and is not a fallback.
  Install missing Linux tools through the Debian guest package routes below;
  use Android host executables for Android framework/device operations, not as
  substitutes for Linux developer tools.
- In an App UID PRoot session, ordinary Debian guest packages may be installed
  with `sudo apt install [--yes] PACKAGE...`. This fixed helper downloads the
  requested package and its required dependency archives and extracts them to
  the app-private `/home/codex/.local/codex-pkgs` prefix. Binaries launched
  from that prefix receive its library directories inside the guest only. It
  does not modify the finalized base rootfs or run package maintainer scripts.
- In a Root PRoot session, `sudo` transparently executes the command as the
  already-root Android worker. Use `apt install PACKAGE...` or
  `sudo apt install PACKAGE...` for normal Debian guest installation; this
  writes the Linux guest rootfs, not Android host partitions. Use the App UID
  package prefix when the base guest should remain unchanged.
- The App UID helper supports package installation only: it does not support
  `apt update`, upgrades, removal, arbitrary `dpkg`, or package setup scripts.
  Its bundled package index is pinned to the rootfs snapshot; recommends and
  maintainer scripts are not applied, so packages requiring configuration or
  files outside the private prefix may not work.
- Prefer explicit argv and exact paths. Do not turn untrusted text into shell
  commands, bypass Android/SELinux restrictions, change SELinux mode, or leave
  a privileged helper running after its operation.
- Do not assume a host-side `adb` connection is required for device-side
  Android commands. In Root Linux Compatibility, use the direct `/system/bin`
  host path documented above; if invocation fails, report its exact exit/error
  rather than claiming that the Android command does not exist.
''';
