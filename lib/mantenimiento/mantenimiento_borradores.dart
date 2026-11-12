import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'mantenimiento_borrador_web.dart'
    if (dart.library.io) 'mantenimiento_borrador_io.dart'
    as storage;

class BorradorMantenimiento {
  BorradorMantenimiento(String empresaId, String formulario)
    : _scope = _clave(empresaId, formulario);

  final String? _scope;
  static final _cipher = AesGcm.with256bits();
  static const _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static Future<SecretKey>? _secret;
  static final _colas = <String, Future<void>>{};

  static String? _clave(String empresa, String formulario) {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;
      return sha256
          .convert(utf8.encode('${user.uid}|$empresa|$formulario'))
          .toString();
    } catch (_) {
      return null;
    }
  }

  static Future<SecretKey> _key() => _secret ??=
      () async {
        const nombre = 'mantenimiento_borradores_aes_v1';
        final stored = await _secure.read(key: nombre);
        if (stored != null) return SecretKey(base64Decode(stored));
        final key = await _cipher.newSecretKey();
        await _secure.write(
          key: nombre,
          value: base64Encode(await key.extractBytes()),
        );
        return key;
      }().onError((Object error, StackTrace stack) {
        _secret = null;
        Error.throwWithStackTrace(error, stack);
      });

  Future<Map<String, dynamic>?> leer() async {
    final scope = _scope;
    if (scope == null) return null;
    final json = await storage.leerBorrador(scope);
    if (json == null) return null;
    final envelope = jsonDecode(json) as Map<String, dynamic>;
    final box = SecretBox(
      base64Decode(envelope['bytes'] as String),
      nonce: base64Decode(envelope['nonce'] as String),
      mac: Mac(base64Decode(envelope['mac'] as String)),
    );
    final data = await _cipher.decrypt(
      box,
      secretKey: await _key(),
      aad: utf8.encode(scope),
    );
    return jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
  }

  Future<void> guardar(Map<String, dynamic>? data) {
    final scope = _scope;
    if (scope == null) return Future.value();
    final siguiente = (_colas[scope] ?? Future<void>.value()).then((_) async {
      if (data == null) return storage.escribirBorrador(scope, null);
      final box = await _cipher.encrypt(
        utf8.encode(jsonEncode(data)),
        secretKey: await _key(),
        aad: utf8.encode(scope),
      );
      await storage.escribirBorrador(
        scope,
        jsonEncode({
          'bytes': base64Encode(box.cipherText),
          'nonce': base64Encode(box.nonce),
          'mac': base64Encode(box.mac.bytes),
        }),
      );
    });
    final cola = siguiente.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _colas[scope] = cola;
    cola.then((_) {
      if (identical(_colas[scope], cola)) _colas.remove(scope);
    });
    return siguiente;
  }
}
