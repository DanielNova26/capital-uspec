import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo/state/empresa_scope.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'selected_empresa_id': 'A'});
  });

  test(
    'la sesión persistida cambia de la empresa retirada a la vigente',
    () async {
      final state = EmpresaState();
      addTearDown(state.dispose);
      await state.hydrate();
      expect(state.selectedEmpresaId, 'A');
      final resolved = await state.reconcileForUserData({
        'empresas': ['A', 'B'],
        'empresasDetalle': {
          'A': {'estadoLaboral': 'inactivo'},
          'B': {'estadoLaboral': 'activo'},
        },
      }, preferredEmpresaId: 'A');
      expect(resolved, 'B');
      expect(state.selectedEmpresaId, 'B');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('selected_empresa_id'), 'B');
    },
  );

  test('una cuenta bloqueada borra la empresa persistida', () async {
    final state = EmpresaState();
    addTearDown(state.dispose);
    await state.hydrate();
    final resolved = await state.reconcileForUserData(
      {
        'estado': 'inactivo',
        'empresas': ['A'],
        'empresasDetalle': {
          'A': {'estadoLaboral': 'activo'},
        },
      },
      preferredEmpresaId: 'A',
      eleccionExplicita: true,
    );
    expect(resolved, isNull);
    expect(state.selectedEmpresaId, isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('selected_empresa_id'), isFalse);
  });
}
