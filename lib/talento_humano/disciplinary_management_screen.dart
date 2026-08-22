import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/internal_module_layout.dart';
import '../widgets/user_avatar.dart';
import 'disciplinary_service.dart';

const _primary = Color(0xFF9A5B32);
const _navy = Color(0xFF173B5E);
const _ink = Color(0xFF17212B);
const _muted = Color(0xFF64748B);
const _border = Color(0xFFE2E8F0);
const _surface = Color(0xFFF8FAFC);
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
  String _peopleFilter = 'todos';
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
      subtitle: 'Carpeta disciplinaria, descargos, seguimiento y cierre',
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
                : ListView.separated(
                    padding: EdgeInsets.all(mobile ? 12 : 10),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 7),
                    itemBuilder: (context, index) {
                      final person = filtered[index];
                      final selected = _selected?.cedula == person.cedula;
                      return _PersonFolderTile(
                        person: person,
                        count: counts[person.cedula] ?? 0,
                        selected: selected,
                        onTap: () => setState(() => _selected = person),
                      );
                    },
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
      if (_recordFilter == 'activos') return record.isOpen;
      if (_recordFilter == 'cerrados') {
        return record.status == DisciplinaryStatus.closed;
      }
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
                onCreate: () => _showCreateDialog(person),
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
                      PopupMenuItem(
                        value: 'activos',
                        child: Text('En proceso'),
                      ),
                      PopupMenuItem(value: 'cerrados', child: Text('Cerrados')),
                    ],
                    child: _FilterButton(label: _recordFilterLabel),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (records.isEmpty)
                _NoRecords(onCreate: () => _showCreateDialog(person))
              else
                for (final record in records) ...[
                  _RecordCard(
                    record: record,
                    onDetails: () => _showDetails(record),
                    onEvidence: () => _attachEvidence(record),
                    onResponse: record.status == DisciplinaryStatus.closed
                        ? null
                        : () => _showResponseDialog(record),
                    onClose: record.status == DisciplinaryStatus.closed
                        ? () => _showReopenDialog(record)
                        : () => _showCloseDialog(record),
                  ),
                  const SizedBox(height: 10),
                ],
            ],
          ),
        ),
      ),
    );
  }

  String get _recordFilterLabel {
    switch (_recordFilter) {
      case 'activos':
        return 'En proceso';
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
        'Pendientes',
        metrics.pendingResponse,
        Icons.mark_unread_chat_alt_outlined,
        const Color(0xFFD97706),
      ),
      _MetricData(
        'Seguimiento',
        metrics.followUp,
        Icons.track_changes_rounded,
        const Color(0xFF7C3AED),
      ),
      _MetricData(
        'Cerrados',
        metrics.closed,
        Icons.task_alt_rounded,
        const Color(0xFF15803D),
      ),
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

  Future<void> _showCreateDialog(DisciplinaryPerson person) async {
    final subject = TextEditingController();
    final description = TextEditingController();
    final reference = TextEditingController();
    final expected = TextEditingController();
    var type = 'escrito';
    var severity = 'leve';
    var incidentDate = DateTime.now();
    DateTime? responseDeadline;
    var saving = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          titlePadding: EdgeInsets.zero,
          contentPadding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
          title: _DialogTitle(
            icon: Icons.record_voice_over_rounded,
            title: 'Nuevo proceso disciplinario',
            subtitle: '${person.name} · CC ${person.cedula}',
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: type,
                          decoration: const InputDecoration(labelText: 'Tipo'),
                          items: const [
                            DropdownMenuItem(
                              value: 'verbal',
                              child: Text('Verbal'),
                            ),
                            DropdownMenuItem(
                              value: 'escrito',
                              child: Text('Escrito'),
                            ),
                            DropdownMenuItem(
                              value: 'descargos',
                              child: Text('Citación a descargos'),
                            ),
                            DropdownMenuItem(
                              value: 'compromiso',
                              child: Text('Compromiso de mejora'),
                            ),
                            DropdownMenuItem(
                              value: 'otro',
                              child: Text('Otro'),
                            ),
                          ],
                          onChanged: (value) => type = value ?? type,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: severity,
                          decoration: const InputDecoration(
                            labelText: 'Gravedad',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'leve',
                              child: Text('Leve'),
                            ),
                            DropdownMenuItem(
                              value: 'media',
                              child: Text('Media'),
                            ),
                            DropdownMenuItem(
                              value: 'alta',
                              child: Text('Alta'),
                            ),
                          ],
                          onChanged: (value) => severity = value ?? severity,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: subject,
                    decoration: const InputDecoration(
                      labelText: 'Asunto',
                      hintText: 'Motivo principal del proceso',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: description,
                    minLines: 4,
                    maxLines: 7,
                    decoration: const InputDecoration(
                      labelText: 'Descripción de los hechos',
                      hintText:
                          'Describe qué ocurrió, cuándo y en qué contexto.',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: reference,
                    decoration: const InputDecoration(
                      labelText: 'Referencia normativa o interna (opcional)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: expected,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Acción o mejora esperada (opcional)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      _DateButton(
                        label: 'Hecho: ${_formatDate(incidentDate)}',
                        icon: Icons.event_note_rounded,
                        onPressed: () async {
                          final value = await showDatePicker(
                            context: context,
                            initialDate: incidentDate,
                            firstDate: DateTime(2000),
                            lastDate: DateTime.now(),
                          );
                          if (value != null) {
                            setDialogState(() => incidentDate = value);
                          }
                        },
                      ),
                      _DateButton(
                        label: responseDeadline == null
                            ? 'Fecha límite de respuesta'
                            : 'Respuesta: ${_formatDate(responseDeadline!)}',
                        icon: Icons.schedule_rounded,
                        onPressed: () async {
                          final value = await showDatePicker(
                            context: context,
                            initialDate:
                                responseDeadline ??
                                DateTime.now().add(const Duration(days: 3)),
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(
                              const Duration(days: 365),
                            ),
                          );
                          if (value != null) {
                            setDialogState(() => responseDeadline = value);
                          }
                        },
                      ),
                    ],
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
                      if (subject.text.trim().isEmpty ||
                          description.text.trim().isEmpty) {
                        _message(
                          'Completa el asunto y la descripción de los hechos.',
                          error: true,
                        );
                        return;
                      }
                      setDialogState(() => saving = true);
                      try {
                        await _service.createRecord(
                          empresaId: widget.empresaId,
                          person: person,
                          type: type,
                          severity: severity,
                          subject: subject.text,
                          description: description.text,
                          incidentDate: incidentDate,
                          responseDeadline: responseDeadline,
                          policyReference: reference.text,
                          expectedAction: expected.text,
                          createdBy: widget.userId,
                        );
                        if (!dialogContext.mounted) return;
                        Navigator.pop(dialogContext);
                        _message(
                          'Proceso registrado en la carpeta del colaborador.',
                        );
                      } catch (error) {
                        setDialogState(() => saving = false);
                        _message('No fue posible guardar: $error', error: true);
                      }
                    },
              icon: saving
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: const Text('Registrar'),
            ),
          ],
        ),
      ),
    );
    subject.dispose();
    description.dispose();
    reference.dispose();
    expected.dispose();
  }

  Future<void> _showResponseDialog(DisciplinaryRecord record) async {
    final controller = TextEditingController(text: record.employeeResponse);
    final value = await _textDialog(
      title: 'Registrar respuesta o descargos',
      subtitle: record.subject,
      label: 'Respuesta del colaborador',
      controller: controller,
      action: 'Guardar respuesta',
    );
    if (value == null) return;
    try {
      await _service.registerResponse(
        record: record,
        response: value,
        performedBy: widget.userId,
      );
      _message('Respuesta registrada. El caso pasó a seguimiento.');
    } catch (error) {
      _message('No fue posible registrar la respuesta: $error', error: true);
    }
  }

  Future<void> _attachEvidence(DisciplinaryRecord record) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg', 'docx', 'xlsx'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) {
        throw StateError('El navegador no entregó el contenido del archivo.');
      }
      _message('Subiendo ${file.name}…');
      await _service.addEvidence(
        record: record,
        bytes: bytes,
        fileName: file.name,
        performedBy: widget.userId,
      );
      _message('Evidencia agregada a la carpeta disciplinaria.');
    } catch (error) {
      _message('No fue posible adjuntar la evidencia: $error', error: true);
    }
  }

  Future<void> _showCloseDialog(DisciplinaryRecord record) async {
    final controller = TextEditingController(text: record.conclusion);
    final value = await _textDialog(
      title: 'Cerrar proceso',
      subtitle: record.subject,
      label: 'Conclusión, decisión y compromisos',
      controller: controller,
      action: 'Cerrar proceso',
    );
    if (value == null) return;
    try {
      await _service.closeRecord(
        record: record,
        conclusion: value,
        performedBy: widget.userId,
      );
      _message('Proceso cerrado y conservado en el historial.');
    } catch (error) {
      _message('No fue posible cerrar el proceso: $error', error: true);
    }
  }

  Future<void> _showReopenDialog(DisciplinaryRecord record) async {
    final controller = TextEditingController();
    final value = await _textDialog(
      title: 'Reabrir seguimiento',
      subtitle: record.subject,
      label: 'Motivo de reapertura',
      controller: controller,
      action: 'Reabrir',
    );
    if (value == null) return;
    try {
      await _service.reopenRecord(
        record: record,
        reason: value,
        performedBy: widget.userId,
      );
      _message('El proceso volvió a seguimiento.');
    } catch (error) {
      _message('No fue posible reabrir el proceso: $error', error: true);
    }
  }

  Future<String?> _textDialog({
    required String title,
    required String subtitle,
    required String label,
    required TextEditingController controller,
    required String action,
  }) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        titlePadding: EdgeInsets.zero,
        title: _DialogTitle(
          icon: Icons.fact_check_outlined,
          title: title,
          subtitle: subtitle,
        ),
        content: SizedBox(
          width: 560,
          child: TextField(
            controller: controller,
            minLines: 5,
            maxLines: 9,
            autofocus: true,
            decoration: InputDecoration(
              labelText: label,
              alignLabelWithHint: true,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isEmpty) return;
              Navigator.pop(context, value);
            },
            child: Text(action),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _showDetails(DisciplinaryRecord record) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        titlePadding: EdgeInsets.zero,
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
        title: _DialogTitle(
          icon: Icons.folder_shared_outlined,
          title: record.subject,
          subtitle:
              '${record.personName} · ${DisciplinaryStatus.label(record.status)}',
        ),
        content: SizedBox(
          width: 680,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DetailRow('Tipo', _typeLabel(record.type)),
                _DetailRow('Gravedad', _capitalize(record.severity)),
                _DetailRow(
                  'Fecha de los hechos',
                  _formatDate(record.incidentDate),
                ),
                if (record.responseDeadline != null)
                  _DetailRow(
                    'Límite de respuesta',
                    _formatDate(record.responseDeadline!),
                  ),
                const Divider(height: 26),
                _DetailBlock('Descripción de los hechos', record.description),
                if (record.policyReference.isNotEmpty)
                  _DetailBlock('Referencia normativa', record.policyReference),
                if (record.expectedAction.isNotEmpty)
                  _DetailBlock('Acción esperada', record.expectedAction),
                if (record.employeeResponse.isNotEmpty)
                  _DetailBlock(
                    'Respuesta o descargos del colaborador',
                    record.employeeResponse,
                    color: const Color(0xFFEFF6FF),
                  ),
                if (record.conclusion.isNotEmpty)
                  _DetailBlock(
                    'Conclusión y decisión',
                    record.conclusion,
                    color: const Color(0xFFECFDF5),
                  ),
                if (record.attachments.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  const Text(
                    'Evidencias y documentos',
                    style: TextStyle(fontWeight: FontWeight.w800, color: _ink),
                  ),
                  const SizedBox(height: 6),
                  for (final attachment in record.attachments)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const CircleAvatar(
                        backgroundColor: Color(0xFFFFF7ED),
                        child: Icon(Icons.attach_file_rounded, color: _primary),
                      ),
                      title: Text(attachment.name),
                      subtitle: Text(
                        attachment.uploadedAt == null
                            ? 'Documento adjunto'
                            : 'Subido ${_formatDate(attachment.uploadedAt!)}',
                      ),
                      trailing: IconButton(
                        tooltip: 'Abrir documento',
                        onPressed: attachment.url.isEmpty
                            ? null
                            : () => launchUrl(
                                Uri.parse(attachment.url),
                                mode: LaunchMode.externalApplication,
                              ),
                        icon: const Icon(Icons.open_in_new_rounded),
                      ),
                    ),
                ],
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

  void _message(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? const Color(0xFFB91C1C) : _navy,
      ),
    );
  }
}

class _PersonFolderTile extends StatelessWidget {
  final DisciplinaryPerson person;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _PersonFolderTile({
    required this.person,
    required this.count,
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
                    person.isActive
                        ? Icons.check_circle_rounded
                        : Icons.archive_rounded,
                    size: 15,
                    color: person.isActive
                        ? const Color(0xFF15803D)
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
  final VoidCallback onEvidence;
  final VoidCallback? onResponse;
  final VoidCallback onClose;

  const _RecordCard({
    required this.record,
    required this.onDetails,
    required this.onEvidence,
    required this.onResponse,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onDetails,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: _border),
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
                      color: _severityColor(
                        record.severity,
                      ).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.record_voice_over_outlined,
                      color: _severityColor(record.severity),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          record.subject,
                          style: const TextStyle(
                            fontFamily: _font,
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                            color: _ink,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_typeLabel(record.type)} · ${_formatDate(record.incidentDate)}',
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
                  _RecordStatusBadge(status: record.status),
                ],
              ),
              const SizedBox(height: 11),
              Text(
                record.description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: _font,
                  fontSize: 12,
                  height: 1.4,
                  color: Color(0xFF475569),
                ),
              ),
              if (record.employeeResponse.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Text(
                    'Respuesta: ${record.employeeResponse}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: _font,
                      fontSize: 11,
                      color: Color(0xFF1D4ED8),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _SmallTag(
                    label: 'Gravedad ${_capitalize(record.severity)}',
                    color: _severityColor(record.severity),
                  ),
                  if (record.responseDeadline != null)
                    _SmallTag(
                      label:
                          'Respuesta ${_formatDate(record.responseDeadline!)}',
                      color: _muted,
                    ),
                  const SizedBox(width: 4),
                  TextButton.icon(
                    onPressed: onDetails,
                    icon: const Icon(Icons.visibility_outlined, size: 17),
                    label: const Text('Detalle'),
                  ),
                  TextButton.icon(
                    onPressed: onEvidence,
                    icon: const Icon(Icons.attach_file_rounded, size: 17),
                    label: Text(
                      record.attachments.isEmpty
                          ? 'Adjuntar evidencia'
                          : '${record.attachments.length} adjunto(s)',
                    ),
                  ),
                  if (onResponse != null)
                    TextButton.icon(
                      onPressed: onResponse,
                      icon: const Icon(
                        Icons.chat_bubble_outline_rounded,
                        size: 17,
                      ),
                      label: Text(
                        record.employeeResponse.isEmpty
                            ? 'Registrar respuesta'
                            : 'Actualizar respuesta',
                      ),
                    ),
                  TextButton.icon(
                    onPressed: onClose,
                    icon: Icon(
                      record.status == DisciplinaryStatus.closed
                          ? Icons.refresh_rounded
                          : Icons.task_alt_rounded,
                      size: 17,
                    ),
                    label: Text(
                      record.status == DisciplinaryStatus.closed
                          ? 'Reabrir'
                          : 'Cerrar proceso',
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
                'Aquí verás procesos, respuestas, seguimientos y cierres del colaborador.',
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
            label: const Text('Registrar primer proceso'),
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

class _DetailBlock extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _DetailBlock(
    this.label,
    this.value, {
    this.color = const Color(0xFFF8FAFC),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w800, color: _ink),
          ),
          const SizedBox(height: 5),
          Text(value, style: const TextStyle(height: 1.4)),
        ],
      ),
    );
  }
}

class _DateButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  const _DateButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
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
          color: active ? const Color(0xFF15803D) : const Color(0xFFB45309),
        ),
      ),
    );
  }
}

class _RecordStatusBadge extends StatelessWidget {
  final String status;
  const _RecordStatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        DisciplinaryStatus.label(status),
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

String _typeLabel(String value) {
  switch (value) {
    case 'verbal':
      return 'Llamado verbal';
    case 'descargos':
      return 'Citación a descargos';
    case 'compromiso':
      return 'Compromiso de mejora';
    case 'otro':
      return 'Otro proceso';
    default:
      return 'Llamado escrito';
  }
}

Color _severityColor(String severity) {
  switch (severity.toLowerCase()) {
    case 'alta':
      return const Color(0xFFB91C1C);
    case 'media':
      return const Color(0xFFD97706);
    default:
      return const Color(0xFF2563EB);
  }
}

Color _statusColor(String status) {
  switch (DisciplinaryStatus.normalize(status)) {
    case DisciplinaryStatus.closed:
      return const Color(0xFF15803D);
    case DisciplinaryStatus.followUp:
    case DisciplinaryStatus.inReview:
      return const Color(0xFF7C3AED);
    case DisciplinaryStatus.cancelled:
      return _muted;
    default:
      return const Color(0xFFD97706);
  }
}
