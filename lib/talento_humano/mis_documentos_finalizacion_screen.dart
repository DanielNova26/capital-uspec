import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/internal_module_layout.dart';
import 'finalizacion_documentos_service.dart';

const _primary = Color(0xFF0F766E);
const _ink = Color(0xFF17212B);
const _muted = Color(0xFF64748B);
const _border = Color(0xFFE2E8F0);
const _surface = Color(0xFFF8FAFC);
const _success = Color(0xFF15803D);
const _font = 'Arial';

/// Lo que ve el trabajador: sus propios documentos de finalización, nada más.
///
/// Es la parte que pidió Talento Humano para dejar de entregar papeles a mano.
/// Por eso la pantalla no tiene búsqueda ni listado: la cédula sale de la
/// sesión, así que aquí nadie puede mirar la carpeta de otro.
class MisDocumentosFinalizacionScreen extends StatefulWidget {
  final String userId;
  final String empresaId;

  const MisDocumentosFinalizacionScreen({
    super.key,
    required this.userId,
    required this.empresaId,
  });

  @override
  State<MisDocumentosFinalizacionScreen> createState() =>
      _MisDocumentosFinalizacionScreenState();
}

class _MisDocumentosFinalizacionScreenState
    extends State<MisDocumentosFinalizacionScreen> {
  final _service = FinalizacionDocumentosService();

  // Memorizada: recrear la stream en cada build rompe Firestore en web.
  late final Stream<CarpetaFinalizacion?> _carpeta;

  @override
  void initState() {
    super.initState();
    _carpeta = _service.watchPersona(
      empresaId: widget.empresaId,
      cedula: widget.userId,
    );
  }

  @override
  Widget build(BuildContext context) {
    return InternalModuleLayout(
      userId: widget.userId,
      empresaId: widget.empresaId,
      title: 'Documentos de finalización de contrato',
      subtitle: 'Descarga tus documentos cuando estén disponibles',
      accentColor: _primary,
      child: StreamBuilder<CarpetaFinalizacion?>(
        stream: _carpeta,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _Aviso(
              icono: Icons.error_outline_rounded,
              titulo: 'No fue posible cargar tus documentos',
              detalle: snapshot.error.toString(),
            );
          }
          if (!snapshot.hasData && snapshot.connectionState ==
              ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final carpeta = snapshot.data;
          // Sin carpeta y sin marca, no hay nada preparado todavía. Se dice
          // así, y no con una lista vacía: la persona necesita saber que no
          // es un error suyo.
          if (carpeta == null || carpeta.documentos.isEmpty) {
            return const _Aviso(
              icono: Icons.hourglass_empty_rounded,
              titulo: 'Todavía no hay documentos',
              detalle:
                  'Cuando Talento Humano cargue tu carta laboral, tu '
                  'certificado de cesantías o tu orden de exámenes de egreso, '
                  'aparecerán aquí para descargar.',
            );
          }

          final tipos = carpeta.tiposEsperados;
          return ColoredBox(
            color: _surface,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 30),
              child: InternalModuleViewport(
                maxWidth: 760,
                padding: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Encabezado(carpeta: carpeta),
                    const SizedBox(height: 16),
                    for (final tipo in tipos) ...[
                      _DocumentoCard(
                        tipo: tipo,
                        documento: carpeta[tipo],
                      ),
                      const SizedBox(height: 10),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Encabezado extends StatelessWidget {
  final CarpetaFinalizacion carpeta;
  const _Encabezado({required this.carpeta});

  @override
  Widget build(BuildContext context) {
    final listos = carpeta.documentos.length;
    final total = carpeta.tiposEsperados.length;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_primary, Color(0xFF14B8A6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tus documentos',
            style: TextStyle(
              color: Colors.white,
              fontFamily: _font,
              fontSize: 19,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            listos >= total
                ? 'Están los $total documentos que te corresponden.'
                : '$listos de $total disponible(s). Los demás aparecerán '
                      'cuando Talento Humano los cargue.',
            style: const TextStyle(
              color: Color(0xFFD1FAE5),
              fontFamily: _font,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _DocumentoCard extends StatelessWidget {
  final String tipo;
  final DocumentoFinalizacion? documento;

  const _DocumentoCard({required this.tipo, required this.documento});

  @override
  Widget build(BuildContext context) {
    final actual = documento;
    final disponible = actual != null && actual.url.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: (disponible ? _success : _muted).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              disponible
                  ? Icons.description_rounded
                  : Icons.hourglass_bottom_rounded,
              color: disponible ? _success : _muted,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DocumentoFinalizacionTipo.label(tipo),
                  style: const TextStyle(
                    fontFamily: _font,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  disponible
                      ? 'Disponible desde el ${_fecha(actual.subidoAt)}'
                      : 'Aún no está cargado',
                  style: TextStyle(
                    fontFamily: _font,
                    fontSize: 11,
                    color: disponible ? _success : _muted,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  DocumentoFinalizacionTipo.description(tipo),
                  style: const TextStyle(
                    fontFamily: _font,
                    fontSize: 10.5,
                    color: _muted,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: disponible
                ? () => launchUrl(
                    Uri.parse(actual.url),
                    mode: LaunchMode.externalApplication,
                  )
                : null,
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text('Descargar'),
            style: FilledButton.styleFrom(backgroundColor: _primary),
          ),
        ],
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String detalle;

  const _Aviso({
    required this.icono,
    required this.titulo,
    required this.detalle,
  });

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _surface,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icono, size: 58, color: _primary),
                const SizedBox(height: 15),
                Text(
                  titulo,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: _font,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  detalle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: _font,
                    color: _muted,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _fecha(DateTime? value) {
  if (value == null) return 'hace poco';
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${dos(value.day)}/${dos(value.month)}/${value.year}';
}
