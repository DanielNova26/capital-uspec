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
  writeBatch,
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

test("Planillas avanza solo con el rol y la empresa de cada etapa", async () => {
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await Promise.all([
      ...["tesoreria", "auditoria", "gerencia"].map((rol) =>
        setDoc(doc(db, `TBL_USUARIOS/pp_${rol}`), {
          empresaId: "EMP_B",
          appsPorEmpresa: true,
          empresasDetalle: {
            EMP_A: {
              apps: ["planillaspagodashboard"],
              rolPlanillas: rol,
              rolPlanillasId: `EMP_A_${rol}`,
            },
            EMP_B: {apps: ["planillaspagodashboard"]},
          },
        })),
    ]);
  });

  const teso = auth("pp_tesoreria");
  const audit = auth("pp_auditoria");
  const ger = auth("pp_gerencia");
  const planilla = "TBL_PP_PLANILLAS/flujo";
  const datos = {
    empresaId: "EMP_A",
    loteId: "lote",
    estado: "en_revision_auditoria",
    cargadoPor: "pp_tesoreria",
    pathPdf: "planillas_pago/EMP_A/lote/pdfs/original.pdf",
  };
  await assertFails(setDoc(doc(audit, planilla), datos));
  await assertFails(setDoc(doc(teso, planilla), {...datos, empresaId: "EMP_B"}));
  const carga = writeBatch(teso);
  carga.set(doc(teso, "TBL_PP_LOTES/lote"), {
    empresaId: "EMP_A", creadoPor: "pp_tesoreria",
  });
  carga.set(doc(teso, planilla), datos);
  carga.set(doc(teso, "TBL_PP_FLUJO/carga"), {
    empresaId: "EMP_A", realizadoPor: "pp_tesoreria",
    accion: "carga_enviada_auditoria",
  });
  await assertSucceeds(carga.commit());
  await assertFails(getDoc(doc(auth("bob"), planilla)));
  await assertSucceeds(getDoc(doc(audit, planilla)));
  const aprobacion = {
    estado: "pendiente_firma_gerencia",
    revisadoPor: "pp_auditoria",
    pathPdf: "planillas_pago/EMP_A/firmados/auditoria.pdf",
  };
  await assertFails(updateDoc(doc(teso, planilla), aprobacion));
  await assertFails(setDoc(doc(teso, "TBL_PP_FLUJO/firmado"), {
    empresaId: "EMP_A", realizadoPor: "pp_tesoreria", accion: "firmado",
  }));
  await assertFails(updateDoc(doc(audit, planilla), {
    ...aprobacion, pathPdf: datos.pathPdf,
  }));
  await assertSucceeds(updateDoc(doc(audit, planilla), aprobacion));
  await assertFails(updateDoc(doc(audit, planilla), {
    estado: "firmada", firmadoPor: "pp_auditoria",
  }));
  await assertSucceeds(updateDoc(doc(ger, planilla), {
    estado: "firmada", firmadoPor: "pp_gerencia",
  }));
  await assertFails(updateDoc(doc(teso, "TBL_PP_FLUJO/carga"), {empresaId: "EMP_B"}));
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

