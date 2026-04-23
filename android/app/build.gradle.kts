import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.todo"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "28.2.13676358"

    // Java 17 + Desugaring (requerido por flutter_local_notifications)
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }
    defaultConfig {
        applicationId = "com.example.todo"
        minSdkVersion(24)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // multiDexEnabled = true // (solo si luego te da error de 64K métodos)
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            // isMinifyEnabled = true
            // isShrinkResources = true
            // proguardFiles(
            //     getDefaultProguardFile("proguard-android-optimize.txt"),
            //     "proguard-rules.pro"
            // )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

dependencies {
    // Firebase BoM
    implementation(platform("com.google.firebase:firebase-bom:33.14.0"))
    implementation("com.google.firebase:firebase-analytics")

    // Desugaring (CLAVE)
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")

    // implementation("androidx.multidex:multidex:2.0.1") // solo si activas multidex arriba
}

flutter {
    source = "../.."
}
