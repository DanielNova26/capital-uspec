// functions/src/carnet.ts
//
// Página pública del carnet: lo que se ve al escanear el QR.
//
// DECISIONES DE PRIVACIDAD — leer antes de agregar un campo
//
// Un QR impreso en un carnet se fotografía, se comparte y termina en manos de
// cualquiera. Por eso esta página expone lo MÍNIMO que un carnet ya muestra a
// simple vista: foto, nombre, cargo, empresa y si la persona está activa.
//
//  - NO lleva la cédula. Es un documento de identidad nacional y además es el
//    ID de la persona en varias colecciones: publicarla convierte el QR en una
//    llave. Por eso el enlace va con un TOKEN opaco y aleatorio, no con la
//    cédula, y el token se puede rotar si un carnet se pierde.
//  - NO lleva correo, teléfono, dirección, salario ni nada de la hoja de vida.
//  - Se sirve desde una Cloud Function y no desde la app web, para no tener
//    que abrir lectura pública sobre TBL_USUARIOS. Las reglas de Firestore no
//    se tocan: aquí se lee con credenciales de administrador y se entrega solo
//    lo que esta función decide.
//
// Si alguien necesita más datos, no es este el sitio: que entre a la app.

import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";

const REGION = "us-central1";

const db = () => admin.firestore();

const esc = (value: unknown): string =>
  String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");

/** Solo se aceptan http(s) para la foto: un `javascript:` en el src sería XSS. */
const fotoSegura = (raw: unknown): string => {
  const url = String(raw ?? "").trim();
  return /^https?:\/\//i.test(url) ? url : "";
};

const pagina = (cuerpo: string, status = 200) => `<!doctype html>
<html lang="es"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex,nofollow">
<title>Carnet</title>
<style>
  :root { color-scheme: light; }
  body { margin:0; min-height:100vh; display:flex; align-items:center;
         justify-content:center; background:#f1f5f9;
         font-family:Arial,Helvetica,sans-serif; color:#1e293b; padding:20px; }
  .card { background:#fff; border-radius:18px; padding:28px 26px 24px;
          box-shadow:0 10px 30px rgba(15,23,42,.12); text-align:center;
          max-width:340px; width:100%; }
  .foto { width:132px; height:132px; border-radius:50%; object-fit:cover;
          margin:0 auto 16px; display:block; border:4px solid #e2e8f0; }
  .sinfoto { width:132px; height:132px; border-radius:50%; margin:0 auto 16px;
             background:#e2e8f0; color:#94a3b8; font-size:46px; display:flex;
             align-items:center; justify-content:center; font-weight:700; }
  h1 { font-size:20px; margin:0 0 4px; line-height:1.25; }
  .cargo { font-size:14px; color:#475569; margin:0 0 2px; }
  .empresa { font-size:12px; color:#94a3b8; margin:0 0 16px; }
  .estado { display:inline-block; padding:6px 14px; border-radius:999px;
            font-size:12.5px; font-weight:700; letter-spacing:.3px; }
  .activo { background:#dcfce7; color:#166534; }
  .inactivo { background:#fee2e2; color:#991b1b; }
  .pie { margin-top:18px; font-size:10.5px; color:#94a3b8; line-height:1.5; }
</style></head>
<body><div class="card">${cuerpo}</div></body></html>`;

const noValido = (mensaje: string) =>
  pagina(
    `<div class="sinfoto">?</div>
     <h1>Carnet no válido</h1>
     <p class="cargo">${esc(mensaje)}</p>
     <p class="pie">Si el carnet es reciente, pide que lo generen de nuevo.</p>`,
    404
  );

/**
 * Página del carnet. Se llega por `.../carnet?t=<token>` o `.../carnet/<token>`.
 *
 * El token es aleatorio y no dice nada de la persona: sin él no se llega al
 * documento, y rotarlo invalida el carnet perdido sin tocar nada más.
 */
export const carnetPublico = functions
  .region(REGION)
  .https.onRequest(async (req: any, res: any) => {
    // Es una página pública de solo lectura; no hay estado que proteger.
    res.set("Cache-Control", "public, max-age=300");
    try {
      const desdeRuta = String(req.path ?? "").split("/").filter(Boolean).pop();
      const token = String(req.query?.t ?? desdeRuta ?? "").trim();

      // Un token corto sería adivinable a fuerza bruta.
      if (!/^[A-Za-z0-9_-]{20,64}$/.test(token)) {
        res.status(404).set("Content-Type", "text/html; charset=utf-8")
          .send(noValido("El enlace no es válido."));
        return;
      }

      const snap = await db()
        .collection("TBL_USUARIOS")
        .where("carnetToken", "==", token)
        .limit(1)
        .get();

      if (snap.empty) {
        res.status(404).set("Content-Type", "text/html; charset=utf-8")
          .send(noValido("Este carnet ya no está vigente."));
        return;
      }

      const data = snap.docs[0].data() ?? {};
      const nombre = String(
        data.nombreCompleto || data.nombre || data.nombres || ""
      ).trim();
      const apellidos = String(data.apellidos ?? "").trim();
      const completo =
        apellidos && !nombre.includes(apellidos)
          ? `${nombre} ${apellidos}`
          : nombre;

      const cargo = String(data.cargoNombre || data.cargo || "").trim();
      const foto = fotoSegura(data.fotoUrl);

      // El estado se resuelve AHORA, no cuando se imprimio el carnet. Guardar
      // un "activo" congelado haria que el carnet de alguien que ya se retiro
      // siguiera diciendo que sigue vinculado hasta que alguien lo regenere,
      // que es justo lo que un carnet no debe hacer.
      //
      // El retiro vive en el bloque de la empresa: el `estado` raiz solo
      // gobierna el login y no dice nada del vinculo laboral.
      const empresaId = String(data.carnetEmpresaId ?? "").trim();
      const detalle = (data.empresasDetalle ?? {})[empresaId] ?? {};
      const estadoLaboral = String(detalle.estadoLaboral ?? "")
        .trim()
        .toLowerCase();
      const activo = estadoLaboral === "" || estadoLaboral === "activo";

      let empresa = "";
      if (empresaId) {
        try {
          const emp = await db().collection("TBL_EMPRESAS").doc(empresaId).get();
          empresa = String(emp.data()?.nombre ?? "").trim();
        } catch (_) {
          empresa = "";
        }
      }

      const inicial = (completo.trim()[0] ?? "?").toUpperCase();
      res.status(200).set("Content-Type", "text/html; charset=utf-8").send(
        pagina(`
          ${
            foto
              ? `<img class="foto" src="${esc(foto)}" alt="">`
              : `<div class="sinfoto">${esc(inicial)}</div>`
          }
          <h1>${esc(completo || "Sin nombre")}</h1>
          ${cargo ? `<p class="cargo">${esc(cargo)}</p>` : ""}
          ${empresa ? `<p class="empresa">${esc(empresa)}</p>` : ""}
          <span class="estado ${activo ? "activo" : "inactivo"}">
            ${activo ? "Personal activo" : "Sin vínculo vigente"}
          </span>
          <p class="pie">Verificación de carnet.<br>
             Esta página no contiene datos de contacto ni documento.</p>
        `)
      );
    } catch (error) {
      functions.logger.error("carnetPublico", error);
      res.status(500).set("Content-Type", "text/html; charset=utf-8")
        .send(noValido("No se pudo verificar el carnet."));
    }
  });
