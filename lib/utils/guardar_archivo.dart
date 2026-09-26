// lib/utils/guardar_archivo.dart
//
// Guardar un archivo generado en memoria (Excel, PDF, CSV, ZIP) donde la
// persona lo pueda encontrar, en las tres plataformas.
//
// `FileSaver.instance.saveFile` hace cosas distintas según dónde corre:
//   - Web: descarga del navegador.
//   - Android: lo deja en Descargas.
//   - iOS / iPadOS: lo escribe en la carpeta Documentos de la app y ya. Sin
//     aviso, sin vista previa y, sin `UIFileSharingEnabled` en Info.plist,
//     invisible para siempre: en iPhone y iPad los botones "Descargar Excel"
//     no hacían nada que la persona pudiera ver.
//
// Aquí, en iOS, después de guardar se abre la vista previa del sistema (Quick
// Look), que trae el botón de compartir: "Guardar en Archivos", correo,
// WhatsApp, AirDrop. Y como Info.plist ahora declara la carpeta como visible,
// la copia queda además en Archivos › En mi iPhone/iPad › To-Do Gestión.
//
// Misma firma que `FileSaver.instance.saveFile` a propósito: reemplazarlo es
// cambiar el nombre de la llamada y nada más.

import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:open_filex/open_filex.dart';

export 'package:file_saver/file_saver.dart' show MimeType;

/// Guarda [bytes] como `name.fileExtension` y, en iOS, lo abre para que la
/// persona lo vea y lo pueda compartir o guardar en Archivos.
Future<void> guardarArchivo({
  required String name,
  required Uint8List bytes,
  required String fileExtension,
  required MimeType mimeType,
}) async {
  final ruta = await FileSaver.instance.saveFile(
    name: name,
    bytes: bytes,
    fileExtension: fileExtension,
    mimeType: mimeType,
  );
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
  if (ruta.isEmpty || !ruta.startsWith('/')) return;
  try {
    await OpenFilex.open(ruta);
  } catch (_) {
    // El archivo ya quedó guardado en Archivos; la vista previa es un extra.
  }
}

/// Punto de anclaje para la hoja de compartir en iPad.
///
/// En iPad la hoja de compartir es un popover y necesita saber de dónde sale:
/// `share_plus` lanza error si no se le da, y `Printing.sharePdf` la pega a
/// la esquina superior izquierda. En iPhone y Android se ignora.
///
/// Con el `context` de un botón sale del botón; con el de una pantalla
/// completa, del centro de la pantalla.
Rect origenCompartir(BuildContext context) {
  final pantalla = MediaQuery.sizeOf(context);
  final caja = context.findRenderObject();
  if (caja is RenderBox && caja.hasSize && caja.attached) {
    final rect = caja.localToGlobal(Offset.zero) & caja.size;
    final esPantallaEntera =
        rect.width >= pantalla.width * 0.9 &&
        rect.height >= pantalla.height * 0.9;
    if (!esPantallaEntera && !rect.isEmpty) return rect;
  }
  return Rect.fromCenter(
    center: pantalla.center(Offset.zero),
    width: 1,
    height: 1,
  );
}
