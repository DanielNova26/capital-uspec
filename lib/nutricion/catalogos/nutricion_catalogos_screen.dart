import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/nutricion_service.dart';

class NutricionCatalogosScreen extends StatefulWidget {
  final String empresaId;
  final String userId;

  const NutricionCatalogosScreen({
    super.key,
    required this.empresaId,
    required this.userId,
  });

  @override
  State<NutricionCatalogosScreen> createState() =>
      _NutricionCatalogosScreenState();
}

class _NutricionCatalogosScreenState
    extends State<NutricionCatalogosScreen> {
  final _service = NutricionService();
  final _searchCtrl = TextEditingController();
  Map<String, dynamic>? _selected;
  Timer? _searchDebounce;
  String _searchQuery = '';

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() => _searchQuery = value.toLowerCase().trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Directorio de pacientes',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 260,
                child: TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Buscar paciente',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: _onSearchChanged,
                ),
              ),
              FilledButton.icon(
                onPressed: _openCrearPaciente,
                icon: const Icon(Icons.person_add),
                label: const Text('Nuevo paciente'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(child: _buildDirectorio()),
        ],
      ),
    );
  }

  Widget _buildDirectorio() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _service.streamDirectorioNutricion(empresaId: widget.empresaId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data ?? [];
        final query = _searchQuery;
        final filtered = data.where((row) {
          final nombre =
              (row['nombreCompleto'] ?? '').toString().toLowerCase();
          final documento =
              (row['documento'] ?? '').toString().toLowerCase();
          return query.isEmpty ||
              nombre.contains(query) ||
              documento.contains(query);
        }).toList();

        if (data.isEmpty) {
          return const Center(child: Text('Sin pacientes registrados.'));
        }

        return Column(
          children: [
            if (_selected != null) _buildDetalleCard(_selected!),
            Expanded(
              child: ListView.separated(
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final paciente = filtered[index];
                  final selected = _selected?['id'] == paciente['id'];
                  final fotoUrl = paciente['fotoUrl']?.toString();
                  final nombre = paciente['nombreCompleto']?.toString() ??
                      'Sin nombre';
                  final tipoDoc =
                      paciente['tipoDocumento']?.toString() ?? 'Doc';
                  final numDoc = paciente['documento']?.toString() ?? '';

                  return ListTile(
                    selected: selected,
                    leading: _AvatarPaciente(fotoUrl: fotoUrl, nombre: nombre),
                    title: Text(
                      nombre,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      '$tipoDoc: $numDoc • ${paciente['diagnosticoNutricional'] ?? 'Sin diagnóstico'}',
                    ),
                    trailing: Wrap(
                      spacing: 4,
                      children: [
                        IconButton(
                          tooltip: 'Ver detalle',
                          icon: const Icon(Icons.description_outlined),
                          onPressed: () =>
                              setState(() => _selected = paciente),
                        ),
                        IconButton(
                          tooltip: 'Editar',
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => _openEditarPaciente(paciente),
                        ),
                      ],
                    ),
                    onTap: () => setState(() => _selected = paciente),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDetalleCard(Map<String, dynamic> p) {
    final fotoUrl = p['fotoUrl']?.toString();
    return Card(
      elevation: 0,
      color: Theme.of(context)
          .colorScheme
          .surfaceVariant
          .withOpacity(0.35),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Marco tipo carnet
            _CarnetFrame(fotoUrl: fotoUrl),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p['nombreCompleto']?.toString() ?? '',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  _detalleRow('Documento',
                      '${p['tipoDocumento'] ?? ''} ${p['documento'] ?? ''}'),
                  _detalleRow(
                      'Diagnóstico médico', p['diagnosticoMedico'] ?? ''),
                  _detalleRow('Diagnóstico nutricional',
                      p['diagnosticoNutricional'] ?? ''),
                  _detalleRow(
                      'Tipo de dieta', p['tipoDietaSugerida'] ?? ''),
                  _detalleRow('Duración', p['duracionDieta'] ?? ''),
                  _detalleRow('Control', p['controlNutricional'] ?? ''),
                  _detalleRow(
                      'Inicio dieta', p['inicioDieta'] ?? ''),
                  _detalleRow(
                      'Reevaluación', p['fechaReevaluacion'] ?? ''),
                  if ((p['observaciones'] ?? '').toString().isNotEmpty)
                    _detalleRow('Observaciones', p['observaciones'] ?? ''),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detalleRow(String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        '$label: $value',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }

  // ── CRUD ──────────────────────────────────────────────────────────────────

  Future<void> _openCrearPaciente() async {
    final data = await showDialog<PacienteFormResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PacienteDialog(
        empresaId: widget.empresaId,
        userId: widget.userId,
        service: _service,
      ),
    );
    if (data == null) return;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Paciente registrado correctamente'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _openEditarPaciente(Map<String, dynamic> existing) async {
    final data = await showDialog<PacienteFormResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PacienteDialog(
        empresaId: widget.empresaId,
        userId: widget.userId,
        service: _service,
        existing: existing,
      ),
    );
    if (data == null) return;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Paciente actualizado correctamente'),
          backgroundColor: Colors.blue,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Resultado del formulario (público para reusar desde otros widgets)
// ─────────────────────────────────────────────────────────────────────────────

class PacienteFormResult {
  const PacienteFormResult();
}

// ─────────────────────────────────────────────────────────────────────────────
// Diálogo de registro / edición de paciente (público para reusar)
// ─────────────────────────────────────────────────────────────────────────────

class PacienteDialog extends StatefulWidget {
  final String empresaId;
  final String userId;
  final NutricionService service;
  final Map<String, dynamic>? existing;

  const PacienteDialog({
    super.key,
    required this.empresaId,
    required this.userId,
    required this.service,
    this.existing,
  });

  @override
  State<PacienteDialog> createState() => _PacienteDialogState();
}

class _PacienteDialogState extends State<PacienteDialog> {
  // ── Controladores ──────────────────────────────────────────────────────────
  late final TextEditingController _nombresCtrl;
  late final TextEditingController _apellidosCtrl;
  late final TextEditingController _documentoCtrl;

  // ── Estado foto ────────────────────────────────────────────────────────────
  Uint8List? _fotoBytes;
  String? _fotoUrlExistente;

  // ── Tipo de documento ──────────────────────────────────────────────────────
  static const List<String> _tiposDocumento = [
    'Cédula de ciudadanía',
    'Cédula de extranjería',
    'Pasaporte',
    'Tarjeta de identidad',
    'NIT',
    'Otro',
  ];
  late String _tipoDocumento;

  // ── Carga / error ──────────────────────────────────────────────────────────
  bool _saving = false;
  String? _error;

  Map<String, dynamic>? get _ex => widget.existing;

  @override
  void initState() {
    super.initState();
    final nombreCompleto = _ex?['nombreCompleto']?.toString() ?? '';
    final partes = nombreCompleto.split(' ');
    final nombres = partes.length > 1
        ? partes.sublist(0, (partes.length / 2).ceil()).join(' ')
        : nombreCompleto;
    final apellidos = partes.length > 1
        ? partes.sublist((partes.length / 2).ceil()).join(' ')
        : (_ex?['apellidos']?.toString() ?? '');

    _nombresCtrl =
        TextEditingController(text: _ex?['nombres']?.toString() ?? nombres);
    _apellidosCtrl =
        TextEditingController(text: _ex?['apellidos']?.toString() ?? apellidos);
    _documentoCtrl =
        TextEditingController(text: _ex?['documento']?.toString() ?? '');

    _fotoUrlExistente = _ex?['fotoUrl']?.toString();

    final storedTipo = _ex?['tipoDocumento']?.toString() ?? '';
    _tipoDocumento = _tiposDocumento.contains(storedTipo)
        ? storedTipo
        : _tiposDocumento.first;
  }

  @override
  void dispose() {
    _nombresCtrl.dispose();
    _apellidosCtrl.dispose();
    _documentoCtrl.dispose();
    super.dispose();
  }

  // ── Foto ───────────────────────────────────────────────────────────────────

  Future<void> _pickFoto() async {
    final picker = ImagePicker();
    final xfile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );
    if (xfile == null) return;
    final bytes = await xfile.readAsBytes();
    if (mounted) setState(() => _fotoBytes = bytes);
  }

  Future<void> _takeFoto() async {
    final picker = ImagePicker();
    final xfile = await picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );
    if (xfile == null) return;
    final bytes = await xfile.readAsBytes();
    if (mounted) setState(() => _fotoBytes = bytes);
  }

  // ── Guardar ────────────────────────────────────────────────────────────────

  Future<void> _guardar() async {
    final nombres = _nombresCtrl.text.trim();
    final apellidos = _apellidosCtrl.text.trim();
    final documento = _documentoCtrl.text.trim();

    if (nombres.isEmpty || apellidos.isEmpty || documento.isEmpty) {
      setState(() => _error = 'Nombres, apellidos y documento son obligatorios.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      // Subir foto si hay nueva
      String? fotoUrl = _fotoUrlExistente;
      if (_fotoBytes != null) {
        fotoUrl = await widget.service.subirFotoPaciente(
          empresaId: widget.empresaId,
          documento: documento,
          bytes: _fotoBytes!,
        );
      }

      final nombreCompleto = '$nombres $apellidos'.trim();

      await widget.service.guardarDirectorioNutricion(
        empresaId: widget.empresaId,
        userId: widget.userId,
        data: {
          'nombres': nombres,
          'apellidos': apellidos,
          'nombreCompleto': nombreCompleto,
          'tipoDocumento': _tipoDocumento,
          'documento': documento,
          if (fotoUrl != null) 'fotoUrl': fotoUrl,
        },
        id: _ex?['id']?.toString(),
      );

      if (mounted) Navigator.of(context).pop(const PacienteFormResult());
    } catch (e) {
      if (mounted) setState(() => _error = 'Error al guardar: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final esEdicion = _ex != null;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Encabezado ──────────────────────────────────────────────
              Row(
                children: [
                  Icon(
                    esEdicion ? Icons.edit : Icons.person_add,
                    color: Theme.of(context).colorScheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      esEdicion ? 'Editar paciente' : 'Nuevo paciente',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Foto centrada ────────────────────────────────────────────
              Center(child: _buildFotoCarnet()),
              const SizedBox(height: 16),

              // ── Nombres y apellidos ──────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      'Nombres',
                      _nombresCtrl,
                      icon: Icons.person_outline,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildTextField(
                      'Apellidos',
                      _apellidosCtrl,
                      icon: Icons.person_outline,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // ── Tipo de documento ────────────────────────────────────────
              _buildDropdown(),
              const SizedBox(height: 10),

              // ── Número de documento ──────────────────────────────────────
              _buildTextField(
                'Número de documento',
                _documentoCtrl,
                icon: Icons.badge_outlined,
                keyboardType: TextInputType.number,
              ),

              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ],

              const SizedBox(height: 20),

              // ── Acciones ─────────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed:
                        _saving ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _saving ? null : _guardar,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(_saving ? 'Guardando…' : 'Guardar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Helpers de UI ──────────────────────────────────────────────────────────

  Widget _buildTextField(
    String label,
    TextEditingController ctrl, {
    IconData? icon,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboardType,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        prefixIcon: icon != null ? Icon(icon, size: 20) : null,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      ),
    );
  }

  Widget _buildDropdown() {
    return DropdownButtonFormField<String>(
      value: _tipoDocumento,
      decoration: InputDecoration(
        labelText: 'Tipo de documento',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        prefixIcon: const Icon(Icons.article_outlined, size: 20),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      ),
      items: _tiposDocumento
          .map((t) => DropdownMenuItem(value: t, child: Text(t, overflow: TextOverflow.ellipsis)))
          .toList(),
      onChanged: (v) {
        if (v != null) setState(() => _tipoDocumento = v);
      },
    );
  }

  Widget _buildFotoCarnet() {
    const double w = 100;
    const double h = 126;

    Widget fotoWidget;

    if (_fotoBytes != null) {
      fotoWidget = Image.memory(
        _fotoBytes!,
        width: w,
        height: h,
        fit: BoxFit.cover,
      );
    } else if (_fotoUrlExistente != null && _fotoUrlExistente!.isNotEmpty) {
      fotoWidget = Image.network(
        _fotoUrlExistente!,
        width: w,
        height: h,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fotoPlaceholder(w, h),
      );
    } else {
      fotoWidget = _fotoPlaceholder(w, h);
    }

    return Column(
      children: [
        // Marco tipo carnet
        Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Theme.of(context).colorScheme.primary,
              width: 2.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: fotoWidget,
          ),
        ),
        const SizedBox(height: 8),
        // Botones de foto
        Wrap(
          spacing: 6,
          children: [
            _miniBtn(Icons.photo_library_outlined, 'Galería', _pickFoto),
            _miniBtn(Icons.camera_alt_outlined, 'Cámara', _takeFoto),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Foto para carnet',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }

  Widget _fotoPlaceholder(double w, double h) {
    return Container(
      width: w,
      height: h,
      color: Theme.of(context).colorScheme.surfaceVariant,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.person,
            size: 48,
            color: Theme.of(context)
                .colorScheme
                .onSurfaceVariant
                .withOpacity(0.5),
          ),
          const SizedBox(height: 4),
          Text(
            'Sin foto',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurfaceVariant
                      .withOpacity(0.7),
                ),
          ),
        ],
      ),
    );
  }

  Widget _miniBtn(IconData icon, String tooltip, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            border: Border.all(
              color: Theme.of(context).colorScheme.outline,
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 18),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Avatar circular para la lista
// ─────────────────────────────────────────────────────────────────────────────

class _AvatarPaciente extends StatelessWidget {
  final String? fotoUrl;
  final String nombre;

  const _AvatarPaciente({this.fotoUrl, required this.nombre});

  @override
  Widget build(BuildContext context) {
    if (fotoUrl != null && fotoUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: 22,
        backgroundImage: NetworkImage(fotoUrl!),
        onBackgroundImageError: (_, __) {},
      );
    }
    final initials = nombre.trim().isNotEmpty
        ? nombre.trim().split(' ').take(2).map((w) => w[0].toUpperCase()).join()
        : '?';
    return CircleAvatar(
      radius: 22,
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      child: Text(
        initials,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Marco tipo carnet para el detalle
// ─────────────────────────────────────────────────────────────────────────────

class _CarnetFrame extends StatelessWidget {
  final String? fotoUrl;

  const _CarnetFrame({this.fotoUrl});

  @override
  Widget build(BuildContext context) {
    const double w = 90;
    const double h = 110;

    Widget fotoWidget = (fotoUrl != null && fotoUrl!.isNotEmpty)
        ? Image.network(
            fotoUrl!,
            width: w,
            height: h,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _placeholder(context, w, h),
          )
        : _placeholder(context, w, h);

    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: fotoWidget,
      ),
    );
  }

  Widget _placeholder(BuildContext context, double w, double h) {
    return Container(
      width: w,
      height: h,
      color: Theme.of(context).colorScheme.surfaceVariant,
      child: Icon(
        Icons.person,
        size: 40,
        color: Theme.of(context)
            .colorScheme
            .onSurfaceVariant
            .withOpacity(0.5),
      ),
    );
  }
}
