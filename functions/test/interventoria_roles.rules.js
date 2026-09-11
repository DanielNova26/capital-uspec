/**
 * Reglas de TBL_INTERVENTORIA_ROLES.
 *
 * Reportado el 11 sep 2026: desde Administración, cambiar el rol de
 * Interventoría de alguien daba "permission-denied" aunque quien lo hacía
 * era el desarrollador y además admin_interventoria de esa empresa.
 *
 * La causa está en cómo se escribe `isDeveloper()`: lee `desarrollador`,
 * `role` y `rol` de la raíz del usuario con punto, y en un usuario que no
 * tiene esos campos —el desarrollador real está marcado DENTRO de
 * `empresasDetalle`— la regla no da falso: da error, y el error se vuelve
 * denegado aunque la otra rama del `||` fuera cierta.
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
const {doc, setDoc, deleteDoc} = require("firebase/firestore");

const projectId = "capital-uspec-interventoria-roles";
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

const rolDoc = (empresa, cedula) => ({
  empresaId: empresa,
  userId: cedula,
  cedula,
  nombre: "PERSONA",
  rol: "registrador_interventoria",
});

test.before(async () => {
  assert.ok(
    process.env.FIRESTORE_EMULATOR_HOST,
    "Ejecuta estas pruebas mediante Firebase Emulator Suite."
  );
  env = await initializeTestEnvironment({projectId, firestore: {rules}});
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await Promise.all([
      // Como está el desarrollador de verdad: NADA en la raíz que diga
      // desarrollador; solo el bloque de la empresa.
      setDoc(doc(db, "TBL_USUARIOS/devempresa"), {
        nombre: "Dev",
        empresas: ["EMP_A"],
        empresasDetalle: {EMP_A: {roleId: "EMP_A_desarrollador"}},
      }),
      // Admin de interventoría sin campos de rol en la raíz.
      setDoc(doc(db, "TBL_USUARIOS/adminint"), {
        nombre: "Admin Int",
        empresas: ["EMP_A"],
        empresasDetalle: {EMP_A: {cargo: "Coordinador"}},
      }),
      setDoc(doc(db, "TBL_INTERVENTORIA_ROLES/EMP_A_adminint"), {
        empresaId: "EMP_A",
        userId: "adminint",
        rol: "admin_interventoria",
      }),
      // Alguien de la empresa sin rol: no puede tocar roles.
      setDoc(doc(db, "TBL_USUARIOS/curioso"), {
        nombre: "Curioso",
        empresas: ["EMP_A"],
        empresasDetalle: {EMP_A: {}},
      }),
      // Desarrollador marcado en la raíz, como en las cuentas viejas.
      setDoc(doc(db, "TBL_USUARIOS/devraiz"), {
        nombre: "Dev raíz",
        desarrollador: true,
        role: "desarrollador",
        empresas: ["EMP_A"],
      }),
      // El desarrollador REAL: `role: rutas_desarrollador` y
      // `roleId: EMPRESA_001_rutas_desarrollador` en la raíz, y en la empresa
      // donde administra (EMP_A) un bloque sin rol. Es lo que la app llama
      // desarrollador (`isDeveloperUser`) y las reglas no reconocían.
      setDoc(doc(db, "TBL_USUARIOS/devreal"), {
        nombre: "Daniel",
        role: "rutas_desarrollador",
        roleKey: "rutas_desarrollador",
        roleId: "EMP_OTRA_rutas_desarrollador",
        empresas: ["EMP_OTRA", "EMP_A"],
        empresasDetalle: {EMP_OTRA: {cargo: "Desarrollador"}, EMP_A: {cargo: "Desarrollador"}},
      }),
      setDoc(doc(db, "TBL_INTERVENTORIA_ROLES/EMP_A_existente"), rolDoc("EMP_A", "existente")),
    ]);
  });
});

test.after(async () => {
  await env?.cleanup();
});

test("el desarrollador marcado dentro de la empresa puede asignar un rol", async () => {
  await assertSucceeds(
    setDoc(doc(auth("devempresa"), "TBL_INTERVENTORIA_ROLES/EMP_A_nueva1"), rolDoc("EMP_A", "nueva1"))
  );
});

test("el admin de interventoría sin campos de rol en la raíz puede asignar", async () => {
  await assertSucceeds(
    setDoc(doc(auth("adminint"), "TBL_INTERVENTORIA_ROLES/EMP_A_nueva2"), rolDoc("EMP_A", "nueva2"))
  );
});

test("y puede quitar un rol (Sin rol = borrar el documento)", async () => {
  await assertSucceeds(
    deleteDoc(doc(auth("adminint"), "TBL_INTERVENTORIA_ROLES/EMP_A_existente"))
  );
});

test("el desarrollador marcado en la raíz sigue pudiendo", async () => {
  await assertSucceeds(
    setDoc(doc(auth("devraiz"), "TBL_INTERVENTORIA_ROLES/EMP_A_nueva3"), rolDoc("EMP_A", "nueva3"))
  );
});

test("el desarrollador real (roleId terminado en _desarrollador) administra", async () => {
  await assertSucceeds(
    setDoc(doc(auth("devreal"), "TBL_INTERVENTORIA_ROLES/EMP_A_nueva4"), rolDoc("EMP_A", "nueva4"))
  );
  // Y su propio rol, que es lo que estaba intentando.
  await assertSucceeds(
    setDoc(doc(auth("devreal"), "TBL_INTERVENTORIA_ROLES/EMP_A_devreal"), {
      ...rolDoc("EMP_A", "devreal"),
      rol: "admin_interventoria",
    })
  );
});

test("alguien sin rol no se puede ascender", async () => {
  await assertFails(
    setDoc(doc(auth("curioso"), "TBL_INTERVENTORIA_ROLES/EMP_A_curioso"), {
      ...rolDoc("EMP_A", "curioso"),
      rol: "admin_interventoria",
    })
  );
});

test("el desarrollador de una empresa no administra los roles de otra", async () => {
  await assertFails(
    setDoc(doc(auth("devempresa"), "TBL_INTERVENTORIA_ROLES/EMP_B_nueva"), rolDoc("EMP_B", "nueva"))
  );
});
