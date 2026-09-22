import java.io.File
import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keyProps = Properties()
val keyPropsFile = rootProject.file("key.properties")
if (keyPropsFile.exists()) {
    keyProps.load(FileInputStream(keyPropsFile))
}

val prodKeyFilePath: String? = System.getenv("ANDROID_KEYSTORE_PATH")
    ?: keyProps.getProperty("storeFile")
val prodKeyFile: File? = prodKeyFilePath?.let { path ->
    val f = file(path)
    if (f.exists()) f else rootProject.file(path)
}
val prodStorePassword: String? = System.getenv("ANDROID_KEYSTORE_PASSWORD")
    ?: keyProps.getProperty("storePassword")
val prodKeyAlias: String? = System.getenv("ANDROID_KEY_ALIAS")
    ?: keyProps.getProperty("keyAlias")
val prodKeyPassword: String? = System.getenv("ANDROID_KEY_PASSWORD")
    ?: keyProps.getProperty("keyPassword")

val hasProductionSigning = prodKeyFile != null && prodKeyFile.exists() &&
    !prodStorePassword.isNullOrBlank() &&
    !prodKeyAlias.isNullOrBlank() &&
    !prodKeyPassword.isNullOrBlank()

android {
    namespace = "com.labwizard.lab_wizard"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications uses java.time; desugaring keeps it
        // working on the oldest supported Android versions.
        isCoreLibraryDesugaringEnabled = true
    }

    signingConfigs {
        // Stable key for installable GitHub development builds. This key is
        // intentionally repository-visible and must not be used for Play Store
        // production signing. It lets phone-only testers install APK updates.
        create("githubRelease") {
            storeFile = file("lab-wizard-github.jks")
            storePassword = "labwizard-github"
            keyAlias = "labwizard"
            keyPassword = "labwizard-github"
        }

        if (hasProductionSigning) {
            create("production") {
                storeFile = prodKeyFile
                storePassword = prodStorePassword
                keyAlias = prodKeyAlias
                keyPassword = prodKeyPassword
            }
        }
    }

    defaultConfig {
        applicationId = "com.labwizard.lab_wizard"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = if (hasProductionSigning) {
                signingConfigs.getByName("production")
            } else {
                signingConfigs.getByName("githubRelease")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // Explicit so the Theme.AppCompat parents in res/values/styles.xml always
    // resolve (local_auth's biometric dialog needs them, SECURITY-01).
    implementation("androidx.appcompat:appcompat:1.7.1")
}

flutter {
    source = "../.."
}
