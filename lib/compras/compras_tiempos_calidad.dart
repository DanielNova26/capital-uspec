// lib/compras/compras_tiempos_calidad.dart
//
// Cronómetro de Calidad.
//
// Compras y Bodega cargan un documento y quedan a la espera de Calidad sin
// saber cuánto lleva esperando; Calidad tampoco ve cuánto lleva cada
// expediente en su bandeja. Aquí se calcula ese tiempo con lo que el
// documento ya guarda (`fechaSubida` y `fechaRevision`): no hace falta un
// campo nuevo ni un cron. Mientras el documento sigue pendiente el reloj corre
// en vivo; cuando Calidad decide, queda fijo en lo que tardó.

import 'dart:async';

import 'package:flutter/material.dart';

import 'compras_models.dart';

/// A partir de aquí la espera se pinta en rojo. Es orientativo: no bloquea
/// nada ni dispara alertas, solo hace visible lo que ya se demoró.
const Duration kEsperaCalidadAlerta = Duration(days: 3);

class TiempoCalidad {
  final DateTime inicio;

  /// null mientras Calidad no haya decidido.
  final DateTime? fin;

  const TiempoCalidad({required this.inicio, this.fin});

  bool get enCurso => fin == null;

  Duration transcurrido([DateTime? ahora]) {
    final hasta = fin ?? ahora ?? DateTime.now();
    final d = hasta.difference(inicio);
    return d.isNegative ? Duration.zero : d;
  }
}

/// Tiempo que un documento lleva (o tardó) en Calidad.
///
/// Devuelve null cuando no hay nada que medir: sin archivo, sin fecha de
/// carga, sin gestión de calidad, o decidido pero sin fecha de revisión.
TiempoCalidad? tiempoCalidadDocumento(DocAdjunto? doc) {
  if (doc == null || !doc.tieneDoc) return null;
  final subida = doc.fechaSubida?.toDate();
  if (subida == null) return null;
  if (doc.estadoCalidad.isEmpty) return null;

  final revision = doc.fechaRevision?.toDate();
  final decidido =
      doc.aprobado || doc.rechazado || doc.estadoCalidad == 'consultado';

  if (decidido) {
    if (revision == null) return null;
    return TiempoCalidad(
      inicio: subida,
      fin: revision.isBefore(subida) ? subida : revision,
    );
  }

  // Sigue en espera. Si Admin revirtió una aprobación, la espera arranca de
  // nuevo desde la reversión, no desde la carga original.
  final reversion = doc.fechaReversion?.toDate();
  final inicio = reversion != null && reversion.isAfter(subida)
      ? reversion
      : subida;
  return TiempoCalidad(inicio: inicio);
}

/// Tiempo de toda la recepción: desde el primer documento cargado hasta la
/// última decisión de Calidad. Basta un documento en espera para que el reloj
/// siga corriendo.
TiempoCalidad? tiempoCalidadRecepcion(RecepcionDoc recepcion) {
  DateTime? inicio;
  DateTime? fin;
  var enCurso = false;
  for (final producto in recepcion.productos) {
    for (final doc in producto.documentos.values) {
      final t = tiempoCalidadDocumento(doc);
      if (t == null) continue;
      if (inicio == null || t.inicio.isBefore(inicio)) inicio = t.inicio;
      if (t.enCurso) {
        enCurso = true;
      } else if (fin == null || t.fin!.isAfter(fin)) {
        fin = t.fin;
      }
    }
  }
  if (inicio == null) return null;
  return TiempoCalidad(inicio: inicio, fin: enCurso ? null : fin);
}

/// "45 min", "3 h 10 min", "2 d 4 h". Nunca segundos: nadie los necesita.
String formatearTiempoCalidad(Duration d) {
  if (d < const Duration(minutes: 1)) return 'menos de 1 min';
  final dias = d.inDays;
  final horas = d.inHours % 24;
  final minutos = d.inMinutes % 60;
  if (dias > 0) return horas > 0 ? '$dias d $horas h' : '$dias d';
  if (horas > 0) return minutos > 0 ? '$horas h $minutos min' : '$horas h';
  return '$minutos min';
}

/// Chip con el cronómetro. Mientras está en curso se refresca solo cada
/// minuto; una vez decidido no vuelve a cambiar.
class TiempoCalidadBadge extends StatefulWidget {
  final TiempoCalidad? tiempo;

  /// Texto corto para filas apretadas ("2 d 4 h" en vez de "En Calidad hace
  /// 2 d 4 h").
  final bool compacto;
  final double fontSize;

  const TiempoCalidadBadge({
    super.key,
    required this.tiempo,
    this.compacto = false,
    this.fontSize = 10.5,
  });

  @override
  State<TiempoCalidadBadge> createState() => _TiempoCalidadBadgeState();
}

class _TiempoCalidadBadgeState extends State<TiempoCalidadBadge> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _programar();
  }

  @override
  void didUpdateWidget(covariant TiempoCalidadBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    _programar();
  }

  void _programar() {
    _tick?.cancel();
    _tick = null;
    if (widget.tiempo?.enCurso == true) {
      _tick = Timer.periodic(const Duration(minutes: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tiempo;
    if (t == null) return const SizedBox.shrink();
    final transcurrido = t.transcurrido();
    final texto = formatearTiempoCalidad(transcurrido);

    final Color color;
    final IconData icono;
    final String label;
    if (t.enCurso) {
      final demorado = transcurrido >= kEsperaCalidadAlerta;
      color = demorado ? const Color(0xFFDC2626) : const Color(0xFFD97706);
      icono = Icons.timer_outlined;
      label = widget.compacto ? texto : 'En Calidad hace $texto';
    } else {
      color = const Color(0xFF15803D);
      icono = Icons.timer_rounded;
      label = widget.compacto ? texto : 'Calidad respondió en $texto';
    }

    return Tooltip(
      message: t.enCurso
          ? 'Tiempo desde que se cargó el documento y sigue sin decisión de Calidad'
          : 'Tiempo que tardó Calidad desde la carga hasta su decisión',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: widget.fontSize + 2, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Arial',
              fontSize: widget.fontSize,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
