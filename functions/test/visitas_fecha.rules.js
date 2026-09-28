/**
 * Reglas de Visitas, 28 sep 2026:
 * - La visita se programa sin formato; el profesional lo fija al iniciarla y
 *   tiene que ser un formato vigente de su departamento.
 * - Se inicia y se cierra el día programado ("debe terminarse el mismo día").
 * - El profesional ya no reprograma: pide el cambio de fecha y el jefe lo
 *   aprueba o lo rechaza. Aprobar una visita en curso la devuelve a
 *   programada sin inicio ni firmas.
 * - Un formato se puede pasar a otro departamento (Desarrollo y Gerencia).
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
  setDoc,
  updateDoc,
  writeBatch,
} = require("firebase/firestore");

const projectId = "capital-uspec-visitas-fecha";
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

const AREA = "EMP_A_talento_humano";

const formato = {
  empresaId: "EMP_A",
  areaId: AREA,
  areaNombre: "Talento Humano",
  nombre: "Inspección SST",
  version: 1,
  estado: "vigente",
  predeterminado: true,
  items: [{id: "s1", orden: 1, texto: "Extintores señalizados"}],
  partes: [],
  tablas: [],
  cargos: [],
};

function dia(offset) {
  const d = new Date();
  d.setHours(0, 0, 0, 0);
  d.setDate(d.getDate() + offset);
  return d;
}

function visita(extra = {}) {
  return {
    empresaId: "EMP_A",
    formatoId: "",
    formatoNombre: "",
    esPrueba: false,
    areaId: AREA,
    areaNombre: "Talento Humano",
    centroId: "C1",
    centroNombre: "Buen Pastor",
    subcentroId: "",
    subcentroNombre: "",
    profesionalId: "prof",
    profesionalNombre: "Yesika",
    asignadoPorId: "jefe",
    asignadoPorNombre: "Zuly",
    fechaProgramada: dia(0),
    estado: "programada",
    ...extra,
  };
}

const inicio = {
  estado: "en_curso",
  inicio: {at: new Date(), lat: 5.5, lng: -73.3},
  responsableEstablecimiento: {nombre: "Admin", cargo: "", userId: ""},
  ciudad: "Tunja",
  cargoProfesional: "Supervisor de HSE",
};

const conFormato = {
  formatoId: "F1",
  formatoNombre: formato.nombre,
  formatoAsignado: formato,
};

function solicitud(extra = {}) {
  return {
    fecha: dia(2),
    motivo: "Paro de transporte",
    porId: "prof",
    porNombre: "Yesika",
    estado: "pendiente",
    at: new Date(),
    ...extra,
  };
}

test.before(async () => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST, "Usa el emulador.");
  env = await initializeTestEnvironment({projectId, firestore: {rules}});
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const miembro = (nombre) => ({nombre, empresas: ["EMP_A"], empresaId: "EMP_A"});
    await Promise.all([
      setDoc(doc(db, "TBL_USUARIOS/dev"), {...miembro("Dev"), desarrollador: true}),
      setDoc(doc(db, "TBL_USUARIOS/jefe"), miembro("Zuly")),
      setDoc(doc(db, "TBL_USUARIOS/prof"), miembro("Yesika")),
      setDoc(doc(db, "TBL_USUARIOS/prof2"), miembro("Otro profesional")),
      setDoc(doc(db, "TBL_VISITAS_ROLES/EMP_A_jefe"), {
        empresaId: "EMP_A", userId: "jefe", rol: "jefe", areaId: AREA,
      }),
      setDoc(doc(db, "TBL_VISITAS_ROLES/EMP_A_prof"), {
        empresaId: "EMP_A", userId: "prof", rol: "profesional", areaId: AREA,
      }),
      setDoc(doc(db, "TBL_VISITAS_ROLES/EMP_A_prof2"), {
        empresaId: "EMP_A", userId: "prof2", rol: "profesional",
        areaId: "EMP_A_contabilidad",
      }),
      setDoc(doc(db, "TBL_VISITAS_FORMATOS/F1"), formato),
      setDoc(doc(db, "TBL_VISITAS_FORMATOS/F2"), {
        ...formato, areaId: "EMP_A_contabilidad", areaNombre: "Contabilidad",
      }),
      setDoc(doc(db, "TBL_VISITAS_FORMATOS/HSE"), {
        ...formato, areaId: "hse", areaNombre: "SST / HSE",
      }),
      setDoc(doc(db, "TBL_VISITAS/hoy"), visita()),
      setDoc(doc(db, "TBL_VISITAS/hoy2"), visita()),
      setDoc(doc(db, "TBL_VISITAS/ayer"), visita({fechaProgramada: dia(-1)})),
      setDoc(doc(db, "TBL_VISITAS/manana"), visita({fechaProgramada: dia(1)})),
      setDoc(doc(db, "TBL_VISITAS/cursoHoy"), visita({
        ...inicio, ...conFormato,
        firmaProfesional: null, firmaEstablecimiento: null,
      })),
      setDoc(doc(db, "TBL_VISITAS/cursoAyer"), visita({
        ...inicio, ...conFormato, fechaProgramada: dia(-1),
        firmaProfesional: {nombre: "Yesika", modo: "dibujada"},
        firmaEstablecimiento: null,
        solicitudCambioFecha: solicitud(),
      })),
      setDoc(doc(db, "TBL_VISITAS/pedida"), visita({
        fechaProgramada: dia(1), solicitudCambioFecha: solicitud(),
      })),
    ]);
  });
});

test.after(async () => {
  await env.cleanup();
});

test("el jefe programa sin formato, solo a profesionales de su departamento", async () => {
  const db = auth("jefe");
  await assertSucceeds(setDoc(doc(db, "TBL_VISITAS/nueva"), visita({
    fechaProgramada: dia(3),
  })));
  // De otro departamento no.
  await assertFails(setDoc(doc(db, "TBL_VISITAS/ajena"), visita({
    profesionalId: "prof2", fechaProgramada: dia(3),
  })));
  // Una copia de formato que no coincide con el guardado tampoco.
  await assertFails(setDoc(doc(db, "TBL_VISITAS/mala"), visita({
    formatoId: "F1", formatoAsignado: {...formato, items: []},
  })));
});

test("programar muchas fechas sin formato en un lote", async () => {
  const db = auth("jefe");
  const batch = writeBatch(db);
  for (let i = 0; i < 15; i++) {
    batch.set(doc(collection(db, "TBL_VISITAS")), visita({fechaProgramada: dia(4 + i)}));
  }
  await assertSucceeds(batch.commit());
});

test("el profesional elige el formato al iniciar, de su departamento", async () => {
  const db = auth("prof");
  // Sin formato no arranca.
  await assertFails(updateDoc(doc(db, "TBL_VISITAS/hoy"), inicio));
  // Formato de otro departamento no.
  await assertFails(updateDoc(doc(db, "TBL_VISITAS/hoy"), {
    ...inicio,
    formatoId: "F2",
    formatoNombre: formato.nombre,
    formatoAsignado: {...formato, areaId: "EMP_A_contabilidad", areaNombre: "Contabilidad"},
  }));
  // Copia distinta a la guardada no.
  await assertFails(updateDoc(doc(db, "TBL_VISITAS/hoy"), {
    ...inicio, ...conFormato, formatoAsignado: {...formato, version: 7},
  }));
  await assertSucceeds(updateDoc(doc(db, "TBL_VISITAS/hoy"), {
    ...inicio, ...conFormato,
  }));
});

test("solo se inicia el día programado", async () => {
  const db = auth("prof");
  await assertFails(updateDoc(doc(db, "TBL_VISITAS/ayer"), {
    ...inicio, ...conFormato,
  }));
  await assertFails(updateDoc(doc(db, "TBL_VISITAS/manana"), {
    ...inicio, ...conFormato,
  }));
});

test("se cierra el mismo día; al día siguiente no", async () => {
  const db = auth("prof");
  const cierre = {
    estado: "terminada", fin: {at: new Date()}, cumplimiento: 100,
    tareasCreadas: [], cerradaPor: "prof",
  };
  await assertFails(updateDoc(doc(db, "TBL_VISITAS/cursoAyer"), cierre));
  await assertSucceeds(updateDoc(doc(db, "TBL_VISITAS/cursoHoy"), cierre));
});

test("el profesional ya no reprograma: pide el cambio", async () => {
  const db = auth("prof");
  await assertFails(updateDoc(doc(db, "TBL_VISITAS/hoy2"), {
    fechaProgramada: dia(5),
    reprogramaciones: [{motivo: "yo mismo"}],
  }));
  // A nombre de otro no.
  await assertFails(updateDoc(doc(db, "TBL_VISITAS/hoy2"), {
    solicitudCambioFecha: solicitud({porId: "jefe"}),
  }));
  // Aprobada por él mismo no.
  await assertFails(updateDoc(doc(db, "TBL_VISITAS/hoy2"), {
    solicitudCambioFecha: solicitud({estado: "aprobada"}),
  }));
  await assertSucceeds(updateDoc(doc(db, "TBL_VISITAS/hoy2"), {
    solicitudCambioFecha: solicitud(),
  }));
  // Con una pendiente no manda otra.
  await assertFails(updateDoc(doc(db, "TBL_VISITAS/hoy2"), {
    solicitudCambioFecha: solicitud({motivo: "otra"}),
  }));
});

test("el jefe rechaza o aprueba la solicitud", async () => {
  const jefe = auth("jefe");
  await assertSucceeds(updateDoc(doc(jefe, "TBL_VISITAS/pedida"), {
    solicitudCambioFecha: solicitud({
      estado: "rechazada", respuesta: "Se hace en la fecha", respondidaPorId: "jefe",
    }),
  }));
  // Aprobar una en curso: vuelve a programada sin inicio ni firmas.
  await assertFails(updateDoc(doc(jefe, "TBL_VISITAS/cursoAyer"), {
    estado: "programada",
    fechaProgramada: dia(2),
    solicitudCambioFecha: solicitud({estado: "aprobada"}),
    inicio: null,
    // Deja la firma: no pasa.
  }));
  await assertSucceeds(updateDoc(doc(jefe, "TBL_VISITAS/cursoAyer"), {
    estado: "programada",
    fechaProgramada: dia(2),
    reprogramaciones: [{motivo: "Solicitud del profesional"}],
    solicitudCambioFecha: solicitud({estado: "aprobada"}),
    inicio: null,
    firmaProfesional: null,
    firmaEstablecimiento: null,
    firmanteEstablecimientoId: "",
  }));
  // El profesional no se devuelve la visita a programada por su cuenta.
  await assertFails(updateDoc(doc(auth("prof"), "TBL_VISITAS/hoy"), {
    estado: "programada",
    inicio: null,
  }));
});

test("un formato se pasa a un departamento real: Desarrollo sí, el jefe no", async () => {
  await assertFails(updateDoc(doc(auth("jefe"), "TBL_VISITAS_FORMATOS/HSE"), {
    areaId: AREA, areaNombre: "Talento Humano",
  }));
  await assertSucceeds(updateDoc(doc(auth("dev"), "TBL_VISITAS_FORMATOS/HSE"), {
    areaId: AREA, areaNombre: "Talento Humano",
  }));
  // Ya en su departamento, el jefe lo edita, pero no se lo lleva a otro.
  await assertSucceeds(updateDoc(doc(auth("jefe"), "TBL_VISITAS_FORMATOS/HSE"), {
    nombre: "Inspección SST mensual",
  }));
  await assertFails(updateDoc(doc(auth("jefe"), "TBL_VISITAS_FORMATOS/HSE"), {
    areaId: "EMP_A_contabilidad",
  }));
});
