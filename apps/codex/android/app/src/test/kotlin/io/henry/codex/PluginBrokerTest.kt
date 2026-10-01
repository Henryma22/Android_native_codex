package io.henry.codex

import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class PluginBrokerTest {
    @get:Rule
    val temporaryFolder = TemporaryFolder()

    @Test
    fun `valid declarative archive binds identity digest and effective R1`() {
        val archive = archive()
        val validated = PluginArchiveValidator.validate(
            archive = archive,
            expectedSha256 = PluginArchiveValidator.sha256(archive),
        )

        assertEquals("ccpocket.plugin.demo", validated.manifest.id)
        assertEquals(PluginRisk.R1, validated.effectiveRisk)
        assertFalse(validated.containsScripts)
        assertEquals(archive.size.toLong(), validated.archiveSizeBytes)
    }

    @Test
    fun `manifest is fixed shape and risk hint cannot lower effective risk`() {
        val scriptArchive = archive(
            manifest = manifestJson(
                riskHint = "R1",
                overlayRoots = listOf("/data/adb/modules"),
            ),
            extraMembers = listOf(
                Member("action.sh", "#!/system/bin/sh\necho unsafe\n"),
                Member("helper.py", "print('unsafe')\n"),
            ),
        )
        val validated = PluginArchiveValidator.validate(scriptArchive)
        assertEquals(PluginRisk.R2, validated.effectiveRisk)

        val unknownField = manifestJson() + "\n"
        val invalid = unknownField.dropLast(2) + ",\"unexpected\":true}"
        val exception = expectBrokerError {
            PluginManifest.parse(invalid)
        }
        assertEquals(PluginBrokerErrorCode.MANIFEST_INVALID, exception.code)
    }

    @Test
    fun `deeply nested manifest is a fixed validation error`() {
        val nested = "[".repeat(20_000) + "0" + "]".repeat(20_000)
        val json = """
            {
              "schemaVersion":1,
              "id":"ccpocket.plugin.demo",
              "name":"Demo Plugin",
              "version":"1.0.0",
              "capabilities":[],
              "riskHint":"R0",
              "requiresReboot":false,
              "reversible":true,
              "overlayRoots":[],
              "actions":[],
              "backupTargets":[],
              "healthChecks":[],
              "unexpected":$nested
            }
        """.trimIndent()
        val exception = expectBrokerError { PluginManifest.parse(json) }
        assertEquals(PluginBrokerErrorCode.MANIFEST_INVALID, exception.code)
    }

    @Test
    fun `sha mismatch and bounded archive are fixed errors`() {
        val archive = archive()
        val digestError = expectBrokerError {
            PluginArchiveValidator.validate(archive, expectedSha256 = "a".repeat(64))
        }
        assertEquals(PluginBrokerErrorCode.DIGEST_MISMATCH, digestError.code)

        val sizeError = expectBrokerError {
            PluginArchiveValidator.validate(
                archive,
                limits = PluginArchiveValidator.Limits(maxArchiveBytes = archive.size.toLong() - 1),
            )
        }
        assertEquals(PluginBrokerErrorCode.ARCHIVE_TOO_LARGE, sizeError.code)
    }

    @Test
    fun `uncompressed archive expansion is bounded`() {
        val base = PluginArchiveValidator.validate(archive())
        val oversized = archive(
            extraMembers = listOf(Member("payload.bin", "x".repeat(1024))),
        )

        val exception = expectBrokerError {
            PluginArchiveValidator.validate(
                oversized,
                limits = PluginArchiveValidator.Limits(
                    maxUncompressedBytes = base.uncompressedSizeBytes + 16,
                ),
            )
        }
        assertEquals(PluginBrokerErrorCode.UNCOMPRESSED_SIZE_LIMIT, exception.code)
    }

    @Test
    fun `path traversal and unsafe overlay roots fail closed`() {
        val escapedMember = archive(
            extraMembers = listOf(Member("../escape", "owned")),
        )
        assertEquals(
            PluginBrokerErrorCode.PATH_ESCAPE,
            expectBrokerError { PluginArchiveValidator.validate(escapedMember) }.code,
        )

        val escapedOverlay = archive(
            manifest = manifestJson(overlayRoots = listOf("/data/adb/modules/../etc")),
        )
        assertEquals(
            PluginBrokerErrorCode.PATH_ESCAPE,
            expectBrokerError { PluginArchiveValidator.validate(escapedOverlay) }.code,
        )
    }

    @Test
    fun `relative backup target traversal fails closed`() {
        val escapedBackup = archive(
            manifest = manifestJson(backupTargets = listOf("../../etc/passwd")),
        )
        assertEquals(
            PluginBrokerErrorCode.PATH_ESCAPE,
            expectBrokerError { PluginArchiveValidator.validate(escapedBackup) }.code,
        )
    }

    @Test
    fun `symlink hardlink metadata and special unix modes are rejected`() {
        val symlink = archive(extraMembers = listOf(Member("link", "target", unixMode = 0xa000)))
        assertEquals(
            PluginBrokerErrorCode.SYMLINK_ENTRY,
            expectBrokerError { PluginArchiveValidator.validate(symlink) }.code,
        )

        val hardlink = archive(
            extraMembers = listOf(
                Member(
                    name = "hardlink",
                    content = "same inode",
                    unixMode = 0x8000,
                    extra = hardlinkExtra(),
                ),
            ),
        )
        assertEquals(
            PluginBrokerErrorCode.HARDLINK_ENTRY,
            expectBrokerError { PluginArchiveValidator.validate(hardlink) }.code,
        )

        val hardlinkWithoutUnixMode = archive(
            extraMembers = listOf(
                Member(
                    name = "hardlink-without-mode",
                    content = "same inode",
                    extra = hardlinkExtra(),
                ),
            ),
        )
        assertEquals(
            PluginBrokerErrorCode.HARDLINK_ENTRY,
            expectBrokerError { PluginArchiveValidator.validate(hardlinkWithoutUnixMode) }.code,
        )

        val fifo = archive(extraMembers = listOf(Member("pipe", "", unixMode = 0x1000)))
        assertEquals(
            PluginBrokerErrorCode.SPECIAL_FILE,
            expectBrokerError { PluginArchiveValidator.validate(fifo) }.code,
        )
    }

    @Test
    fun `overlay and boot chain properties produce R3 and R4`() {
        val systemOverlay = PluginArchiveValidator.validate(
            archive(manifest = manifestJson(overlayRoots = listOf("/system"))),
        )
        assertEquals(PluginRisk.R3, systemOverlay.effectiveRisk)

        val bootChain = PluginArchiveValidator.validate(
            archive(
                manifest = manifestJson(
                    capabilities = listOf("boot-chain"),
                    overlayRoots = emptyList(),
                ),
            ),
        )
        assertEquals(PluginRisk.R4, bootChain.effectiveRisk)

        val bootImageMember = PluginArchiveValidator.validate(
            archive(
                manifest = manifestJson(
                    riskHint = "R1",
                    overlayRoots = listOf("/data/adb/modules"),
                ),
                extraMembers = listOf(Member("assets/boot.img", "raw boot image")),
            ),
        )
        assertEquals(PluginRisk.R4, bootImageMember.effectiveRisk)

        val systemMember = PluginArchiveValidator.validate(
            archive(
                manifest = manifestJson(
                    riskHint = "R1",
                    overlayRoots = listOf("/data/adb/modules"),
                ),
                extraMembers = listOf(Member("system/bin/zygisk", "native payload")),
            ),
        )
        assertEquals(PluginRisk.R3, systemMember.effectiveRisk)

        val understatedSePolicy = PluginArchiveValidator.validate(
            archive(
                manifest = manifestJson(
                    riskHint = "R0",
                    capabilities = listOf("declarative-overlay"),
                    overlayRoots = listOf("/data/adb/modules"),
                ),
                extraMembers = listOf(
                    Member("sepolicy.rule", "type codex_agent, domain\n"),
                ),
            ),
        )
        assertEquals(PluginRisk.R3, understatedSePolicy.effectiveRisk)
        assertEquals("sepolicy.rule", understatedSePolicy.reviewFiles.single().path)
        assertEquals(
            "type codex_agent, domain\n",
            understatedSePolicy.reviewFiles.single().content,
        )
        assertFalse(understatedSePolicy.reviewFiles.single().truncated)

        for (memberName in listOf("service.sh", "post-mount.sh", "initrc/custom.rc")) {
            val bootHook = PluginArchiveValidator.validate(
                archive(
                    manifest = manifestJson(
                        riskHint = "R0",
                        capabilities = listOf("declarative-overlay"),
                        overlayRoots = listOf("/data/adb/modules"),
                    ),
                    extraMembers = listOf(Member(memberName, "# inert fixture\n")),
                ),
            )
            assertEquals("$memberName must be R3", PluginRisk.R3, bootHook.effectiveRisk)
            assertEquals(memberName, bootHook.reviewFiles.single().path)
        }
    }

    @Test
    fun `review previews are bounded and escape bidi controls`() {
        val longPolicy = "allow codex_agent system_file:file read\n".repeat(1200)
        val archive = archive(
            manifest = manifestJson(riskHint = "R0"),
            extraMembers = listOf(
                Member("sepolicy.rule", longPolicy),
                Member("service.sh", "echo\u202e malicious\n"),
            ),
        )

        val review = PluginArchiveValidator.validate(archive).reviewFiles
        val policy = review.first { it.path == "sepolicy.rule" }
        assertTrue(policy.truncated)
        assertTrue((policy.content?.length ?: 0) <= 32 * 1024)
        val script = review.first { it.path == "service.sh" }
        assertTrue(script.content.orEmpty().contains("\\u202e"))

        val manyScripts = archive(
            manifest = manifestJson(riskHint = "R0"),
            extraMembers = (1..6).map { index ->
                Member("scripts/check-$index.sh", "x".repeat(32 * 1024))
            },
        )
        val boundedFiles = PluginArchiveValidator.validate(manyScripts).reviewFiles
        val capturedBytes = boundedFiles.sumOf { file ->
            file.content?.toByteArray(StandardCharsets.UTF_8)?.size ?: 0
        }
        assertTrue(capturedBytes <= 128 * 1024)
        assertTrue(boundedFiles.any { it.truncated })
    }

    @Test
    fun `module IDs must stay inside the reserved namespace`() {
        val invalidManifestId = archive(
            manifest = manifestJson(id = "com.example.module"),
        )
        assertEquals(
            PluginBrokerErrorCode.MANIFEST_INVALID,
            expectBrokerError { PluginArchiveValidator.validate(invalidManifestId) }.code,
        )

        val invalidModulePropId = archive(
            modulePropText = moduleProp(id = "com.example.module"),
        )
        assertEquals(
            PluginBrokerErrorCode.MODULE_PROP_INVALID,
            expectBrokerError { PluginArchiveValidator.validate(invalidModulePropId) }.code,
        )
    }

    @Test
    fun `malformed archive errors do not expose parser diagnostics`() {
        val exception = expectBrokerError {
            PluginArchiveValidator.validate("not a zip at /private/root".toByteArray())
        }

        assertEquals(PluginBrokerErrorCode.MALFORMED_ARCHIVE, exception.code)
        assertEquals(PluginBrokerErrorCode.MALFORMED_ARCHIVE.safeMessage, exception.message)
        assertFalse(exception.toString().contains("/private/root"))
        assertFalse(exception.toString().contains("not a zip"))
    }

    @Test
    fun `R1 install uses only fixed operations and never reboots`() {
        val calls = mutableListOf<Pair<PluginKsudOperation, String>>()
        val runner = PluginKsudRunner { operation, moduleId ->
            calls += operation to moduleId.value
            PluginKsudResult(0)
        }
        val broker = PluginBroker(canonicalStage("stage"), runner)
        val archive = archive()
        val staged = broker.stage(
            requestId = "request-01",
            archiveBytes = archive,
            expectedSha256 = PluginArchiveValidator.sha256(archive),
        )

        val result = broker.install(staged)
        assertEquals(PluginRisk.R1, result.effectiveRisk)
        assertEquals(
            listOf(
                PluginKsudOperation.INSTALL to "ccpocket.plugin.demo",
                PluginKsudOperation.ENABLE to "ccpocket.plugin.demo",
            ),
            calls,
        )
        assertTrue(result.operations.none { it == PluginKsudOperation.ACTION })
    }

    @Test
    fun `staging a replacement preserves one verified previous archive for rollback`() {
        val calls = mutableListOf<PluginKsudOperation>()
        val runner = PluginKsudRunner { operation, _ ->
            calls += operation
            PluginKsudResult(0)
        }
        val stageRoot = canonicalStage("stage-rollback")
        val broker = PluginBroker(stageRoot, runner)
        val first = archive(
            manifest = manifestJson(version = "1.0.0"),
            modulePropText = moduleProp(version = "1.0.0"),
        )
        val second = archive(
            manifest = manifestJson(version = "2.0.0"),
            modulePropText = moduleProp(version = "2.0.0"),
        )

        broker.install(
            broker.stage("first", first, PluginArchiveValidator.sha256(first)),
        )
        val replacement = broker.stage(
            "second",
            second,
            PluginArchiveValidator.sha256(second),
        )
        broker.install(replacement)

        val rollback = broker.rollback(replacement)

        assertEquals("1.0.0", rollback.staged.archive.manifest.version)
        assertEquals(
            first.toList(),
            replacement.stagedFile.readBytes().toList(),
        )
        assertEquals(
            second.toList(),
            stageRoot.resolve("previous/ccpocket.plugin.demo.zip").readBytes().toList(),
        )
        assertEquals(
            listOf(
                PluginKsudOperation.INSTALL,
                PluginKsudOperation.ENABLE,
                PluginKsudOperation.INSTALL,
                PluginKsudOperation.ENABLE,
                PluginKsudOperation.INSTALL,
                PluginKsudOperation.ENABLE,
            ),
            calls,
        )
    }

    @Test
    fun `rollback without a previous verified archive is blocked`() {
        val archive = archive()
        val broker = PluginBroker(canonicalStage("stage-no-rollback"))
        val staged = broker.stage("only", archive, PluginArchiveValidator.sha256(archive))

        assertEquals(
            PluginBrokerErrorCode.ROLLBACK_UNAVAILABLE,
            expectBrokerError { broker.rollback(staged) }.code,
        )
    }

    @Test
    fun `R0 does not call runner and R3 installs disabled before credentialed enable`() {
        val calls = mutableListOf<PluginKsudOperation>()
        val runner = PluginKsudRunner { operation, _ ->
            calls += operation
            PluginKsudResult(0)
        }
        val broker = PluginBroker(canonicalStage("stage"), runner)

        val r0Archive = archive(
            manifest = manifestJson(
                overlayRoots = emptyList(),
                capabilities = listOf("linux-only"),
            ),
        )
        val r0 = broker.stage("r0", r0Archive, PluginArchiveValidator.sha256(r0Archive))
        assertEquals(
            PluginBrokerErrorCode.NO_KERNELSU_OPERATION,
            expectBrokerError { broker.install(r0) }.code,
        )
        assertTrue(calls.isEmpty())

        val r3Archive = archive(
            manifest = manifestJson(
                requiresReboot = true,
                overlayRoots = listOf("/data/adb/modules"),
            ),
        )
        val r3Broker = PluginBroker(canonicalStage("stage-r3"), runner)
        val r3 = r3Broker.stage("r3", r3Archive, PluginArchiveValidator.sha256(r3Archive))
        assertEquals(
            PluginBrokerErrorCode.CONFIRMATION_REQUIRED,
            expectBrokerError { r3Broker.install(r3) }.code,
        )
        val installed = r3Broker.install(r3, PluginConfirmation.USER_CONFIRMED)
        assertEquals(
            listOf(PluginKsudOperation.INSTALL, PluginKsudOperation.DISABLE),
            installed.operations,
        )
        assertEquals(
            PluginBrokerErrorCode.CONFIRMATION_REQUIRED,
            expectBrokerError { r3Broker.enable(r3) }.code,
        )
        r3Broker.enable(r3, PluginConfirmation.DEVICE_CREDENTIAL_CONFIRMED)
        assertEquals(
            listOf(
                PluginKsudOperation.INSTALL,
                PluginKsudOperation.DISABLE,
                PluginKsudOperation.ENABLE,
            ),
            calls,
        )
    }

    @Test
    fun `R4 boot-chain module requires explicit confirmation but is not permanently blocked`() {
        val calls = mutableListOf<PluginKsudOperation>()
        val runner = PluginKsudRunner { operation, _ ->
            calls += operation
            PluginKsudResult(0)
        }
        val broker = PluginBroker(canonicalStage("stage-r4"), runner)
        val firstBootArchive = archive(
            manifest = manifestJson(
                version = "1.0.0",
                capabilities = listOf("boot-chain"),
                overlayRoots = emptyList(),
            ),
            modulePropText = moduleProp(version = "1.0.0"),
        )
        val secondBootArchive = archive(
            manifest = manifestJson(
                version = "2.0.0",
                capabilities = listOf("boot-chain"),
                overlayRoots = emptyList(),
            ),
            modulePropText = moduleProp(version = "2.0.0"),
        )
        val first = broker.stage(
            "r4-boot-chain-first",
            firstBootArchive,
            PluginArchiveValidator.sha256(firstBootArchive),
        )

        assertEquals(PluginRisk.R4, first.archive.effectiveRisk)
        assertEquals(
            PluginBrokerErrorCode.CONFIRMATION_REQUIRED,
            expectBrokerError { broker.install(first) }.code,
        )
        assertTrue(calls.isEmpty())

        val installed = broker.install(first, PluginConfirmation.USER_CONFIRMED)
        assertEquals(
            listOf(PluginKsudOperation.INSTALL, PluginKsudOperation.DISABLE),
            installed.operations,
        )

        val replacement = broker.stage(
            "r4-boot-chain-second",
            secondBootArchive,
            PluginArchiveValidator.sha256(secondBootArchive),
        )
        broker.install(replacement, PluginConfirmation.USER_CONFIRMED)
        assertEquals(
            PluginBrokerErrorCode.CONFIRMATION_REQUIRED,
            expectBrokerError { broker.rollback(replacement) }.code,
        )
        val rollback = broker.rollback(replacement, PluginConfirmation.USER_CONFIRMED)
        assertEquals("1.0.0", rollback.staged.archive.manifest.version)
        assertEquals(
            listOf(PluginKsudOperation.INSTALL, PluginKsudOperation.DISABLE),
            rollback.operation.operations,
        )
        assertEquals(
            PluginBrokerErrorCode.CONFIRMATION_REQUIRED,
            expectBrokerError { broker.enable(rollback.staged) }.code,
        )
        broker.enable(rollback.staged, PluginConfirmation.USER_CONFIRMED)
        broker.disable(rollback.staged)
        broker.uninstall(rollback.staged)

        assertEquals(
            listOf(
                PluginKsudOperation.INSTALL,
                PluginKsudOperation.DISABLE,
                PluginKsudOperation.INSTALL,
                PluginKsudOperation.DISABLE,
                PluginKsudOperation.INSTALL,
                PluginKsudOperation.DISABLE,
                PluginKsudOperation.ENABLE,
                PluginKsudOperation.DISABLE,
                PluginKsudOperation.UNINSTALL,
            ),
            calls,
        )
    }

    @Test
    fun `R2 requires confirmation backup and health declarations`() {
        val calls = mutableListOf<PluginKsudOperation>()
        val runner = PluginKsudRunner { operation, _ ->
            calls += operation
            PluginKsudResult(0)
        }
        val broker = PluginBroker(canonicalStage("stage"), runner)
        val r2Archive = archive(
            manifest = manifestJson(
                actions = listOf("configure"),
                overlayRoots = emptyList(),
                backupTargets = listOf("/data/adb/modules/demo/config"),
                healthChecks = listOf("module_loaded"),
            ),
        )
        val staged = broker.stage("r2", r2Archive, PluginArchiveValidator.sha256(r2Archive))
        assertEquals(PluginRisk.R2, staged.archive.effectiveRisk)
        assertEquals(
            PluginBrokerErrorCode.CONFIRMATION_REQUIRED,
            expectBrokerError { broker.install(staged) }.code,
        )
        broker.install(staged, PluginConfirmation.USER_CONFIRMED)
        assertEquals(
            listOf(PluginKsudOperation.INSTALL, PluginKsudOperation.ENABLE),
            calls,
        )
    }

    @Test
    fun `R2 runAction requires a declared action and explicit confirmation`() {
        val calls = mutableListOf<PluginKsudOperation>()
        val runner = PluginKsudRunner { operation, _ ->
            calls += operation
            PluginKsudResult(0)
        }
        val broker = PluginBroker(canonicalStage("stage-action"), runner)
        val actionArchive = archive(
            manifest = manifestJson(
                actions = listOf("configure"),
                overlayRoots = emptyList(),
                backupTargets = listOf("/data/adb/modules/demo/config"),
                healthChecks = listOf("module_loaded"),
            ),
        )
        val staged = broker.stage("action", actionArchive, PluginArchiveValidator.sha256(actionArchive))

        assertEquals(
            PluginBrokerErrorCode.CONFIRMATION_REQUIRED,
            expectBrokerError { broker.runAction(staged, "configure") }.code,
        )
        assertTrue(calls.isEmpty())
        assertEquals(
            PluginBrokerErrorCode.ACTION_NOT_DECLARED,
            expectBrokerError {
                broker.runAction(staged, "configure;touch", PluginConfirmation.USER_CONFIRMED)
            }.code,
        )
        assertTrue(calls.isEmpty())

        val result = broker.runAction(
            staged,
            "configure",
            PluginConfirmation.USER_CONFIRMED,
        )
        assertEquals(listOf(PluginKsudOperation.ACTION), result.operations)
        assertEquals(listOf(PluginKsudOperation.ACTION), calls)
    }

    @Test
    fun `staged archive replacement is rejected before ksud`() {
        val calls = mutableListOf<PluginKsudOperation>()
        val broker = PluginBroker(
            canonicalStage("stage-integrity"),
            PluginKsudRunner { operation, _ ->
                calls += operation
                PluginKsudResult(0)
            },
        )
        val archive = archive()
        val staged = broker.stage("integrity", archive, PluginArchiveValidator.sha256(archive))
        staged.stagedFile.writeText("replacement")

        assertEquals(
            PluginBrokerErrorCode.NOT_STAGED,
            expectBrokerError { broker.install(staged) }.code,
        )
        assertTrue(calls.isEmpty())
    }

    @Test
    fun `staging rejects a symlinked parent directory`() {
        val root = temporaryFolder.newFolder("stage-parent")
        val outside = temporaryFolder.newFolder("stage-outside")
        val link = Files.createSymbolicLink(
            root.toPath().resolve("link"),
            outside.toPath(),
        )
        val broker = PluginBroker(
            link.resolve("stage").toFile(),
            PluginKsudRunner { _, _ -> PluginKsudResult(0) },
        )
        val archive = archive()

        val exception = expectBrokerError {
            broker.stage("symlink-parent", archive, PluginArchiveValidator.sha256(archive))
        }
        assertEquals(PluginBrokerErrorCode.STAGING_UNSAFE, exception.code)
    }

    @Test
    fun `staging rejects a symlinked ancestor before creating descendants`() {
        val root = temporaryFolder.newFolder("stage-ancestor")
        val outside = temporaryFolder.newFolder("stage-ancestor-outside")
        val link = Files.createSymbolicLink(
            root.toPath().resolve("link"),
            outside.toPath(),
        )
        val broker = PluginBroker(
            link.resolve("missing").resolve("stage").toFile(),
            PluginKsudRunner { _, _ -> PluginKsudResult(0) },
        )
        val archive = archive()

        val exception = expectBrokerError {
            broker.stage("symlink-ancestor", archive, PluginArchiveValidator.sha256(archive))
        }
        assertEquals(PluginBrokerErrorCode.STAGING_UNSAFE, exception.code)
        assertFalse(outside.resolve("missing").exists())
    }

    @Test
    fun `runner failures expose no raw diagnostics`() {
        val broker = PluginBroker(
            canonicalStage("stage"),
            PluginKsudRunner { _, _ ->
                throw IllegalStateException("/private/secret/raw stderr")
            },
        )
        val archive = archive()
        val staged = broker.stage("raw-boundary", archive, PluginArchiveValidator.sha256(archive))
        val exception = expectBrokerError { broker.install(staged) }

        assertEquals(PluginBrokerErrorCode.KSUD_OPERATION_FAILED, exception.code)
        assertEquals("KernelSU operation failed", exception.message)
        assertFalse(exception.message.orEmpty().contains("/private/secret"))
        assertFalse(exception.toString().contains("raw stderr"))
    }

    @Test
    fun `capability probe requires a successful fixed module list`() {
        val calls = mutableListOf<Pair<PluginKsudOperation, String>>()
        val broker = PluginBroker(
            canonicalStage("capability-success"),
            PluginKsudRunner { operation, moduleId ->
                calls += operation to moduleId.value
                PluginKsudResult(0)
            },
        )

        val result = broker.capabilityProbe()

        assertTrue(result.available)
        assertEquals(PluginBrokerCapabilityState.AVAILABLE, result.state)
        assertEquals(null, result.errorCode)
        assertEquals(
            listOf(
                PluginKsudOperation.LIST to "ccpocket.plugin.capability_probe",
            ),
            calls,
        )
        assertEquals(
            mapOf(
                "available" to true,
                "state" to "available",
            ),
            result.asMap(),
        )
    }

    @Test
    fun `capability probe fails closed without diagnostics or root equivalence`() {
        val broker = PluginBroker(
            canonicalStage("capability-failure"),
            PluginKsudRunner { _, _ ->
                throw IllegalStateException("/private/secret stdout stderr")
            },
        )

        val result = broker.probe()

        assertFalse(result.available)
        assertEquals(PluginBrokerCapabilityState.UNAVAILABLE, result.state)
        assertEquals(
            PluginBrokerErrorCode.KSUD_OPERATION_FAILED,
            result.errorCode,
        )
        assertEquals(
            mapOf(
                "available" to false,
                "state" to "unavailable",
                "errorCode" to "ksud_operation_failed",
            ),
            result.asMap(),
        )
        assertFalse(result.asMap().toString().contains("/private/secret"))
        assertFalse(result.asMap().toString().contains("stdout"))
        assertFalse(result.asMap().toString().contains("stderr"))
    }

    @Test
    fun `module list parses safe state fields without exposing raw output`() {
        val runner = PluginKsudRunner { operation, _ ->
            if (operation != PluginKsudOperation.LIST) return@PluginKsudRunner PluginKsudResult(0)
            PluginKsudResult(
                0,
                """
                [
                  {"id":"ccpocket.plugin.demo","name":"Demo","version":"1.2.3","author":"Tester","enabled":"true"},
                  {"id":"bad\u0000entry","name":"ignored","enabled":"false"},
                  {"id":"ccpocket.plugin.off","name":"Off","version":"0.1","enabled":"false"},
                  {"id":"ccpocket.plugin.removed","name":"Removed","version":"0.1","enabled":"false","remove":"true"}
                ]
                """.trimIndent(),
            )
        }
        val broker = PluginBroker(canonicalStage("module-list"), runner)

        val result = broker.list("ccpocket.plugin.capability_probe")

        assertEquals(
            listOf(
                PluginModuleSummary(
                    id = "ccpocket.plugin.demo",
                    name = "Demo",
                    version = "1.2.3",
                    author = "Tester",
                    enabled = true,
                ),
                PluginModuleSummary(
                    id = "ccpocket.plugin.off",
                    name = "Off",
                    version = "0.1",
                    author = "",
                    enabled = false,
                ),
            ),
            result.modules,
        )
    }

    @Test
    fun `latest staged archive restores after broker recreation without root`() {
        val stageRoot = canonicalStage("stage-restore")
        val archive = archive(
            manifest = manifestJson(version = "3.0.0"),
            modulePropText = moduleProp(version = "3.0.0"),
        )
        val firstBroker = PluginBroker(stageRoot)
        firstBroker.stage("persisted", archive, PluginArchiveValidator.sha256(archive))

        val restored = PluginBroker(stageRoot).restoreLatestStaged()

        assertTrue(restored != null)
        assertEquals("restored", restored?.requestId)
        assertEquals("ccpocket.plugin.demo", restored?.moduleId?.value)
        assertEquals("3.0.0", restored?.archive?.manifest?.version)
        assertEquals(PluginArchiveValidator.sha256(archive), restored?.archive?.sha256)
    }

    @Test
    fun `production runner capability probe uses only typed fixed list`() {
        val stagingRoot = temporaryFolder.newFolder("capability-root-helper")
        var probeCalled = false
        val runner = ProcessPluginKsudRunner(
            stagingRoot = stagingRoot,
            rootHelper = object : PluginKsudRootHelper {
                override fun run(
                    operation: PluginKsudOperation,
                    moduleId: VerifiedPluginModuleId,
                    stagingRoot: File,
                ): PluginKsudResult = PluginKsudResult(-1)

                override fun probe(): PluginKsudResult {
                    probeCalled = true
                    return PluginKsudResult(0)
                }
            },
        )

        val result = runner.probe()

        assertEquals(0, result.exitCode)
        assertTrue(probeCalled)
        assertEquals(
            listOf("/data/adb/ksu/bin/ksud", "module", "list"),
            PluginKsudCommandBuilder.buildCapabilityProbe(),
        )
    }

    @Test
    fun `runner command has fixed argv and validated module identity`() {
        val moduleId = VerifiedPluginModuleId.parse("ccpocket.plugin.demo")
        val command = PluginKsudCommandBuilder.build(
            operation = PluginKsudOperation.INSTALL,
            moduleId = moduleId,
            stagingRoot = File("/tmp/plugin-stage"),
        )
        assertEquals(
            listOf(
                "/data/adb/ksu/bin/ksud",
                "module",
                "install",
                "/tmp/plugin-stage/ccpocket.plugin.demo.zip",
            ),
            command,
        )
        assertFalse(command.any { it.contains("sh -c") })
    }

    @Test
    fun productionRunnerDelegatesThroughTypedRootHelper() {
        val stagingRoot = temporaryFolder.newFolder("root-helper-seam")
        var seen: Triple<PluginKsudOperation, String, File>? = null
        val runner = ProcessPluginKsudRunner(
            stagingRoot = stagingRoot,
            rootHelper = PluginKsudRootHelper { operation, moduleId, root ->
                seen = Triple(operation, moduleId.value, root)
                PluginKsudResult(0)
            },
        )

        assertEquals(
            0,
            runner.run(
                operation = PluginKsudOperation.ENABLE,
                moduleId = VerifiedPluginModuleId.parse("ccpocket.plugin.demo"),
            ).exitCode,
        )
        assertEquals(
            Triple(PluginKsudOperation.ENABLE, "ccpocket.plugin.demo", stagingRoot),
            seen,
        )
    }

    @Test
    fun rootHelperCommandIsFixedArgvEncodedInsideSuBoundary() {
        val command = PluginKsudRootCommandBuilder.build(
            operation = PluginKsudOperation.INSTALL,
            moduleId = VerifiedPluginModuleId.parse("ccpocket.plugin.demo"),
            stagingRoot = File("/tmp/plugin-stage;touch /tmp/untrusted"),
        )

        assertEquals(
            "exec '/data/adb/ksu/bin/ksud' 'module' 'install' " +
                "'/tmp/plugin-stage;touch /tmp/untrusted/ccpocket.plugin.demo.zip'",
            command,
        )
        assertFalse(command.contains("sh -c"))
        assertFalse(command.contains("su -c"))
    }

    @Test
    fun installRootHelperUsesOneTimeRootOwnedArchiveInput() {
        val digest = "a".repeat(64)
        val temporaryPath =
            "/data/adb/ksu/tmp/ccpocket-plugin-0123456789abcdef0123456789abcdef.zip"
        val command = PluginKsudRootCommandBuilder.buildInstallFromStdin(
            moduleId = VerifiedPluginModuleId.parse("ccpocket.plugin.demo"),
            temporaryArchive = File(temporaryPath),
            archiveSha256 = digest,
        )

        assertEquals(
            listOf(
                "/data/adb/ksu/bin/ksud",
                "module",
                "install",
                temporaryPath,
            ),
            PluginKsudCommandBuilder.buildInstall(File(temporaryPath)),
        )
        assertFalse(
            command.contains(
                "'$temporaryPath/ccpocket.plugin.demo.zip'",
            ),
        )
        assertTrue(command.contains("busybox"))
        assertTrue(command.contains("sha256sum"))
        assertTrue(command.contains("ccpocket-plugin-0123456789abcdef0123456789abcdef.zip"))
        assertTrue(command.contains(digest))
        assertFalse(command.contains("/tmp/plugin-stage"))
        assertFalse(command.contains("/data/user/"))
    }

    private fun expectBrokerError(block: () -> Unit): PluginBrokerException =
        try {
            block()
            throw AssertionError("expected PluginBrokerException")
        } catch (error: PluginBrokerException) {
            error
        }

    private fun canonicalStage(name: String): File =
        temporaryFolder.newFolder(name).canonicalFile

    private data class Member(
        val name: String,
        val content: String,
        val unixMode: Int? = null,
        val extra: ByteArray? = null,
    )

    private fun archive(
        manifest: String = manifestJson(),
        modulePropText: String = moduleProp(),
        extraMembers: List<Member> = emptyList(),
    ): ByteArray {
        val output = ByteArrayOutputStream()
        ZipOutputStream(output).use { zip ->
            add(zip, "module.prop", modulePropText, null)
            add(zip, PluginManifest.FILE_NAME, manifest, null)
            for (member in extraMembers) {
                add(zip, member.name, member.content, member)
            }
        }
        var bytes = output.toByteArray()
        for (member in extraMembers) {
            if (member.unixMode != null) {
                bytes = patchUnixMode(bytes, member.name, member.unixMode)
            }
        }
        return bytes
    }

    private fun add(
        zip: ZipOutputStream,
        name: String,
        content: String,
        member: Member?,
    ) {
        val entry = ZipEntry(name)
        member?.extra?.let(entry::setExtra)
        zip.putNextEntry(entry)
        zip.write(content.toByteArray(StandardCharsets.UTF_8))
        zip.closeEntry()
    }

    private fun patchUnixMode(bytes: ByteArray, name: String, mode: Int): ByteArray {
        val patched = bytes.copyOf()
        var offset = 0
        var found = false
        while (offset + 46 <= patched.size) {
            if (readLe32(patched, offset) == CENTRAL_SIGNATURE) {
                val nameLength = readLe16(patched, offset + 28)
                val extraLength = readLe16(patched, offset + 30)
                val commentLength = readLe16(patched, offset + 32)
                val entryName = String(
                    patched,
                    offset + 46,
                    nameLength,
                    StandardCharsets.UTF_8,
                )
                if (entryName == name) {
                    writeLe16(patched, offset + 4, (3 shl 8) or 20)
                    writeLe32(patched, offset + 38, mode.toLong() shl 16)
                    found = true
                    break
                }
                offset += 46 + nameLength + extraLength + commentLength
            } else {
                offset += 1
            }
        }
        check(found)
        return patched
    }

    private fun hardlinkExtra(): ByteArray {
        val marker = "hardlink".toByteArray(StandardCharsets.ISO_8859_1)
        return byteArrayOf(
            0x53,
            0x44,
            marker.size.toByte(),
            0x00,
        ) + marker
    }

    private fun manifestJson(
        id: String = "ccpocket.plugin.demo",
        version: String = "1.0.0",
        riskHint: String = "R1",
        capabilities: List<String> = listOf("declarative-overlay"),
        requiresReboot: Boolean = false,
        reversible: Boolean = true,
        overlayRoots: List<String> = listOf("/data/adb/modules"),
        actions: List<String> = emptyList(),
        backupTargets: List<String> = emptyList(),
        healthChecks: List<String> = emptyList(),
    ): String = """
        {
          "schemaVersion":1,
          "id":"$id",
          "name":"Demo Plugin",
          "version":"$version",
          "capabilities":${jsonArray(capabilities)},
          "riskHint":"$riskHint",
          "requiresReboot":$requiresReboot,
          "reversible":$reversible,
          "overlayRoots":${jsonArray(overlayRoots)},
          "actions":${jsonArray(actions)},
          "backupTargets":${jsonArray(backupTargets)},
          "healthChecks":${jsonArray(healthChecks)}
        }
    """.trimIndent()

    private fun jsonArray(values: List<String>): String =
        values.joinToString(prefix = "[", postfix = "]") { "\"$it\"" }

    private fun moduleProp(
        id: String = "ccpocket.plugin.demo",
        version: String = "1.0.0",
    ): String = """
        id=$id
        name=Demo Plugin
        version=$version
        versionCode=1
        author=CC Pocket
        description=Declarative test module
    """.trimIndent()

    private fun readLe16(bytes: ByteArray, offset: Int): Int =
        (bytes[offset].toInt() and 0xff) or
            ((bytes[offset + 1].toInt() and 0xff) shl 8)

    private fun readLe32(bytes: ByteArray, offset: Int): Long =
        (bytes[offset].toLong() and 0xff) or
            ((bytes[offset + 1].toLong() and 0xff) shl 8) or
            ((bytes[offset + 2].toLong() and 0xff) shl 16) or
            ((bytes[offset + 3].toLong() and 0xff) shl 24)

    private fun writeLe16(bytes: ByteArray, offset: Int, value: Int) {
        bytes[offset] = value.toByte()
        bytes[offset + 1] = (value ushr 8).toByte()
    }

    private fun writeLe32(bytes: ByteArray, offset: Int, value: Long) {
        bytes[offset] = value.toByte()
        bytes[offset + 1] = (value ushr 8).toByte()
        bytes[offset + 2] = (value ushr 16).toByte()
        bytes[offset + 3] = (value ushr 24).toByte()
    }

    private companion object {
        const val CENTRAL_SIGNATURE = 0x02014b50L
    }
}
