import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ASKODOX release signing: ONLY the persistent ASKODOX release key (CI writes
// android/key.properties + android/app/askodox-release.jks from the
// ANDROID_KEYSTORE_* GitHub secrets; neither file is ever committed). Every
// installed ASKODOX build is signed with it, so an APK signed with anything
// else -- e.g. a runner's throwaway debug key -- cannot update the app
// ("App not installed"). Without the key a release build fails instead of
// silently falling back to the debug key.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

android {
    namespace = "com.askodox.askodox"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.askodox.askodox"
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

    signingConfigs {
        if (hasReleaseKeystore) {
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
            signingConfig = if (hasReleaseKeystore) signingConfigs.getByName("release") else null
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

// Fail closed: a release APK/bundle without the ASKODOX release key is never built.
gradle.taskGraph.whenReady {
    val releasePackaging = allTasks.any { task ->
        task.project == project && task.name.endsWith("Release") &&
            (task.name.startsWith("assemble") || task.name.startsWith("package") || task.name.startsWith("bundle"))
    }
    if (releasePackaging && !hasReleaseKeystore) {
        throw GradleException(
            "ASKODOX release signing is not configured (android/key.properties missing). " +
                "Release builds must use the persistent ASKODOX release key, never the debug key."
        )
    }
}
