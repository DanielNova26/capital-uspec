// lib/login/login_screen.dart

import 'package:flutter/material.dart';
import 'package:todo/theme/app_typography.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:todo/state/empresa_scope.dart';

// Están en el mismo folder "login"
import 'first_time_screen.dart';
import 'change_password_screen.dart' hide kArial;
import 'forgot_password_screen.dart' hide kArial;

// Está en lib/home (en minúscula)
import '../home/home_screen.dart';

// Admin oculto por triple-tap
import '../admin/seed_admin_screen.dart';
import '../widgets/hidden_admin_unlocker.dart';

// Solo mantenemos la fuente como constante

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
                                        ? empresaId
                                        .substring(0, empresaId.length >= 2 ? 2 : 1)
                                        .toUpperCase()
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

  Future<String?> _selectEmpresaId(
      List<String> empresaIds, {
        String? preselectedId,
      }) async {
    final uniqueIds =
    empresaIds.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
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
                      final title = nombre != null && nombre.isNotEmpty ? nombre : id;
                      final isSelected = selected == id;
                      return Material(
                        color: isSelected ? scheme.primaryContainer : scheme.surface,
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
                                  onChanged: (value) => Navigator.of(context).pop(value),
                                ),
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
        final areaId = _pickStr(det, const ['areaId', 'area_id', 'departamentoId', 'departamento_id']);
        final area = _pickStr(det, const ['area', 'areaNombre', 'area_nombre', 'departamento']);
        final cargoId = _pickStr(det, const ['cargoId', 'cargo_id']);
        final cargo = _pickStr(det, const ['cargo']);
        final centroId = _pickStr(det, const ['centroId', 'centro_id', 'centro']);
        final centroCostos = _pickStr(det, const ['centroCostos', 'centro_costos', 'centro_costos_nombre']);
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
              horizontal: media.size.width > 500 ? media.size.width * 0.2 : 36.0,
              vertical: 16,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
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

                      if (_errorMessage != null) ...[
                        Text(
                          _errorMessage!,
                          style: TextStyle(color: scheme.error, fontFamily: kArial),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                      ],

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

  Future<void> _submitLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final input = usuarioInput;
    final pass = passwordInput;

    try {
      final collectionRef = FirebaseFirestore.instance.collection('TBL_USUARIOS');
      String? selectedEmpresaId;

      final byId = await collectionRef.doc(input).get();
      final List<DocumentSnapshot<Map<String, dynamic>>> candidatos = [];
      if (byId.exists) {
        candidatos.add(byId);
      } else {
        final querySnap = await collectionRef.where('cedula', isEqualTo: input).get();
        if (querySnap.docs.isEmpty) {
          setState(() {
            _errorMessage = 'Usuario o cédula no registrado';
            _isLoading = false;
          });
          return;
        }
        candidatos.addAll(querySnap.docs);
      }

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

      final data = docSnapshot.data();
      if (data == null) {
        setState(() {
          _errorMessage = 'Error al leer los datos del usuario';
          _isLoading = false;
        });
        return;
      }

      final needsChange = data['needsPasswordChange'] as bool? ?? false;
      final docId = docSnapshot.id;

      // Empresas asociadas
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

      final empresasDetalle = data['empresasDetalle'] as Map<String, dynamic>?;
      if (empresasDetalle != null) {
        for (final entry in empresasDetalle.entries) {
          final id = entry.key.toString().trim();
          if (id.isNotEmpty) empresaIds.add(id);
        }
      }

      final uniqueEmpresas = empresaIds.toSet().toList();
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

      // ✅ EmpresaScope + persistencia (incluye sincronización top-level desde empresasDetalle)
      final empresaState = EmpresaScope.of(context, listen: false);
      empresaState.setSelectedEmpresaId(selectedEmpresaId);
      await _persistSelectedEmpresa(docId, selectedEmpresaId);

      if (needsChange) {
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
        setState(() => _isLoading = false);
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => HomeScreen(
              username: docId,
              empresaId: selectedEmpresaId!,
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
