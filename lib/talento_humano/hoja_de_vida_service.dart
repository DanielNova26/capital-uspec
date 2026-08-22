// lib/talento_humano/hoja_de_vida_service.dart
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

/// Estado de revisión de la hoja de vida desde Talento Humano.
enum EstadoRevision { sinEnviar, enRevision, aprobado, requiereCambios }

extension EstadoRevisionX on EstadoRevision {
  String get firestoreValue => const {
    EstadoRevision.sinEnviar: 'sin_enviar',
    EstadoRevision.enRevision: 'en_revision',
    EstadoRevision.aprobado: 'aprobado',
    EstadoRevision.requiereCambios: 'requiere_cambios',
  }[this]!;

  static EstadoRevision fromString(String? value) =>
      const {
        'en_revision': EstadoRevision.enRevision,
        'aprobado': EstadoRevision.aprobado,
        'requiere_cambios': EstadoRevision.requiereCambios,
      }[value] ??
      EstadoRevision.sinEnviar;
}

class HojaDeVidaService {
  static const _col = 'TBL_USUARIOS';
  static const _sub = 'hoja_de_vida';
  static const _docId = 'datos';

  final _db = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;

  CollectionReference<Map<String, dynamic>> get _usuarios =>
      _db.collection(_col);

  Future<List<HvCatalogItem>> getDepartamentos() async {
    final snap = await _db.collection('TBL_DEPARTAMENTOS').get();
    final items = snap.docs
        .map((doc) {
          final data = doc.data();
          return HvCatalogItem(
            code: (data['cod_dane'] ?? doc.id).toString().trim(),
            name: (data['nombre'] ?? doc.id).toString().trim(),
          );
        })
        .where((item) => item.code.isNotEmpty && item.name.isNotEmpty)
        .toList();
    items.sort((a, b) => a.name.compareTo(b.name));
    return items;
  }

  Future<List<HvCatalogItem>> getCiudades(String departamentoCode) async {
    final dep = departamentoCode.trim();
    if (dep.isEmpty) return [];
    final snap = await _db
        .collection('TBL_CIUDADES')
        .where('cod_departamento', isEqualTo: dep)
        .get();
    final items = snap.docs
        .map((doc) {
          final data = doc.data();
          return HvCatalogItem(
            code: (data['cod_dane'] ?? doc.id).toString().trim(),
            name: (data['nombre'] ?? doc.id).toString().trim(),
          );
        })
        .where((item) => item.code.isNotEmpty && item.name.isNotEmpty)
        .toList();
    items.sort((a, b) => a.name.compareTo(b.name));
    return items;
  }

  // ── Resolución de documento ─────────────────────────────────────────────

  /// Devuelve la referencia al doc principal del usuario (puede ser ID=cedula
  /// o ID=usuario).  Busca primero por doc directo, luego por campo cedula.
  Future<DocumentReference<Map<String, dynamic>>> resolveDoc(
    String userId,
  ) async {
    final direct = _usuarios.doc(userId);
    final snap = await direct.get();
    if (snap.exists) return direct;

    final q = await _usuarios.where('cedula', isEqualTo: userId).limit(1).get();
    if (q.docs.isNotEmpty) return q.docs.first.reference;
    return direct;
  }

  // ── Leer hoja de vida ────────────────────────────────────────────────────

  /// Lee la hoja de vida desde la subcollection.  Si no existe, hace fallback
  /// a los campos planos del documento principal (usuarios ya registrados).
  Future<Map<String, dynamic>> getHojaDeVida(String userId) async {
    final docRef = await resolveDoc(userId);
    final mainSnap = await docRef.get();
    final flatData = mainSnap.exists
        ? _fromFlatFields(mainSnap.data()!)
        : <String, dynamic>{};

    final subSnap = await docRef.collection(_sub).doc(_docId).get();
    if (subSnap.exists && (subSnap.data()?.isNotEmpty ?? false)) {
      return _mergeCvData(flatData, subSnap.data()!);
    }
    return flatData;
  }

  static const _cvKeys = [
    'primerNombre',
    'segundoNombre',
    'primerApellido',
    'segundoApellido',
    'lugarExpedicion',
    'lugarExpedicionDepartamentoCod',
    'lugarExpedicionDepartamentoNombre',
    'lugarExpedicionCiudadCod',
    'lugarExpedicionCiudadNombre',
    'email',
    'telefono',
    'direccion',
    'ciudad',
    'residenciaDepartamentoCod',
    'residenciaDepartamentoNombre',
    'residenciaCiudadCod',
    'residenciaCiudadNombre',
    'barrio',
    'eps',
    'fondoPensiones',
    'fondoCesantias',
    'fotoUrl',
    'cedulaDocUrl',
    'epsUrl',
    'pensionUrl',
    'cesantiasUrl',
    'estadoCivil',
    'numeroHijos',
    'tipoSangre',
    'contactoEmergenciaNombre',
    'contactoEmergenciaTelefono',
    'fechaNacimiento',
    'lugarNacimiento',
    'nacimientoDepartamentoCod',
    'nacimientoDepartamentoNombre',
    'nacimientoCiudadCod',
    'nacimientoCiudadNombre',
    'edad',
    'genero',
    'personasCargo',
    'estrato',
    'tipoVehiculo',
    'procUrl',
    'contrUrl',
    'polUrl',
    'medUrl',
    'bachInst',
    'bachFecha',
    'bachillerUrl',
    'hasUniversity',
    'uniInst',
    'uniCarr',
    'uniFecha',
    'uniUrl',
    'hasTarjetaProf',
    'tarjetaNumero',
    'tarjetaUrl',
    'hasSecondCareer',
    'secInst',
    'secCarr',
    'secFecha',
    'secUrl',
    'hasEspecializacion',
    'espInst',
    'espProg',
    'espFecha',
    'espUrl',
    'hasMaestria',
    'maeInst',
    'maeProg',
    'maeFecha',
    'maeUrl',
    'hasCertificados',
    'certificados',
    'experiencias',
    'correctionRequestedAt',
    'correctionUpdatedAt',
    'correctionSubmittedAt',
    'correctionStatus',
    'correctionNote',
    'correctionRequestedBy',
    'correctionRequestedByName',
  ];

  Map<String, dynamic> _fromFlatFields(Map<String, dynamic> data) {
    final cv = <String, dynamic>{
      for (final k in _cvKeys)
        if (data.containsKey(k)) k: data[k],
    };

    cv['primerNombre'] = _firstNonEmpty([
      cv['primerNombre'],
      data['primer_nombre'],
      _namePart(data['nombres'], 0),
      _namePart(data['nombreCompleto'] ?? data['nombre'], 0),
    ]);
    cv['segundoNombre'] = _firstNonEmpty([
      cv['segundoNombre'],
      data['segundo_nombre'],
      _remainingNamePart(data['nombres'], 1),
    ]);
    cv['primerApellido'] = _firstNonEmpty([
      cv['primerApellido'],
      data['primer_apellido'],
      _namePart(data['apellidos'], 0),
      _lastNameFallback(data['nombreCompleto'] ?? data['nombre']),
    ]);
    cv['segundoApellido'] = _firstNonEmpty([
      cv['segundoApellido'],
      data['segundo_apellido'],
      _remainingNamePart(data['apellidos'], 1),
    ]);
    cv['email'] = _firstNonEmpty([
      cv['email'],
      data['correo'],
      data['email'],
      data['mail'],
    ]);
    cv['telefono'] = _firstNonEmpty([
      cv['telefono'],
      data['celular'],
      data['telefonoCelular'],
      data['telefono_contacto'],
    ]);
    cv['direccion'] = _firstNonEmpty([
      cv['direccion'],
      data['direccionResidencia'],
      data['direccion_residencia'],
    ]);
    cv['ciudad'] = _firstNonEmpty([
      cv['ciudad'],
      data['municipio'],
      data['ciudadResidencia'],
    ]);
    cv['eps'] = _firstNonEmpty([cv['eps'], data['EPS']]);
    cv['fondoPensiones'] = _firstNonEmpty([
      cv['fondoPensiones'],
      data['fondoPension'],
      data['fondo_pensiones'],
      data['pension'],
    ]);
    cv['fondoCesantias'] = _firstNonEmpty([
      cv['fondoCesantias'],
      data['fondoCesantia'],
      data['fondo_cesantias'],
      data['cesantias'],
    ]);
    cv['fechaNacimiento'] = _firstNonEmpty([
      cv['fechaNacimiento'],
      _formatDateLike(data['fecha_nacimiento']),
      _formatDateLike(data['fechaNacimiento']),
    ]);

    if (data['needsRevision'] == true) {
      cv['estadoRevision'] = EstadoRevision.requiereCambios.firestoreValue;
      cv['revisionNota'] = data['revisionNote'];
    } else if (data['registered'] == true) {
      cv['estadoRevision'] = EstadoRevision.enRevision.firestoreValue;
    } else {
      cv['estadoRevision'] = EstadoRevision.sinEnviar.firestoreValue;
    }
    for (final key in const [
      'correctionRequestedAt',
      'correctionUpdatedAt',
      'correctionSubmittedAt',
      'correctionStatus',
      'correctionNote',
      'correctionRequestedBy',
      'correctionRequestedByName',
    ]) {
      if (data.containsKey(key)) cv[key] = data[key];
    }
    return cv;
  }

  Map<String, dynamic> _mergeCvData(
    Map<String, dynamic> base,
    Map<String, dynamic> override,
  ) {
    final merged = <String, dynamic>{...base};
    override.forEach((key, value) {
      if (!_isEmptyValue(value)) {
        merged[key] = value;
      }
    });
    return merged;
  }

  bool _isEmptyValue(dynamic value) {
    if (value == null) return true;
    if (value is String) return value.trim().isEmpty;
    if (value is Iterable) return value.isEmpty;
    if (value is Map) return value.isEmpty;
    return false;
  }

  String _firstNonEmpty(List<dynamic> values) {
    for (final value in values) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  String _namePart(dynamic value, int index) {
    final parts = value
        ?.toString()
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts == null || index >= parts.length) return '';
    return parts[index];
  }

  String _remainingNamePart(dynamic value, int startIndex) {
    final parts = value
        ?.toString()
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts == null || startIndex >= parts.length) return '';
    return parts.sublist(startIndex).join(' ');
  }

  String _lastNameFallback(dynamic value) {
    final parts = value
        ?.toString()
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts == null || parts.length < 2) return '';
    return parts.last;
  }

  String _formatDateLike(dynamic value) {
    if (value == null) return '';
    if (value is Timestamp) {
      final d = value.toDate();
      return '${d.day.toString().padLeft(2, '0')}/'
          '${d.month.toString().padLeft(2, '0')}/${d.year}';
    }
    if (value is DateTime) {
      return '${value.day.toString().padLeft(2, '0')}/'
          '${value.month.toString().padLeft(2, '0')}/${value.year}';
    }
    return value.toString().trim();
  }

  // ── Guardar hoja de vida (empleado) ─────────────────────────────────────

  Future<void> saveHojaDeVida(
    String userId,
    String empresaId,
    Map<String, dynamic> cvData,
  ) async {
    final docRef = await resolveDoc(userId);
    final subRef = docRef.collection(_sub).doc(_docId);
    final currentSub = await subRef.get();
    final currentMain = await docRef.get();
    final currentSubData = currentSub.data() ?? <String, dynamic>{};
    final currentMainData = currentMain.data() ?? <String, dynamic>{};
    final correcting =
        currentSubData['estadoRevision'] ==
            EstadoRevision.requiereCambios.firestoreValue ||
        currentMainData['estadoHojaDeVida'] ==
            EstadoRevision.requiereCambios.firestoreValue ||
        currentMainData['needsRevision'] == true;
    final batch = _db.batch();

    final subUpdate = <String, dynamic>{
      ...cvData,
      'estadoRevision': EstadoRevision.enRevision.firestoreValue,
      'revisionNota': null,
      'fechaEnvio': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (correcting) {
      subUpdate.addAll({
        'correctionStatus': 'reenviada',
        'correctionSubmittedAt': FieldValue.serverTimestamp(),
        'correctionUpdatedAt': FieldValue.serverTimestamp(),
      });
    }

    batch.set(subRef, subUpdate, SetOptions(merge: true));

    // Actualiza el doc raíz con nombre y foto para que aparezca en la lista TH
    final mainUpdate = <String, dynamic>{
      'estadoHojaDeVida': EstadoRevision.enRevision.firestoreValue,
      'registered': true,
      'needsRevision': false,
      'revisionNote': null,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (correcting) {
      mainUpdate.addAll({
        'correctionStatus': 'reenviada',
        'correctionSubmittedAt': FieldValue.serverTimestamp(),
        'correctionUpdatedAt': FieldValue.serverTimestamp(),
      });
    }
    final nombre = (cvData['primerNombre'] as String?)?.trim() ?? '';
    if (nombre.isNotEmpty) mainUpdate['primerNombre'] = nombre;
    final apellido = (cvData['primerApellido'] as String?)?.trim() ?? '';
    if (apellido.isNotEmpty) mainUpdate['primerApellido'] = apellido;
    final nombre2 = (cvData['segundoNombre'] as String?)?.trim() ?? '';
    if (nombre2.isNotEmpty) mainUpdate['segundoNombre'] = nombre2;
    final apellido2 = (cvData['segundoApellido'] as String?)?.trim() ?? '';
    if (apellido2.isNotEmpty) mainUpdate['segundoApellido'] = apellido2;
    final foto = cvData['fotoUrl'] as String?;
    if (foto != null && foto.isNotEmpty) mainUpdate['fotoUrl'] = foto;

    batch.set(docRef, mainUpdate, SetOptions(merge: true));

    await batch.commit();
  }

  /// Guarda un borrador parcial sin cambiar el estado de revisión.
  Future<void> saveDraft(String userId, Map<String, dynamic> cvData) async {
    final docRef = await resolveDoc(userId);
    final subRef = docRef.collection(_sub).doc(_docId);
    final currentSub = await subRef.get();
    final currentMain = await docRef.get();
    final currentSubData = currentSub.data() ?? <String, dynamic>{};
    final currentMainData = currentMain.data() ?? <String, dynamic>{};
    final correcting =
        currentSubData['estadoRevision'] ==
            EstadoRevision.requiereCambios.firestoreValue ||
        currentMainData['estadoHojaDeVida'] ==
            EstadoRevision.requiereCambios.firestoreValue ||
        currentMainData['needsRevision'] == true;

    final batch = _db.batch();
    final subUpdate = <String, dynamic>{
      ...cvData,
      'draftUpdatedAt': FieldValue.serverTimestamp(),
    };
    if (correcting) {
      subUpdate.addAll({
        'correctionStatus': 'editando',
        'correctionUpdatedAt': FieldValue.serverTimestamp(),
      });
    }
    batch.set(subRef, subUpdate, SetOptions(merge: true));
    if (correcting) {
      batch.set(docRef, {
        'correctionStatus': 'editando',
        'correctionUpdatedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    await batch.commit();
  }

  // ── Subir archivo ────────────────────────────────────────────────────────

  /// Sube bytes a Storage bajo `hojas/{userId}/{tag}.{extension}` y retorna URL.
  Future<String> uploadFile(
    String userId,
    String tag,
    Uint8List bytes,
    String extension,
  ) async {
    final ref = _storage.ref('hojas/$userId/$tag.$extension');
    final normalizedExtension = extension.trim().toLowerCase();
    final contentType = switch (normalizedExtension) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      'pdf' => 'application/pdf',
      _ => 'application/octet-stream',
    };
    await ref.putData(bytes, SettableMetadata(contentType: contentType));
    return ref.getDownloadURL();
  }

  // ── Acciones de Talento Humano ───────────────────────────────────────────

  Future<void> aprobar(
    String userId,
    String revisadoPor,
    String revisadoPorNombre,
  ) async {
    final docRef = await resolveDoc(userId);
    final batch = _db.batch();

    batch.update(docRef.collection(_sub).doc(_docId), {
      'estadoRevision': EstadoRevision.aprobado.firestoreValue,
      'revisadoPor': revisadoPor,
      'revisadoPorNombre': revisadoPorNombre,
      'fechaRevision': FieldValue.serverTimestamp(),
      'revisionNota': null,
    });

    batch.update(docRef, {
      'estadoHojaDeVida': EstadoRevision.aprobado.firestoreValue,
      'needsRevision': false,
    });

    await batch.commit();
  }

  Future<void> solicitarCorreccion(
    String userId,
    String nota,
    String revisadoPor,
    String revisadoPorNombre,
  ) async {
    final docRef = await resolveDoc(userId);
    final batch = _db.batch();
    final correctionPayload = {
      'correctionRequestedAt': FieldValue.serverTimestamp(),
      'correctionUpdatedAt': null,
      'correctionSubmittedAt': null,
      'correctionStatus': 'pendiente',
      'correctionNote': nota,
      'correctionRequestedBy': revisadoPor,
      'correctionRequestedByName': revisadoPorNombre,
    };

    batch.update(docRef.collection(_sub).doc(_docId), {
      'estadoRevision': EstadoRevision.requiereCambios.firestoreValue,
      'revisionNota': nota,
      'revisadoPor': revisadoPor,
      'revisadoPorNombre': revisadoPorNombre,
      'fechaRevision': FieldValue.serverTimestamp(),
      ...correctionPayload,
    });

    batch.update(docRef, {
      'estadoHojaDeVida': EstadoRevision.requiereCambios.firestoreValue,
      'needsRevision': true,
      'revisionNote': nota,
      ...correctionPayload,
    });

    await batch.commit();
  }

  // ── Stream para lista de empleados (pantalla TH) ─────────────────────────

  Stream<QuerySnapshot<Map<String, dynamic>>> streamEmpleados(
    String empresaId,
  ) {
    return _usuarios.where('empresas', arrayContains: empresaId).snapshots();
  }

  /// Alternativa si el campo es `empresaId` en lugar del array `empresas`.
  Stream<QuerySnapshot<Map<String, dynamic>>> streamEmpleadosByEmpresaId(
    String empresaId,
  ) {
    return _usuarios.where('empresaId', isEqualTo: empresaId).snapshots();
  }

  EstadoRevision estadoFromDoc(Map<String, dynamic> data) =>
      EstadoRevisionX.fromString(data['estadoHojaDeVida'] as String?);

  // ── Consultas de tablas organizacionales ────────────────────────────────

  /// Datos org del empleado (cargo, área, jefe, centro de costos).
  Future<Map<String, dynamic>?> getOrgData(String cedula) async {
    final snap = await _db
        .collection('TBL_ESTRUCTURA_ORGANIZACIONAL')
        .doc(cedula)
        .get();
    return snap.exists ? snap.data() : null;
  }

  /// Nombres de áreas disponibles para filtros en la empresa.
  Future<List<String>> getAreaNames(String empresaId) async {
    final snap = await _db
        .collection('TBL_AREAS')
        .where('empresaId', isEqualTo: empresaId)
        .get();
    return snap.docs
        .map((d) => (d.data()['nombre'] as String?) ?? '')
        .where((n) => n.isNotEmpty)
        .toList()
      ..sort();
  }

  /// Nombres de cargos disponibles para filtros en la empresa.
  /// Lee `nombre` primero; cae a `descripcion` para registros legacy.
  Future<List<String>> getCargoNames(String empresaId) async {
    final snap = await _db
        .collection('TBL_CARGOS')
        .where('empresaId', isEqualTo: empresaId)
        .get();
    return snap.docs
        .map((d) {
          final data = d.data();
          final n = (data['nombre'] as String?)?.trim() ?? '';
          if (n.isNotEmpty) return n;
          return (data['descripcion'] as String?)?.trim() ?? '';
        })
        .where((n) => n.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
  }
}

class HvCatalogItem {
  final String code;
  final String name;

  const HvCatalogItem({required this.code, required this.name});
}
