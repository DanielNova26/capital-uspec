import 'package:flutter_test/flutter_test.dart';
import 'package:todo/gestion_documental/planillas/pp_role_access.dart';
import 'package:todo/gestion_documental/planillas/pp_models.dart';
import 'package:todo/gestion_documental/planillas/pp_cuentas_models.dart';
import 'package:todo/utils/user_company.dart';

Map<String, dynamic> person() => {
  'empresaId': 'A',
  'empresas': ['A', 'B'],
  'appsPorEmpresa': true,
  'role': 'usuario',
  'rolPlanillas': 'admin_doc',
  'empresasDetalle': <String, dynamic>{
    'A': <String, dynamic>{
      'activo': true,
      'apps': ['planillaspagodashboard'],
    },
    'B': <String, dynamic>{'activo': true, 'apps': <String>[]},
  },
};

void main() {
  test('nivel raíz solo sirve en la empresa principal', () {
    final user = person();
    expect(resolvePpPlanillasRole(user, 'A'), 'admin_doc');
    expect(resolvePpPlanillasRole(user, 'B'), isNull);
    expect(ppCanAccess(user, 'B'), isFalse);
    expect(userHasApp(user, 'planillaspagodashboard', empresaId: 'B'), isFalse);
    user['empresasDetalle']['B']['rolPlanillas'] = 'auditoria';
    expect(resolvePpPlanillasRole(user, 'B'), 'auditoria');
    expect(
      ppCanAccess(user, 'B'),
      isTrue,
    ); // Compatibilidad de roles históricos.
  });
  test('vacío y desconocido no recuperan el administrador raíz', () {
    final user = person();
    for (final value in [
      '',
      null,
      'inventado',
      'talento_humano',
      'desarrollador',
    ]) {
      user['empresasDetalle']['A']['rolPlanillas'] = value;
      expect(resolvePpPlanillasRole(user, 'A'), isNull);
      expect(ppCanAccess(user, 'A'), isFalse);
    }
  });
  test('membresía y persona inactivas retiran acceso', () {
    final user = person();
    user['empresasDetalle']['A']['activo'] = false;
    expect(ppCanAccess(user, 'A'), isFalse);
    user['empresasDetalle']['A']['activo'] = true;
    user['empresasDetalle']['A']['estadoLaboral'] = 'inactivo';
    expect(ppCanAccess(user, 'A'), isFalse);
  });
  test('avisos de etapa respetan nivel efectivo y revocación scoped', () {
    final user = person();
    user['empresasDetalle']['A']['rolPlanillas'] = 'auditoria';
    expect(ppIsNotificationRecipient(user, 'A', 'admin_doc'), isFalse);
    expect(ppIsNotificationRecipient(user, 'A', 'auditoria'), isTrue);
    user['empresasDetalle']['A']['rolPlanillas'] = '';
    expect(ppIsNotificationRecipient(user, 'A', 'admin_doc'), isFalse);
    expect(ppIsNotificationRecipient(user, 'B', 'admin_doc'), isFalse);
  });
  test('niveles muestran acciones existentes y separan cuentas bancarias', () {
    expect(ppRoleLevelLabels.length, 4);
    expect(ppActionsForLevel('tesoreria'), contains('gestionar_beneficiarios'));
    expect(ppActionsForLevel('tesoreria'), isNot(contains('firmar')));
    expect(ppActionsForLevel('auditoria'), contains('aprobar_auditoria'));
    expect(ppActionsForLevel('auditoria'), isNot(contains('confirmar_carga')));
    expect(ppActionsForLevel('gerencia'), contains('firmar'));
    expect(ppActionsForLevel('gerencia'), isNot(contains('aprobar_auditoria')));
    expect(puedeVerNumeroCuenta('auditoria'), isFalse);
    expect(puedeEditarNumeroCuenta('gerencia'), isFalse);
    expect(puedeEditarBancoCuenta(kCuentaRolTalentoHumano), isTrue);
    expect(puedeVerNumeroCuenta(kCuentaRolTalentoHumano), isFalse);
    expect(ppLevelDescription(''), contains('Sin acceso'));
  });
  test(
    'desarrollador general conserva la excepción real de eliminar logos',
    () {
      final user = person();
      user['role'] = 'desarrollador';
      expect(resolvePpPlanillasRole(user, 'A'), PpRoles.desarrollador);
      expect(
        PpRoles.puedeEjecutar('eliminar_logo', PpRoles.desarrollador),
        isFalse,
      );
    },
  );
}
