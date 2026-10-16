import * as admin from "firebase-admin";
import * as functions from "firebase-functions/v1";
import {createHash, randomBytes, scryptSync, timingSafeEqual} from "crypto";
import {empresasSeleccionables} from "./acceso";
import {appsDeEmpresa, raizEsDeEmpresa} from "./apps_por_empresa";
import {BioData, calcularBio, fechaBio, diaBio, validarHorario} from "./biometrico_calculo";

export const BIO = {devices: "TBL_BIOMETRICO_DISPOSITIVOS", credentials: "TBL_BIOMETRICO_CREDENCIALES",
  events: "TBL_BIOMETRICO_EVENTOS", schedules: "TBL_BIOMETRICO_HORARIOS", plans: "TBL_BIOMETRICO_JORNADAS",
  approvals: "TBL_BIOMETRICO_APROBACIONES", audit: "TBL_BIOMETRICO_AUDITORIA", pins: "TBL_BIOMETRICO_PINES"};
const db = () => admin.firestore();
const sha = (v: string) => createHash("sha256").update(v).digest("hex");
const fail = (msg: string, code: functions.https.FunctionsErrorCode = "invalid-argument"): never => {
  throw new functions.https.HttpsError(code, msg);
};
function id(v: unknown): string {
  if (typeof v !== "string" || !v.trim() || v.length > 160 || v.includes("/")) fail("Identificador inválido.");
  return (v as string).trim();
}
function texto(v: unknown, max = 200): string {
  if (typeof v !== "string" || !v.trim() || v.length > max) fail("Completa el texto requerido.");
  return (v as string).trim();
}
function pertenece(d: BioData | undefined, empresaId: string): asserts d is BioData {
  if (!d || d.empresaId !== empresaId) fail("Registro no disponible en la empresa activa.", "permission-denied");
}
function plain(v: any): any {
  if (v instanceof admin.firestore.Timestamp) return v.toDate().toISOString();
  if (Array.isArray(v)) return v.map(plain);
  if (v && typeof v === "object") return Object.fromEntries(Object.entries(v).filter(([k]) => k !== "tokenHash").map(([k, x]) => [k, plain(x)]));
  return v;
}
// PIN personal de los administradores que registran huellas en el equipo. Solo se guarda
// su derivación (scrypt con sal propia); los intentos fallidos bloquean la cuenta.
export const PIN_INTENTOS = 5;
export const PIN_BLOQUEO_MS = 15 * 60000;
export const SESION_REGISTRO_MS = 5 * 60000;
export function pinSimple(pin: string): boolean {
  if (/^(\d)\1+$/.test(pin)) return true;
  const d = [...pin].map(Number);
  return d.every((v, i) => i === 0 || v - d[i - 1] === 1) || d.every((v, i) => i === 0 || d[i - 1] - v === 1);
}
export function pinFormatoValido(pin: unknown): pin is string {
  return typeof pin === "string" && /^\d{6}$/.test(pin) && !pinSimple(pin);
}
export function derivarPin(pin: string, salt: string): string {
  return scryptSync(pin, Buffer.from(salt, "hex"), 32).toString("hex");
}
export function pinCoincide(pin: string, salt: string, hash: string): boolean {
  const a = Buffer.from(derivarPin(pin, salt), "hex"); const b = Buffer.from(hash, "hex");
  return a.length === b.length && timingSafeEqual(a, b);
}
// Niveles propios de Biometrico, materializados por el editor común de Admin.
export function nivelBio(u: BioData, empresaId: string, userId: string, rol?: BioData): string {
  if (!empresasSeleccionables(u).includes(empresaId)) return "";
  const scoped = u.empresasDetalle?.[empresaId] || {};
  const normalize = (v: any) => String(v || "").trim().toLowerCase().replace(/[\s-]+/g, "_");
  const global = normalize(u.roleKey || u.role_key || u.role || u.rol);
  const local = normalize(scoped.roleKey || scoped.role_key || scoped.roleId || (raizEsDeEmpresa(u, empresaId) ? global : ""));
  const roleId = normalize(scoped.roleId || u.roleId);
  const dev = [global, local].some((v) => ["developer", "desarrollador"].includes(v)) || /_(developer|desarrollador)$/.test(roleId);
  if (dev) return "administrador";
  if (scoped.soloTalentoHumano === true || (scoped.soloTalentoHumano === undefined && raizEsDeEmpresa(u, empresaId) && u.soloTalentoHumano === true)) return "";
  const apps = appsDeEmpresa(u, empresaId).map((v) => v.toLowerCase());
  if (apps.some((v) => ["admindashboard", "admin"].includes(v))) return "administrador";
  if (!apps.some((v) => ["biometricodashboard", "biometrico"].includes(v))) return "";
  if (!rol) return "consulta";
  return rol.empresaId === empresaId && rol.userId === userId && ["consulta", "gestor", "administrador"].includes(rol.rol) ? rol.rol : "";
}
export async function actorBio(input: BioData, context: functions.https.CallableContext) {
  const userId = String(context.auth?.token.userDocId || "");
  if (!context.auth || context.auth.token.authVersion !== 2 || !userId || userId.includes("/") ||
      context.auth.uid !== `todo_${sha(userId)}`) fail("Inicia sesión de nuevo.", "unauthenticated");
  const empresaId = id(input.empresaId);
  const [u, r, module] = await Promise.all([db().doc(`TBL_USUARIOS/${userId}`).get(),
    db().doc(`TBL_BIOMETRICO_ROLES/${empresaId}_${userId}`).get(), db().doc(`TBL_APPS/${empresaId}_biometricodashboard`).get()]);
  const nivel = u.exists ? nivelBio(u.data()!, empresaId, userId, r.data()) : "";
  if (!nivel) fail("No tienes acceso a Biometrico en esta empresa.", "permission-denied");
  if (module.data()?.enabled === false) fail("Biométrico está deshabilitado en esta empresa.", "permission-denied");
  return {userId, empresaId, nivel};
}
function audit(tx: FirebaseFirestore.Transaction, a: {userId: string; empresaId: string}, accion: string, datos: BioData) {
  tx.create(db().collection(BIO.audit).doc(), {...a, accion, datos, fecha: admin.firestore.Timestamp.now()});
}
async function persona(userId: string, empresaId: string, tx?: FirebaseFirestore.Transaction) {
  const ref = db().doc(`TBL_USUARIOS/${id(userId)}`);
  const p = (await (tx ? tx.get(ref) : ref.get())).data();
  if (!p || !empresasSeleccionables(p).includes(empresaId)) fail("El colaborador no está habilitado en esta empresa.", "failed-precondition");
  return p!;
}
function rango(b: BioData) {
  const desde = texto(b.desde, 10); const hasta = texto(b.hasta, 10);
  const a = fechaBio(desde); const z = fechaBio(hasta);
  if (z < a || z - a > 30 * 86400000) fail("Selecciona un rango máximo de 31 días.");
  return {desde, hasta, a, z};
}
async function informe(empresaId: string, b: BioData, tx?: FirebaseFirestore.Transaction) {
  const {desde, hasta, a, z} = rango(b);
  const read = async (col: string) => {
    const base = db().collection(col).where("empresaId", "==", empresaId);
    const q = col === BIO.events ? base.where("capturadoMs", ">=", a - 86400000).where("capturadoMs", "<", z + 2 * 86400000) :
      base.where("dia", ">=", diaBio(a - 86400000)).where("dia", "<=", hasta);
    const snap = await (tx ? tx.get(q) : q.get());
    return snap.docs.map((d) => ({...d.data(), id: d.id} as BioData));
  };
  // Consulta acotada al periodo, con un día adicional para emparejar noches.
  const [events, plans, approvals] = await Promise.all([read(BIO.events), read(BIO.plans), read(BIO.approvals)]);
  const filtered = events.filter((e) => e.capturadoMs >= a - 86400000 && e.capturadoMs < z + 2 * 86400000 && (!b.userId || e.userId === b.userId));
  const rows = calcularBio(filtered, plans.filter((p) => !b.userId || p.userId === b.userId), desde, hasta);
  const names = new Map<string, string>();
  await Promise.all([...new Set(rows.map((r) => String(r.userId)))].map(async (uid) => {
    const ref = db().doc(`TBL_USUARIOS/${uid}`);
    const u = (await (tx ? tx.get(ref) : ref.get())).data() || {};
    names.set(uid, String(u.nombreCompleto || u.nombre || `${u.nombres || ""} ${u.apellidos || ""}`).trim() || uid);
  }));
  return rows.map((r): BioData => {
    const revision = sha(JSON.stringify(r));
    const approval = approvals.find((x) => x.userId === r.userId && x.dia === r.dia);
    const vigente = approval?.revision === revision;
    return {...r, nombre: names.get(r.userId) || r.userId, revision, estado: vigente ? approval!.estado : "pendiente", aprobado: vigente && approval!.estado === "aprobado" ? r.extra : 0,
      decision: approval ? {...approval, vigente} : null};
  });
}

export async function gestionarBiometrico(b: BioData, context: functions.https.CallableContext): Promise<BioData> {
  const a = await actorBio(b || {}, context);
  const lecturas = ["listar", "buscarPersona", "vinculos", "informe", "personas", "calendario"];
  const administracion = ["crearDispositivo", "rotarToken", "revocarDispositivo", "vincular", "desvincular", "eliminarHuella", "fijarPin"];
  if (a.nivel === "consulta" && !lecturas.includes(b.accion)) fail("Tu nivel solo permite consultar.", "permission-denied");
  if (administracion.includes(b.accion) && a.nivel !== "administrador") fail("Solo el administrador de Biométrico gestiona dispositivos y vínculos.", "permission-denied");
  const read = async (col: string) => (await db().collection(col).where("empresaId", "==", a.empresaId).get()).docs.map((d) => plain({...d.data(), id: d.id}));
  if (b.accion === "listar") {
    const [devices, horarios] = await Promise.all([read(BIO.devices), read(BIO.schedules)]);
    const [pin, centrosSnap, primero] = await Promise.all([db().doc(`${BIO.pins}/${a.empresaId}_${a.userId}`).get(),
      db().collection("TBL_CENTROS_COSTOS").where("empresaId", "==", a.empresaId).get(),
      db().collection(BIO.events).where("empresaId", "==", a.empresaId).orderBy("capturadoMs", "asc").limit(1).get()]);
    const centros = centrosSnap.docs.filter((d) => d.data().enabled !== false)
      .map((d) => ({id: d.id, codigo: String(d.data().codigo || ""), nombre: String(d.data().nombre || d.id)}))
      .sort((x, y) => x.nombre.localeCompare(y.nombre));
    const primerMs = primero.docs[0]?.data().capturadoMs;
    return {devices, horarios, nivel: a.nivel, tienePin: !!pin.data()?.pinHash, centros,
      primerDia: typeof primerMs === "number" ? diaBio(primerMs) : null};
  }
  if (b.accion === "personas") {
    // Personas habilitadas en la empresa activa y si ya tienen una huella vinculada vigente.
    const [porLista, porRaiz, dispositivos] = await Promise.all([
      db().collection("TBL_USUARIOS").where("empresas", "array-contains", a.empresaId).get(),
      db().collection("TBL_USUARIOS").where("empresaId", "==", a.empresaId).get(),
      db().collection(BIO.devices).where("empresaId", "==", a.empresaId).get()]);
    const vinculos = await Promise.all(dispositivos.docs.map((d) => d.ref.collection("vinculos").where("activo", "==", true).get()));
    const vinculadas = new Set(vinculos.flatMap((s) => s.docs.map((v) => String(v.data().userId))));
    const docs = new Map([...porLista.docs, ...porRaiz.docs].map((d) => [d.id, d]));
    const personas = [...docs.values()].filter((d) => empresasSeleccionables(d.data()).includes(a.empresaId)).map((d) => {
      const u = d.data();
      return {id: d.id, cedula: String(u.cedula || d.id), vinculada: vinculadas.has(d.id),
        nombre: String(u.nombreCompleto || u.nombre || `${u.nombres || ""} ${u.apellidos || ""}`).trim() || d.id};
    }).sort((x, y) => x.nombre.localeCompare(y.nombre));
    return {personas};
  }
  if (b.accion === "calendario") {
    const {desde, hasta} = rango(b);
    const snap = await db().collection(BIO.plans).where("empresaId", "==", a.empresaId).where("dia", ">=", desde).where("dia", "<=", hasta).get();
    return {asignaciones: snap.docs.map((d) => {
      const p = d.data();
      return {userId: p.userId, dia: p.dia, nombre: p.nombre, libre: p.libre === true, horarioId: p.horarioId || null, inicio: p.inicio, fin: p.fin};
    })};
  }
  if (b.accion === "fijarPin") {
    if (!pinFormatoValido(b.pin)) fail("El PIN debe tener 6 números y no ser repetido ni consecutivo.");
    const ref = db().doc(`${BIO.pins}/${a.empresaId}_${a.userId}`);
    let rechazo = "";
    await db().runTransaction(async (tx) => {
      rechazo = "";
      const previo = (await tx.get(ref)).data();
      if (previo?.bloqueadoHastaMs > Date.now()) {
        rechazo = "PIN bloqueado temporalmente por intentos fallidos.";
        return;
      }
      if (previo?.pinHash) {
        if (typeof b.pinActual !== "string" || !/^\d{6}$/.test(b.pinActual)) {
          rechazo = "Escribe tu PIN actual.";
          return;
        }
        if (!pinCoincide(b.pinActual, previo.salt, previo.pinHash)) {
          const fallos = Number(previo.fallos || 0) + 1;
          tx.update(ref, {fallos: fallos >= PIN_INTENTOS ? 0 : fallos, bloqueadoHastaMs: fallos >= PIN_INTENTOS ? Date.now() + PIN_BLOQUEO_MS : 0});
          rechazo = "PIN actual incorrecto.";
          return;
        }
      }
      const salt = randomBytes(16).toString("hex");
      tx.set(ref, {empresaId: a.empresaId, userId: a.userId, salt, pinHash: derivarPin(b.pin, salt), fallos: 0, bloqueadoHastaMs: 0,
        actualizadoAt: admin.firestore.Timestamp.now()});
      audit(tx, a, "fijarPin", {});
    });
    if (rechazo) fail(rechazo, "permission-denied");
    return {ok: true};
  }
  if (b.accion === "buscarPersona") {
    const search = texto(b.busqueda, 160);
    const found = await db().collection("TBL_USUARIOS").where("cedula", "==", search).limit(20).get();
    const direct = await db().doc(`TBL_USUARIOS/${id(search)}`).get();
    const docs = new Map([...found.docs, ...(direct.exists ? [direct] : [])].map((d) => [d.id, d]));
    return {personas: [...docs.values()].filter((d) => empresasSeleccionables(d.data()!).includes(a.empresaId)).map((d) => ({id: d.id,
      nombre: d.data()!.nombreCompleto || d.data()!.nombre || `${d.data()!.nombres || ""} ${d.data()!.apellidos || ""}`,
      cedula: d.data()!.cedula || d.id}))};
  }
  if (b.accion === "crearDispositivo" || b.accion === "rotarToken" || b.accion === "revocarDispositivo") {
    const nuevo = b.accion === "crearDispositivo";
    const ref = nuevo ? db().collection(BIO.devices).doc() : db().doc(`${BIO.devices}/${id(b.deviceId)}`);
    const token = `tdb_${randomBytes(32).toString("hex")}`; const tokenHash = sha(token);
    await db().runTransaction(async (tx) => {
      const prev = (await tx.get(ref)).data();
      if (!nuevo) pertenece(prev, a.empresaId);
      if (prev?.tokenHash) tx.delete(db().doc(`${BIO.credentials}/${prev.tokenHash}`));
      const activo = b.accion !== "revocarDispositivo";
      tx.set(ref, {empresaId: a.empresaId, ...(nuevo ? {nombre: texto(b.nombre, 80), sede: texto(b.sede, 120), ...(typeof b.centroCostoId === "string" && b.centroCostoId ? {centroCostoId: id(b.centroCostoId)} : {}), creadoAt: admin.firestore.Timestamp.now()} : {}),
        activo, tokenHash: activo ? tokenHash : "", actualizadoAt: admin.firestore.Timestamp.now()}, {merge: true});
      if (activo) tx.create(db().doc(`${BIO.credentials}/${tokenHash}`), {empresaId: a.empresaId, deviceId: ref.id});
      audit(tx, a, b.accion, {deviceId: ref.id});
    });
    return {deviceId: ref.id, ...(b.accion !== "revocarDispositivo" ? {token, url: "https://us-central1-integra360-94704.cloudfunctions.net/biometricoDispositivo"} : {})};
  }
  if (b.accion === "vinculos") {
    const ref = db().doc(`${BIO.devices}/${id(b.deviceId)}`); pertenece((await ref.get()).data(), a.empresaId);
    return {vinculos: (await ref.collection("vinculos").get()).docs.map((d) => plain({...d.data(), slot: Number(d.id)}))};
  }
  if (b.accion === "vincular") {
    if (!Number.isInteger(b.slot) || b.slot < 1 || b.slot > 65535) fail("Número de huella inválido.");
    const ref = db().doc(`${BIO.devices}/${id(b.deviceId)}`); const userId = id(b.userId);
    // La autorización firmada se conserva físicamente en la contratación; la referencia es opcional.
    const consentimiento = typeof b.consentimiento === "string" && b.consentimiento.trim() ?
      texto(b.consentimiento, 300) : "Autorización de datos biométricos firmada en la contratación (respaldo físico en TH).";
    await db().runTransaction(async (tx) => {
      const device = (await tx.get(ref)).data(); pertenece(device, a.empresaId);
      const previous = (await tx.get(ref.collection("vinculos").doc(String(b.slot)))).data();
      const p = await persona(userId, a.empresaId, tx);
      if (!device.activo) fail("Activa el dispositivo renovando su token.", "failed-precondition");
      if (previous?.activo || previous?.borradoId) fail("Elimina primero esta huella y espera la confirmación del lector.", "failed-precondition");
      if (device.capacidad && b.slot > device.capacidad) fail("La huella supera la capacidad reportada por el sensor.");
      tx.set(ref.collection("vinculos").doc(String(b.slot)), {empresaId: a.empresaId, userId,
        nombre: p.nombreCompleto || p.nombre || `${p.nombres || ""} ${p.apellidos || ""}`, consentimiento,
        activo: true, desdeMs: Date.now(), porId: a.userId});
      audit(tx, a, "vincular", {deviceId: ref.id, slot: b.slot, userId, consentimiento});
    });
    return {ok: true};
  }
  // También los clientes anteriores solicitan borrado real; no dejan perfiles inactivos.
  if (b.accion === "eliminarHuella" || b.accion === "desvincular") {
    if (!Number.isInteger(b.slot) || b.slot < 1 || b.slot > 65535) fail("Número de huella inválido.");
    const deviceRef = db().doc(`${BIO.devices}/${id(b.deviceId)}`);
    const ref = deviceRef.collection("vinculos").doc(String(b.slot));
    const command = deviceRef.collection("comandos").doc();
    await db().runTransaction(async (tx) => {
      const device = (await tx.get(deviceRef)).data(); pertenece(device, a.empresaId);
      const binding = (await tx.get(ref)).data(); pertenece(binding, a.empresaId);
      if (binding.borradoId) return;
      if (!device.activo) fail("Renueva la conexión del equipo antes de solicitar el borrado.", "failed-precondition");
      tx.create(command, {empresaId: a.empresaId, tipo: "eliminarHuella", slot: b.slot, estado: "pendiente", creadoMs: Date.now(), porId: a.userId});
      tx.update(ref, {activo: false, borradoId: command.id});
      audit(tx, a, "solicitarBorradoHuella", {deviceId: deviceRef.id, slot: b.slot, comandoId: command.id, motivo: texto(b.motivo)});
    }); return {ok: true, estado: "pendiente"};
  }
  if (b.accion === "guardarHorario") {
    const horario = validarHorario(b);
    const ref = b.id ? db().doc(`${BIO.schedules}/${id(b.id)}`) : db().collection(BIO.schedules).doc();
    await db().runTransaction(async (tx) => {
      if (b.id) pertenece((await tx.get(ref)).data(), a.empresaId);
      tx.set(ref, {...horario, empresaId: a.empresaId}); audit(tx, a, "guardarHorario", {id: ref.id, ...horario});
    }); return {ok: true};
  }
  if (b.accion === "asignarHorario") {
    const {a: from, z: to} = rango(b); const userId = id(b.userId);
    if (!Array.isArray(b.diasSemana) || !b.diasSemana.length || !b.diasSemana.every((v: any) => Number.isInteger(v) && v >= 0 && v <= 6)) fail("Selecciona días de la semana.");
    await db().runTransaction(async (tx) => {
      await persona(userId, a.empresaId, tx);
      const h = (await tx.get(db().doc(`${BIO.schedules}/${id(b.horarioId)}`))).data(); pertenece(h, a.empresaId);
      const schedule = validarHorario(h);
      for (let d = from; d <= to; d += 86400000) {
        if (!b.diasSemana.includes(new Date(d - 5 * 3600000).getUTCDay())) continue;
        const dia = diaBio(d); const key = sha(`${a.empresaId}|${userId}|${dia}`);
        tx.set(db().doc(`${BIO.plans}/${key}`), {...schedule, empresaId: a.empresaId, userId, dia, horarioId: b.horarioId});
      }
      audit(tx, a, "asignarHorario", {userId, desde: b.desde, hasta: b.hasta, horarioId: b.horarioId, diasSemana: b.diasSemana});
    }); return {ok: true};
  }
  if (b.accion === "informe") return {filas: plain(await informe(a.empresaId, b))};
  if (b.accion === "decidirExtras") {
    const userId = id(b.userId); const dia = texto(b.dia, 10); fechaBio(dia);
    if (!["aprobado", "rechazado"].includes(b.estado)) fail("Decisión inválida.");
    await db().runTransaction(async (tx) => {
      const r = (await informe(a.empresaId, {desde: dia, hasta: dia, userId}, tx)).find((x) => x.userId === userId);
      if (!r || r.revision !== b.revision || r.incidencias.length || r.extra <= 0) return fail("Actualiza el informe y resuelve las incidencias antes de decidir.", "failed-precondition");
      const decision = {empresaId: a.empresaId, userId, dia, revision: r.revision, estado: b.estado,
        minutos: r.extra, motivo: texto(b.motivo, 500), porId: a.userId, fecha: admin.firestore.Timestamp.now()};
      tx.set(db().doc(`${BIO.approvals}/${sha(`${a.empresaId}|${userId}|${dia}`)}`), decision);
      audit(tx, a, "decidirExtras", decision);
    }); return {ok: true};
  }
  if (b.accion === "marcacionManual") {
    const userId = id(b.userId); const capturadoMs = Number(b.capturadoMs);
    if (!["ENTRADA", "SALIDA"].includes(b.tipo) || !Number.isInteger(capturadoMs) || capturadoMs < Date.now() - 366 * 86400000 || capturadoMs > Date.now()) fail("Tipo o fecha inválida (máximo un año atrás).");
    // Idempotencia también para una corrección si el cliente reintenta.
    const ref = db().doc(`${BIO.events}/${sha(`${a.empresaId}|manual|${id(b.eventoId)}`)}`);
    await db().runTransaction(async (tx) => {
      const previous = (await tx.get(ref)).data();
      await persona(userId, a.empresaId, tx);
      if (previous) {
        if (previous.userId !== userId || previous.tipo !== b.tipo || previous.capturadoMs !== capturadoMs) fail("Id de evento ya utilizado."); return;
      }
      tx.create(ref, {empresaId: a.empresaId, userId, tipo: b.tipo, capturadoMs, origen: "manual", motivo: texto(b.motivo, 500),
        porId: a.userId, recibidoAt: admin.firestore.Timestamp.now()});
      audit(tx, a, "marcacionManual", {eventoId: ref.id, userId, motivo: b.motivo});
    }); return {ok: true};
  }
  if (b.accion === "anularMarcacion") {
    const ref = db().doc(`${BIO.events}/${id(b.eventoId)}`);
    await db().runTransaction(async (tx) => {
      pertenece((await tx.get(ref)).data(), a.empresaId);
      tx.update(ref, {anulado: true, anuladoPor: a.userId, motivoAnulacion: texto(b.motivo, 500)});
      audit(tx, a, "anularMarcacion", {eventoId: ref.id, motivo: b.motivo});
    }); return {ok: true};
  }
  return fail("Acción desconocida.");
}

class BioHttpError extends Error {
  constructor(readonly status: number, message: string) {
    super(message);
  }
}
const ACCIONES_REGISTRO = ["autenticarAdmin", "buscarPersona", "registrarHuella"];
const MENSAJE_ADMIN = "Cédula o PIN incorrectos.";

// Registro de huellas desde el equipo: un administrador de Biométrico se identifica con su
// cédula y PIN, abre una sesión corta y solo entonces puede buscar personas y vincular
// posiciones. Los errores dentro de la transacción se devuelven (no se lanzan) para que
// los contadores de intentos fallidos se guarden.
async function registroEquipo(tx: FirebaseFirestore.Transaction, b: BioData, device: BioData,
  ref: FirebaseFirestore.DocumentReference, now: number, minuto: number, cantidad: number): Promise<BioData> {
  const empresaId = String(device.empresaId);
  const contar = () => tx.update(ref, {minuto, cantidad: cantidad + 1});
  const buscar = async (cedula: string) => {
    const snap = await tx.get(db().collection("TBL_USUARIOS").where("cedula", "==", cedula).limit(5));
    const directo = await tx.get(db().doc(`TBL_USUARIOS/${cedula}`));
    const docs = new Map([...snap.docs, ...(directo.exists ? [directo] : [])].map((d) => [d.id, d]));
    const validos = [...docs.values()].filter((d) => empresasSeleccionables(d.data()!).includes(empresaId));
    return validos.length === 1 ? validos[0] : null;
  };
  const nombreDe = (p: BioData) => String(p.nombreCompleto || p.nombre || `${p.nombres || ""} ${p.apellidos || ""}`).trim();

  if (b.accion === "autenticarAdmin") {
    const u = await buscar(b.cedula);
    const pinRef = u ? db().doc(`${BIO.pins}/${empresaId}_${u.id}`) : null;
    const [rol, pin] = u ? await Promise.all([tx.get(db().doc(`TBL_BIOMETRICO_ROLES/${empresaId}_${u.id}`)), tx.get(pinRef!)]) : [null, null];
    const p = pin?.data();
    if (p?.bloqueadoHastaMs > now) throw new BioHttpError(429, "Acceso bloqueado temporalmente por intentos fallidos.");
    const esAdmin = !!u && nivelBio(u.data()!, empresaId, u.id, rol!.data()) === "administrador";
    if (!esAdmin || !p?.pinHash || !pinCoincide(b.pin, p.salt, p.pinHash)) {
      if (p?.pinHash) {
        const fallos = Number(p.fallos || 0) + 1;
        tx.update(pinRef!, {fallos: fallos >= PIN_INTENTOS ? 0 : fallos, bloqueadoHastaMs: fallos >= PIN_INTENTOS ? now + PIN_BLOQUEO_MS : 0});
      }
      contar();
      return {rechazo: {status: 422, mensaje: MENSAJE_ADMIN}};
    }
    const sesion = `tds_${randomBytes(24).toString("hex")}`;
    tx.update(pinRef!, {fallos: 0, bloqueadoHastaMs: 0});
    tx.update(ref, {sesionRegistro: {hash: sha(sesion), userId: u!.id, nombre: nombreDe(u!.data()!), expMs: now + SESION_REGISTRO_MS},
      minuto, cantidad: cantidad + 1});
    audit(tx, {userId: u!.id, empresaId}, "sesionRegistroEquipo", {deviceId: ref.id});
    return {sesion, administrador: nombreDe(u!.data()!), expiraEnS: SESION_REGISTRO_MS / 1000};
  }

  const s = device.sesionRegistro;
  if (!s || s.hash !== sha(b.sesion) || s.expMs < now) return {rechazo: {status: 422, mensaje: "Sesión de registro vencida. Identifícate de nuevo."}};
  const persona = await buscar(b.cedula);
  if (!persona) return {rechazo: {status: 422, mensaje: "No se encontró la persona en esta empresa."}};
  const nombre = nombreDe(persona.data()!);
  if (b.accion === "buscarPersona") {
    contar();
    return {nombre};
  }
  if (device.capacidad && b.slot > device.capacidad) return {rechazo: {status: 422, mensaje: "La posición supera la capacidad del sensor."}};
  const vRef = ref.collection("vinculos").doc(String(b.slot));
  const previo = (await tx.get(vRef)).data();
  if (previo?.activo || previo?.borradoId) return {rechazo: {status: 409, mensaje: "Esa posición está vinculada o pendiente de borrado. Espera la confirmación en la app."}};
  const fecha = new Date(now - 5 * 3600000).toISOString().slice(0, 16).replace("T", " ");
  tx.set(vRef, {empresaId, userId: persona.id, nombre, activo: true, desdeMs: now, porId: s.userId,
    consentimiento: `Aceptado en pantalla del equipo ${device.nombre || ref.id} el ${fecha} (Colombia), registro a cargo de ${s.nombre}. Aviso ${b.aviso}. Respaldo físico firmado en la contratación.`,
    autorizacion: {origen: "equipo", deviceId: ref.id, aviso: b.aviso, fechaMs: now}});
  tx.update(ref, {minuto, cantidad: cantidad + 1});
  audit(tx, {userId: s.userId, empresaId}, "vincularDesdeEquipo", {deviceId: ref.id, slot: b.slot, userId: persona.id, aviso: b.aviso});
  return {ok: true, nombre, slot: b.slot};
}

export async function recibirBiometrico(req: functions.https.Request, res: any): Promise<void> {
  res.set("Cache-Control", "no-store");
  try {
    if (req.method !== "POST") throw new BioHttpError(405, "Usa POST.");
    if (!req.is("application/json")) throw new BioHttpError(415, "Usa JSON.");
    if ((req.rawBody?.length || 0) > 2048) throw new BioHttpError(413, "Máximo 2048 bytes.");
    const bearer = /^Bearer (tdb_[a-f0-9]{64})$/.exec(req.get("Authorization") || "");
    if (!bearer) throw new BioHttpError(401, "Token inválido o revocado.");
    const b = req.body;
    const fields = ["deviceId", "eventoId", "tipo", "slot", "capturadoMs", "accion", "capacidad", "usadas", "firmware",
      "cedula", "pin", "sesion", "autorizo", "aviso", "comandoId"];
    if (!b || Array.isArray(b) || typeof b !== "object" || Object.keys(b).some((k) => !fields.includes(k)) ||
        typeof b.deviceId !== "string" || !/^[a-zA-Z0-9_-]{1,160}$/.test(b.deviceId) ||
        !["marcacion", "heartbeat", "confirmarBorrado", ...ACCIONES_REGISTRO].includes(b.accion)) throw new BioHttpError(400, "Formato inválido.");
    if (b.accion === "confirmarBorrado" && (typeof b.comandoId !== "string" || !/^[a-zA-Z0-9_-]{1,160}$/.test(b.comandoId))) throw new BioHttpError(400, "Confirmación inválida.");
    if (ACCIONES_REGISTRO.includes(b.accion)) {
      const cedulaOk = typeof b.cedula === "string" && /^\d{3,15}$/.test(b.cedula);
      const sesionOk = typeof b.sesion === "string" && /^tds_[a-f0-9]{48}$/.test(b.sesion);
      const valido = b.accion === "autenticarAdmin" ? cedulaOk && typeof b.pin === "string" && /^\d{6}$/.test(b.pin) :
        b.accion === "buscarPersona" ? cedulaOk && sesionOk :
          cedulaOk && sesionOk && Number.isInteger(b.slot) && b.slot >= 1 && b.slot <= 65535 && b.autorizo === true &&
          typeof b.aviso === "string" && /^[a-zA-Z0-9._-]{1,20}$/.test(b.aviso);
      if (!valido) throw new BioHttpError(400, "Solicitud de registro inválida.");
    }
    if (b.accion === "marcacion" && (typeof b.eventoId !== "string" || !/^[a-zA-Z0-9_-]{1,100}$/.test(b.eventoId) ||
        !["ENTRADA", "SALIDA"].includes(b.tipo) || !Number.isInteger(b.slot) || b.slot < 1 || b.slot > 65535 ||
        !Number.isSafeInteger(b.capturadoMs))) throw new BioHttpError(400, "Marcación inválida.");
    if (b.accion === "heartbeat" && (![b.capacidad, b.usadas].every((n) => n === null || (Number.isInteger(n) && n >= 0 && n <= 65535)) ||
        typeof b.firmware !== "string" || b.firmware.length > 40)) throw new BioHttpError(400, "Telemetría inválida.");
    const tokenHash = sha(bearer[1]); const ref = db().doc(`${BIO.devices}/${b.deviceId}`);
    const result = await db().runTransaction(async (tx) => {
      const credential = (await tx.get(db().doc(`${BIO.credentials}/${tokenHash}`))).data();
      const device = (await tx.get(ref)).data();
      if (!credential || !device?.activo || device.tokenHash !== tokenHash || credential.deviceId !== b.deviceId || device.empresaId !== credential.empresaId) throw new BioHttpError(401, "Token inválido o revocado.");
      const module = (await tx.get(db().doc(`TBL_APPS/${device.empresaId}_biometricodashboard`))).data();
      if (module?.enabled === false) throw new BioHttpError(403, "Biométrico deshabilitado en la empresa.");
      const now = Date.now(); const minuto = Math.floor(now / 60000);
      const cantidad = device.minuto === minuto ? Number(device.cantidad || 0) : 0;
      const eRef = db().doc(`${BIO.events}/${sha(`${b.deviceId}|${b.eventoId || "heartbeat"}`)}`);
      if (b.accion === "marcacion") {
        const previous = (await tx.get(eRef)).data();
        if (previous) {
          if (previous.tipo !== b.tipo || previous.slot !== b.slot || previous.capturadoMs !== b.capturadoMs) throw new BioHttpError(409, "Id de evento reutilizado con otros datos.");
          return {duplicada: true, id: eRef.id, nombre: String(previous.nombre || "")};
        }
      }
      if (cantidad >= 60) throw new BioHttpError(429, "Máximo 60 solicitudes nuevas por minuto.");
      if (ACCIONES_REGISTRO.includes(b.accion)) return registroEquipo(tx, b, device, ref, now, minuto, cantidad);
      if (b.accion === "confirmarBorrado") {
        const commandRef = ref.collection("comandos").doc(b.comandoId);
        const command = (await tx.get(commandRef)).data();
        if (!command || command.empresaId !== device.empresaId || command.tipo !== "eliminarHuella") throw new BioHttpError(404, "Orden no encontrada para este equipo.");
        if (command.estado === "completado") return {confirmado: true};
        const bindingRef = ref.collection("vinculos").doc(String(command.slot));
        const binding = (await tx.get(bindingRef)).data();
        if (!binding || binding.borradoId !== b.comandoId) throw new BioHttpError(409, "El vínculo cambió. Revisa el equipo.");
        tx.delete(bindingRef);
        tx.update(commandRef, {estado: "completado", confirmadoMs: now});
        tx.update(ref, {ultimoContactoMs: now, minuto, cantidad: cantidad + 1});
        audit(tx, {empresaId: device.empresaId, userId: command.porId}, "huellaEliminada", {deviceId: ref.id, slot: command.slot, comandoId: commandRef.id});
        return {confirmado: true};
      }
      if (b.accion === "heartbeat") {
        const pending = await tx.get(ref.collection("comandos").where("estado", "==", "pendiente").limit(1));
        const command = pending.docs[0];
        tx.update(ref, {capacidad: b.capacidad, usadas: b.usadas, firmware: b.firmware, ultimoContactoMs: now, minuto, cantidad: cantidad + 1});
        return {heartbeat: true, ...(command ? {comando: {id: command.id, tipo: "eliminarHuella", slot: command.data().slot}} : {})};
      }
      if (b.capturadoMs > now + 60000 || b.capturadoMs < now - 31 * 86400000) throw new BioHttpError(422, "Hora inválida o evento de más de 31 días.");
      const binding = (await tx.get(ref.collection("vinculos").doc(String(b.slot)))).data();
      if (!binding?.activo || binding.empresaId !== device.empresaId || b.capturadoMs < binding.desdeMs) throw new BioHttpError(422, "Huella sin vínculo vigente a la hora del evento.");
      const user = (await tx.get(db().doc(`TBL_USUARIOS/${binding.userId}`))).data();
      if (!user || !empresasSeleccionables(user).includes(device.empresaId)) throw new BioHttpError(422, "Colaborador inactivo en la empresa.");
      tx.create(eRef, {empresaId: device.empresaId, deviceId: b.deviceId, sede: device.sede, userId: binding.userId,
        nombre: binding.nombre || "", slot: b.slot, tipo: b.tipo, capturadoMs: b.capturadoMs,
        recibidoAt: admin.firestore.Timestamp.fromMillis(now), origen: "huella", diferido: now - b.capturadoMs > 120000});
      tx.update(ref, {ultimoContactoMs: now, minuto, cantidad: cantidad + 1});
      return {duplicada: false, id: eRef.id, nombre: String(binding.nombre || "")};
    });
    if (result.rechazo) throw new BioHttpError(result.rechazo.status, result.rechazo.mensaje);
    res.status(result.duplicada || result.heartbeat || result.confirmado || ACCIONES_REGISTRO.includes(b.accion) ? 200 : 201).json({ok: true, ...result});
  } catch (e) {
    const status = e instanceof BioHttpError ? e.status : 503;
    if (status === 429) res.set("Retry-After", "60");
    res.status(status).json({ok: false, error: e instanceof BioHttpError ? e.message : "No se guardó. Reintenta con el mismo eventoId."});
  }
}
export const biometricoGestion = functions.region("us-central1").runWith({timeoutSeconds: 120, memory: "512MB"}).https.onCall(async (b, c) => {
  try {
    return await gestionarBiometrico(b, c);
  } catch (e) {
    if (e instanceof functions.https.HttpsError) throw e;
    if (e instanceof Error && /Fecha inválida|Revisa horas|Escribe un nombre/.test(e.message)) fail(e.message);
    functions.logger.error("Error en gestión de biométrico", e);
    throw new functions.https.HttpsError("internal", "No se completó la operación. Actualiza y vuelve a intentar.");
  }
});
export const biometricoDispositivo = functions.region("us-central1").runWith({timeoutSeconds: 30, memory: "256MB", maxInstances: 4}).https.onRequest(recibirBiometrico);
