package io.henry.codex

import android.content.Context
import android.net.Uri
import android.os.Build
import android.provider.DocumentsContract
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.TimeUnit

/** Imports a builder-produced ARM64 rootfs from one user-selected SAF folder. */
internal class CompatibilityRootfsInstaller(
    private val context: Context,
    private val rootHelpers: List<String>,
    private val runtimeProbe: () -> Map<String, Any?>,
) {
    fun installFromTree(treeUri: Uri): Map<String, Any?> {
        require(treeUri.scheme == "content") {
            "Choose a folder from an Android document provider."
        }
        require(Build.SUPPORTED_ABIS.contains("arm64-v8a")) {
            "Linux compatibility rootfs import requires an ARM64 Android device."
        }
        val documents = findDocuments(treeUri)
        val archives = documents.filter { it.name.endsWith(".tar.gz", ignoreCase = true) }
        require(archives.size == 1) {
            "The selected folder must contain exactly one .tar.gz rootfs archive."
        }
        val archive = archives.single()
        val manifestName = archive.name.removeSuffixIgnoreCase(".tar.gz") + ".manifest.json"
        val manifest = documents.singleOrNull { it.name == manifestName }
            ?: error("Matching rootfs manifest was not found: $manifestName")

        val id = UUID.randomUUID().toString().replace("-", "")
        val stage = File(context.cacheDir, "codex-rootfs-install-$id")
        require(stage.canonicalFile.parentFile == context.cacheDir.canonicalFile) {
            "Compatibility rootfs staging escaped the app cache."
        }
        require(stage.mkdirs() && !stage.isSymbolicLink()) {
            "Could not create private compatibility rootfs staging."
        }
        try {
            val stagedArchive = File(stage, "rootfs.tar.gz")
            val archiveBytes = copyDocument(
                archive.uri,
                stagedArchive,
                CompatibilityRootfsManifest.MAX_ARCHIVE_BYTES,
            )
            val stagedManifest = File(stage, "builder.manifest.json")
            copyDocument(
                manifest.uri,
                stagedManifest,
                CompatibilityRootfsManifest.MAX_MANIFEST_BYTES.toLong(),
            )
            val metadata = CompatibilityRootfsManifest.parse(
                jsonText = stagedManifest.readText(StandardCharsets.UTF_8),
                selectedArchiveName = archive.name,
                actualArchiveBytes = archiveBytes,
                actualArchiveSha256 = sha256(stagedArchive),
            )
            val archiveSummary = CompatibilityRootfsArchiveInspector.inspect(stagedArchive)
            require(archiveSummary.members == metadata.memberCount &&
                archiveSummary.regularFiles == metadata.regularFileCount &&
                archiveSummary.unpackedBytes == metadata.unpackedBytes
            ) { "Rootfs archive contents do not match the safety counts in its manifest." }
            File(stage, "runtime.manifest.json").writeText(
                metadata.runtimeMarkerJson(),
                StandardCharsets.UTF_8,
            )
            copyAsset(FINALIZER_ASSET, File(stage, FINALIZER_NAME), MAX_SCRIPT_BYTES)
            copyAsset(INSTALLER_ASSET, File(stage, INSTALLER_NAME), MAX_SCRIPT_BYTES)

            val noBackup = context.noBackupFilesDir.canonicalFile
            require(noBackup.absolutePath.matches(NO_BACKUP_PATH)) {
                "The app-private runtime directory does not match the Codex package."
            }
            val rootBase = File(noBackup, CompatibilityProcessManager.RUNTIME_BASE_DIRECTORY)
            require(rootBase.absolutePath == File(
                context.noBackupFilesDir,
                CompatibilityProcessManager.RUNTIME_BASE_DIRECTORY,
            ).absolutePath) { "Compatibility runtime base is invalid." }
            val helper = RootProfileLaunchGate.requireSafeHelper(
                AndroidRootProfileProbe(context).run(),
            )
            require(helper in rootHelpers) {
                "KernelSU returned a Root helper that is not available to this app build."
            }
            runInstallerScript(
                helper = helper,
                script = File(stage, INSTALLER_NAME),
                arguments = listOf(
                    rootBase.absolutePath,
                    stage.absolutePath,
                    context.applicationInfo.uid.toString(),
                    context.applicationInfo.nativeLibraryDir,
                    metadata.archiveSha256,
                    metadata.runtimeVersion,
                    metadata.nodeVersion,
                    metadata.codexVersion,
                    id,
                ),
            )
            val result = runtimeProbe()
            check(result["state"] == "verified") {
                "Rootfs install finished, but the Android PRoot guest probe failed: " +
                    (result["reason"]?.toString() ?: "unknown runtime error")
            }
            return result
        } finally {
            stage.deleteRecursively()
        }
    }

    private fun findDocuments(treeUri: Uri): List<PickedDocument> {
        val treeId = DocumentsContract.getTreeDocumentId(treeUri)
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, treeId)
        val columns = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
        )
        val documents = mutableListOf<PickedDocument>()
        context.contentResolver.query(childrenUri, columns, null, null, null)?.use { cursor ->
            val idColumn = cursor.getColumnIndexOrThrow(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            )
            val nameColumn = cursor.getColumnIndexOrThrow(
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            )
            val mimeColumn = cursor.getColumnIndexOrThrow(
                DocumentsContract.Document.COLUMN_MIME_TYPE,
            )
            while (cursor.moveToNext()) {
                if (cursor.getString(mimeColumn) == DocumentsContract.Document.MIME_TYPE_DIR) {
                    continue
                }
                val id = cursor.getString(idColumn) ?: continue
                val name = cursor.getString(nameColumn) ?: continue
                documents += PickedDocument(
                    name = name,
                    uri = DocumentsContract.buildDocumentUriUsingTree(treeUri, id),
                )
            }
        } ?: error("The selected folder could not be read.")
        return documents
    }

    private fun copyDocument(source: Uri, destination: File, maxBytes: Long): Long {
        val input = context.contentResolver.openInputStream(source)
            ?: error("A selected rootfs document could not be opened.")
        try {
            input.use { stream ->
                FileOutputStream(destination).use { output ->
                    val buffer = ByteArray(COPY_BUFFER_BYTES)
                    var total = 0L
                    while (true) {
                        val count = stream.read(buffer)
                        if (count < 0) break
                        total += count
                        require(total <= maxBytes) {
                            "A selected rootfs document exceeds the import size limit."
                        }
                        output.write(buffer, 0, count)
                    }
                    output.fd.sync()
                    return total
                }
            }
        } catch (error: Exception) {
            destination.delete()
            throw error
        }
    }

    private fun copyAsset(name: String, destination: File, maxBytes: Int) {
        context.assets.open(name).use { input ->
            FileOutputStream(destination).use { output ->
                val buffer = ByteArray(4096)
                var total = 0
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    total += count
                    require(total <= maxBytes) { "Bundled rootfs installer asset is too large." }
                    output.write(buffer, 0, count)
                }
                output.fd.sync()
            }
        }
    }

    private fun runInstallerScript(helper: String, script: File, arguments: List<String>) {
        val command = (listOf("/system/bin/sh", script.absolutePath) + arguments)
            .joinToString(" ", transform = ::shellQuote)
        val process = ProcessBuilder(helper, "-c", command)
            .redirectErrorStream(true)
            .start()
        val output = ByteArrayOutputStream()
        val reader = Thread {
            process.inputStream.use { input ->
                val buffer = ByteArray(4096)
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    synchronized(output) {
                        val remaining = MAX_CAPTURED_OUTPUT_BYTES - output.size()
                        if (remaining > 0) output.write(buffer, 0, minOf(count, remaining))
                    }
                }
            }
        }.apply { start() }
        process.outputStream.close()
        if (!process.waitFor(INSTALL_TIMEOUT_SECONDS, TimeUnit.SECONDS)) {
            process.destroyForcibly()
            reader.join(1_000)
            error("Compatibility rootfs installation timed out after $INSTALL_TIMEOUT_SECONDS seconds.")
        }
        reader.join(2_000)
        val outputText = synchronized(output) {
            output.toString(StandardCharsets.UTF_8.name()).trim()
        }
        check(process.exitValue() == 0) {
            outputText.ifBlank { "KernelSU rootfs installation exited ${process.exitValue()}." }
        }
    }

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(COPY_BUFFER_BYTES)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        return digest.digest().joinToString("") { byte -> "%02x".format(byte) }
    }

    private fun shellQuote(value: String): String = "'${value.replace("'", "'\\''")}'"

    private fun File.isSymbolicLink(): Boolean =
        java.nio.file.Files.isSymbolicLink(toPath())

    private fun String.removeSuffixIgnoreCase(suffix: String): String =
        if (endsWith(suffix, ignoreCase = true)) dropLast(suffix.length) else this

    private data class PickedDocument(val name: String, val uri: Uri)

    private companion object {
        const val FINALIZER_ASSET = "proot-finalize-rootfs.sh"
        const val FINALIZER_NAME = "proot-finalize-rootfs.sh"
        const val INSTALLER_ASSET = "install-proot-rootfs.sh"
        const val INSTALLER_NAME = "install-proot-rootfs.sh"
        const val MAX_SCRIPT_BYTES = 64 * 1024
        const val COPY_BUFFER_BYTES = 64 * 1024
        const val MAX_CAPTURED_OUTPUT_BYTES = 32 * 1024
        const val INSTALL_TIMEOUT_SECONDS = 1_800L
        val NO_BACKUP_PATH = Regex("/data/(user|user_de)/[0-9]+/io\\.henry\\.codex/no_backup")
    }
}
