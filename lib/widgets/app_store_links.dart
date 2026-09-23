// lib/widgets/app_store_links.dart
//
// Botones "Descargar en Google Play / App Store". Solo se pintan en web
// (ver `core/app_stores.dart`): en el teléfono ya se está dentro de la app.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_stores.dart';
import '../theme/app_typography.dart';

class AppStoreLinks extends StatelessWidget {
  /// Botones en fila (login) o apilados (menú lateral).
  final bool apilados;
  final EdgeInsetsGeometry padding;

  const AppStoreLinks({
    super.key,
    this.apilados = false,
    this.padding = EdgeInsets.zero,
  });

  Future<void> _abrir(BuildContext context, String url) async {
    final ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No fue posible abrir la tienda.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!mostrarEnlacesTiendas) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;

    Widget boton(String tienda, IconData icono, String url) =>
        OutlinedButton.icon(
          onPressed: () => _abrir(context, url),
          style: OutlinedButton.styleFrom(
            foregroundColor: scheme.onSurface,
            side: BorderSide(color: scheme.outlineVariant),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(9),
            ),
          ),
          icon: Icon(icono, size: 18),
          label: Text(
            'Descargar en $tienda',
            style: const TextStyle(
              fontFamily: kArial,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        );

    final botones = <Widget>[
      if (kUrlPlayStore.isNotEmpty)
        boton('Google Play', Icons.android_rounded, kUrlPlayStore),
      if (kUrlAppStore.isNotEmpty)
        boton('App Store', Icons.phone_iphone_rounded, kUrlAppStore),
    ];

    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Lleva la app en tu celular',
            textAlign: apilados ? TextAlign.start : TextAlign.center,
            style: TextStyle(
              fontFamily: kArial,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          if (apilados)
            for (var i = 0; i < botones.length; i++) ...[
              if (i > 0) const SizedBox(height: 6),
              botones[i],
            ]
          else
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: botones,
            ),
        ],
      ),
    );
  }
}
