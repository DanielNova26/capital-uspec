// lib/widgets/paged_list.dart
//
// Paginación de listados largos, una sola vez para toda la app.
//
// Regla acordada: un listado extenso no se pinta completo. Se muestran 20
// elementos y se navega por páginas. Evita pantallas de miles de filas (lentas
// y difíciles de leer) y deja el mismo control en todos los módulos.
//
// Uso típico dentro de un StatefulWidget que ya tiene su lista filtrada:
//
//   PagedListSection<Persona>(
//     items: filtradas,
//     itemBuilder: (context, p, i) => _fila(p),
//   )
//
// Cuando la pantalla ya arma sus propias filas (una `DataTable`, una rejilla)
// y solo necesita el corte, usa [pageOf] + [PagerBar].

import 'package:flutter/material.dart';

const String _kFont = 'Arial';

/// Elementos por página en toda la app.
const int kPageSize = 20;

/// Recorta una lista a la página pedida. Útil cuando la pantalla ya tiene su
/// propio armado de filas y solo necesita el corte.
List<T> pageOf<T>(List<T> items, int page, {int pageSize = kPageSize}) {
  if (items.isEmpty) return const [];
  final start = (page * pageSize).clamp(0, items.length);
  final end = (start + pageSize).clamp(0, items.length);
  return items.sublist(start, end);
}

int pageCountOf(int total, {int pageSize = kPageSize}) {
  if (total <= 0) return 1;
  return (total / pageSize).ceil();
}

/// Barra de paginación: "1-20 de 137" con anterior/siguiente.
class PagerBar extends StatelessWidget {
  final int total;
  final int page;
  final int pageSize;
  final ValueChanged<int> onPageChanged;

  /// Nombre de lo que se está listando, para el texto ("cargos", "usuarios").
  final String etiqueta;

  const PagerBar({
    super.key,
    required this.total,
    required this.page,
    required this.onPageChanged,
    this.pageSize = kPageSize,
    this.etiqueta = 'registros',
  });

  @override
  Widget build(BuildContext context) {
    final paginas = pageCountOf(total, pageSize: pageSize);
    final desde = total == 0 ? 0 : page * pageSize + 1;
    final hasta = ((page + 1) * pageSize).clamp(0, total);
    final scheme = Theme.of(context).colorScheme;

    final texto = Text(
      '$desde-$hasta de $total $etiqueta',
      style: TextStyle(
        fontFamily: _kFont,
        fontSize: 12,
        color: scheme.onSurfaceVariant,
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Dentro de un scroll horizontal el ancho es infinito y un hijo con
          // flex revienta el layout: ahí la fila se encoge al contenido.
          final acotado = constraints.maxWidth.isFinite;
          return Row(
            mainAxisSize: acotado ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (acotado) Expanded(child: texto) else texto,
              IconButton(
                tooltip: 'Página anterior',
                visualDensity: VisualDensity.compact,
                onPressed: page == 0 ? null : () => onPageChanged(page - 1),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Text(
                '${page + 1}/$paginas',
                style: const TextStyle(
                  fontFamily: _kFont,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              IconButton(
                tooltip: 'Página siguiente',
                visualDensity: VisualDensity.compact,
                onPressed: page + 1 >= paginas
                    ? null
                    : () => onPageChanged(page + 1),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Envuelve una `DataTable` para que muestre 20 filas por página.
///
/// Guarda la página por dentro, así que sirve igual dentro de un
/// `StatelessWidget`: en el sitio de uso solo hay que envolver la tabla.
///
///   PagedDataTable(tabla: DataTable(columns: …, rows: …))
///
/// Reconstruye la tabla con las filas de la página y conserva el resto de
/// propiedades tal como venían.
class PagedDataTable extends StatefulWidget {
  final DataTable tabla;
  final int pageSize;
  final String etiqueta;

  const PagedDataTable({
    super.key,
    required this.tabla,
    this.pageSize = kPageSize,
    this.etiqueta = 'filas',
  });

  @override
  State<PagedDataTable> createState() => _PagedDataTableState();
}

class _PagedDataTableState extends State<PagedDataTable> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final t = widget.tabla;
    final total = t.rows.length;
    final maxPage = pageCountOf(total, pageSize: widget.pageSize) - 1;
    final page = _page.clamp(0, maxPage < 0 ? 0 : maxPage);
    final visibles = pageOf(t.rows, page, pageSize: widget.pageSize);

    final tabla = DataTable(
      key: t.key,
      columns: t.columns,
      sortColumnIndex: t.sortColumnIndex,
      sortAscending: t.sortAscending,
      onSelectAll: t.onSelectAll,
      decoration: t.decoration,
      dataRowColor: t.dataRowColor,
      dataRowMinHeight: t.dataRowMinHeight,
      dataRowMaxHeight: t.dataRowMaxHeight,
      dataTextStyle: t.dataTextStyle,
      headingRowColor: t.headingRowColor,
      headingRowHeight: t.headingRowHeight,
      headingTextStyle: t.headingTextStyle,
      horizontalMargin: t.horizontalMargin,
      columnSpacing: t.columnSpacing,
      showCheckboxColumn: t.showCheckboxColumn,
      showBottomBorder: t.showBottomBorder,
      dividerThickness: t.dividerThickness,
      rows: visibles,
      checkboxHorizontalMargin: t.checkboxHorizontalMargin,
      border: t.border,
      clipBehavior: t.clipBehavior,
    );

    if (total <= widget.pageSize) return tabla;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        tabla,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: PagerBar(
            total: total,
            page: page,
            pageSize: widget.pageSize,
            etiqueta: widget.etiqueta,
            onPageChanged: (p) => setState(() => _page = p),
          ),
        ),
      ],
    );
  }
}

/// Lista paginada lista para usar: pinta 20 elementos y su barra de páginas.
///
/// No hace scroll propio (`shrinkWrap`): está pensada para vivir dentro de la
/// columna que ya scrollea la pantalla.
class PagedListSection<T> extends StatefulWidget {
  final List<T> items;
  final Widget Function(BuildContext context, T item, int indexGlobal)
  itemBuilder;
  final int pageSize;
  final String etiqueta;
  final Widget? separator;

  /// Si el total no supera esto, no se muestra la barra de páginas.
  final bool ocultarBarraSiCabe;

  const PagedListSection({
    super.key,
    required this.items,
    required this.itemBuilder,
    this.pageSize = kPageSize,
    this.etiqueta = 'registros',
    this.separator,
    this.ocultarBarraSiCabe = true,
  });

  @override
  State<PagedListSection<T>> createState() => _PagedListSectionState<T>();
}

class _PagedListSectionState<T> extends State<PagedListSection<T>> {
  int _page = 0;

  @override
  void didUpdateWidget(PagedListSection<T> old) {
    super.didUpdateWidget(old);
    // Si la lista se acortó (cambió un filtro) la página actual puede quedar
    // fuera de rango: se vuelve a la última válida.
    final maxPage =
        pageCountOf(widget.items.length, pageSize: widget.pageSize) - 1;
    if (_page > maxPage) _page = maxPage < 0 ? 0 : maxPage;
  }

  @override
  Widget build(BuildContext context) {
    final visibles = pageOf(widget.items, _page, pageSize: widget.pageSize);
    final desde = _page * widget.pageSize;
    final mostrarBarra =
        !widget.ocultarBarraSiCabe || widget.items.length > widget.pageSize;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < visibles.length; i++) ...[
          widget.itemBuilder(context, visibles[i], desde + i),
          if (widget.separator != null && i < visibles.length - 1)
            widget.separator!,
        ],
        if (mostrarBarra)
          PagerBar(
            total: widget.items.length,
            page: _page,
            pageSize: widget.pageSize,
            etiqueta: widget.etiqueta,
            onPageChanged: (p) => setState(() => _page = p),
          ),
      ],
    );
  }
}
