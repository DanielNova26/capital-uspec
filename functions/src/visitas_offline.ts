import * as admin from "firebase-admin";
import * as functions from "firebase-functions/v1";
import {createHash, randomUUID} from "crypto";
import {appsDeEmpresa, raizEsDeEmpresa} from "./apps_por_empresa";
import {empresasSeleccionables} from "./acceso";

type D = Record<string, any>;
const RESERVAS = "TBL_VISITAS_OFFLINE";
const DAY = 86400000;
const fail = (message: string): never => {
  throw new functions.https.HttpsError("failed-precondition", message);
};
const text = (x: unknown): string => typeof x === "string" ? x.trim() : "";
const tipoItem = (raw: string): string =>
  ["calificacion", "si_no", "elemento", "texto", "parrafo", "numero", "fecha", "opcion", "seleccion_multiple"].includes(raw) ? raw : "calificacion";
function seleccionMultipleValida(valor: string, opciones: unknown): boolean {
  try {
    const seleccion = JSON.parse(valor);
    return Array.isArray(opciones) && Array.isArray(seleccion) && seleccion.length > 0 &&
      new Set(seleccion).size === seleccion.length &&
      seleccion.every((o: unknown) => typeof o === "string" && opciones.includes(o));
  } catch {
    return false;
  }
}
const id = (x: unknown): string => {
  const s = text(x);
  if (!s || s.length > 160 || s.includes("/")) {
    throw new functions.https.HttpsError("invalid-argument", "Identificador inválido.");
  }
  return s;
};

// Wire format shared with visitas_local_store.dart. No implicit date parsing.
export function offlineWire(value: any): any {
  if (value instanceof admin.firestore.Timestamp) return {$ts: value.toMillis()};
  if (Buffer.isBuffer(value)) return {$bytes: value.toString("base64")};
  if (Array.isArray(value)) return value.map(offlineWire);
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.keys(value).sort().map((k) => [k, offlineWire(value[k])]));
  }
  return value;
}
export function offlineDecode(value: any): any {
  if (Array.isArray(value)) return value.map(offlineDecode);
  if (value && typeof value === "object") {
    if (Object.keys(value).length === 1 && Number.isFinite(value.$ts)) {
      return admin.firestore.Timestamp.fromMillis(value.$ts);
    }
    if (Object.keys(value).length === 1 && typeof value.$bytes === "string") {
      return Buffer.from(value.$bytes, "base64");
    }
    return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, offlineDecode(v)]));
  }
  return value;
}
export const offlineHash = (v: any): string =>
  createHash("sha256").update(JSON.stringify(offlineWire(v))).digest("hex");

export function accesoOffline(user: D, role: D, empresaId: string): boolean {
  return empresasSeleccionables(user).includes(empresaId) &&
    !user.needsPasswordChange &&
    appsDeEmpresa(user, empresaId).some((a) => ["visitasdashboard", "visitas"].includes(a)) &&
    ["profesional", "coordinador"].includes(role.rol);
}
function caller(context: functions.https.CallableContext): string {
  const userId = id(context.auth?.token.userDocId);
  if (context.auth?.token.authVersion !== 2 ||
      context.auth.uid !== `todo_${createHash("sha256").update(userId).digest("hex")}`) {
    throw new functions.https.HttpsError("unauthenticated", "Inicia sesión de nuevo.");
  }
  return userId;
}
async function acceso(tx: FirebaseFirestore.Transaction, userId: string, empresaId: string) {
  const db = admin.firestore();
  const u = await tx.get(db.collection("TBL_USUARIOS").doc(userId));
  const r = await tx.get(db.collection("TBL_VISITAS_ROLES").doc(`${empresaId}_${userId}`));
  if (!u.exists || !accesoOffline(u.data()!, r.data() || {}, empresaId)) {
    throw new functions.https.HttpsError("permission-denied",
      "Ya no tienes permiso para ejecutar visitas en esta empresa. El trabajo local se conserva.");
  }
  return u.data()!;
}
function ms(t: any): number {
  return t instanceof admin.firestore.Timestamp ? t.toMillis() : NaN;
}
function distancia(a: D, b: D): number {
  const rad = Math.PI / 180;
  const dlat = (a.lat - b.lat) * rad;
  const dlng = (a.lng - b.lng) * rad;
  const h = Math.sin(dlat / 2) ** 2 +
    Math.cos(a.lat * rad) * Math.cos(b.lat * rad) * Math.sin(dlng / 2) ** 2;
  return 6371000 * 2 * Math.asin(Math.sqrt(Math.min(1, h)));
}
function marca(m: D, p: D, now: number): D {
  const at = ms(m?.at);
  const dia = ms(p.base.fechaProgramada);
  if (!Number.isFinite(at) || at < p.preparadaMs - 60000 || at > now + 60000 ||
      at >= p.venceMs || at < dia || at >= dia + DAY) {
    fail("La hora capturada no corresponde al día autorizado de la visita.");
  }
  if (!p.base.esPrueba) {
    if (!p.ubicacion || !Number.isFinite(m.lat) || !Number.isFinite(m.lng) ||
        Math.abs(m.lat) > 90 || Math.abs(m.lng) > 180 ||
        !Number.isFinite(m.precisionMetros) || m.precisionMetros < 0) {
      fail("Falta una ubicación válida capturada en el establecimiento.");
    }
    const d = distancia(m, p.ubicacion);
    if (d - Math.min(100, m.precisionMetros) > (p.ubicacion.radioMetros ?? 150)) {
      fail("La ubicación capturada está fuera del establecimiento.");
    }
    return {...m, distanciaMetros: d, dentroDelRadio: true};
  }
  return m;
}

// Validates final field report; assignment and template always come from server receipt.
export function validarEntregaOffline(p: D, input: D, now: number): D {
  if (!input || input.estado !== "terminada") fail("Finaliza la visita en el equipo antes de enviarla.");
  const inicio = marca(input.inicio, p, now);
  const fin = marca(input.fin, p, now);
  if (ms(fin.at) < ms(inicio.at)) fail("El cierre es anterior al inicio.");
  if (!text(input.responsableEstablecimiento?.nombre)) fail("Falta el responsable del establecimiento.");
  for (const key of ["firmaProfesional", "firmaEstablecimiento"]) {
    const f = input[key];
    if (!f || !Buffer.isBuffer(f.blob) || f.blob.length < 8 || f.blob.length > 150000 ||
        f.blob.subarray(0, 8).toString("hex") !== "89504e470d0a1a0a" ||
        !text(f.nombre) || f.firmadoPorId !== p.userId ||
        ms(f.at) < ms(inicio.at) || ms(f.at) > ms(fin.at) || !Number.isFinite(ms(f.at))) {
      fail("Falta una firma válida capturada durante la visita.");
    }
  }
  const respuestas = input.respuestas || {};
  let cumple = 0;
  let evaluados = 0;
  for (const it of p.formato.items || []) {
    const r = respuestas[it.id] || {};
    const tipo = tipoItem(it.tipo);
    if (["calificacion", "si_no", "elemento"].includes(tipo)) {
      const permitidos = tipo === "calificacion" ? ["cumple", "no_cumple", "no_aplica"] : ["cumple", "no_cumple"];
      if (!permitidos.includes(r.resultado)) fail(`Falta responder: ${it.texto}`);
      if (r.resultado !== "no_aplica") evaluados++;
      if (r.resultado === "cumple") cumple++;
      if (r.resultado === "no_cumple" && (!text(r.observacion) ||
          (it.requiereEvidencia && !(r.evidencias?.length > 0) && !text(r.sinFotoMotivo)))) {
        fail(`Falta justificar o aportar evidencia: ${it.texto}`);
      }
    } else {
      const valor = text(r.valor);
      if ((!valor && it.obligatoria !== false) ||
          (valor && tipo === "numero" && !Number.isFinite(Number(valor.replace(",", ".")))) ||
          (valor && tipo === "opcion" && it.opciones?.length && !it.opciones.includes(valor)) ||
          (valor && tipo === "seleccion_multiple" && !seleccionMultipleValida(valor, it.opciones))) {
        fail(`Revisa la respuesta: ${it.texto}`);
      }
    }
  }
  const tablas = input.tablas || {};
  for (const t of p.formato.tablas || []) {
    const filas = tablas[t.id] || [];
    if (!Array.isArray(filas) || !filas.length) fail(`Faltan filas: ${t.nombre}`);
    const fijas = t.filasFijas || [];
    const usadas = fijas.length ? fijas.map((_: any, i: number) =>
      filas.find((f: D) => f.id === `fija_${i + 1}`) || {}) : filas;
    if (new Set(filas.map((f: D) => f.id)).size !== filas.length ||
        filas.some((f: D) => !text(f.id)) || (fijas.length && filas.length !== fijas.length)) {
      fail(`Revisa las filas de la tabla: ${t.nombre}`);
    }
    const allowed = t.escala === "cumple" ? ["CU", "NCU", "NA"] :
      t.escala === "si_no" ? ["SI", "NO"] : ["B", "M", "R", "NC"];
    for (const f of usadas) {
      if ((t.camposEstado || []).some((c: D) => !allowed.includes(f.estados?.[c.id])) ||
          (Object.values(f.estados || {}).some((s) => ["M", "NC", "NCU", "NO"].includes(String(s))) &&
          !text(f.observacion))) fail(`Completa la tabla: ${t.nombre}`);
    }
  }
  // Whitelist fields; never accept company, role, assignee, task IDs or template from client.
  const out: D = {estado: "terminada", inicio, fin,
    formatoId: p.formatoId, formatoNombre: p.formato.nombre, formatoAsignado: p.formato,
    cumplimiento: evaluados ? Math.round(cumple * 100 / evaluados) : null};
  for (const k of ["respuestas", "tablas", "observacionGeneral", "responsableEstablecimiento",
    "ciudad", "cargoProfesional", "firmaProfesional", "firmaEstablecimiento", "evidenciasAdicionales"]) {
    out[k] = input[k] ?? (["respuestas", "tablas"].includes(k) ? {} :
      k === "evidenciasAdicionales" ? [] : "");
  }
  return out;
}

export const visitasPrepararOffline = functions.region("us-central1").https.onCall(async (raw, context) => {
  const userId = caller(context);
  const empresaId = id(raw?.empresaId);
  const visitaId = id(raw?.visitaId);
  const formatoId = id(raw?.formatoId);
  const db = admin.firestore();
  const receipt = db.collection(RESERVAS).doc();
  const result = await db.runTransaction(async (tx) => {
    const user = await acceso(tx, userId, empresaId);
    const snap = await tx.get(db.collection("TBL_VISITAS").doc(visitaId));
    const v = snap.data() || {};
    if (!snap.exists || v.empresaId !== empresaId || v.profesionalId !== userId ||
        v.estado !== "programada" || v.firmaProfesional || v.firmaEstablecimiento) {
      fail("Solo puedes descargar tus visitas programadas, todavía sin iniciar.");
    }
    const now = Date.now();
    const fs = await tx.get(db.collection("TBL_VISITAS_FORMATOS").doc(formatoId));
    const formato = fs.data() || {};
    if (!fs.exists || formato.empresaId !== empresaId || formato.areaId !== v.areaId ||
        !(formato.estado === "vigente" || (v.esPrueba && formato.estado === "borrador")) ||
        (v.formatoId && v.formatoId !== formatoId)) fail("El formato no corresponde a esta visita.");
    const scoped = user.empresasDetalle?.[empresaId] || {};
    const raiz = raizEsDeEmpresa(user, empresaId) ? user : {};
    const cargo = [scoped.cargoNombre, scoped.cargo, raiz.cargoNombre, raiz.cargo].map(text).find(Boolean) || "";
    const clave = (s: string) => s.normalize("NFD").replace(/[\u0300-\u036f]/g, "")
      .toLowerCase().replace(/[^a-z0-9]/g, "");
    if (formato.cargos?.length && !formato.cargos.some((c: string) => clave(c) === clave(cargo))) {
      fail("El formato no está habilitado para tu cargo.");
    }
    const root = `${empresaId}_${v.centroId}`;
    let loc = v.subcentroId ?
      await tx.get(db.collection("TBL_VISITAS_UBICACIONES").doc(`${root}__${v.subcentroId}`)) : null;
    if (!loc?.exists) loc = await tx.get(db.collection("TBL_VISITAS_UBICACIONES").doc(root));
    if (!v.esPrueba && !loc.exists) fail("El establecimiento no tiene ubicación configurada.");
    const empresa = (await tx.get(db.collection("TBL_EMPRESAS").doc(empresaId))).data() || {};
    const p = {userId, uid: context.auth!.uid, empresaId, visitaId, formatoId, formato,
      empresaNombre: text(empresa.nombre) || text(empresa.razonSocial) || empresaId,
      base: v, baseHash: offlineHash(v), ubicacion: loc.data() || null,
      preparadaMs: now, venceMs: now + 7 * DAY, cargo};
    tx.create(receipt, p);
    return p;
  });
  return offlineWire({...result, reservaId: receipt.id});
});

/** Restores local unlocking after an explicit logout/login without replacing drafts. */
export const visitasRevalidarOffline = functions.region("us-central1").https.onCall(async (raw, context) => {
  const userId = caller(context);
  const db = admin.firestore();
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(db.collection(RESERVAS).doc(id(raw?.reservaId)));
    const p = snap.data() || {};
    if (p.userId !== userId || p.uid !== context.auth!.uid) fail("Descarga no autorizada.");
    await acceso(tx, userId, p.empresaId);
    const now = Date.now();
    return {userId, uid: p.uid, empresaId: p.empresaId,
      preparadaMs: now, venceMs: now + 7 * DAY};
  });
});

/** Photo upload is authenticated by the same receipt; hash-addressed files make retries idempotent. */
export const visitasSubirFotoOffline = functions.region("us-central1")
  .runWith({memory: "512MB", timeoutSeconds: 120}).https.onCall(async (raw, context) => {
    const userId = caller(context);
    const ref = admin.firestore().collection(RESERVAS).doc(id(raw?.reservaId));
    const p = await admin.firestore().runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const data = snap.data() || {};
      if (data.userId !== userId || data.uid !== context.auth!.uid) fail("Descarga no autorizada.");
      await acceso(tx, userId, data.empresaId);
      return data;
    });
    if (typeof raw?.bytes !== "string" || raw.bytes.length > 8 * 1024 * 1024) fail("La foto supera 6 MB.");
    const bytes = Buffer.from(raw.bytes, "base64");
    if (!bytes.length) fail("La foto está vacía.");
    const hash = createHash("sha256").update(bytes).digest("hex");
    const asset = ref.collection("fotos").doc(hash);
    const prior = await asset.get();
    if (prior.exists) return prior.data();
    const path = `visitas/${p.empresaId}/${p.visitaId}/offline/${ref.id}/${hash}.jpg`;
    const file = admin.storage().bucket().file(path);
    const token = randomUUID();
    try {
      await file.save(bytes, {resumable: false, contentType: "image/jpeg",
        preconditionOpts: {ifGenerationMatch: 0},
        metadata: {metadata: {firebaseStorageDownloadTokens: token}}});
    } catch (e: any) {
      if (e.code !== 412) throw e;
    }
    const [metadata] = await file.getMetadata();
    const storedToken = metadata.metadata?.firebaseStorageDownloadTokens;
    if (!storedToken) fail("No se pudo confirmar la foto en el servidor.");
    const result = {hash, path, url: `https://firebasestorage.googleapis.com/v0/b/${file.bucket.name}/o/${encodeURIComponent(path)}?alt=media&token=${storedToken}`};
    await asset.set(result);
    return result;
  });

export const visitasSincronizarOffline = functions.region("us-central1")
  .runWith({memory: "512MB", timeoutSeconds: 120}).https.onCall(async (raw, context) => {
    const userId = caller(context);
    const db = admin.firestore();
    const ref = db.collection(RESERVAS).doc(id(raw?.reservaId));
    const input = offlineDecode(raw?.visita);
    if (Buffer.byteLength(JSON.stringify(raw?.visita || {})) > 800000) fail("El acta supera el tamaño permitido.");
    return db.runTransaction(async (tx) => {
      const rs = await tx.get(ref);
      const p = rs.data() || {};
      if (p.userId !== userId || p.uid !== context.auth!.uid) fail("Descarga no autorizada.");
      await acceso(tx, userId, p.empresaId);
      const submissionHash = offlineHash(input);
      if (p.sincronizada) {
        if (p.entregaHash !== submissionHash) fail("Esta descarga ya se sincronizó con otro contenido.");
        return {ok: true, tareas: p.tareas || []};
      }
      const visitaRef = db.collection("TBL_VISITAS").doc(p.visitaId);
      const current = await tx.get(visitaRef);
      if (!current.exists || offlineHash(current.data()) !== p.baseHash) {
        fail("La visita cambió en el servidor. Se conserva tu copia; coordina la revisión antes de enviarla.");
      }
      const out = validarEntregaOffline(p, input, Date.now());
      const assets = await tx.get(ref.collection("fotos"));
      const byHash = new Map(assets.docs.map((s) => [s.id, s.data()]));
      const resolve = (e: D): D => {
        const hash = text(e.path).replace(/^local:/, "");
        const a = byHash.get(hash);
        if (!a || e.path !== `local:${hash}`) fail("Hay fotos pendientes de cargar.");
        return {...e, path: a!.path, url: a!.url};
      };
      for (const r of Object.values(out.respuestas) as D[]) r.evidencias = (r.evidencias || []).map(resolve);
      for (const filas of Object.values(out.tablas) as D[][]) {
        for (const f of filas) f.evidencias = (f.evidencias || []).map(resolve);
      }
      out.evidenciasAdicionales = out.evidenciasAdicionales.map(resolve);
      const findings: D[] = [];
      for (const it of p.formato.items || []) {
        const r = out.respuestas[it.id];
        if (["calificacion", "si_no", "elemento"].includes(tipoItem(it.tipo)) &&
            r?.resultado === "no_cumple") findings.push({...r, key: it.id, title: it.texto});
      }
      for (const t of p.formato.tablas || []) {
        for (const f of out.tablas[t.id] || []) {
          if (Object.values(f.estados || {}).some((s) => ["M", "NC", "NCU", "NO"].includes(String(s)))) {
            findings.push({...f, key: `${t.id}:${f.id}`, title: t.nombre});
          }
        }
      }
      if (findings.length > 400) fail("El acta supera 400 hallazgos.");
      // Read all recipients before writes; never assign a task across companies.
      for (const h of p.base.esPrueba ? [] : findings) {
        h.destino = text(h.accionResponsableId) || p.base.asignadoPorId;
        const recipient = await tx.get(db.collection("TBL_USUARIOS").doc(id(h.destino)));
        if (!recipient.exists || !empresasSeleccionables(recipient.data()!).includes(p.empresaId)) {
          fail("Un responsable del plan de acción ya no está habilitado en esta empresa.");
        }
      }
      const tareas: string[] = [];
      const now = admin.firestore.Timestamp.now();
      for (const h of p.base.esPrueba ? [] : findings) {
        const taskId = `visita_offline_${offlineHash([p.visitaId, h.key])}`;
        tareas.push(taskId);
        tx.create(db.collection("TBL_TAREAS").doc(taskId), {
          schemaVersion: 2, titulo: `Visita ${p.base.areaNombre} · ${p.base.centroNombre}: ${h.title}`,
          descripcion: `${h.observacion || ""}\n${h.accion || ""}`, estado: "en_progreso", prioridad: "alta",
          empresaId: p.empresaId, empresas: [p.empresaId],
          centroId: String(p.base.centroId).startsWith(`${p.empresaId}_est_`) ? "global" : p.base.centroId,
          areaId: text(h.accionAreaId) || p.base.areaId, creador_id: userId,
          creador_nombre: p.base.profesionalNombre, asignado_uid: h.destino,
          asignado_nombre: h.accionResponsableNombre || p.base.asignadoPorNombre || "",
          aprobador_uid: userId, aprobador_nombre: p.base.profesionalNombre,
          jefe_uid: userId, jefe_nombre: p.base.profesionalNombre, reasignado: false,
          origen: "visita", visitaId: p.visitaId, visitaItemId: h.key,
          source: {moduleId: "visitasdashboard", type: "visita", entityId: p.visitaId},
          sourceModule: "visitasdashboard", sourceType: "visita",
          status: "en_progreso", priority: "alta", requiere_aprobacion: true,
          approverId: userId, approverName: p.base.profesionalNombre,
          evidencias: (h.evidencias || []).map((e: D) => e.url), adjuntos: [],
          fecha_creacion: now, fecha_limite: admin.firestore.Timestamp.fromMillis(ms(out.fin.at) + 5 * DAY),
          createdAt: now, updatedAt: now,
        });
      }
      tx.update(visitaRef, {...out, tareasCreadas: tareas, cerradaPor: userId,
        offlineReservaId: ref.id, sincronizadaAt: now, updatedAt: now});
      tx.update(ref, {sincronizada: true, entregaHash: submissionHash, tareas, sincronizadaAt: now});
      if (text(p.base.asignadoPorId)) {
        tx.set(db.collection("TBL_NOTIFICACIONES").doc(p.base.asignadoPorId)
          .collection("notifications").doc(`visita_offline_${p.visitaId}`), {
          title: "Visita terminada", description: `${p.base.profesionalNombre} sincronizó la visita de ${p.base.centroNombre}.`,
          type: "visita_terminada", taskId: `visita:${p.visitaId}`, empresaId: p.empresaId,
          createdAt: now, read: false, fromId: userId,
        });
      }
      return {ok: true, tareas};
    });
  });
