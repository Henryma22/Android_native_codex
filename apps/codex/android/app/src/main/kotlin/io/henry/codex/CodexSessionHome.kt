package io.henry.codex

import java.io.File
import java.nio.charset.StandardCharsets
import java.nio.file.FileAlreadyExistsException
import java.nio.file.Files
import java.nio.file.LinkOption
import java.nio.file.StandardOpenOption
import org.json.JSONObject

/**
 * Gives every app-server process its own Codex state directory.
 *
 * Codex's Android writer-lock implementation intentionally cannot use flock
 * on the platform data filesystem. Sharing CODEX_HOME between two app-server
 * processes therefore lets the second process treat the first process's
 * writer locks as stale. The session directory is isolated, while the small
 * set of account/configuration files is copied from the shared login home.
 */
internal object CodexSessionHome {
    private const val SESSION_DIRECTORY = "sessions"
    private const val SESSION_LAYOUT_MARKER = ".android-session-layout"
    private const val SESSION_LAYOUT_VERSION = "2"
    private const val MODEL_CATALOG_FILE = "models.json"
    private const val MAX_CUSTOM_MODEL_CATALOG_BYTES = 64 * 1024
    const val MODEL_CATALOG_ENVIRONMENT_VARIABLE =
        "ANDROID_CODEX_CUSTOM_MODEL_CATALOG_JSON"
    private val SAFE_SESSION_ID = Regex("[A-Za-z0-9._-]{1,128}")
    private val SEED_FILES = listOf(
        "auth.json",
        ".credentials.json",
        "config.toml",
    )

    /** Prepares `/home/codex/sessions/<id>` in the bound compatibility home. */
    fun prepareCompatibility(
        baseHome: File,
        requestedHome: String?,
        guestHome: String = "/home/codex/sessions",
        instructions: String? = null,
        preserveModelsCache: Boolean = false,
        customModelCatalogJson: String? = null,
    ) {
        val target = resolveGuest(baseHome, requestedHome, guestHome) ?: return
        prepare(baseHome, target, instructions, preserveModelsCache, customModelCatalogJson)
    }

    fun modelCatalogFromEnvironment(environment: Map<String, String>): String? =
        environment[MODEL_CATALOG_ENVIRONMENT_VARIABLE]

    fun childEnvironment(environment: Map<String, String>): Map<String, String> =
        environment.filterKeys { it != MODEL_CATALOG_ENVIRONMENT_VARIABLE }

    /** Returns the disposable model-cache path for a validated guest home. */
    fun compatibilityModelsCachePath(
        baseHome: File,
        requestedHome: String?,
        guestHome: String = "/home/codex/sessions",
    ): File? {
        val target = resolveGuest(baseHome, requestedHome, guestHome) ?: return null
        return File(target.canonicalFile, "models_cache.json")
    }

    /** Returns true when App UID removed a cache or can prove it is absent. */
    fun tryRemoveModelsCacheAsApp(cache: File): Boolean {
        if (cache.delete()) return true
        return Files.notExists(cache.toPath(), LinkOption.NOFOLLOW_LINKS)
    }

    private fun prepare(
        baseHome: File,
        target: File,
        instructions: String?,
        preserveModelsCache: Boolean,
        customModelCatalogJson: String?,
    ) {
        val canonicalBase = baseHome.canonicalFile
        require(!Files.isSymbolicLink(baseHome.toPath())) {
            "Codex runtime home must not be a symbolic link"
        }
        require(canonicalBase.exists() && canonicalBase.isDirectory) {
            "Codex runtime home is unavailable"
        }

        val sessions = File(canonicalBase, SESSION_DIRECTORY).canonicalFile
        require(sessions.mkdirs() || sessions.isDirectory) {
            "Codex session home directory is unavailable"
        }
        require(!Files.isSymbolicLink(sessions.toPath())) {
            "Codex session home directory must not be a symbolic link"
        }

        val canonicalTarget = target.canonicalFile
        require(canonicalTarget.parentFile == sessions) {
            "Codex session home escaped the runtime home"
        }
        require(SAFE_SESSION_ID.matches(canonicalTarget.name)) {
            "Codex session home id is invalid"
        }
        require(!Files.isSymbolicLink(target.toPath())) {
            "Codex session home must not be a symbolic link"
        }
        require(target.mkdirs() || target.isDirectory) {
            "Codex session home is unavailable"
        }
        val state = File(target, "state")
        require(state.mkdirs() || state.isDirectory) {
            "Codex session state directory is unavailable"
        }
        require(!Files.isSymbolicLink(state.toPath())) {
            "Codex session state directory must not be a symbolic link"
        }
        val tmp = File(target, "tmp")
        require(tmp.mkdirs() || tmp.isDirectory) {
            "Codex session temp directory is unavailable"
        }
        require(!Files.isSymbolicLink(tmp.toPath())) {
            "Codex session temp directory must not be a symbolic link"
        }
        val log = File(target, "log")
        require(log.mkdirs() || log.isDirectory) {
            "Codex session log directory is unavailable"
        }
        require(!Files.isSymbolicLink(log.toPath())) {
            "Codex session log directory must not be a symbolic link"
        }

        // A model catalog is derived data. App-UID sessions remove the old
        // copy so a root-owned cache cannot become an app-session permission
        // error; Root sessions keep it as an offline starting point and let
        // the installed CLI refresh it in the background. The shared login
        // home is deliberately left alone here because another operation may
        // still be reading it.
        discardDerivedState(canonicalTarget, preserveModelsCache)

        for (name in SEED_FILES) {
            // Login commands intentionally omit CODEX_HOME, so the Codex CLI
            // stores shared credentials/configuration in $HOME/.codex. A
            // conversation sets CODEX_HOME to the isolated session root and
            // therefore expects these same files directly below that root.
            // Also accept a direct base-home file for runtimes that were
            // already launched with CODEX_HOME set. The newest valid source
            // wins when both layouts exist.
            val source = seedSource(canonicalBase, name) ?: continue
            val destination = File(target, name)
            if (destination.exists() && Files.isSymbolicLink(destination.toPath())) {
                continue
            }
            if (!destination.exists() || source.lastModified() > destination.lastModified()) {
                source.copyTo(destination, overwrite = true)
                destination.setLastModified(source.lastModified())
            }
        }

        if (preserveModelsCache) {
            val source = seedSource(canonicalBase, "models_cache.json")
            val destination = File(canonicalTarget, "models_cache.json")
            if (source != null &&
                !destination.exists() &&
                !Files.isSymbolicLink(destination.toPath())
            ) {
                source.copyTo(destination, overwrite = false)
                destination.setLastModified(source.lastModified())
            }
        }

        writeCustomModelCatalog(canonicalTarget, customModelCatalogJson)
        seedAgentInstructions(canonicalTarget, instructions)
    }

    private fun writeCustomModelCatalog(home: File, json: String?) {
        if (json == null) return
        val bytes = json.toByteArray(StandardCharsets.UTF_8)
        require(bytes.isNotEmpty() && bytes.size <= MAX_CUSTOM_MODEL_CATALOG_BYTES) {
            "Codex custom model catalog is empty or too large"
        }
        val models = runCatching { JSONObject(json).optJSONArray("models") }
            .getOrNull()
        require(models != null && models.length() == 1) {
            "Codex custom model catalog must contain exactly one model"
        }
        val destination = File(home, MODEL_CATALOG_FILE)
        require(!Files.isSymbolicLink(destination.toPath())) {
            "Codex custom model catalog must not be a symbolic link"
        }
        Files.newOutputStream(
            destination.toPath(),
            StandardOpenOption.CREATE,
            StandardOpenOption.TRUNCATE_EXISTING,
            StandardOpenOption.WRITE,
        ).use { it.write(bytes) }
    }

    private fun seedSource(baseHome: File, name: String): File? = sequenceOf(
        File(baseHome, name),
        File(File(baseHome, ".codex"), name),
    ).filter { candidate ->
        candidate.isFile && !Files.isSymbolicLink(candidate.toPath())
    }.maxByOrNull(File::lastModified)

    /** Seeds Codex global guidance once, without replacing session/user edits. */
    private fun seedAgentInstructions(home: File, instructions: String?) {
        val content = instructions?.takeIf(String::isNotBlank) ?: return
        val destination = File(home, "AGENTS.md")
        val path = destination.toPath()
        if (Files.exists(path, LinkOption.NOFOLLOW_LINKS)) return

        try {
            Files.newOutputStream(
                path,
                StandardOpenOption.CREATE_NEW,
                StandardOpenOption.WRITE,
            ).use { output ->
                output.write(content.toByteArray(StandardCharsets.UTF_8))
            }
        } catch (_: FileAlreadyExistsException) {
            // A concurrently starting process or user-created file wins.
        }
    }

    private fun discardDerivedState(home: File, preserveModelsCache: Boolean) {
        val legacyCache = File(home, "models_cache.json")
        // File.delete() removes a legacy symlink itself rather than following
        // it. Failure is deliberately best-effort: a root-owned cache must
        // not prevent a new session from starting, and the CLI can still
        // report a cache miss instead of using the file as account state.
        runCatching {
            if (Files.isSymbolicLink(legacyCache.toPath())) {
                legacyCache.delete()
            } else if (!preserveModelsCache && legacyCache.exists()) {
                legacyCache.delete()
            }
        }

        val marker = File(home, SESSION_LAYOUT_MARKER)
        if (Files.isSymbolicLink(marker.toPath())) {
            runCatching { marker.delete() }
        }
        runCatching {
            marker.writeText(SESSION_LAYOUT_VERSION, Charsets.UTF_8)
        }
    }

    private fun resolveGuest(
        baseHome: File,
        requestedHome: String?,
        guestHome: String,
    ): File? {
        val value = requestedHome?.trim().orEmpty()
        val prefix = guestHome.trimEnd('/') + "/"
        if (!value.startsWith(prefix)) return null
        val id = value.removePrefix(prefix)
        if (!SAFE_SESSION_ID.matches(id)) return null
        return File(File(baseHome.canonicalFile, SESSION_DIRECTORY), id)
    }
}
