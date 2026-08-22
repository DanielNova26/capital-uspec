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
/// reemplazar todos los documentos que Calidad marcó como rechazados.
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
  }
  for (final key in rechazados.keys) {
    final corregido = correcciones[key];
    if (corregido == null || !corregido.tieneDoc || corregido.rechazado) {
      return 'Debes corregir todos los documentos rechazados antes de reenviar.';
    }
  }
  return null;
}

EstadoRecepcionCompras estadoRecepcionCompras(RecepcionDoc recepcion) {
  var tienePendientes = false;
  for (final producto in recepcion.productos) {
    for (final doc in producto.documentos.values) {
      if (!doc.tieneDoc) continue;
      if (doc.rechazado) return EstadoRecepcionCompras.rechazada;
      if (doc.pendienteRevisionCalidad ||
          doc.estadoCalidad == 'consulta_calidad' ||
          doc.estadoCalidad.isEmpty) {
        tienePendientes = true;
      }
    }
  }
  return tienePendientes
      ? EstadoRecepcionCompras.pendiente
      : EstadoRecepcionCompras.historico;
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
