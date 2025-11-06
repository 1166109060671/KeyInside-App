plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.project_android"
    compileSdk = flutter.compileSdkVersion

    // ⛳️ เปลี่ยนจาก flutter.ndkVersion → เป็นเวอร์ชันที่ Firebase ต้องการ
    ndkVersion = "27.0.12077973"

    // ✅ ใช้ Java 17 (ไม่ใช่ Java 8 แล้ว)
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    // ✅ ตั้ง Kotlin ให้ใช้ JVM 17 เช่นกัน
    kotlinOptions {
        jvmTarget = "17"
    }

    // ✅ กำหนด Java toolchain ชัดเจน (บังคับใช้ JDK 17)
    java {
        toolchain {
            languageVersion.set(JavaLanguageVersion.of(17))
        }
    }

    defaultConfig {
        applicationId = "com.example.project_android"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

// ✅ เผื่อบาง task Kotlin ที่ยังใช้ jvmTarget เก่า
tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
    kotlinOptions.jvmTarget = "17"
}
