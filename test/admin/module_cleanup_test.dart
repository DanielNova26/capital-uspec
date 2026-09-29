import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/admin/estructura_por_empresa.dart';
import 'package:todo/admin/module_cleanup_service.dart';

void main() {
  test('los módulos de la app son los del servidor, con sus maestros', () {
    final ts = File('functions/src/limpieza.ts').readAsStringSync();
    final servidor = <String, bool>{
      for (final m in RegExp(
        r'id: "([a-z_]+)", nombre: "[^"]+", tareas: (?:true|false),[\s\S]*?maestros: (\[\])?',
      ).allMatches(ts))
        m.group(1)!: m.group(2) == null,
    };
    expect(servidor, isNotEmpty);
    expect({for (final m in kModulosLimpieza) m.id: m.maestros}, servidor);
    expect(
      kModulosLimpieza.map((m) => m.id).toSet().length,
      kModulosLimpieza.length,
    );
    expect(moduloLimpiezaPorId('nada').id, 'tareas');
  });

  test('periodo: completo, lo que viaja al servidor y su texto', () {
    const todo = PeriodoLimpieza(ModoPeriodo.todo);
    expect(todo.completo, isTrue);
    expect(todo.toMap(), {'modo': 'todo'});

    final d1 = DateTime(2026, 9, 1, 15, 30);
    final d10 = DateTime(2026, 9, 10);
    expect(const PeriodoLimpieza(ModoPeriodo.antes).completo, isFalse);
    final entre = PeriodoLimpieza(ModoPeriodo.entre, desde: d1, hasta: d10);
    expect(entre.completo, isTrue);
    // Días completos: la hora no cuenta.
    expect(entre.toMap(), {
      'modo': 'entre',
      'desde': DateTime(2026, 9, 1).millisecondsSinceEpoch,
      'hasta': d10.millisecondsSinceEpoch,
    });
    expect(
      PeriodoLimpieza(ModoPeriodo.entre, desde: d10, hasta: d1).completo,
      isFalse,
    );
    String f(DateTime d) => '${d.day}/${d.month}';
    expect(entre.descripcion(f), 'del 1/9 al 10/9');
  });

  test('vista previa: conteos por colección y registros sin fecha', () {
    final vista = VistaLimpieza.fromMap({
      'colecciones': [
        {
          'coleccion': 'TBL_VISITAS',
          'nombre': 'Visitas',
          'total': 4,
          'sinFecha': 2,
        },
        {
          'coleccion': 'TBL_VISITAS_FORMATOS',
          'nombre': 'Formatos',
          'maestro': true,
          'total': 1,
        },
      ],
      'tareas': 3,
      'tareasSinFecha': 1,
      'notificaciones': 7,
      'total': 15,
    });
    expect(vista.colecciones.last.maestro, isTrue);
    expect(vista.sinFecha, 3);
    expect(vista.total, 15);
    expect(vista.ejecutado, isFalse);
  });

  group('estructura de una persona al quitar una empresa', () {
    test('solo está en esa empresa: se borra', () {
      expect(
        estructuraSinEmpresa({
          'empresaId': 'A',
          'empresas': ['A'],
          'empresasDetalle': {'A': {}},
        }, 'A'),
        isNull,
      );
    });

    test('su principal es otra: solo se quita el bloque', () {
      final cambios = estructuraSinEmpresa({
        'empresaId': 'B',
        'empresas': ['A', 'B'],
        'empresasDetalle': {'A': {}, 'B': {}},
      }, 'A')!;
      expect(cambios['empresasDetalle.A'], FieldValue.delete());
      expect(cambios['empresas'], ['B']);
      expect(cambios.containsKey('empresaId'), isFalse);
    });

    test('era su principal: la siguiente pasa a la raíz con su puesto', () {
      final cambios = estructuraSinEmpresa({
        'empresaId': 'A',
        'empresas': ['A', 'B'],
        'cargo': 'Cargo en A',
        'empresasDetalle': {
          'A': {'cargo': 'Cargo en A'},
          'B': {'cargo': 'Cargo en B', 'areaId': 'B_ops'},
        },
      }, 'A')!;
      expect(cambios['empresaId'], 'B');
      expect(cambios['cargo'], 'Cargo en B');
      expect(cambios['areaId'], 'B_ops');
      expect(cambios['jefeId'], FieldValue.delete());
    });
  });
}
