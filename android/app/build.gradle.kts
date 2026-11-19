import java.util.Properties
import java.io.File

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// The isolated harness is opt-in, debug-only and cannot run the production main.
val sessionCheck = providers.gradleProperty("sessionCheck").isPresent
val requestedTarget = providers.gradleProperty("target").orNull?.let {
    (if (File(it).isAbsolute) File(it) else rootProject.file("../$it")).canonicalFile
}
val usesSessionCheckTarget =
    requestedTarget == rootProject.file("../integration_test/android_session_main.dart").canonicalFile
require(sessionCheck || !usesSessionCheckTarget) {
    "The Android test entrypoint requires the isolated sessionCheck applicationId"
}
if (sessionCheck) {
    require(usesSessionCheckTarget) {
        "sessionCheck requires the isolated Android test entrypoint"
    }
    val allowedTasks = setOf("assembleDebug", "lintDebug", "testDebugUnitTest")
    require(gradle.startParameter.taskNames.isNotEmpty() &&
        gradle.startParameter.taskNames.all { it.substringAfterLast(':') in allowedTasks }) {
        "sessionCheck only permits explicit debug assembly, lint and unit-test tasks"
    }
    val jni = file(providers.gradleProperty("sessionCheckJni").get())
    require(jni.resolve("x86_64/libesurfing.so").isFile) {
        "sessionCheck requires a separately built x86_64 backend"
    }
}

// release 签名：固定密钥库，本地与 CI 共用同一份签名（换签名后旧包无法覆盖安装）。
// 配置在 android/key.properties（不入库），CI 由 workflow 从 Secrets 还原。
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        keystorePropertiesFile.inputStream().use { load(it) }
    }
}

android {
    namespace = "com.esurfing.esurfing_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    testOptions {
        unitTests.isIncludeAndroidResources = true
    }

    defaultConfig {
        applicationId = "com.esurfing.esurfing_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // esurfing_c 使用 getifaddrs/freeifaddrs，需要 API 24。
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        ndk {
            abiFilters += listOf("arm64-v8a", "armeabi-v7a", "x86_64")
        }
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        debug {
            if (sessionCheck) applicationIdSuffix = ".sessioncheck"
        }
        release {
            // 有 key.properties 就用固定的 release 密钥；没有（比如别人 clone 下来
            // 只想跑 flutter run --release）才退回 debug 签名。
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                logger.warn("android/key.properties 不存在，release 包将使用 debug 签名")
                signingConfigs.getByName("debug")
            }
            if (sessionCheck) {
                sourceSets.getByName("debug") {
                    java.srcDir("src/sessionCheck/kotlin")
                    manifest.srcFile("src/sessionCheck/AndroidManifest.xml")
                }
                sourceSets.getByName("main").jniLibs.setSrcDirs(
                    listOf(providers.gradleProperty("sessionCheckJni").get())
                )
            }
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

dependencies {
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.robolectric:robolectric:4.17")
}

// Flutter wires APK assets but not AGP's resource-enabled local test packages.
tasks.matching {
    it.name.startsWith("package") && it.name.endsWith("UnitTestForUnitTest")
}.configureEach {
    val variant = name.removePrefix("package").removeSuffix("UnitTestForUnitTest")
    dependsOn("copyFlutterAssets$variant")
}
