import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SecureAuthException implements Exception {
  final String code;
  final String message;
  const SecureAuthException(this.code, this.message);

  @override
  String toString() => message;
}

class SecureLoginResult {
  final String userDocId;
  final String uid;
  final bool needsPasswordChange;

  const SecureLoginResult({
    required this.userDocId,
    required this.uid,
    required this.needsPasswordChange,
  });
}

class RecoveryChallenge {
  final String id;
  final String question1;
  final String question2;

  const RecoveryChallenge({
    required this.id,
    required this.question1,
    required this.question2,
  });
}

/// Puerta única para el acceso privado de To-Do.
///
/// Ninguna contraseña ni respuesta de seguridad se consulta en Firestore desde
/// el dispositivo. Las operaciones se validan en Cloud Functions y el cliente
/// recibe una sesión Firebase individual mediante custom token.
class SecureAuthService {
  SecureAuthService({FirebaseFunctions? functions, FirebaseAuth? auth})
    : _functions =
          functions ?? FirebaseFunctions.instanceFor(region: 'us-central1'),
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFunctions _functions;
  final FirebaseAuth _auth;

  Future<SecureLoginResult> signIn({
    required String usuario,
    required String password,
  }) async {
    try {
      final response = await _functions.httpsCallable('authIniciarSesion').call(
        {'usuario': usuario.trim(), 'password': password},
      );
      final data = Map<String, dynamic>.from(response.data as Map);
      final token = (data['token'] ?? '').toString();
      final userDocId = (data['userDocId'] ?? '').toString();
      if (token.isEmpty || userDocId.isEmpty) {
        throw const SecureAuthException(
          'invalid-response',
          'El servicio de acceso devolvió una respuesta incompleta.',
        );
      }
      final credential = await _auth.signInWithCustomToken(token);
      final uid = credential.user?.uid ?? '';
      if (uid.isEmpty) {
        throw const SecureAuthException(
          'invalid-session',
          'No fue posible establecer la sesión segura.',
        );
      }
      return SecureLoginResult(
        userDocId: userDocId,
        uid: uid,
        needsPasswordChange: data['needsPasswordChange'] == true,
      );
    } on FirebaseFunctionsException catch (error) {
      throw SecureAuthException(
        error.code,
        error.message ?? 'No fue posible validar el acceso.',
      );
    } on FirebaseAuthException catch (error) {
      throw SecureAuthException(
        error.code,
        error.message ?? 'No fue posible establecer la sesión segura.',
      );
    }
  }

  Future<void> changePassword({
    required String newPassword,
    required String question1,
    required String answer1,
    required String question2,
    required String answer2,
  }) async {
    try {
      await _functions.httpsCallable('authCambiarClave').call({
        'newPassword': newPassword,
        'question1': question1,
        'answer1': answer1,
        'question2': question2,
        'answer2': answer2,
      });
    } on FirebaseFunctionsException catch (error) {
      throw SecureAuthException(
        error.code,
        error.message ?? 'No fue posible cambiar la contraseña.',
      );
    }
  }

  Future<RecoveryChallenge> prepareRecovery(String usuario) async {
    try {
      final response = await _functions
          .httpsCallable('authPrepararRecuperacion')
          .call({'usuario': usuario.trim()});
      final data = Map<String, dynamic>.from(response.data as Map);
      return RecoveryChallenge(
        id: (data['challengeId'] ?? '').toString(),
        question1: (data['question1'] ?? '').toString(),
        question2: (data['question2'] ?? '').toString(),
      );
    } on FirebaseFunctionsException catch (error) {
      throw SecureAuthException(
        error.code,
        error.message ?? 'No fue posible iniciar la recuperación.',
      );
    }
  }

  Future<void> completeRecovery({
    required String challengeId,
    required String answer1,
    required String answer2,
    required String newPassword,
  }) async {
    try {
      await _functions.httpsCallable('authCompletarRecuperacion').call({
        'challengeId': challengeId,
        'answer1': answer1,
        'answer2': answer2,
        'newPassword': newPassword,
      });
    } on FirebaseFunctionsException catch (error) {
      throw SecureAuthException(
        error.code,
        error.message ?? 'No fue posible restablecer la contraseña.',
      );
    }
  }
}
