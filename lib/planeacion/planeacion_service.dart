import 'package:cloud_functions/cloud_functions.dart';

typedef PlaneacionDato = Map<String, dynamic>;

List<PlaneacionDato> filasPlaneacion(Object? value) => value is List
    ? value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
    : [];

String unidadPlaneacion(Object? value) {
  final v = (value ?? '').toString().trim().toLowerCase();
  if (['kg', 'kl', 'kilo', 'kilos', 'kilogramo', 'kilogramos'].contains(v)) {
    return 'kg';
  }
  if (['l', 'lt', 'litro', 'litros'].contains(v)) return 'l';
  if (['und', 'un', 'unidad', 'unidades'].contains(v)) return 'und';
  return v;
}

class PlaneacionService {
  PlaneacionService(this.empresaId, {FirebaseFunctions? functions})
    : _functions = functions;
  final String empresaId;
  final FirebaseFunctions? _functions;

  Future<PlaneacionDato> operar(
    String accion, [
    PlaneacionDato datos = const {},
  ]) async {
    final functions =
        _functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');
    final result = await functions.httpsCallable('planeacionOperar').call({
      'empresaId': empresaId,
      'accion': accion,
      'datos': datos,
    });
    return Map<String, dynamic>.from(result.data as Map);
  }
}
