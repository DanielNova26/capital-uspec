import fs from "node:fs/promises";
import { SpreadsheetFile, Workbook } from "@oai/artifact-tool";

const outputDir = "C:/Desarrollo/capital-uspec/outputs/talento_humano";
const previewDir = `${outputDir}/preview`;
await fs.mkdir(previewDir, { recursive: true });

const wb = Workbook.create();
const navy = "#173B5E";
const blue = "#246B9E";
const paleBlue = "#EAF4FB";
const paleGold = "#FFF5E6";
const ink = "#17212B";
const muted = "#5F6B76";
const border = "#D8E2EA";

function title(sheet, titleText, subtitle, lastCol) {
  sheet.showGridLines = false;
  sheet.getRange(`A1:${lastCol}1`).merge();
  sheet.getRange("A1").values = [[titleText]];
  sheet.getRange(`A1:${lastCol}1`).format = {
    fill: navy,
    font: { color: "#FFFFFF", bold: true, size: 18 },
    verticalAlignment: "center",
  };
  sheet.getRange(`A1:${lastCol}1`).format.rowHeight = 34;
  sheet.getRange(`A2:${lastCol}2`).merge();
  sheet.getRange("A2").values = [[subtitle]];
  sheet.getRange(`A2:${lastCol}2`).format = {
    fill: paleBlue,
    font: { color: muted, italic: true, size: 10 },
    wrapText: true,
    verticalAlignment: "center",
  };
  sheet.getRange(`A2:${lastCol}2`).format.rowHeight = 32;
}

function header(sheet, range) {
  sheet.getRange(range).format = {
    fill: blue,
    font: { color: "#FFFFFF", bold: true, size: 10 },
    wrapText: true,
    verticalAlignment: "center",
    borders: { preset: "all", style: "thin", color: border },
  };
  sheet.getRange(range).format.rowHeight = 32;
}

const instructions = wb.worksheets.add("INSTRUCCIONES");
title(
  instructions,
  "Plantilla de personal · Talento Humano",
  "Diligencia las hojas indicadas, conserva sus nombres y carga el archivo desde Talento Humano > Cargar personal desde Excel.",
  "F",
);
instructions.getRange("A4:F4").merge();
instructions.getRange("A4").values = [["FLUJO DE CARGA"]];
instructions.getRange("A4:F4").format = {
  fill: paleGold,
  font: { color: ink, bold: true, size: 12 },
};
instructions.getRange("A6:F6").values = [["Paso", "Hoja", "Uso", "Qué contiene", "Qué hace la aplicación", "Recomendación"]];
instructions.getRange("A7:F11").values = [
  ["1", "PERSONAL", "Obligatoria", "Una fila por colaborador", "La cédula identifica y actualiza a la persona", "No borres encabezados"],
  ["2", "AREAS", "Opcional", "Catálogo de áreas", "También se infieren desde PERSONAL", "Usa nombres consistentes"],
  ["3", "CARGOS", "Opcional", "Catálogo de cargos", "También se infieren desde PERSONAL", "Un cargo por fila"],
  ["4", "CENTROS_COSTOS", "Opcional", "Código y nombre", "También se infieren desde PERSONAL", "Evita duplicados"],
  ["5", "APPS", "Opcional", "Permisos adicionales", "Separa varias apps con coma", "La app valida antes de importar"],
];
header(instructions, "A6:F6");
instructions.getRange("A6:F11").format.borders = { preset: "all", style: "thin", color: border };
instructions.getRange("A13:F13").merge();
instructions.getRange("A13").values = [["Antes de importar, la aplicación mostrará cuántas personas, áreas, cargos y centros encontró. La carga siempre queda asociada a la empresa activa."]];
instructions.getRange("A13:F13").format = {
  fill: "#E9F8F0",
  font: { color: "#176B45", bold: true, size: 10 },
  wrapText: true,
  borders: { preset: "outside", style: "thin", color: "#9CD8BA" },
};
instructions.getRange("A13:F13").format.rowHeight = 42;
instructions.getRange("A1:F13").format.font = { name: "Arial" };
instructions.getRange("A:A").format.columnWidth = 8;
instructions.getRange("B:B").format.columnWidth = 22;
instructions.getRange("C:C").format.columnWidth = 16;
instructions.getRange("D:D").format.columnWidth = 28;
instructions.getRange("E:E").format.columnWidth = 40;
instructions.getRange("F:F").format.columnWidth = 30;

const personalHeaders = [
  "cedula", "tipo_documento", "nombres", "apellidos", "nombreCompleto", "correo",
  "area", "cargo", "centroCostos", "jefeId", "jefeNombre", "cargoJefe", "estado", "apps",
];
const personal = wb.worksheets.add("PERSONAL");
title(personal, "Personal", "Una fila por colaborador. Obligatorios: cédula y nombre; completa área y cargo para construir la estructura.", "N");
personal.getRange("A4:N4").values = [personalHeaders];
header(personal, "A4:N4");
personal.getRange("A5:N204").format = {
  font: { color: ink, size: 10, name: "Arial" },
  borders: { preset: "insideHorizontal", style: "thin", color: border },
};
personal.getRange("B5:B204").dataValidation = { rule: { type: "list", values: ["CC", "CE", "TI", "PASAPORTE"] } };
personal.getRange("M5:M204").dataValidation = { rule: { type: "list", values: ["ACTIVO", "INACTIVO"] } };
personal.freezePanes.freezeRows(4);
const widths = [16, 18, 22, 22, 30, 32, 26, 30, 22, 16, 30, 28, 15, 28];
for (let i = 0; i < widths.length; i++) personal.getRangeByIndexes(0, i, 204, 1).format.columnWidth = widths[i];

function catalogSheet(name, sheetTitle, subtitle, headers, widths, validations = []) {
  const sheet = wb.worksheets.add(name);
  const last = String.fromCharCode(64 + headers.length);
  title(sheet, sheetTitle, subtitle, last);
  sheet.getRange(`A4:${last}4`).values = [headers];
  header(sheet, `A4:${last}4`);
  sheet.getRange(`A5:${last}104`).format = {
    font: { color: ink, size: 10, name: "Arial" },
    borders: { preset: "insideHorizontal", style: "thin", color: border },
  };
  widths.forEach((width, index) => sheet.getRangeByIndexes(0, index, 104, 1).format.columnWidth = width);
  validations.forEach(({ col, values }) => sheet.getRange(`${col}5:${col}104`).dataValidation = { rule: { type: "list", values } });
  sheet.freezePanes.freezeRows(4);
  return sheet;
}

catalogSheet("AREAS", "Áreas", "Opcional. Si esta hoja está vacía, las áreas también se crearán a partir de la hoja PERSONAL.", ["nombre", "descripcion", "activo"], [30, 46, 14], [{ col: "C", values: ["SI", "NO"] }]);
catalogSheet("CARGOS", "Cargos", "Opcional. Puedes indicar el área y el cargo superior para conservar la jerarquía.", ["nombre", "area", "descripcion", "parent_cargo", "activo"], [32, 28, 44, 32, 14], [{ col: "E", values: ["SI", "NO"] }]);
catalogSheet("CENTROS_COSTOS", "Centros de costos", "Opcional. Usa un código estable y un nombre claro para cada centro.", ["codigo", "nombre"], [22, 44]);
catalogSheet("APPS", "Aplicaciones", "Opcional. Solo úsala si necesitas asignar aplicaciones adicionales durante la carga.", ["appId", "nombre", "descripcion", "enabled"], [24, 28, 46, 14], [{ col: "D", values: ["SI", "NO"] }]);

const example = wb.worksheets.add("EJEMPLO");
title(example, "Ejemplo de diligenciamiento", "Esta hoja no se importa. Úsala solo como referencia visual.", "N");
example.getRange("A4:N4").values = [personalHeaders];
header(example, "A4:N4");
example.getRange("A5:N5").values = [["1012345678", "CC", "Andrea", "Pérez", "Andrea Pérez", "andrea.perez@empresa.com", "Talento Humano", "Analista", "CC-01", "", "", "", "ACTIVO", "tareas"]];
example.getRange("A5:N5").format = { fill: "#F8FAFC", font: { color: ink, size: 10, name: "Arial" }, borders: { preset: "all", style: "thin", color: border } };
widths.forEach((width, index) => example.getRangeByIndexes(0, index, 6, 1).format.columnWidth = width);
example.freezePanes.freezeRows(4);

const output = await SpreadsheetFile.exportXlsx(wb);
await output.save(`${outputDir}/plantilla_personal_talento_humano.xlsx`);
for (const sheetName of ["INSTRUCCIONES", "PERSONAL", "EJEMPLO"]) {
  const rendered = await wb.render({ sheetName, autoCrop: "all", scale: 1, format: "png" });
  await fs.writeFile(`${previewDir}/${sheetName}.png`, new Uint8Array(await rendered.arrayBuffer()));
}
const inspection = await wb.inspect({ kind: "sheet,region", maxChars: 6000, tableMaxRows: 8, tableMaxCols: 14 });
await fs.writeFile(`${outputDir}/inspection.txt`, inspection.ndjson ?? String(inspection), "utf8");
