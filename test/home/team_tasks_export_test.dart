import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/home/team_tasks_export.dart';

void main() {
  final fila = TareaEquipoFila(
    numero: '154',
    responsable: 'Geisson Marenco',
    titulo: 'Informe de trampas — patio 9',
    descripcion: 'Limpieza de trampas de grasa',
    asignadaPor: 'Oscar Cano',
    fechaAsignacion: DateTime(2026, 9, 28),
    fechaLimite: DateTime(2026, 10, 2),
    estado: 'Retrasada',
    dias: 5,
    modulo: 'Manual',
    area: 'Mantenimiento',
  );

  test('las columnas siguen el orden de la matriz', () {
    expect(kColumnasTareasEquipo.take(7).toList(), [
      'N.º tarea',
      'Responsable',
      'Descripción',
      'Asignada por',
      'Fecha asignación',
      'Estado',
      'Días',
    ]);
    expect(filaTareaEquipo(fila).take(7).toList(), [
      '154',
      'Geisson Marenco',
      'Informe de trampas — patio 9',
      'Oscar Cano',
      '28/09/2026',
      'Retrasada',
      '5',
    ]);
    expect(filaTareaEquipo(fila).length, kColumnasTareasEquipo.length);
  });

  test('el Excel trae una sola hoja con cabecera y filas', () {
    final bytes = generarExcelTareasEquipo([fila, fila]);
    final libro = Excel.decodeBytes(bytes);
    expect(libro.tables.keys, ['Tareas del equipo']);
    final hoja = libro.tables['Tareas del equipo']!;
    expect(hoja.maxRows, 3);
    expect(hoja.rows.first.first?.value.toString(), 'N.º tarea');
  });

  test('el PDF se genera aunque no haya fuente con acentos cargada', () async {
    final bytes = await generarPdfTareasEquipo(
      [fila],
      empresa: 'Unión Temporal',
      filtro: 'Tareas abiertas · Responsable: Geisson',
      generado: DateTime(2026, 10, 3, 9),
    );
    expect(bytes.length, greaterThan(800));
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });
}
