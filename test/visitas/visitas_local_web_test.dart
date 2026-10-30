@TestOn('browser')
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/visitas/visitas_local_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Android browser logout never opens native offline storage', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    FlutterSecureStorage.setMockInitialValues({});
    final store = VisitasLocalStore(
      directory: () async {
        throw StateError('Browser must not access native directories');
      },
    );
    expect(kIsWeb, isTrue);
    expect(VisitasLocalStore.disponible, isFalse);
    expect(await store.acceso(), isNull);
    await store.revocarAcceso();
    expect(store.revisionAcceso, 1);
  });
}
