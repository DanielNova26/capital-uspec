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
//
// Y lo horizontal solo lleva barra donde hay puntero. En un teléfono el dedo
// ya desliza la fila, así que la barra no informa nada y encima queda pintada
// sobre las tarjetas: es lo que se veía atravesado en Home, Requerimientos y
// las pestañas de los módulos.

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';

/// Decide si una fila con scroll horizontal debe mostrar barra.
///
/// Se resuelve por plataforma, no por `kIsWeb`, y eso cubre los dos casos de
/// una sola vez: Flutter web en un escritorio reporta windows/macOS/linux
/// (lleva barra), y en el navegador de un teléfono reporta android/iOS (no la
/// lleva), igual que la app nativa.
bool usaBarraHorizontal(BuildContext context) {
  switch (Theme.of(context).platform) {
    case TargetPlatform.linux:
    case TargetPlatform.macOS:
    case TargetPlatform.windows:
      return true;
    case TargetPlatform.android:
    case TargetPlatform.iOS:
    case TargetPlatform.fuchsia:
      return false;
  }
}

/// Envoltorio para los scroll horizontales que ya traían `Scrollbar` a mano.
/// En escritorio se comporta igual que antes; en móvil desaparece y deja que
/// `AppScrollBehavior` decida (que allí es: ninguna barra).
class BarraHorizontal extends StatelessWidget {
  final ScrollController? controller;
  final bool thumbVisibility;
  final Widget child;

  const BarraHorizontal({
    super.key,
    this.controller,
    this.thumbVisibility = false,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (!usaBarraHorizontal(context)) return child;
    return Scrollbar(
      controller: controller,
      thumbVisibility: thumbVisibility,
      interactive: true,
      child: child,
    );
  }
}

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
    // En móvil `super` devuelve el hijo tal cual para el eje horizontal, que
    // es justo lo que queremos: ninguna barra.
    if (!esHorizontal || !usaBarraHorizontal(context)) {
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
