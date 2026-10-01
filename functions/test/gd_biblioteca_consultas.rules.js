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
  getDocs,
  query,
  setDoc,
  where,
} = require("firebase/firestore");

// Las consultas de la Biblioteca y de Correspondencia sobre vínculos,
// colaboración y eventos deben llevar `empresaId`: la regla de lectura es
// `belongsToCompany(resource.data.empresaId)` y, sin ese filtro, Firestore no
// puede probarla y rechaza el listado entero (1 oct 2026: "Correspondencia
// relacionada" caía con permission-denied en todos los documentos).

const projectId = "capital-uspec-gd-biblioteca-test";
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

test.before(async () => {
  assert.ok(
    process.env.FIRESTORE_EMULATOR_HOST,
    "Ejecuta estas pruebas mediante Firebase Emulator Suite."
  );
  env = await initializeTestEnvironment({
    projectId,
    firestore: {rules},
  });
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await Promise.all([
      setDoc(doc(db, "TBL_USUARIOS/alice"), {empresas: ["EMP_A"]}),
      setDoc(doc(db, "TBL_GD_VINCULOS/exp_a_doc_a_v1"), {
        empresaId: "EMP_A",
        expedienteId: "exp_a",
        documentoId: "doc_a",
      }),
      setDoc(doc(db, "TBL_GD_VINCULOS/exp_b_doc_a_v1"), {
        empresaId: "EMP_B",
        expedienteId: "exp_b",
        documentoId: "doc_a",
      }),
      setDoc(doc(db, "TBL_GD_COLABORACION/col_a"), {
        empresaId: "EMP_A",
        expedienteId: "exp_a",
      }),
      setDoc(doc(db, "TBL_GD_EXPEDIENTES_EVENTOS/evt_a"), {
        empresaId: "EMP_A",
        expedienteId: "exp_a",
      }),
      setDoc(doc(db, "TBL_DOCUMENTOS_VERSIONES/ver_a"), {
        empresaId: "EMP_A",
        docId: "doc_a",
        numero: 1,
      }),
    ]);
  });
});

test.after(async () => {
  await env?.cleanup();
});

test("vínculos de un documento: sin empresa se rechaza, con empresa se leen", async () => {
  const db = auth("alice");
  await assertFails(getDocs(query(
    collection(db, "TBL_GD_VINCULOS"),
    where("documentoId", "==", "doc_a")
  )));
  const snap = await assertSucceeds(getDocs(query(
    collection(db, "TBL_GD_VINCULOS"),
    where("empresaId", "==", "EMP_A"),
    where("documentoId", "==", "doc_a")
  )));
  assert.deepEqual(snap.docs.map((d) => d.id), ["exp_a_doc_a_v1"]);
});

test("vínculos, colaboración y eventos del expediente se leen por empresa", async () => {
  const db = auth("alice");
  for (const col of [
    "TBL_GD_VINCULOS",
    "TBL_GD_COLABORACION",
    "TBL_GD_EXPEDIENTES_EVENTOS",
  ]) {
    await assertFails(getDocs(query(
      collection(db, col),
      where("expedienteId", "==", "exp_a")
    )));
    const snap = await assertSucceeds(getDocs(query(
      collection(db, col),
      where("empresaId", "==", "EMP_A"),
      where("expedienteId", "==", "exp_a")
    )));
    assert.equal(snap.size, 1, col);
  }
});

test("otra empresa no se puede consultar aunque se filtre por ella", async () => {
  const db = auth("alice");
  await assertFails(getDocs(query(
    collection(db, "TBL_GD_VINCULOS"),
    where("empresaId", "==", "EMP_B"),
    where("documentoId", "==", "doc_a")
  )));
});

test("las versiones de un documento se listan solo por docId", async () => {
  const db = auth("alice");
  const snap = await assertSucceeds(getDocs(query(
    collection(db, "TBL_DOCUMENTOS_VERSIONES"),
    where("docId", "==", "doc_a")
  )));
  assert.equal(snap.size, 1);
});
