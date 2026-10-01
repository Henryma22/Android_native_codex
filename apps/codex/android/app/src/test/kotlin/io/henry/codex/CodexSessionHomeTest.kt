package io.henry.codex

import java.io.File
import java.nio.file.Files
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CodexSessionHomeTest {
    @Test
    fun `seeds compatibility session homes without overwriting existing guidance`() {
        val baseHome = Files.createTempDirectory("codex-session-home").toFile()
        try {
            val instructions = "# Android runtime instructions\n"
            val direct = File(File(baseHome, "sessions"), "direct-session")
            CodexSessionHome.prepareCompatibility(
                baseHome,
                "/home/codex/sessions/direct-session",
                instructions = instructions,
            )
            assertEquals(instructions, File(direct, "AGENTS.md").readText())

            val compatibility = File(File(baseHome, "sessions"), "compat-session")
            CodexSessionHome.prepareCompatibility(
                baseHome,
                "/home/codex/sessions/compat-session",
                instructions = instructions,
            )
            assertEquals(instructions, File(compatibility, "AGENTS.md").readText())
            assertEquals(
                File(compatibility, "models_cache.json"),
                CodexSessionHome.compatibilityModelsCachePath(
                    baseHome,
                    "/home/codex/sessions/compat-session",
                ),
            )

            val custom = File(File(baseHome, "sessions"), "custom-session")
            assertTrue(custom.mkdirs())
            val customInstructions = "# User-authored session guidance\n"
            File(custom, "AGENTS.md").writeText(customInstructions)
            CodexSessionHome.prepareCompatibility(
                baseHome,
                "/home/codex/sessions/custom-session",
                instructions = instructions,
            )
            assertEquals(customInstructions, File(custom, "AGENTS.md").readText())
            assertFalse(File(baseHome, "AGENTS.md").exists())
        } finally {
            baseHome.walkBottomUp().forEach { it.delete() }
        }
    }

    @Test
    fun `seeds login files from the default codex directory`() {
        val baseHome = Files.createTempDirectory("codex-session-login").toFile()
        try {
            val sharedCodex = File(baseHome, ".codex")
            assertTrue(sharedCodex.mkdirs())
            File(sharedCodex, "auth.json").writeText("{\"auth\":true}")
            File(sharedCodex, "config.toml").writeText("model = \"gpt-5.6-luna\"\n")

            val session = File(File(baseHome, "sessions"), "root-session")
            CodexSessionHome.prepareCompatibility(
                baseHome,
                "/home/codex/sessions/root-session",
            )

            assertEquals("{\"auth\":true}", File(session, "auth.json").readText())
            assertEquals(
                "model = \"gpt-5.6-luna\"\n",
                File(session, "config.toml").readText(),
            )
        } finally {
            baseHome.walkBottomUp().forEach { it.delete() }
        }
    }

    @Test
    fun `writes per-session custom model catalog and removes its transport variable`() {
        val baseHome = Files.createTempDirectory("codex-session-catalog").toFile()
        try {
            val session = File(File(baseHome, "sessions"), "provider-session")
            val catalog = """{"models":[{"slug":"deepseek-flash"}]}"""
            val environment = mapOf(
                CodexSessionHome.MODEL_CATALOG_ENVIRONMENT_VARIABLE to catalog,
                "ANDROID_CODEX_CUSTOM_PROVIDER_API_KEY" to "session-secret",
                "CODEX_HOME" to "/home/codex/sessions/provider-session",
            )

            CodexSessionHome.prepareCompatibility(
                baseHome,
                "/home/codex/sessions/provider-session",
                customModelCatalogJson =
                    CodexSessionHome.modelCatalogFromEnvironment(environment),
            )

            assertEquals(catalog, File(session, "models.json").readText())
            assertEquals(
                mapOf(
                    "ANDROID_CODEX_CUSTOM_PROVIDER_API_KEY" to "session-secret",
                    "CODEX_HOME" to "/home/codex/sessions/provider-session",
                ),
                CodexSessionHome.childEnvironment(environment),
            )
            assertTrue(
                CodexSessionHome.MODEL_CATALOG_ENVIRONMENT_VARIABLE !in
                    CodexSessionHome.childEnvironment(environment),
            )
        } finally {
            baseHome.walkBottomUp().forEach { it.delete() }
        }
    }

    @Test
    fun `rejects malformed custom model catalog without replacing an existing one`() {
        val baseHome = Files.createTempDirectory("codex-session-bad-catalog").toFile()
        try {
            val session = File(File(baseHome, "sessions"), "provider-session")
            CodexSessionHome.prepareCompatibility(
                baseHome,
                "/home/codex/sessions/provider-session",
                customModelCatalogJson =
                    """{"models":[{"slug":"deepseek-flash"}]}""",
            )
            val destination = File(session, "models.json")
            val original = destination.readText()

            try {
                CodexSessionHome.prepareCompatibility(
                    baseHome,
                    "/home/codex/sessions/provider-session",
                    customModelCatalogJson = "not-json",
                )
                throw AssertionError("Malformed model catalog should be rejected")
            } catch (_: IllegalArgumentException) {
                assertEquals(original, destination.readText())
            }
        } finally {
            baseHome.walkBottomUp().forEach { it.delete() }
        }
    }

    @Test
    fun `root sessions inherit the shared model cache without overwriting it`() {
        val baseHome = Files.createTempDirectory("codex-session-models").toFile()
        try {
            val sharedCodex = File(baseHome, ".codex")
            assertTrue(sharedCodex.mkdirs())
            val sharedCache = File(sharedCodex, "models_cache.json")
            sharedCache.writeText("{\"models\":[{\"id\":\"gpt-6-luna\"}]}")

            val session = File(File(baseHome, "sessions"), "root-session")
            CodexSessionHome.prepareCompatibility(
                baseHome,
                "/home/codex/sessions/root-session",
                preserveModelsCache = true,
            )
            assertEquals(sharedCache.readText(), File(session, "models_cache.json").readText())

            File(session, "models_cache.json").writeText("newer cache")
            CodexSessionHome.prepareCompatibility(
                baseHome,
                "/home/codex/sessions/root-session",
                preserveModelsCache = true,
            )
            assertEquals("newer cache", File(session, "models_cache.json").readText())
        } finally {
            baseHome.walkBottomUp().forEach { it.delete() }
        }
    }

    @Test
    fun `missing or app-removable models cache never needs privileged cleanup`() {
        val home = Files.createTempDirectory("codex-models-cache").toFile()
        try {
            val cache = File(home, "models_cache.json")
            assertTrue(CodexSessionHome.tryRemoveModelsCacheAsApp(cache))
            assertTrue(home.isDirectory)

            cache.writeText("derived cache")
            assertTrue(CodexSessionHome.tryRemoveModelsCacheAsApp(cache))
            assertFalse(cache.exists())
        } finally {
            home.walkBottomUp().forEach { it.delete() }
        }
    }
}
