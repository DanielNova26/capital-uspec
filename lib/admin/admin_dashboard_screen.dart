import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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
  Map<String, Set<String>> _userApps = {};

  // Catálogos
  List<CentroCostoItem> _centros = [];
  List<AreaItem> _areas = [];
  List<CargoItem> _cargos = [];

  // UI
  String _userSearch = '';

  // Migración: selección de usuarios
  Set<String> _selectedMigrationUsers = {};

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
    final centros = await _repo.loadCentros(selected);
    final areas = await _repo.loadAreas(selected);
    final cargos = await _repo.loadCargos(selected);

    setState(() {
      _empresas = empresas;
      _empresaId = selected;

      _users = users;
      _apps = apps;

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

  // ---------------- LOGS ----------------
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _loadLogs() async {
    final empresaId = _empresaId ?? '';
    if (empresaId.isEmpty) return [];
    final snap = await FirebaseFirestore.instance
        .collection('TBL_MIGRATIONS_LOGS')
        .where('empresaId', isEqualTo: empresaId)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .get();
    return snap.docs;
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
        length: 4,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Admin Dashboard', style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.w900)),
            bottom: const TabBar(
              indicatorColor: kAdminAccent,
              labelStyle: TextStyle(fontFamily: kArial, fontWeight: FontWeight.w800),
              tabs: [
                Tab(icon: Icon(Icons.people_alt), text: 'Usuarios'),
                Tab(icon: Icon(Icons.account_tree), text: 'Catálogos'),
                Tab(icon: Icon(Icons.construction), text: 'Migraciones'),
                Tab(icon: Icon(Icons.history), text: 'Logs'),
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
                    _tabCatalogos(),
                    _tabMigraciones(),
                    _tabLogs(),
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
}
