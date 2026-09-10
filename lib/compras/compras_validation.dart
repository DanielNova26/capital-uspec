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
      ? 'Todavía no hay ficha técnica para este producto. Puedes continuar la recepción o cargarla aquí.'
      : 'La marca $marca todavía no tiene ficha técnica. Puedes continuar la recepción o cargarla aquí.';
}

/// ¿Se puede devolver este documento a la cola de Calidad?
///
/// Devuelve `null` si se puede, o el motivo por el que no.
///
/// Antes solo se podía revertir lo **aprobado**: un documento rechazado se
/// quedaba rechazado para siempre y no había forma de moverlo. Eso obligaba a
/// borrar el archivo y volverlo a subir para que entrara otra vez a la cola,
/// perdiendo por el camino el historial de quién lo subió y por qué se rechazó.
///
/// Una aprobación y un rechazo son la misma cosa —una decisión de Calidad— y
/// las dos se pueden haber tomado por error. Lo que no tiene sentido es
/// revertir lo que todavía nadie decidió.
///
/// Un documento rechazado vuelve a la cola de revisión; **no salta a
/// aprobado**. Aprobar sin que Calidad lo mire otra vez sería saltarse el
/// control, no arreglar un error: quien lo devuelve a la cola lo aprueba
/// después por el camino de siempre.
String? validarReversionDocumento({
  required bool aprobado,
  required bool rechazado,
  required bool rechazar,
}) {
  if (!aprobado && !rechazado) {
    return 'El documento sigue pendiente de revisión: no hay ninguna decisión '
        'que revertir.';
  }
  if (rechazado && rechazar) {
    return 'El documento ya está rechazado.';
  }
  return null;
}

/// Estado al que queda un documento devuelto a la cola de Calidad.
String estadoTrasReversion({required bool rechazar}) =>
    rechazar ? 'rechazado' : 'pendiente_revision_calidad';

/// Etiqueta del botón, según lo que haya que deshacer.
///
/// "Revertir aprobación" sobre algo rechazado no se entiende. El botón dice lo
/// que va a pasar.
String etiquetaReversionDocumento({
  required bool aprobado,
  required bool rechazado,
}) {
  if (rechazado) return 'Devolver a revisión';
  if (aprobado) return 'Revertir aprobación';
  return 'Devolver a revisión';
}

/// ¿Tiene sentido ofrecerle a Calidad el botón de aprobar?
///
/// No, si el documento **ya está aprobado**. El botón seguía saliendo sobre lo
/// aprobado y no hacía nada útil: volver a aprobar lo aprobado no cambia el
/// estado, y ocupaba el sitio del único botón que sí sirve ahí. Si hay que
/// devolverlo, se rechaza.
///
/// Sobre un documento **rechazado** sí se ofrece: Calidad puede revisarlo otra
/// vez y aprobarlo, y esa es la salida normal de un rechazo.
bool muestraBotonAprobar({required bool aprobado}) => !aprobado;

/// ¿Este enlace apunta a un archivo de Firebase Storage?
///
/// Sirve para saber si se le puede preguntar al servidor si el archivo sigue
/// ahí antes de abrirlo. El enlace vive en Firestore y el archivo en Storage:
/// borrar el archivo no invalida el enlace, así que abrirlo a ciegas lleva a
/// una pestaña con el JSON de error de Google en vez de a un aviso entendible.
bool esUrlDeFirebaseStorage(String url) {
  final u = Uri.tryParse(url.trim());
  if (u == null) return false;
  final host = u.host.toLowerCase();
  return host == 'firebasestorage.googleapis.com' ||
      host.endsWith('.firebasestorage.app') ||
      host == 'storage.googleapis.com';
}

/// Semáforo de la ficha técnica de una marca (reunión 9 sep 2026).
///
/// Tres estados y no dos: "tiene archivo" no es lo mismo que "Calidad lo
/// aprobó". Con un solo verde por tener el archivo cargado, una ficha rechazada
/// y una aprobada se veían igual, que es justo lo que hay que poder distinguir
/// de un vistazo en el listado.
enum EstadoFichaMarca {
  /// Calidad la aprobó.
  aprobada,

  /// Cargada y esperando revisión de Calidad.
  pendiente,

  /// Calidad la rechazó. Hay que reemplazarla.
  rechazada,

  /// No hay ficha de ninguna clase.
  sinFicha,
}

/// Resuelve el semáforo a partir de lo que haya cargado para la marca.
///
/// El orden de precedencia importa y no es alfabético: **manda lo mejor que
/// tenga**. Una marca con una ficha aprobada y otra pendiente está aprobada —
/// ya puede operar—, y bajarla a naranja por una segunda ficha en revisión
/// haría que cargar un documento nuevo empeorara el indicador de una marca que
/// estaba bien.
///
/// El rechazo solo pinta cuando no hay nada mejor: si lo único que hay es una
/// ficha rechazada, eso es lo que hay que ver.
EstadoFichaMarca estadoFichaMarca({
  required bool tieneAprobada,
  required bool tienePendiente,
  required bool tieneRechazada,
}) {
  if (tieneAprobada) return EstadoFichaMarca.aprobada;
  if (tienePendiente) return EstadoFichaMarca.pendiente;
  if (tieneRechazada) return EstadoFichaMarca.rechazada;
  return EstadoFichaMarca.sinFicha;
}

/// Texto del semáforo, para el chip del listado.
String etiquetaFichaMarca(EstadoFichaMarca estado) => switch (estado) {
  EstadoFichaMarca.aprobada => 'Ficha aprobada',
  EstadoFichaMarca.pendiente => 'Ficha pendiente',
  EstadoFichaMarca.rechazada => 'Ficha rechazada',
  EstadoFichaMarca.sinFicha => 'Sin ficha',
};
