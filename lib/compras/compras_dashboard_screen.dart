// lib/compras/compras_dashboard_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';

import 'compras_models.dart';
import 'compras_service.dart';

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

// ══════════════════════════════════════════════════════════════════════════════
// COMPRAS DASHBOARD SCREEN — pantalla principal (hub)
// ══════════════════════════════════════════════════════════════════════════════

class ComprasDashboardScreen extends StatelessWidget {
  final String userId;
  final String empresaId;

  const ComprasDashboardScreen({
    super.key,
    required this.userId,
    required this.empresaId,
  });

  @override
  Widget build(BuildContext context) {
    final svc = ComprasService();
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
              Text('Gestión de proveedores, productos y recepciones',
                  style: TextStyle(
                      fontFamily: _kFont,
                      fontSize: 16,
                      color: Colors.blueGrey.shade700)),
              const SizedBox(height: 24),
              _MenuTile(
                icon: Icons.business,
                titulo: 'Proveedores',
                subtitulo: 'Registrar y gestionar proveedores',
                color: const Color(0xFF1565C0),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => _ProveedoresScreen(
                        empresaId: empresaId, svc: svc),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _MenuTile(
                icon: Icons.inventory_2,
                titulo: 'Productos',
                subtitulo: 'Catálogo de productos del almacén',
                color: const Color(0xFF0277BD),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => _ProductosScreen(
                        empresaId: empresaId, svc: svc),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _MenuTile(
                icon: Icons.local_shipping,
                titulo: 'Recepción de Mercancía',
                subtitulo: 'Registrar llegada de proveedores con documentos',
                color: kComprasPrimary,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => _RecepcionesScreen(
                        empresaId: empresaId, svc: svc),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _MenuTile(
                icon: Icons.manage_search,
                titulo: 'Consultas',
                subtitulo: 'Consultar por proveedor o producto',
                color: const Color(0xFF283593),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => _ConsultasScreen(
                        empresaId: empresaId, svc: svc),
                  ),
                ),
              ),
            ],
          ),
        ),
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
          // Thumbnails
          Expanded(
            child: _imagenes.isEmpty
                ? Column(
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
                                    color: Colors.red, shape: BoxShape.circle),
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
                  ),
          ),
          // Botones
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                    color: Colors.black12,
                    blurRadius: 6,
                    offset: const Offset(0, -2))
              ],
            ),
            child: Column(
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
                            side: const BorderSide(color: kComprasPrimary)),
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
                            side: const BorderSide(color: kComprasPrimary)),
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
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.picture_as_pdf, size: 18),
                        label: Text(
                            _subiendo
                                ? 'Subiendo...'
                                : 'PDF (${_imagenes.length} pág.)',
                            style: const TextStyle(fontFamily: _kFont)),
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

class _DocAttachButton extends StatelessWidget {
  final String label;
  final DocAdjunto? doc;
  final bool required_;
  final VoidCallback onAttach;
  final VoidCallback? onView;

  const _DocAttachButton({
    required this.label,
    required this.doc,
    this.required_ = false,
    required this.onAttach,
    this.onView,
  });

  @override
  Widget build(BuildContext context) {
    final tiene = doc?.tieneDoc == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label,
                style: TextStyle(
                    fontFamily: _kFont,
                    fontSize: 12,
                    color: Colors.grey.shade600)),
            if (required_)
              Text(' *',
                  style: const TextStyle(color: Colors.red, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onAttach,
                icon: Icon(
                  tiene ? Icons.check_circle : Icons.upload_file,
                  size: 16,
                  color: tiene ? kComprasGreen : kComprasPrimary,
                ),
                label: Text(
                  tiene ? (doc!.nombre ?? 'Adjunto') : 'Adjuntar / Escanear',
                  style: TextStyle(
                      fontFamily: _kFont,
                      fontSize: 12,
                      color: tiene ? kComprasGreen : kComprasPrimary),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                      color: tiene ? kComprasGreen : Colors.grey.shade300),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  alignment: Alignment.centerLeft,
                ),
              ),
            ),
            if (tiene && onView != null) ...[
              const SizedBox(width: 6),
              IconButton(
                onPressed: onView,
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
      ],
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
    _departamento = p?.departamento.isNotEmpty == true ? p!.departamento : null;
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

  const _ProductosScreen({required this.empresaId, required this.svc});

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

  const _ProductoFormSheet(
      {required this.empresaId, required this.svc, this.existing});

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
  }

  @override
  void dispose() {
    _codigoCtrl.dispose();
    _nombreCtrl.dispose();
    super.dispose();
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
              const SizedBox(height: 16),
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
// RECEPCIONES SCREEN — listado de recepciones
// ══════════════════════════════════════════════════════════════════════════════

class _RecepcionesScreen extends StatefulWidget {
  final String empresaId;
  final ComprasService svc;

  const _RecepcionesScreen({required this.empresaId, required this.svc});

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
  final TextEditingController marcaCtrl = TextEditingController();
  Map<String, DocAdjunto> documentos = {};
  bool expandido = false;

  _RecepcionEntry();

  void dispose() => marcaCtrl.dispose();
}

class _NuevaRecepcionScreen extends StatefulWidget {
  final String empresaId;
  final ComprasService svc;
  final RecepcionDoc? existing;

  const _NuevaRecepcionScreen({
    required this.empresaId,
    required this.svc,
    this.existing,
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
  bool _guardando = false;
  bool _loadingProvs = true;

  bool get isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
    if (!isNew) {
      final r = widget.existing!;
      _ordenCtrl.text = r.ordenCompra;
      _entries = r.productos.map((rp) {
        final e = _RecepcionEntry();
        e.marcaCtrl.text = rp.marca;
        e.documentos = Map.from(rp.documentos);
        return e;
      }).toList();
    }
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

      if (!mounted) return;

      final provs = pSnap.docs
          .map((d) => ProveedorDoc.fromMap(d.id, d.data()))
          .toList()
        ..sort((a, b) => a.razonSocial.compareTo(b.razonSocial));

      final prods = prSnap.docs
          .map((d) => ProductoDoc.fromMap(d.id, d.data()))
          .toList()
        ..sort((a, b) => a.nombre.compareTo(b.nombre));

      setState(() {
        _proveedores = provs;
        _productos = prods;

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
            try {
              _entries[i].producto =
                  _productos.firstWhere((p) => p.id == rp.productoId);
            } catch (_) {}
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
          marca: e.marcaCtrl.text.trim(),
          documentos: e.documentos,
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
    _entries[idx].dispose();
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
      setState(() => _entries[idx].producto = seleccionado);
    }
  }

  Future<void> _adjuntarDocProducto(int idx, String key) async {
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
      setState(() => _entries[idx].documentos[key] = doc);
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

  const _ProductoEntryCard({
    required this.idx,
    required this.entry,
    required this.onSelectProducto,
    required this.onRemove,
    required this.onAdjuntarDoc,
    required this.onVerDoc,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
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
                    child: entry.producto == null
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
                                child: Text(entry.producto!.nombre,
                                    style: const TextStyle(
                                        fontFamily: _kFont,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14)),
                              ),
                              Row(
                                children: [
                                  _Chip(entry.producto!.categoria,
                                      kComprasPrimary),
                                  const SizedBox(width: 4),
                                  _Chip(entry.producto!.unidadMedida,
                                      Colors.blueGrey),
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
                  TextField(
                    controller: entry.marcaCtrl,
                    decoration: _inputDecoration('Marca').copyWith(
                        hintText: 'Nombre de la marca',
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10)),
                    style:
                        const TextStyle(fontFamily: _kFont, fontSize: 13),
                    onChanged: (_) => onChanged(),
                  ),
                  const SizedBox(height: 12),
                  const Text('Documentos',
                      style: TextStyle(
                          fontFamily: _kFont,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.black54)),
                  const SizedBox(height: 8),
                  ...kDocRecepcionLabels.entries.map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _DocAttachButton(
                          label: e.value,
                          doc: entry.documentos[e.key],
                          onAttach: () => onAdjuntarDoc(e.key),
                          onView: entry.documentos[e.key]?.tieneDoc == true
                              ? () => onVerDoc(e.key)
                              : null,
                        ),
                      )),
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
          indicatorColor: Colors.white,
          labelStyle: const TextStyle(fontFamily: _kFont, fontSize: 13),
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
                  children: lista.map((r) => _RecepcionResumenCard(r)).toList(),
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
                    // Mostrar solo el producto correspondiente
                    final rp = r.productos.firstWhere(
                        (p) => p.productoId == _seleccionado!.id,
                        orElse: () => const RecepcionProducto());
                    return _RecepcionResumenCard(r, highlight: rp);
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

  const _RecepcionResumenCard(this.recepcion, {this.highlight});

  @override
  State<_RecepcionResumenCard> createState() => _RecepcionResumenCardState();
}

class _RecepcionResumenCardState extends State<_RecepcionResumenCard> {
  bool _expandido = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.recepcion;
    final hl = widget.highlight;
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
                      // Si viene highlight, mostrar sus docs en el resumen
                      if (hl != null) ...[
                        ...kDocRecepcionLabels.entries.map((e) {
                          final tiene = hl.documentos[e.key]?.tieneDoc == true;
                          return Tooltip(
                            message: e.value,
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
                  // Si hay highlight (consultando por producto), mostrar marca
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
                  const Text('Productos recibidos',
                      style: TextStyle(
                          fontFamily: _kFont,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.black54)),
                  const SizedBox(height: 8),
                  ...r.productos.map((rp) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                            color: const Color(0xFFF0F4FF),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: kComprasPrimary.withOpacity(0.15))),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
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
                            if (rp.documentos.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                children: kDocRecepcionLabels.entries
                                    .map((e) {
                                  final tiene =
                                      rp.documentos[e.key]?.tieneDoc == true;
                                  return Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                          tiene
                                              ? Icons.check_circle
                                              : Icons.radio_button_unchecked,
                                          size: 13,
                                          color: tiene
                                              ? kComprasGreen
                                              : Colors.grey.shade400),
                                      const SizedBox(width: 3),
                                      Text(e.value,
                                          style: TextStyle(
                                              fontFamily: _kFont,
                                              fontSize: 10,
                                              color: tiene
                                                  ? kComprasGreen
                                                  : Colors.grey.shade500)),
                                    ],
                                  );
                                }).toList(),
                              ),
                            ],
                          ],
                        ),
                      )),
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
