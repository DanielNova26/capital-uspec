const {createHash} = require("node:crypto");
const test = require("node:test");
const assert = require("node:assert/strict");
const admin = require("firebase-admin");
const {puedeCargarPersonal, procesarCargaPersonal} = require("../lib/talento_personal_import");

const app = "talentohumanodashboard";
const actor = {
  empresaId: "A",
  empresas: ["A", "B"],
  appsPorEmpresa: true,
  apps: [app],
  empresasDetalle: {A: {apps: [app]}, B: {apps: [app]}},
};
const rol = (empresaId, rol) => ({empresaId, userId: "gestor", rol});

test("el alta usa el nivel canónico, la empresa y la habilitación vigentes", () => {
  for (const nivel of ["consulta", "solicitante", "reclutador", "gestor", "administrador", ""]) {
    assert.equal(puedeCargarPersonal(actor, "A", "gestor", rol("A", nivel)),
      ["gestor", "administrador"].includes(nivel));
  }
  assert.equal(puedeCargarPersonal(actor, "A", "gestor"), true);
  assert.equal(puedeCargarPersonal(actor, "B", "gestor", rol("A", "gestor")), false);
  assert.equal(puedeCargarPersonal(actor, "C", "gestor"), false);
  const cambiarB = (cambio) => ({...actor, empresasDetalle: {...actor.empresasDetalle, B: cambio}});
  assert.equal(puedeCargarPersonal(cambiarB({apps: []}), "B", "gestor", rol("B", "administrador")), false);
  assert.equal(puedeCargarPersonal(cambiarB({apps: [app], estadoLaboral: "inactivo"}), "B", "gestor"), false);
  assert.equal(puedeCargarPersonal(cambiarB({apps: [app], soloTalentoHumano: true}), "B", "gestor"), false);
  assert.equal(puedeCargarPersonal(cambiarB({apps: ["admindashboard"]}), "B", "gestor"), true);
});

test("catálogos y alta atómica en empresa secundaria con Firestore", {
  skip: !process.env.FIRESTORE_EMULATOR_HOST,
}, async () => {
  const firebase = admin.initializeApp({projectId: "demo-talento-carga"});
  const db = firebase.firestore();
  try {
    const fixtures = {
      "TBL_EMPRESAS/A": {nombre: "Empresa A"},
      "TBL_EMPRESAS/B": {nombre: "Empresa B"},
      "TBL_USUARIOS/gestor": actor,
      "TBL_TALENTO_HUMANO_ROLES/A_gestor": rol("A", "consulta"),
      "TBL_TALENTO_HUMANO_ROLES/B_gestor": rol("B", "gestor"),
      "TBL_TIPO_DOCUMENTO/CC": {codigo: "CC", descripcion: "Cédula"},
      "TBL_AREAS/b_area": {empresaId: "B", nombre: "Área B"},
      "TBL_AREAS/a_area": {empresaId: "A", nombre: "Área A"},
      "TBL_AREAS/b_area2": {empresaId: "B", nombre: "Segunda área"},
      "TBL_CARGOS/cargo_b": {empresaId: "B", nombre: "Auxiliar", areaId: "b_area"},
      "TBL_CENTROS_COSTOS/centro_b": {empresaId: "B", codigo: "001", nombre: "Sede Norte"},
      "TBL_CENTROS_COSTOS/centro_apagado": {empresaId: "B", codigo: "002", nombre: "Sede Sur", enabled: false},
      "TBL_USUARIOS/jefa": {empresaId: "A", empresas: ["A", "B"], cedula: "123",
        nombreCompleto: "María Silva", cargo: "Cargo de A", empresasDetalle: {B: {cargo: "Cargo de B"}}},
      "TBL_USUARIOS/historico": {empresaId: "A", cedula: "234", nombre: "Empleado anterior"},
    };
    const lote = db.batch();
    for (const [path, data] of Object.entries(fixtures)) lote.set(db.doc(path), data);
    await lote.commit();
    const context = {
      auth: {
        uid: "todo_" + createHash("sha256").update("gestor").digest("hex"),
        token: {authVersion: 2, userDocId: "gestor"},
      },
    };
    const llamada = (accion, extra = {}) => procesarCargaPersonal({accion, empresaId: "B", ...extra}, context);
    const catalogo = await llamada("catalogo");
    assert.deepEqual(catalogo.area, ["Área B", "Segunda área"]);
    assert.deepEqual(catalogo.centroCostos, ["001 — Sede Norte"]);
    assert.deepEqual(catalogo.jefe, ["María Silva — 123"]);
    await assert.rejects(llamada("catalogo", {empresaId: "A"}), {code: "permission-denied"});
    await assert.rejects(procesarCargaPersonal({accion: "catalogo", empresaId: "B"}, {}), {code: "unauthenticated"});

    const fila = {
      fila: 2, cedula: "001234", nombres: "Andrea", apellidos: "Pérez",
      tipo_documento: "CC — Cédula", area: "Área B", cargo: "Auxiliar — Área B",
      centroCostos: "001 — Sede Norte", jefe: "María Silva — 123",
    };
    const carga = {empresaPlantilla: "B", filas: [fila]};
    await assert.rejects(llamada("validar", {...carga, empresaPlantilla: "A"}), {code: "invalid-argument"});
    const revision = await llamada("validar", carga);
    assert.equal(revision.vistas.length, 1);
    const usuario = db.doc("TBL_USUARIOS/001234");
    assert.equal((await usuario.get()).exists, false);
    const conErrores = await llamada("importar", {...carga, filas: [
      fila,
      {...fila, fila: 5, cedula: "234", area: "Segunda área"},
      {...fila, fila: 8, area: "Área A"},
    ]});
    assert.deepEqual(conErrores.errores.map((e) => e.fila), [5, 8]);
    assert.match(conErrores.errores[0].mensaje, /ya registrado.*pertenece a otra área/);
    assert.match(conErrores.errores[1].mensaje, /repetido.*Área no disponible/);
    assert.equal((await usuario.get()).exists, false);

    await db.doc("TBL_TALENTO_HUMANO_ROLES/B_gestor").update({rol: "consulta"});
    await assert.rejects(llamada("importar", carga), {code: "permission-denied"});
    await db.doc("TBL_TALENTO_HUMANO_ROLES/B_gestor").update({rol: "gestor"});
    const dosCargas = await Promise.all([llamada("importar", carga), llamada("importar", carga)]);
    assert.equal(dosCargas.reduce((n, r) => n + r.creados, 0), 1);
    assert.match(dosCargas.find((r) => r.creados === 0).errores[0].mensaje, /ya registrado/);
    const datos = (await usuario.get()).data();
    assert.equal(datos.empresaId, "B");
    assert.equal(datos.empresasDetalle.B.cargoJefe, "Cargo de B");
    assert.equal(datos.empresasDetalle.B.centroId, "centro_b");
    assert.deepEqual(datos.apps, []);
    assert.equal((await db.doc("TBL_ESTRUCTURA_ORGANIZACIONAL/001234").get()).data().areaId, "b_area");
    assert.equal((await db.doc("TBL_EMPLEADOS/B_001234").get()).data().cargoId, "cargo_b");
    assert.equal((await db.doc("TBL_CEDULAS/001234").get()).data().usuarioRef.path, usuario.path);
    assert.deepEqual((await db.doc("TBL_USUARIOS/historico").get()).data(), fixtures["TBL_USUARIOS/historico"]);
  } finally {
    await firebase.delete();
  }
});
