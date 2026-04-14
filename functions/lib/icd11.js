"use strict";
// functions/src/icd11.ts
//
// Token broker + proxy seguro para la API ICD-11 de la OMS.
// Las credenciales viven en functions/.env (Firebase Functions env vars),
// nunca en el código ni en el cliente Flutter.
//
// Configuración:
//   Editar functions/.env (o functions/.env.local para emulación):
//     ICD11_CLIENT_ID=<tu_client_id>
//     ICD11_CLIENT_SECRET=<tu_client_secret>
//
// Obtener credenciales en: https://icdaccessmanagement.who.int/
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
exports.icd11Search = void 0;
const functions = __importStar(require("firebase-functions/v1")); // compat v1, coherente con index.ts
// ---------------------------------------------------------------------------
// Constantes OMS
// ---------------------------------------------------------------------------
const WHO_TOKEN_URL = "https://icdaccessmanagement.who.int/connect/token";
const WHO_SEARCH_URL = "https://id.who.int/icd/entity/search";
const WHO_RELEASE_FALLBACK = "2024-01";
// ---------------------------------------------------------------------------
// Caché de token en memoria de la función (válido ~1h por instancia)
// ---------------------------------------------------------------------------
let _cachedToken = null;
let _tokenExpiry = 0;
async function getIcd11Token() {
    // Reutilizar token si aún es válido (margen de 90s para evitar race)
    if (_cachedToken && Date.now() < _tokenExpiry - 90000) {
        console.log("[icd11] token: usando caché en memoria");
        return _cachedToken;
    }
    // Leer desde process.env — cargado automáticamente desde functions/.env
    const clientId = (process.env.ICD11_CLIENT_ID ?? "").trim();
    const clientSecret = (process.env.ICD11_CLIENT_SECRET ?? "").trim();
    if (!clientId || !clientSecret) {
        console.error("[icd11] token: credenciales NO encontradas en process.env. " +
            "Verificar que functions/.env contiene ICD11_CLIENT_ID y ICD11_CLIENT_SECRET.");
        throw new Error("ICD11_CREDENTIALS_MISSING");
    }
    console.log("[icd11] token: solicitando nuevo token a OMS...");
    const body = new URLSearchParams({
        grant_type: "client_credentials",
        client_id: clientId,
        client_secret: clientSecret,
        scope: "icdapi_access",
    });
    const resp = await fetch(WHO_TOKEN_URL, {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: body.toString(),
    });
    if (!resp.ok) {
        const text = await resp.text().catch(() => "");
        console.error(`[icd11] token: OMS respondió ${resp.status} —`, text.slice(0, 200));
        throw new Error(`ICD11_TOKEN_ERROR_${resp.status}`);
    }
    const json = await resp.json();
    _cachedToken = json.access_token;
    _tokenExpiry = Date.now() + (json.expires_in ?? 3600) * 1000;
    const expiresInMin = Math.round((json.expires_in ?? 3600) / 60);
    console.log(`[icd11] token: obtenido correctamente, expira en ~${expiresInMin}min`);
    return _cachedToken;
}
function extractTitle(title) {
    if (!title)
        return "";
    if (typeof title === "string")
        return title;
    return title["@value"] ?? "";
}
// ---------------------------------------------------------------------------
// Cloud Function exportada: icd11Search (onCall autenticado)
// ---------------------------------------------------------------------------
exports.icd11Search = functions
    .region("us-central1")
    .https.onCall(async (data, context) => {
    // Requiere usuario Firebase Auth autenticado
    if (!context.auth) {
        console.warn("[icd11Search] llamada sin autenticación — rechazando");
        throw new functions.https.HttpsError("unauthenticated", "Se requiere autenticación para buscar diagnósticos ICD-11");
    }
    const query = (data?.query ?? "").toString().trim();
    const language = (data?.language ?? "es").toString().trim() || "es";
    const uid = context.auth.uid;
    console.log(`[icd11Search] uid=${uid} query="${query}" lang=${language}`);
    if (query.length < 2) {
        console.log("[icd11Search] query muy corto, retornando vacío");
        return { results: [] };
    }
    try {
        // 1. Obtener token (caché o nuevo)
        const token = await getIcd11Token();
        // 2. Construir URL de búsqueda
        const url = new URL(WHO_SEARCH_URL);
        url.searchParams.set("q", query);
        url.searchParams.set("language", language);
        url.searchParams.set("flatResults", "true");
        url.searchParams.set("highlightingEnabled", "false");
        url.searchParams.set("medicalCodingMode", "true");
        url.searchParams.set("useFlexisearch", "true");
        console.log(`[icd11Search] llamando OMS: ${url.toString()}`);
        // 3. Llamar a la API de la OMS
        const resp = await fetch(url.toString(), {
            headers: {
                "Authorization": `Bearer ${token}`,
                "Accept": "application/json",
                "Accept-Language": language,
                "API-Version": "v2",
            },
        });
        console.log(`[icd11Search] OMS respondió: HTTP ${resp.status}`);
        if (!resp.ok) {
            if (resp.status === 401) {
                // Token expirado en producción: invalidar caché para próxima llamada
                console.warn("[icd11Search] 401 — invalidando token en caché");
                _cachedToken = null;
            }
            const errBody = await resp.text().catch(() => "");
            console.error(`[icd11Search] OMS error ${resp.status}:`, errBody.slice(0, 300));
            throw new Error(`ICD11_API_ERROR_${resp.status}`);
        }
        // 4. Parsear y normalizar resultados
        const json = await resp.json();
        const release = (json.releaseId ?? WHO_RELEASE_FALLBACK).toString();
        const entities = json.destinationEntities ?? [];
        const results = entities
            .slice(0, 20)
            .map((e) => ({
            icdCode: (e.theCode ?? "").toString(),
            icdTitle: extractTitle(e.title),
            icdUri: (e.id ?? "").toString(),
            source: "who_icd11",
            language,
            icdRelease: release,
        }))
            .filter((r) => r.icdCode.length > 0 && r.icdTitle.length > 0);
        console.log(`[icd11Search] OK — entidades totales: ${entities.length}, ` +
            `filtrados+mapeados: ${results.length}, release: ${release}`);
        return { results };
    }
    catch (e) {
        const msg = e instanceof Error ? e.message : String(e);
        console.error("[icd11Search] ERROR — activando fallback cliente:", msg);
        // Retornar fallback:true con el error real para que el cliente Flutter
        // pueda loguear la causa exacta y active el catálogo local.
        // No lanzar HttpsError para no romper la UX.
        return { results: [], fallback: true, errorDetail: msg };
    }
});
