import 'gd_models.dart';

enum GdLibrarySection { formatos, contrato, normograma }

const List<String> gdFormatCategories = [
  'Formato',
  'Procedimiento',
  'Politica',
  'Instructivo',
];

const List<String> gdContractCategories = [
  'Documento contractual',
  'RUT',
  'Certificado de existencia',
  'Certificacion bancaria',
  'Contrato',
  'Anexo',
  'Otrosi',
  'Circular externa',
];

const List<String> gdNormogramCategories = [
  'Norma aplicable',
  'Ley',
  'Decreto',
  'Resolucion',
  'Circular normativa',
];

List<String> gdCategoriesForSection(GdLibrarySection section) =>
    switch (section) {
      GdLibrarySection.formatos => gdFormatCategories,
      GdLibrarySection.contrato => gdContractCategories,
      GdLibrarySection.normograma => gdNormogramCategories,
    };

GdLibrarySection gdSectionForCategory(String? rawCategory) {
  final category = _normalize(rawCategory ?? '');
  if (gdContractCategories.any((value) => _normalize(value) == category)) {
    return GdLibrarySection.contrato;
  }
  if (gdNormogramCategories.any((value) => _normalize(value) == category)) {
    return GdLibrarySection.normograma;
  }
  return GdLibrarySection.formatos;
}

List<String> gdNormalizeKeywords(String raw) {
  final seen = <String>{};
  final result = <String>[];
  for (final part in raw.split(RegExp(r'[,;\n]'))) {
    final keyword = part.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (keyword.isEmpty) continue;
    final normalized = _normalize(keyword);
    if (seen.add(normalized)) result.add(keyword);
  }
  return result;
}

String gdNextDocumentCode({
  required String area,
  required Iterable<String> existingCodes,
}) {
  final prefix = gdDepartmentPrefix(area);
  final expression = RegExp(
    '^${RegExp.escape(prefix)}-(\\d+)\$',
    caseSensitive: false,
  );
  var maxNumber = 0;
  for (final code in existingCodes) {
    final match = expression.firstMatch(code.trim());
    if (match == null) continue;
    final value = int.tryParse(match.group(1) ?? '') ?? 0;
    if (value > maxNumber) maxNumber = value;
  }
  return '$prefix-${(maxNumber + 1).toString().padLeft(3, '0')}';
}

String gdDepartmentPrefix(String rawArea) {
  final area = _normalize(
    rawArea,
  ).replaceAll(RegExp(r'[^a-z0-9 ]'), ' ').trim();
  const known = <String, String>{
    'talento humano': 'TAL',
    'calidad': 'CAL',
    'compras': 'COM',
    'nutricion': 'NUT',
    'mantenimiento': 'MAN',
    'hseq': 'HSE',
    'juridica': 'JUR',
    'financiera': 'FIN',
    'administrativa': 'ADM',
    'operaciones': 'OPE',
    'sistemas': 'SIS',
  };
  final knownPrefix = known[area];
  if (knownPrefix != null) return knownPrefix;

  final words = area
      .split(RegExp(r'\s+'))
      .where(
        (word) => word.isNotEmpty && !{'de', 'del', 'la', 'y'}.contains(word),
      )
      .toList();
  if (words.length >= 2) {
    return words.take(3).map((word) => word[0]).join().toUpperCase();
  }
  final compact = words.isEmpty ? 'DOC' : words.first;
  return compact.padRight(3, 'X').substring(0, 3).toUpperCase();
}

bool gdDocumentMatchesQuery(DocumentoDoc document, String rawQuery) {
  final query = _normalize(rawQuery);
  if (query.isEmpty) return true;
  final haystack = [
    document.codigo,
    document.titulo,
    document.descripcion ?? '',
    document.area ?? '',
    document.categoria ?? '',
    ...document.palabrasClave,
  ].map(_normalize).join(' ');
  return query.split(RegExp(r'\s+')).every(haystack.contains);
}

int gdRelatedDocumentsCount(
  DocumentoDoc target,
  Iterable<DocumentoDoc> documents,
) {
  final targetKeywords = target.palabrasClave.map(_normalize).toSet();
  if (targetKeywords.isEmpty) return 0;
  return documents.where((document) {
    if (document.docId == target.docId) return false;
    return document.palabrasClave.map(_normalize).any(targetKeywords.contains);
  }).length;
}

String _normalize(String value) {
  var normalized = value.trim().toLowerCase();
  const replacements = <String, String>{
    'á': 'a',
    'é': 'e',
    'í': 'i',
    'ó': 'o',
    'ú': 'u',
    'ü': 'u',
    'ñ': 'n',
  };
  replacements.forEach((source, target) {
    normalized = normalized.replaceAll(source, target);
  });
  return normalized;
}
