// lib/login/data_policy_screen.dart
import 'package:flutter/material.dart';

import 'instruction_screen.dart';

const String kArial = 'Arial';

class DataPolicyScreen extends StatelessWidget {
  final String cedula;
  final String empresaId;
  final String? empresaNombre;
  final String? colaboradorNombre;
  final bool accessCreated;

  const DataPolicyScreen({
    super.key,
    required this.cedula,
    required this.empresaId,
    this.empresaNombre,
    this.colaboradorNombre,
    this.accessCreated = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 820;
    final displayEmpresa = (empresaNombre?.trim().isNotEmpty ?? false)
        ? empresaNombre!
        : empresaId;
    final displayName = (colaboradorNombre?.trim().isNotEmpty ?? false)
        ? colaboradorNombre!
        : 'Colaborador';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tratamiento de datos'),
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: isDesktop ? 32 : 18,
            vertical: isDesktop ? 28 : 18,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _HeaderCard(
                  displayName: displayName,
                  displayEmpresa: displayEmpresa,
                  accessCreated: accessCreated,
                ),
                const SizedBox(height: 14),
                Card(
                  elevation: isDesktop ? 2 : 0,
                  margin: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(isDesktop ? 28 : 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Autorizacion para uso de informacion personal',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontFamily: kArial,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Autorizo a To Do App y a $displayEmpresa para recolectar, almacenar, consultar, procesar, actualizar y utilizar la informacion personal suministrada durante mi registro y en mi hoja de vida.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontFamily: kArial,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 18),
                        _PolicyPoint(
                          icon: Icons.assignment_ind_outlined,
                          title: 'Gestion de talento humano',
                          body:
                              'La informacion se usara para validar identidad, hoja de vida, soportes, datos laborales y procesos internos de Talento Humano.',
                        ),
                        _PolicyPoint(
                          icon: Icons.folder_shared_outlined,
                          title: 'Documentos y soportes',
                          body:
                              'Los archivos que adjuntes se almacenan en la plataforma y deben corresponder a documentos reales en formato PDF cuando el campo lo solicite.',
                        ),
                        _PolicyPoint(
                          icon: Icons.privacy_tip_outlined,
                          title: 'Datos demograficos',
                          body:
                              'Los datos de perfil demografico quedan para gestion interna y no hacen parte del PDF de hoja de vida generado para revision.',
                        ),
                        _PolicyPoint(
                          icon: Icons.update_rounded,
                          title: 'Actualizacion y correcciones',
                          body:
                              'Si Talento Humano solicita correcciones, To Do App registrara la fecha de devolucion, edicion y reenvio para trazabilidad.',
                        ),
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => InstructionScreen(
                                  cedula: cedula,
                                  empresaId: empresaId,
                                  empresaNombre: displayEmpresa,
                                  colaboradorNombre: displayName,
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.check_circle_outline_rounded),
                          label: const Text('Acepto y continuar'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            textStyle: const TextStyle(
                              fontFamily: kArial,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final String displayName;
  final String displayEmpresa;
  final bool accessCreated;

  const _HeaderCard({
    required this.displayName,
    required this.displayEmpresa,
    required this.accessCreated,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.12)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.verified_user_outlined, color: scheme.onPrimary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bienvenido a To Do App',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontFamily: kArial,
                    fontWeight: FontWeight.w900,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$displayName · $displayEmpresa',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: kArial,
                    color: scheme.onPrimaryContainer.withValues(alpha: 0.78),
                  ),
                ),
                if (accessCreated) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Tu acceso fue activado con contrasena temporal 123456. Al iniciar sesion deberas cambiarla.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: kArial,
                      color: scheme.onPrimaryContainer.withValues(alpha: 0.82),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PolicyPoint extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _PolicyPoint({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: scheme.secondaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 19, color: scheme.onSecondaryContainer),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontFamily: kArial,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: kArial,
                    color: scheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
