package io.henry.codex

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class CompatibilityRootfsManifestTest {
    @Test
    fun parsesVerifiedArm64RootfsManifestAndBuildsRuntimeMarker() {
        val manifest = CompatibilityRootfsManifest.parse(
            jsonText = fixtureManifest(),
            selectedArchiveName = "codex-rootfs-bookworm.tar.gz",
            actualArchiveBytes = 7,
            actualArchiveSha256 = DIGEST,
        )

        assertEquals(
            "debian-bookworm-node-24.19.0-codex-0.157.1-linux-arm64",
            manifest.runtimeVersion,
        )
        assertEquals("24.19.0", manifest.nodeVersion)
        assertEquals("0.157.1-linux-arm64", manifest.codexVersion)
        assertTrue(manifest.runtimeMarkerJson().contains("\"verificationMode\":\"finalized-proot\""))
        assertTrue(manifest.runtimeMarkerJson().contains("\"rootfsDigest\":\"$DIGEST\""))
    }

    @Test
    fun rejectsArchiveDigestMismatch() {
        val error = runCatching {
            CompatibilityRootfsManifest.parse(
                jsonText = fixtureManifest(),
                selectedArchiveName = "codex-rootfs-bookworm.tar.gz",
                actualArchiveBytes = 7,
                actualArchiveSha256 = "b".repeat(64),
            )
        }.exceptionOrNull()

        assertTrue(error?.message?.contains("SHA-256") == true)
    }

    @Test
    fun rejectsWrongAbiAndArchiveName() {
        val wrongAbi = fixtureManifest().replace("arm64-v8a", "armeabi-v7a")
        assertTrue(runCatching {
            CompatibilityRootfsManifest.parse(
                wrongAbi,
                "codex-rootfs-bookworm.tar.gz",
                7,
                DIGEST,
            )
        }.isFailure)

        assertTrue(runCatching {
            CompatibilityRootfsManifest.parse(
                fixtureManifest(),
                "another-rootfs.tar.gz",
                7,
                DIGEST,
            )
        }.isFailure)
    }

    private fun fixtureManifest(): String = """
        {
          "schema": {"name":"codex-android-local-rootfs","version":1},
          "artifact": {"filename":"codex-rootfs-bookworm.tar.gz","format":"tar.gz","sha256":"$DIGEST","bytes":7,"members":10,"regular_files":8,"unpacked_bytes":1024},
          "target": {"os":"linux","arch":"arm64","android_abi":"arm64-v8a"},
          "debian": {"suite":"bookworm"},
          "components": {
            "node": {"version":"24.19.0"},
            "codex": {"resolved_version":"0.157.1-linux-arm64"}
          },
          "device_finalize": {"script":"device/proot-finalize-rootfs.sh","second_stage":"/debootstrap/debootstrap --second-stage"},
          "security": {
            "archive_check":"archive_safety.py",
            "rejected":["absolute-or-traversal-paths","special-files","setuid-setgid","capability-xattrs","world-writable"]
          }
        }
    """.trimIndent()

    private companion object {
        const val DIGEST = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    }
}
