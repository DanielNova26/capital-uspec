// Exportación condicional: en web usa dart:html iframe real;
// en móvil usa el placeholder con botón de apertura externa.
export 'web_pdf_view_stub.dart'
    if (dart.library.html) 'web_pdf_view_web.dart';
