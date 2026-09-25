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

// ── Excel "Productos por proveedor" (25 sep 2026) ──────────────────────────

/// Columnas del Excel por proveedor, en el orden de la plantilla de Compras.
const List<String> kColumnasProductoProveedor = [
  'Nombre',
  'Categoría',
  'Marca',
  'Proveedor',
  'Ficha técnica por marca',
  'Registro sanitario',
  'Ficha técnica por proveedor',
];

/// Una fila del Excel por proveedor: un producto, una de sus marcas y un
/// proveedor con ficha de esa marca.
///
/// El Excel de Consultas traía cada producto en una sola fila con todas las
/// marcas y todos los proveedores pegados en una celda ("PALMARIUM,
/// SOLYSOYA…", "LUHOMAR / SAN MIGUEL…"), y para escribirle a cada proveedor
/// había que separarlo a mano. Con una fila por combinación se filtra por
/// proveedor y sale la carta.
class FilaProductoProveedor {
  final String producto;
  final String categoria;
  final String marca;
  final String proveedor;
  final String fichaMarca;
  final String registroSanitario;
  final String fichaProveedor;

  const FilaProductoProveedor({
    required this.producto,
    required this.categoria,
    required this.marca,
    required this.proveedor,
    required this.fichaMarca,
    required this.registroSanitario,
    required this.fichaProveedor,
  });

  List<String> get celdas => [
    producto,
    categoria,
    marca,
    proveedor,
    fichaMarca,
    registroSanitario,
    fichaProveedor,
  ];
}

const String kSinProveedorConFicha = 'Sin proveedor con ficha';
const String kSinFichaProveedor = 'Sin ficha del proveedor';
const String kNoAplicaSinMarca = 'No aplica (sin marca)';

/// Filas del Excel por proveedor.
///
/// Por cada marca del producto sale una fila por proveedor que tiene ficha
/// técnica cargada para ese producto y esa marca; si ningún proveedor la
/// tiene, una fila con "Sin proveedor con ficha" para que se vea lo que
/// falta pedir. Las fichas de proveedor cuya marca no está en el producto
/// (o del producto sin marca) también salen, con la marca que traen.
///
/// [estadoDocumento] dice el estado de un documento en palabras (el mismo
/// que muestra la pantalla de Consultas): así el archivo y la pantalla no se
/// contradicen.
List<FilaProductoProveedor> filasProductoMarcaProveedor({
  required Iterable<ProductoDoc> productos,
  required Map<String, MarcaDoc> marcasPorId,
  required Iterable<FichaTecnicaDoc> fichasTecnicas,
  required String Function(String clave, DocAdjunto? doc) estadoDocumento,
}) {
  final fichas = fichasTecnicas.toList();
  final filas = <FilaProductoProveedor>[];

  String claveProveedor(FichaTecnicaDoc f) => f.proveedorId.trim().isNotEmpty
      ? f.proveedorId.trim()
      : normalizarClaveCatalogoCompras(f.proveedorNombre);
  String nombreProveedor(FichaTecnicaDoc f) => f.proveedorNombre.trim().isEmpty
      ? 'Proveedor sin nombre'
      : f.proveedorNombre.trim();

  for (final p in productos) {
    final usadas = <String>{};

    FilaProductoProveedor fila({
      required String marca,
      required String proveedor,
      required String fichaMarca,
      required String registro,
      required String fichaProveedor,
    }) => FilaProductoProveedor(
      producto: p.nombre,
      categoria: p.categoria,
      marca: marca,
      proveedor: proveedor,
      fichaMarca: fichaMarca,
      registroSanitario: registro,
      fichaProveedor: fichaProveedor,
    );

    for (final ref in p.marcas) {
      final marca = marcasPorId[ref.marcaId];
      final fichaMarca = estadoDocumento(
        'fichaTecnica',
        marca?.documentosAsociados['fichaTecnica'],
      );
      final registro = estadoDocumento(
        'registroSanitario',
        marca?.documentosAsociados['registroSanitario'],
      );
      final nombreMarca = ref.descripcion.trim().isNotEmpty
          ? ref.descripcion.trim()
          : (marca?.descripcion ?? 'Marca sin nombre');
      final vistos = <String>{};
      final deMarca = fichasCargadasProductoMarca(
        productoId: p.id,
        productoNombre: p.nombre,
        marcaId: ref.marcaId,
        marcaNombre: nombreMarca,
        fichasTecnicas: fichas,
      );
      for (final f in deMarca) {
        usadas.add(f.id);
        // Un proveedor, una fila: si quedaron dos fichas del mismo
        // proveedor para la misma marca, manda la primera cargada.
        if (!vistos.add(claveProveedor(f))) continue;
        filas.add(
          fila(
            marca: nombreMarca,
            proveedor: nombreProveedor(f),
            fichaMarca: fichaMarca,
            registro: registro,
            fichaProveedor: estadoDocumento(
              'fichaTecnica',
              documentoVisibleFichaTecnica(f),
            ),
          ),
        );
      }
      if (vistos.isEmpty) {
        filas.add(
          fila(
            marca: nombreMarca,
            proveedor: kSinProveedorConFicha,
            fichaMarca: fichaMarca,
            registro: registro,
            fichaProveedor: kSinFichaProveedor,
          ),
        );
      }
    }

    // Fichas del producto que no quedaron en ninguna de sus marcas: producto
    // sin marca, o marca que ya no está vinculada al producto.
    final vistosSueltos = <String>{};
    for (final f in fichas) {
      if (usadas.contains(f.id)) continue;
      if (documentoVisibleFichaTecnica(f) == null) continue;
      if (!fichaTecnicaCorrespondeProducto(
        f,
        productoId: p.id,
        productoNombre: p.nombre,
      )) {
        continue;
      }
      final marca = marcasPorId[f.marcaId];
      final nombreMarca = f.marcaNombre.trim().isNotEmpty
          ? f.marcaNombre.trim()
          : (marca?.descripcion ?? '');
      if (!vistosSueltos.add('${claveProveedor(f)}|$nombreMarca')) continue;
      filas.add(
        fila(
          marca: nombreMarca.isEmpty ? 'Sin marca' : nombreMarca,
          proveedor: nombreProveedor(f),
          fichaMarca: nombreMarca.isEmpty
              ? kNoAplicaSinMarca
              : estadoDocumento(
                  'fichaTecnica',
                  marca?.documentosAsociados['fichaTecnica'],
                ),
          registro: nombreMarca.isEmpty
              ? kNoAplicaSinMarca
              : estadoDocumento(
                  'registroSanitario',
                  marca?.documentosAsociados['registroSanitario'],
                ),
          fichaProveedor: estadoDocumento(
            'fichaTecnica',
            documentoVisibleFichaTecnica(f),
          ),
        ),
      );
    }

    if (p.marcas.isEmpty && vistosSueltos.isEmpty) {
      filas.add(
        fila(
          marca: 'Sin marcas vinculadas',
          proveedor: kSinProveedorConFicha,
          fichaMarca: kNoAplicaSinMarca,
          registro: kNoAplicaSinMarca,
          fichaProveedor: kSinFichaProveedor,
        ),
      );
    }
  }
  return filas;
}
