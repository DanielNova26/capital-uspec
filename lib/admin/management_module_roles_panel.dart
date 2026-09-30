import 'package:flutter/material.dart';

import '../gerencia/gerencia_permisos.dart';
import 'management_module_role.dart';

/// Roles de Gerencia: un interruptor por cada permiso de [kGerenciaPermisos].
/// Un permiso nuevo del catálogo aparece solo aquí, apagado en los roles que
/// ya existían.
class ManagementModuleRolesPanel extends StatefulWidget {
  const ManagementModuleRolesPanel({
    super.key,
    required this.roles,
    required this.onSave,
    required this.onSynchronize,
    required this.onCreateDefaults,
    required this.pendingSyncCount,
    required this.appHoldersWithoutRole,
    required this.onAssignAppHolders,
  });

  final List<ManagementModuleRole> roles;
  final Future<void> Function(
    String name,
    String description,
    GerenciaPermisos permissions,
    bool enabled,
    ManagementModuleRole? previous,
  )
  onSave;
  final Future<void> Function(ManagementModuleRole) onSynchronize;
  final Future<void> Function() onCreateDefaults;
  final int Function(ManagementModuleRole) pendingSyncCount;

  /// Personas con la app de Gerencia y sin rol: hoy no ven nada.
  final int appHoldersWithoutRole;
  final Future<void> Function(ManagementModuleRole) onAssignAppHolders;

  @override
  State<ManagementModuleRolesPanel> createState() =>
      _ManagementModuleRolesPanelState();
}

class _ManagementModuleRolesPanelState
    extends State<ManagementModuleRolesPanel> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit([ManagementModuleRole? role]) async {
    var name = role?.name ?? '';
    var description = role?.description ?? '';
    var permissions =
        role?.permissions ?? const GerenciaPermisos({kGerPermDashboard: true});
    var enabled = role?.enabled ?? true;
    final form = GlobalKey<FormState>();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text(
            role == null ? 'Crear rol de Gerencia' : 'Editar rol de Gerencia',
          ),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Form(
                key: form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      initialValue: name,
                      onChanged: (value) => name = value,
                      decoration: const InputDecoration(
                        labelText: 'Nombre del rol',
                      ),
                      validator: (value) => (value ?? '').trim().isEmpty
                          ? 'Escribe el nombre del rol'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      initialValue: description,
                      onChanged: (value) => description = value,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Descripción',
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (final permiso in kGerenciaPermisos)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(permiso.etiqueta),
                        subtitle: Text(permiso.descripcion),
                        value: permissions.tiene(permiso.clave),
                        onChanged: (value) => setDialog(
                          () => permissions = permissions.con(
                            permiso.clave,
                            value,
                          ),
                        ),
                      ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Rol activo'),
                      subtitle: const Text(
                        'Un rol inactivo deja a sus asignados sin acceso a Gerencia.',
                      ),
                      value: enabled,
                      onChanged: (value) => setDialog(() => enabled = value),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      role == null
                          ? 'Crear el rol no lo asigna a ninguna persona.'
                          : 'Guardar sincroniza estos permisos con las personas que siguen teniendo este rol.',
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                if (!form.currentState!.validate()) return;
                if (!permissions.algunaPestana) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Activa al menos una pestaña: sin ella el rol no deja ver nada.',
                      ),
                    ),
                  );
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: Text(role == null ? 'Crear rol' : 'Guardar y sincronizar'),
            ),
          ],
        ),
      ),
    );
    final cleanName = name.trim();
    final cleanDescription = description.trim();
    if (accepted == true && mounted) {
      await _run(
        () => widget.onSave(
          cleanName,
          cleanDescription,
          permissions,
          enabled,
          role,
        ),
      );
    }
  }

  Future<void> _assignAppHolders(ManagementModuleRole role) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Asignar rol de Gerencia'),
        content: Text(
          'Se asignará "${role.name}" a ${widget.appHoldersWithoutRole} '
          'persona(s) que tienen la app de Gerencia sin rol. Verán lo que '
          'permite este rol: ${role.effectivePermissions.descripcion}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Asignar'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await _run(() => widget.onAssignAppHolders(role));
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'Roles de Gerencia',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              FilledButton.icon(
                onPressed: _busy ? null : () => _edit(),
                icon: const Icon(Icons.add),
                label: const Text('Crear rol'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _run(widget.onCreateDefaults),
                icon: const Icon(Icons.library_add_outlined),
                label: const Text('Crear roles iniciales'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Asignar un rol habilita Gerencia y define qué áreas, empresas y pestañas ve la persona, y si '
            'puede exportar. Sin rol no ve datos en Gerencia aunque tenga la app.',
          ),
          if (widget.appHoldersWithoutRole > 0) ...[
            const SizedBox(height: 8),
            Text(
              '${widget.appHoldersWithoutRole} persona(s) tienen la app de Gerencia sin rol y hoy no ven nada. '
              'Puedes asignarles uno de los roles de abajo.',
              style: const TextStyle(
                color: Color(0xFF9D174D),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator(),
            ),
          for (final role in widget.roles) ...[
            const Divider(height: 24),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${role.name}${role.enabled ? '' : ' · Inactivo'}'),
              subtitle: Text(
                '${role.effectivePermissions.descripcion}'
                '${role.description.isEmpty ? '' : '\n${role.description}'}'
                '${widget.pendingSyncCount(role) == 0 ? '' : '\n${widget.pendingSyncCount(role)} persona(s) por sincronizar'}',
              ),
              trailing: IconButton(
                tooltip: 'Editar ${role.name}',
                onPressed: _busy ? null : () => _edit(role),
                icon: const Icon(Icons.edit_outlined),
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (widget.pendingSyncCount(role) > 0)
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _run(() => widget.onSynchronize(role)),
                    icon: const Icon(Icons.sync),
                    label: const Text('Sincronizar asignados'),
                  ),
                if (role.enabled && widget.appHoldersWithoutRole > 0)
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _assignAppHolders(role),
                    icon: const Icon(Icons.group_add_outlined),
                    label: Text(
                      'Asignar a quienes tienen la app sin rol (${widget.appHoldersWithoutRole})',
                    ),
                  ),
              ],
            ),
          ],
          if (widget.roles.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'Todavía no hay roles de Gerencia. Puedes crear uno o agregar los iniciales.',
              ),
            ),
        ],
      ),
    ),
  );
}
