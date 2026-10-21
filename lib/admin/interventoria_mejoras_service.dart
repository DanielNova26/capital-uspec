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

/// Propuesta de aprobador para un hallazgo, con el mismo resolvedor del
/// maestro que usan la sugerencia y la asignación
/// ([InterventoriaService.resolucionAprobador]). Un empate no propone a
/// nadie: queda como pendiente con las personas empatadas en el motivo.
Map<String, dynamic> propuestaAprobadorMejoras(
  String hallazgoId,
  ResolucionAprobadorMaestro resolucion,
) => {
  'hallazgoId': hallazgoId,
  'candidatoId': resolucion.persona?.id ?? '',
  'cargoRequerido': resolucion.persona == null ? '' : resolucion.cargoMatriz,
  'motivoMaestro': resolucion.motivo,
};

class InterventoriaMejorasService {
  /// Revisa (sin escribir) o aplica los hallazgos de [revision].
  ///
  /// Al aplicar, [revision] trae solo los cambios que Desarrollo dejó
  /// marcados, con la huella que devolvió el servidor al revisarlos.
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
        items.add(
          propuestaAprobadorMejoras(
            doc.id,
            servicio.resolucionAprobador(h, usuarios, reglas: reglas),
          ),
        );
      }
    }
    final motivos = {
      for (final r in items) r['hallazgoId']: r['motivoMaestro'] ?? '',
    };
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
              'candidatoId': r['candidatoId'] ?? '',
              'cargoRequerido': r['cargoRequerido'] ?? '',
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
        (data['resultados'] as List).map((r) {
          final fila = Map<String, dynamic>.from(r as Map);
          fila['motivoMaestro'] = motivos[fila['hallazgoId']] ?? '';
          return fila;
        }),
      );
      progreso(resultado.length, items.length);
    }
    return resultado;
  }
}
