// lib/home/notifications_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'assigned_tasks_screen.dart';

const String _notifsRoot = 'TBL_NOTIFICACIONES';
const Color kMarronOscuro = Color(0xFF145DA0);
const String kArial = 'Arial';

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
    return null;
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

        final docs = snap.data?.docs ?? [];

        // Evita duplicados exactos por taskId + createdAt (si createdAt es null, usa doc.id)
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
            ? uniqueDocs.where((d) => (d.data()['read'] as bool? ?? false) == false).toList()
            : uniqueDocs;

        if (filtered.isEmpty) {
          return Center(
            child: Text(
              onlyUnread ? 'No hay notificaciones nuevas.' : 'Sin notificaciones.',
              style: const TextStyle(fontFamily: kArial, fontSize: 16),
            ),
          );
        }

        return ListView.separated(
          itemCount: filtered.length,
          separatorBuilder: (_, __) => const Divider(),
          itemBuilder: (c, i) {
            final doc = filtered.elementAt(i);
            final data = doc.data();

            final taskId = data['taskId'] as String?;
            final title = (data['title'] as String?) ?? '';
            final desc = (data['description'] as String?) ?? '';
            final dt = _parseCreatedAt(data['createdAt']);
            final when = dt != null ? DateFormat('dd/MM/yyyy HH:mm').format(dt) : '...';
            final isRead = (data['read'] as bool?) ?? false;

            final fromId = (data['fromId'] as String?) ?? '';
            final from = (data['fromName'] as String?) ?? 'Sistema';

            return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              future: taskId == null
                  ? null
                  : FirebaseFirestore.instance.collection('TBL_TAREAS').doc(taskId).get(),
              builder: (ctxTask, snapTask) {
                final taskData = snapTask.data?.data();
                final status = (taskData?['status'] ?? taskData?['estado'] ?? 'pendiente').toString();
                final progress = (taskData?['progreso'] ?? taskData?['avance'] ?? '').toString();

                return ListTile(
                  leading: onlyUnread
                      ? const Icon(Icons.fiber_new, color: Colors.red)
                      : const Icon(Icons.notifications),
                  title: Text(title, style: const TextStyle(fontFamily: kArial)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(when, style: const TextStyle(fontFamily: kArial)),
                      Text(desc, style: const TextStyle(fontFamily: kArial)),
                      if (status.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            children: [
                              const Icon(Icons.timelapse, size: 14),
                              const SizedBox(width: 4),
                              Text('Estado: $status', style: const TextStyle(fontFamily: kArial)),
                            ],
                          ),
                        ),
                      if (progress.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Row(
                            children: [
                              const Icon(Icons.trending_up, size: 14),
                              const SizedBox(width: 4),
                              Text('Avance: $progress%', style: const TextStyle(fontFamily: kArial)),
                            ],
                          ),
                        ),
                      FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                        future: fromId.isEmpty
                            ? null
                            : FirebaseFirestore.instance
                            .collection('TBL_ESTRUCTURA_ORGANIZACIONAL')
                            .doc(fromId)
                            .get(),
                        builder: (ctx2, snapOrg) {
                          String cargo = '';
                          if (snapOrg.connectionState == ConnectionState.done &&
                              snapOrg.hasData &&
                              snapOrg.data!.exists) {
                            cargo = (snapOrg.data!.data()?['cargo'] as String?) ?? '';
                          }
                          return Text(
                            'De: $from${cargo.isNotEmpty ? ' · $cargo' : ''}',
                            style: const TextStyle(
                              fontFamily: kArial,
                              fontStyle: FontStyle.italic,
                              fontSize: 12,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  isThreeLine: true,
                  trailing: taskId == null
                      ? null
                      : TextButton.icon(
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Ver tarea'),
                    onPressed: () async {
                      if (!isRead) {
                        await doc.reference.update({'read': true});
                      }
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AssignedTasksScreen(
                            userId: userId,
                            highlightTaskId: taskId,
                          ),
                        ),
                      );
                    },
                  ),
                  onTap: () async {
                    if (!isRead) {
                      await doc.reference.update({'read': true});
                    }
                    if (taskId != null) {
                      await FirebaseFirestore.instance
                          .collection('TBL_TAREAS')
                          .doc(taskId)
                          .update({'status': 'visto'});

                      showModalBottomSheet(
                        context: context,
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                        ),
                        builder: (_) => Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Detalle de la tarea',
                                style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                (taskData?['descripcion']?.toString() ?? desc),
                                style: const TextStyle(fontFamily: kArial),
                              ),
                              const SizedBox(height: 8),
                              Text('Estado: $status', style: const TextStyle(fontFamily: kArial)),
                              const SizedBox(height: 4),
                              if (taskData != null && taskData['fecha_limite'] != null)
                                Text(
                                  'Vence: ${DateFormat('dd/MM/yyyy').format((taskData['fecha_limite'] as Timestamp).toDate())}',
                                  style: const TextStyle(fontFamily: kArial),
                                ),
                              const SizedBox(height: 12),
                              Align(
                                alignment: Alignment.centerRight,
                                child: ElevatedButton.icon(
                                  icon: const Icon(Icons.open_in_new),
                                  label: const Text('Abrir tarea'),
                                  onPressed: () {
                                    Navigator.pop(context);
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => AssignedTasksScreen(
                                          userId: userId,
                                          highlightTaskId: taskId,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              )
                            ],
                          ),
                        ),
                      );
                    }
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
