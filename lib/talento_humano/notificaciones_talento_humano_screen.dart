//lib/talento_humano/notificaciones_talento_humano_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

const String _notifsCollection = 'TBL_NOTIFICACIONES';

/// Notificaciones exclusivas de Talento Humano
class NotificacionesTalentoHumanoScreen extends StatelessWidget {
  final String userId;
  const NotificacionesTalentoHumanoScreen({Key? key, required this.userId})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Notificaciones TH'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Nuevas'),
              Tab(text: 'Historial'),
            ],
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
    var query = FirebaseFirestore.instance
        .collection(_notifsCollection)
        .where('to', isEqualTo: 'TH_$userId') // por ejemplo filtrar con prefijo
        .orderBy('timestamp', descending: true);
    if (onlyUnread) query = query.where('read', isEqualTo: false);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return Center(
            child: Text(
              onlyUnread ? 'Sin notificaciones nuevas TH.' : 'Sin notificaciones TH.',
              style: const TextStyle(fontSize: 16),
            ),
          );
        }
        return ListView.separated(
          itemCount: docs.length,
          separatorBuilder: (_, __) => const Divider(),
          itemBuilder: (c, i) {
            final d    = docs[i];
            final data = d.data();
            final msg  = data['message'] as String? ?? '';
            final ts   = data['timestamp'] as Timestamp?;
            final when = ts != null
                ? DateFormat('dd/MM/yyyy HH:mm').format(ts.toDate())
                : '';
            final isRead = data['read'] as bool? ?? false;

            return ListTile(
              leading: onlyUnread
                  ? const Icon(Icons.fiber_new, color: Colors.blue)
                  : const Icon(Icons.mark_email_read),
              title: Text(msg),
              subtitle: Text(when),
              onTap: () async {
                if (!isRead) {
                  await FirebaseFirestore.instance
                      .collection(_notifsCollection)
                      .doc(d.id)
                      .update({'read': true});
                }
                showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Detalle TH'),
                    content: Text(msg),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cerrar'),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
