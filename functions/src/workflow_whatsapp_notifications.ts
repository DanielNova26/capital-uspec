import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";
import { sendWhatsAppDirect, sendWhatsAppRoute } from "./whatsapp";

const REGION = "us-central1";

function text(value: unknown): string {
  return (value ?? "").toString().trim();
}

function firstText(...values: unknown[]): string {
  return values.map(text).find(Boolean) || "";
}

async function responsiblePhone(userId: string): Promise<string> {
  if (!userId) return "";
  let snapshot = await admin.firestore().collection("TBL_USUARIOS").doc(userId).get();
  if (!snapshot.exists) {
    const byCedula = await admin.firestore()
      .collection("TBL_USUARIOS")
      .where("cedula", "==", userId)
      .limit(1)
      .get();
    if (!byCedula.empty) snapshot = byCedula.docs[0];
  }
  const user = snapshot.data() || {};
  const hoja = user.hojaDeVida && typeof user.hojaDeVida === "object"
    ? user.hojaDeVida as Record<string, unknown>
    : {};
  return firstText(
    user.celular,
    user.telefono,
    user.numeroCelular,
    user.phone,
    hoja.celular,
    hoja.telefono
  );
}

async function once(eventId: string, work: () => Promise<void>) {
  const ref = admin.firestore().collection("TBL_WHATSAPP_EVENTOS").doc(eventId);
  const acquired = await admin.firestore().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (snap.exists) return false;
    tx.create(ref, {
      estado: "procesando",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return true;
  });
  if (!acquired) return;
  try {
    await work();
    await ref.set({
      estado: "terminado",
      completedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
  } catch (error) {
    await ref.delete().catch(() => undefined);
    throw error;
  }
}

export const ppWhatsAppCambioFirma = functions
  .region(REGION)
  .firestore.document("TBL_PP_PLANILLAS/{planillaId}")
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();
    const previous = text(before.estado);
    const current = text(after.estado);
    if (previous === current) return;
    const empresaId = text(after.empresaId);
    if (!empresaId) return;
    const nombre = text(after.nombrePlanillaDetectado || after.nombreArchivoOriginal) ||
      `Planilla ${context.params.planillaId}`;
    if (current === "en_revision_auditoria") {
      await once(`pp_tesoreria_${context.params.planillaId}_${current}`, async () => {
        await sendWhatsAppRoute({
          empresaId,
          routeId: "planillas_tesoreria_auditoria",
          mensaje: `💳 *Planilla firmada por Tesorería*\n📄 ${nombre}\n🔎 Está disponible para revisión de Auditoría.`,
          metadata: { type: "planillas_tesoreria_auditoria", planillaId: context.params.planillaId },
        });
      });
    }
    if (current === "aprobada_auditoria") {
      await once(`pp_auditoria_${context.params.planillaId}_${current}`, async () => {
        await sendWhatsAppRoute({
          empresaId,
          routeId: "planillas_auditoria_gerencia",
          mensaje: `✅ *Planilla firmada por Auditoría*\n📄 ${nombre}\n✍️ Está disponible para el proceso de Gerencia.`,
          metadata: { type: "planillas_auditoria_gerencia", planillaId: context.params.planillaId },
        });
      });
    }
  });

export const interventoriaWhatsAppNuevaActa = functions
  .region(REGION)
  .firestore.document("TBL_INTERVENTORIA_VISITAS/{visitaId}")
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();
    const previous = Array.isArray(before.imagenesActa) ? before.imagenesActa.length : 0;
    const current = Array.isArray(after.imagenesActa) ? after.imagenesActa.length : 0;
    if (current <= previous) return;
    const empresaId = text(after.empresaId);
    if (!empresaId) return;
    const centro = text(after.centroCostoNombre || after.centroCostoCodigo);
    const fecha = after.fechaVisita?.toDate instanceof Function
      ? after.fechaVisita.toDate().toLocaleDateString("es-CO")
      : "";
    await once(`interventoria_acta_${context.params.visitaId}_${current}`, async () => {
      await sendWhatsAppRoute({
        empresaId,
        routeId: "interventoria_nueva_acta",
        mensaje: [
          "📋 *Nueva acta de Interventoría cargada*",
          centro ? `📍 Centro de costo: ${centro}` : "",
          fecha ? `📅 Fecha de visita: ${fecha}` : "",
          "🔎 Ingresa al módulo de Interventoría para revisarla.",
        ].filter(Boolean).join("\n"),
        metadata: { type: "interventoria_nueva_acta", visitaId: context.params.visitaId },
      });
    });
  });

export const facturacionWhatsAppDocumentoRechazado = functions
  .region(REGION)
  .firestore.document("TBL_FAC_REVISIONES/{revisionId}")
  .onWrite(async (change, context) => {
    if (!change.after.exists) return;
    const before = change.before.exists ? change.before.data() || {} : {};
    const after = change.after.data() || {};
    const currentState = text(after.estado).toLowerCase();
    const previousState = text(before.estado).toLowerCase();
    const version = Number(after.version || 0);
    const previousVersion = Number(before.version || 0);
    if (currentState !== "rechazado") return;
    if (previousState === currentState && previousVersion === version) return;

    const empresaId = text(after.empresaId);
    const responsibleId = text(after.responsableId);
    if (!empresaId || !responsibleId) return;

    await once(
      `facturacion_rechazo_${context.params.revisionId}_${version}`,
      async () => {
        const revisionRef = change.after.ref;
        const phone = firstText(
          after.responsableTelefono,
          await responsiblePhone(responsibleId)
        );
        if (!phone) {
          await revisionRef.set({
            whatsappEstado: "sin_telefono",
            whatsappDetalle: "El responsable no tiene celular en Talento Humano.",
            whatsappActualizadoAt: admin.firestore.FieldValue.serverTimestamp(),
          }, { merge: true });
          return;
        }

        const deadline = after.fechaLimite?.toDate instanceof Function
          ? after.fechaLimite.toDate().toLocaleDateString("es-CO")
          : text(after.fechaLimite);
        try {
          const result = await sendWhatsAppDirect({
            empresaId,
            moduleId: "facturacion",
            telefono: phone,
            mensaje: [
              "⚠️ *Documento rechazado en Facturación*",
              `📍 Establecimiento: ${text(after.establecimientoNombre)}`,
              `📄 Documento: ${text(after.docTipo)}`,
              `🗓️ Periodo: ${text(after.mes)}`,
              `📝 Corrección requerida: ${text(after.motivo)}`,
              deadline ? `⏰ Fecha límite: ${deadline}` : "",
              "Ingresa a tu tarea en la aplicación y envíalo nuevamente a revisión.",
            ].filter(Boolean).join("\n"),
            metadata: {
              type: "facturacion_documento_rechazado",
              templateKey: "facturacion_documento_rechazado",
              revisionId: context.params.revisionId,
              responsableId: responsibleId,
              templateVariables: {
                establecimiento: text(after.establecimientoNombre),
                documento: text(after.docTipo),
                periodo: text(after.mes),
                motivo: text(after.motivo),
                fechaLimite: deadline,
              },
            },
          });
          await revisionRef.set({
            whatsappEstado: result.sent ? "enviado" : "omitido",
            whatsappDetalle: result.reason || "",
            whatsappActualizadoAt: admin.firestore.FieldValue.serverTimestamp(),
          }, { merge: true });
        } catch (error) {
          await revisionRef.set({
            whatsappEstado: "error_reintentable",
            whatsappDetalle: error instanceof Error ? error.message : String(error),
            whatsappActualizadoAt: admin.firestore.FieldValue.serverTimestamp(),
          }, { merge: true });
          throw error;
        }
      }
    );
  });
