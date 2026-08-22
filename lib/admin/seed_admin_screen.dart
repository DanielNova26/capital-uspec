// lib/admin/seed_admin_screen.dart
import 'dart:async';
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
import 'package:share_plus/share_plus.dart';
import 'package:open_filex/open_filex.dart';

import '../services/seed_excel_parser.dart';
import '../services/seeder_service.dart';
import '../services/catalog_export_service.dart';
import '../services/demo_seed_service.dart';
import '../bootstrap/static_excel_catalogs_seed.dart';
import '../utils/user_company.dart';

class SeedAdminScreen extends StatefulWidget {
  const SeedAdminScreen({super.key});

  @override
  State<SeedAdminScreen> createState() => _SeedAdminScreenState();
}

class _SeedAdminScreenState extends State<SeedAdminScreen> {
  final _empresaIdCtrl = TextEditingController(text: 'EMPRESA_001');
  final _empresaNombreCtrl = TextEditingController(text: 'Empresa Demo');
  bool _crearUsuarios = true;

  List<_EmpresaOption> _empresas = [];
  bool _loadingEmpresas = false;
  Timer? _reviewDebounce;

  SeedWorkbook? _wb;
  List<Map<String, dynamic>> _previewPersonal = [];
  _SeedImportReview? _review;
  bool _reviewLoading = false;
  final Set<String> _skipCedulas = <String>{};
  String? _fileName;
  bool _loading = false;
  final DemoSeedService _demoSeedService = DemoSeedService();

  @override
  void initState() {
    super.initState();
    _empresaIdCtrl.addListener(_scheduleReview);
    _empresaNombreCtrl.addListener(_scheduleReview);
    _fetchEmpresas();
  }

  @override
  void dispose() {
    _reviewDebounce?.cancel();
    _empresaIdCtrl.removeListener(_scheduleReview);
    _empresaNombreCtrl.removeListener(_scheduleReview);
    _empresaIdCtrl.dispose();
    _empresaNombreCtrl.dispose();
    super.dispose();
  }

  void _scheduleReview() {
    if (_wb == null) return;
    _reviewDebounce?.cancel();
    _reviewDebounce = Timer(const Duration(milliseconds: 450), () {
      if (mounted) _refreshReview(showErrors: false);
    });
  }

  Future<void> _ensureAuth() async {
    final auth = FirebaseAuth.instance;
    if (auth.currentUser == null) {
      await auth.signInAnonymously();
    }
  }

  Future<void> _fetchEmpresas() async {
    setState(() => _loadingEmpresas = true);
    try {
      await _ensureAuth();
      final snap = await FirebaseFirestore.instance
          .collection('TBL_EMPRESAS')
          .orderBy('updatedAt', descending: true)
          .limit(50)
          .get();

      final options = snap.docs
          .map((d) {
            final data = d.data();
            final id = (data['empresaId'] ?? d.id ?? '').toString();
            return _EmpresaOption(
              id: id,
              nombre: (data['nombre'] ?? id).toString(),
            );
          })
          .where((e) => e.id.isNotEmpty)
          .toList();

      if (!mounted) return;
      setState(() => _empresas = options);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo cargar la lista de empresas: $e')),
      );
    } finally {
      if (mounted) setState(() => _loadingEmpresas = false);
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
          const SnackBar(
            content: Text('No se pudo leer el archivo seleccionado.'),
          ),
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
        _review = null;
        _skipCedulas.clear();
      });

      await _refreshReview(showErrors: false);
      if (!mounted) return;

      if (_previewPersonal.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se encontraron filas de PERSONAL.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al cargar Excel: $e')));
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

    if (_review == null && _wb != null) {
      await _refreshReview(showErrors: false);
      if (!mounted) return;
    }

    if (_skipCedulas.isNotEmpty) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Importar con omisiones'),
          content: Text(
            'Marcaste ${_skipCedulas.length} persona(s) para mantener como están. '
            'Se importarán los nuevos registros y las personas no omitidas.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Revisar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Continuar'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
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
      final workbook = _workbookForImport();
      await seeder.importWorkbook(
        wb: workbook,
        empresaId: empresaId,
        empresaNombre: empresaNombre,
        crearUsuarios: _crearUsuarios,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Importación completada. '
            'PERSONAL: ${workbook.personal.length}, '
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al importar: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  SeedWorkbook _workbookForImport() {
    final wb = _wb!;
    if (_skipCedulas.isEmpty) return wb;
    final personal = wb.personal.where((row) {
      final cedula = _digits(_s(row['cedula']));
      return cedula.isEmpty || !_skipCedulas.contains(cedula);
    }).toList();
    return SeedWorkbook(
      personal: personal,
      areas: wb.areas,
      cargos: wb.cargos,
      centrosCostos: wb.centrosCostos,
      apps: wb.apps,
      tiposDocumento: wb.tiposDocumento,
      ciudades: wb.ciudades,
      departamentos: wb.departamentos,
    );
  }

  Future<void> _refreshReview({bool showErrors = true}) async {
    final wb = _wb;
    final empresaId = _empresaIdCtrl.text.trim();
    final empresaNombre = _empresaNombreCtrl.text.trim();
    if (wb == null || empresaId.isEmpty) return;

    setState(() => _reviewLoading = true);
    try {
      await _ensureAuth();
      final review = await _SeedImportReview.load(
        wb: wb,
        empresaId: empresaId,
        empresaNombre: empresaNombre,
      );
      if (!mounted) return;
      setState(() => _review = review);
    } catch (e) {
      if (!mounted) return;
      if (showErrors) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo comparar con Firebase: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _reviewLoading = false);
    }
  }

  void _toggleSkip(String cedula) {
    setState(() {
      if (_skipCedulas.contains(cedula)) {
        _skipCedulas.remove(cedula);
      } else {
        _skipCedulas.add(cedula);
      }
    });
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
          const SnackBar(
            content: Text(
              'Descargado. Revisa la carpeta de descargas del navegador.',
            ),
          ),
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

      final String filePath = _joinPath(baseDir.path, fileName);
      final io.File f = io.File(filePath);
      await f.writeAsBytes(bytes);

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Guardado en:\n$filePath')));

      try {
        if (io.Platform.isAndroid || io.Platform.isIOS) {
          await SharePlus.instance.share(
            ShareParams(files: [XFile(f.path)], text: 'Catálogos base'),
          );
        } else {
          await OpenFilex.open(f.path);
        }
      } catch (_) {}
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al exportar: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _seedDemoDataset() async {
    setState(() => _loading = true);
    try {
      await _ensureAuth();
      final result = await _demoSeedService.ensureDemoData();
      if (!mounted) return;

      await showDialog(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: const Text('Credenciales demo creadas'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Comparte estos datos con el equipo de revisión. '
                  'El dataset se puede regenerar tantas veces como necesites.',
                ),
                const SizedBox(height: 12),
                SelectableText('Empresa ID: ${result.empresaId}'),
                SelectableText('Usuario: ${result.username}'),
                SelectableText('Contraseña: ${result.password}'),
                SelectableText('Correo: ${result.email}'),
                const SizedBox(height: 12),
                const Text('Preguntas de seguridad:'),
                ...result.securityQuestions.map(
                  (qa) => Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: SelectableText(
                      '${qa.question}\nRespuesta: ${qa.answer}',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SelectableText(
                  'PIN administrador (triple tap): ${result.adminPin}',
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Listo'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al crear demo: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final review = _review;

    return Scaffold(
      appBar: AppBar(title: const Text('Panel de Semillas (Admin)')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SeedHeaderCard(
                    empresaIdCtrl: _empresaIdCtrl,
                    empresaNombreCtrl: _empresaNombreCtrl,
                    empresas: _empresas,
                    loadingEmpresas: _loadingEmpresas,
                    loading: _loading,
                    fileName: _fileName,
                    crearUsuarios: _crearUsuarios,
                    onRefreshEmpresas: _fetchEmpresas,
                    onPickExcel: _pickExcel,
                    onImport: _import,
                    onSeedBase: _seedBaseFromAssets,
                    onExport: _exportCatalogs,
                    onRefreshReview: () => _refreshReview(showErrors: true),
                    onCrearUsuariosChanged: (value) {
                      setState(() => _crearUsuarios = value);
                    },
                    onEmpresaSelected: (selected) {
                      _empresaIdCtrl.text = selected.id;
                      _empresaNombreCtrl.text = selected.nombre;
                    },
                    reviewLoading: _reviewLoading,
                  ),
                  const SizedBox(height: 14),
                  if (_wb != null) _CountsBar(wb: _wb!),
                  const SizedBox(height: 14),
                  if (review != null)
                    _ReviewSummary(
                      review: review,
                      skippedCount: _skipCedulas.length,
                    )
                  else
                    _EmptyReviewCard(reviewLoading: _reviewLoading),
                  const SizedBox(height: 14),
                  _ReviewTabs(
                    review: review,
                    rows: _previewPersonal,
                    skippedCedulas: _skipCedulas,
                    onToggleSkip: _toggleSkip,
                  ),
                  const SizedBox(height: 14),
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Dataset demo para App Store / Play Store',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Genera automáticamente la empresa de ejemplo, el usuario demo y las tareas solicitadas para revisión.',
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            onPressed: _loading ? null : _seedDemoDataset,
                            icon: const Icon(Icons.verified_user),
                            label: Text(
                              _loading
                                  ? 'Creando dataset demo...'
                                  : 'Crear/actualizar usuario demo',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _s(dynamic v) => v == null ? '' : v.toString().trim();

String _joinPath(String dir, String fileName) {
  final separator = dir.endsWith(r'\') || dir.endsWith('/')
      ? ''
      : io.Platform.pathSeparator;
  return '$dir$separator$fileName';
}

String _digits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

String _normKey(String s) =>
    _stripDiacritics(s).toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');

String _idFromName(String s) {
  final base = _stripDiacritics(s)
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
  return base.isEmpty ? 'sin_nombre' : base;
}

String _stripDiacritics(String s) {
  const src = 'áéíóúÁÉÍÓÚäëïöüÄËÏÖÜñÑçÇ';
  const dst = 'aeiouAEIOUaeiouAEIOUnNcC';
  var out = s;
  for (int i = 0; i < src.length; i++) {
    out = out.replaceAll(src[i], dst[i]);
  }
  return out;
}

class _SeedHeaderCard extends StatelessWidget {
  final TextEditingController empresaIdCtrl;
  final TextEditingController empresaNombreCtrl;
  final List<_EmpresaOption> empresas;
  final bool loadingEmpresas;
  final bool loading;
  final bool reviewLoading;
  final String? fileName;
  final bool crearUsuarios;
  final VoidCallback onRefreshEmpresas;
  final VoidCallback onPickExcel;
  final VoidCallback onImport;
  final VoidCallback onSeedBase;
  final VoidCallback onExport;
  final VoidCallback onRefreshReview;
  final ValueChanged<bool> onCrearUsuariosChanged;
  final ValueChanged<_EmpresaOption> onEmpresaSelected;

  const _SeedHeaderCard({
    required this.empresaIdCtrl,
    required this.empresaNombreCtrl,
    required this.empresas,
    required this.loadingEmpresas,
    required this.loading,
    required this.reviewLoading,
    required this.fileName,
    required this.crearUsuarios,
    required this.onRefreshEmpresas,
    required this.onPickExcel,
    required this.onImport,
    required this.onSeedBase,
    required this.onExport,
    required this.onRefreshReview,
    required this.onCrearUsuariosChanged,
    required this.onEmpresaSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedEmpresa = empresas.any((e) => e.id == empresaIdCtrl.text)
        ? empresaIdCtrl.text
        : null;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.dataset_linked_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Importación inteligente por empresa',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                if (reviewLoading)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 250,
                  child: TextField(
                    controller: empresaIdCtrl,
                    enabled: !loading,
                    decoration: const InputDecoration(
                      labelText: 'Empresa ID destino',
                      hintText: 'p.ej. EMPRESA_001',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.business_outlined),
                    ),
                  ),
                ),
                SizedBox(
                  width: 300,
                  child: TextField(
                    controller: empresaNombreCtrl,
                    enabled: !loading,
                    decoration: const InputDecoration(
                      labelText: 'Nombre empresa destino',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                SizedBox(
                  width: 360,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey(selectedEmpresa ?? empresaIdCtrl.text),
                    isExpanded: true,
                    initialValue: selectedEmpresa,
                    decoration: InputDecoration(
                      labelText: 'Empresas existentes',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        onPressed: loadingEmpresas ? null : onRefreshEmpresas,
                        icon: loadingEmpresas
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.refresh),
                        tooltip: 'Refrescar empresas',
                      ),
                    ),
                    hint: Text(
                      loadingEmpresas
                          ? 'Cargando empresas...'
                          : empresas.isEmpty
                          ? 'No hay empresas cargadas'
                          : 'Seleccionar empresa destino',
                    ),
                    items: empresas
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.id,
                            child: Text('${e.id} · ${e.nombre}'),
                          ),
                        )
                        .toList(),
                    onChanged: loading
                        ? null
                        : (value) {
                            if (value == null) return;
                            final selected = empresas.firstWhere(
                              (e) => e.id == value,
                              orElse: () =>
                                  _EmpresaOption(id: value, nombre: value),
                            );
                            onEmpresaSelected(selected);
                          },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: loading ? null : onPickExcel,
                  icon: const Icon(Icons.upload_file),
                  label: Text(
                    fileName == null ? 'Seleccionar Excel' : fileName!,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: loading || fileName == null
                      ? null
                      : onRefreshReview,
                  icon: const Icon(Icons.compare_arrows),
                  label: const Text('Comparar con Firebase'),
                ),
                FilterChip(
                  selected: crearUsuarios,
                  onSelected: loading ? null : onCrearUsuariosChanged,
                  avatar: const Icon(Icons.group_add_outlined, size: 18),
                  label: const Text('Crear usuarios automáticamente'),
                ),
                FilledButton.tonalIcon(
                  onPressed: loading ? null : onImport,
                  icon: loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.playlist_add_check),
                  label: Text(loading ? 'Importando...' : 'Importar revisión'),
                ),
                OutlinedButton.icon(
                  onPressed: loading ? null : onSeedBase,
                  icon: const Icon(Icons.cloud_download),
                  label: const Text('Catálogos base'),
                ),
                OutlinedButton.icon(
                  onPressed: loading ? null : onExport,
                  icon: const Icon(Icons.download),
                  label: const Text('Exportar catálogos'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyReviewCard extends StatelessWidget {
  final bool reviewLoading;
  const _EmptyReviewCard({required this.reviewLoading});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: SizedBox(
        height: 130,
        child: Center(
          child: reviewLoading
              ? const CircularProgressIndicator()
              : const Text(
                  'Selecciona un Excel para ver nuevos registros, coincidencias y cambios.',
                ),
        ),
      ),
    );
  }
}

class _ReviewSummary extends StatelessWidget {
  final _SeedImportReview review;
  final int skippedCount;
  const _ReviewSummary({required this.review, required this.skippedCount});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _MetricTile(
          label: 'Nuevos',
          value: review.newPeopleCount,
          icon: Icons.person_add_alt_1,
          color: Colors.green,
        ),
        _MetricTile(
          label: 'En otra empresa',
          value: review.otherCompanyCount,
          icon: Icons.add_business,
          color: Colors.indigo,
        ),
        _MetricTile(
          label: 'Con cambios',
          value: review.changedPeopleCount,
          icon: Icons.sync_alt,
          color: Colors.orange,
        ),
        _MetricTile(
          label: 'Sin cambios',
          value: review.samePeopleCount,
          icon: Icons.check_circle_outline,
          color: Colors.teal,
        ),
        _MetricTile(
          label: 'Omitidos',
          value: skippedCount,
          icon: Icons.pause_circle_outline,
          color: Colors.grey,
        ),
        if (review.cedulaIssuesTotal > 0)
          _MetricTile(
            label: 'Cédulas a revisar',
            value: review.cedulaIssuesTotal,
            icon: Icons.warning_amber_rounded,
            color: Colors.red,
          ),
        _MetricTile(
          label: 'Areas nuevas',
          value: review.newAreasCount,
          icon: Icons.account_tree_outlined,
          color: Colors.blue,
        ),
        _MetricTile(
          label: 'Cargos nuevos',
          value: review.newCargosCount,
          icon: Icons.badge_outlined,
          color: Colors.purple,
        ),
        _MetricTile(
          label: 'Centros nuevos',
          value: review.newCentrosCount,
          icon: Icons.account_balance_wallet_outlined,
          color: Colors.brown,
        ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;
  final Color color;

  const _MetricTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 150,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Color.alphaBlend(color.withValues(alpha: 0.08), scheme.surface),
        border: Border.all(color: color.withValues(alpha: 0.22)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$value',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewTabs extends StatelessWidget {
  final _SeedImportReview? review;
  final List<Map<String, dynamic>> rows;
  final Set<String> skippedCedulas;
  final ValueChanged<String> onToggleSkip;

  const _ReviewTabs({
    required this.review,
    required this.rows,
    required this.skippedCedulas,
    required this.onToggleSkip,
  });

  @override
  Widget build(BuildContext context) {
    final data = review;
    return Card(
      margin: EdgeInsets.zero,
      child: DefaultTabController(
        length: 4,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const TabBar(
              isScrollable: true,
              tabs: [
                Tab(icon: Icon(Icons.people_outline), text: 'Personas'),
                Tab(icon: Icon(Icons.account_tree_outlined), text: 'Areas'),
                Tab(icon: Icon(Icons.badge_outlined), text: 'Cargos'),
                Tab(
                  icon: Icon(Icons.account_balance_wallet_outlined),
                  text: 'Centros',
                ),
              ],
            ),
            SizedBox(
              height: 460,
              child: TabBarView(
                children: [
                  data == null
                      ? _PreviewTable(rows: rows)
                      : _PeopleReviewTable(
                          items: data.people,
                          skippedCedulas: skippedCedulas,
                          onToggleSkip: onToggleSkip,
                          emptyCedulaCount: data.emptyCedulaCount,
                          duplicateCedulas: data.duplicateCedulas,
                        ),
                  data == null
                      ? const Center(
                          child: Text('Carga un Excel para revisar areas.'),
                        )
                      : _CatalogReviewTable(items: data.areas),
                  data == null
                      ? const Center(
                          child: Text('Carga un Excel para revisar cargos.'),
                        )
                      : _CatalogReviewTable(items: data.cargos),
                  data == null
                      ? const Center(
                          child: Text('Carga un Excel para revisar centros.'),
                        )
                      : _CatalogReviewTable(items: data.centros),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeopleReviewTable extends StatelessWidget {
  final List<_PersonReviewItem> items;
  final Set<String> skippedCedulas;
  final ValueChanged<String> onToggleSkip;
  final int emptyCedulaCount;
  final List<String> duplicateCedulas;

  const _PeopleReviewTable({
    required this.items,
    required this.skippedCedulas,
    required this.onToggleSkip,
    this.emptyCedulaCount = 0,
    this.duplicateCedulas = const [],
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Center(
        child: Text('No hay filas de PERSONAL para revisar.'),
      );
    }

    final warnCount = items.where((i) => i.hasCedulaWarning).length;
    final showBanner =
        warnCount > 0 || emptyCedulaCount > 0 || duplicateCedulas.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showBanner)
          _CedulaWarningBanner(
            warnCount: warnCount,
            emptyCount: emptyCedulaCount,
            duplicateCedulas: duplicateCedulas,
          ),
        Expanded(child: _buildTable(context)),
      ],
    );
  }

  Widget _buildTable(BuildContext context) {
    return Scrollbar(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
          child: DataTable(
            columnSpacing: 18,
            columns: const [
              DataColumn(label: Text('Estado')),
              DataColumn(label: Text('Persona')),
              DataColumn(label: Text('Empresas actuales')),
              DataColumn(label: Text('Comparacion')),
              DataColumn(label: Text('Accion')),
            ],
            rows: items.map((item) {
              final skipped = skippedCedulas.contains(item.cedula);
              return DataRow(
                selected: skipped,
                color: item.hasCedulaWarning && !skipped
                    ? WidgetStatePropertyAll(Colors.red.withValues(alpha: 0.06))
                    : null,
                cells: [
                  DataCell(_StatusChip(item: item)),
                  DataCell(
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 250),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (item.hasCedulaWarning) ...[
                            Tooltip(
                              message: item.cedulaWarnings.join('\n'),
                              child: const Icon(
                                Icons.warning_amber_rounded,
                                size: 18,
                                color: Colors.red,
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Flexible(
                            child: Text(
                              '${item.name}\n${item.cedula}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  DataCell(
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: Text(
                        item.currentCompanies.isEmpty
                            ? 'Sin registro'
                            : item.currentCompanies.join(', '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  DataCell(
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 380),
                      child: Text(
                        item.diffSummary,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  DataCell(
                    OutlinedButton.icon(
                      onPressed: () => onToggleSkip(item.cedula),
                      icon: Icon(
                        skipped ? Icons.undo : Icons.pause_circle_outline,
                      ),
                      label: Text(skipped ? 'Incluir' : item.skipLabel),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

/// Banner de advertencia sobre cédulas que ameritan revisión antes de importar.
class _CedulaWarningBanner extends StatelessWidget {
  final int warnCount;
  final int emptyCount;
  final List<String> duplicateCedulas;

  const _CedulaWarningBanner({
    required this.warnCount,
    required this.emptyCount,
    required this.duplicateCedulas,
  });

  @override
  Widget build(BuildContext context) {
    final lines = <String>[
      if (warnCount > 0)
        '$warnCount cédula(s) con formato sospechoso (marcadas con ⚠ en la lista).',
      if (emptyCount > 0)
        '$emptyCount fila(s) con datos pero SIN cédula: se omiten al importar.',
      if (duplicateCedulas.isNotEmpty)
        'Cédula(s) repetida(s) en el Excel (solo se importa la primera): '
            '${duplicateCedulas.take(8).join(', ')}'
            '${duplicateCedulas.length > 8 ? '…' : ''}.',
    ];

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.withValues(alpha: 0.30)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Revisa estas cédulas antes de importar',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Colors.red,
                  ),
                ),
                const SizedBox(height: 4),
                ...lines.map(
                  (l) => Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text('• $l', style: const TextStyle(fontSize: 13)),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Puedes corregir el Excel y recargar, u omitir las filas con el '
                  'botón de cada fila. La importación no se bloquea.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final _PersonReviewItem item;
  const _StatusChip({required this.item});

  @override
  Widget build(BuildContext context) {
    final color = switch (item.status) {
      _PersonStatus.newUser => Colors.green,
      _PersonStatus.existingOtherCompany => Colors.indigo,
      _PersonStatus.existingChanged => Colors.orange,
      _PersonStatus.existingSame => Colors.teal,
    };
    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(item.icon, size: 16, color: color),
      label: Text(item.statusLabel),
      side: BorderSide(color: color.withValues(alpha: 0.35)),
      backgroundColor: color.withValues(alpha: 0.08),
    );
  }
}

class _CatalogReviewTable extends StatelessWidget {
  final List<_CatalogReviewItem> items;
  const _CatalogReviewTable({required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Center(child: Text('No hay datos para revisar.'));
    }

    return Scrollbar(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Estado')),
              DataColumn(label: Text('Nombre')),
              DataColumn(label: Text('ID destino')),
              DataColumn(label: Text('Detalle')),
            ],
            rows: items.map((item) {
              final color = item.exists ? Colors.teal : Colors.green;
              return DataRow(
                cells: [
                  DataCell(
                    Chip(
                      visualDensity: VisualDensity.compact,
                      avatar: Icon(
                        item.exists
                            ? Icons.check_circle_outline
                            : Icons.add_circle_outline,
                        size: 16,
                        color: color,
                      ),
                      label: Text(item.exists ? 'Ya existe' : 'Nuevo'),
                      side: BorderSide(color: color.withValues(alpha: 0.35)),
                      backgroundColor: color.withValues(alpha: 0.08),
                    ),
                  ),
                  DataCell(Text(item.name)),
                  DataCell(Text(item.id)),
                  DataCell(
                    Text(item.detail.isEmpty ? item.source : item.detail),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

class _EmpresaOption {
  final String id;
  final String nombre;

  _EmpresaOption({required this.id, required this.nombre});
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
      children: items.entries
          .map((e) => Chip(label: Text('${e.key}: ${e.value}')))
          .toList(),
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
    final cols = freq.keys.toList()
      ..sort((a, b) => (freq[b] ?? 0).compareTo(freq[a] ?? 0));
    final display = cols.take(10).toList();

    return Scrollbar(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: MediaQuery.of(context).size.width - 64,
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: DataTable(
              columns: display.map((k) => DataColumn(label: Text(k))).toList(),
              rows: rows
                  .take(200)
                  .map(
                    (r) => DataRow(
                      cells: display
                          .map((k) => DataCell(Text('${r[k] ?? ''}')))
                          .toList(),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ),
    );
  }
}

enum _PersonStatus {
  newUser,
  existingOtherCompany,
  existingChanged,
  existingSame,
}

class _PersonReviewItem {
  final String cedula;
  final String name;
  final _PersonStatus status;
  final List<String> currentCompanies;
  final List<String> diffs;
  final Map<String, dynamic> row;

  const _PersonReviewItem({
    required this.cedula,
    required this.name,
    required this.status,
    required this.currentCompanies,
    required this.diffs,
    required this.row,
  });

  String get statusLabel {
    switch (status) {
      case _PersonStatus.newUser:
        return 'Nuevo';
      case _PersonStatus.existingOtherCompany:
        return 'Otra empresa';
      case _PersonStatus.existingChanged:
        return 'Actualizar';
      case _PersonStatus.existingSame:
        return 'Sin cambios';
    }
  }

  IconData get icon {
    switch (status) {
      case _PersonStatus.newUser:
        return Icons.person_add_alt_1;
      case _PersonStatus.existingOtherCompany:
        return Icons.add_business;
      case _PersonStatus.existingChanged:
        return Icons.sync_alt;
      case _PersonStatus.existingSame:
        return Icons.check_circle_outline;
    }
  }

  String get diffSummary {
    if (status == _PersonStatus.newUser) {
      return 'Se creara usuario, acceso temporal y membresia en la empresa destino.';
    }
    if (status == _PersonStatus.existingOtherCompany) {
      final area = _s(row['area']);
      final cargo = _s(row['cargo']);
      final parts = <String>[
        'Se agregara esta empresa sin borrar sus empresas actuales.',
        if (area.isNotEmpty) 'Area: $area',
        if (cargo.isNotEmpty) 'Cargo: $cargo',
      ];
      return parts.join(' · ');
    }
    if (diffs.isEmpty) {
      return 'El Excel coincide con los datos actuales de esta empresa.';
    }
    return diffs.join(' · ');
  }

  String get skipLabel {
    if (status == _PersonStatus.existingOtherCompany) return 'No vincular';
    if (status == _PersonStatus.newUser) return 'Omitir';
    return 'Mantener actual';
  }

  /// Avisos de formato sobre la cédula. No bloquean la importación, pero se
  /// resaltan para que el admin decida (omitir, corregir el Excel, etc.).
  List<String> get cedulaWarnings {
    final raw = _s(row['cedula']);
    final digits = cedula; // ya normalizada a dígitos en el review
    final out = <String>[];
    if (raw.isNotEmpty && _digits(raw) != raw) {
      out.add('La celda traía caracteres no numéricos: "$raw"');
    }
    if (digits.isNotEmpty && (digits.length < 6 || digits.length > 10)) {
      out.add('Longitud ${digits.length} (se esperan 6–10 dígitos)');
    }
    if (digits.length >= 6 && RegExp(r'0{3,}$').hasMatch(digits)) {
      out.add(
        'Termina en ceros: posible truncamiento al leer Excel como número',
      );
    }
    return out;
  }

  bool get hasCedulaWarning => cedulaWarnings.isNotEmpty;
}

class _CatalogReviewItem {
  final String name;
  final String id;
  final bool exists;
  final String source;
  final String sourceKey;
  final String detail;

  const _CatalogReviewItem({
    required this.name,
    required this.id,
    required this.exists,
    required this.source,
    this.sourceKey = '',
    this.detail = '',
  });
}

class _SeedImportReview {
  final List<_PersonReviewItem> people;
  final List<_CatalogReviewItem> areas;
  final List<_CatalogReviewItem> cargos;
  final List<_CatalogReviewItem> centros;

  /// Filas de PERSONAL con datos pero SIN cédula (se omiten silenciosamente al
  /// importar: data-loss que hay que avisar).
  final int emptyCedulaCount;

  /// Cédulas que aparecen repetidas dentro del mismo Excel (solo la primera
  /// ocurrencia se importa; el resto se pierde).
  final List<String> duplicateCedulas;

  const _SeedImportReview({
    required this.people,
    required this.areas,
    required this.cargos,
    required this.centros,
    this.emptyCedulaCount = 0,
    this.duplicateCedulas = const [],
  });

  int get suspiciousCedulaCount =>
      people.where((p) => p.hasCedulaWarning).length;

  /// Total de cédulas que ameritan revisión (formato + vacías + duplicadas).
  int get cedulaIssuesTotal =>
      suspiciousCedulaCount + emptyCedulaCount + duplicateCedulas.length;

  int get newPeopleCount =>
      people.where((p) => p.status == _PersonStatus.newUser).length;
  int get otherCompanyCount => people
      .where((p) => p.status == _PersonStatus.existingOtherCompany)
      .length;
  int get changedPeopleCount =>
      people.where((p) => p.status == _PersonStatus.existingChanged).length;
  int get samePeopleCount =>
      people.where((p) => p.status == _PersonStatus.existingSame).length;
  int get newAreasCount => areas.where((a) => !a.exists).length;
  int get newCargosCount => cargos.where((c) => !c.exists).length;
  int get newCentrosCount => centros.where((c) => !c.exists).length;

  static Future<_SeedImportReview> load({
    required SeedWorkbook wb,
    required String empresaId,
    required String empresaNombre,
  }) async {
    final cedulas = wb.personal
        .map((row) => _digits(_s(row['cedula'])))
        .where((cedula) => cedula.isNotEmpty)
        .toSet();
    final existingUsers = await _loadDocsByIds('TBL_USUARIOS', cedulas);

    // Agregados de salud sobre el propio Excel: filas sin cédula y cédulas
    // duplicadas dentro del archivo (ambas terminan perdiéndose en la importación).
    var emptyCedulaCount = 0;
    final seenDigits = <String>{};
    final dupDigits = <String>{};
    for (final row in wb.personal) {
      final d = _digits(_s(row['cedula']));
      if (d.isEmpty) {
        emptyCedulaCount++;
        continue;
      }
      if (!seenDigits.add(d)) dupDigits.add(d);
    }

    final areaCandidates = _buildAreaCandidates(wb, empresaId);
    final cargoCandidates = _buildCargoCandidates(wb, empresaId);
    final centroCandidates = _buildCentroCandidates(wb, empresaId);

    final areaIds = areaCandidates
        .map((item) => item.id)
        .where((id) => id.isNotEmpty)
        .toSet();
    final cargoIds = cargoCandidates
        .map((item) => item.id)
        .where((id) => id.isNotEmpty)
        .toSet();
    final centroIds = centroCandidates
        .map((item) => item.id)
        .where((id) => id.isNotEmpty)
        .toSet();

    final existingAreas = await _loadDocsByIds('TBL_AREAS', areaIds);
    final existingCargos = await _loadDocsByIds('TBL_CARGOS', cargoIds);
    final existingCentrosById = await _loadDocsByIds(
      'TBL_CENTROS_COSTOS',
      centroIds,
    );
    final existingCentrosByName = await _loadExistingCentrosByName(empresaId);
    final existingCentrosByCode = await _loadExistingCentrosByCode(empresaId);

    return _SeedImportReview(
      emptyCedulaCount: emptyCedulaCount,
      duplicateCedulas: dupDigits.toList()..sort(),
      people: _buildPeopleReview(
        wb.personal,
        existingUsers,
        empresaId,
        empresaNombre,
      ),
      areas: areaCandidates
          .map(
            (item) => _CatalogReviewItem(
              name: item.name,
              id: item.id,
              exists: existingAreas.containsKey(item.id),
              source: item.source,
              detail: item.detail,
            ),
          )
          .toList(),
      cargos: cargoCandidates
          .map(
            (item) => _CatalogReviewItem(
              name: item.name,
              id: item.id,
              exists: existingCargos.containsKey(item.id),
              source: item.source,
              detail: item.detail,
            ),
          )
          .toList(),
      centros: centroCandidates.map((item) {
        final nameKey = _normKey(item.name);
        final codeKey = _normKey(item.sourceKey);
        final sameId = existingCentrosById.containsKey(item.id);
        final sameName = existingCentrosByName[nameKey];
        final sameCode = codeKey.isEmpty
            ? null
            : existingCentrosByCode[codeKey];
        final matchedId = sameId ? item.id : sameName ?? sameCode;
        final matchDetail = matchedId == null
            ? item.detail
            : matchedId == item.id
            ? 'Coincide por ID destino'
            : 'Coincide por nombre/codigo con $matchedId';

        return _CatalogReviewItem(
          name: item.name,
          id: matchedId ?? item.id,
          exists: matchedId != null,
          source: item.source,
          sourceKey: item.sourceKey,
          detail: matchDetail,
        );
      }).toList(),
    );
  }

  static List<_PersonReviewItem> _buildPeopleReview(
    List<Map<String, dynamic>> rows,
    Map<String, Map<String, dynamic>> existingUsers,
    String empresaId,
    String empresaNombre,
  ) {
    final out = <_PersonReviewItem>[];
    final seen = <String>{};

    for (final row in rows) {
      final cedula = _digits(_s(row['cedula']));
      if (cedula.isEmpty || !seen.add(cedula)) continue;

      final existing = existingUsers[cedula];
      final name = _displayName(row, existing);
      if (existing == null) {
        out.add(
          _PersonReviewItem(
            cedula: cedula,
            name: name,
            status: _PersonStatus.newUser,
            currentCompanies: const [],
            diffs: const [],
            row: row,
          ),
        );
        continue;
      }

      final companies = extractUserEmpresaIds(existing);
      final belongsToTarget = companies.contains(empresaId);
      if (!belongsToTarget) {
        out.add(
          _PersonReviewItem(
            cedula: cedula,
            name: name,
            status: _PersonStatus.existingOtherCompany,
            currentCompanies: companies,
            diffs: ['Nueva membresia: $empresaNombre'],
            row: row,
          ),
        );
        continue;
      }

      final diffs = _diffRowWithExisting(row, existing, empresaId);
      out.add(
        _PersonReviewItem(
          cedula: cedula,
          name: name,
          status: diffs.isEmpty
              ? _PersonStatus.existingSame
              : _PersonStatus.existingChanged,
          currentCompanies: companies,
          diffs: diffs,
          row: row,
        ),
      );
    }

    out.sort((a, b) {
      final statusCompare = a.status.index.compareTo(b.status.index);
      if (statusCompare != 0) return statusCompare;
      return a.name.compareTo(b.name);
    });
    return out;
  }

  static List<String> _diffRowWithExisting(
    Map<String, dynamic> row,
    Map<String, dynamic> existing,
    String empresaId,
  ) {
    final detail = getUserCompanyDetail(existing, empresaId);

    String current(List<String> scopedKeys, List<String> fallbackKeys) {
      if (detail != null) {
        for (final key in scopedKeys) {
          final value = _s(detail[key]);
          if (value.isNotEmpty) return value;
        }
      }
      for (final key in fallbackKeys) {
        final value = _s(existing[key]);
        if (value.isNotEmpty) return value;
      }
      return '';
    }

    final comparisons = <({String label, String excel, String current})>[
      (
        label: 'Area',
        excel: _s(row['area']),
        current: current(
          const ['areaNombre', 'area'],
          const ['areaNombre', 'area'],
        ),
      ),
      (
        label: 'Cargo',
        excel: _s(row['cargo']),
        current: current(const ['cargo'], const ['cargo']),
      ),
      (
        label: 'Centro',
        excel: _s(row['centroCostos']),
        current: current(const ['centroCostos'], const ['centroCostos']),
      ),
      (
        label: 'Correo',
        excel: _s(row['correo']),
        current: current(const ['correo'], const ['correo']),
      ),
      (
        label: 'Estado',
        excel: _s(row['estado']).toLowerCase(),
        current: current(const ['estado'], const ['estado']).toLowerCase(),
      ),
    ];

    final diffs = <String>[];
    for (final item in comparisons) {
      if (item.excel.isEmpty) continue;
      if (_normKey(item.excel) == _normKey(item.current)) continue;
      final currentValue = item.current.isEmpty ? 'vacio' : item.current;
      diffs.add('${item.label}: "$currentValue" -> "${item.excel}"');
    }
    return diffs;
  }

  static String _displayName(
    Map<String, dynamic> row,
    Map<String, dynamic>? existing,
  ) {
    final full = _s(row['nombreCompleto']);
    if (full.isNotEmpty) return full;
    final rowName = '${_s(row['nombres'])} ${_s(row['apellidos'])}'.trim();
    if (rowName.isNotEmpty) return rowName;
    final existingFull = _s(existing?['nombreCompleto']);
    if (existingFull.isNotEmpty) return existingFull;
    final existingName =
        '${_s(existing?['nombres'])} ${_s(existing?['apellidos'])}'.trim();
    return existingName.isEmpty ? _digits(_s(row['cedula'])) : existingName;
  }

  static List<_CatalogReviewItem> _buildAreaCandidates(
    SeedWorkbook wb,
    String empresaId,
  ) {
    final out = <String, _CatalogReviewItem>{};

    void add(String name, String source, {String detail = ''}) {
      final n = name.trim();
      if (n.isEmpty) return;
      final key = _normKey(n);
      out[key] = _CatalogReviewItem(
        name: n,
        id: '${empresaId}_${_idFromName(n)}',
        exists: false,
        source: source,
        detail: detail,
      );
    }

    for (final row in wb.areas) {
      add(
        _s(row['nombre']).isNotEmpty
            ? _s(row['nombre'])
            : _s(row['descripcion']),
        'Hoja AREAS',
      );
    }
    for (final row in wb.personal) {
      add(_s(row['area']), 'Inferida desde PERSONAL');
    }

    return out.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  }

  static List<_CatalogReviewItem> _buildCargoCandidates(
    SeedWorkbook wb,
    String empresaId,
  ) {
    final out = <String, _CatalogReviewItem>{};

    void add(String name, String source, {String area = ''}) {
      final n = name.trim();
      if (n.isEmpty) return;
      final key = _normKey(n);
      out[key] = _CatalogReviewItem(
        name: n,
        id: '${empresaId}_${_idFromName(n)}',
        exists: false,
        source: source,
        detail: area.isEmpty ? source : 'Area: $area',
      );
    }

    for (final row in wb.cargos) {
      add(
        _s(row['nombre']).isNotEmpty
            ? _s(row['nombre'])
            : _s(row['descripcion']),
        'Hoja CARGOS',
        area: _s(row['area']),
      );
    }
    for (final row in wb.personal) {
      add(_s(row['cargo']), 'Inferido desde PERSONAL', area: _s(row['area']));
    }

    return out.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  }

  static List<_CatalogReviewItem> _buildCentroCandidates(
    SeedWorkbook wb,
    String empresaId,
  ) {
    final out = <String, _CatalogReviewItem>{};

    void add({
      required String name,
      required String code,
      required String source,
    }) {
      final n = name.trim();
      final c = code.trim();
      if (n.isEmpty && c.isEmpty) return;
      final displayName = n.isNotEmpty ? n : c;
      final key = _normKey(n.isNotEmpty ? n : c);
      final idBase = c.isNotEmpty ? c : _idFromName(displayName);
      out[key] = _CatalogReviewItem(
        name: displayName,
        id: '${empresaId}_$idBase',
        exists: false,
        source: source,
        sourceKey: c,
        detail: c.isEmpty ? source : 'Codigo: $c',
      );
    }

    for (final row in wb.centrosCostos) {
      add(
        name: _s(row['nombre']),
        code: _s(row['codigo']),
        source: 'Hoja CENTROS',
      );
    }
    for (final row in wb.personal) {
      add(
        name: _s(row['centroCostos']),
        code: '',
        source: 'Inferido desde PERSONAL',
      );
    }

    return out.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  }

  static Future<Map<String, Map<String, dynamic>>> _loadDocsByIds(
    String collection,
    Set<String> ids,
  ) async {
    final out = <String, Map<String, dynamic>>{};
    if (ids.isEmpty) return out;

    final col = FirebaseFirestore.instance.collection(collection);
    final all = ids.toList();
    const chunkSize = 10;
    for (var i = 0; i < all.length; i += chunkSize) {
      final chunk = all.sublist(
        i,
        i + chunkSize > all.length ? all.length : i + chunkSize,
      );
      final snap = await col.where(FieldPath.documentId, whereIn: chunk).get();
      for (final doc in snap.docs) {
        out[doc.id] = doc.data();
      }
    }
    return out;
  }

  static Future<Map<String, String>> _loadExistingCentrosByName(
    String empresaId,
  ) async {
    final snap = await FirebaseFirestore.instance
        .collection('TBL_CENTROS_COSTOS')
        .where('empresaId', isEqualTo: empresaId)
        .get();
    final out = <String, String>{};
    for (final doc in snap.docs) {
      final nombre = _s(doc.data()['nombre']);
      if (nombre.isNotEmpty) out[_normKey(nombre)] = doc.id;
    }
    return out;
  }

  static Future<Map<String, String>> _loadExistingCentrosByCode(
    String empresaId,
  ) async {
    final snap = await FirebaseFirestore.instance
        .collection('TBL_CENTROS_COSTOS')
        .where('empresaId', isEqualTo: empresaId)
        .get();
    final out = <String, String>{};
    for (final doc in snap.docs) {
      final codigo = _s(doc.data()['codigo']);
      if (codigo.isNotEmpty) out[_normKey(codigo)] = doc.id;
    }
    return out;
  }
}
