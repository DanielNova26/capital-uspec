const test = require("node:test");
const fs = require("node:fs");
const path = require("node:path");
const {
  assertFails, assertSucceeds, initializeTestEnvironment,
} = require("@firebase/rules-unit-testing");
const {
  collection, deleteDoc, doc, getDoc, getDocs, query, serverTimestamp, setDoc,
  updateDoc, where,
} = require("firebase/firestore");

const app = "mantenimientodashboard";
const equipos = "TBL_MANTENIMIENTO_EQUIPOS";
const ordenes = "TBL_MANTENIMIENTO_ORDENES";
let env;

const cuenta = (id) => env.authenticatedContext(id, {
  authVersion: 2, userDocId: id,
}).firestore();

const ficha = (empresaId = "A", centroDocId = "centro-A") => ({
  empresaId, centroDocId, codigo: "EQ-001", nombre: "Nevera",
  serie: "", factura: "", updatedAt: serverTimestamp(),
});
const orden = (cambios = {}) => ({
  empresaId: "A", centroDocId: "centro-A", equipoId: "", hallazgoId: "",
  tipo: "correctivo", detalle: "Revisar fuga", factura: "", resultado: "",
  estado: "abierta", createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
  cerradaAt: null, ...cambios,
});
const sembrar = (datos) => env.withSecurityRulesDisabled(async (context) => {
  const db = context.firestore();
  await Promise.all(Object.entries(datos).map(([ruta, data]) =>
    setDoc(doc(db, ruta), data)));
});

test.before(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-mantenimiento",
    firestore: {rules: fs.readFileSync(path.resolve(__dirname, "../../firestore.rules"), "utf8")},
  });
  await sembrar({
    "TBL_USUARIOS/operario": {
      empresaId: "B", empresas: ["A", "B"], appsPorEmpresa: true, apps: [],
      empresasDetalle: {A: {apps: [app]}, B: {apps: []}},
    },
    "TBL_USUARIOS/sinapp": {empresaId: "A", apps: []},
    "TBL_USUARIOS/inhabilitado": {
      empresaId: "A", empresasDetalle: {A: {apps: [app], activo: false}},
    },
    "TBL_USUARIOS/desarrollo": {empresaId: "B", apps: [app], desarrollador: true},
    "TBL_CENTROS_COSTOS/centro-A": {empresaId: "A", centroId: "sede-A"},
    "TBL_CENTROS_COSTOS/otro-A": {empresaId: "A", centroId: "otra-sede-A"},
    "TBL_CENTROS_COSTOS/centro-B": {empresaId: "B", centroId: "sede-B"},
    "TBL_INTERVENTORIA_HALLAZGOS/hallazgo-A": {empresaId: "A", centroCostoId: "sede-A"},
    "TBL_INTERVENTORIA_HALLAZGOS/hallazgo-B": {empresaId: "B", centroCostoId: "sede-B"},
    [`${equipos}/equipo-B`]: ficha("B", "centro-B"),
    [`${equipos}/equipo-importado`]: {
      empresaId: "A", codigo: "COPIA", nombre: "Equipo copiado",
      sincronizadoDesde: {empresaId: "B"},
    },
  });
});
test.after(async () => env?.cleanup());

test("opera en la empresa secundaria con app y edita una ficha base copiada", async () => {
  const db = cuenta("operario");
  const equipo = doc(db, equipos, "equipo-A");
  await assertSucceeds(setDoc(equipo, ficha()));
  await assertSucceeds(getDocs(query(collection(db, equipos), where("empresaId", "==", "A"))));
  await assertFails(getDocs(collection(db, equipos)));
  await assertFails(getDoc(doc(db, equipos, "equipo-B")));
  await assertFails(getDoc(doc(cuenta("sinapp"), equipos, "equipo-A")));
  await assertFails(getDoc(doc(cuenta("inhabilitado"), equipos, "equipo-A")));
  await assertFails(getDoc(doc(cuenta("desarrollo"), equipos, "equipo-A")));
  await assertFails(updateDoc(equipo, {centroDocId: "centro-B", updatedAt: serverTimestamp()}));
  await assertSucceeds(updateDoc(doc(db, equipos, "equipo-importado"), {
    centroDocId: "centro-A", serie: "", factura: "", updatedAt: serverTimestamp(),
  }));
});

test("la orden conserva sus vínculos y solo se cierra tras registrar el trabajo", async () => {
  const db = cuenta("operario");
  const ref = doc(db, ordenes, "orden-A");
  await assertFails(setDoc(ref, orden({equipoId: "equipo-B"})));
  await assertFails(setDoc(ref, orden({hallazgoId: "hallazgo-B"})));
  await assertFails(setDoc(ref, orden({centroDocId: "otro-A", hallazgoId: "hallazgo-A"})));
  await assertSucceeds(setDoc(ref, orden({equipoId: "equipo-A", hallazgoId: "hallazgo-A"})));
  await assertSucceeds(setDoc(doc(db, ordenes, "orden-sede"), orden({tipo: "preventivo"})));
  const cerrar = {
    estado: "cerrada", resultado: "Se corrigió la fuga", factura: "F-12",
    updatedAt: serverTimestamp(), cerradaAt: serverTimestamp(),
  };
  await assertFails(updateDoc(ref, cerrar));
  await assertSucceeds(updateDoc(ref, {estado: "en_curso", updatedAt: serverTimestamp()}));
  await assertFails(updateDoc(ref, {...cerrar, centroDocId: "otro-A"}));
  await assertFails(updateDoc(ref, {...cerrar, resultado: "   "}));
  await assertSucceeds(updateDoc(ref, cerrar));
  await assertSucceeds(updateDoc(ref, {factura: "F-13", updatedAt: serverTimestamp()}));
  await assertFails(deleteDoc(ref));
});

test("revoca y reactiva sin recuperar privilegios de un rol histórico", async () => {
  const equipo = doc(cuenta("operario"), equipos, "equipo-A");
  const usuario = {
    empresaId: "B", empresas: ["A", "B"], appsPorEmpresa: true, apps: [app],
    roleId: "B_administrador",
  };
  await sembrar({"TBL_USUARIOS/operario": {...usuario, empresasDetalle: {A: {apps: []}}}});
  await assertFails(getDoc(equipo));
  await sembrar({
    "TBL_USUARIOS/operario": {...usuario, empresasDetalle: {A: {apps: [app]}}},
    [`TBL_APPS/A_${app}`]: {empresaId: "A", appId: app, enabled: false},
  });
  await assertFails(getDoc(equipo));
  await sembrar({[`TBL_APPS/A_${app}`]: {empresaId: "A", appId: app, enabled: true}});
  await assertSucceeds(getDoc(equipo));
});
