// Ingresos a la app: quién nunca ha entrado y desde qué dispositivo entró
// (29 sep 2026). Lógica pura, sin Firestore, para probarla sola.

// Clave con la que entra quien nunca ha iniciado sesión. Debe cambiarla al
// entrar (needsPasswordChange), con al menos 8 caracteres.
export const CLAVE_INICIAL = "123456";

type Datos = Record<string, unknown>;

function texto(value: unknown, max = 160): string {
  return (value ?? "").toString().trim().slice(0, max);
}

function millis(value: unknown): number | null {
  const ts = value as {toMillis?: () => number} | null;
  const ms = ts?.toMillis?.();
  if (typeof ms === "number" && ms > 0) return ms;
  if (typeof value === "number" && value > 0) return value;
  return null;
}

// El ingreso más reciente que dejó rastro: el que escribe la app al
// entrar (raíz y ficha de cada empresa) y el que marca el servidor.
export function ultimoIngresoMs(raw: Datos): number | null {
  const fechas: Array<number | null> = [
    millis(raw.lastLoginAt),
    millis(raw.ultimoIngresoAt),
    millis(raw.ultimoIngresoSeguroAt),
  ];
  const detalle = raw.empresasDetalle;
  if (detalle && typeof detalle === "object" && !Array.isArray(detalle)) {
    for (const bloque of Object.values(detalle as Datos)) {
      if (bloque && typeof bloque === "object") {
        fechas.push(millis((bloque as Datos).lastLoginAt));
      }
    }
  }
  const validas = fechas.filter((f): f is number => f !== null);
  return validas.length ? Math.max(...validas) : null;
}

// ¿Nunca ha iniciado sesión? Sin ningún ingreso registrado y sin una clave
// propia: o no tiene credencial segura, o la que tiene es temporal (debe
// cambiarla). Quien ya puso su propia clave no entra aquí aunque falte el
// registro del ingreso: asignarle la inicial le cambiaría una clave que
// conoce.
export function nuncaHaIniciadoSesion(raw: Datos, tieneCredencial: boolean): boolean {
  if (ultimoIngresoMs(raw) !== null) return false;
  return !tieneCredencial || raw.needsPasswordChange === true;
}

export type Dispositivo = {
  tipo: "computador" | "celular" | "tablet" | "desconocido";
  marca: string;
  modelo: string;
  sistema: string;
  navegador: string;
  app: boolean;
  descripcion: string;
};

const TIPOS = new Set(["computador", "celular", "tablet", "desconocido"]);

// Dispositivo de un ingreso o del último ingreso de una persona. Los
// registros anteriores al 29 sep 2026 solo traen `platform`/`isWeb`.
export function dispositivoDe(raw: Datos): Dispositivo {
  const d = raw.dispositivo ?? raw.lastLoginDevice;
  if (d && typeof d === "object" && !Array.isArray(d)) {
    const m = d as Datos;
    const tipo = texto(m.tipo, 20);
    return {
      tipo: (TIPOS.has(tipo) ? tipo : "desconocido") as Dispositivo["tipo"],
      marca: texto(m.marca, 60),
      modelo: texto(m.modelo, 80),
      sistema: texto(m.sistema, 60),
      navegador: texto(m.navegador, 40),
      app: m.app === true,
      descripcion: texto(m.descripcion, 200),
    };
  }
  const plataforma = texto(raw.platform ?? raw.lastLoginPlatform, 20).toLowerCase();
  const web = raw.isWeb === true || raw.lastLoginIsWeb === true || plataforma === "web";
  if (!plataforma) {
    return {tipo: "desconocido", marca: "", modelo: "", sistema: "",
      navegador: "", app: false, descripcion: ""};
  }
  if (web) {
    return {tipo: "desconocido", marca: "", modelo: "", sistema: "",
      navegador: "Navegador", app: false,
      descripcion: "Navegador (sin detalle del equipo)"};
  }
  if (plataforma === "android" || plataforma === "ios") {
    const sistema = plataforma === "ios" ? "iOS" : "Android";
    return {tipo: "celular", marca: plataforma === "ios" ? "Apple" : "",
      modelo: "", sistema, navegador: "", app: true,
      descripcion: `Celular ${sistema} · App`};
  }
  const sistemas: Record<string, string> = {
    windows: "Windows", macos: "macOS", linux: "Linux",
  };
  const sistema = sistemas[plataforma] || plataforma;
  return {tipo: "computador", marca: "", modelo: "", sistema, navegador: "",
    app: true, descripcion: `Computador ${sistema} · App`};
}

// Quién creó a la persona, si la creación lo dejó escrito.
export function creadoPorDe(raw: Datos): string {
  for (const campo of ["creadoPor", "createdBy", "registradoPor"]) {
    const valor = texto(raw[campo], 512);
    if (valor) return valor;
  }
  return "";
}

// Empresas a las que pertenece una persona recién creada.
export function empresasDe(raw: Datos): string[] {
  const out = new Set<string>();
  const principal = texto(raw.empresaId, 160);
  if (principal) out.add(principal);
  if (Array.isArray(raw.empresas)) {
    for (const e of raw.empresas) {
      const id = texto(e, 160);
      if (id) out.add(id);
    }
  }
  return [...out];
}
