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
exports.talentoCargarPersonal = void 0;
exports.puedeCargarPersonal = puedeCargarPersonal;
exports.procesarCargaPersonal = procesarCargaPersonal;
const admin = __importStar(require("firebase-admin"));
const functions = __importStar(require("firebase-functions/v1"));
const crypto_1 = require("crypto");
const acceso_1 = require("./acceso");
const apps_por_empresa_1 = require("./apps_por_empresa");
const LIMITE = 100;
const USUARIOS = "TBL_USUARIOS";
const ESTRUCTURA = "TBL_ESTRUCTURA_ORGANIZACIONAL";
const EMPLEADOS = "TBL_EMPLEADOS";
const CEDULAS = "TBL_CEDULAS";
const APP = "talentohumanodashboard";
const ESTADOS = ["ACTIVO", "INACTIVO"];
const CAMPOS = ["cedula", "tipo_documento", "nombres", "apellidos", "correo",
    "area", "cargo", "centroCostos", "jefe", "estado"];
function texto(v) {
    return typeof v === "string" || typeof v === "number" ? String(v).trim() : "";
}
function clave(v) {
    return texto(v).normalize("NFD").replace(/[\u0300-\u036f]/g, "")
        .toLowerCase().replace(/\s+/g, " ");
}
function primero(d, ...campos) {
    return campos.map((campo) => texto(d[campo])).find(Boolean) || "";
}
function habilitado(d) {
    return ![d.activo, d.enabled, d.estado].some((v) => v === false || ["no", "false", "inactivo", "0", "deshabilitado"].includes(clave(v)));
}
function error(code, mensaje) {
    throw new functions.https.HttpsError(code, mensaje);
}
function puedeCargarPersonal(u, empresaId, userId, rol) {
    if (!(0, acceso_1.empresasSeleccionables)(u).includes(empresaId))
        return false;
    const local = u.empresasDetalle?.[empresaId] || {};
    const global = clave(u.roleKey ?? u.role ?? u.rol);
    const roleId = clave(local.roleId ?? u.roleId);
    const localKey = clave(local.roleKey ?? local.role_key ?? local.roleId);
    if ([global, localKey].some((r) => ["desarrollador", "developer"].includes(r)) ||
        /_(developer|desarrollador)$/.test(roleId))
        return true;
    if (local.soloTalentoHumano === true ||
        (local.soloTalentoHumano == null && (0, apps_por_empresa_1.raizEsDeEmpresa)(u, empresaId) && u.soloTalentoHumano === true)) {
        return false;
    }
    const apps = (0, apps_por_empresa_1.appsDeEmpresa)(u, empresaId).map((v) => clave(v).replace(/[^a-z0-9]/g, ""));
    if (apps.some((v) => ["admin", "admindashboard", "administracion", "administraciondashboard"].includes(v)))
        return true;
    return apps.some((v) => [APP, "talentohumano", "talento"].includes(v)) &&
        (!rol || (rol.empresaId === empresaId && rol.userId === userId &&
            ["gestor", "administrador"].includes(clave(rol.rol))));
}
function opcionesUnicas(opciones) {
    const repetidas = new Map();
    for (const opcion of opciones) {
        const k = clave(opcion.etiqueta);
        repetidas.set(k, (repetidas.get(k) || 0) + 1);
    }
    return opciones.map((o) => repetidas.get(clave(o.etiqueta)) === 1 ? o :
        { ...o, etiqueta: `${o.etiqueta} (${o.id})` })
        .sort((a, b) => a.etiqueta.localeCompare(b.etiqueta, "es", { numeric: true }));
}
async function catalogos(db, tx, empresaId, incluirJefes) {
    const empresa = (col) => tx.get(db.collection(col).where("empresaId", "==", empresaId));
    const [areas, cargos, centros, tipos, primaria, secundaria] = await Promise.all([
        empresa("TBL_AREAS"), empresa("TBL_CARGOS"), empresa("TBL_CENTROS_COSTOS"),
        tx.get(db.collection("TBL_TIPO_DOCUMENTO")),
        incluirJefes ? empresa(USUARIOS) : null,
        incluirJefes ? tx.get(db.collection(USUARIOS).where("empresas", "array-contains", empresaId)) : null,
    ]);
    const desde = (snap, convertir) => opcionesUnicas(snap.docs.filter((doc) => habilitado(doc.data()))
        .map((doc) => convertir(doc.id, doc.data())).filter((o) => o.nombre));
    const area = desde(areas, (id, d) => {
        const nombre = primero(d, "nombre", "areaNombre", "area");
        return { id, nombre, etiqueta: nombre };
    });
    const cargo = desde(cargos, (id, d) => {
        const nombre = primero(d, "nombre", "cargoNombre", "descripcion");
        const areaId = texto(d.areaId);
        const areaNombre = area.find((o) => o.id === areaId)?.nombre || primero(d, "areaNombre", "area");
        return { id, nombre, areaId, areaNombre, etiqueta: [nombre, areaNombre].filter(Boolean).join(" — ") };
    });
    const centroCostos = desde(centros, (id, d) => {
        const codigo = primero(d, "codigo", "centroCodigo", "codigoZeus");
        const nombre = primero(d, "nombre", "centroCostos", "descripcion") || codigo;
        return { id, nombre, etiqueta: codigo && codigo !== nombre ? `${codigo} — ${nombre}` : nombre };
    });
    const tiposPorCodigo = new Map();
    for (const doc of tipos.docs) {
        const d = doc.data();
        if (!habilitado(d) || (d.empresaId && d.empresaId !== empresaId))
            continue;
        const id = texto(d.codigo) || doc.id;
        const nombre = primero(d, "descripcion", "nombre") || id;
        if (!tiposPorCodigo.has(clave(id)) || d.empresaId === empresaId) {
            tiposPorCodigo.set(clave(id), { id, nombre, etiqueta: nombre === id ? id : `${id} — ${nombre}` });
        }
    }
    const jefes = new Map();
    for (const doc of [...(primaria?.docs || []), ...(secundaria?.docs || [])]) {
        const d = doc.data();
        if (!(0, acceso_1.empresasSeleccionables)(d).includes(empresaId))
            continue;
        const id = primero(d, "cedula", "usuario") || doc.id;
        const nombre = primero(d, "nombreCompleto", "nombre") ||
            [texto(d.nombres), texto(d.apellidos)].filter(Boolean).join(" ");
        if (!nombre || !/^\d+$/.test(id))
            continue;
        const local = d.empresasDetalle?.[empresaId] || {};
        const cargo = primero(local, "cargoNombre", "cargo") ||
            ((0, apps_por_empresa_1.raizEsDeEmpresa)(d, empresaId) ? primero(d, "cargoNombre", "cargo") : "");
        jefes.set(id, { id, nombre, cargo, etiqueta: `${nombre} — ${id}` });
    }
    return {
        tipo_documento: opcionesUnicas([...tiposPorCodigo.values()]),
        area, cargo, centroCostos, jefe: opcionesUnicas([...jefes.values()]),
    };
}
function leerFilas(input) {
    if (!Array.isArray(input) || !input.length || input.length > LIMITE) {
        error("invalid-argument", `Adjunta un Excel con entre 1 y ${LIMITE} empleados.`);
    }
    return input.map((raw) => {
        if (!raw || !Number.isInteger(raw.fila) || raw.fila < 2 || raw.fila > 1048576 ||
            CAMPOS.some((campo) => raw[campo] != null &&
                (typeof raw[campo] !== "string" || raw[campo].length > 500))) {
            error("invalid-argument", "El archivo contiene una fila que no se puede procesar.");
        }
        return { ...Object.fromEntries(CAMPOS.map((c) => [c, texto(raw[c])])), fila: raw.fila };
    });
}
function refsPersona(db, empresaId, cedula) {
    return {
        usuario: db.collection(USUARIOS).doc(cedula),
        estructura: db.collection(ESTRUCTURA).doc(cedula),
        empleado: db.collection(EMPLEADOS).doc(`${empresaId}_${cedula}`),
        cedula: db.collection(CEDULAS).doc(cedula),
    };
}
async function documentosExistentes(db, tx, empresaId, ids) {
    if (ids.length === 0)
        return new Set();
    const refs = ids.flatMap((id) => Object.values(refsPersona(db, empresaId, id)));
    const documentos = new Set();
    const consultas = [];
    // Compatibilidad con fichas históricas cuyo id de documento no es la cédula.
    for (let i = 0; i < ids.length; i += 30) {
        for (const campo of ["cedula", "usuario", "username"]) {
            consultas.push({ campo, consulta: tx.get(db.collection(USUARIOS).where(campo, "in", ids.slice(i, i + 30))) });
        }
    }
    await Promise.all([
        tx.getAll(...refs).then((snaps) => {
            snaps.forEach((snap, index) => {
                if (snap.exists)
                    documentos.add(ids[Math.floor(index / 4)]);
            });
        }),
        ...consultas.map(async ({ campo, consulta }) => {
            for (const doc of (await consulta).docs)
                documentos.add(texto(doc.data()[campo]));
        }),
    ]);
    return documentos;
}
function elegir(opciones, valor) {
    const k = clave(valor);
    return opciones.find((o) => clave(o.etiqueta) === k);
}
async function procesarCargaPersonal(input, context) {
    const userId = texto(context.auth?.token.userDocId);
    if (!context.auth || context.auth.token.authVersion !== 2 || !userId || userId.includes("/") ||
        context.auth.uid !== `todo_${(0, crypto_1.createHash)("sha256").update(userId).digest("hex")}`) {
        error("unauthenticated", "Inicia sesión de nuevo para cargar personal.");
    }
    const empresaId = texto(input?.empresaId);
    if (!empresaId || empresaId.length > 160 || empresaId.includes("/") || /^__.*__$/.test(empresaId)) {
        error("invalid-argument", "Selecciona una empresa activa.");
    }
    const accion = input?.accion;
    if (!["catalogo", "validar", "importar"].includes(accion)) {
        error("invalid-argument", "Acción de carga inválida.");
    }
    const filas = accion === "catalogo" ? [] : leerFilas(input.filas);
    if (accion !== "catalogo" && input.empresaPlantilla !== empresaId) {
        error("invalid-argument", "Descarga la plantilla de la empresa activa y copia allí las filas.");
    }
    const db = admin.firestore();
    return db.runTransaction(async (tx) => {
        const [actor, rol, empresa, modulo] = await tx.getAll(db.collection(USUARIOS).doc(userId), db.collection("TBL_TALENTO_HUMANO_ROLES").doc(`${empresaId}_${userId}`), db.collection("TBL_EMPRESAS").doc(empresaId), db.collection("TBL_APPS").doc(`${empresaId}_${APP}`));
        if (!empresa.exists || !puedeCargarPersonal(actor.data() || {}, empresaId, userId, rol.data())) {
            error("permission-denied", "No tienes permiso para cargar personal en esta empresa.");
        }
        const moduloEmpresa = modulo.exists ? modulo.data() : (await tx.get(db.collection("TBL_APPS")
            .where("empresaId", "==", empresaId).where("appId", "==", APP).limit(1))).docs[0]?.data();
        if (moduloEmpresa?.enabled === false) {
            error("permission-denied", "Talento Humano está deshabilitado en esta empresa.");
        }
        const nombreEmpresa = primero(empresa.data() || {}, "nombre", "nombreEmpresa", "razonSocial") || empresaId;
        const [catalogo, existentes] = await Promise.all([
            catalogos(db, tx, empresaId, accion === "catalogo" || filas.some((f) => f.jefe)),
            documentosExistentes(db, tx, empresaId, [...new Set(filas.map((f) => f.cedula).filter(documentoValido))]),
        ]);
        if (accion === "catalogo") {
            return {
                empresaNombre: nombreEmpresa, limite: LIMITE, estado: ESTADOS,
                ...Object.fromEntries(Object.entries(catalogo).map(([k, v]) => [k, v.map((o) => o.etiqueta)])),
            };
        }
        const errores = [];
        const vistas = [];
        const vistos = new Set();
        const altas = [];
        for (const f of filas) {
            const problemas = [];
            if (!documentoValido(f.cedula))
                problemas.push("Documento: escribe entre 1 y 30 dígitos.");
            if (vistos.has(f.cedula))
                problemas.push("Documento repetido en el archivo.");
            vistos.add(f.cedula);
            if (existentes.has(f.cedula))
                problemas.push("Documento ya registrado. Las altas existentes se gestionan desde el directorio o Multiempresa.");
            if (!f.nombres || !f.apellidos)
                problemas.push("Completa nombres y apellidos.");
            if (f.correo && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(f.correo))
                problemas.push("Correo inválido.");
            const tipo = elegir(catalogo.tipo_documento, f.tipo_documento);
            const area = elegir(catalogo.area, f.area);
            const cargo = elegir(catalogo.cargo, f.cargo);
            const centro = elegir(catalogo.centroCostos, f.centroCostos);
            const jefe = elegir(catalogo.jefe, f.jefe);
            const estado = (f.estado || "ACTIVO").toUpperCase();
            if (!tipo)
                problemas.push("Elige un tipo de documento de la lista.");
            if (f.area && !area)
                problemas.push("Área no disponible en la empresa.");
            if (f.cargo && !cargo)
                problemas.push("Cargo no disponible en la empresa.");
            if (f.centroCostos && !centro)
                problemas.push("Centro de costos no disponible en la empresa.");
            if (f.jefe && !jefe)
                problemas.push("Jefe directo no disponible en la empresa.");
            if (!ESTADOS.includes(estado))
                problemas.push("Elige un estado de la lista.");
            if (area && cargo && (cargo.areaId ? cargo.areaId !== area.id :
                cargo.areaNombre && clave(cargo.areaNombre) !== clave(area.nombre))) {
                problemas.push("El cargo pertenece a otra área.");
            }
            if (problemas.length || !tipo) {
                errores.push({ fila: f.fila, mensaje: problemas.join(" ") });
                continue;
            }
            const nombre = `${f.nombres} ${f.apellidos}`;
            const scoped = {
                empresaId, empresaNombre: nombreEmpresa, correo: f.correo,
                area: area?.nombre || cargo?.areaNombre || "", areaNombre: area?.nombre || cargo?.areaNombre || "",
                areaId: area?.id || catalogo.area.find((o) => o.id === cargo?.areaId)?.id || "",
                cargo: cargo?.nombre || "", cargoNombre: cargo?.nombre || "", cargoId: cargo?.id || "",
                centroId: centro?.id || "", centroCostos: centro?.nombre || "",
                jefeId: jefe?.id || "", jefeNombre: jefe?.nombre || "", cargoJefe: jefe?.cargo || "",
                estadoLaboral: estado.toLowerCase(),
            };
            vistas.push({ fila: f.fila, cedula: f.cedula, nombre, area: scoped.area, cargo: scoped.cargo });
            altas.push({ f, tipo: tipo.id, scoped, nombre });
        }
        if (accion === "validar" || errores.length)
            return { errores, vistas, creados: 0 };
        const fecha = admin.firestore.FieldValue.serverTimestamp();
        for (const { f, tipo, scoped, nombre } of altas) {
            const refs = refsPersona(db, empresaId, f.cedula);
            const identidad = {
                cedula: f.cedula, tipo_documento: tipo, tipoDocumento: tipo,
                nombres: f.nombres, apellidos: f.apellidos, nombreCompleto: nombre, nombre,
                createdAt: fecha, updatedAt: fecha, createdBy: userId,
            };
            const estado = scoped.estadoLaboral;
            const pertenencia = { empresas: [empresaId], empresasDetalle: { [empresaId]: scoped } };
            tx.create(refs.usuario, {
                ...identidad, ...scoped, ...pertenencia, usuario: f.cedula, estado: "activo",
                appsPorEmpresa: true, apps: [], role: "usuario",
            });
            tx.create(refs.estructura, { ...identidad, ...scoped, ...pertenencia, estado });
            tx.create(refs.empleado, { ...identidad, ...scoped, estado, apps: [] });
            tx.create(refs.cedula, {
                cedula: f.cedula, usuarioRef: refs.usuario, empresaId, empresas: [empresaId],
                createdAt: fecha, updatedAt: fecha,
            });
        }
        return { errores, vistas: [], creados: altas.length };
    }, accion === "importar" ? undefined : { readOnly: true });
}
function documentoValido(id) {
    return /^\d{1,30}$/.test(id);
}
exports.talentoCargarPersonal = functions.region("us-central1")
    .https.onCall(procesarCargaPersonal);
