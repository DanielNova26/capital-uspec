import 'dart:js_interop';
import 'dart:typed_data';

@JS('_extractPdfText')
external JSPromise<JSString> _jsPdfExtract(JSUint8Array data);

Future<String> extractPdfTextFromBytes(Uint8List bytes) async {
  try {
    final result = await _jsPdfExtract(bytes.toJS).toDart;
    return result.toDart;
  } catch (e) {
    return '';
  }
}
