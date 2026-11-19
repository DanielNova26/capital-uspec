import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'planeacion_service.dart';

Uint8List exportarPlaneacion(PlaneacionDato registro) {
  final libro = Excel.createExcel();
  libro.rename('Sheet1', 'Necesidades');
  CellValue celda(Object? v) => switch (v) {
    int n => IntCellValue(n),
    num n => DoubleCellValue(n.toDouble()),
    _ => TextCellValue((v ?? '').toString()),
  };
  void fila(String hoja, List<Object?> valores) =>
      libro[hoja].appendRow(valores.map(celda).toList());
  fila('Necesidades', [
    'Planeación',
    registro['nombre'] ?? registro['tipo'],
    'Empresa',
    registro['empresaId'],
    'Registro',
    registro['id'],
  ]);
  fila('Necesidades', [
    'Consumo desde',
    registro['desde'],
    'Consumo hasta',
    registro['hasta'],
    'Estado',
    registro['estado'],
  ]);
  fila('Necesidades', [
    'Código',
    'Producto',
    'Categoría',
    'Unidad',
    'Cantidad',
    'Costo estimado COP',
  ]);
  for (final l in filasPlaneacion(registro['totales'])) {
    fila('Necesidades', [
      l['productoCodigo'],
      l['producto'],
      l['categoria'],
      l['unidad'],
      l['cantidad'],
      l['costo'] ?? 'Sin precio vigente',
    ]);
  }
  fila('Detalle', [
    'Establecimiento',
    'Consumo',
    'Menú',
    'Raciones',
    'Tiempo',
    'Preparación',
    'Código',
    'Producto',
    'Unidad',
    'Cantidad por ración',
    'Cantidad',
    'Precio COP',
    'Costo COP',
  ]);
  for (final l in filasPlaneacion(registro['lineas'])) {
    fila('Detalle', [
      l['centroNombre'],
      l['fecha'],
      l['menuCodigo'],
      l['raciones'],
      l['tiempo'],
      l['preparacion'],
      l['productoCodigo'],
      l['producto'],
      l['unidad'],
      l['cantidadPorRacion'],
      l['cantidad'],
      l['precio'],
      l['costo'],
    ]);
  }
  fila('Programación', ['Establecimiento', 'Consumo', 'Menú', 'Raciones']);
  for (final s in filasPlaneacion(registro['programacion'])) {
    fila('Programación', [
      s['centroNombre'],
      s['fecha'],
      s['menuCodigo'],
      s['raciones'],
    ]);
  }
  final bytes = libro.encode();
  if (bytes == null) throw StateError('No se pudo generar el Excel.');
  return Uint8List.fromList(bytes);
}
