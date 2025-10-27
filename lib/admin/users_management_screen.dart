import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class UsersManagementScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Gestión de Usuarios')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('TBL_USUARIOS').snapshots(),
        builder: (ctx, snap) {
          if (!snap.hasData) return Center(child: CircularProgressIndicator());
          final docs = snap.data!.docs;
          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (_, i) {
              final u = docs[i].data();
              return ListTile(
                leading: Icon(Icons.person),
                title: Text('${u['primerNombre']} ${u['primerApellido']}'),
                subtitle: Text('Cédula: ${u['cedula']}'),
                trailing: IconButton(
                  icon: Icon(Icons.edit),
                  onPressed: () {
                    // aquí podrías navegar a un UserDetailScreen para editar
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
