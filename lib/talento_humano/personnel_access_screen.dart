// lib/talento_humano/personnel_access_screen.dart
//
// "Accesos del personal": la versión de Talento Humano de la matriz de
// permisos de Admin. Misma fuente de verdad (TBL_USUARIOS.apps por empresa),
// pero en lenguaje de negocio y sin roles internos ni IDs técnicos.

import 'package:flutter/material.dart';

import '../core/app_catalog.dart';
import '../utils/user_company.dart';
import '../widgets/internal_module_layout.dart';
import '../widgets/paged_list.dart';
import '../widgets/user_avatar.dart';
import 'personnel_access_picker.dart';
import 'personnel_access_service.dart';

const Color _kThPrimary = Color(0xffc28942);
const String _kFont = 'Arial';

class PersonnelAccessScreen extends StatefulWidget {
  final String userId;
  final String empresaId;

  const PersonnelAccessScreen({
    super.key,
    required this.userId,
    required this.empresaId,
  });

  @override
  State<PersonnelAccessScreen> createState() => _PersonnelAccessScreenState();
}

class _PersonnelAccessScreenState extends State<PersonnelAccessScreen> {
  final _service = PersonnelAccessService();
  final _buscarCtrl = TextEditingController();

  bool _cargando = true;
  String? _error;
  List<PersonnelAccessRow> _personal = const [];
  List<AppCatalogEntry> _modulos = const [];
  Set<String> _apagadosEmpresa = const {};
  bool _soloActivos = true;
  String _filtroModulo = '';
  String _filtroCargo = '';
  int _pagina = 0;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _buscarCtrl.dispose();
    super.dispose();
  }

  /// [conIndicador] en false refresca sin vaciar la pantalla.
  ///
  /// Al guardar los accesos de una persona se recarga el padron. Poner
  /// `_cargando = true` reemplazaba la lista por el indicador, y al volver se
  /// construia un ListView nuevo: la posicion de scroll se perdia y la vista
  /// saltaba al principio. Quien esta revisando de a una persona terminaba
  /// buscando otra vez donde iba.
  Future<void> _cargar({bool conIndicador = true}) async {
    setState(() {
      if (conIndicador) _cargando = true;
      _error = null;
    });
    try {
      final apagados = await _service.disabledAppIds(widget.empresaId);
      final personal = await _service.loadPersonnel(widget.empresaId);
      if (!mounted) return;
      setState(() {
        _apagadosEmpresa = apagados;
        _modulos = _service.modulosDisponibles(apagados);
        _personal = personal;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo cargar el personal: $e';
        _cargando = false;
      });
    }
  }

  void _mensaje(String texto, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texto),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  /// Cargos presentes en el padron. Salen de la lista completa, no de la ya
  /// filtrada: si no, elegir un cargo vaciaria el desplegable.
  List<String> get _cargosDisponibles {
    final cargos = <String>{
      for (final row in _personal)
        if (row.cargo.trim().isNotEmpty) row.cargo.trim(),
    };
    return cargos.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  List<PersonnelAccessRow> get _visibles {
    final q = _buscarCtrl.text.trim().toLowerCase();
    return _personal.where((row) {
      if (_soloActivos && !row.activo) return false;
      if (_filtroModulo.isNotEmpty &&
          !row.apps.any((app) => appIdsEquivalent(app, _filtroModulo))) {
        return false;
      }
      if (_filtroCargo.isNotEmpty && row.cargo.trim() != _filtroCargo) {
        return false;
      }
      if (q.isEmpty) return true;
      return row.nombre.toLowerCase().contains(q) ||
          row.cedula.toLowerCase().contains(q) ||
          row.cargo.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _editar(PersonnelAccessRow row) async {
    final actuales = row.apps;
    final seleccionInicial = actuales
        .where((app) => _modulos.any((m) => appIdsEquivalent(m.appId, app)))
        .toSet();
    final noAdministrados = PersonnelAccessService.noAdministrados(
      actuales: actuales,
      administrables: _modulos,
    );

    final resultado = await showPersonnelAccessEditor(
      context: context,
      titulo: row.nombreVisible,
      subtitulo: row.cargo.isEmpty ? 'CC ${row.cedula}' : row.cargo,
      modulos: _modulos,
      seleccionInicial: seleccionInicial,
      gestionadosPorAdmin: noAdministrados,
    );
    if (resultado == null) return;

    try {
      final next = PersonnelAccessService.combinarConNoAdministrados(
        actuales: actuales,
        seleccion: resultado,
        administrables: _modulos,
      );
      await _service.saveApps(
        userId: row.userId,
        empresaId: widget.empresaId,
        apps: next,
        actorId: widget.userId,
      );
      _mensaje('Accesos actualizados para ${row.nombreVisible}.');
      await _cargar(conIndicador: false);
    } catch (e) {
      _mensaje('No se pudo guardar: $e', error: true);
    }
  }

  /// Dar o quitar módulos a todo un cargo de una vez.
  ///
  /// Filtrar por cargo ayuda a encontrarlos, pero entrar de a una persona en
  /// cuarenta es lo que hace que estas tareas no se hagan. Aquí se elige a
  /// quiénes por cargo, qué módulos, y si es dar o quitar.
  ///
  /// Es un cambio de permisos masivo y sin deshacer, así que confirma dos
  /// veces: primero se arma la operación, después se dice a cuántas personas
  /// va a tocar antes de escribir nada.
  Future<void> _dialogEnBloque() async {
    final cargos = <String>[];
    final modulos = <String>[];
    var agregar = true;
    var soloActivos = true;

    List<PersonnelAccessRow> afectados() => _personal
        .where(
          (row) =>
              cargos.contains(row.cargo.trim()) && (!soloActivos || row.activo),
        )
        .toList();

    String nombreModulo(String appId) {
      for (final m in _modulos) {
        if (m.appId == appId) return m.nombre;
      }
      return appId;
    }

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final personas = afectados();
          final listo =
              cargos.isNotEmpty && modulos.isNotEmpty && personas.isNotEmpty;

          Widget chips({
            required String titulo,
            required List<String> seleccion,
            required List<String> disponibles,
            required String Function(String) etiqueta,
            required String etiquetaAgregar,
          }) {
            final libres = disponibles
                .where((d) => !seleccion.contains(d))
                .toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 6),
                if (seleccion.isNotEmpty)
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final valor in seleccion)
                        InputChip(
                          label: Text(
                            etiqueta(valor),
                            style: const TextStyle(fontSize: 12),
                          ),
                          onDeleted: () =>
                              setDialogState(() => seleccion.remove(valor)),
                        ),
                    ],
                  ),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  key: ValueKey('$titulo-${seleccion.length}'),
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: etiquetaAgregar,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    for (final valor in libres)
                      DropdownMenuItem(
                        value: valor,
                        child: Text(
                          etiqueta(valor),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: libres.isEmpty
                      ? null
                      : (valor) {
                          if (valor == null) return;
                          setDialogState(() => seleccion.add(valor));
                        },
                ),
              ],
            );
          }

          return AlertDialog(
            title: const Text('Asignar módulos en bloque'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                          value: true,
                          icon: Icon(Icons.add_rounded),
                          label: Text('Agregar'),
                        ),
                        ButtonSegment(
                          value: false,
                          icon: Icon(Icons.remove_rounded),
                          label: Text('Quitar'),
                        ),
                      ],
                      selected: {agregar},
                      onSelectionChanged: (v) =>
                          setDialogState(() => agregar = v.first),
                    ),
                    const SizedBox(height: 18),
                    chips(
                      titulo: 'A quiénes, por cargo',
                      seleccion: cargos,
                      disponibles: _cargosDisponibles,
                      etiqueta: (c) => c,
                      etiquetaAgregar: 'Agregar cargo',
                    ),
                    const SizedBox(height: 18),
                    chips(
                      titulo: agregar
                          ? 'Módulos que se van a dar'
                          : 'Módulos que se van a quitar',
                      seleccion: modulos,
                      disponibles: [for (final m in _modulos) m.appId],
                      etiqueta: nombreModulo,
                      etiquetaAgregar: 'Agregar módulo',
                    ),
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      value: soloActivos,
                      onChanged: (v) =>
                          setDialogState(() => soloActivos = v ?? true),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text('Solo personal activo'),
                      subtitle: const Text(
                        'Quítalo para alcanzar también a quien ya se retiró',
                        style: TextStyle(fontSize: 11.5),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      cargos.isEmpty
                          ? 'Elige al menos un cargo.'
                          : personas.isEmpty
                          ? 'Ninguna persona con ese cargo.'
                          : 'Alcanza a ${personas.length} persona(s).',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: personas.isEmpty
                            ? const Color(0xFFB45309)
                            : const Color(0xFF166534),
                      ),
                    ),
                    if (!agregar) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'Quitar un módulo no se deshace desde aquí: habría '
                        'que volver a darlo.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Color(0xFFB45309),
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
                onPressed: listo ? () => Navigator.pop(ctx, true) : null,
                child: Text(agregar ? 'Agregar' : 'Quitar'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmado != true || !mounted) return;

    final personas = afectados();
    final nombres = [for (final id in modulos) nombreModulo(id)].join(', ');
    final verbo = agregar ? 'dar' : 'quitar';
    final segunda = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          '${agregar ? 'Agregar' : 'Quitar'} a ${personas.length} persona(s)',
        ),
        content: Text(
          'Se van a $verbo estos módulos: $nombres.\n\n'
          'Alcanza a quien tenga '
          '${cargos.length == 1 ? 'el cargo' : 'los cargos'} '
          '${cargos.join(', ')}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Sí, $verbo'),
          ),
        ],
      ),
    );
    if (segunda != true || !mounted) return;

    await _ejecutarEnBloque(
      personas: personas,
      modulos: modulos,
      agregar: agregar,
    );
  }

  Future<void> _ejecutarEnBloque({
    required List<PersonnelAccessRow> personas,
    required List<String> modulos,
    required bool agregar,
  }) async {
    setState(() => _cargando = true);
    var cambiadas = 0;
    var fallidas = 0;
    for (final row in personas) {
      final next = PersonnelAccessService.aplicarEnBloque(
        actuales: row.apps,
        modulos: modulos,
        agregar: agregar,
        administrables: _modulos,
      );
      // A quien ya está como debe no se le escribe: quedaría registrado un
      // cambio en su historial sin que nada haya cambiado.
      if (next.length == row.apps.length && next.containsAll(row.apps)) {
        continue;
      }
      try {
        await _service.saveApps(
          userId: row.userId,
          empresaId: widget.empresaId,
          apps: next,
          actorId: widget.userId,
        );
        cambiadas++;
      } catch (_) {
        fallidas++;
      }
    }
    await _cargar(conIndicador: false);
    if (!mounted) return;
    _mensaje(
      fallidas == 0
          ? '$cambiadas persona(s) actualizada(s).'
          : '$cambiadas actualizada(s), $fallidas con error.',
      error: fallidas > 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWeb = MediaQuery.of(context).size.width >= 900;

    return InternalModuleLayout(
      title: 'Accesos del personal',
      subtitle: 'Qué usa cada persona dentro de la app',
      accentColor: _kThPrimary,
      userId: widget.userId,
      empresaId: widget.empresaId,
      headerActions: [
        IconButton(
          tooltip: 'Actualizar',
          onPressed: _cargando ? null : _cargar,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      child: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _ErrorState(mensaje: _error!, onRetry: _cargar)
          : Column(
              children: [
                _filtros(isWeb),
                const Divider(height: 1),
                Expanded(child: _lista(isWeb)),
              ],
            ),
    );
  }

  Widget _filtros(bool isWeb) {
    final theme = Theme.of(context);
    final visibles = _visibles.length;

    return Padding(
      padding: EdgeInsets.fromLTRB(isWeb ? 24 : 12, 12, isWeb ? 24 : 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _kThPrimary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.lightbulb_outline_rounded,
                  size: 18,
                  color: _kThPrimary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Notificaciones y calendario los tiene todo el personal. '
                    'Aquí se decide qué módulos adicionales ve cada persona al '
                    'entrar a la app. El rol dentro de cada módulo lo asigna '
                    'Admin.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: isWeb ? 320 : double.infinity,
                child: TextField(
                  controller: _buscarCtrl,
                  onChanged: (_) => setState(() => _pagina = 0),
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.search_rounded),
                    hintText: 'Buscar por nombre, cédula o cargo',
                    border: const OutlineInputBorder(),
                    suffixIcon: _buscarCtrl.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => setState(_buscarCtrl.clear),
                          ),
                  ),
                ),
              ),
              SizedBox(
                width: isWeb ? 280 : double.infinity,
                child: DropdownButtonFormField<String>(
                  initialValue: _filtroModulo,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Filtrar por módulo',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('Todos los módulos'),
                    ),
                    ..._modulos.map(
                      (m) => DropdownMenuItem(
                        value: m.appId,
                        child: Text(m.nombre, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() {
                    _filtroModulo = v ?? '';
                    _pagina = 0;
                  }),
                ),
              ),
              SizedBox(
                width: isWeb ? 280 : double.infinity,
                child: DropdownButtonFormField<String>(
                  initialValue: _cargosDisponibles.contains(_filtroCargo)
                      ? _filtroCargo
                      : '',
                  isExpanded: true,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Filtrar por cargo',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('Todos los cargos'),
                    ),
                    ..._cargosDisponibles.map(
                      (c) => DropdownMenuItem(
                        value: c,
                        child: Text(c, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() {
                    _filtroCargo = v ?? '';
                    _pagina = 0;
                  }),
                ),
              ),
              FilterChip(
                selected: _soloActivos,
                onSelected: (v) => setState(() {
                  _soloActivos = v;
                  _pagina = 0;
                }),
                label: const Text('Solo personal activo'),
              ),
              FilledButton.tonalIcon(
                onPressed: _personal.isEmpty ? null : _dialogEnBloque,
                icon: const Icon(Icons.groups_outlined, size: 18),
                label: const Text('Asignar en bloque'),
              ),
              Text(
                '$visibles persona(s)',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          if (_apagadosEmpresa.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'La empresa tiene ${_apagadosEmpresa.length} módulo(s) '
                'apagado(s); no aparecen en esta lista.',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _lista(bool isWeb) {
    final rows = _visibles;
    if (rows.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('No hay personal que coincida con el filtro.'),
        ),
      );
    }

    // De a 20: el padrón de una empresa puede tener cientos de personas.
    final pagina = _pagina.clamp(0, pageCountOf(rows.length) - 1);
    final visibles = pageOf(rows, pagina);

    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.fromLTRB(
              isWeb ? 24 : 12,
              12,
              isWeb ? 24 : 12,
              12,
            ),
            itemCount: visibles.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _PersonaCard(
              row: visibles[i],
              modulos: _modulos,
              onEditar: () => _editar(visibles[i]),
            ),
          ),
        ),
        if (rows.length > kPageSize)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: isWeb ? 24 : 12),
            child: PagerBar(
              total: rows.length,
              page: pagina,
              etiqueta: 'personas',
              onPageChanged: (p) => setState(() => _pagina = p),
            ),
          ),
      ],
    );
  }
}

class _PersonaCard extends StatelessWidget {
  final PersonnelAccessRow row;
  final List<AppCatalogEntry> modulos;
  final VoidCallback onEditar;

  const _PersonaCard({
    required this.row,
    required this.modulos,
    required this.onEditar,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final asignados = modulos
        .where((m) => row.apps.any((app) => appIdsEquivalent(app, m.appId)))
        .toList();

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onEditar,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  UserAvatar(
                    userId: row.userId,
                    nameHint: row.nombre,
                    radius: 20,
                    backgroundColor: _kThPrimary.withValues(alpha: 0.15),
                    foregroundColor: _kThPrimary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        UserNameText(
                          row.userId,
                          fallbackName: row.nombre,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontFamily: _kFont,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          [
                            if (row.cargo.isNotEmpty) row.cargo,
                            'CC ${row.cedula}',
                          ].join(' · '),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!row.activo)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Chip(
                        visualDensity: VisualDensity.compact,
                        label: const Text('Inactivo'),
                        labelStyle: theme.textTheme.labelSmall,
                      ),
                    ),
                  TextButton.icon(
                    onPressed: onEditar,
                    icon: const Icon(Icons.tune_rounded, size: 18),
                    label: const Text('Cambiar'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (asignados.isEmpty)
                Text(
                  'Solo notificaciones y calendario.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                )
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: asignados
                      .map(
                        (m) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: m.color.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: m.color.withValues(alpha: 0.30),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(m.icono, size: 13, color: m.color),
                              const SizedBox(width: 5),
                              Text(
                                m.nombre,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: m.color,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String mensaje;
  final VoidCallback onRetry;

  const _ErrorState({required this.mensaje, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 40),
            const SizedBox(height: 12),
            Text(mensaje, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Intentar nuevamente'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Abre el selector de módulos: hoja inferior en móvil, diálogo en web.
/// Devuelve la selección confirmada o null si se canceló.
Future<Set<String>?> showPersonnelAccessEditor({
  required BuildContext context,
  required String titulo,
  required String subtitulo,
  required List<AppCatalogEntry> modulos,
  required Set<String> seleccionInicial,
  Set<String> gestionadosPorAdmin = const <String>{},
}) {
  final isWide = MediaQuery.of(context).size.width >= 900;
  var seleccion = {...seleccionInicial};

  Widget contenido(void Function(void Function()) setLocal) {
    return PersonnelAccessPicker(
      seleccion: seleccion,
      modulos: modulos,
      gestionadosPorAdmin: gestionadosPorAdmin,
      onChanged: (next) => setLocal(() => seleccion = next),
    );
  }

  if (isWide) {
    return showDialog<Set<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titulo,
                style: const TextStyle(
                  fontFamily: _kFont,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(subtitulo, style: Theme.of(ctx).textTheme.bodySmall),
            ],
          ),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(child: contenido(setLocal)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, seleccion),
              child: const Text('Guardar accesos'),
            ),
          ],
        ),
      ),
    );
  }

  return showModalBottomSheet<Set<String>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, controller) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    style: const TextStyle(
                      fontFamily: _kFont,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                  Text(subtitulo, style: Theme.of(ctx).textTheme.bodySmall),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: contenido(setLocal),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancelar'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(ctx, seleccion),
                        child: const Text('Guardar'),
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
  );
}
