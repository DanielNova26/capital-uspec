const {createHash, randomBytes, scryptSync} = require('node:crypto');
const {createRequire} = require('node:module');
const requireFunctions = createRequire(require.resolve('../../functions/package.json'));
const {initializeApp} = requireFunctions('firebase-admin/app');
const {getFirestore, FieldValue} = requireFunctions('firebase-admin/firestore');
const maestroInterventoria = require('./interventoria.json');

const proyecto = 'demo-capital-servir';
const empresaId = 'DEMO_EMPRESA_APP_REVIEW';
const empresaNombre = 'ToDo Gestión Empresarial (Demo App Review)';
const claveLocal = 'SoloDemoLocal2026!';
const centroId = `${empresaId}_centro_principal`;
const sedeId = `${empresaId}_sede_demo`;
const gerenteId = '9900001000';

const modulos = {
  tareas: ['tareasdashboard', 'Tareas'],
  compras: ['comprasdashboard', 'Compras', 'rolCompras', 'TBL_COMPRAS_ROLES'],
  interventoria: ['interventoriadashboard', 'Interventoría', 'rolInterventoria', 'TBL_INTERVENTORIA_ROLES'],
  visitas: ['visitasdashboard', 'Visitas', 'rolVisitas', 'TBL_VISITAS_ROLES'],
  facturacion: ['facturaciondashboard', 'Facturación', 'rolFac'],
  correo: ['correodashboard', 'Correo', 'rolCorreo', 'TBL_CORREO_ROLES'],
  correspondencia: ['gestiondocumentaldashboard', 'Gestión de Correspondencia'],
  biblioteca: ['bibliotecadocumentaldashboard', 'Biblioteca Documental', 'rolDocumental'],
  planillas: ['planillaspagodashboard', 'Planillas de Pago', 'rolPlanillas'],
  dian: ['tokensdiandashboard', 'Tokens DIAN', 'rolTokensDian', 'TBL_DIAN_TOKEN_ROLES'],
  talento: ['talentohumanodashboard', 'Talento Humano', 'rolTalentoHumano', 'TBL_TALENTO_HUMANO_ROLES'],
  biometrico: ['biometricodashboard', 'Biométrico', 'rolBiometrico', 'TBL_BIOMETRICO_ROLES'],
  mantenimiento: ['mantenimientodashboard', 'Mantenimiento'],
  nutricion: ['nutriciondashboard', 'Nutrición', 'rolNutricion', 'TBL_NUTRICION_ROLES'],
  rutas: ['rutasdashboard', 'Rutas', 'rolRutas', 'TBL_RUTAS_ROLES'],
  planeacion: ['planeaciondashboard', 'Planeación', 'rolPlaneacion', 'TBL_PLANEACION_ROLES'],
  gerencia: ['gerenciadashboard', 'Gerencia'],
  admin: ['admindashboard', 'Administración'],
};

// El orden de los niveles es director, coordinador y analista. Un valor
// vacío habilita una app sin nivel propio y null omite ese acceso.
const areas = [
  ['calidad', 'Calidad', {
    compras: ['calidad', 'consultas', 'consultas'],
    interventoria: ['calidad_interventoria', 'revisor_interventoria', 'registrador_interventoria'],
    visitas: ['jefe', 'coordinador', 'profesional'],
    biblioteca: ['aprobador', 'revisor', 'consulta'],
  }],
  ['compras', 'Compras', {compras: ['compras', 'compras', 'compras']}],
  ['contabilidad', 'Contabilidad', {
    planillas: ['auditoria', 'auditoria', 'tesoreria'],
    dian: ['consulta', 'operador', 'operador'],
    compras: ['consultas', 'consultas', 'consultas'],
    biblioteca: ['consulta', 'consulta', 'consulta'],
  }],
  ['desarrollo', 'Desarrollo', {admin: ['', null, null]}],
  ['facturacion', 'Facturación', {facturacion: ['facturacion', 'facturacion', 'facturacion']}],
  ['gerencia', 'Gerencia', {gerencia: ['', '', ''], biblioteca: ['consulta', 'consulta', 'consulta']}],
  ['juridica', 'Jurídica', {
    correo: ['clasificador', 'clasificador', 'operador'],
    correspondencia: ['', '', ''], biblioteca: ['aprobador', 'revisor', 'redactor'],
  }],
  ['logistica', 'Logística', {compras: ['consultas', 'bodega', 'bodega'], rutas: ['admin', 'calidad', 'conductor'],
    planeacion: [null, null, 'bodega']}],
  ['mantenimiento', 'Mantenimiento', {mantenimiento: ['', '', ''], visitas: ['jefe', 'coordinador', 'profesional']}],
  ['operaciones', 'Operaciones', {
    interventoria: ['directivo_interventoria', 'revisor_interventoria', 'registrador_interventoria'],
    facturacion: ['visor_fac', 'visor_fac', 'establecimiento'],
    nutricion: ['consulta', 'coordinador', 'clinico'],
    visitas: ['jefe', 'coordinador', 'profesional'],
  }],
  ['planeacion', 'Planeación', {
    planeacion: ['administrador', 'planificador', 'consulta'],
    gerencia: ['', '', null], visitas: ['consulta', 'consulta', null],
  }],
  ['sistemas', 'Sistemas', {biblioteca: ['consulta', 'consulta', 'consulta']}],
  ['talento_humano', 'Talento Humano', {
    talento: ['administrador', 'gestor', 'reclutador'], biometrico: ['administrador', 'gestor', 'consulta'],
  }],
  ['gestion_proyectos', 'Gestión de Proyectos', {}],
];

const nivelesGerente = {
  compras: 'consultas', interventoria: 'gerente_interventoria', visitas: 'gerencia',
  facturacion: 'visor_fac', correo: 'visor', correspondencia: '', biblioteca: 'firmante',
  planillas: 'gerencia', dian: 'consulta', talento: 'consulta', biometrico: 'consulta',
  mantenimiento: '', nutricion: 'consulta', rutas: 'calidad', planeacion: 'consulta', gerencia: '',
};

const puesto = (titulo, area) => `${titulo} de ${area}`;
const hash = (valor) => createHash('sha256').update(valor).digest('hex');

function personas() {
  return [
    {id: gerenteId, nombre: 'Gerente General Demo', cargo: 'Gerente General', cargoClave: 'gerente_general',
      area: areas.find(([clave]) => clave === 'gerencia'), roles: nivelesGerente, jefe: '', equipo: true},
    ...areas.flatMap((area, i) => {
      const [clave, nombreArea, accesos] = area;
      const directorId = String(9900001001 + i * 3);
      const coordinadorId = String(Number(directorId) + 1);
      return ['Director', 'Coordinador', 'Analista'].map((titulo, j) => ({
        id: String(Number(directorId) + j),
        nombre: `${puesto(titulo, nombreArea)} Demo`,
        cargo: puesto(titulo, nombreArea),
        cargoClave: `${titulo.toLowerCase()}_${clave}`,
        area,
        roles: Object.fromEntries(Object.entries(accesos)
          .filter(([, valores]) => valores[j] !== null).map(([modulo, valores]) => [modulo, valores[j]])),
        jefe: [gerenteId, directorId, coordinadorId][j],
        equipo: j !== 2,
      }));
    }),
  ];
}

async function cargarMaestroInterventoria(db) {
  const ref = db.collection('TBL_INTERVENTORIA_CONFIG').doc(empresaId);
  const {reglasSubsanacion, ...configuracion} = maestroInterventoria;
  return db.runTransaction(async (tx) => {
    const actual = (await tx.get(ref)).data() ?? {};
    const tiposActivos = Array.isArray(actual.tiposActaHabilitados)
      ? actual.tiposActaHabilitados : configuracion.tiposActaHabilitados;
    const familias = new Set(tiposActivos.map((tipo) => tipo === 'SEGUIMIENTO' ? 'REGULAR' : tipo));
    const reglasExistentes = actual.reglasSubsanacion ?? {};
    const reglasNuevas = Object.fromEntries(Object.entries(reglasSubsanacion).filter(([clave, regla]) =>
      familias.has(regla.tipoActa) && !Object.hasOwn(reglasExistentes, clave) &&
      !(regla.tipoActa === 'REGULAR' && Object.hasOwn(reglasExistentes, regla.numeral))));
    const camposNuevos = Object.fromEntries(Object.entries(configuracion)
      .filter(([campo]) => !Object.hasOwn(actual, campo)));
    const cantidad = Object.keys(reglasNuevas).length;
    if (cantidad || Object.keys(camposNuevos).length) {
      tx.set(ref, {...camposNuevos, empresaId, updatedAt: FieldValue.serverTimestamp(),
        ...(cantidad ? {reglasSubsanacion: reglasNuevas} : {})}, {merge: true});
    }
    return cantidad;
  });
}

async function cargarAccesosMantenimiento(db, listado) {
  const [appId] = modulos.mantenimiento;
  const usuarios = db.collection('TBL_USUARIOS');
  const accesos = db.collection('TBL_MANTENIMIENTO_ACCESOS');
  const asignaciones = listado.filter((persona) => Object.hasOwn(persona.roles, 'mantenimiento'));
  return db.runTransaction(async (tx) => {
    const [empresa, ...docs] = await tx.getAll(db.collection('TBL_EMPRESAS').doc(empresaId),
      ...asignaciones.flatMap(({id}) => [usuarios.doc(id), accesos.doc(`${empresaId}_${id}`)]));
    if (empresa.get('esDemo') !== true) throw new Error('La empresa de pruebas no está disponible.');

    let creados = 0;
    for (const [index, persona] of asignaciones.entries()) {
      const usuario = docs[index * 2].data();
      const acceso = docs[index * 2 + 1];
      const ficha = usuario?.empresasDetalle?.[empresaId];
      if (usuario?.empresas?.length !== 1 || usuario.empresas[0] !== empresaId ||
          usuario.estado !== 'activo' || usuario.activo === false || ficha?.activo === false ||
          ficha?.estadoLaboral !== 'activo' || ficha.soloTalentoHumano === true ||
          !ficha.apps?.includes(appId)) continue;
      const gestorDemo = persona.id === '9900001025';
      if (acceso.exists) {
        if (gestorDemo && acceso.get('operador') === true && acceso.get('gestorMinimos') === undefined) {
          tx.update(acceso.ref, {gestorMinimos: true, updatedAt: FieldValue.serverTimestamp()});
        }
        continue;
      }
      tx.create(acceso.ref, {empresaId, userId: persona.id, operador: true,
        gestorMinimos: gestorDemo, updatedAt: FieldValue.serverTimestamp()});
      creados++;
    }
    return creados;
  });
}

// Planeación se habilita expresamente por empresa (planeacionOperar exige
// TBL_APPS.enabled === true). Agrega app, apps de la persona y nivel solo
// donde falten; nunca pisa un nivel ya guardado.
async function cargarPlaneacion(db, listado) {
  const [appId, nombre, campo, tabla] = modulos.planeacion;
  const appRef = db.collection('TBL_APPS').doc(`${empresaId}_${appId}`);
  const asignaciones = listado.filter((persona) => Object.hasOwn(persona.roles, 'planeacion'));
  return db.runTransaction(async (tx) => {
    const [empresa, app, ...docs] = await tx.getAll(db.collection('TBL_EMPRESAS').doc(empresaId), appRef,
      ...asignaciones.flatMap(({id}) => [db.collection('TBL_USUARIOS').doc(id),
        db.collection(tabla).doc(`${empresaId}_${id}`), db.collection('TBL_EMPLEADOS').doc(`${empresaId}_${id}`)]));
    if (empresa.get('esDemo') !== true) throw new Error('La empresa de pruebas no está disponible.');
    let cambios = 0;
    if (!app.exists || app.get('enabled') !== true) {
      tx.set(appRef, {empresaId, appId, nombre, enabled: true, updatedAt: FieldValue.serverTimestamp(),
        ...(app.exists ? {} : {createdAt: FieldValue.serverTimestamp()})}, {merge: true});
      cambios++;
    }
    for (const [i, persona] of asignaciones.entries()) {
      const [usuario, rol, empleado] = docs.slice(i * 3, i * 3 + 3);
      if (!usuario.exists || usuario.get('empresas')?.length !== 1 || usuario.get('empresas')[0] !== empresaId) continue;
      const apps = [...new Set([...(usuario.get('apps') ?? []), appId])].sort();
      const nivel = rol.exists ? rol.get('rol') : persona.roles.planeacion;
      if (!rol.exists) {
        tx.create(rol.ref, {empresaId, userId: persona.id, cedula: persona.id, nombre: persona.nombre,
          rol: nivel, createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp()});
        cambios++;
      }
      if (!(usuario.get('apps') ?? []).includes(appId)) {
        tx.update(usuario.ref, {apps, [campo]: nivel, [`empresasDetalle.${empresaId}.apps`]: apps,
          [`empresasDetalle.${empresaId}.${campo}`]: nivel});
        if (empleado.exists) tx.update(empleado.ref, {apps});
        cambios++;
      }
    }
    return cambios;
  });
}

async function cargarConfiguracionDemo(db, listado) {
  const empresaRef = db.collection('TBL_EMPRESAS').doc(empresaId);
  await db.runTransaction(async (tx) => {
    const empresa = await tx.get(empresaRef);
    if (empresa.get('esDemo') === true && !empresa.get('logoUrl')) {
      tx.update(empresaRef, {logoUrl: 'http://127.0.0.1:8787/assets/assets/logo.png'});
    }
  });
  const reglas = await cargarMaestroInterventoria(db);
  const accesos = await cargarAccesosMantenimiento(db, listado);
  const planeacion = await cargarPlaneacion(db, listado);
  const jefes = await cargarJefesHallazgos(db, listado);
  return `Reglas de Interventoría agregadas: ${reglas}. Accesos de Mantenimiento agregados: ${accesos}. Tareas con jefatura actualizada: ${jefes}. Cambios de Planeación: ${planeacion}.`;
}

async function cargarJefesHallazgos(db, listado) {
  const {esTareaDeHallazgo} = require('../../functions/lib/tareas_avisos');
  const {jefeEnEmpresa, tareaActiva} = require('../../functions/lib/jefe_inmediato_sync');
  const {empresasSeleccionables} = require('../../functions/lib/acceso');
  const fichas = db.collection('TBL_USUARIOS');
  const ids = new Set(listado.map((p) => p.id));
  const tareas = await db.collection('TBL_TAREAS').where('empresaId', '==', empresaId).get();
  let actualizadas = 0;
  for (const doc of tareas.docs) {
    if (!esTareaDeHallazgo(doc.data()) || !tareaActiva(doc.data())) continue;
    if (await db.runTransaction(async (tx) => {
      const tarea = (await tx.get(doc.ref)).data();
      if (!tarea || tarea.empresaId !== empresaId || !tareaActiva(tarea) ||
          !esTareaDeHallazgo(tarea) || tarea.jefe_inmediato_uid !== undefined) return false;
      const responsable = tarea.asignado_uid || tarea.assignedTo;
      if (!ids.has(responsable)) return false;
      const ficha = (await tx.get(fichas.doc(responsable))).data();
      const jefeId = jefeEnEmpresa(ficha ?? {}, empresaId).id;
      if (jefeId === responsable || !ids.has(jefeId)) return false;
      const jefe = (await tx.get(fichas.doc(jefeId))).data();
      if (!jefe || !empresasSeleccionables(jefe).includes(empresaId)) return false;
      tx.update(doc.ref, {jefe_inmediato_uid: jefeId});
      return true;
    })) actualizadas++;
  }
  return actualizadas;
}

async function poblar() {
  if (process.env.FIRESTORE_EMULATOR_HOST !== '127.0.0.1:8080') {
    throw new Error('Ejecuta la carga con FIRESTORE_EMULATOR_HOST=127.0.0.1:8080.');
  }
  const db = getFirestore(initializeApp({projectId: proyecto}));
  const lote = db.batch();
  const listado = personas();
  const marca = db.collection('demo_setup').doc('capital_servir');
  if ((await marca.get()).exists) {
    return `La estructura de pruebas ya está cargada. ${await cargarConfiguracionDemo(db, listado)}`;
  }
  const fecha = FieldValue.serverTimestamp();
  function crear(coleccion, id, campos) {
    lote.create(db.collection(coleccion).doc(id), {...campos, createdAt: fecha, updatedAt: fecha});
  }
  crear('TBL_EMPRESAS', empresaId, {empresaId, nombre: empresaNombre, esDemo: true});
  crear('TBL_TIPO_DOCUMENTO', 'CC', {codigo: 'CC', descripcion: 'Cédula de ciudadanía'});
  crear('TBL_CENTROS_COSTOS', centroId, {empresaId, centroId, nombre: 'Centro Principal', codigo: 'DEMO-01', enabledFacturacion: false});
  crear('TBL_CENTROS_COSTOS', sedeId, {empresaId, centroId: sedeId, nombre: 'Establecimiento Demo', codigo: 'DEMO-02', enabledFacturacion: true});
  for (const [appId, nombre] of Object.values(modulos)) {
    crear('TBL_APPS', `${empresaId}_${appId}`, {empresaId, appId, nombre, enabled: true});
  }
  for (const [clave, nombre] of areas) {
    const areaId = `${empresaId}_${clave}`;
    crear('TBL_AREAS', areaId, {empresaId, areaId, nombre, centroId});
  }
  const rolesGerencia = [true, false].map((todasLasAreas) => {
    const nombre = todasLasAreas ? 'Dirección general demo' : 'Consulta de su área demo';
    const clave = todasLasAreas ? 'direccion_general_demo' : 'consulta_de_su_area_demo';
    const id = `${empresaId}_mod_gerencia_${clave}`;
    const permissions = {todasLasAreas, todasLasEmpresas: false, pestanaDashboard: true,
      pestanaPuntos: true, pestanaInterventoria: todasLasAreas, exportar: todasLasAreas};
    crear('TBL_ROLES', id, {empresaId, type: 'module_role', moduleId: modulos.gerencia[0],
      moduleName: 'Gerencia', moduleRole: clave, roleId: id, nombre, permissions, enabled: true, revision: 1});
    return {rolGerenciaId: id, rolGerenciaNombre: nombre, rolGerenciaVersion: 1, permisosGerencia: permissions};
  });
  for (const p of listado) {
    const [areaClave, area] = p.area;
    const areaId = `${empresaId}_${areaClave}`;
    const cargoId = `${empresaId}_${p.cargoClave}`;
    const jefe = listado.find((otro) => otro.id === p.jefe);
    const centro = p.roles.facturacion === 'establecimiento' ? sedeId : centroId;
    const apps = [modulos.tareas[0], ...Object.keys(p.roles).map((key) => modulos[key][0])].sort();
    const niveles = {};
    for (const [key, rol] of Object.entries(p.roles)) {
      const [, , campo, tabla] = modulos[key];
      if (campo) niveles[campo] = rol;
      if (tabla) {
        const identidad = key === 'correo' ? {usuarioId: p.id} : {userId: p.id};
        const alcance = key === 'visitas' ? {areaId: ['jefe', 'coordinador', 'profesional'].includes(rol) ? areaId : ''} : {};
        crear(tabla, `${empresaId}_${p.id}`, {empresaId, ...identidad, ...alcance,
          cedula: p.id, nombre: p.nombre, rol});
      }
    }
    const rolGerencia = p.id === gerenteId ? rolesGerencia[0] : 'gerencia' in p.roles ? rolesGerencia[1] : {};
    const ficha = {empresaId, empresaNombre, areaId, area, areaNombre: area, cargoId,
      cargo: p.cargo, cargoNombre: p.cargo, centroId: centro,
      centroCostos: centro === sedeId ? 'Establecimiento Demo' : 'Centro Principal',
      jefeId: p.jefe, jefeNombre: jefe?.nombre ?? '', cargoJefe: jefe?.cargo ?? '',
      estadoLaboral: 'activo'};
    const identidad = {cedula: p.id, tipo_documento: 'CC', tipoDocumento: 'CC',
      nombres: p.cargo, apellidos: 'Demo', nombreCompleto: p.nombre, nombre: p.nombre};
    const membresia = {empresas: [empresaId], empresasDetalle: {[empresaId]: ficha}};
    const uid = `todo_${hash(p.id)}`;
    const salt = randomBytes(32);
    crear('TBL_CARGOS', cargoId, {empresaId, cargoId, nombre: p.cargo, area, areaId, centroId});
    crear('TBL_USUARIOS', p.id, {...identidad, ...ficha, ...niveles,
      usuario: p.id, uid, authVersion: 2, role: 'usuario', estado: 'activo', needsPasswordChange: false,
      empresas: [empresaId], appsPorEmpresa: true, apps,
      empresasDetalle: {[empresaId]: {...ficha, ...niveles, ...rolGerencia, apps,
        ...(p.roles.facturacion === 'establecimiento' ? {establecimientoFacId: sedeId} : {}),
        puedeVerEquipo: p.equipo, crearTareasTodasAreas: p.id === gerenteId}},
    });
    crear('TBL_ESTRUCTURA_ORGANIZACIONAL', p.id, {...identidad, ...ficha, ...membresia, estado: 'activo'});
    crear('TBL_EMPLEADOS', `${empresaId}_${p.id}`, {...identidad, ...ficha, estado: 'activo', apps});
    crear('TBL_CEDULAS', p.id, {cedula: p.id, empresaId, empresas: [empresaId], usuarioRef: db.collection('TBL_USUARIOS').doc(p.id)});
    crear('TBL_AUTH_CREDENTIALS', hash(`todo-auth:${p.id}`), {userDocId: p.id, authUid: uid,
      passwordAlgorithm: 'scrypt-v1', passwordSalt: salt.toString('base64'),
      passwordHash: scryptSync(claveLocal, salt, 64).toString('base64')});
  }
  lote.create(marca, {empresaId, cuentas: listado.length, createdAt: fecha});
  await lote.commit();
  return `${listado.length} cuentas creadas en ${areas.length} áreas para ${Object.keys(modulos).length} módulos. ` +
    await cargarConfiguracionDemo(db, listado);
}

poblar().then(console.log).catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
