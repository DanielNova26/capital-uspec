import 'package:flutter/material.dart';

import 'carnet_service.dart';

enum CarnetFiltroEstado { todos, con, sin }

class CarnetFiltros {
  final String consulta;
  final bool soloActivos;
  final bool soloAprobados;
  final CarnetFiltroEstado foto;
  final CarnetFiltroEstado carnet;

  const CarnetFiltros({
    this.consulta = '',
    this.soloActivos = true,
    this.soloAprobados = false,
    this.foto = CarnetFiltroEstado.todos,
    this.carnet = CarnetFiltroEstado.todos,
  });

  bool incluye(CarnetCandidato c) =>
      (!soloActivos || c.activo) &&
      (!soloAprobados || c.hojaAprobada) &&
      _coincide(foto, c.tieneFoto) &&
      _coincide(carnet, c.tieneCarnet) &&
      c.coincideCon(consulta);

  static bool _coincide(CarnetFiltroEstado filtro, bool valor) =>
      filtro == CarnetFiltroEstado.todos ||
      (filtro == CarnetFiltroEstado.con) == valor;
}

/// Controles que se acomodan al ancho real, también con texto aumentado.
class CarnetFiltrosBar extends StatelessWidget {
  final CarnetFiltroEstado foto;
  final CarnetFiltroEstado carnet;
  final ValueChanged<CarnetFiltroEstado> onFotoChanged;
  final ValueChanged<CarnetFiltroEstado> onCarnetChanged;

  const CarnetFiltrosBar({
    super.key,
    required this.foto,
    required this.carnet,
    required this.onFotoChanged,
    required this.onCarnetChanged,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _selector(
          ancho: constraints.maxWidth,
          etiqueta: 'Foto',
          valor: foto,
          textos: const ['Todas las fotos', 'Con foto', 'Sin foto'],
          onChanged: onFotoChanged,
        ),
        _selector(
          ancho: constraints.maxWidth,
          etiqueta: 'Carnet',
          valor: carnet,
          textos: const ['Todos los carnets', 'Con carnet', 'Sin carnet'],
          onChanged: onCarnetChanged,
        ),
      ],
    ),
  );

  Widget _selector({
    required double ancho,
    required String etiqueta,
    required CarnetFiltroEstado valor,
    required List<String> textos,
    required ValueChanged<CarnetFiltroEstado> onChanged,
  }) => SizedBox(
    width: ancho < 500 ? ancho : (ancho - 12) / 2,
    child: DropdownButtonFormField<CarnetFiltroEstado>(
      initialValue: valor,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: etiqueta,
        border: const OutlineInputBorder(),
      ),
      items: [
        for (final estado in CarnetFiltroEstado.values)
          DropdownMenuItem(value: estado, child: Text(textos[estado.index])),
      ],
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
    ),
  );
}
