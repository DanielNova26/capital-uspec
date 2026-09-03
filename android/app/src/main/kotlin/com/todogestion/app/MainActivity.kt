package com.todogestion.app

import android.os.Bundle
import androidx.activity.enableEdgeToEdge
// local_auth requiere FragmentActivity para mostrar el prompt biométrico.
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Android 15+ lo fuerza por targetSdk; esta llamada mantiene el mismo
        // comportamiento edge-to-edge en versiones anteriores del sistema.
        enableEdgeToEdge()
    }
}
