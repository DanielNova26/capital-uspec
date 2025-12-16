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
  bool _isLoading = false;
  String? _errorMessage;

  Future<Map<String, String>> _loadEmpresaNames(Set<String> ids) async {
    if (ids.isEmpty) return {};
    final empresasCol = FirebaseFirestore.instance.collection('TBL_EMPRESAS');
    final nombres = <String, String>{};

    await Future.wait(ids.map((id) async {
      final emp = await empresasCol.doc(id).get();
      if (emp.exists) {
        final nombre = (emp.data()?['nombre'] as String?)?.trim();
        if (nombre != null && nombre.isNotEmpty) nombres[id] = nombre;
      }
    }));

    return nombres;
  }

  Future<DocumentSnapshot<Map<String, dynamic>>?> _selectEmpresa(
      List<DocumentSnapshot<Map<String, dynamic>>> docs,
      ) async {
    if (docs.length == 1) return docs.first;

    final nombres = await _loadEmpresaNames(docs
        .map((d) => (d.data()?['empresaId'] as String?)?.trim() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet());

    return showModalBottomSheet<DocumentSnapshot<Map<String, dynamic>>>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: scheme.outlineVariant,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                Text(
                  'Selecciona tu empresa',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontFamily: kArial,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, index) {
                      final doc = docs[index];
                      final empresaId =
                          (doc.data()?['empresaId'] as String?)?.trim() ?? '';
                      final nombre = nombres[empresaId];
                      final title =
                      nombre != null && nombre.isNotEmpty ? nombre : empresaId;

                      return Material(
                        color: scheme.surface,
                        elevation: 1,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => Navigator.of(context).pop(doc),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 20,
                                  backgroundColor: scheme.primaryContainer,
                                  child: Text(
                                    empresaId.isNotEmpty
                                        ? empresaId.substring(0, empresaId.length >= 2 ? 2 : 1).toUpperCase()
                                        : '—',
                                    style: TextStyle(
                                      color: scheme.onPrimaryContainer,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        title.isEmpty ? 'Empresa sin nombre' : title,
                                        style: theme.textTheme.bodyLarge?.copyWith(
                                          fontFamily: kArial,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      if (empresaId.isNotEmpty)
                                        Text(
                                          empresaId,
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            fontFamily: kArial,
                                            color: scheme.onSurfaceVariant,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<String?> _selectEmpresaId(List<String> empresaIds) async {
    final uniqueIds = empresaIds.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    if (uniqueIds.isEmpty) return '';
    if (uniqueIds.length == 1) return uniqueIds.first;

    final nombres = await _loadEmpresaNames(uniqueIds);

    return showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        final ids = uniqueIds.toList()..sort();

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: scheme.outlineVariant,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                Text(
                  'Selecciona tu empresa',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontFamily: kArial,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: ids.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, index) {
                      final id = ids[index];
                      final nombre = nombres[id];
                      final title = nombre != null && nombre.isNotEmpty ? nombre : id;
                      return Material(
                        color: scheme.surface,
                        elevation: 1,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => Navigator.of(context).pop(id),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 20,
                                  backgroundColor: scheme.primaryContainer,
                                  child: Text(
                                    id.substring(0, id.length >= 2 ? 2 : 1).toUpperCase(),
                                    style: TextStyle(
                                      color: scheme.onPrimaryContainer,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        title.isEmpty ? 'Empresa sin nombre' : title,
                                        style: theme.textTheme.bodyLarge?.copyWith(
                                          fontFamily: kArial,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      Text(
                                        id,
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          fontFamily: kArial,
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _persistSelectedEmpresa(String userId, String empresaId) async {
    try {
      final empresasCol = FirebaseFirestore.instance.collection('TBL_EMPRESAS');
      final empresaDoc = await empresasCol.doc(empresaId).get();
      final data = empresaDoc.data();
      final nombre = (data?['nombre'] as String?)?.trim();

      await FirebaseFirestore.instance.collection('TBL_USUARIOS').doc(userId).set(
        {
          'empresaId': empresaId,
          if (nombre != null && nombre.isNotEmpty) 'empresaNombre': nombre,
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('No se pudo actualizar la empresa seleccionada: $e');
    }
  }

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

    try {
      final collectionRef =
      FirebaseFirestore.instance.collection('TBL_USUARIOS');
      String? selectedEmpresaId;

      // 1) Intentamos leer por ID (username) y, si no, por cédula
      final byId = await collectionRef.doc(input).get();
      final List<DocumentSnapshot<Map<String, dynamic>>> candidatos = [];
      if (byId.exists) {
        candidatos.add(byId);
      } else {
        final querySnap =
        await collectionRef.where('cedula', isEqualTo: input).get();
        if (querySnap.docs.isEmpty) {
          setState(() {
            _errorMessage = 'Usuario o cédula no registrado';
            _isLoading = false;
          });
          return;
        }
        candidatos.addAll(querySnap.docs);
      }

      // 2) Validamos contraseña antes de mostrar empresas
      final conPassword = candidatos.where((doc) {
        final storedPass = (doc.data()?['password'] as String? ?? '').trim();
        return storedPass == pass;
      }).toList();

      if (conPassword.isEmpty) {
        setState(() {
          _errorMessage = 'Contraseña incorrecta';
          _isLoading = false;
        });
        return;
      }

      DocumentSnapshot<Map<String, dynamic>>? docSnapshot;
      if (conPassword.length == 1) {
        docSnapshot = conPassword.first;
      } else {
        docSnapshot = await _selectEmpresa(conPassword);
        if (docSnapshot == null) {
          setState(() {
            _errorMessage = 'Selecciona la empresa para continuar';
            _isLoading = false;
          });
          return;
        }
      }

      // Si llegamos aquí, docSnapshot existe
      final data = docSnapshot.data();
      if (data == null) {
        setState(() {
          _errorMessage = 'Error al leer los datos del usuario';
          _isLoading = false;
        });
        return;
      }
      final needsChange = data['needsPasswordChange'] as bool? ?? false;
      final docId = docSnapshot!.id; // Esto es el "username" usado

      // Determinar la empresa: permite que un usuario tenga varias empresas
      final empresaIds = <String>[];
      final empresaCampo = (data['empresaId'] as String?)?.trim();
      if (empresaCampo != null && empresaCampo.isNotEmpty) {
        empresaIds.add(empresaCampo);
      }

      final empresasLista = data['empresas'] as List<dynamic>?;
      if (empresasLista != null) {
        for (final e in empresasLista) {
          final id = (e as String?)?.trim();
          if (id != null && id.isNotEmpty) empresaIds.add(id);
        }
      }

      if (empresaIds.isEmpty) {
        setState(() {
          _errorMessage = 'No se encontró empresa asociada al usuario';
          _isLoading = false;
        });
        return;
      }

      selectedEmpresaId ??= (data['empresaId'] as String?)?.trim();

      if (selectedEmpresaId == null || selectedEmpresaId.isEmpty) {
        selectedEmpresaId = await _selectEmpresaId(empresaIds);
      }
      if (selectedEmpresaId == null) {
        setState(() {
          _errorMessage = 'Selecciona la empresa para continuar';
          _isLoading = false;
        });
        return;
      }

      // Persistimos la empresa elegida para que las pantallas usen el filtro correcto
      await _persistSelectedEmpresa(docId, selectedEmpresaId!);
      
      // 4) Según 'needsPasswordChange', redirigimos
      if (needsChange) {
        // Debe cambiarla primero
        setState(() => _isLoading = false);
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ChangePasswordScreen(
              usuario: docId,
              empresaId: selectedEmpresaId!,
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
