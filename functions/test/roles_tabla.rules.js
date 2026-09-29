/**
 * Roles configurables de los módulos con tabla propia (29 sep 2026):
 * Compras, Rutas e Interventoría. Admin de la empresa, Desarrollo o el
 * administrador del módulo crean las definiciones en TBL_ROLES y asignan en
 * la tabla del módulo `{empresa}_{usuario}`; nadie se asigna a sí mismo por
 * ser admin del módulo. Y Compras queda por empresa: antes todo estaba en la
 * regla general.
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

const projectId = "capital-uspec-roles-tabla";
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

const miembroA = {empresas: ["EMP_A"], apps: ["comprasdashboard"], empresasDetalle: {EMP_A: {}}};

const usuarios = {
  adminApp: {
    empresas: ["EMP_A"],
    appsPorEmpresa: true,
    empresasDetalle: {EMP_A: {apps: ["admindashboard"]}},
  },
  jefaCompras: miembroA,
  jefeRutas: miembroA,
  comun: miembroA,
  ajeno: {empresas: ["EMP_B"], empresasDetalle: {EMP_B: {}}},
};

function asignacion(userId, rol, empresaId = "EMP_A") {
  return {empresaId, userId, cedula: userId, nombre: userId, rol};
}

function definicion(moduleId, extra = {}) {
  return {
    empresaId: "EMP_A",
    type: "module_role",
    moduleId,
    nombre: "Rol de prueba",
    baseRole: "compras",
    enabled: true,
    revision: 1,
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
      setDoc(doc(db, "TBL_COMPRAS_ROLES/EMP_A_jefaCompras"),
        asignacion("jefaCompras", "admin")),
      setDoc(doc(db, "TBL_RUTAS_ROLES/EMP_A_jefeRutas"),
        asignacion("jefeRutas", "admin")),
      setDoc(doc(db, "TBL_COMPRAS_PROVEEDORES/p1"), {
        empresaId: "EMP_A", nombre: "Proveedor",
      }),
      setDoc(doc(db, "TBL_COMPRAS_APROBACIONES/ap1"), {
        empresaId: "EMP_A", entidadId: "p1", accion: "aprobado",
      }),
      setDoc(doc(db, "TBL_COMPRAS_CONFIG/EMP_A"), {marcaSeq: 3}),
    ]);
  });
});

test.after(async () => {
  await env?.cleanup();
});

test("definiciones: Admin de la empresa y el admin del propio módulo", async () => {
  for (const moduleId of ["comprasdashboard", "rutasdashboard",
    "interventoriadashboard"]) {
    await assertSucceeds(
      setDoc(doc(auth("adminApp"), `TBL_ROLES/EMP_A_mod_${moduleId}_x`),
        definicion(moduleId))
    );
  }
  await assertSucceeds(
    setDoc(doc(auth("jefaCompras"), "TBL_ROLES/EMP_A_mod_compras_bodega"),
      definicion("comprasdashboard", {baseRole: "bodega"}))
  );
  // La admin de Compras no crea roles de Rutas; alguien común, ninguno.
  await assertFails(
    setDoc(doc(auth("jefaCompras"), "TBL_ROLES/EMP_A_mod_rutas_y"),
      definicion("rutasdashboard"))
  );
  await assertFails(
    setDoc(doc(auth("comun"), "TBL_ROLES/EMP_A_mod_compras_z"),
      definicion("comprasdashboard"))
  );
});

test("Compras: nadie se da el rol de admin", async () => {
  await assertFails(
    setDoc(doc(auth("comun"), "TBL_COMPRAS_ROLES/EMP_A_comun"),
      asignacion("comun", "admin"))
  );
  await assertFails(
    setDoc(doc(auth("ajeno"), "TBL_COMPRAS_ROLES/EMP_A_ajeno"),
      asignacion("ajeno", "admin"))
  );
  // La admin de Compras asigna a otros, no a sí misma.
  await assertSucceeds(
    setDoc(doc(auth("jefaCompras"), "TBL_COMPRAS_ROLES/EMP_A_comun"),
      asignacion("comun", "bodega"))
  );
  await assertFails(
    updateDoc(doc(auth("jefaCompras"), "TBL_COMPRAS_ROLES/EMP_A_jefaCompras"),
      {rol: "calidad"})
  );
});

test("Compras: Admin asigna con el contrato", async () => {
  const admin = auth("adminApp");
  await assertSucceeds(
    setDoc(doc(admin, "TBL_COMPRAS_ROLES/EMP_A_nuevo"),
      {...asignacion("nuevo", "calidad"), rolComprasId: "EMP_A_mod_compras_x"})
  );
  await assertFails(
    setDoc(doc(admin, "TBL_COMPRAS_ROLES/EMP_A_otro"),
      asignacion("otro", "jefe"))
  );
  await assertFails(
    setDoc(doc(admin, "TBL_COMPRAS_ROLES/id_raro"), asignacion("otro", "compras"))
  );
  await assertFails(deleteDoc(doc(admin, "TBL_COMPRAS_ROLES/EMP_A_nuevo")));
  // Quien no tiene rol pregunta por el suyo y recibe vacío; la empresa lista.
  await assertSucceeds(getDoc(doc(auth("comun"), "TBL_COMPRAS_ROLES/EMP_A_nadie")));
  await assertSucceeds(
    getDocs(query(
      collection(auth("comun"), "TBL_COMPRAS_ROLES"),
      where("empresaId", "==", "EMP_A")
    ))
  );
  await assertFails(
    getDocs(query(
      collection(auth("ajeno"), "TBL_COMPRAS_ROLES"),
      where("empresaId", "==", "EMP_A")
    ))
  );
});

test("Compras: los datos quedan en su empresa", async () => {
  await assertSucceeds(getDoc(doc(auth("comun"), "TBL_COMPRAS_PROVEEDORES/p1")));
  await assertFails(getDoc(doc(auth("ajeno"), "TBL_COMPRAS_PROVEEDORES/p1")));
  await assertFails(
    updateDoc(doc(auth("comun"), "TBL_COMPRAS_PROVEEDORES/p1"), {empresaId: "EMP_B"})
  );
  await assertSucceeds(
    setDoc(doc(auth("comun"), "TBL_COMPRAS_PROVEEDORES/p2"), {
      empresaId: "EMP_A", nombre: "Nuevo",
    })
  );
  await assertFails(
    setDoc(doc(auth("ajeno"), "TBL_COMPRAS_PROVEEDORES/p3"), {
      empresaId: "EMP_A", nombre: "Colado",
    })
  );
  // El historial de aprobaciones ahora consulta con la empresa.
  await assertSucceeds(
    getDocs(query(
      collection(auth("comun"), "TBL_COMPRAS_APROBACIONES"),
      where("empresaId", "==", "EMP_A"),
      where("entidadId", "==", "p1")
    ))
  );
  await assertFails(
    getDocs(query(
      collection(auth("comun"), "TBL_COMPRAS_APROBACIONES"),
      where("entidadId", "==", "p1")
    ))
  );
  // La configuración va por el id: cualquiera de la empresa lleva el
  // consecutivo de marcas.
  await assertSucceeds(
    setDoc(doc(auth("comun"), "TBL_COMPRAS_CONFIG/EMP_A"), {marcaSeq: 4},
      {merge: true})
  );
  await assertFails(getDoc(doc(auth("ajeno"), "TBL_COMPRAS_CONFIG/EMP_A")));
});

test("Rutas: Admin asigna sin el perfil de desarrollo y puede dejarlo vacío", async () => {
  const admin = auth("adminApp");
  await assertSucceeds(
    setDoc(doc(admin, "TBL_RUTAS_ROLES/EMP_A_c1"), asignacion("c1", "conductor"))
  );
  await assertSucceeds(
    updateDoc(doc(admin, "TBL_RUTAS_ROLES/EMP_A_c1"), {rol: ""})
  );
  await assertFails(
    setDoc(doc(admin, "TBL_RUTAS_ROLES/EMP_A_c2"),
      asignacion("c2", "desarrollador"))
  );
  // El admin de Rutas sigue sin cambiarse a sí mismo.
  await assertFails(
    updateDoc(doc(auth("jefeRutas"), "TBL_RUTAS_ROLES/EMP_A_jefeRutas"),
      {rol: "admin_calidad"})
  );
});

test("Interventoría: preguntar por el rol propio y Admin asigna", async () => {
  await assertSucceeds(
    getDoc(doc(auth("comun"), "TBL_INTERVENTORIA_ROLES/EMP_A_comun"))
  );
  await assertSucceeds(
    setDoc(doc(auth("adminApp"), "TBL_INTERVENTORIA_ROLES/EMP_A_rev"),
      asignacion("rev", "revisor_interventoria"))
  );
  await assertFails(
    setDoc(doc(auth("adminApp"), "TBL_INTERVENTORIA_ROLES/EMP_A_rev2"),
      asignacion("rev2", "inventado"))
  );
  await assertFails(
    setDoc(doc(auth("comun"), "TBL_INTERVENTORIA_ROLES/EMP_A_comun"),
      asignacion("comun", "admin_interventoria"))
  );
});

test("Visitas: Admin asigna con área y sin dar Gerencia; lee la lista", async () => {
  const admin = auth("adminApp");
  await assertSucceeds(
    setDoc(doc(admin, "TBL_VISITAS_ROLES/EMP_A_prof"), {
      ...asignacion("prof", "profesional"), areaId: "EMP_A_nutricion",
    })
  );
  await assertSucceeds(
    updateDoc(doc(admin, "TBL_VISITAS_ROLES/EMP_A_prof"), {rol: "", areaId: ""})
  );
  await assertFails(
    setDoc(doc(admin, "TBL_VISITAS_ROLES/EMP_A_ger"), {
      ...asignacion("ger", "gerencia"), areaId: "",
    })
  );
  await assertSucceeds(
    getDocs(query(
      collection(admin, "TBL_VISITAS_ROLES"),
      where("empresaId", "==", "EMP_A")
    ))
  );
  // Alguien común solo ve el suyo.
  await assertFails(
    getDocs(query(
      collection(auth("comun"), "TBL_VISITAS_ROLES"),
      where("empresaId", "==", "EMP_A")
    ))
  );
  await assertFails(
    setDoc(doc(auth("comun"), "TBL_VISITAS_ROLES/EMP_A_comun"), {
      ...asignacion("comun", "jefe"), areaId: "EMP_A_nutricion",
    })
  );
});
