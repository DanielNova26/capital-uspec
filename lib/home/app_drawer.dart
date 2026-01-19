// lib/home/app_drawer.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:todo/state/empresa_scope.dart';
import 'package:todo/utils/user_company.dart';

// Ajusta este import según tu estructura real (mayúsculas/minúsculas).
import '../login/login_screen.dart';

import 'profile_screen.dart';
import 'team_screen.dart';
import 'create_task_screen.dart';
import 'task_history_screen.dart';
import 'assigned_tasks_screen.dart';
import 'team_overview_screen.dart';

const Color kMarronOscuro = Color(0xFF145DA0);
const String kArial = 'Arial';

/// Drawer que muestra avatar, nombre y cargo del usuario,
/// y opciones de navegación: Perfil, Mi equipo, Crear tarea, Historial,
/// Tareas asignadas, Ver equipo, Cambiar empresa, Cerrar sesión.
class AppDrawer extends StatelessWidget {
  final String userId; // cédula / id del usuario logueado

  const AppDrawer({Key? key, required this.userId}) : super(key: key);

  // ----------------------- HELPERS: ESTRUCTURA -----------------------
  Future<DocumentSnapshot<Map<String, dynamic>>?> _getEstructuraOnce(
      String uid) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('TBL_ESTRUCTURA_ORGANIZACIONAL')
          .doc(uid)
          .get();
      return snap;
    } catch (_) {
      return null;
    }
  }

  // ----------------------- HELPERS: EMPRESAS -----------------------
  Set<String> _empresasDeUsuario(Map<String, dynamic>? data) {
    final out = <String>{};
    if (data == null) return out;

    // empresaId principal
    final primary = (data['empresaId'] as String? ?? '').trim();
    if (primary.isNotEmpty) out.add(primary);

    // lista "empresas": [...]
    final list = data['empresas'] as List<dynamic>?;
    if (list != null) {
      for (final e in list) {
        final id = (e as String?)?.trim() ?? '';
        if (id.isNotEmpty) out.add(id);
      }
    }

    // map "empresasDetalle": { "EMPRESA_001": {...}, ... }
    final detalle = data['empresasDetalle'] as Map<String, dynamic>?;
    if (detalle != null) {
      for (final k in detalle.keys) {
        final id = k.toString().trim();
        if (id.isNotEmpty) out.add(id);
      }
    }

    return out;
  }

  Future<Map<String, String>> _loadEmpresaNames(Set<String> ids) async {
    if (ids.isEmpty) return {};
    final col = FirebaseFirestore.instance.collection('TBL_EMPRESAS');
    final out = <String, String>{};

    await Future.wait(ids.map((id) async {
      try {
        final doc = await col.doc(id).get();
        final nombre = (doc.data()?['nombre'] as String?)?.trim();
        out[id] = (nombre != null && nombre.isNotEmpty) ? nombre : id;
      } catch (_) {
        out[id] = id;
      }
    }));

    // Asegura fallback
    for (final id in ids) {
      out[id] = out[id] ?? id;
    }
    return out;
  }

  Future<String?> _selectEmpresaIdBottomSheet(
      BuildContext context,
      List<String> empresaIds, {
        String? preselectedId,
      }) async {
    final ids = empresaIds.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList();
    if (ids.isEmpty) return null;
    ids.sort();

    if (ids.length == 1) return ids.first;

    final nombres = await _loadEmpresaNames(ids.toSet());

    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final scheme = theme.colorScheme;

        final selected = (preselectedId != null && ids.contains(preselectedId))
            ? preselectedId
            : ids.first;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Cambiar empresa',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontFamily: kArial,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: ids.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final id = ids[i];
                      final nombre = (nombres[id] ?? id).trim();
                      final isSel = id == selected;

                      return Material(
                        color: isSel ? scheme.primaryContainer : scheme.surface,
                        elevation: 1,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => Navigator.of(ctx).pop(id),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 18,
                                  backgroundColor: scheme.primaryContainer,
                                  child: Text(
                                    id.substring(0, id.length >= 2 ? 2 : 1).toUpperCase(),
                                    style: TextStyle(
                                      color: scheme.onPrimaryContainer,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        nombre.isEmpty ? 'Empresa sin nombre' : nombre,
                                        style: theme.textTheme.bodyLarge?.copyWith(
                                          fontFamily: kArial,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      Text(
                                        id,
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          fontFamily: kArial,
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _persistSelectedEmpresa(String userId, String empresaId) async {
    try {
      final empDoc = await FirebaseFirestore.instance
          .collection('TBL_EMPRESAS')
          .doc(empresaId)
          .get();
      final nombre = (empDoc.data()?['nombre'] as String?)?.trim();

      await FirebaseFirestore.instance.collection('TBL_USUARIOS').doc(userId).set(
        {
          'empresaId': empresaId,
          if (nombre != null && nombre.isNotEmpty) 'empresaNombre': nombre,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (_) {}
  }

  // ----------------------- UI -----------------------
  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('TBL_USUARIOS')
            .doc(userId)
            .snapshots(),
        builder: (context, userSnap) {
          final user = userSnap.data?.data();

          return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>?>(
            future: _getEstructuraOnce(userId),
            builder: (context, estrSnap) {
              final estruct = estrSnap.data?.data();

              // Nombre
              final nombres = (user?['nombres'] as String? ??
                  user?['primerNombre'] as String? ??
                  '')
                  .trim();
              final apellidos = (user?['apellidos'] as String? ??
                  user?['primerApellido'] as String? ??
                  '')
                  .trim();
              String nombreFull = '$nombres $apellidos'.trim();
              if (nombreFull.isEmpty) {
                nombreFull = (estruct?['nombre'] as String? ?? '').trim();
              }

              final parts = nombreFull
                  .split(RegExp(r'\s+'))
                  .where((s) => s.isNotEmpty)
                  .toList();
              final primerNombre = parts.isNotEmpty ? parts.first : '';
              final primerApellido = parts.length > 1 ? parts[1] : '';

              // Cargo
              final scopeEmpresa = EmpresaScope.of(context).selectedEmpresaId;
              final cargoScoped = user == null
                  ? ''
                  : resolveScopedStringWithFallbacks(
                user,
                scopeEmpresa,
                const ['cargo'],
                const ['cargo'],
              ).trim();
              final cargo = cargoScoped.isNotEmpty
                  ? cargoScoped
                  : ((estruct?['cargo'] as String?) ?? '').trim();

              // Foto
              final fotoUrl = ((user?['fotoUrl'] as String?) ??
                  (estruct?['fotoUrl'] as String?) ??
                  '')
                  .trim();

              // Empresa actual (lo que tenga guardado el usuario)
              final empresaActual = (user?['empresaId'] as String? ?? '').trim();

              return ListView(
                padding: EdgeInsets.zero,
                children: [
                  UserAccountsDrawerHeader(
                    decoration: const BoxDecoration(color: kMarronOscuro),
                    currentAccountPicture: CircleAvatar(
                      backgroundColor: Colors.white,
                      backgroundImage: (fotoUrl.isNotEmpty) ? NetworkImage(fotoUrl) : null,
                      child: fotoUrl.isEmpty
                          ? const Icon(Icons.person, size: 48, color: kMarronOscuro)
                          : null,
                    ),
                    accountName: Text(
                      (('$primerNombre ${primerApellido.isNotEmpty ? primerApellido : ''}')
                          .trim()
                          .isEmpty)
                          ? userId
                          : '$primerNombre ${primerApellido.isNotEmpty ? primerApellido : ''}'
                          .trim(),
                      style: const TextStyle(fontFamily: kArial, fontSize: 18),
                    ),
                    accountEmail: Text(
                      cargo.isEmpty ? ' ' : cargo,
                      style: const TextStyle(fontFamily: kArial, fontSize: 14),
                    ),
                  ),

                  // ✅ CAMBIAR EMPRESA SIN CERRAR SESIÓN
                  ListTile(
                    leading: const Icon(Icons.swap_horiz),
                    title: const Text('Cambiar empresa', style: TextStyle(fontFamily: kArial)),
                    subtitle: empresaActual.isEmpty
                        ? null
                        : Text(
                      'Actual: $empresaActual',
                      style: const TextStyle(fontFamily: kArial, fontSize: 12),
                    ),
                    onTap: () async {
                      final empresas = _empresasDeUsuario(user).toList();
                      if (empresas.isEmpty) {
                        if (context.mounted) Navigator.pop(context);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Este usuario no tiene empresas asociadas')),
                          );
                        }
                        return;
                      }

                      final selected = await _selectEmpresaIdBottomSheet(
                        context,
                        empresas,
                        preselectedId: empresaActual.isNotEmpty ? empresaActual : null,
                      );

                      if (selected == null || selected.trim().isEmpty) return;

                      // 1) Setear scope
                      try {
                        EmpresaScope.of(context, listen: false).setSelectedEmpresaId(selected);
                      } catch (_) {}

                      // 2) Persistir en el usuario (para que quede guardado)
                      await _persistSelectedEmpresa(userId, selected);

                      // 3) Cerrar drawer
                      if (context.mounted) Navigator.pop(context);

                      // 4) Aviso
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Empresa activa: $selected')),
                        );
                      }

                      // Si quieres refrescar Home con pushReplacement, me dices y lo dejo listo.
                    },
                  ),

                  const Divider(),

                  // — Menú principal —
                  ListTile(
                    leading: const Icon(Icons.person),
                    title: const Text('Perfil', style: TextStyle(fontFamily: kArial)),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => ProfileScreen(userId: userId)),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.group),
                    title:
                    const Text('Mi equipo de trabajo', style: TextStyle(fontFamily: kArial)),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => TeamScreen(userId: userId)),
                    ),
                  ),

                  const Divider(),

                  ListTile(
                    leading: const Icon(Icons.add_task),
                    title: const Text('Crear tarea', style: TextStyle(fontFamily: kArial)),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CreateTaskScreen(currentUserId: userId),
                      ),
                    ),
                  ),

                  ListTile(
                    leading: const Icon(Icons.history),
                    title: const Text('Historial de tareas', style: TextStyle(fontFamily: kArial)),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TaskHistoryScreen(currentUserId: userId),
                      ),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.assignment_turned_in),
                    title: const Text('Tareas asignadas', style: TextStyle(fontFamily: kArial)),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AssignedTasksScreen(userId: userId),
                      ),
                    ),
                  ),

                  ListTile(
                    leading: const Icon(Icons.group_work),
                    title: const Text('Ver actividades de mi equipo',
                        style: TextStyle(fontFamily: kArial)),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TeamOverviewScreen(
                          currentUserId: userId,
                        ),
                      ),
                    ),
                  ),

                  const Divider(),

                  ListTile(
                    leading: const Icon(Icons.exit_to_app),
                    title: const Text('Cerrar sesión', style: TextStyle(fontFamily: kArial)),
                    onTap: () => _logout(context),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _logout(BuildContext context) async {
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
    try {
      EmpresaScope.of(context, listen: false).clear();
    } catch (_) {}

    if (context.mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
            (_) => false,
      );
    }
  }
}
