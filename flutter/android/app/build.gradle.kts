// uwuHere for Android: Flutter's screens (lib/) with the Java in src/main/java/org/uwuapps/here/
// for what only a phone can do (README.md).
import java.util.Properties

plugins {
    id("com.android.application")
    // Flutter's Gradle plugin, after Android's.
    id("dev.flutter.flutter-gradle-plugin")
}

// A Google Play build (build-apk.ps1 -Aab): no updater of its own, as Play updates the app.
val playBuild = project.hasProperty("uwuherePlay")

// Signed with the app's own key, from flutter/keystore.properties and flutter/android.keystore,
// both kept out of git (README.md). An APK signed with another key can't update an installed
// one. Without them, a build for trying out is signed with the debug key, which build-apk.ps1
// refuses.
val keystoreProps = Properties().apply {
    val f = rootProject.file("../keystore.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

android {
    namespace = "org.uwuapps.here"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // java.time and friends on older Androids, which flutter_local_notifications needs.
        isCoreLibraryDesugaringEnabled = true
    }

    buildFeatures {
        buildConfig = true
    }

    defaultConfig {
        // Permanent: the signing key, verified links, push and the store listing hang on it.
        applicationId = "org.uwuapps.here"
        minSdk = maxOf(flutter.minSdkVersion, 24)
        targetSdk = flutter.targetSdkVersion
        // From pubspec.yaml's version (1.0.0+1 is versionName 1.0.0, versionCode 1).
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        buildConfigField("boolean", "PLAY", playBuild.toString())
    }

    signingConfigs {
        create("release") {
            val store = keystoreProps.getProperty("storeFile")
            if (store != null) {
                storeFile = rootProject.file("../$store")
                storePassword = keystoreProps.getProperty("storePassword")
                keyAlias = keystoreProps.getProperty("keyAlias")
                keyPassword = keystoreProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        getByName("release") {
            // R8 shrinks and obfuscates the Java and its libraries, and unused resources go,
            // as Google Play recommends (and measures as "DEX code optimisation"). What it
            // mustn't rename is in proguard-rules.pro. The Dart side is obfuscated by
            // build-apk.ps1 (--obfuscate --split-debug-info). The mapping that reads crashes
            // back goes into the App Bundle for Play, and beside the APK in release/<version>/.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = if (keystoreProps.getProperty("storeFile") != null) signingConfigs.getByName("release") else signingConfigs.getByName("debug")
            // The native libraries' symbols, stripped from the app but kept in the App Bundle's
            // metadata, so Play's crash reports name the functions.
            ndk {
                debugSymbolLevel = "SYMBOL_TABLE"
            }
        }
    }

    // The Play build's manifest takes the updater and its permission out (src/play/).
    if (playBuild) {
        sourceSets.getByName("release").manifest.srcFile("src/play/AndroidManifest.xml")
    }
}

// A release for phones' processors only: WebRTC (same-wifi check-in) brings x86 copies of its library too,
// for emulators, 16 MB of them. A debug build keeps them, for an emulator. (Flutter's plugin sets
// abiFilters itself, so they're left out of the package instead.)
// The Play build keeps them: Play hands each device only its own processor's files, and x86_64
// Chromebooks need them.
if (!playBuild) {
    androidComponents {
        onVariants(selector().withBuildType("release")) { variant ->
            variant.packaging.jniLibs.excludes.add("lib/x86/**")
            variant.packaging.jniLibs.excludes.add("lib/x86_64/**")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    implementation("androidx.core:core:1.15.0")
    // Notifications: check-ins to your events, new versions and news (FIREBASE-SETUP.md). In every
    // build; it only works once google-services.json is there.
    implementation("com.google.firebase:firebase-messaging:24.1.0")
    // Bluetooth check-in, app to app (Mesh). Not 19.5: built with a newer Kotlin than this build
    // reads.
    implementation("com.google.android.gms:play-services-nearby:19.3.0")
    // The "Your event" widget's refresh while the app is closed (WidgetWorker).
    implementation("androidx.work:work-runtime:2.10.0")
}

// Firebase is set up for this build: the server can push to it (FIREBASE-SETUP.md). Without
// google-services.json the app builds and works, but gets no notifications.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
} else {
    logger.lifecycle("google-services.json not found: building without Firebase (FIREBASE-SETUP.md).")
}
