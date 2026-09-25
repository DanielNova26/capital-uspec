// lib/services/local_notification_service.dart
// Notificaciones locales compartidas (FCM + Firestore) con sonido.

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Canal de los avisos informativos a quien aprueba (25 sep 2026): llegan a
/// la bandeja sin sonido ni vibración. Lo que pide actuar (aprobar) sigue en
/// `tasks_high`, con sonido. El backend elige el canal
/// (`functions/src/notification_sound_policy.ts`).
const AndroidNotificationChannel kCanalSilencioso = AndroidNotificationChannel(
  'tasks_silent',
  'Avisos informativos',
  description: 'Seguimiento de tareas sin sonido (no requieren acción).',
  importance: Importance.low,
  playSound: false,
  enableVibration: false,
);

/// ¿La notificación viene marcada como silenciosa?
bool notificacionSilenciosa(Object? valor) {
  if (valor == true) return true;
  final t = (valor ?? '').toString().trim().toLowerCase();
  return t == '1' || t == 'true';
}

class LocalNotificationService {
  LocalNotificationService._();
  static final instance = LocalNotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const macos = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const init = InitializationSettings(
      android: android,
      iOS: ios,
      macOS: macos,
    );
    await _plugin.initialize(
      init,
      onDidReceiveNotificationResponse: (resp) {
        // Manejo de payload (taskId / deepLink) en el caller.
      },
    );

    const channel = AndroidNotificationChannel(
      'tasks_high',
      'Tareas',
      description: 'Notificaciones de tareas',
      importance: Importance.max,
      playSound: true,
    );

    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.createNotificationChannel(channel);
    await androidPlugin?.createNotificationChannel(kCanalSilencioso);

    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
  }

  Future<void> show({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'tasks_high',
        'Tareas',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
      ),
      iOS: DarwinNotificationDetails(presentSound: true),
      macOS: DarwinNotificationDetails(presentSound: true),
    );
    await _plugin.show(id, title, body, details, payload: payload);
  }
}
