import 'package:flutter/material.dart';

enum AdminInternalSection {
  catalogos('Catálogos y bodegas', Icons.account_tree_outlined),
  grupos('Grupos', Icons.groups_2_outlined),
  membresia('Membresía', Icons.apartment_outlined),
  multiempresa('Multiempresa', Icons.hub_outlined);

  const AdminInternalSection(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Un punto de entrada por empresa para los catálogos y la membresía.
/// La navegación es lateral en Web y compacta en móvil.
class AdminInternalWorkspace extends StatelessWidget {
  const AdminInternalWorkspace({
    super.key,
    required this.selected,
    required this.onSelected,
    required this.sectionBuilder,
  });

  final AdminInternalSection selected;
  final ValueChanged<AdminInternalSection> onSelected;
  final Widget Function(AdminInternalSection) sectionBuilder;

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
            child: DropdownButtonFormField<AdminInternalSection>(
              key: ValueKey(selected),
              initialValue: selected,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Gestión interna de la empresa',
                prefixIcon: Icon(selected.icon),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                for (final section in AdminInternalSection.values)
                  DropdownMenuItem(
                    value: section,
                    child: Text(section.label, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (section) {
                if (section != null) onSelected(section);
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
          width: 210,
          child: Material(
            color: Colors.white,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Text(
                    'Gestión interna',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ),
                for (final section in AdminInternalSection.values)
                  ListTile(
                    dense: true,
                    selected: selected == section,
                    selectedTileColor: const Color(0xFFEFF6FF),
                    selectedColor: const Color(0xFF2563EB),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    leading: Icon(section.icon, size: 20),
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
