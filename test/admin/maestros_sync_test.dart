import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/admin/maestros_sync_card.dart';
import 'package:todo/admin/maestros_sync_service.dart';
import 'package:todo/admin/module_cleanup_service.dart';

import '../support/correspondence_functions.dart';
import '../support/memory_firestore.dart';

void main() {
  test('los módulos y maestros de la app son los del servidor', () {
    final ts = File('functions/src/maestros.ts').readAsStringSync();
    final inicio = ts.indexOf('export const MODULOS_MAESTROS');
    final fin = ts.indexOf('// ─── Ayudas puras');
    final bloque = ts.substring(inicio, fin);
    final cabeceras = RegExp(
      r'id: "([a-z_]+)", nombre: "[^"]+",\s*maestros: \[',
    ).allMatches(bloque).toList();
    final servidor = <String, List<String>>{};
    for (var i = 0; i < cabeceras.length; i++) {
      final desde = cabeceras[i].end;
      final hasta = i + 1 < cabeceras.length
          ? cabeceras[i + 1].start
          : bloque.length;
      servidor[cabeceras[i].group(1)!] = [
        for (final m in RegExp(
          r'id: "(TBL_[A-Z_]+)"',
        ).allMatches(bloque.substring(desde, hasta)))
          m.group(1)!,
      ];
    }
    expect(servidor, isNotEmpty);
    expect({
      for (final m in kModulosMaestros)
        if (m.sincroniza) m.id: [for (final x in m.maestros) x.id],
    }, servidor);
  });

  test('cada módulo existe en Limpieza y no se repite', () {
    final ids = kModulosMaestros.map((m) => m.id).toList();
    expect(ids.toSet().length, ids.length);
    final limpieza = kModulosLimpieza.map((m) => m.id).toSet();
    for (final id in ids) {
      expect(limpieza, contains(id));
    }
    // Lo que antes eran pestañas de Admin sigue teniendo su panel.
    expect({
      for (final m in kModulosMaestros) ?m.panel,
    }, PanelAdminModulo.values.toSet());
    expect(moduloMaestrosPorId('nada').id, kModulosMaestros.first.id);
  });

  test('la respuesta del servidor se lee y se resume', () {
    final vista = VistaSincronizacion.fromMap({
      'modulo': 'compras',
      'ejecutado': false,
      'destinos': [
        {
          'empresaId': 'B',
          'nombre': 'Servir',
          'sinEquivalente': ['Cargo: Chef'],
          'archivosSinCopiar': 1,
          'maestros': [
            {
              'coleccion': 'TBL_COMPRAS_MARCAS',
              'nombre': 'Marcas',
              'tipo': 'coleccion',
              'nuevos': 3,
              'existentes': 10,
              'sinClave': 1,
              'ejemplos': ['Alpina'],
            },
            {
              'coleccion': 'TBL_COMPRAS_CONFIG',
              'nombre': 'Configuración',
              'tipo': 'config',
              'campos': 1,
              'ejemplos': ['diasPlazoRechazados'],
            },
          ],
        },
      ],
    });
    final destino = vista.destinos.single;
    expect(vista.porCopiar, 4);
    expect(destino.sinEquivalente, ['Cargo: Chef']);
    expect(destino.archivosSinCopiar, 1);
    expect(
      destino.maestros.first.resumen(),
      '3 nuevos · 10 ya estaban · 1 sin código ni nombre',
    );
    expect(destino.maestros.last.esConfig, isTrue);
    expect(destino.maestros.last.resumen(), '1 campo por completar');

    final hecho = ResultadoMaestro.fromMap({
      'nombre': 'Marcas',
      'tipo': 'coleccion',
      'nuevos': 3,
      'creados': 2,
      'fallidos': 1,
    });
    expect(
      hecho.resumen(ejecutado: true),
      '2 creados · 1 no se pudieron crear',
    );
  });

  test('destinos: todas menos la activa, primero las que administra', () {
    final actor = <String, dynamic>{
      'activo': true,
      'empresaId': 'A',
      'empresas': ['A', 'B', 'C'],
      // Módulos fijados por empresa: la lista general no vale en las otras.
      'appsPorEmpresa': true,
      'empresasDetalle': {
        'A': {
          'activo': true,
          'apps': ['admindashboard'],
        },
        'B': {'activo': true, 'apps': <String>[]},
        'C': {
          'activo': true,
          'apps': ['admindashboard'],
        },
      },
      'apps': ['admindashboard'],
    };
    final lista = destinosPosibles(
      empresas: const [
        (id: 'A', nombre: 'Capital'),
        (id: 'B', nombre: 'Andes'),
        (id: 'C', nombre: 'Servir'),
        (id: 'D', nombre: 'Otra'),
      ],
      empresaActiva: 'A',
      actor: actor,
    );
    expect([for (final p in lista) p.empresa.id], ['C', 'B', 'D']);
    expect([for (final p in lista) p.administra], [true, false, false]);
    expect(
      destinosPosibles(
        empresas: const [(id: 'B', nombre: 'Andes')],
        empresaActiva: 'A',
        actor: null,
      ).single.administra,
      isFalse,
    );
  });

  testWidgets('elegir destino, ver qué se copiaría y el aviso de faltantes', (
    tester,
  ) async {
    final db = MemoryFirestore();
    db.documents['TBL_USUARIOS/u1'] = {
      'activo': true,
      'empresaId': 'A',
      'empresas': ['A', 'B', 'C'],
      // Módulos fijados por empresa: la lista general no vale en las otras.
      'appsPorEmpresa': true,
      'apps': ['admindashboard'],
      'empresasDetalle': {
        'A': {
          'activo': true,
          'apps': ['admindashboard'],
        },
        'B': {
          'activo': true,
          'apps': ['admindashboard'],
        },
        'C': {'activo': true, 'apps': <String>[]},
      },
    };
    final functions = CorrespondenceFunctions()
      ..response = {
        'modulo': 'rutas',
        'ejecutado': false,
        'destinos': [
          {
            'empresaId': 'B',
            'nombre': 'Andes',
            'sinEquivalente': ['Centro de costos: Sede Norte'],
            'maestros': [
              {
                'coleccion': 'TBL_RUTAS',
                'nombre': 'Rutas',
                'tipo': 'coleccion',
                'nuevos': 2,
                'existentes': 1,
                'ejemplos': ['R1', 'R2'],
              },
            ],
          },
        ],
      };
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MaestrosSyncCard(
              userId: 'u1',
              empresaId: 'A',
              modulo: moduloMaestrosPorId('rutas'),
              empresas: const [
                (id: 'A', nombre: 'Capital'),
                (id: 'B', nombre: 'Andes'),
                (id: 'C', nombre: 'Servir'),
              ],
              service: MaestrosSyncService(functions: functions),
              db: db,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Copiar Rutas a otras empresas'), findsOneWidget);
    // La activa no se ofrece; donde no administra, se ve pero no se elige.
    expect(find.text('Capital'), findsNothing);
    expect(find.text('Servir (sin Administración)'), findsOneWidget);
    OutlinedButton ver() => tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Ver qué se copiaría'),
    );
    expect(ver().onPressed, isNull);

    await tester.tap(find.text('Andes'));
    await tester.pump();
    expect(ver().onPressed, isNotNull);
    await tester.tap(find.text('Ver qué se copiaría'));
    await tester.pumpAndSettle();
    expect(functions.calls, 1);
    expect(
      find.textContaining('Rutas: 2 nuevos · 1 ya estaban'),
      findsOneWidget,
    );
    expect(find.textContaining('Centro de costos: Sede Norte'), findsOneWidget);
    final copiar = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Copiar lo que falta'),
    );
    expect(copiar.onPressed, isNotNull);
  });
}
