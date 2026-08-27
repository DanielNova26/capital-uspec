// lib/talento_humano/cargos_management_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import '../core/hierarchy_order.dart';
import '../utils/user_company.dart';
import '../widgets/internal_module_layout.dart';
import '../widgets/user_avatar.dart';

const String _areasCollection = 'TBL_AREAS';
const String _cargosCollection = 'TBL_CARGOS';
const String _orgCollection = 'TBL_ESTRUCTURA_ORGANIZACIONAL';
const Color _kPrimaryColor = Color(0xffc28942);
const String _kFontFamily = 'Arial';

class CargosManagementScreen extends StatefulWidget {
  final String userId;
  final String empresaId;
  const CargosManagementScreen({
    Key? key,
    required this.userId,
    required this.empresaId,
  }) : super(key: key);

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

  Future<List<Map<String, String>>> _fetchAreasList() async {
    final snap = await FirebaseFirestore.instance
        .collection(_areasCollection)
        .where('empresaId', isEqualTo: widget.empresaId)
        .get();
    final list =
        snap.docs
            .map(
              (d) => {
                'areaId':
                    (d.data()['areaId'] as String?)?.trim().isNotEmpty == true
                    ? (d.data()['areaId'] as String).trim()
                    : d.id,
                'nombre': (d.data()['nombre'] as String?)?.trim() ?? '',
                'descripcion':
                    (d.data()['descripcion'] as String?)?.trim() ?? '',
              },
            )
            .where((m) => m['nombre']!.isNotEmpty)
            .toList()
          ..sort((a, b) => a['nombre']!.compareTo(b['nombre']!));
    return list;
  }

  /// Convierte un nombre en slug de código: {empresaId}_{slug}
  String _slugCode(String nombre) {
    final slug = nombre
        .toLowerCase()
        .replaceAll(RegExp(r'[áàâãä]'), 'a')
        .replaceAll(RegExp(r'[éèêë]'), 'e')
        .replaceAll(RegExp(r'[íìîï]'), 'i')
        .replaceAll(RegExp(r'[óòôõö]'), 'o')
        .replaceAll(RegExp(r'[úùûü]'), 'u')
        .replaceAll('ñ', 'n')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return '${widget.empresaId}_$slug';
  }

  /// Nombre de display del cargo: prefiere `nombre` (título corto),
  /// cae a `descripcion` para registros creados antes de la normalización.
  String _cargoNombre(Map<String, dynamic> data) {
    final n = (data['nombre'] as String?)?.trim() ?? '';
    if (n.isNotEmpty) return n;
    final d = (data['descripcion'] as String?)?.trim() ?? '';
    return d.isNotEmpty ? d : '(sin nombre)';
  }

  bool _cargoMatches(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    String term,
  ) {
    if (term.isEmpty) return true;
    final data = doc.data();
    final haystack = [
      doc.id,
      data['cargoId'],
      data['nombre'],
      data['descripcion'],
      data['area'],
      data['areaNombre'],
      data['parent_desc'],
    ].whereType<Object>().join(' ').toLowerCase();
    return haystack.contains(term);
  }

  Future<List<Map<String, String>>> _fetchCargos(String pattern) async {
    final snap = await FirebaseFirestore.instance
        .collection(_cargosCollection)
        .where('empresaId', isEqualTo: widget.empresaId)
        .get();
    final term = pattern.toLowerCase();
    return snap.docs
        .map((d) {
          final data = d.data();
          return {
            'code': d.id,
            'desc': _cargoNombre(data),
            'area': data['area'] as String? ?? '',
          };
        })
        .where(
          (m) =>
              m['desc']!.toLowerCase().contains(term) ||
              m['area']!.toLowerCase().contains(term),
        )
        .toList();
  }

  Future<int> _nextHierarchyOrder(String parentCargo) async {
    final snap = await FirebaseFirestore.instance
        .collection(_cargosCollection)
        .where('empresaId', isEqualTo: widget.empresaId)
        .get();
    var maxOrder = 0;
    for (final doc in snap.docs) {
      final data = doc.data();
      final parent = (data['parent_cargo'] ?? '').toString().trim();
      if (parent != parentCargo.trim()) continue;
      final order = hierarchyOrderOf(data);
      if (order < 1000000 && order > maxOrder) maxOrder = order;
    }
    return maxOrder + 100;
  }

  Future<void> _openHierarchyOrderPanel() async {
    final snap = await FirebaseFirestore.instance
        .collection(_cargosCollection)
        .where('empresaId', isEqualTo: widget.empresaId)
        .get();
    if (!mounted) return;

    final cargos = <String, Map<String, dynamic>>{
      for (final d in snap.docs)
        d.id: <String, dynamic>{'id': d.id, ...d.data()},
    };
    final initialIndex = CargoHierarchyIndex.fromCargos(cargos.values);
    final parentOf = <String, String>{};
    final siblings = <String, List<String>>{};
    for (final entry in cargos.entries) {
      final rawParent = (entry.value['parent_cargo'] ?? '').toString().trim();
      final parent = rawParent != entry.key && cargos.containsKey(rawParent)
          ? rawParent
          : '';
      parentOf[entry.key] = parent;
      siblings.putIfAbsent(parent, () => []).add(entry.key);
    }
    for (final group in siblings.values) {
      group.sort((a, b) => initialIndex.compareCargos(cargos[a]!, cargos[b]!));
    }

    List<MapEntry<String, int>> visibleRows() {
      final rows = <MapEntry<String, int>>[];
      final visited = <String>{};
      void append(String id, int depth) {
        if (!visited.add(id)) return;
        rows.add(MapEntry(id, depth));
        for (final child in siblings[id] ?? const <String>[]) {
          append(child, depth + 1);
        }
      }

      for (final root in siblings[''] ?? const <String>[]) {
        append(root, 0);
      }
      for (final id in cargos.keys.where((id) => !visited.contains(id))) {
        append(id, 0);
      }
      return rows;
    }

    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final rows = visibleRows();
          final width = (MediaQuery.of(dialogContext).size.width - 48)
              .clamp(320.0, 760.0)
              .toDouble();
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.account_tree_outlined, color: _kPrimaryColor),
                SizedBox(width: 12),
                Expanded(child: Text('Orden jerárquico de cargos')),
              ],
            ),
            content: SizedBox(
              width: width,
              height: (MediaQuery.of(dialogContext).size.height * 0.65).clamp(
                320.0,
                620.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '“Reporta a” define el nivel. Usa las flechas para ordenar '
                    'los cargos que tienen el mismo superior.',
                    style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.separated(
                      itemCount: rows.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, index) {
                        final row = rows[index];
                        final id = row.key;
                        final depth = row.value;
                        final cargo = cargos[id]!;
                        final parent = parentOf[id] ?? '';
                        final group = siblings[parent] ?? const <String>[];
                        final siblingIndex = group.indexOf(id);
                        final parentName = parent.isEmpty
                            ? 'Nivel superior'
                            : _cargoNombre(cargos[parent]!);
                        return Padding(
                          padding: EdgeInsets.only(left: depth * 22.0),
                          child: ListTile(
                            dense: true,
                            leading: CircleAvatar(
                              radius: 15,
                              backgroundColor: _kPrimaryColor.withValues(alpha: 0.12),
                              child: Text(
                                '${depth + 1}',
                                style: const TextStyle(
                                  color: _kPrimaryColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            title: Text(
                              _cargoNombre(cargo),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              '$parentName · ${cargo['area'] ?? ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Subir',
                                  icon: const Icon(Icons.arrow_upward_rounded),
                                  onPressed: siblingIndex <= 0
                                      ? null
                                      : () => setDialogState(() {
                                          final mutable = siblings[parent]!;
                                          final previous =
                                              mutable[siblingIndex - 1];
                                          mutable[siblingIndex - 1] = id;
                                          mutable[siblingIndex] = previous;
                                        }),
                                ),
                                IconButton(
                                  tooltip: 'Bajar',
                                  icon: const Icon(
                                    Icons.arrow_downward_rounded,
                                  ),
                                  onPressed:
                                      siblingIndex < 0 ||
                                          siblingIndex >= group.length - 1
                                      ? null
                                      : () => setDialogState(() {
                                          final mutable = siblings[parent]!;
                                          final next =
                                              mutable[siblingIndex + 1];
                                          mutable[siblingIndex + 1] = id;
                                          mutable[siblingIndex] = next;
                                        }),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kPrimaryColor,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(dialogContext, true),
                icon: const Icon(Icons.save_outlined),
                label: const Text('Guardar orden'),
              ),
            ],
          );
        },
      ),
    );
    if (shouldSave != true) return;

    final batch = FirebaseFirestore.instance.batch();
    for (final group in siblings.values) {
      for (var i = 0; i < group.length; i++) {
        batch.update(
          FirebaseFirestore.instance
              .collection(_cargosCollection)
              .doc(group[i]),
          {
            'ordenJerarquico': (i + 1) * 100,
            'updatedAt': FieldValue.serverTimestamp(),
          },
        );
      }
    }
    await batch.commit();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Orden jerárquico guardado')));
  }

  /// Normaliza un nombre de área (minúsculas, sin acentos, espacios simples)
  /// para emparejar el nombre guardado en el cargo con el área canónica.
  String _normArea(String s) {
    const src = 'áéíóúÁÉÍÓÚäëïöüÄËÏÖÜñÑ';
    const dst = 'aeiouAEIOUaeiouAEIOUnN';
    var out = s;
    for (var i = 0; i < src.length; i++) {
      out = out.replaceAll(src[i], dst[i]);
    }
    return out.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Actualiza todos los cargos: assigned_users_*, subordinates_* y rellena el
  /// `areaId`/`areaNombre` faltante (resuelto desde TBL_AREAS por nombre) para
  /// que el módulo de tareas filtre los cargos por área correctamente.
  Future<void> _updateAllCargos() async {
    final fs = FirebaseFirestore.instance;
    final col = fs.collection(_cargosCollection);
    final cargosSnap = await col
        .where('empresaId', isEqualTo: widget.empresaId)
        .get();
    final orgQueries = await Future.wait([
      fs
          .collection(_orgCollection)
          .where('empresaId', isEqualTo: widget.empresaId)
          .get(),
      fs
          .collection(_orgCollection)
          .where('empresas', arrayContains: widget.empresaId)
          .get(),
    ]);
    final orgDocs = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final query in orgQueries) {
      for (final doc in query.docs) {
        orgDocs[doc.id] = doc;
      }
    }
    final areasSnap = await fs
        .collection(_areasCollection)
        .where('empresaId', isEqualTo: widget.empresaId)
        .get();

    // Índices de áreas: id->nombre y nombreNormalizado->id.
    final areaNombreById = <String, String>{};
    final areaIdByName = <String, String>{};
    for (final a in areasSnap.docs) {
      final data = a.data();
      final areaId = ((data['areaId'] as String?)?.trim().isNotEmpty == true)
          ? (data['areaId'] as String).trim()
          : a.id;
      final nombre = (data['nombre'] as String?)?.trim() ?? '';
      if (areaId.isEmpty) continue;
      areaNombreById[areaId] = nombre;
      final nk = _normArea(nombre);
      if (nk.isNotEmpty) areaIdByName[nk] = areaId;
    }

    String textField(Map<String, dynamic> data, List<String> keys) {
      for (final key in keys) {
        final value = (data[key] as String?)?.trim() ?? '';
        if (value.isNotEmpty) return value;
      }
      return '';
    }

    List<String> sortedUnique(Iterable<String> values) {
      final out =
          values
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toSet()
              .toList()
            ..sort();
      return out;
    }

    bool listChanged(List<dynamic> existing, List<String> next) {
      final a = existing
          .map((e) => e.toString())
          .where((e) => e.isNotEmpty)
          .toSet();
      final b = next.toSet();
      return a.length != b.length || !a.containsAll(b);
    }

    final cargoById = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    final cargoByName = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final cargoDoc in cargosSnap.docs) {
      cargoById[cargoDoc.id] = cargoDoc;
      final nombre = _cargoNombre(cargoDoc.data());
      if (nombre.isNotEmpty) cargoByName[nombre.toLowerCase()] = cargoDoc;
    }

    final cargoCedulasById = <String, Set<String>>{};
    final cargoNamesById = <String, Set<String>>{};
    final cargoByOccupant = <String, String>{};
    for (final personDoc in orgDocs.values) {
      final raw = personDoc.data();
      if (!matchesEmpresaScope(
        raw,
        widget.empresaId,
        allowLegacyWithoutEmpresa: false,
      )) {
        continue;
      }
      final data = mergeCompanyScopedData(raw, widget.empresaId);
      final cargoId = textField(data, ['cargoId']);
      final cargoName = textField(data, ['cargo']);
      final cargoDoc =
          cargoById[cargoId] ?? cargoByName[cargoName.toLowerCase()];
      if (cargoDoc == null) continue;

      final cedula = textField(data, ['cedula']).isNotEmpty
          ? textField(data, ['cedula'])
          : personDoc.id;
      cargoCedulasById.putIfAbsent(cargoDoc.id, () => <String>{}).add(cedula);
      final nombre = textField(data, ['nombre']);
      cargoNamesById
          .putIfAbsent(cargoDoc.id, () => <String>{})
          .add(nombre.isNotEmpty ? nombre : cedula);
      cargoByOccupant[cedula] = cargoDoc.id;
    }

    final subIdsByCargoId = <String, Set<String>>{};
    final subNamesByCargoId = <String, Set<String>>{};
    for (final personDoc in orgDocs.values) {
      final raw = personDoc.data();
      if (!matchesEmpresaScope(
        raw,
        widget.empresaId,
        allowLegacyWithoutEmpresa: false,
      )) {
        continue;
      }
      final data = mergeCompanyScopedData(raw, widget.empresaId);
      final jefeId = textField(data, ['jefe_directo_id', 'jefeId']);
      var jefeCargoId = cargoByOccupant[jefeId];
      if (jefeCargoId == null) {
        final jefeCargo = textField(data, ['jefe_cargo_desc', 'cargoJefe']);
        jefeCargoId = cargoByName[jefeCargo.toLowerCase()]?.id;
      }
      if (jefeCargoId == null) continue;

      final cedula = textField(data, ['cedula']).isNotEmpty
          ? textField(data, ['cedula'])
          : personDoc.id;
      subIdsByCargoId.putIfAbsent(jefeCargoId, () => <String>{}).add(cedula);
      final nombre = textField(data, ['nombre']);
      subNamesByCargoId
          .putIfAbsent(jefeCargoId, () => <String>{})
          .add(nombre.isNotEmpty ? nombre : cedula);
    }

    WriteBatch batch = fs.batch();
    var writes = 0;

    Future<void> commitIfNeeded() async {
      if (writes == 0) return;
      await batch.commit();
      batch = fs.batch();
      writes = 0;
    }

    for (final doc in cargosSnap.docs) {
      final data = doc.data();
      final cedulas = sortedUnique(cargoCedulasById[doc.id] ?? <String>{});
      final assignedNames = sortedUnique(cargoNamesById[doc.id] ?? <String>{});
      final subordinateIds = sortedUnique(
        subIdsByCargoId[doc.id] ?? <String>{},
      );
      final subordinateNames = sortedUnique(
        subNamesByCargoId[doc.id] ?? <String>{},
      );

      final patch = <String, dynamic>{};
      if (listChanged(data['cedulas'] as List<dynamic>? ?? const [], cedulas)) {
        patch['cedulas'] = cedulas;
      }
      if (listChanged(
        data['assigned_users_ids'] as List<dynamic>? ?? const [],
        cedulas,
      )) {
        patch['assigned_users_ids'] = cedulas;
      }
      if (listChanged(
        data['assigned_users_names'] as List<dynamic>? ?? const [],
        assignedNames,
      )) {
        patch['assigned_users_names'] = assignedNames;
      }
      if (listChanged(
        data['subordinates_ids'] as List<dynamic>? ?? const [],
        subordinateIds,
      )) {
        patch['subordinates_ids'] = subordinateIds;
      }
      if (listChanged(
        data['subordinates_names'] as List<dynamic>? ?? const [],
        subordinateNames,
      )) {
        patch['subordinates_names'] = subordinateNames;
      }

      // Backfill de área: si el cargo no tiene `areaId` (o apunta a un área
      // inexistente) pero su nombre de área coincide con un área real, se
      // rellena. Sin esto, el cargo se mostraba en TODAS las áreas del módulo
      // de tareas.
      final currentAreaId = textField(data, ['areaId']);
      final areaNombre = textField(data, ['areaNombre', 'area']);
      final needsAreaId =
          currentAreaId.isEmpty || !areaNombreById.containsKey(currentAreaId);
      if (needsAreaId && areaNombre.isNotEmpty) {
        final resolvedAreaId = areaIdByName[_normArea(areaNombre)];
        if (resolvedAreaId != null && resolvedAreaId != currentAreaId) {
          patch['areaId'] = resolvedAreaId;
          patch['areaNombre'] = areaNombre;
        }
      }

      if (patch.isEmpty) continue;

      patch['updatedAt'] = FieldValue.serverTimestamp();
      batch.update(doc.reference, patch);
      writes++;
      if (writes >= 450) await commitIfNeeded();
    }

    await commitIfNeeded();
  }

  void _openCargoForm({DocumentSnapshot<Map<String, dynamic>>? doc}) {
    final isNew = doc == null;
    final data = doc?.data() ?? {};

    final ctrNombre = TextEditingController(
      text: isNew ? '' : _cargoNombre(data),
    );
    final ctrDescLarga = TextEditingController(
      text: data['descripcion'] as String? ?? '',
    );
    final ctrParentDesc = TextEditingController(
      text: data['parent_desc'] as String? ?? '',
    );

    String selectedArea = data['area'] as String? ?? '';
    String selectedParentCode = data['parent_cargo'] as String? ?? '';
    // Para nuevos: el código se auto-genera; para existentes: es el doc.id
    String generatedCode = doc?.id ?? '';
    // Por defecto todos los cargos reciben trabajo operativo: activar la
    // marca es una decisión explícita, nunca un efecto secundario de crear
    // un cargo nuevo.
    bool recibeAsignaciones = cargoRecibeAsignaciones(data);

    const border = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(10)),
    );
    const inputDec = InputDecoration(
      border: border,
      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setStateDialog) {
          // Vista previa del código (actualiza en tiempo real cuando es nuevo)
          final codePreview = isNew ? generatedCode : doc.id;
          final dialogWidth = (MediaQuery.of(ctx).size.width - 64)
              .clamp(280.0, 480.0)
              .toDouble();

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _kPrimaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.badge_outlined,
                    color: _kPrimaryColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  isNew ? 'Crear Cargo' : 'Editar Cargo',
                  style: const TextStyle(
                    fontFamily: _kFontFamily,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: dialogWidth,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),

                    // ── Nombre del cargo (campo principal) ──────────────────
                    TextFormField(
                      controller: ctrNombre,
                      style: const TextStyle(fontFamily: _kFontFamily),
                      decoration: inputDec.copyWith(
                        labelText: 'Nombre del cargo *',
                        hintText: 'Ej: Administrador Tipo 1',
                        prefixIcon: const Icon(Icons.title_rounded, size: 20),
                      ),
                      onChanged: (val) {
                        if (isNew) {
                          setStateDialog(() => generatedCode = _slugCode(val));
                        }
                      },
                    ),
                    const SizedBox(height: 6),

                    // ── Código (auto-generado o readonly) ───────────────────
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFCBD5E1)),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.tag_rounded,
                            size: 16,
                            color: Color(0xFF94A3B8),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              codePreview.isEmpty
                                  ? 'El código se genera al escribir el nombre'
                                  : codePreview,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                color: codePreview.isEmpty
                                    ? const Color(0xFF94A3B8)
                                    : const Color(0xFF334155),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Área (desplegable desde TBL_AREAS) ─────────────────
                    FutureBuilder<List<Map<String, String>>>(
                      future: _fetchAreasList(),
                      builder: (ctx2, snapAreas) {
                        if (!snapAreas.hasData) {
                          return const SizedBox(
                            height: 56,
                            child: Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          );
                        }
                        final areas = snapAreas.data!;
                        // Asegurar que el valor actual exista en la lista
                        final validArea =
                            areas.any((a) => a['nombre'] == selectedArea)
                            ? selectedArea
                            : null;

                        return DropdownButtonFormField<String>(
                          decoration: inputDec.copyWith(
                            labelText: 'Área *',
                            prefixIcon: const Icon(
                              Icons.hub_outlined,
                              size: 20,
                            ),
                          ),
                          isExpanded: true,
                          initialValue: validArea,
                          hint: const Text(
                            'Selecciona un área',
                            style: TextStyle(fontFamily: _kFontFamily),
                          ),
                          items: areas.map((a) {
                            final desc = a['descripcion']!;
                            return DropdownMenuItem<String>(
                              value: a['nombre'],
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      a['nombre']!,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontFamily: _kFontFamily,
                                        fontWeight: FontWeight.w500,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  if (desc.isNotEmpty) ...[
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        '· $desc',
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontFamily: _kFontFamily,
                                          fontSize: 11,
                                          color: Color(0xFF94A3B8),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          }).toList(),
                          onChanged: (val) =>
                              setStateDialog(() => selectedArea = val ?? ''),
                        );
                      },
                    ),
                    const SizedBox(height: 16),

                    // ── Descripción de responsabilidades ────────────────────
                    TextFormField(
                      controller: ctrDescLarga,
                      style: const TextStyle(fontFamily: _kFontFamily),
                      decoration: inputDec.copyWith(
                        labelText: 'Descripción de responsabilidades',
                        hintText: 'Opcional: funciones principales del cargo',
                        prefixIcon: const Icon(
                          Icons.description_outlined,
                          size: 20,
                        ),
                        alignLabelWithHint: true,
                      ),
                      maxLines: 3,
                      minLines: 2,
                    ),
                    const SizedBox(height: 16),

                    // ── Cargo padre (TypeAhead con área) ────────────────────
                    TypeAheadField<Map<String, String>>(
                      textFieldConfiguration: TextFieldConfiguration(
                        controller: ctrParentDesc,
                        style: const TextStyle(fontFamily: _kFontFamily),
                        decoration: inputDec.copyWith(
                          labelText: 'Reporta a (cargo padre, opcional)',
                          prefixIcon: const Icon(
                            Icons.supervisor_account_outlined,
                            size: 20,
                          ),
                          hintText: 'Buscar cargo superior…',
                        ),
                      ),
                      suggestionsCallback: _fetchCargos,
                      itemBuilder: (_, m) => ListTile(
                        title: Text(
                          m['desc']!,
                          style: const TextStyle(fontFamily: _kFontFamily),
                        ),
                        subtitle: m['area']!.isNotEmpty
                            ? Text(
                                'Área: ${m['area']}',
                                style: const TextStyle(
                                  fontFamily: _kFontFamily,
                                  fontSize: 12,
                                ),
                              )
                            : null,
                      ),
                      onSuggestionSelected: (m) => setStateDialog(() {
                        selectedParentCode = m['code']!;
                        ctrParentDesc.text = m['desc']!;
                      }),
                      minCharsForSuggestions: 0,
                      noItemsFoundBuilder: (_) => const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text(
                          'Sin resultados',
                          style: TextStyle(fontFamily: _kFontFamily),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── ¿Recibe tareas operativas? ─────────────────────────
                    // Saca al cargo de los desplegables de asignación
                    // (Crear tarea, hallazgos de Interventoría) sin retirar a
                    // nadie: la persona sigue vinculada y entrando a la app.
                    Container(
                      decoration: BoxDecoration(
                        color: recibeAsignaciones
                            ? const Color(0xFFF8FAFC)
                            : const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: recibeAsignaciones
                              ? const Color(0xFFCBD5E1)
                              : const Color(0xFFF59E0B),
                        ),
                      ),
                      child: SwitchListTile(
                        value: recibeAsignaciones,
                        onChanged: (val) =>
                            setStateDialog(() => recibeAsignaciones = val),
                        activeThumbColor: _kPrimaryColor,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 2,
                        ),
                        title: const Text(
                          'Recibe tareas operativas',
                          style: TextStyle(
                            fontFamily: _kFontFamily,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          recibeAsignaciones
                              ? 'Aparece en "Crear tarea" y en la asignación de hallazgos.'
                              : 'No aparece como candidato en los módulos operativos. '
                                    'Conserva su acceso y su lugar en el organigrama.',
                          style: const TextStyle(
                            fontFamily: _kFontFamily,
                            fontSize: 11,
                            color: Color(0xFF64748B),
                            height: 1.3,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            actionsPadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 16,
            ),
            actions: [
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF64748B),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'Cancelar',
                  style: TextStyle(fontFamily: _kFontFamily),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kPrimaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
                onPressed: () async {
                  final nombre = ctrNombre.text.trim();
                  if (nombre.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('El nombre del cargo es obligatorio'),
                      ),
                    );
                    return;
                  }
                  if (selectedArea.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Selecciona un área')),
                    );
                    return;
                  }
                  final code = isNew ? generatedCode : doc.id;
                  if (code.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Escribe un nombre para generar el código',
                        ),
                      ),
                    );
                    return;
                  }

                  // Resolver el areaId del área seleccionada. El módulo de
                  // tareas filtra los cargos por `areaId`; sin él, el cargo se
                  // mostraría en todas las áreas del desplegable "Crear tarea".
                  final areas = await _fetchAreasList();
                  final areaHit = areas.firstWhere(
                    (a) => a['nombre'] == selectedArea,
                    orElse: () => const {},
                  );
                  final selectedAreaId = (areaHit['areaId'] ?? '').trim();
                  final hierarchyOrder = isNew
                      ? await _nextHierarchyOrder(selectedParentCode)
                      : hierarchyOrderOf(data);

                  final payload = {
                    'nombre': nombre,
                    'descripcion': ctrDescLarga.text.trim(),
                    'area': selectedArea,
                    'areaNombre': selectedArea,
                    'areaId': selectedAreaId.isEmpty ? null : selectedAreaId,
                    'empresaId': widget.empresaId,
                    'parent_cargo': selectedParentCode.isEmpty
                        ? null
                        : selectedParentCode,
                    'parent_desc': ctrParentDesc.text.trim().isEmpty
                        ? null
                        : ctrParentDesc.text.trim(),
                    'ordenJerarquico': hierarchyOrder,
                    kCampoRecibeAsignaciones: recibeAsignaciones,
                  };
                  final col = FirebaseFirestore.instance.collection(
                    _cargosCollection,
                  );
                  if (isNew) {
                    await col.doc(code).set(payload);
                  } else {
                    await col.doc(code).update(payload);
                  }
                  await _updateAllCargos();
                  if (mounted) Navigator.pop(context);
                },
                child: Text(
                  isNew ? 'Crear cargo' : 'Guardar cambios',
                  style: const TextStyle(fontFamily: _kFontFamily),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _deleteCargo(String code) async {
    await FirebaseFirestore.instance
        .collection(_cargosCollection)
        .doc(code)
        .delete();
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
          icon: const Icon(
            Icons.account_tree_outlined,
            color: Color(0xFF64748B),
          ),
          tooltip: 'Ajustar orden jerárquico',
          onPressed: _openHierarchyOrderPanel,
        ),
        IconButton(
          icon: const Icon(Icons.sync_rounded, color: Color(0xFF64748B)),
          tooltip: 'Sincronizar Estructura',
          onPressed: () async {
            final snack = ScaffoldMessenger.of(context);
            snack.showSnackBar(
              const SnackBar(
                content: Text('Sincronizando cargos con la estructura...'),
              ),
            );
            await _updateAllCargos();
            snack.showSnackBar(
              const SnackBar(
                content: Text('Cargos actualizados correctamente'),
              ),
            );
            setState(() {});
          },
        ),
        IconButton(
          icon: const Icon(
            Icons.add_circle_outline_rounded,
            size: 28,
            color: _kPrimaryColor,
          ),
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
              stream: FirebaseFirestore.instance
                  .collection(_cargosCollection)
                  .where('empresaId', isEqualTo: widget.empresaId)
                  .snapshots(),
              builder: (ctx, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final term = _searchCtrl.text.trim().toLowerCase();
                final allDocs = snap.data!.docs;
                final hierarchy = CargoHierarchyIndex.fromCargos(
                  allDocs.map(
                    (d) => <String, dynamic>{'id': d.id, ...d.data()},
                  ),
                );
                final docs =
                    allDocs.where((d) => _cargoMatches(d, term)).toList()..sort(
                      (a, b) => hierarchy.compareCargos(
                        <String, dynamic>{'id': a.id, ...a.data()},
                        <String, dynamic>{'id': b.id, ...b.data()},
                      ),
                    );

                if (docs.isEmpty) {
                  return const Center(child: Text('No se encontraron cargos.'));
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(24),
                  itemCount: docs.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (c, i) {
                    final d = docs[i];
                    final m = d.data();
                    final code = d.id;
                    final desc = _cargoNombre(m);
                    final area = m['area'] as String? ?? '';
                    final descLarga =
                        (m['descripcion'] as String?)?.trim() ?? '';

                    return ModuleCard(
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: _kPrimaryColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.badge_outlined,
                              color: _kPrimaryColor,
                              size: 20,
                            ),
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
                                Text(
                                  code,
                                  style: const TextStyle(
                                    fontFamily: _kFontFamily,
                                    fontSize: 10,
                                    color: Color(0xFF94A3B8),
                                  ),
                                ),
                                if (descLarga.isNotEmpty && descLarga != desc)
                                  Text(
                                    descLarga,
                                    style: const TextStyle(
                                      fontFamily: _kFontFamily,
                                      fontSize: 11,
                                      color: Color(0xFF94A3B8),
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
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
                                // Solo se muestra la excepción: marcar el 99%
                                // de los cargos con "sí recibe tareas" sería
                                // ruido en la lista.
                                if (!cargoRecibeAsignaciones(m))
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFEF3C7),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: const Color(0xFFF59E0B),
                                        ),
                                      ),
                                      child: const Text(
                                        'No recibe tareas operativas',
                                        style: TextStyle(
                                          fontFamily: _kFontFamily,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF92400E),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.group_outlined,
                              color: Color(0xFF64748B),
                            ),
                            onPressed: () => _showUsersDialog(code),
                            tooltip: 'Ver ocupantes',
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.edit_outlined,
                              color: Color(0xFF64748B),
                            ),
                            onPressed: () => _openCargoForm(doc: d),
                            tooltip: 'Editar',
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.delete_outline,
                              color: Colors.redAccent,
                            ),
                            onPressed: () async {
                              final ok = await showDialog<bool>(
                                context: context,
                                builder: (_) => AlertDialog(
                                  title: const Text('Confirmar borrado'),
                                  content: Text('¿Borrar cargo "$desc"?'),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, false),
                                      child: const Text('Cancelar'),
                                    ),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.red,
                                      ),
                                      onPressed: () =>
                                          Navigator.pop(context, true),
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

  /// Construye el nombre para mostrar a partir de un doc de TBL_USUARIOS.
  String _nombreDeUsuario(Map<String, dynamic> ud) {
    final completo = (ud['nombreCompleto'] as String?)?.trim() ?? '';
    if (completo.isNotEmpty) return completo;
    final nombres = (ud['nombres'] as String?)?.trim() ?? '';
    final apellidos = (ud['apellidos'] as String?)?.trim() ?? '';
    if (nombres.isNotEmpty || apellidos.isNotEmpty) {
      return '$nombres $apellidos'.trim();
    }
    final p1 = (ud['primerNombre'] as String?)?.trim() ?? '';
    final p2 = (ud['segundoNombre'] as String?)?.trim() ?? '';
    final a1 = (ud['primerApellido'] as String?)?.trim() ?? '';
    final a2 = (ud['segundoApellido'] as String?)?.trim() ?? '';
    return '$p1 $p2 $a1 $a2'.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Resuelve el nombre de una cédula buscando en TBL_USUARIOS (directo + query)
  /// junto con su vinculación: el array `cedulas` del cargo conserva a quien ya
  /// se retiró, así que el estado laboral se lee del usuario.
  Future<({String nombre, bool activa})> _resolvePersona(String cedula) async {
    final col = FirebaseFirestore.instance.collection('TBL_USUARIOS');
    final direct = await col.doc(cedula).get();
    final directData = direct.data();
    if (direct.exists && directData != null) {
      final n = _nombreDeUsuario(directData);
      if (n.isNotEmpty) {
        return (
          nombre: n,
          activa: isPersonaActivaEnEmpresa(directData, widget.empresaId),
        );
      }
    }
    final q = await col.where('cedula', isEqualTo: cedula).limit(1).get();
    if (q.docs.isNotEmpty) {
      final data = q.docs.first.data();
      final n = _nombreDeUsuario(data);
      if (n.isNotEmpty) {
        return (
          nombre: n,
          activa: isPersonaActivaEnEmpresa(data, widget.empresaId),
        );
      }
    }
    // fallback: muestra la cédula si no hay nombre
    return (nombre: cedula, activa: true);
  }

  /// Muestra los ocupantes del cargo leyendo el array `cedulas` del doc de TBL_CARGOS.
  Future<void> _showUsersDialog(String cargoCode) async {
    final cargoSnap = await FirebaseFirestore.instance
        .collection(_cargosCollection)
        .doc(cargoCode)
        .get();
    final cargoData = cargoSnap.data() ?? {};
    final cargoNombre = _cargoNombre(cargoData);

    // Leer array de cédulas asignadas directamente del doc del cargo
    final rawList = (cargoData['cedulas'] as List<dynamic>?) ?? [];
    final cedulas = rawList
        .map((e) => e.toString().trim())
        .where((s) => s.isNotEmpty)
        .toList();

    // Resolver nombre de cada cédula, omitiendo a los ya retirados
    final List<Map<String, String>> asignados = [];
    for (final ced in cedulas) {
      final persona = await _resolvePersona(ced);
      if (!persona.activa) continue;
      asignados.add({'cedula': ced, 'nombre': persona.nombre});
    }

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) {
        final dialogWidth = (MediaQuery.of(ctx).size.width - 64)
            .clamp(280.0, 400.0)
            .toDouble();
        return AlertDialog(
          title: Text(
            'Ocupantes: $cargoNombre',
            style: const TextStyle(
              fontFamily: _kFontFamily,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SizedBox(
            width: dialogWidth,
            child: asignados.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'No hay personal asignado a este cargo.',
                      style: TextStyle(
                        fontFamily: _kFontFamily,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: asignados.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final u = asignados[i];
                      final nombre = u['nombre']!;
                      final cedula = u['cedula']!;
                      return ListTile(
                        leading: UserAvatar(
                          userId: cedula,
                          nameHint: nombre,
                          backgroundColor: _kPrimaryColor,
                          foregroundColor: Colors.white,
                        ),
                        title: UserNameText(
                          cedula,
                          fallbackName: nombre,
                          style: const TextStyle(
                            fontFamily: _kFontFamily,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          'Cédula: $cedula',
                          style: const TextStyle(
                            fontFamily: _kFontFamily,
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Cerrar',
                style: TextStyle(fontFamily: _kFontFamily),
              ),
            ),
          ],
        );
      },
    );
  }
}
