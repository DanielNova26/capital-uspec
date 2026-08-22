// lib/compras/compras_req_engine.dart
// Motor de reglas de documentos para el módulo Compras.
// Fuente de verdad: colección TBL_COMPRAS_REQ_DOCUMENTOS en Firestore.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'compras_models.dart'
    show DocAdjunto, kDocProveedorOcultos, kDocRecepcionOcultos;

// ══════════════════════════════════════════════════════════════════════════════
// ReqDocumentoDoc  — un registro de la tabla TBL_COMPRAS_REQ_DOCUMENTOS
// ══════════════════════════════════════════════════════════════════════════════

class ReqDocumentoDoc {
  final String id;
  final String empresaId;
  final String categoriaApp; // 'Proteína' | 'Abarrotes' | 'Aseo' | 'Todas'
  final String materiaPrima; // descripción informativa de la materia prima
  final String origen; // 'NACIONAL' | 'IMPORTADO' | 'AMBOS'
  final String nivel; // 'PROVEEDOR' | 'RECEPCION'
  final String etapa; // 'INICIAL' | 'CADA_PEDIDO' | 'ROTULADO'
  final String codDoc; // código interno del Excel (ej. PROV_FICHA_TECNICA)
  final String keyApp; // clave de almacenamiento en el mapa documentos
  final String documentoRequerido; // nombre legible para mostrar en UI
  final String obligatorio; // 'SI' | 'CONDICIONAL'
  final String condicion; // texto explicativo si obligatorio == 'CONDICIONAL'
  final String norma; // norma(s) separadas por ';'
  final String entidad; // 'INVIMA' | 'ICA' | 'DIAN' | ''
  final String
  frecuencia; // 'AL_INICIO/ACTUALIZACION' | 'ANUAL' | 'POR_PEDIDO' | ...
  final String observaciones;
  final bool activo;

  const ReqDocumentoDoc({
    this.id = '',
    required this.empresaId,
    required this.categoriaApp,
    this.materiaPrima = '',
    required this.origen,
    required this.nivel,
    required this.etapa,
    this.codDoc = '',
    required this.keyApp,
    required this.documentoRequerido,
    required this.obligatorio,
    this.condicion = '',
    this.norma = '',
    this.entidad = '',
    this.frecuencia = '',
    this.observaciones = '',
    this.activo = true,
  });

  factory ReqDocumentoDoc.fromMap(String id, Map<String, dynamic> m) =>
      ReqDocumentoDoc(
        id: id,
        empresaId: m['empresaId'] as String? ?? '',
        categoriaApp: m['categoriaApp'] as String? ?? '',
        materiaPrima: m['materiaPrima'] as String? ?? '',
        origen: m['origen'] as String? ?? 'AMBOS',
        nivel: m['nivel'] as String? ?? 'RECEPCION',
        etapa: m['etapa'] as String? ?? 'CADA_PEDIDO',
        codDoc: m['codDoc'] as String? ?? '',
        keyApp: m['keyApp'] as String? ?? '',
        documentoRequerido: m['documentoRequerido'] as String? ?? '',
        obligatorio: m['obligatorio'] as String? ?? 'SI',
        condicion: m['condicion'] as String? ?? '',
        norma: m['norma'] as String? ?? '',
        entidad: m['entidad'] as String? ?? '',
        frecuencia: m['frecuencia'] as String? ?? '',
        observaciones: m['observaciones'] as String? ?? '',
        activo: m['activo'] as bool? ?? true,
      );

  Map<String, dynamic> toMap() => {
    'empresaId': empresaId,
    'categoriaApp': categoriaApp,
    'materiaPrima': materiaPrima,
    'origen': origen,
    'nivel': nivel,
    'etapa': etapa,
    'codDoc': codDoc,
    'keyApp': keyApp,
    'documentoRequerido': documentoRequerido,
    'obligatorio': obligatorio,
    'condicion': condicion,
    'norma': norma,
    'entidad': entidad,
    'frecuencia': frecuencia,
    'observaciones': observaciones,
    'activo': activo,
    'updatedAt': FieldValue.serverTimestamp(),
  };
}

// ══════════════════════════════════════════════════════════════════════════════
// ReqDocAplic  — documento agrupado (de-duplicado por keyApp) listo para UI
// ══════════════════════════════════════════════════════════════════════════════

class ReqDocAplic {
  final String keyApp;
  final String documentoRequerido;
  final List<String> normas; // lista de normas únicas que lo exigen
  final List<String> entidades; // lista de entidades regulatorias únicas
  final bool esMandatorio; // true si al menos una fila fuente es 'SI'
  final String condicion; // texto de condición (si CONDICIONAL)

  const ReqDocAplic({
    required this.keyApp,
    required this.documentoRequerido,
    required this.normas,
    required this.entidades,
    required this.esMandatorio,
    this.condicion = '',
  });

  /// Texto corto de normas para mostrar en subtítulo de UI
  String get normasResumen {
    if (normas.isEmpty) return '';
    // Cada norma puede contener múltiples separadas por ';' — aplanar y resumir
    final todas = normas
        .expand((n) => n.split(';').map((s) => s.trim()))
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
    if (todas.length <= 2) return todas.join(' • ');
    return '${todas.take(2).join(' • ')} + ${todas.length - 2} más';
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// ReqEngine  — motor de filtrado y agrupación
// ══════════════════════════════════════════════════════════════════════════════

class ReqEngine {
  final List<ReqDocumentoDoc> _todos;

  const ReqEngine(this._todos);

  bool get isEmpty => _todos.isEmpty;

  // ─── Filtrado para PROVEEDOR ────────────────────────────────────────────────

  /// Retorna la lista de documentos aplicables al crear/editar un Proveedor.
  ///
  /// [categorias] — lista de categorías del proveedor (ej. ['Proteína', 'Abarrotes']).
  ///
  /// A nivel PROVEEDOR no se filtra por origen; se muestran todos los documentos
  /// PROVEEDOR+INICIAL de las categorías del proveedor (para cualquier origen).
  /// Los duplicados se agrupan por keyApp combinando todas las normas.
  List<ReqDocAplic> docsProveedor(List<String> categorias) {
    if (_todos.isEmpty || categorias.isEmpty) return const [];

    final catSet = {...categorias, 'Todas'};
    final filtrados = _todos
        .where(
          (d) =>
              d.activo &&
              d.nivel == 'PROVEEDOR' &&
              d.etapa == 'INICIAL' &&
              !kDocProveedorOcultos.contains(d.keyApp) &&
              catSet.contains(d.categoriaApp),
        )
        .toList();

    return _agrupar(filtrados);
  }

  // ─── Filtrado para RECEPCION ────────────────────────────────────────────────

  /// Retorna la lista de documentos aplicables para un producto en recepción.
  ///
  /// [categoriaProducto] — categoría del ProductoDoc (ej. 'Proteína').
  /// [origenProducto]    — 'NACIONAL' o 'IMPORTADO' (seleccionado en el form).
  /// [etapa]             — 'CADA_PEDIDO' o 'ROTULADO'.
  List<ReqDocAplic> docsRecepcion({
    required String categoriaProducto,
    required String origenProducto,
    required String etapa,
  }) {
    if (_todos.isEmpty) return const [];

    final filtrados = _todos
        .where(
          (d) =>
              d.activo &&
              d.nivel == 'RECEPCION' &&
              d.etapa == etapa &&
              !kDocRecepcionOcultos.contains(d.keyApp) &&
              (d.categoriaApp == categoriaProducto ||
                  d.categoriaApp == 'Todas') &&
              (d.origen == 'AMBOS' || d.origen == origenProducto),
        )
        .toList();

    return _agrupar(filtrados);
  }

  // ─── Documentos faltantes ───────────────────────────────────────────────────

  /// Retorna los documentos mandatorios (esMandatorio=true) que faltan en [docs].
  List<ReqDocAplic> getFaltantes(
    Map<String, DocAdjunto> docs,
    List<ReqDocAplic> requeridos,
  ) => requeridos
      .where((r) => r.esMandatorio && !(docs[r.keyApp]?.tieneDoc ?? false))
      .toList();

  // ─── Interno: agrupar por keyApp ────────────────────────────────────────────

  List<ReqDocAplic> _agrupar(List<ReqDocumentoDoc> filas) {
    // Preservar el orden de primera aparición
    final orden = <String>[];
    final mapa = <String, List<ReqDocumentoDoc>>{};

    for (final f in filas) {
      if (!mapa.containsKey(f.keyApp)) {
        orden.add(f.keyApp);
        mapa[f.keyApp] = [];
      }
      mapa[f.keyApp]!.add(f);
    }

    return orden.map((key) {
      final grupo = mapa[key]!;
      final normas = grupo
          .map((f) => f.norma)
          .where((n) => n.isNotEmpty)
          .toSet()
          .toList();
      final entidades = grupo
          .map((f) => f.entidad)
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList();
      final esMandatorio = grupo.any((f) => f.obligatorio == 'SI');
      final condicionFila =
          grupo
              .where(
                (f) => f.obligatorio == 'CONDICIONAL' && f.condicion.isNotEmpty,
              )
              .map((f) => f.condicion)
              .firstOrNull ??
          '';

      return ReqDocAplic(
        keyApp: key,
        documentoRequerido: grupo.first.documentoRequerido,
        normas: normas,
        entidades: entidades,
        esMandatorio: esMandatorio,
        condicion: condicionFila,
      );
    }).toList();
  }
}
