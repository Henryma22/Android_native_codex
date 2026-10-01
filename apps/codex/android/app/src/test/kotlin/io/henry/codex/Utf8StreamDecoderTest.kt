package io.henry.codex

import java.nio.charset.CharacterCodingException
import java.nio.charset.StandardCharsets
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class Utf8StreamDecoderTest {
    @Test
    fun preservesCodePointSplitAcrossProcessReads() {
        val bytes = "prefix 中文 suffix\n".toByteArray(StandardCharsets.UTF_8)
        val decoder = Utf8StreamDecoder()
        val first = decoder.decode(bytes, 0, 8)
        val second = decoder.decode(bytes, 8, bytes.size - 8)

        assertEquals("prefix ", first)
        assertEquals("中文 suffix\n", second + decoder.finish())
    }

    @Test
    fun reportsMalformedOutputAtEndOfProcess() {
        val decoder = Utf8StreamDecoder()
        decoder.decode(byteArrayOf(0xC3.toByte()), 0, 1)

        assertThrows(CharacterCodingException::class.java) {
            decoder.finish()
        }
    }
}
