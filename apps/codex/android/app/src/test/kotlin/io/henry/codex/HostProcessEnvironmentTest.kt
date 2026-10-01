package io.henry.codex

import java.io.File
import java.nio.file.Files
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HostProcessEnvironmentTest {
    @Test
    fun `host commands receive writable home and temp defaults`() {
        val baseHome = Files.createTempDirectory("codex-host-environment").toFile()
        try {
            val environment = completeHostCommandEnvironment(
                emptyMap(),
                baseHome,
            )
            val home = File(environment.getValue("HOME"))
            val temp = File(environment.getValue("TMPDIR"))

            assertEquals(home.absolutePath, File(environment.getValue("HOME")).absolutePath)
            assertEquals(temp.absolutePath, File(environment.getValue("TMP")).absolutePath)
            assertEquals(temp.absolutePath, File(environment.getValue("TEMP")).absolutePath)
            assertTrue(home.isDirectory)
            assertTrue(temp.isDirectory)
        } finally {
            baseHome.walkBottomUp().forEach { it.delete() }
        }
    }

    @Test
    fun `explicit command environment remains authoritative`() {
        val baseHome = Files.createTempDirectory("codex-host-environment-explicit").toFile()
        try {
            val explicitHome = File(baseHome, "explicit-home")
            val explicitTemp = File(baseHome, "explicit-temp")
            val environment = completeHostCommandEnvironment(
                mapOf(
                    "HOME" to explicitHome.absolutePath,
                    "TMPDIR" to explicitTemp.absolutePath,
                ),
                baseHome,
            )

            assertEquals(explicitHome.absolutePath, environment.getValue("HOME"))
            assertEquals(explicitTemp.absolutePath, environment.getValue("TMPDIR"))
            assertTrue(environment.containsKey("TMP"))
            assertTrue(environment.containsKey("TEMP"))
        } finally {
            baseHome.walkBottomUp().forEach { it.delete() }
        }
    }
}
