import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'plantilla_combinacion.dart';

/// Documentos de finalización de contrato.
///
/// El nombre lo eligió Talento Humano en la reunión del 8 sep 2026 y es el que
/// ve el trabajador en la app. Son tres papeles y no una carpeta libre: dejar
/// el tipo abierto haría que cada quien los nombrara distinto y el portal no
/// sabría cuál falta.
class DocumentoFinalizacionTipo {
  static const cartaLaboral = 'carta_laboral';
  static const certificadoCesantias = 'certificado_cesantias';
  static const ordenExamenes = 'orden_examenes_egreso';

  static const values = <String>[
    cartaLaboral,
    certificadoCesantias,
    ordenExamenes,
  ];

  static bool isValid(String value) => values.contains(value.trim());

  static String label(String value) {
    switch (value.trim()) {
      case cartaLaboral:
        return 'Carta laboral';
      case certificadoCesantias:
        return 'Certificado de cesantías';
      case ordenExamenes:
        return 'Orden de exámenes médicos de egreso';
      default:
        return 'Documento';
    }
  }

  /// Qué es cada papel, en una línea, para que el trabajador sepa qué bajó.
  static String description(String value) {
    switch (value.trim()) {
      case cartaLaboral:
        return 'Certifica el cargo, el salario y las fechas del contrato.';
      case certificadoCesantias:
        return 'Solo para quienes tienen cesantías por reclamar.';
      case ordenExamenes:
        return 'Autorización para el examen médico de retiro.';
      default:
        return '';
    }
  }

  /// El único que no le toca a todo el mundo: Talento Humano marca a quién.
  static bool isOptional(String value) =>
      value.trim() == certificadoCesantias;
}

class DocumentoFinalizacion {
  final String tipo;
  final String nombre;
  final String url;
  final String storagePath;
  final String subidoPor;
  final DateTime? subidoAt;

  const DocumentoFinalizacion({
    required this.tipo,
    required this.nombre,
    required this.url,
    required this.storagePath,
    this.subidoPor = '',
    this.subidoAt,
  });

  factory DocumentoFinalizacion.fromMap(String tipo, Map<String, dynamic> d) {
    final fecha = d['fecha'];
    return DocumentoFinalizacion(
      tipo: tipo,
      nombre: (d['nombre'] ?? 'Documento').toString(),
      url: (d['url'] ?? '').toString(),
      storagePath: (d['storagePath'] ?? '').toString(),
      subidoPor: (d['subidoPor'] ?? '').toString(),
      subidoAt: fecha is Timestamp ? fecha.toDate() : null,
    );
  }
}

/// La carpeta de finalización de una persona.
class CarpetaFinalizacion {
  final String id;
  final String empresaId;
  final String cedula;
  final String nombre;

  /// Marcado por Talento Humano. Sin esto el portal no puede distinguir entre
  /// "no le toca certificado de cesantías" y "le toca pero aún no lo subimos",
  /// que para el trabajador son cosas muy distintas.
  final bool aplicaCesantias;

  final Map<String, DocumentoFinalizacion> documentos;
  final DateTime? actualizadoAt;

  const CarpetaFinalizacion({
    required this.id,
    required this.empresaId,
    required this.cedula,
    required this.nombre,
    this.aplicaCesantias = false,
    this.documentos = const {},
    this.actualizadoAt,
  });

  DocumentoFinalizacion? operator [](String tipo) => documentos[tipo];

  /// Tipos que le corresponden a esta persona.
  List<String> get tiposEsperados => DocumentoFinalizacionTipo.values
      .where(
        (tipo) =>
            !DocumentoFinalizacionTipo.isOptional(tipo) || aplicaCesantias,
      )
      .toList();

  List<String> get faltantes =>
      tiposEsperados.where((tipo) => !documentos.containsKey(tipo)).toList();

  bool get completa => faltantes.isEmpty;
  bool get vacia => documentos.isEmpty;

  factory CarpetaFinalizacion.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    final crudos = data['documentos'];
    final documentos = <String, DocumentoFinalizacion>{};
    if (crudos is Map) {
      for (final entry in crudos.entries) {
        final tipo = entry.key.toString();
        final valor = entry.value;
        if (!DocumentoFinalizacionTipo.isValid(tipo) || valor is! Map) continue;
        documentos[tipo] = DocumentoFinalizacion.fromMap(
          tipo,
          valor.map((k, v) => MapEntry(k.toString(), v)),
        );
      }
    }
    final fecha = data['actualizadoAt'];
    return CarpetaFinalizacion(
      id: doc.id,
      empresaId: (data['empresaId'] ?? '').toString(),
      cedula: (data['cedula'] ?? '').toString(),
      nombre: (data['nombre'] ?? '').toString(),
      aplicaCesantias: data['aplicaCesantias'] == true,
      documentos: documentos,
      actualizadoAt: fecha is Timestamp ? fecha.toDate() : null,
    );
  }
}

/// Plantilla de Word guardada por empresa y tipo de documento.
///
/// Se guarda para que la primera vez sea la única vez: después de cargarla,
/// generar el lote es subir el Excel y nada más.
class PlantillaDocumento {
  final String tipo;
  final String nombre;
  final String url;
  final String storagePath;
  final List<String> marcadores;
  final DateTime? subidaAt;
  final String subidaPor;

  const PlantillaDocumento({
    required this.tipo,
    required this.nombre,
    required this.url,
    required this.storagePath,
    this.marcadores = const [],
    this.subidaAt,
    this.subidaPor = '',
  });

  factory PlantillaDocumento.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    final fecha = data['fecha'];
    return PlantillaDocumento(
      tipo: (data['tipo'] ?? '').toString(),
      nombre: (data['nombre'] ?? 'Plantilla').toString(),
      url: (data['url'] ?? '').toString(),
      storagePath: (data['storagePath'] ?? '').toString(),
      marcadores: (data['marcadores'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      subidaAt: fecha is Timestamp ? fecha.toDate() : null,
      subidaPor: (data['subidaPor'] ?? '').toString(),
    );
  }
}

class FinalizacionDocumentosService {
  static const carpetasCollection = 'TBL_TH_DOCUMENTOS_FINALIZACION';
  static const plantillasCollection = 'TBL_TH_PLANTILLAS_DOCUMENTOS';

  static const maxBytes = 15 * 1024 * 1024;

  final FirebaseFirestore _db;
  final FirebaseStorage _storage;

  FinalizacionDocumentosService({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  }) : _db = firestore ?? FirebaseFirestore.instance,
       _storage = storage ?? FirebaseStorage.instance;

  /// La carpeta se identifica por empresa + cédula: la misma persona puede
  /// estar en dos empresas del grupo y sus papeles no se mezclan.
  static String carpetaId(String empresaId, String cedula) =>
      '${empresaId}_$cedula';

  Stream<List<CarpetaFinalizacion>> watchEmpresa(String empresaId) {
    return _db
        .collection(carpetasCollection)
        .where('empresaId', isEqualTo: empresaId)
        .snapshots()
        .map((snapshot) {
          final carpetas = snapshot.docs
              .map(CarpetaFinalizacion.fromDoc)
              .toList();
          carpetas.sort(
            (a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()),
          );
          return carpetas;
        });
  }

  /// Lo que ve el trabajador: solo su propia carpeta.
  Stream<CarpetaFinalizacion?> watchPersona({
    required String empresaId,
    required String cedula,
  }) {
    return _db
        .collection(carpetasCollection)
        .doc(carpetaId(empresaId, cedula))
        .snapshots()
        .map((doc) => doc.exists ? CarpetaFinalizacion.fromDoc(doc) : null);
  }

  Stream<Map<String, PlantillaDocumento>> watchPlantillas(String empresaId) {
    return _db
        .collection(plantillasCollection)
        .where('empresaId', isEqualTo: empresaId)
        .snapshots()
        .map((snapshot) {
          final result = <String, PlantillaDocumento>{};
          for (final doc in snapshot.docs) {
            final plantilla = PlantillaDocumento.fromDoc(doc);
            if (DocumentoFinalizacionTipo.isValid(plantilla.tipo)) {
              result[plantilla.tipo] = plantilla;
            }
          }
          return result;
        });
  }

  /// Guarda la plantilla de Word de un tipo de documento y deja anotados sus
  /// marcadores, para poder avisar después qué columnas debe traer el Excel.
  Future<PlantillaDocumento> guardarPlantilla({
    required String empresaId,
    required String tipo,
    required Uint8List bytes,
    required String fileName,
    required String userId,
  }) async {
    if (!DocumentoFinalizacionTipo.isValid(tipo)) {
      throw ArgumentError('Tipo de documento desconocido.');
    }
    if (!fileName.toLowerCase().endsWith('.docx')) {
      throw ArgumentError('La plantilla debe ser un archivo .docx de Word.');
    }
    _validarTamano(bytes);

    // Se leen los marcadores antes de guardar: si el archivo no es un .docx
    // válido, revienta aquí y no queda una plantilla rota en Storage.
    final Set<String> marcadores;
    try {
      marcadores = marcadoresDePlantilla(bytes);
    } catch (_) {
      throw ArgumentError(
        'No se pudo leer la plantilla. Verifica que sea un .docx de Word y no '
        'un .doc antiguo ni un PDF renombrado.',
      );
    }
    if (marcadores.isEmpty) {
      throw ArgumentError(
        'La plantilla no tiene marcadores. Escribe en el Word, donde va cada '
        'dato, algo como {{NOMBRE}} o {{CARGO}}.',
      );
    }

    final path =
        'talento_humano/finalizacion/plantillas/$empresaId/'
        '${tipo}_${DateTime.now().millisecondsSinceEpoch}_'
        '${_nombreSeguro(fileName)}';
    final ref = _storage.ref(path);
    await ref.putData(
      bytes,
      SettableMetadata(contentType: _contentType(fileName)),
    );
    final url = await ref.getDownloadURL();

    final ordenados = marcadores.toList()..sort();
    await _db.collection(plantillasCollection).doc('${empresaId}_$tipo').set({
      'empresaId': empresaId,
      'tipo': tipo,
      'nombre': fileName.trim(),
      'url': url,
      'storagePath': path,
      'marcadores': ordenados,
      'subidaPor': userId,
      'fecha': Timestamp.now(),
      'actualizadoAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return PlantillaDocumento(
      tipo: tipo,
      nombre: fileName.trim(),
      url: url,
      storagePath: path,
      marcadores: ordenados,
      subidaAt: DateTime.now(),
      subidaPor: userId,
    );
  }

  /// Descarga los bytes de una plantilla guardada para volver a combinarla.
  Future<Uint8List> leerPlantilla(PlantillaDocumento plantilla) async {
    final bytes = await _storage
        .ref(plantilla.storagePath)
        .getData(maxBytes);
    if (bytes == null) {
      throw StateError('No fue posible descargar la plantilla guardada.');
    }
    return bytes;
  }

  /// Marca si a la persona le corresponde el certificado de cesantías.
  ///
  /// Crea la carpeta si no existía: marcar a alguien es la forma natural de
  /// empezar a prepararle sus documentos antes de tener un solo archivo.
  Future<void> marcarCesantias({
    required String empresaId,
    required String cedula,
    required String nombre,
    required bool aplica,
    required String userId,
  }) async {
    await _db
        .collection(carpetasCollection)
        .doc(carpetaId(empresaId, cedula))
        .set({
          'empresaId': empresaId,
          'cedula': cedula,
          'nombre': nombre,
          'aplicaCesantias': aplica,
          'actualizadoPor': userId,
          'actualizadoAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  /// Archiva un documento en la carpeta de una persona. Es lo que el
  /// trabajador va a descargar, así que se guarda por tipo y no en una lista:
  /// subir la carta laboral dos veces reemplaza, no duplica.
  Future<void> subirDocumento({
    required String empresaId,
    required String cedula,
    required String nombre,
    required String tipo,
    required Uint8List bytes,
    required String fileName,
    required String userId,
  }) async {
    if (!DocumentoFinalizacionTipo.isValid(tipo)) {
      throw ArgumentError('Tipo de documento desconocido.');
    }
    if (cedula.trim().isEmpty) {
      throw ArgumentError('No se puede archivar sin la cédula de la persona.');
    }
    _validarTamano(bytes);

    final path =
        'talento_humano/finalizacion/$empresaId/$cedula/'
        '${tipo}_${DateTime.now().millisecondsSinceEpoch}_'
        '${_nombreSeguro(fileName)}';
    final ref = _storage.ref(path);
    await ref.putData(
      bytes,
      SettableMetadata(contentType: _contentType(fileName)),
    );
    final url = await ref.getDownloadURL();

    await _db
        .collection(carpetasCollection)
        .doc(carpetaId(empresaId, cedula))
        .set({
          'empresaId': empresaId,
          'cedula': cedula,
          'nombre': nombre,
          'documentos': {
            tipo: {
              'nombre': fileName.trim(),
              'url': url,
              'storagePath': path,
              'subidoPor': userId,
              'fecha': Timestamp.now(),
            },
          },
          'actualizadoPor': userId,
          'actualizadoAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  /// Quita un documento de la carpeta. El archivo se borra de Storage: dejarlo
  /// suelto guardaría un papel laboral de una persona sin nada que lo enlace.
  Future<void> eliminarDocumento({
    required CarpetaFinalizacion carpeta,
    required String tipo,
    required String userId,
  }) async {
    final documento = carpeta[tipo];
    if (documento == null) return;
    await _db.collection(carpetasCollection).doc(carpeta.id).update({
      'documentos.$tipo': FieldValue.delete(),
      'actualizadoPor': userId,
      'actualizadoAt': FieldValue.serverTimestamp(),
    });
    if (documento.storagePath.isNotEmpty) {
      try {
        await _storage.ref(documento.storagePath).delete();
      } catch (_) {
        // El registro ya no apunta al archivo; que Storage falle no debe
        // dejar la carpeta a medias.
      }
    }
  }

  void _validarTamano(Uint8List bytes) {
    if (bytes.isEmpty) throw ArgumentError('El archivo está vacío.');
    if (bytes.lengthInBytes > maxBytes) {
      throw ArgumentError('El archivo supera el límite de 15 MB.');
    }
  }

  static String _nombreSeguro(String fileName) =>
      fileName.trim().replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_');

  static String _contentType(String fileName) {
    final extension = fileName.toLowerCase().split('.').last;
    switch (extension) {
      case 'pdf':
        return 'application/pdf';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.'
            'wordprocessingml.document';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.'
            'spreadsheetml.sheet';
      case 'zip':
        return 'application/zip';
      default:
        return 'application/octet-stream';
    }
  }
}
