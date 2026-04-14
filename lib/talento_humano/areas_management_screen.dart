// lib/talento_humano/areas_management_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../widgets/internal_module_layout.dart';

const Color _khPrimary   = Color(0xffc28942);
const Color _khSecondary = Color(0xffe19e4c);
const String _kFont      = 'Arial';

class AreasManagementScreen extends StatefulWidget {
  final String userId;
  final String empresaId;
  const AreasManagementScreen({Key? key, required this.userId, required this.empresaId}) : super(key: key);

  @override
  State<AreasManagementScreen> createState() => _AreasManagementScreenState();
}

class _AreasManagementScreenState extends State<AreasManagementScreen> {
  final _db = FirebaseFirestore.instance;
  bool _saving = false;

  CollectionReference<Map<String, dynamic>> get _areasColl =>
      _db.collection('TBL_AREAS');

  String _s(dynamic v) => v == null ? '' : v.toString().trim();

  String _slug(String s) {
    final base = s
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return base.isEmpty ? 'area' : base;
  }

  Future<void> _openAreaDialog({DocumentSnapshot<Map<String, dynamic>>? doc}) async {
    final isNew = doc == null;
    final data = doc?.data() ?? {};
    final formKey = GlobalKey<FormState>();

    final nombreCtrl = TextEditingController(text: isNew ? '' : _s(data['nombre']));
    final descCtrl   = TextEditingController(text: isNew ? '' : _s(data['descripcion']));

    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(isNew ? 'Crear área' : 'Editar área',
              style: const TextStyle(fontFamily: _kFont, fontWeight: FontWeight.bold)),
          content: Form(
            key: formKey,
            child: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nombreCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nombre del área',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Obligatorio'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: descCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Descripción (opcional)',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _khPrimary,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;

                setState(() => _saving = true);
                try {
                  final payload = {
                    'nombre': nombreCtrl.text.trim(),
                    'descripcion': descCtrl.text.trim(),
                    'empresaId': widget.empresaId,
                    'updatedAt': FieldValue.serverTimestamp(),
                  };

                  if (isNew) {
                    final id = '${widget.empresaId}_${_slug(nombreCtrl.text.trim())}';
                    await _areasColl.doc(id).set(payload);
                  } else {
                    await doc.reference.update(payload);
                  }
                  if (mounted) Navigator.of(ctx).pop();
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e')));
                  }
                } finally {
                  if (mounted) setState(() => _saving = false);
                }
              },
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteArea(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar área'),
        content: const Text('¿Estás seguro de eliminar esta área?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _areasColl.doc(id).delete();
    }
  }

  @override
  Widget build(BuildContext context) {
    return InternalModuleLayout(
      userId: widget.userId,
      empresaId: widget.empresaId,
      title: 'Gestión de Áreas',
      subtitle: 'Definición de áreas y departamentos de la empresa',
      accentColor: _khPrimary,
      headerActions: [
        IconButton(
          icon: const Icon(Icons.add_circle_outline_rounded, size: 28),
          onPressed: () => _openAreaDialog(),
          tooltip: 'Nueva Área',
          color: _khPrimary,
        ),
      ],
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _areasColl
            .where('empresaId', isEqualTo: widget.empresaId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(child: Text('No hay áreas registradas para esta empresa.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(24),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (ctx, idx) {
              final doc = docs[idx];
              final data = doc.data();
              return ModuleCard(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _khPrimary.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.hub_outlined, color: _khPrimary, size: 20),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _s(data['nombre']),
                            style: const TextStyle(
                              fontFamily: _kFont,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          if (_s(data['descripcion']).isNotEmpty)
                            Text(
                              _s(data['descripcion']),
                              style: const TextStyle(
                                fontFamily: _kFont,
                                fontSize: 13,
                                color: Color(0xFF64748B),
                              ),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, color: Color(0xFF64748B)),
                      onPressed: () => _openAreaDialog(doc: doc),
                      tooltip: 'Editar',
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                      onPressed: () => _deleteArea(doc.id),
                      tooltip: 'Eliminar',
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
