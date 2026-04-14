// lib/talento_humano/cargos_management_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import '../widgets/internal_module_layout.dart';

const String _areasCollection  = 'TBL_AREAS';
const String _cargosCollection = 'TBL_CARGOS';
const String _orgCollection    = 'TBL_ESTRUCTURA_ORGANIZACIONAL';
const Color  _kPrimaryColor    = Color(0xffc28942);
const String _kFontFamily      = 'Arial';

class CargosManagementScreen extends StatefulWidget {
  final String userId;
  final String empresaId;
  const CargosManagementScreen({Key? key, required this.userId, required this.empresaId}) : super(key: key);

  @override
  State<CargosManagementScreen> createState() => _CargosManagementScreenState();
}

class _CargosManagementScreenState extends State<CargosManagementScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<List<String>> _fetchAreasList() async {
    final snap = await FirebaseFirestore.instance.collection(_areasCollection).get();
    return snap.docs
        .map((d) => d.data()['descripcion'] as String? ?? '')
        .where((s) => s.isNotEmpty)
        .toList();
  }

  Future<List<Map<String,String>>> _fetchCargos(String pattern) async {
    final snap = await FirebaseFirestore.instance.collection(_cargosCollection).get();
    return snap.docs.map((d) {
      final data = d.data();
      return {
        'code': d.id,
        'desc': data['descripcion'] as String? ?? '',
        'area': data['area'] as String? ?? '',
      };
    }).where((m) =>
        m['desc']!.toLowerCase().contains(pattern.toLowerCase())
    ).toList();
  }

  /// Actualiza todos los cargos: assigned_users_* y subordinates_*.
  Future<void> _updateAllCargos() async {
    final col = FirebaseFirestore.instance.collection(_cargosCollection);
    final cargosSnap = await col.get();

    for (final doc in cargosSnap.docs) {
      final cargoData = doc.data();
      final desc = cargoData['descripcion'] as String? ?? '';

      // 1) Usuarios asignados en estructura (campo 'cargo' == desc)
      final asignSnap = await FirebaseFirestore.instance
          .collection(_orgCollection)
          .where('cargo', isEqualTo: desc)
          .get();
      final assignedIds = asignSnap.docs
          .map((d) => d.data()['identificacion'] as String? ?? '')
          .toList();
      final assignedNames = asignSnap.docs
          .map((d) => d.data()['nombre'] as String? ?? '')
          .toList();

      // 2) Subordinados (campo 'jefe_cargo_desc' == desc)
      final subSnap = await FirebaseFirestore.instance
          .collection(_orgCollection)
          .where('jefe_cargo_desc', isEqualTo: desc)
          .get();
      final subIds = subSnap.docs
          .map((d) => d.data()['identificacion'] as String? ?? '')
          .toList();
      final subNames = subSnap.docs
          .map((d) => d.data()['nombre'] as String? ?? '')
          .toList();

      // 3) Actualizar documento de cargo
      await col.doc(doc.id).update({
        'assigned_users_ids'  : assignedIds,
        'assigned_users_names': assignedNames,
        'subordinates_ids'    : subIds,
        'subordinates_names'  : subNames,
      });
    }
  }

  void _openCargoForm({DocumentSnapshot<Map<String,dynamic>>? doc}) {
    final isNew = doc == null;
    final data  = doc?.data() ?? {};

    final ctrCode       = TextEditingController(text: doc?.id ?? '');
    final ctrDesc       = TextEditingController(text: data['descripcion'] as String? ?? '');
    final ctrArea       = TextEditingController(text: data['area'] as String? ?? '');
    final ctrParentDesc = TextEditingController(text: data['parent_desc'] as String? ?? '');

    String _selectedParentCode = data['parent_cargo'] as String? ?? '';

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: Text(
            isNew ? 'Crear Cargo' : 'Editar Cargo',
            style: const TextStyle(fontFamily: _kFontFamily, fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(children: [
              TextField(
                controller: ctrCode,
                decoration: const InputDecoration(labelText: 'Código de cargo'),
                readOnly: !isNew,
              ),
              const SizedBox(height: 8),

              TextField(
                controller: ctrDesc,
                decoration: const InputDecoration(labelText: 'Descripción'),
              ),
              const SizedBox(height: 8),

              // Dropdown de áreas:
              FutureBuilder<List<String>>(
                future: _fetchAreasList(),
                builder: (ctx2, snapAreas) {
                  if (!snapAreas.hasData) return const Center(child: CircularProgressIndicator());
                  final areas = snapAreas.data!;
                  return DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: 'Área'),
                    isExpanded: true,
                    value: ctrArea.text.isNotEmpty ? ctrArea.text : null,
                    items: areas.map((a) => DropdownMenuItem(
                      value: a,
                      child: Text(a),
                    )).toList(),
                    onChanged: (val) => setStateDialog(() => ctrArea.text = val!),
                  );
                },
              ),
              const SizedBox(height: 8),

              // Cargo padre opcional con TypeAhead
              TypeAheadField<Map<String,String>>(
                textFieldConfiguration: TextFieldConfiguration(
                  controller: ctrParentDesc,
                  decoration: const InputDecoration(labelText: 'Cargo padre (opcional)'),
                ),
                suggestionsCallback: _fetchCargos,
                itemBuilder: (_, m) => ListTile(
                  title: Text(m['desc']!),
                  subtitle: Text('Área: ${m['area']}'),
                ),
                onSuggestionSelected: (m) {
                  setStateDialog(() {
                    _selectedParentCode = m['code']!;
                    ctrParentDesc.text  = m['desc']!;
                  });
                },
                minCharsForSuggestions: 0,
              ),
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar', style: TextStyle(fontFamily: _kFontFamily)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _kPrimaryColor),
              onPressed: () async {
                final code = ctrCode.text.trim();
                final desc = ctrDesc.text.trim();
                final area = ctrArea.text.trim();
                if (code.isEmpty || desc.isEmpty || area.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Todos los campos son obligatorios')),
                  );
                  return;
                }

                final payload = {
                  'descripcion':  desc,
                  'area':         area,
                  'parent_cargo': _selectedParentCode.isEmpty ? null : _selectedParentCode,
                  'parent_desc':  ctrParentDesc.text.trim().isEmpty ? null : ctrParentDesc.text.trim(),
                };
                final col = FirebaseFirestore.instance.collection(_cargosCollection);
                if (isNew) {
                  await col.doc(code).set(payload);
                } else {
                  await col.doc(code).update(payload);
                }

                // Reinvoque _updateAllCargos para sincronizar subcargos
                await _updateAllCargos();

                Navigator.pop(context);
              },
              child: Text(isNew ? 'Crear' : 'Guardar',
                  style: const TextStyle(fontFamily: _kFontFamily)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteCargo(String code) async {
    await FirebaseFirestore.instance.collection(_cargosCollection).doc(code).delete();
  }

  @override
  Widget build(BuildContext context) {
    return InternalModuleLayout(
      userId: widget.userId,
      empresaId: widget.empresaId,
      title: 'Gestión de Cargos',
      subtitle: 'Definición de responsabilidades y perfiles de puesto',
      accentColor: _kPrimaryColor,
      headerActions: [
        IconButton(
          icon: const Icon(Icons.sync_rounded, color: Color(0xFF64748B)),
          tooltip: 'Sincronizar Estructura',
          onPressed: () async {
            final snack = ScaffoldMessenger.of(context);
            snack.showSnackBar(
              const SnackBar(content: Text('Sincronizando cargos con la estructura...')),
            );
            await _updateAllCargos();
            snack.showSnackBar(
              const SnackBar(content: Text('Cargos actualizados correctamente')),
            );
            setState(() {});
          },
        ),
        IconButton(
          icon: const Icon(Icons.add_circle_outline_rounded, size: 28, color: _kPrimaryColor),
          onPressed: () => _openCargoForm(),
          tooltip: 'Nuevo Cargo',
        ),
      ],
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
            child: TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                labelText: 'Buscar por descripción o área',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance.collection(_cargosCollection).snapshots(),
              builder: (ctx, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final term = _searchCtrl.text.trim().toLowerCase();
                final docs = snap.data!.docs.where((d) {
                  final m = d.data();
                  final desc = (m['descripcion'] as String? ?? '').toLowerCase();
                  final area = (m['area'] as String? ?? '').toLowerCase();
                  return desc.contains(term) || area.contains(term);
                }).toList();

                if (docs.isEmpty) {
                  return const Center(child: Text('No se encontraron cargos.'));
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(24),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (c, i) {
                    final d = docs[i];
                    final m = d.data();
                    final code = d.id;
                    final desc = m['descripcion'] as String? ?? '';
                    final area = m['area'] as String? ?? '';

                    return ModuleCard(
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: _kPrimaryColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.badge_outlined, color: _kPrimaryColor, size: 20),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  desc,
                                  style: const TextStyle(
                                    fontFamily: _kFontFamily,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                                Text(
                                  'Área: $area',
                                  style: const TextStyle(
                                    fontFamily: _kFontFamily,
                                    fontSize: 13,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                                if (m['parent_desc'] != null)
                                  Text(
                                    'Reporta a: ${m['parent_desc']}',
                                    style: const TextStyle(
                                      fontFamily: _kFontFamily,
                                      fontSize: 11,
                                      color: Color(0xFF94A3B8),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.group_outlined, color: Color(0xFF64748B)),
                            onPressed: () => _showUsersDialog(code),
                            tooltip: 'Ver ocupantes',
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, color: Color(0xFF64748B)),
                            onPressed: () => _openCargoForm(doc: d),
                            tooltip: 'Editar',
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                            onPressed: () async {
                              final ok = await showDialog<bool>(
                                context: context,
                                builder: (_) => AlertDialog(
                                  title: const Text('Confirmar borrado'),
                                  content: Text('¿Borrar cargo "$desc"?'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context, false),
                                      child: const Text('Cancelar'),
                                    ),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                      onPressed: () => Navigator.pop(context, true),
                                      child: const Text('Borrar'),
                                    ),
                                  ],
                                ),
                              );
                              if (ok == true) await _deleteCargo(code);
                            },
                            tooltip: 'Eliminar',
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Igual al código previo: muestra dropdown de usuarios y sus subalternos.
  Future<void> _showUsersDialog(String cargoCode) async {
    final cargoSnap = await FirebaseFirestore.instance
        .collection(_cargosCollection)
        .doc(cargoCode)
        .get();
    final cargoDesc = cargoSnap.data()?['descripcion'] as String? ?? cargoCode;

    final asignSnap = await FirebaseFirestore.instance
        .collection(_orgCollection)
        .where('cargo', isEqualTo: cargoDesc)
        .get();
    final asignados = asignSnap.docs.map((d) {
      final md = d.data();
      return {
        'nombre': md['nombre'] as String? ?? '',
        'id'    : md['identificacion'] as String? ?? '',
      };
    }).toList();

    String? selectedName;
    List<Map<String,String>> subordinates = [];

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: Text('Usuarios para cargo “$cargoDesc”'),
          content: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Asignados al cargo'),
                isExpanded: true,
                value: selectedName,
                items: asignados.map((u) => DropdownMenuItem(
                  value: u['nombre'],
                  child: Text(u['nombre']!),
                )).toList(),
                onChanged: (val) async {
                  setStateDialog(() {
                    selectedName = val;
                    subordinates.clear();
                  });
                  if (val != null) {
                    final subSnap = await FirebaseFirestore.instance
                        .collection(_orgCollection)
                        .where('jefe_directo', isEqualTo: val)
                        .get();
                    final subs = subSnap.docs.map((d) {
                      final md = d.data();
                      return {
                        'nombre': md['nombre'] as String? ?? '',
                        'id'    : md['identificacion'] as String? ?? '',
                      };
                    }).toList();
                    setStateDialog(() => subordinates = subs);
                  }
                },
              ),
              const SizedBox(height: 16),
              const Text('Personas a cargo:', style: TextStyle(fontWeight: FontWeight.bold)),
              if (selectedName == null)
                const Text('Seleccione un usuario.')
              else if (subordinates.isEmpty)
                const Text('— Ninguna persona asignada —')
              else
                for (var u in subordinates) Text('${u['nombre']} (${u['id']})'),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
          ],
        ),
      ),
    );
  }
}
