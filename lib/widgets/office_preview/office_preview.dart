// lib/widgets/office_preview/office_preview.dart
//
// Vista previa de Word / Excel / PowerPoint sin descargar (reunión del 18 sep
// 2026: "vista previa de documentos mediante un complemento").
//
// No hay motor de Office dentro de la app: se usa el visor en línea de
// Microsoft (`view.officeapps.live.com`) y, si no responde, el de Google
// (`docs.google.com/gview`). Ambos necesitan una URL pública del archivo: las
// de Firebase Storage con token lo son. En web va dentro de un iframe; en el
// teléfono se abre el visor en el navegador, que es lo que hace el propio
// sistema con un adjunto de correo.

export 'office_preview_stub.dart'
    if (dart.library.html) 'office_preview_web.dart';

/// Extensiones con visor en línea.
const Set<String> kExtensionesOffice = {
  'doc',
  'docx',
  'xls',
  'xlsx',
  'ppt',
  'pptx',
};

bool tieneVistaPreviaOffice(String? nombreArchivo) {
  final n = (nombreArchivo ?? '').trim().toLowerCase();
  if (!n.contains('.')) return false;
  return kExtensionesOffice.contains(n.split('.').last);
}

/// URL del visor de Microsoft para incrustar.
String urlVisorOffice(String url) =>
    'https://view.officeapps.live.com/op/embed.aspx?src=${Uri.encodeComponent(url)}';

/// URL del visor de Google, como segunda opción.
String urlVisorGoogle(String url) =>
    'https://docs.google.com/gview?embedded=true&url=${Uri.encodeComponent(url)}';
