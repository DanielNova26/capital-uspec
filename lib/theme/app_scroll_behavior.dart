// lib/theme/app_scroll_behavior.dart
//
// Comportamiento de scroll de toda la app.
//
// Dos cosas que Flutter NO hace por defecto y aquí sí:
//
//  1. **Barra en las tablas horizontales.** `MaterialScrollBehavior` nunca
//     dibuja scrollbar en el eje horizontal, así que las tablas anchas
//     (Compras, Interventoría, Admin…) se deslizaban sin ninguna pista de que
//     había más columnas. Ahora llevan barra, y visible.
//
//  2. **Arrastrar con el mouse.** En web, un `SingleChildScrollView`
//     horizontal solo responde a la rueda o a la barra. Habilitar el mouse
//     como dispositivo de arrastre permite "agarrar" la tabla y moverla.
//
// El eje vertical conserva el comportamiento de la plataforma: barra en
// escritorio/web y la indicación efímera de siempre en móvil, para no llenar
// cada lista del teléfono de barras permanentes.

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';

class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
    PointerDeviceKind.unknown,
  };

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    final esHorizontal =
        details.direction == AxisDirection.left ||
        details.direction == AxisDirection.right;
    if (!esHorizontal) {
      return super.buildScrollbar(context, child, details);
    }

    // `thumbVisibility` solo se fuerza cuando el scrollable trae su propio
    // controlador: con uno compartido (o el primario) Flutter exige una única
    // posición adjunta y lanza una aserción. Sin controlador propio, la barra
    // igual aparece al desplazar.
    return Scrollbar(
      controller: details.controller,
      interactive: true,
      thumbVisibility: details.controller != null,
      child: child,
    );
  }
}

/// Barra con grosor suficiente para agarrarla con el mouse.
final ScrollbarThemeData kAppScrollbarTheme = ScrollbarThemeData(
  thickness: WidgetStateProperty.resolveWith(
    (states) => states.contains(WidgetState.hovered) ? 10 : 7,
  ),
  radius: const Radius.circular(8),
  interactive: true,
);
