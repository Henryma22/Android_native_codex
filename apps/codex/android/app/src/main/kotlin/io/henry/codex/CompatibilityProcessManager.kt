package io.henry.codex

import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Process as AndroidProcess
import android.util.Log
import io.flutter.plugin.common.EventChannel
import java.io.File
import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.util.UUID
import java.util.concurrent.locks.ReentrantReadWriteLock
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread
import org.json.JSONObject

private const val PROOT_VERSION_LABEL = "PRoot 5.1.107.94"

internal fun compatibilityGuestCommandArgv(
    executable: String,
    resolvedPath: String,
    arguments: List<String>,
    fromGuestPackage: Boolean = resolvedPath.startsWith(
        "${CompatibilityProcessManager.GUEST_PACKAGE_PREFIX}/",
    ),
): List<String> {
    val command = if (fromGuestPackage) {
        listOf(
            "/usr/bin/env",
            "LD_LIBRARY_PATH=${CompatibilityProcessManager.GUEST_PACKAGE_LIBRARY_PATH}",
            resolvedPath,
        )
    } else {
        listOf(resolvedPath)
    }
    return command + arguments
}

internal fun compatibilityGuestPathDirectories(): List<String> =
    CompatibilityProcessManager.GUEST_PATH_DIRECTORIES

internal fun compatibilityGuestPath(identity: String): List<String> {
    require(identity == "app" || identity == "root") { "unknown Android execution identity" }
    return buildList {
        addAll(compatibilityGuestPathDirectories())
        if (identity == "root") {
            // Root workers can execute Android host scripts such as pm and
            // settings. Keep Debian tools first, but make the Android command
            // directory available for their shebang wrappers and cmd lookup.
            addAll(
                listOf(
                    "/system/bin",
                    "/system/xbin",
                    "/vendor/bin",
                    // A shell launched by an Android host wrapper can reset
                    // PATH to the host-visible tree. Keep those absolute
                    // paths available too; they are behind the Root-only
                    // `/android` bind and never enter App-UID sessions.
                    "/android/system/bin",
                    "/android/system/xbin",
                    "/android/vendor/bin",
                ),
            )
        }
    }
}

internal fun compatibilityAndroidHostRootBindArguments(
    identity: String,
    rootfs: File,
): List<String> {
    require(identity == "app" || identity == "root") { "unknown Android execution identity" }
    if (identity != "root") return emptyList()

    require(rootfs.isDirectory && !Files.isSymbolicLink(rootfs.toPath())) {
        "Android host-root mapping requires the verified guest rootfs directory"
    }
    val canonicalRootfs = rootfs.canonicalFile
    val guestMountpoint = File(rootfs, "android")
    require(!Files.isSymbolicLink(guestMountpoint.toPath())) {
        "Android host-root guest mountpoint must not be a symbolic link"
    }
    require(guestMountpoint.mkdirs() || guestMountpoint.isDirectory) {
        "Android host-root guest mountpoint could not be created"
    }
    require(guestMountpoint.isDirectory &&
        !Files.isSymbolicLink(guestMountpoint.toPath()) &&
        guestMountpoint.canonicalFile.parentFile == canonicalRootfs
    ) { "Android host-root guest mountpoint is invalid" }

    return listOf("--bind=/:/android!")
}

internal fun compatibilityGuestExecutableCandidate(
    rootfs: File,
    guestHome: File,
    directory: String,
    executable: String,
): File = when {
    directory.startsWith("/home/codex/") ->
        File(guestHome, "${directory.removePrefix("/home/codex/")}/$executable")
    else -> File(rootfs, "$directory/$executable".removePrefix("/"))
}

/**
 * Keep the user-facing `python` command compatible with older guest images
 * that contain Debian's `python3` binary but predate `python-is-python3`.
 * This is only an argv[0] lookup alias; it does not add a host executable or
 * change the guest PATH.
 */
internal fun compatibilityGuestExecutableNames(executable: String): List<String> =
    if (executable == "python") listOf("python", "python3") else listOf(executable)

/**
 * Runs one explicitly-argv process in the optional Linux compatibility guest.
 *
 * App-identity PRoot workers run as the Android app UID and see only the
 * selected workspace. A Root-identity worker is launched through the verified
 * KernelSU profile without a UID drop and receives the Android host root at
 * guest `/android` plus fixed conventional Android path binds. PRoot's
 * --root-id remains a guest identity mapping; the su launch and Android
 * profile provide host privileges.
 * The runtime rootfs and guest home remain app-private inputs prepared by the
 * guarded installer.
 */
internal class CompatibilityProcessManager(
    private val context: Context,
) : EventChannel.StreamHandler {
    private val entries = ConcurrentHashMap<String, Entry>()
    private val rootfsLifecycleLock = ReentrantReadWriteLock()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val rootAssistedLauncher = FixedRootAssistedLauncher(context)
    private val rootProfileLock = Any()
    private val sessionInstructions = AndroidCodexAgentGuide.read(context)
    private val guestAdminInstaller = CompatibilityGuestAdminInstaller {
        CompatibilityGuestAdminInstaller.readBundledScript {
            context.assets.open(CompatibilityGuestAdminInstaller.ASSET_PATH)
        }
    }

    @Volatile
    private var eventSink: EventChannel.EventSink? = null

    @Volatile
    private var verifiedRootProfileHelper: String? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        entries.values.forEach(::flushPending)
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    /** Returns fixed capability data and, when installed, an actual guest probe. */
    fun probe(
        proot: File,
        loader: File,
        trampoline: File,
    ): Map<String, Any?> = withRootfsReadLock {
        probeLocked(proot, loader, trampoline)
    }

    private fun probeLocked(
        proot: File,
        loader: File,
        trampoline: File,
    ): Map<String, Any?> {
        if (!proot.isFile || !proot.canExecute()) {
            return mapOf(
                "state" to "missing",
                "reason" to "$PROOT_VERSION_LABEL is not packaged in the arm64-v8a native assets.",
            )
        }
        if (!loader.isFile || !loader.canExecute()) {
            return mapOf(
                "state" to "failed",
                "version" to PROOT_VERSION_LABEL,
                "reason" to "The immutable PRoot loader asset is missing.",
            )
        }
        if (!trampoline.isFile || !trampoline.canExecute()) {
            return mapOf(
                "state" to "failed",
                "version" to PROOT_VERSION_LABEL,
                "reason" to "The immutable PRoot host trampoline asset is missing.",
            )
        }

        val installation = try {
            readInstallation()
        } catch (error: Exception) {
            return mapOf(
                "state" to "failed",
                "version" to PROOT_VERSION_LABEL,
                "reason" to (error.message ?: error::class.java.simpleName).take(512),
            )
        } ?: return mapOf(
            "state" to "available",
            "version" to PROOT_VERSION_LABEL,
            "reason" to "PRoot is packaged; install and verify a guest rootfs before execution.",
        )

        val probeResult = runGuestProbe(proot, loader, trampoline, installation)
        if (!probeResult.success) {
            return mapOf(
                "state" to "failed",
                "version" to PROOT_VERSION_LABEL,
                "rootfsDigest" to installation.digest,
                "reason" to buildString {
                    append("The installed rootfs did not pass the app-UID PRoot guest probe.")
                    probeResult.detail?.let { append(" ").append(it) }
                }.take(768),
            )
        }
        return mapOf(
            "state" to "verified",
            "version" to installation.runtimeVersion,
            "rootfsDigest" to installation.digest,
            "maintenanceCwd" to context.noBackupFilesDir.absolutePath,
            "reason" to if (installation.verificationMode == "finalized-proot") {
                "PRoot guest worker executed /usr/bin/true from the finalized ARM64 compatibility rootfs."
            } else {
                "PRoot guest worker executed /usr/bin/true as the Linux compatibility identity."
            },
        )
    }

    fun start(
        proot: File,
        loader: File,
        trampoline: File,
        argv: List<String>,
        cwd: String,
        identity: String,
        timeoutMs: Long,
        requestedEnvironment: Map<String, String>,
    ): String = withRootfsReadLock {
        startLocked(
            proot = proot,
            loader = loader,
            trampoline = trampoline,
            argv = argv,
            cwd = cwd,
            identity = identity,
            timeoutMs = timeoutMs,
            requestedEnvironment = requestedEnvironment,
        )
    }

    /**
     * Serialize a rootfs publication with process launches.
     *
     * Rootfs installs publish a new immutable slot and atomically switch the
     * active-slot pointer. Existing workers keep their already-resolved
     * absolute rootfs path, so they can finish while new workers pick up the
     * new slot.
     */
    fun <T> withRootfsMaintenance(action: () -> T): T {
        val lock = rootfsLifecycleLock.writeLock()
        lock.lock()
        try {
            return action()
        } finally {
            lock.unlock()
        }
    }

    private fun startLocked(
        proot: File,
        loader: File,
        trampoline: File,
        argv: List<String>,
        cwd: String,
        identity: String,
        timeoutMs: Long,
        requestedEnvironment: Map<String, String>,
    ): String {
        require(argv.isNotEmpty()) { "argv must not be empty" }
        require(argv.size <= MAX_ARGUMENTS) { "argv is too long" }
        argv.forEach { require(it.isNotEmpty() && !it.contains('\u0000')) { "argv is invalid" } }
        require(identity == "app" || identity == "root") { "unsupported compatibility identity" }
        require(timeoutMs in 1..MAX_TIMEOUT_MS) { "invalid execution timeout" }
        // Root PRoot is a real Android UID-0 worker, not just PRoot's guest
        // --root-id. The probe selects the normal KernelSU helper and records
        // diagnostics, but it does not turn project-specific SELinux, group,
        // or boot-write samples into a launch gate.
        val rootHelper = if (identity == "root") rootHelperForLaunch() else null
            val hostWorkspace = validateHostWorkspace(cwd)
        val installation = readInstallation()
            ?: error("Linux compatibility rootfs is not verified")
        require(proot.isFile && proot.canExecute()) { "PRoot is unavailable" }
        require(loader.isFile && loader.canExecute()) { "PRoot loader is unavailable" }
        require(trampoline.isFile && trampoline.canExecute()) {
            "PRoot host trampoline is unavailable"
        }

        val id = UUID.randomUUID().toString()
        // Keep one validated marker for every launch that may go through the
        // fixed KernelSU helper. App-identity compatibility launches also use
        // that helper on shared-storage devices; without the marker they can
        // outlive the Java Process object and ignore cancellation.
        val rootMarkerPath = CompatibilityRootLaunchScript.rootMarkerPath(
            noBackupFilesDirectory = context.noBackupFilesDir.absolutePath,
            id = id,
        )
        val executionIsolation = createExecutionIsolation(id)
        try {
            val customModelCatalogJson =
                CodexSessionHome.modelCatalogFromEnvironment(requestedEnvironment)
            val childEnvironment = CodexSessionHome.childEnvironment(requestedEnvironment)
            // The verified guest rootfs is installed root-owned, so the app
            // process cannot create the empty PRoot destination for the full
            // Android host bind itself. Prepare that one fixed mountpoint
            // through the already-selected normal KernelSU helper before
            // building the worker argv. This does not change the rootfs
            // contents or grant the app UID any extra access.
            if (rootHelper != null) {
                rootAssistedLauncher.ensureRootfsHostMountpoint(
                    helper = rootHelper,
                    rootfs = installation.rootfs,
                )
            }
            CodexSessionHome.prepareCompatibility(
                baseHome = installation.home,
                requestedHome = requestedEnvironment["CODEX_HOME"],
                instructions = sessionInstructions,
                preserveModelsCache = identity == "root",
                customModelCatalogJson = customModelCatalogJson,
            )
            if (identity != "root") {
                removeRootOwnedModelsCache(
                    CodexSessionHome.compatibilityModelsCachePath(
                        baseHome = installation.home,
                        requestedHome = requestedEnvironment["CODEX_HOME"],
                    ),
                )
            }
            val caBundleFile = CompatibilityNetworkConfiguration.prepareCaBundle(context)
            val resolverFile = CompatibilityNetworkConfiguration.prepare(
                context,
                runtimeBase(),
            )
            val environment = guestEnvironment(
                requested = childEnvironment,
                caBundleFile = caBundleFile,
                prootTemp = executionIsolation.prootTemp,
                identity = identity,
            )
            val command = buildCommand(
                proot = proot,
                loader = loader,
                trampoline = trampoline,
                installation = installation,
                hostWorkspace = hostWorkspace,
                identity = identity,
                command = argv,
                resolverFile = resolverFile,
                caBundleFile = caBundleFile,
                executionIsolation = executionIsolation,
                codexHome = environment["CODEX_HOME"],
            )
            val launch = if (rootHelper != null) {
                val started = rootAssistedLauncher.startRootOrNull(
                    helper = rootHelper,
                    command = command,
                    environment = environment,
                    directory = hostWorkspace,
                    rootMarkerPath = rootMarkerPath,
                ) ?: error("KernelSU Root PRoot worker could not be started")
                LaunchedProcess(
                    process = started.process,
                    rootHelper = rootHelper,
                    rootMarkerPath = rootMarkerPath,
                    environmentFile = started.environmentFile,
                )
            } else {
                val assisted = rootAssistedLauncher.startOrNull(
                    command = command,
                    environment = environment,
                    directory = hostWorkspace,
                    redirectErrorStream = false,
                    rootMarkerPath = rootMarkerPath,
                )
                if (assisted != null) {
                    LaunchedProcess(
                        process = assisted.process,
                        rootHelper = assisted.helper,
                        rootMarkerPath = assisted.marker,
                        environmentFile = assisted.environmentFile,
                    )
                } else {
                    LaunchedProcess(
                        process = launchProcess(command, environment, hostWorkspace),
                        rootHelper = null,
                        rootMarkerPath = null,
                        environmentFile = null,
                    )
                }
            }
            val entry = Entry(
                id = id,
                process = launch.process,
                executionIsolation = executionIsolation,
                rootMarkerPath = launch.rootMarkerPath,
                rootHelper = launch.rootHelper,
                environmentFile = launch.environmentFile,
            )
            entries[id] = entry
            launch.rootHelper?.let { helper ->
                rootAssistedLauncher.cleanupStaleMarkers(helper)
            }
            val codexHome = environment["CODEX_HOME"] ?: "default"
            Log.i(
                LOG_TAG,
                "start id=$id pid=${processPid(launch.process) ?: -1} identity=$identity " +
                    "codexHome=$codexHome " +
                    "entries=${entries.size}",
            )
            stream(entry, "stdout", launch.process.inputStream)
            stream(entry, "stderr", launch.process.errorStream)
            thread(name = "codex-compatibility-wait-$id") {
                val completed = launch.process.waitFor(timeoutMs, TimeUnit.MILLISECONDS)
                val exitCode = if (completed) {
                    launch.process.exitValue()
                } else {
                    rootAssistedLauncher.terminateRootWorker(entry)
                    launch.process.destroy()
                    if (!launch.process.waitFor(1, TimeUnit.SECONDS)) launch.process.destroyForcibly()
                    emit(entry, event("stderr", "process timed out\n"))
                    -1
                }
                rootAssistedLauncher.removeRootMarker(entry)
                entry.environmentFile?.delete()
                Log.i(
                    LOG_TAG,
                    "exit id=${entry.id} pid=${processPid(entry.process) ?: -1} " +
                        "code=$exitCode entries=${entries.size}",
                )
                finish(entry, exitCode)
                cleanupExecutionIsolation(entry.executionIsolation)
            }
            return id
        } catch (error: Exception) {
            cleanupExecutionIsolation(executionIsolation)
            throw error
        }
    }

    private inline fun <T> withRootfsReadLock(action: () -> T): T {
        val lock = rootfsLifecycleLock.readLock()
        lock.lock()
        try {
            return action()
        } finally {
            lock.unlock()
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
        require(!value.contains('\u0000')) { "process input contains NUL" }
        val entry = entries[id] ?: error("compatibility process is not running")
        entry.process.outputStream.write(value.toByteArray(StandardCharsets.UTF_8))
        entry.process.outputStream.flush()
    }

    fun closeStdin(id: String) {
        val entry = entries[id] ?: error("compatibility process is not running")
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
        try {
            rootAssistedLauncher.terminateRootWorker(entry)
        } finally {
            // A root-assisted supervisor is not necessarily the Process
            // object held by this app. Always destroy the local handle and
            // remove the marker after asking the helper to terminate the
            // whole worker process group.
            entry.process.destroy()
            if (entry.process.isAlive) entry.process.destroyForcibly()
            rootAssistedLauncher.removeRootMarker(entry)
            entry.environmentFile?.delete()
        }
        Log.i(
            LOG_TAG,
            "stop id=$id pid=${processPid(entry.process) ?: -1} " +
                "entries=${entries.size}",
        )
        emit(entry, event("exit", exitCode = -1))
    }

    fun stopAll() {
        entries.keys.toList().forEach(::stop)
    }

    private fun readInstallation(): Installation? {
        val base = runtimeBase()
        if (Files.isSymbolicLink(base.toPath()) || !base.isDirectory) {
            return null
        }
        val activeSlotFile = File(base, ACTIVE_ROOTFS_SLOT)
        val marker: File
        val rootfs: File
        if (activeSlotFile.isFile && !Files.isSymbolicLink(activeSlotFile.toPath())) {
            require(activeSlotFile.length() in 1..MAX_ACTIVE_SLOT_BYTES) {
                "compatibility active rootfs pointer is too large"
            }
            val slot = activeSlotFile.readText(StandardCharsets.UTF_8).trim()
            require(ACTIVE_SLOT.matches(slot)) {
                "compatibility active rootfs pointer is invalid"
            }
            val slots = File(base, ROOTFS_SLOTS_DIRECTORY)
            val slotDirectory = File(slots, slot)
            rootfs = File(slotDirectory, ROOTFS_DIRECTORY)
            marker = File(slotDirectory, RUNTIME_MARKER)
            require(!Files.isSymbolicLink(slots.toPath()) &&
                !Files.isSymbolicLink(slotDirectory.toPath()) &&
                !Files.isSymbolicLink(rootfs.toPath())
            ) { "compatibility active rootfs slot is a symlink" }
        } else {
            // Keep reading the original fixed slot so existing installations
            // upgrade in place without requiring a rootfs re-import.
            marker = File(base, RUNTIME_MARKER)
            rootfs = File(base, ROOTFS_DIRECTORY)
            if (Files.isSymbolicLink(rootfs.toPath())) return null
        }
        if (!marker.isFile || !rootfs.isDirectory) return null
        // Android commonly exposes the same app-private directory through
        // /data/user/0 and /data/data. Compare canonical parents so that
        // aliasing is accepted while a published rootfs slot still
        // cannot escape the app-private runtime base.
        val canonicalBase = base.canonicalFile
        val canonicalRootfs = rootfs.canonicalFile
        val canonicalSlots = File(canonicalBase, ROOTFS_SLOTS_DIRECTORY).canonicalFile
        require(canonicalRootfs.parentFile == canonicalBase ||
            canonicalRootfs.parentFile?.parentFile == canonicalSlots
        ) {
            "compatibility rootfs escaped its app-private base"
        }
        require(marker.length() in 1..MAX_RUNTIME_MARKER_BYTES) {
            "compatibility runtime manifest is too large"
        }
        val json = JSONObject(marker.readText(StandardCharsets.UTF_8))
        require(json.optInt("schemaVersion", -1) == 1) {
            "compatibility runtime manifest schema is unsupported"
        }
        require(json.optString("state") == "verified") {
            "compatibility runtime manifest is not verified"
        }
        val verificationMode = json.optString("verificationMode")
        require(verificationMode == "guest-probe" || verificationMode == "finalized-proot") {
            "compatibility runtime verification mode is unsupported"
        }
        val digest = json.optString("rootfsDigest")
        require(SHA256.matches(digest)) {
            "compatibility runtime digest is invalid"
        }
        val runtimeVersion = json.optString("runtimeVersion")
        require(RUNTIME_VERSION.matches(runtimeVersion)) {
            "compatibility runtime version is invalid"
        }
        if (verificationMode == "finalized-proot") {
            validateFinalizationMarker(rootfs, digest, json)
        }
        listOf(
            File(rootfs, "usr/bin/dash"),
            File(rootfs, "usr/bin/env"),
            File(rootfs, "usr/bin/true"),
            File(rootfs, "usr/lib/aarch64-linux-gnu/ld-linux-aarch64.so.1"),
            File(rootfs, "opt/node/bin/node"),
            File(rootfs, "opt/codex/lib/node_modules/@openai/codex"),
        ).forEach { candidate ->
            require(candidate.exists()) { "compatibility rootfs is incomplete: ${candidate.path}" }
        }
        val home = File(base, HOME_DIRECTORY)
        require(home.mkdirs() || home.isDirectory) { "compatibility guest home unavailable" }
        guestAdminInstaller.ensureInstalled(home)
        // Codex creates ephemeral arg0 helper aliases below CODEX_HOME/tmp/arg0.
        // The target parent is shared, but every running guest binds a private
        // arg0 directory over it. Sharing the actual arg0 directory makes the
        // next Codex janitor collide with a still-running process.
        val codexTemp = File(home, ".codex/tmp")
        require(codexTemp.mkdirs() || codexTemp.isDirectory) {
            "compatibility Codex temp directory unavailable"
        }
        return Installation(
            rootfs = rootfs,
            home = home,
            digest = digest,
            runtimeVersion = runtimeVersion,
            verificationMode = verificationMode,
        )
    }

    /**
     * A successful Root profile is stable for this app/runtime lifetime. Do
     * not re-run the full KernelSU identity/path probe for every one-shot CLI
     * command or session process: repeated su probes can look like repeated
     * Root approvals even though the user already approved the app profile.
     * A failed probe is never cached, so a denied or changed profile remains a
     * real launch failure instead of being turned into a false capability.
     */
    private fun rootHelperForLaunch(): String {
        verifiedRootProfileHelper?.let { return it }
        synchronized(rootProfileLock) {
            verifiedRootProfileHelper?.let { return it }
            val helper = RootProfileLaunchGate.requireSafeHelper(
                AndroidRootProfileProbe(context).run(),
            )
            verifiedRootProfileHelper = helper
            return helper
        }
    }

    private fun validateFinalizationMarker(
        rootfs: File,
        digest: String,
        manifest: JSONObject,
    ) {
        val marker = File(rootfs, FINALIZATION_MARKER)
        require(marker.isFile && !Files.isSymbolicLink(marker.toPath())) {
            "finalized compatibility marker is missing or unsafe"
        }
        require(marker.length() in 1..MAX_FINALIZATION_MARKER_BYTES) {
            "finalized compatibility marker is too large"
        }
        val values = linkedMapOf<String, String>()
        marker.readLines(StandardCharsets.UTF_8).forEach { line ->
            val separator = line.indexOf('=')
            require(separator > 0) { "finalized compatibility marker is malformed" }
            val key = line.substring(0, separator)
            val value = line.substring(separator + 1)
            require(key.matches(FINALIZATION_KEY)) {
                "finalized compatibility marker key is invalid"
            }
            require(values.put(key, value) == null) {
                "finalized compatibility marker contains duplicate keys"
            }
        }
        require(values["status"] == "finalized") {
            "finalized compatibility marker is not successful"
        }
        require(values["digest"] == digest) {
            "finalized compatibility marker digest does not match the manifest"
        }
        mapOf(
            "node_actual_version" to manifest.optString("nodeVersion"),
            "codex_actual_version" to manifest.optString("codexVersion"),
        ).forEach { (key, expected) ->
            require(COMPONENT_VERSION.matches(expected)) {
                "finalized compatibility manifest component version is invalid"
            }
            require(values[key] == expected) {
                "finalized compatibility marker $key does not match the manifest"
            }
        }
    }

    private fun runGuestProbe(
        proot: File,
        loader: File,
        trampoline: File,
        installation: Installation,
    ): GuestProbeResult {
        val executionIsolation = try {
            createExecutionIsolation("probe-${UUID.randomUUID()}")
        } catch (_: Exception) {
            return GuestProbeResult(false, "The guest process isolation directory could not be created.")
        }
        val process = try {
            val probeCommand = buildCommand(
                proot = proot,
                loader = loader,
                trampoline = trampoline,
                installation = installation,
                hostWorkspace = null,
                identity = "app",
                command = listOf("/usr/bin/true"),
                executionIsolation = executionIsolation,
            ).toMutableList()
            val trampolineIndex = probeCommand.indexOf("/codex-host-trampoline")
            require(trampolineIndex >= 0) { "PRoot guest probe command is incomplete." }
            probeCommand.addAll(trampolineIndex, listOf("-v", "1"))
            launchProcess(
                command = probeCommand,
                environment = guestEnvironment(
                    requested = emptyMap(),
                    prootTemp = executionIsolation.prootTemp,
                ),
                directory = installation.home,
                redirectErrorStream = true,
            )
        } catch (_: Exception) {
            cleanupExecutionIsolation(executionIsolation)
            return GuestProbeResult(false, "The guest process could not be started.")
        }
        return try {
            if (!process.waitFor(PROBE_TIMEOUT_MS, TimeUnit.MILLISECONDS)) {
                process.destroyForcibly()
                GuestProbeResult(false, "The guest probe timed out.")
            } else {
                val output = process.inputStream.readBytes()
                    .toString(StandardCharsets.UTF_8)
                    .trim()
                    .replace(Regex("\\s+"), " ")
                    .takeLast(512)
                val exitCode = process.exitValue()
                if (exitCode == 0) {
                    GuestProbeResult(true, null)
                } else {
                    GuestProbeResult(
                        false,
                        buildString {
                            append("exitCode=").append(exitCode)
                            if (output.isNotEmpty()) append(" output=").append(output)
                        },
                    )
                }
            }
        } catch (_: Exception) {
            runCatching { process.destroyForcibly() }
            GuestProbeResult(false, "The guest probe result could not be read.")
        } finally {
            runCatching { process.errorStream.close() }
            runCatching { process.outputStream.close() }
            cleanupExecutionIsolation(executionIsolation)
        }
    }

    private fun launchProcess(
        command: List<String>,
        environment: Map<String, String>,
        directory: File,
        redirectErrorStream: Boolean = false,
    ): Process {
        rootAssistedLauncher.startOrNull(
            command = command,
            environment = environment,
            directory = directory,
            redirectErrorStream = redirectErrorStream,
        )?.let { return it.process }
        return ProcessBuilder(command)
            .directory(directory)
            .redirectErrorStream(redirectErrorStream)
            .apply {
                environment().clear()
                environment().putAll(environment)
            }
            .start()
    }

    private fun buildCommand(
        proot: File,
        loader: File,
        trampoline: File,
        installation: Installation,
        hostWorkspace: File?,
        identity: String,
        command: List<String>,
        resolverFile: File? = null,
        caBundleFile: File? = null,
        executionIsolation: ExecutionIsolation,
        codexHome: String? = null,
    ): List<String> {
        val rootfs = installation.rootfs
        val guestBin = File(rootfs, "usr/bin")
        val guestLib = File(rootfs, "usr/lib")
        val guestMultiarchLib = File(guestLib, "aarch64-linux-gnu")
        val guestSbin = File(rootfs, "usr/sbin")
        val guestDash = File(guestBin, "dash")
        val guestLoader = File(guestMultiarchLib, "ld-linux-aarch64.so.1")
        require(guestBin.isDirectory && guestLib.isDirectory && guestMultiarchLib.isDirectory)
        require(guestSbin.isDirectory && guestDash.isFile && guestLoader.isFile)
        val args = mutableListOf(
            proot.absolutePath,
            "--link2symlink",
            "--kill-on-exit",
            "--rootfs=${rootfs.absolutePath}",
            "--bind=${guestBin.absolutePath}:/bin!",
            "--bind=${guestDash.absolutePath}:/bin/sh!",
            "--bind=${guestSbin.absolutePath}:/sbin!",
            "--bind=${trampoline.absolutePath}:/codex-host-trampoline",
            "--bind=/proc:/proc",
            "--bind=${installation.home.absolutePath}:/home/codex!",
            "--bind=${executionIsolation.temp.absolutePath}:/tmp!",
        )
        // The guest admin adapter lives in the app-owned home so it can be
        // upgraded without replacing the verified rootfs.  A Codex command
        // shell is allowed to rebuild PATH, however, and older CLI versions
        // have done so without preserving the app-specific admin directory.
        // Bind the fixed adapter at the conventional guest path as well, so
        // `sudo apt install ...` is deterministic for both Root and App UID
        // sessions.  This is still the reviewed, non-shell adapter; it does
        // not grant Android privileges or provide an arbitrary command broker.
        val guestAdminSudo = CompatibilityGuestAdminInstaller.sudoShim(
            installation.home,
        )
        args += "--bind=${guestAdminSudo.absolutePath}:/usr/bin/sudo!"
        if (identity == "root") {
            args += compatibilityAndroidHostRootBindArguments(identity, rootfs)
            val existingAndroidDirectories =
                CompatibilityRootLaunchScript.androidHostBindDirectories
                    .filter { File(it).isDirectory }
                    .toMutableSet()
            // App-UID probing can be denied for Android's linker namespace
            // directory even though the KernelSU Root worker can bind it.
            // Android 10+ always exposes this path; keep it in the Root argv
            // instead of silently dropping it during the App-UID probe.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                existingAndroidDirectories += "/linkerconfig"
            }
            args += CompatibilityRootLaunchScript.androidHostBindArguments(
                existingAndroidDirectories,
            )
        }
        if (identity == "root") {
            // Android exposes several shell wrappers whose implementation is
            // just `cmd <service> ...`. PRoot can rebuild PATH before running
            // those wrappers, so map the well-known paths to equivalent guest
            // shims that call the real /system/bin/cmd service directly. The
            // /usr/bin copies are intentional: Codex CLI child shells can
            // discard the launcher's PATH, while /usr/bin remains in their
            // normal Debian search path.
            val androidCommandShim =
                CompatibilityGuestAdminInstaller.androidCommandShim(installation.home)
            args += "--bind=${androidCommandShim.absolutePath}:/usr/bin/cmd!"
            val androidWrapperShims = listOf(
                "pm" to CompatibilityGuestAdminInstaller.androidPackageManagerShim(installation.home),
                "settings" to CompatibilityGuestAdminInstaller.androidSettingsShim(installation.home),
                "appops" to CompatibilityGuestAdminInstaller.androidAppOpsShim(installation.home),
                "wm" to CompatibilityGuestAdminInstaller.androidWindowManagerShim(installation.home),
                "device_config" to CompatibilityGuestAdminInstaller.androidDeviceConfigShim(installation.home),
                "dpm" to CompatibilityGuestAdminInstaller.androidDevicePolicyShim(installation.home),
                "ime" to CompatibilityGuestAdminInstaller.androidImeShim(installation.home),
                "input" to CompatibilityGuestAdminInstaller.androidInputShim(installation.home),
                "locksettings" to CompatibilityGuestAdminInstaller.androidLockSettingsShim(installation.home),
            )
            androidWrapperShims.forEach { (name, shim) ->
                args += "--bind=${shim.absolutePath}:/system/bin/$name!"
                args += "--bind=${shim.absolutePath}:/usr/bin/$name!"
            }
            // Keep the common host diagnostics discoverable after Codex CLI
            // child shells rebuild PATH. These are fixed wrappers to the
            // real Android binaries, not a general command broker.
            CompatibilityGuestAdminInstaller.ANDROID_HOST_COMMAND_NAMES.forEach { name ->
                val shim = CompatibilityGuestAdminInstaller.androidHostCommandShim(
                    installation.home,
                    name,
                )
                args += "--bind=${shim.absolutePath}:/usr/bin/$name!"
            }
        }
        resolverFile?.let { args += CompatibilityNetworkConfiguration.bindArgument(it) }
        caBundleFile?.let {
            require(it.isFile && it.canRead() && !Files.isSymbolicLink(it.toPath()))
            args += "--bind=${it.absolutePath}:${CompatibilityNetworkConfiguration.GUEST_CA_BUNDLE_PATH}!"
        }
        // Codex creates its arg0 aliases below CODEX_HOME/tmp/arg0. Each
        // session has a different CODEX_HOME, so bind the private execution
        // directory at that exact guest path instead of the old shared
        // /home/codex/.codex path. The probe/auth path has no CODEX_HOME and
        // intentionally keeps Codex's default $HOME/.codex location.
        val guestCodexHome = codexHome?.trim()?.takeIf { it.isNotEmpty() }
            ?: "/home/codex/.codex"
        require(
            guestCodexHome.startsWith("/home/codex/") &&
                guestCodexHome.removePrefix("/home/codex/").split('/').none {
                    it.isEmpty() || it == "." || it == ".."
                },
        ) { "compatibility CODEX_HOME must remain below /home/codex" }
        args += "--bind=${executionIsolation.arg0.absolutePath}:$guestCodexHome/tmp/arg0!"
        // Keep the guest's own /lib -> /usr/lib symlink layout intact.
        // Android PRoot can reject redundant guest library-directory or soname
        // binds under the app-data SELinux label; the loader then reports
        // EPERM. Only bind the executable/path overlays needed by this view.
        hostWorkspace?.let {
            require(it.isDirectory && !Files.isSymbolicLink(it.toPath()))
            args += "--bind=${it.absolutePath}:/workspace!"
            args += "--cwd=/workspace"
        } ?: args.add("--cwd=/home/codex")
        if (identity == "root") {
            args += "--root-id"
        } else {
            args += "--change-id=1000:1000"
        }
        args += "/codex-host-trampoline"
        args += resolveGuestArgv(
            rootfs = rootfs,
            guestHome = installation.home,
            command = command,
        )
        return args
    }

    /**
     * The trampoline receives an explicit argv vector, so it cannot ask a
     * guest shell to perform PATH lookup. Resolve only argv[0] against the
     * fixed guest PATH here; arguments remain byte-for-byte caller input.
     *
     * This keeps commands such as `id`, `node`, and `rg` ergonomic without
     * introducing shell parsing or allowing a host executable to be selected.
     */
    private fun resolveGuestArgv(
        rootfs: File,
        guestHome: File,
        command: List<String>,
    ): List<String> {
        val executable = command.firstOrNull() ?: error("compatibility command is empty")
        if (executable.contains('/')) {
            val fromGuestPackage = executable.startsWith("$GUEST_PACKAGE_PREFIX/")
            return compatibilityGuestCommandArgv(
                executable = executable.substringAfterLast('/'),
                resolvedPath = executable,
                arguments = command.drop(1),
                fromGuestPackage = fromGuestPackage,
            )
        }
        require(GUEST_COMMAND_NAME.matches(executable)) {
            "compatibility argv[0] must be an executable name or guest path"
        }
        if (executable == "codex" && hasVerifiedCodexOverlay(guestHome)) {
            return listOf(GUEST_CODEX_OVERLAY_EXECUTABLE) + command.drop(1)
        }
        val guestDirectories = compatibilityGuestPathDirectories()
        val resolved = compatibilityGuestExecutableNames(executable).asSequence()
            .flatMap { commandName ->
                guestDirectories.asSequence().map { directory ->
                    val path = "$directory/$commandName"
                    val candidate = compatibilityGuestExecutableCandidate(
                        rootfs = rootfs,
                        guestHome = guestHome,
                        directory = directory,
                        executable = commandName,
                    )
                    path to candidate
                }
            }
            .firstOrNull { (_, candidate) ->
                candidate.isFile || Files.isSymbolicLink(candidate.toPath())
            }
            ?: error("compatibility command '$executable' was not found in the guest PATH")
        return compatibilityGuestCommandArgv(
            executable = executable,
            resolvedPath = resolved.first,
            arguments = command.drop(1),
            fromGuestPackage = resolved.first.startsWith("$GUEST_PACKAGE_PREFIX/"),
        )
    }

    /**
     * An app-private npm upgrade may override only the Codex launcher. Resolve
     * it only when the fixed `current` symlink lands inside the updater-owned
     * version directory; this keeps user-controlled symlinks out of argv[0].
     */
    private fun hasVerifiedCodexOverlay(guestHome: File): Boolean = runCatching {
        val home = guestHome.canonicalFile
        val overlay = File(home, CODEX_OVERLAY_DIRECTORY)
        val versions = File(overlay, CODEX_OVERLAY_VERSIONS)
        val current = File(overlay, CODEX_OVERLAY_CURRENT)
        if (Files.isSymbolicLink(overlay.toPath()) ||
            Files.isSymbolicLink(versions.toPath()) ||
            !versions.isDirectory ||
            !Files.isSymbolicLink(current.toPath())
        ) {
            return@runCatching false
        }
        val executable = File(current, "bin/codex")
        val resolved = executable.canonicalFile
        val versionsRoot = versions.canonicalFile
        resolved.isFile && resolved.canExecute() &&
            resolved.path.startsWith(versionsRoot.path + File.separator)
    }.getOrDefault(false)

    private fun guestEnvironment(
        requested: Map<String, String>,
        caBundleFile: File? = null,
        prootTemp: File,
        identity: String = "app",
    ): Map<String, String> {
        requested.forEach { (key, value) ->
            require(ENVIRONMENT_KEY.matches(key)) { "invalid environment key" }
            require(!value.contains('\u0000') && !value.contains('\r') && !value.contains('\n')) {
                "invalid environment value"
            }
            require(key !in RESERVED_ENVIRONMENT_KEYS) {
                "compatibility environment key is reserved: $key"
            }
        }
        val requestedHome = requested["CODEX_HOME"]?.trim()
        val scopedHome = requestedHome?.takeIf { GUEST_SESSION_HOME.matches(it) }
        return buildMap {
            put(
                "PATH",
                "$GUEST_CODEX_OVERLAY_DIRECTORY/current/bin:" +
                    "$GUEST_CODEX_OVERLAY_DIRECTORY/current/codex-path:" +
                    "$GUEST_CODEX_OVERLAY_DIRECTORY/current/codex-resources:" +
                    compatibilityGuestPath(identity)
                        .joinToString(":"),
            )
            // Keep home-relative auxiliary files in the same session as
            // CODEX_HOME. Auth invocations omit CODEX_HOME and intentionally
            // continue to use the shared guest login home.
            put("HOME", scopedHome ?: "/home/codex")
            put("USER", "codex")
            put("LOGNAME", "codex")
            put("LANG", "C.UTF-8")
            put("LC_ALL", "C.UTF-8")
            put("TMPDIR", "/tmp")
            // The Android UI owns the only browser launch.  This prevents the
            // CLI from opening a second browser before Flutter receives the
            // validated OAuth URL.
            put("BROWSER", "/usr/bin/true")
            put("PROOT_NO_SECCOMP", "1")
            put("PROOT_LOADER", prootLoaderPath())
            put("PROOT_TMP_DIR", prootTemp.absolutePath)
            // Android does not automatically propagate LinkProperties into a
            // PRoot guest. Forward only the explicit proxy reported by the
            // active network so Codex HTTPS and MCP traffic follow the same
            // validated route as the Android app itself.
            putAll(CompatibilityNetworkConfiguration.httpProxyEnvironment(context))
            if (caBundleFile != null) {
                put("CODEX_CA_CERTIFICATE", CompatibilityNetworkConfiguration.GUEST_CA_BUNDLE_PATH)
                put("SSL_CERT_FILE", CompatibilityNetworkConfiguration.GUEST_CA_BUNDLE_PATH)
            }
            putAll(requested)
        }
    }

    private fun prootLoaderPath(): String =
        File(context.applicationInfo.nativeLibraryDir, PROOT_LOADER_ASSET_NAME).absolutePath

    private fun runtimeBase(): File =
        File(context.noBackupFilesDir, RUNTIME_BASE_DIRECTORY)

    private fun createExecutionIsolation(id: String): ExecutionIsolation {
        require(EXECUTION_ID.matches(id)) { "invalid compatibility execution id" }
        val base = runtimeBase()
        require(!Files.isSymbolicLink(base.toPath())) {
            "compatibility runtime base must not be a symlink"
        }
        val processRoot = File(base, PROCESS_DIRECTORY)
        require(processRoot.mkdirs() || processRoot.isDirectory) {
            "compatibility process directory unavailable"
        }
        require(!Files.isSymbolicLink(processRoot.toPath())) {
            "compatibility process directory must not be a symlink"
        }
        val root = File(processRoot, id)
        require(root.mkdirs() || root.isDirectory) {
            "compatibility execution directory unavailable"
        }
        require(!Files.isSymbolicLink(root.toPath())) {
            "compatibility execution directory must not be a symlink"
        }
        val temp = File(root, "tmp")
        val prootTemp = File(root, "proot-tmp")
        val arg0 = File(root, "arg0")
        listOf(temp, prootTemp, arg0).forEach { directory ->
            require(directory.mkdirs() || directory.isDirectory) {
                "compatibility execution subdirectory unavailable"
            }
            require(!Files.isSymbolicLink(directory.toPath())) {
                "compatibility execution subdirectory must not be a symlink"
            }
        }
        return ExecutionIsolation(
            root = root,
            temp = temp,
            prootTemp = prootTemp,
            arg0 = arg0,
        )
    }

    private fun cleanupExecutionIsolation(isolation: ExecutionIsolation) {
        runCatching {
            val processRoot = File(runtimeBase(), PROCESS_DIRECTORY).canonicalFile
            val root = isolation.root
            if (Files.isSymbolicLink(root.toPath())) return@runCatching
            if (root.canonicalFile.parentFile != processRoot) return@runCatching
            root.deleteRecursively()
        }
    }

    private fun removeRootOwnedModelsCache(cache: File?) {
        if (cache == null) return
        // A root-owned cache can be hidden from the package UID. The path is
        // already constrained to the validated per-session compatibility
        // home, so always give the exact-file root helper a chance to remove
        // it instead of skipping on an app-side stat failure.
        if (CodexSessionHome.tryRemoveModelsCacheAsApp(cache)) return
        if (rootAssistedLauncher.removeExactFile(cache)) {
            Log.i(LOG_TAG, "Removed legacy compatibility models cache")
        } else {
            Log.w(LOG_TAG, "Could not remove legacy compatibility models cache")
        }
    }

    private fun processPid(process: Process): Long? = try {
        Process::class.java.getMethod("pid").invoke(process) as? Long
    } catch (_: Exception) {
        null
    }

    private fun validateHostWorkspace(cwd: String): File {
        val maintenanceRoot = context.noBackupFilesDir.absolutePath
        val isMaintenanceDirectory =
            cwd == maintenanceRoot || cwd.startsWith("$maintenanceRoot/")
        require(cwd.startsWith("$HOST_WORKSPACE_ROOT/") || isMaintenanceDirectory) {
            "compatibility cwd must remain inside the fixed host workspace or app-private runtime directory"
        }
        require(!cwd.contains('\u0000') && !cwd.contains('\r') && !cwd.contains('\n'))
        require(cwd.removePrefix("/").split('/').none { it.isEmpty() || it == "." || it == ".." })
        val candidate = File(cwd)
        val appVisible = runCatching {
            candidate.isDirectory &&
                !Files.isSymbolicLink(candidate.toPath()) &&
                candidate.canonicalPath == cwd
        }.getOrDefault(false)
        if (appVisible) return candidate

        // Android shared storage may be visible to the fixed root-assisted
        // host path while remaining hidden from the package UID.  Do not
        // reject a valid local workspace just because the initial Java
        // process cannot stat it; the root-assisted launcher performs the
        // same canonical/symlink check in the mount namespace that exposes
        // the workspace and enters it before dropping guest privileges.
        require(rootAssistedLauncher.canAccessDirectory(cwd)) {
            "compatibility cwd is unavailable"
        }
        return candidate
    }

    /**
     * App-identity PRoot sessions use the fixed KernelSU launcher and
     * immutable worker guard, then drop to this package UID via setuidgid;
     * Root-identity sessions use the separately gated no-drop launcher below.
     */
    private class FixedRootAssistedLauncher(
        private val context: Context,
    ) {
        @Volatile
        private var selectedCandidate: String? = null

        @Volatile
        private var probeComplete = false

        fun startOrNull(
            command: List<String>,
            environment: Map<String, String>,
            directory: File,
            redirectErrorStream: Boolean,
            rootMarkerPath: String? = null,
        ): StartedProcess? {
            val guard = File(
                context.applicationInfo.nativeLibraryDir,
                PROOT_GUARD_ASSET_NAME,
            )
            if (!guard.isFile || !guard.canExecute()) return null
            val candidate = rootHelperCandidate() ?: return null
            val appUid = context.applicationInfo.uid.takeIf { it > 0 } ?: return null
            val selinuxContext = currentSelinuxContext() ?: return null
            val supplementaryGroups = currentSupplementaryGroups()
            val workerEnvironment = if (rootMarkerPath != null) {
                environment + ("CODEX_COMPAT_PROCESS_MARKER" to rootMarkerPath)
            } else {
                environment
            }
            val environmentFile = runCatching {
                CompatibilityRootLaunchScript.writeEnvironmentFile(
                    context.filesDir,
                    workerEnvironment,
                )
            }.getOrElse { return null }
            val workerCommand = try {
                buildWorkerCommand(
                    appUid = appUid,
                    selinuxContext = selinuxContext,
                supplementaryGroups = supplementaryGroups,
                command = command,
                environmentFile = environmentFile,
            )
            } catch (error: Exception) {
                environmentFile.delete()
                throw error
            }
            val guardedWorker = if (rootMarkerPath != null) {
                val processDirectory =
                    shellQuote(rootMarkerPath.substringBeforeLast('/'))
                val marker = shellQuote(rootMarkerPath)
                val markerCommand =
                    "export CODEX_COMPAT_PROCESS_MARKER=$marker && umask 077 && " +
                        "/system/bin/mkdir -p $processDirectory && " +
                        "/system/bin/chmod 700 $processDirectory && set -C && " +
                        "printf '%s\\n' \"\$\$\" > $marker"
                "$markerCommand && cd ${shellQuote(directory.absolutePath)} && " +
                    "exec $workerCommand"
            } else {
                "cd ${shellQuote(directory.absolutePath)} && exec $workerCommand"
            }
            val rootCommand = buildList {
                add("exec")
                add(guard.absolutePath)
                add("--root-supervisor")
                add(AndroidProcess.myPid().toString())
                add(appUid.toString())
                add("--")
                add(FIXED_SHELL)
                add("-c")
                add(guardedWorker)
            }.joinToString(" ", transform = ::shellQuote)
            val launchScript = buildString {
                append("exec ")
                append(
                    // Keep the app-created storage mount namespace. Using
                    // KernelSU's global mount-master here hides the per-app
                    // FUSE view that the Host backend already verified.
                    listOf(candidate, "-c", rootCommand)
                        .joinToString(" ", transform = ::shellQuote),
                )
            }
            val process = runCatching {
                ProcessBuilder(FIXED_SHELL, "-c", launchScript)
                    .directory(context.filesDir)
                    .redirectErrorStream(redirectErrorStream)
                    .apply { environment().clear() }
                    .start()
            }.getOrElse {
                environmentFile.delete()
                return null
            }
            return StartedProcess(
                process = process,
                helper = candidate,
                marker = rootMarkerPath,
                environmentFile = environmentFile,
            )
        }

        fun startRootOrNull(
            helper: String,
            command: List<String>,
            environment: Map<String, String>,
            directory: File,
            rootMarkerPath: String,
        ): StartedProcess? {
            val guard = File(
                context.applicationInfo.nativeLibraryDir,
                PROOT_GUARD_ASSET_NAME,
            )
            if (!guard.isFile || !guard.canExecute()) return null
            val appUid = context.applicationInfo.uid.takeIf { it > 0 } ?: return null
            val workerEnvironment = environment +
                ("CODEX_COMPAT_PROCESS_MARKER" to rootMarkerPath)
            val environmentFile = runCatching {
                CompatibilityRootLaunchScript.writeEnvironmentFile(
                    context.filesDir,
                    workerEnvironment,
                )
            }.getOrElse { return null }
            val launch = runCatching {
                CompatibilityRootLaunchScript.build(
                    suHelper = helper,
                    workerGuard = guard.absolutePath,
                    parentPid = AndroidProcess.myPid(),
                    appUid = appUid,
                    rootMarkerPath = rootMarkerPath,
                    workingDirectory = directory.absolutePath,
                    argv = command,
                    environment = environment,
                    environmentFile = environmentFile.absolutePath,
                )
            }.getOrElse {
                environmentFile.delete()
                return null
            }
            val process = runCatching {
                ProcessBuilder(launch)
                    .directory(context.filesDir)
                    .redirectErrorStream(false)
                    .apply { environment().clear() }
                    .start()
            }.getOrElse {
                environmentFile.delete()
                return null
            }
            return StartedProcess(
                process = process,
                helper = helper,
                marker = rootMarkerPath,
                environmentFile = environmentFile,
            )
        }

        fun ensureRootfsHostMountpoint(helper: String, rootfs: File) {
            val canonicalRootfs = rootfs.canonicalFile
            check(canonicalRootfs.isDirectory && !Files.isSymbolicLink(canonicalRootfs.toPath())) {
                "compatibility rootfs is not a real directory"
            }
            val mountpoint = File(canonicalRootfs, "android")
            check(!Files.isSymbolicLink(mountpoint.toPath())) {
                "Android host-root guest mountpoint must not be a symbolic link"
            }
            if (mountpoint.isDirectory) return

            val quotedMountpoint = shellQuote(mountpoint.absolutePath)
            val command =
                "/system/bin/mkdir -p $quotedMountpoint && " +
                    "/system/bin/chmod 0755 $quotedMountpoint"
            val process = runCatching {
                ProcessBuilder(helper, "-c", command)
                    .redirectErrorStream(true)
                    .apply { environment().clear() }
                    .start()
            }.getOrNull() ?: error("KernelSU helper could not prepare the guest mountpoint")
            try {
                check(process.waitFor(ROOT_PROBE_TIMEOUT_MS, TimeUnit.MILLISECONDS)) {
                    "KernelSU helper timed out preparing the guest mountpoint"
                }
                check(process.exitValue() == 0) {
                    "KernelSU helper could not create the guest mountpoint"
                }
                check(
                    mountpoint.isDirectory &&
                        !Files.isSymbolicLink(mountpoint.toPath()) &&
                        mountpoint.canonicalFile.parentFile == canonicalRootfs,
                ) { "KernelSU helper created an invalid guest mountpoint" }
            } finally {
                runCatching { process.destroyForcibly() }
                runCatching { process.inputStream.close() }
                runCatching { process.errorStream.close() }
            }
        }

        fun terminateRootWorker(entry: Entry) {
            val helper = entry.rootHelper ?: return
            val marker = entry.rootMarkerPath ?: return
            val killer = runCatching {
                ProcessBuilder(
                    helper,
                    "-c",
                    CompatibilityRootLaunchScript.rootStopCommand(marker),
                ).redirectErrorStream(true).start()
            }.getOrNull() ?: return
            try {
                if (!killer.waitFor(ROOT_KILL_TIMEOUT_MS, TimeUnit.MILLISECONDS)) {
                    killer.destroyForcibly()
                } else if (killer.exitValue() != 0) {
                    Log.w(LOG_TAG, "Root compatibility worker stop command failed")
                }
            } catch (_: Exception) {
                runCatching { killer.destroyForcibly() }
            } finally {
                runCatching { killer.inputStream.close() }
                runCatching { killer.errorStream.close() }
            }
        }

        fun removeRootMarker(entry: Entry) {
            val helper = entry.rootHelper ?: return
            val marker = entry.rootMarkerPath ?: return
            val cleaner = runCatching {
                ProcessBuilder(
                    helper,
                    "-c",
                    CompatibilityRootLaunchScript.rootRemoveMarkerCommand(marker),
                ).redirectErrorStream(true).start()
            }.getOrNull() ?: return
            try {
                if (!cleaner.waitFor(ROOT_KILL_TIMEOUT_MS, TimeUnit.MILLISECONDS)) {
                    cleaner.destroyForcibly()
                }
            } catch (_: Exception) {
                runCatching { cleaner.destroyForcibly() }
            } finally {
                runCatching { cleaner.inputStream.close() }
                runCatching { cleaner.errorStream.close() }
            }
        }

        fun cleanupStaleMarkers(helper: String) {
            val cleaner = runCatching {
                ProcessBuilder(
                    helper,
                    "-c",
                    CompatibilityRootLaunchScript.rootCleanupStaleMarkersCommand(
                        context.noBackupFilesDir.absolutePath,
                    ),
                ).redirectErrorStream(true).start()
            }.getOrNull() ?: return
            try {
                if (!cleaner.waitFor(ROOT_KILL_TIMEOUT_MS, TimeUnit.MILLISECONDS)) {
                    cleaner.destroyForcibly()
                } else if (cleaner.exitValue() != 0) {
                    Log.w(LOG_TAG, "Stale Root compatibility marker cleanup failed")
                }
            } catch (_: Exception) {
                runCatching { cleaner.destroyForcibly() }
            } finally {
                runCatching { cleaner.inputStream.close() }
                runCatching { cleaner.errorStream.close() }
            }
        }

        fun canAccessDirectory(path: String): Boolean {
            val candidate = rootHelperCandidate() ?: return false
            val target = shellQuote(path)
            val command =
                "target=$target; " +
                    "resolved=${'$'}(/system/bin/readlink -f \"${'$'}target\") || exit 20; " +
                    "test \"${'$'}resolved\" = \"${'$'}target\" || exit 21; " +
                    "test -d \"${'$'}resolved\""
            val process = runCatching {
                ProcessBuilder(candidate, FIXED_MOUNT_MASTER, "-c", command)
                    .redirectErrorStream(true)
                    .start()
            }.getOrNull() ?: return false
            return try {
                process.waitFor(ROOT_PROBE_TIMEOUT_MS, TimeUnit.MILLISECONDS) &&
                    process.exitValue() == 0
            } catch (_: Exception) {
                false
            } finally {
                runCatching { process.destroyForcibly() }
                runCatching { process.inputStream.close() }
                runCatching { process.errorStream.close() }
            }
        }

        fun removeExactFile(file: File): Boolean {
            val candidate = rootHelperCandidate() ?: return false
            // Check removal in the root helper's mount namespace. The app UID
            // may not be able to stat a root-owned file, so a client-side
            // `!file.exists()` check cannot prove that cleanup succeeded.
            val quotedPath = shellQuote(file.absolutePath)
            val command =
                "/system/bin/rm -f $quotedPath && " +
                    "test ! -e $quotedPath && test ! -L $quotedPath"
            val process = runCatching {
                ProcessBuilder(candidate, FIXED_MOUNT_MASTER, "-c", command)
                    .redirectErrorStream(true)
                    .start()
            }.getOrNull() ?: return false
            return try {
                process.waitFor(ROOT_PROBE_TIMEOUT_MS, TimeUnit.MILLISECONDS) &&
                    process.exitValue() == 0 &&
                    !file.exists() &&
                    !Files.isSymbolicLink(file.toPath())
            } catch (_: Exception) {
                false
            } finally {
                runCatching { process.destroyForcibly() }
                runCatching { process.inputStream.close() }
                runCatching { process.errorStream.close() }
            }
        }

        private fun rootHelperCandidate(): String? {
            selectedCandidate?.let { return it }
            if (probeComplete) return null
            synchronized(this) {
                selectedCandidate?.let { return it }
                if (!probeComplete) {
                    val appUid = context.applicationInfo.uid.takeIf { it > 0 }
                    selectedCandidate = appUid?.let { uid ->
                        ROOT_HELPER_CANDIDATES.firstOrNull { probe(it, uid) }
                    }
                    probeComplete = true
                }
                return selectedCandidate
            }
        }

        private fun probe(candidate: String, appUid: Int): Boolean {
            val rootCommand = listOf(
                "exec",
                FIXED_BUSYBOX,
                "setuidgid",
                "$appUid:$appUid",
                "/system/bin/id",
                "-u",
            ).joinToString(" ", transform = ::shellQuote)
            val process = runCatching {
                ProcessBuilder(candidate, FIXED_MOUNT_MASTER, "-c", rootCommand)
                    .redirectErrorStream(true)
                    .apply { environment().clear() }
                    .start()
            }.getOrNull() ?: return false
            return try {
                val finished = process.waitFor(ROOT_PROBE_TIMEOUT_MS, TimeUnit.MILLISECONDS)
                val output = process.inputStream.readBytes()
                    .toString(StandardCharsets.UTF_8)
                    .trim()
                finished && process.exitValue() == 0 && output == appUid.toString()
            } catch (_: Exception) {
                false
            } finally {
                runCatching { process.destroyForcibly() }
                runCatching { process.errorStream.close() }
                runCatching { process.inputStream.close() }
            }
        }

        private fun buildWorkerCommand(
            appUid: Int,
            selinuxContext: String,
            supplementaryGroups: List<String>,
            command: List<String>,
            environmentFile: File,
        ): String {
            require(command.isNotEmpty()) { "compatibility command is empty" }
            val guestCommand = command.joinToString(" ", transform = ::shellQuote)
            val file = shellQuote(environmentFile.absolutePath)
            val script =
                "set -e; set -a; . $file; set +a; /system/bin/rm -f $file; " +
                    "exec $guestCommand"
            val environmentCommand = listOf("exec", FIXED_SHELL, "-c", script)
                .joinToString(" ", transform = ::shellQuote)
            // BusyBox setuidgid clears supplementary groups. The fixed host
            // workspace is shared-storage FUSE, so retain only Android's
            // standard storage groups while still dropping the worker UID to
            // this package. No caller-controlled group or user enters this
            // command shape.
            return buildList {
                add("exec")
                add(FIXED_SU)
                add("-Z")
                add(selinuxContext)
                add("-g")
                add(appUid.toString())
                supplementaryGroups.forEach { group ->
                    add("-G")
                    add(group)
                }
                add(appUid.toString())
                add("-c")
                add(environmentCommand)
            }.joinToString(" ", transform = ::shellQuote)
        }

        private fun currentSelinuxContext(): String? = runCatching {
            File("/proc/self/attr/current")
                .readText(StandardCharsets.UTF_8)
                .trimEnd('\u0000', '\n', '\r')
                .trim()
                .takeIf { SELINUX_CONTEXT.matches(it) }
        }.getOrNull()

        private fun currentSupplementaryGroups(): List<String> = runCatching {
            val line = File("/proc/self/status").useLines { lines ->
                lines.firstOrNull { it.startsWith("Groups:") }
            } ?: return@runCatching emptyList()
            line.removePrefix("Groups:")
                .trim()
                .split(Regex("\\s+"))
                .filter { it.isNotEmpty() && GROUP_ID.matches(it) }
                .distinct()
                .take(MAX_SUPPLEMENTARY_GROUPS)
        }.getOrDefault(emptyList())

        private fun shellQuote(value: String): String =
            "'" + value.replace("'", "'\\''") + "'"

        private companion object {
            val ROOT_HELPER_CANDIDATES = listOf(
                "/data/adb/ksu/bin/su",
                "/system/bin/su",
                "/system/xbin/su",
            )
            const val FIXED_BUSYBOX = "/data/adb/ksu/bin/busybox"
            const val FIXED_SU = "/system/bin/su"
            const val FIXED_SHELL = "/system/bin/sh"
            const val FIXED_MOUNT_MASTER = "--mount-master"
            const val ROOT_PROBE_TIMEOUT_MS = 2_000L
            const val MAX_SUPPLEMENTARY_GROUPS = 32
            val GROUP_ID = Regex("[1-9][0-9]{0,4}")
            val SELINUX_CONTEXT = Regex("[A-Za-z0-9_.:,\\-]+")
        }
    }

    private fun stream(entry: Entry, type: String, input: java.io.InputStream) {
        thread(name = "codex-compatibility-$type-${entry.id}") {
            val buffer = ByteArray(8 * 1024)
            try {
                input.use { stream ->
                    while (true) {
                        val count = stream.read(buffer)
                        if (count <= 0) break
                        emit(entry, event(type, String(buffer, 0, count, StandardCharsets.UTF_8)))
                    }
                }
            } catch (error: Exception) {
                emit(entry, event("error", error.message ?: "guest process stream failed"))
            }
        }
    }

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
        mainHandler.post {
            synchronized(entry) {
                val sink = eventSink
                if (!entry.attached || sink == null) {
                    if (entry.pending.size < MAX_PENDING_EVENTS) entry.pending.add(payload)
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
            entry.pending.forEach(sink::success)
            entry.pending.clear()
        }
    }

    private fun event(type: String, value: String? = null, exitCode: Int? = null): Map<String, Any?> =
        buildMap {
            put("type", type)
            if (value != null) put("value", value)
            if (exitCode != null) put("exitCode", exitCode)
        }

    private data class Installation(
        val rootfs: File,
        val home: File,
        val digest: String,
        val runtimeVersion: String,
        val verificationMode: String,
    )

    private data class ExecutionIsolation(
        val root: File,
        val temp: File,
        val prootTemp: File,
        val arg0: File,
    )

    private data class GuestProbeResult(
        val success: Boolean,
        val detail: String?,
    )

    private data class LaunchedProcess(
        val process: Process,
        val rootMarkerPath: String?,
        val rootHelper: String?,
        val environmentFile: File?,
    )

    private data class StartedProcess(
        val process: Process,
        val helper: String,
        val marker: String?,
        val environmentFile: File,
    )

    private data class Entry(
        val id: String,
        val process: Process,
        val executionIsolation: ExecutionIsolation,
        val rootMarkerPath: String?,
        val rootHelper: String?,
        val environmentFile: File?,
        val pending: MutableList<Map<String, Any?>> = mutableListOf(),
        var attached: Boolean = false,
        var completed: Boolean = false,
        var terminalEventEmitted: Boolean = false,
    )

    internal companion object {
        const val LOG_TAG = "CodexCompatProcess"
        const val HOST_WORKSPACE_ROOT = "/storage/emulated/0/Codex/Workspaces"
        const val RUNTIME_BASE_DIRECTORY = "codex-compatibility-v1"
        const val ROOTFS_DIRECTORY = "rootfs"
        const val ROOTFS_SLOTS_DIRECTORY = "rootfs-slots"
        const val ACTIVE_ROOTFS_SLOT = "active-rootfs-slot"
        const val HOME_DIRECTORY = "home"
        const val PROCESS_DIRECTORY = "processes"
        const val RUNTIME_MARKER = "runtime.manifest.json"
        const val CODEX_OVERLAY_DIRECTORY = ".codex-cli"
        const val CODEX_OVERLAY_VERSIONS = "versions"
        const val CODEX_OVERLAY_CURRENT = "current"
        const val GUEST_CODEX_OVERLAY_DIRECTORY = "/home/codex/.codex-cli"
        const val GUEST_CODEX_OVERLAY_EXECUTABLE =
            "$GUEST_CODEX_OVERLAY_DIRECTORY/current/bin/codex"
        const val GUEST_CODEX_BASE_DIRECTORY =
            "/opt/codex/lib/node_modules/@openai/codex/vendor/aarch64-unknown-linux-musl"
        const val GUEST_CODEX_BASE_PATH_DIRECTORY =
            "$GUEST_CODEX_BASE_DIRECTORY/codex-path"
        const val GUEST_CODEX_BASE_RESOURCES_DIRECTORY =
            "$GUEST_CODEX_BASE_DIRECTORY/codex-resources"
        const val GUEST_ADMIN_BIN = "/home/codex/.local/codex-admin/bin"
        const val GUEST_PACKAGE_PREFIX = "/home/codex/.local/codex-pkgs"
        const val GUEST_PACKAGE_LIBRARY_PATH =
            "$GUEST_PACKAGE_PREFIX/lib/aarch64-linux-gnu:" +
                "$GUEST_PACKAGE_PREFIX/usr/lib/aarch64-linux-gnu:" +
                "$GUEST_PACKAGE_PREFIX/lib:$GUEST_PACKAGE_PREFIX/usr/lib"
        const val FINALIZATION_MARKER = "var/lib/codex/rootfs-finalized-proot-v1"
        const val PROOT_LOADER_ASSET_NAME = "libcodex_proot_loader.so"
        const val PROOT_GUARD_ASSET_NAME = "libcodex_worker_guard.so"
        const val MAX_ARGUMENTS = 128
        const val MAX_PENDING_EVENTS = 2_048
        const val MAX_RUNTIME_MARKER_BYTES = 64 * 1024L
        const val MAX_ACTIVE_SLOT_BYTES = 256L
        const val MAX_FINALIZATION_MARKER_BYTES = 16 * 1024L
        const val MAX_TIMEOUT_MS = 24L * 60L * 60L * 1_000L
        const val ROOT_KILL_TIMEOUT_MS = 3_000L
        const val PROBE_TIMEOUT_MS = 10_000L
        val SHA256 = Regex("[0-9a-f]{64}")
        val RUNTIME_VERSION = Regex("[A-Za-z0-9._+\\-]{1,256}")
        val COMPONENT_VERSION = Regex("[A-Za-z0-9._+\\-]{1,256}")
        val ACTIVE_SLOT = Regex("[0-9a-f]{32}")
        val FINALIZATION_KEY = Regex("[A-Za-z0-9._+\\-]{1,128}")
        val GUEST_COMMAND_NAME = Regex("[A-Za-z0-9._+\\-]+")
        val EXECUTION_ID = Regex("[A-Za-z0-9._+\\-]+")
        val GUEST_PATH_DIRECTORIES = listOf(
            "/opt/node/bin",
            GUEST_CODEX_BASE_PATH_DIRECTORY,
            GUEST_CODEX_BASE_RESOURCES_DIRECTORY,
            GUEST_ADMIN_BIN,
            "$GUEST_PACKAGE_PREFIX/usr/local/bin",
            "$GUEST_PACKAGE_PREFIX/usr/bin",
            "$GUEST_PACKAGE_PREFIX/usr/sbin",
            "$GUEST_PACKAGE_PREFIX/bin",
            "$GUEST_PACKAGE_PREFIX/sbin",
            "/usr/local/bin",
            "/usr/sbin",
            "/usr/bin",
            "/sbin",
            "/bin",
        )
        val ENVIRONMENT_KEY = Regex("[A-Za-z_][A-Za-z0-9_]*")
        val GUEST_SESSION_HOME = Regex("/home/codex/sessions/[A-Za-z0-9._-]{1,128}")
        val RESERVED_ENVIRONMENT_KEYS = setOf(
            "CODEX_COMPAT_PROCESS_MARKER",
            "PATH",
            "HOME",
            "TMPDIR",
            "PROOT_NO_SECCOMP",
            "PROOT_LOADER",
            "PROOT_TMP_DIR",
            "BROWSER",
            "HTTP_PROXY",
            "HTTPS_PROXY",
            "ALL_PROXY",
            "http_proxy",
            "https_proxy",
            "all_proxy",
            "NO_PROXY",
            "no_proxy",
        )
    }
}

/**
 * Keeps compatibility workers alive across Flutter engine/activity reattach,
 * while giving the foreground session service one explicit stop boundary.
 */
internal object CompatibilityProcessRuntime {
    private var instance: CompatibilityProcessManager? = null

    fun manager(context: Context): CompatibilityProcessManager = synchronized(this) {
        instance ?: CompatibilityProcessManager(context.applicationContext).also {
            instance = it
        }
    }

    fun stopAll() {
        synchronized(this) {
            instance?.stopAll()
        }
    }
}
