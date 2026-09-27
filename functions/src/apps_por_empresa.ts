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

type Datos = Record<string, unknown>;

function textList(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value
    .map((item) => (item ?? "").toString().trim())
    .filter((item) => item.length > 0);
}

function detalleDeEmpresa(user: Datos, empresaId: string): Datos | null {
  const detalle = user.empresasDetalle;
  if (!detalle || typeof detalle !== "object" || Array.isArray(detalle)) {
    return null;
  }
  const bloque = (detalle as Datos)[empresaId];
  return bloque && typeof bloque === "object" && !Array.isArray(bloque) ?
    bloque as Datos :
    null;
}

/**
 * ¿La raíz del usuario es de [empresaId]? Es la copia de la empresa
 * principal; sin principal escrita, vale si tiene una sola empresa o ninguna.
 * @param {Datos} user Documento de TBL_USUARIOS.
 * @param {string} empresaId Empresa que se mira.
 * @return {boolean} true si la raíz describe a esa empresa.
 */
export function raizEsDeEmpresa(user: Datos, empresaId: string): boolean {
  const principal = (user.empresaId ?? "").toString().trim();
  if (principal) return principal === empresaId;
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
export function appsDeEmpresa(user: Datos, empresaId: string): string[] {
  const bloque = detalleDeEmpresa(user, empresaId);
  if (user.appsPorEmpresa === true) {
    if (bloque && Array.isArray(bloque.apps)) return textList(bloque.apps);
    return raizEsDeEmpresa(user, empresaId) ? textList(user.apps) : [];
  }
  return [...new Set([...textList(user.apps), ...textList(bloque?.apps)])];
}
