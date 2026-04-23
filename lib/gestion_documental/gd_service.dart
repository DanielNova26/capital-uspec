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

import 'package:cloud_firestore/cloud_firestore.dart';
// Eliminado import de file_picker.dart
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'gd_models.dart';
import '../services/task_service.dart';

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
  GdEstado.borrador: {GdEstado.en_revision},
  GdEstado.en_revision: {GdEstado.observado, GdEstado.aprobado},
  GdEstado.observado: {GdEstado.en_revision},
  GdEstado.aprobado: {GdEstado.firmado},
  GdEstado.firmado: {GdEstado.vigente},
  GdEstado.vigente: {GdEstado.obsoleto},
  GdEstado.obsoleto: {},
};

// ─────────────────────────────────────────────────────────────────────────────
// Servicio
// ─────────────────────────────────────────────────────────────────────────────

class GdService {
  static const String _colDocumentos = 'TBL_DOCUMENTOS';
  static const String _colVersiones = 'TBL_DOCUMENTOS_VERSIONES';
  static const String _colFlujo = 'TBL_DOCUMENTOS_FLUJO';
  static const String _colUsuarios = 'TBL_USUARIOS';

  final FirebaseFirestore _db;
  final FirebaseStorage _storage;
  final TaskService _taskService;

  GdService({
    FirebaseFirestore? db,
    FirebaseStorage? storage,
    TaskService? taskService,
  }) : _db = db ?? FirebaseFirestore.instance,
       _storage = storage ?? FirebaseStorage.instance,
       _taskService = taskService ?? TaskService();

  // ── Colecciones ─────────────────────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> get _docCol =>
      _db.collection(_colDocumentos);
  CollectionReference<Map<String, dynamic>> get _verCol =>
      _db.collection(_colVersiones);
  CollectionReference<Map<String, dynamic>> get _flujoCol =>
      _db.collection(_colFlujo);
  CollectionReference<Map<String, dynamic>> get _usersCol =>
      _db.collection(_colUsuarios);

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
    required String actorId, // userId del redactor
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

    debugPrint(
      '[GdService] Documento creado: docId=$docId versionId=$versionId',
    );
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
    final estadoActual = GdEstadoX.deString(
      (verSnap.data()?['estado'] ?? 'borrador').toString(),
    );
    if (estadoActual != GdEstado.borrador &&
        estadoActual != GdEstado.observado) {
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
    // Datos del documento ya en memoria en la UI — evitan el re-fetch en la notificación.
    String? creadoPorHint,
    String? tituloHint,
    String? codigoHint,
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
      camposDocumento: {'revisadoPor': actorId},
    );
    await _notificarObservacionDocumento(
      docId: docId,
      empresaId: empresaId,
      actorId: actorId,
      nombreActor: nombreActor,
      observacion: observacion.trim(),
      creadoPorHint: creadoPorHint,
      tituloHint: tituloHint,
      codigoHint: codigoHint,
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
      camposDocumento: {'aprobadoPor': actorId},
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
      final firmaDoc = await _usersCol.doc(actorId).get();
      final firmaPerfil = _mapUserToFirmaUsuario(
        actorId,
        empresaId,
        firmaDoc.data(),
      );
      urlFirmaSnapshot = firmaPerfil?.urlFirma;
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
      camposDocumento: {'firmadoPor': actorId},
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
    final estadoActual = GdEstadoX.deString(
      (verSnap.data()?['estado'] ?? '').toString(),
    );
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

    debugPrint(
      '[GdService] Versión vigente: versionId=$versionId docId=$docId',
    );
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
    final versionsSnap = await _verCol.where('docId', isEqualTo: docId).get();
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

    debugPrint(
      '[GdService] Nueva versión: versionId=$versionId ($nuevaEtiqueta) docId=$docId',
    );
    return versionId;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ELIMINAR DOCUMENTO
  // ─────────────────────────────────────────────────────────────────────────

  /// Elimina completamente un documento de la biblioteca documental:
  /// - documento maestro
  /// - todas sus versiones
  /// - todo su historial
  /// - archivos PDF asociados en Firebase Storage
  ///
  /// Solo disponible para admin_doc y desarrollador.
  Future<void> eliminarDocumento({
    required String docId,
    required String empresaId,
    required String actorId,
    required String rolDocumental,
  }) async {
    _validarRol('eliminar_documento', rolDocumental);

    final docRef = _docCol.doc(docId);
    final docSnap = await docRef.get();
    if (!docSnap.exists) {
      throw const GdException('El documento ya no existe o fue eliminado.');
    }

    final docData = docSnap.data() ?? <String, dynamic>{};
    final empresaDocumento = (docData['empresaId'] ?? '').toString();
    if (empresaDocumento != empresaId) {
      throw const GdException(
        'El documento no pertenece a la empresa activa.',
      );
    }

    final versionesSnap = await _verCol.where('docId', isEqualTo: docId).get();
    final flujoSnap = await _flujoCol.where('docId', isEqualTo: docId).get();

    for (final versionDoc in versionesSnap.docs) {
      final pathPdf = (versionDoc.data()['pathPdf'] ?? '').toString().trim();
      if (pathPdf.isEmpty) continue;
      try {
        await _storage.ref(pathPdf).delete();
      } catch (e) {
        debugPrint(
          '[GdService] No fue posible eliminar archivo de Storage '
          '($pathPdf) para $docId: $e',
        );
      }
    }

    final refsAEliminar = <DocumentReference<Map<String, dynamic>>>[
      ...versionesSnap.docs.map((d) => d.reference),
      ...flujoSnap.docs.map((d) => d.reference),
      docRef,
    ];

    for (var i = 0; i < refsAEliminar.length; i += 400) {
      final batch = _db.batch();
      final chunk = refsAEliminar.skip(i).take(400);
      for (final ref in chunk) {
        batch.delete(ref);
      }
      await batch.commit();
    }

    debugPrint(
      '[GdService] Documento eliminado: docId=$docId actorId=$actorId',
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FIRMAS DE USUARIOS — TBL_USUARIOS
  // ─────────────────────────────────────────────────────────────────────────

  /// Guarda o actualiza la firma del usuario dentro de TBL_USUARIOS.
  /// El nombre y el cargo se resuelven desde el perfil existente del usuario.
  Future<void> guardarFirmaUsuario({
    required String empresaId,
    required String userId,
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
      final userSnap = await _usersCol.doc(userId).get();
      final perfil = _mapUserToFirmaUsuario(userId, empresaId, userSnap.data());
      if (perfil?.pathFirma != null) {
        try {
          await _storage.ref(perfil!.pathFirma!).delete();
        } catch (e) {
          debugPrint('Error al eliminar firma antigua: $e');
        }
      }
    }

    final update = <String, dynamic>{
      'firmaActiva': firmaBytes != null,
      'updatedAt': FieldValue.serverTimestamp(),
      'firmaActualizadaEn': FieldValue.serverTimestamp(),
      'empresasDetalle.$empresaId.firmaActiva': firmaBytes != null,
      'empresasDetalle.$empresaId.firmaActualizadaEn':
          FieldValue.serverTimestamp(),
    };
    if (urlFirma != null) {
      update['urlFirma'] = urlFirma;
      update['empresasDetalle.$empresaId.urlFirma'] = urlFirma;
    }
    if (pathFirma != null) {
      update['pathFirma'] = pathFirma;
      update['empresasDetalle.$empresaId.pathFirma'] = pathFirma;
    } else if (firmaBytes == null) {
      update['urlFirma'] = null;
      update['pathFirma'] = null;
      update['firmaBlob'] = null;
      update['empresasDetalle.$empresaId.urlFirma'] = null;
      update['empresasDetalle.$empresaId.pathFirma'] = null;
      update['empresasDetalle.$empresaId.firmaBlob'] = null;
    }
    // Store raw bytes in Firestore as Blob — this is the most reliable read path
    // on web (no Storage CORS or security-rule issues).
    if (firmaBytes != null) {
      update['firmaBlob'] = firmaBytes;
      update['empresasDetalle.$empresaId.firmaBlob'] = firmaBytes;
    }

    await _usersCol.doc(userId).set(update, SetOptions(merge: true));
    debugPrint('[GdService] Firma guardada en TBL_USUARIOS: $userId');
  }

  /// Stream del perfil de firma del usuario.
  Stream<FirmaUsuarioDoc?> streamFirmaUsuario({
    required String empresaId,
    required String userId,
  }) {
    return _usersCol.doc(userId).snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) return null;
      return _mapUserToFirmaUsuario(userId, empresaId, snap.data());
    });
  }

  /// Lee una vez el perfil de firma.
  Future<FirmaUsuarioDoc?> getFirmaUsuario({
    required String empresaId,
    required String userId,
  }) async {
    final snap = await _usersCol.doc(userId).get();
    if (!snap.exists || snap.data() == null) return null;
    return _mapUserToFirmaUsuario(userId, empresaId, snap.data());
  }

  Future<Uint8List> getFirmaBytes(FirmaUsuarioDoc firma) async {
    // Priority 0: Blob from Firestore — no Storage, no CORS, always works.
    if (firma.firmaBlob != null && firma.firmaBlob!.isNotEmpty) {
      return firma.firmaBlob!;
    }

    // Storage SDK first: handles auth/CORS automatically on web.
    if (firma.pathFirma != null && firma.pathFirma!.trim().isNotEmpty) {
      try {
        final bytes = await _storage.ref(firma.pathFirma!).getData();
        if (bytes != null && bytes.isNotEmpty) return bytes;
      } catch (e) {
        debugPrint('[GdService] getFirmaBytes.getData error: $e');
      }

      // Refresh the download URL and retry via HTTP (covers expired-token case).
      try {
        final freshUrl =
            await _storage.ref(firma.pathFirma!).getDownloadURL();
        final resp = await http.get(Uri.parse(freshUrl));
        if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
          return resp.bodyBytes;
        }
      } catch (e) {
        debugPrint('[GdService] getFirmaBytes.freshUrl error: $e');
      }
    }

    // Last resort: use the stored URL directly.
    if (firma.urlFirma != null && firma.urlFirma!.trim().isNotEmpty) {
      try {
        final resp = await http.get(Uri.parse(firma.urlFirma!));
        if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
          return resp.bodyBytes;
        }
      } catch (e) {
        debugPrint('[GdService] getFirmaBytes.storedUrl error: $e');
      }
    }

    throw Exception('No se pudo cargar la firma.');
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
        .map(
          (snap) => snap.docs
              .map((d) => DocumentoDoc.fromMap(d.id, d.data()))
              .toList(),
        );
  }

  /// Stream de documentos vigentes de la empresa (para biblioteca pública).
  Stream<List<DocumentoDoc>> streamDocumentosVigentes(String empresaId) {
    return _docCol
        .where('empresaId', isEqualTo: empresaId)
        .where('estado', isEqualTo: GdEstado.vigente.valor)
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => DocumentoDoc.fromMap(d.id, d.data()))
              .toList(),
        );
  }

  /// Stream de todas las versiones de un documento.
  Stream<List<VersionDoc>> streamVersiones(String docId) {
    return _verCol
        .where('docId', isEqualTo: docId)
        .orderBy('numero', descending: false)
        .snapshots()
        .asyncMap((snap) async {
          final versions = <VersionDoc>[];
          for (final doc in snap.docs) {
            versions.add(await _hydrateVersionPdfUrl(doc.id, doc.data()));
          }
          return versions;
        });
  }

  /// Lee una versión específica.
  Future<VersionDoc?> getVersion(String versionId) async {
    final snap = await _verCol.doc(versionId).get();
    if (!snap.exists) return null;
    return _hydrateVersionPdfUrl(snap.id, snap.data()!);
  }

  /// Stream del historial de eventos de un documento (append-only).
  Stream<List<FlujoEventoDoc>> streamHistorial(String docId) {
    return _flujoCol
        .where('docId', isEqualTo: docId)
        .orderBy('realizadoEn', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => FlujoEventoDoc.fromMap(d.id, d.data()))
              .toList(),
        );
  }

  /// Lee el documento maestro una vez.
  Future<DocumentoDoc?> getDocumento(String docId) async {
    final snap = await _docCol.doc(docId).get();
    if (!snap.exists) return null;
    return DocumentoDoc.fromMap(snap.id, snap.data()!);
  }

  /// Versión vigente del documento (si existe).
  Future<VersionDoc?> getVersionVigente(String docId) async {
    final snap = await _verCol
        .where('docId', isEqualTo: docId)
        .where('esVigente', isEqualTo: true)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    final doc = snap.docs.first;
    return _hydrateVersionPdfUrl(doc.id, doc.data());
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

    debugPrint(
      '[GdService] Transición: $docId $versionId ${desde.valor} → ${hacia.valor}',
    );
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
    final safeName = nombre.replaceAll(
      RegExp(r'[^\w.\-]'),
      '_',
    ); // Limpiar nombre de archivo
    final path = 'documentos/$empresaId/$docId/v$numero/${ts}_$safeName';
    final ref = _storage.ref(path);
    await ref.putData(bytes, SettableMetadata(contentType: 'application/pdf'));
    final url = await ref.getDownloadURL();
    return (url, path);
  }

  /// Repara lecturas incompletas: si existe pathPdf pero falta urlPdf,
  /// intenta regenerar la URL desde Storage y persistirla en Firestore.
  Future<VersionDoc> _hydrateVersionPdfUrl(
    String versionId,
    Map<String, dynamic> data,
  ) async {
    var version = VersionDoc.fromMap(versionId, data);
    if (version.urlPdf != null && version.urlPdf!.trim().isNotEmpty) {
      return version;
    }
    final path = version.pathPdf;
    if (path == null || path.trim().isEmpty) return version;

    try {
      final url = await _storage.ref(path).getDownloadURL();
      await _verCol.doc(versionId).set({
        'urlPdf': url,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      version = version.copyWith(urlPdf: url);
    } catch (e) {
      debugPrint(
        '[GdService] No fue posible hidratar urlPdf para $versionId: $e',
      );
    }

    return version;
  }

  Future<void> _notificarObservacionDocumento({
    required String docId,
    required String empresaId,
    required String actorId,
    required String observacion,
    String? nombreActor,
    // Hints opcionales: si están completos se evita el re-fetch.
    String? creadoPorHint,
    String? tituloHint,
    String? codigoHint,
  }) async {
    try {
      final String creadorId;
      final String titulo;
      final String codigo;

      if (creadoPorHint != null &&
          creadoPorHint.trim().isNotEmpty &&
          tituloHint != null &&
          codigoHint != null) {
        creadorId = creadoPorHint.trim();
        titulo = tituloHint;
        codigo = codigoHint;
      } else {
        final doc = await getDocumento(docId);
        if (doc == null) return;
        creadorId = doc.creadoPor.trim();
        titulo = doc.titulo;
        codigo = doc.codigo;
      }

      if (creadorId.isEmpty || creadorId == actorId.trim()) return;

      await _taskService.pushNotification(
        toUserId: creadorId,
        title: 'Documento observado o rechazado',
        description:
            'El documento "$titulo" ($codigo) fue observado. Motivo: $observacion',
        taskId: docId,
        type: 'gestion_documental_observado',
        fromId: actorId,
        fromName: nombreActor ?? '',
        empresaId: empresaId,
      );
    } catch (e) {
      debugPrint(
        '[GdService] No fue posible notificar observación para $docId: $e',
      );
    }
  }

  /// Valida que el rol tenga permiso para ejecutar la acción.
  void _validarRol(String accion, String rolDocumental) {
    if (!GdRoles.puedeEjecutar(accion, rolDocumental)) {
      throw GdException(
        'El rol "$rolDocumental" no tiene permiso para ejecutar "$accion".',
      );
    }
  }

  FirmaUsuarioDoc? _mapUserToFirmaUsuario(
    String userId,
    String empresaId,
    Map<String, dynamic>? data,
  ) {
    if (data == null) return null;

    final detalleRaw = data['empresasDetalle'];
    Map<String, dynamic>? scoped;
    if (detalleRaw is Map) {
      final rawScoped = detalleRaw[empresaId];
      if (rawScoped is Map<String, dynamic>) {
        scoped = rawScoped;
      } else if (rawScoped is Map) {
        scoped = rawScoped.map((k, v) => MapEntry(k.toString(), v));
      }
    }

    final nombre = _resolveNombreUsuario(userId, data);
    final cargo = ((scoped?['cargo'] ?? data['cargo']) ?? '').toString().trim();
    final urlFirma = ((scoped?['urlFirma'] ?? data['urlFirma']) ?? '')
        .toString()
        .trim();
    final pathFirma = ((scoped?['pathFirma'] ?? data['pathFirma']) ?? '')
        .toString()
        .trim();
    final activaValue = scoped?['firmaActiva'] ?? data['firmaActiva'];
    final activa = activaValue is bool ? activaValue : urlFirma.isNotEmpty;

    // Read Blob stored directly in Firestore (primary read path — no Storage CORS needed).
    final blobRaw = scoped?['firmaBlob'] ?? data['firmaBlob'];
    Uint8List? firmaBlob;
    if (blobRaw is Uint8List && blobRaw.isNotEmpty) {
      firmaBlob = blobRaw;
    } else if (blobRaw is List && blobRaw.isNotEmpty) {
      firmaBlob = Uint8List.fromList(blobRaw.cast<int>());
    }

    return FirmaUsuarioDoc(
      empresaId: empresaId,
      userId: userId,
      nombre: nombre,
      cargo: cargo.isEmpty ? null : cargo,
      urlFirma: urlFirma.isEmpty ? null : urlFirma,
      pathFirma: pathFirma.isEmpty ? null : pathFirma,
      firmaBlob: firmaBlob,
      activa: activa,
      createdAt: data['createdAt'] as Timestamp?,
      updatedAt:
          (scoped?['firmaActualizadaEn'] ??
                  data['firmaActualizadaEn'] ??
                  data['updatedAt'])
              as Timestamp?,
    );
  }

  String _resolveNombreUsuario(String userId, Map<String, dynamic> data) {
    final nombreCompleto = (data['nombreCompleto'] ?? '').toString().trim();
    if (nombreCompleto.isNotEmpty) return nombreCompleto;

    final nombre = (data['nombre'] ?? '').toString().trim();
    if (nombre.isNotEmpty) return nombre;

    final nombres = (data['nombres'] ?? data['primerNombre'] ?? '')
        .toString()
        .trim();
    final apellidos = (data['apellidos'] ?? data['primerApellido'] ?? '')
        .toString()
        .trim();
    final fullName = '$nombres $apellidos'.trim();
    if (fullName.isNotEmpty) return fullName;

    return userId;
  }
}
