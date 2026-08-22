import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

const String kArial = 'Arial';

// Color del módulo de tareas — alineado con create/complete_task_screen
const Color kTaskAccent = Color(0xFF145DA0);

/// Mantiene los paneles secundarios del módulo de tareas centrados y con un
/// ancho legible en escritorio, sin comprimir la experiencia móvil.
BoxConstraints taskPanelConstraints(
  BuildContext context, {
  double desktopMaxWidth = 960,
}) {
  final width = MediaQuery.sizeOf(context).width;
  return BoxConstraints(
    maxWidth: kIsWeb && width >= 900 ? desktopMaxWidth : width,
  );
}

double taskPanelHeight(
  BuildContext context, {
  double mobileFraction = 0.72,
  double desktopMaxHeight = 640,
}) {
  final media = MediaQuery.of(context);
  if (!(kIsWeb && media.size.width >= 900)) {
    return media.size.height * mobileFraction;
  }
  final available = media.size.height * 0.76;
  return available < desktopMaxHeight ? available : desktopMaxHeight;
}

/// Cabecera común para paneles de detalle, novedades, avances y adjuntos.
/// El cierre permanece visible sin depender del gesto de arrastre ni de tocar
/// fuera del panel.
class TaskPanelHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final String? eyebrow;
  final VoidCallback? onBack;
  final VoidCallback? onClose;

  const TaskPanelHeader({
    super.key,
    required this.title,
    this.trailing,
    this.eyebrow,
    this.onBack,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (onBack != null) ...[
            IconButton(
              tooltip: 'Volver al panel anterior',
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (eyebrow != null) ...[
                  Text(
                    eyebrow!,
                    style: const TextStyle(
                      fontFamily: kArial,
                      fontWeight: FontWeight.w900,
                      fontSize: 10,
                      color: Color(0xFF64748B),
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: kArial,
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 12),
            Padding(padding: const EdgeInsets.only(top: 8), child: trailing!),
          ],
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Cerrar panel',
            onPressed: onClose ?? () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

class TaskResponsiveLayout extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? header;
  final Widget? filters;
  final Widget content;
  final List<Widget>? actions;
  final bool showFiltersOnSidebar;
  final bool useScaffold;
  final PreferredSizeWidget? appBar;
  final Widget? detailPanel;

  const TaskResponsiveLayout({
    super.key,
    required this.title,
    this.subtitle,
    this.header,
    this.filters,
    required this.content,
    this.actions,
    this.showFiltersOnSidebar = true,
    this.useScaffold = true,
    this.appBar,
    this.detailPanel,
  });

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isWeb = kIsWeb && screenWidth >= 1100;
    final bool isMobile = !isWeb;
    final scheme = Theme.of(context).colorScheme;

    Widget body;
    if (isMobile && (header != null || filters != null)) {
      body = Container(
        color: const Color(0xFFF8FAFC),
        child: NestedScrollView(
          headerSliverBuilder: (context, _) => [
            if (header != null) SliverToBoxAdapter(child: header!),
            if (filters != null) SliverToBoxAdapter(child: filters!),
          ],
          body: content,
        ),
      );
    } else {
      body = Container(
        color: const Color(0xFFF8FAFC),
        child: Column(
          children: [
            if (isWeb && useScaffold) _buildWebHeader(context),
            if (header != null) header!,
            if (filters != null) filters!,
            Expanded(
              child: detailPanel != null && isWeb
                  ? Row(
                      children: [
                        Expanded(child: content),
                        Container(
                          width: 450,
                          decoration: BoxDecoration(
                            color: scheme.surface,
                            border: Border(
                              left: BorderSide(
                                color: scheme.outlineVariant.withOpacity(0.5),
                              ),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 20,
                                offset: const Offset(-4, 0),
                              ),
                            ],
                          ),
                          child: detailPanel,
                        ),
                      ],
                    )
                  : content,
            ),
          ],
        ),
      );
    }

    if (!useScaffold) return body;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: appBar ?? (isWeb ? null : _buildMobileAppBar(context)),
      body: body,
    );
  }

  // ── AppBar móvil — igual que InternalModuleLayout ─────────────────────────
  PreferredSizeWidget _buildMobileAppBar(BuildContext context) {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded),
        onPressed: () => Navigator.of(context).maybePop(),
        tooltip: 'Volver',
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: kArial,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          if (subtitle != null)
            Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: kArial,
                fontSize: 11,
                fontWeight: FontWeight.w400,
                color: Colors.white.withOpacity(0.8),
              ),
            ),
        ],
      ),
      backgroundColor: kTaskAccent,
      foregroundColor: Colors.white,
      elevation: 0,
      actions: [
        if (actions != null) ...actions!,
        IconButton(
          icon: const Icon(Icons.home_rounded),
          onPressed: () => _navToHome(context),
          tooltip: 'Ir al Home',
        ),
      ],
    );
  }

  // ── Header web — igual que InternalModuleLayout ───────────────────────────
  Widget _buildWebHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
        boxShadow: [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Volver',
            color: const Color(0xFF64748B),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.home_rounded, size: 24),
            onPressed: () => _navToHome(context),
            tooltip: 'Ir al Home',
            color: kTaskAccent,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 4,
                      height: 24,
                      decoration: BoxDecoration(
                        color: kTaskAccent,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      title.toUpperCase(),
                      style: const TextStyle(
                        fontFamily: kArial,
                        fontWeight: FontWeight.w900,
                        fontSize: 22,
                        color: Color(0xFF0F172A),
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: Text(
                      subtitle!,
                      style: const TextStyle(
                        fontFamily: kArial,
                        fontSize: 13,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (actions != null) ...actions!,
        ],
      ),
    );
  }

  void _navToHome(BuildContext context) {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }
}
