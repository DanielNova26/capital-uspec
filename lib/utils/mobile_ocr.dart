// OCR de imágenes en móvil usando ML Kit (Latin script).
// En Web devuelve cadena vacía (el OCR se hace vía PDF.js).
export 'mobile_ocr_stub.dart'
    if (dart.library.io) 'mobile_ocr_native.dart';
