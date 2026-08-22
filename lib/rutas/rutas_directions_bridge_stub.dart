class RutaMapPoint {
  final double lat;
  final double lng;

  const RutaMapPoint({required this.lat, required this.lng});
}

class RutaDirectionsResult {
  final bool ok;
  final String error;
  final int distanceMeters;
  final int durationSeconds;
  final int durationTrafficSeconds;
  final List<RutaMapPoint> points;

  const RutaDirectionsResult({
    required this.ok,
    this.error = '',
    this.distanceMeters = 0,
    this.durationSeconds = 0,
    this.durationTrafficSeconds = 0,
    this.points = const [],
  });
}

Future<RutaDirectionsResult> calcularRutaConTrafico({
  required RutaMapPoint origin,
  required RutaMapPoint destination,
  List<RutaMapPoint> waypoints = const [],
}) async {
  return const RutaDirectionsResult(
    ok: false,
    error: 'El cálculo con Google Directions solo está disponible en web.',
  );
}
