
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';

class CompanyBrandingService {
  CompanyBrandingService({FirebaseFirestore? db})
    : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  static final Map<String, Uint8List?> _logoCache = {};

  Future<Uint8List?> loadLogoBytes(
    String? empresaId, {
    String fallbackAsset = 'assets/logo.png',
  }) async {
    final eid = (empresaId ?? '').trim();
    if (eid.isNotEmpty && _logoCache.containsKey(eid)) {
      return _logoCache[eid];
    }

    Uint8List? bytes;
    if (eid.isNotEmpty) {
      try {
        final doc = await _db.collection('TBL_EMPRESAS').doc(eid).get();
        final data = doc.data();
        final logoUrl = (data?['logoUrl'] ?? '').toString().trim();
        if (logoUrl.isNotEmpty) {
          final bundle = NetworkAssetBundle(Uri.parse(logoUrl));
          final loaded = await bundle.load(logoUrl);
          bytes = loaded.buffer.asUint8List();
        }
      } catch (_) {}
      _logoCache[eid] = bytes;
    }

    if (bytes != null && bytes.isNotEmpty) return bytes;

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
