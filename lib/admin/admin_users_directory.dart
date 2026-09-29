import 'package:flutter/material.dart';

import '../widgets/paged_list.dart';

class AdminPersonSummary {
  const AdminPersonSummary({
    required this.id,
    required this.name,
    required this.cargo,
    required this.departamento,
    required this.enabled,
  });

  final String id;
  final String name;
  final String cargo;
  final String departamento;
  final bool enabled;
}

class AdminUsersDirectory extends StatelessWidget {
  const AdminUsersDirectory({
    super.key,
    required this.people,
    required this.selectedId,
    required this.onSelected,
    required this.detailBuilder,
    required this.avatarBuilder,
  });

  final List<AdminPersonSummary> people;
  final String? selectedId;
  final ValueChanged<String> onSelected;
  final Widget Function(String, {VoidCallback? onNavigate}) detailBuilder;
  final Widget Function(String) avatarBuilder;

  @override
  Widget build(BuildContext context) {
    if (people.isEmpty) {
      return const Center(child: Text('No se encontraron personas'));
    }
    if (MediaQuery.sizeOf(context).width < 900) {
      return ListView.separated(
        itemCount: people.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, index) => detailBuilder(people[index].id),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final sideDetail = constraints.maxWidth >= 960;
        final hasSelection = people.any((p) => p.id == selectedId);
        final table = SingleChildScrollView(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: PagedDataTable(
              etiqueta: 'personas',
              tabla: DataTable(
                showCheckboxColumn: false,
                dataRowMinHeight: 64,
                dataRowMaxHeight: 72,
                headingRowColor: WidgetStateProperty.all(
                  const Color(0xFFF1F5F9),
                ),
                columns: const [
                  DataColumn(label: Text('Persona')),
                  DataColumn(label: Text('Cargo')),
                  DataColumn(label: Text('Departamento')),
                  DataColumn(label: Text('Estado')),
                ],
                rows: [
                  for (final person in people)
                    DataRow(
                      selected: person.id == selectedId,
                      onSelectChanged: (_) {
                        onSelected(person.id);
                        if (!sideDetail) {
                          showDialog<void>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Ficha del usuario'),
                              content: SizedBox(
                                width: 420,
                                child: SingleChildScrollView(
                                  child: detailBuilder(
                                    person.id,
                                    onNavigate: () => Navigator.pop(ctx),
                                  ),
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: const Text('Cerrar'),
                                ),
                              ],
                            ),
                          );
                        }
                      },
                      cells: [
                        DataCell(
                          Row(
                            children: [
                              avatarBuilder(person.id),
                              const SizedBox(width: 10),
                              SizedBox(
                                width: 190,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      person.name,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      person.id,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        DataCell(
                          SizedBox(
                            width: 150,
                            child: Text(
                              person.cargo,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        DataCell(
                          SizedBox(
                            width: 150,
                            child: Text(
                              person.departamento,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        DataCell(
                          Text(person.enabled ? 'Habilitado' : 'Inhabilitado'),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        );
        if (!sideDetail) return table;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: table),
            const SizedBox(width: 16),
            SizedBox(
              width: 360,
              child: hasSelection
                  ? SingleChildScrollView(child: detailBuilder(selectedId!))
                  : const Center(
                      child: Text(
                        'Selecciona una persona para ver su ficha y acciones.',
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}
