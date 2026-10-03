// lib/home/task_correspondencia_preview.dart
//
// Vista previa de la respuesta de una correspondencia dentro del panel de la
// tarea (3 oct 2026).
//
// Antes, tocar una tarea de Gestión de Correspondencia en "Tareas que asigné"
// o "Tareas por aprobar" abría el módulo de correspondencia, y quien debía
// aprobar no veía el panel de la tarea ni el botón Aprobar. Ahora el panel es
// el mismo de cualquier tarea y aquí se ve qué se respondió (o por qué se
// cerró sin respuesta); el expediente completo sigue a un botón de distancia.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../gestion_documental/correspondencia/gd_correspondencia_models.dart';

const String _kFont = 'Arial';

class TaskCorrespondenciaPreview extends StatefulWidget {
  final String expedienteId;

  const TaskCorrespondenciaPreview({super.key, required this.expedienteId});

  @override
  State<TaskCorrespondenciaPreview> createState() =>
      _TaskCorrespondenciaPreviewState();
}

class _TaskCorrespondenciaPreviewState
    extends State<TaskCorrespondenciaPreview> {
  late final Future<GdExpediente?> _expediente = _cargar();
  bool _cuerpoCompleto = false;

  Future<GdExpediente?> _cargar() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('TBL_GD_EXPEDIENTES')
          .doc(widget.expedienteId)
          .get();
      if (!doc.exists) return null;
      return GdExpediente.fromFirestore(doc);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<GdExpediente?>(
      future: _expediente,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: LinearProgressIndicator(minHeight: 2),
          );
        }
        final e = snap.data;
        if (e == null) {
          return _caja(
            color: Colors.blueGrey,
            titulo: 'RESPUESTA',
            children: const [
              Text(
                'No se pudo cargar el expediente. Ábrelo en Gestión de '
                'Correspondencia para revisar la respuesta.',
                style: TextStyle(fontFamily: _kFont, fontSize: 13),
              ),
            ],
          );
        }
        return _contenido(e);
      },
    );
  }

  Widget _contenido(GdExpediente e) {
    final fecha = DateFormat('dd/MM/yyyy HH:mm');
    final codigo = e.codigoInterno.trim().isNotEmpty
        ? e.codigoInterno
        : e.radicado;
    final cuerpo = e.respuestaCuerpo.trim();
    final hayRespuesta = cuerpo.isNotEmpty || e.adjuntosRespuesta.isNotEmpty;
    final String titulo;
    final Color color;
    if (e.respuestaExternaRegistrada) {
      titulo = 'RESPONDIDA FUERA DE LA APP';
      color = const Color(0xFF0F766E);
    } else if (e.enviadoAt != null) {
      titulo = 'RESPUESTA ENVIADA';
      color = const Color(0xFF15803D);
    } else if (e.cierreSinRespuesta) {
      titulo = 'CERRADA SIN RESPUESTA';
      color = const Color(0xFFB45309);
    } else if (hayRespuesta) {
      titulo = 'RESPUESTA EN BORRADOR';
      color = const Color(0xFF1D4ED8);
    } else {
      titulo = 'SIN RESPUESTA REGISTRADA';
      color = Colors.blueGrey;
    }

    final adjuntos = [
      ...e.adjuntosRespuesta,
      ...e.soportesRespuestaExterna,
      ...e.cierreSoportes,
    ];

    return _caja(
      color: color,
      titulo: '$titulo · $codigo',
      children: [
        if (e.enviadoAt != null) _linea('Enviada', fecha.format(e.enviadoAt!)),
        if (e.respuestaDestinatario.trim().isNotEmpty)
          _linea('Para', e.respuestaDestinatario.trim()),
        if (e.respuestaAsunto.trim().isNotEmpty)
          _linea('Asunto', e.respuestaAsunto.trim()),
        if (cuerpo.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            cuerpo,
            maxLines: _cuerpoCompleto ? null : 6,
            overflow: _cuerpoCompleto ? null : TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: _kFont,
              fontSize: 13,
              height: 1.35,
              color: Colors.black87,
            ),
          ),
          if (cuerpo.length > 320 || '\n'.allMatches(cuerpo).length > 5)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () =>
                    setState(() => _cuerpoCompleto = !_cuerpoCompleto),
                child: Text(_cuerpoCompleto ? 'Ver menos' : 'Ver completa'),
              ),
            ),
        ],
        if (e.cierreMotivo.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          _linea('Motivo de cierre', GdMotivoCierre.etiquetaDe(e.cierreMotivo)),
          if (e.cierreJustificacion.trim().isNotEmpty)
            _linea('Justificación', e.cierreJustificacion.trim()),
        ],
        if (adjuntos.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final a in adjuntos)
                ActionChip(
                  avatar: const Icon(Icons.attach_file_rounded, size: 16),
                  label: Text(
                    a.nombre,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: _kFont, fontSize: 12),
                  ),
                  onPressed: a.downloadUrl.trim().startsWith('http')
                      ? () => launchUrlString(
                          a.downloadUrl.trim(),
                          mode: LaunchMode.externalApplication,
                        )
                      : null,
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _linea(String etiqueta, String valor) => Padding(
    padding: const EdgeInsets.only(bottom: 3),
    child: Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$etiqueta: ',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          TextSpan(text: valor),
        ],
      ),
      style: const TextStyle(
        fontFamily: _kFont,
        fontSize: 12.5,
        color: Colors.black87,
      ),
    ),
  );

  Widget _caja({
    required Color color,
    required String titulo,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.mark_email_read_outlined, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  titulo,
                  style: TextStyle(
                    fontFamily: _kFont,
                    fontWeight: FontWeight.w900,
                    fontSize: 10.5,
                    letterSpacing: 0.8,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}
