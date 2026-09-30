// lib/admin/admin_logs_panel.dart
//
// Admin › Logs: la bitácora de las acciones masivas de Admin en la empresa
// activa (migraciones, limpiezas, cierres de módulo, Multiempresa y copia
// de maestros entre empresas), en
// `TBL_MIGRATIONS_LOGS`. No registra el trabajo del día a día (asignar roles,
// prender apps, editar personas).
//
// 29 sep 2026: antes leía 200 registros sin orden y mostraba 50, así que con
// muchos registros no salían los últimos; tampoco decía quién ni cuándo, y
// mostraba el nombre técnico de la acción. Ahora trae los más recientes
// ordenados por el servidor, con persona, fecha y acción en español, de a 20
// por página.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_typography.dart';
import '../widgets/paged_list.dart';
import '../widgets/user_avatar.dart';

/// Cuántos registros recientes se traen. Con 20 por página son 10 páginas.
const kAdminLogsLimit = 200;

const _kAccionesAdmin = <String, String>{
  'normalizeCentroForUsers': 'Migración: centro de costos',
  'normalizeUserTokensForUsers': 'Migración: tokens de notificación (retirada)',
  'normalizeAppIdsForUsers': 'Migración: nombres de apps (retirada)',
  'normalizePersonNames': 'Normalizar nombres de personas',
  'deleteAllTasksForEmpresa': 'Reinicio: todas las tareas',
  'adminModuleCloseout': 'Limpieza: cerrar sin borrar',
  'RESET_USERS_DATA': 'Reinicio: datos de las personas',
  'PURGE_CATALOGS': 'Reinicio: catálogos',
  'PURGE_ESTRUCTURA': 'Reinicio: estructura organizacional',
  'limpiezaModulo': 'Limpieza: datos de prueba de un módulo',
  'createCompanyAndTransferEmployees': 'Crear empresa y trasladar personal',
  'multiempresaVincularPersona': 'Multiempresa: vincular persona',
  'multiempresaSincronizarPersona': 'Multiempresa: sincronizar persona',
  'multiempresaTraslado': 'Multiempresa: traslado',
  'multiempresaEnviarCatalogo': 'Multiempresa: enviar catálogo',
  'multiempresaFijarModulos': 'Multiempresa: fijar módulos por empresa',
  'sincronizarMaestros': 'Maestros: copiados a otras empresas',
  'recibirMaestros': 'Maestros: recibidos de otra empresa',
};

/// Nombre en español de una acción; la clave técnica si no se conoce.
String adminLogActionLabel(String action) =>
    _kAccionesAdmin[action] ?? (action.trim().isEmpty ? 'Acción' : action);

class AdminLogEntry {
  const AdminLogEntry({
    required this.id,
    required this.action,
    required this.adminUserId,
    required this.scanned,
    required this.updated,
    required this.dryRun,
    this.createdAt,
  });

  final String id;
  final String action;
  final String adminUserId;
  final int scanned;
  final int updated;
  final bool dryRun;
  final DateTime? createdAt;

  String get label => adminLogActionLabel(action);

  /// "Revisados 12 · cambiados 3": sin conteos no dice nada.
  String get conteo {
    if (scanned == 0 && updated == 0) return '';
    return 'Revisados $scanned · ${dryRun ? 'a cambiar' : 'cambiados'} '
        '$updated';
  }

  factory AdminLogEntry.fromMap(String id, Map<String, dynamic> data) {
    int entero(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    final ts = data['createdAt'];
    return AdminLogEntry(
      id: id,
      action: (data['action'] ?? '').toString(),
      adminUserId: (data['adminUserId'] ?? '').toString().trim(),
      scanned: entero(data['scanned']),
      updated: entero(data['updated']),
      dryRun: data['dryRun'] == true,
      createdAt: ts is Timestamp ? ts.toDate() : null,
    );
  }
}

/// Más recientes primero; sin fecha (aún sin hora del servidor) arriba.
List<AdminLogEntry> ordenarLogs(Iterable<AdminLogEntry> logs) =>
    logs.toList()..sort((a, b) {
      final at = a.createdAt, bt = b.createdAt;
      if (at == null && bt == null) return 0;
      if (at == null) return -1;
      if (bt == null) return 1;
      return bt.compareTo(at);
    });

/// Los registros más recientes de [empresaId]. Si el índice de
/// `empresaId + createdAt` todavía no está desplegado, cae a la consulta
/// sin orden y ordena en memoria (lo de antes, pero sin cortar a 50).
Future<List<AdminLogEntry>> cargarLogsAdmin(
  FirebaseFirestore db,
  String empresaId,
) async {
  final base = db
      .collection('TBL_MIGRATIONS_LOGS')
      .where('empresaId', isEqualTo: empresaId);
  QuerySnapshot<Map<String, dynamic>> snap;
  try {
    snap = await base
        .orderBy('createdAt', descending: true)
        .limit(kAdminLogsLimit)
        .get();
  } on FirebaseException catch (e) {
    if (e.code != 'failed-precondition') rethrow;
    snap = await base.limit(kAdminLogsLimit).get();
  }
  return ordenarLogs(
    snap.docs.map((d) => AdminLogEntry.fromMap(d.id, d.data())),
  );
}

class AdminLogsPanel extends StatefulWidget {
  const AdminLogsPanel({super.key, required this.empresaId, this.db});

  final String empresaId;
  final FirebaseFirestore? db;

  @override
  State<AdminLogsPanel> createState() => _AdminLogsPanelState();
}

class _AdminLogsPanelState extends State<AdminLogsPanel> {
  late Future<List<AdminLogEntry>> _logs;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void didUpdateWidget(covariant AdminLogsPanel old) {
    super.didUpdateWidget(old);
    if (old.empresaId != widget.empresaId) _cargar();
  }

  // Antes el FutureBuilder recibía la consulta en cada `build`: cualquier
  // redibujo de Admin volvía a leer la bitácora.
  void _cargar() {
    _page = 0;
    _logs = widget.empresaId.trim().isEmpty
        ? Future.value(const [])
        : cargarLogsAdmin(
            widget.db ?? FirebaseFirestore.instance,
            widget.empresaId,
          );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<AdminLogEntry>>(
      future: _logs,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final encabezado = Row(
          children: [
            const Expanded(
              child: Text(
                'Acciones masivas de Admin en esta empresa: migraciones, '
                'limpiezas, cierres de módulo, Multiempresa y maestros '
                'copiados entre empresas. No incluye '
                'asignar roles, prender apps ni editar personas.',
                style: TextStyle(fontFamily: kArial, color: Colors.black54),
              ),
            ),
            IconButton(
              tooltip: 'Actualizar',
              onPressed: () => setState(_cargar),
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        );
        if (snap.hasError) {
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              encabezado,
              const SizedBox(height: 24),
              Text(
                'No fue posible cargar la bitácora: ${snap.error}',
                style: const TextStyle(fontFamily: kArial),
              ),
            ],
          );
        }
        final logs = snap.data ?? const <AdminLogEntry>[];
        final pagina = _page.clamp(0, pageCountOf(logs.length) - 1);
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            encabezado,
            const SizedBox(height: 12),
            if (logs.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 24),
                child: Center(
                  child: Text(
                    'Sin registros en esta empresa.',
                    style: TextStyle(fontFamily: kArial),
                  ),
                ),
              ),
            for (final log in pageOf(logs, pagina)) ...[
              _LogTile(log: log),
              const SizedBox(height: 8),
            ],
            PagerBar(
              total: logs.length,
              page: pagina,
              etiqueta: 'registros',
              onPageChanged: (p) => setState(() => _page = p),
            ),
          ],
        );
      },
    );
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile({required this.log});
  final AdminLogEntry log;

  @override
  Widget build(BuildContext context) {
    final fecha = log.createdAt == null
        ? 'Registrando…'
        : DateFormat('dd/MM/yyyy HH:mm').format(log.createdAt!);
    final simulacion = log.dryRun;
    return Card(
      child: ListTile(
        leading: UserAvatar(userId: log.adminUserId, radius: 18),
        title: Text(
          log.label,
          style: const TextStyle(
            fontFamily: kArial,
            fontWeight: FontWeight.w800,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            UserNameText(
              log.adminUserId,
              fallbackName: 'Persona sin registro',
              style: const TextStyle(fontFamily: kArial),
            ),
            Text(
              [fecha, if (log.conteo.isNotEmpty) log.conteo].join(' · '),
              style: const TextStyle(fontFamily: kArial, fontSize: 12),
            ),
          ],
        ),
        trailing: Chip(
          visualDensity: VisualDensity.compact,
          backgroundColor: simulacion
              ? const Color(0xFFFFF7ED)
              : const Color(0xFFECFDF5),
          label: Text(
            simulacion ? 'Simulación' : 'Ejecutado',
            style: TextStyle(
              fontFamily: kArial,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: simulacion
                  ? const Color(0xFFB45309)
                  : const Color(0xFF047857),
            ),
          ),
        ),
      ),
    );
  }
}
