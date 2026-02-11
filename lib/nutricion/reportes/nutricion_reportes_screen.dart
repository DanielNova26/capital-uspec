import 'package:flutter/material.dart';
import '/helpers/nutricion_dashboard_helper.dart';

/// Pantalla de reportes nutricionales con exportación a Excel.
///
/// INTEGRACIÓN CON SERVICIOS:
/// - Usa NutricionReportService a través de NutricionDashboardHelper
/// - Permite filtrar por rango de fechas
/// - Exporta menús y derivaciones a Excel
class NutricionReportesScreen extends StatefulWidget {
  final String empresaId;

  const NutricionReportesScreen({
    super.key,
    required this.empresaId,
  });

  @override
  State<NutricionReportesScreen> createState() =>
      _NutricionReportesScreenState();
}

class _NutricionReportesScreenState extends State<NutricionReportesScreen> {
  DateTime? _fechaDesde;
  DateTime? _fechaHasta;
  final _helper = NutricionDashboardHelper();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reportes Nutricionales'),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Título y descripción
          Text(
            'Exportar Reportes',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Genera reportes en Excel con información de menús, derivaciones y pacientes.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),

          // Filtros de fecha
          _buildFiltrosFecha(),

          const SizedBox(height: 24),

          // Botones de exportación
          _buildBotonesExportacion(),

          const SizedBox(height: 24),

          // Cards de información
          _buildCardsInformacion(),
        ],
      ),
    );
  }

  Widget _buildFiltrosFecha() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.filter_list,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Filtros de Fecha',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _seleccionarFechaDesde,
                    icon: const Icon(Icons.calendar_today),
                    label: Text(
                      _fechaDesde != null
                          ? _formatearFecha(_fechaDesde!)
                          : 'Desde',
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _seleccionarFechaHasta,
                    icon: const Icon(Icons.calendar_today),
                    label: Text(
                      _fechaHasta != null
                          ? _formatearFecha(_fechaHasta!)
                          : 'Hasta',
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (_fechaDesde != null || _fechaHasta != null) ...[
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _fechaDesde = null;
                    _fechaHasta = null;
                  });
                },
                icon: const Icon(Icons.clear),
                label: const Text('Limpiar filtros'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBotonesExportacion() {
    return Column(
      children: [
        // Botón principal de exportación
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _exportarReporteCompleto,
            icon: const Icon(Icons.file_download),
            label: const Text('Exportar Reporte Completo'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Botones secundarios en grid
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _exportarReporteEspecifico('menus'),
                icon: const Icon(Icons.restaurant_menu, size: 20),
                label: const Text('Solo Menús'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _exportarReporteEspecifico('derivaciones'),
                icon: const Icon(Icons.assignment, size: 20),
                label: const Text('Derivaciones'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCardsInformacion() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Información de Reportes',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        _buildInfoCard(
          title: 'Reporte Completo',
          description: 'Incluye todos los menús creados y derivaciones generadas en el rango de fechas seleccionado.',
          icon: Icons.description,
          color: Colors.blue,
        ),
        const SizedBox(height: 12),
        _buildInfoCard(
          title: 'Solo Menús',
          description: 'Exporta únicamente los menús con su configuración de tiempos de comida.',
          icon: Icons.restaurant_menu,
          color: Colors.orange,
        ),
        const SizedBox(height: 12),
        _buildInfoCard(
          title: 'Derivaciones',
          description: 'Exporta las derivaciones de dietas a pacientes con calorías y porciones.',
          icon: Icons.assignment,
          color: Colors.green,
        ),
      ],
    );
  }

  Widget _buildInfoCard({
    required String title,
    required String description,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _seleccionarFechaDesde() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fechaDesde ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _fechaDesde = picked);
    }
  }

  Future<void> _seleccionarFechaHasta() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fechaHasta ?? DateTime.now(),
      firstDate: _fechaDesde ?? DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _fechaHasta = picked);
    }
  }

  Future<void> _exportarReporteCompleto() async {
    final nombreArchivo = _generarNombreArchivo('reporte_completo');

    await _helper.descargarReporte(
      context: context,
      empresaId: widget.empresaId,
      desde: _fechaDesde,
      hasta: _fechaHasta,
      nombreArchivo: nombreArchivo,
    );
  }

  Future<void> _exportarReporteEspecifico(String tipo) async {
    // En una implementación real, crearías un método en el helper
    // que permita exportar solo un tipo específico de datos

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Exportando reporte de $tipo...'),
        backgroundColor: Colors.blue,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );

    // TODO: Implementar exportación específica
    // await _helper.exportarReporteParcial(
    //   context: context,
    //   empresaId: widget.empresaId,
    //   tipo: tipo,
    //   desde: _fechaDesde,
    //   hasta: _fechaHasta,
    // );
  }

  String _formatearFecha(DateTime fecha) {
    return '${fecha.day.toString().padLeft(2, '0')}/'
        '${fecha.month.toString().padLeft(2, '0')}/'
        '${fecha.year}';
  }

  String _generarNombreArchivo(String prefijo) {
    final ahora = DateTime.now();
    final timestamp = '${ahora.year}${ahora.month.toString().padLeft(2, '0')}'
        '${ahora.day.toString().padLeft(2, '0')}_'
        '${ahora.hour.toString().padLeft(2, '0')}'
        '${ahora.minute.toString().padLeft(2, '0')}';

    String rangoFechas = '';
    if (_fechaDesde != null || _fechaHasta != null) {
      rangoFechas = '_desde_${_fechaDesde?.day ?? 'inicio'}'
          '_hasta_${_fechaHasta?.day ?? 'hoy'}';
    }

    return '${prefijo}_$timestamp$rangoFechas.xlsx';
  }
}