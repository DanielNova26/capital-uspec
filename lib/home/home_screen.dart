// lib/home/home_screen.dart

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:todo/state/empresa_scope.dart';
import 'package:todo/services/local_notification_service.dart';
import 'package:todo/theme/app_typography.dart';
import 'package:todo/utils/task_status.dart';
import 'package:todo/widgets/empty_state_widget.dart';
import 'package:todo/widgets/skeleton_loader.dart';

// Import relativo al Admin Dashboard
import '../admin/admin_dashboard_screen.dart' hide kArial;
// Import relativo al Talento Humano Dashboard
import '../talento_humano/talento_humano_dashboard_screen.dart';
import '../gerencia/gerencia_dashboard_screen.dart';
import 'document_management_screen.dart' hide kArial;
import '../nutricion/nutricion_dashboard_screen.dart';
import '../compras/compras_dashboard_screen.dart';
// Drawer modularizado
import 'app_drawer.dart' hide kArial;
import 'assigned_tasks_screen.dart';
import 'task_history_screen.dart' hide kArial;

class HomeScreen extends StatefulWidget {
  final String username; // cédula o username (docId en TBL_USUARIOS)
  final String empresaId;
  const HomeScreen({
    Key? key,
    required this.username,
    required this.empresaId,
  }) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late DateTime _focusedDay;
  late DateTime _selectedDay;
  Map<String, List<Map<String, dynamic>>> _events = {};

  // Registro automático de FCM
  bool _didRegisterToken = false;
  StreamSubscription<String>? _tokenSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _notifSub;
  final Set<String> _seenNotifIds = <String>{};
  bool _notifsPrimed = false;
  String? _listeningUserId;

  // ✅ Mapea type -> pestaña del Proceso
  String? _processTabForNotifType(String raw) {
    final t = raw.trim().toLowerCase();
    if (t.startsWith('task_status_')) {
      final status = t.replaceFirst('task_status_', '').trim();
      if (status == 'finalizada' ||
          status == 'finalizado' ||
          status == 'completada' ||
          status == 'por_aprobar') {
        return 'Finalización';
      }
      if (status == 'en_progreso') return 'Avances';
    }

    // Avances (incluye tus types reales)
    const avances = {
      'avance',
      'progress',
      'task_progress',
      'task_avance',        // ✅ FIX
      'gestion_avance',
      'avance_creado',
      'avance_actualizado',
    };

    // Novedades (incluye tus types reales)
    const novedades = {
      'novedad',
      'news',
      'task_news',
      'task_novedad',       // ✅ FIX
      'respuesta_novedad',
      'novedad_creada',
      'novedad_actualizada',
    };

    // Finalización (incluye tus types reales)
    const finalizacion = {
      'finalizacion',
      'completed',
      'task_completed',     // ✅ ya venía en tu firestore
      'finalizado',
      'task_finalizado',
      'task_finalizada',
    };

    if (avances.contains(t)) return 'Avances';
    if (novedades.contains(t)) return 'Novedades';
    if (finalizacion.contains(t)) return 'Finalización';

    return null;
  }

  Future<void> _openNotificationTask({
    required String type,
    required String taskId,
    required String cedula,
  }) async {
    if (taskId.trim().isNotEmpty) {
      try {
        await FirebaseFirestore.instance
            .collection('TBL_TAREAS')
            .doc(taskId)
            .set({'visto': true}, SetOptions(merge: true));
      } catch (_) {}
    }
    final tabKey = _processTabForNotifType(type);

    // ✅ Si es avance/novedad/finalización => ir al historial y abrir proceso en la pestaña correcta
    if (tabKey != null) {
      int tabIndex = 0; // 0 = Asignadas a mí, 1 = Yo asigné

      try {
        final snap = await FirebaseFirestore.instance
            .collection('TBL_TAREAS')
            .doc(taskId)
            .get();

        final data = snap.data();
        if (data != null) {
          final creatorId =
          (data['creador_id'] ?? data['creatorId'] ?? '').toString().trim();
          final assignedId =
          (data['asignado_uid'] ?? data['assignedTo'] ?? '').toString().trim();

          if (creatorId.isNotEmpty && creatorId == cedula) {
            tabIndex = 1; // Yo asigné
          } else if (assignedId.isNotEmpty && assignedId == cedula) {
            tabIndex = 0; // Asignadas a mí
          } else {
            tabIndex = 1; // fallback razonable
          }
        }
      } catch (_) {}

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TaskHistoryScreen(
            currentUserId: cedula,
            initialTabIndex: tabIndex,
            highlightTaskId: taskId,
            openProcessTabKey: tabKey, // 👈 pestaña correcta
          ),
        ),
      );
      return;
    }

    // ✅ Si NO es avance/novedad => comportamiento original (mis tareas asignadas)
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AssignedTasksScreen(
          userId: cedula,
          highlightTaskId: taskId,
        ),
      ),
    );
  }

  Future<String?> _getFcmTokenWithRetries() async {
    Future<String?> _safeGetToken() async {
      try {
        return await FirebaseMessaging.instance.getToken();
      } catch (e) {
        debugPrint('[FCM] getToken error: $e');
        return null;
      }
    }

    var token = await _safeGetToken();
    if (token != null && token.isNotEmpty) return token;

    if (Platform.isIOS) {
      var apnsToken = await FirebaseMessaging.instance.getAPNSToken();
      debugPrint('[FCM] APNS token (retry path): $apnsToken');

      for (final delay in const [
        Duration(milliseconds: 400),
        Duration(seconds: 1),
        Duration(seconds: 2),
      ]) {
        await Future.delayed(delay);
        apnsToken = await FirebaseMessaging.instance.getAPNSToken();
        if (apnsToken == null) continue;

        token = await _safeGetToken();
        if (token != null && token.isNotEmpty) return token;
      }
    }

    return token;
  }

  Future<void> _persistFcmToken({
    required String token,
    required String userId,
  }) async {
    final platform = Platform.operatingSystem;
    final deviceName = Platform.isAndroid
        ? 'Android'
        : Platform.isIOS
        ? 'iOS'
        : platform;
    try {
      final fun = FirebaseFunctions.instance.httpsCallable('registerDeviceToken');
      await fun.call({
        'cedula': userId,
        'token': token,
        'platform': platform,
        'deviceName': deviceName,
      });
    } catch (e) {
      debugPrint('[FCM] registerDeviceToken error: $e');
    }

    try {
      await FirebaseFirestore.instance
          .collection('TBL_USUARIOS')
          .doc(userId)
          .set({
        'fcmTokens': FieldValue.arrayUnion([token]),
        'fcmDevices.$token': {
          'platform': platform,
          'deviceName': deviceName,
          'updatedAt': FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[FCM] write fallback error: $e');
    }
  }

  DateTime? _toDate(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt());
    if (v is String) {
      final n = int.tryParse(v);
      if (n != null) return DateTime.fromMillisecondsSinceEpoch(n);
      final iso = DateTime.tryParse(v);
      if (iso != null) return iso;
    }
    return null;
  }

  bool _isRead(Map<String, dynamic> data) {
    final read = data['read'];
    final leido = data['leido'];
    final visto = data['visto'];
    return (read is bool && read) ||
        (leido is bool && leido) ||
        (visto is bool && visto);
  }

  String _titleOf(Map<String, dynamic> m) =>
      (m['titulo'] ?? m['title'] ?? '(Sin título)').toString();

  DateTime? _dueOf(Map<String, dynamic> m) =>
      _toDate(m['fecha_limite'] ?? m['dueDate']);

  String _estadoOf(Map<String, dynamic> m) => resolveTaskStatus(m);

  String _assignedUidOf(Map<String, dynamic> m) =>
      (m['asignado_uid'] ?? m['assignedTo'] ?? '').toString();

  String _assignedNameOf(Map<String, dynamic> m) =>
      (m['asignado_nombre'] ?? m['assignedToName'] ?? '').toString();

  String _creatorIdOf(Map<String, dynamic> m) =>
      (m['creador_id'] ?? m['creatorId'] ?? m['creador_uid'] ?? '').toString();

  String _creatorNameOf(Map<String, dynamic> m) =>
      (m['creador_nombre'] ?? m['creatorName'] ?? '').toString();

  String _creatorDisplayOf(Map<String, dynamic> m) {
    final name = _creatorNameOf(m).trim();
    if (name.isNotEmpty) return name;
    final id = _creatorIdOf(m).trim();
    return id;
  }

  String _notifFromOf(Map<String, dynamic> n) =>
      (n['fromName'] ?? n['fromId'] ?? '').toString().trim();

  String _notifFromLabel(String type) {
    final t = type.trim().toLowerCase();
    if (t == 'task_assigned' ||
        t == 'task_reassigned' ||
        t == 'task_reassigned_info' ||
        t == 'task_reassigned_out') {
      return 'Asignado por';
    }
    if (t == 'avance' ||
        t == 'progress' ||
        t == 'task_progress' ||
        t == 'task_avance') {
      return 'Reportado por';
    }
    if (t == 'novedad' ||
        t == 'news' ||
        t == 'task_news' ||
        t == 'task_novedad' ||
        t == 'respuesta_novedad') {
      return 'Reportado por';
    }
    return 'De';
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

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
    super.dispose();
  }

  void _startNotifListener(String userId) {
    if (userId.isEmpty) return;
    if (_listeningUserId == userId && _notifSub != null) return;

    _notifSub?.cancel();
    _listeningUserId = userId;
    _seenNotifIds.clear();
    _notifsPrimed = false;

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
        final doc = change.doc;
        if (!_seenNotifIds.add(doc.id)) continue;

        final data = doc.data() ?? {};
        final isRead = (data['read'] as bool?) ?? false;
        if (isRead) continue;

        final title = (data['title'] as String?)?.trim().isNotEmpty == true
            ? data['title'].toString()
            : 'Notificación';
        final body = (data['description'] as String?)?.trim().isNotEmpty == true
            ? data['description'].toString()
            : (data['body']?.toString() ?? '');

        final payload = data['taskId']?.toString();

        await LocalNotificationService.instance.show(
          id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          title: title,
          body: body,
          payload: payload,
        );
      }
    });
  }

  Future<void> _ensureFcmRegistered(String userId) async {
    if (userId.isEmpty) return;

    try {
      await FirebaseMessaging.instance.setAutoInitEnabled(true);
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        announcement: false,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
      );
      debugPrint('[FCM] permiso: ${settings.authorizationStatus}');

      _tokenSub ??=
          FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
            if (newToken.isEmpty) return;
            await _persistFcmToken(token: newToken, userId: userId);
          });

      if (Platform.isIOS) {
        final apnsToken = await FirebaseMessaging.instance.getAPNSToken();
        debugPrint('[FCM] APNS token: $apnsToken');
      }

      final token = await _getFcmTokenWithRetries();
      debugPrint('[FCM] token actual: $token');

      if (token != null && token.isNotEmpty) {
        await _persistFcmToken(token: token, userId: userId);
      }
    } catch (e) {
      debugPrint('[FCM] error general: $e');
    }
  }

  List<Map<String, dynamic>> _getEventsForDay(DateTime day) {
    final key = DateFormat('yyyy-MM-dd').format(day);
    return _events[key] ?? [];
  }

  Future<void> _markAllAsRead({
    required String cedula,
    required List<Map<String, dynamic>> notifications,
  }) async {
    try {
      if (notifications.isEmpty) return;
      final batch = FirebaseFirestore.instance.batch();
      var hasUpdates = false;
      for (final n in notifications) {
        if (_isRead(n)) continue;
        final id = (n['id'] ?? '').toString();
        if (id.isEmpty) continue;
        final ref = FirebaseFirestore.instance
            .collection('TBL_NOTIFICACIONES')
            .doc(cedula)
            .collection('notifications')
            .doc(id);
        batch.set(ref, {'read': true}, SetOptions(merge: true));
        final taskId = (n['taskId'] ?? '').toString();
        if (taskId.isNotEmpty) {
          final taskRef =
          FirebaseFirestore.instance.collection('TBL_TAREAS').doc(taskId);
          batch.set(taskRef, {'visto': true}, SetOptions(merge: true));
        }
        hasUpdates = true;
      }
      if (hasUpdates) {
        await batch.commit();
      }
    } catch (_) {}
  }

  Future<void> _showNotificationsSheet({
    required String cedula,
    required List<Map<String, dynamic>> notifications,
  }) async {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: scheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        minChildSize: 0.45,
        maxChildSize: 0.95,
        builder: (_, controller) {
          if (notifications.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Notificaciones',
                      style: TextStyle(
                          fontFamily: kArial,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  Text('No tienes notificaciones todavía.',
                      style: TextStyle(
                          fontFamily: kArial, color: scheme.onSurfaceVariant)),
                ],
              ),
            );
          }

          return Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.onSurface.withOpacity(.12),
                  borderRadius: BorderRadius.circular(100),
                ),
              ),
              const SizedBox(height: 12),
              const Text('Notificaciones',
                  style: TextStyle(
                      fontFamily: kArial,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.separated(
                  controller: controller,
                  padding:
                  const EdgeInsets.only(left: 16, right: 16, bottom: 24),
                  itemCount: notifications.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final n = notifications[i];
                    final title = (n['title'] ?? '').toString();
                    final body = (n['description'] ?? '').toString();
                    final type = (n['type'] ?? '').toString();
                    final typeLabel = _mapNotificationType(type);
                    final from = _notifFromOf(n);
                    final fromLabel = _notifFromLabel(type);
                    final taskId = (n['taskId'] ?? '').toString();
                    final dt = _toDate(n['createdAt']);
                    final when = dt == null
                        ? ''
                        : DateFormat('dd/MM/yyyy HH:mm', 'es').format(dt);
                    final unread = !_isRead(n);

                    return ListTile(
                      leading: Stack(
                        alignment: Alignment.center,
                        children: [
                          CircleAvatar(
                            backgroundColor: scheme.primary,
                            child: const Icon(Icons.notifications,
                                color: Colors.white),
                          ),
                          if (unread)
                            const Positioned(
                              right: -1,
                              top: -1,
                              child: CircleAvatar(
                                  radius: 6, backgroundColor: Colors.red),
                            ),
                        ],
                      ),
                      title: Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontFamily: kArial)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(body,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontFamily: kArial)),
                          if (from.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              '$fromLabel: $from',
                              style: const TextStyle(
                                fontFamily: kArial,
                                fontSize: 12,
                                color: Colors.black54,
                              ),
                            ),
                          ],
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (typeLabel.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: scheme.primary.withOpacity(.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(typeLabel,
                                      style: TextStyle(
                                        fontFamily: kArial,
                                        color: scheme.primary,
                                        fontWeight: FontWeight.w600,
                                      )),
                                ),
                              if (taskId.isNotEmpty)
                                TextButton.icon(
                                  icon: const Icon(Icons.open_in_new, size: 18),
                                  label: const Text('Ir al detalle'),
                                  style: TextButton.styleFrom(
                                      foregroundColor: scheme.primary),
                                  onPressed: () async {
                                    if (!mounted) return;
                                    Navigator.pop(context);
                                    await _openNotificationTask(
                                      type: type,
                                      taskId: taskId,
                                      cedula: cedula,
                                    );
                                  },
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(when,
                              style: TextStyle(
                                  fontFamily: kArial,
                                  color: scheme.onSurfaceVariant,
                                  fontSize: 12)),
                        ],
                      ),
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: Text(title,
                                style: const TextStyle(fontFamily: kArial)),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (typeLabel.isNotEmpty) ...[
                                  Text('Tipo: $typeLabel',
                                      style: const TextStyle(
                                          fontFamily: kArial,
                                          fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 8),
                                ],
                                Text(body,
                                    style: const TextStyle(fontFamily: kArial)),
                                if (when.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text('Fecha: $when',
                                      style: TextStyle(
                                          fontFamily: kArial,
                                          color: scheme.onSurfaceVariant,
                                          fontSize: 12)),
                                ],
                              ],
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Cerrar'),
                              ),
                              if (taskId.isNotEmpty)
                                TextButton.icon(
                                  icon: const Icon(Icons.arrow_forward),
                                  label: const Text('Ver origen'),
                                  onPressed: () async {
                                    Navigator.pop(context);
                                    await _openNotificationTask(
                                      type: type,
                                      taskId: taskId,
                                      cedula: cedula,
                                    );
                                  },
                                ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );

    await _markAllAsRead(cedula: cedula, notifications: notifications);
  }

  // ============= Apps grid/horizontal =============
  Widget _buildAppsSection({
    required String empresaId,
    required String role,
    required List<String> assignedApps,
    required String cedula,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final assignedLower = assignedApps
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toSet();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('TBL_APPS')
          .where('empresaId', isEqualTo: empresaId)
          .where('enabled', isEqualTo: true)
          .snapshots(),
      builder: (context, appsSnap) {
        if (appsSnap.connectionState == ConnectionState.waiting) {
          return const SizedBox(height: 180, child: SkeletonList(items: 2));
        }
        final docs = appsSnap.data?.docs ?? [];

        final tiles = docs.where((doc) {
          final data = doc.data();
          final appId = (data['appId'] as String?)?.trim() ?? '';
          final appIdLower = appId.toLowerCase();

          final isTH = appIdLower == 'talentohumanodashboard';
          final isAdmin = appIdLower == 'admindashboard';
          final isGerencia = appIdLower == 'gerenciadashboard';
          final isDoc = appIdLower == 'gestiondocumental';
          final isNutricion = appIdLower == 'nutriciondashboard';
          final isCompras = appIdLower == 'comprasdashboard';
          final visibleByRole = role == 'desarrollador';
          final visibleByAssign = assignedLower.contains(appIdLower);
          final visibleDocByAssign = isDoc && visibleByAssign;

          return (isTH && (visibleByRole || visibleByAssign)) ||
              (isAdmin && (visibleByRole || visibleByAssign)) ||
              (isGerencia && (visibleByRole || visibleByAssign)) ||
              (isNutricion && (visibleByRole || visibleByAssign)) ||
              (isCompras && (visibleByRole || visibleByAssign)) ||
              visibleDocByAssign;
        }).map((doc) {
          final data = doc.data();
          final appId = (data['appId'] as String?)?.trim() ?? '';
          final nombre = (data['nombre'] as String?)?.trim() ?? appId;

          Widget icon;
          switch (appId.toLowerCase()) {
            case 'admindashboard':
              icon = const Icon(Icons.admin_panel_settings,
                  size: 32, color: Colors.white);
              break;
            case 'talentohumanodashboard':
              icon =
              const Icon(Icons.group_work, size: 32, color: Colors.white);
              break;
            case 'gerenciadashboard':
              icon = const Icon(Icons.domain, size: 32, color: Colors.white);
              break;
          case 'gestiondocumental':
          icon =
          const Icon(Icons.folder_shared, size: 32, color: Colors.white);
          break;
          case 'nutriciondashboard':
          icon = const Icon(Icons.restaurant_menu,
          size: 32, color: Colors.white);
          break;
          case 'comprasdashboard':
            icon = const Icon(Icons.local_shipping,
                size: 32, color: Colors.white);
            break;
            default:
              icon = const Icon(Icons.apps, size: 32, color: Colors.white);
          }

          return _AppItem(
            nombre: nombre,
            iconBuilder: () => icon,
            onTap: () {
              switch (appId.toLowerCase()) {
                case 'admindashboard':
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => AdminDashboardScreen(userId: cedula)),
                  );
                  break;
                case 'talentohumanodashboard':
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) =>
                            TalentoHumanoDashboardScreen(userId: cedula)),
                  );
                  break;
                case 'gerenciadashboard':
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) =>
                            GerenciaDashboardScreen(userId: cedula)),
                  );
                  break;
                case 'gestiondocumental':
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          DocumentManagementScreen(currentUserId: cedula),
                    ),
                  );
                  break;
                case 'nutriciondashboard':
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => NutricionDashboardScreen(
                        userId: cedula,
                        empresaId: empresaId,
                      ),
                    ),
                  );
                  break;
                case 'comprasdashboard':
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ComprasDashboardScreen(
                        userId: cedula,
                        empresaId: empresaId,
                      ),
                    ),
                  );
                  break;
                default:
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Abrir $nombre')));
              }
            },
          );
        }).toList();

        if (tiles.isEmpty) {
          return Text(
            'No tienes apps disponibles.',
            style: TextStyle(
                fontFamily: kArial,
                fontSize: 16,
                color: scheme.onSurfaceVariant),
          );
        }

        Widget buildTile(_AppItem a) => GestureDetector(
          onTap: a.onTap,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: scheme.primary,
                child: a.iconBuilder(),
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: 120,
                child: Text(
                  a.nombre,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: kArial, fontSize: 14),
                ),
              ),
            ],
          ),
        );

        if (tiles.length == 1) {
          return Center(child: buildTile(tiles.first));
        }

        return SizedBox(
          height: 120,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: tiles.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) => buildTile(tiles[i]),
          ),
        );
      },
    );
  }

  String _mapNotificationType(String raw) {
    final type = raw.trim().toLowerCase();
    if (type.startsWith('task_status_')) {
      final status = type.replaceFirst('task_status_', '').replaceAll('_', ' ').trim();
      if (status.isEmpty) return '';
      return status[0].toUpperCase() + status.substring(1);
    }
    switch (type) {
      case 'avance':
      case 'progress':
      case 'task_progress':
      case 'task_avance': // ✅ FIX
        return 'Avance';

      case 'novedad':
      case 'news':
      case 'task_news':
      case 'task_novedad': // ✅ FIX
      case 'respuesta_novedad':
        return 'Novedad';

      case 'task_assigned':
        return 'Tarea asignada';
      case 'task_reassigned':
        return 'Tarea reasignada';

      case 'completed':
      case 'task_completed':
      case 'task_finalizada':
      case 'task_finalizado':
        return 'Tarea finalizada';

      case 'cita_nutricion_agendada':
        return 'Cita nutricional agendada';
      case 'cita_nutricion_recordatorio':
        return 'Recordatorio nutricional';

      default:
        return type.isEmpty ? '' : raw;
    }
  }

  // ====== Slider "Tareas del día" ======
  Widget _buildTodayTasksSlider({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> assignedToMe,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> iCreated,
    required String myId,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = DateTime(now.year, now.month, now.day, 23, 59, 59);

    final cards = <Map<String, dynamic>>[];

    for (final d in assignedToMe) {
      final m = d.data();
      final due = _dueOf(m);
      if (due == null) continue;
      if (due.isBefore(start) || due.isAfter(end)) continue;
      cards.add({
        'type': 'yo',
        'title': _titleOf(m),
        'due': due,
        'to': _creatorDisplayOf(m),
        'estado': _estadoOf(m),
      });
    }

    for (final d in iCreated) {
      final m = d.data();
      final due = _dueOf(m);
      if (due == null) continue;
      if (due.isBefore(start) || due.isAfter(end)) continue;
      cards.add({
        'type': 'otros',
        'title': _titleOf(m),
        'due': due,
        'from': _assignedNameOf(m),
        'estado': _estadoOf(m),
      });
    }

    if (cards.isEmpty) {
      return SizedBox(
        height: 168,
        child: EmptyStateWidget(
          icon: Icons.event_available,
          title: 'No hay tareas para hoy',
          message: 'Cuando tengas actividades del día las verás aquí.',
          actionLabel: 'Ver asignadas',
          compact: true,
          onAction: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AssignedTasksScreen(userId: myId),
              ),
            );
          },
        ),
      );
    }

    cards.sort((a, b) => (a['due'] as DateTime).compareTo(b['due'] as DateTime));

    return SizedBox(
      height: 190,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: cards.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) {
          final c = cards[i];
          final due = c['due'] as DateTime;
          final type = c['type'] as String;
          final estado = (c['estado'] as String?) ?? '';

          final bool yoEntrego = type == 'yo';
          final Color bg =
          yoEntrego ? scheme.primaryContainer : scheme.tertiaryContainer;
          final Color fg =
          yoEntrego ? scheme.onPrimaryContainer : scheme.onTertiaryContainer;
          final IconData ico = yoEntrego ? Icons.upload : Icons.download;

          return Container(
            width: 280,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: fg.withOpacity(.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(ico, size: 18, color: fg),
                    const SizedBox(width: 6),
                    Text(
                      yoEntrego ? 'Yo entrego' : 'Me entregan',
                      style: TextStyle(
                        color: fg,
                        fontFamily: kArial,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                    const Spacer(),
                    _chipEstado(estado, scheme),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  (c['title'] as String?) ?? '(Sin título)',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: kArial,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _pill('Vence: ${DateFormat('HH:mm').format(due)}', scheme),
                    if (yoEntrego && (c['to'] ?? '').toString().isNotEmpty)
                      _pill('Para: ${c['to']}', scheme),
                    if (!yoEntrego && (c['from'] ?? '').toString().isNotEmpty)
                      _pill('Entrega: ${c['from']}', scheme),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _pill(String text, ColorScheme scheme) => Chip(
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    visualDensity: const VisualDensity(horizontal: -3, vertical: -3),
    labelPadding: const EdgeInsets.symmetric(horizontal: 6),
    label: Text(text,
        style: const TextStyle(fontFamily: kArial, fontSize: 11)),
    backgroundColor: scheme.surface,
    side: BorderSide(color: scheme.outlineVariant),
  );

  Widget _chipEstado(String estado, ColorScheme scheme) {
    Color color;
    switch (estado) {
      case 'en_progreso':
        color = Colors.blue.shade700;
        break;
      case 'por_aprobar':
        color = Colors.orange.shade700;
        break;
      case 'finalizado':
        color = Colors.green.shade700;
        break;
      case 'retrasada':
        color = Colors.red.shade700;
        break;
      default:
        color = scheme.outline;
    }
    return Chip(
      labelPadding: const EdgeInsets.symmetric(horizontal: 6),
      visualDensity: const VisualDensity(horizontal: -3, vertical: -3),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      label: Text(estado.isEmpty ? '—' : estado,
          style: const TextStyle(
              color: Colors.white, fontFamily: kArial, fontSize: 11)),
      backgroundColor: color,
    );
  }


  Color _calendarMarkerColor(List<Map<String, dynamic>> events) {
    if (events.any((e) => (e['estado'] ?? '') == 'cita_nutricion')) {
      return Colors.teal.shade600;
    }
    if (events.any((e) => (e['estado'] ?? '') == 'retrasada')) {
      return Colors.red.shade600;
    }
    if (events.any((e) => (e['estado'] ?? '') == 'en_progreso')) {
      return Colors.blue.shade600;
    }
    if (events.any((e) => (e['estado'] ?? '') == 'por_aprobar')) {
      return Colors.orange.shade700;
    }
    return Colors.green.shade600;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final empresaState = EmpresaScope.of(context);
    final selectedEmpresaId = empresaState.selectedEmpresaId?.trim();
    final empresaId = (selectedEmpresaId != null && selectedEmpresaId.isNotEmpty)
        ? selectedEmpresaId
        : widget.empresaId.trim();

    if ((selectedEmpresaId == null || selectedEmpresaId.isEmpty) &&
        widget.empresaId.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        empresaState.setSelectedEmpresaId(widget.empresaId);
      });
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('TBL_USUARIOS')
          .doc(widget.username)
          .snapshots(),
      builder: (context, userSnap) {
        if (userSnap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: SkeletonList(items: 4));
        }
        if (!userSnap.hasData || !userSnap.data!.exists) {
          return Scaffold(
            appBar: AppBar(
              backgroundColor: scheme.primary,
              foregroundColor: scheme.onPrimary,
              title: const Text('Usuario no encontrado',
                  style: TextStyle(fontFamily: kArial)),
            ),
            body: const Center(
              child: Text(
                'Error al cargar usuario.\nPor favor, vuelve a iniciar sesión.',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: kArial, fontSize: 16),
              ),
            ),
          );
        }

        final userData = userSnap.data!.data()!;
        final cedula = (userData['cedula'] as String?)?.trim() ?? '';
        final effectiveId = cedula.isNotEmpty ? cedula : widget.username.trim();
        final pNombre = (userData['nombres'] as String?) ??
            (userData['primerNombre'] as String? ?? '');
        final pApellido = (userData['apellidos'] as String?) ??
            (userData['primerApellido'] as String? ?? '');
        final role =
            (userData['role'] as String?)?.trim().toLowerCase() ?? 'usuario';
        final assignedApps = (userData['apps'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
            <String>[];
        final saludo = '$pNombre${(pApellido.isNotEmpty ? ' $pApellido' : '')}';

        _startNotifListener(effectiveId);

        if (!_didRegisterToken && effectiveId.isNotEmpty) {
          _didRegisterToken = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _ensureFcmRegistered(effectiveId);
          });
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('TBL_NOTIFICACIONES')
              .doc(effectiveId)
              .collection('notifications')
              .orderBy('createdAt', descending: true)
              .snapshots(),
          builder: (context, notifSnap) {
            if (notifSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(body: SkeletonList(items: 4));
            }

            final List<Map<String, dynamic>> notifications = [];
            if (notifSnap.hasData) {
              for (final doc in notifSnap.data!.docs) {
                notifications.add({
                  ...doc.data(),
                  'id': doc.id,
                });
              }
            }
            notifications.sort((a, b) {
              final ad = _toDate(a['createdAt']) ??
                  DateTime.fromMillisecondsSinceEpoch(0);
              final bd = _toDate(b['createdAt']) ??
                  DateTime.fromMillisecondsSinceEpoch(0);
              return bd.compareTo(ad);
            });
            final unreadCount = notifications.where((n) => !_isRead(n)).length;

            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('TBL_TAREAS')
                  .where('asignado_uid', isEqualTo: effectiveId)
                  .where('empresaId', isEqualTo: empresaId)
                  .snapshots(),
              builder: (context, assignedSnap) {
                if (assignedSnap.connectionState == ConnectionState.waiting) {
                  return const Scaffold(body: SkeletonList(items: 4));
                }
                final assignedDocs = assignedSnap.data?.docs ?? [];

                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('TBL_TAREAS')
                      .where('creador_id', isEqualTo: effectiveId)
                      .where('empresaId', isEqualTo: empresaId)
                      .snapshots(),
                  builder: (context, createdSnap) {
                    if (createdSnap.connectionState == ConnectionState.waiting) {
                      return const Scaffold(body: SkeletonList(items: 4));
                    }
                    final createdDocs = createdSnap.data?.docs ?? [];

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance
        .collection('TBL_CITAS_NUTRICION')
        .where('userId', isEqualTo: effectiveId)
        .where('empresaId', isEqualTo: empresaId)
        .where('estado', isEqualTo: 'agendada')
        .snapshots(),
    builder: (context, citasSnap) {
    if (citasSnap.connectionState == ConnectionState.waiting) {
    return const Scaffold(body: SkeletonList(items: 4));
    }

    final map = <String, List<Map<String, dynamic>>>{};
    void addEvt(DateTime d, String title, String desc, String estado) {
    final k = DateFormat('yyyy-MM-dd').format(d);
    (map[k] ??= []).add({
    'title': title,
    'description': desc,
    'estado': estado,
    });
    }

    for (final d in assignedDocs) {
    final m = d.data();
    final due = _dueOf(m);
    if (due != null) {
    addEvt(
    due,
    _titleOf(m),
    'Yo entrego \u2022 Para: ${_creatorDisplayOf(m).isNotEmpty ? _creatorDisplayOf(m) : "\u2014"}',
    _estadoOf(m),
    );
    }
    }
    for (final d in createdDocs) {
    final m = d.data();
    final due = _dueOf(m);
    if (due != null) {
    addEvt(
    due,
    _titleOf(m),
    'Me entregan \u2022 Entrega: ${_assignedNameOf(m).isNotEmpty ? _assignedNameOf(m) : "\u2014"}',
    _estadoOf(m),
    );
    }
    }
    for (final doc in citasSnap.data?.docs ?? const []) {
    final data = doc.data();
    final ts = data['fechaReevaluacion'];
    final fecha = ts is Timestamp ? ts.toDate() : null;
    if (fecha == null) continue;

    final paciente = (data['pacienteNombre'] ?? '').toString();
    final dieta = (data['tipoDieta'] ?? '').toString();
    addEvt(
    fecha,
    'Reevaluaci\u00f3n: $paciente',
    dieta.isNotEmpty
    ? 'Cita nutricional \u2022 Dieta: $dieta'
        : 'Cita de reevaluaci\u00f3n nutricional',
    'cita_nutricion',
    );
    }

    _events = map;

    return Scaffold(
                      drawer: AppDrawer(userId: effectiveId),
                      appBar: AppBar(
                        backgroundColor: scheme.primary,
                        foregroundColor: scheme.onPrimary,
                        leading: Builder(
                          builder: (ctx) => IconButton(
                            icon: const Icon(Icons.menu),
                            onPressed: () => Scaffold.of(ctx).openDrawer(),
                          ),
                        ),
                        title: Text('Bienvenido, $saludo',
                            style: const TextStyle(
                                fontFamily: kArial,
                                fontSize: 20,
                                fontWeight: FontWeight.w600)),
                        centerTitle: true,
                        actions: [
                          IconButton(
                            tooltip: 'Notificaciones',
                            onPressed: () => _showNotificationsSheet(
                              cedula: effectiveId,
                              notifications: notifications,
                            ),
                            icon: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                const Icon(Icons.notifications_none),
                                if (unreadCount > 0)
                                  Positioned(
                                    right: -2,
                                    top: -2,
                                    child: AnimatedSwitcher(
                                      duration: const Duration(milliseconds: 260),
                                      transitionBuilder: (child, animation) => ScaleTransition(
                                        scale: CurvedAnimation(
                                          parent: animation,
                                          curve: Curves.easeOutBack,
                                        ),
                                        child: FadeTransition(opacity: animation, child: child),
                                      ),
                                      child: Container(
                                        key: ValueKey<int>(unreadCount),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 5, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: Colors.red,
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        constraints: const BoxConstraints(
                                            minWidth: 18, minHeight: 16),
                                        child: Text(
                                          unreadCount > 9 ? '9+' : '$unreadCount',
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                      ),
                      body: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Mis Apps',
                                style: TextStyle(
                                    fontFamily: kArial,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            _buildAppsSection(
                              empresaId: empresaId,
                              role: role,
                              assignedApps: assignedApps,
                              cedula: effectiveId,
                            ),
                            const SizedBox(height: 24),
                            const Text('Tareas del día',
                                style: TextStyle(
                                    fontFamily: kArial,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            _buildTodayTasksSlider(
                              assignedToMe: assignedDocs,
                              iCreated: createdDocs,
                              myId: effectiveId,
                            ),
                            const SizedBox(height: 24),
                            const Text('Calendario',
                                style: TextStyle(
                                    fontFamily: kArial,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            TableCalendar(
                              locale: 'es_CO',
                              startingDayOfWeek: StartingDayOfWeek.monday,
                              firstDay: DateTime(2000),
                              lastDay: DateTime.now().add(const Duration(days: 365)),
                              focusedDay: _focusedDay,
                              selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                              onDaySelected: (selected, focused) {
                                setState(() {
                                  _selectedDay = selected;
                                  _focusedDay = focused;
                                });
                              },
                              eventLoader: _getEventsForDay,
                              calendarStyle: CalendarStyle(
                                markersMaxCount: 4,
                                markerDecoration: BoxDecoration(
                                  color: scheme.primary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              calendarBuilders: CalendarBuilders(
                                markerBuilder: (context, day, events) {
                                  if (events.isEmpty) return const SizedBox.shrink();
                                  final raw = events.cast<Map<String, dynamic>>();
                                  final color = _calendarMarkerColor(raw);
                                  return Positioned(
                                    bottom: 2,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: color,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        '${events.length}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Actividades (${DateFormat('dd/MM/yyyy', 'es').format(_selectedDay)})',
                              style: const TextStyle(
                                  fontFamily: kArial,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 8),
                            if (_getEventsForDay(_selectedDay).isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                child: Text(
                                  'No hay actividades para este día.',
                                  style: TextStyle(fontFamily: kArial, color: Colors.black54),
                                ),
                              )
                            else
                              ..._getEventsForDay(_selectedDay).map(
                                    (evt) => ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(Icons.event, color: scheme.primary),
                                  title: Text(evt['title'] as String? ?? '',
                                      style: const TextStyle(fontFamily: kArial)),
                                  subtitle: Text(evt['description'] as String? ?? '',
                                      style: const TextStyle(fontFamily: kArial)),
                                ),
                              ),
                          ],
                        ),
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
      },
    );
  }
}

class _AppItem {
  final String nombre;
  final Widget Function() iconBuilder;
  final VoidCallback onTap;
  const _AppItem({
    required this.nombre,
    required this.iconBuilder,
    required this.onTap,
  });
}
