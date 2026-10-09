// Maestro de notificaciones (9 oct 2026): catálogo de los tipos de aviso y
// los canales por los que sale cada uno. Espejo de
// `functions/src/notification_catalog.ts`; `test/core/notification_catalog_test.dart`
// falla si no coinciden. La configuración de cada empresa vive en
// `TBL_NOTIFICACIONES_CONFIG/{empresaId}` (`tipos.{clave}.{app|push|whatsapp}`).

enum CanalNotificacion { app, push, whatsapp }

class TipoNotificacion {
  const TipoNotificacion({
    required this.clave,
    required this.modulo,
    required this.etiqueta,
    this.critico = false,
    this.conWhatsapp = false,
  });

  final String clave;
  final String modulo;
  final String etiqueta;

  /// Aprobaciones y seguridad: campana y push no se pueden apagar.
  final bool critico;

  /// Tiene eventos de WhatsApp que este tipo gobierna (activo por defecto).
  final bool conWhatsapp;
}

const Map<String, String> kModulosNotificacion = {
  'tareas': 'Tareas',
  'planillas': 'Planillas de pago',
  'compras': 'Compras',
  'facturacion': 'Facturación',
  'visitas': 'Visitas',
  'rutas': 'Rutas',
  'interventoria': 'Interventoría',
  'gestion_documental': 'Gestión documental',
  'talento_humano': 'Talento Humano',
  'nutricion': 'Nutrición',
};

const List<TipoNotificacion> kCatalogoNotificaciones = [
  TipoNotificacion(
    clave: 'tareas_asignacion',
    modulo: 'tareas',
    etiqueta: 'Tarea asignada o reasignada',
  ),
  TipoNotificacion(
    clave: 'tareas_estado',
    modulo: 'tareas',
    etiqueta: 'Cambio de estado de tarea',
  ),
  TipoNotificacion(
    clave: 'tareas_aprobacion',
    modulo: 'tareas',
    etiqueta: 'Solicitud de finalización',
    critico: true,
  ),
  TipoNotificacion(
    clave: 'planillas_flujo',
    modulo: 'planillas',
    etiqueta: 'Flujo de planillas de pago',
    critico: true,
    conWhatsapp: true,
  ),
  TipoNotificacion(
    clave: 'planillas_resumen',
    modulo: 'planillas',
    etiqueta: 'Resumen diario de planillas',
  ),
  TipoNotificacion(
    clave: 'compras_calidad',
    modulo: 'compras',
    etiqueta: 'Recepciones y proveedores para Calidad',
    conWhatsapp: true,
  ),
  TipoNotificacion(
    clave: 'compras_vigencias',
    modulo: 'compras',
    etiqueta: 'Documentos por vencer',
  ),
  TipoNotificacion(
    clave: 'facturacion',
    modulo: 'facturacion',
    etiqueta: 'Facturación',
  ),
  TipoNotificacion(
    clave: 'visitas',
    modulo: 'visitas',
    etiqueta: 'Visitas',
  ),
  TipoNotificacion(
    clave: 'rutas',
    modulo: 'rutas',
    etiqueta: 'Rutas',
  ),
  TipoNotificacion(
    clave: 'interventoria',
    modulo: 'interventoria',
    etiqueta: 'Interventoría',
    conWhatsapp: true,
  ),
  TipoNotificacion(
    clave: 'gestion_documental',
    modulo: 'gestion_documental',
    etiqueta: 'Gestión documental',
  ),
  TipoNotificacion(
    clave: 'talento_humano',
    modulo: 'talento_humano',
    etiqueta: 'Plazos disciplinarios',
    critico: true,
  ),
  TipoNotificacion(
    clave: 'nutricion',
    modulo: 'nutricion',
    etiqueta: 'Citas de nutrición',
  ),
];

/// Canales activos de un tipo según los ajustes de la empresa
/// (`tipos.{clave}`). Lo no ajustado usa el valor por defecto y los críticos
/// no pueden apagar campana ni push. Igual que `canalesDe` del servidor.
Map<CanalNotificacion, bool> canalesDeTipo(
  TipoNotificacion tipo,
  Map<String, dynamic>? ajuste,
) {
  bool leer(CanalNotificacion c, bool defecto) {
    final v = ajuste?[c.name];
    return v is bool ? v : defecto;
  }

  final out = {
    CanalNotificacion.app: leer(CanalNotificacion.app, true),
    CanalNotificacion.push: leer(CanalNotificacion.push, true),
    CanalNotificacion.whatsapp: leer(
      CanalNotificacion.whatsapp,
      tipo.conWhatsapp,
    ),
  };
  if (tipo.critico) {
    out[CanalNotificacion.app] = true;
    out[CanalNotificacion.push] = true;
  }
  return out;
}
