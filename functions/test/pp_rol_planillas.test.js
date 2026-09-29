const test = require("node:test");
const assert = require("node:assert/strict");

const {resolvePlanillasRole} = require("../lib/pp_notifications");

// 28 sep 2026: los avisos de Planillas usan el mismo contrato que Admin.

test("la empresa manda, también cuando le quitaron el rol", () => {
  const u = {
    empresaId: "A", empresas: ["A", "B"], rolPlanillas: "gerencia",
    empresasDetalle: {A: {rolPlanillas: ""}, B: {rolPlanillas: "auditoria"}},
  };
  assert.equal(resolvePlanillasRole(u, "A"), "");
  assert.equal(resolvePlanillasRole(u, "B"), "auditoria");
});

test("la raíz solo sirve en la empresa principal", () => {
  const u = {empresaId: "A", empresas: ["A", "B"], rolPlanillas: "Gerente"};
  assert.equal(resolvePlanillasRole(u, "A"), "gerencia");
  assert.equal(resolvePlanillasRole(u, "B"), "");
});

test("un rol creado en Admin exige la app; uno viejo no", () => {
  const conApp = {
    empresaId: "A", apps: ["planillaspagodashboard"],
    empresasDetalle: {A: {rolPlanillas: "auditoria", rolPlanillasId: "A_mod_planillas_aud"}},
  };
  assert.equal(resolvePlanillasRole(conApp, "A"), "auditoria");
  const sinApp = {...conApp, apps: ["tareasdashboard"]};
  assert.equal(resolvePlanillasRole(sinApp, "A"), "");
  const viejo = {empresaId: "A", apps: [], empresasDetalle: {A: {rolPlanillas: "auditoria"}}};
  assert.equal(resolvePlanillasRole(viejo, "A"), "auditoria");
});
