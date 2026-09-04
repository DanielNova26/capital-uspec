// lib/talento_humano/carnet_qr.dart
//
// QR del carnet: el enlace que se imprime y lo que se ve al escanearlo.
//
// El QR NO lleva la cédula. Lleva un token aleatorio que no dice nada de la
// persona, y la página pública la sirve una Cloud Function que decide qué
// mostrar (foto, nombre, cargo, empresa y si sigue vinculada). Un carnet se
// fotografía y se comparte; poner la cédula en el enlace lo convertiría en una
// llave, porque además es el ID de la persona en varias colecciones.
//
// Si un carnet se pierde, se genera otro token: el anterior deja de resolver
// sin tocar nada más.

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Dominio donde vive la página del carnet. La ruta `/carnet/**` está
/// redirigida a la función `carnetPublico` en `firebase.json`.
const String kCarnetBaseUrl = 'https://to-do-gestion.com/carnet';

String urlCarnet(String token) => '$kCarnetBaseUrl/$token';

/// Token aleatorio de 32 caracteres.
///
/// `Random.secure()` y no `Random()`: uno predecible permitiría adivinar los
/// carnets de los demás a partir de uno propio.
String generarTokenCarnet([Random? random]) {
  final rnd = random ?? Random.secure();
  final bytes = Uint8List.fromList(
    List<int>.generate(24, (_) => rnd.nextInt(256)),
  );
  return base64Url.encode(bytes).replaceAll('=', '');
}

/// Devuelve el token del carnet de la persona, creándolo si no lo tiene.
///
/// Guarda también `carnetEmpresaId`: la función la usa para leer el estado
/// laboral EN VIVO. Congelar un "activo" haría que el carnet de quien ya se
/// retiró siguiera diciendo que sigue vinculado.
Future<String> asegurarTokenCarnet({
  required String userId,
  required String empresaId,
  FirebaseFirestore? db,
  String Function()? generador,
}) async {
  final firestore = db ?? FirebaseFirestore.instance;
  final ref = firestore.collection('TBL_USUARIOS').doc(userId);
  final snap = await ref.get();
  final actual = (snap.data()?['carnetToken'] ?? '').toString().trim();

  if (actual.isNotEmpty) {
    // La empresa puede haber cambiado desde la última vez.
    if ((snap.data()?['carnetEmpresaId'] ?? '') != empresaId) {
      await ref.set({'carnetEmpresaId': empresaId}, SetOptions(merge: true));
    }
    return actual;
  }

  final token = (generador ?? generarTokenCarnet)();
  await ref.set({
    'carnetToken': token,
    'carnetEmpresaId': empresaId,
    'carnetGeneradoEn': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
  return token;
}

/// Genera un token nuevo, invalidando el carnet anterior.
Future<String> rotarTokenCarnet({
  required String userId,
  required String empresaId,
  FirebaseFirestore? db,
  String Function()? generador,
}) async {
  final firestore = db ?? FirebaseFirestore.instance;
  final token = (generador ?? generarTokenCarnet)();
  await firestore.collection('TBL_USUARIOS').doc(userId).set({
    'carnetToken': token,
    'carnetEmpresaId': empresaId,
    'carnetGeneradoEn': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
  return token;
}

const PdfColor _kInk = PdfColor.fromInt(0xFF1E293B);
const PdfColor _kMuted = PdfColor.fromInt(0xFF64748B);
const PdfColor _kLine = PdfColor.fromInt(0xFFE2E8F0);

/// Hoja lista para recortar y pegar en el carnet.
///
/// Sale con el nombre y el cargo junto al QR para que, al imprimir varios, no
/// haya que escanearlos uno por uno para saber de quién es cada uno.
Future<Uint8List> buildCarnetQrPdf({
  required String nombre,
  required String cargo,
  required String token,
  String empresaNombre = '',
  String? fotoUrl,
  DateTime? generatedAt,
}) async {
  final url = urlCarnet(token);
  final fecha = DateFormat('dd/MM/yyyy').format(generatedAt ?? DateTime.now());

  pw.ImageProvider? foto;
  if (fotoUrl != null && fotoUrl.trim().isNotEmpty) {
    try {
      final r = await http.get(Uri.parse(fotoUrl));
      if (r.statusCode == 200) foto = pw.MemoryImage(r.bodyBytes);
    } catch (_) {
      // Sin foto se imprime igual: el QR es lo que importa.
    }
  }

  final doc = pw.Document(theme: await _temaConAcentos());
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a6.copyWith(
        marginTop: 18,
        marginBottom: 18,
        marginLeft: 18,
        marginRight: 18,
      ),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          if (foto != null) ...[
            pw.Container(
              width: 56,
              height: 56,
              decoration: pw.BoxDecoration(
                shape: pw.BoxShape.circle,
                image: pw.DecorationImage(image: foto, fit: pw.BoxFit.cover),
              ),
            ),
            pw.SizedBox(height: 8),
          ],
          pw.Text(
            nombre.trim().isEmpty ? 'Sin nombre' : nombre.trim(),
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
              color: _kInk,
            ),
          ),
          if (cargo.trim().isNotEmpty) ...[
            pw.SizedBox(height: 2),
            pw.Text(
              cargo.trim(),
              textAlign: pw.TextAlign.center,
              style: const pw.TextStyle(fontSize: 9, color: _kMuted),
            ),
          ],
          pw.SizedBox(height: 12),
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: _kLine),
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.BarcodeWidget(
              barcode: pw.Barcode.qrCode(),
              data: url,
              width: 118,
              height: 118,
              drawText: false,
            ),
          ),
          pw.SizedBox(height: 10),
          if (empresaNombre.trim().isNotEmpty)
            pw.Text(
              empresaNombre.trim(),
              textAlign: pw.TextAlign.center,
              style: const pw.TextStyle(fontSize: 8, color: _kMuted),
            ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Escanea para verificar el carnet · $fecha',
            textAlign: pw.TextAlign.center,
            style: const pw.TextStyle(fontSize: 6.5, color: _kMuted),
          ),
        ],
      ),
    ),
  );
  return doc.save();
}

/// Tema con una fuente que sí tiene tildes y ñ.
///
/// Las fuentes por defecto del paquete `pdf` son Helvetica, que no soporta
/// Unicode: sin esto "Cómbita" y "Muñoz" salen partidos en el documento.
/// Se carga a la defensiva porque un PDF sin acentos es mejor que ninguno.
Future<pw.ThemeData?> _temaConAcentos() async {
  try {
    final data = await rootBundle.load('assets/arial.ttf');
    final arial = pw.Font.ttf(data);
    return pw.ThemeData.withFont(base: arial, bold: arial);
  } catch (_) {
    return null;
  }
}
