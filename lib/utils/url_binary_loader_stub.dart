import 'dart:typed_data';

import 'package:http/http.dart' as http;

Future<Uint8List?> loadBinaryFromUrl(String url) async {
  try {
    final resp = await http.get(Uri.parse(url));
    if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
      return resp.bodyBytes;
    }
  } catch (_) {}
  return null;
}
