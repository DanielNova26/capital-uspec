// lib/admin/admin_dashboard_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

const String kArial = 'Arial';

class AdminDashboardScreen extends StatefulWidget {
  final String userId; // cédula del usuario que abre el panel (admin)
  const AdminDashboardScreen({Key? key, required this.userId}) : super(key: key);

  @override
  _AdminDashboardScreenState createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final _db = FirebaseFirestore.instance;

  bool _loading = true;

  // Data Firestore
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _users = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _apps = [];

  // Estado UI
  Map<String, Set<String>> _userAppsMap = {}; // userId -> apps

  @override
  void initState() {
    super.initState();
    _loadAll();
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

    // Traemos las apps disponibles para asignar (solo enabled)
    final appsSnap = await _db
        .collection('TBL_APPS')
        .where('empresaId', isEqualTo: empresaId)
        .where('enabled', isEqualTo: true)
        .get();

    setState(() {
      _users = usersSnap.docs;
      _apps = appsSnap.docs;
      _userAppsMap = {
        for (var u in _users)
          u.id: {
            ...((u.data()['apps'] as List<dynamic>? ?? [])
                .map((e) => _safeStr(e))
                .where((e) => e.isNotEmpty))
          },
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
  Future<void> _saveUserApps(String userId, Set<String> apps) async {
    await _db.collection('TBL_USUARIOS').doc(userId).set({
      'apps': apps.toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    _userAppsMap[userId] = apps;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Apps del usuario actualizadas')),
    );
    setState(() {});
  }

  Future<void> _editUserApps({
    required QueryDocumentSnapshot<Map<String, dynamic>> userDoc,
  }) async {
    final data = userDoc.data();
    final nombre = _userDisplayName(data, userDoc.id);
    final cedula = _safeStr(data['cedula']).isNotEmpty ? _safeStr(data['cedula']) : userDoc.id;
    final localSelected = {...(_userAppsMap[userDoc.id] ?? {})};

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 8,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.8,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Apps asignadas',
                    style: const TextStyle(
                        fontFamily: kArial, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('$nombre • Cédula: $cedula',
                    style: const TextStyle(fontFamily: kArial, color: Colors.black54)),
                const SizedBox(height: 12),
                Expanded(
                  child: _apps.isEmpty
                      ? const Center(
                    child: Text('No hay apps habilitadas para esta empresa.',
                        style: TextStyle(fontFamily: kArial)),
                  )
                      : ListView.separated(
                    itemCount: _apps.length,
                    separatorBuilder: (_, __) => const Divider(height: 0),
                    itemBuilder: (_, i) {
                      final aDoc = _apps[i];
                      final a = aDoc.data();
                      final appId =
                      _safeStr(a['appId']).isNotEmpty ? _safeStr(a['appId']) : aDoc.id;
                      final nombre = _safeStr(a['nombre']).isNotEmpty
                          ? _safeStr(a['nombre'])
                          : _prettyFromAppId(appId);
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
                            style: const TextStyle(
                                fontFamily: kArial, fontSize: 12, color: Colors.black54)),
                        activeColor: scheme.primary,
                      );
                    },
                  ),
                ),

                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: scheme.primary),
                    onPressed: () async {
                      await _saveUserApps(userDoc.id, localSelected);
                      if (!mounted) return;
                      Navigator.of(ctx).pop();
                      await _loadAll();
                    },
                    child: const Text('Guardar cambios', style: TextStyle(fontFamily: kArial)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
  // ------------------------ UI ------------------------
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin', style: TextStyle(fontFamily: kArial)),
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: _loadAll,
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: _users.length,
          itemBuilder: (_, i) {
            final uDoc = _users[i];
            final d = uDoc.data();
            final nombre = _userDisplayName(d, uDoc.id);
            final cedula = _safeStr(d['cedula']).isNotEmpty ? _safeStr(d['cedula']) : uDoc.id;
            final userApps = (_userAppsMap[uDoc.id] ?? {}).toList();

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              elevation: 0,
              shape: RoundedRectangleBorder(
                side: BorderSide(color: scheme.outlineVariant),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          backgroundColor: scheme.primary,
                          foregroundColor: scheme.onPrimary,
                          child: const Icon(Icons.person),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                nombre,
                                style: const TextStyle(
                                  fontFamily: kArial,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text('Cédula: $cedula',
                                  style: const TextStyle(fontFamily: kArial, fontSize: 13)),
                            ],
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => _editUserApps(userDoc: uDoc),
                          icon: const Icon(Icons.apps),
                          label:
                          const Text('Asignar apps', style: TextStyle(fontFamily: kArial)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (userApps.isNotEmpty)
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: userApps
                            .map(
                              (a) => Chip(
                            backgroundColor: scheme.primaryContainer,
                            label: Text(
                              a,
                              style: TextStyle(
                                fontFamily: kArial,
                                fontSize: 12,
                                color: scheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                        )
                            .toList(),
                      )
                    else
                      Text(
                        'Sin apps asignadas',
                        style: TextStyle(
                          fontFamily: kArial,
                          fontSize: 13,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}