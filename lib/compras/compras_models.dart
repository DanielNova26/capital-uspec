// lib/compras/compras_models.dart

import 'package:cloud_firestore/cloud_firestore.dart';

// ══════════════════════════════════════════════════════════════════════════════
// CONSTANTES
// ══════════════════════════════════════════════════════════════════════════════

const List<String> kCategoriasCompras = [
  'Abarrotes',
  'Aseo',
  'Equipos',
  'Fruver',
  'Menaje',
  'Panificado',
  'Postres',
  'Proteína',
];

const List<String> kUnidadesMedida = [
  'Kg', 'g', 'mg', 'Ton',
  'L', 'mL',
  'Und', 'Par', 'Caja', 'Paquete', 'Bolsa',
  'Rollo', 'Metro', 'Cm',
  'Libra', 'Galón', 'Botella', 'Caneca',
  'Costal', 'Bandeja', 'Porción',
];

const List<String> kDepartamentos = [
  'Amazonas', 'Antioquia', 'Arauca', 'Atlántico',
  'Bogotá D.C.', 'Bolívar', 'Boyacá', 'Caldas',
  'Caquetá', 'Casanare', 'Cauca', 'Cesar', 'Chocó',
  'Córdoba', 'Cundinamarca', 'Guainía', 'Guaviare',
  'Huila', 'La Guajira', 'Magdalena', 'Meta',
  'Nariño', 'Norte de Santander', 'Putumayo', 'Quindío',
  'Risaralda', 'San Andrés y Providencia', 'Santander',
  'Sucre', 'Tolima', 'Valle del Cauca', 'Vaupés', 'Vichada',
];

// Los documentos requeridos ya no se definen aquí con constantes hardcodeadas.
// La fuente de verdad es la colección TBL_COMPRAS_REQ_DOCUMENTOS en Firestore,
// gestionada por ReqEngine (compras_req_engine.dart).

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
  final String codigo;       // auto-generado: MRC-0001
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

  MarcaRef toRef() => MarcaRef(
        marcaId: id,
        codigo: codigo,
        descripcion: descripcion,
      );
}

// ══════════════════════════════════════════════════════════════════════════════
// DocAdjunto
// ══════════════════════════════════════════════════════════════════════════════

class DocAdjunto {
  final String? url;
  final String? nombre;
  final String? path;
  final Timestamp? fechaSubida;

  const DocAdjunto({this.url, this.nombre, this.path, this.fechaSubida});

  bool get tieneDoc => url != null && url!.isNotEmpty;

  factory DocAdjunto.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const DocAdjunto();
    return DocAdjunto(
      url: m['url'] as String?,
      nombre: m['nombre'] as String?,
      path: m['path'] as String?,
      fechaSubida: m['fechaSubida'] as Timestamp?,
    );
  }

  Map<String, dynamic> toMap() => {
        'url': url,
        'nombre': nombre,
        'path': path,
        'fechaSubida': fechaSubida,
      };

  DocAdjunto copyWith({
    String? url,
    String? nombre,
    String? path,
    Timestamp? fechaSubida,
  }) =>
      DocAdjunto(
        url: url ?? this.url,
        nombre: nombre ?? this.nombre,
        path: path ?? this.path,
        fechaSubida: fechaSubida ?? this.fechaSubida,
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
  }) =>
      ProveedorDoc(
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
    Timestamp? createdAt,
    Timestamp? updatedAt,
  }) =>
      ProductoDoc(
        id: id ?? this.id,
        empresaId: empresaId ?? this.empresaId,
        codigo: codigo ?? this.codigo,
        nombre: nombre ?? this.nombre,
        unidadMedida: unidadMedida ?? this.unidadMedida,
        categoria: categoria ?? this.categoria,
        esPerecedero: esPerecedero ?? this.esPerecedero,
        marcas: marcas ?? this.marcas,
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
  final String marcaId;      // ID de MarcaDoc (puede ser vacío)
  final String marca;        // Descripción de la marca (para mostrar)
  final String origen;       // 'NACIONAL' | 'IMPORTADO' — default 'NACIONAL'
  final Map<String, DocAdjunto> documentos;

  const RecepcionProducto({
    this.productoId = '',
    this.nombre = '',
    this.categoria = '',
    this.marcaId = '',
    this.marca = '',
    this.origen = 'NACIONAL',
    this.documentos = const {},
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
      };

  RecepcionProducto copyWith({
    String? productoId,
    String? nombre,
    String? categoria,
    String? marcaId,
    String? marca,
    String? origen,
    Map<String, DocAdjunto>? documentos,
  }) =>
      RecepcionProducto(
        productoId: productoId ?? this.productoId,
        nombre: nombre ?? this.nombre,
        categoria: categoria ?? this.categoria,
        marcaId: marcaId ?? this.marcaId,
        marca: marca ?? this.marca,
        origen: origen ?? this.origen,
        documentos: documentos ?? this.documentos,
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
  final List<RecepcionProducto> productos;
  final List<String> productoIds; // para consultas con array-contains
  final Timestamp createdAt;

  const RecepcionDoc({
    this.id = '',
    required this.empresaId,
    required this.fecha,
    required this.proveedorId,
    required this.nit,
    required this.razonSocial,
    this.ordenCompra = '',
    required this.productos,
    this.productoIds = const [],
    required this.createdAt,
  });

  factory RecepcionDoc.fromMap(String id, Map<String, dynamic> m) => RecepcionDoc(
        id: id,
        empresaId: m['empresaId'] as String? ?? '',
        fecha: m['fecha'] as Timestamp? ?? Timestamp.now(),
        proveedorId: m['proveedorId'] as String? ?? '',
        nit: m['nit'] as String? ?? '',
        razonSocial: m['razonSocial'] as String? ?? '',
        ordenCompra: m['ordenCompra'] as String? ?? '',
        productos: ((m['productos'] as List?) ?? [])
            .cast<Map<String, dynamic>>()
            .map(RecepcionProducto.fromMap)
            .toList(),
        productoIds: List<String>.from(m['productoIds'] as List? ?? []),
        createdAt: m['createdAt'] as Timestamp? ?? Timestamp.now(),
      );

  Map<String, dynamic> toMap() => {
        'empresaId': empresaId,
        'fecha': fecha,
        'proveedorId': proveedorId,
        'nit': nit,
        'razonSocial': razonSocial,
        'ordenCompra': ordenCompra,
        'productos': productos.map((p) => p.toMap()).toList(),
        'productoIds': productoIds,
        'createdAt': FieldValue.serverTimestamp(),
      };
}
