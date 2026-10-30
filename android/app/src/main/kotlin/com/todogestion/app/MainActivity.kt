package com.todogestion.app

import android.os.Bundle
import androidx.activity.enableEdgeToEdge
// local_auth requiere FragmentActivity para mostrar el prompt biométrico.
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val storage = VisitasSecureStorage(applicationContext)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "com.todogestion.app/visitas_secure").setMethodCallHandler { call, result ->
            try {
                val key = call.argument<String>("key")
                require(key in setOf("ready", "visitas_offline_aes_v1", "visitas_offline_access_v1"))
                when (call.method) {
                    "read" -> result.success(storage.read(key!!))
                    "write" -> {
                        storage.write(key!!, requireNotNull(call.argument<String>("value")))
                        result.success(null)
                    }
                    "delete" -> { storage.delete(key!!); result.success(null) }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("visitas_secure_unavailable",
                    "No se pudo abrir el almacenamiento seguro de visitas. Reinicia la app e inténtalo de nuevo. Conserva los datos del equipo.", null)
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Android 15+ lo fuerza por targetSdk; esta llamada mantiene el mismo
        // comportamiento edge-to-edge en versiones anteriores del sistema.
        enableEdgeToEdge()
    }
}
