// lib/login/login_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Están en el mismo folder "login"
import 'first_time_screen.dart';
import 'change_password_screen.dart';
import 'forgot_password_screen.dart';

// Está en lib/home (en minúscula)
import '../home/home_screen.dart';

// Admin oculto por triple-tap
import '../admin/seed_admin_screen.dart';
import '../widgets/hidden_admin_unlocker.dart';

// Solo mantenemos la fuente como constante
const String kArial = 'Arial';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();

  // Capturamos directamente los valores con onChanged
  String usuarioInput = '';
  String passwordInput = '';
  String empresaInput = '';
  bool _isLoading = false;
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      // Deja que el tema ponga el fondo (scaffoldBackgroundColor)
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: media.size.width > 500 ? media.size.width * 0.2 : 36.0,
              vertical: 16,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo + 🔒 Desbloqueo oculto por triple-tap (PIN por Firestore o 2468)
                Container(
                  height: 90,
                  margin: const EdgeInsets.only(bottom: 16),
                  child: HiddenAdminUnlocker(
                    onUnlocked: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const SeedAdminScreen()),
                      );
                    },
                    child: Image.asset(
                      'assets/logo.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                Text(
                  'INICIAR SESIÓN',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontFamily: kArial,
                    color: scheme.primary,
                    fontSize: 18,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 8),
                Divider(height: 24, thickness: 1, color: theme.dividerColor),

                Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      // Usuario o Cédula
                      TextFormField(
                        style: const TextStyle(fontFamily: kArial, fontSize: 14),
                        decoration: InputDecoration(
                          labelText: 'Usuario o Cédula',
                          labelStyle: TextStyle(
                            color: scheme.primary.withOpacity(0.8),
                            fontFamily: kArial,
                          ),
                          border: const OutlineInputBorder(),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                        ),
                        onChanged: (value) => usuarioInput = value.trim(),
                        validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Ingrese su usuario' : null,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 20),

                      // Empresa ID
                      TextFormField(
                        style: const TextStyle(fontFamily: kArial, fontSize: 14),
                        decoration: InputDecoration(
                          labelText: 'Empresa ID',
                          labelStyle: TextStyle(
                            color: scheme.primary.withOpacity(0.8),
                            fontFamily: kArial,
                          ),
                          border: const OutlineInputBorder(),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                        ),
                        onChanged: (value) => empresaInput = value.trim(),
                        validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Ingrese el ID de la empresa' : null,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 20),

                      // Contraseña
                      TextFormField(
                        style: const TextStyle(fontFamily: kArial, fontSize: 14),
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: 'Contraseña',
                          labelStyle: TextStyle(
                            color: scheme.primary.withOpacity(0.8),
                            fontFamily: kArial,
                          ),
                          border: const OutlineInputBorder(),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                        ),
                        onChanged: (value) => passwordInput = value.trim(),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Ingrese su contraseña'
                            : null,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _submitLogin(),
                      ),
                      const SizedBox(height: 18),

                      // Botón Iniciar sesión
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: scheme.primary,
                            foregroundColor: scheme.onPrimary,
                            textStyle: const TextStyle(
                              fontFamily: kArial,
                              fontWeight: FontWeight.bold,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: _isLoading ? null : _submitLogin,
                          child: _isLoading
                              ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                              AlwaysStoppedAnimation<Color>(scheme.onPrimary),
                            ),
                          )
                              : const Text('Iniciar sesión'),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Mostrar mensaje de error si existe
                      if (_errorMessage != null) ...[
                        Text(
                          _errorMessage!,
                          style: TextStyle(color: scheme.error, fontFamily: kArial),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                      ],

                      // Enlace “Primera vez ingresa aquí”
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const FirstTimeScreen()),
                          );
                        },
                        child: Text(
                          'Primera vez ingresa aquí',
                          style: TextStyle(
                            fontFamily: kArial,
                            color: scheme.onSurfaceVariant,
                            fontSize: 13,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Enlace “¿Olvidaste tu contraseña?”
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ForgotPasswordScreen(),
                            ),
                          );
                        },
                        child: Text(
                          '¿Olvidaste tu contraseña?',
                          style: TextStyle(
                            fontFamily: kArial,
                            color: scheme.onSurfaceVariant,
                            fontSize: 13,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  'Derechos reservados',
                  style: TextStyle(
                    fontFamily: kArial,
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.7,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Lógica de login que valida contra Firestore:
  /// 1) Busca documento por ID = usuarioInput,
  /// 2) Si no existe, busca por campo cedula == usuarioInput,
  /// 3) Compara la contraseña ingresada contra el campo 'password',
  /// 4) Si needsPasswordChange == true, va a ChangePasswordScreen,
  ///    en caso contrario va a HomeScreen.
  Future<void> _submitLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final input = usuarioInput;
    final pass = passwordInput;
    final empresaId = empresaInput;

    try {
      final collectionRef =
      FirebaseFirestore.instance.collection('TBL_USUARIOS');
      DocumentSnapshot<Map<String, dynamic>>? docSnapshot;

      // 1) Intentamos leer por ID (username)
      final byId = await collectionRef.doc(input).get();
      final empresaDoc = (byId.data()?['empresaId'] as String?)?.trim() ?? '';
      if (byId.exists && empresaDoc == empresaId) {
        docSnapshot = byId;
      }
      if (docSnapshot == null) {
        // 2) Si no existe, buscamos por campo 'cedula' + empresaId
        final querySnap = await collectionRef
            .where('cedula', isEqualTo: input)
            .where('empresaId', isEqualTo: empresaId)
            .limit(1)
            .get();

        if (querySnap.docs.isEmpty) {
          setState(() {
            _errorMessage = 'Usuario o cédula no registrado para esta empresa';
            _isLoading = false;
          });
          return;
        } else {
          docSnapshot = querySnap.docs.first;
        }
      }

      // Si llegamos aquí, docSnapshot existe
      final data = docSnapshot!.data()!;
      final storedPass = data['password'] as String? ?? '';
      final needsChange = data['needsPasswordChange'] as bool? ?? false;
      final docId = docSnapshot!.id; // Esto es el "username" usado

      // 3) Comparamos contraseñas
      if (pass != storedPass) {
        setState(() {
          _errorMessage = 'Contraseña incorrecta';
          _isLoading = false;
        });
        return;
      }

      // 4) Según 'needsPasswordChange', redirigimos
      if (needsChange) {
        // Debe cambiarla primero
        setState(() => _isLoading = false);
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (_) => ChangePasswordScreen(
                usuario: docId,
                empresaId: empresaId,
              ),
          ),
        );
      } else {
        // Ya cambió antes, vamos a HomeScreen
        setState(() => _isLoading = false);
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => HomeScreen(
              username: docId, // ← Pasamos el username
            ),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error al iniciar sesión. Intenta de nuevo.';
        _isLoading = false;
      });
    }
  }
}
