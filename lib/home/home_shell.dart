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

  const HomeShell({
    super.key,
    required this.userId,
    required this.body,
    this.appBar,
    this.floatingActionButton,
  });

  @override
  Widget build(BuildContext context) {
    // Si es Web y la pantalla es lo suficientemente ancha, usamos la versión de escritorio.
    // Usamos un breakpoint de 900px para decidir.
    return LayoutBuilder(
      builder: (context, constraints) {
        if (kIsWeb && constraints.maxWidth >= 900) {
          return _WebShell(
            userId: userId,
            body: body,
            appBar: appBar,
            floatingActionButton: floatingActionButton,
          );
        } else {
          return _MobileShell(
            userId: userId,
            body: body,
            appBar: appBar,
            floatingActionButton: floatingActionButton,
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

  const _MobileShell({
    required this.userId,
    required this.body,
    this.appBar,
    this.floatingActionButton,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: appBar,
      drawer: AppDrawer(userId: userId),
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

  const _WebShell({
    required this.userId,
    required this.body,
    this.appBar,
    this.floatingActionButton,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final empresaId = EmpresaScope.of(context).selectedEmpresaId ?? 'Sin empresa';

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
                  // Encabezado del Sidebar con info de empresa
                  Container(
                    padding: const EdgeInsets.all(20),
                    color: scheme.primaryContainer.withOpacity(0.3),
                    child: SafeArea(
                      bottom: false,
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: scheme.primary,
                            foregroundColor: scheme.onPrimary,
                            child: Text(empresaId.substring(0, empresaId.length >= 2 ? 2 : 1).toUpperCase()),
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
                  // Reutilizamos el AppDrawer pero sin el Scaffold/Drawer wrapper
                  // para que se comporte como un panel lateral estático.
                  Expanded(
                    child: AppDrawer(userId: userId),
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
