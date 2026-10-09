import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:todo/core/notification_catalog.dart';

void main() {
  test('el catálogo de la app es el del servidor', () {
    final ts = File('functions/src/notification_catalog.ts').readAsStringSync();
    final inicio = ts.indexOf('export const CATALOGO_NOTIFICACIONES');
    final fin = ts.indexOf('export type ConfigNotificaciones');
    final bloque = ts.substring(inicio, fin);
    final entradas = RegExp(
      r'\{clave: "([a-z_]+)", modulo: "([a-z_]+)"',
    ).allMatches(bloque).toList();
    expect(entradas, isNotEmpty);
    for (var i = 0; i < entradas.length; i++) {
      final hasta = i + 1 < entradas.length
          ? entradas[i + 1].start
          : bloque.length;
      final cuerpo = bloque.substring(entradas[i].start, hasta);
      final clave = entradas[i].group(1)!;
      final app = kCatalogoNotificaciones.firstWhere((t) => t.clave == clave);
      expect(app.modulo, entradas[i].group(2), reason: clave);
      expect(app.critico, cuerpo.contains('critico: true'), reason: clave);
      expect(
        app.conWhatsapp,
        cuerpo.contains('rutasWhatsapp'),
        reason: clave,
      );
    }
    expect(
      [for (final t in kCatalogoNotificaciones) t.clave],
      [for (final e in entradas) e.group(1)!],
    );
    for (final t in kCatalogoNotificaciones) {
      expect(kModulosNotificacion, contains(t.modulo));
    }
  });

  test('los críticos no apagan campana ni push; WhatsApp sí', () {
    final critico = kCatalogoNotificaciones.firstWhere(
      (t) => t.clave == 'planillas_flujo',
    );
    final c = canalesDeTipo(critico, {
      'app': false,
      'push': false,
      'whatsapp': false,
    });
    expect(c[CanalNotificacion.app], isTrue);
    expect(c[CanalNotificacion.push], isTrue);
    expect(c[CanalNotificacion.whatsapp], isFalse);
  });

  test('sin ajustes: campana y push, y WhatsApp solo donde hay evento', () {
    final visitas = kCatalogoNotificaciones.firstWhere(
      (t) => t.clave == 'visitas',
    );
    expect(canalesDeTipo(visitas, null), {
      CanalNotificacion.app: true,
      CanalNotificacion.push: true,
      CanalNotificacion.whatsapp: false,
    });
    final apagado = canalesDeTipo(visitas, {'push': false});
    expect(apagado[CanalNotificacion.push], isFalse);
  });
}
