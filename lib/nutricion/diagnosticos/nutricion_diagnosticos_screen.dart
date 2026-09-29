// lib/nutricion/diagnosticos/nutricion_diagnosticos_screen.dart
//
// Nutrición › Diagnósticos (29 sep 2026, antes en Admin › Diagnósticos): el
// catálogo que usa el selector de diagnósticos de la atención.
// - Médicos (CIE-11): el selector busca primero en línea en la API de la OMS;
//   este catálogo es el respaldo si la consulta falla.
// - Nutricionales: salen siempre de este catálogo.
// Es uno solo para todas las empresas. Sin nada cargado, la app usa la
// plantilla que trae (assets/diagnosticos_template.xlsx). Solo Administración
// (o Desarrollo) lo actualiza desde un Excel; el resto lo consulta.
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../admin/task_module_role.dart' show canManageModuleRoles;
import '../../services/diagnosticos_service.dart';
import '../../theme/app_typography.dart';
import '../../utils/excel_download.dart';
import '../../widgets/paged_list.dart';
import '../widgets/nutrition_shared_widgets.dart';

/// Una fila del catálogo para la consulta.
typedef FilaDiagnostico = ({String codigo, String nombre, String detalle});

/// Filtra por código, nombre o detalle, sin distinguir mayúsculas.
List<FilaDiagnostico> filtrarDiagnosticos(
  List<FilaDiagnostico> filas,
  String busqueda,
) {
  final q = busqueda.trim().toLowerCase();
  if (q.isEmpty) return filas;
  return [
    for (final f in filas)
      if (f.codigo.toLowerCase().contains(q) ||
          f.nombre.toLowerCase().contains(q) ||
          f.detalle.toLowerCase().contains(q))
        f,
  ];
}

class NutricionDiagnosticosScreen extends StatefulWidget {
  const NutricionDiagnosticosScreen({
    super.key,
    required this.userId,
    required this.empresaId,
    this.service,
    this.db,
  });

  final String userId;
  final String empresaId;
  final DiagnosticosService? service;
  final FirebaseFirestore? db;

  @override
  State<NutricionDiagnosticosScreen> createState() =>
      _NutricionDiagnosticosScreenState();
}

class _NutricionDiagnosticosScreenState
    extends State<NutricionDiagnosticosScreen> {
  late final DiagnosticosService _service =
      widget.service ?? DiagnosticosService();
  late final FirebaseFirestore _db = widget.db ?? FirebaseFirestore.instance;

  ({int medicos, int nutricionales})? _conteo;
  bool _puedeImportar = false;
  String? _archivo;
  Uint8List? _bytes;
  bool _importando = false;

  bool _nutricionales = true;
  String _busqueda = '';
  int _pagina = 0;
  List<FilaDiagnostico>? _medicos;
  List<FilaDiagnostico>? _nutris;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final actor = await _db
          .collection('TBL_USUARIOS')
          .doc(widget.userId)
          .get();
      final puede =
          actor.exists &&
          canManageModuleRoles(actor.data() ?? const {}, widget.empresaId);
      if (mounted) setState(() => _puedeImportar = puede);
    } catch (_) {
      // Sin ficha legible no se muestra la importación.
    }
    await _recargarCatalogo();
  }

  Future<void> _recargarCatalogo() async {
    try {
      final conteo = await _service.contarEnBase();
      final medicos = await _service.listarDiagnosticosMedicos();
      final nutris = await _service.listarDiagnosticosNutricionales();
      if (!mounted) return;
      setState(() {
        _conteo = conteo;
        _medicos = [
          for (final d in medicos)
            (
              codigo: d.codigoCie11,
              nombre: d.nombre,
              detalle: [
                d.categoria,
                d.subcategoria,
              ].whereType<String>().where((t) => t.isNotEmpty).join(' · '),
            ),
        ];
        _nutris = [
          for (final d in nutris)
            (
              codigo: d.codigo,
              nombre: d.nombre,
              detalle: d.tipoDietaSugerida ?? '',
            ),
        ];
      });
    } catch (e) {
      if (mounted) _mensaje('No se pudo leer el catálogo: $e', error: true);
    }
  }

  void _mensaje(String texto, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texto),
        backgroundColor: error ? NutritionPalette.danger : null,
      ),
    );
  }

  Future<void> _descargarPlantilla() async {
    try {
      final data = await rootBundle.load('assets/diagnosticos_template.xlsx');
      await descargarExcelCompras(
        nombreArchivo: 'plantilla_diagnosticos',
        bytes: data.buffer.asUint8List(),
      );
    } catch (e) {
      if (mounted)
        _mensaje('No se pudo descargar la plantilla: $e', error: true);
    }
  }

  Future<void> _elegirArchivo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xlsm', 'xls'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) {
      _mensaje('No se pudo leer el archivo.', error: true);
      return;
    }
    setState(() {
      _archivo = file.name;
      _bytes = file.bytes;
    });
  }

  Future<void> _importar() async {
    final bytes = _bytes;
    if (bytes == null) return;
    setState(() => _importando = true);
    try {
      final result = await _service.importarDiagnosticosDesdeExcel(
        bytes: bytes,
        empresaId: widget.empresaId,
        userId: widget.userId,
        sobrescribir: true,
      );
      if (!mounted) return;
      _mensaje(
        'Catálogo actualizado: ${result['diagnosticosMedicos'] ?? 0} médicos y '
        '${result['diagnosticosNutricionales'] ?? 0} nutricionales.',
      );
      setState(() {
        _archivo = null;
        _bytes = null;
      });
      await _recargarCatalogo();
    } catch (e) {
      if (mounted) _mensaje('No se pudo importar: $e', error: true);
    } finally {
      if (mounted) setState(() => _importando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final conteo = _conteo;
    final filas = filtrarDiagnosticos(
      (_nutricionales ? _nutris : _medicos) ?? const [],
      _busqueda,
    );
    final pagina = _pagina.clamp(0, pageCountOf(filas.length) - 1);
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        NutritionCard(
          title: 'Catálogo de diagnósticos',
          subtitle: 'Lo usa el selector de diagnósticos de la atención.',
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '• Nutricionales: salen siempre de este catálogo.\n'
                  '• Médicos (CIE-11): se buscan primero en línea en la OMS; '
                  'este catálogo es el respaldo si esa consulta falla.\n'
                  '• Es uno solo para todas las empresas.',
                  style: TextStyle(fontFamily: kArial, height: 1.5),
                ),
                const SizedBox(height: 12),
                Text(
                  conteo == null
                      ? 'Contando…'
                      : conteo.medicos + conteo.nutricionales == 0
                      ? 'No hay catálogo cargado: se usa la plantilla que trae '
                            'la app.'
                      : 'Cargados: ${conteo.medicos} médicos y '
                            '${conteo.nutricionales} nutricionales.',
                  style: const TextStyle(
                    fontFamily: kArial,
                    fontWeight: FontWeight.w800,
                    color: NutritionPalette.textMain,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _puedeImportar ? _importacion() : _soloConsulta(),
        const SizedBox(height: 16),
        NutritionCard(
          title: 'Consultar',
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                          value: true,
                          label: Text('Nutricionales'),
                        ),
                        ButtonSegment(value: false, label: Text('Médicos')),
                      ],
                      selected: {_nutricionales},
                      onSelectionChanged: (v) => setState(() {
                        _nutricionales = v.first;
                        _pagina = 0;
                      }),
                    ),
                    SizedBox(
                      width: 320,
                      child: TextField(
                        decoration: const InputDecoration(
                          isDense: true,
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Buscar por código o nombre',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (v) => setState(() {
                          _busqueda = v;
                          _pagina = 0;
                        }),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if ((_nutricionales ? _nutris : _medicos) == null)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (filas.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Ningún diagnóstico coincide.'),
                  )
                else ...[
                  for (final f in pageOf(filas, pagina))
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: ClinicalTag(
                        label: f.codigo,
                        color: NutritionPalette.accent,
                        isCompact: true,
                      ),
                      title: Text(f.nombre),
                      subtitle: f.detalle.isEmpty ? null : Text(f.detalle),
                    ),
                  PagerBar(
                    total: filas.length,
                    page: pagina,
                    etiqueta: 'diagnósticos',
                    onPageChanged: (p) => setState(() => _pagina = p),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _soloConsulta() => const NutritionCard(
    child: Padding(
      padding: EdgeInsets.all(16),
      child: Text(
        'Solo Administración actualiza el catálogo. Si falta un diagnóstico, '
        'pídeselo con el código y el nombre.',
        style: TextStyle(fontFamily: kArial),
      ),
    ),
  );

  Widget _importacion() => NutritionCard(
    title: 'Actualizar desde Excel',
    subtitle: 'Reemplaza cada diagnóstico por el del archivo (por su código).',
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: _importando ? null : _descargarPlantilla,
                icon: const Icon(Icons.download_outlined),
                label: const Text('Descargar plantilla'),
              ),
              OutlinedButton.icon(
                onPressed: _importando ? null : _elegirArchivo,
                icon: const Icon(Icons.upload_file),
                label: const Text('Seleccionar Excel'),
              ),
              FilledButton.icon(
                onPressed: _importando || _bytes == null ? null : _importar,
                icon: _importando
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.cloud_upload_outlined),
                label: const Text('Importar'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _archivo == null
                ? 'Sin archivo seleccionado.'
                : 'Archivo: $_archivo',
            style: const TextStyle(
              fontFamily: kArial,
              fontSize: 12,
              color: NutritionPalette.textMuted,
            ),
          ),
        ],
      ),
    ),
  );
}
