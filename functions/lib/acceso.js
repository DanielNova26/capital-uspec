"use strict";
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
 *   una inhabilitación: si todas están apagadas y ninguna inhabilitada, no se
 *   bloquea (dato a medias; la app lo resuelve).
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.MENSAJE_INHABILITADO_EN_EMPRESAS = exports.MENSAJE_CUENTA_INHABILITADA = void 0;
exports.cuentaInhabilitada = cuentaInhabilitada;
exports.inhabilitadaEn = inhabilitadaEn;
exports.empresasDe = empresasDe;
exports.empresasSeleccionables = empresasSeleccionables;
exports.motivoAccesoBloqueado = motivoAccesoBloqueado;
exports.MENSAJE_CUENTA_INHABILITADA = "Tu usuario está inhabilitado. Comunícate con Talento Humano o con el " +
    "administrador para que te habiliten de nuevo.";
exports.MENSAJE_INHABILITADO_EN_EMPRESAS = "Estás inhabilitado en tu empresa. Comunícate con Talento Humano para " +
    "que te habiliten de nuevo.";
function texto(value) {
    return (value ?? "").toString().trim().toLowerCase();
}
function esMapa(value) {
    return !!value && typeof value === "object" && !Array.isArray(value);
}
function bloque(usuario, empresaId) {
    const detalle = usuario.empresasDetalle;
    if (!esMapa(detalle))
        return null;
    const b = detalle[empresaId];
    return esMapa(b) ? b : null;
}
// La cuenta está apagada para toda la app.
function cuentaInhabilitada(usuario) {
    if (usuario.activo === false)
        return true;
    const estado = texto(usuario.estado);
    const global = estado || texto(usuario.status);
    return global !== "" && global !== "activo" && global !== "active";
}
// Talento Humano la inhabilitó en [empresaId].
function inhabilitadaEn(usuario, empresaId) {
    const b = bloque(usuario, empresaId);
    if (!b)
        return false;
    for (const clave of ["estadoLaboral", "estado"]) {
        const v = texto(b[clave]);
        if (v)
            return v === "inactivo";
    }
    return false;
}
// Empresas de la persona, sin repetir: `empresas` y `empresasDetalle`.
function empresasDe(usuario) {
    const out = [];
    const agregar = (v) => {
        const id = (v ?? "").toString().trim();
        if (id && !out.includes(id))
            out.push(id);
    };
    if (Array.isArray(usuario.empresas))
        usuario.empresas.forEach(agregar);
    if (esMapa(usuario.empresasDetalle)) {
        Object.keys(usuario.empresasDetalle).forEach(agregar);
    }
    if (out.length === 0)
        agregar(usuario.empresaId);
    return out;
}
// Empresas a las que puede entrar. Vacío = no entra a ninguna.
function empresasSeleccionables(usuario) {
    const todas = empresasDe(usuario);
    const abiertas = todas.filter((e) => bloque(usuario, e)?.activo !== false && !inhabilitadaEn(usuario, e));
    if (abiertas.length > 0)
        return abiertas;
    if (todas.some((e) => inhabilitadaEn(usuario, e)))
        return [];
    return todas;
}
// Por qué no puede entrar a la app; null si puede.
function motivoAccesoBloqueado(usuario) {
    if (cuentaInhabilitada(usuario))
        return exports.MENSAJE_CUENTA_INHABILITADA;
    if (empresasDe(usuario).length > 0 &&
        empresasSeleccionables(usuario).length === 0) {
        return exports.MENSAJE_INHABILITADO_EN_EMPRESAS;
    }
    return null;
}
