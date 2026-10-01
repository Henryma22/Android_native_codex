package io.henry.codex

import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.nio.charset.StandardCharsets
import java.nio.file.AtomicMoveNotSupportedException
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.security.MessageDigest

/**
 * Stores only local, user-visible session history in the app-private area.
 *
 * This is deliberately a history cache, not a reconnect token store: it never
 * contains credentials and it does not imply that a provider thread can be
 * resumed after the process has gone away. A named session may retain its
 * explicit Root approval bit so returning to that same session does not ask
 * again; legacy workspace-only rows can never carry that grant.
 */
internal class SessionHistoryStore(private val filesDir: File) {
    fun load(key: String): Map<String, Any>? {
        val file = recordFile(key)
        if (!file.isFile) return null
        return try {
            val record = readRecord(file)
            if (record["archived"] == true) {
                file.delete()
                null
            } else {
                record
            }
        } catch (error: Exception) {
            throw IllegalStateException("session history is invalid", error)
        }
    }

    fun list(): List<Map<String, Any>> {
        val directory = File(filesDir, "codex/session-history")
        if (!directory.isDirectory) return emptyList()
        return directory.listFiles()
            ?.asSequence()
            ?.filter { it.isFile && it.extension == "json" }
            ?.mapNotNull { file ->
                runCatching { readRecord(file) }.getOrNull()
                    ?.takeUnless { record ->
                        if (record["archived"] == true) {
                            file.delete()
                            true
                        } else {
                            false
                        }
                    }
            }
            ?.sortedByDescending { record ->
                (record["updatedAtEpochMs"] as? Number)?.toLong() ?: 0L
            }
            ?.toList()
            ?: emptyList()
    }

    fun save(key: String, record: Map<*, *>) {
        val directory = File(filesDir, "codex/session-history")
        if (!directory.exists() && !directory.mkdirs()) {
            throw IllegalStateException("could not create session history directory")
        }
        val entries = (record["entries"] as? List<*>)
            ?.mapNotNull { it as? String }
            ?.takeLast(MAX_ENTRIES)
            ?.map { it.take(MAX_ENTRY_CHARS) }
            ?: emptyList()
        val queuedPrompts = (record["queuedPrompts"] as? List<*>)
            ?.mapNotNull { it as? String }
            ?.take(MAX_QUEUED_PROMPTS)
            ?.map { it.take(MAX_DRAFT_CHARS) }
            ?: emptyList()
        val promptHistory = (record["promptHistory"] as? List<*>)
            ?.mapNotNull { it as? String }
            ?.filter { it.isNotBlank() }
            ?.take(MAX_PROMPT_HISTORY)
            ?.map { it.take(MAX_DRAFT_CHARS) }
            ?: emptyList()
        val sessionId = (record["sessionId"] as? String)?.trim()
        val authGeneration = (record["authGeneration"] as? Number)?.toLong()
        val json = JSONObject()
            .put("backendId", (record["backendId"] as? String).orEmpty())
            .put("workspacePath", (record["workspacePath"] as? String).orEmpty())
            .put("status", (record["status"] as? String).orEmpty())
            .put("updatedAtEpochMs", (record["updatedAtEpochMs"] as? Number)?.toLong() ?: 0L)
            .put("draft", (record["draft"] as? String).orEmpty().take(MAX_DRAFT_CHARS))
            .put("queuedPrompts", JSONArray(queuedPrompts))
            // Model and effort identifiers come from the installed CLI. Keep
            // them data-driven so upgrading Codex does not require an APK
            // release just to persist a newly introduced choice.
            .put("codexModel", normalizeCodexModel(record["codexModel"] as? String))
            .put("codexEffort", normalizeCodexEffort(record["codexEffort"] as? String))
            .put("executionIdentity", normalizeExecutionIdentity(record["executionIdentity"] as? String))
            .put(
                "rootApprovalGranted",
                (record["rootApprovalGranted"] as? Boolean) == true && !sessionId.isNullOrEmpty(),
            )
            .put("codexSandbox", (record["codexSandbox"] as? String).orEmpty().take(MAX_SETTING_CHARS))
            .put("codexApprovalPolicy", (record["codexApprovalPolicy"] as? String).orEmpty().take(MAX_SETTING_CHARS))
            .put("codexPlanMode", record["codexPlanMode"] as? Boolean ?: false)
            .put("pinned", record["pinned"] as? Boolean ?: false)
            .put("titleIsManual", record["titleIsManual"] as? Boolean ?: false)
            .put("promptHistory", JSONArray(promptHistory))
            .put("entries", JSONArray(entries))
        val title = (record["title"] as? String)?.trim()
        if (!title.isNullOrEmpty()) {
            json.put("title", title.take(MAX_TITLE_CHARS))
        }
        val threadName = (record["threadName"] as? String)?.trim()
        if (!threadName.isNullOrEmpty()) {
            json.put("threadName", threadName.take(MAX_TITLE_CHARS))
        }
        if (!sessionId.isNullOrEmpty()) json.put("sessionId", sessionId)
        if (authGeneration != null && authGeneration > 0L) {
            json.put("authGeneration", authGeneration)
        }
        val threadId = record["threadId"] as? String
        if (!threadId.isNullOrEmpty()) json.put("threadId", threadId)

        val target = recordFile(key)
        writeAtomically(target, json)
    }

    fun updateFlags(key: String, pinned: Boolean?) {
        if (pinned == null) return
        val target = recordFile(key)
        if (!target.isFile) return
        val json = JSONObject(target.readText(StandardCharsets.UTF_8))
        json.put("pinned", pinned)
        writeAtomically(target, json)
    }

    fun updateTitle(key: String, title: String?) {
        val target = recordFile(key)
        if (!target.isFile) return
        val json = JSONObject(target.readText(StandardCharsets.UTF_8))
        val normalized = title?.trim().orEmpty()
        if (normalized.isEmpty()) {
            json.remove("title")
            json.put("titleIsManual", false)
        } else {
            json.put("title", normalized.take(MAX_TITLE_CHARS))
            json.put("titleIsManual", true)
        }
        writeAtomically(target, json)
    }

    fun clear(key: String) {
        recordFile(key).delete()
    }

    fun clearAll() {
        val directory = File(filesDir, "codex/session-history")
        directory.listFiles()
            ?.filter { it.isFile && it.extension == "json" }
            ?.forEach { it.delete() }
    }

    private fun readRecord(file: File): Map<String, Any> {
        val json = JSONObject(file.readText(StandardCharsets.UTF_8))
        val entriesJson = json.optJSONArray("entries") ?: JSONArray()
        val entries = ArrayList<String>(entriesJson.length())
        for (index in 0 until entriesJson.length()) {
            val entry = entriesJson.optString(index, "")
            if (entry.isNotEmpty()) entries.add(entry)
        }
        val sessionId = json.optString("sessionId", "").trim()
        val result = mutableMapOf<String, Any>(
            "backendId" to json.optString("backendId", ""),
            "workspacePath" to json.optString("workspacePath", ""),
            "status" to json.optString("status", "stopped"),
            "updatedAtEpochMs" to json.optLong("updatedAtEpochMs", 0L),
            "draft" to json.optString("draft", ""),
            "codexModel" to normalizeCodexModel(json.optString("codexModel", "")),
            "codexEffort" to normalizeCodexEffort(json.optString("codexEffort", "")),
            "executionIdentity" to normalizeExecutionIdentity(json.optString("executionIdentity", "app")),
            "rootApprovalGranted" to (json.optBoolean("rootApprovalGranted", false) && sessionId.isNotEmpty()),
            "codexSandbox" to json.optString("codexSandbox", "workspace-write"),
            "codexApprovalPolicy" to json.optString("codexApprovalPolicy", "on-request"),
            "codexPlanMode" to json.optBoolean("codexPlanMode", false),
            "pinned" to json.optBoolean("pinned", false),
            "archived" to json.optBoolean("archived", false),
            "entries" to entries,
        )
        if (json.has("titleIsManual")) {
            result["titleIsManual"] = json.optBoolean("titleIsManual", false)
        }
        if (json.has("title") && !json.isNull("title")) {
            val title = json.optString("title").trim()
            if (title.isNotEmpty()) result["title"] = title.take(MAX_TITLE_CHARS)
        }
        if (json.has("threadName") && !json.isNull("threadName")) {
            val threadName = json.optString("threadName").trim()
            if (threadName.isNotEmpty()) {
                result["threadName"] = threadName.take(MAX_TITLE_CHARS)
            }
        }
        if (sessionId.isNotEmpty()) result["sessionId"] = sessionId
        val authGeneration = json.optLong("authGeneration", 0L)
        if (authGeneration > 0L) result["authGeneration"] = authGeneration
        val queuedPromptsJson = json.optJSONArray("queuedPrompts") ?: JSONArray()
        val queuedPrompts = ArrayList<String>(queuedPromptsJson.length())
        for (index in 0 until queuedPromptsJson.length()) {
            val prompt = queuedPromptsJson.optString(index, "")
            if (prompt.isNotEmpty()) queuedPrompts.add(prompt)
        }
        result["queuedPrompts"] = queuedPrompts
        val promptHistoryJson = json.optJSONArray("promptHistory") ?: JSONArray()
        val promptHistory = ArrayList<String>(promptHistoryJson.length())
        for (index in 0 until promptHistoryJson.length()) {
            val prompt = promptHistoryJson.optString(index, "")
            if (prompt.isNotBlank()) promptHistory.add(prompt)
        }
        result["promptHistory"] = promptHistory
        if (json.has("threadId") && !json.isNull("threadId")) {
            result["threadId"] = json.optString("threadId")
        }
        return result
    }

    private fun writeAtomically(target: File, json: JSONObject) {
        val directory = target.parentFile
            ?: throw IllegalStateException("session history target has no parent")
        if (!directory.exists() && !directory.mkdirs()) {
            throw IllegalStateException("could not create session history directory")
        }
        val temporary = File(
            directory,
            ".${target.name}.tmp-${System.nanoTime()}",
        )
        try {
            temporary.writeText(json.toString(), StandardCharsets.UTF_8)
            try {
                Files.move(
                    temporary.toPath(),
                    target.toPath(),
                    StandardCopyOption.ATOMIC_MOVE,
                    StandardCopyOption.REPLACE_EXISTING,
                )
            } catch (_: AtomicMoveNotSupportedException) {
                Files.move(
                    temporary.toPath(),
                    target.toPath(),
                    StandardCopyOption.REPLACE_EXISTING,
                )
            }
        } catch (error: Exception) {
            temporary.delete()
            throw IllegalStateException("could not persist session history", error)
        }
    }

    private fun recordFile(key: String): File {
        require(key.isNotBlank()) { "session history key is required" }
        val digest = MessageDigest.getInstance("SHA-256")
            .digest(key.toByteArray(StandardCharsets.UTF_8))
            .joinToString("") { byte -> "%02x".format(byte) }
        return File(File(filesDir, "codex/session-history"), "$digest.json")
    }

    internal companion object {
        const val DEFAULT_CODEX_MODEL = "gpt-6-luna"
        const val DEFAULT_CODEX_EFFORT = "low"

        fun normalizeCodexModel(value: String?): String =
            normalizeCliSetting(value, DEFAULT_CODEX_MODEL)

        fun normalizeCodexEffort(value: String?): String =
            normalizeCliSetting(value, DEFAULT_CODEX_EFFORT)

        fun normalizeExecutionIdentity(value: String?): String =
            if (value == "root") "root" else "app"

        private fun normalizeCliSetting(value: String?, fallback: String): String {
            val normalized = value?.trim() ?: return fallback
            if (normalized.isEmpty() || normalized.length > MAX_SETTING_CHARS) return fallback
            if (normalized.any { Character.isISOControl(it) }) return fallback
            return normalized
        }

        const val MAX_ENTRIES = 500
        const val MAX_ENTRY_CHARS = 16 * 1024
        const val MAX_QUEUED_PROMPTS = 20
        const val MAX_PROMPT_HISTORY = 30
        const val MAX_DRAFT_CHARS = 16 * 1024
        const val MAX_SETTING_CHARS = 128
        const val MAX_TITLE_CHARS = 128
    }
}
