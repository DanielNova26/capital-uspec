import 'package:shared_preferences/shared_preferences.dart';

Future<String?> leerBorrador(String key) async =>
    (await SharedPreferences.getInstance()).getString(
      'mantenimiento_borrador_$key',
    );

Future<void> escribirBorrador(String key, String? data) async {
  final prefs = await SharedPreferences.getInstance();
  final storageKey = 'mantenimiento_borrador_$key';
  final ok = data == null
      ? await prefs.remove(storageKey)
      : await prefs.setString(storageKey, data);
  if (!ok) {
    throw StateError('No se pudo guardar el borrador en este navegador.');
  }
}
