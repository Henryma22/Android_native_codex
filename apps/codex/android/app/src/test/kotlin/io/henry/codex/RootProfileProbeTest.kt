package io.henry.codex

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RootProfileProbeTest {
    @Test
    fun `shared block check enumerates aliases and never writes`() {
        val script = AndroidBlockDeviceWriteProbe.shell

        assertTrue(script.contains("/dev/block/by-name/*"))
        assertTrue(script.contains("/dev/block/bootdevice/by-name/*"))
        assertTrue(script.contains("/dev/block/mapper/*"))
        assertTrue(script.contains("[ -w \"\$path\" ]"))
        assertTrue(script.contains("BLOCK_ALIAS_ENUMERATION_COMPLETE"))
        assertFalse(script.contains("dd "))
        assertFalse(script.contains("of="))
    }

    @Test
    fun `a rejected normal root invocation has an actionable diagnostic`() {
        val contextFailure = classifyRootProfileProbeFailure(
            "/system/bin/su",
            1,
            "Error: setcontext u:r:codex_agent:s0 Caused by: Invalid argument (os error 22)",
        )

        assertEquals("context_unavailable", contextFailure.state)
        assertEquals(
            "KernelSU rejected the normal Root invocation; check the selected KernelSU app profile.",
            contextFailure.reason,
        )

        val authorizationFailure = classifyRootProfileProbeFailure(
            "/system/bin/su",
            1,
            "KernelSU authorization denied",
        )
        assertEquals("denied", authorizationFailure.state)
        assertTrue(authorizationFailure.reason.contains("/system/bin/su"))

        val missingRootIdentity = classifyRootProfileProbeFailure(
            "/system/bin/su",
            77,
            "root_worker_security_error=not_gid_zero",
        )
        assertEquals("profile_incompatible", missingRootIdentity.state)
        assertTrue(missingRootIdentity.reason.contains("UID"))
    }

    @Test
    fun `safe root launch gate selects only the helper that passed the profile probe`() {
        val profile = RootProfileProbeAssessment.parse("/system/bin/su", profileOutput())

        assertEquals("/system/bin/su", RootProfileLaunchGate.requireSafeHelper(profile))
    }

    @Test
    fun `normal KernelSU domain is accepted when UID is root`() {
        val profile = RootProfileProbeAssessment.parse(
            "/system/bin/su",
            profileOutput().replace("u:r:codex_agent:s0", "u:r:ksu:s0"),
        )

        assertEquals("/system/bin/su", RootProfileLaunchGate.requireSafeHelper(profile))
    }

    @Test
    fun `root launch gate rejects an unapproved helper even with passing evidence`() {
        val profile = RootProfileProbeAssessment.parse("/tmp/su", profileOutput())

        org.junit.Assert.assertThrows(IllegalStateException::class.java) {
            RootProfileLaunchGate.requireSafeHelper(profile)
        }
    }

    @Test
    fun `root identity passes while path samples remain diagnostics`() {
        val result = RootProfileProbeAssessment.parse("/system/bin/su", profileOutput())

        assertEquals("root", result["state"])
        assertEquals("u:r:codex_agent:s0", result["context"])
        assertEquals("0 1007 3003 3009", result["groups"])
        assertTrue(result["networkGroupPresent"] as Boolean)
        assertTrue(result["readProcGroupPresent"] as Boolean)
        assertTrue(result["requiredGroupsPresent"] as Boolean)
        assertTrue(result["systemDataReadable"] as Boolean)
        assertTrue(result["appDataRootReadable"] as Boolean)
        assertTrue(result["appInstallRootReadable"] as Boolean)
        assertTrue(result["globalReadSamplesPassed"] as Boolean)
        assertTrue(result["systemConfigReadable"] as Boolean)
        assertTrue(result["vendorConfigReadable"] as Boolean)
        assertTrue(result["procStatusReadable"] as Boolean)
        assertTrue(result["selinuxStateReadable"] as Boolean)
        assertTrue(result["workspaceWritable"] as Boolean)
        assertTrue(result["appFilesAccessible"] as Boolean)
        assertTrue(result["appNoBackupAccessible"] as Boolean)
        assertTrue(result["blockAliasEnumerationComplete"] as Boolean)
        assertEquals(174, result["blockAliasCount"])
        assertEquals(0, result["writableBlockAliasCount"])
        assertTrue(result["blockAliasesReadOnly"] as Boolean)
        assertTrue(result["protectedWriteSamplesPassed"] as Boolean)
        assertFalse(result["bootBlockWritable"] as Boolean)
        assertFalse(result["protectedRootsWritable"] as Boolean)
        assertTrue((result["reason"] as String).contains("UID 0"))
    }

    @Test
    fun `default KernelSU domain passes root identity`() {
        val output = profileOutput().replace("u:r:codex_agent:s0", "u:r:ksu:s0")

        val result = RootProfileProbeAssessment.parse("/system/bin/su", output)

        assertEquals("root", result["state"])
    }

    @Test
    fun `unrelated system domain passes root identity`() {
        val output = profileOutput().replace("u:r:codex_agent:s0", "u:r:init:s0")

        val result = RootProfileProbeAssessment.parse("/system/bin/su", output)

        assertEquals("root", result["state"])
    }

    @Test
    fun `additional capabilities and groups do not fail smoke`() {
        val output = profileOutput().replace(
            "groups=0 3003 3009 1007",
            "groups=0 3003 3009 1007 1015",
        )

        val result = RootProfileProbeAssessment.parse("/system/bin/su", output)

        assertEquals("root", result["state"])
        assertTrue(result["requiredGroupsPresent"] as Boolean)
    }

    @Test
    fun `profile without Android inet group remains usable and reports the diagnostic`() {
        val output = profileOutput().replace("groups=0 3003 3009 1007", "groups=0 3009 1007")

        val result = RootProfileProbeAssessment.parse("/system/bin/su", output)

        assertEquals("root", result["state"])
        assertFalse(result["networkGroupPresent"] as Boolean)
    }

    @Test
    fun `extra Android groups are accepted`() {
        val output = profileOutput().replace(
            "groups=0 3003 3009 1007",
            "groups=0 3003 3009 1007 1000 1015",
        )

        val result = RootProfileProbeAssessment.parse("/system/bin/su", output)

        assertEquals("root", result["state"])
        assertTrue(result["networkGroupPresent"] as Boolean)
        assertTrue(result["requiredGroupsPresent"] as Boolean)
    }

    @Test
    fun `readproc group is diagnostic rather than a launch gate`() {
        val output = profileOutput().replace("groups=0 3003 3009 1007", "groups=0 3003 1007")

        val result = RootProfileProbeAssessment.parse("/system/bin/su", output)

        assertEquals("root", result["state"])
        assertFalse(result["readProcGroupPresent"] as Boolean)
        assertFalse(result["requiredGroupsPresent"] as Boolean)
    }

    @Test
    fun `primary root group is diagnostic rather than a launch gate`() {
        val output = profileOutput().replace("gid=0", "gid=1000")

        val result = RootProfileProbeAssessment.parse("/system/bin/su", output)

        assertEquals("root", result["state"])
        assertEquals("1000", result["gid"])
        assertTrue((result["reason"] as String).contains("Primary GID is 1000"))
    }

    @Test
    fun `profile without writable app runtime directory cannot pass smoke`() {
        val output = profileOutput().replace("appNoBackupWritable=1", "appNoBackupWritable=0")

        val result = RootProfileProbeAssessment.parse("/system/bin/su", output)

        assertEquals("root", result["state"])
        assertFalse(result["appNoBackupAccessible"] as Boolean)
    }

    @Test
    fun `unreadable global read samples fail smoke`() {
        val unreadableVendor = profileOutput().replace("vendorConfigReadable=1", "vendorConfigReadable=0")
        val unreadableSystem = profileOutput().replace("systemConfigReadable=1", "systemConfigReadable=0")
        val unreadableAppRoots = profileOutput().replace("appInstallRootReadable=1", "appInstallRootReadable=0")
        val unreadableAppProcess = profileOutput().replace(
            "appProcessStatusReadable=1",
            "appProcessStatusReadable=0",
        )

        listOf(unreadableVendor, unreadableSystem, unreadableAppRoots, unreadableAppProcess).forEach { output ->
            val result = RootProfileProbeAssessment.parse("/system/bin/su", output)
            assertEquals("root", result["state"])
            assertFalse(result["globalReadSamplesPassed"] as Boolean)
        }
    }

    @Test
    fun `writable SELinux control remains a diagnostic`() {
        val output = profileOutput().replace("selinuxStateWritable=0", "selinuxStateWritable=1")

        val result = RootProfileProbeAssessment.parse("/system/bin/su", output)

        assertEquals("root", result["state"])
        assertTrue(result["selinuxStateWritable"] as Boolean)
    }

    @Test
    fun `missing protected write-denial evidence does not block root`() {
        val output = profileOutput().replace("vendorConfigWritable=0\n", "")

        val result = RootProfileProbeAssessment.parse("/system/bin/su", output)

        assertEquals("root", result["state"])
    }

    @Test
    fun `writable boot block remains a diagnostic`() {
        val writableBoot = profileOutput().replace("bootBlockWritable=0", "bootBlockWritable=1")

        assertEquals(
            "root",
            RootProfileProbeAssessment.parse("/system/bin/su", writableBoot)["state"],
        )
    }

    @Test
    fun `writable visible block alias remains a diagnostic`() {
        val writableAlias = profileOutput().replace("writableBlockAliasCount=0", "writableBlockAliasCount=1")

        val result = RootProfileProbeAssessment.parse("/system/bin/su", writableAlias)

        assertEquals("root", result["state"])
        assertFalse(result["blockAliasesReadOnly"] as Boolean)
        assertFalse(result["protectedWriteSamplesPassed"] as Boolean)
    }

    @Test
    fun `incomplete or missing block alias enumeration remains a diagnostic`() {
        val incomplete = profileOutput().replace(
            "blockAliasEnumerationComplete=1",
            "blockAliasEnumerationComplete=0",
        )
        val missingCount = profileOutput().replace("blockAliasCount=174\n", "")
        val malformedCount = profileOutput().replace("blockAliasCount=174", "blockAliasCount=unknown")

        listOf(incomplete, missingCount, malformedCount).forEach { output ->
            val result = RootProfileProbeAssessment.parse("/system/bin/su", output)
            assertEquals("root", result["state"])
            assertFalse(result["blockAliasesReadOnly"] as Boolean)
        }
    }

    @Test
    fun `capability and no new privileges values are diagnostic only`() {
        val broadProfile = profileOutput()
            .replace("capEff=000001ffffffffff", "capEff=ffffffffffffffff")
            .replace("linuxNoNewPrivs=1", "linuxNoNewPrivs=0")

        val result = RootProfileProbeAssessment.parse("/system/bin/su", broadProfile)
        assertEquals("root", result["state"])
        assertEquals("ffffffffffffffff", result["capEff"])
        assertEquals("0", result["linuxNoNewPrivs"])
    }

    @Test
    fun `non-root output is denied and cannot pass`() {
        val output = profileOutput().replace("uid=0", "uid=10509")

        val result = RootProfileProbeAssessment.parse("/system/bin/su", output)

        assertEquals("denied", result["state"])
        assertFalse(result["bootBlockWritable"] as Boolean)
    }

    private fun profileOutput(): String = """
        uid=0
        gid=0
        context=u:r:codex_agent:s0
        groups=0 3003 3009 1007
        capEff=000001ffffffffff
        capPrm=000001ffffffffff
        capInh=0000000000000002
        capBnd=000001ffffffffff
        capAmb=0000000000000002
        linuxNoNewPrivs=1
        selinux=Enforcing
        systemDataPresent=1
        systemDataReadable=1
        systemDataWritable=0
        appDataRootPresent=1
        appDataRootReadable=1
        appDataRootWritable=0
        appInstallRootPresent=1
        appInstallRootReadable=1
        appInstallRootWritable=0
        workspacePresent=1
        workspaceReadable=1
        workspaceWritable=1
        bootBlockPresent=1
        bootBlockReadable=1
        bootBlockWritable=0
        ksuModulesPresent=1
        ksuModulesReadable=1
        ksuModulesWritable=0
        modulesPresent=1
        modulesReadable=1
        modulesWritable=0
        systemConfigPresent=1
        systemConfigReadable=1
        systemConfigWritable=0
        vendorConfigPresent=1
        vendorConfigReadable=1
        vendorConfigWritable=0
        procStatusPresent=1
        procStatusReadable=1
        procStatusWritable=0
        appProcessStatusPresent=1
        appProcessStatusReadable=1
        appProcessStatusWritable=0
        selinuxStatePresent=1
        selinuxStateReadable=1
        selinuxStateWritable=0
        appFilesPresent=1
        appFilesReadable=1
        appFilesWritable=1
        appNoBackupPresent=1
        appNoBackupReadable=1
        appNoBackupWritable=1
        blockAliasEnumerationComplete=1
        blockAliasCount=174
        writableBlockAliasCount=0
        blockAliasesReadOnly=1
        protectedWriteSamplesPassed=1
    """.trimIndent()
}
