// lib/talento_humano/talento_humano_dashboard_screen.dart

import 'package:flutter/material.dart';
import '../admin/collections_explorer_screen.dart';
import 'notificaciones_talento_humano_screen.dart';
import 'areas_management_screen.dart';

// Importamos con alias para evitar colisiones de nombre:
import 'organizational_structure_screen.dart' as os;
import 'cargos_management_screen.dart' as cs;

const Color _khPrimary   = Color(0xffc28942);
const Color _khSecondary = Color(0xffe19e4c);
const String _kFont      = 'Arial';

/// Panel de control de Talento Humano
/// Recibe [userId] para pasar a la pantalla de notificaciones
class TalentoHumanoDashboardScreen extends StatelessWidget {
  final String userId;
  const TalentoHumanoDashboardScreen({
    Key? key,
    required this.userId,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Talento Humano', style: TextStyle(fontFamily: _kFont)),
        backgroundColor: _khPrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildButton(
            context,
            label: 'Gestionar Áreas',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AreasManagementScreen(userId: userId),
                ),
              );
            },
          ),
          const SizedBox(height: 12),

          _buildButton(
            context,
            label: 'Gestionar Cargos',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const cs.CargosManagementScreen(),
                ),
              );
            },
          ),
          const SizedBox(height: 12),

          _buildButton(
            context,
            label: 'Gestionar Estructura Organizacional',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const os.OrganizationalStructureScreen(),
                ),
              );
            },
          ),
          const SizedBox(height: 12),

          _buildButton(
            context,
            label: 'Notificaciones TH',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => NotificacionesTalentoHumanoScreen(userId: userId),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildButton(
      BuildContext context, {
        required String label,
        required VoidCallback onTap,
      }) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: _khSecondary,
        padding: const EdgeInsets.symmetric(vertical: 16),
        textStyle: const TextStyle(fontFamily: _kFont, fontSize: 16),
      ),
      onPressed: onTap,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(label),
      ),
    );
  }
}
