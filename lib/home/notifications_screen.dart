// lib/home/notifications_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'assigned_tasks_screen.dart'; // Ajusta ruta si es diferente

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
        final filtered = onlyUnread
            ? docs.where((d) => (d.data()['read'] as bool? ?? false) == false)
            : docs;

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
            final title = data['title'] as String? ?? '';
            final desc = data['description'] as String? ?? '';
            final ts = data['createdAt'] as Timestamp?;
            final when = ts != null
                ? DateFormat('dd/MM/yyyy HH:mm').format(ts.toDate())
                : '';
            final isRead = data['read'] as bool? ?? false;
            final fromId = data['fromId'] as String? ?? '';
            final from = data['fromName'] as String? ?? 'Desconocido';

            return ListTile(
              leading: onlyUnread
                  ? const Icon(Icons.fiber_new, color: Colors.red)
                  : const Icon(Icons.notifications),
              title: Text(title, style: const TextStyle(fontFamily: kArial)),
              subtitle: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                future: FirebaseFirestore.instance
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
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(when, style: const TextStyle(fontFamily: kArial)),
                      Text(
                        'De: $from${cargo.isNotEmpty ? ' · $cargo' : ''}',
                        style: const TextStyle(
                          fontFamily: kArial,
                          fontStyle: FontStyle.italic,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  );
                },
              ),
              isThreeLine: true,
              onTap: () async {
                // 1) Marcar notificación como leída
                if (!isRead) {
                  await doc.reference.update({'read': true});
                }
                // 2) Cambiar estado de la tarea a "visto"
                if (taskId != null) {
                  await FirebaseFirestore.instance
                      .collection('TBL_TAREAS')
                      .doc(taskId)
                      .update({'status': 'visto'});
                }
                // 3) Navegar a AssignedTasksScreen destacando esa tarea
                if (taskId != null) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AssignedTasksScreen(
                        userId: userId,
                        highlightTaskId: taskId,
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
  }
}
