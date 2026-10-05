const test = require('node:test');
const assert = require('node:assert/strict');

const {
  aprobadorDeTarea,
  destinatariosSeguimiento,
  textoNumeroTarea,
  conNumeroTarea,
  cuerpoPushConNumero,
  esperarNumeroTarea,
  CREADOR_INTERVENTORIA,
} = require('../lib/tareas_avisos.js');

// 4 oct 2026, documento "Tareas": número en los avisos y la solicitud de
// finalización también a quien asignó la tarea. El aprobador es el mismo
// que calcula la app (lib/core/task_flujo.dart).

const tarea = (extra = {}) => ({
  asignado_uid: 'yimmy',
  creador_id: 'oscar',
  jefe_uid: 'zuly',
  aprobador_uid: 'zuly',
  ...extra,
});

test('el aprobador nunca es el responsable', () => {
  assert.equal(aprobadorDeTarea(tarea()), 'zuly');
  // Reasignada a quien era el aprobador: decide quien la asignó (tarea 2090).
  assert.equal(aprobadorDeTarea(tarea({asignado_uid: 'zuly'})), 'oscar');
  // Visitas: sin jefe, aprueba quien la asignó.
  assert.equal(aprobadorDeTarea(tarea({aprobador_uid: '', jefe_uid: ''})), 'oscar');
  assert.equal(
    aprobadorDeTarea(tarea({aprobador_uid: '', jefe_uid: '', creador_id: CREADOR_INTERVENTORIA})),
    ''
  );
});

test('la finalización avisa al aprobador y a quien asignó', () => {
  assert.deepEqual(destinatariosSeguimiento(tarea(), 'yimmy').sort(), ['oscar', 'zuly']);
  assert.deepEqual(destinatariosSeguimiento(tarea({creador_id: 'zuly'}), 'yimmy'), ['zuly']);
  assert.deepEqual(
    destinatariosSeguimiento(tarea({creador_id: CREADOR_INTERVENTORIA}), 'yimmy'),
    ['zuly']
  );
});

test('número de tarea en el texto del aviso, sin repetirlo', () => {
  assert.equal(textoNumeroTarea({numero: 2088}), 'Tarea No. 2088');
  assert.equal(textoNumeroTarea({}), '');
  assert.equal(conNumeroTarea({numero: 2088}, 'Informe · Prueba'), 'Tarea No. 2088 · Informe · Prueba');
  assert.equal(conNumeroTarea({numero: 2088}, 'Tarea No. 2088 · Informe'), 'Tarea No. 2088 · Informe');
  assert.equal(conNumeroTarea({}, 'Informe'), 'Informe');
  assert.equal(cuerpoPushConNumero(2090, 'Solicitud'), 'Tarea No. 2090 · Solicitud');
  assert.equal(cuerpoPushConNumero(undefined, 'Solicitud'), 'Solicitud');
});

test('espera el número que asigna tareasAsignarNumero', async () => {
  let lecturas = 0;
  const numero = await esperarNumeroTarea(async () => {
    lecturas += 1;
    return lecturas >= 3 ? {numero: 77} : {};
  }, [1, 1, 1, 1]);
  assert.equal(numero, 77);
  assert.equal(lecturas, 3);
  const sinNumero = await esperarNumeroTarea(async () => ({}), [1, 1]);
  assert.equal(sinNumero, null);
});
