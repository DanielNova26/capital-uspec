// lib/login/instruction_screen.dart
import 'package:flutter/material.dart';

import 'registration_screen.dart';

const String _kArial = 'Arial';

class InstructionScreen extends StatelessWidget {
  final String cedula;
  final String empresaId;
  final String? empresaNombre;
  final String? colaboradorNombre;

  const InstructionScreen({
    super.key,
    required this.cedula,
    required this.empresaId,
    this.empresaNombre,
    this.colaboradorNombre,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 900;
    final displayEmpresa = (empresaNombre?.trim().isNotEmpty ?? false)
        ? empresaNombre!
        : empresaId;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Antes de empezar'),
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
            constraints: const BoxConstraints(maxWidth: 980),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _IntroPanel(
                  empresaNombre: displayEmpresa,
                  colaboradorNombre: colaboradorNombre,
                ),
                const SizedBox(height: 16),
                GridView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: isDesktop ? 2 : 1,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                    childAspectRatio: isDesktop ? 2.7 : 2.25,
                  ),
                  children: const [
                    _InstructionCard(
                      icon: Icons.picture_as_pdf_outlined,
                      title: 'Ten tus soportes en PDF',
                      body:
                          'Cedula, EPS, fondo de pensiones, cesantias, estudios, cursos, antecedentes y experiencia deben subirse en PDF cuando el formulario lo solicite.',
                    ),
                    _InstructionCard(
                      icon: Icons.account_circle_outlined,
                      title: 'Prepara tu foto de perfil',
                      body:
                          'Carga una imagen clara tipo carnet. Se usara en tu hoja de vida y en tu perfil dentro de To Do App.',
                    ),
                    _InstructionCard(
                      icon: Icons.manage_search_rounded,
                      title: 'Usa los desplegables con busqueda',
                      body:
                          'Departamento, ciudad, EPS, fondos, banco y otros catalogos permiten buscar y escribir para completar mas rapido.',
                    ),
                    _InstructionCard(
                      icon: Icons.diversity_3_outlined,
                      title: 'Completa el perfil demografico',
                      body:
                          'Estado civil, hijos, sangre, contacto de emergencia, nacimiento, genero, personas a cargo, estrato y tipo de vehiculo quedan para gestion interna.',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _FlowCard(),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (_) => RegistrationScreen(
                          cedula: cedula,
                          empresaId: empresaId,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.edit_document),
                  label: const Text('Empezar hoja de vida'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    textStyle: const TextStyle(
                      fontFamily: _kArial,
                      fontWeight: FontWeight.w800,
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

class _IntroPanel extends StatelessWidget {
  final String empresaNombre;
  final String? colaboradorNombre;

  const _IntroPanel({required this.empresaNombre, this.colaboradorNombre});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final name = (colaboradorNombre?.trim().isNotEmpty ?? false)
        ? colaboradorNombre!.trim()
        : 'Tu registro';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.12)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(Icons.fact_check_outlined, color: scheme.onPrimary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontFamily: _kArial,
                    fontWeight: FontWeight.w900,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Completaras tu hoja de vida para $empresaNombre. Al enviarla, Talento Humano podra revisarla, aprobarla o solicitar correcciones con trazabilidad.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: _kArial,
                    color: scheme.onPrimaryContainer.withValues(alpha: 0.8),
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

class _InstructionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _InstructionCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      elevation: 1,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: scheme.secondaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: scheme.onSecondaryContainer),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontFamily: _kArial,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    body,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: _kArial,
                      color: scheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FlowCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      elevation: 1,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Flujo de revision',
              style: theme.textTheme.titleMedium?.copyWith(
                fontFamily: _kArial,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            const _FlowStep(
              number: '1',
              label: 'Completa y guarda la informacion solicitada.',
            ),
            const _FlowStep(
              number: '2',
              label: 'Revisa la vista previa y envia la hoja de vida.',
            ),
            const _FlowStep(
              number: '3',
              label:
                  'Talento Humano valida el contenido y los soportes cargados.',
            ),
            const _FlowStep(
              number: '4',
              label:
                  'Si hay correcciones, recibiras una notificacion que abre directamente el documento a ajustar.',
            ),
            const _FlowStep(
              number: '5',
              label:
                  'Para consultar aprobaciones o correcciones debes iniciar sesion en To Do App con tu cedula y contrasena.',
            ),
          ],
        ),
      ),
    );
  }
}

class _FlowStep extends StatelessWidget {
  final String number;
  final String label;

  const _FlowStep({required this.number, required this.label});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.primary,
              shape: BoxShape.circle,
            ),
            child: Text(
              number,
              style: TextStyle(
                color: scheme.onPrimary,
                fontFamily: _kArial,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontFamily: _kArial,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
