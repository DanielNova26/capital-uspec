import 'package:flutter/material.dart';

import 'table_module_role.dart';

/// Creador de roles de un módulo con tabla propia (Compras, Rutas,
/// Interventoría). Mismo formulario que el de Correspondencia, con los
/// niveles y textos de [config].
class TableModuleRolesPanel extends StatefulWidget {
  const TableModuleRolesPanel({
    super.key,
    required this.config,
    required this.roles,
    required this.onSave,
    required this.onSynchronize,
    required this.onCreateDefaults,
    required this.pendingSyncCount,
  });

  final TableModuleRoleConfig config;
  final List<TableModuleRole> roles;
  final Future<void> Function(
    String name,
    String description,
    String level,
    bool enabled,
    TableModuleRole? previous,
  )
  onSave;
  final Future<void> Function(TableModuleRole) onSynchronize;
  final Future<void> Function() onCreateDefaults;
  final int Function(TableModuleRole) pendingSyncCount;

  @override
  State<TableModuleRolesPanel> createState() => _TableModuleRolesPanelState();
}

class _TableModuleRolesPanelState extends State<TableModuleRolesPanel> {
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

  Future<void> _edit([TableModuleRole? role]) async {
    final config = widget.config;
    var name = role?.name ?? '';
    var description = role?.description ?? '';
    var level = role?.level ?? config.levels.keys.first;
    var enabled = role?.enabled ?? true;
    final form = GlobalKey<FormState>();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text(
            role == null
                ? 'Crear rol de ${config.moduleName}'
                : 'Editar rol de ${config.moduleName}',
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
                    DropdownButtonFormField<String>(
                      initialValue: level,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Nivel operativo',
                      ),
                      items: [
                        for (final entry in config.levels.entries)
                          DropdownMenuItem(
                            value: entry.key,
                            child: Text(
                              entry.value,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) setDialog(() => level = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    Text(config.levelDescription(level)),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Rol activo'),
                      subtitle: Text(
                        'Un rol inactivo deja a sus personas así: '
                        '${config.inactiveDescription}',
                      ),
                      value: enabled,
                      onChanged: (value) => setDialog(() => enabled = value),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      role == null
                          ? 'Crear el rol no lo asigna a ninguna persona.'
                          : 'Guardar sincroniza este nivel con las personas que siguen teniendo este rol.',
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
        () => widget.onSave(cleanName, cleanDescription, level, enabled, role),
      );
    }
  }

  @override
  Widget build(BuildContext context) => _card(widget.config);

  Widget _card(TableModuleRoleConfig config) => Card(
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
              Text(
                'Roles de ${config.moduleName}',
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
          Text(
            'Asignar un rol habilita ${config.moduleName} y aplica su nivel a la persona. Los roles individuales '
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
                '${config.levelLabel(role.effectiveLevel)}: ${config.levelDescription(role.effectiveLevel)}'
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
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'Todavía no hay roles de ${config.moduleName}. Puedes crear uno o agregar los iniciales.',
              ),
            ),
        ],
      ),
    ),
  );
}
