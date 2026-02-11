// lib/home/notifications_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:todo/theme/app_typography.dart';
import 'package:intl/intl.dart';

import 'assigned_tasks_screen.dart';
import 'task_history_screen.dart' hide kArial;

const String _notifsRoot = 'TBL_NOTIFICACIONES';
const Color kMarronOscuro = Color(0xFF145DA0);

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

  const avances = {
    'avance',
    'progress',
    'task_progress',
    'task_avance',
    'gestion_avance',
    'avance_creado',
    'avance_actualizado',
  };

  const novedades = {
    'novedad',
    'news',
    'task_news',
    'task_novedad',
    'respuesta_novedad',
    'novedad_creada',
    'novedad_actualizada',
  };

  const finalizacion = {
    'finalizacion',
    'completed',
    'task_completed',
    'finalizado',
    'task_finalizado',
    'task_finalizada',
  };

  if (avances.contains(t)) return 'Avances';
  if (novedades.contains(t)) return 'Novedades';
  if (finalizacion.contains(t)) return 'Finalización';
  return null;
}

Future<void> _openNotificationTask(
    BuildContext context, {
      required String type,
      required String taskId,
      required String cedula,
    }) async {
  final tabKey = _processTabForNotifType(type);

  if (tabKey != null) {
    int tabIndex = 0;

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
          tabIndex = 1;
        } else if (assignedId.isNotEmpty && assignedId == cedula) {
          tabIndex = 0;
        } else {
          tabIndex = 1;
        }
      }
    } catch (_) {}

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TaskHistoryScreen(
          currentUserId: cedula,
          initialTabIndex: tabIndex,
          highlightTaskId: taskId,
          openProcessTabKey: tabKey,
        ),
      ),
    );
    return;
  }

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

class NotificationsScreen extends StatelessWidget {
  final String userId;
  const NotificationsScreen({Key? key, required this.userId}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Notificaciones', style: TextStyle(fontFamily: kArial)),
          backgroundColor: kMarronOscuro,
          bottom: const TabBar(
            tabs: [Tab(text: 'Nuevas'), Tab(text: 'Historial')],
          ),
        ),
        body: TabBarView(
          children: [
            _NotificationList(userId: userId, onlyUnread: true),
            _NotificationList(userId: userId, onlyUnread: false),
          ],
        ),
      ),
    );
  }
}

class _NotificationList extends StatelessWidget {
  final String userId;
  final bool onlyUnread;

  const _NotificationList({
    Key? key,
    required this.userId,
    required this.onlyUnread,
  }) : super(key: key);

  DateTime? _parseCreatedAt(dynamic createdAt) {
    if (createdAt == null) return null;
    if (createdAt is Timestamp) return createdAt.toDate();
    if (createdAt is int) return DateTime.fromMillisecondsSinceEpoch(createdAt);
    if (createdAt is String) return DateTime.tryParse(createdAt);
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

  String _fromOf(Map<String, dynamic> data) {
    final from = (data['fromName'] ?? data['fromId'] ?? '').toString().trim();
    return from;
  }

  String _fromLabel(String type) {
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

  Future<void> _markTaskSeen(String taskId) async {
    if (taskId.trim().isEmpty) return;
    try {
      await FirebaseFirestore.instance
          .collection('TBL_TAREAS')
          .doc(taskId)
          .set({'visto': true}, SetOptions(merge: true));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection(_notifsRoot)
        .doc(userId)
        .collection('notifications')
        .orderBy('createdAt', descending: true)
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 42),
                  const SizedBox(height: 8),
                  const Text(
                    'No se pudieron cargar las notificaciones.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: kArial, fontSize: 16),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    snap.error.toString(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontFamily: kArial, fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
            ),
          );
        }

        final docs = snap.data?.docs ?? [];

        final seen = <String>{};
        final uniqueDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        for (final d in docs) {
          final data = d.data();
          final taskId = (data['taskId'] as String?) ?? '';
          final when = _parseCreatedAt(data['createdAt']);
          final key = '$taskId-${when?.millisecondsSinceEpoch ?? d.id}';
          if (seen.add(key)) uniqueDocs.add(d);
        }

        final filtered = onlyUnread
            ? uniqueDocs.where((d) => !_isRead(d.data())).toList()
            : uniqueDocs;

        if (filtered.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  onlyUnread ? Icons.mark_email_unread : Icons.notifications_none,
                  color: Colors.black54,
                  size: 48,
                ),
                const SizedBox(height: 8),
                Text(
                  onlyUnread ? 'No hay notificaciones nuevas.' : 'Sin notificaciones.',
                  style: const TextStyle(fontFamily: kArial, fontSize: 16),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          itemCount: filtered.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (c, i) {
            final doc = filtered.elementAt(i);
            final data = doc.data();

            final taskId = data['taskId'] as String?;
            final title = (data['title'] as String?) ?? '';
            final desc = (data['description'] as String?) ?? '';
            final type = (data['type'] ?? '').toString(); // ✅ IMPORTANTE
            final from = _fromOf(data);
            final fromLabel = _fromLabel(type);
            final dt = _parseCreatedAt(data['createdAt']);
            final when = dt != null ? DateFormat('dd/MM/yyyy HH:mm').format(dt) : '...';
            final isRead = _isRead(data);

            return Card(
              elevation: 1.5,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              color: isRead ? Colors.white : const Color(0xFFE8F1FB),
              child: ListTile(
                contentPadding: const EdgeInsets.all(12),
                leading: CircleAvatar(
                  backgroundColor: isRead ? Colors.grey.shade200 : const Color(0xFFCCE1F5),
                  child: Icon(
                    onlyUnread ? Icons.fiber_new : Icons.notifications,
                    color: isRead ? Colors.black54 : kMarronOscuro,
                  ),
                ),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(fontFamily: kArial, fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (!isRead)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.redAccent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'NUEVA',
                          style: TextStyle(
                            fontFamily: kArial,
                            fontSize: 10,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(when, style: const TextStyle(fontFamily: kArial)),
                      const SizedBox(height: 4),
                      Text(desc, style: const TextStyle(fontFamily: kArial)),
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
                    ],
                  ),
                ),
                trailing: taskId == null
                    ? null
                    : TextButton.icon(
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Ver detalle'),
                  onPressed: () async {
                    if (!isRead) {
                      await doc.reference.update({'read': true});
                    }
                    if (taskId != null) {
                      await _markTaskSeen(taskId);
                    }
                    await _openNotificationTask(
                      context,
                      type: type,
                      taskId: taskId,
                      cedula: userId,
                    );
                  },
                ),
                onTap: () async {
                  if (!isRead) {
                    await doc.reference.update({'read': true});
                  }
                  if (taskId != null) {
                    await _markTaskSeen(taskId);
                    await _openNotificationTask(
                      context,
                      type: type,
                      taskId: taskId,
                      cedula: userId,
                    );
                  }
                },
              ),
            );
          },
        );
      },
    );
  }
}
