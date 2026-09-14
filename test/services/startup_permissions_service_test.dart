import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/services/startup_permissions_service.dart';

void main() {
  test('Android solicita solo permisos de uso directo', () {
    final plan = startupPermissionPlan(TargetPlatform.android);

    expect(plan, const [
      StartupPermissionKind.notifications,
      StartupPermissionKind.camera,
      StartupPermissionKind.microphone,
      StartupPermissionKind.locationWhenInUse,
    ]);
    expect(plan, isNot(contains(StartupPermissionKind.photos)));
    expect(plan, isNot(contains(StartupPermissionKind.speech)));
  });

  test('iOS incluye galería y reconocimiento de voz', () {
    final plan = startupPermissionPlan(TargetPlatform.iOS);

    expect(plan, contains(StartupPermissionKind.notifications));
    expect(plan, contains(StartupPermissionKind.camera));
    expect(plan, contains(StartupPermissionKind.microphone));
    expect(plan, contains(StartupPermissionKind.speech));
    expect(plan, contains(StartupPermissionKind.photos));
    expect(plan, contains(StartupPermissionKind.locationWhenInUse));
  });

  test('escritorio no abre diálogos de permisos móviles', () {
    expect(startupPermissionPlan(TargetPlatform.windows), isEmpty);
    expect(startupPermissionPlan(TargetPlatform.macOS), isEmpty);
    expect(startupPermissionPlan(TargetPlatform.linux), isEmpty);
  });
}
