plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

import java.util.Properties
import java.io.FileInputStream

// Credentials live outside the repository (android/key.properties, gitignored)
// so the keystore password is never committed.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        load(FileInputStream(keystorePropertiesFile))
    }
}

android {
    namespace = "app.wattxchange.wattx_wallet"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "app.wattxchange.wattx_wallet"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    packaging {

        jniLibs {

            // The daemon is an executable, not a library. Android extracts

            // and chmod +x's files under lib/ only with legacy packaging;

            // in the modern layout they are mapped from the APK and never

            // land on disk as something that can be exec'd.

            useLegacyPackaging = true

        }

    }


    signingConfigs {


        create("release") {


            if (keystorePropertiesFile.exists()) {


                storeFile = file(keystoreProperties["storeFile"] as String)


                storePassword = keystoreProperties["storePassword"] as String


                keyAlias = keystoreProperties["keyAlias"] as String


                keyPassword = keystoreProperties["keyPassword"] as String


                // v3 is what allows this key to be rotated later; without it


                // the first key shipped is the app's identity forever.


                enableV2Signing = true


                enableV3Signing = true


            }


        }


    }



    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Sign with the release key when key.properties is present, and
            // fall back to debug otherwise so a plain checkout still builds.
            //
            // This matters more than it looks: the signing key IS the app's
            // identity to Android. A debug-signed release means every user is
            // pinned to a throwaway key that cannot be rotated, and moving them
            // to a properly signed build later would require an uninstall --
            // which takes the wallet's seed with it.
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
