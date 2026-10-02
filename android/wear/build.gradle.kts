import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}
val flutterVersions = Properties().apply { rootProject.file("local.properties").inputStream().use { load(it) } }
android {
    namespace = "page.amud.wear"
    compileSdk = 36
    defaultConfig {
        // Data Layer pairs applications with the same ID and signing key.
        applicationId = "page.amud"
        minSdk = 26
        targetSdk = 36
        versionCode = (flutterVersions.getProperty("flutter.versionCode") ?: "1").toInt()
        versionName = flutterVersions.getProperty("flutter.versionName") ?: "0.6.1"
    }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
    kotlinOptions { jvmTarget = JavaVersion.VERSION_17.toString() }
    val keys = Properties().apply { val f = rootProject.file("key.properties"); if (f.exists()) f.inputStream().use { load(it) } }
    fun value(key: String, env: String) = keys.getProperty(key) ?: System.getenv(env)
    val store = value("storeFile", "SIDDUR_KEYSTORE_FILE")
    signingConfigs {
        if (store != null) create("release") {
            storeFile = rootProject.file("app").resolve(store)
            storePassword = value("storePassword", "SIDDUR_KEYSTORE_PASSWORD")
            keyAlias = value("keyAlias", "SIDDUR_KEY_ALIAS")
            keyPassword = value("keyPassword", "SIDDUR_KEY_PASSWORD")
        }
    }
    buildTypes { release { signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug") } }
}
dependencies {
    implementation("com.google.android.gms:play-services-wearable:19.0.0")
    implementation("androidx.wear.tiles:tiles:1.5.0")
    implementation("androidx.wear.protolayout:protolayout:1.3.0")
    implementation("androidx.wear.watchface:watchface-complications-data-source:1.2.1")
    implementation("com.google.guava:guava:33.4.0-android")
}
