plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release credentials stay outside the repository. The ordinary release build
// remains installable with the debug key for local QA; a maintainer can require
// a real signing configuration through tools/build-android.ps1.
val releaseStoreFile = System.getenv("CODEX_RELEASE_STORE_FILE")
val releaseStorePassword = System.getenv("CODEX_RELEASE_STORE_PASSWORD")
val releaseKeyAlias = System.getenv("CODEX_RELEASE_KEY_ALIAS")
val releaseKeyPassword = System.getenv("CODEX_RELEASE_KEY_PASSWORD")
val hasReleaseSigning = listOf(
    releaseStoreFile,
    releaseStorePassword,
    releaseKeyAlias,
    releaseKeyPassword,
).all { !it.isNullOrBlank() }

android {
    namespace = "io.henry.codex"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "io.henry.codex"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // PRoot and its static loader/trampoline are verified build inputs, not
    // source-controlled binaries. A local build may provide a directory with
    // the normal `arm64-v8a/` layout through CODEX_PROOT_ASSET_DIR; without it
    // the app deliberately builds with the compatibility backend unavailable.
    val prootAssetDir = System.getenv("CODEX_PROOT_ASSET_DIR")
        ?.takeIf { it.isNotBlank() }
        ?.let(::file)
    if (prootAssetDir != null) {
        sourceSets.getByName("main").jniLibs.srcDir(prootAssetDir)
    }

    // Keep the standalone Android/PRoot guide as the source of truth and
    // package it for the per-session CODEX_HOME seeder. Only AGENTS.md is
    // loaded as global Codex guidance; sibling skill files remain inert assets.
    sourceSets.getByName("main").assets.srcDir(
        file("../../../../tools/android-local-runtime/skills"),
    )
    // Package the canonical ARM64 guest finalizer and its fixed in-app
    // installer entry point. Both are invoked only after the user selects a
    // rootfs archive from Settings and KernelSU confirms UID 0.
    sourceSets.getByName("main").assets.srcDir(
        file("../../../../tools/android-local-runtime/device"),
    )

    // The compatibility worker launches these files by absolute path from
    // ApplicationInfo.nativeLibraryDir. Keep JNI packaging in legacy/extracted
    // mode so Android materializes the optional PRoot assets on disk instead
    // of leaving them only inside the APK.
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.create("codexRelease") {
                    storeFile = file(releaseStoreFile!!)
                    storePassword = releaseStorePassword
                    keyAlias = releaseKeyAlias
                    keyPassword = releaseKeyPassword
                }
            } else {
                // Local QA remains possible without placing a real keystore in
                // the checkout. A release build made this way is not a store
                // artifact and is reported as debug-key signed by the verifier.
                signingConfigs.getByName("debug")
            }
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    testImplementation("junit:junit:4.13.2")
    // The Android SDK exposes org.json to the app, but the local JVM test
    // runtime only provides throwing stubs. Use the reference implementation
    // for SessionHistoryStore tests without changing the APK dependency graph.
    testImplementation("org.json:json:20240303")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
