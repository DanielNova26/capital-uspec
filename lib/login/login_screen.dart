// lib/login/login_screen.dart

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:todo/theme/app_typography.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:todo/state/empresa_scope.dart';
import 'package:url_launcher/url_launcher.dart';

import '../home/widgets/home_shared_widgets.dart';
import '../services/auth_prefs.dart';
import '../services/secure_auth_service.dart';
import '../services/session_audit_service.dart';
import '../utils/user_company.dart';

// Están en el mismo folder "login"
import 'change_password_screen.dart' hide kArial;
import 'forgot_password_screen.dart' hide kArial;

// Está en lib/home (en minúscula)
import '../home/home_screen.dart';

// Solo mantenemos la fuente como constante

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();

  // Controlador del usuario para poder precargar el último usuario recordado.
  final TextEditingController _userCtrl = TextEditingController();

  // Capturamos directamente los valores con onChanged
  String usuarioInput = '';
  String passwordInput = '';
  bool _isLoading = false;
  String? _errorMessage;

  // Conveniencias de inicio de sesión
  bool _rememberUser = false;
  bool _keepSession = false;
  bool _biometricAvailable = false;

  @override
  void initState() {
    super.initState();
    _loadLoginPrefs();
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadLoginPrefs() async {
    final prefs = AuthPrefs.instance;
    final savedUser = await prefs.getSavedUsername();
    final keep = await prefs.getKeepSession();
    final biometric = await prefs.canOfferBiometrics();
    if (!mounted) return;
    setState(() {
      if (savedUser != null) {
        _rememberUser = true;
        usuarioInput = savedUser;
        _userCtrl.text = savedUser;
      }
      _keepSession = keep;
      _biometricAvailable = biometric;
    });
  }

  Future<void> _openWhatsAppSupport() async {
    final identity = _userCtrl.text.trim();
    final message = identity.isEmpty
        ? 'Hola, necesito soporte para iniciar sesión en To-Do y solicitar una contraseña temporal. Aún no he indicado mi usuario o cédula.'
        : 'Hola, necesito soporte para iniciar sesión en To-Do y solicitar una contraseña temporal. Mi usuario o cédula es: $identity.';
    final uri = Uri.https('wa.me', '/573134350281', {'text': message});
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No fue posible abrir WhatsApp. Comunícate al 313 435 0281.',
          ),
        ),
      );
    }
  }

  Future<Map<String, String>> _loadEmpresaNames(Set<String> ids) async {
    if (ids.isEmpty) return {};
    final empresasCol = FirebaseFirestore.instance.collection('TBL_EMPRESAS');
    final nombres = <String, String>{};

    await Future.wait(
      ids.map((id) async {
        final emp = await empresasCol.doc(id).get();
        if (emp.exists) {
          final nombre = (emp.data()?['nombre'] as String?)?.trim();
          if (nombre != null && nombre.isNotEmpty) nombres[id] = nombre;
        }
      }),
    );

    return nombres;
  }

  Future<String?> _selectEmpresaId(
    List<String> empresaIds, {
    String? preselectedId,
  }) async {
    final uniqueIds = empresaIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
    if (uniqueIds.isEmpty) return '';
    final ids = uniqueIds.toList()..sort();
    if (ids.length == 1) return ids.first;

    final nombres = await _loadEmpresaNames(uniqueIds);

    return showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        String selected = preselectedId != null && ids.contains(preselectedId)
            ? preselectedId
            : ids.first;

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
                      final title = nombre != null && nombre.isNotEmpty
                          ? nombre
                          : '';
                      final isSelected = selected == id;
                      return Material(
                        color: isSelected
                            ? scheme.primaryContainer
                            : scheme.surface,
                        elevation: isSelected ? 2 : 1,
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
                                Radio<String>(
                                  value: id,
                                  groupValue: selected,
                                  activeColor: scheme.primary,
                                  onChanged: (value) =>
                                      Navigator.of(context).pop(value),
                                ),
                                CompanyLogoAvatar(
                                  empresaId: id,
                                  radius: 20,
                                  backgroundColor: scheme.primaryContainer,
                                  foregroundColor: scheme.onPrimaryContainer,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        title.isEmpty
                                            ? 'Empresa sin nombre'
                                            : title,
                                        style: theme.textTheme.bodyLarge
                                            ?.copyWith(
                                              fontFamily: kArial,
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.chevron_right,
                                  color: scheme.onSurfaceVariant,
                                ),
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

  // ✅ helpers para leer variantes de campos desde empresasDetalle
  String _pickStr(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  /// ✅ AJUSTE CLAVE:
  /// Al seleccionar empresa, además de guardar empresaId/empresaNombre,
  /// copiamos a nivel raíz areaId/cargoId/centroId/jefeId... desde empresasDetalle[empresaId]
  Future<void> _persistSelectedEmpresa(String userId, String empresaId) async {
    try {
      final db = FirebaseFirestore.instance;

      // 1) nombre oficial desde TBL_EMPRESAS (si existe)
      String? empresaNombre;
      try {
        final empDoc = await db.collection('TBL_EMPRESAS').doc(empresaId).get();
        final data = empDoc.data();
        final n = (data?['nombre'] as String?)?.trim();
        if (n != null && n.isNotEmpty) empresaNombre = n;
      } catch (_) {}

      // 2) leer usuario para extraer empresasDetalle
      final userRef = db.collection('TBL_USUARIOS').doc(userId);
      final userSnap = await userRef.get();
      final userData = userSnap.data() ?? {};

      final empresasDetalle = userData['empresasDetalle'];
      Map<String, dynamic>? det;
      if (empresasDetalle is Map<String, dynamic>) {
        final raw = empresasDetalle[empresaId];
        if (raw is Map<String, dynamic>) det = raw;
      }

      final update = <String, dynamic>{
        'empresaId': empresaId,
        if (empresaNombre != null && empresaNombre.isNotEmpty)
          'empresaNombre': empresaNombre,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // 3) si existe detalle para esa empresa, “sincronizamos” top-level (lo que usa CreateTask)
      if (det != null) {
        final areaId = _pickStr(det, const [
          'areaId',
          'area_id',
          'departamentoId',
          'departamento_id',
        ]);
        final area = _pickStr(det, const [
          'area',
          'areaNombre',
          'area_nombre',
          'departamento',
        ]);
        final cargoId = _pickStr(det, const ['cargoId', 'cargo_id']);
        final cargo = _pickStr(det, const ['cargo']);
        final centroId = _pickStr(det, const [
          'centroId',
          'centro_id',
          'centro',
        ]);
        final centroCostos = _pickStr(det, const [
          'centroCostos',
          'centro_costos',
          'centro_costos_nombre',
        ]);
        final jefeId = _pickStr(det, const ['jefeId', 'jefe_id', 'jefe_uid']);
        final jefeNombre = _pickStr(det, const ['jefeNombre', 'jefe_nombre']);
        final cargoJefe = _pickStr(det, const ['cargoJefe']);

        if (areaId.isNotEmpty) update['areaId'] = areaId;
        if (area.isNotEmpty) update['area'] = area;

        if (cargoId.isNotEmpty) update['cargoId'] = cargoId;
        if (cargo.isNotEmpty) update['cargo'] = cargo;

        if (centroId.isNotEmpty) update['centroId'] = centroId;
        if (centroCostos.isNotEmpty) update['centroCostos'] = centroCostos;

        if (jefeId.isNotEmpty) update['jefeId'] = jefeId;
        if (jefeNombre.isNotEmpty) update['jefeNombre'] = jefeNombre;
        if (cargoJefe.isNotEmpty) update['cargoJefe'] = cargoJefe;
      }

      await userRef.set(update, SetOptions(merge: true));
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
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: media.size.width > 500
                  ? media.size.width * 0.2
                  : 36.0,
              vertical: 16,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  height: 90,
                  margin: const EdgeInsets.only(bottom: 16),
                  child: Image.asset('assets/logo.png', fit: BoxFit.contain),
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
                      TextFormField(
                        controller: _userCtrl,
                        style: const TextStyle(
                          fontFamily: kArial,
                          fontSize: 14,
                        ),
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
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Ingrese su usuario'
                            : null,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 20),

                      TextFormField(
                        style: const TextStyle(
                          fontFamily: kArial,
                          fontSize: 14,
                        ),
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
                      const SizedBox(height: 6),

                      // ── Conveniencias de inicio de sesión ──
                      CheckboxListTile(
                        value: _rememberUser,
                        onChanged: (v) =>
                            setState(() => _rememberUser = v ?? false),
                        title: const Text(
                          'Recordar usuario',
                          style: TextStyle(fontFamily: kArial, fontSize: 13),
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                      CheckboxListTile(
                        value: _keepSession,
                        onChanged: (v) =>
                            setState(() => _keepSession = v ?? false),
                        title: const Text(
                          'Mantener sesión iniciada',
                          style: TextStyle(fontFamily: kArial, fontSize: 13),
                        ),
                        subtitle: Text(
                          _biometricAvailable
                              ? 'Te ofreceremos ingresar con huella / Face ID'
                              : 'Entrarás directo la próxima vez en este dispositivo',
                          style: const TextStyle(
                            fontFamily: kArial,
                            fontSize: 11,
                          ),
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                      const SizedBox(height: 12),

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
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      scheme.onPrimary,
                                    ),
                                  ),
                                )
                              : const Text('Iniciar sesión'),
                        ),
                      ),
                      const SizedBox(height: 8),

                      if (_errorMessage != null) ...[
                        Text(
                          _errorMessage!,
                          style: TextStyle(
                            color: scheme.error,
                            fontFamily: kArial,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                      ],

                      Text(
                        'El acceso se habilita desde Administración.',
                        style: TextStyle(
                          fontFamily: kArial,
                          color: scheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),

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
                      const SizedBox(height: 16),

                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFECFDF3),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFF86EFAC)),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 20,
                                  backgroundColor: Color(0xFF25D366),
                                  child: SvgPicture.asset(
                                    'assets/icons/whatsapp_support.svg',
                                    width: 25,
                                    height: 25,
                                  ),
                                ),
                                const SizedBox(width: 11),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '¿Problemas para iniciar sesión?',
                                        style: TextStyle(
                                          fontFamily: kArial,
                                          color: Color(0xFF14532D),
                                          fontWeight: FontWeight.w800,
                                          fontSize: 13,
                                        ),
                                      ),
                                      SizedBox(height: 2),
                                      Text(
                                        'Solicita soporte o una contraseña temporal.',
                                        style: TextStyle(
                                          fontFamily: kArial,
                                          color: Color(0xFF166534),
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 11),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _openWhatsAppSupport,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF166534),
                                  side: const BorderSide(
                                    color: Color(0xFF22C55E),
                                  ),
                                  backgroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 11,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(9),
                                  ),
                                ),
                                icon: const Icon(Icons.open_in_new, size: 17),
                                label: const Text(
                                  'Solicitar soporte por WhatsApp',
                                  style: TextStyle(
                                    fontFamily: kArial,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Por seguridad, nunca envíes tu contraseña por chat.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: kArial,
                                color: Color(0xFF166534),
                                fontSize: 10,
                              ),
                            ),
                          ],
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

  /// Guarda las preferencias de inicio de sesión tras un login exitoso:
  /// recordar usuario, mantener sesión y (móvil) ofrecer biometría.
  /// NUNCA guarda la contraseña: solo la identidad (docId + empresaId).
  Future<void> _persistLoginConveniences({
    required String input,
    required String docId,
    required String empresaId,
  }) async {
    final prefs = AuthPrefs.instance;

    // 1) Recordar usuario (lo que escribió: usuario o cédula).
    await prefs.setRememberUser(_rememberUser, username: input);

    // 2) Mantener sesión iniciada.
    await prefs.setKeepSession(_keepSession);

    bool persistSession = _keepSession || await prefs.isBiometricEnabled();

    // 3) Ofrecer biometría (solo móvil, si el usuario quiere mantener sesión,
    //    hay hardware enrolado y aún no está activada).
    if (!kIsWeb &&
        _keepSession &&
        _biometricAvailable &&
        !await prefs.isBiometricEnabled()) {
      if (mounted) {
        final enable = await _askEnableBiometric();
        if (enable == true) {
          await prefs.setBiometricEnabled(true);
          persistSession = true;
        }
      }
    }

    if (persistSession) {
      await prefs.saveSession(docId: docId, empresaId: empresaId);
    } else {
      // El usuario no quiere auto-ingreso: limpiamos cualquier sesión previa.
      await prefs.clearSession();
    }
  }

  Future<bool?> _askEnableBiometric() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Ingreso con huella / Face ID',
          style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'La próxima vez podrás ingresar con tu huella o Face ID, sin escribir '
          'tu contraseña. Tu contraseña no se guarda en el dispositivo.',
          style: TextStyle(fontFamily: kArial),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Ahora no', style: TextStyle(fontFamily: kArial)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Activar', style: TextStyle(fontFamily: kArial)),
          ),
        ],
      ),
    );
  }

  Future<void> _submitLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final input = usuarioInput.trim();
    final pass = passwordInput;

    try {
      final secureLogin = await SecureAuthService().signIn(
        usuario: input,
        password: pass,
      );
      String? selectedEmpresaId;
      final docSnapshot = await FirebaseFirestore.instance
          .collection('TBL_USUARIOS')
          .doc(secureLogin.userDocId)
          .get();
      final data = docSnapshot.data();
      if (data == null) {
        setState(() {
          _errorMessage = 'Error al leer los datos del usuario';
          _isLoading = false;
        });
        return;
      }

      final needsChange = secureLogin.needsPasswordChange;
      final docId = docSnapshot.id;

      final uniqueEmpresas = extractUserEmpresaIds(data);
      if (uniqueEmpresas.isEmpty) {
        setState(() {
          _errorMessage = 'No se encontró empresa asociada al usuario';
          _isLoading = false;
        });
        return;
      }

      final storedEmpresaId = (data['empresaId'] as String?)?.trim();
      if (uniqueEmpresas.length == 1) {
        selectedEmpresaId = uniqueEmpresas.first;
      } else {
        selectedEmpresaId = await _selectEmpresaId(
          uniqueEmpresas,
          preselectedId: storedEmpresaId,
        );
      }

      if (selectedEmpresaId == null || selectedEmpresaId.isEmpty) {
        setState(() {
          _errorMessage = 'Selecciona la empresa para continuar';
          _isLoading = false;
        });
        return;
      }

      // ✅ EmpresaScope + persistencia validada contra membresía real
      final empresaState = EmpresaScope.of(context, listen: false);
      final resolvedEmpresaId = await empresaState.reconcileForUserData(
        data,
        preferredEmpresaId: selectedEmpresaId,
        // La empresa que se acaba de elegir manda sobre la que quedó guardada
        // de la sesión anterior.
        eleccionExplicita: true,
      );
      if (resolvedEmpresaId == null || resolvedEmpresaId.isEmpty) {
        setState(() {
          _errorMessage = 'No se encontró una empresa válida para el usuario';
          _isLoading = false;
        });
        return;
      }
      await _persistSelectedEmpresa(docId, resolvedEmpresaId);

      final cedula = (data['cedula'] as String?)?.trim() ?? '';
      debugPrint(
        '[Login] sesión segura — docId=$docId uid=${secureLogin.uid} cedula=$cedula '
        'empresa=$resolvedEmpresaId role=${data['role']}',
      );
      unawaited(
        SessionAuditService()
            .recordLogin(
              userId: docId,
              empresaId: resolvedEmpresaId,
              userData: data,
              source: 'password',
            )
            .catchError((e) => debugPrint('[Login] audit error: $e')),
      );
      // ── Fin Tarea 2 ────────────────────────────────────────────────────────

      // ── Conveniencias de inicio de sesión (recordar / mantener / biometría) ─
      if (mounted) setState(() => _isLoading = false);
      await _persistLoginConveniences(
        input: input,
        docId: docId,
        empresaId: resolvedEmpresaId,
      );

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => needsChange
              ? ChangePasswordScreen(
                  usuario: docId,
                  empresaId: resolvedEmpresaId,
                )
              : HomeScreen(username: docId, empresaId: resolvedEmpresaId),
        ),
      );
    } on SecureAuthException catch (e) {
      debugPrint('[Login] secure auth error (${e.code}): ${e.message}');
      if (!mounted) return;
      setState(() {
        _errorMessage = switch (e.code) {
          'network-request-failed' =>
            'No pudimos conectar con el servicio de acceso. Revisa tu conexión.',
          'resource-exhausted' || 'too-many-requests' =>
            'Se realizaron demasiados intentos. Espera un momento e intenta de nuevo.',
          'permission-denied' => 'Usuario o contraseña incorrectos.',
          'internal' =>
            'El servicio de acceso tuvo un inconveniente temporal. Intenta nuevamente.',
          _ => e.message,
        };
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('[Login] error: $e');
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Error al iniciar sesión. Intenta de nuevo.';
        _isLoading = false;
      });
    }
  }
}
