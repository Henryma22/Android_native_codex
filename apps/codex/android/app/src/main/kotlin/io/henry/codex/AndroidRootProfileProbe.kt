package io.henry.codex

import android.content.Context
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.TimeUnit

internal data class RootProfileProbeFailure(val state: String, val reason: String)

internal fun classifyRootProfileProbeFailure(
    helper: String,
    exitCode: Int,
    output: String,
): RootProfileProbeFailure {
    val diagnostic = output.filter { it == '\n' || it == '\t' || it >= ' ' }
        .replace(Regex("\\s+"), " ")
        .trim()
        .take(240)
    val normalized = output.lowercase()
    return if (normalized.contains("root_worker_security_error=")) {
        RootProfileProbeFailure(
            state = "profile_incompatible",
            reason = "The Root launcher could not verify the worker UID; no Codex worker was started.",
        )
    } else if (normalized.contains("setcontext")) {
        RootProfileProbeFailure(
            state = "context_unavailable",
            reason = "KernelSU rejected the normal Root invocation; check the selected KernelSU app profile.",
        )
    } else {
        RootProfileProbeFailure(
            state = "denied",
            reason = buildString {
                append("$helper did not return Root Profile evidence (exit $exitCode).")
                if (diagnostic.isNotEmpty()) append(" Output: ").append(diagnostic)
            },
        )
    }
}

/** Read-only block-alias diagnostics; never used to gate Root startup. */
internal object AndroidBlockDeviceWriteProbe {
    val shell = """
        codex_scan_block_aliases() {
          BLOCK_ALIAS_COUNT=0
          BLOCK_ALIAS_WRITABLE_COUNT=0
          BLOCK_ALIAS_ENUMERATION_COMPLETE=1
          BLOCK_ALIAS_DIR_FOUND=0

          if [ ! -d /dev/block ] || [ ! -r /dev/block ]; then
            BLOCK_ALIAS_ENUMERATION_COMPLETE=0
          fi
          for dir in /dev/block/by-name /dev/block/bootdevice/by-name /dev/block/mapper; do
            if [ -d "${'$'}dir" ]; then
              BLOCK_ALIAS_DIR_FOUND=1
              if [ ! -r "${'$'}dir" ]; then BLOCK_ALIAS_ENUMERATION_COMPLETE=0; fi
            elif [ -e "${'$'}dir" ] || [ -L "${'$'}dir" ]; then
              BLOCK_ALIAS_ENUMERATION_COMPLETE=0
            fi
          done

          for path in /dev/block/* /dev/block/by-name/* /dev/block/bootdevice/by-name/* /dev/block/mapper/*; do
            if [ -L "${'$'}path" ] && [ ! -e "${'$'}path" ]; then
              BLOCK_ALIAS_ENUMERATION_COMPLETE=0
            fi
            if [ -e "${'$'}path" ] && [ -b "${'$'}path" ]; then
              BLOCK_ALIAS_COUNT=${'$'}((BLOCK_ALIAS_COUNT + 1))
              if [ -w "${'$'}path" ]; then
                BLOCK_ALIAS_WRITABLE_COUNT=${'$'}((BLOCK_ALIAS_WRITABLE_COUNT + 1))
              fi
            fi
          done

          BLOCK_ALIAS_READ_ONLY=0
          if [ "${'$'}BLOCK_ALIAS_ENUMERATION_COMPLETE" = 1 ] &&
             [ "${'$'}BLOCK_ALIAS_DIR_FOUND" = 1 ] &&
             [ "${'$'}BLOCK_ALIAS_COUNT" -gt 0 ] &&
             [ "${'$'}BLOCK_ALIAS_WRITABLE_COUNT" -eq 0 ]; then
            BLOCK_ALIAS_READ_ONLY=1
          fi
          return 0
        }

        codex_protected_write_samples_passed() {
          codex_scan_block_aliases || return 1
          [ "${'$'}BLOCK_ALIAS_READ_ONLY" = 1 ] || return 1
          [ -e /dev/block/by-name/boot_a ] && [ ! -w /dev/block/by-name/boot_a ] || return 1
          [ -e /system/build.prop ] && [ ! -w /system/build.prop ] || return 1
          [ -e /vendor/build.prop ] && [ ! -w /vendor/build.prop ] || return 1
          [ -e /sys/fs/selinux/enforce ] && [ ! -w /sys/fs/selinux/enforce ] || return 1

          protected_root_found=0
          for path in /data/adb/ksu/modules /data/adb/modules; do
            if [ -e "${'$'}path" ]; then
              protected_root_found=1
              [ ! -w "${'$'}path" ] || return 1
            fi
          done
          [ "${'$'}protected_root_found" = 1 ] || return 1
          return 0
        }
    """.trimIndent()
}

/** User-triggered, read-only inspection of the configured KernelSU identity. */
internal class AndroidRootProfileProbe(private val context: Context) {
    fun run(): Map<String, Any?> {
        var lastState = "unavailable"
        var lastReason = "KernelSU did not provide a readable Root Profile probe."
        var lastHelper: String? = null
        val workerGuard = File(
            context.applicationInfo.nativeLibraryDir,
            ROOT_WORKER_GUARD,
        )
        if (!workerGuard.isFile || !workerGuard.canExecute()) {
            return mapOf(
                "state" to "unavailable",
                "reason" to "The immutable Root worker guard is unavailable; no Root probe was run.",
            )
        }
        for (helper in ROOT_HELPERS) {
            // Do not inspect the helper with the App UID first. KernelSU's
            // helper directory is commonly hidden from the App UID even when
            // ProcessBuilder(helper, ...) is allowed to cross the Root
            // boundary. The child invocation is the authoritative probe:
            // it reports whether this configured profile actually returned
            // UID 0. An App-side stat/canExecute check would turn a valid
            // Root profile into a false "helper unavailable" result.
            val process = try {
                ProcessBuilder(
                    *CompatibilityRootLaunchScript.rootSuArguments(
                        helper,
                        CompatibilityRootLaunchScript.rootProfileProbeCommand(
                            workerGuard.absolutePath,
                            probeScript(),
                        ),
                    ).toTypedArray(),
                )
                    .directory(context.filesDir)
                    .redirectErrorStream(true)
                    .apply { environment().clear() }
                    .start()
            } catch (error: Exception) {
                if (lastState !in setOf("denied", "context_unavailable", "profile_incompatible")) {
                    lastState = "failed"
                    lastHelper = helper
                    lastReason = "$helper could not be started (${error.javaClass.simpleName}: " +
                        "${error.message.orEmpty().take(180)})."
                }
                continue
            }
            try {
                if (!process.waitFor(PROBE_TIMEOUT_SECONDS, TimeUnit.SECONDS)) {
                    process.destroyForcibly()
                    return mapOf(
                        "state" to "failed",
                        "helper" to helper,
                        "reason" to "Root Profile probe timed out via $helper.",
                    )
                }
                val output = process.inputStream.use { stream ->
                    val bytes = ByteArray(MAX_OUTPUT_BYTES + 1)
                    val captured = ByteArrayOutputStream()
                    while (true) {
                        val count = stream.read(bytes)
                        if (count <= 0) break
                        if (captured.size() + count > MAX_OUTPUT_BYTES) {
                            return mapOf(
                                "state" to "failed",
                                "helper" to helper,
                                "reason" to "Root Profile probe returned oversized output via $helper.",
                            )
                        }
                        captured.write(bytes, 0, count)
                    }
                    captured.toByteArray().toString(Charsets.UTF_8)
                }
                if (process.exitValue() == 0) {
                    return RootProfileProbeAssessment.parse(helper, output)
                }
                val failure = classifyRootProfileProbeFailure(helper, process.exitValue(), output)
                lastHelper = helper
                if (failure.state in setOf("context_unavailable", "profile_incompatible") ||
                    lastState !in setOf("context_unavailable", "profile_incompatible")
                ) {
                    lastState = failure.state
                    lastReason = failure.reason
                }
            } catch (error: Exception) {
                if (lastState !in setOf("denied", "context_unavailable", "profile_incompatible")) {
                    lastState = "failed"
                    lastHelper = helper
                    lastReason = "$helper probe failed (${error.javaClass.simpleName}: " +
                        "${error.message.orEmpty().take(180)})."
                }
            } finally {
                runCatching { process.destroyForcibly() }
                runCatching { process.errorStream.close() }
                runCatching { process.outputStream.close() }
            }
        }
        return mapOf(
            "state" to lastState,
            "helper" to lastHelper,
            "reason" to lastReason,
        )
    }

    private fun probeScript(): String = buildString {
        append(PROBE_SCRIPT)
        append("\ncheck_path appFiles ")
        append(shellQuote(context.filesDir.absolutePath))
        append(" read_sample")
        append("\ncheck_path appNoBackup ")
        append(shellQuote(context.noBackupFilesDir.absolutePath))
        append(" read_sample")
        append("\ncheck_path appProcessStatus '/proc/")
        append(android.os.Process.myPid())
        append("/status' read_sample")
    }

    private fun shellQuote(value: String): String {
        require(value.none { it == '\u0000' || it == '\r' || it == '\n' })
        return "'" + value.replace("'", "'\\''") + "'"
    }

    private companion object {
        const val ROOT_WORKER_GUARD = "libcodex_worker_guard.so"
        val ROOT_HELPERS = listOf(
            "/data/adb/ksu/bin/su",
            "/system/bin/su",
            "/system/xbin/su",
        )
        const val PROBE_TIMEOUT_SECONDS = 5L
        const val MAX_OUTPUT_BYTES = 4096

        // Every target is fixed. Sample bytes/listings are never returned; this
        // only runs after an explicit Settings tap.
        val PROBE_SCRIPT = """
            set -e
            PATH=/system/bin:/system/xbin
            export PATH
            printf 'uid=%s\n' "$(/system/bin/id -u)"
            printf 'gid=%s\n' "$(/system/bin/id -g)"
            printf 'context=%s\n' "$(/system/bin/id -Z)"
            printf 'groups=%s\n' "$(/system/bin/id -G)"
            printf 'capEff=%s\n' "${'$'}(/system/bin/toybox sed -n 's/^CapEff:[[:space:]]*//p' /proc/self/status)"
            printf 'capPrm=%s\n' "${'$'}(/system/bin/toybox sed -n 's/^CapPrm:[[:space:]]*//p' /proc/self/status)"
            printf 'capInh=%s\n' "${'$'}(/system/bin/toybox sed -n 's/^CapInh:[[:space:]]*//p' /proc/self/status)"
            printf 'capBnd=%s\n' "${'$'}(/system/bin/toybox sed -n 's/^CapBnd:[[:space:]]*//p' /proc/self/status)"
            printf 'capAmb=%s\n' "${'$'}(/system/bin/toybox sed -n 's/^CapAmb:[[:space:]]*//p' /proc/self/status)"
            printf 'linuxNoNewPrivs=%s\n' "${'$'}(/system/bin/toybox sed -n 's/^NoNewPrivs:[[:space:]]*//p' /proc/self/status)"
            printf 'selinux=%s\n' "$(/system/bin/getenforce 2>/dev/null || printf unknown)"
            read_sample() {
              if /system/bin/test -d "${'$'}1"; then
                /system/bin/toybox ls -A "${'$'}1" >/dev/null 2>&1
              else
                /system/bin/toybox head -c 1 "${'$'}1" >/dev/null 2>&1
              fi
            }
            check_path() {
              label=$1
              path=$2
              mode=$3
              if /system/bin/test -e "${'$'}path"; then
                printf '%sPresent=1\n' "${'$'}label"
                readable=0
                if /system/bin/test -r "${'$'}path"; then
                  if [ "${'$'}mode" = read_sample ]; then
                    if read_sample "${'$'}path"; then readable=1; fi
                  else
                    readable=1
                  fi
                fi
                printf '%sReadable=%s\n' "${'$'}label" "${'$'}readable"
                if /system/bin/test -w "${'$'}path"; then printf '%sWritable=1\n' "${'$'}label"; else printf '%sWritable=0\n' "${'$'}label"; fi
              else
                printf '%sPresent=0\n' "${'$'}label"
                printf '%sReadable=0\n' "${'$'}label"
                printf '%sWritable=0\n' "${'$'}label"
              fi
            }
            check_path systemData /data/system/packages.xml read_sample
            check_path appDataRoot /data/user/0 read_sample
            check_path appInstallRoot /data/app read_sample
            check_path workspace /storage/emulated/0/Codex/Workspaces read_sample
            check_path bootBlock /dev/block/by-name/boot_a
            ${AndroidBlockDeviceWriteProbe.shell}
            codex_scan_block_aliases
            printf 'blockAliasEnumerationComplete=%s\n' "${'$'}BLOCK_ALIAS_ENUMERATION_COMPLETE"
            printf 'blockAliasCount=%s\n' "${'$'}BLOCK_ALIAS_COUNT"
            printf 'writableBlockAliasCount=%s\n' "${'$'}BLOCK_ALIAS_WRITABLE_COUNT"
            printf 'blockAliasesReadOnly=%s\n' "${'$'}BLOCK_ALIAS_READ_ONLY"
            if codex_protected_write_samples_passed; then
              printf 'protectedWriteSamplesPassed=1\n'
            else
              printf 'protectedWriteSamplesPassed=0\n'
            fi
            check_path ksuModules /data/adb/ksu/modules
            check_path modules /data/adb/modules
            check_path systemConfig /system/build.prop read_sample
            check_path vendorConfig /vendor/build.prop read_sample
            check_path procStatus /proc/1/status read_sample
            check_path selinuxState /sys/fs/selinux/enforce read_sample
        """.trimIndent()
    }
}

/** Selects a normal KernelSU helper after confirming the worker is really UID 0. */
internal object RootProfileLaunchGate {
    private val allowedHelpers = setOf(
        "/data/adb/ksu/bin/su",
        "/system/bin/su",
        "/system/xbin/su",
    )

    fun requireSafeHelper(profile: Map<String, Any?>): String {
        val reason = profile["reason"] as? String
        val helper = profile["helper"] as? String
        check(helper != null && allowedHelpers.contains(helper)) {
            "Android Root Codex worker is unavailable: KernelSU did not expose a usable su helper."
        }
        check(profile["uid"] == "0") {
            buildString {
                append("Android Root Codex worker is unavailable: KernelSU did not return UID 0.")
                if (!reason.isNullOrBlank()) append(" ").append(reason)
            }
        }
        return helper
    }
}

/** Pure parser so profile classification can be tested without a rooted device. */
internal object RootProfileProbeAssessment {
    private val contextPattern = Regex("u:r:[A-Za-z0-9_.-]+:s0(?::c[0-9]+(?:,c[0-9]+)*)?")
    private val requiredGroups = setOf("0", "3003", "3009")

    fun parse(helper: String, output: String): Map<String, Any?> {
        val fields = output.lineSequence().mapNotNull { line ->
            val separator = line.indexOf('=')
            if (separator <= 0) null else line.substring(0, separator) to line.substring(separator + 1)
        }.toMap()
        val uid = fields["uid"].orEmpty()
        val gid = fields["gid"].orEmpty()
        val context = fields["context"].orEmpty()
        val contextPresent = contextPattern.matches(context)
        val groups = fields["groups"].orEmpty()
            .split(Regex("\\s+"))
            .filter(String::isNotEmpty)
            .toSet()
        val networkGroupPresent = "3003" in groups
        val readProcGroupPresent = "3009" in groups
        val requiredGroupsPresent = requiredGroups.all(groups::contains)
        val bootPresent = fields["bootBlockPresent"] == "1"
        val blockAliasEnumerationComplete = fields["blockAliasEnumerationComplete"] == "1"
        val blockAliasCount = fields["blockAliasCount"]?.toIntOrNull()
        val writableBlockAliasCount = fields["writableBlockAliasCount"]?.toIntOrNull()
        val blockAliasesReadOnly = blockAliasEnumerationComplete &&
            blockAliasCount != null && blockAliasCount > 0 &&
            writableBlockAliasCount == 0 && fields["blockAliasesReadOnly"] == "1"
        val protectedRootExists = fields["ksuModulesPresent"] == "1" ||
            fields["modulesPresent"] == "1"
        val protectedRootsReadOnly =
            (fields["ksuModulesPresent"] != "1" || fields["ksuModulesWritable"] == "0") &&
                (fields["modulesPresent"] != "1" || fields["modulesWritable"] == "0")
        val appFilesAccessible = fields["appFilesPresent"] == "1" &&
            fields["appFilesReadable"] == "1" && fields["appFilesWritable"] == "1"
        val appNoBackupAccessible = fields["appNoBackupPresent"] == "1" &&
            fields["appNoBackupReadable"] == "1" && fields["appNoBackupWritable"] == "1"
        val globalReadSamplesPassed = listOf(
            "systemData",
            "appDataRoot",
            "appInstallRoot",
            "systemConfig",
            "vendorConfig",
            "procStatus",
            "appProcessStatus",
            "selinuxState",
        ).all { label ->
            fields["${label}Present"] == "1" && fields["${label}Readable"] == "1"
        }
        val systemConfigReadable = fields["systemConfigReadable"] == "1"
        val vendorConfigReadable = fields["vendorConfigReadable"] == "1"
        val vendorConfigWritable = fields["vendorConfigWritable"] == "1"
        val procStatusReadable = fields["procStatusReadable"] == "1" &&
            fields["appProcessStatusReadable"] == "1"
        val selinuxStateReadable = fields["selinuxStateReadable"] == "1"
        val selinuxStateWritable = fields["selinuxStateWritable"] == "1"
        val protectedWriteSamplesPassed = fields["protectedWriteSamplesPassed"] == "1" &&
            blockAliasesReadOnly && bootPresent && fields["bootBlockWritable"] == "0" &&
            protectedRootExists && protectedRootsReadOnly &&
            fields["systemConfigPresent"] == "1" && fields["systemConfigWritable"] == "0" &&
            fields["vendorConfigPresent"] == "1" && fields["vendorConfigWritable"] == "0" &&
            fields["selinuxStatePresent"] == "1" && fields["selinuxStateWritable"] == "0"
        // Root availability is an identity fact, not a pass/fail decision
        // based on a project-specific SELinux domain, fixed supplementary
        // groups, or boot/block-device write samples. Those fields remain
        // diagnostics for the UI and agent guidance only.
        val state = if (uid == "0") "root" else "denied"
        val reason = if (uid == "0") {
            buildString {
                append("KernelSU returned UID 0 using its configured profile.")
                if (gid != "0") append(" Primary GID is $gid and remains under KernelSU control.")
                if (!contextPresent) append(" SELinux context was not available as a diagnostic.")
                append(" File visibility and protected-path behavior are reported separately.")
            }
        } else {
            "KernelSU did not return UID 0 for the Root Profile probe."
        }
        return linkedMapOf(
            "state" to state,
            "helper" to helper,
            "uid" to uid,
            "gid" to gid,
            "context" to context,
            "groups" to groups.sorted().joinToString(" "),
            "capEff" to fields["capEff"].orEmpty(),
            "capPrm" to fields["capPrm"].orEmpty(),
            "capInh" to fields["capInh"].orEmpty(),
            "capBnd" to fields["capBnd"].orEmpty(),
            "capAmb" to fields["capAmb"].orEmpty(),
            "networkGroupPresent" to networkGroupPresent,
            "readProcGroupPresent" to readProcGroupPresent,
            "requiredGroupsPresent" to requiredGroupsPresent,
            "linuxNoNewPrivs" to fields["linuxNoNewPrivs"].orEmpty(),
            "selinux" to fields["selinux"].orEmpty(),
            "systemDataReadable" to (fields["systemDataReadable"] == "1"),
            "appDataRootReadable" to (fields["appDataRootPresent"] == "1" &&
                fields["appDataRootReadable"] == "1"),
            "appInstallRootReadable" to (fields["appInstallRootPresent"] == "1" &&
                fields["appInstallRootReadable"] == "1"),
            "globalReadSamplesPassed" to globalReadSamplesPassed,
            "workspaceReadable" to (fields["workspaceReadable"] == "1"),
            "workspaceWritable" to (fields["workspaceWritable"] == "1"),
            "appFilesAccessible" to appFilesAccessible,
            "appNoBackupAccessible" to appNoBackupAccessible,
            "blockAliasEnumerationComplete" to blockAliasEnumerationComplete,
            "blockAliasCount" to blockAliasCount,
            "writableBlockAliasCount" to writableBlockAliasCount,
            "blockAliasesReadOnly" to blockAliasesReadOnly,
            "protectedWriteSamplesPassed" to protectedWriteSamplesPassed,
            "bootBlockPresent" to bootPresent,
            "bootBlockWritable" to (fields["bootBlockWritable"] == "1"),
            "protectedRootPresent" to protectedRootExists,
            "protectedRootsWritable" to !protectedRootsReadOnly,
            "systemConfigPresent" to (fields["systemConfigPresent"] == "1"),
            "systemConfigReadable" to systemConfigReadable,
            "systemConfigWritable" to (fields["systemConfigWritable"] == "1"),
            "vendorConfigPresent" to (fields["vendorConfigPresent"] == "1"),
            "vendorConfigReadable" to vendorConfigReadable,
            "vendorConfigWritable" to vendorConfigWritable,
            "procStatusReadable" to procStatusReadable,
            "selinuxStateReadable" to selinuxStateReadable,
            "selinuxStateWritable" to selinuxStateWritable,
            "reason" to reason,
        )
    }
}
