// lib/talento_humano/organizational_structure_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import '../widgets/internal_module_layout.dart';

const String _areasCollection   = 'TBL_AREAS';
const String _cargosCollection  = 'TBL_CARGOS';
const String _orgCollection     = 'TBL_ESTRUCTURA_ORGANIZACIONAL';
const String _hojaCollection    = 'TBL_USUARIOS';
const String _ccCollection      = 'TBL_CENTROS_COSTOS';
const Color  _kPrimaryColor     = Color(0xffc28942);
const String _kFontFamily       = 'Arial';

class OrganizationalStructureScreen extends StatefulWidget {
  final String userId;
  final String empresaId;
  const OrganizationalStructureScreen({Key? key, required this.userId, required this.empresaId}) : super(key: key);

  @override
  State<OrganizationalStructureScreen> createState() =>
      _OrganizationalStructureScreenState();
}

class _OrganizationalStructureScreenState
    extends State<OrganizationalStructureScreen> {
  final _searchCtrl      = TextEditingController();
  final _areaFilterCtrl  = TextEditingController();
  final _cargoFilterCtrl = TextEditingController();

  String? _filterArea;
  String? _filterCargo;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _areaFilterCtrl.dispose();
    _cargoFilterCtrl.dispose();
    super.dispose();
  }

  Future<List<String>> _fetchAreas(String pattern) async {
    final snap = await FirebaseFirestore.instance
        .collection(_areasCollection)
        .get();
    return snap.docs
        .map((d) => d.data()['descripcion'] as String? ?? '')
        .where((a) => a.toLowerCase().contains(pattern.toLowerCase()))
        .toList();
  }

  Future<List<Map<String, String>>> _fetchCargos(String pattern) async {
    final snap = await FirebaseFirestore.instance
        .collection(_cargosCollection)
        .get();
    return snap.docs.map((d) {
      final data = d.data();
      return {
        'code': d.id,
        'desc': data['descripcion'] as String? ?? '',
      };
    }).where((m) =>
        m['desc']!.toLowerCase().contains(pattern.toLowerCase())
    ).toList();
  }

  Future<List<Map<String, String>>> _fetchCostCenters(int grupo, String pattern) async {
    final snap = await FirebaseFirestore.instance
        .collection(_ccCollection)
        .where('grupo', isEqualTo: grupo)
        .get();
    return snap.docs.map((d) {
      final data = d.data();
      return {
        'code': d.id,
        'nombre': data['nombre'] as String? ?? '',
      };
    }).where((m) =>
        m['nombre']!.toLowerCase().contains(pattern.toLowerCase())
    ).toList();
  }

  Future<void> _openForm({DocumentSnapshot<Map<String, dynamic>>? doc}) async {
    final isNew = doc == null;
    final data  = doc?.data() ?? {};

    // Valores iniciales
    final initialId           = doc?.id ?? '';
    final initialName         = data['nombre']         as String? ?? '';
    final initialArea         = data['area']           as String? ?? '';
    final initialCargo        = data['cargo']          as String? ?? '';
    final initialBossCode     = data['jefe_cargo']     as String? ?? '';
    String initialBossDesc    = data['jefe_cargo_desc'] as String? ?? '';
    if (!isNew && initialBossCode.isNotEmpty) {
      final bSnap = await FirebaseFirestore.instance
          .collection(_cargosCollection)
          .doc(initialBossCode)
          .get();
      initialBossDesc =
          bSnap.data()?['descripcion'] as String? ?? initialBossDesc;
    }
    final initialBossName     = data['jefe_directo']    as String? ?? '';
    final initialBossDirectId = data['jefe_directo_id'] as String? ?? '';
    final initialMail         = data['correo']          as String? ?? '';
    final initialRole         = data['rol']             as String? ?? '';

    // Centro de costos
    final initialGrupo        = data['centro_grupo']    as int?;
    final initialCentroCode   = data['centro_codigo']   as String? ?? '';
    final initialCentroName   = data['centro_nombre']   as String? ?? '';

    // Controllers
    final ctrId        = TextEditingController(text: initialId);
    final ctrName      = TextEditingController(text: initialName);
    final ctrArea      = TextEditingController(text: initialArea);
    final ctrCargo     = TextEditingController(text: initialCargo);
    final ctrBossCargo = TextEditingController(text: initialBossDesc);
    final ctrBossName  = TextEditingController(text: initialBossName);
    final ctrMail      = TextEditingController(text: initialMail);
    final ctrRole      = TextEditingController(text: initialRole);
    final ctrCentro    = TextEditingController(text: initialCentroName);

    int?    selectedGrupo     = initialGrupo;
    String  selectedBossCode  = initialBossCode;
    String  selectedBossDirectId = initialBossDirectId;
    String? selectedCentroCode = initialCentroCode;

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: Text(
            isNew ? 'Crear registro' : 'Editar registro',
            style: const TextStyle(
              fontFamily: _kFontFamily,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(children: [
              // Identificación
              TextField(
                controller: ctrId,
                decoration: const InputDecoration(labelText: 'Identificación'),
                readOnly: !isNew,
              ),
              const SizedBox(height: 8),
              // Nombre completo
              TextField(
                controller: ctrName,
                decoration: const InputDecoration(labelText: 'Nombre completo'),
              ),
              const SizedBox(height: 8),
              // Área
              TypeAheadField<String>(
                textFieldConfiguration: TextFieldConfiguration(
                  controller: ctrArea,
                  decoration: const InputDecoration(labelText: 'Área'),
                ),
                suggestionsCallback: _fetchAreas,
                itemBuilder: (_, a) => ListTile(title: Text(a)),
                onSuggestionSelected: (a) {
                  setStateDialog(() {
                    ctrArea.text = a;
                    // al cambiar área, reset cargo/jefes/centros
                    ctrCargo.clear();
                    ctrBossCargo.clear();
                    ctrBossName.clear();
                    ctrCentro.clear();
                    selectedBossCode = '';
                    selectedBossDirectId = '';
                    selectedGrupo = null;
                    selectedCentroCode = null;
                  });
                },
                minCharsForSuggestions: 0,
              ),
              const SizedBox(height: 8),
              // Cargo
              TypeAheadField<Map<String, String>>(
                textFieldConfiguration: TextFieldConfiguration(
                  controller: ctrCargo,
                  decoration: const InputDecoration(labelText: 'Cargo'),
                ),
                suggestionsCallback: _fetchCargos,
                itemBuilder: (_, m) => ListTile(title: Text(m['desc']!)),
                onSuggestionSelected: (m) {
                  setStateDialog(() {
                    ctrCargo.text = m['desc']!;
                    // al cambiar cargo, reset jefes/centros
                    ctrBossCargo.clear();
                    ctrBossName.clear();
                    ctrCentro.clear();
                    selectedBossCode = m['code']!;
                    selectedBossDirectId = '';
                    selectedGrupo = null;
                    selectedCentroCode = null;
                  });
                },
                minCharsForSuggestions: 0,
              ),
              const SizedBox(height: 8),
              // Cargo del jefe directo
              TypeAheadField<Map<String, String>>(
                textFieldConfiguration: TextFieldConfiguration(
                  controller: ctrBossCargo,
                  decoration: const InputDecoration(labelText: 'Cargo del jefe directo'),
                ),
                suggestionsCallback: _fetchCargos,
                itemBuilder: (_, m) => ListTile(title: Text(m['desc']!)),
                onSuggestionSelected: (m) async {
                  final code = m['code']!;
                  final snap = await FirebaseFirestore.instance
                      .collection(_cargosCollection)
                      .doc(code)
                      .get();
                  final desc = snap.data()?['descripcion'] as String? ?? m['desc']!;
                  setStateDialog(() {
                    ctrBossCargo.text = desc;
                    ctrBossName.clear();
                    selectedBossCode = code;
                    selectedBossDirectId = '';
                  });
                },
                minCharsForSuggestions: 0,
              ),
              const SizedBox(height: 8),
              // Jefe directo
              TypeAheadField<Map<String, String>>(
                textFieldConfiguration: TextFieldConfiguration(
                  controller: ctrBossName,
                  decoration: const InputDecoration(labelText: 'Jefe directo'),
                ),
                suggestionsCallback: (pattern) async {
                  if (selectedBossCode.isEmpty) return [];
                  final doc = await FirebaseFirestore.instance
                      .collection(_cargosCollection)
                      .doc(selectedBossCode)
                      .get();
                  final names = List<String>.from(doc.data()?['assigned_users_names'] ?? []);
                  final ids   = List<String>.from(doc.data()?['assigned_users_ids']   ?? []);
                  final results = <Map<String, String>>[];
                  for (var i = 0; i < names.length; i++) {
                    if (names[i].toLowerCase().contains(pattern.toLowerCase())) {
                      results.add({'id': ids.elementAt(i), 'nombre': names[i]});
                    }
                  }
                  return results;
                },
                itemBuilder: (_, m) => ListTile(
                  title: Text(m['nombre']!),
                  subtitle: Text('ID: ${m['id']!}'),
                ),
                onSuggestionSelected: (m) {
                  setStateDialog(() {
                    ctrBossName.text = m['nombre']!;
                    selectedBossDirectId = m['id']!;
                  });
                },
                minCharsForSuggestions: 0,
              ),
              const SizedBox(height: 8),
              // Correo
              TextField(
                controller: ctrMail,
                decoration: const InputDecoration(labelText: 'Correo electrónico'),
              ),
              const SizedBox(height: 8),
              // Rol
              TextField(
                controller: ctrRole,
                decoration: const InputDecoration(labelText: 'Rol en la organización'),
              ),
              const SizedBox(height: 16),
              // — Centro de Costos: Grupo —
              DropdownButtonFormField<int>(
                decoration: const InputDecoration(labelText: 'Grupo centro de costos'),
                isExpanded: true,
                value: selectedGrupo,
                items: [6, 7].map((g) => DropdownMenuItem(
                  value: g,
                  child: Text('Grupo $g'),
                )).toList(),
                onChanged: (g) => setStateDialog(() {
                  selectedGrupo = g;
                  // reset centro
                  selectedCentroCode = null;
                  ctrCentro.clear();
                }),
                validator: (_) => selectedGrupo == null
                    ? 'Selecciona un grupo'
                    : null,
              ),
              const SizedBox(height: 8),
              // — Centro de Costos: Establecimiento —
              TypeAheadFormField<Map<String, String>>(
                textFieldConfiguration: TextFieldConfiguration(
                  controller: ctrCentro,
                  decoration: const InputDecoration(labelText: 'Centro de costos'),
                ),
                suggestionsCallback: (p) => (selectedGrupo == null)
                    ? []
                    : _fetchCostCenters(selectedGrupo!, p),
                itemBuilder: (_, m) => ListTile(title: Text(m['nombre']!)),
                onSuggestionSelected: (m) {
                  setStateDialog(() {
                    ctrCentro.text = m['nombre']!;
                    selectedCentroCode = m['code']!;
                  });
                },
                minCharsForSuggestions: 0,
                validator: (_) => selectedCentroCode == null
                    ? 'Selecciona un centro'
                    : null,
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
                final id  = ctrId.text.trim();
                if (ctrId.text.isEmpty) return;
                final docRef = FirebaseFirestore.instance.collection(_orgCollection).doc(id);

                final payload = {
                  'nombre'           : ctrName.text.trim(),
                  'area'             : ctrArea.text.trim(),
                  'cargo'            : ctrCargo.text.trim(),
                  'jefe_cargo'       : selectedBossCode,
                  'jefe_cargo_desc'  : ctrBossCargo.text.trim(),
                  'jefe_directo'     : ctrBossName.text.trim(),
                  'jefe_directo_id'  : selectedBossDirectId,
                  'correo'           : ctrMail.text.trim(),
                  'rol'              : ctrRole.text.trim(),
                  'centro_grupo'     : selectedGrupo,
                  'centro_codigo'    : selectedCentroCode,
                  'centro_nombre'    : ctrCentro.text.trim(),
                };

                if (isNew) await docRef.set(payload);
                else       await docRef.update(payload);

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

  Future<void> _deleteEmployee(String id) async {
    await FirebaseFirestore.instance.collection(_orgCollection).doc(id).delete();
  }

  @override
  Widget build(BuildContext context) {
    return InternalModuleLayout(
      userId: widget.userId,
      empresaId: widget.empresaId,
      title: 'Estructura Organizacional',
      subtitle: 'Configuración de jerarquías y dependencias',
      accentColor: _kPrimaryColor,
      headerActions: [
        IconButton(
          icon: const Icon(Icons.add_circle_outline_rounded, size: 28),
          onPressed: () => _openForm(),
          tooltip: 'Agregar Colaborador',
          color: _kPrimaryColor,
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            const SizedBox(height: 16),
            // filtros de área y cargo
            Row(
              children: [
                Expanded(
                  child: TypeAheadField<String>(
                    textFieldConfiguration: TextFieldConfiguration(
                      controller: _areaFilterCtrl,
                      decoration: const InputDecoration(labelText: 'Filtrar por Área'),
                    ),
                    suggestionsCallback: _fetchAreas,
                    itemBuilder: (_, a) => ListTile(title: Text(a)),
                    onSuggestionSelected: (a) => setState(() {
                      _filterArea = a;
                      _areaFilterCtrl.text = a;
                      _filterCargo = null;
                      _cargoFilterCtrl.clear();
                    }),
                    minCharsForSuggestions: 0,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TypeAheadField<String>(
                    textFieldConfiguration: TextFieldConfiguration(
                      controller: _cargoFilterCtrl,
                      decoration: const InputDecoration(labelText: 'Filtrar por Cargo'),
                    ),
                    suggestionsCallback: (p) async =>
                        (await _fetchCargos(p)).map((m) => m['desc']!).toList(),
                    itemBuilder: (_, d) => ListTile(title: Text(d)),
                    onSuggestionSelected: (d) => setState(() {
                      _filterCargo = d;
                      _cargoFilterCtrl.text = d;
                    }),
                    minCharsForSuggestions: 0,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // búsqueda libre
            TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                labelText: 'Buscar por nombre o ID',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),

            // listado con foto en tarjetas
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection(_orgCollection)
                    .snapshots(),
                builder: (ctx, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final term = _searchCtrl.text.trim().toLowerCase();
                  final docs = snap.data!.docs.where((d) {
                    final m = d.data();
                    if (_filterArea != null && m['area'] != _filterArea) return false;
                    if (_filterCargo != null && m['cargo'] != _filterCargo) return false;
                    if (term.isNotEmpty) {
                      final n = (m['nombre'] as String? ?? '').toLowerCase();
                      final i = d.id.toLowerCase();
                      return n.contains(term) || i.contains(term);
                    }
                    return true;
                  }).toList();

                  if (docs.isEmpty) {
                    return const Center(child: Text('No se encontraron registros.'));
                  }

                  return ListView.separated(
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (c, i) {
                      final d = docs[i];
                      final m = d.data();
                      final cedula = d.id;
                      final nombre = m['nombre'] as String? ?? '';
                      final cargo = m['cargo'] as String? ?? '';
                      final area = m['area'] as String? ?? '';

                      return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                        future: FirebaseFirestore.instance
                            .collection(_hojaCollection)
                            .doc(cedula)
                            .get(),
                        builder: (ctxH, snapH) {
                          String photoUrl = '';
                          if (snapH.connectionState == ConnectionState.done &&
                              snapH.hasData &&
                              snapH.data!.exists) {
                            final pd = snapH.data!.data()!;
                            photoUrl = (pd['fotoUrl'] as String?)?.isNotEmpty == true
                                ? pd['fotoUrl'] as String
                                : (pd['cedulaDocUrl'] as String? ?? '');
                          }

                          return ModuleCard(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                // avatar
                                ClipOval(
                                  child: photoUrl.isNotEmpty
                                      ? Image.network(
                                          photoUrl,
                                          width: 56,
                                          height: 56,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => const Icon(
                                            Icons.person,
                                            size: 40,
                                            color: _kPrimaryColor,
                                          ),
                                        )
                                      : const Icon(Icons.person,
                                          size: 40, color: _kPrimaryColor),
                                ),
                                const SizedBox(width: 16),
                                // datos
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        nombre,
                                        style: const TextStyle(
                                          fontFamily: _kFontFamily,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF0F172A),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'ID: $cedula · $cargo',
                                        style: const TextStyle(
                                          fontFamily: _kFontFamily,
                                          fontSize: 12,
                                          color: Color(0xFF64748B),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Área: $area',
                                        style: const TextStyle(
                                          fontFamily: _kFontFamily,
                                          fontSize: 12,
                                          color: Color(0xFF64748B),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Superior: ${m['jefe_cargo_desc'] ?? '—'}\n'
                                        'Centro: ${m['centro_nombre'] ?? '—'}',
                                        style: const TextStyle(
                                          fontFamily: _kFontFamily,
                                          fontSize: 11,
                                          color: Color(0xFF94A3B8),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // acciones
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit_note_rounded,
                                          color: _kPrimaryColor),
                                      onPressed: () => _openForm(doc: d),
                                      tooltip: 'Editar',
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline_rounded,
                                          color: Colors.redAccent),
                                      onPressed: () async {
                                        final ok = await showDialog<bool>(
                                          context: context,
                                          builder: (_) => AlertDialog(
                                            title: const Text('Confirmar borrado'),
                                            content: Text(
                                                '¿Eliminar registro de "$nombre"?'),
                                            actions: [
                                              TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(context, false),
                                                  child: const Text('Cancelar')),
                                              ElevatedButton(
                                                style: ElevatedButton.styleFrom(
                                                    backgroundColor: Colors.red),
                                                onPressed: () =>
                                                    Navigator.pop(context, true),
                                                child: const Text('Eliminar'),
                                              ),
                                            ],
                                          ),
                                        );
                                        if (ok == true) {
                                          await _deleteEmployee(cedula);
                                        }
                                      },
                                      tooltip: 'Eliminar',
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
