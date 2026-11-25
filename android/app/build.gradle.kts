import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Firebase: google-services.json is GENERATED in CI from the FIREBASE_* GitHub
// variables (tool/firebase_android_config.py) and git-ignored -- never
// committed. With it, the Google Services plugin creates the native default
// Firebase app (FCM delivery while ASKODOX is closed, phone sign-in, In-App
// Messaging). Without it (local builds, forks) the app builds without Firebase
// and says push is not configured; main release builds require it (CI).
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
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
        // Firebase Authentication (phone sign-in) needs Android 6.0+ (API 23).
        minSdk = maxOf(flutter.minSdkVersion, 23)
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

// Owner 2026-11-23 (Play Console: "this artifact significantly increases the size"): the live face check of attendance
// uses Google's face model that lives in Google Play services (~0.8 MB in the app) instead of the copy inside the app
// (~6.9 MB per phone, +14 MB in the bundle). Same classes, same answers; the plugin's bundled model is excluded here.
// The model comes down after install (manifest meta-data com.google.mlkit.vision.DEPENDENCIES = face).
// Guarded by backend/tests/test_android_app_size.py.
configurations.all {
    exclude(group = "com.google.mlkit", module = "face-detection")
}

dependencies {
    // Live face check (attendance): the Play services face model, see above.
    implementation("com.google.android.gms:play-services-mlkit-face-detection:17.1.0")
    // OTP autofill: SMS User Consent API (no READ_SMS permission).
    implementation("com.google.android.gms:play-services-auth-api-phone:18.1.0")
    // Payment alerts: AskodoxMessagingService overrides onMessageReceived(RemoteMessage) of the Flutter plugin's
    // FCM service; the plugin keeps firebase-messaging as `implementation`, so the class is declared here too
    // (Gradle resolves one version: the higher of this BoM and the plugin's).
    implementation(platform("com.google.firebase:firebase-bom:33.12.0"))
    implementation("com.google.firebase:firebase-messaging")
    // Shop link phase 2: which shop's link brought this install (Play Install Referrer; no permission, no person).
    implementation("com.android.installreferrer:installreferrer:2.2")
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
