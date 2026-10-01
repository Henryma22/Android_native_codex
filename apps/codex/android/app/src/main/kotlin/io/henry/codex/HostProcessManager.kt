package io.henry.codex

import android.util.Log
import io.flutter.plugin.common.EventChannel
import java.io.File
import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit
import android.os.Handler
import android.os.Looper
import kotlin.concurrent.thread

private const val HOST_COMMAND_HOME_DIRECTORY = "host-command-home"

internal fun completeHostCommandEnvironment(
    environment: Map<String, String>,
    hostCommandHome: File?,
): Map<String, String> {
    val baseHome = hostCommandHome?.canonicalFile ?: return environment
    require(!Files.isSymbolicLink(baseHome.toPath())) {
        "Host command home must not be a symbolic link"
    }
    require(baseHome.mkdirs() || baseHome.isDirectory) {
        "Host command home is unavailable"
    }
    val commandHome = File(baseHome, HOST_COMMAND_HOME_DIRECTORY)
    require(!Files.isSymbolicLink(commandHome.toPath())) {
        "Host command home must not be a symbolic link"
    }
    require(commandHome.mkdirs() || commandHome.isDirectory) {
        "Host command home is unavailable"
    }
    val commandTmp = File(commandHome, "tmp")
    require(!Files.isSymbolicLink(commandTmp.toPath())) {
        "Host command temp directory must not be a symbolic link"
    }
    require(commandTmp.mkdirs() || commandTmp.isDirectory) {
        "Host command temp directory is unavailable"
    }

    return environment.toMutableMap().apply {
        putIfAbsent("HOME", commandHome.absolutePath)
        putIfAbsent("TMPDIR", commandTmp.absolutePath)
        putIfAbsent("TMP", commandTmp.absolutePath)
        putIfAbsent("TEMP", commandTmp.absolutePath)
    }
}

/**
 * Owns explicit argv processes for the Local Android backend.
 *
 * This is deliberately not a shell API: callers provide an argv list and a
 * working directory under the fixed host workspace root. Root execution is a
 * separate identity and still goes through the fixed su helper candidates.
 */
internal class HostProcessManager(
    private val workspaceRoot: String,
    private val rootHelpers: List<String>,
    private val hostCommandHome: File? = null,
    private val networkEnvironment: () -> Map<String, String> = { emptyMap() },
    private val rootProfileProbe: () -> Map<String, Any?> = { emptyMap() },
) : EventChannel.StreamHandler {
    private val entries = ConcurrentHashMap<String, Entry>()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val orphanCleanupLock = Any()
    private val rootProfileLock = Any()

    @Volatile
    private var orphanCleanupComplete = false

    @Volatile
    private var eventSink: EventChannel.EventSink? = null

    @Volatile
    private var verifiedRootProfileHelper: String? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        entries.values.forEach { entry -> flushPending(entry) }
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    /**
     * Reclaims a root process left behind by an app-process death.
     *
     * The Android service normally owns teardown, but a force-stop, crash, or
     * low-memory kill is not required to deliver Service.onDestroy(). Only
     * markers in this app's fixed root-owned directory are considered, and a
     * PID is signalled only when its inherited marker environment variable
     * still matches the exact marker path. A reused PID therefore cannot turn
     * an old marker into a signal for an unrelated process.
     */
    fun cleanupOrphanedRootProcesses(helper: String) {
        val directory = shellQuote(ROOT_PROCESS_DIRECTORY)
        val command =
            "if test -d $directory; then " +
                // The process directory itself is traverse-only for the app
                // UID so root process markers remain private.
                "/system/bin/chmod 711 $directory 2>/dev/null || true; " +
                "for marker in $directory/host-process-*.pid; do " +
                "test -f \"\$marker\" || continue; " +
                "pid=\$(/system/bin/cat \"\$marker\" 2>/dev/null); " +
                "case \"\$pid\" in ''|*[!0-9]*) /system/bin/rm -f \"\$marker\" ;; *) " +
                "if test \"\$pid\" -gt 0 2>/dev/null && " +
                "test -d \"/proc/\$pid\" && " +
                "/system/bin/cat \"/proc/\$pid/environ\" 2>/dev/null | " +
                "/system/bin/toybox tr '\\000' '\\n' | " +
                "/system/bin/toybox grep -F -x \"CODEX_HOST_PROCESS_MARKER=\$marker\" " +
                ">/dev/null 2>&1; then " +
                "kill -TERM -\"\$pid\" 2>/dev/null || kill -TERM \"\$pid\" 2>/dev/null || true; " +
                "kill -KILL -\"\$pid\" 2>/dev/null || kill -KILL \"\$pid\" 2>/dev/null || true; " +
                "fi; /system/bin/rm -f \"\$marker\" ;; esac; " +
                "done; fi"
        try {
            val cleanup = ProcessBuilder(helper, "-c", command)
                .redirectErrorStream(true)
                .start()
            if (!cleanup.waitFor(ROOT_KILL_TIMEOUT_MS, TimeUnit.MILLISECONDS)) {
                cleanup.destroyForcibly()
            }
        } catch (_: Exception) {
            // A later explicitly approved Root session can retry cleanup.
        }
    }

    fun start(
        argv: List<String>,
        cwd: String,
        identity: String,
        timeoutMs: Long,
        environment: Map<String, String>,
    ): String {
        validateArgv(argv)
        // Android's active HTTP proxy is not automatically inherited by a
        // ProcessBuilder child or by a root helper launched through su. Add
        // only the validated platform proxy, then let the explicit caller
        // environment override it for a deliberate per-command choice.
        val effectiveEnvironment = buildMap {
            putAll(runCatching { networkEnvironment() }.getOrDefault(emptyMap()))
            putAll(environment)
        }
        val childEnvironment = withCommandEnvironmentDefaults(effectiveEnvironment)
        validateEnvironment(childEnvironment)
        require(identity == "app" || identity == "root") { "unsupported execution identity" }
        val validatedCwd = validateCwd(cwd, identity)
        require(timeoutMs in 1..MAX_TIMEOUT_MS) { "invalid execution timeout" }
        val rootHelper = if (identity == "root") {
            rootHelperForLaunch().also { helper ->
                synchronized(orphanCleanupLock) {
                    if (!orphanCleanupComplete) {
                        cleanupOrphanedRootProcesses(helper)
                        orphanCleanupComplete = true
                    }
                }
            }
        } else {
            null
        }
        val id = UUID.randomUUID().toString()
        val rootMarkerPath = if (identity == "root") rootMarkerPath(id) else null
        val started = startProcess(
            argv,
            validatedCwd,
            identity,
            childEnvironment,
            rootMarkerPath,
            rootHelper,
        )
        val process = started.process
        val entry = Entry(
            id,
            process,
            identity,
            rootMarkerPath,
            rootHelper,
            rootEnvironmentFile = started.environmentFile,
        )
        entries[id] = entry
        Log.i(
            LOG_TAG,
            "start id=$id pid=${processPid(process) ?: -1} identity=$identity " +
                "cwd=$validatedCwd " +
                "entries=${entries.size}",
        )
        stream(entry, "stdout", process.inputStream)
        stream(entry, "stderr", process.errorStream)
        thread(name = "codex-host-wait-$id") {
            val completed = process.waitFor(timeoutMs, TimeUnit.MILLISECONDS)
            val exitCode = if (completed) {
                process.exitValue()
            } else {
                if (entry.identity == "root") terminateRootProcess(entry)
                process.destroy()
                if (!process.waitFor(1, TimeUnit.SECONDS)) {
                    process.destroyForcibly()
                }
                emit(entry, event("stderr", "process timed out\n"))
                -1
            }
            if (entry.identity == "root") {
                removeRootMarker(entry.rootMarkerPath, entry.rootHelper)
            }
            entry.rootEnvironmentFile?.delete()
            Log.i(
                LOG_TAG,
                "exit id=${entry.id} pid=${processPid(entry.process) ?: -1} " +
                    "code=$exitCode entries=${entries.size}",
            )
            finish(entry, exitCode)
        }
        return id
    }

    /**
     * Reuse the first successful Root profile probe for this manager lifetime.
     * Starting another Codex process still invokes the user's normal KernelSU
     * helper, but it does not perform a second full identity/path probe that
     * can be mistaken for a new per-command approval.
     */
    private fun rootHelperForLaunch(): String {
        verifiedRootProfileHelper?.let { return it }
        synchronized(rootProfileLock) {
            verifiedRootProfileHelper?.let { return it }
            val helper = RootProfileLaunchGate.requireSafeHelper(rootProfileProbe())
            verifiedRootProfileHelper = helper
            return helper
        }
    }

    fun attach(id: String) {
        val entry = entries[id] ?: return
        synchronized(entry) {
            entry.attached = true
            flushPending(entry)
            if (entry.completed) entries.remove(id)
        }
    }

    fun write(id: String, value: String) {
        val entry = entries[id] ?: error("host process is not running")
        entry.process.outputStream.write(value.toByteArray(StandardCharsets.UTF_8))
        entry.process.outputStream.flush()
    }

    fun closeStdin(id: String) {
        val entry = entries[id] ?: error("host process is not running")
        entry.process.outputStream.close()
    }

    fun stop(id: String) {
        val entry = entries[id] ?: return
        val shouldStop = synchronized(entry) {
            if (entry.terminalEventEmitted) {
                if (entry.attached) entries.remove(id)
                false
            } else {
                entry.terminalEventEmitted = true
                entry.completed = true
                entries.remove(id)
                true
            }
        }
        if (!shouldStop) return
        if (entry.identity == "root") terminateRootProcess(entry)
        Log.i(
            LOG_TAG,
            "stop id=$id pid=${processPid(entry.process) ?: -1} " +
                "identity=${entry.identity} entries=${entries.size}",
        )
        entry.process.destroy()
        if (entry.process.isAlive) entry.process.destroyForcibly()
        entry.rootEnvironmentFile?.delete()
        emit(entry, event("exit", exitCode = -1))
    }

    fun stopAll() {
        entries.keys.toList().forEach(::stop)
    }

    private fun startProcess(
        argv: List<String>,
        cwd: String,
        identity: String,
        environment: Map<String, String>,
        rootMarkerPath: String?,
        rootHelper: String?,
    ): StartedProcess {
        if (identity == "app") {
            val appEnvironment = environment.toMutableMap()
            return StartedProcess(
                process = ProcessBuilder(argv)
                .directory(File(cwd))
                .redirectErrorStream(false)
                .apply { environment().putAll(appEnvironment) }
                .start(),
                environmentFile = null,
            )
        }

        val helper = rootHelper
            ?: error("Android Root worker has no verified KernelSU helper")
        val environmentFile = hostCommandHome?.parentFile?.let {
            CompatibilityRootLaunchScript.writeEnvironmentFile(it, environment)
        }
        val environmentSetup = environmentFile?.let { file ->
            val quotedFile = shellQuote(file.absolutePath)
            "set -e; set -a; . $quotedFile; set +a; /system/bin/rm -f $quotedFile; "
        } ?: environment.entries.joinToString("; ") { (key, value) ->
            "export $key=${shellQuote(value)}"
        }.let { value -> if (value.isEmpty()) "" else "$value; " }
        val quotedRoot = shellQuote(workspaceRoot)
        val quotedCwd = shellQuote(cwd)
        val quotedArgv = argv.joinToString(" ", transform = ::shellQuote)
        val quotedMarker = shellQuote(rootMarkerPath ?: error("root marker is required"))
        val isolatedCommand =
            environmentSetup +
                "export CODEX_HOST_PROCESS_MARKER=$quotedMarker; " +
                "echo \$\$ > $quotedMarker; exec $quotedArgv"
        val command =
            "base=$quotedRoot; target=$quotedCwd; " +
                "resolved=\$(readlink -f \"\$target\") || exit 20; " +
                "case \"\$resolved\" in \"\$base\"|\"\$base\"/*) ;; *) exit 21 ;; esac; " +
                "test \"\$resolved\" = \"\$target\" || exit 22; " +
                "test -d \"\$target\" || exit 23; " +
                "cd \"\$target\" || exit 24; umask 077; " +
                "/system/bin/mkdir -p /data/local/tmp/io.henry.codex; " +
                // Keep the parent private from directory listing/read while
                // allowing the app to traverse to its own process markers.
                "/system/bin/chmod 711 /data/local/tmp/io.henry.codex 2>/dev/null || exit 25; " +
                "if test -x /system/bin/setsid; then " +
                "exec /system/bin/setsid /system/bin/sh -c ${shellQuote(isolatedCommand)}; " +
                "else /system/bin/sh -c ${shellQuote(isolatedCommand)}; fi"
        return try {
            StartedProcess(
                process = ProcessBuilder(helper, "-c", command)
                .redirectErrorStream(false)
                .start(),
                environmentFile = environmentFile,
            )
        } catch (error: Exception) {
            environmentFile?.delete()
            throw error
        }
    }

    /**
     * Android shell launches do not promise a writable HOME. Explicit host
     * commands may omit it, so give that path a stable app-private home and
     * temp directory without changing caller-supplied values.
     */
    private fun withCommandEnvironmentDefaults(
        environment: Map<String, String>,
    ): Map<String, String> = completeHostCommandEnvironment(environment, hostCommandHome)

    /**
     * App UIDs cannot reliably signal a root process created through su.
     * Root commands are placed in a private session when toybox supports
     * setsid, then the helper kills that process group (and falls back to the
     * exact PID for older devices).
     */
    private fun terminateRootProcess(entry: Entry) {
        val marker = entry.rootMarkerPath
        val pid = processPid(entry.process)
        if (!entry.process.isAlive && marker == null) return
        val fallback = pid?.takeIf { it > 0 }?.let {
            "kill -TERM -$it 2>/dev/null || kill -TERM $it 2>/dev/null || true; " +
                "kill -KILL -$it 2>/dev/null || kill -KILL $it 2>/dev/null || true"
        } ?: "true"
        val markerCommand = marker?.let { quotedMarker ->
            val markerPath = shellQuote(quotedMarker)
            "if test -f $markerPath; then " +
                "pid=\$(/system/bin/cat $markerPath); " +
                "case \"\$pid\" in ''|*[!0-9]*) $fallback ;; *) " +
                "kill -TERM -\"\$pid\" 2>/dev/null || kill -TERM \"\$pid\" 2>/dev/null || true; " +
                "kill -KILL -\"\$pid\" 2>/dev/null || kill -KILL \"\$pid\" 2>/dev/null || true; " +
                ";; esac; /system/bin/rm -f $markerPath; " +
                "else $fallback; fi"
        }
        val command = markerCommand ?: fallback
        for (helper in listOfNotNull(entry.rootHelper) + rootHelpers) {
            try {
                val killer = ProcessBuilder(helper, "-c", command)
                    .redirectErrorStream(true)
                    .start()
                if (!killer.waitFor(ROOT_KILL_TIMEOUT_MS, TimeUnit.MILLISECONDS)) {
                    killer.destroyForcibly()
                } else if (killer.exitValue() == 0) {
                    return
                }
            } catch (_: Exception) {
                // Try the next fixed helper candidate. The normal destroy
                // path below still handles an App UID-owned process.
            }
        }
    }

    private fun removeRootMarker(markerPath: String?, helper: String?) {
        if (markerPath == null || helper == null) return
        val command = "/system/bin/rm -f ${shellQuote(markerPath)}"
        try {
            val cleaner = ProcessBuilder(helper, "-c", command)
                .redirectErrorStream(true)
                .start()
            if (!cleaner.waitFor(ROOT_KILL_TIMEOUT_MS, TimeUnit.MILLISECONDS)) {
                cleaner.destroyForcibly()
            }
        } catch (_: Exception) {
            // Best-effort cleanup; a stale marker is harmless without an
            // active process and will be checked before the next Root session.
        }
    }

    private fun rootMarkerPath(id: String): String =
        "/data/local/tmp/io.henry.codex/host-process-$id.pid"

    private fun processPid(process: Process): Long? = try {
        Process::class.java.getMethod("pid").invoke(process) as? Long
    } catch (_: Exception) {
        null
    }

    private fun validateArgv(argv: List<String>) {
        require(argv.isNotEmpty()) { "argv must not be empty" }
        argv.forEach { argument ->
            require(!argument.contains('\u0000')) { "argv contains a NUL character" }
        }
    }

    private fun validateEnvironment(environment: Map<String, String>) {
        environment.forEach { (key, value) ->
            require(ENVIRONMENT_KEY.matches(key)) { "invalid environment key" }
            require(!value.contains('\u0000')) { "environment contains a NUL character" }
        }
    }

    private fun validateCwd(cwd: String, identity: String): String {
        require(cwd.isNotEmpty() && cwd.startsWith('/')) {
            "working directory must be an absolute path"
        }
        require(!cwd.contains('\u0000')) { "working directory contains a NUL character" }
        require(cwd.removePrefix("/").split('/').none {
            it == "." || it == ".." || it.isEmpty()
        }) {
            "working directory must be normalized"
        }
        require(cwd == workspaceRoot || cwd.startsWith("$workspaceRoot/")) {
            "working directory is outside the host workspace root"
        }
        if (identity == "app") {
            val file = File(cwd)
            val canonical = file.canonicalPath
            val canonicalRoot = File(workspaceRoot).canonicalPath
            require(canonical == workspaceRoot || canonical.startsWith("$canonicalRoot/")) {
                "working directory escaped the host workspace root"
            }
            require(canonical == cwd) {
                "symbolic-link working directories are not supported"
            }
            require(file.isDirectory) { "working directory does not exist" }
        }
        return cwd
    }

    private fun stream(entry: Entry, type: String, input: java.io.InputStream) {
        thread(name = "codex-host-$type-${entry.id}") {
            val buffer = ByteArray(8 * 1024)
            val decoder = Utf8StreamDecoder()
            try {
                input.use { stream ->
                    while (true) {
                        val count = stream.read(buffer)
                        if (count <= 0) break
                        val value = decoder.decode(buffer, 0, count)
                        if (value.isNotEmpty()) emit(entry, event(type, value))
                    }
                }
                val tail = decoder.finish()
                if (tail.isNotEmpty()) emit(entry, event(type, tail))
            } catch (error: Exception) {
                emit(entry, event("error", error.message ?: "process stream failed"))
            }
        }
    }

    /** Emits exactly one terminal event, even when Stop races waitFor(). */
    private fun finish(entry: Entry, exitCode: Int) {
        val shouldEmit = synchronized(entry) {
            if (entry.terminalEventEmitted) {
                if (entry.attached) entries.remove(entry.id)
                false
            } else {
                entry.terminalEventEmitted = true
                entry.completed = true
                if (entry.attached) entries.remove(entry.id)
                true
            }
        }
        if (shouldEmit) emit(entry, event("exit", exitCode = exitCode))
    }

    private fun emit(entry: Entry, value: Map<String, Any?>) {
        val payload = value.toMutableMap().apply { put("processId", entry.id) }
        synchronized(entry) {
            if (!entry.attached || eventSink == null) {
                if (entry.pending.size < MAX_PENDING_EVENTS) entry.pending.add(payload)
                return
            }
        }
        // EventChannel.EventSink ultimately dispatches through FlutterJNI,
        // which must only be called on the Android main thread. Process
        // stdout/stderr and waitFor callbacks intentionally run on workers.
        mainHandler.post {
            synchronized(entry) {
                val sink = eventSink
                if (!entry.attached || sink == null) {
                    if (entry.pending.size < MAX_PENDING_EVENTS) {
                        entry.pending.add(payload)
                    }
                    return@synchronized
                }
                sink.success(payload)
            }
        }
    }

    private fun flushPending(entry: Entry) {
        synchronized(entry) {
            val sink = eventSink ?: return
            if (!entry.attached) return
            entry.pending.forEach { pending -> sink.success(pending) }
            entry.pending.clear()
        }
    }

    private fun event(
        type: String,
        value: String? = null,
        exitCode: Int? = null,
    ): Map<String, Any?> = buildMap {
        put("type", type)
        if (value != null) put("value", value)
        if (exitCode != null) put("exitCode", exitCode)
    }

    private fun shellQuote(value: String): String =
        "'" + value.replace("'", "'\\''") + "'"

    private data class Entry(
        val id: String,
        val process: Process,
        val identity: String,
        val rootMarkerPath: String?,
        val rootHelper: String?,
        val rootEnvironmentFile: File?,
        val pending: MutableList<Map<String, Any?>> = mutableListOf(),
        var attached: Boolean = false,
        var completed: Boolean = false,
        var terminalEventEmitted: Boolean = false,
    )

    private data class StartedProcess(
        val process: Process,
        val environmentFile: File?,
    )

    private companion object {
        const val LOG_TAG = "CodexHostProcess"
        const val ROOT_PROCESS_DIRECTORY = "/data/local/tmp/io.henry.codex"
        val ENVIRONMENT_KEY = Regex("[A-Za-z_][A-Za-z0-9_]*")
        const val MAX_PENDING_EVENTS = 2_048
        const val MAX_TIMEOUT_MS = 24L * 60L * 60L * 1_000L
        const val ROOT_KILL_TIMEOUT_MS = 1_000L
    }
}
