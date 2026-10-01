package io.henry.codex

import android.annotation.TargetApi
import android.Manifest
import android.content.pm.PackageManager
import android.app.KeyguardManager
import android.hardware.biometrics.BiometricManager
import android.hardware.biometrics.BiometricPrompt
import android.os.Build
import android.os.CancellationSignal
import android.util.Base64
import android.util.Log
import android.content.Intent
import android.app.Activity
import android.content.ActivityNotFoundException
import android.net.Uri
import android.provider.Settings
import android.os.Environment
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.io.OutputStreamWriter
import java.nio.charset.StandardCharsets
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.spec.GCMParameterSpec
import java.nio.file.Files
import java.nio.file.LinkOption
import java.nio.file.AtomicMoveNotSupportedException
import java.nio.file.StandardCopyOption
import java.security.MessageDigest
import java.util.concurrent.TimeUnit
import java.util.Locale
import java.util.UUID
import kotlin.concurrent.thread
import org.json.JSONArray
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    private lateinit var hostProcessManager: HostProcessManager
    private val compatibilityProcessManager by lazy {
        CompatibilityProcessRuntime.manager(this)
    }
    private val compatibilityRootfsInstaller by lazy {
        CompatibilityRootfsInstaller(this, ROOT_HELPER_CANDIDATES) {
            probeLinuxCompatibilityRuntime()
        }
    }
    private val safWorkspaceStore by lazy { SafWorkspaceStore(this) }
    private val kernelSuPluginBridge by lazy { KernelSuPluginBridge(this) }
    private var pendingSafPickerResult: MethodChannel.Result? = null
    private var pendingCompatibilityRootfsPickerResult: MethodChannel.Result? = null
    private var pendingImagePickerResult: MethodChannel.Result? = null
    private var pendingKernelSuPluginPickerResult: MethodChannel.Result? = null
    private var pendingKernelSuCredentialResult: MethodChannel.Result? = null
    private var pendingKernelSuCredentialCall: MethodCall? = null
    private var pendingKernelSuCredentialPrompt: BiometricPrompt? = null
    private var pendingSessionNotificationPermissionResult: MethodChannel.Result? = null

    private companion object {
        const val PROBE_CHANNEL = "io.henry.codex/native_probe"
        const val KERNELSU_PLUGIN_CHANNEL = "io.henry.codex/kernelsu_plugin"
        const val BROWSER_CHANNEL = "io.henry.codex/browser"
        const val LINUX_COMPATIBILITY_RUNTIME_CHANNEL =
            "io.henry.codex/linux_compatibility_runtime"
        const val LOCAL_BACKEND_CHANNEL = "io.henry.codex/local_backend"
        const val SESSION_HISTORY_CHANNEL = "io.henry.codex/session_history"
        const val APP_PREFERENCES_CHANNEL = "io.henry.codex/app_preferences"
        const val HOST_EVENTS_CHANNEL = "io.henry.codex/host_events"
        const val LINUX_COMPATIBILITY_EVENTS_CHANNEL =
            "io.henry.codex/linux_compatibility_events"
        const val COMMAND_TIMEOUT_SECONDS = 3L
        const val HOST_WORKSPACE_ROOT = "/storage/emulated/0/Codex/Workspaces"
        const val MAX_HOST_TEXT_BYTES = 1024 * 1024
        const val MAX_BACKUP_BYTES = MAX_HOST_TEXT_BYTES * 2
        const val MAX_BACKUP_RECORDS = 200
        const val BACKUP_DIRECTORY = "codex/backups"
        const val SAF_BACKUP_DIRECTORY = "codex/saf-backups"
        const val SAF_PICK_REQUEST_CODE = 4301
        const val COMPATIBILITY_ROOTFS_PICK_REQUEST_CODE = 4308
        const val SESSION_NOTIFICATION_PERMISSION_REQUEST_CODE = 4304
        const val IMAGE_PICK_REQUEST_CODE = 4305
        const val KERNELSU_PLUGIN_PICK_REQUEST_CODE = 4307
        const val PROOT_ASSET_NAME = "libcodex_proot.so"
        const val PROOT_LOADER_ASSET_NAME = "libcodex_proot_loader.so"
        const val PROOT_HOST_TRAMPOLINE_ASSET_NAME = "libcodex_host_trampoline.so"
        const val PROVIDER_KEY_ALIAS = "io.henry.codex.custom-provider"
        const val MAX_IMAGE_BYTES = 8L * 1024L * 1024L
        const val MAX_IMAGE_COUNT = 4
        const val MAX_IMAGE_TOTAL_BYTES = 24L * 1024L * 1024L
        const val MAX_KERNELSU_PLUGIN_ARCHIVE_BYTES = 32L * 1024L * 1024L
        val ROOT_HELPER_CANDIDATES = listOf(
            "/data/adb/ksu/bin/su",
            "/system/bin/su",
            "/system/xbin/su",
        )
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val sessionHistoryStore = SessionHistoryStore(filesDir)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PROBE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "probeRootProfile" -> thread(name = "codex-root-profile-probe") {
                        val response = AndroidRootProfileProbe(this).run()
                        runOnUiThread { result.success(response) }
                    }
                    // A status adapter for persisted local-backend records.
                    // No native CLI scan, worker, or probe thread is needed.
                    "probeCodexRuntime" -> result.success(mapOf(
                        "state" to "missing",
                        "reason" to "Direct Android Codex is retired; use the local Linux/PRoot runtime.",
                    ))
                    "probeAppHostAccess" -> result.success(probeAppHostAccess())
                    "openHostAccessSettings" -> {
                        try {
                            openHostAccessSettings()
                            result.success(null)
                        } catch (error: ActivityNotFoundException) {
                            result.error(
                                "host_access_settings_unavailable",
                                "Android storage access settings are unavailable.",
                                null,
                            )
                        } catch (error: IllegalStateException) {
                            result.error(
                                "host_access_settings_unsupported",
                                error.message,
                                null,
                            )
                        }
                    }
                    "pickImages" -> startImagePicker(result)
                    else -> result.notImplemented()
                }
            }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            KERNELSU_PLUGIN_CHANNEL,
        ).setMethodCallHandler { call, result ->
            if (call.method == "pickArchive") {
                startKernelSuPluginPicker(result)
                return@setMethodCallHandler
            }
            dispatchKernelSuPluginCall(call, result)
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BROWSER_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openExternalUrl" -> {
                        val rawUrl = call.argument<String>("url")?.trim().orEmpty()
                        val uri = try {
                            Uri.parse(rawUrl)
                        } catch (_: IllegalArgumentException) {
                            null
                        }
                        val allowedPath = uri?.path?.trimEnd('/') in setOf(
                            "/device",
                            "/codex/device",
                            "/oauth/authorize",
                        )
                        if (uri == null ||
                            uri.scheme?.lowercase(Locale.ROOT) != "https" ||
                            uri.host?.lowercase(Locale.ROOT) != "auth.openai.com" ||
                            uri.port > 0 && uri.port != 443 ||
                            !allowedPath
                        ) {
                            result.error(
                                "invalid_auth_url",
                                "Only verified OpenAI authentication URLs can be opened.",
                                null,
                            )
                            return@setMethodCallHandler
                        }
                        try {
                            startActivity(Intent(Intent.ACTION_VIEW, uri))
                            result.success(true)
                        } catch (_: ActivityNotFoundException) {
                            result.error(
                                "browser_unavailable",
                                "No browser is available to open the login page.",
                                null,
                            )
                        }
                    }
                    "openMcpExternalUrl" -> {
                        val rawUrl = call.argument<String>("url")?.trim().orEmpty()
                        val uri = try {
                            Uri.parse(rawUrl)
                        } catch (_: IllegalArgumentException) {
                            null
                        }
                        val scheme = uri?.scheme?.lowercase(Locale.ROOT)
                        val host = uri?.host?.lowercase(Locale.ROOT)
                        val port = uri?.port ?: -1
                        val isHttps = scheme == "https" &&
                            !host.isNullOrBlank() &&
                            port in setOf(-1, 443)
                        val isLoopbackHttp = scheme == "http" &&
                            host in setOf("localhost", "127.0.0.1", "::1") &&
                            port in -1..65535
                        if (rawUrl.length > 2048 ||
                            uri == null ||
                            uri.userInfo != null ||
                            !(isHttps || isLoopbackHttp)
                        ) {
                            result.error(
                                "invalid_mcp_url",
                                "Only HTTPS or loopback HTTP URLs can be opened.",
                                null,
                            )
                            return@setMethodCallHandler
                        }
                        try {
                            startActivity(Intent(Intent.ACTION_VIEW, uri))
                            result.success(true)
                        } catch (_: ActivityNotFoundException) {
                            result.error(
                                "browser_unavailable",
                                "No browser is available to open the MCP URL.",
                                null,
                            )
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            LINUX_COMPATIBILITY_RUNTIME_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickAndInstallRootfs" -> startCompatibilityRootfsPicker(result)
                "probe" -> thread(name = "codex-compatibility-probe") {
                    val response = probeLinuxCompatibilityRuntime()
                    runOnUiThread { result.success(response) }
                }
                "startProcess" -> {
                    try {
                        val argv = call.argument<List<String>>("argv") ?: emptyList()
                        val cwd = call.argument<String>("cwd") ?: ""
                        val identity = call.argument<String>("identity") ?: "app"
                        val timeoutMs = call.argument<Number>("timeoutMs")?.toLong() ?: 120_000L
                        val environment = call.argument<Map<*, *>>("environment")
                            ?.mapNotNull { (key, value) ->
                                if (key is String && value is String) key to value else null
                            }
                            ?.toMap()
                            ?: emptyMap()
                        thread(name = "codex-compat-process-start") {
                            try {
                                val processId = compatibilityProcessManager.start(
                                    proot = compatibilityProotAsset(),
                                    loader = compatibilityProotLoaderAsset(),
                                    trampoline = compatibilityProotTrampolineAsset(),
                                    argv = argv,
                                    cwd = cwd,
                                    identity = identity,
                                    timeoutMs = timeoutMs,
                                    requestedEnvironment = environment,
                                )
                                runOnUiThread { result.success(processId) }
                            } catch (error: Exception) {
                                runOnUiThread {
                                    result.error(
                                        "compatibility_process_failed",
                                        error.message,
                                        null,
                                    )
                                }
                            }
                        }
                    } catch (error: Exception) {
                        result.error("compatibility_process_failed", error.message, null)
                    }
                }
                "attachProcess" -> {
                    try {
                        compatibilityProcessManager.attach(call.argument<String>("processId") ?: "")
                        result.success(null)
                    } catch (error: Exception) {
                        result.error("compatibility_process_failed", error.message, null)
                    }
                }
                "writeProcess" -> {
                    try {
                        compatibilityProcessManager.write(
                            call.argument<String>("processId") ?: "",
                            call.argument<String>("value") ?: "",
                        )
                        result.success(null)
                    } catch (error: Exception) {
                        result.error("compatibility_process_failed", error.message, null)
                    }
                }
                "closeProcessStdin" -> {
                    try {
                        compatibilityProcessManager.closeStdin(
                            call.argument<String>("processId") ?: "",
                        )
                        result.success(null)
                    } catch (error: Exception) {
                        result.error("compatibility_process_failed", error.message, null)
                    }
                }
                "stopProcess" -> {
                    val processId = call.argument<String>("processId") ?: ""
                    thread(name = "codex-compat-process-stop") {
                        try {
                            compatibilityProcessManager.stop(processId)
                            runOnUiThread { result.success(null) }
                        } catch (error: Exception) {
                            runOnUiThread {
                                result.error(
                                    "compatibility_process_failed",
                                    error.message,
                                    null,
                                )
                            }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            LINUX_COMPATIBILITY_EVENTS_CHANNEL,
        ).setStreamHandler(compatibilityProcessManager)
        val binaryMessenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(
            binaryMessenger,
            SESSION_HISTORY_CHANNEL,
            StandardMethodCodec.INSTANCE,
            // History reads and atomic JSON writes can be large. Keep this
            // channel serialized, but do not run its codec or disk I/O on the
            // Android UI thread.
            binaryMessenger.makeBackgroundTaskQueue(),
        ).setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "loadSessionHistory" -> {
                            val key = call.argument<String>("key") ?: ""
                            result.success(sessionHistoryStore.load(key))
                        }

                        "listSessionHistories" -> {
                            result.success(sessionHistoryStore.list())
                        }

                        "saveSessionHistory" -> {
                            val key = call.argument<String>("key") ?: ""
                            val record = call.argument<Map<*, *>>("record") ?: emptyMap<Any, Any>()
                            sessionHistoryStore.save(key, record)
                            result.success(null)
                        }

                        "updateSessionHistoryFlags" -> {
                            val key = call.argument<String>("key") ?: ""
                            sessionHistoryStore.updateFlags(
                                key = key,
                                pinned = call.argument<Boolean>("pinned"),
                            )
                            result.success(null)
                        }

                        "updateSessionHistoryTitle" -> {
                            val key = call.argument<String>("key") ?: ""
                            sessionHistoryStore.updateTitle(
                                key = key,
                                title = call.argument<String>("title"),
                            )
                            result.success(null)
                        }

                        "clearSessionHistory" -> {
                            val key = call.argument<String>("key") ?: ""
                            sessionHistoryStore.clear(key)
                            result.success(null)
                        }

                        "clearAllSessionHistories" -> {
                            sessionHistoryStore.clearAll()
                            result.success(null)
                        }

                        else -> result.notImplemented()
                    }
                } catch (error: Exception) {
                    result.error("history_failed", error.message, null)
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, APP_PREFERENCES_CHANNEL)
            .setMethodCallHandler { call, result ->
                try {
                    val preferences = getSharedPreferences(
                        "codex_preferences",
                        MODE_PRIVATE,
                    )
                    when (call.method) {
                        "loadAppSettings" -> result.success(
                            mapOf(
                                "themeMode" to preferences.getString(
                                    "theme_mode",
                                    "system",
                                ),
                                "locale" to preferences.getString(
                                    "locale",
                                    "zh",
                                ),
                                "compatibilityCliVersion" to preferences.getString(
                                    "compatibility_cli_version",
                                    null,
                                ),
                                "codexModel" to preferences.getString(
                                    "codex_model",
                                    "gpt-6-luna",
                                ),
                                "codexEffort" to preferences.getString(
                                    "codex_effort",
                                    "low",
                                ),
                                "codexApprovalPolicy" to preferences.getString(
                                    "codex_approval_policy",
                                    "never",
                                ),
                                "codexSandbox" to preferences.getString(
                                    "codex_sandbox",
                                    "danger-full-access",
                                ),
                            ),
                        )

                        "saveAppSettings" -> {
                            val themeMode = call.argument<String>("themeMode")
                            val locale = call.argument<String>("locale")
                            val compatibilityCliVersion =
                                call.argument<String>("compatibilityCliVersion")
                            val codexModel = call.argument<String>("codexModel")?.trim()
                            val codexEffort = call.argument<String>("codexEffort")
                            val codexApprovalPolicy =
                                call.argument<String>("codexApprovalPolicy")
                            val codexSandbox = call.argument<String>("codexSandbox")
                            if (themeMode !in setOf("system", "light", "dark")) {
                                result.error(
                                    "invalid_theme_mode",
                                    "Unsupported theme mode.",
                                    null,
                                )
                            } else if (locale !in setOf("system", "zh", "en")) {
                                result.error(
                                    "invalid_locale",
                                    "Unsupported locale.",
                                    null,
                                )
                            } else if (codexModel.isNullOrBlank() || codexModel.length > 256) {
                                result.error(
                                    "invalid_codex_model",
                                    "A non-empty Codex model id is required.",
                                    null,
                                )
                            } else if (codexEffort !in setOf(
                                    "none",
                                    "minimal",
                                    "low",
                                    "medium",
                                    "high",
                                    "xhigh",
                                    "max",
                                    "ultra",
                                )
                            ) {
                                result.error(
                                    "invalid_codex_effort",
                                    "Unsupported Codex reasoning effort.",
                                    null,
                                )
                            } else if (codexApprovalPolicy !in setOf(
                                    "on-request",
                                    "on-failure",
                                    "never",
                                )
                            ) {
                                result.error(
                                    "invalid_codex_approval_policy",
                                    "Unsupported Codex approval policy.",
                                    null,
                                )
                            } else if (codexSandbox !in setOf(
                                    "workspace-write",
                                    "read-only",
                                    "danger-full-access",
                                )
                            ) {
                                result.error(
                                    "invalid_codex_sandbox",
                                    "Unsupported Codex sandbox mode.",
                                    null,
                                )
                            } else {
                                preferences.edit()
                                    .putString("theme_mode", themeMode)
                                    .putString("locale", locale)
                                    .putString(
                                        "compatibility_cli_version",
                                        compatibilityCliVersion,
                                    )
                                    .putString("codex_model", codexModel)
                                    .putString("codex_effort", codexEffort)
                                    .putString(
                                        "codex_approval_policy",
                                        codexApprovalPolicy,
                                    )
                                    .putString("codex_sandbox", codexSandbox)
                                    .apply()
                                result.success(null)
                            }
                        }

                        "loadPreferredBackendId" -> result.success(
                            preferences.getString("preferred_backend_id", null),
                        )

                        "savePreferredBackendId" -> {
                            val backendId = call.argument<String>("backendId")
                            if (backendId !in setOf("local-android", "linux-compatibility")) {
                                result.error(
                                    "invalid_backend_id",
                                    "Unsupported local backend id.",
                                    null,
                                )
                            } else {
                                preferences.edit()
                                    .putString("preferred_backend_id", backendId)
                                    .apply()
                                result.success(null)
                            }
                        }

                        "loadAuthGeneration" -> result.success(
                            preferences.getLong("auth_generation", 1L).coerceAtLeast(1L),
                        )

                        "advanceAuthGeneration" -> {
                            val next = preferences.getLong("auth_generation", 1L)
                                .coerceAtLeast(1L) + 1L
                            preferences.edit()
                                .putLong("auth_generation", next)
                                .apply()
                            result.success(next)
                        }

                        "loadCustomProviders" -> result.success(loadCustomProviders())

                        "saveCustomProvider" -> {
                            val value = call.arguments as? Map<*, *>
                                ?: throw IllegalArgumentException("Provider config is missing.")
                            saveCustomProvider(value)
                            result.success(null)
                        }

                        "deleteCustomProvider" -> {
                            deleteCustomProvider(call.argument<String>("id") ?: "")
                            result.success(null)
                        }

                        "loadActiveProviderId" -> result.success(
                            preferences.getString("active_custom_provider_id", null),
                        )

                        "saveActiveProviderId" -> {
                            val id = call.argument<String>("id")?.trim().orEmpty()
                            preferences.edit()
                                .putString("active_custom_provider_id", id.ifEmpty { null })
                                .apply()
                            result.success(null)
                        }

                        "loadModelProviderMode" -> result.success(
                            preferences.getString("model_provider_mode", null),
                        )

                        "saveModelProviderMode" -> {
                            val mode = call.argument<String>("mode")?.trim().orEmpty()
                            if (mode == "openai" || mode == "third_party") {
                                preferences.edit()
                                    .putString("model_provider_mode", mode)
                                    .apply()
                            } else {
                                preferences.edit().remove("model_provider_mode").apply()
                            }
                            result.success(null)
                        }

                        "loadCodexModelCatalogCache" -> result.success(
                            preferences.getString("codex_model_catalog_cache", null),
                        )

                        "saveCodexModelCatalogCache" -> {
                            val catalog = call.argument<String>("catalog")
                            if (catalog.isNullOrBlank() || catalog.length > 128 * 1024) {
                                result.error(
                                    "invalid_model_catalog_cache",
                                    "The Codex model catalog cache is empty or too large.",
                                    null,
                                )
                            } else {
                                preferences.edit()
                                    .putString("codex_model_catalog_cache", catalog)
                                    .apply()
                                result.success(null)
                            }
                        }

                        "loadHttpProxyEndpoint" -> result.success(
                            preferences.getString(
                                CompatibilityNetworkConfiguration.HTTP_PROXY_PREFERENCE_KEY,
                                "",
                            ).orEmpty(),
                        )

                        "saveHttpProxyEndpoint" -> {
                            val value = call.argument<String>("endpoint").orEmpty().trim()
                            if (value.isEmpty()) {
                                preferences.edit()
                                    .remove(CompatibilityNetworkConfiguration.HTTP_PROXY_PREFERENCE_KEY)
                                    .apply()
                                result.success(null)
                            } else {
                                val endpoint = CompatibilityNetworkConfiguration
                                    .parseHttpProxyEndpoint(value)
                                if (endpoint == null) {
                                    result.error(
                                        "invalid_http_proxy_endpoint",
                                        "Enter an HTTP proxy as host:port or [IPv6]:port.",
                                        null,
                                    )
                                } else {
                                    preferences.edit()
                                        .putString(
                                            CompatibilityNetworkConfiguration.HTTP_PROXY_PREFERENCE_KEY,
                                            endpoint.normalized,
                                        )
                                        .apply()
                                    result.success(null)
                                }
                            }
                        }

                        else -> result.notImplemented()
                    }
                } catch (error: Exception) {
                    result.error("preferences_failed", error.message, null)
                }
            }
        hostProcessManager = HostProcessRuntime.manager(this)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, HOST_EVENTS_CHANNEL)
            .setStreamHandler(hostProcessManager)
        // Host and SAF filesystem calls may block on storage providers. Keep
        // them ordered on a background queue; picker and service actions hop
        // back to the Activity thread below.
        MethodChannel(
            binaryMessenger,
            LOCAL_BACKEND_CHANNEL,
            StandardMethodCodec.INSTANCE,
            binaryMessenger.makeBackgroundTaskQueue(),
        ).setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "listHostDirectory" -> {
                            val relativePath = call.argument<String>("relativePath") ?: ""
                            result.success(listHostDirectory(relativePath))
                        }

                        "createHostWorkspace" -> {
                            result.success(
                                createHostWorkspace(call.argument<String>("name") ?: ""),
                            )
                        }

                        "deleteHostWorkspace" -> {
                            deleteHostWorkspace(call.argument<String>("name") ?: "")
                            result.success(null)
                        }

                        "listSafWorkspaces" -> {
                            result.success(safWorkspaceStore.listWorkspaces())
                        }

                        "pickSafWorkspace" -> {
                            runOnUiThread { startSafWorkspacePicker(result) }
                        }

                        "forgetSafWorkspace" -> {
                            safWorkspaceStore.forgetTree(call.argument<String>("uri") ?: "")
                            result.success(null)
                        }

                        "listSafDirectory" -> {
                            result.success(
                                safWorkspaceStore.listDirectory(
                                    call.argument<String>("uri") ?: "",
                                    call.argument<String>("relativePath") ?: "",
                                ),
                            )
                        }

                        "readSafText" -> {
                            result.success(
                                safWorkspaceStore.readText(
                                    call.argument<String>("uri") ?: "",
                                    call.argument<String>("relativePath") ?: "",
                                ),
                            )
                        }

                        "snapshotSafText" -> {
                            result.success(
                                safWorkspaceStore.snapshot(
                                    call.argument<String>("uri") ?: "",
                                    call.argument<String>("relativePath") ?: "",
                                ),
                            )
                        }

                        "writeSafText" -> {
                            result.success(
                                safWorkspaceStore.writeText(
                                    call.argument<String>("uri") ?: "",
                                    call.argument<String>("relativePath") ?: "",
                                    call.argument<String>("expectedVersion") ?: "",
                                    call.argument<String>("content") ?: "",
                                ),
                            )
                        }

                        "backupSafText" -> {
                            result.success(
                                safWorkspaceStore.backupText(
                                    call.argument<String>("uri") ?: "",
                                    call.argument<String>("relativePath") ?: "",
                                    call.argument<String>("expectedVersion") ?: "",
                                ),
                            )
                        }

                        "restoreSafText" -> {
                            result.success(
                                safWorkspaceStore.restoreText(
                                    call.argument<String>("uri") ?: "",
                                    call.argument<String>("relativePath") ?: "",
                                    call.argument<String>("backupId") ?: "",
                                    call.argument<String>("expectedVersion") ?: "",
                                ),
                            )
                        }

                        "readHostText" -> {
                            val workspacePath = call.argument<String>("workspacePath") ?: ""
                            val relativePath = call.argument<String>("relativePath") ?: ""
                            result.success(readHostText(workspacePath, relativePath))
                        }

                        "snapshotHostText" -> {
                            val workspacePath = call.argument<String>("workspacePath") ?: ""
                            val relativePath = call.argument<String>("relativePath") ?: ""
                            result.success(snapshotHostText(workspacePath, relativePath))
                        }

                        "writeHostText" -> {
                            val workspacePath = call.argument<String>("workspacePath") ?: ""
                            val relativePath = call.argument<String>("relativePath") ?: ""
                            val expectedVersion = call.argument<String>("expectedVersion") ?: ""
                            val content = call.argument<String>("content") ?: ""
                            result.success(
                                writeHostText(
                                    workspacePath,
                                    relativePath,
                                    expectedVersion,
                                    content,
                                ),
                            )
                        }

                        "backupHostText" -> {
                            val workspacePath = call.argument<String>("workspacePath") ?: ""
                            val relativePath = call.argument<String>("relativePath") ?: ""
                            val expectedVersion = call.argument<String>("expectedVersion") ?: ""
                            result.success(
                                backupHostText(
                                    workspacePath,
                                    relativePath,
                                    expectedVersion,
                                ),
                            )
                        }

                        "restoreHostText" -> {
                            val workspacePath = call.argument<String>("workspacePath") ?: ""
                            val relativePath = call.argument<String>("relativePath") ?: ""
                            val backupId = call.argument<String>("backupId") ?: ""
                            val expectedVersion = call.argument<String>("expectedVersion") ?: ""
                            result.success(
                                restoreHostText(
                                    workspacePath,
                                    relativePath,
                                    backupId,
                                    expectedVersion,
                                ),
                            )
                        }

                        "listBackups" -> {
                            result.success(listBackups())
                        }

                        "startHostProcess" -> {
                            val argv = call.argument<List<String>>("argv") ?: emptyList()
                            val cwd = call.argument<String>("cwd") ?: HOST_WORKSPACE_ROOT
                            val identity = call.argument<String>("identity") ?: "app"
                            val timeoutMs = call.argument<Number>("timeoutMs")?.toLong() ?: 120_000L
                            val environment = call.argument<Map<*, *>>("environment")
                                ?.mapNotNull { (key, value) ->
                                    if (key is String && value is String) key to value else null
                                }
                                ?.toMap()
                                ?: emptyMap()
                            thread(name = "codex-host-process-start") {
                                try {
                                    val processId = hostProcessManager.start(
                                        argv,
                                        cwd,
                                        identity,
                                        timeoutMs,
                                        environment,
                                    )
                                    runOnUiThread { result.success(processId) }
                                } catch (error: Exception) {
                                    val errorCode = when {
                                        identity == "root" -> "root_profile_rejected"
                                        error is HostBackendException -> error.code
                                        error is SafWorkspaceException -> error.code
                                        else -> "operation_failed"
                                    }
                                    runOnUiThread {
                                        result.error(errorCode, error.message, null)
                                    }
                                }
                            }
                        }

                        "attachHostProcess" -> {
                            hostProcessManager.attach(call.argument<String>("processId") ?: "")
                            result.success(null)
                        }

                        "writeHostProcess" -> {
                            hostProcessManager.write(
                                call.argument<String>("processId") ?: "",
                                call.argument<String>("value") ?: "",
                            )
                            result.success(null)
                        }

                        "closeHostProcessStdin" -> {
                            hostProcessManager.closeStdin(
                                call.argument<String>("processId") ?: "",
                            )
                            result.success(null)
                        }

                        "stopHostProcess" -> {
                            val processId = call.argument<String>("processId") ?: ""
                            thread(name = "codex-host-process-stop") {
                                try {
                                    hostProcessManager.stop(processId)
                                    runOnUiThread { result.success(null) }
                                } catch (error: Exception) {
                                    runOnUiThread {
                                        result.error(
                                            "operation_failed",
                                            error.message,
                                            null,
                                        )
                                    }
                                }
                            }
                        }

                        "startSessionForeground" -> {
                            runOnUiThread {
                                try {
                                    startSessionForeground()
                                    result.success(null)
                                } catch (error: Exception) {
                                    result.error("operation_failed", error.message, null)
                                }
                            }
                        }

                        "stopSessionForeground" -> {
                            runOnUiThread {
                                try {
                                    stopSessionForeground()
                                    result.success(null)
                                } catch (error: Exception) {
                                    result.error("operation_failed", error.message, null)
                                }
                            }
                        }

                        "requestSessionNotificationPermission" -> {
                            runOnUiThread {
                                try {
                                    requestSessionNotificationPermission(result)
                                } catch (error: Exception) {
                                    result.error("operation_failed", error.message, null)
                                }
                            }
                        }

                        else -> result.notImplemented()
                    }
                } catch (error: HostBackendException) {
                    result.error(error.code, error.message, null)
                } catch (error: SafWorkspaceException) {
                    result.error(error.code, error.message, null)
                } catch (error: Exception) {
                    result.error("operation_failed", error.message, null)
                }
            }
    }

    private fun startSafWorkspacePicker(result: MethodChannel.Result) {
        if (pendingSafPickerResult != null) {
            result.error("busy", "A SAF workspace picker is already open", null)
            return
        }
        pendingSafPickerResult = result
        try {
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                addFlags(
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                        Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                        Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                        Intent.FLAG_GRANT_PREFIX_URI_PERMISSION,
                )
            }
            startActivityForResult(intent, SAF_PICK_REQUEST_CODE)
        } catch (error: Exception) {
            pendingSafPickerResult = null
            result.error("picker_failed", error.message, null)
        }
    }

    private fun startCompatibilityRootfsPicker(result: MethodChannel.Result) {
        if (pendingSafPickerResult != null || pendingCompatibilityRootfsPickerResult != null) {
            result.error("busy", "Another document picker is already open", null)
            return
        }
        pendingCompatibilityRootfsPickerResult = result
        try {
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                addFlags(
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                        Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                        Intent.FLAG_GRANT_PREFIX_URI_PERMISSION,
                )
            }
            startActivityForResult(intent, COMPATIBILITY_ROOTFS_PICK_REQUEST_CODE)
        } catch (error: Exception) {
            pendingCompatibilityRootfsPickerResult = null
            result.error("picker_failed", error.message, null)
        }
    }

    private fun startImagePicker(result: MethodChannel.Result) {
        if (pendingImagePickerResult != null) {
            result.error("busy", "An image picker is already open", null)
            return
        }
        pendingImagePickerResult = result
        try {
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "image/*"
                putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
                addFlags(
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                        Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
                )
            }
            startActivityForResult(intent, IMAGE_PICK_REQUEST_CODE)
        } catch (error: Exception) {
            pendingImagePickerResult = null
            result.error("picker_failed", error.message, null)
        }
    }

    private fun startKernelSuPluginPicker(result: MethodChannel.Result) {
        if (
            pendingSafPickerResult != null ||
            pendingImagePickerResult != null ||
            pendingKernelSuPluginPickerResult != null
        ) {
            result.error("busy", "A document picker is already open", null)
            return
        }
        pendingKernelSuPluginPickerResult = result
        try {
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                // Keep the MIME filter broad because some document providers
                // label KernelSU ZIPs as application/octet-stream. The broker
                // performs the actual ZIP and manifest validation.
                type = "*/*"
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivityForResult(intent, KERNELSU_PLUGIN_PICK_REQUEST_CODE)
        } catch (error: Exception) {
            pendingKernelSuPluginPickerResult = null
            result.error("picker_failed", error.message, null)
        }
    }

    private fun dispatchKernelSuPluginCall(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        if (call.method != "enable") {
            executeKernelSuPluginCall(call, result)
            return
        }
        thread(name = "codex-kernelsu-preflight") {
            try {
                val requiresCredential = kernelSuPluginBridge.requiresDeviceCredential(call)
                runOnUiThread {
                    if (requiresCredential) {
                        requestKernelSuDeviceCredential(call, result)
                    } else {
                        executeKernelSuPluginCall(call, result)
                    }
                }
            } catch (error: PluginBrokerException) {
                runOnUiThread {
                    result.error(error.code.wireCode, error.code.safeMessage, null)
                }
            } catch (_: Exception) {
                runOnUiThread {
                    result.error(
                        "plugin_operation_failed",
                        "KernelSU plugin operation failed.",
                        null,
                    )
                }
            }
        }
    }

    private fun executeKernelSuPluginCall(
        call: MethodCall,
        result: MethodChannel.Result,
        deviceCredentialConfirmed: Boolean = false,
    ) {
        thread(name = "codex-kernelsu-plugin") {
            try {
                val response = if (deviceCredentialConfirmed) {
                    kernelSuPluginBridge.executeAfterDeviceCredential(call)
                } else {
                    kernelSuPluginBridge.execute(call)
                }
                runOnUiThread { result.success(response) }
            } catch (error: PluginBrokerException) {
                runOnUiThread {
                    result.error(error.code.wireCode, error.code.safeMessage, null)
                }
            } catch (_: Exception) {
                // Never cross the channel boundary with root-helper,
                // archive, path, or process diagnostics.
                runOnUiThread {
                    result.error(
                        "plugin_operation_failed",
                        "KernelSU plugin operation failed.",
                        null,
                    )
                }
            }
        }
    }

    @TargetApi(Build.VERSION_CODES.R)
    private fun requestKernelSuDeviceCredential(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            result.error(
                "device_credential_unsupported",
                "Device-credential approval requires Android 11 or newer.",
                null,
            )
            return
        }
        if (pendingKernelSuCredentialResult != null) {
            result.error("busy", "A device-credential prompt is already open.", null)
            return
        }
        val keyguard = getSystemService(KeyguardManager::class.java)
        if (keyguard?.isDeviceSecure != true) {
            result.error(
                "device_credential_unavailable",
                "Set a device PIN, pattern, or password before enabling this plugin.",
                null,
            )
            return
        }
        val moduleId = call.argument<String>("moduleId")?.trim().orEmpty()
        val digest = call.argument<String>("sha256")?.trim()?.lowercase(Locale.ROOT).orEmpty()
        if (moduleId.isEmpty() || !digest.matches(Regex("[0-9a-f]{64}"))) {
            result.error("invalid_request", "The staged plugin identity is invalid.", null)
            return
        }

        val chinese = Locale.getDefault().language == "zh"
        val prompt = try {
            BiometricPrompt.Builder(this)
                .setTitle(if (chinese) "确认启用 KernelSU 插件" else "Confirm KernelSU plugin enable")
                .setSubtitle(moduleId)
                .setDescription("SHA-256: $digest")
                .setAllowedAuthenticators(BiometricManager.Authenticators.DEVICE_CREDENTIAL)
                .build()
        } catch (_: Exception) {
            result.error(
                "device_credential_unavailable",
                "Android could not start device-credential confirmation.",
                null,
            )
            return
        }

        pendingKernelSuCredentialResult = result
        pendingKernelSuCredentialCall = call
        pendingKernelSuCredentialPrompt = prompt
        try {
            prompt.authenticate(
                CancellationSignal(),
                mainExecutor,
                object : BiometricPrompt.AuthenticationCallback() {
                    override fun onAuthenticationSucceeded(
                        authenticationResult: BiometricPrompt.AuthenticationResult,
                    ) {
                        val pendingCall = pendingKernelSuCredentialCall
                        val pendingResult = pendingKernelSuCredentialResult
                        clearKernelSuCredentialPrompt()
                        if (pendingCall == null || pendingResult == null) return
                        if (
                            authenticationResult.authenticationType !=
                            BiometricPrompt.AUTHENTICATION_RESULT_TYPE_DEVICE_CREDENTIAL
                        ) {
                            pendingResult.error(
                                "device_credential_required",
                                "A device PIN, pattern, or password was not confirmed.",
                                null,
                            )
                            return
                        }
                        executeKernelSuPluginCall(
                            pendingCall,
                            pendingResult,
                            deviceCredentialConfirmed = true,
                        )
                    }

                    override fun onAuthenticationError(
                        errorCode: Int,
                        errString: CharSequence,
                    ) {
                        finishKernelSuCredentialPrompt(
                            "device_credential_required",
                            "Device-credential confirmation was cancelled or failed.",
                        )
                    }
                },
            )
        } catch (_: Exception) {
            finishKernelSuCredentialPrompt(
                "device_credential_unavailable",
                "Android could not start device-credential confirmation.",
            )
        }
    }

    private fun finishKernelSuCredentialPrompt(code: String, message: String) {
        val result = pendingKernelSuCredentialResult
        clearKernelSuCredentialPrompt()
        result?.error(code, message, null)
    }

    private fun clearKernelSuCredentialPrompt() {
        pendingKernelSuCredentialResult = null
        pendingKernelSuCredentialCall = null
        pendingKernelSuCredentialPrompt = null
    }

    @Deprecated("FlutterActivity still routes legacy SAF callbacks here")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == SAF_PICK_REQUEST_CODE) {
            val result = pendingSafPickerResult
            pendingSafPickerResult = null
            if (result == null) {
                super.onActivityResult(requestCode, resultCode, data)
                return
            }
            if (resultCode != Activity.RESULT_OK || data?.data == null) {
                result.success(null)
            } else {
                try {
                    result.success(safWorkspaceStore.registerTree(data.data as Uri))
                } catch (error: SafWorkspaceException) {
                    result.error(error.code, error.message, null)
                } catch (error: Exception) {
                    result.error("picker_failed", error.message, null)
                }
            }
        }
        if (requestCode == COMPATIBILITY_ROOTFS_PICK_REQUEST_CODE) {
            val result = pendingCompatibilityRootfsPickerResult
            pendingCompatibilityRootfsPickerResult = null
            if (result == null) {
                super.onActivityResult(requestCode, resultCode, data)
                return
            }
            val uri = data?.data
            if (resultCode != Activity.RESULT_OK || uri == null) {
                result.success(null)
            } else {
                thread(name = "codex-compatibility-rootfs-install") {
                    var failure: Exception? = null
                    val response = try {
                        compatibilityProcessManager.withRootfsMaintenance {
                            compatibilityRootfsInstaller.installFromTree(uri)
                        }
                    } catch (error: Exception) {
                        Log.e(
                            "CodexCompatibilityRootfs",
                            (error.message ?: error.javaClass.simpleName).take(512),
                        )
                        failure = error
                        null
                    }
                    runOnUiThread {
                        if (failure != null) {
                            result.error(
                                "compatibility_rootfs_install_failed",
                                failure?.message ?: failure?.javaClass?.simpleName,
                                null,
                            )
                        } else {
                            result.success(response)
                        }
                    }
                }
            }
        }
        if (requestCode == IMAGE_PICK_REQUEST_CODE) {
            val result = pendingImagePickerResult
            pendingImagePickerResult = null
            if (result == null) {
                super.onActivityResult(requestCode, resultCode, data)
                return
            }
            if (resultCode != Activity.RESULT_OK || data == null) {
                result.success(emptyList<Map<String, Any>>())
            } else {
                thread(name = "codex-image-import") {
                    try {
                        val response = readSelectedImages(data)
                        runOnUiThread { result.success(response) }
                    } catch (error: Exception) {
                        runOnUiThread {
                            result.error(
                                "image_import_failed",
                                error.message ?: "Unable to read selected images.",
                                null,
                            )
                        }
                    }
                }
            }
        }
        if (requestCode == KERNELSU_PLUGIN_PICK_REQUEST_CODE) {
            val result = pendingKernelSuPluginPickerResult
            pendingKernelSuPluginPickerResult = null
            if (result == null) {
                super.onActivityResult(requestCode, resultCode, data)
                return
            }
            val uri = data?.data
            if (resultCode != Activity.RESULT_OK || uri == null) {
                result.success(null)
            } else {
                thread(name = "codex-kernelsu-plugin-import") {
                    try {
                        val response = readKernelSuPluginArchive(uri)
                        runOnUiThread { result.success(response) }
                    } catch (_: Exception) {
                        runOnUiThread {
                            result.error(
                                "plugin_archive_read_failed",
                                "Unable to read the selected plugin archive.",
                                null,
                            )
                        }
                    }
                }
            }
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    private fun readKernelSuPluginArchive(uri: Uri): Map<String, Any?> {
        val output = ByteArrayOutputStream()
        contentResolver.openInputStream(uri)?.use { input ->
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                if (count == 0) continue
                if (output.size().toLong() + count > MAX_KERNELSU_PLUGIN_ARCHIVE_BYTES) {
                    throw IllegalArgumentException("plugin archive is too large")
                }
                output.write(buffer, 0, count)
            }
        } ?: throw IllegalArgumentException("plugin archive could not be opened")
        val bytes = output.toByteArray()
        require(bytes.isNotEmpty()) { "plugin archive is empty" }
        return KernelSuPluginBridge.archiveResponse(bytes, null)
    }

    private fun readSelectedImages(data: Intent): List<Map<String, Any>> {
        val uris = mutableListOf<Uri>()
        data.clipData?.let { clip ->
            require(clip.itemCount <= MAX_IMAGE_COUNT) {
                "Select at most $MAX_IMAGE_COUNT images at a time."
            }
            for (index in 0 until clip.itemCount) {
                uris += clip.getItemAt(index).uri
            }
        }
        data.data?.let { uri ->
            if (uris.none { it == uri }) uris += uri
        }
        require(uris.isNotEmpty()) { "No image was selected." }
        require(uris.size <= MAX_IMAGE_COUNT) {
            "Select at most $MAX_IMAGE_COUNT images at a time."
        }
        var totalBytes = 0L
        return uris.map { uri ->
            val mimeType = contentResolver.getType(uri)?.lowercase(Locale.ROOT)
                ?: throw IllegalArgumentException("The selected file has no MIME type.")
            require(mimeType.startsWith("image/")) { "Only image files are supported." }
            val bytes = contentResolver.openInputStream(uri)?.use { input ->
                val output = ByteArrayOutputStream()
                val buffer = ByteArray(64 * 1024)
                var size = 0L
                while (true) {
                    val read = input.read(buffer)
                    if (read < 0) break
                    size += read
                    require(size <= MAX_IMAGE_BYTES) {
                        "Each image must be at most ${MAX_IMAGE_BYTES / (1024 * 1024)} MiB."
                    }
                    totalBytes += read
                    require(totalBytes <= MAX_IMAGE_TOTAL_BYTES) {
                        "Selected images are too large in total."
                    }
                    output.write(buffer, 0, read)
                }
                output.toByteArray()
            } ?: throw IllegalArgumentException("Unable to read selected image.")
            mapOf<String, Any>("mimeType" to mimeType, "bytes" to bytes)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (requestCode == SESSION_NOTIFICATION_PERMISSION_REQUEST_CODE) {
            val result = pendingSessionNotificationPermissionResult
            pendingSessionNotificationPermissionResult = null
            result?.success(
                grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED,
            )
            return
        }
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    private fun startSessionForeground() {
        val intent = Intent(this, SessionForegroundService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun stopSessionForeground() {
        stopService(Intent(this, SessionForegroundService::class.java))
    }

    private fun requestSessionNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        if (pendingSessionNotificationPermissionResult != null) {
            result.error(
                "permission_pending",
                "A notification permission request is already in progress.",
                null,
            )
            return
        }
        pendingSessionNotificationPermissionResult = result
        requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            SESSION_NOTIFICATION_PERMISSION_REQUEST_CODE,
        )
    }

    private fun providerKey(): java.security.Key {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val existing = keyStore.getKey(PROVIDER_KEY_ALIAS, null)
        if (existing != null) return existing
        val generator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            "AndroidKeyStore",
        )
        generator.init(
            KeyGenParameterSpec.Builder(
                PROVIDER_KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .build(),
        )
        return generator.generateKey()
    }

    private fun encryptProviderDocument(value: String): String {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, providerKey())
        val ciphertext = cipher.doFinal(value.toByteArray(StandardCharsets.UTF_8))
        val payload = ByteArray(cipher.iv.size + ciphertext.size)
        cipher.iv.copyInto(payload, 0)
        ciphertext.copyInto(payload, cipher.iv.size)
        return Base64.encodeToString(payload, Base64.NO_WRAP)
    }

    private fun decryptProviderDocument(value: String): String {
        val payload = Base64.decode(value, Base64.NO_WRAP)
        require(payload.size > 12) { "Stored provider data is invalid." }
        val iv = payload.copyOfRange(0, 12)
        val ciphertext = payload.copyOfRange(12, payload.size)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, providerKey(), GCMParameterSpec(128, iv))
        return String(cipher.doFinal(ciphertext), StandardCharsets.UTF_8)
    }

    private fun providerArray(): JSONArray {
        val preferences = getSharedPreferences("codex_preferences", MODE_PRIVATE)
        val encoded = preferences.getString("custom_providers_encrypted", null)
            ?: return JSONArray()
        return try {
            JSONArray(decryptProviderDocument(encoded))
        } catch (_: Exception) {
            // A key reset or an interrupted write must not block the local app.
            JSONArray()
        }
    }

    private fun persistProviderArray(value: JSONArray) {
        getSharedPreferences("codex_preferences", MODE_PRIVATE).edit()
            .putString("custom_providers_encrypted", encryptProviderDocument(value.toString()))
            .apply()
    }

    private fun providerString(value: Map<*, *>, key: String): String =
        value[key]?.toString()?.trim().orEmpty()

    private fun validateProviderUrl(raw: String) {
        val uri = Uri.parse(raw)
        require(uri.scheme?.lowercase(Locale.ROOT) in setOf("http", "https")) {
            "Provider URL must use http or https."
        }
        require(!uri.host.isNullOrBlank()) { "Provider URL must include a host." }
        require(uri.userInfo == null) { "Provider URL must not include credentials." }
    }

    private fun loadCustomProviders(): List<Map<String, Any?>> {
        val array = providerArray()
        return (0 until array.length()).mapNotNull { index ->
            val item = array.optJSONObject(index) ?: return@mapNotNull null
            linkedMapOf<String, Any?>(
                "id" to item.optString("id"),
                "name" to item.optString("name"),
                "baseUrl" to item.optString("baseUrl"),
                "model" to item.optString("model"),
                "apiKey" to item.optString("apiKey"),
            ).also {
                val efforts = item.optJSONArray("reasoningEfforts")
                if (efforts != null) {
                    it["reasoningEfforts"] = (0 until efforts.length())
                        .mapNotNull { effortIndex -> efforts.optString(effortIndex).trim().ifEmpty { null } }
                }
            }
        }
    }

    private fun saveCustomProvider(value: Map<*, *>) {
        val id = providerString(value, "id")
        val name = providerString(value, "name")
        val baseUrl = providerString(value, "baseUrl")
        val model = providerString(value, "model")
        val apiKey = providerString(value, "apiKey")
        val efforts = providerEfforts(value, model)
        require(id.matches(Regex("[A-Za-z0-9._-]{1,80}"))) { "Provider id is invalid." }
        require(name.isNotEmpty() && name.length <= 120) { "Provider name is invalid." }
        require(model.isNotEmpty() && model.length <= 200) { "Provider model is invalid." }
        validateProviderUrl(baseUrl)
        val array = providerArray()
        val replacement = JSONObject().apply {
            put("id", id)
            put("name", name)
            put("baseUrl", baseUrl)
            put("model", model)
            put("apiKey", apiKey)
            put("reasoningEfforts", JSONArray().apply { efforts.forEach(::put) })
        }
        var replaced = false
        for (index in 0 until array.length()) {
            val existing = array.optJSONObject(index)
            if (existing?.optString("id") == id) {
                array.put(index, replacement)
                replaced = true
                break
            }
        }
        if (!replaced) array.put(replacement)
        persistProviderArray(array)
    }

    private fun providerEfforts(value: Map<*, *>, model: String): List<String> {
        val raw = (value["reasoningEfforts"] as? List<*>)
            ?.mapNotNull { it?.toString()?.trim()?.lowercase(Locale.ROOT)?.ifEmpty { null } }
            ?.distinct()
            .orEmpty()
        val defaults = if (model.lowercase(Locale.ROOT).startsWith("deepseek-")) {
            listOf("none", "low", "high", "max")
        } else {
            listOf("low")
        }
        val efforts = if (raw.isEmpty()) defaults else raw
        require(efforts.size <= 8 && efforts.all { it.matches(Regex("[a-z][a-z0-9_-]{0,31}")) }) {
            "Provider reasoning efforts are invalid."
        }
        return efforts
    }

    private fun deleteCustomProvider(id: String) {
        if (id.isBlank()) return
        val preferences = getSharedPreferences("codex_preferences", MODE_PRIVATE)
        val old = providerArray()
        val next = JSONArray()
        var removed = false
        for (index in 0 until old.length()) {
            val item = old.optJSONObject(index) ?: continue
            if (item.optString("id") == id) {
                removed = true
            } else {
                next.put(item)
            }
        }
        persistProviderArray(next)
        if (removed && preferences.getString("active_custom_provider_id", null) == id) {
            preferences.edit().remove("active_custom_provider_id").apply()
        }
    }

    private fun probeLinuxCompatibilityRuntime(): Map<String, Any?> {
        val nativeDir = File(applicationInfo.nativeLibraryDir)
        return compatibilityProcessManager.probe(
            proot = File(nativeDir, PROOT_ASSET_NAME),
            loader = File(nativeDir, PROOT_LOADER_ASSET_NAME),
            trampoline = File(nativeDir, PROOT_HOST_TRAMPOLINE_ASSET_NAME),
        )
    }

    private fun compatibilityProotAsset(): File =
        File(applicationInfo.nativeLibraryDir, PROOT_ASSET_NAME)

    private fun compatibilityProotLoaderAsset(): File =
        File(applicationInfo.nativeLibraryDir, PROOT_LOADER_ASSET_NAME)

    private fun compatibilityProotTrampolineAsset(): File =
        File(applicationInfo.nativeLibraryDir, PROOT_HOST_TRAMPOLINE_ASSET_NAME)

    private fun probeAppHostAccess(): Map<String, Any> {
        val root = File(HOST_WORKSPACE_ROOT).absoluteFile
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R &&
                !Environment.isExternalStorageManager()
            ) {
                return mapOf(
                    "state" to "denied",
                    "identity" to "app",
                    "path" to root.path,
                    "reason" to "MANAGE_EXTERNAL_STORAGE is not granted; open Android storage settings",
                )
            }
            if (root.canonicalFile.path != root.path) {
                return mapOf(
                    "state" to "denied",
                    "identity" to "app",
                    "path" to root.path,
                    "reason" to "host workspace root is a symbolic link",
                )
            }
            if (!root.exists()) {
                return mapOf(
                    "state" to "missing",
                    "identity" to "app",
                    "path" to root.path,
                    "reason" to "host workspace root does not exist",
                )
            }
            if (!root.isDirectory) {
                return mapOf(
                    "state" to "denied",
                    "identity" to "app",
                    "path" to root.path,
                    "reason" to "host workspace root is not a directory",
                )
            }
            if (!root.canRead()) {
                return mapOf(
                    "state" to "denied",
                    "identity" to "app",
                    "path" to root.path,
                    "reason" to "App UID cannot read the host workspace root",
                )
            }
            val entries = root.listFiles() ?: return mapOf(
                "state" to "denied",
                "identity" to "app",
                "path" to root.path,
                "reason" to "App UID cannot enumerate the host workspace root",
            )
            mapOf(
                "state" to "available",
                "identity" to "app",
                "path" to root.path,
                "readable" to true,
                "writable" to root.canWrite(),
                "entryCount" to entries.size,
                "reason" to "App UID can enumerate the fixed host workspace root",
            )
        } catch (error: SecurityException) {
            mapOf(
                "state" to "denied",
                "identity" to "app",
                "path" to root.path,
                "reason" to "App UID storage access was denied",
            )
        } catch (error: Exception) {
            mapOf(
                "state" to "failed",
                "identity" to "app",
                "path" to root.path,
                "reason" to (error.message ?: error::class.java.simpleName).take(512),
            )
        }
    }

    private fun openHostAccessSettings() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            throw IllegalStateException(
                "All-files access settings require Android 11 or newer.",
            )
        }
        val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION).apply {
            data = Uri.parse("package:$packageName")
        }
        startActivity(intent)
    }

    private fun listHostDirectory(relativePath: String): List<Map<String, Any>> {
        val path = resolveHostPath(relativePath, allowEmpty = true)
        val command = guardedCommand(path, "/system/bin/ls -1Ap \"${'$'}resolved\"")
        try {
            val appEntries = listAppHostDirectory(relativePath)
            if (appEntries.isNotEmpty()) return appEntries

            // On some Android/FUSE combinations File.listFiles() reports an
            // inaccessible directory as an empty array instead of null. A
            // root-backed probe disambiguates that case while preserving a
            // genuinely empty directory when the root helper is unavailable.
            val rootEntries = try {
                val output = runRootCommand(command)
                listRootHostDirectoryOutput(relativePath, output)
            } catch (rootError: HostBackendException) {
                if (rootError.code == "operation_failed") {
                    return appEntries
                }
                throw rootError
            }
            return if (rootEntries.isEmpty()) appEntries else rootEntries
        } catch (appError: HostBackendException) {
            return withRootFallback(appError) {
                val output = runRootCommand(command)
                listRootHostDirectoryOutput(relativePath, output)
            }
            }
    }

    private fun createHostWorkspace(rawName: String): Map<String, Any> {
        val name = normalizeHostWorkspaceName(rawName)
        val root = File(HOST_WORKSPACE_ROOT).absoluteFile
        try {
            if (root.exists() && !root.isDirectory) {
                throw HostBackendException(
                    "not_directory",
                    "host workspace root is not a directory",
                )
            }
            if (root.canonicalFile.path != root.path) {
                throw HostBackendException(
                    "symlink_not_supported",
                    "host workspace root is a symbolic link",
                )
            }
            if (!root.exists() && !root.mkdirs() && !root.isDirectory) {
                throw HostBackendException(
                    "permission_denied",
                    "App UID cannot create the host workspace root; explicit storage authorization is required",
                )
            }
            val directory = resolveAppHostFile(name, allowEmpty = false)
            if (directory.exists()) {
                throw HostBackendException(
                    "already_exists",
                    "a Host workspace with this name already exists",
                )
            }
            if (!directory.mkdir()) {
                if (directory.exists()) {
                    throw HostBackendException(
                        "already_exists",
                        "a Host workspace with this name already exists",
                    )
                }
                throw HostBackendException(
                    "permission_denied",
                    "App UID cannot create a Host workspace; explicit storage authorization is required",
                )
            }
            if (!directory.isDirectory ||
                directory.canonicalFile.path != directory.path
            ) {
                throw HostBackendException(
                    "operation_failed",
                    "created Host workspace failed its path safety check",
                )
            }
            // The Changes page intentionally opens README.md first. A newly
            // created workspace must therefore be immediately usable instead
            // of presenting a missing-file error on its first open.
            val initialReadme = File(directory, "README.md")
            if (!initialReadme.createNewFile() ||
                !initialReadme.isFile ||
                isAppSymbolicLink(initialReadme)
            ) {
                throw HostBackendException(
                    "operation_failed",
                    "created Host workspace could not initialize README.md",
                )
            }
            return mapOf(
                "name" to name,
                "relativePath" to name,
                "path" to directory.path,
            )
        } catch (error: HostBackendException) {
            throw error
        } catch (error: SecurityException) {
            throw HostBackendException(
                "permission_denied",
                "App UID cannot create a Host workspace; explicit storage authorization is required",
            )
        } catch (error: java.io.IOException) {
            throw HostBackendException(
                "operation_failed",
                "App UID could not validate the Host workspace path",
            )
        }
    }

    private fun deleteHostWorkspace(rawName: String) {
        val name = normalizeHostWorkspaceName(rawName)
        val target = File(HOST_WORKSPACE_ROOT, name).absoluteFile
        val command = guardedCommand(
            target.path,
            "test \"${'$'}resolved\" != '$HOST_WORKSPACE_ROOT' || exit 21; " +
                "test -d \"${'$'}resolved\" || exit 23; " +
                "/system/bin/rm -rf -- \"${'$'}resolved\" || exit 27",
        )
        try {
            val directory = resolveAppHostFile(name, allowEmpty = false)
            if (!directory.exists()) {
                throw HostBackendException(
                    "not_found",
                    "Host workspace does not exist",
                )
            }
            if (!directory.isDirectory || isAppSymbolicLink(directory)) {
                throw HostBackendException(
                    "not_directory",
                    "Host workspace is not a real directory",
                )
            }
            if (!directory.deleteRecursively() || directory.exists()) {
                throw HostBackendException(
                    "permission_denied",
                    "App UID could not delete the Host workspace",
                )
            }
        } catch (error: HostBackendException) {
            if (error.code == "permission_denied" || error.code == "operation_failed") {
                withRootFallback(error) { runRootCommand(command) }
            } else {
                throw error
            }
        } catch (_: SecurityException) {
            val appError = HostBackendException(
                "permission_denied",
                "App UID could not delete the Host workspace",
            )
            withRootFallback(appError) { runRootCommand(command) }
        }
    }

    private fun normalizeHostWorkspaceName(rawName: String): String {
        val name = rawName.trim()
        if (name.isEmpty() || name == "." || name == "..") {
            throw HostBackendException(
                "invalid_workspace_name",
                "A workspace folder name is required",
            )
        }
        if (name.length > 80 || name.any {
                it == '/' || it == '\\' || it.code < 0x20 || it.code == 0x7f
            }
        ) {
            throw HostBackendException(
                "invalid_workspace_name",
                "Workspace name must be one safe directory name",
            )
        }
        return name
    }

    private fun listRootHostDirectoryOutput(
        relativePath: String,
        output: String,
    ): List<Map<String, Any>> {
        return output.lineSequence()
            .map { it.trimEnd('\r') }
            .filter { it.isNotEmpty() }
            .map { entryName ->
                val isDirectory = entryName.endsWith('/')
                val name = entryName.removeSuffix("/")
                val childRelative = if (relativePath.isEmpty()) name else "$relativePath/$name"
                mapOf(
                    "name" to name,
                    "relativePath" to childRelative,
                    "isDirectory" to isDirectory,
                    "sizeBytes" to 0L,
                )
            }
            .toList()
    }

    private fun readHostText(workspacePath: String, relativePath: String): String {
        validateRelativePath(workspacePath, allowEmpty = false)
        validateRelativePath(relativePath, allowEmpty = false)
        val path = resolveHostPath("$workspacePath/$relativePath", allowEmpty = false)
        val command = guardedCommand(
            path,
            "test -f \"${'$'}resolved\" || exit 23; " +
                "size=${'$'}(/system/bin/stat -c %s \"${'$'}resolved\") || exit 24; " +
                "test \"${'$'}size\" -le $MAX_HOST_TEXT_BYTES || exit 22; " +
                "/system/bin/cat \"${'$'}resolved\"",
        )
        val appRelativePath = "$workspacePath/$relativePath"
        try {
            return readAppHostText(appRelativePath)
        } catch (appError: HostBackendException) {
            return withRootFallback(appError) {
                runRootCommand(command, strictText = true)
            }
        }
    }

    private fun listAppHostDirectory(relativePath: String): List<Map<String, Any>> {
        val directory = resolveAppHostFile(relativePath, allowEmpty = true)
        if (!directory.exists()) {
            throw HostBackendException(
                "not_found",
                "App UID cannot access a missing host workspace path",
            )
        }
        if (!directory.isDirectory) {
            throw HostBackendException("not_regular", "host path is not a directory")
        }
        if (!directory.canRead()) {
            throw HostBackendException(
                "permission_denied",
                "App UID cannot read the host workspace; root helper or explicit storage authorization is required",
            )
        }
        val entries = directory.listFiles() ?: throw HostBackendException(
            "permission_denied",
            "App UID cannot enumerate the host workspace; root helper or explicit storage authorization is required",
        )
        return entries
            .sortedBy { it.name }
            .map { entry ->
                val symbolicLink = isAppSymbolicLink(entry)
                val isDirectory = entry.isDirectory && !symbolicLink
                mapOf(
                    "name" to entry.name,
                    "relativePath" to if (relativePath.isEmpty()) {
                        entry.name
                    } else {
                        "$relativePath/${entry.name}"
                    },
                    "isDirectory" to isDirectory,
                    "sizeBytes" to if (entry.isFile && !symbolicLink) entry.length() else 0L,
                )
            }
    }

    private fun readAppHostText(relativePath: String): String {
        val file = resolveAppHostFile(relativePath, allowEmpty = false)
        if (isAppSymbolicLink(file)) {
            throw HostBackendException(
                "symlink_not_supported",
                "App UID reads do not follow symbolic links",
            )
        }
        if (!file.isFile) {
            throw HostBackendException("not_regular", "path is not a regular file")
        }
        if (!file.canRead()) {
            throw HostBackendException(
                "permission_denied",
                "App UID cannot read this host file; root helper or explicit storage authorization is required",
            )
        }
        if (file.length() > MAX_HOST_TEXT_BYTES) {
            throw HostBackendException("too_large", "text file exceeds 1 MiB")
        }
        return try {
            TextFileCodec.decode(
                file.readBytes(),
                MAX_HOST_TEXT_BYTES,
                "Host text file",
            )
        } catch (error: TextFileException) {
            throw HostBackendException(error.code, error.message)
        } catch (error: SecurityException) {
            throw HostBackendException(
                "permission_denied",
                "App UID cannot read this host file; root helper or explicit storage authorization is required",
            )
        } catch (error: Exception) {
            throw HostBackendException(
                "operation_failed",
                (error.message ?: "could not read host file").take(512),
            )
        }
    }

    private fun snapshotHostText(
        workspacePath: String,
        relativePath: String,
    ): Map<String, Any> {
        val snapshot = loadHostSnapshot(workspacePath, relativePath)
        return mapOf(
            "relativePath" to snapshot.relativePath,
            "content" to snapshot.content,
            "version" to snapshot.version,
            "sizeBytes" to snapshot.sizeBytes,
            "uid" to snapshot.metadata.uid,
            "gid" to snapshot.metadata.gid,
            "mode" to snapshot.metadata.mode,
            "isSymbolicLink" to snapshot.isSymbolicLink,
        )
    }

    private fun writeHostText(
        workspacePath: String,
        relativePath: String,
        expectedVersion: String,
        content: String,
    ): Map<String, Any> {
        validateWritableText(content)
        val before = loadHostSnapshot(workspacePath, relativePath)
        if (before.isSymbolicLink) {
            throw HostBackendException(
                "symlink_not_supported",
                "managed writes do not replace symbolic links",
            )
        }
        ensureExpectedVersion(before, expectedVersion)

        val backupId = createBackup(workspacePath, before)
        applyHostText(before, expectedVersion, content, before.metadata)
        return writeReceipt(
            backupId = backupId,
            relativePath = relativePath,
            beforeVersion = before.version,
            afterVersion = sha256(content),
            restored = false,
        )
    }

    private fun restoreHostText(
        workspacePath: String,
        relativePath: String,
        backupId: String,
        expectedVersion: String,
    ): Map<String, Any> {
        val backup = readBackup(backupId)
        if (backup.workspacePath != workspacePath || backup.relativePath != relativePath) {
            throw HostBackendException(
                "invalid_backup",
                "backup target does not match the requested file",
            )
        }
        validateWritableText(backup.content)
        val before = loadHostSnapshot(workspacePath, relativePath)
        if (before.isSymbolicLink) {
            throw HostBackendException(
                "symlink_not_supported",
                "managed writes do not replace symbolic links",
            )
        }
        ensureExpectedVersion(before, expectedVersion)
        applyHostText(before, expectedVersion, backup.content, backup.metadata)
        return writeReceipt(
            backupId = backupId,
            relativePath = relativePath,
            beforeVersion = before.version,
            afterVersion = backup.version,
            restored = true,
        )
    }

    private fun backupHostText(
        workspacePath: String,
        relativePath: String,
        expectedVersion: String,
    ): Map<String, Any> {
        val before = loadHostSnapshot(workspacePath, relativePath)
        if (before.isSymbolicLink) {
            throw HostBackendException(
                "symlink_not_supported",
                "managed backups do not snapshot symbolic links",
            )
        }
        ensureExpectedVersion(before, expectedVersion)
        val backupId = createBackup(workspacePath, before)
        return writeReceipt(
            backupId = backupId,
            relativePath = relativePath,
            beforeVersion = before.version,
            afterVersion = before.version,
            restored = false,
        )
    }

    private fun loadHostSnapshot(
        workspacePath: String,
        relativePath: String,
    ): HostFileSnapshot {
        validateRelativePath(workspacePath, allowEmpty = false)
        validateRelativePath(relativePath, allowEmpty = false)
        val path = resolveHostPath("$workspacePath/$relativePath", allowEmpty = false)
        val content = readHostText(workspacePath, relativePath)
        val metadata = statHostFile(path)
        return HostFileSnapshot(
            workspacePath = workspacePath,
            relativePath = relativePath,
            path = path,
            content = content,
            version = sha256(content),
            sizeBytes = content.toByteArray(StandardCharsets.UTF_8).size.toLong(),
            metadata = metadata,
            isSymbolicLink = metadata.canonicalPath != path,
        )
    }

    private fun statHostFile(path: String): HostFileMetadata {
        val command = guardedCommand(
            path,
            "test -f \"${'$'}resolved\" || exit 23; " +
                "printf '%s\\n' \"${'$'}resolved\"; " +
                "/system/bin/stat -c '%u %g %a %s' \"${'$'}resolved\" || exit 24",
        )
        try {
            return statAppHostFile(path)
        } catch (appError: HostBackendException) {
            return withRootFallback(appError) {
                parseRootHostMetadata(runRootCommand(command))
            }
        }
    }

    private fun parseRootHostMetadata(output: String): HostFileMetadata {
        val lines = output
            .lineSequence()
            .map { it.trim() }
            .filter { it.isNotEmpty() }
            .toList()
        if (lines.size < 2) {
            throw HostBackendException("operation_failed", "invalid host file metadata")
        }
        val fields = lines[1].split(Regex("\\s+"))
        if (fields.size < 4) {
            throw HostBackendException("operation_failed", "invalid host file metadata")
        }
        return try {
            HostFileMetadata(
                canonicalPath = lines[0],
                uid = fields[0].toInt(),
                gid = fields[1].toInt(),
                mode = fields[2],
                sizeBytes = fields[3].toLong(),
            )
        } catch (error: NumberFormatException) {
            throw HostBackendException("operation_failed", "invalid host file metadata")
        }
    }

    private fun ensureExpectedVersion(snapshot: HostFileSnapshot, expectedVersion: String) {
        if (snapshot.version != expectedVersion) {
            throw HostBackendException(
                "conflict",
                "file changed after the preview was created",
            )
        }
    }

    private fun validateWritableText(content: String) {
        try {
            TextFileCodec.validateText(content, MAX_HOST_TEXT_BYTES, "Host text file")
        } catch (error: TextFileException) {
            throw HostBackendException(error.code, error.message)
        }
    }

    private fun createBackup(workspacePath: String, snapshot: HostFileSnapshot): String {
        val directory = File(filesDir, BACKUP_DIRECTORY)
        if (!directory.exists() && !directory.mkdirs()) {
            throw HostBackendException("backup_failed", "could not create backup directory")
        }
        val backupId = UUID.randomUUID().toString()
        val target = File(directory, "$backupId.json")
        val temporary = File(
            directory,
            ".${backupId}.tmp-${UUID.randomUUID()}",
        )
        val record = JSONObject()
            .put("workspacePath", workspacePath)
            .put("relativePath", snapshot.relativePath)
            .put("version", snapshot.version)
            .put("uid", snapshot.metadata.uid)
            .put("gid", snapshot.metadata.gid)
            .put("mode", snapshot.metadata.mode)
            .put(
                "contentBase64",
                Base64.encodeToString(
                    snapshot.content.toByteArray(StandardCharsets.UTF_8),
                    Base64.NO_WRAP,
                ),
            )
        try {
            FileOutputStream(temporary).use { stream ->
                stream.write(record.toString().toByteArray(StandardCharsets.UTF_8))
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
            throw HostBackendException("backup_failed", "could not persist backup")
        }
        return backupId
    }

    /**
     * Lists metadata for durable app-private backups without returning the
     * backed-up file contents. Invalid records remain visible as unavailable
     * entries so corruption is not silently mistaken for an empty history.
     */
    private fun listBackups(): List<Map<String, Any?>> {
        val directories = listOf(
            File(filesDir, BACKUP_DIRECTORY),
            File(filesDir, SAF_BACKUP_DIRECTORY),
        )
        val files = directories.flatMap { directory ->
            try {
                directory.listFiles()
                    ?.filter { it.isFile && it.name.endsWith(".json") }
                    ?: emptyList()
            } catch (_: SecurityException) {
                emptyList()
            }
        }.sortedWith(
            compareByDescending<File> { it.lastModified() }.thenBy { it.name },
        ).take(MAX_BACKUP_RECORDS)
        return files.map(::summarizeBackup)
    }

    private fun summarizeBackup(file: File): Map<String, Any?> {
        val backupId = file.name.removeSuffix(".json")
        val base = mutableMapOf<String, Any?>(
            "backupId" to backupId,
            "createdAtMs" to file.lastModified(),
            "valid" to false,
        )
        try {
            if (!Regex("[A-Za-z0-9-]{1,80}").matches(backupId)) {
                throw IllegalArgumentException("invalid backup id")
            }
            if (file.length() > MAX_BACKUP_BYTES) {
                throw IllegalArgumentException("backup metadata is too large")
            }
            val record = JSONObject(
                TextFileCodec.decode(
                    file.readBytes(),
                    MAX_BACKUP_BYTES,
                    "backup metadata",
                ),
            )
            val relativePath = record.optString("relativePath", "")
            validateRelativePath(relativePath, allowEmpty = false)
            val workspacePath = record.optString("workspacePath", "")
            val workspaceUri = record.optString("workspaceUri", "")
            val hasHost = workspacePath.isNotEmpty()
            val hasSaf = workspaceUri.isNotEmpty()
            if (hasHost == hasSaf) {
                throw IllegalArgumentException("backup workspace identity is invalid")
            }
            if (hasHost) {
                validateRelativePath(workspacePath, allowEmpty = false)
                base["kind"] = "host"
                base["workspacePath"] = "$HOST_WORKSPACE_ROOT/$workspacePath"
            } else {
                if (!workspaceUri.startsWith("content://")) {
                    throw IllegalArgumentException("backup SAF URI is invalid")
                }
                base["kind"] = "saf"
                base["workspaceUri"] = workspaceUri
            }
            val contentBytes = if (record.has("contentBase64")) {
                Base64.decode(record.getString("contentBase64"), Base64.DEFAULT)
            } else {
                record.optString("content", "").toByteArray(StandardCharsets.UTF_8)
            }
            TextFileCodec.decode(contentBytes, MAX_HOST_TEXT_BYTES, "backup content")
            base["relativePath"] = relativePath
            base["sizeBytes"] = contentBytes.size.toLong()
            base["version"] = record.optString(
                "version",
                record.optString("beforeVersion", ""),
            )
            base["valid"] = true
        } catch (error: Exception) {
            base["reason"] = (error.message ?: "backup metadata is invalid").take(256)
        }
        return base
    }

    private fun readBackup(backupId: String): BackupRecord {
        if (!Regex("[A-Za-z0-9-]{1,80}").matches(backupId)) {
            throw HostBackendException("invalid_backup", "invalid backup id")
        }
        val file = File(File(filesDir, BACKUP_DIRECTORY), "$backupId.json")
        if (!file.isFile) {
            throw HostBackendException("not_found", "backup does not exist")
        }
        return try {
            val record = JSONObject(
                TextFileCodec.decode(
                    file.readBytes(),
                    MAX_BACKUP_BYTES,
                    "backup metadata",
                ),
            )
            val content = TextFileCodec.decode(
                Base64.decode(record.getString("contentBase64"), Base64.DEFAULT),
                MAX_HOST_TEXT_BYTES,
                "Host backup",
            )
            BackupRecord(
                workspacePath = record.getString("workspacePath"),
                relativePath = record.getString("relativePath"),
                version = record.getString("version"),
                content = content,
                metadata = HostFileMetadata(
                    canonicalPath = "",
                    uid = record.getInt("uid"),
                    gid = record.getInt("gid"),
                    mode = record.getString("mode"),
                    sizeBytes = content.toByteArray(StandardCharsets.UTF_8).size.toLong(),
                ),
            )
        } catch (error: HostBackendException) {
            throw error
        } catch (error: Exception) {
            throw HostBackendException("invalid_backup", "backup metadata is invalid")
        }
    }

    private fun applyHostText(
        snapshot: HostFileSnapshot,
        expectedVersion: String,
        content: String,
        metadata: HostFileMetadata,
    ) {
        val temporaryPath = "${snapshot.path}.codex-tmp-${UUID.randomUUID()}"
        val command = guardedWriteCommand(
            path = snapshot.path,
            temporaryPath = temporaryPath,
            expectedVersion = expectedVersion,
            metadata = metadata,
        )
        try {
            applyAppHostText(snapshot, expectedVersion, content)
        } catch (appError: HostBackendException) {
            withRootFallback(appError) {
                runRootCommand(command, content.toByteArray(StandardCharsets.UTF_8))
            }
        }
    }

    private fun statAppHostFile(path: String): HostFileMetadata {
        val file = resolveAppHostFile(appRelativePath(path), allowEmpty = false)
        if (isAppSymbolicLink(file)) {
            throw HostBackendException(
                "symlink_not_supported",
                "App UID metadata reads do not follow symbolic links",
            )
        }
        if (!file.isFile) {
            throw HostBackendException("not_regular", "path is not a regular file")
        }
        if (!file.canRead()) {
            throw HostBackendException(
                "permission_denied",
                "App UID cannot read file metadata; root helper or explicit storage authorization is required",
            )
        }
        return HostFileMetadata(
            canonicalPath = file.absoluteFile.path,
            uid = -1,
            gid = -1,
            mode = "app-uid",
            sizeBytes = file.length(),
        )
    }

    private fun applyAppHostText(
        snapshot: HostFileSnapshot,
        expectedVersion: String,
        content: String,
    ) {
        val relativePath = appRelativePath(snapshot.path)
        val target = resolveAppHostFile(relativePath, allowEmpty = false)
        if (isAppSymbolicLink(target)) {
            throw HostBackendException(
                "symlink_not_supported",
                "App UID writes do not replace symbolic links",
            )
        }
        if (!target.isFile) {
            throw HostBackendException("not_regular", "path is not a regular file")
        }
        if (!target.canWrite() || target.parentFile?.canWrite() != true) {
            throw HostBackendException(
                "permission_denied",
                "App UID cannot write this host file; root helper or explicit storage authorization is required",
            )
        }
        if (sha256(readAppHostText(relativePath)) != expectedVersion) {
            throw HostBackendException(
                "conflict",
                "file changed after the preview was created",
            )
        }
        val temporary = File(
            target.parentFile,
            "${target.name}.codex-app-tmp-${UUID.randomUUID()}",
        )
        try {
            FileOutputStream(temporary).use { stream ->
                stream.write(content.toByteArray(StandardCharsets.UTF_8))
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
        } catch (error: HostBackendException) {
            temporary.delete()
            throw error
        } catch (error: SecurityException) {
            temporary.delete()
            throw HostBackendException(
                "permission_denied",
                "App UID cannot write this host file; root helper or explicit storage authorization is required",
            )
        } catch (error: Exception) {
            temporary.delete()
            throw HostBackendException(
                "write_failed",
                (error.message ?: "App UID atomic write failed").take(512),
            )
        }
    }

    private fun writeReceipt(
        backupId: String,
        relativePath: String,
        beforeVersion: String,
        afterVersion: String,
        restored: Boolean,
    ): Map<String, Any> = mapOf(
        "backupId" to backupId,
        "relativePath" to relativePath,
        "beforeVersion" to beforeVersion,
        "afterVersion" to afterVersion,
        "restored" to restored,
    )

    private fun resolveHostPath(relativePath: String, allowEmpty: Boolean): String {
        validateRelativePath(relativePath, allowEmpty)
        return if (relativePath.isEmpty()) {
            HOST_WORKSPACE_ROOT
        } else {
            "$HOST_WORKSPACE_ROOT/$relativePath"
        }
    }

    private fun resolveAppHostFile(relativePath: String, allowEmpty: Boolean): File {
        validateRelativePath(relativePath, allowEmpty)
        val root = File(HOST_WORKSPACE_ROOT).absoluteFile
        val raw = if (relativePath.isEmpty()) root else File(root, relativePath)
        val absolute = raw.absoluteFile
        val canonicalRoot: File
        val canonical: File
        try {
            canonicalRoot = root.canonicalFile
            canonical = absolute.canonicalFile
        } catch (error: SecurityException) {
            throw HostBackendException(
                "permission_denied",
                "App UID cannot inspect the host workspace; root helper or explicit storage authorization is required",
            )
        } catch (error: java.io.IOException) {
            throw HostBackendException(
                "operation_failed",
                "App UID could not resolve the host workspace path",
            )
        }
        if (canonical.path != canonicalRoot.path &&
            !canonical.path.startsWith("${canonicalRoot.path}${File.separator}")
        ) {
            throw HostBackendException(
                "outside_scope",
                "path escaped the fixed host workspace root",
            )
        }
        if (canonical.path != absolute.path) {
            throw HostBackendException(
                "symlink_not_supported",
                "App UID host access does not follow symbolic links",
            )
        }
        return absolute
    }

    private fun appRelativePath(path: String): String {
        if (path == HOST_WORKSPACE_ROOT) return ""
        val prefix = "$HOST_WORKSPACE_ROOT/"
        if (!path.startsWith(prefix)) {
            throw HostBackendException(
                "outside_scope",
                "path escaped the fixed host workspace root",
            )
        }
        return path.removePrefix(prefix)
    }

    private fun isAppSymbolicLink(file: File): Boolean = try {
        Files.isSymbolicLink(file.toPath()) || file.canonicalFile.path != file.absoluteFile.path
    } catch (error: SecurityException) {
        true
    } catch (error: java.io.IOException) {
        true
    }

    private fun <T> withRootFallback(
        appError: HostBackendException,
        rootOperation: () -> T,
    ): T = try {
        rootOperation()
    } catch (rootError: HostBackendException) {
        if (rootError.code == "operation_failed") throw appError
        throw rootError
    }

    private fun validateRelativePath(value: String, allowEmpty: Boolean) {
        require(value.isNotEmpty() || allowEmpty) { "relative path is required" }
        if (value.isEmpty()) return
        require(!value.startsWith('/') && !value.endsWith('/')) {
            "relative path must not be absolute"
        }
        require(!value.contains('\\') && !value.contains('\u0000')) {
            "relative path contains an invalid separator"
        }
        value.split('/').forEach { segment ->
            require(segment.isNotEmpty() && segment != "." && segment != "..") {
                "relative path traversal is not allowed"
            }
            require(segment.none { it.code < 0x20 || it.code == 0x7f }) {
                "relative path contains a control character"
            }
        }
    }

    private fun guardedCommand(path: String, operation: String): String {
        val base = shellQuote(HOST_WORKSPACE_ROOT)
        val target = shellQuote(path)
        return "base=$base; target=$target; " +
            "resolved=${'$'}(/system/bin/readlink -f \"${'$'}target\") || exit 20; " +
            "case \"${'$'}resolved\" in \"${'$'}base\"|\"${'$'}base\"/*) ;; *) exit 21 ;; esac; " +
            operation
    }

    private fun guardedWriteCommand(
        path: String,
        temporaryPath: String,
        expectedVersion: String,
        metadata: HostFileMetadata,
    ): String {
        val base = shellQuote(HOST_WORKSPACE_ROOT)
        val target = shellQuote(path)
        val temporary = shellQuote(temporaryPath)
        val expected = shellQuote(expectedVersion)
        val uid = shellQuote(metadata.uid.toString())
        val gid = shellQuote(metadata.gid.toString())
        val mode = shellQuote(metadata.mode)
        return "base=$base; target=$target; temp=$temporary; " +
            "resolved=${'$'}(/system/bin/readlink -f \"${'$'}target\") || exit 20; " +
            "case \"${'$'}resolved\" in \"${'$'}base\"|\"${'$'}base\"/*) ;; *) exit 21 ;; esac; " +
            "test \"${'$'}resolved\" = \"${'$'}target\" || exit 25; " +
            "test -f \"${'$'}target\" || exit 23; " +
            "current=${'$'}(/system/bin/sha256sum \"${'$'}target\" | /system/bin/cut -d ' ' -f 1) || exit 24; " +
            "test \"${'$'}current\" = $expected || exit 26; " +
            "test ! -e \"${'$'}temp\" || exit 27; " +
            "umask 077; /system/bin/cat > \"${'$'}temp\" || { /system/bin/rm -f \"${'$'}temp\"; exit 27; }; " +
            "/system/bin/chown $uid:$gid \"${'$'}temp\" || { /system/bin/rm -f \"${'$'}temp\"; exit 28; }; " +
            "/system/bin/chmod $mode \"${'$'}temp\" || { /system/bin/rm -f \"${'$'}temp\"; exit 28; }; " +
            "/system/bin/mv -f \"${'$'}temp\" \"${'$'}target\" || { /system/bin/rm -f \"${'$'}temp\"; exit 27; }"
    }

    private fun sha256(value: String): String = MessageDigest
        .getInstance("SHA-256")
        .digest(value.toByteArray(StandardCharsets.UTF_8))
        .joinToString("") { byte -> "%02x".format(byte) }

    private fun runRootCommand(
        command: String,
        input: ByteArray? = null,
        timeoutSeconds: Long = COMMAND_TIMEOUT_SECONDS,
        strictText: Boolean = false,
    ): String {
        var lastFailure = "root helper unavailable"
        for (helper in ROOT_HELPER_CANDIDATES) {
            try {
                // Shared-storage FUSE mounts are visible in the device mount
                // namespace, while a plain KernelSU shell may remain in the
                // app's isolated namespace and report an empty workspace.
                // Keep the helper path fixed and request the mount-master
                // namespace before running the already guarded operation.
                val process = ProcessBuilder(helper, "--mount-master", "-c", command)
                    .redirectErrorStream(true)
                    .start()
                val outputBuffer = ByteArrayOutputStream()
                val outputThread = Thread {
                    try {
                        process.inputStream.use { it.copyTo(outputBuffer) }
                    } catch (_: Exception) {
                        // The process may be destroyed after a timeout.
                    }
                }
                outputThread.start()
                process.outputStream.use { stream ->
                    if (input != null) stream.write(input)
                }
                if (!process.waitFor(timeoutSeconds, TimeUnit.SECONDS)) {
                    process.destroyForcibly()
                    outputThread.join(1_000)
                    throw HostBackendException("timeout", "root operation timed out")
                }
                outputThread.join(1_000)
                val output = if (strictText && process.exitValue() == 0) {
                    try {
                        TextFileCodec.decode(
                            outputBuffer.toByteArray(),
                            MAX_HOST_TEXT_BYTES,
                            "Host text file",
                        )
                    } catch (error: TextFileException) {
                        throw HostBackendException(error.code, error.message)
                    }
                } else {
                    outputBuffer.toString(StandardCharsets.UTF_8.name())
                }
                if (process.exitValue() == 0) {
                    return output
                }
                lastFailure = output.trim().ifEmpty { "root operation exited ${process.exitValue()}" }
                when (process.exitValue()) {
                    20 -> throw HostBackendException(
                        "not_found",
                        "host workspace path does not exist",
                    )
                    21 -> throw HostBackendException("outside_scope", "path escaped host workspace root")
                    22 -> throw HostBackendException("too_large", "text file exceeds 1 MiB")
                    23 -> throw HostBackendException("not_regular", "path is not a regular file")
                    25 -> throw HostBackendException(
                        "symlink_not_supported",
                        "managed writes do not replace symbolic links",
                    )
                    26 -> throw HostBackendException(
                        "conflict",
                        "file changed after the preview was created",
                    )
                    27 -> throw HostBackendException("write_failed", "atomic write failed")
                    28 -> throw HostBackendException(
                        "metadata_failed",
                        "could not preserve file ownership or mode",
                    )
                }
                // The helper process did start, so the command has already
                // run. Retrying it with another helper could duplicate a
                // write or hide the real failure (especially for an atomic
                // runtime install). Only launch failures fall through to the
                // next helper candidate.
                throw HostBackendException(
                    "operation_failed",
                    lastFailure.take(512),
                )
            } catch (error: HostBackendException) {
                throw error
            } catch (error: Exception) {
                lastFailure = error.message ?: error::class.java.simpleName
            }
        }
        throw HostBackendException("operation_failed", lastFailure.take(512))
    }

    private fun shellQuote(value: String): String =
        "'" + value.replace("'", "'\\''") + "'"

    private class HostBackendException(
        val code: String,
        override val message: String,
    ) : RuntimeException(message)

    private data class HostFileMetadata(
        val canonicalPath: String,
        val uid: Int,
        val gid: Int,
        val mode: String,
        val sizeBytes: Long,
    )

    private data class HostFileSnapshot(
        val workspacePath: String,
        val relativePath: String,
        val path: String,
        val content: String,
        val version: String,
        val sizeBytes: Long,
        val metadata: HostFileMetadata,
        val isSymbolicLink: Boolean,
    )

    private data class BackupRecord(
        val workspacePath: String,
        val relativePath: String,
        val version: String,
        val content: String,
        val metadata: HostFileMetadata,
    )

}
