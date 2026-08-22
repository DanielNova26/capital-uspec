// lib/login/first_time_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../home/widgets/home_shared_widgets.dart';
import '../services/anonymous_auth_service.dart';
import '../utils/user_company.dart';
import 'data_policy_screen.dart';

const String _kArial = 'Arial';

class FirstTimeScreen extends StatefulWidget {
  const FirstTimeScreen({super.key});

  @override
  State<FirstTimeScreen> createState() => _FirstTimeScreenState();
}

class _FirstTimeScreenState extends State<FirstTimeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _cedulaCtrl = TextEditingController();
  bool _isLoading = false;
  String? _error;

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  @override
  void dispose() {
    _cedulaCtrl.dispose();
    super.dispose();
  }

  Future<Map<String, String>> _loadEmpresaNames(Set<String> ids) async {
    if (ids.isEmpty) return {};
    final nombres = <String, String>{};
    final empresasCol = _db.collection('TBL_EMPRESAS');

    await Future.wait(
      ids.map((id) async {
        final emp = await empresasCol.doc(id).get();
        final nombre = (emp.data()?['nombre'] as String?)?.trim();
        if (nombre != null && nombre.isNotEmpty) nombres[id] = nombre;
      }),
    );

    return nombres;
  }

  Future<String?> _selectEmpresaId(
    List<String> empresaIds, {
    String? preselectedId,
  }) async {
    final ids =
        empresaIds
            .map((id) => id.trim())
            .where((id) => id.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    if (ids.isEmpty) return null;
    if (ids.length == 1) return ids.first;

    final nombres = await _loadEmpresaNames(ids.toSet());
    if (!mounted) return null;

    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) {
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Selecciona la empresa',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontFamily: _kArial,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Tu cedula esta asociada a mas de una empresa.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: _kArial,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 14),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: ids.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, index) {
                      final id = ids[index];
                      final nombre = nombres[id];
                      final title = nombre != null && nombre.isNotEmpty
                          ? nombre
                          : 'Empresa sin nombre';
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
                                CompanyLogoAvatar(
                                  empresaId: id,
                                  radius: 19,
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
                                        title,
                                        style: theme.textTheme.bodyLarge
                                            ?.copyWith(
                                              fontFamily: _kArial,
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.chevron_right_rounded,
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

  Future<DocumentSnapshot<Map<String, dynamic>>?> _findUserByCedula(
    String cedula,
  ) async {
    final usuarios = _db.collection('TBL_USUARIOS');
    final candidates = <String, DocumentSnapshot<Map<String, dynamic>>>{};

    final byId = await usuarios.doc(cedula).get();
    if (byId.exists) candidates[byId.id] = byId;

    final byField = await usuarios.where('cedula', isEqualTo: cedula).get();
    for (final doc in byField.docs) {
      candidates[doc.id] = doc;
    }

    if (candidates.isEmpty) return null;
    if (candidates.containsKey(cedula)) return candidates[cedula];
    return candidates.values.first;
  }

  String _displayName(Map<String, dynamic> data) {
    final full = (data['nombreCompleto'] ?? '').toString().trim();
    if (full.isNotEmpty) return full;

    final nombres = (data['nombres'] ?? '').toString().trim();
    final apellidos = (data['apellidos'] ?? '').toString().trim();
    final combined = '$nombres $apellidos'.trim();
    if (combined.isNotEmpty) return combined;

    final primerNombre = (data['primerNombre'] ?? '').toString().trim();
    final primerApellido = (data['primerApellido'] ?? '').toString().trim();
    return '$primerNombre $primerApellido'.trim();
  }

  Future<bool> _ensureAccess(
    DocumentReference<Map<String, dynamic>> ref,
    Map<String, dynamic> data,
    String cedula,
    String empresaId,
  ) async {
    final password = (data['password'] ?? '').toString().trim();
    final hasPassword = password.isNotEmpty;
    final payload = <String, dynamic>{
      'usuario': cedula,
      'cedula': cedula,
      'empresaId': empresaId,
      'updatedAt': FieldValue.serverTimestamp(),
      if ((data['role'] ?? '').toString().trim().isEmpty) 'role': 'usuario',
    };

    if (!hasPassword) {
      payload.addAll({'password': '123456', 'needsPasswordChange': true});
    }

    await ref.set(payload, SetOptions(merge: true));
    return !hasPassword;
  }

  bool _shouldOpenHv(Map<String, dynamic> data) {
    final estado = (data['estadoHojaDeVida'] ?? '').toString().trim();
    final needsRevision = data['needsRevision'] == true;
    final registered = data['registered'] == true;

    if (estado == 'requiere_cambios' || needsRevision) return true;
    if (estado == 'en_revision' || estado == 'aprobado') return false;
    return !registered;
  }

  Future<void> _showAlreadyRegisteredDialog({
    required String cedula,
    required String empresaName,
    required bool createdAccess,
  }) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Registro ya iniciado'),
        content: Text(
          createdAccess
              ? 'Tu acceso quedo activado para $empresaName.\n\nUsuario: $cedula\nContrasena temporal: 123456\n\nIngresa por el login y cambia tu contrasena.'
              : 'Tu hoja de vida ya fue enviada o aprobada para $empresaName.\n\nIngresa por el login con tu usuario o cedula.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  Future<void> _verificarCedula() async {
    if (!_formKey.currentState!.validate()) return;

    final cedula = _cedulaCtrl.text.replaceAll(RegExp(r'[^0-9]'), '');
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await AnonymousAuthService.ensureSession();
      final userDoc = await _findUserByCedula(cedula);
      if (userDoc == null || !userDoc.exists) {
        setState(() {
          _error =
              'No encontramos tu cedula cargada por la empresa. Contacta a Talento Humano.';
          _isLoading = false;
        });
        return;
      }

      final data = userDoc.data() ?? <String, dynamic>{};
      final empresaIds = extractUserEmpresaIds(data);
      final selectedEmpresaId = await _selectEmpresaId(
        empresaIds,
        preselectedId: (data['empresaId'] as String?)?.trim(),
      );
      if (selectedEmpresaId == null || selectedEmpresaId.isEmpty) {
        setState(() {
          _error = 'Selecciona la empresa para continuar.';
          _isLoading = false;
        });
        return;
      }

      final nombres = await _loadEmpresaNames({selectedEmpresaId});
      final empresaName = nombres[selectedEmpresaId] ?? selectedEmpresaId;
      final createdAccess = await _ensureAccess(
        userDoc.reference,
        data,
        cedula,
        selectedEmpresaId,
      );

      if (!mounted) return;
      setState(() => _isLoading = false);

      if (_shouldOpenHv(data)) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DataPolicyScreen(
              cedula: cedula,
              empresaId: selectedEmpresaId,
              empresaNombre: empresaName,
              colaboradorNombre: _displayName(data),
              accessCreated: createdAccess,
            ),
          ),
        );
        return;
      }

      await _showAlreadyRegisteredDialog(
        cedula: cedula,
        empresaName: empresaName,
        createdAccess: createdAccess,
      );
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'Ocurrio un error validando tu registro. Intenta de nuevo.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 780;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Primer ingreso'),
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: isDesktop ? 32 : 18,
            vertical: isDesktop ? 32 : 18,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Card(
              elevation: isDesktop ? 2 : 0,
              margin: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(isDesktop ? 18 : 12),
              ),
              child: Padding(
                padding: EdgeInsets.all(isDesktop ? 28 : 18),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              Icons.badge_outlined,
                              color: scheme.onPrimaryContainer,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Activa tu acceso a To Do App',
                                  style: theme.textTheme.headlineSmall
                                      ?.copyWith(
                                        fontFamily: _kArial,
                                        fontWeight: FontWeight.w900,
                                      ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Validaremos tu cedula contra la informacion cargada por la empresa y te llevaremos a completar tu hoja de vida.',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontFamily: _kArial,
                                    color: scheme.onSurfaceVariant,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      TextFormField(
                        controller: _cedulaCtrl,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        decoration: const InputDecoration(
                          labelText: 'Cedula',
                          hintText: 'Escribe solo numeros',
                          prefixIcon: Icon(Icons.credit_card_rounded),
                          border: OutlineInputBorder(),
                        ),
                        onFieldSubmitted: (_) => _verificarCedula(),
                        validator: (v) {
                          final value = (v ?? '').replaceAll(
                            RegExp(r'[^0-9]'),
                            '',
                          );
                          if (value.isEmpty) return 'Ingrese la cedula';
                          if (value.length < 5) return 'Cedula invalida';
                          return null;
                        },
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: scheme.errorContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _error!,
                            style: TextStyle(
                              color: scheme.onErrorContainer,
                              fontFamily: _kArial,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 22),
                      FilledButton.icon(
                        onPressed: _isLoading ? null : _verificarCedula,
                        icon: _isLoading
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: scheme.onPrimary,
                                ),
                              )
                            : const Icon(Icons.arrow_forward_rounded),
                        label: Text(_isLoading ? 'Validando...' : 'Continuar'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          textStyle: const TextStyle(
                            fontFamily: _kArial,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No se crea un usuario nuevo: se activa el registro que Talento Humano ya cargo para tu cedula.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: _kArial,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
