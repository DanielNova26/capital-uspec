import 'gd_permisos.dart';

const correspondenceRoleLevelLabels = <String, String>{
  'visor': 'Visor',
  'operador': 'Operador',
  'clasificador': 'Clasificador y asignador',
  'administrador': 'Administrador del módulo',
};

String correspondenceLevelDescription(String level) {
  final role =
      GdRolCorrespondencia.desdeTexto(level) ?? GdRolCorrespondencia.visor;
  final permissions = GdPermisos(role);
  final actions = <String>[
    'Consultar tablero e histórico',
    if (permissions.puedeGestionarAsignado)
      'Trabajar expedientes asignados: responder, registrar avances y cerrar según responsabilidad',
    if (permissions.puedeClasificar)
      'Radicar, clasificar, asignar responsables y fechas límite',
    if (permissions.puedeAdministrarTipos)
      'Administrar tipos documentales y filtros',
    if (permissions.puedeCerrarCualquiera)
      'Cerrar cualquier expediente según sus validaciones',
  ];
  return '${actions.join('. ')}.';
}
