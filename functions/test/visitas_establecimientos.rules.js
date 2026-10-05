/**
 * Reglas de Visitas, 5 oct 2026:
 * - Establecimientos propios de Visitas (los que no son centros de costo):
 *   los escriben Desarrollo, Admin de la empresa y Gerencia de Visitas; los
 *   leen quienes participan en Visitas y Admin; nadie los borra; el id es
 *   `{empresa}_est_…` y es su centroId.
 * - Número de visita: lo pone el servidor. La app no lo trae al crear ni lo
 *   cambia después, y el contador no se lee ni se escribe desde la app.
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
  query,
  setDoc,
  updateDoc,
  where,
} = require("firebase/firestore");

const projectId = "capital-uspec-visitas-establecimientos";
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

function est(extra = {}) {
  return {
    empresaId: "EMP_A",
    centroId: "EMP_A_est_bodega",
    nombre: "Bodega Norte",
    ciudad: "Bogotá",
    enabled: true,
    ...extra,
  };
}

function visita(extra = {}) {
  return {
    empresaId: "EMP_A",
    formatoId: "",
    formatoNombre: "",
    esPrueba: false,
    areaId: "EMP_A_nutricion",
    areaNombre: "Nutrición",
    centroId: "EMP_A_est_bodega",
    centroNombre: "Bodega Norte",
    subcentroId: "",
    subcentroNombre: "",
    profesionalId: "prof",
    profesionalNombre: "Profesional",
    asignadoPorId: "jefe",
    asignadoPorNombre: "Jefe",
    fechaProgramada: new Date(2026, 9, 5),
    estado: "programada",
    ...extra,
  };
}

test.before(async () => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST, "Usa el emulador.");
  env = await initializeTestEnvironment({projectId, firestore: {rules}});
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const miembro = (nombre, extra = {}) => ({
      nombre, empresas: ["EMP_A"], empresaId: "EMP_A", ...extra,
    });
    await Promise.all([
      setDoc(doc(db, "TBL_USUARIOS/dev"), miembro("Dev", {desarrollador: true})),
      setDoc(doc(db, "TBL_USUARIOS/admin"),
        miembro("Admin", {apps: ["admindashboard"]})),
      setDoc(doc(db, "TBL_USUARIOS/ger"), miembro("Gerencia")),
      setDoc(doc(db, "TBL_USUARIOS/jefe"), miembro("Jefe")),
      setDoc(doc(db, "TBL_USUARIOS/prof"), miembro("Profesional")),
      setDoc(doc(db, "TBL_USUARIOS/nadie"), miembro("Sin rol")),
      // Admin de otra empresa: no lee ni escribe los de EMP_A.
      setDoc(doc(db, "TBL_USUARIOS/adminb"), {
        nombre: "Admin B", empresas: ["EMP_B"], empresaId: "EMP_B",
        apps: ["admindashboard"],
      }),
      setDoc(doc(db, "TBL_VISITAS_ROLES/EMP_A_ger"), {
        empresaId: "EMP_A", userId: "ger", rol: "gerencia", areaId: "",
      }),
      setDoc(doc(db, "TBL_VISITAS_ROLES/EMP_A_jefe"), {
        empresaId: "EMP_A", userId: "jefe", rol: "jefe",
        areaId: "EMP_A_nutricion",
      }),
      setDoc(doc(db, "TBL_VISITAS_ROLES/EMP_A_prof"), {
        empresaId: "EMP_A", userId: "prof", rol: "profesional",
        areaId: "EMP_A_nutricion",
      }),
      setDoc(doc(db, "TBL_VISITAS_ESTABLECIMIENTOS/EMP_A_est_bodega"), est()),
      setDoc(doc(db, "TBL_VISITAS/prog"), visita({numero: 1})),
      setDoc(doc(db, "TBL_VISITAS_CONTADORES/EMP_A"), {
        empresaId: "EMP_A", ultimo: 1,
      }),
    ]);
  });
});

test.after(async () => {
  await env.cleanup();
});

test("Admin, Desarrollo y Gerencia crean; jefe, profesional y otros no", async () => {
  await assertSucceeds(setDoc(
    doc(auth("admin"), "TBL_VISITAS_ESTABLECIMIENTOS/EMP_A_est_picota_2"),
    est({centroId: "EMP_A_est_picota_2", nombre: "Picota 2"})));
  await assertSucceeds(setDoc(
    doc(auth("dev"), "TBL_VISITAS_ESTABLECIMIENTOS/EMP_A_est_modelo"),
    est({centroId: "EMP_A_est_modelo", nombre: "Modelo", ciudad: ""})));
  await assertSucceeds(setDoc(
    doc(auth("ger"), "TBL_VISITAS_ESTABLECIMIENTOS/EMP_A_est_combita"),
    est({centroId: "EMP_A_est_combita", nombre: "Cómbita"})));
  for (const quien of ["jefe", "prof", "nadie", "adminb"]) {
    await assertFails(setDoc(
      doc(auth(quien), `TBL_VISITAS_ESTABLECIMIENTOS/EMP_A_est_${quien}`),
      est({centroId: `EMP_A_est_${quien}`, nombre: `Sitio ${quien}`})));
  }
});

test("el id es de la empresa, con _est_, y es el centroId", async () => {
  const db = auth("admin");
  const malos = [
    ["EMP_A_bodega2", est({centroId: "EMP_A_bodega2"})],
    ["EMP_A_est_b3", est({centroId: "EMP_A_est_otro"})],
    ["EMP_B_est_b4", est({centroId: "EMP_B_est_b4", empresaId: "EMP_B"})],
    ["EMP_A_est_b5", est({centroId: "EMP_A_est_b5", nombre: "B"})],
    ["EMP_A_est_b6", est({centroId: "EMP_A_est_b6", enabled: "si"})],
    ["EMP_A_est_b7", est({centroId: "EMP_A_est_b7", ciudad: "x".repeat(81)})],
    ["EMP_A_est_B8", est({centroId: "EMP_A_est_B8"})],
  ];
  for (const [id, data] of malos) {
    await assertFails(setDoc(doc(db, `TBL_VISITAS_ESTABLECIMIENTOS/${id}`), data));
  }
});

test("se edita e inactiva sin cambiar empresa ni id; no se borra", async () => {
  const ref = (quien) =>
    doc(auth(quien), "TBL_VISITAS_ESTABLECIMIENTOS/EMP_A_est_bodega");
  await assertSucceeds(updateDoc(ref("admin"), {
    nombre: "Bodega Sur", ciudad: "", enabled: false,
    actualizadoPor: "admin",
  }));
  await assertSucceeds(updateDoc(ref("ger"), {enabled: true}));
  await assertFails(updateDoc(ref("admin"), {centroId: "EMP_A_est_otra"}));
  await assertFails(updateDoc(ref("admin"), {empresaId: "EMP_B"}));
  await assertFails(updateDoc(ref("jefe"), {nombre: "Otra"}));
  await assertFails(updateDoc(ref("prof"), {enabled: false}));
  await assertFails(deleteDoc(ref("dev")));
  await assertFails(deleteDoc(ref("admin")));
});

test("los leen quienes participan en Visitas y Admin; otra empresa no", async () => {
  const lista = (quien) => getDocs(query(
    collection(auth(quien), "TBL_VISITAS_ESTABLECIMIENTOS"),
    where("empresaId", "==", "EMP_A"),
  ));
  for (const quien of ["jefe", "prof", "ger", "dev", "admin"]) {
    await assertSucceeds(lista(quien));
  }
  await assertFails(lista("nadie"));
  await assertFails(lista("adminb"));
  await assertSucceeds(getDoc(
    doc(auth("jefe"), "TBL_VISITAS_ESTABLECIMIENTOS/EMP_A_est_bodega")));
  // Preguntar por uno que no existe no falla.
  await assertSucceeds(getDoc(
    doc(auth("nadie"), "TBL_VISITAS_ESTABLECIMIENTOS/EMP_A_est_no_existe")));
});

test("se programa en un establecimiento propio, sin número", async () => {
  const db = auth("jefe");
  await assertSucceeds(setDoc(doc(db, "TBL_VISITAS/nueva"), visita()));
  await assertFails(setDoc(doc(db, "TBL_VISITAS/con_numero"),
    visita({numero: 7})));
});

test("nadie cambia el número de una visita", async () => {
  await assertFails(updateDoc(doc(auth("jefe"), "TBL_VISITAS/prog"), {
    estado: "cancelada", motivoCancelacion: "x", numero: 99,
  }));
  await assertFails(updateDoc(doc(auth("prof"), "TBL_VISITAS/prog"), {
    numero: 99,
  }));
  await assertFails(updateDoc(doc(auth("dev"), "TBL_VISITAS/prog"), {
    numero: 99,
  }));
  await assertSucceeds(updateDoc(doc(auth("jefe"), "TBL_VISITAS/prog"), {
    estado: "cancelada", motivoCancelacion: "Festivo",
  }));
});

test("el contador de visitas es solo del servidor", async () => {
  for (const quien of ["dev", "admin", "ger"]) {
    await assertFails(getDoc(doc(auth(quien), "TBL_VISITAS_CONTADORES/EMP_A")));
    await assertFails(setDoc(doc(auth(quien), "TBL_VISITAS_CONTADORES/EMP_A"), {
      empresaId: "EMP_A", ultimo: 0,
    }));
  }
});
