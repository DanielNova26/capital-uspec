import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/interventoria/interventoria_models.dart';

InterventoriaVisita _visita({
  required String id,
  required String centroId,
  required String centroNombre,
  required DateTime fecha,
  required double total,
  double? categoria,
  bool categoriaNoEvaluada = false,
}) {
  final items = defaultInterventoriaItems();
  final categoriaKey = kInterventoriaCategorias.first.key;
  items[categoriaKey] = items[categoriaKey]!.copyWith(
    valor: categoria,
    noEvaluado: categoriaNoEvaluada,
    clearValor: categoria == null,
  );
  return InterventoriaVisita(
    id: id,
    empresaId: 'empresa',
    centroCostoId: centroId,
    centroCostoCodigo: centroId.toUpperCase(),
    centroCostoNombre: centroNombre,
    fechaVisita: Timestamp.fromDate(fecha),
    fechaRegistro: Timestamp.fromDate(fecha),
    creadoPor: 'usuario',
    porcentajeGeneral: total,
    items: items,
    createdAt: Timestamp.fromDate(fecha),
  );
}

void main() {
  test('solo el aprobador asignado puede resolver una subsanación', () {
    final hallazgo = InterventoriaHallazgo(
      empresaId: 'empresa',
      centroCostoId: 'centro',
      centroCostoNombre: 'Centro',
      descripcion: 'Hallazgo',
      fechaHallazgo: Timestamp.fromDate(DateTime(2026, 9, 2)),
      aprobadorId: 'calidad-1',
      createdAt: Timestamp.fromDate(DateTime(2026, 9, 2)),
    );

    expect(puedeAprobarHallazgo(hallazgo, 'calidad-1'), isTrue);
    expect(puedeAprobarHallazgo(hallazgo, 'desarrollador'), isFalse);
  });

  test('la bandeja de asignación excluye lo ya subsanado', () {
    InterventoriaHallazgo hallazgo(String estado) => InterventoriaHallazgo(
      empresaId: 'empresa',
      centroCostoId: 'centro',
      centroCostoNombre: 'Centro',
      descripcion: 'Hallazgo',
      estado: estado,
      fechaHallazgo: Timestamp.fromDate(DateTime(2026, 9, 2)),
      createdAt: Timestamp.fromDate(DateTime(2026, 9, 2)),
    );

    expect(debeAparecerEnTableroAsignacion(hallazgo('activo')), isTrue);
    expect(
      debeAparecerEnTableroAsignacion(hallazgo('pendiente_aprobacion')),
      isTrue,
    );
    expect(debeAparecerEnTableroAsignacion(hallazgo('subsanado')), isFalse);
  });

  group('catálogo de establecimientos', () {
    test('lee G1/G9 de los datos sin inferirlo desde el nombre', () {
      final g1 = CentroCostoRef.fromMap('a', {
        'nombre': 'Pasto',
        'grupo': 'Grupo 1',
      });
      final g9 = CentroCostoRef.fromMap('b', {
        'nombre': 'Ipiales',
        'codigo': 'CC-G09-014',
      });
      final sinGrupo = CentroCostoRef.fromMap('c', {
        'nombre': 'Establecimiento G1 solo en el nombre',
      });

      expect(g1.grupo, 'G1');
      expect(g9.grupo, 'G9');
      expect(sinGrupo.grupo, isEmpty);
    });

    test('agrupa G1 y G9 y ordena alfabéticamente cada grupo', () {
      const centros = [
        CentroCostoRef(
          centroId: '3',
          empresaId: 'e',
          codigo: '',
          nombre: 'Tunja',
          grupo: 'G9',
        ),
        CentroCostoRef(
          centroId: '2',
          empresaId: 'e',
          codigo: '',
          nombre: 'Bordo',
          grupo: 'G1',
        ),
        CentroCostoRef(
          centroId: '1',
          empresaId: 'e',
          codigo: '',
          nombre: 'Buen Pastor',
          grupo: 'G1',
        ),
        CentroCostoRef(
          centroId: '4',
          empresaId: 'e',
          codigo: '',
          nombre: 'Ipiales',
          grupo: 'G9',
        ),
      ];

      final grupos = agruparCentrosCosto(centros);

      expect(grupos.map((grupo) => grupo.grupo), ['G1', 'G9']);
      expect(grupos.first.centros.map((centro) => centro.nombre), [
        'Bordo',
        'Buen Pastor',
      ]);
      expect(grupos.last.centros.map((centro) => centro.nombre), [
        'Ipiales',
        'Tunja',
      ]);
    });
  });

  group('acta PDF obligatoria', () {
    test('acepta un PDF o imágenes que serán convertidas a PDF', () {
      expect(puedeGenerarActaPdf(['application/pdf']), isTrue);
      expect(puedeGenerarActaPdf(['image/jpeg']), isTrue);
      expect(puedeGenerarActaPdf(['text/plain']), isFalse);
      expect(puedeGenerarActaPdf(const []), isFalse);
    });

    test('la visita persistida debe contener un adjunto PDF', () {
      final pdf = InterventoriaAdjunto(
        url: 'https://example.test/acta.pdf',
        nombre: 'acta.pdf',
        path: 'acta.pdf',
        contentType: 'application/pdf',
        origen: 'web',
        fechaSubida: Timestamp.fromDate(DateTime(2026, 9, 2)),
      );

      expect(contieneActaPdf([pdf]), isTrue);
      expect(contieneActaPdf(const []), isFalse);
    });
  });

  group('calcularPorcentajeGeneral', () {
    test('ignora categorias no evaluadas', () {
      final items = defaultInterventoriaItems();
      final keys = kInterventoriaCategorias.map((c) => c.key).toList();

      items[keys[0]] = items[keys[0]]!.copyWith(valor: 100);
      items[keys[1]] = items[keys[1]]!.copyWith(valor: 80);
      items[keys[2]] = items[keys[2]]!.copyWith(
        noEvaluado: true,
        clearValor: true,
      );

      expect(calcularPorcentajeGeneral(items), 90);
    });

    test('retorna cero cuando no hay categorias evaluadas', () {
      final items = defaultInterventoriaItems().map(
        (key, value) =>
            MapEntry(key, value.copyWith(noEvaluado: true, clearValor: true)),
      );

      expect(calcularPorcentajeGeneral(items), 0);
    });
  });

  group('comparativo de última acta por establecimiento', () {
    test('conserva solo la visita más reciente de cada establecimiento', () {
      final rows = compararUltimaActaPorEstablecimiento([
        _visita(
          id: 'a-vieja',
          centroId: 'a',
          centroNombre: 'Alfa',
          fecha: DateTime(2026, 8, 1),
          total: 75,
        ),
        _visita(
          id: 'b',
          centroId: 'b',
          centroNombre: 'Beta',
          fecha: DateTime(2026, 8, 3),
          total: 82,
        ),
        _visita(
          id: 'a-nueva',
          centroId: 'a',
          centroNombre: 'Alfa',
          fecha: DateTime(2026, 8, 5),
          total: 91,
        ),
      ]);

      expect(rows, hasLength(2));
      expect(rows.map((row) => row.centroCostoNombre), ['Alfa', 'Beta']);
      expect(rows.first.visitaId, 'a-nueva');
      expect(rows.first.valor, 91);
    });

    test('no sustituye una categoría sin dato por una visita anterior', () {
      final categoriaKey = kInterventoriaCategorias.first.key;
      final rows = compararUltimaActaPorEstablecimiento([
        _visita(
          id: 'anterior',
          centroId: 'a',
          centroNombre: 'Alfa',
          fecha: DateTime(2026, 8, 1),
          total: 75,
          categoria: 88,
        ),
        _visita(
          id: 'ultima',
          centroId: 'a',
          centroNombre: 'Alfa',
          fecha: DateTime(2026, 8, 5),
          total: 91,
          categoriaNoEvaluada: true,
        ),
      ], categoriaKey: categoriaKey);

      expect(rows.single.visitaId, 'ultima');
      expect(rows.single.valor, isNull);
    });
  });
}
