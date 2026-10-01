package io.henry.codex

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class CompatibilityNetworkConfigurationTest {
    @Test
    fun buildsAllProxyVariantsWithoutCredentials() {
        val environment = CompatibilityNetworkConfiguration.proxyEnvironment(
            hostValue = " 127.0.0.1 ",
            port = 7890,
        )

        val expectedEndpoint = "http://127.0.0.1:7890"
        assertEquals(expectedEndpoint, environment["HTTP_PROXY"])
        assertEquals(expectedEndpoint, environment["HTTPS_PROXY"])
        assertEquals(expectedEndpoint, environment["ALL_PROXY"])
        assertEquals(expectedEndpoint, environment["http_proxy"])
        assertEquals(expectedEndpoint, environment["https_proxy"])
        assertEquals(expectedEndpoint, environment["all_proxy"])
        assertEquals("127.0.0.1,localhost,::1", environment["NO_PROXY"])
        assertEquals("127.0.0.1,localhost,::1", environment["no_proxy"])
        assertTrue(environment.values.none { it.contains('@') })
    }

    @Test
    fun formatsIpv6ProxyAuthority() {
        val environment = CompatibilityNetworkConfiguration.proxyEnvironment(
            hostValue = "2001:db8::7",
            port = 3128,
        )

        assertEquals("http://[2001:db8::7]:3128", environment["HTTPS_PROXY"])
    }

    @Test
    fun rejectsInvalidProxyEndpoint() {
        assertTrue(
            CompatibilityNetworkConfiguration.proxyEnvironment(
                hostValue = "proxy.example/path",
                port = 7890,
            ).isEmpty(),
        )
        assertTrue(
            CompatibilityNetworkConfiguration.proxyEnvironment(
                hostValue = "127.0.0.1",
                port = 0,
            ).isEmpty(),
        )
        assertTrue(
            CompatibilityNetworkConfiguration.proxyEnvironment(
                hostValue = "127.0.0.1",
                port = 65_536,
            ).isEmpty(),
        )
    }

    @Test
    fun parsesManualProxyEndpointsAndNormalizesSchemeAndIpv6() {
        assertEquals(
            HttpProxyEndpoint("proxy.local", 7890),
            CompatibilityNetworkConfiguration.parseHttpProxyEndpoint(
                "http://proxy.local:7890",
            ),
        )
        assertEquals(
            HttpProxyEndpoint("::1", 7891),
            CompatibilityNetworkConfiguration.parseHttpProxyEndpoint("[::1]:7891"),
        )
        assertEquals(
            "[::1]:7891",
            CompatibilityNetworkConfiguration.parseHttpProxyEndpoint("[::1]:7891")
                ?.normalized,
        )
    }

    @Test
    fun rejectsManualProxyEndpointsThatAreNotHostAndPort() {
        listOf(
            "socks5://127.0.0.1:7890",
            "https://127.0.0.1:7890",
            "127.0.0.1",
            "user@proxy.local:7890",
            "proxy.local:0",
            "proxy.local:65536",
            "2001:db8::1:7890",
            "[not-an-ipv6-address]:7890",
        ).forEach { value ->
            assertEquals(
                "invalid endpoint: $value",
                null,
                CompatibilityNetworkConfiguration.parseHttpProxyEndpoint(value),
            )
        }
    }
}
