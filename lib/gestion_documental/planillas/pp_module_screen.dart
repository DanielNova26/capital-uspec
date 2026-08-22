import 'package:flutter/material.dart';

import '../../core/guarded_module_page.dart';
import '../gd_firmas_screen.dart';
import 'pp_dashboard_screen.dart';

const kPlanillasPagoAppId = 'planillaspagodashboard';

class PlanillasPagoModuleScreen extends StatelessWidget {
  final String userId;
  final String empresaId;

  const PlanillasPagoModuleScreen({
    super.key,
    required this.userId,
    required this.empresaId,
  });

  @override
  Widget build(BuildContext context) => GuardedModulePage(
    userIdentity: userId,
    appId: kPlanillasPagoAppId,
    pageTitle: 'Planillas de Pago',
    fallbackEmpresaId: empresaId,
    child: PpDashboardScreen(
      userId: userId,
      empresaId: empresaId,
      onOpenIdentity: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => GdFirmasScreen(empresaId: empresaId, userId: userId),
        ),
      ),
    ),
  );
}
