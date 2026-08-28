// lib/home/home_screen.dart

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:todo/state/empresa_scope.dart';
import 'package:todo/services/notification_service.dart';
import 'package:todo/theme/app_typography.dart';
import 'package:todo/utils/task_status.dart';
import 'package:todo/utils/user_company.dart';
import 'package:todo/widgets/skeleton_loader.dart';

import '../admin/admin_dashboard_screen.dart' hide kArial;
import '../talento_humano/talento_humano_dashboard_screen.dart';
import '../gerencia/gerencia_dashboard_screen.dart';
import 'document_management_screen.dart' hide kArial;
import '../gestion_documental/planillas/pp_module_screen.dart';
import '../nutricion/nutricion_dashboard_screen.dart';
import '../compras/compras_dashboard_screen.dart';
import '../compras/compras_models.dart';
import '../compras/compras_service.dart';
import '../compras/abastecimiento_models.dart';
import '../compras/abastecimiento_screen.dart';
import '../interventoria/interventoria_dashboard_screen.dart';
import '../interventoria/interventoria_models.dart';
import '../interventoria/interventoria_service.dart';
import '../facturacion/facturacion_dashboard_screen.dart';
import '../facturacion/facturacion_models.dart';
import '../rutas/rutas_dashboard_screen.dart';
import '../rutas/rutas_models.dart';
import '../rutas/rutas_service.dart';
import '../correo/correo_dashboard_screen.dart';
import '../tokens_dian/dian_tokens_dashboard_screen.dart';
import 'assigned_tasks_screen.dart';
import 'created_tasks_screen.dart';
import 'notifications_screen.dart';
import 'task_history_screen.dart' hide kArial;
import 'create_task_screen.dart' hide kArial;
import '../core/access_guard.dart';
import '../core/task_route_guard.dart';
import '../facturacion/facturacion_navigation.dart';

import 'home_shell.dart';
import 'widgets/home_shared_widgets.dart';

class HomeScreen extends StatefulWidget {
  final String username;
  final String empresaId;
  const HomeScreen({Key? key, required this.username, required this.empresaId})
    : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late DateTime _focusedDay;
  late DateTime _selectedDay;
  Map<String, List<Map<String, dynamic>>> _events = {};

  bool _didRegisterToken = false;
  StreamSubscription<String>? _tokenSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _notifSub;
  final Set<String> _seenNotifIds = <String>{};
  bool _notifsPrimed = false;
  String? _listeningUserId;
  // Empresa activa actualizada en build() para filtrar toasts en el listener.
  String? _currentEmpresaId;

  // ── Citas de Nutrición para el calendario ────────────────────────────────
  // Mapa de eventos de Nutrición separado del mapa de tareas, indexado por
  // 'yyyy-MM-dd'. Se suscribe a TBL_CITAS_NUTRICION y se combina en
  // _getEventsForDay() con _events (tareas).
  Map<String, List<Map<String, dynamic>>> _citasEvents = {};
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _citasSub;
  // Clave que detecta cambio de cedula/empresa para re-suscribirse.
  String? _lastCitasKey;

  // Notificaciones no asociadas directamente a tareas, para que el calendario
  // también funcione como agenda operativa transversal.
  Map<String, List<Map<String, dynamic>>> _notificationEvents = {};
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _notificationCalendarSub;
  String? _lastNotificationCalendarKey;
  Map<String, List<Map<String, dynamic>>> _abastecimientoEvents = {};
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _abastecimientoSub;
  String? _lastAbastecimientoKey;
  String? _abastecimientoRol;
  String? _lastSyncedActiveCedula;

  // Con el módulo de Tareas apagado no se consulta TBL_TAREAS. Son campos y no
  // `Stream.empty()` en línea para conservar la misma instancia entre builds y
  // no re-suscribir el StreamBuilder en cada reconstrucción.
  final Stream<QuerySnapshot<Map<String, dynamic>>> _sinTareasAsignadas =
      Stream<QuerySnapshot<Map<String, dynamic>>>.empty();
  final Stream<QuerySnapshot<Map<String, dynamic>>> _sinTareasCreadas =
      Stream<QuerySnapshot<Map<String, dynamic>>>.empty();

  bool get _isWebShell => kIsWeb && MediaQuery.of(context).size.width >= 900;

  // --- Lógica FCM y Notificaciones ---

  Future<void> _openNotificationTask({
    required String type,
    required String taskId,
    required String cedula,
    required Map<String, dynamic> userData,
  }) async {
    // Tipos de Nutrición: navegan a NutricionDashboardScreen.
    if (type == 'cita_nutricion_agendada' ||
        type == 'cita_nutricion_recordatorio') {
      if (taskId.isNotEmpty && mounted) {
        await abrirNutricionDesdeCita(context, userId: cedula, citaId: taskId);
      }
      return;
    }
    if ((type == 'doc_rechazado' ||
            type == 'correccion_requerida' ||
            type == 'nuevo_proveedor' ||
            type == 'documento_por_vencer') &&
        taskId.startsWith('proveedor:')) {
      final empresaId = normalizeEmpresaId(
        EmpresaScope.of(context, listen: false).selectedEmpresaId,
      );
      if (empresaId == null) return;
      final comprasAllowed = await _guardModuleNavigation(
        userData: userData,
        empresaId: empresaId,
        appId: 'comprasdashboard',
        deniedMessage: 'Sin acceso a Compras.',
      );
      if (!comprasAllowed) return;
      final proveedorId = taskId.replaceFirst('proveedor:', '').trim();
      if (proveedorId.isNotEmpty && mounted) {
        await abrirDetalleProveedor(
          context,
          userId: cedula,
          proveedorId: proveedorId,
        );
      }
      return;
    }
    if ((type == 'ficha_rechazada' || type == 'documento_por_vencer') &&
        taskId.startsWith('ficha:')) {
      final empresaId = normalizeEmpresaId(
        EmpresaScope.of(context, listen: false).selectedEmpresaId,
      );
      if (empresaId == null) return;
      final comprasAllowed = await _guardModuleNavigation(
        userData: userData,
        empresaId: empresaId,
        appId: 'comprasdashboard',
        deniedMessage: 'Sin acceso a Compras.',
      );
      if (!comprasAllowed) return;
      final fichaId = taskId.replaceFirst('ficha:', '').trim();
      if (fichaId.isNotEmpty && mounted) {
        await abrirDetalleFichaRechazada(
          context,
          userId: cedula,
          fichaId: fichaId,
        );
      }
      return;
    }
    if (await tryOpenFacturacionDocumentTask(
      context,
      userId: cedula,
      taskId: taskId,
    )) {
      return;
    }
    if (!mounted) return;
    if ((type == 'recepcion_doc_rechazado' || type == 'documento_por_vencer') &&
        taskId.startsWith('recepcion:')) {
      final empresaId = normalizeEmpresaId(
        EmpresaScope.of(context, listen: false).selectedEmpresaId,
      );
      if (empresaId == null) return;
      final comprasAllowed = await _guardModuleNavigation(
        userData: userData,
        empresaId: empresaId,
        appId: 'comprasdashboard',
        deniedMessage: 'Sin acceso a Compras.',
      );
      if (!comprasAllowed) return;
      if (mounted) {
        await abrirDetalleRecepcionCompras(
          context,
          userId: cedula,
          recepcionId: taskId,
        );
      }
      return;
    }
    if ((type == 'documento_por_vencer' || type == 'marca_doc_rechazado') &&
        taskId.startsWith('marca:')) {
      final empresaId = normalizeEmpresaId(
        EmpresaScope.of(context, listen: false).selectedEmpresaId,
      );
      if (empresaId == null) return;
      final comprasAllowed = await _guardModuleNavigation(
        userData: userData,
        empresaId: empresaId,
        appId: 'comprasdashboard',
        deniedMessage: 'Sin acceso a Compras.',
      );
      if (!comprasAllowed) return;
      final marcaId = taskId.replaceFirst('marca:', '').trim();
      if (marcaId.isNotEmpty && mounted) {
        await abrirDocumentosMarcaCompras(
          context,
          userId: cedula,
          marcaId: marcaId,
        );
      }
      return;
    }
    if (taskId.trim().isEmpty) {
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => NotificationsScreen(
              userId: cedula,
              empresaId: normalizeEmpresaId(
                EmpresaScope.of(context, listen: false).selectedEmpresaId,
              ),
            ),
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    final routeDecision = await TaskRouteGuard().resolveNotificationRoute(
      context,
      userIdentity: cedula,
      taskId: taskId,
      type: type,
    );
    if (!mounted) return;
    if (!routeDecision.allowed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            routeDecision.message ?? 'Error al abrir notificación.',
          ),
        ),
      );
      return;
    }
    if (taskId.trim().isNotEmpty) {
      try {
        await FirebaseFirestore.instance
            .collection('TBL_TAREAS')
            .doc(taskId)
            .set({'visto': true}, SetOptions(merge: true));
      } catch (_) {}
    }
    if (!mounted) return;
    if (routeDecision.target == TaskRouteTarget.taskHistory) {
      Navigator.push(
        context,
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
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              CreatedTasksScreen(userId: cedula, highlightTaskId: taskId),
        ),
      );
      return;
    }
    if (routeDecision.target == TaskRouteTarget.approvalTasks) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CreatedTasksScreen(
            userId: cedula,
            highlightTaskId: taskId,
            approvalMode: true,
          ),
        ),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            AssignedTasksScreen(userId: cedula, highlightTaskId: taskId),
      ),
    );
  }

  // VAPID key for web push (FCM). Get it from:
  // Firebase Console → Project Settings → Cloud Messaging → Web Push certificates → Key pair
  static const String _kVapidKey =
      'BM-x7bSttfxkBKB2mlALEZbBHSYmoBDhrPik9pNrW8y9T3k1W8YavykXmHaHTlwjbtmG-QtsIxKTYHruQGpeBVo';

  Future<String?> _getFcmTokenWithRetries() async {
    try {
      if (kIsWeb) {
        return await FirebaseMessaging.instance.getToken(vapidKey: _kVapidKey);
      }
      return await FirebaseMessaging.instance.getToken();
    } catch (_) {
      return null;
    }
  }

  Future<void> _persistFcmToken({
    required String token,
    required String userId,
  }) async {
    final platform = kIsWeb ? 'web' : Platform.operatingSystem;
    try {
      await FirebaseFunctions.instance
          .httpsCallable('registerDeviceToken')
          .call({'cedula': userId, 'token': token, 'platform': platform});
    } catch (_) {}
    try {
      await FirebaseFirestore.instance
          .collection('TBL_USUARIOS')
          .doc(userId)
          .set({
            'fcmTokens': FieldValue.arrayUnion([token]),
            'fcmDevices.$token': {
              'platform': platform,
              'updatedAt': FieldValue.serverTimestamp(),
            },
          }, SetOptions(merge: true));
    } catch (_) {}
  }

  void _startNotifListener(String userId) {
    if (userId.isEmpty) return;
    _notifSub?.cancel();
    _listeningUserId = userId;
    _notifSub = FirebaseFirestore.instance
        .collection('TBL_NOTIFICACIONES')
        .doc(userId)
        .collection('notifications')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((snap) async {
          if (!_notifsPrimed) {
            for (final doc in snap.docs) {
              _seenNotifIds.add(doc.id);
            }
            _notifsPrimed = true;
            return;
          }
          for (final change in snap.docChanges) {
            if (change.type != DocumentChangeType.added) continue;
            _seenNotifIds.add(change.doc.id);
            // La notificación push en foreground y background la gestiona FCM
            // vía el trigger onNotificationCreated en Cloud Functions.
            // Este listener sólo mantiene el conjunto de IDs vistos para el badge.
          }
        });
  }

  Future<void> _ensureFcmRegistered(String userId) async {
    if (userId.isEmpty) return;
    try {
      await FirebaseMessaging.instance.requestPermission();
      final token = await _getFcmTokenWithRetries();
      if (token != null) await _persistFcmToken(token: token, userId: userId);
    } catch (_) {}
  }

  // --- Helpers de Datos ---

  DateTime? _toDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  bool _isRead(Map<String, dynamic> data) =>
      (data['read'] == true || data['leido'] == true || data['visto'] == true);
  String _titleOf(Map<String, dynamic> m) =>
      (m['titulo'] ?? m['title'] ?? '(Sin título)').toString();
  String _estadoOf(Map<String, dynamic> m) => resolveTaskStatus(m);
  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  List<Map<String, dynamic>> _getEventsForDay(DateTime day) {
    final key = DateFormat('yyyy-MM-dd').format(day);
    final tasks = _events[key] ?? [];
    final citas = _citasEvents[key] ?? [];
    final notificaciones = _notificationEvents[key] ?? [];
    final abastecimiento = _abastecimientoEvents[key] ?? [];
    return [...tasks, ...citas, ...notificaciones, ...abastecimiento];
  }

  /// Suscribe (o re-suscribe) a TBL_CITAS_NUTRICION para el cedula+empresa activa.
  /// Solo re-suscribe cuando cambia la clave cedula:empresaId.
  void _restartCitasSubscription(String cedula, String empresaId) {
    final key = '$cedula:$empresaId';
    if (_lastCitasKey == key) return;
    _lastCitasKey = key;
    _citasSub?.cancel();
    _citasEvents = {};
    _citasSub = FirebaseFirestore.instance
        .collection('TBL_CITAS_NUTRICION')
        .where('userId', isEqualTo: cedula)
        .where('empresaId', isEqualTo: empresaId)
        .where('estado', isEqualTo: 'agendada')
        .snapshots()
        .listen((snap) {
          final newEvents = <String, List<Map<String, dynamic>>>{};
          for (final d in snap.docs) {
            final data = <String, dynamic>{'id': d.id, ...d.data()};
            final raw = data['fechaReevaluacion'];
            final fecha = _toDate(raw);
            if (fecha != null) {
              final k = DateFormat('yyyy-MM-dd').format(fecha);
              // Marcar como cita de Nutrición para diferenciar en el calendario.
              data['_calType'] = 'cita_nutricion';
              data['titulo'] =
                  'Control: ${(data['pacienteNombre'] as String?) ?? 'Nutrición'}';
              newEvents.putIfAbsent(k, () => []).add(data);
            }
          }
          if (mounted) setState(() => _citasEvents = newEvents);
        });
  }

  bool _notificationMatchesEmpresa(
    Map<String, dynamic> data,
    String empresaId,
  ) {
    final notifEmpresa = (data['empresaId'] ?? '').toString().trim();
    final eid = empresaId.trim();
    if (eid.isEmpty) return true;
    return notifEmpresa == eid;
  }

  DateTime? _notificationCalendarDate(Map<String, dynamic> data) {
    final explicit = _toDate(
      data['calendarAt'] ??
          data['scheduledFor'] ??
          data['fechaCalendario'] ??
          data['fechaEvento'],
    );
    if (explicit != null) return explicit;

    final type = (data['type'] ?? '').toString().trim().toLowerCase();
    final taskId = (data['taskId'] ?? '').toString().trim();
    final isModuleNotification =
        taskId.isEmpty ||
        taskId.startsWith('proveedor:') ||
        taskId.startsWith('ficha:') ||
        taskId.startsWith('recepcion:') ||
        type.startsWith('gestion_documental') ||
        type == 'planillas_pago_resumen';
    if (!isModuleNotification) return null;

    return _toDate(data['createdAt']);
  }

  String _notificationCalendarLabel(String type) {
    final t = type.trim().toLowerCase();
    if (t.startsWith('gestion_documental')) return 'GESTIÓN DOC.';
    if (t.contains('cita_nutricion')) return 'NUTRICIÓN';
    if (t.contains('planillas')) return 'PLANILLAS';
    if (t.contains('rechazado') || t.contains('correccion')) return 'COMPRAS';
    if (t.contains('talento') || t.contains('th_')) return 'TALENTO H.';
    if (t.startsWith('fac_')) return 'FACTURACIÓN';
    return 'NOTIFICACIÓN';
  }

  void _restartNotificationCalendarSubscription(
    String cedula,
    String empresaId,
  ) {
    final key = '$cedula:$empresaId';
    if (_lastNotificationCalendarKey == key) return;
    _lastNotificationCalendarKey = key;
    _notificationCalendarSub?.cancel();
    _notificationEvents = {};
    _notificationCalendarSub = FirebaseFirestore.instance
        .collection('TBL_NOTIFICACIONES')
        .doc(cedula)
        .collection('notifications')
        .orderBy('createdAt', descending: true)
        .limit(300)
        .snapshots()
        .listen((snap) {
          final newEvents = <String, List<Map<String, dynamic>>>{};
          for (final d in snap.docs) {
            final data = <String, dynamic>{'id': d.id, ...d.data()};
            if (!_notificationMatchesEmpresa(data, empresaId)) continue;
            final fecha = _notificationCalendarDate(data);
            if (fecha == null) continue;
            final k = DateFormat('yyyy-MM-dd').format(fecha);
            data['_calType'] = 'notificacion';
            data['titulo'] = (data['title'] ?? 'Notificación').toString();
            newEvents.putIfAbsent(k, () => []).add(data);
          }
          if (mounted) setState(() => _notificationEvents = newEvents);
        });
  }

  Future<void> _restartAbastecimientoSubscription(
    String cedula,
    String empresaId,
  ) async {
    final key = '$cedula:$empresaId';
    if (_lastAbastecimientoKey == key) return;
    _lastAbastecimientoKey = key;
    _abastecimientoSub?.cancel();
    _abastecimientoEvents = {};
    _abastecimientoRol = null;

    String? role;
    try {
      role = normalizeComprasRol(
        (await ComprasService().resolveRolUsuario(empresaId, cedula))?.rol,
      );
    } catch (_) {}
    if (!mounted || _lastAbastecimientoKey != key) return;
    _abastecimientoRol = role;
    if (role != kRolBodega && role != kRolAdmin) {
      if (mounted) setState(() => _abastecimientoEvents = {});
      return;
    }

    _abastecimientoSub = FirebaseFirestore.instance
        .collection(kAbastecimientoCollection)
        .where('empresaId', isEqualTo: empresaId)
        .snapshots()
        .listen((snapshot) {
          final events = <String, List<Map<String, dynamic>>>{};
          for (final doc in snapshot.docs) {
            final delivery = AbastecimientoDoc.fromMap(doc.id, doc.data());
            if (delivery.eliminado) continue;
            if (!delivery.estado.visibleEnCalendario) continue;
            final date = delivery.fechaProgramada;
            if (date == null) continue;
            final dateKey = DateFormat('yyyy-MM-dd').format(date);
            events.putIfAbsent(dateKey, () => []).add({
              'id': delivery.id,
              'empresaId': delivery.empresaId,
              '_calType': 'abastecimiento',
              'titulo': '${delivery.producto} · ${delivery.proveedor}',
              'description': [
                delivery.destino,
                delivery.ordenCompra,
                delivery.estado.label,
                if (delivery.pendencias.isNotEmpty)
                  delivery.pendencias.map((item) => item.label).join(', '),
              ].where((value) => value.trim().isNotEmpty).join(' · '),
              'estado': delivery.estado.value,
            });
          }
          if (mounted && _lastAbastecimientoKey == key) {
            setState(() => _abastecimientoEvents = events);
          }
        });
  }

  void _syncActiveNotificationCedula(String cedula) {
    if (_lastSyncedActiveCedula == cedula) return;
    _lastSyncedActiveCedula = cedula;
    unawaited(NotificationsService.setActiveCedula(cedula));
  }

  Future<void> _abrirCompras(
    BuildContext context,
    String userId,
    String empresaId,
    Map<String, dynamic> userData,
  ) async {
    if (await _guardModuleNavigation(
      userData: userData,
      empresaId: empresaId,
      appId: 'comprasdashboard',
      deniedMessage: 'Sin acceso a Compras.',
    )) {
      String? rolCompras;
      try {
        rolCompras = (await ComprasService().resolveRolUsuario(
          empresaId,
          userId,
        ))?.rol;
      } catch (_) {}
      if (context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ComprasDashboardScreen(
              userId: userId,
              empresaId: empresaId,
              rolCompras: rolCompras,
            ),
          ),
        );
      }
    }
  }

  Future<void> _abrirInterventoria(
    BuildContext context,
    String userId,
    String empresaId,
    Map<String, dynamic> userData,
  ) async {
    if (await _guardModuleNavigation(
      userData: userData,
      empresaId: empresaId,
      appId: kInterventoriaAppId,
      deniedMessage: 'Sin acceso a Interventoria.',
    )) {
      String? rolInterventoria;
      try {
        rolInterventoria = (await InterventoriaService().getRolUsuario(
          empresaId,
          userId,
        ))?.rol;
      } catch (_) {}
      if (context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => InterventoriaDashboardScreen(
              userId: userId,
              empresaId: empresaId,
              rolInterventoria: rolInterventoria,
            ),
          ),
        );
      }
    }
  }

  Future<void> _abrirRutas(
    BuildContext context,
    String userId,
    String empresaId,
    Map<String, dynamic> userData,
  ) async {
    if (await _guardModuleNavigation(
      userData: userData,
      empresaId: empresaId,
      appId: kRutasAppId,
      deniedMessage: 'Sin acceso a Rutas.',
    )) {
      String? rolRutas;
      try {
        rolRutas = (await RutasService().getRolUsuario(empresaId, userId))?.rol;
      } catch (_) {}
      final developerOverride = isDeveloperUser(userData, empresaId: empresaId);
      if (context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => RutasDashboardScreen(
              userId: userId,
              empresaId: empresaId,
              rolRutas: rolRutas,
              desarrolladorOverride: developerOverride,
            ),
          ),
        );
      }
    }
  }

  Future<void> _abrirFacturacion(
    BuildContext context,
    String userId,
    String empresaId,
    Map<String, dynamic> userData,
  ) async {
    if (await _guardModuleNavigation(
      userData: userData,
      empresaId: empresaId,
      appId: kFacAppId,
      deniedMessage: 'Sin acceso a Facturación.',
    )) {
      if (context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => FacturacionDashboardScreen(
              userId: userId,
              empresaId: empresaId,
              developerOverride: isDeveloperUser(
                userData,
                empresaId: empresaId,
              ),
            ),
          ),
        );
      }
    }
  }

  Future<void> _abrirCorreo(
    BuildContext context,
    String userId,
    String empresaId,
    Map<String, dynamic> userData,
  ) async {
    if (await _guardModuleNavigation(
      userData: userData,
      empresaId: empresaId,
      appId: 'correodashboard',
      deniedMessage: 'Sin acceso a Correo.',
    )) {
      if (context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                CorreoDashboardScreen(userId: userId, empresaId: empresaId),
          ),
        );
      }
    }
  }

  Future<void> _abrirTokensDian(
    BuildContext context,
    String userId,
    String empresaId,
    Map<String, dynamic> userData,
  ) async {
    if (await _guardModuleNavigation(
      userData: userData,
      empresaId: empresaId,
      appId: kDianTokensAppId,
      deniedMessage: 'Sin acceso a Tokens DIAN.',
    )) {
      if (context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DianTokensDashboardScreen(
              userId: userId,
              empresaId: empresaId,
              adminMode:
                  isDeveloperUser(userData, empresaId: empresaId) ||
                  userHasApp(userData, 'admindashboard', empresaId: empresaId),
            ),
          ),
        );
      }
    }
  }

  Future<bool> _guardModuleNavigation({
    required Map<String, dynamic> userData,
    required String empresaId,
    required String appId,
    required String deniedMessage,
  }) async {
    final d = await AccessGuard().canAccess(
      userData: userData,
      empresaId: empresaId,
      appId: appId,
    );
    if (!d.allowed && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(d.message ?? deniedMessage)));
    }
    return d.allowed;
  }

  @override
  void initState() {
    super.initState();
    _focusedDay = DateTime.now();
    _selectedDay = DateTime.now();
  }

  @override
  void dispose() {
    _tokenSub?.cancel();
    _notifSub?.cancel();
    _citasSub?.cancel();
    _notificationCalendarSub?.cancel();
    _abastecimientoSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cedula = widget.username;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final String scopeEmpresa =
        EmpresaScope.of(context).selectedEmpresaId ?? widget.empresaId;
    // Mantener empresa activa sincronizada para el listener de toasts.
    _currentEmpresaId = scopeEmpresa;
    // Suscribir/re-suscribir citas de Nutrición para el calendario.
    _restartCitasSubscription(cedula, scopeEmpresa);
    _restartNotificationCalendarSubscription(cedula, scopeEmpresa);
    unawaited(_restartAbastecimientoSubscription(cedula, scopeEmpresa));
    _syncActiveNotificationCedula(cedula);

    if (!_didRegisterToken) {
      _didRegisterToken = true;
      _ensureFcmRegistered(cedula);
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('TBL_USUARIOS')
          .doc(cedula)
          .snapshots(),
      builder: (context, userSnap) {
        if (!userSnap.hasData) {
          return HomeShell(userId: cedula, body: const SkeletonList());
        }

        final userData = userSnap.data?.data() ?? {};
        final apps = extractUserApps(userData, empresaId: scopeEmpresa);
        final isDev = isDeveloperUser(userData, empresaId: scopeEmpresa);
        final nombreUsuario =
            userData['primerNombre'] ?? userData['nombres'] ?? cedula;

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('TBL_APPS')
              .where('empresaId', isEqualTo: scopeEmpresa)
              .snapshots(),
          builder: (context, appsEmpresaSnap) {
            // Apps explícitamente deshabilitadas para la empresa activa en TBL_APPS.
            // Semántica: ausencia de documento = habilitado (legacy compat).
            // Solo se oculta si el documento existe con enabled == false.
            final disabledAppIds = appsEmpresaSnap.hasData
                ? appsEmpresaSnap.data!.docs
                      .where((d) => (d.data()['enabled'] as bool?) == false)
                      .map((d) {
                        final raw = (d.data()['appId'] ?? '').toString();
                        return normalizeAppId(raw) ?? '';
                      })
                      .where((id) => id.isNotEmpty)
                      .toSet()
                : <String>{};

            // Acceso al módulo de Tareas. Se resuelve ANTES de consultar
            // TBL_TAREAS: si está apagado no se leen tareas, no se pintan en
            // el calendario y no se ofrece crearlas en ninguna vista.
            // Notificaciones y calendario NO dependen de esto: los conserva
            // todo el personal.
            final showTareas = _moduleVisible(
              apps,
              isDev,
              'tareasdashboard',
              disabledAppIds,
            );

            // Dos queries separadas porque Firestore no admite OR entre campos distintos.
            // assignedSnap: tareas donde soy el destinatario.
            // createdSnap:  tareas donde soy el creador/emisor.
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: showTareas
                  ? FirebaseFirestore.instance
                        .collection('TBL_TAREAS')
                        .where('asignado_uid', isEqualTo: cedula)
                        .snapshots()
                  : _sinTareasAsignadas,
              builder: (context, assignedSnap) {
                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: showTareas
                      ? FirebaseFirestore.instance
                            .collection('TBL_TAREAS')
                            .where('creador_id', isEqualTo: cedula)
                            .snapshots()
                      : _sinTareasCreadas,
                  builder: (context, createdSnap) {
                    // Fusionar y deduplicar por doc.id
                    final seen = <String>{};
                    final tasks = <Map<String, dynamic>>[];
                    for (final doc in [
                      ...(assignedSnap.data?.docs ?? []),
                      ...(createdSnap.data?.docs ?? []),
                    ]) {
                      if (!seen.add(doc.id)) continue;
                      final data = doc.data();
                      if (matchesEmpresaScope(
                        data,
                        scopeEmpresa,
                        allowLegacyWithoutEmpresa: true,
                      )) {
                        tasks.add({'id': doc.id, ...data});
                      }
                    }

                    // Actualizar mapa de eventos para marcadores del calendario.
                    // Incluye tanto tareas asignadas a mí como las que yo emití.
                    // Prioridad: fecha_limite → dueDate → fecha_creacion.
                    _events.clear();
                    for (final t in tasks) {
                      final due = _toDate(
                        t['fecha_limite'] ??
                            t['dueDate'] ??
                            t['fecha_creacion'],
                      );
                      if (due != null) {
                        final key = DateFormat('yyyy-MM-dd').format(due);
                        _events.putIfAbsent(key, () => []).add(t);
                      }
                    }

                    return HomeShell(
                      userId: cedula,
                      showTareas: showTareas,
                      appBar: _isWebShell
                          ? null
                          : AppBar(
                              title: CompanyNameWidget(
                                empresaId: scopeEmpresa,
                                style: const TextStyle(
                                  fontFamily: kArial,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                              backgroundColor: scheme.primary,
                              foregroundColor: scheme.onPrimary,
                              actions: [
                                _buildNotificationBell(cedula, userData),
                                const SizedBox(width: 8),
                              ],
                            ),
                      body: _isWebShell
                          ? _buildWebHome(
                              cedula,
                              scopeEmpresa,
                              userData,
                              apps,
                              isDev,
                              disabledAppIds,
                              theme,
                              scheme,
                              nombreUsuario,
                              showTareas,
                            )
                          : _buildMobileHome(
                              cedula,
                              scopeEmpresa,
                              userData,
                              apps,
                              isDev,
                              disabledAppIds,
                              theme,
                              scheme,
                              nombreUsuario,
                              showTareas,
                            ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  // --- HOME WEB (Consola de Control) ---
  Widget _buildWebHome(
    String cedula,
    String empresaId,
    Map<String, dynamic> userData,
    List<String> apps,
    bool isDev,
    Set<String> disabledAppIds,
    ThemeData theme,
    ColorScheme scheme,
    String nombre,
    bool showTareas,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hola, $nombre',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontFamily: kArial,
                    ),
                  ),
                  CompanyNameWidget(
                    empresaId: empresaId,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  // La campana no depende de ningún módulo: las
                  // notificaciones las recibe todo el personal.
                  _buildNotificationBell(cedula, userData),
                  if (showTareas) ...[
                    const SizedBox(width: 16),
                    FilledButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              CreateTaskScreen(currentUserId: cedula),
                        ),
                      ),
                      icon: const Icon(Icons.add),
                      label: const Text('Nueva Tarea'),
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 32),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Columna Izquierda: Grid de Módulos (Consola)
              Expanded(
                flex: 2,
                child: _buildModuleGrid(
                  cedula,
                  empresaId,
                  userData,
                  apps,
                  isDev,
                  disabledAppIds,
                  true,
                ),
              ),
              const SizedBox(width: 32),
              // Columna Derecha: Agenda y Tareas del día
              Expanded(
                flex: 1,
                child: Column(
                  children: [
                    const SectionHeader(title: 'Calendario de Actividades'),
                    const SizedBox(height: 12),
                    _buildCalendarCard(scheme),
                    const SizedBox(height: 24),
                    // Sin el módulo de Tareas la agenda del día sigue viva:
                    // muestra citas y notificaciones, no tareas.
                    SectionHeader(
                      title: showTareas
                          ? 'Pendientes para ${DateFormat('dd/MM').format(_selectedDay)}'
                          : 'Agenda del ${DateFormat('dd/MM').format(_selectedDay)}',
                    ),
                    const SizedBox(height: 12),
                    _buildSelectedDayTasksCard(cedula, empresaId, userData),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- HOME MÓVIL (Acción Rápida) ---
  Widget _buildMobileHome(
    String cedula,
    String empresaId,
    Map<String, dynamic> userData,
    List<String> apps,
    bool isDev,
    Set<String> disabledAppIds,
    ThemeData theme,
    ColorScheme scheme,
    String nombre,
    bool showTareas,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Hola, $nombre',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              fontFamily: kArial,
            ),
          ),
          const SizedBox(height: 20),

          const SectionHeader(title: 'Mis Módulos'),
          const SizedBox(height: 12),
          // Módulos Deslizables en Móvil
          _buildMobileModuleSlider(
            cedula,
            empresaId,
            userData,
            apps,
            isDev,
            disabledAppIds,
          ),

          const SizedBox(height: 32),
          const SectionHeader(title: 'Mi Agenda'),
          const SizedBox(height: 12),
          _buildCalendarCard(scheme),

          const SizedBox(height: 20),
          // "Ver todos" abre la bandeja de tareas: solo con el módulo activo.
          SectionHeader(
            title: showTareas ? 'Pendientes de hoy' : 'Agenda del día',
            trailing: showTareas
                ? TextButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AssignedTasksScreen(userId: cedula),
                      ),
                    ),
                    child: const Text('Ver todos'),
                  )
                : null,
          ),
          const SizedBox(height: 8),
          _buildSelectedDayTasksCard(cedula, empresaId, userData),
        ],
      ),
    );
  }

  // --- Widgets de Soporte ---

  Widget _buildMobileModuleSlider(
    String cedula,
    String empresaId,
    Map<String, dynamic> userData,
    List<String> apps,
    bool isDev,
    Set<String> disabledAppIds,
  ) {
    final modules = _getModuleWidgets(
      cedula,
      empresaId,
      userData,
      apps,
      isDev,
      disabledAppIds,
      false,
    );
    if (modules.isEmpty) return const SizedBox.shrink();

    // La tarjeta mide icono + dos líneas de título. Con la letra del sistema
    // en grande esas dos líneas crecen y se salían de una altura fija de 120,
    // así que la altura acompaña la escala de texto del dispositivo.
    final escala = MediaQuery.textScalerOf(context).scale(11) / 11;
    final alto = (108 + 26 * (escala - 1) * 2).clamp(108.0, 168.0);

    return SizedBox(
      height: alto,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        itemCount: modules.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) => modules[index],
      ),
    );
  }

  Widget _buildNotificationBell(String cedula, Map<String, dynamic> userData) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final scopeEmpresa =
        EmpresaScope.of(context, listen: false).selectedEmpresaId ??
        widget.empresaId;
    final isMobile = !_isWebShell;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('TBL_NOTIFICACIONES')
          .doc(cedula)
          .collection('notifications')
          .snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];
        final unread = docs.where((d) {
          final data = d.data();
          if (_isRead(data)) return false;
          final notifEmpresa = (data['empresaId'] ?? '').toString().trim();
          return scopeEmpresa.trim().isEmpty || notifEmpresa == scopeEmpresa;
        }).length;
        final iconColor = isMobile
            ? Colors.white
            : (unread > 0
                  ? scheme.primary
                  : scheme.onSurfaceVariant.withValues(alpha: 0.7));

        return IconButton(
          tooltip: 'Notificaciones',
          onPressed: () {
            final eid =
                EmpresaScope.of(context, listen: false).selectedEmpresaId ??
                widget.empresaId;
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    NotificationsScreen(userId: cedula, empresaId: eid),
              ),
            );
          },
          icon: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 26,
                height: 26,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: ScaleTransition(scale: anim, child: child),
                  ),
                  child: Icon(
                    unread > 0
                        ? Icons.notifications_active_rounded
                        : Icons.notifications_none_rounded,
                    key: ValueKey(unread > 0),
                    color: iconColor,
                    size: 26,
                  ),
                ),
              ),
              if (unread > 0)
                Positioned(
                  right: -7,
                  top: -6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 3,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.error,
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(color: scheme.surface, width: 1.5),
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 14,
                      minHeight: 14,
                    ),
                    child: Text(
                      unread > 99 ? '99+' : '$unread',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                        fontFamily: kArial,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildModuleGrid(
    String cedula,
    String empresaId,
    Map<String, dynamic> userData,
    List<String> apps,
    bool isDev,
    Set<String> disabledAppIds,
    bool isWeb,
  ) {
    final modules = _getModuleWidgets(
      cedula,
      empresaId,
      userData,
      apps,
      isDev,
      disabledAppIds,
      isWeb,
    );
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: isWeb ? 300 : 160,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: isWeb ? 1.6 : 1.3,
      ),
      itemCount: modules.length,
      itemBuilder: (context, index) => modules[index],
    );
  }

  /// Verifica si el usuario tiene acceso visible a un módulo.
  /// Acepta tanto el ID completo ('comprasdashboard') como el ID corto
  /// legacy ('compras') que puede estar almacenado en el campo apps del
  /// documento de Firestore antes de la estandarización.
  /// [disabledAppIds]: apps con enabled=false en TBL_APPS para la empresa
  /// activa. Si el app está en este set, se oculta aunque el usuario lo tenga
  /// asignado. Ausencia de documento en TBL_APPS = habilitado (legacy compat).
  bool _moduleVisible(
    List<String> apps,
    bool isDev,
    String fullAppId,
    Set<String> disabledAppIds,
  ) {
    if (isDev) return true;
    // Si está explícitamente deshabilitado para esta empresa, no mostrar.
    if (disabledAppIds.any((id) => appIdsEquivalent(id, fullAppId))) {
      return false;
    }
    return apps.any((app) => appIdsEquivalent(app, fullAppId));
  }

  bool _planillasVisible(
    Map<String, dynamic> userData,
    String empresaId,
    List<String> apps,
    bool isDev,
    Set<String> disabledAppIds,
  ) {
    if (disabledAppIds.any((id) => appIdsEquivalent(id, kPlanillasPagoAppId))) {
      return false;
    }
    if (_moduleVisible(apps, isDev, kPlanillasPagoAppId, disabledAppIds)) {
      return true;
    }
    final detail = getUserCompanyDetail(userData, empresaId);
    final legacyRole =
        (detail?['rolPlanillas'] ?? userData['rolPlanillas'] ?? '')
            .toString()
            .trim();
    return legacyRole.isNotEmpty;
  }

  List<Widget> _getModuleWidgets(
    String cedula,
    String empresaId,
    Map<String, dynamic> userData,
    List<String> apps,
    bool isDev,
    Set<String> disabledAppIds,
    bool isWeb,
  ) {
    final cardWidth = isWeb ? null : 140.0;
    return [
      if (_moduleVisible(apps, isDev, 'admindashboard', disabledAppIds))
        ModuleCard(
          width: cardWidth,
          title: 'Administración',
          icon: Icons.admin_panel_settings_rounded,
          color: const Color(0xFF475569),
          compact: !isWeb,
          onTap: () async {
            final permitido = await _guardModuleNavigation(
              userData: userData,
              empresaId: empresaId,
              appId: 'admindashboard',
              deniedMessage: 'Sin acceso',
            );
            if (!permitido || !mounted) return;
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    AdminDashboardScreen(userId: cedula, empresaId: empresaId),
              ),
            );
          },
        ),

      if (_moduleVisible(apps, isDev, 'talentohumanodashboard', disabledAppIds))
        ModuleCard(
          width: cardWidth,
          title: 'Talento Humano',
          icon: Icons.groups_rounded,
          color: const Color(0xFF4F46E5),
          compact: !isWeb,
          onTap: () async {
            final permitido = await _guardModuleNavigation(
              userData: userData,
              empresaId: empresaId,
              appId: 'talentohumanodashboard',
              deniedMessage: 'Sin acceso',
            );
            if (!permitido || !mounted) return;
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => TalentoHumanoDashboardScreen(
                  userId: cedula,
                  empresaId: empresaId,
                ),
              ),
            );
          },
        ),

      if (_moduleVisible(apps, isDev, 'gerenciadashboard', disabledAppIds))
        ModuleCard(
          width: cardWidth,
          title: 'Gerencia',
          icon: Icons.query_stats_rounded,
          color: const Color(0xFF7C3AED),
          compact: !isWeb,
          onTap: () async {
            final permitido = await _guardModuleNavigation(
              userData: userData,
              empresaId: empresaId,
              appId: 'gerenciadashboard',
              deniedMessage: 'Sin acceso',
            );
            if (!permitido || !mounted) return;
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => GerenciaDashboardScreen(
                  userId: cedula,
                  empresaId: empresaId,
                ),
              ),
            );
          },
        ),

      if (_moduleVisible(
        apps,
        isDev,
        'gestiondocumentaldashboard',
        disabledAppIds,
      ))
        ModuleCard(
          width: cardWidth,
          title: 'Gestión de Correspondencia',
          icon: Icons.auto_stories_rounded,
          color: const Color(0xFF0D9488),
          compact: !isWeb,
          onTap: () async {
            final permitido = await _guardModuleNavigation(
              userData: userData,
              empresaId: empresaId,
              appId: 'gestiondocumentaldashboard',
              deniedMessage: 'Sin acceso',
            );
            if (!permitido || !mounted) return;
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DocumentManagementScreen(
                  currentUserId: cedula,
                  empresaId: empresaId,
                ),
              ),
            );
          },
        ),

      if (_planillasVisible(userData, empresaId, apps, isDev, disabledAppIds))
        ModuleCard(
          width: cardWidth,
          title: 'Planillas de Pago',
          icon: Icons.request_quote_rounded,
          color: const Color(0xFFB45309),
          compact: !isWeb,
          onTap: () async {
            final permitido = await _guardModuleNavigation(
              userData: userData,
              empresaId: empresaId,
              appId: kPlanillasPagoAppId,
              deniedMessage: 'Sin acceso a Planillas de Pago',
            );
            if (!permitido || !mounted) return;
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PlanillasPagoModuleScreen(
                  userId: cedula,
                  empresaId: empresaId,
                ),
              ),
            );
          },
        ),

      if (_moduleVisible(apps, isDev, 'nutriciondashboard', disabledAppIds))
        ModuleCard(
          width: cardWidth,
          title: 'Nutrición',
          icon: Icons.restaurant_menu_rounded,
          color: const Color(0xFFEA580C),
          compact: !isWeb,
          onTap: () async {
            final permitido = await _guardModuleNavigation(
              userData: userData,
              empresaId: empresaId,
              appId: 'nutriciondashboard',
              deniedMessage: 'Sin acceso',
            );
            if (!permitido || !mounted) return;
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => NutricionDashboardScreen(
                  userId: cedula,
                  empresaId: empresaId,
                ),
              ),
            );
          },
        ),

      if (_moduleVisible(apps, isDev, 'comprasdashboard', disabledAppIds))
        ModuleCard(
          width: cardWidth,
          title: 'Compras',
          icon: Icons.shopping_bag_rounded,
          color: const Color(0xFF2563EB),
          compact: !isWeb,
          onTap: () => _abrirCompras(context, cedula, empresaId, userData),
        ),

      if (_moduleVisible(apps, isDev, 'correodashboard', disabledAppIds))
        ModuleCard(
          width: cardWidth,
          title: 'Correo',
          icon: Icons.mark_email_unread_rounded,
          color: const Color(0xFF0F766E),
          compact: !isWeb,
          onTap: () => _abrirCorreo(context, cedula, empresaId, userData),
        ),

      if (_moduleVisible(apps, isDev, kDianTokensAppId, disabledAppIds))
        ModuleCard(
          width: cardWidth,
          title: 'Tokens DIAN',
          icon: Icons.vpn_key_rounded,
          color: const Color(0xFF0E7490),
          compact: !isWeb,
          onTap: () => _abrirTokensDian(context, cedula, empresaId, userData),
        ),

      if (_moduleVisible(apps, isDev, kInterventoriaAppId, disabledAppIds))
        ModuleCard(
          width: cardWidth,
          title: 'Interventoria',
          icon: Icons.document_scanner_rounded,
          color: const Color(0xFF0F766E),
          compact: !isWeb,
          onTap: () =>
              _abrirInterventoria(context, cedula, empresaId, userData),
        ),

      if (_moduleVisible(apps, isDev, kFacAppId, disabledAppIds))
        ModuleCard(
          width: cardWidth,
          title: 'Facturación',
          icon: Icons.receipt_long_rounded,
          color: const Color(0xFF0369A1),
          compact: !isWeb,
          onTap: () => _abrirFacturacion(context, cedula, empresaId, userData),
        ),

      if (_moduleVisible(apps, isDev, kRutasAppId, disabledAppIds))
        ModuleCard(
          width: cardWidth,
          title: 'Rutas',
          icon: Icons.local_shipping_rounded,
          color: kRutasColor,
          compact: !isWeb,
          onTap: () => _abrirRutas(context, cedula, empresaId, userData),
        ),
    ];
  }

  Widget _buildCalendarCard(ColorScheme scheme) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: TableCalendar(
        locale: 'es_CO',
        firstDay: DateTime.utc(2020, 1, 1),
        lastDay: DateTime.utc(2030, 12, 31),
        focusedDay: _focusedDay,
        selectedDayPredicate: (day) => _isSameDay(_selectedDay, day),
        eventLoader: _getEventsForDay,
        onDaySelected: (sel, foc) => setState(() {
          _selectedDay = sel;
          _focusedDay = foc;
        }),
        calendarStyle: CalendarStyle(
          todayDecoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.3),
            shape: BoxShape.circle,
          ),
          selectedDecoration: BoxDecoration(
            color: scheme.primary,
            shape: BoxShape.circle,
          ),
          markerDecoration: const BoxDecoration(
            color: Colors.orange,
            shape: BoxShape.circle,
          ),
          markersMaxCount: 3,
          outsideDaysVisible: false,
        ),
        headerStyle: const HeaderStyle(
          formatButtonVisible: false,
          titleCentered: true,
        ),
        // Personalizar marcadores para que sean visibles
        calendarBuilders: CalendarBuilders(
          markerBuilder: (context, date, events) {
            if (events.isEmpty) return const SizedBox.shrink();
            return Positioned(
              right: 1,
              bottom: 1,
              child: _buildEventsMarker(events.length),
            );
          },
        ),
      ),
    );
  }

  Widget _buildEventsMarker(int count) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: const BoxDecoration(
        color: Colors.orange,
        shape: BoxShape.circle,
      ),
      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
      child: Text(
        '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildSelectedDayTasksCard(
    String cedula,
    String scopeEmpresa,
    Map<String, dynamic> userData,
  ) {
    final tasks = _getEventsForDay(_selectedDay);
    final scheme = Theme.of(context).colorScheme;

    if (tasks.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Column(
            children: [
              Icon(
                Icons.event_available_outlined,
                size: 40,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.2),
              ),
              const SizedBox(height: 8),
              Text(
                'Sin pendientes para este día',
                style: TextStyle(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: tasks.map((t) {
        final esCita = t['_calType'] == 'cita_nutricion';
        final esNotificacion = t['_calType'] == 'notificacion';
        final esAbastecimiento = t['_calType'] == 'abastecimiento';

        if (esCita) {
          // ── Evento de Nutrición ───────────────────────────────────────────
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 4,
              ),
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.teal.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.medical_services_outlined,
                  color: Colors.teal,
                  size: 20,
                ),
              ),
              title: Text(
                _titleOf(t),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontFamily: kArial,
                  fontSize: 14,
                  letterSpacing: -0.2,
                ),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.teal.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'NUTRICIÓN',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          color: Colors.teal.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              trailing: const Icon(Icons.chevron_right_rounded, size: 20),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => NutricionDashboardScreen(
                    userId: cedula,
                    empresaId: (t['empresaId'] as String?) ?? scopeEmpresa,
                  ),
                ),
              ),
            ),
          );
        }

        if (esNotificacion) {
          final type = (t['type'] ?? '').toString();
          final desc = (t['description'] ?? t['body'] ?? '').toString();
          final label = _notificationCalendarLabel(type);
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 4,
              ),
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.notifications_active_outlined,
                  color: scheme.primary,
                  size: 20,
                ),
              ),
              title: Text(
                _titleOf(t),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontFamily: kArial,
                  fontSize: 14,
                ),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          color: scheme.primary,
                        ),
                      ),
                    ),
                    if (desc.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        desc,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant.withValues(alpha: 0.75),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              trailing: const Icon(Icons.chevron_right_rounded, size: 20),
              onTap: () => _openNotificationTask(
                type: type,
                taskId: (t['taskId'] ?? '').toString(),
                cedula: cedula,
                userData: userData,
              ),
            ),
          );
        }

        if (esAbastecimiento) {
          final description = (t['description'] ?? '').toString();
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFF0F4C81).withOpacity(0.28),
              ),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 5,
              ),
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F4C81).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.local_shipping_outlined,
                  color: Color(0xFF0F4C81),
                  size: 20,
                ),
              ),
              title: Text(
                _titleOf(t),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontFamily: kArial,
                  fontSize: 14,
                ),
              ),
              subtitle: description.isEmpty
                  ? null
                  : Text(
                      description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
              trailing: const Icon(Icons.chevron_right_rounded, size: 20),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AbastecimientoScreen(
                    empresaId: scopeEmpresa,
                    userId: cedula,
                    rolCompras: _abastecimientoRol,
                    initialDate: _selectedDay,
                    onRegistrarRecepcion: (entrega) =>
                        abrirNuevaRecepcionDesdeAbastecimiento(
                          context,
                          empresaId: scopeEmpresa,
                          userId: cedula,
                          entrega: entrega,
                        ),
                    onAbrirRecepcion: (recepcionId) =>
                        abrirDetalleRecepcionCompras(
                          context,
                          userId: cedula,
                          recepcionId: recepcionId,
                        ),
                  ),
                ),
              ),
            ),
          );
        }

        // ── Tarea normal ──────────────────────────────────────────────────────
        final estado = _estadoOf(t);
        final esFinalizada =
            estado.contains('finalizado') || estado.contains('completada');

        final isAsignadaAMi = t['asignado_uid'] == cedula;
        // Se considera "recibida" si yo la creé o soy el jefe, y NO está asignada a mí
        final isRecibida =
            (t['creador_id'] == cedula || t['jefe_uid'] == cedula) &&
            !isAsignadaAMi;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 4,
            ),
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color:
                    (esFinalizada
                            ? Colors.green
                            : (isRecibida ? Colors.blue : Colors.orange))
                        .withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                esFinalizada
                    ? Icons.check_rounded
                    : (isRecibida
                          ? Icons.input_rounded
                          : Icons.pending_actions_rounded),
                color: esFinalizada
                    ? Colors.green
                    : (isRecibida ? Colors.blue : Colors.orange),
                size: 20,
              ),
            ),
            title: Text(
              _titleOf(t),
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontFamily: kArial,
                fontSize: 14,
                letterSpacing: -0.2,
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: (isRecibida ? Colors.blue : Colors.orange)
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      isRecibida ? 'POR RECIBIR' : 'POR ENTREGAR',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        color: (isRecibida
                            ? Colors.blue.shade700
                            : Colors.orange.shade700),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    estado.toUpperCase(),
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
            trailing: const Icon(Icons.chevron_right_rounded, size: 20),
            onTap: () {
              final taskId = (t['id'] ?? t['taskId'] ?? '').toString();
              if (esFinalizada) {
                // Finalizada: va al historial (tab según si la creé o fue asignada a mí)
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TaskHistoryScreen(
                      currentUserId: cedula,
                      initialTabIndex: isRecibida ? 1 : 0,
                      highlightTaskId: taskId,
                    ),
                  ),
                );
                return;
              }
              if (isRecibida) {
                // Activa y soy creador/jefe: va a "Tareas que yo asigné"
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CreatedTasksScreen(
                      userId: cedula,
                      highlightTaskId: taskId,
                    ),
                  ),
                );
                return;
              }
              // Activa y soy asignado: va a "Mis tareas asignadas"
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AssignedTasksScreen(
                    userId: cedula,
                    highlightTaskId: taskId,
                  ),
                ),
              );
            },
          ),
        );
      }).toList(),
    );
  }
}
