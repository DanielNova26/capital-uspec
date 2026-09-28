import 'package:flutter/material.dart';

import 'task_module_role.dart';

class TaskModuleRolesPanel extends StatefulWidget {
  const TaskModuleRolesPanel({
    super.key,
    required this.roles,
    required this.onSave,
    required this.onSynchronize,
    required this.onCreateDefaults,
    required this.pendingSyncCount,
  });

  final List<TaskModuleRole> roles;
  final Future<void> Function(
    String name,
    String description,
    TaskRolePermissions permissions,
    bool enabled,
    TaskModuleRole? previous,
  )
  onSave;
  final Future<void> Function(TaskModuleRole) onSynchronize;
  final Future<void> Function() onCreateDefaults;
  final int Function(TaskModuleRole) pendingSyncCount;

  @override
  State<TaskModuleRolesPanel> createState() => _TaskModuleRolesPanelState();
}

class _TaskModuleRolesPanelState extends State<TaskModuleRolesPanel> {
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

  Future<void> _edit([TaskModuleRole? role]) async {
    var name = role?.name ?? '';
    var description = role?.description ?? '';
    var allAreas = role?.permissions.allAreas ?? false;
    var viewTeam = role?.permissions.viewTeam ?? false;
    var enabled = role?.enabled ?? true;
    final form = GlobalKey<FormState>();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text(
            role == null ? 'Crear rol de Tareas' : 'Editar rol de Tareas',
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
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Crear en todas las áreas'),
                      subtitle: const Text(
                        'Al desactivarlo, conserva la creación en su propia área.',
                      ),
                      value: allAreas,
                      onChanged: (value) => setDialog(() => allAreas = value),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Ver tareas del equipo'),
                      value: viewTeam,
                      onChanged: (value) => setDialog(() => viewTeam = value),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Rol activo'),
                      subtitle: const Text(
                        'Un rol inactivo deja ambos permisos desactivados en sus asignados.',
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
                if (form.currentState!.validate()) Navigator.pop(ctx, true);
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
          TaskRolePermissions(allAreas: allAreas, viewTeam: viewTeam),
          enabled,
          role,
        ),
      );
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
                'Roles de Tareas',
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
            'Asignar un rol habilita Tareas y aplica sus permisos a la persona. Los permisos individuales '
            'existentes se conservan hasta que les asignes un rol.',
          ),
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
                '${role.effectivePermissions.description}'
                '${role.description.isEmpty ? '' : '\n${role.description}'}'
                '${widget.pendingSyncCount(role) == 0 ? '' : '\n${widget.pendingSyncCount(role)} persona(s) por sincronizar'}',
              ),
              trailing: IconButton(
                tooltip: 'Editar ${role.name}',
                onPressed: _busy ? null : () => _edit(role),
                icon: const Icon(Icons.edit_outlined),
              ),
            ),
            if (widget.pendingSyncCount(role) > 0)
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => _run(() => widget.onSynchronize(role)),
                icon: const Icon(Icons.sync),
                label: const Text('Sincronizar asignados'),
              ),
          ],
          if (widget.roles.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'Todavía no hay roles de Tareas. Puedes crear uno o agregar los iniciales.',
              ),
            ),
        ],
      ),
    ),
  );
}
