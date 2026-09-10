/// Descarga de un Excel generado en memoria, en web y en móvil.
///
/// Reexporta la implementación que ya vive en Compras en vez de duplicar el
/// código de plataforma: es la misma operación y tener dos copias garantiza que
/// una se arregle y la otra no. El nombre de allí dice "Compras" por su origen;
/// este archivo es el que deben importar los demás módulos.
library;

export '../compras/compras_excel_download_io.dart'
    if (dart.library.html) '../compras/compras_excel_download_web.dart';
