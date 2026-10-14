import {PDFDocument, StandardFonts, rgb} from "pdf-lib";
import {DatosPlan} from "./interventoria_planes_policy";

// Una ficha por hallazgo; el exportador agrega después sus anexos originales.
export async function fichaPlanPdf(empresa: string, plan: DatosPlan, item: DatosPlan,
  expediente: boolean, corte: string, revisiones: string, historial: string, etapa = "todo"): Promise<PDFDocument> {
  const pdf = await PDFDocument.create();
  const regular = await pdf.embedFont(StandardFonts.Helvetica);
  const bold = await pdf.embedFont(StandardFonts.HelveticaBold);
  const ink = rgb(.08, .21, .29); const teal = rgb(.03, .42, .44); const red = rgb(.60, .18, .18);
  const safe = (value: unknown) => [...String(value ?? "")].map((c) => {
    try {
      regular.encodeText(c); return c;
    } catch {
      return c === "\n" ? c : "?";
    }
  }).join("");
  let page = pdf.addPage([595.28, 841.89]); let y = 0;
  const lines = (value: unknown, size = 10, width = 499) => {
    const out: string[] = [];
    for (const paragraph of safe(value).split("\n")) {
      let line = "";
      for (const word of paragraph.split(/\s+/)) {
        const candidate = line ? `${line} ${word}` : word;
        if (regular.widthOfTextAtSize(candidate, size) <= width) {
          line = candidate; continue;
        }
        if (line) out.push(line);
        line = "";
        for (const c of word) {
          if (regular.widthOfTextAtSize(line + c, size) > width) {
            out.push(line); line = "";
          }
          line += c;
        }
      }
      out.push(line);
    }
    return out;
  };
  const header = () => {
    page.drawRectangle({x: 0, y: 746, width: 595.28, height: 96, color: ink});
    page.drawText(expediente ? "EXPEDIENTE DE RESPALDO" : "PLAN DE MEJORA", {x: 48, y: 813, size: 10, font: bold, color: rgb(.66, .92, .89)});
    const code = safe(plan.numero);
    const codeSize = Math.min(20, 499 / Math.max(1, bold.widthOfTextAtSize(code, 1)));
    page.drawText(code, {x: 48, y: 788, size: codeSize, font: bold, color: rgb(1, 1, 1)});
    page.drawText(lines(empresa, 10)[0], {x: 48, y: 767, size: 10, font: regular, color: rgb(1, 1, 1)});
    y = 721;
  };
  const space = (height: number) => {
    if (y - height < 54) {
      page = pdf.addPage([595.28, 841.89]); header();
    }
  };
  const text = (value: unknown, color = ink) => {
    for (const line of lines(value)) {
      space(15); page.drawText(line, {x: 48, y, size: 10, font: regular, color}); y -= 15;
    }
    y -= 5;
  };
  const section = (title: string, value: unknown, color = teal) => {
    space(60);
    page.drawRectangle({x: 42, y: y - 5, width: 511, height: 23, color: rgb(.94, .97, .98)});
    page.drawText(title, {x: 48, y: y + 2, size: 11, font: bold, color}); y -= 26;
    text(value, color === red ? red : ink);
  };
  header();
  pdf.setTitle(`${plan.numero} - Acta ${item.idVisitaK2} - Hallazgo ${item.numeral}`);
  text(`${item.establecimiento} | Acta ${item.idVisitaK2} | Fecha ${String(item.fechaActa || "").split("T")[0]}`);
  text(`Notificación ${plan.csc} | ${plan.fechaNotificacion}\nRespuesta máxima: ${plan.limiteRespuesta} | Soportes máximos: ${plan.limiteSoportes}`);
  if (expediente) text(`Corte: ${corte}. Incluye pendientes; no acredita por sí mismo aceptación en K2.`, red);
  section("01  DATOS DE LA TAREA Y SUBSANACIÓN", `Tarea ${item.numeroTarea || ""} | Estado: ${item.tareaEstado || ""}\nResponsable: ${item.responsableNombre || ""}\nAprueba: ${item.aprobadorNombre || ""}\nPlazo de subsanación: ${String(item.limiteSubsanacion || "Sin fecha").split("T")[0]}`);
  section(`02  NUMERAL ${item.numeral}`, item.descripcion);
  section("OBSERVACIÓN DE INTERVENTORÍA", item.observacionInterventoria || "Sin observación registrada.", red);
  if (etapa !== "soportes") section("03  COMPROMISO", `${item.compromiso || "Pendiente"}\nEjecución: ${item.fechaEjecucion || "Pendiente"} | Seguimiento: ${item.fechaSeguimiento || "Pendiente"}`);
  if (etapa !== "respuesta") {
    if (item.respuestaTarea) section("04  RESPUESTA INCORPORADA DE LA TAREA", item.respuestaTarea);
    if (item.respuestaCalidad) section("RESPUESTA DE CALIDAD", item.respuestaCalidad);
    section("RESPUESTA PARA K2", item.respuestaSoportes || "Pendiente de entrega");
  }
  section("05  REVISIÓN Y PRESENTACIÓN", revisiones);
  if (etapa !== "respuesta") {
    section("06  SOPORTES ANEXOS", (item.evidencias || []).map((e: DatosPlan, n: number) =>
      `${n + 1}. ${e.nombre}\nOrigen: ${e.fuenteOrigen || "Adjuntado al plan"}`).join("\n") || "Sin soportes adjuntos.");
  }
  if (historial) section("07  TRAZABILIDAD", historial);
  const pages = pdf.getPages();
  pages.forEach((p, n) => {
    p.drawLine({start: {x: 48, y: 38}, end: {x: 547, y: 38}, thickness: .5, color: teal});
    const footer = safe(`${plan.numero} | Ficha ${n + 1} de ${pages.length}${etapa === "respuesta" ? "" : " | Anexos a continuación"}`);
    const size = Math.min(8, 499 / Math.max(1, regular.widthOfTextAtSize(footer, 1)));
    p.drawText(footer, {x: 48, y: 23, size, font: regular, color: ink});
  });
  return pdf;
}
