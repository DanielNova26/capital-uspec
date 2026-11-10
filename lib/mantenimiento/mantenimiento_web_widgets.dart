import 'package:flutter/material.dart';

import 'mantenimiento_service.dart';

const mantenimientoTinta = Color(0xFF153044);
const mantenimientoAcento = Color(0xFF0F766E);
const mantenimientoFondo = Color(0xFFF2F7F7);
const mantenimientoBorde = Color(0xFFD7E4E7);

const _abierta = Color(0xFF9A4B0E);
const _enCurso = Color(0xFF2459A6);
const _cerrada = Color(0xFF117052);

Color colorEstadoMantenimiento(EstadoOrden estado) => switch (estado) {
  EstadoOrden.abierta => _abierta,
  EstadoOrden.enCurso => _enCurso,
  EstadoOrden.cerrada => _cerrada,
};

IconData iconoEstadoMantenimiento(EstadoOrden estado) => switch (estado) {
  EstadoOrden.abierta => Icons.pending_actions_rounded,
  EstadoOrden.enCurso => Icons.construction_rounded,
  EstadoOrden.cerrada => Icons.check_circle_outline_rounded,
};

class SelloMantenimiento extends StatelessWidget {
  const SelloMantenimiento({
    super.key,
    required this.texto,
    required this.color,
    this.icono,
  });

  final String texto;
  final Color color;
  final IconData? icono;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Color.alphaBlend(color.withValues(alpha: .10), Colors.white),
      borderRadius: BorderRadius.circular(20),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    child: Wrap(
      spacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (icono != null) Icon(icono, color: color, size: 16),
        Text(
          texto,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class PanelMantenimiento extends StatelessWidget {
  const PanelMantenimiento({
    super.key,
    required this.child,
    this.onTap,
    this.seleccionado = false,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final VoidCallback? onTap;
  final bool seleccionado;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Material(
    color: seleccionado ? const Color(0xFFE6F5F2) : Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(
        color: seleccionado ? mantenimientoAcento : mantenimientoBorde,
      ),
    ),
    clipBehavior: Clip.antiAlias,
    child: onTap == null
        ? Padding(padding: padding, child: child)
        : InkWell(
            onTap: onTap,
            child: Padding(padding: padding, child: child),
          ),
  );
}

class EncabezadoMantenimiento extends StatelessWidget {
  const EncabezadoMantenimiento({
    super.key,
    required this.titulo,
    required this.descripcion,
    required this.icono,
  });

  final String titulo, descripcion;
  final IconData icono;

  @override
  Widget build(BuildContext context) {
    final textos = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconoMantenimiento(icono: icono),
        const SizedBox(height: 10),
        Text(
          titulo,
          style: textos.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: mantenimientoTinta,
          ),
        ),
        const SizedBox(height: 4),
        Text(descripcion, style: textos.bodyMedium),
      ],
    );
  }
}

class IconoMantenimiento extends StatelessWidget {
  const IconoMantenimiento({
    super.key,
    required this.icono,
    this.color = mantenimientoAcento,
  });

  final IconData icono;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 40,
    height: 40,
    decoration: BoxDecoration(
      color: Color.alphaBlend(color.withValues(alpha: .10), Colors.white),
      borderRadius: BorderRadius.circular(12),
    ),
    alignment: Alignment.center,
    child: Icon(icono, color: color, size: 22),
  );
}

class TarjetaRutaMantenimiento extends StatelessWidget {
  const TarjetaRutaMantenimiento({
    super.key,
    required this.titulo,
    required this.descripcion,
    required this.icono,
    required this.color,
    required this.onTap,
    this.indicador,
    required this.compacta,
  });

  final String titulo, descripcion;
  final IconData icono;
  final Color color;
  final VoidCallback onTap;
  final String? indicador;
  final bool compacta;

  @override
  Widget build(BuildContext context) {
    final textos = Theme.of(context).textTheme;
    final nombre = Text(
      titulo,
      style: textos.titleMedium?.copyWith(
        color: mantenimientoTinta,
        fontWeight: FontWeight.w800,
      ),
    );
    final detalle = Text(descripcion, style: textos.bodyMedium);
    final contador = indicador == null
        ? null
        : Text(
            indicador!,
            style: textos.headlineSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          );
    final marca = IconoMantenimiento(icono: icono, color: color);
    const flecha = Icon(Icons.arrow_forward_rounded, size: 19);
    return PanelMantenimiento(
      onTap: onTap,
      child: compacta
          ? Row(
              children: [
                marca,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [nombre, detalle],
                  ),
                ),
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 72),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: contador ?? flecha,
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [marca, flecha],
                ),
                const SizedBox(height: 10),
                ?contador,
                nombre,
                const SizedBox(height: 4),
                detalle,
              ],
            ),
    );
  }
}
