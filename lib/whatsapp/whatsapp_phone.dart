/// Mismo formato de normalización que `normalizePhone` del servidor.
String normalizarTelefonoWhatsApp(String valor, String codigoPais) {
  var numero = valor.replaceAll(RegExp(r'\D'), '');
  if (numero.startsWith('00')) numero = numero.substring(2);
  final codigo = codigoPais.replaceAll(RegExp(r'\D'), '');
  if (numero.length == 10 && codigo.isNotEmpty) numero = '$codigo$numero';
  return numero;
}

String ayudaTelefonoWhatsApp(String codigoPais) {
  final codigo = codigoPais.replaceAll(RegExp(r'\D'), '');
  return 'Guarda el número con código de país, solo dígitos: '
      '${codigo.isEmpty ? '57' : codigo}3001234567. '
      'Ejemplo Colombia: +57 300 123 4567 → 573001234567. '
      '${codigo.isEmpty ? '' : 'A un número local de 10 dígitos se le agrega $codigo. '}'
      'Para otro país escribe el número internacional completo.';
}

String? errorTelefonoWhatsApp(String valor, String codigoPais) {
  if (RegExp(r'[a-zA-Z]').hasMatch(valor)) {
    return 'Escribe un número, sin letras.';
  }
  final telefono = normalizarTelefonoWhatsApp(valor, codigoPais);
  if (telefono.length < 8 || telefono.length > 15) {
    return 'Revisa el número y su código de país (entre 8 y 15 dígitos).';
  }
  return null;
}
