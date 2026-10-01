package io.henry.codex

import java.nio.charset.StandardCharsets
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class TextFileCodecTest {
    @Test
    fun decodesUtf8TextWithoutChangingBytes() {
        val bytes = "中文\nplain".toByteArray(StandardCharsets.UTF_8)

        assertEquals("中文\nplain", TextFileCodec.decode(bytes, 1024, "fixture"))
    }

    @Test
    fun rejectsNulBinaryContent() {
        val error = assertThrows(TextFileException::class.java) {
            TextFileCodec.decode(byteArrayOf(0x41, 0x00, 0x42), 1024, "fixture")
        }

        assertEquals("binary", error.code)
    }

    @Test
    fun rejectsMalformedUtf8InsteadOfReplacingBytes() {
        val error = assertThrows(TextFileException::class.java) {
            TextFileCodec.decode(byteArrayOf(0xC3.toByte(), 0x28), 1024, "fixture")
        }

        assertEquals("binary", error.code)
    }

    @Test
    fun rejectsOversizedText() {
        val error = assertThrows(TextFileException::class.java) {
            TextFileCodec.decode(byteArrayOf(0x41, 0x42), 1, "fixture")
        }

        assertEquals("too_large", error.code)
    }

    @Test
    fun validatesWritesAndReturnsExactUtf8Bytes() {
        val content = "safe\n中文"

        assertArrayEquals(
            content.toByteArray(StandardCharsets.UTF_8),
            TextFileCodec.validateText(content, 1024, "fixture"),
        )
    }

    @Test
    fun rejectsNulWrites() {
        val error = assertThrows(TextFileException::class.java) {
            TextFileCodec.validateText("safe\u0000", 1024, "fixture")
        }

        assertEquals("binary", error.code)
    }
}
