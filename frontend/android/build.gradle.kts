allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// file_picker 11.0.3's own android/build.gradle skips applying the Kotlin
// Android plugin whenever AGP >= 9, assuming AGP's "built-in Kotlin" support
// will compile its Kotlin sources instead — but this project disables that
// support (android.builtInKotlin=false in gradle.properties, set by the
// Flutter template because built-in Kotlin isn't reliable yet on this AGP/
// Flutter combination). The 12.0.0 betas fix this by checking that gradle
// property, but they can't be adopted yet (win32 version conflict with
// flutter_secure_storage). Until then, force the plugin on for file_picker
// specifically so its Kotlin classes actually get compiled.
subprojects {
    if (project.name == "file_picker") {
        project.pluginManager.apply("org.jetbrains.kotlin.android")
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
