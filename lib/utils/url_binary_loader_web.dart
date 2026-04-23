import 'dart:html' as html;
import 'dart:typed_data';

Future<Uint8List?> loadBinaryFromUrl(String url) async {
  try {
    final request = await html.HttpRequest.request(
      url,
      method: 'GET',
      responseType: 'arraybuffer',
    );
    final response = request.response;
    if ((request.status == 200 || request.status == 0) && response != null) {
      if (response is ByteBuffer) {
        return response.asUint8List();
      }
      if (response is Uint8List) {
        return response;
      }
    }
  } catch (_) {}
  return null;
}
