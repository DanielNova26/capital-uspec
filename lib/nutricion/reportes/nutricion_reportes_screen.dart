import 'package:flutter/material.dart';
import '../../helpers/nutricion_dashboard_helper.dart';
import '../widgets/nutrition_shared_widgets.dart';
import 'package:todo/theme/app_typography.dart';

/// Pantalla de reportes nutricionales con exportación a Excel.
class NutricionReportesScreen extends StatefulWidget {
  final String empresaId;
  final bool showAppBar;

  const NutricionReportesScreen({
    super.key,
    required this.empresaId,
    this.showAppBar = true,
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
    final content = ListView(
      padding: const EdgeInsets.all(24),
      children: [
        if (!widget.showAppBar) ...[
          const Text(
            'GENERACIÓN DE DOCUMENTOS',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: NutritionPalette.accent,
              fontFamily: kArial,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Exportar Reportes Operativos',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: NutritionPalette.textMain,
              fontFamily: kArial,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Genera reportes en Excel con información técnica de menús, derivaciones y pacientes.',
            style: TextStyle(
              fontSize: 14,
              color: NutritionPalette.textMuted,
              fontFamily: kArial,
            ),
          ),
          const SizedBox(height: 32),
        ],

        // Filtros de fecha
        _buildFiltrosFecha(),

        const SizedBox(height: 24),

        // Botones de exportación
        _buildBotonesExportacion(),

        const SizedBox(height: 32),

        // Cards de información
        const Text(
          'GUÍA DE REPORTES DISPONIBLES',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
            color: NutritionPalette.textMuted,
            fontFamily: kArial,
          ),
        ),
        const SizedBox(height: 12),
        _buildCardsInformacion(),
      ],
    );

    if (!widget.showAppBar) return content;

    return Scaffold(
      backgroundColor: NutritionPalette.background,
      appBar: AppBar(
        title: const Text('Reportes Nutricionales', style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.bold)),
        elevation: 0,
        backgroundColor: NutritionPalette.primary,
        foregroundColor: Colors.white,
      ),
      body: content,
    );
  }

  Widget _buildFiltrosFecha() {
    return NutritionCard(
      title: 'Parámetros de Tiempo',
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _DateSelector(
                  label: 'Fecha Inicial',
                  value: _fechaDesde,
                  onTap: _seleccionarFechaDesde,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _DateSelector(
                  label: 'Fecha Final',
                  value: _fechaHasta,
                  onTap: _seleccionarFechaHasta,
                ),
              ),
            ],
          ),
          if (_fechaDesde != null || _fechaHasta != null) ...[
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() { _fechaDesde = null; _fechaHasta = null; }),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Restablecer fechas', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                style: TextButton.styleFrom(foregroundColor: Colors.red[700]),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBotonesExportacion() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 54,
          child: FilledButton.icon(
            onPressed: _exportarReporteCompleto,
            icon: const Icon(Icons.folder_zip_outlined),
            label: const Text('GENERAR REPORTE MAESTRO (EXCEL)', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.5)),
            style: FilledButton.styleFrom(
              backgroundColor: NutritionPalette.accent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _SubActionButton(
                label: 'Solo Menús',
                icon: Icons.restaurant_menu,
                onTap: () => _exportarReporteEspecifico('menus'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SubActionButton(
                label: 'Derivaciones',
                icon: Icons.assignment_outlined,
                onTap: () => _exportarReporteEspecifico('derivaciones'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCardsInformacion() {
    return Column(
      children: [
        _buildInfoItem('Reporte Completo', 'Consolidado técnico de menús y derivaciones.', Icons.inventory_2_outlined, Colors.blueGrey),
        const SizedBox(height: 12),
        _buildInfoItem('Configuración de Menús', 'Listado detallado de ingredientes y gramajes por tiempo.', Icons.menu_book_outlined, Colors.amber[800]!),
        const SizedBox(height: 12),
        _buildInfoItem('Seguimiento de Pacientes', 'Histórico de atenciones y estados nutricionales.', Icons.person_search_outlined, Colors.teal[700]!),
      ],
    );
  }

  Widget _buildInfoItem(String title, String desc, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NutritionPalette.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: NutritionPalette.border.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: NutritionPalette.textMain)),
                Text(desc, style: const TextStyle(fontSize: 12, color: NutritionPalette.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _seleccionarFechaDesde() async {
    final picked = await showDatePicker(context: context, initialDate: _fechaDesde ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime.now());
    if (picked != null) setState(() => _fechaDesde = picked);
  }

  Future<void> _seleccionarFechaHasta() async {
    final picked = await showDatePicker(context: context, initialDate: _fechaHasta ?? DateTime.now(), firstDate: _fechaDesde ?? DateTime(2020), lastDate: DateTime.now());
    if (picked != null) setState(() => _fechaHasta = picked);
  }

  Future<void> _exportarReporteCompleto() async {
    final nombreArchivo = _generarNombreArchivo('reporte_completo');
    await _helper.descargarReporte(context: context, empresaId: widget.empresaId, desde: _fechaDesde, hasta: _fechaHasta, nombreArchivo: nombreArchivo);
  }

  Future<void> _exportarReporteEspecifico(String tipo) async {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Generando reporte de $tipo...'), backgroundColor: NutritionPalette.primary, behavior: SnackBarBehavior.floating));
  }

  String _formatearFecha(DateTime f) => '${f.day.toString().padLeft(2, '0')}/${f.month.toString().padLeft(2, '0')}/${f.year}';

  String _generarNombreArchivo(String p) {
    final a = DateTime.now();
    final ts = '${a.year}${a.month.toString().padLeft(2, '0')}${a.day.toString().padLeft(2, '0')}_${a.hour}${a.minute}';
    return '${p}_$ts.xlsx';
  }
}

class _DateSelector extends StatelessWidget {
  final String label;
  final DateTime? value;
  final VoidCallback onTap;

  const _DateSelector({required this.label, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: NutritionPalette.border),
          borderRadius: BorderRadius.circular(8),
          color: NutritionPalette.background,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 11, color: NutritionPalette.textMuted, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.calendar_month_outlined, size: 16, color: value != null ? NutritionPalette.accent : NutritionPalette.textMuted),
                const SizedBox(width: 8),
                Text(
                  value != null ? '${value!.day}/${value!.month}/${value!.year}' : 'Seleccionar',
                  style: TextStyle(fontSize: 14, fontWeight: value != null ? FontWeight.bold : FontWeight.normal, color: value != null ? NutritionPalette.textMain : NutritionPalette.textMuted),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SubActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _SubActionButton({required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
      style: OutlinedButton.styleFrom(
        foregroundColor: NutritionPalette.textMain,
        side: const BorderSide(color: NutritionPalette.border),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}
