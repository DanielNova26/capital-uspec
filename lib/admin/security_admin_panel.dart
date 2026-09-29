import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';

import '../services/device_descriptor.dart';
import '../widgets/paged_list.dart';
import '../widgets/user_avatar.dart';
import 'security_admin_service.dart';

enum _SecurityFilter {
  all,
  secure,
  pendingMigration,
  passwordChange,
  blocked,
  inactive,
  neverLoggedIn,
  loggedIn,
  desktop,
  mobile,
}

IconData _iconoDispositivo(DispositivoIngreso d) => switch (d.tipo) {
  TipoDispositivo.computador => Icons.computer_rounded,
  TipoDispositivo.celular => Icons.smartphone_rounded,
  TipoDispositivo.tablet => Icons.tablet_android_rounded,
  TipoDispositivo.desconocido => Icons.devices_other_rounded,
};

/// "Hoy 10:32", "Ayer 08:10", "Hace 3 días", "12/08/26".
String haceCuanto(DateTime fecha, DateTime ahora) {
  final hoy = DateTime(ahora.year, ahora.month, ahora.day);
  final dia = DateTime(fecha.year, fecha.month, fecha.day);
  final dias = hoy.difference(dia).inDays;
  final hora = DateFormat('HH:mm').format(fecha);
  if (dias <= 0) return 'Hoy $hora';
  if (dias == 1) return 'Ayer $hora';
  if (dias < 7) return 'Hace $dias días';
  return DateFormat('dd/MM/yy').format(fecha);
}

class SecurityAdminPanel extends StatefulWidget {
  final String empresaId;

  const SecurityAdminPanel({super.key, required this.empresaId});

  @override
  State<SecurityAdminPanel> createState() => _SecurityAdminPanelState();
}

class _SecurityAdminPanelState extends State<SecurityAdminPanel> {
  final SecurityAdminService _service = SecurityAdminService();
  final TextEditingController _searchController = TextEditingController();
  SecurityOverview? _overview;
  bool _loading = true;
  String? _error;
  String? _busyUserId;
  _SecurityFilter _filter = _SecurityFilter.all;
  int _page = 0;
  static const int _pageSize = 20;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant SecurityAdminPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.empresaId != widget.empresaId) {
      _filter = _SecurityFilter.all;
      _page = 0;
      _searchController.clear();
      _load();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (widget.empresaId.trim().isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final overview = await _service.overview(widget.empresaId);
      if (!mounted) return;
      setState(() {
        _overview = overview;
        _loading = false;
      });
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error =
            error.message ?? 'No fue posible cargar el centro de seguridad.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No fue posible cargar el centro de seguridad: $error';
      });
    }
  }

  List<SecurityUserStatus> get _filteredUsers {
    final query = _searchController.text.trim().toLowerCase();
    final source = _overview?.users ?? const <SecurityUserStatus>[];
    return source.where((user) {
      final matchesText =
          query.isEmpty ||
          user.nombre.toLowerCase().contains(query) ||
          user.cedula.toLowerCase().contains(query) ||
          user.area.toLowerCase().contains(query) ||
          user.cargo.toLowerCase().contains(query);
      if (!matchesText) return false;
      switch (_filter) {
        case _SecurityFilter.secure:
          return user.active && user.migrated && !user.needsPasswordChange;
        case _SecurityFilter.pendingMigration:
          return user.active && !user.migrated;
        case _SecurityFilter.passwordChange:
          return user.active && user.needsPasswordChange;
        case _SecurityFilter.blocked:
          return user.blocked;
        case _SecurityFilter.inactive:
          return !user.active;
        case _SecurityFilter.neverLoggedIn:
          return user.active && user.neverLoggedIn;
        case _SecurityFilter.loggedIn:
          return user.hasLoggedIn;
        case _SecurityFilter.desktop:
          return user.hasLoggedIn &&
              user.lastLoginDevice.tipo == TipoDispositivo.computador;
        case _SecurityFilter.mobile:
          return user.hasLoggedIn && user.lastLoginDevice.esMovil;
        case _SecurityFilter.all:
          return true;
      }
    }).toList();
  }

  Future<void> _runForUser(
    SecurityUserStatus user,
    Future<void> Function() action,
  ) async {
    setState(() => _busyUserId = user.userDocId);
    try {
      await action();
      await _load();
    } on FirebaseFunctionsException catch (error) {
      if (mounted) {
        _message(
          error.message ?? 'No fue posible completar la acción.',
          error: true,
        );
      }
    } catch (error) {
      if (mounted) {
        _message('No fue posible completar la acción: $error', error: true);
      }
    } finally {
      if (mounted) setState(() => _busyUserId = null);
    }
  }

  void _message(String text, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? const Color(0xFFB91C1C) : null,
      ),
    );
  }

  Future<bool> _confirm(String title, String message, String action) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(action),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _togglePasswordChange(SecurityUserStatus user) async {
    final required = !user.needsPasswordChange;
    if (required &&
        !await _confirm(
          'Exigir cambio de contraseña',
          'Se cerrarán las sesiones de ${user.nombre} y deberá crear una contraseña nueva en el siguiente ingreso.',
          'Exigir cambio',
        )) {
      return;
    }
    await _runForUser(user, () async {
      await _service.setPasswordChangeRequired(
        empresaId: widget.empresaId,
        targetUserDocId: user.userDocId,
        required: required,
      );
      if (mounted) {
        _message(
          required
              ? 'Cambio obligatorio activado.'
              : 'Cambio obligatorio retirado.',
        );
      }
    });
  }

  Future<void> _revokeSessions(SecurityUserStatus user) async {
    if (!await _confirm(
      'Cerrar sesiones',
      'Las sesiones renovables de ${user.nombre} dejarán de ser válidas. La persona deberá iniciar sesión nuevamente.',
      'Cerrar sesiones',
    )) {
      return;
    }
    await _runForUser(user, () async {
      await _service.revokeSessions(
        empresaId: widget.empresaId,
        targetUserDocId: user.userDocId,
      );
      if (mounted) _message('Sesiones revocadas.');
    });
  }

  bool _cerrandoInhabilitados = false;

  /// Cierra de una vez las sesiones de todos los inhabilitados: quienes ya
  /// lo estaban antes de que el servidor las cerrara solo, al inhabilitar.
  Future<void> _revokeDisabledSessions(int cuantos) async {
    if (!await _confirm(
      'Cerrar sesiones de inhabilitados',
      'Se cerrarán las sesiones abiertas de $cuantos persona(s) que hoy no '
          'pueden entrar a la app. Si alguna tiene la app abierta en un '
          'navegador o teléfono, saldrá al volver a validarse. Se puede '
          'repetir sin problema.',
      'Cerrar sesiones',
    )) {
      return;
    }
    setState(() => _cerrandoInhabilitados = true);
    try {
      final r = await _service.revokeDisabledSessions(
        empresaId: widget.empresaId,
      );
      if (!mounted) return;
      _message(
        '${r.cerradas} sesión(es) cerradas'
        '${r.sinCuenta > 0 ? '; ${r.sinCuenta} nunca iniciaron sesión segura' : ''}'
        '${r.fallidas > 0 ? '; ${r.fallidas} no se pudieron cerrar, intenta de nuevo' : ''}.',
        error: r.fallidas > 0,
      );
      await _load();
    } on FirebaseFunctionsException catch (error) {
      if (mounted) {
        _message(
          error.message ?? 'No fue posible cerrar las sesiones.',
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _cerrandoInhabilitados = false);
    }
  }

  Widget _avisoInhabilitados(int cuantos) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFFEF2F2),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFFECACA)),
    ),
    child: Wrap(
      spacing: 12,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Icon(Icons.block_rounded, color: Color(0xFFB91C1C)),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Text(
            '$cuantos persona(s) inhabilitadas: no pueden iniciar sesión. '
            'Si alguna tenía una sesión abierta desde antes, ciérrala aquí.',
            style: const TextStyle(fontSize: 13, color: Color(0xFF7F1D1D)),
          ),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFB91C1C),
          ),
          onPressed: _cerrandoInhabilitados
              ? null
              : () => _revokeDisabledSessions(cuantos),
          icon: _cerrandoInhabilitados
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.logout_rounded),
          label: const Text('Cerrar sus sesiones'),
        ),
      ],
    ),
  );

  bool _asignandoClaveInicial = false;

  /// Clave inicial para todos los que nunca han iniciado sesión.
  Future<void> _assignInitialPasswordAll(int cuantos) async {
    if (!await _confirm(
      'Asignar clave inicial $kClaveInicial',
      '$cuantos persona(s) nunca han iniciado sesión. Todas podrán entrar '
          'con su cédula y la clave $kClaveInicial, y al entrar la app les '
          'pedirá crear su propia contraseña (8 caracteres o más) y sus '
          'preguntas de seguridad.\n\nNo cambia la clave de quien ya entró '
          'o ya puso la suya. Queda registrado en la actividad.',
      'Asignar a $cuantos',
    )) {
      return;
    }
    setState(() => _asignandoClaveInicial = true);
    try {
      final asignadas = await _service.assignInitialPassword(
        empresaId: widget.empresaId,
      );
      if (!mounted) return;
      _message(
        asignadas == 0
            ? 'No había personas pendientes.'
            : 'Clave $kClaveInicial asignada a $asignadas persona(s).',
      );
      await _load();
    } on FirebaseFunctionsException catch (error) {
      if (mounted) {
        _message(
          error.message ?? 'No fue posible asignar la clave inicial.',
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _asignandoClaveInicial = false);
    }
  }

  Future<void> _assignInitialPassword(SecurityUserStatus user) async {
    if (!await _confirm(
      'Asignar clave inicial',
      '${user.nombre} podrá entrar con su cédula y la clave $kClaveInicial. '
          'Al entrar deberá crear su propia contraseña.',
      'Asignar',
    )) {
      return;
    }
    await _runForUser(user, () async {
      await _service.assignInitialPassword(
        empresaId: widget.empresaId,
        targetUserDocId: user.userDocId,
      );
      if (mounted) _message('Clave $kClaveInicial asignada a ${user.nombre}.');
    });
  }

  Future<void> _clearBlocks(SecurityUserStatus user) async {
    await _runForUser(user, () async {
      final cleared = await _service.clearLoginBlocks(
        empresaId: widget.empresaId,
        targetUserDocId: user.userDocId,
      );
      if (mounted) {
        _message(
          cleared == 0
              ? 'No había bloqueos activos registrados.'
              : 'Bloqueo retirado.',
        );
      }
    });
  }

  Future<void> _resetPassword(SecurityUserStatus user) async {
    if (!await _confirm(
      'Generar contraseña temporal',
      'Se reemplazará la contraseña actual de ${user.nombre}, se cerrarán sus sesiones y deberá cambiarla al ingresar.',
      'Generar',
    )) {
      return;
    }
    setState(() => _busyUserId = user.userDocId);
    try {
      final password = await _service.resetTemporaryPassword(
        empresaId: widget.empresaId,
        targetUserDocId: user.userDocId,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Contraseña temporal creada'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Se muestra una sola vez. Entrégala directamente al usuario y no la guardes en chats o documentos compartidos.',
              ),
              const SizedBox(height: 14),
              SelectableText(
                password,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.4,
                ),
              ),
            ],
          ),
          actions: [
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: password));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Contraseña copiada.')),
                  );
                }
              },
              icon: const Icon(Icons.copy_outlined),
              label: const Text('Copiar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Ya la entregué'),
            ),
          ],
        ),
      );
      await _load();
    } on FirebaseFunctionsException catch (error) {
      if (mounted) {
        _message(
          error.message ?? 'No fue posible generar la contraseña.',
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busyUserId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _overview == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _overview == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.gpp_bad_outlined,
                size: 48,
                color: Color(0xFFB91C1C),
              ),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    final users = _overview?.users ?? const <SecurityUserStatus>[];
    final secure = users
        .where(
          (user) => user.active && user.migrated && !user.needsPasswordChange,
        )
        .length;
    final migration = users
        .where((user) => user.active && !user.migrated)
        .length;
    final passwordChange = users
        .where((user) => user.active && user.needsPasswordChange)
        .length;
    final blocked = users.where((user) => user.blocked).length;
    final inhabilitados = users.where((user) => user.accessBlocked).length;
    final nuncaEntraron = users
        .where((user) => user.active && user.neverLoggedIn)
        .length;
    final filtered = _filteredUsers;
    final pageCount = filtered.isEmpty
        ? 1
        : (filtered.length / _pageSize).ceil();
    if (_page >= pageCount) _page = pageCount - 1;
    final start = _page * _pageSize;
    final pageUsers = filtered.skip(start).take(_pageSize).toList();
    final width = MediaQuery.sizeOf(context).width;
    final mobile = width < 720;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.all(mobile ? 12 : 20),
        children: [
          _hero(),
          const SizedBox(height: 12),
          _accessSection(users, nuncaEntraron, mobile),
          const SizedBox(height: 12),
          _summaryGrid(
            users.length,
            secure,
            migration,
            passwordChange,
            blocked,
            mobile,
          ),
          if (inhabilitados > 0) ...[
            const SizedBox(height: 12),
            _avisoInhabilitados(inhabilitados),
          ],
          const SizedBox(height: 14),
          _filters(),
          const SizedBox(height: 12),
          if (pageUsers.isEmpty)
            const _EmptySecurityState()
          else
            ...pageUsers.map(_userCard),
          if (filtered.isNotEmpty) ...[
            const SizedBox(height: 4),
            _pager(filtered.length, pageCount),
          ],
          const SizedBox(height: 14),
          _sessionsPanel(),
          const SizedBox(height: 12),
          _auditPanel(),
          const SizedBox(height: 28),
        ],
      ),
    );
  }

  Widget _hero() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1D4ED8)],
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 25,
            backgroundColor: Color(0x22FFFFFF),
            child: SvgPicture.asset(
              'assets/icons/security_shield.svg',
              width: 29,
              height: 29,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Centro de Seguridad',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Cuentas, cambios obligatorios, bloqueos y sesiones de la empresa activa.',
                  style: TextStyle(color: Color(0xFFDCE7FF)),
                ),
              ],
            ),
          ),
          IconButton.filledTonal(
            tooltip: 'Actualizar',
            onPressed: _loading ? null : _load,
            icon: _loading
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }

  /// Clasificación de accesos: quién nunca ha entrado, quién sí, desde qué
  /// equipo y qué celulares. Cada tarjeta filtra la lista de personas.
  Widget _accessSection(
    List<SecurityUserStatus> users,
    int nuncaEntraron,
    bool mobile,
  ) {
    final resumen = resumenDispositivos(users);
    final entraron = users.where((u) => u.hasLoggedIn).length;
    final tarjetas = [
      (
        'Nunca han entrado',
        nuncaEntraron,
        Icons.person_off_outlined,
        const Color(0xFFD97706),
        _SecurityFilter.neverLoggedIn,
      ),
      (
        'Ya entraron',
        entraron,
        Icons.how_to_reg_outlined,
        const Color(0xFF047857),
        _SecurityFilter.loggedIn,
      ),
      (
        'Desde computador',
        resumen.computador,
        Icons.computer_rounded,
        const Color(0xFF1D4ED8),
        _SecurityFilter.desktop,
      ),
      (
        'Desde celular',
        resumen.celular,
        Icons.smartphone_rounded,
        const Color(0xFF7C3AED),
        _SecurityFilter.mobile,
      ),
    ];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Accesos a la app',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 2),
          const Text(
            'Según el último ingreso de cada persona. Toca una tarjeta para '
            'ver quiénes son.',
            style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 10),
          _tarjetasFiltro(tarjetas, mobile ? 2 : 4),
          if (resumen.marcas.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text(
                  'Celulares:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                ),
                for (final marca in resumen.marcas)
                  _statusChip(
                    '${marca.key} ${marca.value}',
                    Icons.smartphone_rounded,
                    const Color(0xFF7C3AED),
                  ),
              ],
            ),
          ],
          if (resumen.sinDetalle > 0) ...[
            const SizedBox(height: 6),
            Text(
              '${resumen.sinDetalle} persona(s) entraron antes de que se '
              'registrara el equipo: se verá en su próximo ingreso.',
              style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
            ),
          ],
          if (nuncaEntraron > 0) ...[
            const SizedBox(height: 12),
            _avisoClaveInicial(nuncaEntraron),
          ],
        ],
      ),
    );
  }

  Widget _avisoClaveInicial(int cuantos) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFFFFBEB),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFFDE68A)),
    ),
    child: Wrap(
      spacing: 12,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Icon(Icons.key_rounded, color: Color(0xFFB45309)),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Text(
            '$cuantos persona(s) nunca han iniciado sesión. Con la clave '
            'inicial entran con su cédula y $kClaveInicial, y la app les pide '
            'cambiarla al entrar.',
            style: const TextStyle(fontSize: 13, color: Color(0xFF78350F)),
          ),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFB45309),
          ),
          onPressed: _asignandoClaveInicial
              ? null
              : () => _assignInitialPasswordAll(cuantos),
          icon: _asignandoClaveInicial
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.password_rounded),
          label: Text('Asignar $kClaveInicial a $cuantos'),
        ),
      ],
    ),
  );

  /// Tarjetas con número que filtran la lista (mismo dibujo que Cuentas).
  Widget _tarjetasFiltro(
    List<(String, int, IconData, Color, _SecurityFilter)> cards,
    int columnas,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 10.0;
        final cardWidth =
            (constraints.maxWidth - spacing * (columnas - 1)) / columnas;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: cards.map((card) {
            final selected = _filter == card.$5;
            return InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => setState(() {
                _filter = selected ? _SecurityFilter.all : card.$5;
                _page = 0;
              }),
              child: Container(
                width: cardWidth,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: selected
                      ? card.$4.withValues(alpha: .08)
                      : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selected ? card.$4 : const Color(0xFFE2E8F0),
                    width: selected ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(card.$3, color: card.$4),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${card.$2}',
                            style: TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w900,
                              color: card.$4,
                            ),
                          ),
                          Text(
                            card.$1,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  TipoDispositivo? _tipoIngresos;
  int _pageIngresos = 0;
  int _pageAudit = 0;

  /// Registro de ingresos de los últimos días: quién, cuándo, cómo y desde
  /// qué equipo, de a 20.
  Widget _sessionsPanel() {
    final todas = _overview?.sessions ?? const <SecuritySession>[];
    final dias = _overview?.sessionDays ?? 30;
    final filtradas = [
      for (final s in todas)
        if (_tipoIngresos == null ||
            (_tipoIngresos == TipoDispositivo.celular
                ? s.device.esMovil
                : s.device.tipo == _tipoIngresos))
          s,
    ];
    final pagina = _pageIngresos.clamp(0, pageCountOf(filtradas.length) - 1);
    final ahora = DateTime.now();
    Widget filtro(String label, TipoDispositivo? tipo) => ChoiceChip(
      label: Text(label),
      selected: _tipoIngresos == tipo,
      onSelected: (_) => setState(() {
        _tipoIngresos = tipo;
        _pageIngresos = 0;
      }),
    );
    return ExpansionTile(
      initiallyExpanded: true,
      tilePadding: const EdgeInsets.symmetric(horizontal: 14),
      childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      collapsedShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      leading: const Icon(Icons.login_rounded),
      title: const Text(
        'Registro de ingresos',
        style: TextStyle(fontWeight: FontWeight.w900),
      ),
      subtitle: Text('${todas.length} ingreso(s) en los últimos $dias días.'),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              filtro('Todos', null),
              filtro('Computador', TipoDispositivo.computador),
              filtro('Celular o tablet', TipoDispositivo.celular),
              filtro('Sin detalle', TipoDispositivo.desconocido),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (filtradas.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('No hay ingresos para este filtro.'),
          ),
        for (final sesion in pageOf(filtradas, pagina))
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: UserAvatar(
              userId: sesion.userDocId,
              nameHint: sesion.nombre,
              radius: 18,
            ),
            title: Text(
              sesion.nombre,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: Row(
              children: [
                Icon(
                  _iconoDispositivo(sesion.device),
                  size: 14,
                  color: const Color(0xFF64748B),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '${sesion.device.tipo == TipoDispositivo.desconocido ? 'Equipo sin detalle' : sesion.device.descripcion}'
                    ' · ${sesion.sourceLabel}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            trailing: Text(
              sesion.loginAt == null ? '-' : haceCuanto(sesion.loginAt!, ahora),
              style: const TextStyle(fontSize: 11),
            ),
          ),
        PagerBar(
          total: filtradas.length,
          page: pagina,
          etiqueta: 'ingresos',
          onPageChanged: (p) => setState(() => _pageIngresos = p),
        ),
      ],
    );
  }

  Widget _summaryGrid(
    int total,
    int secure,
    int migration,
    int passwordChange,
    int blocked,
    bool mobile,
  ) {
    final cards = [
      (
        'Cuentas',
        total,
        Icons.people_alt_outlined,
        const Color(0xFF334155),
        _SecurityFilter.all,
      ),
      (
        'Acceso seguro',
        secure,
        Icons.verified_user_outlined,
        const Color(0xFF047857),
        _SecurityFilter.secure,
      ),
      (
        'Migración pendiente',
        migration,
        Icons.sync_lock_outlined,
        const Color(0xFFD97706),
        _SecurityFilter.pendingMigration,
      ),
      (
        'Cambio obligatorio',
        passwordChange,
        Icons.password_outlined,
        const Color(0xFF7C3AED),
        _SecurityFilter.passwordChange,
      ),
      (
        'Bloqueados',
        blocked,
        Icons.lock_clock_outlined,
        const Color(0xFFB91C1C),
        _SecurityFilter.blocked,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = mobile
            ? 2
            : constraints.maxWidth > 1200
            ? 5
            : 3;
        final spacing = 10.0;
        final cardWidth =
            (constraints.maxWidth - spacing * (count - 1)) / count;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: cards.map((card) {
            final selected = _filter == card.$5;
            return InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => setState(() {
                _filter = card.$5;
                _page = 0;
              }),
              child: Container(
                width: cardWidth,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: selected
                      ? card.$4.withValues(alpha: .08)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selected ? card.$4 : const Color(0xFFE2E8F0),
                    width: selected ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(card.$3, color: card.$4),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${card.$2}',
                            style: TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w900,
                              color: card.$4,
                            ),
                          ),
                          Text(
                            card.$1,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _filters() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 360,
          child: TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search),
              hintText: 'Buscar nombre, cédula, área o cargo',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() => _page = 0),
          ),
        ),
        DropdownButton<_SecurityFilter>(
          value: _filter,
          onChanged: (value) => setState(() {
            _filter = value ?? _SecurityFilter.all;
            _page = 0;
          }),
          items: const [
            DropdownMenuItem(
              value: _SecurityFilter.all,
              child: Text('Todos los estados'),
            ),
            DropdownMenuItem(
              value: _SecurityFilter.secure,
              child: Text('Acceso seguro'),
            ),
            DropdownMenuItem(
              value: _SecurityFilter.pendingMigration,
              child: Text('Migración pendiente'),
            ),
            DropdownMenuItem(
              value: _SecurityFilter.passwordChange,
              child: Text('Cambio obligatorio'),
            ),
            DropdownMenuItem(
              value: _SecurityFilter.blocked,
              child: Text('Bloqueados'),
            ),
            DropdownMenuItem(
              value: _SecurityFilter.inactive,
              child: Text('Inactivos'),
            ),
            DropdownMenuItem(
              value: _SecurityFilter.neverLoggedIn,
              child: Text('Nunca han entrado'),
            ),
            DropdownMenuItem(
              value: _SecurityFilter.loggedIn,
              child: Text('Ya entraron'),
            ),
            DropdownMenuItem(
              value: _SecurityFilter.desktop,
              child: Text('Último ingreso: computador'),
            ),
            DropdownMenuItem(
              value: _SecurityFilter.mobile,
              child: Text('Último ingreso: celular'),
            ),
          ],
        ),
        Text(
          '${_filteredUsers.length} persona(s)',
          style: const TextStyle(color: Color(0xFF64748B)),
        ),
      ],
    );
  }

  Widget _userCard(SecurityUserStatus user) {
    final busy = _busyUserId == user.userDocId;
    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Row(
          children: [
            UserAvatar(
              userId: user.userDocId,
              nameHint: user.nombre,
              radius: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.nombre,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${user.cedula}${user.cargo.isEmpty ? '' : ' · ${user.cargo}'}${user.area.isEmpty ? '' : ' · ${user.area}'}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 5,
                    children: [
                      _statusChip(
                        user.active ? 'Activo' : 'Inactivo',
                        user.active
                            ? Icons.check_circle_outline
                            : Icons.person_off_outlined,
                        user.active
                            ? const Color(0xFF047857)
                            : const Color(0xFF64748B),
                      ),
                      _statusChip(
                        user.migrated ? 'Acceso seguro' : 'Migración pendiente',
                        user.migrated
                            ? Icons.shield_outlined
                            : Icons.sync_lock_outlined,
                        user.migrated
                            ? const Color(0xFF047857)
                            : const Color(0xFFD97706),
                      ),
                      if (user.needsPasswordChange)
                        _statusChip(
                          'Debe cambiar contraseña',
                          Icons.password_outlined,
                          const Color(0xFF7C3AED),
                        ),
                      if (user.blocked)
                        _statusChip(
                          'Bloqueado',
                          Icons.lock_clock_outlined,
                          const Color(0xFFB91C1C),
                        ),
                      if (user.lastLoginAt == null)
                        _statusChip(
                          user.neverLoggedIn
                              ? 'Nunca ha iniciado sesión'
                              : 'Sin ingreso registrado',
                          Icons.person_off_outlined,
                          const Color(0xFFD97706),
                        )
                      else
                        _statusChip(
                          [
                            'Último: ${haceCuanto(user.lastLoginAt!, DateTime.now())}',
                            if (user.lastLoginDevice.tipo !=
                                TipoDispositivo.desconocido)
                              user.lastLoginDevice.descripcion,
                          ].join(' · '),
                          _iconoDispositivo(user.lastLoginDevice),
                          const Color(0xFF475569),
                        ),
                      if (user.initialPassword)
                        _statusChip(
                          'Clave inicial $kClaveInicial',
                          Icons.key_rounded,
                          const Color(0xFFB45309),
                        ),
                      if (user.esNueva(DateTime.now()))
                        _statusChip(
                          'Nuevo · ${DateFormat('dd/MM/yy').format(user.createdAt!)}',
                          Icons.fiber_new_outlined,
                          const Color(0xFF0E7490),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (busy)
              const SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              PopupMenuButton<String>(
                tooltip: 'Acciones de seguridad',
                onSelected: (value) {
                  switch (value) {
                    case 'password-change':
                      _togglePasswordChange(user);
                      break;
                    case 'reset':
                      _resetPassword(user);
                      break;
                    case 'initial':
                      _assignInitialPassword(user);
                      break;
                    case 'revoke':
                      _revokeSessions(user);
                      break;
                    case 'unblock':
                      _clearBlocks(user);
                      break;
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'password-change',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.password_outlined),
                      title: Text(
                        user.needsPasswordChange
                            ? 'Retirar cambio obligatorio'
                            : 'Exigir cambio de contraseña',
                      ),
                    ),
                  ),
                  if (user.neverLoggedIn && user.active)
                    const PopupMenuItem(
                      value: 'initial',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.password_rounded),
                        title: Text('Asignar clave inicial $kClaveInicial'),
                      ),
                    ),
                  const PopupMenuItem(
                    value: 'reset',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.key_outlined),
                      title: Text('Generar contraseña temporal'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'revoke',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.logout),
                      title: Text('Cerrar sesiones'),
                    ),
                  ),
                  if (user.blocked)
                    const PopupMenuItem(
                      value: 'unblock',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.lock_open_outlined),
                        title: Text('Quitar bloqueo'),
                      ),
                    ),
                ],
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.more_vert),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: .25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pager(int total, int pageCount) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          '${_page * _pageSize + 1}-${(_page * _pageSize + _pageSize).clamp(0, total)} de $total',
        ),
        IconButton(
          tooltip: 'Página anterior',
          onPressed: _page == 0 ? null : () => setState(() => _page--),
          icon: const Icon(Icons.chevron_left),
        ),
        Text('${_page + 1}/$pageCount'),
        IconButton(
          tooltip: 'Página siguiente',
          onPressed: _page + 1 >= pageCount
              ? null
              : () => setState(() => _page++),
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }

  Widget _auditPanel() {
    final entries = _overview?.audit ?? const <SecurityAuditEntry>[];
    final pagina = _pageAudit.clamp(0, pageCountOf(entries.length) - 1);
    final ahora = DateTime.now();
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 14),
      childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      collapsedShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      leading: const Icon(Icons.history_rounded),
      title: const Text(
        'Actividad administrativa',
        style: TextStyle(fontWeight: FontWeight.w900),
      ),
      subtitle: const Text(
        'Personas nuevas y acciones sensibles. Nunca se guardan contraseñas.',
      ),
      children: [
        if (entries.isEmpty)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text('Aún no hay acciones administrativas registradas.'),
          ),
        for (final entry in pageOf(entries, pagina))
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(_auditIcon(entry.action), size: 20),
            title: Text(auditLabel(entry)),
            subtitle: _auditPeople(entry),
            trailing: Text(
              entry.createdAt == null
                  ? '-'
                  : haceCuanto(entry.createdAt!, ahora),
              style: const TextStyle(fontSize: 11),
            ),
          ),
        PagerBar(
          total: entries.length,
          page: pagina,
          etiqueta: 'acciones',
          onPageChanged: (p) => setState(() => _pageAudit = p),
        ),
      ],
    );
  }

  /// Persona afectada y quién hizo la acción, por nombre (nunca la cédula).
  Widget _auditPeople(SecurityAuditEntry entry) {
    const estilo = TextStyle(fontSize: 12, color: Color(0xFF64748B));
    final target = entry.targetUserDocId;
    final actor = entry.actorUserDocId;
    return Wrap(
      spacing: 4,
      children: [
        if (target.isNotEmpty && target != '*')
          UserNameText(target, style: estilo, prefix: 'Persona: '),
        if (actor.isNotEmpty) ...[
          if (target.isNotEmpty && target != '*')
            const Text('·', style: estilo),
          UserNameText(
            actor,
            style: estilo,
            prefix: entry.action == 'user_created' ? 'Creó: ' : 'Hizo: ',
          ),
        ] else if (entry.action == 'user_created')
          const Text('Registro automático', style: estilo),
      ],
    );
  }

  IconData _auditIcon(String action) => switch (action) {
    'user_created' => Icons.person_add_alt_1_outlined,
    'initial_password_bulk' ||
    'initial_password_assigned' => Icons.password_rounded,
    'temporary_password_reset' => Icons.key_outlined,
    'revoke_sessions' || 'revoke_disabled_sessions' => Icons.logout_rounded,
    'clear_login_blocks' => Icons.lock_open_outlined,
    _ => Icons.shield_outlined,
  };
}

/// Texto de una acción de la actividad de Seguridad.
String auditLabel(SecurityAuditEntry entry) {
  switch (entry.action) {
    case 'user_created':
      return entry.initialPassword
          ? 'Persona nueva, con clave inicial $kClaveInicial'
          : 'Persona nueva';
    case 'initial_password_bulk':
      return 'Asignó la clave inicial a ${entry.count ?? 0} persona(s) que '
          'nunca habían entrado';
    case 'initial_password_assigned':
      return 'Asignó la clave inicial $kClaveInicial';
    case 'require_password_change':
      return 'Activó cambio obligatorio de contraseña';
    case 'clear_password_change':
      return 'Retiró cambio obligatorio de contraseña';
    case 'temporary_password_reset':
      return 'Generó una contraseña temporal';
    case 'revoke_sessions':
      return 'Cerró sesiones del usuario';
    case 'clear_login_blocks':
      return 'Retiró bloqueos de acceso';
    case 'revoke_disabled_sessions':
      return 'Cerró las sesiones del personal inhabilitado'
          '${entry.count == null ? '' : ' (${entry.count})'}';
    default:
      return entry.action.isEmpty ? 'Acción de seguridad' : entry.action;
  }
}

class _EmptySecurityState extends StatelessWidget {
  const _EmptySecurityState();

  @override
  Widget build(BuildContext context) {
    return const Card(
      elevation: 0,
      child: Padding(
        padding: EdgeInsets.all(30),
        child: Column(
          children: [
            Icon(
              Icons.manage_search_outlined,
              size: 42,
              color: Color(0xFF64748B),
            ),
            SizedBox(height: 10),
            Text('No hay personas para este filtro.'),
          ],
        ),
      ),
    );
  }
}
