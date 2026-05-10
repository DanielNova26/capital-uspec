import 'package:cloud_firestore/cloud_firestore.dart';

const String kInterventoriaAppId = 'interventoriadashboard';

const String kRolInterventoriaAdmin = 'admin_interventoria';
const String kRolInterventoriaRegistrador = 'registrador_interventoria';
const String kRolInterventoriaRevisor = 'revisor_interventoria';
const String kRolInterventoriaGerente = 'gerente_interventoria';
const String kRolInterventoriaDirectivo = 'directivo_interventoria';
const String kRolInterventoriaConsulta = 'consulta_interventoria';

const List<String> kInterventoriaRoles = [
  kRolInterventoriaAdmin,
  kRolInterventoriaRegistrador,
  kRolInterventoriaRevisor,
  kRolInterventoriaGerente,
  kRolInterventoriaDirectivo,
  kRolInterventoriaConsulta,
];

const Map<String, String> kInterventoriaRoleLabels = {
  kRolInterventoriaAdmin: 'Administrador',
  kRolInterventoriaRegistrador: 'Registrador',
  kRolInterventoriaRevisor: 'Revisor OCR',
  kRolInterventoriaGerente: 'Gerente',
  kRolInterventoriaDirectivo: 'Directivo',
  kRolInterventoriaConsulta: 'Consulta',
};

const Set<String> kInterventoriaRolesEscritura = {
  kRolInterventoriaAdmin,
  kRolInterventoriaRegistrador,
  kRolInterventoriaRevisor,
};

const Set<String> kInterventoriaRolesDirectivos = {
  kRolInterventoriaAdmin,
  kRolInterventoriaGerente,
  kRolInterventoriaDirectivo,
};

const List<InterventoriaCategoria> kInterventoriaCategorias = [
  InterventoriaCategoria('conceptoSanitario', 'Concepto Sanitario'),
  InterventoriaCategoria('horario', '1. Horario'),
  InterventoriaCategoria('instalacionesFisicas', '2. Instalaciones fisicas'),
  InterventoriaCategoria('almacenamiento', '3. Almacenamiento'),
  InterventoriaCategoria('equipos', '4. Equipos'),
  InterventoriaCategoria(
    'condicionesProduccion',
    '5. Condiciones de produccion',
  ),
  InterventoriaCategoria(
    'caracteristicasAlimentos',
    '6. Caracteristicas de los alimentos',
  ),
  InterventoriaCategoria('personalManipulador', '7. Personal manipulador'),
  InterventoriaCategoria(
    'condicionesSaneamiento',
    '8. Condiciones de saneamiento',
  ),
  InterventoriaCategoria(
    'condicionesTransporte',
    '9. Condiciones de transporte',
  ),
  InterventoriaCategoria(
    'aseguramientoControlCalidad',
    '10. Aseguramiento y control de calidad',
  ),
  InterventoriaCategoria(
    'seguridadSaludTrabajo',
    '11. Seg. y Salud en el trabajo',
  ),
];

class InterventoriaCategoria {
  final String key;
  final String label;

  const InterventoriaCategoria(this.key, this.label);
}

class CentroCostoRef {
  final String centroId;
  final String empresaId;
  final String codigo;
  final String nombre;

  const CentroCostoRef({
    required this.centroId,
    required this.empresaId,
    required this.codigo,
    required this.nombre,
  });

  factory CentroCostoRef.fromMap(String id, Map<String, dynamic> data) {
    final centroId = (data['centroId'] ?? id).toString().trim();
    return CentroCostoRef(
      centroId: centroId.isEmpty ? id : centroId,
      empresaId: (data['empresaId'] ?? '').toString().trim(),
      codigo: (data['codigo'] ?? '').toString().trim(),
      nombre: (data['nombre'] ?? centroId).toString().trim(),
    );
  }
}

class InterventoriaItem {
  final String key;
  final String label;
  final double? valor;
  final bool noEvaluado;
  final String fuente;
  final double? confianzaOcr;
  final String observacion;

  const InterventoriaItem({
    required this.key,
    required this.label,
    this.valor,
    this.noEvaluado = false,
    this.fuente = 'manual',
    this.confianzaOcr,
    this.observacion = '',
  });

  factory InterventoriaItem.empty(InterventoriaCategoria categoria) =>
      InterventoriaItem(key: categoria.key, label: categoria.label);

  factory InterventoriaItem.fromMap(String key, Map<String, dynamic> data) {
    final rawValor = data['valor'];
    return InterventoriaItem(
      key: (data['key'] ?? key).toString(),
      label: (data['label'] ?? key).toString(),
      valor: rawValor is num
          ? rawValor.toDouble()
          : double.tryParse((rawValor ?? '').toString()),
      noEvaluado: data['noEvaluado'] == true || data['estado'] == 'no_evaluado',
      fuente: (data['fuente'] ?? 'manual').toString(),
      confianzaOcr: data['confianzaOcr'] is num
          ? (data['confianzaOcr'] as num).toDouble()
          : null,
      observacion: (data['observacion'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toMap() => {
    'key': key,
    'label': label,
    'valor': valor,
    'noEvaluado': noEvaluado,
    'estado': noEvaluado ? 'no_evaluado' : 'evaluado',
    'fuente': fuente,
    'confianzaOcr': confianzaOcr,
    'observacion': observacion,
  };

  InterventoriaItem copyWith({
    double? valor,
    bool? noEvaluado,
    String? fuente,
    double? confianzaOcr,
    String? observacion,
    bool clearValor = false,
  }) => InterventoriaItem(
    key: key,
    label: label,
    valor: clearValor ? null : (valor ?? this.valor),
    noEvaluado: noEvaluado ?? this.noEvaluado,
    fuente: fuente ?? this.fuente,
    confianzaOcr: confianzaOcr ?? this.confianzaOcr,
    observacion: observacion ?? this.observacion,
  );
}

class InterventoriaAdjunto {
  final String url;
  final String nombre;
  final String path;
  final String contentType;
  final String origen;
  final Timestamp fechaSubida;

  const InterventoriaAdjunto({
    required this.url,
    required this.nombre,
    required this.path,
    required this.contentType,
    required this.origen,
    required this.fechaSubida,
  });

  factory InterventoriaAdjunto.fromMap(Map<String, dynamic> data) =>
      InterventoriaAdjunto(
        url: (data['url'] ?? '').toString(),
        nombre: (data['nombre'] ?? '').toString(),
        path: (data['path'] ?? '').toString(),
        contentType: (data['contentType'] ?? '').toString(),
        origen: (data['origen'] ?? 'web').toString(),
        fechaSubida: data['fechaSubida'] as Timestamp? ?? Timestamp.now(),
      );

  Map<String, dynamic> toMap() => {
    'url': url,
    'nombre': nombre,
    'path': path,
    'contentType': contentType,
    'origen': origen,
    'fechaSubida': fechaSubida,
  };
}

class InterventoriaVisita {
  final String id;
  final String empresaId;
  final String centroCostoId;
  final String centroCostoCodigo;
  final String centroCostoNombre;
  final Timestamp fechaVisita;
  final Timestamp fechaRegistro;
  final String creadoPor;
  final String estado;
  final double porcentajeGeneral;
  final Map<String, InterventoriaItem> items;
  final List<InterventoriaAdjunto> adjuntos;
  final String actaOriginalUrl;
  final String ocrTextoExtraido;
  final Map<String, dynamic> ocrDatosDetectados;
  final bool ocrRevisado;
  final String observaciones;
  final Timestamp createdAt;
  final Timestamp? updatedAt;

  const InterventoriaVisita({
    this.id = '',
    required this.empresaId,
    required this.centroCostoId,
    required this.centroCostoCodigo,
    required this.centroCostoNombre,
    required this.fechaVisita,
    required this.fechaRegistro,
    required this.creadoPor,
    this.estado = 'registrada',
    required this.porcentajeGeneral,
    required this.items,
    this.adjuntos = const [],
    this.actaOriginalUrl = '',
    this.ocrTextoExtraido = '',
    this.ocrDatosDetectados = const {},
    this.ocrRevisado = false,
    this.observaciones = '',
    required this.createdAt,
    this.updatedAt,
  });

  factory InterventoriaVisita.fromMap(String id, Map<String, dynamic> data) {
    final rawItems = (data['itemsEvaluacion'] as Map?) ?? const {};
    final items = <String, InterventoriaItem>{};
    for (final categoria in kInterventoriaCategorias) {
      final raw = rawItems[categoria.key];
      if (raw is Map) {
        items[categoria.key] = InterventoriaItem.fromMap(
          categoria.key,
          raw.cast<String, dynamic>(),
        );
      } else {
        items[categoria.key] = InterventoriaItem.empty(categoria);
      }
    }
    return InterventoriaVisita(
      id: id,
      empresaId: (data['empresaId'] ?? '').toString(),
      centroCostoId: (data['centroCostoId'] ?? '').toString(),
      centroCostoCodigo: (data['centroCostoCodigo'] ?? '').toString(),
      centroCostoNombre: (data['centroCostoNombre'] ?? '').toString(),
      fechaVisita: data['fechaVisita'] as Timestamp? ?? Timestamp.now(),
      fechaRegistro: data['fechaRegistro'] as Timestamp? ?? Timestamp.now(),
      creadoPor: (data['creadoPor'] ?? '').toString(),
      estado: (data['estado'] ?? 'registrada').toString(),
      porcentajeGeneral: data['porcentajeGeneral'] is num
          ? (data['porcentajeGeneral'] as num).toDouble()
          : 0,
      items: items,
      adjuntos: ((data['imagenesActa'] as List?) ?? const [])
          .whereType<Map>()
          .map((m) => InterventoriaAdjunto.fromMap(m.cast<String, dynamic>()))
          .toList(),
      actaOriginalUrl: (data['actaOriginalUrl'] ?? '').toString(),
      ocrTextoExtraido: (data['ocrTextoExtraido'] ?? '').toString(),
      ocrDatosDetectados: ((data['ocrDatosDetectados'] as Map?) ?? const {})
          .cast<String, dynamic>(),
      ocrRevisado: data['ocrRevisado'] == true,
      observaciones: (data['observaciones'] ?? '').toString(),
      createdAt: data['createdAt'] as Timestamp? ?? Timestamp.now(),
      updatedAt: data['updatedAt'] as Timestamp?,
    );
  }

  Map<String, dynamic> toMap() => {
    'empresaId': empresaId,
    'centroCostoId': centroCostoId,
    'centroCostoCodigo': centroCostoCodigo,
    'centroCostoNombre': centroCostoNombre,
    'fechaVisita': fechaVisita,
    'fechaRegistro': fechaRegistro,
    'creadoPor': creadoPor,
    'estado': estado,
    'porcentajeGeneral': porcentajeGeneral,
    'itemsEvaluacion': items.map((key, value) => MapEntry(key, value.toMap())),
    'totalCondicionesServicio': porcentajeGeneral,
    'imagenesActa': adjuntos.map((a) => a.toMap()).toList(),
    'actaOriginalUrl': actaOriginalUrl,
    'ocrTextoExtraido': ocrTextoExtraido,
    'ocrDatosDetectados': ocrDatosDetectados,
    'ocrRevisado': ocrRevisado,
    'observaciones': observaciones,
    'createdAt': createdAt,
    'updatedAt': FieldValue.serverTimestamp(),
  };
}

class InterventoriaRolDoc {
  final String id;
  final String empresaId;
  final String userId;
  final String cedula;
  final String nombre;
  final String rol;
  final Timestamp createdAt;

  const InterventoriaRolDoc({
    this.id = '',
    required this.empresaId,
    required this.userId,
    required this.cedula,
    required this.nombre,
    required this.rol,
    required this.createdAt,
  });

  factory InterventoriaRolDoc.fromMap(String id, Map<String, dynamic> data) =>
      InterventoriaRolDoc(
        id: id,
        empresaId: (data['empresaId'] ?? '').toString(),
        userId: (data['userId'] ?? '').toString(),
        cedula: (data['cedula'] ?? '').toString(),
        nombre: (data['nombre'] ?? '').toString(),
        rol: (data['rol'] ?? '').toString(),
        createdAt: data['createdAt'] as Timestamp? ?? Timestamp.now(),
      );

  Map<String, dynamic> toMap() => {
    'empresaId': empresaId,
    'userId': userId,
    'cedula': cedula,
    'nombre': nombre,
    'rol': rol,
    'createdAt': createdAt,
  };
}

Map<String, InterventoriaItem> defaultInterventoriaItems() => {
  for (final categoria in kInterventoriaCategorias)
    categoria.key: InterventoriaItem.empty(categoria),
};

double calcularPorcentajeGeneral(Map<String, InterventoriaItem> items) {
  final evaluados = items.values
      .where((item) => !item.noEvaluado && item.valor != null)
      .map((item) => item.valor!.clamp(0, 100).toDouble())
      .toList();
  if (evaluados.isEmpty) return 0;
  final total = evaluados.fold<double>(
    0,
    (accumulated, value) => accumulated + value,
  );
  return double.parse((total / evaluados.length).toStringAsFixed(2));
}

String interventoriaSemaforo(double porcentaje) {
  if (porcentaje >= 90) return 'verde';
  if (porcentaje >= 70) return 'amarillo';
  return 'rojo';
}
