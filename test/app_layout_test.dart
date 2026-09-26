// La composición amplia (barra lateral, cabecera de escritorio) depende del
// ancho y de si el aparato es un teléfono, no de si corre en un navegador.
// Un iPad acostado mide lo mismo que un portátil y debe verse como tal; un
// iPhone acostado sigue siendo un teléfono.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/theme/app_layout.dart';
import 'package:todo/widgets/internal_module_layout.dart';

bool _amplio(
  Size ventana,
  TargetPlatform plataforma, {
  bool web = false,
  double minAncho = kAnchoLayoutAmplio,
}) => anchoUsaLayoutAmplio(
  ancho: ventana.width,
  ventana: ventana,
  minAncho: minAncho,
  web: web,
  plataforma: plataforma,
);

void main() {
  group('anchoUsaLayoutAmplio', () {
    test('iPad acostado usa la composición amplia', () {
      // iPad 10.ª gen, iPad Air 13", iPad Pro 12.9" y iPad mini acostados.
      for (final ventana in const [
        Size(1180, 820),
        Size(1366, 1024),
        Size(1024, 768),
        Size(1133, 744),
      ]) {
        expect(
          _amplio(ventana, TargetPlatform.iOS),
          isTrue,
          reason: '$ventana',
        );
      }
    });

    test('iPad en vertical o en Split View angosto usa la de teléfono', () {
      for (final ventana in const [
        Size(820, 1180),
        Size(744, 1133),
        Size(507, 1024),
        Size(320, 1024),
      ]) {
        expect(
          _amplio(ventana, TargetPlatform.iOS),
          isFalse,
          reason: '$ventana',
        );
      }
    });

    test('iPad Pro 12.9" en vertical ya alcanza la amplia', () {
      expect(_amplio(const Size(1024, 1366), TargetPlatform.iOS), isTrue);
    });

    test('un teléfono acostado nunca es escritorio', () {
      // iPhone 16 Pro Max y un Android grande, acostados.
      expect(_amplio(const Size(932, 430), TargetPlatform.iOS), isFalse);
      expect(_amplio(const Size(915, 412), TargetPlatform.android), isFalse);
    });

    test('tableta Android acostada usa la composición amplia', () {
      expect(_amplio(const Size(1280, 800), TargetPlatform.android), isTrue);
    });

    test('la web conserva la regla de siempre: solo el ancho', () {
      expect(
        _amplio(const Size(932, 430), TargetPlatform.iOS, web: true),
        isTrue,
      );
      expect(
        _amplio(const Size(899, 1000), TargetPlatform.windows, web: true),
        isFalse,
      );
      expect(
        _amplio(const Size(1440, 900), TargetPlatform.windows, web: true),
        isTrue,
      );
    });

    test('respeta el ancho mínimo de cada pantalla', () {
      const ipad = Size(1024, 768);
      expect(_amplio(ipad, TargetPlatform.iOS, minAncho: 980), isTrue);
      expect(_amplio(ipad, TargetPlatform.iOS, minAncho: 1080), isFalse);
    });
  });

  group('InternalModuleLayout', () {
    Future<void> montar(
      WidgetTester tester,
      Size ventana, {
      EdgeInsets padding = EdgeInsets.zero,
    }) async {
      tester.view.physicalSize = ventana;
      tester.view.devicePixelRatio = 1;
      tester.view.padding = FakeViewPadding(
        left: padding.left,
        top: padding.top,
        right: padding.right,
        bottom: padding.bottom,
      );
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        const MaterialApp(
          home: InternalModuleLayout(
            title: 'Compras',
            subtitle: 'Requerimientos',
            accentColor: Colors.teal,
            userId: 'u',
            empresaId: 'e',
            child: SizedBox.expand(),
          ),
        ),
      );
    }

    testWidgets(
      'en iPad acostado usa la cabecera amplia, debajo de la barra de estado',
      (tester) async {
        await montar(
          tester,
          const Size(1180, 820),
          padding: const EdgeInsets.only(top: 24, bottom: 20),
        );

        expect(find.byType(AppBar), findsNothing);
        expect(find.text('COMPRAS'), findsOneWidget);
        // El botón de volver no puede quedar debajo de la hora y la batería.
        final volver = tester.getRect(find.byTooltip('Volver'));
        expect(volver.top, greaterThanOrEqualTo(24));
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );

    testWidgets(
      'en iPhone acostado conserva el AppBar de teléfono',
      (tester) async {
        await montar(
          tester,
          const Size(932, 430),
          padding: const EdgeInsets.only(left: 59, right: 59, bottom: 21),
        );

        expect(find.byType(AppBar), findsOneWidget);
        expect(find.text('COMPRAS'), findsNothing);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );

    testWidgets(
      'en iPad vertical usa el AppBar de teléfono',
      (tester) async {
        await montar(
          tester,
          const Size(820, 1180),
          padding: const EdgeInsets.only(top: 24, bottom: 20),
        );

        expect(find.byType(AppBar), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );
  });
}
