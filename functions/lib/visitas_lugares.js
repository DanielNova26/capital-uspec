"use strict";
// functions/src/visitas_lugares.ts
//
// Búsqueda de lugares en Google para el maestro de ubicaciones de Visitas
// (28 sep 2026): "si yo busco Buen Pastor, que me muestre en Google Maps
// cuál sale, se selecciona y traiga los datos". El geocodificador del
// teléfono solo entiende direcciones y en web no corre; Google Places sí
// encuentra establecimientos por nombre.
//
// Se hace desde el backend para que funcione igual en web y en móvil y la
// clave no viaje en la app. Usa Places API (New), Text Search. La clave es la
// misma de Rutas (Estudio movilidad), en el mismo orden que usa Rutas: la de
// la empresa (Rutas > Estudio movilidad > Programación) y si no, la del
// backend (`MOVILIDAD_GOOGLE_API_KEY`). `VISITAS_GOOGLE_API_KEY` solo hace
// falta si se quiere una clave aparte para Visitas. Esa clave necesita
// "Places API (New)" habilitada, además de la Routes API que ya usa Rutas.
//
// Solo Desarrollo y Gerencia: son quienes cargan el maestro de ubicaciones,
// igual que exigen las reglas de TBL_VISITAS_UBICACIONES.
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
exports.visitasBuscarLugar = void 0;
exports.lugaresDesdeRespuesta = lugaresDesdeRespuesta;
exports.primeraClave = primeraClave;
const admin = __importStar(require("firebase-admin"));
const functions = __importStar(require("firebase-functions/v1"));
const visitas_cleanup_1 = require("./visitas_cleanup");
const REGION = "us-central1";
const PLACES_URL = "https://places.googleapis.com/v1/places:searchText";
const FIELD_MASK = [
    "places.id",
    "places.displayName",
    "places.formattedAddress",
    "places.location",
    "places.addressComponents",
    "places.googleMapsUri",
].join(",");
/**
 * Pasa la respuesta de Places (New) a lo que usa la app. Descarta los que no
 * traen coordenadas. La ciudad es la localidad y, si no hay, el municipio.
 * @param {unknown} body JSON de places:searchText.
 * @return {LugarGoogle[]} Lugares con nombre, dirección y coordenadas.
 */
function lugaresDesdeRespuesta(body) {
    const places = body?.places;
    if (!Array.isArray(places))
        return [];
    const out = [];
    for (const raw of places) {
        const p = raw;
        const loc = p.location;
        const lat = Number(loc?.latitude);
        const lng = Number(loc?.longitude);
        if (!Number.isFinite(lat) || !Number.isFinite(lng))
            continue;
        const comps = Array.isArray(p.addressComponents) ?
            p.addressComponents : [];
        const de = (tipo) => (comps.find((c) => (c.types ?? []).includes(tipo))?.longText ?? "").trim();
        const nombre = (p.displayName?.text ?? "")
            .toString().trim();
        out.push({
            placeId: (p.id ?? "").toString(),
            nombre,
            direccion: (p.formattedAddress ?? "").toString().trim(),
            lat,
            lng,
            ciudad: de("locality") || de("administrative_area_level_2"),
            departamento: de("administrative_area_level_1"),
            mapsUrl: (p.googleMapsUri ?? "").toString(),
        });
    }
    return out;
}
/**
 * La primera clave con contenido, en el orden en que se pasan.
 * @param {unknown[]} candidatas Claves posibles, de la que manda a la última.
 * @return {string} La clave, o vacío si no hay ninguna.
 */
function primeraClave(...candidatas) {
    for (const c of candidatas) {
        const v = typeof c === "string" ? c.trim() : "";
        if (v.length > 0)
            return v;
    }
    return "";
}
/**
 * La clave de Google del servidor, la misma de Rutas: una propia de Visitas
 * si se configuró, si no la de la empresa en el estudio de movilidad y por
 * último la del backend.
 * @param {string} empresaId Empresa activa.
 * @return {Promise<string>} La clave, o vacío si no hay ninguna.
 */
async function claveGoogle(empresaId) {
    let config = {};
    try {
        const snap = await admin.firestore()
            .collection("TBL_RUTAS_MOV_CONFIG").doc(empresaId).get();
        config = snap.data() ?? {};
    }
    catch (_) {
        // Sin la configuración de Rutas se sigue con la del backend.
    }
    // 'apiKey' es el nombre viejo de la clave de Google en Rutas.
    return primeraClave(process.env.VISITAS_GOOGLE_API_KEY, config.apiKeyGoogle, config.apiKey, process.env.MOVILIDAD_GOOGLE_API_KEY);
}
exports.visitasBuscarLugar = functions.region(REGION)
    .runWith({ timeoutSeconds: 30, memory: "256MB" })
    .https.onCall(async (data, context) => {
    const { empresaId, developer } = await (0, visitas_cleanup_1.requireManager)(data, context);
    if (!developer) {
        throw new functions.https.HttpsError("permission-denied", "Las ubicaciones las cargan Desarrollo y Gerencia.");
    }
    const raw = (data ?? {});
    const texto = (raw.texto ?? "").toString().trim().slice(0, 120);
    if (texto.length < 3) {
        throw new functions.https.HttpsError("invalid-argument", "Escribe al menos 3 letras para buscar.");
    }
    const clave = await claveGoogle(empresaId);
    if (!clave) {
        throw new functions.https.HttpsError("failed-precondition", "No hay clave de Google Maps. Se usa la misma de Rutas: guárdala en " +
            "Rutas > Estudio movilidad > Programación (o " +
            "MOVILIDAD_GOOGLE_API_KEY en las funciones).");
    }
    const lat = Number(raw.lat);
    const lng = Number(raw.lng);
    const body = {
        textQuery: texto,
        languageCode: "es",
        regionCode: "CO",
        maxResultCount: 8,
    };
    // Cerca de donde ya hay establecimientos, si la app lo sabe.
    if (Number.isFinite(lat) && Number.isFinite(lng) &&
        Math.abs(lat) <= 90 && Math.abs(lng) <= 180 && (lat !== 0 || lng !== 0)) {
        body.locationBias = {
            circle: { center: { latitude: lat, longitude: lng }, radius: 50000 },
        };
    }
    let res;
    try {
        res = await fetch(PLACES_URL, {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
                "X-Goog-Api-Key": clave,
                "X-Goog-FieldMask": FIELD_MASK,
            },
            body: JSON.stringify(body),
        });
    }
    catch (e) {
        throw new functions.https.HttpsError("unavailable", `No se pudo consultar Google: ${e.message}`);
    }
    const json = await res.json().catch(() => ({}));
    if (!res.ok) {
        const msg = (json.error?.message ?? "")
            .toString();
        console.warn("[visitasBuscarLugar]", res.status, msg);
        throw new functions.https.HttpsError("failed-precondition", `Google rechazó la búsqueda (${res.status}). La clave de Rutas ` +
            "necesita también \"Places API (New)\" habilitada en Google Cloud " +
            `(y en sus restricciones de API, si las tiene). ${msg}`.trim());
    }
    return { lugares: lugaresDesdeRespuesta(json) };
});
