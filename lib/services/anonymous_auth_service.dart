import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';

/// Garantiza la sesión técnica de Firebase que usa la aplicación.
///
/// La identidad funcional sigue siendo la cédula/documento de TBL_USUARIOS.
/// Firebase Anonymous Auth únicamente habilita el acceso protegido por reglas
/// antes de que el usuario complete el formulario de ingreso.
class AnonymousAuthService {
  AnonymousAuthService._();

  static Future<void>? _pendingSignIn;

  static Future<void> ensureSession() async {
    if (FirebaseAuth.instance.currentUser != null) return;

    final pending = _pendingSignIn;
    if (pending != null) {
      await pending;
      return;
    }

    final signIn = FirebaseAuth.instance.signInAnonymously().then<void>((_) {});
    _pendingSignIn = signIn;
    try {
      await signIn;
    } finally {
      if (identical(_pendingSignIn, signIn)) {
        _pendingSignIn = null;
      }
    }
  }
}
