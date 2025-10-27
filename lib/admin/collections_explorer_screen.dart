import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Pantalla para explorar colecciones «conocidas» de Firestore.
class CollectionsExplorerScreen extends StatelessWidget {
  const CollectionsExplorerScreen({Key? key}) : super(key: key);

  // Si más adelante quieres descubrir automáticamente, tendrás que
  // mantener tu propia lista o usar la Admin SDK en un servidor.
  static const _knownCollections = <String>[
    'TBL_USUARIOS',
    'TBL_HojasVida',
    'TBL_ESTRUCTURA_ORGANIZACIONAL',
    'roles',
    'apps',
    'permissions',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Explorar Colecciones')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _knownCollections.length,
        separatorBuilder: (_, __) => const Divider(),
        itemBuilder: (context, i) {
          final name = _knownCollections[i];
          return ListTile(
            title: Text(name),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DocumentListScreen(collectionName: name),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Muestra todos los documentos de una colección.
class DocumentListScreen extends StatelessWidget {
  final String collectionName;
  const DocumentListScreen({Key? key, required this.collectionName}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final coll = FirebaseFirestore.instance.collection(collectionName);

    return Scaffold(
      appBar: AppBar(title: Text('Docs: $collectionName')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: coll.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(child: Text('Colección vacía'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(),
            itemBuilder: (context, i) {
              final d = docs[i];
              final data = d.data();
              return ExpansionTile(
                title: Text(d.id, style: const TextStyle(fontWeight: FontWeight.bold)),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(_prettyMap(data)),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  String _prettyMap(Map<String, dynamic> m) {
    return m.entries.map((e) => '${e.key}: ${e.value}').join('\n');
  }
}
