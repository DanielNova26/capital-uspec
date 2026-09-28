/**
 * Personal inhabilitado en las reglas (28 sep 2026).
 *
 * La regla es la de `personaHabilitadaEn` (lib/utils/user_company.dart) y
 * functions/src/acceso.ts: no entra a los datos de una empresa quien tenga
 * la cuenta apagada (`activo: false`, o `estado` / `status` global distinto
 * de activo), quien esté inhabilitado ahí por Talento Humano
 * (`empresasDetalle.{empresa}.estadoLaboral` o `estado` = inactivo) ni quien
 * tenga la empresa apagada por un traslado (`activo: false` en su bloque).
 * Si sigue habilitado en otra empresa, entra solo a esa. El rol de
 * desarrollador no salta la regla.
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
const {
  collection,
  doc,
  getDoc,
  getDocs,
  query,
  setDoc,
  updateDoc,
  where,
} = require("firebase/firestore");

const projectId = "capital-uspec-inhabilitados";
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

const usuarios = {
  activa: {
    empresas: ["EMP_A"],
    empresasDetalle: {EMP_A: {estadoLaboral: "activo"}},
    estado: "activo",
  },
  retiradaTH: {
    empresas: ["EMP_A"],
    empresasDetalle: {EMP_A: {estadoLaboral: "inactivo"}},
    estado: "activo",
  },
  // Retirada en A y vigente en B: entra solo a B.
  dosEmpresas: {
    empresas: ["EMP_A", "EMP_B"],
    empresasDetalle: {
      EMP_A: {estadoLaboral: "inactivo"},
      EMP_B: {estadoLaboral: "activo"},
    },
  },
  // Pasó "solo a la nueva": A quedó apagada.
  trasladada: {
    empresas: ["EMP_A", "EMP_B"],
    empresasDetalle: {EMP_A: {activo: false}, EMP_B: {}},
  },
  cuentaApagada: {empresas: ["EMP_A"], activo: false},
  estadoGlobalInactivo: {empresas: ["EMP_A"], estado: "inactivo"},
  statusViejoInactivo: {empresas: ["EMP_A"], status: "inactive"},
  statusViejoActivo: {empresas: ["EMP_A"], status: "active"},
  estadoConEspacios: {empresas: ["EMP_A"], estado: " Activo "},
  // Sin estadoLaboral cuenta el `estado` del bloque.
  estadoDelBloque: {
    empresas: ["EMP_A"],
    empresasDetalle: {EMP_A: {estado: "inactivo"}},
  },
  // estadoLaboral manda sobre el `estado` del bloque.
  estadoLaboralManda: {
    empresas: ["EMP_A"],
    empresasDetalle: {EMP_A: {estadoLaboral: "activo", estado: "inactivo"}},
  },
  dev: {desarrollador: true},
  devApagado: {desarrollador: true, activo: false},
  devRetiradoEnA: {
    desarrollador: true,
    empresas: ["EMP_A", "EMP_B"],
    empresasDetalle: {EMP_A: {estadoLaboral: "inactivo"}, EMP_B: {}},
  },
  devDeEmpresaRetirado: {
    empresasDetalle: {
      EMP_A: {roleKey: "desarrollador", estadoLaboral: "inactivo"},
    },
  },
  devDeEmpresa: {
    empresasDetalle: {
      EMP_A: {roleKey: "desarrollador", estadoLaboral: "activo"},
    },
  },
  profActivo: {
    empresas: ["EMP_A"],
    empresasDetalle: {EMP_A: {estadoLaboral: "activo"}},
  },
  profRetirado: {
    empresas: ["EMP_A"],
    empresasDetalle: {EMP_A: {estadoLaboral: "inactivo"}},
  },
};

function visita(profesionalId) {
  const hoy = new Date();
  hoy.setHours(0, 0, 0, 0);
  return {
    empresaId: "EMP_A",
    areaId: "EMP_A_nutricion",
    profesionalId,
    asignadoPorId: "jefe",
    fechaProgramada: hoy,
    estado: "programada",
    esPrueba: false,
  };
}

function solicitud(porId) {
  const fecha = new Date();
  fecha.setDate(fecha.getDate() + 2);
  return {estado: "pendiente", porId, fecha, motivo: "Paro de transporte"};
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
      ...Object.entries(usuarios).map(([id, data]) =>
        setDoc(doc(db, `TBL_USUARIOS/${id}`), data)
      ),
      setDoc(doc(db, "TBL_GD_VINCULOS/v_a"), {empresaId: "EMP_A"}),
      setDoc(doc(db, "TBL_GD_VINCULOS/v_b"), {empresaId: "EMP_B"}),
      setDoc(doc(db, "TBL_INTERVENTORIA_VISITAS/acta_a"), {
        empresaId: "EMP_A",
        faseActa: "puntajes",
      }),
      setDoc(doc(db, "TBL_INTERVENTORIA_CONFIG/EMP_A"), {empresaId: "EMP_A"}),
      setDoc(doc(db, "TBL_VISITAS_UBICACIONES/EMP_A_C1"), {
        empresaId: "EMP_A",
        centroId: "C1",
        radioMetros: 200,
      }),
      ...["profActivo", "profRetirado"].flatMap((id) => [
        setDoc(doc(db, `TBL_VISITAS_ROLES/EMP_A_${id}`), {
          empresaId: "EMP_A",
          userId: id,
          rol: "profesional",
          areaId: "EMP_A_nutricion",
        }),
        setDoc(doc(db, `TBL_VISITAS/visita_${id}`), visita(id)),
      ]),
      setDoc(doc(db, "TBL_VISITAS_UBICACIONES/EMP_B_C1"), {
        empresaId: "EMP_B",
        centroId: "C1",
        radioMetros: 200,
      }),
    ]);
  });
});

test.after(async () => {
  await env?.cleanup();
});

function leerVinculo(userId, id = "v_a") {
  return getDoc(doc(auth(userId), `TBL_GD_VINCULOS/${id}`));
}

test("el personal habilitado sigue entrando a su empresa", async () => {
  for (const id of [
    "activa",
    "statusViejoActivo",
    "estadoConEspacios",
    "estadoLaboralManda",
  ]) {
    await assertSucceeds(leerVinculo(id));
  }
  await assertSucceeds(
    getDocs(query(
      collection(auth("activa"), "TBL_INTERVENTORIA_VISITAS"),
      where("empresaId", "==", "EMP_A")
    ))
  );
  await assertSucceeds(
    setDoc(doc(auth("activa"), "TBL_GD_VINCULOS/nuevo_activa"), {
      empresaId: "EMP_A",
    })
  );
});

test("inhabilitado por Talento Humano: no lee ni escribe en esa empresa", async () => {
  const db = auth("retiradaTH");
  await assertFails(leerVinculo("retiradaTH"));
  await assertFails(getDoc(doc(db, "TBL_INTERVENTORIA_VISITAS/acta_a")));
  await assertFails(
    getDocs(query(
      collection(db, "TBL_INTERVENTORIA_VISITAS"),
      where("empresaId", "==", "EMP_A")
    ))
  );
  await assertFails(
    setDoc(doc(db, "TBL_GD_VINCULOS/nuevo_retirada"), {empresaId: "EMP_A"})
  );
  await assertFails(
    updateDoc(doc(db, "TBL_INTERVENTORIA_VISITAS/acta_a"), {
      faseActa: "revision",
    })
  );
  // Sin estadoLaboral, el `estado` del bloque decide.
  await assertFails(leerVinculo("estadoDelBloque"));
});

test("retirado en una empresa: entra solo a la otra", async () => {
  await assertFails(leerVinculo("dosEmpresas", "v_a"));
  await assertSucceeds(leerVinculo("dosEmpresas", "v_b"));
});

test("empresa apagada por un traslado: no vuelve a entrar a ella", async () => {
  await assertFails(leerVinculo("trasladada", "v_a"));
  await assertSucceeds(leerVinculo("trasladada", "v_b"));
});

test("cuenta apagada: no entra a ninguna empresa", async () => {
  for (const id of [
    "cuentaApagada",
    "estadoGlobalInactivo",
    "statusViejoInactivo",
  ]) {
    await assertFails(leerVinculo(id));
  }
});

test("un desarrollador inhabilitado pierde el rol", async () => {
  // Desarrollador habilitado: entra aunque no sea de la empresa.
  await assertSucceeds(leerVinculo("dev"));

  const apagado = auth("devApagado");
  await assertFails(leerVinculo("devApagado"));
  await assertFails(
    setDoc(doc(apagado, "TBL_INTERVENTORIA_ROLES/EMP_A_x"), {
      empresaId: "EMP_A",
      userId: "x",
      rol: "admin_interventoria",
    })
  );
  await assertFails(
    setDoc(doc(apagado, "TBL_CORREO_ROLES/EMP_A_x"), {
      empresaId: "EMP_A",
      usuarioId: "x",
      rol: "administrador",
    })
  );
  await assertFails(
    setDoc(doc(apagado, "TBL_GD_TIPOS_DOCUMENTALES/EMP_A_XYZ"), {
      empresaId: "EMP_A",
      codigo: "XYZ",
    })
  );
  await assertFails(
    updateDoc(doc(apagado, "TBL_VISITAS_UBICACIONES/EMP_A_C1"), {
      radioMetros: 500,
    })
  );
});

test("desarrollador retirado en una empresa: no la administra, la otra sí", async () => {
  const db = auth("devRetiradoEnA");
  await assertFails(
    setDoc(doc(db, "TBL_INTERVENTORIA_CONFIG/EMP_A"), {empresaId: "EMP_A"})
  );
  await assertFails(
    setDoc(doc(db, "TBL_CORREO_ROLES/EMP_A_y"), {
      empresaId: "EMP_A",
      usuarioId: "y",
      rol: "administrador",
    })
  );
  await assertFails(
    updateDoc(doc(db, "TBL_VISITAS_UBICACIONES/EMP_A_C1"), {radioMetros: 500})
  );
  await assertSucceeds(
    setDoc(doc(db, "TBL_CORREO_ROLES/EMP_B_y"), {
      empresaId: "EMP_B",
      usuarioId: "y",
      rol: "administrador",
    })
  );
  await assertSucceeds(
    updateDoc(doc(db, "TBL_VISITAS_UBICACIONES/EMP_B_C1"), {radioMetros: 300})
  );
});

test("desarrollador marcado en la empresa: inhabilitado ahí, sin rol", async () => {
  const rol = {empresaId: "EMP_A", userId: "z", rol: "admin_interventoria"};
  await assertFails(
    setDoc(doc(auth("devDeEmpresaRetirado"), "TBL_INTERVENTORIA_ROLES/EMP_A_z"), rol)
  );
  await assertSucceeds(
    setDoc(doc(auth("devDeEmpresa"), "TBL_INTERVENTORIA_ROLES/EMP_A_z"), rol)
  );
});

test("Visitas: el profesional retirado ya no ve ni toca sus visitas", async () => {
  const activo = auth("profActivo");
  await assertSucceeds(getDoc(doc(activo, "TBL_VISITAS/visita_profActivo")));
  await assertSucceeds(
    updateDoc(doc(activo, "TBL_VISITAS/visita_profActivo"), {
      solicitudCambioFecha: solicitud("profActivo"),
    })
  );

  const retirado = auth("profRetirado");
  await assertFails(getDoc(doc(retirado, "TBL_VISITAS/visita_profRetirado")));
  await assertFails(
    getDocs(query(
      collection(retirado, "TBL_VISITAS"),
      where("empresaId", "==", "EMP_A"),
      where("profesionalId", "==", "profRetirado")
    ))
  );
  await assertFails(
    updateDoc(doc(retirado, "TBL_VISITAS/visita_profRetirado"), {
      solicitudCambioFecha: solicitud("profRetirado"),
    })
  );
  await assertFails(getDoc(doc(retirado, "TBL_VISITAS_ROLES/EMP_A_profRetirado")));
});
