import 'compras_models.dart';

String normalizarClaveCatalogoCompras(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'\s+'), ' ')
    .replaceAll('á', 'a')
    .replaceAll('é', 'e')
    .replaceAll('í', 'i')
    .replaceAll('ó', 'o')
    .replaceAll('ú', 'u')
    .replaceAll('ü', 'u');

MarcaDoc? buscarMarcaDuplicada(
  Iterable<MarcaDoc> marcas, {
  required String codigo,
  required String descripcion,
  String excluirId = '',
}) {
  final codigoNormalizado = normalizarClaveCatalogoCompras(codigo);
  final descripcionNormalizada = normalizarClaveCatalogoCompras(descripcion);

  for (final marca in marcas) {
    if (excluirId.isNotEmpty && marca.id == excluirId) continue;
    final mismoCodigo =
        codigoNormalizado.isNotEmpty &&
        normalizarClaveCatalogoCompras(marca.codigo) == codigoNormalizado;
    final mismaDescripcion =
        descripcionNormalizada.isNotEmpty &&
        normalizarClaveCatalogoCompras(marca.descripcion) ==
            descripcionNormalizada;
    if (mismoCodigo || mismaDescripcion) return marca;
  }
  return null;
}

bool fichaTecnicaCorrespondeProducto(
  FichaTecnicaDoc ficha, {
  required String productoId,
  required String productoNombre,
}) {
  final id = productoId.trim();
  if (id.isNotEmpty && ficha.productoId.trim() == id) return true;

  // Los nombres de producto son únicos dentro del catálogo. Este respaldo
  // recupera fichas creadas antes de que se estabilizara el id del producto.
  final nombre = normalizarClaveCatalogoCompras(productoNombre);
  return nombre.isNotEmpty &&
      normalizarClaveCatalogoCompras(ficha.productoNombre) == nombre;
}

bool fichaTecnicaCorrespondeMarca(
  FichaTecnicaDoc ficha, {
  required String marcaId,
  required String marcaNombre,
}) {
  final id = marcaId.trim();
  if (id.isNotEmpty && ficha.marcaId.trim() == id) return true;

  // Compatibilidad con fichas antiguas vinculadas por nombre de marca.
  final nombre = normalizarClaveCatalogoCompras(marcaNombre);
  return nombre.isNotEmpty &&
      normalizarClaveCatalogoCompras(ficha.marcaNombre) == nombre;
}

DocAdjunto? documentoVisibleFichaTecnica(FichaTecnicaDoc ficha) {
  final actual = ficha.documentoActual;
  if (actual?.tieneDoc == true) return actual;
  final aprobado = ficha.documentoAprobado;
  return aprobado?.tieneDoc == true ? aprobado : null;
}

/// Devuelve las fichas realmente cargadas para una combinación de producto y
/// marca, incluyendo registros antiguos cuyo vínculo quedó guardado por nombre
/// en lugar del id actual.
List<FichaTecnicaDoc> fichasCargadasProductoMarca({
  required String productoId,
  required String productoNombre,
  required String marcaId,
  required String marcaNombre,
  required Iterable<FichaTecnicaDoc> fichasTecnicas,
}) {
  return fichasTecnicas.where((ficha) {
    if (!fichaTecnicaCorrespondeProducto(
      ficha,
      productoId: productoId,
      productoNombre: productoNombre,
    )) {
      return false;
    }
    if (!fichaTecnicaCorrespondeMarca(
      ficha,
      marcaId: marcaId,
      marcaNombre: marcaNombre,
    )) {
      return false;
    }
    return documentoVisibleFichaTecnica(ficha) != null;
  }).toList()..sort((a, b) => a.proveedorNombre.compareTo(b.proveedorNombre));
}

/// Consolida los documentos de marca almacenados por los modelos anteriores.
///
/// Se contemplan tres variantes que llegaron a producción:
/// - ficha por producto y marca (`fichasTecnicasPorMarca`),
/// - ficha genérica de un producto con una sola marca,
/// - expediente producto-marca-proveedor (`TBL_COMPRAS_FICHAS_TECNICAS`).
///
/// También se recuperan documentos asociados al producto cuando este solo
/// tiene una marca, pues en ese caso la asociación no es ambigua.
List<DocumentoMarcaVinculado> consolidarDocumentosMarcaVinculados({
  required String marcaId,
  String marcaNombre = '',
  required Iterable<ProductoDoc> productos,
  required Iterable<FichaTecnicaDoc> fichasTecnicas,
}) {
  final resultado = <DocumentoMarcaVinculado>[];
  final identidades = <String>{};

  void agregar(DocumentoMarcaVinculado vinculado) {
    if (!vinculado.documento.tieneDoc) return;
    if (!identidades.add(vinculado.identidadArchivo)) return;
    resultado.add(vinculado);
  }

  // La colección producto-marca-proveedor conserva más trazabilidad, por eso
  // tiene prioridad si el mismo archivo también quedó incrustado en producto.
  for (final ficha in fichasTecnicas) {
    if (!fichaTecnicaCorrespondeMarca(
      ficha,
      marcaId: marcaId,
      marcaNombre: marcaNombre,
    )) {
      continue;
    }
    final documento = documentoVisibleFichaTecnica(ficha);
    if (documento == null) continue;
    agregar(
      DocumentoMarcaVinculado(
        id: ficha.id,
        tipo: 'fichaTecnica',
        productoId: ficha.productoId,
        productoNombre: ficha.productoNombre,
        proveedorNombre: ficha.proveedorNombre,
        origen: 'producto_marca_proveedor',
        documento: documento,
      ),
    );
  }

  for (final producto in productos) {
    final nombreMarca = normalizarClaveCatalogoCompras(marcaNombre);
    final referencias = producto.marcas
        .where(
          (marca) =>
              marca.marcaId == marcaId ||
              (nombreMarca.isNotEmpty &&
                  normalizarClaveCatalogoCompras(marca.descripcion) ==
                      nombreMarca),
        )
        .toList();
    if (referencias.isEmpty) continue;

    final fichaPorMarca =
        producto.fichasTecnicasPorMarca[marcaId] ??
        producto.fichasTecnicasPorMarca[referencias.first.marcaId];
    if (fichaPorMarca != null) {
      agregar(
        DocumentoMarcaVinculado(
          id: '${producto.id}:fichaTecnica:$marcaId',
          tipo: 'fichaTecnica',
          productoId: producto.id,
          productoNombre: producto.nombre,
          origen: 'producto_por_marca',
          documento: fichaPorMarca,
        ),
      );
    }

    final asociacionNoAmbigua =
        producto.marcas.length == 1 && referencias.length == 1;
    if (!asociacionNoAmbigua) continue;

    final fichaGenerica = producto.fichaTecnica;
    if (fichaGenerica != null) {
      agregar(
        DocumentoMarcaVinculado(
          id: '${producto.id}:fichaTecnica',
          tipo: 'fichaTecnica',
          productoId: producto.id,
          productoNombre: producto.nombre,
          origen: 'producto_general',
          documento: fichaGenerica,
        ),
      );
    }

    for (final entry in producto.documentosAsociados.entries) {
      agregar(
        DocumentoMarcaVinculado(
          id: '${producto.id}:${entry.key}',
          tipo: entry.key,
          productoId: producto.id,
          productoNombre: producto.nombre,
          origen: 'producto_asociado',
          documento: entry.value,
        ),
      );
    }
  }

  resultado.sort((a, b) {
    final porProducto = a.productoNombre.compareTo(b.productoNombre);
    if (porProducto != 0) return porProducto;
    final porProveedor = a.proveedorNombre.compareTo(b.proveedorNombre);
    if (porProveedor != 0) return porProveedor;
    return a.tipo.compareTo(b.tipo);
  });
  return resultado;
}
