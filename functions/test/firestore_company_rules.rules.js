const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require("@firebase/rules-unit-testing");
const {
  doc,
  getDoc,
  setDoc,
  updateDoc,
} = require("firebase/firestore");

const projectId = "capital-uspec-rules-test";
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
  env = await initializeTestEnvironment({
    projectId,
    firestore: {rules},
  });
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await Promise.all([
      setDoc(doc(db, "TBL_USUARIOS/alice"), {
        empresas: ["EMP_A"],
      }),
      setDoc(doc(db, "TBL_USUARIOS/bob"), {
        empresasDetalle: {EMP_B: {apps: ["interventoriadashboard"]}},
      }),
      setDoc(doc(db, "TBL_USUARIOS/dev"), {
        desarrollador: true,
      }),
      setDoc(doc(db, "TBL_INTERVENTORIA_ROLES/EMP_A_alice"), {
        empresaId: "EMP_A",
        userId: "alice",
        rol: "admin_interventoria",
      }),
      setDoc(doc(db, "TBL_CORREO_ROLES/EMP_A_alice"), {
        empresaId: "EMP_A",
        usuarioId: "alice",
        rol: "administrador",
      }),
      setDoc(doc(db, "TBL_INTERVENTORIA_VISITAS/visita_a"), {
        empresaId: "EMP_A",
        faseActa: "puntajes",
      }),
      setDoc(doc(db, "TBL_GD_EXPEDIENTES/exp_a"), {
        empresaId: "EMP_A",
        asunto: "Prueba",
      }),
    ]);
  });
});

test.after(async () => {
  await env?.cleanup();
});

test("un usuario solo consulta documentos de sus empresas", async () => {
  const alice = auth("alice");
  const bob = auth("bob");
  await assertSucceeds(getDoc(doc(alice, "TBL_INTERVENTORIA_VISITAS/visita_a")));
  await assertSucceeds(getDoc(doc(alice, "TBL_GD_EXPEDIENTES/exp_a")));
  await assertFails(getDoc(doc(bob, "TBL_INTERVENTORIA_VISITAS/visita_a")));
  await assertFails(getDoc(doc(bob, "TBL_GD_EXPEDIENTES/exp_a")));
});

test("la empresa de un documento no se puede cambiar", async () => {
  const alice = auth("alice");
  await assertFails(
    updateDoc(doc(alice, "TBL_INTERVENTORIA_VISITAS/visita_a"), {
      empresaId: "EMP_B",
    })
  );
  await assertFails(
    updateDoc(doc(alice, "TBL_GD_EXPEDIENTES/exp_a"), {
      empresaId: "EMP_B",
    })
  );
});

test("un usuario no puede ascenderse creando su propio rol", async () => {
  const bob = auth("bob");
  await assertFails(
    setDoc(doc(bob, "TBL_INTERVENTORIA_ROLES/EMP_B_bob"), {
      empresaId: "EMP_B",
      userId: "bob",
      rol: "admin_interventoria",
    })
  );
  await assertFails(
    setDoc(doc(bob, "TBL_CORREO_ROLES/EMP_B_bob"), {
      empresaId: "EMP_B",
      usuarioId: "bob",
      rol: "administrador",
    })
  );
});

test("los administradores funcionales gestionan roles y maestros", async () => {
  const alice = auth("alice");
  await assertSucceeds(
    setDoc(doc(alice, "TBL_INTERVENTORIA_ROLES/EMP_A_revisor"), {
      empresaId: "EMP_A",
      userId: "revisor",
      rol: "revisor_interventoria",
    })
  );
  await assertSucceeds(
    setDoc(doc(alice, "TBL_GD_TIPOS_DOCUMENTALES/EMP_A_TUT"), {
      empresaId: "EMP_A",
      codigo: "TUT",
      nombre: "Tutela",
    })
  );
});

test("un miembro sin rol no modifica matrices o tipos documentales", async () => {
  const bob = auth("bob");
  await assertFails(
    setDoc(doc(bob, "TBL_INTERVENTORIA_CONFIG/EMP_B"), {
      empresaId: "EMP_B",
      reglasSubsanacion: {},
    })
  );
  await assertFails(
    setDoc(doc(bob, "TBL_GD_TIPOS_DOCUMENTALES/EMP_B_SOL"), {
      empresaId: "EMP_B",
      codigo: "SOL",
      nombre: "Solicitud",
    })
  );
});

