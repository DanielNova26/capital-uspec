/**
 * Interventoría: qué cargos aprueban un hallazgo y si una persona los cumple
 * (21 oct 2026).
 *
 * Réplica en servidor de la regla que usan la sugerencia y la asignación en
 * la app (`afinidadCargo`, `nivelDeCargo` y `kInterventoriaCargoAlternativas`
 * en `lib/interventoria/interventoria_numerales_catalogo.dart`, y
 * `cargosAprobadoresDe` en `interventoria_service.dart`). El servidor no
 * elige a nadie: valida que la persona propuesta por la app cumpla el cargo
 * que el maestro vigente pide para ese numeral. Las pruebas de Dart y de
 * funciones leen `functions/test/fixtures/interventoria_cargos.json`, y una
 * prueba de Dart compara la matriz de este archivo con la de la app.
 */

type Datos = Record<string, any>;

const texto = (v: unknown): string => String(v ?? "").trim();

/**
 * Minúsculas y sin tildes, igual que `normalizarCargo` en la app.
 * @param {unknown} v Cargo escrito a mano.
 * @return {string} Cargo normalizado.
 */
export function normalizarCargo(v: unknown): string {
  return texto(v).toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "");
}

/** Palabra de rango → nivel. Misma tabla que `kInterventoriaNivelPorPalabra`. */
export const NIVEL_POR_PALABRA: Record<string, string> = {
  director: "director", directora: "director", direccion: "director",
  subdirector: "subdirector", subdirectora: "subdirector", subdireccion: "subdirector",
  gerente: "gerente", gerenta: "gerente", gerencia: "gerente",
  subgerente: "subgerente", subgerencia: "subgerente",
  coordinador: "coordinador", coordinadora: "coordinador", coordinacion: "coordinador",
  supervisor: "supervisor", supervisora: "supervisor", supervision: "supervisor",
  jefe: "jefe", jefa: "jefe", jefatura: "jefe",
  lider: "lider", lideresa: "lider",
  responsable: "responsable",
  encargado: "encargado", encargada: "encargado",
  analista: "analista",
  auxiliar: "auxiliar",
  asistente: "asistente",
  profesional: "profesional",
  tecnico: "tecnico", tecnica: "tecnico", tecnologo: "tecnico", tecnologa: "tecnico",
  practicante: "aprendiz", aprendiz: "aprendiz",
  secretario: "secretario", secretaria: "secretario",
  administrador: "administrador", administradora: "administrador",
  tesorero: "tesorero", tesorera: "tesorero",
  nutricionista: "nutricionista",
  contador: "contador", contadora: "contador",
  operario: "operario", operaria: "operario",
};

/** Alternativas de área. Misma tabla que `kInterventoriaCargoAlternativas`. */
export const CARGO_ALTERNATIVAS: Record<string, string[][]> = {
  "Administrador": [[]],
  "Analista de Compras": [["compras"]],
  "Coordinador de calidad": [["calidad"]],
  "Coordinador de mantenimiento": [["mantenimiento"]],
  "Director de operaciones": [["operacion"], ["operativ"]],
  "Director de talento humano": [["talento", "human"], ["gestion", "human"], ["recursos", "human"]],
  "Nutricionista": [[]],
  "Supervisor de Hse": [["hse"], ["sst"], ["seguridad", "salud"], ["seguridad"]],
  "Tesorero": [[]],
  "Coordinadora de Nutrición": [["nutricion"]],
  "Dirección de talento humano": [["talento", "human"], ["gestion", "human"], ["recursos", "human"]],
  "Director de calidad": [["calidad"]],
  "Gerencia": [["general"], ["="]],
};

const VACIAS = new Set(["de", "del", "la", "las", "los", "el", "y", "e", "en", "para", "por", "con"]);
const NUMERO = /^\d+$/;

export function palabrasCargo(cargo: unknown): string[] {
  return normalizarCargo(cargo).split(/[^a-z0-9]+/).filter(Boolean);
}

export function nivelDeCargo(cargo: unknown): string {
  for (const palabra of palabrasCargo(cargo)) {
    const nivel = NIVEL_POR_PALABRA[palabra];
    if (nivel) return nivel;
  }
  return "";
}

const tieneFragmento = (palabras: string[], fragmento: string) =>
  NUMERO.test(fragmento) ? palabras.includes(fragmento) : palabras.some((p) => p.startsWith(fragmento));

/**
 * Igual que `afinidadCargo` de la app: índice de la alternativa (-1 = mismo
 * cargo) o null si la persona no tiene el cargo. El nivel se exige siempre.
 * @param {string} cargoMatriz Cargo que pide el maestro.
 * @param {string} cargoUsuario Cargo real de la persona en la empresa.
 * @return {number|null} Afinidad o null.
 */
export function afinidadCargo(cargoMatriz: string, cargoUsuario: string): number | null {
  const objetivo = normalizarCargo(cargoUsuario);
  if (!objetivo) return null;
  const nivel = nivelDeCargo(cargoMatriz);
  if (nivel && nivelDeCargo(cargoUsuario) !== nivel) return null;
  if (objetivo === normalizarCargo(cargoMatriz)) return -1;
  const palabras = palabrasCargo(cargoUsuario);
  const alternativas = CARGO_ALTERNATIVAS[cargoMatriz];
  if (!alternativas) {
    const area = palabrasCargo(cargoMatriz).filter((p) => !NIVEL_POR_PALABRA[p] && !VACIAS.has(p) &&
      (p.length > 2 || NUMERO.test(p)));
    if (!area.length && !nivel) return null;
    return area.every((p) => tieneFragmento(palabras, p)) ? 0 : null;
  }
  for (let i = 0; i < alternativas.length; i++) {
    const alternativa = alternativas[i];
    if (alternativa.length === 1 && alternativa[0] === "=") {
      if (palabras.every((p) => NIVEL_POR_PALABRA[p] || VACIAS.has(p))) return i;
      continue;
    }
    if (alternativa.every((f) => tieneFragmento(palabras, f))) return i;
  }
  return null;
}

/**
 * Aprobador de la matriz incluida del acta regular, agrupado por cargo.
 * Copia de `kInterventoriaResponsabilidadPorNumeral`; la prueba
 * `interventoria_aprobador_maestro_test.dart` falla si se separan.
 */
export const APROBADOR_MATRIZ_REGULAR: Record<string, string[]> = {
  "Director de operaciones": ["1.1", "1.2", "1.3", "2.1", "2.2", "2.7", "2.11", "2.12", "2.13", "2.14",
    "2.15", "2.16", "3.3", "3.4", "3.5", "3.6", "3.7", "3.8", "3.9", "3.10", "3.11", "3.12", "3.13", "4.6",
    "4.7", "4.8", "4.9", "4.10", "5.3", "5.6", "5.7", "5.8", "5.9", "5.10", "5.11", "6.1", "6.2", "6.3", "6.4",
    "6.5", "6.6", "6.7", "6.8", "6.9", "6.10", "6.11", "6.12", "6.13", "6.14", "6.15", "6.16", "6.27", "7.3",
    "7.4", "7.5", "7.6", "7.7", "7.10", "8.2", "8.3", "8.4", "8.5", "8.6", "8.7", "8.8", "8.12", "8.13", "8.14",
    "8.16", "8.17", "9.1", "9.2", "9.3", "9.4", "9.5", "10.2", "10.4", "10.5", "10.11", "10.12", "10.13",
    "10.14", "10.15", "10.19", "10.21"],
  "Gerencia": ["2.3", "2.4", "2.5", "2.6", "2.8", "2.9", "2.10", "2.17", "3.2", "4.1", "4.2", "4.3", "4.4",
    "4.5", "7.1", "7.2", "7.8", "7.11", "8.10", "8.11", "10.20"],
  "Director de calidad": ["5.1", "5.2", "5.4", "5.5", "8.1", "8.15", "8.18", "10.1", "10.3", "10.6", "10.7",
    "10.8", "10.9", "10.10", "10.16", "10.17", "10.18"],
  "Coordinadora de Nutrición": ["6.17", "6.18", "6.19", "6.20", "6.21", "6.22", "6.23", "6.24", "6.25", "6.26"],
  "Dirección de talento humano": ["11.1", "11.2", "11.3", "11.4", "11.5", "11.6", "11.7", "11.8"],
};

const APROBADOR_POR_NUMERAL: Record<string, string> = Object.fromEntries(
  Object.entries(APROBADOR_MATRIZ_REGULAR).flatMap(([cargo, numerales]) => numerales.map((n) => [n, cargo]))
);

const CATALOGO_PROPIO = new Set(["INFRAESTRUCTURA", "ESTACION_POLICIA", "ALCALDIA_PLANTA", "ALCALDIA_ESTACION_POLICIA"]);

export function normalizarNumeralActa(v: unknown): string {
  const m = /(\d{1,2})\s*\.\s*(\d{1,2})/.exec(texto(v));
  return m ? `${m[1]}.${m[2]}` : "";
}

/**
 * `InterventoriaHallazgo.numeralParaMatriz`: el ordinal del formulario no
 * es un numeral del acta.
 * @param {Datos} h Hallazgo.
 * @return {string} Numeral normalizado o vacío.
 */
export function numeralParaMatriz(h: Datos): string {
  if (texto(h.numeralActa)) return normalizarNumeralActa(h.numeralActa);
  if (texto(h.fuente) === "acta") return "";
  return normalizarNumeralActa(h.numeroHallazgo);
}

const familiaReglas = (tipo: string) => CATALOGO_PROPIO.has(tipo) ? tipo : "REGULAR";

function cargosDeRegla(lista: unknown, unico: unknown): string[] {
  if (Array.isArray(lista)) {
    const cargos = lista.map(texto).filter(Boolean);
    if (cargos.length) return cargos;
  }
  return texto(unico) ? [texto(unico)] : [];
}

/**
 * Cargos que aprueban el numeral del hallazgo según el maestro vigente: la
 * regla guardada de la empresa y, en el acta regular, la matriz incluida.
 * @param {Datos} h Hallazgo.
 * @param {Datos} reglas `TBL_INTERVENTORIA_CONFIG/{empresa}.reglasSubsanacion`.
 * @return {string[]} Cargos en orden de la regla.
 */
export function cargosAprobadoresDe(h: Datos, reglas: Datos): string[] {
  const numeral = numeralParaMatriz(h);
  if (!numeral) return [];
  const tipo = texto(h.tipoActa).toUpperCase() || "REGULAR";
  const familia = familiaReglas(tipo);
  let regla = reglas?.[`${familia}::${numeral}`];
  if (!(regla && typeof regla === "object") && familia === "REGULAR") regla = reglas?.[numeral];
  if (regla && typeof regla === "object") return cargosDeRegla(regla.aprobadores, regla.aprobador);
  if (CATALOGO_PROPIO.has(tipo)) return [];
  return APROBADOR_POR_NUMERAL[numeral] ? [APROBADOR_POR_NUMERAL[numeral]] : [];
}

/**
 * ¿El cargo real cumple alguno de los cargos que pide el maestro?
 * @param {string[]} cargos Cargos de la regla.
 * @param {string} cargoPersona Cargo real de la persona.
 * @return {boolean} true si cumple alguno.
 */
export function cumpleCargo(cargos: string[], cargoPersona: string): boolean {
  return cargos.some((c) => afinidadCargo(c, cargoPersona) !== null);
}
