// lib/login/instruction_screen.dart

import 'package:flutter/material.dart';
import 'lib/login/package:registration_screen.dart';

class InstructionScreen extends StatelessWidget {
  final String cedula;
  const InstructionScreen({Key? key, required this.cedula}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Instrucciones de Registro'),
        backgroundColor: const Color(0xFFE19E4C),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  'Para un registro exitoso, por favor:\n\n'
                      '1. Captura tu fotografía tipo carnet con buena iluminación.\n'
                      '2. Prepara los siguientes documentos escaneados en PDF:\n'
                      '   • Soportes laborales.\n'
                      '   • Certificados de estudios.\n'
                      '   • Tarjeta profesional.\n'
                      '   • Cédula de ciudadanía (anverso y reverso).\n\n'
                      'Ten todo listo antes de continuar para agilizar el proceso.',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) => RegistrationScreen(cedula: cedula),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE19E4C),
                minimumSize: const Size.fromHeight(48),
              ),
              child: const Text('Siguiente'),
            ),
          ],
        ),
      ),
    );
  }
}
