// lib/nutricion/catalogos/nutricion_catalogos_screen.dart

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:todo/theme/app_typography.dart';
import 'package:todo/widgets/empty_state_widget.dart';

import '../../services/nutricion_service.dart';
import '../widgets/nutrition_shared_widgets.dart';

class NutricionCatalogosScreen extends StatefulWidget {
  final String empresaId;
  final String userId;
  final bool showAppBar;

  const NutricionCatalogosScreen({
    super.key,
    required this.empresaId,
    required this.userId,
    this.showAppBar = true,
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
    final bool isWide = MediaQuery.of(context).size.width >= 900;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!widget.showAppBar) _buildWebHeaderContext(),
        _buildBusquedaBar(isWide),
        Expanded(child: _buildMainContent(isWide)),
      ],
    );

    if (!widget.showAppBar) {
      return Scaffold(
        backgroundColor: NutritionPalette.background,
        body: content,
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _openCrearPaciente,
          icon: const Icon(Icons.person_add_outlined),
          label: const Text('REGISTRAR PACIENTE', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.5)),
          backgroundColor: NutritionPalette.accent,
          foregroundColor: Colors.white,
        ),
      );
    }

    return Scaffold(
      backgroundColor: NutritionPalette.background,
      appBar: AppBar(
        title: const Text('Directorio de Pacientes', style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.bold)),
        backgroundColor: NutritionPalette.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: content,
    );
  }

  Widget _buildWebHeaderContext() {
    return const Padding(
      padding: EdgeInsets.fromLTRB(32, 24, 32, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'EXPEDIENTES CLÍNICOS',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: NutritionPalette.accent, fontFamily: kArial),
          ),
          SizedBox(height: 8),
          Text(
            'Directorio Maestro de Pacientes',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: NutritionPalette.textMain, fontFamily: kArial),
          ),
          SizedBox(height: 8),
          Text(
            'Consulta el historial de atenciones, diagnósticos y planes alimentarios de cada usuario.',
            style: TextStyle(fontSize: 14, color: NutritionPalette.textMuted, fontFamily: kArial),
          ),
        ],
      ),
    );
  }

  Widget _buildBusquedaBar(bool isWide) {
    return Container(
      padding: EdgeInsets.fromLTRB(isWide ? 32 : 16, 16, isWide ? 32 : 16, 16),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Buscar por nombre o documento…',
                prefixIcon: const Icon(Icons.search, size: 20),
                filled: true,
                fillColor: NutritionPalette.surface,
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: NutritionPalette.border)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: NutritionPalette.accent, width: 2)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              onChanged: _onSearchChanged,
            ),
          ),
          if (isWide) ...[
            const SizedBox(width: 16),
            FilledButton.icon(
              onPressed: _openCrearPaciente,
              icon: const Icon(Icons.person_add_outlined, size: 18),
              label: const Text('NUEVO PACIENTE'),
              style: FilledButton.styleFrom(
                backgroundColor: NutritionPalette.accent,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMainContent(bool isWide) {
    if (isWide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 2, child: _buildListaPacientes(true)),
          const VerticalDivider(width: 1, thickness: 1, color: NutritionPalette.border),
          Expanded(flex: 3, child: _buildDetalleVisual(true)),
        ],
      );
    }
    return Column(
      children: [
        if (_selected != null) 
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildDetalleVisual(false),
          ),
        Expanded(child: _buildListaPacientes(false)),
      ],
    );
  }

  Widget _buildListaPacientes(bool isWide) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _service.streamDirectorioNutricion(empresaId: widget.empresaId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        final data = snapshot.data ?? [];
        final filtered = data.where((row) {
          final n = (row['nombreCompleto'] ?? '').toString().toLowerCase();
          final d = (row['documento'] ?? '').toString().toLowerCase();
          return _searchQuery.isEmpty || n.contains(_searchQuery) || d.contains(_searchQuery);
        }).toList();

        if (filtered.isEmpty) {
          return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.person_off_outlined, size: 48, color: NutritionPalette.textMuted), const SizedBox(height: 12), Text(_searchQuery.isEmpty ? 'Sin pacientes' : 'Sin resultados', style: const TextStyle(color: NutritionPalette.textMuted))]));
        }

        return ListView.separated(
          padding: EdgeInsets.fromLTRB(isWide ? 32 : 16, 8, isWide ? 16 : 16, 100),
          itemCount: filtered.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final p = filtered[index];
            final sel = _selected?['id'] == p['id'];
            return _PacienteListTile(
              data: p,
              selected: sel,
              onTap: () => setState(() => _selected = p),
              onEdit: () => _openEditarPaciente(p),
            );
          },
        );
      },
    );
  }

  Widget _buildDetalleVisual(bool isWide) {
    if (_selected == null) {
      return Center(child: EmptyStateWidget(icon: Icons.contact_page_outlined, title: 'Selecciona un paciente', message: 'Toca un registro de la lista para ver el expediente completo.', compact: true));
    }
    final p = _selected!;
    return SingleChildScrollView(
      padding: EdgeInsets.all(isWide ? 32 : 0),
      child: Column(
        children: [
          NutritionCard(
            title: 'EXPEDIENTE TÉCNICO',
            trailing: IconButton(icon: Icon(Icons.close, size: 20), onPressed: () => setState(() => _selected = null)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CarnetFrame(fotoUrl: p['fotoUrl']?.toString()),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p['nombreCompleto']?.toString() ?? 'Sin nombre', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: NutritionPalette.textMain, fontFamily: kArial)),
                      const SizedBox(height: 4),
                      _expedienteItem(Icons.badge_outlined, 'Identificación', '${p['tipoDocumento'] ?? ''} ${p['documento'] ?? ''}'),
                      const Divider(height: 24),
                      _expedienteItem(Icons.medical_information_outlined, 'Dx Médico', p['diagnosticoMedico'] ?? 'No registrado'),
                      _expedienteItem(Icons.health_and_safety_outlined, 'Dx Nutricional', p['diagnosticoNutricional'] ?? 'No registrado'),
                      _expedienteItem(Icons.restaurant_outlined, 'Plan Sugerido', p['tipoDietaSugerida'] ?? 'Pendiente'),
                      _expedienteItem(Icons.calendar_today_outlined, 'Próximo Control', p['fechaReevaluacion'] ?? 'No agendado'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _expedienteItem(IconData icon, String label, String val) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [Icon(icon, size: 14, color: NutritionPalette.textMuted), const SizedBox(width: 8), Text('$label: ', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: NutritionPalette.textMuted)), Expanded(child: Text(val, style: const TextStyle(fontSize: 12, color: NutritionPalette.textMain), overflow: TextOverflow.ellipsis))]),
    );
  }

  Future<void> _openCrearPaciente() async {
    final res = await showDialog<PacienteFormResult>(context: context, builder: (_) => PacienteDialog(empresaId: widget.empresaId, userId: widget.userId, service: _service));
    if (res != null && mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Paciente registrado'), backgroundColor: Colors.green, behavior: SnackBarBehavior.floating));
  }

  Future<void> _openEditarPaciente(Map<String, dynamic> existing) async {
    final res = await showDialog<PacienteFormResult>(context: context, builder: (_) => PacienteDialog(empresaId: widget.empresaId, userId: widget.userId, service: _service, existing: existing));
    if (res != null && mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Paciente actualizado'), backgroundColor: NutritionPalette.accent, behavior: SnackBarBehavior.floating));
  }
}

class _PacienteListTile extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  const _PacienteListTile({required this.data, required this.selected, required this.onTap, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? NutritionPalette.accent.withValues(alpha: 0.05) : NutritionPalette.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? NutritionPalette.accent : NutritionPalette.border.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            _AvatarPaciente(fotoUrl: data['fotoUrl']?.toString(), nombre: data['nombreCompleto']?.toString() ?? ''),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(data['nombreCompleto']?.toString() ?? 'Sin nombre', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: selected ? NutritionPalette.accent : NutritionPalette.textMain)),
                  Text('${data['tipoDocumento'] ?? 'ID'}: ${data['documento'] ?? ''}', style: const TextStyle(fontSize: 11, color: NutritionPalette.textMuted)),
                ],
              ),
            ),
            IconButton(icon: Icon(Icons.edit_outlined, size: 18, color: selected ? NutritionPalette.accent : NutritionPalette.textMuted), onPressed: onEdit),
          ],
        ),
      ),
    );
  }
}

class _AvatarPaciente extends StatelessWidget {
  final String? fotoUrl;
  final String nombre;
  const _AvatarPaciente({this.fotoUrl, required this.nombre});
  @override
  Widget build(BuildContext context) {
    if (fotoUrl != null && fotoUrl!.isNotEmpty) return CircleAvatar(radius: 20, backgroundImage: NetworkImage(fotoUrl!));
    final ini = nombre.trim().isNotEmpty ? nombre.trim().split(' ').take(2).map((w) => w[0].toUpperCase()).join() : '?';
    return CircleAvatar(radius: 20, backgroundColor: NutritionPalette.background, child: Text(ini, style: const TextStyle(color: NutritionPalette.accent, fontWeight: FontWeight.bold, fontSize: 12)));
  }
}

class _CarnetFrame extends StatelessWidget {
  final String? fotoUrl;
  const _CarnetFrame({this.fotoUrl});
  @override
  Widget build(BuildContext context) {
    const double w = 80; const double h = 100;
    return Container(
      width: w, height: h,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), border: Border.all(color: NutritionPalette.border, width: 1.5)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: (fotoUrl != null && fotoUrl!.isNotEmpty)
            ? Image.network(fotoUrl!, fit: BoxFit.cover, errorBuilder: (_, _, _) => const Icon(Icons.person, size: 40, color: NutritionPalette.textMuted))
            : const Icon(Icons.person, size: 40, color: NutritionPalette.textMuted),
      ),
    );
  }
}

// Reutilizamos el PacienteDialog existente pero con ajustes de estilo mínimos si es necesario
// [PacienteDialog y PacienteFormResult se mantienen iguales al original para no romper lógica CRUD]
class PacienteFormResult {
  final String pacienteId, nombreCompleto, documento;
  final bool esNuevo;
  final String? fotoUrl;
  const PacienteFormResult({required this.pacienteId, required this.nombreCompleto, required this.documento, required this.esNuevo, this.fotoUrl});
}

class PacienteDialog extends StatefulWidget {
  final String empresaId, userId;
  final NutricionService service;
  final Map<String, dynamic>? existing;
  const PacienteDialog({super.key, required this.empresaId, required this.userId, required this.service, this.existing});
  @override State<PacienteDialog> createState() => _PacienteDialogState();
}

class _PacienteDialogState extends State<PacienteDialog> {
  late final TextEditingController _nombresCtrl, _apellidosCtrl, _documentoCtrl;
  Uint8List? _fotoBytes; String? _fotoUrlExistente;
  static const List<String> _tiposDocumento = ['Cédula de ciudadanía', 'Cédula de extranjería', 'Pasaporte', 'Tarjeta de identidad', 'NIT', 'Otro'];
  late String _tipoDocumento; bool _saving = false; String? _error;

  @override
  void initState() {
    super.initState();
    final ex = widget.existing;
    _nombresCtrl = TextEditingController(text: ex?['nombres']?.toString() ?? '');
    _apellidosCtrl = TextEditingController(text: ex?['apellidos']?.toString() ?? '');
    _documentoCtrl = TextEditingController(text: ex?['documento']?.toString() ?? '');
    _fotoUrlExistente = ex?['fotoUrl']?.toString();
    _tipoDocumento = _tiposDocumento.contains(ex?['tipoDocumento']) ? ex!['tipoDocumento'] : _tiposDocumento.first;
  }

  @override void dispose() { _nombresCtrl.dispose(); _apellidosCtrl.dispose(); _documentoCtrl.dispose(); super.dispose(); }

  Future<void> _guardar() async {
    if (_nombresCtrl.text.isEmpty || _documentoCtrl.text.isEmpty) return;
    setState(() => _saving = true);
    try {
      String? fotoUrl = _fotoUrlExistente;
      if (_fotoBytes != null) fotoUrl = await widget.service.subirFotoPaciente(empresaId: widget.empresaId, documento: _documentoCtrl.text, bytes: _fotoBytes!);
      final id = await widget.service.guardarDirectorioNutricion(empresaId: widget.empresaId, userId: widget.userId, data: {'nombres': _nombresCtrl.text, 'apellidos': _apellidosCtrl.text, 'nombreCompleto': '${_nombresCtrl.text} ${_apellidosCtrl.text}', 'tipoDocumento': _tipoDocumento, 'documento': _documentoCtrl.text, if (fotoUrl != null) 'fotoUrl': fotoUrl}, id: widget.existing?['id']);
      if (mounted) Navigator.pop(context, PacienteFormResult(pacienteId: id, nombreCompleto: '${_nombresCtrl.text} ${_apellidosCtrl.text}', documento: _documentoCtrl.text, esNuevo: widget.existing == null, fotoUrl: fotoUrl));
    } catch (e) { if (mounted) setState(() => _error = e.toString()); }
    finally { if (mounted) setState(() => _saving = false); }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Nuevo Paciente' : 'Editar Paciente', style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: kArial)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: _nombresCtrl, decoration: const InputDecoration(labelText: 'Nombres')),
            TextField(controller: _apellidosCtrl, decoration: const InputDecoration(labelText: 'Apellidos')),
            DropdownButtonFormField<String>(initialValue: _tipoDocumento, items: _tiposDocumento.map((t)=>DropdownMenuItem(value:t, child: Text(t))).toList(), onChanged: (v)=>setState(()=>_tipoDocumento=v!), decoration: const InputDecoration(labelText: 'Tipo Doc')),
            TextField(controller: _documentoCtrl, decoration: const InputDecoration(labelText: 'Documento'), keyboardType: TextInputType.number),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: ()=>Navigator.pop(context), child: const Text('CANCELAR')),
        FilledButton(onPressed: _saving ? null : _guardar, style: FilledButton.styleFrom(backgroundColor: NutritionPalette.accent), child: Text(_saving ? 'GUARDANDO…' : 'GUARDAR')),
      ],
    );
  }
}
