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
exports.mantenimientoInventario = void 0;
exports.existenciasMantenimiento = existenciasMantenimiento;
const admin = __importStar(require("firebase-admin"));
const functions = __importStar(require("firebase-functions/v1"));
const crypto_1 = require("crypto");
const pdf_lib_1 = require("pdf-lib");
const apps_por_empresa_1 = require("./apps_por_empresa");
const acceso_1 = require("./acceso");
const mantenimiento_anexo_1 = require("./mantenimiento_anexo");
const mantenimiento_ordenes_1 = require("./mantenimiento_ordenes");
const mantenimiento_tareas_1 = require("./mantenimiento_tareas");
const equipos = "TBL_MANTENIMIENTO_EQUIPOS";
const minimos = "TBL_MANTENIMIENTO_MINIMOS";
const privados = "TBL_MANTENIMIENTO_ARCHIVOS";
const temporal = "_bodega_temporal";
const mimeTipos = {
    ficha: ["application/pdf"],
    foto: ["image/jpeg", "image/png"],
    video: ["video/mp4", "video/quicktime"],
};
const hash = (valores) => (0, crypto_1.createHash)("sha256").update(JSON.stringify(valores)).digest("hex");
function cantidad(value, etiqueta, min = 1) {
    if (typeof value !== "number" || !Number.isSafeInteger(value) || value < min || value > 1000000) {
        (0, mantenimiento_ordenes_1.errorMantenimiento)("invalid-argument", `Revisa la cantidad de ${etiqueta}.`);
    }
    return value;
}
function fechaISO(value, label, requerida = false) {
    const fecha = (0, mantenimiento_ordenes_1.textoMantenimiento)(value, 10, label, requerida);
    if (fecha && (!/^\d{4}-\d{2}-\d{2}$/.test(fecha) || !Number.isFinite(Date.parse(fecha)) ||
        new Date(fecha).toISOString().slice(0, 10) !== fecha))
        (0, mantenimiento_ordenes_1.errorMantenimiento)("invalid-argument", `Revisa ${label}.`);
    return fecha;
}
function existenciasMantenimiento(d) {
    if (d.inventario === true)
        return { ...d.existencias };
    // Una ficha histórica ubicada representa una unidad. Las fichas copiadas
    // o históricas sin ubicación requieren registrar su ingreso.
    return d.centroDocId ? { [d.centroDocId]: 1 } : {};
}
function familia(value) {
    const clave = (0, mantenimiento_ordenes_1.textoMantenimiento)(value, 100, "tipo del equipo");
    if (!clave)
        return "";
    if (/^anexo_\d+$/.test(clave) && mantenimiento_anexo_1.familiasAnexo[Number(clave.slice(6))])
        return clave;
    if (/^local_[a-f0-9]{24}$/.test(clave))
        return clave;
    return (0, mantenimiento_ordenes_1.errorMantenimiento)("invalid-argument", "Elige un tipo de equipo del maestro.");
}
function nombrePersona(data) {
    return String(data.nombreCompleto || data.nombre || data.displayName || data.name || "").trim().slice(0, 120);
}
async function validarArchivo(input) {
    const clase = (0, mantenimiento_ordenes_1.textoMantenimiento)(input.clase, 15, "archivo", true);
    const mime = (0, mantenimiento_ordenes_1.textoMantenimiento)(input.mime, 32, "formato", true);
    const nombre = (0, mantenimiento_ordenes_1.textoMantenimiento)(input.nombre, 150, "nombre del archivo", true);
    const max = 5 * 1024 * 1024;
    if (!mimeTipos[clase]?.includes(mime) || typeof input.base64 !== "string" ||
        input.base64.length > Math.ceil(max / 3) * 4) {
        (0, mantenimiento_ordenes_1.errorMantenimiento)("invalid-argument", "Adjunta un PDF, una foto JPG/PNG o un video MP4/MOV de hasta 5 MB.");
    }
    const bytes = Buffer.from(input.base64, "base64");
    if (!bytes.length || bytes.length > max || bytes.toString("base64") !== input.base64) {
        (0, mantenimiento_ordenes_1.errorMantenimiento)("invalid-argument", "El archivo está vacío o supera 5 MB.");
    }
    try {
        if (mime === "application/pdf")
            await pdf_lib_1.PDFDocument.load(bytes);
        else if (clase === "foto") {
            const pdf = await pdf_lib_1.PDFDocument.create();
            if (mime === "image/png")
                await pdf.embedPng(bytes);
            else
                await pdf.embedJpg(bytes);
        }
        else if (bytes.length < 16 || bytes.toString("ascii", 4, 8) !== "ftyp") {
            throw new Error("Formato de video");
        }
    }
    catch {
        (0, mantenimiento_ordenes_1.errorMantenimiento)("invalid-argument", "El archivo está dañado o su contenido no coincide con el formato.");
    }
    return { bytes, clase, mime, nombre };
}
exports.mantenimientoInventario = functions.region("us-central1").https.onCall(async (input, context) => {
    const token = context.auth?.token;
    if (token?.authVersion !== 2 || typeof token.userDocId !== "string") {
        (0, mantenimiento_ordenes_1.errorMantenimiento)("unauthenticated", "Inicia sesión para consultar el inventario.");
    }
    const usuarioId = (0, mantenimiento_ordenes_1.idMantenimiento)(token.userDocId, "usuario");
    const empresaId = (0, mantenimiento_ordenes_1.idMantenimiento)(input?.empresaId, "empresa");
    const db = admin.firestore();
    const usuarios = db.collection("TBL_USUARIOS");
    const permisos = db.collection("TBL_MANTENIMIENTO_ACCESOS");
    const modulo = db.collection("TBL_APPS").doc(`${empresaId}_${mantenimiento_ordenes_1.appIdMantenimiento}`);
    const almacen = db.collection(equipos);
    const planes = db.collection(minimos);
    const proveedores = db.collection("TBL_COMPRAS_PROVEEDORES");
    const centroRef = (valor) => db.collection("TBL_CENTROS_COSTOS").doc(valor);
    async function leerPlan(tx, centroId) {
        const canonico = await tx.get(planes.doc(`${empresaId}_${centroId}`));
        if (canonico.exists)
            return canonico;
        const existente = await tx.get(porEmpresa(planes).where("centroDocId", "==", centroId).limit(1));
        return existente.docs[0] ?? canonico;
    }
    const ahora = admin.firestore.FieldValue.serverTimestamp();
    const porEmpresa = (coleccion) => coleccion.where("empresaId", "==", empresaId);
    const refs = [usuarios.doc(usuarioId), permisos.doc(`${empresaId}_${usuarioId}`), modulo];
    async function autorizar(tx) {
        const [usuario, acceso, app] = tx ? await tx.getAll(...refs) : await db.getAll(...refs);
        if (!(0, mantenimiento_ordenes_1.operaOrdenMantenimiento)(usuario.data(), acceso.data(), app.data(), empresaId, usuarioId)) {
            (0, mantenimiento_ordenes_1.errorMantenimiento)("permission-denied", "No tienes acceso a Mantenimiento en esta empresa.");
        }
        return acceso.data();
    }
    const centroActivo = (datos) => datos?.empresaId === empresaId && datos.enabled !== false;
    const nombreCentro = (centro) => String(centro.nombre || centro.centroCostos || centro.centroId || "").slice(0, 200);
    const esOperador = (d) => (0, acceso_1.empresasSeleccionables)(d).includes(empresaId) &&
        d.empresasDetalle?.[empresaId]?.soloTalentoHumano !== true &&
        (0, apps_por_empresa_1.appsDeEmpresa)(d, empresaId).some((app) => [mantenimiento_ordenes_1.appIdMantenimiento, "mantenimiento"].includes(app));
    const accion = input.accion;
    if (accion === "catalogos") {
        const acceso = await autorizar();
        const [compras, empresaPlanes, operadores] = await Promise.all([
            porEmpresa(proveedores).get(),
            porEmpresa(planes).get(),
            porEmpresa(permisos).get(),
        ]);
        const fichas = operadores.docs.filter((a) => a.get("operador") === true).map((a) => a.get("userId"))
            .filter((v) => typeof v === "string" && !!v && !v.includes("/"));
        const personas = fichas.length ? await db.getAll(...[...new Set(fichas)].map((v) => usuarios.doc(v))) : [];
        return {
            actor: usuarioId, gestor: acceso.gestor === true,
            proveedores: compras.docs.filter((p) => p.get("activo") !== false && p.get("estado") !== "inactivo")
                .map((p) => ({ id: p.id, nombre: String(p.get("razonSocial") || p.get("nombre") || p.id).slice(0, 200) })),
            personas: personas.filter((p) => p.exists && esOperador(p.data()))
                .map((p) => ({ id: p.id, nombre: nombrePersona(p.data()) || p.id })),
            familias: mantenimiento_anexo_1.familiasAnexo.map((nombre, i) => ({ id: `anexo_${i}`, nombre })),
            minimos: empresaPlanes.docs.map((m) => {
                const d = m.data();
                return { centroDocId: d.centroDocId, ppl: d.ppl ?? 0, cantidades: d.cantidades ?? {},
                    nota: d.nota ?? "", locales: d.locales ?? {}, responsableId: d.responsableId ?? "",
                    coordinadorId: d.coordinadorId ?? "", validado: !!d.validadoPor };
            }),
        };
    }
    if (accion === "referenciaAnexo") {
        await autorizar();
        return { cantidades: (0, mantenimiento_anexo_1.minimosAnexo)(cantidad(input.ppl, "PPL")) };
    }
    if (accion === "minimos") {
        const centroId = (0, mantenimiento_ordenes_1.idMantenimiento)(input.centroDocId, "establecimiento");
        const ppl = cantidad(input.ppl, "PPL");
        const responsableId = (0, mantenimiento_ordenes_1.idMantenimiento)(input.responsableId, "responsable");
        const coordinadorId = (0, mantenimiento_ordenes_1.idMantenimiento)(input.coordinadorId, "coordinador");
        const nota = (0, mantenimiento_ordenes_1.textoMantenimiento)(input.nota, 1200, "observaciones");
        const locales = {};
        const cantidades = {};
        if (!input.cantidades || typeof input.cantidades !== "object" || Array.isArray(input.cantidades) ||
            Object.keys(input.cantidades).length > 100)
            (0, mantenimiento_ordenes_1.errorMantenimiento)("invalid-argument", "Revisa el listado de mínimos.");
        for (const [clave, valor] of Object.entries(input.cantidades)) {
            if (!familia(clave))
                (0, mantenimiento_ordenes_1.errorMantenimiento)("invalid-argument", "Revisa el tipo de equipo.");
            cantidades[clave] = cantidad(valor, "mínimo", 0);
            if (clave.startsWith("local_"))
                locales[clave] = (0, mantenimiento_ordenes_1.textoMantenimiento)(input.locales?.[clave], 120, "equipo local", true);
        }
        if (input.validar === true && !Object.keys(cantidades).length) {
            (0, mantenimiento_ordenes_1.errorMantenimiento)("invalid-argument", "Registra las cantidades que vas a validar.");
        }
        return db.runTransaction(async (tx) => {
            const acceso = await autorizar(tx);
            const plan = await leerPlan(tx, centroId);
            const [centro, responsable, coordinador, permisoR, permisoC] = await tx.getAll(centroRef(centroId), usuarios.doc(responsableId), usuarios.doc(coordinadorId), permisos.doc(`${empresaId}_${responsableId}`), permisos.doc(`${empresaId}_${coordinadorId}`));
            if (!centroActivo(centro.data()))
                (0, mantenimiento_ordenes_1.errorMantenimiento)("invalid-argument", "El establecimiento no está activo.");
            const anterior = plan.data();
            if (acceso.gestor !== true &&
                (anterior?.responsableId !== usuarioId || responsableId !== usuarioId ||
                    anterior.coordinadorId !== coordinadorId)) {
                (0, mantenimiento_ordenes_1.errorMantenimiento)("permission-denied", "El gestor de Mantenimiento debe asignar los responsables de la sede.");
            }
            if (![responsable, coordinador].every((p) => p.exists && esOperador(p.data())) ||
                ![permisoR, permisoC].every((p) => p.get("operador") === true)) {
                (0, mantenimiento_ordenes_1.errorMantenimiento)("invalid-argument", "El responsable y el coordinador necesitan acceso operativo a Mantenimiento.");
            }
            const validado = input.validar === true;
            if (validado && usuarioId !== responsableId) {
                (0, mantenimiento_ordenes_1.errorMantenimiento)("permission-denied", "El responsable designado debe validar estos mínimos.");
            }
            tx.set(plan.ref, { empresaId, centroDocId: centroId, ppl, cantidades, locales, nota,
                coordinadorId, responsableId, validadoPor: validado ? usuarioId : "",
                validadoAt: validado ? ahora : null, updatedAt: ahora, updatedBy: usuarioId });
            return { ok: true };
        });
    }
    if (accion === "subirArchivo") {
        await autorizar();
        const archivoId = (0, mantenimiento_ordenes_1.idMantenimiento)(input.archivoId, "archivo");
        const ref = db.collection(privados).doc(hash([empresaId, archivoId]));
        const { bytes, ...metadata } = await validarArchivo(input);
        const path = `mantenimiento/${empresaId}/inventario/${(0, crypto_1.randomUUID)()}`;
        const file = admin.storage().bucket().file(path);
        const key = (0, crypto_1.randomBytes)(32);
        const iv = (0, crypto_1.randomBytes)(12);
        const cipher = (0, crypto_1.createCipheriv)("aes-256-gcm", key, iv);
        await file.save(Buffer.concat([cipher.update(bytes), cipher.final()]), { resumable: false, contentType: "application/octet-stream" });
        let guardado = false;
        try {
            guardado = await db.runTransaction(async (tx) => {
                await autorizar(tx);
                const previo = (await tx.get(ref)).data();
                const digest = (0, crypto_1.createHash)("sha256").update(bytes).digest("hex");
                if (previo) {
                    if (previo.usuarioId !== usuarioId || previo.digest !== digest || previo.clase !== metadata.clase) {
                        (0, mantenimiento_ordenes_1.errorMantenimiento)("already-exists", "El identificador del archivo ya existe.");
                    }
                    return false;
                }
                tx.create(ref, { ...metadata, archivoId, empresaId, usuarioId, path, digest, createdAt: ahora,
                    key: key.toString("base64"), iv: iv.toString("base64"), tag: cipher.getAuthTag().toString("base64") });
                return true;
            });
        }
        finally {
            if (!guardado)
                await file.delete({ ignoreNotFound: true }).catch(() => undefined);
        }
        return { ok: true };
    }
    if (accion === "leerArchivo") {
        await autorizar();
        const archivo = (await db.collection(privados).doc(hash([empresaId, (0, mantenimiento_ordenes_1.idMantenimiento)(input.archivoId, "archivo")])).get()).data();
        if (!archivo || (!archivo.registroId && archivo.usuarioId !== usuarioId)) {
            (0, mantenimiento_ordenes_1.errorMantenimiento)("not-found", "El archivo no está disponible.");
        }
        const [bytes] = await admin.storage().bucket().file(archivo.path).download();
        const cipher = (0, crypto_1.createDecipheriv)("aes-256-gcm", Buffer.from(archivo.key, "base64"), Buffer.from(archivo.iv, "base64"));
        cipher.setAuthTag(Buffer.from(archivo.tag, "base64"));
        return { base64: Buffer.concat([cipher.update(bytes), cipher.final()]).toString("base64") };
    }
    async function adjuntos(tx, requeridos) {
        const ids = input.archivos ?? [];
        if (!Array.isArray(ids) || ids.length > 2 || new Set(ids).size !== ids.length) {
            (0, mantenimiento_ordenes_1.errorMantenimiento)("invalid-argument", "Revisa los archivos adjuntos.");
        }
        const referencias = ids.map((valor) => db.collection(privados).doc(hash([empresaId, (0, mantenimiento_ordenes_1.idMantenimiento)(valor, "archivo")])));
        const docs = referencias.length ? await tx.getAll(...referencias) : [];
        const datos = docs.map((doc) => {
            const a = doc.data();
            if (!a || a.empresaId !== empresaId || a.usuarioId !== usuarioId || a.registroId ||
                !requeridos.includes(a.clase))
                (0, mantenimiento_ordenes_1.errorMantenimiento)("invalid-argument", "Vuelve a adjuntar el archivo.");
            return { id: a.archivoId, clase: a.clase, nombre: a.nombre, mime: a.mime };
        });
        if (new Set(datos.map((a) => a.clase)).size !== datos.length) {
            (0, mantenimiento_ordenes_1.errorMantenimiento)("invalid-argument", "Adjunta un archivo de cada tipo.");
        }
        return { datos, vincular: (registroId) => referencias.forEach((r) => tx.update(r, { registroId })) };
    }
    if (accion === "alta") {
        const solicitudId = (0, mantenimiento_ordenes_1.idMantenimiento)(input.solicitudId, "solicitud");
        const codigo = (0, mantenimiento_ordenes_1.textoMantenimiento)(input.codigo, 60, "rótulo", true);
        const clave = codigo.normalize("NFKC").toLocaleLowerCase("es");
        const copiaId = (0, mantenimiento_ordenes_1.idMantenimiento)(input.equipoId, "ficha base", false);
        const ref = almacen.doc(copiaId || hash([empresaId, clave]));
        const categoria = (0, mantenimiento_ordenes_1.textoMantenimiento)(input.categoria, 15, "categoría", true);
        const propiedad = (0, mantenimiento_ordenes_1.textoMantenimiento)(input.propiedad, 20, "propiedad", true);
        if (!["equipo", "fungible"].includes(categoria) ||
            !["propio", "alquilado", "tercero", "prestado", "comodato"].includes(propiedad)) {
            (0, mantenimiento_ordenes_1.errorMantenimiento)("invalid-argument", "Revisa la categoría y la propiedad.");
        }
        const proveedorId = (0, mantenimiento_ordenes_1.idMantenimiento)(input.proveedorId, "proveedor", false);
        const cantidadInicial = input.grupo === true ? cantidad(input.cantidad, "unidades") : 1;
        const fechaCompra = fechaISO(input.fechaCompra, "fecha de compra");
        const fechaIngreso = fechaISO(input.fechaIngreso, "fecha de ingreso", true);
        if (fechaCompra && fechaCompra > fechaIngreso)
            (0, mantenimiento_ordenes_1.errorMantenimiento)("invalid-argument", "La compra debe ser anterior al ingreso.");
        const ficha = {
            empresaId, codigo, referencia: (0, mantenimiento_ordenes_1.textoMantenimiento)(input.referencia, 100, "referencia"),
            nombre: (0, mantenimiento_ordenes_1.textoMantenimiento)(input.nombre, 120, "nombre", true), descripcion: (0, mantenimiento_ordenes_1.textoMantenimiento)(input.descripcion, 1200, "descripción"),
            categoria, propiedad, grupo: input.grupo === true, familia: familia(input.familia),
            clasificacion: (0, mantenimiento_ordenes_1.textoMantenimiento)(input.clasificacion, 100, "clasificación"),
            otraClasificacion: (0, mantenimiento_ordenes_1.textoMantenimiento)(input.otraClasificacion, 100, "otra clasificación"),
            serie: (0, mantenimiento_ordenes_1.textoMantenimiento)(input.serie, 100, "serie"), factura: (0, mantenimiento_ordenes_1.textoMantenimiento)(input.factura, 160, "factura"),
            fechaCompra, fechaIngreso, proveedorId, cantidadInicial,
        };
        return db.runTransaction(async (tx) => {
            await autorizar(tx);
            const previo = (await tx.get(ref)).data();
            if (previo?.empresaId === empresaId && previo.solicitudId === solicitudId && previo.creadoPor === usuarioId) {
                return { id: ref.id };
            }
            if (copiaId && (!previo || previo.empresaId !== empresaId || previo.codigo !== codigo ||
                previo.inventario === true || Object.keys(existenciasMantenimiento(previo)).length)) {
                (0, mantenimiento_ordenes_1.errorMantenimiento)("failed-precondition", "La ficha base cambió o ya tiene existencias.");
            }
            const indice = almacen.doc(hash([empresaId, clave]));
            const bloqueo = indice.collection("codigos").doc("actual");
            const [codigoActual, duplicado] = await Promise.all([
                tx.get(bloqueo), tx.get(porEmpresa(almacen).where("codigo", "==", codigo).limit(2)),
            ]);
            if ((!copiaId && previo) || codigoActual.exists || duplicado.docs.some((d) => d.id !== copiaId)) {
                (0, mantenimiento_ordenes_1.errorMantenimiento)("already-exists", "Ya existe una ficha con ese rótulo.");
            }
            const prov = proveedorId ? (await tx.get(proveedores.doc(proveedorId))).data() : null;
            if (proveedorId && (!prov || prov.empresaId !== empresaId || prov.activo === false || prov.estado === "inactivo")) {
                (0, mantenimiento_ordenes_1.errorMantenimiento)("invalid-argument", "Selecciona un proveedor activo de Compras.");
            }
            const archivos = await adjuntos(tx, ["ficha", "foto"]);
            if (!archivos.datos.some((a) => a.clase === "ficha"))
                (0, mantenimiento_ordenes_1.errorMantenimiento)("invalid-argument", "Adjunta la ficha técnica en PDF.");
            archivos.vincular(ref.id);
            tx.create(bloqueo, { equipoId: ref.id });
            tx.set(ref, { ...ficha, inventario: true, centroDocId: "", existencias: { [temporal]: cantidadInicial },
                proveedorNombre: String(prov?.razonSocial ?? prov?.nombre ?? "").slice(0, 200),
                archivos: archivos.datos, solicitudId, creadoPor: usuarioId, createdAt: ahora, updatedAt: ahora }, { merge: Boolean(copiaId) });
            return { id: ref.id };
        });
    }
    const ref = almacen.doc((0, mantenimiento_ordenes_1.idMantenimiento)(input.equipoId, "equipo"));
    const movimientos = ref.collection("movimientos");
    if (accion === "asociar") {
        const clave = familia(input.familia);
        return db.runTransaction(async (tx) => {
            await autorizar(tx);
            if ((await tx.get(ref)).get("empresaId") !== empresaId)
                (0, mantenimiento_ordenes_1.errorMantenimiento)("not-found", "El equipo no está disponible.");
            tx.update(ref, { familia: clave, updatedAt: ahora });
            return { ok: true };
        });
    }
    if (accion === "historial") {
        await autorizar();
        if ((await ref.get()).get("empresaId") !== empresaId)
            (0, mantenimiento_ordenes_1.errorMantenimiento)("not-found", "El equipo no está disponible.");
        const registros = await movimientos.orderBy("createdAt", "desc").limit(100).get();
        return { movimientos: registros.docs.map((doc) => {
                const { createdAt, ...d } = doc.data();
                return { id: doc.id, ...d, fecha: createdAt.toMillis() };
            }) };
    }
    if (accion !== "traslado" && accion !== "baja")
        (0, mantenimiento_ordenes_1.errorMantenimiento)("invalid-argument", "Acción de inventario inválida.");
    const traslado = accion === "traslado";
    const movimiento = movimientos.doc((0, mantenimiento_ordenes_1.idMantenimiento)(input.solicitudId, "movimiento"));
    const origen = (0, mantenimiento_ordenes_1.idMantenimiento)(input.origen, "bodega de origen");
    const destino = traslado ? (0, mantenimiento_ordenes_1.idMantenimiento)(input.destino, "destino") : "";
    if (origen === destino)
        (0, mantenimiento_ordenes_1.errorMantenimiento)("invalid-argument", "Elige una bodega diferente.");
    const unidades = cantidad(input.cantidad, "unidades");
    const entrega = traslado ? (0, mantenimiento_ordenes_1.textoMantenimiento)(input.entrega, 120, "quien entrega", true) : "";
    const recibe = traslado ? (0, mantenimiento_ordenes_1.textoMantenimiento)(input.recibe, 120, "quien recibe", true) : "";
    const observaciones = (0, mantenimiento_ordenes_1.textoMantenimiento)(input.observaciones, 1200, "observaciones", !traslado);
    const catalogo = !traslado ? await (0, mantenimiento_tareas_1.catalogoTareasMantenimiento)(db, empresaId) : null;
    return db.runTransaction(async (tx) => {
        await autorizar(tx);
        const [equipo, previo] = await tx.getAll(ref, movimiento);
        const d = equipo.data();
        if (!d || d.empresaId !== empresaId)
            (0, mantenimiento_ordenes_1.errorMantenimiento)("not-found", "El equipo no está disponible.");
        if (previo.exists) {
            if (previo.get("actorId") !== usuarioId || previo.get("accion") !== accion) {
                (0, mantenimiento_ordenes_1.errorMantenimiento)("already-exists", "El movimiento ya existe.");
            }
            return { id: movimiento.id, tareaId: previo.get("tareaId") ?? "" };
        }
        const saldo = existenciasMantenimiento(d);
        if ((saldo[origen] ?? 0) < unidades)
            (0, mantenimiento_ordenes_1.errorMantenimiento)("failed-precondition", "La bodega ya no tiene esas unidades.");
        const ubicacion = async (centro) => {
            if (centro === temporal)
                return "Bodega temporal";
            const datos = (await tx.get(centroRef(centro))).data();
            if (datos?.empresaId !== empresaId)
                (0, mantenimiento_ordenes_1.errorMantenimiento)("failed-precondition", "La ubicación no pertenece a esta empresa.");
            return nombreCentro(datos);
        };
        const sede = traslado ? destino : origen;
        if (sede !== temporal && traslado && !centroActivo((await tx.get(centroRef(sede))).data())) {
            (0, mantenimiento_ordenes_1.errorMantenimiento)("invalid-argument", "El destino no está activo.");
        }
        const [origenNombre, destinoNombre, plan] = await Promise.all([
            ubicacion(origen), traslado ? ubicacion(destino) : "",
            sede !== temporal ? leerPlan(tx, sede) : null,
        ]);
        const minimo = plan?.get("cantidades")?.[d.familia] ?? 0;
        const obligatorio = plan?.get("validadoPor") && d.familia ? minimo > 0 : null;
        const archivos = traslado ? null : await adjuntos(tx, ["foto", "video"]);
        if (archivos && !archivos.datos.length)
            (0, mantenimiento_ordenes_1.errorMantenimiento)("invalid-argument", "Adjunta una foto o un video de la baja.");
        const tareaId = !traslado && obligatorio ? `reemplazo_${hash([empresaId, ref.id, movimiento.id])}` : "";
        const coordinadorId = tareaId ? (0, mantenimiento_ordenes_1.idMantenimiento)(plan?.get("coordinadorId"), "coordinador", false) : "";
        const [coordinador, permiso] = coordinadorId ?
            await tx.getAll(usuarios.doc(coordinadorId), permisos.doc(`${empresaId}_${coordinadorId}`)) : [];
        if (tareaId && (!coordinador?.exists || !esOperador(coordinador.data()) || permiso?.get("operador") !== true)) {
            (0, mantenimiento_ordenes_1.errorMantenimiento)("failed-precondition", "Actualiza el coordinador de Mantenimiento de esta sede antes de dar de baja.");
        }
        saldo[origen] -= unidades;
        if (saldo[origen] === 0)
            delete saldo[origen];
        if (traslado)
            saldo[destino] = (saldo[destino] ?? 0) + unidades;
        const sedes = Object.keys(saldo).filter((b) => b !== temporal);
        if (tareaId) {
            tx.create(db.collection("TBL_TAREAS").doc(tareaId), {
                empresaId, empresas: [empresaId], centroId: sede, centroCostoId: sede, centroCostoNombre: origenNombre,
                areaId: catalogo?.ids.values().next().value ?? `${empresaId}_mantenimiento`, areaNombre: "Mantenimiento",
                titulo: `Reemplazar ${String(d.nombre).slice(0, 95)}`,
                descripcion: `Baja de ${unidades} unidades de ${d.nombre} (${d.codigo}). ${observaciones}`.slice(0, 1200),
                estado: "pendiente", status: "pendiente", creador_id: usuarioId,
                asignado_uid: coordinadorId, asignado_nombre: nombrePersona(coordinador.data()),
                sourceModule: mantenimiento_ordenes_1.appIdMantenimiento, sourceType: "inventario", sourceEntityId: movimiento.id,
                source: { moduleId: mantenimiento_ordenes_1.appIdMantenimiento, type: "inventario", entityId: movimiento.id, equipoId: ref.id },
                fecha_creacion: ahora, createdAt: ahora,
            });
        }
        archivos?.vincular(movimiento.id);
        tx.update(ref, { inventario: true, existencias: saldo, centroDocId: sedes[0] ?? "", updatedAt: ahora });
        tx.create(movimiento, { empresaId, accion, origen, destino, origenNombre, destinoNombre, unidades,
            codigo: d.codigo, nombre: d.nombre, referencia: d.referencia ?? "", entrega, recibe, observaciones,
            obligatorio, archivos: archivos?.datos ?? [], tareaId, actorId: usuarioId, createdAt: ahora });
        return { id: movimiento.id, tareaId };
    });
});
