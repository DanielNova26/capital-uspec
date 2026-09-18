import 'package:flutter_test/flutter_test.dart';
import 'package:todo/core/area_directory.dart';
import 'package:todo/interventoria/interventoria_service.dart';

/// Director del área para el informe de Gerencia: la persona de mayor cargo
/// dentro del área, comparando el área por el catálogo y no por igualdad de
/// id (la misma área vive con varios ids).
void main() {
  const coordinadora = InterventoriaUsuario(
    id: '1001',
    nombre: 'Laura Coordinadora',
    cargo: 'Coordinador de mantenimiento',
    centroId: 'sede',
    areaId: 'EMPRESA_001_mantenimiento',
  );
  const director = InterventoriaUsuario(
    id: '1002',
    nombre: 'Pedro Director',
    cargo: 'Director de operaciones',
    centroId: 'sede',
    // Mismo área, otro id: como aparece en los usuarios importados.
    areaId: 'Mantenimiento',
  );
  const otraArea = InterventoriaUsuario(
    id: '1003',
    nombre: 'Ana Otra',
    cargo: 'Director financiero',
    centroId: 'sede',
    areaId: 'EMPRESA_001_financiera',
  );

  final catalogo = AreaCatalogo.desde(const [
    (id: 'EMPRESA_001_mantenimiento', nombre: 'Mantenimiento'),
    (id: 'Mantenimiento', nombre: 'Mantenimiento'),
    (id: 'EMPRESA_001_financiera', nombre: 'Financiera'),
  ], empresaId: 'EMPRESA_001');

  test('la jerarquía pone al director por encima del coordinador', () {
    expect(
      nivelJerarquiaCargo('Director de operaciones'),
      lessThan(nivelJerarquiaCargo('Coordinador de mantenimiento')),
    );
    expect(nivelJerarquiaCargo('Auxiliar'), 99);
  });

  test('elige al de mayor cargo aunque su área venga con otro id', () {
    final opcion = catalogo.opciones.firstWhere(
      (o) => o.contiene('EMPRESA_001_mantenimiento'),
    );
    final elegido = resolverDirectorDeArea(const [
      coordinadora,
      director,
      otraArea,
    ], esDelArea: (u) => opcion.contiene(u.areaId));
    expect(elegido?.id, director.id);
  });

  test(
    'con una sola persona en el área, esa responde sea cual sea su cargo',
    () {
      final elegido = resolverDirectorDeArea(
        const [coordinadora, otraArea],
        esDelArea: (u) =>
            areaClave(u.areaId) == areaClave('EMPRESA_001_mantenimiento'),
      );
      expect(elegido?.id, coordinadora.id);
    },
  );

  test('sin nadie del área no inventa a alguien de otra', () {
    final elegido = resolverDirectorDeArea(const [
      otraArea,
    ], esDelArea: (u) => u.areaId == 'EMPRESA_001_mantenimiento');
    expect(elegido, isNull);
  });
}
