package io.henry.codex

import android.content.Context
import java.nio.charset.StandardCharsets

/** Loads the single bundled Android runtime guide used to seed each CODEX_HOME. */
internal object AndroidCodexAgentGuide {
    private const val ASSET_PATH = "AGENTS.md"

    fun read(context: Context): String =
        context.assets.open(ASSET_PATH).bufferedReader(StandardCharsets.UTF_8).use { reader ->
            reader.readText().also { content ->
                require(content.isNotBlank()) { "Bundled Android Codex guidance is empty." }
            }
        }
}
