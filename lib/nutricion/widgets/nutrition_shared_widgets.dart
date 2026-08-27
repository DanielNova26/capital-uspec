// lib/nutricion/widgets/nutrition_shared_widgets.dart

import 'package:flutter/material.dart';
import 'package:todo/theme/app_typography.dart';

/// Paleta enterprise para nutrición clínica
class NutritionPalette {
  static const Color primary = Color(0xFF0F172A); // Slate 900
  static const Color secondary = Color(0xFF334155); // Slate 700
  static const Color accent = Color(0xFF2563EB); // Blue 600
  static const Color surface = Colors.white;
  static const Color background = Color(0xFFF8FAFC); // Slate 50
  static const Color border = Color(0xFFE2E8F0); // Slate 200
  static const Color textMain = Color(0xFF1E293B); // Slate 800
  static const Color textMuted = Color(0xFF64748B); // Slate 500

  // Colores de estado clínico
  static const Color success = Color(0xFF10B981); // Emerald 500
  static const Color warning = Color(0xFFF59E0B); // Amber 500
  static const Color danger = Color(0xFFEF4444); // Red 500
  static const Color info = Color(0xFF0EA5E9); // Sky 500
}

/// Tag clínico para estados y categorías
class ClinicalTag extends StatelessWidget {
  final String label;
  final Color color;
  final bool isCompact;

  const ClinicalTag({
    super.key,
    required this.label,
    required this.color,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 8 : 12,
        vertical: isCompact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: isCompact ? 9 : 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
          fontFamily: kArial,
        ),
      ),
    );
  }
}

/// Indicador de pasos profesional y sobrio
class NutritionStepIndicator extends StatelessWidget {
  final int currentStep;
  final List<String> steps;
  final List<IconData> icons;
  final Function(int) onStepTap;

  const NutritionStepIndicator({
    super.key,
    required this.currentStep,
    required this.steps,
    required this.icons,
    required this.onStepTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: const BoxDecoration(
        color: NutritionPalette.surface,
        border: Border(bottom: BorderSide(color: NutritionPalette.border)),
      ),
      child: Row(
        children: List.generate(steps.length, (index) {
          final isActive = index <= currentStep;
          final isCurrent = index == currentStep;

          return Expanded(
            child: InkWell(
              onTap: () => onStepTap(index),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Divider(
                          color: index == 0 ? Colors.transparent : (isActive ? NutritionPalette.accent : NutritionPalette.border),
                          thickness: 2,
                        ),
                      ),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: isCurrent ? NutritionPalette.accent : (isActive ? NutritionPalette.accent.withValues(alpha: 0.1) : NutritionPalette.surface),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isActive ? NutritionPalette.accent : NutritionPalette.border,
                            width: 2,
                          ),
                          boxShadow: isCurrent ? [
                            BoxShadow(
                              color: NutritionPalette.accent.withValues(alpha: 0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            )
                          ] : null,
                        ),
                        child: Icon(
                          icons[index],
                          size: 18,
                          color: isCurrent ? Colors.white : (isActive ? NutritionPalette.accent : NutritionPalette.textMuted),
                        ),
                      ),
                      Expanded(
                        child: Divider(
                          color: index == steps.length - 1 ? Colors.transparent : (index < currentStep ? NutritionPalette.accent : NutritionPalette.border),
                          thickness: 2,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    steps[index],
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                      color: isCurrent ? NutritionPalette.textMain : NutritionPalette.textMuted,
                      fontFamily: kArial,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// Header profesional para Web
class NutritionWebHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget>? actions;

  const NutritionWebHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 24),
      decoration: const BoxDecoration(
        color: NutritionPalette.surface,
        border: Border(bottom: BorderSide(color: NutritionPalette.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: NutritionPalette.accent,
                    fontFamily: kArial,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: NutritionPalette.textMain,
                    fontFamily: kArial,
                  ),
                ),
              ],
            ),
          ),
          if (actions != null) ...[
            const SizedBox(width: 16),
            ...actions!,
          ],
        ],
      ),
    );
  }
}

/// Card enterprise base
class NutritionCard extends StatelessWidget {
  final Widget child;
  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsetsGeometry? padding;
  final Color? headerColor;

  const NutritionCard({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.trailing,
    this.padding,
    this.headerColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: NutritionPalette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: NutritionPalette.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
              decoration: BoxDecoration(
                color: headerColor ?? NutritionPalette.surface,
                border: const Border(bottom: BorderSide(color: NutritionPalette.border)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title!,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: headerColor != null ? Colors.white : NutritionPalette.textMain,
                            fontFamily: kArial,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            style: TextStyle(
                              fontSize: 12,
                              color: headerColor != null ? Colors.white.withValues(alpha: 0.8) : NutritionPalette.textMuted,
                              fontFamily: kArial,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
            ),
          ],
          Padding(
            padding: padding ?? const EdgeInsets.all(24),
            child: child,
          ),
        ],
      ),
    );
  }
}

/// Card informativo compacto
class NutritionInfoCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const NutritionInfoCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NutritionPalette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: NutritionPalette.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 11,
                    color: NutritionPalette.textMuted,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: NutritionPalette.textMain,
                    fontFamily: kArial,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
