/**
 * Pruebas de la jerarquía de roles de Correo / Gestión de Correspondencia.
 *
 * Ejecutar: npm run build && node --test test
 *
 * El control de verdad está aquí, en el backend: la interfaz esconde botones,
 * pero lo que impide que un usuario sin rol clasifique es `roleAllows`. Estas
 * pruebas fijan el efecto de haber insertado `clasificador` entre `operador` y
 * `administrador`, que es un cambio fácil de romper sin darse cuenta.
 */
const test = require("node:test");
const assert = require("node:assert/strict");

const { normalizeRole, roleAllows } = require("../lib/correo");

test("un operador no alcanza para clasificar ni asignar", () => {
  // Es el caso concreto de la reunión: la usuaria entraba al tablero y el
  // sistema la dejaba clasificar y asignar.
  assert.equal(roleAllows("operador", ["clasificador"]), false);
  assert.equal(roleAllows("visor", ["clasificador"]), false);
});

test("el clasificador puede clasificar y también lo del operador", () => {
  assert.equal(roleAllows("clasificador", ["clasificador"]), true);
  assert.equal(roleAllows("clasificador", ["operador"]), true);
  assert.equal(roleAllows("clasificador", ["visor"]), true);
});

test("el administrador conserva todo", () => {
  for (const exigido of ["visor", "operador", "clasificador", "administrador"]) {
    assert.equal(roleAllows("administrador", [exigido]), true, exigido);
  }
});

test("el clasificador no administra el módulo", () => {
  // Buzones, filtros y OAuth siguen siendo de administrador.
  assert.equal(roleAllows("clasificador", ["administrador"]), false);
});

test("insertar clasificador no le quitó nada al operador", () => {
  // Responder, avances y novedades siguen exigiendo solo operador.
  assert.equal(roleAllows("operador", ["operador"]), true);
  assert.equal(roleAllows("operador", ["visor"]), true);
});

test("normalizeRole reconoce las formas del rol clasificador", () => {
  for (const forma of [
    "clasificador",
    "CLASIFICADOR",
    "clasificadora",
    "asignador",
    "clasificador_asignador",
    "clasificador y asignador",
  ]) {
    assert.equal(normalizeRole(forma), "clasificador", forma);
  }
});

test("normalizeRole no convierte texto desconocido en permiso", () => {
  for (const forma of ["juridica", "usuario", "clasificar", "", null, undefined]) {
    assert.equal(normalizeRole(forma), null, `${forma}`);
  }
});

test("normalizeRole conserva los roles que ya existían", () => {
  assert.equal(normalizeRole("administrador"), "administrador");
  assert.equal(normalizeRole("admin"), "administrador");
  assert.equal(normalizeRole("gestor"), "administrador");
  assert.equal(normalizeRole("operador"), "operador");
  assert.equal(normalizeRole("visor"), "visor");
  assert.equal(normalizeRole("lectura"), "visor");
});
