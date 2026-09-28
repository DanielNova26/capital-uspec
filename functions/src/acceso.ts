/**
 * Quién puede entrar a la app. Espejo de `motivoAccesoBloqueado` y
 * `empresasSeleccionables` en lib/utils/user_company.dart: el servidor y la
 * app deben responder lo mismo, o un inhabilitado entra por uno de los dos.
 *
 * Regla: un inhabilitado no entra hasta que lo habiliten otra vez.
 * - Cuenta inhabilitada: `activo: false` (interruptor de Administración) o
 *   un `estado` global (o `status`) distinto de activo.
 * - Inhabilitado por Talento Humano en todas sus empresas
 *   (`empresasDetalle.{empresa}.estadoLaboral` o `estado` = inactivo).
 *   Si queda habilitado en alguna, entra solo a esa.
 * - Una empresa apagada por un traslado (`activo: false` en su bloque) no es
 *   un retiro laboral, pero tampoco permite entrar. Si todas están apagadas,
 *   ninguna se reactiva por defecto.
 */

type Datos = Record<string, unknown>;

export const MENSAJE_CUENTA_INHABILITADA =
  "Tu usuario está inhabilitado. Comunícate con Talento Humano o con el " +
  "administrador para que te habiliten de nuevo.";

export const MENSAJE_INHABILITADO_EN_EMPRESAS =
  "Estás inhabilitado en tu empresa. Comunícate con Talento Humano para " +
  "que te habiliten de nuevo.";

function texto(value: unknown): string {
  return (value ?? "").toString().trim().toLowerCase();
}

function esMapa(value: unknown): value is Datos {
  return !!value && typeof value === "object" && !Array.isArray(value);
}

function bloque(usuario: Datos, empresaId: string): Datos | null {
  const detalle = usuario.empresasDetalle;
  if (!esMapa(detalle)) return null;
  const b = detalle[empresaId];
  return esMapa(b) ? b : null;
}

// La cuenta está apagada para toda la app.
export function cuentaInhabilitada(usuario: Datos): boolean {
  if (usuario.activo === false) return true;
  const estado = texto(usuario.estado);
  const global = estado || texto(usuario.status);
  return global !== "" && global !== "activo" && global !== "active";
}

// Talento Humano la inhabilitó en [empresaId].
export function inhabilitadaEn(usuario: Datos, empresaId: string): boolean {
  const b = bloque(usuario, empresaId);
  if (!b) return false;
  for (const clave of ["estadoLaboral", "estado"]) {
    const v = texto(b[clave]);
    if (v) return v === "inactivo";
  }
  return false;
}

// Empresas de la persona, sin repetir: `empresas` y `empresasDetalle`.
export function empresasDe(usuario: Datos): string[] {
  const out: string[] = [];
  const agregar = (v: unknown) => {
    const id = (v ?? "").toString().trim();
    if (id && !out.includes(id)) out.push(id);
  };
  if (Array.isArray(usuario.empresas)) usuario.empresas.forEach(agregar);
  if (esMapa(usuario.empresasDetalle)) {
    Object.keys(usuario.empresasDetalle).forEach(agregar);
  }
  if (out.length === 0) agregar(usuario.empresaId);
  return out;
}

// Empresas a las que puede entrar. Vacío = no entra a ninguna.
export function empresasSeleccionables(usuario: Datos): string[] {
  if (cuentaInhabilitada(usuario)) return [];
  const todas = empresasDe(usuario);
  return todas.filter(
    (e) => bloque(usuario, e)?.activo !== false && !inhabilitadaEn(usuario, e)
  );
}

// Por qué no puede entrar a la app; null si puede.
export function motivoAccesoBloqueado(usuario: Datos): string | null {
  if (cuentaInhabilitada(usuario)) return MENSAJE_CUENTA_INHABILITADA;
  if (empresasDe(usuario).length > 0 &&
      empresasSeleccionables(usuario).length === 0) {
    return MENSAJE_INHABILITADO_EN_EMPRESAS;
  }
  return null;
}
