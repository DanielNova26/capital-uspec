// lib/gestion_documental/planillas/pp_service.dart
//
// Servicio del subflujo Planillas de Pago.
//
// Colecciones:
//   TBL_PP_LOTES     — lotes de carga
//   TBL_PP_PLANILLAS — planillas individuales
//   TBL_PP_FLUJO     — historial append-only
//
// Storage:
//   planillas_pago/{empresaId}/{loteId}/excel/{ts}_{nombre}.xlsx
//   planillas_pago/{empresaId}/{loteId}/pdfs/{ts}_{nombre}.pdf
//
// Reutiliza la firma guardada dentro de TBL_USUARIOS para firma de gerencia.
//
// Regla crítica: TBL_PP_FLUJO es append-only. Nunca se modifica ni elimina.

import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../services/task_service.dart';
import '../../utils/url_binary_loader.dart';
import '../../utils/user_company.dart';
import 'pp_excel_parser.dart';
import 'pp_models.dart';

class PpException implements Exception {
  final String mensaje;
  const PpException(this.mensaje);
  @override
  String toString() => 'PpException: $mensaje';
}

class _PdfStampBlock {
  final String titulo;
  final PdfColor color;
  final Uint8List? firmaBytes;
  final String? nombre;
  final String? cargo;
  final String? fecha;

  const _PdfStampBlock({
    required this.titulo,
    required this.color,
    this.firmaBytes,
    this.nombre,
    this.cargo,
    this.fecha,
  });
}

class _ResolvedLogo {
  final Uint8List bytes;
  final String? path;
  final String? url;
  final String? nombre;
  final bool sinLogo;

  const _ResolvedLogo({
    required this.bytes,
    this.path,
    this.url,
    this.nombre,
    this.sinLogo = false,
  });
}

typedef _RenderedPdfPage = ({
  Uint8List pngBytes,
  double widthPx,
  double heightPx,
});

class PpService {
  static const String _colLotes = 'TBL_PP_LOTES';
  static const String _colPlanillas = 'TBL_PP_PLANILLAS';
  static const String _colFlujo = 'TBL_PP_FLUJO';
  static const String _colUsuarios = 'TBL_USUARIOS';
  static const String _colConfig = 'TBL_PP_CONFIG';
  static const String _colEmpresas = 'TBL_EMPRESAS';
  static const int _maxStorageDownloadBytes = 50 * 1024 * 1024;
  static const double _renderCacheDpi = 120.0;
  static const int _maxFirestorePdfChunkBytes = 700 * 1024;
  static const int _maxInlinePdfDocBytes = 900 * 1024;

  final FirebaseFirestore _db;
  final FirebaseStorage _storage;
  final FirebaseFunctions _functions;
  final TaskService _taskService;
  final PpExcelParser _excelParser;

  PpService({
    FirebaseFirestore? db,
    FirebaseStorage? storage,
    FirebaseFunctions? functions,
    TaskService? taskService,
    PpExcelParser? excelParser,
  }) : _db = db ?? FirebaseFirestore.instance,
       _storage = storage ?? FirebaseStorage.instance,
       _functions =
           functions ?? FirebaseFunctions.instanceFor(region: 'us-central1'),
       _taskService = taskService ?? TaskService(),
       _excelParser = excelParser ?? PpExcelParser();

  CollectionReference<Map<String, dynamic>> get _lotes =>
      _db.collection(_colLotes);
  CollectionReference<Map<String, dynamic>> get _planillas =>
      _db.collection(_colPlanillas);
  CollectionReference<Map<String, dynamic>> get _flujo =>
      _db.collection(_colFlujo);
  CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection(_colUsuarios);

  bool _esPdfDirectoTipo(String tipoGeneracion) =>
      tipoGeneracion == 'pdf_directo' || tipoGeneracion == 'pdf_cargado';

  // ─────────────────────────────────────────────────────────────────────────
  // LOGO CONFIG
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns all logos and the active path for the company.
  Future<({List<Map<String, String>> logos, String? logoActivoPath})>
  getLogoConfig(String empresaId) async {
    try {
      final doc = await _db.collection(_colConfig).doc(empresaId).get();
      if (!doc.exists) {
        return (logos: <Map<String, String>>[], logoActivoPath: null);
      }
      final data = doc.data()!;
      final rawLogos = data['logos'];
      final logos = rawLogos is List
          ? rawLogos
                .whereType<Map>()
                .map<Map<String, String>>((m) {
                  final rawPath = _cleanString(m['path']);
                  final rawUrl =
                      _normalizeStorageUrl(m['url']) ??
                      _normalizeStorageUrl(rawPath);
                  final resolvedPath =
                      _normalizeStoragePath(rawPath) ??
                      _normalizeStoragePath(rawUrl);
                  final b64 = (m['b64'] ?? '').toString();
                  return {
                    'nombre': (m['nombre'] ?? '').toString(),
                    'path': resolvedPath ?? '',
                    'url': rawUrl ?? '',
                    if (b64.isNotEmpty) 'b64': b64,
                  };
                })
                .where(
                  (logo) => logo['path']!.isNotEmpty || logo['url']!.isNotEmpty,
                )
                .toList()
          : <Map<String, String>>[];
      // Backwards-compat: single logo stored with old schema
      if (logos.isEmpty) {
        final oldPath =
            _normalizeStoragePath(data['logoPath']) ??
            _normalizeStoragePath(data['logoUrl']);
        final oldNombre = data['logoNombre'] as String?;
        if (oldPath != null && oldPath.isNotEmpty) {
          logos.add({
            'nombre': oldNombre ?? 'Logo',
            'path': oldPath,
            'url':
                _normalizeStorageUrl(data['logoUrl']) ??
                _normalizeStorageUrl(data['logoPath']) ??
                '',
          });
        }
      }
      return (
        logos: logos,
        logoActivoPath:
            _normalizeStoragePath(data['logoActivoPath']) ??
            _normalizeStoragePath(data['logoPath']) ??
            logos.firstOrNull?['path'],
      );
    } catch (_) {
      return (logos: <Map<String, String>>[], logoActivoPath: null);
    }
  }

  Future<Map<String, String>?> getLogoActivoMeta(String empresaId) async {
    final config = await getLogoConfig(empresaId);
    if (config.logos.isEmpty) return null;

    final activePath = _cleanString(config.logoActivoPath);
    if (activePath == null) return config.logos.first;

    for (final logo in config.logos) {
      if (_cleanString(logo['path']) == activePath) {
        return logo;
      }
    }
    return config.logos.first;
  }

  Future<String> _resolverNombreEmpresaPlanilla({
    required String empresaId,
    String? nombreLogoPreferido,
    Map<String, dynamic>? planillaData,
  }) async {
    final datosExcel = planillaData?['datosExcel'];
    final desdePlanilla =
        _cleanString(planillaData?['empresaNombre']) ??
        _cleanString(datosExcel is Map ? datosExcel['empresa_nombre'] : null) ??
        _cleanString(planillaData?['logoNombre']) ??
        _cleanString(datosExcel is Map ? datosExcel['logo_nombre'] : null) ??
        _cleanString(nombreLogoPreferido);
    if (desdePlanilla != null) return desdePlanilla;

    final logoActivo = await getLogoActivoMeta(empresaId);
    final desdeLogoActivo = _cleanString(logoActivo?['nombre']);
    if (desdeLogoActivo != null) return desdeLogoActivo;

    try {
      final empresaSnap = await _db
          .collection(_colEmpresas)
          .doc(empresaId)
          .get();
      final data = empresaSnap.data();
      final nombre =
          _cleanString(data?['nombre']) ??
          _cleanString(data?['empresaNombre']) ??
          _cleanString(data?['razonSocial']);
      if (nombre != null) return nombre;
    } catch (_) {}

    return empresaId.trim();
  }

  Future<Uint8List?> cargarLogoBytes({
    required String path,
    String? url,
    String? b64,
  }) async {
    // Prioridad 1: bytes guardados en Firestore (sin CORS, funciona en web)
    if (b64 != null && b64.isNotEmpty) {
      try {
        final decoded = base64Decode(b64);
        if (decoded.isNotEmpty) return decoded;
      } catch (_) {}
    }
    // Fallback: Storage (puede fallar en web si no hay CORS configurado)
    return _loadBinary(path: path, url: url);
  }

  Future<void> guardarLogo({
    required String empresaId,
    required Uint8List bytes,
    required String nombre,
    required String extension,
  }) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final path = 'planillas_pago/$empresaId/config/logo_$ts.$extension';
    final ref = _storage.ref(path);
    final normalizedExt = extension.toLowerCase();
    final contentType = switch (normalizedExt) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      _ => 'image/$normalizedExt',
    };
    await ref.putData(bytes, SettableMetadata(contentType: contentType));
    final url = await ref.getDownloadURL();
    final b64 = base64Encode(bytes);
    final entry = {'nombre': nombre, 'path': path, 'url': url, 'b64': b64};
    final doc = await _db.collection(_colConfig).doc(empresaId).get();
    List<dynamic> logos = [];
    if (doc.exists) {
      final raw = doc.data()?['logos'];
      if (raw is List) logos = List<dynamic>.from(raw);
    }
    logos.add(entry);
    await _db.collection(_colConfig).doc(empresaId).set({
      'logos': logos,
      'logoActivoPath': path,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> setLogoActivo(String empresaId, String path) async {
    final safePath = _normalizeStoragePath(path);
    if (safePath == null) {
      throw const PpException('Selecciona un logo válido.');
    }
    await _db.collection(_colConfig).doc(empresaId).set({
      'logoActivoPath': safePath,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> eliminarLogo({
    required String empresaId,
    required String logoPath,
    required String rolPlanillas,
  }) async {
    _validarRol('eliminar_logo', rolPlanillas);
    final safePath = _normalizeStoragePath(logoPath);
    if (safePath == null) {
      throw const PpException('Selecciona un logo válido para eliminar.');
    }

    final ref = _db.collection(_colConfig).doc(empresaId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;

      final data = snap.data() ?? <String, dynamic>{};
      final rawLogos = data['logos'];
      final logos = rawLogos is List
          ? rawLogos
                .whereType<Map>()
                .map<Map<String, dynamic>>((m) {
                  final rawPath = _cleanString(m['path']);
                  final rawUrl =
                      _normalizeStorageUrl(m['url']) ??
                      _normalizeStorageUrl(rawPath);
                  final resolvedPath =
                      _normalizeStoragePath(rawPath) ??
                      _normalizeStoragePath(rawUrl);
                  return <String, dynamic>{
                    'nombre': (m['nombre'] ?? '').toString(),
                    'path': resolvedPath ?? '',
                    'url': rawUrl ?? '',
                  };
                })
                .where(
                  (logo) =>
                      ((logo['path'] ?? '').toString().trim().isNotEmpty) ||
                      ((logo['url'] ?? '').toString().trim().isNotEmpty),
                )
                .toList()
          : <Map<String, dynamic>>[];

      logos.removeWhere(
        (logo) => _normalizeStoragePath(logo['path']) == safePath,
      );

      final activePath = _normalizeStoragePath(data['logoActivoPath']);
      final nextActivePath = logos.isEmpty
          ? null
          : activePath == safePath
          ? _normalizeStoragePath(logos.first['path'])
          : (activePath ?? _normalizeStoragePath(logos.first['path']));

      final update = <String, dynamic>{
        'logos': logos,
        'updatedAt': FieldValue.serverTimestamp(),
        'logoPath': FieldValue.delete(),
        'logoUrl': FieldValue.delete(),
        'logoNombre': FieldValue.delete(),
        'logoActivoPath': nextActivePath ?? FieldValue.delete(),
      };

      tx.set(ref, update, SetOptions(merge: true));
    });

    try {
      await _storage.ref(safePath).delete();
    } catch (_) {}
  }

  String? _cleanString(dynamic value) {
    final text = (value ?? '').toString().trim();
    return text.isEmpty ? null : text;
  }

  String? _normalizeStorageUrl(dynamic value) {
    final raw = _cleanString(value);
    if (raw == null) return null;
    final lower = raw.toLowerCase();
    if (lower.startsWith('http://') ||
        lower.startsWith('https://') ||
        lower.startsWith('gs://')) {
      return raw;
    }
    return null;
  }

  String? _normalizeStoragePath(dynamic value) {
    final raw = _cleanString(value);
    if (raw == null) return null;

    if (raw.startsWith('gs://')) {
      final slashIndex = raw.indexOf('/', 5);
      if (slashIndex < 0 || slashIndex + 1 >= raw.length) return null;
      return _normalizeRelativeStoragePath(raw.substring(slashIndex + 1));
    }

    final lower = raw.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      return _extractStoragePathFromUrl(raw);
    }

    return _normalizeRelativeStoragePath(raw);
  }

  String? _normalizeRelativeStoragePath(dynamic value) {
    final raw = _cleanString(value);
    if (raw == null) return null;
    var normalized = raw.replaceAll('\\', '/').trim();
    while (normalized.startsWith('/')) {
      normalized = normalized.substring(1);
    }
    return normalized.isEmpty ? null : normalized;
  }

  String? _extractStoragePathFromUrl(String url) {
    try {
      final marker = '/o/';
      final markerIndex = url.indexOf(marker);
      if (markerIndex >= 0) {
        final tail = url.substring(markerIndex + marker.length);
        final encodedPath = tail.split('?').first;
        return _normalizeRelativeStoragePath(Uri.decodeFull(encodedPath));
      }

      final uri = Uri.parse(url);
      final fromName = _cleanString(uri.queryParameters['name']);
      if (fromName != null) {
        return _normalizeRelativeStoragePath(Uri.decodeFull(fromName));
      }
    } catch (_) {}
    return null;
  }

  _ResolvedLogo _logoMetaDesdePlanilla(Map<String, dynamic>? planillaData) {
    final datosExcel = planillaData?['datosExcel'];
    final sinLogoRaw =
        planillaData?['sinLogo'] ??
        (datosExcel is Map ? datosExcel['sin_logo'] : null);
    final sinLogo =
        sinLogoRaw == true ||
        sinLogoRaw.toString().trim().toLowerCase() == 'true';

    return _ResolvedLogo(
      bytes: Uint8List(0),
      path:
          _normalizeStoragePath(
            planillaData?['logoPath'] ??
                (datosExcel is Map ? datosExcel['logo_path'] : null),
          ) ??
          _normalizeStoragePath(
            planillaData?['logoUrl'] ??
                (datosExcel is Map ? datosExcel['logo_url'] : null),
          ),
      url:
          _normalizeStorageUrl(
            planillaData?['logoUrl'] ??
                (datosExcel is Map ? datosExcel['logo_url'] : null),
          ) ??
          _normalizeStorageUrl(
            planillaData?['logoPath'] ??
                (datosExcel is Map ? datosExcel['logo_path'] : null),
          ),
      nombre: _cleanString(
        planillaData?['logoNombre'] ??
            (datosExcel is Map ? datosExcel['logo_nombre'] : null),
      ),
      sinLogo: sinLogo,
    );
  }

  Future<_ResolvedLogo> _resolverLogoGeneracion({
    required String empresaId,
    Uint8List? logoBytes,
    String? logoPath,
    String? logoUrl,
    String? logoNombre,
    bool sinLogo = false,
    Map<String, dynamic>? planillaData,
  }) async {
    final fromPlanilla = _logoMetaDesdePlanilla(planillaData);
    final resolvedSinLogo = sinLogo || fromPlanilla.sinLogo;
    final resolvedPath = _normalizeStoragePath(logoPath) ?? fromPlanilla.path;
    final resolvedUrl =
        _normalizeStorageUrl(logoUrl) ??
        _normalizeStorageUrl(logoPath) ??
        fromPlanilla.url;
    final resolvedNombre = _cleanString(logoNombre) ?? fromPlanilla.nombre;
    final requestedLogo =
        (resolvedPath?.isNotEmpty ?? false) ||
        (resolvedUrl?.isNotEmpty ?? false) ||
        (resolvedNombre?.isNotEmpty ?? false);

    if (resolvedSinLogo) {
      return _ResolvedLogo(
        bytes: Uint8List(0),
        path: resolvedPath,
        url: resolvedUrl,
        nombre: resolvedNombre,
        sinLogo: true,
      );
    }

    if (logoBytes != null && logoBytes.isNotEmpty) {
      return _ResolvedLogo(
        bytes: logoBytes,
        path: resolvedPath,
        url: resolvedUrl,
        nombre: resolvedNombre,
      );
    }

    if ((resolvedPath?.isNotEmpty ?? false) ||
        (resolvedUrl?.isNotEmpty ?? false)) {
      final bytes = await _loadBinary(url: resolvedUrl, path: resolvedPath);
      if (bytes != null && bytes.isNotEmpty) {
        return _ResolvedLogo(
          bytes: bytes,
          path: resolvedPath,
          url: resolvedUrl,
          nombre: resolvedNombre,
        );
      }
      throw PpException(
        'No se pudo cargar el logo "${resolvedNombre ?? resolvedPath ?? 'seleccionado'}". '
        'No se generó el documento para evitar usar un logo incorrecto.',
      );
    }

    final fallback = await _cargarLogoEmpresa(empresaId);
    if (fallback.isNotEmpty) {
      return _ResolvedLogo(
        bytes: fallback,
        path: resolvedPath,
        url: resolvedUrl,
        nombre: resolvedNombre,
        sinLogo: false,
      );
    }
    if (requestedLogo) {
      throw PpException(
        'No se encontró un logo válido para "${resolvedNombre ?? empresaId}".',
      );
    }
    return _ResolvedLogo(bytes: Uint8List(0), sinLogo: true);
  }

  Future<Uint8List> _cargarLogoEmpresa(String empresaId) async {
    try {
      final doc = await _db.collection(_colConfig).doc(empresaId).get();
      if (doc.exists) {
        final data = doc.data()!;
        final activePathField = _normalizeStoragePath(data['logoActivoPath']);
        final rawLogos = data['logos'];

        String? logoPath;
        String? logoUrl;

        if (rawLogos is List && rawLogos.isNotEmpty) {
          final match = rawLogos.whereType<Map>().firstWhere(
            (m) => _normalizeStoragePath(m['path']) == activePathField,
            orElse: () => rawLogos.whereType<Map>().first,
          );
          // b64 stored by guardarLogo — use directly, no Storage round-trip.
          final b64 = match['b64'] as String?;
          if (b64 != null && b64.isNotEmpty) {
            try {
              return base64Decode(b64);
            } catch (_) {}
          }
          logoPath =
              _normalizeStoragePath(match['path']) ??
              _normalizeStoragePath(match['url']);
          logoUrl =
              _normalizeStorageUrl(match['url']) ??
              _normalizeStorageUrl(match['path']);
        } else {
          // backwards compat: old single-logo schema
          logoPath =
              activePathField ??
              _normalizeStoragePath(data['logoPath']) ??
              _normalizeStoragePath(data['logoUrl']);
          logoUrl =
              _normalizeStorageUrl(data['logoUrl']) ??
              _normalizeStorageUrl(data['logoPath']);
        }

        if ((logoPath?.isNotEmpty ?? false) || (logoUrl?.isNotEmpty ?? false)) {
          final bytes = await _loadBinary(url: logoUrl, path: logoPath);
          if (bytes != null && bytes.isNotEmpty) return bytes;
        }
      }
    } catch (_) {}
    return Uint8List(0);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CARGA MASIVA: crear lote + subir Excel + crear planillas individuales
  // ─────────────────────────────────────────────────────────────────────────

  /// Crea el lote, opcionalmente sube el Excel, y crea una PpPlanilla por PDF.
  /// Excel y PDFs son independientes: se puede subir solo uno de los dos o ambos.
  /// Retorna el loteId.
  Future<String> crearLote({
    required String empresaId,
    required String actorId,
    required String rolPlanillas,
    String? nombreActor,
    // Excel (opcional)
    Uint8List? excelBytes,
    String? excelNombre,
    // PDFs + matching (opcional si solo se sube Excel)
    List<({String nombre, Uint8List bytes})> pdfs = const [],
    List<PpMatchResult> matchResults = const [],
    String? descripcion,
  }) async {
    if (excelBytes == null && pdfs.isEmpty) {
      throw const PpException('Debes subir al menos un Excel o un PDF.');
    }
    _validarRol('confirmar_carga', rolPlanillas);
    final actorSnapshot = await _getActorSnapshot(
      actorId,
      empresaId,
      nombreActor,
    );

    final loteRef = _lotes.doc();
    final loteId = loteRef.id;

    // Subir Excel si está presente
    String? excelUrl;
    String? excelPath;
    if (excelBytes != null && excelNombre != null) {
      final (url, path) = await _subirExcel(
        empresaId: empresaId,
        loteId: loteId,
        bytes: excelBytes,
        nombre: excelNombre,
      );
      excelUrl = url;
      excelPath = path;
    }

    // Crear el lote primero (en estado procesando)
    await loteRef.set({
      'empresaId': empresaId,
      'creadoPor': actorId,
      'nombreCreadoPor': nombreActor,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'estado': PpLoteEstado.procesando.valor,
      'excelUrl': excelUrl,
      'excelPath': excelPath,
      'excelNombre': excelNombre,
      'totalPdfs': pdfs.length,
      'totalPlanillas': 0,
      'planillasFirmadas': 0,
      'planillasRechazadas': 0,
      'descripcion': descripcion,
    });

    await _registrarEventoLote(
      planillaId: loteId,
      loteId: loteId,
      empresaId: empresaId,
      accion: PpAccion.lote_creado,
      actorId: actorId,
      nombreActor: nombreActor,
      metadatos: {'excelNombre': excelNombre, 'totalPdfs': pdfs.length},
    );

    // Subir cada PDF y crear planilla
    var creadas = 0;
    for (final pdf in pdfs) {
      final match = matchResults.firstWhere(
        (m) => m.pdfNombre == pdf.nombre,
        orElse: () => PpMatchResult(
          pdfNombre: pdf.nombre,
          matchEstado: PpMatchEstado.sin_coincidencia,
        ),
      );
      final planillaRef = _planillas.doc();
      final (pdfBaseUrl, pdfBasePath) = await _subirPdfBase(
        empresaId: empresaId,
        loteId: loteId,
        planillaId: planillaRef.id,
        bytes: pdf.bytes,
        nombre: pdf.nombre,
      );
      final pdfFirmadoCarga = await _aplicarFirmaCargaInicial(
        pdfBytes: pdf.bytes,
        actorSnapshot: actorSnapshot,
      );

      final (pdfUrl, pdfPath) = await _subirPdf(
        empresaId: empresaId,
        loteId: loteId,
        bytes: pdfFirmadoCarga,
        nombre: pdf.nombre,
      );

      final datosExcel = match.filaExcel != null
          ? <String, dynamic>{
              'tipo_generacion': 'pdf_cargado',
              ...match.filaExcel!.extras,
              if (match.filaExcel!.nombrePlanilla != null)
                'nombre_planilla': match.filaExcel!.nombrePlanilla!,
              if (match.filaExcel!.fecha != null)
                'fecha': match.filaExcel!.fecha!,
              if (match.filaExcel!.valor != null)
                'valor': match.filaExcel!.valor!,
            }
          : <String, dynamic>{'tipo_generacion': 'pdf_cargado'};

      final ahora = FieldValue.serverTimestamp();
      await planillaRef.set({
        'empresaId': empresaId,
        'loteId': loteId,
        'nombreArchivoOriginal': pdf.nombre,
        'nombrePlanillaDetectado': match.filaExcel?.nombrePlanilla,
        'fechaPlanillaDetectada': match.filaExcel?.fecha,
        'valorDetectado': match.filaExcel?.valor,
        'estado': PpEstado.cargada.valor,
        'cargadoPor': actorId,
        'nombreCargado': actorSnapshot.nombre,
        'cargoCargado': actorSnapshot.cargo,
        'urlFirmaCargado': actorSnapshot.urlFirma,
        'pathFirmaCargado': actorSnapshot.pathFirma,
        'revisadoPor': null,
        'revisadoEn': null,
        'firmadoPor': null,
        'firmadoEn': null,
        'urlFirmaAuditoria': null,
        'pathFirmaAuditoria': null,
        'nombreAuditorFirmante': null,
        'cargoAuditorFirmante': null,
        'urlFirmaUsada': null,
        'pathFirmaUsada': null,
        'nombreFirmante': null,
        'cargoFirmante': null,
        'urlPdf': pdfUrl,
        'pathPdf': pdfPath,
        'urlPdfBase': pdfBaseUrl,
        'pathPdfBase': pdfBasePath,
        'datosExcel': datosExcel,
        'matchEstado': match.matchEstado.valor,
        'excelRowIndex': match.filaExcel?.rowIndex,
        'metadatosExtraccion': {
          'metodo': 'excel_matching',
          'score': match.score,
          'matchEstado': match.matchEstado.valor,
          'cargadoEn': DateTime.now().toIso8601String(),
        },
        'observaciones': [],
        'createdAt': ahora,
        'updatedAt': ahora,
      });
      await _guardarRenderPdfBase(
        planillaId: planillaRef.id,
        empresaId: empresaId,
        pdfBytes: pdf.bytes,
      );
      await _guardarPdfBaseFirestore(
        planillaId: planillaRef.id,
        empresaId: empresaId,
        pdfBytes: pdf.bytes,
      );
      await _guardarPdfBaseInlineDoc(
        planillaId: planillaRef.id,
        empresaId: empresaId,
        pdfBytes: pdf.bytes,
      );

      await _registrarEventoLote(
        planillaId: planillaRef.id,
        loteId: loteId,
        empresaId: empresaId,
        accion: PpAccion.planilla_creada,
        actorId: actorId,
        nombreActor: nombreActor,
        metadatos: {
          'nombreArchivo': pdf.nombre,
          'matchEstado': match.matchEstado.valor,
          'score': match.score,
        },
      );

      creadas++;
    }

    // Actualizar contador del lote
    await loteRef.update({
      'totalPlanillas': creadas,
      'estado': PpLoteEstado.listo.valor,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    debugPrint('[PpService] Lote creado: $loteId con $creadas planillas');
    return loteId;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SUBIR PDFs DIRECTOS: sin lote ni Excel, cada PDF → planilla con estado cargada
  // ─────────────────────────────────────────────────────────────────────────

  Future<int> subirPdfsDirectos({
    required String empresaId,
    required String actorId,
    required String rolPlanillas,
    String? nombreActor,
    required List<({String nombre, Uint8List bytes})> pdfs,
    void Function(int procesados, int total)? onProgress,
  }) async {
    if (pdfs.isEmpty) throw const PpException('Selecciona al menos un PDF.');
    _validarRol('confirmar_carga', rolPlanillas);

    final actorSnapshot = await _getActorSnapshot(
      actorId,
      empresaId,
      nombreActor,
    );
    final logoActivo = await getLogoActivoMeta(empresaId);
    final empresaNombrePlanilla = await _resolverNombreEmpresaPlanilla(
      empresaId: empresaId,
      nombreLogoPreferido: logoActivo?['nombre'],
    );
    var creadas = 0;
    onProgress?.call(0, pdfs.length);

    for (final pdf in pdfs) {
      final planillaRef = _planillas.doc();
      final planillaId = planillaRef.id;
      final ahora = FieldValue.serverTimestamp();
      final (pdfBaseUrl, pdfBasePath) = await _subirPdfBase(
        empresaId: empresaId,
        loteId: '',
        planillaId: planillaId,
        bytes: pdf.bytes,
        nombre: pdf.nombre,
      );
      final pdfFirmadoCarga = await _aplicarFirmaCargaInicial(
        pdfBytes: pdf.bytes,
        actorSnapshot: actorSnapshot,
      );

      final ts = DateTime.now().millisecondsSinceEpoch;
      final safe = pdf.nombre.replaceAll(RegExp(r'[^\w.\-]'), '_');
      final path = 'planillas_pago/$empresaId/directos/$planillaId/${ts}_$safe';
      final ref = _storage.ref(path);
      await ref.putData(
        pdfFirmadoCarga,
        _pdfMetadata(_buildPdfFileName(pdf.nombre)),
      );
      final url = await ref.getDownloadURL();

      await planillaRef.set({
        'empresaId': empresaId,
        'empresaNombre': empresaNombrePlanilla,
        'loteId': null,
        'nombreArchivoOriginal': pdf.nombre,
        'nombrePlanillaDetectado': null,
        'fechaPlanillaDetectada': null,
        'valorDetectado': null,
        'logoPath': logoActivo?['path'],
        'logoUrl': logoActivo?['url'],
        'logoNombre': logoActivo?['nombre'],
        'sinLogo': logoActivo == null,
        'estado': PpEstado.cargada.valor,
        'cargadoPor': actorId,
        'nombreCargado': actorSnapshot.nombre,
        'cargoCargado': actorSnapshot.cargo,
        'urlFirmaCargado': actorSnapshot.urlFirma,
        'pathFirmaCargado': actorSnapshot.pathFirma,
        'revisadoPor': null,
        'revisadoEn': null,
        'firmadoPor': null,
        'firmadoEn': null,
        'urlFirmaAuditoria': null,
        'pathFirmaAuditoria': null,
        'nombreAuditorFirmante': null,
        'cargoAuditorFirmante': null,
        'urlFirmaUsada': null,
        'pathFirmaUsada': null,
        'nombreFirmante': null,
        'cargoFirmante': null,
        'urlPdf': url,
        'pathPdf': path,
        'urlPdfBase': pdfBaseUrl,
        'pathPdfBase': pdfBasePath,
        'datosExcel': <String, dynamic>{
          'tipo_generacion': 'pdf_directo',
          'empresa_nombre': empresaNombrePlanilla,
          'logo_path': logoActivo?['path'],
          'logo_url': logoActivo?['url'],
          'logo_nombre': logoActivo?['nombre'],
          'sin_logo': logoActivo == null,
        },
        'matchEstado': null,
        'excelRowIndex': null,
        'metadatosExtraccion': {
          'metodo': 'pdf_directo',
          'empresaNombre': empresaNombrePlanilla,
          'cargadoEn': DateTime.now().toIso8601String(),
        },
        'observaciones': [],
        'createdAt': ahora,
        'updatedAt': ahora,
      });
      await _guardarRenderPdfBase(
        planillaId: planillaId,
        empresaId: empresaId,
        pdfBytes: pdf.bytes,
      );
      await _guardarPdfBaseFirestore(
        planillaId: planillaId,
        empresaId: empresaId,
        pdfBytes: pdf.bytes,
      );
      await _guardarPdfBaseInlineDoc(
        planillaId: planillaId,
        empresaId: empresaId,
        pdfBytes: pdf.bytes,
      );

      await _registrarEventoLote(
        planillaId: planillaId,
        loteId: planillaId,
        empresaId: empresaId,
        accion: PpAccion.planilla_creada,
        actorId: actorId,
        nombreActor: nombreActor,
        metadatos: {'nombreArchivo': pdf.nombre, 'metodo': 'pdf_directo'},
      );

      creadas++;
      onProgress?.call(creadas, pdfs.length);
    }

    debugPrint('[PpService] $creadas planillas creadas desde PDFs directos');
    return creadas;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CONFIRMAR CARGA: cargada → pendiente_validacion
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> confirmarCarga({
    required String planillaId,
    required String empresaId,
    required String loteId,
    required String actorId,
    required String rolPlanillas,
    String? nombreActor,
  }) async {
    _validarRol('confirmar_carga', rolPlanillas);
    final actorSnapshot = await _getActorSnapshot(
      actorId,
      empresaId,
      nombreActor,
    );
    String? pdfUrlActual;
    String? pdfPathActual;
    String? pdfUrlSellado;
    String? pdfPathSellado;
    String? nombrePlanillaDetectado;
    bool requiereSelloCarga = false;
    try {
      final snap = await _planillas.doc(planillaId).get();
      final data = snap.data() ?? {};
      pdfUrlActual = data['urlPdf'] as String?;
      pdfPathActual = data['pathPdf'] as String?;
      nombrePlanillaDetectado = _cleanString(data['nombrePlanillaDetectado']);
      final datosExcel = data['datosExcel'];
      final tipoGeneracion = datosExcel is Map
          ? (datosExcel['tipo_generacion'] ?? '').toString().trim()
          : '';
      requiereSelloCarga = tipoGeneracion.isEmpty;
    } catch (_) {}

    if (requiereSelloCarga) {
      final stamped = await _stampearTrazabilidadEnPdf(
        originalPdfUrl: pdfUrlActual,
        originalPdfPath: pdfPathActual,
        estado: PpEstado.pendiente_validacion,
        bloques: [
          _PdfStampBlock(
            titulo: 'CARGADO POR',
            color: PdfColors.orange700,
            firmaBytes:
                actorSnapshot.firmaBlob ??
                await _loadBinary(
                  url: actorSnapshot.urlFirma,
                  path: actorSnapshot.pathFirma,
                ),
            nombre: actorSnapshot.nombre,
            cargo: actorSnapshot.cargo,
            fecha: DateFormat('dd/MM/yyyy').format(DateTime.now()),
          ),
        ],
      );
      if (stamped != null) {
        final (url, path) = await _subirPdfFirmado(
          empresaId: empresaId,
          planillaId: planillaId,
          bytes: stamped,
          nombrePlanilla: nombrePlanillaDetectado,
        );
        pdfUrlSellado = url;
        pdfPathSellado = path;
      }
    }

    await _transicionar(
      planillaId: planillaId,
      loteId: loteId,
      empresaId: empresaId,
      desde: PpEstado.cargada,
      hacia: PpEstado.pendiente_validacion,
      accion: PpAccion.carga_confirmada,
      actorId: actorId,
      nombreActor: nombreActor,
      camposExtra: {
        'cargadoPor': actorId,
        'nombreCargado': actorSnapshot.nombre,
        'cargoCargado': actorSnapshot.cargo,
        'urlFirmaCargado': actorSnapshot.urlFirma,
        ...?pdfUrlSellado == null ? null : {'urlPdf': pdfUrlSellado},
        ...?pdfPathSellado == null ? null : {'pathPdf': pdfPathSellado},
        ...?(pdfUrlActual != null && pdfUrlSellado != null)
            ? {'urlPdfOriginal': pdfUrlActual}
            : null,
        ...?(pdfPathActual != null && pdfPathSellado != null)
            ? {'pathPdfOriginal': pdfPathActual}
            : null,
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ENVIAR A AUDITORÍA: pendiente_validacion → en_revision_auditoria
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> enviarAuditoria({
    required String planillaId,
    required String empresaId,
    required String loteId,
    required String actorId,
    required String rolPlanillas,
    String? nombreActor,
  }) async {
    _validarRol('enviar_auditoria', rolPlanillas);
    await _transicionar(
      planillaId: planillaId,
      loteId: loteId,
      empresaId: empresaId,
      desde: PpEstado.pendiente_validacion,
      hacia: PpEstado.en_revision_auditoria,
      accion: PpAccion.enviado_auditoria,
      actorId: actorId,
      nombreActor: nombreActor,
    );
    await _notificar(
      empresaId: empresaId,
      planillaId: planillaId,
      rolesDestino: [PpRoles.auditoria],
      titulo: 'Planilla pendiente de revisión',
      descripcion: 'Una planilla está lista para revisión de auditoría.',
      actorId: actorId,
      nombreActor: nombreActor,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // OBSERVAR: en_revision_auditoria → observada
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> observar({
    required String planillaId,
    required String empresaId,
    required String loteId,
    required String actorId,
    required String rolPlanillas,
    required String observacion,
    String? nombreActor,
  }) async {
    if (observacion.trim().isEmpty) {
      throw const PpException('La observación es obligatoria.');
    }
    _validarRol('observar', rolPlanillas);

    await _transicionar(
      planillaId: planillaId,
      loteId: loteId,
      empresaId: empresaId,
      desde: PpEstado.en_revision_auditoria,
      hacia: PpEstado.observada,
      accion: PpAccion.observado,
      actorId: actorId,
      nombreActor: nombreActor,
      observacion: observacion.trim(),
      camposExtra: {
        'revisadoPor': actorId,
        'revisadoEn': FieldValue.serverTimestamp(),
        'nombreAuditorFirmante': nombreActor,
      },
    );

    // Agregar la observación al array append
    await _planillas.doc(planillaId).update({
      'observaciones': FieldValue.arrayUnion([
        {
          'autor': actorId,
          'nombreAutor': nombreActor,
          'texto': observacion.trim(),
          'en': DateTime.now().toIso8601String(),
        },
      ]),
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // REENVIAR: observada → en_revision_auditoria
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> reenviar({
    required String planillaId,
    required String empresaId,
    required String loteId,
    required String actorId,
    required String rolPlanillas,
    String? nombreActor,
    String? comentario,
  }) async {
    _validarRol('reenviar', rolPlanillas);
    await _transicionar(
      planillaId: planillaId,
      loteId: loteId,
      empresaId: empresaId,
      desde: PpEstado.observada,
      hacia: PpEstado.en_revision_auditoria,
      accion: PpAccion.reenviado,
      actorId: actorId,
      nombreActor: nombreActor,
      observacion: comentario,
    );
  }

  Future<void> reemplazarPdfObservado({
    required String planillaId,
    required String empresaId,
    required String loteId,
    required String actorId,
    required String rolPlanillas,
    required Uint8List pdfBytes,
    required String nombrePdf,
    String? nombreActor,
    String? comentario,
  }) async {
    _validarRol('reenviar', rolPlanillas);
    if (pdfBytes.isEmpty) {
      throw const PpException('Debes seleccionar un PDF válido.');
    }

    final snap = await _planillas.doc(planillaId).get();
    if (!snap.exists) throw const PpException('Planilla no encontrada.');
    final data = snap.data() ?? {};
    final estadoActual = PpEstadoX.deString((data['estado'] ?? '').toString());
    if (estadoActual != PpEstado.observada) {
      throw PpException(
        'Solo puedes reemplazar el PDF cuando la planilla está en observaciones.',
      );
    }

    final actorSnapshot = await _getActorSnapshot(
      actorId,
      empresaId,
      nombreActor,
    );
    final (pdfBaseUrl, pdfBasePath) = await _subirPdfBase(
      empresaId: empresaId,
      loteId: loteId,
      planillaId: planillaId,
      bytes: pdfBytes,
      nombre: nombrePdf,
    );
    final stamped = await _stampearTrazabilidadEnPdf(
      originalPdfBytes: pdfBytes,
      estado: PpEstado.en_revision_auditoria,
      bloques: [
        _PdfStampBlock(
          titulo: 'CARGADO POR',
          color: PdfColors.orange700,
          firmaBytes:
              actorSnapshot.firmaBlob ??
              await _loadBinary(
                url: actorSnapshot.urlFirma,
                path: actorSnapshot.pathFirma,
              ),
          nombre: actorSnapshot.nombre,
          cargo: actorSnapshot.cargo,
          fecha: DateFormat('dd/MM/yyyy').format(DateTime.now()),
        ),
      ],
    );
    final bytesFinales = stamped ?? pdfBytes;
    final (pdfUrl, pdfPath) = await _subirPdf(
      empresaId: empresaId,
      loteId: loteId,
      bytes: bytesFinales,
      nombre: nombrePdf,
    );

    // Preserve existing datosExcel but force tipo_generacion = 'pdf_cargado'
    // so aprobarAuditoria treats this as a direct PDF (not an Excel-generated
    // one), preventing _regenerarPdfExcelConFirmas from overwriting it.
    final datosExcelActual = data['datosExcel'] is Map
        ? Map<String, dynamic>.from(data['datosExcel'] as Map)
        : <String, dynamic>{};
    datosExcelActual['tipo_generacion'] = 'pdf_cargado';

    await _transicionar(
      planillaId: planillaId,
      loteId: loteId,
      empresaId: empresaId,
      desde: PpEstado.observada,
      hacia: PpEstado.en_revision_auditoria,
      accion: PpAccion.reenviado,
      actorId: actorId,
      nombreActor: nombreActor,
      observacion: comentario ?? 'Se cargó un nuevo PDF: $nombrePdf',
      camposExtra: {
        'nombreArchivoOriginal': nombrePdf,
        'urlPdf': pdfUrl,
        'pathPdf': pdfPath,
        'urlPdfBase': pdfBaseUrl,
        'pathPdfBase': pdfBasePath,
        'datosExcel': datosExcelActual,
        'cargadoPor': actorId,
        'nombreCargado': actorSnapshot.nombre,
        'cargoCargado': actorSnapshot.cargo,
        'urlFirmaCargado': actorSnapshot.urlFirma,
        'pathFirmaCargado': actorSnapshot.pathFirma,
        'revisadoPor': null,
        'revisadoEn': null,
        'urlFirmaAuditoria': null,
        'pathFirmaAuditoria': null,
        'nombreAuditorFirmante': null,
        'cargoAuditorFirmante': null,
      },
    );
    await _guardarRenderPdfBase(
      planillaId: planillaId,
      empresaId: empresaId,
      pdfBytes: pdfBytes,
    );
    await _guardarPdfBaseFirestore(
      planillaId: planillaId,
      empresaId: empresaId,
      pdfBytes: pdfBytes,
    );
    await _guardarPdfBaseInlineDoc(
      planillaId: planillaId,
      empresaId: empresaId,
      pdfBytes: pdfBytes,
    );
  }

  Future<void> reemplazarPlanillaObservadaDesdeExcel({
    required String planillaId,
    required String empresaId,
    required String loteId,
    required String actorId,
    required String rolPlanillas,
    required Uint8List excelBytes,
    required String nombreExcel,
    String? nombreActor,
    String? comentario,
    String? consolidadoSeleccionado,
  }) async {
    _validarRol('reenviar', rolPlanillas);
    if (excelBytes.isEmpty) {
      throw const PpException('Debes seleccionar un Excel válido.');
    }

    final snap = await _planillas.doc(planillaId).get();
    if (!snap.exists) throw const PpException('Planilla no encontrada.');
    final data = snap.data() ?? {};
    final estadoActual = PpEstadoX.deString((data['estado'] ?? '').toString());
    if (estadoActual != PpEstado.observada) {
      throw const PpException(
        'Solo puedes corregir desde Excel cuando la planilla está observada.',
      );
    }

    final parse = _excelParser.parse(excelBytes);
    if (!parse.exitoso) {
      throw PpException(
        parse.error ?? 'No se pudo leer el Excel seleccionado.',
      );
    }
    if (parse.filas.isEmpty) {
      throw const PpException(
        'El Excel no tiene filas válidas para generar la planilla.',
      );
    }

    final actorSnapshot = await _getActorSnapshot(
      actorId,
      empresaId,
      nombreActor,
    );

    final resolvedLogo = await _resolverLogoGeneracion(
      empresaId: empresaId,
      planillaData: data,
    );
    final logoBytes = resolvedLogo.bytes;

    final storageScopeId = loteId.trim().isNotEmpty ? loteId : planillaId;
    final excelUpload = await _subirExcel(
      empresaId: empresaId,
      loteId: storageScopeId,
      bytes: excelBytes,
      nombre: nombreExcel,
    );

    final ({bool esConsolidado, List<PpExcelFila> filas}) resolved;
    if (consolidadoSeleccionado != null &&
        consolidadoSeleccionado.trim().isNotEmpty) {
      final nombreNorm = _normalizeLookup(consolidadoSeleccionado.trim());
      final filasSeleccionadas = parse.filas
          .where(
            (f) =>
                _normalizeLookup((f.nombrePlanilla ?? '').trim()) == nombreNorm,
          )
          .toList();
      resolved = (
        esConsolidado: true,
        filas: filasSeleccionadas.isNotEmpty ? filasSeleccionadas : parse.filas,
      );
    } else {
      resolved = _resolverReemplazoObservadoDesdeExcel(
        planillaData: data,
        filasExcel: parse.filas,
      );
    }

    late final Uint8List pdfBytes;
    late final String nombreArchivo;
    late final String? nombrePlanilla;
    late final String? fechaPlanilla;
    late final double? valorPlanilla;
    late final Map<String, dynamic> datosExcelActualizados;
    late final int? excelRowIndex;

    final empresaNombrePlanilla = await _resolverNombreEmpresaPlanilla(
      empresaId: empresaId,
      nombreLogoPreferido: resolvedLogo.nombre,
      planillaData: data,
    );

    if (resolved.esConsolidado) {
      final filas = resolved.filas;
      final consolidado =
          (data['nombrePlanillaDetectado'] ??
                  (data['datosExcel'] is Map
                      ? (data['datosExcel']['consolidado'] ??
                            data['datosExcel']['nombre_planilla'])
                      : null) ??
                  filas.first.nombrePlanilla ??
                  'Consolidado')
              .toString()
              .trim();
      pdfBytes = await _generarPdfConsolidadoDesdeFilas(
        consolidado: consolidado,
        filas: filas,
        logoBytes: logoBytes,
        empresaNombre: empresaNombrePlanilla,
        nombreElaborado: actorSnapshot.nombre,
        cargoElaborado: actorSnapshot.cargo,
        firmaElaboradoUrl: actorSnapshot.urlFirma,
        firmaElaboradoPath: actorSnapshot.pathFirma,
        firmaElaboradoBlob: actorSnapshot.firmaBlob,
      );
      nombreArchivo = _nombreArchivoConsolidado(
        consolidado,
        filas,
        empresaNombre: empresaNombrePlanilla,
      );
      nombrePlanilla = consolidado;
      fechaPlanilla = _firstNonEmptyDate(filas);
      valorPlanilla = _sumarValores(filas);
      final pagador = _firstNonEmptyExtra(filas, const ['pagador', 'banco']);
      final banco = _firstNonEmptyExtra(filas, const ['banco']);
      datosExcelActualizados = {
        'tipo_generacion': 'excel_consolidado',
        'consolidado': consolidado,
        'pagador': pagador,
        ...?banco == null ? null : {'banco': banco},
        'logo_path': resolvedLogo.path,
        'logo_url': resolvedLogo.url,
        'logo_nombre': resolvedLogo.nombre,
        'sin_logo': resolvedLogo.sinLogo,
        'filas_consolidadas': filas.length,
        'rango_filas_excel': _rangoFilasExcel(filas),
        'filas_rows': filas.map((f) => f.toMap()).toList(),
      };
      excelRowIndex = filas.first.rowIndex;
    } else {
      final fila = resolved.filas.first;
      pdfBytes = await _generarPdfDesdeFila(
        fila: fila,
        logoBytes: logoBytes,
        empresaNombre: empresaNombrePlanilla,
        nombreElaborado: actorSnapshot.nombre,
        cargoElaborado: actorSnapshot.cargo,
        firmaElaboradoUrl: actorSnapshot.urlFirma,
        firmaElaboradoPath: actorSnapshot.pathFirma,
        firmaElaboradoBlob: actorSnapshot.firmaBlob,
      );
      nombreArchivo = _nombreArchivoFila(
        fila,
        empresaNombre: empresaNombrePlanilla,
      );
      nombrePlanilla = fila.nombrePlanilla;
      fechaPlanilla = fila.fecha;
      valorPlanilla = fila.valor;
      datosExcelActualizados = {
        ...fila.extras,
        if (fila.nombrePlanilla != null)
          'nombre_planilla': fila.nombrePlanilla!,
        if (fila.fecha != null) 'fecha': fila.fecha!,
        if (fila.valor != null) 'valor': fila.valor!,
        'tipo_generacion': 'excel_generado',
        'logo_path': resolvedLogo.path,
        'logo_url': resolvedLogo.url,
        'logo_nombre': resolvedLogo.nombre,
        'sin_logo': resolvedLogo.sinLogo,
        'fila_row': fila.toMap(),
      };
      excelRowIndex = fila.rowIndex;
    }

    final (pdfUrl, pdfPath) = await _subirPdf(
      empresaId: empresaId,
      loteId: storageScopeId,
      bytes: pdfBytes,
      nombre: nombreArchivo,
    );

    if (loteId.trim().isNotEmpty) {
      await _lotes.doc(loteId).set({
        'excelUrl': excelUpload.$1,
        'excelPath': excelUpload.$2,
        'excelNombre': nombreExcel,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    await _transicionar(
      planillaId: planillaId,
      loteId: loteId,
      empresaId: empresaId,
      desde: PpEstado.observada,
      hacia: PpEstado.en_revision_auditoria,
      accion: PpAccion.reenviado,
      actorId: actorId,
      nombreActor: nombreActor,
      observacion:
          comentario ?? 'Se regeneró la planilla desde Excel: $nombreExcel',
      camposExtra: {
        'nombreArchivoOriginal': nombreArchivo,
        'nombrePlanillaDetectado': nombrePlanilla,
        'fechaPlanillaDetectada': fechaPlanilla,
        'valorDetectado': valorPlanilla,
        'urlPdf': pdfUrl,
        'pathPdf': pdfPath,
        'urlPdfBase': null,
        'pathPdfBase': null,
        'logoPath': resolvedLogo.path,
        'logoUrl': resolvedLogo.url,
        'logoNombre': resolvedLogo.nombre,
        'sinLogo': resolvedLogo.sinLogo,
        'datosExcel': datosExcelActualizados,
        'matchEstado': PpMatchEstado.coincidencia_exacta.valor,
        'excelRowIndex': excelRowIndex,
        'metadatosExtraccion': {
          'metodo': 'corregido_desde_excel',
          'excelNombre': nombreExcel,
          'cargadoEn': DateTime.now().toIso8601String(),
        },
        'cargadoPor': actorId,
        'nombreCargado': actorSnapshot.nombre,
        'cargoCargado': actorSnapshot.cargo,
        'urlFirmaCargado': actorSnapshot.urlFirma,
        'pathFirmaCargado': actorSnapshot.pathFirma,
        'revisadoPor': null,
        'revisadoEn': null,
        'urlFirmaAuditoria': null,
        'pathFirmaAuditoria': null,
        'nombreAuditorFirmante': null,
        'cargoAuditorFirmante': null,
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // APROBAR AUDITORÍA: en_revision_auditoria → aprobada_auditoria
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> aprobarAuditoria({
    required String planillaId,
    required String empresaId,
    required String loteId,
    required String actorId,
    required String rolPlanillas,
    String? nombreActor,
    String? comentario,
    Uint8List? currentPdfBytes,
  }) async {
    _validarRol('aprobar_auditoria', rolPlanillas);
    final actorSnapshot = await _getActorSnapshot(
      actorId,
      empresaId,
      nombreActor,
    );
    Map<String, dynamic> planillaData = const {};
    String? pdfUrlActual;
    String? pdfPathActual;
    String? pdfUrlSellado;
    String? pdfPathSellado;
    String? pdfBaseUrl;
    String? pdfBasePath;
    final firmaAuditoriaBytes =
        actorSnapshot.firmaBlob ??
        await _loadBinary(
          url: actorSnapshot.urlFirma,
          path: actorSnapshot.pathFirma,
        );
    try {
      final snap = await _planillas.doc(planillaId).get();
      planillaData = snap.data() ?? {};
      pdfUrlActual = planillaData['urlPdf'] as String?;
      pdfPathActual = planillaData['pathPdf'] as String?;
      pdfBaseUrl = planillaData['urlPdfBase'] as String?;
      pdfBasePath = planillaData['pathPdfBase'] as String?;
    } catch (_) {}
    final datosExcel = planillaData['datosExcel'];
    final tipoGeneracion = datosExcel is Map
        ? (datosExcel['tipo_generacion'] ?? '').toString().trim()
        : '';
    final esPdfDirecto = _esPdfDirectoTipo(tipoGeneracion);
    final sourcePdfUrl = esPdfDirecto
        ? (pdfBaseUrl ?? pdfUrlActual)
        : pdfUrlActual;
    final sourcePdfPath = esPdfDirecto
        ? (pdfBasePath ?? pdfPathActual)
        : pdfPathActual;
    final pdfBaseBytes = esPdfDirecto
        ? await _cargarPdfBaseInlineDoc(planillaId) ??
              await _cargarPdfBaseFirestore(planillaId)
        : null;
    final renderedPages = esPdfDirecto
        ? await _cargarRenderPdfBase(planillaId)
        : const <_RenderedPdfPage>[];
    final blocks = _buildBlocksForStampedPdf(
      planillaData: {
        ...planillaData,
        'firmaCargadoBlob':
            planillaData['firmaCargadoBlob'] ??
            await _loadBinary(
              url: planillaData['urlFirmaCargado'] as String?,
              path: planillaData['pathFirmaCargado'] as String?,
            ),
      },
      auditorSnapshot: (
        nombre: actorSnapshot.nombre,
        cargo: actorSnapshot.cargo,
        urlFirma: actorSnapshot.urlFirma,
        pathFirma: actorSnapshot.pathFirma,
        firmaBlob: firmaAuditoriaBytes,
      ),
    );

    if (esPdfDirecto) {
      final backendStamped = await _sellarPdfDirectoEnBackend(
        planillaId: planillaId,
        empresaId: empresaId,
        estado: PpEstado.aprobada_auditoria,
        sourcePdfUrl: sourcePdfUrl,
        sourcePdfPath: sourcePdfPath,
        bloques: _buildDirectPdfBlocksPayload(
          blocks,
          planillaData: planillaData,
          auditorSnapshot: (
            nombre: actorSnapshot.nombre,
            cargo: actorSnapshot.cargo,
            urlFirma: actorSnapshot.urlFirma,
            pathFirma: actorSnapshot.pathFirma,
            firmaBlob: firmaAuditoriaBytes,
          ),
        ),
      );
      if (backendStamped != null) {
        pdfUrlSellado = backendStamped.$1;
        pdfPathSellado = backendStamped.$2;
      }
    }

    final stamped = pdfPathSellado != null
        ? null
        : await _regenerarPdfExcelConFirmas(
                planillaId: planillaId,
                empresaId: empresaId,
                loteId: loteId,
                planillaData: planillaData,
                auditorSnapshot: actorSnapshot,
              ) ??
              await _stampearTrazabilidadEnPdf(
                originalPdfBytes: esPdfDirecto
                    ? (pdfBaseBytes ??
                          (renderedPages.isNotEmpty ? null : currentPdfBytes))
                    : currentPdfBytes,
                originalPdfUrl: sourcePdfUrl,
                originalPdfPath: sourcePdfPath,
                renderedPages: renderedPages,
                estado: PpEstado.aprobada_auditoria,
                bloques: blocks,
              );
    if (esPdfDirecto &&
        (pdfPathSellado ?? '').trim().isEmpty &&
        (stamped == null || stamped.isEmpty)) {
      throw const PpException(
        'No se pudo regenerar el PDF con la firma de auditoria.',
      );
    }
    if ((pdfPathSellado ?? '').trim().isEmpty && stamped != null) {
      final (url, path) = await _subirPdfFirmado(
        empresaId: empresaId,
        planillaId: planillaId,
        bytes: stamped,
        nombrePlanilla: _cleanString(planillaData['nombrePlanillaDetectado']),
      );
      pdfUrlSellado = url;
      pdfPathSellado = path;
    }

    final camposExtra = <String, dynamic>{
      'revisadoPor': actorId,
      'revisadoEn': FieldValue.serverTimestamp(),
      'urlFirmaAuditoria': actorSnapshot.urlFirma,
      'pathFirmaAuditoria': actorSnapshot.pathFirma,
      'nombreAuditorFirmante': actorSnapshot.nombre,
      'cargoAuditorFirmante': actorSnapshot.cargo,
    };
    if (pdfUrlSellado != null && pdfUrlSellado.trim().isNotEmpty) {
      camposExtra['urlPdf'] = pdfUrlSellado;
      if (pdfUrlActual != null && pdfUrlActual.trim().isNotEmpty) {
        camposExtra['urlPdfOriginal'] = pdfUrlActual;
      }
    }
    if (pdfPathSellado != null && pdfPathSellado.trim().isNotEmpty) {
      camposExtra['pathPdf'] = pdfPathSellado;
      if (pdfPathActual != null && pdfPathActual.trim().isNotEmpty) {
        camposExtra['pathPdfOriginal'] = pdfPathActual;
      }
    }

    await _transicionar(
      planillaId: planillaId,
      loteId: loteId,
      empresaId: empresaId,
      desde: PpEstado.en_revision_auditoria,
      hacia: PpEstado.aprobada_auditoria,
      accion: PpAccion.aprobado_auditoria,
      actorId: actorId,
      nombreActor: nombreActor,
      observacion: comentario,
      camposExtra: camposExtra,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ENVIAR A GERENCIA: aprobada_auditoria → pendiente_firma_gerencia
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> enviarGerencia({
    required String planillaId,
    required String empresaId,
    required String loteId,
    required String actorId,
    required String rolPlanillas,
    String? nombreActor,
  }) async {
    _validarRol('enviar_gerencia', rolPlanillas);
    await _transicionar(
      planillaId: planillaId,
      loteId: loteId,
      empresaId: empresaId,
      desde: PpEstado.aprobada_auditoria,
      hacia: PpEstado.pendiente_firma_gerencia,
      accion: PpAccion.enviado_gerencia,
      actorId: actorId,
      nombreActor: nombreActor,
    );
    await _notificar(
      empresaId: empresaId,
      planillaId: planillaId,
      rolesDestino: [PpRoles.gerencia],
      titulo: 'Planilla pendiente de firma',
      descripcion:
          'Una planilla aprobada por auditoría está lista para su firma.',
      actorId: actorId,
      nombreActor: nombreActor,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FIRMAR: pendiente_firma_gerencia → firmada
  // Captura snapshot de firma del actor.
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> firmar({
    required String planillaId,
    required String empresaId,
    required String loteId,
    required String actorId,
    required String rolPlanillas,
    String? nombreActor,
    String? comentario,
    Uint8List? currentPdfBytes,
  }) async {
    _validarRol('firmar', rolPlanillas);
    final actorSnapshot = await _getActorSnapshot(
      actorId,
      empresaId,
      nombreActor,
    );

    // Leer planilla: URL del PDF original + datos del auditor
    Map<String, dynamic> planillaData = const {};
    String? urlPdfOriginal;
    String? pathPdfOriginal;
    String? urlPdfBase;
    String? pathPdfBase;
    ({
      String? nombre,
      String? cargo,
      String? urlFirma,
      String? pathFirma,
      Uint8List? firmaBlob,
    })?
    auditorSnapshot;
    try {
      final snap = await _planillas.doc(planillaId).get();
      planillaData = snap.data() ?? {};
      urlPdfOriginal = planillaData['urlPdf'] as String?;
      pathPdfOriginal = planillaData['pathPdf'] as String?;
      urlPdfBase = planillaData['urlPdfBase'] as String?;
      pathPdfBase = planillaData['pathPdfBase'] as String?;
      final revisadoPor = (planillaData['revisadoPor'] ?? '').toString().trim();
      if (revisadoPor.isNotEmpty) {
        final auditorActor = await _getActorSnapshot(
          revisadoPor,
          empresaId,
          planillaData['nombreAuditorFirmante'] as String?,
        );
        auditorSnapshot = (
          nombre: auditorActor.nombre,
          cargo: auditorActor.cargo,
          urlFirma: auditorActor.urlFirma,
          pathFirma: auditorActor.pathFirma,
          firmaBlob:
              auditorActor.firmaBlob ??
              await _loadBinary(
                url: auditorActor.urlFirma,
                path: auditorActor.pathFirma,
              ),
        );
      }
    } catch (_) {}

    // Estampar la firma final de gerencia sobre el PDF vigente.
    String? urlPdfFirmado;
    String? pathPdfFirmado;
    final datosExcel = planillaData['datosExcel'];
    final tipoGeneracion = datosExcel is Map
        ? (datosExcel['tipo_generacion'] ?? '').toString().trim()
        : '';
    final esPdfDirecto = _esPdfDirectoTipo(tipoGeneracion);
    final sourcePdfUrl = esPdfDirecto
        ? (urlPdfBase ?? urlPdfOriginal)
        : urlPdfOriginal;
    final sourcePdfPath = esPdfDirecto
        ? (pathPdfBase ?? pathPdfOriginal)
        : pathPdfOriginal;
    final pdfBaseBytes = esPdfDirecto
        ? await _cargarPdfBaseInlineDoc(planillaId) ??
              await _cargarPdfBaseFirestore(planillaId)
        : null;
    final renderedPages = esPdfDirecto
        ? await _cargarRenderPdfBase(planillaId)
        : const <_RenderedPdfPage>[];
    final firmaGerenciaBytes =
        actorSnapshot.firmaBlob ??
        await _loadBinary(
          url: actorSnapshot.urlFirma,
          path: actorSnapshot.pathFirma,
        );
    final blocks = _buildBlocksForStampedPdf(
      planillaData: {
        ...planillaData,
        'firmaCargadoBlob':
            planillaData['firmaCargadoBlob'] ??
            await _loadBinary(
              url: planillaData['urlFirmaCargado'] as String?,
              path: planillaData['pathFirmaCargado'] as String?,
            ),
      },
      auditorSnapshot: auditorSnapshot,
      gerenciaSnapshot: (
        nombre: actorSnapshot.nombre,
        cargo: actorSnapshot.cargo,
        urlFirma: actorSnapshot.urlFirma,
        pathFirma: actorSnapshot.pathFirma,
        firmaBlob: firmaGerenciaBytes,
      ),
    );
    if (esPdfDirecto) {
      final backendStamped = await _sellarPdfDirectoEnBackend(
        planillaId: planillaId,
        empresaId: empresaId,
        estado: PpEstado.firmada,
        sourcePdfUrl: sourcePdfUrl,
        sourcePdfPath: sourcePdfPath,
        bloques: _buildDirectPdfBlocksPayload(
          blocks,
          planillaData: planillaData,
          auditorSnapshot: auditorSnapshot,
          gerenciaSnapshot: (
            nombre: actorSnapshot.nombre,
            cargo: actorSnapshot.cargo,
            urlFirma: actorSnapshot.urlFirma,
            pathFirma: actorSnapshot.pathFirma,
            firmaBlob: firmaGerenciaBytes,
          ),
        ),
      );
      if (backendStamped != null) {
        urlPdfFirmado = backendStamped.$1;
        pathPdfFirmado = backendStamped.$2;
      }
    }
    if (sourcePdfUrl != null || sourcePdfPath != null) {
      try {
        final stamped = pathPdfFirmado != null
            ? null
            : await _regenerarPdfExcelConFirmas(
                    planillaId: planillaId,
                    empresaId: empresaId,
                    loteId: loteId,
                    planillaData: planillaData,
                    auditorSnapshot: auditorSnapshot,
                    gerenciaSnapshot: actorSnapshot,
                  ) ??
                  await _stampearTrazabilidadEnPdf(
                    originalPdfBytes: esPdfDirecto
                        ? (pdfBaseBytes ??
                              (renderedPages.isNotEmpty
                                  ? null
                                  : currentPdfBytes))
                        : currentPdfBytes,
                    originalPdfUrl: sourcePdfUrl,
                    originalPdfPath: sourcePdfPath,
                    renderedPages: renderedPages,
                    estado: PpEstado.firmada,
                    bloques: blocks,
                  );
        if (esPdfDirecto &&
            (pathPdfFirmado ?? '').trim().isEmpty &&
            (stamped == null || stamped.isEmpty)) {
          throw const PpException(
            'No se pudo regenerar el PDF con la firma final.',
          );
        }
        if ((pathPdfFirmado ?? '').trim().isEmpty && stamped != null) {
          final (url, path) = await _subirPdfFirmado(
            empresaId: empresaId,
            planillaId: planillaId,
            bytes: stamped,
            nombrePlanilla: _cleanString(
              planillaData['nombrePlanillaDetectado'],
            ),
          );
          urlPdfFirmado = url;
          pathPdfFirmado = path;
        }
      } catch (e) {
        debugPrint('[PpService] No se pudo estampar firma: $e');
        if (esPdfDirecto) rethrow;
      }
    }
    if (esPdfDirecto &&
        ((urlPdfFirmado ?? '').trim().isEmpty ||
            (pathPdfFirmado ?? '').trim().isEmpty)) {
      throw const PpException(
        'No se pudo guardar el PDF final firmado en este flujo.',
      );
    }

    final ahora = FieldValue.serverTimestamp();
    final camposExtra = <String, dynamic>{
      'firmadoPor': actorId,
      'firmadoEn': ahora,
      'urlFirmaUsada': actorSnapshot.urlFirma,
      'pathFirmaUsada': actorSnapshot.pathFirma,
      'nombreFirmante': actorSnapshot.nombre,
      'cargoFirmante': actorSnapshot.cargo,
    };
    if (urlPdfFirmado != null && urlPdfFirmado.trim().isNotEmpty) {
      camposExtra['urlPdf'] = urlPdfFirmado;
      if (urlPdfOriginal != null && urlPdfOriginal.trim().isNotEmpty) {
        camposExtra['urlPdfOriginal'] = urlPdfOriginal;
      }
    }
    if (pathPdfFirmado != null && pathPdfFirmado.trim().isNotEmpty) {
      camposExtra['pathPdf'] = pathPdfFirmado;
      if (pathPdfOriginal != null && pathPdfOriginal.trim().isNotEmpty) {
        camposExtra['pathPdfOriginal'] = pathPdfOriginal;
      }
    }

    await _transicionar(
      planillaId: planillaId,
      loteId: loteId,
      empresaId: empresaId,
      desde: PpEstado.pendiente_firma_gerencia,
      hacia: PpEstado.firmada,
      accion: PpAccion.firmado,
      actorId: actorId,
      nombreActor: nombreActor,
      observacion: comentario,
      camposExtra: camposExtra,
    );

    if (loteId.trim().isNotEmpty) {
      await _actualizarContadorLote(loteId, empresaId);
    }
    debugPrint('[PpService] Planilla firmada: $planillaId');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // RECHAZAR (auditoría o gerencia)
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> rechazar({
    required String planillaId,
    required String empresaId,
    required String loteId,
    required String actorId,
    required String rolPlanillas,
    required String motivo,
    String? nombreActor,
  }) async {
    if (motivo.trim().isEmpty) {
      throw const PpException('El motivo de rechazo es obligatorio.');
    }

    final snap = await _planillas.doc(planillaId).get();
    if (!snap.exists) throw const PpException('Planilla no encontrada.');
    final estado = PpEstadoX.deString(
      (snap.data()?['estado'] ?? '').toString(),
    );

    if (estado == PpEstado.en_revision_auditoria) {
      _validarRol('rechazar_auditoria', rolPlanillas);
      await _transicionar(
        planillaId: planillaId,
        loteId: loteId,
        empresaId: empresaId,
        desde: PpEstado.en_revision_auditoria,
        hacia: PpEstado.rechazada,
        accion: PpAccion.rechazado_auditoria,
        actorId: actorId,
        nombreActor: nombreActor,
        observacion: motivo.trim(),
      );
    } else if (estado == PpEstado.pendiente_firma_gerencia) {
      _validarRol('rechazar_gerencia', rolPlanillas);
      await _transicionar(
        planillaId: planillaId,
        loteId: loteId,
        empresaId: empresaId,
        desde: PpEstado.pendiente_firma_gerencia,
        hacia: PpEstado.rechazada,
        accion: PpAccion.rechazado_gerencia,
        actorId: actorId,
        nombreActor: nombreActor,
        observacion: motivo.trim(),
      );
    } else {
      throw PpException(
        'No se puede rechazar desde el estado actual: ${estado.etiqueta}',
      );
    }

    if (loteId.trim().isNotEmpty) {
      await _actualizarContadorLote(loteId, empresaId);
    }
  }

  Future<void> eliminarPlanilla({
    required String planillaId,
    required String empresaId,
    required String actorId,
    required String rolPlanillas,
  }) async {
    _validarRol('eliminar_planilla', rolPlanillas);

    final snap = await _planillas.doc(planillaId).get();
    if (!snap.exists) {
      throw const PpException('Planilla no encontrada.');
    }

    final data = snap.data() ?? const <String, dynamic>{};
    final empresaPlanilla = (data['empresaId'] ?? '').toString().trim();
    if (empresaPlanilla != empresaId.trim()) {
      throw const PpException('La planilla no pertenece a la empresa activa.');
    }

    final loteId = (data['loteId'] ?? '').toString().trim();
    final storagePaths = <String>{
      (data['pathPdf'] ?? '').toString().trim(),
      (data['pathPdfBase'] ?? '').toString().trim(),
      (data['pathPdfOriginal'] ?? '').toString().trim(),
    }..removeWhere((path) => path.isEmpty);

    await _eliminarSubcoleccionPlanilla(planillaId, '_render_pages');
    await _eliminarSubcoleccionPlanilla(planillaId, '_pdf_base_chunks');
    await _eliminarSubcoleccionPlanilla(planillaId, '_pdf_base_inline');

    for (final path in storagePaths) {
      await _storage.ref(path).delete().catchError((_) {});
    }

    await _planillas.doc(planillaId).delete();

    if (loteId.isNotEmpty) {
      await _reconciliarLoteTrasEliminarPlanilla(
        loteId: loteId,
        empresaId: empresaId,
      );
    }

    debugPrint('[PpService] Planilla eliminada por $actorId: $planillaId');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CONCILIACIÓN MANUAL: actualiza el matching Excel↔PDF de una planilla
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> conciliarManual({
    required String planillaId,
    required String empresaId,
    required String loteId,
    required String actorId,
    required String rolPlanillas,
    required Map<String, dynamic> datosExcel,
    required String? nombrePlanilla,
    required String? fecha,
    required double? valor,
    String? nombreActor,
    String? nota,
  }) async {
    _validarRol('confirmar_carga', rolPlanillas);

    await _planillas.doc(planillaId).update({
      'datosExcel': datosExcel,
      'nombrePlanillaDetectado': nombrePlanilla,
      'fechaPlanillaDetectada': fecha,
      'valorDetectado': valor,
      'matchEstado': PpMatchEstado.conciliado_manual.valor,
      'updatedAt': FieldValue.serverTimestamp(),
      'metadatosExtraccion.conciliadoPor': actorId,
      'metadatosExtraccion.conciliadoEn': DateTime.now().toIso8601String(),
    });

    await _registrarEventoLote(
      planillaId: planillaId,
      loteId: loteId,
      empresaId: empresaId,
      accion: PpAccion.conciliacion_manual,
      actorId: actorId,
      nombreActor: nombreActor,
      observacion: nota,
      metadatos: {'datosExcel': datosExcel},
    );
  }

  Future<void> actualizarNombrePlanilla({
    required String planillaId,
    required String empresaId,
    required String actorId,
    required String rolPlanillas,
    required String nombrePlanilla,
    String? nombreActor,
  }) async {
    _validarRol('editar_nombre_planilla', rolPlanillas);
    final safeNombre = _cleanString(nombrePlanilla);
    if (safeNombre == null) {
      throw const PpException('Escribe un nombre valido para la planilla.');
    }

    final snap = await _planillas.doc(planillaId).get();
    if (!snap.exists) {
      throw const PpException('Planilla no encontrada.');
    }

    final data = snap.data() ?? const <String, dynamic>{};
    final empresaPlanilla = _cleanString(data['empresaId']) ?? '';
    if (empresaPlanilla != empresaId.trim()) {
      throw const PpException('La planilla no pertenece a la empresa activa.');
    }

    final estadoActual = PpEstadoX.deString((data['estado'] ?? '').toString());
    if (estadoActual != PpEstado.cargada) {
      throw const PpException(
        'Solo puedes editar el nombre mientras la planilla este en estado Cargada.',
      );
    }

    final nombreAnterior = _cleanString(data['nombrePlanillaDetectado']);
    if (nombreAnterior == safeNombre) return;

    final datosExcel = data['datosExcel'] is Map
        ? Map<String, dynamic>.from(data['datosExcel'] as Map)
        : <String, dynamic>{};
    final tipoGeneracion = (datosExcel['tipo_generacion'] ?? '')
        .toString()
        .trim();
    datosExcel['nombre_planilla'] = safeNombre;
    if (tipoGeneracion == 'excel_consolidado' ||
        datosExcel.containsKey('consolidado')) {
      datosExcel['consolidado'] = safeNombre;
    }

    await _planillas.doc(planillaId).update({
      'nombrePlanillaDetectado': safeNombre,
      'datosExcel': datosExcel,
      'updatedAt': FieldValue.serverTimestamp(),
      'metadatosExtraccion.nombreEditadoPor': actorId,
      'metadatosExtraccion.nombreEditadoEn': DateTime.now().toIso8601String(),
    });
    await sincronizarMetadataPdfDescarga(
      empresaId: empresaId,
      planillaId: planillaId,
    );

    final loteId = _cleanString(data['loteId']) ?? planillaId;
    await _registrarEventoLote(
      planillaId: planillaId,
      loteId: loteId,
      empresaId: empresaId,
      accion: PpAccion.metadatos_actualizados,
      actorId: actorId,
      nombreActor: nombreActor,
      metadatos: {
        'campo': 'nombrePlanillaDetectado',
        'valorAnterior': nombreAnterior,
        'valorNuevo': safeNombre,
      },
    );

    if (loteId.isNotEmpty && loteId != planillaId) {
      await _lotes.doc(loteId).set({
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  Future<void> limpiarCamposFirmaBinaria({
    required String empresaId,
    String? planillaId,
  }) async {
    try {
      final docs = <DocumentSnapshot<Map<String, dynamic>>>[];
      if (planillaId != null && planillaId.trim().isNotEmpty) {
        final snap = await _planillas.doc(planillaId.trim()).get();
        if (snap.exists) docs.add(snap);
      } else {
        final snap = await _planillas
            .where('empresaId', isEqualTo: empresaId)
            .get();
        docs.addAll(snap.docs);
      }

      WriteBatch batch = _db.batch();
      var ops = 0;

      Future<void> commitBatch() async {
        if (ops == 0) return;
        await batch.commit();
        batch = _db.batch();
        ops = 0;
      }

      for (final doc in docs) {
        final data = doc.data() ?? const <String, dynamic>{};
        final hasLegacyBlobFields =
            data.containsKey('firmaCargadoBlob') ||
            data.containsKey('firmaAuditoriaBlob') ||
            data.containsKey('firmaGerenciaBlob');
        if (!hasLegacyBlobFields) continue;

        batch.update(doc.reference, {
          'firmaCargadoBlob': FieldValue.delete(),
          'firmaAuditoriaBlob': FieldValue.delete(),
          'firmaGerenciaBlob': FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        ops++;
        if (ops >= 400) {
          await commitBatch();
        }
      }

      await commitBatch();
    } catch (e) {
      debugPrint(
        '[PpService] No se pudieron limpiar campos binarios de firma: $e',
      );
    }
  }

  Future<void> repararPdfFirmadoSiHaceFalta({
    required String planillaId,
    required String empresaId,
  }) async {
    try {
      final snap = await _planillas.doc(planillaId).get();
      if (!snap.exists) return;
      final data = snap.data() ?? const <String, dynamic>{};
      final estado = PpEstadoX.deString((data['estado'] ?? '').toString());
      if (estado != PpEstado.aprobada_auditoria &&
          estado != PpEstado.pendiente_firma_gerencia &&
          estado != PpEstado.firmada) {
        return;
      }

      final datosExcel = data['datosExcel'];
      final tipoGeneracion = datosExcel is Map
          ? (datosExcel['tipo_generacion'] ?? '').toString().trim()
          : '';
      if (tipoGeneracion != 'pdf_directo' && tipoGeneracion != 'pdf_cargado') {
        return;
      }

      final currentUrl = (data['urlPdf'] ?? '').toString().trim();
      final currentPath = (data['pathPdf'] ?? '').toString().trim();
      final baseUrl = ((data['urlPdfBase'] ?? data['urlPdfOriginal']) ?? '')
          .toString()
          .trim();
      final basePath = ((data['pathPdfBase'] ?? data['pathPdfOriginal']) ?? '')
          .toString()
          .trim();
      final yaFirmado =
          currentPath.contains('/firmados/') ||
          currentPath.contains('\\firmados\\') ||
          currentUrl.contains('/firmados/');
      if (yaFirmado) return;

      final firmaCargado = await _loadBinary(
        url: data['urlFirmaCargado'] as String?,
        path: data['pathFirmaCargado'] as String?,
      );
      final firmaAuditoria =
          ((data['revisadoPor'] ?? '').toString().trim().isNotEmpty ||
              (data['nombreAuditorFirmante'] ?? '')
                  .toString()
                  .trim()
                  .isNotEmpty)
          ? await _loadBinary(
              url: data['urlFirmaAuditoria'] as String?,
              path: data['pathFirmaAuditoria'] as String?,
            )
          : null;
      final firmaGerencia =
          ((data['firmadoPor'] ?? '').toString().trim().isNotEmpty ||
              (data['nombreFirmante'] ?? '').toString().trim().isNotEmpty)
          ? await _loadBinary(
              url: data['urlFirmaUsada'] as String?,
              path: data['pathFirmaUsada'] as String?,
            )
          : null;
      final pdfBaseBytes =
          await _cargarPdfBaseInlineDoc(planillaId) ??
          await _cargarPdfBaseFirestore(planillaId);
      final renderedPages = await _cargarRenderPdfBase(planillaId);
      final blocks = _buildBlocksForStampedPdf(
        planillaData: {...data, 'firmaCargadoBlob': firmaCargado},
        auditorSnapshot:
            firmaAuditoria == null &&
                (data['nombreAuditorFirmante'] ?? '').toString().trim().isEmpty
            ? null
            : (
                nombre: data['nombreAuditorFirmante']?.toString().trim(),
                cargo: data['cargoAuditorFirmante']?.toString().trim(),
                urlFirma: data['urlFirmaAuditoria'] as String?,
                pathFirma: data['pathFirmaAuditoria'] as String?,
                firmaBlob: firmaAuditoria,
              ),
        gerenciaSnapshot:
            firmaGerencia == null &&
                (data['nombreFirmante'] ?? '').toString().trim().isEmpty
            ? null
            : (
                nombre: data['nombreFirmante']?.toString().trim(),
                cargo: data['cargoFirmante']?.toString().trim(),
                urlFirma: data['urlFirmaUsada'] as String?,
                pathFirma: data['pathFirmaUsada'] as String?,
                firmaBlob: firmaGerencia,
              ),
      );

      final backendStamped = await _sellarPdfDirectoEnBackend(
        planillaId: planillaId,
        empresaId: empresaId,
        estado: estado,
        sourcePdfUrl: (baseUrl.isEmpty ? currentUrl : baseUrl).isEmpty
            ? null
            : (baseUrl.isEmpty ? currentUrl : baseUrl),
        sourcePdfPath: (basePath.isEmpty ? currentPath : basePath).isEmpty
            ? null
            : (basePath.isEmpty ? currentPath : basePath),
        bloques: _buildDirectPdfBlocksPayload(
          blocks,
          planillaData: data,
          auditorSnapshot:
              firmaAuditoria == null &&
                  (data['nombreAuditorFirmante'] ?? '')
                      .toString()
                      .trim()
                      .isEmpty
              ? null
              : (
                  nombre: data['nombreAuditorFirmante']?.toString().trim(),
                  cargo: data['cargoAuditorFirmante']?.toString().trim(),
                  urlFirma: data['urlFirmaAuditoria'] as String?,
                  pathFirma: data['pathFirmaAuditoria'] as String?,
                  firmaBlob: firmaAuditoria,
                ),
          gerenciaSnapshot:
              firmaGerencia == null &&
                  (data['nombreFirmante'] ?? '').toString().trim().isEmpty
              ? null
              : (
                  nombre: data['nombreFirmante']?.toString().trim(),
                  cargo: data['cargoFirmante']?.toString().trim(),
                  urlFirma: data['urlFirmaUsada'] as String?,
                  pathFirma: data['pathFirmaUsada'] as String?,
                  firmaBlob: firmaGerencia,
                ),
        ),
      );
      if (backendStamped != null) {
        await _planillas.doc(planillaId).update({
          'urlPdf': backendStamped.$1,
          'pathPdf': backendStamped.$2,
          if (baseUrl.isEmpty && currentUrl.isNotEmpty)
            'urlPdfBase': currentUrl,
          if (basePath.isEmpty && currentPath.isNotEmpty)
            'pathPdfBase': currentPath,
          if (currentUrl.isNotEmpty && !data.containsKey('urlPdfOriginal'))
            'urlPdfOriginal': currentUrl,
          if (currentPath.isNotEmpty && !data.containsKey('pathPdfOriginal'))
            'pathPdfOriginal': currentPath,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        return;
      }

      final stamped = await _stampearTrazabilidadEnPdf(
        originalPdfBytes: pdfBaseBytes,
        originalPdfUrl: (baseUrl.isEmpty ? currentUrl : baseUrl).isEmpty
            ? null
            : (baseUrl.isEmpty ? currentUrl : baseUrl),
        originalPdfPath: (basePath.isEmpty ? currentPath : basePath).isEmpty
            ? null
            : (basePath.isEmpty ? currentPath : basePath),
        renderedPages: renderedPages,
        estado: estado,
        bloques: blocks,
      );
      if (stamped == null || stamped.isEmpty) return;

      final (url, path) = await _subirPdfFirmado(
        empresaId: empresaId,
        planillaId: planillaId,
        bytes: stamped,
        nombrePlanilla: _cleanString(data['nombrePlanillaDetectado']),
      );

      await _planillas.doc(planillaId).update({
        'urlPdf': url,
        'pathPdf': path,
        if (baseUrl.isEmpty && currentUrl.isNotEmpty) 'urlPdfBase': currentUrl,
        if (basePath.isEmpty && currentPath.isNotEmpty)
          'pathPdfBase': currentPath,
        if (currentUrl.isNotEmpty && !data.containsKey('urlPdfOriginal'))
          'urlPdfOriginal': currentUrl,
        if (currentPath.isNotEmpty && !data.containsKey('pathPdfOriginal'))
          'pathPdfOriginal': currentPath,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[PpService] No se pudo reparar PDF firmado: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // READS
  // ─────────────────────────────────────────────────────────────────────────

  Stream<List<PpLote>> streamLotes(String empresaId) => _lotes
      .where('empresaId', isEqualTo: empresaId)
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map((d) => PpLote.fromMap(d.id, d.data())).toList());

  Stream<List<PpPlanilla>> streamPlanillasPorLote(String loteId) => _planillas
      .where('loteId', isEqualTo: loteId)
      .orderBy('createdAt', descending: false)
      .snapshots()
      .map(
        (s) => s.docs.map((d) => PpPlanilla.fromMap(d.id, d.data())).toList(),
      );

  Stream<List<PpPlanilla>> streamPlanillasPorEmpresa(
    String empresaId, {
    PpEstado? estado,
  }) {
    var q = _planillas.where('empresaId', isEqualTo: empresaId);
    if (estado != null) q = q.where('estado', isEqualTo: estado.valor);
    return q
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (s) => s.docs.map((d) => PpPlanilla.fromMap(d.id, d.data())).toList(),
        );
  }

  Stream<List<PpFlujoEvento>> streamHistorial(String planillaId) => _flujo
      .where('planillaId', isEqualTo: planillaId)
      .orderBy('realizadoEn', descending: true)
      .snapshots()
      .map(
        (s) =>
            s.docs.map((d) => PpFlujoEvento.fromMap(d.id, d.data())).toList(),
      );

  Future<PpPlanilla?> getPlanilla(String planillaId) async {
    final snap = await _planillas.doc(planillaId).get();
    if (!snap.exists) return null;
    return PpPlanilla.fromMap(snap.id, snap.data()!);
  }

  Future<PpLote?> getLote(String loteId) async {
    if (loteId.isEmpty) return null;
    final snap = await _lotes.doc(loteId).get();
    if (!snap.exists) return null;
    return PpLote.fromMap(snap.id, snap.data()!);
  }

  Future<void> _eliminarSubcoleccionPlanilla(
    String planillaId,
    String nombreSubcoleccion,
  ) async {
    try {
      final col = _planillas.doc(planillaId).collection(nombreSubcoleccion);
      final snap = await col.get();
      if (snap.docs.isEmpty) return;

      WriteBatch batch = _db.batch();
      var ops = 0;

      Future<void> commitBatch() async {
        if (ops == 0) return;
        await batch.commit();
        batch = _db.batch();
        ops = 0;
      }

      for (final doc in snap.docs) {
        batch.delete(doc.reference);
        ops++;
        if (ops >= 400) {
          await commitBatch();
        }
      }

      await commitBatch();
    } catch (e) {
      debugPrint(
        '[PpService] No se pudo limpiar $nombreSubcoleccion de $planillaId: $e',
      );
    }
  }

  Future<void> _reconciliarLoteTrasEliminarPlanilla({
    required String loteId,
    required String empresaId,
  }) async {
    final loteRef = _lotes.doc(loteId);
    final loteSnap = await loteRef.get();
    if (!loteSnap.exists) return;

    final planillasSnap = await _planillas
        .where('loteId', isEqualTo: loteId)
        .get();
    if (planillasSnap.docs.isEmpty) {
      final loteData = loteSnap.data() ?? const <String, dynamic>{};
      final excelPath = (loteData['excelPath'] ?? '').toString().trim();
      if (excelPath.isNotEmpty) {
        await _storage.ref(excelPath).delete().catchError((_) {});
      }
      await loteRef.delete();
      return;
    }

    final estados = planillasSnap.docs
        .map((doc) => (doc.data()['estado'] ?? '').toString())
        .toList();
    final firmadas = estados.where((s) => s == PpEstado.firmada.valor).length;
    final rechazadas = estados
        .where((s) => s == PpEstado.rechazada.valor)
        .length;
    final completado =
        (firmadas + rechazadas) == estados.length && estados.isNotEmpty;
    final algunAvance = estados.any(
      (s) =>
          s != PpEstado.cargada.valor &&
          s != PpEstado.pendiente_validacion.valor,
    );

    await loteRef.set({
      'empresaId': empresaId,
      'totalPlanillas': planillasSnap.docs.length,
      'totalPdfs': planillasSnap.docs.length,
      'planillasFirmadas': firmadas,
      'planillasRechazadas': rechazadas,
      'estado': completado
          ? PpLoteEstado.completado.valor
          : (algunAvance
                ? PpLoteEstado.en_proceso.valor
                : PpLoteEstado.listo.valor),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Cuenta planillas pendientes por rol (para badge/notificaciones).
  Future<int> contarPendientes(String empresaId, String rolPlanillas) async {
    PpEstado? estado;
    if (rolPlanillas == PpRoles.auditoria) {
      estado = PpEstado.en_revision_auditoria;
    }
    if (rolPlanillas == PpRoles.gerencia) {
      estado = PpEstado.pendiente_firma_gerencia;
    }
    if (estado == null) return 0;

    final snap = await _planillas
        .where('empresaId', isEqualTo: empresaId)
        .where('estado', isEqualTo: estado.valor)
        .count()
        .get();
    return snap.count ?? 0;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // UTILIDADES INTERNAS
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _transicionar({
    required String planillaId,
    required String loteId,
    required String empresaId,
    required PpEstado desde,
    required PpEstado hacia,
    required PpAccion accion,
    required String actorId,
    String? nombreActor,
    String? observacion,
    Map<String, dynamic>? camposExtra,
  }) async {
    // Validar transición
    final validas = kPpTransicionesValidas[desde] ?? {};
    if (!validas.contains(hacia)) {
      throw PpException(
        'Transición no permitida: ${desde.etiqueta} → ${hacia.etiqueta}',
      );
    }

    // Leer estado actual
    final snap = await _planillas.doc(planillaId).get();
    if (!snap.exists) throw const PpException('Planilla no encontrada.');
    final estadoReal = PpEstadoX.deString(
      (snap.data()?['estado'] ?? '').toString(),
    );
    if (estadoReal != desde) {
      throw PpException(
        'Estado actual (${estadoReal.etiqueta}) no coincide con el esperado (${desde.etiqueta}).',
      );
    }

    final update = <String, dynamic>{
      'estado': hacia.valor,
      'updatedAt': FieldValue.serverTimestamp(),
      ...?camposExtra,
    };
    await _planillas.doc(planillaId).update(update);

    await _registrarEventoLote(
      planillaId: planillaId,
      loteId: loteId,
      empresaId: empresaId,
      accion: accion,
      actorId: actorId,
      nombreActor: nombreActor,
      observacion: observacion,
    );

    // Actualizar estado del lote (solo si la planilla pertenece a un lote).
    if (loteId.isNotEmpty) {
      await _lotes.doc(loteId).set({
        'estado': PpLoteEstado.en_proceso.valor,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  Future<void> _registrarEventoLote({
    required String planillaId,
    required String loteId,
    required String empresaId,
    required PpAccion accion,
    required String actorId,
    String? nombreActor,
    String? observacion,
    Map<String, dynamic>? metadatos,
  }) async {
    await _flujo.add({
      'planillaId': planillaId,
      'loteId': loteId,
      'empresaId': empresaId,
      'accion': accion.valor,
      'realizadoPor': actorId,
      'nombreActor': nombreActor,
      'realizadoEn': FieldValue.serverTimestamp(),
      'observacion': observacion,
      'metadatos': metadatos,
    });
  }

  Future<(String, String)> _subirExcel({
    required String empresaId,
    required String loteId,
    required Uint8List bytes,
    required String nombre,
  }) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final safe = nombre.replaceAll(RegExp(r'[^\w.\-]'), '_');
    final path = 'planillas_pago/$empresaId/$loteId/excel/${ts}_$safe';
    final ref = _storage.ref(path);
    await ref.putData(
      bytes,
      SettableMetadata(
        contentType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      ),
    );
    final url = await ref.getDownloadURL();
    return (url, path);
  }

  Future<(String, String)> _subirPdf({
    required String empresaId,
    required String loteId,
    required Uint8List bytes,
    required String nombre,
  }) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final safe = nombre.replaceAll(RegExp(r'[^\w.\-]'), '_');
    final path = 'planillas_pago/$empresaId/$loteId/pdfs/${ts}_$safe';
    final ref = _storage.ref(path);
    await ref.putData(bytes, _pdfMetadata(_buildPdfFileName(nombre)));
    final url = await ref.getDownloadURL();
    return (url, path);
  }

  Future<(String, String)> _subirPdfBase({
    required String empresaId,
    required String loteId,
    required String planillaId,
    required Uint8List bytes,
    required String nombre,
  }) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final safe = nombre.replaceAll(RegExp(r'[^\w.\-]'), '_');
    final path = loteId.trim().isNotEmpty
        ? 'planillas_pago/$empresaId/$loteId/originales/${planillaId}_${ts}_$safe'
        : 'planillas_pago/$empresaId/directos_base/$planillaId/${ts}_$safe';
    final ref = _storage.ref(path);
    await ref.putData(bytes, _pdfMetadata(_buildPdfFileName(nombre)));
    final url = await ref.getDownloadURL();
    return (url, path);
  }

  Future<void> _guardarRenderPdfBase({
    required String planillaId,
    required String empresaId,
    required Uint8List pdfBytes,
  }) async {
    try {
      final pages = await Printing.raster(
        pdfBytes,
        dpi: _renderCacheDpi,
      ).toList();
      if (pages.isEmpty) return;

      final col = _planillas.doc(planillaId).collection('_render_pages');
      final existing = await col.get();
      WriteBatch batch = _db.batch();
      var ops = 0;

      Future<void> commitBatch() async {
        if (ops == 0) return;
        await batch.commit();
        batch = _db.batch();
        ops = 0;
      }

      for (final doc in existing.docs) {
        batch.delete(doc.reference);
        ops++;
        if (ops >= 400) {
          await commitBatch();
        }
      }

      for (var i = 0; i < pages.length; i++) {
        final page = pages[i];
        batch.set(col.doc(i.toString().padLeft(4, '0')), {
          'empresaId': empresaId,
          'index': i,
          'png': await page.toPng(),
          'width': page.width.toDouble(),
          'height': page.height.toDouble(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        ops++;
        if (ops >= 400) {
          await commitBatch();
        }
      }

      await commitBatch();
    } catch (e) {
      debugPrint('[PpService] No se pudo guardar render base del PDF: $e');
    }
  }

  Future<List<_RenderedPdfPage>> _cargarRenderPdfBase(String planillaId) async {
    try {
      final snap = await _planillas
          .doc(planillaId)
          .collection('_render_pages')
          .orderBy('index')
          .get();
      return snap.docs
          .map((doc) {
            final data = doc.data();
            final pngBytes = _coerceBinary(data['png']) ?? Uint8List(0);
            final widthPx = (data['width'] as num?)?.toDouble() ?? 0;
            final heightPx = (data['height'] as num?)?.toDouble() ?? 0;
            return (pngBytes: pngBytes, widthPx: widthPx, heightPx: heightPx);
          })
          .where((page) {
            return page.pngBytes.isNotEmpty &&
                page.widthPx > 0 &&
                page.heightPx > 0;
          })
          .toList(growable: false);
    } catch (e) {
      debugPrint('[PpService] No se pudo cargar render base del PDF: $e');
      return const [];
    }
  }

  Future<void> _guardarPdfBaseFirestore({
    required String planillaId,
    required String empresaId,
    required Uint8List pdfBytes,
  }) async {
    try {
      if (pdfBytes.isEmpty) return;
      final col = _planillas.doc(planillaId).collection('_pdf_base_chunks');
      final existing = await col.get();
      WriteBatch batch = _db.batch();
      var ops = 0;

      Future<void> commitBatch() async {
        if (ops == 0) return;
        await batch.commit();
        batch = _db.batch();
        ops = 0;
      }

      for (final doc in existing.docs) {
        batch.delete(doc.reference);
        ops++;
        if (ops >= 400) {
          await commitBatch();
        }
      }

      var index = 0;
      for (
        var offset = 0;
        offset < pdfBytes.length;
        offset += _maxFirestorePdfChunkBytes
      ) {
        final end = (offset + _maxFirestorePdfChunkBytes) < pdfBytes.length
            ? offset + _maxFirestorePdfChunkBytes
            : pdfBytes.length;
        final chunk = Uint8List.sublistView(pdfBytes, offset, end);
        batch.set(col.doc(index.toString().padLeft(4, '0')), {
          'empresaId': empresaId,
          'index': index,
          'bytes': chunk,
          'size': chunk.length,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        index++;
        ops++;
        if (ops >= 400) {
          await commitBatch();
        }
      }

      await commitBatch();
    } catch (e) {
      debugPrint('[PpService] No se pudo guardar PDF base en Firestore: $e');
    }
  }

  Future<void> _guardarPdfBaseInlineDoc({
    required String planillaId,
    required String empresaId,
    required Uint8List pdfBytes,
  }) async {
    try {
      final ref = _planillas
          .doc(planillaId)
          .collection('_pdf_base_inline')
          .doc('base');
      if (pdfBytes.isEmpty || pdfBytes.length > _maxInlinePdfDocBytes) {
        await ref.delete().catchError((_) {});
        return;
      }
      await ref.set({
        'empresaId': empresaId,
        'bytes': pdfBytes,
        'size': pdfBytes.length,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[PpService] No se pudo guardar PDF inline base: $e');
    }
  }

  Future<Uint8List?> _cargarPdfBaseInlineDoc(String planillaId) async {
    try {
      final snap = await _planillas
          .doc(planillaId)
          .collection('_pdf_base_inline')
          .doc('base')
          .get();
      if (!snap.exists) return null;
      final data = snap.data() ?? const <String, dynamic>{};
      final bytes = _coerceBinary(data['bytes']);
      if (bytes == null || bytes.isEmpty) return null;
      return bytes;
    } catch (e) {
      debugPrint('[PpService] No se pudo cargar PDF inline base: $e');
      return null;
    }
  }

  Future<Uint8List?> _cargarPdfBaseFirestore(String planillaId) async {
    try {
      final snap = await _planillas
          .doc(planillaId)
          .collection('_pdf_base_chunks')
          .orderBy('index')
          .get();
      if (snap.docs.isEmpty) return null;

      final bytes = BytesBuilder(copy: false);
      for (final doc in snap.docs) {
        final data = doc.data();
        final chunk = _coerceBinary(data['bytes']);
        if (chunk == null || chunk.isEmpty) {
          return null;
        }
        bytes.add(chunk);
      }

      final merged = bytes.takeBytes();
      return merged.isEmpty ? null : merged;
    } catch (e) {
      debugPrint('[PpService] No se pudo cargar PDF base desde Firestore: $e');
      return null;
    }
  }

  Future<Uint8List> _aplicarFirmaCargaInicial({
    required Uint8List pdfBytes,
    required ({
      String? nombre,
      String? cargo,
      String? urlFirma,
      String? pathFirma,
      Uint8List? firmaBlob,
    })
    actorSnapshot,
  }) async {
    final stamped = await _stampearTrazabilidadEnPdf(
      originalPdfBytes: pdfBytes,
      estado: PpEstado.cargada,
      bloques: [
        _PdfStampBlock(
          titulo: 'ELABORADO',
          color: PdfColors.orange700,
          firmaBytes:
              actorSnapshot.firmaBlob ??
              await _loadBinary(
                url: actorSnapshot.urlFirma,
                path: actorSnapshot.pathFirma,
              ),
          nombre: actorSnapshot.nombre,
          cargo: actorSnapshot.cargo,
          fecha: DateFormat('dd/MM/yyyy').format(DateTime.now()),
        ),
      ],
    );
    return stamped ?? pdfBytes;
  }

  Future<Uint8List?> _stampearTrazabilidadEnPdf({
    Uint8List? originalPdfBytes,
    String? originalPdfUrl,
    String? originalPdfPath,
    List<_RenderedPdfPage>? renderedPages,
    required List<_PdfStampBlock> bloques,
    PpEstado? estado,
  }) async {
    const dpi = 150.0;
    final bloquesValidos = bloques
        .where((b) {
          return (b.firmaBytes != null && b.firmaBytes!.isNotEmpty) ||
              ((b.nombre ?? '').trim().isNotEmpty) ||
              ((b.cargo ?? '').trim().isNotEmpty) ||
              ((b.fecha ?? '').trim().isNotEmpty);
        })
        .toList(growable: false);
    final renderedPagesValidas = (renderedPages ?? const <_RenderedPdfPage>[])
        .where(
          (page) =>
              page.pngBytes.isNotEmpty && page.widthPx > 0 && page.heightPx > 0,
        )
        .toList(growable: false);
    final pdfBytes = renderedPagesValidas.isNotEmpty
        ? null
        : originalPdfBytes ??
              await _loadBinary(url: originalPdfUrl, path: originalPdfPath);
    if ((pdfBytes == null || pdfBytes.isEmpty) &&
        renderedPagesValidas.isEmpty) {
      return null;
    }
    if (bloquesValidos.isEmpty) {
      return null;
    }

    pw.Font? arial;
    try {
      final data = await rootBundle.load('assets/arial.ttf');
      arial = pw.Font.ttf(data);
    } catch (_) {}

    pw.TextStyle tsPdf(double sz, {bool bold = false, PdfColor? color}) =>
        pw.TextStyle(
          font: arial,
          fontSize: sz,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: color,
        );

    final pages = <_RenderedPdfPage>[];
    if (renderedPagesValidas.isNotEmpty) {
      pages.addAll(renderedPagesValidas);
    } else {
      final rasterPages = await Printing.raster(pdfBytes!, dpi: dpi).toList();
      if (rasterPages.isEmpty) return null;
      for (final page in rasterPages) {
        pages.add((
          pngBytes: await page.toPng(),
          widthPx: page.width.toDouble(),
          heightPx: page.height.toDouble(),
        ));
      }
    }
    if (pages.isEmpty) return null;

    final doc = pw.Document();

    for (int i = 0; i < pages.length; i++) {
      final page = pages[i];
      final pageImage = pw.MemoryImage(page.pngBytes);
      final pageDpi = renderedPagesValidas.isNotEmpty ? _renderCacheDpi : dpi;
      final pageWidthPts = page.widthPx * 72.0 / pageDpi;
      final pageHeightPts = page.heightPx * 72.0 / pageDpi;
      final isLast = i == pages.length - 1;
      final stampTop = pageHeightPts * 0.80;
      final blockWidth = switch (bloquesValidos.length) {
        1 => pageWidthPts * 0.26,
        2 => pageWidthPts * 0.24,
        _ => pageWidthPts * 0.20,
      };
      final leftPositions = switch (bloquesValidos.length) {
        1 => <double>[pageWidthPts * 0.06],
        2 => <double>[
          pageWidthPts * 0.06,
          pageWidthPts - (pageWidthPts * 0.06) - blockWidth,
        ],
        _ => <double>[
          pageWidthPts * 0.04,
          (pageWidthPts - blockWidth) / 2,
          pageWidthPts - (pageWidthPts * 0.04) - blockWidth,
        ],
      };

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(pageWidthPts, pageHeightPts),
          margin: pw.EdgeInsets.zero,
          build: (_) => pw.Stack(
            children: [
              pw.Image(pageImage, fit: pw.BoxFit.fill),
              if (estado != null)
                pw.Positioned(
                  left: pageWidthPts - 44,
                  top: pageHeightPts - 44,
                  child: pw.SizedBox(
                    width: 36,
                    height: 36,
                    child: pw.CustomPaint(
                      size: const PdfPoint(36, 36),
                      painter: (canvas, size) =>
                          _paintEstadoIcon(canvas, size, estado),
                    ),
                  ),
                ),
              if (isLast)
                ...List.generate(bloquesValidos.length, (index) {
                  final bloque = bloquesValidos[index];
                  final firmaImage =
                      bloque.firmaBytes != null && bloque.firmaBytes!.isNotEmpty
                      ? pw.MemoryImage(bloque.firmaBytes!)
                      : null;
                  return pw.Positioned(
                    left: leftPositions[index],
                    top: stampTop,
                    child: pw.SizedBox(
                      width: blockWidth,
                      child: pw.Container(
                        padding: const pw.EdgeInsets.all(5),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.center,
                          mainAxisSize: pw.MainAxisSize.min,
                          children: [
                            pw.Text(
                              bloque.titulo,
                              style: tsPdf(7, bold: true, color: bloque.color),
                              textAlign: pw.TextAlign.center,
                            ),
                            pw.SizedBox(height: 3),
                            if (firmaImage != null)
                              pw.Image(
                                firmaImage,
                                width: 80,
                                height: 50,
                                fit: pw.BoxFit.contain,
                              )
                            else
                              pw.SizedBox(height: 18),
                            pw.SizedBox(height: 3),
                            if ((bloque.nombre ?? '').trim().isNotEmpty)
                              pw.Text(
                                bloque.nombre!.trim(),
                                style: tsPdf(6.5, bold: true),
                                textAlign: pw.TextAlign.center,
                              ),
                            if ((bloque.cargo ?? '').trim().isNotEmpty)
                              pw.Text(
                                bloque.cargo!.trim(),
                                style: tsPdf(6),
                                textAlign: pw.TextAlign.center,
                              ),
                            if ((bloque.fecha ?? '').trim().isNotEmpty)
                              pw.Text(
                                bloque.fecha!.trim(),
                                style: tsPdf(6),
                                textAlign: pw.TextAlign.center,
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
            ],
          ),
        ),
      );
    }

    return doc.save();
  }

  Future<(String, String)> _subirPdfFirmado({
    required String empresaId,
    required String planillaId,
    required Uint8List bytes,
    String? nombrePlanilla,
  }) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final path =
        'planillas_pago/$empresaId/firmados/${planillaId}_${ts}_firmado.pdf';
    final ref = _storage.ref(path);
    final fileName = _buildPdfFileName(
      nombrePlanilla,
      fallbackBase: '${planillaId}_firmado',
    );
    await ref.putData(bytes, _pdfMetadata(fileName));
    final url = await ref.getDownloadURL();
    return (url, path);
  }

  String _buildPdfFileName(
    String? rawName, {
    String fallbackBase = 'planilla',
  }) {
    final candidate = (rawName ?? '').trim();
    final normalizedBase = candidate.isNotEmpty ? candidate : fallbackBase;
    final withoutExtension = normalizedBase.toLowerCase().endsWith('.pdf')
        ? normalizedBase.substring(0, normalizedBase.length - 4)
        : normalizedBase;
    final safe = withoutExtension
        .replaceAll(RegExp(r'[<>:"/\\|?*\n\r;]'), '_')
        .trim()
        .replaceAll(RegExp(r'[. ]+$'), '');
    final resolved = safe.isEmpty ? fallbackBase : safe;
    return '$resolved.pdf';
  }

  SettableMetadata _pdfMetadata(String fileName) {
    final asciiFallback = fileName.replaceAll(RegExp(r'[^\x20-\x7E]'), '_');
    final encoded = Uri.encodeComponent(fileName);
    return SettableMetadata(
      contentType: 'application/pdf',
      contentDisposition:
          'inline; filename="$asciiFallback"; filename*=UTF-8\'\'$encoded',
    );
  }

  Future<void> sincronizarMetadataPdfDescarga({
    required String empresaId,
    required String planillaId,
  }) async {
    try {
      final snap = await _planillas.doc(planillaId).get();
      if (!snap.exists) return;
      final data = snap.data() ?? const <String, dynamic>{};
      final empresaPlanilla = _cleanString(data['empresaId']) ?? '';
      if (empresaPlanilla != empresaId.trim()) return;

      final path =
          _normalizeStoragePath(data['pathPdf']) ??
          _normalizeStoragePath(data['urlPdf']);
      if (path == null || path.isEmpty) return;

      final fileName = _buildPdfFileName(
        _cleanString(data['nombrePlanillaDetectado']) ??
            _cleanString(data['nombreArchivoOriginal']),
        fallbackBase: planillaId,
      );
      await _storage.ref(path).updateMetadata(_pdfMetadata(fileName));
    } catch (e) {
      debugPrint('[PpService] No se pudo sincronizar metadata PDF: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // GENERAR PLANILLAS DESDE FILAS EXCEL
  // ─────────────────────────────────────────────────────────────────────────

  /// Genera un PDF por cada fila seleccionada, los sube a Storage y crea
  /// una PpPlanilla por cada uno. Retorna el loteId creado.
  Future<String> crearPlanillasDesdeFilas({
    required String empresaId,
    required String actorId,
    required String rolPlanillas,
    String? nombreActor,
    required List<PpExcelFila> filasSeleccionadas,
    Uint8List? excelBytes,
    String? excelNombre,
    String? descripcion,
  }) async {
    if (filasSeleccionadas.isEmpty) {
      throw const PpException('Selecciona al menos una fila para generar.');
    }
    _validarRol('confirmar_carga', rolPlanillas);
    final actorSnapshot = await _getActorSnapshot(
      actorId,
      empresaId,
      nombreActor,
    );

    // Logo activo y nombre de empresa para el PDF
    final logoActivo = await getLogoActivoMeta(empresaId);
    final logoBytes = await _cargarLogoEmpresa(empresaId);
    final empresaNombrePlanilla = await _resolverNombreEmpresaPlanilla(
      empresaId: empresaId,
      nombreLogoPreferido: logoActivo?['nombre'],
    );

    final loteRef = _lotes.doc();
    final loteId = loteRef.id;

    // Excel opcional
    String? excelUrl;
    String? excelPath;
    if (excelBytes != null && excelNombre != null) {
      final (u, p) = await _subirExcel(
        empresaId: empresaId,
        loteId: loteId,
        bytes: excelBytes,
        nombre: excelNombre,
      );
      excelUrl = u;
      excelPath = p;
    }

    await loteRef.set({
      'empresaId': empresaId,
      'creadoPor': actorId,
      'nombreCreadoPor': nombreActor,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'estado': PpLoteEstado.procesando.valor,
      'excelUrl': excelUrl,
      'excelPath': excelPath,
      'excelNombre': excelNombre,
      'totalPdfs': filasSeleccionadas.length,
      'totalPlanillas': 0,
      'planillasFirmadas': 0,
      'planillasRechazadas': 0,
      'descripcion': descripcion,
      'origen': 'excel_generado',
      'empresaNombre': empresaNombrePlanilla,
      'logoPath': logoActivo?['path'],
      'logoUrl': logoActivo?['url'],
      'logoNombre': logoActivo?['nombre'],
    });

    await _registrarEventoLote(
      planillaId: loteId,
      loteId: loteId,
      empresaId: empresaId,
      accion: PpAccion.lote_creado,
      actorId: actorId,
      nombreActor: nombreActor,
      metadatos: {
        'filasSeleccionadas': filasSeleccionadas.length,
        'origen': 'excel_generado',
      },
    );

    var creadas = 0;
    for (final fila in filasSeleccionadas) {
      final pdfBytes = await _generarPdfDesdeFila(
        fila: fila,
        logoBytes: logoBytes,
        empresaNombre: empresaNombrePlanilla,
        nombreElaborado: actorSnapshot.nombre,
        cargoElaborado: actorSnapshot.cargo,
        firmaElaboradoUrl: actorSnapshot.urlFirma,
        firmaElaboradoPath: actorSnapshot.pathFirma,
        firmaElaboradoBlob: actorSnapshot.firmaBlob,
      );

      final nombre = _nombreArchivoFila(
        fila,
        empresaNombre: empresaNombrePlanilla,
      );
      final (pdfUrl, pdfPath) = await _subirPdf(
        empresaId: empresaId,
        loteId: loteId,
        bytes: pdfBytes,
        nombre: nombre,
      );

      final planillaRef = _planillas.doc();
      final ahora = FieldValue.serverTimestamp();
      await planillaRef.set({
        'empresaId': empresaId,
        'empresaNombre': empresaNombrePlanilla,
        'loteId': loteId,
        'nombreArchivoOriginal': nombre,
        'nombrePlanillaDetectado': fila.nombrePlanilla,
        'fechaPlanillaDetectada': fila.fecha,
        'valorDetectado': fila.valor,
        'logoPath': logoActivo?['path'],
        'logoUrl': logoActivo?['url'],
        'logoNombre': logoActivo?['nombre'],
        'sinLogo': logoActivo == null,
        'estado': PpEstado.cargada.valor,
        'cargadoPor': actorId,
        'nombreCargado': actorSnapshot.nombre,
        'cargoCargado': actorSnapshot.cargo,
        'urlFirmaCargado': actorSnapshot.urlFirma,
        'revisadoPor': null,
        'revisadoEn': null,
        'firmadoPor': null,
        'firmadoEn': null,
        'urlFirmaAuditoria': null,
        'nombreAuditorFirmante': null,
        'cargoAuditorFirmante': null,
        'urlFirmaUsada': null,
        'nombreFirmante': null,
        'cargoFirmante': null,
        'urlPdf': pdfUrl,
        'pathPdf': pdfPath,
        'datosExcel': {
          ...fila.extras,
          'empresa_nombre': empresaNombrePlanilla,
          'logo_path': logoActivo?['path'],
          'logo_url': logoActivo?['url'],
          'logo_nombre': logoActivo?['nombre'],
          'sin_logo': logoActivo == null,
          if (fila.nombrePlanilla != null)
            'nombre_planilla': fila.nombrePlanilla!,
          if (fila.fecha != null) 'fecha': fila.fecha!,
          if (fila.valor != null) 'valor': fila.valor!,
          // Stored so PDF can be regenerated from Firestore without Storage reads.
          'tipo_generacion': 'excel_generado',
          'fila_row': fila.toMap(),
        },
        'matchEstado': PpMatchEstado.coincidencia_exacta.valor,
        'excelRowIndex': fila.rowIndex,
        'metadatosExtraccion': {
          'metodo': 'generado_desde_excel',
          'rowIndex': fila.rowIndex,
          'empresaNombre': empresaNombrePlanilla,
          'cargadoEn': DateTime.now().toIso8601String(),
        },
        'observaciones': [],
        'createdAt': ahora,
        'updatedAt': ahora,
      });

      await _registrarEventoLote(
        planillaId: planillaRef.id,
        loteId: loteId,
        empresaId: empresaId,
        accion: PpAccion.planilla_creada,
        actorId: actorId,
        nombreActor: nombreActor,
        metadatos: {'rowIndex': fila.rowIndex, 'nombre': nombre},
      );
      creadas++;
    }

    await loteRef.update({
      'totalPlanillas': creadas,
      'estado': PpLoteEstado.listo.valor,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    debugPrint(
      '[PpService] Lote generado desde Excel: $loteId con $creadas planillas',
    );
    return loteId;
  }

  Future<String> crearPlanillaConsolidadaDesdeExcel({
    required String empresaId,
    required String actorId,
    required String rolPlanillas,
    required String consolidado,
    required List<PpExcelFila> filas,
    String? nombreActor,
    Uint8List? excelBytes,
    String? excelNombre,
    Uint8List? logoBytes,
    String? logoPath,
    String? logoUrl,
    String? logoNombre,
    bool sinLogo = false,
    Uint8List? firmaElaboradoBlob,
    String? descripcion,
    String? sheetTitle,
  }) async {
    if (filas.isEmpty) {
      throw const PpException(
        'No hay filas para generar la planilla consolidada.',
      );
    }
    _validarRol('confirmar_carga', rolPlanillas);
    final actorSnapshot = await _getActorSnapshot(
      actorId,
      empresaId,
      nombreActor,
    );
    // Use blob passed from caller (loaded in UI layer) — fallback to snapshot blob.
    final firmaBlob = firmaElaboradoBlob ?? actorSnapshot.firmaBlob;
    final resolvedLogo = await _resolverLogoGeneracion(
      empresaId: empresaId,
      logoBytes: logoBytes,
      logoPath: logoPath,
      logoUrl: logoUrl,
      logoNombre: logoNombre,
      sinLogo: sinLogo,
    );
    final empresaNombrePlanilla = await _resolverNombreEmpresaPlanilla(
      empresaId: empresaId,
      nombreLogoPreferido: resolvedLogo.nombre,
    );
    final logoFinal = resolvedLogo.bytes;

    final loteRef = _lotes.doc();
    final loteId = loteRef.id;

    String? excelUrl;
    String? excelPath;
    if (excelBytes != null && excelNombre != null) {
      final (u, p) = await _subirExcel(
        empresaId: empresaId,
        loteId: loteId,
        bytes: excelBytes,
        nombre: excelNombre,
      );
      excelUrl = u;
      excelPath = p;
    }

    final fechaPlanilla = _firstNonEmptyDate(filas);
    final totalPlanilla = _sumarValores(filas);
    final pagador = _firstNonEmptyExtra(filas, const ['pagador', 'banco']);
    final banco = _firstNonEmptyExtra(filas, const ['banco']);

    await loteRef.set({
      'empresaId': empresaId,
      'creadoPor': actorId,
      'nombreCreadoPor': nombreActor,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'estado': PpLoteEstado.procesando.valor,
      'excelUrl': excelUrl,
      'excelPath': excelPath,
      'excelNombre': excelNombre,
      'totalPdfs': 1,
      'totalPlanillas': 0,
      'planillasFirmadas': 0,
      'planillasRechazadas': 0,
      'descripcion': descripcion,
      'origen': 'excel_consolidado',
      'empresaNombre': empresaNombrePlanilla,
      'logoPath': resolvedLogo.path,
      'logoUrl': resolvedLogo.url,
      'logoNombre': resolvedLogo.nombre,
      'sinLogo': resolvedLogo.sinLogo,
    });

    await _registrarEventoLote(
      planillaId: loteId,
      loteId: loteId,
      empresaId: empresaId,
      accion: PpAccion.lote_creado,
      actorId: actorId,
      nombreActor: nombreActor,
      metadatos: {
        'consolidado': consolidado,
        'filasConsolidadas': filas.length,
        'origen': 'excel_consolidado',
      },
    );

    final pdfBytes = await _generarPdfConsolidadoDesdeFilas(
      consolidado: consolidado,
      filas: filas,
      logoBytes: logoFinal,
      empresaNombre: empresaNombrePlanilla,
      sheetTitle: sheetTitle,
      nombreElaborado: actorSnapshot.nombre,
      cargoElaborado: actorSnapshot.cargo,
      firmaElaboradoUrl: actorSnapshot.urlFirma,
      firmaElaboradoPath: actorSnapshot.pathFirma,
      firmaElaboradoBlob: firmaBlob,
    );

    final nombreArchivo = _nombreArchivoConsolidado(
      consolidado,
      filas,
      empresaNombre: empresaNombrePlanilla,
    );
    final (pdfUrl, pdfPath) = await _subirPdf(
      empresaId: empresaId,
      loteId: loteId,
      bytes: pdfBytes,
      nombre: nombreArchivo,
    );

    final planillaRef = _planillas.doc();
    final ahora = FieldValue.serverTimestamp();
    await planillaRef.set({
      'empresaId': empresaId,
      'empresaNombre': empresaNombrePlanilla,
      'loteId': loteId,
      'nombreArchivoOriginal': nombreArchivo,
      'nombrePlanillaDetectado': consolidado,
      'fechaPlanillaDetectada': fechaPlanilla,
      'valorDetectado': totalPlanilla,
      'logoPath': resolvedLogo.path,
      'logoUrl': resolvedLogo.url,
      'logoNombre': resolvedLogo.nombre,
      'sinLogo': resolvedLogo.sinLogo,
      'estado': PpEstado.cargada.valor,
      'cargadoPor': actorId,
      'nombreCargado': actorSnapshot.nombre,
      'cargoCargado': actorSnapshot.cargo,
      'urlFirmaCargado': actorSnapshot.urlFirma,
      'revisadoPor': null,
      'revisadoEn': null,
      'firmadoPor': null,
      'firmadoEn': null,
      'urlFirmaAuditoria': null,
      'nombreAuditorFirmante': null,
      'cargoAuditorFirmante': null,
      'urlFirmaUsada': null,
      'nombreFirmante': null,
      'cargoFirmante': null,
      'urlPdf': pdfUrl,
      'pathPdf': pdfPath,
      'datosExcel': {
        'tipo_generacion': 'excel_consolidado',
        'empresa_nombre': empresaNombrePlanilla,
        'consolidado': consolidado,
        'pagador': pagador,
        ...?banco == null ? null : {'banco': banco},
        'logo_path': resolvedLogo.path,
        'logo_url': resolvedLogo.url,
        'logo_nombre': resolvedLogo.nombre,
        'sin_logo': resolvedLogo.sinLogo,
        'filas_consolidadas': filas.length,
        'rango_filas_excel': _rangoFilasExcel(filas),
        ...?sheetTitle == null ? null : {'sheet_title': sheetTitle},
        // Stored so PDF can be regenerated from Firestore without Storage reads.
        'filas_rows': filas.map((f) => f.toMap()).toList(),
      },
      'matchEstado': PpMatchEstado.coincidencia_exacta.valor,
      'excelRowIndex': filas.first.rowIndex,
      'metadatosExtraccion': {
        'metodo': 'generado_desde_excel_consolidado',
        'excelRows': filas.map((f) => f.excelRowNumber).toList(),
        'empresaNombre': empresaNombrePlanilla,
        'cargadoEn': DateTime.now().toIso8601String(),
      },
      'observaciones': [],
      'createdAt': ahora,
      'updatedAt': ahora,
    });

    await _registrarEventoLote(
      planillaId: planillaRef.id,
      loteId: loteId,
      empresaId: empresaId,
      accion: PpAccion.planilla_creada,
      actorId: actorId,
      nombreActor: nombreActor,
      metadatos: {
        'consolidado': consolidado,
        'filasConsolidadas': filas.length,
        'nombre': nombreArchivo,
      },
    );

    await loteRef.update({
      'totalPlanillas': 1,
      'estado': PpLoteEstado.listo.valor,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    debugPrint(
      '[PpService] Lote consolidado generado: $loteId para $consolidado',
    );
    return loteId;
  }

  // Genera el PDF de una fila con el template Capital USPEC.
  Future<Uint8List> _generarPdfDesdeFila({
    required PpExcelFila fila,
    required Uint8List logoBytes,
    String? empresaNombre,
    String? nombreElaborado,
    String? cargoElaborado,
    String? firmaElaboradoUrl,
    String? firmaElaboradoPath,
    Uint8List? firmaElaboradoBlob,
    String? nombreAuditoria,
    String? cargoAuditoria,
    String? firmaAuditoriaUrl,
    String? firmaAuditoriaPath,
    Uint8List? firmaAuditoriaBlob,
    String? nombreGerencia,
    String? cargoGerencia,
    String? firmaGerenciaUrl,
    String? firmaGerenciaPath,
    Uint8List? firmaGerenciaBlob,
    PpEstado? estado,
  }) async {
    final doc = pw.Document();
    final logo = logoBytes.isNotEmpty ? pw.MemoryImage(logoBytes) : null;
    // Use Blob first (no Storage round-trip), fallback to URL/path.
    final firmaElaborado =
        firmaElaboradoBlob != null && firmaElaboradoBlob.isNotEmpty
        ? pw.MemoryImage(firmaElaboradoBlob)
        : await _loadPdfImage(url: firmaElaboradoUrl, path: firmaElaboradoPath);
    final firmaAuditoria =
        firmaAuditoriaBlob != null && firmaAuditoriaBlob.isNotEmpty
        ? pw.MemoryImage(firmaAuditoriaBlob)
        : await _loadPdfImage(url: firmaAuditoriaUrl, path: firmaAuditoriaPath);
    final firmaGerencia =
        firmaGerenciaBlob != null && firmaGerenciaBlob.isNotEmpty
        ? pw.MemoryImage(firmaGerenciaBlob)
        : await _loadPdfImage(url: firmaGerenciaUrl, path: firmaGerenciaPath);

    // Fuente
    pw.Font? arial;
    try {
      final data = await rootBundle.load('assets/arial.ttf');
      arial = pw.Font.ttf(data);
    } catch (_) {}

    pw.TextStyle ts(double sz, {bool bold = false}) => pw.TextStyle(
      font: bold ? pw.Font.helveticaBold() : arial,
      fontSize: sz,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
    );

    final numeroPlanilla = fila.nombrePlanilla ?? '';
    final empresaTitulo =
        _cleanString(empresaNombre) ?? 'UNION TEMPORAL CAPITAL USPEC 2025';
    final fechaDisplay = _fechaDisplay(fila.fecha);
    const pagador = 'BBVA';
    final totalFmt = fila.valor != null
        ? NumberFormat('#,##0', 'es_CO').format(fila.valor)
        : '';
    final cols = fila.extras.keys.toList();

    doc.addPage(
      pw.Page(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(18),
          buildForeground: estado != null
              ? (_) => _buildEstadoBadge(estado)
              : null,
        ),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // ── CABECERA ──────────────────────────────────────────────
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                if (logo != null)
                  pw.SizedBox(
                    width: 75,
                    height: 50,
                    child: pw.Image(logo, fit: pw.BoxFit.contain),
                  ),
                pw.SizedBox(width: 10),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(empresaTitulo, style: ts(9, bold: true)),
                      pw.Text('Seguimiento o Transferencias', style: ts(8)),
                    ],
                  ),
                ),
                pw.Table(
                  border: pw.TableBorder.all(width: 0.5),
                  columnWidths: {
                    0: const pw.FixedColumnWidth(60),
                    1: const pw.FixedColumnWidth(85),
                  },
                  children: [
                    _pdfInfoRow('N° Planilla', numeroPlanilla, ts),
                    _pdfInfoRow('Fecha', fechaDisplay, ts),
                    _pdfInfoRow('Pagador', pagador, ts),
                    _pdfInfoRow('Total', totalFmt, ts),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 14),
            // ── TABLA DE DATOS ────────────────────────────────────────
            if (cols.isNotEmpty)
              pw.Table(
                border: pw.TableBorder.all(width: 0.5),
                columnWidths: _pdfColumnWidths(cols),
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(
                      color: PdfColors.grey300,
                    ),
                    children: cols
                        .map(
                          (c) => pw.Padding(
                            padding: const pw.EdgeInsets.symmetric(
                              horizontal: 2,
                              vertical: 3,
                            ),
                            child: pw.Text(
                              _colLabel(c),
                              style: ts(5.5, bold: true),
                              textAlign: pw.TextAlign.center,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  pw.TableRow(
                    children: cols
                        .map(
                          (c) => pw.Padding(
                            padding: const pw.EdgeInsets.symmetric(
                              horizontal: 2,
                              vertical: 3,
                            ),
                            child: pw.Text(
                              fila.extras[c] ?? '',
                              style: ts(6, bold: c == 'valor_a_pagar'),
                              textAlign: c == 'valor_a_pagar'
                                  ? pw.TextAlign.right
                                  : pw.TextAlign.center,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            pw.Spacer(),
            _buildFooterFirmas(
              ts: ts,
              nombreElaborado: nombreElaborado,
              cargoElaborado: cargoElaborado,
              firmaElaborado: firmaElaborado,
              nombreAuditoria: nombreAuditoria,
              cargoAuditoria: cargoAuditoria,
              firmaAuditoria: firmaAuditoria,
              nombreGerencia: nombreGerencia,
              cargoGerencia: cargoGerencia,
              firmaGerencia: firmaGerencia,
            ),
          ],
        ),
      ),
    );

    return doc.save();
  }

  Future<Uint8List> _generarPdfConsolidadoDesdeFilas({
    required String consolidado,
    required List<PpExcelFila> filas,
    required Uint8List logoBytes,
    String? empresaNombre,
    String? sheetTitle,
    String? nombreElaborado,
    String? cargoElaborado,
    String? firmaElaboradoUrl,
    String? firmaElaboradoPath,
    Uint8List? firmaElaboradoBlob,
    String? nombreAuditoria,
    String? cargoAuditoria,
    String? firmaAuditoriaUrl,
    String? firmaAuditoriaPath,
    Uint8List? firmaAuditoriaBlob,
    String? nombreGerencia,
    String? cargoGerencia,
    String? firmaGerenciaUrl,
    String? firmaGerenciaPath,
    Uint8List? firmaGerenciaBlob,
    PpEstado? estado,
  }) async {
    final doc = pw.Document();
    final logo = logoBytes.isNotEmpty ? pw.MemoryImage(logoBytes) : null;
    // Use Blob first (no Storage round-trip), fallback to URL/path.
    final firmaElaborado =
        firmaElaboradoBlob != null && firmaElaboradoBlob.isNotEmpty
        ? pw.MemoryImage(firmaElaboradoBlob)
        : await _loadPdfImage(url: firmaElaboradoUrl, path: firmaElaboradoPath);
    final firmaAuditoria =
        firmaAuditoriaBlob != null && firmaAuditoriaBlob.isNotEmpty
        ? pw.MemoryImage(firmaAuditoriaBlob)
        : await _loadPdfImage(url: firmaAuditoriaUrl, path: firmaAuditoriaPath);
    final firmaGerencia =
        firmaGerenciaBlob != null && firmaGerenciaBlob.isNotEmpty
        ? pw.MemoryImage(firmaGerenciaBlob)
        : await _loadPdfImage(url: firmaGerenciaUrl, path: firmaGerenciaPath);

    pw.Font? arial;
    try {
      final data = await rootBundle.load('assets/arial.ttf');
      arial = pw.Font.ttf(data);
    } catch (_) {}

    pw.TextStyle ts(double sz, {bool bold = false}) => pw.TextStyle(
      font: bold ? pw.Font.helveticaBold() : arial,
      fontSize: sz,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
    );

    final empresaTitulo =
        _cleanString(empresaNombre) ?? 'UNION TEMPORAL CAPITAL USPEC 2025';
    final esAlimentarCapital = sheetTitle != null && sheetTitle.isNotEmpty;
    final fechaDisplay = esAlimentarCapital
        ? _fechaDisplay(() {
            final n = DateTime.now();
            return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
          }())
        : _fechaDisplay(_firstNonEmptyDate(filas));
    const pagador = 'BBVA';
    final total = _sumarValores(filas);
    final totalFmt = _formatMontoPdf(total);
    final columns = _pdfColumnsForConsolidado(
      filas,
      esAlimentarCapital: esAlimentarCapital,
    );

    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: esAlimentarCapital
              ? PdfPageFormat.letter.landscape
              : PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.fromLTRB(10, 10, 10, 14),
          buildForeground: estado != null
              ? (_) => _buildEstadoBadge(estado)
              : null,
        ),
        build: (_) => [
          if (esAlimentarCapital)
            // Layout Alimentar Capital: logo izq, título centrado, info box der
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (logo != null)
                  pw.SizedBox(
                    width: 86,
                    height: 40,
                    child: pw.Image(logo, fit: pw.BoxFit.contain),
                  )
                else
                  pw.SizedBox(width: 86),
                pw.SizedBox(width: 8),
                pw.Expanded(
                  child: pw.Center(
                    child: pw.Text(
                      sheetTitle,
                      style: ts(13, bold: true),
                      textAlign: pw.TextAlign.center,
                    ),
                  ),
                ),
                pw.SizedBox(width: 8),
                pw.Table(
                  border: pw.TableBorder.all(width: 0.5),
                  columnWidths: {
                    0: const pw.FixedColumnWidth(60),
                    1: const pw.FixedColumnWidth(88),
                  },
                  children: [
                    _pdfInfoRow('N CONSECUTIVO', consolidado, ts),
                    _pdfInfoRow('Fecha', fechaDisplay, ts),
                    _pdfInfoRow('TOTAL', '\$$totalFmt', ts),
                  ],
                ),
              ],
            )
          else
            // Layout estándar
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (logo != null)
                  pw.SizedBox(
                    width: 86,
                    height: 34,
                    child: pw.Image(logo, fit: pw.BoxFit.contain),
                  ),
                pw.SizedBox(width: 8),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(empresaTitulo, style: ts(10, bold: true)),
                      pw.SizedBox(height: 1),
                      pw.Text('Seguimiento o Transferecias', style: ts(8)),
                    ],
                  ),
                ),
                pw.Table(
                  border: pw.TableBorder.all(width: 0.5),
                  columnWidths: {
                    0: const pw.FixedColumnWidth(46),
                    1: const pw.FixedColumnWidth(84),
                  },
                  children: [
                    _pdfInfoRow('N° Planilla', consolidado, ts),
                    _pdfInfoRow('Fecha', fechaDisplay, ts),
                    _pdfInfoRow('Pagador', pagador, ts),
                    _pdfInfoRow('Total', totalFmt, ts),
                  ],
                ),
              ],
            ),
          pw.SizedBox(height: 8),
          pw.Table(
            border: pw.TableBorder.all(width: 0.5),
            columnWidths: _pdfColumnWidths(
              columns,
              esAlimentarCapital: esAlimentarCapital,
            ),
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                children: columns.map((column) {
                  return pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 2,
                      vertical: 4,
                    ),
                    child: pw.Text(
                      _pdfColumnLabel(column),
                      style: ts(esAlimentarCapital ? 6.5 : 5.5, bold: true),
                      textAlign: pw.TextAlign.center,
                    ),
                  );
                }).toList(),
              ),
              ...filas.map((fila) {
                return pw.TableRow(
                  children: columns.map((column) {
                    final value = _pdfColumnValue(fila, column);
                    final isValor = column == 'valor_a_pagar';
                    final displayValue =
                        isValor && esAlimentarCapital && value.isNotEmpty
                        ? '\$ $value'
                        : value;
                    final alignRight = isValor;
                    return pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 2,
                        vertical: 3,
                      ),
                      child: pw.Text(
                        displayValue,
                        style: ts(
                          esAlimentarCapital ? 6.0 : 5.5,
                          bold: isValor,
                        ),
                        textAlign: alignRight
                            ? pw.TextAlign.right
                            : pw.TextAlign.center,
                      ),
                    );
                  }).toList(),
                );
              }),
            ],
          ),
          // Fila PAGO TOTAL fuera de la tabla para que "PAGO TOTAL" abarque todas las celdas
          if (esAlimentarCapital)
            pw.Container(
              decoration: const pw.BoxDecoration(
                color: PdfColors.grey200,
                border: pw.Border(
                  left: pw.BorderSide(width: 0.5),
                  right: pw.BorderSide(width: 0.5),
                  bottom: pw.BorderSide(width: 0.5),
                ),
              ),
              child: pw.Row(
                children: [
                  pw.Expanded(
                    child: pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 3,
                      ),
                      child: pw.Text(
                        'PAGO TOTAL',
                        style: ts(6.5, bold: true),
                        textAlign: pw.TextAlign.center,
                      ),
                    ),
                  ),
                  pw.Container(
                    width: 74,
                    decoration: const pw.BoxDecoration(
                      border: pw.Border(left: pw.BorderSide(width: 0.5)),
                    ),
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 2,
                      vertical: 3,
                    ),
                    child: pw.Text(
                      '\$ $totalFmt',
                      style: ts(6.5, bold: true),
                      textAlign: pw.TextAlign.right,
                    ),
                  ),
                ],
              ),
            ),
          pw.SizedBox(height: 12),
          _buildFooterFirmas(
            ts: ts,
            nombreElaborado: nombreElaborado,
            cargoElaborado: cargoElaborado,
            firmaElaborado: firmaElaborado,
            nombreAuditoria: nombreAuditoria,
            cargoAuditoria: cargoAuditoria,
            firmaAuditoria: firmaAuditoria,
            nombreGerencia: nombreGerencia,
            cargoGerencia: cargoGerencia,
            firmaGerencia: firmaGerencia,
          ),
        ],
      ),
    );

    return doc.save();
  }

  pw.TableRow _pdfInfoRow(
    String label,
    String value,
    pw.TextStyle Function(double, {bool bold}) ts,
  ) => pw.TableRow(
    children: [
      pw.Padding(
        padding: const pw.EdgeInsets.all(2),
        child: pw.Text(label, style: ts(6.5, bold: true)),
      ),
      pw.Padding(
        padding: const pw.EdgeInsets.all(2),
        child: pw.Text(value, style: ts(6.5)),
      ),
    ],
  );

  String _colLabel(String key) => key
      .split('_')
      .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');

  String _fechaDisplay(String? fecha) {
    if (fecha == null || fecha.isEmpty) return '';
    final parts = fecha.split('-');
    if (parts.length != 3) return fecha;
    const meses = [
      '',
      'enero',
      'febrero',
      'marzo',
      'abril',
      'mayo',
      'junio',
      'julio',
      'agosto',
      'septiembre',
      'octubre',
      'noviembre',
      'diciembre',
    ];
    final mes = int.tryParse(parts[1]) ?? 0;
    return '${parts[2]} de ${mes > 0 && mes <= 12 ? meses[mes] : parts[1]} de ${parts[0]}';
  }

  static const _utNombre = 'UNION TEMPORAL CAPITAL USPEC 2025';

  String _sanitizeFilePart(String s) =>
      s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '').trim();

  String _nombreEmpresaArchivo(String? empresaNombre) {
    final limpio = _sanitizeFilePart(_cleanString(empresaNombre) ?? '');
    return limpio.isEmpty ? _utNombre : limpio;
  }

  String _nombreArchivoFila(PpExcelFila fila, {String? empresaNombre}) {
    final consolidado = _sanitizeFilePart(
      fila.nombrePlanilla ?? 'planilla_${fila.rowIndex + 1}',
    );
    final detalle = _sanitizeFilePart(
      fila.extras['detalle'] ??
          fila.extras['no_factura_orden_de_compra'] ??
          fila.extras['observaciones'] ??
          '',
    );
    final parts = [
      'PL',
      consolidado,
      if (detalle.isNotEmpty) detalle,
      _nombreEmpresaArchivo(empresaNombre),
    ];
    return '${parts.join('-')}.pdf';
  }

  String _nombreArchivoConsolidado(
    String consolidado,
    List<PpExcelFila> filas, {
    String? empresaNombre,
  }) {
    final consolidadoClean = _sanitizeFilePart(
      consolidado.isEmpty ? 'consolidado' : consolidado,
    );
    final detalle = _sanitizeFilePart(
      _firstNonEmptyExtra(filas, const [
            'detalle',
            'no_factura_orden_de_compra',
            'observaciones',
          ]) ??
          '',
    );
    final parts = [
      'PL',
      consolidadoClean,
      if (detalle.isNotEmpty) detalle,
      _nombreEmpresaArchivo(empresaNombre),
    ];
    return '${parts.join('-')}.pdf';
  }

  String? _firstNonEmptyDate(List<PpExcelFila> filas) {
    for (final fila in filas) {
      if (fila.fecha != null && fila.fecha!.trim().isNotEmpty) {
        return fila.fecha;
      }
    }
    return null;
  }

  String? _firstNonEmptyExtra(List<PpExcelFila> filas, List<String> keys) {
    for (final fila in filas) {
      for (final key in keys) {
        final value = fila.extras[key]?.trim();
        if (value != null && value.isNotEmpty) return value;
      }
    }
    return null;
  }

  double _sumarValores(List<PpExcelFila> filas) {
    return filas.fold<double>(0, (total, fila) => total + (fila.valor ?? 0));
  }

  String _rangoFilasExcel(List<PpExcelFila> filas) {
    if (filas.isEmpty) return '';
    final ordered = filas.map((f) => f.excelRowNumber).toList()..sort();
    return ordered.first == ordered.last
        ? '${ordered.first}'
        : '${ordered.first}-${ordered.last}';
  }

  ({bool esConsolidado, List<PpExcelFila> filas})
  _resolverReemplazoObservadoDesdeExcel({
    required Map<String, dynamic> planillaData,
    required List<PpExcelFila> filasExcel,
  }) {
    final datosExcel = planillaData['datosExcel'];
    final datosMap = datosExcel is Map<String, dynamic>
        ? datosExcel
        : (datosExcel is Map
              ? Map<String, dynamic>.from(datosExcel)
              : const <String, dynamic>{});
    final tipoGeneracion = (datosMap['tipo_generacion'] ?? '')
        .toString()
        .trim();
    final esperaConsolidado =
        tipoGeneracion == 'excel_consolidado' ||
        (datosMap['consolidado'] ?? '').toString().trim().isNotEmpty ||
        datosMap['filas_rows'] is List;

    final targetNombre =
        (datosMap['consolidado'] ??
                planillaData['nombrePlanillaDetectado'] ??
                datosMap['nombre_planilla'] ??
                '')
            .toString()
            .trim();
    final targetFecha = (planillaData['fechaPlanillaDetectada'] ?? '')
        .toString()
        .trim();
    final targetValor = (planillaData['valorDetectado'] as num?)?.toDouble();
    final targetArchivo = (planillaData['nombreArchivoOriginal'] ?? '')
        .toString()
        .trim();

    if (esperaConsolidado) {
      final grupos = <String, List<PpExcelFila>>{};
      for (final fila in filasExcel) {
        final key = (fila.nombrePlanilla ?? '').trim();
        if (key.isEmpty) continue;
        grupos.putIfAbsent(key, () => <PpExcelFila>[]).add(fila);
      }

      if (targetNombre.isNotEmpty) {
        for (final entry in grupos.entries) {
          if (_normalizeLookup(entry.key) == _normalizeLookup(targetNombre)) {
            return (esConsolidado: true, filas: entry.value);
          }
        }
      }

      if (targetValor != null) {
        for (final entry in grupos.entries) {
          final total = _sumarValores(entry.value);
          final fecha = _firstNonEmptyDate(entry.value) ?? '';
          final sameValue = (total - targetValor).abs() < 1;
          final sameDate = targetFecha.isEmpty || fecha == targetFecha;
          if (sameValue && sameDate) {
            return (esConsolidado: true, filas: entry.value);
          }
        }
      }

      if (grupos.length == 1) {
        return (esConsolidado: true, filas: grupos.values.first);
      }

      throw const PpException(
        'No pude identificar en el Excel la planilla consolidada observada. '
        'Usa el mismo número o consolidado del documento, o corrígela subiendo PDF.',
      );
    }

    if (targetNombre.isNotEmpty) {
      for (final fila in filasExcel) {
        if (_normalizeLookup(fila.nombrePlanilla) ==
            _normalizeLookup(targetNombre)) {
          return (esConsolidado: false, filas: [fila]);
        }
      }
    }

    if (targetArchivo.isNotEmpty) {
      final targetArchivoNorm = _normalizeLookup(
        _basenameWithoutExtension(targetArchivo),
      );
      for (final fila in filasExcel) {
        final filaArchivo = fila.nombreArchivoPdf;
        if (_normalizeLookup(_basenameWithoutExtension(filaArchivo)) ==
            targetArchivoNorm) {
          return (esConsolidado: false, filas: [fila]);
        }
      }
    }

    if (targetValor != null || targetFecha.isNotEmpty) {
      for (final fila in filasExcel) {
        final sameValue =
            targetValor == null ||
            (fila.valor != null && (fila.valor! - targetValor).abs() < 1);
        final sameDate =
            targetFecha.isEmpty || ((fila.fecha ?? '').trim() == targetFecha);
        if (sameValue && sameDate) {
          return (esConsolidado: false, filas: [fila]);
        }
      }
    }

    if (filasExcel.length == 1) {
      return (esConsolidado: false, filas: [filasExcel.first]);
    }

    throw const PpException(
      'No pude identificar en el Excel la fila correcta para esta planilla observada. '
      'Usa el mismo número de planilla o vuelve a cargar el PDF corregido.',
    );
  }

  String _normalizeLookup(String? value) =>
      (value ?? '').toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  String _basenameWithoutExtension(String? value) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) return '';
    final parts = raw.split(RegExp(r'[\\/]'));
    final fileName = parts.isNotEmpty ? parts.last : raw;
    return fileName.replaceFirst(RegExp(r'\.[^.]+$'), '');
  }

  String _formatMontoPdf(double value) {
    final decimals = value.truncateToDouble() == value ? 0 : 2;
    return NumberFormat.currency(
      locale: 'es_CO',
      symbol: '',
      decimalDigits: decimals,
    ).format(value).trim();
  }

  List<String> _pdfColumnsForConsolidado(
    List<PpExcelFila> filas, {
    bool esAlimentarCapital = false,
  }) {
    if (esAlimentarCapital) {
      return [
        'no',
        'revisado',
        'nit',
        'dv',
        'proveedor',
        'no_factura_orden_de_compra',
        'no_cuenta',
        'cte',
        'aho',
        'banco',
        'valor_a_pagar',
      ];
    }

    const preferred = <String>[
      'fecha_programada',
      'fecha_banco',
      'planilla',
      'nit',
      'proveedor',
      'no_factura_orden_de_compra',
      'valor_a_pagar',
      'tipo_de_cuenta',
      'no_cuenta',
      'banco',
      'detalle',
      'pagador',
      'observaciones',
      'comentarios',
      'pagado_mafe',
      'contabilizado',
      'revisado_karen',
    ];
    return preferred.where((column) {
      if (column == 'planilla' || column == 'valor_a_pagar') return true;
      return filas.any((fila) => (fila.extras[column] ?? '').trim().isNotEmpty);
    }).toList();
  }

  Map<int, pw.TableColumnWidth> _pdfColumnWidths(
    List<String> columns, {
    bool esAlimentarCapital = false,
  }) {
    final widths = <int, pw.TableColumnWidth>{};
    for (var i = 0; i < columns.length; i++) {
      if (esAlimentarCapital) {
        switch (columns[i]) {
          case 'no':
            widths[i] = const pw.FixedColumnWidth(28);
          case 'revisado':
            widths[i] = const pw.FixedColumnWidth(44);
          case 'nit':
            widths[i] = const pw.FixedColumnWidth(64);
          case 'dv':
            widths[i] = const pw.FixedColumnWidth(16);
          case 'proveedor':
            widths[i] = const pw.FlexColumnWidth(1.0);
          case 'no_factura_orden_de_compra':
            widths[i] = const pw.FlexColumnWidth(1.5);
          case 'no_cuenta':
            widths[i] = const pw.FixedColumnWidth(72);
          case 'cte':
          case 'aho':
            widths[i] = const pw.FixedColumnWidth(22);
          case 'banco':
            widths[i] = const pw.FixedColumnWidth(58);
          case 'valor_a_pagar':
            widths[i] = const pw.FixedColumnWidth(74);
          default:
            widths[i] = const pw.FlexColumnWidth();
        }
      } else {
        switch (columns[i]) {
          case 'fecha_programada':
          case 'fecha_banco':
            widths[i] = const pw.FixedColumnWidth(48);
          case 'no':
          case 'planilla':
            widths[i] = const pw.FixedColumnWidth(22);
          case 'nit':
            widths[i] = const pw.FixedColumnWidth(48);
          case 'dv':
            widths[i] = const pw.FixedColumnWidth(12);
          case 'revisado':
            widths[i] = const pw.FixedColumnWidth(22);
          case 'cte':
          case 'aho':
            widths[i] = const pw.FixedColumnWidth(14);
          case 'valor_a_pagar':
            widths[i] = const pw.FixedColumnWidth(58);
          case 'tipo_de_cuenta':
            widths[i] = const pw.FixedColumnWidth(44);
          case 'no_cuenta':
            widths[i] = const pw.FixedColumnWidth(62);
          case 'banco':
            widths[i] = const pw.FixedColumnWidth(36);
          case 'pagado_mafe':
          case 'contabilizado':
          case 'revisado_karen':
            widths[i] = const pw.FixedColumnWidth(42);
          case 'proveedor':
            widths[i] = const pw.FixedColumnWidth(80);
          case 'detalle':
          case 'no_factura_orden_de_compra':
          case 'observaciones':
          case 'comentarios':
            widths[i] = const pw.FixedColumnWidth(86);
          case 'pagador':
            widths[i] = const pw.FixedColumnWidth(58);
          default:
            widths[i] = const pw.FlexColumnWidth();
        }
      }
    }
    return widths;
  }

  String _pdfColumnLabel(String column) => switch (column) {
    'fecha_programada' => 'Fecha programada',
    'fecha_banco' => 'Fecha banco',
    'no' => 'No',
    'planilla' => 'Planilla',
    'nit' => 'NIT',
    'dv' => 'DV',
    'revisado' => 'REVISADO',
    'cte' => 'CTE',
    'aho' => 'AHO',
    'proveedor' => 'PROVEEDOR',
    'no_factura_orden_de_compra' => 'N Factura /Orden de Compra',
    'valor_a_pagar' => 'VALOR A PAGAR',
    'tipo_de_cuenta' => 'Tipo de Cuenta',
    'no_cuenta' => 'N CUENTA',
    'banco' => 'BANCO',
    'detalle' => 'Detalle',
    'pagador' => 'Pagador',
    'observaciones' => 'Observaciones',
    'comentarios' => 'Comentarios',
    'pagado_mafe' => 'Pagado (Mafe)',
    'contabilizado' => 'Contabilizado',
    'revisado_karen' => 'Revisado (Karen)',
    _ => _colLabel(column),
  };

  String _pdfColumnValue(PpExcelFila fila, String column) {
    switch (column) {
      case 'fecha_programada':
      case 'fecha_banco':
        return _formatDateShort(
          column == 'fecha_programada' ? fila.fecha : fila.extras[column],
        );
      case 'no':
      case 'planilla':
        return fila.nombrePlanilla ?? '';
      case 'valor_a_pagar':
        return fila.valor == null ? '' : _formatMontoPdf(fila.valor!);
      default:
        return fila.extras[column] ?? '';
    }
  }

  String _formatDateShort(String? value) {
    if (value == null || value.trim().isEmpty) return '';
    final trimmed = value.trim();
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(trimmed);
    if (match != null) {
      return '${match.group(3)}/${match.group(2)}/${match.group(1)}';
    }
    return trimmed;
  }

  Future<
    ({
      String? nombre,
      String? cargo,
      String? urlFirma,
      String? pathFirma,
      Uint8List? firmaBlob,
    })
  >
  _getActorSnapshot(
    String actorId,
    String empresaId,
    String? fallbackNombre,
  ) async {
    try {
      final userSnap = await _users.doc(actorId).get();
      final data = userSnap.data();
      final scoped = _scopedData(data, empresaId);
      final nombreCompleto =
          ((scoped?['nombreCompleto'] ??
                      data?['nombreCompleto'] ??
                      scoped?['nombre'] ??
                      data?['nombre']) ??
                  '')
              .toString()
              .trim();
      final nombres = ((scoped?['nombres'] ?? data?['nombres']) ?? '')
          .toString()
          .trim();
      final apellidos = ((scoped?['apellidos'] ?? data?['apellidos']) ?? '')
          .toString()
          .trim();
      final fullName = '$nombres $apellidos'.trim();
      final cargo = ((scoped?['cargo'] ?? data?['cargo']) ?? '')
          .toString()
          .trim();
      final urlFirma = ((scoped?['urlFirma'] ?? data?['urlFirma']) ?? '')
          .toString()
          .trim();
      final pathFirma = ((scoped?['pathFirma'] ?? data?['pathFirma']) ?? '')
          .toString()
          .trim();

      // Read Blob stored directly in Firestore — primary read path on web.
      final blobRaw = scoped?['firmaBlob'] ?? data?['firmaBlob'];
      Uint8List? firmaBlob;
      if (blobRaw is Uint8List && blobRaw.isNotEmpty) {
        firmaBlob = blobRaw;
      } else if (blobRaw is List && blobRaw.isNotEmpty) {
        firmaBlob = Uint8List.fromList(blobRaw.cast<int>());
      }

      return (
        nombre: nombreCompleto.isNotEmpty
            ? nombreCompleto
            : (fullName.isNotEmpty ? fullName : fallbackNombre ?? actorId),
        cargo: cargo.isEmpty ? null : cargo,
        urlFirma: urlFirma.isEmpty ? null : urlFirma,
        pathFirma: pathFirma.isEmpty ? null : pathFirma,
        firmaBlob: firmaBlob,
      );
    } catch (_) {
      return (
        nombre: fallbackNombre ?? actorId,
        cargo: null,
        urlFirma: null,
        pathFirma: null,
        firmaBlob: null,
      );
    }
  }

  Future<pw.MemoryImage?> _loadPdfImage({String? url, String? path}) async {
    final bytes = await _loadBinary(url: url, path: path);
    if (bytes == null || bytes.isEmpty) return null;
    return pw.MemoryImage(bytes);
  }

  Future<Uint8List?> _loadBinary({String? url, String? path}) async {
    final safePath = _normalizeStoragePath(path) ?? _normalizeStoragePath(url);
    final safeUrl = _normalizeStorageUrl(url) ?? _normalizeStorageUrl(path);

    if (safePath != null) {
      // Priority 1: Storage SDK getData() — works on web for authenticated users
      // without CORS issues (uses Firebase SDK channel, not browser fetch).
      try {
        final bytes = await _storage
            .ref(safePath)
            .getData(_maxStorageDownloadBytes);
        if (bytes != null && bytes.isNotEmpty) return bytes;
      } catch (e) {
        debugPrint('[PpService] _loadBinary.getData error: $e');
      }

      // Priority 2: fresh download URL using platform-specific loader.
      try {
        final freshUrl = await _storage.ref(safePath).getDownloadURL();
        final bytes = await loadBinaryFromUrl(freshUrl);
        if (bytes != null && bytes.isNotEmpty) {
          return bytes;
        }
      } catch (e) {
        debugPrint('[PpService] _loadBinary.freshUrl error: $e');
      }
    }

    // Priority 3: stored URL as last resort.
    if (safeUrl != null) {
      try {
        final bytes = await _storage
            .refFromURL(safeUrl)
            .getData(_maxStorageDownloadBytes);
        if (bytes != null && bytes.isNotEmpty) {
          return bytes;
        }
      } catch (e) {
        debugPrint('[PpService] _loadBinary.refFromURL error: $e');
      }

      try {
        final bytes = await loadBinaryFromUrl(safeUrl);
        if (bytes != null && bytes.isNotEmpty) {
          return bytes;
        }
      } catch (e) {
        debugPrint('[PpService] _loadBinary.storedUrl error: $e');
      }
    }

    return null;
  }

  Future<Uint8List?> _regenerarPdfExcelConFirmas({
    required String planillaId,
    required String empresaId,
    required String loteId,
    required Map<String, dynamic> planillaData,
    ({
      String? nombre,
      String? cargo,
      String? urlFirma,
      String? pathFirma,
      Uint8List? firmaBlob,
    })?
    auditorSnapshot,
    ({
      String? nombre,
      String? cargo,
      String? urlFirma,
      String? pathFirma,
      Uint8List? firmaBlob,
    })?
    gerenciaSnapshot,
  }) async {
    final datosExcel = planillaData['datosExcel'];
    if (datosExcel is! Map) return null;
    final tipoGeneracion = (datosExcel['tipo_generacion'] ?? '')
        .toString()
        .trim();
    if (tipoGeneracion != 'excel_consolidado' &&
        tipoGeneracion != 'excel_generado') {
      return null;
    }

    // Try loading logo from stored datosExcel paths first (avoids re-downloading
    // when the signing user might not have Storage access to the config).
    Uint8List logoBytes = Uint8List(0);
    final storedLogoPath = _cleanString(datosExcel['logo_path']);
    final storedLogoUrl = _normalizeStorageUrl(
      datosExcel['logo_url'] as String?,
    );
    if ((storedLogoPath?.isNotEmpty ?? false) ||
        (storedLogoUrl?.isNotEmpty ?? false)) {
      logoBytes =
          await _loadBinary(url: storedLogoUrl, path: storedLogoPath) ??
          Uint8List(0);
    }
    if (logoBytes.isEmpty) {
      logoBytes = await _cargarLogoEmpresa(empresaId);
    }
    final empresaNombrePlanilla = await _resolverNombreEmpresaPlanilla(
      empresaId: empresaId,
      planillaData: planillaData,
    );

    final cargadoPor = (planillaData['cargadoPor'] ?? '').toString();
    final cargadorSnapshot = await _getActorSnapshot(
      cargadoPor,
      empresaId,
      planillaData['nombreCargado'] as String?,
    );

    if (tipoGeneracion == 'excel_consolidado') {
      // Priority: use filas stored in Firestore (no Storage read needed on web).
      final filasRaw = datosExcel['filas_rows'];
      List<PpExcelFila>? filas;
      if (filasRaw is List && filasRaw.isNotEmpty) {
        filas = filasRaw
            .whereType<Map>()
            .map((m) => PpExcelFila.fromMap(Map<String, dynamic>.from(m)))
            .toList();
      }

      // Fallback: load Excel from Storage and parse.
      if (filas == null || filas.isEmpty) {
        final loteSnap = await _lotes.doc(loteId).get();
        final loteData = loteSnap.data();
        if (loteData == null) return null;
        final excelBytes = await _loadBinary(
          url: loteData['excelUrl'] as String?,
          path: loteData['excelPath'] as String?,
        );
        if (excelBytes == null || excelBytes.isEmpty) return null;
        final parse = _excelParser.parse(excelBytes);
        if (!parse.exitoso || parse.filas.isEmpty) return null;

        final metadatos = planillaData['metadatosExtraccion'];
        final excelRows = metadatos is Map && metadatos['excelRows'] is List
            ? (metadatos['excelRows'] as List)
                  .map((e) => int.tryParse(e.toString()))
                  .whereType<int>()
                  .toSet()
            : <int>{};

        filas = excelRows.isNotEmpty
            ? parse.filas
                  .where((f) => excelRows.contains(f.excelRowNumber))
                  .toList()
            : parse.filas.where((f) {
                final c = (f.nombrePlanilla ?? f.extras['consolidado'] ?? '')
                    .trim();
                return c ==
                    ((datosExcel['consolidado'] ??
                                planillaData['nombrePlanillaDetectado']) ??
                            '')
                        .toString()
                        .trim();
              }).toList();
      }

      if (filas.isEmpty) return null;

      return _generarPdfConsolidadoDesdeFilas(
        consolidado:
            ((datosExcel['consolidado'] ??
                        planillaData['nombrePlanillaDetectado']) ??
                    '')
                .toString(),
        filas: filas,
        logoBytes: logoBytes,
        empresaNombre: empresaNombrePlanilla,
        sheetTitle: datosExcel['sheet_title'] as String?,
        nombreElaborado: cargadorSnapshot.nombre,
        cargoElaborado: cargadorSnapshot.cargo,
        firmaElaboradoUrl: cargadorSnapshot.urlFirma,
        firmaElaboradoPath: cargadorSnapshot.pathFirma,
        firmaElaboradoBlob: cargadorSnapshot.firmaBlob,
        nombreAuditoria: auditorSnapshot?.nombre,
        cargoAuditoria: auditorSnapshot?.cargo,
        firmaAuditoriaUrl: auditorSnapshot?.urlFirma,
        firmaAuditoriaPath: auditorSnapshot?.pathFirma,
        firmaAuditoriaBlob: auditorSnapshot?.firmaBlob,
        nombreGerencia: gerenciaSnapshot?.nombre,
        cargoGerencia: gerenciaSnapshot?.cargo,
        firmaGerenciaUrl: gerenciaSnapshot?.urlFirma,
        firmaGerenciaPath: gerenciaSnapshot?.pathFirma,
        firmaGerenciaBlob: gerenciaSnapshot?.firmaBlob,
        estado: gerenciaSnapshot != null
            ? PpEstado.firmada
            : PpEstado.aprobada_auditoria,
      );
    }

    // excel_generado: single row.
    // Priority: use fila stored in Firestore.
    PpExcelFila? fila;
    final filaRaw = datosExcel['fila_row'];
    if (filaRaw is Map) {
      fila = PpExcelFila.fromMap(Map<String, dynamic>.from(filaRaw));
    }

    // Fallback: load Excel from Storage.
    if (fila == null) {
      final loteSnap = await _lotes.doc(loteId).get();
      final loteData = loteSnap.data();
      if (loteData != null) {
        final excelBytes = await _loadBinary(
          url: loteData['excelUrl'] as String?,
          path: loteData['excelPath'] as String?,
        );
        if (excelBytes != null && excelBytes.isNotEmpty) {
          final parse = _excelParser.parse(excelBytes);
          if (parse.exitoso) {
            final excelRowIndex = planillaData['excelRowIndex'] as int?;
            for (final item in parse.filas) {
              if (item.rowIndex == excelRowIndex) {
                fila = item;
                break;
              }
            }
          }
        }
      }
    }

    if (fila == null) return null;
    return _generarPdfDesdeFila(
      fila: fila,
      logoBytes: logoBytes,
      empresaNombre: empresaNombrePlanilla,
      nombreElaborado: cargadorSnapshot.nombre,
      cargoElaborado: cargadorSnapshot.cargo,
      firmaElaboradoUrl: cargadorSnapshot.urlFirma,
      firmaElaboradoPath: cargadorSnapshot.pathFirma,
      firmaElaboradoBlob: cargadorSnapshot.firmaBlob,
      nombreAuditoria: auditorSnapshot?.nombre,
      cargoAuditoria: auditorSnapshot?.cargo,
      firmaAuditoriaUrl: auditorSnapshot?.urlFirma,
      firmaAuditoriaPath: auditorSnapshot?.pathFirma,
      firmaAuditoriaBlob: auditorSnapshot?.firmaBlob,
      nombreGerencia: gerenciaSnapshot?.nombre,
      cargoGerencia: gerenciaSnapshot?.cargo,
      firmaGerenciaUrl: gerenciaSnapshot?.urlFirma,
      firmaGerenciaPath: gerenciaSnapshot?.pathFirma,
      firmaGerenciaBlob: gerenciaSnapshot?.firmaBlob,
      estado: gerenciaSnapshot != null
          ? PpEstado.firmada
          : PpEstado.aprobada_auditoria,
    );
  }

  Uint8List? _coerceBinary(dynamic raw) {
    if (raw is Uint8List && raw.isNotEmpty) return raw;
    if (raw is Blob && raw.bytes.isNotEmpty) return raw.bytes;
    if (raw is List && raw.isNotEmpty) {
      return Uint8List.fromList(raw.cast<int>());
    }
    return null;
  }

  List<_PdfStampBlock> _buildBlocksForStampedPdf({
    required Map<String, dynamic> planillaData,
    ({
      String? nombre,
      String? cargo,
      String? urlFirma,
      String? pathFirma,
      Uint8List? firmaBlob,
    })?
    auditorSnapshot,
    ({
      String? nombre,
      String? cargo,
      String? urlFirma,
      String? pathFirma,
      Uint8List? firmaBlob,
    })?
    gerenciaSnapshot,
  }) {
    final cargadoBlob = _coerceBinary(planillaData['firmaCargadoBlob']);
    final auditorBlob =
        auditorSnapshot?.firmaBlob ??
        _coerceBinary(planillaData['firmaAuditoriaBlob']);
    final gerenciaBlob =
        gerenciaSnapshot?.firmaBlob ??
        _coerceBinary(planillaData['firmaGerenciaBlob']);

    final blocks = <_PdfStampBlock>[
      _PdfStampBlock(
        titulo: 'ELABORADO',
        color: PdfColors.orange700,
        firmaBytes: cargadoBlob,
        nombre: (planillaData['nombreCargado'] ?? '').toString().trim(),
        cargo: (planillaData['cargoCargado'] ?? '').toString().trim(),
      ),
    ];

    if (auditorSnapshot != null) {
      blocks.add(
        _PdfStampBlock(
          titulo: 'APROBADO - AUDITORIA',
          color: PdfColors.blue700,
          firmaBytes: auditorBlob,
          nombre:
              (auditorSnapshot.nombre ??
                      planillaData['nombreAuditorFirmante']?.toString())
                  ?.trim(),
          cargo:
              (auditorSnapshot.cargo ??
                      planillaData['cargoAuditorFirmante']?.toString())
                  ?.trim(),
          fecha: DateFormat('dd/MM/yyyy').format(DateTime.now()),
        ),
      );
    } else if (((planillaData['nombreAuditorFirmante'] ?? '').toString().trim())
        .isNotEmpty) {
      blocks.add(
        _PdfStampBlock(
          titulo: 'APROBADO - AUDITORIA',
          color: PdfColors.blue700,
          firmaBytes: auditorBlob,
          nombre: planillaData['nombreAuditorFirmante']?.toString().trim(),
          cargo: planillaData['cargoAuditorFirmante']?.toString().trim(),
        ),
      );
    }

    if (gerenciaSnapshot != null) {
      blocks.add(
        _PdfStampBlock(
          titulo: 'APROBADO PARA PAGO - GERENCIA',
          color: PdfColors.green700,
          firmaBytes: gerenciaBlob,
          nombre:
              (gerenciaSnapshot.nombre ??
                      planillaData['nombreFirmante']?.toString())
                  ?.trim(),
          cargo:
              (gerenciaSnapshot.cargo ??
                      planillaData['cargoFirmante']?.toString())
                  ?.trim(),
          fecha: DateFormat('dd/MM/yyyy').format(DateTime.now()),
        ),
      );
    } else if (((planillaData['nombreFirmante'] ?? '').toString().trim())
        .isNotEmpty) {
      blocks.add(
        _PdfStampBlock(
          titulo: 'APROBADO PARA PAGO - GERENCIA',
          color: PdfColors.green700,
          firmaBytes: gerenciaBlob,
          nombre: planillaData['nombreFirmante']?.toString().trim(),
          cargo: planillaData['cargoFirmante']?.toString().trim(),
        ),
      );
    }

    return blocks;
  }

  String _colorToHex(PdfColor color) {
    int toChannel(double value) {
      final normalized = value.clamp(0, 1).toDouble();
      return (normalized * 255).round().clamp(0, 255);
    }

    final r = toChannel(color.red).toRadixString(16).padLeft(2, '0');
    final g = toChannel(color.green).toRadixString(16).padLeft(2, '0');
    final b = toChannel(color.blue).toRadixString(16).padLeft(2, '0');
    return '#$r$g$b'.toUpperCase();
  }

  List<Map<String, dynamic>> _buildDirectPdfBlocksPayload(
    List<_PdfStampBlock> blocks, {
    required Map<String, dynamic> planillaData,
    ({
      String? nombre,
      String? cargo,
      String? urlFirma,
      String? pathFirma,
      Uint8List? firmaBlob,
    })?
    auditorSnapshot,
    ({
      String? nombre,
      String? cargo,
      String? urlFirma,
      String? pathFirma,
      Uint8List? firmaBlob,
    })?
    gerenciaSnapshot,
  }) {
    final payload = <Map<String, dynamic>>[];

    for (final block in blocks) {
      String? firmaPath;
      String? firmaUrl;
      if (block.titulo == 'ELABORADO') {
        firmaPath = planillaData['pathFirmaCargado'] as String?;
        firmaUrl = planillaData['urlFirmaCargado'] as String?;
      } else if (block.titulo == 'APROBADO - AUDITORIA') {
        firmaPath =
            auditorSnapshot?.pathFirma ??
            planillaData['pathFirmaAuditoria'] as String?;
        firmaUrl =
            auditorSnapshot?.urlFirma ??
            planillaData['urlFirmaAuditoria'] as String?;
      } else if (block.titulo == 'APROBADO PARA PAGO - GERENCIA') {
        firmaPath =
            gerenciaSnapshot?.pathFirma ??
            planillaData['pathFirmaUsada'] as String?;
        firmaUrl =
            gerenciaSnapshot?.urlFirma ??
            planillaData['urlFirmaUsada'] as String?;
      }

      payload.add({
        'titulo': block.titulo,
        'colorHex': _colorToHex(block.color),
        'nombre': block.nombre,
        'cargo': block.cargo,
        'fecha': block.fecha,
        'firmaPath': firmaPath,
        'firmaUrl': firmaUrl,
      });
    }

    return payload;
  }

  Future<(String, String)?> _sellarPdfDirectoEnBackend({
    required String planillaId,
    required String empresaId,
    required PpEstado estado,
    required String? sourcePdfUrl,
    required String? sourcePdfPath,
    required List<Map<String, dynamic>> bloques,
  }) async {
    try {
      final callable = _functions.httpsCallable('ppStampDirectPdf');
      final response = await callable.call({
        'planillaId': planillaId,
        'empresaId': empresaId,
        'estado': estado.valor,
        'sourcePdfUrl': sourcePdfUrl,
        'sourcePdfPath': sourcePdfPath,
        'bloques': bloques,
      });
      final data = Map<String, dynamic>.from(response.data as Map);
      final path = (data['pathPdf'] ?? '').toString().trim();
      if (path.isEmpty) return null;
      final url = await _storage.ref(path).getDownloadURL();
      return (url, path);
    } catch (e) {
      debugPrint('[PpService] Sellado backend PDF directo falló: $e');
      return null;
    }
  }

  // Small status badge in the bottom-right corner of each PDF page.
  pw.Widget _buildEstadoBadge(PpEstado estado) {
    return pw.Align(
      alignment: pw.Alignment.bottomRight,
      child: pw.Padding(
        padding: const pw.EdgeInsets.all(10),
        child: pw.SizedBox(
          width: 36,
          height: 36,
          child: pw.CustomPaint(
            size: const PdfPoint(36, 36),
            painter: (canvas, size) => _paintEstadoIcon(canvas, size, estado),
          ),
        ),
      ),
    );
  }

  // Draws a colored circle with a state icon. PDF canvas: y=0 at bottom-left.
  void _paintEstadoIcon(PdfGraphics canvas, PdfPoint size, PpEstado estado) {
    final r = size.x / 2;
    final cx = r;
    final cy = r; // center: (r, r) from bottom-left

    final bgColor = switch (estado) {
      PpEstado.firmada => const PdfColor(0.15, 0.55, 0.15),
      PpEstado.aprobada_auditoria => const PdfColor(0.10, 0.40, 0.72),
      PpEstado.rechazada => const PdfColor(0.72, 0.12, 0.12),
      PpEstado.anulada => const PdfColor(0.45, 0.45, 0.45),
      PpEstado.cargada => const PdfColor(0.30, 0.50, 0.60),
      PpEstado.observada => const PdfColor(0.50, 0.15, 0.62),
      _ => const PdfColor(0.76, 0.50, 0.10),
    };
    canvas.setFillColor(bgColor);
    canvas.drawEllipse(cx, cy, r * 0.96, r * 0.96);
    canvas.fillPath();

    canvas.setStrokeColor(PdfColors.white);
    canvas.setLineWidth(2.2);

    switch (estado) {
      case PpEstado.firmada:
      case PpEstado.aprobada_auditoria:
        // ✓ checkmark (PDF: y=0 at bottom, high y = upper part)
        canvas.moveTo(cx - r * 0.50, cy + r * 0.05);
        canvas.lineTo(cx - r * 0.10, cy - r * 0.30);
        canvas.lineTo(cx + r * 0.52, cy + r * 0.38);
        canvas.strokePath();
      case PpEstado.rechazada:
      case PpEstado.anulada:
        // ✕ cross
        canvas.moveTo(cx - r * 0.38, cy - r * 0.38);
        canvas.lineTo(cx + r * 0.38, cy + r * 0.38);
        canvas.strokePath();
        canvas.moveTo(cx + r * 0.38, cy - r * 0.38);
        canvas.lineTo(cx - r * 0.38, cy + r * 0.38);
        canvas.strokePath();
      case PpEstado.cargada:
        // ↑ upload arrow (tip at high y = top of circle)
        canvas.moveTo(cx, cy + r * 0.42);
        canvas.lineTo(cx - r * 0.32, cy + r * 0.08);
        canvas.moveTo(cx, cy + r * 0.42);
        canvas.lineTo(cx + r * 0.32, cy + r * 0.08);
        canvas.strokePath();
        canvas.moveTo(cx, cy + r * 0.42);
        canvas.lineTo(cx, cy - r * 0.38);
        canvas.strokePath();
      default:
        // ⏳ hourglass (two triangles sharing center)
        canvas.moveTo(cx - r * 0.40, cy + r * 0.44);
        canvas.lineTo(cx + r * 0.40, cy + r * 0.44);
        canvas.lineTo(cx, cy);
        canvas.lineTo(cx - r * 0.40, cy + r * 0.44);
        canvas.strokePath();
        canvas.moveTo(cx - r * 0.40, cy - r * 0.44);
        canvas.lineTo(cx + r * 0.40, cy - r * 0.44);
        canvas.lineTo(cx, cy);
        canvas.lineTo(cx - r * 0.40, cy - r * 0.44);
        canvas.strokePath();
    }
  }

  pw.Widget _buildElaboradoBlock({
    required String? nombre,
    required String? cargo,
    required pw.MemoryImage? firma,
    required pw.TextStyle Function(double, {bool bold}) ts,
  }) {
    return _buildFirmaEstadoBlock(
      titulo: 'ELABORADO',
      nombre: nombre,
      cargo: cargo,
      firma: firma,
      ts: ts,
      color: PdfColors.orange700,
    );
  }

  pw.Widget _buildFooterFirmas({
    required pw.TextStyle Function(double, {bool bold}) ts,
    String? nombreElaborado,
    String? cargoElaborado,
    pw.MemoryImage? firmaElaborado,
    String? nombreAuditoria,
    String? cargoAuditoria,
    pw.MemoryImage? firmaAuditoria,
    String? nombreGerencia,
    String? cargoGerencia,
    pw.MemoryImage? firmaGerencia,
  }) {
    final widgets = <pw.Widget>[
      pw.Expanded(
        child: _buildElaboradoBlock(
          nombre: nombreElaborado,
          cargo: cargoElaborado,
          firma: firmaElaborado,
          ts: ts,
        ),
      ),
    ];

    if (firmaAuditoria != null ||
        (nombreAuditoria ?? '').trim().isNotEmpty ||
        (cargoAuditoria ?? '').trim().isNotEmpty) {
      widgets.add(pw.SizedBox(width: 18));
      widgets.add(
        pw.Expanded(
          child: _buildFirmaEstadoBlock(
            titulo: 'Aprobado auditoría:',
            nombre: nombreAuditoria,
            cargo: cargoAuditoria,
            firma: firmaAuditoria,
            ts: ts,
            color: PdfColors.blue700,
          ),
        ),
      );
    }

    if (firmaGerencia != null ||
        (nombreGerencia ?? '').trim().isNotEmpty ||
        (cargoGerencia ?? '').trim().isNotEmpty) {
      widgets.add(pw.SizedBox(width: 18));
      widgets.add(
        pw.Expanded(
          child: _buildFirmaEstadoBlock(
            titulo: 'APROBADO PARA PAGO - GERENCIA',
            nombre: nombreGerencia,
            cargo: cargoGerencia,
            firma: firmaGerencia,
            ts: ts,
            color: PdfColors.green700,
          ),
        ),
      );
    }

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: widgets,
    );
  }

  pw.Widget _buildFirmaEstadoBlock({
    required String titulo,
    required String? nombre,
    required String? cargo,
    required pw.MemoryImage? firma,
    required pw.TextStyle Function(double, {bool bold}) ts,
    required PdfColor color,
  }) {
    final safeNombre = (nombre ?? '').trim();
    final safeCargo = (cargo ?? '').trim();
    final rawTitulo = titulo.trim();
    final normalizedTitle = rawTitulo.toLowerCase().contains('auditor')
        ? 'APROBADO - AUDITORIA'
        : rawTitulo.toLowerCase().contains('gerencia')
        ? 'APROBADO PARA PAGO - GERENCIA'
        : rawTitulo.toUpperCase();

    return pw.Container(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Text(
            normalizedTitle,
            style: ts(7, bold: true).copyWith(color: color),
            textAlign: pw.TextAlign.center,
          ),
          pw.SizedBox(height: 3),
          if (firma != null)
            pw.Image(firma, width: 80, height: 40, fit: pw.BoxFit.contain)
          else
            pw.SizedBox(height: 14),
          pw.SizedBox(height: 3),
          if (safeNombre.isNotEmpty)
            pw.Text(
              safeNombre,
              style: ts(6.5, bold: true),
              textAlign: pw.TextAlign.center,
            ),
          if (safeCargo.isNotEmpty)
            pw.Text(safeCargo, style: ts(6), textAlign: pw.TextAlign.center),
        ],
      ),
    );
  }

  Future<void> _actualizarContadorLote(String loteId, String empresaId) async {
    // PDFs subidos directamente no tienen lote; omitir actualización.
    if (loteId.isEmpty) return;

    final snap = await _planillas.where('loteId', isEqualTo: loteId).get();
    final todas = snap.docs.map((d) => d.data()['estado'].toString()).toList();
    final firmadas = todas.where((s) => s == PpEstado.firmada.valor).length;
    final rechazadas = todas.where((s) => s == PpEstado.rechazada.valor).length;
    final completado =
        (firmadas + rechazadas) == todas.length && todas.isNotEmpty;

    await _lotes.doc(loteId).update({
      'planillasFirmadas': firmadas,
      'planillasRechazadas': rechazadas,
      'estado': completado
          ? PpLoteEstado.completado.valor
          : PpLoteEstado.en_proceso.valor,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _notificar({
    required String empresaId,
    required String planillaId,
    required List<String> rolesDestino,
    required String titulo,
    required String descripcion,
    required String actorId,
    String? nombreActor,
  }) async {
    try {
      // Buscar usuarios con los roles destino en esta empresa
      for (final rol in rolesDestino) {
        // Query por rolPlanillas scoped o global
        final snaps = await Future.wait([
          _db
              .collection('TBL_USUARIOS')
              .where('empresasDetalle.$empresaId.rolPlanillas', isEqualTo: rol)
              .get(),
          _db
              .collection('TBL_USUARIOS')
              .where('rolPlanillas', isEqualTo: rol)
              .get(),
        ]);

        final ids = <String>{};
        for (final snap in snaps) {
          for (final doc in snap.docs) {
            // Quien ya salió de la empresa conserva el rol en su ficha pero no
            // debe seguir recibiendo planillas.
            if (!isPersonaActivaEnEmpresa(doc.data(), empresaId)) continue;
            ids.add(doc.id);
          }
        }

        for (final userId in ids) {
          if (userId == actorId) continue;
          await _taskService.pushNotification(
            toUserId: userId,
            title: titulo,
            description: descripcion,
            taskId: planillaId,
            type: 'planillas_pago',
            fromId: actorId,
            fromName: nombreActor ?? '',
            empresaId: empresaId,
          );
        }
      }
    } catch (e) {
      debugPrint('[PpService] Error al notificar: $e');
    }
  }

  void _validarRol(String accion, String rolPlanillas) {
    if (!PpRoles.puedeEjecutar(accion, rolPlanillas)) {
      throw PpException(
        'El rol "$rolPlanillas" no tiene permiso para ejecutar "$accion".',
      );
    }
  }

  Map<String, dynamic>? _scopedData(
    Map<String, dynamic>? data,
    String empresaId,
  ) {
    if (data == null) return null;
    final detalleRaw = data['empresasDetalle'];
    if (detalleRaw is! Map) return null;
    final rawScoped = detalleRaw[empresaId];
    if (rawScoped is Map<String, dynamic>) return rawScoped;
    if (rawScoped is Map) {
      return rawScoped.map((k, v) => MapEntry(k.toString(), v));
    }
    return null;
  }
}
