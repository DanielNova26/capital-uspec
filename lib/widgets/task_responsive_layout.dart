import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

const String kArial = 'Arial';

class TaskResponsiveLayout extends StatelessWidget {
  final String title;
  final Widget? header;
  final Widget? filters;
  final Widget content;
  final List<Widget>? actions;
  final bool showFiltersOnSidebar;
  final bool useScaffold;
  final PreferredSizeWidget? appBar;
  final Widget? detailPanel; // New: optional detail panel for Master-Detail on Web

  const TaskResponsiveLayout({
    super.key,
    required this.title,
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
    final scheme = Theme.of(context).colorScheme;

    Widget body;
    body = Container(
      color: scheme.surfaceVariant.withOpacity(0.1),
      child: Column(
        children: [
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

    if (!useScaffold) return body;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: appBar ?? AppBar(
        title: Text(
          title,
          style: const TextStyle(
            fontFamily: kArial,
            fontWeight: FontWeight.w900,
            fontSize: 22,
            letterSpacing: -0.5,
          ),
        ),
        actions: actions,
        elevation: 0,
        scrolledUnderElevation: 2,
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        centerTitle: !isWeb,
      ),
      body: body,
    );
  }
}

