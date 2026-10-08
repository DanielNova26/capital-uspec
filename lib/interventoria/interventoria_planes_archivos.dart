import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'interventoria_planes_service.dart';

const planMaxArchivo = 5 * 1024 * 1024;
typedef PlanArchivo = ({String nombre, Uint8List bytes});

Uint8List reducirImagenPlan(Uint8List bytes) {
  final decoder = img.findDecoderForData(bytes);
  final info = decoder?.startDecode(bytes);
  if (info == null || info.width * info.height > 40000000)
    throw StateError('Imagen inválida o demasiado grande para procesar.');
  final original = img.decodeImage(bytes);
  if (original == null) throw StateError('No se pudo leer la imagen.');
  final rotated = img.bakeOrientation(original);
  for (final width in [2400, 1800, 1280]) {
    final image = rotated.width > width
        ? img.copyResize(rotated, width: width)
        : rotated;
    final result = Uint8List.fromList(img.encodeJpg(image, quality: 78));
    if (result.length <= planMaxArchivo) return result;
  }
  throw StateError(
    'No se pudo reducir a 5 MB conservando una calidad legible. Divide el archivo.',
  );
}

Future<PlanArchivo> reducirArchivoPlan(Uint8List bytes, String nombre) async {
  if (bytes.length > 40 * 1024 * 1024)
    throw StateError('Máximo 40 MB para optimizar. Divide el documento.');
  if (bytes.length <= planMaxArchivo) return (nombre: nombre, bytes: bytes);
  final base = nombre.replaceFirst(RegExp(r'\.[^.]+$'), '');
  if (!nombre.toLowerCase().endsWith('.pdf')) {
    return (
      nombre: '${base}_5MB.jpg',
      bytes: await compute(reducirImagenPlan, bytes),
    );
  }
  for (final dpi in [140.0, 110.0]) {
    final pdf = pw.Document(compress: true);
    var pages = 0;
    await for (final page in Printing.raster(bytes, dpi: dpi)) {
      if (++pages > 80)
        throw StateError(
          'El PDF tiene más de 80 páginas. Divídelo para conservar la legibilidad.',
        );
      final image = pw.MemoryImage(img.encodeJpg(page.asImage(), quality: 72));
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(
            page.width * 72 / dpi,
            page.height * 72 / dpi,
          ),
          margin: pw.EdgeInsets.zero,
          build: (_) => pw.Image(image, fit: pw.BoxFit.contain),
        ),
      );
    }
    if (pages == 0) throw StateError('El PDF no tiene páginas legibles.');
    final result = await pdf.save();
    if (result.length <= planMaxArchivo)
      return (nombre: '${base}_5MB.pdf', bytes: result);
  }
  throw StateError(
    'No se alcanzaron 5 MB con calidad legible. Divide el PDF en varios soportes.',
  );
}

Future<PlanArchivo?> planOfrecerReducir(
  BuildContext context,
  Uint8List bytes,
  String nombre,
) async {
  final accept = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Reducir a 5 MB'),
      content: Text(
        '$nombre · ${(bytes.length / 1024 / 1024).toStringAsFixed(1)} MB\nSe creará una copia. El original se conserva. En PDF, las páginas se convierten en imágenes: revisa la legibilidad y conserva el original si tiene firma digital.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Reducir copia'),
        ),
      ],
    ),
  );
  if (accept != true || !context.mounted) return null;
  return showDialog<PlanArchivo>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _Reduciendo(bytes: bytes, nombre: nombre),
  );
}

class _Reduciendo extends StatefulWidget {
  const _Reduciendo({required this.bytes, required this.nombre});
  final Uint8List bytes;
  final String nombre;
  @override
  State<_Reduciendo> createState() => _ReduciendoState();
}

class _ReduciendoState extends State<_Reduciendo> {
  String? error;
  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      final result = await reducirArchivoPlan(widget.bytes, widget.nombre);
      if (mounted) Navigator.pop(context, result);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: error != null,
    child: AlertDialog(
      title: const Text('Preparando copia para K2'),
      content: error == null
          ? const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Reduciendo el archivo…'),
              ],
            )
          : Text(error!),
      actions: error == null
          ? null
          : [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cerrar'),
              ),
            ],
    ),
  );
}

Future<PlanData> descargarFuentePlan(
  PlanRequest request,
  String itemId,
  String key,
) async {
  final input = {'accion': 'verFuente', 'itemId': itemId, 'fuenteKey': key};
  final first = await request(input);
  final bytes = BytesBuilder()..add(base64Decode(planText(first, 'base64')));
  for (var n = 1; n < (first['partes'] as num? ?? 1); n++) {
    final next = await request({...input, 'parte': n});
    if (next['tamano'] != first['tamano'] || next['sha256'] != first['sha256'])
      throw StateError('El archivo cambió. Descárgalo de nuevo.');
    bytes.add(base64Decode(planText(next, 'base64')));
  }
  return {'nombre': first['nombre'], 'base64': base64Encode(bytes.takeBytes())};
}
