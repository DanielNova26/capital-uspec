// lib/login/forgot_password_screen.dart

import 'package:flutter/material.dart';
import '../services/secure_auth_service.dart';
import 'login_screen.dart'; // Ajusta la ruta si tu LoginScreen está en otra ubicación

const Color kMarronOscuro = Color(0xffc28942);
const String kArial = 'Arial';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({Key? key}) : super(key: key);

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usuarioOrCedulaCtrl = TextEditingController();
  final _answer1Ctrl = TextEditingController();
  final _answer2Ctrl = TextEditingController();
  final _newPassCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;
  bool _userExists = false;
  bool _questionsLoaded = false;

  // Variables para almacenar preguntas/respuestas traídas de Firestore
  String? _storedPregunta1;
  String? _storedPregunta2;
  String? _recoveryChallengeId;

  @override
  void dispose() {
    _usuarioOrCedulaCtrl.dispose();
    _answer1Ctrl.dispose();
    _answer2Ctrl.dispose();
    _newPassCtrl.dispose();
    _confirmPassCtrl.dispose();
    super.dispose();
  }

  /// 1) Intentar leer directamente por ID (asumimos que el usuario escribió el username),
  /// 2) Si no existe, hacemos un query por campo "cedula"
  Future<void> _checkUserAndLoadQuestions() async {
    final input = _usuarioOrCedulaCtrl.text.trim();
    if (input.isEmpty) {
      setState(() {
        _errorMessage = 'Ingresa tu usuario o cédula';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _userExists = false;
      _questionsLoaded = false;
    });

    try {
      final challenge = await SecureAuthService().prepareRecovery(input);
      setState(() {
        _recoveryChallengeId = challenge.id;
        _storedPregunta1 = challenge.question1;
        _storedPregunta2 = challenge.question2;
        _userExists = true;
        _questionsLoaded = true;
        _errorMessage = null;
      });
    } on SecureAuthException catch (e) {
      setState(() {
        _errorMessage = e.message;
      });
    } catch (_) {
      setState(
        () => _errorMessage = 'Error al buscar usuario. Intenta de nuevo.',
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _submitReset() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_userExists || !_questionsLoaded) {
      setState(() => _errorMessage = 'Primero verifica tu usuario.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final nuevaClave = _newPassCtrl.text.trim();

    try {
      await SecureAuthService().completeRecovery(
        challengeId: _recoveryChallengeId!,
        answer1: _answer1Ctrl.text.trim(),
        answer2: _answer2Ctrl.text.trim(),
        newPassword: nuevaClave,
      );

      if (!mounted) return;
      setState(() => _isLoading = false);

      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('¡Contraseña restablecida!'),
          content: const Text(
            'Tu contraseña ha sido actualizada correctamente.\n'
            'Ahora puedes iniciar sesión con la nueva contraseña.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context); // Cierra el diálogo
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } on SecureAuthException catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.message;
      });
    } catch (_) {
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
        title: const Text('Recuperar Contraseña'),
        backgroundColor: kMarronOscuro,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            children: [
              const Text(
                'Ingresa tu usuario o cédula para restablecer tu contraseña.',
                style: TextStyle(fontFamily: kArial, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              // 1) Campo para usuario / cédula
              TextFormField(
                controller: _usuarioOrCedulaCtrl,
                decoration: const InputDecoration(
                  labelText: 'Usuario o Cédula',
                  border: OutlineInputBorder(),
                ),
                style: const TextStyle(fontFamily: kArial),
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kMarronOscuro,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    textStyle: const TextStyle(
                      fontFamily: kArial,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onPressed: _isLoading ? null : _checkUserAndLoadQuestions,
                  child: _isLoading
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Verificar usuario'),
                ),
              ),
              const SizedBox(height: 16),

              // 2) Si el usuario existe y las preguntas se cargaron, mostramos
              // el formulario completo de respuestas + nueva contraseña
              if (_userExists && _questionsLoaded) ...[
                const Divider(thickness: 1, color: Colors.grey),
                const SizedBox(height: 16),

                Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Pregunta de seguridad 1 (solo se muestra como texto)
                      const Text(
                        'Pregunta 1:',
                        style: TextStyle(
                          fontFamily: kArial,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _storedPregunta1 ?? '',
                        style: const TextStyle(fontFamily: kArial),
                      ),
                      const SizedBox(height: 8),
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
                      const SizedBox(height: 16),

                      // Pregunta de seguridad 2
                      const Text(
                        'Pregunta 2:',
                        style: TextStyle(
                          fontFamily: kArial,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _storedPregunta2 ?? '',
                        style: const TextStyle(fontFamily: kArial),
                      ),
                      const SizedBox(height: 8),
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
                          if (v.trim().length < 8) {
                            return 'Mínimo 8 caracteres';
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
                          style: const TextStyle(
                            color: Colors.red,
                            fontFamily: kArial,
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Botón “Restablecer contraseña”
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
                          onPressed: _isLoading ? null : _submitReset,
                          child: _isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Restablecer contraseña'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              if (_errorMessage != null && !_userExists) ...[
                const SizedBox(height: 16),
                Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.red, fontFamily: kArial),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
