/**
 * Reglas de TBL_INTERVENTORIA_VISITAS y TBL_INTERVENTORIA_HALLAZGOS en el
 * flujo de revisión (Fase 2): guardar el borrador actualiza el acta y
 * sincroniza los hallazgos (crea, actualiza y BORRA los huérfanos).
 *
 * 11 sep 2026: el administrador veía "No se guardó el borrador:
 * permission-denied" al escribir observaciones. Es la misma escritura que
 * perdió las notas de Kary en Ramiriquí.
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
const {doc, getDoc, setDoc, updateDoc, deleteDoc, writeBatch, collection, query, where, getDocs, runTransaction} = require("firebase/firestore");

const projectId = "capital-uspec-interventoria-visitas";
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
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST, "Usa el emulador.");
  env = await initializeTestEnvironment({projectId, firestore: {rules}});
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await Promise.all([
      // Como el desarrollador real y como Kary: miembros de EMP_A por `empresas`.
      setDoc(doc(db, "TBL_USUARIOS/daniel"), {
        nombre: "Daniel",
        role: "rutas_desarrollador",
        roleId: "EMP_OTRA_rutas_desarrollador",
        empresas: ["EMP_OTRA", "EMP_A"],
        empresasDetalle: {EMP_A: {cargo: "Desarrollador"}},
      }),
      setDoc(doc(db, "TBL_USUARIOS/kary"), {
        nombre: "Kary",
        empresas: ["EMP_A"],
        empresaId: "EMP_A",
        empresasDetalle: {EMP_A: {cargo: "Admin"}},
      }),
      setDoc(doc(db, "TBL_INTERVENTORIA_ROLES/EMP_A_kary"), {
        empresaId: "EMP_A", userId: "kary", rol: "admin_interventoria",
      }),
      setDoc(doc(db, "TBL_INTERVENTORIA_VISITAS/v1"), {
        empresaId: "EMP_A",
        centroCostoId: "c1",
        faseActa: "puntajes",
        itemsEvaluacion: {horario: {valor: 100, observacionesDetalle: []}},
      }),
      setDoc(doc(db, "TBL_INTERVENTORIA_HALLAZGOS/h_huerfano"), {
        empresaId: "EMP_A", visitaId: "v1", fuente: "acta", grupoId: "horario_obs0", tareaId: "",
      }),
      setDoc(doc(db, "TBL_INTERVENTORIA_HALLAZGOS/h_huerfano2"), {
        empresaId: "EMP_A", visitaId: "v1", fuente: "acta", grupoId: "horario_obs1", tareaId: "",
      }),
    ]);
  });
});

test.after(async () => {
  await env?.cleanup();
});

test("Kary (admin_interventoria) guarda el borrador del acta", async () => {
  await assertSucceeds(
    updateDoc(doc(auth("kary"), "TBL_INTERVENTORIA_VISITAS/v1"), {
      "itemsEvaluacion.horario.observacionesDetalle": [{texto: "Llegó tarde"}],
    })
  );
});

test("el desarrollador guarda el borrador del acta", async () => {
  await assertSucceeds(
    updateDoc(doc(auth("daniel"), "TBL_INTERVENTORIA_VISITAS/v1"), {
      "itemsEvaluacion.horario.observacionesDetalle": [{texto: "Otra"}],
    })
  );
});

test("sincronizar hallazgos: crear y actualizar pasan", async () => {
  const db = auth("kary");
  await assertSucceeds(
    setDoc(doc(db, "TBL_INTERVENTORIA_HALLAZGOS/h_nuevo"), {
      empresaId: "EMP_A", visitaId: "v1", fuente: "acta", grupoId: "horario_obs9", tareaId: "",
    })
  );
  await assertSucceeds(
    updateDoc(doc(db, "TBL_INTERVENTORIA_HALLAZGOS/h_huerfano"), {descripcion: "x"})
  );
});

test("sincronizar hallazgos: borrar un huérfano sin tarea pasa", async () => {
  // `_autoCrearHallazgosDesdeItems` borra los hallazgos 'acta' sin tarea que
  // ya no tienen observación. Si esto falla, falla TODO el batch y el
  // borrador no se guarda: "permission-denied".
  await assertSucceeds(
    deleteDoc(doc(auth("kary"), "TBL_INTERVENTORIA_HALLAZGOS/h_huerfano"))
  );
});

test("el batch completo de la revisión (update acta + borrar huérfano) pasa", async () => {
  const db = auth("daniel");
  const batch = writeBatch(db);
  batch.update(doc(db, "TBL_INTERVENTORIA_VISITAS/v1"), {faseActa: "puntajes"});
  batch.delete(doc(db, "TBL_INTERVENTORIA_HALLAZGOS/h_huerfano2"));
  await assertSucceeds(batch.commit());
});

test("un hallazgo con tarea asignada no se borra desde el cliente", async () => {
  await env.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "TBL_INTERVENTORIA_HALLAZGOS/h_con_tarea"), {
      empresaId: "EMP_A", visitaId: "v1", fuente: "acta", grupoId: "x", tareaId: "t1",
    });
  });
  await assertFails(
    deleteDoc(doc(auth("kary"), "TBL_INTERVENTORIA_HALLAZGOS/h_con_tarea"))
  );
});

test("la consulta de hallazgos de un acta pasa solo si filtra por empresa", async () => {
  // La regla de lectura mira `resource.data.empresaId`; Firestore exige
  // poder probarla con los filtros de la consulta. Sin `empresaId` en el
  // where, la consulta entera es permission-denied aunque cada documento
  // sea legible. Así fallaba el guardado del borrador (11 sep 2026).
  const db = auth("kary");
  await assertFails(
    getDocs(query(
      collection(db, "TBL_INTERVENTORIA_HALLAZGOS"),
      where("visitaId", "==", "v1"),
      where("fuente", "==", "acta")
    ))
  );
  await assertSucceeds(
    getDocs(query(
      collection(db, "TBL_INTERVENTORIA_HALLAZGOS"),
      where("empresaId", "==", "EMP_A"),
      where("visitaId", "==", "v1"),
      where("fuente", "==", "acta")
    ))
  );
});

test("registrar un acta nueva: leer el id que aun no existe no se deniega", async () => {
  // Registrar acta (Fase 1) hace una transacción: lee el documento con el id
  // nuevo para comprobar que no exista y luego lo crea. Con la regla
  // `belongsToCompany(resource.data.empresaId)`, un documento inexistente no
  // da "no existe": `resource` es nulo, la regla falla y Firestore deniega.
  // En web eso se ve como "Dart exception thrown from converted Future" y
  // NINGÚN registrador pudo guardar actas desde el 11 sep 2026.
  const db = auth("kary");
  await assertSucceeds(getDoc(doc(db, "TBL_INTERVENTORIA_VISITAS/no_existe_aun")));
  await assertSucceeds(runTransaction(db, async (tx) => {
    const ref = doc(db, "TBL_INTERVENTORIA_VISITAS/acta_nueva_tx");
    const snap = await tx.get(ref);
    if (snap.exists()) throw new Error("ya existe");
    tx.set(ref, {empresaId: "EMP_A", centroCostoId: "c1", faseActa: "puntajes"});
  }));
});

test("leer un acta de otra empresa sigue denegado", async () => {
  await env.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "TBL_INTERVENTORIA_VISITAS/ajena"), {
      empresaId: "EMP_B", centroCostoId: "c9",
    });
  });
  await assertFails(getDoc(doc(auth("kary"), "TBL_INTERVENTORIA_VISITAS/ajena")));
});
