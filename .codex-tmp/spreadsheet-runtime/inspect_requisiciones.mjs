import { FileBlob, SpreadsheetFile } from '@oai/artifact-tool';

const sourcePath = 'C:/Users/SERVICIO TECNICO/Downloads/REQUISICONES 2026.xlsx';
const input = await FileBlob.load(sourcePath);
const workbook = await SpreadsheetFile.importXlsx(input);

const overview = await workbook.inspect({
  kind: 'workbook,sheet,table',
  maxChars: 12000,
  tableMaxRows: 18,
  tableMaxCols: 18,
  tableMaxCellChars: 120,
});
console.log(overview.ndjson);

for (const sheet of workbook.worksheets.items) {
  const used = sheet.getUsedRange();
  if (!used) continue;
  const region = await workbook.inspect({
    kind: 'region',
    sheetId: sheet.name,
    range: used.address,
    maxChars: 24000,
    tableMaxRows: 80,
    tableMaxCols: 24,
    tableMaxCellChars: 140,
  });
  console.log(region.ndjson);
}
