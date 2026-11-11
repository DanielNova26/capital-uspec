import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';

import 'personnel_template_service.dart';

typedef VistaAltaPersonal = ({
  int fila,
  String cedula,
  String nombre,
  String area,
  String cargo,
});
typedef ErrorAltaPersonal = ({int fila, String mensaje});

class RevisionCargaPersonal {
  final List<VistaAltaPersonal> vistas;
  final List<ErrorAltaPersonal> errores;
  final int creados;

  const RevisionCargaPersonal({
    required this.vistas,
    required this.errores,
    required this.creados,
  });
}

class PersonnelImportService {
  PersonnelImportService({FirebaseFunctions? functions})
    : _functions =
          functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');

  final FirebaseFunctions _functions;

  Future<Uint8List> plantilla(String empresaId) async {
    final datos = await _llamar(empresaId, 'catalogo');
    return construirPlantillaPersonal(
      empresaId: empresaId,
      empresaNombre: datos['empresaNombre'] as String,
      limite: datos['limite'] as int,
      catalogos: {
        for (final campo in const [
          'tipo_documento',
          'area',
          'cargo',
          'centroCostos',
          'jefe',
          'estado',
        ])
          campo: List<String>.from(datos[campo] as List),
      },
    );
  }

  Future<RevisionCargaPersonal> revisar(
    String empresaId,
    ArchivoCargaPersonal archivo, {
    bool confirmar = false,
  }) async {
    final datos = await _llamar(empresaId, confirmar ? 'importar' : 'validar', {
      'empresaPlantilla': archivo.empresaId,
      'filas': archivo.filas,
    });
    return RevisionCargaPersonal(
      vistas: [
        for (final Map fila in datos['vistas'] as List)
          (
            fila: fila['fila'] as int,
            cedula: fila['cedula'] as String,
            nombre: fila['nombre'] as String,
            area: fila['area'] as String,
            cargo: fila['cargo'] as String,
          ),
      ],
      errores: [
        for (final Map fila in datos['errores'] as List)
          (fila: fila['fila'] as int, mensaje: fila['mensaje'] as String),
      ],
      creados: datos['creados'] as int,
    );
  }

  Future<Map<String, dynamic>> _llamar(
    String empresaId,
    String accion, [
    Map<String, Object> extra = const {},
  ]) async {
    final result = await _functions.httpsCallable('talentoCargarPersonal').call(
      {'empresaId': empresaId, 'accion': accion, ...extra},
    );
    return Map<String, dynamic>.from(result.data as Map);
  }
}
