// lib/talento_humano/areas_management_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

const Color _khPrimary   = Color(0xffc28942);
const Color _khSecondary = Color(0xffe19e4c);
const String _kFont      = 'Arial';

class AreasManagementScreen extends StatefulWidget {
  final String userId; // cédula del usuario logueado
  const AreasManagementScreen({Key? key, required this.userId}) : super(key: key);

  @override
  State<AreasManagementScreen> createState() => _AreasManagementScreenState();
}

class _AreasManagementScreenState extends State<AreasManagementScreen> {
  final _db = FirebaseFirestore.instance;

  String _empresaId = '';
  bool _loadingHeader = true;
  bool _saving = false;

  CollectionReference<Map<String, dynamic>> get _areasColl =>
      _db.collection('TBL_AREAS');

  @override
  void initState() {
    super.initState();
    _loadEmpresa();
  }

  Future<void> _loadEmpresa() async {
    setState(() => _loadingHeader = true);
    final me = await _db.collection('TBL_USUARIOS').doc(widget.userId).get();
    final data = me.data() ?? {};
    _empresaId = (data['empresaId'] as String?)?.trim() ?? '';
    setState(() => _loadingHeader = false);
  }

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
              style: const TextStyle(fontFamily: _kFont)),
          content: Form(
            key: formKey,
            child: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nombreCtrl,
                    decoration: const InputDecoration(labelText: 'Nombre del área'),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Obligatorio'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: descCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Descripción (opcional)'),
                    maxLines: 2,
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
              style: ElevatedButton.styleFrom(backgroundColor: _khSecondary),
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                setState(() => _saving = true);

                final nombre = nombreCtrl.text.trim();
                final descripcion = descCtrl.text.trim();
                try {
                  if (isNew) {
                    // ID determinístico compatible con las semillas:
                    final areaId = '${_empresaId}_${_slug(nombre)}';
                    await _areasColl.doc(areaId).set({
                      'empresaId': _empresaId,
                      'areaId': areaId,
                      'nombre': nombre,
                      if (descripcion.isNotEmpty) 'descripcion': descripcion,
                      'createdAt': FieldValue.serverTimestamp(),
                      'updatedAt': FieldValue.serverTimestamp(),
                    }, SetOptions(merge: true));
                  } else {
                    await _areasColl.doc(doc!.id).set({
                      // No cambiamos el docId para no romper referencias
                      'empresaId': _empresaId,
                      'areaId': doc.id,
                      'nombre': nombre,
                      // Si descripción queda vacía, la removemos para mantener limpio
                      if (descripcion.isNotEmpty) 'descripcion': descripcion else 'descripcion': FieldValue.delete(),
                      'updatedAt': FieldValue.serverTimestamp(),
                    }, SetOptions(merge: true));
                  }
                  if (mounted) Navigator.of(ctx).pop();
                } finally {
                  if (mounted) setState(() => _saving = false);
                }
              },
              child: Text(isNew ? 'Crear' : 'Guardar',
                  style: const TextStyle(fontFamily: _kFont)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirmDelete(DocumentSnapshot<Map<String, dynamic>> doc) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar área', style: TextStyle(fontFamily: _kFont)),
        content: Text(
          '¿Seguro que deseas eliminar el área "${_s(doc.data()?['nombre'])}"?',
          style: const TextStyle(fontFamily: _kFont),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _areasColl.doc(doc.id).delete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = Text('Gestionar Áreas', style: const TextStyle(fontFamily: _kFont));

    return Scaffold(
      appBar: AppBar(
        title: title,
        backgroundColor: _khPrimary,
      ),
      body: _loadingHeader
          ? const Center(child: CircularProgressIndicator())
          : Stack(
        children: [
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _areasColl
                .where('empresaId', isEqualTo: _empresaId)
                .orderBy('nombre')
                .snapshots(),
            builder: (ctx, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) {
                return const Center(
                  child: Text('No hay áreas registradas.',
                      style: TextStyle(fontFamily: _kFont)),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const Divider(),
                itemBuilder: (context, i) {
                  final doc = docs[i];
                  final d = doc.data();
                  final nombre = _s(d['nombre']);
                  final descripcion = _s(d['descripcion']); // puede no existir
                  return ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: _khSecondary,
                      child: Icon(Icons.apartment, color: Colors.white),
                    ),
                    title: Text(
                      nombre.isEmpty ? doc.id : nombre,
                      style: const TextStyle(fontFamily: _kFont, fontSize: 16),
                    ),
                    subtitle: descripcion.isEmpty
                        ? null
                        : Text(descripcion,
                        style: const TextStyle(
                            fontFamily: _kFont, fontSize: 12)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Editar',
                          icon: const Icon(Icons.edit, color: _khPrimary),
                          onPressed: () => _openAreaDialog(doc: doc),
                        ),
                        IconButton(
                          tooltip: 'Eliminar',
                          icon: const Icon(Icons.delete, color: Colors.redAccent),
                          onPressed: () => _confirmDelete(doc),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
          if (_saving)
            const LinearProgressIndicator(
              minHeight: 4,
              backgroundColor: Colors.black26,
              color: _khSecondary,
            ),
        ],
      ),
      floatingActionButton: _loadingHeader
          ? null
          : FloatingActionButton(
        backgroundColor: _khSecondary,
        child: const Icon(Icons.add),
        onPressed: () => _openAreaDialog(),
      ),
    );
  }
}
