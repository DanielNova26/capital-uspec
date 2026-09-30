// Maestros por módulo (29 sep 2026): Admin › Maestros por módulo.
//
// Cada módulo crea y edita sus maestros operativos en su propia empresa, sin
// saber que existen las demás. Admin mantiene configuraciones y los copia a otras
// empresas con la función `adminSincronizarMaestros`
// (functions/src/maestros.ts): solo agrega lo que el destino no tiene, por
// código o nombre, y nunca cambia lo que ya existe.
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

/// Paneles de configuración que viven en Admin (no en el módulo).
enum PanelAdminModulo { compras, correo, tokensDian, whatsapp }

class MaestroInfo {
  const MaestroInfo(this.id, this.nombre);

  /// La colección, igual que en el servidor.
  final String id;
  final String nombre;
}

class ModuloMaestrosInfo {
  const ModuloMaestrosInfo({
    required this.id,
    required this.nombre,
    required this.icono,
    required this.color,
    this.maestros = const [],
    this.panel,
  });

  /// El mismo id del catálogo del servidor y de Limpieza.
  final String id;
  final String nombre;
  final IconData icono;
  final Color color;

  /// Lo que se puede copiar a otras empresas. Vacío: solo configuración
  /// propia de la empresa (cuentas, credenciales).
  final List<MaestroInfo> maestros;
  final PanelAdminModulo? panel;

  bool get sincroniza => maestros.isNotEmpty;
}

const kModulosMaestros = <ModuloMaestrosInfo>[
  ModuloMaestrosInfo(
    id: 'compras',
    nombre: 'Compras',
    icono: Icons.shopping_bag_outlined,
    color: Color(0xFFB45309),
    panel: PanelAdminModulo.compras,
    maestros: [
      MaestroInfo('TBL_COMPRAS_CONFIG', 'Configuración'),
      MaestroInfo('TBL_COMPRAS_GRUPOS', 'Grupos'),
      MaestroInfo('TBL_COMPRAS_BODEGAS', 'Bodegas'),
      MaestroInfo('TBL_COMPRAS_MARCAS', 'Marcas'),
      MaestroInfo('TBL_COMPRAS_PROVEEDORES', 'Proveedores'),
      MaestroInfo('TBL_COMPRAS_PRODUCTOS', 'Productos'),
      MaestroInfo('TBL_COMPRAS_FICHAS_TECNICAS', 'Fichas técnicas'),
      MaestroInfo('TBL_COMPRAS_REQ_DOCUMENTOS', 'Requisitos documentales'),
    ],
  ),
  ModuloMaestrosInfo(
    id: 'interventoria',
    nombre: 'Interventoría',
    icono: Icons.fact_check_outlined,
    color: Color(0xFFDC2626),
    maestros: [
      MaestroInfo(
        'TBL_INTERVENTORIA_CONFIG',
        'Configuración y reglas de subsanación',
      ),
    ],
  ),
  ModuloMaestrosInfo(
    id: 'visitas',
    nombre: 'Visitas',
    icono: Icons.place_outlined,
    color: Color(0xFF9D174D),
    maestros: [
      MaestroInfo('TBL_VISITAS_FORMATOS', 'Formatos'),
      MaestroInfo('TBL_VISITAS_UBICACIONES', 'Ubicaciones de establecimientos'),
    ],
  ),
  ModuloMaestrosInfo(
    id: 'facturacion',
    nombre: 'Facturación',
    icono: Icons.receipt_long_outlined,
    color: Color(0xFF0F766E),
    maestros: [
      MaestroInfo('TBL_FAC_OBLIGACIONES', 'Obligaciones'),
      MaestroInfo(
        'TBL_FAC_ESTABLECIMIENTOS',
        'Documentos que no aplican por establecimiento',
      ),
    ],
  ),
  ModuloMaestrosInfo(
    id: 'rutas',
    nombre: 'Rutas',
    icono: Icons.local_shipping_outlined,
    color: Color(0xFF4F46E5),
    maestros: [
      MaestroInfo('TBL_RUTAS_CONFIG', 'Configuración'),
      MaestroInfo('TBL_RUTAS_MOV_CONFIG', 'Configuración de movilidad'),
      MaestroInfo('TBL_RUTAS_ESTABLECIMIENTOS', 'Establecimientos'),
      MaestroInfo('TBL_RUTAS', 'Rutas'),
      MaestroInfo('TBL_RUTAS_PLACAS', 'Placas'),
      MaestroInfo('TBL_RUTAS_MOV_HORARIOS', 'Horarios de medición'),
    ],
  ),
  ModuloMaestrosInfo(
    id: 'nutricion',
    nombre: 'Nutrición',
    icono: Icons.restaurant_outlined,
    color: Color(0xFF15803D),
    maestros: [
      MaestroInfo('TBL_INGREDIENTES', 'Ingredientes'),
      MaestroInfo('TBL_PATOLOGIAS', 'Patologías'),
      MaestroInfo('TBL_DIETAS', 'Dietas'),
      MaestroInfo('TBL_PLANTILLAS_MENUS', 'Plantillas de menú'),
      MaestroInfo('TBL_MENUS', 'Menús'),
    ],
  ),
  ModuloMaestrosInfo(
    id: 'gestion_documental',
    nombre: 'Correspondencia',
    icono: Icons.markunread_mailbox_outlined,
    color: Color(0xFF0D9488),
    maestros: [MaestroInfo('TBL_GD_TIPOS_DOCUMENTALES', 'Tipos documentales')],
  ),
  ModuloMaestrosInfo(
    id: 'bibliotecadocumental',
    nombre: 'Biblioteca documental',
    icono: Icons.local_library_outlined,
    color: Color(0xFF2563A6),
    maestros: [MaestroInfo('TBL_DOCUMENTOS', 'Documentos (versión vigente)')],
  ),
  ModuloMaestrosInfo(
    id: 'talento_humano',
    nombre: 'Talento Humano',
    icono: Icons.groups_outlined,
    color: Color(0xFF4F46E5),
    maestros: [
      MaestroInfo('TBL_TH_PLANTILLAS_DOCUMENTOS', 'Plantillas de documentos'),
      MaestroInfo('TBL_ZEUS_CONFIG', 'Valores por defecto de Zeus'),
    ],
  ),
  ModuloMaestrosInfo(
    id: 'correo',
    nombre: 'Correo',
    icono: Icons.alternate_email,
    color: Color(0xFF0369A1),
    panel: PanelAdminModulo.correo,
  ),
  ModuloMaestrosInfo(
    id: 'tokens_dian',
    nombre: 'Tokens DIAN',
    icono: Icons.vpn_key_outlined,
    color: Color(0xFF475569),
    panel: PanelAdminModulo.tokensDian,
  ),
  ModuloMaestrosInfo(
    id: 'whatsapp',
    nombre: 'WhatsApp',
    icono: Icons.chat_outlined,
    color: Color(0xFF16A34A),
    panel: PanelAdminModulo.whatsapp,
  ),
];

ModuloMaestrosInfo moduloMaestrosPorId(String id) => kModulosMaestros
    .firstWhere((m) => m.id == id, orElse: () => kModulosMaestros.first);

int _entero(Object? v) => v is num ? v.toInt() : 0;

class ResultadoMaestro {
  const ResultadoMaestro({
    required this.coleccion,
    required this.nombre,
    required this.esConfig,
    this.nuevos = 0,
    this.existentes = 0,
    this.sinClave = 0,
    this.campos = 0,
    this.ejemplos = const [],
    this.creados = 0,
    this.fallidos = 0,
  });

  final String coleccion;
  final String nombre;
  final bool esConfig;

  /// Registros que el destino no tiene y se crearían.
  final int nuevos;

  /// Registros que el destino ya tiene (se conservan como están).
  final int existentes;

  /// Registros sin código ni nombre: no se pueden comparar y no se copian.
  final int sinClave;

  /// Configuración: campos vacíos en el destino que se completarían.
  final int campos;
  final List<String> ejemplos;
  final int creados;
  final int fallidos;

  int get porCopiar => esConfig ? campos : nuevos;

  /// "12 nuevos · 30 ya estaban" o "3 campos por completar".
  String resumen({bool ejecutado = false}) {
    if (esConfig) {
      if (campos == 0) return 'Nada que completar';
      return ejecutado
          ? '$creados de $campos campos completados'
          : '$campos ${campos == 1 ? 'campo' : 'campos'} por completar';
    }
    final partes = <String>[
      ejecutado
          ? '$creados ${creados == 1 ? 'creado' : 'creados'}'
          : '$nuevos ${nuevos == 1 ? 'nuevo' : 'nuevos'}',
      if (existentes > 0) '$existentes ya estaban',
      if (sinClave > 0) '$sinClave sin código ni nombre',
      if (fallidos > 0) '$fallidos no se pudieron crear',
    ];
    return partes.join(' · ');
  }

  factory ResultadoMaestro.fromMap(Map<String, dynamic> d) => ResultadoMaestro(
    coleccion: (d['coleccion'] ?? '').toString(),
    nombre: (d['nombre'] ?? '').toString(),
    esConfig: d['tipo'] == 'config',
    nuevos: _entero(d['nuevos']),
    existentes: _entero(d['existentes']),
    sinClave: _entero(d['sinClave']),
    campos: _entero(d['campos']),
    ejemplos: [for (final e in (d['ejemplos'] as List?) ?? const []) '$e'],
    creados: _entero(d['creados']),
    fallidos: _entero(d['fallidos']),
  );
}

class ResultadoDestino {
  const ResultadoDestino({
    required this.empresaId,
    required this.nombre,
    required this.maestros,
    this.sinEquivalente = const [],
    this.archivosSinCopiar = 0,
  });

  final String empresaId;
  final String nombre;
  final List<ResultadoMaestro> maestros;

  /// Áreas, cargos, centros o maestros que el destino no tiene y que lo
  /// copiado nombra ("Cargo: Chef").
  final List<String> sinEquivalente;
  final int archivosSinCopiar;

  int get porCopiar => maestros.fold(0, (s, m) => s + m.porCopiar);
  int get creados => maestros.fold(0, (s, m) => s + m.creados);
  int get fallidos => maestros.fold(0, (s, m) => s + m.fallidos);

  factory ResultadoDestino.fromMap(Map<String, dynamic> d) => ResultadoDestino(
    empresaId: (d['empresaId'] ?? '').toString(),
    nombre: (d['nombre'] ?? d['empresaId'] ?? '').toString(),
    maestros: [
      for (final m in (d['maestros'] as List?) ?? const [])
        ResultadoMaestro.fromMap(Map<String, dynamic>.from(m as Map)),
    ],
    sinEquivalente: [
      for (final s in (d['sinEquivalente'] as List?) ?? const []) '$s',
    ],
    archivosSinCopiar: _entero(d['archivosSinCopiar']),
  );
}

class VistaSincronizacion {
  const VistaSincronizacion({
    required this.modulo,
    required this.destinos,
    this.ejecutado = false,
  });

  final String modulo;
  final List<ResultadoDestino> destinos;
  final bool ejecutado;

  int get porCopiar => destinos.fold(0, (s, d) => s + d.porCopiar);
  int get creados => destinos.fold(0, (s, d) => s + d.creados);
  int get fallidos => destinos.fold(0, (s, d) => s + d.fallidos);

  factory VistaSincronizacion.fromMap(Map<String, dynamic> d) =>
      VistaSincronizacion(
        modulo: (d['modulo'] ?? '').toString(),
        ejecutado: d['ejecutado'] == true,
        destinos: [
          for (final r in (d['destinos'] as List?) ?? const [])
            ResultadoDestino.fromMap(Map<String, dynamic>.from(r as Map)),
        ],
      );
}

class MaestrosSyncService {
  MaestrosSyncService({FirebaseFunctions? functions})
    : _functions =
          functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');

  final FirebaseFunctions _functions;

  Future<VistaSincronizacion> _llamar({
    required String empresaId,
    required String modulo,
    required List<String> destinos,
    required List<String> maestros,
    required bool ejecutar,
  }) async {
    final result = await _functions
        .httpsCallable(
          'adminSincronizarMaestros',
          options: HttpsCallableOptions(timeout: const Duration(minutes: 9)),
        )
        .call({
          'empresaId': empresaId,
          'modulo': modulo,
          'destinos': destinos,
          'maestros': maestros,
          'ejecutar': ejecutar,
        });
    return VistaSincronizacion.fromMap(
      Map<String, dynamic>.from(result.data as Map),
    );
  }

  /// Cuenta lo que se copiaría a cada empresa, sin escribir nada.
  Future<VistaSincronizacion> previsualizar({
    required String empresaId,
    required String modulo,
    required List<String> destinos,
    required List<String> maestros,
  }) => _llamar(
    empresaId: empresaId,
    modulo: modulo,
    destinos: destinos,
    maestros: maestros,
    ejecutar: false,
  );

  /// Crea en cada destino lo que le falta. Nunca cambia lo que ya existe.
  Future<VistaSincronizacion> copiar({
    required String empresaId,
    required String modulo,
    required List<String> destinos,
    required List<String> maestros,
  }) => _llamar(
    empresaId: empresaId,
    modulo: modulo,
    destinos: destinos,
    maestros: maestros,
    ejecutar: true,
  );
}
