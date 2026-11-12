const test = require("node:test");
const assert = require("node:assert/strict");
const {operaOrdenMantenimiento, cierreMantenimientoValido} = require("../lib/mantenimiento_ordenes");

test("el servidor exige acceso efectivo, empresa y módulo habilitados", () => {
  const usuario = {
    empresaId: "B", empresas: ["A", "B"], appsPorEmpresa: true, apps: ["mantenimientodashboard"],
    empresasDetalle: {A: {apps: ["mantenimientodashboard"]}, B: {apps: []}},
  };
  const acceso = {empresaId: "A", userId: "persona", operador: true};
  const app = {empresaId: "A", appId: "mantenimientodashboard", enabled: true};
  const puede = (u = usuario, a = acceso, m = app) => operaOrdenMantenimiento(u, a, m, "A", "persona");
  assert.equal(puede(), true);
  assert.equal(puede({...usuario, activo: false}), false);
  assert.equal(puede(usuario, {...acceso, operador: false}), false);
  assert.equal(puede(usuario, {...acceso, empresaId: "B"}), false);
  assert.equal(puede(usuario, acceso, {...app, enabled: false}), false);
  for (const cambio of [
    {apps: []}, {apps: ["mantenimientodashboard"], activo: false},
    {apps: ["mantenimientodashboard"], estadoLaboral: "INACTIVO"},
    {apps: ["mantenimientodashboard"], soloTalentoHumano: true},
  ]) {
    assert.equal(puede({...usuario, roleId: "A_administrador", empresasDetalle: {A: cambio}}), false);
  }
});

test("el cierre exige trabajo, técnico, receptor y fotografía final", () => {
  const completo = {trabajo: "Ajustado", tecnico: "Técnico", receptor: "Administrador"};
  assert.equal(cierreMantenimientoValido(completo, [{clase: "evidencia"}]), true);
  assert.equal(cierreMantenimientoValido(completo, [{clase: "diagnostico"}]), false);
  for (const campo of ["trabajo", "tecnico", "receptor"]) {
    assert.equal(cierreMantenimientoValido({...completo, [campo]: ""}, [{clase: "evidencia"}]), false);
  }
});
