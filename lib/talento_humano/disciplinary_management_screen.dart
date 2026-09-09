import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/internal_module_layout.dart';
import '../widgets/paged_list.dart';
import '../widgets/user_avatar.dart';
import 'disciplinary_service.dart';

const _primary = Color(0xFF9A5B32);
const _navy = Color(0xFF173B5E);
const _ink = Color(0xFF17212B);
const _muted = Color(0xFF64748B);
const _border = Color(0xFFE2E8F0);
const _surface = Color(0xFFF8FAFC);
const _danger = Color(0xFFB91C1C);
const _warning = Color(0xFFD97706);
const _success = Color(0xFF15803D);
const _font = 'Arial';

class DisciplinaryManagementScreen extends StatefulWidget {
  final String userId;
  final String empresaId;
  final String initialCedula;
  final String initialName;
  final String initialArea;
  final String initialRole;
  final String initialCostCenter;
  final String initialPhotoUrl;
  final bool initialActive;

  const DisciplinaryManagementScreen({
    super.key,
    required this.userId,
    required this.empresaId,
    this.initialCedula = '',
    this.initialName = '',
    this.initialArea = '',
    this.initialRole = '',
    this.initialCostCenter = '',
    this.initialPhotoUrl = '',
    this.initialActive = true,
  });

  @override
  State<DisciplinaryManagementScreen> createState() =>
      _DisciplinaryManagementScreenState();
}

class _DisciplinaryManagementScreenState
    extends State<DisciplinaryManagementScreen> {
  final _service = DisciplinaryService();
  final _searchController = TextEditingController();
  late Future<List<DisciplinaryPerson>> _peopleFuture;
  DisciplinaryPerson? _selected;
  // Arranca en 'activos': el listado operativo es la plantilla vigente. Los
  // retirados conservan su historial y siguen a un clic con 'Todos'/'Inactivos'.
  String _peopleFilter = 'activos';
  String _recordFilter = 'todos';

  @override
  void initState() {
    super.initState();
    if (widget.initialCedula.trim().isNotEmpty) {
      _selected = DisciplinaryPerson(
        cedula: widget.initialCedula.trim(),
        name: widget.initialName.trim().isEmpty
            ? widget.initialCedula.trim()
            : widget.initialName.trim(),
        area: widget.initialArea,
        role: widget.initialRole,
        costCenter: widget.initialCostCenter,
        photoUrl: widget.initialPhotoUrl,
        status: widget.initialActive ? 'activo' : 'inactivo',
      );
    }
    _peopleFuture = _service.loadPeople(widget.empresaId);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _reloadPeople() {
    setState(() => _peopleFuture = _service.loadPeople(widget.empresaId));
  }

  @override
  Widget build(BuildContext context) {
    return InternalModuleLayout(
      userId: widget.userId,
      empresaId: widget.empresaId,
      title: 'Proceso disciplinario',
      subtitle: 'Solicitud, citación a descargos, diligencia y resultado',
      accentColor: _primary,
      child: StreamBuilder<List<DisciplinaryRecord>>(
        stream: _service.watchCompany(widget.empresaId),
        builder: (context, recordSnapshot) {
          if (recordSnapshot.hasError) {
            return _ErrorState(
              message: 'No fue posible cargar los procesos disciplinarios.',
              detail: recordSnapshot.error.toString(),
            );
          }
          final records = recordSnapshot.data ?? const <DisciplinaryRecord>[];
          return FutureBuilder<List<DisciplinaryPerson>>(
            future: _peopleFuture,
            builder: (context, peopleSnapshot) {
              if (!peopleSnapshot.hasData && peopleSnapshot.hasError) {
                return _ErrorState(
                  message: 'No fue posible cargar el personal.',
                  detail: peopleSnapshot.error.toString(),
                );
              }
              final people =
                  peopleSnapshot.data ?? const <DisciplinaryPerson>[];
              _synchronizeSelected(people);
              if (!peopleSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              return LayoutBuilder(
                builder: (context, constraints) {
                  final desktop = constraints.maxWidth >= 920;
                  return desktop
                      ? _desktopLayout(people, records)
                      : _mobileLayout(people, records);
                },
              );
            },
          );
        },
      ),
    );
  }

  void _synchronizeSelected(List<DisciplinaryPerson> people) {
    final selected = _selected;
    if (selected == null) return;
    for (final person in people) {
      if (person.cedula == selected.cedula && person != selected) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _selected?.cedula == person.cedula) {
            setState(() => _selected = person);
          }
        });
        return;
      }
    }
  }

  Widget _desktopLayout(
    List<DisciplinaryPerson> people,
    List<DisciplinaryRecord> records,
  ) {
    return Row(
      children: [
        SizedBox(width: 360, child: _peoplePanel(people, records)),
        const VerticalDivider(width: 1, color: _border),
        Expanded(child: _folderPanel(records, mobile: false)),
      ],
    );
  }

  Widget _mobileLayout(
    List<DisciplinaryPerson> people,
    List<DisciplinaryRecord> records,
  ) {
    if (_selected == null) return _peoplePanel(people, records, mobile: true);
    return _folderPanel(
      records,
      mobile: true,
      onChangePerson: () => setState(() => _selected = null),
    );
  }

  Widget _peoplePanel(
    List<DisciplinaryPerson> people,
    List<DisciplinaryRecord> records, {
    bool mobile = false,
  }) {
    final term = _searchController.text.trim().toLowerCase();
    final filtered = people.where((person) {
      if (_peopleFilter == 'activos' && !person.isActive) return false;
      if (_peopleFilter == 'inactivos' && person.isActive) return false;
      if (term.isEmpty) return true;
      return person.name.toLowerCase().contains(term) ||
          person.cedula.contains(term) ||
          person.area.toLowerCase().contains(term) ||
          person.role.toLowerCase().contains(term);
    }).toList();
    final counts = <String, int>{};
    for (final record in records) {
      counts.update(record.cedula, (value) => value + 1, ifAbsent: () => 1);
    }
    final alerts = <String, int>{};
    for (final record in records.where((item) => item.isOverdue)) {
      alerts.update(record.cedula, (value) => value + 1, ifAbsent: () => 1);
    }

    return ColoredBox(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              mobile ? 16 : 20,
              mobile ? 16 : 20,
              mobile ? 16 : 20,
              12,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Carpetas del personal',
                            style: TextStyle(
                              fontFamily: _font,
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              color: _ink,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'Activos e inactivos conservan su historial',
                            style: TextStyle(
                              fontFamily: _font,
                              fontSize: 11,
                              color: _muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _reloadPeople,
                      tooltip: 'Actualizar personal',
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Buscar nombre, cédula, área o cargo',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _searchController.clear();
                              setState(() {});
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                    filled: true,
                    fillColor: _surface,
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: _border),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 'todos', label: Text('Todos')),
                    ButtonSegment(value: 'activos', label: Text('Activos')),
                    ButtonSegment(value: 'inactivos', label: Text('Inactivos')),
                  ],
                  selected: {_peopleFilter},
                  onSelectionChanged: (value) =>
                      setState(() => _peopleFilter = value.first),
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    textStyle: WidgetStatePropertyAll(
                      TextStyle(fontFamily: _font, fontSize: 11),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: _border),
          Expanded(
            child: filtered.isEmpty
                ? const Center(child: Text('No se encontró personal.'))
                : SingleChildScrollView(
                    padding: EdgeInsets.all(mobile ? 12 : 10),
                    child: PagedListSection<DisciplinaryPerson>(
                      // La clave lleva el filtro: al cambiar la búsqueda o el
                      // segmento la lista se vuelve a montar en la página 1.
                      // Sin esto, quien venía en la página 4 y teclea un
                      // nombre se queda mirando una página vacía.
                      key: ValueKey('$term|$_peopleFilter'),
                      items: filtered,
                      etiqueta: 'personas',
                      separator: const SizedBox(height: 7),
                      itemBuilder: (context, person, _) => _PersonFolderTile(
                        person: person,
                        count: counts[person.cedula] ?? 0,
                        overdue: alerts[person.cedula] ?? 0,
                        selected: _selected?.cedula == person.cedula,
                        onTap: () => setState(() => _selected = person),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _folderPanel(
    List<DisciplinaryRecord> companyRecords, {
    required bool mobile,
    VoidCallback? onChangePerson,
  }) {
    final person = _selected;
    if (person == null) {
      return const _EmptyFolderState();
    }
    final allRecords = companyRecords
        .where((record) => record.cedula == person.cedula)
        .toList();
    final metrics = DisciplinaryMetrics.fromRecords(allRecords);
    final records = allRecords.where((record) {
      if (_recordFilter == 'tramite') return record.isOpen;
      if (_recordFilter == 'vencidos') return record.isOverdue;
      if (_recordFilter == 'cerrados') return record.isClosed;
      return true;
    }).toList();

    return ColoredBox(
      color: _surface,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          mobile ? 14 : 26,
          mobile ? 14 : 24,
          mobile ? 14 : 26,
          30,
        ),
        child: InternalModuleViewport(
          maxWidth: 1040,
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (mobile)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: onChangePerson,
                    icon: const Icon(Icons.people_alt_outlined),
                    label: const Text('Cambiar colaborador'),
                  ),
                ),
              _PersonFolderHeader(
                person: person,
                metrics: metrics,
                onCreate: () => _showOpenDialog(person),
              ),
              const SizedBox(height: 16),
              _metricsGrid(metrics, mobile),
              const SizedBox(height: 18),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Historial disciplinario',
                      style: TextStyle(
                        fontFamily: _font,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: _ink,
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    initialValue: _recordFilter,
                    tooltip: 'Filtrar historial',
                    onSelected: (value) =>
                        setState(() => _recordFilter = value),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'todos', child: Text('Todos')),
                      PopupMenuItem(value: 'tramite', child: Text('En trámite')),
                      PopupMenuItem(value: 'vencidos', child: Text('Vencidos')),
                      PopupMenuItem(value: 'cerrados', child: Text('Cerrados')),
                    ],
                    child: _FilterButton(label: _recordFilterLabel),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (records.isEmpty)
                _NoRecords(onCreate: () => _showOpenDialog(person))
              else
                PagedListSection<DisciplinaryRecord>(
                  // Una carpeta antigua acumula años de procesos. La clave
                  // incluye persona y filtro para que al cambiarlos se
                  // empiece por la página 1.
                  key: ValueKey('${person.cedula}|$_recordFilter'),
                  items: records,
                  etiqueta: 'procesos',
                  separator: const SizedBox(height: 10),
                  itemBuilder: (context, record, _) => _RecordCard(
                    record: record,
                    onDetails: () => _showDetails(record),
                    onAdvance: record.isClosed
                        ? null
                        : () => _advanceStage(record),
                    onDiscard: record.stage == DisciplinaryStage.solicitud
                        ? () => _showDiscardDialog(record)
                        : null,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String get _recordFilterLabel {
    switch (_recordFilter) {
      case 'tramite':
        return 'En trámite';
      case 'vencidos':
        return 'Vencidos';
      case 'cerrados':
        return 'Cerrados';
      default:
        return 'Todos';
    }
  }

  Widget _metricsGrid(DisciplinaryMetrics metrics, bool mobile) {
    final cards = [
      _MetricData('Total', metrics.total, Icons.folder_copy_outlined, _navy),
      _MetricData(
        'En trámite',
        metrics.inProgress,
        Icons.pending_actions_rounded,
        _warning,
      ),
      _MetricData(
        'Vencidos',
        metrics.overdue,
        Icons.notification_important_rounded,
        _danger,
      ),
      _MetricData('Cerrados', metrics.closed, Icons.task_alt_rounded, _success),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: cards.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: mobile ? 2 : 4,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: mobile ? 1.95 : 1.75,
      ),
      itemBuilder: (_, index) => _MetricCard(data: cards[index]),
    );
  }

  /// Paso 1. Solo se radica lo que llegó: nunca se pide describir la falta.
  Future<void> _showOpenDialog(DisciplinaryPerson person) async {
    var receivedAt = DateTime.now();
    DisciplinaryUpload? document;
    var saving = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          titlePadding: EdgeInsets.zero,
          contentPadding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
          title: _DialogTitle(
            icon: Icons.markunread_mailbox_outlined,
            title: 'Apertura de proceso disciplinario',
            subtitle: '${person.name} · CC ${person.cedula}',
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _DialogHint(
                    'Se recibe la solicitud de apertura del proceso. Adjunta el '
                    'documento tal como llegó y registra la fecha de recibido.',
                  ),
                  const SizedBox(height: 16),
                  _DateField(
                    label: 'Fecha de recibido',
                    value: receivedAt,
                    icon: Icons.event_available_rounded,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now(),
                    onChanged: (value) =>
                        setDialogState(() => receivedAt = value),
                  ),
                  const SizedBox(height: 14),
                  _DocumentField(
                    label: 'Solicitud de apertura',
                    document: document,
                    onPick: () async {
                      final picked = await _pickDocument();
                      if (picked != null) {
                        setDialogState(() => document = picked);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: saving
                  ? null
                  : () async {
                      final upload = document;
                      if (upload == null) {
                        _message(
                          'Adjunta el documento de la solicitud de apertura.',
                          error: true,
                        );
                        return;
                      }
                      setDialogState(() => saving = true);
                      try {
                        await _service.abrirProceso(
                          empresaId: widget.empresaId,
                          person: person,
                          receivedAt: receivedAt,
                          document: upload,
                          createdBy: widget.userId,
                        );
                        if (!dialogContext.mounted) return;
                        Navigator.pop(dialogContext);
                        _message(
                          'Proceso abierto. Sigue la citación a descargos.',
                        );
                      } catch (error) {
                        setDialogState(() => saving = false);
                        _message('No fue posible guardar: $error', error: true);
                      }
                    },
              icon: _saveIcon(saving),
              label: const Text('Registrar apertura'),
            ),
          ],
        ),
      ),
    );
  }

  /// Paso 2. La fecha de la diligencia se propone a 5 días hábiles y es la que
  /// después dispara la alerta.
  Future<void> _showSummonDialog(DisciplinaryRecord record) async {
    var deliveredAt = DateTime.now();
    var hearingDate = DisciplinaryService.fechaDiligenciaSugerida(deliveredAt);
    var manualHearingDate = false;
    DisciplinaryUpload? document;
    var saving = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          titlePadding: EdgeInsets.zero,
          contentPadding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
          title: _DialogTitle(
            icon: Icons.mark_email_read_outlined,
            title: 'Citación a descargos',
            subtitle: '${record.personName} · CC ${record.cedula}',
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _DialogHint(
                    'Adjunta la citación entregada al colaborador. La fecha de '
                    'la diligencia se propone a $kDiasHabilesDescargos días '
                    'hábiles y es la que genera la alerta.',
                  ),
                  const SizedBox(height: 16),
                  _DateField(
                    label: 'Entrega de la citación',
                    value: deliveredAt,
                    icon: Icons.outgoing_mail,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now(),
                    onChanged: (value) => setDialogState(() {
                      deliveredAt = value;
                      // Mientras nadie la mueva a mano, la fecha de la
                      // diligencia sigue a la citación.
                      if (!manualHearingDate) {
                        hearingDate =
                            DisciplinaryService.fechaDiligenciaSugerida(value);
                      }
                    }),
                  ),
                  const SizedBox(height: 14),
                  _DateField(
                    label: 'Fecha de la diligencia',
                    value: hearingDate,
                    icon: Icons.event_busy_rounded,
                    firstDate: deliveredAt,
                    lastDate: deliveredAt.add(const Duration(days: 365)),
                    helper: manualHearingDate
                        ? 'Fecha ajustada manualmente.'
                        : '$kDiasHabilesDescargos días hábiles desde la '
                              'entrega.',
                    onChanged: (value) => setDialogState(() {
                      hearingDate = value;
                      manualHearingDate = true;
                    }),
                  ),
                  const SizedBox(height: 14),
                  _DocumentField(
                    label: 'Citación entregada',
                    document: document,
                    onPick: () async {
                      final picked = await _pickDocument();
                      if (picked != null) {
                        setDialogState(() => document = picked);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: saving
                  ? null
                  : () async {
                      final upload = document;
                      if (upload == null) {
                        _message(
                          'Adjunta la citación entregada al colaborador.',
                          error: true,
                        );
                        return;
                      }
                      setDialogState(() => saving = true);
                      try {
                        await _service.registrarCitacion(
                          record: record,
                          deliveredAt: deliveredAt,
                          hearingDate: hearingDate,
                          document: upload,
                          performedBy: widget.userId,
                        );
                        if (!dialogContext.mounted) return;
                        Navigator.pop(dialogContext);
                        _message(
                          'Citación registrada. Alerta programada para el '
                          '${_formatDate(hearingDate)}.',
                        );
                      } catch (error) {
                        setDialogState(() => saving = false);
                        _message('No fue posible guardar: $error', error: true);
                      }
                    },
              icon: _saveIcon(saving),
              label: const Text('Registrar citación'),
            ),
          ],
        ),
      ),
    );
  }

  /// Paso 3. Llegado el día de la diligencia se monta el acta y se fija cuándo
  /// debe salir el resultado.
  Future<void> _showHearingDialog(DisciplinaryRecord record) async {
    var heldAt = record.hearingDate ?? DateTime.now();
    if (heldAt.isAfter(DateTime.now())) heldAt = DateTime.now();
    var resultDeadline = DisciplinaryService.fechaDiligenciaSugerida(heldAt);
    var manualDeadline = false;
    DisciplinaryUpload? document;
    var saving = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          titlePadding: EdgeInsets.zero,
          contentPadding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
          title: _DialogTitle(
            icon: Icons.record_voice_over_outlined,
            title: 'Diligencia de descargos',
            subtitle: '${record.personName} · CC ${record.cedula}',
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _DialogHint(
                    'Adjunta el acta de la diligencia y fija la fecha para dar '
                    'respuesta. Esa fecha genera la alerta del resultado.',
                  ),
                  const SizedBox(height: 16),
                  _DateField(
                    label: 'Fecha de la diligencia',
                    value: heldAt,
                    icon: Icons.event_note_rounded,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now(),
                    onChanged: (value) => setDialogState(() {
                      heldAt = value;
                      if (!manualDeadline) {
                        resultDeadline =
                            DisciplinaryService.fechaDiligenciaSugerida(value);
                      }
                    }),
                  ),
                  const SizedBox(height: 14),
                  _DateField(
                    label: 'Fecha límite del resultado',
                    value: resultDeadline,
                    icon: Icons.schedule_rounded,
                    firstDate: heldAt,
                    lastDate: heldAt.add(const Duration(days: 365)),
                    helper: manualDeadline
                        ? 'Fecha ajustada manualmente.'
                        : 'Propuesta: $kDiasHabilesDescargos días hábiles '
                              'después de la diligencia.',
                    onChanged: (value) => setDialogState(() {
                      resultDeadline = value;
                      manualDeadline = true;
                    }),
                  ),
                  const SizedBox(height: 14),
                  _DocumentField(
                    label: 'Acta de la diligencia',
                    document: document,
                    onPick: () async {
                      final picked = await _pickDocument();
                      if (picked != null) {
                        setDialogState(() => document = picked);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: saving
                  ? null
                  : () async {
                      final upload = document;
                      if (upload == null) {
                        _message(
                          'Adjunta el acta de la diligencia de descargos.',
                          error: true,
                        );
                        return;
                      }
                      setDialogState(() => saving = true);
                      try {
                        await _service.registrarDiligencia(
                          record: record,
                          heldAt: heldAt,
                          resultDeadline: resultDeadline,
                          document: upload,
                          performedBy: widget.userId,
                        );
                        if (!dialogContext.mounted) return;
                        Navigator.pop(dialogContext);
                        _message(
                          'Diligencia registrada. El resultado vence el '
                          '${_formatDate(resultDeadline)}.',
                        );
                      } catch (error) {
                        setDialogState(() => saving = false);
                        _message('No fue posible guardar: $error', error: true);
                      }
                    },
              icon: _saveIcon(saving),
              label: const Text('Registrar diligencia'),
            ),
          ],
        ),
      ),
    );
  }

  /// Paso 4. El resultado cierra el proceso, y solo con una de las cuatro
  /// sanciones.
  Future<void> _showResultDialog(DisciplinaryRecord record) async {
    var resultAt = DateTime.now();
    String? sanction;
    String? severity;
    DisciplinaryUpload? document;
    var saving = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          titlePadding: EdgeInsets.zero,
          contentPadding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
          title: _DialogTitle(
            icon: Icons.gavel_rounded,
            title: 'Resultado de la diligencia',
            subtitle: '${record.personName} · CC ${record.cedula}',
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _DialogHint(
                    'Con el resultado se cierra el proceso. Aquí sí se '
                    'califica la gravedad: hasta ahora nadie sabía qué tan '
                    'grave era el caso.',
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: sanction,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Resultado',
                      hintText: 'Selecciona el resultado',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final value in DisciplinarySanction.values)
                        DropdownMenuItem(
                          value: value,
                          child: Text(DisciplinarySanction.label(value)),
                        ),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => sanction = value),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: severity,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Gravedad',
                      hintText: 'Cómo se califica la diligencia',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final value in DisciplinarySeverity.values)
                        DropdownMenuItem(
                          value: value,
                          child: Text(DisciplinarySeverity.label(value)),
                        ),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => severity = value),
                  ),
                  const SizedBox(height: 14),
                  _DateField(
                    label: 'Fecha del resultado',
                    value: resultAt,
                    icon: Icons.event_available_rounded,
                    firstDate: record.hearingHeldAt ?? DateTime(2000),
                    lastDate: DateTime.now(),
                    onChanged: (value) => setDialogState(() => resultAt = value),
                  ),
                  const SizedBox(height: 14),
                  _DocumentField(
                    label: 'Documento del resultado',
                    document: document,
                    onPick: () async {
                      final picked = await _pickDocument();
                      if (picked != null) {
                        setDialogState(() => document = picked);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: saving
                  ? null
                  : () async {
                      final upload = document;
                      final chosen = sanction;
                      final grade = severity;
                      if (chosen == null) {
                        _message(
                          'Elige el resultado con el que se cierra el proceso.',
                          error: true,
                        );
                        return;
                      }
                      if (grade == null) {
                        _message(
                          'Califica la gravedad del caso.',
                          error: true,
                        );
                        return;
                      }
                      if (upload == null) {
                        _message(
                          'Adjunta el documento del resultado.',
                          error: true,
                        );
                        return;
                      }
                      setDialogState(() => saving = true);
                      try {
                        await _service.cerrarConResultado(
                          record: record,
                          sanction: chosen,
                          severity: grade,
                          resultAt: resultAt,
                          document: upload,
                          performedBy: widget.userId,
                        );
                        if (!dialogContext.mounted) return;
                        Navigator.pop(dialogContext);
                        _message(
                          'Proceso cerrado: '
                          '${DisciplinarySanction.label(chosen)}.',
                        );
                      } catch (error) {
                        setDialogState(() => saving = false);
                        _message('No fue posible cerrar: $error', error: true);
                      }
                    },
              icon: _saveIcon(saving),
              label: const Text('Cerrar proceso'),
            ),
          ],
        ),
      ),
    );
  }

  /// Salida temprana. Al evaluar la solicitud, Talento Humano puede concluir
  /// que el caso no da para proceso disciplinario y cerrarlo sin citar a
  /// nadie. No se pide sanción ni gravedad: no hubo diligencia que calificar.
  Future<void> _showDiscardDialog(DisciplinaryRecord record) async {
    DisciplinaryUpload? document;
    var saving = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          titlePadding: EdgeInsets.zero,
          contentPadding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
          title: _DialogTitle(
            icon: Icons.block_rounded,
            title: 'La solicitud no corresponde',
            subtitle: '${record.personName} · CC ${record.cedula}',
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _DialogHint(
                    'El caso se cierra sin citación a descargos. Queda en la '
                    'carpeta con quién y cuándo lo evaluó, pero sin sanción '
                    'ni gravedad: no hubo diligencia que calificar.',
                  ),
                  const SizedBox(height: 16),
                  _DocumentField(
                    label: 'Soporte de la evaluación (opcional)',
                    document: document,
                    optional: true,
                    onPick: () async {
                      final picked = await _pickDocument();
                      if (picked != null) {
                        setDialogState(() => document = picked);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: saving
                  ? null
                  : () async {
                      setDialogState(() => saving = true);
                      try {
                        await _service.descartarSolicitud(
                          record: record,
                          document: document,
                          performedBy: widget.userId,
                        );
                        if (!dialogContext.mounted) return;
                        Navigator.pop(dialogContext);
                        _message('Solicitud cerrada: no corresponde.');
                      } catch (error) {
                        setDialogState(() => saving = false);
                        _message('No fue posible cerrar: $error', error: true);
                      }
                    },
              icon: _saveIcon(saving),
              label: const Text('Cerrar sin proceso'),
              style: FilledButton.styleFrom(backgroundColor: _muted),
            ),
          ],
        ),
      ),
    );
  }

  /// Un solo botón por tarjeta: el proceso solo avanza al paso que sigue.
  Future<void> _advanceStage(DisciplinaryRecord record) async {
    switch (record.stage) {
      case DisciplinaryStage.solicitud:
        return _showSummonDialog(record);
      case DisciplinaryStage.citacion:
        return _showHearingDialog(record);
      case DisciplinaryStage.diligencia:
        return _showResultDialog(record);
    }
  }

  Future<void> _replaceDocument(
    DisciplinaryRecord record,
    String stage,
  ) async {
    final picked = await _pickDocument();
    if (picked == null) return;
    try {
      _message('Subiendo ${picked.fileName}…');
      await _service.reemplazarDocumento(
        record: record,
        stage: stage,
        document: picked,
        performedBy: widget.userId,
      );
      _message('Documento reemplazado.');
    } catch (error) {
      _message('No fue posible reemplazar el documento: $error', error: true);
    }
  }

  Future<DisciplinaryUpload?> _pickDocument() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg', 'docx', 'xlsx'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return null;
      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) {
        throw StateError('El navegador no entregó el contenido del archivo.');
      }
      return DisciplinaryUpload(bytes: bytes, fileName: file.name);
    } catch (error) {
      _message('No fue posible leer el archivo: $error', error: true);
      return null;
    }
  }

  Future<void> _showDetails(DisciplinaryRecord record) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        titlePadding: EdgeInsets.zero,
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
        title: _DialogTitle(
          icon: Icons.folder_shared_outlined,
          title: 'Proceso disciplinario',
          subtitle: '${record.personName} · ${record.statusLabel}',
        ),
        content: SizedBox(
          width: 680,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _StageTrack(record: record),
                const SizedBox(height: 18),
                _StageBlock(
                  step: 1,
                  title: 'Solicitud de apertura',
                  done: true,
                  rows: [('Fecha de recibido', _formatDate(record.receivedAt))],
                  document: record.requestDocument,
                  onReplace: () => _replaceDocument(
                    record,
                    DisciplinaryStage.solicitud,
                  ),
                ),
                _StageBlock(
                  step: 2,
                  title: 'Citación a descargos',
                  done: record.summonDocument != null,
                  skipped: record.closedWithoutProcess,
                  rows: [
                    if (record.summonDeliveredAt != null)
                      (
                        'Entrega de la citación',
                        _formatDate(record.summonDeliveredAt!),
                      ),
                    if (record.hearingDate != null)
                      ('Fecha de la diligencia', _formatDate(record.hearingDate!)),
                  ],
                  document: record.summonDocument,
                  onReplace: record.summonDocument == null
                      ? null
                      : () => _replaceDocument(
                          record,
                          DisciplinaryStage.citacion,
                        ),
                ),
                _StageBlock(
                  step: 3,
                  title: 'Diligencia de descargos',
                  done: record.hearingDocument != null,
                  skipped: record.closedWithoutProcess,
                  rows: [
                    if (record.hearingHeldAt != null)
                      ('Diligencia realizada', _formatDate(record.hearingHeldAt!)),
                    if (record.resultDeadline != null)
                      (
                        'Límite del resultado',
                        _formatDate(record.resultDeadline!),
                      ),
                  ],
                  document: record.hearingDocument,
                  onReplace: record.hearingDocument == null
                      ? null
                      : () => _replaceDocument(
                          record,
                          DisciplinaryStage.diligencia,
                        ),
                ),
                _StageBlock(
                  step: 4,
                  title: record.closedWithoutProcess
                      ? 'Cierre sin proceso'
                      : 'Resultado y cierre',
                  done: record.isClosed,
                  rows: [
                    if (record.sanction.isNotEmpty)
                      (
                        record.closedWithoutProcess ? 'Decisión' : 'Resultado',
                        DisciplinarySanction.label(record.sanction),
                      ),
                    if (record.severity.isNotEmpty)
                      ('Gravedad', DisciplinarySeverity.label(record.severity)),
                    if (record.resultAt != null)
                      (
                        record.closedWithoutProcess
                            ? 'Fecha del cierre'
                            : 'Fecha del resultado',
                        _formatDate(record.resultAt!),
                      ),
                  ],
                  document: record.resultDocument,
                  onReplace: record.resultDocument == null
                      ? null
                      : () => _replaceDocument(record, 'resultado'),
                ),
                const SizedBox(height: 8),
                _RecordTimeline(service: _service, record: record),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Widget _saveIcon(bool saving) => saving
      ? const SizedBox.square(
          dimension: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        )
      : const Icon(Icons.save_outlined);

  void _message(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? _danger : _navy,
      ),
    );
  }
}

class _PersonFolderTile extends StatelessWidget {
  final DisciplinaryPerson person;
  final int count;
  final int overdue;
  final bool selected;
  final VoidCallback onTap;

  const _PersonFolderTile({
    required this.person,
    required this.count,
    required this.overdue,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFFFFF7ED) : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            border: Border.all(color: selected ? _primary : _border),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              UserAvatar(
                userId: person.cedula,
                nameHint: person.name,
                fotoUrlHint: person.photoUrl,
                radius: 21,
                backgroundColor: _navy,
                foregroundColor: Colors.white,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      person.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: _font,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: _ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      person.role.isEmpty
                          ? 'CC ${person.cedula}'
                          : '${person.role} · CC ${person.cedula}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: _font,
                        fontSize: 10,
                        color: _muted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                children: [
                  _CountBadge(count: count),
                  const SizedBox(height: 4),
                  Icon(
                    overdue > 0
                        ? Icons.notification_important_rounded
                        : person.isActive
                        ? Icons.check_circle_rounded
                        : Icons.archive_rounded,
                    size: 15,
                    color: overdue > 0
                        ? _danger
                        : person.isActive
                        ? _success
                        : const Color(0xFFB45309),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PersonFolderHeader extends StatelessWidget {
  final DisciplinaryPerson person;
  final DisciplinaryMetrics metrics;
  final VoidCallback onCreate;

  const _PersonFolderHeader({
    required this.person,
    required this.metrics,
    required this.onCreate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_navy, Color(0xFF275C7F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 620;
          final identity = Row(
            children: [
              UserAvatar(
                userId: person.cedula,
                nameHint: person.name,
                fotoUrlHint: person.photoUrl,
                radius: 31,
                backgroundColor: Colors.white,
                foregroundColor: _navy,
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            person.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontFamily: _font,
                              fontWeight: FontWeight.w900,
                              fontSize: 20,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _StatusPill(active: person.isActive),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      [
                        'CC ${person.cedula}',
                        if (person.role.isNotEmpty) person.role,
                        if (person.area.isNotEmpty) person.area,
                      ].join(' · '),
                      style: const TextStyle(
                        color: Color(0xFFDCEAF3),
                        fontFamily: _font,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${metrics.total} proceso(s) conservado(s) en su carpeta',
                      style: const TextStyle(
                        color: Color(0xFFB9D4E5),
                        fontFamily: _font,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
          final button = FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Nuevo proceso'),
            style: FilledButton.styleFrom(
              backgroundColor: _primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 14),
            ),
          );
          return narrow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [identity, const SizedBox(height: 16), button],
                )
              : Row(
                  children: [
                    Expanded(child: identity),
                    const SizedBox(width: 18),
                    button,
                  ],
                );
        },
      ),
    );
  }
}

class _RecordCard extends StatelessWidget {
  final DisciplinaryRecord record;
  final VoidCallback onDetails;
  final VoidCallback? onAdvance;

  /// Solo existe mientras el proceso está en la solicitud: una vez citado el
  /// colaborador, ya no se puede decir que el caso no correspondía.
  final VoidCallback? onDiscard;

  const _RecordCard({
    required this.record,
    required this.onDetails,
    required this.onAdvance,
    required this.onDiscard,
  });

  @override
  Widget build(BuildContext context) {
    final color = _stageColor(record);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onDetails,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(
              color: record.isOverdue ? _danger : _border,
              width: record.isOverdue ? 1.4 : 1,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(_stageIcon(record.stage), color: color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Proceso disciplinario',
                          style: const TextStyle(
                            fontFamily: _font,
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                            color: _ink,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Solicitud recibida el '
                          '${_formatDate(record.receivedAt)}',
                          style: const TextStyle(
                            fontFamily: _font,
                            fontSize: 11,
                            color: _muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _StageBadge(record: record),
                ],
              ),
              const SizedBox(height: 12),
              _StageTrack(record: record),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (record.isClosed) ...[
                    _SmallTag(
                      label: DisciplinarySanction.label(record.sanction),
                      color: record.closedWithoutProcess ? _muted : _success,
                    ),
                    if (record.severity.isNotEmpty)
                      _SmallTag(
                        label:
                            'Gravedad '
                            '${DisciplinarySeverity.label(record.severity)}',
                        color: _severityColor(record.severity),
                      ),
                  ] else
                    _SmallTag(
                      label: DisciplinaryStage.pendingLabel(record.stage),
                      color: _warning,
                    ),
                  if (record.currentDeadline != null)
                    _DeadlineTag(record: record),
                  _SmallTag(
                    label: '${record.attachments.length} documento(s)',
                    color: _muted,
                  ),
                  const SizedBox(width: 4),
                  TextButton.icon(
                    onPressed: onDetails,
                    icon: const Icon(Icons.visibility_outlined, size: 17),
                    label: const Text('Detalle'),
                  ),
                  if (onDiscard != null)
                    TextButton.icon(
                      onPressed: onDiscard,
                      icon: const Icon(Icons.block_rounded, size: 17),
                      label: const Text('No corresponde'),
                      style: TextButton.styleFrom(foregroundColor: _muted),
                    ),
                  if (onAdvance != null)
                    FilledButton.icon(
                      onPressed: onAdvance,
                      icon: const Icon(Icons.arrow_forward_rounded, size: 17),
                      label: Text(
                        DisciplinaryStage.nextActionLabel(record.stage),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: _primary,
                        foregroundColor: Colors.white,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Los cuatro pasos del proceso, con el que va en curso resaltado. Es la única
/// forma de que en la carpeta se vea de un vistazo qué falta.
class _StageTrack extends StatelessWidget {
  final DisciplinaryRecord record;
  const _StageTrack({required this.record});

  static const _steps = <(String, String)>[
    (DisciplinaryStage.solicitud, 'Solicitud'),
    (DisciplinaryStage.citacion, 'Citación'),
    (DisciplinaryStage.diligencia, 'Diligencia'),
    (DisciplinaryStage.cerrado, 'Resultado'),
  ];

  @override
  Widget build(BuildContext context) {
    // Un caso descartado se cerró en la solicitud: pintarle los cuatro pasos
    // completos diría que hubo citación y diligencia, y no las hubo.
    if (record.closedWithoutProcess) {
      return Row(
        children: [
          const _TrackStep(label: 'Solicitud', done: true, current: false),
          Expanded(
            child: Container(
              height: 2,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              color: _border,
            ),
          ),
          const _TrackStep(
            label: 'No corresponde',
            done: true,
            current: true,
            color: _muted,
          ),
        ],
      );
    }
    final current = _steps.indexWhere((step) => step.$1 == record.stage);
    return Row(
      children: [
        for (var index = 0; index < _steps.length; index++) ...[
          if (index > 0)
            Expanded(
              child: Container(
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                color: index <= current ? _primary : _border,
              ),
            ),
          _TrackStep(
            label: _steps[index].$2,
            done: index <= current,
            current: index == current,
          ),
        ],
      ],
    );
  }
}

/// Un paso del recorrido. Vive aparte porque el descarte temprano lo reusa con
/// otro texto y otro color.
class _TrackStep extends StatelessWidget {
  final String label;
  final bool done;
  final bool current;
  final Color color;

  const _TrackStep({
    required this.label,
    required this.done,
    required this.current,
    this.color = _primary,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: done ? color.withValues(alpha: 0.12) : _surface,
          border: Border.all(
            color: current ? color : _border,
            width: current ? 1.4 : 1,
          ),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              done
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 13,
              color: done ? color : _muted,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontFamily: _font,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: done ? color : _muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bloque de una etapa dentro del detalle: fechas, documento y reemplazo.
class _StageBlock extends StatelessWidget {
  final int step;
  final String title;
  final bool done;
  final List<(String, String)> rows;
  final DisciplinaryAttachment? document;
  final VoidCallback? onReplace;

  /// La etapa nunca va a ocurrir porque el caso se cerró antes. No es lo
  /// mismo que "pendiente": nadie la está esperando.
  final bool skipped;

  const _StageBlock({
    required this.step,
    required this.title,
    required this.done,
    required this.rows,
    required this.document,
    required this.onReplace,
    this.skipped = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: done ? Colors.white : _surface,
        border: Border.all(color: done ? _border : const Color(0xFFEDF2F7)),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: done ? _primary : _border,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$step',
                  style: TextStyle(
                    fontFamily: _font,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: done ? Colors.white : _muted,
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontFamily: _font,
                    fontWeight: FontWeight.w800,
                    color: done ? _ink : _muted,
                  ),
                ),
              ),
              if (!done)
                Text(
                  skipped ? 'No aplica' : 'Pendiente',
                  style: const TextStyle(fontSize: 10, color: _muted),
                ),
            ],
          ),
          if (done) ...[
            const SizedBox(height: 10),
            for (final row in rows) _DetailRow(row.$1, row.$2),
            if (document != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFFFF7ED),
                  child: Icon(Icons.attach_file_rounded, color: _primary),
                ),
                title: Text(document!.name),
                subtitle: Text(
                  document!.uploadedAt == null
                      ? 'Documento adjunto'
                      : 'Subido ${_formatDate(document!.uploadedAt!)}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (onReplace != null)
                      IconButton(
                        tooltip: 'Reemplazar documento',
                        onPressed: onReplace,
                        icon: const Icon(Icons.upload_file_rounded),
                      ),
                    IconButton(
                      tooltip: 'Abrir documento',
                      onPressed: document!.url.isEmpty
                          ? null
                          : () => launchUrl(
                              Uri.parse(document!.url),
                              mode: LaunchMode.externalApplication,
                            ),
                      icon: const Icon(Icons.open_in_new_rounded),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _RecordTimeline extends StatelessWidget {
  final DisciplinaryService service;
  final DisciplinaryRecord record;

  const _RecordTimeline({required this.service, required this.record});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: service.watchRecordHistory(record.id),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const LinearProgressIndicator(minHeight: 2);
        }
        final events = [...snapshot.data!.docs]
          ..sort((a, b) {
            final aDate = a.data()['fecha'] as Timestamp?;
            final bDate = b.data()['fecha'] as Timestamp?;
            return (aDate?.millisecondsSinceEpoch ?? 0).compareTo(
              bDate?.millisecondsSinceEpoch ?? 0,
            );
          });
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Trazabilidad interna',
              style: TextStyle(fontWeight: FontWeight.w800, color: _ink),
            ),
            const SizedBox(height: 8),
            if (events.isEmpty)
              const Text('Sin movimientos adicionales.')
            else
              for (final event in events)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(
                    radius: 14,
                    backgroundColor: Color(0xFFEAF4FB),
                    child: Icon(Icons.history_rounded, size: 15, color: _navy),
                  ),
                  title: Text(
                    _capitalize((event.data()['evento'] ?? '').toString()),
                  ),
                  subtitle: Text(
                    '${(event.data()['detalle'] ?? '').toString()}\n'
                    '${_formatTimestamp(event.data()['fecha'])}',
                  ),
                ),
          ],
        );
      },
    );
  }
}

class _MetricData {
  final String label;
  final int value;
  final IconData icon;
  final Color color;
  const _MetricData(this.label, this.value, this.icon, this.color);
}

class _MetricCard extends StatelessWidget {
  final _MetricData data;
  const _MetricCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          Container(
            width: 37,
            height: 37,
            decoration: BoxDecoration(
              color: data.color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(data.icon, color: data.color, size: 19),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${data.value}',
                  style: TextStyle(
                    fontFamily: _font,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: data.color,
                  ),
                ),
                Text(
                  data.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: _font,
                    color: _muted,
                    fontSize: 10,
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

class _EmptyFolderState extends StatelessWidget {
  const _EmptyFolderState();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: _surface,
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.folder_shared_outlined, size: 62, color: _primary),
              SizedBox(height: 15),
              Text(
                'Selecciona una carpeta',
                style: TextStyle(
                  fontFamily: _font,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: _ink,
                ),
              ),
              SizedBox(height: 7),
              Text(
                'Aquí verás la solicitud, la citación, la diligencia y el '
                'resultado de cada proceso del colaborador.',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: _font, color: _muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoRecords extends StatelessWidget {
  final VoidCallback onCreate;
  const _NoRecords({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          const Icon(Icons.verified_user_outlined, size: 42, color: _primary),
          const SizedBox(height: 10),
          const Text(
            'Sin procesos registrados',
            style: TextStyle(
              fontFamily: _font,
              fontWeight: FontWeight.w900,
              color: _ink,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'La carpeta se conservará aunque el colaborador quede inactivo.',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: _font, color: _muted, fontSize: 12),
          ),
          const SizedBox(height: 13),
          OutlinedButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Registrar apertura'),
          ),
        ],
      ),
    );
  }
}

class _DialogTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _DialogTitle({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 18, 16, 16),
      decoration: const BoxDecoration(
        color: _navy,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: _font,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFDCEAF3),
                    fontFamily: _font,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            tooltip: 'Cerrar',
            icon: const Icon(Icons.close_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

/// Explica en una línea qué se está radicando. Reemplaza los campos de texto
/// que antes obligaban a Talento Humano a redactar la falta.
class _DialogHint extends StatelessWidget {
  final String text;
  const _DialogHint(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, size: 18, color: Color(0xFF1D4ED8)),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontFamily: _font,
                fontSize: 11.5,
                height: 1.4,
                color: Color(0xFF1D4ED8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Selector de fecha con aspecto de campo, no de botón suelto: en el flujo
/// anterior las fechas parecían opcionales y se dejaban vacías.
class _DateField extends StatelessWidget {
  final String label;
  final DateTime value;
  final IconData icon;
  final DateTime firstDate;
  final DateTime lastDate;
  final String? helper;
  final ValueChanged<DateTime> onChanged;

  const _DateField({
    required this.label,
    required this.value,
    required this.icon,
    required this.firstDate,
    required this.lastDate,
    required this.onChanged,
    this.helper,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () async {
        final initial = value.isBefore(firstDate)
            ? firstDate
            : value.isAfter(lastDate)
            ? lastDate
            : value;
        final picked = await showDatePicker(
          context: context,
          initialDate: initial,
          firstDate: firstDate,
          lastDate: lastDate,
        );
        if (picked != null) onChanged(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          helperMaxLines: 2,
          prefixIcon: Icon(icon, size: 19),
          border: const OutlineInputBorder(),
        ),
        child: Text(
          _formatDate(value),
          style: const TextStyle(fontFamily: _font, fontSize: 14),
        ),
      ),
    );
  }
}

/// Adjunto obligatorio de la etapa. Sin documento no se avanza: es el requisito
/// que pidió Talento Humano para cada paso.
class _DocumentField extends StatelessWidget {
  final String label;
  final DisciplinaryUpload? document;
  final Future<void> Function() onPick;
  final bool optional;

  const _DocumentField({
    required this.label,
    required this.document,
    required this.onPick,
    this.optional = false,
  });

  @override
  Widget build(BuildContext context) {
    final chosen = document;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: chosen != null
            ? const Color(0xFFECFDF5)
            : optional
            ? _surface
            : const Color(0xFFFFFBEB),
        border: Border.all(
          color: chosen != null
              ? const Color(0xFFA7F3D0)
              : optional
              ? _border
              : const Color(0xFFFDE68A),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            chosen == null
                ? Icons.upload_file_rounded
                : Icons.check_circle_rounded,
            color: chosen != null
                ? _success
                : optional
                ? _muted
                : _warning,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontFamily: _font,
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  chosen != null
                      ? chosen.fileName
                      : optional
                      ? 'Opcional · PDF, imagen, Word o Excel (máx. 10 MB)'
                      : 'Obligatorio · PDF, imagen, Word o Excel (máx. 10 MB)',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: _font,
                    fontSize: 11,
                    color: chosen != null
                        ? _success
                        : optional
                        ? _muted
                        : _warning,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: onPick,
            child: Text(chosen == null ? 'Adjuntar' : 'Cambiar'),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 155,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: _muted,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _FilterButton extends StatelessWidget {
  final String label;
  const _FilterButton({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.filter_list_rounded, size: 17, color: _muted),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final bool active;
  const _StatusPill({required this.active});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: active ? const Color(0xFFDCFCE7) : const Color(0xFFFFEDD5),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        active ? 'ACTIVO' : 'INACTIVO',
        style: TextStyle(
          fontFamily: _font,
          fontSize: 9,
          fontWeight: FontWeight.w900,
          color: active ? _success : const Color(0xFFB45309),
        ),
      ),
    );
  }
}

class _StageBadge extends StatelessWidget {
  final DisciplinaryRecord record;
  const _StageBadge({required this.record});

  @override
  Widget build(BuildContext context) {
    final color = record.closedWithoutProcess
        ? _muted
        : record.isClosed
        ? _success
        : _warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        record.statusLabel.toUpperCase(),
        style: TextStyle(
          fontFamily: _font,
          fontSize: 9,
          fontWeight: FontWeight.w900,
          color: color,
        ),
      ),
    );
  }
}

/// Traduce el plazo de la etapa en curso al lenguaje de la operación: la
/// alerta llega el mismo día, pero la carpeta debe mostrar el vencido.
class _DeadlineTag extends StatelessWidget {
  final DisciplinaryRecord record;
  const _DeadlineTag({required this.record});

  @override
  Widget build(BuildContext context) {
    final days = record.daysToDeadline;
    final deadline = record.currentDeadline;
    if (days == null || deadline == null) return const SizedBox.shrink();
    final label = days < 0
        ? 'Vencido hace ${-days} día(s) · ${_formatDate(deadline)}'
        : days == 0
        ? 'Vence hoy · ${_formatDate(deadline)}'
        : 'Faltan $days día(s) · ${_formatDate(deadline)}';
    final color = days < 0
        ? _danger
        : days == 0
        ? _warning
        : _muted;
    return _SmallTag(label: label, color: color);
  }
}

class _SmallTag extends StatelessWidget {
  final String label;
  final Color color;
  const _SmallTag({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  final int count;
  const _CountBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 24),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: count == 0 ? const Color(0xFFF1F5F9) : const Color(0xFFFFEDD5),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          color: count == 0 ? _muted : _primary,
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final String detail;
  const _ErrorState({required this.message, required this.detail});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: Colors.red,
            ),
            const SizedBox(height: 12),
            Text(message, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _muted, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatDate(DateTime date) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(date.day)}/${two(date.month)}/${date.year}';
}

String _formatTimestamp(dynamic value) {
  if (value is! Timestamp) return 'Fecha pendiente de sincronización';
  final date = value.toDate();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(date.day)}/${two(date.month)}/${date.year} '
      '${two(date.hour)}:${two(date.minute)}';
}

String _capitalize(String value) {
  final text = value.trim().replaceAll('_', ' ');
  if (text.isEmpty) return '—';
  return '${text[0].toUpperCase()}${text.substring(1)}';
}

IconData _stageIcon(String stage) {
  switch (stage) {
    case DisciplinaryStage.citacion:
      return Icons.mark_email_read_outlined;
    case DisciplinaryStage.diligencia:
      return Icons.record_voice_over_outlined;
    case DisciplinaryStage.cerrado:
      return Icons.gavel_rounded;
    default:
      return Icons.markunread_mailbox_outlined;
  }
}

/// La gravedad solo existe en procesos cerrados, así que este color nunca
/// pinta un caso en trámite: es la calificación final, no una alarma.
Color _severityColor(String severity) {
  switch (severity.trim()) {
    case DisciplinarySeverity.gravisima:
      return _danger;
    case DisciplinarySeverity.grave:
      return _warning;
    default:
      return const Color(0xFF2563EB);
  }
}

Color _stageColor(DisciplinaryRecord record) {
  if (record.isClosed) return _success;
  if (record.isOverdue) return _danger;
  if (record.isDueToday) return _warning;
  return _navy;
}
