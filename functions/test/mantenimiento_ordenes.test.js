const test = require("node:test");
const assert = require("node:assert/strict");
const {operaOrdenMantenimiento, cierreMantenimientoValido, personaMantenimiento} = require("../lib/mantenimiento_ordenes");
const {tipoEquipoEnSede} = require("../lib/mantenimiento_inventario");

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

test("el tipo respeta la sede, conserva el histórico y nunca aplica en temporal", () => {
  const equipo = {familia: "anexo_2", familiasPorSede: {norte: "anexo_3", sur: ""}};
  assert.equal(tipoEquipoEnSede(equipo, "norte"), "anexo_3");
  assert.equal(tipoEquipoEnSede(equipo, "sur"), "");
  assert.equal(tipoEquipoEnSede(equipo, "historica"), "anexo_2");
  assert.equal(tipoEquipoEnSede(equipo, "_bodega_temporal"), "");
});

test("el personal usa el cargo y departamento de la empresa activa", () => {
  const datos = {empresaId: "B", empresas: ["A", "B"], nombre: "Ana", cargo: "Cargo B", area: "Área B",
    empresasDetalle: {A: {cargoNombre: "Cargo A", areaNombre: "Área A"}}};
  const persona = (data) => personaMantenimiento({id: "ana", data: () => data}, "A");
  assert.deepEqual(persona(datos), {id: "ana", nombre: "Ana", cargo: "Cargo A", area: "Área A"});
  assert.deepEqual(persona({...datos, empresasDetalle: {A: {}}}), {id: "ana", nombre: "Ana", cargo: "", area: ""});
  assert.equal(persona({...datos, empresasDetalle: {A: {activo: false}}}), null);
});
