package io.henry.codex

import java.io.File
import java.nio.charset.StandardCharsets

/** Builds the normal KernelSU Root -> PRoot launch. */
internal object CompatibilityRootLaunchScript {
    private val allowedSuHelpers = setOf(
        "/data/adb/ksu/bin/su",
        "/system/bin/su",
        "/system/xbin/su",
    )
    private val environmentKey = Regex("[A-Za-z_][A-Za-z0-9_]*")
    private val executionId =
        Regex("[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")
    private val appNoBackupDirectory =
        Regex("/data/(user|user_de)/[0-9]+/io\\.henry\\.codex/no_backup")
    private val markerPath = Regex(
        "/data/(user|user_de)/[0-9]+/io\\.henry\\.codex/no_backup/" +
            "compat-root-processes/compat-process-[0-9a-f-]{36}\\.pid",
    )

    fun build(
        suHelper: String,
        workerGuard: String,
        parentPid: Int,
        appUid: Int,
        rootMarkerPath: String,
        workingDirectory: String,
        argv: List<String>,
        environment: Map<String, String>,
        environmentFile: String,
    ): List<String> {
        require(suHelper in allowedSuHelpers) { "unapproved Root helper" }
        require(workerGuard.startsWith("/") && workerGuard.contains("libcodex_worker_guard.so")) {
            "Root PRoot worker guard is invalid"
        }
        require(parentPid > 1 && appUid > 0) { "Root PRoot supervisor identity is invalid" }
        require(markerPath.matches(rootMarkerPath)) { "Root PRoot marker path is invalid" }
        require(workingDirectory.startsWith("/") && !workingDirectory.contains('\u0000')) {
            "Root PRoot working directory is invalid"
        }
        require(argv.isNotEmpty() && argv.none { it.isEmpty() || it.contains('\u0000') }) {
            "Root PRoot argv is invalid"
        }
        require(argv.any { it.contains("libcodex_proot.so") } && "--kill-on-exit" in argv) {
            "Root supervisor only accepts the fixed PRoot worker"
        }
        require(environment.all { (key, value) ->
            environmentKey.matches(key) &&
                !value.contains('\u0000') && !value.contains('\r') && !value.contains('\n')
        }) { "Root PRoot environment is invalid" }
        validateEnvironmentFilePath(environmentFile)

        // On this Android image, /system/bin/env can start ordinary Bionic
        // executables but cannot directly exec the PRoot ELF: its launcher
        // path treats PRoot's first option as the command and reports
        // `env: exec --link2symlink`. Keep the environment empty at the
        // Android boundary, then let a clean shell exec the fixed argv. The
        // shell is only an argv transport here; no user command is parsed.
        // Keep provider credentials and other per-session values out of the
        // su/worker argv. The file is app-private, read once by the fixed
        // shell, then removed before PRoot/Codex is exec'd. There is no
        // inline-environment fallback: future callers must preserve this
        // property instead of accidentally reintroducing argv leakage.
        val file = shellQuote(environmentFile)
        val script =
            "set -e; set -a; . $file; set +a; /system/bin/rm -f $file; " +
                "exec ${argv.joinToString(" ", transform = ::shellQuote)}"
        val workerArgv = listOf("/system/bin/sh", "-c", script)
        val workerCommand = workerArgv.joinToString(" ", transform = ::shellQuote)
        val processDirectory = shellQuote(rootMarkerPath.substringBeforeLast('/'))
        val marker = shellQuote(rootMarkerPath)
        val markerCommand =
            "export CODEX_COMPAT_PROCESS_MARKER=$marker && umask 077 && " +
                "/system/bin/mkdir -p $processDirectory && " +
                "/system/bin/chmod 700 $processDirectory && set -C && " +
                "printf '%s\\n' \"\$\$\" > $marker"
        val guardedCommand =
            "${rootProfilePreflightCommand()} && $markerCommand && " +
                "cd ${shellQuote(workingDirectory)} && exec $workerCommand"
        val supervisorCommand = listOf(
            "exec",
            workerGuard,
            "--root-codex-supervisor",
            parentPid.toString(),
            appUid.toString(),
            "--",
            "/system/bin/sh",
            "-c",
            guardedCommand,
        ).joinToString(" ", transform = ::shellQuote)
        val suScript = "exec " + rootSuArguments(suHelper, supervisorCommand)
            .joinToString(" ", transform = ::shellQuote)

        return listOf("/system/bin/sh", "-c", suScript)
    }

    /** Launch the probe through the same supervisor/identity guard as Codex. */
    fun rootProfileProbeCommand(workerGuard: String, script: String): String {
        require(workerGuard.startsWith("/") &&
            workerGuard.endsWith("/libcodex_worker_guard.so") &&
            !workerGuard.contains('\u0000') && !workerGuard.contains('\n')) {
            "Root worker guard path is invalid"
        }
        require(script.isNotBlank() && !script.contains('\u0000')) {
            "Root Profile probe script is invalid"
        }
        return listOf(
            "exec",
            workerGuard,
            "--root-codex-profile-probe",
            "--",
            "/system/bin/sh",
            "-c",
            script,
        ).joinToString(" ", transform = ::shellQuote)
    }

    /** Use the profile selected by KernelSU; do not invent a second SELinux domain. */
    fun rootSuArguments(suHelper: String, command: String): List<String> {
        require(suHelper in allowedSuHelpers) { "unapproved Root helper" }
        require(command.isNotEmpty() && !command.contains('\u0000')) {
            "Root command is invalid"
        }
        return listOf(suHelper, "-c", command)
    }

    /**
     * Writes a shell-safe, app-private environment file for a Root launch.
     * The file is intentionally not a general script: every line is one
     * validated environment assignment and values are single-quoted.
     */
    fun writeEnvironmentFile(directory: File, environment: Map<String, String>): File {
        require(directory.isDirectory || directory.mkdirs()) {
            "Root environment directory is unavailable"
        }
        require(!java.nio.file.Files.isSymbolicLink(directory.toPath())) {
            "Root environment directory must not be a symbolic link"
        }
        require(environment.all { (key, value) ->
            environmentKey.matches(key) &&
                !value.contains('\u0000') &&
                !value.contains('\r') &&
                !value.contains('\n')
        }) { "Root environment is invalid" }
        val file = File.createTempFile(".codex-env-", ".sh", directory)
        try {
            file.outputStream().bufferedWriter(StandardCharsets.UTF_8).use { writer ->
                environment.toSortedMap().forEach { (key, value) ->
                    writer.append(key)
                        .append('=')
                        .append(shellQuote(value))
                        .append('\n')
                }
            }
            // App-private directories already have a restrictive parent mode;
            // make the file itself explicit as well.
            file.setReadable(false, false)
            file.setWritable(false, false)
            require(file.setReadable(true, true) && file.setWritable(true, true)) {
                "Root environment file permissions could not be applied"
            }
            return file
        } catch (error: Exception) {
            file.delete()
            throw error
        }
    }

    /**
     * Recheck the actual UID in the process that will launch PRoot. The
     * settings probe is a separate `su` invocation, so a Root Profile change
     * between probe and session start must fail before writing a PID marker or
     * starting Codex. KernelSU owns the SELinux domain and supplementary
     * groups; this launcher must not require a project-specific domain or
     * capability/group mask.
     */
    private fun rootProfilePreflightCommand(): String = """
        root_profile_fail() {
          printf '%s\n' "Android Codex Root Profile recheck failed: ${'$'}1; PRoot was not started." >&2
          exit 126
        }
        root_profile_preflight() {
          uid_values=$(/system/bin/toybox sed -n 's/^Uid:[[:space:]]*//p' /proc/self/status) || root_profile_fail uid
          set -- ${'$'}uid_values
          [ "${'$'}#" -eq 4 ] && [ "${'$'}1" = 0 ] && [ "${'$'}2" = 0 ] && [ "${'$'}3" = 0 ] && [ "${'$'}4" = 0 ] || root_profile_fail uid
        }
        root_profile_preflight
    """.trimIndent()

    fun rootMarkerPath(noBackupFilesDirectory: String, id: String): String {
        require(appNoBackupDirectory.matches(noBackupFilesDirectory)) {
            "Root PRoot marker directory is invalid"
        }
        require(executionId.matches(id)) { "Root PRoot execution id is invalid" }
        return "$noBackupFilesDirectory/compat-root-processes/compat-process-$id.pid"
    }

    fun rootStopCommand(rootMarkerPath: String): String {
        require(markerPath.matches(rootMarkerPath)) { "Root PRoot marker path is invalid" }
        val marker = shellQuote(rootMarkerPath)
        val expectedMarker = shellQuote("CODEX_COMPAT_PROCESS_MARKER=$rootMarkerPath")
        return "if test ! -f $marker; then /system/bin/sleep 1; fi; " +
            "if test -f $marker; then " +
            "pid=\$(/system/bin/cat $marker 2>/dev/null); " +
            "case \"\$pid\" in ''|0|*[!0-9]*) exit 65 ;; esac; " +
            "if /system/bin/toybox tr '\\000' '\\n' < \"/proc/\$pid/environ\" 2>/dev/null | " +
            "/system/bin/toybox grep -F -x $expectedMarker >/dev/null 2>&1; then " +
            "kill -TERM -\"\$pid\" 2>/dev/null || true; " +
            "kill -KILL -\"\$pid\" 2>/dev/null || true; " +
            "/system/bin/rm -f $marker; else exit 66; fi; fi"
    }

    fun rootRemoveMarkerCommand(rootMarkerPath: String): String {
        require(markerPath.matches(rootMarkerPath)) { "Root PRoot marker path is invalid" }
        return "/system/bin/rm -f ${shellQuote(rootMarkerPath)}"
    }

    /** Remove only marker files whose recorded process is no longer alive. */
    fun rootCleanupStaleMarkersCommand(noBackupFilesDirectory: String): String {
        require(appNoBackupDirectory.matches(noBackupFilesDirectory)) {
            "Root PRoot marker directory is invalid"
        }
        val directory = shellQuote("$noBackupFilesDirectory/compat-root-processes")
        return "for marker in $directory/compat-process-*.pid; do " +
            "if test -f \"\$marker\"; then " +
            "pid=\$(/system/bin/cat \"\$marker\" 2>/dev/null); " +
            "case \"\$pid\" in " +
            "''|0|*[!0-9]*) /system/bin/rm -f \"\$marker\" ;; " +
            "*) if /system/bin/toybox tr '\\000' '\\n' < \"/proc/\$pid/environ\" " +
            "2>/dev/null | /system/bin/toybox grep -F -x " +
            "\"CODEX_COMPAT_PROCESS_MARKER=\${marker}\" >/dev/null 2>&1; then :; " +
            "else /system/bin/rm -f \"\$marker\"; fi ;; " +
            "esac; fi; done"
    }

    fun androidHostBindArguments(existingDirectories: Set<String>): List<String> =
        androidHostBindDirectories
            .filter(existingDirectories::contains)
            .map { path -> "--bind=$path:$path!" }

    private fun shellQuote(value: String): String =
        "'${value.replace("'", "'\\''")}'"

    private fun validateEnvironmentFilePath(path: String) {
        require(path.startsWith("/data/") &&
            !path.contains('\u0000') &&
            !path.contains('\n') &&
            path.split('/').none { it == "." || it == ".." }) {
            "Root environment file path is invalid"
        }
    }

    val androidHostBindDirectories = listOf(
        "/data",
        "/system",
        "/system_ext",
        "/vendor",
        "/product",
        "/odm",
        "/apex",
        // Android host executables resolve their namespace configuration
        // through this absolute path. Without the bind, framework commands
        // invoked through the Root host view can fail on some Android builds.
        "/linkerconfig",
        "/metadata",
        "/mnt",
        "/storage",
        "/sys",
        "/dev",
    )
}
