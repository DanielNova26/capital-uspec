// Reglas del tablero de contratación que se acordaron en la reunión del
// 22 ago 2026:
//   * el avance se registra POR CANDIDATO, no como un estado global de la
//     vacante;
//   * la información se presenta ordenada por establecimiento;
//   * el salario es un número, escríbalo como lo escriba quien digita.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/talento_humano/personnel_requisition_models.dart';
import 'package:todo/talento_humano/personnel_requisition_service.dart';
import 'package:todo/utils/text_input_formatters.dart';

PersonnelRequisition _req({
  String id = 'R1',
  String establishment = 'PICOTA',
  String position = 'NUTRICIONISTA',
  int quantity = 1,
  DateTime? requestDate,
  List<PersonnelCandidate> candidates = const [],
  List<PersonnelHire> hires = const [],
  PersonnelRequisitionStage stage = PersonnelRequisitionStage.requested,
}) => PersonnelRequisition(
  id: id,
  empresaId: 'EMP1',
  establishment: establishment,
  position: position,
  quantity: quantity,
  requestDate: requestDate ?? DateTime(2026, 8, 1),
  candidates: candidates,
  hires: hires,
  stage: stage,
);

PersonnelCandidate _cand(
  String document,
  PersonnelCandidateStage stage, {
  String names = 'ANA',
}) => PersonnelCandidate(document: document, names: names, stage: stage);

void main() {
  group('avance individual por candidato', () {
    test('cada aspirante lleva su propia etapa', () {
      final row = _req(
        candidates: [
          _cand('1', PersonnelCandidateStage.interview, names: 'ANA'),
          _cand('2', PersonnelCandidateStage.exams, names: 'LUIS'),
          _cand('3', PersonnelCandidateStage.discarded, names: 'PEDRO'),
        ],
      );
      expect(row.activeCandidates.length, 2);
      expect(row.discardedCandidates.single.names, 'PEDRO');
      expect(
        row.candidateStageCounts[PersonnelCandidateStage.interview],
        1,
      );
    });

    test('el descartado no arrastra la etapa de la vacante', () {
      // Antes, con un solo estado global, descartar al que iba adelante
      // dejaba la vacante marcada en una etapa que ya nadie ocupaba.
      final row = _req(
        candidates: [
          _cand('1', PersonnelCandidateStage.preselection),
          _cand('2', PersonnelCandidateStage.discarded),
        ],
      );
      expect(
        row.furthestCandidateStage,
        PersonnelCandidateStage.preselection,
      );
    });

    test('sin aspirantes no hay etapa derivada', () {
      expect(_req().furthestCandidateStage, isNull);
      expect(_req().candidateSummary, isEmpty);
    });

    test('el resumen dice cuántos hay en cada etapa', () {
      final row = _req(
        candidates: [
          _cand('1', PersonnelCandidateStage.interview),
          _cand('2', PersonnelCandidateStage.interview),
          _cand('3', PersonnelCandidateStage.exams),
        ],
      );
      expect(row.candidateSummary, 'En entrevistas: 2 · En exámenes: 1');
    });

    test('contratado y descartado son etapas cerradas', () {
      expect(PersonnelCandidateStage.hired.isClosed, isTrue);
      expect(PersonnelCandidateStage.discarded.isClosed, isTrue);
      expect(PersonnelCandidateStage.exams.isClosed, isFalse);
    });

    test('los contratados se siguen contando desde `contratados`', () {
      // El cierre de la vacante depende de este array porque es el que se
      // escribe junto con la creación del usuario en TBL_USUARIOS.
      final row = _req(
        quantity: 2,
        hires: const [
          PersonnelHire(document: '1', names: 'ANA', surnames: 'GOMEZ'),
        ],
        candidates: [
          _cand('1', PersonnelCandidateStage.hired),
          _cand('2', PersonnelCandidateStage.interview),
        ],
      );
      expect(row.hiredCount, 1);
      expect(row.pendingCount, 1);
    });
  });

  group('serialización', () {
    test('los candidatos sobreviven al viaje a Firestore', () {
      final original = _req(
        candidates: [
          const PersonnelCandidate(
            document: '99',
            names: 'ANA',
            surnames: 'GOMEZ',
            stage: PersonnelCandidateStage.exams,
            note: 'PENDIENTE EXAMEN DE ALTURAS',
          ),
        ],
      );
      final restored = PersonnelRequisition.fromMap('R1', original.toMap());
      final candidate = restored.candidates.single;
      expect(candidate.document, '99');
      expect(candidate.fullName, 'ANA GOMEZ');
      expect(candidate.stage, PersonnelCandidateStage.exams);
      expect(candidate.note, 'PENDIENTE EXAMEN DE ALTURAS');
    });

    test('una vacante vieja sin candidatos se lee sin romperse', () {
      final restored = PersonnelRequisition.fromMap('R1', {
        'empresaId': 'EMP1',
        'establecimiento': 'LA PICOTA',
        'cargo': 'AUXILIAR',
        'cantidad': 1,
      });
      expect(restored.candidates, isEmpty);
      expect(restored.candidateSummary, isEmpty);
    });

    test('los aspirantes salen del más avanzado al menos avanzado', () {
      final restored = PersonnelRequisition.fromMap('R1', {
        'empresaId': 'EMP1',
        'establecimiento': 'PICOTA',
        'cargo': 'AUXILIAR',
        'cantidad': 3,
        'candidatos': [
          {'documento': '1', 'nombres': 'ANA', 'etapa': 'reclutamiento'},
          {'documento': '2', 'nombres': 'LUIS', 'etapa': 'documentos'},
          {'documento': '3', 'nombres': 'EVA', 'etapa': 'entrevista'},
        ],
      });
      expect(
        restored.candidates.map((item) => item.names).toList(),
        ['LUIS', 'EVA', 'ANA'],
      );
    });

    test('un candidato sin documento se descarta al leer', () {
      // Sin documento no hay forma de moverlo de etapa: la transacción lo
      // busca por ese campo.
      final restored = PersonnelRequisition.fromMap('R1', {
        'empresaId': 'EMP1',
        'establecimiento': 'PICOTA',
        'cargo': 'AUXILIAR',
        'cantidad': 1,
        'candidatos': [
          {'nombres': 'SIN CEDULA'},
          {'documento': '7', 'nombres': 'ANA'},
        ],
      });
      expect(restored.candidates.single.document, '7');
    });
  });

  group('orden por establecimiento', () {
    test('agrupa por sede y dentro de cada una lo más reciente primero', () {
      final rows = [
        _req(id: 'a', establishment: 'PICOTA', requestDate: DateTime(2026, 8, 1)),
        _req(id: 'b', establishment: 'BUEN PASTOR', requestDate: DateTime(2026, 7, 1)),
        _req(id: 'c', establishment: 'PICOTA', requestDate: DateTime(2026, 8, 20)),
      ]..sort(PersonnelRequisitionService.comparePersonnelRequisitions);
      expect(rows.map((row) => row.id).toList(), ['b', 'c', 'a']);
    });

    test('el orden no depende de mayúsculas', () {
      final rows = [
        _req(id: 'a', establishment: 'picota'),
        _req(id: 'b', establishment: 'BUEN PASTOR'),
      ]..sort(PersonnelRequisitionService.comparePersonnelRequisitions);
      expect(rows.first.id, 'b');
    });

    test('a igual sede y fecha, desempata el cargo', () {
      final rows = [
        _req(id: 'a', position: 'NUTRICIONISTA'),
        _req(id: 'b', position: 'AUXILIAR'),
      ]..sort(PersonnelRequisitionService.comparePersonnelRequisitions);
      expect(rows.first.id, 'b');
    });
  });

  group('salario', () {
    test('acepta las tres formas de escribir un importe', () {
      expect(parseMontoColombiano('1423500'), 1423500);
      expect(parseMontoColombiano('1.423.500'), 1423500);
      expect(parseMontoColombiano('1,423,500'), 1423500);
      expect(parseMontoColombiano(r'$ 1.423.500'), 1423500);
    });

    test('sin dígitos devuelve null, no cero', () {
      // "no lo diligenciaron" y "vale cero" no son lo mismo en el informe.
      expect(parseMontoColombiano(''), isNull);
      expect(parseMontoColombiano('  '), isNull);
      expect(parseMontoColombiano('N/A'), isNull);
      expect(parseMontoColombiano('0'), 0);
    });
  });

  group('nombres de aspirantes y contratados', () {
    const formatter = CapitalizedWordsTextFormatter();

    TextEditingValue escribir(String texto) => formatter.formatEditUpdate(
      const TextEditingValue(),
      TextEditingValue(
        text: texto,
        selection: TextSelection.collapsed(offset: texto.length),
      ),
    );

    test('fuerza inicial mayúscula en cada palabra', () {
      expect(
        capitalizarPalabras('mARÍA fernanda de la cruz'),
        'María Fernanda De La Cruz',
      );
      expect(capitalizarPalabras("juan-pablo o'connor"), "Juan-Pablo O'Connor");
    });

    test('también normaliza texto pegado en el formulario', () {
      final value = escribir('ana maría gómez');
      expect(value.text, 'Ana María Gómez');
      expect(value.selection.baseOffset, value.text.length);
    });
  });

  group('el salario se ve como moneda mientras se escribe', () {
    const fmt = MonedaInputFormatter();

    TextEditingValue escribir(String texto) => fmt.formatEditUpdate(
      const TextEditingValue(),
      TextEditingValue(
        text: texto,
        selection: TextSelection.collapsed(offset: texto.length),
      ),
    );

    test('agrupa en miles al teclear', () {
      expect(escribir('1').text, '1');
      expect(escribir('142').text, '142');
      expect(escribir('1423').text, '1.423');
      expect(escribir('1423500').text, '1.423.500');
    });

    test('descarta letras y simbolos', () {
      // Lo que se pegue desde otro lado tambien queda limpio.
      expect(escribir(r'$ 1.423.500 COP').text, '1.423.500');
      expect(escribir('abc').text, '');
    });

    test('el cursor queda despues del ultimo digito escrito', () {
      // Sin contar digitos, insertar el punto empujaba el cursor hacia atras.
      final value = escribir('1423');
      expect(value.text, '1.423');
      expect(value.selection.baseOffset, value.text.length);
    });

    test('el cursor respeta una edicion en la mitad del numero', () {
      // "1.423.500" con el cursor tras el "1" -> se teclea un 9 ahi.
      const previo = TextEditingValue(
        text: '1.423.500',
        selection: TextSelection.collapsed(offset: 1),
      );
      const tecleado = TextEditingValue(
        text: '19.423.500',
        selection: TextSelection.collapsed(offset: 2),
      );
      final value = fmt.formatEditUpdate(previo, tecleado);
      expect(value.text, '19.423.500');

      // La garantia no es una posicion fija sino que se conserve la CANTIDAD
      // de digitos a la izquierda del cursor: al reagrupar, el texto crece y
      // un desplazamiento crudo dejaria el cursor corrido.
      int digitos(String texto) => texto.replaceAll('.', '').length;
      expect(
        digitos(value.text.substring(0, value.selection.baseOffset)),
        digitos(tecleado.text.substring(0, tecleado.selection.baseOffset)),
      );
    });

    test('un numero absurdo no reemplaza lo ya escrito', () {
      const previo = TextEditingValue(text: '1.423.500');
      final value = fmt.formatEditUpdate(
        previo,
        const TextEditingValue(text: '9999999999999999'),
      );
      expect(value.text, '1.423.500');
    });

    test('borrar todo deja el campo vacio', () {
      expect(escribir('').text, isEmpty);
    });

    test('lo que se ve se puede volver a leer como numero', () {
      // El ciclo completo: se teclea, se muestra agrupado, se guarda numero.
      expect(parseMontoColombiano(escribir('1423500').text), 1423500);
    });

    test('agruparMiles y el formateador coinciden', () {
      // El campo se inicializa con agruparMiles al editar una vacante; si las
      // dos formas no coincidieran, el primer tecleo reacomodaria el valor.
      expect(agruparMiles('1423500'), escribir('1423500').text);
      expect(agruparMiles('500'), '500');
      expect(agruparMiles(''), isEmpty);
    });
  });
}
