const test = require("node:test");
const assert = require("node:assert/strict");
const { nivelTokensDian } = require("../lib/dian_tokens");

const miembro = {
  empresas: ["A", "B"],
  appsPorEmpresa: true,
  empresasDetalle: {
    A: { activo: true, apps: ["tokensdiandashboard"] },
    B: { activo: true, apps: [] },
  },
};

test("la membresía y app de la empresa activa limitan Tokens DIAN", () => {
  assert.equal(nivelTokensDian(miembro, "A", "persona", null), "operador");
  assert.equal(nivelTokensDian(miembro, "B", "persona", null), "ninguno");
  assert.equal(nivelTokensDian(miembro, "C", "persona", null), "ninguno");
  assert.equal(nivelTokensDian({ ...miembro, activo: false }, "A", "persona", null), "ninguno");
  assert.equal(nivelTokensDian({
    ...miembro,
    empresasDetalle: { ...miembro.empresasDetalle, A: { activo: false, apps: ["tokensdiandashboard"] } },
  }, "A", "persona", null), "ninguno");
});

test("el nivel canónico reduce el acceso histórico y no cruza empresas", () => {
  assert.equal(nivelTokensDian(miembro, "A", "persona", {
    empresaId: "A", userId: "persona", rol: "consulta",
  }), "consulta");
  assert.equal(nivelTokensDian(miembro, "A", "persona", {
    empresaId: "B", userId: "persona", rol: "administrador",
  }), "ninguno");
  assert.equal(nivelTokensDian(miembro, "A", "persona", {
    empresaId: "A", userId: "otro", rol: "administrador",
  }), "ninguno");
  assert.equal(nivelTokensDian(miembro, "A", "persona", {
    empresaId: "A", userId: "persona", rol: "desconocido",
  }), "ninguno");
});

test("Administración de la empresa conserva gestión sin app de Tokens", () => {
  const admin = {
    ...miembro,
    empresasDetalle: {
      A: { activo: true, apps: ["admindashboard"] },
      B: { activo: true, apps: [] },
    },
  };
  assert.equal(nivelTokensDian(admin, "A", "admin", null), "administrador");
  assert.equal(nivelTokensDian(admin, "B", "admin", null), "ninguno");
});
