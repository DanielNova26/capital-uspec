import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:file_saver/file_saver.dart';

typedef BioMap = Map<String, dynamic>;
typedef BioRequest = Future<BioMap> Function(BioMap input);
BioMap bioMap(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};
List<BioMap> bioList(dynamic value) =>
    value is List ? value.map(bioMap).toList() : [];
String bioDia(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String bioHoras(dynamic minutos) {
  final n = (minutos as num? ?? 0).round();
  return '${n ~/ 60} h ${(n % 60).toString().padLeft(2, '0')} min';
}

String bioHora(dynamic minutos) {
  final n = (minutos as num? ?? 0).toInt();
  return '${(n ~/ 60 % 24).toString().padLeft(2, '0')}:${(n % 60).toString().padLeft(2, '0')}${n >= 1440 ? ' (+1 día)' : ''}';
}

String bioHorario(BioMap h) => h['libre'] == true
    ? 'Día libre'
    : '${bioHora(h['inicio'])} – ${bioHora(h['fin'])}';
int bioMinuto(String raw) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(raw.trim());
  if (m == null) {
    throw const FormatException(
      'Escribe la hora en formato 24 h: 21:00, 06:00.',
    );
  }
  final h = int.parse(m[1]!);
  final min = int.parse(m[2]!);
  if (h > 23 || min > 59) throw const FormatException('Hora inválida.');
  return h * 60 + min;
}

String bioCsv(List<BioMap> rows) {
  String safe(dynamic value) {
    var s = '$value';
    if (RegExp(r'^[=+@\-\t\r\n]').hasMatch(s)) s = "'$s";
    return '"${s.replaceAll('"', '""')}"';
  }

  return '\uFEFF${[
    ['Colaborador', 'Fecha de entrada', 'Programados (min)', 'Trabajados (min)', 'Ordinarios (min)', 'Fuera de horario (min)', 'Extras aprobadas (min)', 'Faltantes (min)', 'Estado', 'Incidencias'],
    ...rows.map((r) => [r['nombre'] ?? r['userId'], r['dia'], r['programado'], r['trabajado'], r['ordinario'], r['extra'], r['aprobado'], r['faltante'], r['estado'], (r['incidencias'] as List).join('; ')]),
  ].map((r) => r.map(safe).join(',')).join('\r\n')}';
}

class BiometricoService {
  BiometricoService(this.empresaId);
  final String empresaId;
  Future<BioMap> call(BioMap input) async => bioMap(
    (await FirebaseFunctions.instanceFor(region: 'us-central1')
            .httpsCallable(
              'biometricoGestion',
              options: HttpsCallableOptions(
                timeout: const Duration(seconds: 120),
              ),
            )
            .call({...input, 'empresaId': empresaId}))
        .data,
  );
  static Future<void> guardar(String name, String ext, String contenido) async {
    await FileSaver.instance.saveFile(
      name: name,
      fileExtension: ext,
      bytes: Uint8List.fromList(utf8.encode(contenido)),
      mimeType: MimeType.other,
    );
  }

  static String configuracion(BioMap cred) =>
      '''#pragma once
// Privado: no publicar este archivo. Completa tu WiFi antes de cargarlo.
const char* TODO_WIFI_SSID = "";
const char* TODO_WIFI_PASS = "";
const char* TODO_DEVICE_ID = ${jsonEncode(cred['deviceId'])};
const char* TODO_API_URL = ${jsonEncode(cred['url'])};
const char* TODO_API_TOKEN = ${jsonEncode(cred['token'])};
''';
}
