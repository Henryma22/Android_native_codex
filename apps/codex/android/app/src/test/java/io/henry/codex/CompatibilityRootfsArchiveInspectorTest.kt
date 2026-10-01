package io.henry.codex

import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileInputStream
import java.security.MessageDigest
import java.util.zip.GZIPOutputStream
import org.junit.Assume.assumeTrue
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class CompatibilityRootfsArchiveInspectorTest {
    @Test
    fun acceptsSafeRegularFileAndInternalAbsoluteLink() {
        val archive = archive(
            entry(".", '5'),
            entry("usr/bin/true", '0', content = byteArrayOf(1, 2, 3)),
            entry("usr/bin/sh", '2', link = "/bin/dash", mode = 0b111_111_111),
            entry("bin/dash", '0'),
        )

        val result = CompatibilityRootfsArchiveInspector.inspect(archive)

        assertEquals(4, result.members)
        assertEquals(2, result.regularFiles)
        assertEquals(3L, result.unpackedBytes)
    }

    @Test
    fun rejectsTraversalSpecialAndUnsafeSymlinkEntries() {
        assertTrue(runCatching {
            CompatibilityRootfsArchiveInspector.safePath("../../outside")
        }.isFailure)
        assertTrue(runCatching {
            CompatibilityRootfsArchiveInspector.requireSafeLink("etc/escape", "../../../data")
        }.isFailure)
        assertTrue(runCatching {
            CompatibilityRootfsArchiveInspector.inspect(archive(entry("dev/mem", '3')))
        }.isFailure)
        assertTrue(runCatching {
            CompatibilityRootfsArchiveInspector.inspect(
                archive(
                    entry(
                        "PaxHeaders/file",
                        'x',
                        content = paxRecord("SCHILY.xattr.security.capability", "cap_net_raw+ep"),
                    ),
                    entry("usr/bin/ping", '0'),
                ),
            )
        }.isFailure)
    }

    @Test
    fun readsUtf8PathFromPosixPaxHeader() {
        val path = "usr/share/doc/café"
        val pax = paxRecord("path", path)
        val summary = CompatibilityRootfsArchiveInspector.inspect(
            archive(
                entry("PaxHeaders/file", 'x', content = pax),
                entry("placeholder", '0', content = byteArrayOf(1)),
            ),
        )

        assertEquals(1, summary.members)
        assertEquals(1, summary.regularFiles)
        assertEquals(1L, summary.unpackedBytes)
    }

    @Test
    fun acceptsStandardPaxAccessAndChangeTimestamps() {
        val summary = CompatibilityRootfsArchiveInspector.inspect(
            archive(
                entry(
                    "PaxHeaders/file",
                    'x',
                    content = paxRecord("atime", "1780000000.25") +
                        paxRecord("ctime", "1780000000.5"),
                ),
                entry("usr/bin/true", '0'),
            ),
        )

        assertEquals(1, summary.members)
        assertEquals(1, summary.regularFiles)
    }

    @Test
    fun generatedArtifactPassesTheAppImportContractWhenPathsAreProvided() {
        val archivePath = System.getenv("CODEX_ROOTFS_TEST_ARCHIVE")
        val manifestPath = System.getenv("CODEX_ROOTFS_TEST_MANIFEST")
        assumeTrue(
            "Set CODEX_ROOTFS_TEST_ARCHIVE and CODEX_ROOTFS_TEST_MANIFEST to check a built artifact.",
            !archivePath.isNullOrBlank() && !manifestPath.isNullOrBlank(),
        )

        val archive = File(requireNotNull(archivePath))
        val manifestJson = File(requireNotNull(manifestPath)).readText(Charsets.UTF_8)
        val digest = sha256(archive)
        val manifest = CompatibilityRootfsManifest.parse(
            jsonText = manifestJson,
            selectedArchiveName = archive.name,
            actualArchiveBytes = archive.length(),
            actualArchiveSha256 = digest,
        )

        val summary = CompatibilityRootfsArchiveInspector.inspect(archive)

        assertEquals(manifest.memberCount, summary.members)
        assertEquals(manifest.regularFileCount, summary.regularFiles)
        assertEquals(manifest.unpackedBytes, summary.unpackedBytes)
    }

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        FileInputStream(file).use { input ->
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    private fun archive(vararg entries: ByteArray): File {
        val file = File.createTempFile("codex-rootfs-", ".tar.gz")
        file.deleteOnExit()
        val tar = ByteArrayOutputStream()
        entries.forEach(tar::write)
        tar.write(ByteArray(1024))
        GZIPOutputStream(file.outputStream()).use { it.write(tar.toByteArray()) }
        return file
    }

    private fun entry(
        name: String,
        type: Char,
        content: ByteArray = byteArrayOf(),
        link: String = "",
        mode: Int = 0b110_100_100,
    ): ByteArray {
        val header = ByteArray(512)
        put(header, 0, 100, name)
        put(header, 100, 8, "%06o\u0000 ".format(mode))
        put(header, 108, 8, "%06o\u0000 ".format(0))
        put(header, 116, 8, "%06o\u0000 ".format(0))
        put(header, 124, 12, "%011o\u0000".format(content.size))
        put(header, 136, 12, "%011o\u0000".format(0))
        header.fill(' '.code.toByte(), 148, 156)
        header[156] = type.code.toByte()
        put(header, 157, 100, link)
        put(header, 257, 6, "ustar\u0000")
        put(header, 263, 2, "00")
        val checksum = header.sumOf { it.toInt() and 0xff }
        put(header, 148, 8, "%06o\u0000 ".format(checksum))
        val padded = ByteArray(((content.size + 511) / 512) * 512)
        content.copyInto(padded)
        return header + padded
    }

    private fun put(target: ByteArray, offset: Int, width: Int, value: String) {
        val bytes = value.toByteArray(Charsets.UTF_8)
        require(bytes.size <= width)
        bytes.copyInto(target, offset)
    }

    private fun paxRecord(key: String, value: String): ByteArray {
        val payload = "$key=$value\n"
        var length = payload.toByteArray(Charsets.UTF_8).size + 2
        while (true) {
            val record = "$length $payload".toByteArray(Charsets.UTF_8)
            if (record.size == length) return record
            length = record.size
        }
    }
}
