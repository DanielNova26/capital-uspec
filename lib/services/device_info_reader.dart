// Lee el equipo desde el que se entra a la app. Nunca falla: si no se puede
// leer, devuelve lo que se sepa por la plataforma.
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'device_descriptor.dart';
import 'device_hints_stub.dart'
    if (dart.library.js_interop) 'device_hints_web.dart';

/// Tablet: pantalla con el lado corto de 600 dp o más.
bool _pantallaDeTablet() {
  try {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return false;
    final view = views.first;
    final size = view.physicalSize / view.devicePixelRatio;
    return size.shortestSide >= 600;
  } catch (_) {
    return false;
  }
}

Future<DispositivoIngreso> leerDispositivo({DeviceInfoPlugin? plugin}) async {
  final info = plugin ?? DeviceInfoPlugin();
  try {
    if (kIsWeb) {
      final web = await info.webBrowserInfo;
      final pistas = await pistasDelNavegador();
      return dispositivoDesdeUserAgent(
        web.userAgent ?? '',
        modeloPista: pistas.modelo,
        versionPista: pistas.version,
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        final a = await info.androidInfo;
        return dispositivoAndroid(
          fabricante: a.manufacturer,
          modelo: a.model,
          version: a.version.release,
          tablet: _pantallaDeTablet(),
        );
      case TargetPlatform.iOS:
        final i = await info.iosInfo;
        return dispositivoIos(
          modelo: i.modelName.isNotEmpty ? i.modelName : i.model,
          version: i.systemVersion,
        );
      case TargetPlatform.macOS:
        final m = await info.macOsInfo;
        return dispositivoEscritorio('macOS', modelo: m.modelName);
      case TargetPlatform.windows:
        return dispositivoEscritorio('Windows');
      case TargetPlatform.linux:
        return dispositivoEscritorio('Linux');
      case TargetPlatform.fuchsia:
        return const DispositivoIngreso.desconocido();
    }
  } catch (_) {
    return _porPlataforma();
  }
}

DispositivoIngreso _porPlataforma() {
  if (kIsWeb) {
    return const DispositivoIngreso(
      tipo: TipoDispositivo.desconocido,
      navegador: 'Navegador',
    );
  }
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => dispositivoAndroid(
      fabricante: '',
      modelo: '',
      version: '',
      tablet: _pantallaDeTablet(),
    ),
    TargetPlatform.iOS => dispositivoIos(modelo: '', version: ''),
    TargetPlatform.windows => dispositivoEscritorio('Windows'),
    TargetPlatform.macOS => dispositivoEscritorio('macOS'),
    TargetPlatform.linux => dispositivoEscritorio('Linux'),
    TargetPlatform.fuchsia => const DispositivoIngreso.desconocido(),
  };
}
