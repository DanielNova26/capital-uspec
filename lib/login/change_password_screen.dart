// lib/login/change_password_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'login_screen.dart'; // Ajusta la ruta si tu LoginScreen está en otra carpeta

const Color kMarronOscuro = Color(0xffc28942);
const String kArial = 'Arial';

class ChangePasswordScreen extends StatefulWidget {
  final String usuario;
  const ChangePasswordScreen({Key? key, required this.usuario}) : super(key: key);

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();

  // Controladores para la nueva contraseña
  final _newPassCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();

  // Controladores para las respuestas de seguridad
  final _answer1Ctrl = TextEditingController();
  final _answer2Ctrl = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;

  // Lista de 10 preguntas de seguridad
  final List<String> _preguntas = [
    '¿Cuál es el nombre de tu primera mascota?',
    '¿Cuál era tu libro favorito de niño?',
    '¿Cuál es el nombre de tu escuela primaria?',
    '¿Cuál es el nombre de tu ciudad natal?',
    '¿Cuál es el segundo nombre de tu madre?',
    '¿Cuál es tu comida favorita?',
    '¿Cuál fue tu primer concierto?',
    '¿Cuál es la marca de tu primer automóvil?',
    '¿Cuál es el nombre de tu mejor amigo de la infancia?',
    '¿Cuál es el nombre de tu abuelo paterno?'
  ];

  // Preguntas seleccionadas por el usuario
  String? _selectedQuestion1;
  String? _selectedQuestion2;

  @override
  void dispose() {
    _newPassCtrl.dispose();
    _confirmPassCtrl.dispose();
    _answer1Ctrl.dispose();
    _answer2Ctrl.dispose();
    super.dispose();
  }

  Future<void> _submitChange() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 1) Actualizar Firestore: contraseña y preguntas/respuestas de seguridad, y needsPasswordChange = false
      final docRef = FirebaseFirestore.instance.collection('TBL_USUARIOS').doc(widget.usuario);

      await docRef.update({
        'password': _newPassCtrl.text.trim(),
        'pregunta_seguridad_1': _selectedQuestion1,
        'respuesta_seguridad_1': _answer1Ctrl.text.trim(),
        'pregunta_seguridad_2': _selectedQuestion2,
        'respuesta_seguridad_2': _answer2Ctrl.text.trim(),
        'needsPasswordChange': false,
      });

      setState(() => _isLoading = false);

      // 2) Mostrar diálogo de éxito
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('¡Contraseña y seguridad actualizadas!'),
          content: const Text(
            'Tu contraseña y preguntas de seguridad han sido guardadas correctamente.\n'
                'Ahora podrás iniciar sesión con tu nueva contraseña.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context); // Cierra el diálogo
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );

      // 3) Regresar al LoginScreen, borrando toda la pila
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
            (route) => false,
      );
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error al actualizar la contraseña. Intenta de nuevo.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cambiar Contraseña'),
        backgroundColor: kMarronOscuro,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            children: [
              Text(
                'Hola, ${widget.usuario}',
                style: const TextStyle(
                  fontFamily: kArial,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: kMarronOscuro,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Debes completar tus preguntas de seguridad y cambiar tu contraseña temporal.',
                style: TextStyle(fontFamily: kArial, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Desplegable Pregunta 1 con contraste y expansión
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Pregunta de seguridad 1',
                        border: OutlineInputBorder(),
                      ),
                      style: const TextStyle(
                        fontFamily: kArial,
                        color: Colors.black,
                      ),
                      dropdownColor: Colors.white,
                      iconEnabledColor: kMarronOscuro,
                      items: _preguntas.map((pregunta) {
                        return DropdownMenuItem(
                          value: pregunta,
                          child: Text(
                            pregunta,
                            style: const TextStyle(fontFamily: kArial, color: Colors.black),
                          ),
                        );
                      }).toList(),
                      value: _selectedQuestion1,
                      onChanged: (value) {
                        setState(() {
                          _selectedQuestion1 = value;
                          // Si coincide con la otra, la limpia
                          if (_selectedQuestion2 == value) {
                            _selectedQuestion2 = null;
                          }
                        });
                      },
                      validator: (v) {
                        if (v == null || v.isEmpty) {
                          return 'Selecciona la pregunta 1';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),

                    // Campo Respuesta 1
                    TextFormField(
                      controller: _answer1Ctrl,
                      decoration: const InputDecoration(
                        labelText: 'Respuesta 1',
                        border: OutlineInputBorder(),
                      ),
                      style: const TextStyle(fontFamily: kArial),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Ingresa la respuesta 1';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),

                    // Desplegable Pregunta 2 con contraste y expansión
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Pregunta de seguridad 2',
                        border: OutlineInputBorder(),
                      ),
                      style: const TextStyle(
                        fontFamily: kArial,
                        color: Colors.black,
                      ),
                      dropdownColor: Colors.white,
                      iconEnabledColor: kMarronOscuro,
                      items: _preguntas.map((pregunta) {
                        return DropdownMenuItem(
                          value: pregunta,
                          child: Text(
                            pregunta,
                            style: const TextStyle(fontFamily: kArial, color: Colors.black),
                          ),
                        );
                      }).toList(),
                      value: _selectedQuestion2,
                      onChanged: (value) {
                        setState(() {
                          _selectedQuestion2 = value;
                          // Si coincide con la otra, la limpia
                          if (_selectedQuestion1 == value) {
                            _selectedQuestion1 = null;
                          }
                        });
                      },
                      validator: (v) {
                        if (v == null || v.isEmpty) {
                          return 'Selecciona la pregunta 2';
                        }
                        if (v == _selectedQuestion1) {
                          return 'Debe ser distinta a la pregunta 1';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),

                    // Campo Respuesta 2
                    TextFormField(
                      controller: _answer2Ctrl,
                      decoration: const InputDecoration(
                        labelText: 'Respuesta 2',
                        border: OutlineInputBorder(),
                      ),
                      style: const TextStyle(fontFamily: kArial),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Ingresa la respuesta 2';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),

                    const Divider(thickness: 1, color: Colors.grey),
                    const SizedBox(height: 24),

                    // Nueva contraseña
                    TextFormField(
                      controller: _newPassCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Nueva contraseña',
                        border: OutlineInputBorder(),
                      ),
                      style: const TextStyle(fontFamily: kArial),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Ingresa la nueva contraseña';
                        }
                        if (v.trim().length < 6) {
                          return 'Mínimo 6 caracteres';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Confirmar contraseña
                    TextFormField(
                      controller: _confirmPassCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Confirmar contraseña',
                        border: OutlineInputBorder(),
                      ),
                      style: const TextStyle(fontFamily: kArial),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Confirma tu contraseña';
                        }
                        if (v.trim() != _newPassCtrl.text.trim()) {
                          return 'No coincide con la nueva contraseña';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),

                    if (_errorMessage != null) ...[
                      Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.red, fontFamily: kArial),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Botón “Actualizar contraseña”
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kMarronOscuro,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          textStyle: const TextStyle(
                            fontFamily: kArial,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onPressed: _isLoading ? null : _submitChange,
                        child: _isLoading
                            ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                            : const Text('Actualizar contraseña'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
