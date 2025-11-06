// ===== add these imports at the very top =====
import java.util.Properties
import java.io.FileInputStream
// ============================================

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

// ===== Load keystore from key.properties (safe) =====
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        FileInputStream(keystorePropertiesFile).use { fis ->
            this.load(fis)
        }
    }
}

android {
    namespace = "th.ac.rmuttt.ct.keyinside"           // <- ปรับตามของคุณ
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    java { toolchain { languageVersion.set(JavaLanguageVersion.of(17)) } }

    defaultConfig {
        applicationId = "th.ac.rmuttt.ct.keyinside"   // <- ต้องตรงกับ google-services.json
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    signingConfigs {
        // release signing config สร้างได้ (ยังไม่ซ้ำ)
        create("release") {
            if (keystorePropertiesFile.exists()) {
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }
    buildTypes {
        // ⚠️ อย่าใช้ create("debug") / create("release") เพราะมีอยู่แล้ว
        getByName("debug") {
            signingConfig = signingConfigs.getByName("debug")
        }
        getByName("release") {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            // ถ้าจำเป็นค่อยเปิด rules:
            // proguardFiles(
            //     getDefaultProguardFile("proguard-android-optimize.txt"),
            //     "proguard-rules.pro"
            // )
        }
    }

    packaging {
        resources { excludes += "META-INF/*" }
    }
}

flutter { source = "../.." }

// กัน task Kotlin เก่าบางตัว
tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
    kotlinOptions.jvmTarget = "17"
}
