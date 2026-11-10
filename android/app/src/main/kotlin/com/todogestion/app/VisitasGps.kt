package com.todogestion.app

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import androidx.core.content.ContextCompat
import androidx.core.location.LocationListenerCompat
import androidx.core.location.LocationManagerCompat
import androidx.core.location.LocationRequestCompat
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
                "leer" -> leer(call.argument<Int>("esperaMs") ?: 120_000, result)
                else -> result.notImplemented()
            }
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        cancelar?.invoke()
    }

    @SuppressLint("MissingPermission")
    private fun leer(esperaMs: Int, result: MethodChannel.Result) {
        if (cancelar != null) {
            result.error("fallo", null, null)
            return
        }
        val manager = locationManager
        if (manager == null) {
            result.error("sin_receptor", null, null)
            return
        }
        if (!LocationManagerCompat.isLocationEnabled(manager)) {
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

        val gps = LocationManager.GPS_PROVIDER
        val providers = manager.getProviders(true).filter {
            it == gps || it == LocationManager.FUSED_PROVIDER || it == LocationManager.NETWORK_PROVIDER
        }
        if (providers.isEmpty()) {
            val codigo = if (gps in manager.allProviders) "desactivada" else "sin_receptor"
            result.error(codigo, null, null)
            return
        }

        val desde = SystemClock.elapsedRealtimeNanos()
        val listener = object : LocationListenerCompat {
            override fun onLocationChanged(location: Location) {
                // El sistema puede entregar primero una lectura anterior al intento.
                if (location.elapsedRealtimeNanos < desde || !location.hasAccuracy()) return
                // Las fuentes asistidas pueden dar posiciones demasiado amplias para la visita.
                if (location.provider != gps && location.accuracy > 100f) return
                terminar(posicion = location)
            }

            override fun onProviderDisabled(provider: String) {
                if (!LocationManagerCompat.isLocationEnabled(manager)) {
                    terminar(error = "desactivada")
                }
            }

            private val plazo = Runnable { terminar(error = "sin_senal") }
            private val cancelarLectura: () -> Unit = { terminar(error = "fallo") }

            fun iniciar() {
                cancelar = cancelarLectura
                main.postDelayed(plazo, esperaMs.coerceIn(1_000, 120_000).toLong())
                val solicitud = LocationRequestCompat.Builder(0L)
                    .setQuality(LocationRequestCompat.QUALITY_HIGH_ACCURACY)
                    .build()
                var registrado = false
                try {
                    for (provider in providers) {
                        try {
                            LocationManagerCompat.requestLocationUpdates(
                                manager, provider, solicitud, this, Looper.getMainLooper()
                            )
                            registrado = true
                        } catch (_: IllegalArgumentException) {
                            // El proveedor pudo desaparecer mientras se iniciaba la lectura.
                        }
                    }
                    if (!registrado) terminar(error = "fallo")
                } catch (_: SecurityException) {
                    terminar(error = "permiso")
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
