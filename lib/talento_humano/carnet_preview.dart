// lib/talento_humano/carnet_preview.dart
//
// El carnet dibujado en Flutter, para elegir los colores viéndolos.
//
// No sustituye al PDF: lo que se imprime siempre sale de carnet_pdf.dart. Esto
// existe porque regenerar un PDF en cada movimiento del selector de color va
// lento (y en web, muy lento), y elegir un color a ciegas no es elegir.
//
// Las dos versiones leen las mismas proporciones de carnet_layout.dart, así que
// no pueden separarse sin que alguien cambie ese archivo a propósito.

import 'package:flutter/material.dart';

import 'carnet_layout.dart';
import 'carnet_marca.dart';
import 'carnet_pdf.dart';

const Color _kTexto = Color(0xFF111111);
const Color _kPlaceholder = Color(0xFFE2E8F0);
const Color _kPlaceholderTexto = Color(0xFF94A3B8);
const String _kFont = 'Arial';

class CarnetPreview extends StatelessWidget {
  final CarnetPersona persona;
  final CarnetMarca marca;
  final CarnetFormato formato;

  /// Ancho en píxeles lógicos. El alto sale de la proporción del formato.
  final double ancho;

  const CarnetPreview({
    super.key,
    required this.persona,
    required this.marca,
    required this.ancho,
    this.formato = CarnetFormato.tarjeta,
  });

  @override
  Widget build(BuildContext context) {
    final w = ancho;
    final h = ancho * (formato.altoMm / formato.anchoMm);
    // Letras y QR contra la unidad, no contra el ancho: ver carnet_layout.dart.
    final u = unidadCarnet(w, h);
    final primario = Color(marca.colorPrimario);
    final secundario = Color(marca.colorSecundario);

    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(w * 0.035),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      // El recorte no es cosmético: los arcos nacen fuera de la tarjeta y sin
      // esto se salen por los bordes, igual que en el PDF.
      child: ClipRRect(
        borderRadius: BorderRadius.circular(w * 0.035),
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _ArcosPainter(
                  primario: primario,
                  secundario: secundario,
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(height: h * CarnetLayout.margenSuperior),
                _logo(w: w, h: h, color: primario),
                SizedBox(height: h * CarnetLayout.espacioLogoFoto),
                _foto(h: h),
                SizedBox(height: h * CarnetLayout.espacioFotoNombre),
                _nombre(w: w, u: u),
                const Spacer(),
                _banda(w: w, h: h, u: u, color: primario),
                SizedBox(height: h * CarnetLayout.espacioBandaPie),
                _pie(w: w, h: h, u: u),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _logo({required double w, required double h, required Color color}) {
    final alto = h * CarnetLayout.altoLogo;
    if (marca.logoUrl.trim().isNotEmpty) {
      return SizedBox(
        height: alto,
        width: w * CarnetLayout.anchoLogo,
        child: Image.network(
          marca.logoUrl,
          fit: BoxFit.contain,
          // Un logo que no carga no puede tumbar la vista previa: se cae al
          // nombre de la empresa, igual que hace el PDF cuando no hay logo.
          errorBuilder: (_, _, _) => _nombreEmpresa(w: w, color: color),
        ),
      );
    }
    return SizedBox(
      height: alto,
      width: w * CarnetLayout.anchoNombreEmpresa,
      child: _nombreEmpresa(w: w, color: color),
    );
  }

  Widget _nombreEmpresa({required double w, required Color color}) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        marca.empresaNombre.toUpperCase(),
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: _kFont,
          fontSize: w * CarnetLayout.letraEmpresaSinLogo,
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _foto({required double h}) {
    final d = h * CarnetLayout.diametroFoto;
    if (persona.fotoUrl.trim().isEmpty) return _fotoVacia(d);
    return ClipOval(
      child: Image.network(
        persona.fotoUrl,
        width: d,
        height: d,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _fotoVacia(d),
      ),
    );
  }

  Widget _fotoVacia(double d) {
    return Container(
      width: d,
      height: d,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: _kPlaceholder,
      ),
      child: Text(
        persona.inicial,
        style: TextStyle(
          fontFamily: _kFont,
          fontSize: d * 0.42,
          color: _kPlaceholderTexto,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _nombre({required double w, required double u}) {
    final nombres = persona.nombres.trim().toUpperCase();
    final apellidos = persona.apellidos.trim().toUpperCase();

    Widget renglon(String texto, double tamano) {
      return SizedBox(
        width: w * CarnetLayout.anchoNombre,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            texto,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: _kFont,
              fontSize: tamano,
              color: _kTexto,
            ),
          ),
        ),
      );
    }

    if (nombres.isEmpty && apellidos.isEmpty) {
      return renglon('SIN NOMBRE', u * CarnetLayout.letraNombres);
    }
    if (nombres.isEmpty || apellidos.isEmpty) {
      return renglon(
        nombres.isEmpty ? apellidos : nombres,
        u * CarnetLayout.letraNombreUnico,
      );
    }
    return Column(
      children: [
        renglon(nombres, u * CarnetLayout.letraNombres),
        SizedBox(height: u * CarnetLayout.espacioRenglon),
        renglon(apellidos, u * CarnetLayout.letraApellidos),
      ],
    );
  }

  Widget _banda({
    required double w,
    required double h,
    required double u,
    required Color color,
  }) {
    return Container(
      width: w,
      height: h * CarnetLayout.altoBanda,
      color: color,
      alignment: Alignment.center,
      padding: EdgeInsets.symmetric(horizontal: w * CarnetLayout.margenCargo),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          persona.cargo.trim().isEmpty ? '—' : persona.cargo.trim(),
          textAlign: TextAlign.center,
          maxLines: 2,
          style: TextStyle(
            fontFamily: _kFont,
            fontSize: u * CarnetLayout.letraCargo,
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  /// Pie: cédula y RH a la izquierda, QR a la derecha. Ver la nota de `_pie`
  /// en carnet_pdf.dart para por qué no van apilados como en el modelo.
  Widget _pie({required double w, required double h, required double u}) {
    final lado = u * CarnetLayout.ladoQr;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        w * CarnetLayout.margenPie,
        0,
        w * CarnetLayout.margenPie,
        h * CarnetLayout.margenInferior,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: _documento(u: u)),
          // El QR real lo dibuja el PDF. Aquí basta con reservar su sitio: esta
          // pantalla es para escoger colores, no para escanear.
          Container(
            width: lado,
            height: lado,
            decoration: BoxDecoration(
              color: _kPlaceholder,
              borderRadius: BorderRadius.circular(lado * 0.08),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.qr_code_2_rounded,
              size: lado * 0.78,
              color: _kPlaceholderTexto,
            ),
          ),
        ],
      ),
    );
  }

  Widget _documento({required double u}) {
    final estilo = TextStyle(
      fontFamily: _kFont,
      fontSize: u * CarnetLayout.letraDocumento,
      color: _kTexto,
    );
    final rh = persona.rh.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'CC: ${persona.cedula.trim()}',
          style: estilo,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (rh.isNotEmpty) ...[
          SizedBox(height: u * CarnetLayout.espacioRenglon),
          Text('RH: $rh', style: estilo, maxLines: 1),
        ],
      ],
    );
  }
}

/// Los arcos concéntricos de las esquinas.
///
/// El eje Y de Flutter crece hacia abajo y el del PDF hacia arriba: por eso el
/// `cy` de carnet_layout.dart se invierte aquí. Es la única diferencia entre
/// los dos dibujos, y está contenida en esta línea.
class _ArcosPainter extends CustomPainter {
  final Color primario;
  final Color secundario;

  const _ArcosPainter({required this.primario, required this.secundario});

  @override
  void paint(Canvas canvas, Size size) {
    _grupo(
      canvas,
      size,
      cxFrac: CarnetLayout.arcoSupCx,
      cyFrac: CarnetLayout.arcoSupCy,
      radioMin: CarnetLayout.arcoSupRadioMin,
      paso: CarnetLayout.arcoSupPaso,
      cuantos: CarnetLayout.arcoSupCuantos,
      a: secundario,
      b: primario,
    );
    _grupo(
      canvas,
      size,
      cxFrac: CarnetLayout.arcoInfCx,
      cyFrac: CarnetLayout.arcoInfCy,
      radioMin: CarnetLayout.arcoInfRadioMin,
      paso: CarnetLayout.arcoInfPaso,
      cuantos: CarnetLayout.arcoInfCuantos,
      a: primario,
      b: secundario,
    );
  }

  void _grupo(
    Canvas canvas,
    Size size, {
    required double cxFrac,
    required double cyFrac,
    required double radioMin,
    required double paso,
    required int cuantos,
    required Color a,
    required Color b,
  }) {
    final w = size.width;
    final centro = Offset(w * cxFrac, size.height * (1 - cyFrac));
    final pincel = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * CarnetLayout.arcoGrosor
      ..isAntiAlias = true;
    for (var i = 0; i < cuantos; i++) {
      pincel.color = i.isEven ? a : b;
      canvas.drawCircle(centro, w * (radioMin + paso * i), pincel);
    }
  }

  @override
  bool shouldRepaint(_ArcosPainter old) =>
      old.primario != primario || old.secundario != secundario;
}
