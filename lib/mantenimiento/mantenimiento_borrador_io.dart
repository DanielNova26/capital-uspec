import 'dart:io';
import 'package:path_provider/path_provider.dart';

Future<File> _archivo(String key) async {
  final directory = await getApplicationSupportDirectory();
  return File('${directory.path}/mantenimiento_borradores/$key');
}

Future<String?> leerBorrador(String key) async {
  final archivo = await _archivo(key);
  return await archivo.exists() ? archivo.readAsString() : null;
}

Future<void> escribirBorrador(String key, String? data) async {
  final archivo = await _archivo(key);
  if (data == null) {
    if (await archivo.exists()) await archivo.delete();
    return;
  }
  await archivo.parent.create(recursive: true);
  final temporal = File('${archivo.path}.tmp');
  await temporal.writeAsString(data, flush: true);
  await temporal.rename(archivo.path);
}
