import 'dart:convert';
import 'dart:js_interop';

class RutaMapPoint {
  final double lat;
  final double lng;

  const RutaMapPoint({required this.lat, required this.lng});

  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng};

  factory RutaMapPoint.fromJson(Map<String, dynamic> json) => RutaMapPoint(
    lat: (json['lat'] as num).toDouble(),
    lng: (json['lng'] as num).toDouble(),
  );
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

  factory RutaDirectionsResult.fromJson(Map<String, dynamic> json) {
    final rawPoints = (json['points'] as List?) ?? const [];
    return RutaDirectionsResult(
      ok: json['ok'] == true,
      error: (json['error'] ?? '').toString(),
      distanceMeters: (json['distanceMeters'] as num?)?.round() ?? 0,
      durationSeconds: (json['durationSeconds'] as num?)?.round() ?? 0,
      durationTrafficSeconds:
          (json['durationTrafficSeconds'] as num?)?.round() ?? 0,
      points: rawPoints
          .whereType<Map>()
          .map((p) => RutaMapPoint.fromJson(Map<String, dynamic>.from(p)))
          .toList(),
    );
  }
}

@JS('rutasDirections')
external JSPromise<JSString> _rutasDirections(JSString payloadJson);

Future<RutaDirectionsResult> calcularRutaConTrafico({
  required RutaMapPoint origin,
  required RutaMapPoint destination,
  List<RutaMapPoint> waypoints = const [],
}) async {
  final payload = jsonEncode({
    'origin': origin.toJson(),
    'destination': destination.toJson(),
    'waypoints': waypoints.map((p) => p.toJson()).toList(),
  });
  final raw = await _rutasDirections(payload.toJS).toDart;
  final decoded = jsonDecode(raw.toDart) as Map<String, dynamic>;
  return RutaDirectionsResult.fromJson(decoded);
}
