// lib/services/app_update_service.dart
//
// Aviso de actualización al abrir la app.
//
// La versión disponible se lee de Firestore, no de las tiendas: consultar la
// App Store o Play desde el cliente es frágil (formatos que cambian, rate
// limits, y en el caso de una app no listada ni siquiera responde). Con un
// documento propio se controla desde la consola, sirve para las dos
// plataformas y permite corregir la URL de la tienda sin publicar una versión
// nueva, que es justo lo que no se puede hacer si va quemada en el código.
//
// La comparación es por NÚMERO DE BUILD, el `+N` de pubspec.yaml, no por el
// nombre de versión. El build es un entero que solo sube y es el mismo que
// gestionan Play y App Store; comparar "2.4.10" contra "2.4.9" como texto da
// resultados equivocados.
//
// Firestore: TBL_CONFIG/APP_VERSION
//
//   minBuildAndroid     int   por debajo de esto, la actualización es obligatoria
//   minBuildIos         int
//   latestBuildAndroid  int   por debajo de esto, se sugiere pero se puede posponer
//   latestBuildIos      int
//   urlAndroid          str   ficha de Play
//   urlIos              str   ficha de App Store
//   mensaje             str   opcional, reemplaza el texto por defecto
//
// Los umbrales van separados por plataforma a propósito: las dos tiendas
// aprueban en tiempos distintos y hay días en que Android va una versión por
// delante de iOS. Un solo número obligaría a los usuarios de la plataforma
// rezagada a actualizar a algo que todavía no existe para ellos.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

enum AppUpdateKind {
  /// La versión instalada está al día.
  ninguna,

  /// Hay una más nueva. Se puede posponer.
  sugerida,

  /// La instalada quedó por debajo del mínimo soportado. No se puede posponer.
  obligatoria,
}

class AppUpdateInfo {
  final AppUpdateKind kind;
  final String storeUrl;
  final String? mensaje;
  final int buildActual;
  final int buildDisponible;

  const AppUpdateInfo({
    required this.kind,
    required this.storeUrl,
    required this.buildActual,
    required this.buildDisponible,
    this.mensaje,
  });

  static const ninguna = AppUpdateInfo(
    kind: AppUpdateKind.ninguna,
    storeUrl: '',
    buildActual: 0,
    buildDisponible: 0,
  );
}

class AppUpdateService {
  AppUpdateService._();
  static final instance = AppUpdateService._();

  /// Se consulta una sola vez por sesión: el usuario ya vio el aviso, repetirlo
  /// cada vez que vuelve al Home sería hostigarlo.
  bool _yaConsultado = false;

  Future<AppUpdateInfo> consultar() async {
    // En web no hay tienda a la que mandar a nadie: el navegador siempre carga
    // la última versión desplegada.
    if (kIsWeb || _yaConsultado) return AppUpdateInfo.ninguna;
    _yaConsultado = true;

    try {
      final info = await PackageInfo.fromPlatform();
      final buildActual = int.tryParse(info.buildNumber) ?? 0;
      if (buildActual == 0) return AppUpdateInfo.ninguna;

      final snap = await FirebaseFirestore.instance
          .collection('TBL_CONFIG')
          .doc('APP_VERSION')
          .get();
      final data = snap.data();
      if (data == null) return AppUpdateInfo.ninguna;

      final esIos = defaultTargetPlatform == TargetPlatform.iOS;
      final minBuild = _entero(data[esIos ? 'minBuildIos' : 'minBuildAndroid']);
      final latestBuild = _entero(
        data[esIos ? 'latestBuildIos' : 'latestBuildAndroid'],
      );
      final url = (data[esIos ? 'urlIos' : 'urlAndroid'] ?? '')
          .toString()
          .trim();

      // Sin URL no hay a dónde mandar al usuario, así que no se avisa: un
      // diálogo obligatorio sin salida deja la app inutilizable.
      if (url.isEmpty) return AppUpdateInfo.ninguna;

      final mensaje = (data['mensaje'] ?? '').toString().trim();

      if (buildActual < minBuild) {
        return AppUpdateInfo(
          kind: AppUpdateKind.obligatoria,
          storeUrl: url,
          buildActual: buildActual,
          buildDisponible: minBuild,
          mensaje: mensaje.isEmpty ? null : mensaje,
        );
      }
      if (buildActual < latestBuild) {
        return AppUpdateInfo(
          kind: AppUpdateKind.sugerida,
          storeUrl: url,
          buildActual: buildActual,
          buildDisponible: latestBuild,
          mensaje: mensaje.isEmpty ? null : mensaje,
        );
      }
      return AppUpdateInfo.ninguna;
    } catch (e) {
      // Sin red, sin permisos de lectura o con el documento mal formado, el
      // aviso simplemente no aparece. Nunca puede impedir usar la app.
      debugPrint('[AppUpdate] no se pudo consultar: $e');
      return AppUpdateInfo.ninguna;
    }
  }

  static int _entero(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('${v ?? ''}') ?? 0;
  }

  Future<void> abrirTienda(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('[AppUpdate] no se pudo abrir la tienda: $e');
    }
  }
}

/// Muestra el aviso si corresponde. Se llama desde el Home, no desde el
/// arranque: bloquear `main()` con una consulta de red es lo que dejaba la app
/// en pantalla blanca cuando algo fallaba.
Future<void> mostrarAvisoActualizacion(BuildContext context) async {
  final info = await AppUpdateService.instance.consultar();
  if (info.kind == AppUpdateKind.ninguna) return;
  if (!context.mounted) return;

  final obligatoria = info.kind == AppUpdateKind.obligatoria;

  await showDialog<void>(
    context: context,
    barrierDismissible: !obligatoria,
    builder: (ctx) => PopScope(
      // En la obligatoria el botón atrás no cierra: la versión instalada ya no
      // es compatible con el backend y dejarla pasar produce errores peores y
      // más difíciles de explicar que este diálogo.
      canPop: !obligatoria,
      child: AlertDialog(
        icon: Icon(
          obligatoria ? Icons.system_update_alt_rounded : Icons.new_releases_outlined,
          color: Theme.of(ctx).colorScheme.primary,
          size: 40,
        ),
        title: Text(
          obligatoria ? 'Actualización necesaria' : 'Hay una versión nueva',
        ),
        content: Text(
          info.mensaje ??
              (obligatoria
                  ? 'Esta versión de la aplicación ya no es compatible. '
                        'Actualízala para seguir usándola.'
                  : 'Actualiza para tener las últimas mejoras y correcciones.'),
        ),
        actions: [
          if (!obligatoria)
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Ahora no'),
            ),
          FilledButton.icon(
            onPressed: () =>
                AppUpdateService.instance.abrirTienda(info.storeUrl),
            icon: const Icon(Icons.download_rounded),
            label: const Text('Actualizar'),
          ),
        ],
      ),
    ),
  );
}
