import 'package:cloud_firestore/cloud_firestore.dart';

const String kAbastecimientoCollection = 'TBL_COMPRAS_ABASTECIMIENTO';
const String kAbastecimientoReportesCollection =
    'TBL_COMPRAS_ABASTECIMIENTO_REPORTES';

enum AbastecimientoEstado { programado, recibido, reprogramado, cancelado }

enum AbastecimientoPendencia { general, pago, entrada }

extension AbastecimientoPendenciaX on AbastecimientoPendencia {
  String get value => switch (this) {
    AbastecimientoPendencia.general => 'general',
    AbastecimientoPendencia.pago => 'pago',
    AbastecimientoPendencia.entrada => 'entrada',
  };

  String get label => switch (this) {
    AbastecimientoPendencia.general => 'Pendiente',
    AbastecimientoPendencia.pago => 'Pendiente de pago',
    AbastecimientoPendencia.entrada => 'Pendiente de entrada',
  };
}

List<AbastecimientoPendencia> detectarPendenciasAbastecimiento(
  String observaciones,
) {
  final text = observaciones
      .trim()
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (text.isEmpty) return const [];

  final pending =
      text.contains('pendiente') || RegExp(r'(^| )pnd($| )').hasMatch(text);
  if (!pending) return const [];

  final result = <AbastecimientoPendencia>[];
  if (text.contains('pago')) result.add(AbastecimientoPendencia.pago);
  if (text.contains('entrada')) result.add(AbastecimientoPendencia.entrada);
  if (result.isEmpty) result.add(AbastecimientoPendencia.general);
  return result;
}

extension AbastecimientoEstadoX on AbastecimientoEstado {
  String get value => switch (this) {
    AbastecimientoEstado.programado => 'programado',
    AbastecimientoEstado.recibido => 'recibido',
    AbastecimientoEstado.reprogramado => 'reprogramado',
    AbastecimientoEstado.cancelado => 'cancelado',
  };

  String get label => switch (this) {
    AbastecimientoEstado.programado => 'Programado',
    AbastecimientoEstado.recibido => 'Entregado',
    AbastecimientoEstado.reprogramado => 'Reprogramado',
    AbastecimientoEstado.cancelado => 'Cancelado',
  };

  bool get finalizado =>
      this == AbastecimientoEstado.recibido ||
      this == AbastecimientoEstado.cancelado;

  bool get visibleEnCalendario =>
      this != AbastecimientoEstado.recibido &&
      this != AbastecimientoEstado.cancelado;
}

AbastecimientoEstado parseAbastecimientoEstado(Object? raw) {
  final value = (raw ?? '')
      .toString()
      .trim()
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
  return switch (value) {
    'confirmado' || 'confirmada' => AbastecimientoEstado.programado,
    'en_camino' ||
    'despachado' ||
    'despachada' => AbastecimientoEstado.programado,
    'recibido' ||
    'recibida' ||
    'entregado' ||
    'entregada' => AbastecimientoEstado.recibido,
    'no_entrega' ||
    'no_entregan' ||
    'no_va' ||
    'no_van' => AbastecimientoEstado.cancelado,
    'reprogramado' || 'reprogramada' => AbastecimientoEstado.reprogramado,
    'cancelado' ||
    'cancelada' ||
    'anulado' ||
    'anulada' => AbastecimientoEstado.cancelado,
    _ => AbastecimientoEstado.programado,
  };
}

DateTime inicioPeriodoConsumo(DateTime fecha) {
  final date = DateTime(fecha.year, fecha.month, fecha.day);
  final diasDesdeViernes = (date.weekday - DateTime.friday + 7) % 7;
  return date.subtract(Duration(days: diasDesdeViernes));
}

DateTime finPeriodoConsumo(DateTime inicio) {
  final date = DateTime(inicio.year, inicio.month, inicio.day);
  return date.add(const Duration(days: 6));
}

class AbastecimientoCambio {
  final String campo;
  final String anterior;
  final String nuevo;
  final String origen;
  final String usuarioId;
  final Timestamp fecha;

  const AbastecimientoCambio({
    required this.campo,
    required this.anterior,
    required this.nuevo,
    required this.origen,
    required this.usuarioId,
    required this.fecha,
  });

  factory AbastecimientoCambio.fromMap(Map<String, dynamic> map) =>
      AbastecimientoCambio(
        campo: (map['campo'] ?? '').toString(),
        anterior: (map['anterior'] ?? '').toString(),
        nuevo: (map['nuevo'] ?? '').toString(),
        origen: (map['origen'] ?? '').toString(),
        usuarioId: (map['usuarioId'] ?? '').toString(),
        fecha: map['fecha'] is Timestamp
            ? map['fecha'] as Timestamp
            : Timestamp.now(),
      );

  Map<String, dynamic> toMap() => {
    'campo': campo,
    'anterior': anterior,
    'nuevo': nuevo,
    'origen': origen,
    'usuarioId': usuarioId,
    'fecha': fecha,
  };
}

class AbastecimientoReporteDoc {
  final String id;
  final String empresaId;
  final String grupo;
  final DateTime? consumoDesde;
  final DateTime? consumoHasta;
  final String url;
  final String storagePath;
  final int registros;
  final Timestamp generatedAt;
  final bool automatico;

  const AbastecimientoReporteDoc({
    required this.id,
    required this.empresaId,
    required this.grupo,
    this.consumoDesde,
    this.consumoHasta,
    required this.url,
    required this.storagePath,
    required this.registros,
    required this.generatedAt,
    required this.automatico,
  });

  factory AbastecimientoReporteDoc.fromMap(
    String id,
    Map<String, dynamic> map,
  ) {
    DateTime? date(Object? value) => value is Timestamp
        ? value.toDate()
        : value is DateTime
        ? value
        : DateTime.tryParse((value ?? '').toString());
    return AbastecimientoReporteDoc(
      id: id,
      empresaId: (map['empresaId'] ?? '').toString(),
      grupo: (map['grupo'] ?? '').toString(),
      consumoDesde: date(map['consumoDesde']),
      consumoHasta: date(map['consumoHasta']),
      url: (map['url'] ?? '').toString(),
      storagePath: (map['storagePath'] ?? '').toString(),
      registros: (map['registros'] as num?)?.toInt() ?? 0,
      generatedAt: map['generatedAt'] is Timestamp
          ? map['generatedAt'] as Timestamp
          : Timestamp.now(),
      automatico: map['automatico'] == true,
    );
  }
}

class AbastecimientoDoc {
  final String id;
  final String empresaId;
  final String importKey;
  final String hojaOrigen;
  final int filaOrigen;
  final String proveedorId;
  final String proveedor;
  final String categoria;
  final String productoId;
  final String producto;
  final String grupoId;
  final String grupo;
  final String destino;
  final String condicion;
  final double? cantidad;
  final String unidad;
  final double? precio;
  final DateTime? fechaProgramada;
  final DateTime? fechaSegundaEntrega;
  final String ordenCompra;
  final String recepcionId;
  final DateTime? fechaRecibido;
  final String numeroEntrada;
  final String entradaRegistradaPor;
  final Timestamp? entradaRegistradaAt;
  final DateTime? consumoDesde;
  final DateTime? consumoHasta;
  final AbastecimientoEstado estado;
  final String observaciones;
  final String novedadEstado;
  final List<AbastecimientoPendencia> pendencias;
  final String archivoOrigen;
  final String importBatchId;
  final String creadoPor;
  final String actualizadoPor;
  final Timestamp createdAt;
  final Timestamp updatedAt;
  final List<AbastecimientoCambio> historial;
  final bool eliminado;
  final String eliminadoPor;
  final Timestamp? eliminadoAt;
  final String motivoEliminacion;

  const AbastecimientoDoc({
    this.id = '',
    required this.empresaId,
    required this.importKey,
    this.hojaOrigen = '',
    this.filaOrigen = 0,
    this.proveedorId = '',
    required this.proveedor,
    required this.categoria,
    this.productoId = '',
    required this.producto,
    this.grupoId = '',
    this.grupo = '',
    this.destino = '',
    this.condicion = '',
    this.cantidad,
    this.unidad = '',
    this.precio,
    this.fechaProgramada,
    this.fechaSegundaEntrega,
    this.ordenCompra = '',
    this.recepcionId = '',
    this.fechaRecibido,
    this.numeroEntrada = '',
    this.entradaRegistradaPor = '',
    this.entradaRegistradaAt,
    this.consumoDesde,
    this.consumoHasta,
    this.estado = AbastecimientoEstado.programado,
    this.observaciones = '',
    this.novedadEstado = '',
    this.pendencias = const [],
    this.archivoOrigen = '',
    this.importBatchId = '',
    this.creadoPor = '',
    this.actualizadoPor = '',
    required this.createdAt,
    required this.updatedAt,
    this.historial = const [],
    this.eliminado = false,
    this.eliminadoPor = '',
    this.eliminadoAt,
    this.motivoEliminacion = '',
  });

  factory AbastecimientoDoc.fromMap(String id, Map<String, dynamic> map) {
    DateTime? date(Object? value) => value is Timestamp
        ? value.toDate()
        : value is DateTime
        ? value
        : DateTime.tryParse((value ?? '').toString());

    final rawHistory = map['historial'];
    return AbastecimientoDoc(
      id: id,
      empresaId: (map['empresaId'] ?? '').toString(),
      importKey: (map['importKey'] ?? '').toString(),
      hojaOrigen: (map['hojaOrigen'] ?? '').toString(),
      filaOrigen: (map['filaOrigen'] as num?)?.toInt() ?? 0,
      proveedorId: (map['proveedorId'] ?? '').toString(),
      proveedor: (map['proveedor'] ?? '').toString(),
      categoria: (map['categoria'] ?? '').toString(),
      productoId: (map['productoId'] ?? '').toString(),
      producto: (map['producto'] ?? '').toString(),
      grupoId: (map['grupoId'] ?? '').toString(),
      grupo: (map['grupo'] ?? '').toString(),
      destino: (map['destino'] ?? '').toString(),
      condicion: (map['condicion'] ?? '').toString(),
      cantidad: (map['cantidad'] as num?)?.toDouble(),
      unidad: (map['unidad'] ?? '').toString(),
      precio: (map['precio'] as num?)?.toDouble(),
      fechaProgramada: date(map['fechaProgramada']),
      fechaSegundaEntrega: date(map['fechaSegundaEntrega']),
      ordenCompra: (map['ordenCompra'] ?? '').toString(),
      recepcionId: (map['recepcionId'] ?? '').toString(),
      fechaRecibido: date(map['fechaRecibido']),
      numeroEntrada: (map['numeroEntrada'] ?? map['entrada'] ?? '').toString(),
      entradaRegistradaPor: (map['entradaRegistradaPor'] ?? '').toString(),
      entradaRegistradaAt: map['entradaRegistradaAt'] is Timestamp
          ? map['entradaRegistradaAt'] as Timestamp
          : null,
      consumoDesde:
          date(map['consumoDesde']) ??
          (date(map['fechaProgramada']) == null
              ? null
              : inicioPeriodoConsumo(date(map['fechaProgramada'])!)),
      consumoHasta:
          date(map['consumoHasta']) ??
          (date(map['fechaProgramada']) == null
              ? null
              : finPeriodoConsumo(
                  inicioPeriodoConsumo(date(map['fechaProgramada'])!),
                )),
      estado: parseAbastecimientoEstado(map['estado']),
      observaciones: (map['observaciones'] ?? '').toString(),
      novedadEstado: (map['novedadEstado'] ?? '').toString(),
      pendencias: map['pendencias'] is List
          ? (map['pendencias'] as List)
                .map((value) => value.toString())
                .map(
                  (value) => AbastecimientoPendencia.values.where(
                    (item) => item.value == value,
                  ),
                )
                .where((items) => items.isNotEmpty)
                .map((items) => items.first)
                .toList()
          : detectarPendenciasAbastecimiento(
              (map['observaciones'] ?? '').toString(),
            ),
      archivoOrigen: (map['archivoOrigen'] ?? '').toString(),
      importBatchId: (map['importBatchId'] ?? '').toString(),
      creadoPor: (map['creadoPor'] ?? '').toString(),
      actualizadoPor: (map['actualizadoPor'] ?? '').toString(),
      createdAt: map['createdAt'] is Timestamp
          ? map['createdAt'] as Timestamp
          : Timestamp.now(),
      updatedAt: map['updatedAt'] is Timestamp
          ? map['updatedAt'] as Timestamp
          : Timestamp.now(),
      historial: rawHistory is List
          ? rawHistory
                .whereType<Map>()
                .map(
                  (entry) => AbastecimientoCambio.fromMap(
                    entry.map((key, value) => MapEntry(key.toString(), value)),
                  ),
                )
                .toList()
          : const [],
      eliminado: map['eliminado'] == true,
      eliminadoPor: (map['eliminadoPor'] ?? '').toString(),
      eliminadoAt: map['eliminadoAt'] is Timestamp
          ? map['eliminadoAt'] as Timestamp
          : null,
      motivoEliminacion: (map['motivoEliminacion'] ?? '').toString(),
    );
  }

  bool get sinFecha => fechaProgramada == null;
  bool get noEntrega => estado == AbastecimientoEstado.cancelado;

  Map<String, dynamic> toMap() => {
    'empresaId': empresaId,
    'importKey': importKey,
    'hojaOrigen': hojaOrigen,
    'filaOrigen': filaOrigen,
    'proveedorId': proveedorId,
    'proveedor': proveedor,
    'categoria': categoria,
    'productoId': productoId,
    'producto': producto,
    'grupoId': grupoId,
    'grupo': grupo,
    'destino': destino,
    'condicion': condicion,
    'cantidad': cantidad,
    'unidad': unidad,
    'precio': precio,
    'fechaProgramada': fechaProgramada == null
        ? null
        : Timestamp.fromDate(fechaProgramada!),
    'fechaSegundaEntrega': fechaSegundaEntrega == null
        ? null
        : Timestamp.fromDate(fechaSegundaEntrega!),
    'ordenCompra': ordenCompra,
    'recepcionId': recepcionId,
    'fechaRecibido': fechaRecibido == null
        ? null
        : Timestamp.fromDate(fechaRecibido!),
    'numeroEntrada': numeroEntrada,
    'entradaRegistradaPor': entradaRegistradaPor,
    if (entradaRegistradaAt != null) 'entradaRegistradaAt': entradaRegistradaAt,
    'consumoDesde': consumoDesde == null
        ? null
        : Timestamp.fromDate(consumoDesde!),
    'consumoHasta': consumoHasta == null
        ? null
        : Timestamp.fromDate(consumoHasta!),
    'estado': estado.value,
    'observaciones': observaciones,
    'novedadEstado': novedadEstado,
    'pendencias': pendencias.map((item) => item.value).toList(),
    'archivoOrigen': archivoOrigen,
    'importBatchId': importBatchId,
    'creadoPor': creadoPor,
    'actualizadoPor': actualizadoPor,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'historial': historial.map((item) => item.toMap()).toList(),
    'eliminado': eliminado,
    if (eliminadoPor.isNotEmpty) 'eliminadoPor': eliminadoPor,
    if (eliminadoAt != null) 'eliminadoAt': eliminadoAt,
    if (motivoEliminacion.isNotEmpty) 'motivoEliminacion': motivoEliminacion,
  };
}
