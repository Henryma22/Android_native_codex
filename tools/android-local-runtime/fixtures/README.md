# Android app-server fixtures

`codex-approval-app-server.sh` is a deterministic, offline JSON-RPC fixture for
the independent `io.henry.codex` app. It is not a Codex binary and never
contacts a model. Run it only with a disposable workspace cwd containing
`README.md`.

The fixture responds to `initialize`, `thread/start`, and `turn/start`, then
sends one complete `item/fileChange/requestApproval` request. After an accepted
decision it writes the fixture text to `README.md` in its cwd and reports turn
completion. The app can therefore verify file-change preview, root-bound
pre-change backup, Host-side write, and restore without auth or network state.

For device acceptance, push the script to a disposable device path, make it
executable, select Root helper in the app, and enter the script as the custom
app-server command. Remove the pushed script, workspace, app-private backup,
and any UI dump after the run.

`codex-approval-runtime/` is the same deterministic protocol fixture in the
upstream-shaped `bin/codex` layout. Its manifest is
`../../manifests/codex-approval-fixture.manifest.json`; the bundle installer can
activate it in the fixed root slot so the default `codex` command exercises the
same UI path. It is a test fixture only and must be replaced with the official
bundle after the probe.

`codex-user-input-app-server.sh` exercises the transient
`item/tool/requestUserInput` path. After `turn/start` it presents two choices,
waits for the standard `answers` response, and completes without writing a
workspace file. It is also offline-only and should be run from a disposable
device path and workspace.
