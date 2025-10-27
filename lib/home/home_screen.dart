// lib/home/home_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_functions/cloud_functions.dart';

// Import relativo al Admin Dashboard
import '../admin/admin_dashboard_screen.dart';
// Import relativo al Talento Humano Dashboard
import '../talento_humano/talento_humano_dashboard_screen.dart';
// Drawer modularizado
import 'app_drawer.dart';

const Color kMarronOscuro = Color(0xffc28942);
const Color kMarronClaro  = Color(0xffe19e4c);
const Color kGris         = Color(0xff8a8a8a);
const String kArial       = 'Arial';

class HomeScreen extends StatefulWidget {
  final String username; // cédula o username (docId en TBL_USUARIOS)
  const HomeScreen({Key? key, required this.username}) : super(key: key);

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

  // Helpers de campos (alias tolerantes)
  String _titleOf(Map<String, dynamic> m) =>
      (m['titulo'] ?? m['title'] ?? '(Sin título)').toString();

  DateTime? _dueOf(Map<String, dynamic> m) =>
      _toDate(m['fecha_limite'] ?? m['dueDate']);

  String _estadoOf(Map<String, dynamic> m) =>
      (m['estado'] ?? m['status'] ?? '').toString();

  String _assignedUidOf(Map<String, dynamic> m) =>
      (m['asignado_uid'] ?? m['assignedTo'] ?? '').toString();

  String _assignedNameOf(Map<String, dynamic> m) =>
      (m['asignado_nombre'] ?? m['assignedToName'] ?? '').toString();

  String _creatorIdOf(Map<String, dynamic> m) =>
      (m['creador_id'] ?? m['creatorId'] ?? '').toString();

  String _creatorNameOf(Map<String, dynamic> m) =>
      (m['creador_nombre'] ?? m['creatorName'] ?? '').toString();

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  void initState() {
    super.initState();
    _focusedDay  = DateTime.now();
    _selectedDay = DateTime.now();
  }

  @override
  void dispose() {
    _tokenSub?.cancel();
    super.dispose();
  }

  // ========= Registro automático de FCM =========
  Future<void> _ensureFcmRegistered(String userId) async {
    if (userId.isEmpty) return;

    try {
      await FirebaseMessaging.instance.setAutoInitEnabled(true);
      await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
        alert: true, badge: true, sound: true,
      );
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true, badge: true, sound: true,
        announcement: false, carPlay: false, criticalAlert: false, provisional: false,
      );
      debugPrint('[FCM] permiso: ${settings.authorizationStatus}');

      // Token actual
      final token = await FirebaseMessaging.instance.getToken();
      debugPrint('[FCM] token actual: $token');

      if (token != null && token.isNotEmpty) {
        // 1) Backend (limpia tokens inválidos)
        try {
          final fun = FirebaseFunctions.instance.httpsCallable('registerDeviceToken');
          await fun.call({'cedula': userId, 'token': token});
        } catch (e) {
          debugPrint('[FCM] registerDeviceToken error: $e');
        }

        // 2) Respaldo directo (por si el callable falló por permisos/App Check)
        try {
          await FirebaseFirestore.instance
              .collection('TBL_USUARIOS')
              .doc(userId)
              .set({'fcmTokens': FieldValue.arrayUnion([token])}, SetOptions(merge: true));
        } catch (e) {
          debugPrint('[FCM] write fallback error: $e');
        }
      }

      // Guarda cada refresh del token también en ambos lados
      _tokenSub ??= FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
        debugPrint('[FCM] onTokenRefresh: $newToken');
        if (newToken.isEmpty) return;

        try {
          final fun = FirebaseFunctions.instance.httpsCallable('registerDeviceToken');
          await fun.call({'cedula': userId, 'token': newToken});
        } catch (_) {}
        try {
          await FirebaseFirestore.instance
              .collection('TBL_USUARIOS')
              .doc(userId)
              .set({'fcmTokens': FieldValue.arrayUnion([newToken])}, SetOptions(merge: true));
        } catch (_) {}
      });
    } catch (e) {
      debugPrint('[FCM] error general: $e');
    }
  }

  // ========= Calendario / Eventos =========

  List<Map<String, dynamic>> _getEventsForDay(DateTime day) {
    final key = DateFormat('yyyy-MM-dd').format(day);
    return _events[key] ?? [];
  }

  // ========= Campana / Notificaciones =========

  Future<void> _markAllAsRead({
    required String cedula,
    required List<Map<String, dynamic>> notifications,
  }) async {
    try {
      final upd = notifications.map((n) => {...n, 'read': true}).toList();
      await FirebaseFirestore.instance
          .collection('TBL_NOTIFICACIONES')
          .doc(cedula)
          .set({'notifications': upd}, SetOptions(merge: true));
    } catch (_) {
      // no-op
    }
  }

  Future<void> _showNotificationsSheet({
    required String cedula,
    required List<Map<String, dynamic>> notifications,
  }) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
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
                children: const [
                  Text('Notificaciones',
                      style: TextStyle(
                          fontFamily: kArial,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                  SizedBox(height: 16),
                  Text('No tienes notificaciones todavía.',
                      style: TextStyle(fontFamily: kArial, color: kGris)),
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
                  color: Colors.black12,
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
                  padding: const EdgeInsets.only(left: 16, right: 16, bottom: 24),
                  itemCount: notifications.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final n     = notifications[i];
                    final title = (n['title'] ?? '') as String;
                    final body  = (n['description'] ?? '') as String;

                    final dt   = _toDate(n['createdAt']);
                    final when = dt == null ? '' : DateFormat('dd/MM/yyyy HH:mm').format(dt);

                    final unread = !(n['read'] as bool? ?? false);

                    return ListTile(
                      dense: false,
                      leading: Stack(
                        alignment: Alignment.center,
                        children: [
                          const CircleAvatar(
                            backgroundColor: kMarronClaro,
                            child: Icon(Icons.notifications, color: Colors.white),
                          ),
                          if (unread)
                            const Positioned(
                              right: -1,
                              top: -1,
                              child: CircleAvatar(
                                radius: 6,
                                backgroundColor: Colors.red,
                              ),
                            ),
                        ],
                      ),
                      title: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontFamily: kArial),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            body,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontFamily: kArial),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            when,
                            style: const TextStyle(
                                fontFamily: kArial, color: kGris, fontSize: 12),
                          ),
                        ],
                      ),
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: Text(title,
                                style: const TextStyle(fontFamily: kArial)),
                            content: Text(body,
                                style: const TextStyle(fontFamily: kArial)),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Cerrar'),
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

    // Al cerrar el modal, marcamos todas como leídas.
    await _markAllAsRead(cedula: cedula, notifications: notifications);
  }

  // ============= Apps grid/horizontal =============
  Widget _buildAppsSection({
    required String empresaId,
    required String role,
    required List<String> assignedApps,
    required String cedula,
  }) {
    final assignedLower =
    assignedApps.map((e) => e.trim().toLowerCase()).where((e) => e.isNotEmpty).toSet();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('TBL_APPS')
          .where('empresaId', isEqualTo: empresaId)
          .where('enabled', isEqualTo: true)
          .snapshots(),
      builder: (context, appsSnap) {
        if (appsSnap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = appsSnap.data?.docs ?? [];

        final tiles = docs.where((doc) {
          final data = doc.data();
          final appId = (data['appId'] as String?)?.trim() ?? '';
          final appIdLower = appId.toLowerCase();

          final isTH = appIdLower == 'talentohumanodashboard';
          final isAdmin = appIdLower == 'admindashboard';
          final visibleByRole = role == 'desarrollador';
          final visibleByAssign = assignedLower.contains(appIdLower);

          return (isTH && (visibleByRole || visibleByAssign)) ||
              (isAdmin && (visibleByRole || visibleByAssign));
        }).map((doc) {
          final data = doc.data();
          final appId = (data['appId'] as String?)?.trim() ?? '';
          final nombre = (data['nombre'] as String?)?.trim() ?? appId;

          Icon icon;
          switch (appId.toLowerCase()) {
            case 'admindashboard':
              icon = const Icon(Icons.admin_panel_settings, size: 32, color: Colors.white);
              break;
            case 'talentohumanodashboard':
              icon = const Icon(Icons.group_work, size: 32, color: Colors.white);
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
                    MaterialPageRoute(builder: (_) => AdminDashboardScreen(userId: cedula)),
                  );
                  break;
                case 'talentohumanodashboard':
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => TalentoHumanoDashboardScreen(userId: cedula)),
                  );
                  break;
                default:
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text('Abrir $nombre')));
              }
            },
          );
        }).toList();

        if (tiles.isEmpty) {
          return const Center(
            child: Text(
              'No tienes apps disponibles.',
              style: TextStyle(fontFamily: kArial, fontSize: 16, color: kGris),
            ),
          );
        }

        return SizedBox(
          height: 100,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: tiles.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) {
              final a = tiles[i];
              return GestureDetector(
                onTap: a.onTap,
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: kMarronClaro,
                      child: a.iconBuilder(),
                    ),
                    const SizedBox(height: 6),
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
            },
          ),
        );
      },
    );
  }

  // ====== Slider "Tareas del día" ======
  Widget _buildTodayTasksSlider({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> assignedToMe,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> iCreated,
    required String myId,
  }) {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end   = DateTime(now.year, now.month, now.day, 23, 59, 59);

    final cards = <Map<String, dynamic>>[];

    // Yo debo entregar (asignado_uid == myId)
    for (final d in assignedToMe) {
      final m = d.data();
      final due = _dueOf(m);
      if (due == null) continue;
      if (due.isBefore(start) || due.isAfter(end)) continue;
      cards.add({
        'type'      : 'yo',
        'title'     : _titleOf(m),
        'due'       : due,
        'to'        : _creatorNameOf(m),
        'estado'    : _estadoOf(m),
      });
    }

    // Me deben entregar (creador_id == myId)
    for (final d in iCreated) {
      final m = d.data();
      final due = _dueOf(m);
      if (due == null) continue;
      if (due.isBefore(start) || due.isAfter(end)) continue;
      cards.add({
        'type'      : 'otros',
        'title'     : _titleOf(m),
        'due'       : due,
        'from'      : _assignedNameOf(m),
        'estado'    : _estadoOf(m),
      });
    }

    if (cards.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text('No hay tareas para hoy.',
            style: TextStyle(fontFamily: kArial, fontSize: 16)),
      );
    }

    // Orden por hora de vencimiento
    cards.sort((a, b) => (a['due'] as DateTime).compareTo(b['due'] as DateTime));

    return SizedBox(
      height: 150,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: cards.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) {
          final c = cards[i];
          final due = c['due'] as DateTime;
          final type = c['type'] as String;
          final estado = (c['estado'] as String?) ?? '';
          final badge = type == 'yo'
              ? const _Badge(text: 'Yo entrego',  color: Color(0xff1565c0))
              : _Badge(text: 'Me entregan${(c['from'] ?? '') != '' ? '' : ''}', color: Color(0xff00897b));

          return Container(
            width: 260,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: kMarronClaro.withOpacity(0.18),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                badge,
                const SizedBox(height: 6),
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
                    _pill('Vence: ${DateFormat('HH:mm').format(due)}'),
                    if (type == 'yo' && (c['to'] ?? '').toString().isNotEmpty)
                      _pill('Para: ${c['to']}'),
                    if (type != 'yo' && (c['from'] ?? '').toString().isNotEmpty)
                      _pill('Entrega: ${c['from']}'),
                    if (estado.isNotEmpty) _chipEstado(estado),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Chip _chipEstado(String estado) => Chip(
    labelPadding: const EdgeInsets.symmetric(horizontal: 6),
    visualDensity: const VisualDensity(horizontal: -3, vertical: -3),
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    label: Text(
      estado,
      style: const TextStyle(color: Colors.white, fontFamily: kArial, fontSize: 11),
    ),
    backgroundColor: _statusColor(estado),
  );

  Color _statusColor(String s) {
    switch (s) {
      case 'pendiente':
        return Colors.orange.shade700;
      case 'en_progreso':
        return Colors.blue.shade700;
      case 'completada':
        return Colors.green.shade700;
      case 'devuelta':
        return Colors.purple.shade700;
      default:
        return Colors.grey.shade600;
    }
  }

  Widget _pill(String text) => Chip(
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    visualDensity: const VisualDensity(horizontal: -3, vertical: -3),
    labelPadding: const EdgeInsets.symmetric(horizontal: 6),
    label: Text(text, style: const TextStyle(fontFamily: kArial, fontSize: 11)),
    backgroundColor: Colors.white,
    side: const BorderSide(color: Colors.black12),
  );

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('TBL_USUARIOS')
          .doc(widget.username)
          .snapshots(),
      builder: (context, userSnap) {
        if (userSnap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (!userSnap.hasData || !userSnap.data!.exists) {
          return Scaffold(
            appBar: AppBar(
              backgroundColor: kMarronOscuro,
              title: const Text('Usuario no encontrado', style: TextStyle(fontFamily: kArial)),
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

        final userData  = userSnap.data!.data()!;
        final cedula = (userData['cedula'] as String?)?.trim() ?? '';
        final effectiveId = cedula.isNotEmpty ? cedula : widget.username.trim();
        final pNombre   = (userData['nombres'] as String?) ?? (userData['primerNombre'] as String? ?? '');
        final pApellido = (userData['apellidos'] as String?) ?? (userData['primerApellido'] as String? ?? '');
        final role      = (userData['role'] as String?)?.trim().toLowerCase() ?? 'usuario';
        final assignedApps =
            (userData['apps'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? <String>[];
        final empresaId = (userData['empresaId'] as String?)?.trim() ?? '';
        final saludo    = '$pNombre${(pApellido.isNotEmpty ? ' $pApellido' : '')}';

        // 🔔 Registrar FCM automáticamente (una sola vez)
        if (!_didRegisterToken && effectiveId.isNotEmpty) {
          _didRegisterToken = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _ensureFcmRegistered(effectiveId); // usa el ID efectivo
          });
        }

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('TBL_NOTIFICACIONES')
              .doc(effectiveId)
              .snapshots(),
          builder: (context, notifSnap) {
            if (notifSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }

            // ----- Parseo notificaciones (solo para campana; el calendario ahora usa TAREAS) -----
            final List<Map<String, dynamic>> notifications = [];
            if (notifSnap.hasData && notifSnap.data!.exists) {
              final raw = notifSnap.data!.data()!['notifications'] as List<dynamic>? ?? [];
              for (final item in raw) {
                if (item is Map<String, dynamic>) notifications.add(item);
              }
            }
            notifications.sort((a, b) {
              final ad = _toDate(a['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0);
              final bd = _toDate(b['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0);
              return bd.compareTo(ad);
            });
            final unreadCount = notifications.where((n) => !(n['read'] as bool? ?? false)).length;

            // ======= Streams de tareas: (1) asignadas a mí, (2) yo asigné =======
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('TBL_TAREAS')
                  .where('asignado_uid', isEqualTo: effectiveId) // alias: assignedTo
                  .snapshots(),
              builder: (context, assignedSnap) {
                if (assignedSnap.connectionState == ConnectionState.waiting) {
                  return const Scaffold(body: Center(child: CircularProgressIndicator()));
                }
                final assignedDocs = assignedSnap.data?.docs ?? [];

                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('TBL_TAREAS')
                      .where('creador_id', isEqualTo: effectiveId) // alias: creatorId
                      .snapshots(),
                  builder: (context, createdSnap) {
                    if (createdSnap.connectionState == ConnectionState.waiting) {
                      return const Scaffold(body: Center(child: CircularProgressIndicator()));
                    }
                    final createdDocs = createdSnap.data?.docs ?? [];

                    // Construir el mapa de eventos del calendario desde tareas (ambos tipos)
                    final map = <String, List<Map<String, dynamic>>>{};
                    void addEvt(DateTime d, String title, String desc) {
                      final k = DateFormat('yyyy-MM-dd').format(d);
                      (map[k] ??= []).add({'title': title, 'description': desc});
                    }

                    for (final d in assignedDocs) {
                      final m = d.data();
                      final due = _dueOf(m);
                      if (due != null) {
                        addEvt(
                          due,
                          _titleOf(m),
                          'Yo entrego • Para: ${_creatorNameOf(m).isNotEmpty ? _creatorNameOf(m) : "—"}',
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
                          'Me entregan • Entrega: ${_assignedNameOf(m).isNotEmpty ? _assignedNameOf(m) : "—"}',
                        );
                      }
                    }
                    // Asignamos al estado (el builder ya va a reconstruir)
                    _events = map;

                    return Scaffold(
                      drawer: AppDrawer(userId: effectiveId),
                      appBar: AppBar(
                        backgroundColor: kMarronOscuro,
                        leading: Builder(
                          builder: (ctx) => IconButton(
                            icon: const Icon(Icons.menu),
                            onPressed: () => Scaffold.of(ctx).openDrawer(),
                          ),
                        ),
                        title: Text('Bienvenido, $saludo',
                            style: const TextStyle(
                                fontFamily: kArial, fontSize: 20, fontWeight: FontWeight.w600)),
                        centerTitle: true,
                        actions: [
                          // ============ Campana con badge ============
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
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: Colors.red,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      constraints: const BoxConstraints(minWidth: 18, minHeight: 16),
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
                                    fontFamily: kArial, fontSize: 18, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            _buildAppsSection(
                              empresaId: empresaId,
                              role: role,
                              assignedApps: assignedApps,
                              cedula: effectiveId,
                            ),
                            const SizedBox(height: 24),

                            // ======= NUEVO: Tareas del día (slider) =======
                            const Text('Tareas del día',
                                style: TextStyle(
                                    fontFamily: kArial, fontSize: 18, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            _buildTodayTasksSlider(
                              assignedToMe: assignedDocs,
                              iCreated: createdDocs,
                              myId: effectiveId,
                            ),
                            const SizedBox(height: 24),

                            // ======= Calendario (eventos a partir de tareas) =======
                            ExpansionTile(
                              tilePadding: EdgeInsets.zero,
                              childrenPadding: const EdgeInsets.only(top: 8),
                              title: const Text('Calendario',
                                  style: TextStyle(
                                      fontFamily: kArial,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold)),
                              children: [
                                TableCalendar(
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
                                  calendarStyle: const CalendarStyle(
                                    markersMaxCount: 1,
                                    markerDecoration: BoxDecoration(
                                      color: kMarronOscuro,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Actividades (${DateFormat('dd/MM/yyyy').format(_selectedDay)})',
                                  style: const TextStyle(
                                      fontFamily: kArial,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 8),
                                if (_getEventsForDay(_selectedDay).isEmpty)
                                  const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 8),
                                    child: Text('No tienes actividades para esta fecha.',
                                        style: TextStyle(
                                            fontFamily: kArial, fontSize: 14, color: kGris)),
                                  )
                                else
                                  ..._getEventsForDay(_selectedDay).map(
                                        (evt) => ListTile(
                                      dense: true,
                                      contentPadding: EdgeInsets.zero,
                                      leading: const Icon(Icons.event, color: kMarronOscuro),
                                      title: Text(evt['title'] as String? ?? '',
                                          style: const TextStyle(fontFamily: kArial)),
                                      subtitle: Text(evt['description'] as String? ?? '',
                                          style: const TextStyle(fontFamily: kArial)),
                                    ),
                                  ),
                              ],
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
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;
  const _Badge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontFamily: kArial,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
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
