import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class NutricionDashboardScreen extends StatefulWidget {
  final String userId;
  final String empresaId;

  const NutricionDashboardScreen({
    super.key,
    required this.userId,
    required this.empresaId,
  });

  @override
  State<NutricionDashboardScreen> createState() =>
      _NutricionDashboardScreenState();
}

class _NutricionDashboardScreenState extends State<NutricionDashboardScreen> {
  final List<String> _establecimientos = const ['Establecimiento principal'];
  late String _selectedEstablecimiento;
  DateTime _weekStart = _mondayOf(DateTime.now());

  @override
  void initState() {
    super.initState();
    _selectedEstablecimiento = _establecimientos.first;
  }

  static DateTime _mondayOf(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    return normalized.subtract(Duration(days: normalized.weekday - 1));
  }

  String _weekLabel(DateTime start) {
    final end = start.add(const Duration(days: 6));
    final format = DateFormat('dd MMM', 'es');
    return '${format.format(start)} - ${format.format(end)}';
  }

  Future<void> _pickWeek() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _weekStart,
      firstDate: DateTime(2024),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      _weekStart = _mondayOf(picked);
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Nutrición y Menús'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Menús', icon: Icon(Icons.restaurant_menu)),
              Tab(text: 'Catálogos', icon: Icon(Icons.menu_book)),
              Tab(text: 'Firmas', icon: Icon(Icons.draw)),
              Tab(text: 'Reportes', icon: Icon(Icons.bar_chart)),
            ],
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 16,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 260,
                    child: DropdownButtonFormField<String>(
                      value: _selectedEstablecimiento,
                      items: _establecimientos
                          .map(
                            (item) => DropdownMenuItem(
                          value: item,
                          child: Text(item),
                        ),
                      )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() {
                          _selectedEstablecimiento = value;
                        });
                      },
                      decoration: const InputDecoration(
                        labelText: 'Establecimiento',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _pickWeek,
                    icon: const Icon(Icons.date_range),
                    label: Text('Semana: ${_weekLabel(_weekStart)}'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: TabBarView(
                children: [
                  _buildPlaceholder(
                    title: 'Menús semanales',
                    description:
                    'Crea y versiona menús por establecimiento y semana.',
                  ),
                  _buildPlaceholder(
                    title: 'Catálogos',
                    description:
                    'Administra preparaciones, dietas terapéuticas y sustituciones.',
                  ),
                  _buildPlaceholder(
                    title: 'Firmas y sellos',
                    description:
                    'Carga firma/sello, firma menús y genera PDF.',
                  ),
                  _buildPlaceholder(
                    title: 'Reportes',
                    description: 'Auditoría y análisis de cumplimiento.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder({
    required String title,
    required String description,
  }) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(description),
          const SizedBox(height: 16),
          const Text(
            'Pendiente de implementación detallada.',
            style: TextStyle(color: Colors.black54),
          ),
        ],
      ),
    );
  }
}
