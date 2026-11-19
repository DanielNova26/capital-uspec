import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';

import '../core/guarded_module_page.dart';
import '../compras/compras_excel_download.dart';
import '../widgets/internal_module_layout.dart';
import 'planeacion_service.dart';
import 'planeacion_import.dart';
import 'planeacion_excel.dart';

const _color = Color(0xFF0F766E);
const _secciones = [
  'Ciclos',
  'Raciones',
  'Menús y recetas',
  'Precios',
  'Salidas',
];
const _iconos = [
  Icons.calendar_month_outlined,
  Icons.groups_outlined,
  Icons.menu_book_outlined,
  Icons.payments_outlined,
  Icons.inventory_2_outlined,
];
String _s(Object? v) => (v ?? '').toString();
String _numero(Object? v) =>
    v is num ? NumberFormat('#,##0.######', 'es_CO').format(v) : '—';
String _dinero(Object? v) => v is num
    ? NumberFormat.currency(
        locale: 'es_CO',
        symbol: r'$',
        decimalDigits: 0,
      ).format(v)
    : 'Sin precio vigente';
String _estado(Object? v) => switch (v) {
  'borrador' => 'Borrador',
  'enviada' => 'Enviada a Compras',
  'en_gestion' => 'En gestión',
  'atendida' => 'Atendida',
  'devuelta' => 'Devuelta',
  'despachada' => 'Despachada',
  _ => _s(v),
};

class PlaneacionScreen extends StatelessWidget {
  const PlaneacionScreen({
    super.key,
    required this.empresaId,
    required this.userId,
    this.desdeCompras = false,
  });
  final String empresaId, userId;
  final bool desdeCompras;

  @override
  Widget build(BuildContext context) => GuardedModulePage(
    userIdentity: userId,
    appId: desdeCompras ? 'comprasdashboard' : 'planeaciondashboard',
    pageTitle: desdeCompras ? 'Solicitudes de Planeación' : 'Planeación',
    fallbackEmpresaId: empresaId,
    child: InternalModuleLayout(
      userId: userId,
      empresaId: empresaId,
      title: desdeCompras ? 'Solicitudes de Planeación' : 'Planeación',
      subtitle: 'Consumo, compra y producción',
      accentColor: _color,
      child: PlaneacionWorkspace(
        service: PlaneacionService(empresaId),
        desdeCompras: desdeCompras,
      ),
    ),
  );
}

/// La composición cambia por espacio lógico. El motor y los permisos son únicos.
class PlaneacionWorkspace extends StatefulWidget {
  const PlaneacionWorkspace({
    super.key,
    required this.service,
    this.desdeCompras = false,
  });
  final PlaneacionService service;
  final bool desdeCompras;
  @override
  State<PlaneacionWorkspace> createState() => _PlaneacionWorkspaceState();
}

class _PlaneacionWorkspaceState extends State<PlaneacionWorkspace> {
  PlaneacionDato? _datos;
  String? _error, _seleccion;
  int _seccion = 0;
  bool _ocupado = false;
  String _busqueda = '', _filtroEstado = '';

  List<PlaneacionDato> _filas(String key) => filasPlaneacion(_datos?[key]);
  String get _nivel => _s(_datos?['nivel']);
  bool get _planifica => ['planificador', 'administrador'].contains(_nivel);
  bool get _bodega => ['bodega', 'administrador'].contains(_nivel);
  bool get _gestionaCompra => ['admin', 'compras', 'calidad'].contains(_nivel);

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _ocupado = true;
      _error = null;
    });
    try {
      final data = await widget.service.operar(
        widget.desdeCompras ? 'cargarCompras' : 'cargar',
      );
      if (mounted) setState(() => _datos = data);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = _mensaje(e);
          _datos = null;
        });
      }
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  String _mensaje(Object e) => e is FirebaseFunctionsException
      ? e.message ?? 'No se pudo completar la operación.'
      : e.toString().replaceFirst('Bad state: ', '');
  void _aviso(String t) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<void> _accion(String accion, PlaneacionDato datos) async {
    if (_ocupado) return;
    setState(() => _ocupado = true);
    try {
      await widget.service.operar(accion, datos);
      if (!mounted) return;
      _aviso('Registro guardado.');
      await _cargar();
    } catch (e) {
      if (mounted) _aviso(_mensaje(e));
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_datos == null) {
      return Center(
        child: _error != null
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: _ocupado ? null : _cargar,
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              )
            : const CircularProgressIndicator(),
      );
    }
    return SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, box) {
          final amplio =
              box.maxWidth >= 1000 &&
              MediaQuery.textScalerOf(context).scale(1) < 1.6;
          final lista = _lista(amplio);
          final seleccionada = _registros
              .where((d) => d['id'] == _seleccion)
              .firstOrNull;
          final contenido = seleccionada == null
              ? lista
              : amplio
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 330, child: lista),
                    const VerticalDivider(width: 1),
                    Expanded(child: _detalle(seleccionada, amplio)),
                  ],
                )
              : _detalle(seleccionada, amplio);
          return Column(
            children: [
              if (_ocupado) const LinearProgressIndicator(minHeight: 2),
              Expanded(
                child: Row(
                  children: [
                    if (amplio && !widget.desdeCompras)
                      NavigationRail(
                        selectedIndex: _seccion,
                        labelType: NavigationRailLabelType.all,
                        onDestinationSelected: _cambiarSeccion,
                        destinations: [
                          for (var i = 0; i < _secciones.length; i++)
                            NavigationRailDestination(
                              icon: Icon(_iconos[i]),
                              label: Text(_secciones[i]),
                            ),
                        ],
                      ),
                    Expanded(
                      child: Column(
                        children: [
                          if (!amplio &&
                              !widget.desdeCompras &&
                              _seleccion == null)
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: DropdownButtonFormField<int>(
                                initialValue: _seccion,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Área de Planeación',
                                  border: OutlineInputBorder(),
                                ),
                                items: [
                                  for (var i = 0; i < _secciones.length; i++)
                                    DropdownMenuItem(
                                      value: i,
                                      child: Text(_secciones[i]),
                                    ),
                                ],
                                onChanged: (v) {
                                  if (v != null) _cambiarSeccion(v);
                                },
                              ),
                            ),
                          Expanded(child: contenido),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _cambiarSeccion(int i) => setState(() {
    _seccion = i;
    _seleccion = null;
    _busqueda = '';
    _filtroEstado = '';
  });
  String get _clave => widget.desdeCompras
      ? 'solicitudes'
      : ['ciclos', 'partes', 'menus', 'precios', 'salidas'][_seccion];
  List<PlaneacionDato> get _registros => _filas(_clave).reversed.toList();
  String _titulo(PlaneacionDato d) => switch (_clave) {
    'partes' => _s(d['centroNombre']),
    'menus' => '${d['codigo']} · ${d['nombre']}',
    'precios' => _producto(_s(d['productoCodigo'])),
    'salidas' =>
      '${d['tipo'] == 'alistar' ? 'Alistamiento' : 'Despacho'} · ${d['desde']}',
    _ => _s(d['nombre']),
  };
  String _producto(String codigo) => _s(
    _filas(
          'productos',
        ).where((p) => p['codigo'] == codigo).firstOrNull?['nombre'] ??
        codigo,
  );
  String _subtitulo(PlaneacionDato d) => switch (_clave) {
    'partes' => '${_numero(d['raciones'])} raciones por día',
    'menus' =>
      '${filasPlaneacion(d['ingredientes']).length} ingredientes · ${d['activo'] == false ? 'Inactivo' : 'Activo'}',
    'precios' =>
      '${d['desde']} a ${d['hasta']} · ${_dinero(d['precio'])}/${d['unidad']}',
    'salidas' =>
      '${d['desde']} a ${d['hasta']} · ${filasPlaneacion(d['lineas']).length} líneas',
    _ => '${d['desde']} a ${d['hasta']} · ${_estado(d['estado'])}',
  };

  Widget _lista(bool amplio) {
    final registros = _registros
        .where(
          (d) =>
              '${_titulo(d)} ${_subtitulo(d)}'.toLowerCase().contains(
                _busqueda.toLowerCase(),
              ) &&
              (_filtroEstado.isEmpty || d['estado'] == _filtroEstado),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.desdeCompras
                    ? 'Requerimientos recibidos'
                    : _secciones[_seccion],
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (_planifica && !widget.desdeCompras && _seccion < 4)
                    FilledButton.icon(
                      onPressed: _ocupado ? null : () => _editar(),
                      icon: const Icon(Icons.add),
                      label: Text(
                        [
                          'Nuevo ciclo',
                          'Definir raciones',
                          'Nuevo menú',
                          'Registrar precio',
                        ][_seccion],
                      ),
                    ),
                  OutlinedButton.icon(
                    onPressed: _ocupado ? null : _cargar,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Actualizar'),
                  ),
                  if (_planifica && _clave == 'menus')
                    OutlinedButton.icon(
                      onPressed: _ocupado ? null : _importar,
                      icon: const Icon(Icons.upload_file),
                      label: const Text('Importar recetas Excel'),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                key: ValueKey('buscar_$_clave'),
                onChanged: (v) => setState(() => _busqueda = v),
                decoration: const InputDecoration(
                  labelText: 'Buscar',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
              ),
              if (_clave == 'ciclos' || _clave == 'solicitudes')
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('estado_$_clave'),
                    initialValue: _filtroEstado,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Estado',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('Todos')),
                      for (final e
                          in (_clave == 'ciclos'
                              ? ['borrador', 'enviada', 'despachada']
                              : [
                                  'enviada',
                                  'en_gestion',
                                  'devuelta',
                                  'atendida',
                                ]))
                        DropdownMenuItem(value: e, child: Text(_estado(e))),
                    ],
                    onChanged: (v) => setState(() => _filtroEstado = v ?? ''),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: registros.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No hay registros. Define raciones y recetas para comenzar.',
                    ),
                  ),
                )
              : amplio && _seleccion == null && _clave == 'ciclos'
              ? SingleChildScrollView(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Ciclo')),
                        DataColumn(label: Text('Consumo')),
                        DataColumn(label: Text('Estado')),
                        DataColumn(label: Text('Costo estimado')),
                      ],
                      rows: [
                        for (final d in registros)
                          DataRow(
                            onSelectChanged: (_) =>
                                setState(() => _seleccion = _s(d['id'])),
                            cells: [
                              DataCell(Text(_titulo(d))),
                              DataCell(Text('${d['desde']} a ${d['hasta']}')),
                              DataCell(Text(_estado(d['estado']))),
                              DataCell(Text(_dinero(d['costoTotal']))),
                            ],
                          ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                  itemCount: registros.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (_, i) {
                    final d = registros[i];
                    return Card(
                      color: d['id'] == _seleccion
                          ? const Color(0xFFE0F2F1)
                          : null,
                      child: ListTile(
                        isThreeLine: true,
                        title: Text(_titulo(d)),
                        subtitle: Text(_subtitulo(d)),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => setState(() => _seleccion = _s(d['id'])),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _detalle(PlaneacionDato d, bool amplio) {
    final ciclo = _clave == 'ciclos';
    final lineas = filasPlaneacion(d['totales']);
    final programacion = filasPlaneacion(d['programacion']);
    final solicitud = _filas(
      'solicitudes',
    ).where((s) => s['id'] == d['id']).firstOrNull;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _seleccion = null),
            icon: const Icon(Icons.arrow_back),
            label: const Text('Volver al listado'),
          ),
        ),
        Text(_titulo(d), style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(_subtitulo(d)),
        const SizedBox(height: 16),
        if (ciclo || widget.desdeCompras) ...[
          Text(
            'Costo estimado: ${_dinero(d['costoTotal'])}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (ciclo && (d['sinPrecio'] as num? ?? 0) > 0)
            Text(
              '${d['sinPrecio']} productos sin precio vigente. Completa Precios y vuelve a guardar o envía el ciclo para recalcular.',
            ),
          if (solicitud != null) ...[
            const SizedBox(height: 8),
            Text('Compras: ${_estado(solicitud['estado'])}'),
            if (_s(solicitud['nota']).isNotEmpty)
              Text('Nota de Compras: ${solicitud['nota']}'),
            if (_s(solicitud['ordenCompraReferencia']).isNotEmpty)
              Text('Orden de compra: ${solicitud['ordenCompraReferencia']}'),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (ciclo && d['estado'] == 'borrador' && _planifica) ...[
                OutlinedButton(
                  onPressed: _ocupado ? null : () => _editar(d),
                  child: const Text('Editar ciclo'),
                ),
                FilledButton.icon(
                  onPressed: _ocupado ? null : () => _confirmarEnvio(d),
                  icon: const Icon(Icons.send_outlined),
                  label: const Text('Enviar a Compras'),
                ),
              ],
              OutlinedButton.icon(
                onPressed: _ocupado ? null : () => _exportar(d),
                icon: const Icon(Icons.download_outlined),
                label: const Text('Descargar Excel'),
              ),
              if (ciclo &&
                  d['estado'] != 'borrador' &&
                  _bodega &&
                  d['estado'] != 'despachada') ...[
                FilledButton(
                  onPressed: _ocupado ? null : () => _salida(d, 'alistar'),
                  child: const Text('Alistar por fechas'),
                ),
                OutlinedButton(
                  onPressed: _ocupado ? null : () => _salida(d, 'despachar'),
                  child: const Text('Despachar a producción'),
                ),
              ],
              if (widget.desdeCompras &&
                  _gestionaCompra &&
                  d['estado'] != 'atendida')
                FilledButton(
                  onPressed: _ocupado ? null : () => _gestionar(d),
                  child: const Text('Gestionar solicitud'),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'Necesidades por producto',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          ..._tablaNecesidades(lineas, amplio),
          const SizedBox(height: 24),
          Text(
            'Consumo por establecimiento',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          for (var i = 0; i < programacion.length; i++)
            Card(
              child: ListTile(
                title: Text(
                  '${programacion[i]['fecha']} · ${programacion[i]['centroNombre']}',
                ),
                subtitle: Text(
                  '${programacion[i]['menuCodigo']} · ${_numero(programacion[i]['raciones'])} raciones'
                  '${ciclo ? '\n${(d['despachados'] as List? ?? []).contains('$i')
                            ? 'Despachado'
                            : (d['alistados'] as List? ?? []).contains('$i')
                            ? 'Alistado'
                            : 'Pendiente de alistar'}' : ''}',
                ),
              ),
            ),
          if (widget.desdeCompras) ...[
            if (_s(d['nota']).isNotEmpty) Text('Nota: ${d['nota']}'),
            if (_s(d['ordenCompraReferencia']).isNotEmpty)
              Text('Orden de compra: ${d['ordenCompraReferencia']}'),
            for (final h in filasPlaneacion(d['historial']))
              ListTile(
                title: Text(_estado(h['estado'])),
                subtitle: Text(
                  '${h['fecha']} · ${h['userId']}\n${h['nota'] ?? ''}',
                ),
              ),
          ],
        ],
        if (_clave == 'menus') ...[
          if (_planifica)
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                onPressed: _ocupado ? null : () => _editar(d),
                child: const Text('Editar receta'),
              ),
            ),
          for (final i in filasPlaneacion(d['ingredientes']))
            Card(
              child: ListTile(
                title: Text('${i['tiempo']} · ${i['preparacion']}'),
                subtitle: Text(
                  '${_producto(_s(i['productoCodigo']))}\n${_numero(i['cantidadPorRacion'])} ${i['unidad']} por ración',
                ),
              ),
            ),
        ],
        if (['partes', 'precios'].contains(_clave) && _planifica)
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              onPressed: _ocupado ? null : () => _editar(d),
              child: const Text('Editar'),
            ),
          ),
        if (_clave == 'salidas') ...[
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _ocupado ? null : () => _exportar(d),
              icon: const Icon(Icons.download_outlined),
              label: const Text('Descargar Excel'),
            ),
          ),
          Text('Registró: ${d['registradoPor']} · ${d['fechaRegistro']}'),
          if (_s(d['observacion']).isNotEmpty) Text(_s(d['observacion'])),
          for (final l in filasPlaneacion(d['lineas']))
            Card(
              child: ListTile(
                title: Text(
                  '${l['producto']} · ${_numero(l['cantidad'])} ${l['unidad']}',
                ),
                subtitle: Text(
                  '${l['centroNombre']} · ${l['fecha']}\n${l['tiempo']} · ${l['preparacion']}',
                ),
              ),
            ),
        ],
      ],
    );
  }

  List<Widget> _tablaNecesidades(List<PlaneacionDato> lineas, bool amplio) =>
      amplio
      ? [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Producto')),
                DataColumn(label: Text('Categoría')),
                DataColumn(label: Text('Cantidad'), numeric: true),
                DataColumn(label: Text('Unidad')),
                DataColumn(label: Text('Costo'), numeric: true),
              ],
              rows: [
                for (final l in lineas)
                  DataRow(
                    cells: [
                      DataCell(Text(_s(l['producto']))),
                      DataCell(Text(_s(l['categoria']))),
                      DataCell(Text(_numero(l['cantidad']))),
                      DataCell(Text(_s(l['unidad']))),
                      DataCell(Text(_dinero(l['costo']))),
                    ],
                  ),
              ],
            ),
          ),
        ]
      : [
          for (final l in lineas)
            Card(
              child: ListTile(
                title: Text(_s(l['producto'])),
                subtitle: Text(
                  '${_numero(l['cantidad'])} ${l['unidad']} · ${_dinero(l['costo'])}',
                ),
              ),
            ),
        ];

  Future<void> _confirmarEnvio(PlaneacionDato d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enviar solicitud a Compras'),
        content: const Text(
          'Se recalcularán cantidades y precios vigentes. El ciclo quedará cerrado para edición y conservará su receta y costos para alistamiento y despacho.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
    if (ok == true) await _accion('enviar', {'id': d['id']});
  }

  Future<void> _exportar(PlaneacionDato d) async {
    try {
      await descargarExcelCompras(
        nombreArchivo: 'Planeacion_${d['id']}',
        bytes: exportarPlaneacion(d),
      );
    } catch (e) {
      if (mounted) _aviso(_mensaje(e));
    }
  }

  Future<void> _importar() async {
    try {
      final archivo = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        withData: true,
      );
      final bytes = archivo?.files.single.bytes;
      if (bytes == null || !mounted) return;
      final vista = interpretarMenusPlaneacion(bytes, _filas('productos'));
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Revisar recetas del Excel'),
          content: SizedBox(
            width: 600,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${vista.menus.length} menús detectados. Solo se crearán códigos nuevos; los menús existentes se conservan.',
                  ),
                  const SizedBox(height: 12),
                  for (final a in vista.advertencias)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(a),
                    ),
                  if (vista.errores.isNotEmpty)
                    Text(
                      '${vista.errores.length} errores. Corrige los códigos o unidades en el archivo antes de importar.',
                    ),
                  for (final e in vista.errores.take(50)) Text(e),
                  for (final m in vista.menus)
                    ListTile(
                      title: Text(_s(m['nombre'])),
                      subtitle: Text(
                        '${filasPlaneacion(m['ingredientes']).length} ingredientes',
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: vista.errores.isNotEmpty || vista.menus.isEmpty
                  ? null
                  : () => Navigator.pop(context, true),
              child: const Text('Crear menús nuevos'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      setState(() => _ocupado = true);
      var creados = 0, omitidos = 0;
      try {
        for (final m in vista.menus) {
          final r = await widget.service.operar('guardarMenu', {
            ...m,
            'soloNuevo': true,
          });
          if (r['omitido'] == true) {
            omitidos++;
          } else {
            creados++;
          }
        }
        if (mounted) {
          _aviso('$creados menús creados; $omitidos existentes conservados.');
        }
      } catch (e) {
        if (mounted) {
          _aviso(
            '$creados menús creados antes del error: ${_mensaje(e)}. Puedes reintentar; no se duplicarán.',
          );
        }
      } finally {
        if (mounted) await _cargar();
      }
    } catch (e) {
      if (mounted) _aviso(_mensaje(e));
    }
  }

  Future<void> _editar([PlaneacionDato? actual]) async {
    final result = await showDialog<PlaneacionDato>(
      context: context,
      builder: (_) => PlaneacionEditor(
        tipo: _clave,
        actual: actual,
        productos: _filas('productos'),
        centros: _filas('centros'),
        menus: _filas('menus'),
        partes: _filas('partes'),
      ),
    );
    if (result != null) {
      await _accion(
        {
          'ciclos': 'guardarCiclo',
          'partes': 'guardarParte',
          'menus': 'guardarMenu',
          'precios': 'guardarPrecio',
        }[_clave]!,
        result,
      );
    }
  }

  Future<void> _salida(PlaneacionDato d, String tipo) async {
    final result = await showDialog<PlaneacionDato>(
      context: context,
      builder: (_) => PlaneacionEditor(tipo: tipo, actual: d),
    );
    if (result != null) await _accion(tipo, result);
  }

  Future<void> _gestionar(PlaneacionDato d) async {
    final result = await showDialog<PlaneacionDato>(
      context: context,
      builder: (_) => PlaneacionEditor(tipo: 'gestionar', actual: d),
    );
    if (result != null) await _accion('gestionarSolicitud', result);
  }
}

class PlaneacionEditor extends StatefulWidget {
  const PlaneacionEditor({
    super.key,
    required this.tipo,
    this.actual,
    this.productos = const [],
    this.centros = const [],
    this.menus = const [],
    this.partes = const [],
  });
  final String tipo;
  final PlaneacionDato? actual;
  final List<PlaneacionDato> productos, centros, menus, partes;
  @override
  State<PlaneacionEditor> createState() => _PlaneacionEditorState();
}

class _PlaneacionEditorState extends State<PlaneacionEditor> {
  final _form = GlobalKey<FormState>();
  final _nombre = TextEditingController(),
      _codigo = TextEditingController(),
      _desde = TextEditingController(),
      _hasta = TextEditingController();
  final _cantidad = TextEditingController(),
      _fecha = TextEditingController(),
      _preparacion = TextEditingController(),
      _nota = TextEditingController(),
      _referencia = TextEditingController();
  String? _producto, _centro, _menu, _estadoNuevo;
  String _tiempo = 'DESAYUNO';
  bool _activo = true;
  List<PlaneacionDato> _items = [];
  String? _error;
  String get _tipo => widget.tipo;
  bool get _ciclo => _tipo == 'ciclos';
  bool get _receta => _tipo == 'menus';
  bool get _salida => _tipo == 'alistar' || _tipo == 'despachar';
  List<PlaneacionDato> get _productos => widget.productos
      .where((p) => _s(p['codigo']).isNotEmpty && p['activo'] != false)
      .toList();
  List<PlaneacionDato> get _centros => widget.centros
      .where((p) => p['activo'] != false && p['enabled'] != false)
      .toList();
  List<PlaneacionDato> get _menus =>
      widget.menus.where((p) => p['activo'] != false).toList();

  @override
  void initState() {
    super.initState();
    final d = widget.actual ?? {};
    final hoy = DateFormat('yyyy-MM-dd').format(DateTime.now());
    _nombre.text = _s(d['nombre']);
    _codigo.text = _s(d['codigo']);
    _desde.text = _s(d['desde'] ?? hoy);
    _hasta.text = _s(d['hasta'] ?? hoy);
    _fecha.text = _desde.text;
    _cantidad.text = _s(d[_tipo == 'precios' ? 'precio' : 'raciones']);
    _centro = d['centroId'] as String?;
    _producto = d['productoCodigo'] as String?;
    _activo = d['activo'] != false;
    _items = filasPlaneacion(
      d[_receta ? 'ingredientes' : 'programacion'],
    ).map((e) => {...e}).toList();
    _referencia.text = _s(d['ordenCompraReferencia']);
  }

  @override
  void dispose() {
    for (final c in [
      _nombre,
      _codigo,
      _desde,
      _hasta,
      _cantidad,
      _fecha,
      _preparacion,
      _nota,
      _referencia,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _campo(
    String label,
    TextEditingController controller, {
    bool numero = false,
    bool obligatorio = true,
    bool soloLectura = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: controller,
      readOnly: soloLectura,
      keyboardType: numero
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      validator: (v) => obligatorio && (v ?? '').trim().isEmpty
          ? 'Completa este campo'
          : null,
    ),
  );

  Widget _fechaCampo(String label, TextEditingController c) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: c,
      decoration: InputDecoration(
        labelText: '$label (AAAA-MM-DD)',
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          tooltip: 'Elegir fecha',
          icon: const Icon(Icons.calendar_today_outlined),
          onPressed: () async {
            final f = await showDatePicker(
              context: context,
              initialDate: DateTime.tryParse(c.text) ?? DateTime.now(),
              firstDate: DateTime(2020),
              lastDate: DateTime(2100),
            );
            if (f != null) c.text = DateFormat('yyyy-MM-dd').format(f);
          },
        ),
      ),
      validator: (v) =>
          _fechaValida(v ?? '') ? null : 'Usa una fecha válida: AAAA-MM-DD',
    ),
  );

  bool _fechaValida(String v) =>
      RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v) &&
      DateTime.tryParse(v)?.toIso8601String().startsWith(v) == true;
  num _positivo(String v, {bool entero = false}) {
    final n = num.tryParse(v.trim().replaceAll(',', '.'));
    if (n == null || !n.isFinite || n <= 0 || (entero && n != n.round())) {
      throw StateError(
        'Ingresa una cantidad positiva${entero ? ' entera' : ''}.',
      );
    }
    return n;
  }

  Widget _selector(
    String label,
    List<({String id, String label})> opciones,
    String? valor,
    ValueChanged<String?> cambiar,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: DropdownButtonFormField<String>(
      key: ValueKey('$label:$valor:${opciones.length}'),
      initialValue: opciones.any((o) => o.id == valor) ? valor : null,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: [
        for (final o in opciones)
          DropdownMenuItem(
            value: o.id,
            child: Text(o.label, maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: cambiar,
    ),
  );

  void _elegirCentro(String? c) => setState(() {
    _centro = c;
    final parte = widget.partes.where((p) => p['centroId'] == c).firstOrNull;
    _cantidad.text = _s(parte?['raciones']);
  });

  @override
  Widget build(BuildContext context) {
    final titulo = switch (_tipo) {
      'ciclos' => 'Ciclo de consumo',
      'partes' => 'Raciones por establecimiento',
      'menus' => 'Menú y receta diaria',
      'precios' => 'Precio por unidad de compra',
      'alistar' => 'Alistamiento de materia prima',
      'despachar' => 'Despacho a producción',
      _ => 'Gestionar solicitud',
    };
    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 720,
          maxHeight:
              MediaQuery.sizeOf(context).height -
              MediaQuery.viewInsetsOf(context).bottom -
              48,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                titulo,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      if (_ciclo || _receta) _campo('Nombre', _nombre),
                      if (_receta) ...[
                        _campo(
                          'Código del menú',
                          _codigo,
                          soloLectura: widget.actual != null,
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Menú activo'),
                          value: _activo,
                          onChanged: (v) => setState(() => _activo = v),
                        ),
                        const Text(
                          'Receta diaria completa: ingredientes por tiempo de comida y preparación. Ingresa la cantidad de UNA ración en la unidad del producto de Compras. Ejemplo: 80 gramos = 0,08 kg. Las unidades y conversiones especiales se revisan explícitamente.',
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (_ciclo || _salida || _tipo == 'precios') ...[
                        _fechaCampo(
                          _salida ? 'Consumo desde' : 'Desde',
                          _desde,
                        ),
                        _fechaCampo(
                          _salida ? 'Consumo hasta' : 'Hasta',
                          _hasta,
                        ),
                      ],
                      if (_tipo == 'partes' || _ciclo)
                        _selector(
                          'Establecimiento',
                          [
                            for (final c in _centros)
                              (
                                id: _s(c['id']),
                                label: _s(
                                  c['nombre'] ?? c['descripcion'] ?? c['id'],
                                ),
                              ),
                          ],
                          _centro,
                          _elegirCentro,
                        ),
                      if (_tipo == 'partes')
                        _campo(
                          'Raciones diarias (parte)',
                          _cantidad,
                          numero: true,
                        ),
                      if (_tipo == 'precios' || _receta) ...[
                        _selector(
                          'Producto de Compras',
                          [
                            for (final p in _productos)
                              (
                                id: _s(p['codigo']),
                                label:
                                    '${p['codigo']} · ${p['nombre']} (${p['unidadMedida']})',
                              ),
                          ],
                          _producto,
                          (v) => setState(() => _producto = v),
                        ),
                        _campo(
                          _receta
                              ? 'Cantidad por ración en unidad de compra'
                              : 'Precio por unidad de compra (COP)',
                          _cantidad,
                          numero: true,
                          obligatorio: !_receta,
                        ),
                      ],
                      if (_receta) ...[
                        _selector(
                          'Tiempo de comida',
                          [
                            for (final t in [
                              'DESAYUNO',
                              'ALMUERZO',
                              'CENA',
                              'REFRIGERIO',
                            ])
                              (id: t, label: t),
                          ],
                          _tiempo,
                          (v) => setState(() => _tiempo = v ?? _tiempo),
                        ),
                        _campo('Preparación', _preparacion, obligatorio: false),
                        OutlinedButton.icon(
                          onPressed: _agregarIngrediente,
                          icon: const Icon(Icons.add),
                          label: const Text('Agregar ingrediente'),
                        ),
                      ],
                      if (_ciclo) ...[
                        const Text(
                          'Programa cada día por establecimiento. Un menú representa la receta diaria completa. Las raciones se toman del parte y puedes ajustarlas para ese día.',
                        ),
                        const SizedBox(height: 12),
                        _fechaCampo('Día de consumo', _fecha),
                        _selector(
                          'Menú diario',
                          [
                            for (final m in _menus)
                              (
                                id: _s(m['codigo']),
                                label: '${m['codigo']} · ${m['nombre']}',
                              ),
                          ],
                          _menu,
                          (v) => setState(() => _menu = v),
                        ),
                        _campo(
                          'Raciones para este día',
                          _cantidad,
                          numero: true,
                          obligatorio: false,
                        ),
                        OutlinedButton.icon(
                          onPressed: _agregarConsumo,
                          icon: const Icon(Icons.add),
                          label: const Text('Agregar día al ciclo'),
                        ),
                      ],
                      if (_ciclo || _receta) ...[
                        const SizedBox(height: 12),
                        Text(
                          '${_items.length} ${_receta ? 'ingredientes' : 'consumos'} agregados',
                        ),
                        for (var i = 0; i < _items.length; i++)
                          Card(
                            child: ListTile(
                              title: Text(
                                _receta
                                    ? '${_items[i]['productoCodigo']} · ${_items[i]['cantidadPorRacion']} ${_items[i]['unidad']}'
                                    : '${_items[i]['fecha']} · ${_items[i]['centroNombre']}',
                              ),
                              subtitle: Text(
                                _receta
                                    ? '${_items[i]['tiempo']} · ${_items[i]['preparacion']}'
                                    : '${_items[i]['menuCodigo']} · ${_items[i]['raciones']} raciones',
                              ),
                              trailing: IconButton(
                                tooltip: 'Retirar línea',
                                icon: const Icon(Icons.close),
                                onPressed: () =>
                                    setState(() => _items.removeAt(i)),
                              ),
                            ),
                          ),
                      ],
                      if (_salida) ...[
                        const Text(
                          'Se registran las cantidades calculadas del ciclo enviado. El rango usa las fechas de consumo. No se repite un consumo ya procesado. El despacho exige alistamiento previo.',
                        ),
                        const SizedBox(height: 12),
                        _campo(
                          'Observaciones de entrega',
                          _nota,
                          obligatorio: false,
                        ),
                      ],
                      if (_tipo == 'gestionar') ...[
                        _selector(
                          'Nuevo estado',
                          [
                            for (final e
                                in (widget.actual?['estado'] == 'en_gestion'
                                    ? ['atendida', 'devuelta']
                                    : widget.actual?['estado'] == 'devuelta'
                                    ? ['en_gestion']
                                    : ['en_gestion', 'devuelta']))
                              (id: e, label: _estado(e)),
                          ],
                          _estadoNuevo,
                          (v) => setState(() => _estadoNuevo = v),
                        ),
                        _campo('Motivo o nota', _nota, obligatorio: false),
                        _campo(
                          'Referencia de orden de compra',
                          _referencia,
                          obligatorio: false,
                        ),
                      ],
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 12,
                runSpacing: 8,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancelar'),
                  ),
                  FilledButton(
                    onPressed: _guardar,
                    child: Text(_salida ? 'Confirmar registro' : 'Guardar'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _capturar(VoidCallback f) {
    try {
      f();
      setState(() => _error = null);
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Bad state: ', ''));
    }
  }

  void _agregarIngrediente() => _capturar(() {
    final p = _productos.where((p) => p['codigo'] == _producto).firstOrNull;
    if (p == null || _preparacion.text.trim().isEmpty) {
      throw StateError('Selecciona el producto y escribe la preparación.');
    }
    _items.add({
      'productoCodigo': _producto,
      'unidad': unidadPlaneacion(p['unidadMedida']),
      'cantidadPorRacion': _positivo(_cantidad.text),
      'tiempo': _tiempo,
      'preparacion': _preparacion.text.trim(),
    });
    _cantidad.clear();
  });

  void _agregarConsumo() => _capturar(() {
    final c = _centros.where((c) => c['id'] == _centro).firstOrNull;
    if (c == null || _menu == null) {
      throw StateError('Selecciona establecimiento y menú.');
    }
    if (!_fechaValida(_fecha.text) ||
        _fecha.text.compareTo(_desde.text) < 0 ||
        _fecha.text.compareTo(_hasta.text) > 0) {
      throw StateError('El consumo debe estar dentro del período.');
    }
    if (_items.any(
      (s) => s['centroId'] == _centro && s['fecha'] == _fecha.text,
    )) {
      throw StateError('Ese establecimiento ya tiene menú para ese día.');
    }
    _items.add({
      'centroId': _centro,
      'centroNombre': c['nombre'] ?? c['descripcion'] ?? c['id'],
      'fecha': _fecha.text,
      'menuCodigo': _menu,
      'raciones': _positivo(_cantidad.text, entero: true),
    });
    final siguiente = DateTime.parse(_fecha.text).add(const Duration(days: 1));
    final key = DateFormat('yyyy-MM-dd').format(siguiente);
    if (key.compareTo(_hasta.text) <= 0) _fecha.text = key;
  });

  void _guardar() => _capturar(() {
    if (!_form.currentState!.validate()) return;
    if ((_ciclo || _receta) && _items.isEmpty) {
      throw StateError('Agrega las líneas antes de guardar.');
    }
    if ((_ciclo || _salida || _tipo == 'precios') &&
        _desde.text.compareTo(_hasta.text) > 0) {
      throw StateError('El rango de fechas está invertido.');
    }
    final d = <String, dynamic>{
      if (widget.actual?['id'] != null) 'id': widget.actual!['id'],
    };
    if (_receta) {
      d.addAll({
        'codigo': _codigo.text.trim(),
        'nombre': _nombre.text.trim(),
        'activo': _activo,
        'ingredientes': _items,
      });
    }
    if (_tipo == 'partes') {
      if (_centro == null) throw StateError('Selecciona un establecimiento.');
      d.addAll({
        'centroId': _centro,
        'raciones': _positivo(_cantidad.text, entero: true),
      });
    }
    if (_tipo == 'precios') {
      if (_producto == null) throw StateError('Selecciona un producto.');
      d.addAll({
        'productoCodigo': _producto,
        'precio': _positivo(_cantidad.text),
      });
    }
    if (_ciclo) {
      d.addAll({'nombre': _nombre.text.trim(), 'programacion': _items});
    }
    if (_ciclo || _salida || _tipo == 'precios') {
      d.addAll({'desde': _desde.text, 'hasta': _hasta.text});
    }
    if (_salida) d['observacion'] = _nota.text;
    if (_tipo == 'gestionar') {
      if (_estadoNuevo == null) throw StateError('Selecciona el nuevo estado.');
      if (_estadoNuevo == 'devuelta' && _nota.text.trim().isEmpty) {
        throw StateError('Indica el motivo de devolución.');
      }
      if (_estadoNuevo == 'atendida' && _referencia.text.trim().isEmpty) {
        throw StateError('Registra la referencia de orden de compra.');
      }
      d.addAll({
        'estado': _estadoNuevo,
        'nota': _nota.text,
        'ordenCompraReferencia': _referencia.text,
      });
    }
    Navigator.pop(context, d);
  });
}
