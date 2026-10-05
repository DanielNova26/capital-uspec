const test = require('node:test');
const assert = require('node:assert/strict');
const {
  MODULOS_MAESTROS,
  camposFaltantes,
  cargosFaltantesEnReglas,
  claveDe,
  codigoLibre,
  idCatalogo,
  idDestino,
  mapearCatalogo,
  normalizarClave,
  numeroDeCodigo,
  pareceId,
  remapear,
  rutaDestino,
} = require('../lib/maestros');
const {MODULOS_LIMPIEZA} = require('../lib/limpieza');

const ctx = (mapa = {}, pendientes = {}) => ({
  origen: 'EMP_A',
  destino: 'EMP_B',
  mapa: new Map(Object.entries(mapa)),
  pendientes: new Map(Object.entries(pendientes)),
  sinEquivalente: new Set(),
});

test('el catálogo solo trae maestros: nunca personas, roles ni secretos', () => {
  const prohibidas = [
    'TBL_USUARIOS', 'TBL_EMPRESAS', 'TBL_APPS', 'TBL_AREAS', 'TBL_CARGOS',
    'TBL_CENTROS_COSTOS', 'TBL_ESTRUCTURA_ORGANIZACIONAL', 'TBL_MIGRATIONS_LOGS',
    'TBL_CORREO_CREDENCIALES', 'TBL_DIAN_TOKENS', 'TBL_PAGOS_BENEFICIARIOS',
    'TBL_PAGOS_BENEFICIARIOS_CUENTA', 'TBL_VISITAS_GRUPOS', 'TBL_PP_CONFIG',
  ];
  const vistas = new Set();
  const modulos = new Set();
  for (const m of MODULOS_MAESTROS) {
    assert.ok(!modulos.has(m.id), `módulo repetido ${m.id}`);
    modulos.add(m.id);
    assert.ok(m.maestros.length > 0, m.id);
    for (const c of m.maestros) {
      assert.ok(!prohibidas.includes(c.id), `${m.id} no copia ${c.id}`);
      assert.ok(!c.id.endsWith('_ROLES') && !c.id.startsWith('TBL_AUTH'), c.id);
      assert.ok(!vistas.has(c.id), `${c.id} en dos módulos`);
      vistas.add(c.id);
      if (c.tipo === 'coleccion') {
        assert.ok(Array.isArray(c.clave), `${c.id} sin clave`);
      }
    }
  }
});

test('los módulos son los mismos ids de Limpieza', () => {
  const limpieza = new Set(MODULOS_LIMPIEZA.map((m) => m.id));
  for (const m of MODULOS_MAESTROS) {
    assert.ok(limpieza.has(m.id), `${m.id} no existe en Limpieza`);
  }
});

test('la clave ignora tildes, mayúsculas y signos', () => {
  assert.equal(normalizarClave('  Auxiliar de Cocína '), 'auxiliardecocina');
  assert.equal(
    claveDe({nombre: 'Leche Entera', codigo: 'P-01'}, ['codigo', 'nombre']),
    'p01|lecheentera',
  );
  assert.equal(claveDe({nombre: ' '}, ['nombre']), '');
  // Un número también sirve de clave (horarios: weekday).
  assert.equal(claveDe({weekday: 3, hora: '07:00'}, ['weekday', 'hora']),
    '3|0700');
});

test('ids: el prefijo de empresa pasa al destino y el resto se traduce', () => {
  const c = ctx({EMP_A_sede_norte: 'EMP_B_sede_norte_2'});
  assert.equal(idDestino('abc123', c), undefined);
  assert.equal(idDestino('EMP_A_AGUA', c), 'EMP_B_AGUA');
  // Establecimiento de Facturación: {empresa}_{centroId}.
  assert.equal(idDestino('EMP_A_EMP_A_sede_norte', c),
    'EMP_B_EMP_B_sede_norte_2');
  // Ubicación de Visitas: {empresa}_{centro}__{subcentro}.
  assert.equal(idDestino('EMP_A_EMP_A_sede_norte__cocina', c),
    'EMP_B_EMP_B_sede_norte_2__cocina');
});

test('remapear traduce valores y llaves, sin tocar fechas ni textos', () => {
  // Como un Timestamp de Firestore: una instancia, no un mapa.
  class Fecha {
    toMillis() {
      return 5;
    }
  }
  const fecha = new Fecha();
  const c = ctx({marcaX: 'marcaY', 'MRC-0003': 'MRC-0009'});
  const out = remapear({
    empresaId: 'EMP_A',
    nombre: 'Leche',
    marcas: [{marcaId: 'marcaX', codigo: 'MRC-0003'}],
    fichasTecnicasPorMarca: {marcaX: {url: 'https://x'}},
    areaId: 'EMP_A_nutricion',
    creado: fecha,
  }, c);
  assert.deepEqual(out.marcas, [{marcaId: 'marcaY', codigo: 'MRC-0009'}]);
  assert.deepEqual(Object.keys(out.fichasTecnicasPorMarca), ['marcaY']);
  assert.equal(out.empresaId, 'EMP_B');
  assert.equal(out.nombre, 'Leche');
  assert.equal(out.areaId, 'EMP_B_nutricion');
  assert.equal(out.creado, fecha);
});

test('lo que no tiene equivalente en el destino queda avisado', () => {
  const c = ctx({EMP_A_chef: 'EMP_B_chef'}, {EMP_A_chef: 'Cargo: Chef'});
  remapear({cargos: ['EMP_A_chef']}, c);
  assert.deepEqual([...c.sinEquivalente], ['Cargo: Chef']);
});

test('catálogo: por nombre; si no existe, el id que crearía Multiempresa', () => {
  const c = ctx();
  mapearCatalogo(
    [
      {ids: ['EMP_A_nutricion', 'NUT'], nombre: 'Nutrición', codigo: ''},
      {ids: ['EMP_A_bodega'], nombre: 'Bodega Central', codigo: ''},
    ],
    [{ids: ['EMP_B_nutricion_1'], nombre: 'NUTRICION', codigo: ''}],
    'EMP_B', 'Área', c,
  );
  assert.equal(c.mapa.get('EMP_A_nutricion'), 'EMP_B_nutricion_1');
  // Un id corto no se toma como referencia: es también un valor normal.
  assert.ok(!c.mapa.has('NUT'));
  assert.equal(c.mapa.get('EMP_A_bodega'), 'EMP_B_bodega_central');
  assert.equal(c.pendientes.get('EMP_A_bodega'), 'Área: Bodega Central');
  assert.ok(!c.pendientes.has('EMP_A_nutricion'));
  assert.equal(idCatalogo('EMP_B', ' Área Técnica '), 'EMP_B_area_tecnica');
});

test('centros: también por código', () => {
  const c = ctx();
  mapearCatalogo(
    [{ids: ['EMP_A_c1'], nombre: 'Sede 1', codigo: '1001'}],
    [{ids: ['EMP_B_x'], nombre: 'Sede Uno', codigo: '1001'}],
    'EMP_B', 'Centro de costos', c,
  );
  assert.equal(c.mapa.get('EMP_A_c1'), 'EMP_B_x');
});

test('configuración: solo completa lo vacío y nunca pisa', () => {
  const {parche, campos} = camposFaltantes(
    {
      empresaId: 'EMP_A',
      diasPlazoRechazados: 20,
      semaforo: {verdeDesde: 90, amarilloDesde: 70},
      programasInterventoria: ['PAE', 'ICBF'],
      reglasSubsanacion: {'REGULAR::1.1': {responsables: ['Chef']}},
      politicaRechazadosActualizadaPor: '123',
      updatedAt: 'ayer',
      alertaCedulas: ['1', '2'],
      vacioEnOrigen: '',
    },
    {
      diasPlazoRechazados: 30,
      semaforo: {verdeDesde: 80},
      programasInterventoria: [],
      reglasSubsanacion: {'REGULAR::1.2': {responsables: ['Gerente']}},
    },
    ['alertaCedulas'],
  );
  assert.deepEqual(parche, {
    semaforo: {amarilloDesde: 70},
    reglasSubsanacion: {'REGULAR::1.1': {responsables: ['Chef']}},
  });
  assert.deepEqual(campos.sort(), [
    'reglasSubsanacion.REGULAR::1.1',
    'semaforo.amarilloDesde',
  ]);
});

test('configuración: un texto vacío en el destino cuenta como faltante', () => {
  const {parche} = camposFaltantes(
    {unidadNegocio: '01', formaPago: 'T'},
    {unidadNegocio: '', formaPago: 'E'},
  );
  assert.deepEqual(parche, {unidadNegocio: '01'});
});

test('configuración: las llaves con ids se traducen antes de comparar', () => {
  const c = ctx({EMP_A_sede: 'EMP_B_sede'});
  const {parche} = camposFaltantes(
    {porCentro: {EMP_A_sede: 5, EMP_A_otra: 3}},
    {porCentro: {EMP_B_sede: 9}},
    [], c,
  );
  assert.deepEqual(parche, {porCentro: {EMP_B_otra: 3}});
});

test('consecutivo de marcas: salta los códigos usados', () => {
  const usados = new Set(['MRC-0001', 'MRC-0002', 'MRC-0004']);
  assert.deepEqual(codigoLibre(usados, 'MRC-', 4, 2),
    {codigo: 'MRC-0003', numero: 3});
  assert.deepEqual(codigoLibre(usados, 'MRC-', 4, 3),
    {codigo: 'MRC-0005', numero: 5});
  assert.equal(numeroDeCodigo('mrc-0012', 'MRC-'), 12);
  assert.equal(numeroDeCodigo('OTRA', 'MRC-'), 0);
});

test('archivo copiado: la carpeta de la empresa y del documento cambian', () => {
  const c = ctx({docA: 'docB'});
  assert.equal(
    rutaDestino('talento_humano/finalizacion/plantillas/EMP_A/x_1_a.docx', c),
    'talento_humano/finalizacion/plantillas/EMP_B/x_1_a.docx',
  );
  assert.equal(rutaDestino('documentos/EMP_A/docA/v2/1_a.pdf', c),
    'documentos/EMP_B/docB/v2/1_a.pdf');
});

test('interventoría: avisa los cargos de las reglas que el destino no tiene', () => {
  const reglas = {
    // Regla vieja: el cargo en singular.
    '1.1': {responsable: 'Administrador tipo 1', aprobador: 'Gerente'},
    'REGULAR::1.2': {
      responsables: ['Administrador tipo 2', 'Chef'],
      aprobadores: ['Gerente'],
    },
    'INFRAESTRUCTURA::1.1': {
      responsables: ['Mantenimiento'],
      aprobadores: ['Director de operaciones'],
    },
    basura: 'no es un mapa',
  };
  const existentes = new Set(
    ['administrador tipo 1', 'GERENTE', 'Chef'].map(normalizarClave),
  );
  assert.deepEqual(cargosFaltantesEnReglas(reglas, existentes), [
    'Administrador tipo 2',
    'Director de operaciones',
    'Mantenimiento',
  ]);
  assert.deepEqual(cargosFaltantesEnReglas(undefined, existentes), []);
});

test('solo los ids con prefijo o de Firestore se traducen como referencia', () => {
  assert.ok(pareceId('EMP_A_sede', 'EMP_A'));
  assert.ok(pareceId('aB3dE5gH7jK9mN1pQ3sT', 'EMP_A'));
  assert.ok(!pareceId('HIPO', 'EMP_A'));
  assert.ok(!pareceId('1001', 'EMP_A'));
  assert.ok(!pareceId('EMP_B_sede', 'EMP_A'));
});

test('visitas: el establecimiento propio va antes que su ubicación', () => {
  // 5 oct 2026: los establecimientos que no son centros de costo se copian
  // con su id `{empresa}_est_…`, que es el centroId de la ubicación; por
  // eso se planean antes y la ubicación queda apuntando al del destino.
  const visitas = MODULOS_MAESTROS.find((m) => m.id === 'visitas');
  const ids = visitas.maestros.map((m) => m.id);
  assert.ok(ids.indexOf('TBL_VISITAS_ESTABLECIMIENTOS') <
    ids.indexOf('TBL_VISITAS_UBICACIONES'));
  const c = ctx({EMP_A_est_bodega: 'EMP_B_est_bodega_2'});
  assert.equal(idDestino('EMP_A_EMP_A_est_bodega', c), 'EMP_B_EMP_B_est_bodega_2');
  assert.deepEqual(
    remapear({centroId: 'EMP_A_est_bodega', centroNombre: 'Bodega'}, c),
    {centroId: 'EMP_B_est_bodega_2', centroNombre: 'Bodega'}
  );
  // Sin equivalente previo, el id conserva el nombre con la otra empresa.
  assert.equal(idDestino('EMP_A_est_picota', ctx()), 'EMP_B_est_picota');
});
