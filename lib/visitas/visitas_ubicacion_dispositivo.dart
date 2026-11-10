import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

enum ErrorUbicacionVisita implements Exception {
  desactivada,
  permiso,
  aproximada,
  sinReceptor,
  sinSenal,
  fallo;

  String get mensaje => switch (this) {
    desactivada =>
      'Activa la ubicación en los ajustes del dispositivo. Vuelve a la app '
          'e inténtalo de nuevo.',
    permiso =>
      kIsWeb
          ? 'Permite que este sitio use tu ubicación en los ajustes del navegador.'
          : 'En los ajustes de la app, permite la ubicación mientras la usas.'
                '${_android ? ' Si Family Link administra el permiso, debe concederlo el supervisor.' : ''}',
    aproximada =>
      'La app tiene permiso de ubicación aproximada. Activa Ubicación precisa '
          'en los permisos de la app.',
    sinReceptor =>
      'Android no encuentra una fuente de ubicación disponible. Para iniciar '
          'sin conexión, usa un equipo con GPS y prepara allí la visita.',
    sinSenal =>
      'No se obtuvo una posición a tiempo. Si estás en el establecimiento, '
          'acércate a una zona con vista al cielo y vuelve a intentar.',
    fallo => 'El dispositivo no pudo leer la ubicación. Vuelve a intentar.',
  };

  bool get permiteAbrirAjustes =>
      !kIsWeb &&
      (_android || defaultTargetPlatform == TargetPlatform.iOS) &&
      (this == desactivada || this == permiso || this == aproximada);

  Future<bool> abrirAjustes() => this == desactivada
      ? Geolocator.openLocationSettings()
      : Geolocator.openAppSettings();
}

bool get _android => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

const _gpsAndroid = MethodChannel('com.todogestion.app/visitas_gps');

Duration get esperaUbicacionDescargada =>
    Duration(seconds: _android ? 120 : 60);

/// En Android se consultan en paralelo el GPS y las fuentes disponibles.
/// Las demás conservan el servicio de ubicación de su plataforma.
Future<Position> leerPosicionVisita({bool descargada = false}) async {
  final satelital = descargada && _android;
  try {
    if (!satelital && !await Geolocator.isLocationServiceEnabled()) {
      throw ErrorUbicacionVisita.desactivada;
    }
    var permiso = await Geolocator.checkPermission();
    if (permiso == LocationPermission.denied) {
      permiso = await Geolocator.requestPermission();
    }
    if (permiso == LocationPermission.denied ||
        permiso == LocationPermission.deniedForever) {
      throw ErrorUbicacionVisita.permiso;
    }
    if (satelital) {
      final posicion = await _gpsAndroid.invokeMapMethod<String, Object>(
        'leer',
        {'esperaMs': esperaUbicacionDescargada.inMilliseconds},
      );
      if (posicion == null) throw ErrorUbicacionVisita.fallo;
      return Position.fromMap(posicion);
    }
    if (descargada &&
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.iOS &&
        await Geolocator.getLocationAccuracy() ==
            LocationAccuracyStatus.reduced) {
      throw ErrorUbicacionVisita.aproximada;
    }
    return await Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: descargada
            ? esperaUbicacionDescargada
            : const Duration(seconds: 15),
      ),
    );
  } on ErrorUbicacionVisita {
    rethrow;
  } on LocationServiceDisabledException {
    throw ErrorUbicacionVisita.desactivada;
  } on PermissionDeniedException {
    throw ErrorUbicacionVisita.permiso;
  } on TimeoutException {
    throw ErrorUbicacionVisita.sinSenal;
  } on PlatformException catch (e) {
    throw switch (e.code) {
      'desactivada' => ErrorUbicacionVisita.desactivada,
      'permiso' => ErrorUbicacionVisita.permiso,
      'aproximada' => ErrorUbicacionVisita.aproximada,
      'sin_receptor' => ErrorUbicacionVisita.sinReceptor,
      'sin_senal' => ErrorUbicacionVisita.sinSenal,
      _ => ErrorUbicacionVisita.fallo,
    };
  } catch (_) {
    throw ErrorUbicacionVisita.fallo;
  }
}
