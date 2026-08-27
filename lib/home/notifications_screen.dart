// lib/home/notifications_screen.dart

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart' as http;
import 'package:todo/theme/app_typography.dart';
import 'package:intl/intl.dart';
import 'package:todo/widgets/empty_state_widget.dart';
import 'package:todo/widgets/user_avatar.dart';
import '../core/task_route_guard.dart';
import '../facturacion/facturacion_navigation.dart';

import '../compras/compras_dashboard_screen.dart';
import '../nutricion/nutricion_dashboard_screen.dart';
import '../rutas/rutas_dashboard_screen.dart';
import '../rutas/rutas_models.dart';
import '../talento_humano/hoja_de_vida_screen.dart';
import 'assigned_tasks_screen.dart';
import 'created_tasks_screen.dart';
import 'task_history_screen.dart' hide kArial;

const String _notifsRoot = 'TBL_NOTIFICACIONES';
const Color kMarronOscuro = Color(0xFF145DA0);

bool _isRutasEvidenceRejected(String type) =>
    type.trim().toLowerCase() == 'rutas_evidencia_rechazada';

Future<bool> _openRutasModuleFromNotification(
  BuildContext context, {
  required String cedula,
  String? empresaId,
}) async {
  final eid = (empresaId ?? '').trim();
  if (eid.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('No se encontró la empresa para abrir Rutas.'),
      ),
    );
    return false;
  }
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => RutasDashboardScreen(
        userId: cedula,
        empresaId: eid,
        rolRutas: kRutasRolConductor,
      ),
    ),
  );
  return true;
}

/// Abre el destino de la notificación según el tipo.
/// Maneja tipos especiales de Compras antes de delegar al TaskRouteGuard.
/// Retorna true si la navegación fue exitosa.
Future<bool> _openNotificationTask(
  BuildContext context, {
  required String type,
  required String taskId,
  required String cedula,
  String? empresaId,
}) async {
  if (_isRutasEvidenceRejected(type)) {
    return _openRutasModuleFromNotification(
      context,
      cedula: cedula,
      empresaId: empresaId,
    );
  }

  if (taskId.trim().isEmpty) return true;

  // Tipos de Nutrición: navegan a NutricionDashboardScreen.
  if (type == 'cita_nutricion_agendada' ||
      type == 'cita_nutricion_recordatorio') {
    if (taskId.isNotEmpty && context.mounted) {
      await abrirNutricionDesdeCita(context, userId: cedula, citaId: taskId);
    }
    return context.mounted;
  }

  // Tipos de Gestión Documental: marcar como leída y mostrar aviso orientativo.
  // El docId viaja como taskId pero no corresponde a TBL_TAREAS, así que
  // no intentamos navegar por TaskRouteGuard para evitar el error.
  if (type.startsWith('gestion_documental')) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Abre el módulo de Gestión de Correspondencia para revisar el documento.',
          ),
          duration: Duration(seconds: 3),
        ),
      );
    }
    return context.mounted;
  }

  // Tipos de Compras: navegan al proveedor o ficha, sin pasar por TaskRouteGuard.
  if ((type == 'doc_rechazado' ||
          type == 'correccion_requerida' ||
          type == 'nuevo_proveedor' ||
          type == 'documento_por_vencer') &&
      taskId.startsWith('proveedor:')) {
    final proveedorId = taskId.replaceFirst('proveedor:', '').trim();
    if (proveedorId.isNotEmpty && context.mounted) {
      await abrirDetalleProveedor(
        context,
        userId: cedula,
        proveedorId: proveedorId,
      );
    }
    return context.mounted;
  }
  if ((type == 'ficha_rechazada' || type == 'documento_por_vencer') &&
      taskId.startsWith('ficha:')) {
    final fichaId = taskId.replaceFirst('ficha:', '').trim();
    if (fichaId.isNotEmpty && context.mounted) {
      await abrirDetalleFichaRechazada(
        context,
        userId: cedula,
        fichaId: fichaId,
      );
    }
    return context.mounted;
  }
  if ((type == 'recepcion_doc_rechazado' || type == 'documento_por_vencer') &&
      taskId.startsWith('recepcion:')) {
    if (context.mounted) {
      await abrirDetalleRecepcionCompras(
        context,
        userId: cedula,
        recepcionId: taskId,
      );
    }
    return context.mounted;
  }
  if ((type == 'documento_por_vencer' || type == 'marca_doc_rechazado') &&
      taskId.startsWith('marca:')) {
    final marcaId = taskId.replaceFirst('marca:', '').trim();
    if (marcaId.isNotEmpty && context.mounted) {
      await abrirDocumentosMarcaCompras(
        context,
        userId: cedula,
        marcaId: marcaId,
      );
    }
    return context.mounted;
  }

  if (await tryOpenFacturacionDocumentTask(
    context,
    userId: cedula,
    taskId: taskId,
  )) {
    return true;
  }

  final routeDecision = await TaskRouteGuard().resolveNotificationRoute(
    context,
    userIdentity: cedula,
    taskId: taskId,
    type: type,
  );
  if (!routeDecision.allowed) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            routeDecision.message ??
                'No se pudo abrir el destino de la notificación.',
          ),
        ),
      );
    }
    return false;
  }

  if (context.mounted) {
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
      return true;
    }

    if (routeDecision.target == TaskRouteTarget.createdTasks) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              CreatedTasksScreen(userId: cedula, highlightTaskId: taskId),
        ),
      );
      return true;
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
      return true;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            AssignedTasksScreen(userId: cedula, highlightTaskId: taskId),
      ),
    );
    return true;
  }
  return false;
}

class NotificationsScreen extends StatelessWidget {
  final String userId;
  final String? empresaId;

  const NotificationsScreen({Key? key, required this.userId, this.empresaId})
    : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isWeb = MediaQuery.of(context).size.width >= 900;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: isWeb
            ? scheme.surfaceContainerHighest.withValues(alpha: 0.2)
            : scheme.surface,
        appBar: AppBar(
          backgroundColor: scheme.surface,
          foregroundColor: scheme.onSurface,
          title: const Text(
            'Notificaciones',
            style: TextStyle(
              fontFamily: kArial,
              fontWeight: FontWeight.w900,
              fontSize: 22,
              letterSpacing: -0.5,
            ),
          ),
          elevation: 0,
          centerTitle: false,
          actions: [
            TextButton.icon(
              onPressed: () => _markAllAsRead(userId, empresaId),
              icon: const Icon(Icons.done_all, size: 18),
              label: const Text(
                'Leer todo',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              style: TextButton.styleFrom(
                foregroundColor: scheme.primary,
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
            ),
            const SizedBox(width: 8),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(60),
            child: Container(
              width: double.infinity,
              padding: isWeb
                  ? const EdgeInsets.symmetric(horizontal: 32)
                  : const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: scheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: isWeb ? 400 : double.infinity,
                ),
                child: TabBar(
                  labelColor: scheme.primary,
                  unselectedLabelColor: scheme.onSurfaceVariant,
                  indicatorColor: scheme.primary,
                  indicatorWeight: 3,
                  indicatorSize: TabBarIndicatorSize.label,
                  labelPadding: const EdgeInsets.symmetric(vertical: 12),
                  labelStyle: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontFamily: kArial,
                    fontSize: 14,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontFamily: kArial,
                    fontSize: 14,
                  ),
                  tabs: const [
                    Tab(text: 'NUEVAS'),
                    Tab(text: 'HISTORIAL'),
                  ],
                ),
              ),
            ),
          ),
        ),
        body: TabBarView(
          children: [
            _NotificationList(
              userId: userId,
              onlyUnread: true,
              empresaId: empresaId,
            ),
            _NotificationList(
              userId: userId,
              onlyUnread: false,
              empresaId: empresaId,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _markAllAsRead(String userId, String? empresaId) async {
    final snap = await FirebaseFirestore.instance
        .collection(_notifsRoot)
        .doc(userId)
        .collection('notifications')
        .get();
    if (snap.docs.isEmpty) return;

    final eid = (empresaId ?? '').trim();
    final toMark = snap.docs.where((d) {
      final data = d.data();
      if (_NotificationList.isReadData(data)) {
        return false;
      }
      if (eid.isNotEmpty) {
        final notifEmpresa = (d.data()['empresaId'] ?? '').toString().trim();
        if (notifEmpresa != eid) return false;
      }
      return true;
    }).toList();

    if (toMark.isEmpty) return;

    for (var i = 0; i < toMark.length; i += 450) {
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in toMark.skip(i).take(450)) {
        batch.update(doc.reference, {'read': true});
      }
      await batch.commit();
    }
  }
}

class _NotificationList extends StatelessWidget {
  final String userId;
  final bool onlyUnread;
  final String? empresaId;

  const _NotificationList({
    Key? key,
    required this.userId,
    required this.onlyUnread,
    this.empresaId,
  }) : super(key: key);

  DateTime? _parseCreatedAt(dynamic createdAt) {
    if (createdAt == null) return null;
    if (createdAt is Timestamp) return createdAt.toDate();
    if (createdAt is int) return DateTime.fromMillisecondsSinceEpoch(createdAt);
    if (createdAt is String) return DateTime.tryParse(createdAt);
    return null;
  }

  static bool isReadData(Map<String, dynamic> data) {
    final read = data['read'];
    final leido = data['leido'];
    final visto = data['visto'];
    return (read is bool && read) ||
        (leido is bool && leido) ||
        (visto is bool && visto);
  }

  bool _isRead(Map<String, dynamic> data) => isReadData(data);

  /// Filtra por empresa activa. Las legacy sin empresaId sólo aparecen en vista general.
  bool _matchesEmpresa(Map<String, dynamic> data) {
    final eid = (empresaId ?? '').trim();
    if (eid.isEmpty) return true;
    final notifEmpresa = (data['empresaId'] ?? '').toString().trim();
    return notifEmpresa == eid;
  }

  String _empresaKey(Map<String, dynamic> data) {
    final raw = (data['empresaId'] ?? '').toString().trim();
    return raw.isEmpty ? '__sin_empresa__' : raw;
  }

  String _empresaLabel(Map<String, dynamic> data) {
    final explicit =
        (data['empresaNombre'] ??
                data['companyName'] ??
                data['nombreEmpresa'] ??
                data['empresa'])
            ?.toString()
            .trim() ??
        '';
    if (explicit.isNotEmpty) return explicit;
    final eid = (data['empresaId'] ?? '').toString().trim();
    return eid.isEmpty ? 'Sin empresa' : eid;
  }

  String _fromOf(Map<String, dynamic> data) {
    return (data['fromName'] ?? data['fromId'] ?? '').toString().trim();
  }

  String _fromLabel(String type) {
    final t = type.trim().toLowerCase();
    if (t.contains('assigned')) return 'Asignado por';
    if (t.contains('avance') || t.contains('progress')) return 'Reportado por';
    if (t.contains('novedad') || t.contains('news')) return 'Reportado por';
    if (t.contains('finaliz') || t.contains('aprobad') || t.contains('devuelt')) {
      return 'Gestionado por';
    }
    return 'De';
  }

  String _typeLabel(String type) {
    final t = type.trim().toLowerCase();
    if (t == 'rutas_evidencia_rechazada') return 'Rutas';
    if (t.contains('reasign')) return 'Reasignación';
    if (t.contains('assigned')) return 'Asignación';
    if (t.contains('avance') || t.contains('progress')) return 'Avance';
    if (t.contains('novedad') || t.contains('news')) return 'Novedad';
    if (t.contains('recepcion_doc_rechazado')) return 'Compras/Bodega';
    if (t.contains('finaliz') ||
        t.contains('aprobad') ||
        t.contains('complet')) {
      return 'Finalización';
    }
    if (t.contains('devuelt')) return 'Devolución';
    // Tipos TH
    if (t == 'cumpleanos') return 'Cumpleaños';
    if (t == 'celebracion') return 'Felicitación';
    if (t == 'general_th') return 'Talento Humano';
    if (t == 'motivacion') return 'Motivación';
    if (t == 'beneficios') return 'Beneficios';
    if (t == 'hv_correccion') return 'Hoja de Vida – Corrección';
    if (t == 'hv_aprobada') return 'Hoja de Vida – Aprobada';
    if (t == 'talento_humano') return 'Talento Humano';
    return 'Notificación';
  }

  IconData _getIconForType(String type) {
    final t = type.trim().toLowerCase();
    if (t == 'rutas_evidencia_rechazada') {
      return Icons.local_shipping_outlined;
    }
    if (t.startsWith('gestion_documental')) return Icons.description_outlined;
    if (t.contains('assigned') || t.contains('reasign')) {
      return Icons.assignment_ind_rounded;
    }
    if (t.contains('avance') || t.contains('progress')) {
      return Icons.trending_up_rounded;
    }
    if (t.contains('novedad') || t.contains('news')) {
      return Icons.error_outline_rounded;
    }
    if (t.contains('rechazado') || t.contains('correccion')) {
      return Icons.description_outlined;
    }
    if (t.contains('finaliz') || t.contains('complet') || t.contains('aprobad')) {
      return Icons.check_circle_outline_rounded;
    }
    if (t.contains('devuelt')) return Icons.undo_rounded;
    // Tipos TH
    if (t == 'cumpleanos') return Icons.cake_outlined;
    if (t == 'celebracion') return Icons.celebration_outlined;
    if (t == 'general_th') return Icons.campaign_outlined;
    if (t == 'motivacion') return Icons.fitness_center_outlined;
    if (t == 'beneficios') return Icons.card_giftcard_outlined;
    if (t == 'hv_correccion') return Icons.edit_note_rounded;
    if (t == 'hv_aprobada') return Icons.verified_rounded;
    if (t == 'talento_humano') return Icons.people_alt_outlined;
    return Icons.notifications_active_outlined;
  }

  Color _getColorForType(String type, BuildContext context) {
    final t = type.trim().toLowerCase();
    if (t == 'rutas_evidencia_rechazada') return const Color(0xFF15803D);
    if (t.startsWith('gestion_documental')) return const Color(0xFF145DA0);
    if (t.contains('assigned') || t.contains('reasign')) return Colors.blue;
    if (t.contains('avance') || t.contains('progress')) return Colors.green;
    if (t.contains('novedad') || t.contains('news')) return Colors.orange;
    if (t.contains('rechazado') || t.contains('correccion')) return Colors.red;
    if (t.contains('finaliz') || t.contains('aprobad')) return Colors.teal;
    if (t.contains('devuelt')) return Colors.deepOrange;
    // Tipos TH
    if (t == 'cumpleanos') return const Color(0xFFF59E0B);
    if (t == 'celebracion') return const Color(0xFF7C3AED);
    if (t == 'general_th') return const Color(0xFFC28942);
    if (t == 'motivacion') return const Color(0xFF059669);
    if (t == 'beneficios') return const Color(0xFF0284C7);
    if (t == 'hv_correccion') return Colors.orange.shade700;
    if (t == 'hv_aprobada') return Colors.green;
    if (t == 'talento_humano') return const Color(0xFFC28942);
    return Theme.of(context).primaryColor;
  }

  @override
  Widget build(BuildContext context) {
    final isWeb = MediaQuery.of(context).size.width >= 900;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

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
          return EmptyStateWidget(
            icon: Icons.error_outline,
            title: 'Error al cargar',
            message: 'No pudimos cargar tus notificaciones en este momento.',
            actionLabel: 'Reintentar',
            onAction: () {},
          );
        }

        final docs = snap.data?.docs ?? [];
        final uniqueDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        final seen = <String>{};

        for (final d in docs) {
          final data = d.data();
          // Filtro de empresa activa: si hay empresa seleccionada, sólo entra esa empresa.
          if (!_matchesEmpresa(data)) continue;
          final taskId = (data['taskId'] as String?) ?? '';
          final when = _parseCreatedAt(data['createdAt']);
          final key = '$taskId-${when?.millisecondsSinceEpoch ?? d.id}';
          if (seen.add(key)) {
            if (!onlyUnread || !_isRead(data)) {
              uniqueDocs.add(d);
            }
          }
        }

        if (uniqueDocs.isEmpty) {
          return EmptyStateWidget(
            icon: onlyUnread
                ? Icons.notifications_off_outlined
                : Icons.notifications_none_rounded,
            title: onlyUnread ? 'Sin novedades' : 'Historial vacío',
            message: onlyUnread
                ? 'Estás al día. No tienes notificaciones nuevas.'
                : 'Aún no tienes un historial de actividades.',
          );
        }

        // Group by company + date when no active company was provided.
        final grouped =
            <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
        final showCompanyDivision = (empresaId ?? '').trim().isEmpty;
        final companyKeys = <String>{};
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final yesterday = today.subtract(const Duration(days: 1));

        for (final doc in uniqueDocs) {
          final data = doc.data();
          companyKeys.add(_empresaKey(data));
          final dt = _parseCreatedAt(data['createdAt']);
          String dateKey = 'Anteriores';
          if (dt != null) {
            final date = DateTime(dt.year, dt.month, dt.day);
            if (date == today) {
              dateKey = 'Hoy';
            } else if (date == yesterday)
              dateKey = 'Ayer';
            else
              dateKey = DateFormat('MMMM dd, yyyy', 'es_CO').format(date);
          }
          final key = showCompanyDivision
              ? '${_empresaLabel(data)} · $dateKey'
              : dateKey;
          grouped.putIfAbsent(key, () => []).add(doc);
        }

        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isWeb ? 800 : double.infinity,
            ),
            child: ListView.builder(
              padding: EdgeInsets.symmetric(
                horizontal: isWeb ? 32 : 16,
                vertical: 24,
              ),
              itemCount: grouped.keys.length + 1,
              itemBuilder: (context, groupIndex) {
                if (groupIndex == 0) {
                  final unreadCount = uniqueDocs
                      .where((doc) => !_isRead(doc.data()))
                      .length;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 24),
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          scheme.primary.withValues(alpha: 0.10),
                          scheme.surfaceContainerHighest.withValues(alpha: 0.55),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: scheme.primary.withValues(alpha: 0.10),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: scheme.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            Icons.notifications_active_rounded,
                            color: scheme.primary,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                onlyUnread
                                    ? 'Bandeja nueva'
                                    : 'Historial de actividad',
                                style: TextStyle(
                                  fontFamily: kArial,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                  color: scheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                onlyUnread
                                    ? '$unreadCount alerta${unreadCount == 1 ? "" : "s"} pendiente${unreadCount == 1 ? "" : "s"}${showCompanyDivision ? " en ${companyKeys.length} empresa${companyKeys.length == 1 ? "" : "s"}" : ""}'
                                    : '${uniqueDocs.length} registro${uniqueDocs.length == 1 ? "" : "s"} disponible${uniqueDocs.length == 1 ? "" : "s"}${showCompanyDivision ? " en ${companyKeys.length} empresa${companyKeys.length == 1 ? "" : "s"}" : ""}',
                                style: TextStyle(
                                  fontFamily: kArial,
                                  fontSize: 13,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }
                final groupKey = grouped.keys.elementAt(groupIndex - 1);
                final items = grouped[groupKey]!;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          groupKey.toUpperCase(),
                          style: TextStyle(
                            color: scheme.primary,
                            fontWeight: FontWeight.w900,
                            fontSize: 11,
                            letterSpacing: 1.5,
                            fontFamily: kArial,
                          ),
                        ),
                      ),
                    ),
                    ...items.map((doc) {
                      final data = doc.data();
                      final taskId = data['taskId'] as String?;
                      final title = (data['title'] as String?) ?? '';
                      final desc = (data['description'] as String?) ?? '';
                      final type = (data['type'] ?? '').toString();
                      final from = _fromOf(data);
                      final fromId = (data['fromId'] ?? '').toString().trim();
                      final fromLabel = _fromLabel(type);
                      final category = _typeLabel(type);
                      final companyLabel = _empresaLabel(data);
                      final dt = _parseCreatedAt(data['createdAt']);
                      final when = dt != null
                          ? DateFormat('hh:mm a').format(dt).toLowerCase()
                          : '--:--';
                      final isRead = _isRead(data);
                      final typeIcon = _getIconForType(type);
                      final typeColor = _getColorForType(type, context);
                      final imageUrl =
                          (data['imageUrl'] as String?)?.trim() ?? '';
                      final bannerId =
                          (data['bannerId'] as String?)?.trim() ?? '';
                      final notifEmpresaId =
                          (data['empresaId'] as String?)?.trim() ?? '';
                      final hasBanner =
                          bannerId.isNotEmpty && notifEmpresaId.isNotEmpty;
                      final target = (data['target'] as String?)?.trim() ?? '';
                      final isHojaVidaNotif =
                          type == 'hv_correccion' ||
                          type == 'hv_aprobada' ||
                          target == 'hoja_vida';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: scheme.surface,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isRead
                                ? scheme.outlineVariant.withValues(alpha: 0.3)
                                : scheme.primary.withValues(alpha: 0.15),
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: isRead
                                  ? Colors.black.withValues(alpha: 0.02)
                                  : scheme.primary.withValues(alpha: 0.04),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Material(
                                color: isRead
                                    ? Colors.transparent
                                    : scheme.primary.withValues(alpha: 0.02),
                                child: InkWell(
                                  onTap: () async {
                                    // Hoja de vida: corrección → abre el formulario
                                    if (isHojaVidaNotif) {
                                      if (!isRead) {
                                        try {
                                          await doc.reference.update({
                                            'read': true,
                                          });
                                        } catch (_) {}
                                      }
                                      if (!context.mounted) return;
                                      final eid = notifEmpresaId.isNotEmpty
                                          ? notifEmpresaId
                                          : (empresaId ?? '');
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => HojaDeVidaScreen(
                                            userId: userId,
                                            empresaId: eid,
                                            mode: HvMode.perfil,
                                          ),
                                        ),
                                      );
                                      return;
                                    }

                                    if (_isRutasEvidenceRejected(type)) {
                                      final opened =
                                          await _openRutasModuleFromNotification(
                                            context,
                                            cedula: userId,
                                            empresaId: notifEmpresaId.isNotEmpty
                                                ? notifEmpresaId
                                                : empresaId,
                                          );
                                      if (opened && !isRead) {
                                        try {
                                          await doc.reference.update({
                                            'read': true,
                                          });
                                        } catch (_) {}
                                      }
                                      return;
                                    }

                                    if (taskId == null ||
                                        taskId.trim().isEmpty) {
                                      if (!isRead) {
                                        try {
                                          await doc.reference.update({
                                            'read': true,
                                          });
                                        } catch (_) {}
                                      }
                                      return;
                                    }
                                    if (!context.mounted) return;
                                    final opened = await _openNotificationTask(
                                      context,
                                      type: type,
                                      taskId: taskId,
                                      cedula: userId,
                                      empresaId: notifEmpresaId.isNotEmpty
                                          ? notifEmpresaId
                                          : empresaId,
                                    );
                                    if (opened && !isRead) {
                                      try {
                                        await doc.reference.update({
                                          'read': true,
                                        });
                                      } catch (_) {}
                                    }
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Stack(
                                          alignment: Alignment.topRight,
                                          children: [
                                            Container(
                                              width: 48,
                                              height: 48,
                                              decoration: BoxDecoration(
                                                color: isRead
                                                    ? scheme.surfaceContainerHighest
                                                          .withValues(alpha: 0.3)
                                                    : typeColor.withValues(
                                                        alpha: 0.12,
                                                      ),
                                                borderRadius:
                                                    BorderRadius.circular(14),
                                              ),
                                              child: Icon(
                                                typeIcon,
                                                color: isRead
                                                    ? scheme.onSurfaceVariant
                                                          .withValues(alpha: 0.7)
                                                    : typeColor,
                                                size: 24,
                                              ),
                                            ),
                                            if (!isRead)
                                              Positioned(
                                                right: -2,
                                                top: -2,
                                                child: Container(
                                                  width: 12,
                                                  height: 12,
                                                  decoration: BoxDecoration(
                                                    color: scheme.primary,
                                                    shape: BoxShape.circle,
                                                    border: Border.all(
                                                      color: scheme.surface,
                                                      width: 2,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      title,
                                                      style: TextStyle(
                                                        fontFamily: kArial,
                                                        fontWeight: isRead
                                                            ? FontWeight.w700
                                                            : FontWeight.w900,
                                                        fontSize: 15,
                                                        color: isRead
                                                            ? scheme.onSurface
                                                                  .withValues(
                                                                    alpha: 0.8,
                                                                  )
                                                            : scheme.onSurface,
                                                        letterSpacing: -0.2,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    when,
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: scheme
                                                          .onSurfaceVariant
                                                          .withValues(alpha: 0.6),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 6),
                                              Wrap(
                                                spacing: 8,
                                                runSpacing: 8,
                                                children: [
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 10,
                                                          vertical: 4,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: typeColor
                                                          .withValues(alpha: 0.10),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            999,
                                                          ),
                                                    ),
                                                    child: Text(
                                                      category,
                                                      style: TextStyle(
                                                        fontFamily: kArial,
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight.w800,
                                                        color: typeColor,
                                                      ),
                                                    ),
                                                  ),
                                                  if (showCompanyDivision)
                                                    Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 10,
                                                            vertical: 4,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: scheme
                                                            .surfaceContainerHighest
                                                            .withValues(alpha: 0.55),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              999,
                                                            ),
                                                      ),
                                                      child: Text(
                                                        companyLabel,
                                                        style: TextStyle(
                                                          fontFamily: kArial,
                                                          fontSize: 11,
                                                          fontWeight:
                                                              FontWeight.w800,
                                                          color: scheme
                                                              .onSurfaceVariant,
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                desc,
                                                style: TextStyle(
                                                  fontFamily: kArial,
                                                  color:
                                                      scheme.onSurfaceVariant,
                                                  fontSize: 14,
                                                  height: 1.4,
                                                  fontWeight: isRead
                                                      ? FontWeight.w400
                                                      : FontWeight.w500,
                                                ),
                                              ),
                                              if (isHojaVidaNotif) ...[
                                                const SizedBox(height: 10),
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 10,
                                                        vertical: 7,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: typeColor
                                                        .withValues(alpha: 0.08),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          10,
                                                        ),
                                                    border: Border.all(
                                                      color: typeColor
                                                          .withValues(alpha: 0.18),
                                                    ),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Icon(
                                                        Icons
                                                            .open_in_new_rounded,
                                                        size: 14,
                                                        color: typeColor,
                                                      ),
                                                      const SizedBox(width: 6),
                                                      Flexible(
                                                        child: Text(
                                                          type == 'hv_correccion'
                                                              ? 'Abrir hoja de vida para corregir'
                                                              : 'Abrir mi hoja de vida',
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style: TextStyle(
                                                            color: typeColor,
                                                            fontSize: 12,
                                                            fontWeight:
                                                                FontWeight.w800,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                              if (imageUrl.isNotEmpty) ...[
                                                const SizedBox(height: 12),
                                                _StorageImage(
                                                  url: imageUrl,
                                                  scheme: scheme,
                                                ),
                                              ],
                                              if (from.isNotEmpty) ...[
                                                const SizedBox(height: 12),
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 10,
                                                        vertical: 4,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: scheme.surfaceContainerHighest
                                                        .withValues(alpha: 0.3),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Icon(
                                                        Icons
                                                            .person_outline_rounded,
                                                        size: 12,
                                                        color: scheme
                                                            .onSurfaceVariant
                                                            .withValues(alpha: 0.7),
                                                      ),
                                                      const SizedBox(width: 6),
                                                      UserNameText(
                                                        fromId,
                                                        fallbackName: from,
                                                        prefix: '$fromLabel: ',
                                                        style: TextStyle(
                                                          fontFamily: kArial,
                                                          fontSize: 11,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          color: scheme
                                                              .onSurfaceVariant
                                                              .withValues(alpha: 0.8),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        if (taskId != null) ...[
                                          const SizedBox(width: 8),
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 12,
                                            ),
                                            child: Icon(
                                              Icons.arrow_forward_ios_rounded,
                                              size: 14,
                                              color: scheme.onSurfaceVariant
                                                  .withValues(alpha: 0.3),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              // Reacciones y comentarios estilo WhatsApp (solo para banners TH)
                              if (hasBanner) ...[
                                Divider(
                                  height: 1,
                                  color: scheme.outlineVariant.withValues(alpha: 0.4),
                                ),
                                _ReactionBar(
                                  bannerId: bannerId,
                                  empresaId: notifEmpresaId,
                                  userId: userId,
                                ),
                                Divider(
                                  height: 1,
                                  color: scheme.outlineVariant.withValues(alpha: 0.3),
                                ),
                                _CommentsSection(
                                  bannerId: bannerId,
                                  empresaId: notifEmpresaId,
                                  userId: userId,
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 16),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

// ── Barra de reacciones estilo WhatsApp ───────────────────────────────────────
class _ReactionBar extends StatefulWidget {
  final String bannerId;
  final String empresaId;
  final String userId;
  const _ReactionBar({
    required this.bannerId,
    required this.empresaId,
    required this.userId,
  });

  @override
  State<_ReactionBar> createState() => _ReactionBarState();
}

class _ReactionBarState extends State<_ReactionBar> {
  static const _emojis = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

  CollectionReference<Map<String, dynamic>> get _reaccionesColl =>
      FirebaseFirestore.instance
          .collection('TBL_BANNERS_TH')
          .doc(widget.empresaId)
          .collection('enviados')
          .doc(widget.bannerId)
          .collection('reacciones');

  Future<void> _react(String emoji, String? currentEmoji) async {
    try {
      if (emoji == currentEmoji) {
        await _reaccionesColl.doc(widget.userId).delete();
      } else {
        await _reaccionesColl.doc(widget.userId).set({
          'emoji': emoji,
          'userId': widget.userId,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _reaccionesColl.snapshots(),
      builder: (ctx, snap) {
        final docs = snap.data?.docs ?? [];
        final counts = <String, int>{};
        String? myEmoji;
        for (final d in docs) {
          final e = (d.data()['emoji'] as String?) ?? '';
          if (e.isNotEmpty) {
            counts[e] = (counts[e] ?? 0) + 1;
            if (d.id == widget.userId) myEmoji = e;
          }
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: _emojis.map((e) {
              final count = counts[e] ?? 0;
              final isMe = myEmoji == e;
              return GestureDetector(
                onTap: () => _react(e, myEmoji),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.only(right: 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isMe
                        ? scheme.primary.withValues(alpha: 0.12)
                        : (count > 0
                              ? scheme.surfaceContainerHighest.withValues(alpha: 0.5)
                              : Colors.transparent),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isMe
                          ? scheme.primary.withValues(alpha: 0.4)
                          : (count > 0
                                ? scheme.outlineVariant.withValues(alpha: 0.5)
                                : Colors.transparent),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(e, style: const TextStyle(fontSize: 15)),
                      if (count > 0) ...[
                        const SizedBox(width: 3),
                        Text(
                          '$count',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            fontFamily: kArial,
                            color: isMe
                                ? scheme.primary
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}

// ── Sección de comentarios ────────────────────────────────────────────────────
class _CommentsSection extends StatefulWidget {
  final String bannerId;
  final String empresaId;
  final String userId;
  const _CommentsSection({
    required this.bannerId,
    required this.empresaId,
    required this.userId,
  });

  @override
  State<_CommentsSection> createState() => _CommentsSectionState();
}

class _CommentsSectionState extends State<_CommentsSection> {
  bool _expanded = false;
  final _ctrl = TextEditingController();
  bool _sending = false;
  String _userName = '';

  CollectionReference<Map<String, dynamic>> get _comentColl => FirebaseFirestore
      .instance
      .collection('TBL_BANNERS_TH')
      .doc(widget.empresaId)
      .collection('enviados')
      .doc(widget.bannerId)
      .collection('comentarios');

  @override
  void initState() {
    super.initState();
    _loadUserName();
  }

  Future<void> _loadUserName() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('TBL_USUARIOS')
          .doc(widget.userId)
          .get();
      if (doc.exists && doc.data() != null) {
        final d = doc.data()!;
        final nombre =
            (d['nombreCompleto'] as String?)?.trim() ??
            '${(d['nombres'] as String?) ?? ''} ${(d['apellidos'] as String?) ?? ''}'
                .trim();
        if (mounted) {
          setState(
            () => _userName = nombre.isNotEmpty ? nombre : widget.userId,
          );
        }
      }
    } catch (_) {
      if (mounted) setState(() => _userName = widget.userId);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _sendComment() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await _comentColl.add({
        'text': text,
        'userId': widget.userId,
        'userName': _userName.isNotEmpty ? _userName : widget.userId,
        'createdAt': FieldValue.serverTimestamp(),
      });
      _ctrl.clear();
    } catch (_) {
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            child: Row(
              children: [
                Icon(
                  Icons.chat_bubble_outline_rounded,
                  size: 14,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                ),
                const SizedBox(width: 6),
                Text(
                  _expanded ? 'Cerrar comentarios' : 'Comentar',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    fontFamily: kArial,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                ),
                const Spacer(),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
              ],
            ),
          ),
        ),
        if (_expanded) ...[
          Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.3)),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _comentColl
                .orderBy('createdAt', descending: false)
                .snapshots(),
            builder: (ctx, snap) {
              final comments = snap.data?.docs ?? [];
              if (comments.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Text(
                    'Sé el primero en comentar.',
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: kArial,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
                  ),
                );
              }
              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                itemCount: comments.length,
                itemBuilder: (_, i) {
                  final c = comments[i].data();
                  final text = (c['text'] as String?) ?? '';
                  final userId = (c['userId'] as String?) ?? '';
                  final name =
                      (c['userName'] as String?) ??
                      (userId.isNotEmpty ? userId : '?');
                  final ts = c['createdAt'];
                  final dt = ts is Timestamp ? ts.toDate() : null;
                  final time = dt != null
                      ? DateFormat('hh:mm a').format(dt).toLowerCase()
                      : '';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        UserAvatar(
                          userId: userId,
                          nameHint: name,
                          radius: 14,
                          backgroundColor: scheme.primary.withValues(alpha: 0.15),
                          foregroundColor: scheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: UserNameText(
                                        userId,
                                        fallbackName: name,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          fontFamily: kArial,
                                          color: scheme.onSurface,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      time,
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: scheme.onSurfaceVariant
                                            .withValues(alpha: 0.5),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  text,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontFamily: kArial,
                                    color: scheme.onSurface,
                                    height: 1.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    decoration: InputDecoration(
                      hintText: 'Escribe un comentario…',
                      hintStyle: TextStyle(
                        fontSize: 13,
                        fontFamily: kArial,
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 9,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(
                          color: scheme.outlineVariant.withValues(alpha: 0.6),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(
                          color: scheme.outlineVariant.withValues(alpha: 0.4),
                        ),
                      ),
                      isDense: true,
                    ),
                    style: const TextStyle(fontSize: 13, fontFamily: kArial),
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendComment(),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _sending ? null : _sendComment,
                  child: Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: _sending
                          ? scheme.primary.withValues(alpha: 0.5)
                          : scheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: _sending
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: scheme.onPrimary,
                            ),
                          )
                        : Icon(
                            Icons.send_rounded,
                            size: 16,
                            color: scheme.onPrimary,
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ── Widget de imagen cargada via SDK Firebase (sin CORS) ──────────────────────
class _StorageImage extends StatefulWidget {
  final String url;
  final ColorScheme scheme;
  const _StorageImage({required this.url, required this.scheme});

  @override
  State<_StorageImage> createState() => _StorageImageState();
}

class _StorageImageState extends State<_StorageImage> {
  Uint8List? _bytes;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final ref = FirebaseStorage.instance.refFromURL(widget.url);
      final downloadUrl = await ref.getDownloadURL();
      final response = await http.get(Uri.parse(downloadUrl));
      if (response.statusCode == 200) {
        if (mounted) {
          setState(() {
            _bytes = response.bodyBytes;
            _loading = false;
          });
        }
      } else {
        if (mounted) setState(() => _loading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Container(
        height: 120,
        decoration: BoxDecoration(
          color: widget.scheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_bytes == null) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.memory(
        _bytes!,
        width: double.infinity,
        fit: BoxFit.fitWidth, // ancho completo, alto proporcional a la imagen
      ),
    );
  }
}
