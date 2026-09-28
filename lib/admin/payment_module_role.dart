import '../gestion_documental/planillas/pp_role_access.dart';
import '../utils/user_company.dart';

const paymentRolesAppId = 'planillaspagodashboard';

class PaymentModuleRole {
  const PaymentModuleRole({
    required this.id,
    required this.empresaId,
    required this.name,
    required this.level,
    this.description = '',
    this.enabled = true,
    this.revision = 1,
  });
  final String id;
  final String empresaId;
  final String name;
  final String description;
  final String level;
  final bool enabled;
  final int revision;

  String get effectiveLevel => enabled ? level : '';

  static PaymentModuleRole? fromData(String id, Map<String, dynamic> data) {
    final level = data['baseRole'];
    if (data['type'] != 'module_role' ||
        !appIdsEquivalent(
          (data['moduleId'] ?? '').toString(),
          paymentRolesAppId,
        ) ||
        data['empresaId'] is! String ||
        (data['empresaId'] as String).trim().isEmpty ||
        data['nombre'] is! String ||
        (data['nombre'] as String).trim().isEmpty ||
        level is! String ||
        !ppRoleLevelLabels.containsKey(level) ||
        data['revision'] is! int ||
        (data['revision'] as int) < 1 ||
        data['enabled'] is! bool) {
      return null;
    }
    return PaymentModuleRole(
      id: id,
      empresaId: data['empresaId'] as String,
      name: data['nombre'] as String,
      description: (data['descripcion'] ?? '').toString(),
      level: level,
      enabled: data['enabled'] as bool,
      revision: data['revision'] as int,
    );
  }
}

String paymentRoleIdOf(Map<String, dynamic> user, String empresaId) =>
    (getUserCompanyDetail(user, empresaId)?['rolPlanillasId'] ?? '')
        .toString()
        .trim();

bool paymentRoleNeedsSync(Map<String, dynamic> user, PaymentModuleRole role) {
  final detail = getUserCompanyDetail(user, role.empresaId);
  return paymentRoleIdOf(user, role.empresaId) == role.id &&
      (detail?['rolPlanillasNombre'] != role.name ||
          detail?['rolPlanillasVersion'] != role.revision ||
          detail?['rolPlanillas'] != role.effectiveLevel ||
          (raizEsDeEmpresa(user, role.empresaId) &&
              user['rolPlanillas'] != role.effectiveLevel));
}
