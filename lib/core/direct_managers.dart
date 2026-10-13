/// El jefe principal conserva los flujos históricos de aprobación única.
/// El segundo jefe se mantiene únicamente en Estructura, por empresa.
String primaryManagerId(Map<String, dynamic> data) {
  for (final key in const [
    'jefe_directo_id',
    'jefeId',
    'jefeDirectoId',
    'jefe_id',
    'jefe_uid',
    'managerId',
    'supervisorId',
  ]) {
    final value = (data[key] ?? '').toString().trim();
    if (value.isNotEmpty) return value;
  }
  return '';
}

Map<String, String> secondManager(Map<String, dynamic> data, String empresaId) {
  final raw = data['segundoJefePorEmpresa'];
  final scoped = raw is Map ? raw[empresaId] : null;
  if (scoped is! Map) return const {};
  return {
    'id': (scoped['id'] ?? '').toString().trim(),
    'nombre': (scoped['nombre'] ?? '').toString().trim(),
  };
}

Set<String> directManagerIds(Map<String, dynamic> data, String empresaId) => {
  if (primaryManagerId(data).isNotEmpty) primaryManagerId(data),
  if ((secondManager(data, empresaId)['id'] ?? '').isNotEmpty)
    secondManager(data, empresaId)['id']!,
};

String? validateDirectManagers({
  required String personId,
  required String primaryId,
  required String secondId,
  required Map<String, Set<String>> managersByPerson,
}) {
  if (secondId.isNotEmpty && primaryId.isEmpty) {
    return 'Selecciona primero el jefe directo principal.';
  }
  if (secondId.isNotEmpty && secondId == primaryId) {
    return 'Los dos jefes directos deben ser personas distintas.';
  }
  final pending = [primaryId, secondId].where((id) => id.isNotEmpty).toList();
  final seen = <String>{};
  while (pending.isNotEmpty) {
    final current = pending.removeLast();
    if (current == personId) {
      return 'La asignación genera un ciclo de jefaturas.';
    }
    if (seen.add(current)) pending.addAll(managersByPerson[current] ?? {});
  }
  return null;
}
