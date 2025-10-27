// lib/services/fcm_token_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FcmTokenService {
  static Future<void> saveCurrentToken({
    required String? token,
    String usersCollection = 'TBL_USUARIOS',
  }) async {
    if (token == null) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final userRef = FirebaseFirestore.instance.collection(usersCollection).doc(uid);
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(userRef);
      if (snap.exists) {
        final data = snap.data() as Map<String, dynamic>;
        final tokens = (data['fcmTokens'] as List?)?.cast<String>().toSet() ?? <String>{};
        tokens.add(token);
        tx.update(userRef, {'fcmTokens': tokens.toList(), 'updatedAt': FieldValue.serverTimestamp()});
      } else {
        tx.set(userRef, {
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'fcmTokens': [token],
        }, SetOptions(merge: true));
      }
    });
  }
}
