import 'package:flutter/material.dart';
import '../theme/app_typography.dart';
import '../home/home_screen.dart';

class InternalModuleLayout extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? badge;
  final Color accentColor;
  final List<Widget>? headerActions;
  final Widget child;
  final String userId;
  final String empresaId;
  final Widget? floatingActionButton;

  const InternalModuleLayout({
    super.key,
    required this.title,
    this.subtitle,
    this.badge,
    required this.accentColor,
    this.headerActions,
    required this.child,
    required this.userId,
    required this.empresaId,
    this.floatingActionButton,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWeb = width >= 900;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC), // Fondo limpio Slate 50
      appBar: isWeb ? null : _buildMobileAppBar(context),
      body: Column(
        children: [
          if (isWeb) _buildWebHeader(context),
          Expanded(child: child),
        ],
      ),
      floatingActionButton: floatingActionButton,
    );
  }

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
      backgroundColor: accentColor,
      foregroundColor: Colors.white,
      elevation: 0,
      actions: [
        if (headerActions != null) ...headerActions!,
        IconButton(
          icon: const Icon(Icons.home_rounded),
          onPressed: () => _navToHome(context),
          tooltip: 'Ir al Home',
        ),
      ],
    );
  }

  Widget _buildWebHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Color(0xFFE2E8F0)),
        ), // Slate 200
        boxShadow: [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          // Botón Volver
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Volver',
            color: const Color(0xFF64748B), // Slate 500
          ),
          const SizedBox(width: 8),
          // Botón Home
          IconButton(
            icon: const Icon(Icons.home_rounded, size: 24),
            onPressed: () => _navToHome(context),
            tooltip: 'Ir al Home',
            color: accentColor,
          ),
          const SizedBox(width: 16),
          // Título y Subtítulo
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
                        color: accentColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      title.toUpperCase(),
                      style: const TextStyle(
                        fontFamily: kArial,
                        fontWeight: FontWeight.w900,
                        fontSize: 24,
                        color: Color(0xFF0F172A), // Slate 900
                        letterSpacing: -0.5,
                      ),
                    ),
                    if (badge != null) ...[
                      const SizedBox(width: 12),
                      _buildBadge(),
                    ],
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
                        fontSize: 14,
                        color: Color(0xFF64748B), // Slate 500
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Acciones
          if (headerActions != null) ...[
            const SizedBox(width: 16),
            ...headerActions!.map(
              (a) =>
                  Padding(padding: const EdgeInsets.only(left: 12), child: a),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: accentColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accentColor.withOpacity(0.3)),
      ),
      child: Text(
        badge!.toUpperCase(),
        style: TextStyle(
          fontFamily: kArial,
          fontSize: 10,
          fontWeight: FontWeight.w900,
          color: accentColor,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  void _navToHome(BuildContext context) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => HomeScreen(username: userId, empresaId: empresaId),
      ),
      (route) => false,
    );
  }
}

class InternalModuleViewport extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;

  const InternalModuleViewport({
    super.key,
    required this.child,
    this.maxWidth = 1280,
    this.padding = const EdgeInsets.all(28),
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class InternalModuleTabItem {
  final String label;
  final IconData icon;

  const InternalModuleTabItem({required this.label, required this.icon});
}

class InternalModuleTabs extends StatefulWidget {
  final List<InternalModuleTabItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final Color accentColor;
  final Widget? trailing;
  final bool compact;

  const InternalModuleTabs({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    required this.accentColor,
    this.trailing,
    this.compact = false,
  });

  @override
  State<InternalModuleTabs> createState() => _InternalModuleTabsState();
}

class _InternalModuleTabsState extends State<InternalModuleTabs> {
  final ScrollController _scrollController = ScrollController();
  late List<GlobalKey> _itemKeys;
  bool _canScrollBack = false;
  bool _canScrollForward = false;

  @override
  void initState() {
    super.initState();
    _itemKeys = List.generate(widget.items.length, (_) => GlobalKey());
    _scrollController.addListener(_syncScrollControls);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScrollControls();
      _ensureSelectedVisible(jump: true);
    });
  }

  @override
  void didUpdateWidget(covariant InternalModuleTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items.length != widget.items.length) {
      _itemKeys = List.generate(widget.items.length, (_) => GlobalKey());
    }
    if (oldWidget.selectedIndex != widget.selectedIndex ||
        oldWidget.items.length != widget.items.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _syncScrollControls();
        _ensureSelectedVisible();
      });
    }
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_syncScrollControls)
      ..dispose();
    super.dispose();
  }

  void _syncScrollControls() {
    if (!mounted || !_scrollController.hasClients) return;
    final position = _scrollController.position;
    final back = position.pixels > position.minScrollExtent + 2;
    final forward = position.pixels < position.maxScrollExtent - 2;
    if (back == _canScrollBack && forward == _canScrollForward) return;
    setState(() {
      _canScrollBack = back;
      _canScrollForward = forward;
    });
  }

  Future<void> _scrollBy(double delta) async {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final target = (_scrollController.offset + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    await _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  void _ensureSelectedVisible({bool jump = false}) {
    if (!_scrollController.hasClients || widget.items.isEmpty) return;
    final index = widget.selectedIndex.clamp(0, widget.items.length - 1);
    final itemContext = _itemKeys[index].currentContext;
    if (itemContext == null) return;
    Scrollable.ensureVisible(
      itemContext,
      alignment: 0.5,
      duration: jump ? Duration.zero : const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  Widget _scrollButton({
    required IconData icon,
    required bool enabled,
    required double delta,
    required String tooltip,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: 36,
      height: 36,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: enabled
            ? widget.accentColor.withOpacity(0.08)
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: enabled
              ? widget.accentColor.withOpacity(0.24)
              : const Color(0xFFE2E8F0),
        ),
      ),
      child: IconButton(
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 36, height: 36),
        onPressed: enabled ? () => _scrollBy(delta) : null,
        tooltip: tooltip,
        icon: Icon(icon, size: 20),
        color: widget.accentColor,
        disabledColor: const Color(0xFFCBD5E1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        children: [
          _scrollButton(
            icon: Icons.chevron_left,
            enabled: _canScrollBack,
            delta: -360,
            tooltip: 'Ver opciones anteriores',
          ),
          Expanded(
            child: Scrollbar(
              controller: _scrollController,
              thumbVisibility: _canScrollBack || _canScrollForward,
              interactive: true,
              child: SingleChildScrollView(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(
                  horizontal: widget.compact ? 8 : 12,
                  vertical: widget.compact ? 12 : 14,
                ),
                child: Row(
                  children: [
                    ...List.generate(widget.items.length, (index) {
                      final item = widget.items[index];
                      final selected = index == widget.selectedIndex;

                      return Padding(
                        key: _itemKeys[index],
                        padding: EdgeInsets.only(
                          right: widget.compact ? 8 : 10,
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => widget.onSelected(index),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: EdgeInsets.symmetric(
                              horizontal: widget.compact ? 12 : 16,
                              vertical: widget.compact ? 10 : 12,
                            ),
                            decoration: BoxDecoration(
                              color: selected
                                  ? widget.accentColor.withOpacity(0.12)
                                  : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: selected
                                    ? widget.accentColor.withOpacity(0.35)
                                    : const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  item.icon,
                                  size: widget.compact ? 17 : 18,
                                  color: selected
                                      ? widget.accentColor
                                      : const Color(0xFF64748B),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  item.label,
                                  style: TextStyle(
                                    fontFamily: kArial,
                                    fontSize: widget.compact ? 12 : 13,
                                    fontWeight: selected
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                    color: selected
                                        ? widget.accentColor
                                        : const Color(0xFF475569),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                    if (widget.trailing != null) ...[
                      SizedBox(width: widget.compact ? 8 : 12),
                      widget.trailing!,
                    ],
                  ],
                ),
              ),
            ),
          ),
          _scrollButton(
            icon: Icons.chevron_right,
            enabled: _canScrollForward,
            delta: 360,
            tooltip: 'Ver más opciones',
          ),
        ],
      ),
    );
  }
}

/// Widget de Card unificado para usar dentro de los módulos
class ModuleCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final Color? color;

  const ModuleCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color ?? Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)), // Slate 200
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: padding ?? const EdgeInsets.all(20),
            child: child,
          ),
        ),
      ),
    );
  }
}
