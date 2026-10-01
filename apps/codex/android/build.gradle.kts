allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Keep Flutter's conventional output at <flutter-project>/build. Resolve the
// paths to concrete java.io.File values: Flutter 3.47's Gradle task passes its
// intermediate directory through Project.file(), and a provider-backed
// Directory can become a path with no parent on this Windows/Gradle pair.
val newBuildDir = file("../build")
rootProject.layout.buildDirectory.set(newBuildDir)

subprojects {
    // `file(...)` is resolved relative to each subproject, which would put
    // outputs back under android/build. Resolve from the root project so
    // Flutter can find the APK under the Flutter project's build directory.
    project.layout.buildDirectory.set(rootProject.file("../build/${project.name}"))
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
