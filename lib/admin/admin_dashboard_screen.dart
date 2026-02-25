import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:todo/services/diagnosticos_service.dart';
import 'package:todo/services/compras_req_excel_parser.dart';
import '../compras/compras_req_seed.dart';
import '../compras/compras_service.dart';
import '../compras/compras_models.dart';

import 'admin_repository.dart';
import 'migrations/admin_migration_service.dart';

const String kArial = 'Arial';

// ======= Paleta Admin (moderna) =======
const Color kAdminBg = Color(0xFFF6F8FF);
const Color kAdminPrimary = Color(0xFF1E3A8A); // Indigo
const Color kAdminAccent = Color(0xFF06B6D4);  // Cyan
const Color kAdminCard = Colors.white;

class AdminDashboardScreen extends StatefulWidget {
  final String userId; // admin id
  const AdminDashboardScreen({super.key, required this.userId});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final _repo = AdminRepository(db: FirebaseFirestore.instance);
  final _mig = AdminMigrationService(db: FirebaseFirestore.instance);

  bool _loading = true;

  // Empresa
  List<EmpresaItem> _empresas = [];
  String? _empresaId;

  // Apps / Usuarios
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _users = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _apps = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _appsAdmin = [];
  Map<String, Set<String>> _userApps = {};

  // Catálogos
  List<CentroCostoItem> _centros = [];
  List<AreaItem> _areas = [];
  List<CargoItem> _cargos = [];

  // UI
  String _userSearch = '';

  // Migración: selección de usuarios
  Set<String> _selectedMigrationUsers = {};

  // Diagnósticos: carga de Excel
  final DiagnosticosService _diagnosticosService = DiagnosticosService();
  String? _diagnosticosFileName;
  Uint8List? _diagnosticosBytes;
  Map<String, int>? _diagnosticosImportResult;
  bool _importandoReqCompras = false;
  final ComprasReqExcelParser _comprasReqParser = ComprasReqExcelParser();
  String? _reqComprasFileName;
  Uint8List? _reqComprasBytes;
  Map<String, int>? _reqComprasImportResult;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll({String? forceEmpresaId}) async {
    setState(() => _loading = true);

    final empresas = await _repo.loadEmpresas();
    String? selected = forceEmpresaId;

    // intenta empresa del admin
    if (selected == null || selected.isEmpty) {
      try {
        final adminDoc =
        await FirebaseFirestore.instance.collection('TBL_USUARIOS').doc(widget.userId).get();
        selected = (adminDoc.data()?['empresaId'] ?? '').toString().trim();
      } catch (_) {}
    }
    selected ??= empresas.isNotEmpty ? empresas.first.empresaId : null;

    if (selected == null || selected.isEmpty) {
      setState(() {
        _empresas = empresas;
        _empresaId = null;
        _loading = false;
      });
      return;
    }

    final users = await _repo.loadUsersByEmpresa(selected);
    final apps = await _repo.loadEnabledAppsByEmpresa(selected);
    final appsAdmin = await _repo.loadAppsByEmpresa(selected);
    final centros = await _repo.loadCentros(selected);
    final areas = await _repo.loadAreas(selected);
    final cargos = await _repo.loadCargos(selected);

    setState(() {
      _empresas = empresas;
      _empresaId = selected;

      _users = users;
      _apps = apps;
      _appsAdmin = appsAdmin;

      _centros = centros;
      _areas = areas;
      _cargos = cargos;

      _userApps = {
        for (final u in users)
          u.id: {
            ...((u.data()['apps'] as List<dynamic>? ?? const [])
                .map((e) => e.toString().trim())
                .where((e) => e.isNotEmpty))
          }
      };

      // Si cambias de empresa, limpiamos selección de migración
      _selectedMigrationUsers = {};

      _loading = false;
    });
  }

  // ---------------- HELPERS ----------------
  String _safe(dynamic v) => v == null ? '' : v.toString().trim();

  String _userName(Map<String, dynamic> d, String fallback) {
    final n = _safe(d['nombres']).isNotEmpty ? _safe(d['nombres']) : _safe(d['primerNombre']);
    final a = _safe(d['apellidos']).isNotEmpty ? _safe(d['apellidos']) : _safe(d['primerApellido']);
    final full = ('$n $a').trim();
    return full.isEmpty ? fallback : full;
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg, style: const TextStyle(fontFamily: kArial))),
    );
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    String confirmText = 'Confirmar',
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title, style: const TextStyle(fontFamily: kArial, fontWeight: FontWeight.w800)),
        content: Text(message, style: const TextStyle(fontFamily: kArial)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar', style: TextStyle(fontFamily: kArial)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kAdminPrimary),
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmText, style: const TextStyle(fontFamily: kArial)),
          ),
        ],
      ),
    );
    return ok == true;
  }

  // ---------------- USUARIOS: editar apps ----------------
  Future<void> _editUserApps(QueryDocumentSnapshot<Map<String, dynamic>> userDoc) async {
    final local = {...(_userApps[userDoc.id] ?? {})};
    final data = userDoc.data();
    final nombre = _userName(data, userDoc.id);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: kAdminBg,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 8,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.85,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Apps asignadas',
                    style: TextStyle(
                      fontFamily: kArial,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      color: kAdminPrimary,
                    )),
                const SizedBox(height: 4),
                Text(nombre, style: const TextStyle(fontFamily: kArial, color: Colors.black54)),
                const SizedBox(height: 12),
                Expanded(
                  child: _apps.isEmpty
                      ? const Center(child: Text('No hay apps habilitadas.', style: TextStyle(fontFamily: kArial)))
                      : Card(
                    color: kAdminCard,
                    child: ListView.separated(
                      itemCount: _apps.length,
                      separatorBuilder: (_, __) => const Divider(height: 0),
                      itemBuilder: (_, i) {
                        final aDoc = _apps[i];
                        final a = aDoc.data();
                        final appId = _safe(a['appId']).isNotEmpty ? _safe(a['appId']) : aDoc.id;
                        final nombre = _safe(a['nombre']).isNotEmpty ? _safe(a['nombre']) : appId;
                        final checked = local.contains(appId);

                        return CheckboxListTile(
                          value: checked,
                          activeColor: kAdminPrimary,
                          title: Text(nombre, style: const TextStyle(fontFamily: kArial, fontWeight: FontWeight.w700)),
                          subtitle: Text(appId, style: const TextStyle(fontFamily: kArial, color: Colors.black54)),
                          onChanged: (v) {
                            if (v == true) {
                              local.add(appId);
                            } else {
                              local.remove(appId);
                            }
                            (ctx as Element).markNeedsBuild();
                          },
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.save),
                    style: ElevatedButton.styleFrom(backgroundColor: kAdminPrimary),
                    onPressed: () async {
                      await _repo.updateUserApps(userDoc.id, local);
                      _snack('Apps actualizadas');
                      if (!mounted) return;
                      Navigator.pop(ctx);
                      await _loadAll(forceEmpresaId: _empresaId);
                    },
                    label: const Text('Guardar', style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---------------- USUARIOS: editar org ----------------
  Future<void> _editUserOrg(QueryDocumentSnapshot<Map<String, dynamic>> userDoc) async {
    final empresaId = _empresaId ?? '';
    if (empresaId.isEmpty) return;

    final d = userDoc.data();
    final nombre = _userName(d, userDoc.id);

    String? centroId = _safe(d['centroId']).isEmpty ? null : _safe(d['centroId']);
    String? areaId = _safe(d['areaId']).isEmpty ? null : _safe(d['areaId']);
    String cargoNombre = _safe(d['cargo']);

    CentroCostoItem? centroSel = _centros.where((c) => c.centroId == centroId).cast<CentroCostoItem?>().firstWhere((x) => x != null, orElse: () => null);
    AreaItem? areaSel = _areas.where((a) => a.areaId == areaId).cast<AreaItem?>().firstWhere((x) => x != null, orElse: () => null);

    await showDialog(
      context: context,
      builder: (_) {
        final centrosEnabled = _centros.where((c) => c.enabled).toList();
        final areasEnabled = _areas.where((a) => a.enabled).toList();

        return AlertDialog(
          title: Text('Organización', style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.w900, color: kAdminPrimary)),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(nombre, style: const TextStyle(fontFamily: kArial, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(height: 12),

                DropdownButtonFormField<CentroCostoItem>(
                  value: centroSel,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Centro de costos', border: OutlineInputBorder()),
                  items: centrosEnabled
                      .map((c) => DropdownMenuItem(
                    value: c,
                    child: Text('${c.codigo} - ${c.nombre}', style: const TextStyle(fontFamily: kArial)),
                  ))
                      .toList(),
                  onChanged: (v) => centroSel = v,
                ),
                const SizedBox(height: 12),

                DropdownButtonFormField<AreaItem>(
                  value: areaSel,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Área / Departamento', border: OutlineInputBorder()),
                  items: areasEnabled
                      .map((a) => DropdownMenuItem(
                    value: a,
                    child: Text(a.nombre, style: const TextStyle(fontFamily: kArial)),
                  ))
                      .toList(),
                  onChanged: (v) => areaSel = v,
                ),
                const SizedBox(height: 12),

                TextFormField(
                  initialValue: cargoNombre,
                  decoration: const InputDecoration(labelText: 'Cargo (texto)', border: OutlineInputBorder()),
                  style: const TextStyle(fontFamily: kArial),
                  onChanged: (v) => cargoNombre = v.trim(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar', style: TextStyle(fontFamily: kArial))),
            ElevatedButton.icon(
              icon: const Icon(Icons.save),
              style: ElevatedButton.styleFrom(backgroundColor: kAdminPrimary),
              onPressed: () async {
                await _repo.updateUserOrg(
                  userId: userDoc.id,
                  empresaId: empresaId,
                  centroId: centroSel?.centroId,
                  centroCodigo: centroSel?.codigo,
                  centroNombre: centroSel?.nombre,
                  areaId: areaSel?.areaId,
                  areaNombre: areaSel?.nombre,
                  cargo: cargoNombre.isEmpty ? null : cargoNombre,
                );
                if (!mounted) return;
                Navigator.pop(context);
                _snack('Usuario actualizado');
                await _loadAll(forceEmpresaId: _empresaId);
              },
              label: const Text('Guardar', style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.w900)),
            ),
          ],
        );
      },
    );
  }

  // ---------------- MIGRACIONES: seleccionar usuarios ----------------
  Future<void> _pickMigrationUsers() async {
    final selected = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: kAdminBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        final local = {..._selectedMigrationUsers};
        String q = '';

        List<QueryDocumentSnapshot<Map<String, dynamic>>> filtered() {
          if (q.trim().isEmpty) return _users;
          final s = q.toLowerCase().trim();
          return _users.where((u) {
            final d = u.data();
            final name = _userName(d, u.id).toLowerCase();
            final ced = _safe(d['cedula']).toLowerCase();
            final cargo = _safe(d['cargo']).toLowerCase();
            return name.contains(s) ||
                ced.contains(s) ||
                u.id.toLowerCase().contains(s) ||
                cargo.contains(s);
          }).toList();
        }

        return StatefulBuilder(
          builder: (ctx2, setLocal) {
            final list = filtered();

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 10,
                  bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
                ),
                child: SizedBox(
                  height: MediaQuery.of(ctx).size.height * 0.9,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Seleccionar usuarios para migración',
                        style: TextStyle(
                          fontFamily: kArial,
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                          color: kAdminPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Seleccionados: ${local.length}',
                        style: const TextStyle(
                          fontFamily: kArial,
                          color: Colors.black54,
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Buscar
                      TextField(
                        decoration: InputDecoration(
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.search),
                          labelText: 'Buscar (nombre, cédula, cargo)',
                          isDense: true,
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        style: const TextStyle(fontFamily: kArial),
                        onChanged: (v) => setLocal(() => q = v),
                      ),

                      const SizedBox(height: 10),

                      // ✅ BOTONES RESPONSIVE (evita overflow)
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final w = constraints.maxWidth;
                          final half = (w - 10) / 2;

                          return Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              SizedBox(
                                width: half,
                                child: OutlinedButton.icon(
                                  onPressed: () => setLocal(() {
                                    local.addAll(_users.map((e) => e.id));
                                  }),
                                  icon: const Icon(Icons.select_all),
                                  label: const Text(
                                    'Seleccionar todos',
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontFamily: kArial,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: half,
                                child: OutlinedButton.icon(
                                  onPressed: () => setLocal(() => local.clear()),
                                  icon: const Icon(Icons.clear),
                                  label: const Text(
                                    'Limpiar',
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontFamily: kArial,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: w,
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: kAdminPrimary,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  onPressed: () => Navigator.pop(ctx, local),
                                  icon: const Icon(Icons.check),
                                  label: const Text(
                                    'Aplicar selección',
                                    style: TextStyle(
                                      fontFamily: kArial,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),

                      const SizedBox(height: 10),

                      // Lista
                      Expanded(
                        child: Card(
                          color: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(color: Colors.grey.shade300),
                          ),
                          child: ListView.separated(
                            itemCount: list.length,
                            separatorBuilder: (_, __) => Divider(height: 0, color: Colors.grey.shade200),
                            itemBuilder: (_, i) {
                              final u = list[i];
                              final d = u.data();
                              final name = _userName(d, u.id);
                              final ced = _safe(d['cedula']).isNotEmpty ? _safe(d['cedula']) : u.id;
                              final cargo = _safe(d['cargo']);
                              final checked = local.contains(u.id);

                              return CheckboxListTile(
                                value: checked,
                                activeColor: kAdminPrimary,
                                controlAffinity: ListTileControlAffinity.trailing,
                                dense: true,
                                visualDensity: VisualDensity.compact,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                title: Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontFamily: kArial,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                subtitle: Text(
                                  'ID: ${u.id} • Cédula: $ced${cargo.isNotEmpty ? " • $cargo" : ""}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontFamily: kArial,
                                    color: Colors.black54,
                                  ),
                                ),
                                onChanged: (v) => setLocal(() {
                                  if (v == true) {
                                    local.add(u.id);
                                  } else {
                                    local.remove(u.id);
                                  }
                                }),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (selected == null) return;
    setState(() => _selectedMigrationUsers = selected);
  }

  // ---------------- MIGRACIONES: CENTRO SOLO USUARIOS SELECCIONADOS ----------------
  Future<void> _runNormalizeCentroSelectedUsers({required bool dryRun}) async {
    final empresaId = _empresaId ?? '';
    if (empresaId.isEmpty) return;

    if (_selectedMigrationUsers.isEmpty) {
      _snack('Selecciona usuarios para migrar');
      return;
    }

    final enabledCentros = _centros.where((c) => c.enabled).toList();
    if (enabledCentros.isEmpty) {
      _snack('No hay centros habilitados en catálogo');
      return;
    }

    CentroCostoItem centroCanonical = enabledCentros.first;

    // selector centro canónico
    await showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('Centro canónico', style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.w900)),
          content: DropdownButtonFormField<CentroCostoItem>(
            value: centroCanonical,
            isExpanded: true,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            items: enabledCentros
                .map((c) => DropdownMenuItem(
              value: c,
              child: Text('${c.codigo} - ${c.nombre}', style: const TextStyle(fontFamily: kArial)),
            ))
                .toList(),
            onChanged: (v) {
              if (v != null) centroCanonical = v;
            },
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar', style: TextStyle(fontFamily: kArial))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: kAdminPrimary),
              onPressed: () => Navigator.pop(context),
              child: const Text('Continuar', style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.w900)),
            ),
          ],
        );
      },
    );

    if (!dryRun) {
      final ok = await _confirm(
        title: 'Ejecutar migración de Centro',
        message:
        'Usuarios seleccionados: ${_selectedMigrationUsers.length}\n'
            'Centro canónico: ${centroCanonical.codigo} - ${centroCanonical.nombre}\n\n'
            'Esto SOLO actualizará TBL_USUARIOS (no tareas/cargos/estructura).\n¿Continuar?',
        confirmText: 'Ejecutar',
      );
      if (!ok) return;
    }

    setState(() => _loading = true);

    final result = await _mig.normalizeCentroForUsers(
      empresaId: empresaId,
      userIds: _selectedMigrationUsers,
      canonicalCentroId: centroCanonical.centroId,
      canonicalCentroCodigo: centroCanonical.codigo,
      canonicalCentroNombre: centroCanonical.nombre,
      dryRun: dryRun,
    );

    await _mig.logMigration(
      adminUserId: widget.userId,
      empresaId: empresaId,
      action: 'normalizeCentroForUsers',
      scanned: result.scanned,
      updated: result.updated,
      dryRun: dryRun,
      extra: {
        'selectedUsersCount': _selectedMigrationUsers.length,
        'canonicalCentroId': centroCanonical.centroId,
        'canonicalCentroCodigo': centroCanonical.codigo,
        'canonicalCentroNombre': centroCanonical.nombre,
        'sample': result.sampleUpdatedIds,
      },
    );

    _snack(dryRun
        ? 'SIMULACIÓN Centro: escaneados ${result.scanned}, a cambiar ${result.updated}'
        : 'Centro ejecutado: escaneados ${result.scanned}, cambiados ${result.updated}');

    await _loadAll(forceEmpresaId: empresaId);
  }

  // ---------------- MIGRACIONES: TOKENS SOLO USUARIOS SELECCIONADOS ----------------
  Future<void> _runNormalizeTokensSelectedUsers({required bool dryRun}) async {
    final empresaId = _empresaId ?? '';
    if (empresaId.isEmpty) return;

    if (_selectedMigrationUsers.isEmpty) {
      _snack('Selecciona usuarios para migrar');
      return;
    }

    if (!dryRun) {
      final ok = await _confirm(
        title: 'Ejecutar normalización de Tokens',
        message:
        'Usuarios seleccionados: ${_selectedMigrationUsers.length}\n\n'
            'Se copiará token/fcm_token a fcmToken si aplica.\n¿Continuar?',
        confirmText: 'Ejecutar',
      );
      if (!ok) return;
    }

    setState(() => _loading = true);

    final result = await _mig.normalizeUserTokensForUsers(
      empresaId: empresaId,
      userIds: _selectedMigrationUsers,
      dryRun: dryRun,
    );

    await _mig.logMigration(
      adminUserId: widget.userId,
      empresaId: empresaId,
      action: 'normalizeUserTokensForUsers',
      scanned: result.scanned,
      updated: result.updated,
      dryRun: dryRun,
      extra: {
        'selectedUsersCount': _selectedMigrationUsers.length,
        'sample': result.sampleUpdatedIds,
      },
    );

    _snack(dryRun
        ? 'SIMULACIÓN Tokens: escaneados ${result.scanned}, a cambiar ${result.updated}'
        : 'Tokens ejecutado: escaneados ${result.scanned}, cambiados ${result.updated}');

    await _loadAll(forceEmpresaId: empresaId);
  }


  // ---------------- MIGRACIONES: ELIMINAR TODAS LAS TAREAS (EMPRESA ACTIVA) ----------------
  Future<bool> _confirmDeleteAllTasks(String empresaId) async {
    final controller = TextEditingController();
    String typed = '';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx2, setLocal) {
            final enabled = typed.trim().toUpperCase() == 'BORRAR';

            return AlertDialog(
              title: const Text('Eliminar todas las tareas', style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.w900)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Empresa activa: $empresaId',
                    style: const TextStyle(fontFamily: kArial, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Esta acción eliminará TODAS las tareas de la empresa activa en TBL_TAREAS. '
                        'No se puede deshacer.',
                    style: TextStyle(fontFamily: kArial),
                  ),
                  const SizedBox(height: 12),
                  const Text('Escribe BORRAR para confirmar:', style: TextStyle(fontFamily: kArial)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: controller,
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                    style: const TextStyle(fontFamily: kArial),
                    onChanged: (v) => setLocal(() => typed = v),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancelar', style: TextStyle(fontFamily: kArial)),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: kAdminPrimary),
                  onPressed: enabled ? () => Navigator.pop(ctx, true) : null,
                  icon: const Icon(Icons.delete_forever),
                  label: const Text('Eliminar', style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.w900)),
                ),
              ],
            );
          },
        );
      },
    );
    return ok == true;
  }

  Future<void> _deleteAllTasksForEmpresa() async {
    final empresaId = _empresaId ?? '';
    if (empresaId.isEmpty) return;

    final ok = await _confirmDeleteAllTasks(empresaId);
    if (!ok) return;

    setState(() => _loading = true);

    const int batchLimit = 400;
    int deleted = 0;

    try {
      while (true) {
        final snap = await FirebaseFirestore.instance
            .collection('TBL_TAREAS')
            .where('empresaId', isEqualTo: empresaId)
            .limit(batchLimit)
            .get();
        if (snap.docs.isEmpty) break;

        final batch = FirebaseFirestore.instance.batch();
        for (final doc in snap.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
        deleted += snap.docs.length;
      }

      await _mig.logMigration(
        adminUserId: widget.userId,
        empresaId: empresaId,
        action: 'deleteAllTasksForEmpresa',
        scanned: deleted,
        updated: deleted,
        dryRun: false,
        extra: {
          'empresaId': empresaId,
        },
      );

      _snack('Tareas eliminadas: $deleted');
    } finally {
      await _loadAll(forceEmpresaId: empresaId);
    }
  }

  // ---------------- LOGS ----------------
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _loadLogs() async {
    final empresaId = _empresaId ?? '';
    if (empresaId.isEmpty) return [];
    try {
      final snap = await FirebaseFirestore.instance
          .collection('TBL_MIGRATIONS_LOGS')
          .where('empresaId', isEqualTo: empresaId)
          .limit(200)
          .get();
      final docs = [...snap.docs];
      docs.sort((a, b) {
        final aTs = (a.data()['createdAt'] as Timestamp?) ?? Timestamp(0, 0);
        final bTs = (b.data()['createdAt'] as Timestamp?) ?? Timestamp(0, 0);
        return bTs.compareTo(aTs);
      });
      return docs.take(50).toList();
    } catch (e) {
      _snack('No fue posible cargar logs: $e');
      return [];
    }
  }

  // ---------------- LIMPIEZA: RESETEAR DATOS DE USUARIOS ----------------
  Future<void> _resetUsersData() async {
    final empresaId = _empresaId ?? '';
    if (empresaId.isEmpty) return;

    final ok = await _confirm(
      title: '⚠ RESETEAR DATOS DE USUARIOS',
      message:
      'Se borrarán Áreas, Cargos, Centros y Jefes de ${_users.length} usuarios en la empresa $empresaId.\n\n'
          'NO se borrarán las cuentas de acceso (correo/clave).\n'
          'Los usuarios quedarán listos para recibir una carga limpia desde Excel.',
      confirmText: 'SÍ, RESETEAR DATOS',
    );
    if (!ok) return;

    setState(() => _loading = true);

    int count = 0;
    WriteBatch batch = FirebaseFirestore.instance.batch();
    bool hasWrites = false;

    Future<void> commitBatch() async {
      if (!hasWrites) return;
      await batch.commit();
      batch = FirebaseFirestore.instance.batch();
      hasWrites = false;
    }

    for (final u in _users) {
      final ref = u.reference;

      final updates = <String, dynamic>{
        'apps': FieldValue.delete(),
        'empresaId': FieldValue.delete(),
        'empresaNombre': FieldValue.delete(),
        'empresas': FieldValue.delete(),
        'empresasDetalle': FieldValue.delete(),
        'empresasDetalle.EMPRESA_001.centroCodigo': FieldValue.delete(),
        'empresasDetalle.EMPRESA_001.centroCostos': FieldValue.delete(),
        'empresasDetalle.EMPRESA_001.centroId': FieldValue.delete(),
        'areaId': FieldValue.delete(),
        'areaNombre': FieldValue.delete(),
        'area': FieldValue.delete(),
        'cargoId': FieldValue.delete(),
        'cargo': FieldValue.delete(),
        'cargoNombre': FieldValue.delete(),
        'cargoJefe': FieldValue.delete(),
        'centroId': FieldValue.delete(),
        'centroCostos': FieldValue.delete(),
        'centro_costos': FieldValue.delete(),
        'centroCodigo': FieldValue.delete(),
        'jefeId': FieldValue.delete(),
        'jefeNombre': FieldValue.delete(),
      };

      batch.update(ref, updates);
      count++;
      hasWrites = true;

      if (count % 400 == 0) {
        await commitBatch();
      }
    }

    await commitBatch();

    await _mig.logMigration(
      adminUserId: widget.userId,
      empresaId: empresaId,
      action: 'RESET_USERS_DATA',
      scanned: count,
      updated: count,
      dryRun: false,
    );

    setState(() => _loading = false);
    _snack('Se resetearon los datos de $count usuarios.');
    await _loadAll(forceEmpresaId: empresaId);
  }

  // ---------------- LIMPIEZA: BORRAR CATÁLOGOS ----------------
  Future<void> _purgeCatalogs() async {
    final empresaId = _empresaId ?? '';
    if (empresaId.isEmpty) return;

    final ok = await _confirm(
      title: '⚠ BORRAR TODOS LOS CATÁLOGOS',
      message:
      'Se eliminarán TODAS las Áreas, Cargos y Centros de Costo de la empresa $empresaId.\n\n'
          'Haz esto solo si vas a volver a subir el archivo Excel completo.\n'
          '¿Estás seguro?',
      confirmText: 'BORRAR TODO',
    );
    if (!ok) return;

    setState(() => _loading = true);
    int deletedCount = 0;

    Future<void> deleteCollection(String collName) async {
      final snap = await FirebaseFirestore.instance
          .collection(collName)
          .where('empresaId', isEqualTo: empresaId)
          .get();
      for (final doc in snap.docs) {
        await doc.reference.delete();
        deletedCount++;
      }
    }

    await deleteCollection('TBL_AREAS');
    await deleteCollection('TBL_CARGOS');
    await deleteCollection('TBL_CENTROS_COSTOS');

    setState(() => _loading = false);
    _snack('Catálogos eliminados. Total documentos borrados: $deletedCount');
    await _loadAll(forceEmpresaId: empresaId);
  }

  // ---------------- LIMPIEZA: BORRAR ESTRUCTURA ORGANIZACIONAL ----------------
  Future<void> _purgeOrganizationalStructure() async {
    final ok = await _confirm(
      title: '⚠ BORRAR ESTRUCTURA ORGANIZACIONAL',
      message:
      'Se eliminarán TODOS los documentos en TBL_ESTRUCTURA_ORGANIZACIONAL.\n\n'
          'Úsalo solo si vas a volver a subir la estructura completa.\n'
          '¿Estás seguro?',
      confirmText: 'BORRAR ESTRUCTURA',
    );
    if (!ok) return;

    setState(() => _loading = true);

    int deletedCount = 0;
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection('TBL_ESTRUCTURA_ORGANIZACIONAL')
        .limit(400);

    while (true) {
      final snap = await query.get();
      if (snap.docs.isEmpty) break;

      WriteBatch batch = FirebaseFirestore.instance.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
        deletedCount++;
      }
      await batch.commit();

      final lastDoc = snap.docs.last;
      query = FirebaseFirestore.instance
          .collection('TBL_ESTRUCTURA_ORGANIZACIONAL')
          .startAfterDocument(lastDoc)
          .limit(400);
    }

    setState(() => _loading = false);
    _snack('Estructura organizacional eliminada. Total documentos borrados: $deletedCount');
    await _loadAll(forceEmpresaId: _empresaId ?? '');
  }


  Future<void> _pickDiagnosticosExcel() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xlsm', 'xls'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) return;

    final file = result.files.single;
    if (file.bytes == null || file.bytes!.isEmpty) {
      _snack('No se pudo leer el archivo seleccionado.');
      return;
    }

    setState(() {
      _diagnosticosFileName = file.name;
      _diagnosticosBytes = file.bytes;
      _diagnosticosImportResult = null;
    });
  }

  Future<void> _importarDiagnosticosExcel() async {
    final empresaId = _empresaId ?? '';
    final bytes = _diagnosticosBytes;

    if (empresaId.isEmpty) {
      _snack('Selecciona una empresa antes de importar diagnósticos.');
      return;
    }
    if (bytes == null || bytes.isEmpty) {
      _snack('Primero selecciona un archivo Excel.');
      return;
    }

    setState(() => _loading = true);
    try {
      final result = await _diagnosticosService.importarDiagnosticosDesdeExcel(
        bytes: bytes,
        empresaId: empresaId,
        sobrescribir: true,
      );
      if (!mounted) return;
      setState(() {
        _diagnosticosImportResult = result;
      });
      _snack(
        'Diagnósticos importados. Médicos: ${result['diagnosticosMedicos'] ?? 0} | Nutricionales: ${result['diagnosticosNutricionales'] ?? 0}',
      );
    } catch (e) {
      _snack('Error importando diagnósticos: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _sembrarReqComprasBase() async {
    if (_empresaId == null || _empresaId!.isEmpty) {
      _snack('Selecciona una empresa primero.');
      return;
    }
    final ok = await _confirm(
      title: 'Cargar requisitos de Compras',
      message:
      'Esto reemplazará los requisitos documentales de Compras de la empresa seleccionada con la parametrización base (incluye proteína, abarrotes y aseo).',
      confirmText: 'Cargar',
    );
    if (!ok) return;

    setState(() => _importandoReqCompras = true);
    try {
      await sembrarReqDocumentos(_empresaId!, ComprasService());
      _snack('Requisitos de Compras cargados correctamente.');
    } catch (e) {
      _snack('Error al cargar requisitos de Compras: $e');
    } finally {
      if (mounted) setState(() => _importandoReqCompras = false);
    }
  }

  Future<void> _pickReqComprasExcel() async {
    final picked = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xlsm', 'xls'],
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.first;
    setState(() {
      _reqComprasFileName = file.name;
      _reqComprasBytes = file.bytes;
      _reqComprasImportResult = null;
    });
  }

  Future<void> _importarReqComprasExcel() async {
    final empresaId = _empresaId ?? '';
    final bytes = _reqComprasBytes;
    if (empresaId.isEmpty) {
      _snack('Selecciona una empresa primero.');
      return;
    }
    if (bytes == null) {
      _snack('Primero selecciona un archivo Excel.');
      return;
    }

    final ok = await _confirm(
      title: 'Importar REQ_DOCUMENTOS desde Excel',
      message:
      'Se reemplazarán los requisitos actuales de Compras para la empresa activa con lo cargado en el Excel.',
      confirmText: 'Importar',
    );
    if (!ok) return;

    setState(() => _importandoReqCompras = true);
    try {
      final parsed = _comprasReqParser.parse(bytes: bytes, empresaId: empresaId);
      if (parsed.docs.isEmpty) {
        _snack('No se detectaron filas válidas en la hoja REQ_DOCUMENTOS.');
        return;
      }

      await ComprasService().importarReqDocumentos(empresaId, parsed.docs);
      if (!mounted) return;
      setState(() {
        _reqComprasImportResult = {
          'importados': parsed.docs.length,
          'omitidos': parsed.skippedRows,
        };
      });
      _snack(
          'Requisitos de Compras importados: ${parsed.docs.length} (omitidos: ${parsed.skippedRows}).');
    } catch (e) {
      _snack('Error al importar requisitos de Compras: $e');
    } finally {
      if (mounted) setState(() => _importandoReqCompras = false);
    }
  }

  Widget _tabReqCompras() {
    final result = _reqComprasImportResult;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          color: kAdminCard,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.rule_folder, color: kAdminPrimary),
                    SizedBox(width: 8),
                    Text(
                      'Requisitos documentales de Compras',
                      style: TextStyle(
                        fontFamily: kArial,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  'Esta sección prepara la aplicación para exigir documentación desde la creación/recepción de productos según categoría (incluyendo proteína).',
                  style: TextStyle(fontFamily: kArial, height: 1.4),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.blue.shade100),
                  ),
                  child: const Text(
                    'Opciones disponibles:\n1) Cargar base REQ_DOCUMENTOS (v3).\n2) Subir tu Excel desde este panel para reemplazar la parametrización.',
                    style: TextStyle(fontFamily: kArial),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _importandoReqCompras ? null : _pickReqComprasExcel,
                  icon: const Icon(Icons.attach_file),
                  label: Text(
                    _reqComprasFileName == null
                        ? 'Seleccionar Excel REQ_DOCUMENTOS'
                        : _reqComprasFileName!,
                    style: const TextStyle(fontFamily: kArial),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F766E),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: _importandoReqCompras ? null : _importarReqComprasExcel,
                    icon: const Icon(Icons.file_upload_outlined),
                    label: const Text(
                      'Importar Excel de requisitos',
                      style: TextStyle(
                        fontFamily: kArial,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kAdminPrimary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: _importandoReqCompras ? null : _sembrarReqComprasBase,
                    icon: _importandoReqCompras
                        ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                        : const Icon(Icons.upload_file),
                    label: Text(
                      _importandoReqCompras
                          ? 'Cargando...'
                          : 'Cargar requisitos base de Compras',
                      style: const TextStyle(
                        fontFamily: kArial,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                if (result != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      border: Border.all(color: Colors.green.shade200),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Última importación: ${result['importados'] ?? 0} filas cargadas • ${result['omitidos'] ?? 0} omitidas.',
                      style: const TextStyle(fontFamily: kArial),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _tabDiagnosticos() {
    final result = _diagnosticosImportResult;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: Colors.teal.shade50,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.teal.shade200),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.upload_file, color: Colors.teal.shade900, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Actualizar diagnósticos',
                        style: TextStyle(
                          fontFamily: kArial,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: Colors.teal.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Sube un Excel con diagnósticos para actualizar el catálogo '
                      'de diagnósticos en Firestore.\n'
                      'Después de importar, el buscador de diagnóstico clínico leerá primero desde Firestore.',
                  style: TextStyle(fontFamily: kArial, height: 1.4),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _pickDiagnosticosExcel,
                  icon: const Icon(Icons.description_outlined),
                  label: const Text(
                    'Seleccionar archivo Excel',
                    style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _diagnosticosFileName == null
                      ? 'Sin archivo seleccionado.'
                      : 'Archivo: $_diagnosticosFileName',
                  style: const TextStyle(fontFamily: kArial),
                ),
                if (result != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Última carga → Médicos: ${result['diagnosticosMedicos'] ?? 0} | Nutricionales: ${result['diagnosticosNutricionales'] ?? 0}',
                    style: const TextStyle(
                      fontFamily: kArial,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: _importarDiagnosticosExcel,
                    icon: const Icon(Icons.cloud_upload),
                    label: const Text(
                      'IMPORTAR DIAGNÓSTICOS',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _tabCleanup() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: Colors.orange.shade50,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.orange.shade200),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.person_remove_outlined, color: Colors.orange.shade900, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Resetear datos de Usuarios',
                        style: TextStyle(
                          fontFamily: kArial,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: Colors.orange.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Esta opción NO borra al usuario ni su contraseña. Borra apps, empresa, cargos, áreas, centros y jefes.\n'
                      'Úsalo antes de subir un Excel actualizado.',
                  style: TextStyle(fontFamily: kArial, height: 1.4),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange.shade800,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: _resetUsersData,
                    icon: const Icon(Icons.cleaning_services),
                    label: const Text('LIMPIAR DATOS DE USUARIOS', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Card(
          color: Colors.red.shade50,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.red.shade200),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.account_tree_outlined, color: Colors.red.shade900, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Purgar Estructura Organizacional',
                        style: TextStyle(
                          fontFamily: kArial,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: Colors.red.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Elimina TODOS los documentos de TBL_ESTRUCTURA_ORGANIZACIONAL para esta empresa.',
                  style: TextStyle(fontFamily: kArial, height: 1.4),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade800,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: _purgeOrganizationalStructure,
                    icon: const Icon(Icons.delete_forever),
                    label: const Text('BORRAR ESTRUCTURA', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Card(
          color: Colors.red.shade50,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.red.shade200),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.folder_delete_outlined, color: Colors.red.shade900, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Purgar Catálogos (Áreas/Cargos)',
                        style: TextStyle(
                          fontFamily: kArial,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: Colors.red.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Elimina TODAS las Áreas, Cargos y Centros de esta empresa. Úsalo si vas a re-subir la estructura completa.',
                  style: TextStyle(fontFamily: kArial, height: 1.4),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade800,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: _purgeCatalogs,
                    icon: const Icon(Icons.delete_sweep),
                    label: const Text('BORRAR TODOS LOS CATÁLOGOS', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        scaffoldBackgroundColor: kAdminBg,
        appBarTheme: const AppBarTheme(
          backgroundColor: kAdminPrimary,
          foregroundColor: Colors.white,
          centerTitle: false,
        ),
      ),
      child: DefaultTabController(
        length: 9,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Admin Dashboard', style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.w900)),
            bottom: const TabBar(
              isScrollable: true,
              indicatorColor: kAdminAccent,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              labelStyle: TextStyle(fontFamily: kArial, fontWeight: FontWeight.w800),
              tabs: [
                Tab(icon: Icon(Icons.people_alt), text: 'Usuarios'),
                Tab(icon: Icon(Icons.apps), text: 'Apps'),
                Tab(icon: Icon(Icons.account_tree), text: 'Catálogos'),
                Tab(icon: Icon(Icons.construction), text: 'Migraciones'),
                Tab(icon: Icon(Icons.history), text: 'Logs'),
                Tab(icon: Icon(Icons.cleaning_services), text: 'Limpieza'),
                Tab(icon: Icon(Icons.medical_information), text: 'Diagnósticos'),
                Tab(icon: Icon(Icons.rule_folder), text: 'Req. Compras'),
                Tab(icon: Icon(Icons.verified_user), text: 'Roles Compras'),
              ],
            ),
          ),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : Column(
            children: [
              _buildEmpresaHeader(),
              const Divider(height: 0),
              Expanded(
                child: TabBarView(
                  children: [
                    _tabUsuarios(),
                    _tabApps(),
                    _tabCatalogos(),
                    _tabMigraciones(),
                    _tabLogs(),
                    _tabCleanup(),
                    _tabDiagnosticos(),
                    _tabReqCompras(),
                    _tabRolesCompras(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmpresaHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Card(
        color: kAdminCard,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Icon(Icons.business, color: kAdminPrimary),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _empresaId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Empresa activa',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: _empresas
                      .map((e) => DropdownMenuItem(
                    value: e.empresaId,
                    child: Text('${e.nombre} (${e.empresaId})',
                        style: const TextStyle(fontFamily: kArial, fontWeight: FontWeight.w700)),
                  ))
                      .toList(),
                  onChanged: (v) async {
                    if (v == null || v.isEmpty) return;
                    await _loadAll(forceEmpresaId: v);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------- TAB: USUARIOS ----------------
  Widget _tabUsuarios() {
    final filtered = _users.where((u) {
      final d = u.data();
      final name = _userName(d, u.id).toLowerCase();
      final ced = _safe(d['cedula']).toLowerCase();
      final cargo = _safe(d['cargo']).toLowerCase();
      final s = _userSearch.toLowerCase();
      if (s.isEmpty) return true;
      return name.contains(s) || ced.contains(s) || u.id.toLowerCase().contains(s) || cargo.contains(s);
    }).toList();

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Card(
            color: kAdminCard,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: TextField(
                decoration: const InputDecoration(
                  labelText: 'Buscar usuario (nombre, cédula, cargo)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.search),
                ),
                style: const TextStyle(fontFamily: kArial),
                onChanged: (v) => setState(() => _userSearch = v.trim()),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.separated(
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final uDoc = filtered[i];
                final d = uDoc.data();
                final nombre = _userName(d, uDoc.id);
                final cedula = _safe(d['cedula']).isNotEmpty ? _safe(d['cedula']) : uDoc.id;
                final cargo = _safe(d['cargo']);
                final centro = _safe(d['centroCostos']);
                final area = _safe(d['areaNombre']);
                final apps = (_userApps[uDoc.id] ?? {}).toList()..sort();

                return Card(
                  color: kAdminCard,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const CircleAvatar(
                              backgroundColor: kAdminPrimary,
                              foregroundColor: Colors.white,
                              child: Icon(Icons.person),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(nombre, style: const TextStyle(fontFamily: kArial, fontWeight: FontWeight.w900)),
                                  const SizedBox(height: 2),
                                  Text('Cédula/ID: $cedula', style: const TextStyle(fontFamily: kArial, fontSize: 12)),
                                  if (cargo.isNotEmpty) Text('Cargo: $cargo', style: const TextStyle(fontFamily: kArial, fontSize: 12)),
                                  if (centro.isNotEmpty || area.isNotEmpty)
                                    Text('Centro: $centro  •  Área: $area',
                                        style: const TextStyle(fontFamily: kArial, fontSize: 12)),
                                ],
                              ),
                            ),
                            PopupMenuButton<String>(
                              onSelected: (v) async {
                                if (v == 'apps') await _editUserApps(uDoc);
                                if (v == 'org') await _editUserOrg(uDoc);
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(value: 'org', child: Text('Editar centro/área/cargo', style: TextStyle(fontFamily: kArial))),
                                PopupMenuItem(value: 'apps', child: Text('Asignar apps', style: TextStyle(fontFamily: kArial))),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (apps.isEmpty)
                          const Text('Apps: (sin asignar)', style: TextStyle(fontFamily: kArial, fontSize: 12))
                        else
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: apps
                                .map((a) => Chip(
                              backgroundColor: const Color(0xFFE6F0FF),
                              label: Text(a, style: const TextStyle(fontFamily: kArial, fontSize: 12, fontWeight: FontWeight.w700)),
                            ))
                                .toList(),
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
    );
  }

  // ---------------- TAB: APPS ----------------
  Widget _tabApps() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _sectionHeader(title: 'Apps (TBL_APPS)', onAdd: () => _dialogApp()),
        const SizedBox(height: 8),
        if (_appsAdmin.isEmpty)
          const Text(
            'No hay apps registradas.',
            style: TextStyle(fontFamily: kArial, fontSize: 12),
          )
        else
          ..._appsAdmin.map((aDoc) {
            final a = aDoc.data();
            final appId = _safe(a['appId']).isNotEmpty ? _safe(a['appId']) : aDoc.id;
            final nombre = _safe(a['nombre']).isNotEmpty ? _safe(a['nombre']) : appId;
            final descripcion = _safe(a['descripcion']);
            final enabled = (a['enabled'] as bool?) ?? true;

            return _catalogTile(
              title: nombre,
              subtitle: appId,
              enabled: enabled,
              trailing2: descripcion.isNotEmpty
                  ? Text(
                descripcion,
                style: const TextStyle(
                  fontFamily: kArial,
                  fontSize: 11,
                  color: Colors.black54,
                ),
              )
                  : null,
              onEdit: () => _dialogApp(existing: aDoc),
              onToggle: (v) async {
                await _repo.setAppEnabled(aDoc.id, v);
                _snack('App actualizada');
                await _loadAll(forceEmpresaId: _empresaId);
              },
            );
          }),
      ],
    );
  }

  // ---------------- TAB: CATALOGOS ----------------
  Widget _tabCatalogos() {
    final centros = _centros.toList();
    final areas = _areas.toList();
    final cargos = _cargos.toList();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _sectionHeader(title: 'Centros de costos (TBL_CENTROS_COSTOS)', onAdd: () => _dialogCentro()),
        const SizedBox(height: 8),
        ...centros.map((c) => _catalogTile(
          title: '${c.codigo} - ${c.nombre}',
          subtitle: c.centroId,
          enabled: c.enabled,
          onEdit: () => _dialogCentro(existing: c),
          onToggle: (v) async {
            await _repo.setCentroEnabled(c.centroId, v);
            _snack('Centro actualizado');
            await _loadAll(forceEmpresaId: _empresaId);
          },
        )),
        const SizedBox(height: 18),

        _sectionHeader(title: 'Áreas (TBL_AREAS)', onAdd: () => _dialogArea()),
        const SizedBox(height: 8),
        ...areas.map((a) => _catalogTile(
          title: a.nombre,
          subtitle: a.areaId,
          enabled: a.enabled,
          onEdit: () => _dialogArea(existing: a),
          onToggle: (v) async {
            await _repo.setAreaEnabled(a.areaId, v);
            _snack('Área actualizada');
            await _loadAll(forceEmpresaId: _empresaId);
          },
        )),
        const SizedBox(height: 18),

        _sectionHeader(title: 'Cargos (TBL_CARGOS)', onAdd: () => _dialogCargo()),
        const SizedBox(height: 8),
        ...cargos.map((c) => _catalogTile(
          title: c.nombre,
          subtitle: c.cargoId,
          enabled: c.enabled,
          trailing2: Text(
            [
              if (c.centroId != null) 'Centro:${c.centroId}',
              if (c.areaId != null) 'Área:${c.areaId}',
            ].join('  •  '),
            style: const TextStyle(fontFamily: kArial, fontSize: 11, color: Colors.black54),
          ),
          onEdit: () => _dialogCargo(existing: c),
          onToggle: (v) async {
            await _repo.setCargoEnabled(c.cargoId, v);
            _snack('Cargo actualizado');
            await _loadAll(forceEmpresaId: _empresaId);
          },
        )),
      ],
    );
  }

  Future<void> _dialogApp({
    QueryDocumentSnapshot<Map<String, dynamic>>? existing,
  }) async {
    final empresaId = _empresaId ?? '';
    if (empresaId.isEmpty) return;

    final data = existing?.data() ?? <String, dynamic>{};
    final existingAppId =
    _safe(data['appId']).isNotEmpty ? _safe(data['appId']) : existing?.id ?? '';
    String appId = existingAppId;
    String nombre = _safe(data['nombre']);
    String descripcion = _safe(data['descripcion']);
    bool enabled = (data['enabled'] as bool?) ?? true;
    final isNew = existing == null;

    await showDialog(
      context: context,
      builder: (_) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: Text(
                isNew ? 'Agregar app' : 'Editar app',
                style: const TextStyle(
                  fontFamily: kArial,
                  fontWeight: FontWeight.w900,
                  color: kAdminPrimary,
                ),
              ),
              content: SizedBox(
                width: 560,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      initialValue: appId,
                      readOnly: !isNew,
                      decoration: const InputDecoration(
                        labelText: 'appId (Ej: NutricionDashboard)',
                        border: OutlineInputBorder(),
                      ),
                      style: const TextStyle(fontFamily: kArial),
                      onChanged: (v) => appId = v.trim(),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      initialValue: nombre,
                      decoration: const InputDecoration(
                        labelText: 'Nombre visible',
                        border: OutlineInputBorder(),
                      ),
                      style: const TextStyle(fontFamily: kArial),
                      onChanged: (v) => nombre = v.trim(),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      initialValue: descripcion,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Descripción',
                        border: OutlineInputBorder(),
                      ),
                      style: const TextStyle(fontFamily: kArial),
                      onChanged: (v) => descripcion = v.trim(),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      value: enabled,
                      activeColor: kAdminAccent,
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Habilitada',
                        style: TextStyle(fontFamily: kArial),
                      ),
                      onChanged: (v) => setLocal(() => enabled = v),
                    ),
                    if (isNew)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          'Se guardará con docId: empresaId_appId',
                          style: TextStyle(fontFamily: kArial, fontSize: 11, color: Colors.black54),
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar', style: TextStyle(fontFamily: kArial)),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.save),
                  style: ElevatedButton.styleFrom(backgroundColor: kAdminPrimary),
                  onPressed: () async {
                    if (appId.trim().isEmpty || nombre.trim().isEmpty) {
                      _snack('appId y nombre son obligatorios');
                      return;
                    }
                    await _repo.upsertApp(
                      empresaId: empresaId,
                      appId: appId.trim(),
                      nombre: nombre.trim(),
                      descripcion: descripcion.trim().isEmpty ? null : descripcion.trim(),
                      enabled: enabled,
                      isNew: isNew,
                    );
                    if (!mounted) return;
                    Navigator.pop(ctx);
                    _snack(isNew ? 'App creada' : 'App actualizada');
                    await _loadAll(forceEmpresaId: _empresaId);
                  },
                  label: const Text(
                    'Guardar',
                    style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _sectionHeader({required String title, required VoidCallback onAdd}) {
    return Row(
      children: [
        Expanded(child: Text(title, style: const TextStyle(fontFamily: kArial, fontWeight: FontWeight.w900, fontSize: 14))),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(backgroundColor: kAdminPrimary),
          onPressed: onAdd,
          icon: const Icon(Icons.add),
          label: const Text('Agregar', style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.w900)),
        ),
      ],
    );
  }

  Widget _catalogTile({
    required String title,
    required String subtitle,
    required bool enabled,
    required VoidCallback onEdit,
    required ValueChanged<bool> onToggle,
    Widget? trailing2,
  }) {
    return Card(
      color: kAdminCard,
      child: ListTile(
        title: Text(title, style: const TextStyle(fontFamily: kArial, fontWeight: FontWeight.w900)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(subtitle, style: const TextStyle(fontFamily: kArial, fontSize: 12, color: Colors.black54)),
            if (trailing2 != null) trailing2,
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(value: enabled, activeColor: kAdminAccent, onChanged: onToggle),
            IconButton(icon: const Icon(Icons.edit, color: kAdminPrimary), onPressed: onEdit),
          ],
        ),
      ),
    );
  }

  // ---------------- TAB: MIGRACIONES (solo usuarios seleccionados) ----------------
  Widget _tabMigraciones() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          color: kAdminCard,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Migraciones por usuario (no global)',
                    style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.w900, fontSize: 16, color: kAdminPrimary)),
                const SizedBox(height: 6),
                const Text(
                  'Primero selecciona usuarios. Luego puedes simular o ejecutar.',
                  style: TextStyle(fontFamily: kArial, fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickMigrationUsers,
                        icon: const Icon(Icons.people_alt),
                        label: Text(
                          _selectedMigrationUsers.isEmpty
                              ? 'Seleccionar usuarios'
                              : 'Usuarios seleccionados: ${_selectedMigrationUsers.length}',
                          style: const TextStyle(fontFamily: kArial, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (_selectedMigrationUsers.isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: () => setState(() => _selectedMigrationUsers.clear()),
                        icon: const Icon(Icons.clear),
                        label: const Text('Limpiar', style: TextStyle(fontFamily: kArial)),
                      ),
                  ],
                ),

                if (_selectedMigrationUsers.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: _selectedMigrationUsers
                        .take(12)
                        .map((id) => Chip(
                      backgroundColor: const Color(0xFFE8FBFF),
                      label: Text(id, style: const TextStyle(fontFamily: kArial, fontSize: 11, fontWeight: FontWeight.w700)),
                    ))
                        .toList(),
                  ),
                  if (_selectedMigrationUsers.length > 12)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('y ${_selectedMigrationUsers.length - 12} más...',
                          style: const TextStyle(fontFamily: kArial, fontSize: 12, color: Colors.black54)),
                    ),
                ],
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        Card(
          color: kAdminCard,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Centro de costos → SOLO usuarios seleccionados',
                    style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _runNormalizeCentroSelectedUsers(dryRun: true),
                        icon: const Icon(Icons.visibility),
                        label: const Text('Simular', style: TextStyle(fontFamily: kArial)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: kAdminPrimary),
                        onPressed: () => _runNormalizeCentroSelectedUsers(dryRun: false),
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Ejecutar', style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.w900)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        Card(
          color: kAdminCard,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Tokens (fcmToken) → SOLO usuarios seleccionados',
                    style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _runNormalizeTokensSelectedUsers(dryRun: true),
                        icon: const Icon(Icons.visibility),
                        label: const Text('Simular', style: TextStyle(fontFamily: kArial)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: kAdminPrimary),
                        onPressed: () => _runNormalizeTokensSelectedUsers(dryRun: false),
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Ejecutar', style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.w900)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        Card(
          color: kAdminCard,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Eliminar todas las tareas (empresa activa)',
                  style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Útil para reiniciar el entorno en periodo de prueba.',
                  style: TextStyle(fontFamily: kArial, fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700),
                    onPressed: _deleteAllTasksForEmpresa,
                    icon: const Icon(Icons.delete_forever),
                    label: const Text(
                      'Eliminar todas las tareas',
                      style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ---------------- TAB: LOGS ----------------
  Widget _tabLogs() {
    return FutureBuilder(
      future: _loadLogs(),
      builder: (context, AsyncSnapshot<List<QueryDocumentSnapshot<Map<String, dynamic>>>> snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snap.data ?? [];
        if (docs.isEmpty) return const Center(child: Text('Sin logs', style: TextStyle(fontFamily: kArial)));

        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) {
            final d = docs[i].data();
            final action = (d['action'] ?? '').toString();
            final scanned = (d['scanned'] ?? 0).toString();
            final updated = (d['updated'] ?? 0).toString();
            final dryRun = (d['dryRun'] as bool?) ?? false;

            return Card(
              color: kAdminCard,
              child: ListTile(
                leading: const Icon(Icons.bolt, color: kAdminAccent),
                title: Text(action, style: const TextStyle(fontFamily: kArial, fontWeight: FontWeight.w900)),
                subtitle: Text(
                  'Scanned: $scanned • Updated: $updated • ${dryRun ? "SIMULACIÓN" : "EJECUTADO"}',
                  style: const TextStyle(fontFamily: kArial),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ======= Dialogs Catálogos (reutiliza los de tu versión anterior) =======
  Future<void> _dialogCentro({CentroCostoItem? existing}) async {
    final empresaId = _empresaId ?? '';
    if (empresaId.isEmpty) return;

    final idCtrl = TextEditingController(text: existing?.centroId ?? '');
    final codCtrl = TextEditingController(text: existing?.codigo ?? '');
    final nomCtrl = TextEditingController(text: existing?.nombre ?? '');
    bool enabled = existing?.enabled ?? true;

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(existing == null ? 'Nuevo centro' : 'Editar centro',
            style: const TextStyle(fontFamily: kArial, fontWeight: FontWeight.w900)),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: idCtrl,
                enabled: existing == null,
                decoration: const InputDecoration(labelText: 'centroId (docId)', border: OutlineInputBorder()),
                style: const TextStyle(fontFamily: kArial),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: codCtrl,
                decoration: const InputDecoration(labelText: 'Código (ej: CC001)', border: OutlineInputBorder()),
                style: const TextStyle(fontFamily: kArial),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: nomCtrl,
                decoration: const InputDecoration(labelText: 'Nombre', border: OutlineInputBorder()),
                style: const TextStyle(fontFamily: kArial),
              ),
              const SizedBox(height: 10),
              SwitchListTile(
                value: enabled,
                activeColor: kAdminAccent,
                onChanged: (v) => setState(() => enabled = v),
                title: const Text('Habilitado', style: TextStyle(fontFamily: kArial)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar', style: TextStyle(fontFamily: kArial))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kAdminPrimary),
            onPressed: () async {
              final centroId = idCtrl.text.trim();
              final codigo = codCtrl.text.trim();
              final nombre = nomCtrl.text.trim();

              if (centroId.isEmpty || codigo.isEmpty || nombre.isEmpty) {
                _snack('Completa centroId, código y nombre');
                return;
              }

              await _repo.upsertCentro(
                empresaId: empresaId,
                centroId: centroId,
                codigo: codigo,
                nombre: nombre,
                enabled: enabled,
              );
              if (!mounted) return;
              Navigator.pop(context);
              _snack('Centro guardado');
              await _loadAll(forceEmpresaId: _empresaId);
            },
            child: const Text('Guardar', style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }

  Future<void> _dialogArea({AreaItem? existing}) async {
    final empresaId = _empresaId ?? '';
    if (empresaId.isEmpty) return;

    final idCtrl = TextEditingController(text: existing?.areaId ?? '');
    final nomCtrl = TextEditingController(text: existing?.nombre ?? '');
    bool enabled = existing?.enabled ?? true;

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(existing == null ? 'Nueva área' : 'Editar área',
            style: const TextStyle(fontFamily: kArial, fontWeight: FontWeight.w900)),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: idCtrl,
                enabled: existing == null,
                decoration: const InputDecoration(labelText: 'areaId (docId)', border: OutlineInputBorder()),
                style: const TextStyle(fontFamily: kArial),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: nomCtrl,
                decoration: const InputDecoration(labelText: 'Nombre', border: OutlineInputBorder()),
                style: const TextStyle(fontFamily: kArial),
              ),
              const SizedBox(height: 10),
              SwitchListTile(
                value: enabled,
                activeColor: kAdminAccent,
                onChanged: (v) => setState(() => enabled = v),
                title: const Text('Habilitado', style: TextStyle(fontFamily: kArial)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar', style: TextStyle(fontFamily: kArial))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kAdminPrimary),
            onPressed: () async {
              final areaId = idCtrl.text.trim();
              final nombre = nomCtrl.text.trim();
              if (areaId.isEmpty || nombre.isEmpty) {
                _snack('Completa areaId y nombre');
                return;
              }
              await _repo.upsertArea(empresaId: empresaId, areaId: areaId, nombre: nombre, enabled: enabled);
              if (!mounted) return;
              Navigator.pop(context);
              _snack('Área guardada');
              await _loadAll(forceEmpresaId: _empresaId);
            },
            child: const Text('Guardar', style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }

  Future<void> _dialogCargo({CargoItem? existing}) async {
    final empresaId = _empresaId ?? '';
    if (empresaId.isEmpty) return;

    final idCtrl = TextEditingController(text: existing?.cargoId ?? '');
    final nomCtrl = TextEditingController(text: existing?.nombre ?? '');
    bool enabled = existing?.enabled ?? true;

    CentroCostoItem? centroSel = existing?.centroId == null
        ? null
        : _centros.where((c) => c.centroId == existing!.centroId).cast<CentroCostoItem?>().firstWhere((x) => x != null, orElse: () => null);
    AreaItem? areaSel = existing?.areaId == null
        ? null
        : _areas.where((a) => a.areaId == existing!.areaId).cast<AreaItem?>().firstWhere((x) => x != null, orElse: () => null);

    final centrosEnabled = _centros.where((c) => c.enabled).toList();
    final areasEnabled = _areas.where((a) => a.enabled).toList();

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(existing == null ? 'Nuevo cargo' : 'Editar cargo',
            style: const TextStyle(fontFamily: kArial, fontWeight: FontWeight.w900)),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: idCtrl,
                enabled: existing == null,
                decoration: const InputDecoration(labelText: 'cargoId (docId)', border: OutlineInputBorder()),
                style: const TextStyle(fontFamily: kArial),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: nomCtrl,
                decoration: const InputDecoration(labelText: 'Nombre', border: OutlineInputBorder()),
                style: const TextStyle(fontFamily: kArial),
              ),
              const SizedBox(height: 10),

              DropdownButtonFormField<CentroCostoItem>(
                value: centroSel,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Centro (opcional)', border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem<CentroCostoItem>(value: null, child: Text('—', style: TextStyle(fontFamily: kArial))),
                  ...centrosEnabled.map((c) => DropdownMenuItem(
                    value: c,
                    child: Text('${c.codigo} - ${c.nombre}', style: const TextStyle(fontFamily: kArial)),
                  )),
                ],
                onChanged: (v) => centroSel = v,
              ),
              const SizedBox(height: 10),

              DropdownButtonFormField<AreaItem>(
                value: areaSel,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Área (opcional)', border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem<AreaItem>(value: null, child: Text('—', style: TextStyle(fontFamily: kArial))),
                  ...areasEnabled.map((a) => DropdownMenuItem(
                    value: a,
                    child: Text(a.nombre, style: const TextStyle(fontFamily: kArial)),
                  )),
                ],
                onChanged: (v) => areaSel = v,
              ),

              const SizedBox(height: 10),
              SwitchListTile(
                value: enabled,
                activeColor: kAdminAccent,
                onChanged: (v) => setState(() => enabled = v),
                title: const Text('Habilitado', style: TextStyle(fontFamily: kArial)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar', style: TextStyle(fontFamily: kArial))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kAdminPrimary),
            onPressed: () async {
              final cargoId = idCtrl.text.trim();
              final nombre = nomCtrl.text.trim();
              if (cargoId.isEmpty || nombre.isEmpty) {
                _snack('Completa cargoId y nombre');
                return;
              }
              await _repo.upsertCargo(
                empresaId: empresaId,
                cargoId: cargoId,
                nombre: nombre,
                centroId: centroSel?.centroId,
                areaId: areaSel?.areaId,
                enabled: enabled,
              );
              if (!mounted) return;
              Navigator.pop(context);
              _snack('Cargo guardado');
              await _loadAll(forceEmpresaId: _empresaId);
            },
            child: const Text('Guardar', style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }

  // ── Tab Roles Compras ─────────────────────────────────────────────────────

  Widget _tabRolesCompras() {
    final empresaId = _empresaId ?? '';
    if (empresaId.isEmpty) {
      return const Center(
        child: Text('Selecciona una empresa',
            style: TextStyle(fontFamily: kArial)),
      );
    }
    final svc = ComprasService();
    final roles = [kRolCalidad, kRolCompras, kRolBodega];
    final rolesLabels = {
      kRolCalidad: 'Calidad',
      kRolCompras: 'Compras',
      kRolBodega: 'Bodega',
    };
    final rolesIcons = {
      kRolCalidad: Icons.verified_user,
      kRolCompras: Icons.shopping_cart,
      kRolBodega: Icons.warehouse,
    };
    final rolesColors = {
      kRolCalidad: Colors.green.shade700,
      kRolCompras: kAdminPrimary,
      kRolBodega: Colors.blue.shade700,
    };

    return StreamBuilder<List<ComprasRolDoc>>(
      stream: svc.streamComprasRoles(empresaId),
      builder: (ctx, snapRoles) {
        final rolesActuales = snapRoles.data ?? [];
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Card(
              color: kAdminCard,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.verified_user, color: kAdminPrimary),
                        SizedBox(width: 8),
                        Text(
                          'Roles en Compras & Bodega',
                          style: TextStyle(
                            fontFamily: kArial,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Asigna a cada usuario su rol en el módulo de Compras. '
                      'Calidad: aprueba documentos. Compras: gestiona proveedores/productos. '
                      'Bodega: solo recepción de mercancía.',
                      style: TextStyle(fontFamily: kArial, fontSize: 13, height: 1.4),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Roles actuales
            if (rolesActuales.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Text('Roles asignados',
                    style: TextStyle(
                        fontFamily: kArial,
                        fontWeight: FontWeight.bold,
                        fontSize: 14)),
              ),
              ...rolesActuales.map((r) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor:
                            (rolesColors[r.rol] ?? kAdminPrimary)
                                .withOpacity(0.15),
                        child: Icon(
                          rolesIcons[r.rol] ?? Icons.person,
                          color: rolesColors[r.rol] ?? kAdminPrimary,
                          size: 20,
                        ),
                      ),
                      title: Text(r.nombre,
                          style: const TextStyle(
                              fontFamily: kArial,
                              fontWeight: FontWeight.w600)),
                      subtitle: Text(
                          '${rolesLabels[r.rol] ?? r.rol} · ${r.cedula}',
                          style: const TextStyle(
                              fontFamily: kArial, fontSize: 12)),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline,
                            color: Colors.red),
                        tooltip: 'Quitar rol',
                        onPressed: () async {
                          final ok = await _confirm(
                            title: 'Quitar rol',
                            message:
                                '¿Quitar el rol de ${rolesLabels[r.rol]} a ${r.nombre}?',
                            confirmText: 'Quitar',
                          );
                          if (ok) {
                            await svc.eliminarComprasRol(r.id);
                            _snack('Rol eliminado');
                          }
                        },
                      ),
                    ),
                  )),
              const Divider(height: 24),
            ],
            // Asignar nuevo rol
            const Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: Text('Asignar rol a usuario',
                  style: TextStyle(
                      fontFamily: kArial,
                      fontWeight: FontWeight.bold,
                      fontSize: 14)),
            ),
            ..._users.map((userDoc) {
              final data = userDoc.data();
              final nombre = _userName(data, userDoc.id);
              final cedula = _safe(data['cedula']);
              final userId = userDoc.id;
              // Rol actual del usuario
              ComprasRolDoc? rolActual;
              try {
                rolActual = rolesActuales.firstWhere(
                    (r) => r.userId == userId || r.cedula == cedula);
              } catch (_) {}

              return Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(nombre,
                                style: const TextStyle(
                                    fontFamily: kArial,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13)),
                            Text(cedula,
                                style: const TextStyle(
                                    fontFamily: kArial,
                                    fontSize: 11,
                                    color: Colors.black54)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      DropdownButton<String>(
                        value: rolActual?.rol,
                        hint: const Text('Sin rol',
                            style: TextStyle(
                                fontFamily: kArial, fontSize: 12)),
                        items: [
                          const DropdownMenuItem<String>(
                            value: null,
                            child: Text('Sin rol',
                                style: TextStyle(
                                    fontFamily: kArial, fontSize: 12)),
                          ),
                          ...roles.map((r) => DropdownMenuItem<String>(
                                value: r,
                                child: Row(
                                  children: [
                                    Icon(rolesIcons[r],
                                        size: 14,
                                        color: rolesColors[r]),
                                    const SizedBox(width: 4),
                                    Text(rolesLabels[r] ?? r,
                                        style: const TextStyle(
                                            fontFamily: kArial,
                                            fontSize: 12)),
                                  ],
                                ),
                              )),
                        ],
                        onChanged: (nuevoRol) async {
                          if (nuevoRol == null) {
                            // Quitar rol si existe
                            if (rolActual != null) {
                              await svc.eliminarComprasRol(rolActual.id);
                              _snack('Rol eliminado de $nombre');
                            }
                            return;
                          }
                          final doc = ComprasRolDoc(
                            id: rolActual?.id ?? '',
                            empresaId: empresaId,
                            userId: userId,
                            cedula: cedula,
                            nombre: nombre,
                            rol: nuevoRol,
                            createdAt: Timestamp.now(),
                          );
                          await svc.guardarComprasRol(
                              doc, isNew: rolActual == null);
                          _snack(
                              'Rol ${rolesLabels[nuevoRol]} asignado a $nombre');
                        },
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }
}
