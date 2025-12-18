// lib/home/app_drawer.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:todo/state/empresa_scope.dart';

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
/// Tareas asignadas, Ver equipo, Cerrar sesión.
class AppDrawer extends StatelessWidget {
  final String userId; // cédula del usuario logueado

  const AppDrawer({Key? key, required this.userId}) : super(key: key);

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
              final cargo =
              ((estruct?['cargo'] as String?) ?? (user?['cargo'] as String?) ?? '')
                  .trim();

              // Foto (intenta primero con TBL_USUARIOS, luego con TBL_ESTRUCTURA_ORGANIZACIONAL)
              final fotoUrl = ((user?['fotoUrl'] as String?) ??
                  (estruct?['fotoUrl'] as String?) ??
                  '')
                  .trim();

              return ListView(
                padding: EdgeInsets.zero,
                children: [
                  UserAccountsDrawerHeader(
                    decoration: const BoxDecoration(color: kMarronOscuro),
                    currentAccountPicture: CircleAvatar(
                      backgroundColor: Colors.white,
                      backgroundImage:
                      (fotoUrl.isNotEmpty) ? NetworkImage(fotoUrl) : null,
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
                    title: const Text('Mi equipo de trabajo',
                        style: TextStyle(fontFamily: kArial)),
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

                  // Historial de tareas
                  ListTile(
                    leading: const Icon(Icons.history),
                    title: const Text('Historial de tareas',
                        style: TextStyle(fontFamily: kArial)),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TaskHistoryScreen(currentUserId: userId),
                      ),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.assignment_turned_in),
                    title: const Text('Tareas asignadas',
                        style: TextStyle(fontFamily: kArial)),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AssignedTasksScreen(userId: userId),
                      ),
                    ),
                  ),

                  // >>>> AQUÍ ESTABA EL ERROR: pasa currentUserId y quita el const
                  ListTile(
                    leading: const Icon(Icons.group_work),
                    title: const Text('Ver equipo de trabajo',
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
                    title: const Text('Cerrar sesión',
                        style: TextStyle(fontFamily: kArial)),
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
