package io.henry.codex

import android.content.Context
import android.util.Base64
import io.flutter.plugin.common.MethodCall
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.util.Locale

/**
 * Flutter-facing adapter for the typed KernelSU broker.
 *
 * This adapter deliberately accepts archive bytes and fixed identifiers only.
 * It does not expose a shell command, a root path, an environment map, or
 * raw KernelSU output to Dart.  The broker remains the policy and validation
 * boundary; this class only translates method-channel values.
 */
internal class KernelSuPluginBridge(context: Context) {
    private val stagingRoot = context.filesDir.resolve("kernelsu/plugin-staging")
    private val broker by lazy {
        PluginBroker(
            stagingRoot = stagingRoot,
            runner = ProcessPluginKsudRunner(stagingRoot),
        )
    }

    fun execute(call: MethodCall): Any? = when (call.method) {
        "probe" -> broker.capabilityProbe().asMap()
        "stage" -> stage(call)
        "install" -> operation(call) { staged, confirmation -> broker.install(staged, confirmation) }
        "enable" -> operation(call) { staged, confirmation -> broker.enable(staged, confirmation) }
        "disable" -> operation(call) { staged, _ -> broker.disable(staged) }
        "uninstall" -> operation(call) { staged, _ -> broker.uninstall(staged) }
        "rollback" -> operation(call) { staged, confirmation -> broker.rollback(staged, confirmation).operation }
        "runAction" -> operation(call) { staged, confirmation ->
            val actionId = call.argument<String>("actionId")?.trim().orEmpty()
            broker.runAction(staged, actionId, confirmation)
        }
        "restoreStage" -> broker.restoreLatestStaged()?.let(::stageMap)
        "list" -> {
            val moduleId = call.argument<String>("moduleId")?.trim().orEmpty()
            broker.list(moduleId.ifEmpty { "ccpocket.plugin.capability_probe" }).toMap()
        }
        else -> throw PluginBrokerException(PluginBrokerErrorCode.INVALID_REQUEST)
    }

    /** Validate the exact staged archive before asking Android for a credential. */
    fun requiresDeviceCredential(call: MethodCall): Boolean {
        if (call.method != "enable") return false
        return restoreStaged(call).archive.effectiveRisk == PluginRisk.R3
    }

    /** Only MainActivity may call this after Android reports device-credential success. */
    fun executeAfterDeviceCredential(call: MethodCall): Any? {
        if (!requiresDeviceCredential(call)) {
            throw PluginBrokerException(PluginBrokerErrorCode.CONFIRMATION_REQUIRED)
        }
        return operation(call, PluginConfirmation.DEVICE_CREDENTIAL_CONFIRMED) { staged, confirmation ->
            broker.enable(staged, confirmation)
        }
    }

    private fun stage(call: MethodCall): Map<String, Any?> {
        val requestId = call.argument<String>("requestId")?.trim().orEmpty()
        val archive = archiveBytes(call)
        val suppliedDigest = call.argument<String>("sha256")?.trim()?.lowercase(Locale.ROOT)
            ?: throw PluginBrokerException(PluginBrokerErrorCode.INVALID_DIGEST)
        val staged = broker.stage(requestId, archive, suppliedDigest)
        return stageMap(staged)
    }

    private fun stageMap(staged: StagedPlugin): Map<String, Any?> {
        val manifest = staged.archive.manifest
        val moduleProp = staged.archive.moduleProp
        val archiveEntriesTruncated = staged.archive.entries.any {
            it.length > MAX_REVIEW_ENTRY_NAME_CHARS
        }
        return linkedMapOf(
            "requestId" to staged.requestId,
            "moduleId" to staged.moduleId.value,
            "sha256" to staged.archive.sha256,
            "effectiveRisk" to staged.archive.effectiveRisk.wireName,
            "archiveSizeBytes" to staged.archive.archiveSizeBytes,
            "uncompressedSizeBytes" to staged.archive.uncompressedSizeBytes,
            "entryCount" to staged.archive.entries.size,
            "containsScripts" to staged.archive.containsScripts,
            "requiresReboot" to staged.archive.manifest.requiresReboot,
            "reviewManifest" to linkedMapOf(
                "name" to safeDisplayText(manifest.name),
                "version" to safeDisplayText(manifest.version),
                "riskHint" to manifest.riskHint.wireName,
                "reversible" to manifest.reversible,
                "capabilities" to manifest.capabilities.map(::safeDisplayText),
                "overlayRoots" to manifest.overlayRoots.map(::safeDisplayText),
                "actions" to manifest.actions.map(::safeDisplayText),
                "backupTargets" to manifest.backupTargets.map(::safeDisplayText),
                "healthChecks" to manifest.healthChecks.map(::safeDisplayText),
            ),
            "moduleProp" to linkedMapOf(
                "author" to safeDisplayText(moduleProp.author),
                "description" to safeDisplayText(moduleProp.description),
            ),
            "archiveEntries" to staged.archive.entries.map { entry ->
                if (entry.length > MAX_REVIEW_ENTRY_NAME_CHARS) {
                    safeDisplayText(entry.take(MAX_REVIEW_ENTRY_NAME_CHARS)) + "…"
                } else {
                    safeDisplayText(entry)
                }
            },
            "archiveEntriesTruncated" to archiveEntriesTruncated,
            "reviewFiles" to staged.archive.reviewFiles.map { file ->
                linkedMapOf(
                    "path" to safeDisplayText(file.path),
                    "sizeBytes" to file.sizeBytes,
                    "content" to file.content,
                    "truncated" to file.truncated,
                )
            },
        )
    }

    private fun operation(
        call: MethodCall,
        trustedConfirmation: PluginConfirmation? = null,
        action: (StagedPlugin, PluginConfirmation) -> PluginOperationResult,
    ): Map<String, Any?> {
        val staged = restoreStaged(call)
        return action(staged, trustedConfirmation ?: parseConfirmation(call)).toMap()
    }

    private fun restoreStaged(call: MethodCall): StagedPlugin {
        val requestId = call.argument<String>("requestId")?.trim().orEmpty()
        val moduleId = call.argument<String>("moduleId")?.trim().orEmpty()
        val digest = call.argument<String>("sha256")?.trim()?.lowercase(Locale.ROOT)
            ?: throw PluginBrokerException(PluginBrokerErrorCode.INVALID_DIGEST)
        return broker.restoreStaged(moduleId, requestId, digest)
    }

    private fun parseConfirmation(call: MethodCall): PluginConfirmation = when (
        call.argument<String>("confirmation")?.trim()
    ) {
        null, "", "none" -> PluginConfirmation.NONE
        "user" -> PluginConfirmation.USER_CONFIRMED
        // A method-channel string is not proof of a device credential. R3
        // enable uses executeAfterDeviceCredential only after MainActivity
        // receives a successful Android system-prompt callback.
        "device_credential" ->
            throw PluginBrokerException(PluginBrokerErrorCode.CONFIRMATION_REQUIRED)
        else -> throw PluginBrokerException(PluginBrokerErrorCode.INVALID_REQUEST)
    }

    private fun archiveBytes(call: MethodCall): ByteArray {
        val direct = call.argument<ByteArray>("archiveBytes")
        if (direct != null) return direct

        // Kept for non-Flutter callers and migration tooling.  Canonical
        // single-line Base64 is required; URL-safe and wrapped variants are
        // intentionally rejected before the broker sees the bytes.
        val encoded = call.argument<String>("archiveBase64")
            ?: throw PluginBrokerException(PluginBrokerErrorCode.INVALID_REQUEST)
        if (encoded.isEmpty() || encoded.any { it.isWhitespace() }) {
            throw PluginBrokerException(PluginBrokerErrorCode.INVALID_REQUEST)
        }
        val decoded = try {
            Base64.decode(encoded, Base64.DEFAULT)
        } catch (_: IllegalArgumentException) {
            throw PluginBrokerException(PluginBrokerErrorCode.INVALID_REQUEST)
        }
        val canonical = Base64.encodeToString(decoded, Base64.NO_WRAP)
        if (canonical != encoded) {
            throw PluginBrokerException(PluginBrokerErrorCode.INVALID_REQUEST)
        }
        return decoded
    }

    private fun PluginOperationResult.toMap(): Map<String, Any?> = linkedMapOf(
        "moduleId" to moduleId,
        "effectiveRisk" to effectiveRisk.wireName,
        "operations" to operations.map { it.wireName },
        "modules" to modules.map { module ->
            linkedMapOf(
                "id" to module.id,
                "name" to module.name,
                "version" to module.version,
                "author" to module.author,
                "enabled" to module.enabled,
            )
        },
    )

    companion object {
        private const val MAX_REVIEW_ENTRY_NAME_CHARS = 512

        private fun safeDisplayText(value: String): String = buildString(value.length) {
            for (character in value) {
                val code = character.code
                if (
                    character.isISOControl() && character !in setOf('\n', '\r', '\t') ||
                    code in 0x202a..0x202e ||
                    code in 0x2066..0x2069 ||
                    code == 0x200b ||
                    code == 0xfeff
                ) {
                    append("\\u")
                    append(code.toString(16).padStart(4, '0'))
                } else {
                    append(character)
                }
            }
        }

        fun sha256(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256")
            .digest(bytes)
            .joinToString("") { byte -> "%02x".format(byte.toInt() and 0xff) }

        fun archiveResponse(bytes: ByteArray, displayName: String?): Map<String, Any?> =
            linkedMapOf(
                "bytes" to bytes,
                "sha256" to sha256(bytes),
                "displayName" to displayName?.takeIf { it.isNotBlank() },
            ).filterValues { it != null }
    }
}
