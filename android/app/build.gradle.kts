import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

// Firma de release. Las credenciales viven en android/key.properties, que esta
// en .gitignore y NUNCA se sube al repo. Si el archivo no existe (equipo de
// desarrollo recien clonado), el release cae a la firma debug para no romper
// el flujo local; ese APK no sirve para Play Console, pero compila igual.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
    // Existir no basta: un key.properties a medio llenar haria que el build
    // intentara firmar en release y fallara con un error incomprensible.
    listOf("keyAlias", "keyPassword", "storeFile", "storePassword").forEach { k ->
        require(!keystoreProperties.getProperty(k).isNullOrBlank()) {
            "android/key.properties: falta el valor de '$k'. Rellenalo antes de compilar release."
        }
    }
    val ksPath = keystoreProperties.getProperty("storeFile")
    require(file(ksPath).exists()) {
        "android/key.properties: storeFile apunta a '$ksPath', que no existe."
    }
}

android {
    namespace = "com.todogestion.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "28.2.13676358"

    // Java 17 + Desugaring (requerido por flutter_local_notifications)
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }
    defaultConfig {
        applicationId = "com.todogestion.app"
        minSdkVersion(24)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // multiDexEnabled = true // (solo si luego te da error de 64K metodos)
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = keystoreProperties.getProperty("storeFile")?.let { file(it) }
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // Flutter activa R8 en release por defecto. Sin declarar
            // proguardFiles, las reglas de proguard-rules.pro no se aplican y
            // R8 aborta por las clases de ML Kit que no se incluyen.
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
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
