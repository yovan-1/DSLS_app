import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasReleaseSigning = keystorePropertiesFile.exists()
if (hasReleaseSigning) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.dsls.app"
    // Pinned rather than inherited from the Flutter toolchain. Foreground
    // service behaviour is API-level dependent — Android 14 requires a declared
    // foregroundServiceType, Android 11+ changed how background location is
    // granted — and that must not shift underneath us on a toolchain upgrade.
    // These are the values the current SDK resolves to; changing them is a
    // deliberate act with device testing attached.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // Immutable once published to the Play Store — do not change casually.
        applicationId = "com.dsls.app"
        // Pinned alongside compileSdk above. minSdk 24 satisfies every plugin
        // in use (flutter_foreground_task needs 21, geolocator 21).
        minSdk = 24
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                logger.warn("No android/key.properties found — release build is falling back to the DEBUG keystore. This is expected in CI unless signing secrets are configured; see DEVELOPER_GUIDE.md.")
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

