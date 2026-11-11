import 'package:cloud_functions/cloud_functions.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../utils/excel_download.dart';
import '../widgets/internal_module_layout.dart';
import 'personnel_import_service.dart';
import 'personnel_template_service.dart';

const _accent = Color(0xFF173B5E);

class PersonnelImportScreen extends StatefulWidget {
  final String userId;
  final String empresaId;
  final PersonnelImportService? service;

  const PersonnelImportScreen({
    super.key,
    required this.userId,
    required this.empresaId,
    this.service,
  });

  @override
  State<PersonnelImportScreen> createState() => _PersonnelImportScreenState();
}

class _PersonnelImportScreenState extends State<PersonnelImportScreen> {
  late final _service = widget.service ?? PersonnelImportService();
  ArchivoCargaPersonal? _archivo;
  String? _nombreArchivo;
  RevisionCargaPersonal? _revision;
  String? _error;
  String? _progreso;
  int _creados = 0;

  bool get _ocupado => _progreso != null;

  Future<void> _descargar() => _operar('Generando plantilla…', () async {
    final bytes = await _service.plantilla(widget.empresaId);
    if (!mounted) return;
    const nombre = 'plantilla_nuevos_empleados';
    if (kIsWeb) {
      await descargarExcelCompras(nombreArchivo: nombre, bytes: bytes);
    } else {
      await FilePicker.platform.saveFile(
        fileName: '$nombre.xlsx',
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
        bytes: bytes,
      );
    }
  });

  Future<void> _seleccionar() => _operar(
    'Leyendo y validando el Excel…',
    () async {
      final archivos = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
        withData: true,
      );
      final archivo = archivos?.files.firstOrNull;
      if (!mounted || archivo == null) return;
      setState(() {
        _nombreArchivo = archivo.name;
        _archivo = null;
        _revision = null;
        _creados = 0;
      });
      final bytes = archivo.bytes;
      if (bytes == null) {
        throw const FormatException('No se pudo leer el archivo seleccionado.');
      }
      if (bytes.length > 5 * 1024 * 1024) {
        throw const FormatException('El archivo debe pesar máximo 5 MB.');
      }
      final datos = ArchivoCargaPersonal.leer(bytes);
      final revision = await _service.revisar(widget.empresaId, datos);
      if (!mounted) return;
      setState(() {
        _archivo = datos;
        _revision = revision;
      });
    },
  );

  Future<void> _confirmar() async {
    final archivo = _archivo;
    if (archivo == null || _ocupado) return;
    final total = archivo.filas.length;
    final aceptar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar altas'),
        content: Text(
          total == 1
              ? 'Se registrará un empleado nuevo en la empresa activa.'
              : 'Se registrarán $total empleados nuevos en la empresa activa.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Registrar'),
          ),
        ],
      ),
    );
    if (!mounted || aceptar != true) return;
    await _operar('Registrando empleados…', () async {
      final resultado = await _service.revisar(
        widget.empresaId,
        archivo,
        confirmar: true,
      );
      if (!mounted) return;
      setState(() {
        _revision = resultado;
        _creados = resultado.creados;
        if (_creados > 0) _archivo = null;
      });
    });
  }

  Future<void> _operar(String progreso, Future<void> Function() hacer) async {
    if (_ocupado) return;
    setState(() {
      _progreso = progreso;
      _error = null;
    });
    try {
      await hacer();
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        setState(
          () => _error = e.message ?? 'No se pudo completar la operación.',
        );
      }
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'No se pudo completar la operación. Revisa el archivo o vuelve a intentarlo.',
        );
      }
    } finally {
      if (mounted) setState(() => _progreso = null);
    }
  }

  @override
  Widget build(BuildContext context) => InternalModuleLayout(
    userId: widget.userId,
    empresaId: widget.empresaId,
    title: 'Carga masiva de empleados',
    accentColor: _accent,
    child: SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final amplia = constraints.maxWidth >= 900;
          return SingleChildScrollView(
            child: InternalModuleViewport(
              maxWidth: 1180,
              padding: EdgeInsets.all(amplia ? 28 : 16),
              child: amplia
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 290, child: _acciones()),
                        const SizedBox(width: 20),
                        Expanded(child: _resultado(amplia: true)),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _acciones(),
                        const SizedBox(height: 12),
                        _resultado(amplia: false),
                      ],
                    ),
            ),
          );
        },
      ),
    ),
  );

  Widget _acciones() => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Descarga la plantilla de la empresa activa. Diligencia PERSONAL '
            'con ayuda del ejemplo y de las listas desplegables.',
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _ocupado ? null : _descargar,
            icon: const Icon(Icons.download_outlined),
            label: const Text('Descargar plantilla'),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _ocupado ? null : _seleccionar,
            icon: const Icon(Icons.upload_file_outlined),
            label: const Text('Seleccionar Excel'),
          ),
        ],
      ),
    ),
  );

  Widget _resultado({required bool amplia}) {
    final revision = _revision;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Revisión de la carga',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (_nombreArchivo != null)
              Text(
                _nombreArchivo!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            const SizedBox(height: 12),
            if (_progreso != null) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Text(_progreso!),
            ],
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (_creados > 0)
              Text(
                _creados == 1
                    ? 'Se registró un empleado.'
                    : 'Se registraron $_creados empleados.',
              )
            else if (revision == null && _error == null && !_ocupado)
              const Text(
                'Selecciona un archivo .xlsx para revisar las filas antes de registrarlas.',
              )
            else if (revision != null) ...[
              Text(
                '${revision.vistas.length} filas válidas · ${revision.errores.length} con errores',
              ),
              if (revision.errores.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text(
                  'Corrige las filas indicadas en el Excel y vuelve a seleccionarlo.',
                ),
                for (final error in revision.errores)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('Fila ${error.fila}: ${error.mensaje}'),
                  ),
              ],
              if (revision.vistas.isNotEmpty) ...[
                const SizedBox(height: 12),
                _vistaPrevia(revision.vistas, amplia: amplia),
              ],
              if (revision.errores.isEmpty && _archivo != null) ...[
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _ocupado ? null : _confirmar,
                  child: Text(
                    revision.vistas.length == 1
                        ? 'Registrar 1 empleado'
                        : 'Registrar ${revision.vistas.length} empleados',
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _vistaPrevia(List<VistaAltaPersonal> filas, {required bool amplia}) {
    final muestra = filas.take(6);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (filas.length > 6)
          Text('Vista previa de 6 de ${filas.length} filas'),
        if (amplia)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Fila')),
                DataColumn(label: Text('Documento')),
                DataColumn(label: Text('Nombre')),
                DataColumn(label: Text('Área')),
                DataColumn(label: Text('Cargo')),
              ],
              rows: [
                for (final f in muestra)
                  DataRow(
                    cells: [
                      for (final valor in [
                        '${f.fila}',
                        f.cedula,
                        f.nombre,
                        f.area,
                        f.cargo,
                      ])
                        DataCell(Text(valor)),
                    ],
                  ),
              ],
            ),
          )
        else
          for (final f in muestra)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(f.nombre),
              subtitle: Text(
                [
                  'Fila ${f.fila}',
                  f.cedula,
                  f.area,
                  f.cargo,
                ].where((v) => v.isNotEmpty).join(' · '),
              ),
            ),
      ],
    );
  }
}
