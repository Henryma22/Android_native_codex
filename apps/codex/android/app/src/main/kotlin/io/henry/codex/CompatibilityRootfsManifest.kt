package io.henry.codex

import org.json.JSONObject

internal data class CompatibilityRootfsManifest(
    val archiveName: String,
    val archiveBytes: Long,
    val archiveSha256: String,
    val memberCount: Int,
    val regularFileCount: Int,
    val unpackedBytes: Long,
    val runtimeVersion: String,
    val nodeVersion: String,
    val codexVersion: String,
) {
    fun runtimeMarkerJson(): String = JSONObject()
        .put("schemaVersion", 1)
        .put("state", "verified")
        .put("verificationMode", "finalized-proot")
        .put("rootfsDigest", archiveSha256)
        .put("runtimeVersion", runtimeVersion)
        .put("nodeVersion", nodeVersion)
        .put("codexVersion", codexVersion)
        .toString()

    companion object {
        private val SHA256 = Regex("[0-9a-f]{64}")
        private val SEMVER = Regex("[0-9]+\\.[0-9]+\\.[0-9]+")
        private val SAFE_TOKEN = Regex("[A-Za-z0-9._+\\-]{1,128}")
        private val REQUIRED_REJECTIONS = setOf(
            "absolute-or-traversal-paths",
            "special-files",
            "setuid-setgid",
            "capability-xattrs",
            "world-writable",
        )

        fun parse(
            jsonText: String,
            selectedArchiveName: String,
            actualArchiveBytes: Long,
            actualArchiveSha256: String,
        ): CompatibilityRootfsManifest {
            require(jsonText.toByteArray(Charsets.UTF_8).size in 1..MAX_MANIFEST_BYTES) {
                "Rootfs manifest is empty or too large."
            }
            require(selectedArchiveName.isNotBlank() &&
                selectedArchiveName == selectedArchiveName.substringAfterLast('/') &&
                selectedArchiveName == selectedArchiveName.substringAfterLast('\\')
            ) { "Selected rootfs archive name is invalid." }
            require(actualArchiveBytes in 1L..MAX_ARCHIVE_BYTES) {
                "Rootfs archive size is outside the import limit."
            }
            require(SHA256.matches(actualArchiveSha256)) {
                "Rootfs archive SHA-256 is invalid."
            }

            val root = JSONObject(jsonText)
            val schema = root.getJSONObject("schema")
            require(schema.optInt("version", -1) == 1 &&
                schema.optString("name") == "codex-android-local-rootfs"
            ) { "Rootfs manifest schema is unsupported." }

            val artifact = root.getJSONObject("artifact")
            val archiveName = artifact.getString("filename")
            require(archiveName.matches(Regex("[A-Za-z0-9._+@-]+\\.tar\\.gz")) &&
                archiveName == selectedArchiveName
            ) { "Selected archive does not match the rootfs manifest." }
            require(artifact.optString("format") == "tar.gz") {
                "Rootfs archive format must be tar.gz."
            }
            val archiveBytes = artifact.getLong("bytes")
            require(archiveBytes == actualArchiveBytes) {
                "Rootfs archive size does not match its manifest."
            }
            val digest = artifact.getString("sha256").lowercase()
            require(SHA256.matches(digest) && digest == actualArchiveSha256) {
                "Rootfs archive SHA-256 does not match its manifest."
            }
            require(artifact.getInt("members") in 1..MAX_ARCHIVE_ENTRIES) {
                "Rootfs manifest archive member count is invalid."
            }
            require(artifact.getLong("unpacked_bytes") in 1..MAX_UNPACKED_BYTES) {
                "Rootfs manifest unpacked size is outside the supported limit."
            }

            val target = root.getJSONObject("target")
            require(target.optString("os") == "linux" &&
                target.optString("arch") == "arm64" &&
                target.optString("android_abi") == "arm64-v8a"
            ) { "Only Linux ARM64 compatibility rootfs archives are supported." }

            val debian = root.getJSONObject("debian")
            val suite = debian.getString("suite")
            require(SAFE_TOKEN.matches(suite)) { "Debian suite in rootfs manifest is invalid." }
            val components = root.getJSONObject("components")
            val nodeVersion = components.getJSONObject("node").getString("version")
            require(SEMVER.matches(nodeVersion)) { "Node.js version in rootfs manifest is invalid." }
            val codexVersion = components.getJSONObject("codex").getString("resolved_version")
            require(SAFE_TOKEN.matches(codexVersion) &&
                SEMVER.matches(codexVersion.removeSuffix("-linux-arm64"))
            ) { "Codex version in rootfs manifest is invalid." }

            val finalize = root.getJSONObject("device_finalize")
            require(finalize.optString("script") == "device/proot-finalize-rootfs.sh" &&
                finalize.optString("second_stage") == "/debootstrap/debootstrap --second-stage"
            ) { "Rootfs finalization contract is unsupported." }
            val security = root.getJSONObject("security")
            require(security.optString("archive_check") == "archive_safety.py") {
                "Rootfs manifest does not identify the required archive checks."
            }
            val rejected = security.getJSONArray("rejected").let { values ->
                (0 until values.length()).map(values::getString).toSet()
            }
            require(rejected.containsAll(REQUIRED_REJECTIONS)) {
                "Rootfs manifest does not declare the required archive checks."
            }

            val runtimeVersion = "debian-$suite-node-$nodeVersion-codex-$codexVersion"
            require(SAFE_TOKEN.matches(runtimeVersion)) {
                "Rootfs runtime version is invalid."
            }
            return CompatibilityRootfsManifest(
                archiveName = archiveName,
                archiveBytes = archiveBytes,
                archiveSha256 = digest,
                memberCount = artifact.getInt("members"),
                regularFileCount = artifact.getInt("regular_files"),
                unpackedBytes = artifact.getLong("unpacked_bytes"),
                runtimeVersion = runtimeVersion,
                nodeVersion = nodeVersion,
                codexVersion = codexVersion,
            )
        }

        const val MAX_MANIFEST_BYTES = 64 * 1024
        const val MAX_ARCHIVE_BYTES = 2L * 1024L * 1024L * 1024L
        const val MAX_UNPACKED_BYTES = 8L * 1024L * 1024L * 1024L
        const val MAX_ARCHIVE_ENTRIES = 200_000
    }
}
