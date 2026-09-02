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
exports.dianBuzonProgramado = exports.dianBuzonDesconectar = exports.dianBuzonSincronizar = exports.dianBuzonConectar = exports.dianBuzonEstado = exports.DIAN_ASUNTO_OFICIAL = exports.DIAN_REMITENTE_OFICIAL = void 0;
exports.extraerDireccion = extraerDireccion;
exports.esCorreoTokenDian = esCorreoTokenDian;
exports.extraerEnlaceDian = extraerEnlaceDian;
exports.buzonSigueConfigurado = buzonSigueConfigurado;
exports.estadoBuzonPublico = estadoBuzonPublico;
exports.errorLegible = errorLegible;
exports.sincronizarBuzonDian = sincronizarBuzonDian;
/**
 * Conector de buzón exclusivo del módulo Tokens DIAN (Yahoo / IMAP).
 *
 * Este módulo es independiente del módulo Correo: no escribe en
 * TBL_CORREO_CUENTAS ni en TBL_CORREO_MENSAJES, no evalúa reglas y no dispara
 * alertas de WhatsApp. Solo baja del buzón los correos que cumplen el filtro
 * oficial DIAN y los entrega al flujo cifrado de dian_tokens.ts.
 *
 * El filtro se aplica dos veces: primero como SEARCH en el servidor IMAP (para
 * que Yahoo ni siquiera envíe el resto de la bandeja) y después en memoria
 * antes de guardar nada. Cualquier otro mensaje se descarta sin almacenarse.
 */
const admin = __importStar(require("firebase-admin"));
const functions = __importStar(require("firebase-functions/v1"));
const imapflow_1 = require("imapflow");
const mailparser_1 = require("mailparser");
const dian_tokens_1 = require("./dian_tokens");
const REGION = "us-central1";
const CONFIG_COLLECTION = "TBL_DIAN_TOKEN_CONFIG";
/** Único remitente aceptado. Cualquier otro correo se ignora. */
exports.DIAN_REMITENTE_OFICIAL = "facturacionelectronica@dian.gov.co";
/** Asunto aceptado como alternativa al remitente oficial. */
exports.DIAN_ASUNTO_OFICIAL = "Token Acceso DIAN";
const YAHOO_HOST = "imap.mail.yahoo.com";
const YAHOO_PORT = 993;
const MAX_MENSAJES_POR_CORRIDA = 40;
const VENTANA_INICIAL_DIAS = 3;
// Yahoo bloquea la cuenta si recibe muchas sesiones IMAP a la vez, y la tabla
// la miran varias personas: el candado evita que dos lecturas se solapen.
const LOCK_VIGENCIA_MS = 2 * 60 * 1000;
function db() {
    return admin.firestore();
}
function texto(value) {
    return value === null || value === undefined ? "" : String(value).trim();
}
function normalizar(value) {
    return texto(value)
        .toLocaleLowerCase("es")
        .normalize("NFD")
        .replace(/[\u0300-\u036f]/g, "")
        .replace(/\s+/g, " ")
        .trim();
}
/**
 * Extrae la dirección de un encabezado From, que puede venir como
 * `DIAN <facturacionelectronica@dian.gov.co>` o como dirección suelta.
 * @param {unknown} remitente Valor crudo del encabezado.
 * @return {string} Dirección en minúsculas o cadena vacía.
 */
function extraerDireccion(remitente) {
    const raw = texto(remitente).toLowerCase();
    const entreAngulos = raw.match(/<([^<>]+@[^<>]+)>/);
    const candidato = entreAngulos ? entreAngulos[1] : raw;
    const suelta = candidato.match(/[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}/);
    return suelta ? suelta[0] : "";
}
/**
 * Compuerta única del módulo: decide si un correo del buzón pertenece al
 * flujo de Tokens DIAN. Solo pasa si viene del remitente oficial o si el
 * asunto es el oficial. Nada más se lee ni se guarda.
 * @param {unknown} remitente Encabezado From del mensaje.
 * @param {unknown} asunto Encabezado Subject del mensaje.
 * @return {{aceptado: boolean, motivo: string}} Resultado y causa.
 */
function esCorreoTokenDian(remitente, asunto) {
    if (extraerDireccion(remitente) === exports.DIAN_REMITENTE_OFICIAL) {
        return { aceptado: true, motivo: "remitente" };
    }
    if (normalizar(asunto).includes(normalizar(exports.DIAN_ASUNTO_OFICIAL))) {
        return { aceptado: true, motivo: "asunto" };
    }
    return { aceptado: false, motivo: "descartado" };
}
const ENLACE_DIAN = new RegExp("https?://catalogo-vpfe\\.dian\\.gov\\.co/User/AuthToken\\?[^\\s\"'<>)\\]]+", "gi");
/**
 * Busca el enlace oficial dentro del cuerpo del correo. El HTML de la DIAN
 * llega con entidades (&amp;) que romperían los parámetros del token.
 * @param {Array<string>} partes Cuerpos del mensaje (texto plano y HTML).
 * @return {string} Primer enlace encontrado o cadena vacía.
 */
function extraerEnlaceDian(...partes) {
    for (const parte of partes) {
        if (!parte)
            continue;
        const limpio = String(parte)
            .replace(/&amp;/gi, "&")
            .replace(/&#3[89];/g, "&");
        ENLACE_DIAN.lastIndex = 0;
        const encontrado = limpio.match(ENLACE_DIAN);
        if (encontrado?.length)
            return encontrado[0].replace(/[.,;]+$/, "");
    }
    return "";
}
function configRef(empresaId) {
    return db().collection(CONFIG_COLLECTION).doc(empresaId);
}
function buzonFromData(data) {
    const raw = data?.buzon;
    if (!raw || typeof raw !== "object")
        return null;
    const email = texto(raw.email);
    if (!email)
        return null;
    return {
        proveedor: texto(raw.proveedor) || "yahoo",
        email,
        host: texto(raw.host) || YAHOO_HOST,
        port: Number(raw.port) || YAHOO_PORT,
        estado: texto(raw.estado) || "sin_conectar",
        procesarHistoricos: raw.procesarHistoricos === true,
        appPasswordEncrypted: texto(raw.appPasswordEncrypted),
        ultimoUid: Number(raw.ultimoUid) || 0,
    };
}
async function cargarBuzon(empresaId) {
    const snap = await configRef(empresaId).get();
    return buzonFromData(snap.data());
}
async function guardarBuzon(empresaId, campos) {
    const payload = {};
    for (const [clave, valor] of Object.entries(campos)) {
        payload[`buzon.${clave}`] = valor;
    }
    payload.updatedAt = admin.firestore.FieldValue.serverTimestamp();
    await configRef(empresaId).set({ empresaId }, { merge: true });
    await configRef(empresaId).update(payload);
}
/**
 * Una credencial guardada sigue configurada aunque Yahoo haya fallado en la
 * última lectura. Solo la desconexión explícita elimina esa configuración.
 * @param {string} estado Último estado operativo.
 * @param {boolean} tieneCredencial Indica si existe el secreto cifrado.
 * @return {boolean} Si la cuenta debe mostrarse como configurada.
 */
function buzonSigueConfigurado(estado, tieneCredencial) {
    return tieneCredencial && estado !== "sin_conectar";
}
/**
 * Estado público del buzón. Nunca devuelve la contraseña ni su ciphertext.
 * @param {string} empresaId Empresa activa.
 * @return {Promise<Record<string, unknown>>} Datos visibles en la app.
 */
async function estadoBuzonPublico(empresaId) {
    const snap = await configRef(empresaId).get();
    const raw = (snap.data()?.buzon ?? {});
    const buzon = buzonFromData(snap.data());
    const revision = raw.ultimaRevisionAt;
    const conectado = raw.conectadoAt;
    const tieneCredencial = !!buzon?.appPasswordEncrypted;
    return {
        // Una caída temporal de Yahoo no borra la clave ni equivale a desconectar
        // el buzón. `estado` informa la salud; `conectado` informa si está configurado.
        conectado: buzonSigueConfigurado(buzon?.estado ?? "sin_conectar", tieneCredencial),
        configurado: tieneCredencial,
        operativo: tieneCredencial && buzon?.estado === "conectado",
        proveedor: buzon?.proveedor ?? "yahoo",
        email: buzon?.email ?? "",
        host: buzon?.host ?? YAHOO_HOST,
        estado: buzon?.estado ?? "sin_conectar",
        procesarHistoricos: buzon?.procesarHistoricos ?? false,
        ultimoError: texto(raw.ultimoError),
        ultimaRevisionAt: revision instanceof admin.firestore.Timestamp ? revision.toMillis() : null,
        conectadoAt: conectado instanceof admin.firestore.Timestamp ? conectado.toMillis() : null,
        totalRegistrados: Number(raw.totalRegistrados || 0),
        totalDescartados: Number(raw.totalDescartados || 0),
        remitenteFiltrado: exports.DIAN_REMITENTE_OFICIAL,
        asuntoFiltrado: exports.DIAN_ASUNTO_OFICIAL,
    };
}
function nuevoCliente(buzon, password) {
    return new imapflow_1.ImapFlow({
        host: buzon.host,
        port: buzon.port,
        secure: true,
        auth: { user: buzon.email, pass: password },
        logger: false,
        // Timeouts explícitos: si no, un rechazo lento de Yahoo se confunde con
        // un problema de red y el usuario espera sin saber por qué.
        connectionTimeout: 20000,
        greetingTimeout: 15000,
        socketTimeout: 60000,
        clientInfo: { name: "Capital USPEC · Tokens DIAN" },
    });
}
/**
 * Detalles del fallo IMAP para el log del servidor. No incluye la contraseña:
 * solo el código y el texto que devuelve Yahoo, que es lo que hace falta para
 * distinguir un rechazo de credenciales de un problema de red.
 * @param {unknown} error Error lanzado por ImapFlow.
 * @return {Record<string, unknown>} Campos seguros de registrar.
 */
function detalleError(error) {
    const e = error;
    return {
        message: texto(e?.message).slice(0, 300),
        code: texto(e?.code),
        errno: texto(e?.errno),
        authenticationFailed: e?.authenticationFailed === true,
        serverResponseCode: texto(e?.serverResponseCode),
        responseText: texto(e?.responseText).slice(0, 300),
        responseStatus: texto(e?.responseStatus),
        response: typeof e?.response === "string" ? texto(e.response).slice(0, 300) : "",
        reason: texto(e?.reason).slice(0, 300),
        hostname: texto(e?.hostname),
        syscall: texto(e?.syscall),
    };
}
function camposError(error) {
    const e = error;
    return [
        error instanceof Error ? error.message : String(error),
        e?.responseText,
        typeof e?.response === "string" ? e.response : "",
        e?.responseStatus,
        e?.serverResponseCode,
        e?.reason,
        e?.code,
    ]
        .map((value) => texto(value).replace(/[\r\n\t]+/g, " "))
        .filter((value, index, values) => value && values.indexOf(value) === index);
}
function esErrorCredenciales(error) {
    const e = error;
    return e?.authenticationFailed === true ||
        /AUTHENTICATIONFAILED|AUTHORIZATIONFAILED|Invalid credentials|LOGIN failed|Authentication failed/i
            .test(camposError(error).join(" · "));
}
/**
 * Convierte los errores técnicos de ImapFlow/Yahoo en una explicación útil.
 * ImapFlow usa `Command failed` como mensaje principal para cualquier NO/BAD,
 * pero conserva el motivo verdadero en responseText/response/serverResponseCode.
 * @param {unknown} error Error recibido desde el cliente IMAP.
 * @return {string} Mensaje seguro para mostrar en la aplicación.
 */
function errorLegible(error) {
    const campos = camposError(error);
    const detalleCompleto = campos.join(" · ");
    const e = error;
    if (esErrorCredenciales(error)) {
        return "Yahoo rechazó la clave. Casi siempre es porque se usó la " +
            "contraseña normal del correo: Yahoo bloquea IMAP con esa y solo acepta " +
            "una contraseña de aplicación. Genérala en Yahoo > Información de la " +
            "cuenta > Seguridad de la cuenta > Generar contraseña de aplicación.";
    }
    if (/Too many|rate.?limit|throttl|TRYLATER|temporar(?:y|ily) unavailable/i
        .test(detalleCompleto)) {
        return "Yahoo limitó temporalmente las conexiones IMAP. La clave guardada " +
            "no se perdió: espera unos minutos y vuelve a intentar; el detector " +
            "automático también reintentará la conexión.";
    }
    if (/ENOTFOUND|ECONNREFUSED/i.test(detalleCompleto)) {
        return "No se pudo alcanzar imap.mail.yahoo.com. Revisa el nombre del " +
            "servidor y que el proyecto tenga salida a internet.";
    }
    if (/ETIMEDOUT|ECONNRESET|Unexpected close|ClosedAfterConnect|timeout|Socket/i
        .test(detalleCompleto)) {
        return "Yahoo cerró o no respondió a tiempo. La clave guardada no se " +
            "eliminó; el detector volverá a intentarlo automáticamente.";
    }
    const respuestaYahoo = texto(e?.responseText) ||
        (typeof e?.response === "string" ? texto(e.response) : "");
    if (/Command failed/i.test(detalleCompleto)) {
        if (respuestaYahoo && !/^Command failed$/i.test(respuestaYahoo)) {
            return `Yahoo rechazó una operación IMAP: ${respuestaYahoo.slice(0, 180)}.`;
        }
        return "Yahoo rechazó una operación IMAP sin indicar el motivo. Esto no " +
            "significa que el servidor de Capital esté apagado. La clave guardada " +
            "no se eliminó; espera unos minutos y vuelve a intentar.";
    }
    return campos[0]?.slice(0, 240) || "Yahoo cerró la conexión sin explicar el motivo.";
}
/**
 * Toma el candado de lectura de la empresa. Devuelve false si otra corrida
 * (manual o del cron) sigue viva.
 * @param {string} empresaId Empresa dueña del buzón.
 * @return {Promise<boolean>} true si esta corrida puede continuar.
 */
async function tomarCandado(empresaId) {
    const ref = configRef(empresaId);
    return db().runTransaction(async (transaction) => {
        const snap = await transaction.get(ref);
        const raw = (snap.data()?.buzon ?? {});
        const desde = raw.sincronizandoDesde;
        if (desde instanceof admin.firestore.Timestamp &&
            Date.now() - desde.toMillis() < LOCK_VIGENCIA_MS) {
            return false;
        }
        transaction.set(ref, { empresaId, buzon: { sincronizandoDesde: admin.firestore.Timestamp.now() } }, { merge: true });
        return true;
    });
}
async function soltarCandado(empresaId) {
    await configRef(empresaId)
        .update({ "buzon.sincronizandoDesde": admin.firestore.FieldValue.delete() })
        .catch(() => undefined);
}
/**
 * Verifica credenciales abriendo y cerrando la sesión IMAP.
 * @param {BuzonConfig} buzon Configuración del buzón.
 * @param {string} password Contraseña de aplicación en claro.
 * @return {Promise<void>} Resuelve si la conexión fue aceptada.
 */
async function probarConexion(buzon, password) {
    const client = nuevoCliente(buzon, password);
    try {
        await client.connect();
        const lock = await client.getMailboxLock("INBOX");
        lock.release();
    }
    finally {
        await client.logout().catch(() => undefined);
    }
}
/**
 * Descarga del buzón únicamente los correos que cumplen el filtro DIAN y los
 * entrega al registro cifrado. El resto de la bandeja nunca se descarga.
 * @param {string} empresaId Empresa dueña del buzón.
 * @return {Promise<ResumenSincronizacion>} Conteos de la corrida.
 */
async function sincronizarBuzonDian(empresaId) {
    const buzon = await cargarBuzon(empresaId);
    if (!buzon || !buzon.appPasswordEncrypted) {
        throw new functions.https.HttpsError("failed-precondition", "Todavía no hay un buzón conectado para esta empresa.");
    }
    if (!(await tomarCandado(empresaId))) {
        throw new functions.https.HttpsError("aborted", "Ya hay una lectura del buzón en curso. Espera unos segundos.");
    }
    const resumen = {
        revisados: 0,
        registrados: 0,
        duplicados: 0,
        descartados: 0,
        sinEnlace: 0,
    };
    const password = (0, dian_tokens_1.decrypt)(buzon.appPasswordEncrypted);
    const client = nuevoCliente(buzon, password);
    let mayorUid = buzon.ultimoUid;
    try {
        await client.connect();
        const lock = await client.getMailboxLock("INBOX");
        try {
            // El OR se resuelve en el servidor de Yahoo: solo viajan los correos
            // del remitente oficial o con el asunto oficial.
            const criterio = {
                or: [
                    { from: exports.DIAN_REMITENTE_OFICIAL },
                    { subject: exports.DIAN_ASUNTO_OFICIAL },
                ],
            };
            if (buzon.ultimoUid > 0) {
                criterio.uid = `${buzon.ultimoUid + 1}:*`;
            }
            else if (!buzon.procesarHistoricos) {
                criterio.since = new Date(Date.now() - VENTANA_INICIAL_DIAS * 24 * 60 * 60 * 1000);
            }
            const encontrados = await client.search(criterio, { uid: true });
            const uids = (Array.isArray(encontrados) ? encontrados : [])
                .filter((uid) => uid > buzon.ultimoUid)
                .sort((a, b) => a - b)
                .slice(0, MAX_MENSAJES_POR_CORRIDA);
            for (const uid of uids) {
                const mensaje = await client.fetchOne(String(uid), { uid: true, source: true, envelope: true, internalDate: true }, { uid: true });
                if (!mensaje || !mensaje.source)
                    continue;
                resumen.revisados += 1;
                mayorUid = Math.max(mayorUid, uid);
                const parsed = await (0, mailparser_1.simpleParser)(mensaje.source);
                const remitente = texto(parsed.from?.text) ||
                    texto(mensaje.envelope?.from?.[0]?.address);
                const asunto = texto(parsed.subject) || texto(mensaje.envelope?.subject);
                // Segunda compuerta: aunque el servidor haya devuelto algo distinto,
                // aquí no pasa nada que no sea un correo DIAN.
                if (!esCorreoTokenDian(remitente, asunto).aceptado) {
                    resumen.descartados += 1;
                    continue;
                }
                const url = extraerEnlaceDian(parsed.text, parsed.html, parsed.textAsHtml);
                if (!url) {
                    resumen.sinEnlace += 1;
                    continue;
                }
                try {
                    const registro = await (0, dian_tokens_1.registrarTokenDianDesdeCorreo)({
                        empresaId,
                        url,
                        recibidoAt: parsed.date ?? (mensaje.internalDate ? new Date(mensaje.internalDate) : new Date()),
                        remitente: extraerDireccion(remitente) || remitente,
                        asunto,
                        buzon: buzon.email,
                        proveedor: buzon.proveedor,
                        sourceMessageId: texto(parsed.messageId) || `uid_${uid}`,
                        registradoPor: "detector_yahoo",
                    });
                    if (registro.created)
                        resumen.registrados += 1;
                    else
                        resumen.duplicados += 1;
                }
                catch (error) {
                    // Un enlace que no supera la validación oficial no detiene la corrida.
                    console.warn(`[dian_mailbox] enlace rechazado empresa=${empresaId} uid=${uid}`, error);
                    resumen.descartados += 1;
                }
            }
        }
        finally {
            lock.release();
        }
        await guardarBuzon(empresaId, {
            estado: "conectado",
            ultimoUid: mayorUid,
            ultimaRevisionAt: admin.firestore.FieldValue.serverTimestamp(),
            ultimoError: "",
            totalRegistrados: admin.firestore.FieldValue.increment(resumen.registrados),
            totalDescartados: admin.firestore.FieldValue.increment(resumen.descartados),
        });
        return resumen;
    }
    catch (error) {
        if (error instanceof functions.https.HttpsError)
            throw error;
        console.error("[dian_mailbox] lectura fallida", JSON.stringify({
            empresaId,
            email: buzon.email,
            ...detalleError(error),
        }));
        const detalle = errorLegible(error);
        await guardarBuzon(empresaId, {
            // Una lectura fallida no desconecta el buzón ni saca la empresa de los
            // reintentos. Las credenciales ya fueron validadas al configurarlas.
            estado: "error",
            ultimoError: detalle,
            ultimaRevisionAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        throw new functions.https.HttpsError("unavailable", detalle);
    }
    finally {
        await client.logout().catch(() => undefined);
        await soltarCandado(empresaId);
    }
}
exports.dianBuzonEstado = functions
    .region(REGION)
    .https.onCall(async (data, context) => {
    const caller = await (0, dian_tokens_1.requireCaller)(data, context);
    return { ok: true, buzon: await estadoBuzonPublico(caller.empresaId) };
});
exports.dianBuzonConectar = functions
    .region(REGION)
    .runWith({ timeoutSeconds: 120 })
    .https.onCall(async (data, context) => {
    const caller = await (0, dian_tokens_1.requireCaller)(data, context, true);
    const email = texto(data?.email).toLowerCase();
    // Yahoo muestra la contraseña de aplicación en grupos de cuatro separados
    // por espacios, pero el servidor la espera sin ellos. Si se pega tal cual
    // como la muestra Yahoo, el login falla aunque la clave sea correcta.
    const password = texto(data?.appPassword).replace(/\s+/g, "");
    if (!email.includes("@") || email.includes(" ")) {
        throw new functions.https.HttpsError("invalid-argument", "Indica el correo completo del buzón que recibe los tokens.");
    }
    if (password.length < 8) {
        throw new functions.https.HttpsError("invalid-argument", "Pega la contraseña de aplicación generada en la cuenta Yahoo.");
    }
    const buzon = {
        proveedor: "yahoo",
        email,
        host: texto(data?.host) || YAHOO_HOST,
        port: Number(data?.port) || YAHOO_PORT,
        estado: "conectado",
        procesarHistoricos: data?.procesarHistoricos === true,
        appPasswordEncrypted: "",
        ultimoUid: 0,
    };
    const anterior = await cargarBuzon(caller.empresaId);
    if (!(await tomarCandado(caller.empresaId))) {
        throw new functions.https.HttpsError("aborted", "El buzón se está revisando en este momento. Espera unos segundos y vuelve a intentar.");
    }
    try {
        await probarConexion(buzon, password);
    }
    catch (error) {
        // Sin esto no hay forma de saber si Yahoo rechazó la clave o si nunca
        // se llegó al servidor: el HttpsError no queda en el log.
        console.error("[dian_mailbox] conexion rechazada", JSON.stringify({
            empresaId: caller.empresaId,
            email: buzon.email,
            host: buzon.host,
            port: buzon.port,
            largoClave: password.length,
            ...detalleError(error),
        }));
        const detalle = errorLegible(error);
        // Se guarda el motivo para que quede visible en el banner del módulo y
        // no solo en un aviso que desaparece.
        const camposFallo = {
            ultimoError: anterior?.appPasswordEncrypted ?
                `No se reemplazó la clave guardada. ${detalle}` : detalle,
            ultimaRevisionAt: admin.firestore.FieldValue.serverTimestamp(),
        };
        // Un intento fallido de cambiar la clave no debe mezclar el correo nuevo
        // con el ciphertext anterior ni destruir una configuración recuperable.
        if (!anterior?.appPasswordEncrypted) {
            Object.assign(camposFallo, {
                email: buzon.email,
                host: buzon.host,
                port: buzon.port,
                proveedor: buzon.proveedor,
                estado: esErrorCredenciales(error) ? "credenciales_invalidas" : "error",
            });
        }
        await guardarBuzon(caller.empresaId, camposFallo);
        throw new functions.https.HttpsError("failed-precondition", detalle);
    }
    finally {
        await soltarCandado(caller.empresaId);
    }
    await guardarBuzon(caller.empresaId, {
        proveedor: buzon.proveedor,
        email: buzon.email,
        host: buzon.host,
        port: buzon.port,
        estado: "conectado",
        procesarHistoricos: buzon.procesarHistoricos,
        appPasswordEncrypted: (0, dian_tokens_1.encrypt)(password),
        // Cambiar de buzón reinicia el recorrido de UIDs.
        ultimoUid: anterior?.email === buzon.email ? anterior.ultimoUid : 0,
        ultimoError: "",
        conectadoAt: admin.firestore.FieldValue.serverTimestamp(),
        conectadoPor: caller.userId,
        conectadoPorNombre: caller.name,
    });
    let resumen = null;
    try {
        resumen = await sincronizarBuzonDian(caller.empresaId);
        console.log("[dian_mailbox] primera lectura", JSON.stringify({
            empresaId: caller.empresaId,
            email: buzon.email,
            procesarHistoricos: buzon.procesarHistoricos,
            ...resumen,
        }));
    }
    catch (error) {
        console.warn(`[dian_mailbox] primera lectura falló empresa=${caller.empresaId}`, error);
    }
    return {
        ok: true,
        resumen,
        buzon: await estadoBuzonPublico(caller.empresaId),
    };
});
exports.dianBuzonSincronizar = functions
    .region(REGION)
    .runWith({ timeoutSeconds: 300, memory: "512MB" })
    .https.onCall(async (data, context) => {
    const caller = await (0, dian_tokens_1.requireCaller)(data, context);
    const resumen = await sincronizarBuzonDian(caller.empresaId);
    return { ok: true, resumen, buzon: await estadoBuzonPublico(caller.empresaId) };
});
exports.dianBuzonDesconectar = functions
    .region(REGION)
    .https.onCall(async (data, context) => {
    const caller = await (0, dian_tokens_1.requireCaller)(data, context, true);
    await guardarBuzon(caller.empresaId, {
        estado: "sin_conectar",
        appPasswordEncrypted: admin.firestore.FieldValue.delete(),
        ultimoError: "",
        desconectadoAt: admin.firestore.FieldValue.serverTimestamp(),
        desconectadoPor: caller.userId,
    });
    return { ok: true, buzon: await estadoBuzonPublico(caller.empresaId) };
});
exports.dianBuzonProgramado = functions
    .region(REGION)
    .runWith({ timeoutSeconds: 540, memory: "512MB" })
    .pubsub.schedule("every 5 minutes")
    .timeZone("America/Bogota")
    .onRun(async () => {
    const snap = await db()
        .collection(CONFIG_COLLECTION)
        // Los fallos conservan la clave y deben recuperarse solos. Se incluye el
        // estado legado credenciales_invalidas para reactivar configuraciones que
        // una única lectura IMAP dejó detenidas.
        .where("buzon.estado", "in", ["conectado", "error", "credenciales_invalidas"])
        .get();
    for (const doc of snap.docs) {
        try {
            const resumen = await sincronizarBuzonDian(doc.id);
            console.log("[dian_mailbox] corrida", JSON.stringify({ empresaId: doc.id, ...resumen }));
        }
        catch (error) {
            console.error(`[dian_mailbox] empresa=${doc.id} error`, error);
        }
    }
    return null;
});
