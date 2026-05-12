plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.voicenotesummarizer.vm_summ"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "28.2.13676358"

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    buildFeatures {
        buildConfig = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.voicenotesummarizer.vm_summ"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26  // Bumped to 26 for better native support
        ndk {
            abiFilters += setOf("arm64-v8a")
        }
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        buildConfigField("String", "LITERT_LM_VERSION", "\"0.11.0\"")
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // LiteRT-LM runtime for bundled Gemma 4 E2B multimodal inference.
    // Pin 0.11.0 because this is the first release with Gemma 4 MTP support.
    implementation("com.google.ai.edge.litertlm:litertlm-android:0.11.0")
    
    // OkHttp for model downloading from HuggingFace
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    
    // Coroutines for async operations
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")

    // Core library desugaring for Flutter Local Notifications
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
