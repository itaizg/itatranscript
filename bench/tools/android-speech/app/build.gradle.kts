plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "dev.itai.itabench"
    compileSdk = 36

    defaultConfig {
        applicationId = "dev.itai.itabench.androidspeech"
        // Streamed audio goes in through RecognizerIntent.EXTRA_AUDIO_SOURCE, which needs API 33.
        minSdk = 33
        targetSdk = 36
        versionCode = 1
        versionName = "0.1"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    testImplementation(kotlin("test"))
}
