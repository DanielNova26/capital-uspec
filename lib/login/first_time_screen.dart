//lib/login/first_time_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'login_screen.dart';
import 'data_policy_screen.dart';

class FirstTimeScreen extends StatefulWidget {
  const FirstTimeScreen({Key? key}) : super(key: key);

  @override
  State<FirstTimeScreen> createState() => _FirstTimeScreenState();
}

class _FirstTimeScreenState extends State<FirstTimeScreen> {
  final _formKey = GlobalKey<FormState>();
  String cedula = '';
  String empresaId = '';
  bool _isLoading = false;
  String? _error;

  Future<void> _verificarCedula(BuildContext context) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final usuariosCol =
      FirebaseFirestore.instance.collection('TBL_USUARIOS');

      // hoja puede ser null si invalidamos el documento inicial
      DocumentSnapshot<Map<String, dynamic>>? hoja =
      await usuariosCol.doc(cedula).get();

      // 1. Intento por ID de documento (cedula como ID)
      if (hoja.exists) {
        final empresaDoc =
            (hoja.data()?['empresaId'] as String?)?.trim() ?? '';
        // Si el empresaId no coincide, ignoramos este documento
        if (empresaDoc != empresaId) {
          hoja = null;
        }
      }

      // 2. Si no encontramos por ID o lo invalidamos, buscamos por campos
      if (hoja == null || !hoja.exists) {
        final query = await usuariosCol
            .where('cedula', isEqualTo: cedula)
            .where('empresaId', isEqualTo: empresaId)
            .limit(1)
            .get();

        if (query.docs.isNotEmpty) {
          hoja = query.docs.first;
        }
      }

      // 3. Si encontramos un registro válido, creamos/actualizamos el usuario de acceso
      if (hoja != null && hoja.exists) {
        final data = hoja.data()!;
        final primerNombre = (data['primerNombre'] ?? '')
            .toString()
            .split(' ')
            .first
            .toLowerCase();
        final primerApellido = (data['primerApellido'] ?? '')
            .toString()
            .split(' ')
            .first
            .toLowerCase();
        final usuario = "$primerNombre.$primerApellido";
        final contrasena = "123456";

        final userRef = usuariosCol.doc(usuario);

        await userRef.set({
          'usuario': usuario,
          'cedula': cedula,
          'password': contrasena,
          'empresaId': empresaId,
          'primerNombre': data['primerNombre'],
          'primerApellido': data['primerApellido'],
          'role': 'usuario',
          'needsPasswordChange': true,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        setState(() => _isLoading = false);

        // Mostrar diálogo de éxito
        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text("¡Usuario creado!"),
            content: Text(
              "Usuario: $usuario\n"
                  "Contraseña temporal: $contrasena\n\n"
                  "Por favor cambia tu contraseña luego de ingresar.",
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context); // cierra el diálogo
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(
                        builder: (_) => const LoginScreen()),
                        (_) => false,
                  );
                },
                child: const Text("Ir al login"),
              ),
            ],
          ),
        );
      } else {
        setState(() => _isLoading = false);
        // No existe en TBL_USUARIOS -> ir a política de datos
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DataPolicyScreen(
              cedula: cedula,
              empresaId: empresaId,
            ),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'Ocurrió un error. Intenta de nuevo.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Primer Ingreso"),
        backgroundColor: const Color(0xFF1975B8),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "Ingrese su número de cédula para validar su información.",
                      style: TextStyle(fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      decoration: const InputDecoration(
                        labelText: "Cédula",
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (v) => cedula = v.trim(),
                      validator: (v) =>
                      v == null || v.trim().isEmpty
                          ? "Ingrese la cédula"
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      decoration: const InputDecoration(
                        labelText: "Empresa ID",
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) => empresaId = v.trim(),
                      validator: (v) =>
                      v == null || v.trim().isEmpty
                          ? "Ingrese el ID de la empresa"
                          : null,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE19E4C),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: _isLoading
                            ? null
                            : () async {
                          if (_formKey.currentState!.validate()) {
                            await _verificarCedula(context);
                          }
                        },
                        child: _isLoading
                            ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                            : const Text("Validar"),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
