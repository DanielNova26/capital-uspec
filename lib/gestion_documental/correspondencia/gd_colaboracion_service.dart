import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../services/task_service.dart';
import '../gd_models.dart';
import 'gd_colaboracion_models.dart';
import 'gd_correspondencia_models.dart';

class GdColaboracionService {
  GdColaboracionService({
    FirebaseFirestore? db,
    FirebaseStorage? storage,
    TaskService? taskService,
  }) : _db = db ?? FirebaseFirestore.instance,
       _storage = storage ?? FirebaseStorage.instance,
       _taskService = taskService ?? TaskService();

  final FirebaseFirestore _db;
  final FirebaseStorage _storage;
  final TaskService _taskService;

  Stream<List<DocumentoDoc>> streamBiblioteca(String empresaId) => _db
      .collection('TBL_DOCUMENTOS')
      .where('empresaId', isEqualTo: empresaId)
      .snapshots()
      .map((snapshot) {
        final rows = snapshot.docs
            .map((doc) => DocumentoDoc.fromMap(doc.id, doc.data()))
            .toList();
        rows.sort((a, b) => a.codigo.compareTo(b.codigo));
        return rows;
      });

  Stream<List<GdDocumentoVinculado>> streamVinculosExpediente(
    String expedienteId,
  ) => _db
      .collection('TBL_GD_VINCULOS')
      .where('expedienteId', isEqualTo: expedienteId)
      .snapshots()
      .map(_mapLinks);

  Stream<List<GdDocumentoVinculado>> streamVinculosDocumento(
    String documentoId,
  ) => _db
      .collection('TBL_GD_VINCULOS')
      .where('documentoId', isEqualTo: documentoId)
      .snapshots()
      .map(_mapLinks);

  List<GdDocumentoVinculado> _mapLinks(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    final rows = snapshot.docs.map(GdDocumentoVinculado.fromFirestore).toList();
    rows.sort(
      (a, b) => (b.vinculadoAt ?? DateTime(0)).compareTo(
        a.vinculadoAt ?? DateTime(0),
      ),
    );
    return rows;
  }

  Stream<List<GdColaboracionEntrada>> streamColaboracion(String expedienteId) =>
      _db
          .collection('TBL_GD_COLABORACION')
          .where('expedienteId', isEqualTo: expedienteId)
          .snapshots()
          .map((snapshot) {
            final rows = snapshot.docs
                .map(GdColaboracionEntrada.fromFirestore)
                .toList();
            rows.sort(
              (a, b) => (a.createdAt ?? DateTime(0)).compareTo(
                b.createdAt ?? DateTime(0),
              ),
            );
            return rows;
          });

  Future<void> vincularDocumento({
    required GdExpediente expediente,
    required DocumentoDoc documento,
    required String userId,
    String tipo = 'referencia',
  }) async {
    if (documento.empresaId != expediente.empresaId) {
      throw StateError('El documento pertenece a otra empresa.');
    }
    final version = await _versionActual(documento);
    final versionKey = version?.versionId ?? documento.versionActual;
    final linkId = '${expediente.id}_${documento.docId}_$versionKey';
    final link = _db.collection('TBL_GD_VINCULOS').doc(linkId);
    final event = _db.collection('TBL_GD_EXPEDIENTES_EVENTOS').doc();
    final batch = _db.batch();
    batch.set(link, {
      'empresaId': expediente.empresaId,
      'expedienteId': expediente.id,
      'radicado': expediente.radicado,
      'asunto': expediente.asunto,
      'documentoId': documento.docId,
      'codigo': documento.codigo,
      'titulo': documento.titulo,
      'categoria': documento.categoria ?? '',
      'estadoDocumento': documento.estado.valor,
      'versionId': version?.versionId ?? '',
      'version': version?.etiqueta ?? documento.versionActual,
      'tipo': tipo,
      'archivoNombre': version?.nombreArchivo ?? '',
      'archivoUrl': version?.urlPdf ?? '',
      'archivoPath': version?.pathPdf ?? '',
      'vinculadoPor': userId,
      'vinculadoAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    batch.set(event, {
      'empresaId': expediente.empresaId,
      'expedienteId': expediente.id,
      'tipo': 'documento_vinculado',
      'usuarioId': userId,
      'detalle': '${documento.codigo} · ${documento.titulo} fue vinculado.',
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  Future<void> usarComoSoporte({
    required GdExpediente expediente,
    required GdDocumentoVinculado vinculo,
    required String userId,
  }) async {
    if (!vinculo.puedeUsarseComoSoporte) {
      throw StateError(
        'Solo una versión aprobada, firmada o vigente puede usarse como soporte.',
      );
    }
    final attachment = GdCorrespondenciaAdjunto(
      nombre: vinculo.archivoNombre.isEmpty
          ? '${vinculo.codigo}_${vinculo.version}.pdf'
          : vinculo.archivoNombre,
      mimeType: 'application/pdf',
      storagePath: vinculo.archivoPath,
      downloadUrl: vinculo.archivoUrl,
      size: 0,
      origen: 'biblioteca_documental',
      documentoId: vinculo.documentoId,
      versionId: vinculo.versionId,
    );
    final expedienteRef = _db
        .collection('TBL_GD_EXPEDIENTES')
        .doc(expediente.id);
    final linkRef = _db.collection('TBL_GD_VINCULOS').doc(vinculo.id);
    final event = _db.collection('TBL_GD_EXPEDIENTES_EVENTOS').doc();
    final batch = _db.batch();
    batch.set(expedienteRef, {
      'adjuntosRespuesta': FieldValue.arrayUnion([attachment.toMap()]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    batch.set(linkRef, {
      'tipo': 'soporte_respuesta',
      'usadoComoSoportePor': userId,
      'usadoComoSoporteAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    batch.set(event, {
      'empresaId': expediente.empresaId,
      'expedienteId': expediente.id,
      'tipo': 'soporte_documental_agregado',
      'usuarioId': userId,
      'detalle':
          '${vinculo.codigo} ${vinculo.version} se agregó a la respuesta.',
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  Future<void> agregarEntrada({
    required GdExpediente expediente,
    required String userId,
    required String mensaje,
    required String tipo,
    String documentoId = '',
    GdResponsable? destinatario,
    List<PlatformFile> adjuntos = const [],
  }) async {
    final clean = mensaje.trim();
    if (clean.isEmpty) throw StateError('Escribe un comentario.');
    if (tipo == 'solicitud_revision' && destinatario == null) {
      throw StateError('Selecciona a quién solicitas la revisión.');
    }
    final userName = await _nombreUsuario(userId);
    GdDocumentoVinculado? linkedDocument;
    if (documentoId.isNotEmpty) {
      final links = await _db
          .collection('TBL_GD_VINCULOS')
          .where('expedienteId', isEqualTo: expediente.id)
          .get();
      for (final link in links.docs) {
        final value = GdDocumentoVinculado.fromFirestore(link);
        if (value.documentoId == documentoId) {
          linkedDocument = value;
          break;
        }
      }
    }
    final ref = _db.collection('TBL_GD_COLABORACION').doc();
    final uploadedAttachments = await _subirAdjuntos(
      expediente: expediente,
      entradaId: ref.id,
      files: adjuntos,
    );
    final event = _db.collection('TBL_GD_EXPEDIENTES_EVENTOS').doc();
    final batch = _db.batch();
    batch.set(ref, {
      'empresaId': expediente.empresaId,
      'expedienteId': expediente.id,
      'documentoId': documentoId,
      'documentoCodigo': linkedDocument?.codigo ?? '',
      'documentoTitulo': linkedDocument?.titulo ?? '',
      'tipo': tipo,
      'mensaje': clean,
      'usuarioId': userId,
      'usuarioNombre': userName,
      'destinatarioId': destinatario?.id ?? '',
      'destinatarioNombre': destinatario?.nombre ?? '',
      'destinatarioAreaId': destinatario?.areaId ?? '',
      'destinatarioAreaNombre': destinatario?.areaNombre ?? '',
      'adjuntos': uploadedAttachments.map((item) => item.toMap()).toList(),
      'estado': tipo == 'comentario' ? 'informativo' : 'abierto',
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(event, {
      'empresaId': expediente.empresaId,
      'expedienteId': expediente.id,
      'tipo': tipo,
      'usuarioId': userId,
      'detalle': tipo == 'solicitud_revision'
          ? 'Se solicitó revisión a ${destinatario!.nombre}${uploadedAttachments.isEmpty ? '' : ' con ${uploadedAttachments.length} adjunto(s)'}.'
          : destinatario == null
          ? 'Se agregó una entrada a la mesa de colaboración.'
          : 'Se compartió una entrada con ${destinatario.nombre}${uploadedAttachments.isEmpty ? '' : ' y ${uploadedAttachments.length} adjunto(s)'}.',
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();

    if (destinatario != null && destinatario.id != userId) {
      await _taskService.pushNotification(
        toUserId: destinatario.id,
        title: tipo == 'solicitud_revision'
            ? 'Revisión documental solicitada'
            : 'Nueva participación documental',
        description: '${expediente.radicado}: $clean',
        taskId: expediente.tareaId.isEmpty ? null : expediente.tareaId,
        type: 'gestion_documental_colaboracion',
        fromId: userId,
        fromName: userName,
        empresaId: expediente.empresaId,
        extraData: {
          'modulo': 'gestion_documental',
          'expedienteId': expediente.id,
          'documentoId': documentoId,
        },
        idempotencyKey: 'gd-colab-${ref.id}-${destinatario.id}',
      );
    }
  }

  Future<List<GdCorrespondenciaAdjunto>> _subirAdjuntos({
    required GdExpediente expediente,
    required String entradaId,
    required List<PlatformFile> files,
  }) async {
    final result = <GdCorrespondenciaAdjunto>[];
    for (final file in files) {
      if (file.size > 25 * 1024 * 1024) {
        throw StateError('${file.name} supera el límite de 25 MB.');
      }
      final Uint8List bytes =
          file.bytes ??
          (throw StateError(
            'No fue posible leer ${file.name}. Selecciónalo nuevamente.',
          ));
      final safeName = file.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final path =
          'gestion_documental/correspondencia/${expediente.empresaId}/${expediente.id}/colaboracion/$entradaId/${DateTime.now().microsecondsSinceEpoch}_$safeName';
      final mime = _mimeType(file.extension);
      final ref = _storage.ref(path);
      await ref.putData(bytes, SettableMetadata(contentType: mime));
      result.add(
        GdCorrespondenciaAdjunto(
          nombre: file.name,
          mimeType: mime,
          storagePath: path,
          downloadUrl: await ref.getDownloadURL(),
          size: bytes.length,
          origen: 'mesa_colaboracion',
        ),
      );
    }
    return result;
  }

  String _mimeType(String? extension) => switch (extension?.toLowerCase()) {
    'pdf' => 'application/pdf',
    'doc' => 'application/msword',
    'docx' =>
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls' => 'application/vnd.ms-excel',
    'xlsx' =>
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'png' => 'image/png',
    'jpg' || 'jpeg' => 'image/jpeg',
    _ => 'application/octet-stream',
  };

  Future<void> resolverEntrada({
    required GdColaboracionEntrada entrada,
    required String userId,
  }) async {
    if (entrada.destinatarioId.isNotEmpty &&
        entrada.destinatarioId != userId &&
        entrada.usuarioId != userId) {
      throw StateError('Solo el solicitante o el revisor puede resolverla.');
    }
    await _db.collection('TBL_GD_COLABORACION').doc(entrada.id).set({
      'estado': 'resuelto',
      'resueltoPor': userId,
      'resolvedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<VersionDoc?> _versionActual(DocumentoDoc documento) async {
    final snapshot = await _db
        .collection('TBL_DOCUMENTOS_VERSIONES')
        .where('docId', isEqualTo: documento.docId)
        .get();
    final versions = snapshot.docs
        .map((doc) => VersionDoc.fromMap(doc.id, doc.data()))
        .toList();
    for (final version in versions) {
      if (documento.versionVigenteId == version.versionId) return version;
    }
    for (final version in versions) {
      if (version.etiqueta == documento.versionActual) return version;
    }
    versions.sort((a, b) => b.numero.compareTo(a.numero));
    return versions.firstOrNull;
  }

  Future<String> _nombreUsuario(String userId) async {
    final doc = await _db.collection('TBL_USUARIOS').doc(userId).get();
    final data = doc.data() ?? const <String, dynamic>{};
    final direct = (data['nombre'] ?? data['nombreCompleto'] ?? '')
        .toString()
        .trim();
    if (direct.isNotEmpty) return direct;
    return '${data['nombres'] ?? ''} ${data['apellidos'] ?? ''}'.trim().isEmpty
        ? userId
        : '${data['nombres'] ?? ''} ${data['apellidos'] ?? ''}'.trim();
  }
}
