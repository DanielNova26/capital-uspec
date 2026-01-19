// lib/login/change_password_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'login_screen.dart'; // Ajusta si tu LoginScreen está en otra carpeta
import 'package:todo/utils/user_company.dart';

const String kArial = 'Arial';

class ChangePasswordScreen extends StatefulWidget {
  final String usuario; // ID del doc (antes mostrabas esto)
  final String empresaId;
  const ChangePasswordScreen({Key? key, required this.usuario, required this.empresaId})
      : super(key: key);

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();

  // Controladores nueva contraseña
  final _newPassCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();

  // Controladores respuestas
  final _answer1Ctrl = TextEditingController();
  final _answer2Ctrl = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;

  // Nombre del usuario (leído de Firestore -> campo "nombres")
  String? _nombre;

  // 10 preguntas
  final List<String> _preguntas = const [
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

  String? _selectedQuestion1;
  String? _selectedQuestion2;

  @override
  void initState() {
    super.initState();
    _cargarNombre();
  }

  Future<void> _cargarNombre() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('TBL_USUARIOS')
          .doc(widget.usuario)
          .get();

      final data = doc.data();
      if (doc.exists && data != null && userBelongsToEmpresa(data, widget.empresaId)) {
        setState(() {
          _nombre = (data['nombres'] as String?)?.trim();
        });
      }  else {
        setState(() {
          _errorMessage = 'El usuario no pertenece a esta empresa.';
        });
      }
    } catch (_) {
      // Si falla, dejamos la cédula como fallback
    }
  }

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
      final docRef = FirebaseFirestore.instance
          .collection('TBL_USUARIOS')
          .doc(widget.usuario);

      final doc = await docRef.get();
      final data = doc.data();
      if (!doc.exists || data == null || !userBelongsToEmpresa(data, widget.empresaId)) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'No se pudo validar la empresa del usuario.';
        });
        return;
      }

      await docRef.update({
        'password': _newPassCtrl.text.trim(),
        'pregunta_seguridad_1': _selectedQuestion1,
        'respuesta_seguridad_1': _answer1Ctrl.text.trim(),
        'pregunta_seguridad_2': _selectedQuestion2,
        'respuesta_seguridad_2': _answer2Ctrl.text.trim(),
        'needsPasswordChange': false,
      });

      setState(() => _isLoading = false);

      await showDialog(
        context: context,
        builder: (_) => const AlertDialog(
          title: Text('¡Contraseña y seguridad actualizadas!'),
          content: Text(
            'Tu contraseña y preguntas de seguridad han sido guardadas correctamente.\n'
                'Ahora podrás iniciar sesión con tu nueva contraseña.',
          ),
        ),
      );

      // ignore: use_build_context_synchronously
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

  // ────────────────────────── UI ──────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cambiar Contraseña'),
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            children: [
              // Saludo con el nombre (o cédula como fallback mientras carga)
              Text(
                'Hola, ${_nombre?.isNotEmpty == true ? _nombre : widget.usuario}',
                style: TextStyle(
                  fontFamily: kArial,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: scheme.primary,
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
                    // Pregunta 1
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      menuMaxHeight: 360,
                      decoration: const InputDecoration(
                        labelText: 'Pregunta de seguridad 1',
                        border: OutlineInputBorder(),
                        contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                      ),
                      iconEnabledColor: scheme.primary,
                      dropdownColor: theme.brightness == Brightness.dark
                          ? scheme.surface
                          : Colors.white,
                      value: _selectedQuestion1,
                      items: _preguntas
                          .map((p) => DropdownMenuItem(
                        value: p,
                        child: Text(
                          p,
                          maxLines: 3,
                          overflow: TextOverflow.visible,
                          style: const TextStyle(
                              fontFamily: kArial, color: Colors.black),
                        ),
                      ))
                          .toList(),
                      // Esto controla cómo se muestra el texto SELECCIONADO en el campo
                      selectedItemBuilder: (_) => _preguntas
                          .map((p) => Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          p,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontFamily: kArial),
                        ),
                      ))
                          .toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedQuestion1 = value;
                          if (_selectedQuestion2 == value) _selectedQuestion2 = null;
                        });
                      },
                      validator: (v) =>
                      (v == null || v.isEmpty) ? 'Selecciona la pregunta 1' : null,
                    ),
                    const SizedBox(height: 12),

                    // Respuesta 1
                    TextFormField(
                      controller: _answer1Ctrl,
                      decoration: const InputDecoration(
                        labelText: 'Respuesta 1',
                        border: OutlineInputBorder(),
                      ),
                      style: const TextStyle(fontFamily: kArial),
                      validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Ingresa la respuesta 1' : null,
                    ),
                    const SizedBox(height: 24),

                    // Pregunta 2
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      menuMaxHeight: 360,
                      decoration: const InputDecoration(
                        labelText: 'Pregunta de seguridad 2',
                        border: OutlineInputBorder(),
                        contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                      ),
                      iconEnabledColor: scheme.primary,
                      dropdownColor: theme.brightness == Brightness.dark
                          ? scheme.surface
                          : Colors.white,
                      value: _selectedQuestion2,
                      items: _preguntas
                          .map((p) => DropdownMenuItem(
                        value: p,
                        child: Text(
                          p,
                          maxLines: 3,
                          overflow: TextOverflow.visible,
                          style: const TextStyle(
                              fontFamily: kArial, color: Colors.black),
                        ),
                      ))
                          .toList(),
                      selectedItemBuilder: (_) => _preguntas
                          .map((p) => Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          p,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontFamily: kArial),
                        ),
                      ))
                          .toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedQuestion2 = value;
                          if (_selectedQuestion1 == value) _selectedQuestion1 = null;
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

                    // Respuesta 2
                    TextFormField(
                      controller: _answer2Ctrl,
                      decoration: const InputDecoration(
                        labelText: 'Respuesta 2',
                        border: OutlineInputBorder(),
                      ),
                      style: const TextStyle(fontFamily: kArial),
                      validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Ingresa la respuesta 2' : null,
                    ),
                    const SizedBox(height: 24),

                    Divider(thickness: 1, color: theme.dividerColor),
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
                        style: TextStyle(color: scheme.error, fontFamily: kArial),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Botón
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: scheme.primary,
                          foregroundColor: scheme.onPrimary,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          textStyle: const TextStyle(
                            fontFamily: kArial,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onPressed: _isLoading ? null : _submitChange,
                        child: _isLoading
                            ? SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              scheme.onPrimary,
                            ),
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
