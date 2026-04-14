// lib/gestion_documental/gd_service.dart
//
// Servicio principal del módulo Gestión Documental.
//
// Colecciones:
//   TBL_DOCUMENTOS            — documento maestro por empresa
//   TBL_DOCUMENTOS_VERSIONES  — versiones de cada documento
//   TBL_DOCUMENTOS_FLUJO      — historial append-only de eventos
//   TBL_FIRMAS_USUARIOS       — perfil de firma interna por usuario+empresa
//
// Storage paths:
//   documentos/{empresaId}/{docId}/v{num}/{ts}_{nombre}.pdf
//   firmas_doc/{empresaId}/{userId}/firma.png
//
// Reglas de transición de estado:
//   borrador     → en_revision   (enviar a revisión)
//   en_revision  → observado     (observar con comentario)
//   en_revision  → aprobado      (aprobar formalmente)
//   observado    → en_revision   (reenviar tras corrección)
//   aprobado     → firmado       (firmar internamente)
//   firmado      → vigente       (marcar vigente — SOLO UNA por documento)
//   vigente      → obsoleto      (automático al marcar nueva vigente)
//
// Regla fuerte: solo una versión puede tener esVigente=true por documento.

import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart'; // Importado para FilePicker
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import 'gd_models.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Excepción de negocio del módulo
// ─────────────────────────────────────────────────────────────────────────────

class GdException implements Exception {
  final String mensaje;
  const GdException(this.mensaje);
  @override
  String toString() => 'GdException: $mensaje';
}

// ─────────────────────────────────────────────────────────────────────────────
// Transiciones válidas
// ─────────────────────────────────────────────────────────────────────────────

const Map<GdEstado, Set<GdEstado>> _kTransicionesValidas = {
  GdEstado.borrador:    {GdEstado.en_revision},
  GdEstado.en_revision: {GdEstado.observado, GdEstado.aprobado},
  GdEstado.observado:   {GdEstado.en_revision},
  GdEstado.aprobado:    {GdEstado.firmado},
  GdEstado.firmado:     {GdEstado.vigente},
  GdEstado.vigente:     {GdEstado.obsoleto},
  GdEstado.obsoleto:    {},
};

// ─────────────────────────────────────────────────────────────────────────────
// Servicio
// ─────────────────────────────────────────────────────────────────────────────

class GdService {
  static const String _colDocumentos = 'TBL_DOCUMENTOS';
  static const String _colVersiones  = 'TBL_DOCUMENTOS_VERSIONES';
  static const String _colFlujo      = 'TBL_DOCUMENTOS_FLUJO';
  static const String _colFirmas     = 'TBL_FIRMAS_USUARIOS';

  final FirebaseFirestore _db;
  final FirebaseStorage _storage;

  GdService({FirebaseFirestore? db, FirebaseStorage? storage})
      : _db = db ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance;

  // ── Colecciones ─────────────────────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> get _docCol => _db.collection(_colDocumentos);
  CollectionReference<Map<String, dynamic>> get _verCol => _db.collection(_colVersiones);
  CollectionReference<Map<String, dynamic>> get _flujoCol => _db.collection(_colFlujo);
  CollectionReference<Map<String, dynamic>> get _firmasCol => _db.collection(_colFirmas);

  // ─────────────────────────────────────────────────────────────────────────
  // CREAR DOCUMENTO + PRIMERA VERSIÓN
  // ─────────────────────────────────────────────────────────────────────────

  /// Crea el documento maestro y la versión inicial (v1) en borrador.
  /// Opcionalmente sube el PDF si se proveen [pdfBytes] y [pdfNombre].
  /// Retorna el [docId] del documento creado.
  Future<String> crearDocumento({
    required String empresaId,
    required String titulo,
    required String codigo,
    required String actorId,      // userId del redactor
    required String rolDocumental,
    String? descripcion,
    String? categoria,
    String? area,
    String? nombreActor,
    // PDF opcional en la creación (puede subirse después)
    Uint8List? pdfBytes,
    String? pdfNombre,
  }) async {
    _validarRol('subir_pdf', rolDocumental);

    final docRef = _docCol.doc();
    final docId = docRef.id;
    final verRef = _verCol.doc();
    final versionId = verRef.id;
    final now = FieldValue.serverTimestamp();

    // Subir PDF si se proveyó
    String? urlPdf;
    String? pathPdf;
    if (pdfBytes != null && pdfNombre != null) {
      final result = await _subirPdfBytes(
        empresaId: empresaId,
        docId: docId,
        numero: 1,
        bytes: pdfBytes,
        nombre: pdfNombre,
      );
      urlPdf = result.$1;
      pathPdf = result.$2;
    }

    final batch = _db.batch();

    // Documento maestro
    batch.set(docRef, {
      'empresaId': empresaId,
      'codigo': codigo.trim(),
      'titulo': titulo.trim(),
      'descripcion': descripcion,
      'categoria': categoria,
      'area': area,
      'versionActual': 'v1',
      'estado': GdEstado.borrador.valor,
      'versionVigenteId': null,
      'creadoPor': actorId,
      'createdAt': now,
      'updatedAt': now,
      'revisadoPor': null,
      'aprobadoPor': null,
      'firmadoPor': null,
    });

    // Versión 1
    batch.set(verRef, {
      'docId': docId,
      'empresaId': empresaId,
      'numero': 1,
      'etiqueta': 'v1',
      'estado': GdEstado.borrador.valor,
      'urlPdf': urlPdf,
      'pathPdf': pathPdf,
      'nombreArchivo': pdfNombre,
      'subidoPor': actorId,
      'subidoEn': now,
      'revisadoPor': null,
      'revisadoEn': null,
      'aprobadoPor': null,
      'aprobadoEn': null,
      'firmadoPor': null,
      'firmadoEn': null,
      'urlFirmaUsada': null,
      'nombreFirmante': null,
      'observacion': null,
      'esVigente': false,
    });

    await batch.commit();

    // Historial: creado
    await _registrarEvento(
      docId: docId,
      versionId: versionId,
      empresaId: empresaId,
      accion: GdAccion.creado,
      actorId: actorId,
      nombreActor: nombreActor,
      metadatos: {'codigo': codigo, 'titulo': titulo},
    );

    // Historial: pdf_subido (si aplica)
    if (urlPdf != null) {
      await _registrarEvento(
        docId: docId,
        versionId: versionId,
        empresaId: empresaId,
        accion: GdAccion.pdf_subido,
        actorId: actorId,
        nombreActor: nombreActor,
        metadatos: {'nombre': pdfNombre},
      );
    }

    debugPrint('[GdService] Documento creado: docId=$docId versionId=$versionId');
    return docId;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SUBIR / REEMPLAZAR PDF EN VERSIÓN EXISTENTE
  // ─────────────────────────────────────────────────────────────────────────

  /// Sube o reemplaza el PDF de una versión que esté en borrador u observado.
  Future<void> subirPdf({
    required String docId,
    required String versionId,
    required String empresaId,
    required int numeroVersion,
    required Uint8List bytes,
    required String nombre,
    required String actorId,
    required String rolDocumental,
    String? nombreActor,
  }) async {
    _validarRol('subir_pdf', rolDocumental);

    // Verificar estado permitido para reemplazar PDF
    final verSnap = await _verCol.doc(versionId).get();
    if (!verSnap.exists) throw const GdException('Versión no encontrada.');
    final estadoActual = GdEstadoX.deString((verSnap.data()?['estado'] ?? 'borrador').toString());
    if (estadoActual != GdEstado.borrador && estadoActual != GdEstado.observado) {
      throw GdException(
        'Solo se puede reemplazar el PDF en estado borrador u observado. '
        'Estado actual: ${estadoActual.etiqueta}',
      );
    }

    final esReemplazo = verSnap.data()?['urlPdf'] != null;

    final (url, path) = await _subirPdfBytes(
      empresaId: empresaId,
      docId: docId,
      numero: numeroVersion,
      bytes: bytes,
      nombre: nombre,
    );

    await _verCol.doc(versionId).update({
      'urlPdf': url,
      'pathPdf': path,
      'nombreArchivo': nombre,
      'subidoEn': FieldValue.serverTimestamp(),
    });

    await _registrarEvento(
      docId: docId,
      versionId: versionId,
      empresaId: empresaId,
      accion: esReemplazo ? GdAccion.pdf_reemplazado : GdAccion.pdf_subido,
      actorId: actorId,
      nombreActor: nombreActor,
      metadatos: {'nombre': nombre},
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TRANSICIONES DE ESTADO
  // ─────────────────────────────────────────────────────────────────────────

  /// Envía el documento a revisión.
  /// Transición: borrador → en_revision
  /// Actor: redactor, admin_doc
  Future<void> enviarARevision({
    required String docId,
    required String versionId,
    required String empresaId,
    required String actorId,
    required String rolDocumental,
    String? nombreActor,
  }) async {
    _validarRol('enviar_revision', rolDocumental);
    await _transicionar(
      docId: docId,
      versionId: versionId,
      empresaId: empresaId,
      desde: GdEstado.borrador,
      hacia: GdEstado.en_revision,
      accion: GdAccion.enviado_revision,
      actorId: actorId,
      nombreActor: nombreActor,
      camposTrazabilidad: {},
    );
  }

  /// Deja una observación con comentario obligatorio.
  /// Transición: en_revision → observado
  /// Actor: revisor, aprobador, admin_doc
  Future<void> observar({
    required String docId,
    required String versionId,
    required String empresaId,
    required String actorId,
    required String rolDocumental,
    required String observacion,
    String? nombreActor,
  }) async {
    if (observacion.trim().isEmpty) {
      throw const GdException('La observación es obligatoria.');
    }
    _validarRol('observar', rolDocumental);
    await _transicionar(
      docId: docId,
      versionId: versionId,
      empresaId: empresaId,
      desde: GdEstado.en_revision,
      hacia: GdEstado.observado,
      accion: GdAccion.observado,
      actorId: actorId,
      nombreActor: nombreActor,
      observacion: observacion.trim(),
      camposTrazabilidad: {
        'revisadoPor': actorId,
        'revisadoEn': FieldValue.serverTimestamp(),
        'observacion': observacion.trim(),
      },
      camposDocumento: {
        'revisadoPor': actorId,
      },
    );
  }

  /// Reenvía el documento a revisión tras corregirlo.
  /// Transición: observado → en_revision
  /// Actor: redactor, admin_doc
  Future<void> reenviar({
    required String docId,
    required String versionId,
    required String empresaId,
    required String actorId,
    required String rolDocumental,
    String? nombreActor,
    String? comentario,
  }) async {
    _validarRol('reenviar', rolDocumental);
    await _transicionar(
      docId: docId,
      versionId: versionId,
      empresaId: empresaId,
      desde: GdEstado.observado,
      hacia: GdEstado.en_revision,
      accion: GdAccion.reenviado,
      actorId: actorId,
      nombreActor: nombreActor,
      observacion: comentario,
      camposTrazabilidad: {},
    );
  }

  /// Aprueba formalmente el documento.
  /// Transición: en_revision → aprobado
  /// Actor: aprobador, admin_doc
  Future<void> aprobar({
    required String docId,
    required String versionId,
    required String empresaId,
    required String actorId,
    required String rolDocumental,
    String? nombreActor,
    String? comentario,
  }) async {
    _validarRol('aprobar', rolDocumental);
    await _transicionar(
      docId: docId,
      versionId: versionId,
      empresaId: empresaId,
      desde: GdEstado.en_revision,
      hacia: GdEstado.aprobado,
      accion: GdAccion.aprobado,
      actorId: actorId,
      nombreActor: nombreActor,
      observacion: comentario,
      camposTrazabilidad: {
        'aprobadoPor': actorId,
        'aprobadoEn': FieldValue.serverTimestamp(),
      },
      camposDocumento: {
        'aprobadoPor': actorId,
      },
    );
  }

  /// Firma internamente el documento aprobado.
  /// Transición: aprobado → firmado
  /// Actor: firmante, admin_doc
  ///
  /// Captura un snapshot de la URL de firma del actor para trazabilidad permanente.
  Future<void> firmar({
    required String docId,
    required String versionId,
    required String empresaId,
    required String actorId,
    required String rolDocumental,
    String? nombreActor,
    String? comentario,
  }) async {
    _validarRol('firmar', rolDocumental);

    // Leer la firma del actor para snapshot permanente
    String? urlFirmaSnapshot;
    try {
      final firmaDoc = await _firmasCol.doc(FirmaUsuarioDoc.docId(empresaId, actorId)).get();
      urlFirmaSnapshot = firmaDoc.data()?['urlFirma'] as String?;
    } catch (_) {}

    await _transicionar(
      docId: docId,
      versionId: versionId,
      empresaId: empresaId,
      desde: GdEstado.aprobado,
      hacia: GdEstado.firmado,
      accion: GdAccion.firmado,
      actorId: actorId,
      nombreActor: nombreActor,
      observacion: comentario,
      camposTrazabilidad: {
        'firmadoPor': actorId,
        'firmadoEn': FieldValue.serverTimestamp(),
        'urlFirmaUsada': urlFirmaSnapshot,
        'nombreFirmante': nombreActor ?? actorId,
      },
      camposDocumento: {
        'firmadoPor': actorId,
      },
    );
  }

  /// Marca la versión como vigente.
  /// Transición: firmado → vigente
  /// Regla fuerte: la versión vigente anterior pasa automáticamente a obsoleto.
  /// Actor: firmante, aprobador, admin_doc
  Future<void> marcarVigente({
    required String docId,
    required String versionId,
    required String empresaId,
    required String actorId,
    required String rolDocumental,
    String? nombreActor,
  }) async {
    _validarRol('marcar_vigente', rolDocumental);

    // Validar que la versión esté en estado firmado
    final verSnap = await _verCol.doc(versionId).get();
    if (!verSnap.exists) throw const GdException('Versión no encontrada.');
    final estadoActual = GdEstadoX.deString((verSnap.data()?['estado'] ?? '').toString());
    if (estadoActual != GdEstado.firmado) {
      throw GdException(
        'La versión debe estar en estado "firmado" para marcarse vigente. '
        'Estado actual: ${estadoActual.etiqueta}',
      );
    }

    // Buscar versión vigente anterior para el mismo documento
    final prevVigSnap = await _verCol
        .where('docId', isEqualTo: docId)
        .where('esVigente', isEqualTo: true)
        .limit(1)
        .get();

    final now = FieldValue.serverTimestamp();
    final batch = _db.batch();

    // 1. Marcar versión anterior como obsoleta (si existe)
    if (prevVigSnap.docs.isNotEmpty) {
      final prevDoc = prevVigSnap.docs.first;
      if (prevDoc.id != versionId) {
        batch.update(prevDoc.reference, {
          'esVigente': false,
          'estado': GdEstado.obsoleto.valor,
        });
      }
    }

    // 2. Marcar versión nueva como vigente
    batch.update(_verCol.doc(versionId), {
      'estado': GdEstado.vigente.valor,
      'esVigente': true,
    });

    // 3. Actualizar documento maestro
    batch.update(_docCol.doc(docId), {
      'estado': GdEstado.vigente.valor,
      'versionVigenteId': versionId,
      'updatedAt': now,
    });

    await batch.commit();

    // 4. Registrar evento: marcado_obsoleto en versión anterior
    if (prevVigSnap.docs.isNotEmpty && prevVigSnap.docs.first.id != versionId) {
      final prevId = prevVigSnap.docs.first.id;
      await _registrarEvento(
        docId: docId,
        versionId: prevId,
        empresaId: empresaId,
        accion: GdAccion.marcado_obsoleto,
        actorId: actorId,
        nombreActor: nombreActor,
        metadatos: {'reemplazadaPor': versionId},
      );
    }

    // 5. Registrar evento: marcado_vigente en versión nueva
    await _registrarEvento(
      docId: docId,
      versionId: versionId,
      empresaId: empresaId,
      accion: GdAccion.marcado_vigente,
      actorId: actorId,
      nombreActor: nombreActor,
    );

    debugPrint('[GdService] Versión vigente: versionId=$versionId docId=$docId');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // NUEVA VERSIÓN
  // ─────────────────────────────────────────────────────────────────────────

  /// Inicia una nueva versión del documento cuando ya existe una versión vigente.
  /// El documento maestro vuelve a borrador con la nueva versión.
  /// La versión vigente anterior NO se toca — sigue vigente hasta que la nueva llegue a vigente.
  /// Retorna el nuevo [versionId].
  Future<String> iniciarNuevaVersion({
    required String docId,
    required String empresaId,
    required String actorId,
    required String rolDocumental,
    String? nombreActor,
    Uint8List? pdfBytes,
    String? pdfNombre,
  }) async {
    _validarRol('nueva_version', rolDocumental);

    // Leer documento maestro para obtener número actual de versión
    final docSnap = await _docCol.doc(docId).get();
    if (!docSnap.exists) throw const GdException('Documento no encontrado.');
    final data = docSnap.data()!;

    // Calcular nuevo número de versión
    final versionsSnap = await _verCol
        .where('docId', isEqualTo: docId)
        .get();
    final maxNumero = versionsSnap.docs.fold<int>(0, (max, d) {
      final n = (d.data()['numero'] as int?) ?? 0;
      return n > max ? n : max;
    });
    final nuevoNumero = maxNumero + 1;
    final nuevaEtiqueta = 'v$nuevoNumero';

    final verRef = _verCol.doc();
    final versionId = verRef.id;
    final now = FieldValue.serverTimestamp();

    // Subir PDF si se proveyó
    String? urlPdf;
    String? pathPdf;
    if (pdfBytes != null && pdfNombre != null) {
      final result = await _subirPdfBytes(
        empresaId: empresaId,
        docId: docId,
        numero: nuevoNumero,
        bytes: pdfBytes,
        nombre: pdfNombre,
      );
      urlPdf = result.$1;
      pathPdf = result.$2;
    }

    final batch = _db.batch();

    // Nueva versión
    batch.set(verRef, {
      'docId': docId,
      'empresaId': empresaId,
      'numero': nuevoNumero,
      'etiqueta': nuevaEtiqueta,
      'estado': GdEstado.borrador.valor,
      'urlPdf': urlPdf,
      'pathPdf': pathPdf,
      'nombreArchivo': pdfNombre,
      'subidoPor': actorId,
      'subidoEn': now,
      'revisadoPor': null,
      'revisadoEn': null,
      'aprobadoPor': null,
      'aprobadoEn': null,
      'firmadoPor': null,
      'firmadoEn': null,
      'urlFirmaUsada': null,
      'nombreFirmante': null,
      'observacion': null,
      'esVigente': false,
    });

    // Actualizar documento maestro: nueva versión en borrador
    batch.update(_docCol.doc(docId), {
      'versionActual': nuevaEtiqueta,
      'estado': GdEstado.borrador.valor,
      'updatedAt': now,
      // Limpiar trazabilidad de versión anterior
      'revisadoPor': null,
      'aprobadoPor': null,
      'firmadoPor': null,
    });

    await batch.commit();

    await _registrarEvento(
      docId: docId,
      versionId: versionId,
      empresaId: empresaId,
      accion: GdAccion.nueva_version,
      actorId: actorId,
      nombreActor: nombreActor,
      metadatos: {
        'etiqueta': nuevaEtiqueta,
        'numero': nuevoNumero,
        'tituloDoc': (data['titulo'] ?? '').toString(),
      },
    );

    if (urlPdf != null) {
      await _registrarEvento(
        docId: docId,
        versionId: versionId,
        empresaId: empresaId,
        accion: GdAccion.pdf_subido,
        actorId: actorId,
        nombreActor: nombreActor,
        metadatos: {'nombre': pdfNombre},
      );
    }

    debugPrint('[GdService] Nueva versión: versionId=$versionId ($nuevaEtiqueta) docId=$docId');
    return versionId;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FIRMAS DE USUARIOS — TBL_FIRMAS_USUARIOS
  // ─────────────────────────────────────────────────────────────────────────

  /// Guarda o actualiza el perfil de firma del usuario.
  /// Si se proveen [firmaBytes], sube la imagen PNG a Storage.
  Future<void> guardarFirmaUsuario({
    required String empresaId,
    required String userId,
    required String nombre,
    String? cargo,
    Uint8List? firmaBytes,
  }) async {
    String? urlFirma;
    String? pathFirma;

    if (firmaBytes != null) {
      pathFirma = 'firmas_doc/$empresaId/$userId/firma.png';
      final ref = _storage.ref(pathFirma);
      await ref.putData(firmaBytes, SettableMetadata(contentType: 'image/png'));
      urlFirma = await ref.getDownloadURL();
    } else {
      // Si no se proveen bytes, eliminar la firma existente si la hay
      final docId = FirmaUsuarioDoc.docId(empresaId, userId);
      final firmaSnap = await _firmasCol.doc(docId).get();
      if (firmaSnap.exists && firmaSnap.data()?['pathFirma'] != null) {
        try {
          await _storage.ref(firmaSnap.data()!['pathFirma']).delete();
        } catch (e) {
          debugPrint('Error al eliminar firma antigua: $e');
        }
      }
    }

    final update = <String, dynamic>{
      'empresaId': empresaId,
      'userId': userId,
      'nombre': nombre,
      'cargo': cargo,
      'activa': firmaBytes != null, // Firma activa solo si se subió algo
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (urlFirma != null) update['urlFirma'] = urlFirma;
    if (pathFirma != null) update['pathFirma'] = pathFirma;
    else if (!firmaBytes!.isEmpty) {
      // Si firmaBytes es null, significa que se quiere eliminar la firma
      update['urlFirma'] = null;
      update['pathFirma'] = null;
    }

    final docId = FirmaUsuarioDoc.docId(empresaId, userId);
    await _firmasCol.doc(docId).set(update, SetOptions(merge: true));
    debugPrint('[GdService] Firma guardada: $docId');
  }

  /// Stream del perfil de firma del usuario.
  Stream<FirmaUsuarioDoc?> streamFirmaUsuario({
    required String empresaId,
    required String userId,
  }) {
    final docId = FirmaUsuarioDoc.docId(empresaId, userId);
    return _firmasCol.doc(docId).snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) return null;
      return FirmaUsuarioDoc.fromMap(empresaId, userId, snap.data()!);
    });
  }

  /// Lee una vez el perfil de firma.
  Future<FirmaUsuarioDoc?> getFirmaUsuario({
    required String empresaId,
    required String userId,
  }) async {
    final snap = await _firmasCol.doc(FirmaUsuarioDoc.docId(empresaId, userId)).get();
    if (!snap.exists || snap.data() == null) return null;
    return FirmaUsuarioDoc.fromMap(empresaId, userId, snap.data()!);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // READS: BIBLIOTECA, VERSIONES, HISTORIAL
  // ─────────────────────────────────────────────────────────────────────────

  /// Stream de todos los documentos de la empresa.
  /// Úsalo con filtros en la UI. Ordenado por updatedAt desc.
  Stream<List<DocumentoDoc>> streamDocumentos(String empresaId) {
    return _docCol
        .where('empresaId', isEqualTo: empresaId)
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => DocumentoDoc.fromMap(d.id, d.data()))
            .toList());
  }

  /// Stream de documentos vigentes de la empresa (para biblioteca pública).
  Stream<List<DocumentoDoc>> streamDocumentosVigentes(String empresaId) {
    return _docCol
        .where('empresaId', isEqualTo: empresaId)
        .where('estado', isEqualTo: GdEstado.vigente.valor)
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => DocumentoDoc.fromMap(d.id, d.data()))
            .toList());
  }

  /// Stream de todas las versiones de un documento.
  Stream<List<VersionDoc>> streamVersiones(String docId) {
    return _verCol
        .where('docId', isEqualTo: docId)
        .orderBy('numero', descending: false)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => VersionDoc.fromMap(d.id, d.data()))
            .toList());
  }

  /// Lee una versión específica.
  Future<VersionDoc?> getVersion(String versionId) async {
    final snap = await _verCol.doc(versionId).get();
    if (!snap.exists) return null;
    return VersionDoc.fromMap(snap.id, snap.data()!);
  }

  /// Stream del historial de eventos de un documento (append-only).
  Stream<List<FlujoEventoDoc>> streamHistorial(String docId) {
    return _flujoCol
        .where('docId', isEqualTo: docId)
        .orderBy('realizadoEn', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => FlujoEventoDoc.fromMap(d.id, d.data()))
            .toList());
  }

  /// Lee el documento maestro una vez.
  Future<DocumentoDoc?> getDocumento(String docId) async {
    final snap = await _docCol.doc(docId).get();
    if (!snap.exists) return null;
    return DocumentoDoc.fromMap(snap.id, snap.data()!)
      ..versionVigenteId = snap.data()?['versionVigenteId'] as String?;
  }

  /// Versión vigente del documento (si existe).
  Future<VersionDoc?> getVersionVigente(String docId) async {
    final snap = await _verCol
        .where('docId', isEqualTo: docId)
        .where('esVigente', isEqualTo: true)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return VersionDoc.fromMap(snap.docs.first.id, snap.docs.first.data());
  }

  // ─────────────────────────────────────────────────────────────────────────
  // UTILIDADES INTERNAS
  // ─────────────────────────────────────────────────────────────────────────

  /// Ejecuta una transición de estado genérica con validación y registro.
  Future<void> _transicionar({
    required String docId,
    required String versionId,
    required String empresaId,
    required GdEstado desde,
    required GdEstado hacia,
    required GdAccion accion,
    required String actorId,
    String? nombreActor,
    String? observacion,
    required Map<String, dynamic> camposTrazabilidad,
    Map<String, dynamic>? camposDocumento,
  }) async {
    // Validar transición
    final validas = _kTransicionesValidas[desde] ?? {};
    if (!validas.contains(hacia)) {
      throw GdException(
        'Transición no permitida: ${desde.etiqueta} → ${hacia.etiqueta}',
      );
    }

    // Leer estado actual de la versión
    final verSnap = await _verCol.doc(versionId).get();
    if (!verSnap.exists) throw const GdException('Versión no encontrada.');
    final estadoReal = GdEstadoX.deString(
      (verSnap.data()?['estado'] ?? '').toString(),
    );
    if (estadoReal != desde) {
      throw GdException(
        'Estado actual (${estadoReal.etiqueta}) no coincide con el esperado '
        '(${desde.etiqueta}).',
      );
    }

    final now = FieldValue.serverTimestamp();
    final batch = _db.batch();

    // Actualizar versión
    final versionUpdate = <String, dynamic>{
      'estado': hacia.valor,
      ...camposTrazabilidad,
    };
    batch.update(_verCol.doc(versionId), versionUpdate);

    // Actualizar documento maestro
    final docUpdate = <String, dynamic>{
      'estado': hacia.valor,
      'updatedAt': now,
      ...?camposDocumento,
    };
    batch.update(_docCol.doc(docId), docUpdate);

    await batch.commit();

    // Registrar evento
    await _registrarEvento(
      docId: docId,
      versionId: versionId,
      empresaId: empresaId,
      accion: accion,
      actorId: actorId,
      nombreActor: nombreActor,
      observacion: observacion,
    );

    debugPrint('[GdService] Transición: $docId $versionId ${desde.valor} → ${hacia.valor}');
  }

  /// Escribe un evento en TBL_DOCUMENTOS_FLUJO (append-only, nunca modifica ni elimina).
  Future<void> _registrarEvento({
    required String docId,
    String? versionId,
    required String empresaId,
    required GdAccion accion,
    required String actorId,
    String? nombreActor,
    String? observacion,
    Map<String, dynamic>? metadatos,
  }) async {
    await _flujoCol.add({
      'docId': docId,
      'versionId': versionId,
      'empresaId': empresaId,
      'accion': accion.valor,
      'realizadoPor': actorId,
      'nombreActor': nombreActor,
      'realizadoEn': FieldValue.serverTimestamp(),
      'observacion': observacion,
      'metadatos': metadatos,
    });
  }

  /// Sube bytes de PDF a Firebase Storage y retorna (url, path).
  Future<(String, String)> _subirPdfBytes({
    required String empresaId,
    required String docId,
    required int numero,
    required Uint8List bytes,
    required String nombre,
  }) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final safeName = nombre.replaceAll(RegExp(r'[^\w.\-]'), '_'); // Limpiar nombre de archivo
    final path = 'documentos/$empresaId/$docId/v$numero/${ts}_$safeName';
    final ref = _storage.ref(path);
    await ref.putData(bytes, SettableMetadata(contentType: 'application/pdf'));
    final url = await ref.getDownloadURL();
    return (url, path);
  }

  /// Valida que el rol tenga permiso para ejecutar la acción.
  void _validarRol(String accion, String rolDocumental) {
    if (!GdRoles.puedeEjecutar(accion, rolDocumental)) {
      throw GdException(
        'El rol "$rolDocumental" no tiene permiso para ejecutar "$accion".',
      );
    }
  }
}
