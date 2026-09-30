const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require("@firebase/rules-unit-testing");
const {doc, getDoc, setDoc, updateDoc} = require("firebase/firestore");

const rules = fs.readFileSync(
  path.resolve(__dirname, "../../firestore.rules"),
  "utf8"
);
let env;

function db(userDocId) {
  return env.authenticatedContext(userDocId, {
    authVersion: 2,
    userDocId,
  }).firestore();
}

test.before(async () => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST,
    "Ejecuta estas pruebas mediante Firebase Emulator Suite.");
  env = await initializeTestEnvironment({
    projectId: "capital-uspec-correo-config",
    firestore: {rules},
  });
  await env.withSecurityRulesDisabled(async (context) => {
    const seed = context.firestore();
    await Promise.all([
      setDoc(doc(seed, "TBL_USUARIOS/adminA"), {
        empresas: ["EMP_A"], appsPorEmpresa: true,
        empresasDetalle: {EMP_A: {apps: ["admindashboard"]}},
      }),
      setDoc(doc(seed, "TBL_USUARIOS/correoA"), {
        empresas: ["EMP_A"], appsPorEmpresa: true,
        empresasDetalle: {EMP_A: {apps: ["correodashboard"]}},
      }),
      setDoc(doc(seed, "TBL_USUARIOS/adminB"), {
        empresas: ["EMP_B"], appsPorEmpresa: true,
        empresasDetalle: {EMP_B: {apps: ["admindashboard"]}},
      }),
      setDoc(doc(seed, "TBL_CORREO_REGLAS/r1"), {
        empresaId: "EMP_A", nombre: "Asunto",
      }),
    ]);
  });
});

test.after(async () => {
  await env?.cleanup();
});

test("la empresa consulta filtros, solo Admin los edita", async () => {
  await assertSucceeds(getDoc(doc(db("correoA"), "TBL_CORREO_REGLAS/r1")));
  await assertFails(getDoc(doc(db("adminB"), "TBL_CORREO_REGLAS/r1")));
  await assertSucceeds(setDoc(doc(db("adminA"), "TBL_CORREO_REGLAS/r2"), {
    empresaId: "EMP_A", nombre: "Remitente",
  }));
  await assertFails(setDoc(doc(db("correoA"), "TBL_CORREO_REGLAS/r3"), {
    empresaId: "EMP_A", nombre: "No autorizado",
  }));
  await assertFails(updateDoc(doc(db("correoA"), "TBL_CORREO_REGLAS/r1"), {
    nombre: "No autorizado",
  }));
  await assertFails(updateDoc(doc(db("adminA"), "TBL_CORREO_REGLAS/r1"), {
    empresaId: "EMP_B",
  }));
});
