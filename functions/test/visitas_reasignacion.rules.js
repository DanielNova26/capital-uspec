/**
 * Reglas de Visitas, 1 oct 2026:
 * - Una visita que no se cumplió (pasó su día) no la mueve el jefe por su
 *   cuenta: primero el profesional pide la reasignación, que queda como
 *   registro del incumplimiento. Con la solicitud pendiente, sí.
 * - El maestro de ubicaciones completo solo lo listan quienes programan o
 *   lo administran; el profesional lee por id la de su establecimiento.
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
  arrayUnion,
  collection,
  doc,
  getDoc,
  getDocs,
  query,
  setDoc,
  updateDoc,
  where,
} = require("firebase/firestore");

const projectId = "capital-uspec-visitas-reasignacion";
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

const AREA = "EMP_A_calidad";

function dia(offset) {
  const d = new Date();
  d.setHours(0, 0, 0, 0);
  d.setDate(d.getDate() + offset);
  return d;
}

function visita(extra = {}) {
  return {
    empresaId: "EMP_A",
    formatoId: "",
    formatoNombre: "",
    esPrueba: false,
    areaId: AREA,
    areaNombre: "Calidad",
    centroId: "C1",
    centroNombre: "Buen Pastor",
    subcentroId: "",
    subcentroNombre: "",
    profesionalId: "prof",
    profesionalNombre: "Ana",
    asignadoPorId: "jefe",
    asignadoPorNombre: "Elvis",
    fechaProgramada: dia(0),
    estado: "programada",
    reprogramaciones: [],
    ...extra,
  };
}

function solicitud(extra = {}) {
  return {
    fecha: dia(2),
    motivo: "Incapacidad médica",
    porId: "prof",
    porNombre: "Ana",
    estado: "pendiente",
    tipo: "reasignacion",
    at: new Date(),
    ...extra,
  };
}

function mover(a, {incumplida = false} = {}) {
  return {
    fechaProgramada: a,
    reprogramaciones: arrayUnion({
      de: dia(-1), a, motivo: "x", porId: "jefe", porNombre: "Elvis",
      at: new Date(), ...(incumplida ? {incumplida: true} : {}),
    }),
  };
}

test.before(async () => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST, "Usa el emulador.");
  env = await initializeTestEnvironment({projectId, firestore: {rules}});
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const miembro = (nombre) => ({nombre, empresas: ["EMP_A"], empresaId: "EMP_A"});
    await Promise.all([
      setDoc(doc(db, "TBL_USUARIOS/jefe"), miembro("Elvis")),
      setDoc(doc(db, "TBL_USUARIOS/prof"), miembro("Ana")),
      setDoc(doc(db, "TBL_USUARIOS/dev"), {...miembro("Dev"), desarrollador: true}),
      setDoc(doc(db, "TBL_VISITAS_ROLES/EMP_A_jefe"), {
        empresaId: "EMP_A", userId: "jefe", rol: "jefe", areaId: AREA,
      }),
      setDoc(doc(db, "TBL_VISITAS_ROLES/EMP_A_prof"), {
        empresaId: "EMP_A", userId: "prof", rol: "profesional", areaId: AREA,
      }),
      setDoc(doc(db, "TBL_VISITAS/manana"), visita({fechaProgramada: dia(1)})),
      setDoc(doc(db, "TBL_VISITAS/ayer"), visita({fechaProgramada: dia(-1)})),
      setDoc(doc(db, "TBL_VISITAS/ayerPedida"), visita({
        fechaProgramada: dia(-1), solicitudCambioFecha: solicitud(),
      })),
      setDoc(doc(db, "TBL_VISITAS/ayerRechazada"), visita({
        fechaProgramada: dia(-1),
        solicitudCambioFecha: solicitud({estado: "rechazada"}),
      })),
      setDoc(doc(db, "TBL_VISITAS/pruebaAyer"), visita({
        fechaProgramada: dia(-1), esPrueba: true,
      })),
      setDoc(doc(db, "TBL_VISITAS_UBICACIONES/EMP_A_C1"), {
        empresaId: "EMP_A", centroId: "C1", centroNombre: "Buen Pastor",
        subcentroId: "", lat: 4.68, lng: -74.07, radioMetros: 150,
      }),
    ]);
  });
});

test.after(async () => {
  await env.cleanup();
});

test("el jefe mueve una visita que todavía no pasa", async () => {
  await assertSucceeds(updateDoc(doc(auth("jefe"), "TBL_VISITAS/manana"),
    mover(dia(3))));
});

test("una visita incumplida no la mueve el jefe sin solicitud", async () => {
  await assertFails(updateDoc(doc(auth("jefe"), "TBL_VISITAS/ayer"),
    mover(dia(2), {incumplida: true})));
  // Una solicitud ya rechazada no cuenta: tiene que pedirla de nuevo.
  await assertFails(updateDoc(doc(auth("jefe"), "TBL_VISITAS/ayerRechazada"),
    mover(dia(2), {incumplida: true})));
});

test("el profesional pide la reasignación y el jefe la aprueba", async () => {
  await assertSucceeds(updateDoc(doc(auth("prof"), "TBL_VISITAS/ayer"), {
    solicitudCambioFecha: solicitud(),
  }));
  await assertSucceeds(updateDoc(doc(auth("jefe"), "TBL_VISITAS/ayerPedida"), {
    ...mover(dia(2), {incumplida: true}),
    solicitudCambioFecha: solicitud({
      estado: "aprobada", respondidaPorId: "jefe", respondidaPorNombre: "Elvis",
    }),
  }));
});

test("las visitas de prueba se siguen moviendo", async () => {
  await assertSucceeds(updateDoc(doc(auth("jefe"), "TBL_VISITAS/pruebaAyer"),
    mover(dia(2))));
});

test("el profesional lee la ubicación de su establecimiento, no el maestro", async () => {
  const prof = auth("prof");
  await assertSucceeds(getDoc(doc(prof, "TBL_VISITAS_UBICACIONES/EMP_A_C1")));
  await assertFails(getDocs(query(
    collection(prof, "TBL_VISITAS_UBICACIONES"),
    where("empresaId", "==", "EMP_A")
  )));
});

test("el jefe y Desarrollo sí listan el maestro", async () => {
  for (const quien of ["jefe", "dev"]) {
    const snap = await assertSucceeds(getDocs(query(
      collection(auth(quien), "TBL_VISITAS_UBICACIONES"),
      where("empresaId", "==", "EMP_A")
    )));
    assert.equal(snap.size, 1, quien);
  }
});
