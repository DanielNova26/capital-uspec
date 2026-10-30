import 'package:flutter/foundation.dart';
import 'package:gal/gal.dart';

/// Saves the unmodified capture before producing the stamped visit evidence.
/// Existing gallery images are excluded by the caller to avoid duplicates.
Future<void> guardarOriginalFotoVisita(Uint8List bytes) async {
  if (kIsWeb ||
      (defaultTargetPlatform != TargetPlatform.android &&
          defaultTargetPlatform != TargetPlatform.iOS)) {
    return;
  }
  if (!await Gal.hasAccess() && !await Gal.requestAccess()) {
    throw StateError('No hay permiso para añadir fotos a la galería.');
  }
  await Gal.putImageBytes(
    bytes,
    name: 'Visita_original_${DateTime.now().microsecondsSinceEpoch}',
  );
}
