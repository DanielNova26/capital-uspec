import 'package:flutter/material.dart';

import '../home/home_screen.dart';
import '../state/empresa_scope.dart';
import 'access_guard.dart';
import 'user_resolver.dart';

class GuardedModulePage extends StatefulWidget {
  final String userIdentity;
  final String appId;
  final String pageTitle;
  final String? fallbackEmpresaId;
  final Widget child;

  const GuardedModulePage({
    super.key,
    required this.userIdentity,
    required this.appId,
    required this.pageTitle,
    required this.child,
    this.fallbackEmpresaId,
  });

  @override
  State<GuardedModulePage> createState() => _GuardedModulePageState();
}

class _GuardedModulePageState extends State<GuardedModulePage> {
  final UserResolver _userResolver = UserResolver();
  final AccessGuard _accessGuard = AccessGuard();

  EmpresaState? _empresaState;
  Future<_GuardState>? _validationFuture;
  String? _authorizedEmpresaId;
  bool _redirectScheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextState = EmpresaScope.of(context);
    if (!identical(_empresaState, nextState)) {
      _empresaState?.removeListener(_onEmpresaChanged);
      _empresaState = nextState;
      _empresaState?.addListener(_onEmpresaChanged);
    }
    _scheduleValidation(notify: false);
  }

  @override
  void dispose() {
    _empresaState?.removeListener(_onEmpresaChanged);
    super.dispose();
  }

  void _onEmpresaChanged() {
    if (!mounted) return;
    _scheduleValidation();
  }

  void _scheduleValidation({bool notify = true}) {
    final selectedEmpresaId =
        _empresaState?.selectedEmpresaId?.trim().isNotEmpty == true
            ? _empresaState!.selectedEmpresaId!.trim()
            : widget.fallbackEmpresaId?.trim();

    if (!notify) {
      _redirectScheduled = false;
      _validationFuture = _validate(selectedEmpresaId);
      return;
    }

    setState(() {
      _redirectScheduled = false;
      _validationFuture = _validate(selectedEmpresaId);
    });
  }

  Future<_GuardState> _validate(String? currentEmpresaId) async {
    final empresaId = currentEmpresaId?.trim();
    if (empresaId == null || empresaId.isEmpty) {
      return const _GuardState.denied(
        message: 'No hay empresa activa válida para este módulo.',
      );
    }

    final userResolution = await _userResolver.resolve(
      docId: widget.userIdentity,
      cedula: widget.userIdentity,
    );
    if (!userResolution.found) {
      return _GuardState.denied(
        message: 'No se pudo resolver el usuario para validar acceso.',
      );
    }

    if (_authorizedEmpresaId != null && _authorizedEmpresaId != empresaId) {
      return _GuardState.denied(
        message:
            'La empresa activa cambió. Regresando a Home para refrescar el contexto.',
        homeUsername: userResolution.docId,
        empresaId: empresaId,
      );
    }

    if (widget.fallbackEmpresaId != null &&
        widget.fallbackEmpresaId!.trim().isNotEmpty &&
        widget.fallbackEmpresaId!.trim() != empresaId) {
      return _GuardState.denied(
        message:
            'La empresa del módulo ya no coincide con la empresa activa.',
        homeUsername: userResolution.docId,
        empresaId: empresaId,
      );
    }

    final decision = await _accessGuard.canAccess(
      userData: userResolution.data,
      empresaId: empresaId,
      appId: widget.appId,
    );
    if (!decision.allowed) {
      return _GuardState.denied(
        message: decision.message ?? 'Acceso no autorizado al módulo.',
        homeUsername: userResolution.docId,
        empresaId: empresaId,
      );
    }

    _authorizedEmpresaId = empresaId;
    return _GuardState.allowed(
      homeUsername: userResolution.docId,
      empresaId: empresaId,
    );
  }

  void _redirectToHome(_GuardState state) {
    if (_redirectScheduled || !mounted) return;
    _redirectScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      final homeUsername = state.homeUsername;
      final empresaId = state.empresaId;
      if (state.message != null && state.message!.isNotEmpty) {
        messenger?.showSnackBar(SnackBar(content: Text(state.message!)));
      }
      if (homeUsername == null || homeUsername.isEmpty) {
        Navigator.of(context).popUntil((route) => route.isFirst);
        return;
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => HomeScreen(
            username: homeUsername,
            empresaId: empresaId ?? '',
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_GuardState>(
      future: _validationFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Scaffold(
            appBar: AppBar(title: Text(widget.pageTitle)),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        final state = snapshot.data!;
        if (!state.allowed) {
          _redirectToHome(state);
          return Scaffold(
            appBar: AppBar(title: Text(widget.pageTitle)),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  state.message ?? 'Validando acceso...',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }

        return widget.child;
      },
    );
  }
}

class _GuardState {
  final bool allowed;
  final String? message;
  final String? homeUsername;
  final String? empresaId;

  const _GuardState._({
    required this.allowed,
    this.message,
    this.homeUsername,
    this.empresaId,
  });

  const _GuardState.allowed({
    required String homeUsername,
    required String empresaId,
  }) : this._(
          allowed: true,
          homeUsername: homeUsername,
          empresaId: empresaId,
        );

  const _GuardState.denied({
    required String message,
    String? homeUsername,
    String? empresaId,
  }) : this._(
          allowed: false,
          message: message,
          homeUsername: homeUsername,
          empresaId: empresaId,
        );
}
