package io.henry.codex

import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.CharBuffer
import java.nio.charset.CharacterCodingException
import java.nio.charset.CodingErrorAction
import java.nio.charset.StandardCharsets

/**
 * Decodes process output without losing UTF-8 code points split across reads.
 *
 * A Process InputStream is byte-oriented. Decoding each read independently can
 * turn a multi-byte character at a read boundary into replacement characters,
 * which is especially visible in Local Session transcript output.
 */
internal class Utf8StreamDecoder {
    private val decoder = StandardCharsets.UTF_8.newDecoder()
        .onMalformedInput(CodingErrorAction.REPORT)
        .onUnmappableCharacter(CodingErrorAction.REPORT)
    private val pending = ByteArrayOutputStream()

    @Throws(CharacterCodingException::class)
    fun decode(bytes: ByteArray, offset: Int, length: Int): String {
        require(offset >= 0 && length >= 0 && offset + length <= bytes.size) {
            "invalid byte range"
        }
        if (length > 0) pending.write(bytes, offset, length)
        val input = ByteBuffer.wrap(pending.toByteArray())
        val output = CharBuffer.allocate(maxOf(16, input.remaining() + 1))
        val result = decoder.decode(input, output, false)
        result.throwExceptionIfNeeded()
        replacePending(input)
        output.flip()
        return output.toString()
    }

    @Throws(CharacterCodingException::class)
    fun finish(): String {
        val input = ByteBuffer.wrap(pending.toByteArray())
        val output = CharBuffer.allocate(maxOf(16, input.remaining() + 1))
        val result = decoder.decode(input, output, true)
        result.throwExceptionIfNeeded()
        decoder.flush(output).throwExceptionIfNeeded()
        replacePending(input)
        output.flip()
        return output.toString()
    }

    private fun replacePending(input: ByteBuffer) {
        pending.reset()
        if (input.hasRemaining()) {
            pending.write(input.array(), input.arrayOffset() + input.position(), input.remaining())
        }
    }

    private fun java.nio.charset.CoderResult.throwExceptionIfNeeded() {
        if (isError) throwException()
    }
}
