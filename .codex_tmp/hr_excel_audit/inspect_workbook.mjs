import fs from 'node:fs/promises';
import path from 'node:path';
import { FileBlob, SpreadsheetFile } from '@oai/artifact-tool';

const sourcePath = 'C:/Users/SERVICIO TECNICO/Downloads/plantila empresa UT SERVIR USPEC 2026 (1) (1).xlsx';
const outputDir = 'C:/Desarrollo/capital-uspec/.codex_tmp/hr_excel_audit/previews';

await fs.mkdir(outputDir, { recursive: true });
const input = await FileBlob.load(sourcePath);
const workbook = await SpreadsheetFile.importXlsx(input);

const sheetSummary = await workbook.inspect({
  kind: 'workbook,sheet,table',
  maxChars: 12000,
  tableMaxRows: 8,
  tableMaxCols: 18,
  tableMaxCellChars: 100,
});
console.log('===SUMMARY===');
console.log(sheetSummary.ndjson);

for (const sheet of workbook.worksheets.items) {
  const used = sheet.getUsedRange();
  const address = used?.address ?? 'A1:A1';
  const safeName = sheet.name.replace(/[\\/:*?"<>|]/g, '_');
  const region = await workbook.inspect({
    kind: 'region',
    sheetId: sheet.name,
    range: address,
    maxChars: 14000,
    tableMaxRows: 18,
    tableMaxCols: 24,
    tableMaxCellChars: 120,
  });
  console.log(`===SHEET ${sheet.name} ${address}===`);
  console.log(region.ndjson);

  const styleRange = address.includes(':') ? address : `${address}:${address}`;
  const styles = await workbook.inspect({
    kind: 'computedStyle',
    sheetId: sheet.name,
    range: styleRange,
    maxChars: 5000,
  });
  console.log(`===STYLE ${sheet.name}===`);
  console.log(styles.ndjson);

  const preview = await workbook.render({
    sheetName: sheet.name,
    autoCrop: 'all',
    scale: 1,
    format: 'png',
  });
  await fs.writeFile(
    path.join(outputDir, `${safeName}.png`),
    new Uint8Array(await preview.arrayBuffer()),
  );
}

const formulaErrors = await workbook.inspect({
  kind: 'match',
  searchTerm: '#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A',
  options: { useRegex: true, maxResults: 100 },
  summary: 'formula errors',
});
console.log('===FORMULA_ERRORS===');
console.log(formulaErrors.ndjson);
