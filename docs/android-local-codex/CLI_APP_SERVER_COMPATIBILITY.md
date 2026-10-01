# Android Codex CLI / app-server compatibility

Updated: 2026-10-01  
Scope: the independent `apps/codex` Android app only.  
Policy: use runtime capability responses and protocol fields, not a hard-coded
Codex version allowlist.

## Linux/PRoot rootfs import and replacement

The Android Settings page now exposes the Linux/PRoot rootfs state and an
install/update action. Select a folder containing exactly one `.tar.gz` rootfs
and its matching `<archive-name>.manifest.json`, as produced by
`tools/android-local-runtime/builder/build-rootfs.sh`. The app copies the
selection to private staging, verifies the ARM64 manifest, file size and
SHA-256, scans tar paths/types/modes/symlinks before Root is invoked, then uses
the normal KernelSU profile to finalize and probe the guest on-device. The
the new immutable app-private runtime slot is switched only after the guest
checks pass by atomically replacing an active-slot pointer; the shared
`/home/codex` tree is carried forward. Existing workers keep their already-
resolved rootfs path and are not stopped; new workers resolve the newly
published slot. The runtime lifecycle lock only serializes publication with a
concurrent launch.

The manifest hash detects mismatch/corruption but is not a publisher
signature. Import only a rootfs artifact and manifest from a trusted build or
release source. Rootfs delivery is currently local-file import, not an
in-app OTA feed; Codex CLI overlay updates remain separately available through
the official npm registry updater.

## Current runtime and update boundary (2026-10-01)

The supported Codex execution route is the official Linux ARM64 CLI/app-server
inside the local PRoot rootfs. The Settings updater changes the Linux CLI
overlay independently of the APK and rootfs. Android/Bionic Codex build,
import, update, restore, and packaged `libcodex.so` paths have been retired;
the APK verifier rejects that executable. The separate Android/Bionic toolchain
for git/node/npm/python has also been retired; those developer tools come from
the Debian guest, while commands that specifically control Android use the
Android host's own OS binaries.

The PRoot updater publishes a verified CLI overlay with rollback. Its
maintenance command runs from an app-private runtime directory, not a user
workspace. This keeps the CLI overlay, rootfs and APK lifecycle decoupled.
Existing app-server processes keep their current executable handles; newly
started sessions resolve the selected CLI after the switch.

The latest physical-device check found the official npm registry at
`@openai/codex 0.159.2`, matching the active overlay. The updater therefore
completed its no-op path and left the active launcher and running Root session
unchanged; a higher-version download/activation test must wait until the
registry publishes one.

### Historical Android/Bionic runtime record (retired)

Historical device evidence: on 2026-09-25 the connected ARM64 device imported
and verified an Android/Bionic `codex-cli 0.156.1` built from upstream commit
`b412ff32c417f855c2b2d1581b77058eed87c84b`. The Settings model tile reported
13 CLI models at that time; this is not a statement about the current APK.

The old Android/Bionic patch, release recipe, APK asset, updater, and restore
controls were removed on 2026-09-28. The historical update and migration issues
above are closed by retiring that runtime path rather than maintaining a second
Codex CLI distribution.

## Connected behavior

| Capability | Current app integration | Boundary / failure behavior |
| --- | --- | --- |
| Login and local process | CLI-owned auth files and one app-server process per session | Android UI owns OAuth browser handoff; a CLI TUI is not embedded |
| Thread lifecycle | `thread/start`, `thread/resume`, `turn/start`, `turn/interrupt` | Durable local history stores the app-server thread ID; the app does not import the CLI's entire thread database into its home list |
| Concurrent sessions | A separate process, CODEX_HOME, temp/SQLite state, and event stream per app session | App-level concurrency, not a global active-process singleton |
| Models | `model/list` plus `codex debug models` bundled/online sources; merge by model ID and parse display/effort fields | Dynamic catalog is authoritative; cached model data is only a fallback |
| Reasoning / plan / permissions | Model and effort are sent on turns; plan mode uses collaboration mode; approval/sandbox choices are sent through app-server settings; when exposed, `permissionProfile/list` supplies named profiles and the selected ID is sent as `permissions` | Fresh Root sessions default to `danger-full-access` + `approvalPolicy=never`; saved sessions retain their stored values, and `read-only` remains an explicit user-selected mode. Profile discovery is user-triggered and falls back to legacy `sandboxPolicy` for older servers, so optional capability discovery cannot block a normal turn |
| Usage / context | `account/rateLimits/read` and `thread/tokenUsage/updated` feed quota and context indicators | Missing server usage data is displayed as unavailable, not fabricated |
| Images | App-server `type: image` with data URL; provider transport uses its separate OpenAI-compatible `image_url` shape | Picker bounds count/size; raw image bytes are not stored in history |
| Approvals | Command/file/permission approvals, structured Codex input, and MCP `form`/`url` elicitation; MCP tool approvals expose only advertised once/session/always choices | Persistent choices are hidden for Root sessions; unknown methods and unsupported elicitation modes never auto-approve |
| CLI commands | `/version`, `/cli-help`, and `/cli <args>` parse quoted arguments into argv without invoking a shell; `/cli thread list [--archived] [--search <term>] [--json]` reads paginated thread metadata from the active app-server; `/cli login status` reads the current runtime status; `/cli mcp list/get/status/add/remove/login/logout` and `/cli plugin list/marketplace list/add/remove/enable/disable` plus `plugin marketplace list/add/remove/upgrade` use the active session app-server or the session-scoped CLI where the protocol has no logout RPC; config/plugin mutations are version-checked or app-server-owned; OAuth authorization opens through the Android browser | Thread listing is scoped to the current app session's isolated `CODEX_HOME` and workspace; it is not cross-session or external CLI history import; the safe JSON omits rollout storage paths; MCP and plugin changes affect only this session's isolated `CODEX_HOME`; plugin output redacts local marketplace paths; plugin enablement uses app-server `config/value/write`, rejects overridden writes, and refreshes the visible catalog after Settings actions; stdio `--env` values are stored in its config file; OAuth callback and credential exchange remain app-server-owned, using its loopback listener; `mcp logout` runs only as a bounded argv in the active session home and never through a shell; interactive TUI commands are not launched; live status is only queried on explicit command (not polled) |
| Dependency tools | Codex uses Debian Linux ARM64 guest tools and package managers inside PRoot; Android host commands use the Android OS binaries | App UID remains the real Android UID when selected; guest `root` alone does not imply Android UID 0 |

The app-server transport uses JSON-RPC and does not reject a runtime merely
because its version string changed. `model/list` pagination and catalog fields
are parsed dynamically. New notification types that are not consumed are
ignored; unsupported server-initiated requests are rejected explicitly. This
prevents many version-only failures, but it does not create feature parity
automatically.

The session-local `/network-test` command starts Python under the current
session's App UID or Root/PRoot identity and checks unauthenticated provider
origins using the same inherited DNS, CA, and proxy environment. An HTTP
401/403 is reported as transport reachability with authentication still
required. The probe sends no credentials, prompt, or model request. It tests
the route with Python's HTTP stack and reports only the configured proxy's
scheme/host/port (never user-info); a pass alone does not prove Codex's Rust
HTTP client or an authenticated model turn succeeds.

## Third-party provider boundary

The custom provider is launched through the same Codex app-server as OpenAI,
using the native `model_provider`, `wire_api = "responses"`, and
`requires_openai_auth = false` configuration overrides. Therefore the active
session keeps the app-server thread/turn, local tools, workspace, approvals,
plan mode, and Root execution behavior; selecting a custom provider does not
silently switch to a separate chat-only client. OpenAI auth remains available
for other sessions, but the selected custom-provider session does not require
it.

Codex has no universal capability-discovery protocol for an arbitrary external
Responses provider. The provider settings therefore persist an explicit
`reasoningEfforts` list and the session model catalog exposes exactly that list.
Existing DeepSeek configurations migrate to `none, low, high, max`; other
providers default to `low` until the user enters the labels documented by that
service. Unknown labels are not guessed or hidden: they are passed through to
the installed Codex runtime, which remains authoritative for request validity.
The UI shows the list in provider settings and exposes the effort control for
all app-server custom providers. Vendor-specific wire fields are still only
added where the provider adapter explicitly knows them.

## MCP server elicitations

`mcpServer/elicitation/request` is routed to the CC Pocket-based session card.
The form renderer handles object fields containing strings, numbers/integers,
booleans, single-select string enums, and multi-select string enum arrays; it
validates required fields and advertised bounds/formats before sending the
MCP `{action, content}` result. Legacy `openai/form` and `openaiForm` names use
the same constrained renderer. Unsupported JSON-schema shapes can only be
declined or canceled.

For MCP tool approvals (`_meta.codex_approval_kind == "mcp_tool_call"`), the
card shows tool details and an allow-once action. Session/always actions are
shown only when `_meta.persist` advertises that scope, and the response sends
that scope in response `_meta.persist`. Root-identity sessions hide both
persistent options. URL-mode requests require an explicit user tap to open a
validated HTTPS or loopback-HTTP URL, then a separate confirmation to continue.
`openai/userVerification` and unknown modes remain non-approvable; native
attestation/proof generation is not implemented.

The source and protocol/UI tests cover these paths. Real MCP server handoff,
external browser return, and persisted approval behavior still require device
acceptance and are not inferred from widget tests. Historical app-server
0.156.1 device evidence returned an HTTP(S) authorization URL and emitted
`mcpServer/oauthLogin/completed`; the current dynamic 0.159.2 path keeps the
same app-server-owned callback contract without an app-side version allowlist.
Its callback listener uses an OS-assigned loopback port. Logout has no
corresponding app-server RPC and is intentionally not run through an isolated
one-shot CLI.

## Device dependency-install smoke (2026-09-23)

On the connected ARM64 Android device, Node `v22.23.2` and npm `10.9.2` ran;
npm fetched and installed `is-number@7.0.0` from the public registry and Node
loaded the installed module. The ADB shell was verified as KernelSU `uid=0`
(`u:r:ksu:s0`), so this only proves Android/Bionic execution and registry
networking in that privileged context. App UID execution and package installs
inside the app's PRoot guest are still not verified. The first attempt also
showed that an unset `HOME` makes npm default to an unwritable `/.npm`; passing
an explicit cache directory fixed that isolated smoke. Its temporary directory
was removed after the test.

## Native Android toolchain command matrix (2026-09-25)

A read-only PATH smoke on the physical ARM64 device successfully ran `bash`,
`git`, `jq`, `node`, `npm`, `npx`, `python`, and `rg` from the installed
toolchain. `adb shell id` reported UID 0 / `u:r:ksu:s0` from an existing
authorization; no additional `su` approval was requested. This verifies the
ARM64 payload in that privileged context, not the app's UID or app-UID PRoot
execution.

The available `codex_api35` AVD is x86_64. A temporary debug-app probe routed
the ARM64 binaries through Android's translation runner and produced
architecture/loader errors, so it is not valid app-UID evidence for the target
ABI. The temporary emulator package, staged bundle, archive, and AVD process
were removed/stopped afterward; the connected phone's app and session were not
replaced or foregrounded. App-UID and PRoot execution remain unverified.

## Not yet wired to the CC Pocket-style Android UI

These are concrete gaps from the current source, not promises about upstream
availability:

1. The active-session `/cli thread list` path now reads paginated current or
   archived thread metadata through app-server. It sends the richer filtering,
   sorting, workspace, and state-db hints when available, and retries with the
   core archive/cursor/limit shape only when the server explicitly rejects
   those newer parameters; search is then applied locally. Cross-session workspace
   browsing, external CLI history import, and opening an arbitrary returned
   thread into a new isolated app session are still not integrated. Resume
   works for thread IDs already saved by this app.
2. Fork/duplicate is now wired to the active session and Home session actions.
   `CodexSessionClient.forkThread()` sends the provider's `thread/fork` RPC and
   reads the returned child thread id and rollout path. The app then copies
   only that provider-created rollout file into a new session's isolated
   `CODEX_HOME` using fixed `mkdir`/`cp` argv, creates a new app-owned history
   record, and opens the child session. Reopening the child sends both its
   thread id and `thread/resume.path`; the native-to-PRoot fallback path also
   preserves the rollout path. `/cli fork` and both active/inactive session
   menus use the same implementation, so the app never shares the source
   session's SQLite, temp directory, process, or event stream. If an older
   CLI does not return a usable rollout path, the app fails explicitly instead
   of fabricating a shared-home fork. Diff-based branch switching, an
   arbitrary cross-session thread picker, and external CLI history import are
   still not integrated. Historical `0.156.1` source used for protocol
   reference exposes `thread/fork` in app-server v2 ([protocol registration](https://github.com/openai/codex/blob/b412ff32c417f855c2b2d1581b77058eed87c84b/codex-rs/app-server-protocol/src/protocol/common.rs#L537-L542),
   [thread parameters](https://github.com/openai/codex/blob/b412ff32c417f855c2b2d1581b77058eed87c84b/codex-rs/app-server-protocol/src/protocol/v2/thread.rs)).
3. The complete app-server approval/request surface is not represented in UI.
   The common approval/input families include advertised `acceptForSession`,
   command-prefix, and network-policy decisions; MCP form/URL elicitation and
   advertised tool-approval persistence now have a UI. Device validation is
   pending; `openai/userVerification` and future request families remain
   fail-closed and unsupported. As of the upstream app-server documentation
   checked on 2026-09-25, user verification is experimental and is advertised
   only to supported TUI/Desktop clients, not mobile. The local flow requires
   a device-authenticated key lifecycle, signed challenge proof, explicit
   cancellation, and late-proof handling; an Android biometric/credential
   prompt alone is not a protocol implementation. This app does not advertise
   that capability and must keep such requests non-approvable until upstream
   provides a mobile rollout and this full flow is implemented.
4. A full interactive CLI TUI and background shell-job browser are not
   implemented. The active session exposes streamed app-server `command/exec`
   through `/exec <argv...>`: it sends a stable connection-scoped `processId`,
   projects `command/exec/outputDelta` into the current session transcript, and
   routes interrupt to `command/exec/terminate`. `/exec --tty <argv...>` now
   opens a session-scoped PTY panel with stdin input, 80x24/120x40 resize
   presets, live output, and interrupt/close handling. The command stays in the
   same session process, workspace, and permission profile. The client-level
   `command/exec/write` and `command/exec/resize` primitives are covered by
   protocol fixtures and the panel was verified on the ARM64 Root/PRoot device.
   The panel is a focused command surface, not a replacement for the full
   interactive Codex CLI TUI. `/cli` remains a bounded one-shot argv interface,
   not a free-form shell.
   Quotes only group arguments; shell expansion, pipes, redirection, and
   command substitution are never run.
5. Full evolving settings and marketplace management still do not have
   dedicated Android screens. The CC Pocket-style `MCP & plugins` settings
   page for the selected session now reads the redacted configured-server list,
   reads live connection status on demand, supports stdio/HTTP add, removal,
   browser OAuth login, plugin catalog listing, plugin install/uninstall, and
   plugin marketplace add/remove/upgrade, all through the active app-server.
   `/cli mcp list`, its redacted `--json`
   form, and `mcp get <name>` remain available for command-oriented users.
   The Android-specific `/cli mcp status [--json]` requests live connection
   status once on user action; it does not poll, and its output omits tools,
   raw errors, capabilities, and credentials. `/cli mcp add` and `/cli mcp remove`
   now mutate only the active session's base user config:
   both read config layers, reject same-name definitions in other layers, use
   the observed user-layer version in `config/batchWrite`, request
   `reloadUserConfig`, then verify effective state. Add supports stdio
   (`--env KEY=VALUE -- COMMAND [ARGS...]`) and streamable HTTP (`--url URL`,
   optionally `--bearer-token-env-var ENV_NAME`). Literal stdio `--env` values
   are stored in that session's local `CODEX_HOME/config.toml`; avoid this for
   secrets that must remain in an OS-protected credential store. The changes
   are session-scoped because each app session has its own `CODEX_HOME`, and a
   read-only session rejects add. `/cli plugin list` and
   `/cli plugin marketplace list` read the active app-server catalog;
   `/cli plugin add/remove` and `/cli plugin marketplace add/remove/upgrade`
   call the active app-server mutation methods and require a writable session.
    MCP logout has no corresponding app-server RPC; the app therefore runs the
    bounded `codex mcp logout <server>` command inside the active session's
    isolated CODEX_HOME instead of pretending that an app-server method exists.
    Real device acceptance with an existing OAuth credential remains pending.
    Plugin enable toggles and the remaining evolving
   catalog controls remain available through `/cli plugin`; the Android
   settings page and `/cli plugin enable|disable` now write the plugin's
   enablement through the active app-server config protocol. The catalog keeps
   its workspace/refresh hints on newer servers and retries the base
   `plugin/list` shape only when those optional fields are explicitly rejected.
   See the upstream [MCP CLI](https://github.com/openai/codex/blob/main/codex-rs/cli/src/mcp_cmd.rs)
   and [app-server config protocol](https://github.com/openai/codex/blob/main/codex-rs/app-server-protocol/src/protocol/v2/config.rs)
   for the evolving command and config surfaces.
6. The updater has host-side tests for version comparison, stage verification,
   activation, and rollback. On 2026-10-01 the physical device completed the
   npm registry check and the idempotent no-op path with latest `0.159.2`:
   the active overlay remained `versions/0.159.2`, the versioned CLI returned
   `codex-cli 0.159.2`, and existing app data was preserved. A higher-version
   download/activation/rollback and post-update model refresh remain pending
   until the registry exposes a newer version.

## Upgrade acceptance

After installing a release that contains the updater:

1. Update from Settings on a connected device and record old/new CLI versions.
2. Confirm a failed or interrupted stage leaves the selected CLI unchanged.
3. Confirm `codex --version` resolves to the overlay while the shipped rootfs
   manifest still reports its original package version.
4. Confirm the model catalog refreshes automatically and GPT-6 Sol/Luna become
   selectable; if the refresh failed, retry from the Model tile.
5. Start and resume separate sessions; check streaming, usage, approvals, and
   CLI model selection still work after the upgrade.
6. If activation verification fails, confirm the prior symlink (or bundled
   CLI when no overlay existed yet) is restored.
7. With a harmless MCP fixture, answer a form, deny/cancel another request,
   exercise an advertised tool-approval persistence choice, and complete a URL
   handoff. Confirm Root sessions do not offer persistent choices and
   `openai/userVerification` is not accepted.

References: [official Codex releases](https://github.com/openai/codex/releases/latest),
[upstream npm platform-package builder](https://github.com/openai/codex/blob/main/codex-cli/scripts/build_npm_package.py),
[app-server README](https://github.com/openai/codex/blob/main/codex-rs/app-server/README.md),
[KernelSU module guide](https://github.com/tiann/KernelSU/blob/main/website/docs/guide/module.md).
