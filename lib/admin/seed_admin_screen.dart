// lib/admin/seed_admin_screen.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Guardado/compartido local (Android/iOS/Desktop)
import 'dart:io' as io;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:open_filex/open_filex.dart';

import '../services/seed_excel_parser.dart';
import '../services/seeder_service.dart';
import '../services/catalog_export_service.dart';
import '../bootstrap/static_excel_catalogs_seed.dart';

class SeedAdminScreen extends StatefulWidget {
  const SeedAdminScreen({Key? key}) : super(key: key);

  @override
  State<SeedAdminScreen> createState() => _SeedAdminScreenState();
}

class _SeedAdminScreenState extends State<SeedAdminScreen> {
  final _empresaIdCtrl = TextEditingController(text: 'EMPRESA_001');
  final _empresaNombreCtrl = TextEditingController(text: 'Empresa Demo');
  bool _crearUsuarios = true;

  SeedWorkbook? _wb;
  List<Map<String, dynamic>> _previewPersonal = [];
  String? _fileName;
  bool _loading = false;

  @override
  void dispose() {
    _empresaIdCtrl.dispose();
    _empresaNombreCtrl.dispose();
    super.dispose();
  }

  Future<void> _ensureAuth() async {
    final auth = FirebaseAuth.instance;
    if (auth.currentUser == null) {
      await auth.signInAnonymously();
    }
  }

  Future<void> _pickExcel() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xlsm', 'xls'],
        withData: true, // intentamos obtener bytes en memoria
      );
      if (result == null || result.files.isEmpty) return;

      final f = result.files.first;

      Uint8List? bytes = f.bytes;
      if (bytes == null && f.path != null && f.path!.isNotEmpty) {
        // Fallback: algunos entornos no entregan bytes aunque withData=true
        bytes = await io.File(f.path!).readAsBytes();
      }

      if (bytes == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo leer el archivo seleccionado.')),
        );
        return;
      }

      // ✅ CORRECCIÓN: usar una INSTANCIA del parser y AWAIT
      final parser = SeedExcelParser();
      final wb = await parser.parseBytes(bytes);

      if (!mounted) return;
      setState(() {
        _fileName = f.name;
        _wb = wb;
        _previewPersonal = wb.personal;
      });

      if (_previewPersonal.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se encontraron filas de PERSONAL.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al cargar Excel: $e')),
      );
    }
  }

  Future<void> _import() async {
    if (_wb == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Primero selecciona un Excel con datos.')),
      );
      return;
    }
    final empresaId = _empresaIdCtrl.text.trim();
    final empresaNombre = _empresaNombreCtrl.text.trim();
    if (empresaId.isEmpty || empresaNombre.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa Empresa ID y Nombre.')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      await _ensureAuth();

      final db = FirebaseFirestore.instance;
      await db.collection('TBL_EMPRESAS').doc(empresaId).set({
        'empresaId': empresaId,
        'nombre': empresaNombre,
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final seeder = SeederService();
      await seeder.importWorkbook(
        wb: _wb!, // ya validado arriba
        empresaId: empresaId,
        empresaNombre: empresaNombre,
        crearUsuarios: _crearUsuarios,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Importación completada. '
                'PERSONAL: ${_wb!.personal.length}, '
                'AREAS: ${_wb!.areas.length}, '
                'CARGOS: ${_wb!.cargos.length}, '
                'CENTROS: ${_wb!.centrosCostos.length}, '
                'CIUDADES: ${_wb!.ciudades.length}, '
                'DEPTO: ${_wb!.departamentos.length}, '
                'APPS: ${_wb!.apps.length}, '
                'TIPO_DOC: ${_wb!.tiposDocumento.length}.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al importar: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Sembrar catálogos base (DEPARTAMENTOS/CIUDADES/TIPO_DOCUMENTO) desde assets/seeds/catalogos_base.xlsx
  Future<void> _seedBaseFromAssets() async {
    setState(() => _loading = true);
    try {
      await _ensureAuth();
      await StaticExcelCatalogsSeed().runForce();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Catálogos base sembrados desde assets.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al sembrar catálogos base: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Exporta a XLSX:
  /// - Web: descarga con FileSaver.
  /// - Android/iOS/Desktop: guarda en carpeta conocida y muestra la ruta; intenta abrir/compartir.
  Future<void> _exportCatalogs() async {
    setState(() => _loading = true);
    try {
      await _ensureAuth();
      final bytes = await CatalogExportService().exportToExcelBytes();

      if (kIsWeb) {
        await FileSaver.instance.saveFile(
          name: 'catalogos_base',
          bytes: bytes,
          fileExtension: 'xlsx',
          mimeType: MimeType.microsoftExcel,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Descargado. Revisa la carpeta de descargas del navegador.')),
        );
        return;
      }

      final String fileName =
          'catalogos_base_${DateTime.now().millisecondsSinceEpoch}.xlsx';

      io.Directory baseDir;
      if (io.Platform.isAndroid || io.Platform.isIOS) {
        baseDir = await getApplicationDocumentsDirectory();
      } else {
        final downloadsDir = await getDownloadsDirectory();
        baseDir = downloadsDir ?? await getApplicationDocumentsDirectory();
      }

      final String filePath = p.join(baseDir.path, fileName);
      final io.File f = io.File(filePath);
      await f.writeAsBytes(bytes);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Guardado en:\n$filePath')),
      );

      try {
        if (io.Platform.isAndroid || io.Platform.isIOS) {
          await Share.shareXFiles([XFile(f.path)], text: 'Catálogos base');
        } else {
          await OpenFilex.open(f.path);
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Panel de Semillas (Admin)')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: 260,
                        child: TextField(
                          controller: _empresaIdCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Empresa ID',
                            hintText: 'p.ej. EMPRESA_001',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 300,
                        child: TextField(
                          controller: _empresaNombreCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Empresa Nombre',
                            hintText: 'p.ej. Unión Temporal XYZ',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: _loading ? null : _pickExcel,
                        icon: const Icon(Icons.upload_file),
                        label: Text(_fileName == null ? 'Seleccionar Excel' : _fileName!),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Checkbox(
                            value: _crearUsuarios,
                            onChanged: _loading ? null : (v) => setState(() => _crearUsuarios = v ?? false),
                          ),
                          const Text('Crear usuarios automáticamente'),
                        ],
                      ),
                      ElevatedButton.icon(
                        onPressed: _loading ? null : _import,
                        icon: _loading
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.playlist_add_check),
                        label: Text(_loading ? 'Importando...' : 'Importar'),
                      ),
                      ElevatedButton.icon(
                        onPressed: _loading ? null : _seedBaseFromAssets,
                        icon: const Icon(Icons.cloud_download),
                        label: const Text('Sembrar catálogos base (assets)'),
                      ),
                      ElevatedButton.icon(
                        onPressed: _loading ? null : _exportCatalogs,
                        icon: const Icon(Icons.download),
                        label: const Text('Exportar catálogos (XLSX)'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (_wb != null) _CountsBar(wb: _wb!),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Previsualización PERSONAL (${_previewPersonal.length} filas)',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: theme.dividerColor),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: _previewPersonal.isEmpty
                        ? const Center(child: Text('Selecciona un archivo Excel (.xlsx) con la hoja PERSONAL.'))
                        : _PreviewTable(rows: _previewPersonal),
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

class _CountsBar extends StatelessWidget {
  final SeedWorkbook wb;
  const _CountsBar({required this.wb});

  @override
  Widget build(BuildContext context) {
    final items = {
      'PERSONAL': wb.personal.length,
      'AREAS': wb.areas.length,
      'CARGOS': wb.cargos.length,
      'CENTROS': wb.centrosCostos.length,
      'CIUDADES': wb.ciudades.length,
      'DEPTO': wb.departamentos.length,
      'APPS': wb.apps.length,
      'TIPO_DOC': wb.tiposDocumento.length,
    };
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: items.entries.map((e) => Chip(label: Text('${e.key}: ${e.value}'))).toList(),
    );
  }
}

class _PreviewTable extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  const _PreviewTable({required this.rows});

  @override
  Widget build(BuildContext context) {
    final freq = <String, int>{};
    for (final r in rows.take(200)) {
      for (final k in r.keys) {
        freq[k] = (freq[k] ?? 0) + 1;
      }
    }
    final cols = freq.keys.toList()..sort((a, b) => (freq[b] ?? 0).compareTo(freq[a] ?? 0));
    final display = cols.take(10).toList();

    return Scrollbar(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width - 64),
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: DataTable(
              columns: display.map((k) => DataColumn(label: Text(k))).toList(),
              rows: rows.take(200).map((r) => DataRow(
                cells: display.map((k) => DataCell(Text('${r[k] ?? ''}'))).toList(),
              )).toList(),
            ),
          ),
        ),
      ),
    );
  }
}
