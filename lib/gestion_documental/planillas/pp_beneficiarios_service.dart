import 'package:cloud_firestore/cloud_firestore.dart';

import 'pp_archivo_plano.dart';
import 'pp_cuentas_models.dart';

/// Acceso al maestro de beneficiarios de pago.
///
/// El maestro y el número de cuenta viven en **dos colecciones** (ver
/// `pp_cuentas_models.dart`), así que este servicio siempre habla con las dos y
/// las vuelve a juntar. Quien lo llame trabaja con `CuentaBancaria` y no tiene
/// que saber del corte.
class PpBeneficiariosService {
  final FirebaseFirestore _db;

  PpBeneficiariosService({FirebaseFirestore? db})
    : _db = db ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _maestro =>
      _db.collection(kCuentasBancariasCol);
  CollectionReference<Map<String, dynamic>> get _numeros =>
      _db.collection(kCuentasNumeroCol);

  /// Beneficiarios de la empresa, **sin** el número de cuenta.
  ///
  /// El número no viaja aquí a propósito: son cientos de documentos y traerlos
  /// todos para pintar una lista sería exponer de más y pagar de más. Se pide
  /// uno a uno cuando alguien abre la ficha, o en bloque solo al generar el
  /// archivo plano.
  Stream<List<CuentaBancaria>> stream(String empresaId) => _maestro
      .where('empresaId', isEqualTo: empresaId)
      .snapshots()
      .map(
        (s) =>
            s.docs.map((d) => CuentaBancaria.fromMap(d.id, d.data())).toList()
              ..sort(
                (a, b) =>
                    a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()),
              ),
      );

  /// Número de cuenta de un beneficiario.
  ///
  /// Devuelve vacío si quien pregunta no tiene permiso. **No se relanza el
  /// error**: que Tesorería lo vea y Talento Humano no es el diseño, no un
  /// fallo, y convertirlo en una pantalla roja enseñaría un problema donde no
  /// lo hay.
  Future<String> numeroDe(String empresaId, String cedula) async {
    try {
      final doc = await _numeros
          .doc(cuentaBancariaDocId(empresaId, cedula))
          .get();
      return (doc.data()?['numeroCuenta'] ?? '').toString();
    } catch (_) {
      return '';
    }
  }

  /// Guarda un beneficiario completo. Escribe en las dos colecciones.
  ///
  /// El número solo se toca cuando viene con algo: guardar la ficha sin
  /// permiso sobre el número no puede borrar el que ya estaba.
  Future<void> guardar(CuentaBancaria cuenta, {required String actorId}) async {
    final id = cuentaBancariaDocId(cuenta.empresaId, cuenta.cedula);
    await _maestro.doc(id).set({
      ...cuenta.toMapPublico(),
      'actualizadoPor': actorId,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (cuenta.numeroCuenta.trim().isEmpty) return;
    await _numeros.doc(id).set({
      ...cuenta.toMapNumero(),
      'numeroActualizadoPor': actorId,
      'numeroActualizadoEn': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Solo el banco. Es la operación que hará Talento Humano cuando entre.
  Future<void> guardarBanco({
    required String empresaId,
    required String cedula,
    required String bancoCodigo,
    required String actorId,
  }) => _maestro.doc(cuentaBancariaDocId(empresaId, cedula)).set({
    'bancoCodigo': normalizarCodigoBanco(bancoCodigo),
    'actualizadoPor': actorId,
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));

  Future<void> eliminar(String empresaId, String cedula) async {
    final id = cuentaBancariaDocId(empresaId, cedula);
    await Future.wait([
      _maestro.doc(id).delete(),
      // El número se borra aparte: si se olvidara, quedaría un documento
      // huérfano con una cuenta bancaria dentro y sin nada que lo nombre.
      _numeros.doc(id).delete().catchError((_) {}),
    ]);
  }

  /// Guarda un lote importado. Solo lo que pasó la revisión.
  Future<int> importar(
    List<CuentaBancaria> cuentas, {
    required String actorId,
  }) async {
    var escritas = 0;
    // De 500 en 500: es el tope de un batch de Firestore, y cada beneficiario
    // ocupa dos escrituras porque son dos colecciones.
    const porLote = 240;
    for (var i = 0; i < cuentas.length; i += porLote) {
      final batch = _db.batch();
      for (final c in cuentas.skip(i).take(porLote)) {
        final id = cuentaBancariaDocId(c.empresaId, c.cedula);
        batch.set(_maestro.doc(id), {
          ...c.toMapPublico(),
          'actualizadoPor': actorId,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        if (c.numeroCuenta.trim().isNotEmpty) {
          batch.set(_numeros.doc(id), {
            ...c.toMapNumero(),
            'numeroActualizadoPor': actorId,
            'numeroActualizadoEn': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
        escritas++;
      }
      await batch.commit();
    }
    return escritas;
  }

  /// El maestro en la forma que necesita el generador del archivo plano.
  ///
  /// Trae los números, así que solo funciona para quien puede leerlos. Es
  /// deliberado: sin número no hay archivo plano que valga.
  Future<Map<String, DatosBeneficiario>> paraArchivoPlano(
    String empresaId,
  ) async {
    final maestro = await _maestro
        .where('empresaId', isEqualTo: empresaId)
        .get();
    final numeros = await _numeros
        .where('empresaId', isEqualTo: empresaId)
        .get();
    final porId = {
      for (final d in numeros.docs)
        d.id: (d.data()['numeroCuenta'] ?? '').toString(),
    };
    return {
      for (final d in maestro.docs)
        (d.data()['cedula'] ?? '').toString().trim(): DatosBeneficiario(
          nombre: (d.data()['nombre'] ?? '').toString(),
          banco: (d.data()['bancoCodigo'] ?? '').toString(),
          tipoCuenta: (d.data()['tipoCuenta'] ?? '').toString(),
          numeroCuenta: porId[d.id] ?? '',
          digitoVerificacion: (d.data()['digitoVerificacion'] ?? '').toString(),
          tipoId: (d.data()['tipoId'] ?? '').toString(),
          email: (d.data()['email'] ?? '').toString(),
        ),
    };
  }
}
