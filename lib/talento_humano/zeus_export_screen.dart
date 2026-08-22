import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';

import '../home/widgets/home_shared_widgets.dart' show CompanyNameWidget;
import '../widgets/internal_module_layout.dart';
import '../widgets/user_avatar.dart';
import 'zeus_export_service.dart';

const Color _zeusPrimary = Color(0xFFC28942);
const Color _zeusInk = Color(0xFF111827);
const Color _zeusMuted = Color(0xFF64748B);
const String _font = 'Arial';

class ZeusExportScreen extends StatefulWidget {
  final String userId;
  final String empresaId;

  const ZeusExportScreen({
    super.key,
    required this.userId,
    required this.empresaId,
  });

  @override
  State<ZeusExportScreen> createState() => _ZeusExportScreenState();
}

class _ZeusExportScreenState extends State<ZeusExportScreen> {
  final _service = ZeusExportService();
  final _newUserFormKey = GlobalKey<FormState>();
  final _newCedula = TextEditingController();
  final _newPrimerNombre = TextEditingController();
  final _newSegundoNombre = TextEditingController();
  final _newPrimerApellido = TextEditingController();
  final _newSegundoApellido = TextEditingController();
  final _newCorreo = TextEditingController();
  final _newArea = TextEditingController();
  final _newCargo = TextEditingController();
  final _newCentro = TextEditingController();
  final _searchController = TextEditingController();

  ZeusExportSummary? _summary;
  bool _loading = true;
  bool _downloading = false;
  bool _creatingUser = false;
  bool _syncing = false;
  int _selectedTab = 0;
  String _estado = '';
  String _area = '';
  String _cargo = '';
  String _search = '';
  final _areaOptions = <String>{};
  final _cargoOptions = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _newCedula.dispose();
    _newPrimerNombre.dispose();
    _newSegundoNombre.dispose();
    _newPrimerApellido.dispose();
    _newSegundoApellido.dispose();
    _newCorreo.dispose();
    _newArea.dispose();
    _newCargo.dispose();
    _newCentro.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final summary = await _service
          .loadSummary(
            widget.empresaId,
            filter: ZeusExportFilter(
              estado: _estado,
              area: _area,
              cargo: _cargo,
            ),
          )
          .timeout(const Duration(seconds: 25));
      _areaOptions.addAll(summary.areas);
      _cargoOptions.addAll(summary.cargos);
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error cargando exportación Zeus: $e')),
      );
    }
  }

  Future<void> _syncAllTables() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Sincronizado desde usuarios, hojas de vida, estructura, cargos, áreas, centros y catálogos Zeus.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _download() async {
    final summary = _summary;
    if (summary == null || _downloading) return;
    setState(() => _downloading = true);
    try {
      final bytes = await _service.exportToExcelBytes(summary);
      final now = DateTime.now();
      final stamp =
          '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
      await FileSaver.instance.saveFile(
        name: 'zeus_alta_${widget.empresaId}_$stamp',
        bytes: bytes,
        fileExtension: 'xlsx',
        mimeType: MimeType.microsoftExcel,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Excel Zeus descargado.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error generando Excel Zeus: $e')));
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _editConfig() async {
    final summary = _summary;
    final current = Map<String, String>.from(summary?.config ?? {});
    final controllers = {
      for (final item in _configFields)
        item.key: TextEditingController(text: current[item.key] ?? ''),
    };

    final saved = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Configuración Zeus TH'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final item in _configFields) ...[
                  TextField(
                    controller: controllers[item.key],
                    decoration: InputDecoration(
                      labelText: item.label,
                      helperText: item.help,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx, {
                for (final entry in controllers.entries)
                  entry.key: entry.value.text.trim(),
              });
            },
            icon: const Icon(Icons.save_rounded),
            label: const Text('Guardar'),
          ),
        ],
      ),
    );

    for (final controller in controllers.values) {
      controller.dispose();
    }
    if (saved == null) return;
    await _service.saveConfig(widget.empresaId, saved);
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Configuración Zeus actualizada.')),
    );
  }

  Future<void> _editEmployee(ZeusEmployeeBundle employee) async {
    final controllers = {
      for (final field in _employeeFields)
        field.key: TextEditingController(
          text: _employeeFieldValue(employee, field.key),
        ),
    };
    void syncFromSources() {
      for (final field in _employeeFields) {
        controllers[field.key]?.text = _employeeFieldValue(employee, field.key);
      }
    }

    final saved = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final completion = _completionFor(employee);
          final width = MediaQuery.sizeOf(ctx).width;
          final compact = width < 720;
          return AlertDialog(
            insetPadding: EdgeInsets.symmetric(
              horizontal: compact ? 14 : 36,
              vertical: 20,
            ),
            contentPadding: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            content: SizedBox(
              width: compact ? width - 28 : 760,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(ctx).height * 0.86,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildEmployeeDialogHeader(employee, completion),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSourceSummary(employee),
                            const SizedBox(height: 16),
                            _buildEmployeeDialogSection(
                              title: 'Contrato Zeus',
                              icon: Icons.assignment_ind_rounded,
                              fields: _contractEmployeeFields,
                              controllers: controllers,
                            ),
                            const SizedBox(height: 16),
                            _buildEmployeeDialogSection(
                              title: 'Pago y banco',
                              icon: Icons.account_balance_rounded,
                              fields: _paymentEmployeeFields,
                              controllers: controllers,
                            ),
                            const SizedBox(height: 16),
                            _buildEmployeeDialogSection(
                              title: 'Organización y distribución',
                              icon: Icons.account_tree_rounded,
                              fields: _organizationEmployeeFields,
                              controllers: controllers,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actionsPadding: const EdgeInsets.fromLTRB(22, 0, 22, 18),
            actions: [
              TextButton.icon(
                onPressed: () {
                  syncFromSources();
                  setDialogState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Datos recargados desde usuarios, hoja de vida y estructura.',
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.sync_rounded),
                label: const Text('Sincronizar datos'),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx, {
                    for (final entry in controllers.entries)
                      entry.key: entry.value.text.trim(),
                  });
                },
                icon: const Icon(Icons.save_rounded),
                label: const Text('Guardar'),
              ),
            ],
          );
        },
      ),
    );
    for (final controller in controllers.values) {
      controller.dispose();
    }
    if (saved == null) return;
    await _service.saveEmployeeZeusData(
      widget.empresaId,
      employee.cedula,
      saved,
    );
    await _load();
  }

  Widget _buildEmployeeDialogHeader(
    ZeusEmployeeBundle employee,
    double completion,
  ) {
    final percent = (completion * 100).round();
    final color = completion >= 0.9
        ? const Color(0xFF16A34A)
        : completion >= 0.65
        ? _zeusPrimary
        : const Color(0xFFEA580C);
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: LayoutBuilder(
        builder: (_, constraints) {
          final compact = constraints.maxWidth < 520;
          final identity = Row(
            children: [
              _ZeusAvatar(employee: employee, color: color, radius: 30),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      employee.nombreCompleto,
                      style: const TextStyle(
                        fontFamily: _font,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: _zeusInk,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${employee.cedula} · ${employee.cargo.isEmpty ? 'Sin cargo' : employee.cargo}',
                      style: const TextStyle(
                        fontFamily: _font,
                        color: _zeusMuted,
                      ),
                    ),
                    Text(
                      employee.area.isEmpty
                          ? 'Sin área asignada'
                          : employee.area,
                      style: const TextStyle(
                        fontFamily: _font,
                        color: _zeusMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
          final progress = SizedBox(
            width: compact ? double.infinity : 150,
            child: _CompletionIndicator(percent: percent, color: color),
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [identity, const SizedBox(height: 14), progress],
            );
          }
          return Row(
            children: [
              Expanded(child: identity),
              const SizedBox(width: 18),
              progress,
            ],
          );
        },
      ),
    );
  }

  Widget _buildSourceSummary(ZeusEmployeeBundle employee) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _SourceChip(label: 'Usuario', active: employee.user.isNotEmpty),
        _SourceChip(label: 'Hoja de vida', active: employee.hv.isNotEmpty),
        _SourceChip(
          label: 'Estructura',
          active: employee.org.isNotEmpty || employee.empresaDetail.isNotEmpty,
        ),
        _SourceChip(label: 'Datos Zeus', active: employee.zeusData.isNotEmpty),
      ],
    );
  }

  Widget _buildEmployeeDialogSection({
    required String title,
    required IconData icon,
    required List<_ConfigField> fields,
    required Map<String, TextEditingController> controllers,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: _zeusPrimary, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontFamily: _font,
                  fontWeight: FontWeight.w900,
                  color: _zeusInk,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (_, constraints) {
              final twoCols = constraints.maxWidth >= 610;
              final itemWidth = twoCols
                  ? (constraints.maxWidth - 12) / 2
                  : double.infinity;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final field in fields)
                    SizedBox(
                      width: itemWidth,
                      child: TextField(
                        controller: controllers[field.key],
                        decoration: InputDecoration(
                          labelText: field.label,
                          helperText: field.help,
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _createBasicUser() async {
    if (!_newUserFormKey.currentState!.validate() || _creatingUser) return;
    setState(() => _creatingUser = true);
    try {
      await _service.createBasicUser(
        empresaId: widget.empresaId,
        cedula: _newCedula.text.replaceAll(RegExp(r'[^0-9]'), ''),
        primerNombre: _newPrimerNombre.text,
        segundoNombre: _newSegundoNombre.text,
        primerApellido: _newPrimerApellido.text,
        segundoApellido: _newSegundoApellido.text,
        correo: _newCorreo.text,
        area: _newArea.text,
        cargo: _newCargo.text,
        centroCostos: _newCentro.text,
      );
      _newCedula.clear();
      _newPrimerNombre.clear();
      _newSegundoNombre.clear();
      _newPrimerApellido.clear();
      _newSegundoApellido.clear();
      _newCorreo.clear();
      _newArea.clear();
      _newCargo.clear();
      _newCentro.clear();
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Usuario activado. Cédula y contraseña temporal: 123456.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error creando usuario: $e')));
    } finally {
      if (mounted) setState(() => _creatingUser = false);
    }
  }

  void _showPendings() {
    final pendings = _summary?.pendientes ?? const <ZeusExportPending>[];
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.72,
          minChildSize: 0.35,
          maxChildSize: 0.9,
          builder: (_, controller) => Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Pendientes para Zeus',
                  style: TextStyle(
                    fontFamily: _font,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  pendings.isEmpty
                      ? 'No hay pendientes con los filtros actuales.'
                      : '${pendings.length} campos por revisar antes de cargar a Zeus.',
                  style: const TextStyle(fontFamily: _font, color: _zeusMuted),
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: pendings.isEmpty
                      ? const Center(child: Text('Todo listo.'))
                      : ListView.separated(
                          controller: controller,
                          itemCount: pendings.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (_, index) {
                            final p = pendings[index];
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: UserAvatar(
                                userId: p.cedula,
                                nameHint: p.nombre,
                                backgroundColor: const Color(0xFFFFF7ED),
                                foregroundColor: _zeusPrimary,
                              ),
                              title: UserNameText(
                                p.cedula,
                                fallbackName: p.nombre,
                                style: const TextStyle(
                                  fontFamily: _font,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              subtitle: Text('${p.campo}: ${p.detalle}'),
                              trailing: Text(
                                p.cedula,
                                style: const TextStyle(
                                  fontFamily: _font,
                                  color: _zeusMuted,
                                  fontSize: 12,
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return InternalModuleLayout(
      userId: widget.userId,
      empresaId: widget.empresaId,
      title: 'Exportar Zeus',
      subtitle: 'Alta de empleados desde Talento Humano',
      accentColor: _zeusPrimary,
      headerActions: [
        CompanyNameWidget(
          empresaId: widget.empresaId,
          style: const TextStyle(
            color: _zeusPrimary,
            fontFamily: _font,
            fontWeight: FontWeight.w800,
            fontSize: 14,
          ),
        ),
      ],
      child: RefreshIndicator(
        onRefresh: _load,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: InternalModuleViewport(
            maxWidth: 1120,
            padding: const EdgeInsets.all(24),
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.only(top: 80),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSummary(),
                      const SizedBox(height: 18),
                      InternalModuleTabs(
                        items: const [
                          InternalModuleTabItem(
                            label: 'Personas',
                            icon: Icons.badge_rounded,
                          ),
                          InternalModuleTabItem(
                            label: 'Configuración',
                            icon: Icons.tune_rounded,
                          ),
                          InternalModuleTabItem(
                            label: 'Nuevo usuario',
                            icon: Icons.person_add_alt_1_rounded,
                          ),
                        ],
                        selectedIndex: _selectedTab,
                        onSelected: (i) => setState(() => _selectedTab = i),
                        accentColor: _zeusPrimary,
                      ),
                      const SizedBox(height: 18),
                      if (_selectedTab == 0) ...[
                        _buildFilters(),
                        const SizedBox(height: 18),
                        _buildActions(),
                        const SizedBox(height: 18),
                        _buildPeopleEditor(),
                      ] else if (_selectedTab == 1) ...[
                        _buildConfigPanel(),
                      ] else ...[
                        _buildNewUserPanel(),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildSummary() {
    final summary = _summary;
    return LayoutBuilder(
      builder: (_, constraints) {
        final narrow = constraints.maxWidth < 760;
        final cards = [
          _MetricCard(
            label: 'Personas filtradas',
            value: '${summary?.total ?? 0}',
            icon: Icons.groups_rounded,
            color: const Color(0xFF2563EB),
          ),
          _MetricCard(
            label: 'Listas',
            value: '${summary?.exportables ?? 0}',
            icon: Icons.check_circle_rounded,
            color: const Color(0xFF16A34A),
          ),
          _MetricCard(
            label: 'Con pendientes',
            value: '${summary?.conPendientes ?? 0}',
            icon: Icons.error_rounded,
            color: const Color(0xFFEA580C),
          ),
        ];
        if (narrow) {
          return Column(
            children: [
              for (final card in cards) ...[card, const SizedBox(height: 10)],
            ],
          );
        }
        return Row(
          children: [
            for (var i = 0; i < cards.length; i++) ...[
              Expanded(child: cards[i]),
              if (i < cards.length - 1) const SizedBox(width: 14),
            ],
          ],
        );
      },
    );
  }

  Widget _buildFilters() {
    final areas = _areaOptions.toList()..sort();
    final cargos = _cargoOptions.toList()..sort();
    return ModuleCard(
      padding: const EdgeInsets.all(18),
      child: LayoutBuilder(
        builder: (_, constraints) {
          final narrow = constraints.maxWidth < 820;
          final searchField = TextField(
            controller: _searchController,
            decoration: InputDecoration(
              labelText: 'Buscar persona',
              hintText: 'Nombre, cédula, cargo o área',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _search.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Limpiar búsqueda',
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _search = '');
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
              border: const OutlineInputBorder(),
            ),
            onChanged: (value) => setState(() => _search = value.trim()),
          );
          final fields = [
            _FilterField(
              label: 'Estado HV',
              value: _estado,
              items: const {
                '': 'Todos',
                'sin_enviar': 'Sin enviar',
                'en_revision': 'En revisión',
                'aprobado': 'Aprobado',
                'requiere_cambios': 'Correcciones',
              },
              onChanged: (v) {
                _estado = v ?? '';
                _load();
              },
            ),
            _FilterField(
              label: 'Área',
              value: _area,
              items: {'': 'Todas', for (final a in areas) a: a},
              onChanged: (v) {
                _area = v ?? '';
                _load();
              },
            ),
            _FilterField(
              label: 'Cargo',
              value: _cargo,
              items: {'': 'Todos', for (final c in cargos) c: c},
              onChanged: (v) {
                _cargo = v ?? '';
                _load();
              },
            ),
          ];
          if (narrow) {
            return Column(
              children: [
                searchField,
                const SizedBox(height: 12),
                for (final field in fields) ...[
                  field,
                  if (field != fields.last) const SizedBox(height: 12),
                ],
              ],
            );
          }
          return Column(
            children: [
              searchField,
              const SizedBox(height: 12),
              Row(
                children: [
                  for (var i = 0; i < fields.length; i++) ...[
                    Expanded(child: fields[i]),
                    if (i < fields.length - 1) const SizedBox(width: 12),
                  ],
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  bool _matchesSearch(ZeusEmployeeBundle employee) {
    final query = _search.toLowerCase();
    if (query.isEmpty) return true;
    final haystack = [
      employee.nombreCompleto,
      employee.cedula,
      employee.cargo,
      employee.area,
      employee.email,
      employee.banco,
      employee.eps,
    ].join(' ').toLowerCase();
    return haystack.contains(query);
  }

  Widget _buildSearchEmptyState() {
    return ModuleCard(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _zeusPrimary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.person_search_rounded, color: _zeusPrimary),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Text(
              'No encontré personas con esa búsqueda dentro de los filtros actuales.',
              style: TextStyle(fontFamily: _font, color: _zeusMuted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    return ModuleCard(
      padding: const EdgeInsets.all(18),
      child: LayoutBuilder(
        builder: (_, constraints) {
          final narrow = constraints.maxWidth < 740;
          final downloadButton = ElevatedButton.icon(
            onPressed: _downloading || (_summary?.total ?? 0) == 0
                ? null
                : _download,
            icon: _downloading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_rounded),
            label: Text(_downloading ? 'Generando...' : 'Descargar XLSX Zeus'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _zeusPrimary,
              foregroundColor: Colors.white,
              minimumSize: const Size(190, 46),
            ),
          );
          final configButton = OutlinedButton.icon(
            onPressed: _editConfig,
            icon: const Icon(Icons.tune_rounded),
            label: const Text('Configurar TH'),
          );
          final syncButton = OutlinedButton.icon(
            onPressed: _syncing ? null : _syncAllTables,
            icon: _syncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync_rounded),
            label: Text(_syncing ? 'Sincronizando...' : 'Sincronizar tablas'),
          );
          final pendingButton = OutlinedButton.icon(
            onPressed: _showPendings,
            icon: const Icon(Icons.rule_rounded),
            label: const Text('Ver pendientes'),
          );
          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                downloadButton,
                const SizedBox(height: 10),
                configButton,
                const SizedBox(height: 10),
                syncButton,
                const SizedBox(height: 10),
                pendingButton,
              ],
            );
          }
          return Row(
            children: [
              downloadButton,
              const SizedBox(width: 12),
              configButton,
              const SizedBox(width: 12),
              syncButton,
              const SizedBox(width: 12),
              pendingButton,
              const Spacer(),
              Text(
                'XLSX equivalente a plantilla Zeus',
                style: TextStyle(
                  fontFamily: _font,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPeopleEditor() {
    final summary = _summary;
    final people = (summary?.empleados ?? const <ZeusEmployeeBundle>[])
        .where(_matchesSearch)
        .toList();
    if (people.isEmpty) {
      if (_search.isNotEmpty) return _buildSearchEmptyState();
      return ModuleCard(
        padding: const EdgeInsets.all(24),
        child: const Center(
          child: Text('No hay personas con los filtros actuales.'),
        ),
      );
    }
    return Column(
      children: [
        for (final employee in people) ...[
          _EmployeeZeusCard(
            employee: employee,
            pendings: _pendingsFor(employee),
            completion: _completionFor(employee),
            onEdit: () => _editEmployee(employee),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _buildConfigPanel() {
    final summary = _summary;
    final config = summary?.config ?? const <String, String>{};
    final catalogs = summary?.indexes.catalogs;
    final stats = [
      _CatalogStat('EPS', catalogs?.eps.length ?? 0),
      _CatalogStat('Pensiones', catalogs?.pension.length ?? 0),
      _CatalogStat('Cesantías', catalogs?.cesantias.length ?? 0),
      _CatalogStat('Bancos', catalogs?.bancos.length ?? 0),
      _CatalogStat('Profesiones', catalogs?.profesiones.length ?? 0),
      _CatalogStat('Cargos', summary?.indexes.cargos.length ?? 0),
      _CatalogStat('Centros', summary?.indexes.centros.length ?? 0),
      _CatalogStat('Ciudades', summary?.indexes.ciudades.length ?? 0),
    ];
    return Column(
      children: [
        ModuleCard(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              const Icon(Icons.settings_suggest_rounded, color: _zeusPrimary),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Configuración y catálogos usados por el Excel',
                      style: TextStyle(
                        fontFamily: _font,
                        fontWeight: FontWeight.w900,
                        color: _zeusInk,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Los defaults aplican solo cuando el empleado no tiene dato individual.',
                      style: TextStyle(fontFamily: _font, color: _zeusMuted),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: _editConfig,
                icon: const Icon(Icons.tune_rounded),
                label: const Text('Editar defaults TH'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        ModuleCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Fuentes que se sincronizan',
                style: TextStyle(
                  fontFamily: _font,
                  fontWeight: FontWeight.w900,
                  color: _zeusInk,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final table in _zeusSourceTables)
                    Chip(
                      label: Text(table),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: const Color(0xFFF8FAFC),
                      side: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (_, constraints) {
            final width = constraints.maxWidth;
            final itemWidth = width < 700 ? width : (width - 28) / 3;
            return Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                for (final stat in stats)
                  SizedBox(
                    width: itemWidth,
                    child: _CatalogStatCard(stat: stat),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 14),
        ModuleCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Defaults actuales',
                style: TextStyle(
                  fontFamily: _font,
                  fontWeight: FontWeight.w900,
                  color: _zeusInk,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final field in _configFields)
                    _InfoPill(
                      label: field.label,
                      value: (config[field.key] ?? '').trim().isEmpty
                          ? 'Pendiente'
                          : config[field.key]!,
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNewUserPanel() {
    return ModuleCard(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _newUserFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Activar usuario nuevo',
              style: TextStyle(
                fontFamily: _font,
                fontWeight: FontWeight.w900,
                color: _zeusInk,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Crea la base para que la persona ingrese con su cédula y contraseña temporal 123456, luego complete su hoja de vida.',
              style: TextStyle(fontFamily: _font, color: _zeusMuted),
            ),
            const SizedBox(height: 18),
            LayoutBuilder(
              builder: (_, constraints) {
                final twoCols = constraints.maxWidth >= 720;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _newField(
                      _newCedula,
                      'Cédula',
                      required: true,
                      numeric: true,
                      twoCols: twoCols,
                    ),
                    _newField(_newCorreo, 'Correo', twoCols: twoCols),
                    _newField(
                      _newPrimerNombre,
                      'Primer nombre',
                      required: true,
                      twoCols: twoCols,
                    ),
                    _newField(
                      _newSegundoNombre,
                      'Segundo nombre',
                      twoCols: twoCols,
                    ),
                    _newField(
                      _newPrimerApellido,
                      'Primer apellido',
                      required: true,
                      twoCols: twoCols,
                    ),
                    _newField(
                      _newSegundoApellido,
                      'Segundo apellido',
                      twoCols: twoCols,
                    ),
                    _newField(_newArea, 'Área inicial', twoCols: twoCols),
                    _newField(_newCargo, 'Cargo inicial', twoCols: twoCols),
                    _newField(
                      _newCentro,
                      'Centro de costos inicial',
                      twoCols: twoCols,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 18),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: _creatingUser ? null : _createBasicUser,
                icon: _creatingUser
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.person_add_alt_1_rounded),
                label: Text(_creatingUser ? 'Creando...' : 'Crear y activar'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _zeusPrimary,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _newField(
    TextEditingController controller,
    String label, {
    bool required = false,
    bool numeric = false,
    required bool twoCols,
  }) {
    return SizedBox(
      width: twoCols ? 320 : double.infinity,
      child: TextFormField(
        controller: controller,
        keyboardType: numeric ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        validator: (value) {
          if (required && (value ?? '').trim().isEmpty) {
            return 'Campo requerido';
          }
          return null;
        },
      ),
    );
  }

  List<ZeusExportPending> _pendingsFor(ZeusEmployeeBundle employee) {
    return (_summary?.pendientes ?? const <ZeusExportPending>[])
        .where((p) => p.cedula == employee.cedula)
        .toList();
  }

  double _completionFor(ZeusEmployeeBundle employee) {
    final missing = _pendingsFor(employee).map((p) => p.campo).toSet().length;
    final done = (_completionBase - missing)
        .clamp(0, _completionBase)
        .toDouble();
    return done / _completionBase;
  }

  String _employeeFieldValue(ZeusEmployeeBundle employee, String key) {
    final direct = employee.zeus(key);
    if (direct.isNotEmpty) return direct;
    switch (key) {
      case 'sueldoBasico':
        return employee.sueldoBasico;
      case 'fechaInicioContrato':
        return employee.fechaInicioContrato;
      case 'fechaVencimientoContrato':
        return employee.fechaVencimientoContrato;
      case 'tipoContrato':
        return employee.tipoContrato;
      case 'tipoNomina':
        return employee.tipoNomina;
      case 'formaPago':
        return employee.formaPago;
      case 'horasTrabajadasMes':
        return employee.horasTrabajadasMes;
      case 'banco':
        return employee.banco;
      case 'tipoCuenta':
        return employee.tipoCuenta;
      case 'cuentaBancaria':
        return employee.cuentaBancaria;
      case 'centroTrabajoCodigo':
        return employee.centroTrabajoCodigo;
      case 'unidadNegocio':
        return employee.unidadNegocio;
      case 'codigoContrato':
        return employee.codigoContrato;
      default:
        return _summary?.config[key] ?? '';
    }
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return ModuleCard(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontFamily: _font,
                    color: color,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(
                    fontFamily: _font,
                    color: _zeusMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ZeusAvatar extends StatelessWidget {
  final ZeusEmployeeBundle employee;
  final Color color;
  final double radius;

  const _ZeusAvatar({
    required this.employee,
    required this.color,
    this.radius = 20,
  });

  @override
  Widget build(BuildContext context) {
    // Si el bundle no trae foto, UserAvatar la resuelve por cédula.
    return UserAvatar(
      userId: employee.cedula,
      nameHint: employee.nombreCompleto,
      fotoUrlHint: employee.fotoUrl.isNotEmpty ? employee.fotoUrl : null,
      radius: radius,
      backgroundColor: color.withValues(alpha: 0.12),
      foregroundColor: color,
    );
  }
}

class _EmployeeZeusCard extends StatelessWidget {
  final ZeusEmployeeBundle employee;
  final List<ZeusExportPending> pendings;
  final double completion;
  final VoidCallback onEdit;

  const _EmployeeZeusCard({
    required this.employee,
    required this.pendings,
    required this.completion,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final percent = (completion * 100).round();
    final color = completion >= 0.9
        ? const Color(0xFF16A34A)
        : completion >= 0.65
        ? _zeusPrimary
        : const Color(0xFFEA580C);
    return ModuleCard(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (_, constraints) {
          final narrow = constraints.maxWidth < 760;
          final facts = [
            _ZeusFact('EPS', employee.eps),
            _ZeusFact('Banco', employee.banco),
            _ZeusFact('Centro', employee.centroTrabajoCodigo),
            _ZeusFact('Contrato', employee.tipoContrato),
          ].where((fact) => fact.value.trim().isNotEmpty).toList();
          final header = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ZeusAvatar(employee: employee, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      employee.nombreCompleto,
                      style: const TextStyle(
                        fontFamily: _font,
                        fontWeight: FontWeight.w900,
                        color: _zeusInk,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${employee.cargo.isEmpty ? 'Sin cargo' : employee.cargo} · ${employee.area.isEmpty ? 'Sin área' : employee.area}',
                      style: const TextStyle(
                        fontFamily: _font,
                        color: _zeusMuted,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      employee.cedula,
                      style: const TextStyle(
                        fontFamily: _font,
                        color: _zeusMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (!narrow)
                SizedBox(
                  width: 150,
                  child: _CompletionIndicator(percent: percent, color: color),
                ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_rounded, size: 18),
                label: const Text('Editar'),
              ),
            ],
          );
          final pendingPreview = pendings.isEmpty
              ? const Text(
                  'Listo para Zeus con los datos actuales.',
                  style: TextStyle(fontFamily: _font, color: _zeusMuted),
                )
              : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final p in pendings.take(5))
                      Chip(
                        label: Text(p.campo),
                        visualDensity: VisualDensity.compact,
                        backgroundColor: const Color(0xFFFFF7ED),
                        side: BorderSide(color: color.withValues(alpha: 0.25)),
                      ),
                    if (pendings.length > 5)
                      Chip(
                        label: Text('+${pendings.length - 5}'),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              header,
              if (narrow) ...[
                const SizedBox(height: 12),
                _CompletionIndicator(percent: percent, color: color),
              ],
              const SizedBox(height: 12),
              if (facts.isNotEmpty) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final fact in facts.take(4))
                      _ZeusFactChip(label: fact.label, value: fact.value),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              pendingPreview,
            ],
          );
        },
      ),
    );
  }
}

class _CompletionIndicator extends StatelessWidget {
  final int percent;
  final Color color;

  const _CompletionIndicator({required this.percent, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '$percent%',
          style: TextStyle(
            fontFamily: _font,
            color: color,
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: percent / 100,
            minHeight: 8,
            backgroundColor: const Color(0xFFE2E8F0),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

class _SourceChip extends StatelessWidget {
  final String label;
  final bool active;

  const _SourceChip({required this.label, required this.active});

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(
        active ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
        size: 16,
        color: active ? const Color(0xFF16A34A) : _zeusMuted,
      ),
      label: Text(label),
      visualDensity: VisualDensity.compact,
      backgroundColor: active
          ? const Color(0xFFF0FDF4)
          : const Color(0xFFF8FAFC),
      side: BorderSide(
        color: active ? const Color(0xFFBBF7D0) : const Color(0xFFE2E8F0),
      ),
      labelStyle: const TextStyle(
        fontFamily: _font,
        fontWeight: FontWeight.w700,
        color: _zeusInk,
      ),
    );
  }
}

class _ZeusFact {
  final String label;
  final String value;

  const _ZeusFact(this.label, this.value);
}

class _ZeusFactChip extends StatelessWidget {
  final String label;
  final String value;

  const _ZeusFactChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(
            fontFamily: _font,
            color: _zeusInk,
            fontSize: 12,
          ),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(
                color: _zeusMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

class _CatalogStat {
  final String label;
  final int count;

  const _CatalogStat(this.label, this.count);
}

class _CatalogStatCard extends StatelessWidget {
  final _CatalogStat stat;

  const _CatalogStatCard({required this.stat});

  @override
  Widget build(BuildContext context) {
    return ModuleCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _zeusPrimary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.dataset_rounded, color: _zeusPrimary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${stat.count}',
                  style: const TextStyle(
                    fontFamily: _font,
                    fontWeight: FontWeight.w900,
                    color: _zeusInk,
                    fontSize: 20,
                  ),
                ),
                Text(
                  stat.label,
                  style: const TextStyle(
                    fontFamily: _font,
                    color: _zeusMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final String label;
  final String value;

  const _InfoPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final pending = value == 'Pendiente';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: pending ? const Color(0xFFFFF7ED) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: pending ? const Color(0xFFFED7AA) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          fontFamily: _font,
          color: pending ? const Color(0xFF9A3412) : const Color(0xFF334155),
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _FilterField extends StatelessWidget {
  final String label;
  final String value;
  final Map<String, String> items;
  final ValueChanged<String?> onChanged;

  const _FilterField({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final safeValue = items.containsKey(value) ? value : '';
    return DropdownButtonFormField<String>(
      initialValue: safeValue,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
      ),
      items: [
        for (final entry in items.entries)
          DropdownMenuItem(
            value: entry.key,
            child: Text(entry.value, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: onChanged,
    );
  }
}

class _ConfigField {
  final String key;
  final String label;
  final String help;

  const _ConfigField(this.key, this.label, this.help);
}

const int _completionBase = 12;

const _zeusSourceTables = [
  'TBL_USUARIOS',
  'hoja_de_vida/datos',
  'TBL_ESTRUCTURA_ORGANIZACIONAL',
  'TBL_CARGOS',
  'TBL_AREAS',
  'TBL_CENTROS_COSTOS',
  'TBL_CIUDADES',
  'TBL_ZEUS_CONFIG',
  'TBL_ZEUS_EMPLEADOS',
  'Catálogos EPS / pensión / cesantías / bancos',
];

const _contractEmployeeFields = [
  _ConfigField('sueldoBasico', 'Sueldo básico', 'Valor propio del empleado.'),
  _ConfigField(
    'fechaInicioContrato',
    'Fecha inicio contrato',
    'Formato recomendado AAAA/MM/DD.',
  ),
  _ConfigField(
    'fechaVencimientoContrato',
    'Fecha vencimiento contrato',
    'Solo si aplica.',
  ),
  _ConfigField('tipoContrato', 'Tipo contrato', 'I, D o F según Zeus.'),
  _ConfigField(
    'tipoNomina',
    'Tipo de nómina',
    'Si no se llena usa default TH.',
  ),
  _ConfigField('formaPago', 'Forma de pago', 'Código Zeus de forma de pago.'),
  _ConfigField('horasTrabajadasMes', 'Horas trabajadas mes', 'Ej: 240.'),
  _ConfigField(
    'codigoContrato',
    'Código contrato',
    'Si queda vacío usa la cédula.',
  ),
];

const _paymentEmployeeFields = [
  _ConfigField(
    'banco',
    'Banco',
    'Nombre como aparece en catálogo/banco de la app.',
  ),
  _ConfigField(
    'tipoCuenta',
    'Tipo de cuenta',
    'Ahorros, corriente o código Zeus.',
  ),
  _ConfigField(
    'cuentaBancaria',
    'Número de cuenta',
    'Cuenta para pago de nómina.',
  ),
];

const _organizationEmployeeFields = [
  _ConfigField(
    'centroTrabajoCodigo',
    'Centro de trabajo',
    'Código Zeus si difiere del centro asignado.',
  ),
  _ConfigField('unidadNegocio', 'Unidad de negocio', 'Código Zeus si aplica.'),
];

const _employeeFields = [
  ..._contractEmployeeFields,
  ..._paymentEmployeeFields,
  ..._organizationEmployeeFields,
];

const _configFields = [
  _ConfigField('sueldoBasico', 'Sueldo básico', 'Valor base para ZContrato1.'),
  _ConfigField(
    'fechaInicioContrato',
    'Fecha inicio contrato',
    'Formato recomendado AAAA/MM/DD.',
  ),
  _ConfigField('tipoContrato', 'Tipo contrato', 'I, D o F según Zeus.'),
  _ConfigField(
    'tipoNomina',
    'Tipo de nómina',
    'Código definido por TH en Zeus.',
  ),
  _ConfigField('formaPago', 'Forma de pago', 'Código Zeus de forma de pago.'),
  _ConfigField('horasTrabajadasMes', 'Horas trabajadas mes', 'Ej: 240.'),
  _ConfigField(
    'centroTrabajoCodigo',
    'Centro de trabajo default',
    'Se usa si el empleado no tiene centro.',
  ),
  _ConfigField('unidadNegocio', 'Unidad de negocio', 'Código Zeus si aplica.'),
  _ConfigField(
    'cajaCompensacionCodigo',
    'Caja compensación código',
    'Código Zeus de la caja.',
  ),
  _ConfigField(
    'cajaCompensacionNombre',
    'Caja compensación nombre',
    'Nombre para hoja ZCajas Compension1.',
  ),
  _ConfigField(
    'fondoRiesgoCodigo',
    'Fondo de riesgo / ARL',
    'Código Zeus de ARL/riesgo.',
  ),
  _ConfigField(
    'tipoCotizante',
    'Tipo cotizante',
    'Código de cotizante para seguridad social.',
  ),
  _ConfigField(
    'distribucionCuenta',
    'Cuenta distribución',
    'Cuenta contable de ZDistribución1.',
  ),
  _ConfigField(
    'distribucionTipoCuenta',
    'Tipo cuenta distribución',
    'Tipo de cuenta para distribución.',
  ),
  _ConfigField(
    'distribucionPorcentaje',
    'Porcentaje distribución',
    'Default 100.',
  ),
];
