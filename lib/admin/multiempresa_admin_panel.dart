// lib/admin/multiempresa_admin_panel.dart
//
// Admin › Multiempresa: cómo está cada persona en cada una de sus empresas
// (área, cargo, centro de costos, centros de operación y de trabajo, jefe y
// estado) y las herramientas para dejarla igual en todas:
//
//   * Sincronizar una persona tomando una empresa de referencia.
//   * Sincronizar en lote a todos los descuadrados del filtro.
//   * Agregar personas a otra empresa con su cargo y área, sin trasladar a
//     todo el personal.
//   * Enviar el catálogo (áreas, cargos, centros) de una empresa a otra.
//   * Traslado de personal: por persona o con filtros, quién queda solo en
//     la empresa nueva, en las dos o solo en la antigua (pantalla aparte,
//     `multiempresa_traslado_screen.dart`).
//
// La lógica vive en `core/multiempresa_sync.dart`; aquí solo se muestra y se
// confirma. Web y móvil comparten todo salvo el detalle por empresa: en
// pantalla ancha es una tabla, en angosta una tarjeta por empresa.

import 'package:flutter/material.dart';

import '../core/app_catalog.dart';
import '../core/area_directory.dart';
import '../core/multiempresa_sync.dart';
import '../core/user_directory.dart';
import '../widgets/paged_list.dart';
import '../utils/user_company.dart';
import '../widgets/user_avatar.dart';
import 'admin_repository.dart';
import 'multiempresa_sync_service.dart';
import 'multiempresa_traslado_screen.dart';

const String _kFont = 'Arial';
const Color _kAccent = Color(0xFF3B82F6);
const Color _kBorder = Color(0xFFE2E8F0);
const Color _kMuted = Color(0xFF64748B);
const Color _kOk = Color(0xFF10B981);
const Color _kWarn = Color(0xFFD97706);
const Color _kWarnBg = Color(0xFFFFF7ED);

enum _Vista { varias, descuadradas, modulos, todas }

extension on _Vista {
  String get etiqueta => switch (this) {
    _Vista.varias => 'En varias empresas',
    _Vista.descuadradas => 'Con descuadres',
    _Vista.modulos => 'Módulos de otra empresa',
    _Vista.todas => 'Todo el personal',
  };
}

/// Valor especial del selector de referencia en lote.
const String _kReferenciaPrincipal = '__principal__';

class AdminMultiempresaPanel extends StatefulWidget {
  final String userId;
  final String empresaId;
  final List<EmpresaItem> empresas;

  /// Para pruebas; por defecto usa Firestore.
  final MultiempresaSyncService? servicio;

  const AdminMultiempresaPanel({
    super.key,
    required this.userId,
    required this.empresaId,
    required this.empresas,
    this.servicio,
  });

  @override
  State<AdminMultiempresaPanel> createState() => _AdminMultiempresaPanelState();
}

class _AdminMultiempresaPanelState extends State<AdminMultiempresaPanel> {
  late final MultiempresaSyncService _svc =
      widget.servicio ?? MultiempresaSyncService();

  MultiempresaDatos? _datos;
  List<PersonaMultiempresa> _personas = const [];
  Map<String, String> _nombres = const {};
  bool _cargando = false;
  bool _ocupado = false;
  String? _progreso;
  String? _error;

  String _busqueda = '';
  _Vista _vista = _Vista.varias;
  String? _empresaFiltro;
  String? _areaFiltro;
  String? _cargoFiltro;
  final Set<String> _seleccion = {};
  final Set<String> _expandidas = {};

  String? _catOrigen;
  String? _catDestino;
  final Set<TipoCatalogo> _catTipos = {TipoCatalogo.area, TipoCatalogo.cargo};

  @override
  void initState() {
    super.initState();
    _catOrigen = widget.empresaId;
    _cargar();
  }

  // ─── Datos ────────────────────────────────────────────────────────────────

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final datos = await _svc.cargar(
        empresas: widget.empresas.map((e) => e.empresaId),
        nombresEmpresa: _nombresEmpresa,
      );
      final personas = datos.personas();
      final nombres = <String, String>{
        for (final p in personas)
          p.cedula: UserDirectory.instance
              .fromUsuario(p.cedula, datos.usuarios[p.cedula]!)
              .displayName,
      };
      personas.sort(
        (a, b) => (nombres[a.cedula] ?? a.cedula).toLowerCase().compareTo(
          (nombres[b.cedula] ?? b.cedula).toLowerCase(),
        ),
      );
      if (!mounted) return;
      setState(() {
        _datos = datos;
        _personas = personas;
        _nombres = nombres;
        _cargando = false;
        _seleccion.removeWhere((c) => !nombres.containsKey(c));
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = '$e';
      });
    }
  }

  String _empresa(String id) {
    for (final e in widget.empresas) {
      if (e.empresaId == id) return e.nombre.isEmpty ? id : e.nombre;
    }
    return id;
  }

  Map<String, String> get _nombresEmpresa => {
    for (final e in widget.empresas) e.empresaId: e.nombre,
  };

  String _nombre(String cedula) => _nombres[cedula] ?? cedula;

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ─── Filtros ──────────────────────────────────────────────────────────────

  Iterable<PuestoEmpresa> _puestosFiltrables(PersonaMultiempresa p) =>
      _empresaFiltro == null
      ? p.puestos
      : p.puestos.where((x) => x.empresaId == _empresaFiltro);

  AreaCatalogo get _areas => AreaCatalogo.desde([
    for (final p in _personas)
      for (final x in p.puestos)
        if (!x.area.vacio)
          (
            id:
                x.area.entrada?.id ??
                (x.area.id.isNotEmpty ? x.area.id : x.area.nombre),
            nombre: x.area.nombre,
          ),
  ]);

  Map<String, String> get _cargos {
    final out = <String, String>{};
    for (final p in _personas) {
      for (final x in p.puestos) {
        if (x.cargo.vacio) continue;
        out.putIfAbsent(x.cargo.clave, () => x.cargo.nombre);
      }
    }
    final orden = out.entries.toList()
      ..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));
    return Map.fromEntries(orden);
  }

  List<PersonaMultiempresa> _filtrar(AreaCatalogo areas) {
    final q = claveCatalogo(_busqueda);
    final area = _areaFiltro == null
        ? null
        : areas.opciones.where((o) => o.id == _areaFiltro).firstOrNull;
    return _personas.where((p) {
      switch (_vista) {
        case _Vista.varias:
          if (p.puestos.length < 2) return false;
        case _Vista.descuadradas:
          if (p.sincronizada) return false;
        case _Vista.modulos:
          if (p.conModulosHeredados.isEmpty) return false;
        case _Vista.todas:
          break;
      }
      if (_empresaFiltro != null && p.puesto(_empresaFiltro!) == null) {
        return false;
      }
      final puestos = _puestosFiltrables(p);
      if (area != null &&
          !puestos.any(
            (x) =>
                area.contiene(x.area.entrada?.id) ||
                area.contiene(x.area.id) ||
                area.contiene(x.area.nombre),
          )) {
        return false;
      }
      if (_cargoFiltro != null &&
          !puestos.any((x) => x.cargo.clave == _cargoFiltro)) {
        return false;
      }
      if (q.isNotEmpty &&
          !claveCatalogo(_nombre(p.cedula)).contains(q) &&
          !p.cedula.contains(_busqueda.trim())) {
        return false;
      }
      return true;
    }).toList();
  }

  // ─── Construcción ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final areas = _areas;
    final filtradas = _filtrar(areas);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _encabezado(),
        const SizedBox(height: 12),
        if (_error != null)
          _aviso(
            'No se pudo cargar: $_error',
            icono: Icons.error_outline,
            color: Colors.red,
          ),
        if (_cargando && _datos == null)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (_datos != null) ...[
          _resumen(),
          const SizedBox(height: 12),
          _tarjetaTraslado(),
          const SizedBox(height: 12),
          _tarjetaCatalogo(),
          const SizedBox(height: 12),
          _tarjetaModulos(),
          const SizedBox(height: 12),
          _filtros(areas),
          const SizedBox(height: 8),
          _accionesLote(filtradas),
          if (_progreso != null) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(),
            const SizedBox(height: 4),
            Text(_progreso!, style: _estilo(12, color: _kMuted)),
          ],
          const SizedBox(height: 8),
          if (filtradas.isEmpty)
            _aviso(
              'Nadie coincide con los filtros.',
              icono: Icons.search_off,
              color: _kMuted,
            )
          else
            PagedListSection<PersonaMultiempresa>(
              items: filtradas,
              etiqueta: 'personas',
              barraArriba: true,
              itemBuilder: (context, p, _) => _tarjetaPersona(p),
            ),
        ],
      ],
    );
  }

  TextStyle _estilo(
    double size, {
    FontWeight weight = FontWeight.w400,
    Color? color,
  }) => TextStyle(
    fontFamily: _kFont,
    fontSize: size,
    fontWeight: weight,
    color: color,
  );

  Widget _aviso(
    String texto, {
    required IconData icono,
    required Color color,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      children: [
        Icon(icono, color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(texto, style: _estilo(13, color: color)),
        ),
      ],
    ),
  );

  Widget _encabezado() => Card(
    color: const Color(0xFFEFF6FF),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: const BorderSide(color: Color(0xFFBFDBFE)),
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.hub_outlined, color: _kAccent, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Personal multiempresa',
                  style: _estilo(16, weight: FontWeight.w900),
                ),
              ),
              IconButton(
                tooltip: 'Volver a cargar',
                onPressed: _cargando || _ocupado ? null : _cargar,
                icon: _cargando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            MediaQuery.sizeOf(context).width >= 760
                ? 'Cómo está cada persona en cada una de sus empresas: área, '
                      'cargo, centro de costos, centros de operación y de '
                      'trabajo. Si una empresa no tiene el dato propio, o lo '
                      'tiene con un id de otra empresa, los módulos muestran '
                      'el cargo equivocado y los filtros la pierden. '
                      'Sincronizar copia el puesto de la empresa de '
                      'referencia al catálogo de cada empresa (por nombre, '
                      'sin duplicar).'
                : 'Área, cargo y centros de cada persona en cada empresa. '
                      'Sincroniza para que todas muestren lo mismo.',
            style: _estilo(13).copyWith(height: 1.4),
          ),
        ],
      ),
    ),
  );

  Widget _resumen() {
    final varias = _personas.where((p) => p.puestos.length > 1).length;
    final descuadradas = _personas.where((p) => !p.sincronizada).length;
    final multiDescuadradas = _personas
        .where((p) => p.puestos.length > 1 && !p.sincronizada)
        .length;
    Widget dato(String valor, String etiqueta, Color color, _Vista vista) =>
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => setState(() => _vista = vista),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _vista == vista ? color : _kBorder,
                width: _vista == vista ? 2 : 1,
              ),
              color: Colors.white,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  valor,
                  style: _estilo(20, weight: FontWeight.w900, color: color),
                ),
                Text(etiqueta, style: _estilo(11.5, color: _kMuted)),
              ],
            ),
          ),
        );
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        dato('$varias', 'en varias empresas', _kAccent, _Vista.varias),
        dato(
          '$descuadradas',
          multiDescuadradas == descuadradas
              ? 'con descuadres'
              : 'con descuadres ($multiDescuadradas multiempresa)',
          _kWarn,
          _Vista.descuadradas,
        ),
        dato(
          '${_personas.where((p) => p.conModulosHeredados.isNotEmpty).length}',
          'con módulos de otra empresa',
          _kWarn,
          _Vista.modulos,
        ),
        dato('${_personas.length}', 'personas en total', _kMuted, _Vista.todas),
      ],
    );
  }

  // ─── Traslado de personal ─────────────────────────────────────────────────

  Widget _tarjetaTraslado() {
    final ancho = MediaQuery.sizeOf(context).width >= 760;
    final texto = Text(
      ancho
          ? 'Pasa personal de una empresa a otra decidiendo por persona, o '
                'en lote con filtros de área, cargo y centro, si queda solo '
                'en la nueva, en las dos o solo en la antigua. Lleva su área, '
                'cargo, centros y módulos.'
          : 'Quién queda solo en la nueva, en las dos o solo en la antigua.',
      style: _estilo(12, color: _kMuted),
    );
    final boton = FilledButton.icon(
      onPressed: _ocupado || widget.empresas.length < 2
          ? null
          : _abrirTraslado,
      icon: const Icon(Icons.move_up_rounded),
      label: const Text('Trasladar personal'),
    );
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: _kBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: ancho
            ? Row(
                children: [
                  const Icon(Icons.move_up_rounded, color: _kAccent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Traslado de personal',
                          style: _estilo(14, weight: FontWeight.w900),
                        ),
                        const SizedBox(height: 2),
                        texto,
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  boton,
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.move_up_rounded, color: _kAccent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Traslado de personal',
                          style: _estilo(13.5, weight: FontWeight.w900),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  texto,
                  const SizedBox(height: 10),
                  SizedBox(width: double.infinity, child: boton),
                ],
              ),
      ),
    );
  }

  Future<void> _abrirTraslado() async {
    final datos = _datos;
    if (datos == null) return;
    final resultado = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => MultiempresaTrasladoScreen(
          userId: widget.userId,
          empresas: widget.empresas,
          datos: datos,
          personas: _personas,
          nombres: _nombres,
          servicio: _svc,
          origenInicial: widget.empresaId,
        ),
      ),
    );
    if (resultado == null || !mounted) return;
    _snack(resultado);
    await _cargar();
  }

  // ─── Módulos por empresa ──────────────────────────────────────────────────

  bool _quitarHeredados = false;

  Widget _tarjetaModulos() {
    final ancho = MediaQuery.sizeOf(context).width >= 760;
    final sinFijar = _personas.where((p) => !p.modulosFijados).toList();
    final conHeredados = _personas
        .where((p) => p.conModulosHeredados.isNotEmpty)
        .toList();
    final heredados = conHeredados.fold<int>(
      0,
      (n, p) =>
          n +
          p.conModulosHeredados.fold<int>(
            0,
            (m, x) => m + x.modulosHeredados.length,
          ),
    );
    const titulo = 'Módulos por empresa';
    final contenido = <Widget>[
      Text(
        'Antes cada empresa sumaba a sus módulos la lista general de la '
        'persona, así que un módulo dado en una empresa aparecía también en la '
        'otra. Fijar deja escrita la lista de cada empresa y desde ahí cada '
        'una ve solo la suya.',
        style: _estilo(12, color: _kMuted),
      ),
      const SizedBox(height: 10),
      Text(
        sinFijar.isEmpty
            ? 'Todo el personal ya tiene los módulos fijados por empresa.'
            : '${sinFijar.length} persona(s) sin fijar. '
                  '${conHeredados.length} ven $heredados módulo(s) que '
                  'llegan de otra empresa.',
        style: _estilo(13, weight: FontWeight.w700),
      ),
      if (sinFijar.isNotEmpty) ...[
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          value: _quitarHeredados,
          onChanged: (v) => setState(() => _quitarHeredados = v ?? false),
          title: Text(
            'Quitar los módulos que llegan de otra empresa',
            style: _estilo(13),
          ),
          subtitle: Text(
            _quitarHeredados
                ? 'Cada empresa queda solo con su lista. Revisa antes quién '
                      'los usa en la vista "Módulos de otra empresa".'
                : 'Nadie pierde nada: cada empresa queda con lo que la persona '
                      've hoy, y después se ajusta persona por persona.',
            style: _estilo(11.5, color: _kMuted),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: _ocupado ? null : () => _fijarModulos(sinFijar),
            icon: const Icon(Icons.lock_outline_rounded),
            label: Text('Fijar módulos de ${sinFijar.length} persona(s)'),
          ),
        ),
      ],
    ];
    final forma = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: const BorderSide(color: _kBorder),
    );
    if (!ancho) {
      return Card(
        shape: forma,
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          leading: const Icon(Icons.apps_rounded, color: _kAccent),
          title: Text(titulo, style: _estilo(13.5, weight: FontWeight.w900)),
          subtitle: sinFijar.isEmpty
              ? null
              : Text(
                  '${sinFijar.length} sin fijar',
                  style: _estilo(11.5, color: _kWarn),
                ),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: contenido,
        ),
      );
    }
    return Card(
      shape: forma,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.apps_rounded, color: _kAccent),
                const SizedBox(width: 8),
                Text(titulo, style: _estilo(14, weight: FontWeight.w900)),
              ],
            ),
            const SizedBox(height: 4),
            ...contenido,
          ],
        ),
      ),
    );
  }

  Future<void> _fijarModulos(List<PersonaMultiempresa> personas) async {
    final datos = _datos;
    if (datos == null) return;
    final quitar = _quitarHeredados;
    final afectados = personas
        .where((p) => p.conModulosHeredados.isNotEmpty)
        .length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Fijar módulos por empresa',
          style: _estilo(16, weight: FontWeight.w800),
        ),
        content: SizedBox(
          width: 480,
          child: Text(
            quitar
                ? 'A ${personas.length} persona(s) se les escribe la lista de '
                      'cada empresa. $afectados dejarán de ver en alguna '
                      'empresa módulos que solo tenían por otra empresa.'
                : 'A ${personas.length} persona(s) se les escribe la lista de '
                      'cada empresa con lo que ven hoy. Nadie gana ni pierde '
                      'módulos; desde ahora un cambio en una empresa no se '
                      'pasa a las otras.',
            style: _estilo(13),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Fijar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _ocupado = true;
      _progreso = 'Fijando módulos…';
    });
    try {
      final n = await _svc.fijarModulos(
        datos: datos,
        cedulas: personas.map((p) => p.cedula),
        actorId: widget.userId,
        quitarHeredadas: quitar,
        onProgreso: (hechas, total) {
          if (mounted) setState(() => _progreso = '$hechas de $total');
        },
      );
      _snack('Módulos fijados por empresa para $n persona(s).');
    } catch (e) {
      _snack('No se pudieron fijar los módulos: $e');
    } finally {
      if (mounted) {
        setState(() {
          _ocupado = false;
          _progreso = null;
        });
      }
      await _cargar();
    }
  }

  Future<void> _editarModulos(PersonaMultiempresa p) async {
    final datos = _datos;
    if (datos == null) return;
    final usuario = datos.usuarios[p.cedula] ?? const <String, dynamic>{};
    final elegidos = <String, Set<String>>{
      for (final x in p.puestos) x.empresaId: {...x.modulos},
    };
    bool tiene(String empresa, String appId) =>
        elegidos[empresa]!.any((a) => appIdsEquivalent(a, appId));

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(
            'Módulos de ${_nombre(p.cedula)}',
            style: _estilo(16, weight: FontWeight.w800),
          ),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Lo marcado en cada empresa es exactamente lo que verá '
                    'allí. En naranja, lo que hoy ve solo porque lo tiene en '
                    'otra empresa.',
                    style: _estilo(12, color: _kMuted),
                  ),
                  for (final x in p.puestos) ...[
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _empresa(x.empresaId),
                            style: _estilo(13.5, weight: FontWeight.w800),
                          ),
                        ),
                        _estado(x),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final m in kAppCatalog)
                          FilterChip(
                            label: Text(m.nombre, style: _estilo(12)),
                            selected: tiene(x.empresaId, m.appId),
                            selectedColor:
                                x.modulosHeredados.any(
                                  (h) => appIdsEquivalent(h, m.appId),
                                )
                                ? _kWarnBg
                                : null,
                            side: BorderSide(
                              color:
                                  x.modulosHeredados.any(
                                    (h) => appIdsEquivalent(h, m.appId),
                                  )
                                  ? _kWarn
                                  : _kBorder,
                            ),
                            onSelected: (v) => setLocal(() {
                              final set = elegidos[x.empresaId]!;
                              if (v) {
                                set.add(m.appId);
                              } else {
                                set.removeWhere(
                                  (a) => appIdsEquivalent(a, m.appId),
                                );
                              }
                            }),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    setState(() => _ocupado = true);
    try {
      await _svc.guardarModulos(
        cedula: p.cedula,
        usuario: usuario,
        porEmpresa: elegidos,
        actorId: widget.userId,
      );
      _snack('Módulos de ${_nombre(p.cedula)} guardados por empresa.');
      await _cargar();
    } catch (e) {
      _snack('No se pudieron guardar los módulos: $e');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Widget _modulos(PuestoEmpresa x) {
    if (x.modulos.isEmpty) {
      return Text('—', style: _estilo(12.5, color: _kMuted));
    }
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final app in x.modulos)
          if (x.modulosHeredados.contains(app))
            Tooltip(
              message: 'Lo ve solo porque lo tiene en otra empresa',
              child: _chip(nombreModulo(app), _kWarn),
            )
          else
            _chip(nombreModulo(app), _kMuted),
      ],
    );
  }

  // ─── Catálogo entre empresas ──────────────────────────────────────────────

  Widget _selectorEmpresa({
    required String label,
    required String? value,
    required ValueChanged<String?> onChanged,
    String? excluir,
  }) {
    final opciones = widget.empresas
        .where((e) => e.empresaId != excluir)
        .toList();
    return DropdownButtonFormField<String>(
      initialValue: opciones.any((e) => e.empresaId == value) ? value : null,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
      items: [
        for (final e in opciones)
          DropdownMenuItem(
            value: e.empresaId,
            child: Text(
              e.nombre.isEmpty ? e.empresaId : e.nombre,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: onChanged,
    );
  }

  Widget _tarjetaCatalogo() {
    final ancho = MediaQuery.sizeOf(context).width >= 760;
    final origen = _selectorEmpresa(
      label: 'Desde',
      value: _catOrigen,
      excluir: _catDestino,
      onChanged: (v) => setState(() => _catOrigen = v),
    );
    final destino = _selectorEmpresa(
      label: 'Hacia',
      value: _catDestino,
      excluir: _catOrigen,
      onChanged: (v) => setState(() => _catDestino = v),
    );
    final tipos = Wrap(
      spacing: 8,
      children: [
        for (final t in TipoCatalogo.values)
          FilterChip(
            label: Text(switch (t) {
              TipoCatalogo.area => 'Áreas',
              TipoCatalogo.cargo => 'Cargos',
              TipoCatalogo.centro => 'Centros de costos',
            }, style: _estilo(12)),
            selected: _catTipos.contains(t),
            onSelected: (v) =>
                setState(() => v ? _catTipos.add(t) : _catTipos.remove(t)),
          ),
      ],
    );
    final boton = FilledButton.icon(
      onPressed:
          _ocupado ||
              _catOrigen == null ||
              _catDestino == null ||
              _catTipos.isEmpty
          ? null
          : _revisarEnvioCatalogo,
      icon: const Icon(Icons.call_split_rounded),
      label: const Text('Revisar y enviar'),
    );
    const titulo = 'Enviar áreas, cargos y centros a otra empresa';
    final descripcion = Text(
      'Crea en la empresa destino lo que le falte del catálogo, sin '
      'trasladar a nadie. Lo que ya existe con el mismo nombre se respeta.',
      style: _estilo(12, color: _kMuted),
    );
    final forma = ShapeDecoration(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: _kBorder),
      ),
    ).shape;

    if (!ancho) {
      // En el teléfono va plegado: es una tarea de vez en cuando y empujaba
      // la lista de personas fuera de la pantalla.
      return Card(
        shape: forma,
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          leading: const Icon(Icons.account_tree_outlined, color: _kAccent),
          title: Text(titulo, style: _estilo(13.5, weight: FontWeight.w900)),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            descripcion,
            const SizedBox(height: 12),
            origen,
            const SizedBox(height: 10),
            destino,
            const SizedBox(height: 10),
            tipos,
            const SizedBox(height: 10),
            SizedBox(width: double.infinity, child: boton),
          ],
        ),
      );
    }

    return Card(
      shape: forma,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.account_tree_outlined, color: _kAccent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    titulo,
                    style: _estilo(14, weight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            descripcion,
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: origen),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward, color: _kMuted),
                ),
                Expanded(child: destino),
                const SizedBox(width: 12),
                boton,
              ],
            ),
            const SizedBox(height: 10),
            tipos,
          ],
        ),
      ),
    );
  }

  Future<void> _revisarEnvioCatalogo() async {
    final datos = _datos;
    final origen = _catOrigen;
    final destino = _catDestino;
    if (datos == null || origen == null || destino == null) return;

    PlanCatalogo planear(Set<String>? ids) => planearEnvioCatalogo(
      origenId: origen,
      destinoId: destino,
      catalogos: copiarCatalogos(datos.catalogos),
      tipos: {..._catTipos},
      ids: ids,
    );

    final completo = planear(null);
    if (completo.nuevas.isEmpty) {
      _snack(
        '${_empresa(destino)} ya tiene todo el catálogo elegido de '
        '${_empresa(origen)} (${completo.yaExistian} coincidencias).',
      );
      return;
    }
    // Se eligen entradas del ORIGEN. Las que el plan crea por arrastre (el
    // área de un cargo) no se pueden desmarcar solas.
    final elegibles = [
      for (final n in completo.nuevas)
        if ((n.datos['registroOrigenId'] ?? '').toString().isNotEmpty) n,
    ];
    final elegidos = {
      for (final n in elegibles) (n.datos['registroOrigenId'] as String),
    };

    final plan = await showDialog<PlanCatalogo>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final actual = planear(elegidos);
          return AlertDialog(
            title: Text(
              'Enviar catálogo a ${_empresa(destino)}',
              style: _estilo(16, weight: FontWeight.w800),
            ),
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Se crearán ${actual.de(TipoCatalogo.area).length} '
                      'área(s), ${actual.de(TipoCatalogo.cargo).length} '
                      'cargo(s) y ${actual.de(TipoCatalogo.centro).length} '
                      'centro(s). ${completo.yaExistian} ya existían con el '
                      'mismo nombre y no se tocan. Nadie del personal cambia.',
                      style: _estilo(13),
                    ),
                    if (completo.cargosConAreaDistinta.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _kWarnBg,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Cargos que ya existen pero en otra área:\n'
                          '${completo.cargosConAreaDistinta.map((c) => '• ${c.nombre}: ${c.areaOrigen} → allá ${c.areaDestino}').join('\n')}',
                          style: _estilo(12, color: _kWarn),
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    PagedListSection<EntradaNueva>(
                      items: elegibles,
                      etiqueta: 'entradas',
                      itemBuilder: (_, n, _) {
                        final origenId = n.datos['registroOrigenId'] as String;
                        return CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          value: elegidos.contains(origenId),
                          title: Text(n.nombre, style: _estilo(13)),
                          subtitle: Text(
                            n.tipo.etiqueta +
                                (n.tipo == TipoCatalogo.cargo &&
                                        (n.datos['areaNombre'] ?? '')
                                            .toString()
                                            .isNotEmpty
                                    ? ' · ${n.datos['areaNombre']}'
                                    : ''),
                            style: _estilo(11, color: _kMuted),
                          ),
                          onChanged: (v) => setLocal(
                            () => v == true
                                ? elegidos.add(origenId)
                                : elegidos.remove(origenId),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: actual.nuevas.isEmpty
                    ? null
                    : () => Navigator.pop(ctx, actual),
                child: Text('Crear ${actual.nuevas.length}'),
              ),
            ],
          );
        },
      ),
    );
    if (plan == null) return;
    setState(() => _ocupado = true);
    try {
      final n = await _svc.enviarCatalogo(plan, actorId: widget.userId);
      _snack('$n entrada(s) creadas en ${_empresa(destino)}.');
      await _cargar();
    } catch (e) {
      _snack('No se pudo enviar el catálogo: $e');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  // ─── Filtros y lote ───────────────────────────────────────────────────────

  Widget _filtros(AreaCatalogo areas) {
    final cargos = _cargos;
    final ancho = MediaQuery.sizeOf(context).width >= 760;
    final buscar = TextField(
      decoration: const InputDecoration(
        prefixIcon: Icon(Icons.search),
        labelText: 'Buscar por nombre o cédula',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      onChanged: (v) => setState(() => _busqueda = v),
    );
    DropdownButtonFormField<String?> selector({
      required String label,
      required String? value,
      required Map<String?, String> opciones,
      required ValueChanged<String?> onChanged,
    }) => DropdownButtonFormField<String?>(
      initialValue: opciones.containsKey(value) ? value : null,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
      items: [
        for (final e in opciones.entries)
          DropdownMenuItem(
            value: e.key,
            child: Text(e.value, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: onChanged,
    );

    final empresa = selector(
      label: 'Empresa',
      value: _empresaFiltro,
      opciones: {
        null: 'Todas las empresas',
        for (final e in widget.empresas) e.empresaId: _empresa(e.empresaId),
      },
      onChanged: (v) => setState(() => _empresaFiltro = v),
    );
    final area = selector(
      label: 'Área',
      value: _areaFiltro,
      opciones: {
        null: 'Todas las áreas',
        for (final o in areas.opciones) o.id: o.nombre,
      },
      onChanged: (v) => setState(() => _areaFiltro = v),
    );
    final cargo = selector(
      label: 'Cargo',
      value: _cargoFiltro,
      opciones: {null: 'Todos los cargos', ...cargos},
      onChanged: (v) => setState(() => _cargoFiltro = v),
    );
    final vista = SegmentedButton<_Vista>(
      segments: [
        for (final v in _Vista.values)
          ButtonSegment(
            value: v,
            label: Text(v.etiqueta, style: _estilo(12)),
          ),
      ],
      selected: {_vista},
      showSelectedIcon: false,
      onSelectionChanged: (s) => setState(() => _vista = s.first),
    );

    if (ancho) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(flex: 3, child: buscar),
              const SizedBox(width: 10),
              Expanded(flex: 2, child: empresa),
              const SizedBox(width: 10),
              Expanded(flex: 2, child: area),
              const SizedBox(width: 10),
              Expanded(flex: 2, child: cargo),
            ],
          ),
          const SizedBox(height: 10),
          vista,
        ],
      );
    }
    final activos = [
      _empresaFiltro,
      _areaFiltro,
      _cargoFiltro,
    ].where((f) => f != null).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        buscar,
        const SizedBox(height: 8),
        SingleChildScrollView(scrollDirection: Axis.horizontal, child: vista),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(
              activos == 0
                  ? 'Filtrar por empresa, área o cargo'
                  : 'Filtros ($activos activo${activos == 1 ? '' : 's'})',
              style: _estilo(13, weight: FontWeight.w700),
            ),
            initiallyExpanded: activos > 0,
            childrenPadding: const EdgeInsets.only(bottom: 4),
            children: [
              empresa,
              const SizedBox(height: 8),
              area,
              const SizedBox(height: 8),
              cargo,
            ],
          ),
        ),
      ],
    );
  }

  Widget _accionesLote(List<PersonaMultiempresa> filtradas) {
    final descuadradas = filtradas.where((p) => !p.sincronizada).toList();
    final seleccionadas = _personas
        .where((p) => _seleccion.contains(p.cedula))
        .toList();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: _kWarn),
          onPressed: _ocupado || descuadradas.isEmpty
              ? null
              : () => _sincronizarLote(descuadradas),
          icon: const Icon(Icons.sync_rounded),
          label: Text('Sincronizar ${descuadradas.length} descuadrada(s)'),
        ),
        OutlinedButton.icon(
          onPressed: _ocupado || seleccionadas.isEmpty
              ? null
              : () => _agregarAEmpresa(seleccionadas),
          icon: const Icon(Icons.group_add_outlined),
          label: Text(
            seleccionadas.isEmpty
                ? 'Enviar seleccionados a otra empresa'
                : 'Enviar ${seleccionadas.length} a otra empresa',
          ),
        ),
        if (_seleccion.isNotEmpty)
          TextButton(
            onPressed: () => setState(_seleccion.clear),
            child: const Text('Quitar selección'),
          )
        else if (filtradas.isNotEmpty)
          TextButton(
            onPressed: () => setState(
              () => _seleccion.addAll(filtradas.map((p) => p.cedula)),
            ),
            child: Text('Seleccionar los ${filtradas.length} del filtro'),
          ),
      ],
    );
  }

  // ─── Tarjeta de persona ───────────────────────────────────────────────────

  Widget _tarjetaPersona(PersonaMultiempresa p) {
    final nombre = _nombre(p.cedula);
    final abierta = _expandidas.contains(p.cedula);
    final ok = p.sincronizada;
    final activas = p.activas.length;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: ok ? _kBorder : const Color(0xFFFCD9B6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(
              () => abierta
                  ? _expandidas.remove(p.cedula)
                  : _expandidas.add(p.cedula),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
              child: Row(
                children: [
                  Checkbox(
                    value: _seleccion.contains(p.cedula),
                    onChanged: (v) => setState(
                      () => v == true
                          ? _seleccion.add(p.cedula)
                          : _seleccion.remove(p.cedula),
                    ),
                  ),
                  UserAvatar(
                    userId: p.cedula,
                    nameHint: nombre,
                    radius: 17,
                    backgroundColor: _kAccent.withValues(alpha: 0.08),
                    foregroundColor: _kAccent,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        UserNameText(
                          p.cedula,
                          fallbackName: nombre,
                          style: _estilo(13.5, weight: FontWeight.w800),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [
                            for (final x in p.puestos)
                              '${_empresa(x.empresaId)}: '
                                  '${x.cargo.vacio ? 'sin cargo' : x.cargo.nombre}'
                                  '${x.activa ? '' : ' (${x.estado.etiqueta.toLowerCase()})'}',
                          ].join('  ·  '),
                          maxLines: abierta ? 4 : 2,
                          overflow: TextOverflow.ellipsis,
                          style: _estilo(11.5, color: _kMuted),
                        ),
                        const SizedBox(height: 4),
                        // Debajo del nombre y no a la derecha: en el teléfono
                        // no caben al lado.
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            _chip(
                              ok
                                  ? 'Sincronizada'
                                  : '${p.descuadres.length} descuadre(s)',
                              ok ? _kOk : _kWarn,
                            ),
                            if (p.conModulosHeredados.isNotEmpty)
                              _chip('Módulos de otra empresa', _kWarn),
                            Text(
                              '$activas activa(s) de ${p.puestos.length}',
                              style: _estilo(10.5, color: _kMuted),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    abierta ? Icons.expand_less : Icons.expand_more,
                    color: _kMuted,
                  ),
                ],
              ),
            ),
          ),
          if (abierta) _detallePersona(p),
        ],
      ),
    );
  }

  Widget _chip(String texto, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      texto,
      style: _estilo(11, weight: FontWeight.w800, color: color),
    ),
  );

  Widget _valor(ValorCatalogo v, {String vacio = '—'}) {
    final texto = v.vacio ? vacio : v.nombre;
    final problema = v.problema != ProblemaValor.ninguno;
    final child = Text(
      texto,
      style: _estilo(
        12.5,
        weight: problema ? FontWeight.w700 : FontWeight.w400,
        color: problema ? _kWarn : (v.vacio ? _kMuted : null),
      ),
    );
    if (!problema) return child;
    return Tooltip(
      message: switch (v.problema) {
        ProblemaValor.heredado => 'Heredado de la empresa principal',
        ProblemaValor.deOtraEmpresa => 'Enlazado al catálogo de otra empresa',
        ProblemaValor.fueraDeCatalogo => 'No está en el catálogo',
        ProblemaValor.sinEnlace => 'Sin enlace a su registro del catálogo',
        ProblemaValor.nombreDesactualizado =>
          'Guardado como "${v.nombreGuardado}"',
        ProblemaValor.ninguno => '',
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.warning_amber_rounded, size: 14, color: _kWarn),
          const SizedBox(width: 3),
          Flexible(child: child),
        ],
      ),
    );
  }

  Widget _valores(List<ValorCatalogo> vs) {
    if (vs.isEmpty) return Text('—', style: _estilo(12.5, color: _kMuted));
    return Wrap(
      spacing: 6,
      runSpacing: 2,
      children: [for (final v in vs) _valor(v)],
    );
  }

  Widget _estado(PuestoEmpresa x) => _chip(
    x.esPrincipal ? '${x.estado.etiqueta} · principal' : x.estado.etiqueta,
    switch (x.estado) {
      EstadoMembresia.activa => _kOk,
      EstadoMembresia.apagada => _kMuted,
      EstadoMembresia.retirada => Colors.red,
    },
  );

  Widget _detallePersona(PersonaMultiempresa p) {
    final ancho = MediaQuery.sizeOf(context).width >= 900;
    final detalle = ancho
        ? SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowHeight: 36,
              dataRowMinHeight: 40,
              dataRowMaxHeight: 72,
              columnSpacing: 18,
              headingTextStyle: _estilo(12, weight: FontWeight.w800),
              columns: const [
                DataColumn(label: Text('Empresa')),
                DataColumn(label: Text('Estado')),
                DataColumn(label: Text('Área')),
                DataColumn(label: Text('Cargo')),
                DataColumn(label: Text('Centro de costos')),
                DataColumn(label: Text('Centros de operación')),
                DataColumn(label: Text('Centros de trabajo')),
                DataColumn(label: Text('Jefe')),
                DataColumn(label: Text('Módulos')),
              ],
              rows: [
                for (final x in p.puestos)
                  DataRow(
                    cells: [
                      DataCell(
                        Text(
                          _empresa(x.empresaId),
                          style: _estilo(12.5, weight: FontWeight.w700),
                        ),
                      ),
                      DataCell(_estado(x)),
                      DataCell(_valor(x.area)),
                      DataCell(_valor(x.cargo)),
                      DataCell(_valor(x.centro)),
                      DataCell(
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 240),
                          child: _valores(x.operacion),
                        ),
                      ),
                      DataCell(
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 240),
                          child: _valores(x.trabajo),
                        ),
                      ),
                      DataCell(
                        Text(
                          x.jefeNombre.isEmpty ? '—' : x.jefeNombre,
                          style: _estilo(12.5),
                        ),
                      ),
                      DataCell(
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 300),
                          child: _modulos(x),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          )
        : Column(children: [for (final x in p.puestos) _puestoCompacto(x)]);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1),
          const SizedBox(height: 8),
          detalle,
          if (p.descuadres.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _kWarnBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final d in p.descuadres)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        '• ${d.tipo.etiqueta}: ${d.detalle}',
                        style: _estilo(12, color: const Color(0xFF9A3412)),
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _ocupado ? null : () => _sincronizarPersona(p),
                icon: const Icon(Icons.sync_rounded, size: 18),
                label: const Text('Sincronizar…'),
              ),
              OutlinedButton.icon(
                onPressed: _ocupado ? null : () => _editarModulos(p),
                icon: const Icon(Icons.apps_rounded, size: 18),
                label: const Text('Módulos…'),
              ),
              OutlinedButton.icon(
                onPressed:
                    _ocupado || p.puestos.length >= widget.empresas.length
                    ? null
                    : () => _agregarAEmpresa([p]),
                icon: const Icon(Icons.add_business_outlined, size: 18),
                label: const Text('Agregar a otra empresa…'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _puestoCompacto(PuestoEmpresa x) {
    Widget fila(String etiqueta, Widget valor) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(etiqueta, style: _estilo(11.5, color: _kMuted)),
          ),
          Expanded(child: valor),
        ],
      ),
    );
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: _kBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _empresa(x.empresaId),
                  style: _estilo(13, weight: FontWeight.w800),
                ),
              ),
              _estado(x),
            ],
          ),
          const SizedBox(height: 6),
          fila('Área', _valor(x.area)),
          fila('Cargo', _valor(x.cargo)),
          fila('Centro costos', _valor(x.centro)),
          fila('Operación', _valores(x.operacion)),
          fila('Trabajo', _valores(x.trabajo)),
          if (x.jefeNombre.isNotEmpty)
            fila('Jefe', Text(x.jefeNombre, style: _estilo(12.5))),
          fila('Módulos', _modulos(x)),
        ],
      ),
    );
  }

  // ─── Diálogos de sincronización ───────────────────────────────────────────

  /// Resumen legible de lo que hará un plan, empresa por empresa.
  List<String> _lineasPlan(PersonaMultiempresa p, PlanPersona plan) {
    final out = <String>[];
    for (final a in plan.ajustes) {
      if (a.vacio) continue;
      final antes = p.puesto(a.empresaId);
      final cambios = <String>[];
      void cambio(String etiqueta, String? previo, Object? nuevo) {
        if (nuevo == null) return;
        final n = nuevo is Iterable ? nuevo.join(', ') : '$nuevo';
        final v = (previo ?? '').trim();
        cambios.add(
          v.isEmpty || v == n
              ? '$etiqueta: ${n.isEmpty ? '(vacío)' : n}'
              : '$etiqueta: $v → ${n.isEmpty ? '(vacío)' : n}',
        );
      }

      String lista(List<ValorCatalogo>? vs) =>
          (vs ?? const []).map((v) => v.nombre).join(', ');

      if (a.usuario.containsKey('areaId')) {
        cambio('Área', antes?.area.nombre, a.usuario['area']);
      }
      if (a.usuario.containsKey('cargoId')) {
        cambio('Cargo', antes?.cargo.nombre, a.usuario['cargo']);
      }
      if (a.usuario.containsKey('centroId')) {
        cambio(
          'Centro de costos',
          antes?.centro.nombre,
          a.usuario['centroCostos'],
        );
      }
      if (a.usuario.containsKey('centrosOperacionIds')) {
        cambio(
          'Operación',
          lista(antes?.operacion),
          a.usuario['centrosOperacionNombres'],
        );
      }
      if (a.usuario.containsKey('centrosTrabajoIds')) {
        cambio(
          'Trabajo',
          lista(antes?.trabajo),
          a.usuario['centrosTrabajoNombres'],
        );
      }
      if (a.estructura.isNotEmpty) {
        cambios.add('Estructura organizacional alineada');
      }
      final titulo = a.vincular
          ? 'Se agrega a ${_empresa(a.empresaId)}'
          : _empresa(a.empresaId);
      out.add(
        '$titulo\n   ${cambios.isEmpty ? 'Enlaces al catálogo' : cambios.join('\n   ')}',
      );
    }
    for (final n in plan.nuevas) {
      out.add(
        'Nuevo en el catálogo de ${_empresa(n.empresaId)}: '
        '${n.tipo.etiqueta.toLowerCase()} "${n.nombre}"',
      );
    }
    out.addAll(plan.avisos);
    return out;
  }

  Widget _camposSelector(
    CamposSincronizacion campos,
    ValueChanged<CamposSincronizacion> onChanged,
  ) => Wrap(
    spacing: 8,
    runSpacing: 4,
    children: [
      FilterChip(
        label: const Text('Área'),
        selected: campos.area,
        onSelected: (v) => onChanged(
          CamposSincronizacion(
            area: v,
            cargo: campos.cargo,
            centros: campos.centros,
          ),
        ),
      ),
      FilterChip(
        label: const Text('Cargo'),
        selected: campos.cargo,
        onSelected: (v) => onChanged(
          CamposSincronizacion(
            area: campos.area,
            cargo: v,
            centros: campos.centros,
          ),
        ),
      ),
      FilterChip(
        label: const Text('Centros (costos, operación y trabajo)'),
        selected: campos.centros,
        onSelected: (v) => onChanged(
          CamposSincronizacion(
            area: campos.area,
            cargo: campos.cargo,
            centros: v,
          ),
        ),
      ),
    ],
  );

  Widget _vistaPrevia(List<String> lineas) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: const Color(0xFFF8FAFC),
      border: Border.all(color: _kBorder),
      borderRadius: BorderRadius.circular(8),
    ),
    child: lineas.isEmpty
        ? Text(
            'Ya está sincronizada: no hay nada que escribir.',
            style: _estilo(12.5, color: _kOk),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final l in lineas)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text(l, style: _estilo(12.5)),
                ),
            ],
          ),
  );

  Future<void> _sincronizarPersona(PersonaMultiempresa p) async {
    final datos = _datos;
    if (datos == null) return;
    final usuario = datos.usuarios[p.cedula] ?? const <String, dynamic>{};
    final estructura = datos.estructuras[p.cedula];
    var referencia = p.referenciaSugerida ?? p.empresaIds.first;
    var campos = const CamposSincronizacion();
    final destinos = {for (final x in p.activas) x.empresaId};

    PlanPersona planear(Map<String, CatalogoEmpresa> catalogos) =>
        planearSincronizacion(
          persona: p,
          usuario: usuario,
          estructura: estructura,
          referenciaId: referencia,
          destinos: {referencia, ...destinos},
          catalogos: catalogos,
          campos: campos,
          nombresEmpresa: _nombresEmpresa,
        );

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final plan = planear(copiarCatalogos(datos.catalogos));
          final ref = p.puesto(referencia);
          return AlertDialog(
            title: Text(
              'Sincronizar a ${_nombre(p.cedula)}',
              style: _estilo(16, weight: FontWeight.w800),
            ),
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Empresa de referencia (la que está bien)',
                      style: _estilo(12.5, weight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        for (final x in p.puestos)
                          ChoiceChip(
                            label: Text(_empresa(x.empresaId)),
                            selected: referencia == x.empresaId,
                            onSelected: (_) =>
                                setLocal(() => referencia = x.empresaId),
                          ),
                      ],
                    ),
                    if (ref != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Allí: ${ref.cargo.vacio ? 'sin cargo' : ref.cargo.nombre}'
                        ' · ${ref.area.vacio ? 'sin área' : ref.area.nombre}'
                        '${ref.centro.vacio ? '' : ' · ${ref.centro.nombre}'}',
                        style: _estilo(12, color: _kMuted),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      'Qué se iguala',
                      style: _estilo(12.5, weight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    _camposSelector(campos, (c) => setLocal(() => campos = c)),
                    const SizedBox(height: 12),
                    Text(
                      'En qué empresas',
                      style: _estilo(12.5, weight: FontWeight.w800),
                    ),
                    for (final x in p.puestos)
                      if (x.empresaId != referencia)
                        CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          value: destinos.contains(x.empresaId),
                          title: Text(_empresa(x.empresaId)),
                          subtitle: x.activa
                              ? null
                              : Text(
                                  '${x.estado.etiqueta}: su cargo allí es '
                                  'historia, normalmente no se toca.',
                                  style: _estilo(11, color: _kMuted),
                                ),
                          onChanged: (v) => setLocal(
                            () => v == true
                                ? destinos.add(x.empresaId)
                                : destinos.remove(x.empresaId),
                          ),
                        ),
                    const SizedBox(height: 10),
                    Text(
                      'Vista previa',
                      style: _estilo(12.5, weight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    _vistaPrevia(_lineasPlan(p, plan)),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: plan.vacio || campos.ninguno
                    ? null
                    : () => Navigator.pop(ctx, true),
                child: const Text('Sincronizar'),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true) return;

    setState(() => _ocupado = true);
    try {
      await _svc.aplicarPlan(
        plan: planear(datos.catalogos),
        usuario: usuario,
        estructura: estructura,
        actorId: widget.userId,
      );
      _snack('${_nombre(p.cedula)} quedó sincronizada.');
      await _cargar();
    } catch (e) {
      _snack('No se pudo sincronizar: $e');
      await _cargar();
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  String _referenciaDe(PersonaMultiempresa p, String modo) {
    if (modo != _kReferenciaPrincipal) {
      final x = p.puesto(modo);
      if (x != null && x.activa) return modo;
    }
    return p.referenciaSugerida ?? p.empresaIds.first;
  }

  Future<void> _sincronizarLote(List<PersonaMultiempresa> personas) async {
    final datos = _datos;
    if (datos == null) return;
    var modo = _kReferenciaPrincipal;
    var campos = const CamposSincronizacion();

    List<PlanPersona> planear(Map<String, CatalogoEmpresa> catalogos) => [
      for (final p in personas)
        planearSincronizacion(
          persona: p,
          usuario: datos.usuarios[p.cedula] ?? const {},
          estructura: datos.estructuras[p.cedula],
          referenciaId: _referenciaDe(p, modo),
          destinos: {
            _referenciaDe(p, modo),
            for (final x in p.activas) x.empresaId,
          },
          catalogos: catalogos,
          campos: campos,
          nombresEmpresa: _nombresEmpresa,
        ),
    ];

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final planes = planear(copiarCatalogos(datos.catalogos));
          final conCambios = planes.where((pl) => !pl.vacio).length;
          final nuevas = {
            for (final pl in planes)
              for (final n in pl.nuevas)
                '${_empresa(n.empresaId)}: ${n.tipo.etiqueta.toLowerCase()} "${n.nombre}"',
          };
          final conflictos = personas
              .where(
                (p) => p.descuadres.any(
                  (d) =>
                      d.tipo == TipoDescuadre.cargoDistinto ||
                      d.tipo == TipoDescuadre.areaDistinta,
                ),
              )
              .length;
          return AlertDialog(
            title: Text(
              'Sincronizar ${personas.length} persona(s)',
              style: _estilo(16, weight: FontWeight.w800),
            ),
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Referencia',
                      style: _estilo(12.5, weight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: modo,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: _kReferenciaPrincipal,
                          child: Text('La empresa principal de cada persona'),
                        ),
                        for (final e in widget.empresas)
                          DropdownMenuItem(
                            value: e.empresaId,
                            child: Text(
                              _empresa(e.empresaId),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) =>
                          setLocal(() => modo = v ?? _kReferenciaPrincipal),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Si alguien no está activo en la empresa elegida, se '
                      'usa su empresa principal.',
                      style: _estilo(11.5, color: _kMuted),
                    ),
                    const SizedBox(height: 12),
                    _camposSelector(campos, (c) => setLocal(() => campos = c)),
                    const SizedBox(height: 12),
                    Text(
                      '$conCambios persona(s) cambian. Solo se tocan sus '
                      'empresas activas.',
                      style: _estilo(13),
                    ),
                    if (conflictos > 0) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _kWarnBg,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$conflictos persona(s) tienen área o cargo '
                          'distinto entre empresas: quedará el de la '
                          'referencia en todas. Si alguna debe quedar '
                          'distinta, sincronízala una por una.',
                          style: _estilo(12, color: _kWarn),
                        ),
                      ),
                    ],
                    if (nuevas.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Se crean en el catálogo (${nuevas.length}):',
                        style: _estilo(12.5, weight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        nuevas.take(30).map((n) => '• $n').join('\n') +
                            (nuevas.length > 30
                                ? '\n… y ${nuevas.length - 30} más'
                                : ''),
                        style: _estilo(12),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: conCambios == 0 || campos.ninguno
                    ? null
                    : () => Navigator.pop(ctx, true),
                child: Text('Sincronizar $conCambios'),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true) return;
    await _aplicarLote(planear(datos.catalogos), 'multiempresaSincronizarLote');
  }

  Future<void> _agregarAEmpresa(List<PersonaMultiempresa> personas) async {
    final datos = _datos;
    if (datos == null) return;
    final candidatas = widget.empresas
        .where(
          (e) =>
              personas.length > 1 ||
              personas.single.puesto(e.empresaId) == null,
        )
        .toList();
    if (candidatas.isEmpty) return;
    var destino = candidatas.first.empresaId;
    var campos = const CamposSincronizacion();

    List<PlanPersona> planear(Map<String, CatalogoEmpresa> catalogos) => [
      for (final p in personas)
        planearSincronizacion(
          persona: p,
          usuario: datos.usuarios[p.cedula] ?? const {},
          estructura: datos.estructuras[p.cedula],
          referenciaId: p.referenciaSugerida ?? p.empresaIds.first,
          destinos: {destino},
          catalogos: catalogos,
          campos: campos,
          nombresEmpresa: _nombresEmpresa,
        ),
    ];

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final planes = planear(copiarCatalogos(datos.catalogos));
          final nuevas = planes
              .where((pl) => pl.ajustes.any((a) => a.vincular))
              .length;
          final yaEstaban = personas.length - nuevas;
          final catalogo = {
            for (final pl in planes)
              for (final n in pl.nuevas)
                '${n.tipo.etiqueta.toLowerCase()} "${n.nombre}"',
          };
          return AlertDialog(
            title: Text(
              personas.length == 1
                  ? 'Agregar a ${_nombre(personas.single.cedula)} a otra empresa'
                  : 'Enviar ${personas.length} persona(s) a otra empresa',
              style: _estilo(16, weight: FontWeight.w800),
            ),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: destino,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Empresa destino',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final e in candidatas)
                          DropdownMenuItem(
                            value: e.empresaId,
                            child: Text(
                              _empresa(e.empresaId),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) => setLocal(() => destino = v ?? destino),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Qué se lleva de su empresa principal',
                      style: _estilo(12.5, weight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    _camposSelector(campos, (c) => setLocal(() => campos = c)),
                    const SizedBox(height: 12),
                    Text(
                      '$nuevas persona(s) quedan vinculadas a '
                      '${_empresa(destino)}'
                      '${yaEstaban > 0 ? ' y $yaEstaban que ya estaban se sincronizan' : ''}. '
                      'Nadie más del personal se mueve y su empresa '
                      'principal no cambia.',
                      style: _estilo(13),
                    ),
                    if (personas.length == 1) ...[
                      const SizedBox(height: 10),
                      _vistaPrevia(_lineasPlan(personas.single, planes.single)),
                    ] else if (catalogo.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Se crean en el catálogo de ${_empresa(destino)}: '
                        '${catalogo.take(20).join(', ')}'
                        '${catalogo.length > 20 ? ' y ${catalogo.length - 20} más' : ''}.',
                        style: _estilo(12),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: planes.every((pl) => pl.vacio)
                    ? null
                    : () => Navigator.pop(ctx, true),
                child: const Text('Enviar'),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true) return;
    await _aplicarLote(planear(datos.catalogos), 'multiempresaVincularPersona');
    if (mounted) setState(_seleccion.clear);
  }

  Future<void> _aplicarLote(List<PlanPersona> planes, String accion) async {
    final datos = _datos;
    if (datos == null) return;
    setState(() {
      _ocupado = true;
      _progreso = 'Aplicando…';
    });
    try {
      final r = await _svc.aplicarPlanes(
        planes: planes,
        datos: datos,
        actorId: widget.userId,
        accion: accion,
        onProgreso: (hechas, total) {
          if (mounted) setState(() => _progreso = '$hechas de $total');
        },
      );
      _snack(
        '${r.personas} persona(s) sincronizadas en ${r.empresasTocadas} '
        'empresa(s); ${r.entradasCreadas} entrada(s) nuevas de catálogo.'
        '${r.errores.isEmpty ? '' : ' ${r.errores.length} con error: ${r.errores.first}'}',
      );
    } catch (e) {
      _snack('No se pudo completar: $e');
    } finally {
      if (mounted) {
        setState(() {
          _ocupado = false;
          _progreso = null;
        });
      }
      await _cargar();
    }
  }
}
