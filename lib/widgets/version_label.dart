// lib/widgets/version_label.dart
//
// Etiqueta con la versión instalada. Sirve para dos cosas concretas:
//
// 1. Soporte. La primera pregunta ante cualquier reporte es "¿qué versión
//    tienes?", y hasta ahora no había forma de que el usuario lo supiera.
// 2. Verificar despliegues. En web permite confirmar de un vistazo que el
//    navegador está sirviendo la build nueva y no una cacheada.
//
// Muestra nombre de versión y número de build, porque el build es el que
// realmente distingue dos envíos con el mismo nombre: durante la publicación
// hubo cuatro builds distintos llamados todos "1.0.0".

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

class VersionLabel extends StatefulWidget {
  final TextStyle? style;
  final EdgeInsetsGeometry padding;

  const VersionLabel({
    super.key,
    this.style,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  });

  @override
  State<VersionLabel> createState() => _VersionLabelState();
}

class _VersionLabelState extends State<VersionLabel> {
  String? _texto;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final build = info.buildNumber.trim();
      if (!mounted) return;
      setState(() {
        _texto = build.isEmpty
            ? 'Versión ${info.version}'
            : 'Versión ${info.version} (${build})';
      });
    } catch (_) {
      // Si no se puede leer, no se muestra nada: una etiqueta de versión rota
      // confunde más que su ausencia.
    }
  }

  @override
  Widget build(BuildContext context) {
    final texto = _texto;
    if (texto == null) return const SizedBox.shrink();
    return Padding(
      padding: widget.padding,
      child: Text(
        texto,
        textAlign: TextAlign.center,
        style:
            widget.style ??
            TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.outline,
            ),
      ),
    );
  }
}
