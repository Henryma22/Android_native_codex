package io.henry.codex

import android.content.Context
import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.provider.DocumentsContract
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.nio.charset.StandardCharsets
import java.nio.file.AtomicMoveNotSupportedException
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.security.MessageDigest
import java.util.UUID
import org.json.JSONObject

/**
 * Owns user-selected Storage Access Framework trees.
 *
 * SAF workspaces deliberately stay URI-backed. They are valid for file
 * browsing and managed text changes, but they do not become fake absolute
 * paths and therefore cannot be used as a HostProcess cwd.
 */
internal class SafWorkspaceStore(private val context: Context) {
    fun listWorkspaces(): List<Map<String, Any?>> {
        return treeUris().map { uriString ->
            val uri = Uri.parse(uriString)
            val available = hasPersistedPermission(uri)
            val name = if (available) queryDisplayName(uri) else null
            mapOf(
                "uri" to uriString,
                "name" to (name ?: uriString),
                "displayPath" to "SAF: ${name ?: uriString}",
                "filesystemOwnerId" to if (available) {
                    "android-saf"
                } else {
                    "android-saf-revoked"
                },
                "available" to available,
                "reason" to if (available) {
                    "Persisted SAF read/write permission is available"
                } else {
                    "SAF permission is no longer available; forget and re-add this tree"
                },
            )
        }
    }

    fun registerTree(uri: Uri): Map<String, Any?> {
        if (uri.scheme != "content" || !DocumentsContract.isTreeUri(uri)) {
            throw SafWorkspaceException(
                "invalid_uri",
                "SAF workspace must use a document-tree content URI",
            )
        }
        try {
            context.contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
            )
        } catch (error: SecurityException) {
            throw SafWorkspaceException(
                "permission_denied",
                "The selected provider did not grant a persistable read/write permission",
            )
        }
        val next = treeUris().toMutableSet()
        next.add(uri.toString())
        inMemoryTrees.add(uri.toString())
        forgottenTrees.remove(uri.toString())
        preferences.edit().putStringSet(KEY_TREES, next).apply()
        return listWorkspaces().first { it["uri"] == uri.toString() }
    }

    fun forgetTree(uriString: String) {
        val uri = parseTreeUri(uriString)
        try {
            context.contentResolver.releasePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
            )
        } catch (_: SecurityException) {
            // The permission may already have been revoked by Android.
        }
        val next = treeUris().toMutableSet()
        next.remove(uriString)
        inMemoryTrees.remove(uriString)
        forgottenTrees.add(uriString)
        preferences.edit().putStringSet(KEY_TREES, next).apply()
    }

    fun listDirectory(uriString: String, relativePath: String): List<Map<String, Any?>> {
        validateRelativePath(relativePath, allowEmpty = true)
        val treeUri = requireAvailableTree(uriString)
        val documentId = resolveDocumentId(treeUri, relativePath)
        val childUri = DocumentsContract.buildChildDocumentsUriUsingTree(
            treeUri,
            documentId,
        )
        return queryChildren(treeUri, childUri, relativePath)
    }

    fun readText(uriString: String, relativePath: String): String {
        val snapshot = snapshot(uriString, relativePath)
        return snapshot["content"] as String
    }

    fun snapshot(uriString: String, relativePath: String): Map<String, Any?> {
        validateRelativePath(relativePath, allowEmpty = false)
        val treeUri = requireAvailableTree(uriString)
        val documentUri = resolveDocumentUri(treeUri, relativePath)
        val content = readDocument(documentUri)
        return mapOf(
            "relativePath" to relativePath,
            "content" to content,
            "version" to sha256(content),
            "sizeBytes" to content.toByteArray(StandardCharsets.UTF_8).size.toLong(),
            "uid" to null,
            "gid" to null,
            "mode" to null,
            "isSymbolicLink" to false,
        )
    }

    fun writeText(
        uriString: String,
        relativePath: String,
        expectedVersion: String,
        content: String,
    ): Map<String, Any?> {
        val before = snapshot(uriString, relativePath)
        ensureExpectedVersion(before, expectedVersion)
        val backupId = createBackup(uriString, relativePath, before["content"] as String)
        writeDocument(
            resolveDocumentUri(requireAvailableTree(uriString), relativePath),
            content,
        )
        return receipt(
            backupId = backupId,
            relativePath = relativePath,
            beforeVersion = expectedVersion,
            afterVersion = sha256(content),
            restored = false,
        )
    }

    fun backupText(
        uriString: String,
        relativePath: String,
        expectedVersion: String,
    ): Map<String, Any?> {
        val before = snapshot(uriString, relativePath)
        ensureExpectedVersion(before, expectedVersion)
        val backupId = createBackup(uriString, relativePath, before["content"] as String)
        return receipt(
            backupId = backupId,
            relativePath = relativePath,
            beforeVersion = expectedVersion,
            afterVersion = expectedVersion,
            restored = false,
        )
    }

    fun restoreText(
        uriString: String,
        relativePath: String,
        backupId: String,
        expectedVersion: String,
    ): Map<String, Any?> {
        val backup = readBackup(backupId)
        if (backup.optString("workspaceUri") != uriString ||
            backup.optString("relativePath") != relativePath
        ) {
            throw SafWorkspaceException(
                "invalid_backup",
                "SAF backup does not match the requested workspace file",
            )
        }
        val before = snapshot(uriString, relativePath)
        ensureExpectedVersion(before, expectedVersion)
        val content = backup.optString("content", "")
        writeDocument(
            resolveDocumentUri(requireAvailableTree(uriString), relativePath),
            content,
        )
        return receipt(
            backupId = backupId,
            relativePath = relativePath,
            beforeVersion = expectedVersion,
            afterVersion = sha256(content),
            restored = true,
        )
    }

    private fun queryChildren(
        treeUri: Uri,
        childUri: Uri,
        relativePath: String,
    ): List<Map<String, Any?>> {
        val resolver = context.contentResolver
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_SIZE,
        )
        try {
            resolver.query(childUri, projection, null, null, null).use { cursor ->
                if (cursor == null) {
                    throw SafWorkspaceException(
                        "operation_failed",
                        "SAF provider returned no directory cursor",
                    )
                }
                val idIndex = cursor.getColumnIndexOrThrow(
                    DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                )
                val nameIndex = cursor.getColumnIndexOrThrow(
                    DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                )
                val mimeIndex = cursor.getColumnIndexOrThrow(
                    DocumentsContract.Document.COLUMN_MIME_TYPE,
                )
                val sizeIndex = cursor.getColumnIndex(
                    DocumentsContract.Document.COLUMN_SIZE,
                )
                val entries = mutableListOf<Map<String, Any?>>()
                while (cursor.moveToNext()) {
                    val name = cursor.getString(nameIndex) ?: "<unnamed>"
                    val childRelative = if (relativePath.isEmpty()) {
                        name
                    } else {
                        "$relativePath/$name"
                    }
                    val isDirectory = cursor.getString(mimeIndex) ==
                        DocumentsContract.Document.MIME_TYPE_DIR
                    val size = if (sizeIndex >= 0 && !cursor.isNull(sizeIndex)) {
                        cursor.getLong(sizeIndex)
                    } else {
                        0L
                    }
                    entries.add(
                        mapOf(
                            "name" to name,
                            "relativePath" to childRelative,
                            "isDirectory" to isDirectory,
                            "sizeBytes" to size,
                        ),
                    )
                }
                return entries.sortedBy { it["name"] as String }
            }
        } catch (error: SafWorkspaceException) {
            throw error
        } catch (error: SecurityException) {
            throw SafWorkspaceException(
                "permission_denied",
                "SAF provider denied directory access",
            )
        } catch (error: Exception) {
            throw SafWorkspaceException(
                "operation_failed",
                (error.message ?: "SAF directory query failed").take(512),
            )
        }
    }

    private fun resolveDocumentUri(treeUri: Uri, relativePath: String): Uri {
        val documentId = resolveDocumentId(treeUri, relativePath)
        return DocumentsContract.buildDocumentUriUsingTree(treeUri, documentId)
    }

    private fun resolveDocumentId(treeUri: Uri, relativePath: String): String {
        validateRelativePath(relativePath, allowEmpty = true)
        var current = DocumentsContract.getTreeDocumentId(treeUri)
        if (relativePath.isEmpty()) return current
        for (segment in relativePath.split('/')) {
            val childUri = DocumentsContract.buildChildDocumentsUriUsingTree(
                treeUri,
                current,
            )
            current = findChildId(childUri, segment)
                ?: throw SafWorkspaceException(
                    "not_found",
                    "SAF path does not exist: $relativePath",
                )
        }
        return current
    }

    private fun findChildId(childUri: Uri, name: String): String? {
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
        )
        try {
            context.contentResolver.query(childUri, projection, null, null, null)
                .use { cursor ->
                    if (cursor == null) return null
                    val idIndex = cursor.getColumnIndexOrThrow(
                        DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                    )
                    val nameIndex = cursor.getColumnIndexOrThrow(
                        DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                    )
                    while (cursor.moveToNext()) {
                        if (cursor.getString(nameIndex) == name) {
                            return cursor.getString(idIndex)
                        }
                    }
                }
        } catch (error: SecurityException) {
            throw SafWorkspaceException(
                "permission_denied",
                "SAF provider denied path lookup",
            )
        } catch (error: SafWorkspaceException) {
            throw error
        } catch (error: Exception) {
            throw SafWorkspaceException(
                "operation_failed",
                (error.message ?: "SAF path lookup failed").take(512),
            )
        }
        return null
    }

    private fun readDocument(uri: Uri): String {
        try {
            val bytes = ByteArrayOutputStream()
            context.contentResolver.openInputStream(uri)?.use { input ->
                val buffer = ByteArray(16 * 1024)
                var total = 0
                while (true) {
                    val count = input.read(buffer)
                    if (count <= 0) break
                    total += count
                    if (total > MAX_TEXT_BYTES) {
                        throw SafWorkspaceException(
                            "too_large",
                            "SAF text file exceeds 1 MiB",
                        )
                    }
                    bytes.write(buffer, 0, count)
                }
            } ?: throw SafWorkspaceException(
                "permission_denied",
                "SAF provider returned no readable stream",
            )
            return TextFileCodec.decode(
                bytes.toByteArray(),
                MAX_TEXT_BYTES,
                "SAF text file",
            )
        } catch (error: SafWorkspaceException) {
            throw error
        } catch (error: TextFileException) {
            throw SafWorkspaceException(error.code, error.message)
        } catch (error: SecurityException) {
            throw SafWorkspaceException(
                "permission_denied",
                "SAF provider denied file read",
            )
        } catch (error: Exception) {
            throw SafWorkspaceException(
                "operation_failed",
                (error.message ?: "SAF file read failed").take(512),
            )
        }
    }

    private fun writeDocument(uri: Uri, content: String) {
        val bytes = try {
            TextFileCodec.validateText(content, MAX_TEXT_BYTES, "SAF text file")
        } catch (error: TextFileException) {
            throw SafWorkspaceException(error.code, error.message)
        }
        try {
            val output = context.contentResolver.openOutputStream(uri, "wt")
                ?: throw SafWorkspaceException(
                    "permission_denied",
                    "SAF provider returned no writable stream",
                )
            output.use { it.write(bytes) }
        } catch (error: SafWorkspaceException) {
            throw error
        } catch (error: SecurityException) {
            throw SafWorkspaceException(
                "permission_denied",
                "SAF provider denied file write",
            )
        } catch (error: Exception) {
            throw SafWorkspaceException(
                "write_failed",
                (error.message ?: "SAF file write failed").take(512),
            )
        }
    }

    private fun createBackup(
        uriString: String,
        relativePath: String,
        content: String,
    ): String {
        val directory = File(context.filesDir, BACKUP_DIRECTORY)
        if (!directory.exists() && !directory.mkdirs()) {
            throw SafWorkspaceException(
                "backup_failed",
                "Could not create the SAF backup directory",
            )
        }
        val backupId = UUID.randomUUID().toString()
        val target = File(directory, "$backupId.json")
        val temporary = File(
            directory,
            ".${backupId}.tmp-${UUID.randomUUID()}",
        )
        try {
            val record = JSONObject()
                .put("workspaceUri", uriString)
                .put("relativePath", relativePath)
                .put("content", content)
                .toString()
            FileOutputStream(temporary).use { stream ->
                stream.write(record.toByteArray(StandardCharsets.UTF_8))
                stream.fd.sync()
            }
            try {
                Files.move(
                    temporary.toPath(),
                    target.toPath(),
                    StandardCopyOption.ATOMIC_MOVE,
                    StandardCopyOption.REPLACE_EXISTING,
                )
            } catch (_: AtomicMoveNotSupportedException) {
                Files.move(
                    temporary.toPath(),
                    target.toPath(),
                    StandardCopyOption.REPLACE_EXISTING,
                )
            }
        } catch (error: Exception) {
            temporary.delete()
            target.delete()
            throw SafWorkspaceException(
                "backup_failed",
                (error.message ?: "Could not persist the SAF backup").take(512),
            )
        }
        return backupId
    }

    private fun readBackup(backupId: String): JSONObject {
        if (backupId.isEmpty() || backupId.any { it !in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_" }) {
            throw SafWorkspaceException("invalid_backup", "Invalid SAF backup id")
        }
        val file = File(context.filesDir, "$BACKUP_DIRECTORY/$backupId.json")
        if (!file.isFile) {
            throw SafWorkspaceException("not_found", "SAF backup does not exist")
        }
        return try {
            JSONObject(
                TextFileCodec.decode(
                    file.readBytes(),
                    MAX_BACKUP_BYTES,
                    "backup metadata",
                ),
            )
        } catch (error: Exception) {
            throw SafWorkspaceException("invalid_backup", "SAF backup is invalid")
        }
    }

    private fun ensureExpectedVersion(
        snapshot: Map<String, Any?>,
        expectedVersion: String,
    ) {
        if (snapshot["version"] != expectedVersion) {
            throw SafWorkspaceException(
                "conflict",
                "SAF file changed after the preview was created",
            )
        }
    }

    private fun receipt(
        backupId: String,
        relativePath: String,
        beforeVersion: String,
        afterVersion: String,
        restored: Boolean,
    ): Map<String, Any?> = mapOf(
        "backupId" to backupId,
        "relativePath" to relativePath,
        "beforeVersion" to beforeVersion,
        "afterVersion" to afterVersion,
        "restored" to restored,
    )

    private fun requireAvailableTree(uriString: String): Uri {
        val uri = parseTreeUri(uriString)
        if (!hasPersistedPermission(uri)) {
            throw SafWorkspaceException(
                "permission_denied",
                "SAF permission is missing or was revoked",
            )
        }
        return uri
    }

    private fun parseTreeUri(uriString: String): Uri {
        val uri = Uri.parse(uriString)
        if (uri.scheme != "content" ||
            !DocumentsContract.isTreeUri(uri)
        ) {
            throw SafWorkspaceException("invalid_uri", "Invalid SAF tree URI")
        }
        return uri
    }

    private fun hasPersistedPermission(uri: Uri): Boolean =
        context.contentResolver.persistedUriPermissions.any {
            it.uri == uri && it.isReadPermission && it.isWritePermission
        }

    private fun queryDisplayName(uri: Uri): String? {
        val documentId = DocumentsContract.getTreeDocumentId(uri)
        val documentUri = DocumentsContract.buildDocumentUriUsingTree(uri, documentId)
        val projection = arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
        return try {
            context.contentResolver.query(documentUri, projection, null, null, null)
                .use { cursor ->
                    if (cursor != null && cursor.moveToFirst()) {
                        cursor.getString(0)
                    } else {
                        null
                    }
                }
        } catch (_: Exception) {
            null
        }
    }

    private fun treeUris(): List<String> {
        val stored = preferences.getStringSet(KEY_TREES, emptySet()).orEmpty()
        return (stored + inMemoryTrees)
            .filterNot { forgottenTrees.contains(it) }
            .distinct()
            .sorted()
    }

    private fun validateRelativePath(value: String, allowEmpty: Boolean) {
        if (!allowEmpty && value.isEmpty()) {
            throw SafWorkspaceException("invalid_path", "A relative path is required")
        }
        if (value.isEmpty()) return
        if (value.startsWith('/') || value.endsWith('/') || value.contains('\\')) {
            throw SafWorkspaceException("invalid_path", "SAF path must be relative")
        }
        value.split('/').forEach { segment ->
            if (segment.isEmpty() || segment == "." || segment == ".." ||
                segment.any { it.code < 0x20 || it.code == 0x7f }
            ) {
                throw SafWorkspaceException("invalid_path", "SAF path traversal is not allowed")
            }
        }
    }

    private fun sha256(value: String): String = MessageDigest
        .getInstance("SHA-256")
        .digest(value.toByteArray(StandardCharsets.UTF_8))
        .joinToString("") { byte -> "%02x".format(byte) }

    private val preferences by lazy {
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
    }

    private companion object {
        const val PREFERENCES = "codex_saf_workspaces"
        const val KEY_TREES = "tree_uris"
        const val BACKUP_DIRECTORY = "codex/saf-backups"
        const val MAX_TEXT_BYTES = 1024 * 1024
        const val MAX_BACKUP_BYTES = MAX_TEXT_BYTES * 2
        val inMemoryTrees = mutableSetOf<String>()
        val forgottenTrees = mutableSetOf<String>()
    }
}

internal class SafWorkspaceException(
    val code: String,
    override val message: String,
) : Exception(message)
