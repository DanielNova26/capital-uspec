import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../core/access_guard.dart';
import '../utils/user_company.dart';
import 'visitas_dashboard_screen.dart';
import 'visitas_models.dart';
import 'visitas_service.dart';

/// Las notificaciones de Visitas llevan `visita:<id>`, no un id de TBL_TAREAS.
Future<bool> abrirVisitasDesdeNotificacion(
  BuildContext context, {
  required String userId,
  String? empresaId,
}) async {
  final eid = (empresaId ?? '').trim();
  if (eid.isEmpty) {
    _avisar(context, 'No se encontró la empresa para abrir Visitas.');
    return false;
  }
  try {
    final user = await FirebaseFirestore.instance
        .collection('TBL_USUARIOS')
        .doc(userId)
        .get();
    final userData = user.data();
    if (userData == null) {
      _avisar(context, 'No se encontró tu usuario para abrir Visitas.');
      return false;
    }
    final access = await AccessGuard().canAccess(
      userData: userData,
      empresaId: eid,
      appId: kVisitasAppId,
    );
    if (!access.allowed) {
      _avisar(context, 'Sin acceso a Visitas en esta empresa.');
      return false;
    }
    var rol = await VisitasService().getRolUsuario(eid, userId);
    if (rol == null && isDeveloperUser(userData, empresaId: eid)) {
      rol = kVisitasRolJefe;
    }
    if (rol == null) {
      _avisar(context, 'No tienes un rol asignado en Visitas.');
      return false;
    }
    final nombre = resolveScopedStringWithFallbacks(
      userData,
      eid,
      const ['nombre', 'nombreCompleto'],
      const ['nombre', 'nombreCompleto', 'name'],
    );
    if (!context.mounted) return false;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VisitasDashboardScreen(
          userId: userId,
          empresaId: eid,
          rol: rol,
          nombreUsuario: nombre.isEmpty ? userId : nombre,
          esDesarrollador: isDeveloperUser(userData, empresaId: eid),
        ),
      ),
    );
    return true;
  } catch (_) {
    _avisar(context, 'No se pudo abrir el módulo de Visitas.');
    return false;
  }
}

void _avisar(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.maybeOf(
    context,
  )?.showSnackBar(SnackBar(content: Text(message)));
}
