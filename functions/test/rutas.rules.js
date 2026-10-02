/**
 * Reglas de Rutas (28 sep 2026). Antes todo Rutas caía en la regla general:
 * cualquiera con sesión, de cualquier empresa, podía darse el rol de
 * administrador, leer las claves de Google y TomTom del estudio de movilidad
 * o la ubicación en vivo de los conductores.
 *
 * - Roles: Desarrollo asigna cualquiera; el administrador de Rutas asigna los
 *   demás a otras personas, sin tocarse a sí mismo ni dar "desarrollador".
 *   La lista la lee cualquiera de la empresa (Administración la carga).
 * - Catálogos, configuración y asignaciones: los lee la empresa, los escribe
 *   Administración de Rutas. Talento Humano solo cierra la asignación de
 *   quien inhabilita.
 * - Evidencias: las ve quien tiene rol en Rutas; el conductor sube la suya y
 *   repite solo la rechazada; Calidad aprueba o rechaza.
 * - Ubicaciones: el centro de control y cada conductor la suya.
 * - Estudio de movilidad: solo Administración de Rutas.
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
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  query,
  setDoc,
  updateDoc,
  where,
} = require("firebase/firestore");

const projectId = "capital-uspec-rutas";
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

const miembroA = {empresas: ["EMP_A"], empresasDetalle: {EMP_A: {}}};

const usuarios = {
  adminR: miembroA,
  adminCal: miembroA,
  calidadR: miembroA,
  conductorR: miembroA,
  conductor2: miembroA,
  devRutas: miembroA,
  // Talento Humano: de la empresa, sin rol en Rutas.
  th: {empresas: ["EMP_A", "EMP_C"], empresasDetalle: {EMP_A: {}, EMP_C: {}}},
  dev: {desarrollador: true},
  ajeno: {empresas: ["EMP_B"], empresasDetalle: {EMP_B: {}}},
  conductorRetirado: {
    empresas: ["EMP_A"],
    empresasDetalle: {EMP_A: {estadoLaboral: "inactivo"}},
  },
};

const roles = {
  EMP_A_adminR: "admin",
  EMP_A_adminCal: "admin_calidad",
  EMP_A_calidadR: "calidad",
  EMP_A_conductorR: "conductor",
  EMP_A_conductor2: "conductor",
  EMP_A_devRutas: "desarrollador",
  EMP_A_conductorRetirado: "conductor",
  EMP_B_ajeno: "admin",
};

function evidencia(extra = {}) {
  return {
    empresaId: "EMP_A",
    rutaId: "r1",
    fecha: "2026-09-28",
    paradaNombre: "Buen Pastor",
    comida: "almuerzo",
    estado: "pendiente",
    downloadURL: "https://example.com/foto.jpg",
    createdBy: "conductorR",
    ...extra,
  };
}

function asignacion(extra = {}) {
  return {
    empresaId: "EMP_A",
    rutaId: "r1",
    rutaCodigo: "Ruta 1",
    conductorCedula: "conductorR",
    ayudanteCedula: "conductor2",
    activa: true,
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
      ...Object.entries(usuarios).map(([id, data]) =>
        setDoc(doc(db, `TBL_USUARIOS/${id}`), data)
      ),
      ...Object.entries(roles).map(([id, rol]) => {
        const [e1, e2, ...resto] = id.split("_");
        return setDoc(doc(db, `TBL_RUTAS_ROLES/${id}`), {
          empresaId: `${e1}_${e2}`,
          userId: resto.join("_"),
          rol,
        });
      }),
      setDoc(doc(db, "TBL_RUTAS/r1"), {
        empresaId: "EMP_A", codigo: "Ruta 1", activa: true, stops: [],
      }),
      setDoc(doc(db, "TBL_RUTAS_CONFIG/EMP_A"), {empresaId: "EMP_A"}),
      setDoc(doc(db, "TBL_RUTAS_ASIGNACIONES/a1"), asignacion()),
      setDoc(doc(db, "TBL_RUTAS_ASIGNACIONES/a2"), asignacion()),
      setDoc(doc(db, "TBL_RUTAS_ASIGNACIONES/a3"), asignacion()),
      setDoc(doc(db, "TBL_RUTAS_EVIDENCIAS/pend"), evidencia()),
      setDoc(doc(db, "TBL_RUTAS_EVIDENCIAS/rech"), evidencia({estado: "rechazada"})),
      setDoc(doc(db, "TBL_RUTAS_EVIDENCIAS/aprobar"), evidencia()),
      setDoc(doc(db, "TBL_RUTAS_RESUMEN_DIARIO/rs1"), {
        empresaId: "EMP_A", fecha: "2026-09-28",
      }),
      setDoc(doc(db, "TBL_RUTAS_UBICACIONES/EMP_A_conductorR"), {
        empresaId: "EMP_A", userId: "conductorR", lat: 4.6, lng: -74.1,
      }),
      setDoc(doc(db, "TBL_RUTAS_MOV_CONFIG/EMP_A"), {
        empresaId: "EMP_A", apiKeyGoogle: "clave-secreta", apiKeyTomtom: "otra",
      }),
      setDoc(doc(db, "TBL_RUTAS_MOV_HORARIOS/h1"), {empresaId: "EMP_A", hora: 7}),
      // TBL_TAREAS ya tiene regla propia (2 oct 2026): el ejemplo de la regla
      // general es una colección sin regla.
      setDoc(doc(db, "TBL_SIN_REGLA_PROPIA/t1"), {empresaId: "EMP_A", titulo: "Libre"}),
    ]);
  });
});

test.after(async () => {
  await env?.cleanup();
});

function rol(userId, valor, empresaId = "EMP_A") {
  return {empresaId, userId, cedula: userId, nombre: userId, rol: valor};
}

test("nadie se da a sí mismo el rol de administrador", async () => {
  await assertFails(
    setDoc(doc(auth("th"), "TBL_RUTAS_ROLES/EMP_A_th"), rol("th", "admin"))
  );
  await assertFails(
    setDoc(doc(auth("th"), "TBL_RUTAS_ROLES/EMP_A_nuevo"), rol("nuevo", "admin"))
  );
  await assertFails(
    updateDoc(doc(auth("conductorR"), "TBL_RUTAS_ROLES/EMP_A_conductorR"), {
      rol: "admin",
    })
  );
  // De otra empresa, tampoco.
  await assertFails(
    setDoc(doc(auth("ajeno"), "TBL_RUTAS_ROLES/EMP_A_ajeno"), rol("ajeno", "admin"))
  );
});

test("el administrador de Rutas asigna roles a otros, sin dar desarrollador", async () => {
  const admin = auth("adminR");
  await assertSucceeds(
    setDoc(doc(admin, "TBL_RUTAS_ROLES/EMP_A_nuevo"), rol("nuevo", "conductor"))
  );
  await assertSucceeds(
    updateDoc(doc(admin, "TBL_RUTAS_ROLES/EMP_A_nuevo"), {rol: "calidad"})
  );
  await assertFails(
    setDoc(doc(admin, "TBL_RUTAS_ROLES/EMP_A_otro"), rol("otro", "desarrollador"))
  );
  await assertFails(
    updateDoc(doc(admin, "TBL_RUTAS_ROLES/EMP_A_devRutas"), {rol: "conductor"})
  );
  await assertFails(
    updateDoc(doc(admin, "TBL_RUTAS_ROLES/EMP_A_adminR"), {rol: "admin_calidad"})
  );
  await assertFails(
    setDoc(doc(admin, "TBL_RUTAS_ROLES/EMP_A_raro"), rol("raro", "jefe"))
  );
  // El id tiene que ser {empresa}_{usuario}: las reglas buscan el rol ahí.
  await assertFails(
    setDoc(doc(admin, "TBL_RUTAS_ROLES/otro_id"), rol("x", "conductor"))
  );
  await assertSucceeds(deleteDoc(doc(admin, "TBL_RUTAS_ROLES/EMP_A_nuevo")));
});

test("Desarrollo asigna cualquier rol; la empresa lee la lista", async () => {
  await assertSucceeds(
    setDoc(doc(auth("dev"), "TBL_RUTAS_ROLES/EMP_A_jefa"), rol("jefa", "admin"))
  );
  await assertSucceeds(
    setDoc(doc(auth("dev"), "TBL_RUTAS_ROLES/EMP_A_jefa"), rol("jefa", "desarrollador"))
  );
  // Administración carga los roles de la empresa sin tener rol en Rutas.
  await assertSucceeds(
    getDocs(query(
      collection(auth("th"), "TBL_RUTAS_ROLES"),
      where("empresaId", "==", "EMP_A")
    ))
  );
  await assertFails(
    getDocs(query(
      collection(auth("ajeno"), "TBL_RUTAS_ROLES"),
      where("empresaId", "==", "EMP_A")
    ))
  );
});

test("las claves del estudio de movilidad solo las ve Administración de Rutas", async () => {
  for (const id of ["conductorR", "calidadR", "th", "ajeno"]) {
    await assertFails(getDoc(doc(auth(id), "TBL_RUTAS_MOV_CONFIG/EMP_A")));
  }
  await assertSucceeds(getDoc(doc(auth("adminR"), "TBL_RUTAS_MOV_CONFIG/EMP_A")));
  await assertSucceeds(getDoc(doc(auth("dev"), "TBL_RUTAS_MOV_CONFIG/EMP_A")));
  await assertSucceeds(
    setDoc(doc(auth("adminCal"), "TBL_RUTAS_MOV_CONFIG/EMP_A"), {
      empresaId: "EMP_A", apiKeyGoogle: "nueva",
    }, {merge: true})
  );
  await assertFails(
    setDoc(doc(auth("calidadR"), "TBL_RUTAS_MOV_CONFIG/EMP_A"), {
      empresaId: "EMP_A", apiKeyGoogle: "mia",
    }, {merge: true})
  );
  await assertFails(
    getDocs(query(
      collection(auth("conductorR"), "TBL_RUTAS_MOV_HORARIOS"),
      where("empresaId", "==", "EMP_A")
    ))
  );
  await assertSucceeds(
    getDocs(query(
      collection(auth("adminR"), "TBL_RUTAS_MOV_HORARIOS"),
      where("empresaId", "==", "EMP_A")
    ))
  );
});

test("rutas y configuración: las lee la empresa, las escribe Administración", async () => {
  await assertSucceeds(getDoc(doc(auth("th"), "TBL_RUTAS/r1")));
  await assertSucceeds(getDoc(doc(auth("conductorR"), "TBL_RUTAS/r1")));
  await assertFails(getDoc(doc(auth("ajeno"), "TBL_RUTAS/r1")));
  await assertSucceeds(
    getDocs(query(
      collection(auth("calidadR"), "TBL_RUTAS"),
      where("empresaId", "==", "EMP_A")
    ))
  );
  await assertFails(
    setDoc(doc(auth("th"), "TBL_RUTAS/r2"), {empresaId: "EMP_A", codigo: "X"})
  );
  await assertFails(
    updateDoc(doc(auth("calidadR"), "TBL_RUTAS/r1"), {activa: false})
  );
  await assertSucceeds(
    setDoc(doc(auth("adminR"), "TBL_RUTAS/r2"), {empresaId: "EMP_A", codigo: "X"})
  );
  await assertFails(
    updateDoc(doc(auth("adminR"), "TBL_RUTAS/r2"), {empresaId: "EMP_B"})
  );
  // La importación pregunta por ids que todavía no existen.
  await assertSucceeds(getDoc(doc(auth("adminR"), "TBL_RUTAS_ESTABLECIMIENTOS/nuevo")));

  await assertSucceeds(getDoc(doc(auth("conductorR"), "TBL_RUTAS_CONFIG/EMP_A")));
  await assertFails(
    setDoc(doc(auth("conductorR"), "TBL_RUTAS_CONFIG/EMP_A"), {
      empresaId: "EMP_A", radioValidacionMetros: 5000,
    }, {merge: true})
  );
  await assertSucceeds(
    setDoc(doc(auth("adminR"), "TBL_RUTAS_CONFIG/EMP_A"), {
      empresaId: "EMP_A", radioValidacionMetros: 300,
    }, {merge: true})
  );
  // Habilitar el módulo crea la configuración base.
  await assertSucceeds(
    setDoc(doc(auth("th"), "TBL_RUTAS_CONFIG/EMP_C"), {empresaId: "EMP_C"})
  );
  await assertFails(
    setDoc(doc(auth("th"), "TBL_RUTAS_CONFIG/EMP_C"), {
      empresaId: "EMP_C", radioValidacionMetros: 1,
    }, {merge: true})
  );
});

test("Talento Humano cierra la asignación de quien inhabilita, y nada más", async () => {
  const th = auth("th");
  await assertSucceeds(
    getDocs(query(
      collection(th, "TBL_RUTAS_ASIGNACIONES"),
      where("empresaId", "==", "EMP_A"),
      where("activa", "==", true)
    ))
  );
  await assertSucceeds(
    updateDoc(doc(th, "TBL_RUTAS_ASIGNACIONES/a1"), {
      activa: false,
      vigenteHasta: new Date(),
      cerradaPor: "inhabilitacion_talento_humano",
      cerradaCedula: "conductorR",
    })
  );
  await assertSucceeds(
    updateDoc(doc(th, "TBL_RUTAS_ASIGNACIONES/a2"), {
      ayudanteCedula: "",
      ayudanteNombre: "",
      ayudanteRetiradoPor: "inhabilitacion_talento_humano",
      ayudanteRetiradoAt: new Date(),
    })
  );
  // Cambiar el conductor o reabrir no es un cierre.
  await assertFails(
    updateDoc(doc(th, "TBL_RUTAS_ASIGNACIONES/a3"), {conductorCedula: "th"})
  );
  await assertFails(
    updateDoc(doc(th, "TBL_RUTAS_ASIGNACIONES/a3"), {
      activa: false, vigenteHasta: new Date(),
    })
  );
  await assertFails(
    setDoc(doc(th, "TBL_RUTAS_ASIGNACIONES/nueva"), asignacion())
  );
  await assertFails(
    updateDoc(doc(auth("ajeno"), "TBL_RUTAS_ASIGNACIONES/a3"), {
      activa: false,
      vigenteHasta: new Date(),
      cerradaPor: "inhabilitacion_talento_humano",
      cerradaCedula: "conductorR",
    })
  );
  await assertSucceeds(
    setDoc(doc(auth("adminR"), "TBL_RUTAS_ASIGNACIONES/nueva"), asignacion())
  );
  await assertFails(deleteDoc(doc(auth("adminR"), "TBL_RUTAS_ASIGNACIONES/nueva")));
});

test("evidencias: el conductor sube la suya y repite solo la rechazada", async () => {
  const conductor = auth("conductorR");
  await assertSucceeds(
    getDoc(doc(conductor, "TBL_RUTAS_EVIDENCIAS/nueva_inexistente"))
  );
  await assertSucceeds(
    setDoc(doc(conductor, "TBL_RUTAS_EVIDENCIAS/nueva"), evidencia())
  );
  await assertFails(
    setDoc(doc(conductor, "TBL_RUTAS_EVIDENCIAS/nueva2"),
      evidencia({createdBy: "conductor2"}))
  );
  await assertFails(
    setDoc(doc(conductor, "TBL_RUTAS_EVIDENCIAS/nueva3"),
      evidencia({estado: "aprobada"}))
  );
  await assertSucceeds(
    setDoc(doc(conductor, "TBL_RUTAS_EVIDENCIAS/rech"),
      evidencia({downloadURL: "https://example.com/otra.jpg"}))
  );
  await assertFails(
    setDoc(doc(conductor, "TBL_RUTAS_EVIDENCIAS/pend"),
      evidencia({downloadURL: "https://example.com/otra.jpg"}))
  );
  await assertSucceeds(
    getDocs(query(
      collection(conductor, "TBL_RUTAS_EVIDENCIAS"),
      where("empresaId", "==", "EMP_A"),
      where("conductorCedula", "==", "conductorR")
    ))
  );
  // Calidad no sube fotos; alguien sin rol no las ve.
  await assertFails(
    setDoc(doc(auth("calidadR"), "TBL_RUTAS_EVIDENCIAS/nueva4"),
      evidencia({createdBy: "calidadR"}))
  );
  await assertFails(getDoc(doc(auth("th"), "TBL_RUTAS_EVIDENCIAS/pend")));
  await assertFails(getDoc(doc(auth("ajeno"), "TBL_RUTAS_EVIDENCIAS/pend")));
});

test("evidencias: Calidad aprueba o rechaza sin tocar la foto", async () => {
  const calidad = auth("calidadR");
  const revision = {
    estado: "aprobada",
    revisadoPor: "calidadR",
    revisadoEn: new Date(),
    motivoRechazo: "",
  };
  await assertFails(
    updateDoc(doc(calidad, "TBL_RUTAS_EVIDENCIAS/aprobar"), {
      ...revision, downloadURL: "https://example.com/cambiada.jpg",
    })
  );
  await assertFails(
    updateDoc(doc(calidad, "TBL_RUTAS_EVIDENCIAS/aprobar"), {
      ...revision, revisadoPor: "otra",
    })
  );
  await assertFails(
    updateDoc(doc(auth("conductorR"), "TBL_RUTAS_EVIDENCIAS/aprobar"), {
      ...revision, revisadoPor: "conductorR",
    })
  );
  await assertSucceeds(
    updateDoc(doc(calidad, "TBL_RUTAS_EVIDENCIAS/aprobar"), revision)
  );
  await assertSucceeds(
    getDocs(query(
      collection(calidad, "TBL_RUTAS_RESUMEN_DIARIO"),
      where("empresaId", "==", "EMP_A")
    ))
  );
  await assertFails(
    setDoc(doc(calidad, "TBL_RUTAS_RESUMEN_DIARIO/rs2"), {empresaId: "EMP_A"})
  );
  // Borrar: solo el perfil de desarrollo.
  await assertFails(deleteDoc(doc(auth("adminR"), "TBL_RUTAS_EVIDENCIAS/pend")));
  await assertSucceeds(deleteDoc(doc(auth("devRutas"), "TBL_RUTAS_EVIDENCIAS/pend")));
});

test("ubicaciones: el centro de control y cada conductor la suya", async () => {
  const conductor = auth("conductorR");
  const ubicacion = {empresaId: "EMP_A", userId: "conductorR", lat: 4.7, lng: -74};
  await assertSucceeds(
    setDoc(doc(conductor, "TBL_RUTAS_UBICACIONES/EMP_A_conductorR"), ubicacion,
      {merge: true})
  );
  await assertSucceeds(getDoc(doc(conductor, "TBL_RUTAS_UBICACIONES/EMP_A_conductorR")));
  await assertFails(
    setDoc(doc(conductor, "TBL_RUTAS_UBICACIONES/EMP_A_conductor2"), ubicacion)
  );
  await assertFails(
    setDoc(doc(auth("conductor2"), "TBL_RUTAS_UBICACIONES/EMP_A_conductorR"), {
      ...ubicacion, userId: "conductor2",
    })
  );
  await assertFails(
    getDoc(doc(auth("conductor2"), "TBL_RUTAS_UBICACIONES/EMP_A_conductorR"))
  );
  await assertSucceeds(
    getDocs(query(
      collection(auth("adminR"), "TBL_RUTAS_UBICACIONES"),
      where("empresaId", "==", "EMP_A")
    ))
  );
  await assertFails(
    getDocs(query(
      collection(auth("calidadR"), "TBL_RUTAS_UBICACIONES"),
      where("empresaId", "==", "EMP_A")
    ))
  );
  await assertFails(
    setDoc(doc(auth("th"), "TBL_RUTAS_UBICACIONES/EMP_A_th"), {
      empresaId: "EMP_A", userId: "th", lat: 1, lng: 1,
    })
  );
});

test("un conductor inhabilitado no sube evidencias ni ve las rutas", async () => {
  const db = auth("conductorRetirado");
  await assertFails(getDoc(doc(db, "TBL_RUTAS/r1")));
  await assertFails(
    setDoc(doc(db, "TBL_RUTAS_EVIDENCIAS/retirado"),
      evidencia({createdBy: "conductorRetirado"}))
  );
});

test("la regla general sigue abierta para lo demás y cerrada para lo excluido", async () => {
  await assertSucceeds(getDoc(doc(auth("th"), "TBL_SIN_REGLA_PROPIA/t1")));
  await assertFails(getDoc(doc(auth("th"), "TBL_WHATSAPP_CONFIG/x")));
  await assertFails(getDoc(doc(auth("th"), "TBL_GD_CONTADORES/x")));
});
