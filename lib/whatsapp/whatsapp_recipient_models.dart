import 'package:cloud_firestore/cloud_firestore.dart';

/// Fuente histórica y única de listas de WhatsApp.
///
/// Se conserva el nombre de la colección para que las reglas de Correo y los
/// datos ya creados sigan funcionando sin migraciones destructivas.
const String kWhatsAppRecipientListsCollection = 'TBL_CORREO_LISTADOS';

/// Catálogo único de módulos que pueden compartir listas de WhatsApp.
///
/// Mantenerlo centralizado evita que un módulo habilitado en Administración
/// desaparezca del formulario de creación o edición de listas.
const List<String> kWhatsAppListModules = <String>[
  'correo',
  'compras',
  'planillas_pago',
  'interventoria',
  'facturacion',
];

List<String> normalizeWhatsAppListModules(Iterable<Object?> values) {
  final selected = values
      .map((value) => value?.toString().trim().toLowerCase() ?? '')
      .where(kWhatsAppListModules.contains)
      .toSet();
  return kWhatsAppListModules.where(selected.contains).toList(growable: false);
}

String whatsappModuleLabel(String moduleId) =>
    switch (moduleId.trim().toLowerCase()) {
      'correo' => 'Correo',
      'compras' => 'Compras',
      'planillas_pago' => 'Planillas de Pago',
      'interventoria' => 'Interventoría',
      'facturacion' => 'Facturación',
      final value => value,
    };

class WhatsAppDestinatario {
  const WhatsAppDestinatario({
    required this.nombre,
    required this.telefono,
    this.activo = true,
    this.personaId = '',
    this.origen = 'manual',
  });

  final String nombre;
  final String telefono;
  final bool activo;
  final String personaId;
  final String origen;

  bool get vinculadoAlDirectorio =>
      personaId.trim().isNotEmpty && origen == 'directorio';

  factory WhatsAppDestinatario.fromMap(dynamic value) {
    if (value is! Map) {
      return WhatsAppDestinatario(
        nombre: '',
        telefono: value?.toString() ?? '',
      );
    }
    return WhatsAppDestinatario(
      nombre: (value['nombre'] ?? '').toString(),
      telefono: (value['telefono'] ?? value['phone'] ?? '').toString(),
      activo: value['activo'] != false,
      personaId: (value['personaId'] ?? '').toString(),
      origen: (value['origen'] ?? 'manual').toString(),
    );
  }

  Map<String, dynamic> toMap() => {
    'nombre': nombre.trim(),
    'telefono': telefono.trim(),
    'activo': activo,
    'personaId': personaId.trim(),
    'origen': vinculadoAlDirectorio ? 'directorio' : 'manual',
  };
}

class WhatsAppListado {
  const WhatsAppListado({
    required this.id,
    required this.empresaId,
    required this.nombre,
    required this.destinatarios,
    this.activo = true,
    this.modulos = const [],
  });

  final String id;
  final String empresaId;
  final String nombre;
  final List<WhatsAppDestinatario> destinatarios;
  final bool activo;
  final List<String> modulos;

  factory WhatsAppListado.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    final recipients = data['destinatarios'] is List
        ? (data['destinatarios'] as List)
              .map(WhatsAppDestinatario.fromMap)
              .where((item) => item.telefono.trim().isNotEmpty)
              .toList()
        : const <WhatsAppDestinatario>[];
    return WhatsAppListado(
      id: document.id,
      empresaId: (data['empresaId'] ?? '').toString(),
      nombre: (data['nombre'] ?? 'Listado sin nombre').toString(),
      destinatarios: recipients,
      activo: data['activo'] != false,
      modulos: data['modulos'] is List
          ? normalizeWhatsAppListModules(data['modulos'] as List)
          : const [],
    );
  }

  int get destinatariosActivos =>
      destinatarios.where((item) => item.activo).length;

  /// Las listas históricas sin clasificación se conservan disponibles hasta
  /// que Administración las guarde con una asociación explícita.
  bool habilitadaPara(String modulo) =>
      modulos.isEmpty || modulos.contains(modulo.trim().toLowerCase());

  bool get pendienteClasificacion => modulos.isEmpty;
}
