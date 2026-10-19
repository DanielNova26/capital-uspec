import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/grupos_trabajo.dart';
import '../interventoria/interventoria_revision_maestro.dart';
import '../interventoria/interventoria_service.dart';

/// Historial y "Deshacer" de los cambios masivos de cobertura.
///
/// Antes de aplicar un lote (quitar grupos, fijar centro de costos o importar
/// un Excel) se guarda lo que cada persona tenía y lo que va a quedar:
/// `TBL_COBERTURA_LOTES/{lote}` con el resumen y, debajo, un documento por
/// persona en `personas`. Deshacer devuelve a cada una a su estado anterior,
/// salvo a quien alguien volvió a cambiar después (no se pisa un cambio más
/// reciente).
const String kColeccionCoberturaLotes = 'TBL_COBERTURA_LOTES';

/// Sedes y grupos de una persona en un momento dado.
class SedesPersona {
  const SedesPersona({
    this.operacion = const {},
    this.trabajo = const {},
    this.grupos = const {},
    this.todas = false,
  });

  final Set<String> operacion;
  final Set<String> trabajo;

  /// Normalizados (`G7`).
  final Set<String> grupos;

  /// Atiende todas las sedes (`coberturaGlobalInterventoria`).
  final bool todas;

  factory SedesPersona.deUsuario(InterventoriaUsuario u) => SedesPersona(
    operacion: {...u.centrosOperacionIds},
    trabajo: {...u.centrosTrabajoIds},
    grupos: {for (final g in u.grupos) claveGrupoTrabajo(g)},
    todas: u.cubreTodas,
  );

  factory SedesPersona.fromMap(Map<dynamic, dynamic>? m) {
    Set<String> set(Object? v) =>
        v is Iterable ? {for (final e in v) e.toString()} : <String>{};
    return SedesPersona(
      operacion: set(m?['operacion']),
      trabajo: set(m?['trabajo']),
      grupos: set(m?['grupos']),
      todas: m?['todas'] == true,
    );
  }

  Map<String, dynamic> toMap() => {
    'operacion': operacion.toList()..sort(),
    'trabajo': trabajo.toList()..sort(),
    'grupos': grupos.toList()..sort(),
    'todas': todas,
  };

  bool igualA(SedesPersona o) =>
      _igual(operacion, o.operacion) &&
      _igual(trabajo, o.trabajo) &&
      _igual(grupos, o.grupos) &&
      todas == o.todas;

  static bool _igual(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);
}

/// Lo que quedará una persona tras aplicar [c] sobre [antes]. Misma lógica
/// que `aplicarCambiosCobertura`.
SedesPersona estadoDespues(SedesPersona antes, CambioCobertura c) {
  final operacion = {...antes.operacion, ...c.agregarCentros}
    ..removeAll(c.quitarCentros);
  final trabajo = {...antes.trabajo}..removeAll(c.quitarCentros);
  final grupos = {...antes.grupos, ...c.agregarGrupos.map(claveGrupoTrabajo)}
    ..removeWhere(c.quitarGrupos.contains);
  return SedesPersona(
    operacion: c.fijarOperacion != null ? {...c.fijarOperacion!} : operacion,
    trabajo: c.fijarTrabajo != null ? {...c.fijarTrabajo!} : trabajo,
    grupos: c.fijarGrupos != null ? {...c.fijarGrupos!} : grupos,
    todas: c.fijarTodas ?? antes.todas,
  );
}

class PersonaDelLote {
  const PersonaDelLote({
    required this.userId,
    required this.nombre,
    required this.antes,
    required this.despues,
  });

  final String userId;
  final String nombre;
  final SedesPersona antes;
  final SedesPersona despues;

  Map<String, dynamic> toMap() => {
    'userId': userId,
    'nombre': nombre,
    'antes': antes.toMap(),
    'despues': despues.toMap(),
  };

  factory PersonaDelLote.fromMap(Map<String, dynamic> m) => PersonaDelLote(
    userId: (m['userId'] ?? '').toString(),
    nombre: (m['nombre'] ?? '').toString(),
    antes: SedesPersona.fromMap(m['antes'] as Map?),
    despues: SedesPersona.fromMap(m['despues'] as Map?),
  );
}

/// Arma el respaldo de un lote con lo que cada persona tiene HOY.
List<PersonaDelLote> prepararLote(
  List<CambioCobertura> cambios,
  Map<String, InterventoriaUsuario> actuales,
) {
  final out = <PersonaDelLote>[];
  for (final c in cambios) {
    final u = actuales[c.userId];
    if (u == null) continue;
    final antes = SedesPersona.deUsuario(u);
    out.add(
      PersonaDelLote(
        userId: c.userId,
        nombre: c.nombre,
        antes: antes,
        despues: estadoDespues(antes, c),
      ),
    );
  }
  return out;
}

class ResultadoDeshacer {
  const ResultadoDeshacer({
    this.cambios = const [],
    this.sinCambio = 0,
    this.modificadasDespues = const [],
    this.noEncontradas = const [],
  });

  /// Lo que hay que escribir para volver atrás.
  final List<CambioCobertura> cambios;

  /// Ya estaban como antes del lote.
  final int sinCambio;

  /// Alguien las cambió después del lote: no se tocan.
  final List<String> modificadasDespues;

  /// Ya no están activas en la empresa.
  final List<String> noEncontradas;
}

/// Qué hay que escribir para deshacer un lote sin pisar cambios posteriores.
ResultadoDeshacer planDeshacer(
  List<PersonaDelLote> personas,
  Map<String, InterventoriaUsuario> actuales,
) {
  final cambios = <CambioCobertura>[];
  final modificadas = <String>[];
  final perdidas = <String>[];
  var sin = 0;
  for (final p in personas) {
    final u = actuales[p.userId];
    if (u == null) {
      perdidas.add(p.nombre);
      continue;
    }
    final hoy = SedesPersona.deUsuario(u);
    if (hoy.igualA(p.antes)) {
      sin++;
    } else if (hoy.igualA(p.despues)) {
      cambios.add(
        CambioCobertura(
          userId: p.userId,
          nombre: p.nombre,
          fijarOperacion: {...p.antes.operacion},
          fijarTrabajo: {...p.antes.trabajo},
          fijarGrupos: {...p.antes.grupos},
          fijarTodas: p.antes.todas,
        ),
      );
    } else {
      modificadas.add(p.nombre);
    }
  }
  return ResultadoDeshacer(
    cambios: cambios,
    sinCambio: sin,
    modificadasDespues: modificadas,
    noEncontradas: perdidas,
  );
}

enum TipoLoteCobertura {
  quitarGrupos('Quitar grupos'),
  fijarCentroDeCostos('Fijar centro de costos'),
  excel('Importación de Excel');

  const TipoLoteCobertura(this.etiqueta);
  final String etiqueta;

  static TipoLoteCobertura desde(String v) =>
      values.firstWhere((t) => t.name == v, orElse: () => excel);
}

class LoteCobertura {
  const LoteCobertura({
    required this.id,
    required this.tipo,
    required this.archivo,
    required this.creadoPor,
    required this.creada,
    required this.total,
    required this.revertido,
    required this.revertidoPor,
  });

  final String id;
  final TipoLoteCobertura tipo;
  final String archivo;
  final String creadoPor;
  final DateTime? creada;
  final int total;
  final bool revertido;
  final String revertidoPor;

  factory LoteCobertura.fromDoc(String id, Map<String, dynamic> d) =>
      LoteCobertura(
        id: id,
        tipo: TipoLoteCobertura.desde((d['tipo'] ?? '').toString()),
        archivo: (d['archivo'] ?? '').toString(),
        creadoPor: (d['creadoPor'] ?? '').toString(),
        creada: d['createdAt'] is Timestamp
            ? (d['createdAt'] as Timestamp).toDate()
            : null,
        total: (d['total'] as num?)?.toInt() ?? 0,
        revertido: d['estado'] == 'revertido',
        revertidoPor: (d['revertidoPor'] ?? '').toString(),
      );
}

/// Lectura y escritura del historial en Firestore.
class CoberturaLotesRepository {
  CoberturaLotesRepository({FirebaseFirestore? db})
    : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  /// Guarda el respaldo ANTES de tocar a nadie. Devuelve el id del lote.
  Future<String> crear({
    required String empresaId,
    required String userId,
    required TipoLoteCobertura tipo,
    required List<PersonaDelLote> personas,
    String archivo = '',
  }) async {
    final ref = _db.collection(kColeccionCoberturaLotes).doc();
    await ref.set({
      'empresaId': empresaId,
      'tipo': tipo.name,
      'archivo': archivo,
      'creadoPor': userId,
      'createdAt': FieldValue.serverTimestamp(),
      'total': personas.length,
      'estado': 'aplicado',
    });
    for (var i = 0; i < personas.length; i += 400) {
      final lote = _db.batch();
      for (final p in personas.skip(i).take(400)) {
        lote.set(ref.collection('personas').doc(p.userId), p.toMap());
      }
      await lote.commit();
    }
    return ref.id;
  }

  Future<List<LoteCobertura>> listar(
    String empresaId, {
    int limite = 40,
  }) async {
    final snap = await _db
        .collection(kColeccionCoberturaLotes)
        .where('empresaId', isEqualTo: empresaId)
        .get();
    final lotes = [
      for (final d in snap.docs) LoteCobertura.fromDoc(d.id, d.data()),
    ];
    lotes.sort(
      (a, b) =>
          (b.creada ?? DateTime(2000)).compareTo(a.creada ?? DateTime(2000)),
    );
    return lotes.take(limite).toList();
  }

  Future<List<PersonaDelLote>> personasDe(String loteId) async {
    final snap = await _db
        .collection(kColeccionCoberturaLotes)
        .doc(loteId)
        .collection('personas')
        .get();
    return [for (final d in snap.docs) PersonaDelLote.fromMap(d.data())];
  }

  Future<void> marcarRevertido(String loteId, String userId) =>
      _db.collection(kColeccionCoberturaLotes).doc(loteId).update({
        'estado': 'revertido',
        'revertidoPor': userId,
        'revertidoAt': FieldValue.serverTimestamp(),
      });
}
