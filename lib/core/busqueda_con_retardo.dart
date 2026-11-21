// lib/core/busqueda_con_retardo.dart
//
// Retardo (debounce) para campos de búsqueda y autocompletado.
//
// Antes cada pulsación hacía `setState` y reconstruía pantallas enormes y
// refiltraba listas completas. Con el retardo se aplica solo el último texto
// cuando la persona deja de escribir. El campo sigue mostrando lo que se
// escribe al instante: solo se retrasa el filtrado.
//
//   onChanged: debounceBusqueda(this, (v) => setState(() => _q = v)),

import 'dart:async';

import 'package:flutter/widgets.dart';

const Duration kRetardoBusqueda = Duration(milliseconds: 300);

final Expando<Timer> _pendientes = Expando<Timer>('busqueda_con_retardo');

/// Devuelve un `onChanged` que aplica [alCambiar] 300 ms después de la última
/// pulsación. Si la pantalla se cierra antes, no hace nada.
ValueChanged<String> debounceBusqueda(
  State estado,
  ValueChanged<String> alCambiar, {
  Duration retardo = kRetardoBusqueda,
}) {
  return (texto) {
    _pendientes[estado]?.cancel();
    _pendientes[estado] = Timer(retardo, () {
      if (estado.mounted) alCambiar(texto);
    });
  };
}
