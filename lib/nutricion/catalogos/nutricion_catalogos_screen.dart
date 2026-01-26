import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../services/nutricion_service.dart';

class NutricionCatalogosScreen extends StatefulWidget {
  final String empresaId;

  const NutricionCatalogosScreen({
    super.key,
    required this.empresaId,
  });

  @override
  State<NutricionCatalogosScreen> createState() => _NutricionCatalogosScreenState();
}

class _NutricionCatalogosScreenState extends State<NutricionCatalogosScreen> {
  final _service = NutricionService();
  final _searchCtrl = TextEditingController();
  String _tipoSeleccionado = 'Todos';
  String _vista = 'Dietas';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Catálogos nutricionales',
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
                    labelText: 'Buscar',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              SizedBox(
                width: 200,
                child: DropdownButtonFormField<String>(
                  value: _tipoSeleccionado,
                  decoration: const InputDecoration(
                    labelText: 'Tipo',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Todos', child: Text('Todos')),
                    DropdownMenuItem(value: 'Terapéutica', child: Text('Terapéutica')),
                    DropdownMenuItem(value: 'Regular', child: Text('Regular')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _tipoSeleccionado = value);
                  },
                ),
              ),
              SizedBox(
                width: 200,
                child: DropdownButtonFormField<String>(
                  value: _vista,
                  decoration: const InputDecoration(
                    labelText: 'Vista',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Dietas', child: Text('Dietas')),
                    DropdownMenuItem(value: 'Patologías', child: Text('Patologías')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _vista = value);
                  },
                ),
              ),
              OutlinedButton.icon(
                onPressed: _openImportDialog,
                icon: const Icon(Icons.upload_file),
                label: const Text('Importar Excel'),
              ),
              OutlinedButton.icon(
                onPressed: _vista == 'Dietas' ? _openCrearDieta : null,
                icon: const Icon(Icons.add),
                label: const Text('Nueva dieta'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(child: _vista == 'Dietas' ? _buildDietasList() : _buildPatologiasList()),
        ],
      ),
    );
  }

  Widget _buildDietasList() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _service.streamDietas(widget.empresaId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data ?? [];
        final query = _searchCtrl.text.toLowerCase();
        final filtered = data.where((dieta) {
          final nombre = (dieta['nombre'] ?? '').toString().toLowerCase();
          final codigo = (dieta['codigo'] ?? '').toString().toLowerCase();
          final tipo = (dieta['tipo'] ?? '').toString();
          final matchQuery = query.isEmpty || nombre.contains(query) || codigo.contains(query);
          final matchTipo = _tipoSeleccionado == 'Todos' || tipo == _tipoSeleccionado;
          return matchQuery && matchTipo;
        }).toList();
        if (filtered.isEmpty) {
          return const Center(child: Text('Sin dietas registradas.'));
        }
        return ListView.separated(
          itemCount: filtered.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final dieta = filtered[index];
            return ListTile(
              title: Text(dieta['nombre']?.toString() ?? ''),
              subtitle: Text('Código: ${dieta['codigo'] ?? ''} • Tipo: ${dieta['tipo'] ?? ''}'),
              trailing: Icon(
                (dieta['activa'] ?? true) ? Icons.check_circle : Icons.remove_circle,
                color: (dieta['activa'] ?? true) ? Colors.green : Colors.red,
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPatologiasList() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _service.streamPatologias(widget.empresaId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data ?? [];
        if (data.isEmpty) {
          return const Center(child: Text('Sin patologías registradas.'));
        }
        return ListView.separated(
          itemCount: data.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final patologia = data[index];
            return ListTile(
              title: Text(patologia['nombre']?.toString() ?? ''),
              subtitle: Text('Código: ${patologia['codigo'] ?? ''}'),
            );
          },
        );
      },
    );
  }

  Future<void> _openCrearDieta() async {
    final codigoCtrl = TextEditingController();
    final nombreCtrl = TextEditingController();
    final tipoCtrl = TextEditingController();
    final kcalCtrl = TextEditingController();
    final tagsCtrl = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Nueva dieta'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _buildField('Código', codigoCtrl),
                  _buildField('Nombre', nombreCtrl),
                  _buildField('Tipo', tipoCtrl),
                  _buildField('Kcal objetivo', kcalCtrl, keyboardType: TextInputType.number),
                  _buildField('Tags (coma separada)', tagsCtrl),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () async {
                await _service.guardarDieta(
                  empresaId: widget.empresaId,
                  codigo: codigoCtrl.text.trim(),
                  nombre: nombreCtrl.text.trim(),
                  tipo: tipoCtrl.text.trim(),
                  kcalObjetivo: num.tryParse(kcalCtrl.text.trim()),
                  tags: tagsCtrl.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
                );
                if (!mounted) return;
                Navigator.of(context).pop();
              },
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildField(String label, TextEditingController controller, {TextInputType? keyboardType}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Future<void> _openImportDialog() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final bytes = result.files.first.bytes;
    if (bytes == null) return;
    await _importCatalog(bytes);
  }

  Future<void> _importCatalog(Uint8List bytes) async {
    try {
      await _service.importarCatalogos(empresaId: widget.empresaId, bytes: bytes);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Catálogos importados correctamente.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al importar: $e')),
      );
    }
  }
}