import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

class CompanyBrandingService {
  CompanyBrandingService({FirebaseFirestore? db, http.Client? client})
    : _db = db ?? FirebaseFirestore.instance,
      _client = client;

  final FirebaseFirestore _db;
  final http.Client? _client;

  static final Map<String, Uint8List?> _logoCache = {};

  /// Logo de la empresa. Sin logo propio devuelve null: marcas de agua,
  /// informes y PDF llevan la marca de la empresa y nunca la de la app
  /// (decisión del usuario, 9 oct 2026). Solo quien lo pida expresamente
  /// pasa un [fallbackAsset].
  Future<Uint8List?> loadLogoBytes(
    String? empresaId, {
    String? fallbackAsset,
  }) async {
    final eid = (empresaId ?? '').trim();
    final cached = eid.isEmpty ? null : _logoCache[eid];
    if (cached != null && cached.isNotEmpty) return cached;

    Uint8List? bytes;
    if (eid.isNotEmpty) {
      try {
        final doc = await _db.collection('TBL_EMPRESAS').doc(eid).get();
        final data = doc.data();
        final logoUrl = (data?['logoUrl'] ?? '').toString().trim();
        if (logoUrl.isNotEmpty) {
          // NetworkAssetBundle usa dart:io HttpClient y falla en Web.
          // package:http selecciona el cliente de navegador o el nativo.
          final uri = Uri.parse(logoUrl);
          final response = await (_client?.get(uri) ?? http.get(uri)).timeout(
            const Duration(seconds: 15),
          );
          if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
            bytes = response.bodyBytes;
          }
        }
      } catch (_) {}
      // Un fallo de red no se recuerda: solo se guarda el logo que sí llegó.
      if (bytes != null && bytes.isNotEmpty) _logoCache[eid] = bytes;
    }

    if (bytes != null && bytes.isNotEmpty) return bytes;
    if (fallbackAsset == null) return null;

    try {
      final fallback = await rootBundle.load(fallbackAsset);
      return fallback.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  static void clearLogoCache(String empresaId) {
    _logoCache.remove(empresaId.trim());
  }
}
