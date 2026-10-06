import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: android/key.properties locally, or SIDDUR_KEYSTORE_*
// environment variables in CI (see signingConfigs below).
val keyProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
fun keyValue(prop: String, env: String): String? = keyProps.getProperty(prop) ?: System.getenv(env)
val storeFilePath = keyValue("storeFile", "SIDDUR_KEYSTORE_FILE")

android {
    namespace = "page.amud"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications uses java.time APIs via desugaring.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "page.amud"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Where the app is distributed. "github": the APK on GitHub Releases,
    // which updates itself (lib/features/update). "play": Google Play, which
    // handles updates, so the self-updater and REQUEST_INSTALL_PACKAGES are
    // left out (src/play/AndroidManifest.xml; Dart checks appFlavor).
    // Android builds need --flavor github or --flavor play.
    flavorDimensions += "store"
    productFlavors {
        create("github") { dimension = "store" }
        create("play") { dimension = "store" }
    }

    // Every release must use the same key or Android refuses to install it
    // as an update. Without one, builds fall back to the debug key (fine for
    // local testing only), except Play releases (see the check below).
    signingConfigs {
        if (storeFilePath != null) {
            create("release") {
                storeFile = file(storeFilePath)
                storePassword = keyValue("storePassword", "SIDDUR_KEYSTORE_PASSWORD")
                keyAlias = keyValue("keyAlias", "SIDDUR_KEY_ALIAS")
                keyPassword = keyValue("keyPassword", "SIDDUR_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
        }
    }
}

// A Play release signed with the debug key would be rejected on upload.
gradle.taskGraph.whenReady {
    if (storeFilePath == null && allTasks.any { it.name.contains("PlayRelease") }) {
        throw GradleException("Play releases need the upload key: set android/key.properties or SIDDUR_KEYSTORE_FILE.")
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // FileProvider for handing update APKs to the installer (MainActivity).
    implementation("androidx.core:core:1.13.1")
    implementation("com.google.android.gms:play-services-wearable:19.0.0")
}
