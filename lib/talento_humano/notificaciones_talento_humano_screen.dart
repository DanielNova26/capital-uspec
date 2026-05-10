// lib/talento_humano/notificaciones_talento_humano_screen.dart

import 'package:flutter/material.dart';

import '../home/notifications_screen.dart';

/// Entrada historica del modulo TH, ahora delegada a la bandeja global.
class NotificacionesTalentoHumanoScreen extends StatelessWidget {
  final String userId;
  final String empresaId;

  const NotificacionesTalentoHumanoScreen({
    super.key,
    required this.userId,
    required this.empresaId,
  });

  @override
  Widget build(BuildContext context) {
    return NotificationsScreen(userId: userId, empresaId: empresaId);
  }
}
