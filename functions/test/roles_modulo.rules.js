/**
 * Roles configurables por módulo (28 sep 2026, trabajo de Codex):
 * - TBL_ROLES `module_role`: solo Desarrollo o Admin de la empresa (y el
 *   administrador de Correo para los de Correspondencia), con el contrato.
 * - Los perfiles generales de TBL_ROLES siguen igual que antes.
 * - TBL_CORREO_ROLES: Admin de la empresa asigna niveles válidos.
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
const {deleteDoc, doc, getDoc, setDoc, updateDoc} = require("firebase/firestore");

const rules = fs.readFileSync(path.resolve(__dirname, "../../firestore.rules"), "utf8");
let env;
const auth = (id) => env.authenticatedContext(id, {authVersion: 2, userDocId: id}).firestore();

function rol(extra = {}) {
  return {
    empresaId: "EMP_A", type: "module_role", moduleId: "tareasdashboard",
    moduleName: "Tareas", moduleRole: "coordinador", roleId: "EMP_A_mod_tareas_coordinador",
    nombre: "Coordinador", descripcion: "", enabled: true, revision: 1,
    permissions: {asignar: true, verTodas: false}, updatedBy: "admin",
    updatedAt: new Date(), ...extra,
  };
}

test.before(async () => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST, "Usa el emulador.");
  env = await initializeTestEnvironment({projectId: "capital-uspec-roles-modulo", firestore: {rules}});
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const base = (extra) => ({nombre: "X", estado: "activo", empresas: ["EMP_A"], empresaId: "EMP_A", ...extra});
    await Promise.all([
      setDoc(doc(db, "TBL_USUARIOS/admin"), base({apps: ["admindashboard", "tareasdashboard"]})),
      setDoc(doc(db, "TBL_USUARIOS/normal"), base({apps: ["tareasdashboard", "correodashboard"]})),
      setDoc(doc(db, "TBL_USUARIOS/correoAdmin"), base({apps: ["correodashboard"]})),
      // Módulos por empresa: Admin solo en EMP_B.
      setDoc(doc(db, "TBL_USUARIOS/adminB"), {
        nombre: "X", estado: "activo", empresas: ["EMP_A", "EMP_B"], empresaId: "EMP_A",
        appsPorEmpresa: true, apps: ["tareasdashboard"],
        empresasDetalle: {EMP_A: {apps: ["tareasdashboard"]}, EMP_B: {apps: ["admindashboard"]}},
      }),
      setDoc(doc(db, "TBL_USUARIOS/adminInhabilitado"), base({
        apps: ["admindashboard"], empresasDetalle: {EMP_A: {estadoLaboral: "inactivo"}},
      })),
      setDoc(doc(db, "TBL_CORREO_ROLES/EMP_A_correoAdmin"), {
        empresaId: "EMP_A", usuarioId: "correoAdmin", rol: "administrador",
      }),
      setDoc(doc(db, "TBL_ROLES/EMP_A_mod_tareas_existente"), rol({roleId: "EMP_A_mod_tareas_existente"})),
      setDoc(doc(db, "TBL_ROLES/EMP_A_supervisor"), {empresaId: "EMP_A", nombre: "Supervisor"}),
    ]);
  });
});

test.after(async () => {
  await env.cleanup();
});

test("Admin de la empresa crea, edita y borra roles de módulo", async () => {
  const db = auth("admin");
  await assertSucceeds(setDoc(doc(db, "TBL_ROLES/EMP_A_mod_tareas_coordinador"), rol()));
  await assertSucceeds(updateDoc(doc(db, "TBL_ROLES/EMP_A_mod_tareas_coordinador"), {
    nombre: "Coordinación", revision: 2,
  }));
  await assertSucceeds(deleteDoc(doc(db, "TBL_ROLES/EMP_A_mod_tareas_coordinador")));
});

test("un rol de módulo mal formado no entra", async () => {
  const db = auth("admin");
  await assertFails(setDoc(doc(db, "TBL_ROLES/EMP_A_mod_tareas_x"), rol({revision: 0})));
  await assertFails(setDoc(doc(db, "TBL_ROLES/EMP_A_mod_tareas_x"), rol({enabled: "si"})));
  // Un módulo que no tiene roles configurables (Compras sí los tiene desde
  // el 29 sep 2026).
  await assertFails(setDoc(doc(db, "TBL_ROLES/EMP_A_mod_tareas_x"), rol({moduleId: "inventadodashboard"})));
  // El id tiene que ser de su empresa.
  await assertFails(setDoc(doc(db, "TBL_ROLES/EMP_B_mod_tareas_x"), rol()));
  // No se cambia de empresa ni de módulo al editar.
  await assertFails(updateDoc(doc(db, "TBL_ROLES/EMP_A_mod_tareas_existente"), {
    moduleId: "correodashboard",
  }));
});

test("sin Admin en la empresa no se tocan roles de módulo", async () => {
  await assertFails(setDoc(doc(auth("normal"), "TBL_ROLES/EMP_A_mod_tareas_y"), rol()));
  await assertFails(updateDoc(doc(auth("normal"), "TBL_ROLES/EMP_A_mod_tareas_existente"), {
    nombre: "Hackeado", revision: 9,
  }));
  await assertFails(deleteDoc(doc(auth("normal"), "TBL_ROLES/EMP_A_mod_tareas_existente")));
  // Admin solo en otra empresa (módulos por empresa) o inhabilitado: tampoco.
  await assertFails(setDoc(doc(auth("adminB"), "TBL_ROLES/EMP_A_mod_tareas_y"), rol()));
  await assertFails(setDoc(doc(auth("adminInhabilitado"), "TBL_ROLES/EMP_A_mod_tareas_y"), rol()));
  // Un perfil general no se convierte en rol de módulo para saltarse esto.
  await assertFails(updateDoc(doc(auth("normal"), "TBL_ROLES/EMP_A_supervisor"), {
    type: "module_role",
  }));
});

test("los perfiles generales siguen como antes", async () => {
  const db = auth("normal");
  await assertSucceeds(getDoc(doc(db, "TBL_ROLES/EMP_A_supervisor")));
  await assertSucceeds(getDoc(doc(db, "TBL_ROLES/EMP_A_mod_tareas_existente")));
  await assertSucceeds(setDoc(doc(db, "TBL_ROLES/EMP_A_auxiliar"), {empresaId: "EMP_A", nombre: "Auxiliar"}));
  await assertSucceeds(updateDoc(doc(db, "TBL_ROLES/EMP_A_supervisor"), {nombre: "Supervisora"}));
});

test("el administrador de Correo maneja solo los roles de Correspondencia", async () => {
  const db = auth("correoAdmin");
  await assertSucceeds(setDoc(doc(db, "TBL_ROLES/EMP_A_mod_correspondencia_radicador"), rol({
    moduleId: "correodashboard", moduleName: "Correspondencia", baseRole: "clasificador",
    roleId: "EMP_A_mod_correspondencia_radicador", nombre: "Radicador",
  })));
  await assertFails(setDoc(doc(db, "TBL_ROLES/EMP_A_mod_tareas_z"), rol()));
});

test("Admin de la empresa asigna niveles de Correspondencia", async () => {
  const db = auth("admin");
  await assertSucceeds(setDoc(doc(db, "TBL_CORREO_ROLES/EMP_A_normal"), {
    empresaId: "EMP_A", usuarioId: "normal", rol: "clasificador",
    rolCorreoId: "EMP_A_mod_correspondencia_radicador", rolCorreoNombre: "Radicador",
    rolCorreoVersion: 1, actualizadoPor: "admin", actualizadoAt: new Date(),
  }));
  await assertSucceeds(updateDoc(doc(db, "TBL_CORREO_ROLES/EMP_A_normal"), {rol: "visor"}));
  // Nivel inventado, id que no cuadra o sin Admin: no.
  await assertFails(updateDoc(doc(db, "TBL_CORREO_ROLES/EMP_A_normal"), {rol: "jefe"}));
  await assertFails(setDoc(doc(db, "TBL_CORREO_ROLES/EMP_A_otro"), {
    empresaId: "EMP_A", usuarioId: "normal", rol: "operador",
  }));
  await assertFails(setDoc(doc(auth("normal"), "TBL_CORREO_ROLES/EMP_A_normal"), {
    empresaId: "EMP_A", usuarioId: "normal", rol: "administrador",
  }));
});
