"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || function (mod) {
    if (mod && mod.__esModule) return mod;
    var result = {};
    if (mod != null) for (var k in mod) if (k !== "default" && Object.prototype.hasOwnProperty.call(mod, k)) __createBinding(result, mod, k);
    __setModuleDefault(result, mod);
    return result;
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.mantenimientoOrden = exports.appIdMantenimiento = void 0;
exports.errorMantenimiento = error;
exports.textoMantenimiento = textoMantenimiento;
exports.idMantenimiento = idMantenimiento;
exports.operaOrdenMantenimiento = operaOrdenMantenimiento;
exports.cierreMantenimientoValido = cierreMantenimientoValido;
const admin = __importStar(require("firebase-admin"));
const functions = __importStar(require("firebase-functions/v1"));
const crypto_1 = require("crypto");
const pdf_lib_1 = require("pdf-lib");
const apps_por_empresa_1 = require("./apps_por_empresa");
const acceso_1 = require("./acceso");
const mantenimiento_tareas_1 = require("./mantenimiento_tareas");
const tareas_numero_1 = require("./tareas_numero");
const whatsapp_1 = require("./whatsapp");
exports.appIdMantenimiento = "mantenimientodashboard";
const appId = exports.appIdMantenimiento;
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
function error(code, message) {
    throw new functions.https.HttpsError(code, message);
}
function textoMantenimiento(value, max, label, required = false) {
    const result = typeof value === "string" ? value.trim() : "";
    if (result.length > max || (required && !result)) {
        error("invalid-argument", `Revisa el campo «${label}».`);
    }
    return result;
}
const texto = textoMantenimiento;
function idMantenimiento(value, label, required = true) {
    const result = texto(value, 200, label, required);
    if (result.includes("/") || result === "." || result === "..") {
        error("invalid-argument", `Identificador inválido de ${label}.`);
    }
    return result;
}
const id = idMantenimiento;
function operaOrdenMantenimiento(usuario, acceso, app, empresaId, userId) {
    if (!usuario || (0, acceso_1.cuentaInhabilitada)(usuario) || (0, acceso_1.inhabilitadaEn)(usuario, empresaId))
        return false;
    const detalle = usuario.empresasDetalle?.[empresaId];
    const pertenece = usuario.empresaId === empresaId || usuario.empresa === empresaId ||
        (Array.isArray(usuario.empresas) && usuario.empresas.includes(empresaId)) ||
        Object.hasOwnProperty.call(usuario.empresasDetalle ?? {}, empresaId);
    return pertenece && detalle?.activo !== false && detalle?.soloTalentoHumano !== true &&
        acceso?.empresaId === empresaId && acceso.userId === userId && acceso.operador === true &&
        app?.empresaId === empresaId && app.appId === appId && app.enabled === true &&
        (0, apps_por_empresa_1.appsDeEmpresa)(usuario, empresaId).some((a) => a === appId || a === "mantenimiento");
}
function versionCoincide(orden, input) {
    const actual = orden.updatedAt;
    return actual ? actual.seconds === input.segundos && actual.nanoseconds === input.nanosegundos :
        input.segundos == null && input.nanosegundos == null;
}
function subcentroDe(centro, subcentroId) {
    if (!subcentroId)
        return { subcentroId: "", subcentroNombre: "" };
    const elementos = Array.isArray(centro.subcentros) ? centro.subcentros : [];
    for (const item of elementos) {
        const nombre = (typeof item === "string" ? item : item?.nombre ?? "").toString().trim();
        const slug = nombre.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "")
            .replace(/[^a-z0-9]+/g, "_").replace(/^_|_$/g, "");
        if (((item?.id ?? "").toString().trim() || slug) === subcentroId && nombre && item?.enabled !== false) {
            return { subcentroId, subcentroNombre: nombre };
        }
    }
    return error("invalid-argument", "La estructura no está activa en este establecimiento.");
}
function datosTrabajo(input) {
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
        ...(input.actividades == null ? {} : { actividades: texto(input.actividades, 1200, "actividades previstas") }),
    };
}
function hallazgoExterno(input) {
    if (input.hallazgoExterno == null)
        return null;
    const h = input.hallazgoExterno;
    const entidad = texto(h.entidad, 40, "entidad", true);
    const descripcion = texto(h.descripcion, 1200, "hallazgo", true);
    const fecha = texto(h.fecha, 10, "fecha del hallazgo", true);
    const limite = texto(h.limite, 10, "fecha límite", true);
    const fechaValida = (value) => /^\d{4}-\d{2}-\d{2}$/.test(value) &&
        !Number.isNaN(Date.parse(value)) && new Date(value).toISOString().slice(0, 10) === value;
    if (!["Interventoría", "Secretaría de Salud"].includes(entidad) ||
        !fechaValida(fecha) || !fechaValida(limite) || limite < fecha) {
        error("invalid-argument", "Revisa la entidad y las fechas del hallazgo.");
    }
    return { entidad, descripcion, fecha, limite };
}
function datosCierre(input) {
    return {
        trabajo: texto(input.trabajo, 1200, "trabajo realizado"),
        materiales: texto(input.materiales, 1200, "materiales"),
        sugerencias: texto(input.sugerencias, 1200, "sugerencias"),
        tecnico: texto(input.tecnico, 120, "técnico"),
        receptor: texto(input.receptor, 120, "quien recibió"),
        cargoReceptor: texto(input.cargoReceptor, 120, "cargo de quien recibió"),
    };
}
function cierreMantenimientoValido(cierre, archivos) {
    return Boolean(cierre.trabajo && cierre.tecnico && cierre.receptor &&
        archivos.some((archivo) => archivo.clase === "evidencia"));
}
async function validarArchivo(input) {
    const clase = input.clase;
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
        if (mime === "application/pdf")
            await pdf_lib_1.PDFDocument.load(bytes);
        else {
            const pdf = await pdf_lib_1.PDFDocument.create();
            if (mime === "image/png")
                await pdf.embedPng(bytes);
            else
                await pdf.embedJpg(bytes);
        }
    }
    catch {
        return error("invalid-argument", "El archivo no coincide con su formato o está dañado.");
    }
    return { clase, mime, nombre, bytes };
}
exports.mantenimientoOrden = functions.region("us-central1").https.onCall(async (input, context) => {
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
    const autorizar = (usuario, acceso, app) => {
        if (!operaOrdenMantenimiento(usuario, acceso, app, empresaId, userId)) {
            error("permission-denied", "No tienes acceso a Mantenimiento en esta empresa.");
        }
    };
    if (accion === "tareas" || accion === "listadosPdf" ||
        (accion === "crear" && (input.tareaId || input.tareaIds))) {
        const [usuario, acceso, app] = await db.getAll(usuarioRef, accesoRef, appRef);
        autorizar(usuario.data(), acceso.data(), app.data());
        if (accion === "tareas")
            return { tareas: await (0, mantenimiento_tareas_1.listarTareasMantenimiento)(db, empresaId) };
        if (accion === "listadosPdf")
            return (0, whatsapp_1.listadosPdfWhatsApp)(empresaId, appId);
    }
    const adicionales = accion === "crear" ? input.tareaIds ?? [] : [];
    if (!Array.isArray(adicionales) || adicionales.length > 19) {
        error("invalid-argument", "Puedes procesar hasta 20 tareas en una orden.");
    }
    const tareaId = accion === "crear" ? id(input.tareaId, "tarea", false) : "";
    if (!tareaId && adicionales.length)
        error("invalid-argument", "Selecciona la primera tarea.");
    const tareaIds = [...new Set([tareaId, ...adicionales.map((v) => id(v, "tarea"))].filter(Boolean))];
    const solicitudId = accion === "crear" ? id(input.ordenId, "solicitud") : "";
    const claveTarea = (valor) => "tarea_" + (0, crypto_1.createHash)("sha256").update(JSON.stringify([empresaId, valor])).digest("hex");
    const ordenId = tareaId
        ? claveTarea(tareaId)
        : id(input.ordenId, "orden");
    const ref = coleccion.doc(ordenId);
    async function leer(tx) {
        const [usuario, acceso, app, orden] = await tx.getAll(usuarioRef, accesoRef, appRef, ref);
        autorizar(usuario.data(), acceso.data(), app.data());
        const data = orden.data();
        if (data?.empresaId !== empresaId && (data || accion !== "crear")) {
            error("not-found", "La orden no está disponible.");
        }
        return data;
    }
    if (accion === "enviarPdf") {
        const orden = await db.runTransaction(async (tx) => (await leer(tx)), { readOnly: true });
        if (orden.estado !== "cerrada")
            error("failed-precondition", "Cierra la orden antes de enviar el informe.");
        const listadoId = id(input.listadoId, "listado de WhatsApp");
        const { bytes } = await validarArchivo({
            clase: "recibo", mime: "application/pdf", nombre: "orden.pdf", base64: input.base64,
        });
        return (0, whatsapp_1.enviarPdfWhatsApp)({
            empresaId, moduleId: appId, listadoId, actorId: userId, bytes,
            nombre: `orden_${orden.numero ?? ref.id}.pdf`, mensaje: `Informe de orden de trabajo ${orden.numero ?? ref.id}`,
            historial: ref.collection("enviosPdf"),
        });
    }
    if (accion === "crear") {
        const trabajo = datosTrabajo(input);
        const externo = hallazgoExterno(input);
        const centroDocId = id(input.centroDocId, "establecimiento");
        const equipoId = id(input.equipoId, "equipo", false);
        const vinculoHallazgo = id(input.hallazgoId, "hallazgo", false);
        if (externo && (vinculoHallazgo || tareaId))
            error("invalid-argument", "Selecciona un solo origen.");
        if (!tareaId && ordenId.startsWith("tarea_"))
            error("invalid-argument", "Identificador reservado.");
        const subcentroId = id(input.subcentroId, "estructura", false);
        const catalogo = tareaId ? await (0, mantenimiento_tareas_1.catalogoTareasMantenimiento)(db, empresaId) : null;
        return db.runTransaction(async (tx) => {
            const existente = await leer(tx);
            const refsTareas = tareaIds.map((valor) => coleccion.doc(claveTarea(valor)));
            const refsVinculos = refsTareas.map((t) => t.collection("vinculos").doc("orden"));
            const vinculos = refsVinculos.length ? await tx.getAll(...refsVinculos) : [];
            const vinculada = vinculos[0]?.data();
            if (vinculada) {
                const original = (await tx.get(coleccion.doc(vinculada.ordenId))).data();
                if (original?.empresaId !== empresaId ||
                    (tareaIds.length > 1 && JSON.stringify(original.tareaIds) !== JSON.stringify(tareaIds))) {
                    error("already-exists", "Una tarea ya tiene orden. Actualiza la bandeja.");
                }
                return {
                    numero: original.numero, ordenId: vinculada.ordenId, existente: true,
                    mismaSolicitud: original.creadaPor === userId && original.solicitudId === solicitudId,
                };
            }
            if (existente) {
                if (tareaId && existente.tareaId === tareaId) {
                    if (tareaIds.length > 1)
                        error("already-exists", "La primera tarea ya tiene una orden.");
                    return {
                        numero: existente.numero, ordenId, existente: true,
                        mismaSolicitud: existente.creadaPor === userId && existente.solicitudId === solicitudId,
                    };
                }
                if (existente.creadaPor === userId)
                    return { numero: existente.numero, ordenId };
                return error("already-exists", "La orden ya existe.");
            }
            let hallazgoId = vinculoHallazgo;
            let origenTarea = null;
            let referenciaTarea = null;
            let estructuraTarea = null;
            const tareasOrigen = [];
            if (catalogo) {
                if (vinculos.some((v) => v.exists) ||
                    (refsTareas.length > 1 && (await tx.getAll(...refsTareas.slice(1))).some((v) => v.exists))) {
                    error("already-exists", "Una tarea ya tiene orden. Actualiza la bandeja.");
                }
                const documentos = await tx.getAll(...tareaIds.map((valor) => db.collection("TBL_TAREAS").doc(valor)));
                for (const doc of documentos) {
                    const datos = doc.data();
                    const origen = datos && (0, mantenimiento_tareas_1.tareaParaMantenimiento)(datos, catalogo);
                    if (!datos || !origen)
                        error("failed-precondition", "Una tarea ya no está pendiente en Mantenimiento.");
                    if (tareaIds.length > 1 && (0, mantenimiento_tareas_1.centroTareaMantenimiento)(datos, catalogo.centros)?.id !== centroDocId) {
                        error("invalid-argument", "Las tareas seleccionadas deben pertenecer al mismo establecimiento.");
                    }
                    tareasOrigen.push({
                        id: doc.id, origen: origen.origen, estado: origen.estado,
                        numero: (0, tareas_numero_1.numeroDeTarea)(datos), fechaLimite: (0, mantenimiento_tareas_1.fechaLimiteTarea)(datos), centroDocId,
                        titulo: String(datos.titulo ?? datos.title ?? "").slice(0, 120),
                        descripcion: String(datos.descripcion ?? datos.description ?? "").slice(0, 1200),
                        responsable: String(datos.asignado_nombre ?? datos.assignedToName ?? "").slice(0, 120),
                        subcentroId: String(datos.subcentroId ?? "").slice(0, 200),
                        subcentroNombre: String(datos.subcentroNombre ?? "").slice(0, 200),
                        hallazgoId: String(datos.hallazgoId ?? "").slice(0, 200),
                    });
                }
                const tarea = documentos[0].data();
                const origen = tarea ? (0, mantenimiento_tareas_1.tareaParaMantenimiento)(tarea, catalogo) : null;
                if (!tarea || !origen) {
                    error("failed-precondition", "La tarea ya no está pendiente en Mantenimiento de esta empresa.");
                }
                const centroTarea = (0, mantenimiento_tareas_1.centroTareaMantenimiento)(tarea, catalogo.centros);
                if (centroTarea && centroTarea.id !== centroDocId) {
                    const original = (await tx.get(centroTarea.ref)).data();
                    if (original?.empresaId === empresaId && original.enabled !== false) {
                        error("invalid-argument", "El establecimiento debe coincidir con el de la tarea.");
                    }
                }
                if (tareaIds.length === 1 && centroTarea?.id === centroDocId && tarea.subcentroId) {
                    if (tarea.subcentroId !== subcentroId) {
                        error("invalid-argument", "La estructura debe coincidir con la de la tarea.");
                    }
                    estructuraTarea = { subcentroId, subcentroNombre: texto(tarea.subcentroNombre, 200, "estructura") };
                }
                origenTarea = origen.origen;
                const plazo = (0, mantenimiento_tareas_1.fechaLimiteTarea)(tarea);
                referenciaTarea = {
                    numeroTarea: (0, tareas_numero_1.numeroDeTarea)(tarea),
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
            const fichaEquipo = equipo?.data();
            if (equipoId && (fichaEquipo?.empresaId !== empresaId || (fichaEquipo.inventario === true
                ? !(fichaEquipo.existencias?.[centroDocId] > 0) : fichaEquipo.centroDocId !== centroDocId))) {
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
                    }
                    else {
                        error("invalid-argument", "El hallazgo no corresponde a la ubicación seleccionada.");
                    }
                }
            }
            const numero = (secuencia.data()?.ultimo ?? 0) + 1;
            if (!Number.isSafeInteger(numero) || numero <= 0)
                error("internal", "Consecutivo inválido.");
            tx.set(contador, { ultimo: numero });
            refsVinculos.forEach((vinculo) => tx.create(vinculo, { ordenId }));
            tx.create(ref, {
                ...trabajo, ...(estructuraTarea ?? subcentroDe(centro, subcentroId)),
                empresaId, centroDocId, equipoId, hallazgoId,
                hallazgoExterno: externo,
                ...(tareaId ? { tareaId, tareaIds, tareasOrigen, origenTarea, solicitudId, ...referenciaTarea } : {}),
                esquema: 2, numero, creadaPor: userId, estado: "abierta", resultado: "", cerradaAt: null,
                createdAt: fecha, updatedAt: fecha,
            });
            return { numero, ordenId };
        });
    }
    if (accion === "leerArchivo") {
        const archivoId = id(input.archivoId, "archivo");
        const archivo = await db.runTransaction(async (tx) => {
            const orden = (await leer(tx));
            const archivo = orden.archivos?.find((a) => a.id === archivoId);
            const secreto = (await tx.get(db.collection(privados).doc(archivoId))).data();
            if (!archivo || !secreto || secreto.empresaId !== empresaId || secreto.ordenId !== ref.id) {
                return error("not-found", "El archivo no está disponible.");
            }
            return { ...secreto, ...archivo };
        }, { readOnly: true });
        const [bytes] = await admin.storage().bucket().file(archivo.path).download();
        const cipher = (0, crypto_1.createDecipheriv)("aes-256-gcm", Buffer.from(archivo.key, "base64"), Buffer.from(archivo.iv, "base64"));
        cipher.setAuthTag(Buffer.from(archivo.tag, "base64"));
        return { base64: Buffer.concat([cipher.update(bytes), cipher.final()]).toString("base64") };
    }
    if (accion === "adjuntar") {
        await db.runTransaction(async (tx) => {
            const orden = (await leer(tx));
            if (orden.estado === "cerrada")
                error("failed-precondition", "La orden ya está cerrada.");
        }, { readOnly: true });
        const { bytes, ...metadata } = await validarArchivo(input);
        const archivoId = id(input.archivoId, "archivo");
        const privado = db.collection(privados).doc(archivoId);
        const path = `mantenimiento/${empresaId}/${ref.id}/${(0, crypto_1.randomUUID)()}`;
        const file = admin.storage().bucket().file(path);
        const key = (0, crypto_1.randomBytes)(32);
        const iv = (0, crypto_1.randomBytes)(12);
        const cipher = (0, crypto_1.createCipheriv)("aes-256-gcm", key, iv);
        const cifrado = Buffer.concat([cipher.update(bytes), cipher.final()]);
        await file.save(cifrado, { resumable: false, contentType: "application/octet-stream" });
        try {
            const guardado = await db.runTransaction(async (tx) => {
                const orden = (await leer(tx));
                if (orden.estado === "cerrada")
                    error("failed-precondition", "La orden ya está cerrada.");
                const archivos = orden.archivos ?? [];
                if (archivos.some((a) => a.id === archivoId))
                    return false;
                if (archivos.filter((a) => a.clase === metadata.clase).length >= 6) {
                    error("failed-precondition", "Puedes adjuntar hasta seis archivos de cada tipo.");
                }
                tx.create(privado, { empresaId, ordenId: ref.id, path, key: key.toString("base64"),
                    iv: iv.toString("base64"), tag: cipher.getAuthTag().toString("base64") });
                tx.update(ref, { esquema: 2, archivos: [...archivos, { ...metadata, id: archivoId }] });
                return true;
            });
            if (!guardado)
                await file.delete({ ignoreNotFound: true });
        }
        catch (e) {
            await file.delete({ ignoreNotFound: true }).catch(() => undefined);
            throw e;
        }
        return { ok: true };
    }
    if (accion === "quitarArchivo") {
        const archivoId = id(input.archivoId, "archivo");
        const privado = db.collection(privados).doc(archivoId);
        const path = await db.runTransaction(async (tx) => {
            const orden = (await leer(tx));
            const secreto = (await tx.get(privado)).data();
            if (orden.estado === "cerrada")
                error("failed-precondition", "La orden ya está cerrada.");
            const archivos = orden.archivos ?? [];
            if (!archivos.some((a) => a.id === archivoId) ||
                secreto?.empresaId !== empresaId || secreto.ordenId !== ref.id)
                return null;
            tx.update(ref, { archivos: archivos.filter((a) => a.id !== archivoId) });
            tx.delete(privado);
            return secreto.path;
        });
        if (path) {
            await admin.storage().bucket().file(path).delete({ ignoreNotFound: true }).catch((e) => {
                functions.logger.warn("No se pudo retirar archivo cifrado de Mantenimiento", e.message);
            });
        }
        return { ok: true };
    }
    return db.runTransaction(async (tx) => {
        const orden = (await leer(tx));
        if (!versionCoincide(orden, input))
            error("aborted", "La orden cambió. Abre la versión actualizada.");
        if (orden.estado === "cerrada") {
            if (accion !== "factura" || orden.esquema === 2) {
                error("failed-precondition", "La orden ya está cerrada.");
            }
            tx.update(ref, { factura: texto(input.factura, 160, "factura"), updatedAt: fecha });
        }
        else if (accion === "editar") {
            tx.update(ref, { ...datosTrabajo(input), esquema: 2, updatedAt: fecha });
        }
        else if (accion === "iniciar" && orden.estado === "abierta") {
            tx.update(ref, { estado: "en_curso", esquema: 2, updatedAt: fecha });
        }
        else if (accion === "borrador" || accion === "cerrar") {
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
        }
        else {
            error("invalid-argument", "Acción de mantenimiento inválida.");
        }
        return { ok: true };
    });
});
