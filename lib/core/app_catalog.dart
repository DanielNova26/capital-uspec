// lib/core/app_catalog.dart
//
// Catálogo único de módulos de la plataforma en lenguaje de negocio.
//
// Existe para que Admin y Talento Humano hablen del mismo conjunto de módulos
// sin que cada pantalla mantenga su propia lista. Admin sigue siendo quien
// configura los roles internos de cada módulo (rol de Compras, de
// Interventoría, etapa de firma de Planillas, etc.); este catálogo solo
// describe QUÉ es cada módulo y para qué le sirve a la persona.
//
// Los appId son los IDs canónicos que viven en `TBL_USUARIOS.apps` y en
// `TBL_APPS.appId`. Se escriben literales a propósito: este archivo es núcleo
// y no debe importar pantallas de los módulos para leer sus constantes.

import 'package:flutter/material.dart';

/// Agrupación con la que se le presenta el catálogo a alguien que no es
/// técnico (Talento Humano). No tiene efecto sobre los permisos.
enum AppCatalogGroup {
  /// Lo que usa casi cualquier colaborador en su día a día.
  diaADia,

  /// Módulos de un área específica (Compras, Nutrición, Rutas…).
  areasOperativas,

  /// Herramientas de gestión y control interno.
  gestion,

  /// Configuración de la plataforma. No lo asigna Talento Humano.
  administracion,
}

extension AppCatalogGroupLabel on AppCatalogGroup {
  String get label => switch (this) {
    AppCatalogGroup.diaADia => 'Día a día',
    AppCatalogGroup.areasOperativas => 'Áreas operativas',
    AppCatalogGroup.gestion => 'Gestión y control',
    AppCatalogGroup.administracion => 'Administración de la plataforma',
  };
}

class AppCatalogEntry {
  /// ID canónico del módulo (el que se guarda en `apps`).
  final String appId;

  /// Nombre corto, el mismo que ve el usuario en la pantalla de inicio.
  final String nombre;

  /// Para qué le sirve a la persona, sin jerga técnica.
  final String paraQueSirve;

  final AppCatalogGroup grupo;
  final IconData icono;
  final Color color;

  /// Módulos que Talento Humano no debe otorgar por su cuenta porque dan
  /// control sobre la plataforma o sobre datos sensibles de terceros.
  /// Siguen estando disponibles en Admin.
  final bool soloAdmin;

  /// Nota que se muestra en Talento Humano cuando, además del acceso, Admin
  /// debe completar una configuración adicional (rol interno del módulo).
  final String notaRolInterno;

  const AppCatalogEntry({
    required this.appId,
    required this.nombre,
    required this.paraQueSirve,
    required this.grupo,
    required this.icono,
    required this.color,
    this.soloAdmin = false,
    this.notaRolInterno = '',
  });
}

/// Módulos de la plataforma, en el orden en que conviene mostrarlos.
const List<AppCatalogEntry> kAppCatalog = [
  AppCatalogEntry(
    appId: 'tareasdashboard',
    nombre: 'Tareas',
    paraQueSirve:
        'Recibir tareas de su jefe, reportar avances y novedades, y ver sus '
        'pendientes del día.',
    grupo: AppCatalogGroup.diaADia,
    icono: Icons.task_alt_rounded,
    color: Color(0xFF2563EB),
  ),
  AppCatalogEntry(
    appId: 'comprasdashboard',
    nombre: 'Compras',
    paraQueSirve:
        'Solicitar productos, manejar proveedores y registrar la recepción de '
        'mercancía.',
    grupo: AppCatalogGroup.areasOperativas,
    icono: Icons.shopping_bag_rounded,
    color: Color(0xFF2563EB),
    notaRolInterno: 'Admin define si entra como Compras, Bodega o Consultas.',
  ),
  AppCatalogEntry(
    appId: 'nutriciondashboard',
    nombre: 'Nutrición',
    paraQueSirve: 'Minutas, citas y seguimiento nutricional.',
    grupo: AppCatalogGroup.areasOperativas,
    icono: Icons.restaurant_menu_rounded,
    color: Color(0xFFEA580C),
  ),
  AppCatalogEntry(
    appId: 'rutasdashboard',
    nombre: 'Rutas',
    paraQueSirve:
        'Programación de rutas, asignación de conductores y evidencia de las '
        'entregas.',
    grupo: AppCatalogGroup.areasOperativas,
    icono: Icons.local_shipping_rounded,
    color: Color(0xFF15803D),
    notaRolInterno: 'Admin define si es conductor, coordinador o consulta.',
  ),
  AppCatalogEntry(
    appId: 'interventoriadashboard',
    nombre: 'Interventoría',
    paraQueSirve: 'Visitas, hallazgos, evidencias y actas de interventoría.',
    grupo: AppCatalogGroup.areasOperativas,
    icono: Icons.document_scanner_rounded,
    color: Color(0xFF0F766E),
    notaRolInterno: 'Admin define el rol dentro de Interventoría.',
  ),
  AppCatalogEntry(
    appId: 'facturaciondashboard',
    nombre: 'Facturación',
    paraQueSirve: 'Facturación por establecimiento y consolidados de cobro.',
    grupo: AppCatalogGroup.areasOperativas,
    icono: Icons.receipt_long_rounded,
    color: Color(0xFF0369A1),
    notaRolInterno:
        'Admin define el rol y, si aplica, el establecimiento asignado.',
  ),
  AppCatalogEntry(
    appId: 'correodashboard',
    nombre: 'Correo y Correspondencia',
    paraQueSirve:
        'Radicar la correspondencia que entra y sale, y hacerle seguimiento.',
    grupo: AppCatalogGroup.gestion,
    icono: Icons.mark_email_unread_rounded,
    color: Color(0xFF0F766E),
    notaRolInterno:
        'Sin rol asignado la persona entra como Operador. El rol Clasificador '
        'lo asigna Admin.',
  ),
  AppCatalogEntry(
    appId: 'gestiondocumentaldashboard',
    nombre: 'Gestión de Correspondencia',
    paraQueSirve:
        'Biblioteca documental: redactar, revisar, aprobar y firmar documentos '
        'controlados.',
    grupo: AppCatalogGroup.gestion,
    icono: Icons.auto_stories_rounded,
    color: Color(0xFF0D9488),
    notaRolInterno:
        'Admin define si es redactor, revisor, aprobador o firmante.',
  ),
  AppCatalogEntry(
    appId: 'planillaspagodashboard',
    nombre: 'Planillas de Pago',
    paraQueSirve: 'Elaborar, revisar y firmar planillas de pago.',
    grupo: AppCatalogGroup.gestion,
    icono: Icons.request_quote_rounded,
    color: Color(0xFFB45309),
    notaRolInterno: 'Admin define la etapa de firma que le corresponde.',
  ),
  AppCatalogEntry(
    appId: 'talentohumanodashboard',
    nombre: 'Talento Humano',
    paraQueSirve:
        'Hojas de vida, estructura de la empresa, contrataciones y procesos '
        'del personal.',
    grupo: AppCatalogGroup.gestion,
    icono: Icons.groups_rounded,
    color: Color(0xFF4F46E5),
  ),
  AppCatalogEntry(
    appId: 'gerenciadashboard',
    nombre: 'Gerencia',
    paraQueSirve: 'Indicadores y seguimiento gerencial de la operación.',
    grupo: AppCatalogGroup.gestion,
    icono: Icons.query_stats_rounded,
    color: Color(0xFF7C3AED),
  ),
  AppCatalogEntry(
    appId: 'tokensdiandashboard',
    nombre: 'Tokens DIAN',
    paraQueSirve:
        'Consulta de tokens y correos de facturación electrónica de la DIAN.',
    grupo: AppCatalogGroup.administracion,
    icono: Icons.vpn_key_rounded,
    color: Color(0xFF0E7490),
    soloAdmin: true,
  ),
  AppCatalogEntry(
    appId: 'admindashboard',
    nombre: 'Administración',
    paraQueSirve:
        'Configuración de la plataforma, empresas, usuarios y permisos.',
    grupo: AppCatalogGroup.administracion,
    icono: Icons.admin_panel_settings_rounded,
    color: Color(0xFF475569),
    soloAdmin: true,
  ),
];

/// Servicios transversales que NO son módulos y por lo tanto no se asignan:
/// todo el personal los tiene por definición. Se listan para poder explicarlo
/// en pantalla y para que ninguna pantalla los trate como app opcional.
class AlwaysOnService {
  final String nombre;
  final String paraQueSirve;
  final IconData icono;

  const AlwaysOnService({
    required this.nombre,
    required this.paraQueSirve,
    required this.icono,
  });
}

const List<AlwaysOnService> kAlwaysOnServices = [
  AlwaysOnService(
    nombre: 'Notificaciones',
    paraQueSirve:
        'Avisos de la empresa, de Talento Humano y de los módulos que use.',
    icono: Icons.notifications_active_rounded,
  ),
  AlwaysOnService(
    nombre: 'Calendario',
    paraQueSirve: 'Agenda personal con sus citas y compromisos.',
    icono: Icons.calendar_month_rounded,
  ),
];

AppCatalogEntry? appCatalogEntryFor(String? appId) {
  final target = (appId ?? '').trim().toLowerCase();
  if (target.isEmpty) return null;
  for (final entry in kAppCatalog) {
    if (entry.appId == target) return entry;
  }
  return null;
}

/// Catálogo que Talento Humano puede administrar (sin los módulos de Admin).
List<AppCatalogEntry> appCatalogParaTalentoHumano() =>
    kAppCatalog.where((entry) => !entry.soloAdmin).toList();
