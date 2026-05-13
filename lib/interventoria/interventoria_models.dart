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

const Map<String, List<String>> kInterventoriaItemsActaPorCategoria = {
  'conceptoSanitario': [
    'Cumplimiento de los horarios de entrega establecidos por la OTPA o acuerdos con el establecimiento.',
    'Concepto sanitario vigente o soportes de renovación ante la autoridad competente.',
    'Servicio libre de medida sanitaria de cierre total o parcial, con acciones correctivas si existen observaciones.',
  ],
  'instalacionesFisicas': [
    'Accesos y alrededores limpios, sin basuras, aguas estancadas o fuentes de contaminación.',
    'Áreas del servicio señalizadas, operativas y usadas para la actividad prevista.',
    'Mantenimiento de pisos, paredes, techos y media cañas en buen estado.',
    'Mantenimiento de ventanas, marcos, puertas y estanterías; aberturas protegidas contra plagas o contaminantes.',
    'Iluminación suficiente y lámparas protegidas en caso de rotura.',
    'Instalaciones eléctricas en buen estado, funcionales y sin riesgo de accidente laboral.',
    'Sistemas de evacuación de aguas residuales protegidos con tapas, sifones o rejillas.',
    'Mesones en buen estado, libres de grietas, porosidad o deterioro.',
    'Lavamanos de accionamiento no manual cerca del área de proceso.',
    'Instalaciones sanitarias en estado operativo y funcional.',
    'Letreros alusivos a BPM y lavado de manos, visibles y ubicados en áreas sanitarias y de proceso.',
    'Mensajes de “Espacio libre de humo, cigarrillo o tabaco”.',
    'Área exclusiva para almacenamiento temporal de productos no conformes.',
    'Área exclusiva para ensamble de raciones.',
    'Espacio físico exclusivo para depósito temporal de residuos sólidos.',
    'Área para limpieza y desinfección de utensilios y menaje.',
    'Instalación de medidores calibrados y certificados para verificar consumo de servicios públicos o acuerdos de pago cuando no estén independizados.',
  ],
  'almacenamiento': [
    'Fichas técnicas de materias primas acorde al listado de proveedores ofertados.',
    'Cumplimiento de la proyección del plan de compras según parte diario, minuta patrón y proveedores ofertados.',
    'Alimentos con fechas de vencimiento vigentes.',
    'Etiquetado y rotulado del empaque primario conforme a la normatividad vigente.',
    'Materias primas libres de contaminación biológica, química o física.',
    'Alimentos enlatados sin golpes, abolladuras, oxidación, hinchazón, tapa suelta o vencimiento expirado.',
    'Materias primas almacenadas según sus características naturales, evitando contaminación cruzada.',
    'Cumplimiento de distancias perimetrales en almacenamiento para permitir limpieza y verificación.',
    'Aplicación del método PEPS e identificación por rótulo de colores según OTM.',
    'Materias primas re envasadas o fraccionadas debidamente identificadas.',
    'Producto no conforme almacenado en el área dispuesta para tal fin, con registros actualizados.',
    'Ausencia de alimentos prohibidos, aditivos o saborizantes artificiales no permitidos.',
  ],
  'equipos': [
    'Equipos mínimos requeridos según el Anexo No. 5, en capacidad, suficiencia, volumen y funcionalidad.',
    'Equipos de materiales inertes, resistentes a la corrosión, fáciles de limpiar y desinfectar.',
    'Utensilios y menaje en materiales adecuados, buen estado y libres de deterioro.',
    'Tablas de corte según código de colores establecido en la OTM.',
    'Equipos de refrigeración y congelación funcionando, suficientes y calibrados.',
    'Entrega de menaje para PPL conforme a las especificaciones técnicas.',
    'Ausencia de menaje o equipos en desuso que generen contaminación.',
    'Carros transportadores inventariados, identificados, funcionales y en buen estado.',
    'Trampas de grasa funcionales, en buen estado y acordes con la capacidad instalada.',
    'Equipos de medición básicos completos y en óptimas condiciones.',
  ],
  'condicionesProduccion': [
    'Procedimiento para operación desde recepción de insumos hasta despacho del producto terminado.',
    'Implementación del procedimiento en prealistamiento y preparación de materias primas.',
    'Producto terminado servido a temperatura mayor a 60 °C y refrigerados no mayor a 4 °C ± 2 °C.',
    'Protocolo de control de temperatura desde recepción hasta distribución final.',
    'Plan de muestreo o control de gramaje con base en NTC ISO 2859 1.',
    'Utensilios estandarizados para garantizar gramaje de los componentes.',
    'Hielo rotulado, almacenado y manipulado en condiciones sanitarias.',
    'Servicio de producto terminado y dietas bajo condiciones que eviten contaminación cruzada.',
    'Raciones terapéuticas en empaque desechable para PPL con diagnósticos especiales, si aplica.',
    'Cumplimiento del protocolo de toma de contramuestras.',
    'Manejo adecuado de productos devueltos por la PPL, sin reproceso ni reelaboración.',
  ],
  'caracteristicasAlimentos': [
    'Cumplimiento de la rotación del ciclo de menú aprobado.',
    'Suministro de la totalidad de los componentes del menú verificado.',
    'Cumplimiento de intercambios permitidos e información a USPEC o interventoría.',
    'Soporte de aprobación cuando se suministre huevo o embutido como intercambio proteico.',
    'Entrega de salchicha conforme a características de la OTM y ficha técnica aprobada.',
    'Preparaciones con ingredientes correspondientes para cada tiempo de comida.',
    'No suministro de preparaciones prohibidas, aditivos o saborizantes no permitidos.',
    'Cumplimiento de gramajes de preparaciones del menú verificado en el ERON.',
    'Cumplimiento de gramajes para EP, UT y URI, cuando aplique.',
    'Calidad organoléptica del menú verificado en el ERON.',
    'Calidad organoléptica del menú para EP, UT y URI, cuando aplique.',
    'Cumplimiento de refrigerios nocturnos, rotación de componentes y frecuencia.',
    'Cumplimiento de alimentación diferencial para grupo étnico o convicción religiosa.',
    'Suministro de menú especial o ración para días festivos.',
    'Suministro de menú especial adicional en fechas notificadas.',
    'Entrega de refrigerios para PPL que salen de remisión.',
    'Cumplimiento del programa de tamizaje nutricional.',
    'Entrega de dietas terapéuticas conforme a la OTM y Manual de Dietas Terapéuticas.',
    'Rotulado de ración terapéutica según nombre del interno, patio y tipo de dieta.',
    'Registro y control diario de entrega de dietas terapéuticas.',
    'Soportes de revaloración, seguimiento, ajuste o retiro de dietas para PPL afiliada a regímenes de salud.',
    'Valoración nutricional inicial, seguimiento, ajuste o retiro de dietas de PPL con cobertura en salud.',
    'Suministro de raciones para gestantes y lactantes.',
    'Educación para lactancia materna exclusiva, alimentación complementaria y cuidados del menor.',
    'Valoración y seguimiento nutricional de gestantes y lactantes.',
    'Registros de renuncias a alimentación o dietas, cuando aplique.',
    'Socialización del ciclo de menús y actualizaciones conforme a la OTM.',
  ],
  'personalManipulador': [
    'Cumplimiento del personal mínimo requerido, perfil, frecuencia de visitas y soportes de asistencia o justificación.',
    'Cumplimiento de entrega de dotación completa al personal profesional y operativo.',
  ],
  'condicionesSaneamiento': [
    'Procedimiento definido e implementado para garantizar condiciones sanitarias y evitar contaminación cruzada.',
    'Paredes, medias cañas, pisos, mesones, ventanas, puertas y barreras de protección limpias.',
    'Techos limpios, sin hongos, con limpieza gestionada conforme a la OTM.',
    'Limpieza y desinfección de equipos, utensilios y carros transportadores.',
    'Instalaciones sanitarias limpias, dotadas y alejadas del área de producción.',
    'Productos químicos con fichas técnicas, concentraciones, modo de preparación y almacenamiento adecuado.',
    'Elementos de aseo e insumos para limpieza y desinfección, rotulados y organizados.',
    'Limpieza y desinfección del menaje para PPL o entrega mensual de kit de limpieza.',
    'Suministro de agua potable o plan de acción para garantizarlo.',
    'Tanque de almacenamiento de agua con capacidad, protección, identificación y registros de limpieza.',
    'Análisis diarios de pH y cloro residual en puntos de agua.',
    'Recipientes suficientes para residuos sólidos, identificados y en buen estado.',
    'Retiro de residuos sólidos mínimo tres veces al día y plano de rutas publicado.',
    'Limpieza y desinfección de trampas de grasa.',
    'Manejo de residuos sólidos aprovechables, líquidos y peligrosos articulado con el PIGA.',
    'Manejo del aceite vegetal usado conforme a la normatividad.',
    'Control de plagas conforme a ficha técnica, cronograma, registros y soportes.',
    'Servicio libre de huellas, presencia o daño causado por plagas.',
  ],
  'condicionesTransporte': [
    'Recibo de materias primas, insumos y alimentos conforme a lineamientos y horarios del establecimiento.',
    'Vehículos transportadores en condiciones físicas e higiénicas adecuadas y con documentación requerida.',
    'Transporte y distribución de alimentos según su naturaleza, en recipientes adecuados y sin contacto con el piso.',
    'Vehículos identificados con la leyenda “Transporte de alimentos”.',
    'Personal transportador con certificado de manipulación, vestimenta adecuada y licencia vigente.',
  ],
  'aseguramientoControlCalidad': [
    'Planes y programas de la OTM ajustados al establecimiento y socializados.',
    'Recibo de materias primas aplicando criterios de aceptación y rechazo.',
    'Formatos básicos para registros de producción.',
    'Programa de mantenimiento preventivo y correctivo de equipos.',
    'Calibración y verificación de equipos de medición.',
    'Muestreos microbiológicos conforme a frecuencia y parámetros establecidos.',
    'Laboratorio de toma de muestras conforme a requisitos de salud pública.',
    'Resultados microbiológicos conformes para microorganismos patógenos.',
    'Resultados microbiológicos conformes para indicadores de calidad, limpieza y desinfección.',
    'Análisis fisicoquímicos del agua conforme a la frecuencia establecida.',
    'Ausencia de brotes de Enfermedad Transmitida por Alimentos.',
    'Protocolo para manejo de posibles ETA.',
    'Control y registro de temperatura en equipos de frío.',
    'Hojas de vida y mantenimiento de carros transportadores.',
    'Sensibilización sobre proceso de higienización del menaje.',
    'Capacitaciones establecidas en la OTM, Resolución 2674 de 2013 y estudios previos.',
    'Programa de trazabilidad definido e implementado.',
    'Plan de contingencia específico del establecimiento.',
    'Planes de emergencia ajustados al establecimiento y socializados.',
    'Soportes relacionados con proyectos productivos, servicios públicos, bonificación de PPL y ARL, si aplica.',
    'No ingreso ni retiro de elementos prohibidos en el establecimiento.',
  ],
  'seguridadSaludTrabajo': [
    'Registros actualizados de capacitaciones en SST.',
    'Botiquín dotado conforme a su clasificación.',
    'Extintores señalizados, visibles, aptos y con inspección.',
    'Manta antifuego cerca de equipos de cocción.',
    'Política SST publicada y firmada; ruta de evacuación señalizada.',
    'Exámenes médicos ocupacionales de ingreso para personal externo.',
    'Entrega y uso de elementos de protección personal.',
    'Campanas o extractores de aire en funcionamiento, buen estado y ventilación adecuada.',
  ],
};

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
  final List<InterventoriaNota> observaciones;
  final Map<String, dynamic> meta;

  const InterventoriaItem({
    required this.key,
    required this.label,
    this.valor,
    this.noEvaluado = false,
    this.fuente = 'manual',
    this.confianzaOcr,
    this.observacion = '',
    this.observaciones = const [],
    this.meta = const {},
  });

  factory InterventoriaItem.empty(InterventoriaCategoria categoria) =>
      InterventoriaItem(key: categoria.key, label: categoria.label);

  factory InterventoriaItem.fromMap(String key, Map<String, dynamic> data) {
    final rawValor = data['valor'];
    final rawObservaciones =
        (data['observacionesDetalle'] as List?) ?? const [];
    final legacyObservacion = (data['observacion'] ?? '').toString();
    final observaciones = rawObservaciones
        .whereType<Map>()
        .map((m) => InterventoriaNota.fromMap(m.cast<String, dynamic>()))
        .where((n) => n.texto.trim().isNotEmpty)
        .toList();
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
      observacion: legacyObservacion,
      observaciones: observaciones.isNotEmpty
          ? observaciones
          : legacyObservacion.trim().isEmpty
          ? const []
          : [
              InterventoriaNota(
                texto: legacyObservacion.trim(),
                fuente: (data['fuente'] ?? 'manual').toString(),
              ),
            ],
      meta: ((data['meta'] as Map?) ?? const {}).cast<String, dynamic>(),
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
    'observacion': observaciones.isNotEmpty
        ? observaciones.map((n) => n.texto.trim()).join('\n')
        : observacion,
    'observacionesDetalle': observaciones.map((n) => n.toMap()).toList(),
    'meta': meta,
  };

  InterventoriaItem copyWith({
    double? valor,
    bool? noEvaluado,
    String? fuente,
    double? confianzaOcr,
    String? observacion,
    List<InterventoriaNota>? observaciones,
    Map<String, dynamic>? meta,
    bool clearValor = false,
  }) => InterventoriaItem(
    key: key,
    label: label,
    valor: clearValor ? null : (valor ?? this.valor),
    noEvaluado: noEvaluado ?? this.noEvaluado,
    fuente: fuente ?? this.fuente,
    confianzaOcr: confianzaOcr ?? this.confianzaOcr,
    observacion: observacion ?? this.observacion,
    observaciones: observaciones ?? this.observaciones,
    meta: meta ?? this.meta,
  );
}

class InterventoriaNota {
  final String aspecto;
  final String texto;
  final String fuente;
  final Timestamp? createdAt;

  const InterventoriaNota({
    this.aspecto = '',
    required this.texto,
    this.fuente = 'manual',
    this.createdAt,
  });

  factory InterventoriaNota.fromMap(Map<String, dynamic> data) =>
      InterventoriaNota(
        aspecto: (data['aspecto'] ?? '').toString(),
        texto: (data['texto'] ?? '').toString(),
        fuente: (data['fuente'] ?? 'manual').toString(),
        createdAt: data['createdAt'] as Timestamp?,
      );

  Map<String, dynamic> toMap() => {
    'aspecto': aspecto,
    'texto': texto,
    'fuente': fuente,
    'createdAt': createdAt ?? Timestamp.now(),
  };

  InterventoriaNota copyWith({
    String? aspecto,
    String? texto,
    String? fuente,
  }) => InterventoriaNota(
    aspecto: aspecto ?? this.aspecto,
    texto: texto ?? this.texto,
    fuente: fuente ?? this.fuente,
    createdAt: createdAt,
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
  final String? tipoActa;
  final String? tiempoComida;
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
    this.tipoActa,
    this.tiempoComida,
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
      tipoActa: data['tipoActa']?.toString(),
      tiempoComida: data['tiempoComida']?.toString(),
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
    'tipoActa': tipoActa,
    'tiempoComida': tiempoComida,
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

// ─────────────────────────────────────────────────────────────────────────────
// Hallazgos
// ─────────────────────────────────────────────────────────────────────────────

const List<String> kDptosInterventoria = [
  'ADMINISTRADOR',
  'BODEGA',
  'CALIDAD',
  'COMPRAS',
  'DIRECTIVA',
  'EQUIPO Y MENAJE',
  'INGENIERO DE PRODUCCIÓN',
  'MANTENIMIENTO',
  'NUTRICIONISTA',
  'PLANEACIÓN',
  'TALENTO HUMANO',
];

const List<String> kTiposActaInterventoria = ['REGULAR', 'INFRAESTRUCTURA'];

const List<String> kTiemposComidaInterventoria = [
  'DESAYUNO',
  'ALMUERZO',
  'CENA',
];

class InterventoriaHallazgo {
  final String id;
  final String empresaId;
  final String visitaId;
  final String centroCostoId;
  final String centroCostoNombre;
  final String grupoId;
  final String estado; // 'activo' | 'subsanado'
  final String? tipoActa;
  final String numeroHallazgo; // e.g. "1.1", "10.20"
  final String descripcion;
  final Timestamp fechaHallazgo;
  final bool persiste;
  final String dptoEncargado; // nombre del área para mostrar
  final String areaId;        // doc ID en TBL_AREAS (para buscar director)
  final String observaciones;
  final String planMejora;
  final double? valorCorreccion;
  final Timestamp? fechaSubsanacion;
  final String seguimiento;
  final String fuente; // 'manual' | 'ocr'
  final Timestamp createdAt;
  final Timestamp? updatedAt;

  const InterventoriaHallazgo({
    this.id = '',
    required this.empresaId,
    this.visitaId = '',
    required this.centroCostoId,
    required this.centroCostoNombre,
    this.grupoId = '',
    this.estado = 'activo',
    this.tipoActa,
    this.numeroHallazgo = '',
    required this.descripcion,
    required this.fechaHallazgo,
    this.persiste = false,
    this.dptoEncargado = '',
    this.areaId = '',
    this.observaciones = '',
    this.planMejora = '',
    this.valorCorreccion,
    this.fechaSubsanacion,
    this.seguimiento = '',
    this.fuente = 'manual',
    required this.createdAt,
    this.updatedAt,
  });

  bool get isSubsanado => estado == 'subsanado';

  int get seccion {
    final parts = numeroHallazgo.split('.');
    return int.tryParse(parts.first) ?? 0;
  }

  factory InterventoriaHallazgo.fromMap(String id, Map<String, dynamic> data) =>
      InterventoriaHallazgo(
        id: id,
        empresaId: (data['empresaId'] ?? '').toString(),
        visitaId: (data['visitaId'] ?? '').toString(),
        centroCostoId: (data['centroCostoId'] ?? '').toString(),
        centroCostoNombre: (data['centroCostoNombre'] ?? '').toString(),
        grupoId: (data['grupoId'] ?? '').toString(),
        estado: (data['estado'] ?? 'activo').toString(),
        tipoActa: data['tipoActa']?.toString(),
        numeroHallazgo: (data['numeroHallazgo'] ?? '').toString(),
        descripcion: (data['descripcion'] ?? '').toString(),
        fechaHallazgo: data['fechaHallazgo'] as Timestamp? ?? Timestamp.now(),
        persiste: data['persiste'] == true,
        dptoEncargado: (data['dptoEncargado'] ?? '').toString(),
        areaId: (data['areaId'] ?? '').toString(),
        observaciones: (data['observaciones'] ?? '').toString(),
        planMejora: (data['planMejora'] ?? '').toString(),
        valorCorreccion: data['valorCorreccion'] is num
            ? (data['valorCorreccion'] as num).toDouble()
            : null,
        fechaSubsanacion: data['fechaSubsanacion'] as Timestamp?,
        seguimiento: (data['seguimiento'] ?? '').toString(),
        fuente: (data['fuente'] ?? 'manual').toString(),
        createdAt: data['createdAt'] as Timestamp? ?? Timestamp.now(),
        updatedAt: data['updatedAt'] as Timestamp?,
      );

  Map<String, dynamic> toMap() => {
    'empresaId': empresaId,
    'visitaId': visitaId,
    'centroCostoId': centroCostoId,
    'centroCostoNombre': centroCostoNombre,
    'grupoId': grupoId,
    'estado': estado,
    'tipoActa': tipoActa,
    'numeroHallazgo': numeroHallazgo,
    'descripcion': descripcion,
    'fechaHallazgo': fechaHallazgo,
    'persiste': persiste,
    'dptoEncargado': dptoEncargado,
    'areaId': areaId,
    'observaciones': observaciones,
    'planMejora': planMejora,
    'valorCorreccion': valorCorreccion,
    'fechaSubsanacion': fechaSubsanacion,
    'seguimiento': seguimiento,
    'fuente': fuente,
    'createdAt': createdAt,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  InterventoriaHallazgo copyWith({
    String? estado,
    String? numeroHallazgo,
    String? descripcion,
    String? dptoEncargado,
    String? areaId,
    String? observaciones,
    String? planMejora,
    double? valorCorreccion,
    bool clearValorCorreccion = false,
    Timestamp? fechaSubsanacion,
    bool clearFechaSubsanacion = false,
    String? seguimiento,
    bool? persiste,
  }) => InterventoriaHallazgo(
    id: id,
    empresaId: empresaId,
    visitaId: visitaId,
    centroCostoId: centroCostoId,
    centroCostoNombre: centroCostoNombre,
    grupoId: grupoId,
    estado: estado ?? this.estado,
    tipoActa: tipoActa,
    numeroHallazgo: numeroHallazgo ?? this.numeroHallazgo,
    descripcion: descripcion ?? this.descripcion,
    fechaHallazgo: fechaHallazgo,
    persiste: persiste ?? this.persiste,
    dptoEncargado: dptoEncargado ?? this.dptoEncargado,
    areaId: areaId ?? this.areaId,
    observaciones: observaciones ?? this.observaciones,
    planMejora: planMejora ?? this.planMejora,
    valorCorreccion: clearValorCorreccion
        ? null
        : (valorCorreccion ?? this.valorCorreccion),
    fechaSubsanacion: clearFechaSubsanacion
        ? null
        : (fechaSubsanacion ?? this.fechaSubsanacion),
    seguimiento: seguimiento ?? this.seguimiento,
    fuente: fuente,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

double calcularScoreHallazgos(List<InterventoriaHallazgo> hallazgos) {
  if (hallazgos.isEmpty) return 0;
  final subsanados = hallazgos.where((h) => h.isSubsanado).length;
  return double.parse((subsanados / hallazgos.length * 100).toStringAsFixed(2));
}
