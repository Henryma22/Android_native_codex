package io.henry.codex

import java.io.ByteArrayOutputStream
import java.io.File
import java.io.InputStream
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.nio.charset.StandardCharsets
import java.security.SecureRandom
import java.util.concurrent.TimeUnit
import org.json.JSONArray

/**
 * Stable, non-diagnostic error vocabulary for the plugin boundary.  The
 * messages are deliberately fixed; archive names, filesystem paths, ksud
 * output, and process exceptions never cross this boundary.
 */
internal enum class PluginBrokerErrorCode(
    val wireCode: String,
    val safeMessage: String,
) {
    INVALID_REQUEST("invalid_request", "invalid plugin request"),
    INVALID_REQUEST_ID("invalid_request_id", "invalid plugin request id"),
    INVALID_MODULE_ID("invalid_module_id", "invalid plugin module id"),
    INVALID_DIGEST("invalid_digest", "invalid plugin digest"),
    DIGEST_MISMATCH("digest_mismatch", "plugin digest mismatch"),
    ARCHIVE_EMPTY("archive_empty", "plugin archive is empty"),
    ARCHIVE_TOO_LARGE("archive_too_large", "plugin archive is too large"),
    UNCOMPRESSED_SIZE_LIMIT("uncompressed_size_limit", "plugin archive expands beyond its limit"),
    ENTRY_COUNT_LIMIT("entry_count_limit", "plugin archive has too many entries"),
    ENTRY_TOO_LARGE("entry_too_large", "plugin archive entry is too large"),
    MALFORMED_ARCHIVE("malformed_archive", "plugin archive is malformed"),
    UNSUPPORTED_COMPRESSION("unsupported_compression", "plugin archive compression is unsupported"),
    ENCRYPTED_ENTRY("encrypted_entry", "plugin archive contains an encrypted entry"),
    PATH_ESCAPE("path_escape", "plugin archive contains an unsafe path"),
    NON_CANONICAL_PATH("non_canonical_path", "plugin archive path is not canonical"),
    DUPLICATE_ENTRY("duplicate_entry", "plugin archive contains a duplicate path"),
    SYMLINK_ENTRY("symlink_entry", "plugin archive contains a symlink"),
    HARDLINK_ENTRY("hardlink_entry", "plugin archive contains hard-link metadata"),
    SPECIAL_FILE("special_file", "plugin archive contains a special file"),
    MANIFEST_MISSING("manifest_missing", "plugin manifest is missing"),
    MANIFEST_INVALID("manifest_invalid", "plugin manifest is invalid"),
    MODULE_PROP_MISSING("module_prop_missing", "module.prop is missing"),
    MODULE_PROP_INVALID("module_prop_invalid", "module.prop is invalid"),
    MODULE_ID_MISMATCH("module_id_mismatch", "plugin module identities do not match"),
    MODULE_METADATA_MISMATCH("module_metadata_mismatch", "plugin module metadata does not match"),
    OVERLAY_ROOT_INVALID("overlay_root_invalid", "plugin overlay root is invalid"),
    STAGING_UNSAFE("staging_unsafe", "plugin staging location is unsafe"),
    STAGING_CONFLICT("staging_conflict", "plugin staging slot is occupied"),
    STAGING_FAILED("staging_failed", "plugin archive could not be staged"),
    NO_KERNELSU_OPERATION("no_kernelsu_operation", "this plugin has no KernelSU operation"),
    CONFIRMATION_REQUIRED("confirmation_required", "plugin confirmation is required"),
    BACKUP_HEALTH_REQUIRED("backup_health_required", "plugin backup and health checks are required"),
    ACTION_NOT_DECLARED("action_not_declared", "plugin action is not declared"),
    RISK_REJECTED("risk_rejected", "plugin risk is not allowed by the broker"),
    NOT_STAGED("not_staged", "plugin is not staged"),
    ROLLBACK_UNAVAILABLE("rollback_unavailable", "no verified previous plugin archive is available"),
    KSUD_OPERATION_FAILED("ksud_operation_failed", "KernelSU operation failed"),
}

/** An exception whose externally visible message is always a fixed string. */
internal class PluginBrokerException(
    val code: PluginBrokerErrorCode,
) : IllegalArgumentException(code.safeMessage) {
    val errorCode: PluginBrokerErrorCode
        get() = code
}

/** Fixed operation vocabulary exposed to the native ksud seam. */
internal enum class PluginKsudOperation(val wireName: String) {
    INSTALL("install"),
    LIST("list"),
    ENABLE("enable"),
    DISABLE("disable"),
    UNINSTALL("uninstall"),
    ACTION("action"),
    CONFIG("config"),
}

/** Fixed, sanitized result of the KernelSU Plugin Broker capability probe. */
internal enum class PluginBrokerCapabilityState(val wireName: String) {
    AVAILABLE("available"),
    UNAVAILABLE("unavailable"),
}

internal class PluginBrokerCapabilityProbeResult private constructor(
    val state: PluginBrokerCapabilityState,
    val errorCode: PluginBrokerErrorCode?,
) {
    val available: Boolean
        get() = state == PluginBrokerCapabilityState.AVAILABLE

    /** Only fixed state/boolean/error-code values cross the broker boundary. */
    fun asMap(): Map<String, Any?> = linkedMapOf(
        "available" to available,
        "state" to state.wireName,
        "errorCode" to errorCode?.wireCode,
    ).filterValues { it != null }

    companion object {
        fun available(): PluginBrokerCapabilityProbeResult =
            PluginBrokerCapabilityProbeResult(
                state = PluginBrokerCapabilityState.AVAILABLE,
                errorCode = null,
            )

        fun unavailable(): PluginBrokerCapabilityProbeResult =
            PluginBrokerCapabilityProbeResult(
                state = PluginBrokerCapabilityState.UNAVAILABLE,
                errorCode = PluginBrokerErrorCode.KSUD_OPERATION_FAILED,
            )
    }
}

/**
 * Typed result from ksud.  Output is retained only for the fixed module-list
 * operation, where it is parsed into safe display fields before crossing the
 * native boundary.  Install/action output is still discarded.
 */
internal data class PluginKsudResult(
    val exitCode: Int,
    val stdout: String? = null,
)

internal data class PluginModuleSummary(
    val id: String,
    val name: String,
    val version: String,
    val author: String,
    val enabled: Boolean,
)

/**
 * The probe deliberately has no caller-supplied module ID.  The LIST command
 * does not consume the ID, but the fixed value keeps the typed runner seam
 * total without opening a raw-string or nullable-ID escape hatch.
 */
private object PluginKsudCapabilityProbe {
    val moduleId: VerifiedPluginModuleId =
        VerifiedPluginModuleId.parse("ccpocket.plugin.capability_probe")
}

/**
 * The only seam a real ksud implementation receives.  In particular, this
 * is not a shell callback and has no command/path/environment arguments.
 */
internal fun interface PluginKsudRunner {
    fun run(
        operation: PluginKsudOperation,
        moduleId: VerifiedPluginModuleId,
    ): PluginKsudResult

    /** Invoke only the fixed `ksud module list` capability operation. */
    fun probe(): PluginKsudResult =
        run(PluginKsudOperation.LIST, PluginKsudCapabilityProbe.moduleId)

    /**
     * Install-only handoff for production runners. The default keeps the
     * injected JVM test seam source-compatible; the production root helper
     * overrides it so ksud never reopens an app-owned archive path.
     */
    fun runWithArchive(
        operation: PluginKsudOperation,
        moduleId: VerifiedPluginModuleId,
        archiveBytes: ByteArray,
        archiveSha256: String,
    ): PluginKsudResult = run(operation, moduleId)
}

/** Confirmation source used by risk-gated broker operations. */
internal enum class PluginConfirmation {
    NONE,
    USER_CONFIRMED,
    DEVICE_CREDENTIAL_CONFIRMED,
}

/** A validated archive after it has been written to app-private staging. */
internal class StagedPlugin internal constructor(
    val requestId: String,
    val moduleId: VerifiedPluginModuleId,
    val archive: ValidatedPluginArchive,
    internal val stagedFile: File,
) {
    override fun toString(): String = "StagedPlugin(${moduleId.value}, ${archive.effectiveRisk.wireName})"
}

internal data class PluginOperationResult(
    val moduleId: String,
    val effectiveRisk: PluginRisk,
    val operations: List<PluginKsudOperation>,
    val modules: List<PluginModuleSummary> = emptyList(),
)

internal data class PluginRollbackResult(
    val staged: StagedPlugin,
    val operation: PluginOperationResult,
)

/**
 * Structured broker for app-private staging and fixed KernelSU operations.
 * There is no public method accepting a shell command, path, environment map,
 * or unvalidated module ID.
 */
internal class PluginBroker(
    private val stagingRoot: File,
    private val runner: PluginKsudRunner = RejectingPluginKsudRunner,
    private val limits: PluginArchiveValidator.Limits = PluginArchiveValidator.Limits(),
) {
    /**
     * Validate the complete archive before creating any staging file.  The
     * request ID is an opaque handle and is not used as a filesystem path.
     */
    fun stage(
        requestId: String,
        archiveBytes: ByteArray,
        expectedSha256: String,
    ): StagedPlugin {
        requireRequestId(requestId)
        if (archiveBytes.isEmpty()) {
            throw PluginBrokerException(PluginBrokerErrorCode.ARCHIVE_EMPTY)
        }
        val validated = PluginArchiveValidator.validate(
            archive = archiveBytes,
            expectedSha256 = expectedSha256,
            limits = limits,
        )
        val moduleId = validated.manifest.verifiedModuleId
        val directory = ensureStagingDirectory()
        val destination = File(directory, "${moduleId.value}.zip")
        if (destination.exists()) {
            if (Files.isSymbolicLink(destination.toPath())) {
                throw PluginBrokerException(PluginBrokerErrorCode.STAGING_UNSAFE)
            }
            val current = readValidatedArchiveFile(destination)
                ?: throw PluginBrokerException(PluginBrokerErrorCode.STAGING_CONFLICT)
            if (current.manifest.verifiedModuleId != moduleId) {
                throw PluginBrokerException(PluginBrokerErrorCode.STAGING_CONFLICT)
            }
            backupCurrentArchive(directory, moduleId, destination, current)
        }

        try {
            writeAtomically(destination, archiveBytes, PluginBrokerErrorCode.STAGING_FAILED)
        } catch (error: PluginBrokerException) {
            throw error
        } catch (_: Exception) {
            throw PluginBrokerException(PluginBrokerErrorCode.STAGING_FAILED)
        }

        return StagedPlugin(
            requestId = requestId,
            moduleId = moduleId,
            archive = validated,
            stagedFile = destination,
        )
    }

    /**
     * Rehydrate a broker-owned archive after the Android app process restarts.
     * This validates the existing slot in place and never backs it up,
     * replaces it, or opens a caller-provided path.
     */
    fun restoreStaged(
        moduleId: String,
        requestId: String,
        expectedSha256: String,
    ): StagedPlugin {
        try {
            requireRequestId(requestId)
            val verifiedModuleId = VerifiedPluginModuleId.parse(moduleId)
            val directory = ensureStagingDirectory()
            val destination = File(directory, "${verifiedModuleId.value}.zip")
            val bytes = readArchiveFile(destination)
                ?: throw PluginBrokerException(PluginBrokerErrorCode.NOT_STAGED)
            val validated = PluginArchiveValidator.validate(
                archive = bytes,
                expectedSha256 = expectedSha256,
                limits = limits,
            )
            if (validated.manifest.verifiedModuleId != verifiedModuleId) {
                throw PluginBrokerException(PluginBrokerErrorCode.NOT_STAGED)
            }
            return StagedPlugin(
                requestId = requestId,
                moduleId = verifiedModuleId,
                archive = validated,
                stagedFile = destination,
            )
        } catch (error: PluginBrokerException) {
            throw error
        } catch (_: Exception) {
            throw PluginBrokerException(PluginBrokerErrorCode.NOT_STAGED)
        }
    }

    /**
     * Rehydrate the newest broker-owned archive for the settings page after
     * the Flutter process has restarted. This is app-private file access only;
     * it does not invoke Root or query KernelSU.
     */
    fun restoreLatestStaged(): StagedPlugin? {
        val directory = ensureStagingDirectory()
        val candidates = directory.listFiles()
            ?.asSequence()
            ?.filter { file ->
                file.name.endsWith(".zip") &&
                    !Files.isSymbolicLink(file.toPath()) &&
                    file.isFile
            }
            ?.sortedWith(
                compareByDescending<File> { it.lastModified() }.thenBy { it.name },
            )
            ?.toList()
            .orEmpty()
        for (candidate in candidates) {
            val moduleId = try {
                VerifiedPluginModuleId.parse(candidate.name.removeSuffix(".zip"))
            } catch (_: PluginBrokerException) {
                continue
            }
            val bytes = readArchiveFile(candidate) ?: continue
            val archive = try {
                PluginArchiveValidator.validate(bytes, limits = limits)
            } catch (_: PluginBrokerException) {
                continue
            }
            if (archive.manifest.verifiedModuleId != moduleId) continue
            return StagedPlugin(
                requestId = "restored",
                moduleId = moduleId,
                archive = archive,
                stagedFile = candidate,
            )
        }
        return null
    }

    fun install(
        staged: StagedPlugin,
        confirmation: PluginConfirmation = PluginConfirmation.NONE,
    ): PluginOperationResult {
        ensureStagedIdentity(staged)
        return when (staged.archive.effectiveRisk) {
            PluginRisk.R0 -> throw PluginBrokerException(PluginBrokerErrorCode.NO_KERNELSU_OPERATION)
            PluginRisk.R1 -> runSequence(
                staged = staged,
                operations = listOf(PluginKsudOperation.INSTALL, PluginKsudOperation.ENABLE),
                confirmation = confirmation,
            )
            PluginRisk.R2 -> {
                requireUserConfirmation(confirmation)
                requireBackupAndHealthChecks(staged)
                runSequence(
                    staged = staged,
                    operations = listOf(PluginKsudOperation.INSTALL, PluginKsudOperation.ENABLE),
                    confirmation = confirmation,
                )
            }
            PluginRisk.R3 -> {
                // A boot-sensitive overlay may be installed only into the
                // disabled state.  The separate enable operation requires a
                // device-credential confirmation, so a user approval cannot
                // accidentally activate a system overlay before reboot.
                runSequence(
                    staged = staged,
                    operations = listOf(
                        PluginKsudOperation.INSTALL,
                        PluginKsudOperation.DISABLE,
                    ),
                    confirmation = confirmation,
                )
            }
            PluginRisk.R4 -> {
                requireUserConfirmation(confirmation)
                // Boot/partition-sensitive modules remain inactive until a
                // separate, concrete enable confirmation. R4 is a review
                // route, not a permanent capability denial.
                runSequence(
                    staged = staged,
                    operations = listOf(
                        PluginKsudOperation.INSTALL,
                        PluginKsudOperation.DISABLE,
                    ),
                    confirmation = confirmation,
                )
            }
        }
    }

    /** Enable an already-installed/staged module without ever installing it. */
    fun enable(
        staged: StagedPlugin,
        confirmation: PluginConfirmation = PluginConfirmation.NONE,
    ): PluginOperationResult {
        ensureStagedIdentity(staged)
        when (staged.archive.effectiveRisk) {
            PluginRisk.R0 -> throw PluginBrokerException(PluginBrokerErrorCode.NO_KERNELSU_OPERATION)
            PluginRisk.R1 -> Unit
            PluginRisk.R2 -> {
                requireUserConfirmation(confirmation)
                requireBackupAndHealthChecks(staged)
            }
            PluginRisk.R3 -> {
                if (confirmation != PluginConfirmation.DEVICE_CREDENTIAL_CONFIRMED) {
                    throw PluginBrokerException(PluginBrokerErrorCode.CONFIRMATION_REQUIRED)
                }
            }
            PluginRisk.R4 -> requireUserConfirmation(confirmation)
        }
        runOperation(PluginKsudOperation.ENABLE, staged.moduleId)
        return PluginOperationResult(
            moduleId = staged.moduleId.value,
            effectiveRisk = staged.archive.effectiveRisk,
            operations = listOf(PluginKsudOperation.ENABLE),
        )
    }

    /**
     * Run one action declared by an R2 module.  The action ID is a policy
     * lookup only: KernelSU receives the fixed module action operation and
     * never receives caller-provided action text.
     */
    fun runAction(
        staged: StagedPlugin,
        actionId: String,
        confirmation: PluginConfirmation = PluginConfirmation.NONE,
    ): PluginOperationResult {
        ensureStagedIdentity(staged)
        if (staged.archive.effectiveRisk !in setOf(
                PluginRisk.R2,
                PluginRisk.R3,
                PluginRisk.R4,
            )
        ) {
            throw PluginBrokerException(PluginBrokerErrorCode.RISK_REJECTED)
        }
        if (!isValidActionId(actionId) || actionId !in staged.archive.manifest.actions) {
            throw PluginBrokerException(PluginBrokerErrorCode.ACTION_NOT_DECLARED)
        }
        requireUserConfirmation(confirmation)
        if (staged.archive.effectiveRisk == PluginRisk.R2) {
            requireBackupAndHealthChecks(staged)
        }
        runOperation(PluginKsudOperation.ACTION, staged.moduleId)
        return PluginOperationResult(
            moduleId = staged.moduleId.value,
            effectiveRisk = staged.archive.effectiveRisk,
            operations = listOf(PluginKsudOperation.ACTION),
        )
    }

    fun disable(staged: StagedPlugin): PluginOperationResult =
        runStagedOperation(staged, PluginKsudOperation.DISABLE)

    fun uninstall(staged: StagedPlugin): PluginOperationResult =
        runStagedOperation(staged, PluginKsudOperation.UNINSTALL)

    /**
     * Reinstall and enable the last verified archive for this module.
     *
     * The current and previous app-private ZIPs are swapped only after both
     * archives have been revalidated.  The fixed ksud INSTALL operation then
     * reads the broker-owned current slot; callers never provide an archive
     * path.  R2 still requires the same explicit confirmation and declared
     * backup/health metadata as a normal install.  A boot-sensitive module is
     * restored disabled; boot-chain modules require a separate explicit
     * confirmation before they can be enabled.
     */
    fun rollback(
        staged: StagedPlugin,
        confirmation: PluginConfirmation = PluginConfirmation.NONE,
    ): PluginRollbackResult {
        ensureStagedIdentity(staged)
        val previousFile = previousArchiveFile(staged.moduleId)
        val previousBytes = readArchiveFile(previousFile)
            ?: throw PluginBrokerException(PluginBrokerErrorCode.ROLLBACK_UNAVAILABLE)
        val previous = try {
            PluginArchiveValidator.validate(previousBytes, limits = limits)
        } catch (_: PluginBrokerException) {
            throw PluginBrokerException(PluginBrokerErrorCode.ROLLBACK_UNAVAILABLE)
        }
        if (previous.manifest.verifiedModuleId != staged.moduleId) {
            throw PluginBrokerException(PluginBrokerErrorCode.ROLLBACK_UNAVAILABLE)
        }

        when (previous.effectiveRisk) {
            PluginRisk.R0 -> throw PluginBrokerException(PluginBrokerErrorCode.NO_KERNELSU_OPERATION)
            PluginRisk.R1 -> Unit
            PluginRisk.R2 -> {
                requireUserConfirmation(confirmation)
                requireBackupAndHealthChecks(
                    StagedPlugin(staged.requestId, staged.moduleId, previous, staged.stagedFile),
                )
            }
            PluginRisk.R3 -> {
                // Rollback preserves the same disabled-by-default invariant
                // as a first install.  It still requires an explicit user
                // confirmation, while enable() remains device-credential
                // gated below.
                requireUserConfirmation(confirmation)
            }
            PluginRisk.R4 -> requireUserConfirmation(confirmation)
        }

        val currentBytes = readArchiveFile(staged.stagedFile)
            ?: throw PluginBrokerException(PluginBrokerErrorCode.NOT_STAGED)
        val restoredStage = StagedPlugin(
            requestId = staged.requestId,
            moduleId = staged.moduleId,
            archive = previous,
            stagedFile = staged.stagedFile,
        )

        try {
            // Preserve the current version before replacing the live broker
            // slot. A single previous slot is intentional: it bounds the
            // recovery data and is enough for the MVP update/rollback flow.
            writeAtomically(previousFile, currentBytes, PluginBrokerErrorCode.STAGING_FAILED)
            writeAtomically(staged.stagedFile, previousBytes, PluginBrokerErrorCode.STAGING_FAILED)
            val operation = runSequence(
                staged = restoredStage,
                operations = when (previous.effectiveRisk) {
                    PluginRisk.R3, PluginRisk.R4 -> listOf(
                        PluginKsudOperation.INSTALL,
                        PluginKsudOperation.DISABLE,
                    )
                    else -> listOf(
                        PluginKsudOperation.INSTALL,
                        PluginKsudOperation.ENABLE,
                    )
                },
                confirmation = confirmation,
            )
            return PluginRollbackResult(restoredStage, operation)
        } catch (error: PluginBrokerException) {
            // Keep the broker slots internally consistent if validation or
            // the fixed runner rejects the rollback. The root operation may
            // already have failed/partially run; its status remains the
            // authoritative device-side result and is never exposed here.
            runCatching {
                writeAtomically(staged.stagedFile, currentBytes, PluginBrokerErrorCode.STAGING_FAILED)
                writeAtomically(previousFile, previousBytes, PluginBrokerErrorCode.STAGING_FAILED)
            }
            throw error
        }
    }

    /**
     * Fixed list operation for an already validated module ID.  No archive or
     * process diagnostics are returned by this method.
     */
    fun list(moduleId: String): PluginOperationResult {
        val verified = VerifiedPluginModuleId.parse(moduleId)
        val result = runOperation(PluginKsudOperation.LIST, verified)
        return PluginOperationResult(
            moduleId = verified.value,
            effectiveRisk = PluginRisk.R0,
            operations = listOf(PluginKsudOperation.LIST),
            modules = parseModuleList(result.stdout),
        )
    }

    /**
     * Prove broker capability with the fixed KernelSU module-list operation.
     * Root access alone is intentionally not consulted or treated as proof.
     */
    fun capabilityProbe(): PluginBrokerCapabilityProbeResult {
        val result = try {
            runner.probe()
        } catch (_: Exception) {
            null
        }
        return if (result?.exitCode == 0) {
            PluginBrokerCapabilityProbeResult.available()
        } else {
            PluginBrokerCapabilityProbeResult.unavailable()
        }
    }

    /** Short alias for callers that expose the operation as `probe`. */
    fun probe(): PluginBrokerCapabilityProbeResult = capabilityProbe()

    private fun runStagedOperation(
        staged: StagedPlugin,
        operation: PluginKsudOperation,
    ): PluginOperationResult {
        ensureStagedIdentity(staged)
        // Stopping or removing a previously authorized module must remain
        // available even when its contents are boot/partition-sensitive.
        runOperation(operation, staged.moduleId)
        return PluginOperationResult(
            moduleId = staged.moduleId.value,
            effectiveRisk = staged.archive.effectiveRisk,
            operations = listOf(operation),
        )
    }

    private fun runSequence(
        staged: StagedPlugin,
        operations: List<PluginKsudOperation>,
        confirmation: PluginConfirmation,
    ): PluginOperationResult {
        // `confirmation` is intentionally consumed by the policy checks above;
        // it is never serialized into a shell command or sent to ksud.
        if (confirmation == PluginConfirmation.NONE && staged.archive.effectiveRisk != PluginRisk.R1) {
            throw PluginBrokerException(PluginBrokerErrorCode.CONFIRMATION_REQUIRED)
        }
        for (operation in operations) {
            if (operation == PluginKsudOperation.INSTALL) {
                val archiveBytes = readVerifiedStagedArchive(staged)
                runOperation(
                    operation = operation,
                    moduleId = staged.moduleId,
                    archiveBytes = archiveBytes,
                    archiveSha256 = staged.archive.sha256,
                )
            } else {
                runOperation(operation, staged.moduleId)
            }
        }
        return PluginOperationResult(
            moduleId = staged.moduleId.value,
            effectiveRisk = staged.archive.effectiveRisk,
            operations = operations,
        )
    }

    private fun runOperation(
        operation: PluginKsudOperation,
        moduleId: VerifiedPluginModuleId,
        archiveBytes: ByteArray? = null,
        archiveSha256: String? = null,
    ): PluginKsudResult {
        val result = try {
            if (archiveBytes != null) {
                runner.runWithArchive(
                    operation = operation,
                    moduleId = moduleId,
                    archiveBytes = archiveBytes.copyOf(),
                    archiveSha256 = requireNotNull(archiveSha256),
                )
            } else {
                runner.run(operation, moduleId)
            }
        } catch (_: Exception) {
            throw PluginBrokerException(PluginBrokerErrorCode.KSUD_OPERATION_FAILED)
        }
        if (result.exitCode != 0) {
            throw PluginBrokerException(PluginBrokerErrorCode.KSUD_OPERATION_FAILED)
        }
        return result
    }

    private fun parseModuleList(output: String?): List<PluginModuleSummary> {
        if (output.isNullOrBlank()) return emptyList()
        val modules = try {
            JSONArray(output)
        } catch (_: Exception) {
            return emptyList()
        }
        val summaries = ArrayList<PluginModuleSummary>(modules.length())
        for (index in 0 until modules.length()) {
            val module = modules.optJSONObject(index) ?: continue
            val id = safeModuleText(module.optString("id")) ?: continue
            // KernelSU keeps an uninstalled module in its JSON list until the
            // next module-manager cleanup/reboot, marked with remove=true.
            // It is no longer an installed module from the app's point of
            // view, so do not resurrect it in Settings after a refresh.
            if (module.optString("remove").equals("true", ignoreCase = true)) {
                continue
            }
            summaries += PluginModuleSummary(
                id = id,
                name = safeModuleText(module.optString("name")) ?: id,
                version = safeModuleText(module.optString("version")).orEmpty(),
                author = safeModuleText(module.optString("author")).orEmpty(),
                enabled = module.optString("enabled").equals("true", ignoreCase = true),
            )
        }
        return summaries
    }

    private fun safeModuleText(value: String?): String? {
        val normalized = value?.trim().orEmpty()
        if (normalized.isEmpty() || normalized.length > 512) return null
        if (normalized.any { it.isISOControl() }) return null
        return normalized
    }

    private fun readVerifiedStagedArchive(staged: StagedPlugin): ByteArray {
        ensureStagedIdentity(staged)
        val bytes = readBoundedStagedArchive(staged.stagedFile, staged.archive.archiveSizeBytes)
            ?: throw PluginBrokerException(PluginBrokerErrorCode.NOT_STAGED)
        if (PluginArchiveValidator.sha256(bytes) != staged.archive.sha256) {
            throw PluginBrokerException(PluginBrokerErrorCode.NOT_STAGED)
        }
        return bytes
    }

    private fun ensureStagedIdentity(staged: StagedPlugin) {
        val verified = try {
            VerifiedPluginModuleId.parse(staged.archive.manifest.id)
        } catch (_: PluginBrokerException) {
            throw PluginBrokerException(PluginBrokerErrorCode.NOT_STAGED)
        }
        if (verified != staged.moduleId || staged.archive.manifest.verifiedModuleId != staged.moduleId) {
            throw PluginBrokerException(PluginBrokerErrorCode.NOT_STAGED)
        }

        val stagedFile = staged.stagedFile
        val expectedFile = File(stagingRoot, "${staged.moduleId.value}.zip")
        val fileIsBoundToBroker = try {
            !Files.isSymbolicLink(stagingRoot.toPath()) &&
                !Files.isSymbolicLink(stagedFile.toPath()) &&
                stagedFile.isFile &&
                stagedFile.canonicalFile == expectedFile.canonicalFile &&
                expectedFile.canonicalFile.parentFile == stagingRoot.canonicalFile
        } catch (_: Exception) {
            false
        }
        if (!fileIsBoundToBroker) {
            throw PluginBrokerException(PluginBrokerErrorCode.NOT_STAGED)
        }

        val expectedSize = staged.archive.archiveSizeBytes
        val archiveBytes = readBoundedStagedArchive(stagedFile, expectedSize)
            ?: throw PluginBrokerException(PluginBrokerErrorCode.NOT_STAGED)
        if (PluginArchiveValidator.sha256(archiveBytes) != staged.archive.sha256) {
            throw PluginBrokerException(PluginBrokerErrorCode.NOT_STAGED)
        }
    }

    private fun readBoundedStagedArchive(file: File, expectedSize: Long): ByteArray? {
        if (
            expectedSize <= 0L ||
            expectedSize > limits.maxArchiveBytes ||
            expectedSize > Int.MAX_VALUE
        ) {
            return null
        }
        return try {
            val output = ByteArrayOutputStream(expectedSize.toInt())
            file.inputStream().use { input ->
                val buffer = ByteArray(16 * 1024)
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    if (output.size().toLong() + count > expectedSize) return null
                    output.write(buffer, 0, count)
                }
            }
            output.toByteArray().takeIf { it.size.toLong() == expectedSize }
        } catch (_: Exception) {
            null
        }
    }

    private fun readArchiveFile(file: File): ByteArray? {
        if (
            Files.isSymbolicLink(file.toPath()) ||
            !file.isFile ||
            file.length() <= 0L ||
            file.length() > limits.maxArchiveBytes
        ) {
            return null
        }
        return readBoundedStagedArchive(file, file.length())
    }

    private fun readValidatedArchiveFile(file: File): ValidatedPluginArchive? {
        val bytes = readArchiveFile(file) ?: return null
        return try {
            PluginArchiveValidator.validate(bytes, limits = limits)
        } catch (_: PluginBrokerException) {
            null
        }
    }

    private fun backupCurrentArchive(
        directory: File,
        moduleId: VerifiedPluginModuleId,
        destination: File,
        current: ValidatedPluginArchive,
    ) {
        val bytes = readBoundedStagedArchive(destination, current.archiveSizeBytes)
            ?: throw PluginBrokerException(PluginBrokerErrorCode.STAGING_CONFLICT)
        val previousDirectory = ensurePreviousDirectory(directory)
        writeAtomically(
            File(previousDirectory, "${moduleId.value}.zip"),
            bytes,
            PluginBrokerErrorCode.STAGING_FAILED,
        )
    }

    private fun previousArchiveFile(moduleId: VerifiedPluginModuleId): File {
        val directory = ensurePreviousDirectory(ensureStagingDirectory())
        return File(directory, "${moduleId.value}.zip")
    }

    private fun ensurePreviousDirectory(directory: File): File {
        val previous = File(directory, PREVIOUS_DIRECTORY_NAME)
        try {
            ensureNoSymlinkInPath(previous)
            if (previous.exists()) {
                if (!previous.isDirectory || Files.isSymbolicLink(previous.toPath())) {
                    throw PluginBrokerException(PluginBrokerErrorCode.STAGING_UNSAFE)
                }
            } else if (!previous.mkdirs() && !previous.isDirectory) {
                throw PluginBrokerException(PluginBrokerErrorCode.STAGING_FAILED)
            }
            return previous
        } catch (error: PluginBrokerException) {
            throw error
        } catch (_: Exception) {
            throw PluginBrokerException(PluginBrokerErrorCode.STAGING_UNSAFE)
        }
    }

    private fun writeAtomically(
        destination: File,
        bytes: ByteArray,
        failure: PluginBrokerErrorCode,
    ) {
        val parent = destination.parentFile
            ?: throw PluginBrokerException(failure)
        ensureNoSymlinkInPath(parent)
        if (Files.isSymbolicLink(destination.toPath())) {
            throw PluginBrokerException(PluginBrokerErrorCode.STAGING_UNSAFE)
        }
        val temporary = try {
            File.createTempFile("plugin-", ".pending", parent)
        } catch (_: Exception) {
            throw PluginBrokerException(failure)
        }
        try {
            temporary.outputStream().use { output -> output.write(bytes) }
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
        } catch (_: Exception) {
            temporary.delete()
            throw PluginBrokerException(failure)
        }
    }

    private fun ensureStagingDirectory(): File {
        ensureNoSymlinkInPath(stagingRoot.absoluteFile)
        if (stagingRoot.exists()) {
            if (!stagingRoot.isDirectory || java.nio.file.Files.isSymbolicLink(stagingRoot.toPath())) {
                throw PluginBrokerException(PluginBrokerErrorCode.STAGING_UNSAFE)
            }
            return stagingRoot
        }
        try {
            if (!stagingRoot.mkdirs() && !stagingRoot.isDirectory) {
                throw PluginBrokerException(PluginBrokerErrorCode.STAGING_FAILED)
            }
        } catch (error: PluginBrokerException) {
            throw error
        } catch (_: Exception) {
            throw PluginBrokerException(PluginBrokerErrorCode.STAGING_FAILED)
        }
        return stagingRoot
    }

    /**
     * Check every existing component, not just the immediate parent.  A
     * missing child below a symlinked ancestor would otherwise make mkdirs()
     * publish the staged archive outside the broker-owned directory.
     */
    private fun ensureNoSymlinkInPath(path: File) {
        try {
            var current: File? = path
            while (current != null) {
                if (Files.isSymbolicLink(current.toPath()) && !isAndroidUserDataAlias(current)) {
                    throw PluginBrokerException(PluginBrokerErrorCode.STAGING_UNSAFE)
                }
                current = current.parentFile
            }
        } catch (error: PluginBrokerException) {
            throw error
        } catch (_: Exception) {
            throw PluginBrokerException(PluginBrokerErrorCode.STAGING_UNSAFE)
        }
    }

    /**
     * Android may expose the app data root through `/data/user/<id>` while
     * Java NIO reports that system-managed alias as a symbolic link.  It is
     * outside the app's writable subtree and cannot be redirected by the app;
     * treating it as an unsafe staging parent makes every valid app-private
     * broker path unusable.  All other symlinks remain rejected.
     */
    private fun isAndroidUserDataAlias(path: File): Boolean {
        val normalized = path.absoluteFile.normalize().path
        val prefix = File.separator + "data" + File.separator + "user" + File.separator
        val userId = normalized.removePrefix(prefix)
        return normalized.startsWith(prefix) && userId.isNotEmpty() && userId.all(Char::isDigit)
    }

    private fun requireUserConfirmation(confirmation: PluginConfirmation) {
        if (
            confirmation != PluginConfirmation.USER_CONFIRMED &&
            confirmation != PluginConfirmation.DEVICE_CREDENTIAL_CONFIRMED
        ) {
            throw PluginBrokerException(PluginBrokerErrorCode.CONFIRMATION_REQUIRED)
        }
    }

    private fun requireBackupAndHealthChecks(staged: StagedPlugin) {
        if (
            staged.archive.manifest.backupTargets.isEmpty() ||
            staged.archive.manifest.healthChecks.isEmpty()
        ) {
            throw PluginBrokerException(PluginBrokerErrorCode.BACKUP_HEALTH_REQUIRED)
        }
    }

    private fun requireRequestId(value: String) {
        if (
            value.isEmpty() ||
            value.length > MAX_REQUEST_ID_LENGTH ||
            value.startsWith('.') ||
            value.contains("..") ||
            !value.all {
                it in 'a'..'z' ||
                    it in 'A'..'Z' ||
                    it in '0'..'9' ||
                    it == '_' ||
                    it == '-'
            }
        ) {
            throw PluginBrokerException(PluginBrokerErrorCode.INVALID_REQUEST_ID)
        }
    }

    private fun isValidActionId(value: String): Boolean =
        value.isNotEmpty() &&
            value.length <= MAX_ACTION_ID_LENGTH &&
            value.all {
                it in 'a'..'z' ||
                    it in 'A'..'Z' ||
                    it in '0'..'9' ||
                    it == '_' ||
                    it == '-' ||
                    it == '.' ||
                    it == ':'
            }

    private object RejectingPluginKsudRunner : PluginKsudRunner {
        override fun run(
            operation: PluginKsudOperation,
            moduleId: VerifiedPluginModuleId,
        ): PluginKsudResult = PluginKsudResult(-1)
    }

    private companion object {
        const val MAX_REQUEST_ID_LENGTH = 64
        const val MAX_ACTION_ID_LENGTH = 256
        const val PREVIOUS_DIRECTORY_NAME = "previous"
    }
}

/**
 * Typed seam between the broker and the privileged root helper.  The helper
 * cannot receive a shell command, executable path, environment map, or raw
 * module ID.  The staging root is constructor-owned broker state.
 */
internal fun interface PluginKsudRootHelper {
    fun run(
        operation: PluginKsudOperation,
        moduleId: VerifiedPluginModuleId,
        stagingRoot: File,
    ): PluginKsudResult

    /** The root helper receives only the fixed module-list probe. */
    fun probe(): PluginKsudResult = PluginKsudResult(-1)

    fun runWithArchive(
        operation: PluginKsudOperation,
        moduleId: VerifiedPluginModuleId,
        stagingRoot: File,
        archiveBytes: ByteArray,
        archiveSha256: String,
    ): PluginKsudResult = run(operation, moduleId, stagingRoot)
}

/**
 * Production runner.  KernelSU is never started directly from the ordinary
 * app UID: every operation is delegated to the fixed root-helper seam.
 */
internal class ProcessPluginKsudRunner(
    private val stagingRoot: File,
    private val rootHelper: PluginKsudRootHelper = ProcessPluginKsudRootHelper(),
) : PluginKsudRunner {
    override fun run(
        operation: PluginKsudOperation,
        moduleId: VerifiedPluginModuleId,
    ): PluginKsudResult = if (operation == PluginKsudOperation.INSTALL) {
        PluginKsudResult(-1)
    } else {
        try {
            rootHelper.run(operation, moduleId, stagingRoot)
        } catch (_: Exception) {
            PluginKsudResult(-1)
        }
    }

    override fun probe(): PluginKsudResult = try {
        rootHelper.probe()
    } catch (_: Exception) {
        PluginKsudResult(-1)
    }

    override fun runWithArchive(
        operation: PluginKsudOperation,
        moduleId: VerifiedPluginModuleId,
        archiveBytes: ByteArray,
        archiveSha256: String,
    ): PluginKsudResult = try {
        rootHelper.runWithArchive(
            operation = operation,
            moduleId = moduleId,
            stagingRoot = stagingRoot,
            archiveBytes = archiveBytes.copyOf(),
            archiveSha256 = archiveSha256,
        )
    } catch (_: Exception) {
        PluginKsudResult(-1)
    }
}

/**
 * Fixed Android su implementation of the root-helper seam.  The -c payload
 * is generated exclusively from the fixed operation enum, the verified
 * module ID, and the broker-owned staging root; caller shell text is never
 * accepted.  All payload values are shell-quoted as individual argv members
 * before being passed to the helper.
 */
internal class ProcessPluginKsudRootHelper : PluginKsudRootHelper {
    override fun run(
        operation: PluginKsudOperation,
        moduleId: VerifiedPluginModuleId,
        stagingRoot: File,
    ): PluginKsudResult = if (operation == PluginKsudOperation.INSTALL) {
        // An install must use runWithArchive so the root side never opens the
        // ordinary app-owned staging path after validation.
        PluginKsudResult(-1)
    } else {
        executeRootCommand(
            command = PluginKsudRootCommandBuilder.build(operation, moduleId, stagingRoot),
            input = null,
            captureOutput = operation == PluginKsudOperation.LIST,
        )
    }

    override fun probe(): PluginKsudResult = executeRootCommand(
        command = PluginKsudRootCommandBuilder.buildCapabilityProbe(),
        input = null,
        captureOutput = false,
    )

    override fun runWithArchive(
        operation: PluginKsudOperation,
        moduleId: VerifiedPluginModuleId,
        stagingRoot: File,
        archiveBytes: ByteArray,
        archiveSha256: String,
    ): PluginKsudResult {
        if (
            operation != PluginKsudOperation.INSTALL ||
            PluginArchiveValidator.sha256(archiveBytes) != archiveSha256
        ) {
            return PluginKsudResult(-1)
        }
        val temporaryArchive = File(
            ROOT_STAGING_DIRECTORY,
            "ccpocket-plugin-${randomToken()}.zip",
        )
        return executeRootCommand(
            command = PluginKsudRootCommandBuilder.buildInstallFromStdin(
                moduleId = moduleId,
                temporaryArchive = temporaryArchive,
                archiveSha256 = archiveSha256,
            ),
            input = archiveBytes.copyOf(),
            captureOutput = false,
        )
    }

    private fun executeRootCommand(
        command: String,
        input: ByteArray?,
        captureOutput: Boolean,
    ): PluginKsudResult {
        val process = try {
            startRootHelper(command)
        } catch (_: Exception) {
            return PluginKsudResult(-1)
        }

        val stdout = if (captureOutput) ByteArrayOutputStream(MAX_CAPTURED_LIST_OUTPUT_BYTES) else null
        val stdoutDrainer = Thread(
            {
                if (stdout == null) {
                    discard(process.inputStream)
                } else {
                    captureBounded(process.inputStream, stdout)
                }
            },
            "ccpocket-ksud-stdout",
        )
            .apply { isDaemon = true }
        val stderrDrainer = Thread({ discard(process.errorStream) }, "ccpocket-ksud-stderr")
            .apply { isDaemon = true }
        stdoutDrainer.start()
        stderrDrainer.start()
        try {
            if (input == null) {
                process.outputStream.close()
            } else {
                process.outputStream.use { output ->
                    output.write(input)
                    output.flush()
                }
            }
        } catch (_: Exception) {
            runCatching { process.destroyForcibly() }
            return PluginKsudResult(-1)
        }
        val finished = try {
            process.waitFor(OPERATION_TIMEOUT_MILLIS, TimeUnit.MILLISECONDS)
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
            false
        }
        if (!finished) {
            process.destroy()
            val stopped = try {
                process.waitFor(PROCESS_KILL_GRACE_MILLIS, TimeUnit.MILLISECONDS)
            } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
                false
            }
            if (!stopped) process.destroyForcibly()
        }
        stdoutDrainer.join(OUTPUT_JOIN_MILLIS)
        stderrDrainer.join(OUTPUT_JOIN_MILLIS)
        return PluginKsudResult(
            exitCode = if (finished) process.exitValue() else 124,
            stdout = stdout?.toString(StandardCharsets.UTF_8.name()),
        )
    }

    private fun captureBounded(input: InputStream, output: ByteArrayOutputStream) {
        val buffer = ByteArray(4096)
        try {
            while (true) {
                val read = input.read(buffer)
                if (read < 0) break
                val remaining = MAX_CAPTURED_LIST_OUTPUT_BYTES - output.size()
                if (remaining > 0) output.write(buffer, 0, minOf(read, remaining))
            }
        } catch (_: Exception) {
            // The exit status remains authoritative; partial JSON is ignored.
        } finally {
            runCatching { input.close() }
        }
    }

    private fun randomToken(): String = ByteArray(16).also(random::nextBytes)
        .joinToString("") { byte -> "%02x".format(byte.toInt() and 0xff) }

    private fun startRootHelper(command: String): Process {
        for (candidate in ROOT_HELPER_CANDIDATES) {
            try {
                return ProcessBuilder(candidate, "-c", command)
                    .apply {
                        environment().clear()
                        environment()["PATH"] = ROOT_HELPER_PATH
                    }
                    .redirectErrorStream(false)
                    .start()
            } catch (_: Exception) {
                // Keep helper discovery and platform diagnostics out of the
                // broker error boundary.
            }
        }
        throw IllegalStateException("no fixed root helper is visible")
    }

    private fun discard(stream: InputStream) {
        try {
            val buffer = ByteArray(4096)
            while (stream.read(buffer) >= 0) {
                // Intentionally discard all ksud output.
            }
        } catch (_: Exception) {
            // Exit status remains authoritative.
        } finally {
            try {
                stream.close()
            } catch (_: Exception) {
                // Ignore close failures.
            }
        }
    }

    private companion object {
        val random = SecureRandom()
        val ROOT_HELPER_CANDIDATES = listOf(
            "/data/adb/ksu/bin/su",
            "/system/bin/su",
            "/system/xbin/su",
        )
        const val OPERATION_TIMEOUT_MILLIS = 30_000L
        const val PROCESS_KILL_GRACE_MILLIS = 2_000L
        const val OUTPUT_JOIN_MILLIS = 2_000L
        const val MAX_CAPTURED_LIST_OUTPUT_BYTES = 512 * 1024
        const val ROOT_STAGING_DIRECTORY = "/data/adb/ksu/tmp"
        const val ROOT_HELPER_PATH = "/system/bin:/system/xbin:/vendor/bin:/data/adb/ksu/bin"
    }
}

/** Builds only fixed argv vectors; it never accepts a shell command string. */
internal object PluginKsudCommandBuilder {
    fun buildCapabilityProbe(): List<String> =
        listOf(FIXED_KSUD_EXECUTABLE, "module", "list")

    fun build(
        operation: PluginKsudOperation,
        moduleId: VerifiedPluginModuleId,
        stagingRoot: File,
    ): List<String> {
        val archive = File(stagingRoot, "${moduleId.value}.zip")
        val base = listOf(FIXED_KSUD_EXECUTABLE, "module")
        return when (operation) {
            PluginKsudOperation.INSTALL -> buildInstall(archive)
            PluginKsudOperation.LIST -> base + listOf("list")
            PluginKsudOperation.ENABLE -> base + listOf("enable", moduleId.value)
            PluginKsudOperation.DISABLE -> base + listOf("disable", moduleId.value)
            PluginKsudOperation.UNINSTALL -> base + listOf("uninstall", moduleId.value)
            PluginKsudOperation.ACTION -> base + listOf("action", moduleId.value)
            PluginKsudOperation.CONFIG -> base + listOf("config", moduleId.value)
        }
    }

    fun buildInstall(archive: File): List<String> = listOf(
        FIXED_KSUD_EXECUTABLE,
        "module",
        "install",
        posixPath(archive),
    )

    /** KernelSU commands are Android/POSIX commands even when unit-tested on Windows. */
    private fun posixPath(file: File): String = file.path.replace('\\', '/')

    private const val FIXED_KSUD_EXECUTABLE = "/data/adb/ksu/bin/ksud"
}

/** Encodes the fixed ksud argv for the fixed su -c root boundary. */
internal object PluginKsudRootCommandBuilder {
    fun buildCapabilityProbe(): String {
        val command = PluginKsudCommandBuilder
            .buildCapabilityProbe()
            .joinToString(" ") { shellQuote(it) }
        val rootCommand = "exec $command"
        require(rootCommand.length < MAX_SU_COMMAND_LENGTH)
        return rootCommand
    }

    fun build(
        operation: PluginKsudOperation,
        moduleId: VerifiedPluginModuleId,
        stagingRoot: File,
    ): String {
        val command = PluginKsudCommandBuilder
            .build(operation, moduleId, stagingRoot)
            .joinToString(" ") { shellQuote(it) }
        val rootCommand = "exec $command"
        require(rootCommand.length < MAX_SU_COMMAND_LENGTH) {
            "KernelSU root command exceeds the fixed su argument budget"
        }
        return rootCommand
    }

    /**
     * Builds the install command for the one-time stdin archive handoff. The
     * root shell creates the temporary file, hashes those exact bytes, and
     * removes it through an EXIT trap after ksud returns. The app-owned
     * staging path is not referenced by this command.
     */
    fun buildInstallFromStdin(
        moduleId: VerifiedPluginModuleId,
        temporaryArchive: File,
        archiveSha256: String,
    ): String {
        require(archiveSha256.matches(Regex("[0-9a-f]{64}")))
        val temporaryPath = temporaryArchive.path.replace('\\', '/')
        require(
            temporaryPath.matches(
                Regex("/data/adb/ksu/tmp/ccpocket-plugin-[0-9a-f]{32}\\.zip"),
            ),
        )
        val temporary = shellQuote(temporaryPath)
        val rootDirectory = shellQuote("/data/adb/ksu/tmp")
        val busybox = shellQuote("/data/adb/ksu/bin/busybox")
        val install = PluginKsudCommandBuilder
            .buildInstall(temporaryArchive)
            .joinToString(" ") { shellQuote(it) }
        val script = listOf(
            "umask 077",
            "mkdir -p $rootDirectory",
            "trap ${shellQuote("rm -f $temporaryPath")} EXIT",
            "$busybox cat > $temporary",
            "actual=\$($busybox sha256sum $temporary)",
            "case \"\$actual\" in ${shellQuote("$archiveSha256  ")}*) ;; *) exit 1 ;; esac",
            "$install; status=\$?; exit \$status",
        ).joinToString("; ")
        return "exec '/system/bin/sh' '-c' ${shellQuote(script)}"
    }

    private fun shellQuote(value: String): String =
        "'" + value.replace("'", "'\\''") + "'"

    private const val MAX_SU_COMMAND_LENGTH = 1024
}
