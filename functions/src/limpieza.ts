// Limpieza por módulo (29 sep 2026): Admin › Limpieza borra los datos de
// prueba de un módulo en la empresa activa, por fecha, con vista previa.
// Solo toca documentos con `empresaId` de esa empresa (o, en los contadores,
// con el id que empieza por ella): nunca otra empresa.
//
// Cada módulo separa sus registros (lo que se va llenando al usar el módulo)
// de sus maestros y configuración (productos, proveedores, formatos,
// rutas…): estos solo se borran si Admin lo pide aparte.
import * as admin from "firebase-admin";
import * as functions from "firebase-functions/v1";
import {requireAdmin} from "./security_admin";

export type Coleccion = {
  id: string;
  nombre: string;
  // Documentos con id `{empresa}_…` y sin campo empresaId.
  porPrefijoId?: boolean;
  // Tiene subcolecciones: se borra con todo lo que cuelga.
  recursivo?: boolean;
};

export type ModuloLimpieza = {
  id: string;
  nombre: string;
  registros: Coleccion[];
  maestros: Coleccion[];
  // Borra también las tareas que creó el módulo (y sus notificaciones).
  tareas: boolean;
};

export const MODULOS_LIMPIEZA: ModuloLimpieza[] = [
  {
    id: "tareas", nombre: "Tareas y notificaciones", tareas: true,
    registros: [], maestros: [],
  },
  {
    id: "interventoria", nombre: "Interventoría", tareas: true,
    registros: [
      {id: "TBL_INTERVENTORIA_VISITAS", nombre: "Actas de visita"},
      {id: "TBL_INTERVENTORIA_HALLAZGOS", nombre: "Hallazgos"},
      {id: "TBL_INTERVENTORIA_SOLICITUDES_ELIMINACION",
        nombre: "Solicitudes de eliminación"},
    ],
    maestros: [],
  },
  {
    id: "visitas", nombre: "Visitas", tareas: true,
    registros: [{id: "TBL_VISITAS", nombre: "Visitas"}],
    maestros: [
      {id: "TBL_VISITAS_FORMATOS", nombre: "Formatos"},
      {id: "TBL_VISITAS_GRUPOS", nombre: "Grupos de profesionales"},
      {id: "TBL_VISITAS_UBICACIONES", nombre: "Ubicaciones de establecimientos"},
    ],
  },
  {
    id: "facturacion", nombre: "Facturación", tareas: true,
    registros: [
      {id: "TBL_FAC_REVISIONES", nombre: "Revisiones"},
      {id: "TBL_FAC_OBSERVACIONES", nombre: "Observaciones"},
      {id: "TBL_FAC_AUTORIZACIONES", nombre: "Autorizaciones"},
    ],
    maestros: [
      {id: "TBL_FAC_OBLIGACIONES", nombre: "Obligaciones"},
      {id: "TBL_FAC_ESTABLECIMIENTOS", nombre: "Establecimientos"},
    ],
  },
  {
    id: "compras", nombre: "Compras", tareas: true,
    registros: [
      {id: "TBL_COMPRAS_RECEPCIONES", nombre: "Recepciones"},
      {id: "TBL_COMPRAS_APROBACIONES", nombre: "Aprobaciones"},
      {id: "TBL_COMPRAS_REQ_DOCUMENTOS", nombre: "Requerimientos de documentos"},
      {id: "TBL_COMPRAS_ABASTECIMIENTO", nombre: "Abastecimiento"},
      {id: "TBL_COMPRAS_ABASTECIMIENTO_REPORTES",
        nombre: "Reportes de abastecimiento"},
      {id: "TBL_COMPRAS_AUDITORIA_DOCUMENTOS", nombre: "Auditoría de documentos"},
    ],
    maestros: [
      {id: "TBL_COMPRAS_PRODUCTOS", nombre: "Productos"},
      {id: "TBL_COMPRAS_PROVEEDORES", nombre: "Proveedores"},
      {id: "TBL_COMPRAS_MARCAS", nombre: "Marcas"},
      {id: "TBL_COMPRAS_FICHAS_TECNICAS", nombre: "Fichas técnicas"},
      {id: "TBL_COMPRAS_BODEGAS", nombre: "Bodegas"},
      {id: "TBL_COMPRAS_GRUPOS", nombre: "Grupos"},
    ],
  },
  {
    id: "rutas", nombre: "Rutas", tareas: false,
    registros: [
      {id: "TBL_RUTAS_ASIGNACIONES", nombre: "Asignaciones"},
      {id: "TBL_RUTAS_EVIDENCIAS", nombre: "Evidencias de entrega"},
      {id: "TBL_RUTAS_RESUMEN_DIARIO", nombre: "Resumen diario"},
      {id: "TBL_RUTAS_MOV_RUNS", nombre: "Recorridos"},
      {id: "TBL_RUTAS_MOV_MEDICIONES", nombre: "Mediciones de recorrido"},
      {id: "TBL_RUTAS_UBICACIONES", nombre: "Ubicaciones en vivo"},
    ],
    maestros: [
      {id: "TBL_RUTAS", nombre: "Rutas"},
      {id: "TBL_RUTAS_ESTABLECIMIENTOS", nombre: "Establecimientos"},
      {id: "TBL_RUTAS_PLACAS", nombre: "Placas"},
      {id: "TBL_RUTAS_MOV_HORARIOS", nombre: "Horarios"},
    ],
  },
  {
    id: "nutricion", nombre: "Nutrición", tareas: false,
    registros: [
      {id: "TBL_PACIENTES", nombre: "Pacientes (con su historial)"},
      {id: "TBL_CITAS_NUTRICION", nombre: "Citas"},
      {id: "TBL_VALORACIONES_NUTRICION", nombre: "Valoraciones"},
      {id: "TBL_MEDICIONES_NUTRICION", nombre: "Mediciones"},
      {id: "TBL_ASIGNACIONES_DIETA", nombre: "Asignaciones de dieta"},
      {id: "TBL_CARNETS_NUTRICION", nombre: "Carnés"},
      {id: "TBL_DERIVACIONES_NUTRICION", nombre: "Derivaciones"},
      {id: "TBL_ALERTAS_NUTRICION", nombre: "Alertas"},
      {id: "TBL_EVIDENCIAS_NUTRICION", nombre: "Evidencias"},
      {id: "TBL_EVALUACIONES_DIAGNOSTICAS", nombre: "Evaluaciones diagnósticas"},
    ],
    maestros: [
      {id: "TBL_DIETAS", nombre: "Dietas"},
      {id: "TBL_MENUS", nombre: "Menús"},
      {id: "TBL_PLANTILLAS_MENUS", nombre: "Plantillas de menú"},
      {id: "TBL_INGREDIENTES", nombre: "Ingredientes"},
      {id: "TBL_PATOLOGIAS", nombre: "Patologías"},
      {id: "TBL_DIRECTORIO_NUTRICION", nombre: "Directorio"},
    ],
  },
  {
    id: "gestion_documental", nombre: "Correspondencia", tareas: true,
    registros: [
      {id: "TBL_GD_EXPEDIENTES", nombre: "Expedientes"},
      {id: "TBL_GD_EXPEDIENTES_EVENTOS", nombre: "Eventos de expediente"},
      {id: "TBL_GD_VINCULOS", nombre: "Vínculos"},
      {id: "TBL_GD_COLABORACION", nombre: "Colaboración"},
    ],
    maestros: [
      {id: "TBL_GD_TIPOS_DOCUMENTALES", nombre: "Tipos documentales"},
      {id: "TBL_GD_CONTADORES", nombre: "Consecutivos de radicado",
        porPrefijoId: true},
    ],
  },
  {
    id: "correo", nombre: "Correo", tareas: true,
    registros: [
      {id: "TBL_CORREO_MENSAJES", nombre: "Mensajes"},
      {id: "TBL_CORREO_EJECUCIONES", nombre: "Ejecuciones"},
      {id: "TBL_CORREO_ALERTAS", nombre: "Alertas"},
    ],
    maestros: [{id: "TBL_CORREO_REGLAS", nombre: "Reglas"}],
  },
  {
    id: "bibliotecadocumental", nombre: "Biblioteca documental", tareas: false,
    registros: [
      {id: "TBL_DOCUMENTOS", nombre: "Documentos"},
      {id: "TBL_DOCUMENTOS_FLUJO", nombre: "Flujo de aprobación"},
      {id: "TBL_DOCUMENTOS_VERSIONES", nombre: "Versiones"},
    ],
    maestros: [],
  },
  {
    id: "planillas_pago", nombre: "Planillas de pago", tareas: true,
    registros: [
      {id: "TBL_PP_PLANILLAS", nombre: "Planillas"},
      {id: "TBL_PP_LOTES", nombre: "Lotes"},
      {id: "TBL_PP_FLUJO", nombre: "Flujo de firmas"},
    ],
    maestros: [
      {id: "TBL_PAGOS_BENEFICIARIOS", nombre: "Beneficiarios"},
      {id: "TBL_PAGOS_BENEFICIARIOS_CUENTA", nombre: "Cuentas de beneficiarios"},
    ],
  },
  {
    id: "talento_humano", nombre: "Talento Humano", tareas: true,
    registros: [
      {id: "TBL_LLAMADOS_ATENCION", nombre: "Llamados de atención"},
      {id: "TBL_HISTORIAL_LLAMADOS_ATENCION", nombre: "Historial de llamados"},
      {id: "TBL_TH_REQUERIMIENTOS_PERSONAL", nombre: "Requerimientos de personal"},
      {id: "TBL_TH_DOCUMENTOS_FINALIZACION", nombre: "Documentos de finalización"},
      {id: "TBL_HISTORIAL_PERSONAL", nombre: "Historial de novedades"},
    ],
    maestros: [
      {id: "TBL_TH_PLANTILLAS_DOCUMENTOS", nombre: "Plantillas de documentos"},
    ],
  },
  {
    id: "tokens_dian", nombre: "Tokens DIAN", tareas: false,
    registros: [{id: "TBL_DIAN_TOKEN_ACCESOS", nombre: "Accesos a tokens"}],
    maestros: [{id: "TBL_DIAN_TOKENS", nombre: "Tokens"}],
  },
  {
    id: "whatsapp", nombre: "WhatsApp", tareas: false,
    registros: [
      {id: "TBL_WHATSAPP_EVENTOS", nombre: "Eventos"},
      {id: "TBL_WHATSAPP_AUDITORIA", nombre: "Auditoría de envíos"},
    ],
    maestros: [],
  },
];

export type Rango = {
  modo: "todo" | "antes" | "desde" | "entre";
  desde: number | null;
  hasta: number | null;
};

// Campos de fecha de creación, en orden. `updatedAt` no cuenta: un registro
// viejo tocado ayer no es de ayer.
const CAMPOS_FECHA = [
  "createdAt", "fecha_creacion", "fechaCreacion", "created_at",
  "fechaRegistro", "registradoEn", "fechaSolicitud", "fechaVisita",
  "fechaHallazgo", "loginAt", "fecha",
];

function comoMs(value: unknown): number | null {
  const ts = value as {toMillis?: () => number} | null;
  if (ts && typeof ts.toMillis === "function") return ts.toMillis();
  if (typeof value === "number" && value > 0) return value;
  if (typeof value === "string" && value.trim()) {
    const ms = Date.parse(value.trim());
    return Number.isNaN(ms) ? null : ms;
  }
  return null;
}

// Fecha de creación de un registro, o null si no trae ninguna.
export function fechaDeRegistro(data: Record<string, unknown>): number | null {
  for (const campo of CAMPOS_FECHA) {
    const ms = comoMs(data[campo]);
    if (ms !== null) return ms;
  }
  return null;
}

// "entra" si está en el rango; "sinFecha" si hay rango y no trae fecha.
export function enRango(
  fecha: number | null,
  rango: Rango
): "entra" | "fuera" | "sinFecha" {
  if (rango.modo === "todo") return "entra";
  if (fecha === null) return "sinFecha";
  const desde = rango.desde ?? 0;
  const hasta = rango.hasta ?? Number.MAX_SAFE_INTEGER;
  switch (rango.modo) {
    case "antes": return fecha < hasta ? "entra" : "fuera";
    case "desde": return fecha >= desde ? "entra" : "fuera";
    case "entre": return fecha >= desde && fecha < hasta ? "entra" : "fuera";
  }
  return "fuera";
}

// Valida lo que manda la app. Las fechas llegan como inicio del día (ms);
// "hasta" se toma hasta el final de ese día.
export function rangoDesde(raw: unknown): Rango {
  const r = (raw && typeof raw === "object" ? raw : {}) as Record<string, unknown>;
  const modo = (r.modo ?? "").toString();
  const num = (v: unknown) => (typeof v === "number" && v > 0 ? v : null);
  const desde = num(r.desde);
  const hastaDia = num(r.hasta);
  const hasta = hastaDia === null ? null : hastaDia + 24 * 60 * 60 * 1000;
  if (modo === "todo") return {modo, desde: null, hasta: null};
  if (modo === "antes" && desde !== null) {
    // "Antes de la fecha": sin incluir ese día.
    return {modo, desde: null, hasta: desde};
  }
  if (modo === "desde" && desde !== null) return {modo, desde, hasta: null};
  if (modo === "entre" && desde !== null && hasta !== null && desde < hasta) {
    return {modo, desde, hasta};
  }
  throw new functions.https.HttpsError(
    "invalid-argument",
    "Revisa el periodo: elige las fechas del rango."
  );
}

function texto(value: unknown): string {
  return (value ?? "").toString().trim();
}

const ALIAS_MODULO: Record<string, string> = {
  interventoriadashboard: "interventoria",
  facturaciondashboard: "facturacion",
  facturacion_observacion: "facturacion",
  visita: "visitas",
  visitasdashboard: "visitas",
  comprasdashboard: "compras",
  compras_correccion: "compras",
  compras_bodega: "compras",
  gestiondocumentaldashboard: "gestion_documental",
  correspondencia: "gestion_documental",
  correodashboard: "correo",
  correo_automatico: "correo",
  planillaspagodashboard: "planillas_pago",
  planillas: "planillas_pago",
  talentohumanodashboard: "talento_humano",
  talentohumano: "talento_humano",
  tareasdashboard: "tareas",
  manual: "tareas",
};

export function normalizarModulo(value: unknown): string {
  const raw = texto(value).toLowerCase().replace(/[^a-z0-9_]/g, "");
  return ALIAS_MODULO[raw] ?? raw;
}

const MODULOS_CON_TAREAS = new Set(
  MODULOS_LIMPIEZA.filter((m) => m.tareas).map((m) => m.id)
);

// Módulo que creó una tarea. Sin marca de ningún módulo, es de Tareas.
export function moduloDeTarea(data: Record<string, unknown>): string {
  const source = data.source && typeof data.source === "object" ?
    data.source as Record<string, unknown> : {};
  if (texto(data.creador_id) === "interventoria_automatica" ||
      texto(data.hallazgoId)) return "interventoria";
  if (texto(data.facObservacionId)) return "facturacion";
  if (texto(data.visitaId)) return "visitas";
  if (texto(data.correspondenciaId)) return "gestion_documental";
  for (const candidato of [source.moduleId, data.sourceModule,
    data.destinoModulo, data.module, data.origen]) {
    const modulo = normalizarModulo(candidato);
    if (MODULOS_CON_TAREAS.has(modulo)) return modulo;
  }
  return "tareas";
}

// ¿La notificación es del módulo? Por su campo `module` o porque es de una
// tarea que se va a borrar.
export function notificacionDelModulo(
  data: Record<string, unknown>,
  modulo: string,
  tareas: Set<string>
): boolean {
  if (tareas.has(texto(data.taskId))) return true;
  const propio = normalizarModulo(data.module ?? data.sourceModule);
  if (propio && propio === modulo) return true;
  const tipo = texto(data.type).toLowerCase();
  return modulo !== "tareas" && tipo.startsWith(`${modulo}_`);
}

type Hallado = {
  ref: FirebaseFirestore.DocumentReference;
  recursivo: boolean;
};

type Conteo = {
  coleccion: string;
  nombre: string;
  maestro: boolean;
  total: number;
  sinFecha: number;
};

async function documentosDeEmpresa(
  db: FirebaseFirestore.Firestore,
  coleccion: Coleccion,
  empresaId: string
): Promise<FirebaseFirestore.QueryDocumentSnapshot[]> {
  if (coleccion.porPrefijoId) {
    const id = admin.firestore.FieldPath.documentId();
    const snap = await db.collection(coleccion.id)
      .where(id, ">=", `${empresaId}_`)
      .where(id, "<", `${empresaId}_`)
      .get();
    return snap.docs;
  }
  const snap = await db.collection(coleccion.id)
    .where("empresaId", "==", empresaId)
    .get();
  return snap.docs;
}

async function usuariosDeEmpresa(
  db: FirebaseFirestore.Firestore,
  empresaId: string
): Promise<string[]> {
  const [porLista, porPrincipal] = await Promise.all([
    db.collection("TBL_USUARIOS").where("empresas", "array-contains", empresaId)
      .select().get(),
    db.collection("TBL_USUARIOS").where("empresaId", "==", empresaId)
      .select().get(),
  ]);
  return [...new Set([...porLista.docs, ...porPrincipal.docs].map((d) => d.id))];
}

export const adminLimpiezaModulo = functions
  .region("us-central1")
  .runWith({timeoutSeconds: 540, memory: "1GB"})
  .https.onCall(async (data: any, context) => {
    const caller = await requireAdmin(data, context);
    const modulo = MODULOS_LIMPIEZA.find((m) => m.id === texto(data?.modulo));
    if (!modulo) {
      throw new functions.https.HttpsError("invalid-argument", "Módulo no válido.");
    }
    const rango = rangoDesde(data?.rango);
    const incluirMaestros = data?.incluirMaestros === true;
    const ejecutar = data?.ejecutar === true;
    if (ejecutar && texto(data?.confirmacion) !== "BORRAR") {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "Escribe BORRAR para confirmar."
      );
    }
    const db = admin.firestore();
    const empresaId = caller.empresaId;
    const conteos: Conteo[] = [];
    const objetivo: Hallado[] = [];

    const colecciones = [
      ...modulo.registros.map((c) => ({c, maestro: false})),
      ...(incluirMaestros ? modulo.maestros.map((c) => ({c, maestro: true})) : []),
    ];
    for (const {c, maestro} of colecciones) {
      const docs = await documentosDeEmpresa(db, c, empresaId);
      let total = 0;
      let sinFecha = 0;
      for (const doc of docs) {
        const estado = enRango(fechaDeRegistro(doc.data()), rango);
        if (estado === "sinFecha") sinFecha++;
        if (estado !== "entra") continue;
        total++;
        objetivo.push({ref: doc.ref, recursivo: c.recursivo === true});
        // El historial de un paciente vive aparte, con id {empresa}-{paciente}.
        if (c.id === "TBL_PACIENTES") {
          objetivo.push({
            ref: db.collection("TBL_HISTORIAL_NUTRICION").doc(`${empresaId}-${doc.id}`),
            recursivo: true,
          });
        }
      }
      conteos.push({coleccion: c.id, nombre: c.nombre, maestro, total, sinFecha});
    }

    // Tareas del módulo y sus notificaciones.
    const tareas = new Set<string>();
    let tareasSinFecha = 0;
    if (modulo.tareas) {
      const snap = await db.collection("TBL_TAREAS")
        .where("empresaId", "==", empresaId).get();
      for (const doc of snap.docs) {
        const t = doc.data();
        if (moduloDeTarea(t) !== modulo.id) continue;
        const estado = enRango(fechaDeRegistro(t), rango);
        if (estado === "sinFecha") tareasSinFecha++;
        if (estado !== "entra") continue;
        tareas.add(doc.id);
        objetivo.push({ref: doc.ref, recursivo: false});
      }
    }
    let notificaciones = 0;
    for (const userId of await usuariosDeEmpresa(db, empresaId)) {
      const snap = await db.collection("TBL_NOTIFICACIONES").doc(userId)
        .collection("notifications").where("empresaId", "==", empresaId).get();
      for (const doc of snap.docs) {
        const n = doc.data();
        if (!notificacionDelModulo(n, modulo.id, tareas)) continue;
        if (!tareas.has(texto(n.taskId)) &&
            enRango(fechaDeRegistro(n), rango) !== "entra") continue;
        notificaciones++;
        objetivo.push({ref: doc.ref, recursivo: false});
      }
    }

    const resumen = {
      modulo: modulo.id,
      colecciones: conteos,
      tareas: tareas.size,
      tareasSinFecha,
      notificaciones,
      total: objetivo.length,
    };
    if (!ejecutar) return {...resumen, ejecutado: false};

    const writer = db.bulkWriter();
    let fallidos = 0;
    writer.onWriteError((error) => {
      if (error.failedAttempts < 3) return true;
      fallidos++;
      return false;
    });
    for (const item of objetivo) {
      if (item.recursivo) {
        await db.recursiveDelete(item.ref, writer);
      } else {
        writer.delete(item.ref).catch(() => undefined);
      }
    }
    await writer.close();

    await db.collection("TBL_MIGRATIONS_LOGS").add({
      adminUserId: caller.userDocId,
      empresaId,
      action: "limpiezaModulo",
      scanned: objetivo.length,
      updated: objetivo.length - fallidos,
      dryRun: false,
      extra: {
        modulo: modulo.id,
        rango: {modo: rango.modo, desde: rango.desde, hasta: rango.hasta},
        incluirMaestros,
        colecciones: conteos.map((c) => ({coleccion: c.coleccion, total: c.total})),
        tareas: tareas.size,
        notificaciones,
        fallidos,
      },
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return {...resumen, ejecutado: true, fallidos};
  });
