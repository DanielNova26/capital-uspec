// lib/home/home_shell.dart

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:todo/state/empresa_scope.dart';
import 'app_drawer.dart';
import 'widgets/home_shared_widgets.dart';

/// Shell que decide qué versión de la interfaz mostrar (Web o Móvil).
class HomeShell extends StatelessWidget {
  final String userId;
  final Widget body;
  final PreferredSizeWidget? appBar;
  final Widget? floatingActionButton;

  /// Controla si se muestran las opciones de Tareas en el drawer/sidebar.
  /// Por defecto true para compatibilidad con usos anteriores.
  final bool showTareas;

  const HomeShell({
    super.key,
    required this.userId,
    required this.body,
    this.appBar,
    this.floatingActionButton,
    this.showTareas = true,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (kIsWeb && constraints.maxWidth >= 900) {
          return _WebShell(
            userId: userId,
            body: body,
            appBar: appBar,
            floatingActionButton: floatingActionButton,
            showTareas: showTareas,
          );
        } else {
          return _MobileShell(
            userId: userId,
            body: body,
            appBar: appBar,
            floatingActionButton: floatingActionButton,
            showTareas: showTareas,
          );
        }
      },
    );
  }
}

class _MobileShell extends StatelessWidget {
  final String userId;
  final Widget body;
  final PreferredSizeWidget? appBar;
  final Widget? floatingActionButton;
  final bool showTareas;

  const _MobileShell({
    required this.userId,
    required this.body,
    this.appBar,
    this.floatingActionButton,
    required this.showTareas,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: appBar,
      drawer: AppDrawer(userId: userId, showTareas: showTareas),
      body: body,
      floatingActionButton: floatingActionButton,
    );
  }
}

class _WebShell extends StatelessWidget {
  final String userId;
  final Widget body;
  final PreferredSizeWidget? appBar;
  final Widget? floatingActionButton;
  final bool showTareas;

  const _WebShell({
    required this.userId,
    required this.body,
    this.appBar,
    this.floatingActionButton,
    required this.showTareas,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final empresaId =
        EmpresaScope.of(context).selectedEmpresaId ?? 'Sin empresa';

    return Scaffold(
      body: Row(
        children: [
          // Sidebar persistente para Web
          SizedBox(
            width: 280,
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(color: scheme.outlineVariant, width: 0.5),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    color: scheme.primaryContainer.withOpacity(0.3),
                    child: SafeArea(
                      bottom: false,
                      child: Row(
                        children: [
                          CompanyLogoAvatar(
                            empresaId: empresaId,
                            radius: 20,
                            backgroundColor: scheme.primary,
                            foregroundColor: scheme.onPrimary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Empresa Activa',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                                CompanyNameWidget(
                                  empresaId: empresaId,
                                  showIdIfNotFound: false,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Arial',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: AppDrawer(userId: userId, showTareas: showTareas),
                  ),
                ],
              ),
            ),
          ),
          // Contenido principal
          Expanded(
            child: Scaffold(
              appBar: appBar,
              body: body,
              floatingActionButton: floatingActionButton,
            ),
          ),
        ],
      ),
    );
  }
}
