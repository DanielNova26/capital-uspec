import 'compras_models.dart';

enum EstadoRecepcionCompras { pendiente, historico, rechazada }

String claveDocumentoRecepcion(String productoId, String docKey) =>
    '${productoId.trim()}::${docKey.trim()}';

Map<String, DocAdjunto> documentosRechazadosRecepcion(RecepcionDoc recepcion) {
  final rechazados = <String, DocAdjunto>{};
  for (final producto in recepcion.productos) {
    for (final entry in producto.documentos.entries) {
      if (!entry.value.rechazado) continue;
      rechazados[claveDocumentoRecepcion(producto.productoId, entry.key)] =
          entry.value;
    }
  }
  return rechazados;
}

/// Valida el único cambio permitido después de cerrar una recepción:
/// reemplazar uno o varios documentos que Calidad marcó como rechazados.
///
/// La corrección es parcial a propósito: Bodega puede reenviar lo que ya tiene
/// disponible y los demás rechazos permanecen abiertos para otra entrega.
String? validarCorreccionesRecepcion({
  required RecepcionDoc original,
  required Map<String, DocAdjunto> correcciones,
}) {
  final rechazados = documentosRechazadosRecepcion(original);
  if (rechazados.isEmpty) {
    return 'La recepción está cerrada y no tiene documentos rechazados por corregir.';
  }
  if (correcciones.isEmpty) {
    return 'Reemplaza los documentos rechazados antes de reenviar la recepción.';
  }
  for (final key in correcciones.keys) {
    if (!rechazados.containsKey(key)) {
      return 'Solo se pueden reemplazar documentos rechazados por Calidad.';
    }
    final corregido = correcciones[key]!;
    if (!corregido.tieneDoc || corregido.rechazado) {
      return 'Cada corrección enviada debe tener un documento nuevo.';
    }
  }
  return null;
}

/// Aplica únicamente los documentos enviados en esta entrega. Un rechazo que
/// no venga en [correcciones] se conserva sin cambios para poder subsanarlo
/// posteriormente.
List<RecepcionProducto> aplicarCorreccionesRecepcion({
  required RecepcionDoc original,
  required Map<String, DocAdjunto> correcciones,
}) {
  return [
    for (final producto in original.productos)
      producto.copyWith(
        documentos: {
          for (final entry in producto.documentos.entries)
            entry.key:
                correcciones[claveDocumentoRecepcion(
                  producto.productoId,
                  entry.key,
                )] ??
                entry.value,
        },
      ),
  ];
}

EstadoRecepcionCompras estadoRecepcionCompras(RecepcionDoc recepcion) {
  var tienePendientes = false;
  var tieneDocumentos = false;
  for (final producto in recepcion.productos) {
    for (final doc in producto.documentos.values) {
      if (!doc.tieneDoc) continue;
      tieneDocumentos = true;
      if (doc.rechazado) return EstadoRecepcionCompras.rechazada;
      if (doc.pendienteRevisionCalidad ||
          doc.estadoCalidad == 'consulta_calidad' ||
          doc.estadoCalidad.isEmpty) {
        tienePendientes = true;
      }
    }
  }
  // Una recepción sin ningún soporte no está finalizada: se guardó así porque
  // la ficha no puede frenar la recepción física, pero Bodega todavía tiene
  // que completarla. Tratarla como histórico la dejaba "Finalizada" y
  // bloqueada sin que Calidad hubiera revisado nada.
  if (!tieneDocumentos) return EstadoRecepcionCompras.pendiente;
  return tienePendientes
      ? EstadoRecepcionCompras.pendiente
      : EstadoRecepcionCompras.historico;
}

/// Valida lo que Bodega cambia en una recepción ya guardada.
///
/// El bloqueo anterior impedía corregir una captura incompleta después de
/// cerrarla. Se permite agregar productos y completar sus soportes, pero no
/// retirar silenciosamente productos que ya formaban parte de la recepción.
///
/// Desde el 6 oct 2026 también se corrige lo capturado de los productos ya
/// registrados (lotes con su fecha y documentos mal cargados), en revisión
/// de Calidad o ya finalizada: Bodega registró mal la fecha de vencimiento
/// de una fécula y no tenía cómo cambiarla. Lo que Calidad aprobó no se
/// quita: se reemplaza y vuelve a su revisión ([fusionarEdicionRecepcion]).
/// Una recepción rechazada sigue su propio flujo de corrección.
String? validarEdicionRecepcionBodega({
  required RecepcionDoc original,
  required List<RecepcionProducto> productosActualizados,
  required String motivo,
}) {
  if (estadoRecepcionCompras(original) == EstadoRecepcionCompras.rechazada) {
    return 'La recepción tiene documentos rechazados: corrígelos primero '
        'desde "Corregir documentos".';
  }
  if (productosActualizados.isEmpty) {
    return 'La recepción debe conservar al menos un producto.';
  }
  if (motivo.trim().isEmpty) {
    return 'Indica el motivo por el cual se está editando la recepción.';
  }

  if (productosActualizados.length < original.productos.length) {
    return 'No se pueden retirar productos que ya estaban registrados en la recepción.';
  }
  for (final producto in productosActualizados) {
    final id = producto.productoId.trim();
    if (id.isEmpty) {
      return 'Todos los productos de la recepción deben estar identificados.';
    }
  }
  for (var i = 0; i < original.productos.length; i++) {
    final originalId = original.productos[i].productoId.trim();
    final actualizadoId = productosActualizados[i].productoId.trim();
    if (originalId.isNotEmpty && originalId != actualizadoId) {
      return 'No se pueden retirar productos que ya estaban registrados en la recepción.';
    }
  }
  for (var i = 0; i < original.productos.length; i++) {
    final antes = original.productos[i];
    final despues = productosActualizados[i];
    for (final entry in antes.documentos.entries) {
      if (!entry.value.tieneDoc || !entry.value.aprobado) continue;
      if (despues.documentos[entry.key]?.tieneDoc == true) continue;
      return 'No se puede quitar "${kDocRecepcionLabels[entry.key] ?? entry.key}" '
          'de ${antes.nombre}: Calidad ya lo aprobó. Si está mal, reemplázalo '
          'y volverá a su revisión.';
    }
  }
  return null;
}

/// Une lo guardado con la edición de Bodega ya validada.
///
/// De un producto ya registrado solo cambian sus lotes, sus observaciones y
/// los archivos. Producto, marca y origen se conservan. Un archivo que no
/// cambió conserva lo guardado, así una pantalla abierta mientras Calidad
/// revisaba no pisa su decisión. Un archivo nuevo o reemplazado entra a
/// revisión de Calidad. Los productos agregados pasan como llegan.
List<RecepcionProducto> fusionarEdicionRecepcion({
  required RecepcionDoc original,
  required List<RecepcionProducto> productosActualizados,
}) => [
  for (var i = 0; i < productosActualizados.length; i++)
    if (i < original.productos.length)
      _fusionarProductoRecepcion(
        original.productos[i],
        productosActualizados[i],
      )
    else
      productosActualizados[i],
];

RecepcionProducto _fusionarProductoRecepcion(
  RecepcionProducto antes,
  RecepcionProducto despues,
) {
  final documentos = <String, DocAdjunto>{};
  for (final entry in despues.documentos.entries) {
    final guardado = antes.documentos[entry.key];
    final nuevo = entry.value;
    if (guardado != null && (guardado.url ?? '') == (nuevo.url ?? '')) {
      documentos[entry.key] = guardado;
    } else if (nuevo.tieneDoc) {
      documentos[entry.key] = nuevo.copyWith(
        estadoCalidad: estadoInicialDocumentoRecepcion(entry.key),
      );
    } else {
      documentos[entry.key] = nuevo;
    }
  }
  // Un registro histórico sin producto identificado toma el que se eligió.
  final base = antes.productoId.trim().isEmpty ? despues : antes;
  final sinMarca = base.marcaId.trim().isEmpty;
  return despues.copyWith(
    productoId: base.productoId,
    nombre: base.nombre,
    categoria: base.categoria,
    marcaId: sinMarca ? despues.marcaId : base.marcaId,
    marca: sinMarca ? despues.marca : base.marca,
    origen: base.origen,
    documentos: documentos,
  );
}

/// Documentos de uso permanente que pertenecen al expediente del producto y
/// continúan sujetos a aprobación de Calidad.
const Set<String> kDocumentosPermanentesRecepcion = {
  'fichaTecnica',
  'fichaTecnicaEs',
  'fichaTecnicaDosificacion',
  'hojaSeguridad',
  'sustanciasPermitidas',
  'soporteRegistroInvima',
};

bool esDocumentoPermanenteRecepcion(String docKey) =>
    kDocumentosPermanentesRecepcion.contains(docKey.trim());

/// Los demás documentos de recepción cambian por entrada, despacho o lote.
/// Calidad puede consultarlos y rechazarlos, pero no aprobarlos.
bool esDocumentoTransitorioRecepcion(String docKey) =>
    docKey.trim().isNotEmpty && !esDocumentoPermanenteRecepcion(docKey);

String estadoInicialDocumentoRecepcion(String docKey) =>
    esDocumentoTransitorioRecepcion(docKey)
    ? 'consulta_calidad'
    : 'pendiente_revision_calidad';

/// Nombres de bodega de compatibilidad mientras cada empresa configura su
/// catálogo en Firestore. Nunca devuelve bodegas de otra empresa.
List<String> bodegasLegacyParaEmpresa({
  required String empresaId,
  required String empresaNombre,
}) {
  final id = _normalizar(empresaId);
  final nombre = _normalizar(empresaNombre);

  if (id == 'empresa 001' ||
      nombre.contains('capital uspec') ||
      nombre.contains('captal uspec')) {
    return const ['Bodega Lutransa'];
  }
  if (id == 'empresa 002' || nombre.contains('servir uspec')) {
    return const ['Bodega Lutransa', 'Bodega Pasto', 'Bodega Gerfor'];
  }
  return const [];
}

/// Encuentra la ficha correspondiente y exige que tenga una versión aprobada.
FichaTecnicaDoc? fichaAprobadaParaRecepcion({
  required Iterable<FichaTecnicaDoc> fichas,
  required String proveedorId,
  required String productoId,
  required String marcaId,
}) {
  for (final ficha in fichas) {
    if (ficha.proveedorId == proveedorId &&
        ficha.productoId == productoId &&
        ficha.marcaId == marcaId &&
        ficha.documentoAprobado?.tieneDoc == true &&
        ficha.documentoAprobado?.aprobado == true) {
      return ficha;
    }
  }
  return null;
}

/// Encuentra una ficha utilizable en la recepción. Se conserva la última
/// aprobada cuando existe; si todavía no hay una, permite asociar la versión
/// actual pendiente para que Bodega pueda guardar y Calidad continúe el flujo.
FichaTecnicaDoc? fichaDisponibleParaRecepcion({
  required Iterable<FichaTecnicaDoc> fichas,
  required String proveedorId,
  required String productoId,
  required String marcaId,
}) {
  final aprobada = fichaAprobadaParaRecepcion(
    fichas: fichas,
    proveedorId: proveedorId,
    productoId: productoId,
    marcaId: marcaId,
  );
  if (aprobada != null) return aprobada;

  for (final ficha in fichas) {
    if (ficha.proveedorId == proveedorId &&
        ficha.productoId == productoId &&
        ficha.marcaId == marcaId &&
        ficha.documentoActual?.tieneDoc == true) {
      return ficha;
    }
  }
  return null;
}

/// Devuelve un error de validación o null cuando los lotes son válidos.
String? validarLotesRecepcion(Iterable<RecepcionLote> lotes) {
  final numeros = <String>{};
  for (final lote in lotes) {
    final numero = lote.numero.trim();
    if (numero.isEmpty) return 'El número de lote no puede estar vacío.';
    final key = numero.toUpperCase();
    if (!numeros.add(key)) {
      return 'El lote $numero está repetido en el mismo producto.';
    }
  }
  return null;
}

String _normalizar(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll('_', ' ')
    .replaceAll('-', ' ')
    .replaceAll(RegExp(r'\s+'), ' ');
