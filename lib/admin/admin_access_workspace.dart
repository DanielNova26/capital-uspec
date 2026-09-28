import 'package:flutter/material.dart';

enum AdminAccessSection {
  modulos('Módulos, roles y permisos', Icons.admin_panel_settings_outlined),
  apps('Configuración de apps', Icons.apps_outlined),
  perfiles('Perfiles generales', Icons.badge_outlined);

  const AdminAccessSection(this.label, this.icon);
  final String label;
  final IconData icon;
}

class AdminAccessWorkspace extends StatelessWidget {
  const AdminAccessWorkspace({
    super.key,
    required this.selected,
    required this.onSelected,
    required this.sectionBuilder,
  });
  final AdminAccessSection selected;
  final ValueChanged<AdminAccessSection> onSelected;
  final Widget Function(AdminAccessSection) sectionBuilder;

  @override
  Widget build(BuildContext context) {
    final content = KeyedSubtree(
      key: ValueKey(selected),
      child: sectionBuilder(selected),
    );
    if (MediaQuery.sizeOf(context).width < 900) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: DropdownButtonFormField<AdminAccessSection>(
              key: ValueKey(selected),
              initialValue: selected,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Apps, roles y permisos',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                for (final section in AdminAccessSection.values)
                  DropdownMenuItem(
                    value: section,
                    child: Text(section.label, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (value) {
                if (value != null) onSelected(value);
              },
            ),
          ),
          Expanded(child: content),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 220,
          child: Material(
            color: Colors.white,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
              children: [
                for (final section in AdminAccessSection.values)
                  ListTile(
                    selected: selected == section,
                    selectedTileColor: const Color(0xFFEFF6FF),
                    leading: Icon(section.icon),
                    title: Text(section.label),
                    onTap: () => onSelected(section),
                  ),
              ],
            ),
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(child: content),
      ],
    );
  }
}
