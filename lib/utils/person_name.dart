/// Resuelve campos separados y padrones históricos sin repetir sus solapes.
/// No elimina palabras iguales: «Pérez Pérez» puede ser un apellido legítimo.
class PersonName {
  final String nombres;
  final String apellidos;

  const PersonName(this.nombres, this.apellidos);

  String get completo => '$nombres $apellidos'.trim();

  factory PersonName.fromMap(Map<String, dynamic> data) {
    String first(List<String> keys) {
      for (final key in keys) {
        final value = _clean(data[key]);
        if (value.isNotEmpty) return value;
      }
      return '';
    }

    final apellidos = _join(
      first(['primerApellido']),
      _clean(data['segundoApellido']),
    );
    var nombres = _join(first(['primerNombre']), _clean(data['segundoNombre']));
    final apellidoResuelto = first(['primerApellido']).isEmpty
        ? first(['apellidos', 'segundoApellido'])
        : apellidos;
    if (first(['primerNombre']).isEmpty) {
      nombres = first(['nombres', 'segundoNombre']);
    }
    if (nombres.isEmpty) {
      nombres = first(['nombreCompleto', 'nombre', 'name']);
    }
    // Algunos padrones guardan el nombre completo en «nombres» o «nombre».
    if (apellidoResuelto.isNotEmpty &&
        nombres.toLowerCase().endsWith(' ${apellidoResuelto.toLowerCase()}')) {
      nombres = nombres
          .substring(0, nombres.length - apellidoResuelto.length)
          .trim();
    }
    return PersonName(nombres, apellidoResuelto);
  }

  static String _clean(Object? value) =>
      (value ?? '').toString().trim().replaceAll(RegExp(r'\s+'), ' ');

  static String _join(String first, String second) {
    if (first.isEmpty) return second;
    if (second.isEmpty) return first;
    // Solo absorbe un segundo campo que ya está dentro de un primero compuesto.
    if (first.toLowerCase().endsWith(' ${second.toLowerCase()}')) return first;
    return '$first $second';
  }
}
