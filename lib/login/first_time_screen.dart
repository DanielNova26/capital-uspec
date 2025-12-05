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
  bool _isLoading = false;
  String? _error;

  Future<DocumentSnapshot<Map<String, dynamic>>?> _selectEmpresa(
      List<DocumentSnapshot<Map<String, dynamic>>> docs,
      ) async {
    if (docs.length == 1) return docs.first;

    final empresasCol = FirebaseFirestore.instance.collection('TBL_EMPRESAS');
    final Map<String, String> nombres = {};
    final ids = docs
        .map((d) => (d.data()?['empresaId'] as String?)?.trim() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();

    await Future.wait(ids.map((id) async {
      final emp = await empresasCol.doc(id).get();
      if (emp.exists) {
        final nombre = (emp.data()?['nombre'] as String?)?.trim();
        if (nombre != null && nombre.isNotEmpty) nombres[id] = nombre;
      }
    }));

    return showDialog<DocumentSnapshot<Map<String, dynamic>>>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('Selecciona tu empresa'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: docs.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, index) {
                final doc = docs[index];
                final empresaId =
                    (doc.data()?['empresaId'] as String?)?.trim() ?? '';
                final nombre = nombres[empresaId];
                final title =
                nombre != null && nombre.isNotEmpty ? nombre : empresaId;

                return ListTile(
                  title: Text(title.isEmpty ? 'Empresa sin nombre' : title),
                  subtitle: empresaId.isEmpty
                      ? null
                      : Text(
                    empresaId,
                    style: const TextStyle(fontFamily: 'Arial'),
                  ),
                  onTap: () => Navigator.of(context).pop(doc),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _verificarCedula(BuildContext context) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final usuariosCol =
      FirebaseFirestore.instance.collection('TBL_USUARIOS');

      final Map<String, DocumentSnapshot<Map<String, dynamic>>> candidatos = {};

      final byId = await usuariosCol.doc(cedula).get();
      if (byId.exists) candidatos[byId.id] = byId;

      final query = await usuariosCol.where('cedula', isEqualTo: cedula).get();
      for (final d in query.docs) {
        candidatos[d.id] = d;
      }

      if (candidatos.isEmpty) {
        setState(() {
          _error =
          'No encontramos tu cédula en ninguna empresa. Contacta al administrador.';
          _isLoading = false;
        });
        return;}

      final docs = candidatos.values.toList();

      DocumentSnapshot<Map<String, dynamic>>? hoja;
      if (docs.length == 1) {
        hoja = docs.first;
      } else {
        hoja = await _selectEmpresa(docs);
        if (hoja == null) {
          setState(() {
            _error = 'Selecciona la empresa para continuar.';
            _isLoading = false;
          });
          return;
        }
      }

      final data = hoja.data()!;
      final empresaId = (data['empresaId'] as String?)?.trim() ?? '';

      if (empresaId.isEmpty) {
        setState(() {
          _error = 'El usuario no tiene empresa asignada. Contacta al administrador.';
          _isLoading = false;
        });
        return;
      }

      // 3. Si encontramos un registro válido, creamos/actualizamos el usuario de acceso
      if (hoja.exists) {
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
                      validator: (v) =>                          v == null || v.trim().isEmpty
                          ? "Ingrese la cédula"
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
