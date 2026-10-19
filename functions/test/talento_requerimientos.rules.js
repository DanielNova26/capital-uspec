const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {initializeTestEnvironment, assertSucceeds, assertFails} =
  require("@firebase/rules-unit-testing");
const {collection, doc, getDocs, query, where, setDoc, updateDoc, deleteDoc} =
  require("firebase/firestore");

let env;
const auth = (id) => env.authenticatedContext(id, {
  authVersion: 2, userDocId: id,
}).firestore();
const niveles = ["consulta", "solicitante", "reclutador", "gestor", "administrador"];
const solicitud = (userId, empresaId = "EMP_A", extra = {}) => ({
  empresaId, creadoPor: userId, cargo: "Auxiliar de procesos",
  establecimiento: "Sede de prueba", cantidad: 1, etapa: "solicitado",
  candidatos: [], contratados: [], ...extra,
});

test.before(async () => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST, "Usa el emulador.");
  env = await initializeTestEnvironment({
    projectId: "demo-talento-requerimientos",
    firestore: {rules: fs.readFileSync(path.resolve(__dirname, "../../firestore.rules"), "utf8")},
  });
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    for (const id of [...niveles, "historico", "sinApp", "inhabilitado", "adminGeneral"]) {
      await setDoc(doc(db, `TBL_USUARIOS/${id}`), {
        empresaId: "EMP_A", empresas: ["EMP_A", "EMP_B"],
        activo: true, estado: "activo", role: "colaborador", rol: "colaborador",
        roleKey: "colaborador", roleId: "EMP_A_colaborador", appsPorEmpresa: true,
        empresasDetalle: {
          EMP_A: {activo: true, estadoLaboral: id === "inhabilitado" ? "inactivo" : "activo",
            roleKey: "colaborador", roleId: "EMP_A_colaborador",
            apps: id === "sinApp" ? [] : [id === "adminGeneral" ? "admindashboard" : "talentohumanodashboard"]},
          EMP_B: {activo: true, apps: ["talentohumanodashboard"]},
        },
      });
      if (id !== "historico") {
        await setDoc(doc(db, `TBL_TALENTO_HUMANO_ROLES/EMP_A_${id}`), {
          empresaId: "EMP_A", userId: id, rol: niveles.includes(id) ? id : "administrador",
        });
      }
      await setDoc(doc(db, `TBL_TALENTO_HUMANO_ROLES/EMP_B_${id}`), {
        empresaId: "EMP_B", userId: id, rol: "consulta",
      });
    }
    for (const name of ["TBL_CENTROS_COSTOS", "TBL_COMPRAS_GRUPOS", "TBL_CARGOS"]) {
      await setDoc(doc(db, `${name}/catalogo`), {empresaId: "EMP_A", nombre: "Prueba"});
    }
  });
});
test.after(async () => { await env?.cleanup(); });

test("administradora de Talento consulta catálogos y crea el perfil requerido", async () => {
  const db = auth("administrador");
  for (const name of ["TBL_CENTROS_COSTOS", "TBL_COMPRAS_GRUPOS", "TBL_CARGOS"]) {
    await assertSucceeds(getDocs(query(collection(db, name), where("empresaId", "==", "EMP_A"))));
  }
  await assertSucceeds(setDoc(doc(db, "TBL_TH_REQUERIMIENTOS_PERSONAL/nuevo"), solicitud("administrador")));
  await assertSucceeds(updateDoc(doc(db, "TBL_TH_REQUERIMIENTOS_PERSONAL/nuevo"), {cargo: "Jefe de cocina"}));
  await assertSucceeds(deleteDoc(doc(db, "TBL_TH_REQUERIMIENTOS_PERSONAL/nuevo")));
});

test("creación por niveles, acceso histórico y Admin general", async () => {
  for (const id of ["solicitante", "reclutador", "gestor", "historico", "adminGeneral"]) {
    await assertSucceeds(setDoc(doc(auth(id), `TBL_TH_REQUERIMIENTOS_PERSONAL/${id}`), solicitud(id)));
  }
  for (const id of ["consulta", "sinApp", "inhabilitado"]) {
    await assertFails(setDoc(doc(auth(id), `TBL_TH_REQUERIMIENTOS_PERSONAL/${id}`), solicitud(id)));
  }
});

test("solicitante edita lo propio sin reclutar, contratar ni suplantar al creador", async () => {
  const db = auth("solicitante");
  const ref = doc(db, "TBL_TH_REQUERIMIENTOS_PERSONAL/propia");
  await assertSucceeds(setDoc(ref, solicitud("solicitante")));
  await assertSucceeds(updateDoc(ref, {cargo: "Cargo corregido"}));
  for (const extra of [
    {creadoPor: "administrador"}, {etapa: "cerrado"},
    {candidatos: [{nombres: "Prueba"}]}, {contratados: [{documento: "123"}]},
  ]) {
    await assertFails(updateDoc(ref, extra));
    await assertFails(setDoc(doc(db, "TBL_TH_REQUERIMIENTOS_PERSONAL/invalida"), solicitud("solicitante", "EMP_A", extra)));
  }
  await assertFails(updateDoc(doc(db, "TBL_TH_REQUERIMIENTOS_PERSONAL/gestor"), {cargo: "Ajeno"}));
  await assertFails(deleteDoc(ref));
});

test("el nivel de la empresa principal no autoriza otra empresa", async () => {
  const db = auth("administrador");
  for (const empresa of ["EMP_B", "EMP_AJENA"]) {
    await assertFails(setDoc(doc(db, `TBL_TH_REQUERIMIENTOS_PERSONAL/${empresa}`), solicitud("administrador", empresa)));
  }
  const ref = doc(db, "TBL_TH_REQUERIMIENTOS_PERSONAL/sinTraslado");
  await assertSucceeds(setDoc(ref, solicitud("administrador")));
  await assertFails(updateDoc(ref, {empresaId: "EMP_B"}));
});

test("reclutador y gestor editan; solo gestor elimina", async () => {
  for (const id of ["reclutador", "gestor"]) {
    const ref = doc(auth(id), `TBL_TH_REQUERIMIENTOS_PERSONAL/gestion_${id}`);
    await assertSucceeds(setDoc(ref, solicitud(id)));
    await assertSucceeds(updateDoc(ref, {candidatos: [{nombres: "Aspirante"}]}));
    await (id === "gestor" ? assertSucceeds(deleteDoc(ref)) : assertFails(deleteDoc(ref)));
  }
});

test("revocar y reactivar con consulta no recupera el permiso de creación", async () => {
  const db = auth("administrador");
  const ref = doc(db, "TBL_TH_REQUERIMIENTOS_PERSONAL/reactivada");
  await env.withSecurityRulesDisabled(async (context) => {
    await updateDoc(doc(context.firestore(), "TBL_USUARIOS/administrador"), {"empresasDetalle.EMP_A.apps": []});
  });
  await assertFails(setDoc(ref, solicitud("administrador")));
  await env.withSecurityRulesDisabled(async (context) => {
    await updateDoc(doc(context.firestore(), "TBL_TALENTO_HUMANO_ROLES/EMP_A_administrador"), {rol: "consulta"});
    await updateDoc(doc(context.firestore(), "TBL_USUARIOS/administrador"), {"empresasDetalle.EMP_A.apps": ["talentohumanodashboard"]});
  });
  await assertFails(setDoc(ref, solicitud("administrador")));
});
