import 'package:flutter/material.dart';

import '../gestion_documental/gd_dashboard_screen.dart';

/// Entrada independiente a la Biblioteca Documental.
class LibraryManagementScreen extends StatelessWidget {
  final String currentUserId;
  final String empresaId;

  const LibraryManagementScreen({
    super.key,
    required this.currentUserId,
    required this.empresaId,
  });

  @override
  Widget build(BuildContext context) {
    return GdDashboardScreen(userId: currentUserId, empresaId: empresaId);
  }
}
