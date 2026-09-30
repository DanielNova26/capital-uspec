import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/admin/admin_internal_workspace.dart';

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

  testWidgets('web cambia entre catálogos, grupos y membresía', (tester) async {
    await mount(tester, const Size(1440, 900));
    expect(find.text('contenido catalogos'), findsOneWidget);
    expect(
      find.byType(DropdownButtonFormField<AdminInternalSection>),
      findsNothing,
    );
    await tester.tap(find.text('Grupos'));
    await tester.pump();
    expect(find.text('contenido grupos'), findsOneWidget);
    expect(find.text('contenido catalogos'), findsNothing);
    await tester.tap(find.text('Membresía'));
    await tester.pump();
    expect(find.text('contenido membresia'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('móvil usa selector compacto para todas las secciones', (
    tester,
  ) async {
    await mount(tester, const Size(390, 844));
    expect(find.byType(ListTile), findsNothing);
    for (final section in AdminInternalSection.values.skip(1)) {
      await tester.tap(
        find.byType(DropdownButtonFormField<AdminInternalSection>),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(section.label).last);
      await tester.pumpAndSettle();
      expect(find.text('contenido ${section.name}'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  for (final width in [1024.0, 1366.0]) {
    testWidgets('Web de ${width.toInt()} px mantiene panel y contenido', (
      tester,
    ) async {
      await mount(tester, Size(width, 768));
      expect(
        find.byType(DropdownButtonFormField<AdminInternalSection>),
        findsNothing,
      );
      await tester.tap(find.text('Grupos'));
      await tester.pump();
      expect(find.text('contenido grupos'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('${platform.name} usa navegación compacta sin desbordes', (
      tester,
    ) async {
      await mount(tester, const Size(390, 844), platform: platform);
      expect(
        find.byType(DropdownButtonFormField<AdminInternalSection>),
        findsOneWidget,
      );
      await tester.tap(
        find.byType(DropdownButtonFormField<AdminInternalSection>),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Membresía').last);
      await tester.pumpAndSettle();
      expect(find.text('contenido membresia'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('texto ampliado conserva navegación en portátil estrecho', (
    tester,
  ) async {
    await mount(tester, const Size(1024, 768), textScale: 1.3);
    await tester.tap(find.text('Multiempresa'));
    await tester.pump();
    expect(find.text('contenido multiempresa'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _Harness extends StatefulWidget {
  const _Harness();

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  AdminInternalSection section = AdminInternalSection.catalogos;

  @override
  Widget build(BuildContext context) => AdminInternalWorkspace(
    selected: section,
    onSelected: (next) => setState(() => section = next),
    sectionBuilder: (selected) =>
        Center(child: Text('contenido ${selected.name}')),
  );
}
