import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

dynamic visitasWire(dynamic value) {
  if (value is Timestamp) return {'\$ts': value.millisecondsSinceEpoch};
  if (value is Blob) return {'\$bytes': base64Encode(value.bytes)};
  if (value is Uint8List) return {'\$bytes': base64Encode(value)};
  if (value is Map) {
    return {
      for (final e in value.entries) e.key.toString(): visitasWire(e.value),
    };
  }
  if (value is List) return value.map(visitasWire).toList();
  return value;
}

dynamic visitasDecode(dynamic value) {
  if (value is Map) {
    if (value.length == 1 && value['\$ts'] is num) {
      return Timestamp.fromMillisecondsSinceEpoch(
        (value['\$ts'] as num).toInt(),
      );
    }
    if (value.length == 1 && value['\$bytes'] is String) {
      return Blob(base64Decode(value['\$bytes'] as String));
    }
    return {
      for (final e in value.entries) e.key.toString(): visitasDecode(e.value),
    };
  }
  if (value is List) return value.map(visitasDecode).toList();
  return value;
}

/// Explicit, bounded authorization to unlock downloaded work, separate from
/// Firebase's online session. Secure storage is never used to save passwords.
class VisitasAccesoLocal {
  final String userId, uid, empresaId;
  final int preparadaMs, venceMs, ultimaMs;
  const VisitasAccesoLocal({
    required this.userId,
    required this.uid,
    required this.empresaId,
    required this.preparadaMs,
    required this.venceMs,
    required this.ultimaMs,
  });
  bool vigente(DateTime now) {
    final ms = now.millisecondsSinceEpoch;
    return userId.isNotEmpty &&
        uid.isNotEmpty &&
        empresaId.isNotEmpty &&
        ms >= preparadaMs - 60000 &&
        ms >= ultimaMs - 60000 &&
        ms < venceMs;
  }

  Map<String, dynamic> toMap() => {
    'userId': userId,
    'uid': uid,
    'empresaId': empresaId,
    'preparadaMs': preparadaMs,
    'venceMs': venceMs,
    'ultimaMs': ultimaMs,
  };
  factory VisitasAccesoLocal.fromMap(Map<String, dynamic> d) =>
      VisitasAccesoLocal(
        userId: d['userId'] as String,
        uid: d['uid'] as String,
        empresaId: d['empresaId'] as String,
        preparadaMs: d['preparadaMs'] as int,
        venceMs: d['venceMs'] as int,
        ultimaMs: d['ultimaMs'] as int,
      );
}

/// Encrypted snapshots and photos. Serialized writes + atomic rename mean a
/// successful save survives process death, and failed writes leave the old copy.
class VisitasLocalStore extends ChangeNotifier {
  static final instance = VisitasLocalStore();
  static bool get disponible =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  static const grantKey = 'visitas_offline_access_v1';
  static const _keyName = 'visitas_offline_aes_v1';
  final FlutterSecureStorage secure;
  final Future<Directory> Function() directory;
  final _cipher = AesGcm.with256bits();
  Future<void> _tail = Future.value();
  Future<SecretKey>? _keyFuture;
  int _revisionAcceso = 0;
  int get revisionAcceso => _revisionAcceso;
  VisitasLocalStore({
    this.secure = const FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    ),
    Future<Directory> Function()? directory,
  }) : directory = directory ?? getApplicationSupportDirectory;

  Future<T> serialized<T>(Future<T> Function() operation) {
    final next = _tail.then((_) => operation());
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<SecretKey> _secret() => _keyFuture ??= _loadSecret();
  Future<SecretKey> _loadSecret() async {
    final stored = await secure.read(key: _keyName);
    if (stored != null) return SecretKey(base64Decode(stored));
    final key = await _cipher.newSecretKey();
    await secure.write(
      key: _keyName,
      value: base64Encode(await key.extractBytes()),
    );
    return key;
  }

  String _scope(String userId, String empresaId) =>
      sha256.convert(utf8.encode('$userId\u0000$empresaId')).toString();

  Future<Directory> _folder(String userId, String empresaId) async {
    final root = await directory();
    final dir = Directory(
      '${root.path}/visitas_offline/${_scope(userId, empresaId)}',
    );
    await dir.create(recursive: true);
    return dir;
  }

  Future<void> _write(File file, Uint8List bytes) async {
    final box = await _cipher.encrypt(bytes, secretKey: await _secret());
    // Keep the original encrypted bytes if a restored download is unreadable.
    if (await file.exists()) {
      try {
        await _read(file);
      } on SecretBoxAuthenticationError {
        await file.copy(
          '${file.path}.${DateTime.now().microsecondsSinceEpoch}.preservada',
        );
      } on FormatException {
        await file.copy(
          '${file.path}.${DateTime.now().microsecondsSinceEpoch}.preservada',
        );
      }
    }
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsBytes(box.concatenation(), flush: true);
    await tmp.rename(file.path);
  }

  Future<Uint8List> _read(File file) async {
    final bytes = await file.readAsBytes();
    if (bytes.length < 28) {
      throw const FormatException('La descarga cifrada está incompleta.');
    }
    final box = SecretBox.fromConcatenation(
      bytes,
      nonceLength: 12,
      macLength: 16,
    );
    return Uint8List.fromList(
      await _cipher.decrypt(box, secretKey: await _secret()),
    );
  }

  Future<VisitasAccesoLocal?> acceso() async {
    if (!disponible) return null;
    final raw = await secure.read(key: grantKey);
    if (raw == null) return null;
    return VisitasAccesoLocal.fromMap(
      Map<String, dynamic>.from(jsonDecode(raw) as Map),
    );
  }

  Future<void> autorizar(
    Map<String, dynamic> paquete, {
    int? revisionEsperada,
  }) => serialized(() async {
    if (revisionEsperada != null && revisionEsperada != _revisionAcceso) {
      throw StateError(
        'La sesión se cerró mientras se preparaba el acceso local.',
      );
    }
    final grant = VisitasAccesoLocal(
      userId: paquete['userId'],
      uid: paquete['uid'],
      empresaId: paquete['empresaId'],
      preparadaMs: paquete['preparadaMs'],
      venceMs: paquete['venceMs'],
      ultimaMs: DateTime.now().millisecondsSinceEpoch,
    );
    await secure.write(key: grantKey, value: jsonEncode(grant.toMap()));
  });

  Future<void> registrarDesbloqueo(VisitasAccesoLocal grant) =>
      serialized(() async {
        final current = await acceso();
        if (current == null ||
            current.userId != grant.userId ||
            current.uid != grant.uid ||
            current.empresaId != grant.empresaId ||
            current.preparadaMs != grant.preparadaMs ||
            current.venceMs != grant.venceMs) {
          throw StateError(
            'El acceso local cambió o se cerró. Vuelve a desbloquearlo.',
          );
        }
        await secure.write(
          key: grantKey,
          value: jsonEncode({
            ...grant.toMap(),
            'ultimaMs': DateTime.now().millisecondsSinceEpoch,
          }),
        );
      });

  Future<void> revocarAcceso() {
    _revisionAcceso++;
    return serialized(() => secure.delete(key: grantKey));
  }

  Future<List<Map<String, dynamic>>> listar(
    String userId,
    String empresaId, {
    bool tolerarIlegibles = false,
    void Function(int cantidad)? onIlegibles,
  }) async {
    await _tail;
    final dir = await _folder(userId, empresaId);
    final result = <Map<String, dynamic>>[];
    var ilegibles = 0;
    await for (final file in dir.list()) {
      if (file is! File || !file.path.endsWith('.visita')) continue;
      // Storage errors and account/company mismatches still stop the operation.
      Map<String, dynamic> data;
      try {
        data =
            visitasDecode(jsonDecode(utf8.decode(await _read(file))))
                as Map<String, dynamic>;
      } on SecretBoxAuthenticationError {
        if (!tolerarIlegibles) rethrow;
        ilegibles++;
        continue;
      } on FormatException {
        if (!tolerarIlegibles) rethrow;
        ilegibles++;
        continue;
      }
      if (data['userId'] != userId || data['empresaId'] != empresaId) {
        throw StateError('La descarga no corresponde a esta cuenta y empresa.');
      }
      result.add(data);
    }
    onIlegibles?.call(ilegibles);
    return result;
  }

  Future<void> guardar(Map<String, dynamic> data) => serialized(() async {
    final dir = await _folder(data['userId'], data['empresaId']);
    final name = sha256
        .convert(utf8.encode(data['visitaId'] as String))
        .toString();
    await _write(
      File('${dir.path}/$name.visita'),
      Uint8List.fromList(utf8.encode(jsonEncode(visitasWire(data)))),
    );
    notifyListeners();
  });

  Future<String> guardarFoto(
    String userId,
    String empresaId,
    Uint8List bytes,
  ) => serialized(() async {
    if (bytes.length > 6 * 1024 * 1024) {
      throw StateError('La foto supera 6 MB.');
    }
    final hash = sha256.convert(bytes).toString();
    final dir = await _folder(userId, empresaId);
    await _write(File('${dir.path}/$hash.foto'), bytes);
    return hash;
  });
  Future<Uint8List> foto(String userId, String empresaId, String hash) async {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) {
      throw StateError('Foto inválida.');
    }
    final dir = await _folder(userId, empresaId);
    return _read(File('${dir.path}/$hash.foto'));
  }
}
