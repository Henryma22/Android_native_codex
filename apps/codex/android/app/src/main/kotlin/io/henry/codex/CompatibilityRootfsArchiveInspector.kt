package io.henry.codex

import java.io.ByteArrayOutputStream
import java.io.File
import java.io.InputStream
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.util.zip.GZIPInputStream

/** Checks the builder's tar safety contract before the archive reaches su. */
internal object CompatibilityRootfsArchiveInspector {
    data class Summary(val members: Int, val regularFiles: Int, val unpackedBytes: Long)

    fun inspect(
        archive: File,
        maxEntries: Int = CompatibilityRootfsManifest.MAX_ARCHIVE_ENTRIES,
        maxEntryBytes: Long = 512L * 1024L * 1024L,
        maxTotalBytes: Long = CompatibilityRootfsManifest.MAX_UNPACKED_BYTES,
    ): Summary {
        require(archive.isFile && !java.nio.file.Files.isSymbolicLink(archive.toPath())) {
            "Rootfs archive is not a regular file."
        }
        GZIPInputStream(archive.inputStream(), TAR_BLOCK_BYTES).use { input ->
            val paths = HashSet<String>()
            var members = 0
            var regularFiles = 0
            var unpackedBytes = 0L
            var headers = 0
            var pendingPax: Map<String, String>? = null
            while (true) {
                val header = ByteArray(TAR_BLOCK_BYTES)
                readFully(input, header)
                if (header.all { it == 0.toByte() }) {
                    val second = ByteArray(TAR_BLOCK_BYTES)
                    readFully(input, second)
                    require(second.all { it == 0.toByte() }) {
                        "Rootfs archive has an invalid end marker."
                    }
                    require(readZeroTail(input)) { "Rootfs archive has data after its end marker." }
                    break
                }
                headers += 1
                require(headers <= maxEntries * 2) { "Rootfs archive has too many headers." }
                require(headerChecksum(header)) { "Rootfs archive header checksum is invalid." }
                val rawPath = headerString(header, 0, 100)
                val prefix = headerString(header, 345, 155)
                val headerPath = if (prefix.isEmpty()) rawPath else "$prefix/$rawPath"
                val size = octal(header, 124, 12)
                val mode = octal(header, 100, 8)
                val type = header[156].toInt().toChar()
                require(size in 0..maxEntryBytes) { "Rootfs archive entry exceeds the size limit." }
                // Tar records symlink mode as 0777 by convention; those bits
                // belong to neither the link target nor the extracted target.
                require(type == '2' || (mode and (SET_UID or SET_GID or WORLD_WRITE)) == 0L) {
                    "Rootfs archive entry has set-id or world-writable permissions: " +
                        "$headerPath (mode ${mode.toString(8)})."
                }
                if (type == 'g') error("Rootfs archive global PAX headers are not allowed.")
                if (type == 'x') {
                    require(pendingPax == null) { "Rootfs archive has consecutive PAX headers." }
                    val paxBytes = readEntry(input, size, MAX_PAX_BYTES)
                    pendingPax = parsePax(paxBytes)
                    skipPadding(input, size)
                    continue
                }

                val pax = pendingPax.orEmpty()
                pendingPax = null
                val path = safePath(pax["path"] ?: headerPath)
                require(members < maxEntries) { "Rootfs archive has too many entries." }
                require(path == "." || paths.add(path)) {
                    "Rootfs archive contains a duplicate path: $path"
                }
                val link = pax["linkpath"] ?: headerString(header, 157, 100)
                when (type) {
                    '\u0000', '0', '5' -> Unit
                    '2' -> requireSafeLink(path, link)
                    '1' -> error("Rootfs archive hardlinks are not allowed.")
                    else -> error("Rootfs archive contains an unsupported special file.")
                }
                members += 1
                if (type == '\u0000' || type == '0') {
                    regularFiles += 1
                    unpackedBytes = Math.addExact(unpackedBytes, size)
                    require(unpackedBytes <= maxTotalBytes) {
                        "Rootfs archive exceeds the unpacked-size limit."
                    }
                }
                skipFully(input, size)
                skipPadding(input, size)
            }
            require(pendingPax == null) { "Rootfs archive ends after a PAX header." }
            return Summary(members, regularFiles, unpackedBytes)
        }
    }

    internal fun safePath(path: String): String {
        require(path.isNotEmpty() && !path.startsWith('/') && '\\' !in path && '\u0000' !in path) {
            "Rootfs archive contains an absolute or malformed path."
        }
        val normalized = path.split('/').filter { it.isNotEmpty() && it != "." }
        require(normalized.none { it == ".." }) {
            "Rootfs archive path escapes its root."
        }
        return normalized.joinToString("/").ifEmpty {
            require(path == "." || path == "./") { "Rootfs archive path is empty." }
            "."
        }
    }

    internal fun requireSafeLink(memberPath: String, target: String) {
        require(target.isNotEmpty() && '\u0000' !in target && '\\' !in target) {
            "Rootfs archive contains an invalid symbolic link."
        }
        val joined = if (target.startsWith('/')) {
            target.removePrefix("/")
        } else {
            val parent = memberPath.substringBeforeLast('/', "")
            if (parent.isEmpty()) target else "$parent/$target"
        }
        val normalized = mutableListOf<String>()
        joined.split('/').forEach { component ->
            when (component) {
                "", "." -> Unit
                ".." -> {
                    require(normalized.isNotEmpty()) {
                        "Rootfs symbolic link escapes the guest root."
                    }
                    normalized.removeAt(normalized.lastIndex)
                }
                else -> normalized += component
            }
        }
        require(normalized.isNotEmpty()) { "Rootfs symbolic link has an empty target." }
    }

    private fun parsePax(bytes: ByteArray): Map<String, String> {
        val attributes = linkedMapOf<String, String>()
        var cursor = 0
        while (cursor < bytes.size) {
            var space = cursor
            while (space < bytes.size && bytes[space] != ' '.code.toByte()) space += 1
            require(space > cursor) { "Rootfs PAX header is malformed." }
            val recordLength = String(
                bytes,
                cursor,
                space - cursor,
                Charsets.US_ASCII,
            ).toIntOrNull()
                ?: error("Rootfs PAX record length is invalid.")
            require(recordLength > space - cursor + 2 && cursor + recordLength <= bytes.size) {
                "Rootfs PAX record length is outside its header."
            }
            val recordEnd = cursor + recordLength
            require(bytes[recordEnd - 1] == '\n'.code.toByte()) {
                "Rootfs PAX record is not newline-terminated."
            }
            val record = decodeUtf8(bytes.copyOfRange(space + 1, recordEnd - 1))
            val separator = record.indexOf('=')
            require(separator > 0) { "Rootfs PAX attribute is malformed." }
            val key = record.substring(0, separator)
            val value = record.substring(separator + 1)
            require(key in ALLOWED_PAX_KEYS) { "Rootfs PAX attribute is unsupported: $key" }
            require(attributes.put(key, value) == null) { "Rootfs PAX attribute is duplicated." }
            cursor = recordEnd
        }
        return attributes
    }

    private fun readEntry(input: InputStream, size: Long, maxBytes: Long): ByteArray {
        require(size in 1..maxBytes) { "Rootfs PAX header exceeds the size limit." }
        val output = ByteArrayOutputStream(size.toInt())
        val buffer = ByteArray(TAR_BLOCK_BYTES)
        var remaining = size
        while (remaining > 0) {
            val requested = minOf(buffer.size.toLong(), remaining).toInt()
            val count = input.read(buffer, 0, requested)
            require(count > 0) { "Rootfs archive is truncated." }
            output.write(buffer, 0, count)
            remaining -= count
        }
        return output.toByteArray()
    }

    private fun readFully(input: InputStream, buffer: ByteArray) {
        var offset = 0
        while (offset < buffer.size) {
            val count = input.read(buffer, offset, buffer.size - offset)
            require(count > 0) { "Rootfs archive ended unexpectedly." }
            offset += count
        }
    }

    private fun skipFully(input: InputStream, length: Long) {
        var remaining = length
        val buffer = ByteArray(TAR_BLOCK_BYTES)
        while (remaining > 0) {
            val skipped = input.skip(remaining)
            if (skipped > 0) {
                remaining -= skipped
            } else {
                val count = input.read(buffer, 0, minOf(buffer.size.toLong(), remaining).toInt())
                require(count > 0) { "Rootfs archive entry is truncated." }
                remaining -= count
            }
        }
    }

    private fun skipPadding(input: InputStream, length: Long) {
        val padding = (TAR_BLOCK_BYTES - (length % TAR_BLOCK_BYTES)) % TAR_BLOCK_BYTES
        skipFully(input, padding)
    }

    private fun readZeroTail(input: InputStream): Boolean {
        val buffer = ByteArray(8192)
        var total = 0
        while (true) {
            val count = input.read(buffer)
            if (count < 0) return true
            total += count
            if (total > MAX_TRAILING_ZERO_BYTES || buffer.take(count).any { it != 0.toByte() }) {
                return false
            }
        }
    }

    private fun headerString(header: ByteArray, offset: Int, length: Int): String {
        var end = offset
        while (end < offset + length && header[end] != 0.toByte()) end += 1
        return decodeUtf8(header.copyOfRange(offset, end))
    }

    private fun decodeUtf8(bytes: ByteArray): String = ByteBuffer.wrap(bytes)
        .let { buffer ->
            java.nio.charset.StandardCharsets.UTF_8.newDecoder()
                .onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
                .decode(buffer)
                .toString()
        }

    private fun octal(header: ByteArray, offset: Int, length: Int): Long {
        var start = offset
        var end = offset + length
        while (start < end && (header[start] == 0.toByte() || header[start] == ' '.code.toByte())) start += 1
        while (end > start && (header[end - 1] == 0.toByte() || header[end - 1] == ' '.code.toByte())) end -= 1
        if (start == end) return 0
        var value = 0L
        for (index in start until end) {
            val digit = header[index].toInt() - '0'.code
            require(digit in 0..7) { "Rootfs archive contains a non-octal tar field." }
            value = Math.addExact(Math.multiplyExact(value, 8L), digit.toLong())
        }
        return value
    }

    private fun headerChecksum(header: ByteArray): Boolean {
        val expected = runCatching { octal(header, CHECKSUM_OFFSET, CHECKSUM_LENGTH) }
            .getOrNull() ?: return false
        val unsigned = header.sumOfIndexed { index, byte ->
            if (index in CHECKSUM_OFFSET until CHECKSUM_OFFSET + CHECKSUM_LENGTH) {
                ' '.code
            } else {
                byte.toInt() and 0xff
            }
        }
        return unsigned == expected
    }

    private inline fun ByteArray.sumOfIndexed(value: (Int, Byte) -> Int): Long {
        var total = 0L
        forEachIndexed { index, byte -> total += value(index, byte) }
        return total
    }

    private const val TAR_BLOCK_BYTES = 512
    private const val CHECKSUM_OFFSET = 148
    private const val CHECKSUM_LENGTH = 8
    private const val SET_UID = 0x800L
    private const val SET_GID = 0x400L
    private const val WORLD_WRITE = 0x002L
    private const val MAX_PAX_BYTES = 1024L * 1024L
    private const val MAX_TRAILING_ZERO_BYTES = 1024 * 1024
    // Debian's reproducible rootfs tar can carry atime/ctime metadata. These
    // timestamps do not affect extraction paths or permissions, so accept and
    // ignore them while continuing to reject unknown PAX directives.
    private val ALLOWED_PAX_KEYS = setOf("path", "linkpath", "mtime", "atime", "ctime")
}
