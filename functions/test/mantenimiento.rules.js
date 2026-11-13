const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const admin = require("firebase-admin");
const {mantenimientoOrden} = require("../lib/mantenimiento_ordenes");
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
const accesos = "TBL_MANTENIMIENTO_ACCESOS";
const projectId = "demo-mantenimiento";
assert.ok(process.env.FIRESTORE_EMULATOR_HOST, "Solo emulador.");
admin.initializeApp({projectId, storageBucket: `${projectId}.appspot.com`});
const dbAdmin = admin.firestore();
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
    projectId,
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
    "TBL_USUARIOS/gestor": {empresaId: "A", apps: ["admindashboard"]},
    [`${accesos}/A_gestor`]: {empresaId: "A", userId: "gestor", gestor: true, operador: false},
    [`${accesos}/A_operario`]: {empresaId: "A", userId: "operario", operador: true},
    [`${accesos}/A_inhabilitado`]: {empresaId: "A", userId: "inhabilitado", operador: true},
    [`TBL_APPS/A_${app}`]: {empresaId: "A", appId: app, enabled: true},
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
test.after(async () => {
  await env?.cleanup();
  await admin.app().delete();
});

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

test("el cliente consulta órdenes y deja todas las escrituras al servidor", async () => {
  const db = cuenta("operario");
  const ref = doc(db, ordenes, "orden-A");
  await assertFails(setDoc(ref, orden({equipoId: "equipo-B"})));
  await assertFails(setDoc(ref, orden({hallazgoId: "hallazgo-B"})));
  await assertFails(setDoc(ref, orden({centroDocId: "otro-A", hallazgoId: "hallazgo-A"})));
  await assertFails(setDoc(ref, orden({equipoId: "equipo-A", hallazgoId: "hallazgo-A"})));
  await sembrar({[`${ordenes}/orden-A`]: orden()});
  await assertSucceeds(getDoc(ref));
  const cerrar = {
    estado: "cerrada", resultado: "Se corrigió la fuga", factura: "F-12",
    updatedAt: serverTimestamp(), cerradaAt: serverTimestamp(),
  };
  await assertFails(updateDoc(ref, cerrar));
  await assertFails(updateDoc(ref, {estado: "en_curso", updatedAt: serverTimestamp()}));
  await assertFails(updateDoc(ref, {...cerrar, centroDocId: "otro-A"}));
  await assertFails(updateDoc(ref, {...cerrar, resultado: "   "}));
  await assertFails(updateDoc(ref, cerrar));
  await assertFails(updateDoc(ref, {factura: "F-13", updatedAt: serverTimestamp()}));
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

test("una ficha alterada no concede acceso ni permite habilitar la app", async () => {
  const db = cuenta("sinapp");
  const admin = cuenta("gestor");
  const appRef = `TBL_APPS/A_${app}`;
  const permiso = `${accesos}/A_sinapp`;
  const data = {empresaId: "A", userId: "sinapp", operador: true, updatedAt: serverTimestamp()};
  await assertSucceeds(updateDoc(doc(db, "TBL_USUARIOS/sinapp"), {
    apps: [app, "admindashboard"], desarrollador: true,
  }));
  await assertFails(getDoc(doc(db, equipos, "equipo-A")));
  await assertFails(setDoc(doc(db, permiso), data));
  await assertFails(updateDoc(doc(db, appRef), {enabled: false}));
  await assertFails(deleteDoc(doc(db, appRef)));
  await assertFails(setDoc(doc(admin, permiso), {...data, gestor: true}));
  await assertSucceeds(setDoc(doc(admin, permiso), data));
  await assertSucceeds(getDoc(doc(db, equipos, "equipo-A")));
  await assertSucceeds(updateDoc(doc(admin, appRef), {enabled: false}));
  await assertFails(getDoc(doc(db, equipos, "equipo-A")));
  await assertSucceeds(updateDoc(doc(admin, appRef), {enabled: true}));
  await assertSucceeds(updateDoc(doc(admin, permiso), {operador: false, updatedAt: serverTimestamp()}));
  await assertFails(getDoc(doc(db, equipos, "equipo-A")));
  await assertFails(setDoc(doc(admin, `${accesos}/B_operario`), {
    empresaId: "B", userId: "operario", operador: true, updatedAt: serverTimestamp(),
  }));
});

test("consecutivos por empresa, estructura y cierre con evidencia en el servidor", {
  skip: !process.env.FIREBASE_STORAGE_EMULATOR_HOST,
}, async () => {
  const datos = {
    tipo: "preventivo", intervencion: "coccion", titulo: "Revisar estufa",
    detalle: "Inspección", centroDocId: "centro-A", subcentroId: "rancho",
    hallazgoId: "hallazgo-A",
  };
  await sembrar({
    "TBL_CENTROS_COSTOS/centro-A": {
      empresaId: "A", centroId: "sede-A", subcentros: [{id: "rancho", nombre: "Rancho"}],
    },
    "TBL_INTERVENTORIA_HALLAZGOS/hallazgo-A": {
      empresaId: "A", centroCostoId: "sede-A", subcentroId: "rancho",
    },
  });
  const call = (accion, input = {}, userDocId = "operario") => mantenimientoOrden.run(
    {empresaId: "A", ordenId: "nueva", accion, ...input},
    {auth: {uid: userDocId, token: {authVersion: 2, userDocId}}},
  );
  const ref = dbAdmin.doc(`${ordenes}/nueva`);
  const version = async () => {
    const {updatedAt} = (await ref.get()).data();
    return {segundos: updatedAt.seconds, nanosegundos: updatedAt.nanoseconds};
  };
  await assert.rejects(call("crear", {...datos, subcentroId: ""}), {code: "invalid-argument"});
  await assert.rejects(call("crear", datos, "sinapp"), {code: "permission-denied"});
  const nuevas = await Promise.all([
    call("crear", datos), call("crear", {...datos, ordenId: "segunda"}),
  ]);
  assert.deepEqual(nuevas.map(x => x.numero).sort(), [1, 2]);
  assert.deepEqual(await call("crear", datos), nuevas[0]);
  assert.equal((await ref.get()).data().subcentroNombre, "Rancho");
  await assertSucceeds(getDoc(doc(cuenta("operario"), ordenes, "nueva")));
  await assertFails(updateDoc(doc(cuenta("operario"), ordenes, "nueva"), {
    estado: "en_curso", updatedAt: serverTimestamp(),
  }));
  const previo = await version();
  await call("borrador", {...previo, materiales: "Empaque"});
  await assert.rejects(call("editar", {...previo, ...datos}), {code: "aborted"});
  assert.equal((await ref.get()).data().estado, "abierta");
  const cierre = {...await version(), trabajo: "Ajuste final", tecnico: "Técnico", receptor: "Responsable"};
  await assert.rejects(call("cerrar", cierre), {code: "failed-precondition"});
  const base64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aT2QAAAAASUVORK5CYII=";
  const adjunto = {archivoId: "foto", clase: "evidencia", mime: "image/png", nombre: "cierre.png", base64};
  await call("adjuntar", adjunto);
  await call("adjuntar", adjunto);
  assert.equal((await ref.get()).data().archivos.length, 1);
  const secreto = dbAdmin.doc("TBL_MANTENIMIENTO_ARCHIVOS/foto");
  const [cifrado] = await admin.storage().bucket().file((await secreto.get()).data().path).download();
  assert.notEqual(cifrado.toString("base64"), base64);
  await assertFails(getDoc(doc(cuenta("operario"), secreto.path)));
  await assertFails(getDoc(doc(cuenta("operario"), "TBL_MANTENIMIENTO_CONTADORES/A")));
  assert.deepEqual(await call("leerArchivo", {archivoId: "foto"}), {base64});
  await assert.rejects(call("leerArchivo", {archivoId: "foto", ordenId: "segunda"}), {code: "not-found"});
  await call("cerrar", cierre);
  assert.equal((await ref.get()).data().estado, "cerrada");
  await assert.rejects(call("quitarArchivo", {archivoId: "foto"}), {code: "failed-precondition"});
  await assert.rejects(call("editar", {...datos, ...await version()}), {code: "failed-precondition"});
  await sembrar({[`${accesos}/A_operario`]: {empresaId: "A", userId: "operario", operador: false}});
  await assert.rejects(call("leerArchivo", {archivoId: "foto"}), {code: "permission-denied"});
});

test("la bandeja reúne los tres orígenes y enlaza cada tarea a una sola orden", async () => {
  const tarea = {
    empresaId: "A", areaId: "area-m", estado: "pendiente",
    titulo: "Reparar puerta", descripcion: "Bisagra suelta",
    asignado_nombre: "Técnico", centroId: "sede-A",
  };
  await sembrar({
    "TBL_CENTROS_COSTOS/centro-A": {
      empresaId: "A", centroId: "sede-A", subcentros: [{id: "rancho", nombre: "Rancho"}],
    },
    "TBL_INTERVENTORIA_HALLAZGOS/hallazgo-A": {
      empresaId: "A", centroCostoId: "sede-A", subcentroId: "rancho",
    },
    "TBL_AREAS/area-m": {empresaId: "A", nombre: "Mantenimiento"},
    "TBL_AREAS/area-calidad": {empresaId: "A", nombre: "Calidad"},
    [`${accesos}/A_operario`]: {empresaId: "A", userId: "operario", operador: true},
    "TBL_TAREAS/m": {...tarea, sourceModule: "tareas", centroId: "global", titulo: "Ajustar toma"},
    "TBL_TAREAS/i": {...tarea, sourceModule: "interventoria", hallazgoId: "hallazgo-A", subcentroId: "rancho"},
    "TBL_TAREAS/v": {...tarea, source: {moduleId: "visita"}, titulo: "Revisar refrigerador"},
    "TBL_TAREAS/b": {...tarea, empresaId: "B"},
    "TBL_TAREAS/cerrada": {...tarea, estado: "finalizado"},
    "TBL_TAREAS/revision": {...tarea, estado: "por_aprobar"},
    "TBL_TAREAS/compras": {...tarea, sourceModule: "compras"},
    "TBL_TAREAS/calidad": {...tarea, areaId: "area-calidad", areaNombre: "Mantenimiento"},
  });
  const call = (accion, data = {}, userDocId = "operario") => mantenimientoOrden.run(
    {empresaId: "A", accion, ...data},
    {auth: {uid: userDocId, token: {authVersion: 2, userDocId}}},
  );
  const {tareas} = await call("tareas");
  assert.deepEqual(tareas.map(({id, origen, centroDocId}) => [id, origen, centroDocId]), [
    ["m", "manual", ""], ["i", "interventoria", "centro-A"], ["v", "visitas", "centro-A"],
  ]);
  await assert.rejects(call("tareas", {empresaId: "B"}), {code: "permission-denied"});
  await assert.rejects(call("tareas", {}, "inhabilitado"), {code: "permission-denied"});
  const datos = {
    tipo: "correctivo", intervencion: "infraestructura", titulo: tarea.titulo,
    detalle: tarea.descripcion, centroDocId: "centro-A", ordenId: "solicitud",
  };
  for (const tareaId of ["b", "cerrada", "revision", "compras", "calidad"]) {
    await assert.rejects(call("crear", {...datos, tareaId}), {code: "failed-precondition"});
  }
  await assert.rejects(call("crear", {...datos, tareaId: "i", centroDocId: "otro-A"}), {code: "invalid-argument"});
  await assert.rejects(call("crear", {...datos, tareaId: "i"}), {code: "invalid-argument"});
  const conversion = {...datos, tareaId: "i", subcentroId: "rancho"};
  const resultados = await Promise.all([
    call("crear", conversion), call("crear", {...conversion, ordenId: "segunda-solicitud"}),
  ]);
  assert.equal(resultados[0].ordenId, resultados[1].ordenId);
  assert.equal(resultados[0].numero, resultados[1].numero);
  assert.equal(resultados.filter((resultado) => resultado.existente).length, 1);
  const doc = (await dbAdmin.doc(`${ordenes}/${resultados[0].ordenId}`).get()).data();
  assert.equal(doc.tareaId, "i");
  assert.equal(doc.origenTarea, "interventoria");
  assert.equal(doc.hallazgoId, "hallazgo-A");
  assert.equal(doc.estado, "abierta");
  assert.equal((await dbAdmin.doc("TBL_TAREAS/i").get()).data().estado, "pendiente");
  const reintento = await call("crear", {...conversion, ordenId: doc.solicitudId});
  assert.equal(reintento.mismaSolicitud, true);
  const manual = await call("crear", {...datos, tareaId: "m"});
  assert.equal((await dbAdmin.doc(`${ordenes}/${manual.ordenId}`).get()).data().centroDocId, "centro-A");
  const visita = await call("crear", {...datos, tareaId: "v"});
  assert.equal((await dbAdmin.doc(`${ordenes}/${visita.ordenId}`).get()).data().origenTarea, "visitas");
});

test("varias tareas de una sede comparten una sola orden sin duplicación", async () => {
  const datos = {empresaId: "A", areaId: "area-m", estado: "pendiente", centroId: "sede-A", titulo: "Trabajo"};
  await sembrar({
    "TBL_TAREAS/grupo-i": {...datos, sourceModule: "interventoria", subcentroId: "rancho"},
    "TBL_TAREAS/grupo-v": {...datos, sourceModule: "visitas"},
    "TBL_TAREAS/grupo-otro": {...datos, centroId: "otra-sede-A"},
  });
  const call = (data) => mantenimientoOrden.run({
    empresaId: "A", accion: "crear", ordenId: "grupo", tipo: "correctivo", intervencion: "otros",
    titulo: "Orden agrupada", detalle: "Trabajos de la sede", centroDocId: "centro-A",
    tareaId: "grupo-i", ...data,
  }, {auth: {uid: "operario", token: {authVersion: 2, userDocId: "operario"}}});
  await assert.rejects(call({tareaIds: ["grupo-otro"]}), {code: "invalid-argument"});
  const primera = await call({tareaIds: ["grupo-v"]});
  const agrupada = (await dbAdmin.doc(`${ordenes}/${primera.ordenId}`).get()).data();
  assert.deepEqual(agrupada.tareaIds, ["grupo-i", "grupo-v"]);
  assert.equal(agrupada.tareasOrigen[0].subcentroId, "rancho");
  const [reintento, segunda] = await Promise.all([
    call({tareaIds: ["grupo-v"]}),
    call({tareaId: "grupo-v", ordenId: "individual"}),
  ]);
  assert.equal(reintento.mismaSolicitud, true);
  assert.equal(segunda.ordenId, primera.ordenId);
  await assert.rejects(call({tareaId: "grupo-v", tareaIds: ["grupo-otro"]}), {code: "already-exists"});
});

test("alta en temporal, traslado parcial y baja obligatoria quedan registrados una vez", {
  skip: !process.env.FIREBASE_STORAGE_EMULATOR_HOST,
}, async () => {
  const {PDFDocument} = require("pdf-lib");
  const {mantenimientoInventario} = require("../lib/mantenimiento_inventario");
  const {minimosAnexo} = require("../lib/mantenimiento_anexo");
  assert.equal(minimosAnexo(1000)[0], 10);
  assert.equal(minimosAnexo(1001)[0], 12);
  assert.equal(minimosAnexo(10001).length, 0);

  const call = (accion, input = {}, userDocId = "operario") => mantenimientoInventario.run(
    {empresaId: "A", accion, ...input},
    {auth: {uid: userDocId, token: {authVersion: 2, userDocId}}},
  );
  await sembrar({
    [`${accesos}/A_operario`]: {empresaId: "A", userId: "operario", operador: true, gestor: true},
    "TBL_COMPRAS_PROVEEDORES/pa": {empresaId: "A", razonSocial: "Proveedor A"},
    "TBL_COMPRAS_PROVEEDORES/pb": {empresaId: "B", razonSocial: "Proveedor B"},
    "TBL_CENTROS_COSTOS/centro-A": {empresaId: "A", centroId: "sede-A", nombre: "Establecimiento A"},
  });
  const catalogo = await call("catalogos");
  assert.deepEqual(catalogo.proveedores.map((p) => p.id), ["pa"]);
  await assert.rejects(call("catalogos", {empresaId: "B"}), {code: "permission-denied"});
  const pdf = await PDFDocument.create();
  pdf.addPage();
  const base64 = Buffer.from(await pdf.save()).toString("base64");
  const foto = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aT2QAAAAASUVORK5CYII=";
  await call("subirArchivo", {clase: "ficha", mime: "application/pdf", nombre: "ficha.pdf", archivoId: "ficha", base64});
  await call("subirArchivo", {clase: "foto", mime: "image/png", nombre: "baja.png", archivoId: "evidencia", base64: foto});
  const datos = {codigo: "LOTE-50", nombre: "Marmitas", categoria: "equipo", propiedad: "propio",
    familia: "anexo_2", grupo: true, cantidad: 50, fechaIngreso: "2026-11-13", archivos: ["ficha"],
    solicitudId: "alta"};
  await assert.rejects(call("alta", {...datos, proveedorId: "pb"}), {code: "invalid-argument"});
  const alta = await call("alta", {...datos, proveedorId: "pa"});
  assert.deepEqual(await call("alta", {...datos, proveedorId: "pa"}), alta);
  const equipoId = alta.id;
  const ref = dbAdmin.doc(`${equipos}/${equipoId}`);
  assert.deepEqual((await ref.get()).data().existencias, {_bodega_temporal: 50});
  await assertFails(updateDoc(doc(cuenta("operario"), ref.path), {centroDocId: "centro-A", updatedAt: serverTimestamp()}));
  const plan = {centroDocId: "centro-A", ppl: 2300, cantidades: {anexo_2: 4},
    responsableId: "operario", coordinadorId: "operario", validar: true};
  await call("minimos", plan);
  await assertFails(getDoc(doc(cuenta("operario"), "TBL_MANTENIMIENTO_MINIMOS/A_centro-A")));
  const traslado = {equipoId, origen: "_bodega_temporal", destino: "centro-A",
    cantidad: 5, solicitudId: "traslado", entrega: "Bodega", recibe: "Establecimiento"};
  await assert.rejects(call("traslado", {...traslado, destino: "centro-B"}), {code: "invalid-argument"});
  const movimientos = await Promise.all([call("traslado", traslado), call("traslado", traslado)]);
  assert.deepEqual(movimientos[0], movimientos[1]);
  assert.deepEqual((await ref.get()).data().existencias, {_bodega_temporal: 45, "centro-A": 5});
  await assert.rejects(call("baja", {equipoId, origen: "centro-A", cantidad: 1, observaciones: "Daño",
    solicitudId: "sin-evidencia"}), {code: "invalid-argument"});
  const baja = {equipoId, origen: "centro-A", cantidad: 5, observaciones: "Daño",
    solicitudId: "baja", archivos: ["evidencia"]};
  const reemplazo = await call("baja", baja);
  assert.ok(reemplazo.tareaId);
  assert.deepEqual(await call("baja", baja), reemplazo);
  assert.deepEqual((await ref.get()).data().existencias, {_bodega_temporal: 45});
  assert.equal((await dbAdmin.doc(`TBL_TAREAS/${reemplazo.tareaId}`).get()).get("asignado_uid"), "operario");
  assert.equal((await call("historial", {equipoId})).movimientos.length, 2);
  assert.deepEqual(await call("leerArchivo", {archivoId: "evidencia"}), {base64: foto});
  await assertFails(getDoc(doc(cuenta("operario"), `${ref.path}/movimientos/baja`)));
  const tareas = await mantenimientoOrden.run({empresaId: "A", accion: "tareas"},
    {auth: {uid: "operario", token: {authVersion: 2, userDocId: "operario"}}});
  assert.ok(tareas.tareas.some((t) => t.id === reemplazo.tareaId && t.origen === "inventario"));
});
