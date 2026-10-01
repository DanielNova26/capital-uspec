const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const {
  assertSucceeds,
  initializeTestEnvironment,
} = require("@firebase/rules-unit-testing");
const {
  collection,
  doc,
  getDocs,
  query,
  runTransaction,
  setDoc,
  where,
} = require("firebase/firestore");

// 1 oct 2026. Admin › Apps, roles y permisos: "No se pudo cambiar el rol de
// Interventoría: Dart exception thrown from converted Future". La app ahora
// muestra el error de adentro (`runTransactionLegible`); estas pruebas fijan
// que las reglas dejan pasar la transacción completa de
// `TableModuleRolesRepository.setIndividualLevel` (leer ficha y asignación,
// escribir las dos) para Desarrollo, Admin y el administrador del módulo.
// Y en Visitas › Equipo, que el jefe sí puede listar los roles de su
// empresa: el "Sin rol" de su equipo venía de la caché, no de las reglas.

const projectId = "capital-uspec-admin-roles-tx-test";
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

function ficha(extra = {}) {
  return {
    empresaId: "EMP_A",
    empresas: ["EMP_A"],
    estado: "activo",
    appsPorEmpresa: true,
    apps: [],
    empresasDetalle: {
      EMP_A: {activo: true, apps: ["interventoriadashboard"]},
    },
    ...extra,
  };
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
      setDoc(doc(db, "TBL_USUARIOS/dev"), ficha({desarrollador: true})),
      setDoc(doc(db, "TBL_USUARIOS/admin"), ficha({
        empresasDetalle: {
          EMP_A: {activo: true, apps: ["admindashboard", "interventoriadashboard"]},
        },
      })),
      setDoc(doc(db, "TBL_USUARIOS/director"), ficha()),
      setDoc(doc(db, "TBL_USUARIOS/jarod"), ficha()),
      setDoc(doc(db, "TBL_USUARIOS/gineth"), ficha()),
      setDoc(doc(db, "TBL_INTERVENTORIA_ROLES/EMP_A_director"), {
        empresaId: "EMP_A",
        userId: "director",
        rol: "admin_interventoria",
      }),
      setDoc(doc(db, "TBL_INTERVENTORIA_ROLES/EMP_A_gineth"), {
        empresaId: "EMP_A",
        userId: "gineth",
        rol: "calidad_interventoria",
      }),
      setDoc(doc(db, "TBL_USUARIOS/jefe"), ficha({
        empresasDetalle: {EMP_A: {activo: true, apps: ["visitasdashboard"]}},
      })),
      setDoc(doc(db, "TBL_VISITAS_ROLES/EMP_A_jefe"), {
        empresaId: "EMP_A",
        userId: "jefe",
        rol: "jefe",
        areaId: "AREA_calidad",
      }),
      setDoc(doc(db, "TBL_VISITAS_ROLES/EMP_A_ana"), {
        empresaId: "EMP_A",
        userId: "ana",
        rol: "profesional",
        areaId: "AREA_calidad",
      }),
    ]);
  });
});

test.after(async () => {
  await env?.cleanup();
});

// Misma forma que setIndividualLevel: dos lecturas y dos escrituras.
async function fijarNivel(db, userId, nivel) {
  const userRef = doc(db, `TBL_USUARIOS/${userId}`);
  const asignacionRef = doc(db, `TBL_INTERVENTORIA_ROLES/EMP_A_${userId}`);
  await runTransaction(db, async (tx) => {
    const user = await tx.get(userRef);
    const asignacion = await tx.get(asignacionRef);
    assert.ok(user.exists());
    const campos = {
      empresaId: "EMP_A",
      userId,
      cedula: userId,
      nombre: userId,
      rol: nivel,
      updatedBy: "x",
    };
    if (asignacion.exists()) tx.update(asignacionRef, campos);
    else tx.set(asignacionRef, campos);
    tx.update(userRef, {
      "empresasDetalle.EMP_A.rolInterventoria": nivel,
      "empresasDetalle.EMP_A.apps": ["interventoriadashboard"],
      "apps": ["interventoriadashboard"],
      "appsPorEmpresa": true,
    });
  });
}

test("Desarrollo cambia el rol de Interventoría en una transacción", async () => {
  await assertSucceeds(fijarNivel(auth("dev"), "jarod", "revisor_interventoria"));
});

test("Admin de la empresa también", async () => {
  await assertSucceeds(fijarNivel(auth("admin"), "gineth", "gerente_interventoria"));
});

test("el administrador de Interventoría cambia el de otro", async () => {
  await assertSucceeds(fijarNivel(auth("director"), "jarod", "registrador_interventoria"));
  await assertSucceeds(fijarNivel(auth("director"), "gineth", "admin_interventoria"));
});

test("el jefe de Visitas lista los roles de su empresa", async () => {
  const snap = await assertSucceeds(getDocs(query(
    collection(auth("jefe"), "TBL_VISITAS_ROLES"),
    where("empresaId", "==", "EMP_A")
  )));
  assert.deepEqual(
    snap.docs.map((d) => d.id).sort(),
    ["EMP_A_ana", "EMP_A_jefe"]
  );
});
