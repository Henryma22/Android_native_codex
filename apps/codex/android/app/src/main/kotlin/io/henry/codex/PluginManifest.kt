package io.henry.codex

import java.nio.ByteBuffer
import java.nio.charset.CharacterCodingException
import java.nio.charset.CodingErrorAction
import java.nio.charset.StandardCharsets

/**
 * The risk levels understood by the Android broker.  The ordinal is
 * deliberately not used for policy decisions; [rank] is the stable ordering
 * used when combining independently observed archive properties.
 */
internal enum class PluginRisk(val wireName: String, val rank: Int) {
    R0("R0", 0),
    R1("R1", 1),
    R2("R2", 2),
    R3("R3", 3),
    R4("R4", 4),
    ;

    companion object {
        fun parse(value: String): PluginRisk =
            entries.firstOrNull { it.wireName == value }
                ?: throw PluginBrokerException(PluginBrokerErrorCode.MANIFEST_INVALID)
    }
}

/**
 * A module ID after the namespace and character policy have been checked.
 * There is intentionally no public constructor: a ksud runner cannot receive
 * an arbitrary string that came from Dart.
 */
@JvmInline
internal value class VerifiedPluginModuleId private constructor(val value: String) {
    companion object {
        private const val PREFIX = "ccpocket.plugin."
        private const val MAX_LENGTH = 64

        fun parse(value: String): VerifiedPluginModuleId {
            if (!isValid(value)) {
                throw PluginBrokerException(PluginBrokerErrorCode.INVALID_MODULE_ID)
            }
            return VerifiedPluginModuleId(value)
        }

        fun from(value: String): VerifiedPluginModuleId = parse(value)

        fun isValid(value: String): Boolean {
            if (value.length <= PREFIX.length || value.length > MAX_LENGTH) return false
            if (!value.startsWith(PREFIX)) return false

            val suffix = value.removePrefix(PREFIX)
            if (suffix.startsWith('.') || suffix.endsWith('.') || suffix.contains("..")) {
                return false
            }
            return suffix.all { character ->
                character in 'a'..'z' ||
                    character in '0'..'9' ||
                    character == '.' ||
                    character == '_' ||
                    character == '-'
            }
        }
    }
}

/**
 * The only JSON shape accepted inside a broker module.  Keeping this model
 * separate from the archive validator makes it possible to test manifest
 * parsing without creating a ZIP, while the validator still owns all
 * archive-dependent decisions.
 */
internal data class PluginManifest(
    val schemaVersion: Int,
    val id: String,
    val name: String,
    val version: String,
    val capabilities: List<String>,
    val riskHint: PluginRisk,
    val requiresReboot: Boolean,
    val reversible: Boolean,
    val overlayRoots: List<String>,
    val actions: List<String>,
    val backupTargets: List<String>,
    val healthChecks: List<String>,
) {
    val verifiedModuleId: VerifiedPluginModuleId
        get() = VerifiedPluginModuleId.parse(id)

    companion object {
        const val FILE_NAME = "ccpocket-plugin.json"
        const val SCHEMA_VERSION = 1
        private const val MAX_JSON_BYTES = 64 * 1024
        private const val MAX_LIST_ITEMS = 64
        private const val MAX_ITEM_LENGTH = 256
        private const val MAX_NAME_LENGTH = 128
        private const val MAX_VERSION_LENGTH = 64

        private val FIELD_NAMES = setOf(
            "schemaVersion",
            "id",
            "name",
            "version",
            "capabilities",
            "riskHint",
            "requiresReboot",
            "reversible",
            "overlayRoots",
            "actions",
            "backupTargets",
            "healthChecks",
        )

        fun parse(bytes: ByteArray): PluginManifest {
            if (bytes.isEmpty() || bytes.size > MAX_JSON_BYTES) {
                throw PluginBrokerException(PluginBrokerErrorCode.MANIFEST_INVALID)
            }
            return parse(decodeUtf8(bytes))
        }

        fun parse(jsonText: String): PluginManifest {
            if (jsonText.toByteArray(StandardCharsets.UTF_8).size > MAX_JSON_BYTES) {
                throw PluginBrokerException(PluginBrokerErrorCode.MANIFEST_INVALID)
            }

            val json = try {
                StrictJsonParser(jsonText).parseObject()
            } catch (_: Exception) {
                throw PluginBrokerException(PluginBrokerErrorCode.MANIFEST_INVALID)
            }

            rejectUnknownFields(json)

            val schemaVersion = requiredInteger(json, "schemaVersion")
            if (schemaVersion != SCHEMA_VERSION) {
                throw PluginBrokerException(PluginBrokerErrorCode.MANIFEST_INVALID)
            }

            val id = requiredString(json, "id", MAX_ITEM_LENGTH)
            val verifiedId = try {
                VerifiedPluginModuleId.parse(id)
            } catch (_: PluginBrokerException) {
                throw PluginBrokerException(PluginBrokerErrorCode.MANIFEST_INVALID)
            }

            val name = requiredString(json, "name", MAX_NAME_LENGTH)
            val version = requiredString(json, "version", MAX_VERSION_LENGTH)
            val capabilities = requiredList(json, "capabilities", ListKind.TOKEN)
            val riskHint = PluginRisk.parse(requiredString(json, "riskHint", 2))
            val requiresReboot = requiredBoolean(json, "requiresReboot")
            val reversible = requiredBoolean(json, "reversible")
            val overlayRoots = requiredList(json, "overlayRoots", ListKind.PATH)
            val actions = requiredList(json, "actions", ListKind.TOKEN)
            val backupTargets = requiredList(json, "backupTargets", ListKind.PATH)
            val healthChecks = requiredList(json, "healthChecks", ListKind.TOKEN)

            // Keep the verified value alive through parsing.  This also makes
            // it explicit that the broker never trusts a raw manifest ID.
            check(verifiedId.value == id)
            return PluginManifest(
                schemaVersion = schemaVersion,
                id = id,
                name = name,
                version = version,
                capabilities = capabilities,
                riskHint = riskHint,
                requiresReboot = requiresReboot,
                reversible = reversible,
                overlayRoots = overlayRoots,
                actions = actions,
                backupTargets = backupTargets,
                healthChecks = healthChecks,
            )
        }

        private enum class ListKind {
            TOKEN,
            PATH,
        }

        private fun rejectUnknownFields(json: JsonObject) {
            if (json.fields.keys.any { it !in FIELD_NAMES }) {
                throw PluginBrokerException(PluginBrokerErrorCode.MANIFEST_INVALID)
            }
            if (FIELD_NAMES.any { !json.fields.containsKey(it) || json.fields[it] is JsonNull }) {
                throw PluginBrokerException(PluginBrokerErrorCode.MANIFEST_INVALID)
            }
        }

        private fun requiredInteger(json: JsonObject, key: String): Int {
            val literal = (json.fields[key] as? JsonNumber)?.literal
                ?: throw PluginBrokerException(PluginBrokerErrorCode.MANIFEST_INVALID)
            val longValue = literal.toLongOrNull()
                ?: throw PluginBrokerException(PluginBrokerErrorCode.MANIFEST_INVALID)
            if (longValue !in Int.MIN_VALUE..Int.MAX_VALUE) {
                throw PluginBrokerException(PluginBrokerErrorCode.MANIFEST_INVALID)
            }
            return longValue.toInt()
        }

        private fun requiredBoolean(json: JsonObject, key: String): Boolean =
            (json.fields[key] as? JsonBoolean)?.value
                ?: throw PluginBrokerException(PluginBrokerErrorCode.MANIFEST_INVALID)

        private fun requiredString(json: JsonObject, key: String, maxLength: Int): String {
            val value = (json.fields[key] as? JsonString)?.value
                ?: throw PluginBrokerException(PluginBrokerErrorCode.MANIFEST_INVALID)
            if (!isTextSafe(value) || value.isBlank() || value.length > maxLength) {
                throw PluginBrokerException(PluginBrokerErrorCode.MANIFEST_INVALID)
            }
            return value
        }

        private fun requiredList(json: JsonObject, key: String, kind: ListKind): List<String> {
            val values = (json.fields[key] as? JsonArray)?.values
                ?: throw PluginBrokerException(PluginBrokerErrorCode.MANIFEST_INVALID)
            if (values.size > MAX_LIST_ITEMS) {
                throw PluginBrokerException(PluginBrokerErrorCode.MANIFEST_INVALID)
            }

            val result = ArrayList<String>(values.size)
            val seen = HashSet<String>()
            for (valueNode in values) {
                val value = (valueNode as? JsonString)?.value
                    ?: throw PluginBrokerException(PluginBrokerErrorCode.MANIFEST_INVALID)
                if (
                    !isTextSafe(value) ||
                    value.isBlank() ||
                    value.length > MAX_ITEM_LENGTH ||
                    (kind == ListKind.TOKEN && !isToken(value)) ||
                    !seen.add(value)
                ) {
                    throw PluginBrokerException(PluginBrokerErrorCode.MANIFEST_INVALID)
                }
                result += value
            }
            return result
        }

        private fun isTextSafe(value: String): Boolean =
            value.none { character ->
                character.code < 0x20 || character == '\u007f' || character == '\u0000'
            }

        private fun isToken(value: String): Boolean =
            value.all { character ->
                character in 'a'..'z' ||
                    character in 'A'..'Z' ||
                    character in '0'..'9' ||
                    character == '_' ||
                    character == '-' ||
                    character == '.' ||
                    character == ':'
            }

        private fun decodeUtf8(bytes: ByteArray): String {
            return try {
                val decoder = StandardCharsets.UTF_8.newDecoder()
                    .onMalformedInput(CodingErrorAction.REPORT)
                    .onUnmappableCharacter(CodingErrorAction.REPORT)
                decoder.decode(ByteBuffer.wrap(bytes)).toString()
            } catch (_: CharacterCodingException) {
                throw PluginBrokerException(PluginBrokerErrorCode.MANIFEST_INVALID)
            }
        }
    }
}

/** Small strict JSON value model used so JVM tests do not depend on android.jar stubs. */
private sealed interface JsonValue

private data class JsonObject(val fields: LinkedHashMap<String, JsonValue>) : JsonValue

private data class JsonArray(val values: List<JsonValue>) : JsonValue

private data class JsonString(val value: String) : JsonValue

private data class JsonNumber(val literal: String) : JsonValue

private data class JsonBoolean(val value: Boolean) : JsonValue

private data object JsonNull : JsonValue

private const val MAX_JSON_NESTING_DEPTH = 64

private class StrictJsonParser(private val input: String) {
    private var offset = 0
    private var nestingDepth = 0

    fun parseObject(): JsonObject {
        val value = parseValue()
        skipWhitespace()
        if (offset != input.length || value !is JsonObject) throw JsonParseFailure
        return value
    }

    private fun parseValue(): JsonValue {
        skipWhitespace()
        if (offset >= input.length) throw JsonParseFailure
        if (input[offset] == '{' || input[offset] == '[') {
            if (nestingDepth >= MAX_JSON_NESTING_DEPTH) throw JsonParseFailure
            nestingDepth += 1
            return try {
                when (input[offset]) {
                    '{' -> parseObjectValue()
                    '[' -> parseArrayValue()
                    else -> throw JsonParseFailure
                }
            } finally {
                nestingDepth -= 1
            }
        }
        return when (input[offset]) {
            '"' -> JsonString(parseString())
            't' -> parseLiteral("true", JsonBoolean(true))
            'f' -> parseLiteral("false", JsonBoolean(false))
            'n' -> parseLiteral("null", JsonNull)
            '-', in '0'..'9' -> JsonNumber(parseNumber())
            else -> throw JsonParseFailure
        }
    }

    private fun parseObjectValue(): JsonObject {
        expect('{')
        skipWhitespace()
        val fields = LinkedHashMap<String, JsonValue>()
        if (consume('}')) return JsonObject(fields)
        while (true) {
            skipWhitespace()
            if (offset >= input.length || input[offset] != '"') throw JsonParseFailure
            val key = parseString()
            if (fields.containsKey(key)) throw JsonParseFailure
            skipWhitespace()
            expect(':')
            fields[key] = parseValue()
            skipWhitespace()
            when {
                consume('}') -> return JsonObject(fields)
                consume(',') -> Unit
                else -> throw JsonParseFailure
            }
        }
    }

    private fun parseArrayValue(): JsonArray {
        expect('[')
        skipWhitespace()
        val values = ArrayList<JsonValue>()
        if (consume(']')) return JsonArray(values)
        while (true) {
            values += parseValue()
            skipWhitespace()
            when {
                consume(']') -> return JsonArray(values)
                consume(',') -> Unit
                else -> throw JsonParseFailure
            }
        }
    }

    private fun parseString(): String {
        expect('"')
        val result = StringBuilder()
        while (offset < input.length) {
            val character = input[offset++]
            when {
                character == '"' -> return result.toString()
                character == '\\' -> {
                    if (offset >= input.length) throw JsonParseFailure
                    when (val escaped = input[offset++]) {
                        '"', '\\', '/' -> result.append(escaped)
                        'b' -> result.append('\b')
                        'f' -> result.append('\u000c')
                        'n' -> result.append('\n')
                        'r' -> result.append('\r')
                        't' -> result.append('\t')
                        'u' -> result.append(parseUnicodeEscape())
                        else -> throw JsonParseFailure
                    }
                }
                character.code < 0x20 -> throw JsonParseFailure
                else -> result.append(character)
            }
        }
        throw JsonParseFailure
    }

    private fun parseUnicodeEscape(): Char {
        if (offset + 4 > input.length) throw JsonParseFailure
        var value = 0
        repeat(4) {
            val digit = input[offset++].digitToIntOrNull(16) ?: throw JsonParseFailure
            value = (value shl 4) or digit
        }
        return value.toChar()
    }

    private fun parseNumber(): String {
        val start = offset
        consume('-')
        if (offset >= input.length) throw JsonParseFailure
        if (consume('0')) {
            if (offset < input.length && input[offset] in '0'..'9') throw JsonParseFailure
        } else {
            if (offset >= input.length || input[offset] !in '1'..'9') throw JsonParseFailure
            while (offset < input.length && input[offset] in '0'..'9') offset++
        }
        if (consume('.')) {
            if (offset >= input.length || input[offset] !in '0'..'9') throw JsonParseFailure
            while (offset < input.length && input[offset] in '0'..'9') offset++
        }
        if (offset < input.length && (input[offset] == 'e' || input[offset] == 'E')) {
            offset++
            if (offset < input.length && (input[offset] == '+' || input[offset] == '-')) offset++
            if (offset >= input.length || input[offset] !in '0'..'9') throw JsonParseFailure
            while (offset < input.length && input[offset] in '0'..'9') offset++
        }
        return input.substring(start, offset)
    }

    private fun parseLiteral(literal: String, value: JsonValue): JsonValue {
        if (!input.startsWith(literal, offset)) throw JsonParseFailure
        offset += literal.length
        return value
    }

    private fun skipWhitespace() {
        while (offset < input.length && input[offset] in " \t\r\n") offset++
    }

    private fun expect(character: Char) {
        if (!consume(character)) throw JsonParseFailure
    }

    private fun consume(character: Char): Boolean {
        if (offset < input.length && input[offset] == character) {
            offset++
            return true
        }
        return false
    }

    private object JsonParseFailure : Exception()
}

/** The subset of standard KernelSU module.prop needed for identity binding. */
internal data class PluginModuleProp(
    val id: String,
    val name: String,
    val version: String,
    val versionCode: Int,
    val author: String,
    val description: String,
)


