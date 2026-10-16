// Control operativo de tiempo. No liquida salarios ni recargos legales.
export type BioData = Record<string, any>;
export const diaBio = (ms: number): string => new Date(ms - 5 * 3600000).toISOString().slice(0, 10);
export function fechaBio(dia: string, minutos = 0): number {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(dia)) throw new Error("Fecha inválida.");
  const ms = Date.parse(`${dia}T05:00:00Z`);
  if (!Number.isFinite(ms) || diaBio(ms) !== dia) throw new Error("Fecha inválida.");
  return ms + minutos * 60000;
}
export function validarHorario(h: BioData): BioData {
  const nombre = String(h.nombre || "").trim();
  if (!nombre || nombre.length > 100) throw new Error("Escribe un nombre de hasta 100 caracteres.");
  if (h.libre === true) return {nombre, libre: true, inicio: 0, fin: 0, descansoInicio: 0, descansoFin: 0};
  const {inicio, fin, descansoInicio = 0, descansoFin = 0} = h;
  if (![inicio, fin, descansoInicio, descansoFin].every(Number.isInteger) ||
      inicio < 0 || inicio >= 1440 || fin <= inicio || fin > inicio + 1440 ||
      !((descansoInicio === 0 && descansoFin === 0) ||
        (descansoInicio >= inicio && descansoFin > descansoInicio && descansoFin <= fin))) {
    throw new Error("Revisa horas y descanso. La salida puede ser al día siguiente; máximo 24 horas.");
  }
  return {nombre, libre: false, inicio, fin, descansoInicio, descansoFin};
}
const overlap = (a: number, b: number, c: number, d: number) => Math.max(0, Math.min(b, d) - Math.max(a, c));
// Agrupa por fecha de ENTRADA en Colombia, incluso en turnos que cruzan medianoche.
// Las secuencias ambiguas nunca se convierten en horas aprobables.
export function calcularBio(eventos: BioData[], planes: BioData[], desde: string, hasta: string): BioData[] {
  const rows = new Map<string, BioData>();
  const get = (userId: string, dia: string): BioData => {
    const key = `${userId}|${dia}`;
    if (!rows.has(key)) rows.set(key, {userId, dia, trabajado: 0, ordinario: 0, extra: 0, incidencias: [], eventos: []});
    return rows.get(key)!;
  };
  const schedule = new Map(planes.map((p) => [`${p.userId}|${p.dia}`, p]));
  const jornadaDia = (e: BioData): string => {
    const dia = diaBio(e.capturadoMs);
    const anterior = diaBio(fechaBio(dia) - 86400000);
    const p = schedule.get(`${e.userId}|${anterior}`);
    // Una nueva entrada tras el descanso nocturno sigue en la jornada previa.
    return p && !p.libre && p.fin > 1440 && e.capturadoMs <= fechaBio(anterior, p.fin) ? anterior : dia;
  };
  for (const p of planes) get(p.userId, p.dia);
  const pending = new Map<string, BioData>();
  const ordered = eventos.filter((e) => !e.anulado).sort((a, b) => a.capturadoMs - b.capturadoMs || String(a.id).localeCompare(String(b.id)));
  for (const e of ordered) {
    const open = pending.get(e.userId);
    const r = get(e.userId, jornadaDia(open || e));
    r.eventos.push(e);
    if (e.tipo === "ENTRADA") {
      if (open) r.incidencias.push("Entrada repetida sin salida");
      else pending.set(e.userId, e);
      continue;
    }
    if (!open) {
      r.incidencias.push("Salida sin entrada"); continue;
    }
    pending.delete(e.userId);
    const a = open.capturadoMs; const b = e.capturadoMs;
    if (b <= a || b - a > 24 * 3600000) {
      r.incidencias.push("Duración inválida o mayor de 24 h"); continue;
    }
    const p = schedule.get(`${e.userId}|${r.dia}`);
    if (!p) {
      r.trabajado += (b - a) / 60000; continue;
    }
    const base = fechaBio(r.dia);
    const pausa = p.libre ? 0 : overlap(a, b, base + p.descansoInicio * 60000, base + p.descansoFin * 60000);
    const neto = b - a - pausa;
    const ordinario = p.libre ? 0 : overlap(a, b, base + p.inicio * 60000, base + p.fin * 60000) - pausa;
    r.trabajado += neto / 60000; r.ordinario += ordinario / 60000; r.extra += (neto - ordinario) / 60000;
  }
  for (const e of pending.values()) get(e.userId, jornadaDia(e)).incidencias.push("Falta salida");
  return [...rows.values()].filter((r) => r.dia >= desde && r.dia <= hasta).map((r): BioData => {
    const p = schedule.get(`${r.userId}|${r.dia}`);
    if (!p) r.incidencias.push("Sin horario asignado");
    if (p && !p.libre && r.eventos.length === 0) r.incidencias.push("Sin marcaciones");
    const programado = !p || p.libre ? 0 : p.fin - p.inicio - (p.descansoFin - p.descansoInicio);
    return {...r, horario: p || null, programado, faltante: Math.max(0, programado - r.ordinario),
      trabajado: Math.round(r.trabajado), ordinario: Math.round(r.ordinario), extra: Math.round(r.extra),
      incidencias: [...new Set(r.incidencias)]};
  }).sort((a, b) => a.dia.localeCompare(b.dia) || a.userId.localeCompare(b.userId));
}
