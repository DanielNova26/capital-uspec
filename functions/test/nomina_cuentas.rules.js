/**
 * Reglas del maestro de datos bancarios del personal.
 *
 * Lo que se fija aquí es que el corte entre las dos colecciones sea REAL:
 * Firestore no tiene seguridad por campo, así que "Talento Humano ve el banco y
 * no la cuenta" solo es cierto si el número vive en otro documento con otra
 * regla. Si esto se rompe, no falla nada visible: simplemente las cuentas
 * bancarias de todo el personal quedan legibles para quien no debe.
 */
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require("@firebase/rules-unit-testing");
const {doc, getDoc, setDoc} = require("firebase/firestore");

const projectId = "capital-uspec-nomina-rules";
const rules = fs.readFileSync(
  path.resolve(__dirname, "../../firestore.rules"),
  "utf8"
);

let env;

function auth(userDocId) {
  return env.authenticatedContext(userDocId, {
    authVersion: 2,
    userDocId,
  }).firestore();
}

test.before(async () => {
  assert.ok(
    process.env.FIRESTORE_EMULATOR_HOST,
    "Ejecuta estas pruebas mediante Firebase Emulator Suite."
  );
  env = await initializeTestEnvironment({projectId, firestore: {rules}});
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await Promise.all([
      setDoc(doc(db, "TBL_USUARIOS/tesorera"), {
        empresas: ["EMP_A"],
        empresasDetalle: {EMP_A: {rolPlanillas: "tesoreria"}},
      }),
      setDoc(doc(db, "TBL_USUARIOS/talento"), {
        empresas: ["EMP_A"],
        empresasDetalle: {EMP_A: {rolPlanillas: "talento_humano"}},
      }),
      setDoc(doc(db, "TBL_USUARIOS/curioso"), {
        empresas: ["EMP_A"],
        empresasDetalle: {EMP_A: {}},
      }),
      setDoc(doc(db, "TBL_USUARIOS/otraempresa"), {
        empresas: ["EMP_B"],
        empresasDetalle: {EMP_B: {rolPlanillas: "tesoreria"}},
      }),
      setDoc(doc(db, "TBL_PAGOS_BENEFICIARIOS/EMP_A_123"), {
        empresaId: "EMP_A",
        cedula: "123",
        nombre: "PERSONA DE PRUEBA",
        bancoCodigo: "0013",
      }),
      setDoc(doc(db, "TBL_PAGOS_BENEFICIARIOS_CUENTA/EMP_A_123"), {
        empresaId: "EMP_A",
        cedula: "123",
        numeroCuenta: "902027895",
      }),
    ]);
  });
});

test.after(async () => {
  if (env) await env.cleanup();
});

test("Tesorería lee el maestro y el número", async () => {
  const db = auth("tesorera");
  await assertSucceeds(getDoc(doc(db, "TBL_PAGOS_BENEFICIARIOS/EMP_A_123")));
  await assertSucceeds(getDoc(doc(db, "TBL_PAGOS_BENEFICIARIOS_CUENTA/EMP_A_123")));
});

test("Talento Humano lee el maestro y NO el número", async () => {
  const db = auth("talento");
  await assertSucceeds(getDoc(doc(db, "TBL_PAGOS_BENEFICIARIOS/EMP_A_123")));
  // Esta es la línea que importa de todo el archivo.
  await assertFails(getDoc(doc(db, "TBL_PAGOS_BENEFICIARIOS_CUENTA/EMP_A_123")));
});

test("Talento Humano puede corregir el banco", async () => {
  const db = auth("talento");
  await assertSucceeds(
    setDoc(doc(db, "TBL_PAGOS_BENEFICIARIOS/EMP_A_123"), {
      empresaId: "EMP_A",
      cedula: "123",
      nombre: "PERSONA DE PRUEBA",
      bancoCodigo: "0007",
    })
  );
});

test("el número no se puede colar en el maestro", async () => {
  // Si se admitiera, quedaria legible para Talento Humano y el corte entre las
  // dos colecciones no serviria de nada.
  const db = auth("tesorera");
  await assertFails(
    setDoc(doc(db, "TBL_PAGOS_BENEFICIARIOS/EMP_A_123"), {
      empresaId: "EMP_A",
      cedula: "123",
      nombre: "PERSONA DE PRUEBA",
      bancoCodigo: "0013",
      numeroCuenta: "902027895",
    })
  );
});

test("Talento Humano no puede escribir el número", async () => {
  const db = auth("talento");
  await assertFails(
    setDoc(doc(db, "TBL_PAGOS_BENEFICIARIOS_CUENTA/EMP_A_123"), {
      empresaId: "EMP_A",
      cedula: "123",
      numeroCuenta: "111",
    })
  );
});

test("alguien de la empresa sin rol de planillas no ve nada", async () => {
  const db = auth("curioso");
  await assertFails(getDoc(doc(db, "TBL_PAGOS_BENEFICIARIOS/EMP_A_123")));
  await assertFails(getDoc(doc(db, "TBL_PAGOS_BENEFICIARIOS_CUENTA/EMP_A_123")));
});

test("la Tesorería de otra empresa no ve estas cuentas", async () => {
  const db = auth("otraempresa");
  await assertFails(getDoc(doc(db, "TBL_PAGOS_BENEFICIARIOS/EMP_A_123")));
  await assertFails(getDoc(doc(db, "TBL_PAGOS_BENEFICIARIOS_CUENTA/EMP_A_123")));
});

test("sin sesión no se ve nada", async () => {
  const db = env.unauthenticatedContext().firestore();
  await assertFails(getDoc(doc(db, "TBL_PAGOS_BENEFICIARIOS/EMP_A_123")));
  await assertFails(getDoc(doc(db, "TBL_PAGOS_BENEFICIARIOS_CUENTA/EMP_A_123")));
});
