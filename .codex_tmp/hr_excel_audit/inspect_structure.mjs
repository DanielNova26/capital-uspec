import { FileBlob, SpreadsheetFile } from '@oai/artifact-tool';

const sourcePath = 'C:/Users/SERVICIO TECNICO/Downloads/plantila empresa UT SERVIR USPEC 2026 (1) (1).xlsx';
const input = await FileBlob.load(sourcePath);
const workbook = await SpreadsheetFile.importXlsx(input);

const sheets = await workbook.inspect({
  kind: 'sheet',
  include: 'id,name',
  maxChars: 8000,
});
console.log('===SHEETS===');
console.log(sheets.ndjson);

for (const sheet of workbook.worksheets.items) {
  const used = sheet.getUsedRange();
  console.log(`===USED ${sheet.name}: ${used?.address ?? 'A1:A1'}===`);
  const region = await workbook.inspect({
    kind: 'region',
    sheetId: sheet.name,
    range: used?.address ?? 'A1:Z30',
    maxChars: 9000,
    tableMaxRows: 14,
    tableMaxCols: 24,
    tableMaxCellChars: 100,
  });
  console.log(region.ndjson);
}
