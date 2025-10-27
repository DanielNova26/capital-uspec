//lib/login/data_policy_screen.dart
import 'package:flutter/material.dart';
import 'instruction_screen.dart';

// Usa las mismas constantes globales para colores y fuente
const Color kMarronOscuro = Color(0xffc28942);
const Color kMarronClaro = Color(0xffe19e4c);
const String kArial = 'Arial';

class DataPolicyScreen extends StatelessWidget {
  final String cedula;
  const DataPolicyScreen({Key? key, required this.cedula}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Política de Tratamiento de Datos',
          style: TextStyle(
            fontFamily: kArial,
            fontWeight: FontWeight.bold,
            fontSize: 17,
            color: Colors.white,
            letterSpacing: 1,
          ),
        ),
        backgroundColor: kMarronClaro,
        centerTitle: true,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  'AUTORIZO a la UNIÓN TEMPORAL CAPITAL USPEC 2025, para que recolecte, almacene, consulte, procese, actualice y utilice la información personal contenida en mi hoja de vida, '
                      'así como cualquier otro dato suministrado durante el proceso de selección y contratación.',
                  style: const TextStyle(
                    fontFamily: kArial,
                    fontSize: 16,
                    height: 1.5,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.justify,
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => InstructionScreen(cedula: cedula),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: kMarronClaro,
                  foregroundColor: Colors.white,
                  textStyle: const TextStyle(
                    fontFamily: kArial,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 1,
                ),
                child: const Text('Acepto'),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}
