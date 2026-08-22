import 'gd_correspondencia_models.dart';

/// Dato agregado que el tablero puede representar sin conocer Firestore ni UI.
class GdConteoAgrupado {
  final String etiqueta;
  final int cantidad;

  const GdConteoAgrupado({required this.etiqueta, required this.cantidad});
}

/// Filtros del tablero. Se mantienen fuera del widget para que web y móvil
/// compartan exactamente el mismo criterio aunque presenten controles
/// distintos.
class GdFiltrosCorrespondencia {
  final String estado;
  final String consulta;
  final String tipoDocumental;
  final String responsable;
  final DateTime? recibidoDesde;
  final DateTime? recibidoHasta;

  const GdFiltrosCorrespondencia({
    this.estado = 'activos',
    this.consulta = '',
    this.tipoDocumental = '',
    this.responsable = '',
    this.recibidoDesde,
    this.recibidoHasta,
  });

  bool coincide(GdExpediente row) {
    final estadoCoincide = switch (estado) {
      'recibido' => row.recibido,
      'asignado' => row.asignado,
      'terminado' => row.terminado,
      'vencidos' => row.vencido,
      'vencen_pronto' => row.vencePronto,
      'activos' => row.activo,
      _ => true,
    };
    if (!estadoCoincide) return false;

    if (tipoDocumental.trim().isNotEmpty &&
        row.tipoDocumental.trim() != tipoDocumental.trim()) {
      return false;
    }
    if (responsable.trim().isNotEmpty &&
        row.responsableNombre.trim() != responsable.trim()) {
      return false;
    }

    final recepcion = row.fechaRecepcion;
    if (recibidoDesde != null &&
        (recepcion == null || recepcion.isBefore(_inicioDia(recibidoDesde!)))) {
      return false;
    }
    if (recibidoHasta != null &&
        (recepcion == null || recepcion.isAfter(_finDia(recibidoHasta!)))) {
      return false;
    }

    final query = consulta.trim().toLowerCase();
    if (query.isEmpty) return true;
    return '${row.radicado} ${row.codigoInterno} ${row.codigoExterno} '
            '${row.tipoDocumental} ${row.alias} ${row.asunto} '
            '${row.remitente} ${row.responsableNombre} ${row.areaNombre}'
        .toLowerCase()
        .contains(query);
  }

  static DateTime _inicioDia(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static DateTime _finDia(DateTime value) =>
      DateTime(value.year, value.month, value.day, 23, 59, 59, 999);
}

List<String> gdTiposDisponibles(Iterable<GdExpediente> expedientes) =>
    _valoresUnicos(expedientes.map((row) => row.tipoDocumental));

List<String> gdResponsablesDisponibles(Iterable<GdExpediente> expedientes) =>
    _valoresUnicos(expedientes.map((row) => row.responsableNombre));

List<String> _valoresUnicos(Iterable<String> values) {
  final result = values
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toSet()
      .toList();
  result.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return result;
}

/// Carga operativa actual por responsable.
///
/// Solo cuenta procesos en estado Asignado: los recibidos todavía no tienen
/// responsable y los terminados ya pertenecen al histórico. Esto evita que el
/// gráfico mezcle trabajo pendiente con trabajo cerrado.
List<GdConteoAgrupado> gdAsignadosPorResponsable(
  Iterable<GdExpediente> expedientes, {
  int limite = 8,
}) {
  final counts = <String, int>{};
  for (final expediente in expedientes) {
    if (!expediente.asignado) continue;
    final responsable = expediente.responsableNombre.trim();
    if (responsable.isEmpty) continue;
    counts[responsable] = (counts[responsable] ?? 0) + 1;
  }

  final rows =
      counts.entries
          .map(
            (entry) =>
                GdConteoAgrupado(etiqueta: entry.key, cantidad: entry.value),
          )
          .toList()
        ..sort((a, b) {
          final cantidad = b.cantidad.compareTo(a.cantidad);
          return cantidad != 0
              ? cantidad
              : a.etiqueta.toLowerCase().compareTo(b.etiqueta.toLowerCase());
        });

  if (limite <= 0 || rows.length <= limite) return rows;
  return rows.take(limite).toList(growable: false);
}
