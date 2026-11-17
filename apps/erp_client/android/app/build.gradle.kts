import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val uploadProperties = Properties()
val keyFile = rootProject.file("key.properties")
if (keyFile.isFile) {
    keyFile.inputStream().use(uploadProperties::load)
    require(listOf("storeFile", "keyAlias", "storePassword", "keyPassword").all {
        !uploadProperties.getProperty(it).isNullOrBlank()
    }) { "Fill in storeFile, keyAlias, storePassword and keyPassword in android/key.properties." }
}

android {
    namespace = "org.localerp.erp_client"
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
        applicationId = "org.localerp.erp_client"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Android 11 includes the OS fix for the StrandHogg task-hijacking variants.
        minSdk = 30
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keyFile.isFile) {
            create("upload") {
                storeFile = file(uploadProperties.getProperty("storeFile"))
                storePassword = uploadProperties.getProperty("storePassword")
                keyAlias = uploadProperties.getProperty("keyAlias")
                keyPassword = uploadProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("upload")
        }
    }
}

flutter {
    source = "../.."
}
