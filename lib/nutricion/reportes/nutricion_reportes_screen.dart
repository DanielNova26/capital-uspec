import 'dart:io' as io;

import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/nutricion_report_service.dart';

class NutricionReportesScreen extends StatefulWidget {
  final String empresaId;

  const NutricionReportesScreen({
    super.key,
    required this.empresaId,
  });

  @override
  State<NutricionReportesScreen> createState() => _NutricionReportesScreenState();
}

class _NutricionReportesScreenState extends State<NutricionReportesScreen> {
  final _service = NutricionReportService();
  DateTimeRange? _rango;
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Reportes nutricionales', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: _pickRange,
                icon: const Icon(Icons.date_range),
                label: Text(_rango == null
                    ? 'Seleccionar rango'
                    : '${_rango!.start.day}/${_rango!.start.month} - ${_rango!.end.day}/${_rango!.end.month}'),
              ),
              ElevatedButton.icon(
                onPressed: _loading ? null : _exportar,
                icon: const Icon(Icons.download),
                label: Text(_loading ? 'Generando...' : 'Exportar Excel'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'El reporte incluye menús, derivaciones y auditoría de consumos disponibles en el rango.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
      initialDateRange: _rango,
    );
    if (picked == null) return;
    setState(() => _rango = picked);
  }

  Future<void> _exportar() async {
    setState(() => _loading = true);
    try {
      final bytes = await _service.exportResumen(
        empresaId: widget.empresaId,
        desde: _rango?.start,
        hasta: _rango?.end,
      );

      if (kIsWeb) {
        await FileSaver.instance.saveFile(
          name: 'reporte_nutricion',
          bytes: bytes,
          fileExtension: 'xlsx',
          mimeType: MimeType.microsoftExcel,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Descargado en el navegador.')),
        );
        return;
      }

      final fileName = 'reporte_nutricion_${DateTime.now().millisecondsSinceEpoch}.xlsx';
      io.Directory baseDir;
      if (io.Platform.isAndroid || io.Platform.isIOS) {
        baseDir = await getApplicationDocumentsDirectory();
      } else {
        baseDir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
      }

      final filePath = '${baseDir.path}/$fileName';
      final file = io.File(filePath);
      await file.writeAsBytes(bytes);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Guardado en: $filePath')),
      );

      try {
        if (io.Platform.isAndroid || io.Platform.isIOS) {
          await Share.shareXFiles([XFile(file.path)], text: 'Reporte nutrición');
        } else {
          await OpenFilex.open(file.path);
        }
      } catch (_) {}
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al exportar: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}