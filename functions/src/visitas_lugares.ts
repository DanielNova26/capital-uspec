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
// de Google Maps Platform del servidor: `VISITAS_GOOGLE_API_KEY` o, si no está,
// la misma del estudio de movilidad (`MOVILIDAD_GOOGLE_API_KEY` o la de la
// configuración de la empresa). Esa clave necesita "Places API (New)"
// habilitada.
//
// Solo Desarrollo y Gerencia: son quienes cargan el maestro de ubicaciones,
// igual que exigen las reglas de TBL_VISITAS_UBICACIONES.

import * as admin from "firebase-admin";
import * as functions from "firebase-functions/v1";
import {requireManager} from "./visitas_cleanup";

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

export interface LugarGoogle {
  placeId: string;
  nombre: string;
  direccion: string;
  lat: number;
  lng: number;
  ciudad: string;
  departamento: string;
  mapsUrl: string;
}

interface Componente {
  longText?: string;
  shortText?: string;
  types?: string[];
}

/**
 * Pasa la respuesta de Places (New) a lo que usa la app. Descarta los que no
 * traen coordenadas. La ciudad es la localidad y, si no hay, el municipio.
 * @param {unknown} body JSON de places:searchText.
 * @return {LugarGoogle[]} Lugares con nombre, dirección y coordenadas.
 */
export function lugaresDesdeRespuesta(body: unknown): LugarGoogle[] {
  const places = (body as {places?: unknown[]} | null)?.places;
  if (!Array.isArray(places)) return [];
  const out: LugarGoogle[] = [];
  for (const raw of places) {
    const p = raw as Record<string, unknown>;
    const loc = p.location as {latitude?: unknown; longitude?: unknown} | undefined;
    const lat = Number(loc?.latitude);
    const lng = Number(loc?.longitude);
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) continue;
    const comps = Array.isArray(p.addressComponents) ?
      (p.addressComponents as Componente[]) : [];
    const de = (tipo: string) =>
      (comps.find((c) => (c.types ?? []).includes(tipo))?.longText ?? "").trim();
    const nombre = ((p.displayName as {text?: unknown} | undefined)?.text ?? "")
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
 * La clave de Google del servidor: la propia de Visitas, la del estudio de
 * movilidad del backend o la guardada en la configuración de la empresa.
 * @param {string} empresaId Empresa activa.
 * @return {Promise<string>} La clave, o vacío si no hay ninguna.
 */
async function claveGoogle(empresaId: string): Promise<string> {
  const env = [
    process.env.VISITAS_GOOGLE_API_KEY,
    process.env.MOVILIDAD_GOOGLE_API_KEY,
  ].map((v) => (v ?? "").trim()).find((v) => v.length > 0);
  if (env) return env;
  try {
    const snap = await admin.firestore()
      .collection("TBL_RUTAS_MOV_CONFIG").doc(empresaId).get();
    const d = snap.data() ?? {};
    return String(d.apiKeyGoogle ?? d.apiKey ?? "").trim();
  } catch (_) {
    return "";
  }
}

export const visitasBuscarLugar = functions.region(REGION)
  .runWith({timeoutSeconds: 30, memory: "256MB"})
  .https.onCall(async (data, context) => {
    const {empresaId, developer} = await requireManager(data, context);
    if (!developer) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Las ubicaciones las cargan Desarrollo y Gerencia."
      );
    }
    const raw = (data ?? {}) as Record<string, unknown>;
    const texto = (raw.texto ?? "").toString().trim().slice(0, 120);
    if (texto.length < 3) {
      throw new functions.https.HttpsError(
        "invalid-argument", "Escribe al menos 3 letras para buscar."
      );
    }
    const clave = await claveGoogle(empresaId);
    if (!clave) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "No hay clave de Google Maps en el servidor. Configura " +
        "VISITAS_GOOGLE_API_KEY en las funciones (o la del estudio de movilidad)."
      );
    }
    const lat = Number(raw.lat);
    const lng = Number(raw.lng);
    const body: Record<string, unknown> = {
      textQuery: texto,
      languageCode: "es",
      regionCode: "CO",
      maxResultCount: 8,
    };
    // Cerca de donde ya hay establecimientos, si la app lo sabe.
    if (Number.isFinite(lat) && Number.isFinite(lng) &&
        Math.abs(lat) <= 90 && Math.abs(lng) <= 180 && (lat !== 0 || lng !== 0)) {
      body.locationBias = {
        circle: {center: {latitude: lat, longitude: lng}, radius: 50000},
      };
    }
    let res: Response;
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
    } catch (e) {
      throw new functions.https.HttpsError(
        "unavailable", `No se pudo consultar Google: ${(e as Error).message}`
      );
    }
    const json = await res.json().catch(() => ({}));
    if (!res.ok) {
      const msg = ((json as {error?: {message?: unknown}}).error?.message ?? "")
        .toString();
      console.warn("[visitasBuscarLugar]", res.status, msg);
      throw new functions.https.HttpsError(
        "failed-precondition",
        `Google rechazó la búsqueda (${res.status}). Revisa que la clave ` +
        `tenga habilitada "Places API (New)". ${msg}`.trim()
      );
    }
    return {lugares: lugaresDesdeRespuesta(json)};
  });
