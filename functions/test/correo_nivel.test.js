const test = require("node:test");
const assert = require("node:assert/strict");
const {createHash} = require("node:crypto");

const {
  nivelCorreoDeFicha,
  normalizeRole,
  tieneAppCorreo,
  userDocIdDelToken,
} = require("../lib/correo");

// 28 sep 2026: el servidor resuelve el nivel de Correspondencia igual que
// `resolveCorrespondenceRole` del cliente (gd_permisos.dart) y la identidad
// sale del token, no del cuerpo de la petición.

test("nivel por ficha: la empresa manda y el vacío explícito es Visor", () => {
  const u = {
    empresaId: "A", empresas: ["A", "B"], rolCorreo: "administrador",
    empresasDetalle: {A: {rolCorreo: ""}, B: {rolCorreo: "clasificador"}},
  };
  assert.equal(nivelCorreoDeFicha(u, "A"), "visor");
  assert.equal(nivelCorreoDeFicha(u, "B"), "clasificador");
});

test("nivel por ficha: la raíz solo sirve en la empresa principal", () => {
  const u = {empresaId: "A", empresas: ["A", "B"], rolCorreo: "clasificador"};
  assert.equal(nivelCorreoDeFicha(u, "A"), "clasificador");
  // En B no hay decisión: Operador, no el clasificador de A.
  assert.equal(nivelCorreoDeFicha(u, "B"), "operador");
});

test("nivel por ficha: sin decisión es Operador; admin general es administrador", () => {
  assert.equal(nivelCorreoDeFicha({empresaId: "A"}, "A"), "operador");
  assert.equal(nivelCorreoDeFicha({empresaId: "A", role: "admin"}, "A"),
    "administrador");
  assert.equal(nivelCorreoDeFicha({
    empresaId: "A", empresasDetalle: {B: {roleKey: "administrador"}},
  }, "B"), "administrador");
  // El rol general de la principal no sube a nadie en otra empresa.
  assert.equal(nivelCorreoDeFicha({
    empresaId: "A", empresas: ["A", "B"], role: "admin",
    empresasDetalle: {B: {}},
  }, "B"), "operador");
});

test("niveles: los mismos textos que el cliente", () => {
  for (const t of ["superadmin", "desarrollador", "developer", "Admin", "gestor"]) {
    assert.equal(normalizeRole(t), "administrador", t);
  }
  assert.equal(normalizeRole("Clasificador y asignador"), "clasificador");
  assert.equal(normalizeRole("lectura"), "visor");
  assert.equal(normalizeRole("otro"), null);
});

test("app de Correo por empresa", () => {
  const porEmpresa = {
    empresaId: "A", empresas: ["A", "B"], appsPorEmpresa: true,
    apps: ["correodashboard"],
    empresasDetalle: {A: {apps: ["correodashboard"]}, B: {apps: ["tareasdashboard"]}},
  };
  assert.equal(tieneAppCorreo(porEmpresa, "A"), true);
  assert.equal(tieneAppCorreo(porEmpresa, "B"), false);
  assert.equal(tieneAppCorreo({empresaId: "A", apps: ["correo"]}, "A"), true);
});

test("identidad: solo la del token de Auth v2", () => {
  const uid = `todo_${createHash("sha256").update("123", "utf8").digest("hex")}`;
  assert.equal(userDocIdDelToken(uid, {userDocId: "123", authVersion: 2}), "123");
  // Otro userDocId con el mismo uid, versión vieja o sin claim: nada.
  assert.equal(userDocIdDelToken(uid, {userDocId: "999", authVersion: 2}), "");
  assert.equal(userDocIdDelToken(uid, {userDocId: "123", authVersion: 1}), "");
  assert.equal(userDocIdDelToken("anonimo", {userDocId: "123", authVersion: 2}), "");
  assert.equal(userDocIdDelToken(uid, undefined), "");
});
