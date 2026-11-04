import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/user_company.dart';

/// Consulta el estado de Talento Humano sin reescribir los espejos históricos.
/// Los módulos mantienen los usuarios como fuente de identidad y permisos.
class PersonalEmpresaEstado {
  const PersonalEmpresaEstado(this.empresaId, this.estructuras);

  final String empresaId;
  final Map<String, Map<String, dynamic>> estructuras;

  static Future<PersonalEmpresaEstado> cargar(
    FirebaseFirestore db,
    String empresaId,
  ) async {
    final col = db.collection('TBL_ESTRUCTURA_ORGANIZACIONAL');
    final snaps = await Future.wait([
      col.where('empresaId', isEqualTo: empresaId).get(),
      col.where('empresas', arrayContains: empresaId).get(),
    ]);
    return PersonalEmpresaEstado(empresaId, {
      for (final snap in snaps)
        for (final doc in snap.docs) doc.id: doc.data(),
    });
  }

  bool habilitada(String userId, Map<String, dynamic> usuario) {
    final cedula = (usuario['cedula'] ?? '').toString().trim();
    final estructura = estructuras[cedula] ?? estructuras[userId];
    return personaHabilitadaEn(usuario, empresaId, estructura: estructura);
  }
}
