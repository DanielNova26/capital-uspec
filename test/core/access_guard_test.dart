import 'package:flutter_test/flutter_test.dart';
import 'package:todo/core/access_guard.dart';
import 'package:todo/data/firestore_user_repository.dart';

class _Repository extends Fake implements FirestoreUserRepository {
  int moduleReads = 0;

  @override
  Future<EmpresaAppModule?> getEmpresaAppModule({
    required String empresaId,
    required String appId,
  }) async {
    moduleReads++;
    return null;
  }
}

void main() {
  Map<String, dynamic> usuario() => {
    'estado': 'activo',
    'empresas': ['A', 'B'],
    'apps': ['tareasdashboard'],
    'empresasDetalle': {
      'A': {'estadoLaboral': 'inactivo'},
      'B': {'estadoLaboral': 'activo'},
    },
  };

  test(
    'el acceso directo rechaza la empresa retirada y permite la vigente',
    () async {
      final repo = _Repository();
      final guard = AccessGuard(repo: repo);
      final retirada = await guard.canAccess(
        userData: usuario(),
        empresaId: 'A',
        appId: 'tareasdashboard',
      );
      expect(retirada.allowed, isFalse);
      expect(retirada.reason, AccessDenialReason.userDisabled);
      expect(repo.moduleReads, 0);
      final vigente = await guard.canAccess(
        userData: usuario(),
        empresaId: 'B',
        appId: 'tareasdashboard',
      );
      expect(vigente.allowed, isTrue);
      expect(repo.moduleReads, 1);
    },
  );

  test('el rol de desarrollador no reactiva una cuenta bloqueada', () async {
    final repo = _Repository();
    final guard = AccessGuard(repo: repo);
    for (final bloqueo in [
      {'estado': 'inactivo'},
      {'activo': false},
      {
        'empresasDetalle': {
          'B': {'activo': false},
        },
      },
    ]) {
      final decision = await guard.canAccess(
        userData: {...usuario(), 'role': 'desarrollador', ...bloqueo},
        empresaId: 'B',
        appId: 'tareasdashboard',
      );
      expect(decision.allowed, isFalse);
      expect(decision.reason, AccessDenialReason.userDisabled);
    }
    expect(repo.moduleReads, 0);
  });

  test('un desarrollador habilitado conserva su acceso', () async {
    final decision = await AccessGuard(repo: _Repository()).canAccess(
      userData: {'estado': 'activo', 'role': 'desarrollador'},
      empresaId: 'B',
      appId: 'tareasdashboard',
    );
    expect(decision.allowed, isTrue);
    expect(decision.isDeveloperOverride, isTrue);
  });
}
