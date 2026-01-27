import 'package:flutter/material.dart';

import '../atencion/nutricion_atencion_actions.dart';
import '../../services/nutricion_service.dart';

class NutricionMenusScreen extends StatefulWidget {
  final String userId;
  final String empresaId;
  final String establecimiento;
  final DateTime semana;

  const NutricionMenusScreen({
    super.key,
    required this.userId,
    required this.empresaId,
    required this.establecimiento,
    required this.semana,
  });

  @override
  State<NutricionMenusScreen> createState() => _NutricionMenusScreenState();
}

class _NutricionMenusScreenState extends State<NutricionMenusScreen> {
  final _service = NutricionService();
  final _tiemposComida = const ['Desayuno', 'Almuerzo', 'Cena', 'Merienda'];
  final _plantillas = const [
    'Vacío',
    'Desayuno',
    'Almuerzo/Cena',
    'Refrigerio',
    'Completo',
  ];

  static const _plantillaDesayuno = [
    _PresetItem('Cereal', 'Pan'),
    _PresetItem('Proteína', 'Alternativa 1 - Huevo'),
    _PresetItem('Proteína', 'Alternativa 1 - Queso'),
    _PresetItem('Proteína', 'Alternativa 1 - Total'),
    _PresetItem('Proteína', 'Alternativa 2 - Queso'),
    _PresetItem('Proteína', 'Alternativa 2 - Total'),
    _PresetItem('Fruta', 'Fruta'),
    _PresetItem('Fruta', 'Fruta de mano'),
  ];

  static const _plantillaAlmuerzoCena = [
    _PresetItem('Cereal', 'Arroz almuerzo - cocido'),
    _PresetItem('Cereal', 'Arroz cena - cocido'),
    _PresetItem('Cereal', 'Total'),
    _PresetItem('Proteína', 'Alternativa 1 - Pechuga sin hueso almuerzo y almuerzo 0.5'),
    _PresetItem('Proteína', 'Alternativa 1 - Queso almuerzo y almuerzo 0.5'),
    _PresetItem('Proteína', 'Alternativa 1 - Subtotal'),
    _PresetItem('Proteína', 'Alternativa 1 - Pechuga sin hueso cocido cena y cena 0.5'),
    _PresetItem('Proteína', 'Alternativa 1 - Queso cena y cena 0.5'),
    _PresetItem('Proteína', 'Alternativa 1 - Subtotal'),
    _PresetItem('Proteína', 'Alternativa 1 - Total pechuga sin hueso'),
    _PresetItem('Proteína', 'Alternativa 1 - Total queso'),
    _PresetItem('Proteína', 'Alternativa 2 - Pechuga sin hueso almuerzo'),
    _PresetItem('Proteína', 'Alternativa 2 - Queso almuerzo y almuerzo 0.5'),
    _PresetItem('Proteína', 'Alternativa 2 - Subtotal'),
    _PresetItem('Proteína', 'Alternativa 2 - Pechuga sin hueso cena'),
    _PresetItem('Proteína', 'Alternativa 2 - Queso cena y cena 0.5'),
    _PresetItem('Proteína', 'Alternativa 2 - Subtotal'),
    _PresetItem('Proteína', 'Alternativa 2 - Total pechuga sin hueso'),
    _PresetItem('Proteína', 'Alternativa 2 - Total queso'),
    _PresetItem('Proteína', 'Alternativa 3 - Pechuga sin hueso cocido almuerzo'),
    _PresetItem('Proteína', 'Alternativa 3 - Queso almuerzo y almuerzo 0.5'),
    _PresetItem('Proteína', 'Alternativa 3 - Huevo almuerzo 0.5'),
    _PresetItem('Proteína', 'Alternativa 3 - Subtotal'),
    _PresetItem('Proteína', 'Alternativa 3 - Pechuga sin hueso cocido cena'),
    _PresetItem('Proteína', 'Alternativa 3 - Queso cena y cena 0.5'),
    _PresetItem('Proteína', 'Alternativa 3 - Huevo cena 0.5'),
    _PresetItem('Proteína', 'Alternativa 3 - Subtotal'),
    _PresetItem('Proteína', 'Alternativa 3 - Total pechuga sin hueso cocido'),
    _PresetItem('Proteína', 'Alternativa 3 - Total queso'),
    _PresetItem('Proteína', 'Alternativa 3 - Total huevo'),
    _PresetItem('Proteína', 'Alternativa 4 - Pechuga sin hueso almuerzo y almuerzo 0.5'),
    _PresetItem('Proteína', 'Alternativa 4 - Queso almuerzo y almuerzo 0.5'),
    _PresetItem('Proteína', 'Alternativa 4 - Subtotal'),
    _PresetItem('Proteína', 'Alternativa 4 - Huevo cena y cena 0.5'),
    _PresetItem('Proteína', 'Alternativa 4 - Queso cena y cena 0.5'),
    _PresetItem('Proteína', 'Alternativa 4 - Subtotal'),
    _PresetItem('Proteína', 'Alternativa 4 - Total pechuga sin hueso'),
    _PresetItem('Proteína', 'Alternativa 4 - Total huevo'),
    _PresetItem('Proteína', 'Alternativa 4 - Total queso'),
    _PresetItem('Proteína', 'Alternativa 5 - Huevo almuerzo y almuerzo 0.5'),
    _PresetItem('Proteína', 'Alternativa 5 - Queso almuerzo y almuerzo 0.5'),
    _PresetItem('Proteína', 'Alternativa 5 - Subtotal'),
    _PresetItem('Proteína', 'Alternativa 5 - Huevo cena y cena 0.5'),
    _PresetItem('Proteína', 'Alternativa 5 - Queso cena y cena 0.5'),
    _PresetItem('Proteína', 'Alternativa 5 - Subtotal'),
    _PresetItem('Proteína', 'Alternativa 5 - Total huevo almuerzo-cena'),
    _PresetItem('Proteína', 'Alternativa 5 - Total queso almuerzo-cena'),
    _PresetItem('Proteína', 'Alternativa 6 - Pescado almuerzo y almuerzo 0.5'),
    _PresetItem('Proteína', 'Alternativa 6 - Queso almuerzo y almuerzo 0.5'),
    _PresetItem('Proteína', 'Alternativa 6 - Subtotal'),
    _PresetItem('Proteína', 'Alternativa 6 - Pescado cena y cena 0.5'),
    _PresetItem('Proteína', 'Alternativa 6 - Queso cena y cena 0.5'),
    _PresetItem('Proteína', 'Alternativa 6 - Subtotal'),
    _PresetItem('Proteína', 'Alternativa 6 - Total pescado'),
    _PresetItem('Proteína', 'Alternativa 6 - Total queso'),
    _PresetItem('Proteína', 'Alternativa 7 - Pescado almuerzo'),
    _PresetItem('Proteína', 'Alternativa 7 - Queso almuerzo y almuerzo 0.5'),
    _PresetItem('Proteína', 'Alternativa 7 - Subtotal'),
    _PresetItem('Proteína', 'Alternativa 7 - Pescado cena'),
    _PresetItem('Proteína', 'Alternativa 7 - Queso cena y cena 0.5'),
    _PresetItem('Proteína', 'Alternativa 7 - Subtotal'),
    _PresetItem('Proteína', 'Alternativa 7 - Total pescado'),
    _PresetItem('Proteína', 'Alternativa 7 - Total queso'),
    _PresetItem('Proteína', 'Alternativa 8 - Pescado almuerzo y almuerzo 0.5'),
    _PresetItem('Proteína', 'Alternativa 8 - Queso almuerzo y almuerzo 0.5'),
    _PresetItem('Proteína', 'Alternativa 8 - Subtotal'),
    _PresetItem('Proteína', 'Alternativa 8 - Pechuga sin hueso cocido cena y cena 0.5'),
    _PresetItem('Proteína', 'Alternativa 8 - Queso cena y cena 0.5'),
    _PresetItem('Proteína', 'Alternativa 8 - Subtotal'),
    _PresetItem('Proteína', 'Alternativa 8 - Total pescado'),
    _PresetItem('Proteína', 'Alternativa 8 - Total pechuga sin hueso cocido'),
    _PresetItem('Proteína', 'Alternativa 8 - Total queso'),
    _PresetItem('Proteína', 'Alternativa 9 - Pescado almuerzo'),
    _PresetItem('Proteína', 'Alternativa 9 - Queso almuerzo y almuerzo 0.5'),
    _PresetItem('Proteína', 'Alternativa 9 - Huevo almuerzo 0.5'),
    _PresetItem('Proteína', 'Alternativa 9 - Subtotal'),
    _PresetItem('Proteína', 'Alternativa 9 - Pescado cena'),
    _PresetItem('Proteína', 'Alternativa 9 - Queso cena y cena 0.5'),
    _PresetItem('Proteína', 'Alternativa 9 - Huevo cena 0.5'),
    _PresetItem('Proteína', 'Alternativa 9 - Subtotal'),
    _PresetItem('Proteína', 'Alternativa 9 - Total pechuga sin hueso cocido'),
    _PresetItem('Proteína', 'Alternativa 9 - Total queso'),
    _PresetItem('Proteína', 'Alternativa 9 - Total huevo'),
    _PresetItem('Proteína', 'Alternativa 10 - Pescado almuerzo'),
    _PresetItem('Proteína', 'Alternativa 10 - Queso almuerzo y almuerzo 0.5'),
    _PresetItem('Proteína', 'Alternativa 10 - Subtotal'),
    _PresetItem('Proteína', 'Alternativa 10 - Huevo cena y cena 0.5'),
    _PresetItem('Proteína', 'Alternativa 10 - Queso cena y cena 0.5'),
    _PresetItem('Proteína', 'Alternativa 10 - Subtotal'),
    _PresetItem('Proteína', 'Alternativa 10 - Total pescado'),
    _PresetItem('Proteína', 'Alternativa 10 - Total huevo'),
    _PresetItem('Proteína', 'Alternativa 10 - Total queso'),
    _PresetItem('Proteína', 'Alternativa 11 - Carne almuerzo y almuerzo 0.5'),
    _PresetItem('Proteína', 'Alternativa 11 - Queso almuerzo y almuerzo 0.5'),
    _PresetItem('Proteína', 'Alternativa 11 - Subtotal'),
    _PresetItem('Proteína', 'Alternativa 11 - Carne cena y cena 0.5'),
    _PresetItem('Proteína', 'Alternativa 11 - Queso cena y cena 0.5'),
    _PresetItem('Proteína', 'Alternativa 11 - Subtotal'),
    _PresetItem('Proteína', 'Alternativa 11 - Total carne'),
    _PresetItem('Proteína', 'Alternativa 11 - Total queso'),
    _PresetItem('Proteína', 'Alternativa 12 - Carne cocida almuerzo'),
    _PresetItem('Proteína', 'Alternativa 12 - Queso almuerzo y almuerzo 0.5'),
    _PresetItem('Proteína', 'Alternativa 12 - Subtotal'),
    _PresetItem('Proteína', 'Alternativa 12 - Carne cocida cena'),
    _PresetItem('Proteína', 'Alternativa 12 - Queso cena y cena 0.5'),
    _PresetItem('Proteína', 'Alternativa 12 - Subtotal'),
    _PresetItem('Proteína', 'Alternativa 12 - Total carne cocida'),
    _PresetItem('Proteína', 'Alternativa 12 - Total queso'),
    _PresetItem('Proteína', 'Alternativa 13 - Carne cocida almuerzo y almuerzo 0.5'),
    _PresetItem('Proteína', 'Alternativa 13 - Queso almuerzo y almuerzo 0.5'),
    _PresetItem('Proteína', 'Alternativa 13 - Subtotal'),
    _PresetItem('Proteína', 'Alternativa 13 - Pechuga sin hueso cocido cena y cena 0.5'),
    _PresetItem('Proteína', 'Alternativa 13 - Queso cena y cena 0.5'),
    _PresetItem('Proteína', 'Alternativa 13 - Subtotal'),
    _PresetItem('Proteína', 'Alternativa 13 - Total carne cocida'),
    _PresetItem('Proteína', 'Alternativa 13 - Total pechuga sin hueso'),
    _PresetItem('Proteína', 'Alternativa 13 - Total queso'),
    _PresetItem('Proteína', 'Alternativa 14 - Carne cocida almuerzo'),
    _PresetItem('Proteína', 'Alternativa 14 - Queso almuerzo y almuerzo 0.5'),
    _PresetItem('Proteína', 'Alternativa 14 - Huevo almuerzo 0.5'),
    _PresetItem('Proteína', 'Alternativa 14 - Subtotal'),
    _PresetItem('Proteína', 'Alternativa 14 - Carne cocida cena'),
    _PresetItem('Proteína', 'Alternativa 14 - Queso cena y cena 0.5'),
    _PresetItem('Proteína', 'Alternativa 14 - Huevo cena 0.5'),
    _PresetItem('Proteína', 'Alternativa 14 - Subtotal'),
    _PresetItem('Proteína', 'Alternativa 14 - Total carne cocida'),
    _PresetItem('Proteína', 'Alternativa 14 - Total queso'),
    _PresetItem('Proteína', 'Alternativa 14 - Total huevo'),
    _PresetItem('Proteína', 'Alternativa 15 - Carne cocida almuerzo'),
    _PresetItem('Proteína', 'Alternativa 15 - Queso almuerzo y almuerzo 0.5'),
    _PresetItem('Proteína', 'Alternativa 15 - Subtotal'),
    _PresetItem('Proteína', 'Alternativa 15 - Huevo cena y cena 0.5'),
    _PresetItem('Proteína', 'Alternativa 15 - Queso cena y cena 0.5'),
    _PresetItem('Proteína', 'Alternativa 15 - Subtotal'),
    _PresetItem('Proteína', 'Alternativa 15 - Total carne'),
    _PresetItem('Proteína', 'Alternativa 15 - Total huevo'),
    _PresetItem('Proteína', 'Alternativa 15 - Total queso'),
    _PresetItem('Proteína', 'Alternativa 16 - Piernas de pollo almuerzo y almuerzo 0.5'),
    _PresetItem('Proteína', 'Alternativa 16 - Queso almuerzo y almuerzo 0.5'),
    _PresetItem('Proteína', 'Alternativa 16 - Subtotal'),
    _PresetItem('Proteína', 'Alternativa 16 - Piernas de pollo cena y cena 0.5'),
    _PresetItem('Proteína', 'Alternativa 16 - Queso cena y cena 0.5'),
    _PresetItem('Proteína', 'Alternativa 16 - Subtotal'),
    _PresetItem('Proteína', 'Alternativa 16 - Total piernas de pollo'),
    _PresetItem('Proteína', 'Alternativa 16 - Total queso'),
    _PresetItem('Proteína', 'Alternativa 17 - Piernas de pollo almuerzo'),
    _PresetItem('Proteína', 'Alternativa 17 - Queso almuerzo y almuerzo 0.5'),
    _PresetItem('Proteína', 'Alternativa 17 - Subtotal'),
    _PresetItem('Proteína', 'Alternativa 17 - Piernas de pollo cena'),
    _PresetItem('Proteína', 'Alternativa 17 - Queso cena y cena 0.5'),
    _PresetItem('Proteína', 'Alternativa 17 - Subtotal'),
    _PresetItem('Proteína', 'Alternativa 17 - Total pescado'),
    _PresetItem('Proteína', 'Alternativa 17 - Total queso'),
    _PresetItem('Proteína', 'Alternativa 18 - Piernas de pollo almuerzo'),
    _PresetItem('Proteína', 'Alternativa 18 - Queso almuerzo y almuerzo 0.5'),
    _PresetItem('Proteína', 'Alternativa 18 - Huevo almuerzo 0.5'),
    _PresetItem('Proteína', 'Alternativa 18 - Subtotal'),
    _PresetItem('Proteína', 'Alternativa 18 - Piernas de pollo cena'),
    _PresetItem('Proteína', 'Alternativa 18 - Queso cena y cena 0.5'),
    _PresetItem('Proteína', 'Alternativa 18 - Huevo cena 0.5'),
    _PresetItem('Proteína', 'Alternativa 18 - Subtotal'),
    _PresetItem('Proteína', 'Alternativa 18 - Total piernas de pollo'),
    _PresetItem('Proteína', 'Alternativa 18 - Total queso'),
    _PresetItem('Proteína', 'Alternativa 18 - Total huevo'),
    _PresetItem('Proteína', 'Alternativa 19 - Piernas de pollo almuerzo'),
    _PresetItem('Proteína', 'Alternativa 19 - Queso almuerzo y almuerzo 0.5'),
    _PresetItem('Proteína', 'Alternativa 19 - Subtotal'),
    _PresetItem('Proteína', 'Alternativa 19 - Huevo cena y cena 0.5'),
    _PresetItem('Proteína', 'Alternativa 19 - Queso cena y cena 0.5'),
    _PresetItem('Proteína', 'Alternativa 19 - Subtotal'),
    _PresetItem('Proteína', 'Alternativa 19 - Total piernas de pollo'),
    _PresetItem('Proteína', 'Alternativa 19 - Total huevo'),
    _PresetItem('Proteína', 'Alternativa 19 - Total queso'),
    _PresetItem('Proteína', 'Alternativa 20 - Chuleta almuerzo y almuerzo 0.5'),
    _PresetItem('Proteína', 'Alternativa 20 - Queso almuerzo y almuerzo 0.5'),
    _PresetItem('Proteína', 'Alternativa 20 - Subtotal'),
    _PresetItem('Proteína', 'Alternativa 20 - Chuleta cena y cena 0.5'),
    _PresetItem('Proteína', 'Alternativa 20 - Queso cena y cena 0.5'),
    _PresetItem('Proteína', 'Alternativa 20 - Subtotal'),
    _PresetItem('Proteína', 'Alternativa 20 - Total chuleta'),
    _PresetItem('Proteína', 'Alternativa 20 - Total queso'),
    _PresetItem('Proteína', 'Alternativa 21 - Chuleta almuerzo'),
    _PresetItem('Proteína', 'Alternativa 21 - Queso almuerzo y almuerzo 0.5'),
    _PresetItem('Proteína', 'Alternativa 21 - Subtotal'),
    _PresetItem('Proteína', 'Alternativa 21 - Chuleta cena'),
    _PresetItem('Proteína', 'Alternativa 21 - Queso cena y cena 0.5'),
    _PresetItem('Proteína', 'Alternativa 21 - Subtotal'),
    _PresetItem('Proteína', 'Alternativa 21 - Total pescado'),
    _PresetItem('Proteína', 'Alternativa 21 - Total queso'),
    _PresetItem('Proteína', 'Alternativa 22 - Chuleta almuerzo'),
    _PresetItem('Proteína', 'Alternativa 22 - Queso almuerzo y almuerzo 0.5'),
    _PresetItem('Proteína', 'Alternativa 22 - Huevo almuerzo 0.5'),
    _PresetItem('Proteína', 'Alternativa 22 - Subtotal'),
    _PresetItem('Proteína', 'Alternativa 22 - Chuleta cena'),
    _PresetItem('Proteína', 'Alternativa 22 - Queso cena y cena 0.5'),
    _PresetItem('Proteína', 'Alternativa 22 - Huevo cena 0.5'),
    _PresetItem('Proteína', 'Alternativa 22 - Subtotal'),
    _PresetItem('Proteína', 'Alternativa 22 - Total chuleta'),
    _PresetItem('Proteína', 'Alternativa 22 - Total queso'),
    _PresetItem('Proteína', 'Alternativa 22 - Total huevo'),
    _PresetItem('Proteína', 'Alternativa 23 - Chuleta almuerzo'),
    _PresetItem('Proteína', 'Alternativa 23 - Queso almuerzo y almuerzo 0.5'),
    _PresetItem('Proteína', 'Alternativa 23 - Subtotal'),
    _PresetItem('Proteína', 'Alternativa 23 - Huevo cena y cena 0.5'),
    _PresetItem('Proteína', 'Alternativa 23 - Queso cena y cena 0.5'),
    _PresetItem('Proteína', 'Alternativa 23 - Subtotal'),
    _PresetItem('Proteína', 'Alternativa 23 - Total chuleta'),
    _PresetItem('Proteína', 'Alternativa 23 - Total huevo'),
    _PresetItem('Proteína', 'Alternativa 23 - Total queso'),
    _PresetItem('Fruta', 'Fruta porcionada'),
    _PresetItem('Tubérculo', 'Tubérculo almuerzo'),
    _PresetItem('Tubérculo', 'Tubérculo cena'),
    _PresetItem('Tubérculo', 'Total'),
  ];

  static const _plantillaRefrigerio = [
  _PresetItem('Cereal', 'Alternativa 1 - Pan'),
    _PresetItem('Cereal', 'Alternativa 2 - Galleta'),
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader('Menús del establecimiento'),
          const SizedBox(height: 8),
          _buildMenuList(context),
          const SizedBox(height: 24),
          _sectionHeader('Flujo nutricional'),
          const SizedBox(height: 8),
          Text(
            'Registra pacientes, valoraciones, mediciones y asignaciones en el mismo flujo de nutrición.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              OutlinedButton.icon(
                onPressed: () => _openRegistrarPaciente(context),
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Registrar paciente'),
              ),
              OutlinedButton.icon(
                onPressed: () => _openRegistrarValoracion(context),
                icon: const Icon(Icons.assignment),
                label: const Text('Valoración'),
              ),
              OutlinedButton.icon(
                onPressed: () => _openRegistrarMedicion(context),
                icon: const Icon(Icons.monitor_weight),
                label: const Text('Mediciones'),
              ),
              OutlinedButton.icon(
                onPressed: () => _openAsignarDieta(context),
                icon: const Icon(Icons.restaurant),
                label: const Text('Asignar dieta'),
              ),
              OutlinedButton.icon(
                onPressed: () => _openGenerarCarnet(context),
                icon: const Icon(Icons.badge),
                label: const Text('Generar carnet'),
              ),
              OutlinedButton.icon(
                onPressed: () => _openDerivarMenu(context),
                icon: const Icon(Icons.merge_type),
                label: const Text('Derivar menú'),
              ),
              OutlinedButton.icon(
                onPressed: () => _openProgramarAlerta(context),
                icon: const Icon(Icons.notifications_active),
                label: const Text('Programar alerta'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleLarge,
    );
  }

  Widget _buildMenuList(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Semana ${widget.semana.day}/${widget.semana.month}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _openCrearMenu(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Nuevo menú'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            StreamBuilder<List<Map<String, dynamic>>>(
              stream: _service.streamMenus(
                empresaId: widget.empresaId,
                establecimiento: widget.establecimiento,
                semana: widget.semana,
              ),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final menus = snapshot.data ?? [];
                if (menus.isEmpty) {
                  return const Text('Sin menús registrados para esta semana.');
                }
                return Column(
                  children: menus.map((menu) {
                    final items = (menu['itemsPorTiempoComida'] as Map?) ?? {};
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(menu['nombre']?.toString() ?? 'Menú sin nombre'),
                      subtitle: Text(
                        '${menu['periodo'] ?? ''} • ${items.keys.join(', ')}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openCrearMenu(BuildContext context) async {
    final nombreCtrl = TextEditingController();
    final periodoCtrl = ValueNotifier<String>('Semanal');
    final plantillaCtrl = ValueNotifier<String>(_plantillas.first);
    final entradas = {
      for (final tiempo in _tiemposComida) tiempo: <_MenuItemEntry>[],
    };
    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            void replaceEntries(String tiempo, List<_PresetItem> preset) {
              for (final entry in entradas[tiempo] ?? []) {
                entry.dispose();
              }
              entradas[tiempo] = preset
                  .map(
                    (item) => _MenuItemEntry(
                  grupo: item.grupo,
                  descripcion: item.descripcion,
                ),
              )
                  .toList();
            }

            void applyPlantilla(String value) {
              if (value == 'Vacío') {
                for (final tiempo in _tiemposComida) {
                  replaceEntries(tiempo, const []);
                }
                return;
              }
              if (value == 'Desayuno' || value == 'Completo') {
                replaceEntries('Desayuno', _plantillaDesayuno);
              }
              if (value == 'Almuerzo/Cena' || value == 'Completo') {
                replaceEntries('Almuerzo', _plantillaAlmuerzoCena);
                replaceEntries('Cena', _plantillaAlmuerzoCena);
              }
              if (value == 'Refrigerio' || value == 'Completo') {
                replaceEntries('Merienda', _plantillaRefrigerio);
              }
            }

            return AlertDialog(
              title: const Text('Nuevo menú'),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      TextField(
                        controller: nombreCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Nombre del menú',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ValueListenableBuilder<String>(
                        valueListenable: periodoCtrl,
                        builder: (context, value, _) {
                          return DropdownButtonFormField<String>(
                            value: value,
                            decoration: const InputDecoration(
                              labelText: 'Periodo',
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'Semanal', child: Text('Semanal')),
                              DropdownMenuItem(value: 'Mensual', child: Text('Mensual')),
                            ],
                            onChanged: (newValue) {
                              if (newValue != null) periodoCtrl.value = newValue;
                            },
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      ValueListenableBuilder<String>(
                        valueListenable: plantillaCtrl,
                        builder: (context, value, _) {
                          return DropdownButtonFormField<String>(
                            value: value,
                            decoration: const InputDecoration(
                              labelText: 'Plantilla predeterminada',
                              border: OutlineInputBorder(),
                            ),
                            items: _plantillas
                                .map(
                                  (plantilla) => DropdownMenuItem(
                                value: plantilla,
                                child: Text(plantilla),
                              ),
                            )
                                .toList(),
                            onChanged: (newValue) {
                              if (newValue == null) return;
                              plantillaCtrl.value = newValue;
                              setState(() => applyPlantilla(newValue));
                            },
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      for (final tiempo in _tiemposComida) ...[
                        _TiempoComidaHeader(
                          tiempo: tiempo,
                          onAdd: () {
                            setState(() {
                              entradas[tiempo]!.add(_MenuItemEntry());
                            });
                          },
                        ),
                        const SizedBox(height: 8),
                        for (final entry in entradas[tiempo]!) ...[
                          _MenuItemRow(
                            entry: entry,
                            onRemove: () {
                              setState(() {
                                entradas[tiempo]!.remove(entry);
                                entry.dispose();
                              });
                            },
                          ),
                          const SizedBox(height: 8),
                        ],
                        const SizedBox(height: 12),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final nombre = nombreCtrl.text.trim();
                    if (nombre.isEmpty) return;
                    final items = <String, List<String>>{};
                    for (final tiempo in _tiemposComida) {
                      final list = <String>[];
                      for (final entry in entradas[tiempo] ?? []) {
                        final grupo = entry.grupo.text.trim();
                        final descripcion = entry.descripcion.text.trim();
                        if (grupo.isEmpty && descripcion.isEmpty) continue;
                        if (grupo.isEmpty) {
                          list.add(descripcion);
                        } else if (descripcion.isEmpty) {
                          list.add(grupo);
                        } else {
                          list.add('$grupo: $descripcion');
                        }
                      }
                      items[tiempo] = list;
                    }
                    await _service.crearMenu(
                      empresaId: widget.empresaId,
                      userId: widget.userId,
                      nombre: nombre,
                      periodo: periodoCtrl.value,
                      establecimiento: widget.establecimiento,
                      semana: widget.semana,
                      itemsPorTiempoComida: items,
                    );
                    if (!mounted) return;
                    Navigator.of(context).pop();
                  },
                  child: const Text('Guardar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _openRegistrarPaciente(BuildContext context) async {
    await NutricionAtencionActions.registrarPaciente(
      context,
      empresaId: widget.empresaId,
    );
  }

  Future<void> _openRegistrarValoracion(BuildContext context) async {
    await NutricionAtencionActions.registrarValoracion(
      context,
      empresaId: widget.empresaId,
    );
  }

  Future<void> _openRegistrarMedicion(BuildContext context) async {
    await NutricionAtencionActions.registrarMedicion(
      context,
      empresaId: widget.empresaId,
    );
  }

  Future<void> _openAsignarDieta(BuildContext context) async {
    await NutricionAtencionActions.asignarDieta(
      context,
      empresaId: widget.empresaId,
    );
  }

  Future<void> _openGenerarCarnet(BuildContext context) async {
    await NutricionAtencionActions.generarCarnet(
      context,
      empresaId: widget.empresaId,
    );
  }

  Future<void> _openDerivarMenu(BuildContext context) async {
    await NutricionAtencionActions.derivarMenu(
      context,
      empresaId: widget.empresaId,
    );
  }

  Future<void> _openProgramarAlerta(BuildContext context) async {
    await NutricionAtencionActions.programarAlerta(
      context,
      empresaId: widget.empresaId,
    );
  }
}

class _PresetItem {
  final String grupo;
  final String descripcion;

  const _PresetItem(this.grupo, this.descripcion);
}

class _MenuItemEntry {
  final TextEditingController grupo;
  final TextEditingController descripcion;

  _MenuItemEntry({
    String? grupo,
    String? descripcion,
  })  : grupo = TextEditingController(text: grupo),
        descripcion = TextEditingController(text: descripcion);

  void dispose() {
    grupo.dispose();
    descripcion.dispose();
  }
}

class _TiempoComidaHeader extends StatelessWidget {
  final String tiempo;
  final VoidCallback onAdd;

  const _TiempoComidaHeader({
    required this.tiempo,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            tiempo,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        TextButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add),
          label: const Text('Agregar fila'),
        ),
      ],
    );
  }
}

class _MenuItemRow extends StatelessWidget {
  final _MenuItemEntry entry;
  final VoidCallback onRemove;

  const _MenuItemRow({
    required this.entry,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(
          flex: 2,
          child: TextField(
            controller: entry.grupo,
            decoration: const InputDecoration(
              labelText: 'Grupo alimenticio',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          flex: 3,
          child: TextField(
            controller: entry.descripcion,
            decoration: const InputDecoration(
              labelText: 'Detalle',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: onRemove,
          icon: const Icon(Icons.remove_circle_outline),
          tooltip: 'Quitar',
        ),
      ],
    );
  }
}
