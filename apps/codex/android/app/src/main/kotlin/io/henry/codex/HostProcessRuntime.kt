package io.henry.codex

import android.content.Context
import java.io.File

/**
 * Process ownership shared by the Flutter activity and the foreground
 * session service. Keeping one manager in the application process means an
 * Activity/Flutter-engine detach does not implicitly kill an approved local
 * app-server; the explicit session Stop action still does.
 */
internal object HostProcessRuntime {
    const val HOST_WORKSPACE_ROOT = "/storage/emulated/0/Codex/Workspaces"

    private val rootHelpers = listOf(
        "/data/adb/ksu/bin/su",
        "/system/bin/su",
        "/system/xbin/su",
    )

    @Volatile
    private var instance: HostProcessManager? = null

    fun manager(context: Context): HostProcessManager = synchronized(this) {
        instance ?: HostProcessManager(
            workspaceRoot = HOST_WORKSPACE_ROOT,
            rootHelpers = rootHelpers,
            hostCommandHome = File(context.filesDir, "host-command-home"),
            networkEnvironment = {
                CompatibilityNetworkConfiguration.localRuntimeEnvironment(
                    context.applicationContext,
                )
            },
            rootProfileProbe = {
                AndroidRootProfileProbe(context.applicationContext).run()
            },
        ).also {
            instance = it
        }
    }

    fun stopAll() {
        instance?.stopAll()
    }
}
