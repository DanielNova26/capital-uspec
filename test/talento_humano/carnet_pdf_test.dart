import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:todo/talento_humano/carnet_layout.dart';
import 'package:todo/talento_humano/carnet_marca.dart';
import 'package:todo/talento_humano/carnet_pdf.dart';

/// Persona de prueba con los campos más largos que se van a encontrar en
/// producción: si el diseño aguanta este nombre y este cargo, aguanta el resto.
const _persona = CarnetPersona(
  userId: '1020304050',
  nombres: 'María Fernanda',
  apellidos: 'Rodríguez Cárdenas',
  cargo: 'Auxiliar de Servicios Generales',
  cedula: '1.020.304.050',
  rh: 'O+',
  token: 'aBcDeFgHiJkLmNoPqRsTuVwXyZ012345',
);

const _marca = CarnetMarca(
  empresaId: 'alfa',
  empresaNombre: 'ALFA Unión Temporal',
  colorPrimario: kCarnetAzulPorDefecto,
  colorSecundario: kCarnetDoradoPorDefecto,
);

/// Sin logo ni foto: así el PDF se arma sin tocar la red y la prueba no depende
/// de que Storage esté arriba.
const _sinImagenes = CarnetRecursos();

void main() {
  // `temaCarnet()` lee assets/arial.ttf por rootBundle.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('carnet impreso', () {
    test('sale un PDF válido y no vacío', () async {
      final bytes = await buildCarnetPdf(
        persona: _persona,
        marca: _marca,
        recursos: _sinImagenes,
      );
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(bytes.length, greaterThan(2000));
    });

    test('los dos formatos generan documentos distintos', () async {
      final tarjeta = await buildCarnetPdf(
        persona: _persona,
        marca: _marca,
        formato: CarnetFormato.tarjeta,
        recursos: _sinImagenes,
      );
      final escarapela = await buildCarnetPdf(
        persona: _persona,
        marca: _marca,
        formato: CarnetFormato.escarapela,
        recursos: _sinImagenes,
      );
      expect(tarjeta.length, isNot(escarapela.length));
    });

    test('una persona sin RH no rompe el carnet', () async {
      // El RH vive en la hoja de vida y buena parte del padrón lo tiene vacío:
      // el renglón se omite, no se imprime "RH: ".
      final bytes = await buildCarnetPdf(
        persona: const CarnetPersona(
          userId: 'x',
          nombres: 'Ana',
          apellidos: 'Gómez',
          cargo: 'Enfermera',
          cedula: '52123456',
        ),
        marca: _marca,
        recursos: _sinImagenes,
      );
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });

    test('una persona sin token se imprime sin QR en vez de fallar', () async {
      // Pasa cuando alguien reimprime antes de que el token se haya creado.
      // Un carnet sin QR sigue sirviendo; una excepción deja a TH sin nada.
      final bytes = await buildCarnetPdf(
        persona: const CarnetPersona(
          userId: 'x',
          nombres: 'Ana',
          apellidos: 'Gómez',
          cargo: 'Enfermera',
          cedula: '52123456',
        ),
        marca: _marca,
        recursos: _sinImagenes,
      );
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });
  });

  group('hoja de lotes', () {
    test('la tarjeta CR80 entra 9 veces en una hoja carta', () {
      // Si este número baja, alguien tocó márgenes o canal y el lote pasa a
      // gastar el doble de papel sin que nadie se entere.
      expect(carnetsPorHoja(CarnetFormato.tarjeta), 9);
    });

    test('la escarapela entra 4 veces', () {
      expect(carnetsPorHoja(CarnetFormato.escarapela), 4);
    });

    test('un lote más grande que una hoja genera varias páginas', () async {
      final personas = List.generate(
        14,
        (i) => CarnetPersona(
          userId: 'u$i',
          nombres: 'Persona',
          apellidos: 'Número $i',
          cargo: 'Operario',
          cedula: '100$i',
          token: 'token${i.toString().padLeft(28, '0')}',
        ),
      );
      final bytes = await buildCarnetsHojaPdf(
        personas: personas,
        marca: _marca,
        recursos: _sinImagenes,
      );
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(bytes.length, greaterThan(10000));
    });

    test('sin personas no se genera un PDF vacío', () async {
      expect(
        () => buildCarnetsHojaPdf(
          personas: const [],
          marca: _marca,
          recursos: _sinImagenes,
        ),
        throwsArgumentError,
      );
    });
  });

  group('el contenido cabe en el alto de la tarjeta', () {
    // El desborde del PDF no lanza excepción: recorta en silencio y el error
    // solo aparece impreso. Por eso el presupuesto vertical se comprueba con
    // aritmética, sobre las mismas constantes que usan los dos dibujos.
    //
    // Las letras se miden contra `unidadCarnet`, que en proporción al alto vale
    // siempre kProporcionBase, así que la cuenta da igual en los dos formatos.
    const interlineado = 1.3; // conservador: Arial ronda 1,15
    const u = kProporcionBase;

    double alturaTexto(double tamano) => tamano * u * interlineado;

    final nombre =
        alturaTexto(CarnetLayout.letraNombres) +
        CarnetLayout.espacioRenglon * u +
        alturaTexto(CarnetLayout.letraApellidos);

    final documento =
        alturaTexto(CarnetLayout.letraDocumento) * 2 +
        CarnetLayout.espacioRenglon * u;
    final qr = CarnetLayout.ladoQr * u;
    final pie = documento > qr ? documento : qr;

    final total =
        CarnetLayout.margenSuperior +
        CarnetLayout.altoLogo +
        CarnetLayout.espacioLogoFoto +
        CarnetLayout.diametroFoto +
        CarnetLayout.espacioFotoNombre +
        nombre +
        CarnetLayout.altoBanda +
        CarnetLayout.espacioBandaPie +
        pie +
        CarnetLayout.margenInferior;

    test('la suma de los bloques deja holgura para el aire del medio', () {
      // Si esto falla, alguien agrandó la foto, el logo, la banda o el QR sin
      // quitar altura de otro lado, y el carnet va a salir recortado.
      expect(total, lessThan(0.97));
    });

    test('el QR no baja del tamaño en que deja de escanearse', () {
      // 0,28 de la unidad sobre 54 mm son ~15 mm, el piso práctico para un QR
      // de ~37 módulos impreso y leído con un teléfono.
      expect(CarnetLayout.ladoQr, greaterThanOrEqualTo(0.28));
    });

    test('los arcos de arriba no llegan al renglón de apellidos', () {
      // El arco más externo, medido desde su centro hacia abajo, no puede pasar
      // del 55% del alto: ahí empieza el nombre y las líneas lo estorban.
      final radioMax =
          CarnetLayout.arcoSupRadioMin +
          CarnetLayout.arcoSupPaso * (CarnetLayout.arcoSupCuantos - 1);
      // De fracción del ancho a fracción del alto.
      final alcance = radioMax * kProporcionBase;
      final bordeInferior = (1 - CarnetLayout.arcoSupCy) + alcance;
      expect(bordeInferior, lessThan(0.55));
    });

    test('los arcos de abajo no cruzan por detrás de la cédula', () {
      final radioMax =
          CarnetLayout.arcoInfRadioMin +
          CarnetLayout.arcoInfPaso * (CarnetLayout.arcoInfCuantos - 1);
      // Hasta dónde entra por la izquierda, en fracción del ancho.
      final entra = CarnetLayout.arcoInfCx + radioMax;
      expect(entra, lessThan(CarnetLayout.margenPie));
    });
  });

  group('colores de la empresa', () {
    test('un hex de 6 dígitos se lee como color opaco', () {
      expect(colorDesdeHex('#1B1B64', 0), 0xFF1B1B64);
      expect(colorDesdeHex('1B1B64', 0), 0xFF1B1B64);
    });

    test('un valor escrito a mano que no es color cae en el de reserva', () {
      // Alguien puede dejar cualquier cosa en el campo de Firestore; la
      // pantalla no puede quedarse sin color por eso.
      expect(colorDesdeHex('azul', 0xFF123456), 0xFF123456);
      expect(colorDesdeHex(null, 0xFF123456), 0xFF123456);
      expect(colorDesdeHex('', 0xFF123456), 0xFF123456);
    });

    test('ida y vuelta entre hex y entero conserva el color', () {
      expect(colorDesdeHex(hexDeColor(0xFFC6A02C), 0), 0xFFC6A02C);
    });

    test('una empresa sin diseño guardado usa los colores por defecto', () {
      final marca = CarnetMarca.desdeEmpresa('e1', {'nombre': 'Empresa'});
      expect(marca.colorPrimario, kCarnetAzulPorDefecto);
      expect(marca.colorSecundario, kCarnetDoradoPorDefecto);
    });
  });

  // Deja el PDF a la vista para revisarlo con los ojos. La prueba no valida el
  // aspecto —eso no se automatiza— pero evita tener que montar la app entera
  // para ver cómo quedó un cambio de diseño.
  test('deja una muestra en build/ para revisar a ojo', () async {
    final hoja = await buildCarnetsHojaPdf(
      personas: List.generate(
        9,
        (i) => CarnetPersona(
          userId: 'u$i',
          nombres: i.isEven ? 'María Fernanda' : 'Juan',
          apellidos: i.isEven ? 'Rodríguez Cárdenas' : 'Muñoz',
          cargo: i.isEven ? 'Auxiliar de Servicios Generales' : 'Conductor',
          cedula: '1.020.304.05$i',
          rh: 'O+',
          token: 'token${i.toString().padLeft(28, '0')}',
        ),
      ),
      marca: _marca,
      recursos: _sinImagenes,
    );
    final salida = Directory('build/carnet_muestra')
      ..createSync(recursive: true);
    File('${salida.path}/hoja.pdf').writeAsBytesSync(hoja);
    File('${salida.path}/tarjeta.pdf').writeAsBytesSync(
      await buildCarnetPdf(
        persona: _persona,
        marca: _marca,
        recursos: _sinImagenes,
      ),
    );
    expect(File('${salida.path}/hoja.pdf').existsSync(), isTrue);
  });
}
