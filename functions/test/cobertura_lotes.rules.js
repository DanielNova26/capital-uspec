/**
 * Historial de cambios masivos de cobertura (19 oct 2026):
 * `TBL_COBERTURA_LOTES` y su subcolección `personas`. Solo Admin de la empresa
 * (o Desarrollo) lo lee y lo crea; un lote solo pasa de "aplicado" a
 * "revertido"; nada se borra.
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
  deleteDoc,
  doc,
  getDoc,
  serverTimestamp,
  setDoc,
  updateDoc,
} = require("firebase/firestore");

const projectId = "capital-uspec-cobertura-lotes";
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

const lote = (creadoPor, extra = {}) => ({
  empresaId: "EMP_A",
  tipo: "excel",
  creadoPor,
  createdAt: serverTimestamp(),
  total: 1,
  estado: "aplicado",
  ...extra,
});

test.before(async () => {
  assert.ok(
    process.env.FIRESTORE_EMULATOR_HOST,
    "Ejecuta estas pruebas mediante Firebase Emulator Suite."
  );
  env = await initializeTestEnvironment({projectId, firestore: {rules}});
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await Promise.all([
      setDoc(doc(db, "TBL_USUARIOS/adminA"), {
        empresas: ["EMP_A"],
        appsPorEmpresa: true,
        empresasDetalle: {EMP_A: {apps: ["admindashboard"]}},
      }),
      setDoc(doc(db, "TBL_USUARIOS/comunA"), {
        empresas: ["EMP_A"], empresasDetalle: {EMP_A: {}},
      }),
      setDoc(doc(db, "TBL_USUARIOS/adminB"), {
        empresas: ["EMP_B"],
        appsPorEmpresa: true,
        empresasDetalle: {EMP_B: {apps: ["admindashboard"]}},
      }),
      setDoc(doc(db, "TBL_COBERTURA_LOTES/l1"), {
        empresaId: "EMP_A", tipo: "excel", creadoPor: "adminA",
        total: 1, estado: "aplicado",
      }),
      setDoc(doc(db, "TBL_COBERTURA_LOTES/l1/personas/p1"), {
        userId: "p1", nombre: "Persona", antes: {}, despues: {},
      }),
    ]);
  });
});

test.after(async () => {
  await env?.cleanup();
});

test("lo lee Admin de su empresa y nadie más", async () => {
  await assertSucceeds(getDoc(doc(auth("adminA"), "TBL_COBERTURA_LOTES/l1")));
  await assertSucceeds(
    getDoc(doc(auth("adminA"), "TBL_COBERTURA_LOTES/l1/personas/p1"))
  );
  await assertFails(getDoc(doc(auth("comunA"), "TBL_COBERTURA_LOTES/l1")));
  await assertFails(getDoc(doc(auth("adminB"), "TBL_COBERTURA_LOTES/l1")));
  await assertFails(
    getDoc(doc(auth("adminB"), "TBL_COBERTURA_LOTES/l1/personas/p1"))
  );
});

test("lo crea Admin a su nombre y con estado aplicado", async () => {
  await assertSucceeds(
    setDoc(doc(auth("adminA"), "TBL_COBERTURA_LOTES/nuevo"), lote("adminA"))
  );
  await assertSucceeds(
    setDoc(doc(auth("adminA"), "TBL_COBERTURA_LOTES/nuevo/personas/p2"), {
      userId: "p2", nombre: "Otra", antes: {}, despues: {},
    })
  );
  await assertFails(
    setDoc(doc(auth("comunA"), "TBL_COBERTURA_LOTES/c1"), lote("comunA"))
  );
  await assertFails(
    setDoc(doc(auth("adminB"), "TBL_COBERTURA_LOTES/c2"), lote("adminB"))
  );
  await assertFails(
    setDoc(doc(auth("adminA"), "TBL_COBERTURA_LOTES/c3"), lote("adminB"))
  );
  await assertFails(
    setDoc(doc(auth("adminA"), "TBL_COBERTURA_LOTES/c4"),
      lote("adminA", {estado: "revertido"}))
  );
  await assertFails(
    setDoc(doc(auth("comunA"), "TBL_COBERTURA_LOTES/nuevo/personas/p3"), {
      userId: "p3",
    })
  );
});

test("solo pasa de aplicado a revertido y nada se borra", async () => {
  await assertSucceeds(
    updateDoc(doc(auth("adminA"), "TBL_COBERTURA_LOTES/l1"), {
      estado: "revertido",
      revertidoPor: "adminA",
      revertidoAt: serverTimestamp(),
    })
  );
  // Ya revertido: no vuelve a cambiar.
  await assertFails(
    updateDoc(doc(auth("adminA"), "TBL_COBERTURA_LOTES/l1"), {
      estado: "revertido",
      revertidoPor: "adminA",
    })
  );
  await assertFails(
    updateDoc(doc(auth("adminA"), "TBL_COBERTURA_LOTES/nuevo"), {total: 99})
  );
  await assertFails(
    updateDoc(doc(auth("comunA"), "TBL_COBERTURA_LOTES/nuevo"), {
      estado: "revertido",
    })
  );
  await assertFails(deleteDoc(doc(auth("adminA"), "TBL_COBERTURA_LOTES/l1")));
  await assertFails(
    updateDoc(doc(auth("adminA"), "TBL_COBERTURA_LOTES/l1/personas/p1"), {
      nombre: "X",
    })
  );
  await assertFails(
    deleteDoc(doc(auth("adminA"), "TBL_COBERTURA_LOTES/l1/personas/p1"))
  );
});
