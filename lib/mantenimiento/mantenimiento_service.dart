import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

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

enum IntervencionMantenimiento {
  procesamiento('Procesamiento'),
  coccion('Cocción'),
  refrigeracion('Refrigeración'),
  infraestructura('Infraestructura'),
  medicion('Medición'),
  otros('Otros');

  const IntervencionMantenimiento(this.label);
  final String label;

  static IntervencionMantenimiento? leer(String valor) {
    for (final tipo in values) {
      if (tipo.name == valor) return tipo;
    }
    return null;
  }
}

enum ClaseArchivoOrden {
  diagnostico('Fotos iniciales', true),
  cotizacion('Cotizaciones', false),
  evidencia('Fotos del trabajo realizado', true),
  recibo('Recibos y soportes de pago', false);

  const ClaseArchivoOrden(this.label, this.soloFotos);
  final String label;
  final bool soloFotos;
}

typedef ArchivoOrden = ({
  String id,
  String nombre,
  String mime,
  ClaseArchivoOrden clase,
});
typedef ArchivoPendienteOrden = ({ArchivoOrden archivo, Uint8List bytes});

class CierreMantenimiento {
  const CierreMantenimiento({
    this.trabajo = '',
    this.materiales = '',
    this.sugerencias = '',
    this.tecnico = '',
    this.receptor = '',
    this.cargoReceptor = '',
  });

  factory CierreMantenimiento.fromMap(Map<String, dynamic> data) =>
      CierreMantenimiento(
        trabajo: _texto(data, 'trabajo'),
        materiales: _texto(data, 'materiales'),
        sugerencias: _texto(data, 'sugerencias'),
        tecnico: _texto(data, 'tecnico'),
        receptor: _texto(data, 'receptor'),
        cargoReceptor: _texto(data, 'cargoReceptor'),
      );

  final String trabajo,
      materiales,
      sugerencias,
      tecnico,
      receptor,
      cargoReceptor;

  Map<String, String> toMap() => {
    'trabajo': trabajo,
    'materiales': materiales,
    'sugerencias': sugerencias,
    'tecnico': tecnico,
    'receptor': receptor,
    'cargoReceptor': cargoReceptor,
  };
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

enum OrigenTareaMantenimiento {
  interventoria('Interventoría'),
  visitas('Visitas'),
  inventario('Inventario'),
  manual('Manual');

  const OrigenTareaMantenimiento(this.label);
  final String label;

  static OrigenTareaMantenimiento? leer(Object? valor) =>
      values.where((origen) => origen.name == valor).firstOrNull;
}

class TareaMantenimiento {
  TareaMantenimiento(Map<String, dynamic> data)
    : id = _texto(data, 'id'),
      titulo = _texto(data, 'titulo'),
      descripcion = _texto(data, 'descripcion'),
      responsable = _texto(data, 'responsable'),
      centroDocId = _texto(data, 'centroDocId'),
      subcentroId = _texto(data, 'subcentroId'),
      subcentroNombre = _texto(data, 'subcentroNombre'),
      estado = _texto(data, 'estado'),
      numero = (data['numero'] as num?)?.toInt(),
      fechaLimite = (data['fechaLimite'] as num?) == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              (data['fechaLimite'] as num).toInt(),
            ),
      origen = OrigenTareaMantenimiento.values.byName(_texto(data, 'origen'));

  final String id,
      titulo,
      descripcion,
      responsable,
      centroDocId,
      subcentroId,
      subcentroNombre,
      estado;
  final int? numero;
  final DateTime? fechaLimite;
  final OrigenTareaMantenimiento origen;

  String get estadoLabel => switch (estado) {
    'pendiente' => 'Pendiente',
    'en_progreso' => 'En progreso',
    'devuelta' => 'Devuelta',
    'reasignado' => 'Reasignada',
    _ => estado,
  };
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
      datos = data,
      existencias = data['inventario'] == true
          ? Map<String, int>.from(data['existencias'] as Map? ?? const {})
          : _texto(data, 'centroDocId').isNotEmpty
          ? {_texto(data, 'centroDocId'): 1}
          : const {},
      updatedAt = data['updatedAt'] as Timestamp?;

  final String id, codigo, nombre, serie, factura, centroDocId;
  final Map<String, dynamic> datos;
  final Map<String, int> existencias;
  String get familia => _texto(datos, 'familia');
  final Timestamp? updatedAt;
}

class OrdenMantenimiento {
  OrdenMantenimiento(this.id, Map<String, dynamic> data)
    : centroDocId = _texto(data, 'centroDocId'),
      equipoId = _texto(data, 'equipoId'),
      hallazgoId = _texto(data, 'hallazgoId'),
      tareaId = _texto(data, 'tareaId'),
      tareasOrigen = [
        for (final tarea
            in (data['tareasOrigen'] as List? ?? []).whereType<Map>())
          TareaMantenimiento(Map<String, dynamic>.from(tarea)),
      ],
      origenTarea = OrigenTareaMantenimiento.leer(data['origenTarea']),
      numeroTarea = (data['numeroTarea'] as num?)?.toInt(),
      responsableTarea = _texto(data, 'responsableTarea'),
      limiteTarea = (data['limiteTarea'] as Timestamp?)?.toDate(),
      detalle = _texto(data, 'detalle'),
      actividades = _texto(data, 'actividades'),
      resultado = _texto(data, 'resultado'),
      factura = _texto(data, 'factura'),
      titulo = _texto(data, 'titulo'),
      subcentroId = _texto(data, 'subcentroId'),
      subcentroNombre = _texto(data, 'subcentroNombre'),
      intervencion = IntervencionMantenimiento.leer(
        _texto(data, 'intervencion'),
      ),
      numero = data['numero'] as int?,
      esquema = (data['esquema'] as int?) ?? 1,
      cierre = data['cierre'] is Map<String, dynamic>
          ? CierreMantenimiento.fromMap(data['cierre'] as Map<String, dynamic>)
          : null,
      archivos = [
        for (final archivo
            in (data['archivos'] as List? ?? []).whereType<Map>())
          (
            id: archivo['id'] as String,
            nombre: archivo['nombre'] as String,
            mime: archivo['mime'] as String,
            clase: ClaseArchivoOrden.values.byName(archivo['clase'] as String),
          ),
      ],
      hallazgoExterno = data['hallazgoExterno'] is Map
          ? Map<String, String>.from(data['hallazgoExterno'] as Map)
          : const {},
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
      actividades,
      resultado,
      factura;
  final TipoMantenimiento tipo;
  final EstadoOrden estado;
  final String titulo, subcentroId, subcentroNombre;
  final IntervencionMantenimiento? intervencion;
  final int? numero;
  final int esquema;
  final CierreMantenimiento? cierre;
  final List<ArchivoOrden> archivos;
  final String tareaId;
  final List<TareaMantenimiento> tareasOrigen;
  Iterable<String> get tareaIds => tareasOrigen.isEmpty
      ? [if (tareaId.isNotEmpty) tareaId]
      : tareasOrigen.map((tarea) => tarea.id);
  final OrigenTareaMantenimiento? origenTarea;
  final int? numeroTarea;
  final String responsableTarea;
  final DateTime? limiteTarea;
  final Map<String, String> hallazgoExterno;
  final DateTime? creada, cerrada;
  final Timestamp? updatedAt;

  String get referencia => numero?.toString().padLeft(3, '0') ?? id;
  String get asunto => titulo.isEmpty ? detalle : titulo;
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

  Future<({String id, bool existente, bool mismaSolicitud})> crearOrden({
    required String ordenId,
    required String centroDocId,
    required String equipoId,
    required String hallazgoId,
    required String subcentroId,
    required TipoMantenimiento tipo,
    required IntervencionMantenimiento intervencion,
    required String titulo,
    required String detalle,
    required String factura,
    Map<String, String>? hallazgoExterno,
    String tareaId = '',
    List<String> tareasAdicionales = const [],
    String? actividades,
  }) async {
    final respuesta = await _operar('crear', ordenId, {
      'centroDocId': centroDocId,
      'equipoId': equipoId,
      'hallazgoId': hallazgoId,
      'subcentroId': subcentroId,
      'tipo': tipo.name,
      'intervencion': intervencion.name,
      'titulo': titulo,
      'detalle': detalle,
      'actividades': ?actividades,
      'factura': factura,
      'hallazgoExterno': hallazgoExterno,
      if (tareaId.isNotEmpty) 'tareaId': tareaId,
      if (tareasAdicionales.isNotEmpty) 'tareaIds': tareasAdicionales,
    });
    return (
      id: (respuesta['ordenId'] as String?) ?? ordenId,
      existente: respuesta['existente'] == true,
      mismaSolicitud: respuesta['mismaSolicitud'] == true,
    );
  }

  Future<List<TareaMantenimiento>> tareasPendientes() async {
    final respuesta = await _operar('tareas', '', {});
    return [
      for (final tarea in (respuesta['tareas'] as List).whereType<Map>())
        TareaMantenimiento(Map<String, dynamic>.from(tarea)),
    ];
  }

  Future<OrdenMantenimiento> orden(String ordenId) async {
    final documento = await _db.collection(_ordenes).doc(ordenId).get();
    final data = documento.data();
    if (data == null || data['empresaId'] != empresaId) {
      throw StateError('La orden no está disponible.');
    }
    return OrdenMantenimiento(documento.id, data);
  }

  Future<void> editarOrden(
    OrdenMantenimiento orden, {
    required TipoMantenimiento tipo,
    required IntervencionMantenimiento intervencion,
    required String titulo,
    required String detalle,
    required String factura,
    String? actividades,
  }) => _mutar('editar', orden, {
    'tipo': tipo.name,
    'intervencion': intervencion.name,
    'titulo': titulo,
    'detalle': detalle,
    'actividades': ?actividades,
    'factura': factura,
  });

  Future<void> avanzar(OrdenMantenimiento orden, {String factura = ''}) =>
      _mutar(
        orden.estado == EstadoOrden.cerrada ? 'factura' : 'iniciar',
        orden,
        {'factura': factura},
      );

  Future<void> guardarCierre(
    OrdenMantenimiento orden,
    CierreMantenimiento datos, {
    required String factura,
    required bool cerrar,
  }) => _mutar(cerrar ? 'cerrar' : 'borrador', orden, {
    ...datos.toMap(),
    'factura': factura,
  });

  Future<void> adjuntar(String ordenId, ArchivoPendienteOrden pendiente) async {
    final archivo = pendiente.archivo;
    await _operar('adjuntar', ordenId, {
      'archivoId': archivo.id,
      'clase': archivo.clase.name,
      'nombre': archivo.nombre,
      'mime': archivo.mime,
      'base64': base64Encode(pendiente.bytes),
    });
  }

  Future<void> quitarArchivo(String ordenId, String archivoId) async {
    await _operar('quitarArchivo', ordenId, {'archivoId': archivoId});
  }

  Future<Uint8List> leerArchivo(String ordenId, String archivoId) async {
    final resultado = await _operar('leerArchivo', ordenId, {
      'archivoId': archivoId,
    });
    return base64Decode(resultado['base64'] as String);
  }

  Future<void> _mutar(
    String accion,
    OrdenMantenimiento orden,
    Map<String, dynamic> datos,
  ) async {
    await _operar(accion, orden.id, {
      ...datos,
      'segundos': orden.updatedAt?.seconds,
      'nanosegundos': orden.updatedAt?.nanoseconds,
    });
  }

  Future<Map<String, dynamic>> _operar(
    String accion,
    String ordenId,
    Map<String, dynamic> datos,
  ) async {
    try {
      final resultado =
          await FirebaseFunctions.instanceFor(
            region: 'us-central1',
          ).httpsCallable('mantenimientoOrden').call<Map<String, dynamic>>({
            ...datos,
            'empresaId': empresaId,
            'accion': accion,
            'ordenId': ordenId,
          });
      return resultado.data;
    } on FirebaseFunctionsException catch (error) {
      throw StateError(error.message ?? 'No se pudo procesar la orden.');
    }
  }

  Future<Map<String, dynamic>> inventario(
    String accion, [
    Map<String, dynamic> datos = const {},
  ]) async {
    try {
      final resultado =
          await FirebaseFunctions.instanceFor(
            region: 'us-central1',
          ).httpsCallable('mantenimientoInventario').call<Map<String, dynamic>>(
            {...datos, 'empresaId': empresaId, 'accion': accion},
          );
      return resultado.data;
    } on FirebaseFunctionsException catch (error) {
      throw StateError(error.message ?? 'No se pudo procesar el inventario.');
    }
  }

  Future<Map<String, dynamic>> listadosPdf() => _operar('listadosPdf', '', {});

  Future<Map<String, dynamic>> enviarPdf(
    String ordenId,
    String listadoId,
    Uint8List bytes,
  ) => _operar('enviarPdf', ordenId, {
    'listadoId': listadoId,
    'base64': base64Encode(bytes),
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
