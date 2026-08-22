import 'package:flutter_test/flutter_test.dart';
import 'package:todo/whatsapp/whatsapp_recipient_models.dart';

void main() {
  group('listado central de WhatsApp', () {
    test('conserva compatibilidad con destinatarios creados por Correo', () {
      final recipient = WhatsAppDestinatario.fromMap({
        'nombre': 'Calidad',
        'telefono': '3001234567',
        'activo': true,
      });

      expect(recipient.nombre, 'Calidad');
      expect(recipient.telefono, '3001234567');
      expect(recipient.activo, isTrue);
    });

    test('conserva el vínculo de una persona seleccionada del directorio', () {
      final recipient = WhatsAppDestinatario.fromMap({
        'nombre': 'Daniel Nova',
        'telefono': '3001234567',
        'activo': true,
        'personaId': '1019152994',
        'origen': 'directorio',
      });

      expect(recipient.personaId, '1019152994');
      expect(recipient.vinculadoAlDirectorio, isTrue);
      expect(recipient.toMap()['origen'], 'directorio');
    });

    test('cuenta únicamente las personas activas', () {
      const list = WhatsAppListado(
        id: 'lista-1',
        empresaId: 'empresa-1',
        nombre: 'Compras',
        destinatarios: [
          WhatsAppDestinatario(
            nombre: 'Persona activa',
            telefono: '3001234567',
          ),
          WhatsAppDestinatario(
            nombre: 'Persona inactiva',
            telefono: '3007654321',
            activo: false,
          ),
        ],
      );

      expect(list.destinatariosActivos, 1);
    });

    test('filtra una lista por el módulo seleccionado', () {
      const list = WhatsAppListado(
        id: 'lista-correo',
        empresaId: 'empresa-1',
        nombre: 'Alertas de correo',
        modulos: ['correo'],
        destinatarios: [],
      );

      expect(list.habilitadaPara('correo'), isTrue);
      expect(list.habilitadaPara('compras'), isFalse);
    });

    test('mantiene disponibles las listas históricas sin clasificación', () {
      const legacy = WhatsAppListado(
        id: 'lista-antigua',
        empresaId: 'empresa-1',
        nombre: 'Lista anterior',
        destinatarios: [],
      );

      expect(legacy.pendienteClasificacion, isTrue);
      expect(legacy.habilitadaPara('correo'), isTrue);
      expect(legacy.habilitadaPara('compras'), isTrue);
    });

    test('incluye todos los módulos habilitables al crear una lista', () {
      expect(kWhatsAppListModules, [
        'correo',
        'compras',
        'planillas_pago',
        'interventoria',
        'facturacion',
      ]);
    });

    test('normaliza módulos, elimina duplicados y conserva facturación', () {
      expect(
        normalizeWhatsAppListModules([
          'FACTURACION',
          'compras',
          'facturacion',
          'desconocido',
        ]),
        ['compras', 'facturacion'],
      );
    });
  });
}
