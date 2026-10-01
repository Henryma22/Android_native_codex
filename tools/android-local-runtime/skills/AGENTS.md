# Android Codex runtime and root-access policy

This is the canonical Android/PRoot operating guide. The Android app bundles
this Markdown asset and seeds it as `AGENTS.md` into each app-managed
per-session `CODEX_HOME` only when that file does not already exist; existing
session/user guidance is never overwritten. In PRoot, the file therefore lives
under `/home/codex/sessions/<session-id>/AGENTS.md`, not the shared
`/home/codex/.codex` directory. The app-server also injects companion
instructions from `apps/codex/lib/core/application/android_codex_agents.dart`
on thread start and resume. This guide is not a replacement for Android's
kernel, SELinux, or KernelSU enforcement.

## Runtime model

- Codex CLI and app-server run only in the verified ARM64 Debian/PRoot guest.
  There is no Android/Bionic Codex or native-toolchain fallback. If PRoot or
  its rootfs is unavailable, report that concrete state and use the Settings
  install/update action; do not silently launch a second runtime. Root
  execution uses the normal KernelSU profile configured by the user and
  requires actual UID 0; there is no project-specific SELinux domain gate.
- Each session owns its own app-server process, temporary directory, SQLite
  state, and event stream. Leaving the UI, switching sessions, or opening
  Settings must not stop a session. Only an explicit Stop, process exit, or
  unrecoverable runtime failure may stop it.
- `git`, `node`, `npm`, `npx`, `python`, `bash`, `rg`, and `jq` come from the
  verified ARM64 Debian guest and its package paths. Install missing guest
  packages with the supported package helper or within the selected workspace;
  do not look for an Android/Bionic or Bridge fallback.
- App-UID and Root PRoot are distinct execution identities. Root PRoot uses the
  user's normal KernelSU profile and host mappings; App-UID PRoot does not
  inherit Root visibility. These mappings do not change the worker's Android
  identity or SELinux access.
- Project dependencies such as `npm install`, `pip install`, and virtualenvs
  should stay in the selected workspace and run in PRoot. In an App UID session,
  `sudo apt install [--yes] PACKAGE...` downloads the requested Debian packages
  and dependencies into the shared `/home/codex/.local/codex-pkgs` prefix. This
  helper does not modify the base rootfs or run package maintainer scripts; the
  app adds its binaries and ARM64 library directories to guest discovery. It
  does not support `apt update`, upgrades, removal, arbitrary `dpkg`, or package
  setup scripts; indexes follow the pinned rootfs snapshot.
- Root PRoot runs as the user's normal KernelSU Root identity. In that session,
  `sudo` transparently executes the requested command as the already-root
  worker; `apt install` or `sudo apt install` installs into the Debian guest
  rootfs, not Android host partitions. Use this for persistent guest-wide
  packages, or the App UID prefix when the base guest should remain unchanged.

## Android host commands

- In a Root Linux Compatibility session, the launcher binds Android host
  directories such as `/system`, `/vendor`, and `/data` at their conventional
  guest paths, and exposes the complete host filesystem below `/android`.
  Use `/android/<host-path>` for host files and real Android executable paths
  for framework commands; do not install Debian lookalikes as substitutes.
- Invoke Android commands directly through their Android paths:
  ```sh
  /system/bin/getprop ro.product.device
  /system/bin/pm list packages -3
  /system/bin/settings list system
  /system/bin/cmd package list packages -3
  /system/bin/dumpsys package <package>
  /system/bin/logcat -d -t 100
  ```
  These use the active Root worker and existing PRoot host binds, not a
  separate broker. Android services, SELinux, and the KernelSU profile remain
  authoritative; verify each command's actual result.
- Keep queries narrow and avoid dumping unrelated app, account, or system data.
  Normal authorized host operations stay on the ordinary Root path; use boot
  soft-routing only when the concrete target affects the startup chain.

## Root identity and reads

- The current Root worker launch check requires actual Android UID 0 from the
  normal KernelSU profile. SELinux context, primary/supplementary groups,
  capabilities, NoNewPrivs, and path samples are reported for diagnostics, not
  turned into a custom domain or fixed-group gate. If KernelSU returns no UID
  0, report that concrete failure; passing sample paths is not proof of global
  policy.
- Newly created local Codex sessions select Root by default; saved sessions
  retain their stored execution identity, while legacy records without one stay
  App UID. The user can switch a session to App UID in its settings. The
  default uses the user's normal KernelSU profile. Root execution uses the
  fixed host process manager and approved `su` helper
  candidates; it is never inferred from a UI label or from a PRoot UID.
- A Root grant is scoped to its named session and reused for later Root
  operations in that session. It does not authorize writes or carry to other
  sessions; do not prompt again merely because another turn starts.
- In a root session, Codex may attempt to read any absolute path. There is no
  architecture-level sensitive-read allowlist. The actual Android kernel,
  SELinux policy, mount state, and `su` helper remain the final authority; a
  denial must be reported as a device denial, not hidden as “file not found”.
- Root PRoot requests the complete Android host `/` below guest `/android`;
  App-UID PRoot does not receive that Root-only host-root mapping. The root
  bind establishes the intended full-host view, but representative device
  reads still need verification and every actual denial must be reported as a
  device/SELinux limitation.
- Read access does not grant write access. Never turn a read request into a
  shell command with side effects.

## Tiered write policy

Classify the exact target before a root write. Never use a broad recursive
write when a file-level operation is sufficient.

| Tier | Targets | Route |
| --- | --- | --- |
| Normal | Ordinary, relative, or otherwise unclassified operations whose concrete target is not a known critical target | Direct Root execution without a generic per-operation approval. Resolve relative paths using the active working directory where practical; unknown syntax alone is not a boot-risk signal. |
| Soft route | Whole-host root `/`, boot-critical init/fstab/SELinux/module paths, raw block devices, boot/recovery images, KernelSU control state | Identify the exact target and intended effect; prefer a reversible KernelSU module when it fits. Obtain concrete authorization for boot-chain or otherwise irreversible changes. Ordinary system files, fonts, hosts, app configuration, and guest package installs remain direct. Never turn this route into a permanent denial. |
| Control state | KernelSU profile/allowlist/control state | Operate through KernelSU Manager; do not confuse profile configuration with a normal workspace file. |

The app's pure classifier is `RootAccessPolicy`, a decision aid rather than a
write sandbox. Keep ordinary and unknown Root operations direct; do not add a
generic approval solely because a command or path was not recognized. Preserve
soft routing for concrete critical targets and read-only mode. The native
process manager still validates argv, cwd, environment, and the chosen
identity. These app-side checks do not constrain an arbitrary UID-0 child at
the kernel boundary. The soft route reduces avoidable mistakes but is not a
kernel guarantee and must not be presented as a zero-brick guarantee. An
explicitly authorized legitimate operation remains possible through the
appropriate Android/KernelSU path.

Root ordinary, relative, and unclassified operations remain direct under the
app's `RootAccessPolicy`; concrete whole-root, boot-critical, raw-block, boot,
and KernelSU-control targets use the soft route. Ordinary `/system` and
`/vendor` files are not treated as boot-critical merely because of their+partition path. This is an app-side classifier,
not a kernel boundary. Root PRoot mounts the Android host root `/`
at guest path `/android`, and keeps selected host paths such as `/data` and
`/system` available at their original names. App-identity PRoot does not
receive the `/android` mapping. Guest paths such as `/etc` remain separate
from Android host system files. The mapping provides path visibility only:
actual access still depends on the KernelSU Root Profile and SELinux. A device
check on 2026-09-27 verified the live worker as UID 0 in the normal
`u:r:ksu:s0` context and verified representative host reads
(`/system/build.prop`, `/data/system/packages.xml`) plus listings under
`/data/user/0`, `/data/app`, and `/dev/block/by-name`. This proves those sampled
paths on that device at that time, not every path or future device state. Report
an actual kernel, mount, or SELinux denial as such; do not add a path allowlist.

KernelSU Root Profile `NO_NEW_PRIVS` is distinct from Linux
`/proc/self/status` `NoNewPrivs`. The app neither sets nor requires the Linux
bit and does not rewrite the profile's capability set. Verify actual worker
UID/GID, SELinux context, granted capabilities/groups, and read/write cases
on-device.

## KernelSU and boot changes

When Android itself must change, use the least coupled Android/KernelSU path
that actually performs the requested operation:

1. classify the smallest capability and risk;
2. verify the expected state and create a reversible backup;
3. build a bounded module with `module.prop` and `ccpocket-plugin.json`;
4. if a reversible KernelSU module is appropriate, stage it through the normal
   user-controlled KernelSU workflow;
5. obtain explicit authorization for the concrete high-risk operation, run the
   declared health checks, and disable or roll back when the result is bad.

Do not invent a universal broker or per-command Root approval. Use the normal
Root execution path for ordinary work, and keep boot/image/KernelSU control
changes explicit, target-specific, and user-authorized.

## Images, tools, and third-party providers

- Image attachments are bounded by the Android picker and are sent only as
  the current turn's input; do not persist raw image bytes in session history.
- A custom OpenAI-compatible provider is configured as a native Codex
  `model_provider` using the Responses API in the same app-server/thread flow,
  not as a separate chat-only client. OpenAI OAuth is not used by a session
  while that provider is selected. Tool/session behavior remains app-server
  functionality; exact model, image, reasoning, and usage support depends on
  the endpoint and must not be fabricated. API keys are stored by the Android
  Keystore-backed provider store and passed only into that session process.
- Do not claim a tool or provider is available until its version/endpoint probe
  has returned successfully on the device.

## Diagnostics

Each thread keeps its own PRoot app-server process, CODEX_HOME, SQLite state,
and event stream. Never solve a session problem by sharing one process or one
SQLite home across sessions. Surface concrete PRoot/app-server failures in
runtime diagnostics rather than disguising them as conversation messages.
