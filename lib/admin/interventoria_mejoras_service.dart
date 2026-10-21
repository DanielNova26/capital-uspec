import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../interventoria/interventoria_models.dart';
import '../interventoria/interventoria_service.dart';

typedef EjecutarMejorasInterventoria =
    Future<List<Map<String, dynamic>>> Function({
      required String empresaId,
      required bool aplicar,
      required List<Map<String, dynamic>> revision,
      required void Function(int hechos, int total) progreso,
      required bool Function() vigente,
    });

class InterventoriaMejorasService {
  Future<List<Map<String, dynamic>>> ejecutar({
    required String empresaId,
    required bool aplicar,
    required List<Map<String, dynamic>> revision,
    required void Function(int hechos, int total) progreso,
    required bool Function() vigente,
  }) async {
    final items = <Map<String, dynamic>>[];
    if (aplicar) {
      items.addAll(
        revision.where((r) => r['cambia'] == true && r['error'] == null),
      );
    } else {
      final servicio = InterventoriaService();
      final reglas = await servicio.reglasSubsanacion(empresaId);
      final usuarios = await servicio.listarUsuariosActivos(empresaId);
      final hallazgos = await FirebaseFirestore.instance
          .collection('TBL_INTERVENTORIA_HALLAZGOS')
          .where('empresaId', isEqualTo: empresaId)
          .get();
      for (final doc in hallazgos.docs) {
        final h = InterventoriaHallazgo.fromMap(doc.id, doc.data());
        final candidato = servicio.sugerirAprobador(
          h,
          usuarios,
          reglas: reglas,
        );
        items.add({'hallazgoId': doc.id, 'candidatoId': candidato?.id ?? ''});
      }
    }
    final resultado = <Map<String, dynamic>>[];
    final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
        .httpsCallable(
          'interventoriaSincronizarMejoras',
          options: HttpsCallableOptions(timeout: const Duration(minutes: 2)),
        );
    for (var inicio = 0; inicio < items.length; inicio += 20) {
      if (!vigente()) return resultado;
      final lote = items
          .skip(inicio)
          .take(20)
          .map(
            (r) => {
              'hallazgoId': r['hallazgoId'],
              'candidatoId': r['candidatoId'],
              if (aplicar) 'huella': r['huella'],
            },
          )
          .toList();
      final res = await callable.call({
        'empresaId': empresaId,
        'modo': aplicar ? 'aplicar' : 'revisar',
        'items': lote,
      });
      final data = Map<String, dynamic>.from(res.data as Map);
      resultado.addAll(
        (data['resultados'] as List).map(
          (r) => Map<String, dynamic>.from(r as Map),
        ),
      );
      progreso(resultado.length, items.length);
    }
    return resultado;
  }
}
