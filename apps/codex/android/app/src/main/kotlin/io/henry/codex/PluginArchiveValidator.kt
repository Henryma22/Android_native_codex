package io.henry.codex

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.nio.charset.CharacterCodingException
import java.nio.charset.Charset
import java.nio.charset.CodingErrorAction
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.util.Locale
import java.util.zip.ZipEntry
import java.util.zip.ZipException
import java.util.zip.ZipInputStream

/**
 * Archive-level facts returned after all untrusted bytes have been checked.
 * The original archive is intentionally not retained here; callers either
 * stage their already-validated bytes or discard them.
 */
internal data class ValidatedPluginArchive(
    val manifest: PluginManifest,
    val moduleProp: PluginModuleProp,
    val sha256: String,
    val effectiveRisk: PluginRisk,
    val entries: List<String>,
    val reviewFiles: List<PluginReviewFile>,
    val containsScripts: Boolean,
    val archiveSizeBytes: Long,
    val uncompressedSizeBytes: Long,
)

/** Bounded source excerpt for an archive member that can execute or set policy. */
internal data class PluginReviewFile(
    val path: String,
    val sizeBytes: Long,
    val content: String?,
    val truncated: Boolean,
)

/**
 * Bounded, extraction-free validation for a KernelSU plugin ZIP.
 *
 * The broker validates the bytes before they are written to a staging file.
 * In particular, this class does not use `File` or `Path` supplied by a
 * caller, and it never follows archive links.
 */
internal object PluginArchiveValidator {
    data class Limits(
        val maxArchiveBytes: Long = DEFAULT_MAX_ARCHIVE_BYTES,
        val maxUncompressedBytes: Long = DEFAULT_MAX_UNCOMPRESSED_BYTES,
        val maxEntryBytes: Long = DEFAULT_MAX_ENTRY_BYTES,
        val maxEntries: Int = DEFAULT_MAX_ENTRIES,
    ) {
        init {
            require(maxArchiveBytes > 0)
            require(maxUncompressedBytes > 0)
            require(maxEntryBytes > 0)
            require(maxEntries > 0)
        }
    }

    private data class CentralEntry(
        val name: String,
        val flags: Int,
        val method: Int,
        val compressedSize: Long,
        val uncompressedSize: Long,
        val versionMadeBy: Int,
        val externalAttributes: Long,
        val extra: ByteArray,
    ) {
        val unixMode: Int
            get() = if (((versionMadeBy ushr 8) and 0xff) == UNIX_MADE_BY) {
                ((externalAttributes ushr 16) and 0xffff).toInt()
            } else {
                0
            }

        val unixType: Int
            get() = unixMode and UNIX_FILE_TYPE_MASK
    }

    private data class ArchiveRead(
        val manifestBytes: ByteArray?,
        val modulePropBytes: ByteArray?,
        val entries: List<String>,
        val reviewFiles: List<PluginReviewFile>,
        val containsScripts: Boolean,
        val uncompressedSize: Long,
    )

    private enum class OverlaySafety {
        SAFE,
        R2,
        R3,
        R4,
    }

    private const val DEFAULT_MAX_ARCHIVE_BYTES = 32L * 1024 * 1024
    private const val DEFAULT_MAX_UNCOMPRESSED_BYTES = 128L * 1024 * 1024
    private const val DEFAULT_MAX_ENTRY_BYTES = 16L * 1024 * 1024
    private const val DEFAULT_MAX_ENTRIES = 256
    private const val MAX_MANIFEST_BYTES = 64 * 1024
    private const val MAX_MODULE_PROP_BYTES = 16 * 1024
    private const val MAX_CAPTURED_HEAD_BYTES = 512
    private const val MAX_REVIEW_FILE_BYTES = 32 * 1024
    private const val MAX_REVIEW_TOTAL_BYTES = 128 * 1024
    private const val UNIX_MADE_BY = 3
    private const val UNIX_FILE_TYPE_MASK = 0xf000
    private const val UNIX_REGULAR_FILE = 0x8000
    private const val UNIX_DIRECTORY = 0x4000
    private const val UNIX_FIFO = 0x1000
    private const val UNIX_CHAR_DEVICE = 0x2000
    private const val UNIX_BLOCK_DEVICE = 0x6000
    private const val UNIX_SOCKET = 0xc000
    private const val UNIX_SYMLINK = 0xa000
    private const val EOCD_SIGNATURE = 0x06054b50L
    private const val CENTRAL_SIGNATURE = 0x02014b50L
    private const val MAX_ZIP_COMMENT_BYTES = 0xffff
    private const val SAFE_MODULES_ROOT = "/data/adb/modules"
    private const val SAFE_MODULES_UPDATE_ROOT = "/data/adb/modules_update"

    private val CP437: Charset = Charset.forName("IBM437")

    /** Validate an archive and, when supplied, bind it to an exact SHA-256. */
    fun validate(
        archive: ByteArray,
        expectedSha256: String? = null,
        limits: Limits = Limits(),
    ): ValidatedPluginArchive = try {
        validateInternal(archive, expectedSha256, limits)
    } catch (error: PluginBrokerException) {
        throw error
    } catch (_: Exception) {
        // No parser or filesystem diagnostic is allowed across the broker
        // boundary, including an unexpected JDK ZIP runtime exception.
        throw PluginBrokerException(PluginBrokerErrorCode.MALFORMED_ARCHIVE)
    }

    private fun validateInternal(
        archive: ByteArray,
        expectedSha256: String?,
        limits: Limits,
    ): ValidatedPluginArchive {
        val archiveSize = archive.size.toLong()
        if (archiveSize == 0L) {
            throw PluginBrokerException(PluginBrokerErrorCode.ARCHIVE_EMPTY)
        }
        if (archiveSize > limits.maxArchiveBytes) {
            throw PluginBrokerException(PluginBrokerErrorCode.ARCHIVE_TOO_LARGE)
        }
        if (expectedSha256 != null && !isSha256(expectedSha256)) {
            throw PluginBrokerException(PluginBrokerErrorCode.INVALID_DIGEST)
        }

        val digest = sha256(archive)
        if (expectedSha256 != null && digest != expectedSha256) {
            throw PluginBrokerException(PluginBrokerErrorCode.DIGEST_MISMATCH)
        }

        val centralEntries = readCentralDirectory(archive, limits)
        val read = readZipEntries(archive, centralEntries, limits)
        val manifestBytes = read.manifestBytes
            ?: throw PluginBrokerException(PluginBrokerErrorCode.MANIFEST_MISSING)
        val modulePropBytes = read.modulePropBytes
            ?: throw PluginBrokerException(PluginBrokerErrorCode.MODULE_PROP_MISSING)

        val manifest = PluginManifest.parse(manifestBytes)
        val moduleProp = parseModuleProp(modulePropBytes)
        val moduleId = try {
            VerifiedPluginModuleId.parse(moduleProp.id)
        } catch (_: PluginBrokerException) {
            throw PluginBrokerException(PluginBrokerErrorCode.MODULE_PROP_INVALID)
        }
        if (moduleId.value != manifest.id) {
            throw PluginBrokerException(PluginBrokerErrorCode.MODULE_ID_MISMATCH)
        }
        if (moduleProp.name != manifest.name || moduleProp.version != manifest.version) {
            throw PluginBrokerException(PluginBrokerErrorCode.MODULE_METADATA_MISMATCH)
        }

        validateManifestPaths(manifest)
        val effectiveRisk = computeEffectiveRisk(
            manifest = manifest,
            containsScripts = read.containsScripts,
            entries = read.entries,
        )

        return ValidatedPluginArchive(
            manifest = manifest,
            moduleProp = moduleProp,
            sha256 = digest,
            effectiveRisk = effectiveRisk,
            entries = read.entries,
            reviewFiles = read.reviewFiles,
            containsScripts = read.containsScripts,
            archiveSizeBytes = archiveSize,
            uncompressedSizeBytes = read.uncompressedSize,
        )
    }

    fun validate(archive: ByteArray, limits: Limits): ValidatedPluginArchive =
        validate(archive = archive, expectedSha256 = null, limits = limits)

    fun sha256(archive: ByteArray): String {
        val bytes = MessageDigest.getInstance("SHA-256").digest(archive)
        val result = StringBuilder(bytes.size * 2)
        for (byte in bytes) {
            val unsigned = byte.toInt() and 0xff
            result.append(HEX_DIGITS[unsigned ushr 4])
            result.append(HEX_DIGITS[unsigned and 0x0f])
        }
        return result.toString()
    }

    private fun readCentralDirectory(
        archive: ByteArray,
        limits: Limits,
    ): List<CentralEntry> {
        val eocdOffset = findEndOfCentralDirectory(archive)
        if (eocdOffset < 0) {
            throw PluginBrokerException(PluginBrokerErrorCode.MALFORMED_ARCHIVE)
        }

        val diskNumber = readLe16(archive, eocdOffset + 4)
        val centralDisk = readLe16(archive, eocdOffset + 6)
        val entriesOnDisk = readLe16(archive, eocdOffset + 8)
        val totalEntries = readLe16(archive, eocdOffset + 10)
        val centralSize = readLe32(archive, eocdOffset + 12)
        val centralOffset = readLe32(archive, eocdOffset + 16)
        val commentLength = readLe16(archive, eocdOffset + 20)

        // ZIP64 and multi-disk archives are outside this small, deterministic
        // broker contract.  Rejecting them also prevents offset truncation.
        if (
            diskNumber != 0 ||
            centralDisk != 0 ||
            entriesOnDisk != totalEntries ||
            totalEntries == 0xffff ||
            centralSize == UINT32_MAX ||
            centralOffset == UINT32_MAX ||
            commentLength > MAX_ZIP_COMMENT_BYTES
        ) {
            throw PluginBrokerException(PluginBrokerErrorCode.MALFORMED_ARCHIVE)
        }
        if (totalEntries > limits.maxEntries) {
            throw PluginBrokerException(PluginBrokerErrorCode.ENTRY_COUNT_LIMIT)
        }

        val centralEnd = centralOffset + centralSize
        if (
            centralOffset > eocdOffset.toLong() ||
            centralEnd < centralOffset ||
            centralEnd != eocdOffset.toLong() ||
            centralEnd > archive.size.toLong()
        ) {
            throw PluginBrokerException(PluginBrokerErrorCode.MALFORMED_ARCHIVE)
        }

        val result = ArrayList<CentralEntry>(totalEntries)
        var cursor = centralOffset.toInt()
        val end = centralEnd.toInt()
        var totalCompressed = 0L
        repeat(totalEntries) {
            if (cursor + 46 > end || readLe32(archive, cursor) != CENTRAL_SIGNATURE) {
                throw PluginBrokerException(PluginBrokerErrorCode.MALFORMED_ARCHIVE)
            }
            val versionMadeBy = readLe16(archive, cursor + 4)
            val flags = readLe16(archive, cursor + 8)
            val method = readLe16(archive, cursor + 10)
            val compressedSize = readLe32(archive, cursor + 20)
            val uncompressedSize = readLe32(archive, cursor + 24)
            val nameLength = readLe16(archive, cursor + 28)
            val extraLength = readLe16(archive, cursor + 30)
            val entryCommentLength = readLe16(archive, cursor + 32)
            val externalAttributes = readLe32(archive, cursor + 38)
            if (
                compressedSize == UINT32_MAX ||
                uncompressedSize == UINT32_MAX ||
                cursor + 46 + nameLength + extraLength + entryCommentLength > end
            ) {
                throw PluginBrokerException(PluginBrokerErrorCode.MALFORMED_ARCHIVE)
            }

            val nameStart = cursor + 46
            val extraStart = nameStart + nameLength
            val name = decodeZipName(
                archive.copyOfRange(nameStart, extraStart),
                flags,
            )
            val extra = archive.copyOfRange(extraStart, extraStart + extraLength)
            if (flags and 0x0001 != 0) {
                throw PluginBrokerException(PluginBrokerErrorCode.ENCRYPTED_ENTRY)
            }
            if (method != ZipEntry.STORED && method != ZipEntry.DEFLATED) {
                throw PluginBrokerException(PluginBrokerErrorCode.UNSUPPORTED_COMPRESSION)
            }
            if (compressedSize > limits.maxArchiveBytes) {
                throw PluginBrokerException(PluginBrokerErrorCode.ENTRY_TOO_LARGE)
            }
            totalCompressed += compressedSize
            if (totalCompressed > limits.maxArchiveBytes) {
                throw PluginBrokerException(PluginBrokerErrorCode.ARCHIVE_TOO_LARGE)
            }

            result += CentralEntry(
                name = name,
                flags = flags,
                method = method,
                compressedSize = compressedSize,
                uncompressedSize = uncompressedSize,
                versionMadeBy = versionMadeBy,
                externalAttributes = externalAttributes,
                extra = extra,
            )
            cursor = extraStart + extraLength + entryCommentLength
        }
        if (cursor != end) {
            throw PluginBrokerException(PluginBrokerErrorCode.MALFORMED_ARCHIVE)
        }
        return result
    }

    private fun readZipEntries(
        archive: ByteArray,
        centralEntries: List<CentralEntry>,
        limits: Limits,
    ): ArchiveRead {
        val manifestCapture = ByteArrayOutputStream()
        val modulePropCapture = ByteArrayOutputStream()
        val names = ArrayList<String>(centralEntries.size)
        val reviewFiles = ArrayList<PluginReviewFile>()
        val seenNames = HashSet<String>()
        val seenCaseFoldedNames = HashSet<String>()
        var manifestBytes: ByteArray? = null
        var modulePropBytes: ByteArray? = null
        var containsScripts = false
        var totalUncompressed = 0L
        var totalReviewCaptured = 0
        var centralIndex = 0
        val input = ZipInputStream(ByteArrayInputStream(archive), StandardCharsets.UTF_8)

        try {
            while (true) {
                val entry = try {
                    input.nextEntry
                } catch (_: ZipException) {
                    throw PluginBrokerException(PluginBrokerErrorCode.MALFORMED_ARCHIVE)
                }
                if (entry == null) break
                if (centralIndex >= centralEntries.size) {
                    throw PluginBrokerException(PluginBrokerErrorCode.MALFORMED_ARCHIVE)
                }
                val central = centralEntries[centralIndex++]
                if (entry.name != central.name || entry.method != central.method) {
                    throw PluginBrokerException(PluginBrokerErrorCode.MALFORMED_ARCHIVE)
                }

                val canonicalName = canonicalMemberName(entry.name)
                val foldedName = canonicalName.lowercase(Locale.ROOT)
                if (!seenNames.add(canonicalName) || !seenCaseFoldedNames.add(foldedName)) {
                    // A duplicate path is rejected as an aliasing primitive;
                    // extraction must never choose "first" versus "last".
                    throw PluginBrokerException(PluginBrokerErrorCode.DUPLICATE_ENTRY)
                }

                val unixType = central.unixType
                when (unixType) {
                    0, UNIX_REGULAR_FILE -> Unit
                    UNIX_DIRECTORY -> {
                        if (!entry.isDirectory) {
                            throw PluginBrokerException(PluginBrokerErrorCode.SPECIAL_FILE)
                        }
                    }
                    UNIX_SYMLINK -> throw PluginBrokerException(PluginBrokerErrorCode.SYMLINK_ENTRY)
                    UNIX_FIFO,
                    UNIX_CHAR_DEVICE,
                    UNIX_BLOCK_DEVICE,
                    UNIX_SOCKET,
                    -> throw PluginBrokerException(PluginBrokerErrorCode.SPECIAL_FILE)
                    else -> throw PluginBrokerException(PluginBrokerErrorCode.SPECIAL_FILE)
                }
                if (hasHardlinkMetadata(central.extra)) {
                    throw PluginBrokerException(PluginBrokerErrorCode.HARDLINK_ENTRY)
                }

                if (central.uncompressedSize > limits.maxEntryBytes) {
                    throw PluginBrokerException(PluginBrokerErrorCode.ENTRY_TOO_LARGE)
                }
                if (central.uncompressedSize > limits.maxUncompressedBytes) {
                    throw PluginBrokerException(PluginBrokerErrorCode.UNCOMPRESSED_SIZE_LIMIT)
                }

                val isManifest = canonicalName == PluginManifest.FILE_NAME
                val isModuleProp = canonicalName == "module.prop"
                val capture = when {
                    isManifest -> manifestCapture
                    isModuleProp -> modulePropCapture
                    else -> null
                }
                val reviewCapture =
                    if (!entry.isDirectory && isReviewSource(canonicalName)) {
                        ByteArrayOutputStream()
                    } else {
                        null
                    }
                val head = ByteArrayOutputStream(MAX_CAPTURED_HEAD_BYTES)
                var entryUncompressed = 0L
                val buffer = ByteArray(16 * 1024)
                while (true) {
                    val count = try {
                        input.read(buffer)
                    } catch (_: ZipException) {
                        throw PluginBrokerException(PluginBrokerErrorCode.MALFORMED_ARCHIVE)
                    }
                    if (count < 0) break
                    if (count == 0) continue
                    entryUncompressed += count
                    totalUncompressed += count
                    if (entryUncompressed > limits.maxEntryBytes) {
                        throw PluginBrokerException(PluginBrokerErrorCode.ENTRY_TOO_LARGE)
                    }
                    if (totalUncompressed > limits.maxUncompressedBytes) {
                        throw PluginBrokerException(PluginBrokerErrorCode.UNCOMPRESSED_SIZE_LIMIT)
                    }
                    if (capture != null) {
                        val maxCapture = if (isManifest) MAX_MANIFEST_BYTES else MAX_MODULE_PROP_BYTES
                        if (capture.size() + count > maxCapture) {
                            throw PluginBrokerException(PluginBrokerErrorCode.MANIFEST_INVALID)
                        }
                        capture.write(buffer, 0, count)
                    }
                    if (reviewCapture != null) {
                        val remainingFile = MAX_REVIEW_FILE_BYTES - reviewCapture.size()
                        val remainingTotal = MAX_REVIEW_TOTAL_BYTES - totalReviewCaptured
                        val reviewCount = minOf(count, remainingFile, remainingTotal)
                        if (reviewCount > 0) {
                            reviewCapture.write(buffer, 0, reviewCount)
                            totalReviewCaptured += reviewCount
                        }
                    }
                    if (head.size() < MAX_CAPTURED_HEAD_BYTES) {
                        val copyCount = minOf(count, MAX_CAPTURED_HEAD_BYTES - head.size())
                        head.write(buffer, 0, copyCount)
                    }
                }
                try {
                    input.closeEntry()
                } catch (_: ZipException) {
                    throw PluginBrokerException(PluginBrokerErrorCode.MALFORMED_ARCHIVE)
                }

                if (entryUncompressed != central.uncompressedSize) {
                    throw PluginBrokerException(PluginBrokerErrorCode.MALFORMED_ARCHIVE)
                }
                if (!entry.isDirectory && entry.name.endsWith('/')) {
                    throw PluginBrokerException(PluginBrokerErrorCode.MALFORMED_ARCHIVE)
                }
                if (!entry.isDirectory && (isScriptName(canonicalName) || hasShebang(head.toByteArray()))) {
                    containsScripts = true
                }
                if (reviewCapture != null) {
                    val bytes = reviewCapture.toByteArray()
                    reviewFiles += PluginReviewFile(
                        path = canonicalName,
                        sizeBytes = entryUncompressed,
                        content = decodeReviewText(bytes),
                        truncated = bytes.size < entryUncompressed,
                    )
                }
                names += canonicalName
                if (isManifest) manifestBytes = manifestCapture.toByteArray()
                if (isModuleProp) modulePropBytes = modulePropCapture.toByteArray()
            }
        } catch (error: PluginBrokerException) {
            throw error
        } catch (_: ZipException) {
            throw PluginBrokerException(PluginBrokerErrorCode.MALFORMED_ARCHIVE)
        } catch (_: Exception) {
            throw PluginBrokerException(PluginBrokerErrorCode.MALFORMED_ARCHIVE)
        } finally {
            try {
                input.close()
            } catch (_: Exception) {
                // The safe, fixed error code from the read path is authoritative.
            }
        }

        if (centralIndex != centralEntries.size) {
            throw PluginBrokerException(PluginBrokerErrorCode.MALFORMED_ARCHIVE)
        }
        return ArchiveRead(
            manifestBytes = manifestBytes,
            modulePropBytes = modulePropBytes,
            entries = names,
            reviewFiles = reviewFiles,
            containsScripts = containsScripts,
            uncompressedSize = totalUncompressed,
        )
    }

    private fun parseModuleProp(bytes: ByteArray): PluginModuleProp {
        if (bytes.isEmpty() || bytes.size > MAX_MODULE_PROP_BYTES) {
            throw PluginBrokerException(PluginBrokerErrorCode.MODULE_PROP_INVALID)
        }
        val text = decode(bytes, StandardCharsets.UTF_8, PluginBrokerErrorCode.MODULE_PROP_INVALID)
        val fields = LinkedHashMap<String, String>()
        for (rawLine in text.split('\n')) {
            val line = rawLine.removeSuffix("\r")
            if (line.isBlank()) continue
            val separator = line.indexOf('=')
            if (separator <= 0) {
                throw PluginBrokerException(PluginBrokerErrorCode.MODULE_PROP_INVALID)
            }
            val key = line.substring(0, separator)
            val value = line.substring(separator + 1)
            if (
                key !in MODULE_PROP_FIELDS ||
                value.isBlank() ||
                value.length > 1024 ||
                !isSafeText(value) ||
                fields.put(key, value) != null
            ) {
                throw PluginBrokerException(PluginBrokerErrorCode.MODULE_PROP_INVALID)
            }
        }
        if (!REQUIRED_MODULE_PROP_FIELDS.all { it in fields }) {
            throw PluginBrokerException(PluginBrokerErrorCode.MODULE_PROP_INVALID)
        }
        val versionCode = fields["versionCode"]?.toIntOrNull()
            ?: throw PluginBrokerException(PluginBrokerErrorCode.MODULE_PROP_INVALID)
        if (versionCode < 0) {
            throw PluginBrokerException(PluginBrokerErrorCode.MODULE_PROP_INVALID)
        }
        return PluginModuleProp(
            id = fields.getValue("id"),
            name = fields.getValue("name"),
            version = fields.getValue("version"),
            versionCode = versionCode,
            author = fields.getValue("author"),
            description = fields.getValue("description"),
        )
    }

    private fun validateManifestPaths(manifest: PluginManifest) {
        for (root in manifest.overlayRoots) {
            if (!root.startsWith('/')) {
                throw PluginBrokerException(PluginBrokerErrorCode.OVERLAY_ROOT_INVALID)
            }
            validateCanonicalPath(root, PluginBrokerErrorCode.OVERLAY_ROOT_INVALID)
        }
        for (path in manifest.backupTargets) {
            // Backup implementations may resolve relative targets below a
            // trusted module/workspace root.  Validate both forms here so a
            // relative `../...` target cannot become an escape at execution
            // time.
            validateCanonicalPath(path, PluginBrokerErrorCode.PATH_ESCAPE)
        }
    }

    private fun computeEffectiveRisk(
        manifest: PluginManifest,
        containsScripts: Boolean,
        entries: List<String>,
    ): PluginRisk {
        val text = buildString {
            append(manifest.capabilities.joinToString("\n"))
            append('\n')
            append(manifest.overlayRoots.joinToString("\n"))
            append('\n')
            append(manifest.actions.joinToString("\n"))
            append('\n')
            append(manifest.backupTargets.joinToString("\n"))
            append('\n')
            append(manifest.healthChecks.joinToString("\n"))
        }.lowercase(Locale.ROOT)

        if (
            containsAny(text, R4_MARKERS) ||
            entries.any { archiveEntrySafety(it) == OverlaySafety.R4 }
        ) {
            return PluginRisk.R4
        }
        if (manifest.overlayRoots.any { overlaySafety(it) == OverlaySafety.R4 }) return PluginRisk.R4
        if (
            manifest.requiresReboot ||
            containsAny(text, R3_MARKERS) ||
            entries.any { archiveEntrySafety(it) == OverlaySafety.R3 }
        ) {
            return PluginRisk.R3
        }
        if (manifest.overlayRoots.any { overlaySafety(it) == OverlaySafety.R3 }) return PluginRisk.R3

        val unsafeOverlay = manifest.overlayRoots.any {
            overlaySafety(it) == OverlaySafety.R2
        }
        val rootCapability = containsAny(text, ROOT_CAPABILITY_MARKERS)
        if (
            containsScripts ||
            manifest.actions.isNotEmpty() ||
            unsafeOverlay ||
            rootCapability ||
            !manifest.reversible
        ) {
            return PluginRisk.R2
        }
        if (manifest.overlayRoots.isNotEmpty()) return PluginRisk.R1
        return PluginRisk.R0
    }

    private fun overlaySafety(root: String): OverlaySafety {
        val lower = root.lowercase(Locale.ROOT)
        if (containsAny(lower, R4_MARKERS)) return OverlaySafety.R4
        if (containsAny(lower, R3_MARKERS)) return OverlaySafety.R3
        if (
            lower == SAFE_MODULES_ROOT ||
            lower.startsWith("$SAFE_MODULES_ROOT/") ||
            lower == SAFE_MODULES_UPDATE_ROOT ||
            lower.startsWith("$SAFE_MODULES_UPDATE_ROOT/")
        ) {
            return OverlaySafety.SAFE
        }
        return OverlaySafety.R2
    }

    /**
     * Module members are relative to the KernelSU module root, so a manifest
     * can claim a safe overlay while the ZIP itself carries boot-sensitive
     * paths. Classify those members independently of the declared hint.
     */
    private fun archiveEntrySafety(name: String): OverlaySafety {
        val lower = name.lowercase(Locale.ROOT)
        val components = lower.split('/')
        val basename = components.last()
        if (
            components.any { it in ARCHIVE_R4_COMPONENTS } ||
            basename in ARCHIVE_R4_NAMES ||
            R4_ARCHIVE_MARKERS.any { lower.contains(it) }
        ) {
            return OverlaySafety.R4
        }
        if (
            components.any { it in ARCHIVE_R3_COMPONENTS } ||
            basename in ARCHIVE_R3_NAMES ||
            basename.removeSuffix(".sh") in ARCHIVE_R3_NAMES
        ) {
            return OverlaySafety.R3
        }
        return OverlaySafety.SAFE
    }

    private fun canonicalMemberName(name: String): String {
        if (
            name.isEmpty() ||
            name.indexOf('\u0000') >= 0 ||
            name.contains('\\') ||
            name.startsWith('/') ||
            name.startsWith("/") ||
            WINDOWS_DRIVE_PREFIX.matches(name)
        ) {
            throw PluginBrokerException(PluginBrokerErrorCode.PATH_ESCAPE)
        }
        val isDirectory = name.endsWith('/')
        val body = if (isDirectory) name.dropLast(1) else name
        if (body.isEmpty() || body.endsWith('/') || body.contains("//")) {
            throw PluginBrokerException(PluginBrokerErrorCode.NON_CANONICAL_PATH)
        }
        for (component in body.split('/')) {
            if (component.isEmpty() || component == "." || component == "..") {
                throw PluginBrokerException(PluginBrokerErrorCode.PATH_ESCAPE)
            }
        }
        return body
    }

    private fun validateCanonicalPath(path: String, invalidCode: PluginBrokerErrorCode) {
        if (
            path.isEmpty() ||
            path.indexOf('\u0000') >= 0 ||
            path.contains('\\') ||
            path.contains("//") ||
            WINDOWS_DRIVE_PREFIX.matches(path)
        ) {
            throw PluginBrokerException(invalidCode)
        }
        val body = if (path.length > 1 && path.endsWith('/')) path.dropLast(1) else path
        val components = when {
            body == "/" -> emptyList()
            body.startsWith('/') -> body.removePrefix("/").split('/')
            else -> body.split('/')
        }
        if (components.any { it.isEmpty() || it == "." || it == ".." }) {
            throw PluginBrokerException(
                if (components.any { it == ".." }) {
                    PluginBrokerErrorCode.PATH_ESCAPE
                } else {
                    invalidCode
                },
            )
        }
    }

    private fun isScriptName(name: String): Boolean {
        val lower = name.lowercase(Locale.ROOT)
        val basename = lower.substringAfterLast('/')
        return SCRIPT_EXTENSIONS.any { lower.endsWith(it) } ||
            basename in KERNELSU_SCRIPT_NAMES
    }

    private fun isReviewSource(name: String): Boolean {
        val lower = name.lowercase(Locale.ROOT)
        return isScriptName(name) ||
            lower == "sepolicy.rule" ||
            lower == "system.prop" ||
            (lower.startsWith("initrc/") && lower.endsWith(".rc"))
    }

    private fun decodeReviewText(bytes: ByteArray): String? {
        val decoded = try {
            decode(bytes, StandardCharsets.UTF_8, PluginBrokerErrorCode.MALFORMED_ARCHIVE)
        } catch (_: PluginBrokerException) {
            return null
        }
        return buildString(decoded.length) {
            for (character in decoded) {
                val code = character.code
                if (
                    character.isISOControl() && character !in setOf('\n', '\r', '\t') ||
                    code in 0x202a..0x202e ||
                    code in 0x2066..0x2069 ||
                    code == 0x200b ||
                    code == 0xfeff
                ) {
                    append("\\u")
                    append(code.toString(16).padStart(4, '0'))
                } else {
                    append(character)
                }
            }
        }
    }

    private fun hasShebang(bytes: ByteArray): Boolean =
        bytes.size >= 2 && bytes[0] == '#'.code.toByte() && bytes[1] == '!'.code.toByte()

    private fun hasHardlinkMetadata(extra: ByteArray): Boolean {
        // ZIP has no native hard-link inode primitive.  A few archive tools
        // nevertheless carry a textual hard-link marker in private extras;
        // reject such metadata rather than treating it as a regular file.
        var offset = 0
        while (offset + 4 <= extra.size) {
            readLe16(extra, offset)
            val length = readLe16(extra, offset + 2)
            offset += 4
            if (offset + length > extra.size) {
                throw PluginBrokerException(PluginBrokerErrorCode.MALFORMED_ARCHIVE)
            }
            val text = extra.copyOfRange(offset, offset + length)
                .toString(StandardCharsets.ISO_8859_1)
                .lowercase(Locale.ROOT)
            if (text.contains("hardlink")) return true
            offset += length
        }
        if (offset != extra.size) {
            throw PluginBrokerException(PluginBrokerErrorCode.MALFORMED_ARCHIVE)
        }
        return false
    }

    private fun decodeZipName(bytes: ByteArray, flags: Int): String {
        val charset = if (flags and 0x0800 != 0) StandardCharsets.UTF_8 else CP437
        return decode(bytes, charset, PluginBrokerErrorCode.MALFORMED_ARCHIVE)
    }

    private fun decode(
        bytes: ByteArray,
        charset: Charset,
        errorCode: PluginBrokerErrorCode,
    ): String {
        return try {
            val decoder = charset.newDecoder()
                .onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
            decoder.decode(java.nio.ByteBuffer.wrap(bytes))
                .toString()
        } catch (_: CharacterCodingException) {
            throw PluginBrokerException(errorCode)
        } catch (_: Exception) {
            throw PluginBrokerException(errorCode)
        }
    }

    private fun findEndOfCentralDirectory(archive: ByteArray): Int {
        val start = maxOf(0, archive.size - 22 - MAX_ZIP_COMMENT_BYTES)
        for (offset in archive.size - 22 downTo start) {
            if (
                offset >= 0 &&
                readLe32(archive, offset) == EOCD_SIGNATURE &&
                offset + 22 <= archive.size &&
                offset + 22 + readLe16(archive, offset + 20) == archive.size
            ) {
                return offset
            }
        }
        return -1
    }

    private fun readLe16(bytes: ByteArray, offset: Int): Int {
        if (offset < 0 || offset + 2 > bytes.size) {
            throw PluginBrokerException(PluginBrokerErrorCode.MALFORMED_ARCHIVE)
        }
        return (bytes[offset].toInt() and 0xff) or
            ((bytes[offset + 1].toInt() and 0xff) shl 8)
    }

    private fun readLe32(bytes: ByteArray, offset: Int): Long {
        if (offset < 0 || offset + 4 > bytes.size) {
            throw PluginBrokerException(PluginBrokerErrorCode.MALFORMED_ARCHIVE)
        }
        return (bytes[offset].toLong() and 0xff) or
            ((bytes[offset + 1].toLong() and 0xff) shl 8) or
            ((bytes[offset + 2].toLong() and 0xff) shl 16) or
            ((bytes[offset + 3].toLong() and 0xff) shl 24)
    }

    private fun isSha256(value: String): Boolean =
        value.length == 64 && value.all { it in '0'..'9' || it in 'a'..'f' }

    private fun isSafeText(value: String): Boolean =
        value.none { character -> character.code < 0x20 || character == '\u007f' }

    private fun containsAny(value: String, markers: List<String>): Boolean =
        markers.any { value.contains(it) }

    private const val UINT32_MAX = 0xffffffffL
    private val HEX_DIGITS = "0123456789abcdef".toCharArray()
    private val WINDOWS_DRIVE_PREFIX = Regex("^[A-Za-z]:")
    private val MODULE_PROP_FIELDS = setOf(
        "id",
        "name",
        "version",
        "versionCode",
        "author",
        "description",
        "updateJson",
        "minApi",
        "maxApi",
    )
    private val REQUIRED_MODULE_PROP_FIELDS = setOf(
        "id",
        "name",
        "version",
        "versionCode",
        "author",
        "description",
    )
    private val KERNELSU_SCRIPT_NAMES = setOf(
        "action.sh",
        "boot-completed.sh",
        "customize.sh",
        "install.sh",
        "post-fs-data.sh",
        "service.sh",
        "uninstall.sh",
    )
    private val SCRIPT_EXTENSIONS = setOf(
        ".sh",
        ".bash",
        ".zsh",
        ".ksh",
        ".mksh",
        ".py",
        ".pl",
        ".rb",
        ".lua",
        ".js",
        ".mjs",
        ".ts",
    )
    private val ARCHIVE_R4_COMPONENTS = setOf(
        "boot",
        "init_boot",
        "vendor_boot",
        "dtbo",
        "vbmeta",
        "recovery",
        "kernel",
        "partition",
        "raw_block",
        "bootloader",
        "mtd",
    )
    private val ARCHIVE_R4_NAMES = setOf(
        "boot.img",
        "init_boot.img",
        "vendor_boot.img",
        "dtbo.img",
        "vbmeta.img",
        "super.img",
        "recovery.img",
    )
    private val R4_ARCHIVE_MARKERS = listOf(
        "boot.img",
        "init_boot",
        "vendor_boot",
        "dtbo",
        "vbmeta",
        "super.img",
        "raw_block",
        "bootloader",
        "partition",
        "kernel",
        "mtd",
    )
    private val ARCHIVE_R3_COMPONENTS = setOf(
        "initrc",
        "system",
        "vendor",
        "product",
        "system_ext",
        "odm",
        "apex",
        "sepolicy",
        "zygisk",
        "riru",
        "system_server",
    )
    private val ARCHIVE_R3_NAMES = setOf(
        "post-fs-data",
        "post-fs-data.sh",
        "boot-completed",
        "boot-completed.sh",
        "init.rc",
        "default.prop",
        "ueventd.rc",
        "sepolicy.rule",
        "service.sh",
        "post-mount.sh",
        "system.img",
        "vendor.img",
        "product.img",
        "system_ext.img",
        "odm.img",
        "sepolicy",
        "zygisk",
        "riru",
        "system_server",
    )
    private val R4_MARKERS = listOf(
        "boot-chain",
        "boot.img",
        "init_boot",
        "vendor_boot",
        "dtbo",
        "vbmeta",
        "recovery",
        "partition",
        "kernel",
        "/dev/block",
        "raw_block",
        "bootloader",
        "mtd",
        "super.img",
    )
    private val R3_MARKERS = listOf(
        "requires-reboot",
        "selinux",
        "sepolicy",
        "zygisk",
        "riru",
        "post-fs-data",
        "boot-completed",
        "system_server",
        "/system",
        "/vendor",
        "/product",
        "/system_ext",
        "/odm",
        "/apex",
    )
    private val ROOT_CAPABILITY_MARKERS = listOf(
        "root",
        "kernelsu",
        "mount",
        "exec",
        "action",
        "service",
        "sepolicy",
    )
}
