package io.henry.codex

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class CompatibilityRootLaunchScriptTest {
    @Test
    fun `Root PRoot launch preserves KernelSU capabilities and UID`() {
        val command = build()

        assertEquals(listOf("/system/bin/sh", "-c", command.last()), command)
        assertTrue(command.last().contains("/data/adb/ksu/bin/su"))
        assertTrue(command.last().contains("'/data/adb/ksu/bin/su' '-c'"))
        assertFalse(command.last().contains("codex_agent"))
        assertFalse(command.last().contains("--ksu-no-new-privs"))
        assertTrue(command.last().contains("--root-codex-supervisor"))
        assertTrue(command.last().contains("libcodex_proot.so"))
        assertTrue(command.last().contains("--kill-on-exit"))
        assertTrue(command.last().contains(MARKER_PATH))
        assertTrue(command.last().contains("CODEX_COMPAT_PROCESS_MARKER"))
        assertTrue(command.last().contains("set -C"))
        assertFalse(command.last().contains("setuidgid"))
        assertTrue(command.last().contains("phone project"))
    }

    @Test
    fun `root probe and PRoot launch use the configured KernelSU profile`() {
        assertEquals(
            listOf(
                "/data/adb/ksu/bin/su",
                "-c",
                "id -Z",
            ),
            CompatibilityRootLaunchScript.rootSuArguments(
                "/data/adb/ksu/bin/su",
                "id -Z",
            ),
        )
        val probe = CompatibilityRootLaunchScript.rootProfileProbeCommand(
            "/data/app/io.henry.codex/lib/libcodex_worker_guard.so",
            "printf '%s\\n' 'safe probe'",
        )
        assertTrue(probe.startsWith("'exec' '/data/app/io.henry.codex/lib/libcodex_worker_guard.so'"))
        assertTrue(probe.contains("'--root-codex-profile-probe' '--'"))
        assertTrue(probe.contains("libcodex_worker_guard.so"))
        assertTrue(probe.contains("safe probe"))
        assertFalse(probe.contains("--ksu-no-new-privs"))
        assertThrows(IllegalArgumentException::class.java) {
            CompatibilityRootLaunchScript.rootSuArguments("/tmp/su", "id -Z")
        }
        assertThrows(IllegalArgumentException::class.java) {
            CompatibilityRootLaunchScript.rootProfileProbeCommand("/tmp/guard", "id")
        }
    }

    @Test
    fun `Root worker rechecks KernelSU identity before marker creation and PRoot`() {
        val command = build().last()
        val profileCheck = command.indexOf("root_profile_preflight")
        val markerCreation = command.indexOf("CODEX_COMPAT_PROCESS_MARKER=")
        val prootStart = command.indexOf("libcodex_proot.so")

        assertTrue(profileCheck >= 0)
        assertTrue(markerCreation > profileCheck)
        assertTrue(prootStart > markerCreation)
        assertTrue(command.contains("Uid:[[:space:]]*"))
        assertFalse(command.contains("u:r:codex_agent:s0"))
        assertFalse(command.contains("/system/bin/getenforce"))
        assertFalse(command.contains("root_gid"))
        assertFalse(command.contains("root_profile_fail readproc-group"))
        assertTrue(command.contains("root_profile_fail uid"))
        assertFalse(command.contains("NoNewPrivs"))
        assertFalse(command.contains("codex_protected_write_samples_passed"))
        assertTrue(command.contains("PRoot was not started"))
    }

    @Test
    fun `Root PRoot launcher rejects arbitrary helpers commands and marker paths`() {
        assertThrows(IllegalArgumentException::class.java) {
            build(suHelper = "/tmp/su")
        }
        assertThrows(IllegalArgumentException::class.java) {
            build(argv = listOf("/system/bin/sh", "-c", "id"))
        }
        assertThrows(IllegalArgumentException::class.java) {
            build(rootMarkerPath = "/tmp/root-worker.pid")
        }
        assertThrows(IllegalArgumentException::class.java) {
            CompatibilityRootLaunchScript.rootMarkerPath(
                "/tmp/no_backup",
                EXECUTION_ID,
            )
        }
        assertThrows(IllegalArgumentException::class.java) {
            CompatibilityRootLaunchScript.rootMarkerPath(
                "/data/user/0/io.henry.codex/no_backup",
                "../outside",
            )
        }
    }

    @Test
    fun `Root worker stop command signals only its validated process group`() {
        val command = CompatibilityRootLaunchScript.rootStopCommand(MARKER_PATH)

        assertTrue(command.contains(MARKER_PATH))
        assertTrue(command.contains("/system/bin/sleep 1"))
        assertTrue(command.contains("toybox grep -F -x"))
        assertTrue(command.contains("CODEX_COMPAT_PROCESS_MARKER="))
        assertTrue(command.contains("kill -TERM"))
        assertTrue(command.contains("kill -KILL"))
        assertTrue(command.contains("-\"\$pid\""))
        assertThrows(IllegalArgumentException::class.java) {
            CompatibilityRootLaunchScript.rootStopCommand("/tmp/root-worker.pid")
        }
    }

    @Test
    fun `Root launch loads environment from an app private file without embedding values`() {
        val secret = "provider-secret-not-in-argv"
        val command = build(
            environment = mapOf(
                "CODEX_HOME" to "/home/codex/sessions/test",
                "API_KEY" to secret,
            ),
            environmentFile = "/data/user/0/io.henry.codex/files/.codex-env-test.sh",
        )
        val rendered = command.joinToString(" ")

        assertTrue(rendered.contains("codex-env-test.sh"))
        assertTrue(rendered.contains("set -a"))
        assertTrue(rendered.contains("rm -f"))
        assertFalse(rendered.contains(secret))
    }

    @Test
    fun `stale marker cleanup keeps only a matching live process`() {
        val command = CompatibilityRootLaunchScript.rootCleanupStaleMarkersCommand(
            "/data/user/0/io.henry.codex/no_backup",
        )

        assertTrue(command.contains("compat-process-*.pid"))
        assertTrue(command.contains("/proc/\$pid/environ"))
        assertTrue(command.contains("CODEX_COMPAT_PROCESS_MARKER=\${marker}"))
        assertTrue(command.contains("rm -f \"\$marker\""))
        assertThrows(IllegalArgumentException::class.java) {
            CompatibilityRootLaunchScript.rootCleanupStaleMarkersCommand(
                "/tmp/no_backup",
            )
        }
    }

    @Test
    fun `Android host paths are bound only from the fixed list and only when present`() {
        val binds = CompatibilityRootLaunchScript.androidHostBindArguments(
            setOf("/data", "/system", "/dev", "/linkerconfig", "/tmp/user-path"),
        )

        assertEquals(
            listOf(
                "--bind=/data:/data!",
                "--bind=/system:/system!",
                "--bind=/linkerconfig:/linkerconfig!",
                "--bind=/dev:/dev!",
            ),
            binds,
        )
        assertTrue(binds.none { it.contains("/tmp/user-path") })
    }

    private fun build(
        suHelper: String = "/data/adb/ksu/bin/su",
        rootMarkerPath: String = MARKER_PATH,
        environment: Map<String, String> = mapOf(
            "CODEX_HOME" to "/home/codex/sessions/test",
            "PATH" to "/usr/bin:/bin:/system/bin",
        ),
        environmentFile: String = ENVIRONMENT_FILE,
        argv: List<String> = listOf(
            "/data/app/io.henry.codex/lib/libcodex_proot.so",
            "--kill-on-exit",
            "--root-id",
            "--rootfs=/data/user/0/io.henry.codex/files/rootfs",
        ),
    ): List<String> = CompatibilityRootLaunchScript.build(
        suHelper = suHelper,
        workerGuard = "/data/app/io.henry.codex/lib/libcodex_worker_guard.so",
        parentPid = 321,
        appUid = 10503,
        rootMarkerPath = rootMarkerPath,
        workingDirectory = "/storage/emulated/0/Codex/Workspaces/phone project",
        argv = argv,
        environment = environment,
        environmentFile = environmentFile,
    )

    private companion object {
        const val EXECUTION_ID = "12345678-1234-4234-8234-123456789abc"
        const val MARKER_PATH =
            "/data/user/0/io.henry.codex/no_backup/compat-root-processes/" +
                "compat-process-$EXECUTION_ID.pid"
        const val ENVIRONMENT_FILE =
            "/data/user/0/io.henry.codex/files/.codex-env-test.sh"
    }
}
