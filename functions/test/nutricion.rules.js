/**
 * Nutrición por empresa (28 sep 2026). Pacientes, valoraciones, patologías
 * e historial son datos de salud y solo pedían sesión: cualquiera, de
 * cualquier empresa, los leía y escribía. Ahora cada documento es de su
 * empresa, de nadie inhabilitado en ella, y no cambia de empresa.
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
  limit,
  orderBy,
  query,
  setDoc,
  updateDoc,
  where,
} = require("firebase/firestore");

const projectId = "capital-uspec-nutricion";
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

const usuarios = {
  nutriA: {empresas: ["EMP_A"], empresasDetalle: {EMP_A: {}}},
  empleadoA: {empresas: ["EMP_A"], empresasDetalle: {EMP_A: {}}},
  ajeno: {empresas: ["EMP_B"], empresasDetalle: {EMP_B: {}}},
  retirada: {
    empresas: ["EMP_A"],
    empresasDetalle: {EMP_A: {estadoLaboral: "inactivo"}},
  },
  dev: {desarrollador: true},
};

const paciente = {
  empresaId: "EMP_A",
  documento: "123",
  nombre: "Paciente de prueba",
  establecimiento: "Buen Pastor",
  patologias: ["HTA"],
};

test.before(async () => {
  assert.ok(
    process.env.FIRESTORE_EMULATOR_HOST,
    "Ejecuta estas pruebas mediante Firebase Emulator Suite."
  );
  env = await initializeTestEnvironment({projectId, firestore: {rules}});
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await Promise.all([
      ...Object.entries(usuarios).map(([id, data]) =>
        setDoc(doc(db, `TBL_USUARIOS/${id}`), data)
      ),
      setDoc(doc(db, "TBL_PACIENTES/p1"), paciente),
      setDoc(doc(db, "TBL_VALORACIONES_NUTRICION/v1"), {
        empresaId: "EMP_A", pacienteId: "p1", imc: 27.1,
      }),
      setDoc(doc(db, "TBL_MENUS/m1"), {empresaId: "EMP_A", nombre: "Semana 1"}),
      setDoc(doc(db, "TBL_DIETAS/D1"), {empresaId: "EMP_B", codigo: "D1"}),
      setDoc(doc(db, "TBL_EVALUACIONES_DIAGNOSTICAS/e1"), {
        empresaId: "EMP_A", pacienteId: "p1", diagnosticoMedicoCie11: "5A11",
      }),
      setDoc(doc(db, "TBL_CITAS_NUTRICION/c1"), {
        empresaId: "EMP_A", userId: "empleadoA", estado: "agendada",
      }),
      setDoc(doc(db, "TBL_HISTORIAL_NUTRICION/EMP_A-p1/registros/r1"), {
        empresaId: "EMP_A", pacienteId: "p1", registradoEn: new Date(),
      }),
    ]);
  });
});

test.after(async () => {
  await env?.cleanup();
});

test("los pacientes de una empresa no los ve ni toca otra", async () => {
  const ajeno = auth("ajeno");
  await assertFails(getDoc(doc(ajeno, "TBL_PACIENTES/p1")));
  await assertFails(getDoc(doc(ajeno, "TBL_VALORACIONES_NUTRICION/v1")));
  await assertFails(
    getDocs(query(
      collection(ajeno, "TBL_PACIENTES"),
      where("empresaId", "==", "EMP_A")
    ))
  );
  await assertFails(updateDoc(doc(ajeno, "TBL_PACIENTES/p1"), {nombre: "X"}));
  await assertFails(deleteDoc(doc(ajeno, "TBL_PACIENTES/p1")));
  // Sin filtro por empresa, la consulta no pasa.
  await assertFails(getDocs(collection(auth("nutriA"), "TBL_PACIENTES")));
});

test("en su empresa se trabaja normal", async () => {
  const nutri = auth("nutriA");
  await assertSucceeds(getDoc(doc(nutri, "TBL_PACIENTES/p1")));
  await assertSucceeds(
    getDocs(query(
      collection(nutri, "TBL_PACIENTES"),
      where("empresaId", "==", "EMP_A"),
      where("establecimiento", "==", "Buen Pastor")
    ))
  );
  await assertSucceeds(
    setDoc(doc(nutri, "TBL_PACIENTES/p2"), {...paciente, documento: "456"})
  );
  await assertSucceeds(
    setDoc(doc(nutri, "TBL_PACIENTES/p1"), {peso: 70}, {merge: true})
  );
  // Guardar un menú manda solo lo que cambia: la empresa se conserva.
  await assertSucceeds(
    setDoc(doc(nutri, "TBL_MENUS/m1"), {nombre: "Semana 2"}, {merge: true})
  );
  // Preguntar por un id que no existe responde vacío.
  await assertSucceeds(getDoc(doc(nutri, "TBL_FIRMAS/EMP_A-nutriA")));
  await assertSucceeds(
    setDoc(doc(nutri, "TBL_FIRMAS/EMP_A-nutriA"), {
      empresaId: "EMP_A", userId: "nutriA", urlFirma: "https://example.com/f.png",
    })
  );
});

test("un documento no cambia de empresa ni se crea en otra", async () => {
  const nutri = auth("nutriA");
  await assertFails(
    updateDoc(doc(nutri, "TBL_PACIENTES/p1"), {empresaId: "EMP_B"})
  );
  await assertFails(
    setDoc(doc(nutri, "TBL_PACIENTES/p3"), {...paciente, empresaId: "EMP_B"})
  );
  await assertFails(
    setDoc(doc(nutri, "TBL_PACIENTES/p4"), {nombre: "Sin empresa"})
  );
  // Las dietas usan el código como id: antes una empresa le pisaba la
  // dieta a otra con el mismo código.
  await assertFails(
    setDoc(doc(nutri, "TBL_DIETAS/D1"), {
      empresaId: "EMP_A", codigo: "D1", nombre: "Mía",
    }, {merge: true})
  );
});

test("inhabilitada: no ve pacientes de su empresa", async () => {
  const db = auth("retirada");
  await assertFails(getDoc(doc(db, "TBL_PACIENTES/p1")));
  await assertFails(
    setDoc(doc(db, "TBL_VALORACIONES_NUTRICION/v2"), {
      empresaId: "EMP_A", pacienteId: "p1",
    })
  );
});

test("historial del paciente: se lee y se agrega, no se reescribe", async () => {
  const nutri = auth("nutriA");
  const registros = collection(nutri, "TBL_HISTORIAL_NUTRICION/EMP_A-p1/registros");
  await assertSucceeds(
    getDocs(query(registros, orderBy("registradoEn", "desc"), limit(20)))
  );
  await assertSucceeds(
    addDoc(registros, {empresaId: "EMP_A", pacienteId: "p1", nota: "Control"})
  );
  await assertFails(
    addDoc(registros, {empresaId: "EMP_B", pacienteId: "p1", nota: "Otra"})
  );
  await assertFails(
    updateDoc(doc(nutri, "TBL_HISTORIAL_NUTRICION/EMP_A-p1/registros/r1"), {
      nota: "Cambiada",
    })
  );
  const ajenos = collection(auth("ajeno"), "TBL_HISTORIAL_NUTRICION/EMP_A-p1/registros");
  await assertFails(getDocs(query(ajenos, orderBy("registradoEn", "desc"), limit(20))));
  await assertFails(addDoc(ajenos, {empresaId: "EMP_A", nota: "Colada"}));
});

test("las citas del calendario de Inicio siguen cargando", async () => {
  await assertSucceeds(
    getDocs(query(
      collection(auth("empleadoA"), "TBL_CITAS_NUTRICION"),
      where("userId", "==", "empleadoA"),
      where("empresaId", "==", "EMP_A"),
      where("estado", "==", "agendada")
    ))
  );
  await assertSucceeds(getDoc(doc(auth("empleadoA"), "TBL_CITAS_NUTRICION/c1")));
  await assertFails(
    getDocs(query(
      collection(auth("ajeno"), "TBL_CITAS_NUTRICION"),
      where("userId", "==", "empleadoA"),
      where("empresaId", "==", "EMP_A")
    ))
  );
  // Desarrollo entra a cualquier empresa.
  await assertSucceeds(getDoc(doc(auth("dev"), "TBL_PACIENTES/p1")));
});

test("evaluaciones diagnósticas: solo en su empresa", async () => {
  await assertSucceeds(
    getDocs(query(
      collection(auth("empleadoA"), "TBL_EVALUACIONES_DIAGNOSTICAS"),
      where("empresaId", "==", "EMP_A"),
      where("pacienteId", "==", "p1")
    ))
  );
  await assertFails(
    getDoc(doc(auth("ajeno"), "TBL_EVALUACIONES_DIAGNOSTICAS/e1"))
  );
  await assertFails(
    setDoc(doc(auth("ajeno"), "TBL_EVALUACIONES_DIAGNOSTICAS/e2"), {
      empresaId: "EMP_A", pacienteId: "p1",
    })
  );
  await assertSucceeds(
    setDoc(doc(auth("empleadoA"), "TBL_EVALUACIONES_DIAGNOSTICAS/e3"), {
      empresaId: "EMP_A", pacienteId: "p1",
    })
  );
});
