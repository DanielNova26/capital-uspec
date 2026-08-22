// lib/widgets/user_avatar.dart
//
// Widgets compartidos para mostrar usuarios de forma consistente en toda
// la app (Web y Móvil): foto si existe, iniciales del nombre si no, y un
// ícono de persona como último recurso (nunca el dígito de la cédula).
//
// - UserAvatar:   avatar circular con foto / iniciales / ícono.
// - UserNameText: texto con el nombre resuelto (nunca la cédula si el
//                 usuario existe en TBL_USUARIOS).
//
// Ambos usan UserDirectory (caché por sesión), por lo que cada usuario se
// lee de Firestore una sola vez aunque aparezca en muchas tarjetas.

import 'package:flutter/material.dart';

import '../core/user_directory.dart';

const String _kFont = 'Arial';

/// Avatar circular de usuario: foto → iniciales → ícono de persona.
class UserAvatar extends StatelessWidget {
  /// Cédula / docId en TBL_USUARIOS. Si es vacío se usa solo [nameHint].
  final String? userId;

  /// Nombre ya conocido por el caller (evita esperar la resolución para
  /// las iniciales). Si parece una cédula se ignora.
  final String? nameHint;

  /// URL de foto ya conocida por el caller (se muestra de inmediato).
  final String? fotoUrlHint;

  final double radius;
  final Color? backgroundColor;
  final Color? foregroundColor;

  const UserAvatar({
    super.key,
    this.userId,
    this.nameHint,
    this.fotoUrlHint,
    this.radius = 18,
    this.backgroundColor,
    this.foregroundColor,
  });

  bool get _hintIsRealName {
    final n = (nameHint ?? '').trim();
    if (n.isEmpty) return false;
    if (n == (userId ?? '').trim()) return false;
    return RegExp(r'[A-Za-zÁÉÍÓÚÑáéíóúñ]').hasMatch(n);
  }

  String _initialsFrom(String name) {
    final words = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) =>
            w.isNotEmpty &&
            RegExp(r'[A-Za-zÁÉÍÓÚÑáéíóúñ]').hasMatch(w[0]))
        .take(2);
    return words.map((w) => w[0].toUpperCase()).join();
  }

  @override
  Widget build(BuildContext context) {
    final id = (userId ?? '').trim();
    final hintFoto = (fotoUrlHint ?? '').trim();

    if (hintFoto.isNotEmpty) {
      return _avatar(context, fotoUrl: hintFoto, initials: _hintInitials());
    }
    if (id.isEmpty) {
      return _avatar(context, fotoUrl: '', initials: _hintInitials());
    }

    final cached = UserDirectory.instance.peek(id);
    if (cached != null) {
      return _avatar(
        context,
        fotoUrl: cached.fotoUrl,
        initials: cached.iniciales.isNotEmpty ? cached.iniciales : _hintInitials(),
      );
    }

    return FutureBuilder<UserDisplayInfo>(
      future: UserDirectory.instance.resolve(id),
      builder: (context, snap) {
        final info = snap.data;
        return _avatar(
          context,
          fotoUrl: info?.fotoUrl ?? '',
          initials: (info != null && info.iniciales.isNotEmpty)
              ? info.iniciales
              : _hintInitials(),
        );
      },
    );
  }

  String _hintInitials() =>
      _hintIsRealName ? _initialsFrom(nameHint!) : '';

  Widget _avatar(BuildContext context,
      {required String fotoUrl, required String initials}) {
    final scheme = Theme.of(context).colorScheme;
    final bg = backgroundColor ?? scheme.primary.withOpacity(0.12);
    final fg = foregroundColor ?? scheme.primary;

    return CircleAvatar(
      radius: radius,
      backgroundColor: bg,
      foregroundImage: fotoUrl.isNotEmpty ? NetworkImage(fotoUrl) : null,
      onForegroundImageError: fotoUrl.isNotEmpty ? (_, __) {} : null,
      child: initials.isNotEmpty
          ? Text(
              initials,
              style: TextStyle(
                fontFamily: _kFont,
                fontWeight: FontWeight.bold,
                fontSize: radius * 0.72,
                color: fg,
              ),
            )
          : Icon(Icons.person_rounded, size: radius * 1.1, color: fg),
    );
  }
}

/// Texto con el nombre del usuario resuelto desde UserDirectory.
///
/// Si [fallbackName] ya es un nombre real lo muestra sin leer Firestore.
/// Si solo se conoce la cédula, muestra la cédula mientras resuelve y la
/// reemplaza por el nombre al llegar.
class UserNameText extends StatelessWidget {
  final String userId;
  final String? fallbackName;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  /// Prefijo opcional, p. ej. 'Por: '.
  final String prefix;

  const UserNameText(
    this.userId, {
    super.key,
    this.fallbackName,
    this.style,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
    this.prefix = '',
  });

  bool get _fallbackIsRealName {
    final n = (fallbackName ?? '').trim();
    if (n.isEmpty) return false;
    if (n == userId.trim()) return false;
    return RegExp(r'[A-Za-zÁÉÍÓÚÑáéíóúñ]').hasMatch(n);
  }

  @override
  Widget build(BuildContext context) {
    final id = userId.trim();

    if (_fallbackIsRealName || id.isEmpty) {
      return _text((fallbackName ?? '').trim().isNotEmpty
          ? fallbackName!.trim()
          : id);
    }

    final cached = UserDirectory.instance.peek(id);
    if (cached != null) return _text(cached.displayName);

    return FutureBuilder<UserDisplayInfo>(
      future: UserDirectory.instance.resolve(id),
      builder: (context, snap) {
        final info = snap.data;
        return _text(info?.displayName ?? id);
      },
    );
  }

  Widget _text(String value) => Text(
        '$prefix$value',
        style: style,
        maxLines: maxLines,
        overflow: overflow,
      );
}
