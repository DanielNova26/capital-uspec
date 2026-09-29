/**
 * Logs de Admin (29 sep 2026): `TBL_MIGRATIONS_LOGS` estaba en la regla
 * general y cualquiera la leía, la editaba o la borraba. Ahora la lee Admin
 * de esa empresa (o Desarrollo), se agrega a nombre propio con la hora del
 * servidor y nadie la cambia.
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
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  orderBy,
  query,
  serverTimestamp,
  setDoc,
  Timestamp,
  updateDoc,
  where,
} = require("firebase/firestore");

const projectId = "capital-uspec-admin-logs";
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

function registro(adminUserId, extra = {}) {
  return {
    adminUserId,
    empresaId: "EMP_A",
    action: "normalizeCentroForUsers",
    scanned: 3,
    updated: 1,
    dryRun: false,
    createdAt: serverTimestamp(),
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
      setDoc(doc(db, "TBL_USUARIOS/retirado"), {
        empresas: ["EMP_A"],
        estado: "inactivo",
        appsPorEmpresa: true,
        empresasDetalle: {EMP_A: {apps: ["admindashboard"]}},
      }),
      setDoc(doc(db, "TBL_MIGRATIONS_LOGS/l1"), {
        adminUserId: "adminA",
        empresaId: "EMP_A",
        action: "deleteAllTasksForEmpresa",
        createdAt: Timestamp.now(),
      }),
    ]);
  });
});

test.after(async () => {
  await env?.cleanup();
});

test("la lee Admin de su empresa; nadie más", async () => {
  await assertSucceeds(getDoc(doc(auth("adminA"), "TBL_MIGRATIONS_LOGS/l1")));
  await assertSucceeds(
    getDocs(query(
      collection(auth("adminA"), "TBL_MIGRATIONS_LOGS"),
      where("empresaId", "==", "EMP_A"),
      orderBy("createdAt", "desc")
    ))
  );
  await assertFails(getDoc(doc(auth("comunA"), "TBL_MIGRATIONS_LOGS/l1")));
  await assertFails(getDoc(doc(auth("adminB"), "TBL_MIGRATIONS_LOGS/l1")));
  await assertFails(
    getDocs(query(
      collection(auth("adminB"), "TBL_MIGRATIONS_LOGS"),
      where("empresaId", "==", "EMP_A")
    ))
  );
});

test("se agrega a nombre propio y con la hora del servidor", async () => {
  await assertSucceeds(
    setDoc(doc(auth("adminA"), "TBL_MIGRATIONS_LOGS/nuevo"), registro("adminA"))
  );
  // Multiempresa registra con la empresa de referencia de la persona, o '*'.
  await assertSucceeds(
    setDoc(doc(auth("adminA"), "TBL_MIGRATIONS_LOGS/todas"),
      registro("adminA", {empresaId: "*", action: "multiempresaFijarModulos"}))
  );
  await assertFails(
    setDoc(doc(auth("comunA"), "TBL_MIGRATIONS_LOGS/falso"), registro("adminA"))
  );
  await assertFails(
    setDoc(doc(auth("adminA"), "TBL_MIGRATIONS_LOGS/fecha"),
      registro("adminA", {createdAt: Timestamp.fromDate(new Date(2020, 0, 1))}))
  );
  await assertFails(
    setDoc(doc(auth("adminA"), "TBL_MIGRATIONS_LOGS/sinaccion"),
      registro("adminA", {action: ""}))
  );
  await assertFails(
    setDoc(doc(auth("retirado"), "TBL_MIGRATIONS_LOGS/retirado"),
      registro("retirado"))
  );
});

test("nadie la edita ni la borra", async () => {
  await assertFails(
    updateDoc(doc(auth("adminA"), "TBL_MIGRATIONS_LOGS/l1"), {updated: 0})
  );
  await assertFails(deleteDoc(doc(auth("adminA"), "TBL_MIGRATIONS_LOGS/l1")));
  await assertFails(deleteDoc(doc(auth("comunA"), "TBL_MIGRATIONS_LOGS/l1")));
});
