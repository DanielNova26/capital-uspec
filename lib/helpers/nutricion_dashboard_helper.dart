import 'dart:io';
import 'dart:typed_data';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import '../services/nutricion_service.dart';
import '../services/nutricion_report_service.dart';

/// Helper class para integrar los servicios de nutrición con el dashboard.
/// Proporciona métodos de alto nivel para operaciones comunes y manejo de errores.
class NutricionDashboardHelper {
  final NutricionService _nutricionService;
  final NutricionReportService _reportService;

  NutricionDashboardHelper({
    NutricionService? nutricionService,
    NutricionReportService? reportService,
  })  : _nutricionService = nutricionService ?? NutricionService(),
        _reportService = reportService ?? NutricionReportService();

  // ---------------------------------------------------------------------------
  // DIRECTORIO DE PACIENTES
  // ---------------------------------------------------------------------------

  /// Stream de pacientes desde el directorio de nutrición.
  /// Retorna una lista de mapas con id, nombreCompleto y documento.
  Stream<List<Map<String, dynamic>>> streamPacientes({
    required String empresaId,
  }) {
    return _nutricionService.streamDirectorioNutricion(
      empresaId: empresaId,
    );
  }

  /// Guarda o actualiza un paciente en el directorio.
  /// Si [id] es null, crea un nuevo documento.
  /// Si [id] se proporciona, actualiza el documento existente.
  Future<void> guardarPaciente({
    required BuildContext context,
    required String empresaId,
    required String userId,
    required Map<String, dynamic> data,
    String? id,
  }) async {
    try {
      await _nutricionService.guardarDirectorioNutricion(
        empresaId: empresaId,
        userId: userId,
        data: data,
        id: id,
      );
    } catch (e) {
      if (context.mounted) {
        _showError(context, 'Error al guardar paciente: $e');
      }
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // REPORTES
  // ---------------------------------------------------------------------------

  /// Exporta un resumen en Excel de menús y derivaciones.
  /// Opcionalmente filtra por rango de fechas.
  Future<Uint8List?> exportarResumen({
    required BuildContext context,
    required String empresaId,
    DateTime? desde,
    DateTime? hasta,
  }) async {
    try {
      return await _reportService.exportResumen(
        empresaId: empresaId,
        desde: desde,
        hasta: hasta,
      );
    } catch (e) {
      if (context.mounted) {
        _showError(context, 'Error al exportar reporte: $e');
      }
      return null;
    }
  }

  /// Descarga un reporte Excel y lo guarda en el dispositivo.
  Future<void> descargarReporte({
    required BuildContext context,
    required String empresaId,
    DateTime? desde,
    DateTime? hasta,
    String nombreArchivo = 'reporte_nutricion.xlsx',
  }) async {
    // Mostrar loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Generando reporte...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final bytes = await exportarResumen(
        context: context,
        empresaId: empresaId,
        desde: desde,
        hasta: hasta,
      );

      if (!context.mounted) return;
      Navigator.of(context).pop(); // Cerrar loading

      if (bytes == null) {
        _showError(context, 'No se pudo generar el reporte');
        return;
      }

      if (kIsWeb) {
        await FileSaver.instance.saveFile(
          name: nombreArchivo.replaceAll('.xlsx', ''),
          bytes: bytes,
          fileExtension: 'xlsx',
          mimeType: MimeType.microsoftExcel,
        );
      } else {
        final dir = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/$nombreArchivo');
        await file.writeAsBytes(bytes);
        await OpenFilex.open(file.path);
      }

      _showSuccess(context, 'Reporte descargado: $nombreArchivo');
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context).pop(); // Cerrar loading
      _showError(context, 'Error al descargar reporte: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // VALIDACIONES
  // ---------------------------------------------------------------------------

  /// Valida que los datos del paciente sean correctos antes de guardar.
  String? validarDatosPaciente(Map<String, dynamic> data) {
    final nombre = (data['nombreCompleto'] ?? '').toString().trim();
    final documento = (data['documento'] ?? '').toString().trim();

    if (nombre.isEmpty) {
      return 'El nombre completo es obligatorio';
    }

    if (documento.isEmpty) {
      return 'El número de documento es obligatorio';
    }

    // Validar que el documento sea numérico (o según tus reglas)
    if (!RegExp(r'^\d+$').hasMatch(documento)) {
      return 'El documento debe contener solo números';
    }

    return null; // Sin errores
  }

  // ---------------------------------------------------------------------------
  // UTILIDADES PRIVADAS
  // ---------------------------------------------------------------------------

  void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Theme.of(context).colorScheme.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  void _showSuccess(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 8),
            Text(message),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}

/// Extension methods para facilitar el uso del helper desde cualquier widget.
extension NutricionDashboardHelperExtension on BuildContext {
  /// Obtiene una instancia del helper de nutrición.
  /// Puede extenderse para usar Provider o GetIt si lo prefieres.
  NutricionDashboardHelper get nutricionHelper => NutricionDashboardHelper();
}