plugins {
    id("com.android.application")
    id("kotlin-android")

    id("dev.flutter.flutter-gradle-plugin")
}

import java . util . Properties
        import java . io . FileInputStream
        import java . io . File

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.cybrosys.mobo_sales"
    compileSdk = 36
    // NDK r28: the first release that defaults to 16 KB-aligned output. The
    // libraries Play flagged are prebuilt inside AARs, so this does not align
    // them — the dependency versions do — but it keeps anything compiled here
    // aligned.
    ndkVersion = "28.2.13676358"

    // buildToolsVersion was pinned to 34.0.0 while compileSdk moved to 36.
    // Unpinned, AGP picks the version that matches compileSdk.

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {

        applicationId = "com.cybrosys.mobo_sales"


        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = keystoreProperties["storeFile"]?.let { file(it as String) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

    buildTypes {
        release {

            signingConfig = signingConfigs.getByName("release")

            // R8 shrinks and obfuscates the code; resource shrinking drops
            // the drawables and layouts the shrunken code can no longer
            // reach. Both are what Play measures under "DEX optimization".
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}
