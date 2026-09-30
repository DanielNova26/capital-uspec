/**
 * Gerencia (29 sep 2026): sus roles configurables van en TBL_ROLES y solo los
 * crea Admin de la empresa o Desarrollo. Los permisos se materializan en la
 * ficha (`permisosGerencia`), que sigue bajo la regla general de
 * TBL_USUARIOS: el límite de áreas, empresas, pestañas y exportación se
 * aplica en el módulo.
 */
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require("@firebase/rules-unit-testing");
const {doc, setDoc, updateDoc} = require("firebase/firestore");

const projectId = "capital-uspec-gerencia";
const rules = fs.readFileSync(
  path.resolve(__dirname, "../../firestore.rules"),
  "utf8"
);

let env;

function auth(userDocId) {
  return env.authenticatedContext(userDocId, {
    authVersion: 2,
    userDocId,
  }).firestore();
}

function definicion(extra = {}) {
  return {
    empresaId: "EMP_A",
    type: "module_role",
    moduleId: "gerenciadashboard",
    nombre: "Dirección",
    permissions: {pestanaDashboard: true, exportar: false},
    enabled: true,
    revision: 1,
    ...extra,
  };
}

test.before(async () => {
  assert.ok(
    process.env.FIRESTORE_EMULATOR_HOST,
    "Ejecuta estas pruebas mediante Firebase Emulator Suite."
  );
  env = await initializeTestEnvironment({projectId, firestore: {rules}});
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await Promise.all([
      setDoc(doc(db, "TBL_USUARIOS/adminApp"), {
        empresas: ["EMP_A"],
        appsPorEmpresa: true,
        empresasDetalle: {EMP_A: {apps: ["admindashboard"]}},
      }),
      setDoc(doc(db, "TBL_USUARIOS/adminInhabilitado"), {
        empresas: ["EMP_A"],
        appsPorEmpresa: true,
        empresasDetalle: {
          EMP_A: {apps: ["admindashboard"], estadoLaboral: "inactivo"},
        },
      }),
      setDoc(doc(db, "TBL_USUARIOS/comun"), {
        empresas: ["EMP_A"], empresasDetalle: {EMP_A: {}},
      }),
      setDoc(doc(db, "TBL_USUARIOS/adminAjeno"), {
        empresas: ["EMP_B"],
        appsPorEmpresa: true,
        empresasDetalle: {EMP_B: {apps: ["admindashboard"]}},
      }),
      setDoc(doc(db, "TBL_ROLES/EMP_A_mod_gerencia_existente"), definicion()),
    ]);
  });
});

test.after(async () => {
  await env?.cleanup();
});

test("roles de Gerencia: Admin de la empresa, no cualquiera", async () => {
  await assertSucceeds(
    setDoc(doc(auth("adminApp"), "TBL_ROLES/EMP_A_mod_gerencia_direccion"),
      definicion())
  );
  await assertFails(
    setDoc(doc(auth("comun"), "TBL_ROLES/EMP_A_mod_gerencia_mio"),
      definicion())
  );
  await assertFails(
    setDoc(doc(auth("adminAjeno"), "TBL_ROLES/EMP_A_mod_gerencia_ajeno"),
      definicion())
  );
  await assertFails(
    setDoc(doc(auth("adminInhabilitado"),
      "TBL_ROLES/EMP_A_mod_gerencia_inhabilitado"), definicion())
  );
});

test("roles de Gerencia: contrato de la definición", async () => {
  // Sin el prefijo de su empresa o sin revisión no se guarda.
  await assertFails(
    setDoc(doc(auth("adminApp"), "TBL_ROLES/EMP_B_mod_gerencia_x"),
      definicion())
  );
  await assertFails(
    setDoc(doc(auth("adminApp"), "TBL_ROLES/EMP_A_mod_gerencia_sinrev"),
      definicion({revision: 0}))
  );
  // Editar exige Admin y no deja cambiar de módulo.
  await assertSucceeds(
    updateDoc(doc(auth("adminApp"), "TBL_ROLES/EMP_A_mod_gerencia_existente"),
      {revision: 2, enabled: false})
  );
  await assertFails(
    updateDoc(doc(auth("comun"), "TBL_ROLES/EMP_A_mod_gerencia_existente"),
      {revision: 3})
  );
  await assertFails(
    updateDoc(doc(auth("adminApp"), "TBL_ROLES/EMP_A_mod_gerencia_existente"),
      {revision: 3, moduleId: "tareasdashboard"})
  );
});
