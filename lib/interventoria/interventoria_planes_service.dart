import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:file_saver/file_saver.dart';

typedef PlanData = Map<String, dynamic>;
typedef PlanRequest = Future<PlanData> Function(PlanData input);

PlanData planMap(dynamic value) => value is Map
    ? value.map((k, v) => MapEntry(k.toString(), v))
    : <String, dynamic>{};
List<PlanData> planList(dynamic value) =>
    value is List ? value.map(planMap).toList() : [];
String planText(PlanData data, String key) => (data[key] ?? '').toString();

String planDia(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
DateTime planHoy() => DateTime.now().toUtc().subtract(const Duration(hours: 5));

bool planAprobado(PlanData item, String etapa) {
  final revision = planMap(item['${etapa}Revision']);
  return revision['estado'] == 'satisfactorio' &&
      revision['version'] == item['${etapa}Version'];
}

String planEstado(PlanData item, String etapa) {
  if (item['${etapa}Presentado'] != null) return 'Presentado en K2';
  if (planAprobado(item, etapa)) return 'Listo para K2';
  return switch (planMap(item['${etapa}Revision'])['estado']) {
    'devuelto' => 'Requiere corrección',
    'por_revisar' => 'Por revisar',
    _ => 'Pendiente de entrega',
  };
}

String planVencimiento(String fecha, {DateTime? ahora}) {
  final d = DateTime.tryParse(fecha);
  if (d == null) return 'Sin fecha máxima';
  final today = ahora ?? planHoy();
  final days = DateTime.utc(
    d.year,
    d.month,
    d.day,
  ).difference(DateTime.utc(today.year, today.month, today.day)).inDays;
  return days < 0
      ? 'Vencido hace ${-days} días'
      : days == 0
      ? 'Vence hoy'
      : 'Vence en $days días';
}

class InterventoriaPlanesService {
  InterventoriaPlanesService(this.empresaId);
  final String empresaId;

  Future<PlanData> call(PlanData input) async {
    final result = await FirebaseFunctions.instanceFor(region: 'us-central1')
        .httpsCallable(
          'interventoriaPlanes',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 120)),
        )
        .call({...input, 'empresaId': empresaId});
    return planMap(result.data);
  }

  static Future<Uint8List> leerArchivo(
    PlanData result, {
    PlanRequest? request,
  }) async {
    final builder = BytesBuilder(copy: false);
    if (result['exportId'] != null) {
      if (request == null) {
        throw StateError('Falta la conexión para descargar el paquete.');
      }
      for (var i = 0; i < (result['partes'] as num).toInt(); i++) {
        final parte = await request({
          'accion': 'exportParte',
          'planId': result['planId'],
          'exportId': result['exportId'],
          'parte': i,
        });
        builder.add(base64Decode(planText(parte, 'base64')));
      }
    } else {
      builder.add(base64Decode(planText(result, 'base64')));
    }
    return builder.takeBytes();
  }

  static Future<void> guardarArchivo(
    PlanData result, {
    PlanRequest? request,
  }) async {
    final bytes = await leerArchivo(result, request: request);
    final name = planText(result, 'nombre');
    final dot = name.lastIndexOf('.');
    await FileSaver.instance.saveFile(
      name: dot < 0 ? name : name.substring(0, dot),
      fileExtension: dot < 0 ? '' : name.substring(dot + 1),
      bytes: bytes,
      mimeType: MimeType.other,
    );
  }
}
