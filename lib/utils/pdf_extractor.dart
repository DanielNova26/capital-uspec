// Extracción de texto de PDFs — web usa PDF.js vía JS interop,
// otras plataformas devuelven cadena vacía (los PDFs se escanean con cámara).
export 'pdf_extractor_stub.dart'
    if (dart.library.html) 'pdf_extractor_web.dart';
