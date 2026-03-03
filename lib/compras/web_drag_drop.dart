// Exporta la implementación correcta según plataforma:
// - dart:html (web real) cuando se compila para web
// - stub vacío para móvil/desktop
export 'web_drag_drop_stub.dart'
    if (dart.library.html) 'web_drag_drop_web.dart';
