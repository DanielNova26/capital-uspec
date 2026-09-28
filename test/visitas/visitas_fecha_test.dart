import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/visitas/visitas_models.dart';

/// Cambios del 28 sep 2026 (documento "Cambios módulo visitas"): la visita
/// se programa sin formato y el profesional lo elige al iniciar; se hace y
/// se cierra el mismo día; el profesional pide el cambio de fecha a su jefe.
void main() {
  VisitaProfesional visita({
    String id = 'v',
    String estado = kVisitaProgramada,
    DateTime? fecha,
    DateTime? inicio,
    bool esPrueba = false,
    String formatoId = '',
    VisitaSolicitudFecha? solicitud,
    String centro = 'tunja',
  }) => VisitaProfesional(
    id: id,
    empresaId: 'capital',
    formatoId: formatoId,
    formatoNombre: formatoId.isEmpty ? '' : 'SST',
    areaId: 'AREA_003_talento_humano',
    areaNombre: 'Talento Humano',
    centroId: centro,
    centroNombre: centro,
    profesionalId: 'yesika',
    profesionalNombre: 'Yesika',
    asignadoPorId: 'zuly',
    asignadoPorNombre: 'Zuly',
    fechaProgramada: fecha ?? DateTime(2026, 10, 6),
    estado: estado,
    esPrueba: esPrueba,
    inicio: inicio == null ? null : VisitaMarca(at: Timestamp.fromDate(inicio)),
    solicitudFecha: solicitud,
  );

  VisitaFormato formato(
    String id, {
    String area = 'AREA_003_talento_humano',
    String estado = kFormatoVigente,
    List<String> cargos = const [],
    bool predeterminado = false,
    String empresa = 'capital',
  }) => VisitaFormato(
    id: id,
    empresaId: empresa,
    areaId: area,
    areaNombre: 'Talento Humano',
    nombre: id,
    estado: estado,
    cargos: cargos,
    predeterminado: predeterminado,
    items: const [VisitaFormatoItem(id: 'a', orden: 1, texto: 'Algo')],
  );

  group('se programa sin formato', () {
    test('la visita dice que todavía no tiene formato', () {
      expect(visita().tieneFormato, isFalse);
      expect(visita(formatoId: 'f1').tieneFormato, isTrue);
    });

    test('el profesional escoge entre los de su departamento y su cargo', () {
      final formatos = [
        formato('SST', predeterminado: true),
        formato('Botiquín', cargos: ['Supervisor De Hse']),
        formato('Nómina', cargos: ['Analista de nómina']),
        formato('Borrador', estado: kFormatoBorrador),
        formato('Retirado', estado: kFormatoRetirado),
        formato('Contabilidad', area: 'AREA_001_contabilidad'),
        // El SST viejo: "hse" no es el departamento de la visita.
        formato('HSE', area: 'hse'),
        formato('Otra empresa', empresa: 'otra'),
      ];
      final real = formatosParaVisita(
        formatos,
        visita: visita(),
        cargo: 'Supervisor de HSE',
      );
      // El de su cargo primero (es el que se propondría), luego el resto.
      expect(real.map((f) => f.id), ['Botiquín', 'SST']);
      final prueba = formatosParaVisita(
        formatos,
        visita: visita(esPrueba: true),
        cargo: 'Supervisor de HSE',
      );
      expect(prueba.map((f) => f.id), contains('Borrador'));
    });
  });

  group('mismo día', () {
    final dia = DateTime(2026, 10, 6);

    test('se inicia solo el día programado', () {
      final v = visita(fecha: dia);
      expect(motivoNoIniciaHoy(v, DateTime(2026, 10, 6, 8)), isNull);
      expect(
        motivoNoIniciaHoy(v, DateTime(2026, 10, 5, 18)),
        contains('se inicia ese día'),
      );
      expect(
        motivoNoIniciaHoy(v, DateTime(2026, 10, 7, 8)),
        contains('cambio de fecha'),
      );
    });

    test('la prueba se puede iniciar ese día o después', () {
      final v = visita(fecha: dia, esPrueba: true);
      expect(visitaSePuedeIniciar(v, DateTime(2026, 10, 9)), isTrue);
      expect(visitaSePuedeIniciar(v, DateTime(2026, 10, 5)), isFalse);
    });

    test('se cierra el mismo día en que se inició', () {
      final v = visita(
        estado: kVisitaEnCurso,
        fecha: dia,
        inicio: DateTime(2026, 10, 6, 9),
      );
      expect(motivoNoCierraHoy(v, DateTime(2026, 10, 6, 17)), isNull);
      expect(
        motivoNoCierraHoy(v, DateTime(2026, 10, 7, 8)),
        contains('debía cerrarse ese mismo día'),
      );
      // Una prueba no tiene la restricción.
      expect(
        motivoNoCierraHoy(
          visita(estado: kVisitaEnCurso, fecha: dia, esPrueba: true),
          DateTime(2026, 10, 9),
        ),
        isNull,
      );
    });
  });

  group('registro de visita: el profesional la elige', () {
    test('hoy, en curso y las que pasaron sin hacerse', () {
      final ahora = DateTime(2026, 10, 6, 9);
      final r = visitasParaRegistro([
        visita(id: 'hoy', fecha: DateTime(2026, 10, 6)),
        visita(id: 'manana', fecha: DateTime(2026, 10, 7)),
        visita(id: 'ayer', fecha: DateTime(2026, 10, 5)),
        visita(
          id: 'curso',
          estado: kVisitaEnCurso,
          fecha: DateTime(2026, 10, 5),
          inicio: DateTime(2026, 10, 5, 9),
        ),
        visita(id: 'hecha', estado: kVisitaTerminada),
      ], ahora);
      expect(r.hoy.map((v) => v.id), ['hoy']);
      expect(r.enCurso.map((v) => v.id), ['curso']);
      expect(r.vencidas.map((v) => v.id), ['ayer']);
    });
  });

  group('solicitud de cambio de fecha', () {
    final hoy = DateTime(2026, 10, 6);

    test('se pide con fecha futura y motivo, una a la vez', () {
      final v = visita(fecha: DateTime(2026, 10, 6));
      expect(
        validarSolicitudFecha(
          v,
          fecha: DateTime(2026, 10, 8),
          motivo: 'Paro',
          hoy: hoy,
        ),
        isNull,
      );
      expect(
        validarSolicitudFecha(
          v,
          fecha: DateTime(2026, 10, 1),
          motivo: 'Paro',
          hoy: hoy,
        ),
        contains('anterior a hoy'),
      );
      expect(
        validarSolicitudFecha(
          v,
          fecha: DateTime(2026, 10, 8),
          motivo: ' ',
          hoy: hoy,
        ),
        contains('motivo'),
      );
      final pedida = visita(
        solicitud: VisitaSolicitudFecha(
          fecha: DateTime(2026, 10, 8),
          motivo: 'Paro',
          porId: 'yesika',
          porNombre: 'Yesika',
        ),
      );
      expect(
        validarSolicitudFecha(
          pedida,
          fecha: DateTime(2026, 10, 9),
          motivo: 'Otra',
          hoy: hoy,
        ),
        contains('esperando respuesta'),
      );
      expect(
        validarSolicitudFecha(
          visita(estado: kVisitaTerminada),
          fecha: DateTime(2026, 10, 9),
          motivo: 'Otra',
          hoy: hoy,
        ),
        isNotNull,
      );
    });

    test('se guarda y se lee con la respuesta del jefe', () {
      final s = VisitaSolicitudFecha(
        fecha: DateTime(2026, 10, 8),
        motivo: 'Paro de transporte',
        porId: 'yesika',
        porNombre: 'Yesika',
      );
      final v = VisitaProfesional.fromMap('v', visita(solicitud: s).toMap());
      expect(v.solicitudFecha?.pendiente, isTrue);
      expect(v.solicitudFecha?.motivo, 'Paro de transporte');
      final rechazada = s.respondida(
        aprobada: false,
        porId: 'zuly',
        porNombre: 'Zuly',
        respuesta: 'Se hace en la fecha',
      );
      final leida = VisitaSolicitudFecha.fromMap(rechazada.toMap());
      expect(leida.estado, kSolicitudRechazada);
      expect(leida.respuesta, 'Se hace en la fecha');
      expect(leida.respondidaPorNombre, 'Zuly');
      expect(leida.porId, 'yesika');
    });

    test('el jefe responde; el profesional ve su consolidado', () {
      expect(visitasPuedeResponderSolicitud(kVisitasRolJefe), isTrue);
      expect(visitasPuedeResponderSolicitud(kVisitasRolProfesional), isFalse);
      expect(visitasPuedeVerConsolidado(kVisitasRolProfesional), isTrue);
    });
  });

  test('cerrar exige estar en el sitio, con el mensaje de cerrar', () {
    const ref = VisitaUbicacion(
      empresaId: 'capital',
      centroId: 'tunja',
      centroNombre: 'Tunja',
      lat: 5.5353,
      lng: -73.3678,
      radioMetros: 150,
    );
    final lejos = verificarUbicacionInicio(
      referencia: ref,
      lat: 5.5453,
      lng: -73.3678,
      accion: 'cerrar',
    );
    expect(lejos.permitido, isFalse);
    expect(lejos.motivo, contains('vuelve a él para cerrarla'));
    final sinGps = verificarUbicacionInicio(
      referencia: ref,
      lat: null,
      lng: null,
      accion: 'cerrar',
    );
    expect(sinGps.motivo, contains('no se cierra'));
  });
}
