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

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
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

  List<PersonnelAccessRow> get _visibles {
    final q = _buscarCtrl.text.trim().toLowerCase();
    return _personal.where((row) {
      if (_soloActivos && !row.activo) return false;
      if (_filtroModulo.isNotEmpty &&
          !row.apps.any((app) => appIdsEquivalent(app, _filtroModulo))) {
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
      await _cargar();
    } catch (e) {
      _mensaje('No se pudo guardar: $e', error: true);
    }
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
              FilterChip(
                selected: _soloActivos,
                onSelected: (v) => setState(() {
                  _soloActivos = v;
                  _pagina = 0;
                }),
                label: const Text('Solo personal activo'),
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
