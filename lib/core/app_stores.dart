// lib/core/app_stores.dart
//
// Enlaces a las tiendas para descargar la app desde la versión web
// (reunión del 18 sep 2026: "botones en la versión web para descargar la
// aplicación desde la App Store o la Play Store").
//
// El de Play Store sale del `applicationId` de Android. El de App Store
// necesita el número que Apple asigna a la ficha (https://apps.apple.com/
// co/app/idNNNNNNNNNN); mientras esté vacío el botón de iPhone no se pinta.

import 'package:flutter/foundation.dart' show kIsWeb;

const String kUrlPlayStore =
    'https://play.google.com/store/apps/details?id=com.todogestion.app';

/// Pendiente de la ficha en App Store Connect. Vacío = sin botón.
const String kUrlAppStore = '';

/// Los botones solo tienen sentido en web: en el teléfono ya se está dentro
/// de la app.
bool get mostrarEnlacesTiendas =>
    kIsWeb && (kUrlPlayStore.isNotEmpty || kUrlAppStore.isNotEmpty);
