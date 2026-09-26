// lib/theme/app_layout.dart
//
// Cuándo una pantalla usa la composición amplia (barra lateral fija, tablas,
// maestro-detalle, cabecera propia) y cuándo la de teléfono (AppBar, drawer,
// tarjetas apiladas).
//
// Antes cada pantalla lo decidía con `kIsWeb && ancho >= N`. Eso dejaba al
// iPad (y a las tabletas Android) con la versión de teléfono estirada a 1024
// o 1366 puntos: drawer escondido, tarjetas de lado a lado y media pantalla
// vacía, aunque el ancho es el mismo de un portátil. Y al revés, las pantallas
// que solo miraban el ancho (`InternalModuleLayout`) le ponían la cabecera de
// escritorio a un iPhone grande acostado (932 × 430), sin AppBar y con el
// botón de volver debajo de la isla.
//
// La regla ahora es una sola:
//   - Web y escritorio: amplia desde el ancho pedido, como siempre.
//   - Tableta (iPad, tableta Android): igual que la web al mismo ancho. Un
//     iPad acostado usa la barra lateral; en vertical o en Split View, la de
//     teléfono, porque 820 puntos menos una barra de 280 es un teléfono.
//   - Teléfono: nunca, ni acostado. Se reconoce por el lado corto de la
//     ventana (< 600), que no cambia al girar.
//
// Solo decide composición. Lo que depende de verdad del navegador (arrastrar
// archivos, descargar con el navegador, `dart:html`) sigue con `kIsWeb`.

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Ancho desde el cual la app pasa a la composición amplia.
const double kAnchoLayoutAmplio = 900;

/// Lado corto mínimo de una tableta. Material usa 600 como frontera entre
/// teléfono y tableta; el iPad mini más chico mide 744.
const double kLadoCortoTableta = 600;

/// ¿La ventana es la de un teléfono nativo (Android/iOS)?
///
/// En web siempre es falso: el navegador ya decidía por ancho y se conserva.
/// [web] y [plataforma] existen para las pruebas.
bool esTelefonoNativo(Size ventana, {bool? web, TargetPlatform? plataforma}) {
  if (web ?? kIsWeb) return false;
  final p = plataforma ?? defaultTargetPlatform;
  final esMovil = p == TargetPlatform.android || p == TargetPlatform.iOS;
  return esMovil && ventana.shortestSide < kLadoCortoTableta;
}

/// Regla pura detrás de [usaLayoutAmplio], separada para poder probarla y para
/// quien ya tiene el ancho disponible (un `LayoutBuilder`).
bool anchoUsaLayoutAmplio({
  required double ancho,
  required Size ventana,
  double minAncho = kAnchoLayoutAmplio,
  bool? web,
  TargetPlatform? plataforma,
}) {
  if (ancho < minAncho) return false;
  return !esTelefonoNativo(ventana, web: web, plataforma: plataforma);
}

/// ¿Esta pantalla debe usar la composición amplia?
///
/// Reemplaza a `kIsWeb && MediaQuery.sizeOf(context).width >= minAncho`.
bool usaLayoutAmplio(
  BuildContext context, {
  double minAncho = kAnchoLayoutAmplio,
}) {
  final ventana = MediaQuery.sizeOf(context);
  return anchoUsaLayoutAmplio(
    ancho: ventana.width,
    ventana: ventana,
    minAncho: minAncho,
  );
}
