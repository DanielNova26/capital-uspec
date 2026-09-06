// lib/talento_humano/foto_carnet_captura.dart
//
// Tomar o reemplazar la foto que sale en el carnet.
//
// La foto del carnet NO es una foto aparte: es la misma `fotoUrl` de la hoja de
// vida. Guardar una segunda foto "de carnet" dejaría a la app con dos caras
// para la misma persona y una de las dos siempre vieja. Por eso esta pantalla
// escribe donde ya vive: la subcolección `hoja_de_vida/datos` y el documento
// raíz de TBL_USUARIOS, que es de donde leen las listas y los avatares.
//
// El recorte de fondo se intenta y se ofrece; nunca se impone. Ver
// foto_carnet.dart para por qué solo ocurre en Android e iOS.

import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'foto_carnet.dart';
import 'hoja_de_vida_service.dart';

const String _kFont = 'Arial';

/// Toma una foto nueva y la deja guardada en la hoja de vida.
///
/// Devuelve la URL nueva, o `null` si se canceló o falló. El llamador solo
/// tiene que refrescar lo que muestre la foto.
Future<String?> capturarFotoDeCarnet(
  BuildContext context, {
  required String userId,
  required String nombreVisible,
}) async {
  final elegida = await _elegirImagen(context);
  if (elegida == null) return null;
  if (!context.mounted) return null;

  // El recorte tarda: en un teléfono de gama baja, con una foto de 12 MP, son
  // un par de segundos entre ML Kit y la composición.
  final recortada = await _conIndicador(
    context,
    'Quitando el fondo…',
    () => recortarFondoCarnet(rutaArchivo: elegida.ruta, bytes: elegida.bytes),
  );
  if (!context.mounted) return null;

  final escogida = await _confirmar(
    context,
    original: elegida.bytes,
    recortada: recortada,
  );
  if (escogida == null) return null;
  if (!context.mounted) return null;

  return _conIndicador(context, 'Guardando la foto…', () async {
    try {
      return await _guardar(userId: userId, bytes: escogida);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo guardar la foto de $nombreVisible: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return null;
    }
  });
}

typedef _Imagen = ({Uint8List bytes, String ruta, String extension});

/// Cámara o galería en el teléfono; archivo en web y escritorio.
///
/// El límite de 1600 px no es estético: ML Kit y la composición trabajan pixel
/// a pixel, y una foto de 12 MP multiplica el tiempo por diez sin que el
/// círculo impreso de 21 mm gane un solo detalle.
Future<_Imagen?> _elegirImagen(BuildContext context) async {
  if (kIsWeb) {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final archivo = r?.files.singleOrNull;
    final bytes = archivo?.bytes;
    if (bytes == null) return null;
    return (
      bytes: bytes,
      ruta: archivo!.path ?? '',
      extension: (archivo.extension ?? 'jpg').toLowerCase(),
    );
  }

  final origen = await showModalBottomSheet<ImageSource>(
    context: context,
    builder: (_) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              'Foto del carnet',
              style: TextStyle(
                fontFamily: _kFont,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              'De frente, con buena luz y sin gorra. El fondo se quita solo.',
              style: TextStyle(
                fontFamily: _kFont,
                fontSize: 12.5,
                color: Color(0xFF64748B),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.camera_alt),
            title: const Text('Tomar la foto ahora'),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library),
            title: const Text('Elegir de la galería'),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
        ],
      ),
    ),
  );
  if (origen == null) return null;

  final tomada = await ImagePicker().pickImage(
    source: origen,
    imageQuality: 90,
    maxWidth: 1600,
    maxHeight: 1600,
  );
  if (tomada == null) return null;
  return (
    bytes: await tomada.readAsBytes(),
    ruta: tomada.path,
    extension: tomada.path.split('.').last.toLowerCase(),
  );
}

/// Deja ver el resultado antes de reemplazar nada.
///
/// Cuando hay recorte se muestran las dos y se puede quedar con la original: el
/// recorte falla con gorras, cabello suelto contra fondos claros y fotos de
/// cuerpo entero, y en esos casos la original es la buena.
Future<Uint8List?> _confirmar(
  BuildContext context, {
  required Uint8List original,
  required Uint8List? recortada,
}) {
  return showDialog<Uint8List>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('¿Así queda bien?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _muestra('Original', original),
              if (recortada != null) ...[
                const SizedBox(width: 16),
                _muestra('Sin fondo', recortada),
              ],
            ],
          ),
          const SizedBox(height: 14),
          Text(
            recortada == null
                ? soportaRecorteDeFondo
                      ? 'No se pudo separar a la persona del fondo. La foto se '
                            'guarda tal cual.'
                      : 'Quitar el fondo solo funciona tomando la foto desde '
                            'la app del celular. Aquí se guarda tal cual.'
                : 'Así se verá en el círculo del carnet.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: _kFont,
              fontSize: 12,
              color: Color(0xFF64748B),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancelar'),
        ),
        if (recortada != null)
          TextButton(
            onPressed: () => Navigator.pop(ctx, original),
            child: const Text('Usar la original'),
          ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, recortada ?? original),
          child: const Text('Guardar'),
        ),
      ],
    ),
  );
}

Widget _muestra(String etiqueta, Uint8List bytes) {
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      ClipOval(
        child: Image.memory(bytes, width: 104, height: 104, fit: BoxFit.cover),
      ),
      const SizedBox(height: 6),
      Text(
        etiqueta,
        style: const TextStyle(
          fontFamily: _kFont,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: Color(0xFF64748B),
        ),
      ),
    ],
  );
}

/// Sube la foto y la deja escrita en los dos sitios donde la app la lee.
///
/// Se escribe en la subcolección Y en el documento raíz porque las listas, los
/// avatares y el carnet leen del raíz, mientras que la hoja de vida lee de la
/// subcolección. Actualizar solo uno deja a la persona con dos caras según la
/// pantalla.
Future<String> _guardar({
  required String userId,
  required Uint8List bytes,
}) async {
  final svc = HojaDeVidaService();
  // Siempre `jpg`: lo que devuelve el recorte es JPEG, y el nombre del archivo
  // en Storage es fijo, así que una extensión distinta dejaría el archivo
  // anterior colgado sin que nadie lo borre.
  final url = await svc.uploadFile(userId, 'foto', bytes, 'jpg');

  final docRef = await svc.resolveDoc(userId);
  final batch = FirebaseFirestore.instance.batch();
  batch.set(docRef, {
    'fotoUrl': url,
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
  batch.set(docRef.collection('hoja_de_vida').doc('datos'), {
    'fotoUrl': url,
  }, SetOptions(merge: true));
  await batch.commit();

  return url;
}

/// Diálogo de espera bloqueante. Estas operaciones no se pueden dejar a medias
/// (una foto subida a medias y una URL sin escribir), así que no se ofrece
/// cancelar mientras corren.
Future<T> _conIndicador<T>(
  BuildContext context,
  String mensaje,
  Future<T> Function() tarea,
) async {
  // Se guarda el context DEL DIÁLOGO, no el de la pantalla. Con
  // `Navigator.canPop()` se cerraría lo que hubiera encima de la pila, que si
  // el diálogo no alcanzó a montarse es la pantalla entera.
  BuildContext? contextoDelDialogo;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      contextoDelDialogo = ctx;
      return PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  mensaje,
                  style: const TextStyle(fontFamily: _kFont, fontSize: 13.5),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
  try {
    return await tarea();
  } finally {
    // El `mounted` del State no sirve aquí: el diálogo tiene su propio ciclo de
    // vida y puede haberse ido ya (o no haber llegado a montarse nunca).
    final ctx = contextoDelDialogo;
    if (ctx != null && ctx.mounted) Navigator.of(ctx).pop();
  }
}
