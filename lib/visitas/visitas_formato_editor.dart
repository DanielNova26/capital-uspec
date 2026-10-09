// lib/visitas/visitas_formato_editor.dart
//
// Editor de formatos de visita (26 sep 2026): "que parezca prácticamente
// como hacer un formato de Google, más entendible, más práctico, tanto que
// se pueda hacer como en Excel como que se pueda hacer agregando ahí".
//
// Dos vistas sobre los mismos datos:
//  - Tarjetas, como Google Forms: una tarjeta por pregunta con su tipo en
//    palabras, cómo la verá el profesional, ayuda, obligatoria y foto.
//  - Tabla, como Excel: una fila por pregunta y una columna por dato, para
//    armar o corregir muchas de una vez.
// Más "Pegar desde Excel" (se copian las celdas y se pegan), "Agregar desde
// un Excel" y las tablas del formato (extintores, áreas…), que antes solo
// venían del formato SST generado y no se podían crear.
//
// Nada se guarda hasta tocar Guardar: un formato recién importado de Excel
// llega aquí para revisarlo.

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../widgets/paged_list.dart';
import 'visitas_formato_excel.dart';
import 'visitas_models.dart';
import 'visitas_service.dart';

const Color _kColor = Color(0xFF7C3AED);
const String _kFont = 'Arial';

void _snack(BuildContext context, String msg, {bool error = false}) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(msg),
      backgroundColor: error ? const Color(0xFFB91C1C) : null,
    ),
  );
}

var _secuencia = 0;
String _nuevoId(String prefijo) =>
    '${prefijo}_${DateTime.now().microsecondsSinceEpoch}_${_secuencia++}';

IconData iconoTipoPregunta(String tipo) => switch (tipo) {
  kItemTipoCalificacion => Icons.rule_rounded,
  kItemTipoSiNo => Icons.toggle_on_outlined,
  kItemTipoElemento => Icons.inventory_2_outlined,
  kItemTipoOpcion => Icons.radio_button_checked,
  kItemTipoTexto => Icons.short_text_rounded,
  kItemTipoParrafo => Icons.notes_rounded,
  kItemTipoNumero => Icons.pin_outlined,
  kItemTipoFecha => Icons.event_outlined,
  _ => Icons.help_outline,
};

class VisitaFormatoEditorScreen extends StatefulWidget {
  final VisitasService svc;
  final VisitaFormato formato;
  final String userId;
  final Map<String, String> areas;
  final String areaFija;

  /// Lo que se supuso al adaptar un Excel. Sale arriba para revisarlo.
  final List<String> avisosImportacion;

  const VisitaFormatoEditorScreen({
    super.key,
    required this.svc,
    required this.formato,
    required this.userId,
    required this.areas,
    required this.areaFija,
    this.avisosImportacion = const [],
  });

  @override
  State<VisitaFormatoEditorScreen> createState() =>
      _VisitaFormatoEditorScreenState();
}

enum _Vista { tarjetas, tabla }

class _VisitaFormatoEditorScreenState extends State<VisitaFormatoEditorScreen> {
  late final TextEditingController _nombre;
  late final TextEditingController _areaNombre;
  late final TextEditingController _codigo;
  late final TextEditingController _versionDoc;
  late final TextEditingController _elaboracion;
  late final TextEditingController _sistema;
  late String _estado;
  late String _areaId;
  late bool _predeterminado;
  late List<_ItemEdit> _items;
  late List<VisitaFormatoTabla> _tablas;
  late List<_ParteEdit> _partes;
  late Set<String> _cargos;
  List<String> _cargosEmpresa = const [];
  bool _guardando = false;
  bool _sucio = false;
  bool _mostrarAvisos = true;
  _Vista _vista = _Vista.tarjetas;
  int _pagina = 0;

  @override
  void initState() {
    super.initState();
    final f = widget.formato;
    _cargos = {...f.cargos};
    _nombre = _ctrl(f.nombre);
    _areaNombre = _ctrl(f.areaNombre);
    _codigo = _ctrl(f.codigo);
    _versionDoc = _ctrl(f.versionDocumento);
    _elaboracion = _ctrl(f.elaboracion);
    _sistema = _ctrl(f.sistema);
    _estado = f.estado;
    _areaId = f.areaId.isNotEmpty ? f.areaId : widget.areaFija;
    _predeterminado = f.predeterminado;
    _items = [for (final it in f.itemsOrdenados) _ItemEdit.de(it, _marcar)];
    _tablas = [...f.tablas];
    _partes = [for (final p in f.partes) _ParteEdit.de(p, _marcar)];
    // Un formato recién importado todavía no está guardado.
    _sucio = f.id.isEmpty && (f.items.isNotEmpty || f.tablas.isNotEmpty);
    _cargarCargos();
  }

  /// Cargos del departamento elegido (28 sep 2026: "los cargos deben
  /// depender del área seleccionada previamente").
  Future<void> _cargarCargos() async {
    final area = _areaId;
    if (area.isEmpty) {
      if (_cargosEmpresa.isNotEmpty) setState(() => _cargosEmpresa = const []);
      return;
    }
    final c = await widget.svc.cargosDeArea(
      widget.formato.empresaId,
      areaId: area,
      areaNombre: widget.areas[area] ?? widget.formato.areaNombre,
    );
    if (mounted && area == _areaId) setState(() => _cargosEmpresa = c);
  }

  TextEditingController _ctrl(String texto) =>
      TextEditingController(text: texto)..addListener(_marcar);

  void _marcar() {
    if (!_sucio && mounted) setState(() => _sucio = true);
  }

  @override
  void dispose() {
    for (final c in [
      _nombre,
      _areaNombre,
      _codigo,
      _versionDoc,
      _elaboracion,
      _sistema,
    ]) {
      c.dispose();
    }
    for (final i in _items) {
      i.dispose();
    }
    for (final p in _partes) {
      p.dispose();
    }
    super.dispose();
  }

  String _areaIdDesdeNombre(String n) => n
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[áà]'), 'a')
      .replaceAll(RegExp(r'[éè]'), 'e')
      .replaceAll(RegExp(r'[íì]'), 'i')
      .replaceAll(RegExp(r'[óò]'), 'o')
      .replaceAll(RegExp(r'[úù]'), 'u')
      .replaceAll('ñ', 'n')
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_');

  List<String> get _secciones {
    final vistas = <String>{};
    return [
      for (final i in _items)
        if (i.seccion.text.trim().isNotEmpty &&
            vistas.add(i.seccion.text.trim()))
          i.seccion.text.trim(),
    ];
  }

  String get _parteDefecto => _partes.isEmpty ? '' : _partes.first.codigo;

  VisitaFormato _armar() {
    final areaId = _areaId.isNotEmpty
        ? _areaId
        : _areaIdDesdeNombre(_areaNombre.text);
    return VisitaFormato(
      id: widget.formato.id,
      empresaId: widget.formato.empresaId,
      areaId: areaId,
      // Si no cambió de departamento se conserva el nombre guardado (la
      // lista puede traerlo marcado "no es un departamento").
      areaNombre:
          areaId == widget.formato.areaId &&
              widget.formato.areaNombre.isNotEmpty
          ? widget.formato.areaNombre
          : (widget.areas[areaId] ?? _areaNombre.text.trim()),
      nombre: _nombre.text.trim(),
      estado: _estado,
      predeterminado: _estado != kFormatoRetirado && _predeterminado,
      // Cambiar un formato ya usado es una versión nueva; así el informe de
      // una visita vieja dice con qué versión se hizo.
      version: widget.formato.id.isEmpty ? 1 : widget.formato.version + 1,
      items: [for (var i = 0; i < _items.length; i++) _items[i].aItem(i + 1)],
      partes: [for (final p in _partes) p.aParte()],
      tablas: _tablas,
      cargos: _cargos.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())),
      codigo: _codigo.text.trim(),
      versionDocumento: _versionDoc.text.trim(),
      elaboracion: _elaboracion.text.trim(),
      sistema: _sistema.text.trim(),
    );
  }

  Future<void> _guardar() async {
    final f = _armar();
    final errores = validarFormato(f);
    if (errores.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Revisa antes de guardar'),
          content: SizedBox(
            width: 420,
            child: ListView(
              shrinkWrap: true,
              children: [for (final e in errores.take(20)) Text('• $e')],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
      return;
    }
    setState(() => _guardando = true);
    try {
      await widget.svc.guardarFormato(f, actorId: widget.userId);
      if (!mounted) return;
      _sucio = false;
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _guardando = false);
        _snack(context, 'No se pudo guardar: $e', error: true);
      }
    }
  }

  Future<bool> _confirmarSalida() async {
    if (!_sucio) return true;
    final salir = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('¿Salir sin guardar?'),
        content: const Text(
          'Los cambios de este formato se pierden si sales sin guardar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Seguir editando'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB91C1C),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Salir sin guardar'),
          ),
        ],
      ),
    );
    return salir == true;
  }

  // ── Preguntas ──────────────────────────────────────────────────────────

  void _irAUltimaPagina() => _pagina = pageCountOf(_items.length) - 1 < 0
      ? 0
      : pageCountOf(_items.length) - 1;

  void _agregarPregunta({String seccion = '', String parte = ''}) {
    setState(() {
      _items.add(
        _ItemEdit.nuevo(
          _marcar,
          seccion: seccion,
          parte: parte.isNotEmpty ? parte : _parteDefecto,
        ),
      );
      _irAUltimaPagina();
      _sucio = true;
    });
  }

  Future<void> _agregarSeccion() async {
    final ctrl = TextEditingController();
    final nombre = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Nueva sección'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Nombre de la sección',
            hintText: 'Cocina, Bodega, Botiquín…',
          ),
          onSubmitted: (v) => Navigator.pop(context, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _kColor),
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('Crear y agregar pregunta'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (nombre == null || nombre.isEmpty) return;
    _agregarPregunta(seccion: nombre);
  }

  void _duplicar(int i) => setState(() {
    _items.insert(i + 1, _items[i].copia(_marcar));
    _sucio = true;
  });

  void _eliminar(int i) => setState(() {
    _items.removeAt(i).dispose();
    _sucio = true;
    final max = pageCountOf(_items.length) - 1;
    if (_pagina > max) _pagina = max < 0 ? 0 : max;
  });

  void _mover(int i, int a) {
    if (a < 0 || a >= _items.length) return;
    setState(() {
      _items.insert(a, _items.removeAt(i));
      _pagina = a ~/ kPageSize;
      _sucio = true;
    });
  }

  void _agregarItems(List<VisitaFormatoItem> nuevos) {
    setState(() {
      for (final it in nuevos) {
        _items.add(
          _ItemEdit.de(
            it.copyWith(parte: it.parte.isEmpty ? _parteDefecto : it.parte),
            _marcar,
          ),
        );
      }
      _irAUltimaPagina();
      _sucio = true;
    });
  }

  Future<void> _pegarDesdeExcel() async {
    final ctrl = TextEditingController();
    final r = await showDialog<List<VisitaFormatoItem>>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setLocal) {
          final prev = preguntasDesdeTextoPegado(
            ctrl.text,
            desdeOrden: _items.length + 1,
            prefijoId: _nuevoId('pg'),
          );
          return AlertDialog(
            title: const Text('Pegar desde Excel'),
            content: SizedBox(
              width: 560,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'En Excel o Google Sheets selecciona las celdas (Sección y '
                    'Pregunta, o solo las preguntas), cópialas y pégalas aquí. '
                    'Si copias también los encabezados de la plantilla, se '
                    'respetan el tipo, las opciones y lo demás.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: ctrl,
                    autofocus: true,
                    minLines: 6,
                    maxLines: 12,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText:
                          'Cocina\t¿Pisos limpios?\n'
                          'Cocina\t¿Nevera a menos de 4 °C?',
                    ),
                    onChanged: (_) => setLocal(() {}),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    prev.items.isEmpty
                        ? 'Todavía no hay preguntas.'
                        : '${prev.items.length} pregunta(s) para agregar.',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _kColor),
                onPressed: prev.items.isEmpty
                    ? null
                    : () => Navigator.pop(context, prev.items),
                child: const Text('Agregar'),
              ),
            ],
          );
        },
      ),
    );
    ctrl.dispose();
    if (r == null || r.isEmpty || !mounted) return;
    _agregarItems(r);
    _snack(context, '${r.length} pregunta(s) agregadas al final.');
  }

  Future<void> _agregarDesdeExcel() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        withData: true,
      );
      if (picked == null) return;
      final bytes = picked.files.single.bytes;
      if (bytes == null) throw const FormatException('No se pudo leer.');
      final r = leerFormatoVisitasExcel(
        bytes,
        empresaId: widget.formato.empresaId,
        areaId: _areaId.isEmpty ? 'area' : _areaId,
        areaNombre: _areaNombre.text,
        nombre: _nombre.text.trim().isEmpty ? 'Formato' : _nombre.text,
      );
      final base = _items.length;
      final stamp = _nuevoId('xl');
      final nuevos = [
        for (final (i, it) in r.formato.items.indexed)
          VisitaFormatoItem.fromMap({
            ...it.toMap(),
            'id': '${stamp}_$i',
            'orden': base + i + 1,
            // Las partes del otro Excel no existen en este formato.
            'parte': '',
          }),
      ];
      _agregarItems(nuevos);
      if (r.formato.tablas.isNotEmpty) {
        setState(() {
          for (final t in r.formato.tablas) {
            _tablas.add(
              VisitaFormatoTabla.fromMap({
                ...t.toMap(),
                'id': _nuevoId('tabla'),
                'parte': _parteDefecto,
              }),
            );
          }
        });
      }
      if (!mounted) return;
      _snack(
        context,
        '${nuevos.length} pregunta(s)'
        '${r.formato.tablas.isEmpty ? '' : ' y ${r.formato.tablas.length} tabla(s)'}'
        ' agregadas al final.',
      );
    } catch (e) {
      if (mounted) _snack(context, 'No se pudo leer el Excel: $e', error: true);
    }
  }

  // ── Tablas ─────────────────────────────────────────────────────────────

  Future<void> _editarTabla(int? i) async {
    final t = await showDialog<VisitaFormatoTabla>(
      context: context,
      builder: (_) => _TablaEditorDialog(
        tabla: i == null ? null : _tablas[i],
        partes: [for (final p in _partes) p.codigo],
        parteDefecto: _parteDefecto,
      ),
    );
    if (t == null) return;
    setState(() {
      if (i == null) {
        _tablas.add(t);
      } else {
        _tablas[i] = t;
      }
      _sucio = true;
    });
  }

  // ── Construcción ───────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final ancho = MediaQuery.of(context).size.width;
    final maxPagina = pageCountOf(_items.length) - 1;
    final pagina = _pagina.clamp(0, maxPagina < 0 ? 0 : maxPagina);
    final desde = pagina * kPageSize;
    final visibles = pageOf(_items, pagina);
    return PopScope(
      canPop: !_sucio,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final salir = await _confirmarSalida();
        if (salir && context.mounted) {
          _sucio = false;
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F0FA),
        appBar: AppBar(
          backgroundColor: _kColor,
          foregroundColor: Colors.white,
          title: Text(
            widget.formato.id.isEmpty ? 'Nuevo formato' : 'Editar formato',
            style: const TextStyle(fontFamily: _kFont),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: _kColor,
                ),
                onPressed: _guardando ? null : _guardar,
                icon: const Icon(Icons.save_outlined, size: 18),
                label: Text(_guardando ? 'Guardando…' : 'Guardar'),
              ),
            ),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: _vista == _Vista.tabla ? 1400 : 820,
            ),
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                ancho < 600 ? 8 : 16,
                12,
                ancho < 600 ? 8 : 16,
                40,
              ),
              children: [
                if (widget.avisosImportacion.isNotEmpty && _mostrarAvisos)
                  _avisos(),
                _tarjetaEncabezado(),
                const SizedBox(height: 12),
                _barraPreguntas(),
                const SizedBox(height: 8),
                if (_items.length > kPageSize)
                  PagerBar(
                    total: _items.length,
                    page: pagina,
                    etiqueta: 'preguntas',
                    onPageChanged: (p) => setState(() => _pagina = p),
                  ),
                if (_items.isEmpty)
                  _vacio()
                else if (_vista == _Vista.tarjetas)
                  for (var j = 0; j < visibles.length; j++)
                    _tarjetaPregunta(desde + j)
                else
                  _tablaExcel(desde, visibles.length),
                if (_items.length > kPageSize)
                  PagerBar(
                    total: _items.length,
                    page: pagina,
                    etiqueta: 'preguntas',
                    onPageChanged: (p) => setState(() => _pagina = p),
                  ),
                const SizedBox(height: 8),
                _botonesAgregar(),
                const SizedBox(height: 20),
                _seccionTablas(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _avisos() => Card(
    color: const Color(0xFFFFFBEB),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: const BorderSide(color: Color(0xFFF59E0B)),
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.auto_fix_high_outlined,
                color: Color(0xFFB45309),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Adaptado desde Excel: revísalo antes de guardar',
                  style: TextStyle(
                    fontFamily: _kFont,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF92400E),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Ocultar',
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => setState(() => _mostrarAvisos = false),
              ),
            ],
          ),
          for (final a in widget.avisosImportacion)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '• $a',
                style: const TextStyle(fontSize: 12, color: Color(0xFF92400E)),
              ),
            ),
        ],
      ),
    ),
  );

  Widget _vacio() => Card(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: const [
          Icon(Icons.post_add_outlined, size: 40, color: _kColor),
          SizedBox(height: 8),
          Text(
            'Todavía no hay preguntas',
            style: TextStyle(fontFamily: _kFont, fontWeight: FontWeight.w800),
          ),
          SizedBox(height: 4),
          Text(
            'Agrégalas una por una, pégalas desde Excel o trae un Excel '
            'completo con los botones de abajo.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      ),
    ),
  );

  /// La tarjeta de arriba, como el título de un Google Forms: nombre, área,
  /// estado, cargos y el encabezado del documento que va en el informe.
  Widget _tarjetaEncabezado() {
    final f = widget.formato;
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(height: 10, color: _kColor),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _nombre,
                  style: const TextStyle(
                    fontFamily: _kFont,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Nombre del formato',
                    labelText: 'Nombre del formato',
                  ),
                ),
                const SizedBox(height: 10),
                // Departamento (28 sep 2026): Desarrollo y Gerencia lo eligen
                // también en un formato ya creado, para pasarlo al que lo
                // diligencia; el director trabaja en el suyo.
                if (widget.areas.isNotEmpty &&
                    (f.areaId.isEmpty || widget.areaFija.isEmpty))
                  DropdownButtonFormField<String>(
                    initialValue: widget.areas.containsKey(_areaId)
                        ? _areaId
                        : null,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Departamento del formato',
                      helperText: f.areaId.isNotEmpty && _areaId != f.areaId
                          ? 'Al guardar, el formato pasa a este departamento.'
                          : null,
                    ),
                    items: [
                      for (final e in widget.areas.entries)
                        DropdownMenuItem(value: e.key, child: Text(e.value)),
                    ],
                    onChanged: widget.areaFija.isNotEmpty
                        ? null
                        : (value) {
                            setState(() {
                              _areaId = value ?? '';
                              _sucio = true;
                              // Los cargos son del departamento: al cambiarlo
                              // no se quedan los del anterior.
                              _cargos.clear();
                            });
                            _cargarCargos();
                          },
                  )
                else
                  TextField(
                    controller: _areaNombre,
                    enabled: false,
                    decoration: const InputDecoration(
                      labelText: 'Departamento',
                    ),
                  ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 320,
                      child: DropdownButtonFormField<String>(
                        initialValue: _estado,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Estado'),
                        items: const [
                          DropdownMenuItem(
                            value: kFormatoBorrador,
                            child: Text('Borrador (solo visitas de prueba)'),
                          ),
                          DropdownMenuItem(
                            value: kFormatoVigente,
                            child: Text('Vigente'),
                          ),
                          DropdownMenuItem(
                            value: kFormatoRetirado,
                            child: Text('Retirado (no se ofrece)'),
                          ),
                        ],
                        onChanged: (v) => setState(() {
                          _estado = v ?? kFormatoBorrador;
                          _sucio = true;
                        }),
                      ),
                    ),
                    SizedBox(
                      width: 330,
                      child: SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Predeterminado del área',
                          style: TextStyle(fontSize: 13),
                        ),
                        value: _predeterminado && _estado != kFormatoRetirado,
                        onChanged: _estado == kFormatoRetirado
                            ? null
                            : (value) => setState(() {
                                _predeterminado = value;
                                _sucio = true;
                              }),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                _cargosEditor(),
                const Divider(height: 24),
                _encabezadoInforme(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cargosEditor() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Cargos a los que aplica',
        style: TextStyle(fontFamily: _kFont, fontWeight: FontWeight.w800),
      ),
      const Text(
        'Sin cargos, el formato aplica a todo el departamento. Con cargos, '
        'solo lo ven al iniciar la visita quienes tengan uno de ellos.',
        style: TextStyle(fontSize: 12, color: Colors.black54),
      ),
      if (_areaId.isEmpty)
        const Text(
          'Elige primero el departamento: los cargos salen de ahí.',
          style: TextStyle(fontSize: 12, color: Color(0xFFB45309)),
        )
      else if (_cargosEmpresa.isEmpty)
        const Text(
          'El departamento no tiene cargos en el maestro de cargos ni en las '
          'fichas del personal.',
          style: TextStyle(fontSize: 12, color: Color(0xFFB45309)),
        ),
      const SizedBox(height: 6),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final c in _cargos.toList()..sort())
            InputChip(
              label: Text(c),
              onDeleted: () => setState(() {
                _cargos.remove(c);
                _sucio = true;
              }),
            ),
          if (_cargos.isEmpty) const Chip(label: Text('Todo el departamento')),
        ],
      ),
      const SizedBox(height: 6),
      DropdownButtonFormField<String>(
        key: ValueKey('cargos-${_cargos.length}'),
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Agregar cargo',
          isDense: true,
        ),
        items: [
          for (final c in _cargosEmpresa)
            if (!_cargos.contains(c))
              DropdownMenuItem(value: c, child: Text(c)),
        ],
        onChanged: (c) {
          if (c != null) {
            setState(() {
              _cargos.add(c);
              _sucio = true;
            });
          }
        },
      ),
    ],
  );

  /// Código, versión y elaboración del documento, como el encabezado del
  /// Excel de SST. Con partes (una hoja por inspección) cada parte tiene el
  /// suyo.
  Widget _encabezadoInforme() {
    Widget campo(TextEditingController c, String label, {double w = 200}) =>
        SizedBox(
          width: w,
          child: TextField(
            controller: c,
            decoration: InputDecoration(labelText: label, isDense: true),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Encabezado del informe',
          style: TextStyle(fontFamily: _kFont, fontWeight: FontWeight.w800),
        ),
        const Text(
          'Va arriba de cada hoja del PDF, como en el formato SST: sistema de '
          'gestión, nombre, código, versión, página y elaboración.',
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          child: TextField(
            controller: _sistema,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              isDense: true,
              labelText: 'Sistema de gestión (primera línea)',
              hintText:
                  'SISTEMA DE GESTIÓN · ${_areaNombre.text.toUpperCase()}',
            ),
          ),
        ),
        const SizedBox(height: 6),
        if (_partes.isEmpty)
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              campo(_codigo, 'Código (ej. F-UT-CAL-01)'),
              campo(_versionDoc, 'Versión del documento', w: 170),
              campo(_elaboracion, 'Fecha de elaboración', w: 170),
            ],
          )
        else
          for (final p in _partes)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                spacing: 12,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.end,
                children: [
                  Chip(
                    avatar: const Icon(Icons.description_outlined, size: 16),
                    label: Text(p.codigo),
                  ),
                  campo(p.nombre, 'Nombre de la hoja', w: 280),
                  campo(p.version, 'Versión', w: 90),
                  campo(p.elaboracion, 'Elaboración', w: 130),
                ],
              ),
            ),
      ],
    );
  }

  Widget _barraPreguntas() => Wrap(
    spacing: 8,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    alignment: WrapAlignment.spaceBetween,
    children: [
      Text(
        'Preguntas (${_items.length})',
        style: const TextStyle(
          fontFamily: _kFont,
          fontWeight: FontWeight.w800,
          fontSize: 15,
        ),
      ),
      SegmentedButton<_Vista>(
        segments: const [
          ButtonSegment(
            value: _Vista.tarjetas,
            icon: Icon(Icons.view_agenda_outlined, size: 18),
            label: Text('Tarjetas'),
          ),
          ButtonSegment(
            value: _Vista.tabla,
            icon: Icon(Icons.grid_on_outlined, size: 18),
            label: Text('Tabla (Excel)'),
          ),
        ],
        selected: {_vista},
        onSelectionChanged: (s) => setState(() => _vista = s.first),
      ),
    ],
  );

  Widget _botonesAgregar() => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: _kColor),
        onPressed: () => _agregarPregunta(
          seccion: _items.isEmpty ? '' : _items.last.seccion.text.trim(),
          parte: _items.isEmpty ? '' : _items.last.parte,
        ),
        icon: const Icon(Icons.add_circle_outline),
        label: const Text('Pregunta'),
      ),
      OutlinedButton.icon(
        onPressed: _agregarSeccion,
        icon: const Icon(Icons.view_stream_outlined),
        label: const Text('Sección'),
      ),
      OutlinedButton.icon(
        onPressed: _pegarDesdeExcel,
        icon: const Icon(Icons.content_paste_go_outlined),
        label: const Text('Pegar desde Excel'),
      ),
      OutlinedButton.icon(
        onPressed: _agregarDesdeExcel,
        icon: const Icon(Icons.upload_file_outlined),
        label: const Text('Agregar desde un Excel'),
      ),
      OutlinedButton.icon(
        onPressed: () => _editarTabla(null),
        icon: const Icon(Icons.table_chart_outlined),
        label: const Text('Tabla'),
      ),
    ],
  );

  // ── Vista tarjetas ─────────────────────────────────────────────────────

  Widget _tarjetaPregunta(int i) {
    final it = _items[i];
    final nuevaSeccion =
        i == 0 || _items[i - 1].seccion.text.trim() != it.seccion.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (nuevaSeccion && it.seccion.text.trim().isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: _kColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              it.seccion.text.trim().toUpperCase(),
              style: const TextStyle(
                fontFamily: _kFont,
                color: Colors.white,
                fontWeight: FontWeight.w800,
                letterSpacing: .5,
              ),
            ),
          ),
        Card(
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: it.texto.text.trim().isEmpty
                  ? const Color(0xFFDC2626)
                  : Colors.transparent,
            ),
          ),
          child: Container(
            decoration: const BoxDecoration(
              border: Border(left: BorderSide(color: _kColor, width: 5)),
            ),
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: _kColor.withValues(alpha: .12),
                      child: Text(
                        '${i + 1}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: _kColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: it.texto,
                        minLines: 1,
                        maxLines: 4,
                        textCapitalization: TextCapitalization.sentences,
                        style: const TextStyle(
                          fontFamily: _kFont,
                          fontWeight: FontWeight.w700,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Pregunta',
                          hintText: '¿Qué se revisa?',
                          filled: true,
                          fillColor: Color(0xFFF8F7FC),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    SizedBox(width: 300, child: _selectorTipo(it)),
                    SizedBox(width: 260, child: _campoSeccion(it)),
                    if (_partes.isNotEmpty)
                      SizedBox(
                        width: 200,
                        child: DropdownButtonFormField<String>(
                          initialValue: _partes.any((p) => p.codigo == it.parte)
                              ? it.parte
                              : null,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Hoja',
                            isDense: true,
                          ),
                          items: [
                            for (final p in _partes)
                              DropdownMenuItem(
                                value: p.codigo,
                                child: Text(p.codigo),
                              ),
                          ],
                          onChanged: (v) => setState(() {
                            it.parte = v ?? '';
                            _sucio = true;
                          }),
                        ),
                      ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    kItemTiposAyuda[it.tipo] ?? '',
                    style: const TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                ),
                if (it.tipo == kItemTipoOpcion) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: it.opciones,
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'Opciones, separadas por punto y coma',
                      hintText: 'Excelente; Bueno; Regular; Malo',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ],
                if (it.tipo == kItemTipoElemento) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: it.unidad,
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'Cantidad esperada',
                      hintText: '1 paquete x 20',
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                _vistaPrevia(it),
                if (it.mostrarAyuda) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: it.ayuda,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'Ayuda para el profesional',
                      hintText: 'Qué mirar o cómo medir',
                    ),
                  ),
                ],
                const Divider(height: 18),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  runSpacing: 4,
                  children: [
                    Wrap(
                      spacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (it.califica)
                          _interruptor(
                            'Foto obligatoria si no cumple',
                            it.requiereEvidencia,
                            (v) => it.requiereEvidencia = v,
                          )
                        else
                          _interruptor(
                            'Obligatoria',
                            it.obligatoria,
                            (v) => it.obligatoria = v,
                          ),
                        TextButton.icon(
                          onPressed: () => setState(
                            () => it.mostrarAyuda = !it.mostrarAyuda,
                          ),
                          icon: const Icon(Icons.help_outline, size: 16),
                          label: Text(
                            it.mostrarAyuda ? 'Quitar ayuda' : 'Agregar ayuda',
                          ),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Subir',
                          icon: const Icon(Icons.arrow_upward, size: 18),
                          onPressed: i == 0 ? null : () => _mover(i, i - 1),
                        ),
                        IconButton(
                          tooltip: 'Bajar',
                          icon: const Icon(Icons.arrow_downward, size: 18),
                          onPressed: i == _items.length - 1
                              ? null
                              : () => _mover(i, i + 1),
                        ),
                        IconButton(
                          tooltip: 'Duplicar',
                          icon: const Icon(Icons.copy_all_outlined, size: 18),
                          onPressed: () => _duplicar(i),
                        ),
                        IconButton(
                          tooltip: 'Eliminar',
                          icon: const Icon(Icons.delete_outline, size: 18),
                          onPressed: () => _eliminar(i),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _interruptor(String texto, bool valor, ValueChanged<bool> cambiar) =>
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Switch(
            value: valor,
            activeThumbColor: _kColor,
            onChanged: (v) => setState(() {
              cambiar(v);
              _sucio = true;
            }),
          ),
          // En un teléfono angosto el texto baja de línea en vez de salirse.
          Flexible(child: Text(texto, style: const TextStyle(fontSize: 12))),
        ],
      );

  Widget _selectorTipo(_ItemEdit it, {bool compacto = false}) =>
      DropdownButtonFormField<String>(
        initialValue: it.tipo,
        isExpanded: true,
        isDense: true,
        decoration: InputDecoration(
          isDense: true,
          labelText: compacto ? null : 'Tipo de respuesta',
          border: compacto ? InputBorder.none : null,
        ),
        items: [
          for (final e in kItemTiposLabel.entries)
            DropdownMenuItem(
              value: e.key,
              child: Row(
                children: [
                  Icon(iconoTipoPregunta(e.key), size: 18, color: _kColor),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      e.value,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
        ],
        onChanged: (v) => setState(() {
          it.tipo = v ?? kItemTipoCalificacion;
          _sucio = true;
        }),
      );

  Widget _campoSeccion(_ItemEdit it, {bool compacto = false}) {
    final secciones = _secciones;
    return TextField(
      controller: it.seccion,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        isDense: true,
        labelText: compacto ? null : 'Sección',
        border: compacto ? InputBorder.none : null,
        suffixIcon: secciones.isEmpty
            ? null
            : PopupMenuButton<String>(
                tooltip: 'Elegir una sección que ya existe',
                icon: const Icon(Icons.arrow_drop_down),
                itemBuilder: (_) => [
                  for (final s in secciones)
                    PopupMenuItem(value: s, child: Text(s)),
                ],
                onSelected: (s) => setState(() => it.seccion.text = s),
              ),
      ),
      onChanged: (_) => setState(() {}),
    );
  }

  /// Cómo lo verá el profesional, como la vista previa de Google Forms.
  Widget _vistaPrevia(_ItemEdit it) {
    Widget chip(String t) => Padding(
      padding: const EdgeInsets.only(right: 6, bottom: 4),
      child: Chip(
        label: Text(t, style: const TextStyle(fontSize: 12)),
        visualDensity: VisualDensity.compact,
        backgroundColor: Colors.white,
        side: const BorderSide(color: Colors.black26),
      ),
    );
    Widget caja(String t, {IconData? icono, double ancho = 220}) => Container(
      width: ancho,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.black38)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              t,
              style: const TextStyle(fontSize: 12, color: Colors.black45),
            ),
          ),
          if (icono != null) Icon(icono, size: 16, color: Colors.black38),
        ],
      ),
    );
    final opciones = [
      for (final o in it.opciones.text.split(';'))
        if (o.trim().isNotEmpty) o.trim(),
    ];
    final contenido = switch (it.tipo) {
      kItemTipoCalificacion => Wrap(
        children: [chip('Cumple (1)'), chip('No cumple (0)'), chip('NA')],
      ),
      kItemTipoSiNo => Wrap(children: [chip('Sí'), chip('No')]),
      kItemTipoElemento => Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          chip('Sí'),
          chip('No'),
          caja('Cantidad', ancho: 110),
          caja('Vence', icono: Icons.event, ancho: 110),
        ],
      ),
      kItemTipoOpcion => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final o
              in (opciones.isEmpty ? ['Opción 1', 'Opción 2'] : opciones))
            Row(
              children: [
                const Icon(
                  Icons.radio_button_unchecked,
                  size: 16,
                  color: Colors.black38,
                ),
                const SizedBox(width: 6),
                Text(o, style: const TextStyle(fontSize: 12)),
              ],
            ),
        ],
      ),
      kItemTipoTexto => caja('Respuesta corta'),
      kItemTipoParrafo => caja('Respuesta larga', ancho: 400),
      kItemTipoNumero => caja('0', ancho: 120),
      kItemTipoFecha => caja('dd/mm/aaaa', icono: Icons.event, ancho: 160),
      _ => const SizedBox.shrink(),
    };
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F7FC),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Así lo verá el profesional',
            style: TextStyle(fontSize: 10, color: Colors.black45),
          ),
          const SizedBox(height: 4),
          contenido,
        ],
      ),
    );
  }

  // ── Vista tabla (Excel) ────────────────────────────────────────────────

  Widget _tablaExcel(int desde, int cuantos) {
    Widget celda(Widget child, {double w = 160}) =>
        SizedBox(width: w, child: child);
    InputDecoration deco(String hint) => InputDecoration(
      isDense: true,
      hintText: hint,
      border: InputBorder.none,
    );
    return Card(
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(
            _kColor.withValues(alpha: .1),
          ),
          columnSpacing: 12,
          dataRowMinHeight: 52,
          dataRowMaxHeight: 96,
          columns: [
            const DataColumn(label: Text('#')),
            const DataColumn(label: Text('Sección')),
            const DataColumn(label: Text('Pregunta')),
            const DataColumn(label: Text('Tipo de respuesta')),
            const DataColumn(label: Text('Opciones / cantidad esperada')),
            const DataColumn(label: Text('Obligatoria')),
            const DataColumn(label: Text('Foto si no cumple')),
            if (_partes.isNotEmpty) const DataColumn(label: Text('Hoja')),
            const DataColumn(label: Text('')),
          ],
          rows: [
            for (var i = desde; i < desde + cuantos; i++)
              DataRow(
                color: WidgetStateProperty.all(
                  _items[i].texto.text.trim().isEmpty
                      ? const Color(0xFFFEF2F2)
                      : null,
                ),
                cells: [
                  DataCell(Text('${i + 1}')),
                  DataCell(
                    celda(_campoSeccion(_items[i], compacto: true), w: 170),
                  ),
                  DataCell(
                    celda(
                      TextField(
                        controller: _items[i].texto,
                        maxLines: 3,
                        minLines: 1,
                        decoration: deco('¿Qué se revisa?'),
                      ),
                      w: 360,
                    ),
                  ),
                  DataCell(
                    celda(_selectorTipo(_items[i], compacto: true), w: 260),
                  ),
                  DataCell(
                    celda(
                      _items[i].tipo == kItemTipoOpcion
                          ? TextField(
                              controller: _items[i].opciones,
                              decoration: deco('Opción 1; Opción 2'),
                            )
                          : _items[i].tipo == kItemTipoElemento
                          ? TextField(
                              controller: _items[i].unidad,
                              decoration: deco('1 paquete x 20'),
                            )
                          : const Text(
                              '—',
                              style: TextStyle(color: Colors.black38),
                            ),
                      w: 190,
                    ),
                  ),
                  DataCell(
                    Checkbox(
                      value: _items[i].califica || _items[i].obligatoria,
                      onChanged: _items[i].califica
                          ? null
                          : (v) => setState(() {
                              _items[i].obligatoria = v ?? true;
                              _sucio = true;
                            }),
                    ),
                  ),
                  DataCell(
                    Checkbox(
                      value: _items[i].califica && _items[i].requiereEvidencia,
                      onChanged: !_items[i].califica
                          ? null
                          : (v) => setState(() {
                              _items[i].requiereEvidencia = v ?? false;
                              _sucio = true;
                            }),
                    ),
                  ),
                  if (_partes.isNotEmpty)
                    DataCell(
                      DropdownButton<String>(
                        value: _partes.any((p) => p.codigo == _items[i].parte)
                            ? _items[i].parte
                            : null,
                        underline: const SizedBox.shrink(),
                        items: [
                          for (final p in _partes)
                            DropdownMenuItem(
                              value: p.codigo,
                              child: Text(p.codigo),
                            ),
                        ],
                        onChanged: (v) => setState(() {
                          _items[i].parte = v ?? '';
                          _sucio = true;
                        }),
                      ),
                    ),
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Subir',
                          icon: const Icon(Icons.arrow_upward, size: 16),
                          onPressed: i == 0 ? null : () => _mover(i, i - 1),
                        ),
                        IconButton(
                          tooltip: 'Bajar',
                          icon: const Icon(Icons.arrow_downward, size: 16),
                          onPressed: i == _items.length - 1
                              ? null
                              : () => _mover(i, i + 1),
                        ),
                        IconButton(
                          tooltip: 'Duplicar',
                          icon: const Icon(Icons.copy_all_outlined, size: 16),
                          onPressed: () => _duplicar(i),
                        ),
                        IconButton(
                          tooltip: 'Eliminar',
                          icon: const Icon(Icons.delete_outline, size: 16),
                          onPressed: () => _eliminar(i),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  // ── Tablas del formato ─────────────────────────────────────────────────

  Widget _seccionTablas() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          const Expanded(
            child: Text(
              'Tablas del formato',
              style: TextStyle(
                fontFamily: _kFont,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: () => _editarTabla(null),
            icon: const Icon(Icons.add),
            label: const Text('Tabla'),
          ),
        ],
      ),
      const Text(
        'Una tabla califica varias cosas por fila: un extintor por fila con '
        'su ubicación y el estado de cada parte, o las áreas del '
        'establecimiento (Cocina, Bodega…) con su limpieza y orden. En la '
        'visita, cada tabla es su propia página.',
        style: TextStyle(fontSize: 12, color: Colors.black54),
      ),
      const SizedBox(height: 8),
      if (_tablas.isEmpty)
        const Padding(
          padding: EdgeInsets.all(8),
          child: Text(
            'Este formato no tiene tablas.',
            style: TextStyle(color: Colors.black45),
          ),
        ),
      for (var i = 0; i < _tablas.length; i++) _tarjetaTabla(i),
    ],
  );

  Widget _tarjetaTabla(int i) {
    final t = _tablas[i];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.table_chart_outlined, color: _kColor),
        title: Text(
          t.nombre,
          style: const TextStyle(
            fontFamily: _kFont,
            fontWeight: FontWeight.w800,
          ),
        ),
        subtitle: Text(
          [
            if (t.conFilasFijas)
              'Filas: ${t.filasFijas.join(', ')}'
            else
              'El profesional agrega un(a) ${t.etiquetaFila.toLowerCase()} por fila',
            if (t.camposTexto.isNotEmpty)
              'Escribe: ${t.camposTexto.map((c) => c.label).join(', ')}',
            'Califica: ${t.camposEstado.map((c) => c.label).join(', ')}',
            'Escala: ${kEscalasLabel[t.escala]}',
            if (t.parte.isNotEmpty) 'Hoja ${t.parte}',
          ].join('\n'),
          style: const TextStyle(fontSize: 12),
        ),
        isThreeLine: true,
        trailing: Wrap(
          children: [
            IconButton(
              tooltip: 'Editar tabla',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _editarTabla(i),
            ),
            IconButton(
              tooltip: 'Eliminar tabla',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => setState(() {
                _tablas.removeAt(i);
                _sucio = true;
              }),
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemEdit {
  final String id;
  final TextEditingController seccion;
  final TextEditingController texto;
  final TextEditingController unidad;
  final TextEditingController opciones;
  final TextEditingController ayuda;
  bool requiereEvidencia;
  bool obligatoria;
  bool mostrarAyuda;
  String tipo;
  String parte;

  _ItemEdit({
    required this.id,
    required String seccion,
    required String texto,
    required this.requiereEvidencia,
    required VoidCallback onChange,
    this.tipo = kItemTipoCalificacion,
    this.parte = '',
    this.obligatoria = true,
    String unidad = '',
    String opciones = '',
    String ayuda = '',
  }) : seccion = TextEditingController(text: seccion)..addListener(onChange),
       texto = TextEditingController(text: texto)..addListener(onChange),
       unidad = TextEditingController(text: unidad)..addListener(onChange),
       opciones = TextEditingController(text: opciones)..addListener(onChange),
       ayuda = TextEditingController(text: ayuda)..addListener(onChange),
       mostrarAyuda = ayuda.isNotEmpty;

  bool get califica => itemCalifica(tipo);

  factory _ItemEdit.de(VisitaFormatoItem it, VoidCallback onChange) =>
      _ItemEdit(
        id: it.id,
        seccion: it.seccion,
        texto: it.texto,
        requiereEvidencia: it.requiereEvidencia,
        onChange: onChange,
        tipo: it.tipo,
        parte: it.parte,
        obligatoria: it.obligatoria,
        unidad: it.unidad,
        opciones: it.opciones.join('; '),
        ayuda: it.ayuda,
      );

  factory _ItemEdit.nuevo(
    VoidCallback onChange, {
    String seccion = '',
    String parte = '',
  }) => _ItemEdit(
    id: _nuevoId('it'),
    seccion: seccion,
    texto: '',
    requiereEvidencia: false,
    onChange: onChange,
    parte: parte,
  );

  _ItemEdit copia(VoidCallback onChange) => _ItemEdit(
    id: _nuevoId('it'),
    seccion: seccion.text,
    texto: texto.text,
    requiereEvidencia: requiereEvidencia,
    onChange: onChange,
    tipo: tipo,
    parte: parte,
    obligatoria: obligatoria,
    unidad: unidad.text,
    opciones: opciones.text,
    ayuda: ayuda.text,
  );

  VisitaFormatoItem aItem(int orden) => VisitaFormatoItem(
    id: id,
    orden: orden,
    seccion: seccion.text.trim(),
    texto: texto.text.trim(),
    requiereEvidencia: califica && requiereEvidencia,
    tipo: tipo,
    parte: parte,
    unidad: tipo == kItemTipoElemento ? unidad.text.trim() : '',
    opciones: tipo == kItemTipoOpcion
        ? [
            for (final o in opciones.text.split(';'))
              if (o.trim().isNotEmpty) o.trim(),
          ]
        : const [],
    obligatoria: califica || obligatoria,
    ayuda: mostrarAyuda ? ayuda.text.trim() : '',
  );

  void dispose() {
    seccion.dispose();
    texto.dispose();
    unidad.dispose();
    opciones.dispose();
    ayuda.dispose();
  }
}

class _ParteEdit {
  final String codigo;
  final TextEditingController nombre;
  final TextEditingController version;
  final TextEditingController elaboracion;

  _ParteEdit(
    this.codigo, {
    required String nombre,
    required String version,
    required String elaboracion,
    required VoidCallback onChange,
  }) : nombre = TextEditingController(text: nombre)..addListener(onChange),
       version = TextEditingController(text: version)..addListener(onChange),
       elaboracion = TextEditingController(text: elaboracion)
         ..addListener(onChange);

  factory _ParteEdit.de(VisitaFormatoParte p, VoidCallback onChange) =>
      _ParteEdit(
        p.codigo,
        nombre: p.nombre,
        version: p.version,
        elaboracion: p.elaboracion,
        onChange: onChange,
      );

  VisitaFormatoParte aParte() => VisitaFormatoParte(
    codigo: codigo,
    nombre: nombre.text.trim(),
    version: version.text.trim().isEmpty ? '1' : version.text.trim(),
    elaboracion: elaboracion.text.trim(),
  );

  void dispose() {
    nombre.dispose();
    version.dispose();
    elaboracion.dispose();
  }
}

/// Crea o edita una tabla del formato: nombre, cómo se llama cada fila,
/// columnas que se escriben, columnas que se califican, escala y filas
/// fijas.
class _TablaEditorDialog extends StatefulWidget {
  final VisitaFormatoTabla? tabla;
  final List<String> partes;
  final String parteDefecto;
  const _TablaEditorDialog({
    required this.tabla,
    required this.partes,
    required this.parteDefecto,
  });

  @override
  State<_TablaEditorDialog> createState() => _TablaEditorDialogState();
}

class _TablaEditorDialogState extends State<_TablaEditorDialog> {
  late final TextEditingController _nombre;
  late final TextEditingController _fila;
  late String _escala;
  late String _parte;
  late List<VisitaTablaCampo> _texto;
  late List<VisitaTablaCampo> _estado;
  late List<String> _fijas;
  bool _conFijas = false;

  @override
  void initState() {
    super.initState();
    final t = widget.tabla;
    _nombre = TextEditingController(text: t?.nombre ?? '');
    _fila = TextEditingController(text: t?.etiquetaFila ?? 'Fila');
    _escala = t?.escala ?? kEscalaBmrnc;
    _parte = t?.parte ?? widget.parteDefecto;
    _texto = [...?t?.camposTexto];
    _estado = [...?t?.camposEstado];
    _fijas = [...?t?.filasFijas];
    _conFijas = _fijas.isNotEmpty;
  }

  @override
  void dispose() {
    _nombre.dispose();
    _fila.dispose();
    super.dispose();
  }

  /// Id de columna que no choque con ninguna de la tabla.
  String _idColumna(String prefijo) {
    final usados = {
      for (final c in [..._texto, ..._estado]) c.id,
    };
    var n = usados.length + 1;
    while (usados.contains('$prefijo$n')) {
      n++;
    }
    return '$prefijo$n';
  }

  Future<String?> _pedirTexto(String titulo, {String inicial = ''}) async {
    final c = TextEditingController(text: inicial);
    final r = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(titulo),
        content: TextField(
          controller: c,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (v) => Navigator.pop(context, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _kColor),
            onPressed: () => Navigator.pop(context, c.text.trim()),
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
    c.dispose();
    return (r == null || r.isEmpty) ? null : r;
  }

  Widget _lista({
    required String titulo,
    required String ayuda,
    required List<String> valores,
    required VoidCallback onAgregar,
    required void Function(int) onQuitar,
    required void Function(int) onEditar,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(titulo, style: const TextStyle(fontWeight: FontWeight.w800)),
      Text(ayuda, style: const TextStyle(fontSize: 11, color: Colors.black54)),
      const SizedBox(height: 4),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (var i = 0; i < valores.length; i++)
            InputChip(
              label: Text(valores[i]),
              onPressed: () => onEditar(i),
              onDeleted: () => onQuitar(i),
            ),
          ActionChip(
            avatar: const Icon(Icons.add, size: 16),
            label: const Text('Agregar'),
            onPressed: onAgregar,
          ),
        ],
      ),
    ],
  );

  void _guardar() {
    final nombre = _nombre.text.trim();
    if (nombre.isEmpty) {
      _snack(context, 'Escribe el nombre de la tabla.', error: true);
      return;
    }
    if (_estado.isEmpty) {
      _snack(
        context,
        'Agrega al menos una columna para calificar.',
        error: true,
      );
      return;
    }
    if (_conFijas && _fijas.isEmpty) {
      _snack(context, 'Escribe las filas fijas o apágalas.', error: true);
      return;
    }
    Navigator.pop(
      context,
      VisitaFormatoTabla(
        id: widget.tabla?.id ?? _nuevoId('tabla'),
        parte: _parte,
        nombre: nombre,
        etiquetaFila: _fila.text.trim().isEmpty ? 'Fila' : _fila.text.trim(),
        camposTexto: _texto,
        camposEstado: _estado,
        escala: _escala,
        filasFijas: _conFijas ? _fijas : const [],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ancho = MediaQuery.of(context).size.width;
    return AlertDialog(
      title: Text(widget.tabla == null ? 'Nueva tabla' : 'Editar tabla'),
      content: SizedBox(
        width: ancho < 640 ? ancho : 580,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _nombre,
                autofocus: widget.tabla == null,
                decoration: const InputDecoration(
                  labelText: 'Nombre de la tabla',
                  hintText: 'Extintores, Áreas del establecimiento',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _fila,
                decoration: const InputDecoration(
                  labelText: 'Cada fila es un(a)',
                  hintText: 'Extintor, Área, Equipo',
                ),
              ),
              if (widget.partes.isNotEmpty) ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: widget.partes.contains(_parte) ? _parte : null,
                  decoration: const InputDecoration(labelText: 'Hoja'),
                  items: [
                    for (final p in widget.partes)
                      DropdownMenuItem(value: p, child: Text(p)),
                  ],
                  onChanged: (v) => setState(() => _parte = v ?? ''),
                ),
              ],
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _escala,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Con qué se califica cada columna',
                ),
                items: [
                  for (final e in kEscalasLabel.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => setState(() => _escala = v ?? kEscalaBmrnc),
              ),
              const SizedBox(height: 14),
              _lista(
                titulo: 'Columnas para escribir',
                ayuda: 'Datos que se anotan en cada fila: Ubicación, Tipo…',
                valores: [for (final c in _texto) c.label],
                onAgregar: () async {
                  final l = await _pedirTexto('Columna para escribir');
                  if (l != null) {
                    setState(
                      () => _texto.add(VisitaTablaCampo(_idColumna('c'), l)),
                    );
                  }
                },
                onQuitar: (i) => setState(() => _texto.removeAt(i)),
                onEditar: (i) async {
                  final l = await _pedirTexto(
                    'Columna para escribir',
                    inicial: _texto[i].label,
                  );
                  if (l != null) {
                    setState(
                      () => _texto[i] = VisitaTablaCampo(_texto[i].id, l),
                    );
                  }
                },
              ),
              const SizedBox(height: 14),
              _lista(
                titulo: 'Columnas para calificar',
                ayuda: 'Lo que se califica en cada fila con la escala elegida.',
                valores: [for (final c in _estado) c.label],
                onAgregar: () async {
                  final l = await _pedirTexto('Columna para calificar');
                  if (l != null) {
                    setState(
                      () => _estado.add(VisitaTablaCampo(_idColumna('e'), l)),
                    );
                  }
                },
                onQuitar: (i) => setState(() => _estado.removeAt(i)),
                onEditar: (i) async {
                  final l = await _pedirTexto(
                    'Columna para calificar',
                    inicial: _estado[i].label,
                  );
                  if (l != null) {
                    setState(
                      () => _estado[i] = VisitaTablaCampo(_estado[i].id, l),
                    );
                  }
                },
              ),
              const SizedBox(height: 10),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Filas fijas (como una cuadrícula)'),
                subtitle: const Text(
                  'Encendido: el profesional califica las filas que escribas. '
                  'Apagado: agrega una fila por cada equipo que encuentre.',
                  style: TextStyle(fontSize: 11),
                ),
                value: _conFijas,
                onChanged: (v) => setState(() => _conFijas = v),
              ),
              if (_conFijas)
                _lista(
                  titulo: 'Filas',
                  ayuda: 'Cocina, Bodega, Comedor, Baños…',
                  valores: _fijas,
                  onAgregar: () async {
                    final l = await _pedirTexto('Nueva fila');
                    if (l != null && !_fijas.contains(l)) {
                      setState(() => _fijas.add(l));
                    }
                  },
                  onQuitar: (i) => setState(() => _fijas.removeAt(i)),
                  onEditar: (i) async {
                    final l = await _pedirTexto('Fila', inicial: _fijas[i]);
                    if (l != null) setState(() => _fijas[i] = l);
                  },
                ),
              const SizedBox(height: 8),
              Text(
                'En la visita: ${leyendaEscala(_escala)}',
                style: const TextStyle(fontSize: 11, color: Colors.black54),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: _kColor),
          onPressed: _guardar,
          child: const Text('Guardar tabla'),
        ),
      ],
    );
  }
}
