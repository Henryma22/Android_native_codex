package io.henry.codex

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test
import java.nio.file.Files

class SessionHistoryStoreTest {
    @Test
    fun preservesCliProvidedModelAndEffortChoices() {
        assertEquals("gpt-6-sol", SessionHistoryStore.normalizeCodexModel("gpt-6-sol"))
        assertEquals("custom-future-model", SessionHistoryStore.normalizeCodexModel("custom-future-model"))
        assertEquals("xhigh", SessionHistoryStore.normalizeCodexEffort("xhigh"))
        assertEquals("ultra", SessionHistoryStore.normalizeCodexEffort("ultra"))
        assertEquals("gpt-6-luna", SessionHistoryStore.normalizeCodexModel("\n"))
        assertEquals("low", SessionHistoryStore.normalizeCodexEffort(null))
        assertEquals("root", SessionHistoryStore.normalizeExecutionIdentity("root"))
        assertEquals("app", SessionHistoryStore.normalizeExecutionIdentity("unknown"))
    }

    @Test
    fun persistsIdentityAndRootApprovalWithItsSessionRecord() {
        val root = Files.createTempDirectory("codex-session-root-grant").toFile()
        try {
            val store = SessionHistoryStore(root)
            val key = "local-android|/workspace/demo|session:one"
            store.save(
                key,
                mapOf(
                    "backendId" to "local-android",
                    "workspacePath" to "/workspace/demo",
                    "sessionId" to "one",
                    "status" to "stopped",
                    "updatedAtEpochMs" to 1L,
                    "executionIdentity" to "root",
                    "rootApprovalGranted" to true,
                    "entries" to emptyList<String>(),
                ),
            )

            val row = store.load(key)!!
            assertEquals("root", row["executionIdentity"])
            assertEquals(true, row["rootApprovalGranted"])

            val legacyKey = "local-android|/workspace/demo"
            store.save(
                legacyKey,
                mapOf(
                    "backendId" to "local-android",
                    "workspacePath" to "/workspace/demo",
                    "executionIdentity" to "root",
                    "rootApprovalGranted" to true,
                    "entries" to emptyList<String>(),
                ),
            )
            assertEquals(false, store.load(legacyKey)!!["rootApprovalGranted"])
        } finally {
            root.deleteRecursively()
        }
    }

    @Test
    fun keepsMultipleSessionRowsForOneWorkspaceWithoutOverwriting() {
        val root = Files.createTempDirectory("codex-session-history").toFile()
        try {
            val store = SessionHistoryStore(root)
            val workspaceKey = "local-android|/workspace/demo"
            store.save(
                "$workspaceKey|session:first",
                mapOf(
                    "backendId" to "local-android",
                    "workspacePath" to "/workspace/demo",
                    "sessionId" to "first",
                    "status" to "stopped",
                    "updatedAtEpochMs" to 200L,
                    "codexModel" to "gpt-6-luna",
                    "codexEffort" to "high",
                    "entries" to listOf("You: first"),
                ),
            )
            store.save(
                "$workspaceKey|session:second",
                mapOf(
                    "backendId" to "local-android",
                    "workspacePath" to "/workspace/demo",
                    "sessionId" to "second",
                    "status" to "stopped",
                    "updatedAtEpochMs" to 100L,
                    "entries" to listOf("You: second"),
                ),
            )

            val rows = store.list()
            assertEquals(2, rows.size)
            assertEquals(
                listOf("first", "second"),
                rows.mapNotNull { it["sessionId"] as? String },
            )
            assertEquals("gpt-6-luna", rows.first()["codexModel"])
            assertEquals("high", rows.first()["codexEffort"])
        } finally {
            root.deleteRecursively()
        }
    }

    @Test
    fun persistsCodexThreadNameAndManualRenameState() {
        val root = Files.createTempDirectory("codex-session-title").toFile()
        try {
            val store = SessionHistoryStore(root)
            val key = "local-android|/workspace/demo|session:one"
            store.save(
                key,
                mapOf(
                    "backendId" to "local-android",
                    "workspacePath" to "/workspace/demo",
                    "sessionId" to "one",
                    "status" to "stopped",
                    "updatedAtEpochMs" to 1L,
                    "title" to "Codex generated task",
                    "threadName" to "Codex generated task",
                    "titleIsManual" to false,
                    "entries" to emptyList<String>(),
                ),
            )

            val generated = store.load(key)!!
            assertEquals("Codex generated task", generated["threadName"])
            assertEquals(false, generated["titleIsManual"])

            store.updateTitle(key, "My session")
            val manual = store.load(key)!!
            assertEquals("My session", manual["title"])
            assertEquals(true, manual["titleIsManual"])
            assertEquals("Codex generated task", manual["threadName"])

            store.updateTitle(key, null)
            val restored = store.load(key)!!
            assertEquals(false, restored["titleIsManual"])
            assertEquals(false, restored.containsKey("title"))
            assertEquals("Codex generated task", restored["threadName"])
        } finally {
            root.deleteRecursively()
        }
    }

    @Test
    fun legacyArchivedRowsAreRemovedWhenTheHistoryIndexIsRead() {
        val root = Files.createTempDirectory("codex-archived-history").toFile()
        try {
            val store = SessionHistoryStore(root)
            store.save(
                "local-android|/workspace/demo|session:archived",
                mapOf(
                    "backendId" to "local-android",
                    "workspacePath" to "/workspace/demo",
                    "sessionId" to "archived",
                    "status" to "stopped",
                    "updatedAtEpochMs" to 200L,
                    "entries" to listOf("You: old"),
                ),
            )
            val row = root.resolve("codex/session-history").listFiles()!!.single()
            assertFalse(JSONObject(row.readText()).has("archived"))
            row.writeText(JSONObject(row.readText()).put("archived", true).toString())

            assertEquals(0, store.list().size)
            assertFalse(row.exists())
        } finally {
            root.deleteRecursively()
        }
    }
}
