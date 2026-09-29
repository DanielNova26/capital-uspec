import 'package:flutter/material.dart';

enum AdminUsersSection {
  personas('Personas', Icons.people_alt_outlined),
  crear('Crear usuario', Icons.person_add_alt_1_outlined),
  accesos('Roles y permisos', Icons.admin_panel_settings_outlined),
  perfiles('Perfiles generales', Icons.badge_outlined),
  saludUsuarios('Salud usuarios', Icons.health_and_safety_outlined),
  saludCargos('Salud cargos', Icons.fact_check_outlined),
  membresia('Membresía', Icons.apartment_outlined),
  multiempresa('Multiempresa', Icons.hub_outlined),
  migraciones('Migraciones de usuarios', Icons.construction_outlined);

  const AdminUsersSection(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Una entrada para personal y accesos, con navegación propia por plataforma.
/// El estado pertenece al dashboard para conservar la sección al recargar.
class AdminUsersWorkspace extends StatelessWidget {
  const AdminUsersWorkspace({
    super.key,
    required this.selected,
    required this.onSelected,
    required this.sectionBuilder,
  });

  final AdminUsersSection selected;
  final ValueChanged<AdminUsersSection> onSelected;
  final Widget Function(AdminUsersSection) sectionBuilder;

  @override
  Widget build(BuildContext context) {
    final content = KeyedSubtree(
      key: ValueKey(selected),
      child: sectionBuilder(selected),
    );
    // Se usa el ancho de la plataforma, como el layout principal de Admin.
    if (MediaQuery.sizeOf(context).width < 900) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: DropdownButtonFormField<AdminUsersSection>(
              key: ValueKey(selected),
              initialValue: selected,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Gestión de usuarios',
                prefixIcon: Icon(selected.icon),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                for (final section in AdminUsersSection.values)
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
                    'Usuarios',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ),
                for (final section in AdminUsersSection.values)
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
