import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/user_company.dart';

/// Estado global sencillo para la empresa seleccionada.
class EmpresaState extends ChangeNotifier {
  String? _selectedEmpresaId;

  String? get selectedEmpresaId => _selectedEmpresaId;

  static const String _kEmpresaPrefKey = 'selected_empresa_id';

  Future<void> hydrate() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_kEmpresaPrefKey);
    if (stored == null || stored.trim().isEmpty) return;
    _selectedEmpresaId = normalizeEmpresaId(stored);
    notifyListeners();
  }

  void setSelectedEmpresaId(String? empresaId) {
    final normalized = normalizeEmpresaId(empresaId);
    if (_selectedEmpresaId == normalized) return;
    _selectedEmpresaId = normalized;
    notifyListeners();
    _persistSelection();
  }

  Future<String?> reconcileForUserData(
    Map<String, dynamic> userData, {
    String? preferredEmpresaId,
  }) async {
    final previous = _selectedEmpresaId;
    final resolved = resolveValidEmpresaId(
      data: userData,
      selectedEmpresaId: _selectedEmpresaId,
      preferredEmpresaId: preferredEmpresaId,
    );
    if (_selectedEmpresaId == resolved) return _selectedEmpresaId;

    debugPrint(
      '[EmpresaState] empresa activa corregida '
      'from=$previous to=$resolved preferred=$preferredEmpresaId',
    );
    _selectedEmpresaId = resolved;
    notifyListeners();
    await _persistSelection();
    return _selectedEmpresaId;
  }

  Future<void> _persistSelection() async {
    final prefs = await SharedPreferences.getInstance();
    final current = _selectedEmpresaId;
    if (current == null || current.isEmpty) {
      await prefs.remove(_kEmpresaPrefKey);
    } else {
      await prefs.setString(_kEmpresaPrefKey, current);
    }
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
