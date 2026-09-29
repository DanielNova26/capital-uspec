// Limpieza por módulo (29 sep 2026): Admin › Limpieza. Cada módulo tiene
// dos herramientas según lo que necesite:
// - "Cerrar sin borrar": finaliza tareas abiertas y da por leídas sus
//   notificaciones (AdminModuleCloseoutService), donde el módulo crea tareas
//   que se cierran sin dejar su origen a medias.
// - "Borrar datos de prueba": la función `adminLimpiezaModulo` borra los
//   registros del módulo en la empresa activa, por periodo, con vista previa.
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

class ModuloLimpiezaInfo {
  const ModuloLimpiezaInfo({
    required this.id,
    required this.nombre,
    required this.icono,
    required this.color,
    required this.descripcion,
    this.cierre = false,
    this.maestros = false,
  });

  /// El mismo id del catálogo del servidor (functions/src/limpieza.ts).
  final String id;
  final String nombre;
  final IconData icono;
  final Color color;
  final String descripcion;

  /// Tiene "Cerrar sin borrar".
  final bool cierre;

  /// Tiene maestros o configuración que se pueden incluir en el borrado.
  final bool maestros;
}

const kModulosLimpieza = <ModuloLimpiezaInfo>[
  ModuloLimpiezaInfo(
    id: 'tareas',
    nombre: 'Tareas y notificaciones',
    icono: Icons.task_alt_rounded,
    color: Color(0xFF2563EB),
    descripcion:
        'Tareas creadas a mano (no por un módulo) y notificaciones '
        'acumuladas.',
    cierre: true,
  ),
  ModuloLimpiezaInfo(
    id: 'interventoria',
    nombre: 'Interventoría',
    icono: Icons.fact_check_outlined,
    color: Color(0xFFDC2626),
    descripcion: 'Actas, hallazgos, solicitudes de eliminación y sus tareas.',
    cierre: true,
  ),
  ModuloLimpiezaInfo(
    id: 'visitas',
    nombre: 'Visitas',
    icono: Icons.place_outlined,
    color: Color(0xFF9D174D),
    descripcion:
        'Visitas y sus tareas. Maestros: formatos, grupos y '
        'ubicaciones.',
    maestros: true,
  ),
  ModuloLimpiezaInfo(
    id: 'facturacion',
    nombre: 'Facturación',
    icono: Icons.receipt_long_outlined,
    color: Color(0xFF0F766E),
    descripcion:
        'Revisiones, observaciones, autorizaciones y sus tareas. '
        'Maestros: obligaciones y establecimientos.',
    cierre: true,
    maestros: true,
  ),
  ModuloLimpiezaInfo(
    id: 'compras',
    nombre: 'Compras',
    icono: Icons.shopping_bag_outlined,
    color: Color(0xFFB45309),
    descripcion:
        'Recepciones, aprobaciones, abastecimiento y sus tareas. '
        'Maestros: productos, proveedores, marcas, fichas, bodegas y grupos.',
    maestros: true,
  ),
  ModuloLimpiezaInfo(
    id: 'rutas',
    nombre: 'Rutas',
    icono: Icons.local_shipping_outlined,
    color: Color(0xFF4F46E5),
    descripcion:
        'Asignaciones, evidencias, recorridos y ubicaciones. '
        'Maestros: rutas, establecimientos, placas y horarios.',
    maestros: true,
  ),
  ModuloLimpiezaInfo(
    id: 'nutricion',
    nombre: 'Nutrición',
    icono: Icons.restaurant_outlined,
    color: Color(0xFF15803D),
    descripcion:
        'Pacientes con su historial, citas, valoraciones y demás '
        'registros. Maestros: dietas, menús, ingredientes y patologías.',
    maestros: true,
  ),
  ModuloLimpiezaInfo(
    id: 'gestion_documental',
    nombre: 'Correspondencia',
    icono: Icons.markunread_mailbox_outlined,
    color: Color(0xFF0D9488),
    descripcion:
        'Expedientes, sus eventos y tareas. Maestros: tipos '
        'documentales y consecutivos de radicado.',
    maestros: true,
  ),
  ModuloLimpiezaInfo(
    id: 'correo',
    nombre: 'Correo',
    icono: Icons.alternate_email,
    color: Color(0xFF0369A1),
    descripcion: 'Mensajes, ejecuciones y alertas. Maestros: reglas.',
    maestros: true,
  ),
  ModuloLimpiezaInfo(
    id: 'bibliotecadocumental',
    nombre: 'Biblioteca documental',
    icono: Icons.local_library_outlined,
    color: Color(0xFF2563A6),
    descripcion: 'Documentos, su flujo y sus versiones.',
  ),
  ModuloLimpiezaInfo(
    id: 'planillas_pago',
    nombre: 'Planillas de pago',
    icono: Icons.request_quote_outlined,
    color: Color(0xFFB45309),
    descripcion:
        'Planillas, lotes, flujo de firmas y sus tareas. '
        'Maestros: beneficiarios y sus cuentas.',
    maestros: true,
  ),
  ModuloLimpiezaInfo(
    id: 'talento_humano',
    nombre: 'Talento Humano',
    icono: Icons.groups_outlined,
    color: Color(0xFF4F46E5),
    descripcion:
        'Llamados de atención, requerimientos de personal, '
        'documentos de finalización e historial. No borra personas.',
    maestros: true,
  ),
  ModuloLimpiezaInfo(
    id: 'tokens_dian',
    nombre: 'Tokens DIAN',
    icono: Icons.vpn_key_outlined,
    color: Color(0xFF475569),
    descripcion: 'Registro de accesos a los tokens. Maestro: los tokens.',
    maestros: true,
  ),
  ModuloLimpiezaInfo(
    id: 'whatsapp',
    nombre: 'WhatsApp',
    icono: Icons.chat_outlined,
    color: Color(0xFF16A34A),
    descripcion: 'Eventos y auditoría de envíos.',
  ),
];

ModuloLimpiezaInfo moduloLimpiezaPorId(String id) => kModulosLimpieza
    .firstWhere((m) => m.id == id, orElse: () => kModulosLimpieza.first);

enum ModoPeriodo {
  todo('Todo lo de esta empresa'),
  antes('Antes de una fecha'),
  desde('Desde una fecha'),
  entre('Entre dos fechas');

  const ModoPeriodo(this.etiqueta);
  final String etiqueta;
}

class PeriodoLimpieza {
  const PeriodoLimpieza(this.modo, {this.desde, this.hasta});

  final ModoPeriodo modo;
  final DateTime? desde;
  final DateTime? hasta;

  bool get completo => switch (modo) {
    ModoPeriodo.todo => true,
    ModoPeriodo.antes || ModoPeriodo.desde => desde != null,
    ModoPeriodo.entre =>
      desde != null && hasta != null && !hasta!.isBefore(desde!),
  };

  static int? _dia(DateTime? d) => d == null
      ? null
      : DateTime(d.year, d.month, d.day).millisecondsSinceEpoch;

  /// Días completos: "hasta" incluye ese día (el servidor suma 24 h).
  Map<String, dynamic> toMap() => {
    'modo': modo.name,
    'desde': ?_dia(desde),
    'hasta': ?_dia(hasta),
  };

  String descripcion(String Function(DateTime) fecha) => switch (modo) {
    ModoPeriodo.todo => 'todo',
    ModoPeriodo.antes => 'antes del ${fecha(desde!)}',
    ModoPeriodo.desde => 'desde el ${fecha(desde!)}',
    ModoPeriodo.entre => 'del ${fecha(desde!)} al ${fecha(hasta!)}',
  };
}

class ConteoColeccion {
  const ConteoColeccion({
    required this.coleccion,
    required this.nombre,
    required this.maestro,
    required this.total,
    required this.sinFecha,
  });

  final String coleccion;
  final String nombre;
  final bool maestro;
  final int total;

  /// Registros sin fecha: con un periodo no entran (con "todo" sí).
  final int sinFecha;

  factory ConteoColeccion.fromMap(Map<String, dynamic> data) => ConteoColeccion(
    coleccion: (data['coleccion'] ?? '').toString(),
    nombre: (data['nombre'] ?? '').toString(),
    maestro: data['maestro'] == true,
    total: (data['total'] as num?)?.toInt() ?? 0,
    sinFecha: (data['sinFecha'] as num?)?.toInt() ?? 0,
  );
}

class VistaLimpieza {
  const VistaLimpieza({
    required this.colecciones,
    required this.tareas,
    required this.tareasSinFecha,
    required this.notificaciones,
    required this.total,
    this.ejecutado = false,
    this.fallidos = 0,
  });

  final List<ConteoColeccion> colecciones;
  final int tareas;
  final int tareasSinFecha;
  final int notificaciones;

  /// Documentos que se borran (incluye historiales que cuelgan de pacientes).
  final int total;
  final bool ejecutado;
  final int fallidos;

  int get sinFecha =>
      colecciones.fold(tareasSinFecha, (suma, c) => suma + c.sinFecha);

  factory VistaLimpieza.fromMap(Map<String, dynamic> data) => VistaLimpieza(
    colecciones: ((data['colecciones'] as List?) ?? const [])
        .map(
          (c) => ConteoColeccion.fromMap(Map<String, dynamic>.from(c as Map)),
        )
        .toList(),
    tareas: (data['tareas'] as num?)?.toInt() ?? 0,
    tareasSinFecha: (data['tareasSinFecha'] as num?)?.toInt() ?? 0,
    notificaciones: (data['notificaciones'] as num?)?.toInt() ?? 0,
    total: (data['total'] as num?)?.toInt() ?? 0,
    ejecutado: data['ejecutado'] == true,
    fallidos: (data['fallidos'] as num?)?.toInt() ?? 0,
  );
}

class ModuleCleanupService {
  ModuleCleanupService({FirebaseFunctions? functions})
    : _functions =
          functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');

  final FirebaseFunctions _functions;

  Future<VistaLimpieza> _llamar({
    required String empresaId,
    required String modulo,
    required PeriodoLimpieza periodo,
    required bool incluirMaestros,
    required bool ejecutar,
  }) async {
    final result = await _functions
        .httpsCallable(
          'adminLimpiezaModulo',
          options: HttpsCallableOptions(timeout: const Duration(minutes: 9)),
        )
        .call({
          'empresaId': empresaId,
          'modulo': modulo,
          'rango': periodo.toMap(),
          'incluirMaestros': incluirMaestros,
          'ejecutar': ejecutar,
          if (ejecutar) 'confirmacion': 'BORRAR',
        });
    return VistaLimpieza.fromMap(Map<String, dynamic>.from(result.data as Map));
  }

  /// Cuenta lo que se borraría, sin borrar nada.
  Future<VistaLimpieza> previsualizar({
    required String empresaId,
    required String modulo,
    required PeriodoLimpieza periodo,
    bool incluirMaestros = false,
  }) => _llamar(
    empresaId: empresaId,
    modulo: modulo,
    periodo: periodo,
    incluirMaestros: incluirMaestros,
    ejecutar: false,
  );

  Future<VistaLimpieza> borrar({
    required String empresaId,
    required String modulo,
    required PeriodoLimpieza periodo,
    bool incluirMaestros = false,
  }) => _llamar(
    empresaId: empresaId,
    modulo: modulo,
    periodo: periodo,
    incluirMaestros: incluirMaestros,
    ejecutar: true,
  );
}
