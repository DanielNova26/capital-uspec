import 'compras_models.dart';

const List<String> kDocumentosProveedorObligatorios = [
  kDocRut,
  kDocCertExistencia,
];

/// Documentos cuya carga debe incluir una fecha "Vigente hasta".
const Set<String> kDocumentosConVigenciaObligatoria = {
  'rut',
  'camaraComercio',
  'actaIvcPlanta',
  'actaIvcVehiculo',
  'examenMedico',
  'cursoManipulacion',
  'soporteRegistroInvima',
};

bool documentoRequiereVigencia(String docKey) =>
    kDocumentosConVigenciaObligatoria.contains(docKey.trim());

String? validarMarcasNuevoProducto(List<MarcaRef> marcas) {
  if (marcas.isNotEmpty) return null;
  return 'Asocia al menos una marca antes de crear el producto.';
}

String? validarNuevaFilaProductoRecepcion({
  required bool filaAnteriorTieneProducto,
}) {
  if (filaAnteriorTieneProducto) return null;
  return 'Selecciona el producto de la fila actual antes de agregar otro.';
}

String? validarDocumentosMarcasProducto(
  List<MarcaRef> marcas,
  Iterable<MarcaDoc> catalogoMarcas,
) {
  final porId = {for (final marca in catalogoMarcas) marca.id: marca};
  for (final ref in marcas) {
    final marca = porId[ref.marcaId];
    if (marca == null) {
      return 'No fue posible verificar los documentos de ${ref.descripcion}.';
    }
    final faltantes = kDocumentosAsociadosLabels.entries
        .where(
          (entry) => marca.documentosAsociados[entry.key]?.tieneDoc != true,
        )
        .map((entry) => entry.value)
        .toList();
    if (faltantes.isNotEmpty) {
      return 'Completa los documentos de la marca ${ref.descripcion}: '
          '${faltantes.join(' y ')}.';
    }
    final vigenciasError = validarVigenciasDocumentales(
      marca.documentosAsociados,
      labels: kDocumentosAsociadosLabels,
    );
    if (vigenciasError != null) {
      return '${ref.descripcion}: $vigenciasError';
    }
  }
  return null;
}

String? validarVigenciasDocumentales(
  Map<String, DocAdjunto> documentos, {
  Map<String, String> labels = const {},
}) {
  final sinVigencia = documentos.entries
      .where(
        (entry) =>
            entry.value.tieneDoc &&
            documentoRequiereVigencia(entry.key) &&
            entry.value.fechaVencimiento == null,
      )
      .map((entry) => labels[entry.key] ?? entry.key)
      .toList();
  if (sinVigencia.isEmpty) return null;
  return 'Indica “Vigente hasta” para: ${sinVigencia.join(', ')}.';
}

String? validarVigenciasDocumentalesProveedor(
  Map<String, DocAdjunto> documentos,
) => validarVigenciasDocumentales(
  Map.fromEntries(
    documentos.entries.where(
      (entry) => !kDocProveedorOcultos.contains(entry.key),
    ),
  ),
  labels: kDocProveedorLabels,
);

String? validarDocumentosObligatoriosProveedor(
  Map<String, DocAdjunto> documentos,
) {
  final faltantes = kDocumentosProveedorObligatorios
      .where((key) => documentos[key]?.tieneDoc != true)
      .map((key) => kDocProveedorLabels[key] ?? key)
      .toList();
  if (faltantes.isEmpty) return null;
  return 'Adjunta los documentos obligatorios: ${faltantes.join(' y ')}.';
}

String? resumenPendientesDocumentalesProveedor(
  Map<String, DocAdjunto> documentos,
) {
  final pendientes = <String>[
    if (validarDocumentosObligatoriosProveedor(documentos) case final error?)
      error,
    if (validarVigenciasDocumentalesProveedor(documentos) case final error?)
      error,
  ];
  return pendientes.isEmpty ? null : pendientes.join(' ');
}

String? validarRangoFechasCompras(
  DateTime? fechaInicial,
  DateTime? fechaFinal,
) {
  if (fechaInicial == null || fechaFinal == null) {
    return 'Selecciona la fecha inicial y la fecha final.';
  }
  final inicial = DateTime(
    fechaInicial.year,
    fechaInicial.month,
    fechaInicial.day,
  );
  final final_ = DateTime(fechaFinal.year, fechaFinal.month, fechaFinal.day);
  if (inicial.isAfter(final_)) {
    return 'La fecha inicial no puede ser superior a la fecha final.';
  }
  return null;
}

/// Aviso que ve Bodega cuando una entrada de recepción no encuentra ficha
/// técnica para la marca elegida.
///
/// El texto anterior decía "Este producto no tiene ficha técnica cargada para
/// el proveedor y la marca seleccionados", y estaba mal por dos razones:
///
/// - **El sujeto.** Quien acaba de elegir —o de crear— algo es la marca. Decir
///   "este producto" justo después de crear una marca hace pensar que el
///   problema está en el producto, cuando la ficha que falta es la de la marca
///   nueva. Fue el reclamo textual del 9 sep 2026: "si yo estoy creando una
///   marca, no me tiene que salir este producto".
/// - **La afirmación.** El aviso solo aparece cuando NO hay ficha por
///   proveedor+producto+marca, ni ficha de la marca, ni ficha del producto. O
///   sea: no existe en ninguna parte. Culpar a "el proveedor y la marca
///   seleccionados" mandaba a buscarla bajo otro proveedor, donde tampoco está.
String avisoFichaTecnicaFaltante({required String marcaNombre}) {
  final marca = marcaNombre.trim();
  return marca.isEmpty
      ? 'Todavía no hay ficha técnica para este producto. Puedes cargarla aquí.'
      : 'La marca $marca todavía no tiene ficha técnica. Puedes cargarla aquí.';
}
