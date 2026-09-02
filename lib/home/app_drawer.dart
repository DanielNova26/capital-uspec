// lib/home/app_drawer.dart

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../widgets/version_label.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:todo/state/empresa_scope.dart';
import 'package:todo/utils/user_company.dart';

import '../core/task_permissions.dart';
import '../services/auth_prefs.dart';
import '../widgets/user_avatar.dart';

// Ajusta este import según tu estructura real (mayúsculas/minúsculas).
import '../login/login_screen.dart';

import 'profile_screen.dart';
import 'team_screen.dart';
import 'create_task_screen.dart';
import 'task_history_screen.dart';
import 'assigned_tasks_screen.dart';
import 'created_tasks_screen.dart';
import 'team_overview_screen.dart';
import 'widgets/home_shared_widgets.dart';

const Color kMarronOscuro = Color(0xFF145DA0);
const String kArial = 'Arial';

/// Drawer que muestra avatar, nombre y cargo del usuario,
/// y opciones de navegación: Perfil, Mi equipo, Crear tarea, Historial,
/// Tareas asignadas, Ver equipo, Cambiar empresa, Cerrar sesión.
class AppDrawer extends StatelessWidget {
  final String userId; // cédula / id del usuario logueado
  /// Si es false, oculta todas las opciones de Tareas del drawer.
  /// Controlado por TBL_APPS (appId: tareasdashboard).
  final bool showTareas;

  const AppDrawer({super.key, required this.userId, this.showTareas = true});

  // ----------------------- HELPERS: ESTRUCTURA -----------------------
  Future<DocumentSnapshot<Map<String, dynamic>>?> _getEstructuraOnce(
    String uid,
  ) async {
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
  Future<Map<String, String>> _loadEmpresaNames(Set<String> ids) async {
    if (ids.isEmpty) return {};
    final col = FirebaseFirestore.instance.collection('TBL_EMPRESAS');
    final out = <String, String>{};

    await Future.wait(
      ids.map((id) async {
        try {
          final doc = await col.doc(id).get();
          final nombre = (doc.data()?['nombre'] as String?)?.trim();
          out[id] = (nombre != null && nombre.isNotEmpty) ? nombre : '';
        } catch (_) {
          out[id] = '';
        }
      }),
    );

    // Asegura fallback
    for (final id in ids) {
      out[id] = out[id] ?? '';
    }
    return out;
  }

  Future<String?> _selectEmpresaIdBottomSheet(
    BuildContext context,
    List<String> empresaIds, {
    String? preselectedId,
  }) async {
    final ids = empresaIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    if (ids.isEmpty) return null;
    ids.sort();

    if (ids.length == 1) return ids.first;

    final nombres = await _loadEmpresaNames(ids.toSet());
    if (!context.mounted) return null;

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
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 10),
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
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            child: Row(
                              children: [
                                CompanyLogoAvatar(
                                  empresaId: id,
                                  radius: 18,
                                  backgroundColor: scheme.primaryContainer,
                                  foregroundColor: scheme.onPrimaryContainer,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        nombre.isEmpty
                                            ? 'Empresa sin nombre'
                                            : nombre,
                                        style: theme.textTheme.bodyLarge
                                            ?.copyWith(
                                              fontFamily: kArial,
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.chevron_right,
                                  color: scheme.onSurfaceVariant,
                                ),
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

      await FirebaseFirestore.instance
          .collection('TBL_USUARIOS')
          .doc(userId)
          .set({
            'empresaId': empresaId,
            if (nombre != null && nombre.isNotEmpty) 'empresaNombre': nombre,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
    } catch (_) {}
  }

  bool _shouldShowTeamPanel({
    required Map<String, dynamic>? user,
    required Map<String, dynamic>? estruct,
    required String? scopeEmpresa,
    required bool tareasEnabled,
  }) {
    return tareasEnabled &&
        user != null &&
        canViewTaskTeam(user, structureData: estruct, empresaId: scopeEmpresa);
  }

  // ----------------------- UI -----------------------
  @override
  Widget build(BuildContext context) {
    // Si estamos en web (sidebar), no usamos el wrapper Drawer ni el header redundante
    final bool isSidebar = kIsWeb && MediaQuery.of(context).size.width >= 900;

    final content = StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
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
            final nombres =
                (user?['nombres'] as String? ??
                        user?['primerNombre'] as String? ??
                        '')
                    .trim();
            final apellidos =
                (user?['apellidos'] as String? ??
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
            final fotoUrl =
                ((user?['fotoUrl'] as String?) ??
                        (estruct?['fotoUrl'] as String?) ??
                        '')
                    .trim();

            // Empresa actual y empresas autorizadas.
            final empresaActual = (user?['empresaId'] as String? ?? '').trim();
            final activeEmpresa = (scopeEmpresa?.trim().isNotEmpty ?? false)
                ? scopeEmpresa!.trim()
                : empresaActual;
            final empresas = user == null
                ? <String>[]
                : extractUserEmpresaIds(user);
            final canChangeEmpresa = empresas.length >= 2;
            final showTeamPanel = _shouldShowTeamPanel(
              user: user,
              estruct: estruct,
              scopeEmpresa: activeEmpresa,
              tareasEnabled: showTareas,
            );

            final listContent = ListView(
              padding: EdgeInsets.zero,
              children: [
                if (!isSidebar)
                  UserAccountsDrawerHeader(
                    decoration: const BoxDecoration(color: kMarronOscuro),
                    currentAccountPicture: UserAvatar(
                      userId: userId,
                      nameHint: nombreFull,
                      fotoUrlHint: fotoUrl,
                      radius: 36,
                      backgroundColor: Colors.white,
                      foregroundColor: kMarronOscuro,
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

                // ✅ INFO DE PERFIL COMPACTA PARA WEB SIDEBAR
                if (isSidebar) ...[
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        UserAvatar(
                          userId: userId,
                          nameHint: nombreFull,
                          fotoUrlHint: fotoUrl,
                          radius: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                nombreFull.isEmpty ? userId : nombreFull,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                cargo.isEmpty ? 'Usuario' : cargo,
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                  fontSize: 12,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                ],

                // ✅ CAMBIAR EMPRESA SIN CERRAR SESIÓN
                if (canChangeEmpresa) ...[
                  ListTile(
                    leading: const Icon(Icons.swap_horiz),
                    title: const Text(
                      'Cambiar empresa',
                      style: TextStyle(fontFamily: kArial),
                    ),
                    subtitle: activeEmpresa.isEmpty
                        ? null
                        : Row(
                            children: [
                              const Text(
                                'Actual: ',
                                style: TextStyle(
                                  fontFamily: kArial,
                                  fontSize: 12,
                                ),
                              ),
                              Expanded(
                                child: CompanyNameWidget(
                                  empresaId: activeEmpresa,
                                  showIdIfNotFound: false,
                                  style: const TextStyle(
                                    fontFamily: kArial,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                    onTap: () async {
                      final selected = await _selectEmpresaIdBottomSheet(
                        context,
                        empresas,
                        preselectedId: activeEmpresa.isNotEmpty
                            ? activeEmpresa
                            : null,
                      );

                      if (!context.mounted) return;
                      if (selected == null || selected.trim().isEmpty) return;

                      // 1) Setear scope
                      try {
                        EmpresaScope.of(
                          context,
                          listen: false,
                        ).setSelectedEmpresaId(selected);
                      } catch (_) {}

                      // 2) Persistir en el usuario (para que quede guardado)
                      await _persistSelectedEmpresa(userId, selected);

                      // 3) Cerrar drawer si aplica
                      if (!isSidebar && context.mounted) Navigator.pop(context);

                      // 4) Aviso
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Empresa activa actualizada'),
                          ),
                        );
                      }
                    },
                  ),

                  const Divider(),
                ],

                // — Menú principal —
                ListTile(
                  leading: const Icon(Icons.assignment_ind_rounded),
                  title: const Text(
                    'Mi hoja de vida',
                    style: TextStyle(fontFamily: kArial),
                  ),
                  subtitle: const Text(
                    'Editar datos y subir soportes',
                    style: TextStyle(fontFamily: kArial),
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ProfileScreen(
                        userId: userId,
                        empresaId: (scopeEmpresa?.trim().isNotEmpty ?? false)
                            ? scopeEmpresa
                            : empresaActual,
                      ),
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.group),
                  title: const Text(
                    'Mi equipo de trabajo',
                    style: TextStyle(fontFamily: kArial),
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TeamScreen(userId: userId),
                    ),
                  ),
                ),

                // ── SECCIÓN GESTIÓN DE TAREAS (solo si el módulo está habilitado) ──
                if (showTareas) ...[
                  const Divider(),

                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text(
                      'GESTIÓN DE TAREAS',
                      style: TextStyle(
                        fontFamily: kArial,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.7),
                        letterSpacing: 1.1,
                      ),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.add_task_rounded,
                      color: kMarronOscuro,
                    ),
                    title: const Text(
                      'Crear nueva tarea',
                      style: TextStyle(
                        fontFamily: kArial,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onTap: () {
                      if (!isSidebar) Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              CreateTaskScreen(currentUserId: userId),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.assignment_ind_rounded,
                      color: kMarronOscuro,
                    ),
                    title: const Text(
                      'Mis tareas',
                      style: TextStyle(
                        fontFamily: kArial,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    subtitle: const Text(
                      'Activas para resolver',
                      style: TextStyle(fontFamily: kArial, fontSize: 11),
                    ),
                    onTap: () {
                      if (!isSidebar) Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AssignedTasksScreen(userId: userId),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.manage_accounts_rounded,
                      color: kMarronOscuro,
                    ),
                    title: const Text(
                      'Tareas que asigné',
                      style: TextStyle(
                        fontFamily: kArial,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    subtitle: const Text(
                      'Seguimiento de equipo',
                      style: TextStyle(fontFamily: kArial, fontSize: 11),
                    ),
                    onTap: () {
                      if (!isSidebar) Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CreatedTasksScreen(userId: userId),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.fact_check_rounded,
                      color: kMarronOscuro,
                    ),
                    title: const Text(
                      'Tareas por aprobar',
                      style: TextStyle(
                        fontFamily: kArial,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    subtitle: const Text(
                      'Cierres y devoluciones',
                      style: TextStyle(fontFamily: kArial, fontSize: 11),
                    ),
                    onTap: () {
                      if (!isSidebar) Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CreatedTasksScreen(
                            userId: userId,
                            approvalMode: true,
                          ),
                        ),
                      );
                    },
                  ),
                ],

                if (showTeamPanel) ...[
                  ListTile(
                    leading: const Icon(Icons.group_work_rounded),
                    title: const Text(
                      'Tareas de mi equipo',
                      style: TextStyle(fontFamily: kArial),
                    ),
                    subtitle: const Text(
                      'Agrupadas por responsable',
                      style: TextStyle(fontFamily: kArial, fontSize: 11),
                    ),
                    onTap: () {
                      if (!isSidebar) Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              TeamOverviewScreen(currentUserId: userId),
                        ),
                      );
                    },
                  ),
                ],

                if (showTareas)
                  ListTile(
                    leading: const Icon(
                      Icons.history_rounded,
                      color: kMarronOscuro,
                    ),
                    title: const Text(
                      'Historial de tareas',
                      style: TextStyle(
                        fontFamily: kArial,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    subtitle: const Text(
                      'Finalizadas y cerradas',
                      style: TextStyle(fontFamily: kArial, fontSize: 11),
                    ),
                    onTap: () {
                      if (!isSidebar) Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              TaskHistoryScreen(currentUserId: userId),
                        ),
                      );
                    },
                  ),

                const Divider(),

                ListTile(
                  leading: const Icon(Icons.exit_to_app),
                  title: const Text(
                    'Cerrar sesión',
                    style: TextStyle(fontFamily: kArial),
                  ),
                  onTap: () => _logout(context),
                ),

                // Versión instalada. Es lo primero que hay que preguntar en
                // soporte, y en web confirma que el navegador no está sirviendo
                // una build cacheada.
                const VersionLabel(),
              ],
            );

            return isSidebar ? listContent : Drawer(child: listContent);
          },
        );
      },
    );

    return content;
  }

  Future<void> _logout(BuildContext context) async {
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
    // Borra la sesión guardada y apaga el auto-ingreso (mantener sesión /
    // biometría). Conserva "recordar usuario" para comodidad en el próximo login.
    try {
      await AuthPrefs.instance.clearSession();
    } catch (_) {}
    if (!context.mounted) return;
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
