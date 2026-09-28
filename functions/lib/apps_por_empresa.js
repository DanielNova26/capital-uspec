"use strict";
/**
 * Módulos que una persona tiene en una empresa. Espejo de `extractUserApps`
 * en lib/utils/user_company.dart: la app y las funciones deben responder lo
 * mismo, o la pantalla muestra un módulo que el servidor niega (o al revés).
 *
 * - Con `appsPorEmpresa: true` (módulos ya escritos empresa por empresa):
 *   la lista de la empresa y nada más. Sin lista propia, la general solo
 *   vale en la empresa principal.
 * - Sin la marca (datos de antes): la lista general más la de la empresa.
 *   Esa suma era la que pasaba módulos de una razón social a otra.
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.raizEsDeEmpresa = raizEsDeEmpresa;
exports.appsDeEmpresa = appsDeEmpresa;
function textList(value) {
    if (!Array.isArray(value))
        return [];
    return value
        .map((item) => (item ?? "").toString().trim())
        .filter((item) => item.length > 0);
}
function detalleDeEmpresa(user, empresaId) {
    const detalle = user.empresasDetalle;
    if (!detalle || typeof detalle !== "object" || Array.isArray(detalle)) {
        return null;
    }
    const bloque = detalle[empresaId];
    return bloque && typeof bloque === "object" && !Array.isArray(bloque) ?
        bloque :
        null;
}
/**
 * ¿La raíz del usuario es de [empresaId]? Es la copia de la empresa
 * principal; sin principal escrita, vale si tiene una sola empresa o ninguna.
 * @param {Datos} user Documento de TBL_USUARIOS.
 * @param {string} empresaId Empresa que se mira.
 * @return {boolean} true si la raíz describe a esa empresa.
 */
function raizEsDeEmpresa(user, empresaId) {
    const principal = (user.empresaId ?? "").toString().trim();
    if (principal)
        return principal === empresaId;
    const empresas = new Set(textList(user.empresas));
    const detalle = user.empresasDetalle;
    if (detalle && typeof detalle === "object" && !Array.isArray(detalle)) {
        Object.keys(detalle).forEach((k) => empresas.add(k));
    }
    return empresas.size === 0 ||
        (empresas.size === 1 && empresas.has(empresaId));
}
/**
 * Módulos de la persona en la empresa.
 * @param {Datos} user Documento de TBL_USUARIOS.
 * @param {string} empresaId Empresa que se mira.
 * @return {string[]} appIds tal como están guardados.
 */
function appsDeEmpresa(user, empresaId) {
    const bloque = detalleDeEmpresa(user, empresaId);
    if (user.appsPorEmpresa === true) {
        if (bloque && Array.isArray(bloque.apps))
            return textList(bloque.apps);
        return raizEsDeEmpresa(user, empresaId) ? textList(user.apps) : [];
    }
    return [...new Set([...textList(user.apps), ...textList(bloque?.apps)])];
}
