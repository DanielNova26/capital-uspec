// lib/home/document_management_screen.dart

import 'package:flutter/material.dart';
import '../core/guarded_module_page.dart';
import '../gestion_documental/correspondencia/gd_control_dashboard_screen.dart';

/// Entrada independiente al control de Gestión de Correspondencia.
class DocumentManagementScreen extends StatelessWidget {
  final String currentUserId;
  final String empresaId;

  const DocumentManagementScreen({
    super.key,
    required this.currentUserId,
    required this.empresaId,
  });

  @override
  Widget build(BuildContext context) {
    return GuardedModulePage(
      userIdentity: currentUserId,
      appId: 'gestiondocumentaldashboard',
      pageTitle: 'Gestión de Correspondencia',
      fallbackEmpresaId: empresaId,
      child: GdControlDashboardScreen(
        userId: currentUserId,
        empresaId: empresaId,
      ),
    );
  }
}
