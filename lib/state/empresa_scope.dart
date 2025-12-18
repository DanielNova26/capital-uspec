import 'package:flutter/material.dart';

/// Estado global sencillo para la empresa seleccionada.
class EmpresaState extends ChangeNotifier {
  String? _selectedEmpresaId;

  String? get selectedEmpresaId => _selectedEmpresaId;

  void setSelectedEmpresaId(String? empresaId) {
    final next = empresaId?.trim();
    final normalized = (next == null || next.isEmpty) ? null : next;
    if (_selectedEmpresaId == normalized) return;
    _selectedEmpresaId = normalized;
    notifyListeners();
  }

  void clear() => setSelectedEmpresaId(null);
}

/// InheritedNotifier ligero para exponer [EmpresaState] sin dependencias externas.
class EmpresaScope extends InheritedNotifier<EmpresaState> {
  const EmpresaScope({
    super.key,
    required EmpresaState notifier,
    required Widget child,
  }) : super(notifier: notifier, child: child);

  static EmpresaState of(BuildContext context, {bool listen = true}) {
    final widget = listen
        ? context.dependOnInheritedWidgetOfExactType<EmpresaScope>()
        : context.getElementForInheritedWidgetOfExactType<EmpresaScope>()?.widget
    as EmpresaScope?;
    assert(widget != null, 'EmpresaScope no encontrado en el árbol de widgets.');
    return widget!.notifier!;
  }
}