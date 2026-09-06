// lib/talento_humano/carnet_layout.dart
//
// Las proporciones del carnet, en un solo sitio.
//
// El carnet se dibuja DOS veces: en PDF (lo que se imprime, carnet_pdf.dart) y
// en Flutter (la vista previa donde se eligen los colores). Si cada uno tuviera
// sus propios números, la vista previa mentiría en cuanto alguien tocara uno de
// los dos, y el error solo se vería después de imprimir.
//
// Este archivo no importa `flutter` ni `pdf` a propósito: es aritmética que
// deben poder leer los dos lados.
//
// DOS UNIDADES, Y NO SON INTERCAMBIABLES
//
// Los bloques verticales (logo, foto, banda, aire) van como fracción del ALTO.
// Las letras y el QR van como fracción de [unidadCarnet], que NO es el ancho.
//
// El motivo: la tarjeta CR80 es 54 × 85,6 (proporción 0,63) y la escarapela es
// 86 × 120 (proporción 0,72), más ancha en relación con su alto. Si las letras
// y el QR se midieran contra el ancho, en la escarapela crecerían más que el
// alto disponible y el contenido no cabría. Con la unidad común, las dos salen
// con el mismo diseño y la escarapela simplemente respira más por los lados.

/// Proporción de la tarjeta CR80 (54 / 85,6). Es el formato de referencia con
/// el que se dimensionó el diseño.
const double kProporcionBase = 54 / 85.6;

/// Unidad con la que se miden letras y QR.
///
/// En la tarjeta coincide con el ancho. En un formato más ancho se queda en el
/// ancho equivalente de una CR80 de ese alto, para no inflar el contenido.
double unidadCarnet(double ancho, double alto) {
  final equivalente = alto * kProporcionBase;
  return ancho < equivalente ? ancho : equivalente;
}

class CarnetLayout {
  const CarnetLayout._();

  // --- Bloques verticales, como fracción del alto ---
  //
  // La suma de todo esto más el pie tiene que dejar holgura, o el `Spacer` del
  // medio se queda sin sitio y la columna desborda. Hay una prueba que renderiza
  // el carnet y falla si alguien se pasa: test/talento_humano/carnet_preview_test.dart

  /// Aire sobre el logo.
  static const double margenSuperior = 0.028;

  /// Alto de la caja del logo.
  static const double altoLogo = 0.135;

  /// Aire entre el logo y la foto.
  static const double espacioLogoFoto = 0.018;

  /// Diámetro de la foto circular.
  static const double diametroFoto = 0.230;

  /// Aire entre la foto y el nombre.
  static const double espacioFotoNombre = 0.026;

  /// Alto de la banda de color con el cargo.
  static const double altoBanda = 0.118;

  /// Aire entre la banda y el pie.
  static const double espacioBandaPie = 0.024;

  /// Aire bajo el pie.
  static const double margenInferior = 0.026;

  // --- Medidas horizontales ---
  //
  // Los anchos de caja van contra el ancho real (el logo y el nombre pueden
  // aprovechar todo el formato); los tamaños de letra, contra la unidad.

  /// Ancho máximo del logo, sobre el ancho real.
  static const double anchoLogo = 0.68;

  /// Ancho máximo del nombre de la empresa cuando no hay logo.
  static const double anchoNombreEmpresa = 0.78;

  /// Ancho útil para los renglones del nombre.
  static const double anchoNombre = 0.88;

  /// Márgenes laterales del texto del cargo dentro de la banda.
  static const double margenCargo = 0.06;

  /// Márgenes laterales del pie.
  static const double margenPie = 0.06;

  /// Lado del QR, sobre la unidad.
  ///
  /// NO se puede achicar por estética. La URL con el token da un QR de unos 37
  /// módulos más zona de silencio; a 54 mm de ancho, 0,30 deja el módulo en
  /// ~0,36 mm, que es el piso al que un teléfono todavía escanea un carnet
  /// impreso. Por debajo empieza a fallar, y un carnet cuyo QR no se lee no es
  /// un carnet verificable.
  ///
  /// 0,30 era ese piso, no el tamaño deseable: el pie se veía vacío, con la
  /// cédula a un lado y mucho blanco al otro. Sube a 0,32, que es lo máximo
  /// que deja el presupuesto de alto de la tarjeta —a 0,34 el contenido ya no
  /// cabe y la prueba de `carnet_pdf_test.dart` lo detiene—. De paso el código
  /// se escanea con más margen.
  static const double ladoQr = 0.32;

  // --- Tamaños de letra, como fracción de la unidad ---

  static const double letraNombres = 0.080;
  static const double letraApellidos = 0.100;

  /// Cuando la persona solo tiene cargado uno de los dos renglones.
  static const double letraNombreUnico = 0.098;
  static const double letraEmpresaSinLogo = 0.095;
  static const double letraCargo = 0.078;
  static const double letraDocumento = 0.062;

  /// Separación entre los dos renglones del nombre y entre CC y RH.
  static const double espacioRenglon = 0.010;

  // --- Arcos decorativos ---
  //
  // Los centros caen FUERA de la tarjeta: por eso se ve un arco y no un
  // círculo. `cx`/`cy` van como fracción de w y h; los radios, del ancho.
  //
  // Los radios son deliberadamente cortos. Con radios grandes el arco deja de
  // ser un detalle de esquina y cruza por encima del nombre y de la banda, que
  // es lo que pasaba en la primera versión: la decoración se comía la tarjeta.
  // El tope es que el cúmulo de arriba no baje del ~60% del alto y el de abajo
  // no suba por encima de la banda del cargo.

  /// Cúmulo superior derecho: nace del borde derecho, a la altura de la foto.
  ///
  /// El radio está calibrado para que el arco más externo no baje del 52% del
  /// alto, que es donde empieza el renglón de apellidos. Si baja, las líneas
  /// pasan por detrás del apellido y estorban justo el dato que más se lee.
  static const double arcoSupCx = 1.14;
  static const double arcoSupCy = 0.68;
  static const double arcoSupRadioMin = 0.15;
  static const double arcoSupPaso = 0.024;
  static const int arcoSupCuantos = 8;

  /// Cúmulo inferior izquierdo: acento pequeño en la esquina de abajo.
  ///
  /// Va pegado al borde porque en esa banda ahora vive la cédula. Con el centro
  /// más adentro, los arcos cruzan por detrás de "CC:" y del RH.
  static const double arcoInfCx = -0.18;
  static const double arcoInfCy = 0.04;
  static const double arcoInfRadioMin = 0.10;
  static const double arcoInfPaso = 0.024;
  static const int arcoInfCuantos = 6;

  /// Grosor de línea de los arcos, como fracción del ancho.
  ///
  /// Relativo y no absoluto: un grosor fijo de 1 pt sobre los 153 pt de ancho
  /// de una CR80 se ve el doble de grueso que ese mismo 1 px sobre una vista
  /// previa de 300 px, así que el PDF y la pantalla no coincidirían.
  static const double arcoGrosor = 0.004;
}
