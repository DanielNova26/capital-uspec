// Reglas de la carga Excel de Abastecimiento por orden de compra
// (30 sep 2026).
//
// La orden de compra identifica la entrega: una fila del Excel es la misma
// entrega que ya existe cuando coinciden su OC y su producto, sin importar la
// hoja, el grupo o el destino con que se cargó antes (antes cada variación
// creaba otro registro y aparecían duplicados). Además:
// - Una OC pertenece a un solo proveedor. Si ya está relacionada con otro
//   (en Abastecimiento o en Recepción), la fila se rechaza y se dice con cuál.
// - Solo se cambia por Excel una entrega en estado Programado. Si pasó a otro
//   estado y el archivo trae algo distinto, la fila se rechaza con el aviso
//   del usuario: "No se puede subir la OC-XXXX porque pasó a un estado
//   posterior a programado".
// - Las filas repetidas en el archivo o que coinciden con varios registros
//   del sistema no se cargan y se avisa "Existen registros duplicados".
//
// Es lógica pura para poder probarla; la usa [AbastecimientoService].
import '../services/compras_abastecimiento_excel_parser.dart';
import 'abastecimiento_models.dart';
import 'abastecimiento_recepcion_sync.dart';

export 'abastecimiento_recepcion_sync.dart' show normalizarClaveAbastecimiento;

/// "OC-2-2160", "oc 2 2160" y "OC2-2160" son la misma orden.
String claveOrdenCompra(String ordenCompra) =>
    normalizarClaveAbastecimiento(ordenCompra);

String claveLineaAbastecimiento(String ordenCompra, String producto) =>
    '${claveOrdenCompra(ordenCompra)}|'
    '${normalizarClaveAbastecimiento(producto)}';

/// "OC-2160" se muestra igual; "2160" se muestra como "OC 2160".
String etiquetaOrdenCompra(String ordenCompra) {
  final value = ordenCompra.trim();
  return RegExp(r'^o[cs]\b|^o[cs][-\s\d]', caseSensitive: false).hasMatch(value)
      ? value
      : 'OC $value';
}

class OrdenCompraRelacion {
  final String proveedorId;
  final String proveedor;
  final String origen;

  const OrdenCompraRelacion({
    required this.proveedorId,
    required this.proveedor,
    required this.origen,
  });

  bool esDelProveedor(String otroId, String otroNombre) {
    if (proveedorId.isNotEmpty && otroId.isNotEmpty) {
      return proveedorId == otroId;
    }
    return normalizarClaveAbastecimiento(proveedor) ==
        normalizarClaveAbastecimiento(otroNombre);
  }
}

class AbastecimientoPlanCarga {
  /// Filas que se pueden cargar (nuevas, cambios o sin cambios).
  final List<AbastecimientoImportRow> filas;

  /// Línea (OC + producto) → id de la entrega existente que se actualiza.
  final Map<String, String> existentePorLinea;
  final List<AbastecimientoExcelIssue> incidencias;

  /// Avisos "Existen registros duplicados", uno por OC y producto.
  final List<String> duplicados;

  /// OC que no se pueden cambiar porque ya no están programadas.
  final List<String> bloqueadas;

  const AbastecimientoPlanCarga({
    required this.filas,
    required this.existentePorLinea,
    required this.incidencias,
    required this.duplicados,
    required this.bloqueadas,
  });
}

/// Decide qué hace la carga con cada fila ya validada contra los catálogos.
/// [existentes] son las entregas no eliminadas de la empresa activa y
/// [ordenesRecepcion] las OC que Recepción ya asoció a un proveedor.
AbastecimientoPlanCarga planearCargaAbastecimiento({
  required List<AbastecimientoImportRow> filas,
  required List<AbastecimientoDoc> existentes,
  Map<String, OrdenCompraRelacion> ordenesRecepcion = const {},
}) {
  final incidencias = <AbastecimientoExcelIssue>[];
  final duplicados = <String>[];
  final bloqueadas = <String>[];
  void rechazar(AbastecimientoImportRow row, String mensaje) => incidencias.add(
    AbastecimientoExcelIssue(hoja: row.hoja, fila: row.fila, mensaje: mensaje),
  );

  // 1. Filas repetidas dentro del archivo: no se adivina cuál vale.
  final porLinea = <String, List<AbastecimientoImportRow>>{};
  for (final row in filas) {
    porLinea
        .putIfAbsent(
          claveLineaAbastecimiento(row.ordenCompra, row.producto),
          () => [],
        )
        .add(row);
  }
  var pendientes = <AbastecimientoImportRow>[];
  for (final grupo in porLinea.values) {
    if (grupo.length == 1) {
      pendientes.add(grupo.first);
      continue;
    }
    final ubicaciones = grupo.map((row) => '${row.hoja} fila ${row.fila}');
    final first = grupo.first;
    duplicados.add(
      '${etiquetaOrdenCompra(first.ordenCompra)} · ${first.producto}: '
      'se repite en el archivo (${ubicaciones.join(', ')}).',
    );
    for (final row in grupo) {
      rechazar(
        row,
        'Registro duplicado en el archivo: la '
        '${etiquetaOrdenCompra(row.ordenCompra)} con "${row.producto}" '
        'aparece ${grupo.length} veces.',
      );
    }
  }

  // 2. Una OC pertenece a un solo proveedor.
  final relaciones = <String, OrdenCompraRelacion>{...ordenesRecepcion};
  for (final doc in existentes) {
    final key = claveOrdenCompra(doc.ordenCompra);
    if (key.isEmpty || doc.proveedor.trim().isEmpty) continue;
    relaciones[key] = OrdenCompraRelacion(
      proveedorId: doc.proveedorId,
      proveedor: doc.proveedor,
      origen: 'Abastecimiento',
    );
  }
  final conProveedor = <AbastecimientoImportRow>[];
  for (final row in pendientes) {
    final relacion = relaciones[claveOrdenCompra(row.ordenCompra)];
    if (relacion != null &&
        !relacion.esDelProveedor(row.proveedorId, row.proveedor)) {
      rechazar(
        row,
        'La ${etiquetaOrdenCompra(row.ordenCompra)} ya está relacionada con '
        'el proveedor ${relacion.proveedor}, no con ${row.proveedor}.',
      );
      continue;
    }
    conProveedor.add(row);
  }
  final porOrden = <String, List<AbastecimientoImportRow>>{};
  for (final row in conProveedor) {
    porOrden.putIfAbsent(claveOrdenCompra(row.ordenCompra), () => []).add(row);
  }
  pendientes = [];
  for (final grupo in porOrden.values) {
    final proveedores = <String, String>{};
    for (final row in grupo) {
      proveedores.putIfAbsent(
        row.proveedorId.isNotEmpty
            ? row.proveedorId
            : normalizarClaveAbastecimiento(row.proveedor),
        () => row.proveedor,
      );
    }
    if (proveedores.length == 1) {
      pendientes.addAll(grupo);
      continue;
    }
    for (final row in grupo) {
      rechazar(
        row,
        'La ${etiquetaOrdenCompra(row.ordenCompra)} aparece con proveedores '
        'distintos en el archivo: ${proveedores.values.join(', ')}.',
      );
    }
  }

  // 3. La entrega existente es la de la misma OC y producto.
  final existentesPorLinea = <String, List<AbastecimientoDoc>>{};
  for (final doc in existentes) {
    if (claveOrdenCompra(doc.ordenCompra).isEmpty) continue;
    existentesPorLinea
        .putIfAbsent(
          claveLineaAbastecimiento(doc.ordenCompra, doc.producto),
          () => [],
        )
        .add(doc);
  }
  final aptas = <AbastecimientoImportRow>[];
  final existentePorLinea = <String, String>{};
  for (final row in pendientes) {
    final linea = claveLineaAbastecimiento(row.ordenCompra, row.producto);
    final candidatos = existentesPorLinea[linea] ?? const [];
    AbastecimientoDoc? actual;
    if (candidatos.length == 1) {
      actual = candidatos.first;
    } else if (candidatos.length > 1) {
      final destino = normalizarClaveAbastecimiento(row.destino);
      final mismoDestino = candidatos
          .where((doc) => normalizarClaveAbastecimiento(doc.destino) == destino)
          .toList();
      duplicados.add(
        '${etiquetaOrdenCompra(row.ordenCompra)} · ${row.producto}: '
        '${candidatos.length} registros en Abastecimiento.',
      );
      if (mismoDestino.length != 1) {
        rechazar(
          row,
          'Existen registros duplicados de la '
          '${etiquetaOrdenCompra(row.ordenCompra)} con "${row.producto}" '
          '(${candidatos.length}). Elimina los sobrantes en Abastecimiento '
          'y vuelve a cargar.',
        );
        continue;
      }
      actual = mismoDestino.first;
    }

    if (actual != null &&
        actual.estado != AbastecimientoEstado.programado &&
        filaDifiereDeEntrega(row, actual)) {
      final oc = etiquetaOrdenCompra(row.ordenCompra);
      final mensaje =
          'No se puede subir la $oc porque pasó a un estado posterior a '
          'programado (${actual.estado.label}).';
      rechazar(row, mensaje);
      if (!bloqueadas.contains(mensaje)) bloqueadas.add(mensaje);
      continue;
    }
    if (actual != null) existentePorLinea[linea] = actual.id;
    aptas.add(row);
  }

  return AbastecimientoPlanCarga(
    filas: aptas,
    existentePorLinea: existentePorLinea,
    incidencias: incidencias,
    duplicados: duplicados,
    bloqueadas: bloqueadas,
  );
}

/// Si cargar la fila cambiaría la entrega. Sigue la misma regla de la carga:
/// una celda vacía no borra lo guardado; mayúsculas, tildes y espacios no
/// cuentan como cambio. El período de consumo no se compara porque una
/// entrega que ya no está programada conserva el suyo.
bool filaDifiereDeEntrega(AbastecimientoImportRow row, AbastecimientoDoc doc) {
  bool texto(String next, String current) =>
      next.trim().isNotEmpty &&
      normalizarClaveAbastecimiento(next) !=
          normalizarClaveAbastecimiento(current);
  bool numero(double? next, double? current) => next != null && next != current;
  bool fecha(DateTime? next, DateTime? current) =>
      next != null &&
      (current == null ||
          next.year != current.year ||
          next.month != current.month ||
          next.day != current.day);

  if (row.proveedorId.isNotEmpty && row.proveedorId != doc.proveedorId) {
    return true;
  }
  if (row.grupoId.isNotEmpty && row.grupoId != doc.grupoId) return true;
  if (row.recepcionId.isNotEmpty && row.recepcionId != doc.recepcionId) {
    return true;
  }
  if (row.estadoExplicito != null && row.estadoExplicito != doc.estado) {
    return true;
  }
  return texto(row.categoria, doc.categoria) ||
      texto(row.destino, doc.destino) ||
      texto(row.condicion, doc.condicion) ||
      texto(row.unidad, doc.unidad) ||
      texto(row.numeroEntrada, doc.numeroEntrada) ||
      texto(row.observaciones, doc.observaciones) ||
      numero(row.cantidad, doc.cantidad) ||
      numero(row.precio, doc.precio) ||
      fecha(row.fechaProgramada, doc.fechaProgramada) ||
      fecha(row.fechaSegundaEntrega, doc.fechaSegundaEntrega) ||
      fecha(row.fechaRecibido, doc.fechaRecibido);
}
