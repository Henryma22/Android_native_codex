package io.henry.codex

import android.content.Context
import android.net.ConnectivityManager
import java.io.File
import java.net.Inet6Address
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Proxy
import java.net.ProxySelector
import java.net.URI
import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.nio.file.StandardCopyOption

/**
 * Keeps the immutable guest rootfs independent from the DNS configuration of
 * the machine that produced it.  Android supplies the active network DNS
 * servers and each guest process receives a private resolver file.
 */
internal object CompatibilityNetworkConfiguration {
    private const val RESOLVER_FILE_NAME = "resolver.conf"
    private const val TEMP_RESOLVER_FILE_NAME = "resolver.conf.pending"
    private const val CA_BUNDLE_FILE_NAME = "codex-android-ca.pem"
    private const val TEMP_CA_BUNDLE_FILE_NAME = "codex-android-ca.pem.pending"
    const val GUEST_CA_BUNDLE_PATH = "/etc/codex-android-ca.pem"
    const val HTTP_PROXY_PREFERENCE_KEY = "manual_http_proxy_endpoint"
    private const val GUEST_RESOLVER_PATH = "/etc/resolv.conf"
    private const val ANDROID_CA_DIRECTORY = "/system/etc/security/cacerts"
    private const val MAX_NAMESERVERS = 4

    private val lock = Any()
    private val caBundleLock = Any()

    fun prepare(context: Context, runtimeBase: File): File = synchronized(lock) {
        require(runtimeBase.isDirectory && !Files.isSymbolicLink(runtimeBase.toPath())) {
            "compatibility runtime base is unavailable"
        }
        val state = File(runtimeBase, "state")
        require(state.mkdirs() || state.isDirectory) {
            "compatibility runtime state directory is unavailable"
        }
        val target = File(state, RESOLVER_FILE_NAME)
        val temporary = File(state, TEMP_RESOLVER_FILE_NAME)
        require(!Files.isSymbolicLink(target.toPath())) {
            "compatibility resolver file must not be a symlink"
        }
        require(!Files.isSymbolicLink(temporary.toPath())) {
            "temporary compatibility resolver file must not be a symlink"
        }

        val servers = activeDnsServers(context)
        require(servers.isNotEmpty()) {
            "Android has no usable DNS configuration for the current network; " +
                "connect Wi-Fi, mobile data, or a VPN and retry"
        }
        temporary.writeText(renderResolverConfig(servers), StandardCharsets.US_ASCII)
        require(temporary.setReadable(true, false)) {
            "compatibility resolver file is not readable"
        }
        try {
            Files.move(
                temporary.toPath(),
                target.toPath(),
                StandardCopyOption.ATOMIC_MOVE,
                StandardCopyOption.REPLACE_EXISTING,
            )
        } catch (_: java.nio.file.AtomicMoveNotSupportedException) {
            Files.move(
                temporary.toPath(),
                target.toPath(),
                StandardCopyOption.REPLACE_EXISTING,
            )
        }
        require(!Files.isSymbolicLink(target.toPath())) {
            "compatibility resolver file became a symlink"
        }
        require(target.isFile && target.canRead()) {
            "compatibility resolver file is unavailable"
        }
        target
    }

    fun bindArgument(file: File): String {
        require(file.isAbsolute && file.isFile && file.canRead()) {
            "compatibility resolver file is unavailable"
        }
        require(!Files.isSymbolicLink(file.toPath())) {
            "compatibility resolver file must not be a symlink"
        }
        return "--bind=${file.absolutePath}:$GUEST_RESOLVER_PATH"
    }

    /**
     * Exposes only an explicit Android HTTP proxy to the local guest.
     *
     * Android's VPN/network stack does not automatically copy LinkProperties
     * into a PRoot process.  Codex and its optional MCP worker use HTTPS, so a
     * device which relies on an HTTP proxy otherwise reports TLS handshake
     * failures even though the Android network itself is validated.
     */
    fun httpProxyEnvironment(context: Context): Map<String, String> {
        val manualEndpoint = runCatching {
            context.applicationContext
                .getSharedPreferences("codex_preferences", Context.MODE_PRIVATE)
                .getString(HTTP_PROXY_PREFERENCE_KEY, null)
        }.getOrNull()
        parseHttpProxyEndpoint(manualEndpoint)?.let { endpoint ->
            return proxyEnvironment(endpoint.host, endpoint.port)
        }
        val proxy = activeHttpProxy(context) ?: return emptyMap()
        return proxyEnvironment(proxy.host, proxy.port)
    }

    /**
     * Makes Android's platform roots available to Codex's Rustls transports.
     * Rustls-native-certs cannot discover Android's individual PEM files by
     * itself, so keep a private aggregate bundle and use Codex's supported CA
     * environment hooks. Certificate verification remains enabled.
     */
    fun caBundleEnvironment(context: Context): Map<String, String> {
        val bundle = prepareCaBundle(context) ?: return emptyMap()
        return mapOf(
            "CODEX_CA_CERTIFICATE" to bundle.absolutePath,
            "SSL_CERT_FILE" to bundle.absolutePath,
        )
    }

    fun localRuntimeEnvironment(context: Context): Map<String, String> = buildMap {
        putAll(httpProxyEnvironment(context))
        putAll(caBundleEnvironment(context))
    }

    /** Returns the private CA bundle that can be bind-mounted into a guest. */
    fun prepareCaBundle(context: Context): File? = synchronized(caBundleLock) {
        val outputDirectory = context.filesDir
        if (!outputDirectory.isDirectory && !outputDirectory.mkdirs()) return null
        val target = File(outputDirectory, CA_BUNDLE_FILE_NAME)
        val temporary = File(outputDirectory, TEMP_CA_BUNDLE_FILE_NAME)
        if (Files.isSymbolicLink(target.toPath()) || Files.isSymbolicLink(temporary.toPath())) {
            return null
        }

        val sourceFiles = File(ANDROID_CA_DIRECTORY).listFiles()
            ?.asSequence()
            ?.filter { file ->
                file.isFile && !Files.isSymbolicLink(file.toPath()) &&
                    file.name.matches(Regex("[0-9a-fA-F]+\\.0"))
            }
            ?.sortedBy(File::getName)
            ?.toList()
            .orEmpty()
        if (sourceFiles.isEmpty()) return null

        val endMarker = "-----END CERTIFICATE-----"
        val bundle = buildString {
            sourceFiles.forEach { source ->
                val pem = runCatching {
                    source.readText(StandardCharsets.US_ASCII)
                }.getOrNull() ?: return@forEach
                val begin = pem.indexOf("-----BEGIN CERTIFICATE-----")
                val end = pem.indexOf(endMarker, begin)
                if (begin >= 0 && end >= begin) {
                    append(pem.substring(begin, end + endMarker.length).trim())
                    append('\n')
                }
            }
        }
        if (bundle.isBlank()) return null

        val size = bundle.toByteArray(StandardCharsets.US_ASCII).size
        if (target.isFile && target.length() == size.toLong() && target.canRead()) return target

        try {
            temporary.writeText(bundle, StandardCharsets.US_ASCII)
            require(!Files.isSymbolicLink(temporary.toPath())) {
                "temporary Android CA bundle must not be a symlink"
            }
            try {
                Files.move(
                    temporary.toPath(),
                    target.toPath(),
                    StandardCopyOption.ATOMIC_MOVE,
                    StandardCopyOption.REPLACE_EXISTING,
                )
            } catch (_: java.nio.file.AtomicMoveNotSupportedException) {
                Files.move(
                    temporary.toPath(),
                    target.toPath(),
                    StandardCopyOption.REPLACE_EXISTING,
                )
            }
            target.takeIf { it.isFile && it.canRead() && !Files.isSymbolicLink(it.toPath()) }
        } catch (_: Exception) {
            runCatching { temporary.delete() }
            null
        }
    }

    /**
     * Builds the small, credential-free proxy environment shared by every
     * local execution identity. Kept pure so the Android network boundary can
     * be regression-tested without faking ConnectivityManager.
     */
    internal fun proxyEnvironment(hostValue: String, port: Int): Map<String, String> {
        val host = hostValue.trim()
        if (!isSafeProxyHost(host) || port !in 1..65_535) return emptyMap()
        val authority = if (host.contains(':') && !host.startsWith('[')) {
            "[$host]"
        } else {
            host
        }
        val endpoint = "http://$authority:$port"
        return mapOf(
            "HTTP_PROXY" to endpoint,
            "HTTPS_PROXY" to endpoint,
            "ALL_PROXY" to endpoint,
            "http_proxy" to endpoint,
            "https_proxy" to endpoint,
            "all_proxy" to endpoint,
            "NO_PROXY" to "127.0.0.1,localhost,::1",
            "no_proxy" to "127.0.0.1,localhost,::1",
        )
    }

    internal fun parseHttpProxyEndpoint(value: String?): HttpProxyEndpoint? {
        var authority = value?.trim().orEmpty()
        if (authority.isEmpty()) return null
        if (authority.startsWith("http://", ignoreCase = true)) {
            authority = authority.substringAfter("://")
        } else if (authority.contains("://")) {
            return null
        }
        if (authority.any { character ->
                character.isWhitespace() || character.isISOControl() ||
                    character == '/' || character == '@' ||
                    character == '?' || character == '#'
            }) {
            return null
        }

        val host: String
        val portText: String
        if (authority.startsWith('[')) {
            val closingBracket = authority.indexOf(']')
            if (closingBracket <= 1 || authority.getOrNull(closingBracket + 1) != ':') {
                return null
            }
            host = authority.substring(1, closingBracket)
            portText = authority.substring(closingBracket + 2)
            if (runCatching { InetAddress.getByName(host) }.getOrNull() !is Inet6Address) {
                return null
            }
        } else {
            val separator = authority.lastIndexOf(':')
            if (separator <= 0 || authority.indexOf(':') != separator) return null
            host = authority.substring(0, separator)
            portText = authority.substring(separator + 1)
        }
        val port = portText.toIntOrNull()?.takeIf { it in 1..65_535 } ?: return null
        if (!isSafeProxyHost(host)) return null
        return HttpProxyEndpoint(host, port)
    }

    private fun renderResolverConfig(servers: List<String>): String {
        val normalized = servers.asSequence()
            .mapNotNull(::normalizeAddress)
            .distinct()
            .take(MAX_NAMESERVERS)
            .toList()
        require(normalized.isNotEmpty()) { "Android returned no valid DNS server" }
        return buildString {
        append("# Managed by the Android local Codex runtime\n")
            normalized.forEach { address ->
                append("nameserver ").append(address).append('\n')
            }
        }
    }

    private fun activeDnsServers(context: Context): List<String> {
        val connectivity = runCatching {
            context.applicationContext.getSystemService(ConnectivityManager::class.java)
        }.getOrNull() ?: return emptyList()
        val active = connectivity.activeNetwork
        // Keep the active VPN/Wi-Fi resolver first, but retain validated
        // underlying-network resolvers as fallbacks. A VPN can publish a DNS
        // address that is reachable only while its tunnel is fully ready; a
        // resolver file containing that single address made the guest fail
        // with EAI_AGAIN during VPN handover even though Android had already
        // reported another validated network.
        val fallbackNetworks = runCatching { connectivity.allNetworks.asList() }
            .getOrDefault(emptyList())
            .asSequence()
            .filter { network -> network != active && hasInternet(connectivity, network) }
            .toList()
        return sequence {
            if (active != null) yieldAll(dnsForNetwork(connectivity, active))
            yieldAll(
                fallbackNetworks.asSequence().flatMap { network ->
                    dnsForNetwork(connectivity, network).asSequence()
                },
            )
        }
            .distinct()
            .take(MAX_NAMESERVERS)
            .toList()
    }

    private fun activeHttpProxy(context: Context): android.net.ProxyInfo? {
        val connectivity = runCatching {
            context.applicationContext.getSystemService(ConnectivityManager::class.java)
        }.getOrNull() ?: return null
        val active = connectivity.activeNetwork
        active?.let { network ->
            connectivity.getLinkProperties(network)?.httpProxy?.let { proxy ->
                if (isSafeProxyHost(proxy.host) && proxy.port in 1..65_535) return proxy
            }
        }

        // A VPN can briefly be published after the process' active network
        // changes. Prefer a validated network with an explicit proxy before
        // falling back to direct connectivity.
        return runCatching { connectivity.allNetworks.asList() }
            .getOrDefault(emptyList())
            .asSequence()
            .filter { it != active && hasInternet(connectivity, it) }
            .mapNotNull { network -> connectivity.getLinkProperties(network)?.httpProxy }
            .firstOrNull { proxy ->
                isSafeProxyHost(proxy.host) && proxy.port in 1..65_535
            }
            ?: proxySelectorHttpProxy()
    }

    /**
     * Some Android VPN/global-proxy implementations expose their HTTP proxy
     * through the process ProxySelector but omit it from LinkProperties. The
     * root/PRoot worker cannot otherwise inherit that proxy automatically.
     * Never forward DIRECT, SOCKS, unresolved, or credential-bearing proxies.
     */
    private fun proxySelectorHttpProxy(): android.net.ProxyInfo? = runCatching {
        val uri = URI("https://api.openai.com/")
        ProxySelector.getDefault()
            ?.select(uri)
            .orEmpty()
            .asSequence()
            .filter { proxy -> proxy.type() == Proxy.Type.HTTP }
            .mapNotNull { proxy -> proxy.address() as? InetSocketAddress }
            .filter { address -> !address.isUnresolved }
            .map { address ->
                android.net.ProxyInfo.buildDirectProxy(address.hostString, address.port)
            }
            .firstOrNull { proxy ->
                isSafeProxyHost(proxy.host) && proxy.port in 1..65_535
            }
    }.getOrNull()

    private fun isSafeProxyHost(host: String): Boolean = host.isNotBlank() &&
        host.length <= 255 &&
        host.all { character ->
            !character.isWhitespace() &&
                !character.isISOControl() &&
                character != '/' && character != '@' &&
                character != '?' && character != '#'
        }

    private fun dnsForNetwork(
        connectivity: ConnectivityManager,
        network: android.net.Network,
    ): List<String> = runCatching {
        connectivity.getLinkProperties(network)?.dnsServers.orEmpty()
            .asSequence()
            .mapNotNull { address -> address.hostAddress }
            .mapNotNull(::normalizeAddress)
            .distinct()
            .take(MAX_NAMESERVERS)
            .toList()
    }.getOrDefault(emptyList())

    private fun hasInternet(
        connectivity: ConnectivityManager,
        network: android.net.Network,
    ): Boolean = runCatching {
        val capabilities = connectivity.getNetworkCapabilities(network)
        capabilities != null &&
            capabilities.hasCapability(android.net.NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
            capabilities.hasCapability(android.net.NetworkCapabilities.NET_CAPABILITY_NOT_RESTRICTED)
    }.getOrDefault(false)

    private fun normalizeAddress(value: String): String? {
        val withoutZone = value.substringBefore('%')
        if (withoutZone.isEmpty() || withoutZone.any { character ->
                character != '.' && character != ':' &&
                    character !in '0'..'9' && character.lowercaseChar() !in 'a'..'f'
            }) {
            return null
        }
        return runCatching {
            InetAddress.getByName(withoutZone).hostAddress?.substringBefore('%')
        }.getOrNull()
    }
}

internal data class HttpProxyEndpoint(val host: String, val port: Int) {
    val normalized: String
        get() = if (host.contains(':')) "[$host]:$port" else "$host:$port"
}
