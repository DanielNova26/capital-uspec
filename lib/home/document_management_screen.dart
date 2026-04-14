// lib/home/document_management_screen.dart

import 'package:flutter/material.dart';
import '../gestion_documental/gd_dashboard_screen.dart';

/// Puente hacia la implementación real del módulo de Gestión Documental.
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
    return GdDashboardScreen(
      userId: currentUserId,
      empresaId: empresaId,
    );
  }
}
