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

/**
 * El administrador del módulo leía "no tienes permiso para clasificar".
 *
 * `isDeveloper` solo miraba una bandera booleana y los campos de la raíz del
 * usuario. En una aplicación multiempresa el rol vive en
 * `empresasDetalle[empresaId]`, así que quien administra el módulo caía al rol
 * por defecto y el servidor le rechazaba la acción.
 */
test("se reconoce al desarrollador marcado dentro de la empresa", () => {
  const { isDeveloper } = require("../lib/correo.js");

  assert.equal(
    isDeveloper({ empresasDetalle: { CAPITAL: { roleKey: "desarrollador" } } }, "CAPITAL"),
    true
  );
  assert.equal(
    isDeveloper({ empresasDetalle: { CAPITAL: { roleId: "CAPITAL_desarrollador" } } }, "CAPITAL"),
    true
  );
  assert.equal(isDeveloper({ roleId: "CAPITAL_desarrollador" }), true);
});

test("se siguen reconociendo las formas de siempre", () => {
  const { isDeveloper } = require("../lib/correo.js");

  assert.equal(isDeveloper({ desarrollador: true }), true);
  assert.equal(isDeveloper({ role: "superadmin" }), true);
});

test("un rol cualquiera de la empresa no convierte en desarrollador", () => {
  const { isDeveloper } = require("../lib/correo.js");

  assert.equal(
    isDeveloper({ empresasDetalle: { CAPITAL: { roleKey: "operador" } } }, "CAPITAL"),
    false
  );
  assert.equal(isDeveloper({}), false);
});

/**
 * El orden de precedencia se unificó el 10 sep 2026: manda `TBL_CORREO_ROLES`
 * sobre `rolCorreo` del usuario, en el backend igual que en el cliente. Antes
 * estaban al revés y a quien tuviera los dos puestos con valores distintos se
 * le enseñaba u ocultaba lo que no correspondía.
 *
 * `resolveCorreoRole` toca Firestore, así que aquí se fija la parte que sí se
 * puede probar sin emulador: que el texto de la colección se traduzca igual que
 * el del usuario, y que un texto raro no conceda nada por ninguno de los dos
 * caminos.
 */
test("un texto no reconocido no concede nada, venga de donde venga", () => {
  const { normalizeRole } = require("../lib/correo.js");

  for (const raro of ["coordinador", "jefe", "", null, undefined, 7]) {
    assert.equal(normalizeRole(raro), null, `"${raro}" no debe conceder rol`);
  }
});

test("los dos caminos traducen el rol igual", () => {
  const { normalizeRole } = require("../lib/correo.js");

  // Lo que escribe la pantalla de roles y lo que pudo quedar a mano en el
  // usuario tienen que significar lo mismo.
  assert.equal(normalizeRole("clasificador"), "clasificador");
  assert.equal(normalizeRole("clasificador_asignador"), "clasificador");
  assert.equal(normalizeRole("administrador"), "administrador");
  assert.equal(normalizeRole("operador"), "operador");
});
