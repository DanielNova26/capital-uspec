// lib/login/registration_screen.dart
// Wrapper de compatibilidad: delega a HojaDeVidaScreen en modo registro.
import 'package:flutter/material.dart';
import '../talento_humano/hoja_de_vida_screen.dart';

// Re-exportar formateadores para compatibilidad con cualquier import existente
export '../talento_humano/hoja_de_vida_screen.dart'
    show HojaDeVidaScreen, HvMode;

class RegistrationScreen extends StatelessWidget {
  final String cedula;
  final String empresaId;

  const RegistrationScreen({
    super.key,
    required this.cedula,
    required this.empresaId,
  });

  @override
  Widget build(BuildContext context) {
    return HojaDeVidaScreen(
      userId: cedula,
      empresaId: empresaId,
      mode: HvMode.registro,
    );
  }
}
