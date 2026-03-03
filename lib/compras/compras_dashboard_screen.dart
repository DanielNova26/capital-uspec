// lib/compras/compras_req_excel_parser.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'web_drag_drop.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';

import 'compras_models.dart';
import 'compras_service.dart';
import 'compras_req_engine.dart';

// ══════════════════════════════════════════════════════════════════════════════
// COLORES DEL MÓDULO
// ══════════════════════════════════════════════════════════════════════════════

const Color kComprasPrimary = Color(0xFF1565C0);   // Blue 800
const Color kComprasAccent  = Color(0xFF42A5F5);   // Blue 300
const Color kComprasBg      = Color(0xFFF0F4FF);   // Fondo azul muy claro
const Color kComprasCard    = Colors.white;
const Color kComprasGreen   = Color(0xFF16A34A);
const Color kComprasRed     = Color(0xFFDC2626);
const String _kFont = 'Arial';

// ══════════════════════════════════════════════════════════════════════════════
// HELPERS
// ══════════════════════════════════════════════════════════════════════════════

/// Busca en kDepartamentos el valor que coincida con [raw] ignorando
/// mayúsculas/minúsculas y tildes. Devuelve null si no hay coincidencia,
/// lo que evita el crash del DropdownButtonFormField cuando el valor
/// almacenado tiene variante de acento diferente (ej. "Antioquía" vs "Antioquia").
String? _matchDepartamento(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  String strip(String s) => s
      .trim()
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ü', 'u')
      .replaceAll('ñ', 'n');
  final canon = strip(raw);
  for (final d in kDepartamentos) {
    if (strip(d) == canon) return d;
  }
  return null; // no match → dropdown queda vacío, sin crash
}

String _normalizarNombre(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return trimmed;
  return trimmed.split(RegExp(r'\s+')).map((w) {
    if (w.isEmpty) return w;
    return w[0].toUpperCase() + (w.length > 1 ? w.substring(1) : '');
  }).join(' ');
}

String _normalizarUM(String input) {
  return input.trim();
}

String _fmtFecha(Timestamp ts) {
  return DateFormat('dd/MM/yyyy', 'es').format(ts.toDate());
}

String _fmtFechaHora(Timestamp ts) {
  return DateFormat('dd/MM/yyyy HH:mm', 'es').format(ts.toDate());
}


List<String> docsParaCategoria(String? categoria) {
  final cat = (categoria ?? '').trim().toLowerCase();

  // Puente de compatibilidad: hasta terminar la migración completa al motor
  // dinámico (ReqEngine), usamos un subconjunto por categoría para evitar
  // sobre-exigir documentos en vistas históricas/resumen.
  final base = <String>[
    'certCalidad',
    'fichaTecnica',
    'evidenciaEtiqueta',
    'fechaVencimientoEtiqueta',
  ];

  final proteina = <String>[
    'guiaTransporte',
    'guiaSacrificio',
    'permisoZoo',
    'vistoInvima',
    'declImport',
    'docTransporte',
  ];

  final aseo = <String>[
    'hojaSeguridad',
    'sustanciasPermitidas',
    'rotuladoSGA',
  ];

  final fruver = <String>[
    'permisoZoo',
    'vistoInvima',
    'declImport',
  ];

  final merged = <String>[...base];
  if (cat.contains('prote')) merged.addAll(proteina);
  if (cat.contains('aseo')) merged.addAll(aseo);
  if (cat.contains('fruv')) merged.addAll(fruver);

  if (merged.length == base.length) {
    // Categoría no clasificada: mantener solo documentos universales.
    merged.addAll([
      'guiaTransporte',
      'docTransporte',
    ]);
  }

  // Únicos + existentes en mapa de etiquetas para evitar llaves inválidas.
  final uniques = <String>[];
  for (final key in merged) {
    if (!kDocRecepcionLabels.containsKey(key)) continue;
    if (!uniques.contains(key)) uniques.add(key);
  }
  return uniques;
}

// ══════════════════════════════════════════════════════════════════════════════
// COMPRAS DASHBOARD SCREEN — pantalla principal (hub)
// ══════════════════════════════════════════════════════════════════════════════

class ComprasDashboardScreen extends StatelessWidget {
  final String userId;
  final String empresaId;
  /// Rol del usuario: 'calidad' | 'compras' | 'bodega' | null (sin restricción)
  final String? rolCompras;

  const ComprasDashboardScreen({
    super.key,
    required this.userId,
    required this.empresaId,
    this.rolCompras,
  });

  bool get _esBodega => rolCompras == kRolBodega;
  bool get _esCalidad => rolCompras == kRolCalidad;
  bool get _esCompras => rolCompras == kRolCompras;
  bool get _soloRecepcion => _esBodega;

  @override
  Widget build(BuildContext context) {
    final svc = ComprasService();

    String subtituloRol = 'Gestión de proveedores, productos y recepciones';
    Color colorRol = kComprasPrimary;
    if (_esBodega) {
      subtituloRol = 'Recepción de mercancía';
      colorRol = const Color(0xFF0277BD);
    } else if (_esCalidad) {
      subtituloRol = 'Calidad — revisión y aprobación de documentos';
      colorRol = const Color(0xFF15803D);
    } else if (_esCompras) {
      subtituloRol = 'Compras — gestión de proveedores y productos';
      colorRol = kComprasPrimary;
    }

    final isDesktop = kIsWeb && MediaQuery.of(context).size.width > 800;

    if (isDesktop) {
      return _buildWebLayout(context, svc, subtituloRol, colorRol);
    }

    return Scaffold(
      backgroundColor: kComprasBg,
      appBar: AppBar(
        title: const Text('Compras & Bodega',
            style: TextStyle(fontFamily: _kFont, fontWeight: FontWeight.bold)),
        backgroundColor: kComprasPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Módulo de Compras',
                  style: TextStyle(
                      fontFamily: _kFont,
                      fontSize: 13,
                      color: Colors.blueGrey.shade400)),
              const SizedBox(height: 4),
              Text(subtituloRol,
                  style: TextStyle(
                      fontFamily: _kFont,
                      fontSize: 16,
                      color: colorRol)),
              const SizedBox(height: 24),
              if (!_soloRecepcion) ...[
                _MenuTile(
                  icon: Icons.business,
                  titulo: 'Proveedores',
                  subtitulo: 'Registrar y gestionar proveedores',
                  color: const Color(0xFF1565C0),
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => _ProveedoresScreen(empresaId: empresaId, svc: svc))),
                ),
                const SizedBox(height: 14),
                _MenuTile(
                  icon: Icons.label_important,
                  titulo: 'Marcas',
                  subtitulo: 'Gestionar marcas vinculadas a productos',
                  color: const Color(0xFF1976D2),
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => _MarcasScreen(empresaId: empresaId, svc: svc))),
                ),
                const SizedBox(height: 14),
                _MenuTile(
                  icon: Icons.inventory_2,
                  titulo: 'Productos',
                  subtitulo: 'Catálogo de productos del almacén',
                  color: const Color(0xFF0277BD),
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => _ProductosScreen(empresaId: empresaId, svc: svc, userId: userId))),
                ),
                const SizedBox(height: 14),
              ],
              _MenuTile(
                icon: Icons.local_shipping,
                titulo: 'Recepción de Mercancía',
                subtitulo: 'Registrar llegada de proveedores con documentos',
                color: kComprasPrimary,
                onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => _RecepcionesScreen(empresaId: empresaId, svc: svc, userId: userId))),
              ),
              if (!_soloRecepcion) ...[
                const SizedBox(height: 14),
                _MenuTile(
                  icon: Icons.manage_search,
                  titulo: 'Consultas',
                  subtitulo: 'Consultar por proveedor o producto',
                  color: const Color(0xFF283593),
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => _ConsultasScreen(empresaId: empresaId, svc: svc))),
                ),
              ],
              if (_esCalidad) ...[
                const SizedBox(height: 14),
                _MenuTile(
                  icon: Icons.verified_user,
                  titulo: 'Revisión de Calidad',
                  subtitulo: 'Aprobar o rechazar documentos de recepción',
                  color: const Color(0xFF15803D),
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => _CalidadScreen(empresaId: empresaId, svc: svc, userId: userId))),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWebLayout(BuildContext context, ComprasService svc,
      String subtituloRol, Color colorRol) {
    final scheme = Theme.of(context).colorScheme;

    Widget card({
      required IconData icon,
      required String titulo,
      required String subtitulo,
      required Color color,
      required VoidCallback onTap,
    }) {
      return SizedBox(
        width: 420,
        child: Card(
          elevation: 2,
          shadowColor: color.withOpacity(0.18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            hoverColor: color.withOpacity(0.05),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(icon, color: color, size: 27),
                  ),
                  const SizedBox(height: 16),
                  Text(titulo,
                      style: TextStyle(
                          fontFamily: _kFont,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: color)),
                  const SizedBox(height: 5),
                  Text(subtitulo,
                      style: const TextStyle(
                          fontFamily: _kFont,
                          fontSize: 12,
                          color: Colors.black54)),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: Column(
        children: [
          // Header
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1565C0), Color(0xFF1E88E5)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            padding: const EdgeInsets.fromLTRB(40, 32, 40, 32),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.shopping_cart_outlined,
                      color: Colors.white, size: 32),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Compras & Bodega',
                          style: TextStyle(
                              fontFamily: _kFont,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.white)),
                      const SizedBox(height: 4),
                      Text(subtituloRol,
                          style: TextStyle(
                              fontFamily: _kFont,
                              fontSize: 13,
                              color: Colors.white.withOpacity(0.85))),
                    ],
                  ),
                ),
                if (rolCompras != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: Colors.white.withOpacity(0.4), width: 1),
                    ),
                    child: Text(
                      rolCompras!.toUpperCase(),
                      style: const TextStyle(
                          fontFamily: _kFont,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 1),
                    ),
                  ),
              ],
            ),
          ),
          // Cards
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Wrap(
                    spacing: 20,
                    runSpacing: 20,
                    children: [
                      if (!_soloRecepcion) ...[
                        card(
                          icon: Icons.business,
                          titulo: 'Proveedores',
                          subtitulo: 'Registrar y gestionar proveedores',
                          color: const Color(0xFF1565C0),
                          onTap: () => Navigator.push(context, MaterialPageRoute(
                              builder: (_) => _ProveedoresScreen(
                                  empresaId: empresaId, svc: svc))),
                        ),
                        card(
                          icon: Icons.label_important,
                          titulo: 'Marcas',
                          subtitulo: 'Gestionar marcas vinculadas a productos',
                          color: const Color(0xFF1976D2),
                          onTap: () => Navigator.push(context, MaterialPageRoute(
                              builder: (_) =>
                                  _MarcasScreen(empresaId: empresaId, svc: svc))),
                        ),
                        card(
                          icon: Icons.inventory_2,
                          titulo: 'Productos',
                          subtitulo: 'Catálogo de productos del almacén',
                          color: const Color(0xFF0277BD),
                          onTap: () => Navigator.push(context, MaterialPageRoute(
                              builder: (_) => _ProductosScreen(
                                  empresaId: empresaId, svc: svc, userId: userId))),
                        ),
                      ],
                      card(
                        icon: Icons.local_shipping,
                        titulo: 'Recepción de Mercancía',
                        subtitulo:
                            'Registrar llegada de proveedores con documentos',
                        color: kComprasPrimary,
                        onTap: () => Navigator.push(context, MaterialPageRoute(
                            builder: (_) => _RecepcionesScreen(
                                empresaId: empresaId,
                                svc: svc,
                                userId: userId))),
                      ),
                      if (!_soloRecepcion)
                        card(
                          icon: Icons.manage_search,
                          titulo: 'Consultas',
                          subtitulo: 'Consultar por proveedor o producto',
                          color: const Color(0xFF283593),
                          onTap: () => Navigator.push(context, MaterialPageRoute(
                              builder: (_) => _ConsultasScreen(
                                  empresaId: empresaId, svc: svc))),
                        ),
                      if (_esCalidad)
                        card(
                          icon: Icons.verified_user,
                          titulo: 'Revisión de Calidad',
                          subtitulo:
                              'Aprobar o rechazar documentos de recepción',
                          color: const Color(0xFF15803D),
                          onTap: () => Navigator.push(context, MaterialPageRoute(
                              builder: (_) => _CalidadScreen(
                                  empresaId: empresaId,
                                  svc: svc,
                                  userId: userId))),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// BADGE DE NOTIFICACIONES
// ══════════════════════════════════════════════════════════════════════════════

class _NotifBadge extends StatelessWidget {
  final String empresaId;
  final String userId;
  final ComprasService svc;

  const _NotifBadge({
    required this.empresaId,
    required this.userId,
    required this.svc,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<NotificacionComprasDoc>>(
      stream: svc.streamNotificaciones(empresaId, userId),
      builder: (ctx, snap) {
        final count = snap.data?.length ?? 0;
        return Stack(
          children: [
            IconButton(
              icon: const Icon(Icons.notifications_outlined),
              onPressed: count == 0
                  ? null
                  : () => _mostrarNotificaciones(context, snap.data ?? []),
              tooltip: 'Notificaciones de calidad',
            ),
            if (count > 0)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: const BoxDecoration(
                      color: Colors.red, shape: BoxShape.circle),
                  child: Center(
                    child: Text('$count',
                        style: const TextStyle(
                            fontSize: 10,
                            color: Colors.white,
                            fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  void _mostrarNotificaciones(
      BuildContext context, List<NotificacionComprasDoc> notifs) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _NotifSheet(
        notifs: notifs,
        svc: svc,
      ),
    );
  }
}

class _NotifSheet extends StatelessWidget {
  final List<NotificacionComprasDoc> notifs;
  final ComprasService svc;

  const _NotifSheet({required this.notifs, required this.svc});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      builder: (_, scrollCtrl) => ListView(
        controller: scrollCtrl,
        padding: const EdgeInsets.all(16),
        children: [
          const Center(
            child: Text('Notificaciones de Calidad',
                style: TextStyle(
                    fontFamily: _kFont,
                    fontSize: 17,
                    fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 12),
          ...notifs.map((n) => Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.cancel, color: Colors.red, size: 18),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text('Documento rechazado',
                                style: const TextStyle(
                                    fontFamily: _kFont,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text('Producto: ${n.productoNombre}',
                          style: const TextStyle(
                              fontFamily: _kFont, fontSize: 13)),
                      Text('Documento: ${n.docLabel}',
                          style: const TextStyle(
                              fontFamily: _kFont,
                              fontSize: 12,
                              color: Colors.black54)),
                      Text('Motivo: ${n.motivo}',
                          style: const TextStyle(
                              fontFamily: _kFont,
                              fontSize: 12,
                              fontStyle: FontStyle.italic)),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () async {
                            await svc.marcarNotificacionLeida(n.id);
                            if (context.mounted) Navigator.pop(context);
                          },
                          child: const Text('Marcar como leída',
                              style: TextStyle(fontFamily: _kFont)),
                        ),
                      ),
                    ],
                  ),
                ),
              )),
          if (notifs.isNotEmpty)
            TextButton.icon(
              onPressed: () async {
                if (notifs.isNotEmpty) {
                  await svc.marcarTodasLeidas(
                      notifs.first.empresaId, notifs.first.userId);
                  if (context.mounted) Navigator.pop(context);
                }
              },
              icon: const Icon(Icons.done_all),
              label: const Text('Marcar todas como leídas',
                  style: TextStyle(fontFamily: _kFont)),
            ),
        ],
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String titulo;
  final String subtitulo;
  final Color color;
  final VoidCallback onTap;

  const _MenuTile({
    required this.icon,
    required this.titulo,
    required this.subtitulo,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 2,
      shadowColor: color.withOpacity(0.2),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo,
                        style: TextStyle(
                            fontFamily: _kFont,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: color)),
                    const SizedBox(height: 3),
                    Text(subtitulo,
                        style: const TextStyle(
                            fontFamily: _kFont,
                            fontSize: 13,
                            color: Colors.black54)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: color.withOpacity(0.5)),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SCANNER SHEET — escáner de documentos con cámara → PDF
// ══════════════════════════════════════════════════════════════════════════════

class _ScannerSheet extends StatefulWidget {
  final String empresaId;
  final String carpeta;
  final String nombreSugerido;
  final ComprasService svc;

  const _ScannerSheet({
    required this.empresaId,
    required this.carpeta,
    required this.nombreSugerido,
    required this.svc,
  });

  @override
  State<_ScannerSheet> createState() => _ScannerSheetState();
}

class _ScannerSheetState extends State<_ScannerSheet> {
  final List<Uint8List> _imagenes = [];
  bool _subiendo = false;
  final _picker = ImagePicker();
  bool _isDragging = false;
  StreamSubscription<bool>? _wDragSub;
  StreamSubscription<DroppedFile>? _wFileSub;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      WebDragDrop.instance.enable();
      _wDragSub = WebDragDrop.instance.isDragging
          .listen((v) { if (mounted) setState(() => _isDragging = v); });
      _wFileSub = WebDragDrop.instance.droppedFile.listen(_onWebFileDrop);
    }
  }

  @override
  void dispose() {
    if (kIsWeb) WebDragDrop.instance.disable();
    _wDragSub?.cancel();
    _wFileSub?.cancel();
    super.dispose();
  }

  Future<void> _tomarFoto() async {
    final img = await _picker.pickImage(
        source: ImageSource.camera, imageQuality: 80);
    if (img != null) {
      final bytes = await img.readAsBytes();
      setState(() => _imagenes.add(bytes));
    }
  }

  Future<void> _desdeGaleria() async {
    final imgs = await _picker.pickMultiImage(imageQuality: 80);
    for (final img in imgs) {
      final bytes = await img.readAsBytes();
      setState(() => _imagenes.add(bytes));
    }
  }

  Future<void> _desdeArchivo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) return;
    final nombre = file.name;
    final contentType =
        nombre.toLowerCase().endsWith('.pdf') ? 'application/pdf' : 'image/jpeg';
    setState(() => _subiendo = true);
    try {
      final doc = await widget.svc.subirBytes(
        bytes: file.bytes!,
        empresaId: widget.empresaId,
        carpeta: widget.carpeta,
        nombre: nombre,
        contentType: contentType,
      );
      if (mounted) Navigator.pop(context, doc);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al subir archivo: $e')));
      }
    } finally {
      if (mounted) setState(() => _subiendo = false);
    }
  }

  Future<Uint8List> _imagenesToPdf() async {
    final doc = pw.Document();
    for (final imgBytes in _imagenes) {
      final pdfImg = pw.MemoryImage(imgBytes);
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(16),
          build: (ctx) => pw.Center(
            child: pw.Image(pdfImg, fit: pw.BoxFit.contain),
          ),
        ),
      );
    }
    return doc.save();
  }

  Future<void> _convertirYSubir() async {
    if (_imagenes.isEmpty) return;
    setState(() => _subiendo = true);
    try {
      final pdfBytes = await _imagenesToPdf();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final nombre = '${widget.nombreSugerido}_$ts.pdf';
      final doc = await widget.svc.subirBytes(
        bytes: pdfBytes,
        empresaId: widget.empresaId,
        carpeta: widget.carpeta,
        nombre: nombre,
        contentType: 'application/pdf',
      );
      if (mounted) Navigator.pop(context, doc);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al convertir PDF: $e')));
      }
    } finally {
      if (mounted) setState(() => _subiendo = false);
    }
  }

  // Zona drag-and-drop visible en web cuando no hay imágenes
  Widget _buildWebDropZoneArea(ScrollController scrollCtrl) {
    // Zona de arrastre + botón separado para abrir selector de archivo.
    // El DropzoneView (HTML) captura eventos HTML5 drag; el botón queda fuera
    // de esa área para que Flutter lo reciba correctamente en CanvasKit.
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        children: [
          // Zona de arrastre
          Expanded(
            child: DropTarget(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: _isDragging
                      ? kComprasPrimary.withOpacity(0.07)
                      : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _isDragging
                        ? kComprasPrimary
                        : Colors.grey.shade300,
                    width: _isDragging ? 2 : 1.5,
                  ),
                ),
                child: _subiendo
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const CircularProgressIndicator(
                              color: kComprasPrimary),
                          const SizedBox(height: 16),
                          Text('Convirtiendo y subiendo como PDF…',
                              style: TextStyle(
                                  fontFamily: _kFont,
                                  color: Colors.grey.shade600)),
                        ],
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.cloud_upload_outlined,
                              size: 64,
                              color: _isDragging
                                  ? kComprasPrimary
                                  : Colors.grey.shade300),
                          const SizedBox(height: 14),
                          Text(
                            _isDragging
                                ? '¡Suelta el archivo aquí!'
                                : 'Arrastra el archivo aquí',
                            style: TextStyle(
                                fontFamily: _kFont,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: _isDragging
                                    ? kComprasPrimary
                                    : Colors.black54),
                          ),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'PDF · JPG · PNG — Se guarda como PDF',
                              style: TextStyle(
                                  fontFamily: _kFont,
                                  fontSize: 11,
                                  color: Colors.grey.shade500),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
          // Botón separado para abrir selector de archivo
          if (!_subiendo) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _desdeArchivo,
                icon: const Icon(Icons.folder_open, size: 16),
                label: const Text('o seleccionar archivo (PDF/img)',
                    style: TextStyle(fontFamily: _kFont)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: kComprasPrimary,
                  side: const BorderSide(color: kComprasPrimary),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  // Recibe archivo arrastrado vía dart:html y lo procesa
  Future<void> _onWebFileDrop(DroppedFile file) async {
    if (!mounted) return;
    final name = file.name;
    final ext = name.toLowerCase().split('.').last;
    if (!['pdf', 'jpg', 'jpeg', 'png'].contains(ext)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Solo se permiten PDF, JPG o PNG',
                style: TextStyle(fontFamily: _kFont))));
      }
      return;
    }
    final bytes = file.bytes;
    if (ext == 'pdf') {
      // PDF: subir directamente
      setState(() => _subiendo = true);
      try {
        final doc = await widget.svc.subirBytes(
          bytes: bytes,
          empresaId: widget.empresaId,
          carpeta: widget.carpeta,
          nombre: name,
          contentType: 'application/pdf',
        );
        if (mounted) Navigator.pop(context, doc);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error al subir: $e')));
        }
      } finally {
        if (mounted) setState(() => _subiendo = false);
      }
    } else {
      // Imagen: agregar a la lista y convertir a PDF
      setState(() => _imagenes.add(bytes));
      await _convertirYSubir();
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.45,
      expand: false,
      builder: (ctx, scrollCtrl) => Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Icon(Icons.document_scanner, color: kComprasPrimary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Adjuntar Documento',
                      style: TextStyle(
                          fontFamily: _kFont,
                          fontSize: 17,
                          fontWeight: FontWeight.bold)),
                ),
                IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close)),
              ],
            ),
          ),
          const Divider(height: 1),
          // Thumbnails / Drag zone
          Expanded(
            child: _imagenes.isEmpty
                ? (kIsWeb
                    ? _buildWebDropZoneArea(scrollCtrl)
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.camera_alt_outlined,
                              size: 56, color: Colors.grey.shade300),
                          const SizedBox(height: 12),
                          Text('Sin imágenes capturadas',
                              style: TextStyle(
                                  fontFamily: _kFont,
                                  color: Colors.grey.shade500)),
                          const SizedBox(height: 6),
                          Text('Usa la cámara o selecciona un archivo',
                              style: TextStyle(
                                  fontFamily: _kFont,
                                  fontSize: 12,
                                  color: Colors.grey.shade400)),
                        ],
                      ))
                : (_subiendo && kIsWeb
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const CircularProgressIndicator(color: kComprasPrimary),
                          const SizedBox(height: 16),
                          Text('Convirtiendo y subiendo como PDF…',
                              style: TextStyle(
                                  fontFamily: _kFont,
                                  color: Colors.grey.shade600)),
                        ],
                      )
                    : GridView.builder(
                        controller: scrollCtrl,
                        padding: const EdgeInsets.all(12),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                        itemCount: _imagenes.length,
                        itemBuilder: (ctx, i) => ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.memory(_imagenes[i], fit: BoxFit.cover),
                              Positioned(
                                top: 6,
                                right: 6,
                                child: GestureDetector(
                                  onTap: () =>
                                      setState(() => _imagenes.removeAt(i)),
                                  child: Container(
                                    decoration: const BoxDecoration(
                                        color: Colors.red,
                                        shape: BoxShape.circle),
                                    padding: const EdgeInsets.all(3),
                                    child: const Icon(Icons.close,
                                        size: 14, color: Colors.white),
                                  ),
                                ),
                              ),
                              Positioned(
                                bottom: 6,
                                left: 6,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text('Pág. ${i + 1}',
                                      style: const TextStyle(
                                          fontSize: 10, color: Colors.white)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )),
          ),
          // Botones
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            decoration: const BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                    color: Colors.black12,
                    blurRadius: 6,
                    offset: Offset(0, -2))
              ],
            ),
            child: kIsWeb
                ? Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _subiendo ? null : _desdeArchivo,
                          icon: const Icon(Icons.upload_file, size: 18),
                          label: const Text('Seleccionar archivo (PDF/img)',
                              style: TextStyle(fontFamily: _kFont)),
                          style: OutlinedButton.styleFrom(
                              foregroundColor: kComprasPrimary,
                              side: const BorderSide(color: kComprasPrimary)),
                        ),
                      ),
                      if (_imagenes.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed:
                                (_subiendo || _imagenes.isEmpty) ? null : _convertirYSubir,
                            icon: _subiendo
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.picture_as_pdf, size: 18),
                            label: Text(
                                _subiendo
                                    ? 'Subiendo…'
                                    : 'PDF (${_imagenes.length} pág.)',
                                style: const TextStyle(fontFamily: _kFont)),
                            style: FilledButton.styleFrom(
                                backgroundColor: kComprasPrimary),
                          ),
                        ),
                      ],
                    ],
                  )
                : Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _subiendo ? null : _tomarFoto,
                              icon: const Icon(Icons.camera_alt, size: 18),
                              label: const Text('Cámara',
                                  style: TextStyle(fontFamily: _kFont)),
                              style: OutlinedButton.styleFrom(
                                  foregroundColor: kComprasPrimary,
                                  side: const BorderSide(
                                      color: kComprasPrimary)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _subiendo ? null : _desdeGaleria,
                              icon: const Icon(Icons.photo_library, size: 18),
                              label: const Text('Galería',
                                  style: TextStyle(fontFamily: _kFont)),
                              style: OutlinedButton.styleFrom(
                                  foregroundColor: kComprasPrimary,
                                  side: const BorderSide(
                                      color: kComprasPrimary)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _subiendo ? null : _desdeArchivo,
                              icon: const Icon(Icons.attach_file, size: 18),
                              label: const Text('Archivo (PDF/img)',
                                  style: TextStyle(fontFamily: _kFont)),
                              style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.grey.shade700),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: (_subiendo || _imagenes.isEmpty)
                                  ? null
                                  : _convertirYSubir,
                              icon: _subiendo
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white))
                                  : const Icon(Icons.picture_as_pdf, size: 18),
                              label: Text(
                                  _subiendo
                                      ? 'Subiendo...'
                                      : 'PDF (${_imagenes.length} pág.)',
                                  style:
                                      const TextStyle(fontFamily: _kFont)),
                              style: FilledButton.styleFrom(
                                  backgroundColor: kComprasPrimary),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

Future<DocAdjunto?> _mostrarEscaneador(
  BuildContext context, {
  required String empresaId,
  required String carpeta,
  required String nombreSugerido,
  required ComprasService svc,
}) async {
  return showModalBottomSheet<DocAdjunto>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _ScannerSheet(
      empresaId: empresaId,
      carpeta: carpeta,
      nombreSugerido: nombreSugerido,
      svc: svc,
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// DOC ATTACH BUTTON — botón reutilizable para adjuntar documentos
// ══════════════════════════════════════════════════════════════════════════════

/// Archivo en espera de ser combinado/subido (solo web).
class _PendingFile {
  final Uint8List bytes;
  final String name;
  const _PendingFile(this.bytes, this.name);
  bool get isPdf => name.toLowerCase().endsWith('.pdf');
}

class _DocAttachButton extends StatefulWidget {
  final String label;
  final DocAdjunto? doc;
  final bool required_;
  final bool uploading;
  final VoidCallback onAttach;
  final VoidCallback? onView;
  /// Solo web: callback que recibe bytes + nombre y sube el archivo.
  /// El caller es responsable de actualizar su estado con el DocAdjunto resultante.
  final Future<void> Function(Uint8List bytes, String name)? onWebUpload;

  /// Solo web: elimina el documento ya adjunto (limpia la referencia en el estado del padre).
  final VoidCallback? onDelete;

  const _DocAttachButton({
    required this.label,
    required this.doc,
    this.required_ = false,
    this.uploading = false,
    required this.onAttach,
    this.onView,
    this.onWebUpload,
    this.onDelete,
  });

  @override
  State<_DocAttachButton> createState() => _DocAttachButtonState();
}

class _DocAttachButtonState extends State<_DocAttachButton> {
  bool _isDragging = false;
  bool _webUploading = false;
  // Drag-and-drop web
  final _dropKey = GlobalKey();
  StreamSubscription<bool>? _wDragSub;
  StreamSubscription<DroppedFile>? _wFileSub;

  /// Archivos en espera de combinarse y subir (solo web).
  final List<_PendingFile> _pending = [];
  bool _combining = false;

  static const int _maxBytes = 10 * 1024 * 1024; // 10 MB

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      WebDragDrop.instance.enable();
      _wDragSub = WebDragDrop.instance.isDragging
          .listen((v) { if (mounted) setState(() => _isDragging = v); });
      _wFileSub = WebDragDrop.instance.droppedFile.listen(_onWebFileDrop);
    }
  }

  @override
  void dispose() {
    if (kIsWeb) WebDragDrop.instance.disable();
    _wDragSub?.cancel();
    _wFileSub?.cancel();
    super.dispose();
  }

  /// Recibe archivo arrastrado; lo agrega a la cola de pendientes si el cursor
  /// cayó sobre este widget.
  void _onWebFileDrop(DroppedFile file) {
    if (!mounted || _isUploading || _combining || widget.onWebUpload == null) return;
    // Verificar que el drop ocurrió dentro de los límites de este widget
    final rb = _dropKey.currentContext?.findRenderObject() as RenderBox?;
    if (rb != null) {
      final topLeft = rb.localToGlobal(Offset.zero);
      final bounds = topLeft & rb.size;
      if (!bounds.contains(WebDragDrop.instance.lastDropPosition)) return;
    }
    final name = file.name;
    final ext = name.toLowerCase().split('.').last;
    if (!['pdf', 'jpg', 'jpeg', 'png'].contains(ext)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Solo se permiten PDF, JPG o PNG',
                style: TextStyle(fontFamily: _kFont))));
      }
      return;
    }
    if (file.bytes.length > _maxBytes) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('El archivo supera el límite de 10 MB',
                style: TextStyle(fontFamily: _kFont))));
      }
      return;
    }
    setState(() => _pending.add(_PendingFile(file.bytes, name)));
  }

  Color get _borderColor {
    if (widget.doc?.pendiente == true) return Colors.orange;
    if (widget.doc?.aprobado == true) return kComprasGreen;
    if (widget.doc?.rechazado == true) return kComprasRed;
    if (widget.doc?.tieneDoc == true) return kComprasGreen;
    return Colors.grey.shade300;
  }

  Color get _iconColor {
    if (widget.doc?.pendiente == true) return Colors.orange;
    if (widget.doc?.aprobado == true) return kComprasGreen;
    if (widget.doc?.rechazado == true) return kComprasRed;
    if (widget.doc?.tieneDoc == true) return kComprasGreen;
    return kComprasPrimary;
  }

  IconData get _icon {
    if (widget.doc?.pendiente == true) return Icons.hourglass_empty;
    if (widget.doc?.aprobado == true) return Icons.check_circle;
    if (widget.doc?.rechazado == true) return Icons.cancel;
    if (widget.doc?.tieneDoc == true) return Icons.check_circle;
    return Icons.upload_file;
  }

  String get _estadoLabel {
    if (widget.doc?.pendiente == true) return ' · Pendiente revisión calidad';
    if (widget.doc?.aprobado == true) return ' · Aprobado';
    if (widget.doc?.rechazado == true) return ' · Rechazado';
    return '';
  }

  bool get _isUploading => widget.uploading || _webUploading;

  Future<void> _handleWebFilePick() async {
    if (_isUploading || _combining || widget.onWebUpload == null) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      withData: true,
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty) return;
    final newFiles = <_PendingFile>[];
    for (final f in result.files) {
      if (f.bytes == null) continue;
      if (f.bytes!.length > _maxBytes) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('${f.name}: supera el límite de 10 MB',
                  style: const TextStyle(fontFamily: _kFont))));
        }
        continue;
      }
      newFiles.add(_PendingFile(f.bytes!, f.name));
    }
    if (newFiles.isNotEmpty && mounted) {
      setState(() => _pending.addAll(newFiles));
    }
  }

  Future<void> _handleWebDrop(DropDoneDetails details) async {
    if (!mounted || details.files.isEmpty || widget.onWebUpload == null) return;
    setState(() => _isDragging = false);
    final xFile = details.files.first;
    final name = xFile.name;
    final ext = name.toLowerCase().split('.').last;
    if (!['pdf', 'jpg', 'jpeg', 'png'].contains(ext)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Solo se permiten PDF, JPG o PNG',
                style: TextStyle(fontFamily: _kFont))));
      }
      return;
    }
    final bytes = await xFile.readAsBytes();
    await _processWebBytes(bytes, name);
  }

  Future<void> _processWebBytes(Uint8List bytes, String name) async {
    if (bytes.length > _maxBytes) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('El archivo supera el límite de 10 MB',
                style: TextStyle(fontFamily: _kFont))));
      }
      return;
    }
    setState(() => _webUploading = true);
    try {
      await widget.onWebUpload!(bytes, name);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error al subir: $e',
                style: const TextStyle(fontFamily: _kFont))));
      }
    } finally {
      if (mounted) setState(() => _webUploading = false);
    }
  }

  /// Combina todos los archivos pendientes en un único PDF y lo sube.
  Future<void> _combinarYSubir() async {
    if (_pending.isEmpty || widget.onWebUpload == null) return;
    setState(() => _combining = true);
    try {
      Uint8List finalBytes;
      String finalName;

      if (_pending.length == 1 && _pending.first.isPdf) {
        // Un único PDF: subir directo sin recodificar
        finalBytes = _pending.first.bytes;
        finalName = _pending.first.name;
      } else {
        // Combinar en un único PDF
        final pdfDoc = pw.Document();
        for (final pf in _pending) {
          if (pf.isPdf) {
            // Rasterizar cada página del PDF a imagen
            await for (final raster
                in Printing.raster(pf.bytes, dpi: 150)) {
              final imgBytes = await raster.toPng();
              final pwImg = pw.MemoryImage(imgBytes);
              // Reconstituir tamaño original en puntos (150 dpi → puntos a 72 dpi)
              final wPt = raster.width * 72.0 / 150.0;
              final hPt = raster.height * 72.0 / 150.0;
              pdfDoc.addPage(pw.Page(
                pageFormat: PdfPageFormat(wPt, hPt),
                margin: pw.EdgeInsets.zero,
                build: (_) => pw.Image(pwImg, fit: pw.BoxFit.fill),
              ));
            }
          } else {
            // Imagen: agregar como página A4
            final pwImg = pw.MemoryImage(pf.bytes);
            pdfDoc.addPage(pw.Page(
              pageFormat: PdfPageFormat.a4,
              margin: const pw.EdgeInsets.all(16),
              build: (_) =>
                  pw.Center(child: pw.Image(pwImg, fit: pw.BoxFit.contain)),
            ));
          }
        }
        finalBytes = await pdfDoc.save();
        finalName = 'documento_combinado.pdf';
      }

      await widget.onWebUpload!(finalBytes, finalName);
      if (mounted) setState(() => _pending.clear());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error al combinar: $e',
                style: const TextStyle(fontFamily: _kFont))));
      }
    } finally {
      if (mounted) setState(() => _combining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tiene = widget.doc?.tieneDoc == true;

    if (kIsWeb) {
      return _buildWeb(tiene);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                widget.label,
                style: TextStyle(
                    fontFamily: _kFont,
                    fontSize: 12,
                    color: Colors.grey.shade600),
                softWrap: true,
              ),
            ),
            if (widget.required_)
              const Text(' *',
                  style: TextStyle(color: Colors.red, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: widget.uploading ? null : widget.onAttach,
                icon: widget.uploading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(_icon, size: 16, color: _iconColor),
                label: Text(
                  widget.uploading
                      ? 'Subiendo...'
                      : tiene
                          ? '${widget.doc!.nombre ?? 'Adjunto'}$_estadoLabel'
                          : 'Adjuntar / Escanear',
                  style: TextStyle(
                      fontFamily: _kFont,
                      fontSize: 12,
                      color: widget.uploading ? Colors.grey : _iconColor),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: _borderColor),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  alignment: Alignment.centerLeft,
                ),
              ),
            ),
            if (tiene && widget.onView != null) ...[
              const SizedBox(width: 6),
              IconButton(
                onPressed: widget.onView,
                icon: const Icon(Icons.open_in_new,
                    size: 18, color: Colors.blue),
                tooltip: 'Ver documento',
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ],
        ),
        if (widget.doc?.rechazado == true &&
            widget.doc?.observacionCalidad != null) ...[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Text(
              'Motivo: ${widget.doc!.observacionCalidad}',
              style: TextStyle(
                  fontFamily: _kFont,
                  fontSize: 11,
                  color: Colors.red.shade700),
            ),
          ),
        ],
      ],
    );
  }

  // ── Web layout ──────────────────────────────────────────────────────────────

  Widget _buildWeb(bool tiene) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label
        Row(children: [
          Expanded(
            child: Text(widget.label,
                style: TextStyle(
                    fontFamily: _kFont,
                    fontSize: 12,
                    color: Colors.grey.shade600),
                softWrap: true),
          ),
          if (widget.required_)
            const Text(' *',
                style: TextStyle(color: Colors.red, fontSize: 12)),
        ]),
        const SizedBox(height: 6),
        // Zona de contenido según estado
        if (_pending.isNotEmpty)
          _buildWebPendingList()
        else if (tiene)
          _buildWebFileRow()
        else
          _buildWebDropZone(),
        // Observación de calidad
        if (widget.doc?.rechazado == true &&
            widget.doc?.observacionCalidad != null) ...[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Text(
              'Motivo: ${widget.doc!.observacionCalidad}',
              style: TextStyle(
                  fontFamily: _kFont,
                  fontSize: 11,
                  color: Colors.red.shade700),
            ),
          ),
        ],
      ],
    );
  }

  /// Lista de archivos en espera de ser combinados y subidos.
  Widget _buildWebPendingList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Encabezado con contador y botón "Agregar más"
        Row(children: [
          Text(
            'Archivos a combinar (${_pending.length})',
            style: const TextStyle(
                fontFamily: _kFont,
                fontSize: 12,
                fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: _combining ? null : _handleWebFilePick,
            icon: const Icon(Icons.add, size: 14),
            label: const Text('Agregar más',
                style: TextStyle(fontFamily: _kFont, fontSize: 11)),
            style: TextButton.styleFrom(
                foregroundColor: kComprasPrimary,
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
          ),
        ]),
        const SizedBox(height: 4),
        // Lista de archivos pendientes
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: _pending.asMap().entries.map((e) {
              final idx = e.key;
              final pf = e.value;
              final ext = pf.name.split('.').last.toLowerCase();
              final isImg = ['jpg', 'jpeg', 'png'].contains(ext);
              return ListTile(
                dense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                leading: Icon(
                    isImg ? Icons.image : Icons.picture_as_pdf,
                    size: 18,
                    color: isImg ? Colors.blue.shade600 : Colors.red.shade600),
                title: Text(pf.name,
                    style: const TextStyle(
                        fontFamily: _kFont, fontSize: 12),
                    overflow: TextOverflow.ellipsis),
                subtitle: Text(
                    '${(pf.bytes.length / 1024).toStringAsFixed(0)} KB',
                    style: TextStyle(
                        fontFamily: _kFont,
                        fontSize: 10,
                        color: Colors.grey.shade500)),
                trailing: IconButton(
                  icon: const Icon(Icons.close,
                      size: 16, color: Colors.grey),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: _combining
                      ? null
                      : () => setState(() => _pending.removeAt(idx)),
                  tooltip: 'Quitar',
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 8),
        // Botones de acción
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _combining
                  ? null
                  : () => setState(() => _pending.clear()),
              icon: const Icon(Icons.clear, size: 13),
              label: const Text('Cancelar',
                  style: TextStyle(fontFamily: _kFont, fontSize: 11)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: Colors.grey.shade300),
                padding: const EdgeInsets.symmetric(vertical: 6),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: FilledButton.icon(
              onPressed: _combining ? null : _combinarYSubir,
              icon: _combining
                  ? const SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.merge_type, size: 14),
              label: Text(
                _combining
                    ? 'Combinando...'
                    : _pending.length == 1
                        ? 'Subir archivo'
                        : 'Combinar y subir PDF',
                style: const TextStyle(
                    fontFamily: _kFont, fontSize: 11),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: kComprasPrimary,
                padding: const EdgeInsets.symmetric(vertical: 6),
              ),
            ),
          ),
        ]),
      ],
    );
  }

  Widget _buildWebDropZone() {
    // En web: zona drag-and-drop + botón separado para abrir selector
    // El DropzoneView (HTML) captura los eventos de arrastre del navegador.
    // El botón queda fuera del área del DropzoneView para que Flutter lo reciba.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Zona de arrastre
        SizedBox(
          key: _dropKey,
          height: 72,
          child: DropTarget(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: double.infinity,
              decoration: BoxDecoration(
                color: _isDragging
                    ? kComprasPrimary.withOpacity(0.07)
                    : (_isUploading
                        ? Colors.blue.shade50
                        : Colors.grey.shade50),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _isDragging
                      ? kComprasPrimary
                      : Colors.grey.shade300,
                  width: _isDragging ? 2 : 1,
                ),
              ),
              child: _isUploading
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: kComprasPrimary)),
                        const SizedBox(width: 10),
                        Text('Subiendo...',
                            style: TextStyle(
                                fontFamily: _kFont,
                                fontSize: 12,
                                color: Colors.grey.shade600)),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.cloud_upload_outlined,
                            size: 26,
                            color: _isDragging
                                ? kComprasPrimary
                                : Colors.grey.shade400),
                        const SizedBox(width: 10),
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isDragging
                                  ? '¡Suelta el archivo aquí!'
                                  : 'Arrastra el archivo aquí',
                              style: TextStyle(
                                  fontFamily: _kFont,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: _isDragging
                                      ? kComprasPrimary
                                      : Colors.black54),
                            ),
                            Text('PDF · JPG · PNG · Máx. 10 MB',
                                style: TextStyle(
                                    fontFamily: _kFont,
                                    fontSize: 10,
                                    color: Colors.grey.shade500)),
                          ],
                        ),
                      ],
                    ),
            ),
          ),
        ),
        // Botón separado para abrir selector de archivo
        if (!_isUploading && widget.onWebUpload != null) ...[
          const SizedBox(height: 4),
          OutlinedButton.icon(
            onPressed: _handleWebFilePick,
            icon: Icon(Icons.folder_open,
                size: 13, color: Colors.grey.shade600),
            label: Text('o seleccionar archivo',
                style: TextStyle(
                    fontFamily: _kFont,
                    fontSize: 11,
                    color: Colors.grey.shade600)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: Colors.grey.shade300),
              padding: const EdgeInsets.symmetric(vertical: 4),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildWebFileRow() {
    final doc = widget.doc!;
    final nombre = doc.nombre ?? 'Adjunto';
    final ext = nombre.split('.').last.toLowerCase();
    final isImg = ['jpg', 'jpeg', 'png'].contains(ext);

    Color statusColor = kComprasGreen;
    String statusText = 'Adjunto';
    IconData statusIcon = Icons.check_circle;
    if (doc.pendiente == true) {
      statusColor = Colors.orange;
      statusText = 'Pendiente revisión';
      statusIcon = Icons.hourglass_empty;
    } else if (doc.rechazado == true) {
      statusColor = kComprasRed;
      statusText = 'Rechazado';
      statusIcon = Icons.cancel;
    } else if (doc.aprobado == true) {
      statusColor = kComprasGreen;
      statusText = 'Aprobado';
      statusIcon = Icons.verified;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: statusColor.withOpacity(0.3), width: 1),
      ),
      child: Row(
        children: [
          Icon(isImg ? Icons.image : Icons.picture_as_pdf,
              color: statusColor, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nombre,
                  style: const TextStyle(
                      fontFamily: _kFont,
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
                Row(children: [
                  Icon(statusIcon, size: 11, color: statusColor),
                  const SizedBox(width: 3),
                  Text(statusText,
                      style: TextStyle(
                          fontFamily: _kFont,
                          fontSize: 10,
                          color: statusColor)),
                ]),
              ],
            ),
          ),
          if (widget.onView != null)
            TextButton.icon(
              onPressed: widget.onView,
              icon: const Icon(Icons.open_in_new, size: 14),
              label: const Text('Ver',
                  style: TextStyle(fontFamily: _kFont, fontSize: 11)),
              style: TextButton.styleFrom(
                  foregroundColor: Colors.blue,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4)),
            ),
          if (widget.onWebUpload != null)
            TextButton.icon(
              onPressed: _isUploading ? null : _handleWebFilePick,
              icon: const Icon(Icons.add_circle_outline, size: 14),
              label: const Text('Agregar',
                  style: TextStyle(fontFamily: _kFont, fontSize: 11)),
              style: TextButton.styleFrom(
                  foregroundColor: Colors.grey.shade600,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4)),
            ),
          if (widget.onDelete != null)
            IconButton(
              onPressed: _isUploading ? null : widget.onDelete,
              icon: Icon(Icons.delete_outline,
                  size: 18, color: Colors.red.shade400),
              tooltip: 'Eliminar documento',
              padding: const EdgeInsets.symmetric(horizontal: 4),
              constraints:
                  const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
        ],
      ),
    );
  }
}

void _abrirUrl(BuildContext context, String? url) async {
  if (url == null || url.isEmpty) return;
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } else {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo abrir el documento')));
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// PROVEEDORES SCREEN — listado
// ══════════════════════════════════════════════════════════════════════════════

class _ProveedoresScreen extends StatefulWidget {
  final String empresaId;
  final ComprasService svc;

  const _ProveedoresScreen({required this.empresaId, required this.svc});

  @override
  State<_ProveedoresScreen> createState() => _ProveedoresScreenState();
}

class _ProveedoresScreenState extends State<_ProveedoresScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kComprasBg,
      appBar: AppBar(
        title: const Text('Proveedores',
            style: TextStyle(fontFamily: _kFont, fontWeight: FontWeight.bold)),
        backgroundColor: kComprasPrimary,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Buscar por nombre o NIT...',
                hintStyle:
                    const TextStyle(fontFamily: _kFont, fontSize: 14),
                prefixIcon: const Icon(Icons.search, size: 20),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                filled: true,
                fillColor: Colors.white,
              ),
              onChanged: (v) => setState(() => _query = v.toLowerCase()),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<ProveedorDoc>>(
              stream: widget.svc.streamProveedores(widget.empresaId),
              builder: (ctx, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final all = snap.data ?? [];
                final filtered = _query.isEmpty
                    ? all
                    : all
                        .where((p) =>
                            p.razonSocial.toLowerCase().contains(_query) ||
                            p.nit.contains(_query) ||
                            p.ciudad.toLowerCase().contains(_query))
                        .toList();
                if (filtered.isEmpty) {
                  return Center(
                    child: Text(
                        _query.isEmpty
                            ? 'Sin proveedores registrados'
                            : 'Sin resultados para "$_query"',
                        style: const TextStyle(
                            fontFamily: _kFont, color: Colors.black45)),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 80),
                  itemCount: filtered.length,
                  itemBuilder: (ctx, i) {
                    final p = filtered[i];
                    return _ProveedorCard(
                      proveedor: p,
                      onTap: () => _openForm(existing: p),
                      onDelete: () => _confirmDelete(p),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: kComprasPrimary,
        foregroundColor: Colors.white,
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label:
            const Text('Nuevo Proveedor', style: TextStyle(fontFamily: _kFont)),
      ),
    );
  }

  void _openForm({ProveedorDoc? existing}) => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _ProveedorFormScreen(
            empresaId: widget.empresaId,
            svc: widget.svc,
            existing: existing,
          ),
        ),
      );

  Future<void> _confirmDelete(ProveedorDoc p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar proveedor',
            style: TextStyle(fontFamily: _kFont)),
        content: Text('¿Desea eliminar a "${p.razonSocial}"?',
            style: const TextStyle(fontFamily: _kFont)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Eliminar',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok == true) await widget.svc.eliminarProveedor(p.id);
  }
}

class _ProveedorCard extends StatelessWidget {
  final ProveedorDoc proveedor;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ProveedorCard({
    required this.proveedor,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final docsKeys = [
      kDocRut,
      kDocCertExistencia,
      kDocActaInspeccion
    ];
    final tieneRequeridos =
        docsKeys.every((k) => proveedor.documentos[k]?.tieneDoc == true);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(proveedor.razonSocial,
                        style: const TextStyle(
                            fontFamily: _kFont,
                            fontWeight: FontWeight.w600,
                            fontSize: 15)),
                  ),
                  _StatusDot(ok: tieneRequeridos),
                  const SizedBox(width: 4),
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'delete') onDelete();
                      if (v == 'edit') onTap();
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                          value: 'edit',
                          child: Text('Editar',
                              style: TextStyle(fontFamily: _kFont))),
                      const PopupMenuItem(
                          value: 'delete',
                          child: Text('Eliminar',
                              style: TextStyle(
                                  fontFamily: _kFont, color: Colors.red))),
                    ],
                    icon: const Icon(Icons.more_vert, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.badge, size: 14, color: Colors.black45),
                  const SizedBox(width: 4),
                  Text('NIT: ${proveedor.nit}',
                      style: const TextStyle(
                          fontFamily: _kFont,
                          fontSize: 12,
                          color: Colors.black54)),
                  const Spacer(),
                  if (proveedor.ciudad.isNotEmpty)
                    Row(
                      children: [
                        const Icon(Icons.location_on,
                            size: 13, color: Colors.black38),
                        const SizedBox(width: 2),
                        Text(proveedor.ciudad,
                            style: const TextStyle(
                                fontFamily: _kFont,
                                fontSize: 12,
                                color: Colors.black45)),
                      ],
                    ),
                ],
              ),
              if (proveedor.categorias.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: proveedor.categorias
                      .map((c) => _Chip(c, kComprasPrimary))
                      .toList(),
                ),
              ],
              const SizedBox(height: 6),
              Row(
                children: [
                  if (proveedor.esLocal)
                    _Chip('Local', kComprasGreen)
                  else
                    _Chip('No local', Colors.grey),
                  const Spacer(),
                  ...docsKeys.map((k) {
                    final tiene = proveedor.documentos[k]?.tieneDoc == true;
                    return Tooltip(
                      message: kDocProveedorLabels[k] ?? k,
                      child: Container(
                        width: 10,
                        height: 10,
                        margin: const EdgeInsets.only(left: 4),
                        decoration: BoxDecoration(
                          color: tiene ? kComprasGreen : kComprasRed,
                          shape: BoxShape.circle,
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// PROVEEDOR FORM SCREEN — crear / editar
// ══════════════════════════════════════════════════════════════════════════════

class _ProveedorFormScreen extends StatefulWidget {
  final String empresaId;
  final ComprasService svc;
  final ProveedorDoc? existing;

  const _ProveedorFormScreen({
    required this.empresaId,
    required this.svc,
    this.existing,
  });

  @override
  State<_ProveedorFormScreen> createState() => _ProveedorFormScreenState();
}

class _ProveedorFormScreenState extends State<_ProveedorFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nitCtrl;
  late final TextEditingController _razonCtrl;
  late final TextEditingController _dirCtrl;
  late final TextEditingController _telCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _ciudadCtrl;

  String? _departamento;
  bool _esLocal = false;
  List<String> _categorias = [];
  Map<String, DocAdjunto> _documentos = {};
  bool _guardando = false;

  bool get isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _nitCtrl = TextEditingController(text: p?.nit ?? '');
    _razonCtrl = TextEditingController(text: p?.razonSocial ?? '');
    _dirCtrl = TextEditingController(text: p?.direccion ?? '');
    _telCtrl = TextEditingController(text: p?.telefono ?? '');
    _emailCtrl = TextEditingController(text: p?.email ?? '');
    _ciudadCtrl = TextEditingController(text: p?.ciudad ?? '');
    _departamento = _matchDepartamento(p?.departamento);
    _esLocal = p?.esLocal ?? false;
    _categorias = List.from(p?.categorias ?? []);
    _documentos = Map.from(p?.documentos ?? {});
  }

  @override
  void dispose() {
    for (final c in [
      _nitCtrl, _razonCtrl, _dirCtrl, _telCtrl, _emailCtrl, _ciudadCtrl
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _guardando = true);
    try {
      final p = ProveedorDoc(
        id: widget.existing?.id ?? '',
        empresaId: widget.empresaId,
        nit: _nitCtrl.text.trim(),
        razonSocial: _normalizarNombre(_razonCtrl.text),
        direccion: _dirCtrl.text.trim(),
        telefono: _telCtrl.text.trim(),
        email: _emailCtrl.text.trim().toLowerCase(),
        departamento: _departamento ?? '',
        ciudad: _normalizarNombre(_ciudadCtrl.text),
        esLocal: _esLocal,
        categorias: _categorias,
        documentos: _documentos,
        createdAt: widget.existing?.createdAt ?? Timestamp.now(),
      );
      await widget.svc.guardarProveedor(p, isNew: isNew);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(isNew ? 'Proveedor creado' : 'Proveedor actualizado'),
          backgroundColor: kComprasGreen,
        ));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: kComprasRed));
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _adjuntarDoc(String key) async {
    final nombre = kDocProveedorLabels[key] ?? key;
    final doc = await _mostrarEscaneador(
      context,
      empresaId: widget.empresaId,
      carpeta: 'proveedores',
      nombreSugerido: '${_nitCtrl.text}_$nombre',
      svc: widget.svc,
    );
    if (doc != null) setState(() => _documentos = {..._documentos, key: doc});
  }

  Widget _sectionHeader(String title) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 10),
        child: Row(
          children: [
            Container(
                width: 4,
                height: 18,
                decoration: BoxDecoration(
                    color: kComprasPrimary,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 8),
            Text(title,
                style: const TextStyle(
                    fontFamily: _kFont,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: kComprasPrimary)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kComprasBg,
      appBar: AppBar(
        title: Text(isNew ? 'Nuevo Proveedor' : 'Editar Proveedor',
            style: const TextStyle(
                fontFamily: _kFont, fontWeight: FontWeight.bold)),
        backgroundColor: kComprasPrimary,
        foregroundColor: Colors.white,
        actions: [
          if (_guardando)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white)),
            )
          else
            TextButton(
              onPressed: _guardar,
              child: const Text('Guardar',
                  style: TextStyle(
                      color: Colors.white,
                      fontFamily: _kFont,
                      fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Info básica ──────────────────────────────
              _sectionHeader('Información básica'),
              _buildField(
                controller: _nitCtrl,
                label: 'NIT *',
                hint: 'Ej: 900123456-1',
                keyboardType: TextInputType.text,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d\-]'))
                ],
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Campo requerido' : null,
              ),
              const SizedBox(height: 12),
              _buildField(
                controller: _razonCtrl,
                label: 'Razón Social *',
                hint: 'Nombre de la empresa proveedora',
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Campo requerido' : null,
              ),
              // ── Contacto ────────────────────────────────
              _sectionHeader('Contacto'),
              _buildField(
                  controller: _dirCtrl,
                  label: 'Dirección',
                  hint: 'Calle 123 # 45-67'),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildField(
                      controller: _telCtrl,
                      label: 'Teléfono',
                      keyboardType: TextInputType.phone,
                      hint: '3001234567',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildField(
                      controller: _emailCtrl,
                      label: 'Email',
                      keyboardType: TextInputType.emailAddress,
                      hint: 'correo@empresa.com',
                    ),
                  ),
                ],
              ),
              // ── Ubicación ────────────────────────────────
              _sectionHeader('Ubicación'),
              DropdownButtonFormField<String>(
                value: _departamento,
                decoration: _inputDecoration('Departamento'),
                isExpanded: true,
                items: kDepartamentos
                    .map((d) => DropdownMenuItem(
                        value: d,
                        child: Text(d, style: const TextStyle(fontFamily: _kFont))))
                    .toList(),
                onChanged: (v) => setState(() => _departamento = v),
              ),
              const SizedBox(height: 12),
              _buildField(
                  controller: _ciudadCtrl,
                  label: 'Ciudad / Municipio',
                  hint: 'Bogotá'),
              const SizedBox(height: 12),
              SwitchListTile(
                value: _esLocal,
                onChanged: (v) => setState(() => _esLocal = v),
                title: const Text('Es proveedor local',
                    style: TextStyle(fontFamily: _kFont, fontSize: 14)),
                activeColor: kComprasPrimary,
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
              // ── Categorías ───────────────────────────────
              _sectionHeader('Categorías de productos'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: kCategoriasCompras.map((cat) {
                  final sel = _categorias.contains(cat);
                  return FilterChip(
                    label: Text(cat,
                        style:
                            const TextStyle(fontFamily: _kFont, fontSize: 13)),
                    selected: sel,
                    onSelected: (v) {
                      setState(() {
                        if (v) {
                          _categorias.add(cat);
                        } else {
                          _categorias.remove(cat);
                        }
                      });
                    },
                    selectedColor: kComprasPrimary.withOpacity(0.15),
                    checkmarkColor: kComprasPrimary,
                    side: BorderSide(
                        color: sel ? kComprasPrimary : Colors.grey.shade300),
                  );
                }).toList(),
              ),
              // ── Documentos ───────────────────────────────
              _sectionHeader('Documentos'),
              ...kDocProveedorLabels.entries.map((e) {
                final key = e.key;
                final label = e.value;
                final isReq = key == kDocRut || key == kDocCertExistencia;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _DocAttachButton(
                    label: label,
                    required_: isReq,
                    doc: _documentos[key],
                    onAttach: () => _adjuntarDoc(key),
                    onView: _documentos[key]?.tieneDoc == true
                        ? () => _abrirUrl(context, _documentos[key]!.url)
                        : null,
                    onDelete: _documentos[key]?.tieneDoc == true
                        ? () => setState(() =>
                            _documentos = {..._documentos, key: const DocAdjunto()})
                        : null,
                    onWebUpload: (bytes, name) async {
                      final ext = name.toLowerCase().split('.').last;
                      final ct = ext == 'pdf'
                          ? 'application/pdf'
                          : 'image/$ext';
                      final doc = await widget.svc.subirBytes(
                        bytes: bytes,
                        empresaId: widget.empresaId,
                        carpeta: 'proveedores',
                        nombre:
                            '${_nitCtrl.text}_${kDocProveedorLabels[key] ?? key}_$name',
                        contentType: ct,
                      );
                      setState(() =>
                          _documentos = {..._documentos, key: doc});
                    },
                  ),
                );
              }),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    String? hint,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) =>
      TextFormField(
        controller: controller,
        decoration: _inputDecoration(label).copyWith(hintText: hint),
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        validator: validator,
        style: const TextStyle(fontFamily: _kFont, fontSize: 14),
      );
}

InputDecoration _inputDecoration(String label) => InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontFamily: _kFont, fontSize: 13),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      filled: true,
      fillColor: Colors.white,
    );

// ══════════════════════════════════════════════════════════════════════════════
// PRODUCTOS SCREEN — listado
// ══════════════════════════════════════════════════════════════════════════════

class _ProductosScreen extends StatefulWidget {
  final String empresaId;
  final ComprasService svc;
  final String userId;

  const _ProductosScreen(
      {required this.empresaId, required this.svc, required this.userId});

  @override
  State<_ProductosScreen> createState() => _ProductosScreenState();
}

class _ProductosScreenState extends State<_ProductosScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  String? _filtroCategoria;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kComprasBg,
      appBar: AppBar(
        title: const Text('Productos',
            style: TextStyle(fontFamily: _kFont, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0277BD),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Buscar producto o código...',
                hintStyle: const TextStyle(fontFamily: _kFont, fontSize: 14),
                prefixIcon: const Icon(Icons.search, size: 20),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                filled: true,
                fillColor: Colors.white,
              ),
              onChanged: (v) => setState(() => _query = v.toLowerCase()),
            ),
          ),
          // Filtro por categoría
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              children: [
                _CatChip('Todos', _filtroCategoria == null,
                    () => setState(() => _filtroCategoria = null)),
                ...kCategoriasCompras.map((c) => _CatChip(
                    c,
                    _filtroCategoria == c,
                    () => setState(() => _filtroCategoria = c))),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: StreamBuilder<List<ProductoDoc>>(
              stream: widget.svc.streamProductos(widget.empresaId),
              builder: (ctx, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final all = snap.data ?? [];
                var filtered = _query.isEmpty
                    ? all
                    : all
                        .where((p) =>
                            p.nombre.toLowerCase().contains(_query) ||
                            p.codigo.toLowerCase().contains(_query) ||
                            p.categoria.toLowerCase().contains(_query))
                        .toList();
                if (_filtroCategoria != null) {
                  filtered = filtered
                      .where((p) => p.categoria == _filtroCategoria)
                      .toList();
                }
                if (filtered.isEmpty) {
                  return Center(
                      child: Text('Sin productos',
                          style: const TextStyle(
                              fontFamily: _kFont, color: Colors.black45)));
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 80),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) => _ProductoCard(
                    producto: filtered[i],
                    onTap: () => _openForm(existing: filtered[i]),
                    onDelete: () => _confirmDelete(filtered[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF0277BD),
        foregroundColor: Colors.white,
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label:
            const Text('Nuevo Producto', style: TextStyle(fontFamily: _kFont)),
      ),
    );
  }

  void _openForm({ProductoDoc? existing}) => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (_) => _ProductoFormSheet(
          empresaId: widget.empresaId,
          svc: widget.svc,
          existing: existing,
          userId: widget.userId,
        ),
      );

  Future<void> _confirmDelete(ProductoDoc p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar producto',
            style: TextStyle(fontFamily: _kFont)),
        content: Text('¿Eliminar "${p.nombre}"?',
            style: const TextStyle(fontFamily: _kFont)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Eliminar',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok == true) await widget.svc.eliminarProducto(p.id);
  }
}

Widget _CatChip(String label, bool selected, VoidCallback onTap) => Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF0277BD) : Colors.white,
            border: Border.all(
                color: selected
                    ? const Color(0xFF0277BD)
                    : Colors.grey.shade300),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(label,
              style: TextStyle(
                  fontFamily: _kFont,
                  fontSize: 12,
                  color: selected ? Colors.white : Colors.black54)),
        ),
      ),
    );

class _ProductoCard extends StatelessWidget {
  final ProductoDoc producto;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ProductoCard(
      {required this.producto, required this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF0277BD).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.inventory_2,
                    color: Color(0xFF0277BD), size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(producto.codigo,
                              style: const TextStyle(
                                  fontFamily: _kFont,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black54)),
                        ),
                        const SizedBox(width: 8),
                        if (producto.esPerecedero)
                          _Chip('Perecedero', Colors.orange.shade700),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(producto.nombre,
                        style: const TextStyle(
                            fontFamily: _kFont,
                            fontWeight: FontWeight.w600,
                            fontSize: 14)),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        _Chip(producto.categoria, const Color(0xFF0277BD)),
                        const SizedBox(width: 6),
                        _Chip(producto.unidadMedida, Colors.blueGrey),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'edit') onTap();
                  if (v == 'delete') onDelete();
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                      value: 'edit',
                      child: Text('Editar',
                          style: TextStyle(fontFamily: _kFont))),
                  const PopupMenuItem(
                      value: 'delete',
                      child: Text('Eliminar',
                          style: TextStyle(
                              fontFamily: _kFont, color: Colors.red))),
                ],
                icon: const Icon(Icons.more_vert, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// PRODUCTO FORM SHEET — crear / editar (bottom sheet)
// ══════════════════════════════════════════════════════════════════════════════

class _ProductoFormSheet extends StatefulWidget {
  final String empresaId;
  final ComprasService svc;
  final ProductoDoc? existing;
  final String userId;

  const _ProductoFormSheet(
      {required this.empresaId,
      required this.svc,
      this.existing,
      required this.userId});

  @override
  State<_ProductoFormSheet> createState() => _ProductoFormSheetState();
}

class _ProductoFormSheetState extends State<_ProductoFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _codigoCtrl;
  late final TextEditingController _nombreCtrl;
  String? _unidad;
  String? _categoria;
  bool _perecedero = false;
  bool _guardando = false;
  List<MarcaRef> _marcasProducto = [];
  List<MarcaDoc> _todasMarcas = [];
  List<ProductoDoc> _productosExistentes = [];
  bool _loadingMarcas = true;
  String _origen = 'NACIONAL'; // 'NACIONAL' | 'IMPORTADO'
  Map<String, DocAdjunto> _fichasPorMarca = {};

  bool get isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _codigoCtrl = TextEditingController(text: p?.codigo ?? '');
    _nombreCtrl = TextEditingController(text: p?.nombre ?? '');
    _unidad = p?.unidadMedida.isNotEmpty == true ? p!.unidadMedida : null;
    _categoria = p?.categoria.isNotEmpty == true ? p!.categoria : null;
    _perecedero = p?.esPerecedero ?? false;
    _marcasProducto = List.from(p?.marcas ?? []);
    _origen = p?.origen ?? 'NACIONAL';
    _fichasPorMarca = Map<String, DocAdjunto>.from(p?.fichasTecnicasPorMarca ?? {});
    _loadMarcas();
    _loadProductosExistentes();
  }

  Future<void> _loadMarcas() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('TBL_COMPRAS_MARCAS')
          .where('empresaId', isEqualTo: widget.empresaId)
          .get();
      if (!mounted) return;
      final list = snap.docs
          .map((d) => MarcaDoc.fromMap(d.id, d.data()))
          .toList()
        ..sort((a, b) => a.descripcion.compareTo(b.descripcion));
      setState(() {
        _todasMarcas = list;
        _loadingMarcas = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMarcas = false);
    }
  }

  Future<void> _loadProductosExistentes() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('TBL_COMPRAS_PRODUCTOS')
          .where('empresaId', isEqualTo: widget.empresaId)
          .get();
      if (!mounted) return;
      setState(() {
        _productosExistentes = snap.docs
            .map((d) => ProductoDoc.fromMap(d.id, d.data()))
            .toList();
      });
    } catch (_) {}
  }

  ProductoDoc? _buscarCoincidenciaProducto({
    required String codigo,
    required String nombre,
  }) {
    final code = codigo.trim().toUpperCase();
    final name = _normalizarNombre(nombre).toLowerCase();
    for (final p in _productosExistentes) {
      if (!isNew && p.id == widget.existing?.id) continue;
      final sameCode = p.codigo.trim().toUpperCase() == code;
      final sameName = p.nombre.trim().toLowerCase() == name;
      if (sameCode || sameName) return p;
    }
    return null;
  }

  bool _pareceProteina(String texto) {
    final t = texto.toLowerCase();
    return t.contains('prote') ||
        t.contains('carne') ||
        t.contains('pollo') ||
        t.contains('cerdo') ||
        t.contains('pescado') ||
        t.contains('res');
  }

  @override
  void dispose() {
    _codigoCtrl.dispose();
    _nombreCtrl.dispose();
    super.dispose();
  }

  Future<void> _agregarMarca() async {
    // Mostrar sólo las marcas que aún no están vinculadas
    final yaVinculadas = _marcasProducto.map((r) => r.marcaId).toSet();
    final disponibles =
        _todasMarcas.where((m) => !yaVinculadas.contains(m.id)).toList();
    if (disponibles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('No hay marcas disponibles. Crea marcas desde el menú.')));
      return;
    }
    final seleccionada = await showModalBottomSheet<MarcaDoc>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _MarcaSelectorSheet(marcas: disponibles),
    );
    if (seleccionada != null && mounted) {
      setState(() => _marcasProducto.add(seleccionada.toRef()));
    }
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    if (_unidad == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Seleccione la unidad de medida')));
      return;
    }
    if (_categoria == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Seleccione la categoría')));
      return;
    }

    final coincidencia = _buscarCoincidenciaProducto(
      codigo: _codigoCtrl.text,
      nombre: _nombreCtrl.text,
    );
    if (coincidencia != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          'Ya existe un producto similar (${coincidencia.codigo} - ${coincidencia.nombre}). Revise antes de crear uno nuevo.',
        ),
        backgroundColor: kComprasRed,
      ));
      return;
    }

    final textoProducto = '${_codigoCtrl.text} ${_nombreCtrl.text}';
    if (_categoria != 'Proteína' && _pareceProteina(textoProducto)) {
      final continuar = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Posible producto de proteína'),
          content: const Text(
            'Detectamos palabras asociadas a proteína. Si aplica, seleccione la categoría Proteína para exigir la documentación correcta en recepción.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Revisar categoría'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Continuar'),
            ),
          ],
        ),
      );
      if (continuar != true) return;
    }

    setState(() => _guardando = true);
    try {
      final codigo = _codigoCtrl.text.trim().toUpperCase();
      final p = ProductoDoc(
        id: widget.existing?.id ?? '',
        empresaId: widget.empresaId,
        codigo: codigo,
        nombre: _normalizarNombre(_nombreCtrl.text),
        unidadMedida: _normalizarUM(_unidad!),
        categoria: _categoria!,
        esPerecedero: _perecedero,
        marcas: _marcasProducto,
        origen: _origen,
        fichaTecnica: widget.existing?.fichaTecnica,
        fichasTecnicasPorMarca: _fichasPorMarca,
        createdAt: widget.existing?.createdAt ?? Timestamp.now(),
      );
      await widget.svc.guardarProducto(p, isNew: isNew);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(isNew ? 'Producto creado' : 'Producto actualizado'),
          backgroundColor: kComprasGreen,
        ));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: kComprasRed));
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(4)),
                ),
              ),
              Row(
                children: [
                  const Icon(Icons.inventory_2, color: Color(0xFF0277BD)),
                  const SizedBox(width: 8),
                  Text(isNew ? 'Nuevo Producto' : 'Editar Producto',
                      style: const TextStyle(
                          fontFamily: _kFont,
                          fontSize: 17,
                          fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 16),
              // Código — ingreso manual
              TextFormField(
                controller: _codigoCtrl,
                decoration: _inputDecoration('Código *').copyWith(
                  hintText: 'Ej: PRD-0001, CARNE-001',
                  prefixIcon: const Icon(Icons.qr_code, size: 18),
                  helperText: 'Se guardará en mayúsculas automáticamente',
                ),
                style: const TextStyle(
                    fontFamily: _kFont,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2),
                textCapitalization: TextCapitalization.characters,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Campo requerido' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _nombreCtrl,
                decoration: _inputDecoration('Nombre del producto *')
                    .copyWith(hintText: 'Ej: Carne De Res'),
                style: const TextStyle(fontFamily: _kFont, fontSize: 14),
                textCapitalization: TextCapitalization.words,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Campo requerido' : null,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _unidad,
                      decoration: _inputDecoration('Unidad de medida *'),
                      isExpanded: true,
                      items: kUnidadesMedida
                          .map((u) => DropdownMenuItem(
                              value: u,
                              child: Text(u,
                                  style:
                                      const TextStyle(fontFamily: _kFont))))
                          .toList(),
                      onChanged: (v) => setState(() => _unidad = v),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _categoria,
                      decoration: _inputDecoration('Categoría *'),
                      isExpanded: true,
                      items: kCategoriasCompras
                          .map((c) => DropdownMenuItem(
                              value: c,
                              child: Text(c,
                                  style:
                                      const TextStyle(fontFamily: _kFont))))
                          .toList(),
                      onChanged: (v) => setState(() => _categoria = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SwitchListTile(
                value: _perecedero,
                onChanged: (v) => setState(() => _perecedero = v),
                title: const Text('Es perecedero',
                    style: TextStyle(fontFamily: _kFont, fontSize: 14)),
                activeColor: const Color(0xFF0277BD),
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
              const SizedBox(height: 14),
              // ── Origen Nacional / Importado ───────────────────────────────
              const Text('Origen del producto',
                  style: TextStyle(
                      fontFamily: _kFont,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.black54)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _OrigenButton(
                      label: 'Nacional',
                      icon: Icons.home_work_outlined,
                      selected: _origen == 'NACIONAL',
                      color: Colors.green.shade700,
                      onTap: () => setState(() => _origen = 'NACIONAL'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _OrigenButton(
                      label: 'Importado',
                      icon: Icons.flight_land,
                      selected: _origen == 'IMPORTADO',
                      color: Colors.purple.shade700,
                      onTap: () => setState(() => _origen = 'IMPORTADO'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const SizedBox(height: 20),
              const Text(
                'Documentos que se solicitarán en recepción',
                style: TextStyle(
                  fontFamily: _kFont,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: kComprasPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.blue.shade100),
                ),
                child: (_categoria == null)
                    ? const Text(
                  'Seleccione una categoría para previsualizar los documentos obligatorios.',
                  style: TextStyle(fontFamily: _kFont, fontSize: 12),
                )
                    : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: docsParaCategoria(_categoria)
                      .map((key) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '• ${kDocRecepcionLabels[key] ?? key}',
                      style: const TextStyle(
                        fontFamily: _kFont,
                        fontSize: 12,
                      ),
                    ),
                  ))
                      .toList(),
                ),
              ),
              const SizedBox(height: 16),
              // ── Marcas vinculadas ─────────────────────────────────────────
              Row(
                children: [
                  const Icon(Icons.label_important,
                      size: 16, color: Color(0xFF1976D2)),
                  const SizedBox(width: 6),
                  const Text('Marcas del producto',
                      style: TextStyle(
                          fontFamily: _kFont,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  const Spacer(),
                  if (_loadingMarcas)
                    const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                ],
              ),
              const SizedBox(height: 8),
              if (_marcasProducto.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Sin marcas vinculadas',
                    style: TextStyle(
                        fontFamily: _kFont,
                        fontSize: 13,
                        color: Colors.blueGrey.shade400),
                  ),
                )
              else
                ...List.generate(_marcasProducto.length, (i) {
                  final ref = _marcasProducto[i];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    color: const Color(0xFFE3F2FD),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: const BorderSide(
                            color: Color(0xFF90CAF9), width: 0.8)),
                    child: ListTile(
                      dense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12),
                      leading: const Icon(Icons.label,
                          size: 18, color: Color(0xFF1976D2)),
                      title: Text('${ref.codigo} – ${ref.descripcion}',
                          style: const TextStyle(
                              fontFamily: _kFont,
                              fontSize: 13,
                              fontWeight: FontWeight.w500)),
                      subtitle: const Text(
                        'Gestiona fichas técnicas por proveedor',
                        style: TextStyle(
                          fontFamily: _kFont,
                          fontSize: 11,
                          color: Colors.black45,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.description_outlined,
                                size: 18, color: Color(0xFF1976D2)),
                            tooltip: 'Fichas técnicas por proveedor',
                            onPressed: widget.existing == null
                                ? null
                                : () => showModalBottomSheet(
                                      context: context,
                                      isScrollControlled: true,
                                      useSafeArea: true,
                                      backgroundColor: Colors.white,
                                      shape: const RoundedRectangleBorder(
                                          borderRadius: BorderRadius.vertical(
                                              top: Radius.circular(20))),
                                      builder: (_) =>
                                          _FichasTecnicasPorMarcaSheet(
                                        empresaId: widget.empresaId,
                                        svc: widget.svc,
                                        productoId: widget.existing!.id,
                                        productoNombre:
                                            widget.existing!.nombre,
                                        productoCategoria:
                                            widget.existing!.categoria,
                                        marcaId: ref.marcaId,
                                        marcaNombre: ref.descripcion,
                                        userId: widget.userId,
                                      ),
                                    ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline,
                                size: 18, color: Colors.redAccent),
                            onPressed: () => setState(() {
                              final removed = _marcasProducto.removeAt(i);
                              _fichasPorMarca.remove(removed.marcaId);
                            }),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              const SizedBox(height: 8),
              if (!_loadingMarcas)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _agregarMarca,
                    icon: const Icon(Icons.add, size: 16,
                        color: Color(0xFF1976D2)),
                    label: const Text('Agregar marca',
                        style: TextStyle(
                            fontFamily: _kFont, color: Color(0xFF1976D2))),
                    style: OutlinedButton.styleFrom(
                        side:
                            const BorderSide(color: Color(0xFF1976D2)),
                        padding:
                            const EdgeInsets.symmetric(vertical: 10)),
                  ),
                ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _guardando ? null : _guardar,
                  icon: _guardando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save),
                  label: Text(_guardando ? 'Guardando...' : 'Guardar',
                      style: const TextStyle(fontFamily: _kFont)),
                  style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0277BD),
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// FICHAS TÉCNICAS POR MARCA — gestión desde formulario de producto
// ══════════════════════════════════════════════════════════════════════════════

class _FichasTecnicasPorMarcaSheet extends StatelessWidget {
  final String empresaId;
  final ComprasService svc;
  final String productoId;
  final String productoNombre;
  final String productoCategoria;
  final String marcaId;
  final String marcaNombre;
  final String userId;

  const _FichasTecnicasPorMarcaSheet({
    required this.empresaId,
    required this.svc,
    required this.productoId,
    required this.productoNombre,
    required this.productoCategoria,
    required this.marcaId,
    required this.marcaNombre,
    required this.userId,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (_, ctrl) => Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Icon(Icons.description, color: Color(0xFF0277BD)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(productoNombre,
                          style: const TextStyle(
                              fontFamily: _kFont,
                              fontSize: 15,
                              fontWeight: FontWeight.w700)),
                      if (marcaNombre.isNotEmpty)
                        Text('Marca: $marcaNombre',
                            style: const TextStyle(
                                fontFamily: _kFont,
                                fontSize: 12,
                                color: Colors.black54)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 20),
          Expanded(
            child: StreamBuilder<List<FichaTecnicaDoc>>(
              stream: svc.streamFichasTecnicas(empresaId),
              builder: (ctx, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final fichas = (snap.data ?? [])
                    .where((f) =>
                        f.productoId == productoId && f.marcaId == marcaId)
                    .toList()
                  ..sort((a, b) => a.proveedorNombre.compareTo(b.proveedorNombre));

                return ListView(
                  controller: ctrl,
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 20),
                  children: [
                    ...fichas.map((f) => _FichaProveedorCard(
                          ficha: f,
                          svc: svc,
                          userId: userId,
                          empresaId: empresaId,
                          productoId: productoId,
                          productoNombre: productoNombre,
                          productoCategoria: productoCategoria,
                          marcaId: marcaId,
                          marcaNombre: marcaNombre,
                        )),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => showModalBottomSheet(
                        context: ctx,
                        isScrollControlled: true,
                        useSafeArea: true,
                        backgroundColor: Colors.white,
                        shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.vertical(
                                top: Radius.circular(20))),
                        builder: (_) => _SubirFichaSheet(
                          empresaId: empresaId,
                          svc: svc,
                          productoId: productoId,
                          productoNombre: productoNombre,
                          productoCategoria: productoCategoria,
                          marcaId: marcaId,
                          marcaNombre: marcaNombre,
                          userId: userId,
                          fichasExistentes: fichas,
                        ),
                      ),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Agregar ficha para otro proveedor',
                          style: TextStyle(fontFamily: _kFont)),
                      style: OutlinedButton.styleFrom(
                          side:
                              const BorderSide(color: Color(0xFF0277BD)),
                          padding: const EdgeInsets.symmetric(vertical: 10)),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FichaProveedorCard extends StatelessWidget {
  final FichaTecnicaDoc ficha;
  final ComprasService svc;
  final String userId;
  final String empresaId;
  final String productoId;
  final String productoNombre;
  final String productoCategoria;
  final String marcaId;
  final String marcaNombre;

  const _FichaProveedorCard({
    required this.ficha,
    required this.svc,
    required this.userId,
    required this.empresaId,
    required this.productoId,
    required this.productoNombre,
    required this.productoCategoria,
    required this.marcaId,
    required this.marcaNombre,
  });

  @override
  Widget build(BuildContext context) {
    final doc = ficha.documentoActual;
    Color badgeColor;
    String badgeLabel;
    if (doc == null || !doc.tieneDoc) {
      badgeColor = Colors.grey;
      badgeLabel = 'Sin ficha';
    } else if (doc.aprobado) {
      badgeColor = kComprasGreen;
      badgeLabel = 'Aprobada';
    } else if (doc.rechazado) {
      badgeColor = kComprasRed;
      badgeLabel = 'Rechazada';
    } else {
      badgeColor = const Color(0xFFB45309);
      badgeLabel = 'Pendiente';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(ficha.proveedorNombre,
                      style: const TextStyle(
                          fontFamily: _kFont,
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: badgeColor.withAlpha(30),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: badgeColor)),
                  child: Text(badgeLabel,
                      style: TextStyle(
                          fontFamily: _kFont,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: badgeColor)),
                ),
              ],
            ),
            if (doc != null && doc.tieneDoc) ...[
              const SizedBox(height: 4),
              Text(doc.nombre ?? '',
                  style: const TextStyle(
                      fontFamily: _kFont, fontSize: 12, color: Colors.black54)),
              if (doc.observacionActualizacion?.isNotEmpty == true)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Obs: ${doc.observacionActualizacion}',
                    style: const TextStyle(
                        fontFamily: _kFont,
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                        color: Colors.black45),
                  ),
                ),
              if (doc.rechazado && doc.observacionCalidad?.isNotEmpty == true)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Motivo rechazo: ${doc.observacionCalidad}',
                    style: const TextStyle(
                        fontFamily: _kFont,
                        fontSize: 11,
                        color: kComprasRed),
                  ),
                ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                if (doc != null && doc.tieneDoc)
                  TextButton.icon(
                    onPressed: () =>
                        _abrirUrl(context, doc.url),
                    icon: const Icon(Icons.open_in_new, size: 14),
                    label: const Text('Ver PDF',
                        style:
                            TextStyle(fontFamily: _kFont, fontSize: 12)),
                    style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4)),
                  ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    backgroundColor: Colors.white,
                    shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(
                            top: Radius.circular(20))),
                    builder: (_) => _SubirFichaSheet(
                      empresaId: empresaId,
                      svc: svc,
                      productoId: productoId,
                      productoNombre: productoNombre,
                      productoCategoria: productoCategoria,
                      marcaId: marcaId,
                      marcaNombre: marcaNombre,
                      userId: userId,
                      fichasExistentes: [],
                      fichaExistente: ficha,
                    ),
                  ),
                  icon: const Icon(Icons.upload_file, size: 14,
                      color: Color(0xFF0277BD)),
                  label: Text(
                      doc != null && doc.tieneDoc ? 'Actualizar' : 'Subir',
                      style: const TextStyle(
                          fontFamily: _kFont,
                          fontSize: 12,
                          color: Color(0xFF0277BD))),
                  style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SUBIR / ACTUALIZAR FICHA TÉCNICA — bottom sheet
// ══════════════════════════════════════════════════════════════════════════════

class _SubirFichaSheet extends StatefulWidget {
  final String empresaId;
  final ComprasService svc;
  final String productoId;
  final String productoNombre;
  final String productoCategoria;
  final String marcaId;
  final String marcaNombre;
  final String userId;
  /// Fichas ya existentes para el producto+marca (para validar unicidad proveedor).
  final List<FichaTecnicaDoc> fichasExistentes;
  /// Si se pasa, es actualización de la ficha existente.
  final FichaTecnicaDoc? fichaExistente;

  const _SubirFichaSheet({
    required this.empresaId,
    required this.svc,
    required this.productoId,
    required this.productoNombre,
    required this.productoCategoria,
    required this.marcaId,
    required this.marcaNombre,
    required this.userId,
    required this.fichasExistentes,
    this.fichaExistente,
  });

  @override
  State<_SubirFichaSheet> createState() => _SubirFichaSheetState();
}

class _SubirFichaSheetState extends State<_SubirFichaSheet> {
  final _obsCtrl = TextEditingController();
  bool get isUpdate => widget.fichaExistente != null;

  // Proveedor seleccionado (sólo para fichas nuevas)
  ProveedorDoc? _proveedor;
  List<ProveedorDoc> _proveedores = [];
  bool _loadingProvs = true;

  // Archivo
  String? _fileName;
  Uint8List? _fileBytes;
  bool _subiendo = false;

  // Web drag-and-drop
  bool _isDragging = false;
  StreamSubscription<bool>? _wDragSub;
  StreamSubscription<DroppedFile>? _wFileSub;

  @override
  void initState() {
    super.initState();
    _cargarProveedores();
    if (kIsWeb) {
      WebDragDrop.instance.enable();
      _wDragSub = WebDragDrop.instance.isDragging
          .listen((v) { if (mounted) setState(() => _isDragging = v); });
      _wFileSub = WebDragDrop.instance.droppedFile.listen(_onWebFileDrop);
    }
  }

  @override
  void dispose() {
    _obsCtrl.dispose();
    if (kIsWeb) WebDragDrop.instance.disable();
    _wDragSub?.cancel();
    _wFileSub?.cancel();
    super.dispose();
  }

  Future<void> _cargarProveedores() async {
    final snap = await FirebaseFirestore.instance
        .collection('TBL_COMPRAS_PROVEEDORES')
        .where('empresaId', isEqualTo: widget.empresaId)
        .get();
    if (!mounted) return;
    setState(() {
      _proveedores = snap.docs
          .map((d) => ProveedorDoc.fromMap(d.id, d.data()))
          .toList()
        ..sort((a, b) => a.razonSocial.compareTo(b.razonSocial));
      // Pre-seleccionar si es actualización
      if (isUpdate) {
        try {
          _proveedor = _proveedores.firstWhere(
              (p) => p.id == widget.fichaExistente!.proveedorId);
        } catch (_) {}
      }
      _loadingProvs = false;
    });
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final f = result.files.first;
    setState(() {
      _fileName = f.name;
      _fileBytes = f.bytes;
    });
  }

  // Recibe archivo arrastrado vía dart:html
  void _onWebFileDrop(DroppedFile file) {
    if (!mounted) return;
    final name = file.name;
    final ext = name.toLowerCase().split('.').last;
    if (!['pdf', 'jpg', 'jpeg', 'png'].contains(ext)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Solo se permiten PDF, JPG o PNG',
                style: TextStyle(fontFamily: _kFont))));
      }
      return;
    }
    if (file.bytes.length > 10 * 1024 * 1024) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('El archivo supera el límite de 10 MB',
                style: TextStyle(fontFamily: _kFont))));
      }
      return;
    }
    setState(() {
      _fileName = name;
      _fileBytes = file.bytes;
    });
  }

  Widget _buildFileZone() {
    if (!kIsWeb) {
      return OutlinedButton.icon(
        onPressed: _subiendo ? null : _pickFile,
        icon: const Icon(Icons.attach_file, size: 16),
        label: Text(
          _fileName ?? 'Seleccionar PDF o imagen',
          style: const TextStyle(fontFamily: _kFont, fontSize: 13),
          overflow: TextOverflow.ellipsis,
        ),
        style: OutlinedButton.styleFrom(
            padding:
                const EdgeInsets.symmetric(vertical: 10, horizontal: 12)),
      );
    }

    // Web: zona drag-and-drop + botón separado para abrir selector de archivo
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Si hay archivo seleccionado, mostrar preview en lugar de la zona
        if (_fileBytes != null)
          Container(
            height: 80,
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green.shade300, width: 1.5),
            ),
            child: _buildFilePreview(),
          )
        else
          // Zona de arrastre
          SizedBox(
            height: 110,
            child: DropTarget(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: _isDragging
                      ? kComprasPrimary.withOpacity(0.07)
                      : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _isDragging
                        ? kComprasPrimary
                        : Colors.grey.shade300,
                    width: _isDragging ? 2 : 1.5,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.cloud_upload_outlined,
                        size: 34,
                        color: _isDragging
                            ? kComprasPrimary
                            : Colors.grey.shade400),
                    const SizedBox(height: 8),
                    Text(
                      _isDragging
                          ? '¡Suelta el archivo aquí!'
                          : 'Arrastra el archivo aquí',
                      style: TextStyle(
                          fontFamily: _kFont,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _isDragging
                              ? kComprasPrimary
                              : Colors.black54),
                    ),
                    const SizedBox(height: 2),
                    Text('PDF · JPG · PNG · Máx. 10 MB',
                        style: TextStyle(
                            fontFamily: _kFont,
                            fontSize: 10,
                            color: Colors.grey.shade500)),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: 6),
        // Botón separado para abrir selector de archivo
        OutlinedButton.icon(
          onPressed: _subiendo ? null : _pickFile,
          icon: Icon(Icons.folder_open,
              size: 14,
              color: _subiendo ? Colors.grey : kComprasPrimary),
          label: Text(
            _fileBytes != null
                ? 'Cambiar archivo'
                : 'o seleccionar archivo (PDF/img)',
            style: TextStyle(
                fontFamily: _kFont,
                fontSize: 12,
                color: _subiendo ? Colors.grey : kComprasPrimary),
          ),
          style: OutlinedButton.styleFrom(
            side: BorderSide(
                color: _subiendo
                    ? Colors.grey.shade300
                    : kComprasPrimary.withOpacity(0.5)),
            padding: const EdgeInsets.symmetric(vertical: 8),
          ),
        ),
      ],
    );
  }

  Widget _buildFilePreview() {
    final ext = (_fileName ?? '').split('.').last.toLowerCase();
    final isImg = ['jpg', 'jpeg', 'png'].contains(ext);
    return Row(
      children: [
        const SizedBox(width: 16),
        Icon(
          isImg ? Icons.image : Icons.picture_as_pdf,
          color: isImg ? Colors.blue.shade600 : Colors.red.shade600,
          size: 38,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _fileName ?? '',
                style: const TextStyle(
                    fontFamily: _kFont,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 3),
              Text(
                'Haz clic para cambiar',
                style: TextStyle(
                    fontFamily: _kFont,
                    fontSize: 11,
                    color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Icon(Icons.check_circle,
              color: Colors.green.shade600, size: 22),
        ),
      ],
    );
  }

  Future<void> _subir() async {
    if (!isUpdate && _proveedor == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Selecciona un proveedor.',
              style: TextStyle(fontFamily: _kFont))));
      return;
    }
    if (isUpdate && _obsCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Ingresa el motivo de la actualización.',
              style: TextStyle(fontFamily: _kFont))));
      return;
    }
    if (_fileBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Selecciona un archivo PDF o imagen.',
              style: TextStyle(fontFamily: _kFont))));
      return;
    }

    setState(() => _subiendo = true);
    try {
      final ext = _fileName?.split('.').last.toLowerCase() ?? 'pdf';
      final contentType =
          ext == 'pdf' ? 'application/pdf' : 'image/$ext';
      final doc = await widget.svc.subirBytes(
        bytes: _fileBytes!,
        empresaId: widget.empresaId,
        carpeta: 'fichas_tecnicas',
        nombre: _fileName ?? 'ficha.pdf',
        contentType: contentType,
        pendienteCalidad: false, // guardarFichaTecnica marca pendiente_revision_calidad
      );

      final prov = isUpdate
          ? ProveedorDoc(
              id: widget.fichaExistente!.proveedorId,
              empresaId: widget.empresaId,
              nit: '',
              razonSocial: widget.fichaExistente!.proveedorNombre,
              createdAt: Timestamp.now())
          : _proveedor!;

      final ficha = FichaTecnicaDoc(
        id: isUpdate ? widget.fichaExistente!.id : '',
        empresaId: widget.empresaId,
        proveedorId: prov.id,
        proveedorNombre: prov.razonSocial,
        productoId: widget.productoId,
        productoNombre: widget.productoNombre,
        productoCategoria: widget.productoCategoria,
        marcaId: widget.marcaId,
        marcaNombre: widget.marcaNombre,
        documentoActual: doc,
        historial: isUpdate ? widget.fichaExistente!.historial : [],
        creadoPor: widget.userId,
        createdAt: isUpdate
            ? widget.fichaExistente!.createdAt
            : Timestamp.now(),
      );

      await widget.svc.guardarFichaTecnica(
        ficha,
        isNew: !isUpdate,
        observacion: _obsCtrl.text.trim(),
        actualizadoPor: widget.userId,
      );

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              isUpdate
                  ? 'Ficha actualizada. Pendiente de revisión de calidad.'
                  : 'Ficha cargada. Pendiente de revisión de calidad.',
              style: const TextStyle(fontFamily: _kFont))));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e',
              style: const TextStyle(fontFamily: _kFont))));
    } finally {
      if (mounted) setState(() => _subiendo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Text(
            isUpdate
                ? 'Actualizar ficha técnica'
                : 'Agregar ficha técnica',
            style: const TextStyle(
                fontFamily: _kFont,
                fontSize: 16,
                fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            '${widget.productoNombre}'
            '${widget.marcaNombre.isNotEmpty ? ' / ${widget.marcaNombre}' : ''}',
            style: const TextStyle(
                fontFamily: _kFont, fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 16),
          // Proveedor
          if (!isUpdate)
            _loadingProvs
                ? const LinearProgressIndicator()
                : DropdownButtonFormField<ProveedorDoc>(
                    value: _proveedor,
                    decoration: const InputDecoration(
                      labelText: 'Proveedor *',
                      labelStyle: TextStyle(fontFamily: _kFont),
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    isExpanded: true,
                    items: _proveedores
                        .where((p) => widget.fichasExistentes
                            .every((f) => f.proveedorId != p.id))
                        .map((p) => DropdownMenuItem(
                              value: p,
                              child: Text(p.razonSocial,
                                  style: const TextStyle(
                                      fontFamily: _kFont, fontSize: 13),
                                  overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _proveedor = v),
                  ),
          if (!isUpdate) const SizedBox(height: 12),
          if (isUpdate)
            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8)),
              child: Row(
                children: [
                  const Icon(Icons.store, size: 16, color: Colors.black54),
                  const SizedBox(width: 8),
                  Text(widget.fichaExistente!.proveedorNombre,
                      style: const TextStyle(
                          fontFamily: _kFont,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          // Observación
          TextFormField(
            controller: _obsCtrl,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: isUpdate
                  ? 'Motivo de actualización *'
                  : 'Observación (opcional)',
              labelStyle: const TextStyle(fontFamily: _kFont),
              hintText: isUpdate
                  ? '¿Por qué se actualiza la ficha técnica?'
                  : 'Nota inicial sobre la ficha…',
              border: const OutlineInputBorder(),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            style: const TextStyle(fontFamily: _kFont, fontSize: 13),
          ),
          const SizedBox(height: 12),
          // Archivo (botón normal en móvil, zona drag-and-drop en web)
          _buildFileZone(),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0277BD),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12)),
              onPressed: _subiendo ? null : _subir,
              icon: _subiendo
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.upload_file),
              label: Text(
                _subiendo
                    ? 'Subiendo...'
                    : (isUpdate ? 'Actualizar ficha' : 'Subir ficha'),
                style: const TextStyle(
                    fontFamily: _kFont, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SELECTOR DE MARCA para ProductoFormSheet (bottom sheet con búsqueda)
// ══════════════════════════════════════════════════════════════════════════════

class _MarcaSelectorSheet extends StatefulWidget {
  final List<MarcaDoc> marcas;
  const _MarcaSelectorSheet({required this.marcas});
  @override
  State<_MarcaSelectorSheet> createState() => _MarcaSelectorSheetState();
}

class _MarcaSelectorSheetState extends State<_MarcaSelectorSheet> {
  final _ctrl = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _q.isEmpty
        ? widget.marcas
        : widget.marcas
            .where((m) =>
                m.descripcion.toLowerCase().contains(_q) ||
                m.codigo.toLowerCase().contains(_q))
            .toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          margin: const EdgeInsets.symmetric(vertical: 10),
          width: 40,
          height: 4,
          decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(4)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              const Icon(Icons.label_important, color: Color(0xFF1976D2)),
              const SizedBox(width: 8),
              const Text('Seleccionar Marca',
                  style: TextStyle(
                      fontFamily: _kFont,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: TextField(
            controller: _ctrl,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Buscar marca...',
              prefixIcon: const Icon(Icons.search, size: 18),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
            style: const TextStyle(fontFamily: _kFont, fontSize: 13),
            onChanged: (v) => setState(() => _q = v.toLowerCase()),
          ),
        ),
        ConstrainedBox(
          constraints:
              BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.4),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: filtered.length,
            itemBuilder: (_, i) {
              final m = filtered[i];
              return ListTile(
                leading: const Icon(Icons.label,
                    size: 18, color: Color(0xFF1976D2)),
                title: Text(m.descripcion,
                    style: const TextStyle(
                        fontFamily: _kFont, fontSize: 14)),
                subtitle: Text(m.codigo,
                    style: const TextStyle(
                        fontFamily: _kFont,
                        fontSize: 12,
                        color: Colors.black54)),
                onTap: () => Navigator.pop(context, m),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// RECEPCIONES SCREEN — listado de recepciones
// ══════════════════════════════════════════════════════════════════════════════

class _RecepcionesScreen extends StatefulWidget {
  final String empresaId;
  final ComprasService svc;
  final String userId;

  const _RecepcionesScreen({
    required this.empresaId,
    required this.svc,
    required this.userId,
  });

  @override
  State<_RecepcionesScreen> createState() => _RecepcionesScreenState();
}

class _RecepcionesScreenState extends State<_RecepcionesScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kComprasBg,
      appBar: AppBar(
        title: const Text('Recepción de Mercancía',
            style: TextStyle(fontFamily: _kFont, fontWeight: FontWeight.bold)),
        backgroundColor: kComprasPrimary,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<List<RecepcionDoc>>(
        stream: widget.svc.streamRecepciones(widget.empresaId),
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Error al cargar: ${snap.error}',
                    style: const TextStyle(
                        fontFamily: _kFont, color: Colors.red)),
              ),
            );
          }
          final list = snap.data ?? [];
          if (list.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.local_shipping_outlined,
                      size: 64, color: Colors.grey.shade300),
                  const SizedBox(height: 12),
                  const Text('Sin recepciones registradas',
                      style: TextStyle(
                          fontFamily: _kFont, color: Colors.black45)),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 80),
            itemCount: list.length,
            itemBuilder: (_, i) {
              final r = list[i];
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 1,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => _NuevaRecepcionScreen(
                        empresaId: widget.empresaId,
                        svc: widget.svc,
                        existing: r,
                        userId: widget.userId,
                      ),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(r.razonSocial,
                                  style: const TextStyle(
                                      fontFamily: _kFont,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15)),
                            ),
                            Text(_fmtFecha(r.fecha),
                                style: const TextStyle(
                                    fontFamily: _kFont,
                                    fontSize: 12,
                                    color: Colors.black45)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(Icons.badge,
                                size: 13, color: Colors.black38),
                            const SizedBox(width: 4),
                            Text('NIT: ${r.nit}',
                                style: const TextStyle(
                                    fontFamily: _kFont,
                                    fontSize: 12,
                                    color: Colors.black54)),
                            const Spacer(),
                            if (r.ordenCompra.isNotEmpty) ...[
                              const Icon(Icons.receipt,
                                  size: 13, color: Colors.black38),
                              const SizedBox(width: 4),
                              Text('OC: ${r.ordenCompra}',
                                  style: const TextStyle(
                                      fontFamily: _kFont,
                                      fontSize: 12,
                                      color: Colors.black54)),
                            ],
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _Chip(
                                '${r.productos.length} producto${r.productos.length == 1 ? '' : 's'}',
                                kComprasPrimary),
                            const Spacer(),
                            const Icon(Icons.chevron_right,
                                color: Colors.black26),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: kComprasPrimary,
        foregroundColor: Colors.white,
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _NuevaRecepcionScreen(
              empresaId: widget.empresaId,
              svc: widget.svc,
              userId: widget.userId,
            ),
          ),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Nueva Recepción',
            style: TextStyle(fontFamily: _kFont)),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// NUEVA RECEPCION SCREEN
// ══════════════════════════════════════════════════════════════════════════════

class _RecepcionEntry {
  ProductoDoc? producto;
  MarcaDoc? marcaSeleccionada;
  String pendingMarcaId = ''; // para restaurar al editar
  Map<String, DocAdjunto> documentos = {};
  bool expandido = false;
  final observacionesCtrl = TextEditingController();

  _RecepcionEntry();

  void dispose() => observacionesCtrl.dispose();
}

class _NuevaRecepcionScreen extends StatefulWidget {
  final String empresaId;
  final ComprasService svc;
  final RecepcionDoc? existing;
  final String userId;

  const _NuevaRecepcionScreen({
    required this.empresaId,
    required this.svc,
    this.existing,
    required this.userId,
  });

  @override
  State<_NuevaRecepcionScreen> createState() => _NuevaRecepcionScreenState();
}

class _NuevaRecepcionScreenState extends State<_NuevaRecepcionScreen> {
  ProveedorDoc? _proveedor;
  final _provCtrl = TextEditingController();
  final _ordenCtrl = TextEditingController();
  List<_RecepcionEntry> _entries = [];
  List<ProveedorDoc> _proveedores = [];
  List<ProductoDoc> _productos = [];
  List<MarcaDoc> _marcas = [];
  List<FichaTecnicaDoc> _fichasTecnicas = [];
  bool _guardando = false;
  bool _loadingProvs = true;

  bool get isNew => widget.existing == null;

  /// Busca la ficha técnica para una entrada (proveedor + producto + marca).
  FichaTecnicaDoc? _fichaParaEntry(_RecepcionEntry e) {
    if (_proveedor == null || e.producto == null) return null;
    try {
      return _fichasTecnicas.firstWhere((f) =>
          f.proveedorId == _proveedor!.id &&
          f.productoId == e.producto!.id &&
          f.marcaId == (e.marcaSeleccionada?.id ?? ''));
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    if (!isNew) {
      final r = widget.existing!;
      _ordenCtrl.text = r.ordenCompra;
      _entries = r.productos.map((rp) {
        final e = _RecepcionEntry();
        e.pendingMarcaId = rp.marcaId;
        e.documentos = Map.from(rp.documentos);
        e.observacionesCtrl.text = rp.observaciones;
        return e;
      }).toList();
    }
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    try {
      // Sin orderBy para evitar requerir índice compuesto en Firestore.
      // El ordenamiento se hace en cliente.
      final pSnap = await FirebaseFirestore.instance
          .collection('TBL_COMPRAS_PROVEEDORES')
          .where('empresaId', isEqualTo: widget.empresaId)
          .get();
      final prSnap = await FirebaseFirestore.instance
          .collection('TBL_COMPRAS_PRODUCTOS')
          .where('empresaId', isEqualTo: widget.empresaId)
          .get();
      final mSnap = await FirebaseFirestore.instance
          .collection('TBL_COMPRAS_MARCAS')
          .where('empresaId', isEqualTo: widget.empresaId)
          .get();

      if (!mounted) return;

      final provs = pSnap.docs
          .map((d) => ProveedorDoc.fromMap(d.id, d.data()))
          .toList()
        ..sort((a, b) => a.razonSocial.compareTo(b.razonSocial));

      final prods = prSnap.docs
          .map((d) => ProductoDoc.fromMap(d.id, d.data()))
          .toList()
        ..sort((a, b) => a.nombre.compareTo(b.nombre));

      final marcas = mSnap.docs
          .map((d) => MarcaDoc.fromMap(d.id, d.data()))
          .toList()
        ..sort((a, b) => a.descripcion.compareTo(b.descripcion));

      final fichas = await widget.svc.getFichasTecnicas(widget.empresaId);

      setState(() {
        _proveedores = provs;
        _productos = prods;
        _marcas = marcas;
        _fichasTecnicas = fichas;

        if (!isNew) {
          final r = widget.existing!;
          try {
            _proveedor =
                _proveedores.firstWhere((p) => p.id == r.proveedorId);
            _provCtrl.text = _proveedor?.razonSocial ?? r.razonSocial;
          } catch (_) {
            _provCtrl.text = r.razonSocial;
          }
          for (int i = 0;
              i < _entries.length && i < r.productos.length;
              i++) {
            final rp = r.productos[i];
            // Restaurar producto
            try {
              _entries[i].producto =
                  _productos.firstWhere((p) => p.id == rp.productoId);
            } catch (_) {}
            // Restaurar marca
            if (_entries[i].pendingMarcaId.isNotEmpty) {
              try {
                _entries[i].marcaSeleccionada = _marcas
                    .firstWhere((m) => m.id == _entries[i].pendingMarcaId);
              } catch (_) {}
            }
          }
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar datos: $e'),
            backgroundColor: kComprasRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingProvs = false);
    }
  }

  @override
  void dispose() {
    _provCtrl.dispose();
    _ordenCtrl.dispose();
    for (final e in _entries) {
      e.dispose();
    }
    super.dispose();
  }

  Future<void> _guardar() async {
    if (_proveedor == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Seleccione un proveedor')));
      return;
    }
    if (_entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Agregue al menos un producto')));
      return;
    }
    final sinProducto = _entries.any((e) => e.producto == null);
    if (sinProducto) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Seleccione el producto en cada fila')));
      return;
    }

    setState(() => _guardando = true);
    try {
      final productos = _entries.map((e) {
        return RecepcionProducto(
          productoId: e.producto!.id,
          nombre: e.producto!.nombre,
          categoria: e.producto!.categoria,
          marcaId: e.marcaSeleccionada?.id ?? '',
          marca: e.marcaSeleccionada?.descripcion ?? '',
          origen: e.producto!.origen,
          documentos: e.documentos,
          observaciones: e.observacionesCtrl.text.trim(),
        );
      }).toList();

      final r = RecepcionDoc(
        id: widget.existing?.id ?? '',
        empresaId: widget.empresaId,
        fecha: widget.existing?.fecha ?? Timestamp.now(),
        proveedorId: _proveedor!.id,
        nit: _proveedor!.nit,
        razonSocial: _proveedor!.razonSocial,
        ordenCompra: _ordenCtrl.text.trim(),
        productos: productos,
        productoIds: productos.map((p) => p.productoId).toList(),
        creadoPor: widget.existing?.creadoPor ?? widget.userId,
        createdAt: widget.existing?.createdAt ?? Timestamp.now(),
      );
      await widget.svc.guardarRecepcion(r);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Recepción guardada correctamente'),
          backgroundColor: kComprasGreen,
        ));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: kComprasRed));
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  void _agregarProducto() {
    setState(() => _entries.add(_RecepcionEntry()));
  }

  void _eliminarEntrada(int idx) {
    setState(() => _entries.removeAt(idx));
  }

  Future<void> _seleccionarProducto(int idx) async {
    final seleccionado = await showModalBottomSheet<ProductoDoc>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _ProductoSelectorSheet(productos: _productos),
    );
    if (seleccionado != null) {
      setState(() {
        _entries[idx].producto = seleccionado;
        _entries[idx].marcaSeleccionada = null; // limpiar marca al cambiar producto
      });
    }
  }

  Future<void> _adjuntarDocProducto(int idx, String key) async {
    if (key == 'fichaTecnica' &&
        _entries[idx].observacionesCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
          'Antes de cargar la ficha técnica, registre la observación de por qué se actualiza.',
        ),
      ));
      return;
    }
    final p = _entries[idx].producto;
    final nombreSug =
        '${_proveedor?.nit ?? ''}_${p?.nombre ?? 'prod'}_${kDocRecepcionLabels[key] ?? key}';
    final doc = await _mostrarEscaneador(
      context,
      empresaId: widget.empresaId,
      carpeta: 'recepciones',
      nombreSugerido: nombreSug,
      svc: widget.svc,
    );
    if (doc != null) {
      // Marcar como pendiente de revisión calidad
      final docPendiente = doc.copyWith(
        estadoCalidad: 'pendiente_revision_calidad',
        observacionActualizacion: _entries[idx].observacionesCtrl.text.trim(),
      );
      setState(() => _entries[idx].documentos[key] = docPendiente);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fechaDisplay = widget.existing != null
        ? _fmtFechaHora(widget.existing!.fecha)
        : _fmtFechaHora(Timestamp.now());

    return Scaffold(
      backgroundColor: kComprasBg,
      appBar: AppBar(
        title: Text(isNew ? 'Nueva Recepción' : 'Ver Recepción',
            style: const TextStyle(
                fontFamily: _kFont, fontWeight: FontWeight.bold)),
        backgroundColor: kComprasPrimary,
        foregroundColor: Colors.white,
        actions: [
          if (_guardando)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white)),
            )
          else
            TextButton(
              onPressed: _guardar,
              child: const Text('Guardar',
                  style: TextStyle(
                      color: Colors.white,
                      fontFamily: _kFont,
                      fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      body: _loadingProvs
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Encabezado ──────────────────────────
                  _SectionHeader(
                      'Encabezado', Icons.info_outline, kComprasPrimary),
                  const SizedBox(height: 12),
                  // Fecha (solo lectura)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade200)),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today,
                            size: 16, color: Colors.black45),
                        const SizedBox(width: 8),
                        Text('Fecha: $fechaDisplay',
                            style: const TextStyle(
                                fontFamily: _kFont,
                                fontSize: 13,
                                color: Colors.black87)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Proveedor (typeahead)
                  TypeAheadField<ProveedorDoc>(
                    textFieldConfiguration: TextFieldConfiguration(
                      controller: _provCtrl,
                      decoration: _inputDecoration('Proveedor *').copyWith(
                        hintText: 'Buscar proveedor...',
                        prefixIcon: const Icon(Icons.business, size: 18),
                      ),
                      style:
                          const TextStyle(fontFamily: _kFont, fontSize: 14),
                    ),
                    suggestionsCallback: (pattern) => _proveedores
                        .where((p) =>
                            p.razonSocial
                                .toLowerCase()
                                .contains(pattern.toLowerCase()) ||
                            p.nit.contains(pattern))
                        .toList(),
                    itemBuilder: (ctx, p) => ListTile(
                      dense: true,
                      title: Text(p.razonSocial,
                          style:
                              const TextStyle(fontFamily: _kFont, fontSize: 13)),
                      subtitle: Text('NIT: ${p.nit}',
                          style: const TextStyle(
                              fontFamily: _kFont, fontSize: 11)),
                    ),
                    onSuggestionSelected: (p) =>
                        setState(() {
                          _proveedor = p;
                          _provCtrl.text = p.razonSocial;
                        }),
                    noItemsFoundBuilder: (_) => const Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('Sin resultados',
                          style: TextStyle(fontFamily: _kFont)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // NIT (auto)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade200)),
                    child: Row(
                      children: [
                        const Icon(Icons.badge,
                            size: 16, color: Colors.black38),
                        const SizedBox(width: 8),
                        Text(
                            'NIT: ${_proveedor?.nit ?? '(Seleccione proveedor)'}',
                            style: TextStyle(
                                fontFamily: _kFont,
                                fontSize: 13,
                                color: _proveedor != null
                                    ? Colors.black87
                                    : Colors.black38)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _ordenCtrl,
                    decoration: _inputDecoration('Orden de Compra')
                        .copyWith(hintText: 'OC-2024-001'),
                    style:
                        const TextStyle(fontFamily: _kFont, fontSize: 14),
                  ),
                  const SizedBox(height: 24),
                  // ── Productos ────────────────────────────
                  _SectionHeader(
                      'Productos recibidos', Icons.inventory, kComprasPrimary),
                  const SizedBox(height: 12),
                  ..._entries.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final e = entry.value;
                    return _ProductoEntryCard(
                      idx: idx,
                      entry: e,
                      onSelectProducto: () => _seleccionarProducto(idx),
                      onRemove: () => _eliminarEntrada(idx),
                      onAdjuntarDoc: (key) => _adjuntarDocProducto(idx, key),
                      onVerDoc: (key) => _abrirUrl(
                          context, e.documentos[key]?.url),
                      onChanged: () => setState(() {}),
                      todasMarcas: _marcas,
                      onMarcaChanged: (m) =>
                          setState(() => _entries[idx].marcaSeleccionada = m),
                      fichaTecnicaDoc: _fichaParaEntry(e),
                      onWebUploadDoc: (key, bytes, name) async {
                        if (key == 'fichaTecnica' &&
                            _entries[idx]
                                .observacionesCtrl
                                .text
                                .trim()
                                .isEmpty) {
                          throw Exception(
                              'Registra la observación antes de cargar la ficha técnica.');
                        }
                        final ext = name.toLowerCase().split('.').last;
                        final ct = ext == 'pdf'
                            ? 'application/pdf'
                            : 'image/$ext';
                        final doc = await widget.svc.subirBytes(
                          bytes: bytes,
                          empresaId: widget.empresaId,
                          carpeta: 'recepciones',
                          nombre: name,
                          contentType: ct,
                        );
                        final docPendiente = doc.copyWith(
                          estadoCalidad: 'pendiente_revision_calidad',
                          observacionActualizacion:
                              _entries[idx].observacionesCtrl.text.trim(),
                        );
                        setState(() =>
                            _entries[idx].documentos[key] = docPendiente);
                      },
                      onWebDeleteDoc: (key) =>
                          setState(() => _entries[idx].documentos.remove(key)),
                    );
                  }),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _agregarProducto,
                      icon: const Icon(Icons.add, color: kComprasPrimary),
                      label: const Text('Agregar Producto',
                          style: TextStyle(
                              fontFamily: _kFont, color: kComprasPrimary)),
                      style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: kComprasPrimary),
                          padding:
                              const EdgeInsets.symmetric(vertical: 12)),
                    ),
                  ),
                  const SizedBox(height: 30),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _guardando ? null : _guardar,
                      icon: _guardando
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.save),
                      label: Text(_guardando ? 'Guardando...' : 'Guardar Recepción',
                          style: const TextStyle(fontFamily: _kFont)),
                      style: FilledButton.styleFrom(
                          backgroundColor: kComprasPrimary,
                          padding:
                              const EdgeInsets.symmetric(vertical: 14)),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }
}

class _ProductoEntryCard extends StatelessWidget {
  final int idx;
  final _RecepcionEntry entry;
  final VoidCallback onSelectProducto;
  final VoidCallback onRemove;
  final void Function(String key) onAdjuntarDoc;
  final void Function(String key) onVerDoc;
  final VoidCallback onChanged;
  final List<MarcaDoc> todasMarcas;
  final void Function(MarcaDoc?) onMarcaChanged;
  /// Ficha técnica encontrada en la colección TBL_COMPRAS_FICHAS_TECNICAS para
  /// este proveedor + producto + marca. Null si no existe todavía.
  final FichaTecnicaDoc? fichaTecnicaDoc;
  /// Solo web: recibe (key, bytes, name) y sube el archivo directamente.
  final Future<void> Function(String key, Uint8List bytes, String name)?
      onWebUploadDoc;

  /// Solo web: elimina el documento ya adjunto para la clave indicada.
  final void Function(String key)? onWebDeleteDoc;

  const _ProductoEntryCard({
    required this.idx,
    required this.entry,
    required this.onSelectProducto,
    required this.onRemove,
    required this.onAdjuntarDoc,
    required this.onVerDoc,
    required this.onChanged,
    required this.todasMarcas,
    required this.onMarcaChanged,
    this.fichaTecnicaDoc,
    this.onWebUploadDoc,
    this.onWebDeleteDoc,
  });

  @override
  Widget build(BuildContext context) {
    final producto = entry.producto;
    final esImportado = producto?.origen == 'IMPORTADO';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          // Header row
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            onTap: () {
              entry.expandido = !entry.expandido;
              onChanged();
            },
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                        color: kComprasPrimary.withOpacity(0.1),
                        shape: BoxShape.circle),
                    child: Center(
                      child: Text('${idx + 1}',
                          style: const TextStyle(
                              fontFamily: _kFont,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: kComprasPrimary)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: producto == null
                        ? GestureDetector(
                            onTap: onSelectProducto,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 8, horizontal: 10),
                              decoration: BoxDecoration(
                                  border: Border.all(
                                      color: kComprasPrimary.withOpacity(0.4),
                                      style: BorderStyle.solid),
                                  borderRadius: BorderRadius.circular(8)),
                              child: const Row(
                                children: [
                                  Icon(Icons.search,
                                      size: 16, color: kComprasPrimary),
                                  SizedBox(width: 6),
                                  Text('Seleccionar producto...',
                                      style: TextStyle(
                                          fontFamily: _kFont,
                                          fontSize: 13,
                                          color: kComprasPrimary)),
                                ],
                              ),
                            ),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              GestureDetector(
                                onTap: onSelectProducto,
                                child: Text(producto.nombre,
                                    style: const TextStyle(
                                        fontFamily: _kFont,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14)),
                              ),
                              Wrap(
                                spacing: 4,
                                children: [
                                  _Chip(producto.categoria, kComprasPrimary),
                                  _Chip(producto.unidadMedida, Colors.blueGrey),
                                  _Chip(
                                    esImportado ? 'Importado' : 'Nacional',
                                    esImportado
                                        ? Colors.purple.shade700
                                        : Colors.green.shade700,
                                  ),
                                ],
                              ),
                            ],
                          ),
                  ),
                  IconButton(
                      onPressed: onRemove,
                      icon: const Icon(Icons.delete_outline,
                          color: Colors.red, size: 20),
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 32, minHeight: 32)),
                  Icon(
                      entry.expandido
                          ? Icons.expand_less
                          : Icons.expand_more,
                      color: Colors.black38),
                ],
              ),
            ),
          ),
          // Expanded section
          if (entry.expandido)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 16),
                  // ─ Selector de Marca ─
                  Builder(builder: (context) {
                    if (producto == null) return const SizedBox.shrink();
                    final linkedIds = producto.marcas
                        .map((r) => r.marcaId)
                        .toSet();
                    final disponibles = todasMarcas
                        .where((m) => linkedIds.contains(m.id))
                        .toList();
                    if (disponibles.isEmpty) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.info_outline,
                                size: 15, color: Colors.black45),
                            SizedBox(width: 6),
                            Text(
                              'Sin marcas configuradas para este producto',
                              style: TextStyle(
                                  fontFamily: _kFont,
                                  fontSize: 12,
                                  color: Colors.black45),
                            ),
                          ],
                        ),
                      );
                    }
                    final currentId = entry.marcaSeleccionada?.id;
                    final validId = disponibles.any((m) => m.id == currentId)
                        ? currentId
                        : null;
                    return DropdownButtonFormField<String>(
                      value: validId,
                      decoration: _inputDecoration('Marca').copyWith(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                      ),
                      isExpanded: true,
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('— Sin selección —',
                              style: TextStyle(
                                  fontFamily: _kFont,
                                  fontSize: 13,
                                  color: Colors.black45)),
                        ),
                        ...disponibles.map((m) => DropdownMenuItem(
                              value: m.id,
                              child: Text('${m.codigo} – ${m.descripcion}',
                                  style: const TextStyle(
                                      fontFamily: _kFont, fontSize: 13)),
                            )),
                      ],
                      onChanged: (id) {
                        if (id == null) {
                          onMarcaChanged(null);
                        } else {
                          try {
                            onMarcaChanged(disponibles
                                .firstWhere((m) => m.id == id));
                          } catch (_) {}
                        }
                        onChanged();
                      },
                      style: const TextStyle(
                          fontFamily: _kFont,
                          fontSize: 13,
                          color: Colors.black87),
                    );
                  }),
                  const SizedBox(height: 12),
                  // ─ Ficha técnica (nueva colección primero, fallback producto) ─
                  Builder(builder: (context) {
                    if (producto == null) return const SizedBox.shrink();

                    // 1. Ficha de la nueva colección (pasada como parámetro)
                    final fichaDoc = fichaTecnicaDoc;

                    // 2. Fallback: fichasTecnicasPorMarca / fichaTecnica del producto
                    final fichaMarcaLegacy = entry.marcaSeleccionada != null
                        ? producto.fichasTecnicasPorMarca[
                            entry.marcaSeleccionada!.id]
                        : null;
                    final fichaLegacy = (fichaMarcaLegacy?.tieneDoc == true)
                        ? fichaMarcaLegacy
                        : producto.fichaTecnica;

                    // Si no hay ninguna fuente, no mostrar
                    if (fichaDoc == null && fichaLegacy?.tieneDoc != true) {
                      return const SizedBox.shrink();
                    }

                    // Determinar fuente y estado
                    final doc = fichaDoc?.documentoActual ?? fichaLegacy;
                    final url = doc?.url;

                    Color badgeColor;
                    String badgeLabel;
                    String badgeTip;
                    if (fichaDoc != null) {
                      final d = fichaDoc.documentoActual;
                      if (d == null || !d.tieneDoc) {
                        badgeColor = Colors.grey;
                        badgeLabel = 'Sin ficha';
                        badgeTip = 'No hay ficha técnica registrada';
                      } else if (d.aprobado) {
                        badgeColor = kComprasGreen;
                        badgeLabel = 'Aprobada';
                        badgeTip = 'Ficha técnica aprobada por calidad';
                      } else if (d.rechazado) {
                        badgeColor = kComprasRed;
                        badgeLabel = 'Rechazada';
                        badgeTip =
                            'Ficha rechazada: ${d.observacionCalidad ?? ''}';
                      } else {
                        badgeColor = const Color(0xFFB45309);
                        badgeLabel = 'Pendiente';
                        badgeTip = 'Ficha técnica pendiente de revisión';
                      }
                    } else {
                      badgeColor = Colors.blue;
                      badgeLabel = 'Disponible';
                      badgeTip = 'Ficha técnica del producto';
                    }

                    return Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: badgeColor.withAlpha(20),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: badgeColor.withAlpha(80)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.description,
                                  size: 16, color: badgeColor),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    const Text('Ficha técnica',
                                        style: TextStyle(
                                            fontFamily: _kFont,
                                            fontSize: 12,
                                            fontWeight:
                                                FontWeight.w600)),
                                    Text(badgeTip,
                                        style: TextStyle(
                                            fontFamily: _kFont,
                                            fontSize: 11,
                                            color: badgeColor)),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                    color: badgeColor.withAlpha(30),
                                    borderRadius:
                                        BorderRadius.circular(6),
                                    border: Border.all(
                                        color: badgeColor)),
                                child: Text(badgeLabel,
                                    style: TextStyle(
                                        fontFamily: _kFont,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: badgeColor)),
                              ),
                              if (url != null && url.isNotEmpty)
                                IconButton(
                                  onPressed: () =>
                                      _abrirUrl(context, url),
                                  icon: const Icon(Icons.open_in_new,
                                      size: 16),
                                  tooltip: 'Ver ficha técnica',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                      minWidth: 32, minHeight: 32),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                    );
                  }),
                  // ─ Documentos requeridos ─
                  Row(
                    children: [
                      const Text('Documentos requeridos',
                          style: TextStyle(
                              fontFamily: _kFont,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.black54)),
                      const Spacer(),
                      if (producto?.categoria != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: kComprasPrimary.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(producto!.categoria,
                              style: const TextStyle(
                                  fontFamily: _kFont,
                                  fontSize: 10,
                                  color: kComprasPrimary)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...docsParaCategoria(producto?.categoria)
                      .map((key) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _DocAttachButton(
                              label: kDocRecepcionLabels[key] ?? key,
                              doc: entry.documentos[key],
                              onAttach: () => onAdjuntarDoc(key),
                              onView: entry.documentos[key]?.tieneDoc == true
                                  ? () => onVerDoc(key)
                                  : null,
                              onDelete: entry.documentos[key]?.tieneDoc ==
                                          true &&
                                      onWebDeleteDoc != null
                                  ? () => onWebDeleteDoc!(key)
                                  : null,
                              onWebUpload: onWebUploadDoc != null
                                  ? (bytes, name) =>
                                      onWebUploadDoc!(key, bytes, name)
                                  : null,
                            ),
                          )),
                  const SizedBox(height: 10),
                  // ─ Observaciones ─
                  TextField(
                    controller: entry.observacionesCtrl,
                    decoration: _inputDecoration(
                      'Observaciones de actualización (obligatorio para ficha técnica)',
                    ).copyWith(
                      hintText:
                      'Explique por qué se actualiza el documento (especialmente ficha técnica)...',
                      prefixIcon: const Icon(Icons.note_alt_outlined, size: 18),
                    ),
                    maxLines: 2,
                    style: const TextStyle(fontFamily: _kFont, fontSize: 13),
                    onChanged: (_) => onChanged(),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// Selector de producto para recepción
class _ProductoSelectorSheet extends StatefulWidget {
  final List<ProductoDoc> productos;

  const _ProductoSelectorSheet({required this.productos});

  @override
  State<_ProductoSelectorSheet> createState() => _ProductoSelectorSheetState();
}

class _ProductoSelectorSheetState extends State<_ProductoSelectorSheet> {
  final _ctrl = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _q.isEmpty
        ? widget.productos
        : widget.productos
            .where((p) =>
                p.nombre.toLowerCase().contains(_q) ||
                p.codigo.toLowerCase().contains(_q) ||
                p.categoria.toLowerCase().contains(_q))
            .toList();

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.symmetric(vertical: 10),
          width: 40,
          height: 4,
          decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(4)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: TextField(
            controller: _ctrl,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Buscar producto...',
              prefixIcon: const Icon(Icons.search, size: 18),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
            style: const TextStyle(fontFamily: _kFont, fontSize: 13),
            onChanged: (v) => setState(() => _q = v.toLowerCase()),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: filtered.length,
            itemBuilder: (_, i) {
              final p = filtered[i];
              return ListTile(
                dense: true,
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                      color: const Color(0xFF0277BD).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.inventory_2,
                      size: 18, color: Color(0xFF0277BD)),
                ),
                title: Text(p.nombre,
                    style: const TextStyle(
                        fontFamily: _kFont,
                        fontSize: 13,
                        fontWeight: FontWeight.w500)),
                subtitle: Text('${p.codigo} · ${p.categoria}',
                    style: const TextStyle(
                        fontFamily: _kFont, fontSize: 11)),
                trailing: _Chip(p.unidadMedida, Colors.blueGrey),
                onTap: () => Navigator.pop(context, p),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// CONSULTAS SCREEN
// ══════════════════════════════════════════════════════════════════════════════

class _ConsultasScreen extends StatefulWidget {
  final String empresaId;
  final ComprasService svc;

  const _ConsultasScreen({required this.empresaId, required this.svc});

  @override
  State<_ConsultasScreen> createState() => _ConsultasScreenState();
}

class _ConsultasScreenState extends State<_ConsultasScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kComprasBg,
      appBar: AppBar(
        title: const Text('Consultas',
            style: TextStyle(fontFamily: _kFont, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF283593),
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabCtrl,
          indicator: UnderlineTabIndicator(
            borderSide: const BorderSide(width: 3, color: kComprasAccent),
            borderRadius: BorderRadius.circular(999),
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          labelColor: Colors.white,
          unselectedLabelColor: const Color(0xFFB3E5FC),
          labelStyle: const TextStyle(
              fontFamily: _kFont,
              fontSize: 13,
              fontWeight: FontWeight.w700),
          unselectedLabelStyle: const TextStyle(
              fontFamily: _kFont,
              fontSize: 13,
              fontWeight: FontWeight.w500),
          tabs: const [
            Tab(icon: Icon(Icons.business, size: 18), text: 'Por Proveedor'),
            Tab(icon: Icon(Icons.inventory_2, size: 18), text: 'Por Producto'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _ConsultaProveedorTab(
              empresaId: widget.empresaId, svc: widget.svc),
          _ConsultaProductoTab(
              empresaId: widget.empresaId, svc: widget.svc),
        ],
      ),
    );
  }
}

// ─── Consulta Por Proveedor ────────────────────────────────────────────────

class _ConsultaProveedorTab extends StatefulWidget {
  final String empresaId;
  final ComprasService svc;

  const _ConsultaProveedorTab(
      {required this.empresaId, required this.svc});

  @override
  State<_ConsultaProveedorTab> createState() => _ConsultaProveedorTabState();
}

class _ConsultaProveedorTabState extends State<_ConsultaProveedorTab> {
  final _ctrl = TextEditingController();
  List<ProveedorDoc> _proveedores = [];
  ProveedorDoc? _seleccionado;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('TBL_COMPRAS_PROVEEDORES')
          .where('empresaId', isEqualTo: widget.empresaId)
          .get();
      if (!mounted) return;
      final lista = snap.docs
          .map((d) => ProveedorDoc.fromMap(d.id, d.data()))
          .toList()
        ..sort((a, b) => a.razonSocial.compareTo(b.razonSocial));
      setState(() => _proveedores = lista);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: kComprasRed));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TypeAheadField<ProveedorDoc>(
            textFieldConfiguration: TextFieldConfiguration(
              controller: _ctrl,
              decoration: _inputDecoration('Buscar proveedor').copyWith(
                prefixIcon: const Icon(Icons.search, size: 18),
                hintText: 'Nombre o NIT...',
              ),
              style: const TextStyle(fontFamily: _kFont, fontSize: 14),
            ),
            suggestionsCallback: (p) => _proveedores
                .where((x) =>
                    x.razonSocial.toLowerCase().contains(p.toLowerCase()) ||
                    x.nit.contains(p))
                .toList(),
            itemBuilder: (_, p) => ListTile(
              dense: true,
              title: Text(p.razonSocial,
                  style: const TextStyle(fontFamily: _kFont, fontSize: 13)),
              subtitle: Text(p.nit,
                  style:
                      const TextStyle(fontFamily: _kFont, fontSize: 11)),
            ),
            onSuggestionSelected: (p) =>
                setState(() {
                  _seleccionado = p;
                  _ctrl.text = p.razonSocial;
                }),
            noItemsFoundBuilder: (_) => const Padding(
              padding: EdgeInsets.all(8),
              child: Text('Sin resultados',
                  style: TextStyle(fontFamily: _kFont)),
            ),
          ),
          if (_seleccionado != null) ...[
            const SizedBox(height: 20),
            _ProveedorDetalleCard(proveedor: _seleccionado!),
            const SizedBox(height: 16),
            const Text('Recepciones registradas',
                style: TextStyle(
                    fontFamily: _kFont,
                    fontWeight: FontWeight.bold,
                    fontSize: 14)),
            const SizedBox(height: 10),
            StreamBuilder<List<RecepcionDoc>>(
              stream: widget.svc.streamRecepcionesByProveedor(
                  widget.empresaId, _seleccionado!.id),
              builder: (_, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final lista = snap.data ?? [];
                if (lista.isEmpty) {
                  return const Text('Sin recepciones para este proveedor',
                      style: TextStyle(
                          fontFamily: _kFont, color: Colors.black45));
                }
                return Column(
                  children: lista
                      .map((r) => _RecepcionResumenCard(
                            r,
                            svc: widget.svc,
                            empresaId: widget.empresaId,
                          ))
                      .toList(),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _ProveedorDetalleCard extends StatelessWidget {
  final ProveedorDoc proveedor;

  const _ProveedorDetalleCard({required this.proveedor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(proveedor.razonSocial,
              style: const TextStyle(
                  fontFamily: _kFont,
                  fontWeight: FontWeight.bold,
                  fontSize: 15)),
          const SizedBox(height: 10),
          _InfoRow(Icons.badge, 'NIT', proveedor.nit),
          if (proveedor.direccion.isNotEmpty)
            _InfoRow(Icons.location_on, 'Dirección', proveedor.direccion),
          if (proveedor.telefono.isNotEmpty)
            _InfoRow(Icons.phone, 'Teléfono', proveedor.telefono),
          if (proveedor.ciudad.isNotEmpty)
            _InfoRow(Icons.map, 'Ciudad',
                '${proveedor.ciudad}, ${proveedor.departamento}'),
          _InfoRow(
              Icons.home_work,
              'Tipo',
              proveedor.esLocal ? 'Proveedor local' : 'Proveedor no local'),
          const SizedBox(height: 10),
          const Text('Estado de documentos',
              style: TextStyle(
                  fontFamily: _kFont,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.black54)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: kDocProveedorLabels.entries.map((e) {
              final tiene = proveedor.documentos[e.key]?.tieneDoc == true;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                      tiene ? Icons.check_circle : Icons.cancel,
                      size: 14,
                      color: tiene ? kComprasGreen : kComprasRed),
                  const SizedBox(width: 3),
                  Text(e.value,
                      style: TextStyle(
                          fontFamily: _kFont,
                          fontSize: 11,
                          color: tiene ? kComprasGreen : kComprasRed)),
                ],
              );
            }).toList(),
          ),
          if (proveedor.categorias.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              children: proveedor.categorias
                  .map((c) => _Chip(c, kComprasPrimary))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Consulta Por Producto ────────────────────────────────────────────────

class _ConsultaProductoTab extends StatefulWidget {
  final String empresaId;
  final ComprasService svc;

  const _ConsultaProductoTab({required this.empresaId, required this.svc});

  @override
  State<_ConsultaProductoTab> createState() => _ConsultaProductoTabState();
}

class _ConsultaProductoTabState extends State<_ConsultaProductoTab> {
  final _ctrl = TextEditingController();
  List<ProductoDoc> _productos = [];
  ProductoDoc? _seleccionado;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('TBL_COMPRAS_PRODUCTOS')
          .where('empresaId', isEqualTo: widget.empresaId)
          .get();
      if (!mounted) return;
      final lista = snap.docs
          .map((d) => ProductoDoc.fromMap(d.id, d.data()))
          .toList()
        ..sort((a, b) => a.nombre.compareTo(b.nombre));
      setState(() => _productos = lista);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: kComprasRed));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TypeAheadField<ProductoDoc>(
            textFieldConfiguration: TextFieldConfiguration(
              controller: _ctrl,
              decoration: _inputDecoration('Buscar producto').copyWith(
                prefixIcon: const Icon(Icons.search, size: 18),
                hintText: 'Nombre, código o categoría...',
              ),
              style: const TextStyle(fontFamily: _kFont, fontSize: 14),
            ),
            suggestionsCallback: (p) => _productos
                .where((x) =>
                    x.nombre.toLowerCase().contains(p.toLowerCase()) ||
                    x.codigo.toLowerCase().contains(p.toLowerCase()) ||
                    x.categoria.toLowerCase().contains(p.toLowerCase()))
                .toList(),
            itemBuilder: (_, p) => ListTile(
              dense: true,
              title: Text(p.nombre,
                  style: const TextStyle(fontFamily: _kFont, fontSize: 13)),
              subtitle: Text('${p.codigo} · ${p.categoria}',
                  style:
                      const TextStyle(fontFamily: _kFont, fontSize: 11)),
            ),
            onSuggestionSelected: (p) =>
                setState(() {
                  _seleccionado = p;
                  _ctrl.text = p.nombre;
                }),
            noItemsFoundBuilder: (_) => const Padding(
              padding: EdgeInsets.all(8),
              child: Text('Sin resultados',
                  style: TextStyle(fontFamily: _kFont)),
            ),
          ),
          if (_seleccionado != null) ...[
            const SizedBox(height: 20),
            // Info del producto
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(_seleccionado!.nombre,
                            style: const TextStyle(
                                fontFamily: _kFont,
                                fontWeight: FontWeight.bold,
                                fontSize: 15)),
                      ),
                      _Chip(_seleccionado!.codigo, Colors.black54),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      _Chip(
                          _seleccionado!.categoria, const Color(0xFF0277BD)),
                      _Chip(_seleccionado!.unidadMedida, Colors.blueGrey),
                      if (_seleccionado!.esPerecedero)
                        _Chip('Perecedero', Colors.orange.shade700),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text('Recepciones donde aparece este producto',
                style: TextStyle(
                    fontFamily: _kFont,
                    fontWeight: FontWeight.bold,
                    fontSize: 14)),
            const SizedBox(height: 10),
            StreamBuilder<List<RecepcionDoc>>(
              stream: widget.svc.streamRecepcionesByProducto(
                  widget.empresaId, _seleccionado!.id),
              builder: (_, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final lista = snap.data ?? [];
                if (lista.isEmpty) {
                  return const Text('Sin recepciones para este producto',
                      style: TextStyle(
                          fontFamily: _kFont, color: Colors.black45));
                }
                return Column(
                  children: lista.map((r) {
                    final rp = r.productos.firstWhere(
                        (p) => p.productoId == _seleccionado!.id,
                        orElse: () => const RecepcionProducto());
                    return _RecepcionResumenCard(
                      r,
                      highlight: rp,
                      svc: widget.svc,
                      empresaId: widget.empresaId,
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _RecepcionResumenCard extends StatefulWidget {
  final RecepcionDoc recepcion;
  final RecepcionProducto? highlight;
  final ComprasService? svc;
  final String? empresaId;

  const _RecepcionResumenCard(
    this.recepcion, {
    this.highlight,
    this.svc,
    this.empresaId,
  });

  @override
  State<_RecepcionResumenCard> createState() => _RecepcionResumenCardState();
}

class _RecepcionResumenCardState extends State<_RecepcionResumenCard> {
  bool _expandido = false;
  late RecepcionDoc _r;
  final Map<String, bool> _subiendo = {};

  @override
  void initState() {
    super.initState();
    _r = widget.recepcion;
  }

  /// Sube o reemplaza un documento de un producto en una recepción existente
  Future<void> _subirDocProducto(int productoIdx, String docKey) async {
    if (widget.svc == null || widget.empresaId == null) return;
    final p = _r.productos[productoIdx];
    final nombreSug =
        '${_r.nit}_${p.nombre}_${kDocRecepcionLabels[docKey] ?? docKey}';

    final doc = await _mostrarEscaneador(
      context,
      empresaId: widget.empresaId!,
      carpeta: 'recepciones',
      nombreSugerido: nombreSug,
      svc: widget.svc!,
    );
    if (doc == null || !mounted) return;

    final subiendoKey = '${productoIdx}_$docKey';
    setState(() => _subiendo[subiendoKey] = true);
    try {
      // Construir productos actualizados con el nuevo doc
      final nuevosProductos = List<RecepcionProducto>.from(_r.productos);
      final docPendiente = doc.copyWith(
        estadoCalidad: 'pendiente_revision_calidad',
        observacionActualizacion: p.observaciones,
      );
      nuevosProductos[productoIdx] = RecepcionProducto(
        productoId: p.productoId,
        nombre: p.nombre,
        categoria: p.categoria,
        marcaId: p.marcaId,
        marca: p.marca,
        origen: p.origen,
        documentos: {...p.documentos, docKey: docPendiente},
        observaciones: p.observaciones,
      );
      final nuevaRecepcion = RecepcionDoc(
        id: _r.id,
        empresaId: _r.empresaId,
        fecha: _r.fecha,
        proveedorId: _r.proveedorId,
        nit: _r.nit,
        razonSocial: _r.razonSocial,
        ordenCompra: _r.ordenCompra,
        productos: nuevosProductos,
        productoIds: _r.productoIds,
        creadoPor: _r.creadoPor,
        createdAt: _r.createdAt,
      );
      await widget.svc!.guardarRecepcion(nuevaRecepcion);
      if (mounted) {
        setState(() => _r = nuevaRecepcion);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Documento guardado correctamente'),
          backgroundColor: kComprasGreen,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error al guardar: $e'),
            backgroundColor: kComprasRed));
      }
    } finally {
      if (mounted) setState(() => _subiendo.remove(subiendoKey));
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _r;
    final hl = widget.highlight != null
        ? r.productos.firstWhere(
            (p) => p.productoId == widget.highlight!.productoId,
            orElse: () => widget.highlight!)
        : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 2,
      child: Column(
        children: [
          // ── Encabezado ───────────────────────────────────
          InkWell(
            borderRadius: BorderRadius.vertical(
                top: const Radius.circular(14),
                bottom: Radius.circular(_expandido ? 0 : 14)),
            onTap: () => setState(() => _expandido = !_expandido),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: kComprasPrimary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.local_shipping,
                            size: 18, color: kComprasPrimary),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(r.razonSocial,
                                style: const TextStyle(
                                    fontFamily: _kFont,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14)),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                const Icon(Icons.badge,
                                    size: 12, color: Colors.black38),
                                const SizedBox(width: 3),
                                Text('NIT: ${r.nit}',
                                    style: const TextStyle(
                                        fontFamily: _kFont,
                                        fontSize: 11,
                                        color: Colors.black54)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(_fmtFecha(r.fecha),
                              style: const TextStyle(
                                  fontFamily: _kFont,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: kComprasPrimary)),
                          if (r.ordenCompra.isNotEmpty)
                            Text('OC: ${r.ordenCompra}',
                                style: const TextStyle(
                                    fontFamily: _kFont,
                                    fontSize: 10,
                                    color: Colors.black45)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _Chip(
                          '${r.productos.length} producto${r.productos.length == 1 ? '' : 's'}',
                          kComprasPrimary),
                      const Spacer(),
                      // Indicador de docs del highlight
                      if (hl != null) ...[
                        ...docsParaCategoria(hl.categoria).map((key) {
                          final tiene =
                              hl.documentos[key]?.tieneDoc == true;
                          return Tooltip(
                            message: kDocRecepcionLabels[key] ?? key,
                            child: Container(
                              width: 10,
                              height: 10,
                              margin: const EdgeInsets.only(left: 4),
                              decoration: BoxDecoration(
                                color: tiene ? kComprasGreen : kComprasRed,
                                shape: BoxShape.circle,
                              ),
                            ),
                          );
                        }),
                        const SizedBox(width: 6),
                      ],
                      Icon(
                          _expandido
                              ? Icons.expand_less
                              : Icons.expand_more,
                          size: 18,
                          color: Colors.black38),
                    ],
                  ),
                  if (hl != null && hl.marca.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.local_offer,
                            size: 13, color: Colors.black38),
                        const SizedBox(width: 4),
                        Text('Marca: ${hl.marca}',
                            style: const TextStyle(
                                fontFamily: _kFont,
                                fontSize: 12,
                                color: Colors.black54,
                                fontStyle: FontStyle.italic)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          // ── Productos expandidos ─────────────────────────
          if (_expandido) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('Productos recibidos',
                          style: TextStyle(
                              fontFamily: _kFont,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.black54)),
                      const Spacer(),
                      if (widget.svc != null)
                        const Tooltip(
                          message: 'Toca un documento para cargarlo',
                          child: Row(
                            children: [
                              Icon(Icons.upload_file,
                                  size: 13, color: kComprasPrimary),
                              SizedBox(width: 3),
                              Text('Editable',
                                  style: TextStyle(
                                      fontFamily: _kFont,
                                      fontSize: 10,
                                      color: kComprasPrimary)),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...r.productos.asMap().entries.map((entry) {
                    final productoIdx = entry.key;
                    final rp = entry.value;
                    final docsKeys = docsParaCategoria(rp.categoria);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: const Color(0xFFF0F4FF),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: kComprasPrimary.withOpacity(0.15))),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Nombre + categoría
                          Row(
                            children: [
                              Expanded(
                                child: Text(rp.nombre,
                                    style: const TextStyle(
                                        fontFamily: _kFont,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13)),
                              ),
                              _Chip(rp.categoria, kComprasPrimary),
                            ],
                          ),
                          // Marca
                          if (rp.marca.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(Icons.local_offer,
                                    size: 12, color: Colors.black38),
                                const SizedBox(width: 4),
                                Text('Marca: ${rp.marca}',
                                    style: const TextStyle(
                                        fontFamily: _kFont,
                                        fontSize: 11,
                                        color: Colors.black54)),
                              ],
                            ),
                          ],
                          const SizedBox(height: 8),
                          // Documentos — interactivos si hay svc
                          ...docsKeys.map((key) {
                            final doc = rp.documentos[key];
                            final tiene = doc?.tieneDoc == true;
                            final subiendo =
                                _subiendo['${productoIdx}_$key'] == true;
                            if (widget.svc != null) {
                              // Modo editable — botones con carga/ver
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: _DocAttachButton(
                                  label: kDocRecepcionLabels[key] ?? key,
                                  doc: doc,
                                  uploading: subiendo,
                                  onAttach: () => _subirDocProducto(
                                      productoIdx, key),
                                  onView: tiene
                                      ? () => _abrirUrl(
                                          context, doc!.url)
                                      : null,
                                  onWebUpload: (bytes, name) async {
                                    final ext = name
                                        .toLowerCase()
                                        .split('.')
                                        .last;
                                    final ct = ext == 'pdf'
                                        ? 'application/pdf'
                                        : 'image/$ext';
                                    final uploadedDoc =
                                        await widget.svc!.subirBytes(
                                      bytes: bytes,
                                      empresaId: widget.empresaId!,
                                      carpeta: 'recepciones',
                                      nombre: name,
                                      contentType: ct,
                                    );
                                    final p = _r.productos[productoIdx];
                                    final docPendiente =
                                        uploadedDoc.copyWith(
                                      estadoCalidad:
                                          'pendiente_revision_calidad',
                                      observacionActualizacion:
                                          p.observaciones,
                                    );
                                    final nuevosProductos =
                                        List<RecepcionProducto>.from(
                                            _r.productos);
                                    nuevosProductos[productoIdx] =
                                        RecepcionProducto(
                                      productoId: p.productoId,
                                      nombre: p.nombre,
                                      categoria: p.categoria,
                                      marcaId: p.marcaId,
                                      marca: p.marca,
                                      origen: p.origen,
                                      documentos: {
                                        ...p.documentos,
                                        key: docPendiente
                                      },
                                      observaciones: p.observaciones,
                                    );
                                    final nuevaRecepcion = RecepcionDoc(
                                      id: _r.id,
                                      empresaId: _r.empresaId,
                                      fecha: _r.fecha,
                                      proveedorId: _r.proveedorId,
                                      nit: _r.nit,
                                      razonSocial: _r.razonSocial,
                                      ordenCompra: _r.ordenCompra,
                                      productos: nuevosProductos,
                                      productoIds: _r.productoIds,
                                      creadoPor: _r.creadoPor,
                                      createdAt: _r.createdAt,
                                    );
                                    await widget.svc!
                                        .guardarRecepcion(nuevaRecepcion);
                                    if (mounted) {
                                      setState(() => _r = nuevaRecepcion);
                                    }
                                  },
                                  onDelete: tiene
                                      ? () async {
                                          final p =
                                              _r.productos[productoIdx];
                                          final nuevaDocs =
                                              Map<String, DocAdjunto>.from(
                                                  p.documentos)
                                                ..remove(key);
                                          final nuevosProductos =
                                              List<RecepcionProducto>.from(
                                                  _r.productos);
                                          nuevosProductos[productoIdx] =
                                              RecepcionProducto(
                                            productoId: p.productoId,
                                            nombre: p.nombre,
                                            categoria: p.categoria,
                                            marcaId: p.marcaId,
                                            marca: p.marca,
                                            origen: p.origen,
                                            documentos: nuevaDocs,
                                            observaciones: p.observaciones,
                                          );
                                          final nuevaRecepcion = RecepcionDoc(
                                            id: _r.id,
                                            empresaId: _r.empresaId,
                                            fecha: _r.fecha,
                                            proveedorId: _r.proveedorId,
                                            nit: _r.nit,
                                            razonSocial: _r.razonSocial,
                                            ordenCompra: _r.ordenCompra,
                                            productos: nuevosProductos,
                                            productoIds: _r.productoIds,
                                            creadoPor: _r.creadoPor,
                                            createdAt: _r.createdAt,
                                          );
                                          await widget.svc!
                                              .guardarRecepcion(
                                                  nuevaRecepcion);
                                          if (mounted) {
                                            setState(
                                                () => _r = nuevaRecepcion);
                                          }
                                        }
                                      : null,
                                ),
                              );
                            } else {
                              // Modo solo lectura — chips de estado
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Row(
                                  children: [
                                    Icon(
                                        tiene
                                            ? Icons.check_circle
                                            : Icons.radio_button_unchecked,
                                        size: 14,
                                        color: tiene
                                            ? kComprasGreen
                                            : Colors.grey.shade400),
                                    const SizedBox(width: 5),
                                    Expanded(
                                      child: Text(
                                          kDocRecepcionLabels[key] ?? key,
                                          style: TextStyle(
                                              fontFamily: _kFont,
                                              fontSize: 11,
                                              color: tiene
                                                  ? kComprasGreen
                                                  : Colors.grey.shade500)),
                                    ),
                                    if (tiene)
                                      InkWell(
                                        onTap: () => _abrirUrl(
                                            context, doc!.url),
                                        child: const Text('Ver',
                                            style: TextStyle(
                                                fontFamily: _kFont,
                                                fontSize: 11,
                                                color: kComprasPrimary,
                                                decoration:
                                                    TextDecoration.underline)),
                                      ),
                                  ],
                                ),
                              );
                            }
                          }),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// MARCAS SCREEN — listado de marcas
// ══════════════════════════════════════════════════════════════════════════════

class _MarcasScreen extends StatefulWidget {
  final String empresaId;
  final ComprasService svc;

  const _MarcasScreen({required this.empresaId, required this.svc});

  @override
  State<_MarcasScreen> createState() => _MarcasScreenState();
}

class _MarcasScreenState extends State<_MarcasScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _abrirForm({MarcaDoc? existing}) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _MarcaFormSheet(
            empresaId: widget.empresaId, svc: widget.svc, existing: existing),
      ),
    );
  }

  Future<void> _eliminar(MarcaDoc m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar marca',
            style: TextStyle(fontFamily: _kFont)),
        content: Text(
            '¿Eliminar "${m.descripcion}"? Esta acción no se puede deshacer.',
            style: const TextStyle(fontFamily: _kFont)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: kComprasRed),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok == true && mounted) {
      try {
        await widget.svc.eliminarMarca(m.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Marca eliminada'),
              backgroundColor: kComprasGreen));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Error: $e'), backgroundColor: kComprasRed));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kComprasBg,
      appBar: AppBar(
        title: const Text('Marcas',
            style: TextStyle(fontFamily: _kFont, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1976D2),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrirForm(),
        backgroundColor: const Color(0xFF1976D2),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Nueva Marca', style: TextStyle(fontFamily: _kFont)),
      ),
      body: Column(
        children: [
          // Buscador
          Container(
            color: const Color(0xFF1976D2),
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: TextField(
              controller: _searchCtrl,
              style:
                  const TextStyle(fontFamily: _kFont, color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Buscar marca...',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                prefixIcon:
                    const Icon(Icons.search, color: Colors.white70),
                filled: true,
                fillColor: Colors.white.withOpacity(0.15),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(
                    vertical: 8, horizontal: 12),
              ),
              onChanged: (v) =>
                  setState(() => _query = v.toLowerCase()),
            ),
          ),
          // Lista
          Expanded(
            child: StreamBuilder<List<MarcaDoc>>(
              stream: widget.svc.streamMarcas(widget.empresaId),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(
                      child: Text('Error: ${snap.error}',
                          style: const TextStyle(fontFamily: _kFont)));
                }
                final todas = snap.data ?? [];
                final list = _query.isEmpty
                    ? todas
                    : todas
                        .where((m) =>
                            m.descripcion.toLowerCase().contains(_query) ||
                            m.codigo.toLowerCase().contains(_query))
                        .toList();
                if (list.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.label_off,
                            size: 60,
                            color: Colors.blueGrey.shade200),
                        const SizedBox(height: 12),
                        Text(
                          _query.isEmpty
                              ? 'No hay marcas registradas'
                              : 'Sin resultados para "$_query"',
                          style: TextStyle(
                              fontFamily: _kFont,
                              color: Colors.blueGrey.shade400),
                        ),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final m = list[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        leading: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: const Color(0xFF1976D2).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.label,
                              color: Color(0xFF1976D2), size: 22),
                        ),
                        title: Text(m.descripcion,
                            style: const TextStyle(
                                fontFamily: _kFont,
                                fontWeight: FontWeight.w600,
                                fontSize: 15)),
                        subtitle: Text(m.codigo,
                            style: const TextStyle(
                                fontFamily: _kFont,
                                fontSize: 12,
                                color: Colors.black54)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined,
                                  size: 20,
                                  color: Color(0xFF1976D2)),
                              onPressed: () => _abrirForm(existing: m),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  size: 20, color: Colors.redAccent),
                              onPressed: () => _eliminar(m),
                            ),
                          ],
                        ),
                        onTap: () => _abrirForm(existing: m),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// MARCA FORM SHEET — crear / editar marca (bottom sheet)
// ══════════════════════════════════════════════════════════════════════════════

class _MarcaFormSheet extends StatefulWidget {
  final String empresaId;
  final ComprasService svc;
  final MarcaDoc? existing;

  const _MarcaFormSheet(
      {required this.empresaId, required this.svc, this.existing});

  @override
  State<_MarcaFormSheet> createState() => _MarcaFormSheetState();
}

class _MarcaFormSheetState extends State<_MarcaFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _codigoCtrl;
  late final TextEditingController _descCtrl;
  bool _guardando = false;
  bool _generandoCodigo = false;

  bool get isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    _codigoCtrl =
        TextEditingController(text: widget.existing?.codigo ?? '');
    _descCtrl =
        TextEditingController(text: widget.existing?.descripcion ?? '');
    if (isNew) {
      _generarCodigo();
    }
  }

  Future<void> _generarCodigo() async {
    setState(() => _generandoCodigo = true);
    try {
      final codigo =
          await widget.svc.generarCodigoMarca(widget.empresaId);
      if (mounted) setState(() => _codigoCtrl.text = codigo);
    } catch (_) {
      // Si falla la generación, el usuario puede escribirlo manualmente
    } finally {
      if (mounted) setState(() => _generandoCodigo = false);
    }
  }

  @override
  void dispose() {
    _codigoCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _guardando = true);
    try {
      final m = MarcaDoc(
        id: widget.existing?.id ?? '',
        empresaId: widget.empresaId,
        codigo: _codigoCtrl.text.trim().toUpperCase(),
        descripcion: _normalizarNombre(_descCtrl.text),
        createdAt: widget.existing?.createdAt ?? Timestamp.now(),
      );
      await widget.svc.guardarMarca(m, isNew: isNew);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(isNew ? 'Marca creada' : 'Marca actualizada'),
          backgroundColor: kComprasGreen,
        ));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: kComprasRed));
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(4)),
              ),
            ),
            Row(
              children: [
                const Icon(Icons.label_important, color: Color(0xFF1976D2)),
                const SizedBox(width: 8),
                Text(isNew ? 'Nueva Marca' : 'Editar Marca',
                    style: const TextStyle(
                        fontFamily: _kFont,
                        fontSize: 17,
                        fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 20),
            // Código
            TextFormField(
              controller: _codigoCtrl,
              decoration: _inputDecoration('Código *').copyWith(
                hintText: 'MRC-0001',
                prefixIcon: _generandoCodigo
                    ? const Padding(
                        padding: EdgeInsets.all(10),
                        child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2)))
                    : const Icon(Icons.tag, size: 18),
                helperText: 'Auto-generado, editable si es necesario',
              ),
              style: const TextStyle(
                  fontFamily: _kFont,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.1),
              textCapitalization: TextCapitalization.characters,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Campo requerido' : null,
            ),
            const SizedBox(height: 14),
            // Descripción
            TextFormField(
              controller: _descCtrl,
              decoration: _inputDecoration('Descripción / Nombre *')
                  .copyWith(hintText: 'Ej: Nike, Zenú, Colanta'),
              style: const TextStyle(fontFamily: _kFont, fontSize: 14),
              textCapitalization: TextCapitalization.words,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Campo requerido' : null,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _guardando ? null : _guardar,
                icon: _guardando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save),
                label: Text(_guardando ? 'Guardando...' : 'Guardar',
                    style: const TextStyle(fontFamily: _kFont)),
                style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF1976D2),
                    padding: const EdgeInsets.symmetric(vertical: 14)),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// ══════════════════════════════════════════════════════════════════════════════
// ORIGEN BUTTON — selector Nacional / Importado
// ══════════════════════════════════════════════════════════════════════════════

class _OrigenButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _OrigenButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.12) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? color : Colors.grey.shade300,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: selected ? color : Colors.black45),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontFamily: _kFont,
                    fontSize: 13,
                    fontWeight:
                        selected ? FontWeight.bold : FontWeight.normal,
                    color: selected ? color : Colors.black54)),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// CALIDAD SCREEN — revisión y aprobación de documentos
// ══════════════════════════════════════════════════════════════════════════════

class _CalidadScreen extends StatefulWidget {
  final String empresaId;
  final ComprasService svc;
  final String userId;

  const _CalidadScreen({
    required this.empresaId,
    required this.svc,
    required this.userId,
  });

  @override
  State<_CalidadScreen> createState() => _CalidadScreenState();
}

class _CalidadScreenState extends State<_CalidadScreen> {
  String _filtroProducto = '';
  DateTime? _filtroFecha;
  final _searchCtrl = TextEditingController();
  bool _soloRechazados = false;
  ReqEngine? _reqEngine;
  bool _cargandoReq = true;

  @override
  void initState() {
    super.initState();
    widget.svc.cargarReqEngine(widget.empresaId).then((engine) {
      if (mounted) setState(() { _reqEngine = engine; _cargandoReq = false; });
    }).catchError((_) {
      if (mounted) setState(() { _cargandoReq = false; });
    });
  }

  bool _recepcionTieneIncompletos(RecepcionDoc r) {
    final engine = _reqEngine;
    for (final rp in r.productos) {
      if (engine != null && !engine.isEmpty) {
        final requeridos = engine.docsRecepcion(
          categoriaProducto: rp.categoria,
          origenProducto: rp.origen,
          etapa: 'CADA_PEDIDO',
        );
        if (engine.getFaltantes(rp.documentos, requeridos).isNotEmpty) return true;
      }
      if (rp.documentos.values.any((d) => d.tieneDoc && !d.aprobado)) return true;
    }
    return false;
  }

  bool _proveedorTieneIncompletos(ProveedorDoc p) {
    final engine = _reqEngine;
    if (engine != null && !engine.isEmpty) {
      final requeridos = engine.docsProveedor(p.categorias);
      if (engine.getFaltantes(p.documentos, requeridos).isNotEmpty) return true;
    }
    return p.documentos.values.any((d) => d.tieneDoc && !d.aprobado);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kComprasBg,
      appBar: AppBar(
        title: const Text('Revisión de Calidad',
            style: TextStyle(fontFamily: _kFont, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF15803D),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(
              _soloRechazados
                  ? Icons.filter_list
                  : Icons.filter_list_off,
            ),
            tooltip: _soloRechazados
                ? 'Mostrar todos'
                : 'Solo rechazados',
            onPressed: () =>
                setState(() => _soloRechazados = !_soloRechazados),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Filtros ──
          Container(
            color: Colors.white,
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'Filtrar por producto...',
                      prefixIcon:
                          const Icon(Icons.search, size: 18),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 8, horizontal: 12),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                    style:
                        const TextStyle(fontFamily: _kFont, fontSize: 13),
                    onChanged: (v) =>
                        setState(() => _filtroProducto = v.toLowerCase()),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(
                    Icons.calendar_today,
                    color: _filtroFecha != null
                        ? const Color(0xFF15803D)
                        : Colors.black45,
                  ),
                  tooltip: 'Filtrar por fecha',
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _filtroFecha ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) {
                      setState(() => _filtroFecha = picked);
                    }
                  },
                ),
                if (_filtroFecha != null)
                  IconButton(
                    icon: const Icon(Icons.clear, color: Colors.red),
                    tooltip: 'Limpiar fecha',
                    onPressed: () => setState(() => _filtroFecha = null),
                  ),
              ],
            ),
          ),
          if (_filtroFecha != null)
            Container(
              color: Colors.green.shade50,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.filter_alt,
                      size: 14, color: Color(0xFF15803D)),
                  const SizedBox(width: 4),
                  Text(
                    'Fecha: ${DateFormat('dd/MM/yyyy', 'es').format(_filtroFecha!)}',
                    style: const TextStyle(
                        fontFamily: _kFont,
                        fontSize: 12,
                        color: Color(0xFF15803D)),
                  ),
                ],
              ),
            ),
          // ── Lista combinada: fichas técnicas + recepciones ──
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                // ── Fichas técnicas pendientes de calidad ──
                StreamBuilder<List<FichaTecnicaDoc>>(
                  stream: widget.svc
                      .streamFichasTecnicasPendientes(widget.empresaId),
                  builder: (_, fSnap) {
                    final fichas = fSnap.data ?? [];
                    if (fichas.isEmpty) return const SizedBox.shrink();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.description,
                                size: 18, color: Color(0xFF0277BD)),
                            const SizedBox(width: 6),
                            Text(
                              'Fichas Técnicas pendientes (${fichas.length})',
                              style: const TextStyle(
                                  fontFamily: _kFont,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: Color(0xFF0277BD)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ...fichas.map((f) => _FichaCalidadCard(
                              ficha: f,
                              svc: widget.svc,
                              userId: widget.userId,
                            )),
                        const Divider(height: 24, thickness: 1),
                      ],
                    );
                  },
                ),
                // ── Recepciones (todas, filtradas por incompletos) ──
                if (_cargandoReq)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else
                  StreamBuilder<List<RecepcionDoc>>(
                    stream: widget.svc.streamRecepciones(widget.empresaId),
                    builder: (ctx, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      var lista = (snap.data ?? [])
                          .where(_recepcionTieneIncompletos)
                          .toList();
                      if (_filtroProducto.isNotEmpty) {
                        lista = lista
                            .where((r) => r.productos.any((p) => p.nombre
                                .toLowerCase()
                                .contains(_filtroProducto)))
                            .toList();
                      }
                      if (_filtroFecha != null) {
                        lista = lista.where((r) {
                          final d = r.fecha.toDate();
                          return d.year == _filtroFecha!.year &&
                              d.month == _filtroFecha!.month &&
                              d.day == _filtroFecha!.day;
                        }).toList();
                      }
                      if (lista.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const SizedBox(height: 40),
                              Icon(Icons.verified_user,
                                  size: 64, color: Colors.green.shade300),
                              const SizedBox(height: 16),
                              const Text('Sin documentos de recepción pendientes',
                                  style: TextStyle(
                                      fontFamily: _kFont,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600)),
                              const Text('Todo está al día',
                                  style: TextStyle(
                                      fontFamily: _kFont,
                                      color: Colors.black54)),
                            ],
                          ),
                        );
                      }
                      return Column(
                        children: List.generate(
                          lista.length,
                          (i) => _RecepcionCalidadCard(
                            recepcion: lista[i],
                            svc: widget.svc,
                            userId: widget.userId,
                            filtroProducto: _filtroProducto,
                            reqEngine: _reqEngine,
                          ),
                        ),
                      );
                    },
                  ),
                // ── Proveedores con documentación incompleta ──
                if (!_cargandoReq)
                  StreamBuilder<List<ProveedorDoc>>(
                    stream: widget.svc.streamProveedores(widget.empresaId),
                    builder: (_, pSnap) {
                      final provs = (pSnap.data ?? [])
                          .where(_proveedorTieneIncompletos)
                          .toList();
                      if (provs.isEmpty) return const SizedBox.shrink();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Divider(height: 24, thickness: 1),
                          Row(
                            children: [
                              const Icon(Icons.business,
                                  size: 18, color: Color(0xFF7B3F00)),
                              const SizedBox(width: 6),
                              Text(
                                'Documentos de Proveedores (${provs.length})',
                                style: const TextStyle(
                                    fontFamily: _kFont,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    color: Color(0xFF7B3F00)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ...provs.map((p) => _ProveedorCalidadCard(
                                proveedor: p,
                                svc: widget.svc,
                                userId: widget.userId,
                                reqEngine: _reqEngine,
                              )),
                        ],
                      );
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// FICHA TÉCNICA CARD para pantalla de Calidad
// ══════════════════════════════════════════════════════════════════════════════

class _FichaCalidadCard extends StatelessWidget {
  final FichaTecnicaDoc ficha;
  final ComprasService svc;
  final String userId;

  const _FichaCalidadCard({
    required this.ficha,
    required this.svc,
    required this.userId,
  });

  Future<void> _aprobar(BuildContext context) async {
    try {
      await svc.aprobarFichaTecnica(
          fichaId: ficha.id, revisadoPor: userId);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Ficha técnica aprobada.',
              style: TextStyle(fontFamily: _kFont))));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e',
              style: const TextStyle(fontFamily: _kFont))));
    }
  }

  Future<void> _rechazar(BuildContext context) async {
    final motivoCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rechazar ficha técnica',
            style: TextStyle(fontFamily: _kFont, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: motivoCtrl,
          autofocus: true,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: 'Motivo del rechazo *',
            labelStyle: TextStyle(fontFamily: _kFont),
            border: OutlineInputBorder(),
            hintText: 'Describe el motivo del rechazo…',
          ),
          style: const TextStyle(fontFamily: _kFont),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar',
                  style: TextStyle(fontFamily: _kFont))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kComprasRed),
            onPressed: () {
              if (motivoCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx, true);
            },
            child: const Text('Rechazar',
                style: TextStyle(
                    fontFamily: _kFont, color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true || motivoCtrl.text.trim().isEmpty) return;
    try {
      await svc.rechazarFichaTecnica(
        fichaId: ficha.id,
        motivo: motivoCtrl.text.trim(),
        revisadoPor: userId,
        creadoPor: ficha.creadoPor,
        empresaId: ficha.empresaId,
        productoNombre: ficha.productoNombre,
        marcaNombre: ficha.marcaNombre,
        proveedorNombre: ficha.proveedorNombre,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Ficha técnica rechazada. Se notificó al usuario.',
              style: TextStyle(fontFamily: _kFont))));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e',
              style: const TextStyle(fontFamily: _kFont))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final doc = ficha.documentoActual;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFF90CAF9), width: 0.8)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.description_outlined,
                    size: 20, color: Color(0xFF0277BD)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(ficha.productoNombre,
                      style: const TextStyle(
                          fontFamily: _kFont,
                          fontWeight: FontWeight.w700,
                          fontSize: 14)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (ficha.marcaNombre.isNotEmpty)
              Text('Marca: ${ficha.marcaNombre}',
                  style: const TextStyle(
                      fontFamily: _kFont, fontSize: 12, color: Colors.black54)),
            Text('Proveedor: ${ficha.proveedorNombre}',
                style: const TextStyle(
                    fontFamily: _kFont, fontSize: 12, color: Colors.black54)),
            if (doc?.observacionActualizacion?.isNotEmpty == true) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.amber.shade200)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline,
                        size: 14, color: Color(0xFFB45309)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Obs. actualización: ${doc!.observacionActualizacion}',
                        style: const TextStyle(
                            fontFamily: _kFont,
                            fontSize: 12,
                            color: Color(0xFFB45309)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                if (doc?.tieneDoc == true)
                  TextButton.icon(
                    onPressed: () => _abrirUrl(context, doc!.url),
                    icon: const Icon(Icons.open_in_new, size: 14),
                    label: const Text('Ver PDF',
                        style: TextStyle(fontFamily: _kFont, fontSize: 12)),
                    style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4)),
                  ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _rechazar(context),
                  icon: const Icon(Icons.cancel_outlined,
                      size: 16, color: kComprasRed),
                  label: const Text('Rechazar',
                      style: TextStyle(
                          fontFamily: _kFont,
                          fontSize: 12,
                          color: kComprasRed)),
                  style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4)),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: kComprasGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8)),
                  onPressed: () => _aprobar(context),
                  icon: const Icon(Icons.check_circle_outline, size: 16),
                  label: const Text('Aprobar',
                      style: TextStyle(
                          fontFamily: _kFont,
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RecepcionCalidadCard extends StatelessWidget {
  final RecepcionDoc recepcion;
  final ComprasService svc;
  final String userId;
  final String filtroProducto;
  final ReqEngine? reqEngine;

  const _RecepcionCalidadCard({
    required this.recepcion,
    required this.svc,
    required this.userId,
    required this.filtroProducto,
    this.reqEngine,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: proveedor + fecha
            Row(
              children: [
                const Icon(Icons.business, size: 14, color: Colors.black45),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(recepcion.razonSocial,
                      style: const TextStyle(
                          fontFamily: _kFont,
                          fontWeight: FontWeight.bold,
                          fontSize: 14)),
                ),
                Text(_fmtFecha(recepcion.fecha),
                    style: const TextStyle(
                        fontFamily: _kFont,
                        fontSize: 12,
                        color: Colors.black45)),
              ],
            ),
            if (recepcion.ordenCompra.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text('OC: ${recepcion.ordenCompra}',
                  style: const TextStyle(
                      fontFamily: _kFont, fontSize: 11, color: Colors.black45)),
            ],
            const Divider(height: 16),
            // Productos con todos los docs requeridos
            ...recepcion.productos.asMap().entries.expand((entry) {
              final productoIdx = entry.key;
              final rp = entry.value;
              if (filtroProducto.isNotEmpty &&
                  !rp.nombre.toLowerCase().contains(filtroProducto)) {
                return <Widget>[];
              }

              final engine = reqEngine;
              final requeridos = (engine != null && !engine.isEmpty)
                  ? engine.docsRecepcion(
                      categoriaProducto: rp.categoria,
                      origenProducto: rp.origen,
                      etapa: 'CADA_PEDIDO',
                    )
                  : <ReqDocAplic>[];

              // Docs subidos que no están en la lista de requeridos (legacy/extra)
              final keysRequeridos = requeridos.map((r) => r.keyApp).toSet();
              final docsExtra = rp.documentos.entries
                  .where((e) =>
                      e.value.tieneDoc &&
                      !e.value.aprobado &&
                      !keysRequeridos.contains(e.key))
                  .toList();

              // ¿Hay algo que mostrar?
              final faltantesSet = (engine != null && !engine.isEmpty)
                  ? engine
                      .getFaltantes(rp.documentos, requeridos)
                      .map((r) => r.keyApp)
                      .toSet()
                  : <String>{};
              final tieneAlgo = faltantesSet.isNotEmpty ||
                  rp.documentos.values.any((d) => d.tieneDoc && !d.aprobado) ||
                  (requeridos.isEmpty &&
                      rp.documentos.values.any((d) => d.tieneDoc));
              if (!tieneAlgo) return <Widget>[];

              // Contar docs aprobados vs requeridos
              final totalReq = requeridos.length;
              final aprobadosCount = requeridos
                  .where((r) => rp.documentos[r.keyApp]?.aprobado == true)
                  .length;

              return [
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: faltantesSet.isNotEmpty
                        ? Colors.amber.shade50
                        : Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: faltantesSet.isNotEmpty
                            ? Colors.amber.shade300
                            : Colors.orange.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.inventory_2,
                              size: 14, color: Colors.black54),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(rp.nombre,
                                style: const TextStyle(
                                    fontFamily: _kFont,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13)),
                          ),
                          if (rp.marca.isNotEmpty)
                            _Chip(rp.marca, kComprasPrimary),
                          const SizedBox(width: 4),
                          _Chip(
                              rp.origen,
                              rp.origen == 'IMPORTADO'
                                  ? Colors.purple.shade700
                                  : Colors.green.shade700),
                        ],
                      ),
                      if (totalReq > 0) ...[
                        const SizedBox(height: 4),
                        Text(
                          '$aprobadosCount/$totalReq docs aprobados',
                          style: TextStyle(
                            fontFamily: _kFont,
                            fontSize: 11,
                            color: aprobadosCount == totalReq
                                ? kComprasGreen
                                : Colors.orange.shade800,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      if (rp.observaciones.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text('Obs: ${rp.observaciones}',
                            style: const TextStyle(
                                fontFamily: _kFont,
                                fontSize: 11,
                                fontStyle: FontStyle.italic,
                                color: Colors.black54)),
                      ],
                      const SizedBox(height: 8),
                      // Docs requeridos (del ReqEngine)
                      ...requeridos.map((req) {
                        final docKey = req.keyApp;
                        final doc = rp.documentos[docKey];
                        final label =
                            kDocRecepcionLabels[docKey] ?? req.documentoRequerido;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _buildDocRow(
                            context: context,
                            docKey: docKey,
                            label: label,
                            doc: doc,
                            productoIdx: productoIdx,
                          ),
                        );
                      }),
                      // Docs extra subidos (no en la lista de requeridos)
                      ...docsExtra.map((e) {
                        final docKey = e.key;
                        final doc = e.value;
                        final label =
                            kDocRecepcionLabels[docKey] ?? docKey;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _buildDocRow(
                            context: context,
                            docKey: docKey,
                            label: label,
                            doc: doc,
                            productoIdx: productoIdx,
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ];
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildDocRow({
    required BuildContext context,
    required String docKey,
    required String label,
    required DocAdjunto? doc,
    required int productoIdx,
  }) {
    final tieneDoc = doc?.tieneDoc == true;

    if (!tieneDoc) {
      // Sin cargar
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.amber.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.amber.shade300),
        ),
        child: Row(
          children: [
            Icon(Icons.upload_outlined, size: 14, color: Colors.amber.shade800),
            const SizedBox(width: 6),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontFamily: _kFont,
                      fontSize: 12,
                      color: Colors.amber.shade900)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.amber.shade100,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.amber.shade400),
              ),
              child: Text('Sin cargar',
                  style: TextStyle(
                      fontFamily: _kFont,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Colors.amber.shade900)),
            ),
          ],
        ),
      );
    }

    if (doc!.aprobado) {
      // Aprobado — solo visual
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.green.shade200),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle, size: 14, color: kComprasGreen),
            const SizedBox(width: 6),
            Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontFamily: _kFont,
                      fontSize: 12,
                      color: Colors.black87)),
            ),
            if (doc.tieneDoc)
              IconButton(
                onPressed: () => _abrirUrl(context, doc.url),
                icon: const Icon(Icons.open_in_new,
                    size: 14, color: Colors.blue),
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 28, minHeight: 28),
                tooltip: 'Ver documento',
              ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.green.shade100,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.green.shade300),
              ),
              child: const Text('Aprobado',
                  style: TextStyle(
                      fontFamily: _kFont,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: kComprasGreen)),
            ),
          ],
        ),
      );
    }

    if (doc.rechazado) {
      // Rechazado — muestra motivo
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Row(
              children: [
                const Icon(Icons.cancel, size: 14, color: kComprasRed),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(label,
                      style: const TextStyle(
                          fontFamily: _kFont,
                          fontSize: 12,
                          color: Colors.black87)),
                ),
                if (doc.tieneDoc)
                  IconButton(
                    onPressed: () => _abrirUrl(context, doc.url),
                    icon: const Icon(Icons.open_in_new,
                        size: 14, color: Colors.blue),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                        minWidth: 28, minHeight: 28),
                    tooltip: 'Ver documento',
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.red.shade100,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.red.shade300),
                  ),
                  child: const Text('Rechazado',
                      style: TextStyle(
                          fontFamily: _kFont,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: kComprasRed)),
                ),
              ],
            ),
          ),
          if (doc.observacionCalidad?.isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 4, right: 4),
              child: Text(
                'Motivo: ${doc.observacionCalidad}',
                style: TextStyle(
                    fontFamily: _kFont,
                    fontSize: 11,
                    color: Colors.red.shade700),
              ),
            ),
        ],
      );
    }

    // Pendiente de revisión — botones Aprobar / Rechazar
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.hourglass_empty,
                size: 14, color: Colors.orange),
            const SizedBox(width: 4),
            Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontFamily: _kFont, fontSize: 12)),
            ),
            if (doc.tieneDoc)
              IconButton(
                onPressed: () => _abrirUrl(context, doc.url),
                icon: const Icon(Icons.search,
                    size: 18, color: Colors.blue),
                tooltip: 'Ver documento',
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
          ],
        ),
        if (doc.observacionActualizacion?.trim().isNotEmpty == true) ...[
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Text(
              'Obs. actualización: ${doc.observacionActualizacion!.trim()}',
              style: const TextStyle(
                  fontFamily: _kFont,
                  fontSize: 11,
                  color: Colors.black87),
            ),
          ),
        ],
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () =>
                    _aprobarDoc(context, productoIdx, docKey),
                icon: const Icon(Icons.check_circle,
                    size: 16, color: kComprasGreen),
                label: const Text('Aprobar',
                    style: TextStyle(
                        fontFamily: _kFont,
                        fontSize: 12,
                        color: kComprasGreen)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: kComprasGreen),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () =>
                    _rechazarDoc(context, productoIdx, docKey),
                icon: const Icon(Icons.cancel,
                    size: 16, color: kComprasRed),
                label: const Text('Rechazar',
                    style: TextStyle(
                        fontFamily: _kFont,
                        fontSize: 12,
                        color: kComprasRed)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: kComprasRed),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _aprobarDoc(
      BuildContext context, int productoIdx, String docKey) async {
    try {
      await svc.aprobarDocRecepcion(
        recepcion: recepcion,
        productoIdx: productoIdx,
        docKey: docKey,
        revisadoPor: userId,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Documento aprobado'),
          backgroundColor: kComprasGreen,
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _rechazarDoc(
      BuildContext context, int productoIdx, String docKey) async {
    final motivoCtrl = TextEditingController();
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Rechazar documento',
            style: TextStyle(fontFamily: _kFont)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Documento: ${kDocRecepcionLabels[docKey] ?? docKey}',
              style: const TextStyle(fontFamily: _kFont, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: motivoCtrl,
              decoration: InputDecoration(
                labelText: 'Motivo del rechazo *',
                labelStyle: const TextStyle(fontFamily: _kFont),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              maxLines: 3,
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child:
                const Text('Cancelar', style: TextStyle(fontFamily: _kFont)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: kComprasRed,
                foregroundColor: Colors.white),
            onPressed: () {
              if (motivoCtrl.text.trim().isEmpty) return;
              Navigator.pop(context, true);
            },
            child: const Text('Rechazar',
                style: TextStyle(fontFamily: _kFont)),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    try {
      await svc.rechazarDocRecepcion(
        recepcion: recepcion,
        productoIdx: productoIdx,
        docKey: docKey,
        motivo: motivoCtrl.text.trim(),
        revisadoPor: userId,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Documento rechazado. Se notificará al usuario.'),
          backgroundColor: kComprasRed,
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// PROVEEDOR CALIDAD CARD
// ══════════════════════════════════════════════════════════════════════════════

class _ProveedorCalidadCard extends StatelessWidget {
  final ProveedorDoc proveedor;
  final ComprasService svc;
  final String userId;
  final ReqEngine? reqEngine;

  const _ProveedorCalidadCard({
    required this.proveedor,
    required this.svc,
    required this.userId,
    this.reqEngine,
  });

  @override
  Widget build(BuildContext context) {
    final engine = reqEngine;
    final requeridos = (engine != null && !engine.isEmpty)
        ? engine.docsProveedor(proveedor.categorias)
        : <ReqDocAplic>[];

    // Docs subidos no en la lista de requeridos
    final keysRequeridos = requeridos.map((r) => r.keyApp).toSet();
    final docsExtra = proveedor.documentos.entries
        .where((e) =>
            e.value.tieneDoc &&
            !e.value.aprobado &&
            !keysRequeridos.contains(e.key))
        .toList();

    // Contar aprobados vs requeridos
    final totalReq = requeridos.length;
    final aprobadosCount = requeridos
        .where((r) => proveedor.documentos[r.keyApp]?.aprobado == true)
        .length;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.brown.shade200, width: 0.8)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.business, size: 18, color: Color(0xFF7B3F00)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(proveedor.razonSocial,
                      style: const TextStyle(
                          fontFamily: _kFont,
                          fontWeight: FontWeight.w700,
                          fontSize: 14)),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text('NIT: ${proveedor.nit}',
                style: const TextStyle(
                    fontFamily: _kFont,
                    fontSize: 12,
                    color: Colors.black54)),
            if (totalReq > 0) ...[
              const SizedBox(height: 4),
              Text(
                '$aprobadosCount/$totalReq docs aprobados',
                style: TextStyle(
                  fontFamily: _kFont,
                  fontSize: 11,
                  color: aprobadosCount == totalReq
                      ? kComprasGreen
                      : Colors.orange.shade800,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 10),
            // Docs requeridos
            ...requeridos.map((req) {
              final docKey = req.keyApp;
              final doc = proveedor.documentos[docKey];
              final label = kDocProveedorLabels[docKey] ?? req.documentoRequerido;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _buildDocRow(
                    context: context, docKey: docKey, label: label, doc: doc),
              );
            }),
            // Docs extra subidos
            ...docsExtra.map((e) {
              final docKey = e.key;
              final doc = e.value;
              final label = kDocProveedorLabels[docKey] ?? docKey;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _buildDocRow(
                    context: context, docKey: docKey, label: label, doc: doc),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildDocRow({
    required BuildContext context,
    required String docKey,
    required String label,
    required DocAdjunto? doc,
  }) {
    final tieneDoc = doc?.tieneDoc == true;

    if (!tieneDoc) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.amber.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.amber.shade300),
        ),
        child: Row(
          children: [
            Icon(Icons.upload_outlined,
                size: 14, color: Colors.amber.shade800),
            const SizedBox(width: 6),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontFamily: _kFont,
                      fontSize: 12,
                      color: Colors.amber.shade900)),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.amber.shade100,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.amber.shade400),
              ),
              child: Text('Sin cargar',
                  style: TextStyle(
                      fontFamily: _kFont,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Colors.amber.shade900)),
            ),
          ],
        ),
      );
    }

    if (doc!.aprobado) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.green.shade200),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle, size: 14, color: kComprasGreen),
            const SizedBox(width: 6),
            Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontFamily: _kFont,
                      fontSize: 12,
                      color: Colors.black87)),
            ),
            IconButton(
              onPressed: () => _abrirUrl(context, doc.url),
              icon:
                  const Icon(Icons.open_in_new, size: 14, color: Colors.blue),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              tooltip: 'Ver documento',
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.green.shade100,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.green.shade300),
              ),
              child: const Text('Aprobado',
                  style: TextStyle(
                      fontFamily: _kFont,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: kComprasGreen)),
            ),
          ],
        ),
      );
    }

    if (doc.rechazado) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Row(
              children: [
                const Icon(Icons.cancel, size: 14, color: kComprasRed),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(label,
                      style: const TextStyle(
                          fontFamily: _kFont,
                          fontSize: 12,
                          color: Colors.black87)),
                ),
                IconButton(
                  onPressed: () => _abrirUrl(context, doc.url),
                  icon: const Icon(Icons.open_in_new,
                      size: 14, color: Colors.blue),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                      minWidth: 28, minHeight: 28),
                  tooltip: 'Ver documento',
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.red.shade100,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.red.shade300),
                  ),
                  child: const Text('Rechazado',
                      style: TextStyle(
                          fontFamily: _kFont,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: kComprasRed)),
                ),
              ],
            ),
          ),
          if (doc.observacionCalidad?.isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 4, right: 4),
              child: Text(
                'Motivo: ${doc.observacionCalidad}',
                style: TextStyle(
                    fontFamily: _kFont,
                    fontSize: 11,
                    color: Colors.red.shade700),
              ),
            ),
        ],
      );
    }

    // Pendiente — botones Aprobar / Rechazar
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.hourglass_empty,
                size: 14, color: Colors.orange),
            const SizedBox(width: 4),
            Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontFamily: _kFont, fontSize: 12)),
            ),
            IconButton(
              onPressed: () => _abrirUrl(context, doc.url),
              icon: const Icon(Icons.search,
                  size: 18, color: Colors.blue),
              tooltip: 'Ver documento',
              padding: EdgeInsets.zero,
              constraints:
                  const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _aprobarDoc(context, docKey),
                icon: const Icon(Icons.check_circle,
                    size: 16, color: kComprasGreen),
                label: const Text('Aprobar',
                    style: TextStyle(
                        fontFamily: _kFont,
                        fontSize: 12,
                        color: kComprasGreen)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: kComprasGreen),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _rechazarDoc(context, docKey),
                icon: const Icon(Icons.cancel,
                    size: 16, color: kComprasRed),
                label: const Text('Rechazar',
                    style: TextStyle(
                        fontFamily: _kFont,
                        fontSize: 12,
                        color: kComprasRed)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: kComprasRed),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _aprobarDoc(BuildContext context, String docKey) async {
    try {
      await svc.aprobarDocProveedor(
        proveedorId: proveedor.id,
        docKey: docKey,
        revisadoPor: userId,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Documento aprobado'),
          backgroundColor: kComprasGreen,
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _rechazarDoc(BuildContext context, String docKey) async {
    final motivoCtrl = TextEditingController();
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Rechazar documento',
            style: TextStyle(fontFamily: _kFont)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Documento: ${kDocProveedorLabels[docKey] ?? docKey}',
              style: const TextStyle(fontFamily: _kFont, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: motivoCtrl,
              decoration: InputDecoration(
                labelText: 'Motivo del rechazo *',
                labelStyle: const TextStyle(fontFamily: _kFont),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              maxLines: 3,
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar',
                style: TextStyle(fontFamily: _kFont)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: kComprasRed,
                foregroundColor: Colors.white),
            onPressed: () {
              if (motivoCtrl.text.trim().isEmpty) return;
              Navigator.pop(context, true);
            },
            child: const Text('Rechazar',
                style: TextStyle(fontFamily: _kFont)),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    try {
      await svc.rechazarDocProveedor(
        proveedorId: proveedor.id,
        docKey: docKey,
        motivo: motivoCtrl.text.trim(),
        revisadoPor: userId,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Documento rechazado.'),
          backgroundColor: kComprasRed,
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }
}

// WIDGETS DE APOYO
// ══════════════════════════════════════════════════════════════════════════════

class _SectionHeader extends StatelessWidget {
  final String titulo;
  final IconData icon;
  final Color color;

  const _SectionHeader(this.titulo, this.icon, this.color);

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(
              width: 4,
              height: 20,
              decoration: BoxDecoration(
                  color: color, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 8),
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(titulo,
              style: TextStyle(
                  fontFamily: _kFont,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: color)),
        ],
      );
}

Widget _Chip(String label, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label,
          style: TextStyle(
              fontFamily: _kFont,
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: color)),
    );

class _StatusDot extends StatelessWidget {
  final bool ok;

  const _StatusDot({required this.ok});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: ok ? 'Documentos completos' : 'Documentos pendientes',
        child: Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
              color: ok ? kComprasGreen : kComprasRed,
              shape: BoxShape.circle),
        ),
      );
}

Widget _InfoRow(IconData icon, String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: Colors.black38),
          const SizedBox(width: 6),
          Text('$label: ',
              style: const TextStyle(
                  fontFamily: _kFont,
                  fontSize: 12,
                  color: Colors.black45)),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontFamily: _kFont,
                    fontSize: 12,
                    color: Colors.black87)),
          ),
        ],
      ),
    );
