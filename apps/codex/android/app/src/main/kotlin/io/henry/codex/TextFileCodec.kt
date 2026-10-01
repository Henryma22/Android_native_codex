package io.henry.codex

import java.nio.ByteBuffer
import java.nio.charset.CharacterCodingException
import java.nio.charset.CodingErrorAction
import java.nio.charset.StandardCharsets

/**
 * Keeps managed file changes strictly text-only.
 *
 * Android's String(byte[], UTF_8) replaces malformed bytes silently. That is
 * unsafe for a managed editor because a binary file could be previewed and
 * written back with different bytes. Decode with REPORT and reject NUL bytes
 * before a file reaches the Flutter change-set boundary.
 */
internal object TextFileCodec {
    fun decode(bytes: ByteArray, maxBytes: Int, label: String): String {
        if (bytes.size > maxBytes) {
            throw TextFileException("too_large", "$label exceeds 1 MiB")
        }
        if (bytes.any { it == 0.toByte() }) {
            throw TextFileException("binary", "$label is not a text file")
        }
        return try {
            val decoder = StandardCharsets.UTF_8.newDecoder()
                .onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
            decoder.decode(ByteBuffer.wrap(bytes)).toString()
        } catch (_: CharacterCodingException) {
            throw TextFileException("binary", "$label is not valid UTF-8 text")
        }
    }

    fun validateText(value: String, maxBytes: Int, label: String): ByteArray {
        if (value.indexOf('\u0000') >= 0) {
            throw TextFileException("binary", "$label contains a NUL byte")
        }
        val bytes = value.toByteArray(StandardCharsets.UTF_8)
        if (bytes.size > maxBytes) {
            throw TextFileException("too_large", "$label exceeds 1 MiB")
        }
        return bytes
    }
}

internal class TextFileException(
    val code: String,
    override val message: String,
) : RuntimeException(message)
