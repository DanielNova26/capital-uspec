import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Genera un PDF de reporte nutricional con:
/// - Datos del paciente
/// - Diagnósticos y plan alimentario
/// - Fotos de evidencia
/// - Firma, sello, nombre, cargo y empresa del profesional
class NutricionPdfService {
  final _db = FirebaseFirestore.instance;

  /// Descarga una imagen desde [url] y retorna los bytes, o null si falla.
  Future<Uint8List?> _fetchImageBytes(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) return response.bodyBytes;
    } catch (_) {}
    return null;
  }

  /// Obtiene los datos del usuario (nombre, cargo, empresa).
  Future<Map<String, String>> _getUserData(String userId) async {
    try {
      final doc = await _db.collection('TBL_USUARIOS').doc(userId).get();
      final data = doc.data() ?? {};
      final nombres = (data['nombres'] ?? '').toString().trim();
      final apellidos = (data['apellidos'] ?? '').toString().trim();
      final nombreCompleto =
          [nombres, apellidos].where((s) => s.isNotEmpty).join(' ');
      return {
        'nombre': nombreCompleto.isEmpty ? userId : nombreCompleto,
        'cargo': (data['cargo'] ?? '').toString().trim(),
        'empresa': (data['empresaNombre'] ?? '').toString().trim(),
      };
    } catch (_) {
      return {'nombre': userId, 'cargo': '', 'empresa': ''};
    }
  }

  /// Genera el PDF del reporte nutricional y retorna los bytes.
  ///
  /// [pacienteData] mapa con los campos del paciente (nombre, documento, etc.)
  /// [firmaUrl] URL de la firma del profesional
  /// [selloUrl] URL del sello del profesional
  /// [evidenciasUrls] lista de URLs de fotos de evidencia
  Future<Uint8List> generarReportePDF({
    required String userId,
    required Map<String, dynamic> pacienteData,
    required String firmaUrl,
    required String selloUrl,
    List<String> evidenciasUrls = const [],
  }) async {
    final pdf = pw.Document();

    // 1) Datos del profesional desde Firestore
    final userData = await _getUserData(userId);

    // 2) Descargar imágenes en paralelo
    final futures = <Future<Uint8List?>>[];
    futures.add(_fetchImageBytes(firmaUrl));
    futures.add(_fetchImageBytes(selloUrl));
    for (final url in evidenciasUrls) {
      futures.add(_fetchImageBytes(url));
    }
    final images = await Future.wait(futures);

    final firmaBytes = images[0];
    final selloBytes = images[1];
    final evidenciasBytes =
        images.sublist(2).whereType<Uint8List>().toList();

    // 3) Construir imágenes pw
    pw.MemoryImage? firmaImg;
    pw.MemoryImage? selloImg;
    if (firmaBytes != null) firmaImg = pw.MemoryImage(firmaBytes);
    if (selloBytes != null) selloImg = pw.MemoryImage(selloBytes);

    final evidenciasImgs =
        evidenciasBytes.map((b) => pw.MemoryImage(b)).toList();

    // 4) Extraer datos del paciente
    final nombre =
        (pacienteData['nombreCompleto'] ?? pacienteData['nombre'] ?? '')
            .toString();
    final documento = (pacienteData['documento'] ?? '').toString();
    final regimen = (pacienteData['regimenAfiliacion'] ?? '').toString();
    final dxMedico = (pacienteData['diagnosticoMedico'] ?? '').toString();
    final dxNutri = (pacienteData['diagnosticoNutricional'] ?? '').toString();
    final dieta = (pacienteData['tipoDietaSugerida'] ?? '').toString();
    final duracion = (pacienteData['duracionDieta'] ?? '').toString();
    final observaciones = (pacienteData['observaciones'] ?? '').toString();
    final inicioDieta = (pacienteData['inicioDieta'] ?? '').toString();
    final fechaReeval =
        (pacienteData['fechaReevaluacion'] ?? '').toString();
    final fechaReporte =
        DateFormat('dd/MM/yyyy HH:mm', 'es').format(DateTime.now());

    // Colores
    const azul = PdfColor.fromInt(0xFF2563EB);
    const grisClaro = PdfColor.fromInt(0xFFF3F4F6);
    const grisBorde = PdfColor.fromInt(0xFFD1D5DB);
    const negro = PdfColors.black;
    const blancoColor = PdfColors.white;

    // 5) Construir página
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (ctx) => _buildHeader(
          fechaReporte: fechaReporte,
          azul: azul,
          blancoColor: blancoColor,
        ),
        footer: (ctx) => _buildFooter(
          pageNumber: ctx.pageNumber,
          totalPages: ctx.pagesCount,
          grisBorde: grisBorde,
        ),
        build: (ctx) => [
          pw.SizedBox(height: 16),

          // Sección datos del paciente
          _buildSectionTitle('Datos del Paciente', azul),
          pw.SizedBox(height: 8),
          _buildInfoTable([
            ['Nombre completo', nombre],
            ['Documento', documento],
            ['Régimen de afiliación', regimen],
          ], grisClaro, grisBorde, negro),

          pw.SizedBox(height: 16),

          // Sección información clínica
          _buildSectionTitle('Información Clínica y Nutricional', azul),
          pw.SizedBox(height: 8),
          _buildInfoTable([
            ['Diagnóstico médico', dxMedico],
            ['Diagnóstico nutricional', dxNutri],
            ['Tipo de dieta', dieta],
            ['Duración de dieta', duracion],
          ], grisClaro, grisBorde, negro),

          if (observaciones.isNotEmpty) ...[
            pw.SizedBox(height: 8),
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: grisClaro,
                border: pw.Border.all(color: grisBorde),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Observaciones y recomendaciones:',
                      style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold, fontSize: 10)),
                  pw.SizedBox(height: 4),
                  pw.Text(observaciones,
                      style: const pw.TextStyle(fontSize: 10)),
                ],
              ),
            ),
          ],

          pw.SizedBox(height: 16),

          // Sección plan alimentario
          _buildSectionTitle('Plan Alimentario', azul),
          pw.SizedBox(height: 8),
          _buildInfoTable([
            ['Inicio de dieta', inicioDieta],
            ['Fecha tentativa de reevaluación', fechaReeval],
          ], grisClaro, grisBorde, negro),

          // Fotos de evidencia
          if (evidenciasImgs.isNotEmpty) ...[
            pw.SizedBox(height: 20),
            _buildSectionTitle('Evidencias Fotográficas', azul),
            pw.SizedBox(height: 8),
            pw.Wrap(
              spacing: 12,
              runSpacing: 12,
              children: evidenciasImgs
                  .map(
                    (img) => pw.Container(
                      width: 200,
                      height: 150,
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: grisBorde),
                        borderRadius:
                            const pw.BorderRadius.all(pw.Radius.circular(6)),
                      ),
                      child: pw.ClipRRect(
                        horizontalRadius: 6,
                        verticalRadius: 6,
                        child: pw.Image(img, fit: pw.BoxFit.cover),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],

          pw.SizedBox(height: 32),

          // Sección firma y cierre
          _buildFirmaSection(
            nombreProfesional: userData['nombre']!,
            cargo: userData['cargo']!,
            empresa: userData['empresa']!,
            firmaImg: firmaImg,
            selloImg: selloImg,
            grisBorde: grisBorde,
            grisClaro: grisClaro,
            azul: azul,
            negro: negro,
            blancoColor: blancoColor,
          ),
        ],
      ),
    );

    return pdf.save();
  }

  pw.Widget _buildHeader({
    required String fechaReporte,
    required PdfColor azul,
    required PdfColor blancoColor,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: pw.BoxDecoration(color: azul),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'REPORTE NUTRICIONAL',
                style: pw.TextStyle(
                  color: blancoColor,
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                'Sistema de Gestión Nutricional',
                style: pw.TextStyle(color: blancoColor, fontSize: 10),
              ),
            ],
          ),
          pw.Text(
            fechaReporte,
            style: pw.TextStyle(color: blancoColor, fontSize: 10),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildFooter({
    required int pageNumber,
    required int totalPages,
    required PdfColor grisBorde,
  }) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 8),
      padding: const pw.EdgeInsets.only(top: 6),
      decoration: pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: grisBorde)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('Documento confidencial - Uso médico/nutricional',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey)),
          pw.Text('Página $pageNumber de $totalPages',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey)),
        ],
      ),
    );
  }

  pw.Widget _buildSectionTitle(String title, PdfColor azul) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: pw.BoxDecoration(
        color: azul,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      child: pw.Text(
        title,
        style: pw.TextStyle(
          color: PdfColors.white,
          fontWeight: pw.FontWeight.bold,
          fontSize: 11,
        ),
      ),
    );
  }

  pw.Widget _buildInfoTable(
    List<List<String>> rows,
    PdfColor grisClaro,
    PdfColor grisBorde,
    PdfColor negro,
  ) {
    return pw.Table(
      border: pw.TableBorder.all(color: grisBorde, width: 0.5),
      columnWidths: {
        0: const pw.FlexColumnWidth(2),
        1: const pw.FlexColumnWidth(3),
      },
      children: rows.map((row) {
        final isEven = rows.indexOf(row) % 2 == 0;
        return pw.TableRow(
          decoration: pw.BoxDecoration(
            color: isEven ? grisClaro : PdfColors.white,
          ),
          children: [
            pw.Padding(
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: pw.Text(
                row[0],
                style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 10,
                    color: negro),
              ),
            ),
            pw.Padding(
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: pw.Text(
                row[1].isEmpty ? '—' : row[1],
                style: pw.TextStyle(fontSize: 10, color: negro),
              ),
            ),
          ],
        );
      }).toList(),
    );
  }

  pw.Widget _buildFirmaSection({
    required String nombreProfesional,
    required String cargo,
    required String empresa,
    required pw.MemoryImage? firmaImg,
    required pw.MemoryImage? selloImg,
    required PdfColor grisBorde,
    required PdfColor grisClaro,
    required PdfColor azul,
    required PdfColor negro,
    required PdfColor blancoColor,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        color: grisClaro,
        border: pw.Border.all(color: grisBorde),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Firma y certificación del profesional',
            style: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              fontSize: 11,
              color: azul,
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Firma
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text('Firma',
                        style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 9,
                            color: negro)),
                    pw.SizedBox(height: 6),
                    pw.Container(
                      height: 80,
                      width: double.infinity,
                      decoration: pw.BoxDecoration(
                        color: PdfColors.white,
                        border: pw.Border.all(color: grisBorde),
                        borderRadius:
                            const pw.BorderRadius.all(pw.Radius.circular(4)),
                      ),
                      child: firmaImg != null
                          ? pw.Padding(
                              padding: const pw.EdgeInsets.all(4),
                              child: pw.Image(firmaImg, fit: pw.BoxFit.contain),
                            )
                          : pw.Center(
                              child: pw.Text('Sin firma',
                                  style: const pw.TextStyle(
                                      fontSize: 8, color: PdfColors.grey))),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(width: 16),
              // Sello
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text('Sello',
                        style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 9,
                            color: negro)),
                    pw.SizedBox(height: 6),
                    pw.Container(
                      height: 80,
                      width: double.infinity,
                      decoration: pw.BoxDecoration(
                        color: PdfColors.white,
                        border: pw.Border.all(color: grisBorde),
                        borderRadius:
                            const pw.BorderRadius.all(pw.Radius.circular(4)),
                      ),
                      child: selloImg != null
                          ? pw.Padding(
                              padding: const pw.EdgeInsets.all(4),
                              child: pw.Image(selloImg, fit: pw.BoxFit.contain),
                            )
                          : pw.Center(
                              child: pw.Text('Sin sello',
                                  style: const pw.TextStyle(
                                      fontSize: 8, color: PdfColors.grey))),
                    ),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 12),
          // Línea separadora
          pw.Divider(color: grisBorde),
          pw.SizedBox(height: 8),
          // Datos del profesional
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    nombreProfesional.isNotEmpty
                        ? nombreProfesional
                        : 'Nutricionista',
                    style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 11,
                        color: negro),
                  ),
                  if (cargo.isNotEmpty) ...[
                    pw.SizedBox(height: 2),
                    pw.Text(cargo,
                        style:
                            const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
                  ],
                  if (empresa.isNotEmpty) ...[
                    pw.SizedBox(height: 2),
                    pw.Text(empresa,
                        style:
                            const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
                  ],
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
