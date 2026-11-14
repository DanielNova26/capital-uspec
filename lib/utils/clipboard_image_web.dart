import 'dart:js_interop';
import 'dart:typed_data';

@JS('navigator.clipboard')
external _Clipboard? get _clipboard;

extension type _Clipboard(JSObject _) implements JSObject {
  external JSPromise<JSArray<_ClipboardItem>> read();
}

extension type _ClipboardItem(JSObject _) implements JSObject {
  external JSArray<JSString> get types;
  external JSPromise<_Blob> getType(JSString mime);
}

extension type _Blob(JSObject _) implements JSObject {
  external JSPromise<JSArrayBuffer> arrayBuffer();
}

Future<Uint8List?> readClipboardImage() async {
  final clipboard = _clipboard;
  if (clipboard == null) return null;
  final items = await clipboard.read().toDart;
  for (final item in items.toDart) {
    if (!item.types.toDart.any((type) => type.toDart == 'image/png')) continue;
    final blob = await item.getType('image/png'.toJS).toDart;
    return (await blob.arrayBuffer().toDart).toDart.asUint8List();
  }
  return null;
}
