// lib/admin/multiempresa_sync_service.dart
//
// Lectura y escritura en Firestore de la sincronización multiempresa. Toda la
// decisión de QUÉ escribir vive en `lib/core/multiempresa_sync.dart` (puro y
// con pruebas); aquí solo se cargan los documentos y se aplican los planes.
//
// Dónde se escribe, con las mismas reglas que ya usan Talento Humano e
// Interventoría:
//   * `TBL_USUARIOS/{cedula}`: `empresasDetalle.{empresa}.*` con rutas de
//     punto (no pisa las otras empresas) y la raíz solo si esa empresa es la
//     principal.
//   * `TBL_ESTRUCTURA_ORGANIZACIONAL/{cedula}`: igual, si el documento existe.
//   * `TBL_EMPLEADOS/{empresa}_{cedula}`: si existe.
//   * `cedulas` de `TBL_CARGOS` / `TBL_AREAS`: entra al nuevo, sale del viejo.
//   * Catálogo nuevo en `TBL_AREAS`, `TBL_CARGOS`, `TBL_CENTROS_COSTOS`.

import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/multiempresa_sync.dart';
import '../core/user_directory.dart';
import '../utils/user_company.dart';

/// Todo lo que necesita la pantalla, cargado de una vez.
class MultiempresaDatos {
  final Map<String, Map<String, dynamic>> usuarios;
  final Map<String, Map<String, dynamic>> estructuras;
  final Map<String, CatalogoEmpresa> catalogos;

  /// Nombre visible de cada empresa, para los mensajes.
  final Map<String, String> nombresEmpresa;

  const MultiempresaDatos({
    required this.usuarios,
    required this.estructuras,
    required this.catalogos,
    this.nombresEmpresa = const {},
  });

  List<PersonaMultiempresa> personas() {
    final out = <PersonaMultiempresa>[];
    for (final e in usuarios.entries) {
      if (extractUserEmpresaIds(e.value).isEmpty) continue;
      out.add(
        analizarPersona(
          cedula: e.key,
          usuario: e.value,
          estructura: estructuras[e.key],
          catalogos: catalogos,
          nombresEmpresa: nombresEmpresa,
        ),
      );
    }
    return out;
  }
}

class ResultadoSincronizacion {
  final int personas;
  final int empresasTocadas;
  final int entradasCreadas;
  final List<String> errores;

  const ResultadoSincronizacion({
    this.personas = 0,
    this.empresasTocadas = 0,
    this.entradasCreadas = 0,
    this.errores = const [],
  });
}

class MultiempresaSyncService {
  final FirebaseFirestore _db;

  MultiempresaSyncService({FirebaseFirestore? db})
    : _db = db ?? FirebaseFirestore.instance;

  static const _usuarios = 'TBL_USUARIOS';
  static const _estructura = 'TBL_ESTRUCTURA_ORGANIZACIONAL';
  static const _empleados = 'TBL_EMPLEADOS';

  /// Carga usuarios, estructura y los catálogos de TODAS las empresas. La
  /// cédula es global: para ver a una persona en todas sus empresas no sirve
  /// filtrar por la activa.
  Future<MultiempresaDatos> cargar({
    Iterable<String> empresas = const [],
    Map<String, String> nombresEmpresa = const {},
  }) async {
    final res = await Future.wait([
      _db.collection(_usuarios).get(),
      _db.collection(_estructura).get(),
      _db.collection(TipoCatalogo.area.coleccion).get(),
      _db.collection(TipoCatalogo.cargo.coleccion).get(),
      _db.collection(TipoCatalogo.centro.coleccion).get(),
    ]);
    List<({String id, Map<String, dynamic> data})> docs(
      QuerySnapshot<Map<String, dynamic>> s,
    ) => [for (final d in s.docs) (id: d.id, data: d.data())];

    final estructuras = <String, Map<String, dynamic>>{};
    for (final d in res[1].docs) {
      final data = d.data();
      final cedula = (data['cedula'] ?? '').toString().trim();
      estructuras[d.id] = data;
      if (cedula.isNotEmpty) estructuras.putIfAbsent(cedula, () => data);
    }
    return MultiempresaDatos(
      nombresEmpresa: nombresEmpresa,
      usuarios: {for (final d in res[0].docs) d.id: d.data()},
      estructuras: estructuras,
      catalogos: CatalogoEmpresa.agrupar(
        empresas: empresas,
        areas: docs(res[2]),
        cargos: docs(res[3]),
        centros: docs(res[4]),
      ),
    );
  }

  /// Catálogos solo de [empresaIds]: para operaciones puntuales que no
  /// justifican leer el catálogo de todas las empresas.
  Future<Map<String, CatalogoEmpresa>> cargarCatalogos(
    Iterable<String> empresaIds,
  ) async {
    final ids = {
      for (final e in empresaIds)
        if (e.trim().isNotEmpty) e.trim(),
    }.toList();
    Future<List<({String id, Map<String, dynamic> data})>> leer(
      TipoCatalogo tipo,
    ) async {
      final out = <({String id, Map<String, dynamic> data})>[];
      for (var i = 0; i < ids.length; i += 30) {
        final chunk = ids.sublist(i, i + 30 > ids.length ? ids.length : i + 30);
        final snap = await _db
            .collection(tipo.coleccion)
            .where('empresaId', whereIn: chunk)
            .get();
        out.addAll([for (final d in snap.docs) (id: d.id, data: d.data())]);
      }
      return out;
    }

    final res = await Future.wait([
      leer(TipoCatalogo.area),
      leer(TipoCatalogo.cargo),
      leer(TipoCatalogo.centro),
    ]);
    return CatalogoEmpresa.agrupar(
      empresas: ids,
      areas: res[0],
      cargos: res[1],
      centros: res[2],
    );
  }

  /// Agrega a la persona a [empresaId] con el puesto de su empresa
  /// principal (área, cargo y centros traducidos al catálogo de la nueva
  /// empresa, creando lo que falte).
  ///
  /// Es lo que antes hacía el chip de Membresía con un bloque vacío: la
  /// persona entraba a la empresa sin cargo propio y las pantallas le
  /// mostraban el de la otra empresa.
  Future<PlanPersona> vincularPersona({
    required String cedula,
    required String empresaId,
    required String actorId,
    Map<String, String> nombresEmpresa = const {},
    CamposSincronizacion campos = const CamposSincronizacion(),
  }) async {
    final res = await Future.wait([
      _db.collection(_usuarios).doc(cedula).get(),
      _db.collection(_estructura).doc(cedula).get(),
    ]);
    final original = res[0].data();
    if (original == null) {
      throw StateError('No existe el usuario $cedula.');
    }
    final estructura = res[1].exists ? res[1].data() : null;

    // Un bloque que quedó de una membresía anterior no cuenta: se vincula de
    // nuevo con el puesto actual.
    final detalle = Map<String, dynamic>.from(
      (original['empresasDetalle'] as Map?) ?? const {},
    )..remove(empresaId);
    final usuario = <String, dynamic>{
      ...original,
      'empresas': [
        for (final e in (original['empresas'] as List?) ?? const [])
          if (e.toString().trim() != empresaId) e.toString().trim(),
      ],
      'empresasDetalle': detalle,
    };

    final empresas = {...extractUserEmpresaIds(usuario), empresaId};
    final catalogos = await cargarCatalogos(empresas);
    final persona = analizarPersona(
      cedula: cedula,
      usuario: usuario,
      estructura: estructura,
      catalogos: catalogos,
      nombresEmpresa: nombresEmpresa,
    );
    final referencia = persona.referenciaSugerida;
    if (referencia == null) {
      // Sin ninguna empresa previa no hay puesto que llevar.
      await _db.collection(_usuarios).doc(cedula).set({
        'empresas': FieldValue.arrayUnion([empresaId]),
        'empresasDetalle': {
          empresaId: {
            'empresaNombre': nombresEmpresa[empresaId] ?? empresaId,
            'activo': true,
            'vinculadoAt': FieldValue.serverTimestamp(),
          },
        },
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      UserDirectory.instance.invalidate(cedula);
      return PlanPersona(
        cedula: cedula,
        referenciaId: empresaId,
        ajustes: const [],
        nuevas: const [],
        avisos: const ['Sin empresa previa: se agregó sin puesto.'],
      );
    }
    final plan = planearSincronizacion(
      persona: persona,
      usuario: usuario,
      estructura: estructura,
      referenciaId: referencia,
      destinos: {empresaId},
      catalogos: catalogos,
      campos: campos,
      nombresEmpresa: nombresEmpresa,
    );
    await aplicarPlan(
      plan: plan,
      usuario: usuario,
      estructura: estructura,
      actorId: actorId,
      accion: 'multiempresaVincularPersona',
    );
    return plan;
  }

  Map<String, dynamic> _datosEntrada(EntradaNueva n, String actorId) => {
    ...n.datos,
    'creadoPorSincronizacion': actorId,
    'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  };

  /// Crea en el destino las áreas, cargos y centros del plan. No toca a
  /// ninguna persona.
  Future<int> enviarCatalogo(
    PlanCatalogo plan, {
    required String actorId,
  }) async {
    var batch = _db.batch();
    var writes = 0;
    for (final n in plan.nuevas) {
      batch.set(
        _db.collection(n.tipo.coleccion).doc(n.id),
        _datosEntrada(n, actorId),
        SetOptions(merge: true),
      );
      writes++;
      if (writes >= 400) {
        await batch.commit();
        batch = _db.batch();
        writes = 0;
      }
    }
    if (writes > 0) await batch.commit();
    await _log(
      actorId: actorId,
      action: 'multiempresaEnviarCatalogo',
      empresaId: plan.origenId,
      extra: {
        'destino': plan.destinoId,
        'areas': plan.de(TipoCatalogo.area).length,
        'cargos': plan.de(TipoCatalogo.cargo).length,
        'centros': plan.de(TipoCatalogo.centro).length,
        'yaExistian': plan.yaExistian,
      },
    );
    return plan.nuevas.length;
  }

  /// Aplica el plan de UNA persona en un solo lote: o queda todo o nada.
  Future<void> aplicarPlan({
    required PlanPersona plan,
    required Map<String, dynamic> usuario,
    Map<String, dynamic>? estructura,
    required String actorId,
    String accion = 'multiempresaSincronizarPersona',
    bool crearCatalogo = true,

    /// Campos adicionales con punto para `TBL_USUARIOS` y para la
    /// estructura (traslados: activar/apagar empresas, empresa principal).
    /// [kAhora] y [kBorrar] se traducen aquí.
    Map<String, Object?> extraUsuario = const {},
    Map<String, Object?> extraEstructura = const {},
    Map<String, Object?> extraLog = const {},
  }) async {
    if (plan.vacio && extraUsuario.isEmpty && extraEstructura.isEmpty) return;
    final cedula = plan.cedula;
    final principal = normalizeEmpresaId(usuario['empresaId']?.toString());
    final orgPrincipal = normalizeEmpresaId(
      estructura?['empresaId']?.toString(),
    );

    // Lecturas antes del lote: el espejo de TBL_EMPLEADOS solo se toca si
    // existe, y al vincular se parte del de la empresa de referencia.
    final empleados = <String, DocumentSnapshot<Map<String, dynamic>>>{};
    for (final id in {
      for (final a in plan.ajustes)
        if (a.empleado.isNotEmpty || a.vincular) a.empresaId,
      if (plan.ajustes.any((a) => a.vincular)) plan.referenciaId,
    }) {
      empleados[id] = await _db
          .collection(_empleados)
          .doc('${id}_$cedula')
          .get();
    }

    final batch = _db.batch();
    for (final n in crearCatalogo ? plan.nuevas : const <EntradaNueva>[]) {
      batch.set(
        _db.collection(n.tipo.coleccion).doc(n.id),
        _datosEntrada(n, actorId),
        SetOptions(merge: true),
      );
    }

    final userUpdate = <String, Object?>{
      'updatedAt': FieldValue.serverTimestamp(),
    };
    final orgUpdate = <String, Object?>{};
    final vinculadas = <String>[];

    for (final a in plan.ajustes) {
      if (a.vacio) continue;
      final e = a.empresaId;
      a.usuario.forEach((k, v) {
        userUpdate['empresasDetalle.$e.$k'] = v;
        // `activo` en la raíz es el interruptor global de Admin y
        // `empresaNombre` raíz es el de la principal: nunca se pisan aquí.
        if (e == principal && k != 'activo' && k != 'empresaNombre') {
          userUpdate[k] = v;
        }
      });
      if (a.vincular) {
        vinculadas.add(e);
        userUpdate['empresasDetalle.$e.vinculadoAt'] =
            FieldValue.serverTimestamp();
        userUpdate['empresasDetalle.$e.vinculadoPor'] = actorId;
      }

      if (estructura != null && a.estructura.isNotEmpty) {
        a.estructura.forEach((k, v) {
          orgUpdate['empresasDetalle.$e.$k'] = v;
          if (e == orgPrincipal) orgUpdate[k] = v;
        });
      }

      final empleado = empleados[e];
      if (empleado != null && empleado.exists && a.empleado.isNotEmpty) {
        batch.set(empleado.reference, {
          ...a.empleado,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } else if (a.vincular) {
        final base = empleados[plan.referenciaId];
        if (base != null && base.exists) {
          batch.set(_db.collection(_empleados).doc('${e}_$cedula'), {
            ...?base.data(),
            ...a.empleado,
            'empresaId': e,
            'empresaNombre': a.usuario['empresaNombre'] ?? e,
            'empresaOrigenId': plan.referenciaId,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      }

      for (final m in a.cedulas) {
        batch.set(_db.collection(m.coleccion).doc(m.docId), {
          'cedulas': m.agregar
              ? FieldValue.arrayUnion([cedula])
              : FieldValue.arrayRemove([cedula]),
        }, SetOptions(merge: true));
      }
    }

    if (vinculadas.isNotEmpty) {
      userUpdate['empresas'] = FieldValue.arrayUnion(vinculadas);
    }
    // Módulos de las empresas nuevas; las que ya tenía conservan los suyos.
    final modulos = <String, List<String>>{
      for (final a in plan.ajustes)
        if (a.modulos != null) a.empresaId: a.modulos!,
    };
    if (modulos.isNotEmpty) {
      userUpdate.addAll(
        planearAppsPorEmpresa(usuario, cambios: modulos).comoRutas(),
      );
    }
    Object? traducir(Object? v) => identical(v, kAhora)
        ? FieldValue.serverTimestamp()
        : identical(v, kBorrar)
        ? FieldValue.delete()
        : v;
    extraUsuario.forEach((k, v) => userUpdate[k] = traducir(v));
    if (estructura != null) {
      extraEstructura.forEach((k, v) => orgUpdate[k] = traducir(v));
    }
    batch.update(_db.collection(_usuarios).doc(cedula), userUpdate);

    if (estructura != null && (orgUpdate.isNotEmpty || vinculadas.isNotEmpty)) {
      if (vinculadas.isNotEmpty) {
        orgUpdate['empresas'] = FieldValue.arrayUnion(vinculadas);
      }
      orgUpdate['updatedAt'] = FieldValue.serverTimestamp();
      batch.update(_db.collection(_estructura).doc(cedula), orgUpdate);
    }

    batch.set(_db.collection('TBL_MIGRATIONS_LOGS').doc(), {
      'adminUserId': actorId,
      'empresaId': plan.referenciaId,
      'action': accion,
      'scanned': 1,
      'updated': 1,
      'dryRun': false,
      'extra': {
        'cedula': cedula,
        'referencia': plan.referenciaId,
        'empresas': [
          for (final a in plan.ajustes)
            if (!a.vacio) a.empresaId,
        ],
        'vinculadas': vinculadas,
        'catalogoCreado': [for (final n in plan.nuevas) n.id],
        ...extraLog,
      },
      'createdAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
    UserDirectory.instance.invalidate(cedula);
  }

  /// Sincroniza varias personas, una por lote. Si una falla, las demás
  /// siguen y el error queda en el resultado.
  Future<ResultadoSincronizacion> aplicarPlanes({
    required List<PlanPersona> planes,
    required MultiempresaDatos datos,
    required String actorId,
    String accion = 'multiempresaSincronizarPersona',
    void Function(int hechas, int total)? onProgreso,
  }) async {
    var personas = 0;
    var empresas = 0;
    var creadas = 0;
    final errores = <String>[];
    final pendientes = planes.where((p) => !p.vacio).toList();

    // El catálogo nuevo va primero y completo: los planes se armaron en
    // cadena y una persona puede usar el cargo que "creó" la anterior. Si esa
    // anterior fallara, la siguiente quedaría apuntando a un cargo que no
    // existe.
    final nuevas = <String, EntradaNueva>{
      for (final p in pendientes)
        for (final n in p.nuevas) '${n.tipo.coleccion}/${n.id}': n,
    };
    if (nuevas.isNotEmpty) {
      await enviarCatalogo(
        PlanCatalogo(
          origenId: pendientes.first.referenciaId,
          destinoId: {for (final n in nuevas.values) n.empresaId}.join(','),
          nuevas: nuevas.values.toList(),
          yaExistian: 0,
          cargosConAreaDistinta: const [],
        ),
        actorId: actorId,
      );
      creadas = nuevas.length;
    }

    for (var i = 0; i < pendientes.length; i++) {
      final plan = pendientes[i];
      try {
        await aplicarPlan(
          plan: plan,
          usuario: datos.usuarios[plan.cedula] ?? const {},
          estructura: datos.estructuras[plan.cedula],
          actorId: actorId,
          accion: accion,
          crearCatalogo: false,
        );
        personas++;
        empresas += plan.ajustes.where((a) => !a.vacio).length;
      } catch (e) {
        errores.add('${plan.cedula}: $e');
      }
      onProgreso?.call(i + 1, pendientes.length);
    }
    return ResultadoSincronizacion(
      personas: personas,
      empresasTocadas: empresas,
      entradasCreadas: creadas,
      errores: errores,
    );
  }

  /// Aplica traslados, una persona por lote (todo o nada por persona). El
  /// catálogo que haga falta en la empresa nueva se crea primero y completo.
  Future<ResultadoSincronizacion> aplicarTraslados({
    required List<PlanTraslado> planes,
    required MultiempresaDatos datos,
    required String actorId,
    required String origenId,
    required String destinoId,
    void Function(int hechas, int total)? onProgreso,
  }) async {
    final pendientes = planes.where((p) => !p.vacio).toList();
    final nuevas = <String, EntradaNueva>{
      for (final p in pendientes)
        for (final n in p.puesto.nuevas) '${n.tipo.coleccion}/${n.id}': n,
    };
    if (nuevas.isNotEmpty) {
      await enviarCatalogo(
        PlanCatalogo(
          origenId: origenId,
          destinoId: destinoId,
          nuevas: nuevas.values.toList(),
          yaExistian: 0,
          cargosConAreaDistinta: const [],
        ),
        actorId: actorId,
      );
    }
    var personas = 0;
    final errores = <String>[];
    for (var i = 0; i < pendientes.length; i++) {
      final plan = pendientes[i];
      try {
        await aplicarPlan(
          plan: plan.puesto,
          usuario: datos.usuarios[plan.cedula] ?? const {},
          estructura: datos.estructuras[plan.cedula],
          actorId: actorId,
          accion: 'multiempresaTraslado',
          crearCatalogo: false,
          extraUsuario: plan.usuario,
          extraEstructura: plan.estructura,
          extraLog: {
            'origen': origenId,
            'destino': destinoId,
            'decision': plan.decision.name,
            if (plan.nuevaPrincipal != null)
              'nuevaPrincipal': plan.nuevaPrincipal,
          },
        );
        personas++;
      } catch (e) {
        errores.add('${plan.cedula}: $e');
      }
      onProgreso?.call(i + 1, pendientes.length);
    }
    return ResultadoSincronizacion(
      personas: personas,
      empresasTocadas: personas,
      entradasCreadas: nuevas.length,
      errores: errores,
    );
  }

  /// Fija los módulos por empresa de [cedulas]: cada empresa queda con lo
  /// que la persona ve hoy en ella (o, con [quitarHeredadas], sin lo que solo
  /// veía por la lista general de otra empresa) y la persona pasa a la regla
  /// de módulos por empresa. Devuelve cuántas personas se escribieron.
  Future<int> fijarModulos({
    required MultiempresaDatos datos,
    required Iterable<String> cedulas,
    required String actorId,
    bool quitarHeredadas = false,
    void Function(int hechas, int total)? onProgreso,
  }) async {
    final lista = cedulas.where(datos.usuarios.containsKey).toList();
    var batch = _db.batch();
    var writes = 0;
    var hechas = 0;
    for (final cedula in lista) {
      final plan = planearAppsPorEmpresa(
        datos.usuarios[cedula]!,
        quitarHeredadas: quitarHeredadas,
      );
      if (plan.porEmpresa.isEmpty) continue;
      batch.update(_db.collection(_usuarios).doc(cedula), {
        ...plan.comoRutas(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      writes++;
      hechas++;
      if (writes >= 400) {
        await batch.commit();
        batch = _db.batch();
        writes = 0;
        onProgreso?.call(hechas, lista.length);
      }
    }
    if (writes > 0) await batch.commit();
    onProgreso?.call(hechas, lista.length);
    for (final cedula in lista) {
      UserDirectory.instance.invalidate(cedula);
    }
    await _log(
      actorId: actorId,
      action: 'multiempresaFijarModulos',
      empresaId: '*',
      extra: {'personas': hechas, 'quitarHeredadas': quitarHeredadas},
    );
    return hechas;
  }

  /// Guarda los módulos de una persona en cada una de sus empresas.
  Future<void> guardarModulos({
    required String cedula,
    required Map<String, dynamic> usuario,
    required Map<String, Set<String>> porEmpresa,
    required String actorId,
  }) async {
    final plan = planearAppsPorEmpresa(usuario, cambios: porEmpresa);
    await _db.collection(_usuarios).doc(cedula).update({
      ...plan.comoRutas(),
      'accesosActualizadoPor': actorId,
      'accesosActualizadoAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    UserDirectory.instance.invalidate(cedula);
  }

  Future<void> _log({
    required String actorId,
    required String action,
    required String empresaId,
    Map<String, dynamic> extra = const {},
  }) => _db.collection('TBL_MIGRATIONS_LOGS').add({
    'adminUserId': actorId,
    'empresaId': empresaId,
    'action': action,
    'scanned': 0,
    'updated': 0,
    'dryRun': false,
    'extra': extra,
    'createdAt': FieldValue.serverTimestamp(),
  });
}
