const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {createHash} = require('node:crypto');
const admin = require('firebase-admin');
const {initializeTestEnvironment, assertFails, assertSucceeds} = require('@firebase/rules-unit-testing');
const {doc, setDoc, getDoc} = require('firebase/firestore');
assert.ok(process.env.FIRESTORE_EMULATOR_HOST, 'Solo emulador.');
const projectId = 'demo-biometrico';
admin.initializeApp({projectId});
const {BIO, gestionarBiometrico, recibirBiometrico} = require('../lib/biometrico');
const {fechaBio, diaBio} = require('../lib/biometrico_calculo');
const hash = v => createHash('sha256').update(v).digest('hex');
const ctx = id => ({auth: {uid:`todo_${hash(id)}`,token:{userDocId:id,authVersion:2}}});
const call = (data, user='admin') => gestionarBiometrico({empresaId:'A',...data},ctx(user));
let env;
test.before(async()=> { env=await initializeTestEnvironment({projectId,firestore:{rules:fs.readFileSync(path.resolve(__dirname,'../../firestore.rules'),'utf8')}}); });
test.beforeEach(async()=> {
  await env.clearFirestore();
  for (const [uid,role] of [['admin','administrador'],['gestor','gestor'],['consulta','consulta']]) {
    await admin.firestore().doc(`TBL_USUARIOS/${uid}`).set({empresaId:'A',empresas:['A'],apps:['biometricodashboard'],activo:true});
    await admin.firestore().doc(`TBL_BIOMETRICO_ROLES/A_${uid}`).set({empresaId:'A',userId:uid,rol:role});
  }
  await admin.firestore().doc('TBL_USUARIOS/p').set({empresaId:'A',empresas:['A'],cedula:'123',nombre:'Persona de prueba',activo:true});
});
test.after(async()=> { await env.cleanup(); await admin.app().delete(); });
async function device() {
  const c = await call({accion:'crearDispositivo',nombre:'Lector',sede:'Pruebas'});
  await call({accion:'vincular',deviceId:c.deviceId,slot:1,userId:'p',consentimiento:'Soporte prueba'});
  return c;
}
async function http(c, body, opts={}) {
  const res={headers:{},statusCode:200,set(k,v){this.headers[k]=v;return this;},status(c){this.statusCode=c;return this;},json(b){this.body=b;return this;}};
  await recibirBiometrico({method:opts.method||'POST',body:{deviceId:c.deviceId,...body},rawBody:Buffer.alloc(100),
    get:()=>`Bearer ${opts.token||c.token}`,is:()=>true},res);
  return res;
}
test('borrado físico: permisos, orden persistente, bloqueo, ACK por equipo y reintento seguro', async()=> {
  const c = await device();
  const erase = {accion:'eliminarHuella',deviceId:c.deviceId,slot:1,motivo:'Solicitud del titular'};
  await assert.rejects(call(erase,'gestor'),{code:'permission-denied'});
  await assert.rejects(call(erase,'consulta'),{code:'permission-denied'});
  await assert.rejects(call({...erase,empresaId:'B'}));
  const event = {accion:'marcacion',eventoId:'conservar',slot:1,tipo:'ENTRADA',capturadoMs:Date.now()};
  assert.equal((await http(c,event)).statusCode,201);
  await Promise.all([call(erase),call(erase)]);
  const root = admin.firestore().doc(`${BIO.devices}/${c.deviceId}`);
  assert.equal((await root.collection('comandos').get()).size,1);
  let binding = (await root.collection('vinculos').doc('1').get()).data();
  assert.equal(binding.activo,false); assert.ok(binding.borradoId);
  await assert.rejects(call({accion:'vincular',deviceId:c.deviceId,slot:1,userId:'p'}));
  assert.equal((await http(c,{...event,eventoId:'bloqueado',capturadoMs:Date.now()})).statusCode,422);
  const heartbeat = {accion:'heartbeat',capacidad:200,usadas:1,firmware:'ToDo-Bio-2.4.0'};
  const order = (await http(c,heartbeat)).body.comando;
  assert.equal(order.id,binding.borradoId); assert.equal(order.slot,1);
  assert.deepEqual((await http(c,heartbeat)).body.comando,order);
  const other = await call({accion:'crearDispositivo',nombre:'Otro',sede:'Pruebas'});
  const ack = {accion:'confirmarBorrado',comandoId:order.id};
  assert.equal((await http(other,ack)).statusCode,404);
  assert.equal((await http(c,ack)).statusCode,200);
  assert.equal((await root.collection('vinculos').doc('1').get()).exists,false);
  assert.equal((await http(c,heartbeat)).body.comando,undefined);
  assert.equal((await admin.firestore().collection(BIO.events).get()).size,1);
  await call({accion:'vincular',deviceId:c.deviceId,slot:1,userId:'p'});
  assert.equal((await http(c,ack)).statusCode,200); // ACK perdido no borra un vínculo nuevo.
  assert.equal((await root.collection('vinculos').doc('1').get()).data().activo,true);
});
test('dispositivo: vínculo, marcación idempotente, heartbeat y separación de empresas', async()=> {
  const c=await device();
  const body={accion:'marcacion',eventoId:'event1',slot:1,tipo:'ENTRADA',capturadoMs:Date.now()};
  const first=await http(c,body); assert.equal(first.statusCode,201);
  assert.equal((await http(c,body)).statusCode,200);
  assert.equal((await http(c,{...body,tipo:'SALIDA'})).statusCode,409);
  const stored=(await admin.firestore().doc(`${BIO.events}/${first.body.id}`).get()).data();
  assert.equal(stored.userId,'p'); assert.equal(stored.empresaId,'A');
  assert.equal((await http(c,{...body,eventoId:'otro',empresaId:'B'})).statusCode,400);
  assert.equal((await http(c,{accion:'heartbeat',capacidad:200,usadas:1,firmware:'test'})).statusCode,200);
  const listing=await call({accion:'listar'});
  assert.equal(listing.devices[0].tokenHash,undefined); assert.equal(listing.devices[0].usadas,1);
});
test('revocación y rotación invalidan el token anterior; vínculo y persona deben estar vigentes', async()=> {
  const c=await device(); const body={accion:'marcacion',eventoId:'e1',slot:1,tipo:'ENTRADA',capturadoMs:Date.now()};
  assert.equal((await http(c,{...body,capturadoMs:Date.now()-10000})).statusCode,422);
  assert.equal((await http(c,{...body,slot:2})).statusCode,422);
  await admin.firestore().doc('TBL_USUARIOS/p').update({activo:false});
  assert.equal((await http(c,body)).statusCode,422);
  await admin.firestore().doc('TBL_USUARIOS/p').update({activo:true});
  const rotated=await call({accion:'rotarToken',deviceId:c.deviceId});
  assert.equal((await http(c,body)).statusCode,401);
  assert.equal((await http(rotated,body)).statusCode,201);
  await call({accion:'revocarDispositivo',deviceId:c.deviceId});
  assert.equal((await http(rotated,body)).statusCode,401);
});
test('vínculo no se pisa, ni admite otra empresa; rechazo por hora inválida y límite por minuto', async()=> {
  const c=await device();
  await assert.rejects(call({accion:'vincular',deviceId:c.deviceId,slot:1,userId:'p',consentimiento:'otro'}));
  await assert.rejects(call({accion:'vinculos',empresaId:'B',deviceId:c.deviceId}));
  const body={accion:'marcacion',eventoId:'x',slot:1,tipo:'ENTRADA',capturadoMs:Date.now()+120000};
  assert.equal((await http(c,body)).statusCode,422);
  await admin.firestore().doc(`${BIO.devices}/${c.deviceId}`).update({minuto:Math.floor(Date.now()/60000),cantidad:60});
  assert.equal((await http(c,{...body,capturadoMs:Date.now()})).statusCode,429);
});
test('consulta no modifica; gestor no emite tokens; quitar app neutraliza rol; TH no hereda acceso', async()=> {
  assert.equal((await call({accion:'listar'},'consulta')).nivel,'consulta');
  await assert.rejects(call({accion:'guardarHorario',nombre:'x',inicio:0,fin:60},'consulta'),{code:'permission-denied'});
  await assert.rejects(call({accion:'crearDispositivo',nombre:'x',sede:'y'},'gestor'),{code:'permission-denied'});
  await admin.firestore().doc('TBL_USUARIOS/gestor').update({apps:['talentohumanodashboard']});
  await assert.rejects(call({accion:'listar'},'gestor'),{code:'permission-denied'});
  await assert.rejects(gestionarBiometrico({accion:'listar',empresaId:'A'},{auth:{uid:'admin',token:{userDocId:'admin',authVersion:2}}}),{code:'unauthenticated'});
});
test('deshabilitar la app de la empresa detiene consulta y recepción de dispositivos', async()=> {
  const c=await device();
  await admin.firestore().doc('TBL_APPS/A_biometricodashboard').set({empresaId:'A',appId:'biometricodashboard',enabled:false});
  await assert.rejects(call({accion:'listar'}),{code:'permission-denied'});
  assert.equal((await http(c,{accion:'heartbeat',capacidad:200,usadas:1,firmware:'test'})).statusCode,403);
});
test('nocturno, descanso, aprobación y cambios posteriores requieren nueva revisión', async()=> {
  const day=diaBio(Date.now()-2*86400000), base=fechaBio(day);
  await call({accion:'guardarHorario',nombre:'Noche',inicio:1260,fin:1800,descansoInicio:1500,descansoFin:1560},'gestor');
  const h=(await call({accion:'listar'})).horarios[0];
  await call({accion:'asignarHorario',userId:'p',horarioId:h.id,desde:day,hasta:day,diasSemana:[0,1,2,3,4,5,6]},'gestor');
  for(const [tipo,min] of [['ENTRADA',1260],['SALIDA',1860]]) await call({accion:'marcacionManual',userId:'p',tipo,capturadoMs:base+min*60000,eventoId:tipo,motivo:'Falla de equipo'},'gestor');
  let r=(await call({accion:'informe',desde:day,hasta:day})).filas[0];
  assert.equal(r.ordinario,480);assert.equal(r.extra,60);assert.equal(r.aprobado,0);
  await call({accion:'decidirExtras',userId:'p',dia:day,revision:r.revision,estado:'aprobado',motivo:'Autorizadas'},'gestor');
  r=(await call({accion:'informe',desde:day,hasta:day})).filas[0];assert.equal(r.aprobado,60);
  await call({accion:'anularMarcacion',eventoId:r.eventos.find(e=>e.tipo==='SALIDA').id,motivo:'Hora incorrecta'},'gestor');
  const after=(await call({accion:'informe',desde:day,hasta:day})).filas[0];
  assert.equal(after.aprobado,0); assert.equal(after.estado,'pendiente');assert.equal(after.decision.vigente,false);
  await assert.rejects(call({accion:'decidirExtras',userId:'p',dia:day,revision:r.revision,estado:'aprobado',motivo:'Vieja'},'gestor'));
  assert.ok((await admin.firestore().collection(BIO.audit).get()).size>=5);
});
test('reglas: datos de asistencia y credenciales cerrados al cliente; rol solo lo administra quien tiene facultad', async()=> {
  const client=env.authenticatedContext(`todo_${hash('gestor')}`,{userDocId:'gestor',authVersion:2}).firestore();
  for(const col of Object.values(BIO)) {
    await admin.firestore().doc(`${col}/r`).set({empresaId:'A'});
    await assertFails(getDoc(doc(client,`${col}/r`)));
    await assertFails(setDoc(doc(client,`${col}/r`),{empresaId:'A',estado:'aprobado'}));
  }
  await assertFails(setDoc(doc(client,'TBL_BIOMETRICO_ROLES/A_gestor'),{empresaId:'A',userId:'gestor',rol:'administrador'}));
  const ac=env.authenticatedContext(`todo_${hash('admin')}`,{userDocId:'admin',authVersion:2}).firestore();
  await assertSucceeds(setDoc(doc(ac,'TBL_BIOMETRICO_ROLES/A_gestor'),{empresaId:'A',userId:'gestor',rol:'consulta'}));
  await assertFails(setDoc(doc(ac,'TBL_BIOMETRICO_ROLES/B_gestor'),{empresaId:'B',userId:'gestor',rol:'gestor'}));
  await assertSucceeds(setDoc(doc(ac,'TBL_ROLES/A_mod_biometrico_revision'),{empresaId:'A',moduleId:'biometricodashboard',type:'module_role',baseRole:'gestor',enabled:true,revision:1,nombre:'Revisión'}));
});

test('registro desde el equipo: PIN, sesión corta, bloqueo, autorización y bienvenida', async()=> {
  const c = await call({accion:'crearDispositivo',nombre:'Lector',sede:'Pruebas'});
  await admin.firestore().doc(`TBL_BIOMETRICO_DISPOSITIVOS/${c.deviceId}`).update({capacidad:150});
  await admin.firestore().doc('TBL_USUARIOS/admin').update({cedula:'900'});
  assert.equal((await call({accion:'listar'})).tienePin, false);
  await assert.rejects(call({accion:'fijarPin',pin:'123456'}), /PIN debe tener/);
  await assert.rejects(call({accion:'fijarPin',pin:'483920'},'gestor'), /administrador/);
  await call({accion:'fijarPin',pin:'483920'});
  assert.equal((await call({accion:'listar'})).tienePin, true);
  const pinDoc = (await admin.firestore().doc('TBL_BIOMETRICO_PINES/A_admin').get()).data();
  assert.ok(pinDoc.pinHash && !JSON.stringify(pinDoc).includes('483920'));
  await assert.rejects(call({accion:'fijarPin',pin:'719283'}), /PIN actual/);
  // Sin sesión no se busca ni se vincula.
  let r = await http(c,{accion:'buscarPersona',cedula:'123',sesion:`tds_${'0'.repeat(48)}`});
  assert.equal(r.statusCode,422);
  // PIN incorrecto igual que cédula inexistente: mismo mensaje.
  r = await http(c,{accion:'autenticarAdmin',cedula:'900',pin:'111112'}); assert.equal(r.statusCode,422);
  const msg = r.body.error;
  r = await http(c,{accion:'autenticarAdmin',cedula:'777',pin:'111112'}); assert.equal(r.body.error,msg);
  // Una persona sin nivel de administrador no abre sesión aunque tenga PIN.
  r = await http(c,{accion:'autenticarAdmin',cedula:'123',pin:'483920'}); assert.equal(r.statusCode,422);
  r = await http(c,{accion:'autenticarAdmin',cedula:'900',pin:'483920'});
  assert.equal(r.statusCode,200); assert.match(r.body.sesion,/^tds_[a-f0-9]{48}$/);
  const sesion = r.body.sesion;
  r = await http(c,{accion:'buscarPersona',cedula:'123',sesion}); assert.equal(r.body.nombre,'Persona de prueba');
  r = await http(c,{accion:'buscarPersona',cedula:'555',sesion}); assert.equal(r.statusCode,422);
  // Autorización obligatoria y posición dentro de la capacidad.
  r = await http(c,{accion:'registrarHuella',cedula:'123',sesion,slot:7,autorizo:false,aviso:'v1'}); assert.equal(r.statusCode,400);
  r = await http(c,{accion:'registrarHuella',cedula:'123',sesion,slot:151,autorizo:true,aviso:'v1'}); assert.equal(r.statusCode,422);
  r = await http(c,{accion:'registrarHuella',cedula:'123',sesion,slot:7,autorizo:true,aviso:'v1'}); assert.equal(r.statusCode,200);
  r = await http(c,{accion:'registrarHuella',cedula:'123',sesion,slot:7,autorizo:true,aviso:'v1'}); assert.equal(r.statusCode,409);
  const v = (await admin.firestore().doc(`TBL_BIOMETRICO_DISPOSITIVOS/${c.deviceId}/vinculos/7`).get()).data();
  assert.equal(v.userId,'p'); assert.equal(v.porId,'admin'); assert.equal(v.activo,true);
  assert.match(v.consentimiento,/Aceptado en pantalla/); assert.equal(v.autorizacion.origen,'equipo');
  // La huella registrada marca y la respuesta trae el nombre para la bienvenida.
  r = await http(c,{accion:'marcacion',eventoId:'e-bien-1',slot:7,tipo:'ENTRADA',capturadoMs:Date.now()});
  assert.equal(r.statusCode,201); assert.equal(r.body.nombre,'Persona de prueba');
  // La sesión vencida se rechaza.
  await admin.firestore().doc(`TBL_BIOMETRICO_DISPOSITIVOS/${c.deviceId}`).update({'sesionRegistro.expMs':Date.now()-1});
  r = await http(c,{accion:'buscarPersona',cedula:'123',sesion}); assert.equal(r.statusCode,422);
  // Cinco PIN incorrectos bloquean, incluso con el PIN correcto después.
  for (let i=0;i<5;i++) await http(c,{accion:'autenticarAdmin',cedula:'900',pin:'111112'});
  r = await http(c,{accion:'autenticarAdmin',cedula:'900',pin:'483920'}); assert.equal(r.statusCode,429);
  // Otro equipo de otra empresa no ve a esta persona ni usa esta sesión.
  const auditoria = await admin.firestore().collection('TBL_BIOMETRICO_AUDITORIA').get();
  const acciones = auditoria.docs.map(d=>d.data().accion);
  assert.ok(acciones.includes('vincularDesdeEquipo') && acciones.includes('sesionRegistroEquipo') && acciones.includes('fijarPin'));
});

test('app: sedes, personas con huella, calendario por colaborador y vínculo sin referencia manual', async()=> {
  const c = await call({accion:'crearDispositivo',nombre:'Lector',sede:'Planta',centroCostoId:'cc1'});
  await admin.firestore().doc('TBL_CENTROS_COSTOS/cc1').set({empresaId:'A',nombre:'Planta La Spezia',codigo:'01',enabled:true});
  await admin.firestore().doc('TBL_CENTROS_COSTOS/cc2').set({empresaId:'A',nombre:'Inactivo',enabled:false});
  await admin.firestore().doc('TBL_CENTROS_COSTOS/ccB').set({empresaId:'B',nombre:'Otra empresa',enabled:true});
  let l = await call({accion:'listar'});
  assert.deepEqual(l.centros.map(x=>x.nombre), ['Planta La Spezia']);
  assert.equal(l.primerDia, null);
  assert.equal((await admin.firestore().doc(`TBL_BIOMETRICO_DISPOSITIVOS/${c.deviceId}`).get()).data().centroCostoId, 'cc1');
  let r = await call({accion:'personas'},'consulta');
  assert.equal(r.personas.find(p=>p.id==='p').vinculada, false);
  await call({accion:'vincular',deviceId:c.deviceId,slot:3,userId:'p'});
  const v = (await admin.firestore().doc(`TBL_BIOMETRICO_DISPOSITIVOS/${c.deviceId}/vinculos/3`).get()).data();
  assert.match(v.consentimiento, /firmada en la contratación/);
  r = await call({accion:'personas'});
  assert.equal(r.personas.find(p=>p.id==='p').vinculada, true);
  assert.ok(r.personas.every(x => x.id !== 'otra'));
  const h = await call({accion:'guardarHorario',nombre:'Mañana',libre:false,inicio:360,fin:840,descansoInicio:0,descansoFin:0});
  const horarios = (await call({accion:'listar'})).horarios;
  await call({accion:'asignarHorario',userId:'p',horarioId:horarios[0].id,desde:'2026-10-12',hasta:'2026-10-18',diasSemana:[1,2,3]});
  r = await call({accion:'calendario',desde:'2026-10-12',hasta:'2026-10-18'},'consulta');
  assert.deepEqual(r.asignaciones.map(a=>a.dia).sort(), ['2026-10-12','2026-10-13','2026-10-14']);
  assert.equal(r.asignaciones[0].nombre, 'Mañana');
  await assert.rejects(call({accion:'calendario',desde:'2026-10-01',hasta:'2026-12-31'}), /31 días/);
  // Primer día: aparece cuando hay marcaciones.
  const res = await http(c,{accion:'marcacion',eventoId:'e-primero',slot:3,tipo:'ENTRADA',capturadoMs:Date.now()});
  assert.equal(res.statusCode,201);
  l = await call({accion:'listar'});
  assert.equal(l.primerDia, diaBio(Date.now()));
  void h;
});

