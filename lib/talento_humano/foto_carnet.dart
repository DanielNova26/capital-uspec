// lib/talento_humano/foto_carnet.dart
//
// Recorte de fondo de la foto del carnet.
//
// Se hace EN EL TELÉFONO con ML Kit: gratis, sin llamadas de red y sin que la
// foto de una persona salga del dispositivo para procesarse. La contrapartida
// es que ML Kit solo existe en Android e iOS, así que en web y escritorio esto
// avisa que no hay soporte y la foto se usa tal cual.
//
// Quien llama NUNCA debe asumir que el recorte va a ocurrir: se pregunta por
// [soportaRecorteDeFondo] y se trata `null` como "quedó la original", que es
// un resultado válido y no un error.
//
// La selección de implementación sigue el mismo patrón que
// gestion_documental/widgets/gd_pdf_preview.dart.

export 'foto_carnet_io.dart' if (dart.library.html) 'foto_carnet_web.dart';
