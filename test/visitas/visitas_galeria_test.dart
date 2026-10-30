import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/visitas/visitas_galeria.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('gal');
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test('saves unchanged original bytes on $platform', () async {
      debugDefaultTargetPlatformOverride = platform;
      final original = Uint8List.fromList([255, 216, 255, 1, 2, 3]);
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'hasAccess' || call.method == 'requestAccess') {
              return true;
            }
            return null;
          });
      await guardarOriginalFotoVisita(original);
      final saved = calls.singleWhere((c) => c.method == 'putImageBytes');
      expect(saved.arguments['bytes'], original);
      expect(saved.arguments['name'], startsWith('Visita_original_'));
      expect(saved.arguments['album'], isNull);
    });
  }

  test('denied permission does not attempt saving', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return false;
        });
    await expectLater(
      guardarOriginalFotoVisita(Uint8List(1)),
      throwsStateError,
    );
    expect(calls, ['hasAccess', 'requestAccess']);
  });

  test('desktop does not request gallery permissions', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await guardarOriginalFotoVisita(Uint8List(1));
  });
}
