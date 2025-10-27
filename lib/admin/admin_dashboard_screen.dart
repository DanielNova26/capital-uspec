// lib/admin/admin_dashboard_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../home/app_drawer.dart';

const Color kMarronOscuro = Color(0xffc28942);
const Color kMarronClaro  = Color(0xffe19e4c);
const String kArial       = 'Arial';

class AdminDashboardScreen extends StatefulWidget {
  final String userId; // cédula del usuario que abre el panel (admin)
  const AdminDashboardScreen({Key? key, required this.userId}) : super(key: key);

  @override
  _AdminDashboardScreenState createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen>
    with SingleTickerProviderStateMixin {
  final _db = FirebaseFirestore.instance;

  late final TabController _tabController;

  bool _loading = true;
  String _empresaId = '';

  // Data Firestore
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _users = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _roles = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _apps  = []; // catálogo para asignar en ROLES

  // Estado UI
  Map<String, String> _userRoleMap = {}; // userId -> roleName

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this); // Usuarios · Roles
    _loadAll();
    _tabController.addListener(() => setState(() {})); // refrescar FAB según pestaña
  }

  // ------------------------ CARGA INICIAL ------------------------
  Future<void> _loadAll() async {
    setState(() => _loading = true);

    // 1) empresaId del admin logueado
    final yo = await _db.collection('TBL_USUARIOS').doc(widget.userId).get();
    final dataYo = yo.data() ?? {};
    final empresaId = (dataYo['empresaId'] as String?)?.trim() ?? '';

    // 2) cargar por empresa
    final usersSnap = await _db
        .collection('TBL_USUARIOS')
        .where('empresaId', isEqualTo: empresaId)
        .get();

    final rolesSnap = await _db
        .collection('TBL_ROLES')
        .where('empresaId', isEqualTo: empresaId)
        .get();

    // Traemos las apps disponibles para ASIGNAR EN ROLES (solo enabled)
    final appsSnap = await _db
        .collection('TBL_APPS')
        .where('empresaId', isEqualTo: empresaId)
        .where('enabled', isEqualTo: true)
        .get();

    setState(() {
      _empresaId   = empresaId;
      _users       = usersSnap.docs;
      _roles       = rolesSnap.docs;
      _apps        = appsSnap.docs;
      _userRoleMap = {
        for (var u in _users) u.id: _safeStr(u.data()['role']),
      };
      _loading = false;
    });
  }

  // ------------------------ HELPERS ------------------------
  String _safeStr(dynamic v) => v == null ? '' : v.toString().trim();

  String _userDisplayName(Map<String, dynamic> d, String fallback) {
    final n = _safeStr(d['nombres']).isNotEmpty
        ? _safeStr(d['nombres'])
        : _safeStr(d['primerNombre']);
    final a = _safeStr(d['apellidos']).isNotEmpty
        ? _safeStr(d['apellidos'])
        : _safeStr(d['primerApellido']);
    final full = ('$n $a').trim();
    return full.isEmpty ? fallback : full;
  }

  String _prettyFromAppId(String appId) {
    // fallback si falta 'nombre'
    var s = appId.replaceAll('_', ' ').replaceAll('-', ' ');
    s = s.replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}');
    s = s
        .split(RegExp(r'\s+'))
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
        .join(' ');
    return s.trim();
  }

  // ------------------------ USUARIOS ------------------------
  Future<void> _saveUserRoles() async {
    final batch = _db.batch();
    for (final u in _users) {
      final newRole = _safeStr(_userRoleMap[u.id]);
      batch.update(u.reference, {
        'role': newRole,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Roles de usuarios guardados')),
    );
  }

  // ------------------------ ROLES (con apps dentro del rol) ------------------------
  Future<void> _createOrEditRole({DocumentSnapshot<Map<String, dynamic>>? roleDoc}) async {
    final isEdit = roleDoc != null;
    final data   = roleDoc?.data() ?? {};

    final TextEditingController nameCtrl = TextEditingController(
      text: isEdit ? _safeStr(data['name']) : '',
    );

    // apps actuales del rol
    final currentApps = <String>{
      if (isEdit)
        ...((data['apps'] as List<dynamic>? ?? [])
            .map((e) => _safeStr(e))
            .where((e) => e.isNotEmpty))
    };
    final localSelected = currentApps.toSet();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16, right: 16, top: 8,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.85,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(isEdit ? 'Editar rol' : 'Crear rol',
                    style: const TextStyle(
                        fontFamily: kArial, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nombre del rol',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Apps que puede usar este rol',
                    style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),

                // Lista de apps (nombre visible y appId como subtítulo)
                Expanded(
                  child: _apps.isEmpty
                      ? const Center(
                    child: Text('No hay apps habilitadas en esta empresa.',
                        style: TextStyle(fontFamily: kArial)),
                  )
                      : ListView.separated(
                    itemCount: _apps.length,
                    separatorBuilder: (_, __) => const Divider(height: 0),
                    itemBuilder: (_, i) {
                      final aDoc = _apps[i];
                      final a = aDoc.data();
                      final appId  = _safeStr(a['appId']).isNotEmpty ? _safeStr(a['appId']) : aDoc.id;
                      final nombre = _safeStr(a['nombre']).isNotEmpty ? _safeStr(a['nombre']) : _prettyFromAppId(appId);
                      final checked = localSelected.contains(appId);

                      return CheckboxListTile(
                        value: checked,
                        onChanged: (v) {
                          if (v == true) {
                            localSelected.add(appId);
                          } else {
                            localSelected.remove(appId);
                          }
                          (ctx as Element).markNeedsBuild();
                        },
                        title: Text(nombre, style: const TextStyle(fontFamily: kArial)),
                        subtitle: Text(appId,
                            style: const TextStyle(fontFamily: kArial, fontSize: 12, color: Colors.black54)),
                        activeColor: kMarronClaro,
                      );
                    },
                  ),
                ),

                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: kMarronClaro),
                    onPressed: () async {
                      final name = _safeStr(nameCtrl.text);
                      if (name.isEmpty) return;

                      final payload = {
                        'empresaId': _empresaId,
                        'name': name,
                        'apps': localSelected.toList(),
                        'updatedAt': FieldValue.serverTimestamp(),
                        'createdAt': FieldValue.serverTimestamp(),
                      };

                      if (isEdit) {
                        await roleDoc!.reference.set(payload, SetOptions(merge: true));
                      } else {
                        await _db.collection('TBL_ROLES').add(payload);
                      }

                      if (!mounted) return;
                      Navigator.of(ctx).pop();
                      await _loadAll();
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(isEdit ? 'Rol actualizado' : 'Rol creado')),
                      );
                    },
                    child: Text(isEdit ? 'Guardar cambios' : 'Crear rol',
                        style: const TextStyle(fontFamily: kArial)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _deleteRole(String id) async {
    await _db.collection('TBL_ROLES').doc(id).delete();
    await _loadAll();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Rol eliminado')));
  }

  // ------------------------ UI ------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: AppDrawer(userId: widget.userId),
      appBar: AppBar(
        backgroundColor: kMarronOscuro,
        title: const Text('Admin', style: TextStyle(fontFamily: kArial)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: Container(
            color: kMarronOscuro,
            child: TabBar(
              controller: _tabController,
              indicatorColor: kMarronClaro,
              indicatorWeight: 3,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              labelStyle: const TextStyle(fontFamily: kArial, fontWeight: FontWeight.bold),
              tabs: const [
                Tab(text: 'Usuarios'),
                Tab(text: 'Roles'),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: (_tabController.index == 1) // Solo en Roles
          ? FloatingActionButton(
        backgroundColor: kMarronClaro,
        onPressed: () => _createOrEditRole(),
        child: const Icon(Icons.add, color: Colors.white),
      )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
        controller: _tabController,
        children: [
          // -------- Usuarios: asignar rol --------
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Expanded(
                  child: ListView.separated(
                    itemCount: _users.length,
                    separatorBuilder: (_, __) => const Divider(color: kMarronClaro),
                    itemBuilder: (_, i) {
                      final uDoc = _users[i];
                      final d = uDoc.data();
                      final nombre = _userDisplayName(d, uDoc.id);
                      final cedula = _safeStr(d['cedula']).isNotEmpty ? _safeStr(d['cedula']) : uDoc.id;
                      final currentRole = _safeStr(_userRoleMap[uDoc.id]);

                      return ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: kMarronClaro,
                          child: Icon(Icons.person, color: Colors.white),
                        ),
                        title: Text(nombre, style: const TextStyle(fontFamily: kArial)),
                        subtitle: Text('Cédula: $cedula', style: const TextStyle(fontFamily: kArial)),
                        trailing: DropdownButton<String>(
                          value: currentRole.isEmpty ? null : currentRole,
                          hint: const Text('Rol', style: TextStyle(fontFamily: kArial)),
                          items: _roles.map((r) {
                            final name = _safeStr(r.data()['name']).isNotEmpty
                                ? _safeStr(r.data()['name'])
                                : r.id;
                            return DropdownMenuItem<String>(
                              value: name,
                              child: Text(name, style: const TextStyle(fontFamily: kArial)),
                            );
                          }).toList(),
                          onChanged: (v) => setState(() {
                            if (v != null) _userRoleMap[uDoc.id] = v;
                          }),
                        ),
                      );
                    },
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: kMarronClaro),
                    onPressed: _saveUserRoles,
                    child: const Text('Guardar roles', style: TextStyle(fontFamily: kArial)),
                  ),
                ),
              ],
            ),
          ),

          // -------- Roles: listar + editar apps del rol --------
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Expanded(
                  child: ListView.separated(
                    itemCount: _roles.length,
                    separatorBuilder: (_, __) => const Divider(color: kMarronClaro),
                    itemBuilder: (_, i) {
                      final rDoc = _roles[i];
                      final r = rDoc.data();
                      final name = _safeStr(r['name']).isNotEmpty ? _safeStr(r['name']) : rDoc.id;
                      final apps = ((r['apps'] as List<dynamic>? ?? [])
                          .map((e) => _safeStr(e))
                          .where((e) => e.isNotEmpty)
                          .toList())
                          .cast<String>();

                      return ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: kMarronClaro,
                          child: Icon(Icons.badge, color: Colors.white),
                        ),
                        title: Text(name, style: const TextStyle(fontFamily: kArial)),
                        subtitle: apps.isEmpty
                            ? const Text('Sin apps asignadas',
                            style: TextStyle(fontFamily: kArial, fontSize: 12))
                            : Text(apps.join(' · '),
                            style: const TextStyle(fontFamily: kArial, fontSize: 12)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Editar',
                              icon: const Icon(Icons.edit, color: kMarronOscuro),
                              onPressed: () => _createOrEditRole(roleDoc: rDoc),
                            ),
                            IconButton(
                              tooltip: 'Eliminar',
                              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                              onPressed: () => _deleteRole(rDoc.id),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                // FAB para crear rol
              ],
            ),
          ),
        ],
      ),
    );
  }
}
