import 'dart:convert';

/// Convierte el cuerpo recibido desde Gmail o Microsoft 365 en texto legible.
/// También corrige el caso común en el que UTF-8 fue interpretado como
/// Windows-1252 (por ejemplo, `informaciÃ³n`).
String gdTextoCorreoLegible(String input) {
  var value = input.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  if (_pareceHtml(value)) {
    value = value
        .replaceAll(
          RegExp(r'<(style|script)[^>]*>[\s\S]*?</\1>', caseSensitive: false),
          ' ',
        )
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(
          RegExp(r'</(p|div|li|tr|h[1-6])\s*>', caseSensitive: false),
          '\n',
        )
        .replaceAll(RegExp(r'<li[^>]*>', caseSensitive: false), '• ')
        .replaceAll(RegExp(r'<[^>]+>'), ' ');
  }

  value = _decodificarEntidadesHtml(value);
  value = _repararUtf8InterpretadoComoWindows1252(value);
  return value
      .replaceAll(RegExp(r'[ \t]+\n'), '\n')
      .replaceAll(RegExp(r'\n[ \t]+'), '\n')
      .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

bool _pareceHtml(String value) => RegExp(
  r'<\s*(html|body|div|p|br|table|tr|td|span|style|script|h[1-6]|ul|ol|li)\b',
  caseSensitive: false,
).hasMatch(value);

String _decodificarEntidadesHtml(String value) {
  const named = <String, String>{
    'nbsp': ' ',
    'amp': '&',
    'lt': '<',
    'gt': '>',
    'quot': '"',
    'apos': "'",
    'ndash': '–',
    'mdash': '—',
    'hellip': '…',
  };
  return value.replaceAllMapped(
    RegExp(r'&(#(?:x[0-9a-f]+|[0-9]+)|[a-z]+);', caseSensitive: false),
    (match) {
      final entity = match.group(1) ?? '';
      if (!entity.startsWith('#')) {
        return named[entity.toLowerCase()] ?? match.group(0)!;
      }
      final hexadecimal = entity.length > 2 && entity[1].toLowerCase() == 'x';
      final raw = entity.substring(hexadecimal ? 2 : 1);
      final codePoint = int.tryParse(raw, radix: hexadecimal ? 16 : 10);
      if (codePoint == null || codePoint < 0 || codePoint > 0x10ffff) {
        return match.group(0)!;
      }
      return String.fromCharCode(codePoint);
    },
  );
}

String _repararUtf8InterpretadoComoWindows1252(String value) {
  final before = _puntajeMojibake(value);
  if (before == 0) return value;

  final bytes = <int>[];
  for (final rune in value.runes) {
    final byte = rune <= 0xff ? rune : _windows1252ToByte[rune];
    if (byte == null) return value;
    bytes.add(byte);
  }
  try {
    final candidate = utf8.decode(bytes, allowMalformed: false);
    return _puntajeMojibake(candidate) < before ? candidate : value;
  } on FormatException {
    return value;
  }
}

int _puntajeMojibake(String value) {
  var score = 0;
  for (final token in const ['Ã', 'Â', 'â€', 'ðŸ', 'ï¿½', '�']) {
    score += token.allMatches(value).length;
  }
  return score;
}

const _windows1252ToByte = <int, int>{
  0x20ac: 0x80,
  0x201a: 0x82,
  0x0192: 0x83,
  0x201e: 0x84,
  0x2026: 0x85,
  0x2020: 0x86,
  0x2021: 0x87,
  0x02c6: 0x88,
  0x2030: 0x89,
  0x0160: 0x8a,
  0x2039: 0x8b,
  0x0152: 0x8c,
  0x017d: 0x8e,
  0x2018: 0x91,
  0x2019: 0x92,
  0x201c: 0x93,
  0x201d: 0x94,
  0x2022: 0x95,
  0x2013: 0x96,
  0x2014: 0x97,
  0x02dc: 0x98,
  0x2122: 0x99,
  0x0161: 0x9a,
  0x203a: 0x9b,
  0x0153: 0x9c,
  0x017e: 0x9e,
  0x0178: 0x9f,
};
