package io.henry.codex

import java.io.ByteArrayOutputStream
import java.io.File
import java.io.InputStream
import java.nio.file.Files
import java.nio.file.StandardCopyOption

/**
 * Installs the fixed guest-admin shim and Android command adapters in the
 * writable guest home.
 *
 * The bundled `sudo` asset has two intentionally different execution paths:
 * a real Root PRoot worker passes the requested Linux command through because
 * it already has the required guest identity, while an App-UID worker uses
 * the private package prefix.  Neither path is an Android privilege broker.
 */
internal class CompatibilityGuestAdminInstaller(
    private val readBundledScript: () -> ByteArray,
) {
    fun ensureInstalled(home: File): File {
        require(home.isDirectory && !Files.isSymbolicLink(home.toPath())) {
            "compatibility guest home is unavailable or unsafe"
        }
        var parent = home
        for (name in listOf(".local", "codex-admin", "bin")) {
            val child = File(parent, name)
            require(!Files.isSymbolicLink(child.toPath())) {
                "compatibility guest admin directory must not be a symlink"
            }
            if (!child.exists()) {
                require(child.mkdir()) {
                    "compatibility guest admin directory could not be created"
                }
            }
            require(child.isDirectory && child.canonicalFile.parentFile == parent.canonicalFile) {
                "compatibility guest admin directory escaped the guest home"
            }
            parent = child
        }

        val script = readBundledScript()
        require(script.size in 1..MAX_SCRIPT_BYTES && script.startsWith(SCRIPT_MARKER)) {
            "compatibility guest admin asset is invalid"
        }
        val destination = File(parent, SCRIPT_NAME)
        require(!Files.isSymbolicLink(destination.toPath())) {
            "compatibility guest admin executable must not be a symlink"
        }
        if (destination.exists()) {
            require(destination.isFile) {
                "compatibility guest admin executable is not a regular file"
            }
            val current = destination.readBytes()
            if (current.contentEquals(script)) {
                ensureExecutable(destination)
                ensureAndroidCommandShim(parent)
                ensureAndroidPackageManagerShim(parent)
                ensureAndroidSettingsShim(parent)
                ensureAndroidAppOpsShim(parent)
                ensureAndroidWindowManagerShim(parent)
                ensureAndroidDeviceConfigShim(parent)
                ensureAndroidDevicePolicyShim(parent)
                ensureAndroidImeShim(parent)
                ensureAndroidInputShim(parent)
                ensureAndroidLockSettingsShim(parent)
                ensureAndroidHostCommandShims(parent)
                return destination
            }
            require(isKnownScript(current)) {
                "compatibility guest admin executable has unexpected content"
            }
        }

        val temporary = File.createTempFile(".codex-guest-admin-", ".pending", parent)
        try {
            temporary.outputStream().use { it.write(script) }
            ensureExecutable(temporary)
            try {
                Files.move(
                    temporary.toPath(),
                    destination.toPath(),
                    StandardCopyOption.ATOMIC_MOVE,
                    StandardCopyOption.REPLACE_EXISTING,
                )
            } catch (_: Exception) {
                Files.move(
                    temporary.toPath(),
                    destination.toPath(),
                    StandardCopyOption.REPLACE_EXISTING,
                )
            }
        } finally {
            if (temporary.exists()) temporary.delete()
        }
        require(
            !Files.isSymbolicLink(destination.toPath()) &&
                destination.isFile && destination.canExecute(),
        ) { "compatibility guest admin executable was not installed" }
        ensureAndroidCommandShim(parent)
        ensureAndroidPackageManagerShim(parent)
        ensureAndroidSettingsShim(parent)
        ensureAndroidAppOpsShim(parent)
        ensureAndroidWindowManagerShim(parent)
        ensureAndroidDeviceConfigShim(parent)
        ensureAndroidDevicePolicyShim(parent)
        ensureAndroidImeShim(parent)
        ensureAndroidInputShim(parent)
        ensureAndroidLockSettingsShim(parent)
        ensureAndroidHostCommandShims(parent)
        return destination
    }

    /**
     * Android's `/system/bin/pm` is a shell wrapper around `cmd`.  The
     * app-server may create a command environment whose PATH is rebuilt by
     * the guest shell, so keep a guest-side absolute fallback ahead of the
     * host directories.  It still executes the real Android binary; it is
     * not a privileged broker or a fake implementation.
     */
    private fun ensureAndroidCommandShim(directory: File) {
        ensureFixedShim(
            directory = directory,
            name = ANDROID_COMMAND_NAME,
            script = ANDROID_COMMAND_SHIM.toByteArray(),
            description = "Android command shim",
        )
    }

    /** Maps Android's pm wrapper to the real cmd package service. */
    private fun ensureAndroidPackageManagerShim(directory: File) {
        ensureFixedShim(
            directory = directory,
            name = ANDROID_PACKAGE_MANAGER_NAME,
            script = ANDROID_PACKAGE_MANAGER_SHIM.toByteArray(),
            description = "Android package-manager shim",
        )
    }

    /** Maps Android's settings wrapper to the real cmd settings service. */
    private fun ensureAndroidSettingsShim(directory: File) {
        ensureFixedShim(
            directory = directory,
            name = ANDROID_SETTINGS_NAME,
            script = ANDROID_SETTINGS_SHIM.toByteArray(),
            description = "Android settings shim",
        )
    }

    /** Maps Android's appops wrapper to the real cmd appops service. */
    private fun ensureAndroidAppOpsShim(directory: File) {
        ensureFixedShim(
            directory = directory,
            name = ANDROID_APPOPS_NAME,
            script = ANDROID_APPOPS_SHIM.toByteArray(),
            description = "Android appops shim",
        )
    }

    /** Maps Android's wm wrapper to the real cmd window service. */
    private fun ensureAndroidWindowManagerShim(directory: File) {
        ensureFixedShim(
            directory = directory,
            name = ANDROID_WINDOW_MANAGER_NAME,
            script = ANDROID_WINDOW_MANAGER_SHIM.toByteArray(),
            description = "Android window-manager shim",
        )
    }

    /** Maps Android's device_config wrapper to the cmd service. */
    private fun ensureAndroidDeviceConfigShim(directory: File) {
        ensureFixedShim(
            directory = directory,
            name = ANDROID_DEVICE_CONFIG_NAME,
            script = ANDROID_DEVICE_CONFIG_SHIM.toByteArray(),
            description = "Android device-config shim",
        )
    }

    /** Maps Android's dpm wrapper to the device_policy cmd service. */
    private fun ensureAndroidDevicePolicyShim(directory: File) {
        ensureFixedShim(
            directory = directory,
            name = ANDROID_DEVICE_POLICY_NAME,
            script = ANDROID_DEVICE_POLICY_SHIM.toByteArray(),
            description = "Android device-policy shim",
        )
    }

    /** Maps Android's ime wrapper to the input_method cmd service. */
    private fun ensureAndroidImeShim(directory: File) {
        ensureFixedShim(
            directory = directory,
            name = ANDROID_IME_NAME,
            script = ANDROID_IME_SHIM.toByteArray(),
            description = "Android IME shim",
        )
    }

    /** Maps Android's input wrapper to the input cmd service. */
    private fun ensureAndroidInputShim(directory: File) {
        ensureFixedShim(
            directory = directory,
            name = ANDROID_INPUT_NAME,
            script = ANDROID_INPUT_SHIM.toByteArray(),
            description = "Android input shim",
        )
    }

    /** Maps Android's locksettings wrapper to the lock_settings cmd service. */
    private fun ensureAndroidLockSettingsShim(directory: File) {
        ensureFixedShim(
            directory = directory,
            name = ANDROID_LOCK_SETTINGS_NAME,
            script = ANDROID_LOCK_SETTINGS_SHIM.toByteArray(),
            description = "Android locksettings shim",
        )
    }

    /** Exposes fixed Android diagnostics under the Debian guest PATH. */
    private fun ensureAndroidHostCommandShims(directory: File) {
        ANDROID_HOST_COMMAND_NAMES.forEach { name ->
            ensureFixedShim(
                directory = directory,
                name = name,
                script = androidHostCommandScript(name).toByteArray(),
                description = "Android $name shim",
            )
        }
    }

    private fun ensureFixedShim(
        directory: File,
        name: String,
        script: ByteArray,
        description: String,
    ) {
        val destination = File(directory, name)
        require(!Files.isSymbolicLink(destination.toPath())) {
            "$description must not be a symlink"
        }
        if (destination.exists()) {
            require(destination.isFile) { "$description is not a regular file" }
            val current = destination.readBytes()
            require(current.contentEquals(script)) {
                "$description has unexpected content"
            }
            ensureExecutable(destination)
            return
        }
        val temporary = File.createTempFile(".codex-android-$name-", ".pending", directory)
        try {
            temporary.outputStream().use { it.write(script) }
            ensureExecutable(temporary)
            try {
                Files.move(
                    temporary.toPath(),
                    destination.toPath(),
                    StandardCopyOption.ATOMIC_MOVE,
                )
            } catch (_: Exception) {
                Files.move(temporary.toPath(), destination.toPath())
            }
        } finally {
            if (temporary.exists()) temporary.delete()
        }
        require(
            !Files.isSymbolicLink(destination.toPath()) &&
                destination.isFile && destination.canExecute(),
        ) { "$description was not installed" }
    }

    private fun ensureExecutable(file: File) {
        require(file.setExecutable(true, false) || file.canExecute()) {
            "compatibility guest admin executable mode is unavailable"
        }
    }

    private fun isKnownScript(bytes: ByteArray): Boolean =
        KNOWN_SCRIPT_MARKERS.any { bytes.startsWith(it) }

    private fun ByteArray.startsWith(prefix: ByteArray): Boolean =
        size >= prefix.size && prefix.indices.all { this[it] == prefix[it] }

    companion object {
        const val ASSET_PATH = "codex-guest-admin/sudo"
        const val SCRIPT_NAME = "sudo"
        const val ANDROID_COMMAND_NAME = "cmd"
        const val ANDROID_PACKAGE_MANAGER_NAME = "pm"
        const val ANDROID_SETTINGS_NAME = "settings"
        const val ANDROID_APPOPS_NAME = "appops"
        const val ANDROID_WINDOW_MANAGER_NAME = "wm"
        const val ANDROID_DEVICE_CONFIG_NAME = "device_config"
        const val ANDROID_DEVICE_POLICY_NAME = "dpm"
        const val ANDROID_IME_NAME = "ime"
        const val ANDROID_INPUT_NAME = "input"
        const val ANDROID_LOCK_SETTINGS_NAME = "locksettings"
        val ANDROID_HOST_COMMAND_NAMES = listOf(
            "am",
            "content",
            "dumpsys",
            "getprop",
            "logcat",
            "svc",
        )
        const val MAX_SCRIPT_BYTES = 32 * 1024
        private val ANDROID_COMMAND_SHIM =
            "#!/bin/sh\n# codex-android-command-shim-version=1\nexec /system/bin/cmd \"\$@\"\n"
        private val ANDROID_PACKAGE_MANAGER_SHIM =
            "#!/bin/sh\n# codex-android-package-manager-shim-version=1\n" +
                "exec /system/bin/cmd package \"\$@\"\n"
        private val ANDROID_SETTINGS_SHIM =
            "#!/bin/sh\n# codex-android-settings-shim-version=1\n" +
                "exec /system/bin/cmd settings \"\$@\"\n"
        private val ANDROID_APPOPS_SHIM =
            "#!/bin/sh\n# codex-android-appops-shim-version=1\n" +
                "exec /system/bin/cmd appops \"\$@\"\n"
        private val ANDROID_WINDOW_MANAGER_SHIM =
            "#!/bin/sh\n# codex-android-window-manager-shim-version=1\n" +
                "exec /system/bin/cmd window \"\$@\"\n"
        private val ANDROID_DEVICE_CONFIG_SHIM =
            "#!/bin/sh\n# codex-android-device-config-shim-version=1\n" +
                "exec /system/bin/cmd device_config \"\$@\"\n"
        private val ANDROID_DEVICE_POLICY_SHIM =
            "#!/bin/sh\n# codex-android-device-policy-shim-version=1\n" +
                "exec /system/bin/cmd device_policy \"\$@\"\n"
        private val ANDROID_IME_SHIM =
            "#!/bin/sh\n# codex-android-ime-shim-version=1\n" +
                "exec /system/bin/cmd input_method ime \"\$@\"\n"
        private val ANDROID_INPUT_SHIM =
            "#!/bin/sh\n# codex-android-input-shim-version=1\n" +
                "exec /system/bin/cmd input \"\$@\"\n"
        private val ANDROID_LOCK_SETTINGS_SHIM =
            "#!/bin/sh\n# codex-android-locksettings-shim-version=1\n" +
                "exec /system/bin/cmd lock_settings \"\$@\"\n"

        private fun androidHostCommandScript(name: String): String {
            require(name in ANDROID_HOST_COMMAND_NAMES) { "unsupported Android host command" }
            return "#!/bin/sh\n# codex-android-host-command-shim-version=1\n" +
                "exec /android/system/bin/$name \"\$@\"\n"
        }
        private val SCRIPT_MARKER =
            "#!/bin/sh\n# codex-guest-admin-version=3\n".toByteArray()
        private val KNOWN_SCRIPT_MARKERS = listOf(
            SCRIPT_MARKER,
            "#!/bin/sh\n# codex-guest-admin-version=2\n".toByteArray(),
            "#!/bin/sh\n# codex-guest-admin-version=1\n".toByteArray(),
        )

        fun readBundledScript(open: () -> InputStream): ByteArray {
            val output = ByteArrayOutputStream()
            val buffer = ByteArray(4096)
            open().use { input ->
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    output.write(buffer, 0, count)
                    require(output.size() <= MAX_SCRIPT_BYTES) {
                        "compatibility guest admin asset is too large"
                    }
                }
            }
            return output.toByteArray()
        }

        fun androidPackageManagerShim(home: File): File {
            return verifiedAndroidShim(home, ANDROID_PACKAGE_MANAGER_NAME, "Android package-manager shim")
        }

        fun androidCommandShim(home: File): File {
            return verifiedAndroidShim(home, ANDROID_COMMAND_NAME, "Android command shim")
        }

        fun sudoShim(home: File): File {
            return verifiedAndroidShim(home, SCRIPT_NAME, "guest admin adapter")
        }

        fun androidSettingsShim(home: File): File {
            return verifiedAndroidShim(home, ANDROID_SETTINGS_NAME, "Android settings shim")
        }

        fun androidAppOpsShim(home: File): File {
            return verifiedAndroidShim(home, ANDROID_APPOPS_NAME, "Android appops shim")
        }

        fun androidWindowManagerShim(home: File): File {
            return verifiedAndroidShim(home, ANDROID_WINDOW_MANAGER_NAME, "Android window-manager shim")
        }

        fun androidDeviceConfigShim(home: File): File {
            return verifiedAndroidShim(home, ANDROID_DEVICE_CONFIG_NAME, "Android device-config shim")
        }

        fun androidDevicePolicyShim(home: File): File {
            return verifiedAndroidShim(home, ANDROID_DEVICE_POLICY_NAME, "Android device-policy shim")
        }

        fun androidImeShim(home: File): File {
            return verifiedAndroidShim(home, ANDROID_IME_NAME, "Android IME shim")
        }

        fun androidInputShim(home: File): File {
            return verifiedAndroidShim(home, ANDROID_INPUT_NAME, "Android input shim")
        }

        fun androidLockSettingsShim(home: File): File {
            return verifiedAndroidShim(home, ANDROID_LOCK_SETTINGS_NAME, "Android locksettings shim")
        }

        fun androidHostCommandShim(home: File, name: String): File {
            require(name in ANDROID_HOST_COMMAND_NAMES) { "unsupported Android host command" }
            return verifiedAndroidShim(home, name, "Android $name shim")
        }

        private fun verifiedAndroidShim(home: File, name: String, description: String): File {
            val directory = File(home, ".local/codex-admin/bin")
            val target = File(directory, name)
            require(
                directory.isDirectory &&
                    !Files.isSymbolicLink(directory.toPath()) &&
                    target.isFile &&
                    !Files.isSymbolicLink(target.toPath()) &&
                    target.canExecute(),
            ) { "$description is unavailable" }
            return target
        }
    }
}
