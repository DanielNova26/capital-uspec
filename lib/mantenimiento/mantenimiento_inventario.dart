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
    this.bajas = false,
    this.minimos = false,
  });

  final MantenimientoService service;
  final List<EquipoMantenimiento> equipos;
  final List<EstablecimientoMantenimiento> centros;
  final bool vistaWeb, bajas, minimos;

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
      setState(() => _catalogos = widget.service.inventario('catalogos'));
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

  Future<void> _asociar(EquipoMantenimiento equipo) async {
    try {
      final datos = await widget.service.inventario('catalogos');
      if (!mounted) return;
      var familia = equipo.familia;
      final guardar = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(equipo.nombre),
          content: _selector('Tipo en el maestro de mínimos', familia, {
            '': 'Sin asociar',
            ..._familias(datos),
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
          baja: baja ?? widget.bajas,
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
          if (!widget.bajas && saldo == 0 && equipo.datos['inventario'] != true)
            TextButton(
              onPressed: () => _alta(equipo),
              child: const Text('Registrar ingreso'),
            ),
          if (!widget.bajas && saldo > 0)
            TextButton(
              onPressed: () => _asociar(equipo),
              child: const Text('Asociar tipo'),
            ),
          if (saldo > 0 && !widget.bajas)
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
                    onPressed: () => setState(
                      () => _catalogos = widget.service.inventario('catalogos'),
                    ),
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
      if (e.existencias.isEmpty && _bodega.isEmpty && !widget.bajas) {
        filas.add((e, '', 0));
      }
      for (final b in e.existencias.entries) {
        if (_bodega.isEmpty || b.key == _bodega) filas.add((e, b.key, b.value));
      }
    }
    final paginas = (filas.length / 20).ceil();
    final pagina = paginas == 0 ? 0 : _pagina.clamp(0, paginas - 1);
    final visibles = filas.skip(pagina * 20).take(20);
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
                  widget.bajas ? 'Baja de equipos' : 'Inventario de equipos',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                if (!widget.bajas)
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
                      'Código o nombre',
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
                    2: FlexColumnWidth(1.6),
                    3: FlexColumnWidth(.75),
                    4: FlexColumnWidth(2.3),
                  },
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  border: const TableBorder(
                    horizontalInside: BorderSide(color: mantenimientoBorde),
                  ),
                  children: [
                    TableRow(
                      decoration: const BoxDecoration(color: Color(0xFFE6F5F2)),
                      children: [
                        for (final t in [
                          'Código',
                          'Nombre',
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
                          _celda(
                            Text(
                              bodegas[b] ?? (b.isEmpty ? 'Sin existencias' : b),
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
  decoration: InputDecoration(labelText: label),
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
        'familia',
        'clasificacion',
        'otraClasificacion',
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
    onChanged: (v) => _datos[clave] = v,
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
        _campo('Código o rótulo', 'codigo', 60, requerido: true)
      else
        Text('Rótulo ${widget.equipo!.codigo}'),
      _campo('Referencia', 'referencia', 100),
      _campo('Nombre', 'nombre', 120, requerido: true),
      _campo('Descripción', 'descripcion', 1200, lineas: 2),
      _campo('Serial', 'serie', 100),
      _campo('Factura', 'factura', 160),
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
        'Tipo en el maestro de mínimos',
        _texto(_datos, 'familia'),
        {'': 'Sin asociar', ..._familias(widget.catalogos)},
        (v) => _datos['familia'] = v,
      ),
      _selector(
        'Clasificación',
        _texto(_datos, 'clasificacion'),
        const {
          '': 'Sin clasificación',
          'Línea caliente': 'Línea caliente',
          'Línea fría': 'Línea fría',
          'Otra': 'Otra',
        },
        (v) => _datos['clasificacion'] = v,
      ),
      _campo('Otra clasificación', 'otraClasificacion', 100),
      _selector('Propiedad', _texto(_datos, 'propiedad'), const {
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
          'Cantidad de unidades',
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
      _fechaCampo('Fecha de ingreso', 'fechaIngreso'),
      _archivoCampo(
        context,
        'Ficha técnica en PDF',
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
      'entrega': _entrega,
      'recibe': _recibe,
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
        Text('${widget.equipo.codigo} · ${widget.equipo.nombre}'),
        if (_texto(widget.equipo.datos, 'referencia').isNotEmpty)
          Text('Referencia ${_texto(widget.equipo.datos, 'referencia')}'),
        Text('${widget.origenNombre} · $saldo unidades disponibles'),
        _entero(
          'Unidades',
          _cantidad,
          (v) => _cantidad = v,
          minimo: 1,
          maximo: saldo,
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
              if (widget.equipo.familia.isEmpty) {
                return const Text(
                  'Este equipo no está asociado al maestro de mínimos.',
                );
              }
              if (plan?['validado'] != true) {
                return const Text(
                  'La sede tiene mínimos pendientes de validar.',
                );
              }
              final minimo =
                  (plan?['cantidades'] as Map?)?[widget.equipo.familia]
                      as int? ??
                  0;
              return Text(
                minimo > 0
                    ? widget.baja
                          ? 'Equipo obligatorio. La baja asignará una tarea de reemplazo al coordinador.'
                          : 'Equipo obligatorio en el destino.'
                    : 'Equipo sin mínimo obligatorio en esta sede.',
              );
            },
          ),
      ],
      soportes: [
        if (!widget.baja) ...[
          campoMantenimiento(
            'Quién entrega',
            120,
            requerido: true,
            onChanged: (v) => _entrega = v,
          ),
          campoMantenimiento(
            'Quién recibe',
            120,
            requerido: true,
            onChanged: (v) => _recibe = v,
          ),
        ],
        campoMantenimiento(
          'Observaciones',
          1200,
          lineas: 3,
          requerido: widget.baja,
          onChanged: (v) => _observaciones = v,
        ),
        if (widget.baja) ...[
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
                                  if (m['accion'] == 'traslado')
                                    OutlinedButton.icon(
                                      onPressed: _ocupado
                                          ? null
                                          : () => _procesar(() async {
                                              final bytes = await _acta(m);
                                              if (context.mounted) {
                                                await _verPdf(
                                                  context,
                                                  bytes,
                                                  'acta_${m['id']}.pdf',
                                                );
                                              }
                                            }),
                                      icon: const Icon(
                                        Icons.picture_as_pdf_outlined,
                                      ),
                                      label: const Text('Ver acta de traslado'),
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

Future<Uint8List> _acta(Map m) async {
  final fuente = pw.Font.ttf(await rootBundle.load('assets/arial.ttf'));
  final documento = pw.Document(title: 'Acta de traslado');
  documento.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      theme: pw.ThemeData.withFont(base: fuente, bold: fuente),
      build: (_) => [
        pw.Text(
          'Acta de traslado de equipos',
          style: const pw.TextStyle(fontSize: 22),
        ),
        pw.SizedBox(height: 16),
        for (final linea in [
          'Movimiento ${m['id']}',
          'Empresa ${m['empresaId']}',
          'Fecha ${_fechaMovimiento(m)}',
          'Equipo ${m['codigo']} · ${m['nombre']}',
          'Referencia ${m['referencia']}',
          'Unidades ${m['unidades']}',
          'Origen ${m['origenNombre']}',
          'Destino ${m['destinoNombre']}',
          'Entrega ${m['entrega']}',
          'Recibe ${m['recibe']}',
          'Equipo obligatorio ${m['obligatorio'] == null
              ? 'Sin validar'
              : m['obligatorio'] == true
              ? 'Sí'
              : 'No'}',
          if (_texto(m, 'observaciones').isNotEmpty)
            'Observaciones ${m['observaciones']}',
        ])
          pw.Paragraph(text: linea),
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
    for (final e in widget.equipos.where((e) => e.familia.isNotEmpty)) {
      actual.update(
        e.familia,
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
