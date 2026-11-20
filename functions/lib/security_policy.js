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
exports.sha256 = void 0;
exports.assertTrustedOrigin = assertTrustedOrigin;
exports.signedUserId = signedUserId;
exports.requireActiveUser = requireActiveUser;
exports.requireRutas = requireRutas;
exports.reserveRequest = reserveRequest;
exports.reservePublicAuth = reservePublicAuth;
exports.boundedText = boundedText;
const admin = __importStar(require("firebase-admin"));
const functions = __importStar(require("firebase-functions/v1"));
const crypto_1 = require("crypto");
const acceso_1 = require("./acceso");
const apps_por_empresa_1 = require("./apps_por_empresa");
const origins = new Set([
    "https://to-do-gestion.web.app", "https://to-do-gestion.firebaseapp.com",
    "https://integra360.web.app", "https://integra360.firebaseapp.com",
    "https://integra360-94704.web.app", "https://integra360-94704.firebaseapp.com",
]);
const sha256 = (value) => (0, crypto_1.createHash)("sha256").update(value).digest("hex");
exports.sha256 = sha256;
// Las llamadas autenticadas viajan con token en cabecera, no con cookies: el
// origen no es una barrera real y bloquearlo dejó sin ingreso a usuarios
// legítimos. Solo se registra (sin datos personales) los que no son conocidos.
function assertTrustedOrigin(context) {
    const origin = context.rawRequest?.get?.("origin");
    if (!origin || origins.has(origin))
        return;
    functions.logger.warn("security.origin_unknown", { origin: String(origin).slice(0, 120) });
}
function signedUserId(context) {
    assertTrustedOrigin(context);
    const id = context.auth?.token.userDocId;
    if (context.auth?.token.authVersion !== 2 || typeof id !== "string" ||
        !id || id.length > 512 || id.includes("/") || /^__.*__$/.test(id) ||
        context.auth.uid !== `todo_${(0, exports.sha256)(id)}`) {
        throw new functions.https.HttpsError("unauthenticated", "Se requiere una sesión segura.");
    }
    return id;
}
async function requireActiveUser(context) {
    const userDocId = signedUserId(context);
    const ref = admin.firestore().collection("TBL_USUARIOS").doc(userDocId);
    const snap = await ref.get();
    const user = snap.data() || {};
    if (!snap.exists || (0, acceso_1.motivoAccesoBloqueado)(user)) {
        throw new functions.https.HttpsError("permission-denied", "La cuenta no está habilitada.");
    }
    return { userDocId, ref, user };
}
async function requireRutas(context, empresaId, manage = false) {
    const caller = await requireActiveUser(context);
    if (!empresaId || empresaId.includes("/") || !(0, acceso_1.empresasSeleccionables)(caller.user).includes(empresaId)) {
        throw new functions.https.HttpsError("permission-denied", "Empresa no autorizada.");
    }
    // Global authority only comes from the root, never a module's role.
    const developer = caller.user.desarrollador === true || caller.user.developer === true ||
        [caller.user.roleKey, caller.user.roleId, caller.user.role, caller.user.rol]
            .some((r) => typeof r === "string" && /^(desarrollador|developer|superadmin|administrador_sistema|.*_(desarrollador|developer))$/.test(r));
    const assignment = await admin.firestore().collection("TBL_RUTAS_ROLES").doc(`${empresaId}_${caller.userDocId}`).get();
    const allowed = manage ? ["admin", "admin_calidad", "desarrollador", "developer"] :
        ["conductor", "calidad", "admin", "admin_calidad", "desarrollador", "developer"];
    if (!developer && (!(0, apps_por_empresa_1.appsDeEmpresa)(caller.user, empresaId).some((a) => ["rutasdashboard", "rutas"].includes(a)) ||
        !allowed.includes(String(assignment.data()?.rol || "")))) {
        throw new functions.https.HttpsError("permission-denied", "No tienes permiso en Rutas.");
    }
    return caller;
}
// Reserve BEFORE expensive work, atomically across instances. No raw IP,
// passwords, answers or tokens are written to counters or application logs.
async function reserveRequest(context, scope, limit, windowMs = 900000) {
    assertTrustedOrigin(context);
    const ref = admin.firestore().collection("TBL_AUTH_LOGIN_ATTEMPTS").doc((0, exports.sha256)(`rate:${scope}`));
    const accepted = await admin.firestore().runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        const now = Date.now();
        const data = snap.data() || {};
        const start = data.startedAt?.toMillis?.() || 0;
        const count = start > now - windowMs ? Number(data.count || 0) : 0;
        if (count >= limit)
            return false;
        tx.set(ref, { count: count + 1,
            startedAt: admin.firestore.Timestamp.fromMillis(count ? start : now),
            expiresAt: admin.firestore.Timestamp.fromMillis(now + windowMs),
            lastAttemptAt: admin.firestore.FieldValue.serverTimestamp() });
        return true;
    });
    if (!accepted) {
        functions.logger.warn("security.rate_limited", { scopeHash: (0, exports.sha256)(scope) });
        throw new functions.https.HttpsError("resource-exhausted", "Demasiados intentos. Intenta más tarde.");
    }
}
async function reservePublicAuth(context, account) {
    // Sin contador solo por IP: en una oficina con una sola salida a Internet todo
    // el personal compartiría un documento y los ingresos simultáneos se
    // abortarían por contención. El límite por cuenta y por par IP+cuenta basta.
    const ip = context.rawRequest?.ip || "unknown";
    await reserveRequest(context, `auth-account:${account.toLowerCase()}`, 30);
    await reserveRequest(context, `auth-pair:${ip}:${account.toLowerCase()}`, 15);
}
function boundedText(value, max, field) {
    if (typeof value !== "string" || value.length > max || value.includes("\u0000")) {
        throw new functions.https.HttpsError("invalid-argument", `Campo inválido: ${field}.`);
    }
    return value.trim();
}
