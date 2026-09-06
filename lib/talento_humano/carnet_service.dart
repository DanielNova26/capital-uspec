// lib/talento_humano/carnet_service.dart
//
// De dónde sale cada dato del carnet.
//
// Casi todo vive en el documento raíz de TBL_USUARIOS, que ya trae nombre,
// cargo, foto y token. El RH es la excepción: solo existe en la hoja de vida
// (`TBL_USUARIOS/{id}/hoja_de_vida/datos`), así que se lee aparte y SOLO para
// las personas que se van a imprimir. Leer la subcolección de todo el padrón
// para pintar un listado sería una lectura por persona cada vez que alguien
// abre la pantalla.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:todo/data/firestore_user_repository.dart';
import 'package:todo/utils/user_company.dart';

import 'carnet_pdf.dart';
import 'carnet_qr.dart';

/// Una persona en el listado de selección. Es lo que se ve ANTES de generar:
/// todavía sin RH ni token, porque eso cuesta lecturas y escrituras.
class CarnetCandidato {
  final String userId;
  final String cedula;
  final String nombres;
  final String apellidos;
  final String cargo;
  final String fotoUrl;
  final bool activo;

  /// La hoja de vida está aprobada. No bloquea la impresión, pero se muestra:
  /// un carnet con datos sin revisar sale a la calle con el nombre de la
  /// empresa encima.
  final bool hojaAprobada;

  /// Ya tiene un carnet impreso antes (token generado).
  final bool tieneCarnet;

  const CarnetCandidato({
    required this.userId,
    required this.cedula,
    required this.nombres,
    required this.apellidos,
    required this.cargo,
    this.fotoUrl = '',
    this.activo = true,
    this.hojaAprobada = false,
    this.tieneCarnet = false,
  });

  String get nombreCompleto {
    final completo = '$nombres $apellidos'.trim();
    return completo.isEmpty ? cedula : completo;
  }

  bool get tieneFoto => fotoUrl.trim().isNotEmpty;

  bool coincideCon(String consulta) {
    final q = consulta.trim().toLowerCase();
    if (q.isEmpty) return true;
    return nombreCompleto.toLowerCase().contains(q) ||
        cedula.toLowerCase().contains(q) ||
        cargo.toLowerCase().contains(q);
  }
}

class CarnetService {
  final FirebaseFirestore _db;
  final FirestoreUserRepository _users;

  CarnetService({FirebaseFirestore? db, FirestoreUserRepository? users})
    : _db = db ?? FirebaseFirestore.instance,
      _users = users ?? FirestoreUserRepository.instance;

  /// Personal de la empresa, ordenado por nombre.
  ///
  /// Trae también a quien está retirado: se marca en la fila, no se esconde.
  /// Talento Humano necesita ver que existe para entender por qué no debería
  /// imprimirle carnet, y a veces hay que reimprimir el de alguien que se fue
  /// para reemplazarlo por el duplicado.
  Future<List<CarnetCandidato>> cargarCandidatos(String empresaId) async {
    final id = empresaId.trim();
    if (id.isEmpty) return const <CarnetCandidato>[];

    final docs = await _users.loadUsersByEmpresa(id);
    final cargosPorId = await _cargoNombrePorId(id);

    final filas = docs.map((doc) {
      final data = doc.data();
      final detalle = getUserCompanyDetail(data, id);
      final estadoLaboral = (detalle?['estadoLaboral'] ?? '')
          .toString()
          .trim()
          .toLowerCase();

      final cargoCrudo = resolveScopedStringWithFallbacks(
        data,
        id,
        const ['cargoNombre', 'cargo'],
        const ['cargoNombre', 'cargo'],
      ).trim();

      return CarnetCandidato(
        userId: doc.id,
        cedula: (data['cedula'] ?? doc.id).toString().trim(),
        nombres: _nombres(data),
        apellidos: _apellidos(data),
        cargo: cargosPorId[cargoCrudo] ?? cargoCrudo,
        fotoUrl: (data['fotoUrl'] ?? '').toString().trim(),
        // El retiro vive en el bloque de la empresa; el `estado` raíz solo
        // gobierna el login y no dice nada del vínculo laboral.
        activo: estadoLaboral.isEmpty || estadoLaboral == 'activo',
        hojaAprobada:
            (data['estadoHojaDeVida'] ?? '').toString().trim().toLowerCase() ==
            'aprobado',
        tieneCarnet: (data['carnetToken'] ?? '').toString().trim().isNotEmpty,
      );
    }).toList();

    filas.sort(
      (a, b) => a.nombreCompleto.toLowerCase().compareTo(
        b.nombreCompleto.toLowerCase(),
      ),
    );
    return filas;
  }

  /// Arma los datos definitivos de una persona y le asegura el token.
  ///
  /// `asegurarTokenCarnet` no rota nada: si ya tenía carnet, se reimprime el
  /// MISMO QR. Generar un token nuevo en cada impresión invalidaría el carnet
  /// que la persona lleva encima cada vez que alguien reimprime la hoja.
  Future<CarnetPersona> prepararPersona({
    required CarnetCandidato candidato,
    required String empresaId,
  }) async {
    final token = await asegurarTokenCarnet(
      userId: candidato.userId,
      empresaId: empresaId,
      db: _db,
    );
    return CarnetPersona(
      userId: candidato.userId,
      nombres: candidato.nombres,
      apellidos: candidato.apellidos,
      cargo: candidato.cargo,
      cedula: candidato.cedula,
      rh: await _tipoSangre(candidato.userId),
      token: token,
      fotoUrl: candidato.fotoUrl,
    );
  }

  /// Igual que [prepararPersona] pero para un lote.
  ///
  /// En serie a propósito: cada persona hace una lectura y puede hacer una
  /// escritura del token, y disparar 30 transacciones en paralelo desde un
  /// teléfono es la forma rápida de que Firestore empiece a rechazar.
  Future<List<CarnetPersona>> prepararLote({
    required List<CarnetCandidato> candidatos,
    required String empresaId,
  }) async {
    final salida = <CarnetPersona>[];
    for (final candidato in candidatos) {
      salida.add(
        await prepararPersona(candidato: candidato, empresaId: empresaId),
      );
    }
    return salida;
  }

  /// RH de la hoja de vida. Vacío si no está cargado: el carnet omite el
  /// renglón en vez de imprimir "RH: null".
  /// Tipo de sangre de la hoja de vida, para la vista previa.
  ///
  /// Va aparte de [prepararPersona] porque esa crea el token del carnet, y la
  /// vista previa no debe escribir nada solo por mirar.
  Future<String> tipoSangreDe(String userId) => _tipoSangre(userId);

  Future<String> _tipoSangre(String userId) async {
    try {
      final snap = await _db
          .collection('TBL_USUARIOS')
          .doc(userId)
          .collection('hoja_de_vida')
          .doc('datos')
          .get();
      return (snap.data()?['tipoSangre'] ?? '').toString().trim();
    } catch (_) {
      return '';
    }
  }

  /// Nombre de cada cargo por su id: parte del padrón guarda el ID en `cargo`
  /// y sin traducirlo el carnet saldría impreso con un identificador crudo.
  Future<Map<String, String>> _cargoNombrePorId(String empresaId) async {
    final snap = await _db
        .collection('TBL_CARGOS')
        .where('empresaId', isEqualTo: empresaId)
        .get();
    return {
      for (final doc in snap.docs)
        if ((doc.data()['nombre'] ?? '').toString().trim().isNotEmpty)
          doc.id: (doc.data()['nombre']).toString().trim(),
    };
  }

  static String _nombres(Map<String, dynamic> data) {
    final partes = [
      (data['primerNombre'] ?? '').toString().trim(),
      (data['segundoNombre'] ?? '').toString().trim(),
    ].where((p) => p.isNotEmpty).toList();
    if (partes.isNotEmpty) return partes.join(' ');
    // Padrón viejo: solo hay un campo con todo junto. Se imprime completo en
    // el renglón de nombres antes que dejar el carnet en blanco.
    return (data['nombreCompleto'] ?? data['nombre'] ?? data['nombres'] ?? '')
        .toString()
        .trim();
  }

  static String _apellidos(Map<String, dynamic> data) {
    final partes = [
      (data['primerApellido'] ?? '').toString().trim(),
      (data['segundoApellido'] ?? '').toString().trim(),
    ].where((p) => p.isNotEmpty).toList();
    if (partes.isNotEmpty) return partes.join(' ');
    return (data['apellidos'] ?? '').toString().trim();
  }
}
