// lib/widgets/skeleton.dart
//
// Esqueleto de carga: reemplaza al círculo centrado cuando una pantalla espera
// su primera lista. Muestra la forma del contenido (filas con avatar y dos
// líneas) para que la espera se perciba más corta y el diseño no salte al
// llegar los datos.
//
// Seguro en cualquier contenedor: con alto limitado reparte las filas que
// caben; con alto sin límite (dentro de una Column o un ListView) usa
// [filasPorDefecto]. Respeta "reducir movimiento" del sistema.

import 'package:flutter/material.dart';

class EsqueletoCarga extends StatefulWidget {
  const EsqueletoCarga({
    super.key,
    this.filasPorDefecto = 4,
    this.altoFila = 72,
  });

  /// Filas cuando el contenedor no limita el alto.
  final int filasPorDefecto;
  final double altoFila;

  @override
  State<EsqueletoCarga> createState() => _EsqueletoCargaState();
}

class _EsqueletoCargaState extends State<EsqueletoCarga>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulso = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  bool _animando = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final quieto = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (quieto && _animando) {
      _pulso.stop();
      _animando = false;
    } else if (!quieto && !_animando) {
      _pulso.repeat(reverse: true);
      _animando = true;
    }
  }

  @override
  void dispose() {
    _pulso.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.09);
    Widget barra(double? ancho, double alto) => Container(
      width: ancho,
      height: alto,
      decoration: BoxDecoration(
        color: base,
        borderRadius: BorderRadius.circular(6),
      ),
    );
    return Semantics(
      label: 'Cargando',
      container: true,
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, c) {
            final acotado = c.hasBoundedHeight;
            final filas = acotado
                ? ((c.maxHeight - 32) / widget.altoFila).floor().clamp(1, 8)
                : widget.filasPorDefecto;
            final contenido = Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < filas; i++)
                  SizedBox(
                    height: widget.altoFila,
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: base,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              FractionallySizedBox(
                                widthFactor: i.isEven ? 0.62 : 0.48,
                                child: barra(null, 14),
                              ),
                              const SizedBox(height: 9),
                              FractionallySizedBox(
                                widthFactor: 0.86,
                                child: barra(null, 11),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            );
            return ClipRect(
              child: FadeTransition(
                opacity: Tween<double>(begin: 0.45, end: 1).animate(_pulso),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  // Sin desbordes aunque el espacio sea menor que una fila.
                  child: acotado
                      ? SingleChildScrollView(
                          physics: const NeverScrollableScrollPhysics(),
                          child: contenido,
                        )
                      : contenido,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
