import fs from "node:fs/promises";
import { FileBlob, SpreadsheetFile } from "@oai/artifact-tool";

const inputPath =
  "C:/Users/SERVICIO TECNICO/Downloads/plantilla_personal_talento_humano.xlsx";
const outputDir =
  "C:/Desarrollo/capital-uspec/outputs/talento_humano/dynamic_preview";

await fs.mkdir(outputDir, { recursive: true });
const input = await FileBlob.load(inputPath);
const workbook = await SpreadsheetFile.importXlsx(input);

const checks = [];
for (const [sheetId, range] of [
  ["INSTRUCCIONES", "A1:F13"],
  ["AREAS", "A1:C20"],
  ["CARGOS", "A1:E25"],
  ["CENTROS_COSTOS", "A1:B20"],
  ["APPS", "A1:D20"],
]) {
  const inspection = await workbook.inspect({
    kind: "region",
    sheetId,
    range,
    maxChars: 8000,
    tableMaxRows: 25,
    tableMaxCols: 6,
  });
  checks.push(`--- ${sheetId} ${range} ---\n${inspection.ndjson ?? inspection}`);

  const rendered = await workbook.render({
    sheetName: sheetId,
    autoCrop: "all",
    scale: 1,
    format: "png",
  });
  await fs.writeFile(
    `${outputDir}/${sheetId}.png`,
    new Uint8Array(await rendered.arrayBuffer()),
  );
}

await fs.writeFile(`${outputDir}/inspection.txt`, checks.join("\n\n"), "utf8");
console.log(checks.join("\n\n"));
