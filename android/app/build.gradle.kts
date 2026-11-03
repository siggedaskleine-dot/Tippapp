import java.util.Base64

plugins {
    id("com.android.application")
    kotlin("android")
    id("org.jetbrains.kotlin.plugin.compose")
}

// Valfri egen signeringsnyckel från GitHub-hemligheter (TIPSAPP_KEYSTORE_B64 / TIPSAPP_KEYSTORE_PASSWORD).
val keystoreB64: String? = System.getenv("TIPSAPP_KEYSTORE_B64")
val keystoreFile = layout.buildDirectory.file("tipsapp.jks").get().asFile
if (!keystoreB64.isNullOrBlank()) {
    keystoreFile.parentFile.mkdirs()
    keystoreFile.writeBytes(Base64.getDecoder().decode(keystoreB64.trim()))
}

android {
    namespace = "tipsapp.android"
    compileSdk = 35

    defaultConfig {
        applicationId = "se.mattias.tipsapp"
        minSdk = 26
        targetSdk = 35
        versionCode = (System.getenv("GITHUB_RUN_NUMBER") ?: "1").toInt()
        versionName = "0.1.${System.getenv("GITHUB_RUN_NUMBER") ?: "0"}"
    }

    signingConfigs {
        // Fast debug-nyckel i repot gör att varje ny APK kan installeras ovanpå den förra.
        getByName("debug") {
            storeFile = file("debug.keystore")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
        create("release") {
            if (keystoreFile.exists()) {
                storeFile = keystoreFile
                storePassword = System.getenv("TIPSAPP_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("TIPSAPP_KEY_ALIAS") ?: "tipsapp"
                keyPassword = System.getenv("TIPSAPP_KEYSTORE_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            signingConfig = if (keystoreFile.exists()) signingConfigs.getByName("release") else signingConfigs.getByName("debug")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    buildFeatures { compose = true }
    packaging { resources { excludes += "/META-INF/{AL2.0,LGPL2.1}" } }
}

dependencies {
    implementation(project(":core"))
    implementation(platform("androidx.compose:compose-bom:2024.10.01"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-core")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.7")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.7")
    implementation("androidx.security:security-crypto:1.0.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
}
