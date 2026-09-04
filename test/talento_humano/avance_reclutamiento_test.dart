import 'package:flutter_test/flutter_test.dart';
import 'package:todo/talento_humano/personnel_recruitment_summary_pdf.dart';
import 'package:todo/talento_humano/personnel_requisition_models.dart';

PersonnelRequisition _solicitud({
  String id = 'r1',
  String establecimiento = 'Cómbita',
  int cantidad = 1,
  int contratados = 0,
  PersonnelRequisitionStage etapa = PersonnelRequisitionStage.recruitment,
  DateTime? pedida,
}) => PersonnelRequisition(
  id: id,
  empresaId: 'e1',
  establishment: establecimiento,
  position: 'Auxiliar',
  quantity: cantidad,
  requestDate: pedida ?? DateTime(2026, 9, 1),
  stage: etapa,
  hires: [
    for (var i = 0; i < contratados; i++)
      PersonnelHire(document: '$id-$i', names: 'N$i', surnames: 'A$i'),
  ],
);

void main() {
  final hoy = DateTime(2026, 10, 1);

  group('conteos básicos', () {
    test('suma lo pedido, lo cubierto y lo que falta', () {
      final a = calcularAvanceReclutamiento([
        _solicitud(id: 'r1', cantidad: 3, contratados: 1),
        _solicitud(id: 'r2', cantidad: 2, contratados: 2),
      ], hoy: hoy);

      expect(a.solicitadas, 5);
      expect(a.contratadas, 3);
      expect(a.vacantesAbiertas, 2);
      expect(a.cobertura, closeTo(0.6, 0.001));
    });

    test('sin solicitudes no divide por cero', () {
      final a = calcularAvanceReclutamiento(const [], hoy: hoy);
      expect(a.solicitadas, 0);
      expect(a.cobertura, 0);
      expect(a.diasPromedioAbiertos, 0);
      expect(a.diasMasAntiguo, 0);
      expect(a.porEstablecimiento, isEmpty);
    });
  });

  group('canceladas', () {
    test('no se cuentan como solicitadas', () {
      // Sumarlas hundiría la cobertura por vacantes que nadie espera que se
      // llenen.
      final a = calcularAvanceReclutamiento([
        _solicitud(id: 'r1', cantidad: 2, contratados: 2),
        _solicitud(
          id: 'r2',
          cantidad: 8,
          etapa: PersonnelRequisitionStage.cancelled,
        ),
      ], hoy: hoy);

      expect(a.solicitadas, 2);
      expect(a.cobertura, 1);
      expect(a.procesosCancelados, 1);
      expect(a.procesos, 2);
    });

    test('tampoco cuentan como proceso abierto', () {
      final a = calcularAvanceReclutamiento([
        _solicitud(id: 'r1', etapa: PersonnelRequisitionStage.cancelled),
      ], hoy: hoy);
      expect(a.procesosAbiertos, 0);
    });
  });

  group('embudo por etapa', () {
    test('cuenta las vacantes pendientes de cada proceso abierto', () {
      final a = calcularAvanceReclutamiento([
        _solicitud(
          id: 'r1',
          cantidad: 3,
          contratados: 1,
          etapa: PersonnelRequisitionStage.interview,
        ),
        _solicitud(
          id: 'r2',
          cantidad: 2,
          etapa: PersonnelRequisitionStage.interview,
        ),
        _solicitud(
          id: 'r3',
          cantidad: 4,
          etapa: PersonnelRequisitionStage.exams,
        ),
      ], hoy: hoy);

      expect(a.vacantesPorEtapa[PersonnelRequisitionStage.interview], 4);
      expect(a.vacantesPorEtapa[PersonnelRequisitionStage.exams], 4);
    });

    test('un proceso ya contratado no aparece en el embudo', () {
      final a = calcularAvanceReclutamiento([
        _solicitud(
          id: 'r1',
          cantidad: 1,
          contratados: 1,
          etapa: PersonnelRequisitionStage.hired,
        ),
      ], hoy: hoy);
      expect(a.vacantesPorEtapa, isEmpty);
      expect(a.procesosAbiertos, 0);
    });
  });

  group('antigüedad', () {
    test('se cuenta desde la fecha de solicitud, solo para los abiertos', () {
      final a = calcularAvanceReclutamiento([
        _solicitud(id: 'r1', pedida: DateTime(2026, 9, 1)), // 30 días
        _solicitud(id: 'r2', pedida: DateTime(2026, 9, 21)), // 10 días
        _solicitud(
          id: 'r3',
          pedida: DateTime(2025, 1, 1),
          contratados: 1,
          etapa: PersonnelRequisitionStage.hired,
        ),
      ], hoy: hoy);

      expect(a.diasMasAntiguo, 30);
      expect(a.diasPromedioAbiertos, 20);
    });

    test('una fecha futura no produce días negativos', () {
      final a = calcularAvanceReclutamiento([
        _solicitud(id: 'r1', pedida: DateTime(2026, 12, 1)),
      ], hoy: hoy);
      expect(a.diasMasAntiguo, 0);
    });
  });

  group('por establecimiento', () {
    test('ordena primero lo que más falta', () {
      final a = calcularAvanceReclutamiento([
        _solicitud(id: 'r1', establecimiento: 'Picota', cantidad: 1),
        _solicitud(id: 'r2', establecimiento: 'Cómbita', cantidad: 5),
      ], hoy: hoy);

      expect(a.porEstablecimiento.first.establecimiento, 'Cómbita');
      expect(a.porEstablecimiento.first.vacantesAbiertas, 5);
      expect(a.porEstablecimiento.last.establecimiento, 'Picota');
    });

    test('agrupa varias solicitudes del mismo establecimiento', () {
      final a = calcularAvanceReclutamiento([
        _solicitud(id: 'r1', establecimiento: 'Cómbita', cantidad: 2),
        _solicitud(
          id: 'r2',
          establecimiento: 'Cómbita',
          cantidad: 3,
          contratados: 3,
          etapa: PersonnelRequisitionStage.hired,
        ),
      ], hoy: hoy);

      expect(a.porEstablecimiento, hasLength(1));
      final combita = a.porEstablecimiento.single;
      expect(combita.solicitadas, 5);
      expect(combita.contratadas, 3);
      expect(combita.vacantesAbiertas, 2);
      expect(combita.procesosAbiertos, 1);
    });

    test('sin establecimiento no deja el grupo sin nombre', () {
      final a = calcularAvanceReclutamiento([
        _solicitud(id: 'r1', establecimiento: '  '),
      ], hoy: hoy);
      expect(
        a.porEstablecimiento.single.establecimiento,
        'Sin establecimiento',
      );
    });
  });
}
