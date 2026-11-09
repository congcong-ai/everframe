import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
}
val playSigningPropertiesFile = System.getenv("EVERFRAME_PLAY_SIGNING_PROPERTIES")
    ?.let(::file)
    ?: file("${System.getProperty("user.home")}/.config/everframe/google-play/everframe/signing.properties")
val playSigningProperties = Properties()
if (playSigningPropertiesFile.isFile) {
    playSigningPropertiesFile.inputStream().use { playSigningProperties.load(it) }
} else if (gradle.startParameter.taskNames.any {
        it.contains("bundleRelease", ignoreCase = true)
    }) {
    throw GradleException("Google Play upload signing is not configured. Set EVERFRAME_PLAY_SIGNING_PROPERTIES.")
}
android {
    namespace = "com.everframe.app"
    compileSdk = 36
    defaultConfig {
        applicationId = "com.bebackpacker.everframe"
        minSdk = 26
        targetSdk = 36
        versionCode = 3
        versionName = "0.2.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }
    if (playSigningPropertiesFile.isFile) {
        signingConfigs {
            create("playRelease") {
                storeFile = file(requireNotNull(playSigningProperties.getProperty("storeFile")))
                storePassword = requireNotNull(playSigningProperties.getProperty("storePassword"))
                keyAlias = requireNotNull(playSigningProperties.getProperty("keyAlias"))
                keyPassword = requireNotNull(playSigningProperties.getProperty("keyPassword"))
            }
        }
    }
    buildTypes {
        release {
            if (playSigningPropertiesFile.isFile) {
                signingConfig = signingConfigs.getByName("playRelease")
            }
            ndk { debugSymbolLevel = "FULL" }
        }
    }
    buildFeatures { compose = true; buildConfig = true }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
    sourceSets["main"].assets.srcDir("../../EverFrame/Web")
    sourceSets["test"].resources.srcDir("../../shared/fixtures")
    testOptions { unitTests.isReturnDefaultValues = true }
    packaging { resources.excludes += "/META-INF/{AL2.0,LGPL2.1}" }
}
kotlin { compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) } }
dependencies {
    implementation(platform("androidx.compose:compose-bom:2025.10.00"))
    implementation("androidx.activity:activity-compose:1.11.0")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.9.4")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.9.4")
    implementation("androidx.lifecycle:lifecycle-service:2.9.4")
    implementation("androidx.core:core-ktx:1.17.0")
    for (module in listOf("camera-camera2", "camera-lifecycle", "camera-video", "camera-view")) {
        implementation("androidx.camera:$module:1.6.2")
    }
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.9.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.10.2")
}
