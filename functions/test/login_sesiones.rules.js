/**
 * Registro de ingresos (29 sep 2026): `TBL_LOGIN_SESIONES` estaba en la
 * regla general y cualquiera veía y borraba los ingresos de todas las
 * empresas. Ahora cada quien agrega el suyo y lo lee Admin de esa empresa.
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
  addDoc,
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  query,
  setDoc,
  Timestamp,
  updateDoc,
  where,
} = require("firebase/firestore");

const projectId = "capital-uspec-login-sesiones";
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

function ingreso(userId, extra = {}) {
  return {
    empresaId: "EMP_A",
    userId,
    nombre: "Ana",
    source: "password",
    platform: "web",
    dispositivo: {tipo: "celular", marca: "Samsung", modelo: "SM-A515F"},
    loginAt: Timestamp.now(),
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
      setDoc(doc(db, "TBL_USUARIOS/ana"), {
        empresas: ["EMP_A"], empresasDetalle: {EMP_A: {}},
      }),
      setDoc(doc(db, "TBL_USUARIOS/adminB"), {
        empresas: ["EMP_B"],
        appsPorEmpresa: true,
        empresasDetalle: {EMP_B: {apps: ["admindashboard"]}},
      }),
      setDoc(doc(db, "TBL_LOGIN_SESIONES/s1"), ingreso("ana")),
    ]);
  });
});

test.after(async () => {
  await env?.cleanup();
});

test("cada quien registra su propio ingreso", async () => {
  await assertSucceeds(
    addDoc(collection(auth("ana"), "TBL_LOGIN_SESIONES"), ingreso("ana"))
  );
  await assertFails(
    addDoc(collection(auth("ana"), "TBL_LOGIN_SESIONES"), ingreso("adminA"))
  );
  await assertFails(
    addDoc(collection(auth("ana"), "TBL_LOGIN_SESIONES"),
      ingreso("ana", {empresaId: ""}))
  );
});

test("lo lee Admin de la empresa; ni el personal ni otra empresa", async () => {
  await assertSucceeds(getDoc(doc(auth("adminA"), "TBL_LOGIN_SESIONES/s1")));
  await assertSucceeds(
    getDocs(query(
      collection(auth("adminA"), "TBL_LOGIN_SESIONES"),
      where("empresaId", "==", "EMP_A")
    ))
  );
  await assertFails(getDoc(doc(auth("ana"), "TBL_LOGIN_SESIONES/s1")));
  await assertFails(getDoc(doc(auth("adminB"), "TBL_LOGIN_SESIONES/s1")));
});

test("nadie lo edita ni lo borra", async () => {
  await assertFails(
    updateDoc(doc(auth("adminA"), "TBL_LOGIN_SESIONES/s1"), {nombre: "x"})
  );
  await assertFails(deleteDoc(doc(auth("ana"), "TBL_LOGIN_SESIONES/s1")));
  await assertFails(deleteDoc(doc(auth("adminA"), "TBL_LOGIN_SESIONES/s1")));
});
