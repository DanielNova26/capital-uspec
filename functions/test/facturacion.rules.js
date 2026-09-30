/**
 * Facturación (29 sep 2026): roles configurables en TBL_ROLES solo para Admin
 * de la empresa o Desarrollo, y sus datos por empresa. Antes todo estaba en
 * la regla general.
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
const {
  collection,
  doc,
  getDoc,
  getDocs,
  query,
  setDoc,
  updateDoc,
  where,
} = require("firebase/firestore");

const projectId = "capital-uspec-facturacion";
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
    moduleId: "facturaciondashboard",
    nombre: "Gestión",
    baseRole: "facturacion",
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
      setDoc(doc(db, "TBL_USUARIOS/comun"), {
        empresas: ["EMP_A"], empresasDetalle: {EMP_A: {}},
      }),
      setDoc(doc(db, "TBL_USUARIOS/ajeno"), {
        empresas: ["EMP_B"], empresasDetalle: {EMP_B: {}},
      }),
      setDoc(doc(db, "TBL_FAC_REVISIONES/r1"), {
        empresaId: "EMP_A", estado: "pendiente",
      }),
      setDoc(doc(db, "TBL_FAC_OBSERVACIONES/o1"), {
        empresaId: "EMP_A", texto: "Falta el paz y salvo",
      }),
      setDoc(doc(db, "TBL_FAC_CONFIG/EMP_A"), {meses: ["2026-09"]}),
    ]);
  });
});

test.after(async () => {
  await env?.cleanup();
});

test("roles de Facturación: Admin de la empresa, no cualquiera", async () => {
  await assertSucceeds(
    setDoc(doc(auth("adminApp"), "TBL_ROLES/EMP_A_mod_facturacion_gestion"),
      definicion())
  );
  await assertFails(
    setDoc(doc(auth("comun"), "TBL_ROLES/EMP_A_mod_facturacion_mio"),
      definicion())
  );
});

test("los datos de Facturación quedan en su empresa", async () => {
  await assertSucceeds(getDoc(doc(auth("comun"), "TBL_FAC_REVISIONES/r1")));
  await assertSucceeds(
    getDocs(query(
      collection(auth("comun"), "TBL_FAC_OBSERVACIONES"),
      where("empresaId", "==", "EMP_A")
    ))
  );
  await assertSucceeds(
    updateDoc(doc(auth("comun"), "TBL_FAC_OBSERVACIONES/o1"), {
      tareaEstado: "por_aprobar",
    })
  );
  await assertFails(getDoc(doc(auth("ajeno"), "TBL_FAC_REVISIONES/r1")));
  await assertFails(
    getDocs(query(
      collection(auth("ajeno"), "TBL_FAC_OBSERVACIONES"),
      where("empresaId", "==", "EMP_A")
    ))
  );
  await assertFails(
    updateDoc(doc(auth("comun"), "TBL_FAC_REVISIONES/r1"), {empresaId: "EMP_B"})
  );
  await assertFails(
    setDoc(doc(auth("ajeno"), "TBL_FAC_OBLIGACIONES/EMP_A_x"), {
      empresaId: "EMP_A", nombre: "Colada",
    })
  );
  // Un id que no existe responde vacío (se pregunta antes de crear).
  await assertSucceeds(
    getDoc(doc(auth("comun"), "TBL_FAC_ESTABLECIMIENTOS/EMP_A_nuevo"))
  );
  await assertSucceeds(getDoc(doc(auth("comun"), "TBL_FAC_CONFIG/EMP_A")));
  await assertFails(getDoc(doc(auth("ajeno"), "TBL_FAC_CONFIG/EMP_A")));
});
