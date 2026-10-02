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
/// En móvil desaparece y deja que `AppScrollBehavior` decida (que allí es:
/// ninguna barra).
///
/// En escritorio deja UNA sola barra (28 sep 2026). Antes sumaba la suya a la
/// que `AppScrollBehavior` ya pone en todo scroll horizontal, y quedaban dos
/// encimadas. Sin [controller], la de aquí buscaba el PrimaryScrollController,
/// no encontraba posición ("The Scrollbar's ScrollController has no
/// ScrollPosition attached") y al arrastrarla la tabla no se movía: fue la
/// queja de Análisis de Interventoría. Ahora:
/// - sin [controller], no dibuja nada: vale la barra del tema, que sí está
///   atada al scroll;
/// - con [controller], dibuja la suya y apaga la del tema debajo.
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
    final propio = controller;
    if (propio == null) return child;
    return Scrollbar(
      controller: propio,
      thumbVisibility: thumbVisibility,
      interactive: true,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: child,
      ),
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
