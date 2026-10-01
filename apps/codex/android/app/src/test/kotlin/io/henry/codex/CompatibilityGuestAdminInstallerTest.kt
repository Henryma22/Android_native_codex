package io.henry.codex

import java.io.File
import java.nio.file.Files
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class CompatibilityGuestAdminInstallerTest {
    @Test
    fun `installs the bundled helper under the private guest home and is idempotent`() {
        val home = Files.createTempDirectory("codex-guest-home").toFile()
        try {
            val script = validScript()
            val installer = CompatibilityGuestAdminInstaller { script }

            val first = installer.ensureInstalled(home)
            val second = installer.ensureInstalled(home)

            assertEquals(File(home, ".local/codex-admin/bin/sudo"), first)
            assertEquals(first, second)
            assertTrue(first.isFile)
            assertTrue(first.canExecute())
            assertTrue(first.readBytes().contentEquals(script))
            assertEquals(first, CompatibilityGuestAdminInstaller.sudoShim(home))
            val commandShim = File(home, ".local/codex-admin/bin/cmd")
            assertTrue(commandShim.isFile)
            assertTrue(commandShim.canExecute())
            assertTrue(commandShim.readText().contains("exec /system/bin/cmd \"\$@\""))
            val packageManagerShim =
                CompatibilityGuestAdminInstaller.androidPackageManagerShim(home)
            assertEquals(File(home, ".local/codex-admin/bin/pm"), packageManagerShim)
            assertTrue(packageManagerShim.readText().contains("exec /system/bin/cmd package"))
            val settingsShim = CompatibilityGuestAdminInstaller.androidSettingsShim(home)
            assertEquals(File(home, ".local/codex-admin/bin/settings"), settingsShim)
            assertTrue(settingsShim.readText().contains("exec /system/bin/cmd settings"))
            val appOpsShim = CompatibilityGuestAdminInstaller.androidAppOpsShim(home)
            assertEquals(File(home, ".local/codex-admin/bin/appops"), appOpsShim)
            assertTrue(appOpsShim.readText().contains("exec /system/bin/cmd appops"))
            val windowManagerShim = CompatibilityGuestAdminInstaller.androidWindowManagerShim(home)
            assertEquals(File(home, ".local/codex-admin/bin/wm"), windowManagerShim)
            assertTrue(windowManagerShim.readText().contains("exec /system/bin/cmd window"))
            val deviceConfigShim = CompatibilityGuestAdminInstaller.androidDeviceConfigShim(home)
            assertEquals(File(home, ".local/codex-admin/bin/device_config"), deviceConfigShim)
            assertTrue(deviceConfigShim.readText().contains("exec /system/bin/cmd device_config"))
            val devicePolicyShim = CompatibilityGuestAdminInstaller.androidDevicePolicyShim(home)
            assertEquals(File(home, ".local/codex-admin/bin/dpm"), devicePolicyShim)
            assertTrue(devicePolicyShim.readText().contains("exec /system/bin/cmd device_policy"))
            val imeShim = CompatibilityGuestAdminInstaller.androidImeShim(home)
            assertEquals(File(home, ".local/codex-admin/bin/ime"), imeShim)
            assertTrue(imeShim.readText().contains("exec /system/bin/cmd input_method ime"))
            val inputShim = CompatibilityGuestAdminInstaller.androidInputShim(home)
            assertEquals(File(home, ".local/codex-admin/bin/input"), inputShim)
            assertTrue(inputShim.readText().contains("exec /system/bin/cmd input"))
            val lockSettingsShim = CompatibilityGuestAdminInstaller.androidLockSettingsShim(home)
            assertEquals(File(home, ".local/codex-admin/bin/locksettings"), lockSettingsShim)
            assertTrue(lockSettingsShim.readText().contains("exec /system/bin/cmd lock_settings"))
            for (name in CompatibilityGuestAdminInstaller.ANDROID_HOST_COMMAND_NAMES) {
                val hostShim = CompatibilityGuestAdminInstaller.androidHostCommandShim(home, name)
                assertEquals(File(home, ".local/codex-admin/bin/$name"), hostShim)
                assertTrue(hostShim.readText().contains("exec /android/system/bin/$name"))
            }
        } finally {
            deleteTree(home)
        }
    }

    @Test
    fun `refuses to replace an unexpected preexisting helper`() {
        val home = Files.createTempDirectory("codex-guest-home").toFile()
        try {
            val target = File(home, ".local/codex-admin/bin/sudo")
            assertTrue(target.parentFile!!.mkdirs())
            target.writeText("unexpected content")

            assertThrows(IllegalArgumentException::class.java) {
                CompatibilityGuestAdminInstaller { validScript() }.ensureInstalled(home)
            }
            assertEquals("unexpected content", target.readText())
        } finally {
            deleteTree(home)
        }
    }

    @Test
    fun `upgrades previous bundled helper versions`() {
        val home = Files.createTempDirectory("codex-guest-home").toFile()
        try {
            val target = File(home, ".local/codex-admin/bin/sudo")
            assertTrue(target.parentFile!!.mkdirs())
            val currentScript = validScript()
            for (version in listOf(1, 2)) {
                target.writeText("#!/bin/sh\n# codex-guest-admin-version=$version\nold\n")
                val installed =
                    CompatibilityGuestAdminInstaller { currentScript }.ensureInstalled(home)
                assertTrue(installed.readBytes().contentEquals(currentScript))
            }
        } finally {
            deleteTree(home)
        }
    }

    @Test
    fun `rejects a malformed or oversized bundled helper`() {
        val home = Files.createTempDirectory("codex-guest-home").toFile()
        try {
            assertThrows(IllegalArgumentException::class.java) {
                CompatibilityGuestAdminInstaller { "#!/bin/sh\necho unsafe\n".toByteArray() }
                    .ensureInstalled(home)
            }
            assertThrows(IllegalArgumentException::class.java) {
                CompatibilityGuestAdminInstaller {
                    ("#!/bin/sh\n# codex-guest-admin-version=3\n" +
                        "x".repeat(CompatibilityGuestAdminInstaller.MAX_SCRIPT_BYTES))
                        .toByteArray()
                }.ensureInstalled(home)
            }
            assertTrue(File(home, ".local").isDirectory)
            assertTrue(!File(home, ".local/codex-admin/bin/sudo").exists())
        } finally {
            deleteTree(home)
        }
    }

    private fun validScript(): ByteArray =
        "#!/bin/sh\n# codex-guest-admin-version=3\nexit 0\n".toByteArray()

    private fun deleteTree(root: File) {
        if (!root.exists()) return
        Files.walk(root.toPath()).use { paths ->
            paths.sorted(Comparator.reverseOrder()).forEach(Files::deleteIfExists)
        }
    }
}
