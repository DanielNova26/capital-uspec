import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../utils/user_company.dart';
import '../widgets/internal_module_layout.dart';

const Color _accent = Color(0xFFC28942);
const String _font = 'Arial';

class CentrosCostosManagementScreen extends StatefulWidget {
  const CentrosCostosManagementScreen({
    super.key,
    required this.userId,
    required this.empresaId,
  });

  final String userId;
  final String empresaId;

  @override
  State<CentrosCostosManagementScreen> createState() =>
      _CentrosCostosManagementScreenState();
}

class _CentrosCostosManagementScreenState
    extends State<CentrosCostosManagementScreen> {
  final _db = FirebaseFirestore.instance;
  List<_CentroPerson> _people = const [];
  bool _loadingPeople = true;

  @override
  void initState() {
    super.initState();
    _loadPeople();
  }

  String _text(dynamic value) => (value ?? '').toString().trim();

  String _personName(Map<String, dynamic> data) {
    for (final value in [data['nombreCompleto'], data['displayName']]) {
      final name = _text(value);
      if (name.isNotEmpty) return name;
    }
    final parts = [
      data['primerNombre'],
      data['segundoNombre'],
      data['primerApellido'],
      data['segundoApellido'],
    ].map(_text).where((item) => item.isNotEmpty).toList();
    if (parts.isNotEmpty) return parts.join(' ');
    final combined = '${_text(data['nombres'])} ${_text(data['apellidos'])}'
        .trim();
    return combined.isEmpty ? _text(data['nombre']) : combined;
  }

  Future<void> _loadPeople() async {
    if (mounted) setState(() => _loadingPeople = true);
    try {
      final results = await Future.wait([
        _db
            .collection('TBL_USUARIOS')
            .where('empresas', arrayContains: widget.empresaId)
            .get(),
        _db
            .collection('TBL_USUARIOS')
            .where('empresaId', isEqualTo: widget.empresaId)
            .get(),
      ]);
      final docs = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
      for (final result in results) {
        for (final doc in result.docs) {
          docs[doc.id] = doc;
        }
      }
      final people = <_CentroPerson>[];
      for (final doc in docs.values) {
        final root = doc.data();
        final data = mergeCompanyScopedData(root, widget.empresaId);
        final center = _text(
          data['centroCostos'] ?? data['centro_nombre'] ?? data['centroNombre'],
        );
        if (center.isEmpty) continue;
        people.add(
          _CentroPerson(
            id: _text(root['cedula']).isEmpty ? doc.id : _text(root['cedula']),
            name: _personName(root).isEmpty ? doc.id : _personName(root),
            role: _text(data['cargo'] ?? data['cargoNombre']),
            area: _text(data['area'] ?? data['areaNombre']),
            center: center,
            centerId: _text(data['centroId']),
          ),
        );
      }
      people.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      if (mounted) setState(() => _people = people);
    } finally {
      if (mounted) setState(() => _loadingPeople = false);
    }
  }

  String _centerKey(String value) => value.trim().toLowerCase();

  List<_CentroPerson> _peopleFor(String id, String name) =>
      _people.where((person) {
        if (id.isNotEmpty && person.centerId == id) return true;
        return _centerKey(person.center) == _centerKey(name);
      }).toList();

  Future<void> _showPeople(
    String centerName,
    List<_CentroPerson> people,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$centerName · ${people.length} persona(s)'),
        content: SizedBox(
          width: 620,
          height: people.isEmpty ? 130 : 460,
          child: people.isEmpty
              ? const Center(
                  child: Text(
                    'No hay personal asignado a este centro de costo.',
                  ),
                )
              : ListView.separated(
                  itemCount: people.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final person = people[index];
                    final detail = [
                      person.role,
                      person.area,
                    ].where((item) => item.isNotEmpty).join(' · ');
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: _accent.withValues(alpha: .14),
                        foregroundColor: _accent,
                        child: Text(
                          person.name.isEmpty
                              ? '?'
                              : person.name[0].toUpperCase(),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      title: Text(person.name),
                      subtitle: Text(
                        detail.isEmpty
                            ? 'C.C. ${person.id}'
                            : '$detail\nC.C. ${person.id}',
                      ),
                      isThreeLine: detail.isNotEmpty,
                    );
                  },
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

  String _slug(String value) {
    final normalized = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return normalized.isEmpty ? 'centro' : normalized;
  }

  Query<Map<String, dynamic>> get _query => _db
      .collection('TBL_CENTROS_COSTOS')
      .where('empresaId', isEqualTo: widget.empresaId);

  Future<void> _edit([DocumentSnapshot<Map<String, dynamic>>? document]) async {
    final data = document?.data() ?? const <String, dynamic>{};
    final code = TextEditingController(text: (data['codigo'] ?? '').toString());
    final name = TextEditingController(text: (data['nombre'] ?? '').toString());
    var enabled = data['enabled'] != false;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            document == null
                ? 'Nuevo centro de costo'
                : 'Editar centro de costo',
          ),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: code,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Código',
                    hintText: 'Ej. CC-001',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Nombre',
                    hintText: 'Ej. Administración central',
                    border: OutlineInputBorder(),
                  ),
                ),
                SwitchListTile(
                  value: enabled,
                  onChanged: (value) => setDialogState(() => enabled = value),
                  title: const Text('Centro activo'),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                if (code.text.trim().isEmpty || name.text.trim().isEmpty) {
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true) return;
    final id = document?.id ?? '${widget.empresaId}_${_slug(code.text)}';
    await _db.collection('TBL_CENTROS_COSTOS').doc(id).set({
      'empresaId': widget.empresaId,
      'centroId': id,
      'codigo': code.text.trim(),
      'nombre': name.text.trim(),
      'enabled': enabled,
      'updatedBy': widget.userId,
      'updatedAt': FieldValue.serverTimestamp(),
      if (document == null) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _toggle(
    DocumentSnapshot<Map<String, dynamic>> document,
    bool value,
  ) => document.reference.set({
    'enabled': value,
    'updatedBy': widget.userId,
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));

  Future<void> _editDetected(String name) async {
    final code = _slug(name).toUpperCase();
    final id = '${widget.empresaId}_${_slug(name)}';
    await _db.collection('TBL_CENTROS_COSTOS').doc(id).set({
      'empresaId': widget.empresaId,
      'centroId': id,
      'codigo': code,
      'nombre': name.trim(),
      'enabled': true,
      'origen': 'detectado_personal',
      'updatedBy': widget.userId,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Widget build(BuildContext context) => InternalModuleLayout(
    userId: widget.userId,
    empresaId: widget.empresaId,
    title: 'Centros de costo',
    subtitle: 'Catálogo de Talento Humano para la empresa activa',
    accentColor: _accent,
    headerActions: [
      FilledButton.icon(
        onPressed: _edit,
        icon: const Icon(Icons.add_business_outlined),
        label: const Text('Nuevo centro'),
      ),
    ],
    child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final rows = [...?snapshot.data?.docs]
          ..sort(
            (a, b) => (a.data()['codigo'] ?? '').toString().compareTo(
              (b.data()['codigo'] ?? '').toString(),
            ),
          );
        final catalogNames = rows
            .map((doc) => _centerKey(_text(doc.data()['nombre'])))
            .toSet();
        final detected = <String, String>{};
        for (final person in _people) {
          final key = _centerKey(person.center);
          if (key.isNotEmpty && !catalogNames.contains(key)) {
            detected.putIfAbsent(key, () => person.center);
          }
        }
        return InternalModuleViewport(
          maxWidth: 980,
          padding: const EdgeInsets.all(24),
          child: rows.isEmpty && detected.isEmpty && !_loadingPeople
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.account_tree_outlined,
                        size: 52,
                        color: Color(0xFF94A3B8),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'No hay centros de costo configurados.',
                        style: TextStyle(fontFamily: _font),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _edit,
                        icon: const Icon(Icons.add),
                        label: const Text('Crear el primero'),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  itemCount: rows.length + detected.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    if (index >= rows.length) {
                      final name = detected.values.elementAt(
                        index - rows.length,
                      );
                      final people = _peopleFor('', name);
                      return Card(
                        color: const Color(0xFFFFFBEB),
                        child: ListTile(
                          onTap: () => _showPeople(name, people),
                          leading: const CircleAvatar(
                            backgroundColor: Color(0xFFFEF3C7),
                            child: Icon(
                              Icons.people_outline,
                              color: Color(0xFFD97706),
                            ),
                          ),
                          title: Text(
                            name,
                            style: const TextStyle(
                              fontFamily: _font,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: Text(
                            '${people.length} persona(s) · Detectado en el personal, pendiente de agregar al catálogo',
                          ),
                          trailing: FilledButton.tonalIcon(
                            onPressed: () => _editDetected(name),
                            icon: const Icon(Icons.add_business_outlined),
                            label: const Text('Agregar'),
                          ),
                        ),
                      );
                    }
                    final doc = rows[index];
                    final data = doc.data();
                    final enabled = data['enabled'] != false;
                    final name = _text(data['nombre']);
                    final people = _peopleFor(doc.id, name);
                    return Card(
                      child: ListTile(
                        onTap: () => _showPeople(name, people),
                        leading: CircleAvatar(
                          backgroundColor: enabled
                              ? _accent.withValues(alpha: .14)
                              : const Color(0xFFE2E8F0),
                          child: Icon(
                            Icons.account_tree_outlined,
                            color: enabled ? _accent : const Color(0xFF64748B),
                          ),
                        ),
                        title: Text(
                          (data['nombre'] ?? 'Sin nombre').toString(),
                          style: const TextStyle(
                            fontFamily: _font,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: Text(
                          '${data['codigo'] ?? 'Sin código'} · ${enabled ? 'Activo' : 'Inactivo'} · ${people.length} persona(s)',
                        ),
                        trailing: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Switch(
                              value: enabled,
                              onChanged: (value) => _toggle(doc, value),
                            ),
                            IconButton(
                              onPressed: () => _edit(doc),
                              icon: const Icon(Icons.edit_outlined),
                              tooltip: 'Editar',
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        );
      },
    ),
  );
}

class _CentroPerson {
  const _CentroPerson({
    required this.id,
    required this.name,
    required this.role,
    required this.area,
    required this.center,
    required this.centerId,
  });

  final String id;
  final String name;
  final String role;
  final String area;
  final String center;
  final String centerId;
}
