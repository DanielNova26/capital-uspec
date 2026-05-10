// lib/compras/compras_models.dart

import 'package:cloud_firestore/cloud_firestore.dart';

// ══════════════════════════════════════════════════════════════════════════════
// CONSTANTES
// ══════════════════════════════════════════════════════════════════════════════

const List<String> kCategoriasCompras = [
  'Abarrotes',
  'Aseo',
  'Desechables',
  'Equipos',
  'Fruver',
  'Menaje',
  'Panificado',
  'Postres',
  'Proteína',
];

const List<String> kUnidadesMedida = [
  'Kg',
  'g',
  'mg',
  'Ton',
  'L',
  'mL',
  'Und',
  'Par',
  'Caja',
  'Paquete',
  'Bolsa',
  'Rollo',
  'Metro',
  'Cm',
  'Libra',
  'Galón',
  'Botella',
  'Caneca',
  'Costal',
  'Bandeja',
  'Porción',
];

const List<String> kDepartamentos = [
  'Amazonas',
  'Antioquia',
  'Arauca',
  'Atlántico',
  'Bogotá D.C.',
  'Bolívar',
  'Boyacá',
  'Caldas',
  'Caquetá',
  'Casanare',
  'Cauca',
  'Cesar',
  'Chocó',
  'Córdoba',
  'Cundinamarca',
  'Guainía',
  'Guaviare',
  'Huila',
  'La Guajira',
  'Magdalena',
  'Meta',
  'Nariño',
  'Norte de Santander',
  'Putumayo',
  'Quindío',
  'Risaralda',
  'San Andrés y Providencia',
  'Santander',
  'Sucre',
  'Tolima',
  'Valle del Cauca',
  'Vaupés',
  'Vichada',
];

// Los documentos requeridos ya no se definen aquí con constantes hardcodeadas.
// La fuente de verdad es la colección TBL_COMPRAS_REQ_DOCUMENTOS en Firestore,
// gestionada por ReqEngine (compras_req_engine.dart).
//
// COMPATIBILIDAD TEMPORAL:
// Algunas pantallas aún consumen estas constantes mientras terminan su migración
// al motor dinámico. Las llaves están alineadas con KEY_APP de REQ_DOCUMENTOS.
const String kDocRut = 'rut';
const String kDocCertExistencia = 'camaraComercio';
const String kDocActaInspeccion = 'actaIvcPlanta';
const String kDocFichaTecnicaProv = 'fichaTecnicaProv';

/// Documentos legacy de proveedor que ya no deben mostrarse en la UI activa.
const Set<String> kDocProveedorOcultos = {kDocFichaTecnicaProv};

/// Documentos a nivel de PROVEEDOR.
/// NOTA: la ficha técnica del producto ya no se gestiona desde proveedor.
const Map<String, String> kDocProveedorLabels = {
  'rut': 'RUT del proveedor',
  'camaraComercio': 'Cámara de comercio vigente',
  'actaIvcPlanta': 'Acta IVC planta de producción (vigencia menor a 1 año)',
  'actaIvcVehiculo':
      'Acta IVC del vehículo transportador (vigencia menor a 1 año)',
  'examenMedico': 'Examen médico del conductor con énfasis en alimentos',
  'cursoManipulacion':
      'Certificado/curso de manipulación de alimentos del conductor/manipulador',
  'soporteRegistroInvima': 'Soporte de registro sanitario INVIMA',
  'fichaTecnicaDosificacion':
      'Ficha técnica con registro sanitario y dosificaciones',
};

const Map<String, String> kDocRecepcionLabels = {
  'guiaTransporte': 'Guía de transporte',
  'guiaSacrificio': 'Guía de sacrificio',
  'certCalidad': 'Certificado de calidad',
  'fichaTecnica': 'Ficha técnica (copia vigente)',
  'evidenciaEtiqueta': 'Evidencia fotográfica del rótulo/etiqueta del empaque',
  'fechaVencimientoEtiqueta':
      'Fecha de vencimiento impresa en el empaque (verificación/evidencia)',
  'declImport': 'Declaración de Importación (DIAN)',
  'docTransporte': 'Documento de transporte (BL/AWB/Carta porte)',
  'mandatoAduanas': 'Mandato o poder del agente de aduanas',
  'vistoInvima': 'Visto Bueno Sanitario',
  'permisoZoo': 'Permiso Zoosanitario de Importación',
  'certSanitariaImport': 'Certificación sanitaria de importación',
  'fichaTecnicaEs': 'Ficha técnica de la materia prima en español',
  'etiquetaEspanol': 'Etiqueta en idioma español (evidencia fotográfica)',
  'soporteRegistroInvima': 'Soporte de registro sanitario INVIMA',
  'fichaTecnicaDosificacion':
      'Ficha técnica con registro sanitario y dosificaciones (uso alimentario)',
  'hojaSeguridad': 'Hoja de seguridad (SGA) con 16 parámetros',
  'sustanciasPermitidas':
      'Listado/soporte de sustancias permitidas para uso en proceso alimentario',
  'rotuladoSGA':
      'Etiqueta SGA: pictogramas, palabra de advertencia, H/P, identificación y proveedor (evidencia)',
  'rotuladoInfoBasica':
      'Rotulado: nombre alimento, contenido neto, fabricante/fraccionador, lote, vencimiento, conservación, ciudad, etc. (evidencia)',
  'rotuladoAditivos': 'Declaración de aditivos',
  'rotuladoIngredientes':
      'Lista de ingredientes y declaración de agua añadida (evidencia)',
  'rotuladoDenominacion': 'Denominación del producto (evidencia)',
  'rotuladoLoteFechas':
      'Rotulado: lote, peso neto, fechas, conservación y datos del fabricante (evidencia)',
  'rotuladoAdvertencias':
      'Rotulado: advertencias (alérgenos, sodio, azúcares, etc.) (evidencia)',
  'rotuladoRegistroInvima':
      'Registro sanitario INVIMA visible en etiqueta (evidencia)',
  'rotuladoImportOrigen':
      'Rotulado: información obligatoria incluyendo país de origen (evidencia)',
  'rotuladoFrontal810': 'Etiquetado nutricional frontal (evidencia)',
};

/// Roles de usuario en el módulo Compras/Bodega.
/// calidad: permisos completos + aprobación de documentos
/// compras: gestión de proveedores/productos/recepciones (requiere aprobación calidad)
/// bodega: recepción de mercancía + consultas
/// consultas: solo consultas (solo lectura)
const String kRolCalidad = 'calidad';
const String kRolCompras = 'compras';
const String kRolBodega = 'bodega';
const String kRolConsultas = 'consultas';
/// Acceso total: ve y puede eliminar recepciones, marcas, fichas técnicas y documentos.
const String kRolAdmin = 'admin';

// ══════════════════════════════════════════════════════════════════════════════
// MarcaRef  (referencia liviana incrustada en ProductoDoc.marcas)
// ══════════════════════════════════════════════════════════════════════════════

class MarcaRef {
  final String marcaId;
  final String codigo;
  final String descripcion;

  const MarcaRef({
    required this.marcaId,
    required this.codigo,
    required this.descripcion,
  });

  factory MarcaRef.fromMap(Map<String, dynamic> m) => MarcaRef(
    marcaId: m['marcaId'] as String? ?? '',
    codigo: m['codigo'] as String? ?? '',
    descripcion: m['descripcion'] as String? ?? '',
  );

  Map<String, dynamic> toMap() => {
    'marcaId': marcaId,
    'codigo': codigo,
    'descripcion': descripcion,
  };
}

// ══════════════════════════════════════════════════════════════════════════════
// MarcaDoc  (colección TBL_COMPRAS_MARCAS)
// ══════════════════════════════════════════════════════════════════════════════

class MarcaDoc {
  final String id;
  final String empresaId;
  final String codigo; // auto-generado: MRC-0001
  final String descripcion;
  final Timestamp createdAt;
  final Timestamp? updatedAt;

  const MarcaDoc({
    this.id = '',
    required this.empresaId,
    required this.codigo,
    required this.descripcion,
    required this.createdAt,
    this.updatedAt,
  });

  factory MarcaDoc.fromMap(String id, Map<String, dynamic> m) => MarcaDoc(
    id: id,
    empresaId: m['empresaId'] as String? ?? '',
    codigo: m['codigo'] as String? ?? '',
    descripcion: m['descripcion'] as String? ?? '',
    createdAt: m['createdAt'] as Timestamp? ?? Timestamp.now(),
    updatedAt: m['updatedAt'] as Timestamp?,
  );

  Map<String, dynamic> toMap() => {
    'empresaId': empresaId,
    'codigo': codigo,
    'descripcion': descripcion,
    'createdAt': createdAt,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  MarcaRef toRef() =>
      MarcaRef(marcaId: id, codigo: codigo, descripcion: descripcion);
}

// ══════════════════════════════════════════════════════════════════════════════
// DocAdjunto
// ══════════════════════════════════════════════════════════════════════════════

/// Estados de revisión de calidad para un documento adjunto.
/// - '' (vacío): sin gestión de calidad (doc antiguo o no aplica)
/// - 'pendiente': estado legado (compatibilidad)
/// - 'pendiente_revision_calidad': subido por bodega/compras y pendiente de revisión
/// - 'pendiente': subido por bodega/compras, esperando revisión de calidad
/// - 'aprobado': aprobado por calidad
/// - 'rechazado': rechazado por calidad (con observación)
class DocAdjunto {
  final String? url;
  final String? nombre;
  final String? path;
  final Timestamp? fechaSubida;

  /// Fecha de vencimiento del documento (opcional, p.ej. para registro sanitario).
  final Timestamp? fechaVencimiento;

  /// Estado de revisión calidad: '' | 'pendiente' | 'aprobado' | 'rechazado'
  final String estadoCalidad;
  final String? observacionActualizacion;
  final String? observacionCalidad;
  final String? revisadoPor;
  final Timestamp? fechaRevision;

  /// userId del usuario que subió este documento (para notificaciones de rechazo).
  final String? subidoPor;

  const DocAdjunto({
    this.url,
    this.nombre,
    this.path,
    this.fechaSubida,
    this.fechaVencimiento,
    this.estadoCalidad = '',
    this.observacionActualizacion,
    this.observacionCalidad,
    this.revisadoPor,
    this.fechaRevision,
    this.subidoPor,
  });

  bool get tieneDoc => url != null && url!.isNotEmpty;
  bool get pendienteRevisionCalidad =>
      estadoCalidad == 'pendiente_revision_calidad' ||
      estadoCalidad == 'pendiente';
  bool get pendiente => pendienteRevisionCalidad;
  bool get aprobado => estadoCalidad == 'aprobado';
  bool get rechazado => estadoCalidad == 'rechazado';

  factory DocAdjunto.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const DocAdjunto();
    return DocAdjunto(
      url: m['url'] as String?,
      nombre: m['nombre'] as String?,
      path: m['path'] as String?,
      fechaSubida: m['fechaSubida'] as Timestamp?,
      fechaVencimiento: m['fechaVencimiento'] as Timestamp?,
      estadoCalidad: m['estadoCalidad'] as String? ?? '',
      observacionActualizacion: m['observacionActualizacion'] as String?,
      observacionCalidad: m['observacionCalidad'] as String?,
      revisadoPor: m['revisadoPor'] as String?,
      fechaRevision: m['fechaRevision'] as Timestamp?,
      subidoPor: m['subidoPor'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
    'url': url,
    'nombre': nombre,
    'path': path,
    'fechaSubida': fechaSubida,
    'fechaVencimiento': fechaVencimiento,
    'estadoCalidad': estadoCalidad,
    'observacionCalidad': observacionCalidad,
    'observacionActualizacion': observacionActualizacion,
    'revisadoPor': revisadoPor,
    'fechaRevision': fechaRevision,
    'subidoPor': subidoPor,
  };

  DocAdjunto copyWith({
    String? url,
    String? nombre,
    String? path,
    Timestamp? fechaSubida,
    Timestamp? fechaVencimiento,
    String? estadoCalidad,
    String? observacionCalidad,
    String? observacionActualizacion,
    String? revisadoPor,
    Timestamp? fechaRevision,
    String? subidoPor,
  }) => DocAdjunto(
    url: url ?? this.url,
    nombre: nombre ?? this.nombre,
    path: path ?? this.path,
    fechaSubida: fechaSubida ?? this.fechaSubida,
    fechaVencimiento: fechaVencimiento ?? this.fechaVencimiento,
    estadoCalidad: estadoCalidad ?? this.estadoCalidad,
    observacionCalidad: observacionCalidad ?? this.observacionCalidad,
    observacionActualizacion:
        observacionActualizacion ?? this.observacionActualizacion,
    revisadoPor: revisadoPor ?? this.revisadoPor,
    fechaRevision: fechaRevision ?? this.fechaRevision,
    subidoPor: subidoPor ?? this.subidoPor,
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// ProveedorDoc
// ══════════════════════════════════════════════════════════════════════════════

class ProveedorDoc {
  final String id;
  final String empresaId;
  final String nit;
  final String razonSocial;
  final String direccion;
  final String telefono;
  final String email;
  final String departamento;
  final String ciudad;
  final bool esLocal;
  final List<String> categorias;
  final Map<String, DocAdjunto> documentos;
  final Timestamp createdAt;
  final Timestamp? updatedAt;

  const ProveedorDoc({
    this.id = '',
    required this.empresaId,
    required this.nit,
    required this.razonSocial,
    this.direccion = '',
    this.telefono = '',
    this.email = '',
    this.departamento = '',
    this.ciudad = '',
    this.esLocal = false,
    this.categorias = const [],
    this.documentos = const {},
    required this.createdAt,
    this.updatedAt,
  });

  factory ProveedorDoc.fromMap(String id, Map<String, dynamic> m) {
    final rawDocs = (m['documentos'] as Map<String, dynamic>?) ?? {};
    return ProveedorDoc(
      id: id,
      empresaId: m['empresaId'] as String? ?? '',
      nit: m['nit'] as String? ?? '',
      razonSocial: m['razonSocial'] as String? ?? '',
      direccion: m['direccion'] as String? ?? '',
      telefono: m['telefono'] as String? ?? '',
      email: m['email'] as String? ?? '',
      departamento: m['departamento'] as String? ?? '',
      ciudad: m['ciudad'] as String? ?? '',
      esLocal: m['esLocal'] as bool? ?? false,
      categorias: List<String>.from(m['categorias'] as List? ?? []),
      documentos: rawDocs.map(
        (k, v) => MapEntry(k, DocAdjunto.fromMap(v as Map<String, dynamic>?)),
      ),
      createdAt: m['createdAt'] as Timestamp? ?? Timestamp.now(),
      updatedAt: m['updatedAt'] as Timestamp?,
    );
  }

  Map<String, dynamic> toMap() => {
    'empresaId': empresaId,
    'nit': nit,
    'razonSocial': razonSocial,
    'direccion': direccion,
    'telefono': telefono,
    'email': email,
    'departamento': departamento,
    'ciudad': ciudad,
    'esLocal': esLocal,
    'categorias': categorias,
    'documentos': documentos.map((k, v) => MapEntry(k, v.toMap())),
    'createdAt': createdAt,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  ProveedorDoc copyWith({
    String? id,
    String? empresaId,
    String? nit,
    String? razonSocial,
    String? direccion,
    String? telefono,
    String? email,
    String? departamento,
    String? ciudad,
    bool? esLocal,
    List<String>? categorias,
    Map<String, DocAdjunto>? documentos,
    Timestamp? createdAt,
    Timestamp? updatedAt,
  }) => ProveedorDoc(
    id: id ?? this.id,
    empresaId: empresaId ?? this.empresaId,
    nit: nit ?? this.nit,
    razonSocial: razonSocial ?? this.razonSocial,
    direccion: direccion ?? this.direccion,
    telefono: telefono ?? this.telefono,
    email: email ?? this.email,
    departamento: departamento ?? this.departamento,
    ciudad: ciudad ?? this.ciudad,
    esLocal: esLocal ?? this.esLocal,
    categorias: categorias ?? this.categorias,
    documentos: documentos ?? this.documentos,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// ProductoDoc
// ══════════════════════════════════════════════════════════════════════════════

class ProductoDoc {
  final String id;
  final String empresaId;
  final String codigo;
  final String nombre;
  final String unidadMedida;
  final String categoria;
  final bool esPerecedero;
  final List<MarcaRef> marcas;

  /// 'NACIONAL' | 'IMPORTADO' — determina la documentación requerida en recepción
  final String origen;

  /// Ficha técnica del producto (antes estaba a nivel de proveedor)
  final DocAdjunto? fichaTecnica;

  /// Ficha técnica por marca vinculada al producto (marcaId -> DocAdjunto)
  final Map<String, DocAdjunto> fichasTecnicasPorMarca;
  final Timestamp createdAt;
  final Timestamp? updatedAt;

  const ProductoDoc({
    this.id = '',
    required this.empresaId,
    this.codigo = '',
    required this.nombre,
    required this.unidadMedida,
    required this.categoria,
    this.esPerecedero = false,
    this.marcas = const [],
    this.origen = 'NACIONAL',
    this.fichaTecnica,
    this.fichasTecnicasPorMarca = const {},
    required this.createdAt,
    this.updatedAt,
  });

  factory ProductoDoc.fromMap(String id, Map<String, dynamic> m) => ProductoDoc(
    id: id,
    empresaId: m['empresaId'] as String? ?? '',
    codigo: m['codigo'] as String? ?? '',
    nombre: m['nombre'] as String? ?? '',
    unidadMedida: m['unidadMedida'] as String? ?? '',
    categoria: m['categoria'] as String? ?? '',
    esPerecedero: m['esPerecedero'] as bool? ?? false,
    marcas: ((m['marcas'] as List?) ?? [])
        .cast<Map<String, dynamic>>()
        .map(MarcaRef.fromMap)
        .toList(),
    origen: m['origen'] as String? ?? 'NACIONAL',
    fichaTecnica: m['fichaTecnica'] != null
        ? DocAdjunto.fromMap(m['fichaTecnica'] as Map<String, dynamic>?)
        : null,
    fichasTecnicasPorMarca:
        ((m['fichasTecnicasPorMarca'] as Map<String, dynamic>?) ?? {}).map(
          (k, v) => MapEntry(
            k,
            DocAdjunto.fromMap((v as Map?)?.cast<String, dynamic>()),
          ),
        ),
    createdAt: m['createdAt'] as Timestamp? ?? Timestamp.now(),
    updatedAt: m['updatedAt'] as Timestamp?,
  );

  Map<String, dynamic> toMap() => {
    'empresaId': empresaId,
    'codigo': codigo,
    'nombre': nombre,
    'unidadMedida': unidadMedida,
    'categoria': categoria,
    'esPerecedero': esPerecedero,
    'marcas': marcas.map((r) => r.toMap()).toList(),
    'origen': origen,
    'fichaTecnica': fichaTecnica?.toMap(),
    'fichasTecnicasPorMarca': fichasTecnicasPorMarca.map(
      (k, v) => MapEntry(k, v.toMap()),
    ),
    'createdAt': createdAt,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  ProductoDoc copyWith({
    String? id,
    String? empresaId,
    String? codigo,
    String? nombre,
    String? unidadMedida,
    String? categoria,
    bool? esPerecedero,
    List<MarcaRef>? marcas,
    String? origen,
    DocAdjunto? fichaTecnica,
    Map<String, DocAdjunto>? fichasTecnicasPorMarca,
    bool clearFichaTecnica = false,
    Timestamp? createdAt,
    Timestamp? updatedAt,
  }) => ProductoDoc(
    id: id ?? this.id,
    empresaId: empresaId ?? this.empresaId,
    codigo: codigo ?? this.codigo,
    nombre: nombre ?? this.nombre,
    unidadMedida: unidadMedida ?? this.unidadMedida,
    categoria: categoria ?? this.categoria,
    esPerecedero: esPerecedero ?? this.esPerecedero,
    marcas: marcas ?? this.marcas,
    origen: origen ?? this.origen,
    fichaTecnica: clearFichaTecnica
        ? null
        : (fichaTecnica ?? this.fichaTecnica),
    fichasTecnicasPorMarca:
        fichasTecnicasPorMarca ?? this.fichasTecnicasPorMarca,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// RecepcionProducto
// ══════════════════════════════════════════════════════════════════════════════

class RecepcionProducto {
  final String productoId;
  final String nombre;
  final String categoria;
  final String marcaId; // ID de MarcaDoc (puede ser vacío)
  final String marca; // Descripción de la marca (para mostrar)
  final String origen; // 'NACIONAL' | 'IMPORTADO' — hereda del ProductoDoc
  final Map<String, DocAdjunto> documentos;

  /// Observaciones del operador (bodega) sobre esta recepción del producto
  final String observaciones;

  const RecepcionProducto({
    this.productoId = '',
    this.nombre = '',
    this.categoria = '',
    this.marcaId = '',
    this.marca = '',
    this.origen = 'NACIONAL',
    this.documentos = const {},
    this.observaciones = '',
  });

  factory RecepcionProducto.fromMap(Map<String, dynamic> m) {
    final rawDocs = (m['documentos'] as Map<String, dynamic>?) ?? {};
    return RecepcionProducto(
      productoId: m['productoId'] as String? ?? '',
      nombre: m['nombre'] as String? ?? '',
      categoria: m['categoria'] as String? ?? '',
      marcaId: m['marcaId'] as String? ?? '',
      marca: m['marca'] as String? ?? '',
      origen: m['origen'] as String? ?? 'NACIONAL',
      documentos: rawDocs.map(
        (k, v) => MapEntry(k, DocAdjunto.fromMap(v as Map<String, dynamic>?)),
      ),
      observaciones: m['observaciones'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
    'productoId': productoId,
    'nombre': nombre,
    'categoria': categoria,
    'marcaId': marcaId,
    'marca': marca,
    'origen': origen,
    'documentos': documentos.map((k, v) => MapEntry(k, v.toMap())),
    'observaciones': observaciones,
  };

  RecepcionProducto copyWith({
    String? productoId,
    String? nombre,
    String? categoria,
    String? marcaId,
    String? marca,
    String? origen,
    Map<String, DocAdjunto>? documentos,
    String? observaciones,
  }) => RecepcionProducto(
    productoId: productoId ?? this.productoId,
    nombre: nombre ?? this.nombre,
    categoria: categoria ?? this.categoria,
    marcaId: marcaId ?? this.marcaId,
    marca: marca ?? this.marca,
    origen: origen ?? this.origen,
    documentos: documentos ?? this.documentos,
    observaciones: observaciones ?? this.observaciones,
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// RecepcionDoc
// ══════════════════════════════════════════════════════════════════════════════

class RecepcionDoc {
  final String id;
  final String empresaId;
  final Timestamp fecha;
  final String proveedorId;
  final String nit;
  final String razonSocial;
  final String ordenCompra;

  /// Bodega o ubicación de destino de la mercancía
  final String bodega;
  final List<RecepcionProducto> productos;
  final List<String> productoIds; // para consultas con array-contains
  final String creadoPor; // userId de quien creó la recepción
  final Timestamp createdAt;

  const RecepcionDoc({
    this.id = '',
    required this.empresaId,
    required this.fecha,
    required this.proveedorId,
    required this.nit,
    required this.razonSocial,
    this.ordenCompra = '',
    this.bodega = '',
    required this.productos,
    this.productoIds = const [],
    this.creadoPor = '',
    required this.createdAt,
  });

  factory RecepcionDoc.fromMap(String id, Map<String, dynamic> m) =>
      RecepcionDoc(
        id: id,
        empresaId: m['empresaId'] as String? ?? '',
        fecha: m['fecha'] as Timestamp? ?? Timestamp.now(),
        proveedorId: m['proveedorId'] as String? ?? '',
        nit: m['nit'] as String? ?? '',
        razonSocial: m['razonSocial'] as String? ?? '',
        ordenCompra: m['ordenCompra'] as String? ?? '',
        bodega: m['bodega'] as String? ?? '',
        productos: ((m['productos'] as List?) ?? [])
            .cast<Map<String, dynamic>>()
            .map(RecepcionProducto.fromMap)
            .toList(),
        productoIds: List<String>.from(m['productoIds'] as List? ?? []),
        creadoPor: m['creadoPor'] as String? ?? '',
        createdAt: m['createdAt'] as Timestamp? ?? Timestamp.now(),
      );

  Map<String, dynamic> toMap() => {
    'empresaId': empresaId,
    'fecha': fecha,
    'proveedorId': proveedorId,
    'nit': nit,
    'razonSocial': razonSocial,
    'ordenCompra': ordenCompra,
    'bodega': bodega,
    'productos': productos.map((p) => p.toMap()).toList(),
    'productoIds': productoIds,
    'creadoPor': creadoPor,
    'createdAt': FieldValue.serverTimestamp(),
  };
}

// ══════════════════════════════════════════════════════════════════════════════
// ComprasRolDoc  (colección TBL_COMPRAS_ROLES)
// ══════════════════════════════════════════════════════════════════════════════

/// Asignación de rol de un usuario en el módulo Compras.
class ComprasRolDoc {
  final String id;
  final String empresaId;
  final String userId;
  final String cedula;
  final String nombre;

  /// 'calidad' | 'compras' | 'bodega'
  final String rol;
  final Timestamp createdAt;

  const ComprasRolDoc({
    this.id = '',
    required this.empresaId,
    required this.userId,
    required this.cedula,
    required this.nombre,
    required this.rol,
    required this.createdAt,
  });

  factory ComprasRolDoc.fromMap(String id, Map<String, dynamic> m) =>
      ComprasRolDoc(
        id: id,
        empresaId: m['empresaId'] as String? ?? '',
        userId: m['userId'] as String? ?? '',
        cedula: m['cedula'] as String? ?? '',
        nombre: m['nombre'] as String? ?? '',
        rol: m['rol'] as String? ?? '',
        createdAt: m['createdAt'] as Timestamp? ?? Timestamp.now(),
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

// ══════════════════════════════════════════════════════════════════════════════
// NotificacionComprasDoc  (colección TBL_COMPRAS_NOTIFICACIONES)
// ══════════════════════════════════════════════════════════════════════════════

/// Notificación enviada a bodega cuando calidad rechaza un documento.
class NotificacionComprasDoc {
  final String id;
  final String empresaId;

  /// userId destinatario (quien subió el documento — bodega)
  final String userId;
  final String recepcionId;
  final String productoNombre;
  final String docKey;
  final String docLabel;
  final String motivo;
  final Timestamp createdAt;
  final bool leida;

  const NotificacionComprasDoc({
    this.id = '',
    required this.empresaId,
    required this.userId,
    required this.recepcionId,
    required this.productoNombre,
    required this.docKey,
    required this.docLabel,
    required this.motivo,
    required this.createdAt,
    this.leida = false,
  });

  factory NotificacionComprasDoc.fromMap(String id, Map<String, dynamic> m) =>
      NotificacionComprasDoc(
        id: id,
        empresaId: m['empresaId'] as String? ?? '',
        userId: m['userId'] as String? ?? '',
        recepcionId: m['recepcionId'] as String? ?? '',
        productoNombre: m['productoNombre'] as String? ?? '',
        docKey: m['docKey'] as String? ?? '',
        docLabel: m['docLabel'] as String? ?? '',
        motivo: m['motivo'] as String? ?? '',
        createdAt: m['createdAt'] as Timestamp? ?? Timestamp.now(),
        leida: m['leida'] as bool? ?? false,
      );

  Map<String, dynamic> toMap() => {
    'empresaId': empresaId,
    'userId': userId,
    'recepcionId': recepcionId,
    'productoNombre': productoNombre,
    'docKey': docKey,
    'docLabel': docLabel,
    'motivo': motivo,
    'createdAt': createdAt,
    'leida': leida,
  };
}

// ══════════════════════════════════════════════════════════════════════════════
// FichaTecnicaHistorial
// Versión archivada de una ficha técnica (al ser reemplazada por una nueva).
// ══════════════════════════════════════════════════════════════════════════════

class FichaTecnicaHistorial {
  final String url;
  final String nombre;
  final String? path;

  /// Motivo obligatorio de la actualización (por qué se reemplazó).
  final String observacion;

  /// userId que realizó la actualización.
  final String actualizadoPor;
  final Timestamp fecha;

  /// Estado de calidad que tenía el documento al momento de ser archivado.
  final String estadoCalidadFinal;

  const FichaTecnicaHistorial({
    required this.url,
    required this.nombre,
    this.path,
    required this.observacion,
    required this.actualizadoPor,
    required this.fecha,
    this.estadoCalidadFinal = '',
  });

  factory FichaTecnicaHistorial.fromMap(Map<String, dynamic> m) =>
      FichaTecnicaHistorial(
        url: m['url'] as String? ?? '',
        nombre: m['nombre'] as String? ?? '',
        path: m['path'] as String?,
        observacion: m['observacion'] as String? ?? '',
        actualizadoPor: m['actualizadoPor'] as String? ?? '',
        fecha: m['fecha'] as Timestamp? ?? Timestamp.now(),
        estadoCalidadFinal: m['estadoCalidadFinal'] as String? ?? '',
      );

  Map<String, dynamic> toMap() => {
    'url': url,
    'nombre': nombre,
    'path': path,
    'observacion': observacion,
    'actualizadoPor': actualizadoPor,
    'fecha': fecha,
    'estadoCalidadFinal': estadoCalidadFinal,
  };
}

// ══════════════════════════════════════════════════════════════════════════════
// FichaTecnicaDoc
// Ficha técnica específica de un Proveedor + Producto + Marca.
// Colección: TBL_COMPRAS_FICHAS_TECNICAS
// ══════════════════════════════════════════════════════════════════════════════

class FichaTecnicaDoc {
  final String id;
  final String empresaId;
  final String proveedorId;
  final String proveedorNombre;
  final String productoId;
  final String productoNombre;
  final String productoCategoria;

  /// '' cuando el producto no tiene marca.
  final String marcaId;
  final String marcaNombre;

  /// Ficha vigente con su estado de calidad.
  final DocAdjunto? documentoActual;

  /// Versiones anteriores archivadas.
  final List<FichaTecnicaHistorial> historial;

  /// userId que subió la ficha (para enviar notificaciones si calidad rechaza).
  final String creadoPor;
  final Timestamp createdAt;
  final Timestamp? updatedAt;

  const FichaTecnicaDoc({
    this.id = '',
    required this.empresaId,
    required this.proveedorId,
    required this.proveedorNombre,
    required this.productoId,
    required this.productoNombre,
    this.productoCategoria = '',
    this.marcaId = '',
    this.marcaNombre = '',
    this.documentoActual,
    this.historial = const [],
    required this.creadoPor,
    required this.createdAt,
    this.updatedAt,
  });

  factory FichaTecnicaDoc.fromMap(String id, Map<String, dynamic> m) =>
      FichaTecnicaDoc(
        id: id,
        empresaId: m['empresaId'] as String? ?? '',
        proveedorId: m['proveedorId'] as String? ?? '',
        proveedorNombre: m['proveedorNombre'] as String? ?? '',
        productoId: m['productoId'] as String? ?? '',
        productoNombre: m['productoNombre'] as String? ?? '',
        productoCategoria: m['productoCategoria'] as String? ?? '',
        marcaId: m['marcaId'] as String? ?? '',
        marcaNombre: m['marcaNombre'] as String? ?? '',
        documentoActual: m['documentoActual'] != null
            ? DocAdjunto.fromMap(
                (m['documentoActual'] as Map?)?.cast<String, dynamic>(),
              )
            : null,
        historial: ((m['historial'] as List?) ?? [])
            .cast<Map<String, dynamic>>()
            .map(FichaTecnicaHistorial.fromMap)
            .toList(),
        creadoPor: m['creadoPor'] as String? ?? '',
        createdAt: m['createdAt'] as Timestamp? ?? Timestamp.now(),
        updatedAt: m['updatedAt'] as Timestamp?,
      );

  Map<String, dynamic> toMap() => {
    'empresaId': empresaId,
    'proveedorId': proveedorId,
    'proveedorNombre': proveedorNombre,
    'productoId': productoId,
    'productoNombre': productoNombre,
    'productoCategoria': productoCategoria,
    'marcaId': marcaId,
    'marcaNombre': marcaNombre,
    'documentoActual': documentoActual?.toMap(),
    'historial': historial.map((h) => h.toMap()).toList(),
    'creadoPor': creadoPor,
    'createdAt': createdAt,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  FichaTecnicaDoc copyWith({
    String? id,
    String? empresaId,
    String? proveedorId,
    String? proveedorNombre,
    String? productoId,
    String? productoNombre,
    String? productoCategoria,
    String? marcaId,
    String? marcaNombre,
    DocAdjunto? documentoActual,
    bool clearDocumentoActual = false,
    List<FichaTecnicaHistorial>? historial,
    String? creadoPor,
    Timestamp? createdAt,
    Timestamp? updatedAt,
  }) => FichaTecnicaDoc(
    id: id ?? this.id,
    empresaId: empresaId ?? this.empresaId,
    proveedorId: proveedorId ?? this.proveedorId,
    proveedorNombre: proveedorNombre ?? this.proveedorNombre,
    productoId: productoId ?? this.productoId,
    productoNombre: productoNombre ?? this.productoNombre,
    productoCategoria: productoCategoria ?? this.productoCategoria,
    marcaId: marcaId ?? this.marcaId,
    marcaNombre: marcaNombre ?? this.marcaNombre,
    documentoActual: clearDocumentoActual
        ? null
        : (documentoActual ?? this.documentoActual),
    historial: historial ?? this.historial,
    creadoPor: creadoPor ?? this.creadoPor,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}
