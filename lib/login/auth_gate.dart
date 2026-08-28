// lib/login/auth_gate.dart
//
// Pantalla de arranque de la app. Reemplaza a LoginScreen como `home:`.
// Decide entre:
//   - Mostrar el LoginScreen (no hay sesión guardada o no se puede reanudar).
//   - Reanudar la sesión directo (opción "Mantener sesión iniciada").
//   - Pedir biometría y luego reanudar (huella / Face ID, solo móvil).
//
// Al reanudar SIEMPRE revalida contra Firestore: que el usuario exista, que su
// `estado` siga 'activo', que la empresa siga siendo válida y si tiene cambio
// de clave pendiente. Así la lógica de permisos/empresa queda intacta y no se
// confía ciegamente en lo guardado en el dispositivo.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/auth_prefs.dart';
import '../services/session_audit_service.dart';
import '../state/empresa_scope.dart';
import '../theme/app_typography.dart';
import '../home/home_screen.dart';
import 'login_screen.dart';
import 'change_password_screen.dart' hide kArial;

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _needsBiometric = false;
  bool _authInProgress = false;
  String? _error;
  SavedSession? _session;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _decide());
  }

  Future<void> _decide() async {
    final prefs = AuthPrefs.instance;
    final session = await prefs.getSession();
    if (session == null || !await prefs.canAutoResume()) {
      await _goLogin();
      return;
    }
    _session = session;

    if (await prefs.isBiometricEnabled()) {
      if (!mounted) return;
      setState(() => _needsBiometric = true);
      _runBiometric();
    } else {
      // "Mantener sesión iniciada" sin biometría -> entra directo.
      await _resume();
    }
  }

  Future<void> _goLogin({bool cerrarSesionFirebase = true}) async {
    // Cuando la causa es transitoria (aún no se restauró la sesión, no hay
    // red) NO se cierra la sesión de Firebase: hacerlo destruiría una sesión
    // válida y el próximo arranque tampoco podría reanudar.
    if (cerrarSesionFirebase) {
      try {
        await FirebaseAuth.instance.signOut();
      } catch (_) {}
    }
    if (!mounted) return;
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  /// Espera a que Firebase Auth termine de restaurar la sesión persistida.
  ///
  /// `currentUser` es null durante los primeros milisegundos del arranque
  /// (en web hasta que lee IndexedDB). Preguntar de una sola vez hacía que
  /// "mantener sesión iniciada" mandara al login **y borrara la sesión
  /// guardada**, así que la opción parecía apagarse sola.
  Future<User?> _esperarUsuarioAuth() async {
    final actual = FirebaseAuth.instance.currentUser;
    if (actual != null) return actual;
    try {
      return await FirebaseAuth.instance
          .authStateChanges()
          .firstWhere((user) => user != null)
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      return FirebaseAuth.instance.currentUser;
    }
  }

  Future<void> _runBiometric() async {
    if (_authInProgress) return;
    setState(() {
      _authInProgress = true;
      _error = null;
    });
    final ok = await AuthPrefs.instance.authenticateBiometric();
    if (!mounted) return;
    setState(() => _authInProgress = false);
    if (ok) {
      await _resume();
    } else {
      setState(
        () => _error =
            'No se pudo verificar tu identidad. Intenta de nuevo o usa tu contraseña.',
      );
    }
  }

  /// Revalida la sesión contra Firestore y navega a Home (o cambio de clave).
  Future<void> _resume() async {
    final session = _session;
    if (session == null) {
      await _goLogin();
      return;
    }
    try {
      final authUser = await _esperarUsuarioAuth();
      if (authUser == null) {
        // Puede ser que la sesión de Firebase sí caducara, pero también que
        // el dispositivo esté sin red al arrancar. La sesión guardada se
        // conserva para reintentar en el próximo arranque.
        await _goLogin(cerrarSesionFirebase: false);
        return;
      }
      final token = await authUser.getIdTokenResult(true);
      if (token.claims?['authVersion'] != 2 ||
          token.claims?['userDocId'] != session.docId) {
        await FirebaseAuth.instance.signOut();
        await AuthPrefs.instance.clearSession();
        await _goLogin();
        return;
      }
      final snap = await FirebaseFirestore.instance
          .collection('TBL_USUARIOS')
          .doc(session.docId)
          .get();
      final data = snap.data();

      // Usuario inexistente -> sesión inválida, limpiar.
      if (!snap.exists || data == null) {
        await AuthPrefs.instance.clearSession();
        await _goLogin();
        return;
      }

      // Usuario deshabilitado (estado distinto de 'activo' si está definido).
      final estado = (data['estado'] ?? '').toString().trim().toLowerCase();
      if (estado.isNotEmpty && estado != 'activo') {
        await AuthPrefs.instance.clearSession();
        await _goLogin();
        return;
      }

      if (!mounted) return;
      final empresaState = EmpresaScope.of(context, listen: false);
      final resolved = await empresaState.reconcileForUserData(
        data,
        preferredEmpresaId: session.empresaId,
      );
      if (resolved == null || resolved.isEmpty) {
        await AuthPrefs.instance.clearSession();
        await _goLogin();
        return;
      }

      // Mantener la sesión sincronizada con la empresa válida resuelta.
      await AuthPrefs.instance.saveSession(
        docId: session.docId,
        empresaId: resolved,
      );
      unawaited(
        SessionAuditService()
            .recordLogin(
              userId: session.docId,
              empresaId: resolved,
              userData: data,
              source: _needsBiometric ? 'biometria' : 'sesion_guardada',
            )
            .catchError((e) => debugPrint('[AuthGate] audit error: $e')),
      );

      final needsChange = data['needsPasswordChange'] as bool? ?? false;
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => needsChange
              ? ChangePasswordScreen(
                  usuario: session.docId,
                  empresaId: resolved,
                )
              : HomeScreen(username: session.docId, empresaId: resolved),
        ),
      );
    } catch (e) {
      // Error transitorio (p. ej. sin red): NO borramos la sesión ni cerramos
      // la de Firebase; dejamos que el usuario inicie sesión manualmente y
      // reintente en otro arranque.
      debugPrint('[AuthGate] _resume error: $e');
      await _goLogin(cerrarSesionFirebase: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 90,
                  child: Image.asset('assets/logo.png', fit: BoxFit.contain),
                ),
                const SizedBox(height: 28),
                if (!_needsBiometric) ...[
                  const CircularProgressIndicator(),
                ] else ...[
                  Icon(Icons.fingerprint, size: 56, color: scheme.primary),
                  const SizedBox(height: 12),
                  Text(
                    'Ingreso con huella / Face ID',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: kArial,
                      fontWeight: FontWeight.w700,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_error != null) ...[
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontFamily: kArial, color: scheme.error),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_authInProgress)
                    const CircularProgressIndicator()
                  else
                    FilledButton.icon(
                      onPressed: _runBiometric,
                      icon: const Icon(Icons.fingerprint),
                      label: const Text(
                        'Verificar identidad',
                        style: TextStyle(fontFamily: kArial),
                      ),
                    ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _goLogin,
                    child: const Text(
                      'Usar contraseña',
                      style: TextStyle(fontFamily: kArial),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
