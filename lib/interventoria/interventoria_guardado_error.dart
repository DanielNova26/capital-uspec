import 'package:flutter/material.dart';

/// Permanece sobre la hoja de registro; cerrarlo conserva el formulario.
class InterventoriaGuardadoError extends StatelessWidget {
  final Object error;
  final String etapa;
  final bool actaPersistida;

  const InterventoriaGuardadoError({
    super.key,
    required this.error,
    required this.etapa,
    required this.actaPersistida,
  });

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      actaPersistida
          ? 'El acta ya está guardada'
          : 'No se pudo guardar el acta',
    ),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Paso: $etapa'),
            const SizedBox(height: 12),
            SelectableText(
              error is StateError ? (error as StateError).message : '$error',
            ),
            const SizedBox(height: 16),
            Text(
              actaPersistida
                  ? 'Quedó pendiente este paso. Revisa el acta en el histórico; no la registres de nuevo.'
                  : 'Los datos del formulario siguen disponibles al cerrar este aviso.',
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Volver al formulario'),
      ),
    ],
  );
}
