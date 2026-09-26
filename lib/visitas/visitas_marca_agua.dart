// lib/visitas/visitas_marca_agua.dart
//
// Marca de agua de las fotos de una visita (26 sep 2026): "agregar
// evidencias adicionales y esas fotos generarlas con una marca de agua".
// Toda foto que se toma en la visita (de una pregunta, de una fila de tabla
// o adicional) sale con:
//  - una banda debajo con el logo, el área y el establecimiento, fecha y
//    hora, el profesional y la ubicación registrada al iniciar;
//  - el establecimiento y la fecha en diagonal sobre la foto, para que no se
//    pueda pasar como evidencia de otra visita.
// Es el mismo dibujo de las evidencias de Rutas (`rutas_watermark.dart`)
// con el color de Visitas.

import 'dart:typed_data';
import 'dart:ui' as ui;

import '../rutas/rutas_watermark.dart';
import 'visitas_models.dart';

String _dd(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

String _hhmm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// Las líneas de la banda. Pura, para probarla sin dibujar.
List<String> lineasMarcaVisita({
  required VisitaProfesional v,
  required String detalle,
  required DateTime ahora,
}) {
  final ini = v.inicio;
  return [
    'VISITA ${v.areaNombre.toUpperCase()} · ${v.establecimiento}',
    '${_dd(ahora)} ${_hhmm(ahora)}${detalle.trim().isEmpty ? '' : ' · $detalle'}',
    'Profesional: ${v.profesionalNombre}',
    if (v.esPrueba)
      'Visita de prueba · sin comprobar ubicación'
    else if (ini != null && ini.tieneUbicacion)
      'GPS ${ini.lat!.toStringAsFixed(5)}, ${ini.lng!.toStringAsFixed(5)}'
          '${ini.distanciaMetros == null ? '' : ' · a ${ini.distanciaMetros!.round()} m del establecimiento'}',
  ];
}

/// La foto con su marca, en JPEG. Si algo falla al dibujar se devuelve la
/// original: una evidencia sin marca es mejor que ninguna.
Future<({Uint8List bytes, bool conMarca})> fotoConMarcaVisita({
  required Uint8List foto,
  required VisitaProfesional v,
  required String detalle,
  Uint8List? logo,
  DateTime? ahora,
}) async {
  final t = ahora ?? DateTime.now();
  try {
    final r = await generarEvidenciaConMarca(
      fotoBytes: foto,
      lineas: lineasMarcaVisita(v: v, detalle: detalle, ahora: t),
      logoBytes: logo,
      acento: const ui.Color(0xFF7C3AED),
      marcaDiagonal: '${v.establecimiento.toUpperCase()}\n${_dd(t)}',
      jpgQuality: 80,
    );
    return (bytes: r.full, conMarca: true);
  } catch (_) {
    return (bytes: foto, conMarca: false);
  }
}
