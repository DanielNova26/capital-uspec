import 'facturacion_models.dart';

/// Niveles de Facturación que se pueden dar con un rol creado en Admin, del
/// menor al mayor. Son los tres que ya resuelve `resolveFacAccessMode`.
const facRoleLevelLabels = <String, String>{
  kRolFacVisor: 'Visor',
  kRolEstablecimiento: 'Establecimiento',
  kRolFacturacion: 'Gestión de Facturación',
};

String facLevelDescription(String level) => switch (level) {
  kRolFacVisor =>
    'Consulta el tablero y el histórico de Facturación sin cambiar nada.',
  kRolEstablecimiento =>
    'Carga los documentos de un solo establecimiento, el de su centro de '
        'costo, y responde sus observaciones. Sin centro de costo no entra.',
  kRolFacturacion =>
    'Gestiona el módulo: obligaciones, meses, revisión de documentos, '
        'observaciones y autorizaciones de todos los establecimientos.',
  _ => 'Sin rol de Facturación: consulta, como Visor.',
};
