// lib/home/team_screen.dart
//
// Wrapper para reutilizar la misma lógica/estilo de TeamOverviewScreen.
// Mantiene compatibilidad con llamadas antiguas (userId) y nuevas (currentUserId).

import 'package:flutter/material.dart';
import 'team_overview_screen.dart';

class TeamScreen extends StatelessWidget {
  /// ID del usuario actual. Usamos el mismo nombre que TeamOverviewScreen.
  final String currentUserId;

  const TeamScreen({
    Key? key,
    String? userId,         // compat: llamadas antiguas
    String? currentUserId,  // nombre unificado (recomendado)
  })  : currentUserId = currentUserId ?? userId ?? '',
        assert(
        (currentUserId != null && currentUserId != '') ||
            (userId != null && userId != ''),
        'Debes pasar "currentUserId" o "userId" con un valor no vacío.',
        ),
        super(key: key);

  @override
  Widget build(BuildContext context) {
    // Reutilizamos toda la pantalla avanzada.
    return TeamOverviewScreen(currentUserId: currentUserId);
  }
}
