plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.fahad1"
    // compileSdk 36 is REQUIRED by plugins (mobile_scanner, sqflite, androidx
    // core 1.18). Force the STABLE 36.0.0 build-tools (not the rc preview).
    compileSdk = 36
    buildToolsVersion = "36.0.0"
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.fahad1"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // minSdk 23 (Android 6): wider device support AND it makes the build
        // tools include v1 (JAR) signing, which v2-only APKs lack — the cause
        // of "There was a problem parsing the package" on some phones.
        minSdk = flutter.minSdkVersion
        // Stable target (Android 15) — not the API 36 preview.
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        getByName("debug") {
            // Force v1 (JAR) signing back ON. With minSdk 24 the build tools
            // otherwise drop v1 and sign with v2 only, which makes some phones
            // reject the APK with "There was a problem parsing the package".
            enableV1Signing = true
            enableV2Signing = true
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
