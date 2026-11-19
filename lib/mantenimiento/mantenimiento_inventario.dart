import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import 'mantenimiento_archivos.dart' show nuevoIdMantenimiento;
import 'mantenimiento_forms.dart';
import 'mantenimiento_report.dart'
    show marcaMantenimiento, membreteMantenimiento;
import 'mantenimiento_service.dart';
import 'mantenimiento_web_widgets.dart';

const bodegaTemporalMantenimiento = '_bodega_temporal';

List<Map<String, dynamic>> _lista(Object? datos) => [
  for (final fila in (datos as List? ?? const []).whereType<Map>())
    Map<String, dynamic>.from(fila),
];

String _texto(Map datos, String campo) => (datos[campo] ?? '').toString();
String _fecha(DateTime fecha) => DateFormat('yyyy-MM-dd').format(fecha);

class InventarioMantenimiento extends StatefulWidget {
  const InventarioMantenimiento({
    super.key,
    required this.service,
    required this.equipos,
    required this.centros,
    required this.vistaWeb,
    this.minimos = false,
  });

  final MantenimientoService service;
  final List<EquipoMantenimiento> equipos;
  final List<EstablecimientoMantenimiento> centros;
  final bool vistaWeb, minimos;

  @override
  State<InventarioMantenimiento> createState() =>
      _InventarioMantenimientoState();
}

class _InventarioMantenimientoState extends State<InventarioMantenimiento> {
  Future<Map<String, dynamic>>? _catalogos;
  String _bodega = '', _categoria = '', _buscar = '', _ingreso = '';
  int _pagina = 0;

  Map<String, String> get _bodegas => {
    bodegaTemporalMantenimiento: 'Bodega temporal',
    for (final c in widget.centros) c.id: c.centro.nombre,
  };

  Future<void> _abrir(Widget pagina) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => pagina));
    if (mounted && widget.minimos) {
      setState(() {
        _catalogos = widget.service.inventario('catalogos');
      });
    }
  }

  void _alta([EquipoMantenimiento? equipo]) => _abrir(
    _ConCatalogos(
      futuro: _catalogos ??= widget.service.inventario('catalogos'),
      titulo: 'Registrar equipo',
      builder: (datos) => _AltaEquipo(
        service: widget.service,
        catalogos: datos,
        vistaWeb: widget.vistaWeb,
        equipo: equipo,
      ),
    ),
  );

  Future<void> _asociar(EquipoMantenimiento equipo, String sede) async {
    try {
      final datos = await widget.service.inventario('catalogos');
      if (!mounted) return;
      var familia = equipo.tipoEnSede(sede);
      final guardar = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(equipo.nombre),
          content: _selector('Tipo en el maestro de mínimos', familia, {
            '': 'Sin asociar',
            ..._familiasSede(datos, sede),
          }, (v) => familia = v),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Guardar'),
            ),
          ],
        ),
      );
      if (guardar == true && mounted) {
        await widget.service.inventario('asociar', {
          'equipoId': equipo.id,
          'familia': familia,
          'centroDocId': sede,
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is StateError ? e.message : 'No se pudo asociar el equipo.',
            ),
          ),
        );
      }
    }
  }

  void _movimiento(EquipoMantenimiento equipo, String origen, {bool? baja}) =>
      _abrir(
        _MovimientoEquipo(
          service: widget.service,
          equipo: equipo,
          origen: origen,
          origenNombre: _bodegas[origen] ?? origen,
          destinos: {
            bodegaTemporalMantenimiento: 'Bodega temporal',
            for (final c in widget.centros.where((c) => c.activo))
              c.id: c.centro.nombre,
          }..remove(origen),
          baja: baja ?? false,
          vistaWeb: widget.vistaWeb,
        ),
      );

  Widget _acciones(EquipoMantenimiento equipo, String bodega, int saldo) =>
      Wrap(
        spacing: 4,
        children: [
          TextButton(
            onPressed: () =>
                _abrir(_FichaEquipo(service: widget.service, equipo: equipo)),
            child: const Text('Ver'),
          ),
          if (saldo == 0 && equipo.datos['inventario'] != true)
            TextButton(
              onPressed: () => _alta(equipo),
              child: const Text('Registrar ingreso'),
            ),
          if (saldo > 0 && bodega != bodegaTemporalMantenimiento)
            TextButton(
              onPressed: () => _asociar(equipo, bodega),
              child: const Text('Asociar tipo'),
            ),
          if (saldo > 0)
            TextButton(
              onPressed: () => _movimiento(equipo, bodega),
              child: const Text('Trasladar'),
            ),
          if (saldo > 0)
            TextButton(
              onPressed: () => _movimiento(equipo, bodega, baja: true),
              child: const Text('Dar de baja'),
            ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    if (widget.minimos) {
      return FutureBuilder(
        future: _catalogos ??= widget.service.inventario('catalogos'),
        builder: (context, snap) {
          final datos = snap.data;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Mínimos por establecimiento',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              if (snap.hasError)
                PanelMantenimiento(
                  child: OutlinedButton(
                    onPressed: () => setState(() {
                      _catalogos = widget.service.inventario('catalogos');
                    }),
                    child: const Text('Reintentar la carga del maestro'),
                  ),
                )
              else if (datos == null)
                const LinearProgressIndicator()
              else ...[
                for (final centro in widget.centros.where((c) => c.activo))
                  PanelMantenimiento(
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(centro.centro.nombre),
                      subtitle: Text(_estadoPlan(datos, centro.id)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _abrir(
                        _MinimosSede(
                          service: widget.service,
                          centro: centro,
                          catalogos: datos,
                          equipos: widget.equipos,
                          vistaWeb: widget.vistaWeb,
                        ),
                      ),
                    ),
                  ),
              ],
            ],
          );
        },
      );
    }
    final bodegas = _bodegas;
    final filas = <(EquipoMantenimiento, String, int)>[];
    for (final e in widget.equipos) {
      if (e.datos['inventario'] == true &&
          !e.existencias.values.any((n) => n > 0)) {
        continue;
      }
      if (_categoria.isNotEmpty && _texto(e.datos, 'categoria') != _categoria) {
        continue;
      }
      if (_ingreso.isNotEmpty && _texto(e.datos, 'fechaIngreso') != _ingreso) {
        continue;
      }
      if (!'${e.codigo} ${e.nombre}'.toLowerCase().contains(
        _buscar.toLowerCase(),
      )) {
        continue;
      }
      if (e.existencias.isEmpty && _bodega.isEmpty) {
        filas.add((e, '', 0));
      }
      for (final b in e.existencias.entries) {
        if (b.value > 0 && (_bodega.isEmpty || b.key == _bodega)) {
          filas.add((e, b.key, b.value));
        }
      }
    }
    final paginas = (filas.length / 20).ceil();
    final pagina = paginas == 0 ? 0 : _pagina.clamp(0, paginas - 1);
    final visibles = filas.skip(pagina * 20).take(20);
    return FutureBuilder<Map<String, dynamic>>(
      future: _catalogos ??= widget.service.inventario('catalogos'),
      builder: (context, snap) {
        final clases = {
          for (final c in _lista(snap.data?['clasificaciones']))
            _texto(c, 'id'): _texto(c, 'nombre'),
        };
        String clasificacion(EquipoMantenimiento e) =>
            clases[_texto(e.datos, 'clasificacionId')] ??
            (_texto(e.datos, 'clasificacion').isEmpty
                ? 'Sin clasificación'
                : _texto(e.datos, 'clasificacion'));
        return LayoutBuilder(
          builder: (context, espacio) {
            final tabla =
                widget.vistaWeb &&
                espacio.maxWidth >= 830 &&
                MediaQuery.textScalerOf(context).scale(16) <= 26;
            return ListView(
              padding: EdgeInsets.all(tabla ? 24 : 16),
              children: [
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Inventario de equipos',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await _abrir(
                          _ClasificacionesEquipos(
                            service: widget.service,
                            vistaWeb: widget.vistaWeb,
                          ),
                        );
                        if (mounted) {
                          setState(() {
                            _catalogos = widget.service.inventario('catalogos');
                          });
                        }
                      },
                      icon: const Icon(Icons.category_outlined),
                      label: const Text('Clasificaciones'),
                    ),
                    FilledButton.icon(
                      onPressed: _alta,
                      icon: const Icon(Icons.add),
                      label: const Text('Registrar equipo'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                PanelMantenimiento(
                  child: Wrap(
                    runSpacing: 10,
                    spacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: tabla ? 210 : double.infinity,
                        child: campoMantenimiento(
                          'Rótulo o nombre',
                          120,
                          onChanged: (v) => setState(() {
                            _buscar = v;
                            _pagina = 0;
                          }),
                        ),
                      ),
                      SizedBox(
                        width: tabla ? 230 : double.infinity,
                        child: _selector(
                          'Establecimiento o bodega',
                          _bodega,
                          {'': 'Todas las bodegas', ...bodegas},
                          (v) => setState(() {
                            _bodega = v;
                            _pagina = 0;
                          }),
                        ),
                      ),
                      SizedBox(
                        width: tabla ? 170 : double.infinity,
                        child: _selector(
                          'Categoría',
                          _categoria,
                          const {
                            '': 'Todas',
                            'equipo': 'Equipo',
                            'fungible': 'Fungible',
                          },
                          (v) => setState(() {
                            _categoria = v;
                            _pagina = 0;
                          }),
                        ),
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.event_outlined),
                        label: Text(
                          _ingreso.isEmpty ? 'Fecha de ingreso' : _ingreso,
                        ),
                        onPressed: () async {
                          final fecha = await _elegirFecha(context, _ingreso);
                          if (fecha != null && mounted) {
                            setState(() {
                              _ingreso = fecha;
                              _pagina = 0;
                            });
                          }
                        },
                      ),
                      if (_ingreso.isNotEmpty)
                        IconButton(
                          tooltip: 'Quitar fecha',
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() {
                            _ingreso = '';
                            _pagina = 0;
                          }),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (filas.isEmpty)
                  const PanelMantenimiento(
                    child: Text('No hay existencias con estos filtros.'),
                  )
                else if (tabla)
                  PanelMantenimiento(
                    padding: EdgeInsets.zero,
                    child: Table(
                      columnWidths: const {
                        0: FlexColumnWidth(1.2),
                        1: FlexColumnWidth(2),
                        2: FixedColumnWidth(170),
                        3: FlexColumnWidth(1.6),
                        4: FixedColumnWidth(118),
                        5: FlexColumnWidth(2.3),
                      },
                      defaultVerticalAlignment:
                          TableCellVerticalAlignment.middle,
                      border: const TableBorder(
                        horizontalInside: BorderSide(color: mantenimientoBorde),
                      ),
                      children: [
                        TableRow(
                          decoration: const BoxDecoration(
                            color: Color(0xFFE6F5F2),
                          ),
                          children: [
                            for (final t in [
                              'Rótulo',
                              'Nombre',
                              'Clasificación',
                              'Bodega',
                              'Cantidad',
                              'Acciones',
                            ])
                              _celda(
                                Text(
                                  t,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        for (final (e, b, n) in visibles)
                          TableRow(
                            children: [
                              _celda(Text(e.codigo)),
                              _celda(Text(e.nombre)),
                              _celda(Text(clasificacion(e))),
                              _celda(
                                Text(
                                  bodegas[b] ??
                                      (b.isEmpty ? 'Sin existencias' : b),
                                ),
                              ),
                              _celda(Text('$n')),
                              _acciones(e, b, n),
                            ],
                          ),
                      ],
                    ),
                  )
                else
                  for (final (e, b, n) in visibles)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: PanelMantenimiento(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              e.nombre,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(e.codigo),
                            Text('Clasificación: ${clasificacion(e)}'),
                            Text(
                              '${bodegas[b] ?? (b.isEmpty ? 'Sin existencias' : b)} · $n unidades',
                            ),
                            _acciones(e, b, n),
                          ],
                        ),
                      ),
                    ),
                if (paginas > 1)
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      IconButton(
                        tooltip: 'Anterior',
                        onPressed: pagina <= 0
                            ? null
                            : () => setState(() => _pagina = pagina - 1),
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Text('${pagina + 1} de $paginas'),
                      IconButton(
                        tooltip: 'Siguiente',
                        onPressed: pagina + 1 >= paginas
                            ? null
                            : () => setState(() => _pagina = pagina + 1),
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

String _estadoPlan(Map datos, String centro) {
  final plan = _lista(
    datos['minimos'],
  ).where((p) => p['centroDocId'] == centro).firstOrNull;
  if (plan == null || plan['ppl'] == 0) return 'Pendiente de configurar';
  return '${plan['ppl']} PPL · ${plan['validado'] == true ? 'Validado' : 'Pendiente de validar'}';
}

Widget _celda(Widget hijo) =>
    Padding(padding: const EdgeInsets.all(10), child: hijo);

Widget _selector(
  String label,
  String valor,
  Map<String, String> items,
  ValueChanged<String>? cambiar, {
  bool requerido = false,
}) => DropdownButtonFormField<String>(
  initialValue: items.containsKey(valor) ? valor : null,
  isExpanded: true,
  decoration: InputDecoration(labelText: requerido ? '$label *' : label),
  items: [
    for (final item in items.entries) opcionMantenimiento(item.key, item.value),
  ],
  validator: requerido
      ? (v) => v == null || v.isEmpty ? 'Selecciona una opción' : null
      : null,
  onChanged: cambiar == null ? null : (v) => cambiar(v ?? ''),
);

Future<String?> _elegirFecha(BuildContext context, String actual) async {
  final hoy = DateTime.now();
  final fecha = await showDatePicker(
    context: context,
    firstDate: DateTime(1900),
    lastDate: DateTime(hoy.year + 1, 12, 31),
    initialDate: DateTime.tryParse(actual) ?? hoy,
  );
  return fecha == null ? null : _fecha(fecha);
}

Widget _entero(
  String label,
  String inicial,
  ValueChanged<String> cambiar, {
  int minimo = 0,
  int maximo = 1000000,
}) => TextFormField(
  initialValue: inicial,
  decoration: InputDecoration(labelText: label),
  keyboardType: TextInputType.number,
  inputFormatters: [
    FilteringTextInputFormatter.digitsOnly,
    LengthLimitingTextInputFormatter(7),
  ],
  validator: (v) {
    final n = int.tryParse(v ?? '');
    return n == null || n < minimo || n > maximo
        ? 'Ingresa un valor entre $minimo y $maximo'
        : null;
  },
  onChanged: cambiar,
);

class _ConCatalogos extends StatelessWidget {
  const _ConCatalogos({
    required this.futuro,
    required this.titulo,
    required this.builder,
  });
  final Future<Map<String, dynamic>> futuro;
  final String titulo;
  final Widget Function(Map<String, dynamic>) builder;

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: futuro,
    builder: (context, snap) => snap.hasData
        ? builder(snap.data!)
        : Scaffold(
            appBar: AppBar(title: Text(titulo)),
            body: Center(
              child: snap.hasError
                  ? const Text(
                      'No se pudieron cargar los catálogos. Vuelve a intentarlo.',
                    )
                  : const CircularProgressIndicator(),
            ),
          ),
  );
}

class _Adjunto {
  _Adjunto(this.clase, this.archivo, this.mime) : id = nuevoIdMantenimiento();
  final String id, clase, mime;
  final PlatformFile archivo;

  Future<void> subir(MantenimientoService service) async =>
      service.inventario('subirArchivo', {
        'archivoId': id,
        'clase': clase,
        'nombre': archivo.name,
        'mime': mime,
        'base64': base64Encode(archivo.bytes!),
      });
}

const _formatos = {
  'pdf': 'application/pdf',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'mp4': 'video/mp4',
  'mov': 'video/quicktime',
};

Widget _archivoCampo(
  BuildContext context,
  String label,
  String clase,
  List<String> extensiones,
  _Adjunto? actual,
  ValueChanged<_Adjunto?> cambiar, {
  bool camara = false,
}) {
  void aviso(String mensaje) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(mensaje)));
    }
  }

  Future<void> capturar() async {
    try {
      final picker = ImagePicker();
      final captura = clase == 'video'
          ? await picker.pickVideo(
              source: ImageSource.camera,
              maxDuration: const Duration(seconds: 10),
            )
          : await picker.pickImage(
              source: ImageSource.camera,
              maxWidth: 1600,
              maxHeight: 1600,
              imageQuality: 78,
            );
      if (captura == null || !context.mounted) return;
      final peso = await captura.length();
      final mime = _formatos[captura.name.split('.').last.toLowerCase()];
      if (peso > 5 * 1024 * 1024 || mime == null) {
        aviso('Adjunta una captura compatible de hasta 5 MB.');
        return;
      }
      final bytes = await captura.readAsBytes();
      if (context.mounted) {
        cambiar(
          _Adjunto(
            clase,
            PlatformFile(name: captura.name, size: peso, bytes: bytes),
            mime,
          ),
        );
      }
    } catch (_) {
      aviso(
        'No se pudo abrir la cámara. Revisa los permisos o adjunta un archivo.',
      );
    }
  }

  return Wrap(
    spacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      OutlinedButton.icon(
        icon: const Icon(Icons.attach_file),
        label: Text(actual?.archivo.name ?? label),
        onPressed: () async {
          final seleccion = await FilePicker.platform.pickFiles(
            type: FileType.custom,
            allowedExtensions: extensiones,
            withData: true,
          );
          final archivo = seleccion?.files.single;
          if (archivo == null || !context.mounted) return;
          final mime = _formatos[archivo.extension?.toLowerCase()];
          if (mime == null ||
              archivo.size > 5 * 1024 * 1024 ||
              archivo.bytes == null) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Elige un archivo válido de hasta 5 MB.'),
              ),
            );
            return;
          }
          cambiar(_Adjunto(clase, archivo, mime));
        },
      ),
      if (actual != null)
        IconButton(
          tooltip: 'Quitar adjunto',
          onPressed: () => cambiar(null),
          icon: const Icon(Icons.close),
        ),
      if (camara)
        OutlinedButton.icon(
          onPressed: capturar,
          icon: Icon(
            clase == 'video'
                ? Icons.videocam_outlined
                : Icons.camera_alt_outlined,
          ),
          label: Text(clase == 'video' ? 'Grabar video' : 'Tomar foto'),
        ),
    ],
  );
}

Map<String, String> _familias(Map catalogos) => {
  for (final f in _lista(catalogos['familias']))
    _texto(f, 'id'): _texto(f, 'nombre'),
  for (final plan in _lista(catalogos['minimos']))
    ...Map<String, String>.from(plan['locales'] as Map? ?? const {}),
};

Map<String, String> _familiasSede(Map catalogos, String sede) => {
  for (final f in _lista(catalogos['familias']))
    _texto(f, 'id'): _texto(f, 'nombre'),
  for (final p in _lista(
    catalogos['minimos'],
  ).where((p) => p['centroDocId'] == sede))
    ...Map<String, String>.from(p['locales'] as Map? ?? const {}),
};

class _AltaEquipo extends StatefulWidget {
  const _AltaEquipo({
    required this.service,
    required this.catalogos,
    required this.vistaWeb,
    this.equipo,
  });
  final MantenimientoService service;
  final Map<String, dynamic> catalogos;
  final bool vistaWeb;
  final EquipoMantenimiento? equipo;

  @override
  State<_AltaEquipo> createState() => _AltaEquipoState();
}

class _AltaEquipoState extends State<_AltaEquipo> {
  final _solicitud = nuevoIdMantenimiento();
  late final _datos = <String, dynamic>{
    if (widget.equipo case final e?)
      for (final campo in [
        'codigo',
        'nombre',
        'referencia',
        'descripcion',
        'serie',
        'factura',
        'clasificacionId',
      ])
        campo: _texto(e.datos, campo),
    if (widget.equipo != null) 'equipoId': widget.equipo!.id,
    'categoria': 'equipo',
    'propiedad': 'propio',
    'fechaIngreso': _fecha(DateTime.now()),
    'grupo': false,
    'solicitudId': _solicitud,
  };
  _Adjunto? _pdf, _foto;
  String _cantidad = '1';

  Widget _campo(
    String label,
    String clave,
    int max, {
    bool requerido = false,
    int lineas = 1,
  }) => campoMantenimiento(
    label,
    max,
    initialValue: _texto(_datos, clave),
    requerido: requerido,
    lineas: lineas,
    onChanged: (v) => setState(() => _datos[clave] = v),
  );

  Widget _fechaCampo(String label, String clave) => OutlinedButton.icon(
    icon: const Icon(Icons.event_outlined),
    label: Text(
      [label, _texto(_datos, clave)].where((s) => s.isNotEmpty).join(' · '),
    ),
    onPressed: () async {
      final fecha = await _elegirFecha(context, _texto(_datos, clave));
      if (fecha != null && mounted) setState(() => _datos[clave] = fecha);
    },
  );

  Future<void> _guardar() async {
    if (_pdf == null) throw StateError('Adjunta la ficha técnica en PDF.');
    final adjuntos = [_pdf!, ?_foto];
    for (final archivo in adjuntos) {
      await archivo.subir(widget.service);
    }
    await widget.service.inventario('alta', {
      ..._datos,
      'cantidad': int.tryParse(_cantidad) ?? 1,
      'archivos': adjuntos.map((a) => a.id).toList(),
    });
  }

  @override
  Widget build(BuildContext context) => EditorMantenimiento(
    titulo: 'Registrar equipo',
    etiqueta: 'Ingresar a bodega temporal',
    vistaWeb: widget.vistaWeb,
    guardar: _guardar,
    campos: [
      if (widget.equipo == null)
        const InputDecorator(
          decoration: InputDecoration(labelText: 'Rótulo *'),
          child: Text('Se genera automáticamente al guardar'),
        )
      else
        Text('Rótulo ${widget.equipo!.codigo}'),
      _campo('Nombre', 'nombre', 120, requerido: true),
      _campo('Descripción', 'descripcion', 1200, lineas: 2),
      _campo('Serial', 'serie', 100),
      _campo('Factura', 'factura', 160),
      TextFormField(
        decoration: InputDecoration(
          labelText: _texto(_datos, 'factura').trim().isEmpty
              ? 'Precio de compra (COP)'
              : 'Precio de compra (COP) *',
        ),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [LengthLimitingTextInputFormatter(16)],
        validator: (v) {
          if ((v ?? '').trim().isEmpty) {
            return _texto(_datos, 'factura').trim().isEmpty
                ? null
                : 'Obligatorio cuando hay factura';
          }
          final n = double.tryParse(v!.replaceAll(',', '.'));
          return n == null ||
                  !n.isFinite ||
                  n <= 0 ||
                  n > 1000000000000 ||
                  (n * 100 - (n * 100).round()).abs() > .001
              ? 'Ingresa un precio positivo con hasta dos decimales'
              : null;
        },
        onChanged: (v) => _datos['precioCompra'] = v.trim().isEmpty
            ? null
            : double.tryParse(v.replaceAll(',', '.')),
      ),
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'equipo', label: Text('Equipo')),
          ButtonSegment(value: 'fungible', label: Text('Fungible')),
        ],
        selected: {_texto(_datos, 'categoria')},
        onSelectionChanged: (v) =>
            setState(() => _datos['categoria'] = v.single),
      ),
      _selector(
        'Clasificación',
        _texto(_datos, 'clasificacionId'),
        {
          '': 'Sin clasificación',
          for (final c in _lista(
            widget.catalogos['clasificaciones'],
          ).where((c) => c['activo'] != false))
            _texto(c, 'id'): '${c['codigo']} · ${c['nombre']}',
        },
        (v) => _datos['clasificacionId'] = v,
      ),
      const Text(
        'El tipo del maestro de mínimos se asocia por establecimiento después del traslado.',
      ),
      _selector('Propiedad *', _texto(_datos, 'propiedad'), const {
        'propio': 'Propio',
        'alquilado': 'Alquilado',
        'tercero': 'De tercero',
        'prestado': 'Prestado',
        'comodato': 'Comodato',
      }, (v) => _datos['propiedad'] = v),
    ],
    soportes: [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Es un grupo de unidades'),
        value: _datos['grupo'] == true,
        onChanged: (v) => setState(() => _datos['grupo'] = v),
      ),
      if (_datos['grupo'] == true)
        _entero(
          'Cantidad de unidades *',
          _cantidad,
          (v) => _cantidad = v,
          minimo: 1,
        ),
      _selector(
        'Proveedor de Compras',
        _texto(_datos, 'proveedorId'),
        {
          '': 'Sin proveedor',
          for (final p in _lista(widget.catalogos['proveedores']))
            _texto(p, 'id'): _texto(p, 'nombre'),
        },
        (v) => _datos['proveedorId'] = v,
      ),
      _fechaCampo('Fecha de compra', 'fechaCompra'),
      _fechaCampo('Fecha de ingreso *', 'fechaIngreso'),
      _archivoCampo(
        context,
        'Ficha técnica en PDF * (máximo 5 MB)',
        'ficha',
        ['pdf'],
        _pdf,
        (v) => setState(() => _pdf = v),
      ),
      _archivoCampo(
        context,
        'Imagen del equipo',
        'foto',
        ['jpg', 'jpeg', 'png'],
        _foto,
        (v) => setState(() => _foto = v),
      ),
    ],
  );
}

class _MovimientoEquipo extends StatefulWidget {
  const _MovimientoEquipo({
    required this.service,
    required this.equipo,
    required this.origen,
    required this.origenNombre,
    required this.destinos,
    required this.baja,
    required this.vistaWeb,
  });

  final MantenimientoService service;
  final EquipoMantenimiento equipo;
  final String origen, origenNombre;
  final Map<String, String> destinos;
  final bool baja, vistaWeb;

  @override
  State<_MovimientoEquipo> createState() => _MovimientoEquipoState();
}

class _MovimientoEquipoState extends State<_MovimientoEquipo> {
  final _solicitud = nuevoIdMantenimiento();
  _Adjunto? _foto, _video;
  String _destino = '', _entrega = '', _recibe = '', _observaciones = '';
  late String _cantidad = widget.baja ? '$saldo' : '1';
  late final _catalogos = widget.service.inventario('catalogos');
  int get saldo => widget.equipo.existencias[widget.origen] ?? 0;

  Future<void> _guardar() async {
    final catalogos = await _catalogos;
    _entrega = _texto(catalogos, 'actor');
    if (_entrega.isEmpty) {
      throw StateError('No se pudo identificar a la persona autenticada.');
    }
    if (!widget.baja && (_recibe.isEmpty || _recibe == _entrega)) {
      throw StateError('Elige una persona diferente de quien entrega.');
    }
    final adjuntos = [?_foto, ?_video];
    if (widget.baja && adjuntos.isEmpty) {
      throw StateError('Adjunta una foto o un video de la baja.');
    }
    for (final archivo in adjuntos) {
      await archivo.subir(widget.service);
    }
    await widget.service.inventario(widget.baja ? 'baja' : 'traslado', {
      'solicitudId': _solicitud,
      'equipoId': widget.equipo.id,
      'origen': widget.origen,
      'destino': _destino,
      'cantidad': int.parse(_cantidad),
      'entregaId': _entrega,
      'recibeId': _recibe,
      'observaciones': _observaciones,
      'archivos': adjuntos.map((a) => a.id).toList(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final navegador = Navigator.of(context);
    return EditorMantenimiento(
      titulo: widget.baja ? 'Dar de baja' : 'Trasladar equipo',
      etiqueta: widget.baja ? 'Confirmar baja' : 'Registrar traslado',
      vistaWeb: widget.vistaWeb,
      guardar: _guardar,
      alGuardar: () => navegador.push(
        MaterialPageRoute<void>(
          builder: (_) => _FichaEquipo(
            service: widget.service,
            equipo: widget.equipo,
            movimiento: _solicitud,
          ),
        ),
      ),
      campos: [
        Text(
          widget.equipo.nombre,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        Text('Rótulo: ${widget.equipo.codigo}'),
        if (_texto(widget.equipo.datos, 'referencia').isNotEmpty)
          Text('Referencia ${_texto(widget.equipo.datos, 'referencia')}'),
        Text('Descripción: ${_texto(widget.equipo.datos, 'descripcion')}'),
        Text('Bodega seleccionada: ${widget.origenNombre}'),
        Text('Unidades en bodega: $saldo'),
        _entero(
          'Unidades *',
          _cantidad,
          (v) => setState(() => _cantidad = v),
          minimo: 1,
          maximo: saldo,
        ),
        InputDecorator(
          decoration: const InputDecoration(
            labelText: 'Saldo en bodega después del movimiento',
          ),
          child: Text(
            int.tryParse(_cantidad) == null || int.parse(_cantidad) > saldo
                ? 'Revisa las unidades'
                : '${saldo - int.parse(_cantidad)}',
          ),
        ),
        if (!widget.baja)
          _selector(
            'Bodega o sede de destino',
            _destino,
            {'': 'Selecciona', ...widget.destinos},
            (v) => setState(() => _destino = v),
            requerido: true,
          ),
        if (_destino.isNotEmpty || widget.baja)
          FutureBuilder(
            future: _catalogos,
            builder: (context, snap) {
              final sede = widget.baja ? widget.origen : _destino;
              final plan = _lista(
                snap.data?['minimos'],
              ).where((p) => p['centroDocId'] == sede).firstOrNull;
              if (sede == bodegaTemporalMantenimiento) {
                return const Text(
                  'Obligatoriedad no aplica en bodega temporal.',
                );
              }
              final tipo = widget.equipo.tipoEnSede(sede);
              if (tipo.isEmpty) {
                return const Text(
                  'Este equipo no está asociado al maestro de mínimos.',
                );
              }
              if (plan?['validado'] != true) {
                return const Text(
                  'La sede tiene mínimos pendientes de validar.',
                );
              }
              final minimo = (plan?['cantidades'] as Map?)?[tipo] as int? ?? 0;
              return Text(
                minimo > 0
                    ? widget.baja
                          ? 'Equipo obligatorio. La baja asignará una tarea de reemplazo al coordinador.'
                          : 'Equipo obligatorio en el destino.'
                    : 'Equipo sin mínimo obligatorio en esta sede.',
              );
            },
          ),
        FutureBuilder(
          future: _catalogos,
          builder: (context, snap) {
            if (snap.hasError) {
              return const Text(
                'No se pudo cargar el personal. Vuelve a abrir el formulario.',
              );
            }
            if (!snap.hasData) return const LinearProgressIndicator();
            final actor = _texto(snap.data!, 'actor');
            final persona = _lista(
              snap.data!['personal'],
            ).where((p) => p['id'] == actor).firstOrNull;
            return InputDecorator(
              decoration: InputDecoration(
                labelText: widget.baja
                    ? 'Responsable de la baja'
                    : 'Quién entrega (sesión actual)',
              ),
              child: Text(
                persona == null
                    ? 'Persona autenticada'
                    : [persona['nombre'], persona['cargo'], persona['area']]
                          .whereType<String>()
                          .where((s) => s.isNotEmpty)
                          .join(' · '),
              ),
            );
          },
        ),
        if (!widget.baja)
          FutureBuilder(
            future: _catalogos,
            builder: (context, snap) => PersonaMantenimientoField(
              etiqueta: 'Quién recibe',
              catalogo: _catalogos,
              excluirIds: {_texto(snap.data ?? {}, 'actor')},
              onChanged: (p) => _recibe = p['id'] as String,
            ),
          ),
        campoMantenimiento(
          'Observaciones',
          1200,
          lineas: 3,
          requerido: widget.baja,
          onChanged: (v) => _observaciones = v,
        ),
      ],
      soportes: [
        _ImagenEquipo(
          service: widget.service,
          archivos: _lista(widget.equipo.datos['archivos']),
        ),
        if (widget.baja) ...[
          const Text(
            'Evidencia obligatoria *: adjunta al menos una foto o un video (máximo 5 MB por archivo).',
          ),
          _archivoCampo(
            context,
            'Evidencia fotográfica',
            'foto',
            ['jpg', 'jpeg', 'png'],
            _foto,
            (v) => setState(() => _foto = v),
            camara: !widget.vistaWeb,
          ),
          _archivoCampo(
            context,
            'Video de la baja',
            'video',
            ['mp4', 'mov'],
            _video,
            (v) => setState(() => _video = v),
            camara: !widget.vistaWeb,
          ),
        ],
      ],
    );
  }
}

class _FichaEquipo extends StatefulWidget {
  const _FichaEquipo({
    required this.service,
    required this.equipo,
    this.movimiento,
  });
  final MantenimientoService service;
  final EquipoMantenimiento equipo;
  final String? movimiento;

  @override
  State<_FichaEquipo> createState() => _FichaEquipoState();
}

class _FichaEquipoState extends State<_FichaEquipo> {
  late final _historial = widget.service.inventario('historial', {
    'equipoId': widget.equipo.id,
    if (widget.movimiento != null) 'movimientoId': widget.movimiento,
  });
  bool _ocupado = false;

  Future<void> _procesar(Future<void> Function() accion) async {
    setState(() => _ocupado = true);
    try {
      await accion();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo abrir el documento.')),
        );
      }
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Widget _adjunto(Map a) => OutlinedButton.icon(
    icon: const Icon(Icons.attachment),
    label: Text(_texto(a, 'nombre')),
    onPressed: _ocupado
        ? null
        : () => _procesar(() async {
            final caja = context.findRenderObject() as RenderBox?;
            final area = caja == null
                ? null
                : caja.localToGlobal(Offset.zero) & caja.size;
            final resultado = await widget.service.inventario('leerArchivo', {
              'archivoId': a['id'],
            });
            final bytes = base64Decode(resultado['base64'] as String);
            if (!mounted) return;
            final mime = _texto(a, 'mime');
            if (mime.startsWith('image/')) {
              await showDialog<void>(
                context: context,
                builder: (context) => Dialog(
                  child: InteractiveViewer(
                    child: Image.memory(bytes, fit: BoxFit.contain),
                  ),
                ),
              );
            } else if (mime == 'application/pdf') {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      _FichaTecnica(bytes: bytes, nombre: _texto(a, 'nombre')),
                ),
              );
            } else {
              await SharePlus.instance.share(
                ShareParams(
                  files: [XFile.fromData(bytes, mimeType: mime)],
                  fileNameOverrides: [_texto(a, 'nombre')],
                  sharePositionOrigin: area,
                ),
              );
            }
          }),
  );

  @override
  Widget build(BuildContext context) {
    final e = widget.equipo;
    return Scaffold(
      appBar: AppBar(title: Text(e.nombre)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (widget.movimiento == null)
              PanelMantenimiento(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.codigo,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    for (final (clave, label) in [
                      ('referencia', 'Referencia'),
                      ('descripcion', 'Descripción'),
                      ('categoria', 'Categoría'),
                      ('clasificacion', 'Clasificación'),
                      ('otraClasificacion', 'Otra clasificación'),
                      ('propiedad', 'Propiedad'),
                      ('serie', 'Serial'),
                      ('factura', 'Factura'),
                      ('precioCompra', 'Precio de compra (COP)'),
                      ('proveedorNombre', 'Proveedor'),
                      ('fechaCompra', 'Compra'),
                      ('fechaIngreso', 'Ingreso'),
                    ])
                      if (_texto(e.datos, clave).isNotEmpty)
                        Text('$label · ${_texto(e.datos, clave)}'),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final a in _lista(e.datos['archivos']))
                          _adjunto(a),
                      ],
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            FutureBuilder(
              future: _historial,
              builder: (context, snap) {
                if (snap.hasError) {
                  return const Text('No se pudo consultar el historial.');
                }
                if (!snap.hasData) return const LinearProgressIndicator();
                final movimientos = _lista(snap.data?['movimientos']).where(
                  (m) =>
                      widget.movimiento == null || m['id'] == widget.movimiento,
                );
                if (movimientos.isEmpty) {
                  return const Text('Sin movimientos registrados.');
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final m in movimientos)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: PanelMantenimiento(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${m['accion'] == 'traslado' ? 'Traslado' : 'Baja'} · ${m['unidades']} unidades',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Text('Acta: ${codigoActaEquipo(m)}'),
                              Text(
                                '${_fechaMovimiento(m)} · ${m['origenNombre']}${m['accion'] == 'traslado' ? ' → ${m['destinoNombre']}' : ''}',
                              ),
                              if (_texto(m, 'observaciones').isNotEmpty)
                                Text(_texto(m, 'observaciones')),
                              if (_texto(m, 'tareaId').isNotEmpty)
                                const Text(
                                  'Tarea de reemplazo asignada al coordinador.',
                                ),
                              Wrap(
                                spacing: 8,
                                children: [
                                  for (final a in _lista(m['archivos']))
                                    _adjunto(a),
                                  OutlinedButton.icon(
                                    onPressed: _ocupado
                                        ? null
                                        : () => _procesar(() async {
                                            final foto = await _fotoActa(
                                              widget.service,
                                              m,
                                              e,
                                            );
                                            final marca =
                                                await marcaMantenimiento(
                                                  widget.service.empresaId,
                                                );
                                            final bytes =
                                                await generarActaEquipo(
                                                  m,
                                                  widget.service.empresaId,
                                                  foto: foto,
                                                  empresaNombre: marca.nombre,
                                                  empresaLogo: marca.logo,
                                                );
                                            if (context.mounted) {
                                              await _verPdf(
                                                context,
                                                bytes,
                                                nombreActaEquipo(m),
                                              );
                                            }
                                          }),
                                    icon: const Icon(
                                      Icons.picture_as_pdf_outlined,
                                    ),
                                    label: Text(
                                      m['accion'] == 'traslado'
                                          ? 'Ver acta de traslado'
                                          : 'Ver acta de baja',
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

String _fechaMovimiento(Map m) => DateFormat(
  'dd/MM/yyyy HH:mm',
).format(DateTime.fromMillisecondsSinceEpoch((m['fecha'] as num).toInt()));

String codigoActaEquipo(Map m) => _texto(m, 'actaCodigo').isNotEmpty
    ? _texto(m, 'actaCodigo')
    : '${m['accion'] == 'baja' ? 'BA' : 'TR'}-${m['codigo']}-${_texto(m, 'id')}';

String nombreActaEquipo(Map m) {
  final nombre = '${m['nombre']}'.replaceAll(
    RegExp(r'[^a-zA-Z0-9áéíóúÁÉÍÓÚñÑ]+'),
    '_',
  );
  return 'acta_${m['accion'] == 'baja' ? 'baja' : 'traslado'}_${codigoActaEquipo(m).replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}_${nombre.substring(0, nombre.length.clamp(0, 60))}.pdf';
}

Future<Uint8List?> _fotoActa(
  MantenimientoService service,
  Map m,
  EquipoMantenimiento e,
) async {
  final fotos = _lista(m['fotosEquipo']).isNotEmpty
      ? _lista(m['fotosEquipo'])
      : _lista(e.datos['archivos']).where((a) => a['clase'] == 'foto').toList();
  if (fotos.isEmpty) return null;
  final datos = await service.inventario('leerArchivo', {
    'archivoId': fotos.first['id'],
  });
  return base64Decode(datos['base64'] as String);
}

Future<Uint8List> generarActaEquipo(
  Map m,
  String empresaId, {
  Uint8List? foto,
  String empresaNombre = '',
  Uint8List? empresaLogo,
}) async {
  final fuente = pw.Font.ttf(await rootBundle.load('assets/arial.ttf'));
  final baja = m['accion'] == 'baja';
  final titulo = baja ? 'ACTA DE BAJA' : 'ACTA DE TRASLADO DE EQUIPOS';
  final documento = pw.Document(title: titulo);
  final membrete = membreteMantenimiento(
    titulo,
    nombre: empresaNombre.isEmpty ? empresaId : empresaNombre,
    logo: empresaLogo,
  );
  pw.Widget ficha(String titulo, Map<String, String> datos) => pw.Inseparable(
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(height: 14),
        pw.Text(
          titulo,
          style: const pw.TextStyle(fontSize: 13, color: PdfColors.teal900),
        ),
        pw.SizedBox(height: 5),
        pw.TableHelper.fromTextArray(
          headerCount: 0,
          data: datos.entries
              .map(
                (e) => [
                  e.key,
                  e.value.isEmpty
                      ? '—'
                      : e.value.replaceAll(RegExp(r'\s+'), ' ').trim(),
                ],
              )
              .toList(),
          columnWidths: {
            0: const pw.FlexColumnWidth(1),
            1: const pw.FlexColumnWidth(3),
          },
          cellPadding: const pw.EdgeInsets.all(7),
          oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
          border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
        ),
      ],
    ),
  );
  documento.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      theme: pw.ThemeData.withFont(base: fuente, bold: fuente),
      header: (_) => membrete,
      footer: (context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('${context.pageNumber} / ${context.pagesCount}'),
      ),
      build: (_) => [
        ficha('Movimiento', {
          'Código del acta': codigoActaEquipo(m),
          'Fecha': _fechaMovimiento(m),
          'Bodega de origen': _texto(m, 'origenNombre'),
          if (!baja) 'Destino': _texto(m, 'destinoNombre'),
        }),
        ficha(baja ? 'Equipo dado de baja' : 'Equipo trasladado', {
          'Rótulo': _texto(m, 'codigo'),
          'Equipo': _texto(m, 'nombre'),
          'Referencia': _texto(m, 'referencia'),
          'Descripción': _texto(m, 'descripcion'),
          'Unidades': _texto(m, 'unidades'),
          if (m['saldoAnterior'] != null)
            'Saldo anterior': _texto(m, 'saldoAnterior'),
          if (m['saldoPosterior'] != null)
            'Saldo posterior': _texto(m, 'saldoPosterior'),
          'Obligatorio en la sede': m['obligatorio'] == null
              ? 'Sin validar'
              : m['obligatorio'] == true
              ? 'Sí'
              : 'No',
        }),
        if (foto != null) ...[
          pw.SizedBox(height: 12),
          pw.Center(
            child: pw.Image(
              pw.MemoryImage(foto),
              width: 220,
              height: 150,
              fit: pw.BoxFit.contain,
            ),
          ),
        ],
        ficha(baja ? 'Responsable de la baja' : 'Entrega y recepción', {
          baja ? 'Responsable' : 'Entregó': _texto(m, 'entrega'),
          if (m['entregaPersona'] is Map)
            'Cargo / departamento de entrega':
                '${m['entregaPersona']['cargo']} / ${m['entregaPersona']['area']}',
          if (!baja) 'Recibió': _texto(m, 'recibe'),
          if (!baja && m['recibePersona'] is Map)
            'Cargo / departamento de recepción':
                '${m['recibePersona']['cargo']} / ${m['recibePersona']['area']}',
        }),
        if (_texto(m, 'observaciones').isNotEmpty) ...[
          pw.SizedBox(height: 14),
          pw.Text(
            'Observaciones',
            style: const pw.TextStyle(fontSize: 13, color: PdfColors.teal900),
          ),
          pw.Paragraph(text: _texto(m, 'observaciones')),
        ],
      ],
    ),
  );
  return documento.save();
}

Future<void> _verPdf(BuildContext context, Uint8List bytes, String nombre) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Documento PDF')),
          body: SafeArea(
            child: PdfPreview(
              maxPageWidth: 700,
              build: (_) => bytes,
              pdfFileName: nombre,
              canChangePageFormat: false,
              canChangeOrientation: false,
              canDebug: false,
            ),
          ),
        ),
      ),
    );

class _ImagenEquipo extends StatefulWidget {
  const _ImagenEquipo({required this.service, required this.archivos});
  final MantenimientoService service;
  final List<Map<String, dynamic>> archivos;
  @override
  State<_ImagenEquipo> createState() => _ImagenEquipoState();
}

class _ImagenEquipoState extends State<_ImagenEquipo> {
  late final _foto = widget.archivos
      .where((a) => a['clase'] == 'foto')
      .firstOrNull;
  late final _carga = _foto == null
      ? null
      : widget.service.inventario('leerArchivo', {'archivoId': _foto!['id']});
  @override
  Widget build(BuildContext context) => PanelMantenimiento(
    child: _carga == null
        ? const SizedBox(
            height: 160,
            child: Center(child: Text('Equipo sin fotografía registrada')),
          )
        : FutureBuilder(
            future: _carga,
            builder: (context, snap) => snap.hasError
                ? const Text('No se pudo cargar la fotografía del equipo.')
                : !snap.hasData
                ? const LinearProgressIndicator()
                : Image.memory(
                    base64Decode(snap.data!['base64'] as String),
                    height: 220,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) =>
                        const Text('Fotografía no disponible'),
                  ),
          ),
  );
}

const _metodosDepreciacion = {
  'linea_recta': 'Línea recta',
  'saldo_decreciente': 'Saldo decreciente',
  'unidades_produccion': 'Unidades de producción',
  'no_deprecia': 'No deprecia',
};

class _ClasificacionesEquipos extends StatefulWidget {
  const _ClasificacionesEquipos({
    required this.service,
    required this.vistaWeb,
  });
  final MantenimientoService service;
  final bool vistaWeb;
  @override
  State<_ClasificacionesEquipos> createState() =>
      _ClasificacionesEquiposState();
}

class _ClasificacionesEquiposState extends State<_ClasificacionesEquipos> {
  late Future<Map<String, dynamic>> _catalogos = widget.service.inventario(
    'catalogos',
  );
  Future<void> _editar([Map<String, dynamic>? clase]) async {
    var codigo = _texto(clase ?? {}, 'codigo');
    var nombre = _texto(clase ?? {}, 'nombre');
    var metodo = _texto(clase ?? {}, 'metodoDepreciacion');
    var activo = clase?['activo'] != false;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StatefulBuilder(
          builder: (context, cambiar) => EditorMantenimiento(
            titulo: clase == null
                ? 'Nueva clasificación'
                : 'Editar clasificación',
            vistaWeb: widget.vistaWeb,
            guardar: () async {
              await widget.service.inventario('clasificacion', {
                if (clase != null) 'clasificacionId': clase['id'],
                'codigo': codigo,
                'nombre': nombre,
                'metodoDepreciacion': metodo,
                'activo': activo,
              });
            },
            campos: [
              if (clase == null)
                campoMantenimiento(
                  'Código',
                  40,
                  requerido: true,
                  onChanged: (v) => codigo = v,
                )
              else
                Text('Código: $codigo'),
              campoMantenimiento(
                'Nombre',
                120,
                initialValue: nombre,
                requerido: true,
                onChanged: (v) => nombre = v,
              ),
              _selector(
                'Método de depreciación',
                metodo,
                {'': 'Selecciona', ..._metodosDepreciacion},
                (v) => metodo = v,
                requerido: true,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Activa'),
                value: activo,
                onChanged: (v) => cambiar(() => activo = v),
              ),
            ],
          ),
        ),
      ),
    );
    if (mounted) {
      setState(() {
        _catalogos = widget.service.inventario('catalogos');
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Clasificaciones de equipos')),
    body: SafeArea(
      child: FutureBuilder(
        future: _catalogos,
        builder: (context, snap) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: _editar,
                icon: const Icon(Icons.add),
                label: const Text('Nueva clasificación'),
              ),
            ),
            const SizedBox(height: 16),
            if (snap.hasError)
              OutlinedButton(
                onPressed: () => setState(() {
                  _catalogos = widget.service.inventario('catalogos');
                }),
                child: const Text('Reintentar'),
              )
            else if (!snap.hasData)
              const LinearProgressIndicator()
            else if (_lista(snap.data!['clasificaciones']).isEmpty)
              const Text(
                'No hay clasificaciones. Crea la primera para asignarla a los equipos.',
              )
            else
              for (final c in _lista(snap.data!['clasificaciones']))
                PanelMantenimiento(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${c['codigo']} · ${c['nombre']}'),
                    subtitle: Text(
                      '${_metodosDepreciacion[c['metodoDepreciacion']] ?? c['metodoDepreciacion']} · ${c['activo'] == false ? 'Inactiva' : 'Activa'}',
                    ),
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: () => _editar(c),
                  ),
                ),
          ],
        ),
      ),
    ),
  );
}

class ConsultaMovimientosMantenimiento extends StatefulWidget {
  const ConsultaMovimientosMantenimiento({
    super.key,
    required this.service,
    required this.equipos,
    required this.vistaWeb,
    this.bajas = false,
  });
  final MantenimientoService service;
  final List<EquipoMantenimiento> equipos;
  final bool vistaWeb, bajas;
  @override
  State<ConsultaMovimientosMantenimiento> createState() =>
      _ConsultaMovimientosMantenimientoState();
}

class _ConsultaMovimientosMantenimientoState
    extends State<ConsultaMovimientosMantenimiento> {
  final _registros = <Map<String, dynamic>>[];
  String _cursor = '', _buscar = '', _origen = '', _destino = '';
  DateTimeRange? _periodo;
  bool _cargando = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar({bool reiniciar = false}) async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final datos = await widget.service.inventario('movimientos', {
        'clase': widget.bajas ? 'baja' : 'traslado',
        if (!reiniciar && _cursor.isNotEmpty) 'cursor': _cursor,
      });
      if (!mounted) return;
      setState(() {
        if (reiniciar) _registros.clear();
        _registros.addAll(_lista(datos['movimientos']));
        _cursor = _texto(datos, 'cursor');
      });
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is StateError
              ? e.message
              : 'No se pudieron cargar los movimientos.',
        );
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _abrir(Map<String, dynamic> m) {
    final equipo =
        widget.equipos.where((e) => e.id == m['equipoId']).firstOrNull ??
        EquipoMantenimiento(
          _texto(m, 'equipoId'),
          Map<String, dynamic>.from(m),
        );
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _FichaEquipo(
          service: widget.service,
          equipo: equipo,
          movimiento: _texto(m, 'id'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, espacio) {
      final tabla =
          widget.vistaWeb &&
          espacio.maxWidth >= 830 &&
          MediaQuery.textScalerOf(context).scale(16) <= 26;
      final origenes = {
        for (final m in _registros)
          _texto(m, 'origen'): _texto(m, 'origenNombre'),
      };
      final destinos = {
        for (final m in _registros)
          _texto(m, 'destino'): _texto(m, 'destinoNombre'),
      };
      final visibles = _registros.where((m) {
        final fecha = DateTime.fromMillisecondsSinceEpoch(
          (m['fecha'] as num).toInt(),
        );
        return '${m['nombre']} ${m['codigo']} ${codigoActaEquipo(m)}'
                .toLowerCase()
                .contains(_buscar.toLowerCase()) &&
            (_origen.isEmpty || m['origen'] == _origen) &&
            (_destino.isEmpty || m['destino'] == _destino) &&
            (_periodo == null ||
                (!fecha.isBefore(_periodo!.start) &&
                    fecha.isBefore(
                      _periodo!.end.add(const Duration(days: 1)),
                    )));
      }).toList();
      return ListView(
        padding: EdgeInsets.all(tabla ? 24 : 16),
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                widget.bajas
                    ? 'Consulta de bajas'
                    : 'Movimientos entre bodegas',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              OutlinedButton.icon(
                onPressed: _cargando ? null : () => _cargar(reiniciar: true),
                icon: const Icon(Icons.refresh),
                label: const Text('Actualizar'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          PanelMantenimiento(
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: tabla ? 230 : double.infinity,
                  child: campoMantenimiento(
                    'Rótulo, equipo o acta',
                    120,
                    onChanged: (v) => setState(() => _buscar = v),
                  ),
                ),
                SizedBox(
                  width: tabla ? 230 : double.infinity,
                  child: _selector('Origen', _origen, {
                    '': 'Todos',
                    ...origenes,
                  }, (v) => setState(() => _origen = v)),
                ),
                if (!widget.bajas)
                  SizedBox(
                    width: tabla ? 230 : double.infinity,
                    child: _selector('Destino', _destino, {
                      '': 'Todos',
                      ...destinos,
                    }, (v) => setState(() => _destino = v)),
                  ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.date_range),
                  label: Text(
                    _periodo == null
                        ? 'Fecha del movimiento'
                        : '${_fecha(_periodo!.start)} / ${_fecha(_periodo!.end)}',
                  ),
                  onPressed: () async {
                    final periodo = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now().add(const Duration(days: 1)),
                      initialDateRange: _periodo,
                    );
                    if (periodo != null && mounted) {
                      setState(() => _periodo = periodo);
                    }
                  },
                ),
                if (_periodo != null)
                  TextButton(
                    onPressed: () => setState(() => _periodo = null),
                    child: const Text('Quitar fechas'),
                  ),
              ],
            ),
          ),
          if (_error != null) Text(_error!),
          if (_cargando) const LinearProgressIndicator(),
          if (!_cargando && visibles.isEmpty)
            const PanelMantenimiento(
              child: Text('No hay movimientos con estos filtros.'),
            ),
          if (tabla && visibles.isNotEmpty)
            PanelMantenimiento(
              child: Table(
                columnWidths: const {
                  0: FlexColumnWidth(1.4),
                  1: FlexColumnWidth(2),
                  2: FlexColumnWidth(2),
                  3: FixedColumnWidth(132),
                  4: FixedColumnWidth(150),
                },
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                children: [
                  TableRow(
                    children: [
                      for (final t in [
                        'Acta / fecha',
                        'Equipo / rótulo',
                        'Movimiento',
                        'Unidades',
                        'Consulta',
                      ])
                        _celda(
                          Text(
                            t,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  ),
                  for (final m in visibles)
                    TableRow(
                      children: [
                        _celda(
                          Text(
                            '${codigoActaEquipo(m)}\n${_fechaMovimiento(m)}',
                          ),
                        ),
                        _celda(Text('${m['nombre']}\n${m['codigo']}')),
                        _celda(
                          Text(
                            '${m['origenNombre']}${widget.bajas ? '' : ' → ${m['destinoNombre']}'}',
                          ),
                        ),
                        _celda(Text('${m['unidades']}')),
                        TextButton(
                          onPressed: () => _abrir(m),
                          child: const Text('Ver acta'),
                        ),
                      ],
                    ),
                ],
              ),
            )
          else
            for (final m in visibles)
              PanelMantenimiento(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${m['nombre']} · ${m['codigo']}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text('${codigoActaEquipo(m)} · ${_fechaMovimiento(m)}'),
                    Text(
                      '${m['origenNombre']}${widget.bajas ? '' : ' → ${m['destinoNombre']}'} · ${m['unidades']} unidades',
                    ),
                    TextButton(
                      onPressed: () => _abrir(m),
                      child: const Text('Ver acta'),
                    ),
                  ],
                ),
              ),
          if (_cursor.isNotEmpty) ...[
            const Text(
              'Los filtros se aplican a los movimientos cargados. Carga más para consultar registros anteriores.',
            ),
            OutlinedButton(
              onPressed: _cargando ? null : _cargar,
              child: const Text('Cargar más movimientos'),
            ),
          ],
          if (_error != null)
            OutlinedButton(
              onPressed: _cargando
                  ? null
                  : () => _cargar(reiniciar: _registros.isEmpty),
              child: const Text('Reintentar'),
            ),
        ],
      );
    },
  );
}

class _FichaTecnica extends StatefulWidget {
  const _FichaTecnica({required this.bytes, required this.nombre});
  final Uint8List bytes;
  final String nombre;

  @override
  State<_FichaTecnica> createState() => _FichaTecnicaState();
}

class _FichaTecnicaState extends State<_FichaTecnica> {
  late final _controlador = pdfx.PdfControllerPinch(
    document: pdfx.PdfDocument.openData(widget.bytes),
  );

  @override
  void dispose() {
    _controlador.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.nombre)),
    body: SafeArea(child: pdfx.PdfViewPinch(controller: _controlador)),
  );
}

class _MinimosSede extends StatefulWidget {
  const _MinimosSede({
    required this.service,
    required this.centro,
    required this.catalogos,
    required this.equipos,
    required this.vistaWeb,
  });
  final MantenimientoService service;
  final EstablecimientoMantenimiento centro;
  final Map<String, dynamic> catalogos;
  final List<EquipoMantenimiento> equipos;
  final bool vistaWeb;

  @override
  State<_MinimosSede> createState() => _MinimosSedeState();
}

class _MinimosSedeState extends State<_MinimosSede> {
  late final _plan =
      _lista(
        widget.catalogos['minimos'],
      ).where((p) => p['centroDocId'] == widget.centro.id).firstOrNull ??
      const <String, dynamic>{};
  late final _personas = {
    '': 'Selecciona una persona',
    for (final p in _lista(widget.catalogos['personas']))
      _texto(p, 'id'): _texto(p, 'nombre'),
  };
  late final _base = {
    for (final f in _lista(widget.catalogos['familias']))
      _texto(f, 'id'): _texto(f, 'nombre'),
  };
  late final _locales = Map<String, String>.from(
    _plan['locales'] as Map? ?? const {},
  );
  late final _minimos = <String, String>{
    for (final entry in (_plan['cantidades'] as Map? ?? const {}).entries)
      entry.key as String: '${entry.value}',
  };
  late final _ppl = TextEditingController(
    text: _plan['ppl'] == null || _plan['ppl'] == 0 ? '' : '${_plan['ppl']}',
  );
  late String _responsable = _texto(_plan, 'responsableId'),
      _coord = _texto(_plan, 'coordinadorId'),
      _nota = _texto(_plan, 'nota');
  late bool _validar = _plan['validado'] == true && _responsable == _actor;
  final _local = TextEditingController();
  Map<String, int> _referencia = {};
  int? _referenciaPpl;
  bool _consultando = false;
  int _revision = 0;
  String? _mensaje;
  String get _actor => _texto(widget.catalogos, 'actor');
  bool get _gestor => widget.catalogos['gestor'] == true;
  bool get _edita => _gestor || _texto(_plan, 'responsableId') == _actor;

  @override
  void dispose() {
    _ppl.dispose();
    _local.dispose();
    super.dispose();
  }

  Future<void> _consultar({bool aplicar = false}) async {
    final ppl = int.tryParse(_ppl.text);
    if (ppl == null || ppl < 1) {
      setState(() => _mensaje = 'Ingresa la cantidad de PPL.');
      return;
    }
    setState(() {
      _consultando = true;
      _mensaje = null;
    });
    try {
      final respuesta = await widget.service.inventario('referenciaAnexo', {
        'ppl': ppl,
      });
      final valores = respuesta['cantidades'] as List;
      if (!mounted) return;
      setState(() {
        _referenciaPpl = ppl;
        _referencia = {
          for (var i = 0; i < valores.length; i++)
            'anexo_$i': (valores[i] as num).toInt(),
        };
        if (valores.isEmpty) {
          _mensaje =
              'El Anexo 5 cubre de 1 a 10.000 PPL. Registra el mínimo validado para esta sede.';
        } else if (aplicar) {
          for (final entrada in _referencia.entries) {
            _minimos[entrada.key] = '${entrada.value}';
          }
          _revision++;
          _validar = false;
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() => _mensaje = 'No se pudo consultar el Anexo 5.');
      }
    } finally {
      if (mounted) setState(() => _consultando = false);
    }
  }

  void _agregarLocal() {
    final nombre = _local.text.trim();
    if (nombre.isEmpty) return;
    final existente = _familias(widget.catalogos).entries
        .where((f) => f.value.toLowerCase() == nombre.toLowerCase())
        .firstOrNull;
    setState(() {
      final id =
          existente?.key ??
          'local_${nuevoIdMantenimiento().replaceAll('-', '').substring(0, 24)}';
      _locales[id] = existente?.value ?? nombre;
      _minimos.putIfAbsent(id, () => '0');
      _local.clear();
    });
  }

  Future<void> _guardar() async {
    final ppl = int.tryParse(_ppl.text);
    if (ppl == null || ppl < 1 || ppl > 1000000) {
      throw StateError('Ingresa una cantidad de PPL válida.');
    }
    final cantidades = <String, int>{};
    for (final entrada in _minimos.entries) {
      final n = int.tryParse(entrada.value);
      if (n == null) throw StateError('Completa las cantidades mínimas.');
      cantidades[entrada.key] = n;
    }
    if (_validar && cantidades.isEmpty) {
      throw StateError('Registra las cantidades que vas a validar.');
    }
    await widget.service.inventario('minimos', {
      'centroDocId': widget.centro.id,
      'ppl': ppl,
      'responsableId': _responsable,
      'coordinadorId': _coord,
      'nota': _nota,
      'validar': _validar,
      'cantidades': cantidades,
      'locales': _locales,
    });
  }

  @override
  Widget build(BuildContext context) {
    final familias = {..._base, ..._locales};
    final actual = <String, int>{};
    for (final e in widget.equipos.where(
      (e) => e.tipoEnSede(widget.centro.id).isNotEmpty,
    )) {
      actual.update(
        e.tipoEnSede(widget.centro.id),
        (n) => n + (e.existencias[widget.centro.id] ?? 0),
        ifAbsent: () => e.existencias[widget.centro.id] ?? 0,
      );
    }
    final filas = familias.entries
        .where(
          (f) =>
              _edita || _minimos.containsKey(f.key) || (actual[f.key] ?? 0) > 0,
        )
        .toList();
    final tabla = widget.vistaWeb && MediaQuery.sizeOf(context).width >= 900;
    Widget cantidades(MapEntry<String, String> f, {required bool compacta}) {
      final n = actual[f.key] ?? 0;
      final minimo = int.tryParse(_minimos[f.key] ?? '');
      final falta = minimo == null ? '—' : '${(minimo - n).clamp(0, 1000000)}';
      final referencia = _referenciaPpl == int.tryParse(_ppl.text)
          ? _referencia[f.key]
          : null;
      return Wrap(
        spacing: 12,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (referencia != null) Text('Anexo $referencia'),
          if (_edita)
            SizedBox(
              width: compacta ? 120 : 134,
              child: KeyedSubtree(
                key: ValueKey((f.key, _revision)),
                child: _entero(
                  'Mínimo',
                  _minimos[f.key] ?? '0',
                  (valor) => setState(() {
                    _minimos[f.key] = valor;
                  }),
                ),
              ),
            )
          else
            Text('Mínimo ${minimo ?? '—'}'),
          Text('Actual $n'),
          Text(
            'Faltante $falta',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      );
    }

    final campos = [
      Text(_estadoPlan(widget.catalogos, widget.centro.id)),
      TextFormField(
        controller: _ppl,
        enabled: _edita,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(7),
        ],
        decoration: const InputDecoration(labelText: 'Cantidad de PPL'),
        onChanged: (_) => setState(() {}),
      ),
      _selector(
        'Responsable de validar por la sede',
        _responsable,
        _personas,
        _gestor
            ? (v) => setState(() {
                _responsable = v;
                _validar = false;
              })
            : null,
        requerido: _edita,
      ),
      _selector(
        'Coordinador para las tareas de reemplazo',
        _coord,
        _personas,
        _gestor ? (v) => _coord = v : null,
        requerido: _edita,
      ),
      if (_edita)
        campoMantenimiento(
          'Observaciones de infraestructura y preparaciones',
          1200,
          lineas: 3,
          initialValue: _nota,
          onChanged: (v) => _nota = v,
        )
      else if (_nota.isNotEmpty)
        Text(_nota),
      Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          OutlinedButton(
            onPressed: _consultando ? null : _consultar,
            child: const Text('Consultar Anexo 5'),
          ),
          if (_edita)
            OutlinedButton(
              onPressed: _consultando
                  ? null
                  : () async {
                      final aplicar =
                          _minimos.isEmpty ||
                          await showDialog<bool>(
                                context: context,
                                builder: (c) => AlertDialog(
                                  title: const Text(
                                    'Aplicar cantidades del Anexo 5',
                                  ),
                                  content: const Text(
                                    'Las cantidades descargadas reemplazarán los valores de las filas del Anexo en este formulario.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(c, false),
                                      child: const Text('Cancelar'),
                                    ),
                                    FilledButton(
                                      onPressed: () => Navigator.pop(c, true),
                                      child: const Text('Aplicar'),
                                    ),
                                  ],
                                ),
                              ) ==
                              true;
                      if (aplicar && mounted) await _consultar(aplicar: true);
                    },
              child: const Text('Cargar referencia del Anexo'),
            ),
        ],
      ),
      if (_mensaje != null) Text(_mensaje!),
      const Text(
        'Valida los mínimos según infraestructura y preparaciones. La tabla y la nota sobre hidrolavadoras traen cantidades distintas.',
      ),
      if (_edita && _responsable == _actor)
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Validar mínimos de esta sede'),
          value: _validar,
          onChanged: (v) => setState(() => _validar = v),
        ),
      if (_edita)
        Row(
          children: [
            Expanded(
              child: campoMantenimiento(
                'Equipo local',
                120,
                controller: _local,
              ),
            ),
            IconButton(
              tooltip: 'Agregar equipo local',
              onPressed: _agregarLocal,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
    ];
    final filasWidget = [
      for (final f in filas)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: PanelMantenimiento(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  f.value,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                cantidades(f, compacta: !tabla),
              ],
            ),
          ),
        ),
    ];
    if (!_edita) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.centro.centro.nombre)),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [...campos, ...filasWidget],
          ),
        ),
      );
    }
    return EditorMantenimiento(
      titulo: widget.centro.centro.nombre,
      vistaWeb: widget.vistaWeb,
      etiqueta: 'Guardar mínimos',
      guardar: _guardar,
      campos: campos,
      soportes: filasWidget,
    );
  }
}
