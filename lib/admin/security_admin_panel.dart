import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';

import '../widgets/user_avatar.dart';
import 'security_admin_service.dart';

enum _SecurityFilter {
  all,
  secure,
  pendingMigration,
  passwordChange,
  blocked,
  inactive,
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
          _summaryGrid(
            users.length,
            secure,
            migration,
            passwordChange,
            blocked,
            mobile,
          ),
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
                      _statusChip(
                        user.lastLoginAt == null
                            ? 'Sin ingreso registrado'
                            : 'Último: ${DateFormat('dd/MM/yy HH:mm').format(user.lastLoginAt!)}',
                        Icons.history,
                        const Color(0xFF475569),
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
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
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
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 14),
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
        'Las acciones sensibles quedan registradas sin guardar contraseñas.',
      ),
      children: entries.isEmpty
          ? const [
              Padding(
                padding: EdgeInsets.all(20),
                child: Text('Aún no hay acciones administrativas registradas.'),
              ),
            ]
          : entries
                .map(
                  (entry) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.shield_outlined, size: 20),
                    title: Text(_auditLabel(entry.action)),
                    subtitle: Text(
                      'Usuario: ${entry.targetUserDocId} · Administró: ${entry.actorUserDocId}',
                    ),
                    trailing: Text(
                      entry.createdAt == null
                          ? '-'
                          : DateFormat(
                              'dd/MM/yy HH:mm',
                            ).format(entry.createdAt!),
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                )
                .toList(),
    );
  }

  String _auditLabel(String action) {
    switch (action) {
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
      default:
        return action.isEmpty ? 'Acción de seguridad' : action;
    }
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
