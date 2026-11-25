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
  getDoc,
  query,
  setDoc,
  updateDoc,
  writeBatch,
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
      setDoc(doc(db, "TBL_USUARIOS/multi"), {empresas: ["EMP_A", "EMP_B"]}),
      setDoc(doc(db, "TBL_USUARIOS/inactive"), {empresas: ["EMP_A"], activo: false}),
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
      setDoc(doc(db, "TBL_DOCUMENTOS/doc_a"), {empresaId: "EMP_A"}),
      setDoc(doc(db, "TBL_DOCUMENTOS/doc_b"), {empresaId: "EMP_B"}),
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
  await assertFails(getDocs(query(collection(db, "TBL_DOCUMENTOS_VERSIONES"), where("docId", "==", "doc_b"))));
});

for (const estado of ["borrador", "vigente"]) {
  test(`crear documento y versión inicial atómicamente: ${estado}`, async () => {
    const db = auth("alice");
    const id = `nuevo_${estado}`;
    const batch = writeBatch(db);
    batch.set(doc(db, "TBL_DOCUMENTOS", id), {
      empresaId: "EMP_A", estado, creadoPor: "alice", codigo: "GER-007",
    });
    batch.set(doc(db, "TBL_DOCUMENTOS_VERSIONES", id), {
      empresaId: "EMP_A", docId: id, estado, numero: 1,
    });
    await assertSucceeds(batch.commit());
    assert.equal((await getDoc(doc(db, "TBL_DOCUMENTOS_VERSIONES", id))).data().docId, id);
  });
}

test("versión y evento posteriores conservan acceso al documento existente", async () => {
  const db = auth("alice");
  for (const col of ["TBL_DOCUMENTOS_VERSIONES", "TBL_DOCUMENTOS_FLUJO"]) {
    await assertSucceeds(setDoc(doc(db, col, "posterior"), {
      empresaId: "EMP_A", docId: "doc_a",
    }));
  }
  await assertSucceeds(updateDoc(doc(db, "TBL_DOCUMENTOS_VERSIONES/posterior"), {
    urlPdf: "https://example.com/documento.pdf",
  }));
});

test("las versiones y eventos sin padre siguen rechazados", async () => {
  const db = auth("alice");
  for (const col of ["TBL_DOCUMENTOS_VERSIONES", "TBL_DOCUMENTOS_FLUJO"]) {
    await assertFails(setDoc(doc(db, col, "huerfano"), {
      empresaId: "EMP_A", docId: "no_existe",
    }));
  }
});

test("crear en lote no permite mezclar empresas aunque la persona pertenezca a ambas", async () => {
  const db = auth("multi");
  const batch = writeBatch(db);
  batch.set(doc(db, "TBL_DOCUMENTOS/empresa_a"), {empresaId: "EMP_A"});
  batch.set(doc(db, "TBL_DOCUMENTOS_VERSIONES/empresa_b"), {
    empresaId: "EMP_B", docId: "empresa_a",
  });
  await assertFails(batch.commit());
});

test("no se crea para otra empresa, una cuenta inactiva ni sin sesión", async () => {
  for (const [db, empresaId] of [
    [auth("alice"), "EMP_B"],
    [auth("inactive"), "EMP_A"],
    [env.unauthenticatedContext().firestore(), "EMP_A"],
  ]) {
    const batch = writeBatch(db);
    batch.set(doc(db, "TBL_DOCUMENTOS/no_autorizado"), {empresaId});
    batch.set(doc(db, "TBL_DOCUMENTOS_VERSIONES/no_autorizado"), {
      empresaId, docId: "no_autorizado",
    });
    await assertFails(batch.commit());
  }
});

test("no se puede cambiar el padre ni la empresa de una versión existente", async () => {
  const db = auth("multi");
  await assertFails(updateDoc(doc(db, "TBL_DOCUMENTOS_VERSIONES/ver_a"), {docId: "doc_b"}));
  await assertFails(updateDoc(doc(db, "TBL_DOCUMENTOS_VERSIONES/ver_a"), {empresaId: "EMP_B"}));
});
