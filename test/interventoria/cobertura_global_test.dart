import 'package:flutter_test/flutter_test.dart';
import 'package:todo/interventoria/interventoria_service.dart';

InterventoriaUsuario _u(
  String id,
  String cargo, {
  Set<String> cubre = const {},
  bool todas = false,
}) => InterventoriaUsuario(
  id: id,
  nombre: 'Persona $id',
  cargo: cargo,
  centroId: '',
  areaId: '',
  centrosAsignadosIds: cubre,
  cubreTodas: todas,
);

void main() {
  test('quien atiende todas las sedes cubre cualquier sede', () {
    final g = _u('1', 'Tesorero', todas: true);
    expect(g.cubreCentro('guateque'), isTrue);
    expect(g.cubreCentroEspecifico('guateque'), isFalse);
    expect(_u('2', 'Tesorero').cubreCentro('guateque'), isFalse);
  });

  test(
    'el titular de la sede va antes que el global, aunque el global sea el primero',
    () {
      final usuarios = [
        _u('1', 'Tesorero', todas: true),
        _u('2', 'Tesorero', cubre: {'guateque'}),
      ];
      final p = resolverCargoUnico('Tesorero', 'guateque', usuarios);
      expect(p?.id, '2');
      expect(p?.delCentro, isTrue);
    },
  );

  test('sin titular propio responde el global, y cuenta como de la sede', () {
    final usuarios = [
      _u('1', 'Tesorero', cubre: {'picota'}),
      _u('2', 'Tesorero', todas: true),
    ];
    final p = resolverCargoUnico('Tesorero', 'guateque', usuarios);
    expect(p?.id, '2');
    expect(p?.delCentro, isTrue);
  });

  test('sin global ni titular en la sede no se asigna dentro de la sede', () {
    final usuarios = [
      _u('1', 'Tesorero', cubre: {'picota'}),
    ];
    final p = resolverCargoUnico('Tesorero', 'guateque', usuarios);
    expect(p?.delCentro, isFalse);
  });

  test('un cargo distinto no se mezcla aunque la persona sea global', () {
    final usuarios = [_u('1', 'Abogado', todas: true)];
    expect(resolverCargoUnico('Tesorero', 'guateque', usuarios), isNull);
  });
}
