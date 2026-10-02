/**
 * Reglas de TBL_INTERVENTORIA_CONCEPTOS_SANITARIOS (28 sep 2026): la sección
 * "Concepto sanitario" guarda establecimiento, fecha, puntaje y concepto.
 * La ve la empresa, la registran los roles con escritura del módulo y la
 * borran administración, gerencia y Desarrollo.
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
  Timestamp, collection, deleteDoc, doc, getDoc, getDocs, query, setDoc,
  updateDoc, where,
} = require("firebase/firestore");

const projectId = "capital-uspec-interventoria-conceptos";
const rules = fs.readFileSync(
  path.resolve(__dirname, "../../firestore.rules"),
  "utf8"
);
const COL = "TBL_INTERVENTORIA_CONCEPTOS_SANITARIOS";

let env;

function auth(userDocId) {
  return env.authenticatedContext(userDocId, {
    authVersion: 2,
    userDocId,
  }).firestore();
}

const concepto = (extra = {}) => ({
  empresaId: "EMP_A",
  centroCostoId: "c1",
  centroCostoNombre: "Sogamoso",
  fecha: Timestamp.fromDate(new Date(2026, 8, 10)),
  puntaje: 92.5,
  concepto: "FAVORABLE",
  ...extra,
});

test.before(async () => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST, "Usa el emulador.");
  env = await initializeTestEnvironment({projectId, firestore: {rules}});
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const usuario = (id) => setDoc(doc(db, `TBL_USUARIOS/${id}`), {
      nombre: id, empresaId: "EMP_A", empresas: ["EMP_A"],
      empresasDetalle: {EMP_A: {cargo: "Cargo"}},
    });
    const rol = (id, r) => setDoc(doc(db, `TBL_INTERVENTORIA_ROLES/EMP_A_${id}`), {
      empresaId: "EMP_A", userId: id, rol: r,
    });
    await Promise.all([
      usuario("registrador"), rol("registrador", "registrador_interventoria"),
      usuario("gerente"), rol("gerente", "gerente_interventoria"),
      usuario("calidad"), rol("calidad", "calidad_interventoria"),
      usuario("sinrol"),
      setDoc(doc(db, "TBL_USUARIOS/ajeno"), {
        nombre: "Ajeno", empresaId: "EMP_B", empresas: ["EMP_B"],
      }),
      setDoc(doc(db, "TBL_INTERVENTORIA_ROLES/EMP_B_ajeno"), {
        empresaId: "EMP_B", userId: "ajeno", rol: "admin_interventoria",
      }),
      setDoc(doc(db, `${COL}/existente`), concepto()),
    ]);
  });
});

test.after(async () => {
  await env?.cleanup();
});

test("quien registra actas sube un concepto sanitario", async () => {
  await assertSucceeds(
    setDoc(doc(auth("registrador"), `${COL}/nuevo`), concepto())
  );
});

test("calidad y quien no tiene rol solo consultan", async () => {
  await assertFails(setDoc(doc(auth("calidad"), `${COL}/c_calidad`), concepto()));
  await assertFails(setDoc(doc(auth("sinrol"), `${COL}/c_sinrol`), concepto()));
  await assertSucceeds(getDoc(doc(auth("calidad"), `${COL}/existente`)));
  await assertSucceeds(getDocs(query(
    collection(auth("sinrol"), COL),
    where("empresaId", "==", "EMP_A")
  )));
});

test("los datos se validan: puntaje 0-100 y un concepto conocido", async () => {
  const db = auth("gerente");
  await assertFails(setDoc(doc(db, `${COL}/malo1`), concepto({puntaje: 120})));
  await assertFails(setDoc(doc(db, `${COL}/malo2`), concepto({concepto: "OK"})));
  await assertFails(setDoc(doc(db, `${COL}/malo3`), concepto({centroCostoId: ""})));
  await assertFails(setDoc(doc(db, `${COL}/malo4`), concepto({fecha: "10/09/2026"})));
  await assertSucceeds(
    updateDoc(doc(db, `${COL}/existente`), {concepto: "DESFAVORABLE", puntaje: 40})
  );
});

test("otra empresa no lee ni escribe", async () => {
  await assertFails(getDoc(doc(auth("ajeno"), `${COL}/existente`)));
  await assertFails(setDoc(doc(auth("ajeno"), `${COL}/ajeno`), concepto()));
});

test("borran administración y gerencia, no quien registra", async () => {
  await assertFails(deleteDoc(doc(auth("registrador"), `${COL}/existente`)));
  await assertSucceeds(deleteDoc(doc(auth("gerente"), `${COL}/existente`)));
});
