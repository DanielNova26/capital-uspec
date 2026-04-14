// lib/talento_humano/talento_humano_dashboard_screen.dart

import 'package:flutter/material.dart';
import '../core/guarded_module_page.dart';
import '../widgets/internal_module_layout.dart';
import 'notificaciones_talento_humano_screen.dart';
import 'areas_management_screen.dart';
import 'organizational_structure_screen.dart';
import 'cargos_management_screen.dart';

const Color _khPrimary = Color(0xFFC28942);
const String _kFont = 'Arial';

class TalentoHumanoDashboardScreen extends StatelessWidget {
  final String userId;
  final String empresaId;

  const TalentoHumanoDashboardScreen({
    super.key,
    required this.userId,
    required this.empresaId,
  });

  @override
  Widget build(BuildContext context) {
    return GuardedModulePage(
      userIdentity: userId,
      appId: 'talentohumanodashboard',
      pageTitle: 'Talento Humano',
      fallbackEmpresaId: empresaId,
      child: InternalModuleLayout(
        userId: userId,
        empresaId: empresaId,
        title: 'Talento Humano',
        subtitle: 'Gestión de colaboradores, cargos y estructura organizacional',
        accentColor: _khPrimary,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 800),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionTitle('ORGANIZACIÓN'),
                  const SizedBox(height: 16),
                  _MenuButton(
                    label: 'Gestionar Áreas',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AreasManagementScreen(
                          userId: userId,
                          empresaId: empresaId,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _MenuButton(
                    label: 'Gestionar Cargos',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CargosManagementScreen(
                          userId: userId,
                          empresaId: empresaId,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _MenuButton(
                    label: 'Gestionar Estructura Organizacional',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => OrganizationalStructureScreen(
                          userId: userId,
                          empresaId: empresaId,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  _buildSectionTitle('COMUNICACIÓN'),
                  const SizedBox(height: 16),
                  _MenuButton(
                    label: 'Notificaciones TH',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => NotificacionesTalentoHumanoScreen(
                          userId: userId,
                          empresaId: empresaId,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontFamily: _kFont,
        fontWeight: FontWeight.w900,
        fontSize: 12,
        color: Color(0xFF64748B),
        letterSpacing: 1.5,
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _MenuButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ModuleCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: _kFont,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E293B),
              ),
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: Color(0xFF64748B)),
        ],
      ),
    );
  }
}
