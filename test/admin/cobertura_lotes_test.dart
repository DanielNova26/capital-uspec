import 'package:flutter_test/flutter_test.dart';
import 'package:todo/admin/cobertura_lotes.dart';
import 'package:todo/interventoria/interventoria_revision_maestro.dart';
import 'package:todo/interventoria/interventoria_service.dart';

InterventoriaUsuario _u(
  String id, {
  Set<String> operacion = const {},
  Set<String> trabajo = const {},
  Set<String> grupos = const {},
}) => InterventoriaUsuario(
  id: id,
  nombre: 'Persona $id',
  cargo: 'Administrador',
  centroId: '',
  areaId: '',
  centrosOperacionIds: operacion,
  centrosTrabajoIds: trabajo,
  centrosAsignadosIds: {...operacion, ...trabajo},
  grupos: grupos,
);

void main() {
  globales();
  test('el estado después replica lo que escribe la aplicación', () {
    const antes = SedesPersona(
      operacion: {'moniquira'},
      trabajo: {'moniquira', 'picota'},
      grupos: {'G7'},
    );
    final quitar = estadoDespues(
      antes,
      const CambioCobertura(userId: '1', nombre: 'x', quitarGrupos: {'G7'}),
    );
    expect(quitar.grupos, isEmpty);
    expect(quitar.operacion, {'moniquira'});

    final fijar = estadoDespues(
      antes,
      const CambioCobertura(
        userId: '1',
        nombre: 'x',
        fijarOperacion: {'lamesa'},
        fijarGrupos: {},
      ),
    );
    expect(fijar.operacion, {'lamesa'});
    expect(fijar.trabajo, {'moniquira', 'picota'});
    expect(fijar.grupos, isEmpty);

    final agregar = estadoDespues(
      antes,
      const CambioCobertura(
        userId: '1',
        nombre: 'x',
        agregarCentros: {'lamesa'},
        quitarCentros: {'picota'},
      ),
    );
    expect(agregar.operacion, {'moniquira', 'lamesa'});
    expect(agregar.trabajo, {'moniquira'});
  });

  test('el respaldo guarda cómo estaba y cómo quedará cada persona', () {
    final actuales = {
      '1': _u('1', operacion: {'moniquira'}, grupos: {'G7'}),
    };
    final lote = prepararLote(const [
      CambioCobertura(userId: '1', nombre: 'Persona 1', quitarGrupos: {'G7'}),
      CambioCobertura(userId: '99', nombre: 'No existe', quitarGrupos: {'G1'}),
    ], actuales);
    expect(lote.length, 1);
    expect(lote.single.antes.grupos, {'G7'});
    expect(lote.single.despues.grupos, isEmpty);
    // Ida y vuelta por el mapa que se guarda en Firestore.
    final otra = PersonaDelLote.fromMap(lote.single.toMap());
    expect(otra.antes.igualA(lote.single.antes), isTrue);
    expect(otra.despues.igualA(lote.single.despues), isTrue);
  });

  group('deshacer', () {
    final persona = PersonaDelLote(
      userId: '1',
      nombre: 'Persona 1',
      antes: const SedesPersona(operacion: {'moniquira'}, grupos: {'G7'}),
      despues: const SedesPersona(operacion: {'moniquira'}),
    );

    test('devuelve a quien quedó como el lote lo dejó', () {
      final r = planDeshacer(
        [persona],
        {
          '1': _u('1', operacion: {'moniquira'}),
        },
      );
      final c = r.cambios.single;
      expect(c.userId, '1');
      expect(c.fijarOperacion, {'moniquira'});
      expect(c.fijarTrabajo, isEmpty);
      expect(c.fijarGrupos, {'G7'});
    });

    test('no pisa a quien alguien cambió después del lote', () {
      final r = planDeshacer(
        [persona],
        {
          '1': _u('1', operacion: {'picota'}),
        },
      );
      expect(r.cambios, isEmpty);
      expect(r.modificadasDespues, ['Persona 1']);
    });

    test('quien ya estaba como antes no se toca, ni a quien ya no está', () {
      final r = planDeshacer(
        [
          persona,
          const PersonaDelLote(
            userId: '2',
            nombre: 'Persona 2',
            antes: SedesPersona(),
            despues: SedesPersona(operacion: {'a'}),
          ),
        ],
        {
          '1': _u('1', operacion: {'moniquira'}, grupos: {'G7'}),
        },
      );
      expect(r.cambios, isEmpty);
      expect(r.sinCambio, 1);
      expect(r.noEncontradas, ['Persona 2']);
    });

    test('un lote aplicado a medias también se puede deshacer', () {
      // Una persona ya cambió y otra no llegó a cambiar.
      final dos = [
        persona,
        PersonaDelLote(
          userId: '2',
          nombre: 'Persona 2',
          antes: const SedesPersona(grupos: {'G1'}),
          despues: const SedesPersona(),
        ),
      ];
      final r = planDeshacer(dos, {
        '1': _u('1', operacion: {'moniquira'}),
        '2': _u('2', grupos: {'G1'}),
      });
      expect(r.cambios.map((c) => c.userId), ['1']);
      expect(r.sinCambio, 1);
    });
  });
}

void globales() {
  test('la marca de todas las sedes entra al respaldo y se deshace', () {
    final antes = InterventoriaUsuario(
      id: '1',
      nombre: 'Persona 1',
      cargo: 'Tesorero',
      centroId: '',
      areaId: '',
    );
    final lote = prepararLote(
      const [
        CambioCobertura(userId: '1', nombre: 'Persona 1', fijarTodas: true),
      ],
      {'1': antes},
    );
    expect(lote.single.antes.todas, isFalse);
    expect(lote.single.despues.todas, isTrue);
    expect(PersonaDelLote.fromMap(lote.single.toMap()).despues.todas, isTrue);

    final hoy = InterventoriaUsuario(
      id: '1',
      nombre: 'Persona 1',
      cargo: 'Tesorero',
      centroId: '',
      areaId: '',
      cubreTodas: true,
    );
    final r = planDeshacer(lote, {'1': hoy});
    expect(r.cambios.single.fijarTodas, isFalse);
  });
}
