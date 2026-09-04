// lib/admin/users_management_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../widgets/user_avatar.dart';

/// Pantalla principal que lista todos los usuarios y permite editarlos.
class UsersManagementScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gestión de Usuarios')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('TBL_USUARIOS')
            .snapshots(),
        builder: (ctx, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data!.docs;
          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (_, i) {
              final doc = docs[i];
              final u = doc.data();
              final nombre = [
                (u['primerNombre'] ?? u['nombres'] ?? '').toString().trim(),
                (u['primerApellido'] ?? u['apellidos'] ?? '').toString().trim(),
              ].where((s) => s.isNotEmpty).join(' ');
              return ListTile(
                leading: UserAvatar(userId: doc.id, nameHint: nombre),
                title: UserNameText(doc.id, fallbackName: nombre),
                subtitle: Text('Cédula: ${u['cedula']}'),
                trailing: IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () {
                    // Navegamos a la pantalla de edición pasando el documento completo.
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => UserDetailScreen(userDoc: doc),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Pantalla de edición de un usuario concreto.
/// Permite editar nombre, apellido y cédula y guarda los cambios en Firestore.
class UserDetailScreen extends StatefulWidget {
  final DocumentSnapshot<Map<String, dynamic>> userDoc;

  const UserDetailScreen({Key? key, required this.userDoc}) : super(key: key);

  @override
  _UserDetailScreenState createState() => _UserDetailScreenState();
}

class _UserDetailScreenState extends State<UserDetailScreen> {
  late final TextEditingController _primerNombreCtrl;
  late final TextEditingController _primerApellidoCtrl;
  late final TextEditingController _cedulaCtrl;

  @override
  void initState() {
    super.initState();
    final data = widget.userDoc.data() ?? {};
    _primerNombreCtrl = TextEditingController(text: data['primerNombre'] ?? '');
    _primerApellidoCtrl = TextEditingController(
      text: data['primerApellido'] ?? '',
    );
    _cedulaCtrl = TextEditingController(text: data['cedula'] ?? '');
  }

  @override
  void dispose() {
    _primerNombreCtrl.dispose();
    _primerApellidoCtrl.dispose();
    _cedulaCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    // Referencia al documento original.
    final ref = widget.userDoc.reference;

    // Actualizamos los campos en Firestore.
    await ref.update({
      'primerNombre': _primerNombreCtrl.text.trim(),
      'primerApellido': _primerApellidoCtrl.text.trim(),
      'cedula': _cedulaCtrl.text.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Regresamos a la pantalla anterior y mostramos un mensaje.
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Usuario actualizado')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Editar usuario')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _primerNombreCtrl,
              decoration: const InputDecoration(labelText: 'Primer nombre'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _primerApellidoCtrl,
              decoration: const InputDecoration(labelText: 'Primer apellido'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _cedulaCtrl,
              decoration: const InputDecoration(labelText: 'Cédula'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _save, child: const Text('Guardar')),
          ],
        ),
      ),
    );
  }
}
