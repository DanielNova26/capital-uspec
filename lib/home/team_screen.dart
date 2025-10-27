// lib/home/team_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

const Color kMarronOscuro      = Color(0xffc28942);
const String kArial            = 'Arial';
const String _orgCollection    = 'TBL_ESTRUCTURA_ORGANIZACIONAL';
const String _hojaCollection   = 'TBL_HojasVida';
const String _cargosCollection = 'TBL_CARGOS';

class TeamScreen extends StatelessWidget {
  final String userId;
  const TeamScreen({Key? key, required this.userId}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance
          .collection(_orgCollection)
          .doc(userId)
          .get(),
      builder: (ctxLeader, snapLeader) {
        if (snapLeader.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (!snapLeader.hasData || !snapLeader.data!.exists) {
          return const Scaffold(
            body: Center(child: Text('Perfil no encontrado')),
          );
        }

        final leaderData  = snapLeader.data!.data()!;
        final fullName    = leaderData['nombre'] as String? ?? '';
        final parts       = fullName.split(' ');
        final firstName   = parts.isNotEmpty ? parts[0] : '';
        final lastName    = parts.length > 1 ? parts[1] : '';
        final leaderCargo = leaderData['cargo'] as String? ?? '';

        return Scaffold(
          appBar: AppBar(
            title: Text('Mi equipo de $firstName',
                style: const TextStyle(fontFamily: kArial)),
            backgroundColor: kMarronOscuro,
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Tu header
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$firstName $lastName',
                        style: const TextStyle(
                            fontFamily: kArial,
                            fontSize: 20,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(leaderCargo,
                        style:
                        const TextStyle(fontFamily: kArial, fontSize: 16)),
                  ],
                ),
              ),
              const Divider(),

              // Stream de tu cargo
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection(_cargosCollection)
                      .where('assigned_users_ids', arrayContains: userId)
                      .snapshots(),
                  builder: (ctxCargo, snapCargo) {
                    if (snapCargo.connectionState !=
                        ConnectionState.active) {
                      return const Center(
                          child: CircularProgressIndicator());
                    }
                    final docs = snapCargo.data?.docs ?? [];
                    if (docs.isEmpty) {
                      return const Center(
                        child: Text(
                          'No estás asignado a ningún cargo.',
                          style: TextStyle(fontFamily: kArial),
                        ),
                      );
                    }

                    // Solo tomamos el primer cargo donde apareces
                    final cargoData = docs.first.data();
                    final subIds    = List<String>.from(
                        cargoData['subordinates_ids'] ?? <String>[]);
                    final subNames  = List<String>.from(
                        cargoData['subordinates_names'] ?? <String>[]);

                    // Preparamos la lista de futuros para todos los subordinados
                    final subsFuture = Future.wait<Map<String, dynamic>>(
                      subIds.asMap().entries.map((entry) async {
                        final idx = entry.key;
                        final ced = entry.value;
                        final snapH = await FirebaseFirestore.instance
                            .collection(_hojaCollection)
                            .doc(ced)
                            .get();

                        String telefono = '';
                        String photoUrl = '';
                        String centro   = '';
                        String grupo    = '';

                        if (snapH.exists && snapH.data() != null) {
                          final hoja = snapH.data()!;
                          telefono = hoja['telefono'] as String? ?? '';
                          photoUrl = (hoja['fotoUrl'] as String?) ?? '';
                          if (photoUrl.isEmpty) {
                            photoUrl = (hoja['cedulaDocUrl'] as String?) ?? '';
                          }
                          centro = hoja['centro_costos'] as String? ?? '—';
                          grupo  = hoja['grupo_centro_costos'] as String? ?? '—';
                        }

                        return {
                          'cedula': ced,
                          'nombre': subNames.length > idx ? subNames[idx] : '',
                          'telefono': telefono,
                          'photoUrl': photoUrl,
                          'centro': centro,
                          'grupo' : grupo,
                        };
                      }),
                    );

                    return FutureBuilder<List<Map<String, dynamic>>>(
                      future: subsFuture,
                      builder: (ctxSub, snapSub) {
                        if (snapSub.connectionState != ConnectionState.done) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }
                        final subs = snapSub.data ?? [];

                        // Agrupar por centro de costos
                        final Map<String, List<Map<String, dynamic>>> grouped = {};
                        for (var s in subs) {
                          final key = s['centro'] as String;
                          grouped.putIfAbsent(key, () => []).add(s);
                        }

                        return ListView(
                          children: grouped.entries.map((entry) {
                            final centroName = entry.key;
                            final members    = entry.value;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 8),
                                  child: Text(
                                    'Centro de costos: $centroName',
                                    style: const TextStyle(
                                      fontFamily: kArial,
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                ...members.map((m) {
                                  final ced  = m['cedula'] as String;
                                  final name = m['nombre'] as String;
                                  final tel  = m['telefono'] as String;
                                  final url  = m['photoUrl'] as String;
                                  Widget avatar;
                                  if (url.isNotEmpty) {
                                    avatar = ClipOval(
                                      child: Image.network(
                                        url,
                                        width: 56,
                                        height: 56,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                        const Icon(Icons.person,
                                            size: 40,
                                            color: kMarronOscuro),
                                      ),
                                    );
                                  } else {
                                    avatar = const CircleAvatar(
                                      radius: 28,
                                      backgroundColor: Colors.grey,
                                      child: Icon(Icons.person,
                                          size: 40, color: kMarronOscuro),
                                    );
                                  }
                                  return Card(
                                    margin: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 4),
                                    child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                              children: [
                                                Text(name,
                                                    style: const TextStyle(
                                                        fontFamily: kArial,
                                                        fontSize: 16,
                                                        fontWeight:
                                                        FontWeight.bold)),
                                                const SizedBox(height: 4),
                                                Text('Cédula: $ced',
                                                    style: const TextStyle(
                                                        fontFamily: kArial)),
                                                const SizedBox(height: 4),
                                                Text(
                                                    'Tel: ${tel.isNotEmpty ? tel : '—'}',
                                                    style: const TextStyle(
                                                        fontFamily: kArial)),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          avatar,
                                        ],
                                      ),
                                    ),
                                  );
                                }),
                              ],
                            );
                          }).toList(),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
