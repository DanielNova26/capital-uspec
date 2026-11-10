import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/transaccion_legible.dart';
import '../interventoria/interventoria_models.dart';

const _equipos = 'TBL_MANTENIMIENTO_EQUIPOS';
const _ordenes = 'TBL_MANTENIMIENTO_ORDENES';

enum TipoMantenimiento {
  correctivo('Correctivo'),
  preventivo('Preventivo');

  const TipoMantenimiento(this.label);
  final String label;
}

enum EstadoOrden {
  abierta('Abierta'),
  enCurso('En curso', valor: 'en_curso'),
  cerrada('Cerrada');

  const EstadoOrden(this.label, {String? valor}) : _valor = valor;
  final String label;
  final String? _valor;
  String get valor => _valor ?? name;
}

String _texto(Map<String, dynamic> data, String key) =>
    (data[key] ?? '').toString().trim();

typedef EstablecimientoMantenimiento = ({
  String id,
  CentroCostoRef centro,
  bool activo,
});

class EquipoMantenimiento {
  EquipoMantenimiento(this.id, Map<String, dynamic> data)
    : codigo = _texto(data, 'codigo'),
      nombre = _texto(data, 'nombre'),
      serie = _texto(data, 'serie'),
      factura = _texto(data, 'factura'),
      centroDocId = _texto(data, 'centroDocId'),
      updatedAt = data['updatedAt'] as Timestamp?;

  final String id, codigo, nombre, serie, factura, centroDocId;
  final Timestamp? updatedAt;
}

class OrdenMantenimiento {
  OrdenMantenimiento(this.id, Map<String, dynamic> data)
    : centroDocId = _texto(data, 'centroDocId'),
      equipoId = _texto(data, 'equipoId'),
      hallazgoId = _texto(data, 'hallazgoId'),
      detalle = _texto(data, 'detalle'),
      resultado = _texto(data, 'resultado'),
      factura = _texto(data, 'factura'),
      tipo = TipoMantenimiento.values.byName(data['tipo'] as String),
      estado = EstadoOrden.values.firstWhere((e) => e.valor == data['estado']),
      creada = (data['createdAt'] as Timestamp?)?.toDate(),
      cerrada = (data['cerradaAt'] as Timestamp?)?.toDate(),
      updatedAt = data['updatedAt'] as Timestamp?;

  final String id,
      centroDocId,
      equipoId,
      hallazgoId,
      detalle,
      resultado,
      factura;
  final TipoMantenimiento tipo;
  final EstadoOrden estado;
  final DateTime? creada, cerrada;
  final Timestamp? updatedAt;
}

class MantenimientoService {
  MantenimientoService(this.empresaId, {FirebaseFirestore? db})
    : _db = db ?? FirebaseFirestore.instance;

  final String empresaId;
  final FirebaseFirestore _db;

  Stream<List<EstablecimientoMantenimiento>> establecimientos() => _db
      .collection('TBL_CENTROS_COSTOS')
      .where('empresaId', isEqualTo: empresaId)
      .snapshots()
      .map((snapshot) {
        return [
          for (final doc in snapshot.docs)
            (
              id: doc.id,
              centro: CentroCostoRef.fromMap(doc.id, doc.data()),
              activo: doc.data()['enabled'] != false,
            ),
        ]..sort((a, b) => a.centro.nombre.compareTo(b.centro.nombre));
      });

  Stream<List<EquipoMantenimiento>> equipos() => _db
      .collection(_equipos)
      .where('empresaId', isEqualTo: empresaId)
      .snapshots()
      .map((snapshot) {
        return [
          for (final doc in snapshot.docs)
            EquipoMantenimiento(doc.id, doc.data()),
        ]..sort((a, b) => a.nombre.compareTo(b.nombre));
      });

  Stream<List<OrdenMantenimiento>> ordenes() => _db
      .collection(_ordenes)
      .where('empresaId', isEqualTo: empresaId)
      .snapshots()
      .map((snapshot) {
        return [
          for (final doc in snapshot.docs)
            OrdenMantenimiento(doc.id, doc.data()),
        ]..sort((a, b) {
          final fechaA = a.creada;
          final fechaB = b.creada;
          if (fechaA == null) return fechaB == null ? 0 : -1;
          return fechaB == null ? 1 : fechaB.compareTo(fechaA);
        });
      });

  Stream<List<InterventoriaHallazgo>> hallazgos(
    EstablecimientoMantenimiento establecimiento,
  ) {
    final ids = {establecimiento.id, establecimiento.centro.centroId};
    return _db
        .collection('TBL_INTERVENTORIA_HALLAZGOS')
        .where('empresaId', isEqualTo: empresaId)
        .where('centroCostoId', whereIn: ids.toList())
        .snapshots()
        .map((snapshot) {
          return [
            for (final doc in snapshot.docs)
              InterventoriaHallazgo.fromMap(doc.id, doc.data()),
          ]..sort((a, b) => b.fechaHallazgo.compareTo(a.fechaHallazgo));
        });
  }

  Future<InterventoriaHallazgo?> hallazgo(String id) async {
    final doc = await _db
        .collection('TBL_INTERVENTORIA_HALLAZGOS')
        .doc(id)
        .get();
    final data = doc.data();
    return data?['empresaId'] == empresaId
        ? InterventoriaHallazgo.fromMap(doc.id, data!)
        : null;
  }

  Future<void> guardarEquipo({
    EquipoMantenimiento? equipo,
    required String centroDocId,
    required String codigo,
    required String nombre,
    required String serie,
    required String factura,
  }) async {
    final collection = _db.collection(_equipos);
    final data = {
      'centroDocId': centroDocId,
      'codigo': codigo,
      'nombre': nombre,
      'serie': serie,
      'factura': factura,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (equipo == null) {
      await collection.add({...data, 'empresaId': empresaId});
      return;
    }
    await _actualizar(collection.doc(equipo.id), equipo.updatedAt, data);
  }

  Future<void> crearOrden({
    required String centroDocId,
    required String equipoId,
    required String hallazgoId,
    required TipoMantenimiento tipo,
    required String detalle,
    required String factura,
  }) async {
    await _db.collection(_ordenes).add({
      'empresaId': empresaId,
      'centroDocId': centroDocId,
      'equipoId': equipoId,
      'hallazgoId': hallazgoId,
      'tipo': tipo.name,
      'detalle': detalle,
      'factura': factura,
      'estado': EstadoOrden.abierta.valor,
      'resultado': '',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'cerradaAt': null,
    });
  }

  Future<void> avanzar(
    OrdenMantenimiento orden, {
    String? resultado,
    String? factura,
  }) => _actualizar(_db.collection(_ordenes).doc(orden.id), orden.updatedAt, {
    'factura': ?factura,
    'updatedAt': FieldValue.serverTimestamp(),
    if (orden.estado == EstadoOrden.abierta)
      'estado': EstadoOrden.enCurso.valor,
    if (orden.estado == EstadoOrden.enCurso) ...{
      'estado': EstadoOrden.cerrada.valor,
      'resultado': resultado,
      'cerradaAt': FieldValue.serverTimestamp(),
    },
  });

  Future<void> _actualizar(
    DocumentReference<Map<String, dynamic>> ref,
    Timestamp? version,
    Map<String, dynamic> data,
  ) => _db.runTransactionLegible((transaction) async {
    final actual = (await transaction.get(ref)).data();
    if (actual == null || actual['empresaId'] != empresaId) {
      throw StateError('El registro ya no está disponible.');
    }
    if (actual['updatedAt'] != version) {
      throw StateError('El registro cambió. Abre la versión actualizada.');
    }
    transaction.update(ref, data);
  });
}
