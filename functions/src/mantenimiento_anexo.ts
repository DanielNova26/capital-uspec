// Anexo 5, versión 02, hoja Table 1 (C3:T22). Los valores son la referencia de la tabla.
export const familiasAnexo = [
  "Puestos para cocción en estufas industriales",
  "Puestos para coción en estufas cuando no existan marmitas",
  "Marmita",
  "Caldera",
  "Pela-papa (Mínimo 50 kg/H)",
  "Pela-papa grande (Mínimo 200 kg/H)",
  "Procesador de alimentos 50kg/h",
  "Procesador de alimentos 200 kg/h",
  "Bandeja asadora de sobreponer",
  "Hidrolavadora",
  "Licuadora Industrial (Mínimo de 10 Lt)",
  "Licuadora no industrial (Mínimo de 2 Lt)",
  "Refrigerador (Mínimo de 520 Lt)",
  "Congelador (Mínimo de 530 Lt)",
  "Tanque de Agua (500 Lt)",
  "Báscula de Plataforma digital (Mínimo de 200 Kg)",
  "Gramera digital de 1000 g (máximo 1 g de sensibilidad)",
  "Termometro por area de proceso (calibrados)",
];

const rangos: Array<[number, number, number[]]> = [
  [1, 50, [4, 0, 0, 0, 1, 0, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 4]],
  [51, 100, [4, 0, 0, 0, 1, 0, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 4]],
  [101, 200, [4, 0, 0, 0, 1, 0, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 4]],
  [201, 250, [4, 0, 0, 0, 1, 0, 2, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 4]],
  [251, 300, [6, 0, 0, 0, 1, 0, 2, 0, 1, 1, 1, 1, 2, 2, 1, 1, 1, 4]],
  [301, 400, [6, 0, 0, 0, 1, 0, 2, 0, 1, 1, 1, 1, 2, 2, 1, 1, 1, 4]],
  [401, 600, [8, 0, 0, 0, 1, 0, 2, 0, 2, 1, 1, 1, 2, 2, 1, 1, 1, 4]],
  [601, 800, [8, 0, 0, 0, 0, 1, 0, 1, 2, 2, 1, 1, 3, 3, 1, 1, 1, 4]],
  [801, 1000, [10, 0, 0, 0, 0, 1, 0, 1, 2, 2, 1, 1, 3, 3, 1, 1, 1, 4]],
  [1001, 1500, [12, 12, 0, 0, 0, 1, 0, 1, 3, 2, 1, 2, 4, 4, 2, 1, 2, 4]],
  [1501, 2000, [14, 14, 0, 0, 0, 1, 0, 1, 3, 2, 1, 2, 4, 4, 2, 1, 2, 4]],
  [2001, 2500, [2, 16, 4, 1, 0, 1, 0, 1, 3, 2, 1, 2, 5, 5, 2, 1, 2, 4]],
  [2501, 3000, [2, 18, 4, 1, 0, 1, 0, 1, 3, 2, 1, 2, 6, 6, 2, 1, 2, 4]],
  [3001, 4000, [2, 28, 4, 1, 0, 1, 0, 1, 4, 3, 1, 3, 8, 8, 2, 1, 2, 4]],
  [4001, 5000, [4, 38, 5, 1, 0, 1, 0, 1, 4, 3, 1, 3, 10, 10, 2, 1, 2, 4]],
  [5001, 6000, [4, 48, 6, 1, 0, 2, 0, 2, 5, 3, 1, 3, 12, 12, 2, 1, 2, 4]],
  [6001, 7000, [6, 58, 7, 1, 0, 2, 0, 2, 5, 3, 1, 4, 14, 14, 2, 1, 2, 4]],
  [7001, 10000, [6, 68, 8, 1, 0, 2, 0, 2, 6, 3, 1, 4, 14, 14, 2, 1, 2, 4]],
];

export function minimosAnexo(ppl: number) {
  return rangos.find(([desde, hasta]) => ppl >= desde && ppl <= hasta)?.[2] ?? [];
}
