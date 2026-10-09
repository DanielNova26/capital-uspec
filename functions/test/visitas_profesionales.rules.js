/**
 * Reglas de Visitas de profesionales (25 sep 2026):
 * - El firmante del establecimiento lee y firma SOLO la visita donde el
 *   profesional lo designó, y solo su firma.
 * - El profesional puede designar al firmante aunque ya haya firmado él.
 * - Grupos de profesionales: los administra el jefe de su área.
 * - Roles: se acepta `firmante`; el jefe solo da el rol Profesional.
 * - Programar varias fechas en un solo lote no revienta el tope de lecturas
 *   de las reglas.
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
  doc,
  getDoc,
  getDocs,
  query,
  setDoc,
  updateDoc,
  where,
  writeBatch,
} = require("firebase/firestore");

const projectId = "capital-uspec-visitas-profesionales";
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

const formato = {
  empresaId: "EMP_A",
  areaId: "EMP_A_nutricion",
  areaNombre: "Nutrición",
  nombre: "Visita de nutrición",
  version: 1,
  estado: "vigente",
  predeterminado: true,
  items: [{id: "n1", orden: 1, texto: "Minuta publicada"}],
  partes: [],
  tablas: [],
  cargos: [],
};

function visitaNueva(fecha) {
  return {
    empresaId: "EMP_A",
    formatoId: "F1",
    formatoNombre: formato.nombre,
    formatoAsignado: formato,
    esPrueba: false,
    areaId: "EMP_A_nutricion",
    areaNombre: "Nutrición",
    centroId: "C1",
    centroNombre: "Buen Pastor",
    subcentroId: "",
    subcentroNombre: "",
    profesionalId: "prof",
    profesionalNombre: "Profesional",
    asignadoPorId: "jefe",
    asignadoPorNombre: "Jefe",
    fechaProgramada: fecha,
    estado: "programada",
  };
}

test.before(async () => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST, "Usa el emulador.");
  env = await initializeTestEnvironment({projectId, firestore: {rules}});
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const miembro = (nombre) => ({nombre, empresas: ["EMP_A"], empresaId: "EMP_A"});
    await Promise.all([
      setDoc(doc(db, "TBL_USUARIOS/dev"), {
        ...miembro("Dev"), desarrollador: true,
      }),
      setDoc(doc(db, "TBL_USUARIOS/jefe"), miembro("Jefe")),
      setDoc(doc(db, "TBL_USUARIOS/prof"), miembro("Profesional")),
      setDoc(doc(db, "TBL_USUARIOS/firm"), miembro("Firmante")),
      setDoc(doc(db, "TBL_USUARIOS/otro"), miembro("Otro")),
      setDoc(doc(db, "TBL_VISITAS_ROLES/EMP_A_jefe"), {
        empresaId: "EMP_A", userId: "jefe", rol: "jefe",
        areaId: "EMP_A_nutricion",
      }),
      setDoc(doc(db, "TBL_VISITAS_ROLES/EMP_A_prof"), {
        empresaId: "EMP_A", userId: "prof", rol: "profesional",
        areaId: "EMP_A_nutricion",
      }),
      setDoc(doc(db, "TBL_VISITAS_ROLES/EMP_A_firm"), {
        empresaId: "EMP_A", userId: "firm", rol: "firmante", areaId: "",
      }),
      setDoc(doc(db, "TBL_VISITAS_FORMATOS/F1"), formato),
      setDoc(doc(db, "TBL_VISITAS/v1"), {
        ...visitaNueva(new Date(2026, 8, 25)),
        estado: "en_curso",
        respuestas: {n1: {resultado: "cumple"}},
        firmanteEstablecimientoId: "firm",
        firmaProfesional: {nombre: "Profesional", modo: "dibujada"},
        firmaEstablecimiento: null,
      }),
      setDoc(doc(db, "TBL_VISITAS/v2"), {
        ...visitaNueva(new Date(2026, 8, 26)),
        estado: "en_curso",
        firmanteEstablecimientoId: "otro",
        firmaProfesional: null,
        firmaEstablecimiento: null,
      }),
      setDoc(doc(db, "TBL_VISITAS/v3"), {
        ...visitaNueva(new Date(2026, 8, 27)),
        estado: "en_curso",
        respuestas: {n1: {resultado: "cumple"}},
        firmaProfesional: null,
        firmaEstablecimiento: null,
      }),
      setDoc(doc(db, "TBL_VISITAS_GRUPOS/G1"), {
        empresaId: "EMP_A", nombre: "Norte", areaId: "EMP_A_nutricion",
        centroIds: ["C1"], profesionalIds: ["prof"],
      }),
    ]);
  });
});

test.after(async () => {
  await env.cleanup();
});

test("el firmante lee la visita que le pidieron y no otra", async () => {
  await assertSucceeds(getDoc(doc(auth("firm"), "TBL_VISITAS/v1")));
  await assertFails(getDoc(doc(auth("firm"), "TBL_VISITAS/v2")));
  await assertSucceeds(getDocs(query(
    collection(auth("firm"), "TBL_VISITAS"),
    where("empresaId", "==", "EMP_A"),
    where("firmanteEstablecimientoId", "==", "firm"),
  )));
  // Sin el filtro por firmante la consulta no pasa: vería visitas ajenas.
  await assertFails(getDocs(query(
    collection(auth("firm"), "TBL_VISITAS"),
    where("empresaId", "==", "EMP_A"),
  )));
});

test("el firmante estampa solo su firma", async () => {
  const db = auth("firm");
  await assertFails(updateDoc(doc(db, "TBL_VISITAS/v1"), {
    respuestas: {n1: {resultado: "no_cumple"}},
  }));
  await assertFails(updateDoc(doc(db, "TBL_VISITAS/v1"), {
    firmaEstablecimiento: {nombre: "Firmante", modo: "dibujada"},
    estado: "terminada",
  }));
  await assertSucceeds(updateDoc(doc(db, "TBL_VISITAS/v1"), {
    firmaEstablecimiento: {nombre: "Firmante", modo: "dibujada"},
  }));
  // Ya firmó: no puede reemplazarla.
  await assertFails(updateDoc(doc(db, "TBL_VISITAS/v1"), {
    firmaEstablecimiento: {nombre: "Otra", modo: "dibujada"},
  }));
});

test("alguien que no es el firmante designado no firma", async () => {
  await assertFails(updateDoc(doc(auth("firm"), "TBL_VISITAS/v2"), {
    firmaEstablecimiento: {nombre: "Firmante", modo: "dibujada"},
  }));
});

test("el profesional designa al firmante, antes y después de firmar", async () => {
  const db = auth("prof");
  await assertSucceeds(updateDoc(doc(db, "TBL_VISITAS/v3"), {
    firmanteEstablecimientoId: "firm",
    responsableEstablecimiento: {nombre: "Firmante", cargo: "Administrador", userId: "firm"},
  }));
  await assertSucceeds(updateDoc(doc(db, "TBL_VISITAS/v3"), {
    firmaProfesional: {nombre: "Profesional", modo: "dibujada"},
  }));
  await assertSucceeds(updateDoc(doc(db, "TBL_VISITAS/v3"), {
    firmanteEstablecimientoId: "otro",
    responsableEstablecimiento: {nombre: "Otro", cargo: "Administrador", userId: "otro"},
  }));
  // Pero con la firma puesta el contenido sigue congelado.
  await assertFails(updateDoc(doc(db, "TBL_VISITAS/v3"), {
    respuestas: {n1: {resultado: "no_cumple"}},
  }));
});

test("grupos: los arma el jefe de su área", async () => {
  const grupo = {
    empresaId: "EMP_A", nombre: "Sur", areaId: "EMP_A_nutricion",
    centroIds: ["C2"], profesionalIds: [],
  };
  await assertSucceeds(setDoc(doc(auth("jefe"), "TBL_VISITAS_GRUPOS/G2"), grupo));
  await assertFails(setDoc(doc(auth("jefe"), "TBL_VISITAS_GRUPOS/G3"), {
    ...grupo, areaId: "EMP_A_mantenimiento",
  }));
  await assertFails(setDoc(doc(auth("prof"), "TBL_VISITAS_GRUPOS/G4"), grupo));
  await assertFails(setDoc(doc(auth("otro"), "TBL_VISITAS_GRUPOS/G5"), grupo));
  await assertFails(updateDoc(doc(auth("jefe"), "TBL_VISITAS_GRUPOS/G1"), {
    areaId: "EMP_A_mantenimiento",
  }));
  await assertSucceeds(updateDoc(doc(auth("jefe"), "TBL_VISITAS_GRUPOS/G1"), {
    profesionalIds: [],
  }));
  await assertSucceeds(getDoc(doc(auth("prof"), "TBL_VISITAS_GRUPOS/G1")));
  await assertFails(getDoc(doc(auth("otro"), "TBL_VISITAS_GRUPOS/G1")));
});

test("roles: se acepta firmante y el jefe solo da Profesional", async () => {
  await assertSucceeds(setDoc(doc(auth("dev"), "TBL_VISITAS_ROLES/EMP_A_otro"), {
    empresaId: "EMP_A", userId: "otro", rol: "firmante", areaId: "",
  }));
  await assertFails(setDoc(doc(auth("jefe"), "TBL_VISITAS_ROLES/EMP_A_nuevo1"), {
    empresaId: "EMP_A", userId: "nuevo1", rol: "firmante", areaId: "EMP_A_nutricion",
  }));
  await assertSucceeds(setDoc(doc(auth("jefe"), "TBL_VISITAS_ROLES/EMP_A_nuevo2"), {
    empresaId: "EMP_A", userId: "nuevo2", rol: "profesional",
    areaId: "EMP_A_nutricion",
  }));
  await assertFails(setDoc(doc(auth("jefe"), "TBL_VISITAS_ROLES/EMP_A_nuevo3"), {
    empresaId: "EMP_A", userId: "nuevo3", rol: "profesional",
    areaId: "EMP_A_mantenimiento",
  }));
});

test("programar varias fechas en un solo lote", async () => {
  const db = auth("jefe");
  const batch = writeBatch(db);
  for (let i = 0; i < 12; i++) {
    batch.set(doc(collection(db, "TBL_VISITAS")),
      visitaNueva(new Date(2026, 9, 1 + i)));
  }
  await assertSucceeds(batch.commit());
});
