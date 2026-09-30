import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/admin/admin_access_workspace.dart';

void main() {
  Future<void> mount(
    WidgetTester tester,
    Size size, {
    TargetPlatform platform = TargetPlatform.android,
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: platform),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const Scaffold(body: _Harness()),
      ),
    );
  }

  for (final width in [1024.0, 1366.0]) {
    testWidgets('Apps y roles navega en Web de ${width.toInt()} px', (
      tester,
    ) async {
      await mount(tester, Size(width, 768), textScale: 1.3);
      expect(
        find.byType(DropdownButtonFormField<AdminAccessSection>),
        findsNothing,
      );
      await tester.tap(find.text('Perfiles generales'));
      await tester.pump();
      expect(find.text('contenido perfiles'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('Apps y roles navega en ${platform.name}', (tester) async {
      await mount(tester, const Size(390, 844), platform: platform);
      await tester.tap(
        find.byType(DropdownButtonFormField<AdminAccessSection>),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Configuración de apps').last);
      await tester.pumpAndSettle();
      expect(find.text('contenido apps'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

class _Harness extends StatefulWidget {
  const _Harness();

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  AdminAccessSection selected = AdminAccessSection.modulos;

  @override
  Widget build(BuildContext context) => AdminAccessWorkspace(
    selected: selected,
    onSelected: (next) => setState(() => selected = next),
    sectionBuilder: (section) =>
        Center(child: Text('contenido ${section.name}')),
  );
}
