---
name: ccpocket-kernelsu-plugin
description: Build and operate an optional reversible KernelSU module for Android system changes. Use it when a module is the clearest route; ordinary rooted work stays on the normal Root/PRoot path, and explicitly authorized boot-sensitive work is not permanently blocked merely because a broker cannot express it.
---

# CC Pocket KernelSU plugin workflow

Use this skill for the method, not for one particular system modification. A
plugin is an optional small, reviewable capability request. Linux work,
package installation inside the PRoot guest, ordinary Root operations, and
ordinary app-configuration edits stay on their normal execution paths. Use a
KernelSU module when Android itself must change and a reversible module is a
good fit; do not turn this workflow into a universal privilege broker.

## Operating boundary

When a reversible module is the chosen route, use the local `ccpocket-android`
MCP tools exposed by the running worker:

1. `android_capabilities`
2. `plugin_stage`
3. `plugin_apply`
4. `plugin_list`, `plugin_enable`, `plugin_disable`, `plugin_rollback`,
   `plugin_uninstall`, and `plugin_run_action` when the task requires them

Do not use these module tools for ordinary Codex commands. The normal Root
runtime may invoke the user's configured KernelSU `su` path for ordinary work
and for a specifically authorized direct system operation. Module operations
still accept only module IDs, declared action IDs, and a bounded archive; do
not pass caller-supplied shell text or environment through the broker. Do not
read or print tokens, root output, staging paths, or diagnostic exceptions.

## Workflow

1. Describe the Android capability in terms of the smallest desired effect,
   the target Android component, whether a reboot is needed, and how to undo
   it. Keep all generation and testing files in the current Linux workspace.
2. Decide the lowest honest risk level:
   - **R0**: Linux-only or an ordinary user service. Do not make a plugin.
   - **R1**: a reversible declarative overlay with no executable script,
     symlink, hardlink, hook, boot-sensitive target, or reboot requirement.
     It must declare a broker-safe module root in `overlayRoots`; an archive
     with an empty `overlayRoots` list is R0 and must not be sent to
     `plugin_apply`. It may be applied automatically by the broker.
   - **R2**: an action script, root setting, non-trivial overlay, or anything
     requiring backup and health checks. Stage it, then wait for user approval.
   - **R3**: boot-sensitive files, early-boot hooks, SELinux rules, broad
     system overlays, or any module requiring reboot. Stage disabled and wait
     for explicit device-credential confirmation before enabling.
   - **R4**: boot image/partition writes, kernel modules, KernelSU changes,
     raw block access, or other boot-chain changes. Do not execute them
     implicitly. Validate the exact target, device/slot, backup and recovery
     path, explain the concrete brick risk, and obtain authorization for that
     operation. Prefer a reversible module when it fits, but an authorized
     direct route remains available when the module workflow cannot perform the
     requested function.
3. Choose a new lowercase ID of the form `ccpocket.plugin.<slug>`. Keep the
   suffix short and stable. Do not reuse another module's ID or touch modules
   outside this namespace.
4. Create a KernelSU ZIP in the workspace with exactly these required
   members:
   - `module.prop`, containing `id`, `name`, `version`, `versionCode`,
     `author`, and `description`;
   - `ccpocket-plugin.json`, containing exactly:
     `schemaVersion`, `id`, `name`, `version`, `capabilities`, `riskHint`,
     `requiresReboot`, `reversible`, `overlayRoots`, `actions`,
     `backupTargets`, and `healthChecks`;
   - only the payload and declared scripts needed for the capability.
   Use relative ZIP member names. Do not add symlinks, hardlinks, device
   nodes, FIFOs, setuid files, or unexplained generated content.
5. Make the manifest truthful. `riskHint` is only a declaration; the broker
   independently classifies archive members, paths, scripts, reboot flags,
   actions, and reversibility. For R2/R3, declare concrete backup targets and
   health-check IDs. An action is an ID looked up by the broker, never shell
   text supplied to MCP.
6. Validate the ZIP locally before submitting it: inspect its member list,
   ensure `module.prop` and the JSON parse, confirm the ID fields match, check
   that all paths stay inside the module, and run the smallest relevant test.
   Do not claim broker approval from local validation alone.
7. Compute the SHA-256 of the exact ZIP bytes, base64-encode those same bytes,
   and call `plugin_stage` with a fresh opaque `requestId`, the digest, and
   `archiveBase64`. `archiveBase64` must be one canonical single-line Base64
   string: no newline, whitespace, URL-safe substitutions, or implicit line
   wrapping. On Debian, use `base64 -w 0 plugin.zip` (or an equivalent
   no-wrap command) and verify that decoding and re-encoding produces the
   identical string before calling MCP. Keep the archive in memory or in the
   workspace; never pass a filesystem path to MCP.
8. Inspect the structured result and actual broker risk. Call `plugin_apply`
   for the staged request:
   - R1 should return the fixed install-and-enable operation and become
     usable without a user prompt;
   - R2/R3 should return `approval_required` with an opaque request ID. Tell
     the user what capability is waiting, then stop and wait for the GUI's
     approval. Never attempt to approve your own request through MCP;
   - A broker rejection means the module route is unavailable or unsafe for
     that archive; do not weaken the archive or retry with a lower hint. If the
     user still needs the function, return to the validated normal Root path
     and the explicit-authorization route instead of silently declaring the
     capability unsupported.
9. After a successful operation, call `plugin_list` and verify only the
   structured module ID, state, effective risk, and `pendingReboot` flag.
   For a rebooting module, ask the user to reboot; the app never reboots the
   device automatically. After reboot, use the broker/UI health-check flow.
10. If the effect is wrong or the health check fails, disable or rollback the
    broker-owned module. Use `plugin_rollback` only when the broker reports a
    verified previous archive. Report the structured result, not root output.

## Reusable module template

```text
<workspace>/plugin/<slug>/
├── module.prop
├── ccpocket-plugin.json
└── <payload and, only for R2/R3, declared action files>
```

Example manifest shape (replace every example value with task-specific values):

```json
{
  "schemaVersion": 1,
  "id": "ccpocket.plugin.example",
  "name": "Example capability",
  "version": "0.1.0",
  "capabilities": ["example-overlay"],
  "riskHint": "R1",
  "requiresReboot": false,
  "reversible": true,
  "overlayRoots": ["/data/adb/modules/ccpocket.plugin.example"],
  "actions": [],
  "backupTargets": [],
  "healthChecks": []
}
```

A metadata-only archive with no `overlayRoots` is still R0. For a harmless R1
fixture, declare the broker-safe KernelSU module root (for example
`/data/adb/modules` or the module-specific path below it), keep
`requiresReboot` false, and include no actual Android system overlay payload,
scripts, hooks, actions, or boot-sensitive files. The declaration makes the
target root explicit; it does not grant access to arbitrary Android paths.

The example is a shape, not a permission grant. A target outside the broker's
safe declarative roots, a reboot flag, a script, an action, or a non-reversible
claim raises the effective risk regardless of `riskHint`. Do not turn an R2
or R3 task into R1 by changing metadata.

## Completion report

Return a short report with: capability requested; module ID; broker-reported
effective risk; stage/apply result; whether approval or reboot is pending;
health/rollback result; and any remaining user action. Never include ZIP
contents, tokens, root stdout/stderr, absolute paths, or exception text.
