import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/interventoria/interventoria_models.dart';

/// Seguimiento con histórico (11 sep 2026): calidad escribe, sube evidencia,
/// queda quién y cuándo, y al responsable le llega la guía.
void main() {
  group('quién registra seguimiento', () {
    test('calidad sí, aunque no tenga escritura general', () {
      expect(puedeRegistrarSeguimiento(kRolInterventoriaCalidad), isTrue);
      expect(
        kInterventoriaRolesEscritura,
        isNot(contains(kRolInterventoriaCalidad)),
      );
    });

    test('los de escritura también; sin rol, no', () {
      expect(puedeRegistrarSeguimiento(kRolInterventoriaAdmin), isTrue);
      expect(puedeRegistrarSeguimiento(kRolInterventoriaRevisor), isTrue);
      expect(puedeRegistrarSeguimiento(''), isFalse);
      expect(puedeRegistrarSeguimiento('otro'), isFalse);
    });

    test('calidad sigue sin reasignar ni editar el maestro', () {
      expect(puedeReasignarResponsable(kRolInterventoriaCalidad), isFalse);
      expect(
        puedeEditarMaestroSubsanaciones(kRolInterventoriaCalidad),
        isFalse,
      );
    });
  });

  group('validación', () {
    test('sin texto no hay seguimiento: una foto sola no guía', () {
      expect(validarSeguimiento(''), isNotNull);
      expect(validarSeguimiento('   '), isNotNull);
      expect(validarSeguimiento('ok'), isNotNull);
      expect(validarSeguimiento('Cambiar el empaque del congelador 2'), isNull);
    });
  });

  group('histórico', () {
    test('se lee ordenado del más antiguo al más reciente', () {
      final data = {
        'seguimientos': [
          {
            'id': 'b',
            'texto': 'Segundo',
            'autorId': '1',
            'fecha': Timestamp.fromDate(DateTime(2026, 9, 11)),
          },
          {
            'id': 'a',
            'texto': 'Primero',
            'autorId': '1',
            'fecha': Timestamp.fromDate(DateTime(2026, 9, 10)),
          },
        ],
      };
      final lista = seguimientosDesdeData(data);
      expect(lista.map((s) => s.texto), ['Primero', 'Segundo']);
    });

    test('un hallazgo viejo con solo el texto no pierde ese texto', () {
      final lista = seguimientosDesdeData({
        'seguimiento': 'Se acordó pintar la pared',
        'updatedAt': Timestamp.fromDate(DateTime(2026, 8, 1)),
      });
      expect(lista, hasLength(1));
      expect(lista.single.texto, 'Se acordó pintar la pared');
      expect(lista.single.autorId, isEmpty);
    });

    test('si hay histórico, el texto viejo no se duplica', () {
      final lista = seguimientosDesdeData({
        'seguimiento': 'Último',
        'seguimientos': [
          {
            'id': 'x',
            'texto': 'Último',
            'autorId': '1',
            'fecha': Timestamp.now(),
          },
        ],
      });
      expect(lista, hasLength(1));
    });

    test('ida y vuelta conserva autor y evidencias', () {
      final s = InterventoriaSeguimiento(
        id: 'k',
        texto: 'Texto',
        autorId: '123',
        autorNombre: 'Loren',
        autorRol: kRolInterventoriaCalidad,
        fecha: Timestamp.fromDate(DateTime(2026, 9, 11, 8)),
        adjuntos: [
          InterventoriaAdjunto(
            url: 'u',
            nombre: 'foto.jpg',
            path: 'p',
            contentType: 'image/jpeg',
            origen: 'mobile_camera',
            fechaSubida: Timestamp.now(),
          ),
        ],
      );
      final leido = InterventoriaSeguimiento.fromMap(s.toMap());
      expect(leido.autorNombre, 'Loren');
      expect(leido.adjuntos.single.nombre, 'foto.jpg');
    });
  });

  group('la notificación es la guía', () {
    final h = InterventoriaHallazgo(
      id: 'h1',
      empresaId: 'capital',
      visitaId: 'v1',
      centroCostoId: 'tunja',
      centroCostoNombre: 'Tunja',
      numeroHallazgo: '3.2',
      numeralActa: '3.2',
      descripcion: 'Congelador sin registro de temperatura',
      fechaHallazgo: Timestamp.now(),
      createdAt: Timestamp.now(),
      responsableId: '999',
      responsableNombre: 'Admin Tunja',
    );

    test('título con establecimiento y numeral, cuerpo con quién y qué', () {
      final s = InterventoriaSeguimiento(
        id: 'k',
        texto: 'Registrar temperatura dos veces al día desde mañana',
        autorId: '1',
        autorNombre: 'Loren',
        fecha: Timestamp.now(),
        adjuntos: const [],
      );
      expect(
        tituloNotificacionSeguimiento(h),
        'Seguimiento · Tunja · Obs. 3.2',
      );
      final cuerpo = cuerpoNotificacionSeguimiento(h, s);
      expect(cuerpo, startsWith('Loren: Registrar temperatura'));
      expect(cuerpo, isNot(contains('adjunto')));
    });

    test('con evidencia lo dice, y un texto largo se recorta', () {
      final s = InterventoriaSeguimiento(
        id: 'k',
        texto: 'x' * 300,
        autorId: '1',
        autorNombre: 'Loren',
        fecha: Timestamp.now(),
        adjuntos: [
          InterventoriaAdjunto(
            url: 'u',
            nombre: 'f',
            path: 'p',
            contentType: 'image/jpeg',
            origen: 'w',
            fechaSubida: Timestamp.now(),
          ),
        ],
      );
      final cuerpo = cuerpoNotificacionSeguimiento(h, s);
      expect(cuerpo, contains('1 adjunto(s)'));
      expect(cuerpo.length, lessThan(220));
    });
  });
}
