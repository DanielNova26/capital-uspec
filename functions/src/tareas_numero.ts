/**
 * Número interno de las tareas (3 oct 2026).
 *
 * Pedido del documento "TAREAS - SEPTIEMBRE 29": "mostrar el número interno
 * de la tarea para mayor facilidad de lectura", y la matriz de "Tareas de mi
 * equipo" lo lleva como primera columna. Es un consecutivo POR EMPRESA.
 *
 * Lo asigna el servidor al crear la tarea y no el cliente: las tareas nacen
 * en Crear tarea, Interventoría, Visitas, Compras, Facturación y en las
 * Functions de Correspondencia. Aquí se cubren todas, y el contador
 * (`TBL_TAREAS_CONTADORES/{empresaId}`) queda fuera del alcance de la app.
 *
 * Tareas que ya existían: la primera vez que se numera algo en una empresa
 * se reservan los números 1..N para las tareas que ya estaban, y la
 * incorporación (`tareasNumerarHistoricas`, desde Admin › Migraciones) las
 * numera en orden de creación dentro de esa reserva. Así el número sigue el
 * orden en que se crearon, sin importar cuándo se corra la incorporación.
 * Un número asignado nunca cambia.
 */
import * as admin from "firebase-admin";
import * as functions from "firebase-functions/v1";
import {requireAdmin} from "./security_admin";

const REGION = "us-central1";
const TAREAS = "TBL_TAREAS";
export const CONTADORES_TAREAS = "TBL_TAREAS_CONTADORES";

type Datos = FirebaseFirestore.DocumentData;

function texto(value: unknown): string {
  return (value ?? "").toString().trim();
}

/**
 * Número ya asignado a la tarea.
 * @param {Datos | undefined} data Documento de la tarea.
 * @return {number | null} El número, o null si no tiene uno válido.
 */
export function numeroDeTarea(data: Datos | undefined): number | null {
  const valor = Number(data?.numero);
  return Number.isInteger(valor) && valor > 0 ? valor : null;
}

/**
 * Milisegundos de creación de una tarea.
 * @param {Datos | undefined} data Documento de la tarea.
 * @return {number} Milisegundos desde epoch, o 0 si no se sabe.
 */
export function creadaEn(data: Datos | undefined): number {
  for (const campo of ["createdAt", "fecha_creacion"]) {
    const valor = data?.[campo] as {toMillis?: () => number} | number | undefined;
    if (typeof valor === "number" && valor > 0) return valor;
    const ms = (valor as {toMillis?: () => number} | undefined)?.toMillis?.();
    if (typeof ms === "number" && ms > 0) return ms;
  }
  return 0;
}

export interface TareaPorNumerar {
  id: string;
  creada: number;
}

/**
 * Orden de la incorporación: por creación y, a igualdad, por id.
 * @param {T[]} tareas Tareas sin número.
 * @return {T[]} Copia ordenada.
 */
export function ordenarParaNumerar<T extends TareaPorNumerar>(tareas: T[]): T[] {
  return [...tareas].sort(
    (a, b) => a.creada - b.creada || a.id.localeCompare(b.id)
  );
}

/**
 * Reparte números a las tareas históricas: primero los libres de la reserva
 * (1..reservado que nadie usa), en orden; si no alcanzan, a continuación del
 * contador.
 * @param {object} input Tareas sin número, números usados, tamaño de la
 *   reserva y último número del contador.
 * @return {object} Número de cada tarea y el último número resultante.
 */
export function planNumeracion(input: {
  tareas: TareaPorNumerar[];
  usados: Set<number>;
  reservado: number;
  ultimo: number;
}): {asignaciones: Array<{id: string; numero: number}>; ultimo: number} {
  const asignaciones: Array<{id: string; numero: number}> = [];
  let candidato = 1;
  let ultimo = input.ultimo;
  for (const tarea of ordenarParaNumerar(input.tareas)) {
    while (candidato <= input.reservado && input.usados.has(candidato)) {
      candidato++;
    }
    if (candidato <= input.reservado) {
      asignaciones.push({id: tarea.id, numero: candidato});
      candidato++;
    } else {
      ultimo++;
      asignaciones.push({id: tarea.id, numero: ultimo});
    }
  }
  return {asignaciones, ultimo};
}

/** Asigna el número al crear la tarea. Reintenta si el contador está ocupado. */
export const tareasAsignarNumero = functions
  .region(REGION)
  .runWith({failurePolicy: true})
  .firestore.document(`${TAREAS}/{taskId}`)
  .onCreate(async (snap: functions.firestore.DocumentSnapshot) => {
    const empresaId = texto(snap.get("empresaId"));
    if (!empresaId || empresaId.includes("/")) return;
    if (numeroDeTarea(snap.data())) return;
    const db = admin.firestore();
    const contadorRef = db.collection(CONTADORES_TAREAS).doc(empresaId);

    // Primera tarea numerada de la empresa: se reservan los números de las
    // que ya existían (se cuentan fuera de la transacción; las consultas de
    // agregación no van dentro).
    let existentes = 0;
    if (!(await contadorRef.get()).exists) {
      const conteo = await db
        .collection(TAREAS)
        .where("empresaId", "==", empresaId)
        .count()
        .get();
      // Sin la tarea que se está creando.
      existentes = Math.max(0, conteo.data().count - 1);
    }

    await db.runTransaction(async (tx) => {
      const tarea = await tx.get(snap.ref);
      if (!tarea.exists || numeroDeTarea(tarea.data())) return;
      const contador = await tx.get(contadorRef);
      const base = contador.exists ?
        Number(contador.get("ultimo")) || 0 :
        existentes;
      const numero = base + 1;
      tx.set(contadorRef, {
        empresaId,
        ultimo: numero,
        ...(contador.exists ? {} : {reservadoHistorico: existentes}),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
      tx.update(snap.ref, {numero});
    });
  });

/**
 * Incorporación de las tareas que ya existían, por empresa y revisable:
 * `aplicar: false` solo cuenta; `aplicar: true` numera. Solo Administración
 * (o Desarrollo) de la empresa activa.
 */
export const tareasNumerarHistoricas = functions
  .region(REGION)
  .runWith({timeoutSeconds: 540, memory: "1GB"})
  .https.onCall(async (data: any, context: functions.https.CallableContext) => {
    const caller = await requireAdmin(data, context);
    const empresaId = caller.empresaId;
    const aplicar = data?.aplicar === true;
    const db = admin.firestore();

    const snap = await db
      .collection(TAREAS)
      .where("empresaId", "==", empresaId)
      .get();
    const usados = new Set<number>();
    const pendientes: TareaPorNumerar[] = [];
    for (const doc of snap.docs) {
      const numero = numeroDeTarea(doc.data());
      if (numero) {
        usados.add(numero);
      } else {
        pendientes.push({id: doc.id, creada: creadaEn(doc.data())});
      }
    }
    const resumen = {
      total: snap.size,
      conNumero: snap.size - pendientes.length,
      sinNumero: pendientes.length,
    };
    if (!aplicar || pendientes.length === 0) {
      return {...resumen, numeradas: 0, aplicado: false};
    }

    const contadorRef = db.collection(CONTADORES_TAREAS).doc(empresaId);
    // El plan se fija en una transacción sobre el contador: si mientras tanto
    // se crea otra tarea, su número sale después del bloque reservado aquí.
    const plan = await db.runTransaction(async (tx) => {
      const contador = await tx.get(contadorRef);
      const maximoUsado = Array.from(usados).reduce((a, b) => Math.max(a, b), 0);
      const reservado = contador.exists ?
        Number(contador.get("reservadoHistorico")) || 0 :
        pendientes.length;
      const ultimo = contador.exists ?
        Math.max(Number(contador.get("ultimo")) || 0, maximoUsado) :
        Math.max(maximoUsado, reservado);
      const resultado = planNumeracion({
        tareas: pendientes,
        usados,
        reservado,
        ultimo,
      });
      tx.set(contadorRef, {
        empresaId,
        ultimo: resultado.ultimo,
        reservadoHistorico: reservado,
        historicoNumeradoAt: admin.firestore.FieldValue.serverTimestamp(),
        historicoNumeradoPor: caller.userDocId,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
      return resultado.asignaciones;
    });

    // De a 50 en paralelo. Una tarea que recibió número entre la lectura y
    // la escritura (no debería: son tareas viejas) conserva el suyo.
    let numeradas = 0;
    for (let i = 0; i < plan.length; i += 50) {
      const lote = plan.slice(i, i + 50);
      await Promise.all(lote.map(async ({id, numero}) => {
        const ref = db.collection(TAREAS).doc(id);
        await db.runTransaction(async (tx) => {
          const tarea = await tx.get(ref);
          if (!tarea.exists || numeroDeTarea(tarea.data())) return;
          tx.update(ref, {numero});
          numeradas++;
        });
      }));
    }
    console.log("[tareasNumerarHistoricas]", empresaId, numeradas);
    return {...resumen, numeradas, aplicado: true};
  });
