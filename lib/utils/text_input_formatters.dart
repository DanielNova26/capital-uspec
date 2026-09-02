import 'package:flutter/services.dart';

/// Fuerza MAYÚSCULAS mientras se escribe.
///
/// Vivía como clase privada en Compras. Se compartió porque la regla de
/// negocio es transversal: las notas y observaciones que van a un informe
/// deben salir en mayúsculas para que el reporte se lea homogéneo, sin
/// depender de cómo escribió cada persona.
///
/// Se aplica sobre el texto completo (no solo lo tecleado) para que un pegado
/// desde el portapapeles también quede normalizado.
class UpperCaseTextFormatter extends TextInputFormatter {
  const UpperCaseTextFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
      composing: TextRange.empty,
    );
  }
}

/// Deja cada palabra con inicial mayúscula y el resto en minúscula.
///
/// Además de los espacios, trata guiones y apóstrofes como separadores para
/// que nombres como `maría-josé` y `o'connor` queden bien formados. La función
/// también se usa en los servicios antes de persistir, de modo que la regla no
/// dependa únicamente del formulario desde el que se creó la persona.
String capitalizarPalabras(String input) {
  final lower = input.toLowerCase();
  final buffer = StringBuffer();
  final separadores = RegExp(r"[\s\-']");
  var capitalizarSiguiente = true;

  for (var index = 0; index < lower.length; index++) {
    final character = lower[index];
    final separador = separadores.hasMatch(character);
    if (separador) {
      buffer.write(character);
      capitalizarSiguiente = true;
      continue;
    }
    buffer.write(capitalizarSiguiente ? character.toUpperCase() : character);
    capitalizarSiguiente = false;
  }
  return buffer.toString();
}

/// Aplica [capitalizarPalabras] mientras se escribe o se pega un nombre.
class CapitalizedWordsTextFormatter extends TextInputFormatter {
  const CapitalizedWordsTextFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(
      text: capitalizarPalabras(newValue.text),
      selection: newValue.selection,
      composing: TextRange.empty,
    );
  }
}

/// Solo dígitos. `TextInputType.number` únicamente sugiere un teclado: en Web
/// y con teclado físico no impide escribir letras, y un "cantidad: 2a" llegaba
/// al parse como null.
final digitsOnlyFormatter = FilteringTextInputFormatter.digitsOnly;

/// Dígitos y separadores de miles/decimales, para importes que la gente
/// escribe con puntos o comas ("1.423.500"). La normalización a número la hace
/// [parseMontoColombiano].
final montoFormatter = FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'));

/// Agrupa de a tres desde la derecha con punto, como se escribe la moneda en
/// Colombia: `1423500` → `1.423.500`.
String agruparMiles(String digits) {
  if (digits.length <= 3) return digits;
  final buffer = StringBuffer();
  final resto = digits.length % 3;
  if (resto > 0) buffer.write(digits.substring(0, resto));
  for (var i = resto; i < digits.length; i += 3) {
    if (buffer.isNotEmpty) buffer.write('.');
    buffer.write(digits.substring(i, i + 3));
  }
  return buffer.toString();
}

/// Campo de dinero: descarta todo lo que no sea dígito y reagrupa en miles
/// **mientras se escribe**, así que el valor se lee como moneda desde el
/// primer momento en vez de quedar como `1423500`.
///
/// Solo enteros: los salarios del sector no llevan centavos y admitir decimales
/// obligaba a decidir si la coma separa miles o decimales — la misma
/// ambigüedad que hacía que un mismo sueldo se guardara de dos formas.
///
/// El cursor se reposiciona contando **dígitos**, no caracteres: al insertar un
/// separador el texto crece y mantener el desplazamiento crudo saltaba el
/// cursor una posición hacia atrás en cada millar.
class MonedaInputFormatter extends TextInputFormatter {
  const MonedaInputFormatter({this.maxDigitos = 12});

  /// Tope de seguridad. Doce dígitos son billones de pesos: más que eso es un
  /// error de digitación, no un salario.
  final int maxDigitos;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return const TextEditingValue();
    // Pasado el tope se conserva lo anterior: truncar en silencio deja al
    // usuario mirando un número que él no escribió.
    if (digits.length > maxDigitos) return oldValue;

    final formatted = agruparMiles(digits);
    final cursor = newValue.selection.end.clamp(0, newValue.text.length);
    final digitosAntes = newValue.text
        .substring(0, cursor)
        .replaceAll(RegExp(r'[^0-9]'), '')
        .length;

    var offset = 0;
    var vistos = 0;
    while (offset < formatted.length && vistos < digitosAntes) {
      if (formatted[offset] != '.') vistos++;
      offset++;
    }
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}

/// Convierte lo escrito en un campo de dinero a número.
///
/// Acepta las tres formas con las que la gente escribe un salario en Colombia
/// —`1423500`, `1.423.500`, `1,423,500`— tratando los separadores como miles.
/// Devuelve `null` si no queda ningún dígito, para poder distinguir "no lo
/// diligenciaron" de "vale cero".
num? parseMontoColombiano(String raw) {
  final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return null;
  return num.tryParse(digits);
}
