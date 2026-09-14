import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum StartupPermissionKind {
  notifications,
  camera,
  microphone,
  speech,
  photos,
  locationWhenInUse,
}

/// Permisos que esta versión usa realmente en cada plataforma.
///
/// Android usa los selectores del sistema para fotos y archivos, por lo que no
/// necesita acceso general a la galería. iOS sí expone permisos separados para
/// galería y reconocimiento de voz.
List<StartupPermissionKind> startupPermissionPlan(TargetPlatform platform) {
  switch (platform) {
    case TargetPlatform.android:
      return const [
        StartupPermissionKind.notifications,
        StartupPermissionKind.camera,
        StartupPermissionKind.microphone,
        StartupPermissionKind.locationWhenInUse,
      ];
    case TargetPlatform.iOS:
      return const [
        StartupPermissionKind.notifications,
        StartupPermissionKind.camera,
        StartupPermissionKind.microphone,
        StartupPermissionKind.speech,
        StartupPermissionKind.photos,
        StartupPermissionKind.locationWhenInUse,
      ];
    case TargetPlatform.fuchsia:
    case TargetPlatform.linux:
    case TargetPlatform.macOS:
    case TargetPlatform.windows:
      return const [];
  }
}

Permission _permissionFor(StartupPermissionKind kind) {
  switch (kind) {
    case StartupPermissionKind.notifications:
      return Permission.notification;
    case StartupPermissionKind.camera:
      return Permission.camera;
    case StartupPermissionKind.microphone:
      return Permission.microphone;
    case StartupPermissionKind.speech:
      return Permission.speech;
    case StartupPermissionKind.photos:
      return Permission.photos;
    case StartupPermissionKind.locationWhenInUse:
      return Permission.locationWhenInUse;
  }
}

class StartupPermissionsService {
  StartupPermissionsService._();

  // Cambiar la versión de esta clave permite volver a presentar la secuencia
  // en una futura entrega si la app incorpora un permiso nuevo.
  static const _requestedKey = 'startup_permissions_requested_v1';

  /// Presenta, uno tras otro, los diálogos nativos de los permisos pendientes.
  ///
  /// Se ejecuta después del primer frame y solo una vez. Los módulos conservan
  /// sus solicitudes en contexto como respaldo cuando alguien niega un permiso
  /// inicialmente o lo desactiva más tarde desde Ajustes.
  static Future<void> requestInitialPermissions() async {
    if (kIsWeb) return;

    final plan = startupPermissionPlan(defaultTargetPlatform);
    if (plan.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_requestedKey) == true) return;

    // Deja que la primera pantalla termine de aparecer antes de abrir diálogos
    // del sistema. Los permisos nunca deben bloquear el arranque de la app.
    await Future<void>.delayed(const Duration(milliseconds: 700));

    for (final kind in plan) {
      try {
        final permission = _permissionFor(kind);
        final status = await permission.status;
        if (status.isDenied) {
          await permission.request();
        }
      } catch (e) {
        debugPrint('[permissions] no se pudo solicitar $kind: $e');
      }
    }

    await prefs.setBool(_requestedKey, true);
  }
}
