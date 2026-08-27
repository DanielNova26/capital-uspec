// lib/talento_humano/areas_management_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../core/hierarchy_order.dart';
import '../utils/user_company.dart';
import '../widgets/internal_module_layout.dart';
import '../widgets/user_avatar.dart';

const Color _khPrimary = Color(0xffc28942);
const Color _khSecondary = Color(0xffe19e4c);
const String _kFont = 'Arial';

class AreasManagementScreen extends StatefulWidget {
  final String userId;
  final String empresaId;
  const AreasManagementScreen({
    Key? key,
    required this.userId,
    required this.empresaId,
  }) : super(key: key);

  @override
  State<AreasManagementScreen> createState() => _AreasManagementScreenState();
}

class _AreasManagementScreenState extends State<AreasManagementScreen> {
  final _db = FirebaseFirestore.instance;
  bool _saving = false;

  CollectionReference<Map<String, dynamic>> get _areasColl =>
      _db.collection('TBL_AREAS');

  String _s(dynamic v) => v == null ? '' : v.toString().trim();

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

  /// Nombre y vinculación de una cédula. El array `cedulas` del área conserva
  /// a quien ya se retiró, así que el estado laboral se lee del usuario para
  /// no listar personal inactivo.
  Future<({String nombre, bool activa})> _resolvePersonaArea(
    String cedula,
  ) async {
    final col = _db.collection('TBL_USUARIOS');
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
    return (nombre: cedula, activa: true);
  }

  Future<void> _showAreaUsersDialog(
    String areaNombre,
    List<dynamic> rawCedulas,
  ) async {
    final cedulas = rawCedulas
        .map((e) => e.toString().trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final cargosSnap = await _db
        .collection('TBL_CARGOS')
        .where('empresaId', isEqualTo: widget.empresaId)
        .get();
    final cargoCatalog = cargosSnap.docs
        .map((d) => <String, dynamic>{'id': d.id, ...d.data()})
        .toList();
    final hierarchy = CargoHierarchyIndex.fromCargos(cargoCatalog);
    final cargoByCedula = <String, Map<String, dynamic>>{};
    for (final cargo in cargoCatalog) {
      final raw = cargo['cedulas'];
      if (raw is! List) continue;
      for (final value in raw) {
        final cedula = _s(value);
        if (cedula.isEmpty) continue;
        final current = cargoByCedula[cedula];
        if (current == null || hierarchy.compareCargos(cargo, current) < 0) {
          cargoByCedula[cedula] = cargo;
        }
      }
    }

    final resueltos = await Future.wait(
      cedulas.map((ced) async {
        final cargo = cargoByCedula[ced] ?? const <String, dynamic>{};
        final persona = await _resolvePersonaArea(ced);
        return (
          activa: persona.activa,
          fila: <String, dynamic>{
            'cedula': ced,
            'nombre': persona.nombre,
            'cargoId': cargoIdOf(cargo),
            'cargo': cargoNameOf(cargo),
          },
        );
      }),
    );
    final asignados = [
      for (final r in resueltos)
        if (r.activa) r.fila,
    ];
    asignados.sort(hierarchy.comparePersonnel);

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) {
        final dialogWidth = (MediaQuery.of(ctx).size.width - 64)
            .clamp(280.0, 400.0)
            .toDouble();
        return AlertDialog(
          title: Text(
            'Personal en: $areaNombre',
            style: const TextStyle(
              fontFamily: _kFont,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SizedBox(
            width: dialogWidth,
            child: asignados.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'No hay personal asignado a esta área.',
                      style: TextStyle(
                        fontFamily: _kFont,
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
                      final cargo = (u['cargo'] ?? '').toString();
                      return ListTile(
                        leading: UserAvatar(
                          userId: cedula,
                          nameHint: nombre,
                          backgroundColor: _khPrimary,
                          foregroundColor: Colors.white,
                        ),
                        title: UserNameText(
                          cedula,
                          fallbackName: nombre,
                          style: const TextStyle(
                            fontFamily: _kFont,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          cargo.isEmpty
                              ? 'Cédula: $cedula'
                              : '$cargo · Cédula: $cedula',
                          style: const TextStyle(
                            fontFamily: _kFont,
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
              child: const Text('Cerrar', style: TextStyle(fontFamily: _kFont)),
            ),
          ],
        );
      },
    );
  }

  String _slug(String s) {
    final base = s
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return base.isEmpty ? 'area' : base;
  }

  Future<void> _openAreaDialog({
    DocumentSnapshot<Map<String, dynamic>>? doc,
  }) async {
    final isNew = doc == null;
    final data = doc?.data() ?? {};

    final nombreCtrl = TextEditingController(
      text: isNew ? '' : _s(data['nombre']),
    );
    final descCtrl = TextEditingController(
      text: isNew ? '' : _s(data['descripcion']),
    );
    String generatedCode = doc?.id ?? '';

    const border = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(10)),
    );
    const inputDec = InputDecoration(
      border: border,
      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setStateDialog) {
          final dialogWidth = (MediaQuery.of(ctx2).size.width - 64)
              .clamp(280.0, 440.0)
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
                    color: _khPrimary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.hub_outlined,
                    color: _khPrimary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  isNew ? 'Crear Área' : 'Editar Área',
                  style: const TextStyle(
                    fontFamily: _kFont,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: dialogWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),

                  // ── Nombre del área ─────────────────────────────────────────
                  TextFormField(
                    controller: nombreCtrl,
                    style: const TextStyle(fontFamily: _kFont),
                    decoration: inputDec.copyWith(
                      labelText: 'Nombre del área *',
                      hintText: 'Ej: Recursos Humanos',
                      prefixIcon: const Icon(Icons.title_rounded, size: 20),
                    ),
                    onChanged: (val) {
                      if (isNew) {
                        setStateDialog(
                          () => generatedCode =
                              '${widget.empresaId}_${_slug(val)}',
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 6),

                  // ── Código (auto-generado o readonly) ───────────────────────
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
                            generatedCode.isEmpty
                                ? 'El código se genera al escribir el nombre'
                                : generatedCode,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              color: generatedCode.isEmpty
                                  ? const Color(0xFF94A3B8)
                                  : const Color(0xFF334155),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Descripción ─────────────────────────────────────────────
                  TextFormField(
                    controller: descCtrl,
                    style: const TextStyle(fontFamily: _kFont),
                    decoration: inputDec.copyWith(
                      labelText: 'Descripción (opcional)',
                      hintText: 'Propósito y funciones del área',
                      prefixIcon: const Icon(
                        Icons.description_outlined,
                        size: 20,
                      ),
                      alignLabelWithHint: true,
                    ),
                    maxLines: 3,
                    minLines: 2,
                  ),
                  const SizedBox(height: 8),
                ],
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
                onPressed: () => Navigator.of(ctx2).pop(),
                child: const Text(
                  'Cancelar',
                  style: TextStyle(fontFamily: _kFont),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _khPrimary,
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
                  final nombre = nombreCtrl.text.trim();
                  if (nombre.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('El nombre del área es obligatorio'),
                      ),
                    );
                    return;
                  }
                  setState(() => _saving = true);
                  try {
                    final payload = {
                      'nombre': nombre,
                      'descripcion': descCtrl.text.trim(),
                      'empresaId': widget.empresaId,
                      'updatedAt': FieldValue.serverTimestamp(),
                    };
                    if (isNew) {
                      final id = '${widget.empresaId}_${_slug(nombre)}';
                      await _areasColl.doc(id).set(payload);
                    } else {
                      await doc.reference.update(payload);
                    }
                    if (mounted) Navigator.of(ctx2).pop();
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text('Error: $e')));
                    }
                  } finally {
                    if (mounted) setState(() => _saving = false);
                  }
                },
                child: Text(
                  isNew ? 'Crear área' : 'Guardar cambios',
                  style: const TextStyle(fontFamily: _kFont),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _deleteArea(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar área'),
        content: const Text('¿Estás seguro de eliminar esta área?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
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
            return const Center(
              child: Text('No hay áreas registradas para esta empresa.'),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(24),
            itemCount: docs.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (ctx, idx) {
              final doc = docs[idx];
              final data = doc.data();
              return ModuleCard(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _khPrimary.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.hub_outlined,
                        color: _khPrimary,
                        size: 20,
                      ),
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
                      icon: const Icon(
                        Icons.group_outlined,
                        color: Color(0xFF64748B),
                      ),
                      tooltip: 'Ver personal',
                      onPressed: () => _showAreaUsersDialog(
                        _s(data['nombre']),
                        (data['cedulas'] as List<dynamic>?) ?? [],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.edit_outlined,
                        color: Color(0xFF64748B),
                      ),
                      onPressed: () => _openAreaDialog(doc: doc),
                      tooltip: 'Editar',
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.delete_outline,
                        color: Colors.redAccent,
                      ),
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
