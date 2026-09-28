// lib/login/vigilante_acceso.dart
//
// Saca de la app, en el momento, a quien inhabiliten mientras la tiene
// abierta. La regla es la misma del inicio de sesión (`motivoAccesoBloqueado`
// en utils/user_company.dart; en el servidor, functions/src/acceso.ts): un
// inhabilitado no entra hasta que lo habiliten otra vez.
//
// Si solo lo inhabilitan en la empresa que está usando y sigue habilitado en
// otra, no se le cierra la sesión: pasa a la otra y se le avisa.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/auth_prefs.dart';
import '../state/empresa_scope.dart';
import '../utils/user_company.dart';
import 'login_screen.dart';

class VigilanteAcceso {
  VigilanteAcceso._();

  /// Empieza a vigilar la ficha de [userDocId]. Cancela lo que devuelve en
  /// el `dispose` de la pantalla que lo inicia.
  static StreamSubscription<DocumentSnapshot<Map<String, dynamic>>> iniciar(
    BuildContext context,
    String userDocId, {
    FirebaseFirestore? db,
  }) {
    var saliendo = false;
    return (db ?? FirebaseFirestore.instance)
        .collection('TBL_USUARIOS')
        .doc(userDocId)
        .snapshots()
        .listen(
          (snap) async {
            final data = snap.data();
            if (data == null || saliendo || !context.mounted) return;
            final motivo = motivoAccesoBloqueado(data);
            if (motivo != null) {
              saliendo = true;
              await cerrarSesion(context, aviso: motivo);
              return;
            }
            final scope = EmpresaScope.of(context, listen: false);
            final actual = scope.selectedEmpresaId;
            if (actual == null ||
                empresasSeleccionables(data).contains(actual)) {
              return;
            }
            final nueva = await scope.reconcileForUserData(data);
            if (!context.mounted || nueva == null) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Ya no estás habilitado en la empresa que tenías abierta. '
                  'Pasaste a una en la que sí lo estás.',
                ),
              ),
            );
          },
          // Sin red o con la sesión ya revocada: el próximo arranque vuelve a
          // validar contra el servidor.
          onError: (_) {},
        );
  }

  /// Cierra la sesión y vuelve al inicio con [aviso] visible.
  static Future<void> cerrarSesion(
    BuildContext context, {
    String? aviso,
  }) async {
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
    try {
      await AuthPrefs.instance.clearSession();
    } catch (_) {}
    if (!context.mounted) return;
    try {
      EmpresaScope.of(context, listen: false).clear();
    } catch (_) {}
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => LoginScreen(aviso: aviso)),
      (_) => false,
    );
  }
}
