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
  arrayUnion,
  collection,
  doc,
  getDoc,
  getDocs,
  query,
  setDoc,
  updateDoc,
  where,
  writeBatch,
} = require("firebase/firestore");

const rules = fs.readFileSync(
  path.resolve(__dirname, "../../firestore.rules"),
  "utf8"
);
let env;

function auth(uid) {
  return env.authenticatedContext(uid, {
    authVersion: 2,
    userDocId: uid,
  }).firestore();
}

function user(empresaId, apps, extra = {}) {
  return {
    empresaId,
    empresas: [empresaId],
    appsPorEmpresa: true,
    empresasDetalle: {[empresaId]: {apps, ...extra}},
  };
}

function task(overrides = {}) {
  return {
    titulo: "Verificar hallazgo",
    empresaId: "EMP_A",
    estado: "en_progreso",
    status: "en_progreso",
    asignado_uid: "alice",
    creador_id: "jefe",
    jefe_uid: "jefe",
    aprobador_uid: "jefe",
    sourceModule: "tareas",
    sourceType: "manual",
    ...overrides,
  };
}

/**
 * Las mismas reglas con un relleno de [margen] expresiones delante de cada
 * regla de TBL_TAREAS. Si un flujo permitido pasa con el relleno, le quedan
 * al menos [margen] de las 1000 que Firestore evalúa por petición.
 * @param {number} margen Expresiones de holgura que se exigen.
 * @return {string} Reglas con el relleno.
 */
function reglasConMargen(margen) {
  const relleno = `[${Array.from({length: margen}, (_, i) => i).join(",")}].size() >= 0 && `;
  const cambios = [
    ["allow get: if isSignedIn() && (resource == null || puedeLeerTarea(resource.data));",
      `allow get: if ${relleno}isSignedIn() && (resource == null || puedeLeerTarea(resource.data));`],
    ["allow list: if puedeLeerTarea(resource.data);",
      `allow list: if ${relleno}puedeLeerTarea(resource.data);`],
    ["allow create: if tareaNuevaValida();", `allow create: if ${relleno}tareaNuevaValida();`],
    ["allow update: if tareaActualizacionValida();",
      `allow update: if ${relleno}tareaActualizacionValida();`],
    ["&& puedeCrearEventoTarea(taskId, tipo);", `&& ${relleno}puedeCrearEventoTarea(taskId, tipo);`],
  ];
  return cambios.reduce((texto, [antes, despues]) => {
    assert.ok(texto.includes(antes), `No está en las reglas: ${antes}`);
    return texto.replace(antes, despues);
  }, rules);
}

test.before(async () => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST);
  env = await initializeTestEnvironment({
    projectId: "capital-uspec-tareas-rules",
    firestore: {rules},
  });
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await Promise.all([
      setDoc(doc(db, "TBL_USUARIOS/alice"), user("EMP_A", ["tareasdashboard"], {areaId: "SST"})),
      setDoc(doc(db, "TBL_USUARIOS/jefe"), user("EMP_A", ["tareasdashboard"])),
      setDoc(doc(db, "TBL_USUARIOS/destino"), user("EMP_A", ["tareasdashboard"])),
      setDoc(doc(db, "TBL_USUARIOS/compras"), user("EMP_A", ["tareasdashboard"], {areaId: "COMPRAS"})),
      setDoc(doc(db, "TBL_USUARIOS/lider"), user("EMP_A", ["tareasdashboard"], {puedeVerEquipo: true})),
      setDoc(doc(db, "TBL_USUARIOS/sinapp"), user("EMP_A", [])),
      setDoc(doc(db, "TBL_USUARIOS/retirado"), user("EMP_A", ["tareasdashboard"], {activo: false})),
      setDoc(doc(db, "TBL_USUARIOS/otro"), user("EMP_B", ["tareasdashboard"])),
      setDoc(doc(db, "TBL_USUARIOS/inter"), user("EMP_A", ["interventoriadashboard"])),
      setDoc(doc(db, "TBL_USUARIOS/admin"), user("EMP_A", ["admindashboard"])),
      setDoc(doc(db, "TBL_USUARIOS/dev"), {
        ...user("EMP_A", ["tareasdashboard"]),
        roleKey: "desarrollador",
      }),
      setDoc(doc(db, "TBL_TAREAS/t1"), task()),
      setDoc(doc(db, "TBL_TAREAS/inter1"), task({
        asignado_uid: "inter",
        sourceModule: "interventoria",
        sourceType: "hallazgo",
        creador_id: "interventoria_automatica",
      })),
      setDoc(doc(db, "TBL_TAREAS/inter2"), task({
        asignado_uid: "inter",
        aprobador_uid: "inter_aprob",
        jefe_uid: "inter_aprob",
        sourceModule: "interventoria",
        sourceType: "hallazgo",
        creador_id: "interventoria_automatica",
      })),
      setDoc(doc(db, "TBL_USUARIOS/inter_aprob"), user("EMP_A", ["interventoriadashboard"])),
      setDoc(doc(db, "TBL_TAREAS/b1"), task({empresaId: "EMP_B", asignado_uid: "otro"})),
      setDoc(doc(db, "TBL_TAREAS/reas"), task({titulo: "Reasignar a Compras"})),
      setDoc(doc(db, "TBL_TAREAS/fin"), task({titulo: "Cerrar con comentario"})),
      setDoc(doc(db, "TBL_TAREAS/cierre"), task({titulo: "Cierre administrativo"})),
    ]);
  });
});

test.after(async () => {
  await env?.cleanup();
});

test("lectura y consultas respetan empresa, participante y app efectiva", async () => {
  await assertSucceeds(getDoc(doc(auth("alice"), "TBL_TAREAS/t1")));
  await assertSucceeds(getDoc(doc(auth("jefe"), "TBL_TAREAS/t1")));
  await assertSucceeds(getDoc(doc(auth("lider"), "TBL_TAREAS/t1")));
  await assertSucceeds(getDoc(doc(auth("inter"), "TBL_TAREAS/inter1")));
  await assertFails(getDoc(doc(auth("otro"), "TBL_TAREAS/t1")));
  await assertFails(getDoc(doc(auth("sinapp"), "TBL_TAREAS/t1")));
  await assertFails(getDoc(doc(auth("retirado"), "TBL_TAREAS/t1")));

  await assertSucceeds(getDocs(query(
    collection(auth("alice"), "TBL_TAREAS"),
    where("empresaId", "==", "EMP_A"),
    where("asignado_uid", "==", "alice")
  )));
  await assertSucceeds(getDocs(query(
    collection(auth("jefe"), "TBL_TAREAS"),
    where("empresaId", "==", "EMP_A"),
    where("aprobador_uid", "==", "jefe")
  )));
  await assertSucceeds(getDocs(query(
    collection(auth("lider"), "TBL_TAREAS"),
    where("empresaId", "==", "EMP_A")
  )));
  await assertFails(getDocs(query(
    collection(auth("alice"), "TBL_TAREAS"),
    where("empresaId", "==", "EMP_A")
  )));
  // Sin empresa no se lista: el Home filtra por la empresa activa.
  await assertFails(getDocs(query(
    collection(auth("alice"), "TBL_TAREAS"),
    where("asignado_uid", "==", "alice")
  )));
  await assertFails(getDocs(query(
    collection(auth("otro"), "TBL_TAREAS"),
    where("empresaId", "==", "EMP_A"),
    where("asignado_uid", "==", "otro")
  )));
});

test("Desarrollo busca las tareas de una persona en todas las empresas", async () => {
  await assertSucceeds(getDocs(query(
    collection(auth("dev"), "TBL_TAREAS"),
    where("asignado_uid", "==", "otro")
  )));
  await assertSucceeds(getDocs(query(
    collection(auth("dev"), "TBL_TAREAS"),
    where("creador_id", "==", "jefe")
  )));
});

test("creación exige destino activo de la misma empresa y app del módulo", async () => {
  await assertSucceeds(setDoc(doc(auth("alice"), "TBL_TAREAS/nueva"), task({
    creador_id: "alice",
  })));
  await assertFails(setDoc(doc(auth("sinapp"), "TBL_TAREAS/sin_app"), task({
    creador_id: "sinapp",
  })));
  await assertFails(setDoc(doc(auth("alice"), "TBL_TAREAS/otro_destino"), task({
    creador_id: "alice",
    asignado_uid: "otro",
  })));
  await assertFails(setDoc(doc(auth("alice"), "TBL_TAREAS/retirado_destino"), task({
    creador_id: "alice",
    asignado_uid: "retirado",
  })));
  await assertFails(setDoc(doc(auth("alice"), "TBL_TAREAS/a_nombre_de_otro"), task({
    creador_id: "jefe",
  })));
  await assertSucceeds(setDoc(doc(auth("inter"), "TBL_TAREAS/inter_nueva"), task({
    asignado_uid: "inter",
    sourceModule: "interventoria",
    sourceType: "hallazgo",
    creador_id: "interventoria_automatica",
  })));
});

test("solo responsable solicita finalización y solo aprobador la resuelve", async () => {
  const ref = doc(auth("alice"), "TBL_TAREAS/t1");
  await assertFails(updateDoc(doc(auth("sinapp"), "TBL_TAREAS/t1"), {
    estado: "finalizado", status: "finalizado",
  }));
  await assertFails(updateDoc(ref, {titulo: "Cambio sin permiso"}));
  await assertFails(updateDoc(ref, {empresaId: "EMP_B"}));
  await assertSucceeds(updateDoc(ref, {
    estado: "por_aprobar",
    status: "por_aprobar",
    solicitud_finalizacion_estado: "pendiente",
    solicitud_finalizacion_by_uid: "alice",
    lastEventType: "solicitud_finalizacion",
  }));
  await assertFails(updateDoc(ref, {
    estado: "finalizado", status: "finalizado", approved: true,
  }));
  // Con la finalización en espera ya no se registran novedades.
  await assertFails(updateDoc(ref, {
    lastEventType: "task_novedad", lastEventText: "Otra novedad",
  }));
  await assertSucceeds(updateDoc(doc(auth("jefe"), "TBL_TAREAS/t1"), {
    estado: "finalizado",
    status: "finalizado",
    approved: true,
    solicitud_finalizacion_estado: "aprobado",
    lastEventType: "aprobada",
  }));
});

test("finalización con comentario: tarea y bitácora en la misma escritura", async () => {
  const db = auth("alice");
  const sinComentario = writeBatch(db);
  sinComentario.update(doc(db, "TBL_TAREAS/fin"), {
    estado: "por_aprobar",
    status: "por_aprobar",
    solicitud_finalizacion_estado: "pendiente",
    solicitud_finalizacion_by_uid: "alice",
    lastEventType: "solicitud_finalizacion",
  });
  sinComentario.set(doc(db, "TBL_TAREAS/fin/finalizacion/sin"), {
    type: "solicitud_finalizacion", createdBy: "alice", comment: "  ",
  });
  await assertFails(sinComentario.commit());

  const conComentario = writeBatch(db);
  conComentario.update(doc(db, "TBL_TAREAS/fin"), {
    estado: "por_aprobar",
    status: "por_aprobar",
    solicitud_finalizacion_estado: "pendiente",
    solicitud_finalizacion_by_uid: "alice",
    lastEventType: "solicitud_finalizacion",
  });
  conComentario.set(doc(db, "TBL_TAREAS/fin/finalizacion/con"), {
    type: "solicitud_finalizacion",
    createdBy: "alice",
    comment: "Se instaló el extintor y se adjunta la foto",
  });
  await assertSucceeds(conComentario.commit());

  // El responsable no inventa una finalización sin cambiar la tarea.
  await assertFails(setDoc(doc(db, "TBL_TAREAS/t1/finalizacion/falsa"), {
    type: "finalizacion", createdBy: "alice", comment: "Ya está",
  }));

  const jefe = auth("jefe");
  const aprobar = writeBatch(jefe);
  aprobar.update(doc(jefe, "TBL_TAREAS/fin"), {
    estado: "finalizado",
    status: "finalizado",
    approved: true,
    solicitud_finalizacion_estado: "aprobado",
    lastEventType: "aprobada",
  });
  aprobar.set(doc(jefe, "TBL_TAREAS/fin/finalizacion/aprobada"), {
    type: "aprobacion_finalizacion", createdBy: "jefe",
  });
  await assertSucceeds(aprobar.commit());

  // Historial: el responsable y el aprobador leen lo que se escribió.
  await assertSucceeds(getDocs(collection(auth("alice"), "TBL_TAREAS/fin/finalizacion")));
  await assertSucceeds(getDocs(collection(jefe, "TBL_TAREAS/fin/finalizacion")));
  await assertFails(getDocs(collection(auth("otro"), "TBL_TAREAS/fin/finalizacion")));
});

test("reasignación directa conserva participantes y valida destino", async () => {
  const root = doc(auth("inter"), "TBL_TAREAS/inter1");
  const cambio = (destino) => ({
    asignado_uid: destino,
    estado: "en_progreso",
    status: "en_progreso",
    reasignada_por_uid: "inter",
    reasignada_desde_uid: "inter",
    participantes_uid: arrayUnion("inter", destino),
    lastEventType: "reasignacion_directa",
  });
  await assertFails(updateDoc(root, cambio("otro")));
  await assertFails(updateDoc(root, cambio("retirado")));
  await assertFails(updateDoc(root, {
    ...cambio("destino"),
    participantes_uid: ["destino"],
  }));
  // Una tarea manual no se reasigna directo: necesita aprobación.
  await assertFails(updateDoc(doc(auth("alice"), "TBL_TAREAS/reas"), {
    ...cambio("compras"),
    reasignada_por_uid: "alice",
    reasignada_desde_uid: "alice",
    participantes_uid: arrayUnion("alice", "compras"),
  }));
  await assertSucceeds(updateDoc(root, cambio("destino")));
  await assertSucceeds(getDoc(doc(auth("destino"), "TBL_TAREAS/inter1")));
  // Quien la tenía sigue viendo su historial.
  await assertSucceeds(getDoc(doc(auth("inter"), "TBL_TAREAS/inter1")));
  // Pero ya no actúa sobre ella.
  await assertFails(updateDoc(root, cambio("inter")));
});

test("solicitud de reasignación hacia otra área y aprobación del jefe", async () => {
  const alice = auth("alice");
  const solicitud = (destino) => ({
    solicitud_reasignacion_estado: "pendiente",
    solicitud_reasignacion_by_uid: "alice",
    solicitud_reasignacion_to_uid: destino,
    solicitud_reasignacion_to_nombre: "Persona de Compras",
    solicitud_reasignacion_areaId: "COMPRAS",
    solicitud_reasignacion_areaNombre: "Compras",
    lastEventType: "solicitud_reasignacion",
  });
  await assertFails(updateDoc(doc(alice, "TBL_TAREAS/reas"), solicitud("otro")));
  await assertFails(updateDoc(doc(alice, "TBL_TAREAS/reas"), solicitud("retirado")));
  await assertFails(updateDoc(doc(alice, "TBL_TAREAS/reas"), solicitud("alice")));
  await assertSucceeds(updateDoc(doc(alice, "TBL_TAREAS/reas"), solicitud("compras")));
  await assertFails(updateDoc(doc(alice, "TBL_TAREAS/reas"), solicitud("destino")));

  const jefe = auth("jefe");
  // El jefe no cambia el destino que se pidió.
  await assertFails(updateDoc(doc(jefe, "TBL_TAREAS/reas"), {
    asignado_uid: "destino",
    estado: "en_progreso",
    status: "en_progreso",
    solicitud_reasignacion_estado: "aprobada",
    participantes_uid: arrayUnion("alice", "destino"),
    lastEventType: "reasignacion_aprobada",
  }));
  await assertSucceeds(updateDoc(doc(jefe, "TBL_TAREAS/reas"), {
    asignado_uid: "compras",
    asignado_nombre: "Persona de Compras",
    areaId: "COMPRAS",
    estado: "en_progreso",
    status: "en_progreso",
    reasignado: false,
    solicitud_reasignacion_estado: "aprobada",
    participantes_uid: arrayUnion("alice", "compras"),
    lastEventType: "reasignacion_aprobada",
  }));

  await assertSucceeds(getDoc(doc(auth("compras"), "TBL_TAREAS/reas")));
  // "Antes asignadas": la consulta por participante con empresa.
  await assertSucceeds(getDocs(query(
    collection(alice, "TBL_TAREAS"),
    where("participantes_uid", "array-contains", "alice"),
    where("empresaId", "==", "EMP_A")
  )));
  await assertSucceeds(getDocs(collection(alice, "TBL_TAREAS/reas/novedades")));
});

test("novedad y avance del responsable con su bitácora", async () => {
  const db = auth("alice");
  const novedad = writeBatch(db);
  novedad.set(doc(db, "TBL_TAREAS/nueva/novedades/uno"), {by: "alice", message: "Bloqueo"});
  novedad.update(doc(db, "TBL_TAREAS/nueva"), {
    lastEventType: "task_novedad", lastEventText: "Bloqueo",
  });
  await assertSucceeds(novedad.commit());
  await assertFails(updateDoc(doc(db, "TBL_TAREAS/nueva/novedades/uno"), {message: "Alterado"}));
  await assertFails(setDoc(doc(auth("otro"), "TBL_TAREAS/nueva/novedades/dos"), {
    by: "otro", message: "Falso",
  }));
  await assertFails(setDoc(doc(auth("jefe"), "TBL_TAREAS/nueva/novedades/tres"), {
    by: "jefe", message: "Suplantación",
  }));

  const avance = writeBatch(db);
  avance.set(doc(db, "TBL_TAREAS/nueva/avances/uno"), {by: "alice", message: "50%"});
  avance.update(doc(db, "TBL_TAREAS/nueva"), {
    lastEventType: "task_avance", lastEventText: "50%",
  });
  await assertSucceeds(avance.commit());
  await assertSucceeds(updateDoc(doc(db, "TBL_TAREAS/nueva"), {visto: true}));
  await assertSucceeds(updateDoc(doc(auth("lider"), "TBL_TAREAS/nueva"), {visto: true}));
  await assertFails(updateDoc(doc(auth("sinapp"), "TBL_TAREAS/nueva"), {visto: true}));
});

test("devolución del aprobador con su novedad", async () => {
  await env.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "TBL_TAREAS/dev1"), task({
      estado: "por_aprobar",
      status: "por_aprobar",
      solicitud_finalizacion_estado: "pendiente",
    }));
  });
  const jefe = auth("jefe");
  const lote = writeBatch(jefe);
  lote.update(doc(jefe, "TBL_TAREAS/dev1"), {
    estado: "devuelta",
    status: "devuelta",
    approved: false,
    solicitud_finalizacion_estado: "rechazado",
    lastEventType: "task_devuelta",
  });
  lote.set(doc(jefe, "TBL_TAREAS/dev1/novedades/devolucion"), {
    type: "devolucion", reason: "Falta la foto",
  });
  await assertSucceeds(lote.commit());
});

test("Interventoría aprueba la subsanación sin solicitud pendiente en la tarea", async () => {
  const db = auth("inter_aprob");
  await assertFails(updateDoc(doc(auth("inter"), "TBL_TAREAS/inter2"), {
    estado: "finalizado",
    status: "finalizado",
    solicitud_finalizacion_estado: "aprobado",
    solicitud_finalizacion_resuelto_por: "inter",
  }));
  await assertSucceeds(setDoc(doc(db, "TBL_TAREAS/inter2"), {
    estado: "finalizado",
    status: "finalizado",
    solicitud_finalizacion_estado: "aprobado",
    solicitud_finalizacion_resuelto_por: "inter_aprob",
  }, {merge: true}));
});

test("cierre administrativo y mantenimiento de Desarrollo", async () => {
  await assertFails(setDoc(doc(auth("alice"), "TBL_TAREAS/cierre"), {
    estado: "finalizado",
    status: "finalizado",
    lastEventType: "admin_module_closeout",
  }, {merge: true}));
  await assertSucceeds(setDoc(doc(auth("admin"), "TBL_TAREAS/cierre"), {
    estado: "finalizado",
    status: "finalizado",
    solicitud_finalizacion_estado: "aprobado",
    lastEventType: "admin_module_closeout",
  }, {merge: true}));
  // Cambio de cédula: Desarrollo mueve responsable y creador, no la empresa.
  await assertSucceeds(updateDoc(doc(auth("dev"), "TBL_TAREAS/t1"), {
    creador_id: "jefe_nuevo",
  }));
  await assertFails(updateDoc(doc(auth("dev"), "TBL_TAREAS/t1"), {
    empresaId: "EMP_B",
  }));
});

test("los flujos permitidos más caros dejan margen bajo el tope de 1000", async () => {
  const margen = 150;
  const holgado = await initializeTestEnvironment({
    projectId: "capital-uspec-tareas-margen",
    firestore: {rules: reglasConMargen(margen)},
  });
  try {
    await holgado.clearFirestore();
    await holgado.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await Promise.all([
        setDoc(doc(db, "TBL_USUARIOS/alice"), user("EMP_A", ["tareasdashboard"])),
        setDoc(doc(db, "TBL_USUARIOS/jefe"), user("EMP_A", ["tareasdashboard"])),
        setDoc(doc(db, "TBL_USUARIOS/destino"), user("EMP_A", ["tareasdashboard"])),
        setDoc(doc(db, "TBL_USUARIOS/lider"), user("EMP_A", ["tareasdashboard"], {puedeVerEquipo: true})),
        setDoc(doc(db, "TBL_USUARIOS/inter"), user("EMP_A", ["interventoriadashboard"])),
        setDoc(doc(db, "TBL_USUARIOS/admin"), user("EMP_A", ["admindashboard"])),
        setDoc(doc(db, "TBL_TAREAS/m1"), task()),
        setDoc(doc(db, "TBL_TAREAS/m2"), task({
          asignado_uid: "inter",
          aprobador_uid: "inter",
          jefe_uid: "inter",
          sourceModule: "interventoria",
          sourceType: "hallazgo",
          creador_id: "interventoria_automatica",
        })),
        setDoc(doc(db, "TBL_TAREAS/m3"), task({
          asignado_uid: "inter",
          sourceModule: "interventoria",
          sourceType: "hallazgo",
          creador_id: "interventoria_automatica",
        })),
      ]);
    });
    // Cada paso dice su nombre: si uno se queda sin margen se sabe cuál.
    const paso = async (nombre, promesa) => {
      try {
        await assertSucceeds(promesa);
      } catch (error) {
        throw new Error(`${nombre}: ${error.message}`);
      }
    };
    const como = (uid) => holgado.authenticatedContext(uid, {
      authVersion: 2,
      userDocId: uid,
    }).firestore();

    await paso("leer como líder del equipo", getDoc(doc(como("lider"), "TBL_TAREAS/m1")));
    await paso("leer como Admin", getDoc(doc(como("admin"), "TBL_TAREAS/m1")));
    await paso("crear desde Interventoría", setDoc(doc(como("inter"), "TBL_TAREAS/m_nueva"), task({
      asignado_uid: "destino",
      sourceModule: "interventoria",
      sourceType: "hallazgo",
      creador_id: "interventoria_automatica",
    })));
    await paso("reasignar directo en Interventoría", updateDoc(doc(como("inter"), "TBL_TAREAS/m3"), {
      asignado_uid: "destino",
      estado: "en_progreso",
      status: "en_progreso",
      reasignada_por_uid: "inter",
      reasignada_desde_uid: "inter",
      participantes_uid: arrayUnion("inter", "destino"),
      lastEventType: "reasignacion_directa",
    }));
    await paso("aprobar la subsanación", setDoc(doc(como("inter"), "TBL_TAREAS/m2"), {
      estado: "finalizado",
      status: "finalizado",
      solicitud_finalizacion_estado: "aprobado",
      solicitud_finalizacion_resuelto_por: "inter",
    }, {merge: true}));

    const alice = como("alice");
    await paso("pedir reasignación", updateDoc(doc(alice, "TBL_TAREAS/m1"), {
      solicitud_reasignacion_estado: "pendiente",
      solicitud_reasignacion_by_uid: "alice",
      solicitud_reasignacion_to_uid: "destino",
      lastEventType: "solicitud_reasignacion",
    }));
    await paso("aprobar la reasignación", updateDoc(doc(como("jefe"), "TBL_TAREAS/m1"), {
      asignado_uid: "destino",
      estado: "en_progreso",
      status: "en_progreso",
      solicitud_reasignacion_estado: "aprobada",
      participantes_uid: arrayUnion("alice", "destino"),
      lastEventType: "reasignacion_aprobada",
    }));
    const destino = como("destino");
    const cierre = writeBatch(destino);
    cierre.update(doc(destino, "TBL_TAREAS/m1"), {
      estado: "por_aprobar",
      status: "por_aprobar",
      solicitud_finalizacion_estado: "pendiente",
      solicitud_finalizacion_by_uid: "destino",
      lastEventType: "solicitud_finalizacion",
    });
    cierre.set(doc(destino, "TBL_TAREAS/m1/finalizacion/uno"), {
      type: "solicitud_finalizacion",
      createdBy: "destino",
      comment: "Listo",
    });
    await paso("solicitar finalización con comentario", cierre.commit());
    await paso("leer la bitácora como responsable anterior", getDocs(collection(alice, "TBL_TAREAS/m1/finalizacion")));
  } finally {
    await holgado.cleanup();
  }
});
