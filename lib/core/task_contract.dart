/// Contrato canónico de una tarea compartida por todos los módulos.
///
/// Mantiene los campos históricos que consumen las pantallas actuales y añade
/// metadatos explícitos de origen, aprobador y versión de esquema. Es una capa
/// pura para que pueda probarse sin Firebase.
class TaskContract {
  TaskContract._();

  static const int schemaVersion = 2;

  static const Set<String> statuses = {
    'pendiente',
    'en_progreso',
    'por_aprobar',
    'finalizado',
    'devuelta',
    'reasignado',
  };

  static const Set<String> priorities = {'baja', 'media', 'alta', 'urgente'};

  static String _text(dynamic value) => value?.toString().trim() ?? '';

  static String normalizeStatus(dynamic value) {
    final raw = _text(value).toLowerCase().replaceAll(' ', '_');
    switch (raw) {
      case 'finalizada':
      case 'completada':
      case 'aprobada':
        return 'finalizado';
      case 'pendiente_aprobacion':
        return 'por_aprobar';
      case 'retrasada':
      case 'retrasado':
        // Retraso es una condición calculada desde la fecha, no un estado
        // persistido del flujo.
        return 'en_progreso';
      default:
        return statuses.contains(raw) ? raw : 'en_progreso';
    }
  }

  static String normalizePriority(dynamic value) {
    final raw = _text(value).toLowerCase();
    return priorities.contains(raw) ? raw : 'media';
  }

  static String normalizeModuleId(dynamic value) {
    final raw = _text(
      value,
    ).toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '');
    const aliases = {
      'comprasdashboard': 'compras',
      'compras_bodega': 'compras',
      'interventoriadashboard': 'interventoria',
      'facturaciondashboard': 'facturacion',
      'correodashboard': 'correo',
      'gestiondocumentaldashboard': 'gestion_documental',
      'talentohumanodashboard': 'talento_humano',
      'mantenimientodashboard': 'mantenimiento',
      'vehiculosdashboard': 'vehiculos',
    };
    return aliases[raw] ?? (raw.isEmpty ? 'tareas' : raw);
  }

  /// Normaliza una tarea antes de crearla.
  ///
  /// Los campos críticos no pueden quedar vacíos ni ser sustituidos de forma
  /// accidental por metadatos de módulo. Los aliases se conservan para no
  /// romper documentos históricos ni pantallas existentes.
  static Map<String, dynamic> normalizeForCreate(
    Map<String, dynamic> draft, {
    String defaultSourceModule = 'tareas',
  }) {
    final data = Map<String, dynamic>.from(draft);
    final title = _text(data['titulo'] ?? data['title']);
    final empresaId = _text(data['empresaId'] ?? data['empresa_id']);
    final assignedId = _text(data['asignado_uid'] ?? data['assignedTo']);
    final creatorId = _text(data['creador_id'] ?? data['creatorId']);

    if (title.isEmpty) throw StateError('La tarea requiere título.');
    if (empresaId.isEmpty) throw StateError('La tarea requiere empresaId.');
    if (assignedId.isEmpty) {
      throw StateError('La tarea requiere un responsable.');
    }
    if (creatorId.isEmpty) throw StateError('La tarea requiere creador.');

    final status = normalizeStatus(data['estado'] ?? data['status']);
    final priority = normalizePriority(data['prioridad'] ?? data['priority']);
    final approverId = [
      data['aprobador_uid'],
      data['approverId'],
      data['jefe_uid'],
      data['bossId'],
      creatorId,
    ].map(_text).firstWhere((value) => value.isNotEmpty);
    final approverName = [
      data['aprobador_nombre'],
      data['approverName'],
      data['jefe_nombre'],
      data['bossName'],
      data['creador_nombre'],
    ].map(_text).firstWhere((value) => value.isNotEmpty, orElse: () => '');

    final source = data['source'] is Map
        ? Map<String, dynamic>.from(data['source'] as Map)
        : <String, dynamic>{};
    final moduleId = normalizeModuleId(
      source['moduleId'] ??
          data['sourceModule'] ??
          data['destinoModulo'] ??
          data['module'] ??
          (data['origen'] == 'manual' ? defaultSourceModule : data['origen']) ??
          defaultSourceModule,
    );
    final sourceType = _text(
      source['type'] ?? data['sourceType'] ?? data['origen'] ?? 'manual',
    );
    final entityId = _text(
      source['entityId'] ??
          data['sourceEntityId'] ??
          data['hallazgoId'] ??
          data['facObservacionId'],
    );
    final entityCollection = _text(
      source['entityCollection'] ?? data['sourceEntityCollection'],
    );
    final route = _text(source['route'] ?? data['sourceRoute']);

    final empresas = <String>{empresaId};
    final rawEmpresas = data['empresas'];
    if (rawEmpresas is Iterable) {
      empresas.addAll(
        rawEmpresas.map(_text).where((value) => value.isNotEmpty),
      );
    }

    data
      ..['schemaVersion'] = schemaVersion
      ..['titulo'] = title
      ..['estado'] = status
      ..['status'] = status
      ..['prioridad'] = priority
      ..['priority'] = priority
      ..['empresaId'] = empresaId
      ..['empresas'] = empresas.toList()
      ..['asignado_uid'] = assignedId
      ..['creador_id'] = creatorId
      ..['sourceModule'] = moduleId
      ..['sourceType'] = sourceType.isEmpty ? 'manual' : sourceType
      ..['source'] = <String, dynamic>{
        'moduleId': moduleId,
        'type': sourceType.isEmpty ? 'manual' : sourceType,
        if (entityId.isNotEmpty) 'entityId': entityId,
        if (entityCollection.isNotEmpty) 'entityCollection': entityCollection,
        if (route.isNotEmpty) 'route': route,
      }
      ..['requiere_aprobacion'] =
          data['requiere_aprobacion'] ?? data['requiresApproval'] ?? true;

    if (approverId.isNotEmpty) {
      data['aprobador_uid'] = approverId;
      data['approverId'] = approverId;
    }
    if (approverName.isNotEmpty) {
      data['aprobador_nombre'] = approverName;
      data['approverName'] = approverName;
    }
    return data;
  }
}
