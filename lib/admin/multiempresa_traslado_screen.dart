// lib/admin/multiempresa_traslado_screen.dart
//
// Admin › Multiempresa › Traslado de personal.
//
// Se elige una empresa antigua (origen) y una nueva (destino) y, persona por
// persona o en lote con filtros de área, cargo y centro, dónde debe quedar:
//
//   * Solo en la nueva: entra a la nueva con su área, cargo y centros de la
//     antigua y la antigua se apaga (no se borra ni es un retiro).
//   * En las dos: entra a la nueva y sigue activa en la antigua.
//   * Solo en la antigua: no pasa; si ya estaba en la nueva, allá se apaga.
//
// La decisión inicial de cada persona es cómo está hoy, así que solo se
// escribe a quien se le cambie. Toda la lógica de qué escribir vive en
// `planearTraslado` (core/multiempresa_sync.dart, con pruebas).
//
// Web y móvil comparten estado y lógica. Cambia la composición: en pantalla
// ancha las personas van en tabla con la decisión en la fila; en el teléfono,
// una tarjeta por persona y los filtros plegados.

import 'package:flutter/material.dart';

import '../core/area_directory.dart';
import '../core/multiempresa_sync.dart';
import '../widgets/paged_list.dart';
import '../widgets/user_avatar.dart';
import 'admin_repository.dart';
import 'multiempresa_sync_service.dart';

const String _kFont = 'Arial';
const Color _kAccent = Color(0xFF3B82F6);
const Color _kBorder = Color(0xFFE2E8F0);
const Color _kMuted = Color(0xFF64748B);
const Color _kOk = Color(0xFF10B981);
const Color _kWarn = Color(0xFFD97706);
const Color _kWarnBg = Color(0xFFFFF7ED);
const Color _kCambio = Color(0xFFEFF6FF);

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

extension on DestinoTraslado {
  String get corto => switch (this) {
    DestinoTraslado.soloNueva => 'Solo nueva',
    DestinoTraslado.ambas => 'Las dos',
    DestinoTraslado.soloAntigua => 'Solo antigua',
  };

  IconData get icono => switch (this) {
    DestinoTraslado.soloNueva => Icons.east_rounded,
    DestinoTraslado.ambas => Icons.compare_arrows_rounded,
    DestinoTraslado.soloAntigua => Icons.west_rounded,
  };
}

/// Cómo está hoy la persona respecto a las dos empresas.
enum _Hoy { soloAntigua, ambas, soloNueva, ninguna }

class MultiempresaTrasladoScreen extends StatefulWidget {
  final String userId;
  final List<EmpresaItem> empresas;
  final MultiempresaDatos datos;
  final List<PersonaMultiempresa> personas;

  /// Nombre visible de cada cédula.
  final Map<String, String> nombres;
  final MultiempresaSyncService servicio;
  final String? origenInicial;

  const MultiempresaTrasladoScreen({
    super.key,
    required this.userId,
    required this.empresas,
    required this.datos,
    required this.personas,
    required this.nombres,
    required this.servicio,
    this.origenInicial,
  });

  @override
  State<MultiempresaTrasladoScreen> createState() =>
      _MultiempresaTrasladoScreenState();
}

class _MultiempresaTrasladoScreenState
    extends State<MultiempresaTrasladoScreen> {
  String? _origen;
  String? _destino;

  bool _llevaArea = true;
  bool _llevaCargo = true;
  bool _llevaCentros = true;
  bool _llevaModulos = true;

  String _busqueda = '';
  String? _areaFiltro;
  String? _cargoFiltro;
  String? _centroFiltro;
  _Hoy? _hoyFiltro;
  DestinoTraslado? _decisionFiltro;
  bool _soloCambios = false;
  bool _verInhabilitados = false;

  /// Por qué cada persona no se puede trasladar (null = sí se puede). Se
  /// calcula una vez por par de empresas.
  final Map<String, String?> _bloqueos = {};

  /// Lo que el usuario eligió; quien no está aquí queda como está hoy.
  final Map<String, DestinoTraslado> _decisiones = {};
  final Set<String> _seleccion = {};
  int _pagina = 0;

  bool _ocupado = false;
  String? _progreso;

  @override
  void initState() {
    super.initState();
    final inicial = widget.origenInicial;
    if (inicial != null && widget.empresas.any((e) => e.empresaId == inicial)) {
      _origen = inicial;
    }
  }

  // ─── Datos ────────────────────────────────────────────────────────────────

  String _empresa(String? id) {
    if (id == null) return '';
    for (final e in widget.empresas) {
      if (e.empresaId == id) return e.nombre.isEmpty ? id : e.nombre;
    }
    return id;
  }

  Map<String, String> get _nombresEmpresa => {
    for (final e in widget.empresas) e.empresaId: e.nombre,
  };

  String _nombre(String cedula) => widget.nombres[cedula] ?? cedula;

  bool get _listo => _origen != null && _destino != null && _origen != _destino;

  CamposSincronizacion get _campos => CamposSincronizacion(
    area: _llevaArea,
    cargo: _llevaCargo,
    centros: _llevaCentros,
    modulos: _llevaModulos,
  );

  /// Personas de la empresa antigua: son las que se pueden trasladar.
  List<PersonaMultiempresa> get _candidatas {
    final origen = _origen;
    if (!_listo || origen == null) return const [];
    return [
      for (final p in widget.personas)
        if (p.puesto(origen) != null) p,
    ];
  }

  _Hoy _hoy(PersonaMultiempresa p) {
    final o = p.puesto(_origen!);
    final d = p.puesto(_destino!);
    final enO = o != null && o.estado != EstadoMembresia.apagada;
    final enD = d != null && d.estado != EstadoMembresia.apagada;
    if (enO && enD) return _Hoy.ambas;
    if (enO) return _Hoy.soloAntigua;
    if (enD) return _Hoy.soloNueva;
    return _Hoy.ninguna;
  }

  String _hoyTexto(_Hoy h) => switch (h) {
    _Hoy.soloAntigua => 'Solo en ${_empresa(_origen)}',
    _Hoy.ambas => 'En las dos',
    _Hoy.soloNueva => 'Solo en ${_empresa(_destino)}',
    _Hoy.ninguna => 'Apagada en las dos',
  };

  DestinoTraslado _situacion(PersonaMultiempresa p) =>
      situacionTraslado(p, _origen!, _destino!);

  DestinoTraslado _decision(PersonaMultiempresa p) =>
      _decisiones[p.cedula] ?? _situacion(p);

  /// ¿Hay algo que escribir para esta persona? Quien está apagada en las
  /// dos cambia con cualquier decisión explícita.
  bool _cambia(PersonaMultiempresa p) {
    if (_bloqueo(p) != null) return false;
    final d = _decisiones[p.cedula];
    if (d == null) return false;
    return d != _situacion(p) || _hoy(p) == _Hoy.ninguna;
  }

  void _decidir(PersonaMultiempresa p, DestinoTraslado? d) {
    // Personal inhabilitado no pasa: su decisión no se puede cambiar.
    if (_bloqueo(p) != null) {
      _decisiones.remove(p.cedula);
      return;
    }
    if (d == null || (d == _situacion(p) && _hoy(p) != _Hoy.ninguna)) {
      _decisiones.remove(p.cedula);
    } else {
      _decisiones[p.cedula] = d;
    }
  }

  /// Por qué no se puede trasladar (inhabilitada en alguna de las dos o con
  /// la cuenta apagada); null si se puede. Ver `motivoNoTraslada`.
  String? _bloqueo(PersonaMultiempresa p) => _bloqueos.putIfAbsent(
    p.cedula,
    () => motivoNoTraslada(
      usuario: widget.datos.usuarios[p.cedula] ?? const <String, dynamic>{},
      estructura: widget.datos.estructuras[p.cedula],
      empresas: [_origen!, _destino!],
      nombresEmpresa: _nombresEmpresa,
    ),
  );

  /// El puesto que se mira para filtrar: el de la antigua.
  PuestoEmpresa? _puesto(PersonaMultiempresa p) => p.puesto(_origen!);

  AreaCatalogo _areas(List<PersonaMultiempresa> candidatas) =>
      AreaCatalogo.desde([
        for (final p in candidatas)
          if (_puesto(p) case final x? when !x.area.vacio)
            (
              id:
                  x.area.entrada?.id ??
                  (x.area.id.isNotEmpty ? x.area.id : x.area.nombre),
              nombre: x.area.nombre,
            ),
      ]);

  Map<String, String> _opciones(
    List<PersonaMultiempresa> candidatas,
    Iterable<ValorCatalogo> Function(PuestoEmpresa) valores,
  ) {
    final out = <String, String>{};
    for (final p in candidatas) {
      final x = _puesto(p);
      if (x == null) continue;
      for (final v in valores(x)) {
        if (!v.vacio) out.putIfAbsent(v.clave, () => v.nombre);
      }
    }
    final orden = out.entries.toList()
      ..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));
    return Map.fromEntries(orden);
  }

  Iterable<ValorCatalogo> _centros(PuestoEmpresa x) => [
    x.centro,
    ...x.operacion,
    ...x.trabajo,
  ];

  List<PersonaMultiempresa> _filtrar(
    List<PersonaMultiempresa> candidatas,
    AreaCatalogo areas,
  ) {
    final q = claveCatalogo(_busqueda);
    final area = _areaFiltro == null
        ? null
        : areas.opciones.where((o) => o.id == _areaFiltro).firstOrNull;
    return candidatas.where((p) {
      final x = _puesto(p)!;
      if (!_verInhabilitados && _bloqueo(p) != null) return false;
      if (area != null &&
          !area.contiene(x.area.entrada?.id) &&
          !area.contiene(x.area.id) &&
          !area.contiene(x.area.nombre)) {
        return false;
      }
      if (_cargoFiltro != null && x.cargo.clave != _cargoFiltro) return false;
      if (_centroFiltro != null &&
          !_centros(x).any((c) => c.clave == _centroFiltro)) {
        return false;
      }
      if (_hoyFiltro != null && _hoy(p) != _hoyFiltro) return false;
      if (_decisionFiltro != null && _decision(p) != _decisionFiltro) {
        return false;
      }
      if (_soloCambios && !_cambia(p)) return false;
      if (q.isNotEmpty &&
          !claveCatalogo(_nombre(p.cedula)).contains(q) &&
          !p.cedula.contains(_busqueda.trim())) {
        return false;
      }
      return true;
    }).toList();
  }

  void _filtro(VoidCallback cambio) => setState(() {
    cambio();
    _pagina = 0;
  });

  void _cambiarEmpresas(VoidCallback cambio) => setState(() {
    cambio();
    _decisiones.clear();
    _seleccion.clear();
    _bloqueos.clear();
    _areaFiltro = null;
    _cargoFiltro = null;
    _centroFiltro = null;
    _pagina = 0;
  });

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ─── Construcción ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final candidatas = _candidatas;
    final areas = _areas(candidatas);
    final filtradas = _listo
        ? _filtrar(candidatas, areas)
        : const <PersonaMultiempresa>[];
    final cambios = candidatas.where(_cambia).toList();
    return PopScope(
      canPop: !_ocupado,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: Text(
            'Traslado de personal',
            style: _estilo(17, weight: FontWeight.w800),
          ),
        ),
        bottomNavigationBar: _listo ? _barraAplicar(cambios) : null,
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            _tarjetaEmpresas(),
            if (!_listo)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Elige la empresa antigua y la nueva para ver al personal.',
                  textAlign: TextAlign.center,
                  style: _estilo(13, color: _kMuted),
                ),
              )
            else ...[
              const SizedBox(height: 12),
              _resumen(candidatas),
              const SizedBox(height: 12),
              _filtros(candidatas, areas),
              const SizedBox(height: 8),
              _accionesLote(filtradas),
              const SizedBox(height: 8),
              if (candidatas.isEmpty)
                _aviso('${_empresa(_origen)} no tiene personal.')
              else if (filtradas.isEmpty)
                _aviso('Nadie coincide con los filtros.')
              else
                _listado(filtradas),
            ],
          ],
        ),
      ),
    );
  }

  Widget _aviso(String texto) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Row(
      children: [
        const Icon(Icons.search_off, color: _kMuted, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(texto, style: _estilo(13, color: _kMuted)),
        ),
      ],
    ),
  );

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
        filled: true,
        fillColor: Colors.white,
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
      onChanged: _ocupado ? null : onChanged,
    );
  }

  Widget _tarjetaEmpresas() {
    final ancho = MediaQuery.sizeOf(context).width >= 760;
    final origen = _selectorEmpresa(
      label: 'Empresa antigua',
      value: _origen,
      excluir: _destino,
      onChanged: (v) => _cambiarEmpresas(() => _origen = v),
    );
    final destino = _selectorEmpresa(
      label: 'Empresa nueva',
      value: _destino,
      excluir: _origen,
      onChanged: (v) => _cambiarEmpresas(() => _destino = v),
    );
    Widget lleva(String texto, bool valor, ValueChanged<bool> onChanged) =>
        FilterChip(
          label: Text(texto, style: _estilo(12)),
          selected: valor,
          onSelected: _ocupado ? null : (v) => setState(() => onChanged(v)),
        );
    final llevar = Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          'Se lleva a la nueva:',
          style: _estilo(12.5, weight: FontWeight.w700),
        ),
        lleva('Área', _llevaArea, (v) => _llevaArea = v),
        lleva('Cargo', _llevaCargo, (v) => _llevaCargo = v),
        lleva(
          'Centros (costos, operación y trabajo)',
          _llevaCentros,
          (v) => _llevaCentros = v,
        ),
        lleva('Módulos', _llevaModulos, (v) => _llevaModulos = v),
      ],
    );
    return Card(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: _kBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.move_up_rounded, color: _kAccent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'De qué empresa a cuál',
                    style: _estilo(14, weight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              ancho
                  ? 'Por cada persona decides si queda solo en la nueva, en '
                        'las dos o solo en la antigua. Quien entra a la nueva '
                        'lleva el área, el cargo y los centros que tiene en la '
                        'antigua; si allá no existen, se crean por nombre. La '
                        'empresa que deja se apaga: ya no puede entrar a ella '
                        'ni sale en su personal, pero no se borra ni cuenta '
                        'como retiro, y lo que registró allí se conserva.'
                  : 'Decide por persona: solo en la nueva, en las dos o solo '
                        'en la antigua. La empresa que deja se apaga, no se '
                        'borra.',
              style: _estilo(12, color: _kMuted).copyWith(height: 1.35),
            ),
            const SizedBox(height: 12),
            if (ancho)
              Row(
                children: [
                  Expanded(child: origen),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(Icons.arrow_forward, color: _kMuted),
                  ),
                  Expanded(child: destino),
                ],
              )
            else ...[
              origen,
              const SizedBox(height: 10),
              destino,
            ],
            const SizedBox(height: 12),
            llevar,
          ],
        ),
      ),
    );
  }

  Widget _resumen(List<PersonaMultiempresa> candidatas) {
    // Los inhabilitados van aparte: no se trasladan, así que no se cuentan
    // en cómo está hoy el personal que sí se puede mover.
    final conteo = <_Hoy, int>{for (final h in _Hoy.values) h: 0};
    var inhabilitados = 0;
    for (final p in candidatas) {
      if (_bloqueo(p) != null) {
        inhabilitados++;
      } else {
        conteo[_hoy(p)] = conteo[_hoy(p)]! + 1;
      }
    }
    Widget tarjeta({
      required int valor,
      required String etiqueta,
      required Color color,
      required bool activo,
      required VoidCallback onTap,
    }) => InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: activo ? color : _kBorder,
            width: activo ? 2 : 1,
          ),
          color: Colors.white,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$valor',
              style: _estilo(20, weight: FontWeight.w900, color: color),
            ),
            Text(etiqueta, style: _estilo(11.5, color: _kMuted)),
          ],
        ),
      ),
    );

    Widget dato(_Hoy h, Color color) {
      final activo = _hoyFiltro == h;
      final t = _hoyTexto(h);
      return tarjeta(
        valor: conteo[h]!,
        // Solo la inicial en minúscula: el nombre de la empresa se escribe
        // como es.
        etiqueta: 'Hoy ${t[0].toLowerCase()}${t.substring(1)}',
        color: color,
        activo: activo,
        onTap: () => _filtro(() => _hoyFiltro = activo ? null : h),
      );
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        dato(_Hoy.soloAntigua, _kMuted),
        dato(_Hoy.ambas, _kAccent),
        dato(_Hoy.soloNueva, _kOk),
        if (conteo[_Hoy.ninguna]! > 0) dato(_Hoy.ninguna, _kWarn),
        if (inhabilitados > 0)
          Tooltip(
            message: _verInhabilitados
                ? 'Toca para ocultarlos'
                : 'Toca para verlos en la lista (no se pueden trasladar)',
            child: tarjeta(
              valor: inhabilitados,
              etiqueta: 'Inhabilitados: no se trasladan',
              color: Colors.red,
              activo: _verInhabilitados,
              onTap: () =>
                  _filtro(() => _verInhabilitados = !_verInhabilitados),
            ),
          ),
      ],
    );
  }

  Widget _filtros(List<PersonaMultiempresa> candidatas, AreaCatalogo areas) {
    final ancho = MediaQuery.sizeOf(context).width >= 760;
    final cargos = _opciones(candidatas, (x) => [x.cargo]);
    final centros = _opciones(candidatas, _centros);
    final buscar = TextField(
      decoration: const InputDecoration(
        prefixIcon: Icon(Icons.search),
        labelText: 'Buscar por nombre o cédula',
        border: OutlineInputBorder(),
        isDense: true,
        filled: true,
        fillColor: Colors.white,
      ),
      onChanged: (v) => _filtro(() => _busqueda = v),
    );
    Widget selector<T>({
      required String label,
      required T? value,
      required Map<T?, String> opciones,
      required ValueChanged<T?> onChanged,
    }) => DropdownButtonFormField<T?>(
      initialValue: opciones.containsKey(value) ? value : null,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
        filled: true,
        fillColor: Colors.white,
      ),
      items: [
        for (final e in opciones.entries)
          DropdownMenuItem(
            value: e.key,
            child: Text(e.value, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (v) => _filtro(() => onChanged(v)),
    );

    final area = selector<String>(
      label: 'Área en ${_empresa(_origen)}',
      value: _areaFiltro,
      opciones: {
        null: 'Todas las áreas',
        for (final o in areas.opciones) o.id: o.nombre,
      },
      onChanged: (v) => _areaFiltro = v,
    );
    final cargo = selector<String>(
      label: 'Cargo',
      value: _cargoFiltro,
      opciones: {null: 'Todos los cargos', ...cargos},
      onChanged: (v) => _cargoFiltro = v,
    );
    final centro = selector<String>(
      label: 'Centro',
      value: _centroFiltro,
      opciones: {null: 'Todos los centros', ...centros},
      onChanged: (v) => _centroFiltro = v,
    );
    final quedara = selector<DestinoTraslado>(
      label: 'Quedará',
      value: _decisionFiltro,
      opciones: {
        null: 'Cualquier decisión',
        DestinoTraslado.soloNueva: 'Solo en ${_empresa(_destino)}',
        DestinoTraslado.ambas: 'En las dos',
        DestinoTraslado.soloAntigua: 'Solo en ${_empresa(_origen)}',
      },
      onChanged: (v) => _decisionFiltro = v,
    );
    final opciones = Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        FilterChip(
          label: Text('Solo con cambios', style: _estilo(12)),
          selected: _soloCambios,
          onSelected: (v) => _filtro(() => _soloCambios = v),
        ),
        FilterChip(
          label: Text('Ver inhabilitados', style: _estilo(12)),
          selected: _verInhabilitados,
          onSelected: (v) => _filtro(() => _verInhabilitados = v),
        ),
      ],
    );

    if (ancho) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(flex: 3, child: buscar),
              const SizedBox(width: 10),
              Expanded(flex: 2, child: area),
              const SizedBox(width: 10),
              Expanded(flex: 2, child: cargo),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(flex: 2, child: centro),
              const SizedBox(width: 10),
              Expanded(flex: 2, child: quedara),
              const SizedBox(width: 10),
              Expanded(flex: 3, child: opciones),
            ],
          ),
        ],
      );
    }
    final activos = [
      _areaFiltro,
      _cargoFiltro,
      _centroFiltro,
      _decisionFiltro,
    ].where((f) => f != null).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        buscar,
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(
              activos == 0
                  ? 'Filtrar por área, cargo o centro'
                  : 'Filtros ($activos activo${activos == 1 ? '' : 's'})',
              style: _estilo(13, weight: FontWeight.w700),
            ),
            initiallyExpanded: activos > 0,
            childrenPadding: const EdgeInsets.only(bottom: 4),
            children: [
              area,
              const SizedBox(height: 8),
              cargo,
              const SizedBox(height: 8),
              centro,
              const SizedBox(height: 8),
              quedara,
            ],
          ),
        ),
        opciones,
      ],
    );
  }

  Widget _accionesLote(List<PersonaMultiempresa> filtradas) {
    // El lote nunca alcanza a un inhabilitado, aunque se esté viendo.
    final trasladables = filtradas.where((p) => _bloqueo(p) == null).toList();
    final seleccionadas = trasladables
        .where((p) => _seleccion.contains(p.cedula))
        .toList();
    final objetivo = seleccionadas.isNotEmpty ? seleccionadas : trasladables;
    final quien = seleccionadas.isNotEmpty
        ? 'los ${seleccionadas.length} seleccionados'
        : 'los ${trasladables.length} del filtro';
    void aplicar(DestinoTraslado? d) => setState(() {
      for (final p in objetivo) {
        _decidir(p, d);
      }
    });

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Para $quien:',
                  style: _estilo(12.5, weight: FontWeight.w700),
                ),
              ),
              if (_seleccion.isNotEmpty)
                TextButton(
                  onPressed: () => setState(_seleccion.clear),
                  child: const Text('Quitar selección'),
                )
              else if (trasladables.isNotEmpty)
                TextButton(
                  onPressed: () => setState(
                    () => _seleccion.addAll(trasladables.map((p) => p.cedula)),
                  ),
                  child: const Text('Seleccionar todos'),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final d in DestinoTraslado.values)
                OutlinedButton.icon(
                  onPressed: _ocupado || objetivo.isEmpty
                      ? null
                      : () => aplicar(d),
                  icon: Icon(d.icono, size: 18),
                  label: Text(switch (d) {
                    DestinoTraslado.soloNueva =>
                      'Solo en ${_empresa(_destino)}',
                    DestinoTraslado.ambas => 'En las dos',
                    DestinoTraslado.soloAntigua =>
                      'Solo en ${_empresa(_origen)}',
                  }),
                ),
              TextButton.icon(
                onPressed: _ocupado || objetivo.isEmpty
                    ? null
                    : () => aplicar(null),
                icon: const Icon(Icons.undo_rounded, size: 18),
                label: const Text('Dejar como está hoy'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Dónde queda. A un inhabilitado no se le ofrece: en su lugar va el
  /// porqué.
  Widget _selectorDecision(PersonaMultiempresa p) {
    final bloqueo = _bloqueo(p);
    if (bloqueo == null) return _segmentos(p);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.block_rounded, size: 16, color: Colors.red),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            bloqueo,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: _estilo(11.5, weight: FontWeight.w700, color: Colors.red),
          ),
        ),
      ],
    );
  }

  Widget _segmentos(PersonaMultiempresa p) => SegmentedButton<DestinoTraslado>(
    segments: [
      for (final d in DestinoTraslado.values)
        ButtonSegment(
          value: d,
          tooltip: switch (d) {
            DestinoTraslado.soloNueva => 'Solo en ${_empresa(_destino)}',
            DestinoTraslado.ambas => 'En las dos empresas',
            DestinoTraslado.soloAntigua => 'Solo en ${_empresa(_origen)}',
          },
          label: Text(d.corto, style: _estilo(11.5)),
        ),
    ],
    selected: {_decision(p)},
    showSelectedIcon: false,
    style: const ButtonStyle(
      visualDensity: VisualDensity.compact,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    onSelectionChanged: _ocupado
        ? null
        : (s) => setState(() => _decidir(p, s.first)),
  );

  Widget _texto(ValorCatalogo v) => Text(
    v.vacio ? '—' : v.nombre,
    overflow: TextOverflow.ellipsis,
    style: _estilo(12.5, color: v.vacio ? _kMuted : null),
  );

  Widget _listado(List<PersonaMultiempresa> filtradas) {
    final maxPagina = pageCountOf(filtradas.length) - 1;
    final pagina = _pagina.clamp(0, maxPagina < 0 ? 0 : maxPagina);
    final visibles = pageOf(filtradas, pagina);
    final barra = filtradas.length > kPageSize
        ? PagerBar(
            total: filtradas.length,
            page: pagina,
            etiqueta: 'personas',
            onPageChanged: (v) => setState(() => _pagina = v),
          )
        : null;
    final ancho = MediaQuery.sizeOf(context).width >= 900;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      // Arriba, como en el panel: en el teléfono la de abajo queda escondida
      // detrás de 20 tarjetas.
      children: [
        ?barra,
        if (ancho) _tabla(visibles) else for (final p in visibles) _tarjeta(p),
      ],
    );
  }

  Widget _tabla(List<PersonaMultiempresa> visibles) => Card(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: const BorderSide(color: _kBorder),
    ),
    clipBehavior: Clip.antiAlias,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 38,
        dataRowMinHeight: 52,
        dataRowMaxHeight: 64,
        columnSpacing: 18,
        headingTextStyle: _estilo(12, weight: FontWeight.w800),
        showCheckboxColumn: true,
        columns: [
          const DataColumn(label: Text('Persona')),
          const DataColumn(label: Text('Hoy')),
          DataColumn(label: Text('Área en ${_empresa(_origen)}')),
          const DataColumn(label: Text('Cargo')),
          const DataColumn(label: Text('Centro de costos')),
          const DataColumn(label: Text('Quedará')),
        ],
        rows: [
          for (final p in visibles)
            DataRow(
              selected: _seleccion.contains(p.cedula),
              color: WidgetStatePropertyAll(_cambia(p) ? _kCambio : null),
              // Un inhabilitado no se puede seleccionar: no entra al lote.
              onSelectChanged: _bloqueo(p) != null
                  ? null
                  : (v) => setState(
                      () => v == true
                          ? _seleccion.add(p.cedula)
                          : _seleccion.remove(p.cedula),
                    ),
              cells: [
                DataCell(_persona(p, radio: 15)),
                DataCell(_estadoHoy(p, corto: true)),
                DataCell(
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 160),
                    child: _texto(_puesto(p)!.area),
                  ),
                ),
                DataCell(
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 180),
                    child: _texto(_puesto(p)!.cargo),
                  ),
                ),
                DataCell(
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 150),
                    child: _texto(_puesto(p)!.centro),
                  ),
                ),
                DataCell(_selectorDecision(p)),
              ],
            ),
        ],
      ),
    ),
  );

  Widget _persona(PersonaMultiempresa p, {double radio = 17}) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      UserAvatar(
        userId: p.cedula,
        nameHint: _nombre(p.cedula),
        radius: radio,
        backgroundColor: _kAccent.withValues(alpha: 0.08),
        foregroundColor: _kAccent,
      ),
      const SizedBox(width: 10),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 200),
        child: UserNameText(
          p.cedula,
          fallbackName: _nombre(p.cedula),
          style: _estilo(13, weight: FontWeight.w800),
        ),
      ),
    ],
  );

  /// [corto]: en la tabla, sin el nombre de la empresa (queda en el
  /// tooltip) para que quepa la columna de la decisión.
  Widget _estadoHoy(PersonaMultiempresa p, {bool corto = false}) {
    final h = _hoy(p);
    final inhabilitada = _bloqueo(p) != null;
    final chip = _chip(
      corto
          ? switch (h) {
              _Hoy.soloAntigua => 'Solo antigua',
              _Hoy.ambas => 'En las dos',
              _Hoy.soloNueva => 'Solo nueva',
              _Hoy.ninguna => 'Apagada en las dos',
            }
          : _hoyTexto(h),
      switch (h) {
        _Hoy.soloAntigua => _kMuted,
        _Hoy.ambas => _kAccent,
        _Hoy.soloNueva => _kOk,
        _Hoy.ninguna => _kWarn,
      },
    );
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        if (corto) Tooltip(message: _hoyTexto(h), child: chip) else chip,
        if (inhabilitada) _chip('Inhabilitado', Colors.red),
      ],
    );
  }

  Widget _tarjeta(PersonaMultiempresa p) {
    final x = _puesto(p)!;
    final cambia = _cambia(p);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: cambia ? _kCambio : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: cambia ? const Color(0xFFBFDBFE) : _kBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: _seleccion.contains(p.cedula),
                  onChanged: _bloqueo(p) != null
                      ? null
                      : (v) => setState(
                          () => v == true
                              ? _seleccion.add(p.cedula)
                              : _seleccion.remove(p.cedula),
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: UserAvatar(
                    userId: p.cedula,
                    nameHint: _nombre(p.cedula),
                    radius: 17,
                    backgroundColor: _kAccent.withValues(alpha: 0.08),
                    foregroundColor: _kAccent,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      UserNameText(
                        p.cedula,
                        fallbackName: _nombre(p.cedula),
                        style: _estilo(13.5, weight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          x.cargo.vacio ? 'Sin cargo' : x.cargo.nombre,
                          if (!x.area.vacio) x.area.nombre,
                          if (!x.centro.vacio) x.centro.nombre,
                        ].join('  ·  '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: _estilo(11.5, color: _kMuted),
                      ),
                      const SizedBox(height: 4),
                      _estadoHoy(p),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: _selectorDecision(p),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Aplicar ──────────────────────────────────────────────────────────────

  Widget _barraAplicar(List<PersonaMultiempresa> cambios) {
    final porDecision = <DestinoTraslado, int>{
      for (final d in DestinoTraslado.values) d: 0,
    };
    for (final p in cambios) {
      porDecision[_decision(p)] = porDecision[_decision(p)]! + 1;
    }
    final detalle = [
      if (porDecision[DestinoTraslado.soloNueva]! > 0)
        '${porDecision[DestinoTraslado.soloNueva]} solo en la nueva',
      if (porDecision[DestinoTraslado.ambas]! > 0)
        '${porDecision[DestinoTraslado.ambas]} en las dos',
      if (porDecision[DestinoTraslado.soloAntigua]! > 0)
        '${porDecision[DestinoTraslado.soloAntigua]} solo en la antigua',
    ].join(' · ');
    return Material(
      elevation: 8,
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_progreso != null) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 4),
                Text(_progreso!, style: _estilo(12, color: _kMuted)),
                const SizedBox(height: 6),
              ],
              Row(
                children: [
                  Expanded(
                    child: Text(
                      cambios.isEmpty
                          ? 'Sin cambios: elige dónde queda cada persona.'
                          : '${cambios.length} con cambios${detalle.isEmpty ? '' : ': $detalle'}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: _estilo(12.5, weight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: _ocupado || cambios.isEmpty
                        ? null
                        : () => _revisar(cambios),
                    icon: const Icon(Icons.fact_check_outlined),
                    label: const Text('Revisar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<PlanTraslado> _planear(
    List<PersonaMultiempresa> cambios,
    Map<String, CatalogoEmpresa> catalogos,
  ) => [
    for (final p in cambios)
      planearTraslado(
        persona: p,
        usuario: widget.datos.usuarios[p.cedula] ?? const <String, dynamic>{},
        estructura: widget.datos.estructuras[p.cedula],
        origenId: _origen!,
        destinoId: _destino!,
        decision: _decision(p),
        catalogos: catalogos,
        campos: _campos,
        nombresEmpresa: _nombresEmpresa,
      ),
  ];

  Future<void> _revisar(List<PersonaMultiempresa> cambios) async {
    final origen = _origen!;
    final destino = _destino!;
    // Se planea sobre una copia del catálogo: lo que se cree para una persona
    // lo encuentra la siguiente y no se duplica. El servicio crea ese catálogo
    // primero y completo.
    final planes = _planear(cambios, copiarCatalogos(widget.datos.catalogos));
    final pendientes = planes.where((p) => !p.vacio).toList();
    if (pendientes.isEmpty) {
      _snack('No hay nada que escribir: ya están así.');
      return;
    }
    final nuevas = <String, EntradaNueva>{
      for (final p in pendientes)
        for (final n in p.puesto.nuevas) '${n.tipo.coleccion}/${n.id}': n,
    }.values.toList();
    int cuantas(TipoCatalogo t) => nuevas.where((n) => n.tipo == t).length;
    final entran = pendientes
        .where((p) => p.puesto.ajustes.any((a) => !a.vacio))
        .length;
    final apagan = pendientes
        .where(
          (p) => p.usuario.entries.any(
            (e) => e.key.endsWith('.activo') && e.value == false,
          ),
        )
        .length;
    final principal = pendientes.where((p) => p.nuevaPrincipal != null).length;
    final avisos = <String, int>{};
    for (final p in pendientes) {
      for (final a in p.puesto.avisos) {
        avisos[a] = (avisos[a] ?? 0) + 1;
      }
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Trasladar ${pendientes.length} persona(s)',
          style: _estilo(16, weight: FontWeight.w800),
        ),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _linea(
                  Icons.login_rounded,
                  '$entran entran a ${_empresa(destino)}'
                  '${_campos.ninguno ? ' sin puesto' : ' con su puesto de ${_empresa(origen)}'}'
                  '${_llevaModulos ? ' y sus módulos (sin los de Administración)' : ''}.',
                ),
                _linea(
                  Icons.power_settings_new_rounded,
                  '$apagan quedan apagadas en la empresa que dejan: ya no '
                  'pueden entrar a ella ni salen en su personal. No se '
                  'borran ni cuentan como retiro.',
                ),
                if (principal > 0)
                  _linea(
                    Icons.star_outline_rounded,
                    '$principal cambian de empresa principal: sus datos '
                    'generales pasan a ser los de esa empresa.',
                  ),
                _linea(
                  Icons.account_tree_outlined,
                  nuevas.isEmpty
                      ? '${_empresa(destino)} ya tiene las áreas, cargos y '
                            'centros que se necesitan.'
                      : 'Se crearán en ${_empresa(destino)}: '
                            '${cuantas(TipoCatalogo.area)} área(s), '
                            '${cuantas(TipoCatalogo.cargo)} cargo(s) y '
                            '${cuantas(TipoCatalogo.centro)} centro(s).',
                ),
                if (nuevas.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  PagedListSection<EntradaNueva>(
                    items: nuevas,
                    etiqueta: 'entradas',
                    itemBuilder: (_, n, _) => Padding(
                      padding: const EdgeInsets.only(left: 30, bottom: 2),
                      child: Text(
                        '• ${n.tipo.etiqueta}: ${n.nombre}',
                        style: _estilo(12),
                      ),
                    ),
                  ),
                ],
                if (avisos.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _kWarnBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      avisos.entries
                          .map((e) => '• ${e.key} (${e.value})')
                          .join('\n'),
                      style: _estilo(12, color: _kWarn),
                    ),
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
            child: const Text('Trasladar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() {
      _ocupado = true;
      _progreso = 'Trasladando…';
    });
    try {
      final r = await widget.servicio.aplicarTraslados(
        planes: pendientes,
        datos: widget.datos,
        actorId: widget.userId,
        origenId: origen,
        destinoId: destino,
        onProgreso: (hechas, total) {
          if (mounted) setState(() => _progreso = '$hechas de $total');
        },
      );
      if (!mounted) return;
      if (r.errores.isNotEmpty) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(
              '${r.personas} trasladada(s), ${r.errores.length} con error',
              style: _estilo(16, weight: FontWeight.w800),
            ),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Text(r.errores.join('\n'), style: _estilo(12)),
              ),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Entendido'),
              ),
            ],
          ),
        );
      }
      if (!mounted) return;
      setState(() {
        _ocupado = false;
        _progreso = null;
      });
      Navigator.of(context).pop(
        '${r.personas} persona(s) trasladada(s)'
        '${r.entradasCreadas > 0 ? ', ${r.entradasCreadas} entrada(s) de catálogo creadas' : ''}.',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ocupado = false;
        _progreso = null;
      });
      _snack('No se pudo trasladar: $e');
    }
  }

  Widget _linea(IconData icono, String texto) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icono, size: 20, color: _kAccent),
        const SizedBox(width: 10),
        Expanded(child: Text(texto, style: _estilo(13))),
      ],
    ),
  );
}
