// lib/compras/compras_aprobaciones.dart
//
// Historial de aprobaciones de Compras.
//
// Hasta ahora cada documento guardaba solo al ÚLTIMO revisor
// (`revisadoPor` + `fechaRevision`): aprobar, revertir y volver a aprobar
// dejaba un único nombre y la pista anterior se perdía. Aquí cada decisión de
// calidad queda como un registro propio en `TBL_COMPRAS_APROBACIONES`, así se
// puede responder "¿quién aprobó esto y cuándo?" aunque después haya cambiado.
//
// La colección es solo de lectura para la app: la escribe el servicio de
// Compras al aprobar, rechazar, requerir o revertir.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../widgets/user_avatar.dart';

const String kComprasAprobacionesColl = 'TBL_COMPRAS_APROBACIONES';

/// Acciones registrables. El valor es el que queda guardado en Firestore.
class ComprasAprobacionAccion {
  static const aprobado = 'aprobado';
  static const aprobadoConRequerimientos = 'aprobado_con_requerimientos';
  static const rechazado = 'rechazado';
  static const consultado = 'consultado';
  static const reversion = 'reversion';
  static const requerimientoResuelto = 'requerimiento_resuelto';
}

class ComprasAprobacion {
  final String id;
  final String empresaId;

  /// recepcion | marca | ficha | proveedor
  final String tipo;
  final String entidadId;
  final String productoId;
  final String productoNombre;
  final String docKey;
  final String docLabel;
  final String accion;
  final String usuarioId;
  final String nota;
  final DateTime? fecha;

  const ComprasAprobacion({
    required this.id,
    required this.empresaId,
    required this.tipo,
    required this.entidadId,
    required this.accion,
    required this.usuarioId,
    this.productoId = '',
    this.productoNombre = '',
    this.docKey = '',
    this.docLabel = '',
    this.nota = '',
    this.fecha,
  });

  factory ComprasAprobacion.fromMap(String id, Map<String, dynamic> m) {
    final raw = m['fecha'];
    return ComprasAprobacion(
      id: id,
      empresaId: (m['empresaId'] ?? '').toString(),
      tipo: (m['tipo'] ?? '').toString(),
      entidadId: (m['entidadId'] ?? '').toString(),
      productoId: (m['productoId'] ?? '').toString(),
      productoNombre: (m['productoNombre'] ?? '').toString(),
      docKey: (m['docKey'] ?? '').toString(),
      docLabel: (m['docLabel'] ?? '').toString(),
      accion: (m['accion'] ?? '').toString(),
      usuarioId: (m['usuarioId'] ?? '').toString(),
      nota: (m['nota'] ?? '').toString(),
      fecha: raw is Timestamp ? raw.toDate() : null,
    );
  }

  String get accionLabel => switch (accion) {
    ComprasAprobacionAccion.aprobado => 'Aprobó',
    ComprasAprobacionAccion.aprobadoConRequerimientos =>
      'Aprobó con requerimientos',
    ComprasAprobacionAccion.rechazado => 'Rechazó',
    ComprasAprobacionAccion.consultado => 'Marcó como consultado',
    ComprasAprobacionAccion.reversion => 'Revirtió la aprobación',
    ComprasAprobacionAccion.requerimientoResuelto => 'Dio por resuelto',
    _ => accion.isEmpty ? 'Registró' : accion,
  };

  Color get accionColor => switch (accion) {
    ComprasAprobacionAccion.aprobado => const Color(0xFF16A34A),
    ComprasAprobacionAccion.aprobadoConRequerimientos => const Color(
      0xFFB45309,
    ),
    ComprasAprobacionAccion.rechazado => const Color(0xFFDC2626),
    ComprasAprobacionAccion.reversion => const Color(0xFFDC2626),
    _ => const Color(0xFF64748B),
  };

  IconData get accionIcono => switch (accion) {
    ComprasAprobacionAccion.aprobado => Icons.check_circle_rounded,
    ComprasAprobacionAccion.aprobadoConRequerimientos =>
      Icons.assignment_late_rounded,
    ComprasAprobacionAccion.rechazado => Icons.cancel_rounded,
    ComprasAprobacionAccion.reversion => Icons.undo_rounded,
    ComprasAprobacionAccion.requerimientoResuelto => Icons.task_alt_rounded,
    _ => Icons.visibility_rounded,
  };
}

/// Línea corta "Aprobado por X · dd/MM/yyyy".
///
/// Se alimenta de lo que ya trae el documento (`revisadoPor`/`fechaRevision`),
/// así que también funciona con lo aprobado antes de existir el historial.
class AprobadoPorLinea extends StatelessWidget {
  final String? revisadoPor;
  final DateTime? fecha;

  /// Texto inicial: "Aprobado", "Rechazado"…
  final String etiqueta;
  final Color color;

  const AprobadoPorLinea({
    super.key,
    required this.revisadoPor,
    required this.fecha,
    this.etiqueta = 'Aprobado',
    this.color = const Color(0xFF16A34A),
  });

  @override
  Widget build(BuildContext context) {
    final userId = (revisadoPor ?? '').trim();
    if (userId.isEmpty && fecha == null) return const SizedBox.shrink();
    final fechaTexto = fecha == null
        ? ''
        : ' · ${DateFormat('dd/MM/yyyy').format(fecha!)}';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.verified_user_rounded, size: 12, color: color),
        const SizedBox(width: 4),
        Text(
          userId.isEmpty ? '$etiqueta$fechaTexto' : '$etiqueta por ',
          style: TextStyle(fontSize: 10.5, color: color, fontFamily: 'Arial'),
        ),
        if (userId.isNotEmpty)
          Flexible(
            child: UserNameText(
              userId,
              style: TextStyle(
                fontSize: 10.5,
                color: color,
                fontWeight: FontWeight.w700,
                fontFamily: 'Arial',
              ),
            ),
          ),
        if (userId.isNotEmpty && fechaTexto.isNotEmpty)
          Text(
            fechaTexto,
            style: TextStyle(fontSize: 10.5, color: color, fontFamily: 'Arial'),
          ),
      ],
    );
  }
}

/// Botón que abre el historial completo de decisiones de un documento
/// o de toda una entidad (recepción, proveedor, ficha).
class HistorialAprobacionesBoton extends StatelessWidget {
  final String entidadId;
  final String? docKey;
  final String titulo;
  final bool compacto;

  const HistorialAprobacionesBoton({
    super.key,
    required this.entidadId,
    this.docKey,
    this.titulo = 'Historial de aprobaciones',
    this.compacto = true,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () => mostrarHistorialAprobaciones(
        context,
        entidadId: entidadId,
        docKey: docKey,
        titulo: titulo,
      ),
      icon: const Icon(Icons.history_rounded, size: 14),
      label: Text(
        compacto ? 'Historial' : titulo,
        style: const TextStyle(fontSize: 11, fontFamily: 'Arial'),
      ),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(0, 30),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

Future<void> mostrarHistorialAprobaciones(
  BuildContext context, {
  required String entidadId,
  String? docKey,
  String titulo = 'Historial de aprobaciones',
}) {
  final ancho = MediaQuery.sizeOf(context).width;
  final contenido = _HistorialAprobacionesLista(
    entidadId: entidadId,
    docKey: docKey,
  );

  if (ancho >= 900) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          titulo,
          style: const TextStyle(
            fontFamily: 'Arial',
            fontWeight: FontWeight.w800,
          ),
        ),
        content: SizedBox(width: 520, height: 420, child: contenido),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (_, controller) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              titulo,
              style: const TextStyle(
                fontFamily: 'Arial',
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
          ),
          Expanded(
            child: _HistorialAprobacionesLista(
              entidadId: entidadId,
              docKey: docKey,
              controller: controller,
            ),
          ),
        ],
      ),
    ),
  );
}

class _HistorialAprobacionesLista extends StatelessWidget {
  final String entidadId;
  final String? docKey;
  final ScrollController? controller;

  const _HistorialAprobacionesLista({
    required this.entidadId,
    this.docKey,
    this.controller,
  });

  @override
  Widget build(BuildContext context) {
    // Consulta por igualdad sobre un solo campo: no necesita índice compuesto.
    // El orden y el filtro por documento se resuelven en memoria porque un
    // expediente no acumula tantos eventos como para que pese.
    final stream = FirebaseFirestore.instance
        .collection(kComprasAprobacionesColl)
        .where('entidadId', isEqualTo: entidadId)
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.hasError) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('No se pudo cargar el historial.'),
            ),
          );
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final key = (docKey ?? '').trim();
        final items =
            snap.data!.docs
                .map((d) => ComprasAprobacion.fromMap(d.id, d.data()))
                .where((a) => key.isEmpty || a.docKey == key)
                .toList()
              ..sort((a, b) {
                final fa = a.fecha;
                final fb = b.fecha;
                if (fa == null && fb == null) return 0;
                if (fa == null) return 1;
                if (fb == null) return -1;
                return fb.compareTo(fa);
              });

        if (items.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Todavía no hay decisiones registradas para este documento.\n'
                'Lo aprobado antes de activar el historial conserva su '
                'revisor en la ficha del documento.',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Arial', fontSize: 12),
              ),
            ),
          );
        }

        return ListView.separated(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
          itemCount: items.length,
          separatorBuilder: (_, __) => const Divider(height: 12),
          itemBuilder: (_, i) => _EventoTile(evento: items[i]),
        );
      },
    );
  }
}

class _EventoTile extends StatelessWidget {
  final ComprasAprobacion evento;

  const _EventoTile({required this.evento});

  @override
  Widget build(BuildContext context) {
    final fecha = evento.fecha;
    final subtitulo = [
      if (evento.docLabel.isNotEmpty) evento.docLabel,
      if (evento.productoNombre.isNotEmpty) evento.productoNombre,
    ].join(' · ');

    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: UserAvatar(userId: evento.usuarioId, radius: 17),
      title: Row(
        children: [
          Icon(evento.accionIcono, size: 14, color: evento.accionColor),
          const SizedBox(width: 5),
          Expanded(
            child: UserNameText(
              evento.usuarioId,
              style: const TextStyle(
                fontFamily: 'Arial',
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            evento.accionLabel,
            style: TextStyle(
              fontFamily: 'Arial',
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: evento.accionColor,
            ),
          ),
          if (subtitulo.isNotEmpty)
            Text(
              subtitulo,
              style: const TextStyle(
                fontFamily: 'Arial',
                fontSize: 11,
                color: Colors.black54,
              ),
            ),
          if (evento.nota.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                evento.nota.trim(),
                style: const TextStyle(
                  fontFamily: 'Arial',
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  color: Colors.black87,
                ),
              ),
            ),
        ],
      ),
      trailing: fecha == null
          ? null
          : Text(
              DateFormat('dd/MM/yy\nHH:mm').format(fecha),
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontFamily: 'Arial',
                fontSize: 10,
                color: Colors.black45,
              ),
            ),
    );
  }
}
