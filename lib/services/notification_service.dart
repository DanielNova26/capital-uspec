// lib/services/notifications_service.dart
//
// Servicio de notificaciones para:
// 1) Registrar y refrescar el token FCM por cédula (vía callable registerDeviceToken)
// 2) Manejar permisos y handlers de Firebase Messaging
// 3) Mostrar notificaciones locales en foreground con sonido (canal tasks_high)
// 4) Ofrecer un stream de la bandeja in-app (si usas doc por cédula con array 'notifications')
//
// Requisitos en pubspec.yaml (según tu versión):
//   firebase_messaging: ^15.2.7
//   flutter_local_notifications: ^17.2.4
//   cloud_functions: ^5.1.3
//   firebase_core, cloud_firestore, firebase_auth (ya los tienes)
//
// AndroidManifest.xml: ya declaraste POST_NOTIFICATIONS y el default channel id 'tasks_high'

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../compras/compras_dashboard_screen.dart';
import '../nutricion/nutricion_dashboard_screen.dart';
import '../home/notifications_screen.dart';
import '../home/assigned_tasks_screen.dart';
import '../home/created_tasks_screen.dart';
import '../home/task_history_screen.dart';
import '../core/task_route_guard.dart';

typedef CedulaProvider = FutureOr<String?> Function();

/// Handler de mensajes en background.
/// IMPORTANTE: No intentes mostrar notificación local aquí.
/// En background, FCM con payload 'notification' ya muestra sistema.
/// Solo dejamos el init para asegurar el isolate.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
    if (kDebugMode) {
      print('[BG] FCM received: ${message.messageId}');
    }
    // No mostrar locales aquí; FCM ya levanta push del sistema en background.
  } catch (_) {}
}

class NotificationsService {
  NotificationsService._();

  static final FlutterLocalNotificationsPlugin _fln =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;
  static CedulaProvider? _cedulaProvider;
  static GlobalKey<NavigatorState>? _navigatorKey;
  static String? _activeCedula;
  static const String _kActiveCedulaPrefKey = 'active_notification_cedula';

  static Future<void> setActiveCedula(String? cedula) async {
    final normalized = cedula?.trim();
    _activeCedula = (normalized == null || normalized.isEmpty)
        ? null
        : normalized;
    final prefs = await SharedPreferences.getInstance();
    if (_activeCedula == null) {
      await prefs.remove(_kActiveCedulaPrefKey);
    } else {
      await prefs.setString(_kActiveCedulaPrefKey, _activeCedula!);
    }
  }

  /// Inicializa todo: canales, permisos, handlers y registro de token.
  ///
  /// [cedulaProvider]: función que devuelva la cédula del usuario actual.
  /// Si no la proporcionas, intentará buscarla en TBL_USUARIOS por `uid` del auth.
  ///
  /// [useCustomSound]: si deseas usar un sonido raw llamado 'task_ping'
  /// ubicado en android/app/src/main/res/raw/task_ping.(mp3|wav).
  static Future<void> init({
    CedulaProvider? cedulaProvider,
    GlobalKey<NavigatorState>? navigatorKey,
    bool useCustomSound = false,
  }) async {
    if (_initialized) return;
    _initialized = true;

    _cedulaProvider = cedulaProvider;
    _navigatorKey = navigatorKey;

    // 0) Background handler
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // 1) Init de notificaciones locales
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    await _fln.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (resp) async {
        final payload = resp.payload;
        if (kDebugMode) print('[LOCAL TAP] payload=$payload');
        await _handleNotificationTapPayload(payload);
      },
    );

    // 2) Crear canal Android con máxima importancia (coincide con AndroidManifest)
    final android = _fln
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null && !kIsWeb && Platform.isAndroid) {
      // ✅ Solicitar permiso explícito para Android 13+
      await android.requestNotificationsPermission();

      final channel = AndroidNotificationChannel(
        'tasks_high',
        'Tareas y Novedades',
        description: 'Notificaciones críticas de tareas y avances.',
        importance: Importance.max,
        playSound: true,
        sound: useCustomSound
            ? const RawResourceAndroidNotificationSound('task_ping')
            : null, // default
      );
      await android.createNotificationChannel(channel);
    }

    // 3) Pedir permisos FCM + mostrar notificaciones en foreground (iOS)
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );
    if (kDebugMode) print('[FCM] Permission: ${settings.authorizationStatus}');

    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );

    // 4) Handlers de mensajes (foreground + tap desde terminated/background)
    FirebaseMessaging.onMessage.listen(_onMessageForeground);
    FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpenedApp);

    // App arrancada desde estado terminated al tocar una notificación.
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      await _onMessageOpenedApp(initialMessage);
    }

    // 5) Obtener y registrar token actual
    final token = await FirebaseMessaging.instance.getToken();
    if (kDebugMode) print('[FCM] Token: $token');
    if (token != null) {
      await _registerTokenWithCedula(token);
    }

    // 6) Suscribirse a refresh de token
    FirebaseMessaging.instance.onTokenRefresh.listen((t) async {
      if (kDebugMode) print('[FCM] Token refresh: $t');
      await _registerTokenWithCedula(t);
    });
  }

  /// Muestra notificación local cuando el app está en foreground.
  /// El payload incluye "type::rawId" para preservar el tipo en el tap.
  static Future<void> _onMessageForeground(RemoteMessage m) async {
    final n = m.notification;
    final data = m.data;

    final title = n?.title ?? data['title'] ?? 'Nueva tarea';
    final body = n?.body ?? data['body'] ?? 'Tienes una notificación';
    final rawPayload = (data['deepLink'] ?? data['taskId'])?.toString();
    final type = (data['type'] ?? '').toString().trim();
    final empresaId = (data['empresaId'] ?? '').toString().trim();
    final combinedPayload = jsonEncode({
      'type': type,
      'payload': rawPayload ?? '',
      'empresaId': empresaId,
    });

    await _fln.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'tasks_high',
          'Tareas',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
        ),
        iOS: const DarwinNotificationDetails(presentSound: true),
      ),
      payload: combinedPayload,
    );
  }

  static Future<void> _onMessageOpenedApp(RemoteMessage m) async {
    final data = m.data;
    if (kDebugMode) print('[FCM TAP] data=$data');
    final rawPayload =
        data['deepLink']?.toString() ?? data['taskId']?.toString();
    final type = (data['type'] ?? '').toString().trim();
    final empresaId = (data['empresaId'] ?? '').toString().trim();
    final combinedPayload = type.isNotEmpty
        ? '$type::${rawPayload ?? ''}'
        : rawPayload;
    await _handleNotificationTapPayload(combinedPayload, empresaId: empresaId);
  }

  static Future<void> _handleNotificationTapPayload(
    String? payload, {
    String? empresaId,
  }) async {
    // Parse "type::rawId" format; type may be empty for legacy payloads.
    String notifType = '';
    String? rawPayload = payload;
    String? notifEmpresaId = empresaId?.trim();
    if (payload != null && payload.trim().startsWith('{')) {
      try {
        final parsed = jsonDecode(payload);
        if (parsed is Map<String, dynamic>) {
          notifType = (parsed['type'] ?? '').toString().trim();
          rawPayload = (parsed['payload'] ?? '').toString();
          final parsedEmpresa = (parsed['empresaId'] ?? '').toString().trim();
          if (parsedEmpresa.isNotEmpty) notifEmpresaId = parsedEmpresa;
        }
      } catch (_) {}
    } else if (payload != null && payload.contains('::')) {
      final idx = payload.indexOf('::');
      notifType = payload.substring(0, idx).trim();
      rawPayload = payload.substring(idx + 2);
    }
    final taskId = _extractTaskId(rawPayload);

    final navigator = _navigatorKey?.currentState;
    if (navigator == null || _navigatorKey?.currentContext == null) {
      if (kDebugMode) {
        print('[FCM TAP] navigatorKey no configurado; payload=$payload');
      }
      return;
    }

    final cedula = await _resolveCedula();
    if (cedula == null || cedula.trim().isEmpty) {
      if (kDebugMode) {
        print('[FCM TAP] no se pudo resolver cédula para taskId=$taskId');
      }
      return;
    }

    final context = _navigatorKey?.currentContext;
    if (context == null) return;

    if (taskId == null) {
      navigator.push(
        MaterialPageRoute(
          builder: (_) => NotificationsScreen(
            userId: cedula,
            empresaId: (notifEmpresaId ?? '').isEmpty ? null : notifEmpresaId,
          ),
        ),
      );
      return;
    }

    // Tipos de Nutrición: navegan a NutricionDashboardScreen.
    if (notifType == 'cita_nutricion_agendada' ||
        notifType == 'cita_nutricion_recordatorio') {
      await abrirNutricionDesdeCita(context, userId: cedula, citaId: taskId);
      return;
    }

    // Tipos especiales de Compras: navegan al proveedor o ficha técnica.
    if ((notifType == 'doc_rechazado' || notifType == 'correccion_requerida') &&
        taskId.startsWith('proveedor:')) {
      final proveedorId = taskId.replaceFirst('proveedor:', '').trim();
      if (proveedorId.isNotEmpty) {
        await abrirDetalleProveedor(
          context,
          userId: cedula,
          proveedorId: proveedorId,
        );
      }
      return;
    }
    if (notifType == 'ficha_rechazada' && taskId.startsWith('ficha:')) {
      final fichaId = taskId.replaceFirst('ficha:', '').trim();
      if (fichaId.isNotEmpty) {
        await abrirDetalleFichaRechazada(
          context,
          userId: cedula,
          fichaId: fichaId,
        );
      }
      return;
    }
    if (notifType == 'recepcion_doc_rechazado' &&
        taskId.startsWith('recepcion:')) {
      await abrirDetalleRecepcionCompras(
        context,
        userId: cedula,
        recepcionId: taskId,
      );
      return;
    }

    final routeDecision = await TaskRouteGuard().resolveNotificationRoute(
      context,
      userIdentity: cedula,
      taskId: taskId,
      type: notifType,
    );
    if (!routeDecision.allowed) {
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            routeDecision.message ??
                'No se pudo abrir el destino de la notificación.',
          ),
        ),
      );
      return;
    }

    if (routeDecision.target == TaskRouteTarget.taskHistory) {
      navigator.push(
        MaterialPageRoute(
          builder: (_) => TaskHistoryScreen(
            currentUserId: cedula,
            initialTabIndex: routeDecision.initialTabIndex,
            highlightTaskId: taskId,
          ),
        ),
      );
      return;
    }

    if (routeDecision.target == TaskRouteTarget.createdTasks) {
      navigator.push(
        MaterialPageRoute(
          builder: (_) =>
              CreatedTasksScreen(userId: cedula, highlightTaskId: taskId),
        ),
      );
      return;
    }

    navigator.push(
      MaterialPageRoute(
        builder: (_) =>
            AssignedTasksScreen(userId: cedula, highlightTaskId: taskId),
      ),
    );
  }

  static String? _extractTaskId(String? payload) {
    if (payload == null) return null;
    final value = payload.trim();
    if (value.isEmpty) return null;

    if (!value.contains('/')) {
      return value;
    }

    final uri = Uri.tryParse(value);
    if (uri != null) {
      final fromQuery = uri.queryParameters['taskId'];
      if (fromQuery != null && fromQuery.trim().isNotEmpty) {
        return fromQuery.trim();
      }

      final segments = uri.pathSegments
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      final tareaIdx = segments.lastIndexWhere(
        (s) => s.toLowerCase() == 'tareas',
      );
      if (tareaIdx != -1 && tareaIdx + 1 < segments.length) {
        return segments[tareaIdx + 1];
      }
      if (segments.isNotEmpty) {
        return segments.last;
      }
    }

    final asUriPath = value
        .split('/')
        .where((s) => s.trim().isNotEmpty)
        .toList();
    return asUriPath.isEmpty ? null : asUriPath.last.trim();
  }

  /// Intenta resolver la cédula:
  /// 1) Usa el provider si existe.
  /// 2) Busca en TBL_USUARIOS por uid == FirebaseAuth.currentUser?.uid y toma el campo 'cedula'.
  static Future<String?> _resolveCedula() async {
    if (_cedulaProvider != null) {
      final v = await _cedulaProvider!.call();
      if (v != null && v.trim().isNotEmpty) return v.trim();
    }

    if (_activeCedula != null && _activeCedula!.trim().isNotEmpty) {
      return _activeCedula!.trim();
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_kActiveCedulaPrefKey);
      if (stored != null && stored.trim().isNotEmpty) {
        _activeCedula = stored.trim();
        return _activeCedula;
      }
    } catch (_) {}

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;

    final q = await FirebaseFirestore.instance
        .collection('TBL_USUARIOS')
        .where('uid', isEqualTo: uid)
        .limit(1)
        .get();

    if (q.docs.isNotEmpty) {
      final ced = q.docs.first.data()['cedula'];
      if (ced is String && ced.trim().isNotEmpty) {
        return ced.trim();
      }
    }
    return null;
  }

  /// Registra el token en la función registerDeviceToken (doc por cédula).
  static Future<void> _registerTokenWithCedula(String token) async {
    final platform = kIsWeb ? 'web' : Platform.operatingSystem;
    final deviceName = kIsWeb
        ? 'Web'
        : Platform.isAndroid
        ? 'Android'
        : Platform.isIOS
        ? 'iOS'
        : platform;
    try {
      final cedula = await _resolveCedula();
      if (cedula == null) {
        if (kDebugMode) {
          print('[FCM] No se pudo resolver cédula. Token no registrado.');
        }
        return;
      }
      final callable = FirebaseFunctions.instance.httpsCallable(
        'registerDeviceToken',
      );
      await callable.call(<String, dynamic>{
        'cedula': cedula,
        'token': token,
        'platform': platform,
        'deviceName': deviceName,
      });
      if (kDebugMode) {
        print('[FCM] Token registrado para cédula: $cedula');
      }
    } catch (e) {
      if (kDebugMode) print('[FCM] registerDeviceToken callable error: $e');
      // Fallback directo a Firestore — funciona en debug Y producción.
      // Si la Cloud Function falla por cualquier razón, el token queda guardado
      // directamente en TBL_USUARIOS para que el servidor pueda enviarlo.
      final cedula = await _resolveCedula();
      if (cedula != null) {
        try {
          await FirebaseFirestore.instance
              .collection('TBL_USUARIOS')
              .doc(cedula)
              .set({
                'fcmTokens': FieldValue.arrayUnion([token]),
                'fcmDevices.$token': {
                  'platform': platform,
                  'deviceName': deviceName,
                  'updatedAt': FieldValue.serverTimestamp(),
                },
              }, SetOptions(merge: true));
          if (kDebugMode) {
            print('[FCM] Token registrado vía fallback para: $cedula');
          }
        } catch (e2) {
          if (kDebugMode) print('[FCM] Fallback Firestore error: $e2');
        }
      }
    }
  }

  /// Stream de la bandeja in-app (si usas doc por cédula y array 'notifications')
  /// Estructura esperada:
  /// TBL_NOTIFICACIONES/<cedula> { notifications: [ {title, description, taskId, createdAt, read}, ... ] }
  static Stream<List<Map<String, dynamic>>> userNotificationsStream({
    required String cedula,
  }) {
    final ref = FirebaseFirestore.instance
        .collection('TBL_NOTIFICACIONES')
        .doc(cedula);

    return ref.snapshots().map((snap) {
      final data = snap.data();
      if (data == null) return <Map<String, dynamic>>[];

      final List list = (data['notifications'] ?? []) as List;
      // Ordena por createdAt desc si existe
      list.sort((a, b) {
        final tsA = (a['createdAt'] as Timestamp?)?.toDate();
        final tsB = (b['createdAt'] as Timestamp?)?.toDate();
        final tA = tsA?.millisecondsSinceEpoch ?? 0;
        final tB = tsB?.millisecondsSinceEpoch ?? 0;
        return tB.compareTo(tA);
      });

      return list.cast<Map<String, dynamic>>();
    });
  }

  /// Marca “read: true” una notificación dentro del array en TBL_NOTIFICACIONES/<cedula>.
  /// Como es un array de mapas, se recomienda reescribir el array con el objeto actualizado.
  static Future<void> markAsRead({
    required String cedula,
    required int indexInArray,
  }) async {
    final docRef = FirebaseFirestore.instance
        .collection('TBL_NOTIFICACIONES')
        .doc(cedula);

    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(docRef);
      final data = snap.data() ?? {};
      final List notifs = (data['notifications'] ?? []) as List;

      if (indexInArray < 0 || indexInArray >= notifs.length) return;

      final item = Map<String, dynamic>.from(notifs[indexInArray] as Map);
      item['read'] = true;
      notifs[indexInArray] = item;

      tx.set(docRef, {'notifications': notifs}, SetOptions(merge: true));
    });
  }
}
