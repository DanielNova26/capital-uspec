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
  query,
  setDoc,
  updateDoc,
  where,
} = require("firebase/firestore");

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
    projectId: "capital-uspec-whatsapp-auditoria",
    firestore: {rules},
  });
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await Promise.all([
      setDoc(doc(db, "TBL_USUARIOS/adminA"), {
        empresas: ["EMP_A"],
        appsPorEmpresa: true,
        empresasDetalle: {EMP_A: {apps: ["admindashboard"]}},
      }),
      setDoc(doc(db, "TBL_USUARIOS/adminB"), {
        empresas: ["EMP_B"],
        appsPorEmpresa: true,
        empresasDetalle: {EMP_B: {apps: ["admindashboard"]}},
      }),
      setDoc(doc(db, "TBL_USUARIOS/memberA"), {
        empresas: ["EMP_A"],
      }),
      setDoc(doc(db, "TBL_USUARIOS/correoA"), {
        empresas: ["EMP_A"],
        appsPorEmpresa: true,
        empresasDetalle: {EMP_A: {apps: ["correodashboard"]}},
      }),
      setDoc(doc(db, "TBL_USUARIOS/revokedCorreoA"), {
        empresas: ["EMP_A"],
        apps: ["correodashboard"],
        appsPorEmpresa: true,
        empresasDetalle: {EMP_A: {apps: []}},
      }),
      setDoc(doc(db, "TBL_USUARIOS/disabledA"), {
        empresas: ["EMP_A"],
        appsPorEmpresa: true,
        empresasDetalle: {EMP_A: {apps: ["admindashboard"], activo: false}},
      }),
      setDoc(doc(db, "TBL_USUARIOS/dev"), {desarrollador: true}),
      setDoc(doc(db, "TBL_WHATSAPP_AUDITORIA/sendA"), {
        empresaId: "EMP_A",
        action: "send_accepted",
        details: {providerMessageId: "wamid.A"},
      }),
      setDoc(doc(db, "TBL_WHATSAPP_META_ESTADOS/statusA"), {
        messageId: "wamid.A",
        status: "failed",
      }),
      setDoc(doc(db, "TBL_CORREO_ALERTAS/alertA"), {
        empresaId: "EMP_A",
        destinatario: "573001234567",
        mensaje: "Aviso de prueba",
        estado: "enviado",
      }),
    ]);
  });
});

test.after(async () => {
  await env?.cleanup();
});

test("solo Admin de la empresa o Desarrollo lee la auditoría", async () => {
  const auditPath = "TBL_WHATSAPP_AUDITORIA/sendA";
  await assertSucceeds(getDoc(doc(auth("adminA"), auditPath)));
  await assertSucceeds(getDoc(doc(auth("dev"), auditPath)));
  await assertSucceeds(getDocs(query(
    collection(auth("adminA"), "TBL_WHATSAPP_AUDITORIA"),
    where("empresaId", "==", "EMP_A")
  )));
  await assertFails(getDoc(doc(auth("adminB"), auditPath)));
  await assertFails(getDoc(doc(auth("memberA"), auditPath)));
  await assertFails(getDoc(doc(auth("disabledA"), auditPath)));
  await assertFails(getDocs(collection(auth("adminA"), "TBL_WHATSAPP_AUDITORIA")));
});

test("ningún cliente modifica la auditoría ni accede a estados crudos", async () => {
  const auditPath = "TBL_WHATSAPP_AUDITORIA/sendA";
  const statusPath = "TBL_WHATSAPP_META_ESTADOS/statusA";
  const adminA = auth("adminA");
  const dev = auth("dev");
  await assertFails(updateDoc(doc(adminA, auditPath), {action: "delivery_status"}));
  await assertFails(deleteDoc(doc(dev, auditPath)));
  await assertFails(setDoc(doc(dev, "TBL_WHATSAPP_AUDITORIA/fake"), {
    empresaId: "EMP_A", action: "send_accepted",
  }));
  await assertFails(getDoc(doc(dev, statusPath)));
  await assertFails(setDoc(doc(adminA, statusPath), {status: "delivered"}));
  await assertFails(deleteDoc(doc(dev, statusPath)));
});

test("solo Correo, Admin o Desarrollo de la empresa lee avisos", async () => {
  const alertPath = "TBL_CORREO_ALERTAS/alertA";
  await assertSucceeds(getDoc(doc(auth("correoA"), alertPath)));
  await assertSucceeds(getDoc(doc(auth("adminA"), alertPath)));
  await assertSucceeds(getDoc(doc(auth("dev"), alertPath)));
  await assertSucceeds(getDocs(query(
    collection(auth("correoA"), "TBL_CORREO_ALERTAS"),
    where("empresaId", "==", "EMP_A")
  )));
  await assertFails(getDoc(doc(auth("memberA"), alertPath)));
  await assertFails(getDoc(doc(auth("adminB"), alertPath)));
  await assertFails(getDoc(doc(auth("revokedCorreoA"), alertPath)));
  await assertFails(getDoc(doc(auth("disabledA"), alertPath)));
  await assertFails(getDocs(collection(auth("correoA"), "TBL_CORREO_ALERTAS")));
});

test("solo el servidor registra y actualiza avisos", async () => {
  const alertPath = "TBL_CORREO_ALERTAS/alertA";
  await assertFails(setDoc(doc(auth("correoA"), "TBL_CORREO_ALERTAS/fake"), {
    empresaId: "EMP_A", estado: "enviado",
  }));
  await assertFails(updateDoc(doc(auth("adminA"), alertPath), {
    estado: "entregado",
  }));
  await assertFails(deleteDoc(doc(auth("dev"), alertPath)));
});
