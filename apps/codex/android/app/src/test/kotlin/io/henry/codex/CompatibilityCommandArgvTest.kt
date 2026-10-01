package io.henry.codex

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.nio.file.Files

class CompatibilityCommandArgvTest {
    @Test
    fun `guest tools come only from Debian and do not expose an Android toolchain`() {
        val guestPath = compatibilityGuestPath("app")

        assertTrue("/usr/bin" in guestPath)
        assertTrue("/system/bin" !in guestPath)
        assertTrue(
            guestPath.none { it.contains("native-tools") || it.contains("/data/local/tmp") },
        )
    }

    @Test
    fun `only Root PRoot maps the complete Android host root below android`() {
        val base = Files.createTempDirectory("codex-android-host-root").toFile()
        try {
            val rootfs = File(base, "rootfs").apply { mkdirs() }

            assertEquals(
                listOf("--bind=/:/android!"),
                compatibilityAndroidHostRootBindArguments("root", rootfs),
            )
            assertTrue(File(rootfs, "android").isDirectory)

            val appRootfs = File(base, "app-rootfs").apply { mkdirs() }
            assertTrue(compatibilityAndroidHostRootBindArguments("app", appRootfs).isEmpty())
            assertTrue(!File(appRootfs, "android").exists())
        } finally {
            base.deleteRecursively()
        }
    }

    @Test
    fun `compatibility PATH uses the Linux guest toolchain`() {
        val guestPath = compatibilityGuestPathDirectories()

        assertEquals("/opt/node/bin", guestPath.first())
        assertTrue(
            guestPath.indexOf(CompatibilityProcessManager.GUEST_CODEX_BASE_RESOURCES_DIRECTORY) <
                guestPath.indexOf("/usr/bin"),
        )
        assertTrue(
            guestPath.indexOf(CompatibilityProcessManager.GUEST_CODEX_BASE_PATH_DIRECTORY) <
                guestPath.indexOf("/usr/bin"),
        )
        assertTrue(guestPath.indexOf(CompatibilityProcessManager.GUEST_ADMIN_BIN) <
            guestPath.indexOf("/usr/bin"))
        assertTrue(guestPath.indexOf(CompatibilityProcessManager.GUEST_PACKAGE_PREFIX + "/usr/bin") <
            guestPath.indexOf("/usr/bin"))
        assertEquals(CompatibilityProcessManager.GUEST_PATH_DIRECTORIES, guestPath)
    }

    @Test
    fun `only Root guest PATH exposes Android host command directories`() {
        val appPath = compatibilityGuestPath("app")
        val rootPath = compatibilityGuestPath("root")

        assertTrue("/system/bin" !in appPath)
        assertTrue("/system/bin" in rootPath)
        assertTrue("/system/xbin" in rootPath)
        assertTrue("/vendor/bin" in rootPath)
        assertTrue("/android/system/bin" in rootPath)
        assertTrue("/android/system/xbin" in rootPath)
        assertTrue("/android/vendor/bin" in rootPath)
        assertTrue("/android/system/bin" !in appPath)
        assertTrue(rootPath.indexOf("/usr/bin") < rootPath.indexOf("/system/bin"))
    }

    @Test
    fun `guest package commands resolve from the bound app-private home`() {
        val root = Files.createTempDirectory("codex-compat-path").toFile()
        try {
            val rootfs = File(root, "rootfs").apply { mkdirs() }
            val home = File(root, "home").apply { mkdirs() }
            val packageCommand = File(
                home,
                ".local/codex-pkgs/usr/bin/tree",
            ).apply {
                parentFile!!.mkdirs()
                writeText("fixture")
            }

            val resolved = compatibilityGuestExecutableCandidate(
                rootfs = rootfs,
                guestHome = home,
                directory = "${CompatibilityProcessManager.GUEST_PACKAGE_PREFIX}/usr/bin",
                executable = "tree",
            )

            assertEquals(packageCommand, resolved)
            assertTrue(resolved.isFile)
        } finally {
            root.deleteRecursively()
        }
    }

    @Test
    fun `python command keeps working on guests that only ship python3`() {
        assertEquals(listOf("python", "python3"), compatibilityGuestExecutableNames("python"))
        assertEquals(listOf("node"), compatibilityGuestExecutableNames("node"))

        val root = Files.createTempDirectory("codex-python-alias").toFile()
        try {
            val rootfs = File(root, "rootfs").apply { mkdirs() }
            val home = File(root, "home").apply { mkdirs() }
            val python3 = File(rootfs, "usr/bin/python3").apply {
                parentFile!!.mkdirs()
                writeText("fixture")
            }

            val resolved = compatibilityGuestExecutableNames("python")
                .asSequence()
                .map { name ->
                    compatibilityGuestExecutableCandidate(
                        rootfs = rootfs,
                        guestHome = home,
                        directory = "/usr/bin",
                        executable = name,
                    )
                }
                .first { it.isFile }

            assertEquals(python3, resolved)
        } finally {
            root.deleteRecursively()
        }
    }

    @Test
    fun `guest package binaries load extracted dependency libraries without changing host env`() {
        val resolved = compatibilityGuestCommandArgv(
            executable = "tree",
            resolvedPath = "${CompatibilityProcessManager.GUEST_PACKAGE_PREFIX}/usr/bin/tree",
            arguments = listOf("--version"),
        )

        assertEquals(
            listOf(
                "/usr/bin/env",
                "LD_LIBRARY_PATH=${CompatibilityProcessManager.GUEST_PACKAGE_LIBRARY_PATH}",
                "${CompatibilityProcessManager.GUEST_PACKAGE_PREFIX}/usr/bin/tree",
                "--version",
            ),
            resolved,
        )

        val explicitPath = compatibilityGuestCommandArgv(
            executable = "tree",
            resolvedPath = "${CompatibilityProcessManager.GUEST_PACKAGE_PREFIX}/usr/bin/tree",
            arguments = emptyList(),
        )
        assertEquals(resolved.take(3), explicitPath)
    }

    @Test
    fun `Linux guest commands stay direct and app-installed packages get guest libraries`() {
        val arguments = listOf("--version")

        assertEquals(
            listOf("/usr/bin/npm", "--version"),
            compatibilityGuestCommandArgv(
                executable = "npm",
                resolvedPath = "/usr/bin/npm",
                arguments = arguments,
            ),
        )
        assertEquals(
            listOf("/usr/bin/env", "LD_LIBRARY_PATH=${CompatibilityProcessManager.GUEST_PACKAGE_LIBRARY_PATH}",
                "${CompatibilityProcessManager.GUEST_PACKAGE_PREFIX}/usr/bin/tree", "--version"),
            compatibilityGuestCommandArgv(
                executable = "tree",
                resolvedPath = "${CompatibilityProcessManager.GUEST_PACKAGE_PREFIX}/usr/bin/tree",
                arguments = arguments,
            ),
        )
    }
}
