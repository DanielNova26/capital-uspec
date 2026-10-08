/**
 * Reglas de Visitas, 26 sep 2026:
 * - Gerencia ve y administra todas las áreas, como Desarrollo: visitas,
 *   formatos, grupos, programar, reprogramar y el maestro de ubicaciones.
 * - Gerencia nombra jefes, profesionales, consulta y firmantes, pero no a
 *   otra Gerencia ni se cambia a sí misma: eso es de Desarrollo.
 * - Ubicaciones: Desarrollo y Gerencia; ni el jefe ni el profesional.
 * - El profesional guarda las evidencias adicionales mientras el acta no
 *   está firmada; con la primera firma quedan congeladas como el resto.
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
  getDocs,
  query,
  setDoc,
  updateDoc,
  where,
} = require("firebase/firestore");

const projectId = "capital-uspec-visitas-gerencia";
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

function visita(extra = {}) {
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
    fechaProgramada: new Date(Date.now() + 86400000),
    estado: "programada",
    ...extra,
  };
}

test.before(async () => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST, "Usa el emulador.");
  env = await initializeTestEnvironment({projectId, firestore: {rules}});
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const miembro = (nombre) => ({nombre, empresas: ["EMP_A"], empresaId: "EMP_A"});
    await Promise.all([
      setDoc(doc(db, "TBL_USUARIOS/dev"), {...miembro("Dev"), desarrollador: true}),
      setDoc(doc(db, "TBL_USUARIOS/ger"), miembro("Oscar")),
      setDoc(doc(db, "TBL_USUARIOS/jefe"), miembro("Jefe")),
      setDoc(doc(db, "TBL_USUARIOS/prof"), miembro("Profesional")),
      setDoc(doc(db, "TBL_USUARIOS/otro"), miembro("Otro")),
      // Gerencia por cargo, sin rol en TBL_VISITAS_ROLES (27 sep 2026).
      setDoc(doc(db, "TBL_USUARIOS/oscar"), {
        ...miembro("Oscar"), cargo: "Gerencia", area: "Gerencia",
      }),
      setDoc(doc(db, "TBL_USUARIOS/sub"), {
        ...miembro("Sub"), cargo: "Subgerente administrativo",
      }),
      setDoc(doc(db, "TBL_USUARIOS/multi"), {
        ...miembro("Multi"), cargo: "Gerente",
        empresasDetalle: {EMP_A: {cargoNombre: "Analista"}},
      }),
      // Gerente en su empresa principal (EMP_B), sin cargo propio en EMP_A:
      // la raíz es de EMP_B y no le da Gerencia en EMP_A.
      setDoc(doc(db, "TBL_USUARIOS/gerb"), {
        nombre: "Gerente B", empresas: ["EMP_A", "EMP_B"], empresaId: "EMP_B",
        cargo: "Gerente general", empresasDetalle: {EMP_A: {}},
      }),
      setDoc(doc(db, "TBL_USUARIOS/gerbperfil"), {
        nombre: "Gerente por perfil B", empresas: ["EMP_A", "EMP_B"],
        empresaId: "EMP_B", roleKey: "gerencia",
        empresasDetalle: {EMP_A: {roleKey: "usuario"}},
      }),
      setDoc(doc(db, "TBL_VISITAS_ROLES/EMP_A_ger"), {
        empresaId: "EMP_A", userId: "ger", rol: "gerencia", areaId: "",
      }),
      setDoc(doc(db, "TBL_VISITAS_ROLES/EMP_A_jefe"), {
        empresaId: "EMP_A", userId: "jefe", rol: "jefe",
        areaId: "EMP_A_calidad",
      }),
      setDoc(doc(db, "TBL_VISITAS_ROLES/EMP_A_prof"), {
        empresaId: "EMP_A", userId: "prof", rol: "profesional",
        areaId: "EMP_A_nutricion",
      }),
      setDoc(doc(db, "TBL_VISITAS_FORMATOS/F1"), formato),
      setDoc(doc(db, "TBL_VISITAS/prog"), visita()),
      setDoc(doc(db, "TBL_VISITAS/curso"), visita({
        estado: "en_curso",
        firmaProfesional: null,
        firmaEstablecimiento: null,
      })),
      setDoc(doc(db, "TBL_VISITAS/firmada"), visita({
        estado: "en_curso",
        firmaProfesional: {nombre: "Profesional", modo: "dibujada"},
        firmaEstablecimiento: null,
      })),
    ]);
  });
});

test.after(async () => {
  await env.cleanup();
});

test("Gerencia ve las visitas y los formatos de todas las áreas", async () => {
  const db = auth("ger");
  await assertSucceeds(getDocs(query(
    collection(db, "TBL_VISITAS"),
    where("empresaId", "==", "EMP_A"),
  )));
  await assertSucceeds(getDocs(query(
    collection(db, "TBL_VISITAS_FORMATOS"),
    where("empresaId", "==", "EMP_A"),
  )));
  // El jefe de Calidad no ve las de Nutrición.
  await assertFails(getDocs(query(
    collection(auth("jefe"), "TBL_VISITAS"),
    where("empresaId", "==", "EMP_A"),
  )));
});

test("Gerencia crea formatos y programa en cualquier área", async () => {
  const db = auth("ger");
  await assertSucceeds(setDoc(doc(db, "TBL_VISITAS_FORMATOS/F2"), {
    ...formato, areaId: "EMP_A_mantenimiento", estado: "borrador",
  }));
  await assertSucceeds(setDoc(doc(db, "TBL_VISITAS/nueva"), visita({
    asignadoPorId: "ger", asignadoPorNombre: "Oscar",
  })));
  await assertSucceeds(updateDoc(doc(db, "TBL_VISITAS/prog"), {
    fechaProgramada: new Date(Date.now() + 3 * 86400000),
    reprogramaciones: [{motivo: "Festivo"}],
  }));
});

test("ubicaciones: Desarrollo y Gerencia sí; jefe y profesional no", async () => {
  const u = {
    empresaId: "EMP_A", centroId: "C1", centroNombre: "Buen Pastor",
    lat: 4.6, lng: -74.1, radioMetros: 150,
  };
  await assertSucceeds(setDoc(doc(auth("ger"), "TBL_VISITAS_UBICACIONES/EMP_A_C1"), u));
  await assertSucceeds(setDoc(doc(auth("dev"), "TBL_VISITAS_UBICACIONES/EMP_A_C2"), {
    ...u, centroId: "C2",
  }));
  await assertFails(setDoc(doc(auth("jefe"), "TBL_VISITAS_UBICACIONES/EMP_A_C3"), {
    ...u, centroId: "C3",
  }));
  await assertFails(setDoc(doc(auth("prof"), "TBL_VISITAS_UBICACIONES/EMP_A_C4"), {
    ...u, centroId: "C4",
  }));
});

test("Gerencia nombra roles, pero no otra Gerencia ni se toca a sí misma", async () => {
  const db = auth("ger");
  await assertSucceeds(setDoc(doc(db, "TBL_VISITAS_ROLES/EMP_A_otro"), {
    empresaId: "EMP_A", userId: "otro", rol: "jefe", areaId: "EMP_A_mantenimiento",
  }));
  await assertFails(setDoc(doc(db, "TBL_VISITAS_ROLES/EMP_A_nuevo"), {
    empresaId: "EMP_A", userId: "nuevo", rol: "gerencia", areaId: "",
  }));
  await assertFails(updateDoc(doc(db, "TBL_VISITAS_ROLES/EMP_A_ger"), {
    rol: "jefe", areaId: "EMP_A_calidad",
  }));
  // El jefe no se vuelve Gerencia; Desarrollo sí la nombra.
  await assertFails(updateDoc(doc(auth("jefe"), "TBL_VISITAS_ROLES/EMP_A_jefe"), {
    rol: "gerencia", areaId: "",
  }));
  await assertSucceeds(setDoc(doc(auth("dev"), "TBL_VISITAS_ROLES/EMP_A_nuevo"), {
    empresaId: "EMP_A", userId: "nuevo", rol: "gerencia", areaId: "",
  }));
});

test("evidencias adicionales: sí antes de firmar, no después", async () => {
  const db = auth("prof");
  const fotos = [{url: "u", path: "p", nombre: "a.jpg", descripcion: "Fachada"}];
  await assertSucceeds(updateDoc(doc(db, "TBL_VISITAS/curso"), {
    evidenciasAdicionales: fotos,
  }));
  await assertFails(updateDoc(doc(db, "TBL_VISITAS/firmada"), {
    evidenciasAdicionales: fotos,
  }));
});

test("Gerencia por cargo, sin rol asignado", async () => {
  const todas = (quien) => getDocs(query(
    collection(auth(quien), "TBL_VISITAS"),
    where("empresaId", "==", "EMP_A"),
  ));
  await assertSucceeds(todas("oscar"));
  await assertSucceeds(setDoc(doc(auth("oscar"), "TBL_VISITAS_UBICACIONES/EMP_A_C9"), {
    empresaId: "EMP_A", centroId: "C9", centroNombre: "Chocontá",
    lat: 5.1, lng: -73.6, radioMetros: 150,
  }));
  await assertSucceeds(setDoc(doc(auth("oscar"), "TBL_VISITAS_FORMATOS/F9"), {
    ...formato, areaId: "EMP_A_sst", estado: "borrador",
  }));
  // Lo que antes solo leía quien tenía rol: ubicaciones, grupos y roles.
  for (const col of ["TBL_VISITAS_UBICACIONES", "TBL_VISITAS_GRUPOS",
    "TBL_VISITAS_ROLES"]) {
    await assertSucceeds(getDocs(query(
      collection(auth("oscar"), col),
      where("empresaId", "==", "EMP_A"),
    )));
  }
  // Subgerente no; y el cargo de la empresa manda sobre el de la raíz.
  await assertFails(todas("sub"));
  await assertFails(todas("multi"));
  // El cargo de la raíz es de su empresa principal, no de esta.
  await assertFails(todas("gerb"));
  // Tampoco se hereda el perfil de Gerencia de la empresa principal.
  await assertFails(todas("gerbperfil"));
});
