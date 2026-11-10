package com.todogestion.app

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

internal class VisitasGps(private val context: Context, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "com.todogestion.app/visitas_gps")
    private val locationManager = context.getSystemService(LocationManager::class.java)
    private val main = Handler(Looper.getMainLooper())
    private var cancelar: (() -> Unit)? = null

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "leer" -> leer(result)
                else -> result.notImplemented()
            }
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        cancelar?.invoke()
    }

    @SuppressLint("MissingPermission")
    private fun leer(result: MethodChannel.Result) {
        if (cancelar != null) {
            result.error("fallo", null, null)
            return
        }
        val provider = LocationManager.GPS_PROVIDER
        val manager = locationManager
        if (manager == null || provider !in manager.allProviders) {
            result.error("sin_receptor", null, null)
            return
        }
        if (!manager.isProviderEnabled(provider)) {
            result.error("desactivada", null, null)
            return
        }
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            val aproximada = ContextCompat.checkSelfPermission(
                context, Manifest.permission.ACCESS_COARSE_LOCATION
            ) == PackageManager.PERMISSION_GRANTED
            result.error(if (aproximada) "aproximada" else "permiso", null, null)
            return
        }

        val desde = SystemClock.elapsedRealtimeNanos()
        val listener = object : LocationListener {
            override fun onLocationChanged(location: Location) {
                // El sistema puede entregar primero una lectura anterior al intento.
                if (location.elapsedRealtimeNanos < desde || !location.hasAccuracy()) return
                terminar(posicion = location)
            }

            override fun onProviderDisabled(provider: String) {
                terminar(error = "desactivada")
            }

            override fun onProviderEnabled(provider: String) {}

            @Deprecated("Callback anterior a Android 10")
            override fun onStatusChanged(provider: String, status: Int, extras: Bundle?) {}

            private val plazo = Runnable { terminar(error = "sin_senal") }
            private val cancelarLectura: () -> Unit = { terminar(error = "fallo") }

            fun iniciar() {
                cancelar = cancelarLectura
                main.postDelayed(plazo, 60_000L)
                try {
                    manager.requestLocationUpdates(provider, 0L, 0f, this, Looper.getMainLooper())
                } catch (_: SecurityException) {
                    terminar(error = "permiso")
                } catch (_: IllegalArgumentException) {
                    terminar(error = "sin_receptor")
                }
            }

            private fun terminar(posicion: Location? = null, error: String = "fallo") {
                if (cancelar !== cancelarLectura) return
                cancelar = null
                main.removeCallbacks(plazo)
                manager.removeUpdates(this)
                if (posicion == null) {
                    result.error(error, null, null)
                } else {
                    result.success(mapOf(
                        "latitude" to posicion.latitude,
                        "longitude" to posicion.longitude,
                        "accuracy" to posicion.accuracy.toDouble(),
                        "timestamp" to posicion.time
                    ))
                }
            }
        }
        listener.iniciar()
    }
}
