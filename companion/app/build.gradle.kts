plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.serialization")
    id("org.jetbrains.kotlin.plugin.compose")
}

// Signing material belongs to the release machine, never Gradle arguments or source.
val releaseSigningNames = listOf("UAI_ANDROID_KEYSTORE", "UAI_ANDROID_STORE_PASSWORD", "UAI_ANDROID_KEY_ALIAS", "UAI_ANDROID_KEY_PASSWORD")
val releaseSigningValues = releaseSigningNames.associateWith { System.getenv(it).orEmpty() }
val hasReleaseSigning = releaseSigningValues.values.any { it.isNotEmpty() }
if (hasReleaseSigning && releaseSigningValues.values.any { it.isEmpty() }) {
    error("Provide all four UAI_ANDROID signing environment variables, or none for an unsigned local build")
}

android {
    namespace = "dev.projectuai.relay"
    // Tor Android's current AAR requires the Android 37.1 compile API.
    compileSdk { version = release(37) { minorApiLevel = 1 } }

    defaultConfig {
        applicationId = "dev.projectuai.relay"
        minSdk = 26
        targetSdk = 36
        versionCode = 9
        versionName = "3.7.2"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(releaseSigningValues.getValue("UAI_ANDROID_KEYSTORE"))
                storePassword = releaseSigningValues.getValue("UAI_ANDROID_STORE_PASSWORD")
                keyAlias = releaseSigningValues.getValue("UAI_ANDROID_KEY_ALIAS")
                keyPassword = releaseSigningValues.getValue("UAI_ANDROID_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            if (hasReleaseSigning) signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures { compose = true }
    sourceSets.getByName("main").assets.srcDir("../../licenses")

    packaging {
        resources { excludes += "/META-INF/{AL2.0,LGPL2.1}" }
    }

    testOptions {
        unitTests.isReturnDefaultValues = true
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2024.12.01")
    implementation(composeBom)
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.7")
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.security:security-crypto:1.1.0-alpha06")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")
    implementation("io.ktor:ktor-server-core:3.0.3")
    implementation("io.ktor:ktor-server-cio:3.0.3")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("info.guardianproject:tor-android:0.4.9.14") {
        // TorService is Java; use the application's aligned Kotlin runtime.
        exclude(group = "org.jetbrains.kotlin", module = "kotlin-stdlib")
    }

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.9.0")
    testImplementation("com.squareup.okhttp3:mockwebserver:4.12.0")
    testImplementation("io.ktor:ktor-client-core:3.0.3")
    testImplementation("io.ktor:ktor-client-cio:3.0.3")

    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    androidTestImplementation("androidx.test:runner:1.6.2")
}

tasks.withType<Test>().configureEach {
    testLogging { events("passed", "failed", "skipped") }
}
