import 'package:flutter_test/flutter_test.dart';
import 'package:todo/core/app_catalog.dart';
import 'package:todo/talento_humano/personnel_access_service.dart';

void main() {
  // Los módulos que Talento Humano administra, tal como los ve la pantalla.
  final administrables = appCatalogParaTalentoHumano();
  final tareas = administrables
      .firstWhere((m) => m.appId == 'tareasdashboard')
      .appId;
  final otro = administrables.firstWhere((m) => m.appId != tareas).appId;

  group('aplicarEnBloque · agregar', () {
    test('da el módulo a quien no lo tiene', () {
      final out = PersonnelAccessService.aplicarEnBloque(
        actuales: {tareas},
        modulos: [otro],
        agregar: true,
        administrables: administrables,
      );
      expect(out, containsAll(<String>[tareas, otro]));
    });

    test('no duplica el que ya tiene', () {
      final out = PersonnelAccessService.aplicarEnBloque(
        actuales: {tareas, otro},
        modulos: [otro],
        agregar: true,
        administrables: administrables,
      );
      expect(out, hasLength(2));
    });
  });

  group('aplicarEnBloque · quitar', () {
    test('quita el módulo pedido y deja los demás', () {
      final out = PersonnelAccessService.aplicarEnBloque(
        actuales: {tareas, otro},
        modulos: [otro],
        agregar: false,
        administrables: administrables,
      );
      expect(out, {tareas});
    });

    test('quitar lo que no tiene no cambia nada', () {
      final out = PersonnelAccessService.aplicarEnBloque(
        actuales: {tareas},
        modulos: [otro],
        agregar: false,
        administrables: administrables,
      );
      expect(out, {tareas});
    });
  });

  group('lo que Talento Humano no administra no se toca', () {
    test('agregar conserva los módulos de Admin', () {
      // 'adminpanel' no está en el catálogo de Talento Humano: se conserva
      // porque quitarlo aquí le retiraría a la persona un acceso que este
      // módulo ni siquiera muestra.
      final out = PersonnelAccessService.aplicarEnBloque(
        actuales: {'adminpanel', tareas},
        modulos: [otro],
        agregar: true,
        administrables: administrables,
      );
      expect(out, contains('adminpanel'));
    });

    test('quitar conserva los módulos de Admin', () {
      final out = PersonnelAccessService.aplicarEnBloque(
        actuales: {'adminpanel', tareas},
        modulos: [tareas],
        agregar: false,
        administrables: administrables,
      );
      expect(out, {'adminpanel'});
    });

    test('pedir un módulo que no se administra no lo cuela', () {
      // Si no, esta ventana sería una puerta de atrás para dar accesos que
      // Talento Humano no puede otorgar de a uno.
      final out = PersonnelAccessService.aplicarEnBloque(
        actuales: {tareas},
        modulos: ['adminpanel'],
        agregar: true,
        administrables: administrables,
      );
      expect(out, isNot(contains('adminpanel')));
      expect(out, {tareas});
    });
  });

  group('variantes del id', () {
    test('quitar elimina la variante aunque esté escrita de otra forma', () {
      // El mismo módulo aparece con más de una forma en el padrón; quitar solo
      // la escrita lo dejaría puesto sin que se note.
      final out = PersonnelAccessService.aplicarEnBloque(
        actuales: {'TareasDashboard'},
        modulos: [tareas],
        agregar: false,
        administrables: administrables,
      );
      expect(out, isEmpty);
    });
  });
}
