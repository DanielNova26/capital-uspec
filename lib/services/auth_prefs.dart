// lib/services/auth_prefs.dart
//
// Capa única de "conveniencias de inicio de sesión":
//   1. Recordar usuario        -> precarga el usuario/cédula en el login.
//   2. Mantener sesión iniciada -> entra directo al abrir la app (sin clave).
//   3. Huella / Face ID         -> biometría local (solo móvil) como llave de
//                                  entrada para reanudar la sesión.
//
// IMPORTANTE (seguridad): NUNCA se guarda la contraseña en el dispositivo.
// La "sesión" persistida es solo la identidad (docId + empresaId) que
// HomeScreen necesita. Al reanudar, AuthGate revalida contra Firestore
// (que el usuario exista, su estado y la empresa activa). La biometría es
// únicamente la llave LOCAL que destraba esa reanudación.
//
// Web vs Móvil:
//   - Biometría es solo móvil (local_auth usa Keystore/Keychain del dispositivo).
//   - En web, isBiometricEnabled()/canOfferBiometrics() devuelven false y solo
//     aplican "recordar usuario" y "mantener sesión".

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// Identidad mínima de una sesión guardada en el dispositivo.
class SavedSession {
  final String docId;
  final String empresaId;
  const SavedSession({required this.docId, required this.empresaId});
}

class AuthPrefs {
  AuthPrefs._();
  static final AuthPrefs instance = AuthPrefs._();

  // --- Claves SharedPreferences (datos NO sensibles) ---
  static const _kRememberUser = 'login_remember_user';
  static const _kSavedUsername = 'login_saved_username';
  static const _kKeepSession = 'login_keep_session';
  static const _kBiometricEnabled = 'login_biometric_enabled';

  // --- Claves SecureStorage (identidad de sesión, cifrada) ---
  static const _kSessDocId = 'session_doc_id';
  static const _kSessEmpresaId = 'session_empresa_id';

  final FlutterSecureStorage _secure = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  final LocalAuthentication _localAuth = LocalAuthentication();

  // ───────────────────────── Recordar usuario ─────────────────────────

  Future<bool> getRememberUser() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kRememberUser) ?? false;
  }

  /// Devuelve el usuario guardado solo si "recordar" está activo.
  Future<String?> getSavedUsername() async {
    final p = await SharedPreferences.getInstance();
    if (!(p.getBool(_kRememberUser) ?? false)) return null;
    final u = p.getString(_kSavedUsername)?.trim();
    return (u == null || u.isEmpty) ? null : u;
  }

  Future<void> setRememberUser(bool value, {String? username}) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kRememberUser, value);
    if (value && username != null && username.trim().isNotEmpty) {
      await p.setString(_kSavedUsername, username.trim());
    } else if (!value) {
      await p.remove(_kSavedUsername);
    }
  }

  // ──────────────────── Mantener sesión / biometría (flags) ────────────────────

  Future<bool> getKeepSession() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kKeepSession) ?? false;
  }

  Future<void> setKeepSession(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kKeepSession, value);
  }

  Future<bool> isBiometricEnabled() async {
    if (kIsWeb) return false;
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kBiometricEnabled) ?? false;
  }

  Future<void> setBiometricEnabled(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kBiometricEnabled, value);
  }

  // ──────────────────────────── Sesión (identidad) ────────────────────────────

  Future<void> saveSession({
    required String docId,
    required String empresaId,
  }) async {
    await _secure.write(key: _kSessDocId, value: docId.trim());
    await _secure.write(key: _kSessEmpresaId, value: empresaId.trim());
  }

  Future<SavedSession?> getSession() async {
    try {
      final docId = await _secure.read(key: _kSessDocId);
      final empresaId = await _secure.read(key: _kSessEmpresaId);
      if (docId == null || docId.trim().isEmpty) return null;
      if (empresaId == null || empresaId.trim().isEmpty) return null;
      return SavedSession(docId: docId.trim(), empresaId: empresaId.trim());
    } catch (e) {
      debugPrint('[AuthPrefs] getSession error: $e');
      return null;
    }
  }

  /// ¿Hay una sesión guardada Y algún mecanismo (mantener/biometría) que
  /// permita reanudarla automáticamente al abrir la app?
  Future<bool> canAutoResume() async {
    if (await getSession() == null) return false;
    return (await getKeepSession()) || (await isBiometricEnabled());
  }

  /// Borra la identidad de sesión y apaga el auto-ingreso.
  /// Conserva "recordar usuario" (comodidad inofensiva).
  Future<void> clearSession() async {
    try {
      await _secure.delete(key: _kSessDocId);
      await _secure.delete(key: _kSessEmpresaId);
    } catch (e) {
      debugPrint('[AuthPrefs] clearSession error: $e');
    }
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kKeepSession, false);
    await p.setBool(_kBiometricEnabled, false);
  }

  // ──────────────────────────── Biometría (móvil) ────────────────────────────

  /// ¿El dispositivo tiene biometría enrolada (huella/rostro) para ofrecer la
  /// opción de activarla? Solo móvil.
  Future<bool> canOfferBiometrics() async {
    if (kIsWeb) return false;
    try {
      final supported = await _localAuth.isDeviceSupported();
      if (!supported) return false;
      final canCheck = await _localAuth.canCheckBiometrics;
      if (!canCheck) return false;
      final available = await _localAuth.getAvailableBiometrics();
      return available.isNotEmpty;
    } catch (e) {
      debugPrint('[AuthPrefs] canOfferBiometrics error: $e');
      return false;
    }
  }

  /// Lanza el prompt biométrico. Devuelve true si autenticó correctamente.
  /// Permite respaldo con PIN/patrón del dispositivo (biometricOnly: false).
  Future<bool> authenticateBiometric({
    String reason = 'Confirma tu identidad para ingresar',
  }) async {
    if (kIsWeb) return false;
    try {
      return await _localAuth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
    } catch (e) {
      debugPrint('[AuthPrefs] authenticate error: $e');
      return false;
    }
  }
}
