import 'package:flutter_test/flutter_test.dart';
import 'package:todo/core/multiempresa_sync.dart';

const _a = 'EMPRESA_001';
const _b = 'EMPRESA_002';
const _c = 'EMPRESA_003';

typedef _Doc = ({String id, Map<String, dynamic> data});

_Doc _area(String empresa, String slug, String nombre) =>
    (id: '${empresa}_$slug', data: {'empresaId': empresa, 'nombre': nombre});

_Doc _cargo(
  String empresa,
  String slug,
  String nombre, {
  String areaSlug = '',
  String areaNombre = '',
  String parent = '',
}) => (
  id: '${empresa}_$slug',
  data: {
    'empresaId': empresa,
    'nombre': nombre,
    if (areaSlug.isNotEmpty) 'areaId': '${empresa}_$areaSlug',
    if (areaNombre.isNotEmpty) 'areaNombre': areaNombre,
    if (parent.isNotEmpty) 'parent_cargo': '${empresa}_$parent',
    'descripcion': 'Descripción de $nombre',
    'cedulas': ['111'],
  },
);

_Doc _centro(String empresa, String codigo, String nombre) => (
  id: '${empresa}_$codigo',
  data: {'empresaId': empresa, 'codigo': codigo, 'nombre': nombre},
);

Map<String, CatalogoEmpresa> _catalogos({bool bCompleto = true}) =>
    CatalogoEmpresa.agrupar(
      empresas: const [_a, _b, _c],
      areas: [
        _area(_a, 'cocina', 'Cocina'),
        _area(_a, 'talento_humano', 'Talento Humano'),
        if (bCompleto) _area(_b, 'cocina', 'Cocina'),
      ],
      cargos: [
        _cargo(_a, 'jefe_cocina', 'Jefe de Cocina', areaSlug: 'cocina'),
        _cargo(
          _a,
          'auxiliar_cocina',
          'Auxiliar de Cocina',
          areaSlug: 'cocina',
          areaNombre: 'Cocina',
          parent: 'jefe_cocina',
        ),
        _cargo(_a, 'analista_th', 'Analista de Talento Humano'),
        if (bCompleto) ...[
          _cargo(_b, 'auxiliar_cocina', 'Auxiliar de cocina'),
          _cargo(_b, 'coordinador', 'Coordinador'),
        ],
      ],
      centros: [
        _centro(_a, '1003', 'Bodega Cota'),
        _centro(_a, '2001', 'Cómbita'),
        if (bCompleto) _centro(_b, '2001', 'Cómbita'),
      ],
    );

Map<String, dynamic> _usuario({
  Map<String, dynamic> raiz = const {},
  Map<String, Map<String, dynamic>> detalle = const {},
  List<String> empresas = const [_a, _b],
}) => {
  'empresaId': _a,
  'empresas': empresas,
  // La raíz es la copia de la empresa principal.
  ..._bloqueA(),
  ...raiz,
  'empresasDetalle': detalle,
};

Map<String, dynamic> _bloqueA() => {
  'cargoId': '${_a}_auxiliar_cocina',
  'cargo': 'Auxiliar de Cocina',
  'areaId': '${_a}_cocina',
  'area': 'Cocina',
  'centroId': '${_a}_2001',
  'centroCostos': 'Cómbita',
  'centrosOperacionIds': ['${_a}_2001'],
  'centrosOperacionNombres': ['Cómbita'],
};

Map<String, dynamic> _bloqueBSano() => {
  'cargoId': '${_b}_auxiliar_cocina',
  'cargo': 'Auxiliar de cocina',
  'areaId': '${_b}_cocina',
  'area': 'Cocina',
  'centroId': '${_b}_2001',
  'centroCostos': 'Cómbita',
  'centrosOperacionIds': ['${_b}_2001'],
  'centrosOperacionNombres': ['Cómbita'],
};

Set<TipoDescuadre> _tipos(PersonaMultiempresa p, {String? empresa}) => {
  for (final d in p.descuadres)
    if (empresa == null || d.empresaId == empresa) d.tipo,
};

/// Aplica un plan sobre los mapas en memoria, como lo haría el servicio.
Map<String, dynamic> _aplicar(Map<String, dynamic> usuario, PlanPersona plan) {
  final out = Map<String, dynamic>.from(usuario);
  final detalle = Map<String, dynamic>.from(
    (out['empresasDetalle'] as Map?) ?? const {},
  );
  final empresas = List<String>.from((out['empresas'] as List?) ?? const []);
  for (final a in plan.ajustes) {
    final bloque = Map<String, dynamic>.from(
      (detalle[a.empresaId] as Map?) ?? const {},
    )..addAll(a.usuario);
    detalle[a.empresaId] = bloque;
    if (a.vincular && !empresas.contains(a.empresaId)) {
      empresas.add(a.empresaId);
    }
    if (out['empresaId'] == a.empresaId) out.addAll(a.usuario);
  }
  out['empresasDetalle'] = detalle;
  out['empresas'] = empresas;
  return out;
}

void main() {
  group('idCatalogo', () {
    test('usa la forma {empresa}_{slug} sin tildes', () {
      expect(idCatalogo(_b, 'Gestión Humana'), '${_b}_gestion_humana');
      expect(
        idCatalogo(_b, '  Auxiliar  de Cocina '),
        '${_b}_auxiliar_de_cocina',
      );
    });

    test('no repite un id ocupado', () {
      final cat = _catalogos()[_b]!;
      expect(
        cat.idLibre(TipoCatalogo.cargo, 'Coordinador'),
        '${_b}_coordinador_2',
      );
    });
  });

  group('CatalogoEmpresa', () {
    test('encuentra por nombre sin importar tildes ni mayúsculas', () {
      final cat = _catalogos()[_b]!;
      expect(
        cat.porNombre(TipoCatalogo.cargo, 'AUXILIAR DE COCINA')?.id,
        '${_b}_auxiliar_cocina',
      );
      expect(cat.porNombre(TipoCatalogo.centro, 'combita')?.id, '${_b}_2001');
    });

    test('los centros también se reconocen por código', () {
      final cat = _catalogos()[_b]!;
      expect(
        cat.porNombre(TipoCatalogo.centro, 'Otro nombre', codigo: '2001')?.id,
        '${_b}_2001',
      );
    });
  });

  group('analizarPersona', () {
    test('persona bien sincronizada no tiene descuadres', () {
      final p = analizarPersona(
        cedula: '111',
        usuario: _usuario(detalle: {_a: _bloqueA(), _b: _bloqueBSano()}),
        catalogos: _catalogos(),
      );
      expect(p.esMultiempresa, isTrue);
      expect(p.descuadres, isEmpty);
      expect(p.puesto(_b)!.cargo.nombre, 'Auxiliar de cocina');
    });

    test('bloque vacío en la otra empresa: ve el cargo de la principal', () {
      final p = analizarPersona(
        cedula: '111',
        usuario: _usuario(detalle: {_a: _bloqueA(), _b: {}}),
        catalogos: _catalogos(),
      );
      expect(_tipos(p, empresa: _b), contains(TipoDescuadre.heredado));
      expect(_tipos(p, empresa: _a), isEmpty);
    });

    test('id de cargo de otra empresa', () {
      final bloque = _bloqueBSano()
        ..['cargoId'] = '${_a}_jefe_cocina'
        ..['cargo'] = 'Jefe de Cocina';
      final p = analizarPersona(
        cedula: '111',
        usuario: _usuario(detalle: {_a: _bloqueA(), _b: bloque}),
        catalogos: _catalogos(),
      );
      expect(_tipos(p, empresa: _b), contains(TipoDescuadre.deOtraEmpresa));
      // Y como el cargo visible difiere entre empresas, también se señala.
      expect(_tipos(p), contains(TipoDescuadre.cargoDistinto));
    });

    test('cargo distinto entre empresas activas', () {
      final bloque = _bloqueBSano()
        ..['cargoId'] = '${_b}_coordinador'
        ..['cargo'] = 'Coordinador';
      final p = analizarPersona(
        cedula: '111',
        usuario: _usuario(detalle: {_a: _bloqueA(), _b: bloque}),
        catalogos: _catalogos(),
      );
      final distinto = p.descuadres.singleWhere(
        (d) => d.tipo == TipoDescuadre.cargoDistinto,
      );
      expect(distinto.detalle, contains('Coordinador'));
      expect(distinto.detalle, contains('Auxiliar de Cocina'));
    });

    test('empresa apagada no cuenta como descuadre', () {
      final bloque = {
        ..._bloqueBSano(),
        'cargoId': '${_b}_coordinador',
        'cargo': 'Coordinador',
        'activo': false,
      };
      final p = analizarPersona(
        cedula: '111',
        usuario: _usuario(detalle: {_a: _bloqueA(), _b: bloque}),
        catalogos: _catalogos(),
      );
      expect(p.puesto(_b)!.estado, EstadoMembresia.apagada);
      expect(p.descuadres, isEmpty);
      expect(p.esMultiempresa, isFalse);
    });

    test('nombre en el catálogo pero sin su id: sin enlace', () {
      final bloque = _bloqueBSano()..remove('cargoId');
      final p = analizarPersona(
        cedula: '111',
        usuario: _usuario(
          raiz: const {'empresaId': _b},
          detalle: {_a: _bloqueA(), _b: bloque},
        ),
        catalogos: _catalogos(),
      );
      // La raíz es de B, así que el cargoId raíz (de A) sí se lee para B…
      // y es de otra empresa.
      expect(_tipos(p, empresa: _b), contains(TipoDescuadre.deOtraEmpresa));
    });

    test('cargo renombrado en el catálogo: nombre desactualizado', () {
      final cats = CatalogoEmpresa.agrupar(
        empresas: const [_a],
        areas: [_area(_a, 'cocina', 'Cocina')],
        cargos: [_cargo(_a, 'auxiliar_cocina', 'Auxiliar de Producción')],
        centros: [_centro(_a, '2001', 'Cómbita')],
      );
      final p = analizarPersona(
        cedula: '111',
        usuario: _usuario(
          empresas: const [_a],
          detalle: {
            _a: {
              'cargoId': '${_a}_auxiliar_cocina',
              'cargo': 'Auxiliar de Cocina',
              'areaId': '${_a}_cocina',
              'area': 'Cocina',
            },
          },
        ),
        catalogos: cats,
      );
      expect(p.descuadres.single.tipo, TipoDescuadre.nombreDesactualizado);
      expect(p.puesto(_a)!.cargo.nombre, 'Auxiliar de Producción');
    });

    test('área guardada con el nombre en el campo del id', () {
      final bloque = _bloqueBSano()
        ..['areaId'] = 'Cocina'
        ..remove('area');
      final p = analizarPersona(
        cedula: '111',
        // Sin área en la raíz, para que no se lea la de la principal.
        usuario: _usuario(
          raiz: const {'area': '', 'areaId': ''},
          detalle: {_a: _bloqueA(), _b: bloque},
        ),
        catalogos: _catalogos(),
      );
      final area = p.puesto(_b)!.area;
      expect(area.entrada?.id, '${_b}_cocina');
      expect(area.problema, ProblemaValor.sinEnlace);
    });

    test('centro de operación de otra empresa', () {
      final bloque = _bloqueBSano()
        ..['centrosOperacionIds'] = ['${_a}_1003']
        ..['centrosOperacionNombres'] = ['Bodega Cota'];
      final p = analizarPersona(
        cedula: '111',
        usuario: _usuario(detalle: {_a: _bloqueA(), _b: bloque}),
        catalogos: _catalogos(),
      );
      final d = p.descuadres.singleWhere((d) => d.empresaId == _b);
      expect(d.tipo, TipoDescuadre.deOtraEmpresa);
      expect(d.detalle, contains('Centro de operación'));
    });

    test('raíz pisada con el cargo de otra empresa', () {
      final usuario = _usuario(
        raiz: const {'cargo': 'Coordinador', 'cargoId': '${_b}_coordinador'},
        detalle: {_a: _bloqueA(), _b: _bloqueBSano()},
      );
      final p = analizarPersona(
        cedula: '111',
        usuario: usuario,
        catalogos: _catalogos(),
      );
      expect(_tipos(p, empresa: _a), {TipoDescuadre.raizDesalineada});
      // Sincronizar con la principal de referencia repara la raíz.
      final plan = planearSincronizacion(
        persona: p,
        usuario: usuario,
        referenciaId: _a,
        destinos: const [_a, _b],
        catalogos: _catalogos(),
      );
      final despues = analizarPersona(
        cedula: '111',
        usuario: _aplicar(usuario, plan),
        catalogos: _catalogos(),
      );
      expect(despues.descuadres, isEmpty);
      expect(_aplicar(usuario, plan)['cargo'], 'Auxiliar de Cocina');
    });

    test('estructura organizacional con otro cargo', () {
      final p = analizarPersona(
        cedula: '111',
        usuario: _usuario(detalle: {_a: _bloqueA(), _b: _bloqueBSano()}),
        estructura: {
          'empresaId': _a,
          'empresasDetalle': {
            _b: {'cargo': 'Coordinador', 'area': 'Cocina'},
          },
        },
        catalogos: _catalogos(),
      );
      expect(
        _tipos(p, empresa: _b),
        contains(TipoDescuadre.estructuraDesalineada),
      );
    });
  });

  group('planearSincronizacion', () {
    test('iguala B a la principal y deja a la persona sin descuadres', () {
      final cats = _catalogos();
      final usuario = _usuario(
        detalle: {
          _a: _bloqueA(),
          _b: {'cargoId': '${_a}_jefe_cocina', 'cargo': 'Jefe de Cocina'},
        },
      );
      final persona = analizarPersona(
        cedula: '111',
        usuario: usuario,
        catalogos: cats,
      );
      expect(persona.sincronizada, isFalse);

      final plan = planearSincronizacion(
        persona: persona,
        usuario: usuario,
        referenciaId: _a,
        destinos: const [_a, _b],
        catalogos: cats,
      );
      final ajusteB = plan.ajustes.singleWhere((a) => a.empresaId == _b);
      expect(ajusteB.usuario['cargoId'], '${_b}_auxiliar_cocina');
      expect(ajusteB.usuario['cargo'], 'Auxiliar de cocina');
      expect(ajusteB.usuario['areaId'], '${_b}_cocina');
      expect(ajusteB.usuario['centroId'], '${_b}_2001');
      expect(ajusteB.usuario['centrosOperacionIds'], ['${_b}_2001']);
      // B ya tenía todo en su catálogo: no se crea nada.
      expect(plan.nuevas, isEmpty);
      // La referencia ya estaba bien: no se le escribe nada.
      expect(plan.ajustes.singleWhere((a) => a.empresaId == _a).vacio, isTrue);

      final despues = analizarPersona(
        cedula: '111',
        usuario: _aplicar(usuario, plan),
        catalogos: cats,
      );
      expect(despues.descuadres, isEmpty);
    });

    test('crea en el destino el cargo, su área y el centro que falten', () {
      final cats = _catalogos(bCompleto: false);
      final usuario = _usuario(detalle: {_a: _bloqueA(), _b: {}});
      final persona = analizarPersona(
        cedula: '111',
        usuario: usuario,
        catalogos: cats,
      );
      final plan = planearSincronizacion(
        persona: persona,
        usuario: usuario,
        referenciaId: _a,
        destinos: const [_b],
        catalogos: cats,
      );
      final nuevas = {for (final n in plan.nuevas) '${n.tipo.name}:${n.id}': n};
      expect(
        nuevas.keys,
        containsAll([
          'area:${_b}_cocina',
          'cargo:${_b}_auxiliar_de_cocina',
          'centro:${_b}_2001',
        ]),
      );
      final cargo = nuevas['cargo:${_b}_auxiliar_de_cocina']!.datos;
      expect(cargo['empresaId'], _b);
      expect(cargo['areaId'], '${_b}_cocina');
      expect(cargo['descripcion'], 'Descripción de Auxiliar de Cocina');
      expect(cargo.containsKey('cedulas'), isFalse);
      // El jefe no existe en B: no se arrastra la cadena de mando.
      expect(cargo.containsKey('parent_cargo'), isFalse);
      expect(cargo['registroOrigenId'], '${_a}_auxiliar_cocina');

      final ajuste = plan.ajustes.single;
      expect(
        ajuste.cedulas.map((m) => '${m.coleccion}/${m.docId}/${m.agregar}'),
        containsAll([
          'TBL_CARGOS/${_b}_auxiliar_de_cocina/true',
          'TBL_AREAS/${_b}_cocina/true',
        ]),
      );

      final despues = analizarPersona(
        cedula: '111',
        usuario: _aplicar(usuario, plan),
        catalogos: cats,
      );
      expect(despues.descuadres, isEmpty);
    });

    test('dos personas con el mismo cargo nuevo no lo crean dos veces', () {
      final cats = _catalogos(bCompleto: false);
      for (final cedula in ['111', '222']) {
        final usuario = _usuario(detalle: {_a: _bloqueA(), _b: {}});
        final persona = analizarPersona(
          cedula: cedula,
          usuario: usuario,
          catalogos: cats,
        );
        final plan = planearSincronizacion(
          persona: persona,
          usuario: usuario,
          referenciaId: _a,
          destinos: const [_b],
          catalogos: cats,
        );
        expect(
          plan.nuevas.where((n) => n.tipo == TipoCatalogo.cargo).length,
          cedula == '111' ? 1 : 0,
        );
      }
    });

    test('vincula a una empresa nueva con su cargo y área', () {
      final cats = _catalogos();
      final usuario = _usuario(empresas: const [_a], detalle: {_a: _bloqueA()});
      final persona = analizarPersona(
        cedula: '111',
        usuario: usuario,
        catalogos: cats,
      );
      final plan = planearSincronizacion(
        persona: persona,
        usuario: usuario,
        referenciaId: _a,
        destinos: const [_c],
        catalogos: cats,
        nombresEmpresa: const {_c: 'Empresa Tres'},
        campos: const CamposSincronizacion(centros: false),
      );
      final ajuste = plan.ajustes.single;
      expect(ajuste.vincular, isTrue);
      expect(ajuste.usuario['empresaNombre'], 'Empresa Tres');
      expect(ajuste.usuario['activo'], isTrue);
      expect(ajuste.usuario['cargoId'], '${_c}_auxiliar_de_cocina');
      // Sin centros: quedan escritos en vacío para no heredar los de A.
      expect(ajuste.usuario['centroId'], '');
      expect(ajuste.usuario['centrosOperacionIds'], isEmpty);

      final despues = analizarPersona(
        cedula: '111',
        usuario: _aplicar(usuario, plan),
        catalogos: cats,
      );
      expect(despues.empresaIds, [_a, _c]);
      expect(despues.descuadres, isEmpty);
    });

    test('una referencia sin cargo no borra el cargo del destino', () {
      final cats = _catalogos();
      final bloqueA = _bloqueA()
        ..remove('cargoId')
        ..remove('cargo');
      final usuario = _usuario(
        raiz: const {'cargo': '', 'cargoId': ''},
        detalle: {_a: bloqueA, _b: _bloqueBSano()},
      );
      final persona = analizarPersona(
        cedula: '111',
        usuario: usuario,
        catalogos: cats,
      );
      final plan = planearSincronizacion(
        persona: persona,
        usuario: usuario,
        referenciaId: _a,
        destinos: const [_b],
        catalogos: cats,
      );
      expect(plan.avisos.single, contains('no tiene cargo'));
      expect(plan.ajustes.single.usuario.containsKey('cargo'), isFalse);
    });

    test('también alinea la estructura organizacional', () {
      final cats = _catalogos();
      final usuario = _usuario(detalle: {_a: _bloqueA(), _b: _bloqueBSano()});
      final estructura = {
        'empresaId': _a,
        'empresasDetalle': {
          _b: {'cargo': 'Coordinador', 'cargoId': '${_b}_coordinador'},
        },
      };
      final persona = analizarPersona(
        cedula: '111',
        usuario: usuario,
        estructura: estructura,
        catalogos: cats,
      );
      final plan = planearSincronizacion(
        persona: persona,
        usuario: usuario,
        estructura: estructura,
        referenciaId: _a,
        destinos: const [_b],
        catalogos: cats,
      );
      final ajuste = plan.ajustes.single;
      expect(ajuste.usuario, isEmpty);
      expect(ajuste.estructura['cargo'], 'Auxiliar de cocina');
      expect(ajuste.estructura['cargoId'], '${_b}_auxiliar_cocina');
    });
  });

  group('planearEnvioCatalogo', () {
    test('envía solo lo que falta y enlaza cargos con su área', () {
      final cats = _catalogos();
      final plan = planearEnvioCatalogo(
        origenId: _a,
        destinoId: _b,
        catalogos: cats,
        tipos: TipoCatalogo.values.toSet(),
      );
      final nombres = {
        for (final n in plan.nuevas) '${n.tipo.name}:${n.nombre}',
      };
      expect(nombres, {
        'area:Talento Humano',
        'centro:Bodega Cota',
        'cargo:Jefe de Cocina',
        'cargo:Analista de Talento Humano',
      });
      // Cocina, Cómbita y Auxiliar de cocina ya estaban.
      expect(plan.yaExistian, 3);
      final jefe = plan.nuevas.singleWhere((n) => n.nombre == 'Jefe de Cocina');
      expect(jefe.datos['areaId'], '${_b}_cocina');
      expect(jefe.id, '${_b}_jefe_de_cocina');
      final centro = plan.nuevas.singleWhere(
        (n) => n.tipo == TipoCatalogo.centro,
      );
      expect(centro.id, '${_b}_1003');
      expect(centro.datos['codigo'], '1003');
    });

    test('a una empresa vacía le llega el catálogo completo', () {
      final cats = _catalogos();
      final plan = planearEnvioCatalogo(
        origenId: _a,
        destinoId: _c,
        catalogos: cats,
      );
      expect(plan.de(TipoCatalogo.area).length, 2);
      expect(plan.de(TipoCatalogo.cargo).length, 3);
      expect(plan.de(TipoCatalogo.centro), isEmpty);
      // El jefe se creó en el mismo envío, así que el auxiliar lo enlaza.
      final aux = plan.nuevas.singleWhere(
        (n) => n.nombre == 'Auxiliar de Cocina',
      );
      expect(aux.datos['parent_cargo'], '${_c}_jefe_de_cocina');
    });

    test('solo los cargos elegidos, con su área', () {
      final cats = _catalogos();
      final plan = planearEnvioCatalogo(
        origenId: _a,
        destinoId: _c,
        catalogos: cats,
        tipos: const {TipoCatalogo.cargo},
        ids: const {'${_a}_analista_th'},
      );
      expect(plan.nuevas.map((n) => n.nombre), ['Analista de Talento Humano']);
    });
  });
}
