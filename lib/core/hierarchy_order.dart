class HierarchyRank {
  final int sequence;
  final int depth;
  final int siblingOrder;

  const HierarchyRank({
    required this.sequence,
    required this.depth,
    required this.siblingOrder,
  });
}

/// Índice compartido del orden jerárquico definido en TBL_CARGOS.
///
/// La relación `parent_cargo` define los niveles y `ordenJerarquico` ordena
/// cargos hermanos. Los registros antiguos sin orden conservan un orden
/// estable por nombre.
class CargoHierarchyIndex {
  final Map<String, HierarchyRank> _byId;
  final Map<String, HierarchyRank> _byName;

  const CargoHierarchyIndex._(this._byId, this._byName);

  factory CargoHierarchyIndex.empty() => const CargoHierarchyIndex._({}, {});

  factory CargoHierarchyIndex.fromCargos(
    Iterable<Map<String, dynamic>> cargos,
  ) {
    final byId = <String, Map<String, dynamic>>{};
    for (final cargo in cargos) {
      final id = cargoIdOf(cargo);
      if (id.isNotEmpty) byId[id] = cargo;
    }

    final children = <String, List<String>>{};
    for (final entry in byId.entries) {
      final rawParent = _text(entry.value, const [
        'parent_cargo',
        'parentCargo',
        'cargoPadreId',
      ]);
      final parent = rawParent != entry.key && byId.containsKey(rawParent)
          ? rawParent
          : '';
      children.putIfAbsent(parent, () => []).add(entry.key);
    }

    int compareIds(String a, String b) {
      final ma = byId[a] ?? const <String, dynamic>{};
      final mb = byId[b] ?? const <String, dynamic>{};
      final oa = hierarchyOrderOf(ma);
      final ob = hierarchyOrderOf(mb);
      if (oa != ob) return oa.compareTo(ob);
      final byName = cargoNameOf(
        ma,
      ).toLowerCase().compareTo(cargoNameOf(mb).toLowerCase());
      return byName != 0 ? byName : a.compareTo(b);
    }

    for (final group in children.values) {
      group.sort(compareIds);
    }

    final ranksById = <String, HierarchyRank>{};
    final ranksByName = <String, HierarchyRank>{};
    final visited = <String>{};
    var sequence = 0;

    void visit(String id, int depth) {
      if (!visited.add(id)) return;
      final cargo = byId[id];
      if (cargo == null) return;
      final rank = HierarchyRank(
        sequence: sequence++,
        depth: depth,
        siblingOrder: hierarchyOrderOf(cargo),
      );
      ranksById[id] = rank;
      final nameKey = normalizeHierarchyText(cargoNameOf(cargo));
      if (nameKey.isNotEmpty) ranksByName.putIfAbsent(nameKey, () => rank);
      for (final child in children[id] ?? const <String>[]) {
        visit(child, depth + 1);
      }
    }

    for (final root in children[''] ?? const <String>[]) {
      visit(root, 0);
    }
    final remaining = byId.keys.where((id) => !visited.contains(id)).toList()
      ..sort(compareIds);
    for (final id in remaining) {
      visit(id, 0);
    }

    return CargoHierarchyIndex._(ranksById, ranksByName);
  }

  HierarchyRank? rankFor({String cargoId = '', String cargoName = ''}) {
    final id = cargoId.trim();
    if (id.isNotEmpty && _byId.containsKey(id)) return _byId[id];
    return _byName[normalizeHierarchyText(cargoName)];
  }

  int depthFor({String cargoId = '', String cargoName = ''}) =>
      rankFor(cargoId: cargoId, cargoName: cargoName)?.depth ?? 0;

  int compareCargos(Map<String, dynamic> a, Map<String, dynamic> b) {
    final ra = rankFor(cargoId: cargoIdOf(a), cargoName: cargoNameOf(a));
    final rb = rankFor(cargoId: cargoIdOf(b), cargoName: cargoNameOf(b));
    final rankCompare = _compareRanks(ra, rb);
    if (rankCompare != 0) return rankCompare;
    return cargoNameOf(a).toLowerCase().compareTo(cargoNameOf(b).toLowerCase());
  }

  int comparePersonnel(Map<String, dynamic> a, Map<String, dynamic> b) {
    final ra = rankFor(cargoId: cargoIdOf(a), cargoName: cargoNameOf(a));
    final rb = rankFor(cargoId: cargoIdOf(b), cargoName: cargoNameOf(b));
    final rankCompare = _compareRanks(ra, rb);
    if (rankCompare != 0) return rankCompare;
    return personNameOf(
      a,
    ).toLowerCase().compareTo(personNameOf(b).toLowerCase());
  }

  static int _compareRanks(HierarchyRank? a, HierarchyRank? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return a.sequence.compareTo(b.sequence);
  }
}

int hierarchyOrderOf(Map<String, dynamic> data) {
  for (final key in const [
    'ordenJerarquico',
    'orden_jerarquico',
    'hierarchyOrder',
    'orden',
  ]) {
    final value = data[key];
    if (value is num) return value.toInt();
    final parsed = int.tryParse((value ?? '').toString());
    if (parsed != null) return parsed;
  }
  return 1000000;
}

String cargoIdOf(Map<String, dynamic> data) =>
    _text(data, const ['cargoId', 'cargo_id', 'id', 'code']);

String cargoNameOf(Map<String, dynamic> data) => _text(data, const [
  'cargo',
  'cargoNombre',
  'cargo_nombre',
  'nombreCargo',
  'nombre',
  'descripcion',
]);

String personNameOf(Map<String, dynamic> data) => _text(data, const [
  'nombreCompleto',
  'empleadoNombre',
  'nombre',
  'displayName',
  'cedula',
  'uid',
]);

String normalizeHierarchyText(String value) => value
    .toLowerCase()
    .replaceAll('á', 'a')
    .replaceAll('é', 'e')
    .replaceAll('í', 'i')
    .replaceAll('ó', 'o')
    .replaceAll('ú', 'u')
    .replaceAll('ü', 'u')
    .replaceAll('ñ', 'n')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

String _text(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    final value = (data[key] ?? '').toString().trim();
    if (value.isNotEmpty && value != 'null') return value;
  }
  return '';
}
