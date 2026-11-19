import * as admin from "firebase-admin";
import * as functions from "firebase-functions/v1";
import {createHash} from "crypto";
import {appsDeEmpresa} from "./apps_por_empresa";
import {empresasSeleccionables} from "./acceso";
import {calcularPlaneacion, Dato, exigir, fecha, PLANEACION_APP, puedePlaneacion, positivo, seleccionSalida, unidad} from "./planeacion_policy";

const tablas = {menus: "TBL_PLANEACION_MENUS", precios: "TBL_PLANEACION_PRECIOS",
  partes: "TBL_PLANEACION_PARTES", ciclos: "TBL_PLANEACION_CICLOS",
  solicitudes: "TBL_PLANEACION_SOLICITUDES", salidas: "TBL_PLANEACION_SALIDAS"};
const idDe = (...valores: string[]) => createHash("sha256").update(JSON.stringify(valores)).digest("hex");
const texto = (v: unknown, max = 120) => {
  const s = String(v ?? "").trim(); exigir(s.length > 0 && s.length <= max, "Completa los campos de texto."); return s;
};
const tieneApp = (u: Dato, e: string, app: string) => appsDeEmpresa(u, e).some((a) => [app, app.replace("dashboard", "")].includes(a.trim().toLowerCase()));

// Todas las mutaciones se validan en una transacción. No se aceptan totales,
// precios, nombres ni permisos calculados por el cliente.
export const planeacionOperar = functions.region("us-central1").https.onCall(async (raw, context) => {
  if (!context.auth || context.auth.token.authVersion !== 2 || !context.auth.token.userDocId) {
    throw new functions.https.HttpsError("unauthenticated", "Inicia sesión.");
  }
  try {
    const empresaId = texto(raw?.empresaId);
    const accion = texto(raw?.accion);
    const d: Dato = raw?.datos ?? {};
    const userId = String(context.auth.token.userDocId);
    const db = admin.firestore();
    return await db.runTransaction(async (tx) => {
      const user = (await tx.get(db.collection("TBL_USUARIOS").doc(userId))).data() ?? {};
      exigir(empresasSeleccionables(user).includes(empresaId), "No perteneces o no estás habilitado en esta empresa.");
      const compras = accion === "cargarCompras" || accion === "gestionarSolicitud";
      const app = compras ? "comprasdashboard" : PLANEACION_APP;
      exigir(tieneApp(user, empresaId, app), "No tienes acceso al módulo en esta empresa.");
      const habilitacion = await tx.get(db.collection("TBL_APPS").doc(`${empresaId}_${app}`));
      // Planeación es nueva: se habilita expresamente. Compras mantiene su contrato histórico.
      exigir(compras ? habilitacion.data()?.enabled !== false : habilitacion.data()?.enabled === true, "El módulo está deshabilitado en esta empresa.");
      const rol = (await tx.get(db.collection(compras ? "TBL_COMPRAS_ROLES" : "TBL_PLANEACION_ROLES").doc(`${empresaId}_${userId}`))).data();
      const nivel = rol?.empresaId === empresaId && rol?.userId === userId ? String(rol.rol) : "";
      const permitido = compras ? (accion === "cargarCompras" || ["admin", "compras", "calidad"].includes(nivel)) :
        puedePlaneacion(nivel, accion);
      exigir(permitido, "Tu nivel no permite esta acción. Solicita la asignación en Admin.");
      const listar = async (tabla: string) => {
        const snap = await tx.get(db.collection(tabla).where("empresaId", "==", empresaId));
        return snap.docs.map((s) => ({...s.data(), id: s.id}) as Dato);
      };
      const guardar = (tabla: string, id: string, datos: Dato) => tx.set(db.collection(tabla).doc(id), {
        ...datos, empresaId, actualizadoPor: userId, updatedAt: admin.firestore.FieldValue.serverTimestamp()
      }, {merge: true});
      if (accion === "cargarCompras") return {nivel, solicitudes: await listar(tablas.solicitudes)};
      if (accion === "cargar") {
        const resultado: Dato = {nivel};
        for (const [key, tabla] of Object.entries(tablas)) resultado[key] = await listar(tabla);
        resultado.productos = await listar("TBL_COMPRAS_PRODUCTOS");
        resultado.centros = await listar("TBL_CENTROS_COSTOS");
        // Los timestamps no forman parte del contrato JSON de la pantalla.
        return JSON.parse(JSON.stringify(resultado));
      }
      if (accion === "gestionarSolicitud") {
        const id = texto(d.id);
        const ref = db.collection(tablas.solicitudes).doc(id);
        const actual = (await tx.get(ref)).data();
        exigir(actual?.empresaId === empresaId, "Solicitud ajena o inexistente.");
        const destino = texto(d.estado);
        const transiciones: Dato = {enviada: ["en_gestion", "devuelta"],
          en_gestion: ["atendida", "devuelta"], devuelta: ["en_gestion"]};
        exigir(transiciones[actual.estado]?.includes(destino), "La solicitud cambió o la transición no es válida.");
        const nota = String(d.nota ?? "").trim();
        const referencia = String(d.ordenCompraReferencia ?? "").trim();
        exigir(nota.length <= 1000 && referencia.length <= 120, "Texto demasiado largo.");
        if (destino === "devuelta") exigir(nota, "Indica el motivo de devolución.");
        if (destino === "atendida") exigir(referencia, "Registra la referencia de la orden de compra.");
        guardar(tablas.solicitudes, id, {estado: destino, nota, ordenCompraReferencia: referencia,
          historial: [...(actual.historial ?? []),
            {estado: destino, nota, referencia, userId, fecha: new Date().toISOString()}]});
        return {id};
      }
      if (accion === "guardarParte") {
        const centroId = texto(d.centroId);
        const centro = (await tx.get(db.collection("TBL_CENTROS_COSTOS").doc(centroId))).data();
        exigir(centro?.empresaId === empresaId && centro?.activo !== false && centro?.enabled !== false, "Establecimiento ajeno, inactivo o inexistente.");
        const id = idDe(empresaId, centroId);
        const anterior = (await tx.get(db.collection(tablas.partes).doc(id))).data();
        guardar(tablas.partes, id, {centroId, centroNombre: centro.nombre ?? centro.descripcion ?? centroId,
          raciones: positivo(d.raciones, true),
          createdAt: anterior?.createdAt ?? admin.firestore.FieldValue.serverTimestamp()});
        return {id};
      }
      const productos = await listar("TBL_COMPRAS_PRODUCTOS");
      const menus = await listar(tablas.menus);
      if (accion === "guardarMenu") {
        const codigo = texto(d.codigo, 40);
        exigir(Array.isArray(d.ingredientes) && d.ingredientes.length > 0 && d.ingredientes.length <= 150, "Agrega entre 1 y 150 ingredientes.");
        const ingredientes = d.ingredientes.map((i: Dato) => {
          const productoCodigo = texto(i.productoCodigo, 80);
          const candidatos = productos.filter((p) => p.codigo === productoCodigo && p.activo !== false);
          exigir(candidatos.length === 1, `Producto sin código único en Compras: ${productoCodigo}.`);
          const um = unidad(candidatos[0].unidadMedida);
          exigir(um && unidad(i.unidad) === um, "La cantidad debe estar en la unidad de compra del producto.");
          return {productoCodigo, unidad: um, cantidadPorRacion: positivo(i.cantidadPorRacion),
            tiempo: texto(i.tiempo, 50), preparacion: texto(i.preparacion)};
        });
        const existentes = menus.filter((m) => m.codigo === codigo);
        exigir(existentes.length <= 1, "Hay menús duplicados con ese código. Consolídalos antes de editar.");
        if (d.soloNuevo === true && existentes.length) return {id: existentes[0].id, omitido: true};
        const id = existentes[0]?.id ?? idDe(empresaId, codigo);
        guardar(tablas.menus, id, {codigo, nombre: texto(d.nombre), activo: d.activo !== false, ingredientes,
          createdAt: existentes[0]?.createdAt ?? admin.firestore.FieldValue.serverTimestamp()});
        return {id};
      }
      const precios = await listar(tablas.precios);
      if (accion === "guardarPrecio") {
        const productoCodigo = texto(d.productoCodigo, 80);
        const candidatos = productos.filter((p) => p.codigo === productoCodigo);
        exigir(candidatos.length === 1, "Selecciona un producto con código único en Compras.");
        const desde = fecha(d.desde); const hasta = fecha(d.hasta);
        exigir(desde <= hasta, "La vigencia está invertida.");
        const existentes = precios.filter((p) => p.productoCodigo === productoCodigo && p.desde === desde);
        exigir(existentes.length <= 1, "Hay precios duplicados para esa fecha. Consolídalos antes de editar.");
        const anterior = d.id ? precios.find((p) => p.id === d.id) : undefined;
        exigir(!d.id || anterior?.productoCodigo === productoCodigo, "El precio no pertenece a ese producto y empresa.");
        const id = anterior?.id ?? existentes[0]?.id ?? idDe(empresaId, productoCodigo, desde);
        exigir(!precios.some((p) => p.id !== id && p.productoCodigo === productoCodigo && p.activo !== false && p.desde <= hasta && p.hasta >= desde), "La vigencia se cruza con otro precio del producto.");
        guardar(tablas.precios, id, {productoCodigo, unidad: unidad(candidatos[0].unidadMedida),
          desde, hasta, precio: positivo(d.precio), activo: true,
          createdAt: anterior?.createdAt ?? existentes[0]?.createdAt ?? admin.firestore.FieldValue.serverTimestamp()});
        return {id};
      }
      if (accion === "guardarCiclo") {
        const centros = await listar("TBL_CENTROS_COSTOS");
        exigir(Array.isArray(d.programacion), "Falta la programación.");
        const desde = fecha(d.desde); const hasta = fecha(d.hasta);
        exigir(desde <= hasta && (Date.parse(hasta) - Date.parse(desde)) / 86400000 <= 61, "El ciclo debe tener entre 1 y 62 días.");
        const programacion = d.programacion.map((s: Dato) => {
          const centro = centros.find((c) => c.id === s.centroId && c.activo !== false && c.enabled !== false);
          exigir(centro, "Establecimiento ajeno o inactivo.");
          exigir(fecha(s.fecha) >= desde && s.fecha <= hasta, "Consumo fuera del ciclo.");
          return {centroId: centro.id, centroNombre: centro.nombre ?? centro.descripcion ?? centro.id,
            fecha: s.fecha, menuCodigo: texto(s.menuCodigo, 40), raciones: positivo(s.raciones, true)};
        });
        const calculo = calcularPlaneacion(programacion, menus, productos, precios);
        const ref = d.id ? db.collection(tablas.ciclos).doc(texto(d.id)) : db.collection(tablas.ciclos).doc();
        const anterior = (await tx.get(ref)).data();
        exigir(!d.id || anterior?.empresaId === empresaId, "Ciclo ajeno o inexistente.");
        exigir(!anterior || anterior.estado === "borrador", "Un ciclo enviado no se edita. Crea un ciclo nuevo.");
        const datos = {nombre: texto(d.nombre), desde, hasta, programacion, ...calculo, estado: "borrador",
          alistados: [], despachados: [], creadoPor: anterior?.creadoPor ?? userId,
          createdAt: anterior?.createdAt ?? admin.firestore.FieldValue.serverTimestamp()};
        exigir(Buffer.byteLength(JSON.stringify(datos), "utf8") < 850000, "Divide el ciclo en períodos o establecimientos más pequeños.");
        guardar(tablas.ciclos, ref.id, datos);
        return {id: ref.id};
      }
      const id = texto(d.id);
      const ciclo = (await tx.get(db.collection(tablas.ciclos).doc(id))).data();
      exigir(ciclo?.empresaId === empresaId, "Ciclo ajeno o inexistente.");
      if (accion === "enviar") {
        if (ciclo.estado !== "borrador") return {id}; // Reintento idempotente.
        const calculo = calcularPlaneacion(ciclo.programacion, menus, productos, precios);
        exigir(Buffer.byteLength(JSON.stringify({...ciclo, ...calculo}), "utf8") < 850000,
          "Divide el ciclo en períodos o establecimientos más pequeños.");
        exigir(calculo.sinPrecio === 0, "Completa los precios vigentes de todos los productos antes de enviar.");
        const centros = await listar("TBL_CENTROS_COSTOS");
        exigir(ciclo.programacion.every((s: Dato) => centros.some((c) => c.id === s.centroId && c.activo !== false && c.enabled !== false)), "Hay establecimientos retirados o inactivos.");
        guardar(tablas.ciclos, id, {...calculo, estado: "enviada"});
        guardar(tablas.solicitudes, id, {cicloId: id, nombre: ciclo.nombre, desde: ciclo.desde,
          hasta: ciclo.hasta, programacion: ciclo.programacion, lineas: calculo.lineas,
          totales: calculo.totales, costoTotal: calculo.costoTotal, estado: "enviada", creadoPor: userId,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          historial: [{estado: "enviada", userId, fecha: new Date().toISOString()}]});
        return {id};
      }
      exigir(ciclo.estado !== "borrador", "Envía el ciclo a Compras antes de alistar.");
      const seleccion = seleccionSalida(ciclo, d.desde, d.hasta, accion);
      const campo = accion === "alistar" ? "alistados" : "despachados";
      const acumulados = [...(ciclo[campo] ?? []), ...seleccion];
      const salidaId = idDe(empresaId, id, accion, ...seleccion);
      guardar(tablas.salidas, salidaId, {cicloId: id, tipo: accion, desde: d.desde, hasta: d.hasta,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        programacionIds: seleccion, lineas: ciclo.lineas.filter((l: Dato) => seleccion.includes(l.programacionId)),
        observacion: String(d.observacion ?? "").trim().slice(0, 1000), registradoPor: userId, fechaRegistro: new Date().toISOString()});
      guardar(tablas.ciclos, id, {[campo]: acumulados,
        ...(accion === "despachar" && acumulados.length === ciclo.programacion.length ? {estado: "despachada"} : {})});
      return {id: salidaId};
    });
  } catch (error) {
    if (error instanceof functions.https.HttpsError) throw error;
    if (error instanceof Error && error.constructor === Error) throw new functions.https.HttpsError("failed-precondition", error.message);
    functions.logger.error("planeacionOperar", error);
    throw new functions.https.HttpsError("internal", "No se pudo guardar. Actualiza e inténtalo de nuevo.");
  }
});
