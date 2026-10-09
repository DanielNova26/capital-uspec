// lib/widgets/acciones_de_fila.dart
//
// Botones de acción al final de una fila de lista (ver, editar, eliminar).
//
// Tres `IconButton` ocupan unos 144 px: en el teléfono dejan al nombre de la
// fila con poco más de 100 px. Por debajo de [kAnchoAccionesEnLinea] los
// botones pasan a un solo menú; en ancho amplio se muestran como siempre.

import 'package:flutter/material.dart';

/// Ancho de pantalla desde el cual las acciones van en línea.
const double kAnchoAccionesEnLinea = 520;

/// Devuelve [botones] tal cual en ancho amplio, o un único menú con las mismas
/// acciones (icono, texto del tooltip y `onPressed`) en pantallas angostas.
/// Un botón sin `onPressed` aparece desactivado en el menú.
List<Widget> accionesDeFila(BuildContext context, List<IconButton> botones) {
  if (MediaQuery.sizeOf(context).width >= kAnchoAccionesEnLinea ||
      botones.length < 2) {
    return botones;
  }
  return [
    PopupMenuButton<int>(
      tooltip: 'Acciones',
      icon: const Icon(Icons.more_vert, color: Color(0xFF64748B)),
      onSelected: (i) => botones[i].onPressed?.call(),
      itemBuilder: (_) => [
        for (var i = 0; i < botones.length; i++)
          PopupMenuItem<int>(
            value: i,
            enabled: botones[i].onPressed != null,
            child: Row(
              children: [
                IconTheme.merge(
                  data: const IconThemeData(size: 20),
                  child: botones[i].icon,
                ),
                const SizedBox(width: 12),
                Flexible(child: Text(botones[i].tooltip ?? 'Acción')),
              ],
            ),
          ),
      ],
    ),
  ];
}
