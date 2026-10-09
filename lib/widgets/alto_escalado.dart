// lib/widgets/alto_escalado.dart
//
// Alto de tarjeta que crece con la escala de texto del dispositivo.
//
// Una rejilla con `childAspectRatio` fija da a cada tarjeta un alto que solo
// depende del ancho: en el teléfono (dos columnas) o con letra grande el texto
// no cabe y se corta o desborda. Las rejillas de tarjetas usan `mainAxisExtent`
// con este alto, como ya hace el Home.

import 'package:flutter/widgets.dart';

/// [base] es el alto que funciona con texto al 100 %. Se amplía en proporción a
/// la escala de texto, sin pasar de 1,8× para que una tarjeta no ocupe la
/// pantalla entera.
double altoEscalado(BuildContext context, double base) {
  final escala = MediaQuery.textScalerOf(context).scale(14) / 14;
  return base * escala.clamp(1.0, 1.8);
}
