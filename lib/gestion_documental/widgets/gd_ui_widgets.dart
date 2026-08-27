// lib/gestion_documental/widgets/gd_ui_widgets.dart

import 'package:flutter/material.dart';
import '../gd_models.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PALETA DOCUMENTAL (Premium Slate/Blue)
// ─────────────────────────────────────────────────────────────────────────────

class GdPalette {
  static const Color background = Color(0xFFF8FAFC); // Slate 50
  static const Color primary = Color(0xFF0F172A);    // Slate 900
  static const Color accent = Color(0xFF3B82F6);     // Blue 500
  static const Color border = Color(0xFFE2E8F0);     // Slate 200
  static const Color muted = Color(0xFF64748B);      // Slate 500
  static const Color success = Color(0xFF10B981);    // Emerald 500
  static const Color warning = Color(0xFFF59E0B);    // Amber 500
  static const Color error = Color(0xFFEF4444);      // Red 500
  static const Color surface = Colors.white;
}

const String kArial = 'Arial';

// ─────────────────────────────────────────────────────────────────────────────
// BADGES DE ESTADO
// ─────────────────────────────────────────────────────────────────────────────

class GdStatusBadge extends StatelessWidget {
  final GdEstado estado;
  final bool isVigente;

  const GdStatusBadge({
    super.key,
    required this.estado,
    this.isVigente = false,
  });

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color text;
    IconData icon;

    if (isVigente) {
      bg = GdPalette.primary;
      text = Colors.white;
      icon = Icons.verified;
    } else {
      switch (estado) {
        case GdEstado.borrador:
          bg = GdPalette.muted.withValues(alpha: 0.1);
          text = GdPalette.muted;
          icon = Icons.edit_note;
          break;
        case GdEstado.en_revision:
          bg = GdPalette.accent.withValues(alpha: 0.1);
          text = GdPalette.accent;
          icon = Icons.visibility;
          break;
        case GdEstado.observado:
          bg = GdPalette.warning.withValues(alpha: 0.1);
          text = GdPalette.warning;
          icon = Icons.rule;
          break;
        case GdEstado.aprobado:
          bg = GdPalette.success.withValues(alpha: 0.1);
          text = GdPalette.success;
          icon = Icons.check_circle_outline;
          break;
        case GdEstado.firmado:
          bg = GdPalette.success.withValues(alpha: 0.2);
          text = GdPalette.success;
          icon = Icons.draw;
          break;
        case GdEstado.vigente:
          bg = GdPalette.primary;
          text = Colors.white;
          icon = Icons.verified;
          break;
        case GdEstado.obsoleto:
          bg = GdPalette.muted.withValues(alpha: 0.05);
          text = GdPalette.muted;
          icon = Icons.history;
          break;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: text.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: text),
          const SizedBox(width: 6),
          Text(
            isVigente ? 'VIGENTE' : estado.etiqueta.toUpperCase(),
            style: TextStyle(
              fontFamily: kArial,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: text,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CARDS BASE
// ─────────────────────────────────────────────────────────────────────────────

class GdCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final Color? color;
  final Border? border;

  const GdCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.color,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color ?? GdPalette.surface,
        borderRadius: BorderRadius.circular(12),
        border: border ?? Border.all(color: GdPalette.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: padding ?? const EdgeInsets.all(16),
            child: child,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION HEADER
// ─────────────────────────────────────────────────────────────────────────────

class GdSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;

  const GdSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: kArial,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: GdPalette.primary,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      fontFamily: kArial,
                      fontSize: 12,
                      color: GdPalette.muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TIMELINE ITEM
// ─────────────────────────────────────────────────────────────────────────────

class GdTimelineItem extends StatelessWidget {
  final String title;
  final String actor;
  final String date;
  final String? comment;
  final bool isFirst;
  final bool isLast;
  final GdAccion? accion;

  const GdTimelineItem({
    super.key,
    required this.title,
    required this.actor,
    required this.date,
    this.comment,
    this.isFirst = false,
    this.isLast = false,
    this.accion,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Line and dot
          Column(
            children: [
              Container(
                width: 2,
                height: 12,
                color: isFirst ? Colors.transparent : GdPalette.border,
              ),
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: _colorForAccion(accion),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
              Expanded(
                child: Container(
                  width: 2,
                  color: isLast ? Colors.transparent : GdPalette.border,
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          // Content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontFamily: kArial,
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                            color: GdPalette.primary,
                          ),
                        ),
                      ),
                      Text(
                        date,
                        style: const TextStyle(
                          fontFamily: kArial,
                          fontSize: 11,
                          color: GdPalette.muted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.person_outline, size: 12, color: GdPalette.muted),
                      const SizedBox(width: 4),
                      Text(
                        actor,
                        style: const TextStyle(
                          fontFamily: kArial,
                          fontSize: 12,
                          color: GdPalette.muted,
                        ),
                      ),
                    ],
                  ),
                  if (comment != null && comment!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: GdPalette.background,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: GdPalette.border),
                      ),
                      child: Text(
                        comment!,
                        style: const TextStyle(
                          fontFamily: kArial,
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: GdPalette.primary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _colorForAccion(GdAccion? a) {
    if (a == null) return GdPalette.muted;
    switch (a) {
      case GdAccion.aprobado:
      case GdAccion.firmado:
      case GdAccion.marcado_vigente:
        return GdPalette.success;
      case GdAccion.observado:
      case GdAccion.marcado_obsoleto:
        return GdPalette.error;
      case GdAccion.enviado_revision:
      case GdAccion.reenviado:
        return GdPalette.accent;
      default:
        return GdPalette.muted;
    }
  }
}
