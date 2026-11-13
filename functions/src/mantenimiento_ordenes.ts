import * as admin from "firebase-admin";
import * as functions from "firebase-functions/v1";
import {createCipheriv, createDecipheriv, createHash, randomBytes, randomUUID} from "crypto";
import {PDFDocument} from "pdf-lib";
import {appsDeEmpresa} from "./apps_por_empresa";
import {cuentaInhabilitada, inhabilitadaEn} from "./acceso";
import {
  catalogoTareasMantenimiento, centroTareaMantenimiento,
  fechaLimiteTarea, listarTareasMantenimiento, tareaParaMantenimiento,
} from "./mantenimiento_tareas";
import {numeroDeTarea} from "./tareas_numero";

type Data = FirebaseFirestore.DocumentData;
type Tx = FirebaseFirestore.Transaction;
const appId = "mantenimientodashboard";
const ordenes = "TBL_MANTENIMIENTO_ORDENES";
const privados = "TBL_MANTENIMIENTO_ARCHIVOS";
const limiteArchivo = 5 * 1024 * 1024;
const clases = ["procesamiento", "coccion", "refrigeracion", "infraestructura", "medicion", "otros"];
const tiposArchivo = {
  diagnostico: ["image/jpeg", "image/png"],
  cotizacion: ["application/pdf", "image/jpeg", "image/png"],
  evidencia: ["image/jpeg", "image/png"],
  recibo: ["application/pdf", "image/jpeg", "image/png"],
};

function error(code: functions.https.FunctionsErrorCode, message: string): never {
  throw new functions.https.HttpsError(code, message);
}

function texto(value: unknown, max: number, label: string, required = false): string {
  const result = typeof value === "string" ? value.trim() : "";
  if (result.length > max || (required && !result)) {
    error("invalid-argument", `Revisa el campo «${label}».`);
  }
  return result;
}

function id(value: unknown, label: string, required = true): string {
  const result = texto(value, 200, label, required);
  if (result.includes("/") || result === "." || result === "..") {
    error("invalid-argument", `Identificador inválido de ${label}.`);
  }
  return result;
}

export function operaOrdenMantenimiento(
  usuario: Data | undefined, acceso: Data | undefined, app: Data | undefined,
  empresaId: string, userId: string,
): boolean {
  if (!usuario || cuentaInhabilitada(usuario) || inhabilitadaEn(usuario, empresaId)) return false;
  const detalle = usuario.empresasDetalle?.[empresaId];
  const pertenece = usuario.empresaId === empresaId || usuario.empresa === empresaId ||
    (Array.isArray(usuario.empresas) && usuario.empresas.includes(empresaId)) ||
    Object.hasOwnProperty.call(usuario.empresasDetalle ?? {}, empresaId);
  return pertenece && detalle?.activo !== false && detalle?.soloTalentoHumano !== true &&
    acceso?.empresaId === empresaId && acceso.userId === userId && acceso.operador === true &&
    app?.empresaId === empresaId && app.appId === appId && app.enabled === true &&
    appsDeEmpresa(usuario, empresaId).some((a) => a === appId || a === "mantenimiento");
}

function versionCoincide(orden: Data, input: Data): boolean {
  const actual = orden.updatedAt;
  return actual ? actual.seconds === input.segundos && actual.nanoseconds === input.nanosegundos :
    input.segundos == null && input.nanosegundos == null;
}

function subcentroDe(centro: Data, subcentroId: string): {subcentroId: string; subcentroNombre: string} {
  if (!subcentroId) return {subcentroId: "", subcentroNombre: ""};
  const elementos = Array.isArray(centro.subcentros) ? centro.subcentros : [];
  for (const item of elementos) {
    const nombre = (typeof item === "string" ? item : item?.nombre ?? "").toString().trim();
    const slug = nombre.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "")
      .replace(/[^a-z0-9]+/g, "_").replace(/^_|_$/g, "");
    if (((item?.id ?? "").toString().trim() || slug) === subcentroId && nombre && item?.enabled !== false) {
      return {subcentroId, subcentroNombre: nombre};
    }
  }
  return error("invalid-argument", "La estructura no está activa en este establecimiento.");
}

function datosTrabajo(input: Data) {
  const tipo = texto(input.tipo, 20, "tipo", true);
  const intervencion = texto(input.intervencion, 20, "tipo de intervención", true);
  if (!["preventivo", "correctivo"].includes(tipo) || !clases.includes(intervencion)) {
    error("invalid-argument", "Selecciona un tipo de mantenimiento y de intervención.");
  }
  return {
    tipo, intervencion,
    titulo: texto(input.titulo, 120, "título", true),
    detalle: texto(input.detalle, 1200, "diagnóstico", true),
    factura: texto(input.factura, 160, "factura"),
  };
}

function hallazgoExterno(input: Data): Data | null {
  if (input.hallazgoExterno == null) return null;
  const h = input.hallazgoExterno;
  const entidad = texto(h.entidad, 40, "entidad", true);
  const descripcion = texto(h.descripcion, 1200, "hallazgo", true);
  const fecha = texto(h.fecha, 10, "fecha del hallazgo", true);
  const limite = texto(h.limite, 10, "fecha límite", true);
  const fechaValida = (value: string) => /^\d{4}-\d{2}-\d{2}$/.test(value) &&
    !Number.isNaN(Date.parse(value)) && new Date(value).toISOString().slice(0, 10) === value;
  if (!["Interventoría", "Secretaría de Salud"].includes(entidad) ||
      !fechaValida(fecha) || !fechaValida(limite) || limite < fecha) {
    error("invalid-argument", "Revisa la entidad y las fechas del hallazgo.");
  }
  return {entidad, descripcion, fecha, limite};
}

function datosCierre(input: Data) {
  return {
    trabajo: texto(input.trabajo, 1200, "trabajo realizado"),
    materiales: texto(input.materiales, 1200, "materiales"),
    sugerencias: texto(input.sugerencias, 1200, "sugerencias"),
    tecnico: texto(input.tecnico, 120, "técnico"),
    receptor: texto(input.receptor, 120, "quien recibió"),
    cargoReceptor: texto(input.cargoReceptor, 120, "cargo de quien recibió"),
  };
}

export function cierreMantenimientoValido(cierre: ReturnType<typeof datosCierre>, archivos: Data[]): boolean {
  return Boolean(cierre.trabajo && cierre.tecnico && cierre.receptor &&
    archivos.some((archivo) => archivo.clase === "evidencia"));
}

async function validarArchivo(input: Data) {
  const clase = input.clase as keyof typeof tiposArchivo;
  const mime = texto(input.mime, 40, "tipo de archivo", true);
  if (!Object.hasOwnProperty.call(tiposArchivo, clase) || !tiposArchivo[clase].includes(mime)) {
    error("invalid-argument", "Usa JPG o PNG para fotos y JPG, PNG o PDF para documentos.");
  }
  const nombre = texto(input.nombre, 150, "nombre del archivo", true);
  const contenido = input.base64;
  if (typeof contenido !== "string" || contenido.length > Math.ceil(limiteArchivo / 3) * 4) {
    error("invalid-argument", "Cada archivo puede pesar hasta 5 MB.");
  }
  const bytes = Buffer.from(contenido, "base64");
  if (!bytes.length || bytes.length > limiteArchivo || bytes.toString("base64") !== contenido) {
    error("invalid-argument", "Archivo inválido o mayor de 5 MB.");
  }
  try {
    if (mime === "application/pdf") await PDFDocument.load(bytes);
    else {
      const pdf = await PDFDocument.create();
      if (mime === "image/png") await pdf.embedPng(bytes);
      else await pdf.embedJpg(bytes);
    }
  } catch {
    return error("invalid-argument", "El archivo no coincide con su formato o está dañado.");
  }
  return {clase, mime, nombre, bytes};
}

export const mantenimientoOrden = functions.region("us-central1").https.onCall(async (input: Data, context) => {
  const token = context.auth?.token;
  if (token?.authVersion !== 2 || typeof token.userDocId !== "string") {
    error("unauthenticated", "Inicia sesión para gestionar órdenes.");
  }
  const userId = id(token.userDocId, "usuario");
  const empresaId = id(input?.empresaId, "empresa");
  const accion = input.accion;
  const db = admin.firestore();
  const coleccion = db.collection(ordenes);
  const usuarioRef = db.collection("TBL_USUARIOS").doc(userId);
  const accesoRef = db.collection("TBL_MANTENIMIENTO_ACCESOS").doc(`${empresaId}_${userId}`);
  const appRef = db.collection("TBL_APPS").doc(`${empresaId}_${appId}`);
  const fecha = admin.firestore.FieldValue.serverTimestamp();
  const autorizar = (usuario: Data | undefined, acceso: Data | undefined, app: Data | undefined) => {
    if (!operaOrdenMantenimiento(usuario, acceso, app, empresaId, userId)) {
      error("permission-denied", "No tienes acceso a Mantenimiento en esta empresa.");
    }
  };
  if (accion === "tareas" || (accion === "crear" && input.tareaId)) {
    const [usuario, acceso, app] = await db.getAll(usuarioRef, accesoRef, appRef);
    autorizar(usuario.data(), acceso.data(), app.data());
    if (accion === "tareas") return {tareas: await listarTareasMantenimiento(db, empresaId)};
  }
  const tareaId = accion === "crear" ? id(input.tareaId, "tarea", false) : "";
  const solicitudId = accion === "crear" ? id(input.ordenId, "solicitud") : "";
  const ordenId = tareaId
    ? "tarea_" + createHash("sha256").update(JSON.stringify([empresaId, tareaId])).digest("hex")
    : id(input.ordenId, "orden");
  const ref = coleccion.doc(ordenId);

  async function leer(tx: Tx) {
    const [usuario, acceso, app, orden] = await tx.getAll(usuarioRef, accesoRef, appRef, ref);
    autorizar(usuario.data(), acceso.data(), app.data());
    const data = orden.data();
    if (data?.empresaId !== empresaId && (data || accion !== "crear")) {
      error("not-found", "La orden no está disponible.");
    }
    return data;
  }

  if (accion === "crear") {
    const trabajo = datosTrabajo(input);
    const externo = hallazgoExterno(input);
    const centroDocId = id(input.centroDocId, "establecimiento");
    const equipoId = id(input.equipoId, "equipo", false);
    const vinculoHallazgo = id(input.hallazgoId, "hallazgo", false);
    if (externo && (vinculoHallazgo || tareaId)) error("invalid-argument", "Selecciona un solo origen.");
    if (!tareaId && ordenId.startsWith("tarea_")) error("invalid-argument", "Identificador reservado.");
    const subcentroId = id(input.subcentroId, "estructura", false);
    const catalogo = tareaId ? await catalogoTareasMantenimiento(db, empresaId) : null;
    return db.runTransaction(async (tx) => {
      const existente = await leer(tx);
      if (existente) {
        if (tareaId && existente.tareaId === tareaId) {
          return {
            numero: existente.numero, ordenId, existente: true,
            mismaSolicitud: existente.creadaPor === userId && existente.solicitudId === solicitudId,
          };
        }
        if (existente.creadaPor === userId) return {numero: existente.numero, ordenId};
        return error("already-exists", "La orden ya existe.");
      }
      let hallazgoId = vinculoHallazgo;
      let origenTarea: string | null = null;
      let referenciaTarea: Data | null = null;
      let estructuraTarea: {subcentroId: string; subcentroNombre: string} | null = null;
      if (catalogo) {
        const tarea = (await tx.get(db.collection("TBL_TAREAS").doc(tareaId))).data();
        const origen = tarea ? tareaParaMantenimiento(tarea, catalogo) : null;
        if (!tarea || !origen) {
          error("failed-precondition", "La tarea ya no está pendiente en Mantenimiento de esta empresa.");
        }
        const centroTarea = centroTareaMantenimiento(tarea, catalogo.centros);
        if (centroTarea && centroTarea.id !== centroDocId) {
          const original = (await tx.get(centroTarea.ref)).data();
          if (original?.empresaId === empresaId && original.enabled !== false) {
            error("invalid-argument", "El establecimiento debe coincidir con el de la tarea.");
          }
        }
        if (centroTarea?.id === centroDocId && tarea.subcentroId) {
          if (tarea.subcentroId !== subcentroId) {
            error("invalid-argument", "La estructura debe coincidir con la de la tarea.");
          }
          estructuraTarea = {subcentroId, subcentroNombre: texto(tarea.subcentroNombre, 200, "estructura")};
        }
        origenTarea = origen.origen;
        const plazo = fechaLimiteTarea(tarea);
        referenciaTarea = {
          numeroTarea: numeroDeTarea(tarea),
          responsableTarea: String(tarea.asignado_nombre ?? tarea.assignedToName ?? "").trim().slice(0, 120),
          limiteTarea: plazo == null ? null : admin.firestore.Timestamp.fromMillis(plazo),
        };
        hallazgoId = origenTarea === "interventoria"
          ? id(tarea.hallazgoId ?? tarea.source?.entityId ?? tarea.sourceEntityId, "hallazgo", false) : "";
      }
      const contador = db.collection("TBL_MANTENIMIENTO_CONTADORES").doc(empresaId);
      const [centroSnap, secuencia, equipo, hallazgo] = await Promise.all([
        tx.get(db.collection("TBL_CENTROS_COSTOS").doc(centroDocId)),
        tx.get(contador),
        equipoId ? tx.get(db.collection("TBL_MANTENIMIENTO_EQUIPOS").doc(equipoId)) : null,
        hallazgoId ? tx.get(db.collection("TBL_INTERVENTORIA_HALLAZGOS").doc(hallazgoId)) : null,
      ]);
      const centro = centroSnap.data();
      if (!centro || centro.empresaId !== empresaId || centro.enabled === false) {
        error("invalid-argument", "El establecimiento no está activo en esta empresa.");
      }
      if (equipoId && (equipo?.data()?.empresaId !== empresaId || equipo.data()?.centroDocId !== centroDocId)) {
        error("invalid-argument", "El equipo no pertenece al establecimiento.");
      }
      if (hallazgoId) {
        const h = hallazgo?.data();
        if (!h || h.empresaId !== empresaId || ![centroDocId, centro.centroId].includes(h.centroCostoId) ||
          (h.subcentroId && h.subcentroId !== subcentroId)) {
          if (tareaId) {
            // La tarea conserva su vínculo aunque su acta histórica ya no exista
            // o el centro original esté inactivo.
            hallazgoId = "";
          } else {
            error("invalid-argument", "El hallazgo no corresponde a la ubicación seleccionada.");
          }
        }
      }
      const numero = (secuencia.data()?.ultimo ?? 0) + 1;
      if (!Number.isSafeInteger(numero) || numero <= 0) error("internal", "Consecutivo inválido.");
      tx.set(contador, {ultimo: numero});
      tx.create(ref, {
        ...trabajo, ...(estructuraTarea ?? subcentroDe(centro, subcentroId)),
        empresaId, centroDocId, equipoId, hallazgoId,
        hallazgoExterno: externo,
        ...(tareaId ? {tareaId, origenTarea, solicitudId, ...referenciaTarea} : {}),
        esquema: 2, numero, creadaPor: userId, estado: "abierta", resultado: "", cerradaAt: null,
        createdAt: fecha, updatedAt: fecha,
      });
      return {numero, ordenId};
    });
  }

  if (accion === "leerArchivo") {
    const archivoId = id(input.archivoId, "archivo");
    const archivo = await db.runTransaction(async (tx) => {
      const orden = (await leer(tx))!;
      const archivo = orden.archivos?.find((a: Data) => a.id === archivoId);
      const secreto = (await tx.get(db.collection(privados).doc(archivoId))).data();
      if (!archivo || !secreto || secreto.empresaId !== empresaId || secreto.ordenId !== ref.id) {
        return error("not-found", "El archivo no está disponible.");
      }
      return {...secreto, ...archivo};
    }, {readOnly: true});
    const [bytes] = await admin.storage().bucket().file(archivo.path).download();
    const cipher = createDecipheriv("aes-256-gcm", Buffer.from(archivo.key, "base64"), Buffer.from(archivo.iv, "base64"));
    cipher.setAuthTag(Buffer.from(archivo.tag, "base64"));
    return {base64: Buffer.concat([cipher.update(bytes), cipher.final()]).toString("base64")};
  }

  if (accion === "adjuntar") {
    await db.runTransaction(async (tx) => {
      const orden = (await leer(tx))!;
      if (orden.estado === "cerrada") error("failed-precondition", "La orden ya está cerrada.");
    }, {readOnly: true});
    const {bytes, ...metadata} = await validarArchivo(input);
    const archivoId = id(input.archivoId, "archivo");
    const privado = db.collection(privados).doc(archivoId);
    const path = `mantenimiento/${empresaId}/${ref.id}/${randomUUID()}`;
    const file = admin.storage().bucket().file(path);
    const key = randomBytes(32);
    const iv = randomBytes(12);
    const cipher = createCipheriv("aes-256-gcm", key, iv);
    const cifrado = Buffer.concat([cipher.update(bytes), cipher.final()]);
    await file.save(cifrado, {resumable: false, contentType: "application/octet-stream"});
    try {
      const guardado = await db.runTransaction(async (tx) => {
        const orden = (await leer(tx))!;
        if (orden.estado === "cerrada") error("failed-precondition", "La orden ya está cerrada.");
        const archivos: Data[] = orden.archivos ?? [];
        if (archivos.some((a) => a.id === archivoId)) return false;
        if (archivos.filter((a) => a.clase === metadata.clase).length >= 6) {
          error("failed-precondition", "Puedes adjuntar hasta seis archivos de cada tipo.");
        }
        tx.create(privado, {empresaId, ordenId: ref.id, path, key: key.toString("base64"),
          iv: iv.toString("base64"), tag: cipher.getAuthTag().toString("base64")});
        tx.update(ref, {esquema: 2, archivos: [...archivos, {...metadata, id: archivoId}]});
        return true;
      });
      if (!guardado) await file.delete({ignoreNotFound: true});
    } catch (e) {
      await file.delete({ignoreNotFound: true}).catch(() => undefined);
      throw e;
    }
    return {ok: true};
  }

  if (accion === "quitarArchivo") {
    const archivoId = id(input.archivoId, "archivo");
    const privado = db.collection(privados).doc(archivoId);
    const path = await db.runTransaction(async (tx) => {
      const orden = (await leer(tx))!;
      const secreto = (await tx.get(privado)).data();
      if (orden.estado === "cerrada") error("failed-precondition", "La orden ya está cerrada.");
      const archivos: Data[] = orden.archivos ?? [];
      if (!archivos.some((a) => a.id === archivoId) ||
          secreto?.empresaId !== empresaId || secreto.ordenId !== ref.id) return null;
      tx.update(ref, {archivos: archivos.filter((a) => a.id !== archivoId)});
      tx.delete(privado);
      return secreto.path as string;
    });
    if (path) {
      await admin.storage().bucket().file(path).delete({ignoreNotFound: true}).catch((e) => {
        functions.logger.warn("No se pudo retirar archivo cifrado de Mantenimiento", e.message);
      });
    }
    return {ok: true};
  }

  return db.runTransaction(async (tx) => {
    const orden = (await leer(tx))!;
    if (!versionCoincide(orden, input)) error("aborted", "La orden cambió. Abre la versión actualizada.");
    if (orden.estado === "cerrada") {
      if (accion !== "factura" || orden.esquema === 2) {
        error("failed-precondition", "La orden ya está cerrada.");
      }
      tx.update(ref, {factura: texto(input.factura, 160, "factura"), updatedAt: fecha});
    } else if (accion === "editar") {
      tx.update(ref, {...datosTrabajo(input), esquema: 2, updatedAt: fecha});
    } else if (accion === "iniciar" && orden.estado === "abierta") {
      tx.update(ref, {estado: "en_curso", esquema: 2, updatedAt: fecha});
    } else if (accion === "borrador" || accion === "cerrar") {
      const cierre = datosCierre(input);
      if (accion === "cerrar" && !cierreMantenimientoValido(cierre, orden.archivos ?? [])) {
        error("failed-precondition", "Registra el trabajo, el técnico, quien recibió y al menos una foto final.");
      }
      tx.update(ref, {
        cierre, factura: texto(input.factura, 160, "factura"), esquema: 2, updatedAt: fecha,
        ...(accion === "cerrar" ? {
          estado: "cerrada", resultado: cierre.trabajo, cerradaAt: fecha, cerradaPor: userId,
        } : {}),
      });
    } else {
      error("invalid-argument", "Acción de mantenimiento inválida.");
    }
    return {ok: true};
  });
});
