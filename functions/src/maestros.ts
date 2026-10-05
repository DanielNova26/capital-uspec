// Maestros por módulo (29 sep 2026): Admin › Maestros por módulo copia los
// maestros y la configuración de un módulo de la empresa activa a otras
// empresas, para que cada módulo trabaje solo con su empresa y no tenga que
// saber que existen las demás.
//
// "Agregar lo que falta": en el destino solo se crea lo que no tiene (por
// su código o su nombre) y nunca se toca lo que ya existe; se puede repetir.
// En la configuración se completan los campos vacíos, sin cambiar los que
// ya tienen valor.
//
// Las referencias entre maestros (el producto a su marca, la ficha a su
// proveedor, el formato a su área…) se traducen a los ids del destino. Las
// áreas, cargos y centros se buscan por nombre en el destino; si allí no
// existen se deja el id que tendrían al enviarlos desde Multiempresa y se
// avisa en la vista previa.
import * as admin from "firebase-admin";
import * as functions from "firebase-functions/v1";
import {randomUUID} from "crypto";
import {requireAdmin} from "./security_admin";

export type Maestro = {
  id: string;
  nombre: string;
  // "config": un documento por empresa con id = empresaId.
  // "coleccion": documentos con campo empresaId.
  tipo: "config" | "coleccion";
  // Campos que identifican el registro entre empresas. Vacío: solo por id.
  clave?: string[];
  // Campos de cada empresa que no se copian.
  omitir?: string[];
  // Archivo en Storage que se duplica: campo de la ruta y de la URL.
  archivo?: {ruta: string; url: string};
  // Biblioteca documental: además del documento, su versión vigente.
  biblioteca?: boolean;
  // Solo se copian los registros que traen este campo con algo.
  soloSi?: string;
  // Campo con reglas que nombran cargos por NOMBRE (Interventoría): se
  // avisa de los que el destino no tiene, porque la regla no resolvería a
  // nadie y el hallazgo quedaría sin responsable.
  cargosEnReglas?: string;
  // Código consecutivo por empresa (las marcas: MRC-0001): si el código ya
  // lo usa otra en el destino, se le da el siguiente libre.
  consecutivo?: {
    campo: string;
    prefijo: string;
    digitos: number;
    config: string;
    contador: string;
  };
};

export type ModuloMaestros = {
  id: string;
  nombre: string;
  maestros: Maestro[];
};

export const MODULOS_MAESTROS: ModuloMaestros[] = [
  {
    id: "compras", nombre: "Compras",
    maestros: [
      // El período de consumo de Abastecimiento se copia; quién y cuándo
      // lo cambió es de cada empresa.
      {id: "TBL_COMPRAS_CONFIG", nombre: "Configuración", tipo: "config",
        omitir: ["marcaSeq", "abastecimientoPeriodoActualizadoPor",
          "abastecimientoPeriodoActualizadoAt"]},
      {id: "TBL_COMPRAS_GRUPOS", nombre: "Grupos", tipo: "coleccion",
        clave: ["nombre"]},
      {id: "TBL_COMPRAS_BODEGAS", nombre: "Bodegas", tipo: "coleccion",
        clave: ["nombre"]},
      {id: "TBL_COMPRAS_MARCAS", nombre: "Marcas", tipo: "coleccion",
        clave: ["descripcion"],
        consecutivo: {campo: "codigo", prefijo: "MRC-", digitos: 4,
          config: "TBL_COMPRAS_CONFIG", contador: "marcaSeq"}},
      {id: "TBL_COMPRAS_PROVEEDORES", nombre: "Proveedores", tipo: "coleccion",
        clave: ["nit"]},
      {id: "TBL_COMPRAS_PRODUCTOS", nombre: "Productos", tipo: "coleccion",
        clave: ["codigo"]},
      {id: "TBL_COMPRAS_FICHAS_TECNICAS", nombre: "Fichas técnicas",
        tipo: "coleccion",
        clave: ["productoNombre", "marcaNombre", "proveedorNombre"]},
      {id: "TBL_COMPRAS_REQ_DOCUMENTOS", nombre: "Requisitos documentales",
        tipo: "coleccion",
        clave: ["categoriaApp", "materiaPrima", "origen", "nivel", "etapa",
          "codDoc"]},
    ],
  },
  {
    id: "interventoria", nombre: "Interventoría",
    maestros: [
      {id: "TBL_INTERVENTORIA_CONFIG",
        nombre: "Configuración y reglas de subsanación", tipo: "config",
        cargosEnReglas: "reglasSubsanacion"},
    ],
  },
  {
    id: "visitas", nombre: "Visitas",
    maestros: [
      {id: "TBL_VISITAS_FORMATOS", nombre: "Formatos", tipo: "coleccion",
        clave: ["areaNombre", "nombre", "version"]},
      // Los que no son centros de costo (5 oct 2026). Antes que Ubicaciones:
      // su id (`{empresa}_est_…`) es el centroId que nombra la ubicación.
      {id: "TBL_VISITAS_ESTABLECIMIENTOS",
        nombre: "Establecimientos propios de Visitas", tipo: "coleccion",
        clave: ["nombre"], omitir: ["creadoPor", "actualizadoPor"]},
      {id: "TBL_VISITAS_UBICACIONES", nombre: "Ubicaciones de establecimientos",
        tipo: "coleccion", clave: ["centroNombre", "subcentroNombre"],
        omitir: ["actualizadoPor"]},
    ],
  },
  {
    id: "facturacion", nombre: "Facturación",
    maestros: [
      {id: "TBL_FAC_OBLIGACIONES", nombre: "Obligaciones", tipo: "coleccion",
        clave: ["codigo"]},
      // El mes y las fechas límite son del ciclo de cada empresa; se copia
      // qué documentos no aplican a cada establecimiento.
      {id: "TBL_FAC_ESTABLECIMIENTOS",
        nombre: "Documentos que no aplican por establecimiento",
        tipo: "coleccion", clave: [], soloSi: "ignoredDocs",
        omitir: ["mes", "fechaLimite", "deadlines"]},
    ],
  },
  {
    id: "rutas", nombre: "Rutas",
    maestros: [
      {id: "TBL_RUTAS_CONFIG", nombre: "Configuración", tipo: "config"},
      {id: "TBL_RUTAS_MOV_CONFIG", nombre: "Configuración de movilidad",
        tipo: "config", omitir: ["alertaCedulas"]},
      {id: "TBL_RUTAS_ESTABLECIMIENTOS", nombre: "Establecimientos",
        tipo: "coleccion", clave: ["nombre"]},
      {id: "TBL_RUTAS", nombre: "Rutas", tipo: "coleccion", clave: ["codigo"]},
      {id: "TBL_RUTAS_PLACAS", nombre: "Placas", tipo: "coleccion",
        clave: ["placa"]},
      {id: "TBL_RUTAS_MOV_HORARIOS", nombre: "Horarios de medición",
        tipo: "coleccion", clave: ["weekday", "hora", "escenario"]},
    ],
  },
  {
    id: "nutricion", nombre: "Nutrición",
    maestros: [
      {id: "TBL_INGREDIENTES", nombre: "Ingredientes", tipo: "coleccion",
        clave: ["nombre"]},
      {id: "TBL_PATOLOGIAS", nombre: "Patologías", tipo: "coleccion",
        clave: ["codigo"]},
      {id: "TBL_DIETAS", nombre: "Dietas", tipo: "coleccion",
        clave: ["codigo"]},
      {id: "TBL_PLANTILLAS_MENUS", nombre: "Plantillas de menú",
        tipo: "coleccion", clave: ["establecimiento", "plantillaKey"]},
      {id: "TBL_MENUS", nombre: "Menús", tipo: "coleccion",
        clave: ["establecimiento", "semana", "nombre"]},
    ],
  },
  {
    id: "gestion_documental", nombre: "Correspondencia",
    maestros: [
      {id: "TBL_GD_TIPOS_DOCUMENTALES", nombre: "Tipos documentales",
        tipo: "coleccion", clave: ["codigo"]},
    ],
  },
  {
    id: "bibliotecadocumental", nombre: "Biblioteca documental",
    maestros: [
      // Cada documento va con su versión vigente y su archivo; el historial
      // de flujo y las versiones anteriores son de la otra empresa.
      {id: "TBL_DOCUMENTOS", nombre: "Documentos (versión vigente)",
        tipo: "coleccion", clave: ["codigo"], biblioteca: true},
    ],
  },
  {
    id: "talento_humano", nombre: "Talento Humano",
    maestros: [
      {id: "TBL_TH_PLANTILLAS_DOCUMENTOS", nombre: "Plantillas de documentos",
        tipo: "coleccion", clave: ["tipo"],
        archivo: {ruta: "storagePath", url: "url"}},
      {id: "TBL_ZEUS_CONFIG", nombre: "Valores por defecto de Zeus",
        tipo: "config"},
    ],
  },
];

// ─── Ayudas puras (probadas en test/maestros.test.js) ────────────────────────

function texto(value: unknown): string {
  return (value ?? "").toString().trim();
}

const TILDES: Record<string, string> = {
  "á": "a", "é": "e", "í": "i", "ó": "o", "ú": "u", "ä": "a", "ë": "e",
  "ï": "i", "ö": "o", "ü": "u", "ñ": "n", "ç": "c",
};

function sinTildes(value: string): string {
  return value.replace(/[áéíóúäëïöüñç]/gi, (c) => {
    const base = TILDES[c.toLowerCase()] ?? c;
    return c === c.toLowerCase() ? base : base.toUpperCase();
  });
}

// "Auxiliar de Cocina", "AUXILIAR  DE COCINA" y "auxiliar_de_cocina" empatan.
export function normalizarClave(value: unknown): string {
  return sinTildes(texto(value)).toLowerCase().replace(/[^a-z0-9]+/g, "");
}

// Clave del registro con sus campos; vacía si ninguno trae valor.
export function claveDe(
  data: Record<string, unknown>,
  campos: string[]
): string {
  const partes = campos.map((c) => normalizarClave(data[c]));
  return partes.some((p) => p) ? partes.join("|") : "";
}

// Id de catálogo que crea Multiempresa al enviar un área, cargo o centro:
// `{empresaId}_{slug}` (lib/core/multiempresa_sync.dart, idCatalogo).
export function idCatalogo(empresaId: string, base: string): string {
  const slug = sinTildes(base).toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/_+/g, "_")
    .replace(/^_|_$/g, "");
  return `${empresaId.trim()}_${slug || "item"}`;
}

export type Contexto = {
  origen: string;
  destino: string;
  // id del origen → id del destino (maestros y catálogos).
  mapa: Map<string, string>;
  // ids del origen cuyo equivalente no existe aún en el destino → qué es.
  pendientes: Map<string, string>;
  // Lo que se tradujo a un id que el destino todavía no tiene.
  sinEquivalente: Set<string>;
  // Nombres (normalizados) de los cargos del destino.
  cargosDestino?: Set<string>;
};

// ¿Se puede tratar como referencia? Solo los ids con el prefijo de la
// empresa o con forma de id automático de Firestore (20 letras y números).
// Un código corto usado como id ("HIPO", "1001") también aparece como
// valor normal en otros campos y no se debe cambiar.
export function pareceId(value: string, origen: string): boolean {
  return value.startsWith(`${origen}_`) || /^[A-Za-z0-9]{20,}$/.test(value);
}

function registrar(
  ctx: Contexto,
  origenId: string,
  destinoId: string,
  pendiente?: string
): void {
  if (!pareceId(origenId, ctx.origen) || ctx.mapa.has(origenId)) return;
  ctx.mapa.set(origenId, destinoId);
  if (pendiente) ctx.pendientes.set(origenId, pendiente);
}

function traducirTexto(s: string, ctx: Contexto, avisar = true): string {
  if (s === ctx.origen) return ctx.destino;
  const mapeado = ctx.mapa.get(s);
  if (mapeado !== undefined) {
    const pendiente = ctx.pendientes.get(s);
    if (pendiente && avisar) ctx.sinEquivalente.add(pendiente);
    return mapeado;
  }
  const prefijo = `${ctx.origen}_`;
  if (s.startsWith(prefijo) && s.length > prefijo.length) {
    return `${ctx.destino}_${s.slice(prefijo.length)}`;
  }
  return s;
}

function esObjetoPlano(value: unknown): value is Record<string, unknown> {
  if (value === null || typeof value !== "object") return false;
  const proto = Object.getPrototypeOf(value);
  return proto === Object.prototype || proto === null;
}

// Copia profunda con los ids del origen cambiados por los del destino, en
// valores y en llaves de mapas. Fechas, referencias y demás objetos de
// Firestore pasan tal cual.
export function remapear(value: unknown, ctx: Contexto): unknown {
  if (typeof value === "string") return traducirTexto(value, ctx);
  if (Array.isArray(value)) return value.map((v) => remapear(v, ctx));
  if (esObjetoPlano(value)) {
    const out: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(value)) {
      out[traducirTexto(k, ctx)] = remapear(v, ctx);
    }
    return out;
  }
  return value;
}

// Id del documento en el destino. Los ids `{origen}_{resto}` pasan a
// `{destino}_{resto traducido}` (el resto puede ser un centro, o
// `{centro}__{subcentro}`); cualquier otro id se crea nuevo (undefined).
export function idDestino(docId: string, ctx: Contexto): string | undefined {
  const prefijo = `${ctx.origen}_`;
  if (!docId.startsWith(prefijo) || docId.length === prefijo.length) {
    return undefined;
  }
  const resto = docId.slice(prefijo.length);
  const traducir = (parte: string) => {
    const mapeado = ctx.mapa.get(parte);
    if (mapeado === undefined) return parte;
    const pendiente = ctx.pendientes.get(parte);
    if (pendiente) ctx.sinEquivalente.add(pendiente);
    return mapeado;
  };
  if (ctx.mapa.has(resto)) return `${ctx.destino}_${traducir(resto)}`;
  return `${ctx.destino}_${resto.split("__").map(traducir).join("__")}`;
}

// Ruta del archivo copiado: la carpeta de la empresa y la del documento
// pasan a las del destino.
export function rutaDestino(ruta: string, ctx: Contexto): string {
  return ruta.split("/").map((parte) => {
    if (parte === ctx.origen) return ctx.destino;
    return ctx.mapa.get(parte) ?? parte;
  }).join("/");
}

function vacio(value: unknown): boolean {
  return value === undefined || value === null ||
    (typeof value === "string" && value.trim() === "");
}

const AUDITORIA = /(ActualizadaPor|ActualizadoPor|ActualizadaAt|ActualizadoAt|UpdatedAt|CopiadaDe)$/;
const NO_SE_COPIAN = new Set([
  "empresaId", "createdAt", "updatedAt", "createdBy", "updatedBy",
  "actualizadoPor", "actualizadoEn", "creadoPor", "creadoEn",
  "sincronizadoDesde",
]);

// Lo que le falta a la configuración del destino: los campos que allí no
// existen o están vacíos, recorriendo los mapas por dentro. Las listas se
// toman completas: si el destino ya tiene una, es su decisión. Con [ctx],
// las llaves y los valores del origen se traducen a los ids del destino.
export function camposFaltantes(
  origen: Record<string, unknown>,
  destino: Record<string, unknown>,
  omitir: string[] = [],
  ctx?: Contexto,
  raiz = true
): {parche: Record<string, unknown>; campos: string[]} {
  const parche: Record<string, unknown> = {};
  const campos: string[] = [];
  for (const [llave, v] of Object.entries(origen)) {
    if (raiz && (NO_SE_COPIAN.has(llave) || AUDITORIA.test(llave) ||
      omitir.includes(llave))) continue;
    if (vacio(v)) continue;
    const k = ctx ? traducirTexto(llave, ctx, false) : llave;
    const actual = destino[k];
    if (esObjetoPlano(v) && esObjetoPlano(actual)) {
      const sub = camposFaltantes(v, actual, [], ctx, false);
      if (sub.campos.length) {
        parche[k] = sub.parche;
        campos.push(...sub.campos.map((c) => `${k}.${c}`));
        if (ctx) traducirTexto(llave, ctx);
      }
      continue;
    }
    if (!vacio(actual)) continue;
    parche[k] = ctx ? remapear(v, ctx) : v;
    campos.push(k);
    if (ctx) traducirTexto(llave, ctx);
  }
  return {parche, campos};
}

function listaDeCargos(lista: unknown, unico: unknown): string[] {
  if (Array.isArray(lista)) {
    const cargos = lista.map((c) => texto(c)).filter((c) => c);
    if (cargos.length) return cargos;
  }
  const uno = texto(unico);
  return uno ? [uno] : [];
}

// Cargos que nombran las reglas y que no están en [existentes] (nombres
// normalizados). Las reglas viejas traen el cargo en singular.
export function cargosFaltantesEnReglas(
  reglas: unknown,
  existentes: Set<string>
): string[] {
  if (!esObjetoPlano(reglas)) return [];
  const faltan = new Map<string, string>();
  for (const regla of Object.values(reglas)) {
    if (!esObjetoPlano(regla)) continue;
    for (const cargo of [
      ...listaDeCargos(regla.responsables, regla.responsable),
      ...listaDeCargos(regla.aprobadores, regla.aprobador),
    ]) {
      const k = normalizarClave(cargo);
      if (k && !existentes.has(k) && !faltan.has(k)) faltan.set(k, cargo);
    }
  }
  return [...faltan.values()].sort((a, b) => a.localeCompare(b));
}

// Siguiente código libre de un consecutivo (MRC-0007) sin chocar con los
// que ya existen en el destino.
export function codigoLibre(
  usados: Set<string>,
  prefijo: string,
  digitos: number,
  desde: number
): {codigo: string; numero: number} {
  let n = desde;
  for (;;) {
    n++;
    const codigo = `${prefijo}${n.toString().padStart(digitos, "0")}`;
    if (!usados.has(codigo.toUpperCase())) return {codigo, numero: n};
  }
}

export function numeroDeCodigo(codigo: string, prefijo: string): number {
  const c = codigo.trim().toUpperCase();
  if (!c.startsWith(prefijo.toUpperCase())) return 0;
  const n = Number.parseInt(c.slice(prefijo.length), 10);
  return Number.isFinite(n) ? n : 0;
}

// ─── Catálogos de la empresa (áreas, cargos, centros) ────────────────────────

const CATALOGOS = [
  {coleccion: "TBL_AREAS", campoId: "areaId", etiqueta: "Área"},
  {coleccion: "TBL_CARGOS", campoId: "cargoId", etiqueta: "Cargo"},
  {coleccion: "TBL_CENTROS_COSTOS", campoId: "centroId",
    etiqueta: "Centro de costos"},
];

type EntradaCatalogo = {ids: string[]; nombre: string; codigo: string};

function nombreCatalogo(
  id: string,
  data: Record<string, unknown>,
  empresaId: string
): string {
  const nombre = texto(data.nombre) || texto(data.descripcion);
  if (nombre && !nombre.includes("_")) return nombre;
  let base = nombre || id;
  const prefijo = `${empresaId}_`.toLowerCase();
  if (base.toLowerCase().startsWith(prefijo)) base = base.slice(prefijo.length);
  return base.replace(/_+/g, " ").trim() || id;
}

export function entradasCatalogo(
  docs: {id: string; data: Record<string, unknown>}[],
  campoId: string,
  empresaId: string
): EntradaCatalogo[] {
  return docs.map((d) => {
    const alterno = texto(d.data[campoId]);
    return {
      ids: alterno && alterno !== d.id ? [d.id, alterno] : [d.id],
      nombre: nombreCatalogo(d.id, d.data, empresaId),
      codigo: texto(d.data.codigo),
    };
  });
}

// Cada id del catálogo del origen con su equivalente en el destino, por
// nombre (los centros también por código). Sin equivalente, el id que
// tendría al enviarlo desde Multiempresa, marcado como pendiente.
export function mapearCatalogo(
  origen: EntradaCatalogo[],
  destino: EntradaCatalogo[],
  destinoId: string,
  etiqueta: string,
  ctx: Contexto
): void {
  const porNombre = new Map<string, string>();
  const porCodigo = new Map<string, string>();
  for (const e of destino) {
    const n = normalizarClave(e.nombre);
    if (n && !porNombre.has(n)) porNombre.set(n, e.ids[0]);
    const c = normalizarClave(e.codigo);
    if (c && !porCodigo.has(c)) porCodigo.set(c, e.ids[0]);
  }
  for (const e of origen) {
    const hallado = porNombre.get(normalizarClave(e.nombre)) ??
      porCodigo.get(normalizarClave(e.codigo));
    const id = hallado ?? idCatalogo(destinoId, e.nombre);
    for (const origenId of e.ids) {
      registrar(ctx, origenId, id,
        hallado ? undefined : `${etiqueta}: ${e.nombre}`);
    }
  }
}

// ─── Plan por destino ────────────────────────────────────────────────────────

type Doc = {id: string; data: Record<string, unknown>};

type PlanMaestro = {
  maestro: Maestro;
  nuevos: {origen: Doc; id: string}[];
  existentes: number;
  sinClave: number;
  // Solo config.
  parche?: Record<string, unknown>;
  campos?: string[];
  // Solo consecutivo: último número usado en el destino tras copiar.
  contador?: number;
};

type ResultadoMaestro = {
  coleccion: string;
  nombre: string;
  tipo: string;
  nuevos: number;
  existentes: number;
  sinClave: number;
  campos: number;
  ejemplos: string[];
  creados: number;
  fallidos: number;
};

async function docsDeEmpresa(
  db: FirebaseFirestore.Firestore,
  coleccion: string,
  empresaId: string
): Promise<Doc[]> {
  const snap = await db.collection(coleccion)
    .where("empresaId", "==", empresaId).get();
  return snap.docs.map((d) => ({id: d.id, data: d.data()}));
}

function etiquetaDe(doc: Doc, maestro: Maestro): string {
  const partes = (maestro.clave ?? []).map((c) => texto(doc.data[c]))
    .filter((p) => p);
  if (partes.length) return partes.join(" · ");
  return texto(doc.data.nombre) || texto(doc.data.descripcion) || doc.id;
}

function tieneAlgo(value: unknown): boolean {
  if (vacio(value)) return false;
  if (Array.isArray(value)) return value.length > 0;
  if (esObjetoPlano(value)) return Object.keys(value).length > 0;
  return true;
}

// Primero las colecciones (para conocer sus ids en el destino) y luego la
// configuración, que puede nombrarlas. Los maestros que no se van a copiar
// solo aportan los que ya existen en el destino; lo demás que los nombre
// queda avisado como sin equivalente.
async function planear(
  db: FirebaseFirestore.Firestore,
  modulo: ModuloMaestros,
  origenDocs: Map<string, Doc[]>,
  origenConfig: Map<string, Record<string, unknown>>,
  pedidos: Set<string> | null,
  ctx: Contexto
): Promise<PlanMaestro[]> {
  const planes = new Map<string, PlanMaestro>();
  for (const maestro of modulo.maestros) {
    if (maestro.tipo !== "coleccion") continue;
    const copiar = !pedidos || pedidos.has(maestro.id);
    const destinoDocs = await docsDeEmpresa(db, maestro.id, ctx.destino);
    const idsDestino = new Set(destinoDocs.map((d) => d.id));
    const porClave = new Map<string, string>();
    const campos = maestro.clave ?? [];
    for (const d of destinoDocs) {
      const k = claveDe(d.data, campos);
      if (k && !porClave.has(k)) porClave.set(k, d.id);
    }
    const plan: PlanMaestro = {maestro, nuevos: [], existentes: 0, sinClave: 0};
    for (const doc of origenDocs.get(maestro.id) ?? []) {
      if (maestro.soloSi && !tieneAlgo(doc.data[maestro.soloSi])) continue;
      const k = claveDe(doc.data, campos);
      const propio = idDestino(doc.id, {...ctx, sinEquivalente: new Set()});
      const existente = (k ? porClave.get(k) : undefined) ??
        (propio !== undefined && idsDestino.has(propio) ? propio : undefined);
      if (existente) {
        registrar(ctx, doc.id, existente);
        plan.existentes++;
        continue;
      }
      if (!k && propio === undefined) {
        plan.sinClave++;
        continue;
      }
      if (!copiar) {
        registrar(ctx, doc.id, doc.id,
          `${maestro.nombre}: ${etiquetaDe(doc, maestro)}`);
        continue;
      }
      const id = propio === undefined ? db.collection(maestro.id).doc().id :
        idDestino(doc.id, ctx) as string;
      registrar(ctx, doc.id, id);
      if (k) porClave.set(k, id);
      idsDestino.add(id);
      plan.nuevos.push({origen: doc, id});
    }
    const cons = maestro.consecutivo;
    if (cons && plan.nuevos.length) {
      const usados = new Set(destinoDocs.map((d) =>
        texto(d.data[cons.campo]).toUpperCase()).filter((c) => c));
      const config = await db.collection(cons.config).doc(ctx.destino).get();
      let contador = Math.max(
        Number(config.data()?.[cons.contador]) || 0,
        ...[...usados].map((c) => numeroDeCodigo(c, cons.prefijo)));
      for (const nuevo of plan.nuevos) {
        const codigo = texto(nuevo.origen.data[cons.campo]);
        if (codigo && !usados.has(codigo.toUpperCase())) {
          usados.add(codigo.toUpperCase());
          contador = Math.max(contador, numeroDeCodigo(codigo, cons.prefijo));
          continue;
        }
        const libre = codigoLibre(usados, cons.prefijo, cons.digitos, contador);
        usados.add(libre.codigo.toUpperCase());
        contador = libre.numero;
        if (codigo) ctx.mapa.set(codigo, libre.codigo);
        nuevo.origen = {
          id: nuevo.origen.id,
          data: {...nuevo.origen.data, [cons.campo]: libre.codigo},
        };
      }
      plan.contador = contador;
    }
    planes.set(maestro.id, plan);
  }
  for (const maestro of modulo.maestros) {
    if (maestro.tipo !== "config") continue;
    const snap = await db.collection(maestro.id).doc(ctx.destino).get();
    const copiar = !pedidos || pedidos.has(maestro.id);
    const {parche, campos} = camposFaltantes(
      origenConfig.get(maestro.id) ?? {}, snap.data() ?? {}, maestro.omitir,
      copiar ? ctx : {...ctx, sinEquivalente: new Set()});
    if (copiar && maestro.cargosEnReglas && ctx.cargosDestino) {
      for (const cargo of cargosFaltantesEnReglas(
        parche[maestro.cargosEnReglas], ctx.cargosDestino)) {
        ctx.sinEquivalente.add(`Cargo: ${cargo}`);
      }
    }
    planes.set(maestro.id, {maestro, nuevos: [], existentes: 0, sinClave: 0,
      parche, campos});
  }
  return modulo.maestros
    .filter((m) => !pedidos || pedidos.has(m.id))
    .map((m) => planes.get(m.id) as PlanMaestro);
}

// ─── Escritura ───────────────────────────────────────────────────────────────

function urlConToken(bucket: string, ruta: string, token: string): string {
  return `https://firebasestorage.googleapis.com/v0/b/${bucket}/o/` +
    `${encodeURIComponent(ruta)}?alt=media&token=${token}`;
}

// Duplica el archivo; null si no se pudo (el destino queda con el enlace
// del origen, que sigue sirviendo mientras el origen no lo borre).
async function copiarArchivo(
  origen: string,
  destino: string
): Promise<string | null> {
  try {
    const bucket = admin.storage().bucket();
    const archivo = bucket.file(destino);
    await bucket.file(origen).copy(archivo);
    const token = randomUUID();
    await archivo.setMetadata({metadata: {firebaseStorageDownloadTokens: token}});
    return urlConToken(bucket.name, destino, token);
  } catch (e) {
    functions.logger.warn("maestros: no se pudo copiar el archivo", {origen, e});
    return null;
  }
}

function nombreSeguro(nombre: string): string {
  return (nombre || "documento.pdf").replace(/[^\w.-]/g, "_");
}

type Escritura = {
  ref: FirebaseFirestore.DocumentReference;
  data: Record<string, unknown>;
  maestro: string;
};

async function escrituras(
  db: FirebaseFirestore.Firestore,
  planes: PlanMaestro[],
  ctx: Contexto,
  actorId: string,
  origenNombre: string,
  archivos: {sinCopiar: number}
): Promise<Escritura[]> {
  const ahora = admin.firestore.FieldValue.serverTimestamp();
  const out: Escritura[] = [];
  for (const plan of planes) {
    const m = plan.maestro;
    for (const nuevo of plan.nuevos) {
      const data = remapear(nuevo.origen.data, ctx) as Record<string, unknown>;
      for (const campo of m.omitir ?? []) delete data[campo];
      data.empresaId = ctx.destino;
      data.sincronizadoDesde = {
        empresaId: ctx.origen,
        docId: nuevo.origen.id,
        por: actorId,
        at: admin.firestore.Timestamp.now(),
      };
      if ("createdAt" in data) data.createdAt = ahora;
      if ("updatedAt" in data) data.updatedAt = ahora;

      if (m.archivo) {
        const ruta = texto(nuevo.origen.data[m.archivo.ruta]);
        if (ruta) {
          const destinoRuta = rutaDestino(ruta, ctx);
          const url = destinoRuta === ruta ? null :
            await copiarArchivo(ruta, destinoRuta);
          if (url) {
            data[m.archivo.ruta] = destinoRuta;
            data[m.archivo.url] = url;
          } else {
            data[m.archivo.ruta] = ruta;
            data[m.archivo.url] = nuevo.origen.data[m.archivo.url] ?? null;
            archivos.sinCopiar++;
          }
        }
      }

      if (m.biblioteca) {
        out.push(...await escriturasBiblioteca(db, nuevo, data, ctx, actorId,
          origenNombre, archivos));
        continue;
      }
      out.push({ref: db.collection(m.id).doc(nuevo.id), data, maestro: m.id});
    }
  }
  return out;
}

async function escriturasBiblioteca(
  db: FirebaseFirestore.Firestore,
  nuevo: {origen: Doc; id: string},
  data: Record<string, unknown>,
  ctx: Contexto,
  actorId: string,
  origenNombre: string,
  archivos: {sinCopiar: number}
): Promise<Escritura[]> {
  const ahora = admin.firestore.FieldValue.serverTimestamp();
  const versiones = await db.collection("TBL_DOCUMENTOS_VERSIONES")
    .where("docId", "==", nuevo.origen.id).get();
  let elegida = versiones.docs.find((v) => v.data().esVigente === true);
  if (!elegida) {
    for (const v of versiones.docs) {
      const n = Number(v.data().numero) || 0;
      if (!elegida || n > (Number(elegida.data().numero) || 0)) elegida = v;
    }
  }
  const estado = texto(data.estado) || "vigente";
  const docRef = db.collection("TBL_DOCUMENTOS").doc(nuevo.id);
  const verRef = db.collection("TBL_DOCUMENTOS_VERSIONES").doc();
  const out: Escritura[] = [{
    ref: docRef,
    maestro: "TBL_DOCUMENTOS",
    data: {
      ...data,
      versionActual: "v1",
      estado,
      versionVigenteId: elegida ? verRef.id : null,
      creadoPor: actorId,
      copiadoDe: {
        empresaId: ctx.origen,
        docId: nuevo.origen.id,
        versionId: elegida?.id ?? null,
        por: actorId,
      },
      createdAt: ahora,
      updatedAt: ahora,
    },
  }];
  if (!elegida) return out;

  const ver = elegida.data();
  const pathOrigen = texto(ver.pathPdf);
  let urlPdf: unknown = texto(ver.urlPdf) || null;
  let pathPdf: string | null = pathOrigen || null;
  if (pathOrigen) {
    const destino = `documentos/${ctx.destino}/${nuevo.id}/v1/` +
      `${Date.now()}_${nombreSeguro(texto(ver.nombreArchivo))}`;
    const url = await copiarArchivo(pathOrigen, destino);
    if (url) {
      urlPdf = url;
      pathPdf = destino;
    }
  }
  if (!pathPdf || pathPdf === pathOrigen) archivos.sinCopiar++;
  out.push({
    ref: verRef,
    maestro: "TBL_DOCUMENTOS_VERSIONES",
    data: {
      ...(remapear(ver, ctx) as Record<string, unknown>),
      docId: nuevo.id,
      empresaId: ctx.destino,
      numero: 1,
      etiqueta: "v1",
      urlPdf,
      pathPdf,
      subidoPor: actorId,
      subidoEn: ahora,
      createdAt: ahora,
      updatedAt: ahora,
    },
  });
  out.push({
    ref: db.collection("TBL_DOCUMENTOS_FLUJO").doc(),
    maestro: "TBL_DOCUMENTOS_FLUJO",
    data: {
      docId: nuevo.id,
      versionId: verRef.id,
      empresaId: ctx.destino,
      accion: "copiado",
      desde: estado,
      hacia: estado,
      realizadoPor: actorId,
      realizadoEn: ahora,
      observacion: `Copiado desde la biblioteca de ${origenNombre}`,
    },
  });
  return out;
}

// ─── Función ─────────────────────────────────────────────────────────────────

async function nombreEmpresa(
  db: FirebaseFirestore.Firestore,
  id: string
): Promise<string> {
  try {
    const snap = await db.collection("TBL_EMPRESAS").doc(id).get();
    return texto(snap.data()?.nombre) || id;
  } catch (_) {
    return id;
  }
}

export const adminSincronizarMaestros = functions
  .region("us-central1")
  .runWith({timeoutSeconds: 540, memory: "1GB"})
  .https.onCall(async (data: any, context) => {
    const caller = await requireAdmin(data, context);
    const origen = caller.empresaId;
    const modulo = MODULOS_MAESTROS.find((m) => m.id === texto(data?.modulo));
    if (!modulo) {
      throw new functions.https.HttpsError("invalid-argument", "Módulo no válido.");
    }
    const destinos = [...new Set(
      (Array.isArray(data?.destinos) ? data.destinos : [])
        .map((d: unknown) => texto(d))
        .filter((d: string) => d && d !== origen)
    )] as string[];
    if (!destinos.length || destinos.length > 20) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Elige entre 1 y 20 empresas destino."
      );
    }
    const pedidos = Array.isArray(data?.maestros) ?
      new Set((data.maestros as unknown[]).map((m) => texto(m))) : null;
    const ejecutar = data?.ejecutar === true;
    const db = admin.firestore();

    const nombres = new Map<string, string>();
    for (const id of [origen, ...destinos]) {
      nombres.set(id, await nombreEmpresa(db, id));
    }
    // Hay que ser Administración también en cada destino.
    for (const destino of destinos) {
      try {
        await requireAdmin({empresaId: destino}, context);
      } catch (_) {
        throw new functions.https.HttpsError(
          "permission-denied",
          `No eres Administración en ${nombres.get(destino)}.`
        );
      }
    }

    // Lo del origen se lee una vez para todos los destinos.
    const origenDocs = new Map<string, Doc[]>();
    const origenConfig = new Map<string, Record<string, unknown>>();
    for (const m of modulo.maestros) {
      if (m.tipo === "config") {
        const snap = await db.collection(m.id).doc(origen).get();
        origenConfig.set(m.id, snap.data() ?? {});
      } else {
        origenDocs.set(m.id, await docsDeEmpresa(db, m.id, origen));
      }
    }
    const catalogosOrigen = await Promise.all(CATALOGOS.map(async (c) =>
      entradasCatalogo(await docsDeEmpresa(db, c.coleccion, origen), c.campoId,
        origen)));

    const resultados = [];
    let totalCreados = 0;
    let totalFallidos = 0;
    for (const destino of destinos) {
      const ctx: Contexto = {
        origen, destino,
        mapa: new Map(), pendientes: new Map(), sinEquivalente: new Set(),
      };
      for (let i = 0; i < CATALOGOS.length; i++) {
        const c = CATALOGOS[i];
        const destinoCat = entradasCatalogo(
          await docsDeEmpresa(db, c.coleccion, destino), c.campoId, destino);
        mapearCatalogo(catalogosOrigen[i], destinoCat, destino, c.etiqueta, ctx);
        if (c.coleccion === "TBL_CARGOS") {
          ctx.cargosDestino = new Set(
            destinoCat.map((e) => normalizarClave(e.nombre)));
        }
      }
      const planes = await planear(db, modulo, origenDocs, origenConfig,
        pedidos, ctx);

      // La vista previa también avisa lo que quedaría sin equivalente.
      for (const plan of planes) {
        for (const nuevo of plan.nuevos) remapear(nuevo.origen.data, ctx);
      }

      const creados = new Map<string, number>();
      const fallidos = new Map<string, number>();
      const archivos = {sinCopiar: 0};
      if (ejecutar) {
        const lista = await escrituras(db, planes, ctx, caller.userDocId,
          nombres.get(origen) ?? origen, archivos);
        const writer = db.bulkWriter();
        writer.onWriteError((error) =>
          error.code !== 6 && error.failedAttempts < 3);
        const pendientes = lista.map((e) => {
          const maestro = e.maestro === "TBL_DOCUMENTOS_VERSIONES" ||
            e.maestro === "TBL_DOCUMENTOS_FLUJO" ? null : e.maestro;
          // `create` nunca pisa: si alguien lo creó entre la vista previa y
          // ahora, falla y se cuenta.
          return writer.create(e.ref, e.data).then(() => {
            if (maestro) creados.set(maestro, (creados.get(maestro) ?? 0) + 1);
          }).catch(() => {
            if (maestro) fallidos.set(maestro, (fallidos.get(maestro) ?? 0) + 1);
          });
        });
        for (const plan of planes) {
          const m = plan.maestro;
          if (m.tipo === "config" && plan.campos?.length) {
            const ref = db.collection(m.id).doc(destino);
            pendientes.push(writer.set(ref, {
              ...plan.parche,
              empresaId: destino,
              sincronizadoDesde: {
                empresaId: origen,
                por: caller.userDocId,
                at: admin.firestore.Timestamp.now(),
              },
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            }, {merge: true}).then(() => {
              creados.set(m.id, plan.campos?.length ?? 0);
            }).catch(() => {
              fallidos.set(m.id, plan.campos?.length ?? 0);
            }));
          }
          if (m.consecutivo && plan.contador !== undefined) {
            pendientes.push(writer.set(
              db.collection(m.consecutivo.config).doc(destino),
              {[m.consecutivo.contador]: plan.contador},
              {merge: true}
            ).then(() => undefined).catch(() => undefined));
          }
        }
        await writer.close();
        await Promise.all(pendientes);
      }

      const maestros: ResultadoMaestro[] = planes.map((p) => ({
        coleccion: p.maestro.id,
        nombre: p.maestro.nombre,
        tipo: p.maestro.tipo,
        nuevos: p.nuevos.length,
        existentes: p.existentes,
        sinClave: p.sinClave,
        campos: p.campos?.length ?? 0,
        ejemplos: p.maestro.tipo === "config" ?
          (p.campos ?? []).slice(0, 5) :
          p.nuevos.slice(0, 5).map((n) => etiquetaDe(n.origen, p.maestro)),
        creados: creados.get(p.maestro.id) ?? 0,
        fallidos: fallidos.get(p.maestro.id) ?? 0,
      }));
      for (const m of maestros) {
        totalCreados += m.creados;
        totalFallidos += m.fallidos;
      }
      resultados.push({
        empresaId: destino,
        nombre: nombres.get(destino) ?? destino,
        maestros,
        sinEquivalente: [...ctx.sinEquivalente].sort().slice(0, 50),
        archivosSinCopiar: archivos.sinCopiar,
      });

      if (ejecutar) {
        await db.collection("TBL_MIGRATIONS_LOGS").add({
          adminUserId: caller.userDocId,
          empresaId: destino,
          action: "recibirMaestros",
          scanned: maestros.reduce((s, m) => s + m.nuevos + m.campos, 0),
          updated: maestros.reduce((s, m) => s + m.creados, 0),
          dryRun: false,
          extra: {
            modulo: modulo.id,
            origen,
            maestros: maestros.map((m) => ({coleccion: m.coleccion,
              creados: m.creados, fallidos: m.fallidos})),
          },
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
    }

    if (ejecutar) {
      await db.collection("TBL_MIGRATIONS_LOGS").add({
        adminUserId: caller.userDocId,
        empresaId: origen,
        action: "sincronizarMaestros",
        scanned: resultados.reduce((s, r) => s + r.maestros.reduce(
          (t, m) => t + m.nuevos + m.campos, 0), 0),
        updated: totalCreados,
        dryRun: false,
        extra: {
          modulo: modulo.id,
          destinos,
          maestros: pedidos ? [...pedidos] : modulo.maestros.map((m) => m.id),
          fallidos: totalFallidos,
        },
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
    return {modulo: modulo.id, ejecutado: ejecutar, destinos: resultados};
  });
