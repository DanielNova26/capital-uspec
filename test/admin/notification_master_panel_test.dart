import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/admin/notification_master_panel.dart';
import 'package:todo/admin/notification_master_service.dart';
import 'package:todo/core/notification_catalog.dart';
import 'package:todo/home/notification_preferences_screen.dart';
import 'package:todo/services/notification_preferences_service.dart';

class MasterFake implements NotificationMasterService {
  String? savedCompany;
  @override
  Future<Map<String, Map<String, dynamic>>> cargar(String empresaId) async =>
      {};
  @override
  Future<void> guardar({
    required String empresaId,
    required String userId,
    required Map<String, Map<CanalNotificacion, bool>> elegido,
  }) async {
    savedCompany = empresaId;
  }
}

class PreferencesFake implements NotificationPreferencesService {
  String? savedUser;
  @override
  Future<Map<String, Map<CanalNotificacion, bool>>> cargar(
    String userId,
  ) async => {};
  @override
  Future<void> guardar(
    String userId,
    Map<String, Map<CanalNotificacion, bool>> elegido,
  ) async {
    savedUser = userId;
  }
}

void main() {
  for (final width in [390.0, 768.0, 1024.0, 1366.0]) {
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      testWidgets('maestro y avisos $width $platform texto 1.6', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        Widget app(Widget child) => MaterialApp(
          theme: ThemeData(platform: platform),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: Scaffold(body: child),
        );
        final master = MasterFake();
        await tester.pumpWidget(
          app(
            AdminNotificationMasterPanel(
              userId: 'persona',
              empresaId: 'B',
              service: master,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.byType(Switch).first);
        await tester.tap(find.byType(Switch).first);
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Guardar'),
          -250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Guardar'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Guardar'));
        await tester.pumpAndSettle();
        expect(master.savedCompany, 'B');
        expect(tester.takeException(), isNull);
        final personal = PreferencesFake();
        await tester.pumpWidget(
          app(
            NotificationPreferencesScreen(userId: 'persona', service: personal),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byType(SwitchListTile).first);
        await tester.tap(find.byType(SwitchListTile).first);
        await tester.pumpAndSettle();
        expect(personal.savedUser, 'persona');
        expect(tester.takeException(), isNull);
      });
    }
  }
}
