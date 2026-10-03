import 'package:flutter/material.dart';

import 'paged_list.dart';

const String _kFont = 'Arial';

/// Columnas de la grilla de tareas según el ancho lógico disponible.
///
/// 3 oct 2026 ("colocar las tareas en una grilla que ocupe 3 columnas de
/// ancho"): tres en un portátil de 14" o un monitor, dos en uno de 10" o una
/// tableta, una en el teléfono.
int taskGridColumnas(double ancho) {
  if (ancho >= 1100) return 3;
  if (ancho >= 720) return 2;
  return 1;
}

/// Tarjetas de tareas en grilla, 20 por página ([kPageSize]), con
/// encabezados de grupo opcionales.
///
/// Las tarjetas de una misma fila quedan con el mismo alto. Al agrupar, la
/// lista debe venir ordenada por grupo: la grilla corta la página y pone un
/// encabezado cada vez que cambia el grupo.
class TaskCardGrid<T> extends StatelessWidget {
  final List<T> items;
  final Widget Function(BuildContext context, T item, bool compact) itemBuilder;
  final int page;
  final ValueChanged<int> onPageChanged;

  /// Clave del grupo de cada elemento; sin ella no hay encabezados.
  final String Function(T item)? grupoDe;
  final String Function(String clave)? nombreGrupo;
  final String etiqueta;
  final double maxWidth;

  const TaskCardGrid({
    super.key,
    required this.items,
    required this.itemBuilder,
    required this.page,
    required this.onPageChanged,
    this.grupoDe,
    this.nombreGrupo,
    this.etiqueta = 'tareas',
    this.maxWidth = 1180,
  });

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 900;
    final horizontal = isWide ? 20.0 : 12.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final disponible =
            (constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : MediaQuery.sizeOf(context).width) -
            horizontal * 2;
        final ancho = disponible.clamp(0.0, maxWidth).toDouble();
        final columnas = taskGridColumnas(ancho);
        final compact = true;

        final paginas = pageCountOf(items.length);
        final actual = page.clamp(0, paginas - 1);
        final pagina = pageOf(items, actual);

        final totalPorGrupo = <String, int>{};
        if (grupoDe != null) {
          for (final item in items) {
            final clave = grupoDe!(item);
            totalPorGrupo[clave] = (totalPorGrupo[clave] ?? 0) + 1;
          }
        }

        final bloques = <Widget>[];
        var fila = <T>[];
        String? grupo;
        void cerrarFila() {
          if (fila.isEmpty) return;
          bloques.add(_fila(context, fila, columnas, compact));
          fila = <T>[];
        }

        for (final item in pagina) {
          if (grupoDe != null) {
            final clave = grupoDe!(item);
            if (clave != grupo) {
              cerrarFila();
              grupo = clave;
              bloques.add(
                _encabezado(
                  nombreGrupo?.call(clave) ?? clave,
                  totalPorGrupo[clave] ?? 0,
                ),
              );
            }
          }
          fila.add(item);
          if (fila.length == columnas) cerrarFila();
        }
        cerrarFila();

        if (items.length > kPageSize) {
          bloques.add(
            PagerBar(
              total: items.length,
              page: actual,
              onPageChanged: onPageChanged,
              etiqueta: etiqueta,
            ),
          );
        }

        return ListView(
          padding: EdgeInsets.fromLTRB(horizontal, 14, horizontal, 24),
          children: [
            for (final bloque in bloques)
              Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: bloque,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _fila(BuildContext context, List<T> fila, int columnas, bool compact) {
    if (columnas == 1) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: itemBuilder(context, fila.first, compact),
      );
    }
    final hijos = <Widget>[];
    for (var i = 0; i < columnas; i++) {
      if (i > 0) hijos.add(const SizedBox(width: 12));
      hijos.add(
        Expanded(
          child: i < fila.length
              ? itemBuilder(context, fila[i], compact)
              : const SizedBox.shrink(),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: hijos,
        ),
      ),
    );
  }

  Widget _encabezado(String nombre, int total) {
    // El nombre no es flexible: si lo fuera, la línea solo tomaría la mitad
    // del espacio libre. Se le pone tope para que quepan el total y la línea.
    return LayoutBuilder(
      builder: (context, constraints) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 10, 4, 10),
        child: Row(
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: (constraints.maxWidth - 90).clamp(40.0, 600.0),
              ),
              child: Text(
                nombre.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: _kFont,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                  color: Colors.blueGrey,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.blueGrey.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$total',
                style: const TextStyle(
                  fontFamily: _kFont,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                  color: Colors.blueGrey,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Expanded(child: Divider(height: 1)),
          ],
        ),
      ),
    );
  }
}
