const test = require('node:test');
const assert = require('node:assert/strict');
const {
  MODULOS_LIMPIEZA,
  enRango,
  fechaDeRegistro,
  moduloDeTarea,
  notificacionDelModulo,
  rangoDesde,
} = require('../lib/limpieza');

const DIA = 24 * 60 * 60 * 1000;
const ts = (ms) => ({toMillis: () => ms});

test('el catálogo nunca toca personas, empresas, roles ni credenciales', () => {
  const prohibidas = [
    'TBL_USUARIOS', 'TBL_EMPRESAS', 'TBL_ROLES', 'TBL_APPS',
    'TBL_ESTRUCTURA_ORGANIZACIONAL', 'TBL_AREAS', 'TBL_CARGOS',
    'TBL_CENTROS_COSTOS', 'TBL_EMPLEADOS', 'TBL_CORREO_CREDENCIALES',
    'TBL_CORREO_CUENTAS', 'TBL_MIGRATIONS_LOGS', 'TBL_FIRMAS',
  ];
  const vistas = new Set();
  const ids = new Set();
  for (const m of MODULOS_LIMPIEZA) {
    assert.ok(!ids.has(m.id), `módulo repetido ${m.id}`);
    ids.add(m.id);
    for (const c of [...m.registros, ...m.maestros]) {
      assert.ok(!prohibidas.includes(c.id), `${m.id} no puede borrar ${c.id}`);
      assert.ok(!c.id.startsWith('TBL_AUTH'), c.id);
      assert.ok(!c.id.endsWith('_ROLES') && !c.id.endsWith('_CONFIG'), c.id);
      // Cada colección es de un solo módulo.
      assert.ok(!vistas.has(c.id), `${c.id} en dos módulos`);
      vistas.add(c.id);
    }
  }
});

test('fecha de creación: el primer campo que la trae', () => {
  assert.equal(fechaDeRegistro({createdAt: ts(5), fecha: ts(9)}), 5);
  assert.equal(fechaDeRegistro({fecha_creacion: ts(7)}), 7);
  assert.equal(fechaDeRegistro({fecha: '2026-09-01'}), Date.parse('2026-09-01'));
  // updatedAt no es la fecha de creación.
  assert.equal(fechaDeRegistro({updatedAt: ts(3)}), null);
  assert.equal(fechaDeRegistro({fecha: 'no es fecha'}), null);
});

test('periodos: todo, antes, desde y entre (el día final incluido)', () => {
  const d1 = Date.UTC(2026, 8, 1);
  const d10 = Date.UTC(2026, 8, 10);
  assert.deepEqual(rangoDesde({modo: 'todo'}), {modo: 'todo', desde: null, hasta: null});
  const antes = rangoDesde({modo: 'antes', desde: d10});
  assert.equal(enRango(d10 - 1, antes), 'entra');
  assert.equal(enRango(d10, antes), 'fuera');
  const desde = rangoDesde({modo: 'desde', desde: d10});
  assert.equal(enRango(d10, desde), 'entra');
  assert.equal(enRango(d1, desde), 'fuera');
  const entre = rangoDesde({modo: 'entre', desde: d1, hasta: d10});
  assert.equal(enRango(d10 + DIA - 1, entre), 'entra');
  assert.equal(enRango(d10 + DIA, entre), 'fuera');
  assert.equal(enRango(null, entre), 'sinFecha');
  assert.equal(enRango(null, rangoDesde({modo: 'todo'})), 'entra');
  assert.throws(() => rangoDesde({modo: 'entre', desde: d10, hasta: d1}));
  assert.throws(() => rangoDesde({modo: 'desde'}));
  assert.throws(() => rangoDesde({modo: 'nada'}));
});

test('tareas: cada una es del módulo que la creó', () => {
  assert.equal(moduloDeTarea({hallazgoId: 'h1'}), 'interventoria');
  assert.equal(moduloDeTarea({creador_id: 'interventoria_automatica'}), 'interventoria');
  assert.equal(moduloDeTarea({facObservacionId: 'o1'}), 'facturacion');
  assert.equal(moduloDeTarea({origen: 'visita', visitaId: 'v'}), 'visitas');
  assert.equal(moduloDeTarea({origen: 'compras_correccion', module: 'compras_bodega'}), 'compras');
  assert.equal(
    moduloDeTarea({source: {moduleId: 'gestion_documental'}}),
    'gestion_documental'
  );
  assert.equal(moduloDeTarea({source: {moduleId: 'planillas_pago'}}), 'planillas_pago');
  assert.equal(moduloDeTarea({origen: 'manual', sourceModule: 'tareas'}), 'tareas');
  assert.equal(moduloDeTarea({}), 'tareas');
});

test('notificaciones: por su módulo o por la tarea que se borra', () => {
  const tareas = new Set(['t1']);
  assert.equal(notificacionDelModulo({taskId: 't1'}, 'tareas', tareas), true);
  assert.equal(notificacionDelModulo({module: 'interventoriadashboard'}, 'interventoria', tareas), true);
  assert.equal(notificacionDelModulo({type: 'facturacion_nueva'}, 'facturacion', tareas), true);
  assert.equal(notificacionDelModulo({module: 'compras'}, 'interventoria', tareas), false);
  assert.equal(notificacionDelModulo({taskId: 'otra'}, 'tareas', tareas), false);
});
