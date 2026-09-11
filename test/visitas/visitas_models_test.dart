import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/visitas/visitas_models.dart';

/// Reglas de la maqueta de Visitas de profesionales (reunión 9 sep 2026).
void main() {
  final formato = VisitaFormato(
    id: 'f1',
    empresaId: 'capital',
    areaId: 'calidad',
    areaNombre: 'Calidad',
    nombre: 'Calidad',
    items: const [
      VisitaFormatoItem(id: 'a', orden: 1, texto: 'Personal con carné'),
      VisitaFormatoItem(
        id: 'b',
        orden: 2,
        texto: 'Sin productos vencidos',
        requiereEvidencia: true,
      ),
      VisitaFormatoItem(id: 'c', orden: 3, texto: 'Refrigerio servido'),
    ],
  );

  VisitaProfesional visita({
    Map<String, VisitaRespuesta> respuestas = const {},
    String estado = kVisitaEnCurso,
    bool iniciada = true,
    DateTime? fecha,
    String centro = 'tunja',
    String sub = '',
    int? cumplimiento,
    String formatoId = 'f1',
  }) => VisitaProfesional(
    id: 'v',
    empresaId: 'capital',
    formatoId: formatoId,
    formatoNombre: 'Calidad',
    areaId: 'calidad',
    areaNombre: 'Calidad',
    centroId: centro,
    centroNombre: centro,
    subcentroId: sub,
    subcentroNombre: sub,
    profesionalId: '111',
    profesionalNombre: 'Miguel',
    asignadoPorId: '222',
    asignadoPorNombre: 'Oscar',
    fechaProgramada: fecha ?? DateTime(2026, 9, 10),
    estado: estado,
    inicio: iniciada ? VisitaMarca(at: Timestamp.now()) : null,
    respuestas: respuestas,
    cumplimiento: cumplimiento,
  );

  const cumple = VisitaRespuesta(resultado: kItemCumple);
  const noAplica = VisitaRespuesta(resultado: kItemNoAplica);
  const noCumpleSinNada = VisitaRespuesta(resultado: kItemNoCumple);
  const noCumpleConObs = VisitaRespuesta(
    resultado: kItemNoCumple,
    observacion: 'Dos yogures vencidos en la nevera 2',
  );
  final noCumpleCompleto = noCumpleConObs.copyWith(
    evidencias: const [VisitaEvidencia(url: 'u', path: 'p', nombre: 'n')],
  );

  group('resumen y porcentaje', () {
    test('no aplica no suma ni resta', () {
      // Un establecimiento sin refrigerio no pierde puntos por él.
      final r = resumenDeVisita(formato, {
        'a': cumple,
        'b': cumple,
        'c': noAplica,
      });
      expect(r.porcentaje, 100);
      expect(r.noAplica, 1);
    });

    test('sin nada evaluado el porcentaje es null, no cero', () {
      final r = resumenDeVisita(formato, {'c': noAplica});
      expect(r.porcentaje, isNull);
      expect(r.sinResponder, 2);
    });

    test('cumple sobre lo evaluado', () {
      final r = resumenDeVisita(formato, {
        'a': cumple,
        'b': noCumpleCompleto,
        'c': cumple,
      });
      expect(r.porcentaje, 67);
    });
  });

  group('cierre', () {
    test('no se cierra sin iniciar', () {
      final errores = validarCierreVisita(
        formato,
        visita(iniciada: false, respuestas: {'a': cumple, 'b': cumple, 'c': cumple}),
      );
      expect(errores.single, contains('no se ha iniciado'));
    });

    test('todo respondido y sin hallazgos cierra', () {
      expect(
        validarCierreVisita(
          formato,
          visita(respuestas: {'a': cumple, 'b': cumple, 'c': noAplica}),
        ),
        isEmpty,
      );
    });

    test('un ítem sin responder bloquea', () {
      final errores = validarCierreVisita(
        formato,
        visita(respuestas: {'a': cumple, 'b': cumple}),
      );
      expect(errores.single, contains('Ítem 3 sin responder'));
    });

    test('no cumple sin observación bloquea', () {
      // "Falló el ítem 7" no le dice al establecimiento qué corregir.
      final errores = validarCierreVisita(
        formato,
        visita(respuestas: {'a': noCumpleSinNada, 'b': cumple, 'c': cumple}),
      );
      expect(errores.single, contains('no dice por qué'));
    });

    test('no cumple donde el formato exige foto, sin foto, bloquea', () {
      final errores = validarCierreVisita(
        formato,
        visita(respuestas: {'a': cumple, 'b': noCumpleConObs, 'c': cumple}),
      );
      expect(errores.single, contains('exige foto'));
    });

    test('no cumple con observación y foto pasa', () {
      expect(
        validarCierreVisita(
          formato,
          visita(respuestas: {'a': cumple, 'b': noCumpleCompleto, 'c': cumple}),
        ),
        isEmpty,
      );
    });

    test('donde el formato no exige foto, la observación basta', () {
      expect(
        validarCierreVisita(
          formato,
          visita(respuestas: {'a': noCumpleConObs, 'b': cumple, 'c': cumple}),
        ),
        isEmpty,
      );
    });
  });

  group('hallazgos → tareas', () {
    test('un hallazgo por cada no cumple, en orden del formato', () {
      final h = hallazgosDeVisita(formato, {
        'c': noCumpleConObs,
        'a': noCumpleConObs,
        'b': cumple,
      });
      expect(h.map((x) => x.item.id), ['a', 'c']);
    });

    test('el título dice área, establecimiento y qué falló', () {
      final v = visita(centro: 'Cómbita', sub: 'Alta');
      final h = hallazgosDeVisita(formato, {'a': noCumpleConObs}).single;
      expect(
        tituloTareaHallazgo(v, h),
        'Visita Calidad · Cómbita Alta: Personal con carné',
      );
      expect(descripcionTareaHallazgo(v, h), contains('yogures vencidos'));
    });
  });

  group('cuándo se puede iniciar', () {
    test('el día programado sí, el día anterior no', () {
      final v = visita(estado: kVisitaProgramada, iniciada: false);
      expect(visitaSePuedeIniciar(v, DateTime(2026, 9, 10, 7)), isTrue);
      expect(visitaSePuedeIniciar(v, DateTime(2026, 9, 9, 23)), isFalse);
      expect(visitaSePuedeIniciar(v, DateTime(2026, 9, 12)), isTrue);
    });

    test('una en curso o terminada no se vuelve a iniciar', () {
      expect(
        visitaSePuedeIniciar(visita(estado: kVisitaEnCurso), DateTime(2026, 9, 10)),
        isFalse,
      );
    });

    test('vencida: programada, pasó el día y nadie la inició', () {
      final v = visita(estado: kVisitaProgramada, iniciada: false);
      expect(visitaVencida(v, DateTime(2026, 9, 10, 23, 59)), isFalse);
      expect(visitaVencida(v, DateTime(2026, 9, 11, 0, 1)), isTrue);
    });
  });

  group('permisos', () {
    test('solo el profesional asignado ejecuta, ni el jefe', () {
      final v = visita(estado: kVisitaProgramada);
      expect(
        visitasPuedeEjecutar(rol: kVisitasRolProfesional, visita: v, userId: '111'),
        isTrue,
      );
      expect(
        visitasPuedeEjecutar(rol: kVisitasRolProfesional, visita: v, userId: '999'),
        isFalse,
      );
      expect(
        visitasPuedeEjecutar(rol: kVisitasRolJefe, visita: v, userId: '111'),
        isFalse,
      );
    });

    test('una terminada ya no se ejecuta', () {
      expect(
        visitasPuedeEjecutar(
          rol: kVisitasRolProfesional,
          visita: visita(estado: kVisitaTerminada),
          userId: '111',
        ),
        isFalse,
      );
    });

    test('consulta ve el consolidado pero no programa', () {
      expect(visitasPuedeVerConsolidado(kVisitasRolConsulta), isTrue);
      expect(visitasPuedeProgramar(kVisitasRolConsulta), isFalse);
      expect(visitasPuedeProgramar(null), isFalse);
    });
  });

  group('formato', () {
    test('ids repetidos no pasan', () {
      final errores = validarFormato(
        formato.copyWith(
          items: const [
            VisitaFormatoItem(id: 'x', orden: 1, texto: 'A'),
            VisitaFormatoItem(id: 'x', orden: 2, texto: 'B'),
          ],
        ),
      );
      expect(errores.single, contains('repetido'));
    });

    test('los borradores sembrados son válidos y vienen como borrador', () {
      for (final f in formatosSemilla('capital')) {
        expect(validarFormato(f), isEmpty, reason: f.nombre);
        expect(f.esBorrador, isTrue);
        expect(f.nombre, contains('borrador'));
      }
    });

    test('un formato retirado no se ofrece', () {
      expect(formato.copyWith(estado: kFormatoRetirado).usable, isFalse);
      expect(formato.usable, isTrue);
    });
  });

  group('consolidado mensual', () {
    test('solo las terminadas promedian; las demás se cuentan aparte', () {
      final c = consolidarMes([
        visita(estado: kVisitaTerminada, cumplimiento: 80, centro: 'tunja'),
        visita(estado: kVisitaTerminada, cumplimiento: 100, centro: 'tumaco'),
        visita(estado: kVisitaProgramada, iniciada: false, centro: 'modelo'),
        visita(estado: kVisitaCancelada, centro: 'modelo'),
      ]);
      expect(c.visitasTerminadas, 2);
      expect(c.visitasProgramadas, 1);
      expect(c.visitasCanceladas, 1);
      expect(c.promedioGeneral, 90);
    });

    test('los peores establecimientos salen primero', () {
      final c = consolidarMes([
        visita(estado: kVisitaTerminada, cumplimiento: 100, centro: 'tumaco'),
        visita(estado: kVisitaTerminada, cumplimiento: 60, centro: 'tunja'),
      ]);
      expect(c.porEstablecimiento.first.nombre, 'tunja');
    });

    test('un subcentro es su propia fila', () {
      final c = consolidarMes([
        visita(estado: kVisitaTerminada, cumplimiento: 90, centro: 'combita', sub: 'Alta'),
        visita(estado: kVisitaTerminada, cumplimiento: 50, centro: 'combita', sub: 'Media'),
      ]);
      expect(c.porEstablecimiento, hasLength(2));
      expect(c.porEstablecimiento.first.nombre, 'combita Media');
    });

    test('los ítems más incumplidos llevan su texto', () {
      final c = consolidarMes(
        [
          visita(
            estado: kVisitaTerminada,
            cumplimiento: 33,
            respuestas: {'a': noCumpleConObs, 'b': noCumpleCompleto},
          ),
          visita(
            estado: kVisitaTerminada,
            cumplimiento: 67,
            respuestas: {'b': noCumpleCompleto},
            centro: 'tumaco',
          ),
        ],
        formatos: {'f1': formato},
      );
      expect(c.hallazgos, 3);
      expect(c.itemsCriticos.first.texto, 'Sin productos vencidos');
      expect(c.itemsCriticos.first.incumplimientos, 2);
    });

    test('si el formato ya no existe, el ítem sale con su id y no se pierde', () {
      final c = consolidarMes([
        visita(
          estado: kVisitaTerminada,
          cumplimiento: 0,
          respuestas: {'zz': noCumpleConObs},
          formatoId: 'borrado',
        ),
      ]);
      expect(c.itemsCriticos.single.texto, 'zz');
    });
  });

  group('serialización', () {
    test('ida y vuelta conserva respuestas, marcas y evidencias', () {
      final v = visita(
        respuestas: {'b': noCumpleCompleto},
        cumplimiento: 50,
      );
      final leida = VisitaProfesional.fromMap('v', v.toMap());
      expect(leida.respuestas['b']?.resultado, kItemNoCumple);
      expect(leida.respuestas['b']?.evidencias.single.url, 'u');
      expect(leida.inicio, isNotNull);
      expect(leida.cumplimiento, 50);
      expect(leida.establecimiento, 'tunja');
    });
  });
}
