import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";
import { enviarWhatsAppAListado } from "./correo";
import {
  getWhatsAppPublicState,
  getWhatsAppRouteListId,
} from "./whatsapp";
import { loadCompanyNotificationBranding } from "./notification_branding";

const REGION = "us-central1";

function text(value: unknown): string {
  return (value ?? "").toString().trim();
}

function normalize(value: unknown): string {
  return text(value)
    .toLocaleLowerCase("es")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

async function resolveListadoId(
  empresaId: string,
  configuredId: string
): Promise<string> {
  if (configuredId) return configuredId;
  const lists = await admin
    .firestore()
    .collection("TBL_CORREO_LISTADOS")
    .where("empresaId", "==", empresaId)
    .get();
  const compatible = lists.docs.filter((doc) => {
    if (doc.get("activo") === false) return false;
    const modules = Array.isArray(doc.get("modulos"))
      ? doc.get("modulos").map(normalize).filter(Boolean)
      : [];
    return !modules.length || modules.includes("compras");
  });
  const selected = compatible.find((doc) => {
    const name = normalize(doc.get("nombre"));
    return name === "nuevos proveedores" ||
      name === "compras nuevos proveedores";
  });
  if (selected) return selected.id;

  // Si Administración dejó una sola lista activa para Compras, esa lista es
  // inequívoca y se puede usar sin exigir una segunda asignación del evento.
  return compatible.length === 1 ? compatible[0].id : "";
}

function comprasRoleRecipient(
  role: admin.firestore.QueryDocumentSnapshot
): string {
  return text(role.get("cedula")) ||
    text(role.get("userId")) ||
    text(role.get("uid"));
}

async function notifyInAppNewSupplier(input: {
  empresaId: string;
  proveedorId: string;
  razonSocial: string;
  nit: string;
  createdBy: string;
}): Promise<{ estado: string; enviados: number }> {
  const branding = await loadCompanyNotificationBranding(input.empresaId);
  const recipients = new Set<string>();
  if (input.createdBy) recipients.add(input.createdBy);

  const roles = await admin
    .firestore()
    .collection("TBL_COMPRAS_ROLES")
    .where("empresaId", "==", input.empresaId)
    .get();
  for (const role of roles.docs) {
    if (normalize(role.get("rol")) !== "calidad") continue;
    const recipient = comprasRoleRecipient(role);
    if (recipient) recipients.add(recipient);
  }

  if (!recipients.size) return { estado: "sin_destinatarios", enviados: 0 };

  const notificationId = `compras_nuevo_proveedor_${input.proveedorId}`;
  const title = `${branding.emoji} Nuevo proveedor registrado`;
  const description =
    `${input.razonSocial} (${input.nit}) fue registrado y su documentación ` +
    "está disponible para revisión.";

  await Promise.all(
    [...recipients].map(async (userId) => {
      const parent = admin
        .firestore()
        .collection("TBL_NOTIFICACIONES")
        .doc(userId);
      await parent.set(
        { updatedAt: admin.firestore.FieldValue.serverTimestamp() },
        { merge: true }
      );
      await parent.collection("notifications").doc(notificationId).set(
        {
          id: notificationId,
          title,
          description,
          type: "nuevo_proveedor",
          taskId: `proveedor:${input.proveedorId}`,
          module: "compras_bodega",
          empresaId: input.empresaId,
          fromId: input.createdBy,
          fromName: "Compras",
          proveedorId: input.proveedorId,
          empresaNombreCorto: branding.shortName,
          empresaEmoji: branding.emoji,
          empresaColor: branding.color,
          read: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    })
  );
  return { estado: "procesado", enviados: recipients.size };
}

/**
 * Notifica únicamente las altas manuales de proveedores.
 *
 * El listado se asigna desde Administración > WhatsApp. Se conserva el campo
 * legado de TBL_COMPRAS_CONFIG como respaldo durante la migración.
 */
export const comprasNotificarNuevoProveedorWhatsApp = functions
  .region(REGION)
  .firestore.document("TBL_COMPRAS_PROVEEDORES/{proveedorId}")
  .onCreate(async (snapshot, context) => {
    const data = snapshot.data();
    if (data.notificarWhatsAppNuevoProveedor !== true) return null;

    const empresaId = text(data.empresaId);
    const razonSocial = text(data.razonSocial) || "Sin razón social";
    const nit = text(data.nit) || "Sin NIT";
    const createdBy = text(data.creadoPor || data.createdBy);
    if (!empresaId) {
      await snapshot.ref.set(
        {
          notificarWhatsAppNuevoProveedor: false,
          whatsappNuevoProveedor: {
            estado: "omitido",
            error: "Proveedor sin empresaId.",
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
        },
        { merge: true }
      );
      return null;
    }

    let campana = { estado: "sin_destinatarios", enviados: 0 };
    try {
      campana = await notifyInAppNewSupplier({
        empresaId,
        proveedorId: context.params.proveedorId,
        razonSocial,
        nit,
        createdBy,
      });
    } catch (error) {
      console.error("COMPRAS_NEW_SUPPLIER_BELL_ERROR", {
        proveedorId: context.params.proveedorId,
        error: error instanceof Error ? error.message : text(error),
      });
      campana = { estado: "fallido", enviados: 0 };
    }

    const config = await admin
      .firestore()
      .collection("TBL_COMPRAS_CONFIG")
      .doc(empresaId)
      .get();
    const centralListId = await getWhatsAppRouteListId(
      empresaId,
      "compras_nuevo_proveedor"
    );
    const listadoId = await resolveListadoId(
      empresaId,
      centralListId || text(config.get("whatsappNuevoProveedorListadoId"))
    );
    if (!listadoId) {
      await snapshot.ref.set(
        {
          notificarWhatsAppNuevoProveedor: false,
          whatsappNuevoProveedor: {
            estado: "sin_configuracion",
            error:
              "Asigna una lista en Administración > WhatsApp para el evento de proveedor nuevo.",
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          notificacionCampanaNuevoProveedor: {
            ...campana,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
        },
        { merge: true }
      );
      return null;
    }

    const whatsAppState = await getWhatsAppPublicState(empresaId, "compras");
    if (!whatsAppState.enabled || !whatsAppState.moduleEnabled) {
      await snapshot.ref.set(
        {
          notificarWhatsAppNuevoProveedor: false,
          whatsappNuevoProveedor: {
            estado: "deshabilitado",
            error:
              "Los avisos de Compras están deshabilitados desde Administración > WhatsApp.",
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          notificacionCampanaNuevoProveedor: {
            ...campana,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
        },
        { merge: true }
      );
      return null;
    }

    const categorias = Array.isArray(data.categorias)
      ? data.categorias.map(text).filter(Boolean).join(", ")
      : "";
    const mensaje = [
      "📣 *Nuevo proveedor registrado*",
      `🏭 *Proveedor:* ${razonSocial}`,
      `🪪 *NIT:* ${nit}`,
      ifText("📦 *Categorías*", categorias),
      "🔎 Ingresa al módulo de Compras para consultar el expediente.",
    ]
      .filter(Boolean)
      .join("\n");

    try {
      const result = await enviarWhatsAppAListado({
        empresaId,
        listadoId,
        mensaje,
        dedupeKey: `compras_nuevo_proveedor_${context.params.proveedorId}`,
        moduleId: "compras",
        prioridad: "normal",
        metadata: {
          tipo: "nuevo_proveedor",
          proveedorId: context.params.proveedorId,
          razonSocial,
          nit,
          templateKey: "compras_nuevo_proveedor",
          templateVariables: {
            proveedor: razonSocial,
            nit,
            categorias: categorias || "Sin categorías registradas",
          },
        },
      });

      await snapshot.ref.set(
        {
          notificarWhatsAppNuevoProveedor: false,
          whatsappNuevoProveedor: {
            estado: result.failed > 0 && result.sent === 0
              ? "fallido"
              : "procesado",
            listadoId,
            enviados: result.sent,
            fallidos: result.failed,
            omitidos: result.skipped,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          notificacionCampanaNuevoProveedor: {
            ...campana,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
        },
        { merge: true }
      );
    } catch (error) {
      const message = error instanceof Error ? error.message : text(error);
      console.error("COMPRAS_NEW_SUPPLIER_WHATSAPP_ERROR", {
        proveedorId: context.params.proveedorId,
        error: message,
      });
      await snapshot.ref.set(
        {
          notificarWhatsAppNuevoProveedor: false,
          whatsappNuevoProveedor: {
            estado: "fallido",
            listadoId,
            error: message.slice(0, 300),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          notificacionCampanaNuevoProveedor: {
            ...campana,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
        },
        { merge: true }
      );
    }
    return null;
  });

function ifText(label: string, value: string): string {
  return value ? `${label}: ${value}` : "";
}
