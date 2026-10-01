# Android Codex root access policy

The current contract is [PROJECT_DIRECTION.md](PROJECT_DIRECTION.md) and
[PROJECT_GOAL.md](PROJECT_GOAL.md). This file's dated implementation notes
below are historical evidence; where they conflict with the current contract
or code, follow the current contract.

## Current contract — 2026-09-27

- Root is the normal execution mode and uses the user's ordinary KernelSU
  profile via `su`; the app checks that the helper works and the worker is
  actually UID 0. It does not require a custom SELinux domain, fixed capability
  mask, or per-command broker.
- Root can read across the Android host filesystem wherever the active kernel,
  SELinux policy, mounts, and KernelSU profile permit. Root PRoot exposes the
  host root at `/android`; the guest's own `/` remains its Linux rootfs.
- Root PRoot also binds conventional Android directories such as `/system`,
  `/vendor`, and `/data` at their original guest paths. Invoke Android
  framework commands directly (for example `/system/bin/pm`,
  `/system/bin/settings`, `/system/bin/cmd`, or `/system/bin/dumpsys`) instead
  of adding a privileged broker or installing Linux lookalikes. Host file
  paths use `/android/<path>`; each command's actual success still needs device
  verification.
- Ordinary, relative, and unclassified Root operations proceed directly and
  do not trigger a generic approval just because the app cannot classify them.
  The app-side `RootAccessPolicy` is advisory routing, not a kernel sandbox.
- Known whole-host-root, KernelSU-control, raw-block, system, and boot targets
  receive a visible soft route. Explain the concrete operation and recovery
  implications, prefer a reversible KernelSU module where useful, and keep a
  legitimate direct operation available after concrete user authorization.
  These are behavior precautions, not a claim of zero risk or absolute
  enforcement. Explicit read-only session mode remains an app-level choice
  that denies writes.
- Root confirmation is session-scoped, not re-requested on every Settings
  visit. Codex threads, turns, tools, and approvals continue through the normal
  app-server protocol.
- KernelSU profile changes are performed by the user. Do not silently change
  the user's profile or add architecture-level restrictions to compensate for
  hypothetical failure modes.

## Historical snapshots (superseded)

Android Codex is local-first. The Codex worker must be able to inspect any
device file that the selected Android identity can actually read. The app does
not add a “sensitive read” denylist, because that creates false negatives and
prevents legitimate diagnostics. Android's kernel, SELinux, mount permissions,
and the root helper still decide whether a read succeeds.

Writes are different: a write can alter user data, packages, the boot chain, or
the device's recoverability. The exact target is classified by
`apps/codex/lib/core/domain/root_access_policy.dart`:

- Low risk: workspace/runtime data and ordinary resolved absolute paths; direct
  write without a per-operation prompt. This includes app-private Android
  configuration under `/data/user/0`, `/data/data`, and `/data/misc`.
- Medium risk: unresolved, relative, broad, or otherwise unclassified scopes;
  show a visible approval with the best available exact target and diff.
- High risk: Android system partitions/configuration, init files, boot image
  files, or KernelSU module deployment; do not write through the ordinary Root
  command path. Verify the intended state and use the reviewed KernelSU plugin
  workflow where supported.
- Blocked: writes to the filesystem root itself (`/`), raw block devices, and
  KernelSU profile/allowlist/control-state files. KernelSU control state must
  be changed through KernelSU Manager; only explicitly supported module/bin
  paths use the typed plugin route. Raw partitions are never direct `su`
  targets.

Root PRoot now binds the complete Android host `/` at guest `/android`, while
retaining selected host binds such as `/data` and `/system` at their original
pathnames. App-identity PRoot does not receive this mapping. Guest paths such
as `/etc` remain guest paths and can be changed by package managers. The bind
provides path visibility, not permission: SELinux and the active KernelSU Root
Profile still decide which reads and writes succeed. On 2026-09-28, a real
device Root session returned UID 0 and successfully read `/android/etc/hosts`;
this is the current device evidence for the mapping. It does not imply that
every path is readable on every ROM or that App UID sessions gain the mapping.
This classification is best-effort app logic, not a kernel write sandbox.

## Operational rules

1. Prefer one exact file operation over recursive writes.
2. Preserve a write receipt and backup for medium/high-risk operations.
3. Do not combine read and write requests in one approval.
4. Newly created local Codex sessions select Root by default; saved sessions
   retain their recorded identity, and legacy records without an identity remain
   App UID. The user can select App UID from session settings. This default
   still requires the ordinary KernelSU `su` helper to return a real UID 0. The
   app does not require a project-specific SELinux domain, fixed groups, or a
   capability mask; those fields are diagnostics. If KernelSU does not grant
   UID 0, Root execution is unavailable and the user can switch that session to
   App UID to continue.
5. A new Root session prefers the verified Linux/PRoot backend; that
   preference is not applied to a restored session that already has a Codex
   thread ID. App-identity sessions and the PRoot host worker run as the Android app UID.
   PRoot guest UID 0 is only an emulated identity and grants no Android
   filesystem privilege. Root sessions request Android UID 0 through the normal
   KernelSU profile; the launcher rechecks the resulting UID before starting
   PRoot. The profile's context, groups, capabilities, and Linux `NoNewPrivs`
   value are reported for diagnosis, not used as a project-specific startup gate.
6. The in-app Root-session confirmation is granted once per session, not every
   time Settings opens. Ordinary resolved absolute write targets are routed
   directly in Root mode. Unknown, system, boot, raw-block, and KernelSU-control
   targets receive a visible soft-route explanation with the concrete target and
   recovery implications; after explicit user authorization the legitimate
   operation remains available. This is not a hidden hard block or a per-command
   Root approval loop.
7. In Linux compatibility mode, App identity remains App UID. A Root identity
   is forwarded to the native launcher through the ordinary KernelSU `su`
   helper, which preserves the user's selected KernelSU context, groups, and
   capabilities. Only Root mode receives the complete Android host bind at
   `/android` plus the fixed compatibility-path binds. PRoot's guest
   `--root-id` alone is never device Root; the in-app CLI updater still writes
   its app-owned guest version directory as App identity.
8. A KernelSU module or boot-related operation should declare its capability,
   backup targets, health checks, reversibility, and reboot requirement. This is
   a reviewable soft route and documentation contract, not a replacement for
   KernelSU's own profile or a generic Android broker.
9. Never put API keys, OAuth tokens, or root command output in progress logs.
10. Passive runtime-status checks during startup, app resume, or Settings
    refresh must not invoke `su`, repair Root-owned files, or inspect the
    persistent Root runtime slot. Root runtime verification belongs to an
    explicit import/restore flow or a session that has passed its Root
    authorization gate. Debian guest package/tool availability is checked
    inside that guest, not through a retired Android/Bionic toolchain importer.

## Historical implementation boundary (superseded)

`HostProcessManager` owns per-process root execution and validates argv, cwd,
environment, and helper identity. It now requires `smoke_passed` evidence from
the explicit read-only worker probe and launches through only the exact fixed
`su` helper that passed that probe. Both probe and session request the same
fixed per-invocation context and KernelSU no-new-privileges flag. The immutable
APK worker guard drops the app-wide `su` capabilities before launching the
Codex child; the probe uses this same guard and measures the reduced child, not
the initial KernelSU profile. The initial profile must provide `CAP_SETPCAP`
and the six routine worker capabilities (`CAP_CHOWN`, `CAP_DAC_OVERRIDE`,
`CAP_DAC_READ_SEARCH`, `CAP_FOWNER`, `CAP_SETGID`, `CAP_SETUID`) so the guard
can establish the bounded child. It removes every bounding capability except
mask `0xcf`, sets effective/permitted to `0xcf`, clears inheritable/ambient capabilities, and sets
Linux `NoNewPrivs=1`; any failure exits before the shell, PID marker, or PRoot
starts. The separate fixed plugin-broker mode is unchanged and continues to
use its own app-approved KernelSU invocation. A missing context or unsafe
sampled filesystem profile blocks the worker. Immediately before creating the
Root session marker and starting PRoot, the generated Root-side shell
independently rechecks all four UIDs are 0, the `codex_agent` SELinux domain is
enforcing, Android groups are only 0/3003, Linux `NoNewPrivs=1`, and the
effective/permitted/bounding/inheritable/ambient masks match the reduced-worker
contract. A mismatch exits before Codex starts. The per-invocation context and
capability reduction still do not by themselves create per-path write policy.
The Dart
policy classifier and
`apps/codex/lib/core/application/android_codex_agents.dart` provide the
write-routing contract used by the UI and Codex instructions; the app injects
that synchronous instruction block as `developerInstructions` on both
`thread/start` and `thread/resume`. `PluginBroker`, `PluginArchiveValidator`, and
`KernelSuPluginBridge` now own the plugin boundary: archives are validated in
app-private staging, only `ccpocket.plugin.*` module IDs and fixed `ksud`
operations are accepted, and root output is discarded. The app does not accept
a caller-supplied shell, path, environment, or fake device-credential flag.
The canonical runtime guide at `tools/android-local-runtime/skills/AGENTS.md`
is bundled as an Android asset and seeded into each app-managed per-session
`CODEX_HOME/AGENTS.md` only when that file is absent, so standalone Codex CLI
children receive the same operational baseline without overwriting user-authored
session guidance. This is behavior guidance, not an OS security boundary.
R3 plugin enable now requires Android 11+ system device-credential
authentication. The confirmation is bound to the staged module ID and SHA-256;
the Dart channel cannot forge the trusted confirmation. This authenticates the
user's intent to enable that module, but does not itself validate that the
module's SELinux policy is safe or that the resulting Root profile enforces the
intended write boundary. The settings review shows parsed manifest declarations,
archive member names, and bounded UTF-8 previews of scripts, `sepolicy.rule`,
`system.prop`, and `initrc/*.rc`. Manifest fields are untrusted self-description;
non-text files are opaque, and truncated previews are not a complete code audit.

Root app-server threads use `approvalPolicy=untrusted`; do not change this to
`on-request` while using `danger-full-access`, because that combination can
allow commands without the app's per-command approval path. The app silently
accepts its explicit read-only command set and ordinary resolved absolute
write targets. Unknown commands/scopes retain a visible approval; recognized
system/boot targets are diverted to the plugin-only route or denied for raw
devices and unsupported control state. The app does not automatically create a
KernelSU plugin from a blocked command; Settings remains a separate
user-initiated workflow.

The Root session's “Read-only (app-enforced)” permission level keeps global
read visibility but denies file-change approvals, unknown/write command
approvals, and non-read-only one-shot CLI commands. Only exact commands in the
read-only diagnostic allowlist remain eligible for automatic approval. This is
still enforced in the Android app approval flow, not by a kernel sandbox; it
must not be described as protection against a compromised app-server or a
launcher/policy bypass.

This classifier is still a best-effort app-layer preflight, not an OS-enforced
write sandbox. It cannot prove the effects of arbitrary or obfuscated code,
symlink changes, or tools that write through paths not visible in argv. Until a
separate execution boundary enforces read/write capabilities, Root mode must
not be described as guaranteeing that every system write can only occur via a
KernelSU plugin. Direct file-write requests targeting KernelSU control state
are now denied by the classifier; this does not constrain an arbitrary root
child or make the settings files safe to edit through another path. This is an
explicit remaining architecture gap.

On the connected Xiaomi 24031PN0DC (Android 16, kernel
`6.1.138-android14-11-g965475777129-mi`), a read-only check on 2026-09-23 found
`CONFIG_SECURITY_LANDLOCK` unset. During the same active session, the Codex
`libcodex.so` process was UID 0 with `CAP_DAC_OVERRIDE` in its effective set,
`NoNewPrivs=0`, and `Seccomp=0`. This is direct evidence that the current
native Root process can bypass ordinary DAC write checks; it is not protected
by the Dart classifier at the kernel boundary. A separate launcher/broker
design must be proven on this device before changing this claim. Path
classification now canonicalizes `.` and `..` and uses exact-case matching for
the low-risk workspace root, but it does not resolve filesystem symlinks.

2026-09-25 device probe refinement: UID 0 alone does not define a useful or
safe Root profile. On the connected Xiaomi, a UID-0 process labeled with the
App's `untrusted_app` context had full effective capabilities but SELinux
denied access to `system_data_file`, the app's `fuse` workspace, and
`block_device`; a UID-0 process labeled `u:r:ksu:s0` could read those objects
and `test -w` also succeeded for both the workspace and
`/dev/block/by-name/boot_a`. These were permission checks only, launched from
ADB root with explicit contexts; they are not App-originated Root PRoot tests.
The profile therefore needs a dedicated enforcing SELinux domain and a
capability set verified against actual read/write cases. Do not substitute
`u:r:ksu:s0`, permissive SELinux, or broad `allow *` rules for that policy.
KernelSU documents per-app Root Profiles with configurable UID/GID/groups,
capabilities, SELinux context and rules: [App Profile guide](https://kernelsu.org/guide/app-profile.html).
The exact device observations and limitations are recorded in
[`DEFECT_REMEDIATION_PROGRESS.md`](DEFECT_REMEDIATION_PROGRESS.md).

The next device acceptance pass must exercise one low-risk read, one
medium-risk approval, and a harmless KernelSU module stage/rollback; no boot
image or raw block write is part of acceptance. R3 enablement is wired to
Android device credentials but has not yet been exercised on the connected
device.

Settings now has an explicit, read-only `Inspect KernelSU Root Profile`
action. It reports the bounded worker UID, SELinux context, capability masks,
Linux `/proc` `NoNewPrivs` (required to be 1), SELinux mode, and
`test -r`/`test -w` results for fixed paths. The global-read smoke samples are
`/data/system/packages.xml`, `/data/user/0`, `/data/app`, `/system/build.prop`,
`/vendor/build.prop`, `/proc/1/status`, the current app process status, and
`/sys/fs/selinux/enforce`; app-private runtime and workspace access are checked
separately. Global sample files are actually opened and read for one byte
(discarded), while sample directories are enumerated with output discarded; no
file bytes or names are returned to the app. It also enumerates visible block
aliases under `/dev/block`, `/dev/block/by-name`,
`/dev/block/bootdevice/by-name`, and `/dev/block/mapper` (when present), and
requires every discovered alias to report non-writable. The settings probe and
the launch-time preflight share this check. It also checks the exact boot
sample, KernelSU/module roots, system/vendor config, and SELinux enforcement
control. Only counts and booleans are returned; file bytes and directory names
are never returned or logged. The probe does not run automatically when
Settings opens. These write checks use access checks only; no write is
attempted, and aliases outside the enumerated directories or alternate
device-specific paths are not proven safe.
The separate KernelSU plugin-broker capability check invokes the fixed
`ksud module list` operation through `su`; it is user-triggered from the
settings refresh control and does not run merely by opening Settings. This
keeps a settings visit from implicitly requesting KernelSU authorization.
`smoke_passed` means only that these representative checks matched the reduced
`u:r:codex_agent:s0` worker; it is not proof of global path policy or access to
every Android path. Missing read or write-denial evidence fails closed. The
worker's effective, permitted, and bounding masks must equal `0xcf` (only
`CAP_CHOWN`, `CAP_DAC_OVERRIDE`, `CAP_DAC_READ_SEARCH`, `CAP_FOWNER`,
`CAP_SETGID`, and `CAP_SETUID`), inheritable/ambient masks must be
empty, and Linux `NoNewPrivs` must be 1. The app-wide KernelSU Root Profile is
not required to equal `0xcf`: it must include `CAP_SETPCAP` and all six worker
capabilities so the immutable helper can reduce the Codex child. This keeps the
separate plugin broker's KernelSU operations available, but means trusted
in-app code and that fixed broker remain within the app-wide profile's
authority. KernelSU's own `--ksu-no-new-privs` is an additional control and is
not the Linux `/proc` bit. KernelSU's Root Profile must expose only Android
groups `0` and `3003` (`inet`); other supplementary groups fail closed. These
checks are still only sample/profile evidence, not proof of every device path.
The Linux compatibility Root launch path is now implemented but not yet
device-verified: the Dart backend forwards Root identity, Kotlin requires the
same `smoke_passed` KernelSU profile gate as native Root, and its fixed
supervisor starts PRoot without dropping UID. Root mode maps a fixed set of
Android host paths into the guest; App mode does not. PRoot still does not
provide kernel namespaces, and bind visibility does not prove SELinux access.
Each Root PRoot session records its process-group leader in a private
`noBackupFilesDir` marker; the fixed stop helper verifies that the target
process environment contains that session's marker before signalling the
group. This stop path has host unit coverage but has not yet been exercised on
the device.
Do not claim that Codex/app-server is Android UID 0 until a device-side probe
of the actual worker proves its kernel UID, enforcing context, capabilities,
host-path reads, protected-path write denials, and stop behavior. The Root
launch remains unavailable on devices whose explicit profile probe does not
pass.

## KernelSU operation procedure

1. Use Settings → Root capabilities → import and inspect a ZIP. Staging is
   app-private and does not install or enable the module.
2. Inspect the module ID, effective risk, manifest declarations, archive
   member-name list (overlong names are marked truncated), bounded script/policy previews, target paths,
   backup/rollback metadata, and health checks before applying it. The preview
   does not make binary or truncated content auditable. Only the
   `ccpocket.plugin.*` namespace and the broker's fixed `ksud` operations are
   accepted.
3. R1 declarative, reversible operations may use the broker's constrained
   automatic path. R2/R3 require explicit approval; R3 installs disabled and
   requires system device-credential authentication to enable. R4 is rejected.
4. Verify the resulting module state with the broker's list operation and run
   its declared health check. On failure, disable or roll back only the module
   created by this request. Never use this workflow to flash boot images or
   write raw partitions.
5. A successful JVM broker test is not device evidence. Record a real-device
   stage/install/list/rollback separately, and do not claim it until all four
   operations are observed on the target device.

6. Do not interpret a `kernelSuPlugin` classification as a completed plugin
   deployment. Today it prevents normal root approval; the user must separately
   stage and review an archive in Settings. Automatic handoff remains open.

## KernelSU Root Profile scope and the plugin broker

KernelSU Root Profiles still supply UID, GID, groups, and capabilities to `su`
for an installed app; those values are not per Codex session ([KernelSU App
Profile guide](https://github.com/tiann/KernelSU/blob/v3.3.0/website/docs/guide/app-profile.md)).
Upstream KernelSU `su` supports a per-invocation `-Z/--context` option and
`--ksu-no-new-privs` (merged in [KernelSU PR #3653](https://github.com/tiann/KernelSU/pull/3653));
the context option does not provide per-invocation capability masks. Android
Codex's immutable native worker guard now drops the capability bounding set
and effective/permitted sets to `0xcf` (routine ownership, DAC, and UID/GID
operations only) and enables Linux `NoNewPrivs=1` before starting the Codex worker. This lets the app-wide KernelSU profile retain the
capabilities needed by the separate fixed plugin broker without passing those
capabilities to Codex. The probe follows the same reduction path. Direct `su`
calls from the app remain governed by the app-wide Root Profile, so trusted app
code and the typed plugin broker are still part of that authority boundary.

Keep the distinction between the Profile's default SELinux context and the
worker's explicit context. `ProcessPluginKsudRootHelper` invokes the fixed
KernelSU broker using plain `su -c`, while `CompatibilityRootLaunchScript`
passes the fixed `-Z u:r:codex_agent:s0` only for the Codex worker. Upstream
`ksud su` applies an explicit `-Z/--context` immediately before `exec`; thus
the Manager's Rules must define and enforce `codex_agent`, but changing the
Profile's default context from `u:r:ksu:s0` to `codex_agent` is not required to
request that worker context and may change the broker's context. Keep the
default context unchanged until the worker policy and plugin path are both
tested. Sources: [KernelSU v3.3.0 `su.rs`](https://github.com/tiann/KernelSU/blob/v3.3.0/userspace/ksud/src/su.rs),
[`CompatibilityRootLaunchScript.kt`](../../apps/codex/android/app/src/main/kotlin/io/henry/codex/CompatibilityRootLaunchScript.kt),
[`PluginBroker.kt`](../../apps/codex/android/app/src/main/kotlin/io/henry/codex/PluginBroker.kt).

This is an implemented launch-path change, not yet device proof of isolation.
On the connected Android 16 device, `/system/bin/su` reports both options, but
the device rejects `u:r:codex_agent:s0` at `setcontext`; the Root Profile probe
surfaces this as `context_unavailable`. The capability reducer has host-side
source and tests but has not yet been exercised on the target device. A dedicated
enforcing policy must still be reviewed and installed, and the actual
Codex/app-server child must be tested for global reads, workspace writes, and
denials on boot, KernelSU, system, vendor, and SELinux-control targets. Since
`CAP_DAC_OVERRIDE` remains in the reduced worker, SELinux denials are essential;
the app's medium-write approval is still not a kernel boundary for arbitrary
shell commands. Plugin module writes through the default broker context and the
requested worker context must be tested separately. No Root session is enabled
until these checks pass.

KernelSU's current Root Profile supports configuring a custom SELinux context
and per-domain rules; its official example creates a domain with `type` and
`enforce` statements, while explicitly warning that `allow <domain> * * *` is
only a demonstration and is effectively permissive. This means the missing
`codex_agent` type may be supplied through the app's KernelSU Root Profile; a
separate module is not inherently required just to create the context. The
exact read/write rules for this device are still unreviewed and untested, so
the app remains fail-closed and must not suggest copying an allow-all policy.
See the [KernelSU v3.3.0 App Profile guide](https://github.com/tiann/KernelSU/blob/v3.3.0/website/docs/guide/app-profile.md).

Product-fit limitation: UID 0 with capability mask `0xcf` supports routine
ownership, permission, DAC, and UID/GID operations, but intentionally excludes
`CAP_SYS_ADMIN`, `CAP_SYS_MODULE`, `CAP_SYS_BOOT`, `CAP_SYS_RAWIO`, and
`CAP_SETPCAP`. This is still not a verified general-purpose root-first
environment: the target device must accept the dedicated enforcing domain, and
its effective policy must be shown to deny protected boot/system writes while
allowing intended ordinary paths. The app-side classifier and representative
`test -w` samples do not establish that boundary; visible approvals only cover
unclassified operations and do not constrain an arbitrary Root child. Keep the
Root gate closed until the device policy and actual worker are tested.

### 2026-09-25 device and KernelSU policy follow-up

Read-only ADB inspection of the connected Android 16 / SDK 36 Xiaomi reported
`getenforce=Enforcing`, KernelSU `su -V=32601`, and an ADB shell identity of
UID 0 in `u:r:ksu:s0`. That ADB shell is not the app's Root Profile child and
does not prove the Codex context is installed. Resolving the target nodes for
`boot_a`, `boot_b`, `vendor_boot_a`, `vbmeta_a`, and `super` showed labels
`boot_block_device`, `vendor_custom_ab_block_device`, and `super_block_device`.
Across the 236 physical block nodes under `/dev/block`, 29 distinct SELinux
types were observed; this device-specific evidence favors checking the block
device class as a whole rather than assuming boot partitions share one label.
No device node was opened for writing.

`/data/adb/ksud profile get-sepolicy io.henry.codex` returned “No such file or
directory”; no app-specific custom policy text was found or changed. A
read-only `ksud sepolicy check` returned success for a syntax-only sample that
defines/enforces `codex_agent`, adds `mlstrustedsubject`, and names three
observed block-device types. This command only runs KernelSU's strict text
parser (`parse_sepolicy(..., true)`); it does not apply rules, resolve their
effective access, or prove any denial. It is not a validated policy candidate.

Upstream KernelSU implements `deny` by clearing a permission bit from a
matching allow-vector entry; it is not a general SELinux `neverallow` rule.
Rules must therefore be checked against the active policy's direct and
attribute-derived grants, and then tested under the actual `codex_agent`
context. Also, `ksud profile set-sepolicy` persists the text before applying
it, while profile application uses the non-strict live-patch path; a successful
CLI exit is not proof that every rule was applied. Android Codex must not
silently write or auto-apply a Root Profile policy from Settings.
Sources pinned to the device's Manager/`ksud` release: [KernelSU v3.3.0 policy implementation](https://github.com/tiann/KernelSU/blob/v3.3.0/kernel/selinux/sepolicy.c),
[KernelSU v3.3.0 `ksud` policy/profile implementation](https://github.com/tiann/KernelSU/blob/v3.3.0/userspace/ksud/src/sepolicy.rs),
[KernelSU v3.3.0 profile persistence](https://github.com/tiann/KernelSU/blob/v3.3.0/userspace/ksud/src/profile.rs).

Feasibility update: launching a UID-0 Codex child with a custom enforcing
domain is supported in principle by KernelSU, but the requested “routine root
access plus protected boot/system writes” is not yet implemented or verified.
The current phone still rejects `u:r:codex_agent:s0`; the worker remains
blocked. A safe next device step requires an explicitly reviewed profile in
KernelSU Manager followed by the app-originated probe and real worker tests.
Until that happens, neither the parser check nor the ADB root shell may be
reported as Root Profile acceptance.
