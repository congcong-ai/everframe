plugins {
    id("com.android.application") version "8.13.2" apply false
    id("org.jetbrains.kotlin.android") version "2.2.21" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.2.21" apply false
    id("org.jetbrains.kotlin.plugin.serialization") version "2.2.21" apply false
}
allprojects {
    layout.buildDirectory.set(file("${System.getenv("EVERFRAME_BUILD_DIR") ?: System.getProperty("java.io.tmpdir") + "/everframe-android-build"}/${project.name}"))
}
