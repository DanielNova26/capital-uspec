import { FileBlob, SpreadsheetFile } from "@oai/artifact-tool";

const input = await FileBlob.load(
  "C:/Users/SERVICIO TECNICO/Downloads/Numerales Interventoria.xlsx",
);
const workbook = await SpreadsheetFile.importXlsx(input);
const overview = await workbook.inspect({
  kind: "workbook,sheet,table",
  maxChars: 8000,
  tableMaxRows: 12,
  tableMaxCols: 10,
  tableMaxCellChars: 240,
});
process.stdout.write(`${overview.ndjson}\n`);
const matches = await workbook.inspect({
  kind: "match",
  searchTerm: "11.8|SEGURIDAD Y SALUD|Supervisor de Hse|Dirección de talento humano",
  options: { useRegex: true, maxResults: 80 },
  maxChars: 16000,
});
process.stdout.write(`${matches.ndjson}\n`);
const sectionEleven = await workbook.inspect({
  kind: "table",
  sheetId: "Table 1",
  range: "A248:A258",
  include: "values,formulas",
  tableMaxRows: 20,
  tableMaxCols: 3,
  tableMaxCellChars: 2000,
  maxChars: 22000,
});
process.stdout.write(`${sectionEleven.ndjson}\n`);
const matrixEleven = await workbook.inspect({
  kind: "table",
  sheetId: "Numerales",
  range: "A133:G141",
  include: "values,formulas",
  tableMaxRows: 20,
  tableMaxCols: 8,
  tableMaxCellChars: 2000,
  maxChars: 24000,
});
process.stdout.write(`${matrixEleven.ndjson}\n`);
