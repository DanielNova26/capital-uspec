# Bitácora de Mejoras — Capital USPEC

Registro de cambios ejecutados por sesión de mejora. Objetivo: app nivel
"SAP" — consistencia visual Web/Móvil, módulos conectados, usuarios siempre
con nombre y foto (nunca cédula cruda ni letra suelta).

---

## 2026-10-06 — Visitas: el calendario en el celular y planes K2 para Gerencia (Claude)

Pedido del usuario (nota de voz): "en el celular, dándole clic al calendario,
no deja [agregar] visitas a ese día" y "lo que se agregó de Interventoría del
K2 […] también lo puede [hacer] Gerencia".

- **Causa del calendario.** `TableCalendar` trae por defecto
  `AvailableGestures.all`: aunque no cambia de formato (no hay
  `onFormatChanged`), registra un reconocedor de arrastre vertical que le gana
  al scroll de la pantalla. Con el dedo, todo arrastre que empezaba sobre el
  calendario se perdía: en el Cronograma no se llegaba a las visitas del día
  tocado y en "Agregar visitas" (pantalla completa en el teléfono) no se bajaba
  a ponerle el establecimiento al día marcado. Con mouse no pasa (la rueda no
  es un arrastre), por eso en Web sí funcionaba.
- **Arreglo.** `availableGestures: AvailableGestures.horizontalSwipe` en el
  Cronograma, en el diálogo "Agregar visitas" y en el calendario del inicio
  (mismo problema en "Mi agenda"). El deslizamiento lateral sigue cambiando
  de mes. Además, en el Cronograma la cabecera del día tocado trae
  **"Agregar"** (programa en esa fecha; solo jefe/Gerencia y desde hoy,
  `visitaDiaProgramable`) y en el teléfono se baja lo justo para que esa
  cabecera se vea al tocar el día.
- **Planes de mejora K2 para Gerencia.** El rol Gerente de Interventoría
  (`gerente_interventoria`) opera los planes con el mismo alcance que Calidad:
  pestaña "Planes de mejora", crear, vincular, revisar, presentar, reabrir y
  las acciones de Calidad dentro de la tarea. Lista única
  `kInterventoriaRolesPlanes` (app) / `ROLES_GESTION_PLANES` (callable
  `interventoriaPlanes`); una prueba Dart falla si no coinciden. Sigue
  exigiendo rol canónico `{empresa}_{usuario}`, app activa y empresa
  habilitada: Directivo, ids históricos y otra empresa sin rol propio quedan
  fuera. **Decisión:** los avisos de "entrega por revisar" y los recordatorios
  siguen yendo solo a Calidad (`gestores`), para no llenar de avisos a
  Gerencia; si la empresa no tiene Calidad, nadie recibe esos avisos. Si el
  usuario quería solo consulta para Gerencia, hay que separar lectura de
  gestión en el callable.
- **Pruebas:** `flutter test test/visitas test/interventoria/interventoria_planes_test.dart`
  (182) con la prueba nueva de arrastre en el teléfono (sin el arreglo queda
  en 0 px; con él baja) y `visitaDiaProgramable`. Functions: `npm test`
  179/179; emulador Firestore + Storage `interventoria_planes.rules.js` 12/12
  (nueva: Gerencia opera, no recibe los avisos de Calidad, y se revoca por
  rol, id histórico, empresa y app).
- **Pendiente:** desplegar Functions (`interventoriaPlanes`; sin eso la
  pestaña aparece para Gerencia pero el servidor responde "Solo Calidad…") y
  publicar Web/Android/iOS. Sin verificación en dispositivo: el arrastre del
  Cronograma y del inicio solo se comprobó con el diálogo en prueba de widget
  a 390 px; probar en Android e iPhone reales.

## 2026-10-06 — Reglas: por qué no se publicaban desde el 2 oct y arreglo (Claude)

- **Síntoma.** Desde el 2 oct `firebase deploy --only firestore:rules` daba
  503 y la consola "Se produjo un error desconocido"; producción siguió con
  las reglas del 1 oct. El emulador las compilaba sin problema.
- **Qué se sabe**, por cuatro rondas de `--dry-run` desde el PC del usuario:
  - Con el bloque de Tareas del 2 oct, ninguna versión compilaba: la regla
    de actualizar tareas sola (con la de lectura) fallaba, y crear +
    eventos + borrar juntas también; cada una de estas tres por separado
    compilaba.
  - **No es el tamaño del archivo.** Las reglas del 1 oct con 19 mil
    caracteres de relleno (84,5 mil en total, más que las que fallaban)
    compilaron. Tampoco es el número de funciones, de textos, de `.get()`
    ni las construcciones nuevas (`toSet`, `difference`, `concat`,
    comodines): cada una, agregada sola a la versión del 1 oct, compiló.
    Las dos primeras explicaciones de esta entrada (funciones copiadas al
    compilar; tamaño total) quedan descartadas.
  - El 503 también aparece suelto: la versión nueva falló una vez y en la
    ronda siguiente compiló al primer intento. Ante un 503, reintentar
    antes de concluir nada.
  - La causa exacta del lado de Google sigue sin identificarse. La versión
    reorganizada **compila** (6 oct 2026).
- **La versión que compila, sin cambiar permisos:**
  - Una sola `tieneAppsEn(empresaId, apps, tareas)` en lugar de siete
    copias (Admin, Correo, Tokens DIAN, Talento, Nutrición, Compras y la de
    Tareas). Con `tareas` en true rige "No opera en To-Do", solo donde ya
    regía.
  - Nutrición (15 colecciones), Facturación con evaluaciones diagnósticas
    (6) y las tablas de roles de Tokens DIAN, Talento Humano y Nutrición
    (3): un `match /{collection}/{docId}` por grupo, con la misma regla de
    antes. `nivelesDeModulo` comparte las listas de niveles con
    `rolDeModuloValido`.
  - Las trece colecciones cerradas (`if false`) ya no tienen `match`: las
    excluye la regla general y ninguna otra las abre.
  - `empresaSeConserva()` en las 22 actualizaciones, `gestionaPagos` en
    Pagos, y fuera dos funciones sin uso (`hasVisitasRole`,
    `administraVisitas`).
  - Tareas: las ramas del flujo reciben `propios` (los cambios sin
    `updatedAt` ni `lastEvent*`, que todas permiten) y
    `camposSolicitudReasignacion()`.
- **Costo por petición (tope de 1000), medido en el emulador.** Cada
  elemento de una lista literal cuenta como una expresión (`c in [50
  nombres]` ≈ 53; `matches` con un literal ≈ 3). Y Firestore evalúa las
  reglas que coinciden **en el orden del archivo**, sumando lo que cuestan
  las que dan falso hasta que una permite. Por eso los grupos y la regla
  general usan expresiones regulares (`matches` compara el nombre
  completo), y los `match` con comodín van al final, justo antes de la
  regla general: en medio del archivo le cobraban su filtro a Tareas,
  Rutas y Facturación. Expresiones de margen de los flujos de Tareas
  (antes → ahora): leer como líder 495 → 510, crear desde Interventoría
  376 → 390, reasignación directa 184 → 191, aprobar la subsanación
  347 → 349, pedir reasignación 248 → 257, aprobarla 400 → 410, solicitar
  finalización 482 → 492. Ninguno pierde.
- **Para Codex:** antes de publicar reglas, siempre
  `firebase deploy --only firestore:rules --dry-run`; si da 503,
  reintentar dos o tres veces. Un `match` con comodín nuevo va al final del
  archivo, no en medio. Para colecciones con la misma regla, un comodín con
  `matches` en lugar de copias.
- **Pruebas:** todas las suites `functions/test/*.rules.js` en emulador:
  171 aprobadas (incluida la de margen de Tareas), 3 omitidas de antes y 1
  falla **ajena y previa**: `visitas_gerencia.rules.js` "Gerencia crea
  formatos y programa" fija la visita el 5 oct 2026, que ya pasó; falla
  igual con las reglas de `main`. Hay que fechar esa prueba en relación con
  hoy.
- **Pendiente:** publicar desde el PC del usuario (`firebase deploy --only
  firestore:rules`) y subir `main`. Los archivos de diagnóstico
  (`tool/reglas_diagnostico`) se quitaron de la rama.

## 2026-10-05 — Planes de mejora: Desarrollo, número de acta y PDF (Codex)

- La Web publicada contenía los planes, pero pestaña y callable solo admitían
  Calidad. Desarrollo ahora accede sin cambiar su nivel, conservando cuenta
  activa y empresa vinculada/habilitada; no se amplían otros perfiles.
- «Número de acta» reemplaza el rótulo de ID K2 en registro, selección, detalle
  y PDF. Se conserva `idVisitaK2` internamente para no migrar registros.
  Adjuntar PDF vuelve a estar visible en actas nuevas y correcciones, opcional
  y sin exigir evidencia inicial de los hallazgos.
- Versión 2.6.16+30: TypeScript y Web compilados, 20 pruebas Flutter, 11 de
  integración Firestore/Storage y seis de política correctas. Desarrollo,
  revocación, aislamiento por empresa y tamaños de pantalla cubiertos.
- Publicados Web 2.6.16 y callable. Luego se integró la rama de Tareas
  solicitada por el usuario para publicar la versión consolidada 2.6.17+31.
  Pendiente comprobación autenticada del usuario y Android/iPhone reales.

### Consolidación con la rama de Claude

- Integrado `origin/claude/kind-wright-jnusvi` (commit `8478f59`) en main,
  junto con la corrección de Interventoría `3616fe9`. Único conflicto en
  esta bitácora: se conservaron ambas entradas completas. Las rutas a los
  planes desde Tareas y Notificaciones permanecen integradas.
- 1.548 pruebas Flutter, 178 pruebas Node y 173 pruebas de reglas aprobadas
  (dos omitidas existentes, ningún fallo); compilación TypeScript y Web
  2.6.17+31 correctas. Publicación consolidada en curso.
  La compilación Web conserva advertencias Wasm de dependencias;
  se publica JavaScript. No se genera una nueva entrega a tiendas móviles.

## 2026-10-05 — Tareas: documento "Tareas - octubre 04 de 2026" (Claude)

Pedido del usuario: "módulo de tareas, lo que hay que mejorar" (documento con
capturas de Notificaciones, Crear tarea, Mis tareas, Por aprobar, Reportar
avance/novedad, Historial, Interventoría y Mi equipo).

- **Lógica compartida** (`lib/core/task_flujo.dart`, pura y probada):
  - *Aprobador efectivo* (`taskAprobadorId`): `aprobador_uid`, luego
    `jefe_uid` y luego quien asignó, **nunca el propio responsable**. La
    tarea 2090 (reasignada a quien era su aprobador y terminada por ella) no
    le salía a nadie: ahora decide quien la asignó. Espejo en servidor:
    `functions/src/tareas_avisos.ts` (`aprobadorDeTarea`).
  - *Destinatarios de seguimiento*: quien asignó (emisor) + aprobador, sin
    quien hace la acción ni el creador automático de Interventoría.
  - *Destino de un aviso* (`decidirDestinoAvisoTarea`) según la relación de
    la persona con la tarea, no según el tipo: responsable → Mis tareas;
    aprobador con decisión pendiente → Por aprobar; quien asignó → Tareas que
    asigné; quien la entregó → Historial › Antes asignadas; cerrada →
    Historial con el proceso. `TaskRouteGuard.resolveNotificationRoute` lo
    usa, y los tres despachadores repetidos (bandeja, Home, toque de push)
    pasan por `lib/home/task_aviso_navigation.dart`.
  - *Aprobador al aprobar una reasignación* (`taskAprobadorTrasReasignar`):
    pasa al jefe inmediato del nuevo responsable (como al crear); sin jefe,
    a quien asignó.
- **Avisos.** "Tarea No. N" en rojo en la bandeja (`TaskNumeroAvisoChip`;
  los avisos nuevos traen `taskNumero`, los viejos lo buscan una vez por
  tarea) y al principio del texto del push. `onTaskCreated` espera unos
  segundos el número que asigna `tareasAsignarNumero` (corren a la vez).
  Avance, novedad y solicitud de reasignación avisan a quien asignó y al
  aprobador (antes solo a `jefe_uid`, vacío en Visitas: al analista no le
  llegaba). La solicitud de finalización (servidor) va al aprobador y a quien
  asignó. Aprobada/rechazada la reasignación, el aviso lleva número.
- **Crear tarea.** Botón habilitado solo con título, descripción, fecha
  límite, área, cargo y persona (dice qué falta). Área y Cargo en la misma
  línea desde 520 px de ancho del formulario; en teléfono, uno debajo del
  otro. Al crear, diálogo con número (en cuanto llega), título, responsable,
  área, cargo, prioridad, fecha, evidencias y quién aprueba.
- **Talento Humano: "No opera en To-Do"** (TH › Accesos del personal, en el
  editor de cada persona). `empresasDetalle.{empresa}.soloTalentoHumano`.
  Al marcarla se le retiran los módulos que administra TH; además
  `userHasApp` y el Home la neutralizan (no ve módulos ni Tareas aunque le
  quede alguno), `recibeAsignacionesEnEmpresa` la saca de todo desplegable
  de asignación (Crear tarea, Interventoría) y también de la reasignación,
  del personal de Visitas y de responsables de Correspondencia. Sigue
  vinculada (no es retiro) y conserva perfil, hoja de vida, avisos y
  calendario. Reglas: no se le crea ni reasigna una tarea y
  `tieneAppDeListaEn` la deja sin app en esa empresa. Quitar la marca no
  devuelve módulos.
- **Mis tareas.** "Completar tarea" dice siempre "Requiere evidencias" o
  "No requiere evidencias" (y hay un chip en el encabezado). Con una
  reasignación en espera: completar, novedad y avance quedan inhabilitados
  (también en el servicio, `CompleteTaskScreen` y reglas) y el panel y la
  tarjeta muestran a quién pasa y quién la aprueba. Avance y novedad se abren
  encima del panel, se cierran al enviar y se vuelve al panel; si la novedad
  terminó en finalización, el panel se cierra. Historial de actividad en
  ventana flotante centrada (hoja en el teléfono) con "volver"
  (`showTaskActivityPanel`), también en Mi equipo e Interventoría. En
  "Mostrando únicamente la tarea seleccionada" los filtros ya funcionan
  (salen de ese modo) y si la tarea ya no es suya lo dice. En tareas de
  Interventoría, "Ver hallazgo" abre el panel de ESE hallazgo (consulta), no
  el módulo; sin hallazgo vinculado no aparece.
- **Por aprobar / Tareas que asigné.** "Por aprobar" lista solo lo que
  espera una decisión de la persona (finalización o reasignación), con
  chips Todas/Finalización/Reasignación; la consulta suma `creador_id` para
  las tareas cuyo aprobador guardado es el propio responsable. Aprobar,
  devolver y resolver reasignaciones solo lo ve el aprobador efectivo; quien
  asignó sin ser aprobador ve "en espera" y quién la aprueba (**cambio**:
  antes el creador también podía aprobar desde Tareas que asigné; las reglas
  lo siguen permitiendo). El panel muestra descripción, fecha, prioridad,
  evidencias y quién asignó. "Devolver" se habilita con fecha y motivo.
  Retroalimentación: en "Ver novedades", quien asignó o aprueba responde cada
  novedad del responsable (`type: respuesta_novedad`), le llega aviso y
  queda en el historial con la etiqueta "Retroalimentación".
- **Tareas de mi equipo.** No se actualizaba: desde el 3 oct se leía una
  sola vez (para no repetir la consulta al escribir). Ahora escucha en vivo
  (consultas unidas). Para Dirección, el área se consulta con todas sus
  variantes de id y por las personas del área (antes `areaId ==`, contra la
  regla de Áreas). "Actualizar" vuelve a leer también el equipo.
- **Validación.** `flutter test --no-pub` 1547/1547; nuevas:
  `test/core/task_flujo_test.dart` (18), `test/utils/solo_talento_humano_test.dart`
  (4), `test/widgets/task_avisos_widgets_test.dart` (4). Functions
  `npm test` 178/178 (4 nuevas en `tareas_avisos.test.js`), ESLint sin
  errores. Reglas en emulador: `tareas_rules.rules.js` 18/18 (5 nuevas:
  "No opera en To-Do", reasignación en espera, aprobador tras reasignar,
  retroalimentación, consulta de Por aprobar) y todas las suites `functions/test/*.rules.js` juntas: 171 aprobadas, 0
  fallas, 3 omitidas que ya estaban marcadas. `flutter analyze` sin errores (solo avisos previos).
- **Pendiente / decisiones:**
  - Despliegue: Functions `onTaskCreated`, `onTaskUpdated`,
    `onNotificationCreated` (número y destinatarios) y Web. Las reglas
    siguen el plan de Tareas (esperan 2.6.15 en tiendas); sin ellas la marca
    de TH y el bloqueo con reasignación en espera rigen solo en app/servicio.
  - `TBL_USUARIOS` no tiene regla propia (cae en la general): la marca
    `soloTalentoHumano` no está protegida contra escritura por servidor.
    Hace falta una regla de usuarios (o un callable de TH) — tarea aparte.
  - Mis tareas, punto "cuando se reasigna, debe mostrarse al responsable (no
    a quien la reasignó)": se interpretó junto con "tareas con reasignación
    en espera: mostrar a quién y quién aprueba". Mientras espera aprobación
    la tarea sigue en Mis tareas de quien la pidió, solo de consulta y con
    esos datos; al aprobarse pasa al nuevo responsable y sale de su lista.
    Si el usuario quiere que salga apenas se pide, es otro cambio.
  - Tareas ya reasignadas antes de hoy conservan el aprobador anterior; el
    aprobador efectivo corrige el caso del propio responsable, no otros.
    Si se quiere, preparar una incorporación revisable por empresa.
  - Admin › Apps/Usuarios todavía no muestra la marca "No opera en To-Do"
    (solo TH): si Admin le concede un módulo, sigue neutralizado.
  - "N.º tarea" sale "—" en Mi equipo para tareas sin número: falta correr
    Admin › Migraciones › "Número interno de tareas" en cada empresa.
  - Sin verificación visual en Web (390/768/1024/1366, texto ampliado),
    Android ni iOS: solo pruebas de widgets.
- Git: entregado en la rama `claude/kind-wright-jnusvi` (sesión en la nube,
  sin acceso a `main`); integrar en `main`.

## 2026-10-05 — Gestión documental: plantilla Word del formato institucional (Claude)

Pedido del usuario: "así como me permite generar el Excel cuando quiero
cargar un formato, así mismo me permita un Word, con las mismas
especificaciones, el mismo encabezado y un pie de página bonito".

- `lib/gestion_documental/gd_formato_plantilla_word.dart`: `.docx` escrito a
  mano (OOXML, sin dependencias de Flutter), con los mismos datos que el
  Excel (`GdPlantillaFormatoDatos`): logo en las cuatro filas, TIPO arriba,
  título en mayúscula en dos filas, área, y Versión/Aprobado/Fecha/Código
  con la etiqueta sobre el color secundario; bordes finos del primario y
  colores de `TBL_EMPRESAS` igual que el Excel. Va en el **encabezado de
  página** (se repite en cada hoja). Pie: línea del color primario, empresa,
  código y versión a la izquierda y "Página X de Y" a la derecha. Carta
  vertical, Arial; estilos Título 1/2 y "Tabla con cuadrícula" en el color
  primario para que lo que se escriba debajo combine.
- Botones **PLANTILLA EXCEL** y **PLANTILLA WORD** en el paso 1 del alta del
  formato y en el detalle del formato (`generarPlantillaFormato*` con
  `word: true`). El nombre del archivo es el del Excel en `.docx`.
- Sello de Calidad: "Aprobado" es un control de contenido bloqueado
  (`w:tag gdAprobado`); al validar, `gdSellarPlantillaWordValidada` escribe
  quién validó en todas las copias del encabezado (Word o LibreOffice lo
  duplican al guardar) sin tocar el resto del archivo. `.xlsx` sigue igual.
- Validación: `.docx` generado validado contra los esquemas OOXML (con logo,
  sin logo y sellado) y renderizado con LibreOffice (encabezado, pie y sello
  correctos); el sello también funciona después de volver a guardar el
  archivo en LibreOffice. Pruebas: `test/gestion_documental/gd_formato_plantilla_word_test.dart`.
- Integrado sobre `main` `ed9d9f6` (planes K2 de Codex) junto con lo de
  Visitas: `flutter test` 1521/1521, Functions 174/174, reglas en emulador
  157/157 (+2 omitidas de antes) y planes K2 10/10; `flutter build web
  --release` correcto. Se entrega como parche para aplicar en `main` desde
  PowerShell (`git apply --3way`), probado también con finales de línea CRLF.
- Despliegue sugerido: Functions `visitasAsignarNumero`,
  `visitasNumerarHistoricas`, `interventoriaPlanes` e
  `interventoriaPlanesAvisos`, y hosting. Las reglas siguen esperando el plan
  de Tareas (apps 2.6.15 en tiendas).
- Sin verificar: apertura en Microsoft Word real (solo LibreOffice), Web a
  390/768/1024/1366 y con texto ampliado, Android e iOS (la descarga usa el
  mismo `FileSaver` del Excel).

## 2026-10-05 — Visitas: número de visita y establecimientos propios en Admin (Claude)

Pedido del usuario con el documento "Visitas - octubre 03" ("Guardar ID de
VISITA", ejemplo "Visita No 00001" en rojo junto al establecimiento) y, aparte,
"agregarle al módulo de visitas ciertos establecimientos que no son
necesariamente iguales a los de Interventoría, pero hacen falta para visitas;
lo podemos poner en el admin".

- **Número de visita.** Consecutivo por empresa que asigna el servidor:
  `visitasAsignarNumero` (`functions/src/visitas_numero.ts`, onCreate de
  `TBL_VISITAS`, contador `TBL_VISITAS_CONTADORES/{empresaId}`), mismo
  esquema que `tareasAsignarNumero`. Las visitas de prueba no se numeran
  (se pueden eliminar y dejarían huecos). La primera vez en una empresa se
  reservan 1..N para las visitas reales que ya existían; las del mismo lote
  de Programar no cuentan como históricas (`historicasAntesDe`).
  Incorporación revisable en **Admin › Migraciones › Número de visitas**
  (`visitasNumerarHistoricas`, `TaskNumeracionCard.visitas`).
- Se muestra en rojo junto al establecimiento en Cronograma, Mis visitas,
  Registro de visita y Por firmar; bajo el título en el detalle y al
  ejecutar; en el PDF ("VISITA No:" en DATOS, título, etiqueta del acta y
  tabla del consolidado), en el nombre del archivo y en la descripción de la
  tarea de cada hallazgo. El buscador encuentra "00012".
- Reglas: crear una visita con `numero` se rechaza; ninguna actualización lo
  admite; `TBL_VISITAS_CONTADORES` cerrado a la app y excluido del fallback.
- **Establecimientos propios de Visitas** (`TBL_VISITAS_ESTABLECIMIENTOS`):
  lugares que se visitan y no son centros de costo. Se crean, renombran e
  inactivan en **Admin › Maestros por módulo › Visitas › Configuración**
  (`lib/admin/visitas_establecimientos_panel.dart`; tabla desde 720 px,
  tarjetas en móvil, 20 por página). No se borran. Id = `centroId` =
  `{empresa}_est_{nombre}`; no repite el nombre de otro propio ni de un centro
  de costo de la empresa. En Visitas salen junto con los centros
  (`centrosDeEmpresa`/`streamCentros` → `unirEstablecimientos`): Programar,
  Equipo › Grupos y Ubicaciones (marcados "Solo Visitas", sin subcentros).
  Interventoría y Facturación no los ven. La tarea de un hallazgo en uno de
  ellos queda con sede `global` (no es centro de costo de Tareas).
- Reglas: escriben Desarrollo, Admin de la empresa y Gerencia de Visitas;
  leen quienes participan en Visitas y Admin, siempre de la misma empresa
  (la prueba detectó que `tieneAppAdminEn` sola dejaba listar a un Admin de
  otra empresa; corregido). Id y `centroId` fijos; borrar, nunca.
- Catálogo común: agregado a `MODULOS_MAESTROS` (antes de Ubicaciones, para
  que la copia traduzca el `centroId` de la ubicación) y a `kModulosMaestros`
  con `PanelAdminModulo.visitas`; también en Limpieza (maestros de Visitas).
- Validación: `flutter test --no-pub` 1491/1491 (13 nuevas en
  `test/visitas/visitas_numero_establecimientos_test.dart`, panel a 390 y
  1366 px); `npm test` de Functions; reglas en emulador
  (`test/visitas_establecimientos.rules.js` y las demás `*.rules.js`);
  `flutter analyze` sin avisos nuevos en los archivos tocados.
- **Pendiente de despliegue:** Functions `visitasAsignarNumero` y
  `visitasNumerarHistoricas` (sin ellas las visitas nuevas no reciben número)
  y reglas. Las reglas siguen el plan de Codex para Tareas (esperan a 2.6.15
  en las tiendas): mientras no se publiquen, `TBL_VISITAS_ESTABLECIMIENTOS`
  cae en la regla general (cualquier sesión de la empresa lee y escribe) y
  el bloqueo de `numero` en `TBL_VISITAS` no rige.
  Después, en cada empresa: Admin › Migraciones › Número de visitas ›
  **Revisar** y **Numerar visitas existentes**.
- Sin verificar en dispositivo: Web a 768/1024 px y con texto ampliado,
  Android e iOS (solo pruebas de widgets a 390 y 1366 px).
- Git: esta entrega se publicó por error primero en la rama
  `claude/pensive-ramanujan-4zdtkn`. Se integró sobre `main` (`ed9d9f6`, planes
  K2 de Codex) en un parche junto con la plantilla Word, que el usuario aplica
  en `main` con PowerShell; después se borra la rama remota.

## 2026-10-05 — Planes de mejora K2 implementados (Codex)

- Interventoría → Calidad → Planes de mejora: PM/CSC, hallazgos de visitas
  vinculados a sus tareas existentes, responsables actuales y dos entregas
  independientes. El administrador registra ID K2 y porcentajes; las actas
  nuevas no piden PDF ni evidencia inicial. Los archivos históricos se conservan.
- Máximos comunes por plan: propuesta +5/+20 días calendario desde notificación,
  confirmada o corregida por Calidad. Cada responsable ve las dos fechas.
  Edición de fechas con motivo, sin reiniciar plazos al vincular hallazgos.
- Compromiso, ejecución y seguimiento; revisar/devolver con motivo; evidencias
  de subsanación propias o reutilizadas de Tareas; copiar campos; PDF por hallazgo
  y ZIP; registro explícito de la presentación en K2 por etapa. Cambiar una
  entrega invalida su revisión. Reaperturas y versiones quedan auditadas.
- Avisos de asignación, entrega, revisión y reapertura; recordatorios diarios
  a las 08:00 de Bogotá desde tres días antes de cada máximo, sin duplicarse
  ni volver a marcar avisos leídos. Navegación desde Tareas y Notificaciones.
- Servicio exige empresa habilitada, app vigente y rol canónico de Calidad o
  asignación actual de tarea. Firestore directo denegado en expedientes y
  subcolecciones; evidencias cifradas y descargadas por servicio autorizado.
  Se reutilizan `interventoriadashboard`, Admin y su creador de roles; no se
  crean maestros ni fuentes de configuración duplicadas. Sin migraciones.
- Validación: 252 pruebas Flutter (Interventoría y catálogo de maestros), 25
  de creador/asignación/edición/revocación de roles, 6 de política y 10 de
  integración Firestore/Storage. Cobertura de empresa secundaria, rol histórico,
  reactivación, reasignación, versiones, PDF y avisos. TypeScript y Web compilan.
  Widgets en 390/768/1024/1366, texto 1/1.6, temas Android e iOS; capturas y PDF
  de prueba revisados. Las pruebas no modificaron datos de producción.
- Pendientes reales: despliegue de reglas, dos Functions y cliente; prueba
  autenticada en navegador y en Android/iPhone reales (teclado, áreas seguras,
  cámara, archivos y descarga). Web JS compilada; dependencias existentes
  siguen mostrando advertencias de compatibilidad Wasm. No se implementan
  importación Excel, correo ni envío automático a K2 en esta entrega.
- Alcance y límites en `docs/interventoria-k2-propuesta.md`. Se conservó el
  trabajo local previo de Functions y registradores generados.

## 2026-10-05 — Propuesta de preparación de planes K2 (Codex)

- Analizados el PDF `NUEVO SUBMODULO_INTERVENTORIA.pdf` (10 páginas), el
  Excel `k2_EstadoPlanMejoraOperador_2026-10-01.xlsx` (9 registros, 14
  columnas) y el flujo autenticado de K2, solo en consulta. No se enviaron
  respuestas ni se modificaron planes externos.
- Propuesta en `docs/interventoria-k2-propuesta.md`: ampliar Interventoría
  con planes para Calidad vinculados a las tareas existentes; revisión de
  compromisos y soportes por separado, copiar campos, PDFs por hallazgo y
  registro explícito de presentación en K2. No implementado ni desplegado.
- El usuario indica 5 días calendario para respuesta y 20 para soportes.
  Falta precisar el origen de ambos plazos y si son internos o externos.
  K2 muestra para PM-4158 notificación 27/09, presentación 05/10 y ejecución
  máxima 27/10/2026: conservar las fechas oficiales sin sustituirlas por una
  regla supuesta. Preguntas de cómputo enviadas al usuario.
- Identificados puntos de integración: distinguir numeral, ordinal de
  hallazgo, ID externo de visita y número de tarea; importación con vista
  previa, sin duplicados ni sobrescritura. El Excel declara A1:A1 pero
  contiene más filas/columnas; no confiar en esa dimensión al importarlo.
- Validación pendiente de la funcionalidad futura: permisos en servidor,
  roles y multiempresa, vencimientos, archivos, alertas, Web a
  390/768/1024/1366 con texto ampliado, Android e iOS. No se confirmó API
  oficial de K2. Se conservaron los cambios locales ajenos de Functions y
  registradores generados; esta entrega solo documenta el análisis.

## 2026-10-05 — Comprobación cruzada de Tareas 2.6.15 (Codex)

- Se trajo `origin/main` de `c9a9b65` a `a3c93be` (commits de Claude
  `3a70c8f`, `7212f90` y `a3c93be`). El trabajo local anterior de Codex quedó
  conservado en el stash local `Codex local Tareas review before Claude sync
  2026-10-05`, sin mezclarlo con la versión recibida. La implementación de
  Claude cubre los paneles centrados, dictado, buscador estable, tarjetas y
  filtros, Correspondencia, Mi equipo, exportaciones y numeración que estaban
  en revisión local, además de las correcciones de Compras.
- La Web pública `https://to-do-gestion.com/version.json` respondió
  `2.6.15` / build `29` el 5 de octubre. Se descargó el `main.dart.js`
  público y contiene textos de las nuevas pantallas de dictado, filtros,
  Correspondencia y equipo. Firebase lista activas las Functions nuevas
  `tareasAsignarNumero` y `tareasNumerarHistoricas`. Esto confirma publicación
  de Web y presencia de Functions, pero no sustituye una prueba de sesión real.
- La App Store colombiana sigue mostrando iOS `2.5.0 (12)` en la consulta
  oficial de Apple. La ficha pública de Google Play para
  `com.todogestion.app` devuelve 404; no se pudo saber el estado de canales
  internos de Android. La numeración de tareas históricas requiere ejecutar
  **Revisar** y **Numerar** en Admin para cada empresa; no se verificó si ya se
  hizo. Las reglas nuevas constan como pendientes en la entrada del 3 de
  octubre; su estado desplegado no se comprobó en esta revisión.
- Validación local de lo sincronizado: `flutter test --no-pub` 1478/1478;
  `node --test test/tareas_numero.test.js` 6/6; `flutter analyze --no-pub`
  sin errores, con 211 avisos de lint. Quedan sin prueba visual
  autenticada la Web a 390/768/1024/1366 y con texto ampliado, la app
  instalada de Windows, Android e iOS.
- Diferencias frente al trabajo local reservado: la versión recibida muestra
  **PENDIENTE** en la interfaz, pero las tareas nuevas conservan
  `estado: en_progreso` en datos; Gerencia y avisos de servidor aún usan ese
  estado. El texto de permiso de micrófono y reconocimiento de voz en iOS
  todavía menciona solo Interventoría. Las reglas propuestas permiten a
  quien tenga `puedeVerEquipo` leer cualquier tarea de su empresa, mientras
  el tablero limita en la interfaz el equipo de jefes y directores. Hay que
  ajustar ese alcance en reglas antes de considerarlo protegido por servidor.

## Tareas: documento "TAREAS - SEPTIEMBRE 29" completo — 3 oct 2026 (Claude)

Pedido del usuario desde un PC nuevo: "Codex estaba trabajando algo y no hay
ningún cambio de lo que corresponde en Tareas: no está centrado, no está el
dictado". En `main` (`c9a9b65`) no había nada de esos puntos ni ramas con
trabajo de Codex: si Codex dejó cambios sin subir en el PC anterior, siguen
allá y van a chocar con estos (mismos archivos de `lib/home/`). Antes de
traerlos, comparar contra esta entrada.

- **Paneles centrados.** `showTaskPanel` (`task_responsive_layout.dart`):
  diálogo centrado desde 600 px lógicos de ancho, hoja inferior en el
  teléfono (por ancho, no por `kIsWeb`). Lo usan Mis tareas, Tareas que
  asigné, Por aprobar, sus paneles de novedades/avances/adjuntos, Historial y
  Mi equipo. Ambos se apilan en el mismo `Navigator` que la pantalla
  (`useRootNavigator: false`), así que `Navigator.pop(context)` sigue
  cerrando el panel.
- **Dictado en Crear tarea** (título y descripción). El diálogo de Visitas
  pasó a `lib/widgets/dictado_dialog.dart` (`DictadoDialog`,
  `DictadoSuffixButton`) y Visitas usa el mismo.
- **Buscador que "solo deja digitar un carácter".** Causa: Mis tareas y
  Tareas que asigné armaban la consulta en cada `build`; al escribir, el
  StreamBuilder volvía a "cargando", reemplazaba la pantalla y el campo
  perdía el foco. Ahora la consulta se crea una vez por empresa y solo la
  primera carga muestra el esqueleto. Mi equipo repetía la consulta con cada
  letra (FutureBuilder en `build`): también quedó fija.
- **Estado uniforme** (`lib/core/task_estado_visible.dart`): PENDIENTE gris,
  REASIGNADA violeta, POR_APROBAR amarillo, RETRASADA rojo, TERMINADA verde,
  sin importar el módulo. El `estado` guardado no cambia; `en_progreso` y la
  devuelta se ven PENDIENTE (la devuelta con la marca "Devuelta"). Reasignada
  = `reasignada_desde_uid`, reasignación aprobada o en trámite. Lo usan las
  pantallas de Tareas y la etiqueta de las tareas del Home; Gerencia sigue
  con `taskStatusColor` (su torta distingue pendiente de en progreso).
- **Error de fechas corregido:** `taskDaysLeft` truncaba hacia cero y una
  tarea vencida ayer no salía RETRASADA hasta el día siguiente (el servidor,
  con `Math.floor`, sí la marcaba). Ahora cuenta días de calendario.
- **Mis tareas:** número interno en la tarjeta; el pie muestra quién asignó
  (la matriz de Interventoría sale como "Interventoría"); tarjeta compacta en
  grilla de 3/2/1 columnas según el ancho (`TaskCardGrid`, 20 por página);
  contadores por estado en los filtros; "Área que asignó" agrupa y filtra por
  el área de QUIEN ASIGNÓ (antes era el área de la propia tarea, que es la
  del responsable) y solo ofrece áreas de las que la persona tiene tareas;
  filtro por módulo de origen (Manual, Interventoría, Visitas, Gestión de
  Correspondencia, Compras…). El área de cada persona sale de
  `PersonasEmpresa` (`lib/core/task_personas_empresa.dart`), con el puente
  por cargo que ya usaban la reasignación y Visitas.
- **Tareas que asigné:** filtro principal "Asignadas desde" que arranca en
  "Asignadas por mí (manual)"; lo que nació en un módulo (Correspondencia,
  Calidad de Compras…) se ve eligiendo el origen. Cargo del responsable solo
  con cargos que tienen tareas pendientes, reasignadas o retrasadas. El
  responsable aparece una sola vez (pie de la tarjeta, sin chip repetido).
  Ver novedades/avances/adjuntos quedan inhabilitados cuando no hay nada.
- **Correspondencia en el panel de la tarea:** ya no salta al módulo. El
  panel muestra la vista previa de la respuesta (enviada, en borrador,
  respondida fuera o cerrada sin respuesta, con motivo y adjuntos;
  `task_correspondencia_preview.dart`), el botón "Ver en Gestión de
  Correspondencia" y, en POR_APROBAR, Aprobar/Devolver como cualquier tarea
  (el paso que `gdTerminarExpediente` deja a `_approveFinish`).
- **Tareas por aprobar:** área y responsable solo con tareas que esperan la
  aprobación de la persona; la tarjeta dice "Terminada el …" (fecha en que el
  responsable pidió el cierre).
- **Tareas de mi equipo** (reescrita): tablero por responsable (pendientes,
  reasignadas, por aprobar, retrasadas, total y la más antigua; tocar uno
  filtra), filtro por responsable solo con tareas no terminadas, matriz N.º /
  responsable / descripción / asignada por / fecha de asignación / estado /
  días (tabla en Web, tarjetas en el teléfono, 20 por página), Excel y PDF de
  lo filtrado (`team_tasks_export.dart`; el PDF usa `assets/arial.ttf` y,
  sin ella, Helvetica sin caracteres fuera de Latin-1) y detalle con el
  historial de actividad. Gerencia consulta solo los estados abiertos (antes
  1000 tareas de cualquier estado, y las terminadas desplazaban a las
  abiertas). Se corrigió la colección de centros (`TBL_CENTROS_COSTO` no
  existe; el filtro se retiró porque el documento no lo pide).
- **Botón "Tareas de mi equipo":** el cargo "Gerencia" no contiene "gerent"
  y `canViewTaskTeam` lo dejaba por fuera; por eso Oscar no lo veía.
- **Correcciones de Compras al Analista de Compras:** el rechazo y la
  aprobación con requerimientos de Calidad crean la tarea para la persona
  activa con cargo de Analista de Compras (`esCargoAnalistaCompras`); si quien
  subió el documento es analista, se queda con él; si la empresa no tiene ese
  cargo, el rol Compras del módulo; si tampoco, quien subió (como antes).
  `requerimientoResponsableId` sigue al mismo responsable, para que pueda
  adjuntar el soporte. Quien subió recibe el aviso informativo.
- **Número interno** (`functions/src/tareas_numero.ts`):
  `tareasAsignarNumero` (onCreate, reintento activado) da un consecutivo por
  empresa en `TBL_TAREAS_CONTADORES/{empresaId}`; la primera vez reserva
  1..N para las tareas que ya existían. `tareasNumerarHistoricas` (Admin ›
  Usuarios › Migraciones de usuarios, tarjeta "Número interno de tareas")
  revisa y luego numera las existentes en orden de creación dentro de esa
  reserva. Un número asignado no cambia. Reglas: el contador es solo de
  servidor y la app no puede crear ni cambiar `numero`.
- **Versión 2.6.15 (29)**, subida a pedido del usuario para comprobar la
  publicación (la 2.6.14 (28) no se publicó). La 2.6.13 (27) generada en el
  PC anterior no lleva nada de esto.
- **Pruebas:** `flutter analyze` sin errores y con las mismas advertencias
  que antes (213 → 211 avisos). Nuevas: estado visible, módulo de origen,
  número y días (`test/core/task_estado_visible_test.dart`), áreas y cargos
  por persona (`task_personas_empresa_test.dart`), días de calendario
  (`test/utils/task_status_test.dart`), Excel/PDF del equipo
  (`test/home/team_tasks_export_test.dart`), panel centrado en 1366 px y hoja
  en 390 px, grilla de 20 con grupos, contadores y desplegable sin la opción
  elegida (`test/widgets/task_filters_grid_test.dart`), Gerencia ve su
  equipo y cargo de Analista de Compras. Suite completa de Flutter
  1478/1478. Functions: `npm test` 165/165 (6 nuevas de numeración) y ESLint
  sin errores en el archivo nuevo. Reglas en emulador: todas las suites
  `functions/test/*.rules.js` 150 aprobadas y 2 omitidas que ya estaban
  marcadas "[pendiente TH]"; `tareas_rules.rules.js` 13/13 con una nueva (la
  app no crea ni cambia `numero` y no lee ni escribe el contador).
- **Pendiente:**
  - **Reglas: no publicarlas todavía.** 3 oct, desde el PC nuevo: la
    compilación volvió a dar HTTP 503 en
    `firebaserules.googleapis.com/...:test` (igual que el 2 oct; en el
    emulador compilan y pasan). Producción sigue con las reglas anteriores al
    2 oct, donde `TBL_TAREAS` no tiene regla propia y cae en la regla general
    (cualquier sesión lee y escribe): la Web 2.6.15 funciona con ellas. Las
    reglas nuevas son más estrictas y la app de iPhone de la tienda (2.5.0)
    y los Android anteriores consultan el Home sin empresa: se quedarían sin
    tareas. Orden: Web y Functions ahora; reglas cuando 2.6.15 esté en las
    tiendas y `TBL_CONFIG/APP_VERSION` obligue a actualizar, y antes
    averiguar el 503 (el bloque de `TBL_TAREAS` del 2 oct llevó el archivo
    de 104 KB a 129 KB; no supera los límites documentados de argumentos,
    `let` ni tamaño). Los índices sí se pueden publicar solos
    (`firebase deploy --only firestore:indexes`).
  - Publicar Functions (incluye `tareasAsignarNumero` y
    `tareasNumerarHistoricas`) y Web (`flutter build web --release` y
    `firebase deploy --only hosting`). Comprobar que
    `https://to-do-gestion.com/version.json` diga 2.6.15 / 29 y el menú
    lateral también. Luego, por empresa, Admin › Usuarios › Migraciones de
    usuarios › "Número interno de tareas": Revisar y Numerar. Sin las
    Functions, la app funciona y simplemente no muestra número.
  - Sin verificación visual en Web (390/768/1024/1366, texto ampliado),
    Android ni iOS: el ingreso pasa por Functions de producción. Revisar en
    especial la grilla de 3 columnas, el panel centrado en un portátil de
    10" y el PDF del equipo en iPhone (`Printing.sharePdf`).
  - El estado uniforme no se llevó a Gerencia ni a las notificaciones del
    servidor ("Estado de tarea: En progreso"); si se quiere igual allí, es
    otro cambio.
  - Si una empresa tiene varias personas con cargo de Analista de Compras,
    la tarea va a la primera por nombre (o a quien subió, si es analista).
    Si se necesita reparto, definir la regla.

## Tareas: completar con comentario, "¿novedad o finalización?", historial y reasignación a otras áreas — 2 oct 2026 (Codex → Claude)

Pedido del usuario (además del documento `TAREAS - SEPTIEMBRE 29.docx`, que
queda como contexto): (1) completar tareas con comentario, también desde
Interventoría; (2) la gente confunde novedad con cumplimiento: preguntar al
enviar una novedad si en realidad es una finalización; (3) guardar y mostrar
el historial de lo que cada quien puso como novedad y como finalización;
(4) reasignar también hacia otras áreas, eligiendo área y persona.
Codex dejó la interfaz casi lista y se quedó sin cupo revisando las reglas;
Claude completó, corrigió y validó.

- **Completar con comentario.** `CompleteTaskScreen` pide "Comentario de
  finalización" (obligatorio, hasta 3000) y lo guarda en
  `TBL_TAREAS/{id}/finalizacion` (`comment`) en la misma transacción que deja
  la tarea por aprobar. Se quitó el "envío rápido" sin formulario de
  Mis tareas. En Interventoría, el panel del hallazgo tiene "Solicitar
  finalización" para el responsable y "Ver historial de actividad".
- **¿Novedad o finalización?** Al enviar una novedad sale el diálogo; "Ir a
  finalización" abre el formulario de cierre con el texto ya escrito (los
  adjuntos de la novedad no se trasladan y el diálogo lo advierte).
- **Historial.** `TaskActivityScreen` (desde Mis tareas y el panel del
  hallazgo) muestra novedades, avances y finalizaciones con su comentario; en
  Tareas que asigné el aprobador ve "Comentario y evidencias" y la fecha en
  que el responsable terminó antes de aprobar; la devolución del aprobador ahora guarda quién devolvió (`by`)
  y el historial muestra su motivo. Nueva pestaña "Antes asignadas" en el
  historial: tareas por `participantes_uid` que ya no son de la persona.
  Aprobar la finalización deja un registro `aprobacion_finalizacion`.
- **Reasignación a otras áreas.** El diálogo arranca en "Todas las áreas" y
  filtra por área, centro de trabajo, cargo y búsqueda; la persona elegida
  define el destino. El área de cada persona sale de su cargo cuando la ficha
  no trae `areaId` (puente por `TBL_CARGOS`, igual que Interventoría): antes
  casi nadie aparecía al filtrar otra área. Avatar y nombre en la lista. Las
  tareas de Interventoría se reasignan directo; las demás siguen como
  solicitud que aprueba el jefe. No se ofrece reasignar con la finalización
  en espera. Quien entrega la tarea queda en `participantes_uid` y sigue
  viendo su historial.
- **Reglas de `TBL_TAREAS` (de Codex, sin desplegar) corregidas.** Tal como
  estaban: (a) la reasignación directa nunca pasaba (vivía dentro de la rama
  que exige el mismo responsable); (b) casi toda petición rechazada, y varias
  válidas, agotaban el tope de 1000 expresiones (`belongsToCompany` + apps
  cuesta ~300 y se evaluaba varias veces); (c) la consulta "Antes asignadas"
  no se podía demostrar (`participantes_uid is list` impide probar
  `array-contains`); (d) un responsable podía agregar una "finalización" a
  una tarea ya cerrada; (e) la aprobación de la subsanación en Interventoría
  exigía una solicitud pendiente en la tarea y tumbaba la transacción del
  hallazgo; (f) las herramientas de Desarrollo (cambio de cédula, borrar
  usuario) consultan por persona sin empresa y se caían. Reescritas: lo
  barato primero (evento, actor, campos que cambian) y empresa/app una sola
  vez al final; `diff()` una vez por petición; Desarrollo lee sin filtro de
  empresa y mantiene las tareas (nunca cambia la empresa); el cambio de
  aprobador de Interventoría queda solo por servidor
  (`interventoriaCambiarAprobador`); pasar al creador automático las tareas
  de la matriz queda para administración/gerencia de Interventoría.
- **Consultas ajustadas a las reglas.** El Home consultaba `TBL_TAREAS` sin
  empresa (ahora filtra por la empresa activa, que ya filtraba en el
  cliente). "Mi equipo" y la vista de equipo sumaban una consulta por la
  lista `empresas` que las reglas rechazan, y al ir en el mismo
  `Future.wait` tumbaban la pantalla: ahora solo por `empresaId`.
- **Pruebas:** `functions/test/tareas_rules.rules.js` 12/12 en emulador
  (lectura por empresa y vínculo, creación, finalización con comentario en
  lote, reasignación directa y por solicitud hacia otra área, novedad/avance,
  devolución, subsanación de Interventoría, cierre administrativo,
  mantenimiento de Desarrollo y una prueba de margen que repite los flujos
  permitidos más caros con 150 expresiones de relleno). Costos medidos
  (de 1000): reasignación directa ~780, solicitar reasignación ~720, aprobarla ~595, solicitar finalización ~500 (igual con 11 o 70 campos en la tarea: el tamaño no influye). Una petición rechazada puede terminar en "maximum of 1000" porque al fallar se evalúa también la regla general; sigue siendo un rechazo. `flutter test` de Tareas (navegación, permisos,
  contrato, calendario, equipo, origen) 39/39. `dart analyze` de los archivos
  tocados sin errores (las advertencias de `home_screen.dart` son
  anteriores). Las demás suites de reglas siguen pasando (Rutas 11, empresa
  5, inhabilitados 9, Interventoría 11 + 5, Gerencia 2, roles 10);
  `rutas.rules.js` usaba `TBL_TAREAS` como ejemplo de la regla general y
  ahora usa una colección sin regla propia.
- **Versión 2.6.13 (27)** para comprobar la publicación.
- **Comprobación de publicación (2 oct 2026):** `main` y `origin/main`
  coinciden en `251ceddb`; la Web pública (`to-do-gestion.com/version.json`)
  informa `2.6.13+27` y las Functions consultadas están activas. La App
  Store colombiana aún muestra iOS `2.5.0 (12)` (11 sep 2026), por lo que
  iOS 2.6.13 no está publicada allí. La ficha pública de Play para
  `com.todogestion.app` devuelve 404; no se puede comprobar el canal de
  pruebas de Play sin entrar a Play Console. Se generó el AAB Android
  `build/app/outputs/bundle/release/app-release.aab` (2.6.13, código 27,
  `com.todogestion.app`, firma verificada; SHA256
  `2CEF04036210FDCDCD679A4B249DFE9C41E005A61B6BA968F8D181F2AE06A7EC`).
  En este entorno, Gradle primero falló con `Unable to establish loopback
  connection`; se resolvió solo para el proceso con
  `JAVA_TOOL_OPTIONS=-Djdk.net.unixdomain.tmpdir=.../__no_existe_socket__`
  para que Java usara TCP local. Flutter luego falló al verificar los símbolos
  porque el SDK de Android vive en una ruta con espacios; un junction ignorado
  en `build/AndroidSdk` y `ANDROID_HOME` apuntando allí permitieron terminar
  `flutter build appbundle --release --no-pub` con salida 0. No se cambió la
  configuración versionada del proyecto. En producción,
  `TBL_CONFIG/APP_VERSION` aún tiene `minBuildAndroid=6`, `minBuildIos=6`,
  `latestBuildAndroid=12` y `latestBuildIos=12` (las URL de tienda existen):
  los builds anteriores a 27 todavía no reciben el aviso obligatorio.
  El índice `participantes_uid` + `empresaId` aún no aparece en el proyecto.
  La prueba remota de `firestore.rules` recibió HTTP 503 `UNAVAILABLE` de
  `firebaserules.googleapis.com/v1/projects/integra360-94704:test`, sin
  diagnóstico de sintaxis; no se desplegaron las reglas.
- **Pendiente:**
  - Coordinar Android/iOS 2.6.13 con el despliegue de `firestore.rules` e
    `firestore.indexes.json` (índice `participantes_uid` + `empresaId`):
    una app móvil vieja todavía consulta el Home sin empresa y recibiría
    permission-denied. Una vez disponibles ambas versiones en las tiendas,
    configurar `TBL_CONFIG/APP_VERSION` (`minBuildAndroid` y `minBuildIos`
    en 27, con sus URL de tienda) para forzar la actualización de los
    clientes anteriores; verificar el documento y el aviso en cada plataforma.
    La Web ya informa 2.6.13+27. Las reglas comparten
    archivo con el trabajo de Interventoría del mismo día (concepto
    sanitario), también sin desplegar.
  - Tareas reasignadas antes de este cambio no tienen `participantes_uid`:
    no salen en "Antes asignadas" (sí se leen por `reasignada_desde_uid`).
    Si se quiere el histórico, preparar una incorporación revisable por
    empresa.
  - `crearTareaYNotificarHallazgo` borra la tarea anterior al reasignar en
    Interventoría; las reglas solo dejan borrar a Admin, Desarrollo y a
    administración/gerencia de Interventoría. Con otros roles el `try` deja
    viva la tarea vieja (lo anotó también la sesión de Interventoría).
  - Mis tareas y Tareas que asigné consultan sin empresa si no hay empresa
    activa y la persona tiene varias; con las reglas eso falla en vez de
    mezclar empresas. En la práctica siempre hay empresa activa tras el
    login.
  - `CompleteTaskScreen` conserva la rama `requestFinish: false` (finalizar
    sin aprobación), que las reglas no permiten; hoy nadie la usa.
  - Sin verificación visual en Web (390/768/1024/1366, texto ampliado),
    Android ni iOS: el ingreso pasa por Functions de producción.

## Interventoría: revisión del 28 sep 2026 (aprobador a mano, Análisis, concepto sanitario, jefe inmediato, empresa en el encabezado) — 2 oct 2026 (Claude)

Documento `INTERVENTORIA - SEPTIEMBRE 28.docx` y reporte del usuario sobre
Análisis en una pantalla de 16".

- **Error al asignar ("La regla no tiene un aprobador activo").** El aprobador
  salía solo de la regla del maestro; en los numerales sin regla (actas de
  policía como el 3.1 de Bordo, el 90.2, los que no se identifican) elegir a
  Miguel, Alejandro o Geisson fallaba siempre. Ahora la asignación a mano
  tiene dos pasos (`elegirAsignacionManual`, compartido por tablero y panel):
  quién responde y una confirmación de quién aprueba, que propone la regla, el
  aprobador actual o el jefe inmediato de quien responde
  (`resolverAprobadorAsignacion`) y deja cambiarlo. Si no hay ninguno, hay que
  elegirlo. El jefe inmediato solo entra en asignaciones a mano: la
  automática (completar acta, "Asignar por el maestro") sigue exigiendo el
  aprobador de la regla y, si no resuelve, deja el hallazgo en "Sin asignar".
  `InterventoriaUsuario.jefeId` se lee por empresa con las claves de
  `OrgContextResolver`.
- **Cambiar el aprobador al reasignar.** Botón "Cambiar aprobador" en el
  tablero y en el panel. Va por servidor (`interventoriaCambiarAprobador`,
  `functions/src/interventoria_aprobador.ts`): las reglas de `TBL_TAREAS` que
  se están cerrando en paralelo no dejan mover `jefe_uid`/`aprobador_uid` desde
  el cliente. Valida rol (administración, gerencia o Desarrollo), empresa y que
  la persona esté activa; actualiza hallazgo y tarea (los seis nombres del
  aprobador) sin rehacerla y avisa al nuevo aprobador (en silencio salvo que
  ya esté por aprobar).
- **"El 3.1 no aparece en el maestro".** El acta regular salta del 3 al 3.2
  (así es el papel); el 3.1 era de un acta de Estación de policía. La tarjeta
  y el panel dicen de qué acta es el hallazgo, el aviso dice "el maestro de
  Estación de policía no define…", y al buscar un numeral que el acta elegida
  no tiene, el maestro indica en qué acta está y lleva a ella.
- **Por revisar:** "Fecha de acta 10/09/2026 · Fecha cargue 10/09/2026
  (18 días)" (`diasDesdeCargue`, días corridos desde `fechaRegistro`) y el
  tipo de acta con su nombre legible.
- **Análisis.** (1) Toda la pestaña baja con la página: antes el gráfico era
  fijo y la matriz vivía con su propio scroll en el alto sobrante, y en el
  portátil la rueda no bajaba. (2) La barra horizontal no se dejaba arrastrar:
  había dos encimadas y la de `BarraHorizontal`, sin controlador, buscaba el
  PrimaryScrollController ("no ScrollPosition attached", reproducido en
  prueba). `BarraHorizontal` ahora deja una sola barra en toda la app: sin
  controlador no dibuja nada (vale la del tema) y con controlador apaga la del
  tema. Arregla también las tablas del Maestro, Revisión y Subsanaciones.
  (3) La matriz tenía fijas las filas del acta regular: las actas de policía,
  alcaldía e infraestructura salían con "NE" en todo. Ahora cada tipo de acta
  presente aporta sus secciones con un título (`filasMatrizAnalisis`); "—"
  marca la sección que no existe en esa acta. Columnas de a 20 actas
  (`PagerBar`). (4) El gráfico inicial ordenaba por nombre y las actas
  recientes quedaban fuera de la pantalla: ahora arranca por "Más recientes",
  con "Menor puntaje" y "Nombre", y su barra horizontal se arrastra.
- **Concepto sanitario (sección nueva).** Pestaña "Concepto sanitario":
  establecimiento, fecha, puntaje, concepto (Favorable / Favorable con
  requerimientos / Desfavorable) y el archivo del acta, opcional. Colección
  `TBL_INTERVENTORIA_CONCEPTOS_SANITARIOS` con regla propia (lee la empresa,
  registran los roles con escritura, borran administración, gerencia y
  Desarrollo; valida puntaje y concepto) y fuera de la regla general. Web
  tabla, móvil tarjetas; marca el concepto vigente de cada sede. Registros
  operativos, no un maestro: no va a `kModulosMaestros`.
- **Integridad: cambio de jefe inmediato.** Disparador
  `tareasReemplazarJefeInmediato` (`functions/src/jefe_inmediato_sync.ts`)
  sobre `TBL_USUARIOS`: si a alguien le cambian el jefe en una empresa, sus
  tareas activas de esa empresa que estaban con el jefe anterior pasan al
  nuevo (`jefe_uid`, y el aprobador si era el mismo jefe) y el nuevo recibe un
  aviso con cuántas. No toca las de Interventoría (su aprobador sale del
  maestro), ni las cerradas, ni un aprobador elegido a propósito.
- **Empresa en el encabezado.** `EmpresaActivaChip` en `InternalModuleLayout`
  (los 26 módulos que lo usan): arriba a la derecha en Web; en el teléfono,
  segunda línea del AppBar. El nombre se lee una vez por empresa.
- **Pruebas:** `test/interventoria/interventoria_mejoras_28sep_test.dart`
  (15), `analisis_barra_horizontal_test.dart` (4), `app_scroll_behavior_test`
  actualizado; `flutter test test/interventoria test/app_scroll_behavior_test.dart`
  236/236. Functions: `jefe_inmediato_sync.test.js` e
  `interventoria_aprobador.test.js` (25/25 con las de Interventoría). Reglas en
  emulador: `interventoria_conceptos.rules.js` 5/5 y
  `interventoria_visitas.rules.js` 11/11.
- **Pendiente:** desplegar Functions (`interventoriaCambiarAprobador` y
  `tareasReemplazarJefeInmediato`; sin la primera, "Cambiar aprobador"
  responde not-found), `firestore.rules` y publicar Web/móvil. Sin
  verificación visual en Web (390/768/1024/1366, texto ampliado), Android ni
  iOS: el ingreso pasa por Functions de producción. No pude leer las actas de
  producción para confirmar por qué el gráfico "no traía las últimas" más
  allá del orden y la barra; si persiste, revisar actas con `fechaVisita`
  mal digitada. Queda por aclarar con el usuario qué es "la sección 12": no
  hay acta con 12 secciones (la regular tiene Concepto sanitario + 1 a 11).
- **Coordinación con Codex:** las reglas nuevas de `TBL_TAREAS`
  (`tareaBaseConservada`) prohíben mover `jefe_uid`/`aprobador_uid` desde el
  cliente: por eso el cambio de aprobador y el reemplazo de jefe van por
  servidor. `crearTareaYNotificarHallazgo` sigue borrando la tarea anterior al
  reasignar; con esas reglas solo Admin puede borrar, y el `try` deja la tarea
  vieja viva: conviene moverlo también a servidor o permitir ese borrado.

## Visitas: ubicación dentro de Iniciar, reasignación obligatoria, ubicaciones fuera del profesional y dictado del plan de acción — 1 oct 2026 (Claude)

Pedido del usuario: "que el dónde estoy quede combinado al hacer inicio,
que si alguien no cumple la visita primero tenga que solicitar reasignación y
quede registro, que a los profesionales no les salga lo de ubicaciones, y que
plan de acción permita por micrófono y que salga algo de hable ahora".

- **"¿Dónde estoy?" dentro de Iniciar.** Ya no hay botón aparte en Registro
  de visita. Al tocar Iniciar la app toma el GPS, muestra en la tarjeta del
  establecimiento si quedó dentro ("Estás en el establecimiento (a N m)") o
  a cuántos metros, y con esa misma lectura inicia (`iniciar(...,
  posicion:)`); el servicio vuelve a comprobar contra la referencia.
- **Reasignación obligatoria de lo incumplido.** `visitaIncumplida`: pasó su
  día programada o en curso (las pruebas no cuentan). El jefe ya no la mueve
  por su cuenta: el profesional solicita la reasignación ("¿Por qué no se
  cumplió?" + fecha propuesta), la solicitud queda con `tipo:
  'reasignacion'` y, al aprobarla (o reprogramarla con la solicitud
  pendiente), la entrada del historial lleva `incumplida: true`. El detalle
  muestra "No cumplida · …" y al jefe le avisa que falta la solicitud.
  Reglas: `esReprogramacionDeVisita` exige solicitud pendiente si ya pasó
  `fechaProgramada + 1 día`.
- **Ubicaciones fuera del profesional.** Sin el "¿Dónde estoy?" ya no ve el
  maestro (establecimiento más cercano, radios); la tarjeta de inicio no
  habla del maestro ni de "Visitas > Ubicaciones". Reglas: listar
  `TBL_VISITAS_UBICACIONES` solo Desarrollo, Gerencia y jefes
  (`administraVisitasEn`); el profesional sigue leyendo por id la de SU
  establecimiento para iniciar y cerrar.
- **Plan de acción por micrófono** y aviso **"Hable ahora…"** con el
  micrófono latiendo en todos los dictados de Visitas (observación,
  respuesta, observaciones generales y plan de acción).
- Pruebas: `functions/test/visitas_reasignacion.rules.js` (6) y todas las
  de Visitas en emulador (43/43); `flutter test test/visitas` 146/146 con el
  grupo nuevo de reasignación.
- **Desplegado** (commit `9919295`): web publicada (to-do-gestion.com con el
  bundle nuevo) y `firestore.rules` liberadas. La API de reglas de Google
  respondía 503 de forma intermitente, también con las reglas anteriores
  (2 de 5 en seco); entró al noveno reintento, sin cambiar las reglas.
- **Pendiente:** publicar Android e iOS (la app vieja que toque "¿Dónde
  estoy?" ahora recibe permission-denied). `resolverRegistroVisita` quedó
  sin uso en la app (solo sus pruebas). Sin verificación visual en Web,
  Android ni iOS; el dictado y el GPS hay que probarlos en el teléfono.

## Admin: error ilegible al cambiar el rol de Interventoría y Visitas: el jefe veía a su equipo "Sin rol" — 1 oct 2026 (Claude)

**Visitas › Equipo (Director de Calidad).** El jefe veía a sus profesionales
"Sin rol" y su departamento con 0 profesionales; Desarrollo y Gerencia los
veían bien. No eran las reglas (el jefe sí lista `TBL_VISITAS_ROLES`,
probado en emulador): `equipoVisitas` leía los roles con
`streamRoles(empresaId).first`, y el primer evento de un listener puede salir
de la caché con solo los documentos ya leídos. El jefe abre Visitas leyendo
su propio rol (`areaDeUsuario`), así que la lista llegaba con ese único
documento. Desarrollo no lee su rol antes y por eso no lo veía.
- `VisitasService` tiene lecturas únicas con `get()` (`rolesDeEmpresa`,
  `centrosDeEmpresa`, `gruposDeEmpresa`, `formatosDeEmpresa`,
  `ubicacionesDeEmpresa`) que comparten consulta y conversión con sus
  `stream...`. Equipo, Programar, el diálogo de ubicación y los formatos de la
  visita ya no usan `stream...().first`.
- **Pendiente (mismo patrón, fuera de Visitas):**
  `gerencia_interventoria_tab.dart` (`streamReglasSubsanacion(...).first`) e
  `interventoria_maestro_revision.dart` (`streamCentrosCosto(eid).first`).

**Admin › Apps, roles y permisos › Interventoría.** "No se pudo cambiar el
rol de Interventoría: Dart exception thrown from converted Future…". En web,
cualquier excepción dentro del manejador de una transacción sale envuelta
y esconde la causa. No eran las reglas: en el emulador, Desarrollo, Admin y el
administrador del módulo hacen la transacción completa de
`setIndividualLevel` (`functions/test/admin_roles_transaccion.rules.js`).
- `lib/core/transaccion_legible.dart` (`runTransactionLegible`) guarda el
  error de adentro y lo relanza afuera; la transacción se aborta igual. Lo
  usan todos los repositorios de roles de Admin, el inventario de módulos, el
  control documental de Compras y `ComprasService._transaccion`, que ya
  tenía su propia copia de este arreglo.
- `extractUserApps`/`extractUserEmpresaIds` ya no hacen `as List` sobre
  `apps`/`empresas`: un dato viejo con otra forma en CUALQUIER empresa de la
  persona tumbaba el cambio, porque `planearAppsPorEmpresa` las recorre
  todas.
- **Pendiente:** no se pudo ver la causa exacta en los datos (la lectura de
  producción no está autorizada en esta sesión). Con la nueva versión el
  mensaje dice el motivo real. Si vuelve a fallar, revisar la ficha de esa
  persona según el texto que aparezca.
- Pruebas: `test/core/transaccion_legible_test.dart`, regla nueva en
  emulador (4/4 + 21 de roles existentes) y `flutter test` de core, admin,
  visitas, compras, utils y gestión documental en verde (907). Sin
  verificación visual en Web, Android ni iOS.
- **Publicado en web** (commit `01a57ff`, misma versión 2.6.12+26):
  `flutter build web --release --no-tree-shake-icons --no-wasm-dry-run` y
  `firebase deploy --only hosting`. to-do-gestion.web.app y
  to-do-gestion.com responden 200 con el bundle nuevo. Android e iOS siguen
  con la compilación anterior.

## Biblioteca Documental: vista previa y Correspondencia relacionada caían en todos los documentos — 1 oct 2026 (Claude)

Reporte del usuario: al abrir cualquier documento de la Biblioteca, la vista
previa decía "No se pudo cargar la versión del documento"
(`failed-precondition`, índice `TBL_DOCUMENTOS_VERSIONES` docId+numero) y
"Correspondencia relacionada" decía `permission-denied`.

- **Versiones e historial sin índice compuesto.** `GdService.streamVersiones`
  y `streamHistorial` usaban `where('docId') + orderBy(...)`, que exige un
  índice compuesto que no está desplegado (confirmado con
  `firebase firestore:indexes`). Ahora filtran solo por `docId` y ordenan en
  el cliente (versiones por `numero` ascendente; historial por
  `realizadoEn` descendente, el evento recién escrito arriba), como ya
  hacía `streamDocumentos`. La pestaña Historial muestra el error en vez de
  quedarse cargando.
- **Consultas con `empresaId` en vínculos, colaboración y eventos.** Las
  reglas de `TBL_GD_VINCULOS`, `TBL_GD_COLABORACION` y
  `TBL_GD_EXPEDIENTES_EVENTOS` son `belongsToCompany(resource.data.empresaId)`;
  una consulta sin ese filtro no se puede probar y Firestore rechaza el
  listado entero. `streamVinculosDocumento`, `streamVinculosExpediente`,
  `streamColaboracion`, `streamEventos` y la búsqueda de vínculos al
  comentar ahora reciben y filtran por la empresa (la activa en el detalle
  de la Biblioteca; la del expediente, ya validada contra la activa, en
  Correspondencia). Esto también arregla "Documentos vinculados", "Mesa de
  colaboración" y "Trazabilidad del expediente" en Correspondencia, que
  tenían la misma falla. Todos los registros existentes llevan `empresaId`
  (la regla de creación lo exige y los eventos del servidor lo escriben).
- Sin cambios en `firestore.rules` ni índices: no hace falta deploy de
  reglas, solo publicar la app.
- Prueba nueva en emulador: `functions/test/gd_biblioteca_consultas.rules.js`
  (sin empresa se rechaza, con empresa se lee, otra empresa se rechaza).
  `flutter test test/gestion_documental` en verde.
- **Pendiente para Codex:** confirmar y publicar en `main`. Sin verificación
  visual en Web, Android ni iOS (requiere sesión real contra producción);
  validar en las tres plataformas abriendo un documento de la Biblioteca y
  un expediente de Correspondencia. De paso: `PpService.streamLotes` y
  `streamPlanillasPorLote` usan índices que tampoco están desplegados, pero
  hoy nadie los llama.

## Git compartido entre Claude y Codex — 30 sep 2026

Por decisión del usuario, Claude también puede sincronizar, confirmar y subir
sus propios cambios a GitHub. Ambos trabajan directamente en `main`, revisan
el contenido del commit para no incluir cambios ajenos y resuelven avances
remotos sin hacer push forzado. La regla está en `AGENTS.md`.

## Abastecimiento: desplegables en el Excel, período configurable y OC como identidad — 30 sep 2026 (Claude)

Pedido del usuario (documento "ABASTECIMIENTO – SEPTIEMBRE 28" y audio):

- **Modelo Excel con listas desplegables.** El botón "Modelo Excel" lee lo
  guardado en la empresa activa y lo pone como listas: proveedores activos,
  categorías de esos proveedores, grupos activos y estado (estrictas);
  productos, bodegas/destinos y unidades (sugeridas, admiten otro valor
  porque son informativos). Cantidad y precio exigen número y las fechas
  exigen fecha. Los valores van en la hoja oculta `Listas`; el paquete
  `excel` no escribe validaciones, así que se agregan al XML del libro
  (`lib/compras/abastecimiento_excel_template.dart`). El importador ignora
  esa hoja.
- **Período de consumo configurable.** Ya no es fijo de viernes a jueves:
  `TBL_COMPRAS_CONFIG/{empresaId}.abastecimientoPeriodo` guarda un ciclo de
  1 a 62 días desde una fecha de referencia (`modo: 'ciclo'`,
  `inicioReferencia: 'yyyy-MM-dd'`, `duracionDias`) o el mes calendario
  (`modo: 'mensual'`). Sin configuración rige la regla histórica (7 días
  desde el viernes 2 ene 2026). Se edita en **Admin › Maestros por módulo ›
  Compras › Configuración** (tarjeta "Período de consumo de
  Abastecimiento"); es configuración de la empresa y se copia con
  TBL_COMPRAS_CONFIG en "Copiar a otras empresas" (quién/cuándo no se
  copia). `firestore.rules` exige Admin o administrador de Compras de la
  empresa (`gestionaRolesDeModulo`) y valida la forma del campo. La lógica
  es una sola en la app (`lib/compras/abastecimiento_periodo.dart`) con su
  espejo en el servidor (`functions/src/compras_abastecimiento_reports.ts`);
  la carga Excel, la entrega manual, el filtro y el reporte de las 5:00
  p. m. usan la misma configuración, y el servicio rechaza un período que
  la configuración vigente no genera.
- **La OC identifica la entrega.** Una fila del Excel actualiza la entrega
  existente con la misma OC y el mismo producto (antes la clave incluía
  hoja, grupo y destino y por eso aparecían duplicados como BOGOTA/BOGOTAQ).
  Reglas nuevas en `lib/compras/abastecimiento_import_rules.dart`:
  - Solo cambia por Excel una entrega **Programada**. Si pasó a otro estado
    y el archivo trae algo distinto: "No se puede subir la OC-XXXX porque
    pasó a un estado posterior a programado (Entregado)". Si el archivo no
    cambia nada, cuenta como sin cambios.
  - Una OC pertenece a un solo proveedor: si ya está relacionada con otro
    (en Abastecimiento o en Recepción) la fila se rechaza con "La OC-X ya
    está relacionada con el proveedor Y". También si el archivo trae la
    misma OC con dos proveedores.
  - Filas repetidas en el archivo (misma OC y producto) o que coinciden con
    varios registros guardados sin poder elegir por destino: aviso
    "Existen registros duplicados" en la revisión de la carga, y no se
    cargan.
  - La entrega manual aplica las mismas reglas de OC.
  - Corregido de paso: una celda de observaciones vacía ya no borra las
    pendencias; una entrega eliminada ya no se "actualiza" oculta con otra
    carga.
- **Reportes PDF.** "PDF de lo filtrado" (barra de filtros en Web, ícono de
  impresora en móvil) arma el PDF con exactamente lo que muestra la lista y
  lleva el nombre de la empresa y los filtros. El reporte automático usa el
  nombre de la empresa (antes el id `EMPRESA_002`) y **ya no guarda
  histórico**: cada ejecución deja solo el del período vigente por grupo y
  borra los anteriores con su PDF; la lista del diálogo muestra solo el
  vigente. `comprasGenerarReporteAbastecimiento` ahora exige que quien lo
  llama pueda entrar a la empresa (antes cualquier sesión podía generarlo
  para cualquier empresa).
- **"Con pendientes" aclarado.** Tiene ayuda (tooltip) y, al activarlo, una
  línea explica que muestra las entregas con PND, pendiente de pago o de
  entrada en Observaciones.

Datos históricos (transición):

- Las entregas conservan el período con que se cargaron aunque la empresa
  cambie la configuración; el filtro de consumo ofrece los períodos
  configurados y los que ya tienen entregas. Solo se corrige el rango
  histórico jueves–viernes de 9 días y las entregas sin período completo
  (toman el ciclo viernes–jueves de su fecha). Una entrega antigua con
  `consumoDesde`/`consumoHasta` guardados que no eran viernes–jueves ahora
  se muestra con su rango guardado (antes se forzaba al viernes).
- Los duplicados que ya existen (misma OC y producto) no se borran solos:
  la carga los señala y la fila no se aplica hasta eliminar el sobrante en
  Abastecimiento. Pendiente sugerido: un listado revisable por empresa de
  OC duplicadas para depurarlas de una vez.

Versión 2.6.12 (26), integrada en `main` por Claude a pedido expreso del
usuario (el primer intento de integración no llegó a `origin/main` y el
despliegue publicó la versión anterior). Compilación Web verificada.

**Estado del despliegue (30 sep, noche):** Hosting 2.6.12 (26) y las
Functions `comprasReporteAbastecimiento1700`,
`comprasGenerarReporteAbastecimiento` y `adminSincronizarMaestros`
publicados. **Reglas de Firestore pendientes:** `firebaserules.googleapis.com`
respondió 503 en todos los intentos (también con las reglas anteriores, no es
por el cambio). La app funciona sin ellas: solo agregan la validación del
campo `abastecimientoPeriodo`. Reintentar `firebase deploy --only
firestore:rules`.

El respaldo de los cambios locales que quedaron en el equipo del usuario
(`origin/respaldo-local-30sep`) es la primera versión del arreglo de
Planillas y la regla de Git, ya en `main`. Se portó a `main` la prueba que
faltaba (gerente con Planillas asignada y aislamiento de otra empresa en
`registerMissing`); la rama puede borrarse.

**Urgente:** Google deja de aceptar despliegues de Functions con Node.js 20
el 30 oct 2026; hay que pasar `functions` a Node 22 antes.

Despliegue necesario: reglas de Firestore, Functions
(`comprasReporteAbastecimiento1700`, `comprasGenerarReporteAbastecimiento`,
`adminSincronizarMaestros`) y Hosting. Tras desplegar Functions, la primera
ejecución de las 5:00 p. m. (o "Generar ahora") borra los reportes de
períodos anteriores.

Validación: 1.428 pruebas de la app (16 nuevas), 138 de Functions (5
nuevas) y reglas de Compras, roles de tabla, roles de módulo y aislamiento
por empresa en el emulador (28, 1 nueva), sin errores de análisis. El
modelo generado se abrió con openpyxl: hoja `Listas` oculta y las 12
validaciones en su lugar. **No verificado en dispositivo:** Web
estrecho/amplio, Android e iOS (diálogo de carga con avisos, tarjeta de
Admin, descarga del PDF con `Printing.sharePdf`), ni la apertura del modelo
en Excel de escritorio y Google Sheets.

## Planillas de Pago se le quitaba y ponía al gerente en el Home — 30 sep 2026 (Claude)

Caso: el gerente (Empresa 001) veía aparecer y desaparecer Planillas de
Pago en el Home. Codex encontró que TBL_APPS de la Empresa 001 marcaba
Planillas como apagado y se quedó sin tokens a mitad del arreglo (sus
cambios no llegaron a `main`). Causas y arreglos:

- **Cada pantalla decidía distinto.** Una empresa puede tener varios
  documentos del mismo módulo en TBL_APPS (el canónico
  `{empresa}_planillaspagodashboard` y viejos con `planillas` o
  `planillaspago`). Admin y la entrada al módulo leían el canónico; el Home
  y Talento Humano lo ocultaban si **cualquiera** decía apagado. Con un
  duplicado viejo apagado, Admin mostraba Planillas prendido y el Home lo
  quitaba. Ahora todos usan la misma regla (`lib/core/apps_empresa.dart`):
  manda el canónico; si no hay, el último que se tocó; sin fechas, prendido
  si alguno lo está.
- **Admin solo prendía uno.** El interruptor de Configuración de apps ahora
  escribe todos los documentos del módulo en la empresa, así no quedan
  duplicados contradiciéndose.
- **El Home pintaba antes de saber.** Mostraba todos los módulos del usuario
  y, al llegar TBL_APPS, quitaba los apagados (el "se quita y se pone").
  Ahora espera la primera respuesta con el esqueleto de carga; si la
  consulta falla, sigue como antes.
- **Registrar módulos faltantes los apagaba.** Un módulo sin documento está
  prendido; registrarlo apagado se lo quitaba a quien ya lo usaba. Ahora
  queda prendido si alguien de la empresa lo tiene asignado y apagado solo
  si nadie lo usa.
- **La carga de personal de Talento Humano reescribía los módulos.**
  Volvía a prender Tareas y ponía cada módulo como dijera la hoja APPS del
  Excel (descargado quizá días antes). Ahora solo crea los módulos que la
  empresa no tiene; prender o apagar es de Admin.

Qué hacer en producción, después de desplegar el Hosting: en Admin ›
Configuración de apps de la Empresa 001, dejar Planillas de Pago prendido
(si aparece apagado, prenderlo: el interruptor corrige también los
duplicados viejos).

Pruebas: 1.412 de la app (7 nuevas), sin errores de análisis.

## Alcance de maestros de configuración y cargas de Compras — 30 sep 2026 (Codex)

El usuario precisó que el personal de Compras crea y carga proveedores,
marcas y productos en Compras. Se trasladó la importación Excel de
proveedores y productos desde Admin a una entrada del módulo de Compras;
Marcas conserva su editor en ese módulo. Admin mantiene la configuración de
requisitos documentales y plazos, así como los autorizados y el buzón de
Tokens DIAN, filtros de Correo y la copia controlada entre empresas. Desde el
panel DIAN se enlaza la asignación de acceso y rol en Apps, roles y permisos,
sin duplicar el editor de roles; la conexión del buzón se edita en Admin y el
módulo muestra su estado y permite la sincronización operativa. El editor de
filtros de Correo pasó a Admin y la pestaña operativa de Correo quedó en
Resumen y Bandeja. `firestore.rules` exige Admin de la empresa o Desarrollo
para escribir filtros; la lectura se mantiene dentro de la empresa.
`AGENTS.md` y
`CLAUDE.md` distinguen maestros operativos de configuraciones reservadas.
Una restricción exclusiva de Desarrollo se aplicará por parámetro técnico
concreto, también en servidor/reglas, sin bloquear toda la pestaña ni las
cargas diarias de Compras.

Validación: 159 pruebas dirigidas de Compras/Admin y una prueba de la nueva
pantalla aprobadas; también pasaron 16 pruebas de Correo/permisos/Compras y
22 dirigidas de Tokens DIAN/Correo/Compras. Los archivos nuevos y los paneles
movidos no tienen errores de análisis; la compilación Web final pasó. La
prueba de reglas de Correo quedó escrita,
pero el emulador Firestore no inició en Windows por un error Java/Netty de
conexión loopback; se requiere ejecutarla en un entorno donde arranque.

---

## Revisión final de Admin y contrato multiplataforma — 30 sep 2026 (Codex ↔ Claude)

`AGENTS.md` y `CLAUDE.md` exigen cobertura Web adaptable, Android e iOS,
validación por ancho lógico (390/768/1024/1366 px y texto ampliado), y
registro de maestros por empresa en el catálogo de Admin. La decisión
posterior del 30 sep sitúa la edición operativa dentro de cada módulo y
centraliza en Admin la configuración administrativa y la copia entre
empresas. El contrato conserva UX diferenciada para Web y móvil y
lógica/permisos compartidos. Como excepción de esta sesión,
el usuario hará Git personalmente; Codex no ejecutará add, commit ni push.

**Perfiles generales:** se mantienen en Admin → Apps, roles y permisos como
plantillas opcionales para conceder apps; se quitó el acceso duplicado del
menú Usuarios. Su edición o inactivación no revoca automáticamente apps ya
concedidas, por lo que se corrigió el texto que decía lo contrario. El
repositorio rechaza asignación a otra empresa, perfiles inactivos y personas
inhabilitadas, además de edición cruzada o creación que pise un perfil
existente. Desarrollo, Gerencia y administradores históricos son casos cuyos
`roleKey` aún intervienen en autorización. Se impide desactivarlos sin migrar
antes esa dependencia. La raíz del perfil de Gerencia deja de conceder nivel
en empresa secundaria, tanto en el cliente como en la regla de Visitas.

**Validación ejecutada:** la suite Flutter completa pasó con 1337 pruebas
antes de los últimos ajustes de alcance de perfil y navegación; después
pasaron 181 pruebas de Admin y las pruebas dirigidas de empresa secundaria,
perfiles y permisos. El emulador de Firestore volvió a fallar antes de ejecutar
`visitas_gerencia.rules.js`: Java/Netty no establece conexión loopback.
`flutter build web --no-pub` terminó correctamente para JavaScript; el
diagnóstico opcional de WebAssembly advierte incompatibilidades de paquetes
terceros (`desktop_drop`, `flutter_secure_storage_web`, `pdfx`, entre otros).
Android tiene el SDK en una ruta con espacios y `flutter doctor` lo marca
incompatible con NDK. Además, `flutter build apk --debug --no-pub` falló al
iniciar Gradle por el mismo error de Java: `Unable to establish loopback
connection`. iOS no se puede compilar en este host Windows; las
pruebas de widgets con `TargetPlatform.iOS` y Android solo validan layout y
navegación, no los binarios nativos. Además pasó la navegación con texto
ampliado en 1024 px.

**Pendientes reales para Claude y la próxima integración:** los maestros de
productos, proveedores y marcas de Compras aún se editan allí; auditar los
maestros específicos de Facturación, Nutrición, Rutas y demás módulos y
llevar sus editores canónicos a Admin sin migrar datos en producción por
defecto. Ejecutar las reglas en un emulador funcional y probar Android/iOS
en toolchains adecuados. Este checkout sigue seis commits detrás de
`origin/main`; el `index.lock` persistente impide el pull. La rama remota
incluye cambios amplios en Admin, Facturación y Gerencia que deben
integrarse y volver a probarse antes de afirmar cierre global o publicar.

---

## Gestión interna unificada por empresa — 29 sep 2026 (Codex ↔ Claude)

Admin muestra una sola entrada **Gestión interna** con navegación propia para
**Catálogos y bodegas, Grupos, Membresía y Multiempresa**. En Web usa panel
lateral; en móvil, selector compacto. La ficha de empresa y los catálogos
compartidos quedan en Catálogos; la asignación de empresas y grupos a personas
queda en Membresía. Se retiraron las entradas duplicadas de Membresía y
Multiempresa de la gestión de usuarios, y el segundo editor de grupos que
estaba dentro de Membresía.

**Fuente de verdad:** bodegas siguen en `TBL_COMPRAS_BODEGAS`, grupos en
`TBL_COMPRAS_GRUPOS`, centros en `TBL_CENTROS_COSTOS`, áreas en `TBL_AREAS`,
cargos en `TBL_CARGOS` y la membresía/asignación de grupos en `TBL_USUARIOS`.
Las lecturas y escrituras nuevas se limitan a la empresa activa; editar un
grupo o bodega de otra empresa se rechaza también en el repositorio. Compras
y Talento Humano siguen leyendo las mismas colecciones; no se crearon copias.

Las bodegas históricas de `TBL_EMPRESAS.bodegas` y del catálogo de respaldo
de Compras se muestran como **pendientes de incorporar**, sin reescribir
producción ni sobrescribir bodegas existentes. El administrador puede
incorporarlas una por una a la colección canónica. Las sugerencias omiten
nombres ya presentes, incluso si la bodega canónica está inactiva. Recepción
y Abastecimiento conservan visibles las bodegas históricas aún no incorporadas
durante la transición, pero una bodega canónica inactiva ya no reaparece por
el respaldo histórico del mismo nombre.

Validación: 169 pruebas de Admin y 14 de integración de Compras aprobadas,
incluida la importación parcial, navegación Web/móvil, grupos, bodegas,
empresa secundaria y vista previa histórica. El análisis de los
archivos nuevos y del repositorio no mostró errores; conserva avisos de lint
preexistentes. Pendiente de validar en emulador las reglas Firestore porque
Java no logra iniciar la conexión loopback en este equipo.
`origin/main` avanzó seis commits durante esta sesión; la sincronización,
commit y push quedan pendientes porque `.git/index.lock` sigue bloqueando Git.
La revisión automática rechazó retirar ese archivo, así que no se forzó la
operación ni se creó una rama.

**Para Claude en una siguiente revisión:** auditar los catálogos específicos
de Facturación, Nutrición, Rutas y demás módulos para decidir cuáles son
compartidos por empresa y cuáles deben conservar su editor operativo. Los
catálogos de productos, proveedores y marcas de Compras todavía tienen su
gestión en Compras; no se han trasladado ni sincronizado automáticamente.
Revisar con el emulador las reglas de escritura de bodegas y grupos para
Admin y el aislamiento al leer `TBL_EMPRESAS.bodegas` antes de desplegar.

---

## Regla permanente para módulos y conversaciones — 29 sep 2026

Por indicación del usuario, `AGENTS.md` define el contrato obligatorio para
todo módulo nuevo: catálogo y empresa activa, centro de Apps/roles/permisos,
creador y sincronización cuando haya niveles, revocación coherente en todos
los editores, reglas/backend, pruebas y experiencia Web/Móvil diferenciada.
`CLAUDE.md` remite a ese contrato. En cada conversación de este repositorio
se trabaja sobre `main`; solo Codex hace Git. La comunicación al usuario se
reduce al resultado final, validación y pendientes reales, con avisos
intermedios solo cuando un bloqueo lo exige. Codex y Claude registran aquí
su coordinación técnica.

---

## Auditoría de homogeneidad en Admin — 29 sep 2026 (Codex ↔ Claude)

Se revisó **Admin → Apps, roles y permisos** contra la lista completa de
módulos de la matriz. Tareas, Talento Humano, Biblioteca Documental,
Planillas de Pago, Nutrición, Compras, Correo y Correspondencia, Tokens DIAN,
Interventoría, Rutas y Visitas tienen creador, asignación individual y nivel
operativo dentro de su tarjeta. Admin, Gerencia y Gestión de Correspondencia
figuran como acceso a la app, sin una jerarquía de roles propia que crear.

**Corrección:** la operación masiva de dar o quitar acceso ahora usa el mismo
repositorio de roles que la operación individual para Tokens DIAN, Talento
Humano y Nutrición. Así, quitar acceso elimina su asignación y volver a darlo
parte de Consulta; no reaparece un nivel histórico. Si ya tenía acceso, la
acción masiva conserva su nivel. El editor general de módulos por usuario y
el editor del catálogo aplican esos cambios en la misma transacción que las
apps, incluso cuando la persona pertenece a varias empresas. Las etiquetas
de sus niveles en la matriz se toman de la configuración del creador, para
evitar dos catálogos divergentes.

La validación dirigida de Admin pasó **46/46** (incluye revocación,
reactivación y preservación de niveles entre empresas). El análisis de los
archivos modificados no muestra errores nuevos. Las reglas Firestore de las
entregas previas aún no se han podido probar en este equipo: el emulador falla
al iniciar por Java. Tampoco hay commit ni push porque persiste el
`.git/index.lock` cuya retirada rechazó la revisión automática.

**Brecha restante:** Facturación ofrece Facturación, Establecimiento y Visor
como roles internos y permite asignarlos en la matriz, pero no tiene creador
de roles configurables ni sincronización de definiciones en su tarjeta. La
pantalla Admin conserva además otro editor de `rolFac` fuera del centro de
Apps, roles y permisos. Por eso **no se puede afirmar que todos los módulos
con niveles cumplen todavía la misma experiencia**. Una integración futura
debe respetar `establecimientoFacId` y el flujo de permisos de Facturación;
no conviene fabricar un rol genérico sin esa relación. Este pendiente se
coordina con Claude solo por este archivo.

---

## Nutrición: roles configurables — 29 sep 2026 (Codex ↔ Claude)

**En integración y validación.** Admin → Apps, roles y permisos incluye
Nutrición en el creador común. Las definiciones viven en `TBL_ROLES` y la
asignación efectiva en `TBL_NUTRICION_ROLES/{empresaId}_{userDocId}`. Los
niveles son Consulta (reportes), Atención clínica (atención, pacientes,
firmas), Menús e ingredientes (menú, ítems), Coordinación (ambos flujos) y
Administrador (ambos flujos y gestión de roles). Activar el módulo desde la
matriz asigna Consulta; retirarlo elimina la app y su fila solo en la empresa
activa. El acceso anterior basado solo en la app se conserva como
Administrador hasta ejecutar la consolidación manual, que no sobrescribe
filas existentes.

`lib/nutricion/nutricion_roles.dart` concentra capacidades y pestañas; para
añadir un nivel o sección futura se actualizan allí, la configuración del
creador, y las reglas Firestore. La UI instancia únicamente las secciones
permitidas y conserva su estado al cambiar de pestaña. El seed de dietas, plantillas e ingredientes se
ejecuta solo para niveles que gestionan menús. Las reglas restringen lectura
de datos nutricionales a personas con acceso y separan escrituras clínicas
de menús. `TBL_CITAS_NUTRICION` mantiene lectura por empresa para no romper
el calendario compartido; su escritura queda en capacidad clínica.

**Para Claude:** revisar consultas directas a datos de Nutrición desde otros
módulos y los archivos de Firebase Storage usados por firmas/evidencias. Las
reglas de Storage deben reflejar la misma capacidad clínica. Si una colección
compartida requiere otro lector, resolverlo de forma explícita. No desplegar
las reglas nuevas hasta validar el conjunto con el emulador Firestore. No se
han ejecutado cambios de datos ni consolidación en producción. Las pruebas
dirigidas Flutter pasaron **29/29**, la suite completa **1.322/1.322** y la
compilación Web terminó bien. El análisis dirigido no mostró errores (solo
avisos preexistentes). El emulador Firestore volvió a fallar antes de cargar
las reglas por `Unable to establish loopback connection` de Java; quedan sin
verificar las pruebas de reglas. `main` conserva un `.git/index.lock` antiguo:
la revisión automática impidió retirarlo y siguen pendientes pull, commit y
push.

---

## Talento Humano: roles configurables — 29 sep 2026 (Codex ↔ Claude)

**En integración y validación.** Admin → Apps, roles y permisos ahora incluye
creador, asignación individual y cinco niveles de Talento Humano: Consulta,
Solicitante, Reclutamiento, Gestión de personal y Administrador. Las
definiciones se guardan en `TBL_ROLES` y el nivel efectivo en
`TBL_TALENTO_HUMANO_ROLES/{empresaId}_{userDocId}`. La ficha por empresa
conserva el vínculo del rol creado. Activar la app desde la matriz asigna
Consulta; retirarla elimina la asignación y la app solo en esa empresa.

La navegación Web/Móvil mantiene su composición actual y filtra herramientas
según el nivel: Solicitante usa Requerimientos; Reclutamiento incorpora
selección y hojas de vida; Gestión de personal incorpora estructura,
documentos, disciplina y comunicaciones; Administrador añade Accesos del
personal y la administración de roles. Requerimientos reutiliza las
capacidades existentes de visor, solicitante, reclutador y responsable.
La tabla canónica manda sobre los campos históricos. Mientras no exista
asignación, una persona que ya tenía la app conserva Administrador, para no
romper el acceso anterior. La consolidación manual materializa ese nivel sin
alterar otras empresas ni sobrescribir asignaciones existentes.

Las reglas Firestore validan definición/asignación y aplican los niveles a
`TBL_TH_REQUERIMIENTOS_PERSONAL`, `TBL_LLAMADOS_ATENCION` y
`TBL_HISTORIAL_LLAMADOS_ATENCION`. El historial disciplinario se consulta
también con `empresaId` para no mezclar casos. **Pendiente con Claude:** los
flujos que escriben colecciones compartidas (`TBL_USUARIOS`, estructura,
catálogos, documentos y almacenamiento) siguen sujetos a reglas generales;
revisar sus operaciones y cerrar las escrituras por capacidad sin romper la
hoja de vida propia ni otros módulos. Hasta entonces los roles restringen
navegación y los tres conjuntos específicos citados, pero no constituyen
una frontera completa para todos los datos de Talento Humano.

No se ejecutó la consolidación sobre producción ni se desplegaron reglas o
Web. Las pruebas dirigidas Flutter pasaron **51/51** y la suite completa
**1.316/1.316**. El análisis dirigido no encontró errores nuevos (1
advertencia y 6 avisos existentes en Admin); `node --check` y
`git diff --check` pasaron. El emulador Firestore no arrancó en esta sesión
(`Unable to establish loopback connection` de Java), así que las reglas
nuevas requieren verificación antes del despliegue. `main` sigue con un
`.git/index.lock` antiguo que la revisión automática impide retirar; pull,
commit y push están pendientes. La compilación Web finalizó correctamente con
`flutter build web --no-pub
--no-wasm-dry-run`.

---

## Tokens DIAN: roles y NIT de la empresa activa — 29 sep 2026 (Codex)

**Estado: IMPLEMENTADO Y VERIFICADO EN CÓDIGO.** Coordinación con Claude por
esta bitácora. Admin → Apps, roles y permisos incorpora Tokens DIAN en el
mismo creador y matriz de niveles de los módulos con tabla. La asignación
canónica vive en `TBL_DIAN_TOKEN_ROLES/{empresaId}_{userDocId}` y los roles
creados usan `TBL_ROLES` con `moduleId: tokensdiandashboard`. Los niveles son
**Consulta** (ver estado y metadatos), **Operador** (abrir enlace y sincronizar
buzón) y **Administrador** (configurar enlaces y conexión del buzón). Crear un
rol no lo asigna automáticamente; editarlo sincroniza sus miembros e
inactivarlo los deja en Consulta. Retirar el acceso individual también retira
la app Tokens DIAN de esa empresa. El panel anterior de Tokens DIAN conserva
la gestión de enlaces y muestra las personas como referencia, sin un segundo
interruptor de acceso.

La función de listado devuelve el nombre y NIT registrados en
`TBL_EMPRESAS/{empresaId}` de la **empresa activa**. Web y móvil muestran
ese contexto y el nivel efectivo controla las acciones; el NIT del enlace
DIAN permanece identificado por separado. Esto vincula el contexto de la
empresa con Organización. Hoy ese registro contiene el número NIT, **no un
archivo PDF del RUT**; cualquier
adjunto RUT requerirá un modelo y flujo propios si se solicita después.

La autorización de las funciones exige identidad autenticada, membresía
habilitada, empresa y app. La tabla canónica manda; el acceso histórico por
app queda temporalmente como Operador. La acción manual **Consolidar accesos
anteriores** materializa ese nivel para las personas existentes con app y
empresa, sin conceder acceso nuevo ni sobrescribir niveles canónicos. No se
ha ejecutado una migración sobre datos de producción. Las reglas Firestore
validan la tabla nueva y siguen cerrando al cliente los documentos cifrados
de tokens y configuración. Se eliminó la posibilidad de usar un `userId`
enviado por el cliente como identidad para estas funciones.

Para Claude: revisar el contrato de `TBL_EMPRESAS.nit` y la pertenencia por
empresa antes de cualquier cambio de esquema; mantener el nivel canónico y
la comprobación en servidor en futuras funciones DIAN. El despliegue de
Functions, reglas y Web sigue pendiente de coordinación operativa.

Validación: pruebas dirigidas Flutter **34/34**, Functions **15/15**,
suite Functions **107/107**, reglas dirigidas **8/8** y suite de reglas
**99 aprobadas, 2 omitidas, 0 fallidas**. Compilación TypeScript y Web
correctas; suite Flutter **1.310/1.310**. Análisis dirigido sin errores
(1 advertencia y 6 avisos preexistentes en Admin). El commit y push a `main`
esperan que se libere un `.git/index.lock` antiguo: la revisión automática
rechazó retirarlo desde esta sesión.

---
---

## Integración de cambios concurrentes en `main` — 30 sep 2026 (Codex)

Se conservaron los niveles de Tokens DIAN, Talento Humano y Nutrición junto
con los de Facturación y Gerencia en Admin y en `firestore.rules`. La nueva
pestaña de Diagnósticos de Nutrición quedó incluida en la navegación de todos
los niveles que pueden consultar, sin saltar el filtro de pestañas por rol.
La bitácora mantiene los cambios de ambas sesiones y `AGENTS.md`/`CLAUDE.md`
usan la decisión más reciente documentada sobre edición de maestros en cada
módulo y copia entre empresas desde Admin.

Validación de la integración: 1.405 pruebas Flutter y 133 de Functions
aprobadas; `flutter build web --no-pub` correcto. El análisis dirigido no
detectó errores; persisten 9 avisos de estilo/elementos sin uso. La
compilación Android y la de iOS no se pudieron verificar en esta integración.

---

## Admin › Maestros por módulo: copiar maestros a otras empresas — 30 sep 2026 (Claude)

Pedido: todo lo de "mover entre empresas" que estaba dentro de los módulos
pasa a Admin, para copiar los maestros y la configuración de un módulo a
otras empresas; los módulos no necesitan saber que hay otras empresas.
Decisiones: todos los maestros (no solo documentos: configuración,
establecimientos…); **agregar lo que falta**; cada módulo sigue editando sus
maestros y Admin copia; las pestañas Compras, Correo, Tokens DIAN y WhatsApp
se agrupan en una sola.

### Cómo queda
- Nueva pestaña **Admin › Maestros por módulo** (reemplaza Compras, Correo,
  Tokens DIAN y WhatsApp). Arriba se elige el módulo (chips en web, lista
  en móvil). Donde había panel propio (Compras, Correo, Tokens DIAN,
  WhatsApp) sigue igual en "Configuración".
- **Copiar a otras empresas**: se eligen las empresas destino (solo donde se
  es Administración; las demás se ven pero no se eligen) y qué maestros
  (todos por defecto) → "Ver qué se copiaría" (por empresa y maestro:
  nuevos, ya estaban, sin código ni nombre, campos por completar, ejemplos)
  → "Copiar lo que falta" con confirmación.
- Qué se copia:
  - Compras: configuración, grupos, bodegas, marcas, proveedores,
    productos, fichas técnicas y requisitos documentales.
  - Interventoría: configuración y reglas de subsanación.
  - Visitas: formatos y ubicaciones de establecimientos.
  - Facturación: obligaciones y qué documentos no aplican por
    establecimiento (el mes y las fechas límite son de cada empresa).
  - Rutas: configuración, movilidad (sin las cédulas de alerta),
    establecimientos, rutas, placas y horarios.
  - Nutrición: ingredientes, patologías, dietas, plantillas de menú y menús.
  - Correspondencia: tipos documentales.
  - Biblioteca documental: cada documento con su versión vigente y su
    archivo (duplicado en Storage).
  - Talento Humano: plantillas de documentos (con su Word) y valores por
    defecto de Zeus.
  - No se copian personas ni lo que es de cada empresa: grupos de Visitas,
    beneficiarios y logos de Planillas, cuentas de Correo, tokens DIAN,
    WhatsApp.

### Dónde se edita cada cosa (confirmado por el usuario, 30 sep 2026)
Cada módulo crea y edita sus maestros en su módulo; en Compras,
proveedores, productos, marcas y fichas técnicas los maneja el equipo de
Compras uno a uno, y no es un pendiente de Admin. Admin conserva las cargas
por Excel, bodegas y grupos, Correo, Tokens DIAN, WhatsApp y la copia entre
empresas. Quedó como regla 6 en `CLAUDE.md` y en `AGENTS.md`.

### Reglas de la copia (`functions/src/maestros.ts`, `adminSincronizarMaestros`)
- Solo crea lo que el destino no tiene, comparando por código o nombre (sin
  tildes ni mayúsculas); nunca cambia lo que ya existe (`create`, que falla
  si el documento apareció entre la vista previa y la copia). Se puede
  repetir.
- Configuración: completa solo los campos vacíos, por dentro de los mapas;
  las listas que el destino ya tiene se respetan.
- Las referencias se traducen al destino: el producto a su marca, la ficha
  a su producto, proveedor y marca, el formato a su área, la ubicación a su
  centro. Áreas, cargos y centros se buscan por nombre (centros también por
  código); si el destino no los tiene, la vista previa lo avisa y remite a
  Usuarios › Multiempresa para enviarlos (el id queda como el que crea ese
  envío, así se enlazan al enviarlos). En Interventoría avisa los cargos de
  las reglas que el destino no tiene (antes lo avisaba el diálogo del
  módulo).
- Marcas: si el código (MRC-0003) ya lo usa otra marca en el destino, se le
  da el siguiente libre y se ajusta el consecutivo del destino.
- Exige ser Administración en la empresa activa **y** en cada destino. Queda
  en Logs de las dos: "Maestros: copiados a otras empresas" y "Maestros:
  recibidos de otra empresa".

### Sale de los módulos
- Biblioteca documental: el botón "COPIAR A OTRA EMPRESA" y su servicio.
- Interventoría: "Copiar a otras empresas" del maestro de subsanaciones
  (reglas y configuración) y sus métodos del servicio.

### Corregido de paso
- **Limpieza › Compras** borraba la parametrización de requisitos
  documentales (`TBL_COMPRAS_REQ_DOCUMENTOS`) como si fuera un registro de
  prueba. Ahora es un maestro: solo se borra si se pide incluir maestros.
- **Nutrición:** importar dietas o patologías desde Excel usaba el código
  como id, así que la misma dieta en otra empresa se sobrescribía (y se le
  cambiaba la empresa). Ahora se usa la de la empresa o
  `{empresa}_{código}`.
- Los textos que mandaban a "Admin > WhatsApp" o "Admin → Tokens DIAN"
  apuntan a la nueva pestaña.

Pruebas: 1.367 de la app (5 nuevas de Maestros por módulo; salen las 5 del
diálogo de copia de Interventoría), 130 de Functions (15 nuevas).
Despliegue: `firebase deploy --only functions,hosting` (sin cambios de
reglas ni índices).

## Diagnósticos pasa de Admin a Nutrición — 29 sep 2026 (Claude)

Admin › Diagnósticos no revisaba el sistema: cargaba el catálogo de
diagnósticos que usa solo Nutrición. Ahora es la pestaña **Nutrición ›
Diagnósticos** (`lib/nutricion/diagnosticos/nutricion_diagnosticos_screen.dart`).

- Explica qué usa cada búsqueda: los **nutricionales** salen siempre del
  catálogo; los **médicos** (CIE-11) se buscan primero en línea en la OMS y
  el catálogo es el respaldo. Muestra cuántos hay cargados o que se usa la
  plantilla de la app.
- **Consultar**: médicos o nutricionales, buscador por código, nombre o
  detalle, de a 20.
- **Actualizar desde Excel** (solo Admin o Desarrollo; el resto consulta):
  descargar la plantilla, elegir el archivo e importar.
- **Corregido:** la importación iba en un solo lote y Firestore no acepta
  más de 500 escrituras: la plantilla que trae la app (unos 3.600
  diagnósticos médicos) nunca se podía importar. Ahora va de a 400.
- El catálogo es uno para todas las empresas: ya no guarda un `empresaId`
  (que hacía creer que era de una), sino desde qué empresa y quién lo
  actualizó.
- **Reglas:** `TBL_EVALUACIONES_DIAGNOSTICAS` (evaluaciones del paciente,
  datos de salud) seguía en la regla general, legible desde cualquier
  empresa; ahora queda en su empresa como el resto de Nutrición. También
  entra en Limpieza › Nutrición.
- El doble de Firestore de las pruebas ahora rechaza lotes de más de 500,
  como el real.
- Pruebas: 1.367 de la app, 115 de Functions, 109 de reglas (2 omitidas
  desde antes). Despliegue: `firebase deploy --only
  firestore:rules,functions,hosting`.

## Admin › Limpieza por módulo — 29 sep 2026 (Claude)

Pedido: enfocar Limpieza a cada módulo y a su necesidad; estamos en pruebas
y hay muchos datos de prueba en casi todos. Decisiones: las dos cosas
(cerrar lo real sin borrar y borrar lo de prueba) y los reinicios totales
aparte, con doble confirmación.

### Cómo queda
- Arriba se elige el **módulo** (chips en web, lista en móvil): Tareas y
  notificaciones, Interventoría, Visitas, Facturación, Compras, Rutas,
  Nutrición, Correspondencia, Correo, Biblioteca documental, Planillas de
  pago, Talento Humano, Tokens DIAN y WhatsApp. Cada uno muestra solo lo
  suyo.
- **Cerrar sin borrar** (Tareas, Interventoría, Facturación): finaliza las
  tareas abiertas por fecha de corte y da por leídas sus notificaciones;
  Interventoría además da por subsanados sus hallazgos y Facturación cierra
  sus observaciones. Nuevo: **tareas creadas a mano** (sin marca de ningún
  módulo). Visitas, Compras y Correspondencia no lo tienen: cerrar solo su
  tarea dejaría el origen (visita, recepción, expediente) a medias.
- **Borrar datos de prueba** (todos): periodo (todo, antes de, desde, entre
  fechas) → "Ver qué se borraría" con el conteo por colección → escribir
  BORRAR. Borra los registros del módulo, **sus tareas y sus
  notificaciones**. Maestros y configuración (productos, proveedores,
  formatos, rutas, dietas, consecutivos de radicado…) solo con el
  interruptor "Incluir maestros". Los pacientes se borran con su historial.
  Registros sin fecha: con un periodo no se tocan (se avisa cuántos); con
  "Todo" sí.
- Función `adminLimpiezaModulo` (`functions/src/limpieza.ts`): solo Admin de
  la empresa, solo documentos con `empresaId` de la empresa activa (los
  consecutivos, por el prefijo del id). Nunca toca personas, empresas,
  roles, credenciales, áreas, cargos ni centros. Queda en Logs.
- Los **adjuntos** (fotos, PDF en Storage) no se borran.

### Reinicio total (aparte, al final)
Todas las tareas · Datos de las personas en la empresa · Estructura
organizacional · Catálogos. Cada uno cuenta antes y pide escribir BORRAR.
- **Corregido (grave):** "Purgar estructura" borraba la estructura
  organizacional de **todas las empresas**, aunque decía "para esta
  empresa". Ahora solo la de la empresa activa: quien está también en otras
  conserva la de ellas.
- "Datos de las personas" ya no incluye a quien lo ejecuta (perdía su
  acceso a Admin a mitad) y su texto dice lo que hace de verdad: quita a las
  personas de la empresa (área, cargo, centro, jefe y módulos) para
  recargar el Excel.
- Catálogos y estructura ahora quedan en Logs. "Eliminar todas las tareas"
  pasó de Migraciones a Reinicio total.

### Pruebas
- Nuevas: `functions/test/limpieza.test.js` (5; entre ellas que el catálogo
  nunca toque personas, roles ni credenciales y que cada colección sea de un
  solo módulo), `test/admin/module_cleanup_test.dart` (6; entre ellas que la
  lista de módulos de la app sea la del servidor) y 1 en el cierre.
- Totales: 1.365 de la app, 115 de Functions, 108 de reglas (sin cambios).
  `flutter analyze` sin errores.

### Despliegue
`firebase deploy --only functions,hosting`.

## Admin › Seguridad: clave inicial y registro de accesos — 29 sep 2026 (Claude)

Admin queda para Daniel y Oscar. Pedido: dejar de generar claves temporales
una por una, registrar a cada persona nueva y ver con claridad quién entra,
quién no y desde qué equipo.

### Clave inicial 123456
- **Botón "Asignar 123456 a N"** en Seguridad, para todos los que **nunca
  han iniciado sesión** en la empresa activa. También por persona (menú de
  la tarjeta). Función `securityAdminAssignInitialPassword`.
- "Nunca ha iniciado sesión" (`functions/src/ingresos.ts`): sin ningún
  ingreso registrado **y** sin clave propia (sin credencial, o con una
  temporal o inicial aún sin cambiar). A quien ya entró o ya puso su clave
  no se le toca: a esos se les sigue generando la contraseña temporal.
- La clave se guarda **cifrada** en `TBL_AUTH_CREDENTIALS` (nunca en texto)
  y la persona queda con cambio obligatorio: al entrar crea su contraseña
  (8 o más caracteres) y sus preguntas de seguridad. Se excluyen
  inhabilitados, Desarrollo y quien la ejecuta. Queda en la actividad.
- El servidor ahora marca cada ingreso (`ultimoIngresoSeguroAt`), así
  "nunca ha entrado" no depende de que la app alcance a registrarlo.

### Personas nuevas
- Trigger `securityRegistrarUsuarioNuevo`: toda persona creada (Admin,
  Talento Humano o carga) deja un registro **"Persona nueva"** en la
  actividad de Seguridad de sus empresas, con quién la creó (`creadoPor`,
  que ahora escribe el alta de Admin/TH). Si llega sin clave o con 123456 en
  texto, la clave queda cifrada y se borra el texto.
- Corregido: activar de nuevo a alguien que ya entró (Talento Humano) o
  pasar por "primera vez" le volvía a poner 123456 y a exigir el cambio,
  aunque ya tuviera su propia clave (y esa 123456 no le servía). Ahora la
  conserva y el mensaje lo dice.

### Registro de accesos
- La app guarda en cada ingreso **el equipo**: computador, celular o
  tablet; marca y modelo del celular (Samsung SM-A515F, iPhone 15 Pro…),
  sistema (Android 14, iOS 17.5, Windows 11…) y si fue por la app o por
  navegador (cuál). En la app instalada con `device_info_plus` (dependencia
  nueva); en el navegador por el user agent y, en Chrome/Edge, las "client
  hints", que traen el modelo que el user agent ya no trae. Safari no dice
  el modelo del iPhone: sale "iPhone".
- Seguridad muestra:
  - **Accesos a la app**: Nunca han entrado · Ya entraron · Desde computador
    · Desde celular (cada tarjeta filtra la lista) y los celulares por marca.
  - En cada persona: último ingreso ("Hoy 10:32", "Hace 3 días") con su
    equipo, "Nunca ha iniciado sesión", "Clave inicial 123456" pendiente y
    "Nuevo" (creada hace 30 días o menos).
  - **Registro de ingresos** de los últimos 30 días: quién, cuándo, cómo
    (contraseña, sesión guardada, huella/rostro) y desde qué equipo, con
    filtro por tipo y de a 20.
  - **Actividad administrativa** con nombres (no cédulas), las acciones
    nuevas, de a 20 y ordenada por el servidor.
- Los ingresos anteriores solo guardaban "web/android": salen como "sin
  detalle" hasta el próximo ingreso de cada persona.

### Servidor (reglas)
- `TBL_LOGIN_SESIONES` sale de la regla general: cada quien agrega su
  propio ingreso; lo lee Admin de esa empresa o Desarrollo; nadie lo edita
  ni lo borra. Antes cualquiera veía y borraba los ingresos de todas las
  empresas.
- Índice nuevo `TBL_AUTH_ADMIN_AUDIT` (`empresaId` + `createdAt`
  descendente). Sin él, la actividad se ve como antes.

### Pruebas
- Nuevas: `test/services/device_descriptor_test.dart` (11),
  `test/admin/security_access_test.dart` (8),
  `functions/test/ingresos.test.js` (6) y
  `functions/test/login_sesiones.rules.js` (3).
- Totales: 1.358 de la app, 110 de Functions, 108 de reglas (2 omitidas
  desde antes). `flutter analyze` sin errores. `flutter build web` compila.

### Despliegue
`firebase deploy --only firestore:rules,firestore:indexes,functions,hosting`.
La app Android/iOS toma la dependencia nueva en su próxima compilación
(`flutter pub get`; en iOS, `pod install`).

## Admin: Migraciones y Logs revisados — 29 sep 2026 (Claude)

Se revisó para qué sirve cada herramienta hoy. Lo que ya no cumple un papel
se retiró; lo demás se corrigió.

### Migraciones (Usuarios → Migraciones de usuarios)
- **Centro de costos: se queda, corregida.** Asigna un centro del catálogo a
  las personas elegidas.
  - Escribía el centro también en los datos generales aunque se migrara
    desde una empresa que no es la principal: le cambiaba el centro de su
    empresa principal. Ahora los datos generales solo se tocan si es su
    principal.
  - Escribía la ficha con `set(merge)`, que no entiende rutas con punto:
    creaba campos sueltos llamados `empresasDetalle.X.centroId` y **la ficha
    nunca cambiaba**. Ahora escribe la ficha de verdad y borra esos campos
    sueltos si quedaron.
  - Quien no es de la empresa activa no se toca. "Cancelar" al elegir el
    centro ya cancela (antes simulaba igual).
- **Tokens (fcmToken): retirada.** La app registra el token de cada
  dispositivo en `fcmTokens` al entrar y las notificaciones leen ese campo
  primero; copiar tokens viejos a `fcmToken` no le servía a nadie.
- **App IDs: retirada.** La app, las reglas y Admin ya aceptan el nombre
  corto y el largo de cada app, y Admin guarda el largo en cada cambio. El
  único lugar que comparaba exacto (Visitas en el calendario del inicio) ya
  compara por equivalencia.
- **Eliminar todas las tareas: se queda** como estaba (pide escribir BORRAR
  y queda en Logs). Sirve para reiniciar una empresa en prueba.
- El selector de personas muestra foto, nombre y cargo de la empresa activa,
  de a 20 por página; los elegidos se ven con nombre y foto, no con la
  cédula.

### Logs
- **Servidor:** `TBL_MIGRATIONS_LOGS` sale de la regla general. La lee Admin
  de esa empresa o Desarrollo; se agrega solo a nombre propio y con la hora
  del servidor; nadie la edita ni la borra. No se exige la empresa al crear:
  Multiempresa registra con la empresa de referencia de la persona (o `*`)
  en el mismo lote que su cambio, y negar el registro tumbaría el cambio.
- **Pantalla** (`lib/admin/admin_logs_panel.dart`): trae los 200 más
  recientes ordenados por el servidor (antes 200 sin orden, de los que
  mostraba 50), con persona (foto y nombre), fecha, la acción en español,
  conteos y Simulación/Ejecutado, de a 20 por página. Ya no vuelve a leer la
  bitácora en cada redibujo de Admin. Sin el índice nuevo desplegado, cae a
  la consulta de antes.
- Aclara que no registra el día a día (asignar roles, apps, editar
  personas).

### Pruebas
- Nuevas: `test/admin/admin_migrations_logs_test.dart` (8) y
  `functions/test/admin_logs.rules.js` (3).
- Totales: 1.339 de la app, 104 de Functions, 105 de reglas (2 omitidas
  desde antes). `flutter analyze` sin errores.

### Despliegue
`firebase deploy --only firestore:rules,firestore:indexes,hosting` (índice
nuevo `TBL_MIGRATIONS_LOGS`: `empresaId` + `createdAt` descendente).

## Admin: roles configurables de Gerencia — 29 sep 2026 (Claude)

Gerencia no tenía niveles: quien tenía la app veía todo. Decisiones del
usuario: el rol limita **áreas, empresas, pestañas y exportar**, y lo que se
agregue después; "solo su área" es **la de su ficha**; **sin rol no ve
nada**; los **Puntos** salen de lo que el rol deja ver.

### Qué hace
- **Rol por permisos** (como Tareas, no por niveles). Catálogo único en
  `lib/gerencia/gerencia_permisos.dart` (`kGerenciaPermisos`): Todas las
  áreas, Todas sus empresas, Pestaña Dashboard, Pestaña Puntos, Pestaña
  Interventoría y Exportar. Admin pinta un interruptor por permiso; un
  permiso nuevo se agrega ahí y queda **apagado** en los roles que ya
  existían hasta que Admin lo encienda.
- Definición en `TBL_ROLES/{empresa}_mod_gerencia_{nombre}` con
  `permissions`. Asignar escribe en la ficha de la empresa
  `rolGerenciaId/Nombre/Version` y `permisosGerencia`, y la app. Los nombres
  no chocan con la detección de Gerencia que hace Visitas por el rol
  general. Archivos: `management_module_role.dart`,
  `management_module_roles_repository.dart` y
  `management_module_roles_panel.dart`.
- **Sin rol no ve nada**, aunque tenga la app: el módulo dice "No tienes un
  rol de Gerencia en esta empresa" y no carga datos. Desarrollo entra con
  todo. No hay nivel individual: en la matriz el selector va de "Sin rol
  (no ve nada)" a los roles creados.
- **Alcance en el módulo** (`resolverAccesoGerencia`):
  - Manda el rol de la **empresa activa**: pestañas y exportar.
  - "Todas sus empresas" suma las otras empresas **solo si allí también
    tiene rol** de Gerencia; en cada una, el límite de áreas es el de su
    propio rol.
  - "Solo su área": tareas, gráficas, ranking de Puntos y hallazgos de
    Interventoría quedan en el área de su ficha (con el cargo de respaldo,
    como el resto de Gerencia), comparada por nombre normalizado. Sin área
    en la ficha no ve registros. Un aviso dice qué área está viendo.
  - Sin Exportar desaparecen los botones de PDF y Excel de Interventoría.
- Inactivar un rol deja a sus asignados sin acceso. Editar sincroniza.
- **Transición**: hoy todos los que tienen la app quedarían sin ver nada.
  El panel muestra cuántos son y, por rol, un botón **"Asignar a quienes
  tienen la app sin rol"** (con confirmación). Hay tres roles iniciales:
  Gerencia general (todo), Director de área (su área, todas las pestañas y
  exportar) y Consulta de indicadores (su área, solo Dashboard).

### Servidor (reglas)
- `TBL_ROLES` acepta `gerenciadashboard` (solo Admin de la empresa o
  Desarrollo).
- **El límite es del módulo, no del servidor**: Gerencia lee `TBL_TAREAS`,
  que sigue en la regla general, y los permisos viven en la ficha, que
  todavía escribe cualquiera (P0 de `TBL_USUARIOS`).

### Pruebas
- Nuevas: `test/gerencia/gerencia_permisos_test.dart` (11),
  `test/admin/management_module_roles_test.dart` (8) y
  `functions/test/gerencia.rules.js` (2).
- Totales: 1.331 de la app, 104 de Functions, 102 de reglas (2 omitidas
  desde antes). `flutter analyze` sin errores.

### Despliegue
`firebase deploy --only firestore:rules,hosting`. **Justo después de
publicar**, en cada empresa: Admin → Gerencia → "Crear roles iniciales" y
"Asignar a quienes tienen la app sin rol". Mientras tanto, quien tenga la
app sin rol no ve datos (las reglas nuevas hacen falta para guardar los
roles, por eso no se puede hacer antes).

### Quedan sin roles configurables
Tokens DIAN (lista de autorizados), Talento Humano, Nutrición y
Administración.

## Admin: roles configurables de Facturación — 29 sep 2026 (Claude)

Siguiente módulo del centro **Admin → Apps, roles y permisos**. Facturación
guarda el rol en la ficha (`empresasDetalle.{empresa}.rolFac`), como
Planillas, así que sigue ese patrón y no el de tabla.

### Qué hace
- Creador con los tres niveles que ya resuelve `resolveFacAccessMode`:
  **Visor** (consulta), **Establecimiento** (carga documentos de un solo
  establecimiento) y **Gestión de Facturación** (todo el módulo). Textos en
  `lib/facturacion/fac_role_access.dart`.
- Definición en `TBL_ROLES/{empresa}_mod_facturacion_{nombre}`. Asignar
  escribe en una transacción `rolFac` y su vínculo
  (`rolFacId/Nombre/Version`) en la ficha de la empresa, la raíz solo en la
  principal, y la app. Archivos: `billing_module_role.dart`,
  `billing_module_roles_repository.dart` y `billing_module_roles_panel.dart`.
- **El establecimiento.** Con Establecimiento se conserva el
  `establecimientoFacId` que tenga o se deduce de su centro de costo en
  esta empresa (por id, nombre o código del maestro), como hacía la matriz;
  con otro nivel se retira. Sin centro de costo el módulo sigue diciendo
  "Falta asignar el establecimiento" y se elige en la matriz, igual que
  antes.
- Inactivar deja **Visor** explícito; nivel individual desvincula; "Sin rol"
  deja `rolFac` vacío (consulta). Editar sincroniza a sus personas.
- Admin: panel en Facturación, selector de rol en la matriz y el nivel
  individual por el repositorio. Se quitó el camino viejo que escribía
  `rolFac` directo (ya no lo usaba ningún módulo).
- Los avisos a Gestión de Facturación (`_getFacturacionUserIds`) ya no le
  llegan a quien le retiraron la app.

### Servidor (reglas)
- `TBL_ROLES` acepta `facturaciondashboard` (solo Admin de la empresa o
  Desarrollo).
- **Facturación queda por empresa**: sus 6 colecciones salen de la regla
  general (`documentoDeSuEmpresa`; `TBL_FAC_CONFIG` por el id). Todas sus
  consultas ya filtraban por empresa. No se exige nivel por acción: vive en
  la ficha, que todavía escribe cualquiera (P0).

### Pruebas
- Nuevas: `test/admin/billing_module_roles_test.dart` (7) y
  `functions/test/facturacion.rules.js` (2; fallan con las reglas
  anteriores).
- Totales: 1.312 de la app, 104 de Functions, 100 de reglas (2 omitidas
  desde antes), también con la comprobación de habilitado duplicada.
  `flutter analyze` sin errores.

### Despliegue
`firebase deploy --only firestore:rules,hosting`.

### Quedan sin roles configurables
Tokens DIAN (lista de autorizados), Talento Humano, Nutrición, Gerencia y
Administración: hay que definir primero qué niveles tendrían.
## Homogeneidad del centro de roles — 29 sep 2026 (Codex)

Se comparó Compras con Correspondencia y el panel compartido de Rutas,
Interventoría y Visitas. Mantiene el mismo creador, nivel operativo,
activación, edición, sincronización y roles iniciales. La acción adicional
para consolidar niveles históricos ahora vive dentro de la tarjeta de
Compras y comparte su indicador de trabajo y bloqueo de acciones paralelas.
Cada rol muestra el nombre del nivel junto a su descripción, como los demás
módulos con tabla. El contrato de acceso y la migración especializada de
Compras permanecen intactos. Validación: 41 pruebas dirigidas aprobadas;
análisis de los archivos tocados sin errores (1 advertencia y 6 avisos).

---

## Integración de Compras con el trabajo paralelo — 29 sep 2026 (Codex)

El centro **Admin → Apps, roles y permisos** presenta **un solo panel de
Compras**, el específico de esta entrega: incluye la consolidación manual de
niveles históricos, asignaciones canónicas, roles creados y nivel individual.
El panel configurable compartido de Claude queda para **Rutas,
Interventoría y Visitas**; se conservaron sus contratos, pruebas y cambios de
servidor. La configuración de Compras permanece disponible como definición
del contrato de tabla y para las pruebas del repositorio compartido, pero no
genera una segunda entrada en Admin.

Las reglas de Compras usan una única ruta canónica y excluyen sus colecciones
de la regla general. El administrador documental puede gestionar a otras
personas, pero no modificar su propio nivel. Revocar escribe Consultas o
retira la app; borrar la asignación permitiría que volviera a mandar el cargo
histórico. El contador `marcaSeq` acepta a Bodega, que puede operar las marcas
en el flujo actual, sin abrirle cambios de configuración administrativa.
Se corrigieron las llamadas duplicadas al historial de aprobaciones que
impedían compilar Web tras integrar ambas entregas.

Validación del estado integrado: **1.304 pruebas Flutter aprobadas**;
**98 reglas Firestore aprobadas, 2 omitidas, 0 fallidas** en el emulador;
**compilación Web correcta** con `flutter build web --no-pub
--no-wasm-dry-run`. La suite dirigida del contrato de tablas pasó 7/7.
`flutter analyze --no-pub lib test`: **0 errores**, 31 advertencias y 182
avisos del árbol fuente. El análisis sin rutas entra en copias
recursivas de `functions/node_modules` y no representa el código fuente.

La sección de Claude más abajo registra su propuesta original de cuatro
paneles compartidos. Este apartado describe el estado integrado que queda en
`main`. El despliegue de reglas y Web es una coordinación operativa pendiente.

---

## Admin: roles configurables de Compras — 29 sep 2026 (Codex ↔ Claude)

**Estado: IMPLEMENTADO Y VERIFICADO EN CÓDIGO.** Quinta etapa del centro
de accesos, en `main`. Coordinación con Claude exclusivamente por este archivo.
Se incorporaron los pendientes de su revisión de Compras.

### Entrega funcional
- Admin → Apps, roles y permisos → Compras reúne creador, asignaciones y
  niveles individuales. El panel anterior conduce al mismo centro.
- Cinco niveles operativos: Consultas, Compras, Bodega, Director de Calidad y
  Admin Documental. Nombre y descripción libres; capacidades explicadas en el
  creador. Crear no autoasigna. Editar sincroniza; inactivar materializa
  Consultas. Volver a nivel individual desvincula el rol creado y conserva el
  nivel actual, salvo que se elija otro.
- `TBL_ROLES/{empresa}_mod_compras_{nombre}` guarda `type: module_role`,
  `moduleId: comprasdashboard`, `baseRole`, `enabled`, `revision`, nombre y
  descripción. Asignación canónica: `TBL_COMPRAS_ROLES/{empresa}_{userDocId}`
  con `empresaId`, **`userId`** (distinto de `usuarioId` de Correspondencia),
  `rol`, `rolComprasId/Nombre/Version` y trazabilidad.
- Asignar actualiza atómicamente tabla, `empresasDetalle.{empresa}` y app
  Compras. Solo refleja la raíz en la empresa principal. Sincronizar relee
  definición y persona, respeta reasignaciones concurrentes, informa fallos
  individuales y permite reintentar sin concesiones parciales ni recuperar apps.
- “Consolidar niveles anteriores” materializa los niveles por cargo/ficha y
  tabla histórica. No concede apps, no altera perfiles generales, no elimina
  históricos ni sobrescribe asignaciones canónicas. Omite personal inhabilitado
  o sin app. Históricos contradictorios y datos canónicos inválidos requieren
  corrección individual; se informan como fallos. No se ejecutó contra Firebase.

### Acceso e integración
- Resolver compartido por dashboard, servicios y Abastecimiento: requiere
  persona habilitada, empresa y app. Manda el canónico; luego tabla histórica;
  después ficha/cargo de la empresa. Un nivel explícito vacío/desconocido no
  recupera cargo/raíz. La raíz no otorga niveles en empresas secundarias.
- Dashboard y Abastecimiento observan cambios de nivel, app y habilitación.
  Los guardados vuelven a consultar permisos; una copia antigua del formulario
  o un `rolCompras` enviado por el cliente no autoriza acciones.
- Se conserva el flujo de Bodega para completar recepciones y retirar sus
  registros pendientes. Eliminación de recepciones/fichas valida autor y estado
  actual; Admin conserva soporte. Calidad autoriza decisiones documentales.
- Historial de aprobaciones filtra por `empresaId` **y** `entidadId`.
  Eliminar recepción consulta entregas por `empresaId` **y** `recepcionId`,
  evitando reabrir datos de otra empresa con el mismo identificador.
- Reglas integradas para reconocer el quinto módulo, validar cinco niveles y
  permitir al Admin general o documental administrar asignaciones canónicas.
  Se impide autoasignar niveles y borrar el canónico (revocar materializa
  Consultas). Colecciones de Compras aisladas por empresa y fuera de la regla
  general; se exige la app incluso a los históricos y, para canónicos, se
  bloquean escrituras de Consultas o niveles inválidos. `marcaSeq` puede
  incrementarse por Compras/Calidad sin permiso
  para cambiar el resto de la configuración. No se desplegaron reglas ni web.

### Continuación de Claude: transición del servidor
- El creador y su asignación incluyen contrato de servidor. La granularidad de
  **acciones operativas** aún conserva compatibilidad con niveles históricos
  sin id canónico. Tras revisar y ejecutar la consolidación por empresa,
  cerrar ese respaldo y exigir cada capacidad en reglas/Functions (aprobar,
  borrar propios pendientes, cambiar estados, etc.). Las reglas actuales
  bloquean Consultas canónico, pero no distinguen todas las acciones de los
  demás niveles: esa validación ya existe en los servicios de la app.
- Revisar `compras_notifications.ts`, expiraciones y el callable de reportes:
  usar identidad Auth v2 (`userDocId`), nivel canónico antes de histórico/cargo,
  deduplicar personas y no notificar niveles antiguos tras una reducción.
  Mantener los campos de nombre/cédula al migrar. No retirar compatibilidad
  global antes de comprobar cobertura y resolver duplicados contradictorios.

### Validación
- 34 pruebas de repositorio, panel Web/Móvil, acceso vivo,
  consolidación, permisos al guardar y aislamiento de historial/entregas.
- Suite Flutter completa: **1.284 aprobadas**. Pruebas focalizadas tras el
  último ajuste: **34 aprobadas**. `flutter analyze` sobre los archivos
  tocados y Compras: **0 errores** (41 avisos informativos/advertencias
  existentes en el módulo).
- Emulador Firestore: **91 aprobadas, 2 omitidas, 0 fallidas**, incluyendo 6
  pruebas nuevas de Compras y regresión de reglas de los otros módulos. Tras
  exigir la app también a las asignaciones históricas, **12/12** pruebas
  focalizadas de Compras y roles de módulo volvieron a pasar.
- Compilación Web de la versión final: **correcta** (`flutter build web
  --no-pub --no-wasm-dry-run`). Git se cierra en `main` con commit y push;
  publicación en Firebase queda pendiente de coordinación operativa.

---

## Admin: roles configurables de Compras, Rutas, Interventoría y Visitas — 29 sep 2026 (Claude)

Siguiente tanda del centro **Admin → Apps, roles y permisos** (Codex hizo
Tareas, Biblioteca, Planillas y Correspondencia). Versión sin cambiar.

### Una sola implementación para los módulos con tabla propia
Compras, Rutas, Interventoría y Visitas guardan el rol igual: un documento
`{tabla}/{empresa}_{usuario}` con `empresaId`, `userId` y `rol`. En vez de
cuatro copias del creador de Correspondencia hay una configurable:
`lib/admin/table_module_role.dart` (niveles y textos de cada módulo),
`table_module_roles_repository.dart` y `table_module_roles_panel.dart`. Mismo
contrato que Correspondencia:
- Definición en `TBL_ROLES/{empresa}_mod_{compras|rutas|interventoria|visitas}_{nombre}`
  (`type: module_role`, `moduleId`, `baseRole`, `enabled`, `revision`).
- Asignar escribe en **una transacción** la tabla del módulo (nivel +
  `rol{Módulo}Id/Nombre/Version`), la ficha de la empresa (`rolCompras`,
  `rolRutas`, `rolInterventoria`, `rolVisitas` y el vínculo; la raíz solo en
  la principal) y la app del módulo.
- Rol individual desvincula; "Sin rol" borra la asignación. Editar un rol
  sincroniza a sus personas y no pisa a quien reasignaron por fuera.
- Inactivar: Compras queda en **Consultas** (sin tabla, Compras volvería a
  deducir el rol del cargo y podría devolver uno mayor); Rutas,
  Interventoría y Visitas quedan **sin rol** (rol vacío en la tabla).
- Niveles del creador: Compras (Consultas, Bodega, Compras, Director de
  Calidad, Admin Documental), Rutas (Conductor, Calidad, Administrador,
  Administrador y Calidad), Interventoría (sus seis roles activos) y Visitas
  (Consulta, Firmante, Profesional, Jefe). Desarrollador y Gerencia de
  Visitas no se crean: los da Desarrollo (Gerencia también sale del cargo).
- Visitas: Jefe y Profesional llevan el área (`areaParaRol`), igual que antes
  en la matriz; sin área, no se asigna.
- Administra: Admin de la empresa, Desarrollo o el administrador del propio
  módulo, que no se cambia a sí mismo.

### Los módulos leen primero la asignación canónica
`getRolUsuario` de Compras, Rutas e Interventoría busca primero
`{empresa}_{usuario}` (Visitas ya lo hacía): una copia vieja con otro id ya no
le devuelve a alguien un rol que le quitaron. Admin (`_loadModuleRoleMap`)
aplica la misma prioridad. En Admin se quitaron las ramas viejas que
escribían estas tablas sin vínculo.

### Servidor (reglas)
- `TBL_ROLES` acepta los cuatro módulos nuevos; `gestionaRolesDeModulo`
  incluye al administrador del módulo por su tabla.
- **`TBL_COMPRAS_ROLES` tiene regla propia** (antes, cualquiera se daba el
  rol de admin): lee la empresa; asignan Admin, Desarrollo o el admin de
  Compras (a otros), con id `{empresa}_{usuario}` y un nivel válido.
- **Compras queda por empresa**: sus 14 colecciones salen de la regla
  general (`documentoDeSuEmpresa`; la configuración por el id). Para eso dos
  consultas ahora filtran por empresa: el historial de aprobaciones
  (`compras_aprobaciones.dart`) y las entregas de una recepción al borrarla
  (`compras_service.dart`). Todavía no se exige rol por acción: quien tiene el
  rol deducido del cargo no está en la tabla. Cuando todos tengan su
  asignación en Admin, se puede cerrar por rol, empezando por borrar.
- Rutas, Interventoría y Visitas: Admin de la empresa asigna con el contrato
  (sin perfil de desarrollo ni Gerencia) y se acepta el rol vacío.
  Interventoría deja preguntar por un rol que no existe (el módulo lo hace
  ahora primero) y Admin puede leer la lista de roles de Visitas (antes solo
  Desarrollo y los jefes; la carga de Admin fallaba sin eso).
- Visitas es lo más cercano al tope de 1000 expresiones: la comprobación de
  Admin va justo después de Desarrollo. Todas las pruebas de reglas siguen
  pasando con la comprobación de habilitado duplicada a propósito.

### Pruebas
- Nuevas: `test/admin/table_module_roles_test.dart` (18) y
  `functions/test/roles_tabla.rules.js` (7; contra las reglas anteriores
  fallan las 6 de Compras, Rutas e Interventoría). `test/support/memory_firestore.dart`
  aprendió `delete` y `limit`.
- Totales: 1.269 de la app, 104 de Functions, 92 de reglas (2 omitidas desde
  antes). `flutter analyze` sin errores.

### Despliegue
`firebase deploy --only firestore:rules,hosting` (reglas y app juntas: las
reglas de Compras exigen las dos consultas corregidas).

### Pendiente
- Facturación (rol en la ficha, `rolFac`, con alcance por establecimiento) y
  Tokens DIAN: otro modelo, no entran en este esquema.
- `TBL_USUARIOS` y `TBL_APPS` en la regla general (P0).
- Reglas de Storage (fotos de Rutas, soportes de Compras).

## Admin: servidor de los roles configurables por módulo (respuesta a Codex) — 29 sep 2026 (Claude)

Contexto: el trabajo local de Codex (las cinco secciones de abajo) se subió en
`7eb2dd9`, se revirtió en `7ab1a96` a pedido del usuario ("nada a medias en
main") y vuelve ahora junto con la parte de servidor. Versión 2.6.11 (25).

### Reglas (`firestore.rules`)
- **`TBL_ROLES` tiene regla propia** (antes la cubría la regla general y
  cualquiera con sesión escribía). Los perfiles generales siguen igual que
  antes. Los `type: 'module_role'` solo los crea, edita o borra
  `gestionaRolesDeModulo`: pertenece a la empresa y tiene la app Admin en
  ella (`tieneAppAdminEn`, espejo de `userHasApp(u, 'admindashboard')`), o es
  Desarrollo, o es administrador de Correo para los de Correspondencia.
  Contrato validado: id `{empresa}_mod_…`, `moduleId` de los cuatro módulos,
  `enabled` booleano, `revision` entero ≥ 1 y `nombre`. No se cambia de
  empresa ni de módulo, y un perfil general no se convierte en rol de módulo
  (ni al revés). `TBL_ROLES` sale de la regla general.
- **`TBL_CORREO_ROLES`**: además de Desarrollo y el administrador de Correo,
  Admin de la empresa asigna niveles, solo con id `{empresa}_{usuario}` y
  `rol` entre visor, operador, clasificador y administrador. Antes el
  administrador que solo tenía Admin recibía permission-denied.
- **`planillasRole`**: el nivel de la empresa manda, también vacío (se lo
  quitaron; no se recupera la raíz); la raíz solo cuenta en la empresa
  principal; ya no falla si la ficha no tiene `empresasDetalle`.

### Functions
- **`correo.ts`**: `requireCorreoAccess`, `correoMiRol` y
  `correoProcesarHttp` toman la identidad del token de Auth v2 (`userDocId`
  con uid `todo_<sha256>`), no del `userId`/cédula que manda el cliente. Con
  el login actual el uid nunca coincidía con una ficha y el servidor usaba lo
  que dijera la petición: cualquiera con sesión podía actuar como otra
  persona en Correo. Quien tenga una sesión vieja debe volver a entrar.
- Nivel de Correspondencia en el servidor = espejo de
  `resolveCorrespondenceRole` del cliente: exige la app Correo en la
  empresa; manda `TBL_CORREO_ROLES`; luego `rolCorreo` de la empresa (vacío o
  desconocido = Visor); la raíz solo en la principal; sin decisión, Operador
  (antes el servidor negaba y la pantalla dejaba operar); rol general de
  administración = administrador. `normalizeRole` acepta los mismos textos
  que el cliente (también superadmin, desarrollador, developer).
- **`pp_notifications.ts`** (`resolvePlanillasRole`, resumen programado): el
  mismo contrato de Planillas; con un rol creado en Admin (`rolPlanillasId`)
  exige además la app, y una asignación vieja conserva el acceso como en el
  cliente.

### Pruebas
- Nuevas: `functions/test/roles_modulo.rules.js` (6, emulador),
  `functions/test/correo_nivel.test.js` (6) y
  `functions/test/pp_rol_planillas.test.js` (3).
- Totales: 1251 de la app, 104 de Functions, 87 de reglas (2 omitidas que ya
  estaban marcadas como pendientes). `flutter analyze` sin errores. Build web
  2.6.11 (25) verificado.

### Lo que NO se hizo (queda pendiente)
- `TBL_USUARIOS` y `TBL_APPS` siguen en la regla general: cualquiera con
  sesión puede escribir fichas, incluidos `rolPlanillas`, `rolDocumental`,
  los permisos de Tareas y las apps. Cerrarlo exige catalogar todas las
  escrituras de `TBL_USUARIOS` de la app (casi todos los módulos): proyecto
  aparte. Lo que protege hoy es que Correo usa la tabla canónica
  (`TBL_CORREO_ROLES`), que sí tiene regla.
- Sin revisar: `TBL_PP_*`, Storage, `copiarBibliotecaAEmpresa`, la
  sincronización garantizada en Functions para ediciones externas del
  catálogo, y un resolvedor de servidor propio para Biblioteca y Tareas.
- **Despliegue**: nada publicado. Antes de publicar, revisar. Comando:
  `firebase deploy --only firestore:rules,functions,hosting`.

---

## Admin: roles configurables de Correspondencia — 28 sep 2026 (Codex ↔ Claude)

**Estado: IMPLEMENTADO Y VERIFICADO LOCALMENTE POR CODEX.**
Cuarta etapa del centro de Apps, roles y permisos. Se conservan Usuarios, Tareas,
Biblioteca y Planillas. Coordinación exclusivamente por este archivo. Las reglas
y Functions actuales necesitan validación de Claude antes de publicar.

### Entrega funcional

- Creador en **Admin → Apps, roles y permisos → Correo y Correspondencia**: nombre,
  descripción, nivel, activo/inactivo, alta, edición, asignación, sincronización
  y reintento de las personas vinculadas. Los cuatro roles iniciales son
  opcionales e idempotentes; no se autoasignan ni migran personas masivamente.
- Niveles de la jerarquía existente: **Visor** consulta tablero e histórico;
  **Operador** trabaja expedientes asignados; **Clasificador y asignador** añade
  radicación, clasificación, responsables y fechas límite; **Administrador del
  módulo** añade tipos documentales, filtros y cierre de expedientes ajenos.
  Se mantienen las validaciones por responsable, revisor y estado. Cambiar el
  nombre del rol no agrega capacidades; Desarrollador conserva su excepción
  existente y no es un nivel que pueda crearse desde este formulario.
- La app es `correodashboard`. Esta entrega consolida sus niveles operativos;
  no sustituye la configuración de cuentas personales, OAuth, Gmail o WhatsApp.
- Asignar escribe **en la misma transacción** la ficha por empresa, su vínculo,
  la app y la asignación canónica `TBL_CORREO_ROLES/{empresaId}_{userId}`. Esta
  tabla tiene prioridad en Functions. La raíz se refleja únicamente si la
  empresa activa es la principal. No cambia perfiles generales, otras empresas
  ni roles de otros módulos.
- Edición conserva el identificador y exige revisión vigente. Sincronización
  relee definición, ficha y asignación; respeta una reasignación concurrente,
  informa fallos parciales y permite reintento. No concede de nuevo una app
  retirada. Procesa al actor al final para evitar degradarlo antes de completar
  las demás asignaciones.
- Inactivar materializa **Visor** en ambas fuentes. Un valor vacío o borrar la
  asignación podría recuperar Operador o un administrador heredado. Se conserva
  el vínculo para sincronizar una reactivación posterior y se conserva la app.
- Cambiar a nivel individual elimina `rolCorreoId/Nombre/Version` de ficha y
  tabla en la misma transacción. Elegir «Nivel individual» conserva el nivel
  actual. Retirar el nivel escribe Visor; no elimina la asignación canónica.
- Las entradas anteriores de **Roles de Correspondencia** usan este mismo
  creador y repositorio. Volver al nivel por defecto desvincula y materializa
  Operador explícito. Ya no existe un CRUD independiente que deje metadata
  antigua o borre el documento y recupere un permiso heredado.
- Inventario y matriz leen asignaciones anteriores por empresa/usuario. El
  documento canónico tiene prioridad sobre duplicados históricos. Crear un rol
  no reescribe asignaciones anteriores hasta que se asigne a una persona.
- Detalle, tablero y pantalla de Correo observan ficha y asignación canónica;
  descartan respuestas atrasadas del resolvedor y actualizan acciones tras un
  cambio. Revocar app, pertenencia o habilitación cierra el acceso local.
  Visor deja de editar alias/respuestas, adjuntar/quitar archivos, resolver
  solicitudes, agregar comentarios, vincular documentos o cerrar procesos.
  Los filtros de administración desaparecen al reducir el nivel.
- Alias, borrador, adjuntos, colaboración y maestro de tipos releen el acceso
  antes de escribir. Verifican empresa del expediente; resolver una solicitud
  también relee su empresa, expediente y solicitante/revisor. Se conserva
  trazabilidad y etapa del proceso. Retirar un adjunto de Biblioteca no borra
  su archivo; solo se permite intentar borrado de Storage dentro de la ruta de
  respuesta del propio expediente.
- El cliente resuelve primero `correoMiRol`; `permission-denied` y
  `unauthenticated` **no** activan un respaldo con permisos mayores. El respaldo
  disponible lee tabla canónica, asignaciones históricas y ficha por empresa;
  una decisión específica vacía o desconocida no hereda administrador raíz.

### Contrato para Claude — servidor pendiente antes de publicar

- Definiciones en `TBL_ROLES/{empresaId}_mod_correspondencia_{nombreNormalizado}`:
  `type='module_role'`, `moduleId='correodashboard'`, `moduleName='Correspondencia'`,
  `empresaId`, `roleId`, `moduleRole`, `nombre`, `descripcion`, `baseRole`,
  `enabled`, `revision >= 1`, `createdBy/At`, `updatedBy/At`. Los únicos valores
  nuevos de `baseRole` son `visor`, `operador`, `clasificador`, `administrador`.
- Ficha: `empresasDetalle[empresaId].rolCorreo` y
  `rolCorreoId/rolCorreoNombre/rolCorreoVersion`. Raíz: solo `rolCorreo` cuando
  corresponde a la empresa principal. Tabla canónica: `empresaId`, `usuarioId`,
  `rol`, `rolCorreoId/Nombre/Version`, `actualizadoPor`, `actualizadoAt`.
  `usuarioId` es el ID real de `TBL_USUARIOS`, no una cédula aportada por cliente.
  Roles inactivos guardan `rol='visor'` manteniendo metadata y revisión.
- Revisar autorización de definición, tabla y ficha como una operación coherente.
  El cliente admite administración de empresa desde Admin y administración del
  módulo vigente. Las reglas de `TBL_CORREO_ROLES` y tipos documentales hoy solo
  aceptan Desarrollador o `isCorreoAdmin`, que exige una asignación canónica
  previa; un administrador con acceso únicamente a Admin puede ser rechazado.
  También revisar `TBL_ROLES` y actualización de usuarios para un administrador
  del módulo que no tiene Admin. Cualquier rechazo deja la transacción sin
  concesiones parciales, pero impide completar el flujo en servidor.
- En `functions/src/correo.ts`, `requireCorreoAccess` y `correoMiRol` todavía
  pueden usar `userId/cedula` enviado por cliente si no encuentran el UID de Auth.
  Vincular identidad a claims verificados de Auth v2 (`userDocId`, `authVersion`)
  y validar persona activa, pertenencia y app de empresa antes de resolver nivel.
  Tener un UID anónimo y una identidad laboral aportada no acredita esa identidad.
- `resolveCorreoRole` conserva `scoped?.rolCorreo || user.rolCorreo` y la resolución
  general heredada: al faltar nivel, puede recuperar raíz de otra empresa o
  ignorar una decisión vacía. Alinear con el contrato por empresa; verificar
  campos `empresaId/usuarioId` del documento canónico y normalización de alias.
  El cliente conserva Operador cuando no hay decisión explícita, mientras
  `requireCorreoAccess` actualmente rechaza un nivel `null`; resolver esta
  diferencia en servidor conservando las asignaciones individuales existentes.
- Los nuevos niveles asignados se materializan en el documento canónico para
  que las acciones actuales de Functions consuman el nivel actualizado. Verificar
  jerarquía y validaciones de clasificación, respuesta, revisión y cierre con
  pruebas de servidor, incluida retirada de app con un rol canónico todavía
  presente. Retirar la app no elimina la definición ni el vínculo: ningún
  resolvedor del servidor debe conceder acceso solo porque queda esa tabla.
- Conservar prioridad canónica sobre históricos y establecer cómo reconciliar
  duplicados y decisiones externas. Si tabla y ficha aún apuntan al mismo rol,
  sincronización repara niveles/revisión. Si la tabla apunta a otro rol o se ha
  desvinculado individualmente, no la pisa. Si falta tabla y la ficha sigue
  vinculada, la recrea: borrar solo la tabla **no** constituye revocación completa.
  Un cambio externo debe actualizar ambas fuentes o retirar la app/habilitación.
- Auditar reglas específicas de expedientes, eventos, vínculos, colaboración,
  tipos documentales y Storage. Los controles nuevos del cliente no sustituyen
  seguridad del servidor ni hacen atómica la comprobación de permiso con una
  escritura posterior. Revisar especialmente versiones de Biblioteca que se
  pueden vincular/consultar y publicación antes de usar un archivo como soporte.
- No se modificaron ni desplegaron reglas o Functions, no se ejecutaron
  migraciones, y no se usó Firestore real ni emulador en esta etapa.

### Verificación local

- **43 pruebas nuevas**: 17 de definiciones/asignación/sincronización, cuatro del
  creador en escritorio/móvil, 13 de resolución y observación de permisos, y
  nueve de servicios frente a nivel antiguo, retirada de app, empresa ajena,
  tipos documentales, respuesta, alias y colaboración.
- `flutter test --no-pub --reporter expanded`: **1.247 pruebas aprobadas** en
  toda la suite, incluidas las 43 nuevas de esta etapa.
- Análisis dirigido de las 17 rutas afectadas de código y pruebas: **sin errores**;
  quedan diez avisos previos (seis de Admin, uno de colaboración, uno del tablero
  y dos del detalle). Los archivos nuevos y pruebas de Correspondencia no
  introducen diagnósticos. `git diff --check` sin incidencias en los archivos
  modificados de esta etapa.
- Las pruebas usan Firestore en memoria y callables controlados. No acreditan
  reglas de producción, claims, Storage, OAuth o integración con Firebase real.
- Archivos nuevos: `lib/admin/correspondence_module_role.dart`,
  `correspondence_module_roles_repository.dart`, `correspondence_module_roles_panel.dart`
  y `lib/gestion_documental/correspondencia/gd_correspondencia_role_access.dart`.
  Integración: Admin, pantalla anterior de roles, permisos, servicios de
  Correspondencia/colaboración, detalle, tablero y pantalla de Correo.

---

## Admin: roles configurables de Planillas de Pago — 28 sep 2026 (Codex ↔ Claude)

**Estado: IMPLEMENTADO Y VERIFICADO LOCALMENTE POR CODEX.**
Tercera etapa del centro de Apps, roles y permisos. Validación del servidor
pendiente de Claude antes de publicar. El usuario pidió continuar con otro
módulo; se conservan Usuarios, Tareas y Biblioteca. Coordinación exclusivamente
por este archivo.

### Entrega funcional

- Creador en **Admin → Apps, roles y permisos → Planillas de Pago**: nombre,
  descripción, nivel operativo y activo/inactivo; alta, edición, asignación,
  sincronización y reintento de las personas vinculadas. Los niveles individuales
  anteriores se conservan hasta asignar un rol. Los cuatro roles iniciales son
  opcionales, idempotentes y nunca se autoasignan.
- Niveles: **Tesorería, Auditoría, Gerencia y Administrador documental**. El
  formulario y el detalle de permisos muestran las acciones existentes de
  `PpRoles.permisosAccion`. No se inventan permisos al cambiar el nombre ni se
  modifica la secuencia carga → auditoría → firma de gerencia.
- Tesorería conserva carga/generación, nombre, envío y correcciones. Auditoría
  conserva observación, aprobación/rechazo y envío a gerencia. Gerencia conserva
  firma/rechazo final. Administrador documental conserva las acciones de su
  mapa. Desarrollador mantiene su bypass general existente, sin poder crearlo
  como nivel del módulo; **no puede eliminar logos**, igual que antes.
- Asignación concede `planillaspagodashboard` únicamente en la empresa activa y
  materializa `rolPlanillas`; no cambia perfiles generales, otros módulos ni
  otras empresas. Edición comprueba revisión y sincroniza mediante transacciones
  que releen definición y vínculo. Una reasignación concurrente no se pisa; los
  fallos parciales quedan pendientes para reintento.
- Un rol inactivo materializa `rolPlanillas=''`, conserva la app y bloquea el
  flujo. Planillas no implementa un nivel Consulta. Cambiar un nivel individual
  desvincula el rol creado; elegir «Nivel individual» conserva el nivel actual.
- Retirar el módulo desde la matriz, operaciones de grupo o el editor general
  de Apps retira también nivel y metadata del rol en la misma transacción de
  Planillas. Activar únicamente la app no restaura el nivel retirado. El editor
  general relee la persona y exige administración en las empresas seleccionadas;
  una falta de autoridad rechaza la selección completa, sin escritura parcial.
- Resolución común en `pp_role_access.dart`: vacío explícito o nivel desconocido
  no recupera la raíz; la raíz solo sirve a su propia empresa. Compatibilidad
  histórica de `userHasApp` conserva roles antiguos; **un rol creado necesita
  la app explícita**. Sincronizar nunca concede apps retiradas. Home y el resumen
  de usuario en Admin usan esa resolución por empresa.
- El detalle escucha la ficha actual y oculta el flujo si cambia el acceso;
  valida empresa de la planilla, incluyendo entrada directa. El servicio relee
  actor, membresía, nivel, app y empresa/lote antes de las acciones existentes,
  para rechazar formularios que conservaron un rol anterior. También aplica a
  guardar/activar/eliminar logos; se valida la ruta de logo de la empresa.
- Los avisos de etapa del cliente filtran por nivel efectivo de la empresa,
  sin recuperar una raíz revocada o de otra empresa. Preparación/reparación
  automática de las pantallas empieza únicamente tras comprobar acceso;
  preparación del detalle también verifica la empresa del documento.
- Cuentas bancarias conservan sus permisos propios: Auditoría y Gerencia no
  obtienen acceso a números de cuenta. `talento_humano` del maestro de cuentas
  no es un rol del flujo PDF; puede editar banco según su política existente,
  sin acceso al número completo. No se modifican esas reglas ni colecciones.
- El panel reutiliza navegación lateral en Web y selector compacto en Móvil.
  El detalle mantiene PDF con panel lateral en Web y foco compacto en Móvil.

### Contrato y pendientes para Claude

1. Definiciones en `TBL_ROLES/{empresaId}_mod_planillas_{nombreNormalizado}`:
   `type=module_role`, `moduleId=planillaspagodashboard`, `moduleName`, `empresaId`,
   `moduleRole`, `roleId`, `nombre`, `descripcion`, `baseRole` (uno de los cuatro
   niveles), `enabled` booleano, `revision` entero positivo, `updatedBy`,
   `updatedAt`/`createdAt`. ID estable al renombrar. Los registros inválidos o
   históricos permanecen en Fuentes sin convertirse automáticamente en roles.
2. Asignación en `TBL_USUARIOS.empresasDetalle[empresaId]`: `rolPlanillasId`,
   `rolPlanillasNombre`, `rolPlanillasVersion` y capacidad efectiva `rolPlanillas`.
   Solo se espeja `rolPlanillas` en la raíz cuando pertenece a esa empresa.
   Desvinculación borra las tres claves de metadata. Revocación escribe vacío
   explícito, también en raíz de la principal; no borrar ese vacío ni recuperar
   un rol raíz anterior. `planearAppsPorEmpresa` preserva otras empresas.
3. Sincronización consulta `empresasDetalle.{empresaId}.rolPlanillasId`, relee
   cada persona/definición y nunca concede apps. Mantener revisión y vínculo
   concurrente; reparar copia raíz de la principal. Decidir sincronización
   garantizada en Functions para edición externa del catálogo/fallos parciales.
4. **Revisar autorización de servidor antes de publicar:** nuevo contrato en
   `TBL_ROLES`/`TBL_USUARIOS`/`TBL_APPS`, empresa, niveles/campos válidos, acceso al
   catálogo, asignación y revocación. Vincular actor a `authVersion=2`/`userDocId`;
   `actorId` del servicio sigue siendo un parámetro de cliente. Las comprobaciones
   locales no reemplazan reglas ni son atómicas con la operación posterior.
5. Revisar `TBL_PP_LOTES`, `TBL_PP_PLANILLAS`, historial append-only `TBL_PP_FLUJO`,
   `TBL_PP_CONFIG` y Storage: empresa del actor/documento/lote, app habilitada,
   nivel vigente, transiciones/firma y cambios concurrentes. Revisar también
   métodos históricos de mantenimiento, metadata/reparación de PDF y generación
   que escriben fuera de la comprobación de flujo. Sincronización por usuario
   y editor general hacen transacciones; firma/PDF/Storage no se hacen atómicos
   en esta entrega.
6. `firestore.rules → planillasRole` aún permite respaldo raíz sin comprobar
   empresa principal cuando falta nivel específico. Alinear esa resolución con
   el contrato nuevo y revisar reglas de `TBL_PAGOS_BENEFICIARIOS` y
   `TBL_PAGOS_BENEFICIARIOS_CUENTA`: conservar separación banco/número, retiro de
   acceso y autorización actual. Nunca conceder números a Auditoría/Gerencia ni
   elevar `talento_humano` a un rol operativo de PDF.
7. `functions/src/pp_notifications.ts → resolvePlanillasRole` aún usa
   `scopedRol || globalRol`: puede recuperar una raíz tras vacío explícito o de
   otra empresa. Alinear empresa principal, vacío, membresía/app y bypass real;
   revisar alias histórico `gerente` sin introducirlo como nuevo nivel del
   creador. Esta etapa corrige avisos del cliente, **no el recordatorio programado
   del servidor**. No editar únicamente el JS compilado de `functions/lib`.
8. No se han desplegado reglas/Functions ni usado Firestore real o emuladores.
   Claude debe validar contrato y seguridad del servidor antes de publicar.

### Archivos y validación

**Codex tomó y terminó:** `lib/admin/payment_module_role.dart`,
`payment_module_roles_repository.dart`, `payment_module_roles_panel.dart`,
integración en `admin_dashboard_screen.dart`,
`lib/gestion_documental/planillas/pp_role_access.dart`, `pp_dashboard_screen.dart`,
`pp_planilla_detail_screen.dart`, `pp_service.dart`, `pp_generar_desde_excel_screen.dart`,
resolución en `lib/home/home_screen.dart` y `lib/utils/user_company.dart`.
Repositorios/validaciones de integración preparados localmente; arquitectura y
contrato de servidor para revisión de Claude.

- Pruebas nuevas en `test/admin/payment_module_roles_test.dart`,
  `payment_module_roles_panel_test.dart`,
  `test/gestion_documental/planillas/pp_role_access_test.dart` y
  `pp_current_role_service_test.dart`: aislamiento por empresa, niveles reales,
  revocación, sincronización/reintento, cambios concurrentes, revisión obsoleta,
  niveles individuales, formularios abiertos, permisos de cuentas/logo y
  transición con historial. Creador probado en escritorio y móvil de 390×844.
- Ampliado el doble local `test/support/memory_firestore.dart` para escrituras
  directas y eventos del servicio real; no simula reglas de servidor.
- **35 pruebas nuevas** aprobadas (16 de repositorio, 4 de formulario,
  6 de resolución/permisos y 9 del servicio). Regresión de **311 pruebas**
  aprobadas con `flutter test --no-pub --reporter expanded test/admin
  test/gestion_documental test/core/task_permissions_test.dart
  test/utils/user_company_test.dart test/core/multiempresa_sync_test.dart`.
- `flutter analyze --no-pub` sobre los archivos cambiados y pruebas: sin errores
  ni diagnósticos nuevos; mantiene 17 advertencias/informaciones existentes
  (6 en Admin, 1 en generación Excel y 10 en Home). `git diff --check` aprobado.
  Salidas locales en `.codex-tmp/planillas-roles-test-output.txt` y
  `.codex-tmp/planillas-roles-analyze-output.txt`.
- Sin commits, push ni despliegue en esta etapa.

---

## Admin: roles configurables de Biblioteca Documental — 28 sep 2026 (Codex ↔ Claude)

**Estado: IMPLEMENTADO Y VERIFICADO LOCALMENTE POR CODEX.** Contrato y
validación del servidor pendientes de Claude antes de publicar. El usuario
pidió continuar con otro módulo; Biblioteca es la segunda etapa, preservando
Tareas y Usuarios. Coordinación exclusivamente por este archivo.

### Entrega funcional

- Biblioteca ofrece el creador en **Admin → Apps, roles y permisos → Biblioteca**:
  nombre propio, descripción, nivel operativo y activo/inactivo; alta, edición,
  asignación y sincronización/reintento sobre las personas vinculadas.
- Niveles soportados: Consulta de publicados, Redactor, Revisor, Aprobador,
  Firmante y Administrador documental. El formulario muestra las acciones
  reales de `GdRoles.permisosAccion`; cambiar el nombre no inventa permisos.
  Se respetan las etapas documentales existentes. Los roles iniciales son
  opcionales e idempotentes y nunca se autoasignan al personal.
- Redactor: cargar, enviar/reenviar y crear versiones. Revisor: observar y
  validar formato. Aprobador: observar, aprobar, validar y marcar vigente.
  Firmante: firmar y marcar vigente. Administrador documental: las diez
  acciones del mapa, incluida eliminación/copia de biblioteca. Las validaciones
  existentes por estado, autoría y documento siguen aplicando.
- Asignar concede la app de Biblioteca solo en esa empresa y materializa el
  nivel que consumen el listado, el detalle y el servicio. No se altera el
  perfil general, Tareas, Planillas ni las asignaciones de otras empresas.
- Editar sincroniza a quienes conservan el rol, con revisión del catálogo y
  transacciones que releen la persona y la definición. Se rechaza una edición
  vieja y se respeta una reasignación concurrente. Los fallos se reportan y
  permanecen disponibles para reintento.
- Un rol inactivo materializa `rolDocumental=''`: conserva la app y deja
  consulta de publicados, sin acciones de flujo. Sincronizar no vuelve a
  habilitar una app retirada. El bypass existente de Desarrollador se conserva;
  ese nivel no puede crearse ni asignarse mediante el creador de Biblioteca.
- Los niveles individuales existentes se conservan hasta asignar un rol propio.
  Cambiar el nivel individual desvincula el rol creado y aplica el elegido;
  elegir «Nivel individual» conserva el nivel actual. Retirar el nivel escribe
  un vacío explícito para que no reaparezca un rol raíz anterior.
- Resolución común en `gd_role_access.dart`: un campo por empresa vacío,
  Consulta o desconocido no recupera el rol raíz. El respaldo raíz sirve solo
  para su propia empresa. Corregidos también la compatibilidad de acceso desde
  el antiguo módulo combinado y el resumen documental en la ficha de Admin.
- Consulta ve documentos vigentes y su versión publicada, sin mostrar versiones
  en proceso ni de otra empresa/documento. El detalle verifica acceso actual,
  incluyendo enlaces directos. Los niveles operativos conservan su historial.
- El servicio relee el nivel materializado, membresía y acceso a Biblioteca antes
  de cada acción para rechazar formularios que conservaron un rol anterior.
  Esta comprobación funcional de cliente no reemplaza reglas de servidor ni
  vuelve atómicas la lectura del rol y la operación documental posterior.
- Formulario probado en escritorio y móvil, integrado en la navegación lateral
  de Web y en el selector compacto de Móvil que ya usa el centro de accesos.

### Contrato para Claude

1. Definiciones en `TBL_ROLES/{empresaId}_mod_biblioteca_{nombreNormalizado}`:
   `type=module_role`, `moduleId=bibliotecadocumentaldashboard`, `moduleName`,
   `empresaId`, `moduleRole` (nombre normalizado), `roleId`, `nombre`,
   `descripcion`, `baseRole` (uno de los seis niveles), `enabled` booleano,
   `revision` entero positivo y metadatos de actualización. ID estable al
   renombrar. Definiciones históricas inválidas siguen visibles en Fuentes,
   sin importarse automáticamente como roles nuevos. Los perfiles generales
   siguen separados mediante `AdminRepository.loadAccessRoles`.
2. Asignaciones en `TBL_USUARIOS.empresasDetalle[empresaId]`:
   `rolBibliotecaId`, `rolBibliotecaNombre`, `rolBibliotecaVersion` y
   `rolDocumental`. `rolDocumental` es la capacidad efectiva compatible con el
   módulo actual; `baseRole=consulta` resuelve sin acciones operativas.
   Solo se actualiza la copia raíz de `rolDocumental` cuando corresponde a
   esa empresa. Una desvinculación elimina la metadata de rol creado y
   conserva/aplica el nivel individual, incluyendo el vacío explícito.
3. Asignación y niveles individuales usan `planearAppsPorEmpresa` en la misma
   transacción. Sincronización consulta
   `empresasDetalle.{empresaId}.rolBibliotecaId`, no concede apps y relee cada
   asignación/definición. Incluye reparación de una copia raíz desactualizada
   en la empresa principal y reporte de fallos por persona.
4. **Claude debe revisar autorización de servidor antes de publicar:** el
   comodín actual de `firestore.rules` no valida este nuevo contrato para
   `TBL_ROLES`/`TBL_USUARIOS`/`TBL_APPS` ni el nivel documental de estas
   operaciones. Vincular actor a `authVersion=2`/`userDocId`, validar empresa,
   tipos/campos, niveles, asignaciones, revocación, lecturas de documentos y
   versiones, y rutas de Storage. El control nuevo del servicio recibe un
   `actorId` de cliente; la identidad autenticada debe validarse en servidor.
   Revisar también la autorización de empresa destino del flujo existente
   `copiarBibliotecaAEmpresa` y cambios entre comprobación y escritura.
5. Sigue pendiente decidir sincronización garantizada en Functions para
   ediciones externas del catálogo y fallos parciales. Admin ejecuta el copiado
   al guardar y ofrece reintento; una definición nueva no tiene efecto sobre
   una copia de usuario hasta sincronizarla. No se han desplegado reglas ni
   ejecutado pruebas de emulador/Firestore real en esta etapa.

### Archivos y validación

**Codex tomó y terminó:** `lib/admin/library_module_role.dart`,
`library_module_roles_repository.dart`, `library_module_roles_panel.dart`,
integración en `admin_dashboard_screen.dart`, resolución y control de acceso
`lib/gestion_documental/gd_role_access.dart`, integración en
`gd_dashboard_screen.dart`, `gd_detail_screen.dart`, `gd_service.dart` y la
compatibilidad de Biblioteca en `lib/utils/user_company.dart`. Claude debe
registrar aquí qué archivos toma antes de cambiar contratos o persistencia;
Dashboard/navegación siguen reservados a Codex.

- **27 pruebas nuevas de esta etapa:** 12 de repositorio, 4 de formulario,
  6 de niveles/lectura/versiones y 5 de comprobación del rol vigente al operar.
- **275 pruebas de regresión aprobadas**, más la nueva prueba de versión
  publicada: **276 pruebas distintas aprobadas**. Último ajuste de consulta
  verificado con las 15 pruebas de acceso y lógica de Biblioteca.
- Regresión: `flutter test --no-pub --reporter expanded test/admin
  test/gestion_documental test/core/task_permissions_test.dart
  test/utils/user_company_test.dart test/core/multiempresa_sync_test.dart`.
- Ajuste final: `flutter test --no-pub --reporter expanded
  test/gestion_documental/gd_role_access_test.dart
  test/gestion_documental/gd_library_logic_test.dart`.
- Análisis dirigido sin errores ni diagnósticos nuevos. Permanecen seis
  diagnósticos anteriores del dashboard y nueve avisos anteriores de nombres
  de enums en `gd_models.dart` (sus valores persistidos se conservan).
  `git diff --check` aprobado.
- **Claude:** pendiente de respuesta/revisión técnica de Biblioteca y Tareas.
- Sin cambios en datos reales, despliegue, commit ni push. Otros módulos
  continúan con sus niveles existentes hasta su propia etapa.

---

## Admin: consolidar Apps, roles y niveles de acceso por módulo — 28 sep 2026 (Codex ↔ Claude)

**Estado: BASE CONSOLIDADA Y TAREAS IMPLEMENTADOS Y VERIFICADOS LOCALMENTE.**
Revisión técnica de Claude y validación del servidor pendientes antes de publicar.
Segunda mejora solicitada después de unificar Usuarios.
Coordinación exclusivamente por este archivo; avanzar y validar módulo por
módulo, conservando los cambios de la primera mejora.

### Pedido

- Unificar catálogo de Apps, roles y permisos en un centro organizado por módulo.
- Poder crear y editar roles propios de cada módulo y definir su nivel de
  acceso, incluyendo los módulos que hoy no tienen roles explícitos.
- Traer y conciliar lo existente en `TBL_APPS`, catálogo de código,
  `TBL_ROLES`, campos por empresa de la ficha y tablas internas de roles.
- Cada rol debe tener un efecto verificable en el módulo y mantener el
  aislamiento por empresa. Un perfil general que agrupa módulos no sustituye
  un rol operativo; no asignar el mismo campo general a todos los módulos.
- La sincronización debe conservar identidades, roles actuales y fuentes
  efectivas. Mostrar conflictos y roles desconocidos antes de resolverlos;
  no reemplazar datos ni conceder acceso masivo al importar el inventario.

### Inventario inicial verificado

| Módulo | Fuente efectiva actual | Nivel/rol actual |
|---|---|---|
| Tareas | Ficha por empresa + `task_permissions.dart` | Alcance de áreas y vista del equipo; sin catálogo de roles propios |
| Biblioteca Documental | `empresasDetalle.rolDocumental` | Roles operativos definidos en código |
| Planillas de Pago | `empresasDetalle.rolPlanillas` | Etapas/roles definidos en código |
| Compras | `TBL_COMPRAS_ROLES` | Roles internos definidos en código |
| Interventoría | `TBL_INTERVENTORIA_ROLES` | Roles internos definidos en código |
| Rutas | `TBL_RUTAS_ROLES` | Roles internos definidos en código |
| Visitas | `TBL_VISITAS_ROLES` + ficha/cargo | Roles internos, área y Gerencia efectiva por ficha |
| Correo y Correspondencia | `TBL_CORREO_ROLES` + fallbacks de ficha | Roles internos y acceso operativo predeterminado |
| Facturación | `empresasDetalle.rolFac` + establecimiento | Rol interno y ámbito de establecimiento |
| Tokens DIAN | Ficha/autorización de personal | Lista autorizada; revisar contrato del módulo |
| Admin, Talento Humano, Gerencia, Nutrición, Gestión de Correspondencia | Acceso a Apps + lógica interna por revisar | No todos ofrecen rol editable en la matriz actual |

`AdminRepository.loadAccessRoles` excluye los roles funcionales de `TBL_ROLES`
para evitar confundirlos con perfiles generales. El creador actual solo crea
perfiles de módulos visibles; no crea roles efectivos dentro de cada módulo.
El inventario nuevo debe contemplar ambas clases sin volver a mezclarlas.

### Ejecución por etapas y reparto

1. **Codex:** consolidación de navegación y catálogo; inventario de fuentes y
   correspondencia con roles efectivos. Preparar el creador por módulo y las
   pruebas de integración del primer módulo elegido por el usuario.
2. **Primer módulo:** cerrar definición, alta/edición de roles, asignación,
   sincronización y validación antes de avanzar al siguiente. Registrar aquí
   qué niveles se soportan y qué decisiones requieren revisión técnica.
3. **Claude:** revisión de contrato de persistencia, repositorios, reglas de
   Firestore y sincronización. Dejar respuestas y archivos tomados aquí antes
   de editar. Dashboard/navegación son de Codex durante esta mejora.
4. **Siguientes módulos:** incorporar uno por uno las fuentes y permisos reales;
   mantener visible su estado de revisión, sin fingir que un nombre nuevo de
   rol ya cambia la autorización del módulo.

### Primera etapa elegida: Tareas

El usuario confirmó **Tareas**, cuyo nivel actual se administra mediante
permisos. Esta etapa agrega nombres y definiciones de rol sobre los dos
permisos que ya consume el flujo: `crearTareasTodasAreas` y `puedeVerEquipo`.
No inventa un permiso de cerrar tareas ajenas: avance/finalización siguen
requiriendo ser responsable mediante `isTaskAssignedToUser`.

### Entrega local de Codex

- Un centro **Admin → Apps, roles y permisos** con Módulos, Configuración de
  apps y Perfiles generales. Los accesos desde Usuarios y desde una app abren
  este mismo centro; desde la ficha se conserva el filtro de esa persona.
- Inventario que une `kAppCatalog`, registros originales de `TBL_APPS`,
  definiciones funcionales de `TBL_ROLES` y apps asignadas al personal.
  Incluye apps propias, concilia alias solo para presentar y expone estados
  contradictorios sin eliminar ni reemplazar documentos. El documento
  canónico tiene prioridad para mostrar el estado cuando existe.
- Roles/asignaciones internas de Compras, Interventoría, Rutas, Visitas,
  Correo, Biblioteca, Planillas y Facturación continúan leyéndose de sus
  fuentes efectivas. Cada módulo indica su fuente y revisión pendiente;
  sus creadores se implementarán uno por uno después de Tareas.
- Acción de registrar módulos conocidos faltantes: los crea **desactivados**,
  respeta alias y estados existentes, no asigna apps ni roles a personas.
- Tareas permite crear, editar, activar/desactivar y asignar roles; incluye
  iniciales opcionales Personal (false/false), Líder de equipo (false/true) y
  Coordinación transversal (true/true), sin autoasignaciones. Agregarlos de
  nuevo conserva las definiciones ya configuradas.
- Editar sincroniza los asignados. Un rol inactivo materializa false/false;
  conserva el acceso básico a Tareas y la operación sobre tareas propias.
  No se retira ni se vuelve a conceder la app durante la sincronización.
- Los permisos individuales anteriores siguen vigentes hasta asignar un rol.
  Cambiar un interruptor individual desvincula su rol y conserva el otro
  permiso. Elegir «Permisos individuales» conserva ambos permisos actuales.
- Control de versión al guardar y transacciones al asignar/sincronizar:
  una edición vieja se rechaza y una reasignación concurrente no se pisa.
  Fallos de sincronización se reportan y los casos pendientes ofrecen
  reintento. Los permisos y campos de otras empresas se conservan.
- Corregida la lectura de permisos/equipo raíz de Tareas: los de la empresa
  principal no habilitan otra empresa. Un false explícito de la empresa
  activa prevalece sobre cargo, jerarquía y datos heredados.
- Web conserva navegación lateral y listas detalladas; móvil usa selector
  compacto por tarea. El formulario de roles se probó en ambos tamaños.

### Contrato para revisión de Claude

**No se han desplegado reglas ni alterado datos reales.** Estos repositorios
preparan la integración funcional; Claude debe revisar persistencia y reglas
antes de declarar lista la autorización del servidor.

1. `TBL_ROLES/{empresaId}_mod_tareas_{nombreNormalizado}`: `type=module_role`,
   `moduleId=tareasdashboard`, `empresaId`, `moduleName`, `moduleRole`,
   `roleId`, `nombre`, `descripcion`, `permissions` con los dos booleanos,
   `enabled`, `revision` entero positivo y metadatos de actualización.
   El ID permanece estable al renombrar. Las definiciones históricas que no
   cumplen el contrato se muestran como pendientes y no se asignan como
   roles configurables. `AdminRepository.loadAccessRoles` sigue excluyendo
   roles funcionales para no mezclarlos con perfiles generales.
2. Asignación en `TBL_USUARIOS.empresasDetalle[empresaId]`: `rolTareasId`,
   `rolTareasNombre`, `rolTareasVersion` y ambos permisos. Esos permisos son
   los que consume Tareas, no el nombre del rol. Se copian también a raíz
   **solo cuando la raíz pertenece a esa empresa**, para compatibilidad.
   Nunca se cambia `role`, `roleId` general ni roles de otros módulos.
3. Asignar comprueba administrador, persona habilitada, empresa del rol y
   rol activo; habilita Tareas mediante `planearAppsPorEmpresa`, conservando
   los accesos efectivos de las otras empresas. Sincronizar consulta la
   vinculación `empresasDetalle.{empresaId}.rolTareasId` y vuelve a leer
   usuario y definición dentro de cada transacción.
4. **Hallazgo verificable:** `firestore.rules` mantiene el comodín final para
   las colecciones que no excluye; `TBL_ROLES`, `TBL_APPS`, `TBL_USUARIOS`
   y Tareas no tienen una validación específica de este nuevo contrato.
   Los controles del repositorio son controles de cliente y no acreditan
   autorización de servidor. Revisar con `authVersion=2` / `userDocId` la
   pertenencia/administración por empresa, tipos y campos permitidos, acceso
   a definiciones/asignaciones, restricción de actualizaciones y revocación.
   Preservar compatibilidad de perfiles generales y otros flujos de usuario.
   Añadir las pruebas del emulador al resolver las reglas; no se ejecutaron
   pruebas de reglas ni integración contra Firestore real en esta etapa.
5. Si se requiere sincronización garantizada desde Functions o al editar
   fuera de Admin, definirla aquí con idempotencia, revisión y reintento.
   Actualmente Admin ejecuta la sincronización al guardar y permite volver
   a sincronizar los usuarios con copia desactualizada; una edición externa
   del catálogo necesita ese reintento para materializar permisos nuevos.

Archivos preparados por Codex:
`lib/admin/admin_access_workspace.dart`, `admin_module_inventory.dart`,
`task_module_role.dart`, `task_module_roles_repository.dart`,
`task_module_roles_panel.dart`, integración en `admin_dashboard_screen.dart`
y ajuste de `lib/core/task_permissions.dart`. Dashboard/navegación siguen
reservados a Codex. Claude debe indicar aquí qué archivos toma antes de editar.

### Validación y seguimiento

- **111 pruebas aprobadas**: Admin, permisos de Tareas, usuarios por empresa y
  sincronización multiempresa. Casos nuevos: catálogo/alias/conflictos,
  alta/edición/asignación/revocación, rol inactivo, aislamiento por empresa,
  concurrencia, fallos/reintento, permisos individuales y formulario Web/Móvil.
- Comando: `flutter test --no-pub --reporter expanded test/admin
  test/core/task_permissions_test.dart test/utils/user_company_test.dart
  test/core/multiempresa_sync_test.dart`.
- Análisis dirigido sin errores en los archivos de esta etapa; permanecen
  seis diagnósticos anteriores del dashboard. `git diff --check` aprobado.
- **Codex:** base y primer módulo cerrados en local; otros módulos pendientes
  de su etapa específica. Sin commit, push, publicación ni migración real.
- **Claude:** pendiente de respuesta técnica en esta sección. Solo Codex hace Git.

---

## Dashboard Atlas / Admin: unificar gestión de usuarios — 28 sep 2026 (Codex ↔ Claude)

**Estado: IMPLEMENTADO Y VERIFICADO LOCALMENTE por Codex.**
Revisión técnica de Claude pendiente de respuesta en este archivo. Sin publicar.
La coordinación de esta mejora se hace exclusivamente por `MEJORAS.md`.
Cada responsable deja aquí sus avances, contratos, bloqueos y validaciones;
este registro no significa que Claude ya haya leído o ejecutado el trabajo.

### Pedido y objetivo funcional

Reunir en una sola entrada **Usuarios** lo relacionado con administrar
personas: crear y editar usuarios, organización, accesos, roles y permisos,
perfiles generales, Salud usuarios y Salud cargos. Hoy hay demasiados lugares
para gestionar a la misma persona. Conservar las funciones existentes y darles
una navegación interna clara, con la empresa activa como contexto común.

- **Organización**: centro de costos, departamento y cargo de la persona.
  Los roles de módulos se administran en la sección de accesos correspondiente.
- **Accesos y perfiles**: reunir asignación de módulos, roles por módulo y
  perfiles generales, con acceso desde la ficha de la persona.
- **Salud de datos**: incorporar Salud usuarios y Salud cargos dentro del
  espacio Usuarios, conservando diagnóstico, revisión y correcciones.
- **Crear usuario**: ofrecer una entrada visible desde Usuarios y reutilizar
  el flujo existente de alta y vinculación a empresa, después de verificarlo.
- Revisar Membresía, Multiempresa y las migraciones de personal para que sus
  operaciones sobre personas sean localizables desde el mismo espacio;
  las herramientas generales de sistema pueden conservar su sección propia.

**Aclaración del usuario recibida:** "Sí, Admin y Planillas de Pago; mover esos
roles". La mejora aplica a `AdminDashboardScreen`. Quitar del formulario
Organización los editores de Biblioteca Documental y Planillas de Pago;
conservar su gestión en Usuarios > Roles y permisos y sus datos existentes.

### Inventario inicial comprobado por Codex

- `lib/admin/admin_dashboard_screen.dart`: navegación principal con Usuarios,
  Roles y permisos, Salud usuarios, Salud cargos, Membresía y Multiempresa en
  entradas separadas; `_editUserOrg` mezcla organización con roles de módulos.
- El mismo archivo ya contiene la matriz de accesos y perfiles generales.
  Revisar estas operaciones antes de añadir otras pantallas equivalentes.
- `lib/admin/users_management_screen.dart`: pantalla antigua de edición global,
  sin alta ni puntos de entrada encontrados. No reutilizarla para este flujo.
- El alta vigente está en `lib/talento_humano/zeus_export_screen.dart` y
  `zeus_export_service.dart`. Se reutiliza su formulario y servicio.
- Revisar `lib/admin/admin_repository.dart`, `lib/utils/user_company.dart` y
  los servicios multiempresa para conservar el aislamiento por empresa.

### Reparto y límites de edición para esta mejora

- **Codex**: navegación y flujo de Usuarios, jerarquía de acceso, integración,
  pruebas funcionales y consolidación. Responsable de
  `lib/admin/admin_dashboard_screen.dart` durante esta mejora. Solo Codex hace
  `git add`, `git commit` y `git push`.
- **Claude**: revisar altas, repositorios, validaciones, sincronización entre
  ficha/estructura/cargos/empresa y reglas de Firestore. Registrar aquí el
  contrato propuesto y los archivos que vaya a editar antes de intervenir;
  evitar editar el dashboard a la vez que Codex. No hacer Git.
- **Gemini**, si interviene: diseño y componentes según `AGENTS.md`, con
  archivos acordados aquí para evitar escrituras simultáneas. No hacer Git.

### Criterios de aceptación

- Una entrada Usuarios permite encontrar alta, ficha, organización, accesos,
  perfiles generales y salud de datos sin recorrer pestañas principales
  desconectadas; cada operación existente conserva su alcance y validaciones.
- Cambiar centro, departamento o cargo no modifica roles de Biblioteca o
  Planillas ni los permisos de otra empresa. Mover un editor no borra su dato.
- Los accesos se respetan tanto al navegar como al guardar, incluidos usuarios
  inactivos y restricciones administrativas. Los filtros y la persona elegida
  mantienen un contexto coherente al cambiar de sección.
- Web: lista/tabla con filtros y detalle de la persona aprovechando el ancho.
  Móvil: lista compacta, ficha y acciones por tarea. Compartir lógica,
  empresa y permisos; diferenciar presentación y navegación.
- Verificar alta y edición, roles/perfiles, diagnósticos, cambio de empresa y
  navegación en escritorio y teléfono con las pruebas pertinentes.

### Entrega y seguimiento

- **Codex:** implementación local verificada. La entrada Usuarios reúne
  Personas, Crear usuario, Roles y permisos, Perfiles generales, Salud usuarios,
  Salud cargos, Membresía, Multiempresa y Migraciones de usuarios. Web usa
  navegación lateral interna y tabla paginada con ficha lateral cuando hay
  espacio; en escritorio estrecho la ficha abre en diálogo y al ir a permisos
  se cierra ese diálogo. Móvil usa selector de tarea y fichas compactas. La sección elegida
  se conserva al recargar. La ficha da acceso a edición, organización,
  asignación de módulos, roles y perfil; los roles ya no se guardan desde
  Organización. Los perfiles tienen su sección de catálogo y asignación.
  Desde Apps > Gestionar, los módulos reconocidos llevan a esta misma vista
  de accesos; las apps personalizadas conservan su editor existente.
  Al cambiar de empresa se limpia la persona seleccionada y los datos de
  mantenimiento de la anterior; respuestas tardías de Membresía y Salud cargos
  no repueblan ese contexto. El diagnóstico y la unificación de cargos usan
  la empresa seleccionada.
- **Archivos de Codex:** `lib/admin/admin_dashboard_screen.dart`, nuevo
  `lib/admin/admin_users_workspace.dart`, nuevo
  `lib/admin/admin_users_directory.dart`, integración de alta en
  `lib/talento_humano/zeus_export_screen.dart` y opción de alta exclusiva en
  `lib/talento_humano/zeus_export_service.dart`.
- **Contrato de alta para revisar por Claude:**
  `ZeusExportService.createBasicUser(..., soloNuevo: true)` valida identificación,
  nombre y empresa y crea mediante transacción; si la cédula ya existe rechaza
  la operación sin modificar identidad, empresa principal, estado o perfil.
  La nueva entrada Admin usa esta opción. El flujo anterior de Zeus conserva
  su comportamiento por defecto. Revisar junto a las reglas y fuentes de
  identidad antes de ampliar el alcance de altas/sincronización.
- **Claude:** pendiente de respuesta en esta sección con revisión técnica,
  contrato y archivos que tomará.

### Validación final de Codex

- `flutter test --no-pub test/admin test/utils/user_company_test.dart
  test/core/multiempresa_sync_test.dart`: **77 pruebas aprobadas**, incluidas
  **11 nuevas** en `test/admin/admin_users_workspace_test.dart`,
  `admin_users_directory_test.dart` y `admin_user_creation_test.dart`.
- Las pruebas nuevas verifican selección de tareas en Web/móvil, montaje solo
  de la herramienta elegida, escritorio estrecho, ficha de la persona correcta,
  cierre del diálogo al navegar, paginación, alta en la empresa elegida,
  rechazo de identidad existente y de un alta competidora e identificación
  inválida sin escrituras.
- Analizador sobre los archivos modificados y `test/admin`: sin errores;
  conserva un warning y cinco avisos informativos anteriores del dashboard
  (método de sesiones sin uso, estilo de nulos/nombre local y Radio deprecado).
  `git diff --check`: correcto.
- La protección del alta se probó con dobles de Firestore ejecutando el servicio
  real; estas pruebas no certifican autorización ni reglas del servidor. La
  revisión de reglas/sincronización queda explícitamente para Claude aquí.
  No se modificaron reglas, no se ejecutaron operaciones sobre datos reales
  ni se publicó una compilación.

---

## Visitas: el profesional recibía permission-denied — 28 sep 2026 (Claude)

- **Causa**: en las reglas de `TBL_VISITAS`, el caso del profesional (su
  propia visita) iba al final, después de los chequeos de Desarrollo, jefe y
  Gerencia. Con `belongsToCompany` más completo (personal inhabilitado), a él
  se le evaluaba todo eso y la consulta de Mis visitas pasaba el tope de 1000
  expresiones por petición: Firestore la negaba.
- **Arreglo**: `esVisitaPropiaDelProfesional()` va primero en `get` y `list`,
  y su rama va primero en `update` (llenar, guardar avance, iniciar, cerrar).
  La lista de formatos y `participaEnVisitas` miran el rol antes que
  Desarrollo y Gerencia por ficha. Nadie gana ni pierde permisos: solo cambia
  el orden.
- Pruebas: `functions/test/visitas_fecha.rules.js` (Mis visitas, abrir, guardar
  avance y formatos con una ficha multiempresa; otro profesional no ve ni toca).
- Despliegue: `firebase deploy --only firestore:rules`.

## Nutrición: los datos de salud quedan en su empresa — 28 sep 2026 (Claude)

Ronda "módulo por módulo". Pacientes, valoraciones, patologías, historial,
derivaciones y alertas son datos de salud, y solo pedían sesión:
cualquiera, de cualquier empresa, los leía y escribía (10 colecciones con
`isSignedIn()` y 7 más en la regla general).

- Las 16 colecciones de Nutrición van por empresa, con la regla de
  inhabilitados: se lee, crea, cambia y borra solo en la propia empresa, y
  un documento no cambia de empresa (`nutricionDeSuEmpresa`).
- `TBL_HISTORIAL_NUTRICION/{empresa}-{paciente}/registros`: su consulta no
  filtra por empresa, así que la empresa sale del id (los códigos de
  empresa no llevan guion). Se agrega y no se reescribe.
- Las citas las sigue consultando el calendario de Inicio de todo el
  personal: su consulta ya filtra por empresa.
- De paso se cierra un choque entre empresas: dietas y patologías usan el
  código como id (`TBL_DIETAS/{codigo}`), y guardar la dieta "D1" en una
  empresa le pisaba la "D1" a la otra. Ahora la regla lo rechaza. Si dos
  empresas llegan a usar Nutrición con los mismos códigos, hay que pasar a
  `{empresa}_{codigo}` (la carga inicial de dietas ya lo hace).
- No se exige tener el módulo asignado: la lista de módulos vive en la
  ficha del usuario, que todavía puede escribir cualquiera (P0).

Solo cambian las reglas. **Despliegue:** `firebase deploy --only firestore:rules`.

**Pruebas:** `functions/test/nutricion.rules.js` (6; contra las reglas
anteriores fallan 5, la que pasa es la de control). Todas las de reglas:
77 aprobadas, 2 omitidas, también con la comprobación de habilitado
duplicada.

### Compras: lo que hay que resolver antes de cerrarle las reglas

Revisado para la misma ronda y dejado para Codex, que es dueño de
`lib/compras`. Hoy todo Compras está en la regla general, incluido
`TBL_COMPRAS_ROLES`: cualquiera con sesión puede darse el rol de admin.

1. **Dos consultas no filtran por empresa** y fallarían con reglas por
   empresa: `compras_service.dart:482` (abastecimiento por `recepcionId`) y
   `compras_aprobaciones.dart:299` (aprobaciones por `entidadId`). Hay que
   agregarles `.where('empresaId', isEqualTo: …)`.
2. **El rol no siempre está donde las reglas lo pueden ver.**
   `getRolUsuario` busca el rol por consulta (cualquier id) y, si no hay,
   `_inferComprasRolFromUserData` lo deduce de la ficha: `rolCompras`,
   `roleKey`, `role`, `rol` o el **cargo** ("Director de Calidad",
   "Almacenista"…). Las reglas solo pueden leer
   `TBL_COMPRAS_ROLES/{empresa}_{usuario}`. Antes de reglas por rol, cada
   persona de Compras necesita su documento con ese id; si no, quien hoy
   entra por el cargo se queda sin permisos.
3. Con eso listo, las reglas siguen el patrón de Rutas: lectura por
   empresa, escritura por rol, y roles asignados solo por Desarrollo o el
   admin de Compras.

## Rutas: reglas por empresa y por rol — 28 sep 2026 (Claude)

Ronda "módulo por módulo" (Codex va con Correspondencia). Rutas estaba
entero en la regla general, así que cualquiera con sesión, de cualquier
empresa, podía:
- darse el rol de administrador de Rutas (`TBL_RUTAS_ROLES`);
- leer las claves de Google y TomTom del estudio de movilidad
  (`TBL_RUTAS_MOV_CONFIG.apiKeyGoogle` / `apiKeyTomtom`);
- ver la ubicación en vivo de los conductores y aprobar sus fotos.

Solo cambian las reglas y la copia de roles al crear una empresa; las
pantallas de Rutas no se tocaron.

**Quién hace qué** (roles en `TBL_RUTAS_ROLES/{empresa}_{usuario}`; el
desarrollador de la app y el rol `desarrollador` de Rutas entran a todo):
- Roles: la lista la lee cualquiera de la empresa (Administración la carga).
  Los asigna Desarrollo, o el administrador de Rutas a otras personas: no se
  cambia a sí mismo ni da o quita "desarrollador".
- Rutas, establecimientos, placas, configuración y asignaciones: los lee la
  empresa, los escribe Administración de Rutas (`admin`, `admin_calidad`).
  La configuración base la puede crear quien habilita el módulo.
- Talento Humano, al inhabilitar, cierra la asignación del conductor o
  retira al ayudante sin tener rol en Rutas: ese cierre exacto
  (`cerradaPor` / `ayudanteRetiradoPor` = `inhabilitacion_talento_humano`)
  lo puede escribir cualquiera de la empresa; nada más.
- Evidencias y resumen diario: los ve quien tiene rol en Rutas. El
  conductor sube la suya a su nombre, en pendiente, y repite solo la
  rechazada. Calidad aprueba o rechaza sin tocar la foto. Borrar: solo el
  perfil de desarrollo.
- Ubicaciones: el centro de control (Administración) y cada conductor la
  suya.
- Estudio de movilidad (configuración con las claves, horarios, mediciones,
  corridas): solo Administración de Rutas.

**La copia de roles al crear una empresa usaba un id que las reglas no
encuentran.** `CompanyTransitionService` copiaba los roles como
`{nueva}_{origen}_{usuario}`; las reglas buscan `{empresa}_{usuario}`. Ya
pasaba con Interventoría y Correo: la persona veía el rol en la pantalla y
el servidor le negaba el permiso. Ahora usa `idRolEnEmpresa`
(`test/admin/id_rol_en_empresa_test.dart`).

**De paso:** la regla general excluía las colecciones con una cadena de 28
`!=`; ahora es una lista con `in` (41 colecciones, con las de Rutas).

**Antes de desplegar:**
- En la consola, `TBL_RUTAS_ROLES`: los roles copiados por "Crear empresa y
  trasladar" antes de este cambio tienen id `{nueva}_{origen}_{usuario}` y
  dejan de dar permiso. Se arreglan volviendo a guardar el rol en
  Administración (escribe `{empresa}_{usuario}`).
- Asignar roles de Rutas desde Administración ahora exige ser Desarrollo o
  administrador de Rutas, como ya pasaba con Interventoría.

**Despliegue:** `firebase deploy --only firestore:rules`. La copia de
roles es de la app: entra con la próxima publicación.

**Pruebas:** `functions/test/rutas.rules.js` (11; contra las reglas
anteriores fallan 10). Todas las de reglas: 71 aprobadas, 2 omitidas, y
siguen pasando con la comprobación de habilitado duplicada a propósito
(margen en el tope de 1000 expresiones). Flutter: 1.109 aprobadas.

**Pendiente:** las fotos viven en Storage y sus reglas no están en el
repositorio (se manejan en la consola); conviene revisarlas con el mismo
criterio.

## Reglas de Firestore: el inhabilitado tampoco entra por la base — 28 sep 2026 (Claude)

La app y Functions ya no dejaban entrar a un inhabilitado, pero las reglas no
lo sabían: con la sesión abierta (o una app vieja, sin el vigilante) seguía
leyendo y escribiendo los datos de la empresa directo en Firestore. Solo se
tocó `firestore.rules`; la app y Functions no cambian.

- `habilitadaEn` en las reglas, espejo de `personaHabilitadaEn`
  (`lib/utils/user_company.dart`) y de `functions/src/acceso.ts`. No pasa
  quien tiene la cuenta apagada (`activo: false`, o `estado`/`status` global
  distinto de activo), quien está inhabilitado ahí por Talento Humano
  (`estadoLaboral`, o `estado`, = inactivo) ni quien tiene la empresa apagada
  por un traslado. Si sigue habilitado en otra empresa, entra solo a esa.
- `belongsToCompany` la exige, así que cubre todo lo que ya estaba por
  empresa: Interventoría, Visitas, Correspondencia, Biblioteca, Planillas y
  datos bancarios.
- El desarrollador no se salta la regla, igual que en `AccessGuard`:
  `isDeveloper` exige la cuenta habilitada, `isDeveloperIn` la empresa, y las
  reglas que no pasaban por `belongsToCompany` (roles de Interventoría y
  Correo, tipos documentales, ubicaciones de Visitas) usan `isDeveloperFor`.
- **Tope de 1000 expresiones.** Visitas evaluaba `belongsToCompany` hasta
  cuatro veces por petición y con la regla nueva se pasaba del tope. Las
  funciones terminadas en `En` (`administraVisitasAreaEn`,
  `gerenciaVisitasEn`, `rolVisitasEn`…) no vuelven a mirar la empresa y se
  usan dentro de una regla que ya la miró; el `update` de `TBL_VISITAS` la
  mira una sola vez arriba. Lo que permite cada regla no cambia. Con la
  comprobación nueva duplicada a propósito siguen pasando todas las pruebas:
  quedó margen.

**Despliegue:** `firebase deploy --only firestore:rules`.

**Pruebas:** `functions/test/inhabilitados.rules.js` (9; contra las reglas
anteriores fallan 8). Con el emulador:
`firebase emulators:exec --only firestore "cd functions && node --test test/*.rules.js"`
→ 60 aprobadas, 2 omitidas a propósito.

**Lo que las reglas NO cubren todavía** (decisión aparte, no es de este
cambio):
- La regla general `/{collection}/{document=**}` (Tareas, Usuarios, Compras,
  Talento Humano…) solo pide sesión: ni empresa ni estado. Quien queda
  inhabilitado en todas sus empresas conserva hasta una hora ahí, hasta que
  vence su sesión (Functions se las revoca en ese momento); quien sigue
  habilitado en otra empresa no pierde la sesión y sigue viendo esas
  colecciones completas. Cerrarlo pide leer un documento más en cada
  petición de toda la app y filtrar por empresa esas colecciones.
- Cualquiera con sesión puede escribir `TBL_USUARIOS`, incluida su propia
  ficha: podría volver a habilitarse o darse un rol. Es el P0 de "Seguridad
  transversal"; hay que acordar con Codex quién escribe qué en Usuarios antes
  de cerrarlo.

## Visitas: Google Maps y subcentros como establecimiento — 28 sep 2026 (Claude)

Pedido: "que se busquen los lugares con Google Maps (busco Buen Pastor, sale
cuál es, lo selecciono y trae los datos), que los subcentros se puedan
agregar como visitas, y que esté relacionado al generar y asignar la visita".
Versión 2.6.9 (23).

### Ubicaciones (Desarrollo y Gerencia)
- **Buscar en Google Maps**: la búsqueda va por la función
  `visitasBuscarLugar` (Places API New, Text Search), así sirve igual en web
  y en el teléfono y la clave no queda en la app. Orienta la búsqueda hacia el
  centro (50 km) cuando ya tiene ubicación. Al elegir un resultado se llenan
  dirección, ciudad y coordenadas, y se guarda el lugar de Google (`placeId`,
  `nombreGoogle`) para abrirlo exacto después.
- **Mapa** en el diálogo: marcador que se arrastra, círculo con el radio
  permitido, tocar el mapa mueve el punto, y "Abrir en Google Maps".
- **Agregar subcentro** desde la fila del centro: queda en el maestro de
  centros de costo (`TBL_CENTROS_COSTOS.subcentros`, el mismo de
  Administración), sin nombres repetidos, y enseguida se le busca la
  ubicación. Un subcentro sin ubicación propia usa la del centro.
- Si Google rechaza la búsqueda (clave o API sin habilitar), el diálogo dice
  exactamente qué falta.

### Equipo > Grupos
- Cada establecimiento muestra debajo sus subcentros activos. Marcar el
  centro es todo el sitio (sus subcentros quedan incluidos); se puede marcar
  solo un subcentro (`centroIds` guarda `centro|subcentro`, la misma clave
  de la visita). Buscar un subcentro trae su centro.

### Agregar visitas
- Un solo desplegable con el centro y, debajo, sus subcentros (solo los del
  grupo del profesional; un centro entero trae los suyos). La visita queda
  con `centroId` y `subcentroId`.
- Cada día dice la **dirección** que quedó en Ubicaciones, o avisa "sin
  ubicación: no se podrá iniciar", y arriba cuántos días están así.

### Iniciar visita
- El recuadro de la ubicación de referencia muestra el lugar y la dirección,
  con **Cómo llegar (Google Maps)**.

### Despliegue
- `firebase deploy --only functions:visitasBuscarLugar,hosting`. Las reglas
  no cambian.
- La clave es **la misma de Rutas**, en el mismo orden que usa Rutas: la de
  la empresa (Rutas > Estudio movilidad > Programación) y si no,
  `MOVILIDAD_GOOGLE_API_KEY` del backend. `VISITAS_GOOGLE_API_KEY` solo si se
  quiere una aparte. En Google Cloud esa clave debe tener habilitada también
  **Places API (New)** (Rutas usa Routes API), y agregarla a sus
  restricciones de API si las tiene.

### Pruebas
- `test/visitas/visitas_ubicaciones_test.dart`: buscar y elegir el lugar,
  error de Google, agregar subcentro en el teléfono, claves de
  establecimiento, ubicación que aplica, enlace de Maps.
- `test/visitas/visitas_programar_equipo_test.dart`: subcentros en el grupo
  y al programar, dirección y aviso sin ubicación, teléfono.
- `functions/test/visitas_lugares.test.js`: lectura de la respuesta de
  Places.

## Visitas: documento "Cambios módulo visitas" — 28 sep 2026 (Claude)

Revisión punto por punto del documento que envió la dirección. Versión 2.6.5
(19).

### Cronograma
- El filtro de todo acceso dice **Departamento** y lista los departamentos de
  la empresa (`TBL_AREAS`), no las áreas que traían los formatos ("SST / HSE",
  "Desarrollo"). Una visita vieja en un área que no es departamento sigue
  saliendo en la lista, para no esconderla.
- Agregar visitas (`visitas_programar.dart`):
  - Solo salen los **profesionales de visita** del departamento (rol
    Profesional con el departamento exacto). El director ya no se asigna a
    sí mismo como "prueba".
  - Solo salen los **establecimientos del grupo** del profesional (Equipo >
    Grupos y establecimientos), no todos. Sin grupo, lo dice y no programa.
  - **Sin formato**: la visita queda en el departamento del profesional y él
    escoge el formato al iniciarla (`programarVarias`,
    `asignacionVisitaValida` en reglas acepta `formatoId` vacío; una app
    vieja que lo mande sigue pasando si la copia coincide).
- El jefe ve arriba las **solicitudes de cambio de fecha** con Aprobar /
  Rechazar (rechazar exige motivo); también en el detalle de la visita.

### Formatos
- El director ve los formatos de su departamento y el encabezado lo dice.
  Por qué el de Talento Humano no veía nada: el SST estaba en "SST / HSE"
  (`hse`), que no es un departamento. Ahora:
  - Desarrollo y Gerencia ven marcado en rojo todo formato cuya área no es
    un departamento, y en el editor lo pasan a uno (**Departamento del
    formato**, también en formatos ya creados). Reglas: mover un formato
    exige administrar los dos departamentos.
  - "Cargar formato SST oficial" pregunta el departamento (propone Talento
    Humano); el director lo carga en el suyo.
- Nuevo formato: los **cargos dependen del departamento** elegido
  (`cargosDeArea`: los de `TBL_CARGOS` con ese departamento más los del
  personal que trabaja en él). Al cambiar de departamento se limpian.
- Los profesionales no crean formatos: la pestaña y las reglas son solo del
  director, Gerencia y Desarrollo (sin cambios, se verificó).

### Equipo
- Personal es **de consulta**: el rol viene de Administración > Roles y
  permisos y el departamento de la ficha; ya no se editan aquí. Se quitó el
  diálogo que dejaba cambiar rol y departamento (el caso de un Profesional
  que terminó como jefe de otro departamento). Si el departamento del rol no
  coincide con el de la ficha, lo advierte.
- Las tarjetas por departamento dicen en palabras: director, profesionales
  de visita y quiénes no tienen grupo ("no se les puede programar").
- Grupos que no aparecían y "Nuevo grupo" sin establecimientos: la pestaña
  desmontaba las consultas al recargar. Ahora la de grupos queda siempre
  montada (con error visible si falla) y el diálogo lee los establecimientos
  por su cuenta, con carga y reintento. El departamento del grupo ya no se
  vuelve a escoger para el director.
- El filtro de roles desbordaba la fila en el teléfono: ancho fijo.

### Consolidado
- **Un departamento a la vez** ("no combinar informe por áreas"): Gerencia,
  Desarrollo y Consulta lo eligen; el director ve el suyo.
- El **profesional** tiene la pestaña con **solo sus actas**.
- PDF: "DEPARTAMENTO" en vez de "ÁREAS"; la tabla por departamento solo sale
  si llegan varios.

### Visita (profesional)
- **Elige la visita**: Registro de visita lista las de hoy, las en curso y
  las que pasaron sin hacerse (`visitasParaRegistro`); "¿Dónde estoy?" queda
  como ayuda.
- Al iniciar **escoge el formato** entre los de su departamento que aplican
  a su cargo (`formatosParaVisita`); sin formatos, lo dice.
- **Mismo día**: se inicia solo el día programado (`visitaSePuedeIniciar`,
  `motivoNoIniciaHoy`) y se cierra ese mismo día (`motivoNoCierraHoy`). Las
  reglas lo exigen con la hora del servidor (`enElDiaDeLaVisita`: de la
  medianoche programada a 24 h después). Las pruebas no tienen la
  restricción.
- **No puede estar en otra ubicación**: el GPS se verifica al iniciar (ya
  estaba) y ahora también al cerrar (`verificarUbicacionInicio(accion:
  'cerrar')`).
- **Grabar parcialmente**: cada respuesta ya se guardaba; la barra lo dice
  ("lo que respondes se guarda solo") y "Guardar avance" sigue.
- **Pedir cambio de fecha al jefe inmediato** (`VisitaSolicitudFecha`,
  `solicitarCambioFecha` / `responderCambioFecha`): el profesional ya no
  reprograma. Aprobar una visita que se inició y no se cerró la devuelve a
  programada en la fecha nueva: conserva las respuestas, pero inicio y
  firmas se hacen de nuevo. Reglas: el profesional solo escribe una
  solicitud pendiente a su nombre, y no otra mientras esa espera; el jefe
  la rechaza o la aprueba.

### Pruebas
- Dart: `visitas_fecha_test.dart` (modelo) y
  `visitas_programar_equipo_test.dart` (pantallas, escritorio y teléfono);
  Visitas 131 verdes.
- Reglas: `visitas_fecha.rules.js` (programar sin formato, formato al
  iniciar, mismo día, solicitud y aprobación, mover formato); 49 verdes, 2
  omitidas de antes.

---

## Publicación web: no se sube una compilación vieja — 27 sep 2026 (Claude)

Caso: con `main` en la 2.6.2 (16), se publicó y to-do-gestion.com seguía
diciendo 2.6.1 (15). `firebase deploy --only hosting` sube lo que haya en
`build/web` sin compilar: si `flutter build web` no corrió o falló, sale la
anterior sin ningún aviso.

- El hosting tiene `predeploy`: `tool/verificar_build_web.js` compara
  `build/web/version.json` con la versión de `pubspec.yaml` y detiene la
  publicación, con la instrucción de compilar, si no coinciden o si no hay
  compilación.
- Probado con build igual (pasa), vieja y ausente (se detiene), también como
  lo ejecuta Firebase CLI (cross-env, directorio del proyecto).

---

## Visitas: Gerencia por cargo, sin tener que asignar el rol — 27 sep 2026 (Claude)

Caso: tras publicar, en Admin › Roles y permisos › Visitas no aparecía
"Gerencia" y a Oscar seguía sin salirle nada. La lista sale del código, así
que lo publicado no traía la rama; pero además el rol dependía de que alguien
se lo diera.

- Quien tiene cargo de Gerencia ("Gerencia", "Gerente general"…, no
  "Subgerente") o el rol de la app `gerencia` / `gerente` entra a Visitas
  como Gerencia aunque su rol guardado sea otro o ninguno
  (`resolverRolVisitas`, `VisitasService.rolVisitasDeUsuario`). El cargo es el
  primero con texto entre `cargoNombre` y `cargo` de la empresa y luego los de
  la raíz, como lo muestra Administración (`cargoDeFicha`).
- Reglas: `esGerenciaPorFicha` con el mismo criterio, al final de cada `||`
  (el primer intento pasaba el tope de 1000 expresiones y le negaba a un jefe
  asignar profesionales; el emulador lo pilló). También entra en
  `administraVisitas`, así Oscar lee ubicaciones, grupos y roles.
- `visitasEliminarFormato` / `visitasEliminarPrueba` lo reconocen igual.
- Admin muestra en la fila de Visitas "Por su cargo entra a Visitas como
  Gerencia".
- Versión 2.6.2 (16): en el menú lateral se ve si el navegador ya carga la
  build nueva.
- Ojo, ya existía: `TBL_USUARIOS` cae en el comodín de las reglas, así que
  cualquiera con sesión puede editar cualquier ficha (hasta
  `desarrollador: true`). El cargo hereda esa debilidad; no la agrava.
- Pruebas: Dart 118 de Visitas; reglas 41 verdes (2 omitidas de antes),
  con Gerencia por cargo, subgerente denegado y cargo de empresa sobre raíz.

---

## Visitas: formatos como Google Forms / Excel, acta fija, anexos, Gerencia y consolidado por fechas — 26 sep 2026 (Claude)

Pedido del módulo de Visitas, punto por punto.

**Plantilla y "elementos".** La plantilla que se descargaba mostraba los
códigos `calificacion / si_no / elemento` y nadie sabía qué era "elemento".
- Tipos en palabras (`kItemTiposLabel`) con su explicación
  (`kItemTiposAyuda`): Cumple / No cumple / No aplica · Sí / No · Sí / No con
  cantidad y vencimiento (el "elemento" de antes, el del botiquín) · Lista de
  opciones · Respuesta corta · Párrafo · Número · Fecha. Los cuatro últimos
  son de formulario: guardan `VisitaRespuesta.valor`, no califican (no
  cuentan en el %) y nunca son hallazgo; pueden ser opcionales
  (`VisitaFormatoItem.obligatoria`) y llevar ayuda (`ayuda`).
- `assets/visitas_plantilla_formato.xlsx` nueva, generada con
  `tool/visitas_plantilla_formato.py` (openpyxl): hojas Instrucciones,
  Preguntas (listas desplegables en palabras), Tablas, Ejemplo preguntas y
  Ejemplo tablas. Los códigos viejos se siguen aceptando al importar.

**Subir cualquier Excel y adaptarlo** (`visitas_formato_excel.dart`).
`leerFormatoVisitasExcel` lee la plantilla tal cual; si el archivo no es la
plantilla lo adapta: busca la columna de preguntas ("Parámetros de
evaluación", "Pregunta", "Aspecto", "Descripción"…), la de secciones ("Items
a evaluar", "Sección"…), títulos en mayúscula como sección, salta subtotales
y firmas, toma CÓDIGO / VERSIÓN / ELABORACIÓN del encabezado y, con varias
hojas, cada hoja es una parte del formato (como el Excel de SST). Siempre
abre el editor para revisar antes de guardar, con los avisos de lo que se
supuso. "Pegar desde Excel" en el editor usa el mismo adaptador.

**Editor** (`visitas_formato_editor.dart`, nuevo; reemplaza al de la
pantalla). Tarjetas como Google Forms (tipo con ícono, vista previa de cómo
lo verá el profesional, ayuda, obligatoria, foto, duplicar, mover) o vista
Tabla como Excel; 20 preguntas por página; "Sección", "Pegar desde Excel",
"Agregar desde un Excel". Pregunta antes de salir sin guardar.
- **Tablas**: ahora se crean y editan (antes solo venían del SST): nombre,
  cómo se llama cada fila, columnas para escribir, columnas para calificar,
  **escala** (`kEscalasLabel`: B/M/R/NC, Cumple/No cumple/NA, Sí/No) y
  **filas fijas** (cuadrícula: Cocina, Bodega…; el profesional las califica
  y no agrega otras). Los códigos de estado no se repiten entre escalas
  (`CU`, `NCU`, `NA`, `SI`, `NO`) para que "¿es hallazgo?" siga sin depender
  de la tabla.
- **Encabezado del informe** por formato: sistema de gestión, código,
  versión y fecha de elaboración (`VisitaFormato.codigo/versionDocumento/
  elaboracion/sistema`); con partes, cada parte el suyo.
- Ojo, reglas: `asignacionVisitaValida` compara `formatoAsignado.items`,
  `partes` y `tablas` con los guardados campo por campo. Los campos nuevos
  de ítems y tablas solo se escriben si no son los de siempre, así un
  formato viejo copiado sigue siendo idéntico (prueba en
  `visitas_formulario_test.dart`).

**El acta: "Profesional", no "Responsable", y datos fijos.**
- Firma y datos dicen "Profesional que realiza la visita" (pantalla y PDF).
- Nombre y cargo del profesional salen de su ficha
  (`cargoProfesionalDeActa`; sin cargo en la ficha, "Profesional de <área>")
  y no se editan ni al firmar. La ciudad sale del maestro de ubicaciones y
  queda fija. El responsable del establecimiento elegido de la lista queda
  fijo con nombre y cargo de su ficha (menú: elegir otro o escribirlo a
  mano si no es usuario); solo el escrito a mano se corrige al firmar.
- Observaciones generales resaltadas (ámbar) y con **Dictar**; el dictado
  ahora se suma a lo escrito en vez de reemplazarlo (también en las
  observaciones de cada ítem y en respuestas de párrafo).
- **Evidencias adicionales** opcionales al final
  (`VisitaProfesional.evidenciasAdicionales`, con descripción).
- **Marca de agua** en todas las fotos de la visita
  (`visitas_marca_agua.dart` sobre `rutas_watermark.dart`, que ganó `acento`
  y `marcaDiagonal`): banda con logo, área, establecimiento, fecha y hora,
  profesional y GPS del inicio, más el establecimiento y la fecha en
  diagonal sobre la foto.

**Informes PDF** (`visitas_informe_pdf.dart`).
- Todos con el encabezado del SST: logo, sistema de gestión, empresa,
  nombre del formato y código / versión / página / elaboración (antes solo
  el SST). DATOS con PROFESIONAL, hora de inicio y cierre y distancia.
- Respuestas de formulario en "Información registrada"; tablas con su
  escala y filas fijas; "Mejora y seguimiento" en todos los informes.
- Observaciones generales destacadas y sin partirse entre páginas.
- Firmas con espacio: firma, línea, NOMBRE y cargo centrados, fecha y
  equipo (antes celdas grises apeñuscadas).
- **Anexos · Registro fotográfico**: las fotos de ítems, filas y adicionales
  incrustadas (dos por fila, con pie), bajadas por el SDK de Storage
  (`VisitasService.bytesEvidencia`) y reducidas a 1100 px si pesan más de
  450 KB. Las que no bajen salen como enlace.
- Texto saneado a Latin-1 (`_s`): comillas tipográficas, guiones largos y
  "…" ya no dejan huecos.

**Gerencia (don Oscar) ve y hace todo, como Desarrollo.** Rol nuevo de
Visitas `gerencia` ("Gerencia (ve y administra todo)"), sin área:
`visitasTodoAcceso` le abre cronograma, formatos, equipo y consolidado de
todas las áreas y el maestro de ubicaciones.
- Reglas: `esGerenciaVisitas`; entra en `administraVisitas` y
  `administraVisitasArea` (todas las áreas), lista todos los formatos,
  escribe ubicaciones, nombra jefes, profesionales, consulta y firmantes,
  pero no otra Gerencia ni se cambia a sí misma (eso es de Desarrollo).
- `visitasEliminarFormato` / `visitasEliminarPrueba` la aceptan como a
  Desarrollo (`functions/src/visitas_cleanup.ts` + `lib/`).
- Admin › Roles y permisos › Visitas describe el rol; el calendario del
  Home le muestra las visitas que programa.
- **Hay que asignarle a Oscar el rol "Gerencia"** en Admin › Roles y
  permisos › Visitas (lo asigna Desarrollo).

**Ubicaciones y filtros.** El maestro de ubicaciones queda para Desarrollo y
Gerencia (`visitasPuedeGestionarUbicaciones`). "Mis visitas" gana buscador,
estado (incluida "Vencidas"), rango de fechas y establecimiento
(`filtrarVisitas`); el Cronograma, para quien ve todas las áreas, filtra
por área, profesional y establecimiento.

**Consolidado por fechas, combinado y con colores**
(`visitas_consolidado.dart`, nuevo). Periodo libre con atajos (este mes,
anterior, 7 y 30 días, año) y una o varias áreas a la vez; cada área tiene
su color (`kPaletaAreasVisitas`, `indiceColorAreas`) igual en pantalla y
PDF. `consolidarMes` ganó `porArea` y `separarPorArea` (un establecimiento
por área al combinar) y toma el texto de los ítems de la copia del formato
de la visita. El PDF trae KPIs, tabla y barras por área, establecimientos,
lo que más se incumple y el detalle, todo con el color del área; con
"Incluir las actas completas" van detrás las actas del periodo, cada una
con la franja del color de su área ("ACTA 2 DE 12 · NUTRICIÓN · …").

**Pruebas.** `test/visitas/visitas_formulario_test.dart` (nuevo: Gerencia,
tipos de formulario, escalas y filas fijas, compatibilidad con las reglas,
consolidado por área, filtros y generación de los PDF),
`visitas_formato_excel_test.dart` (plantilla nueva, ejemplo, adaptar Excel
libre, pegar) y `visitas_formato_editor_test.dart` (el editor en teléfono y
escritorio sin desbordes); Visitas: 116 verdes, toda la app: 995. Reglas:
`functions/test/visitas_gerencia.rules.js` (6 casos) y todas las demás en el
emulador, 40 verdes (2 omitidas que ya lo estaban).

**Para desplegar:** `firestore.rules` y `firebase deploy --only
functions:visitasEliminarFormato,functions:visitasEliminarPrueba`; sin las
reglas, Gerencia recibe permission-denied y las evidencias adicionales no se
guardan. Luego asignar el rol Gerencia a Oscar.

---

## Subsanaciones muestra a quien de verdad tiene la tarea — 26 sep 2026 (Claude)

Caso: el jefe directo recibía la tarea del hallazgo, la reasignaba a alguien
de su equipo desde "Mis tareas", y Subsanaciones lo seguía mostrando a él
como responsable.

- Adelante: `onTaskUpdated` (Cloud Functions) actualiza `responsableId`,
  `responsableNombre` y `cargoResponsable` del hallazgo cada vez que cambia
  `asignado_uid` de una tarea de Interventoría, por cualquier camino
  (`functions/src/interventoria_task_sync.ts`). El cliente ya lo hacía al
  reasignar desde "Mis tareas"; esto cubre el resto.
- Lo que ya quedó mal: Maestro › Revisión muestra arriba "N hallazgos
  muestran a alguien que ya no tiene la tarea" con el botón **Actualizar
  responsables**. Solo corrige el hallazgo; no toca tareas ni avisa a
  nadie.
- Requiere `firebase deploy --only functions` para la parte automática.

---

## Reasignar tareas de Interventoría sin área — 26 sep 2026 (Claude)

Caso: SST tenía el hallazgo de los EPP (Buen Pastor 12.1), los entregó pero
el administrador no los usa, y al reasignarle la tarea salía "La tarea no
tiene área definida para reasignar".

- Causa: los hallazgos del acta no traen área y la tarea nacía con
  `areaId` vacío; "Reasignar" (Mis tareas) exigía área.
- Reasignar ahora ofrece "Todas las áreas" y abre ahí cuando la tarea no
  tiene área: se busca a la persona por nombre o cargo.
- Las tareas nuevas de Interventoría toman el área del responsable cuando
  el hallazgo no la tiene.
- Al reasignar una tarea de Interventoría se actualiza también el hallazgo
  (`responsableId`, `responsableNombre`, `cargoResponsable`): antes la
  tarea pasaba a la otra persona y Subsanaciones seguía mostrando a la
  anterior.

---

## Maestro › Revisión: cambiar la persona de una sede desde ahí — 26 sep 2026 (Claude)

Pedido: "poder editar desde ahí, seleccionar a otra persona, más grupal" y
ver el centro de operación y de trabajo para asignar.

- La matriz dice qué CARGO responde; la persona es quien tiene ese cargo y
  cubre la sede (centros de operación, de trabajo o grupo de Interventoría,
  lo que guarda Talento Humano › Estructura organizacional). Cambiar a la
  persona de una sede = cambiar esa cobertura.
- Por establecimiento: cada fila tiene un lápiz para "quién responde" y
  "quién aprueba". El diálogo lista a quienes tienen el cargo con su
  cobertura ("Grupo G1 · Opera en … · Trabaja en …"), permite cubrir **solo
  esa sede** (se agrega a sus centros de operación) o **todo el grupo** (se
  agrega el grupo: un coordinador de calidad por grupo), y quita la sede a
  quien la cubría con el mismo cargo. Antes de guardar muestra cómo queda
  (`planearCambioEnSede`), y avisa si alguien la sigue cubriendo por su
  grupo o su centro de costo.
- Se guarda en `TBL_USUARIOS` (lo que lee la asignación) y en los espejos
  de Talento Humano (`TBL_ESTRUCTURA_ORGANIZACIONAL`, `TBL_EMPLEADOS`), con
  las listas completas por empresa (`aplicarCambiosCobertura`).
- Cada sede muestra su grupo y hay filtro por grupo. Las reglas sin cargos
  (actas con catálogo propio sin llenar) salen en un solo aviso y ya no
  marcan a todas las sedes.
- "Quiénes lo tienen" (Cargos del maestro) muestra la cobertura de cada
  persona.

---

## Notificaciones de Interventoría, calendario y Maestro › Revisión — 25 sep 2026 (Claude)

Origen: con la asignación automática de Interventoría "empezaron a llegar las
notificaciones a todo el mundo de una"; a Daniel y a Kary les salían en el
calendario hallazgos "por recibir" que reciben los aprobadores.

**Causas encontradas**
- La reparación del rezago (`asignarHallazgosPendientesAutomaticamente`)
  corría sola cada vez que un revisor abría el módulo: creaba de golpe las
  tareas de todas las sedes y cada tarea mandaba dos avisos con sonido
  (responsable y aprobador).
- El creador de esas tareas era quien abría la pantalla, y el calendario
  consultaba `creador_id`: todo lo creado salía como "POR RECIBIR".
- Al aprobador (jefe de la tarea) le sonaba todo lo informativo: creada,
  reasignada, cambio de estado.

**Qué cambió**
- Sonido (`functions/src/notification_sound_policy.ts`): al aprobador lo
  informativo le llega en silencio (canal Android `tasks_silent`, iOS
  `passive`); lo que le pide actuar (`solicitud_finalizacion`, "por
  aprobar") sí suena. Al responsable todo le sigue sonando. La marca viaja en
  la notificación (`silenciosa: true`); `TaskService.pushNotification` acepta
  `silenciosa`.
- Asignación en lote (completar acta, tablero › "Asignar por el maestro",
  generar pendientes): las tareas nacen con `notificarCreacion: false`
  (`onTaskCreated` no avisa) y al final sale UN aviso por persona: al
  responsable con sonido y al aprobador en silencio
  (`interventoria_avisos_asignacion.dart`). En el lote, usuarios y reglas se
  leen una vez (`InterventoriaService.enLote`), no dos veces por hallazgo.
- La reparación ya no corre al abrir el módulo: se genera a pedido desde
  Maestro › Revisión › Hallazgos sin tarea, con vista previa.
- Calendario (`lib/core/task_calendar.dart`): solo POR ENTREGAR (asignada a
  mí) y POR RECIBIR (la apruebo: `aprobador_uid` o `jefe_uid`). Haberla
  creado ya no la pone en el calendario; en una tarea manual sin jefe el
  creador es el aprobador y la sigue viendo. Tocar una "por recibir" abre
  "Tareas por aprobar".
- "Tareas que asigné": lo que asigna la matriz de Interventoría no es de
  quien dio clic ("él solo le dio al botón"). Las tareas nuevas nacen con
  creador `interventoria_automatica` ("Asigna: Interventoría") y quien dio
  clic queda en `ejecutadoPorId`. Las viejas (`asignacionAutomatica: true`)
  se excluyen de "Tareas que asigné" y de su historial
  (`lib/core/task_origen.dart`), y Maestro › Revisión ofrece "Pasar a
  Interventoría" para cambiarles el creador. Si alguien eligió a la persona
  a mano en el tablero, la tarea sí es suya. En Gerencia, "por área de quien
  asigna" las agrupa como "Interventoría (automática)".
- Solicitudes de corrección ("devolver") y eliminación ("borrar") de actas:
  el aviso llega solo a Revisor (Kary) y a los desarrolladores activos.
  Quién puede resolverlas no cambia.
- Maestro › Revisión (`interventoria_maestro_revision.dart`, lógica en
  `interventoria_revision_maestro.dart`):
  - Cargos del maestro: existe / nadie lo tiene / no existe / nadie recibe
    tareas, con quiénes lo tienen y en qué numerales; "Reemplazar" cambia
    un cargo por otro existente en todas las reglas.
  - Por establecimiento: quién queda como responsable y aprobador en cada
    sede, y cuándo la tarea sale a otra sede.
  - Hallazgos sin tarea: cuántos se pueden asignar, qué cargo los detiene y
    el botón "Generar asignaciones pendientes (N)".

**Pendiente de despliegue**
- `firebase deploy --only functions` ANTES de publicar la app: sin el
  `onTaskCreated` nuevo, cada tarea del lote volvería a avisar sola además
  del resumen.
- Nueva versión de la app: crea el canal silencioso en Android. Mientras un
  teléfono no actualice, Android entrega esos avisos por el canal por
  defecto y pueden seguir sonando.

---

## Inicio: botones de módulo más pequeños en web — 23 sep 2026 (Claude)

- En el mapa de procesos por columnas (web, ancho ≥ 720) la tarjeta ya no
  usa proporción 1.6 sobre todo el ancho de la franja: tiene alto fijo de
  96 px (icono + dos líneas de título), que crece con la escala de texto
  hasta 140. El espacio vertical entre tarjetas baja de 16 a 10.
- Móvil y web angosto no cambian.

---

## Abastecimiento: indicadores según el periodo elegido — 23 sep 2026 (Claude)

- Hoy / Atrasadas / Cancelados / Pendientes / Entregados se cuentan solo
  sobre las filas del corte elegido: periodo (consumo principal + rango de
  entrega) más proveedor, producto y grupo, con `_enCorte()` compartido con
  el filtro de la tabla.
- Estado, "Con pendientes" y búsqueda no cambian los números: son lo que el
  indicador mide, y si entraran los demás indicadores quedarían en cero.
- Tocar un indicador ya no borra el rango de entrega (salvo "Hoy", que lo
  fija en hoy), para que la lista que aparece cuadre con el número tocado.

---

## Visitas: formato SST oficial, ubicación obligatoria, firmas y calendario — 17 sep 2026 (Claude)

Origen: el Excel "FORMATO INSPECCIÓN SST, EXTINTOR Y BOTIQUÍN" (F-UT-SST-02,
-03 y -01) que el contrato exige diligenciar en una visita mensual por
establecimiento. Pedido del usuario: sincronizarlo con el cronograma, que
jefes y profesionales puedan mover el calendario, ubicación en tiempo real
obligatoria con cercanía al sitio, firma del profesional y del responsable
del establecimiento (dibujada o guardada, como en Planillas), y PDF por
visita y de fin de mes. Todo va sobre el módulo Visitas existente; no hay
módulo nuevo.

**Decisiones acordadas en la sesión**
- Una sola visita HSE cubre las tres hojas; un solo PDF con las tres partes.
- Maestro de ubicaciones propio (`TBL_VISITAS_UBICACIONES`), lo carga solo
  Desarrollo, radio corto (150 m por defecto, editable por establecimiento).
  Sin GPS, sin referencia en el maestro o fuera del radio → no se inicia.

**Modelo (`visitas_models.dart`)**
- `VisitaFormatoItem` gana `tipo` (`calificacion` 1/0/NA, `si_no`,
  `elemento` con cantidad y vencimiento), `parte` (código de hoja) y
  `unidad`. `VisitaFormato` gana `partes` y `tablas` (filas dinámicas con
  campos de texto y de estado B/M/R/NC).
- `VisitaRespuesta` gana `cantidad`, `vencimiento` y `accion` (plan de
  acción). Nuevos: `VisitaFilaTabla`, `VisitaFirma` (PNG como Blob en el
  documento + URL en Storage, igual que la firma interna de GD),
  `VisitaResponsable`, `VisitaReprogramacion`, `VisitaUbicacion`.
- `VisitaMarca` guarda `distanciaMetros` y `dentroDelRadio` calculados al
  momento, para que el informe no dependa de que la referencia siga igual.
- Lógica pura: `distanciaMetros` (haversine), `verificarUbicacionInicio`
  (descuenta la precisión del GPS hasta 100 m), `validarCierreVisita` exige
  tablas completas, responsable del sitio y las dos firmas;
  `hallazgosDeVisita` incluye filas en M/NC; `resumenDeVisita` por parte.
  Corregido de paso: `total` del resumen ahora respeta el filtro por parte.
- `visitasPuedeReprogramar` (jefe cualquiera programada; profesional la
  suya) y `visitasPuedeGestionarUbicaciones` (solo desarrollador).

**Formato oficial (`visitas_formato_sst.dart`, nuevo)**
- Generado desde el Excel con script: 77 ítems de diagnóstico en 14
  secciones, tabla de extintores (6 textos + 13 estados), botiquín con 4
  chequeos sí/no, 25 elementos con unidad y 3 de camilla. Ids estables
  (`sst02_01`, `sst01_e01`, …). El borrador HSE de la semilla se retiró; el
  oficial se siembra vigente y hay botón "Cargar formato SST oficial" en
  Formatos (mismo docId: actualiza, no duplica). El "84" de la calificación
  máxima del Excel era un número viejo: el formato real tiene 77 ítems y el
  PDF lo calcula (`N − NA`).

**Servicio (`visitas_service.dart`)**
- `iniciar()` ahora exige responsable/ciudad/cargo, resuelve la referencia
  (subcentro → centro), verifica y lanza `VisitasException` con el motivo.
- `reprogramar()` con historial y notificación cruzada (jefe ↔ profesional).
- Maestro: `streamUbicaciones`, `guardarUbicacion`, `ubicacionPara`.
- Firmas: `firmaGuardadaDe` (lee el perfil vía `GdService`) y `firmar()`.
- `guardarFilas`, `guardarEncabezado`, `cargoDe`, `cargarFormatoSst`.

**Pantallas**
- `visitas_ubicaciones_screen.dart` (nuevo): pestaña "Ubicaciones" solo para
  el desarrollador; lista centros y subcentros, marca en rojo los que no
  tienen coordenadas, diálogo con lat/lng/radio/ciudad, "Usar mi ubicación"
  (web y móvil) y "Buscar dirección" (solo móvil: el plugin no corre en web).
- `visitas_firma.dart` (nuevo): diálogo de firma (trazo con `signature`, o
  "mi firma guardada" para el profesional), `FirmaTile`, diálogo de
  reprogramar.
- Dashboard: pantalla de inicio con estado de la referencia y encabezado
  del acta; formato por partes con tarjetas por tipo, tabla de extintores
  (diálogo por fila con "Todo Bueno"), encabezado editable, firmas y cierre;
  detalle con reprogramar, firmas, filas y distancia; editor de formatos
  conserva tipo/parte/unidad y tablas al guardar.
- Home: las visitas salen en el calendario (`_calType: 'visita'`): las
  asignadas al usuario y, si es jefe o desarrollador, las que programó.
  Tocar abre el módulo. Solo se suscribe si tiene el módulo en sus accesos.

**PDF (`visitas_informe_pdf.dart`)**
- Con partes: una hoja por parte replicando el Excel (encabezado con
  código/versión/página/elaboración, DATOS, criterios, ítems con subtotal
  por sección, calificación máxima/real y % total; extintores apaisado con
  "Mejora y seguimiento" alimentado por los hallazgos; botiquín con unidad,
  cantidad y vencimiento) y firmas al pie de cada hoja con nombre, cargo y
  fecha/hora. Sin partes, el informe sencillo de antes más firmas.
- Consolidado mensual: columnas hallazgos, distancia al sitio y si está
  firmada.

**Reglas Firestore (`firestore.rules`) — EDITADAS, NO DESPLEGADAS**
- `TBL_VISITAS` update: reprogramar (jefe y profesional dueño, solo
  `fechaProgramada`+`reprogramaciones`); iniciar lleva encabezado; en curso
  admite `tablas`, encabezado y las dos firmas; el cierre NO puede tocar
  firmas. Se reordenó para evaluar lo barato antes de los `get()` de rol.
- `TBL_VISITAS_UBICACIONES`: lee quien participa en Visitas, escribe solo
  Desarrollo. Excluida del comodín final.
- Tests: `functions/test/visitas_profesionales.rules.js` (8 casos, verdes
  en el emulador). Observación: en los rechazos el emulador avisa "maximum
  of 1000 expressions" al caer al comodín `/{collection}`; ya pasaba con
  las reglas anteriores y los permitidos no lo tocan.

**Pruebas**: `test/visitas/visitas_sst_test.dart` (19 casos) +
`visitas_models_test.dart` ajustado (el cierre ahora exige firmas).

**Pendiente / para decidir**
- Desplegar `firestore.rules` (sin eso, reprogramar, tablas y firmas dan
  permission-denied a jefes y profesionales; el desarrollador tampoco
  pasa el update).
- Cargar el maestro de ubicaciones de todos los establecimientos.
- Índice compuesto para el calendario del Home: `TBL_VISITAS`
  (`empresaId`, `asignadoPorId`) — Firestore lo pedirá la primera vez.
- El plan de acción del PDF toma "Responsable" = responsable del
  establecimiento y "Fecha" = 5 días; si HSE quiere otro plazo, se
  parametriza en el formato.

---

## Compras: Bodega puede quitar el archivo rechazado y cronómetro de Calidad — 17 sep 2026 (Claude)

Origen: pedido directo. Bodega, al corregir una recepción rechazada, no podía
eliminar el archivo ni entendía cómo volverlo a subir; y nadie sabía cuánto
tarda Calidad en decidir sobre lo que cargan Compras y Bodega.

**Corrección de recepción (`compras_dashboard_screen.dart`)**
- `_DocAttachButton` pinta el botón "Eliminar documento" también en móvil
  (antes solo web). En web, sobre un documento rechazado, "Agregar" pasa a
  "Reemplazar" en rojo: es la acción real.
- `_ProductoEntryCard.onWebDeleteDoc` → `onDeleteDoc`; la ficha técnica
  dentro de la tarjeta también lo recibe.
- `_NuevaRecepcionScreen` habilita eliminar en modo corrección
  (`_eliminarDocProducto`). Sobre un rechazado deja el estado y el motivo
  sin archivo, así la zona de carga sigue mostrando por qué se rechazó; si
  intentan reenviar sin subir nada, `validarCorreccionesRecepcion` lo
  detiene. El archivo en Storage no se borra (política del módulo).

**Cronómetro de Calidad (`compras_tiempos_calidad.dart`, nuevo)**
- `tiempoCalidadDocumento(doc)`: desde `fechaSubida` hasta `fechaRevision`
  (aprobado, rechazado o consultado). Pendiente → sigue corriendo. Si hubo
  reversión de Admin, la espera reinicia desde `fechaReversion`. Sin
  gestión de calidad o sin fechas → nada. No hay campos nuevos en Firestore.
- `tiempoCalidadRecepcion(r)`: primer documento cargado → última decisión;
  basta uno pendiente para que siga en curso.
- `TiempoCalidadBadge`: "En Calidad hace 2 d 4 h" (ámbar; rojo a partir de
  `kEsperaCalidadAlerta` = 3 días) o "Calidad respondió en 1 d 3 h" (verde).
  Se refresca solo cada minuto mientras corre.
- Dónde sale: en cada documento del formulario (móvil y web), junto a
  "Subió:" en las tarjetas de la bandeja de Calidad (recepción, proveedor y
  ficha) y a nivel de recepción en el listado de Recepciones.
- Pruebas: `test/compras/compras_tiempos_calidad_test.dart` (12 casos).

Pendiente si lo piden: medir también lo que tarda Bodega en corregir (del
rechazo a la nueva carga); hoy la fecha del rechazo se pierde al reemplazar
el archivo y habría que conservarla en el `DocAdjunto`.

---

## Biblioteca Documental: carpetas, alias, normograma y check de Calidad — 14 sep 2026 (Codex, cerrado por Claude)

Origen: reunión del 12 sep 2026 (notas de Gemini). Oscar pidió tres cosas
para la Biblioteca: formatos institucionales validados con un solo check,
documentos del contrato organizados por carpetas temáticas y buscables por
alias o código externo, y un normograma único (número de norma + tema) sin
carpetas.

**Modelo (`gd_models.dart`)**
- `DocumentoDoc` gana `carpeta`, `alias` y `codigoExterno` (todos opcionales,
  `null` cuando no aplican). Se guardan en `TBL_GD_DOCUMENTOS` y viajan en
  `fromMap/toMap/copyWith`.
- Nuevas acciones de historial: `formato_validado` y `metadatos_actualizados`.
- Nuevo permiso `validar_formato` para revisor, aprobador, admin_doc y
  desarrollador.

**Servicio (`gd_service.dart`)**
- `crearDocumento` acepta los tres campos nuevos (recortados con `trim`).
- `validarFormatoInstitucional`: un solo paso `en_revision → vigente` para
  categorías de formato (Formato, Política, Procedimiento, Instructivo…).
  Exige archivo adjunto, versión actual en revisión y vuelve obsoleta la
  vigente anterior. Registra `formato_validado` con sello "Formato validado".
- **Contrato y normograma no pasan por ningún flujo** (decisión de Daniel,
  14 sep): son documentos que ya existen (RUT, resoluciones, leyes) y están
  para conocimiento general. `gdIsReferenceDocument(categoria)` los
  identifica y:
  - `crearDocumento` exige archivo y los crea directamente **vigentes**
    (`esVigente: true`, `versionVigenteId`), con evento `publicado`.
  - `iniciarNuevaVersion` exige archivo y la versión nueva entra vigente en
    el acto; la anterior queda obsoleta (`marcado_obsoleto` + `publicado`).
  - `publicarDocumentoConsulta` publica registros de contrato/normograma que
    quedaron en borrador/revisión antes de este cambio (botón **PUBLICAR
    PARA CONSULTA** en el detalle).
  - En el detalle, estos documentos muestran línea de tiempo de 2 pasos
    (Cargado → Publicado), y como acciones solo **REEMPLAZAR ARCHIVO** y
    eliminar. Nada de enviar a revisión, aprobar, firmar ni marcar vigente.
  - Quien no tiene rol documental ve solo vigentes, así que estos documentos
    quedan visibles para todos desde que se cargan.
- Flujo de formatos (revisado 14 sep): crear registro → descargar
  plantilla con encabezado → armar contenido y subir → Calidad da el check.
  Solo vuelve atrás si Calidad observa.
- `actualizarClasificacionBiblioteca`: edita carpeta/alias/código externo de
  un documento ya cargado sin tocar archivo ni versión. Solo el creador o
  admin_doc/desarrollador; en contrato la carpeta es obligatoria, en
  normograma el número de norma es obligatorio, en formatos no aplica. Deja
  evento `metadatos_actualizados` con los valores nuevos.

**Búsqueda (`gd_library_logic.dart`)**
- `gdDocumentMatchesQuery` incluye carpeta, alias y código externo, así que
  "RUT", "fiambreras" o "USPEC 001-26" encuentran el documento desde
  cualquier carpeta.
- `gdIsInstitutionalFormat(categoria)` decide si aplica el check único.

**Pantallas**
- Dashboard: filtro de carpeta (solo en sección Contrato, con opción "Sin
  carpeta"), columna CARPETA en la tabla web, chips de carpeta/código/alias
  en tarjetas, y botón **DESCARGAR EXCEL BASE** en Formatos que baja
  `assets/templates/plantilla_formato_institucional_base.xlsx` con
  `FileSaver` (web y móvil).
- Alta de documento: en Contrato pide carpeta (obligatoria), código externo y
  alias; en Normograma el título se llama "Tema tratado" y el número de norma
  es obligatorio; en Formatos no cambia.
- Detalle: botón **EDITAR CLASIFICACIÓN** (creador o admin), sello
  "FORMATO VALIDADO POR CALIDAD" con persona y fecha/hora, línea de tiempo
  de 3 pasos (Creación → Revisión → Validado) para formatos y botón
  **VALIDAR FORMATO** en lugar de "Aprobar revisión".

**Plantilla Excel generada por registro** (`gd_formato_plantilla.dart`)
- Daniel (14 sep): el encabezado debe ser uno solo y que "nadie lo pueda
  dañar"; el logo sale de la app. Se retiró el Excel suelto de Codex
  (`assets/templates/...`, botón "DESCARGAR EXCEL BASE") y en su lugar el
  detalle de cada formato tiene **PLANTILLA EXCEL CON ENCABEZADO**
  (`GdService.generarPlantillaFormato`), visible para cualquier rol
  documental.
- El `.xlsx` se escribe como OOXML a mano (zip con `archive`): el paquete
  `excel` no inserta imágenes ni protege hojas. Estructura fija:
  - Filas 1-5: logo de la empresa (`TBL_EMPRESAS.logoUrl`, PNG o JPEG,
    centrado sin deformar en A1:B5; si no hay o falla la descarga, va el
    nombre de la empresa), nombre del formato (C1:G3), dependencia (C4:G4),
    empresa (C5:G5) y a la derecha Versión / Aprobado / Fecha / Código /
    Empresa. "Aprobado" dice *Pendiente de validación* hasta que el formato
    esté vigente; después lleva nombre (nunca cédula) y fecha del check.
  - Fila 6: separador. Paneles congelados en A7.
  - **Protección de hoja** con clave `kGdPlantillaClaveHoja`
    (`CALIDAD-USPEC`, hash heredado de Excel, verificado contra openpyxl).
    Encabezado bloqueado y no seleccionable (así tampoco se le insertan
    filas). Todo lo demás desbloqueado —estilo Normal y xf 0 con
    `locked=0`— y con permiso de formato, filas, ordenar y filtrar, para que
    cada dependencia arme el contenido a su gusto. Insertar columnas y
    tablas dinámicas quedan bloqueados.
  - Colores: `kGdPlantillaColorPrimario` / `Secundario` (provisionales);
    `TBL_EMPRESAS.colorPrimario` / `colorSecundario` (hex de 6 dígitos sin
    `#`) los reemplazan por empresa. **Admin → Editar empresa** tiene ahora
    la sección "Colores corporativos" con los dos campos y una vista previa
    del encabezado; vacío = defecto, y un hex inválido no se guarda.
- Descarga con `FileSaver` (web y móvil); nombre `LOG-001_Acta_de_baja_v1.xlsx`.
- Alta de formato, **todo en el mismo diálogo** (Daniel: "si se descarga
  por fuera y luego se sube, se rompe el flujo"): Paso 1 · con dependencia y
  nombre escritos se habilita **DESCARGAR PLANTILLA EXCEL**
  (`generarPlantillaFormatoPrevia`: código previsto, v1, logo y colores de
  la empresa); Paso 2 · se sube el formato armado; **CREAR FORMATO** (el
  archivo vuelve a ser obligatorio). Al crear se abre el detalle, que
  conserva su botón de plantilla para versiones nuevas. La **dependencia**
  ya no es texto libre: desplegable desde `TBL_AREAS` vía `AreaCatalogo`
  (regla 3 de CLAUDE.md); solo si la empresa no tiene áreas se escribe a
  mano.
- Pruebas: `test/gestion_documental/gd_formato_plantilla_test.dart` (hash de
  clave, bloqueo, merges, logo, escape XML, nombre). Además se abrió un
  archivo generado con openpyxl: protección, clave, merges, imagen y
  paneles correctos.
- **Sello dentro del archivo subido** (`gdSellarPlantillaValidada`): Daniel
  pidió revisar si de verdad era imposible. No lo es: re-serializar el libro
  entero con `excel` sí lo daña, pero cambiar UNA celda del XML de la hoja
  dentro del zip (igual que Planillas hace con `styles.xml`) deja todo lo
  demás byte a byte. Al dar el check, `validarFormatoInstitucional` descarga
  el `.xlsx`, escribe "Nombre · dd/mm/aaaa HH:mm" en la celda *Aprobado*
  (I2, que está bloqueada y por eso siempre está ahí), sube el resultado como
  `validado_<nombre>` y lo deja como archivo de la versión; el original
  queda en `archivoOriginalUrl/Path`. Reconoce la hoja por la clave de
  protección o, si la desprotegieron, por la combinación C1:G3; acepta la
  celda como inlineStr (nuestra) o como sharedString (como la deja Excel).
  Si el archivo es PDF/Word, no conserva el encabezado o falla la red, el
  check sigue igual y el motivo queda en el evento
  (`selloEnArchivo`, `selloDetalle`). Probado con un archivo re-guardado por
  openpyxl con contenido y combinaciones del usuario: sello escrito,
  contenido intacto, protección intacta.

**Pendiente / decisiones abiertas**
- Reglas de Firestore: `TBL_GD_DOCUMENTOS`, `TBL_GD_VERSIONES` y
  `TBL_GD_FLUJO` siguen bajo la regla genérica de usuario autenticado; no se
  tocaron.
- Ver la Biblioteca sigue exigiendo el módulo asignado; "público" hoy
  significa "todo el personal con acceso a Biblioteca", no toda la empresa.
- Las carpetas son texto libre: no hay catálogo. Si se escriben "Legales" y
  "legales" salen como dos carpetas.

Pruebas: `flutter test test/gestion_documental` (búsqueda por carpeta/alias/
código y por número de norma).

---

## Correspondencia: "Contestado", quién y qué contestó — 12 sep 2026 (Claude)

La columna "Canal de respuesta" del tablero decía "Microsoft 365 · fuera de
la app" cuando el cron encontraba la respuesta en *Elementos enviados*. Era
correcto pero no se leía como contestado, y el backend solo guardaba que
salió un correo del buzón: ni el texto, ni el remitente, ni el responsable.

- Tablero: chip verde **Contestado** con fecha, canal debajo ("Desde Outlook
  (detectada en el buzón)" / "Desde la app por…" / "Marcada Ya contesté") y
  "Por Fulano" con `UserAvatar`/`UserNameText`. "Pendiente" sigue igual.
  Excel: columna nueva "Contestada por".
- Backend (`correo.ts`): al enlazar un enviado se leen cuerpo, adjuntos
  (solo nombres) y remitente (`sender`/`from` en Graph, `From` en Gmail) y
  se escriben `respuestaCuerpo`/`respuestaAsunto` (si estaban vacíos),
  `respuestaRemitente`, `respuestaAdjuntosNombres`, `respondidoPorId/Nombre`
  (el responsable asignado al detectar) y `respuestaDetalleAt`.
- Backfill: las detectadas antes de este cambio no se vuelven a escanear,
  así que cada corrida completa hasta 5 expedientes `buzon_externo` sin
  `respuestaDetalleAt` (`backfillDetectedResponses`).

Quién contestó, en orden: (1) el responsable asignado al detectar la
respuesta; (2) si no hay, la **firma del correo**: se toma solo lo que
escribió quien contesta (se corta en `De:` / `From:` / "El ... escribió:" /
`>`) y se compara contra el personal de la empresa (nombre completo o
primer nombre + primer apellido, con hasta dos palabras entre medio). Solo
se atribuye si casa exactamente una persona; con dos o ninguna queda vacío
y se muestra el buzón. `respondidoPorOrigen` = `responsable` | `firma`; en
la UI la firma lleva un icono de pluma / "(según la firma del correo)".
Prueba: `functions/test/gd_firma_respuesta.test.js`.

El remitente del buzón (`sender`/`from`) se guarda igual, pero como las
respuestas salen del mismo buzón compartido en que entran, casi nunca es
la persona; por eso la firma es el respaldo, no el remitente.

Aparte: `functions/src/interventoria_deletion.ts` estaba en ceros en la
copia de trabajo (16 KB de NUL, sin commit). Se reconstruyó desde
`lib/interventoria_deletion.js` (compilado del 11 sep 21:33); el JS que
genera es idéntico. Incluye `interventoriaEliminarActa`, que la app ya llama.

---

## Planillas por WhatsApp: revisado — 11 sep 2026 (Claude)

`ppWhatsAppCambioFirma` está bien planteado: es `onUpdate` sobre
`TBL_PP_PLANILLAS` y las firmas SÍ son updates de `estado`, así que dispara
(en los logs corre en cada cambio). Plantilla `planilla_pago_actualizacion`
aprobada en Meta con variables planilla/estado/accion en ese orden, que es
el que manda la función. Listas de EMPRESA_001 activas: Aprob_auditoria
(Karen, Daniel) y Aprob_gerencia (Oscar, Daniel).

Dos cosas encontradas:

- **EMPRESA_002 no tiene rutas de planillas** (`planillas_tesoreria_auditoria`
  ni `planillas_auditoria_gerencia`). La planilla 1583 firmada el 07/09 en
  esa empresa no avisó a nadie por eso. Se configura en Administración >
  WhatsApp; no es código.
- La idempotencia era por planilla+estado, así que una planilla **observada
  y vuelta a enviar** a Auditoría no avisaba la segunda vez. Ahora la clave
  es el `eventId` de Firestore: único por cambio, estable en reintentos.

Aún no se ha ejercido ninguna firma desde que se migró a Meta (la última
fue el 07/09, antes de la migración del 11/09 03:10). La primera firma real
después del deploy lo confirma; con `WHATSAPP_ROUTE_SENT` / `_SKIPPED` en
logs ya no hay que adivinar.

---

## El WhatsApp de "nueva acta" no salía nunca — 11 sep 2026 (Claude)

Codex se quedó sin créditos a mitad de la migración a WhatsApp Cloud (Meta).
La configuración en producción está completa: proveedor `whatsapp_cloud`,
plantilla `interventoria_actividad` APROBADA, ruta `interventoria_nueva_acta`
con lista "Nueva_acta" (Kary y Oscar, activos), módulo encendido. Y aun así
no llegaba nada.

Causa: `interventoriaWhatsAppNuevaActa` era `onUpdate` y comparaba cuántas
imágenes había antes y después. Pero el acta se crea en UNA escritura con las
imágenes ya adentro (`guardarVisita` hace un `set`), así que la creación
nunca disparaba la función; solo la disparaban los guardados de revisión, y
ahí terminaba en 6 ms sin enviar (se ve en los logs de hoy). Ahora es
`onWrite` y trata la creación como "de 0 a N imágenes".

Además `sendWhatsAppRoute` tenía ocho `return { skipped: true }` mudos.
Ahora cada omisión escribe `WHATSAPP_ROUTE_SKIPPED` con el motivo
(módulo apagado, ruta sin lista, lista inactiva, sin destinatarios…) y cada
envío `WHATSAPP_ROUTE_SENT`. La próxima vez se diagnostica con un
`gcloud logging read`, no adivinando.

**Requiere deploy de functions.** No se tocaron los archivos de Codex a
medias (`functions/lib/**`, `package.json`, `main.dart`, permisos de
arranque, acta devuelta): siguen sin commit en el árbol para que él los
retome.

---

## Facturación: la devolución llega pero "Sin observaciones" — 14 sep 2026 (Claude)

Yolmaider recibió la notificación de un documento devuelto (Proyectos
Productivos, agosto) y al abrir el chat de observaciones: "Sin observaciones
para este documento", en todos los documentos. La observación SÍ está en
`TBL_FAC_OBSERVACIONES` (verificado en producción). La consulta era
`where empresaId + where establecimientoId + orderBy fecha`, que exige un
índice compuesto que nunca se creó; Firestore responde
FAILED_PRECONDITION, y las tres suscripciones de la pantalla no escuchaban
el error: lista vacía, como si no hubiera nada.

Arreglo sin índice ni deploy de Firestore: la consulta ya no ordena en el
servidor (se ordena en memoria; son pocas por establecimiento), y cualquier
error de la stream se muestra en pantalla en vez de parecer "sin
observaciones". De paso el autor sale con `UserNameText`: en el dato quedó
la cédula en `autorNombre`.

---

## Compras: "Indica el motivo por el cual se está editando la recepción" — 14 sep 2026 (Claude)

La auditoría de ediciones de recepción (Codex, `ea52583`) exige un motivo
al editar una recepción que ya estaba en revisión. El campo "Motivo de la
edición *" está ARRIBA del formulario (después del grupo), y el botón
"Guardar cambios" abajo, después de todos los productos y sus archivos: el
aviso rojo decía "indica el motivo" y la persona no encontraba dónde. Ahora,
si al guardar está vacío, se pide en un diálogo ahí mismo y se sigue
guardando. Y el campo se movió de arriba del formulario a JUSTO ENCIMA del
botón de guardar, que es donde la persona está cuando lo necesita.

Aclaración para Compras: "Observaciones de la ficha técnica" es otra cosa
(va con el producto, para Calidad); el motivo de edición es de la recepción
y queda en su histórico.

---

## Registrar acta: la causa real era una regla — 14 sep 2026 (Claude)

El "Dart exception thrown from converted Future" de los registradores no
era (solo) el churn de listeners. Reproducido en el emulador: el registro de
un acta (versión de Codex) abre una transacción que LEE el id nuevo para
comprobar que no exista y luego lo crea. La regla de lectura de
`TBL_INTERVENTORIA_VISITAS` era `belongsToCompany(resource.data.empresaId)`,
y en un documento inexistente `resource` es nulo: la regla falla con error y
Firestore deniega. En web, un error dentro de una transacción sale con ese
texto genérico. Ningún registrador pudo guardar actas desde el build del 11.

Regla: `get` permite `resource == null` (leer un id que no existe no expone
nada) y `list` sigue exigiendo pertenencia. Mismo cambio en
`TBL_INTERVENTORIA_HALLAZGOS` y `TBL_CORREO_ROLES`, que tenían la misma
trampa (la de Correo se había esquivado desde el cliente el 11 sep). 28
casos de reglas en verde; la prueba nueva reproduce la transacción.

**Solo requiere `firebase deploy --only firestore:rules`; no hace falta
build.** El MemoStreamBuilder del commit anterior sigue siendo correcto,
pero por sí solo no habría destrabado el registro.

---

## Entrega de Codex integrada — 14 sep 2026 (commit por Claude)

Codex terminó su lista pero la dejó sin commit en el árbol de trabajo (y
sin nota aquí). Claude verificó el árbol completo —analizador sin errores,
745 pruebas Flutter y 56 de functions en verde, `tsc` limpio— y lo commiteó
tal cual, sin cambiar nada suyo. Lo que trae, leído del diff:

- **Interventoría:** acta devuelta con estado propio `devuelta` (la corrige
  quien la registró o a quien se le asignó; no reaparece en Por revisar
  hasta corregirla); ID determinístico del acta para que dos dispositivos no
  creen dos visitas de la misma; asignación masiva que vuelve a resolver con
  datos actuales y rechaza responsables de otra sede; selector de centro en
  el tablero con reparación de nombres viejos.
- **Correspondencia:** detección de la respuesta contestada desde el buzón
  (quién firmó, texto sin citas, adjuntos) y su exportación.
- **Tareas / notificaciones:** propiedad operativa de la tarea
  (`asignado_uid` y alias, nunca el creador ni el jefe) antes de permitir
  avances o cierre; pantalla de notificaciones ampliada.
- **Arranque móvil:** `StartupPermissionsService` pide cámara, micrófono y
  ubicación en la primera apertura.
- **Talento Humano:** selección de centro de costo del personal como
  desplegable, con reparación de ids viejos.
- **WhatsApp Cloud:** variables de entorno de Meta en `.env.example`,
  `package.json` con build limpio y `test:rules`.

`functions/lib-deploy/` queda ignorado (es artefacto de deploy).

---

## "Dart exception thrown from converted Future" al guardar actas — 14 sep 2026 (Claude)

Varios registradores desde el viernes: al tocar "Guardar acta" sale ese
error y el acta no se guarda. Ese texto es lo que muestra Flutter web cuando
el SDK de Firestore en JavaScript lanza un error que no es FirebaseError, y
el que lo provoca en esta app es el conocido `FIRESTORE INTERNAL ASSERTION
FAILED` por recrear listeners en cada build (ver memoria
`firestore-listener-churn`). A partir de ahí toda escritura de la sesión
falla hasta recargar la pestaña.

Qué lo disparó ahora: el viernes la hoja "Registrar acta" pasó a mostrar el
establecimiento en un desplegable también para el Registrador, y ese
desplegable creaba `streamCentrosCosto(...).snapshots()` DENTRO de build.
Esa hoja se redibuja con cada puntaje y cada nota: decenas de listeners
nuevos por acta. Y no era el único: el tablero principal recreaba
`streamVisitas` + `streamHallazgos` en cada setState (el IndexedStack
mantiene todas las pestañas construidas), y la tabla de Subsanaciones un
listener de `TBL_TAREAS` por fila.

Arreglo: `lib/widgets/memo_stream_builder.dart`, un `StreamBuilder` que
conserva la stream mientras su `memoKey` (empresa, centro, filtros) no
cambie. Reemplazados los 11 puntos de Interventoría (tablero, histórico,
por revisar, análisis, solicitudes, selector de centro, hoja de registro,
chips de tarea, panel del hallazgo). Es la misma corrección que
Correspondencia recibió el 11 sep; conviene pasarla al resto de módulos.

Mientras sale el build: recargar la pestaña (F5) después de un error de
estos y volver a guardar; el acta no se pierde porque los puntajes se
vuelven a escribir.

Nota de árbol: HEAD lleva mezclado trabajo a medias de Codex en
`interventoria_models.dart` (estado `devuelta`), arrastrado por `git add`
de directorio en `1ad591c`/`8a0e2e5`. La prueba "devolución de un acta
vuelve al estado que ya existe" falla en HEAD limpio y pasa con el árbol de
trabajo. Codex debe commitear su parte para cerrar eso.

---

## Devolver un acta también en Fase 1 — 12 sep 2026 (Claude)

El botón "Devolver acta con errores" solo salía en actas ya completas
(Fase 2). Un acta registrada mal —el establecimiento equivocado, como Ubaté
en Bodega Cota— hay que devolverla ANTES de revisarla. Ahora sale en todas
las actas para admin, revisor y gerencia. Y el botón naranja de "Recuperar
observaciones desde los hallazgos" ya solo aparece en actas completas sin
notas: en Fase 1 no tener notas es lo normal y salía en todas las tarjetas.

---

## Compras: el registro sanitario es SOLO del producto — 11 sep 2026 (Claude)

Compras corrigió lo del 10 sep: el registro sanitario no va en el
proveedor "ni en ningún otro lado", solo en el producto (por marca, junto a
la ficha técnica). Se deshizo esa parte del commit `918a6b3`:

- `kDocumentosAsociadosLabels` vuelve a tener `registroSanitario` (con
  vigencia obligatoria; la ficha técnica sigue SIN vigencia, eso sí era de
  la reunión);
- `soporteRegistroInvima` vuelve a `kDocProveedorOcultos`: no se pide al
  proveedor aunque la matriz lo traiga, y lo ya cargado no se borra;
- un producto nuevo vuelve a exigir ficha y registro por marca; la ficha
  del producto muestra el estado del registro; Consulta de productos y de
  marcas lo listan y lo exportan; "Marcas por completar" lo cuenta.

Lo que NO se tocó: el semáforo de la marca sigue siendo solo de la ficha
(verde aprobada / naranja pendiente / rojo rechazada), como se decidió el
10 sep; el registro se ve como chip aparte, no cambia el color.

---

## "No se guardó el borrador: permission-denied" en la revisión — 11 sep 2026 (Claude)

Con el aviso nuevo de la pantalla de revisión, el administrador vio de
inmediato lo que antes se tragaba en silencio: `permission-denied` al
guardar el borrador de Pasto. Reproducido en el emulador
(`functions/test/interventoria_visitas.rules.js`): el acta se actualiza
bien y los hallazgos se crean bien, pero `TBL_INTERVENTORIA_HALLAZGOS` tenía
`allow delete: if false`, y guardar la revisión BORRA los hallazgos
huérfanos (sin observación y sin tarea). Un batch con un borrado prohibido
falla completo. Ahora se permite borrar desde el cliente solo un hallazgo
`fuente: 'acta'` sin `tareaId`; uno con tarea sigue sin poderse borrar (lo
hace la función con aprobación). 25 casos de reglas en verde.

**Requiere `firebase deploy --only firestore:rules`.**

**Segunda causa, la que seguía después del deploy:** "sí se guarda pero
sale el error". El acta se actualizaba y luego reventaba la LECTURA de sus
hallazgos: `where('visitaId').where('fuente')` sin `empresaId`. La regla de
lectura es `belongsToCompany(resource.data.empresaId)` y Firestore solo
acepta una consulta si puede probar la regla con los filtros de la consulta;
sin el filtro por empresa la consulta entera es permission-denied aunque
cada documento sea legible. Afectaba a guardar borrador, a Completar acta
(quedaba `completa` sin sincronizar hallazgos) y a eliminar acta. Las tres
consultas llevan ahora `empresaId`. Reproducido y cubierto en el emulador
(`interventoria_visitas.rules.js`, caso 7). Es cambio de cliente: build web.

## Cómbita, segunda vuelta: dos "Combita Alta" — 11 sep 2026 (Claude)

El dato: Cómbita existe TRES veces en `TBL_CENTROS_COSTOS` de EMPRESA_002.
`..._1013` "Combita" (dividido en subcentros desde el 4 sep), y los centros
viejos `..._1024` "Combita Alta" y `..._1023` "Combita Media", con actas
hasta el 21 y 25 de agosto. Agrupando por id salían dos "Combita Alta".
Ahora la barra se agrupa por el NOMBRE del establecimiento tal como se
pinta, y las actas sin subcentro de un centro que ya está dividido no van
al comparativo (siguen en el histórico). Con los datos de hoy: Combita Alta
(10/09) y Combita Media (09/09). Dos barras.

Pendiente de datos, no de código: los centros 1023 y 1024 deberían
deshabilitarse en el catálogo para que nadie registre más actas ahí.

---

## Ramiriquí perdió las observaciones al guardar — 11 sep 2026 (Claude)

Kary: "guardé el acta de Ramiriquí y ya no puedo leer los hallazgos que
guardé". En el histórico el acta sale con las once secciones y ninguna nota.

**Lo que dice el dato (consultado en producción, solo lectura):** el acta
`DlJJeeQa4lkLjtmrr9uK` de Ramiriquí la creó Luis Carlos Cuervo (registrador)
el 10 sep 19:26 en Fase 1, y `updateTime == createTime`: **el documento no
recibió ninguna escritura después**. Cero notas, cero hallazgos. Las
observaciones de Kary nunca llegaron al servidor, así que no hay de dónde
recuperarlas; hay que registrarlas de nuevo. La pantalla de revisión solo
guardaba al tocar el check de cada nota o al Completar, se tragaba los
errores y salir no avisaba. Por eso además del punto siguiente:

- autosave dos segundos después de cada cambio, y al tocar el check;
- si el guardado falla, banner rojo con "Reintentar" y el subtítulo dice
  "Sin guardar"; ya no se traga nada;
- botón "Guardar borrador" en la barra;
- salir con cambios pendientes pregunta: guardar, salir sin guardar o
  seguir.

Causa de la otra forma de perderlas (no fue esta vez, pero el código lo
permitía): `_RevisionActaScreen` tomaba una FOTO de los ítems al abrirse y
al guardar —borrador o completar— escribía `itemsEvaluacion` completo con
esa foto. Cualquier observación escrita entretanto en Firestore (otro
dispositivo, el autosave de una nota, otra persona) se pisaba, y
`_autoCrearHallazgosDesdeItems` borraba los hallazgos sin tarea que ya no
tenían nota. Pérdida real, silenciosa.

Arreglo: la pantalla lleva los ítems que la persona tocó (`_tocados`) y al
guardar mezcla con lo fresco de Firestore (`mezclarItemsRevision`): manda
Firestore salvo en lo tocado aquí. Probado.

Recuperación: botón "Recuperar observaciones desde los hallazgos" en la
tarjeta del acta (roles que revisan), visible solo cuando el acta no tiene
ninguna nota. Reconstruye las notas desde `TBL_INTERVENTORIA_HALLAZGOS`
(fuente 'acta', por `grupoId`). Si los hallazgos también se borraron (no
estaban asignados), no hay de dónde y toca registrarlas de nuevo.

---

## Avances móvil, Calidad en Interventoría y seguimiento con histórico — 11 sep 2026 (Claude)

**Tareas > Avances: "Tomar foto" no abría la cámara en el móvil.** El botón
pedía el permiso de ubicación ANTES de abrir la cámara y, si estaba negado,
se quedaba en un aviso fugaz. Ahora la cámara va primero y la ubicación es
opcional (10 s de tope); si no hay, la marca de agua dice "Sin ubicación".
Un error real de la cámara se muestra en pantalla.

**Calidad en Interventoría.** Análisis ya lo tenían (está al final de la
tira de pestañas, en móvil hay que deslizar). Maestro no: ahora lo
**consultan** admin, gerencia y calidad; **editar la regla** sigue siendo
de admin y gerencia (`puedeEditarMaestroSubsanaciones`).

**Subsanaciones: seguimiento con histórico.** Antes el seguimiento era un
solo texto que se sobrescribía, y calidad no podía ni escribirlo. Ahora:

- `puedeRegistrarSeguimiento(rol)`: escritura general + calidad. Calidad
  sigue sin reasignar.
- Cada seguimiento es una entrada en `TBL_INTERVENTORIA_HALLAZGOS.seguimientos[]`
  con texto, autor, fecha y adjuntos (foto desde la cámara o archivo). El
  campo viejo `seguimiento` guarda el último texto para el Excel y las
  pantallas que no cambiaron; un hallazgo viejo con solo ese texto lo
  muestra como "Seguimiento anterior".
- Al publicar, el responsable recibe notificación con la guía
  (`interventoria_seguimiento`, enlazada a su tarea). Sin responsable, queda
  en el histórico y se avisa que no hay a quién notificar.
- El botón grande de abajo ("Guardar seguimiento") publica lo que haya
  escrito sin publicar y guarda la fecha de subsanación.

Reglas: `TBL_INTERVENTORIA_HALLAZGOS` ya permitía update a cualquiera de la
empresa; no cambian. Pruebas: `interventoria_seguimiento_test.dart` (11).

---

## Cómbita salía cinco veces en Análisis — 11 sep 2026 (Claude)

Combita, Combita Alta, Combita Combita Alta, Combita Combita Media y
Combita Media: cinco barras para dos partes. Dos causas, las dos de datos:

- el subcentro quedó guardado unas veces como "Alta" y otras como "Combita
  Alta", con ids distintos según la época del catálogo. La barra se agrupaba
  por id, así que el mismo subcentro salía dos veces; y el nombre se armaba
  centro + subcentro, de ahí el "Combita Combita Alta";
- hay actas de Cómbita sin subcentro (de antes de dividirlo, y una del
  03/09 registrada antes de que fuera obligatorio).

Ahora las barras y las columnas de la matriz se agrupan por clave
normalizada del subcentro sin el nombre del centro (`claveSubcentro` en
`lib/core/subcentros_costo.dart`), el nombre no se duplica, y el acta sin
subcentro de un centro dividido sale como "Combita (sin subcentro)" en vez
de parecer una tercera parte. Quedan dos barras + esa, mientras existan
actas viejas sin subcentro; el registro ya exige subcentro.

---

## Admin no podía cambiar roles de Interventoría — 11 sep 2026 (Claude)

"No se pudo cambiar el rol de Interventoría: permission-denied", con el
desarrollador administrando la Unión Temporal. La regla de
`TBL_INTERVENTORIA_ROLES` solo aceptaba `isDeveloper()` (marca en la RAÍZ del
usuario) o `admin_interventoria`. El desarrollador real está marcado dentro de
`empresasDetalle[empresa]`, y su documento de rol en esa empresa no coincidía
con lo que la regla busca. Ahora `administraInterventoria(empresaId)` suma
`isDeveloperIn(empresaId)`, igual que ya hacía el maestro de beneficiarios.
También aplica a `TBL_INTERVENTORIA_CONFIG` (matriz de responsables).

Probado en el emulador (`functions/test/interventoria_roles.rules.js`, 6
casos): con las reglas viejas fallaba exactamente el caso del desarrollador
por empresa; con las nuevas pasan los 6 más los 7 del maestro bancario. De
paso quedó demostrado que un error de evaluación en una rama de `||` NO tumba
la regla si la otra rama es cierta: el `isDeveloper()` con campos ausentes
no era el culpable.

**Requiere `firebase deploy --only firestore:rules`.**

**Segunda vuelta (misma tarde):** desplegado lo anterior, seguía el
permission-denied al cambiarse el rol a sí mismo en Servir USPEC. El dato:
el desarrollador real tiene `role: rutas_desarrollador` y
`roleId: EMPRESA_001_rutas_desarrollador` en la raíz, y en EMPRESA_002 un
bloque sin rol. La app lo reconoce porque `isDeveloperUser` acepta un
`roleId` que TERMINA en `_desarrollador`; las reglas exigían el valor exacto
`desarrollador`. Ahora `esRolDeDesarrollo(valor)` acepta la lista corta o el
sufijo `_(desarrollador|developer)$`, y se usa en `isDeveloper` e
`isDeveloperIn`. De paso `let u = currentUser()` en vez de seis llamadas:
el emulador avisaba del tope de 1000 expresiones por petición. Caso
`devreal` añadido a la prueba; 19 casos de reglas en verde.

Para correr el emulador desde esta máquina (Windows, JDK 21) hace falta un
directorio corto para los sockets locales, si no muere con "Unable to
establish loopback connection":

```powershell
$env:JAVA_TOOL_OPTIONS='-Djdk.net.unixdomain.tmpdir=C:\Temp\uds'   # crear la carpeta antes
$env:PATH='C:\Program Files\Eclipse Adoptium\jdk-21.0.12.101-hotspot\bin;'+$env:PATH
cd functions; npx firebase emulators:exec --only firestore "node --test test/interventoria_roles.rules.js test/nomina_cuentas.rules.js"
```

---

## Cuatro reportes de Gerencia — 11 sep 2026 (Claude)

1. **Correo: "No fue posible cargar los permisos del módulo".** No era
   permisos: era que quien NO tiene documento en `TBL_CORREO_ROLES` recibe
   `permission-denied` y no "no existe", porque la regla de lectura mira
   `resource.data.empresaId` y en un documento inexistente `resource` es nulo.
   Y aunque el documento exista (Oscar tiene "Administrador del módulo" en la
   matriz), la lectura depende de cómo la regla entiende la pertenencia a la
   empresa, que no es exactamente como la entiende la app. Por eso el rol
   ahora lo da el servidor: callable nuevo `correoMiRol`, que devuelve lo
   mismo que `resolveCorreoRole` aplica en cada acción. La lectura directa de
   Firestore queda de respaldo si la función no responde, y en ese respaldo
   el denegado del documento inexistente se toma como "sin rol asignado".
   **Requiere deploy de functions.** Sin reglas nuevas.
2. **Interventoría: "Otra persona autorizada debe resolver esta solicitud".**
   La regla de cuatro ojos tenía sentido cuando nadie borraba directo. Desde
   el 10 sep admin, gerente y revisor eliminan sin pedir permiso, así que la
   propia solicitud (la de Oscar del 05/09 sobre Ponal) solo quedaba atascada.
   Backend (`interventoriaResolverEliminacion`) y pestaña dejan resolverla.
   **Requiere deploy de functions.**
3. **Las actas de Ubaté quedaban en "Bodega Cota".** El Registrador tenía el
   establecimiento FIJO desde `TBL_USUARIOS.centroId` (o
   `empresasDetalle[empresa].centroId`) y no podía ni verlo ni cambiarlo. Ahora
   arranca preseleccionado en el suyo, con aviso, y puede cambiarlo. El dato de
   ese usuario sigue mal: corregir su `centroId` en Admin/TH. Las actas ya
   guardadas en Bodega Cota hay que volverlas a registrar (no hay "cambiar
   establecimiento" de un acta).
4. **Correspondencia: "me llega el mensaje pero no se actualiza".** Las dos
   pantallas creaban `streamExpedientes(...).snapshots()` dentro de `build`:
   cada tecla del buscador abría un listener nuevo; en web eso acaba en el
   `INTERNAL ASSERTION FAILED` conocido y la lista se congela. Stream
   memoizada por pantalla, recreada solo si cambia la empresa.

---

## Visitas de profesionales — maqueta funcional (Claude, 10 sep 2026)

Módulo nuevo `lib/visitas/` según la reunión del 9 sep (02:00–02:05 de la
transcripción): el jefe programa en un cronograma, el profesional ejecuta en
el establecimiento con ubicación y hora del dispositivo, responde el formato
de su área (cumple / no cumple / no aplica) con observación digitada o
dictada y foto por ítem, cierra y sale el informe; cada "no cumple" se vuelve
tarea; a fin de mes el consolidado por área.

**Qué es maqueta:** los FORMATOS. Oscar quedó de recogerlos con los
directores. Por eso son un maestro en Firestore (`TBL_VISITAS_FORMATOS`),
versionado, con cuatro **borradores de ejemplo** sembrables desde la pestaña
Formatos (calidad, HSE, mantenimiento, nutrición) y marcados como borrador en
el nombre. Cuando lleguen los reales se cargan o editan sin tocar código.

**Qué es definitivo:** el flujo. Reglas que aplican y que están probadas
(`test/visitas/visitas_models_test.dart`, 27 casos):

- Solo el profesional asignado ejecuta su visita. Ni el jefe: si el jefe
  pudiera responder por él, volveríamos a "dicen que fueron".
- Se inicia el día programado o después, nunca antes.
- No se cierra con ítems sin responder; un "no cumple" exige observación, y
  foto donde el formato lo pida (`requiereEvidencia`).
- "No aplica" no suma ni resta; sin nada evaluado el porcentaje es null, no 0.
- El cumplimiento se guarda al cerrar y no se recalcula, para que el
  consolidado no dependa de que el formato siga igual.
- Consolidado: solo terminadas promedian; programadas sin hacer y canceladas
  se cuentan aparte; peores establecimientos primero; subcentro = fila propia.

Colecciones: `TBL_VISITAS`, `TBL_VISITAS_FORMATOS`, `TBL_VISITAS_ROLES`
(roles `jefe` / `profesional` / `consulta`; el desarrollador entra como jefe).
Las tres caen en el catch-all de `firestore.rules` (cualquier usuario
autenticado), igual que Rutas o Compras: no hay reglas nuevas que desplegar.

Toqué archivos de Codex para enchufarlo, con cambios mínimos y aditivos:
`lib/core/app_catalog.dart` (entrada `visitasdashboard`),
`lib/home/home_screen.dart` (`_abrirVisitas` + tarjeta), `user_company.dart`
(alias `visitas`), `admin_dashboard_screen.dart` (lista de apps y tabla de
permisos) y `personnel_template_service.dart` (plantilla de `TBL_APPS`).
**Codex: `git pull` antes de tocar esos cinco.**

Para que aparezca: en Admin dar `visitasdashboard` al usuario (y crear el
registro en TBL_APPS de la empresa si la plantilla no lo hizo); luego en
Visitas > Roles asignar jefe / profesional.

Pendiente, y no es de esta maqueta:
- Las tareas de los hallazgos se asignan al jefe que programó. Quién responde
  por cada hallazgo EN el establecimiento es la matriz por cargo de
  Interventoría; conectarla es el paso siguiente.
- Los formatos reales de cada director (los recoge Oscar).
- Comparar la ubicación de inicio con la del establecimiento (los centros de
  costo no tienen coordenadas todavía).

---

## Biblioteca Documental — fase 1 de separación (Codex, 10 sep 2026)

Implementada la decisión literal de la reunión: **Correo**, **Gestión de
Correspondencia** y **Biblioteca Documental** son accesos independientes. La
Biblioteca dejó de abrirse como una vista interna de Correspondencia y usa el
nuevo `appId` `bibliotecadocumentaldashboard`; su asignación y rol documental
ya aparecen por separado en la matriz de Administración.

Se reutilizó el flujo existente de `gd_*` —documentos, versiones, revisión,
aprobación y firma— sin copiar colecciones ni servicios. La Biblioteca añadió
los tipos iniciales de la reunión: Formato, Documento contractual, Circular
externa y Norma aplicable, conservando los tipos históricos. La búsqueda ya
incluye código, título, área y tipo. La carga sigue siendo un archivo por
registro, nunca masiva.

Compatibilidad: quien ya tenía `gestiondocumentaldashboard` y un
`rolDocumental` conserva acceso a Biblioteca durante la transición. Las
asignaciones nuevas usan el appId independiente.

Próxima fase sobre esta base, sin volver a unir módulos:

- [x] maqueta funcional diferenciada: navegación lateral y tabla en Web;
  pestañas compactas, indicadores y tarjetas en Móvil;
- [x] código automático por dependencia y consecutivo visible al cargar;
- [x] formatos Word/Excel además de PDF, siempre un archivo por registro;
- [x] sello visible de aprobación con responsable y fecha;
- [x] Normograma con palabras clave y asociación por coincidencias;
- [ ] generar el sello dentro del archivo descargable publicado;
- [ ] llevar el consecutivo a un contador transaccional de Firestore para evitar
  colisiones si dos usuarios crean al mismo tiempo;
- reglas explícitas y pruebas de Firestore para `TBL_DOCUMENTOS`, versiones y
  flujo antes del despliegue productivo.

Validación de esta fase: suite completa de 670 pruebas en verde y compilación
web release correcta.

---

## Reparto de trabajo — reunión 9 sep 2026 (Claude ↔ Codex)

**Estado: EJECUTADO EN SU MAYOR PARTE.** Ver el traspaso justo debajo.

## Traspaso a Codex — 10 sep 2026, tarde

Codex se quedó sin créditos a media mañana con su P0 a medias. Con permiso del
usuario, Claude **tomó la línea de Codex** además de la suya. Todo está en
`main`, versión `2.5.0+12`, 595 pruebas verdes y sin errores del analizador.

### Codex tenía razón dos veces, y quedó como él dijo

- **Fichas técnicas: era QUITAR la vigencia, no agregarla.** Claude lo había
  leído al revés en el reparto original. La transcripción dice literal "fichas
  técnicas no tienen vigencia… quitar eso". Está quitado.
- **El viernes era el plazo para RECIBIR el archivo plano**, no para entregar el
  módulo. Y en la transcripción Oscar dice del plano: "no es de mis grandes
  urgentes". Claude lo había priorizado por una fecha mal leída.

La lección para los dos: **el resumen de Gemini no es la fuente.** Ha fallado en
las dos cosas que se han verificado contra la transcripción. Ante cualquier duda,
buscar la frase en el texto de la reunión.

### Lo que Codex NO tiene que rehacer

Todo lo de la lista de Codex está hecho:

- Compras: vigencia quitada, registro sanitario al proveedor, mensaje de marca,
  fila de producto, **reversión de documentos rechazados**, **botón Aprobar
  fuera de lo ya aprobado**.
- Facturación: **filtro de mes** (el acta lo describía mal: el conteo sí
  filtraba, mentía la etiqueta), semáforo con verde solo al 100 %, el ZIP ya
  existía, **observaciones por mes**, **el chat acumula el historial**.
- Tareas: reasignación a otro departamento.
- Tokens DIAN: el backend ya aislaba por empresa; Codex añadió una segunda
  compuerta en cliente y pruebas específicas para FYC sin heredar permisos de
  Capital.

**No quedan correcciones de código concretamente especificadas de la lista de
Codex.** Para usar Tokens
DIAN en FYC todavía hay que asignar `tokensdiandashboard` a esa empresa y a sus
usuarios desde Administración, y conectar el buzón propio de FYC. Es
configuración de datos, no un permiso hardcodeado.

### Lo que hay que saber antes de tocar nada

- **Hay un deploy de backend pendiente que no es de Claude.** En el árbol hay
  cambios sin commitear en `functions/src/correo.ts` (la validación del tipo
  documental de 3 caracteres), `functions/src/whatsapp.ts` y `firestore.rules`
  (reglas nuevas de `TBL_INTERVENTORIA_ROLES`, `TBL_INTERVENTORIA_CONFIG` y
  `TBL_CORREO_ROLES`). Necesitan
  `firebase deploy --only functions,firestore:rules`. **Las reglas no viajan con
  el hosting.**
- **`TBL_NOMINA_CUENTAS` no tiene reglas de Firestore.** El maestro de datos
  bancarios está modelado con permisos por campo (Talento Humano pone el banco y
  no ve el número; Tesorería ve todo), pero eso es de la interfaz. **No importar
  las 176 cuentas reales hasta que la regla lo respalde.**
- **`lib/utils/excel_download.dart`** reexporta el descargador que vivía solo en
  Compras. Si se mueve o renombra `compras_excel_download_*`, hay que actualizar
  ese archivo: ahora lo usa Interventoría.
- **La matriz de permisos de Interventoría está fijada en**
  `test/interventoria/interventoria_permisos_test.dart`. Si hay que moverla, se
  cambia ahí también y con su comentario; no se borra la prueba.
- **Pendiente de dato, no de código:** en el panel de administración hay que
  poner a Kary como **Revisor** y mover a quien corresponda al perfil nuevo
  **Calidad**. Hasta entonces Calidad existe vacío.

### Preguntas abiertas para el usuario

1. El pantallazo del docx del error al ver la ficha técnica: se corrigieron los
   dos `return` silenciosos de `_abrirUrl`, pero si el fallo era el archivo
   borrado de Storage con el enlace vivo en Firestore, hace falta comprobar la
   existencia del objeto antes de abrirlo.
2. ~~Facturación: qué campos operativos sobran.~~ **Resuelto el 10 sep: no
   sobra ninguno.** No hay nada que quitar.
3. ~~Archivo plano: si el banco quiere los importes con coma de miles.~~
   **Resuelto el 10 sep: sí.** El usuario confirmó que el CSV que envía
   Tesorería —el que trae "3,868,695.00"— es el que recibe el banco. El
   generador ya lo reproduce campo por campo, así que `conSeparadorDeMiles`
   se queda en `true`, que es el valor por defecto.

Fuentes: notas de Gemini del 9 sep 2026, `Correciones COMPRAS.docx`,
`NUEVOS MODULOS.xlsx`, `ARCHIVO PLANO COTA ADMINISTRATIVA AGOSTO 2026.csv`.

**Criterio de fuente.** El resumen automático de Gemini sirve como índice, pero
la transcripción y las capturas mandan cuando hay ambigüedad. El XLSX y el CSV
del archivo plano son dos representaciones del mismo ejemplo: 15 pagos y el
mismo total; no son dos requerimientos distintos. Los datos bancarios son
sensibles y no se copiarán a esta bitácora ni a pruebas del repositorio.

### Regla de convivencia: cada archivo tiene un solo dueño

No es burocracia. `compras_dashboard_screen.dart` tiene 23.788 líneas y
`interventoria_dashboard_screen.dart` 10.926: si los dos tocamos el mismo
archivo, el segundo en guardar pisa al primero sin que nadie se entere. El
reparto está hecho por **módulo completo**, no por tarea, precisamente para
que nunca coincidamos en un archivo.

| Ruta | Dueño |
|---|---|
| `lib/interventoria/**` | Claude |
| `lib/gestion_documental/correspondencia/**` | Claude |
| `lib/gestion_documental/gd_*` (Biblioteca existente) | Claude |
| `lib/core/maestro_formatos/**` (nuevo) | Claude |
| `lib/mantenimiento/**` (nuevo) | Claude |
| `lib/gestion_documental/planillas/pp_archivo_plano_*` (nuevo) | Claude |
| `firestore.rules`, `firestore.indexes.json` y pruebas de reglas | Claude |
| migración backend de registro sanitario (archivo nuevo bajo `functions/src/`) | Claude |
| `lib/compras/**` | Codex |
| `lib/facturacion/**` | Codex |
| `lib/tokens_dian/**` | Codex |
| `lib/home/*task*`, `lib/widgets/task_*`, `lib/core/task_*`, `lib/services/task_service.dart` | Codex |
| `lib/core/app_catalog.dart`, navegación y matriz de acceso a módulos nuevos | Codex |

Fronteras compartidas que **sí** hay que negociar antes de tocar:

- `lib/services/task_service.dart` es de Codex. Claude lo necesita para que el
  rechazo de un acta cree la tarea de corrección, pero **no lo va a editar**:
  llama a `createTaskEs(...)`, que ya existe (línea 248). Si hiciera falta un
  método nuevo, se pide aquí antes de escribirlo.
- `lib/home/home_screen.dart`, `lib/core/app_catalog.dart` y la matriz de acceso
  quedan en Codex porque son navegación, roles e integración. Claude entrega el
  contrato del módulo y no edita esos archivos.
- `pubspec.yaml`, la versión, la consolidación, las pruebas finales y Git quedan
  en Codex. Si Claude necesita una dependencia, la propone aquí primero.

---

### Claude — permisos de lo que ya está al aire, más lo nuevo

**P0 · Seguridad transversal antes de publicar módulos sensibles**

- [ ] Cerrar reglas explícitas por empresa, módulo y rol para Biblioteca,
      formatos, Planillas y datos bancarios. Los permisos de la interfaz no
      sustituyen las reglas de Firestore.
- [ ] Añadir pruebas de aislamiento multiempresa y de denegación por rol.
- [ ] Preservar los cambios locales que ya existen en Interventoría; revisar el
      diff antes de editar y no rehacer lo que ya esté implementado.

**P0 · Interventoría** (todo el módulo, correcciones del docx + notas)

- [x] Quitar el "sugerido" de la asignación automática de tareas.
- [x] `Por revisar`: quitar a terceros distintos de Kary y Gerencia.
- [x] `Subsanaciones`: calidad y demás roles en **solo lectura**, sin poder
      reasignar responsables.
- [x] Maestro de responsabilidades: separar `Administrador tipo 1` de
      `Administrador tipo 2` para que la tarea caiga en el rol correcto según
      el establecimiento.
- [x] Rechazo de acta por calidad → genera automáticamente la tarea de
      corrección al administrador del establecimiento, editable desde el
      histórico.
- [x] Exportar la tabla de subsanaciones.
- [x] GUI del reporte: poder "recoger" el acta para ganar espacio, y ventana
      flotante con el detalle al tocar una barra del indicador.
- [ ] Mostrar de forma visible los elementos pendientes de revisión por
      Calidad. Esta observación pertenece a Interventoría, no al semáforo de
      fichas técnicas de Compras.
- [x] Datos maestros: Adriana Rojas es de Tunja. · [ ] Revisar numerales.

**P0 · Correspondencia**

- [ ] El código de tipo documental debe aceptar **exactamente 3 caracteres**.
      La validación ya existe (`gd_correspondencia_service.dart:139`,
      `gd_tipos_documentales_screen.dart:412`); lo que falla es la asignación
      de correos, que se queda a medias. Reproducir y corregir el filtro.

**P1 · Motor de maestro de formatos + Biblioteca Documental**

`NUEVOS MODULOS.xlsx` agrupa seis frentes (Biblioteca, Visitas, Informe Técnico,
Mantenimiento, Nutrición y Rutas/HSE). Varios comparten el mismo patrón de
campos, anexos obligatorios, revisión de Calidad y formatos por empresa. Esa
parte común es un motor y cada frente aporta su configuración; no se deben
crear seis copias de la misma lógica.

- [ ] Motor: formato = departamento + código + campos fijos + campos variables
      + restricciones de anexo + flujo de aprobación por calidad.
- [ ] Extender la Biblioteca Documental existente (`gd_*`), no crear un segundo
      módulo paralelo: subir formato diligenciado, calidad revisa /
      aprueba / rechaza, y **solo se descarga lo aprobado y no editable**.
- [ ] Documentos del contrato: internos (RUT, RIT, cert. bancario, contrato,
      anexos, otrosí) y externos (circulares). Carga **uno a uno**, nunca
      masiva — se decidió así en la reunión para evitar confusiones.
- [ ] Biblioteca queda **separada** de gestión de correspondencia: son módulos
      distintos (decisión de la reunión).

**P1 · Archivo plano de nómina — validación y prototipo**

El CSV de Alejandra ya llegó. Es un plano bancario por columnas: identificación,
tipo de id, dígito de verificación, apellidos y nombres, forma de pago, banco,
tipo de cuenta, número de cuenta, código de oficina, fecha límite partida en
año/mes/día, importe y hasta cuatro conceptos.

- [x] Añadir el generador al módulo existente de Planillas de Pago, con modelo,
      validaciones y exportación CSV compatibles con el ejemplo recibido; no
      crear un módulo de nómina nuevo. **Hecho el núcleo**
      (`pp_archivo_plano.dart`); falta la pantalla y el origen de los datos.
- [x] Conservar códigos y cuentas como texto cuando tengan ceros a la izquierda,
      fecha separada en año/mes/día, importes con dos decimales y total en la
      cabecera. Probar sin incluir datos reales de los beneficiarios. Hecho: las
      pruebas del repositorio usan datos inventados, y la comprobación contra el
      archivo real se hizo con un test temporal que ya se borró.
- [ ] No asumir que el XLSX es una macro funcional: no contiene VBA y conserva
      varios nombres definidos con `#REF!`. Usarlo como especificación del
      layout y validar el CSV producido. El viernes de la transcripción era el
      plazo para recibir el insumo, no una fecha confirmada de entrega del módulo.

**P2 · Mantenimiento** — maquetado sobre el motor de formatos (compromiso de
"para el día siguiente" de la reunión).

---

### Codex — los dos módulos en producción con más correcciones pendientes

**P0 · Compras** (`Correciones COMPRAS.docx`, todo el módulo)

- [ ] **Quitar** de la ficha técnica el campo, validación, bloqueo y alerta de
      `Vigente hasta`. La transcripción dice literalmente “quitar eso”; no se
      pidió agregar vigencia.
- [x] Creación de marca: el mensaje de error es incorrecto. Hecho por Claude:
      hablaba del producto cuando lo que falta es la ficha de la marca, y
      culpaba al proveedor de un documento que no existe en ninguna parte.
- [x] Error al ver el detalle de una ficha técnica durante la entrada de
      producto. Hecho por Claude: `_abrirUrl` tenía dos `return` silenciosos,
      así que el botón se pulsaba y no pasaba nada. **Falta confirmar con el
      pantallazo del docx que era eso y no otra cosa.**
- [ ] **Registro sanitario no va en el producto, va en el proveedor.** Hoy
      vive en `documentosAsociados` de la marca
      (`compras_dashboard_screen.dart`, ~12 usos; `compras_models.dart:171`;
      `compras_validation.dart:17`). Codex hace la lectura compatible y el flujo
      en `lib/compras/**`; Claude prepara una migración auditable que reporte
      relaciones ambiguas y no borre el origen hasta validar el destino.
- [ ] En una recepción, no permitir agregar otra fila de producto mientras
      exista una fila anterior vacía o incompleta; evita acumular productos
      indefinidos sin bloquear una recepción válida con varios productos.
- [ ] Indicador de presencia en la marca: verde si tiene al menos una ficha
      técnica y rojo si no tiene. El estado de Calidad de cada ficha sigue
      mostrándose en su detalle, sin confundir “archivo presente” con “aprobado”.
- [ ] Descartar el supuesto fallo del filtro del histórico de recepciones: en la
      transcripción se confirmó que era un filtro seleccionado por el usuario y
      se pidió ignorarlo.

**P0 · Facturación**

- [x] **El filtro por mes.** El acta lo describía mal: el conteo SÍ usaba el
      filtro. Lo que mentía era la etiqueta de al lado ("6 de 11 · Mes: julio"
      con agosto seleccionado) y, peor, abrir esa fila entraba al mes del
      establecimiento y no al del filtro. Hecho por Claude.
- [x] Semáforo: rojo por debajo del 50 %, naranja intermedio, verde solo al
      100 %. Eran tres copias de la regla y las tres daban rojo en el 50 %
      exacto. Hecho por Claude.
- [x] Exportar en `.zip` cuando todos los documentos estén cargados. **Ya
      estaba hecho**: `_descargarZip` existe y el botón sale solo con
      `_todoCompleto`. No hacía falta tocar nada.
- [x] Limpieza de la interfaz. **Cerrado sin cambios**: preguntado el 10 sep,
      no sobra ningún campo. Lo que molestaba de los filtros era el mes que no
      correspondía, y eso ya está.

**P1 · Tareas**

- [x] Permitir reasignar una tarea a **otro departamento**. Implementado por
      Claude y cubierto por las pruebas de opciones de asignación.
- [ ] Antes de ampliar permisos, validar si todavía se necesitan observaciones
      de seguimiento por otras áreas. En la reunión quedó como propuesta de
      última prioridad porque el seguimiento ya puede hacerse en la tarea.

**P2 · Tokens DIAN**

- [x] Filtro por empresa y soporte para habilitar el módulo en FYC. El callable
      ya consultaba por `empresaId`; se añadió filtrado defensivo en cliente y
      pruebas de aislamiento. La asignación a FYC y la conexión de su buzón se
      hacen desde Administración.

**Cierre de Codex**

- [ ] Integrar los contratos entregados por Claude con navegación, empresa
      activa, roles y permisos por usuario.
- [ ] Ejecutar pruebas funcionales por rol y por plataforma, verificando que Web
      use tablas/filtros persistentes/maestro-detalle y Móvil mantenga flujos
      compactos por tarea.
- [ ] Revisar el árbol sucio, incluir solo archivos de esta tanda y realizar los
      únicos `git add`, `git commit` y `git push` autorizados.

---

### Lo que NO tomó nadie (y por qué)

No es olvido: es que no hay especificación suficiente para escribirlo bien.

- **Visitas de profesionales** e **Informe técnico**: Claude puede definir el
  esquema común y los contratos técnicos, pero no se construyen los formularios
  finales. Oscar quedó de recoger con los directores qué se diligencia en cada
  visita y hay una reunión pendiente para cerrar campos fijos, variables y las
  93 obligaciones del informe. La reunión dejó el informe mensual para el final.
- **Nutrición** y **Rutas/HSE** como maestros de formato: salen casi gratis
  una vez exista el motor de `lib/core/maestro_formatos/`. Ya existen módulos
  de Nutrición y Rutas: se extienden después, no se duplican ni se hacen en
  paralelo al motor.
- **Crear la nueva empresa con el RUT** y el **traslado a F&C**: es carga de
  datos y configuración, no código.
- **Verificación de Google (Gmail)** y **plantillas de Meta (WhatsApp)**:
  trámites externos con demora de días. No dependen de nosotros.

---
## Política de versiones (leer antes de tocar `version:` en pubspec.yaml)

Las dos plataformas leen la versión de **un solo sitio**: `version: X.Y.Z+N` en
`pubspec.yaml`.

- Android: `versionName` y `versionCode` salen de `flutter.versionName` /
  `flutter.versionCode` en `android/app/build.gradle.kts`.
- iOS: `CFBundleShortVersionString` y `CFBundleVersion` usan
  `$(FLUTTER_BUILD_NAME)` y `$(FLUTTER_BUILD_NUMBER)` en `ios/Runner/Info.plist`.

Estaban hardcodeadas a `2.3` en el Info.plist, lo que obligaba a editar el
archivo a mano en cada release. Se corrigió.

### Por qué la versión arranca en 2.4.0 y no en 1.0.0

La app **ya existía en App Store Connect** con bundle ID
`com.capitaluspec.gestionapp`, bajo el nombre "To-Do", con este historial:

| Versión | Estado | Fecha |
|---|---|---|
| 2.1 | Listo para distribución | 21 feb 2026 |
| 1.1 | Listo para distribución | 11 dic 2025 |

Las versiones de App Store **solo pueden subir**. Un build 1.0.0 sobre un
linaje que ya llegó a 2.1 lo rechaza Apple automáticamente. Por eso el punto de
unificación tuvo que quedar por encima de 2.1, no en 1.0.0.

Se eligió 2.4.0 y no 2.2 por margen: el Info.plist tenía 2.3 hardcodeado, lo que
sugiere que en algún momento se preparó un build con ese número. Si un
`versión + build` llegó a subirse alguna vez a App Store Connect, ese par queda
consumido aunque nunca se publicara.

Android no tiene problema con el salto: su `versionName` es texto libre y puede
pasar de 1.0.0 a 2.4.0 sin más. Lo único que Play exige es que el `versionCode`
aumente siempre.

### Códigos ya consumidos

- **Play**: 1, 2, 3 y 4. El 3 quedó publicado en prueba cerrada Alpha.
- **App Store**: versiones 1.1 y 2.1 publicadas.

Ninguno se puede reutilizar en ninguna de las dos tiendas.

### No borrar la app de App Store Connect para "empezar limpio"

Apple **nunca libera un bundle ID** que ya estuvo asociado a una app, aunque se
borre. `com.capitaluspec.gestionapp` quedaría inutilizable para siempre. Y una
app ya aprobada no se puede eliminar del todo: se retira de la venta, pero el
registro, las reseñas y el historial se pierden sin recuperar el identificador.

### Los bundle ID de las dos tiendas son distintos, y está bien

- Android: `com.todogestion.app`
- iOS: `com.capitaluspec.gestionapp`

Son espacios de nombres independientes. Lo que importa es que cada uno sea
consistente consigo mismo: en iOS, que coincidan Xcode, `GoogleService-Info.plist`
y `firebase_options.dart`, que es el caso.

---

## Versión 2.6.1 (15) — 2026-09-25

Lo que entró después de publicar la 2.6.0. Nada de esto toca reglas de
Firestore ni índices: es todo cliente, salvo dos funciones de WhatsApp.

### Interventoría: la asignación deja rastro y se puede reparar

Al completar un acta, la asignación de hallazgos ahora devuelve un **resumen
verificable** en vez de ocurrir en silencio: cuántos se asignaron, a quién y
cuáles quedaron sin responsable.

Se agregó una **reparación del rezago**: las versiones anteriores solo
*sugerían* el responsable en pantalla sin crear la tarea, así que hay
hallazgos viejos que nunca le llegaron a nadie. La reparación es idempotente
—ignora los que ya tienen `tareaId` y usa un id de tarea estable por
hallazgo—, así que puede correrse dos veces sin duplicar nada.

También entraron las **devoluciones como acción obligatoria**: un acta
devuelta deja una tarea que la persona no puede ignorar. La consulta va por
empresa (que es el campo que cubren las reglas) y el OR entre responsable
explícito y registrador histórico se resuelve en memoria, para no exigir un
índice compuesto nuevo.

### Talento Humano: cobertura de operación, distinta del centro de costos

El centro de costos es la **adscripción administrativa**; no dice dónde puede
trabajar la persona. Se agregó la **cobertura de operación**: las sedes donde
realmente puede atender visitas. `cubreCentro()` es lo que resuelve la
pregunta "¿esta persona puede ir a este establecimiento?", que antes se
respondía mirando el centro de costos y daba falsos negativos con quien cubre
varias sedes.

### Compras: plantilla oficial de abastecimiento

Se genera desde la aplicación (`abastecimiento_excel_template.dart`) en vez de
pasarse un archivo por correo, que es como terminan circulando tres versiones
distintas del mismo formato.

**El periodo de consumo no es una columna**: se elige explícitamente al cargar
y se aplica a toda la carga. Ponerlo por fila invitaba a archivos con la mitad
de los renglones en un mes y la otra mitad en otro, sin que nadie lo notara.

### Lo demás

- WhatsApp: ajustes en el panel de administración y en las dos funciones de
  notificación.
- Home, Admin, GD y el tablero de asignación: correcciones sueltas.

### Estado

`dart analyze` limpio · **871 pruebas** · functions compilan con lint en 0
errores.

---

## Sesión 2026-09-09 — Amonestaciones del reglamento y aviso al citado

### El cierre pasó de 4 resultados a 12, en dos grupos

El reglamento Capital USPEC 2025 separa dos cosas que antes estaban en el mismo
cajón, y la distinción **no es de redacción**: llamar sanción a un plan de
mejora tiene efectos laborales.

**Grupo A — medidas preventivas, correctivas o administrativas, expresamente NO
sancionatorias:** retroalimentación verbal, reinducción o capacitación,
requerimiento preventivo, acta de compromiso, plan de mejora, seguimiento
especial, corrección operativa o documental.

**Grupo B — sanciones disciplinarias:** amonestación escrita con carácter
disciplinario, suspensión hasta por ocho (8) días en la primera sanción,
suspensión hasta por dos (2) meses en caso de reincidencia, terminación del
contrato con justa causa.

Más `Exonerado`, que no es ninguno de los dos: no hubo falta.

Por eso el grupo viaja **con el valor** (`DisciplinaryOutcomeKind`) y no se
deduce en la pantalla. `isSanction()` responde la pregunta que de verdad
importa, y un informe que cuente sanciones no puede sumar un acta de
compromiso.

Las dos suspensiones son valores distintos a propósito: ocho días y dos meses
no se pueden colapsar en un "suspensión" genérico porque el plazo lo fija la
ley y depende de la reincidencia.

Los valores viejos (`llamado_escrito`, `suspension`) se siguen entendiendo en
`label()` para que un proceso cerrado antes no aparezca como "—", pero ya no se
ofrecen al cerrar.

### Exonerar dejó de pedir gravedad

Calificar la gravedad de algo de lo que se exonera es contradictorio. El campo
desaparece del formulario al elegir Exonerado, y el servicio lo rechaza si
llega lleno.

### El citado ahora sí se entera

`thNotificarCitacionDescargos` — disparador de Firestore sobre
`TBL_LLAMADOS_ATENCION`, que corre al cruzar a la etapa `citacion`. Antes el
proceso avisaba a Talento Humano pero no a la persona citada, que es justamente
quien tiene que presentarse.

Sale por dos canales:

- **Notificación en la app**, al centro único (`TBL_NOTIFICACIONES/{cedula}`).
  El id es determinista (`disciplinario_citacion_{procesoId}`) y se escribe con
  `create()`: un guardado posterior sobre el mismo proceso no vuelve a citar a
  nadie.
- **WhatsApp** al número registrado, con `sendWhatsAppDirect`.

Sobre el teléfono: la ficha guarda el dato con varios nombres según la época
(`celular`, `telefono`, `numeroCelular`, `phone`) y parte vive en la hoja de
vida. Hay que mirar en todos — un campo vacío aquí es una citación sin avisar.

El resultado de cada canal queda escrito en el proceso (`avisoCitacion`), para
poder responder después "¿le avisamos o no?" sin adivinar.

### El correo NO se envió, y no es un olvido

**El proyecto no tiene envío de correo saliente.** `imapflow` y `mailparser`
solo *leen* IMAP; no hay `nodemailer`, ni SMTP, ni SendGrid, ni la extensión
Trigger Email. Se revisó `functions/src`, `lib/` y `package.json`.

El disparador deja el canal anotado como `pendiente:sin_envio_saliente` en vez
de fingir que salió. Habilitarlo es una decisión aparte: hay que elegir la
cuenta emisora y sus credenciales.

---

## Sesión 2026-09-08 (ronda 5) — El deploy de functions fallaba por el antivirus

`firebase deploy --only functions:...` fallaba de dos formas encadenadas y
ninguna tenía que ver con el código.

### Síntoma 1: "Cannot determine backend specification. Timeout after 10000"

Firebase carga `lib/index.js` en un proceso aparte para enumerar los exports.
Ese paso se rindió a los 10 segundos. Se sube el plazo con una variable de
entorno, que hay que poner en la **misma** consola que lanza el deploy:

```powershell
$env:FUNCTIONS_DISCOVERY_TIMEOUT = 180
```

El código no era el problema: cargado a mano, `lib/index.js` tarda 1,2 s y no
deja ningún handle abierto.

### Síntoma 2: TS5033 "Could not write file" en cuatro archivos

Siempre los mismos: `correo.js`, `index.js`, `whatsapp.js` y
`workflow_whatsapp_notifications.js`.

Lo que descartó las hipótesis fáciles:

- **No es un proceso colgado.** Ningún proceso tiene el proyecto abierto
  (`Get-Process | Where Path -like *capital-uspec*` no devuelve nada), y el
  puerto 8350 del discovery queda libre.
- **No es permisos.** Los archivos son `Archive`, no `ReadOnly`.
- **No es el predeploy.** Correr a mano `npm run lint && npm run build` —los dos
  comandos exactos del predeploy— funciona.
- **No están bloqueados.** Antes y después del fallo se abren para escritura sin
  problema.

Lo que sí es: **Defender en tiempo real** (`DisableRealtimeMonitoring: False`)
toma los `.js` recién escritos el tiempo justo para que la **sobrescritura**
falle. Por eso siempre los cuatro más grandes, que además son los que llevan
código de red — `correo.js` pesa 158 KB e `whatsapp.js` 78 KB.

La prueba definitiva: `npm run build` (que ahora borra `lib/` antes) pasa dos
veces seguidas, y `npm test` —que corría `tsc` pelado sobre el `lib/`
existente— fallaba en esos mismos cuatro.

### El arreglo: crear en vez de sobrescribir

Borrar el directorio antes de compilar esquiva el problema, porque crear un
archivo nuevo no necesita abrir el viejo.

```json
"clean": "node -e \"require('fs').rmSync('lib',{recursive:true,force:true})\"",
"build": "npm run clean && tsc",
"test": "npm run build && node --test test/*.test.js",
```

Se usa `fs.rmSync` de Node y no `rm -rf` ni `rimraf`: funciona en Windows sin
agregar dependencias. `lib/` es solo salida de tsc —23 archivos, todos `.js`—
así que borrarlo no pierde nada.

Con eso, `npm test` pasa tres veces seguidas (44/44) y el deploy entró.

Si vuelve a molestar, la solución de fondo es una exclusión de Defender para la
carpeta del proyecto, pero eso pide permisos de administrador.

### Quedó desplegada

`thNotificarPlazosDisciplinarios · scheduled · us-central1 · nodejs20`, el cron
de las alertas del proceso disciplinario. Corre a las 7:00 de Bogotá.

---

## Sesión 2026-09-08 (ronda 4) — Borrar novedades del historial de un requerimiento

Talento Humano registra un avance con el texto equivocado, o en la vacante
equivocada, y ese renglón queda para siempre en el informe que va a
interventoría. Se pidió poder borrarlo.

### El historial es un arreglo, y eso decide el diseño

`historial` vive dentro del documento del requerimiento, no en una
subcolección. Borrar "la tercera novedad" es borrar lo que haya en esa posición
**cuando llegue la escritura**, no lo que el usuario vio: si otra persona
registró un avance en el intervalo, se va el equivocado.

Por eso cada novedad ahora nace con `id` propio, generado con
`_db.collection(collection).doc().id` — un documento de Firestore que nunca se
escribe, que es la forma barata de tener un identificador único sin agregar
`uuid` como dependencia. Los siete sitios que escribían en `historial` pasan
ahora por un único helper `_novedad()`.

Las novedades que ya estaban guardadas no tienen `id`. Se reconocen por su
**huella**: `fecha en microsegundos | usuario | nota`. Alcanza porque
`Timestamp.now()` llega al microsegundo, así que dos novedades distintas no
coinciden en las tres cosas. `mapMatches()` centraliza la comparación y le da
prioridad al id: una novedad vieja no puede hacerse pasar por una nueva.

### Se borra en transacción y reescribiendo el arreglo

Ni `arrayRemove` ni índice:

- `arrayRemove` con un mapa "igual" se llevaría también las novedades
  duplicadas, y exige que el mapa coincida campo por campo.
- El índice se corre si alguien escribe en el intervalo.

`deleteHistoryEntry` lee dentro de la transacción, filtra por llave sobre los
**mapas crudos** (no sobre los objetos tipados, para no perder campos que el
modelo todavía no conoce) y reescribe el arreglo completo.

Dos guardas: si la llave no aparece se avisa "esa novedad ya no está" en vez de
escribir en vano, y no se permite dejar el historial vacío — una vacante sin
rastro de cuándo se abrió no le sirve a nadie.

### Lo que borrar NO hace, y hay que decirlo antes

La etapa de la vacante **no vuelve atrás**. Si el avance equivocado movió la
solicitud a "entrevistas", borrar el renglón lo quita del informe pero la
vacante sigue en entrevistas. El diálogo de confirmación lo dice, y explica que
eso se corrige registrando el avance correcto.

Permiso: solo el gestor (`access.canDelete`), el mismo que puede eliminar el
requerimiento completo. Borrar rastro es la misma clase de acción destructiva.

### Dos cosas que estaban mal en esa pantalla y se arreglaron de paso

**La stream se creaba dentro de `build`.**
`stream: _service.streamForCompany(widget.empresaId)` montaba un listener nuevo
en cada repintado — exactamente lo que en web termina en "INTERNAL ASSERTION
FAILED" de Firestore. Ahora vive en `_rows` y solo se rehace al cambiar de
empresa.

**El historial mostraba la cédula cruda**: `'Por ${entry.userId}'`, contra la
regla transversal 4 de `CLAUDE.md`. Pasó a `UserNameText`.

### De paso: el cargo antes de la fecha

En la reunión se dio por hecho ("no, mira, ya está"), pero solo estaba en el
**PDF**. La tabla en pantalla y el Excel seguían con `Fecha` antes de `Cargo`.
Ya quedan los tres iguales.

El semáforo (`Tiempo`, `Estado`) se conserva adelante: Zuly dijo que la alerta
está bien, lo que pedía era no tener que buscar el cargo. El test del Excel
comprobaba la columna 6 y ahora comprueba la 2, que es donde quedó.

### El detalle móvil estaba congelado

La hoja de `showModalBottomSheet` se quedaba con la copia del requerimiento del
momento en que se abrió. Al borrar una novedad parecía que no había pasado nada
hasta cerrar y volver a abrir — y eso invita a borrar dos veces. Ahora la hoja
escucha `_rows` y se cierra sola si el requerimiento desaparece. Beneficia
también a agregar aspirantes y registrar contrataciones, que tenían el mismo
problema.

---

## Sesión 2026-09-08 (ronda 2) — El disciplinario listaba la empresa entera de un tirón

El panel izquierdo de `disciplinary_management_screen.dart` (las carpetas del
personal) pintaba `ListView.separated` con `itemCount: filtered.length`, y la
carpeta de cada persona recorría sus procesos con un `for` suelto dentro de la
columna. Ninguno de los dos pasaba por `lib/widgets/paged_list.dart`, que es la
regla transversal 1 de `CLAUDE.md`: **20 por página, sin excepciones**.

### Qué se rompía de verdad

Conviene ser exacto, porque el `ListView.separated` es perezoso y solo construye
lo que se ve: no había un cuelgue. Lo que había era otra cosa.

- Una empresa de 400 personas se recorre a rueda, sin forma de saltar. El
  buscador ayuda si ya sabes el nombre; si estás revisando, no.
- Cada tecla en el buscador dispara `setState`, y con él se rehace el filtro
  completo más los mapas `counts` y `alerts` sobre **todos** los procesos de la
  empresa. Con la página acotada, ese trabajo por tecla es el mismo, pero la
  lista que se reconstruye ya no es de 400 tarjetas potenciales sino de 20.
- Y sobre todo: era una pantalla que no cumplía el contrato de la app. Un
  listado que se comporta distinto al resto obliga a aprender dos veces.

### La página vuelve a 1 con la clave, no con el clamp

`PagedListSection` ya se defiende sola cuando la lista **se acorta**:
`didUpdateWidget` baja la página a la última válida. Eso no alcanza aquí.

Si estás en la página 4 de "Todos" (137 personas) y escribes un apellido que
deja 90 coincidencias, la página 4 sigue existiendo: no ves un vacío, ves las
personas 61-80 de un resultado nuevo, que es peor porque parece correcto. Lo
mismo al saltar de "Activos" a "Inactivos".

Se resolvió como en el maestro de subsanaciones de Interventoría: la clave del
widget lleva los filtros.

```dart
key: ValueKey('$term|$_peopleFilter'),                 // carpetas del personal
key: ValueKey('${person.cedula}|$_recordFilter'),      // procesos de la carpeta
```

Cambiar el término, el segmento, la persona o el filtro de procesos monta un
`State` nuevo y `_page` arranca en 0. Es una línea y no hay que sincronizar
nada a mano.

### Detalle de montaje: el `Expanded` necesita su propio scroll

`PagedListSection` no scrollea (`mainAxisSize.min`, pensada para vivir dentro de
una columna que ya scrollea). Dentro del `Expanded` del panel hay que darle uno:
`SingleChildScrollView` con el `padding` que antes llevaba el `ListView`. Es el
mismo montaje que usa `_TablaMaestro` en Interventoría.

Se conservan sin tocar el resaltado de la carpeta abierta, el `_CountBadge` con
el número de procesos y el ícono rojo de plazo vencido: la tarjeta es la misma
`_PersonFolderTile`, solo cambió quién decide cuántas se pintan.

### Lo que se revisó y se dejó igual

No todo lo que se repite es un listado extenso. En este módulo quedaron fuera a
propósito:

- `_metricsGrid`: 4 tarjetas fijas (Total / En trámite / Vencidos / Cerrados).
- `_StageTrack`: las 4 etapas del proceso.
- `_RecordTimeline` ("Trazabilidad interna"): es el historial de **un** proceso,
  y en `disciplinary_service.dart` solo hay 6 sitios que escriben eventos, todos
  atados a un cambio de etapa. Tiene techo natural; paginar 6 filas estorba.

### Lo que sigue debiendo en Talento Humano

El barrido del 2026-08-25 (ronda 3) convirtió las tablas de la app, pero las
listas de tarjetas de este módulo se quedaron atrás. Siguen pintando completo:

| Pantalla | Listado |
|---|---|
| `areas_management_screen.dart` | lista de áreas; personal asignado al área |
| `cargos_management_screen.dart` | lista de cargos; orden jerárquico; personal del cargo |
| `centros_costos_management_screen.dart` | lista de centros; personal del centro |
| `hv_dashboard_screen.dart` | personas detrás de cada indicador |
| `notificaciones_talento_humano_screen.dart` | historial de notificaciones |
| `organizational_structure_screen.dart` | movimientos de personal; listado de registros |
| `personnel_requisition_screen.dart` | tarjetas de requerimientos en móvil |
| `zeus_export_screen.dart` | pendientes de exportación |

Los de "personal asignado a…" son los urgentes: son justamente los que crecen
con la plantilla. `personnel_access_screen.dart` ya pagina con `pageOf` +
`PagerBar`, y en Requerimientos solo falta el camino móvil — el de escritorio ya
usa `PagedDataTable`.

`dart analyze lib/talento_humano/` no reporta nada nuevo (los 21 avisos son
previos, en otros archivos) y `flutter test test/talento_humano/` pasa los 100.

---

## Sesión 2026-09-08 (ronda 3) — Cédula opcional + documentos de finalización

Dos cosas de la reunión del mismo día.

### La cédula del aspirante era la llave, no un dato

Talento Humano pidió que el documento fuera opcional: *"citamos solo con el
nombre de acuerdo a la hoja de vida, mucha gente no pone las cédulas"*.

Pero quitar el `validator` habría roto el módulo en silencio.
`PersonnelCandidate` se identificaba **por su documento**:

```dart
current.candidates.indexWhere((item) => item.document == target)
```

Con dos aspirantes sin cédula, mover a uno de etapa movía al otro, y el segundo
sin cédula ni siquiera entraba: el chequeo de duplicados lo rechazaba con "ese
aspirante ya está en la solicitud".

Ahora hay `candidatoId`, generado con `_db.collection(...).doc().id` (id de
Firestore sin escribir nada). `PersonnelCandidate.key` devuelve el id propio, o
el documento en los registros viejos que no lo tienen — así la migración es
nada. `matches()` centraliza esa comparación.

Tres reglas que cambiaron con esto:
- El duplicado **solo** se puede afirmar si el aspirante trajo cédula. Sin ella,
  dos "Juan Pérez" pueden ser dos personas.
- `updateCandidateStage` recibe `candidateKey`, no `document`.
- Al contratar sí hay cédula. Si el aspirante se había registrado sin ella, se
  reconcilia **por nombre** contra los que siguen vivos y no tienen documento, y
  se le llena la cédula. Sin eso, la contratación creaba una ficha duplicada y
  la original se quedaba congelada en su etapa.

La observación sigue siendo opcional al registrar y obligatoria al avanzar de
etapa, que es donde de verdad sustenta el informe de interventoría. No se tocó.

### Documentos de finalización de contrato

Módulo nuevo, con el nombre que eligieron en la reunión. Tres papeles fijos:
carta laboral, certificado de cesantías y orden de exámenes médicos de egreso.

**El certificado de cesantías no es para todos** (*"yo te avisaré quiénes son"*),
así que Talento Humano lo marca por persona. La marca no es cosmética: define
`tiposEsperados`, y sin ella el portal no puede distinguir entre "no le toca" y
"le toca pero aún no lo subimos", que para el trabajador son cosas distintas.

**El portal es del trabajador.** `MisDocumentosFinalizacionScreen` sale del
perfil, no del menú de Talento Humano, y no tiene búsqueda ni listado: la
cédula viene de la sesión. No es un módulo del catálogo — lo tiene todo el
personal, como notificaciones y calendario.

### La combinación de correspondencia (reemplaza la macro)

`lib/talento_humano/plantilla_combinacion.dart`. Se sube un Word con
marcadores `{{NOMBRE}}` y un Excel con una fila por persona, y sale un .zip.

**Lo difícil no es el reemplazo, es que Word parte los marcadores.** Word
guarda el texto en `<w:r>` y lo corta cada vez que cambia una propiedad — y el
corrector ortográfico corta incluso donde no cambia nada. Un `{{NOMBRE}}`
escrito de una sentada puede quedar como `{{NOM` + `BRE` + `}}` en tres nodos.
Un `replaceAll` sobre el XML no encuentra nada y el documento sale con los
marcadores impresos.

El algoritmo: por cada `<w:p>` se aplana el texto de sus `<w:t>`, se busca el
marcador en el texto plano, y el valor se escribe **completo en el primer nodo
que tocaba** (así hereda su formato) borrando de los demás solo el pedazo
cubierto. Los nodos que el marcador no tocaba quedan intactos, con su negrita y
su tamaño. Se trabaja por párrafo y no sobre todo el XML para que un `{{` suelto
al principio no se empareje con un `}}` suelto al final y borre el documento
entero.

Detalles que estaban en la trampa:
- `xml:space="preserve"` al escribir, o Word recorta y "Señor {{NOMBRE}}" queda
  como "SeñorJUAN".
- Se reemplaza también en `header*.xml` y `footer*.xml`: los marcadores viven en
  el membrete tan seguido como en el cuerpo.
- Las claves se normalizan sin tildes ni mayúsculas, así "Número de Documento"
  del Excel casa con `{{NUMERO DE DOCUMENTO}}` del Word.
- Un marcador sin columna que lo alimente **se deja impreso** en vez de salir en
  blanco: así se ve que faltó una columna, en vez de firmar cien cartas con un
  hueco. Además se avisa antes de generar.
- Dos filas sin cédula ni nombre no se pisan dentro del zip.

18 pruebas en `test/talento_humano/plantilla_combinacion_test.dart`, incluida la
de un marcador partido carácter por carácter.

### La plantilla se guarda; el Excel es lo único que cambia

`TBL_TH_PLANTILLAS_DOCUMENTOS` guarda el Word por empresa y tipo, con sus
marcadores ya leídos. La primera vez es la única vez: de ahí en adelante,
generar el lote es subir el Excel y darle a generar.

### Lo que el .zip trae, y lo que falta

Trae **.docx**, no PDF. Convertir Word a PDF necesita un renderizador
(LibreOffice headless o similar) que no existe en el proyecto. Para el flujo
descrito da igual: esos documentos se imprimen y se firman, y lo que sube al
portal después es el PDF firmado.

Falta la segunda parte que pidió Zuly: subir un lote de PDF ya firmados y que el
sistema los reparta solo a cada carpeta por la cédula del nombre del archivo.
Hoy se archivan uno por uno desde la pestaña "Carpetas del personal".

### Reglas y almacenamiento

Las dos colecciones nuevas (`TBL_TH_DOCUMENTOS_FINALIZACION` y
`TBL_TH_PLANTILLAS_DOCUMENTOS`) entran por el `match /{collection}/{document=**}`
de `firestore.rules`, así que **no hubo que tocar reglas**. Ojo con lo que eso
implica: como en el resto de la app, cualquier usuario autenticado puede leer la
colección; el portal limita por pantalla, no por regla.

Storage usa `talento_humano/finalizacion/...`, hermano de
`talento_humano/llamados/...` que ya funciona. `storage.rules` no está en el
repo (se administra en la consola): conviene confirmarlo en la primera carga.

---

## Sesión 2026-09-08 — Proceso disciplinario: cuatro pasos, no un formulario

El módulo pedía a Talento Humano **redactar la falta** al abrir el proceso
(asunto, descripción de los hechos, gravedad, referencia normativa, acción
esperada). Eso está mal repartido: quien abre el proceso no es quien juzga, y
en el paso 1 lo único que existe es un documento que llegó.

El proceso real tiene cuatro pasos, y en cada uno lo que importa es **un
documento y una fecha**:

| Paso | Qué se monta | Fecha | Alerta |
|---|---|---|---|
| 1 | Solicitud de apertura recibida | Fecha de recibido | — |
| 2 | Citación entregada al colaborador | Fecha de la diligencia (5 días hábiles) | **Sí** |
| 3 | Acta de la diligencia de descargos | Fecha límite del resultado | **Sí** |
| 4 | Documento del resultado | Fecha del resultado | Cierra |

### El cierre ya no es texto libre

Antes se cerraba escribiendo una "conclusión" a mano. Ahora se cierra con una
de **cuatro sanciones y ninguna más**, porque la sanción tiene efecto laboral:

- Exonerado
- Llamado de Atención Escrito
- Suspensión del contrato
- Terminación de contrato por justa causa

### La gravedad no desaparece: se muda al cierre

En la reunión del mismo día quedó claro que la gravedad sí hace falta, pero
**solo en el paso 4**. Ayli: *"el tipo de gravedad sería un botón que puedes
dejar, pero solo para el cierre, porque en el cierre ya se sabe cómo te
califica esa diligencia"*.

La escala también cambió: **leve / grave / gravísima**, no la vieja
leve/media/alta. Pedirla al abrir obligaba a Talento Humano a prejuzgar un caso
que todavía no había oído.

### Salida temprana: "No corresponde"

Zuly: *"yo puedo decir validé la situación y no, este informe no va para proceso
disciplinario, no corresponde, y ya se cerró el proceso"*.

Un proceso puede cerrarse **desde la solicitud**, sin citar a nadie. Se guarda
con `sancion: no_corresponde`, que a propósito **no** está en
`DisciplinarySanction.values`: esa lista alimenta el desplegable del paso 4 y
solo puede contener las cuatro sanciones reales. El descarte tampoco lleva
gravedad — no hubo diligencia que calificar — y su documento es opcional.

Ojo con la pantalla: un caso descartado no puede pintar las cuatro etapas
completas, porque diría que hubo citación y diligencia. `_StageTrack` detecta
`closedWithoutProcess` y dibuja `Solicitud → No corresponde`; los pasos 2 y 3
dicen "No aplica", no "Pendiente".

### Los 5 días son hábiles, y ya existían

`fechaDiligenciaSugerida()` reusa `sumarDiasHabilesColombia()` de
`lib/core/festivos_colombia.dart`: salta fines de semana **y festivos** (Ley
Emiliani incluida). Con días corridos, una citación entregada antes de Semana
Santa vencía antes de tiempo. La fecha se propone sola y se puede corregir a
mano; en cuanto alguien la mueve, deja de seguir a la citación.

### La alerta vive en un cron, no en la pantalla

`thNotificarPlazosDisciplinarios` (`functions/src/disciplinary_deadline_notifications.ts`)
corre a las 7:00 de Bogotá y avisa **el mismo día del vencimiento** a todo el
equipo de Talento Humano de la empresa dueña del proceso.

Se resolvió con cron y no en el cliente a propósito: una alerta que solo se
dispara cuando alguien abre el módulo es una alerta que se pierde el día que
nadie entra. El id de la notificación es determinista
(`disciplinario_{id}_{etapa}_{yyyymmdd}`) y se escribe con `create()`, así que
un reintento del cron no vuelve a sonarle a nadie.

Ojo con el destinatario: la membresía de empresa se guarda de dos formas
(`empresas[]` y `empresaId`) y los módulos también (`apps` global y
`empresasDetalle[empresaId].apps`). Hay que mirar las cuatro combinaciones, y
aceptar los ids cortos (`talento`, `talentohumano`) además del completo, o
media Talento Humano se queda sin alerta.

### Modelo en TBL_LLAMADOS_ATENCION

La etapa guardada es siempre **la última completada**, así que lo pendiente se
deduce sin campos extra y el proceso no puede saltarse pasos: cada método del
servicio exige la etapa anterior.

```
etapa: solicitud | citacion | diligencia | cerrado
fechaRecibido            + docSolicitud
fechaCitacion            + fechaDiligencia        + docCitacion
fechaDiligenciaRealizada + fechaLimiteResultado   + docDiligencia
sancion                  + fechaResultado         + docResultado
```

Los adjuntos dejaron de ser un `arrayUnion` sin etiqueta: cada documento vive
en su campo, porque el requisito es saber *cuál* es la citación y *cuál* el
resultado, no cuántos archivos hay.

### El dashboard ya no puede hablar de "gravedad"

`highSeverityCases` contaba procesos con `gravedad: alta`, campo que dejó de
existir. Se renombró a `overdueDisciplinaryCases` y ahora cuenta los que tienen
**el plazo de su etapa vencido**, que es la urgencia real. La tarjeta dice
"N con plazo vencido" en vez de "N de prioridad alta".

### Lo que la reunión dejó pendiente

De la misma reunión salieron cuatro requisitos que **no** son de este módulo y
quedaron sin hacer: documentos de finalización de contrato descargables por el
propio trabajador (carta laboral, cesantías, orden de exámenes de egreso) más
su generación masiva en ZIP; certificado de publicación de la vacante en el
Servicio Público de Empleo, adjuntable por cargo; cédula opcional al registrar
aspirantes (solo nombre y observaciones obligatorios); y carga de experiencia
laboral con contrato, fecha de ingreso y fecha de fin.

Queda una ambigüedad sin resolver: en la reunión se dijo "un botón que diga
generar [la citación]". No está claro si el sistema debe **producir** el PDF de
la citación desde una plantilla o si basta con adjuntar la que Talento Humano
ya redactó. Por ahora el botón se llama "Generar citación a descargos" pero
solo adjunta; generar el documento sería una funcionalidad aparte, con
plantilla por empresa.

### Dato de prueba eliminado

Había un solo registro en `TBL_LLAMADOS_ATENCION` (`GOXRozTawixuxHSyAsvI`,
EMPRESA_002, en la carpeta de Amalia Vasquez Ardila pero describiendo a otra
persona). Era la prueba con la que se levantó el requisito. Se borró con sus 2
eventos de historial y su PDF en Storage.

El lector de `DisciplinaryRecord` igual tolera registros del modelo viejo: sin
`etapa` se leen como "solicitud recibida" en vez de reventar.

---

## Sesión 2026-09-04 (ronda 6) — QR de carnet

Desde la hoja de vida aprobada se genera un QR para pegar en el carnet. Al
escanearlo se abre una página con foto, nombre, cargo, empresa y si la persona
sigue vinculada.

### El QR no lleva la cédula

Un carnet se fotografía, se comparte y termina en manos de cualquiera. La
cédula es un documento de identidad nacional **y** el ID de la persona en
varias colecciones: ponerla en el enlace convertiría el QR en una llave.

El enlace lleva un **token aleatorio** (`Random.secure()`, 32 caracteres) que
no dice nada de la persona. Si un carnet se pierde, "generar uno nuevo" rota
el token y el impreso deja de resolver, sin tocar nada más.

### La página la sirve una Cloud Function, no la app web

Servirla desde la app habría exigido abrir lectura pública sobre
`TBL_USUARIOS`. Las reglas de Firestore no se tocan: `carnetPublico` lee con
credenciales de administrador y entrega **solo** los cinco datos que decide.
La ruta `/carnet/**` está redirigida a la función desde `firebase.json`.

No expone correo, teléfono, dirección, salario ni nada de la hoja de vida.

### El estado se resuelve en vivo

El "personal activo" se lee en el momento de escanear, desde el
`estadoLaboral` del bloque de la empresa. Congelarlo al imprimir haría que el
carnet de alguien ya retirado siguiera diciendo que sigue vinculado hasta que
alguien lo regenerara, que es justo lo que un carnet no debe hacer.

### Detalle que casi se escapa

El paquete `pdf` usa Helvetica por defecto, que **no soporta Unicode**: los
nombres con tilde o ñ salían partidos. Los dos PDF nuevos de esta sesión (el
QR y el informe de reclutamiento) cargan `assets/arial.ttf`, igual que los
demás PDF del proyecto, y lo hacen a la defensiva: un PDF sin acentos es mejor
que ninguno.

**Requiere desplegar functions y hosting** para que el QR resuelva.

---

## Sesión 2026-09-04 (ronda 5) — Informe de avance de reclutamiento

Gerencia pidió un PDF que muestre el avance. Ya existía
`personnel_requisition_pdf.dart` —el informe de procesos de selección para
interventoría— pero **no lo llamaba nadie**: estaba escrito y nunca se conectó
a un botón. Ahora hay un botón "Informe PDF" que ofrece los dos, porque no son
el mismo documento.

### Por qué son dos documentos y no uno

El de interventoría lista **una línea por aspirante** con su etapa: es lo que
ellos piden, poder ver quién está en entrevistas y quién en exámenes.

Gerencia no necesita nombres. Necesita saber **cuánto falta, dónde está
trancado y desde cuándo**. Juntar las dos cosas haría que ninguna se lea.

### Qué muestra el de gerencia

- Vacantes solicitadas, cubiertas, por cubrir y % de cobertura.
- Procesos abiertos, días promedio y **el más antiguo**, resaltado a partir de
  30 días. El promedio solo puede esconder una vacante trancada de 90.
- Embudo: en qué etapa están las vacantes que faltan por cubrir.
- Tabla por establecimiento **ordenada por lo que falta**, no alfabéticamente.

### Decisiones de cálculo

- **Las canceladas no cuentan como solicitadas.** Sumarlas hundiría la
  cobertura por puestos que nadie espera que se llenen. Se reportan aparte.
- Los días se cuentan solo para procesos abiertos, y una fecha futura no
  produce días negativos.
- **No lleva ningún dato personal**: ni nombres de aspirantes ni documentos.
  Es un informe que circula por correo.

11 pruebas cubren el cálculo, que vive separado del PDF para poder probarlo.

---

## Sesión 2026-09-04 (ronda 4) — Accesos en bloque por cargo

El filtro por cargo ayuda a encontrar a los cuarenta, pero entrar de a una
persona en cuarenta es exactamente lo que hace que estas tareas no se hagan.

**Accesos del personal → "Asignar en bloque"**: se eligen uno o varios cargos,
uno o varios módulos, y si es dar o quitar. Antes de escribir nada dice a
cuántas personas alcanza.

### Salvaguardas, porque es un cambio masivo y sin deshacer

- **Doble confirmación**: primero se arma la operación viendo el conteo en
  vivo, después un diálogo dice qué módulos y a cuántas personas.
- **Solo lo que Talento Humano administra.** Pedir un módulo que no está en su
  catálogo no lo cuela: sería una puerta de atrás para dar accesos que no
  puede otorgar de a uno. Los módulos que gobierna Admin se conservan
  intactos, igual que en la edición individual.
- **Al quitar se eliminan todas las variantes del id.** El mismo módulo
  aparece escrito de varias formas en el padrón; quitar solo la forma exacta
  lo dejaría puesto sin que se note.
- **A quien ya está como debe no se le escribe.** Si no, quedaría registrado
  un cambio en su historial sin que nada hubiera cambiado.
- Casilla "Solo personal activo", encendida por defecto, que se puede quitar
  para alcanzar también a quien ya se retiró.

8 pruebas fijan estas reglas, incluida la de la puerta de atrás.

---

## Sesión 2026-09-04 (ronda 3) — Subcentros de costo

Cómbita está registrado una vez pero opera como **Alta** y **Media**. Picota,
como **ERE 1** y **ERE 2**. Al registrar un acta hacía falta poder decir a cuál
corresponde, sin que dejen de ser el mismo establecimiento.

### Por qué viven DENTRO del centro y no como centros aparte

La alternativa era un documento por subcentro en `TBL_CENTROS_COSTOS` con un
`padreId`. Se descartó por dos razones concretas:

1. **La asignación de hallazgos se rompería.** El responsable se resuelve
   buscando quién tiene el cargo *en el establecimiento*. La gente está
   adscrita a Cómbita, no a "Cómbita Alta". Partir el centro dejaría esos
   hallazgos sin responsable — justo el problema que se acababa de cerrar.
2. **Facturación y Talento Humano listan la misma colección.** Un documento
   nuevo por subcentro les aparecería como establecimiento independiente sin
   que nadie lo hubiera pedido.

Si algún día un subcentro necesita presupuesto o facturación propios, deja de
ser un subcentro: hay que promoverlo a centro, y eso es otro cambio.

### Lo que quedó

- `TBL_CENTROS_COSTOS.subcentros`: lista de `{id, nombre, enabled}`. El lector
  acepta también textos sueltos, para poder sembrarlos desde la consola de
  Firebase sin romper la app.
- **El id no se recalcula al renombrar.** Queda escrito en las visitas y
  hallazgos ya registrados; recalcularlo dejaría el histórico apuntando a nada.
- Admin → Catálogos → Centros de Costos: chip **Subcentros** por establecimiento,
  con agregar, apagar y quitar. Apagar deja de ofrecerlo sin tocar el histórico.
- Al registrar un acta, si el establecimiento está dividido **es obligatorio**
  elegir el subcentro: "Cómbita" a secas no identifica nada y después no hay
  forma de saber cuál era.
- La visita y el hallazgo guardan `subcentroId` y `subcentroNombre`. El
  responsable se sigue resolviendo por `centroCostoId`, que es lo que hace que
  todo lo anterior siga funcionando.
- Los listados muestran `Cómbita — Alta` en vez de dos "Cómbita"
  indistinguibles.

---

## Sesión 2026-09-04 (ronda 2) — Interventoría: tres actas, no una con variantes

Llegaron dos formatos nuevos: **Instalaciones físicas y sanitarias -
Infraestructura** (1 sección, 28 aspectos) y **Estaciones de Policía / UT /
URI** (5 secciones, 25 aspectos). No son variantes del acta regular: son
formularios distintos, con otras secciones, otros aspectos y otra numeración.

Los PDF llegaron escaneados. El OCR de CamScanner los deja ilegibles
(`"IISTALACIONES l'lslc:AS"`, columnas mezcladas, páginas enteras vacías), así
que el catálogo se transcribió leyendo las páginas como imagen. Cargarlo desde
ese OCR habría metido errores en el texto que después es la fuente de las
reglas de asignación.

### Lo que ya estaba mal

`INFRAESTRUCTURA` existía como tipo de acta desde antes, pero implementado
como "marcar no evaluado todo lo que no sea instalaciones físicas" **del acta
regular**. Esa sección tiene 17 aspectos; la del acta de infraestructura tiene
28 y otra redacción. Quien registraba un acta de infraestructura estaba
calificando una lista que no era la suya.

### La trampa que había que resolver primero

Las reglas del maestro se guardaban con el numeral como clave: `"1.4"`. Con
tres actas, `1.4` significa cosas distintas en cada una. Cargar los catálogos
nuevos sin tocar eso habría hecho que el acta de policía heredara los
responsables de la regular, y el hallazgo se iría a quien no es sin que nada
lo advirtiera.

Ahora la clave lleva la familia del acta por delante: `REGULAR::1.4`,
`ESTACION_POLICIA::1.4`. **Las claves viejas siguen valiendo, pero solo para
la familia regular** — que era la única que existía cuando se guardaron. Por
eso no hubo que migrar nada.

REGULAR y SEGUIMIENTO comparten familia: evalúan el mismo catálogo y se
distinguen solo por el propósito de la visita. Separarlas obligaría a editar
cada numeral dos veces, y bastaría olvidar una para que el mismo hallazgo se
asignara distinto según el tipo de visita.

`Restaurar regla base` borra las dos formas de la clave. Con solo la nueva no
habría hecho nada sobre una regla guardada antes de este cambio: se borraba
una clave inexistente y la vieja seguía mandando.

### Lo que se corrigió de paso

El tablero **sugería** responsable con la matriz incluida en la aplicación,
mientras la asignación real leía la regla guardada. Podían discrepar: se veía
un nombre sugerido y el hallazgo se iba a otra persona. Ahora las dos leen lo
mismo.

### Matriz vacía, a propósito

Las actas nuevas no traen matriz de responsabilidad incluida. Se llena desde
el maestro. Un responsable equivocado por defecto no se nota; una regla sin
responsable queda marcada "sin asignar" y se ve.

---

## Sesión 2026-09-04 — Cuatro estorbos de uso diario

Cambios pedidos desde la operación. Ninguno cambia estructura de datos.

### Subsanaciones: filtro por asignado

Faltaba poder preguntar "¿qué tiene fulano?" y, sobre todo, "¿qué no tiene
nadie?". La opción **Sin asignar** es la que de verdad se usa: un hallazgo sin
responsable no le figura a nadie en su bandeja y solo aparece revisando la
lista entera.

Las opciones del desplegable se calculan sobre la lista **sin filtrar**. Si
salieran de la ya filtrada, elegir a una persona vaciaría el selector y no
habría forma de volver.

### Maestro: la tabla ya no obliga a desplazarse en horizontal

Las columnas de sección y descripción tenían ancho fijo (250 y 560). Sumadas
al resto, la tabla medía más que cualquier pantalla: para ver quién responde
por un numeral había que arrastrar en horizontal o alejar el zoom hasta que la
letra no se leía. Ahora se reparten el espacio disponible con `LayoutBuilder`.
El scroll horizontal se conserva como salida en pantallas angostas.

### Accesos del personal: filtro por cargo

Para dar o quitar un módulo a un grupo hay que encontrarlo primero. El buscador
ya miraba el cargo, pero exigía escribirlo bien y no ofrecía la lista.

Al hacerlo salió un problema de fondo: parte del padrón guarda en `cargo` el
**ID** del cargo, no su nombre. Esas personas mostraban un identificador crudo
y habrían quedado fuera del filtro. `loadPersonnel` ahora traduce el id contra
`TBL_CARGOS`. Es el mismo problema que tenía Interventoría al resolver
responsables por cargo.

### La lista ya no salta al principio

Al guardar los accesos de una persona se recargaba el padrón poniendo
`_cargando = true`. Eso reemplazaba la lista por el indicador y, al volver,
construía un `ListView` nuevo: la posición se perdía y la vista saltaba
arriba. Quien revisaba de a una persona tenía que buscar otra vez dónde iba.
La recarga posterior a guardar ya no vacía la pantalla.

---

## Sesión 2026-09-03 (ronda 2) — En iPhone no llegaba ninguna notificación

En Android llegaban y sonaban; en iPhone, nada. La función
`onNotificationCreated` terminaba en `ok` en todas las ejecuciones.

### Por qué "ok" no significaba entregado

`sendEachForMulticast` **no lanza** aunque fallen todos los tokens: informa el
resultado uno por uno en `resp.responses`. El código miraba esa respuesta solo
para limpiar tokens muertos, nunca para registrar el motivo de un fallo. Con
ocho entregas y dos fallos, la ejecución terminaba en `ok` y en los logs no
quedaba absolutamente nada.

Ahora se registran los fallos agrupados por código, con conteos pero **sin los
tokens**: un token identifica el dispositivo de una persona.

### El diagnóstico

Un script contra FCM con las credenciales del proyecto mostró lo que los logs
no decían:

```
...31U0Aywk  ios      FALLO  messaging/third-party-auth-error → Invalid APNs credential
...Vuy3ujos  ios      FALLO  messaging/third-party-auth-error → Invalid APNs credential
(8 tokens android/web)        ENTREGADO
```

El iPhone **sí** tenía token registrado. El problema estaba en la credencial
APNs del proyecto.

### Dos causas encadenadas, ninguna visible desde la app

**1. Los datos de la clave estaban inventados.** En Firebase → Cloud Messaging
figuraban dos claves con "ID de clave: `ToDo APPLE`" e "ID de equipo:
`ToDo App D`" — el nombre de la app escrito a mano en los campos de los IDs.
Firebase firma con la clave un JWT cuyo `iss` es el Team ID y cuyo `kid` es el
Key ID; con esos valores Apple rechaza la firma.

**2. Firebase pide la clave en DOS renglones.** "Clave de autenticación de APNS
de desarrollo" y "de producción". Subirla solo en desarrollo no basta: la app
instalada viene de App Store, FCM la trata como producción y consulta ese
renglón. Estaba vacío, y el error es el mismo `Invalid APNs credential`, sin
distinguirse en nada del caso anterior.

**El mismo `.p8` va en los dos renglones.** La clave se crea en el portal de
Apple con Environment `Sandbox & Production` — ese ajuste **no se puede cambiar
después de guardar** — y sirve para ambos.

### Lo que NO era

El entitlement. La configuración Release del *target* apuntaba a
`Runner.entitlements` (`development`) mientras la del *proyecto* apuntaba a
`RunnerProfile.entitlements` (`production`), y en Xcode el target pisa al
proyecto: los builds de App Store salían con `development`. Se corrigió, porque
Apple exige `production` para distribución, pero **no era la causa de esta
falla**. Se llegó a afirmar que sí; la evidencia lo desmintió.

### Cómo verificarlo sin recompilar

Los tokens ya están guardados en `TBL_USUARIOS`, así que se puede probar la
entrega contra FCM sin tocar la app. Códigos que importan:

| Código | Significa |
|---|---|
| `third-party-auth-error` | la clave APNs de Firebase está mal o falta en el renglón que se consulta |
| `registration-token-not-registered` | token muerto, o de sandbox contra APNs de producción |
| sin tokens del todo | el fallo está en el registro del dispositivo, no en el envío |

---

## Sesión 2026-09-03 — Interventoría: por qué "nadie salía por el cargo"

Reporte con capturas: el botón de asignación masiva había desaparecido del
tablero y, sobre todo, **ningún hallazgo sugería responsable**. Las dos cosas
tenían causas distintas.

### 1. El puente que faltaba: usuarios que guardan `cargoId`, no el nombre

`_perfilPorCargo` indexaba los cargos por nombre, y al recorrer el personal
comparaba contra el campo `cargo` del usuario. Pero una parte de
`TBL_USUARIOS` guarda ahí el **id** del cargo, no su nombre. Esos usuarios
entraban al `continue` y quedaban fuera del universo sin dejar rastro: no hay
error, no hay log, simplemente no aparecen. De ahí "nadie me sale por el
cargo".

Ahora `_perfilPorCargo` devuelve también `nombrePorId`, y antes de descartar a
un usuario se traduce el id a nombre. Las sugerencias pasaron de 0 a 598.

Es la misma familia de problema que [el área del usuario sale del cargo]: el
dato existe, pero en la forma que el lector no esperaba.

### 2. Un cargo sin gente en el establecimiento responde en pleno

El hallazgo pertenece a un establecimiento, así que la regla asigna a quien
tenga el cargo **en esa sede**. Antes, si nadie con ese cargo estaba asignado
al establecimiento, la función devolvía `null` y el hallazgo quedaba huérfano.

`resolverCargoTodos` devuelve ahora la persona de la sede si existe, y si no,
**todos** los que tengan el cargo. Es preferible que dos personas reciban un
hallazgo que no les toca a que no lo reciba nadie: lo primero se corrige en un
minuto, lo segundo se descubre cuando ya venció el plazo.

### 3. Varios cargos por regla, elegidos de `TBL_CARGOS`

El maestro pedía el cargo en un campo de texto libre. Un "Adminis" a medio
teclear produce una regla que no resuelve a nadie, y nada avisa. Los campos
son ahora **desplegables alimentados de `TBL_CARGOS`** y aceptan **más de un
cargo** por rol.

En responsable la lista es de **alternativas**, no de destinatarios: con
"Administrador tipo 1" y "Administrador tipo 2" en la misma regla, cada sede
queda cubierta por el que realmente exista allí, sin una regla por sede. En
aprobador la lista es de **permisos**: cualquiera de esos cargos puede aprobar
el cierre.

Las reglas se guardan en `responsables`/`aprobadores` **y** en el campo
singular con el primer elemento. Hay lectores que esperan el formato viejo, y
romperlos dejaría reglas sin aplicar sin ningún aviso.

### 4. La limpieza administrativa no veía los hallazgos sin asignar

El cierre de módulos contaba tareas y notificaciones, pero los hallazgos
**sin responsable** no generan tarea: no existían para el conteo, y el botón
"Aplicar" quedaba deshabilitado aunque hubiera cientos por cerrar.

`_hallazgosSinAsignar()` los busca consultando solo por `empresaId` y
filtrando fecha y estado en memoria — a propósito, para no exigir un índice
compuesto nuevo. Se cierran como `subsanado` con la marca
`cierreAdministrativoSinAsignar: true`, no se borran: el histórico de una
interventoría no se tira.

### Lo que queda pendiente

Asignar un hallazgo a **varias personas a la vez** todavía no se puede:
`crearTareaYNotificarHallazgo` borra la tarea anterior al crear la nueva, y el
cierre de módulos busca un `tareaId` en singular. El hallazgo tendría que
referenciar varias tareas. Hoy, cuando hay varios candidatos, el tablero los
muestra y la asignación toma al primero.

---

## Sesión 2026-08-27 — La barra de scroll horizontal no va en móvil

Reporte con capturas del teléfono: salía una barra gris **atravesada sobre el
contenido** — encima de las tarjetas de resumen de Requerimientos de personal,
encima del módulo "Administración" en Home y encima de las pestañas de
Nutrición.

Corrige el alcance de lo que hizo la sesión del 2026-08-25 (ronda 3), que
introdujo las barras de scroll. La barra horizontal es una ayuda de puntero:
avisa que hay más columnas y deja agarrar la fila con el mouse. Con el dedo no
informa nada, y como se dibuja dentro del área del scroll, en filas bajas queda
pintada sobre las tarjetas.

### Dos orígenes distintos

**1. `AppScrollBehavior`** forzaba `Scrollbar` en *todo* scroll horizontal, sin
mirar la plataforma. De ahí salían Home y Requerimientos, que son `ListView`
horizontales normales. Ahora en móvil delega en `super`, que para el eje
horizontal devuelve el hijo tal cual: ninguna barra.

**2. `internal_module_layout.dart`** tenía su propio `Scrollbar` con
`thumbVisibility` para la fila de pestañas — un widget explícito que el
`ScrollBehavior` no puede interceptar. Se envuelve condicionalmente. Las
flechas laterales `‹ ›` se conservan en ambas plataformas.

### La regla se decide por plataforma, no por `kIsWeb`

`usaBarraHorizontal(context)` mira `Theme.of(context).platform`. Eso resuelve
los dos casos de una sola vez: Flutter web en un escritorio reporta
windows/macOS/linux y lleva barra; en el navegador de un teléfono reporta
android/iOS y no la lleva, igual que la app nativa. Con `kIsWeb` la web móvil
habría seguido rota.

### Limpieza de paso

CLAUDE.md ya dice que no hay que envolver tablas en `Scrollbar` a mano, pero
quedaban 5 sitios que sí lo hacían (3 en `seed_admin_screen`, 2 en
`interventoria_dashboard_screen`). No forzaban `thumbVisibility`, así que solo
asomaban al deslizar, pero en móvil incumplían igual. Pasan a `BarraHorizontal`,
que en escritorio se comporta idéntico y en móvil desaparece.

Los dos `Scrollbar` de `rutas_dashboard_screen` **no se tocaron**: envuelven
scroll vertical, donde la barra sí corresponde.

### Verificación
`test/app_scroll_behavior_test.dart`, 7 casos: móvil sin barra, escritorio con
barra, el eje vertical intacto, y `BarraHorizontal` en ambos sentidos. Suite
completa en verde (296 tests).

### Archivos
- `lib/theme/app_scroll_behavior.dart` — `usaBarraHorizontal`, `BarraHorizontal`,
  gate en `buildScrollbar`
- `lib/widgets/internal_module_layout.dart` — `_conBarra`
- `lib/admin/seed_admin_screen.dart`, `lib/interventoria/interventoria_dashboard_screen.dart`
- `test/app_scroll_behavior_test.dart` (nuevo)

---
## Sesión 2026-08-27 — `BuildContext` después de un `await`: los 41 avisos que sí eran crashes

De los 222 avisos que dejó la limpieza de lint del commit `9c5d134`, estos 41
eran los únicos con riesgo real: `use_build_context_synchronously`. El resto es
cosmético (`withOpacity`, `use_null_aware_elements`, código muerto).

**Por qué importa.** Si la persona toca dos veces "Guardar", sale de la pantalla
mientras está guardando o cierra la app con una subida en vuelo, el `State` se
desmonta y el `context` que quedó capturado antes del `await` ya no apunta a
nada. `Navigator.push`, `ScaffoldMessenger.of` o `EmpresaScope.of` sobre ese
context lanzan excepción. Se ve como un crash intermitente imposible de
reproducir a pedido, que es exactamente lo que veníamos arrastrando.

`dart fix` no lo puede automatizar porque el arreglo depende de qué se hace con
el context, así que fue caso por caso. Nada se silenció con `// ignore:`.

### Los cuatro patrones que se aplicaron

1. **Solo para un SnackBar → capturar el messenger antes del `await`.** Es el
   patrón que ya usaba `_descargarActaPdf` en Interventoría. El aviso se muestra
   igual aunque la pantalla se haya ido, y nunca se toca un context muerto.
2. **Para `Navigator.push`/`pop` sobre el context del `State` → `if (!mounted) return;`**
   justo después del `await`.
3. **Para un context que no es el del `State`** (el `ctx` de un diálogo, el
   parámetro de `build`, el de un `StatefulBuilder`) → `context.mounted` /
   `ctx.mounted`. Aquí estaba el error más traicionero: había `if (!mounted)`
   que *parecían* proteger pero comprobaban el `State` mientras el `Navigator.pop`
   iba contra el context del diálogo. El analizador lo marca como
   "guarded by an unrelated 'mounted' check" y tiene razón: son dos ciclos de
   vida distintos.
4. **En funciones sueltas y servicios** (sin `State`, así que sin `mounted`) →
   `context.mounted` sobre el propio `BuildContext`.

### Qué se tocó

**`services/notification_service.dart` (9 avisos).** `_handleNotificationTapPayload`
es estático y saca el context del `navigatorKey`; no hay `mounted` que valga.
Se agregó `!context.mounted` al resolver el context (cubre las siete
navegaciones por tipo de notificación) y otra guarda antes de
`resolveNotificationRoute`, con el messenger capturado antes de ese `await`.
Es el peor caso de todos: toda la ruta de "tocar una notificación push" pasaba
por acá sin una sola comprobación.

**`home/home_screen.dart` (13 avisos).** Seis eran las tarjetas de módulo
(Administración, Talento Humano, Gerencia, Correspondencia, Planillas,
Nutrición), escritas como `onTap: () async => (await _guard(...)) ? Navigator.push(context, ...) : null`.
El `?:` no deja meter la guarda, así que pasaron a bloque con
`if (!permitido || !mounted) return;`. Los módulos nuevos (Compras, Correo,
Tokens DIAN, Interventoría, Facturación, Rutas) ya usaban helpers `_abrirX()`
con `context.mounted` — ahora las doce entradas se comportan igual. Los otros
siete estaban en `_openNotificationTask`: faltaban guardas después del guardián
de Facturación, antes de `resolveNotificationRoute` y —el más sutil— después
del `set({'visto': true})` en Firestore, que invalidaba el `if (!mounted)` de
más arriba y dejaba cuatro `Navigator.push` sin protección.

**`admin/admin_dashboard_screen.dart` (5 avisos).** Los cinco son el caso 3:
guardar usuario, accesos masivos, bodega, perfil de empresa y alta de app.
Todos tenían `if (!mounted) return;` seguido de `Navigator.pop(ctx)` /
`pop(dialogContext)` / `pop(ctx2)`. Ahora comprueban las dos cosas: el `State`
(porque después llaman `_snack` y `_loadAll`) y el context del diálogo.

**`compras/compras_dashboard_screen.dart` (2).** Subida web de documentos de
proveedor y de recepción: después de `subirBytes` se abre el diálogo de
vigencia con un context de `build`/`StatefulBuilder`.

**`core/task_route_guard.dart` (1).** `validateTaskAccess` lee
`EmpresaScope.of(context)` después de dos consultas a Firestore. No es un
`State`, así que devuelve una `TaskAccessValidation` no permitida con mensaje
propio; quien llama ya sabe manejar ese caso.

**`login/` (4).** `change_password_screen` tenía un `// ignore: use_build_context_synchronously`
tapando el `pushAndRemoveUntil` posterior al diálogo de confirmación: se quitó
el ignore y se puso la guarda de verdad, más otra antes del `setState` que
sigue al `signOut()`. Igual en `forgot_password_screen`. En `login_screen`,
`_selectEmpresaId` devuelve `null` si se desmontó, y la guarda del llamador se
subió *antes* del `if (selectedEmpresaId == null)` — porque ese bloque hace
`setState`, que sobre un `State` desmontado también revienta; no alcanzaba con
proteger el `EmpresaScope.of` de abajo.

**`home/create_task_screen.dart` (2, no contaban en los 41).** El archivo tenía
`// ignore_for_file: use_build_context_synchronously` en la cabecera, o sea que
sus avisos ni aparecían en el conteo. Se quitó y salieron dos: el
`showTimePicker` que va después del `showDatePicker` en `_pickDeadline`, y el
SnackBar de "no se pudo leer la información del asignado" después de releer al
asignado. Los dos arreglados.

**El resto (5).** `home/notifications_screen.dart` (función suelta que devuelve
`bool`), `helpers/nutricion_dashboard_helper.dart` (el aviso de "reporte
descargado" después de escribir el archivo),
`talento_humano/areas_management_screen.dart` (`ctx2` del diálogo de área),
`talento_humano/organizational_structure_screen.dart` (2, el context de
`build` en Sincronizar jerarquía) y `widgets/hidden_admin_unlocker.dart`
(messenger capturado antes del diálogo del PIN y de leer `TBL_CONFIG`).

### Verificación
- `dart analyze`: **222 → 181 avisos**, exactamente −41. `use_build_context_synchronously`
  queda en **0**, y no se introdujo ningún aviso nuevo (la diferencia total es
  solo esos 41). **0 errores.**
- Los 32 `warning` que quedan son previos a esta sesión y de otra naturaleza
  (`unused_element`, `unused_field`, `undefined_hidden_name`); no se tocaron.
- `flutter test`: **289/289**, el mismo conteo que antes del cambio.
- No hay ningún `// ignore:` ni `// ignore_for_file:` de esta regla en `lib/`.

---

## Sesión 2026-08-26 (ronda 2) — Publicación en Google Play y recuperación del árbol

### Lo que se preparó para publicar
- **R8 abortaba el release.** `google_mlkit_text_recognition` referencia los
  reconocedores de chino, devanagari, japonés y coreano, cuyos artefactos no se
  incluyen (la app solo escanea texto latino). Se creó
  `android/app/proguard-rules.pro` con los `-dontwarn` y se activó
  `proguardFiles` en el `buildType` de release, que estaba comentado: Flutter
  activa R8 por defecto, así que sin declararlo las reglas nunca se aplicaban.
- **Validación de `key.properties`.** `hasReleaseKeystore` solo comprobaba que
  el archivo existiera, así que uno a medio llenar hacía fallar la firma con un
  error incomprensible. Ahora exige las cuatro claves y que el `.jks` exista.
- **Permisos que entraban solos.** El manifiesto fusionado del AAB traía
  `AD_ID`, `ACCESS_ADSERVICES_AD_ID`, `ACCESS_ADSERVICES_ATTRIBUTION`,
  `READ_MEDIA_IMAGES`, `READ_MEDIA_VIDEO` y `READ_MEDIA_AUDIO` sin que nadie
  los declarara. Los inyectan la cadena de medición de `firebase_messaging` y
  `file_picker`. Se eliminan con `tools:node="remove"`: la app no tiene
  publicidad, no maneja video ni audio, y las fotos pasan por `image_picker`,
  que en Android 13+ usa el selector del sistema sin pedir permiso. Los dos
  `FileType.image` que quedan están dentro de ramas `if (kIsWeb)`.
  `READ_EXTERNAL_STORAGE` **sí** se conserva: hace falta en Android 12 y
  anteriores. Verificado leyendo el manifiesto proto dentro del AAB, no el
  fuente: el fuente nunca los mostró.
- **Seed demo ampliado.** Pasó de 3 a 8 tareas cubriendo los cuatro estados
  (`en_progreso`, `por_aprobar`, `devuelta`, `finalizado`) y las tres
  prioridades, más hojas de vida ficticias para los tres usuarios demo. Sin
  esto, Talento Humano y los listados salían vacíos en las capturas de la ficha.

### El árbol se revirtió y hubo que recuperarlo
Una herramienta de cambio de rama dejó el working tree en HEAD y guardó todo en
un stash (`epitaxy: pre-switch`). Se perdieron de vista ~3.274 líneas sin
commitear. El stash se había creado con `--include-untracked`, así que también
traía `proguard-rules.pro`, `MainActivity.kt` y `play-assets/`.

`git stash apply` dejó **11 conflictos en 6 archivos**, porque el stash se basa
en `59a5da0` y la rama ya tenía tres commits encima. Los conflictos cortaban por
la mitad de árboles de widgets anidados, así que no se resolvieron eligiendo
lados sino decidiendo **por archivo** y portando funciones:

| Archivo | Decisión |
|---|---|
| `interventoria_tablero_asignacion.dart` | versión del stash + se le devolvió la paginación |
| `interventoria_hallazgo_panel.dart` | versión del stash (lo único propio era un `setState`) |
| `interventoria_dashboard_screen.dart` | versión del commit + se portó `_descargarActaPdf` |
| `personnel_requisition_screen.dart` | versión del commit + se portaron los candidatos |
| `gd_correspondencia_screen.dart` | versión del commit, sin tocar |
| `MEJORAS.md` | versión del commit + esta sección |

**`gd_correspondencia_screen.dart` se dejó como estaba a propósito**: la versión
del stash filtraba con `user.areaId == selectedArea!.id` y caía a mostrar el
`areaId` crudo como nombre. Las dos cosas que la regla 3 de CLAUDE.md prohíbe.
La versión commiteada ya usa `contiene()` y `GdArea.desdeResponsables()`.

Resultado: `dart analyze` con 0 errores y 0 warnings, y los mismos 966 `info`
preexistentes de antes del merge.

### Estado del bundle
`build/app/outputs/bundle/release/app-release.aab`, 103,6 MB, `versionCode 2`
(el 1 ya se consumió en la primera subida a prueba cerrada). Firmado con
`CN=Daniel Felipe Nova Velasco` desde `C:/Desarrollo/keys/todogestion-release.jks`.

Queda pendiente el `strip` de símbolos del NDK, que falla porque el SDK de
Android está en una ruta con espacios (`C:\Users\SERVICIO TECNICO\...`). El AAB
se genera igual; solo pesa más de lo necesario.

---


## Sesión 2026-08-26 — Clave temporal al agregar personal y empresa elegida en el login

### 1. "Agregar colaborador" no dejaba entrar a la persona

El alta desde Talento Humano › Gestión de personal creaba el usuario **sin
contraseña**, a propósito ("el acceso lo habilita Admin al asignarla"). Las
otras dos vías sí la asignan: la contratación desde Requerimientos y la carga
por Excel ponen `123456` + `needsPasswordChange`. Resultado: la persona quedaba
registrada pero sin poder ingresar, y sin ninguna señal de por qué.

- El alta ahora usa `personnelAccessCredentials`, igual que la contratación:
  usuario = cédula, contraseña temporal `123456`, obligada a cambiarla al
  entrar. Al guardar se muestra un aviso con esos datos para poder dictárselos.
- A las cuentas ya creadas por esa vía (registradas y sin clave) se les asigna
  la temporal al editarlas, así se recuperan sin migración.

**Corregido de paso un riesgo que ya existía en la contratación:**
`personnelAccessCredentials` miraba solo el campo `password`. Pero el backend
**borra** ese campo en el primer ingreso, cuando migra la clave cifrada a
`TBL_AUTH_CREDENTIALS` y marca `authVersion: 2`. Así que a alguien que ya
usaba la app y era recontratado se le volvía a poner `123456` y se le exigía
cambiar una clave que ya tenía. Ahora `personnelNeedsTemporaryPassword` mira
`authVersion` y no toca a quien ya ingresó alguna vez.

### 2. Elegir empresa en el login no cambiaba de empresa

Al iniciar sesión con varias empresas, la elegida se pasaba a
`reconcileForUserData` como `preferredEmpresaId`. Pero `resolveValidEmpresaId`
da prioridad a `selectedEmpresaId` —la empresa que quedó guardada de la sesión
anterior— y solo cae en la preferida si aquella ya no es válida. Como la
anterior casi siempre sigue siendo válida, **la elección del usuario se
descartaba** y entraba a la empresa donde estaba antes.

- `reconcileForUserData` recibe `eleccionExplicita`. Con eso la empresa
  elegida manda; sin eso (reanudar sesión guardada) se conserva el
  comportamiento de antes, que ahí sí es el correcto.
- El login la pasa en true: elegir empresa es una decisión explícita, no una
  sugerencia.

---

## Sesión 2026-08-25 (ronda 3) — Área editable en Salud de cargos, paginación de 20 y barras de scroll

### 1. "Salud de cargos" ya deja arreglar el cargo ahí mismo

Los cargos "Sin área" (sin `areaId` **ni** nombre de área) no tienen nada que
deducir, así que el panel solo decía "revisa el nombre del área o créala en
Catálogos" y el camino se cortaba ahí.

- Nuevo botón **"Elegir área…"** en cada cargo con problema de área: abre el
  desplegable con las áreas de la empresa y escribe `areaId`, `areaNombre` y
  `area` en TBL_CARGOS. Después vuelve a escanear solo.
- El escaneo ahora guarda el catálogo de áreas (pasado por `areasUnicas`, así
  que sin repetidas ni ids crudos) para alimentar ese selector.
- El texto rojo de "no reparable automáticamente" se reemplazó por una
  indicación útil: elígela arriba, o créala en Catálogos si no existe.

### 2. Listados largos: de a 20

Nuevo `lib/widgets/paged_list.dart` con la regla en un solo lugar:
`kPageSize = 20`, `pageOf()`, `pageCountOf()`, `PagerBar` ("1-20 de 137" con
anterior/siguiente) y `PagedListSection` para listas que ya viven dentro de una
columna con scroll.

Aplicado en: Salud de cargos, Salud usuarios, tablero de asignación de
Interventoría (por grupo), tabla de hallazgos de Interventoría, tabla de
vigencias de Compras y Accesos del personal (Talento Humano). El panel de
Seguridad ya paginaba de a 20 por su cuenta y quedó igual.

**Convertidas todas las tablas de la app (19 en total)** con
`PagedDataTable`, un envoltorio que recibe la `DataTable` ya construida,
guarda la página por dentro y la vuelve a emitir con las 20 filas que tocan:
Admin (5), seed de Admin (3), Rutas (3), Interventoría (2), Gerencia,
Correspondencia, Planillas desde Excel, Movilidad, Requerimientos de personal
y Tokens DIAN. En el sitio de uso solo se envuelve la tabla, así que sirve
igual dentro de un `StatelessWidget`.

La regla quedó escrita en `CLAUDE.md` (Reglas transversales de interfaz) para
que aplique a cualquier pantalla nueva.

### 3. Barra de scroll en las tablas deslizables (global)

`MaterialScrollBehavior` **nunca** dibuja scrollbar horizontal, así que las
tablas anchas se deslizaban sin ninguna pista de que había más columnas.

- Nuevo `lib/theme/app_scroll_behavior.dart` + `scrollBehavior` en el
  `MaterialApp`: barra visible en todo scroll horizontal de la app.
- Además el mouse queda habilitado como dispositivo de arrastre, así que en web
  se puede "agarrar" la tabla y moverla, no solo usar la rueda o la barra.
- El eje vertical conserva el comportamiento de la plataforma (barra en
  escritorio/web, indicación efímera en móvil) para no llenar de barras fijas
  cada lista del teléfono.
- `thumbVisibility` se fuerza solo cuando el scrollable trae su propio
  controlador: con uno compartido Flutter exige una única posición adjunta y
  lanza una aserción.

---

## Sesión 2026-08-25 (ronda 2) — Sesión guardada, áreas repetidas y quién aprobó en Compras

Seis puntos que reportó Daniel probando en vivo.

### 1. "Mantener sesión iniciada" no aguantaba (y se apagaba sola)

`AuthGate._resume()` preguntaba por `FirebaseAuth.instance.currentUser` apenas
arrancaba la app. Firebase Auth **restaura la sesión persistida de forma
asíncrona** (en web, leyendo IndexedDB), así que en ese instante todavía es
null. El código lo interpretaba como sesión inválida, llamaba a
`clearSession()` —que además pone `keepSession = false`— y mandaba al login.
Resultado: la casilla aparecía apagada al volver a entrar.

- Nuevo `_esperarUsuarioAuth()`: usa el `currentUser` si ya está y, si no,
  espera el primer `authStateChanges()` no nulo con tope de 8 segundos.
- Si aun así no hay usuario, **ya no se borra la sesión guardada**: puede ser
  falta de red. Se va al login y el próximo arranque reintenta.
- `_goLogin(cerrarSesionFirebase: false)` para los caminos transitorios: cerrar
  sesión en Firebase ahí destruía una sesión válida.

Solo se limpia la sesión cuando la invalidez es concluyente: claims que no
corresponden, usuario inexistente, usuario inactivo o sin empresa válida.

### 2 y 3. Áreas repetidas y áreas mostrando su id crudo

Dos síntomas, dos causas, un archivo nuevo: `lib/core/area_directory.dart`.

**"EMPRESA_002_mantenimiento" como nombre.** Los documentos de `TBL_AREAS` se
crean con id `{empresaId}_{slug(nombre)}`. Media app resolvía el nombre con
`?? d.id`, así que un documento **sin campo `nombre`** terminaba mostrando su
id en el desplegable. `areaNombreLegible()` reconstruye "Mantenimiento" a
partir del id (quita el prefijo de empresa y capitaliza), y ninguna pantalla
vuelve a mostrar un id crudo.

**"Mantenimiento" dos veces y "Operaciones" tres.** El desplegable de
Correspondencia arma las áreas a partir de los USUARIOS y deduplicaba por
`areaId`. Pero el área de un usuario a veces es el id del catálogo y otras el
nombre suelto —`listarResponsables` hace `areaId.isEmpty ? areaNombre :
areaId`—, así que la misma área entraba dos y tres veces. Peor: al elegir una
de ellas, el filtro de responsables (`user.areaId == area.id`) dejaba fuera a
la gente registrada con la otra variante.

- `areasUnicas()` agrupa por nombre normalizado (sin tildes ni signos) y cada
  opción conserva **todos** los ids equivalentes.
- `GdArea` ahora lleva ese conjunto y expone `contiene(areaId)`; el diálogo
  "Clasificar y asignar" y el panel de colaboración filtran con eso, así que
  una sola entrada por área muestra a todo su personal.
- `AreaCatalogo` (mismo archivo) da el mapa para los desplegables y decide si
  un registro cae en el filtro, sin romper el filtrado existente.

Aplicado en: Correspondencia (diálogo y panel), Tareas asignadas, Historial de
tareas, Tareas creadas, Vista de equipo, Crear tarea, Gerencia y
`OrgService.listAreas` (de donde salen los desplegables de Interventoría).

> Nota de datos: esto arregla lo que se **ve**. El origen sigue ahí: hay
> documentos en `TBL_AREAS` sin `nombre` y usuarios con `areaId` guardado como
> nombre. Conviene una revisión tipo "Salud de cargos" para repararlos.

### 4. "Crear tarea" tardaba en habilitar el desplegable de Área

No era el catálogo: era la cadena de viajes de red.

- `_queryByEmpresa` lanzaba **cuatro consultas en serie** por catálogo (una por
  cada forma de declarar la empresa: `empresas`, `empresaId`, `empresa_id`,
  `empresa`). Ahora salen en paralelo y cuesta lo que la más lenta. Igual en
  `_loadEstructura` y `_loadCargos`.
- El desplegable esperaba a `_loadingData`, que solo se apaga **después** de
  cargar el padrón completo de usuarios de la empresa. Se separó
  `_loadingCatalogos`: Área y Cargo se habilitan apenas están áreas y cargos,
  sin esperar a los usuarios.

### 5. Compras: quién aprobó, con historial

El documento solo guardaba al **último** revisor (`revisadoPor` +
`fechaRevision`): aprobar → revertir → aprobar borraba la pista anterior.

- Nueva colección `TBL_COMPRAS_APROBACIONES`: un registro por decisión de
  calidad (aprobó, aprobó con requerimientos, rechazó, revirtió, dio por
  resuelto) con usuario, fecha, documento, producto y nota.
- Se escribe desde `ComprasService` en recepciones, fichas técnicas,
  proveedores y marcas. Es auditoría: si la escritura falla, la aprobación
  igual queda hecha (solo se pierde la línea del historial).
- `lib/compras/compras_aprobaciones.dart`: `AprobadoPorLinea` ("Aprobado por
  {nombre} · fecha", con nombre y foto reales) y `HistorialAprobacionesBoton`,
  que abre el historial completo — diálogo en web, hoja en móvil.
- Ya visible en la tarjeta de calidad de ficha técnica y en el documento
  aprobado de una recepción. La línea "Aprobado por" funciona también con lo
  aprobado antes de existir el historial, porque lee lo que ya trae el
  documento.
- La consulta filtra por un solo campo (`entidadId`) y ordena en memoria: no
  hace falta índice compuesto nuevo.

### 6. Módulos en móvil

La tira horizontal de módulos tenía altura fija de 120 px, mientras la tarjeta
crece con la escala de letra del sistema (título a dos líneas). Con la letra
en grande se recortaba. Ahora la altura acompaña `textScaler` y la separación
entre tarjetas pasó de 4 a 8 px.

---

## Sesión 2026-08-25 — Apagar "Tareas" de verdad + accesos de módulos desde Talento Humano

Daniel: "en admin permisos y roles desactivo tareas y no las esconde"; y en
Talento Humano, poder decidir al crear/contratar a alguien qué módulos va a
usar, "menos técnico"; además "todos deben tener habilitado notificaciones y
calendario".

### 1. Desactivar Tareas ocultaba el menú, pero no el Home

`home_screen.dart` sí calculaba `showTareas` con `_moduleVisible(...,
'tareasdashboard', ...)`, pero solo se lo pasaba a `HomeShell` → `AppDrawer`.
El **cuerpo** del Home nunca miró esa bandera: el botón "Nueva Tarea" (Web),
la sección "Pendientes" con su "Ver todos" (Móvil) y las dos consultas a
`TBL_TAREAS` seguían ahí para todo el mundo. Quitar el módulo dejaba el menú
limpio y la pantalla principal igual que antes.

- `showTareas` se calcula ahora **antes** de las consultas, apenas se resuelve
  `disabledAppIds`. Con el módulo apagado los dos `.snapshots()` de
  `TBL_TAREAS` se reemplazan por streams vacíos (campos de estado, no
  `Stream.empty()` en línea, para no re-suscribir en cada build): no se leen
  tareas, no se pintan marcadores de tareas en el calendario y no hay lecturas
  de Firestore por un módulo que la persona no tiene.
- Web: "Nueva Tarea" solo aparece con el módulo activo. Móvil: "Ver todos"
  (bandeja de tareas) idem.
- **Notificaciones y calendario no dependen del módulo.** La campana y la
  tarjeta del calendario siguen igual para todo el personal; la tarjeta del
  día conserva citas de Nutrición y notificaciones y solo pierde las tareas.
  Con Tareas apagado el título deja de decir "Pendientes" y pasa a "Agenda
  del día" / "Agenda del dd/MM", que es lo que realmente queda ahí.

Nota: un usuario **desarrollador** ve todos los módulos por diseño
(`_moduleVisible` hace bypass con `isDev`), así que apagar Tareas no le cambia
nada a esa cuenta — hay que probarlo con una cuenta normal.

### 2. Talento Humano ya decide qué módulos usa cada persona

Antes esto solo existía en Admin → "Roles y permisos", una matriz por appId
pensada para quien conoce la plataforma. Ahora vive también donde Talento
Humano trabaja, en su propio lenguaje:

- **`lib/core/app_catalog.dart` (nuevo)** — catálogo único de módulos con
  nombre y "para qué le sirve" en lenguaje de negocio, agrupados (Día a día /
  Áreas operativas / Gestión y control / Administración). Marca `soloAdmin`
  (Administración y Tokens DIAN: Talento Humano no los otorga) y la nota de
  rol interno cuando Admin debe completar la configuración. Aquí también se
  declaran Notificaciones y Calendario como **servicios transversales**: no
  son módulos, no se asignan y no se pueden quitar.
- **`personnel_access_service.dart` (nuevo)** — misma fuente de verdad que
  Admin (`TBL_USUARIOS`: `empresasDetalle.{empresa}.apps` + `apps` global),
  filtrando por lo que la empresa tenga apagado en `TBL_APPS`.
- **`personnel_access_picker.dart` (nuevo)** — selector reutilizable con
  descripciones, sin appIds a la vista, encabezado fijo "Todo el personal
  recibe esto: Notificaciones y Calendario".
- **`personnel_access_screen.dart` (nuevo)** — "Accesos del personal":
  buscador, filtro por módulo, solo activos, y por persona los módulos que
  usa. Nueva tarjeta en el tablero de Talento Humano (sección Personas).
- **Alta/edición de personal** (`organizational_structure_screen.dart`): el
  formulario "Agregar/Editar colaborador" trae la sección "Qué va a usar en la
  app", abierta por defecto en los nuevos. Se guarda después del batch porque
  `saveApps` necesita leer el documento ya creado.
- **Contrataciones** (`personnel_requisition_*`): el diálogo "Registrar
  contratación y crear usuario" incluye el mismo selector; `PersonnelHire`
  lleva ahora `apps` y `registerHireAndCreateUser` los escribe dentro de la
  transacción. Contratar **solo suma**: a alguien que ya existía no se le
  quita nada; quitar se hace en Accesos del personal.
- La carga masiva por Excel ya traía columna `apps` y no se tocó.

Talento Humano concede el **acceso** al módulo; el **rol interno**
(comprador, firmante, clasificador, conductor…) lo sigue definiendo Admin, y
así se dice en pantalla.

### 3. Dos arreglos de datos que hacían falta para lo anterior

- **`apps` global pisaba a las otras empresas.** Como `extractUserApps` une la
  lista global con la de la empresa, escribir `apps` (lo que hace la matriz de
  Admin desde siempre) le podía quitar módulos a la misma persona en otra
  empresa que los heredaba de esa lista global. Antes de escribir, ahora se
  **congela** en cada otra empresa su lista efectiva actual
  (`empresasDetalle.{otra}.apps`), y solo entonces se pisa la global. Es
  idempotente: si la empresa ya tenía su propia lista, no se toca.
- **`kAppIdNormalizationMap`** no tenía `tareas` → `tareasdashboard`. La
  equivalencia ya funcionaba (`_canonicalAppId` recorta el sufijo), pero las
  normalizaciones escribían `tareas` como si fuera canónico.
- `loadUsersByEmpresa` pasó de `AdminRepository` a
  `FirestoreUserRepository` (Admin delega): Talento Humano y Admin tienen que
  ver exactamente el mismo padrón por empresa.

---

## Sesión 2026-08-27 — Compras: Abastecimiento y reversión de fichas técnicas

### Abastecimiento conectado con el consolidado Excel
- Nuevo apartado **Compras › Abastecimiento**, con experiencia diferenciada:
  tabla y detalle persistente en Web; tarjetas y acciones rápidas en Móvil.
- Importación idempotente del consolidado XLSX: detecta las hojas operativas,
  presenta vista previa, evita duplicados y registra cada diferencia en el
  historial como cambio originado en Excel.
- Estados operativos: programado, confirmado, en camino, recibido, no entrega,
  reprogramado y cancelado. Los registros de no entrega se muestran tachados.
- Las observaciones `PND`, `PND PAGO`, `PENDIENTE POR PAGO`, `PND ENTRADA` y
  equivalentes se clasifican como pendientes operativos y se muestran en el
  tablero y en el calendario de Home de Bodega.
- La observación del consolidado queda separada del motivo del cambio de estado,
  por lo que marcar recibido/no entrega no borra novedades de pago o entrada.
- Cada fila exige OC/OS, proveedor activo y una categoría asociada al proveedor.
  Los proveedores desconocidos quedan fuera y se listan como pendientes de
  creación. La creación manual usa selectores de proveedor y categoría reales.
- Cuando ya existe una recepción con la misma OC, el abastecimiento conserva el
  vínculo con `TBL_COMPRAS_RECEPCIONES`.

### Reversión de fichas técnicas
- En documentos aprobados, Admin Documental puede regresar una ficha técnica a
  revisión o revertirla como rechazada, siempre con motivo y trazabilidad.
- La copia aprobada deja de ser utilizable en nuevas recepciones mientras la
  ficha vuelve a revisión.

### Verificación y publicación
- `flutter test test/compras`: **77/77**.
- Analizador de los componentes nuevos de Abastecimiento: sin hallazgos.
- El consolidado real se procesó correctamente: 6 hojas operativas, 76 filas
  estructuradas y 22 filas incompletas reportadas para corrección.
- `flutter build web --release --no-tree-shake-icons --no-wasm-dry-run`: correcto.
- `firebase deploy --only hosting`: desplegado en
  <https://to-do-gestion.web.app> y verificado con HTTP 200 sobre el bundle.

### Ajuste posterior: filtros, eliminación y catálogos
- Los cinco KPI del tablero ahora son accionables. En particular, **No
  entregan** aplica directamente el estado `no_entrega`; Atrasadas, Hoy,
  Pendientes y Recibidas también filtran su conjunto correspondiente.
- Web incorpora filtros visibles por estado, proveedor, producto, grupo y
  fecha. Móvil conserva estado/fecha en primer nivel y reúne proveedor,
  producto y grupo en una hoja compacta de filtros.
- Compras/Admin puede eliminar una entrega indicando motivo. La eliminación es
  lógica y auditable: se retira del tablero y calendario, pero conserva quién,
  cuándo y por qué la eliminó.
- La creación manual dejó de aceptar texto libre para producto y grupo: ambos
  se seleccionan de `TBL_COMPRAS_PRODUCTOS` y `TBL_COMPRAS_GRUPOS`; los
  productos se filtran por la categoría elegida del proveedor.
- La importación también enlaza `productoId` y `grupoId`. Productos o grupos no
  encontrados quedan fuera y se muestran como pendientes de catálogo.

### Coordinación Abastecimiento ↔ Recepción
- Desde una entrega programada se abre la **Recepción completa** con proveedor,
  OC, grupo, producto y destino precargados; se mantienen las validaciones de
  marca, ficha técnica, lotes y documentos.
- Guardar una recepción enlaza ambos registros en una sola operación, marca la
  programación como recibida y deja el cambio en el historial con origen
  `recepcion`.
- Las recepciones creadas directamente también buscan su programación por
  empresa, OC, proveedor, grupo y producto, evitando cruces por una OC similar.
- El botón **Sincronizar con Recepción** repara vínculos históricos y actualiza
  ambos documentos. Las importaciones de Excel reconocen recepciones existentes
  con los mismos criterios.
- Si se elimina una recepción, la entrega vinculada se reabre en su estado
  anterior y conserva la trazabilidad de la reversión.
- Verificación funcional de Compras actualizada: **80/80 pruebas aprobadas**.
- Compilación web de producción correcta y publicación verificada con HTTP 200
  en `to-do-gestion.web.app` y `to-do-gestion.com`.

### Destino de la entrega
- La creación manual de Abastecimiento usa el catálogo de bodegas de la empresa
  activa, igual que Recepción, en lugar de un campo libre permanente.
- El desplegable siempre incluye **Otro destino…**; al seleccionarlo aparece un
  campo obligatorio para escribir la ciudad, bodega o establecimiento.

### Semáforo de estados
- Los estados ahora se presentan como **Cancelado** en rojo, **Entregado** en
  verde y **En entrega** en naranja, de forma consistente en Web y Móvil.

### Estado de artefactos móviles
- Existe un AAB anterior de compilación 4 (`com.todogestion.app`), firmado con
  el certificado de carga de To-Do. No contiene esta sesión de Abastecimiento.
- No hay artefacto iOS en este equipo Windows; App Store requiere compilar y
  firmar desde macOS/Xcode.
- Antes del próximo AAB debe consolidarse en el repositorio la configuración de
  Android para producción: el archivo actual aún declara `com.example.todo` y
  firma `release` con la configuración debug, aunque el `key.properties` y el
  almacén de claves de carga sí existen localmente.

---

## Sesión 2026-08-10 — Renombre de módulo + tarea de cierre saltaba la aprobación

Dos pedidos de Daniel en pruebas en vivo sobre el trabajo de esta misma sesión.

### 1. El módulo pasó a llamarse "Gestión de Correspondencia"
Antes el módulo (`gestiondocumentaldashboard`) conservaba el nombre "Gestión
Documental" mientras que la sección se llamaba "Gestión de Correspondencia" —
decisión deliberada de la sesión anterior ("el módulo contiene la sección, no
al revés"). Daniel pidió ir más allá y renombrar el módulo completo.

El módulo en realidad tiene dos partes con identidad propia:
- **Correspondencia** — la vista por defecto al abrir el módulo (radicar,
  clasificar, responder). Es el 90% de lo que se usa.
- **Biblioteca documental** — vista secundaria (subir/eliminar PDF), con su
  propio sistema de roles (`rolDocumental`: redactor/revisor/aprobador/
  firmante/admin_doc), **sin relación** con el rol Clasificador y asignador de
  Correspondencia.

Por eso el rename fue selectivo:
- Nombre del módulo (tarjeta del Home, título de la app, listas de módulos
  asignables en Admin, referencias cruzadas desde Correo) → **Gestión de
  Correspondencia**.
- La vista de Biblioteca y su rol interno se renombraron a **"Biblioteca
  documental"** en vez de heredar el nombre nuevo del módulo — decían
  "Gestión Documental" y ahora habrían quedado huérfanos de significado, y
  ese rol nunca tuvo nada que ver con clasificar correspondencia.

**Efecto colateral que valió la pena corregir de una vez:** la pestaña "Roles
y permisos" de Admin (la matriz central de accesos) todavía traía la fila
"Gestión doc." con el dropdown de roles de Biblioteca — alguien que buscara
ahí "Clasificador y asignador" no lo iba a encontrar y la pestaña se sentía
como un callejón sin salida. Se le agregó un aviso fijo arriba
("Correo y Correspondencia se administran aparte") con botón directo a
**Roles de Correspondencia**, y la fila se renombró a "Biblioteca doc." para
que quede claro qué rol es ese.

Archivos: `home_screen.dart`, `gd_dashboard_screen.dart`,
`gd_control_dashboard_screen.dart`, `correo_dashboard_screen.dart`,
`notifications_screen.dart`, `admin_dashboard_screen.dart`
(`_correoRoleCallout`, nuevo), `personnel_template_service.dart`,
`demo_seed_service.dart`, `functions/src/correo.ts` (dos descripciones de
tarea generadas automáticamente).

### 2. "Terminar proceso" saltaba la aprobación de la tarea
Daniel lo señaló probando en el módulo de Tareas: al terminar un proceso de
Correspondencia, la tarea vinculada aparecía directo como **Finalizado**, en
vez de **Por aprobar** como pasa en el resto de la app (Compras, Facturación,
Interventoría, y el flujo genérico de "Completar tarea").

Causa: `gdTerminarExpediente` escribía `estado: "finalizado"` en la tarea
directamente. El resto de la app usa un flujo de dos pasos — quien termina
"solicita finalización" (`por_aprobar`, `solicitud_finalizacion_estado:
pendiente`) y quien está en `aprobador_uid` la confirma desde **Tareas › Por
aprobar** (`_approveFinish` en `created_tasks_screen.dart`, ya existente, sin
tocar). `gdTerminarExpediente` nunca entraba a ese circuito.

Corrección: el expediente sigue pasando a **Terminado** de inmediato (eso no
cambió, es la palabra del responsable sobre el proceso). La tarea vinculada
ahora sí entra en solicitud de finalización, con los mismos campos que usa
`complete_task_screen.dart` (`solicitud_finalizacion_at/by_uid/by_nombre`),
así que la aprueba quien ya estaba configurado como `aprobador_uid` — el
revisor si lo hay, o quien clasificó. El diálogo de confirmación en pantalla
se actualizó para decir esto en vez de "la tarea se cerrará".

Archivo: `functions/src/correo.ts` (`gdTerminarExpediente`),
`gd_correspondencia_screen.dart` (texto del diálogo).

### Verificación
- `cd functions && npm run build && npm test`: **23/23**, sin cambios en el
  conteo porque el flujo transaccional de `gdTerminarExpediente` no tiene
  arnés de emulador en este repo (se probó por lectura de código contra el
  contrato exacto de `complete_task_screen.dart`/`_approveFinish`, que sí está
  probado en producción por el resto de módulos que ya lo usan).
- `flutter analyze` sobre los archivos tocados: sin hallazgos nuevos.
- `flutter build web --no-tree-shake-icons --no-wasm-dry-run`: compila.

### Desplegado a producción
A pedido explícito de Daniel, con verificación de build y tests ya en verde:
- `firebase deploy --only functions` — **Deploy complete**. Incluye
  `gdAsignarExpediente`, `correoCrearExpediente` (rol clasificador) y
  `gdTerminarExpediente` (aprobación de tarea) de esta sesión, más el resto
  del backend sin cambios de lógica.
- `firebase deploy --only hosting` — **Deploy complete**.
  `https://to-do-gestion.web.app`.

---

## Sesión 2026-08-10 — Correspondencia: rol clasificador y asignador

Bloques C y F de la reunión del 07-ago 08:01. En el acta son dos entradas
distintas ("Restringir permisos de usuario" y "Ajustar asignación de casos"),
pero en la transcripción son el mismo tema — quedó dicho literalmente: *"Roles y
permisos. F."* — así que se resolvieron juntos.

### El problema
`operador` mezclaba dos cosas muy distintas: **trabajar lo que a uno le
asignan** y **decidir qué es cada documento y a quién se le asigna**. Todos los
callables de clasificación pedían `["operador"]`, así que cualquiera que entrara
al módulo clasificaba y asignaba. Textual de Oscar sobre una usuaria del
tablero: *"ella puede ver todo esto porque ella entró al tablero, pero no puede
hacer nada, ni clasificar, ni asignar, ni procesar"*.

Peor: **no existía ninguna interfaz para `TBL_CORREO_ROLES`**. La colección la
leía el backend desde el primer día, pero solo se podía escribir a mano en la
consola de Firestore. En la práctica nadie tenía rol y todos eran operadores.

### El rol nuevo
Se insertó `clasificador` entre `operador` y `administrador`:

| Rol | Nivel | Puede |
|---|---|---|
| `visor` | 1 | Consultar el tablero y el histórico. |
| `operador` | 2 | Trabajar lo que le asignan. **Por defecto.** |
| `clasificador` | 3 | Clasificar, asignar, radicar, fijar fecha límite. |
| `administrador` | 4 | Además tipos documentales, filtros y cerrar cualquier expediente. |

Es jerárquico, que es exactamente lo que se acordó en la reunión: *"sería
usuario clasificador y asignador que incluya las funciones de un usuario"*. Un
clasificador no pierde nada de lo que podía como operador.

Decisiones que conviene tener escritas:
- **El rol por defecto es `operador`, no `visor`.** El cambio quita el permiso
  de clasificar, no el acceso al módulo: quien solo responde lo suyo sigue
  trabajando igual sin que haya que asignarle nada.
- **Un texto desconocido en el campo `rol` no concede permisos.** Si alguien
  escribe "jurídica", `normalizeRole` devuelve `null` y cae al defecto. Un rol no
  puede salir de un error de digitación.
- **El rol global solo sirve para reconocer al administrador** que configura el
  módulo por primera vez. Un "usuario" global no se vuelve clasificador por esa
  vía; eso se asigna explícitamente.
- **Los filtros y el maestro son solo de administrador.** Un clasificador decide
  sobre un expediente, no sobre la configuración del módulo: *"los filtros nada
  más lo podemos hacer tú y yo"*.
- **En el cliente el estado inicial es el más restrictivo.** Mientras se
  resuelve el rol no se puede clasificar; al revés se alcanzaría a pintar el
  botón y luego quitarlo.

### Dónde se bloquea de verdad
En el backend, no en la interfaz:
- `gdAsignarExpediente` (clasificar y asignar): `operador` → **`clasificador`**.
- `correoCrearExpediente` (radicar): `operador` → **`clasificador`**. Radicar
  elige responsable y fecha límite, así que es una asignación.
- `correoProbarRegla`: `operador` → **`administrador`**. La pestaña Filtros ya
  estaba oculta para el resto; esto cierra la puerta de atrás del callable.

Responder, avances, novedades y cerrar lo propio siguen en `operador`: el cambio
no le quitó nada a quien trabaja sus expedientes.

### El expediente que nadie podía cerrar
En la prueba del 07-ago quedó un expediente asignado a otra persona que el
administrador no podía cerrar: recibía *"No tienes permiso para realizar esta
acción"*. `gdTerminarExpediente` exigía ser el responsable asignado, sin
excepción. Ahora el administrador del módulo también puede, y **la bitácora lo
dice**: el evento distingue "Un administrador del módulo marcó el proceso como
terminado" de "El responsable marcó…", en vez de dejarlo deducir comparando
cédulas.

### Interfaz
`gd_permisos.dart` (**nuevo**) es el único lugar donde el cliente interpreta un
rol. `lib/correo/correo_dashboard_screen.dart` usaba su propia lista de strings
para decidir `canManage`; ahora usa este mismo resolutor, así que la interfaz y
el backend ya no pueden discrepar (antes un desarrollador sin campo `rol` veía
Filtros oculto aunque el backend lo tratara como administrador).

- **Detalle del expediente**: sin permiso no se muestra el botón "Clasificar y
  asignar" deshabilitado — un botón gris invita a insistir. Va un aviso que
  explica qué falta, y el texto de la tarjeta cambia a "Está pendiente de que un
  clasificador defina el tipo documental y el responsable".
- **Bandeja de Correo**: el botón de radicar se reemplaza por un candado con
  tooltip cuando no hay permiso.
- **Tablero**: sigue visible para todos, como pidió Oscar. Se agregó un chip con
  el rol propio, **solo para quien no clasifica**: sin él, entrar a un
  expediente y no encontrar el botón parece una pantalla rota.

### Auditoría de lo ya construido — tres huecos cerrados
Antes de dar por cerrado el bloque, repasé todo lo anterior de esta misma
sesión buscando cabos sueltos entre backend, `gd_permisos.dart` y las pantallas.
Encontré tres:

1. **El botón de cerrar ajeno no existía.** `GdPermisos.puedeCerrarCualquiera`
   ya estaba definido y probado, pero `gd_correspondencia_screen.dart` seguía
   mostrando el botón "Terminar proceso" solo si
   `expediente.responsableId == widget.userId`. El backend ya dejaba pasar al
   administrador (sección anterior); la interfaz nunca le ofrecía el botón para
   usarlo. Ahora se muestra también con `_permisos.puedeCerrarCualquiera`, con
   un texto que dice explícito que se está cerrando un proceso ajeno y de quién
   es, para que no sea un clic accidental.
2. **Dos selectores para el mismo rol.** La matriz de accesos genérica de Admin
   (la que también configura Compras/Interventoría/Rutas) todavía ofrecía un
   selector "Correo: Administrador/Operador/Solo lectura" que escribía en
   `rolCorreo` (campo del usuario) — un lugar **distinto** al que ahora lee
   `GdPermisosService` con prioridad (`TBL_CORREO_ROLES`, la colección que
   escribe `gd_roles_screen.dart`). Con las dos activas, un admin podía elegir
   "Operador" en la matriz y el usuario seguir resolviendo como Clasificador
   porque el otro documento pesaba más — sin que la matriz avisara. Se quitó el
   selector de esa matriz (queda solo el interruptor de visibilidad del ícono);
   `gd_roles_screen.dart` es ahora el único lugar que asigna este rol.
3. **`CorreoService.resolverRol` quedó muerto** desde que
   `correo_dashboard_screen.dart` pasó a usar `GdPermisosService`, pero seguía
   en el archivo devolviendo un string plano sin el nivel `clasificador`. Se
   quitó: un método sin llamadores que además da una respuesta más pobre que el
   resolutor real es un riesgo para quien lo encuentre después.

`docs/correo.md` también describía los tres roles viejos; se actualizó con los
cuatro y con que el rol se asigna en "Roles de Correspondencia", no en la
matriz de Admin.

### `gd_roles_screen.dart` (nuevo) — "crear los roles"
Lista los usuarios de la empresa activa con su rol efectivo y un desplegable
para cambiarlo. Reutiliza `listarResponsables` (la misma lista de gente que
puede ser responsable) y `UserAvatar` con `nameHint`.

- Quien no tiene rol explícito aparece como "Rol por defecto (sin asignar)", no
  en blanco: en blanco daría a entender que no tiene acceso, y sí lo tiene.
- **Avisa cuando la empresa se queda sin clasificadores** — si no, la
  correspondencia entrante se acumula sin que nadie entienda por qué.
- Confirma dos casos: quitarle a alguien el permiso de clasificar, y **cambiarse
  el rol a sí mismo** (un administrador podría dejarse fuera de la pantalla que
  está usando).
- El docId es `{empresaId}_{userId}`, el mismo que lee el backend, así que un
  usuario no puede terminar con dos roles en la misma empresa. Se guardan
  también `empresaId` y `usuarioId` como campos porque el backend tiene una
  segunda búsqueda por campos para documentos antiguos.
- Responsivo: bajo 560 px el selector pasa debajo del nombre; "Clasificador y
  asignador" junto a un nombre largo no cabe en una fila de móvil.

Se llega desde **Admin › Correo** (primera tarjeta del panel) y desde **Admin ›
Catálogos**, junto al maestro de tipos.

### Archivos
| Archivo | Cambio |
|---|---|
| `gd_permisos.dart` | **Nuevo**. `GdRolCorrespondencia`, `GdPermisos`, `GdPermisosService` (resolver, listar, asignar, quitar). |
| `gd_roles_screen.dart` | **Nuevo**. Asignación de roles por usuario y empresa. |
| `functions/src/correo.ts` | Rol `clasificador` en el tipo, `normalizeRole` y la jerarquía; tres callables re-gateados; administrador puede cerrar; evento de cierre distingue quién. |
| `gd_correspondencia_screen.dart` | Carga de permisos, botón de clasificar gateado, aviso `_SinPermisoAviso`, segunda barrera en `_classify`; botón "Terminar proceso" también para `puedeCerrarCualquiera`. |
| `gd_control_dashboard_screen.dart` | Carga de permisos y chip de rol para quien no clasifica. |
| `correo_dashboard_screen.dart` | `_CorreoAccess` sobre `GdRolCorrespondencia`; botón de radicar gateado. |
| `correo_admin_panel.dart` | Tarjeta "Roles de Correspondencia". |
| `admin_dashboard_screen.dart` | Acceso a roles en Catálogos; quitado el selector de rol de Correo duplicado en la matriz de accesos (queda solo el interruptor de visibilidad). |
| `correo_service.dart` | Quitado `resolverRol` (dead code, superado por `GdPermisosService`). |
| `docs/correo.md` | Los cuatro roles y dónde se asignan ahora. |

### Verificación
- `cd functions && npm test`: **23/23**, con 8 nuevas de la jerarquía. Las que
  importan: `operador` no alcanza `clasificador`; `clasificador` sí alcanza
  `operador`; `clasificador` **no** alcanza `administrador`; un texto
  desconocido no concede permiso.
- `flutter test test/gestion_documental test/correo`: **40/40**, con 11 nuevas de
  `GdPermisos` (incluida la de que el estado "cargando" es el más restrictivo).
- `flutter analyze` sobre lo tocado: sin hallazgos nuevos (los 92 issues
  restantes son infos preexistentes en `admin_dashboard_screen.dart` y
  `gd_colaboracion_panel.dart`, ninguno en lo tocado).
- `flutter build web --no-tree-shake-icons --no-wasm-dry-run`: compila. Se
  verificaron contra el bundle las cadenas nuevas de rol y permisos
  ("Roles de Correspondencia", "Clasificador y asignador", el mensaje sin
  permiso, "Rol por defecto (sin asignar)").

### Pendiente operativo
1. **Desplegar functions** — es lo único que hace efectivo el bloqueo:
   `cd functions && firebase deploy --only functions`. Con el backend viejo la
   interfaz esconde los botones, pero el callable sigue aceptando a un operador.
2. **Asignar los clasificadores por empresa** en Admin › Correo › Roles de
   Correspondencia. Hasta que se asignen, todos quedan como operadores y **nadie
   podrá clasificar**: es el efecto buscado, pero hay que designar a alguien
   antes de que entre correspondencia nueva. La pantalla lo avisa en rojo.
3. Los filtros se escriben directo desde el cliente a `TBL_CORREO_REGLAS`. La
   pestaña está oculta para quien no es administrador y el callable de prueba ya
   exige administrador, pero **la escritura no está cerrada en
   `firestore.rules`** (no se toca por acuerdo). Cerrarla es tarea de la pasada
   de reglas.

---

## Sesión 2026-08-10 — Correspondencia: maestro de tipos documentales y códigos

Bloque A del cierre de la reunión del 07-ago 08:01. Es el que desbloqueaba a
los demás: sin maestro no hay código interno, y sin código interno la búsqueda
por expediente sigue dependiendo del radicado `GD-2026-000001`, que no dice
nada de qué documento es.

### El maestro: `TBL_GD_TIPOS_DOCUMENTALES`
Antes los tipos eran una lista `const` en `gd_correspondencia_screen.dart`, así
que agregar "SST" o "demandas laborales" exigía recompilar.

Campos: `empresaId`, `codigo`, `nombre`, `nombreLower`, `alias`, `activo`.
**El docId es `{empresaId}_{codigo}`**, y de ahí sale gratis la regla que pidió
Oscar: dos tipos no pueden compartir código, porque serían el mismo documento.
No hace falta consultar la colección para validar el duplicado — la creación va
en transacción y falla si el doc ya existe, con el mensaje que dice qué tipo lo
está usando.

Decisiones que vale la pena dejar escritas:
- **El código no se puede editar** después de crear el tipo. Si `TUT` cambiara,
  los expedientes que ya circularon como `TUT100826-001` quedarían apuntando a
  una raíz que no existe. La pantalla lo bloquea y sugiere crear otro tipo.
- **Los tipos se desactivan, no se borran.** El histórico guarda el nombre y el
  código del tipo con el que se clasificó.
- La colección entra por el catch-all de `firestore.rules`; **no hubo que tocar
  las reglas**.
- Las consultas son solo por igualdad (`empresaId`) y el orden se hace en
  cliente, así que **no hay índices nuevos por declarar**.

### El código interno: `TUT100826-001`
Tres letras del tipo + `ddMMyy` + consecutivo del día, como el estándar que ya
usa Interventoría (`PD-`, `RQ-`).

Se genera **en el backend**, dentro de la misma transacción de
`gdAsignarExpediente` que ya crea la tarea: contador
`TBL_GD_CONTADORES/{empresaId}_{CODIGO}_{ddMMyy}`, campo `ultimo`, igual que el
del radicado. Dos personas clasificando a la vez no pueden sacar el mismo
número.

- **La fecha es en hora de Bogotá**, no UTC. Con `new Date()` a secas, todo lo
  clasificado después de las 7 p.m. habría quedado fechado al día siguiente y el
  consecutivo no coincidiría con el día que ve quien clasifica.
- **El código se asigna una sola vez.** Reasignar el expediente (otro
  responsable, otra fecha) conserva el código con el que ya circuló en oficios.
- Si la empresa no tiene maestro, el expediente se clasifica igual y queda sin
  código interno. No se bloquea la operación por falta de configuración.

### El código externo
Campo opcional en Clasificar y asignar: el número con el que el remitente
identifica el oficio. Entra a la búsqueda, que es para lo que sirve — "el
expediente que me mandaron con el número 456".

### Dónde se ve
- Tabla del tablero: la columna `RADICADO` pasó a `CÓDIGO` y muestra el interno
  con el radicado debajo en gris (los expedientes viejos siguen mostrando su
  radicado, sin línea extra).
- Tarjeta móvil, ficha del listado, encabezado del detalle y título de la
  pantalla: `codigoVisible` (interno si existe, radicado si no).
- Encabezado del detalle: también el código externo cuando lo hay.
- Búsqueda: interno y externo entran en las dos pantallas, y el hint ahora dice
  "Buscar código, alias, asunto o responsable".

### Archivos
| Archivo | Cambio |
|---|---|
| `gd_tipos_documentales_screen.dart` | **Nuevo**. CRUD del maestro, código sugerido desde el nombre, vista previa del código que se generará, botón para sembrar los tipos base. Memoiza la stream (recrearla en cada build rompe web). |
| `gd_correspondencia_models.dart` | `GdTipoDocumental` + `normalizarCodigo`/`codigoSugerido`; `tipoDocumentalCodigo`, `codigoInterno`, `codigoExterno` y `codigoVisible` en `GdExpediente`. |
| `gd_correspondencia_service.dart` | CRUD del maestro, `sembrarTiposBase`, `GdTipoDocumentalError`; `clasificarYAsignar` envía código y código externo. |
| `gd_correspondencia_screen.dart` | Desplegable desde el maestro, campo de código externo, búsqueda y encabezados con los códigos. |
| `gd_control_dashboard_screen.dart` | Columna CÓDIGO, tarjeta móvil y búsqueda. |
| `functions/src/correo.ts` | `documentTypeCode`, `bogotaDayStamp` y la generación transaccional del código interno; devuelve `codigoInterno` al cliente. |
| `admin_dashboard_screen.dart` | Acceso al maestro desde Catálogos. |

### Los tipos base
`REQ` Requerimiento · `DPE` Derecho de petición · `TUT` Tutela · `CIR` Circular
· `SOL` Solicitud · `CON` Contrato · `DCO` Documento contractual · `PQR` PQR ·
`OTR` Otro. Son los mismos nueve que estaban fijos en código. El botón los
siembra sin tocar lo que ya exista.

### Verificación
- `flutter test test/gestion_documental test/correo`: 29/29, incluidas 10
  pruebas nuevas de `normalizarCodigo`/`codigoSugerido` (acentos, ñ, corte en
  cinco, nombres compuestos).
- `cd functions && npm test`: 15/15, con 7 nuevas del código interno. La que
  importa: 6-ago 23:30 Bogotá (7-ago 04:30 UTC) tiene que dar `060826`.
- `flutter analyze` sobre los archivos tocados: sin hallazgos. En
  `admin_dashboard_screen.dart` los 92 issues son infos preexistentes
  (`withOpacity`, `groupValue`); ninguno en lo agregado.
- `flutter build web --no-tree-shake-icons --no-wasm-dry-run`: compila.
- `npm run build` en functions: tsc sin errores.

### Pendiente operativo
1. **Desplegar functions** (`cd functions && firebase deploy --only functions`).
   Hasta que `gdAsignarExpediente` esté publicado, la app envía el código del
   tipo pero el backend viejo lo ignora: los expedientes se clasifican bien y
   sin código interno.
2. Sembrar los tipos base por empresa desde Admin › Catálogos › Tipos
   documentales.
3. El acceso al maestro está solo en Admin. Cuando esté el rol
   clasificador/asignador (Bloque C) conviene exponerlo también dentro del
   módulo, para que Oscar no tenga que salir a Administración.

---

## Sesión 2026-08-10 — Cierre de las reuniones del 07-ago (tanda rápida)

Los cuatro puntos de las dos actas del 7 de agosto que se resolvían con un
cambio puntual, para que Oscar los vea en sus pruebas del mismo día. Los
bloques pesados (maestro de tipos documentales + códigos interno/externo,
gráficas por responsable, permisos de clasificar/asignar, rendimiento al
cambiar de empresa, hoja de vida obligatoria) quedan pendientes y van después.

### 1. La sección se llama "Gestión de Correspondencia"
`gd_control_dashboard_screen.dart` › `_HeroHeader`: el título decía "Centro de
control documental". Oscar lo pidió explícito porque esa pantalla es solo
correspondencia. El AppBar sigue diciendo "Gestión Documental" a propósito: ese
es el nombre del módulo en Home y en `GuardedModulePage`; el módulo contiene la
sección, no al revés.

### 2. El anillo "Estado general" ya no cuenta terminados
Mismo archivo › `_StatusChart`. El razonamiento de Oscar: con 2.000 procesos
cerrados y cinco vigentes, el anillo se pintaba de un solo color y dejaba de
informar. Ahora solo Recibido + Asignado, subtítulo "Procesos activos" y el
número del centro dice "activos" en vez de "procesos" para que no se lea como
el total del sistema. El conteo de terminados no se pierde: sigue en la tarjeta
KPI "Terminados".

### 3. Plazo de subsanación: 1 día hábil por defecto
`interventoria_service.dart` › `kPlazoSubsanacionPorDefecto`: 8 → 1. De ahí
venía el "20 de agosto" que Oscar vio sobre un acta del 7. La fecha ya se
calculaba desde la fecha del acta (`desde: hallazgo.fechaHallazgo`), así que
bastó el default. Sigue siendo configurable por empresa en
`TBL_INTERVENTORIA_CONFIG/{empresaId}.plazoSubsanacion` (y por sección), que es
el mecanismo para ampliarlo donde un día no dé.

### 4. Las dos fechas quedaron rotuladas
Oscar veía "7 de agosto" y "20" sin saber cuál era cuál.
- Tabla de Hallazgos y tabla de Subsanaciones: encabezados `Fecha` → **Fecha
  del acta** y `Vence` → **Fecha límite**.
- Tarjeta móvil de hallazgo: prefijos `Acta …` y `Límite …`.
- Fichas del tablero de asignación: `Acta dd/MM/yy` y `Límite dd/MM/yy`, con
  Tooltip ("Fecha del acta" / "Fecha límite para subsanar") porque en la ficha
  no cabe el rótulo completo.
`_VenceHallazgoCell` se dejó sin prefijo: se usa dentro de columnas cuyo
encabezado ya dice "Fecha límite", y repetirlo sobraba.

### Verificación
- `flutter analyze` sobre los cuatro archivos: sin errores. Los 9 issues de
  `interventoria_dashboard_screen.dart` son de estilo y preexistentes (líneas
  755, 1748, 1899, 2198, 2698, 2944, 7106-7117), ninguno en lo tocado.
- `flutter build web --no-tree-shake-icons --no-wasm-dry-run` y revisión en
  navegador con el perfil desarrollador.

### Nota de riesgo pendiente
`lib/correo/` y `lib/gestion_documental/correspondencia/` (~5.100 líneas) están
**sin commitear**. Es el módulo que se presenta el 28 de agosto y no tiene punto
de retorno en git.

---

## Sesión 2026-08-07 — Rutas: Estudio de Movilidad (mediciones automáticas de tiempos)

### Qué se construyó
Submódulo **"Estudio movilidad"** dentro de la consola de Rutas (pestaña
nueva entre "Centro control" y "Configuración inicial"). Mide
automáticamente, **desde el backend** (no depende del celular), los tiempos
de desplazamiento Centro de Operaciones (Cra. 69 #79-11) → todos los
establecimientos, con tráfico en tiempo real, para el estudio técnico de
condiciones equivalentes de operación. Documentación completa en
`ESTUDIO_MOVILIDAD.md` (raíz).

### Backend (`functions/src/rutas_movilidad.ts`)
- `rutasMovilidadTick`: cron cada 5 min (America/Bogota) que dispara los
  horarios activos de `TBL_RUTAS_MOV_HORARIOS` con candado anti-duplicado en
  `TBL_RUTAS_MOV_RUNS` (docId determinístico + transacción).
- `rutasMovilidadMedirAhora`: callable para corridas manuales (todas o un
  punto), registra la cédula de quien dispara.
- Fuentes: **Google Routes API** (TRAFFIC_AWARE_OPTIMAL) por defecto y
  **TomTom** como alternativa; key por empresa (config) o `.env`
  (`MOVILIDAD_GOOGLE_API_KEY`, `MOVILIDAD_TOMTOM_API_KEY`).
- Cada medición guarda origen/destino con coordenadas, distancia vial,
  tiempo con/sin tráfico, demora, ruta principal/alterna, escenario, estado
  de tráfico, **riesgo** (0-60 bajo · 61-90 medio · 91-120 alto controlado ·
  >120 crítico), parámetros enviados y **JSON crudo de la API** como
  evidencia. Fallidas también quedan (`ok=false`).
- Alerta configurable (default 105 min ≈ "cerca de 2 horas", conservación de
  alimentos): observación automática + notificación a cédulas configuradas
  (`TBL_NOTIFICACIONES/{cedula}/notifications`, `createdAt` con
  `Timestamp.now()`, nunca serverTimestamp).

### App (lib/rutas/movilidad/: models + service + screen)
- Vistas: **Resumen** (última/próxima medición, pico vs valle, promedios por
  día/escenario/hora, top rutas lentas, críticas, corridas), **Mediciones**
  (tabla paginada filtrable por punto/día/hora/escenario/riesgo, detalle con
  JSON copiable), **Mapa** (Google Maps: origen violeta, puntos por color de
  riesgo verde/amarillo/naranja/rojo), **Programación** (interruptor
  maestro, fuente API, umbral, cédulas de alerta con UserAvatar/UserNameText,
  origen editable, horarios CRUD + "Crear sugeridos" sáb/dom/lun/mar ×
  06:00/07:00/09:30/12:00/17:00, sincronización de puntos del KML/CSV
  corregido contra `TBL_RUTAS_ESTABLECIMIENTOS`).
- Exportes (respetan filtros): **Excel** 3 hojas, **CSV** con BOM y **PDF**
  en 4 modos (resumen, por punto, por día, consolidado con metodología).
- Streams de Firestore memoizadas en estado (regla anti listener-churn).

### Datos / índices
- Colecciones nuevas: `TBL_RUTAS_MOV_CONFIG`, `TBL_RUTAS_MOV_HORARIOS`,
  `TBL_RUTAS_MOV_MEDICIONES`, `TBL_RUTAS_MOV_RUNS` (equivalen a
  `route_measurements` / `measurement_schedules` del requerimiento).
- `firestore.indexes.json`: +3 índices (mediciones por empresa+fechaHora,
  empresa+punto+fechaHora; runs por empresa+createdAt).
- Los 26 destinos del CSV corregido van embebidos como semilla en
  `movilidad_models.dart`; el centro (4.6862937, -74.082623) es el origen en
  config (OJO: el default viejo de `TBL_RUTAS_CONFIG` tenía otra coordenada;
  el estudio usa la suya propia).

### Reset de mediciones (añadido el mismo día)
Programación → **Zona de riesgo → "Borrar todas las mediciones"**: borra el
histórico (`TBL_RUTAS_MOV_MEDICIONES`) y la bitácora
(`TBL_RUTAS_MOV_RUNS`) de la empresa activa, por lotes paginados de 400.
Conserva configuración, horarios y establecimientos. Exige escribir
`BORRAR` en el diálogo porque es irreversible (una medición depende del
tráfico del instante y no se reconstruye).

### BUG: la vista Rutas y el PDF mezclaban corridas distintas
El usuario notó horas imposibles en la secuencia: Ruta 4 iba
`15:04 → 15:41`, `16:01 → 16:14` y la tercera parada saltaba a
`07:21 → 07:34`. Igual en Ruta 5 y Ruta 8 (siempre la última parada).

Causa: tanto `_rutasView` como el reporte PDF por ruta tomaban **la última
medición de CADA parada por separado**. Si la corrida en curso todavía no
había escrito la última parada, esa fila caía a una corrida anterior (la de
las 06:00) y la línea de tiempo quedaba con dos corridas mezcladas — con
horas que no encadenan y un acumulado que no corresponde.

Arreglo: se identifica el `runId` más reciente de cada ruta y se muestran
**solo las paradas de esa corrida**. Las que falten quedan como "sin
medición" en vez de traer datos de otro momento.

### Validación de la secuencia de rutas (integridad del estudio)
Al revisar los informes del usuario apareció un problema de datos, no de
código: **la misma ruta aparecía con distinta secuencia el mismo día**
(Ruta 1 iba TERMINAL→USME a las 04:00-06:00 y USME→TERMINAL desde las 10:00)
y con paradas que no son las del estudio (Ruta 5 con KENNEDY en vez de
BÚNKER/AEROPUERTO/FONTIBÓN). Como el acumulado depende del orden, eso cambia
el resultado de Medio (86 min) a **Crítico (134 min)** para el mismo punto, y
las mediciones dejan de ser comparables.

Causa probable: se estaban usando las rutas preexistentes del módulo Rutas,
que alguien reordenó a mitad del día.

Arreglo (hacerlo VISIBLE en vez de producir datos incomparables en silencio):
`MovilidadService.compararConEstudio(codigo, paradas)` contrasta la secuencia
guardada contra `kMovRutasEstudio`. En la vista Rutas cada tarjeta lleva un
sello ✓/✗ y, si algo no cuadra, sale un aviso rojo arriba que muestra
`guardada:` vs `estudio:` por ruta, las que faltan por crear, y un botón
directo a Programación. `_normalizar` se expuso como
`MovilidadService.normalizarNombre`.

**Confirmado por el usuario:** el orden correcto es planta → parada 1 →
parada 2 → fin, según la tabla de las 10 rutas, "así con todos".

### Informe para licitación: gráficas + ventanas en el PDF
El usuario descargó los informes y **las columnas nuevas no aparecían**:
salida→llegada y ventana se habían añadido a la app y al Excel, pero NO al
PDF. Corregido, y de paso el informe se reforzó para que sostenga una
licitación:

- **Gráficas** (paquete `pdf`, widget `pw.Chart`): tiempo en ruta por hora de
  salida (línea suavizada), por escenario, por día, **tiempo de cierre de
  cada ruta** (el indicador que decide si la operación es viable) y
  distribución de entregas por nivel de riesgo.
- **Sección "Cumplimiento de las ventanas de entrega"**: % de incumplimiento
  por servicio (desayuno/almuerzo/cena), peor retraso y tabla de los puntos
  que no alcanzan su ventana. Es una restricción DISTINTA del riesgo por
  tiempo en ruta y a veces más exigente.
- Columnas nuevas en el detalle del PDF (`Sale-llega`, `Ventana`) y en la
  secuencia del reporte por ruta (`Sale`, `Llega`, `Ventana`).
- `MovStats.cierrePorRuta()`: promedio del acumulado en la ÚLTIMA parada de
  cada ruta.

**Bug encontrado por una prueba, no en producción:** `test/movilidad_grafico_test.dart`
genera un PDF real con las gráficas. Reveló que con **una sola categoría** el
eje X queda sin rango y el paquete pinta con **NaN** (`PdfNum.output: '!value.isNaN'`),
tumbando la generación del informe. Arreglo: el eje siempre lleva ≥ 2
posiciones y la sobrante va sin etiqueta. La prueba también verifica que la
escala del eje Y quede ascendente con máximos de 0 a 1200.

### Horas reales por tramo + ventanas de entrega
Reporte del usuario: "no tiene sentido que TERMINAL y USME se midan a las
6am". **El encadenado sí funcionaba** (comprobado contra la API: los tramos
salen con su hora real); el problema era de PRESENTACIÓN — la columna "Hora"
mostraba la franja de la corrida en todas las filas. Además el descargue
estaba en 0.

- Se guardan y muestran `horaSalidaTramoTxt` y `horaLlegadaTxt` (Bogotá):
  la columna pasó a ser **"Salida → llegada"** (`06:00 → 06:17`).
- `minutosPorParada` por defecto **20** (antes 0).
- **Ventanas de entrega** nuevas (config `ventanasEntrega`): desayuno
  06:00–08:00, almuerzo 11:30–13:40, cena 16:00–18:00. Cada medición guarda
  `comida`, `ventanaHasta`, `dentroDeVentana` y `minutosFueraVentana`, con
  observación automática si llega tarde. Columna "Ventana" en la tabla,
  aviso "⚠ TARDE" en la vista Rutas y 6 columnas nuevas en el Excel.
  Es una restricción DISTINTA del riesgo por tiempo en ruta, y a veces más
  exigente.
- Horarios sugeridos alineados a las ventanas: 06:00, 07:00, 09:30
  (control), 11:30, 12:30, 16:00, 17:00.

Comprobado con salida real del sábado 06:00 y 20 min de descargue:
Ruta 1 → TERMINAL llega 06:17, descarga hasta 06:37, y **el tramo a USME se
consulta con salida 06:37**, llegando 07:24 (85 min en ruta). El mismo tramo
un viernes 17:44 daba 68 min contra 47 min el sábado: la hora encadenada sí
cambia el resultado. En rutas de 4 paradas **el descargue pesa más que el
tráfico** (~60 min de descargue vs ~45 de manejo).

### Selección de mediciones + informe por ruta o general
Tres peticiones del usuario tras ver la vista Rutas:

1. **Programar mediciones por ruta**: aclarado con el usuario — quiere
   **todas las rutas en cada horario**, que es justo como ya funcionaba. No
   se cambió nada.
**BUG corregido en la selección (reportado al probar):** con filtros puestos
no dejaba seleccionar para borrar. Dos causas, ambas mías:
`_MedicionesSource` se **construía en cada build** (PaginatedDataTable se
resuscribe al cambiar la instancia y perdía la selección), y
`selectedRowCount` estaba **fijo en 0**, así que la cabecera de la tabla no
reflejaba nada. Arreglo: la fuente se crea UNA vez en `initState`, guarda la
selección dentro y expone `selectedRowCount` real; el build solo le pasa las
filas visibles con `fijarDatos()` (sin `notifyListeners`, que en build
reventaría). El diálogo de borrado recibe ahora la lista COMPLETA, no la
filtrada, para poder mostrar qué se va a borrar aunque el filtro haya
cambiado después de seleccionar.

2. **Eliminar mediciones seleccionadas**: casillas en la tabla de
   Mediciones + botones "Seleccionar todas/filtradas", "N seleccionadas"
   (limpia) y "Eliminar" con diálogo que **muestra qué se va a borrar**, no
   solo cuántas. `MovilidadService.eliminarMediciones(ids)` borra por lotes
   de 400. Como la casilla ocupa el clic de la fila, el detalle se abre
   ahora con un ícono en la última columna.
3. **Informe por ruta o general**: filtro **"Ruta"** nuevo en la tabla (que
   acota también lo exportado) + modo de PDF **"Reporte por ruta"** con, por
   cada ruta, la secuencia de la última corrida (parada, desde, tramo,
   acumulado, km, riesgo) y su histórico completo. El chip de exportar
   ahora dice "Exportar (general)" o "Exportar (Ruta N)" para que quede
   claro el alcance antes de generar.

### CAMBIO DE FONDO: el estudio mide 10 RUTAS ENCADENADAS, no 26 viajes
Corrección metodológica del usuario: la operación no son 26 trayectos
independientes desde la planta (eso equivaldría a 26 vehículos saliendo a la
vez), sino **10 rutas**. Un vehículo sale, entrega en la parada 1, sigue a la
2, etc.

- El backend ahora lee la secuencia de `TBL_RUTAS` (colección propia del
  módulo) y mide **tramo a tramo**: planta→parada 1, parada 1→parada 2, …
  Los tramos de una ruta van en SERIE (el tramo N sale cuando termina el
  N-1); las rutas entre sí, en paralelo.
- **Cada tramo se consulta con su hora de salida real** (`departureTime` en
  Google, `departAt` en TomTom), así las paradas finales se evalúan con el
  tráfico que de verdad encontrarán, no con el de la hora de arranque.
- **El riesgo se calcula sobre el ACUMULADO** (`minutosEnRutaAlLlegar`), no
  sobre el tramo: lo que expone al alimento es cuánto lleva fuera de la
  planta al llegar, no lo que tardó el último trayecto. Las alertas y todas
  las estadísticas (promedios por día/hora/escenario, pico vs valle,
  ranking, comparativo) usan ese valor.
- Campos nuevos por medición: `rutaId`, `rutaCodigo`, `ordenParada`,
  `totalParadasRuta`, `esPrimerTramo`, `tramoDesdeNombre/Lat/Lng`,
  `duracionAcumuladaMin`, `distanciaAcumuladaKm`, `minutosEnRutaAlLlegar`,
  `riesgoTramo`, `horaSalidaTramo`.
- Config nueva: `minutosPorParada` (descargue por parada, default 0) que se
  suma al tiempo en ruta de las paradas siguientes.
- Semilla `kMovRutasEstudio` con las 10 rutas y su secuencia + botón
  **"Sincronizar rutas del estudio"** que las crea en `TBL_RUTAS` cruzando
  con el maestro de establecimientos. Verificado: las 10 rutas cubren
  exactamente los 26 puntos, sin faltantes ni sobrantes.
- Compatibilidad: los registros del modelo anterior no traen acumulado, así
  que `minutosEnRutaAlLlegar` cae a `duracionTraficoMin` al leerlos.
- UI: columnas "Ruta" y "En ruta" (acumulado, la que manda el riesgo) además
  de "Tramo"; el detalle muestra la posición en la secuencia y desde dónde
  salió el tramo. Excel y PDF con las mismas columnas; el ranking del PDF
  pasó a ser "por TIEMPO EN RUTA".
- **Vista "Rutas" nueva en el dashboard** (2ª pestaña del selector): cada
  ruta como una línea de tiempo vertical — salida de planta y luego cada
  parada numerada con el tramo, la distancia, las obras si las hay y el
  **acumulado en ruta** en color de riesgo; en la cabecera el total de la
  ruta. Funciona sin mediciones (muestra la secuencia y "sin medición").
  Las vistas quedaron: 0 Resumen · 1 Rutas · 2 Mediciones · 3 Mapa ·
  4 Programación.

**Comprobado contra la API real** (17:44 hora pico, antes de desplegar el
backend): Ruta 1 → TERMINAL 38,4 min, y USME acumula **106,5 min** (riesgo
alto controlado) frente a los 54 min que daba el modelo directo. El segundo
tramo se consultó con salida 23:22 UTC, no con la del arranque, o sea que la
hora de salida sí se encadena. MÁRTIRES→DIJIN da 0 km / 0,2 min porque están
en la misma dirección (Kr 24 #12-32), lo que coincide con la tabla del
usuario.

### Obras OFICIALES del Distrito (PMT de la SDM) + sección de fuentes
El usuario aportó dos fuentes distritales y se evaluaron ambas:

- **INTEGRADA — PMT (Planes de Manejo de Tránsito), Secretaría Distrital de
  Movilidad vía SIMUR**: `sig.simur.gov.co/arcgis/rest/services/PMT/
  Publicacion_Vigentes_Provisional/MapServer`. Servicio público, sin llave.
  Es el visor "Obras en la vía" del Portal Mi Movilidad. Se consultan las
  capas 0,1,2,3,5,6 (obras infraestructura y servicios públicos en punto y
  tramo, eventos y desvíos) con filtro de vigencia
  `FINI <= CURRENT_TIMESTAMP AND FFIN >= CURRENT_TIMESTAMP`, se cruzan con la
  geometría de cada ruta y se deduplican por radicado. Se guarda tramo,
  tipo de afectación, contratista, localidad, horario, vigencia y **radicado
  SDM** — o sea evidencia administrativa citable, muy superior a "TomTom
  detectó una obra". 6.096 registros vigentes verificados.
- **DESCARTADA de la automatización — Malla Vial Integral (SDP)**: trae
  estado de la vía (B/R/M/SD), carriles, ancho y CIV, pero el campo
  velocidad de operación viene VACÍO y carriles está parcialmente
  diligenciado; además es estático. Queda para consulta manual.

Rendimiento: el cruce pasó a un **índice espacial de rejilla** (celda
derivada de `RADIO_INCIDENTE_M`), porque 6.000 obras × 26 rutas por fuerza
bruta eran decenas de millones de comparaciones.

Informe: nueva sección **"Fuentes de información y trazabilidad"** (en el
resumen y en el consolidado) que documenta cada dato, su fuente, su endpoint
y su alcance, distinguiendo oficial vs comercial. Nueva sección **"Obras
autorizadas por la SDM sobre las rutas medidas"** agrupada por radicado con
las rutas afectadas. Excel con 3 columnas nuevas (obras PMT, radicados,
detalle).

### Obras en la vía + reintentos (tras analizar el primer PDF real)
Del primer informe consolidado salieron dos hallazgos y una petición:

1. **6 de 26 llamadas a TomTom fallaron (~23 %)**. Probados los 6 puntos uno
   a uno todos respondían 200 → fallo transitorio por cuota del plan
   gratuito. Ahora `fetchConReintentos()` reintenta hasta 3 veces con espera
   creciente (400 ms → 1,2 s) ante 429/403/5xx y errores de red, en ambas
   APIs. Los errores no recuperables fallan de una.
2. **Obras en la vía** (petición del usuario): cada medición cruza la
   **geometría de su ruta** con los incidentes viales vigentes y conserva
   los que caen a menos de 150 m. Fuente TomTom Traffic Incidents (Google no
   expone incidentes); 1 llamada por corrida, no por punto. Geometría:
   `legs[].points` en TomTom y `polyline.encodedPolyline` decodificada en
   Google. Se guardan conteos (obras/cierres/congestiones/accidentes) y
   detalle de hasta 15 incidentes con calles, longitud y demora. Si hay
   obras, la observación automática de la medición lo dice.
   UI: columna "Estado de la vía" + sección en el detalle; Excel con 4
   columnas nuevas; PDF con apartado "Condiciones de la vía durante las
   mediciones".
3. Cosméticos del informe: se quitó el "(25 min)" redundante cuando el
   promedio no llega a una hora, y el comparativo ahora explica que solo
   lista los puntos con medición válida de AMBOS proveedores.

Nota de despliegue: `valid-jsdoc` de eslint **no acepta el tipo
`number[][]`** en `@param`/`@return` (da "JSDoc syntax error" y tumba el
predeploy) — usar `Array<Array<number>>`.

### BUG corregido: "Crear sugeridos" no mostraba los horarios
Causa raíz: **la variante inversa del listener churn** de
`firestore-listener-churn`. El mismo `Stream` memoizado de horarios se
consumía en DOS vistas que se montan/desmontan al cambiar de pestaña
(Resumen y Programación). Al cambiar de vista se cancelaba la suscripción y
la siguiente se enganchaba a un stream ya cerrado → nunca llegaban datos y
la pantalla decía "Sin horarios", idéntico a que no existieran.

Agravante: los fallos eran **invisibles**. El botón no tenía `try/catch` y
el `StreamBuilder` ignoraba `hasError`, así que un error de permisos o de
stream se veía igual que una lista vacía.

Arreglo:
- Los horarios y las corridas se leen con **una suscripción única viva
  mientras exista la pestaña** (`_horariosSub`/`_runsSub` con `.listen()` en
  `initState`, `cancel()` en `dispose`); el estado se guarda en campos y se
  pasa como `List` a las vistas hijas, no como `Stream`.
- Errores visibles: banner rojo con el texto del error, snackbar de 8 s,
  estado "Cargando horarios…" y `try/catch` en el botón.
- `crearHorariosSugeridos` devuelve `(creados, yaExistian)` para distinguir
  un fallo de ESCRITURA de uno de LECTURA, y valida `empresaId` vacío.

### API keys fuera de la UI
Los campos de API key se quitaron de Programación: viven solo en
`functions/.env` para no exponerlas en el bundle del navegador. **El `.env`
se empaqueta al desplegar**, así que tras cambiar una key hay que
redesplegar las functions.

### Rediseño de columnas: ACTUAL vs ESPERADO + comparativo de 2 APIs
Decisión del usuario: el estudio no compara "con tráfico" contra "vía
vacía", sino **lo actual medido** contra **lo calculado/esperado**. Cambios:
- Columnas renombradas en tabla, detalle, Excel, CSV y PDF: **Actual**
  (`duration`, tráfico en vivo) y **Esperado** (`staticDuration`, modelo de
  velocidades nominales).
- Nueva columna **Diferencia con signo** (`diferenciaEsperadoMin`): positiva
  = va peor que lo calculado (naranja), negativa = mejor (verde). La columna
  formal "Demora por tráfico" (≥ 0) del requerimiento se conserva aparte.
- **Comparativo entre proveedores**: switch "Medir con las dos APIs" en
  Programación. Cada punto se mide en la misma corrida con Google y TomTom y
  se guarda **una medición por fuente** (cada una con su JSON crudo). Las
  alertas y KPIs salen solo de la fuente principal (`fuentePrincipal`) para
  no duplicar. Nueva sección en Resumen, hoja "Comparativo fuentes" en Excel
  y bloque en el PDF: promedio por API, diferencia absoluta/%, promedio de
  ambas.
- Config: `apiKey` → `apiKeyGoogle` + `apiKeyTomtom` (lee `apiKey` legacy),
  y `compararFuentes`. Campos separados en la UI.

### Nota técnica: "actual" a veces sale MENOR que "esperado"
No es error de captura. En Google Routes API `staticDuration` no es
free-flow sino un modelo de **velocidades nominales** por tramo, conservador
en las arterias de Bogotá; cuando el tráfico fluye mejor que ese modelo
(festivos, domingos, madrugada) la predicción en vivo queda por debajo.
Verificado el 2026-08-07 en las 3 rutas alternativas a USME (54 vs 59 min en
la elegida), o sea que no es artefacto de selección de ruta. La demora se
guarda como 0 (no existe demora negativa). Si se necesitara un free-flow
real + demora explícita del proveedor, TomTom los entrega — se cambia en
Programación. Detalle en `ESTUDIO_MOVILIDAD.md` § 2.

### Estado operativo
1. ✅ Functions desplegadas (`rutasMovilidadTick` scheduled +
   `rutasMovilidadMedirAhora` callable, us-central1, nodejs20, 512 MB; el
   cron ya corre cada 5 min). Smoke test callable OK.
2. ✅ Índices de Firestore desplegados.
2b. ✅ Hosting desplegado: <https://to-do-gestion.web.app> ya sirve el build
   con la pestaña "Estudio movilidad" (verificado en el bundle de
   producción).
3. ✅ **Routes API verificada habilitada**: llamada real con la key de `.env`
   devolvió ruta centro → Engativá (3,36 km, 735 s). Paso a paso para key
   dedicada/TomTom en `ESTUDIO_MOVILIDAD.md` § 9.
4. ✅ Verificado: `tsc` y eslint limpios, `flutter analyze` sin errores
   nuevos, `flutter build web` OK, app arranca sin errores de consola.
5. Pendiente (usuario, en la app): Programación → "Crear sugeridos" →
   "Sincronizar puntos" → "Medir ahora"; y revisar el origen errado del
   default viejo de `TBL_RUTAS_CONFIG`.

---

## Sesión 2026-08-07 — Tokens DIAN: buzón propio (Yahoo/IMAP) con filtro exclusivo

### Problema
El módulo quedó desplegado con la bóveda cifrada y la tabla funcionando, pero
sin conector: para conectar el buzón había que pasar por **Admin → Correo**,
que es el módulo general. Ese botón conecta Gmail/Microsoft, baja la bandeja
completa, la pasa por reglas y la escribe en `TBL_CORREO_MENSAJES`. No es lo
que se necesita: del buzón DIAN solo deben entrar los correos del token.

### Decisión
Tokens DIAN tiene **su propio buzón**, separado del módulo Correo. Nada de lo
que baja este conector toca `TBL_CORREO_CUENTAS`, `TBL_CORREO_MENSAJES`, las
reglas ni las alertas de WhatsApp.

Proveedor: **Yahoo por IMAP con contraseña de aplicación** (Yahoo ya no expone
OAuth para terceros). Dependencias nuevas en `functions`: `imapflow` y
`mailparser`, ambas MIT.

### El filtro, que es el punto
Solo entra un correo si cumple **una** de las dos condiciones:

- remitente exactamente `facturacionelectronica@dian.gov.co`, o
- asunto que contenga `Token Acceso DIAN`.

Se aplica **dos veces**:

1. Como `SEARCH ... OR FROM ... SUBJECT ...` en el servidor de Yahoo, así que
   el resto de la bandeja ni siquiera se descarga.
2. En memoria antes de guardar nada. Esto importa porque el SEARCH de IMAP
   compara por subcadena: `facturacionelectronica@dian.gov.co.attacker.net`
   pasaría el filtro del servidor, pero la segunda compuerta compara la
   dirección completa y lo descarta.

El enlace se extrae del cuerpo (texto y HTML, decodificando `&amp;`) y entra
al mismo `registrarTokenDianDesdeCorreo` que ya existía: se valida contra
`catalogo-vpfe.dian.gov.co/User/AuthToken`, se cifra AES-256-GCM y se
deduplica por hash. Un enlace que no sea del portal oficial no se guarda.

### Cambios
- `functions/src/dian_mailbox.ts` (nuevo): compuerta `esCorreoTokenDian`,
  extracción del enlace, sincronización IMAP y callables `dianBuzonEstado`,
  `dianBuzonConectar`, `dianBuzonSincronizar`, `dianBuzonDesconectar`, más el
  cron `dianBuzonProgramado` cada 5 minutos.
- `functions/src/dian_tokens.ts`: se exportan `requireCaller`, `encrypt` y
  `decrypt` para reusarlos sin duplicar la lógica de permisos ni de cifrado.
- `lib/admin/dian_tokens_admin_panel.dart`: la tarjeta estática "se completará
  mañana" se reemplaza por la conexión real — estado, botón **Conectar buzón
  Yahoo**, buscar ahora, desconectar y el texto que dice qué se lee y qué no.
- `lib/tokens_dian/dian_tokens_dashboard_screen.dart`: el banner muestra el
  estado real del buzón y deja lanzar una lectura manual.
- `lib/tokens_dian/dian_tokens_models.dart` + `_service.dart`:
  `DianBuzonEstado` y `DianBuzonResumen`.

### Credenciales
La contraseña de aplicación viaja una sola vez, se prueba contra el servidor
IMAP antes de aceptarla y queda cifrada en `TBL_DIAN_TOKEN_CONFIG/{empresaId}`
— colección que las reglas ya bloquean por completo (`allow read, write: if
false`), así que **no hubo que tocar `firestore.rules`**. La app nunca recibe
la contraseña ni su ciphertext: `dianBuzonEstado` devuelve solo lo mostrable.

### Verificación
- `npm run build` + `node --test test/dian_mailbox.test.js`: 8/8. Cubren
  remitente oficial en sus tres formas, asunto con tildes y espacios dobles,
  descarte de correos ajenos, dominio parecido que no se cuela, extracción del
  enlace desde HTML con entidades y rechazo de enlaces de otro dominio.
  La prueba 7 usa el correo real: saca el `href` del botón verde "Ingrese
  aquí" y comprueba que el enlace llega entero a `validatedDianUrl` — `pk`
  con el pipe codificado (`%7C`), `rk` y `token` intactos. La 8 verifica que
  el `mailto:` del destinatario no se confunda con el enlace del token.
- `flutter test test/tokens_dian/`: 8/8.
- `flutter analyze` sobre los archivos tocados: sin hallazgos.
- `flutter build web --no-tree-shake-icons --no-wasm-dry-run`: compila.

### Corrección posterior: el botón estaba donde no se buscaba
Al probarlo en producción, un admin dentro del módulo solo veía **Registrar
manual** — que pide un enlace que todavía no tiene — y el botón de conectar
había quedado únicamente en Admin → Tokens DIAN, sin forma de llegar desde ahí.

- El formulario de conexión se extrajo a `lib/tokens_dian/dian_buzon_dialog.dart`
  para no tener dos versiones del mismo texto sobre qué se lee del buzón.
- El módulo ahora muestra **Conectar buzón Yahoo** cuando falta conectarlo, y
  el registro manual pasó a ser una acción secundaria, "Pegar enlace a mano",
  con la explicación de cuándo sirve (copiar el enlace del botón "Ingrese
  aquí" del correo) y de que con el buzón conectado no hace falta.

### Segunda corrección: el primer intento de conexión falló
Log de `dianBuzonConectar`: `took 10332 ms, finished with status code: 400`.
La función se llamó bien (`auth: VALID`); los 10 segundos son el login contra
Yahoo, que rechazó la clave. Se usó la contraseña normal del correo — Yahoo
bloquea IMAP con esa a propósito y solo acepta una contraseña de aplicación.

Tres arreglos a partir de ahí:

1. **Bug real encontrado al revisar**: Yahoo muestra la contraseña de
   aplicación en grupos de cuatro separados por espacios, pero el servidor la
   espera sin ellos. `texto()` solo recortaba los extremos, así que pegarla tal
   como Yahoo la muestra fallaba aunque fuera correcta. Ahora se quitan todos
   los espacios antes de enviarla.
2. El diálogo abre con un aviso en amarillo: **no uses la clave con la que
   entras a Yahoo**, y los 4 pasos para generar la de aplicación.
3. El mensaje de error de Yahoo ahora nombra la causa más probable en vez de
   decir solo "credenciales rechazadas".

### Retirado: el registro manual de enlaces
Por decisión del usuario, los tokens entran **únicamente** por el detector del
buzón. Se eliminaron el botón, el diálogo, `DianTokensService.registrarManual`
y la callable `dianTokenRegistrar` (borrada también de producción con
`firebase functions:delete`). `registrarTokenDianDesdeCorreo` se conserva: es
la puerta de entrada del detector.

### Sobre por qué no hay "iniciar sesión con Yahoo"
Google y Microsoft publican OAuth abierto, por eso esos dos botones del módulo
Correo funcionan. Yahoo reserva el suyo para apps aprobadas como socio
comercial; lo que ofrece a todo el mundo es IMAP con contraseña de aplicación.
No es una limitación del código. Si algún día se quiere el flujo de sign-in,
el camino es mover el buzón DIAN a Gmail o Microsoft 365 y reusar el conector
de Correo, que ya existe.

### Tercera corrección: faltaba el log, y por eso hubo que adivinar
Los dos primeros intentos fallaron con `status code: 400` y nada más en el log:
el `HttpsError` se llevaba el motivo real de Yahoo y no quedaba registrado.
Estar adivinando entre "clave rechazada" y "no hay salida de red" costó dos
rondas. Corregido:

- `detalleError()` registra código, `serverResponseCode` y `responseText` de
  Yahoo. Nunca la contraseña.
- El motivo se guarda en `buzon.ultimoError`, así que queda escrito en el
  banner del módulo en vez de desaparecer en un aviso de 4 segundos.
- Avisos de error de 14 segundos y con botón de cerrar.
- Timeouts explícitos en ImapFlow (conexión 20 s, saludo 15 s, socket 60 s).

Para descartar la hipótesis de red se desplegó un diagnóstico temporal
(`diagImapYahoo`, sin credenciales: solo saludo y CAPABILITY del servidor) y se
borró después. Desde la máquina local el saludo llega en 281 ms y Yahoo
anuncia `AUTH=PLAIN AUTH=XOAUTH2 AUTH=OAUTHBEARER ... UIDONLY X-UIDONLY`.
La red nunca fue el problema: era la contraseña.

### Estado: funcionando
```
14:28:31  dianBuzonConectar: took 18060 ms, status code: 200
14:30:10  [dian_mailbox] corrida {"empresaId":"EMPRESA_001","revisados":0,...}
```
Buzón conectado y el cron leyéndolo cada 5 minutos sin errores. Desplegadas 5
funciones en `us-central1`, `dianTokenRegistrar` y `diagImapYahoo` eliminadas, y
la web en https://to-do-gestion.web.app.

### Nota para el futuro
El primer barrido solo mira los últimos 3 días. Para recuperar tokens más
viejos hay que reconectar con **Revisar tokens DIAN anteriores** encendido.

---

## Sesión 2026-08-05 — Interventoría: asignación automática por numeral

### Objetivo
Los responsables de cada numeral del acta estaban en un Excel
(`Numerales Interventoria.xlsx`, hoja `Numerales`, 140 numerales con
Responsable + Aprobador por cargo). En la app la asignación era 100% manual:
alguien elegía un área y recién ahí se creaba la tarea, **sin fecha límite**.
Ahora el hallazgo se asigna solo según su numeral, y la tarea nace con fecha.

### Decisiones de negocio (definidas con el usuario)
1. **Cargo → persona**: por centro de costo + cargo. "Administrador" cae en el
   administrador de ESE establecimiento; los cargos corporativos (Gerencia,
   Director de operaciones) se resuelven a nivel empresa.
2. **Aprobador**: queda como `jefeUid` de la tarea → recibe notificación al
   finalizar y es quien aprueba la subsanación (reusa el flujo de estados).
3. **Fecha límite**: 8 días hábiles por defecto, configurable por sección en
   `TBL_INTERVENTORIA_CONFIG/{empresaId}.plazoSubsanacion`.
4. **Automatismo**: se asigna sola al crear el hallazgo; quien tenga permiso
   puede reasignar después y esa elección manual gana sobre la matriz.

### Defecto encontrado y corregido: el numeral no era el numeral
`_autoCrearHallazgosDesdeItems` guardaba en `numeroHallazgo` un ordinal
`índiceCategoría.índiceObservación`, **no** el numeral del acta — y encima
corrido un lugar, porque `kInterventoriaCategorias` arranca con
`conceptoSanitario`: la sección 2 del acta quedaba registrada como "3.x".
Consultar la matriz con ese número habría asignado al cargo equivocado.

Solución: campo nuevo `numeralActa` con el numeral REAL, reconstruido desde la
categoría + el número que encabeza el aspecto ("14. El contratista…" en
`instalacionesFisicas` → "2.14"). `numeroHallazgo` se deja intacto para no
alterar lo ya registrado. El getter `numeralParaMatriz` nunca usa
`numeroHallazgo` en hallazgos de fuente `acta`. Si el numeral no se puede
determinar con certeza, queda vacío y la asignación sigue siendo manual:
**preferimos no asignar antes que asignar mal**.

### Cambios
| Archivo | Qué cambió |
|---|---|
| `interventoria_numerales_catalogo.dart` (NUEVO) | Matriz de 140 numerales → cargo responsable + cargo aprobador, generada del Excel. Además: `kInterventoriaSeccionPorCategoria` (categoría → sección real del acta), `numeralActaDesdeAspecto`, `normalizarNumeralActa`, `normalizarCargo` y `afinidadCargo` (reconoce "ADMINISTRADORA" o "Gerente General" sin duplicar entradas). |
| `interventoria_models.dart` | Campos `numeralActa`, `responsableId/Nombre`, `cargoResponsable`, `aprobadorId/Nombre`, `cargoAprobador`, `fechaLimite` en `InterventoriaHallazgo` (todos opcionales, sin migración) + getter `numeralParaMatriz`. |
| `interventoria_service.dart` | `resolverAsignacionPorNumeral()`, `_usuariosDeEmpresa()`, `_resolverCargo()`, `plazoSubsanacionDias()`, `sumarDiasHabiles()`. `crearTareaYNotificarHallazgo` ahora asigna por matriz, pone al aprobador como jefe, **pasa `fechaLimite` a `createTaskEs`** y guarda todo en el hallazgo. `_autoCrearHallazgosDesdeItems` calcula `numeralActa` y dispara la asignación de los hallazgos recién creados. |
| `interventoria_dashboard_screen.dart` | Columnas "Responsable" y "Vence" (en rojo si venció) en la tabla de hallazgos; `completarActa` pasa quién registra; la asignación manual usa `preferirAreaManual: true`. |
| `test/interventoria/interventoria_numerales_catalogo_test.dart` (NUEVO) | 14 pruebas: cobertura de los 140 numerales, saltos del acta respetados, sección ≠ posición en la lista de categorías, matching de cargos. |

### Decisiones técnicas
- **Sin Cloud Function nueva ni índices**: todo se resuelve con la matriz local
  y una lectura de `TBL_USUARIOS` ya existente en el módulo.
- La matriz vive en Dart, igual que `kInterventoriaItemsActaPorCategoria`: es
  el mismo tipo de dato (estructura del acta, no dato de operación).
- Solo se auto-asignan los hallazgos **creados en esa pasada**. Los que ya
  existían conservan el flujo manual, para no generar de golpe tareas y
  notificaciones de actas viejas.
- Un fallo al crear la tarea no tumba el guardado del acta: el hallazgo queda
  registrado y asignable a mano.

### Verificación
- `flutter test test/interventoria/`: **15 pruebas OK**.
- `flutter analyze lib/interventoria/`: 9 issues, **todos infos preexistentes**
  (`curly_braces`, `deprecated value:`, `dart:html`), ninguno en lo modificado.

### PENDIENTE — decisión del usuario
`kInterventoriaCategorias` declara 12 categorías y solo hay 11 listas de
numerales: **`horario` ("1. Horario") queda con cero numerales**, porque los 3
aspectos de la sección 1 están dentro de `conceptoSanitario`. El acta real
tiene 11 secciones puntuables. Arreglarlo = quitar `horario` y renombrar
`conceptoSanitario` a "1. Horario y concepto sanitario", pero
`InterventoriaVisita.fromMap` solo lee las claves que estén en la lista: las
actas viejas que tengan puntaje bajo `horario` dejarían de contarlo y su
porcentaje recalculado cambiaría (el `porcentajeGeneral` ya guardado no se
toca). Requiere confirmar antes de ejecutar.

---

## Sesión 2026-08-05 — Gestión Documental: alias del expediente

### Objetivo
El expediente se identifica hoy por `radicado` + `asunto`, y ambos los escribe
la Cloud Function al radicar el correo. Nadie puede ponerle al caso un nombre
propio para reconocerlo después. Se agrega un campo libre "Alias del
expediente" (ej.: `Tutela Pedro Pérez TD1234`) que además entra en la búsqueda.

### Alcance
- Editable **en cualquier momento** por cualquier usuario con acceso al módulo
  (decisión del negocio). Cada cambio queda en la trazabilidad.
- Campo opcional: los expedientes ya existentes no requieren migración.

### Cambios
| Archivo | Qué cambió |
|---|---|
| `gd_correspondencia_models.dart` | Campo `alias` en `GdExpediente` (default `''`) + getters `tieneAlias` y `titulo` (alias si existe, asunto mientras no). |
| `gd_correspondencia_service.dart` | `guardarAlias()`: batch que escribe `alias`, `aliasLower`, `aliasActualizadoPor/At` en `TBL_GD_EXPEDIENTES` y registra evento `alias_actualizado` / `alias_eliminado` en `TBL_GD_EXPEDIENTES_EVENTOS`. No-op si el valor no cambió. |
| `gd_correspondencia_screen.dart` | `_editAlias()` (diálogo con hint y opción "Quitar alias"); `_DetailHeader` muestra el título y el botón "Ponerle un alias"/"Editar alias" (con el asunto como línea secundaria); `_CorrespondenceTile` titula por alias; alias sumado al filtro de búsqueda y al hint. |
| `gd_control_dashboard_screen.dart` | Columna `ALIAS / ASUNTO` en `_ProcessTable`, alias en `_MobileProcessCard`, alias sumado al filtro de búsqueda y al hint. |

### Decisiones técnicas
- **Sin Cloud Function nueva**: `TBL_GD_EXPEDIENTES` cae en el catch-all de
  `firestore.rules` (`allow read, write: if isSignedIn()`), así que el alias se
  escribe directo desde el cliente. Tampoco hay reglas ni índices nuevos.
- **Sin índice Firestore**: la búsqueda de correspondencia ya es 100% en
  cliente (`streamExpedientes` trae la empresa completa y se filtra en
  memoria), así que sumar el alias al filtro no cuesta nada.
- `aliasLower` se persiste desde ahora aunque hoy no se use: cuando el volumen
  obligue a mover la búsqueda al servidor, no habrá que migrar los expedientes
  ya etiquetados.
- **Web vs Móvil**: mismo modelo, mismo service, misma validación. Solo cambia
  la composición (tabla con columna en web, tarjeta en móvil).

### Verificación
- `flutter analyze lib/gestion_documental/correspondencia`: sin errores nuevos
  (único info = `use_null_aware_elements` preexistente en
  `gd_colaboracion_panel.dart:641`).

---

## Sesión 2026-07-30 — Compras: revertir aprobaciones dadas por error

### Objetivo
Calidad a veces aprueba un documento que no debía. Hasta ahora la única salida
era **descargar el archivo y volverlo a subir**, porque `aprobado` era un estado
terminal. Ahora el **Admin Documental** (`kRolAdmin`) puede corregir esa
aprobación desde la app.

### Por qué estaba bloqueado
| Punto | Qué hacía |
|---|---|
| `compras_dashboard_screen.dart` (rama `if (doc!.aprobado)`) | Pintaba el documento aprobado como "solo visual": ningún botón. |
| `_matchesDocFilter` (recepción y proveedor) | `!doc.aprobado && !doc.rechazado` → los aprobados **desaparecen** de la pantalla de Calidad. |
| `validarCorreccionesRecepcion` | Sin documentos rechazados, rechaza cualquier corrección sobre una recepción cerrada. |

Los tres juntos cerraban la puerta. Por eso no bastaba con agregar un botón:
había que darle al admin un lugar donde los aprobados vuelvan a ser visibles.

### Cambios
| Archivo | Cambio |
|---|---|
| `lib/compras/compras_models.dart` | `DocAdjunto` gana trazabilidad de reversión: `revertidoPor`, `fechaReversion`, `motivoReversion`, `estadoAnteriorReversion`, el getter `tuvoReversion` y `clearReversion` en `copyWith`. Serializados en `toMap`/`fromMap`. |
| `lib/compras/compras_service.dart` | `revertirAprobacionDocRecepcion(...)` y `revertirAprobacionDocProveedor(...)`. Motivo obligatorio; exigen que el documento esté realmente aprobado; registran quién revirtió y desde qué estado. |
| `lib/compras/compras_dashboard_screen.dart` | Pestaña **"Aprobados"** en la pantalla de Calidad, visible **solo si `esAdmin`** (4 pestañas en vez de 3). Diálogo `_pedirMotivoReversion` con motivo obligatorio y elección de destino. |
| `test/compras/compras_reversion_aprobacion_test.dart` *(nuevo)* | 12 pruebas: trazabilidad, ida y vuelta por Firestore, compatibilidad con documentos antiguos y efecto sobre el estado de la recepción. |

### Decisiones de negocio
- **Dos destinos**, los elige el admin en el diálogo:
  - *Volver a revisión* → regresa a la cola de Calidad. No notifica: no hay nada
    que corregir, solo que volver a mirarlo.
  - *Rechazar* → queda rechazado, **notifica a quien subió el archivo** y crea la
    tarea de corrección de 8 días, reutilizando `_notificarYTareaRechazo`.
- **Motivo obligatorio** en ambos casos. Es una acción excepcional y debe
  quedar por escrito quién la hizo y por qué.
- **No se borra `revisadoPor`/`fechaRevision`.** Quien aprobó por error queda
  registrado; la reversión se suma al historial, no lo tapa.
- **Solo `kRolAdmin`.** Coherente con eliminar recepciones y fichas, que ya son
  exclusivas de ese rol. Calidad no puede deshacer su propia aprobación.
- Al volver a revisión se respeta la naturaleza del documento:
  `estadoInicialDocumentoRecepcion` manda los transitorios a `consulta_calidad`
  y los permanentes a `pendiente_revision_calidad`.

### Efectos que salen gratis
`estadoRecepcionCompras()` deriva el estado de los documentos, así que al
revertir, la recepción sale sola de "histórico" y vuelve a "pendiente" o
"rechazada". No hubo que tocar el estado de la recepción a mano.

### Pendiente
- **Fichas técnicas: no incluidas.** `FichaTecnicaDoc.fromMap` reconstruye
  `documentoAprobado` recorriendo `historial` en busca de
  `estadoCalidadFinal == 'aprobado'`. Nulear el campo no alcanza: el historial
  resucita la aprobación. Requiere decidir cómo marcar esa entrada del historial.
  Además, revertir una ficha **bloquea crear recepciones nuevas** de ese producto
  y marca (`fichaAprobadaParaRecepcion` la exige aprobada).
- Revertir **no reabre** la tarea de corrección que `aprobarDocRecepcion` cerró
  vía `_finalizarTareasCorreccionAprobadas`. En la rama "rechazar" se crea una
  tarea nueva, así que el caso queda cubierto; en "volver a revisión" no se creó
  ninguna. Confirmar si hace falta.

### Validación
- `flutter test`: **102 pruebas aprobadas** (12 nuevas).
- `flutter build web --release --no-tree-shake-icons --no-wasm-dry-run`: correcto.
- `flutter analyze lib/compras/`: sin errores (quedan infos/warnings previos del proyecto).
- Sin commit: el cierre de Git corresponde a Codex.

### Segunda entrega — el botón, en el sitio donde se ve el documento
La pestaña "Aprobados" servía para buscar, pero obligaba a salir del expediente.
Ahora la reversión también está **en línea, en cada documento**.

| Archivo | Cambio |
|---|---|
| `compras_dashboard_screen.dart` · `_DocAttachButton` | Nuevo callback opcional `onRevertir` y `_buildRevertirAprobacion()`. El enlace "Revertir aprobación" solo se dibuja si el documento está aprobado **y** el callback existe. Va en los dos layouts (móvil y web). |
| `compras_dashboard_screen.dart` · `_ProveedorFormScreen` | Nuevo `esAdmin`; método `_revertirAprobacion(key)` que llama al servicio y refresca el estado local sin recargar la pantalla. |
| `compras_dashboard_screen.dart` · cadena de rol | `_esAdmin` → `_ProveedoresScreen` → `_ProveedorFormScreen`. |
| `compras_dashboard_screen.dart` · `abrirDetalleProveedor` | Entrada por notificación: no viene del dashboard, así que resuelve el rol con `svc.resolveRolUsuario` antes de abrir el formulario. |
| `compras_dashboard_screen.dart` · carga de archivo nuevo | El `copyWith` del documento recién subido usa `clearReversion: true`: archivo nuevo, la reversión anterior ya no aplica. |

`_DocAttachButton` es el widget reutilizable de documentos, así que basta con
pasarle `onRevertir` para habilitar la reversión en cualquier otra pantalla que
lo use.

### Tercera entrega — arreglo visual de Aprobados, scroll + calendario en Vigencias, pestaña Resumen

**1. Aprobados se veía roto (texto vertical, una letra por línea).**
Causa: `_CalidadActionButton` declara `minimumSize: Size.fromHeight(42)` → ancho
infinito. Sus usos existentes lo envuelven en `Expanded`; en `_AprobadoFila` iba
suelto dentro del Row, se comía todo el ancho y aplastaba el `Expanded` del
label a ~0 px. Fix: botón compacto `OutlinedButton.icon` de ancho intrínseco
(comentario en el código para que nadie repita el patrón).

**2. Vigencias documentales no tenía desplazamiento (web ≥800 px).**
`_webTable` solo tenía `SingleChildScrollView` horizontal; las filas bajo el
borde eran inalcanzables. Fix: scroll vertical + horizontal anidados.

**3. Calendario de vigencias** (`_CalendarioVencimientos`, sin paquetes):
mes navegable, días con badge de conteo coloreado (rojo vencido / ámbar ≤30
días / verde posterior), tooltip por día, leyenda. Tocar un día filtra la lista
a esa fecha exacta (chip "Día: dd/MM/yyyy" para limpiar; los ChoiceChips de
rango quedan en pausa mientras hay día elegido). Chip "Calendario" para
mostrar/ocultar: por defecto visible en ≥800 px y oculto en móvil.

**4. Pestaña "Resumen"** — dashboard documental en "Documentos pendientes"
(primera pestaña, visible para Calidad y Admin):
- `_ResumenDocumental.calcular(...)`: agregados puros sobre los streams ya
  existentes (proveedores + recepciones + fichas), sin lecturas extra.
- Revisión de Calidad: por revisar / recepción por consultar / aprobados /
  rechazados, con desglose Prov·Recep·Fichas; cada tarjeta navega a su pestaña
  (Aprobados solo si esAdmin).
- Expediente por completar: documentos faltantes según `ReqEngine.docsProveedor`
  (fallback RUT+Cámara si la empresa no configuró reglas), proveedores
  incompletos y top 6 con el detalle de lo que falta.
- Vigencias: vencidos / ≤30 días / sin fecha registrada + acceso directo a la
  pantalla de vigencias con calendario.
- TabBar pasa a 5/4 pestañas; `isScrollable` bajo 700 px para que quepan en móvil.

Validación: `flutter test` 102 OK, build web OK, deploy hosting OK.

### Cuarta entrega — recepciones visibles, tooltips "cuáles son", marcas y UX de vigencias

**1. Bug real destapado por el Resumen: las recepciones pendientes no se veían
en NINGUNA pestaña.** `_RecepcionCalidadCard` solo se instanciaba con
`consultaTransitorios: true` (pestaña Recepción); los documentos PERMANENTES de
recepción pendientes de aprobación no tenían dónde revisarse — el contador
decía 6 y la pantalla no mostraba ninguno. Fix: nueva sección **"Recepciones en
revisión"** en la pestaña Pendientes, con modo `soloPermanentes: true` en la
tarjeta (los transitorios siguen en su propia pestaña, sin duplicarse).

**2. Tooltips "cuáles son"** (pedido explícito): `_ResumenStatCard` acepta
`tooltip`; `_ResumenDocumental` ahora arma listas de detalle por indicador
(máx. 12 + "… y N más"). Al pasar el mouse (o dejar presionado en móvil) se ve
exactamente qué documentos componen el número: proveedores/fichas/recepciones
por revisar, transitorios, faltantes por proveedor, marcas, vencidos, ≤30 días
y sin fecha.

**3. "Por revisar" separado** en tres tarjetas: Proveedores / Fichas /
Recepciones (antes una sola con desglose en texto).

**4. Marcas: ficha técnica y registro sanitario ("para los 2").** Los
`documentosAsociados` de la marca no pasan por aprobación de Calidad, así que
se reportan como expediente: tarjeta "Marcas por completar" con tooltip que
dice por marca cuál de los dos documentos falta.

**5. Vigencias documentales — UX:**
- Los docs **sin fecha registrada** ahora entran a la pantalla (antes se
  excluían): filtro y métrica "Sin fecha", fila con "—" y pill gris.
- Métricas clicables (aplican su filtro y se resaltan); 4 métricas:
  Vencidos / Próximos 30 / Sin fecha / Todos.
- En pantallas ≥1100 px el calendario pasa al costado derecho de la tabla
  (antes quedaba centrado con espacio muerto y empujaba la tabla).
- Estado de la tabla como pill de color en lugar de texto plano.
- `_VencimientosScreen` acepta `filtroInicial`: las tarjetas de vigencias del
  Resumen abren la pantalla ya filtrada (vencidos / 30 / sin_fecha).

Validación: analyzer 0 errores, `flutter test` 102 OK, build web OK, deploy OK.

### Quinta entrega — compromisos del acta del 29/07/2026

Acta: `La reunión se inició a las 2026_07_29 14_01 GMT-05_00 - Notas de Gemini.docx`
(Daniel Nova / Oscar Cano). Tareas asignadas a Daniel:

| Compromiso | Estado |
|---|---|
| Renombrar "Recepciones pendientes" → "Recepciones" | HECHO |
| Filtros de fecha en histórico y rechazadas (evitar sobrecarga) | HECHO |
| Indicador visual de ficha técnica en Nueva Recepción | HECHO |
| Automatización WhatsApp | PENDIENTE (infra Cloudflare/OpenWap, fuera del código Flutter) |

**1. Renombrado.** Tarjeta del dashboard: 'Recepciones pendientes' →
'Recepciones'. Las pestañas Pendientes / Histórico / Rechazadas ya existían
dentro, que era lo que Oscar pedía aclarar.

**2. Filtros de fecha — acotado REAL en servidor.** Oscar pidió evitar la
sobrecarga de datos, no solo filtrar visualmente:
- `ComprasService.streamRecepcionesPorRango(empresaId, desde, hasta)`: consulta
  con rango sobre `fecha`, resuelta por Firestore.
- `firestore.indexes.json`: nuevo índice compuesto
  `TBL_COMPRAS_RECEPCIONES (empresaId ASC, fecha DESC)`. **Desplegado** con
  `firebase deploy --only firestore:indexes` ANTES del hosting.
- `_RecepcionesScreen`: barra de rango en Histórico y Rechazadas, con atajos
  30/60/90/180 días y 1 año, y selector de rango libre. Por defecto 60 días.
- **Pendientes NO se acota**: esconder trabajo por hacer detrás de un filtro de
  fechas sería peor que el costo de traerlo completo.
- Stream memoizada por rango (`_rangoStream`) — recrear `.snapshots()` en cada
  build provoca "INTERNAL ASSERTION FAILED" en web.

**3. Indicador de ficha técnica.** El acta decía que el sistema "no indica
claramente si el producto cuenta con la ficha técnica". Causa exacta: en
`_ProductoEntryCard`, cuando no había ficha por ninguna fuente (colección nueva
ni legacy del producto), el bloque hacía `return const SizedBox.shrink()` — no
se pintaba NADA, y la ausencia del badge era indistinguible de "no revisado".
Ahora se muestra una advertencia ámbar "Sin ficha" diciendo que ese producto no
tiene ficha técnica para el proveedor y marca seleccionados.

**Sin cambios (decisiones del acta de NO tocar):**
- Vigencia documental: se mantiene la configuración actual.
- Recepción abierta aunque la documentación esté en revisión: no se bloquea el
  flujo operativo (se aplicarán restricciones cuando el software esté en pleno
  funcionamiento).
- Ficha ya aprobada no requiere nueva validación al cargarse en recepción: ya
  estaba implementado en `_sincronizarFichaAprobada` + `fichaAprobadaParaRecepcion`.

Validación: analyzer 0 errores, `flutter test` 102 OK, build web OK,
índices desplegados, hosting desplegado.

### Pendiente de esta segunda entrega
- **Recepciones**: la reversión en línea todavía no está en el detalle de la
  recepción; ahí sigue siendo por la pestaña "Aprobados".
- **Marcas** (`kDocumentosAsociadosLabels`, fichas y registros sanitarios):
  usan `_DocAttachButton` pero aún no reciben `onRevertir`.
- Fichas técnicas siguen fuera por lo del `historial` descrito arriba.

---

## Sesión 2026-06-25 — Conveniencias de inicio de sesión (recordar / mantener / biometría)

### Objetivo
Evitar tener que escribir usuario+clave en cada arranque. Tres niveles:
**recordar usuario**, **mantener sesión iniciada** y **ingreso con huella / Face ID**.

### Contexto técnico
El login **no usa Firebase Auth**: lee `TBL_USUARIOS` y compara la contraseña
(texto plano). La "sesión" es solo `docId` + `empresaId` que recibe `HomeScreen`.
Por eso **no se guarda la contraseña** en el dispositivo: se persiste solo la
identidad y al reanudar se **revalida contra Firestore**.

### Cambios
| Archivo | Cambio |
|---|---|
| `lib/services/auth_prefs.dart` *(nuevo)* | Capa única: recordar usuario (SharedPreferences), mantener sesión + biometría (flags), identidad de sesión cifrada (`flutter_secure_storage`) y prompt biométrico (`local_auth`). Todo `local_auth` va detrás de `if (kIsWeb) return false`. |
| `lib/login/auth_gate.dart` *(nuevo)* | Pantalla de arranque (reemplaza a LoginScreen como `home:`). Decide: login / reanudar directo / pedir biometría y reanudar. Al reanudar revalida usuario (`estado=='activo'`), empresa (`reconcileForUserData`) y `needsPasswordChange`. |
| `lib/main.dart` | `home: const AuthGate()`. |
| `lib/login/login_screen.dart` | Precarga del último usuario, checks **"Recordar usuario"** y **"Mantener sesión iniciada"**, guardado de preferencias y diálogo opt-in de biometría (solo móvil con hardware enrolado). |
| `lib/home/app_drawer.dart` | `_logout()` llama `AuthPrefs.clearSession()` (borra sesión + apaga auto-ingreso; conserva "recordar usuario"). |
| `pubspec.yaml` | `local_auth: ^2.3.0`, `flutter_secure_storage: ^9.2.4`. |
| `android/.../MainActivity.kt` | `FlutterActivity` → `FlutterFragmentActivity` (requisito de `local_auth`). |
| `android/.../AndroidManifest.xml` | Permiso `USE_BIOMETRIC`. |
| `ios/Runner/Info.plist` | `NSFaceIDUsageDescription`. |
| `test/widget_test.dart` | Smoke test adaptado al AuthGate (mock de SharedPreferences + secure storage). |

### Web vs Móvil
- **Móvil:** huella / Face ID (`local_auth` + Keystore/Keychain).
- **Web:** solo recordar usuario + mantener sesión; biometría deshabilitada por `kIsWeb`.
- **Compartido:** validación de empresa/rol/identidad sin cambios; solo se añade la capa de arranque.

### Pendiente / nota de seguridad
La biometría mejora la *comodidad*, no el modelo de fondo: las contraseñas
siguen en texto plano y sin Firebase Auth. Endurecer = migrar a Firebase Auth real.

---

## Sesión 2026-06-20 — Cargos por área en "Crear tarea" + diagnóstico de salud

### Problema
Al filtrar un área en **Crear tarea** (p. ej. Talento Humano), el desplegable
**Cargo** mostraba cargos de otras áreas (Conductor, Director de Compras,
Supervisor De HSE, etc.). El organigrama sí salía bien porque lee
`TBL_ESTRUCTURA_ORGANIZACIONAL`.

### Causa raíz (inconsistencia de datos)
- El **seeder** escribe cada cargo de `TBL_CARGOS` con `areaId`.
- La pantalla **Gestión de Cargos** guardaba solo `area` (el **nombre**), sin
  `areaId`.
- `create_task_screen._loadCargos()` leía solo `areaId`/`area_id` → vacío.
- `mergeTaskCargoCatalog` trataba `areaId` vacío como **comodín**, así que esos
  cargos aparecían en **todas** las áreas.

### Cambios
| Archivo | Cambio |
|---|---|
| `lib/core/task_assignment_options.dart` | El merge ahora exige coincidencia de área **por `areaId` o por nombre normalizado** (acentos/mayúsculas/espacios). Un cargo sin área ya **no** es comodín → se excluye. |
| `lib/home/create_task_screen.dart` | `_loadCargos()` conserva `areaNombre`; `_cargosFiltrados` pasa el nombre del área activa al merge. |
| `lib/talento_humano/cargos_management_screen.dart` | Al crear/editar un cargo se persiste `areaId`+`areaNombre` (resueltos desde `TBL_AREAS`). `_updateAllCargos()` ("Sincronizar Estructura") ahora **rellena el `areaId` faltante** de cargos viejos. |
| `lib/admin/admin_dashboard_screen.dart` | Nueva pestaña **"Salud cargos"** (solo lectura) que detecta: sin `areaId`, área inexistente, `areaId`↔nombre desfasado, sin área. Incluye **reparación** por fila y en lote (resuelve `areaId` por nombre). |
| `test/core/task_assignment_options_test.dart` | 5 casos, incl. el escenario del bug (Conductor/Director de Compras no deben salir bajo Talento Humano). |

### Cómo dejar los datos consistentes
Sin migración obligatoria (el fix de lectura ya empareja por nombre). Para
limpiar el catálogo: Admin → **Salud cargos** → *Reparar areaId*, o en
**Gestión de Cargos** → *Sincronizar Estructura*.

---

## Sesión 2026-06-11 — Identidad visual de usuarios (nombre + foto en toda la app)

### Problema
En varios módulos los usuarios aparecían como cédula en labels y como una
letra inicial en los avatares, aunque `TBL_USUARIOS` tiene `nombres`,
`apellidos` y `fotoUrl`.

### Infraestructura nueva (compartida Web + Móvil)
| Archivo | Qué hace |
|---|---|
| `lib/core/user_directory.dart` | `UserDirectory`: caché en memoria por sesión que resuelve cédula → nombre completo, fotoUrl y cargo. Lee `TBL_USUARIOS` (por docId, luego por campo `cedula`) con fallback a `TBL_ESTRUCTURA_ORGANIZACIONAL`. Cada usuario se lee de Firestore **una sola vez** por sesión sin importar cuántas tarjetas lo muestren. Incluye `warm()` para pre-carga en lote (chunks de 10 por límite de `whereIn`). |
| `lib/widgets/user_avatar.dart` | `UserAvatar`: avatar circular con prioridad foto → iniciales del nombre → ícono de persona (nunca el dígito de la cédula). `UserNameText`: texto que muestra el nombre real resuelto; si solo se conoce la cédula la reemplaza al resolver. Ambos aceptan hints (`nameHint`, `fotoUrlHint`, `fallbackName`) para no esperar la red cuando el dato ya se conoce. |

### Pantallas actualizadas
| Pantalla | Cambio |
|---|---|
| `lib/home/notifications_screen.dart` | Comentarios: avatar de letra → `UserAvatar` con foto; nombre del comentarista resuelto por cédula. Tarjeta de notificación: "Asignado por / Reportado por" ahora resuelve el nombre real cuando solo llega `fromId` (cédula). |
| `lib/home/team_screen.dart` | Árbol organizacional: avatar de letra → `UserAvatar` con foto; nombre del nodo resuelto si el campo viene vacío. |
| `lib/home/assigned_tasks_screen.dart` | Chip "Asigna:" del detalle de tarea resuelve nombre real del creador (antes podía mostrar cédula). Strip de urgencia pasa `assigneeId` para resolución. `_MetaChip` extendido con resolución de usuario opcional (compatible con usos existentes). |
| `lib/home/created_tasks_screen.dart` | "Asignada a:" en el bottom sheet resuelve nombre por `asignado_uid`. Strip de urgencia separa nombre/cédula para resolución correcta. |
| `lib/widgets/task_urgency_strip.dart` | `TaskUrgencyItem` acepta `assigneeId` y renderiza con `UserNameText`. |
| `lib/talento_humano/areas_management_screen.dart` | Diálogo "Personal en área": avatar de letra → `UserAvatar` con foto; nombre resuelto. |
| `lib/talento_humano/cargos_management_screen.dart` | Diálogo "Ocupantes del cargo": ídem. |
| `lib/talento_humano/organizational_structure_screen.dart` | Tarjeta de empleado: avatar (foto/iniciales) unificado en `UserAvatar`; eliminado `_InitialsAvatar` duplicado; el label "Cédula: X" ahora muestra el nombre resuelto. |
| `lib/talento_humano/hv_dashboard_screen.dart` | `_PersonTile`: si la HV no trae foto, se resuelve por cédula desde `TBL_USUARIOS`. |
| `lib/talento_humano/zeus_export_screen.dart` | Lista de pendientes y `_ZeusAvatar`: avatar de letra → `UserAvatar` con foto resuelta por cédula; nombre resuelto cuando falta. |
| `lib/widgets/task_modern_card.dart` | Tarjeta de tarea (Web+Móvil): nueva fila con avatar (foto) + nombre del responsable (asignado, o creador como fallback) en la barra inferior. |

### Decisiones de arquitectura
- **Compartido Web/Móvil**: la resolución (UserDirectory) y los widgets son
  100 % compartidos; no hay lógica de plataforma.
- **Costo Firestore controlado**: caché por sesión + dedup de lecturas en
  vuelo; el fallback a estructura organizacional solo se consulta si el
  usuario no tiene nombre o foto en `TBL_USUARIOS`.
- **Sin tocar reglas de Firebase** ni estructura de datos: solo lectura.
- **Compatibilidad**: todos los widgets aceptan los nombres ya denormalizados
  en las tareas (`creador_nombre`, `asignado_nombre`) y solo van a la red
  cuando el dato falta o es una cédula.

### Verificación
- `flutter analyze`: sin errores nuevos (solo infos/warnings preexistentes
  del proyecto: `withOpacity` deprecado, elementos sin uso en módulos no
  tocados).
- `flutter build web --no-tree-shake-icons --no-wasm-dry-run`: exitoso.
- Verificación visual en navegador (login con perfil desarrollador):
  - Login y selector multi-empresa OK.
  - Home Web: 8 módulos enlazados; drawer con foto + nombre + cargo.
  - Mis Tareas (Web y Móvil 375px): tarjetas con avatar+nombre sin
    overflow; strip de urgencia con nombres reales de creadores;
    bottom sheet con "Asigna: <nombre real>".
  - Notificaciones: "De: <nombre real>" resuelto.
  - Mi equipo: 121 personas con nombre completo e iniciales dobles
    (foto cuando existe en TBL_USUARIOS).
  - Consola del navegador sin errores.

### Enlaces entre módulos (verificado)
Los 8 módulos están correctamente enlazados desde Home con `AccessGuard` y
empresa activa consistente: Administración, Talento Humano, Gerencia,
Gestión Documental, Nutrición, Compras, Interventoría y Facturación
(`lib/home/home_screen.dart` → `_getModuleWidgets`). Compras, Interventoría
y Facturación resuelven además el rol del usuario antes de abrir.

---

## Sesión 2026-06-11 (ronda 2) — Barrido completo de TODOS los módulos

Revisión módulo por módulo aplicando `UserAvatar`/`UserNameText` donde
faltaba, tras observación del usuario de que Admin y otros módulos no
estaban cubiertos.

| Módulo | Cambio |
|---|---|
| **Admin** (`admin_dashboard_screen.dart`) | Tarjetas de usuarios: ícono genérico → foto + nombre resuelto. Listas "Roles asignados" (Compras e Interventoría): ícono de rol → foto del usuario + nombre resuelto. Filas de asignación de roles (×2): avatar añadido + nombre resuelto. |
| **Admin** (`users_management_screen.dart`) | Lista de usuarios: ícono → `UserAvatar` con foto; nombre resuelto (maneja nombres con campos `nombres/apellidos` además de `primerNombre/primerApellido`). |
| **Gerencia** (`gerencia_dashboard_screen.dart`) | Header del gerente: ícono premium → foto del usuario. (El ranking ya resolvía nombres). |
| **Facturación** (`facturacion_dashboard_screen.dart`) | Observaciones de documentos: avatar de letra → foto por `autorId`; nombre del autor resuelto. |
| **Interventoría** (`interventoria_service.dart`) | Fix de datos: la notificación "nota del registrador" guardaba `fromName` = cédula; ahora resuelve el nombre real desde TBL_USUARIOS antes de escribir. |
| **Nutrición** (`nutricion_dashboard_screen.dart`) | Avatares de paciente: ícono genérico → iniciales del nombre (pacientes no están en TBL_USUARIOS; sin lecturas extra). El catálogo de pacientes ya manejaba foto+iniciales. |
| **Panel de equipo** (`team_overview_screen.dart`) | Pills "Asignado"/"Asignado por" y detalle: resuelven nombre real por cédula (antes podía mostrar cédula cruda). |
| **Historial** (`task_history_screen.dart`) | Entradas de avances/novedades/finalización: autor resuelto por `byId`/`createdBy`. |
| **TH – HV Management** (`hoja_de_vida_management_screen.dart`) | Lista de hojas de vida: si la HV no trae foto, se resuelve desde TBL_USUARIOS. |
| **TH – HV Dashboard** (`hv_dashboard_screen.dart`) | Cumpleaños del calendario: ícono de torta → foto/iniciales de la persona (se añadió `cedula` a `_CumpleData`). |
| **TH – Notificaciones** (`notificaciones_talento_humano_screen.dart`) | Buscador de empleados: ícono → foto + nombre resuelto. |
| **GD – Planillas** (`pp_planilla_detail_screen.dart`) | Trazabilidad ("Cargado/Revisado/Firmado por") y observaciones: nombre real resuelto cuando solo hay cédula (`_userInfoRow` nuevo). |

Revisados sin cambios necesarios: Compras (avatares son de productos; no
muestra usuarios en UI), GD dashboard (no muestra usuarios),
`create_task_screen` (selector ya resuelve nombres), catálogo de pacientes
de Nutrición (ya tenía foto+iniciales), login (avatares decorativos/logo).

### Verificación (ronda 2)
- `flutter analyze`: sin errores; solo warnings preexistentes.
- `flutter build web`: exitoso (151s).
- Visual en navegador con perfil desarrollador: Panel de Administración →
  Gestión de Usuarios muestra avatares con iniciales dobles/foto y nombre
  completo + cédula como subtítulo (antes: ícono genérico). Sin errores de
  consola en la sesión verificada.

---

## Sesión 2026-06-12 — Centro de notificaciones ÚNICO (todos los módulos)

### Objetivo
Garantizar que toda notificación de cualquier módulo llegue al centro de
notificaciones único (campana del Home, `NotificationsScreen` →
`TBL_NOTIFICACIONES/{cedula}/notifications`) y eliminar sistemas internos
por módulo.

### Auditoría (cómo notifica cada módulo)
| Módulo | Método | Llega al centro |
|---|---|---|
| Tareas (crear/avance/novedad/finalizar/reasignar) | `TaskService.pushNotification(ToMany)` | ✓ |
| Facturación | `pushNotification(ToMany)` | ✓ |
| Gestión Documental | `pushNotification` | ✓ |
| Planillas | `pushNotification` | ✓ |
| Hojas de Vida (TH) | `pushNotificationToMany` | ✓ |
| Interventoría | escritura directa a `TBL_NOTIFICACIONES` | ✓ |
| Citas Nutrición | escritura directa | ✓ |
| Talento Humano (banners) | escritura directa (batch) | ✓ |
| Compras | **antes**: doble (interno + global) → **ahora**: solo global | ✓ |
| Admin | solo lee/borra (herramienta de limpieza) | N/A |

Contrato del centro confirmado: subcolección `notifications`, orden por
`createdAt` (Timestamp), campos `title/description/type/taskId/fromId/fromName/read/empresaId`.
Trigger FCM (`functions` `TBL_NOTIFICACIONES/{userId}/notifications/{notifId}`)
dispara push para TODOS los módulos. Todos los callers pasan `empresaId`
(necesario porque el centro oculta notifs sin empresa cuando hay empresa activa).

### Cambios ejecutados
1. **Fix de orden en la campana** — `createdAt` pasaba con `FieldValue.serverTimestamp()`
   en 2 servicios (`compras_service._crearNotificacionGlobalCompras`,
   `citas_nutricion_service`). Con serverTimestamp el doc aparece local con
   `createdAt=null` un instante y se desordena/parpadea en la campana y el
   badge. Cambiado a `Timestamp.now()` (igual que el método canónico).
2. **Compras unificado a un solo centro** (decisión del usuario "solo centro global"):
   - `streamNotificaciones` ahora lee del centro global filtrando client-side
     por `module == 'compras_bodega'` y `read == false` (sin índices nuevos →
     no se tocan reglas Firebase).
   - `marcarNotificacionLeida(userId, id)` y `marcarTodasLeidas` operan sobre
     el centro global (`read: true`).
   - `_crearNotificacionGlobalCompras` ahora embebe los campos ricos
     (`userId`, `recepcionId`, `productoNombre`, `docKey`, `docLabel`, `motivo`)
     para que la campana de Compras conserve su UI detallada.
   - Eliminadas las 3 escrituras a `TBL_COMPRAS_NOTIFICACIONES` (recepción,
     proveedor, ficha técnica). Ya no existe colección interna paralela.
   - `NotificacionComprasDoc.fromMap` lee `read` (con fallback a `leida`).

### Verificación
- `flutter analyze`: SIN ERRORES (842 issues = warnings/infos preexistentes).
- `flutter build web`: (en curso al cierre de esta entrada).
- Nota de comportamiento: las notifs internas viejas en `TBL_COMPRAS_NOTIFICACIONES`
  quedan huérfanas (ya no se leen); las nuevas van al centro. No se borran
  datos existentes.

### Pendiente / próximas mejoras sugeridas
- [ ] Unificar `kArial` duplicado en múltiples archivos hacia un solo
      `lib/theme/`.
- [ ] Limpiar código muerto señalado por `flutter analyze` (elementos sin
      uso en admin/compras/gerencia, preexistente).
- [ ] `notification_service.dart` tiene código muerto conocido
      (`userNotificationsStream()`/`markAsRead()` con estructura errónea) —
      candidato a eliminación.

---

## Sesión 2026-06-14 — Módulo RUTAS (logística + evidencia georreferenciada)

Nuevo módulo adaptado del proyecto externo "FYC Rutas", integrado al patrón
multiempresa/roles del proyecto. Rutas = solo direcciones; el personal
(conductor/ayudante) se asigna como usuarios. Menú automático por ciclo de 21
días; tiempo de comida por ventana horaria; evidencia por punto+comida con
secuencia obligatoria desayuno→almuerzo→cena; revisión con aprobación.

### Archivos nuevos
| Archivo | Qué hace |
|---|---|
| `lib/rutas/rutas_models.dart` | Modelos + constantes: `RutaDoc`/`RutaStop`, `RutaAsignacionDoc` (histórico de personal), `RutaConfigDoc` (ciclo de menú + ventanas + radio), `RutaEvidenciaDoc` (foto por ruta/fecha/parada/comida + estado), `RutaResumenDiarioDoc`, `RutaRolDoc`. `createdAt` con Timestamp de cliente. |
| `lib/rutas/rutas_logic.dart` | Lógica PURA (testeable, sin Firebase): menú por ciclo de 21 días, comida por hora, distancia Haversine, stop más cercano, secuencia de comidas, docId/storagePath determinísticos. |
| `lib/rutas/rutas_service.dart` | Firestore + Storage: CRUD rutas, asignaciones con histórico (batch), config, evidencias (subida ATÓMICA — no fire-and-forget como FYC), aprobar/rechazar (+ notificación al conductor por el centro único), roles (`getRolUsuario`), resumen por rango. Queries solo por igualdad + orden en cliente (sin índices compuestos). |
| `lib/rutas/rutas_dashboard_screen.dart` | Enrutador por rol (admin/calidad/conductor) + consola Admin web: pestañas Rutas (CRUD + geocodificación persistida), Asignaciones (personal por ruta + histórico), Roles, Configuración (ciclo de menú + ventanas + radio). |

### Colecciones Firestore (todas con `empresaId`)
`TBL_RUTAS`, `TBL_RUTAS_ASIGNACIONES`, `TBL_RUTAS_CONFIG` (docId=empresaId),
`TBL_RUTAS_EVIDENCIAS`, `TBL_RUTAS_RESUMEN_DIARIO`, `TBL_RUTAS_ROLES`
(docId=`{empresaId}_{userId}`).

### Registro del módulo
- `lib/utils/user_company.dart`: `'rutas' → 'rutasdashboard'` en el mapa de IDs.
- `lib/home/home_screen.dart`: import, `_abrirRutas(...)` y `ModuleCard` "Rutas".
- Falta crear el registro en `TBL_APPS` (`{empresaId}_rutasdashboard`) desde el
  AdminDashboard para que la tarjeta sea visible a no-desarrolladores.

### Estado
- Fases 1–5 COMPLETAS y compilando (fundación, consola Admin, conductor móvil,
  calidad/revisión, Cloud Functions). Módulo funcionalmente terminado.
- Reglas Firestore: por decisión del usuario quedan ABIERTAS durante desarrollo.
- Pendiente operativo: registrar `{empresaId}_rutasdashboard` en TBL_APPS;
  `cd functions && npm run build && firebase deploy --only functions` para
  publicar las 3 Cloud Functions.

### Reparto Web/Móvil (decisión del usuario)
- admin, calidad y desarrollador → web + móvil (pantallas responsive).
- conductor → SOLO móvil (cámara + GPS). En web el módulo muestra "usa la app
  móvil" (gate `kIsWeb` en el enrutador de `rutas_dashboard_screen.dart`).

### Fase 4 — Calidad (web + móvil)
- `_CalidadHome` en `rutas_dashboard_screen.dart`: filtros server-side por
  igualdad (fecha "Hoy"/fecha exacta/todas, estado, comida, ruta) sin índices
  compuestos; grilla responsive (2–6 columnas según ancho) con miniaturas;
  visor con metadatos (incl. distancia y aviso "fuera de rango" según el radio
  configurado) y botones Aprobar / Rechazar (el rechazo pide motivo y notifica
  al conductor por el centro único). Botones Informe (PDF diario/semanal/
  mensual) y ZIP que invocan las Cloud Functions.

### Fase 5 — Cloud Functions (`functions/src/rutas.ts`, exportadas en index.ts)
| Función | Tipo | Qué hace |
|---|---|---|
| `rutasResumenEvidencia` | trigger onWrite en `TBL_RUTAS_EVIDENCIAS` | Recalcula `TBL_RUTAS_RESUMEN_DIARIO/{empresaId_fecha_rutaId}`: puntos completos, aprobadas/rechazadas/pendientes, primera/última entrega, duración, distancia promedio. |
| `rutasGenerarInforme` | callable (us-central1) | PDF con `pdf-lib` (sin fotos) por rango de fechas; lo sube a Storage y devuelve enlace con token. |
| `rutasGenerarZip` | callable (us-central1) | Empaqueta las fotos filtradas con `jszip` en carpetas RUTA/PUNTO/COMIDA; sube el .zip y devuelve enlace + total. |
- Dependencia nueva: `jszip` en `functions/package.json`.
- Verificación: `npm run build` (tsc) SIN ERRORES.

### Fase 3 — Conductor (móvil), archivos nuevos
| Archivo | Qué hace |
|---|---|
| `lib/rutas/rutas_watermark.dart` | Genera la evidencia con banda inferior de datos (SIN mapa) usando dart:ui; re-codifica a JPEG (mucho más liviano que el PNG de FYC) y produce miniatura con el paquete `image`. |
| `lib/rutas/rutas_conductor_screen.dart` | `ConductorHomeScreen`: pensada para usuarios poco técnicos. SIN MAPA. Autodetecta ruta del día (asignación vigente), punto más cercano por GPS y comida por hora; botón grande "TOMAR FOTO" directo a la cámara; secuencia por punto (desayuno→almuerzo→cena con candado); galería de fotos de hoy con previsualizar/repetir y estado (pendiente/aprobada/rechazada). |
- Decisión UX del usuario: el mapa confundía a los conductores → se eliminó el
  mapa por completo (en pantalla y en la marca de agua).

### Asignación de roles desde el Admin Dashboard
Por consistencia con Compras/Interventoría/Facturación, los roles de Rutas se
asignan desde `admin_dashboard_screen.dart` (nueva pestaña "Roles Rutas":
agregada a `_kAdminModuleTabs`, `_allTabItems()`, `_allTabs()` y método
`_tabRolesRutas()`). Se quitó la pestaña Roles de la consola del módulo (ahora
3 pestañas: Rutas, Asignaciones, Configuración).

### Verificación
- `flutter analyze lib/rutas/`: SIN ERRORES (infos de estilo preexistentes en
  el proyecto: `withOpacity`, `activeColor`, `onReorder`, `_`).
- `flutter analyze lib/admin/admin_dashboard_screen.dart`: SIN ERRORES nuevos
  (issues = warnings/infos preexistentes del archivo).

### Fix — Rutas de 1 establecimiento no aparecían en Asignaciones
Síntoma: al editar una ruta y dejarla con un solo establecimiento (ej. "Ruta 2"),
la ruta seguía visible y activa en la pestaña Rutas, pero desaparecía de
Asignaciones sin ningún aviso.

Causa: filtros inconsistentes sobre `stops`.
- Editor de ruta (`_guardar`): exige `stops.isNotEmpty` (≥ 1).
- Pestaña Rutas / Combinar rutas: filtra `activa && stops.isNotEmpty`.
- Pestaña Asignaciones: filtraba `activa && stops.length > 1` → excluía las de 1.
- Calidad › Asignaciones: mismo `stops.length > 1`.

Cambios en `lib/rutas/rutas_dashboard_screen.dart`:
- `_AsignacionesTabState.build`: `stops.length > 1` → `stops.isNotEmpty`, y el
  texto vacío ahora dice "al menos un establecimiento".
- `_CalidadAsignacionesViewState._rutasVisibles`: `stops.length > 1` →
  `stops.isNotEmpty`.

No es un problema de rutas nuevas: cualquier ruta (nueva o vieja) con 0 stops o
inactiva sigue sin listarse; con 1 o más ya aparece para asignar.
Nota: `desactivarRutasDeUnEstablecimiento` en `rutas_service.dart` (importación
inicial) sí desactiva a propósito las rutas de 1 establecimiento; eso es la
migración a Establecimientos, no este filtro de UI.

Verificación: `flutter analyze lib/rutas` → 38 issues, todos info preexistentes
(`withOpacity`, `activeColor`, `onReorder`, `_`). Sin errores ni warnings.

### Personal: Talento Humano ↔ TBL_USUARIOS ↔ Rutas
Tres huecos que hacían que una persona dada de alta (o retirada) en Talento
Humano no se reflejara en el resto de la app.

**1. TH no creaba el usuario** (`talento_humano/organizational_structure_screen.dart`)
El formulario de estructura organizacional escribía en
`TBL_ESTRUCTURA_ORGANIZACIONAL` y `TBL_EMPLEADOS`, pero a `TBL_USUARIOS` solo
`if (userSnap.exists)`. Si la persona no tenía doc de usuario, nunca se creaba;
y si existía por otra empresa, jamás se le agregaba el `empresaId` al array
`empresas`. Como Rutas consulta
`TBL_USUARIOS.where('empresas', arrayContains: empresaId)`, esa persona no
aparecía como conductor/ayudante (ni en Crear tarea, ni en directorios).
Ahora se escribe SIEMPRE:
- si el doc existe → `update` con rutas punteadas (`empresasDetalle.{id}.campo`)
  + `arrayUnion` sobre `empresas`, sin pisar otras empresas;
- si no existe → `set` con el mapa `empresasDetalle` ANIDADO (ojo: `set` no
  interpreta los puntos como ruta de campo, `update` sí), `empresas: [empresaId]`,
  `estado: 'activo'` y `needsPasswordChange: true`.
- El doc se crea SIN `password`: la persona ya figura en listas y asignaciones,
  pero el acceso lo habilita Admin al asignar contraseña.

**2. Inhabilitar no quitaba a la persona de ningún lado**
`PersonnelStatusService.changeStatus` escribía
`empresasDetalle.{empresa}.estadoLaboral = 'inactivo'`, pero fuera de TH nadie
leía ese campo. Resultado: un retirado seguía saliendo como candidato y seguía
figurando como conductor de su ruta.
- `personnel_status_service.dart`: al inhabilitar cierra sus asignaciones
  vigentes en `TBL_RUTAS_ASIGNACIONES` (conductor → `activa:false` +
  `vigenteHasta`, la ruta vuelve a Pendiente; ayudante → se limpia solo el
  ayudante y el conductor conserva la ruta). El histórico no se borra.
- `rutas_dashboard_screen.dart`: nuevo `_usuarioActivo()` lee
  `empresasDetalle.{empresa}.estadoLaboral` (con respaldo en el `estado` global)
  y `_UsuarioOpcion.activo` filtra Asignar y Relevo. La tabla además ignora
  asignaciones cuyo conductor esté inhabilitado, para los datos viejos que ya
  quedaron colgados.

**3. Ayudantes con reglas distintas a conductores**
- `esAyudanteDistribucion` exigía "ayudante de distribución" literal → ahora
  basta con que el cargo contenga "ayudante" (los cargos reales varían).
- Ayudantes no respetaban `modoDesarrollador` ni el filtro de activo; ahora
  conductor y ayudante usan el mismo criterio: activo + perfil + libre.
- La lista de usuarios se relee al abrir Asignar/Relevo (antes se cacheaba en
  `initState`, así que un alta de TH no aparecía sin recargar la pantalla).

Resultado: un usuario nuevo con el cargo correspondiente aparece de inmediato
como conductor o ayudante, y un inhabilitado desaparece de la operación.


---

## Carnet imprimible en Talento Humano

Antes solo se podía sacar el QR suelto (una hoja A6 con foto pequeña, nombre y
QR) para pegarlo en un carnet hecho por fuera. Ahora TH imprime el carnet
completo desde la app.

### Qué se agregó

- **`carnet_layout.dart`** — todas las proporciones del carnet en un solo sitio.
- **`carnet_pdf.dart`** — el dibujo del carnet en PDF vectorial. Dos formatos
  (tarjeta CR80 54×86 mm y escarapela 86×120 mm) y dos salidas: hoja carta con
  marcas de corte (9 tarjetas o 4 escarapelas por hoja) o una página por carnet
  para impresora de PVC.
- **`carnet_marca.dart`** — los colores del carnet por empresa, en TBL_EMPRESAS
  (`carnetColorPrimario` / `carnetColorSecundario`). El logo NO se duplica: es
  el `logoUrl` que ya usan notificaciones y planillas.
- **`carnet_preview.dart`** — el mismo carnet dibujado en Flutter, para elegir
  los colores viéndolos sin regenerar un PDF en cada cambio.
- **`carnet_service.dart`** — el padrón de la empresa y el armado de los datos.
- **`carnet_screen.dart`** — la pantalla: diseño + selección múltiple + generar.
  Registrada en el dashboard de TH bajo "Documentación".
- **`foto_carnet*.dart`** — recorte del fondo de la foto con ML Kit en el
  celular, y la captura/corrección que escribe en la hoja de vida.

### Decisiones que no son de gusto

- **Vectorial y no plantilla PNG.** Un PNG habría que rehacerlo cada vez que una
  empresa cambia de color, y a 54 mm impreso se ve borroso si no viene a 640 px
  de ancho. Con el PDF, el color es un parámetro y el tamaño no degrada nada.
- **El QR sigue llevando el token opaco, no la cédula.** Es el mismo de
  `carnet_qr.dart` y la misma página pública (`functions/src/carnet.ts`). El
  carnet impreso NO generó un token nuevo: `asegurarTokenCarnet` reutiliza el
  que ya existe, porque si cada reimpresión rotara el token, el carnet que la
  persona lleva encima quedaría invalidado.
- **La cédula sí va impresa en la tarjeta.** El carnet es un documento que se
  muestra en mano. Lo que no puede llevarla es el QR, que se fotografía y
  circula sin control.
- **Dos unidades de medida.** Los bloques verticales van sobre el alto; las
  letras y el QR, sobre `unidadCarnet`, que NO es el ancho. Medir las letras
  contra el ancho hacía que en la escarapela (más ancha en relación con su
  alto) el contenido no cupiera.
- **El QR tiene un tamaño mínimo.** 0,30 de la unidad son ~16 mm en una CR80.
  Por debajo, cada módulo baja de ~0,36 mm impresos y los teléfonos empiezan a
  fallar. Un carnet cuyo QR no se lee no es un carnet verificable.
- **La cédula y el RH van al lado del QR, no encima.** El modelo de referencia
  es más alargado (proporción 0,59) que una tarjeta CR80 (0,63); apilados, el
  contenido no cabía en el alto. Se usa el hueco que el modelo deja vacío al
  lado del QR.

### Recorte de fondo de la foto

Se hace con ML Kit **en el teléfono**: gratis, sin llamadas de red y sin que la
foto salga del dispositivo para procesarse. Solo funciona en Android e iOS; en
web y escritorio la foto se usa tal cual y la pantalla lo dice.

La foto del carnet **no es una foto aparte**: es la misma `fotoUrl` de la hoja
de vida, para no terminar con dos caras de la misma persona y una de las dos
vieja. Se escribe en la subcolección `hoja_de_vida/datos` y en el documento raíz
de TBL_USUARIOS, que es de donde leen las listas y los avatares.

Dependencia nueva: `google_mlkit_selfie_segmentation: ^0.12.1`.

### Fallo encontrado al revisar el render

La primera versión desbordaba: el contenido no cabía en el alto de la tarjeta y
los arcos decorativos cruzaban por encima del nombre y de la cédula. No lo
detectaba `dart analyze` (el PDF recorta en silencio), así que se agregaron dos
pruebas que sí lo detectan:

- `test/talento_humano/carnet_preview_test.dart` renderiza el carnet y falla si
  hay desborde de layout.
- `test/talento_humano/carnet_pdf_test.dart` comprueba con aritmética que la
  suma de los bloques verticales deja holgura, que el QR no baja del tamaño
  legible y que los arcos no invaden el nombre ni la cédula.

### Pendiente

La negrita del cargo se ve como texto normal: `assets/` solo trae `arial.ttf`
regular. Si se quiere negrita real, poner `assets/arial_bold.ttf`, declararlo en
`pubspec.yaml` y `temaCarnet()` lo toma solo (ya está previsto; si el archivo no
está, cae en la regular sin romper nada).

---

## Interventoría — permisos y responsable por establecimiento (10 sep 2026)

Correcciones de la reunión del 9 sep 2026. Todo dentro de `lib/interventoria/`.

### Los permisos dejaron de ser uno solo

`canWrite` era un permiso único: quien podía escribir en el módulo podía
registrar seguimiento **y** cambiar el responsable de un hallazgo. Son dos
decisiones distintas y ahora son dos permisos distintos:

- `puedeRevisarActas(rol)` → entra a "Por revisar". Admin, Revisor (calidad) y
  Gerente. **Directivo quedó fuera**; conserva Análisis y el histórico, porque
  ver el resultado no es lo mismo que poder cambiarlo.
- `puedeReasignarResponsable(rol)` → mueve al responsable en Subsanaciones.
  Solo Admin y Gerencia. Calidad sigue registrando seguimiento; lo que no hace
  es decidir a quién se le exige el trabajo.

Los dos viven en `interventoria_models.dart`, que es la única fuente. El panel
del hallazgo (`interventoria_hallazgo_panel.dart`) recibe `canReasignar` aparte
de `canWrite` para poder ocultar "Cambiar responsable" sin bloquear el
seguimiento.

`kInterventoriaRolesFase2` desapareció: su único uso era la pestaña "Por
revisar", y dejarlo habría sido tener dos listas de roles diciendo cosas
distintas sobre la misma pantalla.

### Por qué una responsable de Tunja recibía hallazgos de otra sede

Tres defectos encadenados, y cada uno bastaba para producir el síntoma.

**1. La afinidad del cargo pesaba más que el establecimiento.**
`resolverCargo` ordenaba por qué tan bien encajaba el cargo con el de la matriz
y solo usaba el establecimiento para desempatar. Alguien de otra sede con el
cargo "limpio" le ganaba a quien sí trabaja en el establecimiento del hallazgo.
Ahora el establecimiento manda y la afinidad decide después
(`resolverCargoUnico`, función de nivel superior para poder probarla sin
Firebase).

**2. La regla con varios cargos se agotaba sede por sede en el orden
equivocado.** Una regla que lista "Administrador tipo 1" y "tipo 2" existe
precisamente para que cada sede quede cubierta por el que allí exista. Pero se
tomaba el primer cargo que resolviera a **alguien**, en cualquier sede: si la
sede tenía un tipo 2 y en otra sede había un tipo 1, ganaba el de la otra sede.
`resolverPrimerCargoQueResuelva` hace dos pasadas: agota el establecimiento
antes de mirar afuera.

**3. `afinidadCargo` no distinguía tipo 1 de tipo 2.** Al comparar contra un
cargo que no está en la tabla de alternativas, partía el nombre en palabras y
descartaba las de menos de tres letras. El `1` y el `2` —lo único que separa a
los dos administradores— se caían por ese filtro, así que ambos cargos quedaban
reducidos a `{administrador, tipo}` y eran intercambiables. Ahora los números se
conservan aunque tengan un solo carácter. La regla genérica "Administrador"
sigue cubriendo a los dos, que es lo que se espera de ella.

Esto último es lo que hacía imposible el "maestro de responsabilidades por tipo
de administrador" que se pidió: la pantalla ya dejaba escribir la regla —los
cargos salen de `TBL_CARGOS`, no de un catálogo fijo— pero el motor no podía
honrarla.

### La palabra "sugerido" se fue del tablero

No fue un cambio de redacción. Una lista de "sugeridos" que incluía gente de
otras sedes invitaba a aceptarla en bloque, y así es como salían las
asignaciones equivocadas. Ahora:

- La tarjeta solo afirma "Responde: <persona>" cuando esa persona trabaja en el
  establecimiento del hallazgo. No es una sugerencia: es lo que dice el maestro.
- Si nadie de ese establecimiento tiene el cargo, lo dice y pide elegir a mano.
  El responsable de otra sede se puede seguir eligiendo — hay cargos
  corporativos que atienden varias sedes — pero con nombre y apellido, no en
  lote.
- El botón masivo pasó a "Asignar por el maestro (n)" y solo cuenta los
  hallazgos con responsable **en la sede**. Vuelve a comprobarlo justo antes de
  escribir, porque entre el filtro y el clic la lista de usuarios puede cambiar
  y una asignación fuera de sede no se puede colar por una carrera.

### Pruebas

`test/interventoria/interventoria_resolver_cargo_test.dart` — 14 casos que
fijan las tres reglas: el del establecimiento gana aunque su cargo encaje peor,
la regla multi-cargo agota la sede antes de mirar afuera, y tipo 1 / tipo 2 no
se resuelven el uno al otro. Sin ellas los tres defectos vuelven sin ruido:
ninguno rompe la compilación y el síntoma solo se ve semanas después, cuando a
alguien le llega una tarea de una cárcel en la que nunca ha estado.

---

## Facturación — el mes que se pintaba no era el que se filtraba (10 sep 2026)

El acta de la reunión decía que "el aplicativo tomaba el mes del último archivo
subido en lugar del periodo seleccionado". Leída así, el bug estaría en el
conteo. No lo estaba: `_recargarProgreso` siempre usó `_filtroMes`.

Lo que pasaba está en la transcripción, con nombre propio:

> Oscar Cano: Mira que te sale **Tulua 6 de 11 mes de julio**. Todos julio.
> …¿por qué sale mes de julio, Dani?

El "6 de 11" se calculaba para agosto y el "mes: julio" salía de
`establecimiento.mes`, que es el mes **asignado** al establecimiento — el de la
última carga. Dos datos de distinta procedencia pegados en la misma línea. Y la
mitad grave no era la etiqueta: `_abrirDetalle` pasaba ese mismo
`establecimiento.mes`, así que **entrar a una fila filtrada por agosto abría
julio** y ahí sí se subían archivos al mes equivocado.

La corrección no es cambiar la etiqueta por `_filtroMes`. Es que `FacProgresoEst`
ahora lleva el `mes` para el que se calculó. El conteo y su etiqueta salen del
mismo objeto, así que no pueden volver a contradecirse aunque alguien pinte esa
tarjeta en otra pantalla.

### El semáforo estaba escrito tres veces

`prog.completo ? verde : (pct > 0.5 ? naranja : rojo)`, copiado en la tarjeta
del establecimiento y en las dos cabeceras de detalle. Las tres tenían el mismo
defecto: `> 0.5` deja el 50 % exacto en rojo, cuando la instrucción fue rojo por
**debajo** del 50 %.

Ahora es una función, `facNivelCumplimiento`, que devuelve un enum y vive en
`facturacion_models.dart` para poder probarse sin levantar un widget. La
pantalla solo traduce enum a color. El verde queda reservado al 100 %, que era
la instrucción explícita de la reunión.

`requeridos == 0` (todos los documentos ignorados) sigue siendo verde: no hay
deuda que pintar en rojo, y marcarlo incompleto dejaría filas rojas que nadie
puede arreglar.

### El ZIP ya estaba

`_descargarZip` existe desde antes y el botón solo aparece con `_todoCompleto`,
que es literalmente "una vez que todos los documentos sean cargados". No hacía
falta escribir nada. El cambio de Codex en `facDocumentosCompletos` incluso lo
apretó: un establecimiento sin documentos configurados ya no ofrece el ZIP.

---

## Compras — los dos mensajes de la reunión (10 sep 2026)

### "Si yo estoy creando una marca, no me tiene que salir este producto"

El aviso decía: *"Este producto no tiene ficha técnica cargada para el proveedor
y la marca seleccionados"*. Estaba mal en dos cosas distintas, y solo una es de
redacción.

**El sujeto.** Sale justo después de elegir o crear una marca. Quien acaba de
crear algo es la marca, así que la ficha que falta es la de esa marca nueva —
decir "este producto" manda a revisar el producto, que no tiene nada malo.

**La afirmación.** Ese aviso solo aparece cuando no hay ficha por
proveedor+producto+marca, **ni** ficha de la marca, **ni** ficha del producto.
Es decir: no existe en ninguna parte. Nombrar "el proveedor y la marca
seleccionados" como la condición mandaba a buscarla bajo otro proveedor, donde
tampoco iba a estar. El código nunca comprobó lo que el mensaje afirmaba.

Ahora el texto sale de `avisoFichaTecnicaFaltante` en `compras_validation.dart`,
con pruebas, en vez de estar incrustado en un `const Text` a 12.000 líneas de
profundidad.

### El botón de ver la ficha no hacía nada

`_abrirUrl` empezaba así:

```dart
if (url == null || url.isEmpty) return;
final uri = Uri.tryParse(url);
if (uri == null) return;
```

Dos salidas silenciosas. Con un documento sin archivo o con el enlace dañado, el
botón estaba visible, se pulsaba y no ocurría nada: ni se abría, ni avisaba, ni
fallaba. Desde fuera es indistinguible de que la aplicación se haya colgado, y
es exactamente lo que se reportó al ver el detalle de una ficha técnica durante
la entrada de producto.

Ahora los tres caminos que no abren el documento dicen cuál es: no hay archivo
cargado, el enlace está dañado, o el sistema no pudo abrirlo.

**Confirmado el 10 sep con el PDF**, que sí traía el pantallazo: era lo
segundo. El enlace abría una pestaña con el JSON crudo de Google —
`"error": {"code": 404, "message": "Not Found."}`— sobre
`firebasestorage.googleapis.com`.

El enlace vive en Firestore y el archivo en Storage: **borrar el archivo no
invalida el enlace**, así que sigue siendo válido y sigue abriendo. Ahora, antes
de abrir un enlace de Storage, se le pregunta al servidor si el archivo sigue
ahí (`refFromURL(...).getMetadata()`); si no está, se avisa con palabras en vez
de mandar a nadie a leer un JSON de error.

Solo se comprueban los enlaces de Storage: de otro dominio no hay forma de
preguntar, y no se bloquea la apertura por eso.

---

## Archivo plano de pagos — el núcleo (10 sep 2026)

Hoy Tesorería arma este archivo a mano en una macro de Excel. Talento Humano
pasa la información y alguien la transcribe fila por fila; Oscar lo describió
como "una de las cosas que quita mucho tiempo en la empresa".

Lo entregado es **la regla**, no la pantalla: modelo, validación y generación
del texto, en `lib/gestion_documental/planillas/pp_archivo_plano.dart`. No sabe
de Firestore ni de widgets, así que se prueba entero sin levantar nada.

### La especificación salió de la plantilla, no de suponer

El XLSX no es solo un ejemplo de datos: los **comentarios de las celdas** son
las instrucciones del banco, y las validaciones de la hoja son sus límites.

- `Fecha Limite`: "Si la forma de pago es 1 o 2, formato aaaammdd. Si la forma
  de pago es 3, ingrese 8 ceros: 00000000".
- `Concepto 1`: máximo 40 caracteres. `Banco`: código ACH. `Cod Oficina`:
  código de oficina.
- Validaciones de la hoja: nombre y e-mail `LEN <= 36`, identificación
  `LEN <= 15`, tipo de cuenta lista `01,02`.

### Dos decisiones de modelo que no son de estilo

**Los códigos son texto, no números.** En la hoja, `Banco`, `Tipo Cuenta`,
`Forma Pago`, `Dígito V` y `Cod Oficina` están guardados como números con
formato `0000`: el 507 se *ve* como "0507" y el 1 como "0001". El cero de la
izquierda solo existe al pintarlo. Modelado con `int`, el archivo saldría con
"507" y el banco no reconocería la entidad.

Por lo mismo, `rellenarCodigoPlano` nunca recorta un código que llegue más
largo de la cuenta. Recortarlo lo convertiría en otro código válido y el pago se
iría a otra entidad sin que nada fallara. Que salga largo lo detecta la
validación; que salga recortado no lo detecta nadie.

**El importe es un entero de centavos, no un `double`.** Sumar 160 sueldos en
coma flotante deja el total desviado por unos centavos, y el total de la
cabecera es lo primero que revisa el banco.

### La validación devuelve todo y con nombre propio

No se para en el primer error y cada problema lleva la fila, la cédula y el
nombre. Quien corrige esto tiene una lista de 160 personas delante: un mensaje
"identificación demasiado larga" sin decir de quién no sirve para corregir nada,
y parar en el primer fallo obliga a regenerar una vez por cada dato malo.

Casos que se rechazan y que hoy nadie ve: cédulas con puntos, cuentas con
guiones, forma de pago 1 sin fecha (saldría con ocho ceros, que para el banco
significa "sin fecha límite", otra instrucción distinta), y la misma cédula
repetida dos veces en el lote, que casi siempre es una fila pegada dos veces y
son dos transferencias reales.

### Comprobado contra el archivo real

Se generó el lote a partir del archivo que Tesorería ya envió al banco y se
comparó **campo por campo**: las 15 filas, las 18 columnas de cada una y el
total de la cabecera (52.096.549) coinciden. Además, el archivo real pasa la
validación sin un solo error, que es la comprobación de que las reglas no son
más estrictas que la realidad.

Esa comprobación se hizo con un test temporal que leía el archivo de Descargas y
**se borró**: trae cédulas, cuentas bancarias y sueldos de personas concretas.
Las pruebas que quedan en el repositorio usan datos inventados y fijan la forma,
no los datos.

### Lo que falta

- La pantalla en Planillas de Pago para elegir periodo, personas e importes.
- El servicio de lectura/escritura del maestro contra Firestore, y las reglas
  de `firestore.rules` que respalden los permisos por campo.
- El maestro de datos bancarios **ya está modelado** (ver la entrada siguiente).
- ~~Confirmar el formato de salida con el banco.~~ **Confirmado el 10 sep de
  2026: el CSV con comas de miles es el que recibe el banco**, no un artefacto
  de Excel. El generador ya lo reproduce campo por campo —las 15 filas, las 18
  columnas y el total—, así que el formato queda cerrado y
  `conSeparadorDeMiles` se queda en `true`. El interruptor se conserva por si
  algún día cambia el canal, no porque haya duda hoy.

---

## Maestro de datos bancarios del personal (10 sep 2026)

La hoja `CUENTAS` del Excel de Tesorería, convertida en colección
(`TBL_NOMINA_CUENTAS`). Es lo que alimenta al generador del archivo plano.

### Vive aparte de TBL_USUARIOS, y no por gusto

El número de cuenta no puede quedar en el mismo documento que el nombre y la
foto, porque ese documento lo lee media aplicación para pintar avatares.
Separarlo es lo único que permite que la regla de Firestore sea distinta.

### Talento Humano pone el banco; el número es de Tesorería

Es la instrucción recibida, y encaja con cómo trabaja cada área: a Talento
Humano le llega el dato de en qué banco está la persona cuando entra o cuando lo
cambia; el número de cuenta no le hace falta para nada, y un dato que no se
necesita no se muestra.

- `puedeEditarBancoCuenta` → Talento Humano, Tesorería, Admin documental.
- `puedeVerNumeroCuenta` / `puedeEditarNumeroCuenta` → Tesorería y Admin
  documental. Talento Humano queda fuera de las dos.

A quien no le compete, el número le llega **enmascarado, no vacío**
(`•••••7895`). Un campo en blanco y un campo oculto se ven igual, y el primero
lleva a pedirle a la persona un dato que ya está registrado.

Se guarda `numeroActualizadoPor` / `numeroActualizadoEn` aparte del `updatedAt`
general: cambiar el banco y cambiar el número de cuenta no son lo mismo, y al
segundo se le sigue el rastro.

### El código de banco venía escrito de dos formas

En la hoja real hay **21 valores distintos para 14 bancos**: `0013` y `13`,
`0507` y `507`, `0809` y `809`. Unas celdas están guardadas como texto y otras
como número con formato `0000`. Comparar `bancoCodigo == '0013'` deja fuera a
media plantilla del BBVA.

Es el mismo problema que los ids de área, y se resuelve igual: una sola puerta
de entrada (`normalizarCodigoBanco`), aplicada **también al leer de Firestore**,
no solo al escribir — porque un documento que entró por consola o por una
importación vieja trae "13" y tiene que comportarse como los demás.

### Qué se bloquea y qué solo se avisa

La distinción es la parte importante del importador:

- **Bloqueo** (no entra): la misma cédula dos veces. Son dos cuentas para la
  misma persona y nadie sabe cuál es la vigente; quedarse con la primera sería
  decidir a dónde va un sueldo. El archivo real trae cuatro casos.
- **Aviso** (entra y se revisa): dos personas con el mismo número de cuenta.
  Pasa de verdad —una pareja que cobra en la misma cuenta— pero no puede pasar
  desapercibido. El archivo real trae dos.
- **Aviso**, nunca bloqueo: un código de banco que no está en el catálogo. En el
  maestro real hay once personas cobrando en 0507, 0551 y 0809, que el catálogo
  del propio Excel no tiene, y esos pagos llevan meses funcionando. **El
  catálogo está viejo, no los datos.** Bloquear ahí dejaría a once personas sin
  sueldo por un problema de nuestra tabla.

### Comprobado contra el Excel real

Con un test temporal, ya borrado: 176 filas leídas, los 21 códigos de banco
colapsan a los 14 reales, ninguna cuenta se leyó en notación científica, y el
análisis devuelve 172 listas, 4 bloqueos y 2 avisos — los mismos que se cuentan
a mano sobre la hoja.

Lo de la notación científica no es teórico: `toString()` sobre una cuenta de
doce dígitos leída como decimal devuelve `1.1161004988e11`. Por eso el parser
trata cada tipo de celda por separado en vez de confiar en `toString()`.

---

## Tres reportes del 10 sep 2026

### Compras: lo rechazado ya se puede mover

Solo se podía revertir un documento **aprobado**. Uno rechazado se quedaba
rechazado para siempre: la única salida era borrar el archivo y volverlo a
subir, y por el camino se perdía el historial de quién lo había subido y por
qué se rechazó.

Una aprobación y un rechazo son la misma cosa —una decisión de Calidad— y las
dos se pueden haber tomado por error. La regla quedó en
`validarReversionDocumento`: se puede devolver a la cola lo que ya tiene
decisión, y no se puede revertir lo que nadie ha decidido todavía. Se aplica
igual a documentos de proveedor, de recepción y a fichas técnicas, que eran tres
guardas separadas diciendo lo mismo.

**Un documento rechazado vuelve a la cola de revisión; no salta a aprobado.**
Aprobar sin que Calidad lo mire otra vez sería saltarse el control, no arreglar
un error: quien lo devuelve a la cola lo aprueba después por el camino de
siempre.

El diálogo cambia según lo que haya que deshacer: sobre algo rechazado no
ofrece "Rechazar" otra vez ni habla de revertir una aprobación que no existe.

### Bodega: ya estaba corregido, falta publicarlo

El error de la ficha técnica que no dejaba completar la recepción era el campo
"Vigente hasta" obligatorio, que bloqueaba el guardado. Está quitado en el
árbol —`kDocumentosConVigenciaObligatoria` ya no incluye `fichaTecnica`— pero
`pubspec.yaml` sigue en `2.4.6+11`, que es la versión que ya está publicada.

Mientras no se suba la versión, quien esté en la tienda sigue con el error. Y
sin subir el número de versión las tiendas rechazan el envío.

### Facturación: las observaciones se veían de todos los meses

`streamObservaciones` filtraba por empresa y establecimiento y **no por mes**.
Las cuatro pantallas que la usan mostraban las observaciones de todos los
periodos juntas, cada una con su etiqueta "Mes: …". No se estaban creando de
más: se estaban pintando de más. El contador del botón también las sumaba
todas, así que marcaba un número que no correspondía con lo que se abría.

Ahora la consulta acepta `mes` y `docTipo`. Filtran **en memoria** y no en el
`where`: llevarlos a la consulta obligaría a un índice compuesto nuevo y a
desplegarlo antes de que la pantalla funcione, y el número de observaciones de
un establecimiento es pequeño.

Dos detalles que no son obvios:

- La suscripción lleva el mes dentro, así que **se rehace al cambiar de mes**.
  Dejarla fija en `initState` mostraba las del mes con el que se entró aunque
  después se cambiara el filtro.
- Una observación **sin mes** es general del establecimiento y se ve siempre. No
  pertenece a ningún periodo, así que esconderla bajo uno sería perderla.

También se normaliza el mes al escribir la observación: la tarea ya guardaba
`facMes` normalizado y tener las dos formas conviviendo obligaba a comparar con
cuidado en cada lector.

**Queda pendiente** confirmar en qué pantalla buscan la observación del rechazo
("el chat de ese documento" / Mis tareas). El motivo se guarda en la tarea, en
la observación y en el historial de la revisión, así que el dato está.

---

## El chat no se reescribe, se acumula (10 sep 2026)

Cuando se rechazaba **dos veces** el mismo documento y la tarea seguía abierta,
el segundo motivo sobrescribía el `texto` de la observación existente. El primer
motivo desaparecía: el chat mostraba solo el último y no había forma de
reconstruir qué se le pidió al establecimiento ni cuántas veces se le devolvió.

El chat es el registro de lo ocurrido. Un registro que se reescribe no es un
registro.

Ahora cada rechazo crea **una observación nueva**. La anterior se deja intacta
—es un mensaje ya enviado— y solo deja de ser la que la tarea señala: la tarea y
la revisión pasan a apuntar al último mensaje, que es el que hay que atender.

De paso se arregló algo que nadie había reportado todavía: **el segundo rechazo
no notificaba a nadie.** Como la tarea ya existía, no se creaba —y la
notificación salía dentro de la creación—, así que el establecimiento se
enteraba solo si entraba a mirar. Ahora se notifica en los dos caminos.

### Los demás chats ya acumulaban

Se revisaron antes de tocar nada:

- Planillas de pago usa `arrayUnion` sobre el documento.
- Compras lleva un registro aparte de aprobaciones y rechazos
  (`ComprasAprobacion`); lo que se sobrescribe ahí es `observacionCalidad`, que
  es el **estado actual** del documento, no el historial.

## El botón "Aprobar" sobre lo ya aprobado

Seguía saliendo, y no hacía nada útil: volver a aprobar lo aprobado no cambia el
estado y le quitaba el sitio al único botón que sirve ahí. Sobre un documento
aprobado queda solo **Rechazar**, que es la salida si hay que devolverlo.

La condición vive dentro de `_CalidadDecisionButtons`, no en cada sitio que lo
pinta: son cuatro pantallas distintas y una condición repetida cuatro veces está
mal en alguna.

Sobre un documento **rechazado** el botón de aprobar sí se mantiene: revisarlo
otra vez y aprobarlo es la salida normal de un rechazo.

---

## Dónde se ve el motivo de un rechazo (10 sep 2026)

"Que aparezca en todas las partes donde puedan buscarlo, por si se les olvida".
El dato ya se guardaba en cinco sitios; lo que fallaba era que en el sitio
principal era ilegible.

### El motivo en la tarjeta del documento

Se pintaba a **tamaño 9**, recortado a dos líneas con puntos suspensivos, y
solo `if (widget.archivos.isNotEmpty)`. Esa última condición es la peor: se
rechazaba un documento, el establecimiento borraba el archivo malo para subir
otro, y **el motivo desaparecía justo cuando hacía falta leerlo**. De ahí el
"no hay dónde verla".

Ahora es un bloque con su borde, a tamaño 11, hasta cuatro líneas, sin depender
de que haya archivo, y **se toca para abrir el chat completo del documento** —
porque lo que se ve en la tarjeta es el último motivo y el historial está en el
chat. Cuando hay más de un mensaje lo dice ("3 mensajes").

### Los cinco sitios donde queda

1. **La tarjeta del documento**: el último motivo, legible, con el número de
   mensajes.
2. **El chat del documento** (el botón de comentarios de esa misma tarjeta): el
   historial completo, ya acumulado y filtrado por mes y documento.
3. **Observaciones del establecimiento**: todas las del mes.
4. **Mis tareas**: la descripción de la tarea es el motivo, a tamaño 14.
5. **La notificación**, que desde ahora también sale en el segundo rechazo y
   siguientes.

---

## Interventoría — devolver un acta con errores (10 sep 2026)

Lo que se pidió: que calidad pueda rechazar un acta y que eso genere sola la
tarea de corrección para el administrador del establecimiento, quedando el acta
editable desde el histórico.

Ya existía `reabrirActaParaRevision`, pero es otra cosa: es el admin deshaciendo
un clic propio. No pide motivo, no deja constancia y no avisa a nadie. Devolver
un acta es una decisión sobre el trabajo del establecimiento, no un deshacer.

`devolverActaParaCorreccion` hace las tres cosas que van juntas:

1. Regresa el acta a `puntajes`, que es el estado que ya significa "pendiente de
   revisión": reaparece en "Por revisar" y es editable desde el histórico. No se
   inventó un estado nuevo porque el que hacía falta ya existía y todas las
   pantallas saben leerlo.
2. Deja constancia: motivo, quién y cuándo. Y **acumula** en `devoluciones`, no
   sobrescribe: un acta puede volver varias veces y saber cuántas es parte de
   evaluar al establecimiento.
3. Crea la tarea para quien responde por esa sede, resuelta con el mismo motor
   del maestro — así que hereda la corrección de esta mañana y no se la manda a
   alguien de otra ciudad.

### El acta vuelve aunque no haya a quién asignarle la tarea

Si en el establecimiento no hay nadie con el cargo de administrador, la función
devuelve el acta igual y avisa de que la tarea quedó sin dueño. Dejar un acta
mala como buena por un problema de nuestro maestro de personal sería lo peor de
las dos opciones; el aviso dice a la cara que hay que asignarla a mano.

Por lo mismo se exige un motivo de al menos diez caracteres: un acta que vuelve
sin decir qué está mal obliga a adivinar, y lo normal es que la devuelvan igual.

### Quién puede

`puedeRevisarActas`: calidad, gerencia y la administración del módulo. El botón
de devolver **no** está detrás de `esAdminDesarrollo` como el de reabrir,
precisamente porque no son la misma acción.

---

## Interventoría — exportar subsanaciones y la GUI del reporte (10 sep 2026)

### Se exporta lo que se está viendo

El botón descarga `sorted`, la lista **ya filtrada y ordenada**, no todos los
hallazgos. Un archivo que no coincide con lo que había en pantalla obliga a
rehacer el filtro en Excel y a explicarle a quien lo recibe por qué sobran
filas. El botón dice cuántas van a salir.

Las columnas son las mismas de la tabla y en el mismo orden, por lo mismo: si se
separan, quien recibe el archivo no puede cruzarlo con lo que ve el que se lo
mandó.

**Todo sale como texto**, y no es pereza. Los numerales del acta son "1.1",
"1.10", "10.20": si Excel los toma por números, **1.10 se convierte en 1.1** y
deja de existir un numeral. Igual con las fechas, que cambian de formato según
la configuración regional de quien abra el archivo.

Dos cosas que la tabla resuelve con color y el Excel no puede:

- El estado va en palabras ("Subsanado" / "Pendiente de aprobación" /
  "Abierto"). En blanco y negro, tres colores son tres celdas iguales.
- "Sin tarea" se escribe. Una casilla vacía se lee como un dato que faltó
  exportar.

La descarga reutiliza el ayudante que ya existía en Compras, ahora accesible
desde `lib/utils/excel_download.dart`. Duplicar el código de plataforma habría
garantizado que un día se arregle una copia y no la otra.

### Recoger el reporte

En una tablet el gráfico se come la pantalla y la matriz queda en una rendija.
Ahora se pliega. Arranca **desplegado**: lo que hacía falta era poder quitarlo
de en medio, no esconderlo por defecto.

### La ventana flotante del indicador

Tocar una barra salía directamente al histórico del establecimiento. En una
tablet eso es perder el gráfico para leer un dato y tener que volver — y si te
equivocaste de barra, que en pantalla estrecha pasa, el viaje era en balde.

Ahora el detalle se lee **encima del propio gráfico**: establecimiento, código,
el porcentaje con su color, la fecha de la última acta, y el histórico a un
botón.

En esa ventana **"Sin dato" no se pinta como cero**. Un cero es una evaluación
pésima; la ausencia de dato es que esa categoría no se evaluó en la última acta.
Confundirlos en un tablero de indicadores es exactamente el error que hace que
nadie se fíe del tablero.

---

## Interventoría — el perfil Calidad y la matriz de permisos (10 sep 2026)

Antes de esto el módulo tenía cinco roles y las decisiones de la reunión no
cabían en ellos: el único rol con visión completa era Directivo, y Directivo
acababa de perder la revisión. No había forma de dar "ver todo y analizar" sin
dar también "revisar el acta".

Se creó **Calidad** (`calidad_interventoria`), asignable desde el panel de
administración como los demás.

| Rol | Histórico | Por revisar | Subsanaciones | Maestro | Análisis |
|---|---|---|---|---|---|
| Administrador | sí | sí | sí + reasigna | **sí** | sí |
| Registrador | su sede | no | sí | no | no |
| **Revisor** (Kary) | sí | **sí** | sí, sin reasignar | **no** | **no** |
| **Calidad** (nuevo) | sí | **no** | **solo lectura** | no | **sí** |
| Gerente | sí | **sí** | sí + reasigna | **sí** | sí |
| Directivo | sí | **no** | solo lectura | no | sí |

Los tres cambios respecto a lo que había esta mañana:

- **Gerencia entra al Maestro.** El maestro decide quién responde por cada uno
  de los 141 numerales; cambiarlo mueve el trabajo de todo el mundo, y esa es
  una decisión de gerencia tanto como de administración.
- **Kary (Revisor) sale de Análisis.** Ella corrige actas; el análisis es de
  quien mira el desempeño de los establecimientos.
- **Calidad entra a Análisis y no a "Por revisar".** Vigila sin reescribir.

### Por qué la matriz está en pruebas y no solo aquí

`test/interventoria/interventoria_permisos_test.dart` fija las seis filas. Un
permiso que se mueve sin querer **no rompe la compilación**: se descubre cuando
alguien no puede entrar a trabajar, o peor, cuando entra alguien que no debía.

Una prueba anterior afirmaba que el maestro era solo del administrador. Se
actualizó en vez de borrarse: la regla cambió, y el comentario dice cuándo y por
qué.

### Lo que hay que hacer a mano

El código define qué puede cada rol; **quién tiene cada rol es dato**. En el
panel de administración, pestaña Interventoría, hay que revisar:

1. Que Kary esté como **Revisor**.
2. Que quien deba analizar sin revisar quede como **Calidad**.
3. Que nadie más siga como **Directivo** esperando entrar a "Por revisar".

---

## Admin — crear una empresa pidiendo solo el nombre (10 sep 2026)

Ya había un "Crear empresa y trasladar empleados", pero es otra cosa: mueve a
todo el personal y copia centros, áreas, cargos y roles. Para abrir una empresa
nueva y empezar de cero, ese camino obliga a llenar un id a mano y arrastra
datos que no se querían.

**Nueva empresa** pide el nombre y nada más. La empresa nace vacía y quien la
crea queda dentro.

### El código se enseña antes de crear

El id de una empresa es el doc id de `TBL_EMPRESAS` y **viaja concatenado dentro
de otros ids**: `TBL_APPS` usa `{empresaId}_{appId}`, los empleados
`{empresaId}_{cedula}`, y Storage lo mete en las rutas de facturación.
Cambiarlo después no es un `update`, es una migración —el mismo problema que la
cédula—. Por eso el diálogo lo muestra mientras se escribe el nombre: es la
única oportunidad de decir "ese no".

`codigoEmpresaDesdeNombre` pasa a mayúsculas, quita tildes y convierte todo lo
demás en guion bajo. **No intenta ser listo**: no quita "SAS" ni "LTDA" ni
abrevia, porque dos empresas del mismo grupo se distinguen justamente por ese
sufijo.

### Una colisión se detiene, no se arregla sola

Si el código ya existe, no se crea `EMPRESA_2`. Que dos nombres produzcan el
mismo código casi siempre significa que se está creando una empresa **que ya
existe**, y un duplicado silencioso no se nota hasta que la información está
repartida entre las dos. Se avisa con el código concreto y se para.

### Dos decisiones más

- **La membresía se escribe en `TBL_USUARIOS` y en
  `TBL_ESTRUCTURA_ORGANIZACIONAL`.** Las dos guardan la membresía y hay
  pantallas que leen de cada una; escribir solo la primera hace que la empresa
  aparezca en el selector pero no en los listados de personal.
- **No cambia la empresa activa de quien la crea.** Sigue trabajando donde
  estaba y entra a la nueva cuando quiera. Moverlo por haber pulsado "crear" lo
  saca de lo que estaba haciendo.

---

## Dos huecos del mismo cambio, encontrados probando (10 sep 2026)

Los dos son fallos de la misma tanda: se habilitó una regla y no se llevó a
todas las pantallas donde hace falta.

### El botón "Aprobar" seguía en Facturación

Se quitó de Compras (`_CalidadDecisionButtons`) y se dio por hecho que era el
único sitio. **Facturación tiene sus propios botones**, en `_DocCard`, y ahí
seguía saliendo "Aprobar" sobre un documento ya aprobado. Corregido: sobre lo
aprobado queda solo "Rechazar", que es la salida si hay que devolverlo.

La lección: "quitar el botón X" casi nunca es un sitio. Antes de darlo por
hecho hay que buscar el texto del botón en todo el módulo **y en los demás**.

### En "Rechazados" de Compras no había ninguna acción

Se hizo reversible el rechazo, pero la pestaña **Rechazados** envuelve todas
sus acciones en `if (!showRejectedOnly)`: era una lista para mirar. O sea que
la acción existía y **la pantalla donde uno busca un documento rechazado no la
ofrecía**; había que entrar al expediente del proveedor a buscarla.

Ahora **los cuatro tipos** traen ahí su "Devolver a revisión": fichas técnicas,
documentos de marca, documentos de proveedor y documentos de recepción.

Los de proveedor y recepción escondían el botón por otro motivo distinto al de
las fichas: en sus tarjetas, `if (doc.rechazado)` hace un **`return` temprano**
con una versión compacta de solo lectura, así que nunca llegaban a los botones
de decisión. Eran tarjetas para mirar. Ninguna de las dos cosas se ve leyendo el
código de los botones: hay que seguir el camino del documento rechazado hasta
donde sale.

---

## Correspondencia — el administrador del módulo no tenía permisos (10 sep 2026)

Quien administra el módulo veía "No tienes permiso para clasificar ni asignar
correspondencia. Solicítalo al administrador del módulo" — es decir, el
administrador pidiéndose permiso a sí mismo.

`gd_permisos` resolvía el rol **de una forma distinta al resto de la
aplicación**, y fallaba por dos sitios a la vez:

1. **Buscaba una bandera booleana** `desarrollador == true`. El desarrollador de
   esta aplicación no se marca así: se reconoce por el rol —que puede venir
   dentro de `empresasDetalle[empresa]`— o por un `roleId` terminado en
   `_desarrollador`, que es como los crea el sembrado. Ahora usa el mismo
   `isDeveloperUser` que Interventoría, Gestión Documental y Planillas.
2. **Leía el rol de la raíz del usuario.** En una aplicación multiempresa el rol
   vive en `empresasDetalle[empresa]`; la raíz puede estar vacía o traer el de
   otra empresa. Ahora pasa por `resolveScopedRoleKey` y solo después mira la
   raíz.

Con los dos fallos, el administrador caía hasta el rol por defecto —`operador`—
que es exactamente el que no clasifica.

Lo que **no** se cambió: que un rol global de "usuario" no pueda volverse
clasificador por esta vía, y que un texto no reconocido no conceda nada. Eso
estaba bien y sigue igual; el problema no era que la puerta fuera estrecha, era
que no reconocía a quien llamaba.

`test/gestion_documental/gd_permisos_rol_test.dart` fija las dos formas de
reconocer al desarrollador y la tabla de qué puede cada rol.

## Compras — a los documentos de marca les faltaba la reversión

De los cuatro tipos de documento (recepción, proveedor, ficha técnica y marca),
**marca era el único sin reversión**. Un documento de marca rechazado no tenía
más salida que borrarlo y volverlo a subir. Ya la tiene, y aparece en la pestaña
"Rechazados" igual que la de las fichas.

---

## Correspondencia — el backend tenía el mismo fallo (10 sep 2026)

Arreglado el cliente, el servidor habría rechazado igual: `isDeveloper` en
`functions/src/correo.ts` miraba **solo una bandera booleana y los campos de la
raíz** del usuario, exactamente como el cliente antes del arreglo. El botón
habría aparecido y la acción habría fallado.

Se añadió `scopedRoleKey`, gemelo de `resolveScopedRoleKey` del cliente: mira
`empresasDetalle[empresaId].roleKey`, luego `roleId` —quitándole el prefijo de
la empresa— y solo al final la raíz. `isDeveloper` lo usa, reconoce también un
`roleId` terminado en `_desarrollador`, y el respaldo del "administrador global"
de `resolveCorreoRole` pasa por lo mismo.

`userBelongsToEmpresa` también recibe ahora la empresa: era una puerta anterior,
y un desarrollador marcado dentro de la empresa se quedaba fuera antes de que
nadie le mirara el rol.

Tres casos nuevos en `functions/test/gd_roles.test.js`. 49 pruebas del backend
en verde.

### Lo que NO se cambió, y hay que decidir

**Cliente y backend resuelven el rol en orden distinto**, y el comentario del
cliente dice que es "un espejo del control que hace el backend". No lo es:

| | Cliente | Backend |
|---|---|---|
| 2.º | `TBL_CORREO_ROLES` | `rolCorreo` del usuario |
| 3.º | `rolCorreo` del usuario | `TBL_CORREO_ROLES` |

A quien tenga los dos puestos **con valores distintos**, el cliente y el
servidor le dan permisos distintos: la pantalla enseña u oculta lo que no
corresponde.

**Unificado el 10 sep 2026 por decisión del usuario: manda
`TBL_CORREO_ROLES`.** Es lo que escribe la pantalla de roles del módulo, o sea
la asignación explícita y más reciente; `rolCorreo` en el usuario es el camino
viejo, de cuando el rol se ponía a mano. El backend se reordenó para que sea el
cliente el que tiene razón, no al revés.

De paso se corrigió algo que salió al reordenar: un documento de
`TBL_CORREO_ROLES` con el rol **mal escrito** cortaba la búsqueda y devolvía
"sin rol", o sea denegaba todo, mientras la pantalla seguía mostrando el rol por
defecto. Ahora un texto no reconocido **no corta**: se sigue buscando por los
demás caminos, igual que en el cliente.

### Lo que sigue sin unificar, y a propósito

El cliente, sin rol reconocido en ninguna parte, cae en `operador`. El backend
cae en "sin rol" y deniega. Es decir: alguien de la empresa sin rol asignado ve
la interfaz de operador y el servidor le rechaza lo que intente.

**No se cambió porque el arreglo obvio es el peligroso**: poner `operador` por
defecto en el backend le da acceso al módulo a *todo* el que pertenezca a la
empresa. Eso es una decisión de seguridad, no una corrección de coherencia, y
hay que tomarla mirando quién entraría.

---

## Compras — recepción sin ficha y captura incompleta (10 sep 2026)

La captura seguía bloqueando el guardado con "Cada producto debe tener una
ficha técnica". Se quitó esa segunda barrera: la ficha queda como soporte
opcional y visible, pero su ausencia no impide registrar la recepción física.
El aviso ahora dice expresamente que se puede continuar sin ella.

Una recepción que todavía esté en **Revisión de Calidad** puede abrirse con la
acción **Completar recepción** para agregar productos omitidos y cargar sus
soportes. La edición está disponible específicamente para **Bodega**, con Admin
Documental como respaldo; Compras y Calidad conservan el candado. Antes de
guardar, Bodega debe explicar el motivo. Cada motivo se acumula como una nota
con usuario y fecha y se muestra en la sección **Histórico de ediciones** del
detalle, incluso después de finalizar. Los productos ya guardados no pueden
retirarse y una recepción finalizada o rechazada no puede reabrirse por este
camino. La misma validación se repite dentro de la transacción para cubrir una
pantalla que haya quedado abierta mientras Calidad toma una decisión.

Si el producto agregado corresponde a una entrega programada de la misma OC,
el servicio actualiza también el vínculo con Abastecimiento y su historial.
Las pruebas específicas de recepción, permisos e histórico quedan cubiertas y
la suite completa de Compras en **105/105**. La compilación web termina correcta.

---

## Interventoría — las actas con catálogo propio parecían vacías (10 sep 2026)

Reportado por Kary: las actas de Estación de Policía y de Infraestructura, aun
estando al 100 %, se veían sin hallazgos al guardarlas y revisarlas.

La tarjeta del histórico pintaba **`kInterventoriaCategorias` fijo**, o sea las
secciones del acta **regular** —Horario, Almacenamiento, Equipos…—, sin mirar de
qué tipo era el acta. Un acta de Infraestructura guarda sus puntajes bajo
`seccion1`, `seccion2`…, así que ninguna casilla encontraba su dato y todas
salían en "—%": el acta parecía vacía aunque estuviera completa.

Eso era el síntoma. **La causa estaba más abajo y era peor.**

### La lectura del acta descartaba lo que no fuera del acta regular

`InterventoriaVisita.fromMap` construía los ítems recorriendo
`kInterventoriaCategorias` y **descartaba todas las demás claves** de
`itemsEvaluacion`. Un acta de Estación de Policía o de Infraestructura guarda
sus puntajes bajo `seccion1`, `seccion2`…, así que al releerla llegaban las doce
categorías de la regular, vacías, y ni una sola de las suyas.

Y lo grave no es verlo mal. La Fase 2 hace `_items = Map.from(visita.items)` y
al completar el acta los vuelve a guardar: **el siguiente guardado escribía las
doce categorías vacías encima y borraba de verdad los puntajes que sí estaban en
Firestore.** De ahí el "no está guardando los porcentajes" de Kary: los
guardaba, los perdía al releer, y los destruía al volver a guardar.

Leer con una lista fija no es un problema de presentación cuando lo leído se
vuelve a escribir.

Ahora se lee **todo** lo que haya guardado, con la clave que sea —incluso de un
tipo de acta que este código todavía no conozca— y solo después se completan con
vacías las secciones que el acta debería tener. Nada de lo guardado se descarta.

### Qué se recupera y qué no

Un acta que se registró y **no se ha vuelto a guardar** conserva sus puntajes en
Firestore y se verá bien en cuanto se despliegue, sin tocar nada. Un acta que ya
pasó por Fase 2 después del registro tiene los puntajes sobrescritos y hay que
volver a registrarlos: eso ya no está en ninguna parte.

### Lo que se dejó igual

En la pestaña **Análisis** el filtro de categoría ya ofrece las secciones de las
tres actas, no solo las de la regular. El valor del desplegable lleva el tipo de
acta además de la clave (`ESTACION_POLICIA|seccion1`), porque la clave sola no
identifica nada: Infraestructura y Estación de Policía usan `seccion1` para
secciones que no tienen nada que ver.

Al filtrar por una sección de un acta propia, **las actas de otro tipo se
descartan en vez de contar como cero**. Un cero es una evaluación pésima; no
tener ese acta no lo es, y promediarlas juntas hundiría el indicador de un
establecimiento por un acta que nunca le tocó.

## Borrar un acta sin pedirse permiso a uno mismo

Kary tenía que radicar una solicitud de eliminación, ir a "Permisos de borrado"
y **aprobársela ella misma**: ya estaba en
`kInterventoriaRolesAprobadoresEliminacion`. Eso no protegía de nada, porque
quien pedía y quien aprobaba eran la misma persona.

Ahora quien puede aprobar borrados borra directo. **No cambia quién puede
borrar** —es el mismo conjunto de siempre—, se quita el rodeo. Quien no está en
ese conjunto sigue radicando la solicitud.

La confirmación dice **qué más se lleva por delante**: los hallazgos del acta,
sus archivos adjuntos, y que las tareas ya creadas quedan sin su origen. Un
"¿seguro?" a secas no deja decidir nada.

---

## El comparativo se parte por subcentro (10 sep 2026)

Cómbita está registrado una vez pero opera como **Alta y Media**; Picota, como
ERE 1 y ERE 2. El comparativo agrupaba por establecimiento, así que las dos
operaciones **se pisaban**: solo sobrevivía el acta más reciente y la otra mitad
del establecimiento desaparecía del gráfico sin decirlo.

No se ocultó Cómbita, que era la petición inicial: esconder un establecimiento
entero resuelve el síntoma y deja al siguiente que mire el gráfico
preguntándose por qué falta. Ahora la clave de agrupación lleva el subcentro,
así que salen "Cómbita Alta" y "Cómbita Media" con su propio puntaje.

Dos cosas que no cambian:

- **Un establecimiento sin dividir sigue teniendo exactamente una barra.** El
  subcentro entra en la clave, no la reemplaza.
- **Dentro de cada subcentro sigue mandando la última acta**, que era la regla
  de siempre.

Sirve igual para Picota y para cualquier división futura, sin volver a tocar
esto. Y el acta ya guardaba a cuál de los dos correspondía: el dato estaba, solo
no se usaba.

De paso, el cálculo del valor pasó a `valorCategoriaAnalisis`, que es el mismo
que usa el resto del análisis. Antes el comparativo tenía su propia copia de esa
lógica y no descartaba las actas de otro tipo.

---

## Semáforo de tres estados en las marcas (10 sep 2026)

Pedido: **verde aprobada, naranja pendiente, rojo rechazada**. Antes era verde
si la marca *tenía* ficha, sin más: una ficha rechazada y una aprobada se veían
igual, que es justo lo que hay que poder distinguir de un vistazo.

Dos decisiones que no son de color:

- **Manda lo mejor que tenga la marca.** Con una ficha aprobada y otra
  pendiente, la marca está aprobada: ya puede operar. Bajarla a naranja haría
  que cargar un documento nuevo **empeorara** el indicador de una marca que
  estaba bien.
- **En el producto manda lo peor de sus marcas.** Un producto en verde con una
  marca rechazada dentro esconde justo lo que hay que atender.

`sinFicha` es un estado aparte de `rechazada` aunque los dos pinten en rojo: no
tener ficha y tener una que Calidad rechazó se arreglan de forma distinta, y la
etiqueta lo dice ("Sin ficha" / "Ficha rechazada"). El chip lleva texto además
de color porque el color solo no se lee en una captura ni en un listado impreso.

Con esto queda cerrado el documento `Correciones COMPRAS`. Los dos puntos que
quedaban —"marcar pendientes por calidad" y "revisar los numerales"— el usuario
los descartó el 10 sep: no hacen falta.

---

## La ventana de la barra muestra todos los porcentajes (10 sep 2026)

La primera versión enseñaba solo el total general. "El detalle de los
indicadores" que se pidió es el **desglose por sección**: con el total a secas
hay que salir al histórico para saber qué sección está bajando la nota, que es
justo lo que la ventana venía a evitar.

Ahora lista cada sección con su porcentaje y su color, con las secciones **del
tipo de acta** —un acta de Estación de Policía trae sus cinco, no las doce de la
regular— y en el orden en que van impresas.

Dos detalles:

- El desglose **viaja dentro del punto del comparativo**, no se recalcula al
  abrir. Volver a buscar el acta al hacer clic abriría la puerta a que la barra
  diga una cosa y el detalle otra.
- Una sección sin evaluar dice **"Sin dato"**, no 0 %. Un cero es una evaluación
  pésima; que nadie la haya evaluado no lo es.

---

## "Crear empresa y trasladar" pasa a ser solo "Trasladar" (10 sep 2026)

Con "Nueva empresa" ya resuelto, el otro botón hacía dos cosas y una sobraba.
Ahora la empresa destino **se elige de una lista**, no se escribe.

Que se escribiera era además un riesgo real: el id de una empresa **no se puede
corregir después** —viaja dentro de otros ids y de las rutas de Storage—, así
que un id mal tecleado en ese campo creaba una empresa nueva sin querer, con un
identificador equivocado y para siempre.

`CompanyTransitionService` fallaba con "ya existe una empresa con ese ID" cuando
el destino existía: era la única forma de trasladar, creando. Ahora trabajar
sobre una empresa que ya existe es el caso normal.

**A una empresa que ya existe no se le toca la ficha.** Tiene su NIT, su logo y
sus datos, puestos a propósito; copiarle encima los del origen los borraría en
silencio. Solo se deja constancia del traslado. Cuando la empresa destino no
existe, el comportamiento de siempre se conserva intacto.

---

## El archivo plano sale de la planilla firmada (10 sep 2026)

El generador estaba hecho y sin conectar. Ya hay un botón **"Descargar archivo
plano (CSV)"** en el detalle de la planilla, debajo del de PDF.

### No hace falta el maestro de cuentas para esto

La planilla de anticipos ya trae **todo lo que el banco necesita**: NIT, dígito
de verificación, beneficiario, número de cuenta, si es corriente o de ahorros,
banco y valor. El maestro de cuentas es para la **nómina**, donde el
beneficiario es una persona y esos datos no están en ningún documento.

Las filas ya se guardaban: un consolidado las tiene en
`datosExcel.filas_rows`, y una planilla individual es una sola fila en su propio
`datosExcel`.

### Solo con la planilla firmada

El botón no aparece antes. El plano es la instrucción que se le sube al banco:
bajarlo antes de la firma de gerencia permitiría pagar algo que todavía no está
aprobado.

### Tres cosas que no son obvias

- **CTE / AHO se marcan con una X**, no con un número. Se traduce a 01 y 02, que
  es lo que el banco espera.
- **Las cabeceras del Excel las escriben personas** y cambian entre archivos:
  "No Cuenta", "N CUENTA", "numero_cuenta". Se buscan todas las formas conocidas
  en vez de exigir una.
- **El archivo se escribe en latin1**, no en UTF-8. El cargador del banco es de
  los que no entienden UTF-8, y un nombre con tilde mal codificado es una fila
  rechazada. Las tildes y la eñe existen en latin1 y se conservan; lo que no
  existe —comillas tipográficas, guiones largos pegados desde Word— se cambia
  por su equivalente simple en vez de reventar el archivo entero.

### Se avisa antes de descargar, no después

Si alguna fila tiene un dato que el banco va a rechazar, se enseña la lista con
nombre y apellido y se pregunta si se descarga igual. Un plano con un dato malo
lo rechaza el banco **entero**, y enterarse allí cuesta un día de pagos.

### Sigue faltando el maestro de cuentas

`TBL_NOMINA_CUENTAS` está modelado y probado, con su importador de Excel, pero
**no tiene pantalla ni reglas de Firestore**. Eso es lo que falta para la nómina;
para los anticipos a proveedores no hace falta.

---

## El maestro es de beneficiarios de pago, no de nómina (10 sep 2026)

`TBL_NOMINA_CUENTAS` pasó a `TBL_PAGOS_BENEFICIARIOS`. **Se renombró antes de
que hubiera un solo dato dentro**, que es la única ventana en que sale gratis:
después es una migración, como la cédula.

Un beneficiario es cualquiera a quien la empresa le paga —un empleado por cédula
o un proveedor por NIT—. La nómina y los anticipos usan el mismo archivo plano
y las mismas columnas: dos maestros obligarían a mantener dos veces la misma
tabla y a que el generador supiera de cuál leer.

## Reglas de Firestore: el corte tiene que ser real

**Firestore no tiene seguridad por campo.** Una regla decide si se lee el
documento entero, no una parte. Con todo en un solo documento, "Talento Humano
ve el banco y no la cuenta" era una cortesía de la interfaz: bastaba abrir la
consola.

Por eso son **dos colecciones**, con el mismo id:

- `TBL_PAGOS_BENEFICIARIOS` — nombre, banco, tipo y forma de pago. La lee
  Talento Humano y Tesorería, y Talento Humano puede corregir el banco.
- `TBL_PAGOS_BENEFICIARIOS_CUENTA` — solo el número. Tesorería y administración
  documental. Talento Humano **no entra**.

La regla del maestro rechaza además cualquier escritura que traiga
`numeroCuenta`: si se colara ahí, quedaría legible para Talento Humano y el
corte no serviría de nada.

### El punto de partida era peor de lo que parecía

La regla comodín del final del archivo es
`allow read, write: if isSignedIn()` con una lista de excepciones. Estas dos
colecciones no estaban en esa lista, así que **cualquiera con una cuenta podía
leerlas y escribirlas**, de cualquier empresa. Ahora están excluidas del comodín
y tienen regla propia.

### Probadas en el emulador el 10 sep 2026

`functions/test/nomina_cuentas.rules.js`, **6 de 6 en verde** (2 saltadas, las
de Talento Humano, que entran cuando exista su módulo):

- Tesorería lee el maestro y el número.
- El número no se puede colar en el maestro.
- Quien no es Tesorería no puede escribir el número.
- Alguien de la empresa **sin rol de planillas** no ve nada.
- La Tesorería **de otra empresa** no ve estas cuentas.
- Sin sesión no se ve nada.

Hizo falta instalar Temurin 21 (`choco install temurin21`, en consola de
administrador) y ponerlo **en el PATH**, no solo en `JAVA_HOME`: la CLI de
Firebase ejecuta el `java` que encuentra en el PATH. Se pone solo para esa
ventana, para no mover el JDK con el que compila Android.

```
$env:PATH='C:\Program Files\Eclipse Adoptium\jdk-21.0.12.101-hotspotin;'+$env:PATH
cd C:\Desarrollo\capital-uspecunctions
npx firebase emulators:exec --only firestore "node --test test/nomina_cuentas.rules.js"
```

### Pendiente: `isDeveloper()` toca campos que pueden no existir

En los registros del emulador aparece `Property desarrollador is undefined on
object`. En las reglas, leer un campo ausente con el punto **lanza un error de
evaluación**, y la mayoría de los usuarios no tienen `desarrollador`. Hoy no
rompe nada porque quien llama a `isDeveloper()` lo hace dentro de un `||` que
sigue siendo cierto por otra rama, pero el día que esa función sea la única
rama de un permiso, el error denegará a quien sí tenía derecho.

El arreglo es leer con `get('campo', valorPorDefecto)`. **Se intentó y se
revirtió**: `isDeveloper()` gobierna todas las reglas de la aplicación y el
emulador dejó de arrancar antes de poder comprobarlo
(`NoClassDefFoundError: LegacySystemExit`, con el jar recién descargado). Subir
sin verificar un cambio en el portero de todo, para quitar ruido de un registro,
es mal negocio. Queda anotado para hacerlo cuando el emulador vuelva a levantar.

## El maestro completa el archivo, no lo sustituye

`completarConMaestro` cruza las filas del Excel subido con el maestro por
identificación y **rellena solo los huecos**. Es lo que evita que generar el
plano sea un trabajo manual: el Excel trae el pago —a quién y cuánto— y el
maestro pone la cuenta y el banco cuando el beneficiario ya es conocido.

**El archivo manda sobre el maestro.** Si la fila trae un dato, ese se respeta:
puede ser un pago excepcional a otra cuenta, y sustituirlo por "lo de siempre"
mandaría el dinero a donde el archivo no dijo.

Lo que no esté en ninguno de los dos se queda vacío y lo reporta la validación
con nombre y apellido. Y `beneficiariosSinMaestro` dice a quién hay que dar de
alta antes de reintentar, en vez de dejarlo deducir de una lista de errores.

---

## Pantalla del maestro de beneficiarios (10 sep 2026)

En Planillas de Pago, botón **BENEFICIARIOS**. Listado paginado de 20 con
buscador, ficha para crear y editar, e importación del Excel de Tesorería.

**Es de proveedores, no de nómina.** La nómina la gestionará Talento Humano
desde su propio módulo; por eso el rol `talento_humano` se quitó de las reglas:
dejarlo puesto sería dar acceso a algo que todavía no existe. Cuando llegue, es
añadir ese rol a **una** lista de **una** regla y nada más — no hay migración,
porque el corte en dos colecciones ya está hecho.

### Detalles que no son de pantalla

- **El número de cuenta no viaja en el listado.** Se pide uno a uno al abrir la
  ficha. Traer cientos de números para pintar una lista sería exponer de más y
  pagar de más en lecturas.
- **El banco se elige por su nombre**, no por el código. Nadie recuerda que
  Davivienda es 0051, y un dígito mal escrito manda el dinero a otra entidad. Si
  el beneficiario ya tiene un código que no está en el catálogo —pasa: 0507,
  0551, 0809— se conserva y se avisa, en vez de reemplazarlo por uno de la
  lista.
- **La identificación no se puede editar** en una ficha existente: es el id del
  documento, así que cambiarla crearía otro y dejaría el viejo suelto.
- **Guardar sin permiso sobre el número no borra el que ya estaba**: solo se
  escribe la colección del número cuando llega con algo.
- **La importación enseña lo encontrado antes de escribir**, con sus bloqueos y
  sus avisos. Importar a ciegas un maestro de cuentas bancarias y revisarlo
  después es al revés.
- El error de permiso en el listado se muestra como "esto es de Tesorería", no
  como una pantalla roja: no es una caída.

### El plano ya usa el maestro

Al descargar el archivo plano de una planilla firmada, las filas se completan
con el maestro por identificación. Si algún beneficiario no está, el aviso dice
**cuáles** hay que dar de alta, no solo que falta un dato.

Si el maestro no se puede leer, se sigue con lo que trae el archivo: quedarse
sin plano por un permiso sería peor que generarlo incompleto y avisar.

---

## El Excel que ya se sube alimenta el archivo plano (10 sep 2026)

Pregunta del usuario: si el Excel se sube para generar los PDF, ¿se puede
aprovechar para el archivo plano?

**Ya se estaba guardando**, en las dos formas, desde antes de esta sesión:

- un consolidado guarda todas sus filas en `datosExcel.filas_rows`;
- una planilla individual guarda la suya en `datosExcel.fila_row`, y además
  esparce sus columnas en el propio `datosExcel`.

Así que el plano sale de ahí **sin volver a subir nada**. Se afinó la lectura
para preferir `fila_row` sobre el `datosExcel` suelto: los dos funcionan, pero
el segundo trae ruido (`logo_path`, `tipo_generacion`) y solo hace falta para
las planillas generadas antes de que `fila_row` existiera. Se conserva ese
tercer camino precisamente por ellas: dejar sin plano lo ya generado sería peor
que leer un mapa con basura que el extractor ignora.

### Lo que NO se guarda, y probablemente esté bien

El archivo `.xlsx` original **no** se conserva; sí sus filas. Para regenerar el
plano hacen falta los datos, no el archivo. Guardar el original añadiría
almacenamiento y una copia más de cuentas bancarias que proteger, sin resolver
nada que las filas no resuelvan ya. Si algún día hace falta el original como
soporte de auditoría, es otra decisión y otro sitio.

## Jefe directo en "Ver personal": la lista salía vacía o sin nombre (14 sep 2026)

Al editar o agregar un colaborador, el campo **Jefe directo** no traía a nadie,
o mostraba la cédula en lugar del nombre. Tres causas en
`organizational_structure_screen.dart`:

- buscaba solo en `_currentDocs`, que es la lista **ya filtrada** en pantalla
  (estado, área, cargo, búsqueda). Si el jefe estaba en otra área o fuera de la
  búsqueda, no existía para el selector;
- tomaba el nombre del doc de `TBL_ESTRUCTURA_ORGANIZACIONAL`, que en muchos
  registros está vacío; el nombre real vive en `TBL_USUARIOS` y así lo
  resuelven las tarjetas;
- comparaba el cargo con `==` exacto contra el texto del campo "Cargo del jefe
  directo": una tilde o una mayúscula distinta dejaba la lista en cero.

Ahora el selector lee de `_companyDocs` (todo el personal activo de la empresa,
sin filtros de vista), resuelve el nombre como las tarjetas, compara el cargo
normalizado (`normalizeHierarchyText`) o por `cargoId`, y si con ese cargo no
hay nadie muestra a todo el personal con su cargo en el subtítulo, para que el
proceso nunca quede bloqueado. Si se elige al jefe sin haber elegido su cargo,
el cargo se completa solo a partir de la persona.

De paso: al elegir el **cargo propio** se guardaba su código en `jefe_cargo`
(el cargo del jefe). Ahora se limpia, como el resto de campos del jefe.

## Plantilla Excel de formato: encabezado según el modelo del jefe (14 sep 2026)

El jefe entregó `1. Formato modelo v1.xlsx` con el encabezado como lo quiere.
`gd_formato_plantilla.dart` ahora reproduce esa geometría en vez de la
provisional del 12 sep:

- **Rellenos como la versión del 12 sep** (el jefe sí los quiere; el modelo
  los traía en blanco pero fue una aclaración posterior): título en blanco
  sobre el primario `0D1B68` (azul marino del modelo), empresa, dependencia
  y etiquetas sobre el secundario claro `E8EEF5`, valores en blanco, y una
  franja del primario en la fila 6 (la fila 5, de 2 pt, queda en blanco como
  hueco). Bordes finos en el primario. `TBL_EMPRESAS.colorPrimario/
  colorSecundario` los siguen sobreescribiendo por empresa.
- **Columnas A-Q todas angostas e iguales** (4.86 en Excel) y R como margen:
  el encabezado mide 497 pt y cabe en carta vertical; la cuadrícula fina es
  la que usan las dependencias para armar el contenido.
- **Bloques:** logo `A1:C4` · empresa `D1:L1` (negrilla 11) · nombre del
  formato `D2:L3` (negrilla 11) · dependencia `D4:L4` (normal 11) ·
  etiquetas `M:N` · valores `O:Q`. Se elimina la fila "Empresa": la empresa
  va arriba del título.
- **Filas:** 1-4 de 14.25 pt; 5 y 6 separadoras de 2 y 8 pt. El contenido
  libre sigue empezando en la fila 7 y la protección de hoja no cambia.
- **Aprobado lleva solo el nombre.** La celda `O2:Q2` mide 87 pt: no cabe
  "nombre · fecha hora". El modelo pone `[usuario]`, así que el sello de
  Calidad escribe el nombre y la fecha/hora exacta queda en el registro de la
  Biblioteca (ya estaba). Nombres largos se encogen (`shrinkToFit`) en vez
  de cortarse; lo mismo empresa y dependencia.
- El sello sigue reconociendo los archivos descargados con el encabezado
  anterior (combinación `C1:G3`) y les escribe en `I2`; los nuevos van en
  `O2`.

Verificado abriendo el .xlsx generado en Excel (COM): mismas medidas que el
modelo (`A1:Q4` = 497.25 × 57 pt, logo centrado en `A1:C4` sin deformar).

Lo que NO se copió del modelo, a propósito: la hoja del jefe no está
protegida y tiene `D1:L4` desbloqueadas; eso contradice el acuerdo del 12 sep
(encabezado intocable), así que el candado se mantiene. Tampoco la columna
S oculta, que no aporta nada al usuario. Y el blanco sin rellenos del modelo
tampoco: el jefe aclaró después que los rellenos van.

## Biblioteca: área en vez de dependencia, carpetas fijas y normograma (14 sep 2026)

Instrucciones del jefe sobre la Biblioteca Documental:

- **Títulos siempre en mayúscula.** El servicio guarda `titulo` en mayúscula
  al crear, el campo del formulario capitaliza mientras se escribe y la
  plantilla Excel pone en mayúscula el nombre del formato y la empresa.
  Los registros anteriores también se ven en mayúscula: `DocumentoDoc.fromMap`
  normaliza al leer, así que no hay migración de datos.
- **"Dependencia" pasa a llamarse "Área"** en formulario, tabla, detalle,
  plantilla y mensajes. El campo de datos sigue siendo `area`.
- **El área solo se pide en formatos.** En documentos del contrato y en
  normograma el campo no aparece y se guarda `null`. El código automático
  ahí sale del **tipo de documento** (`gdCodePrefixFor`): Resolución →
  `RES-001`, Contrato → `CTR-001`, Documentación interna → `DIN-001`…
  Los formatos siguen tomando el prefijo del área.
- **Nuevo tipo de documento del contrato:** `Documentación interna`.
- **Carpetas fijas del contrato** (`gdContractFolders`, sin numerar, solo
  el nombre): Documentos básicos · Documentos precontractuales · Documentos
  presentados en licitación · Normas aplicables · Formatos · Correspondencia
  enviada · Imagen corporativa. El alta las ofrece en un desplegable (más las que ya
  existan y "Otra carpeta…"), el filtro las lista siempre en ese orden y el
  detalle las sugiere al editar.
- **Normograma:** el título se registra como "Título de la ley o norma" y el
  número como "Número de ley o resolución" (obligatorio). En la tabla el
  título va unido a su número y a los documentos asociados, y hay una
  columna nueva **N° LEY / RESOLUCIÓN**; las palabras clave pasan a la
  columna siguiente.

### Ajuste del jefe por la tarde (14 sep 2026): color solo en etiquetas y tipo en la fila 1

- **Color solo en Versión, Aprobado, Fecha y Código** (relleno secundario
  claro). Título, tipo, área y las filas separadoras van sin relleno, en
  azul marino sobre blanco.
- **La fila 1 (`D1:L1`) muestra el TIPO del documento** (FORMATO,
  PROCEDIMIENTO, POLÍTICA…) en vez del nombre de la empresa. El nombre de la
  empresa solo aparece como texto de respaldo cuando no hay logo. El tipo
  sale de `categoria` (`GdPlantillaFormatoDatos.tipo`); la descarga previa
  desde el diálogo de alta lo toma del tipo elegido.

## Facturación: el autor de las observaciones salía como cédula (14 sep 2026)

En "Observaciones" de Proyectos Productivos el autor aparecía como
`1073241667`. El widget correcto (`UserAvatar`/`UserNameText`) ya estaba,
pero el nombre no llegaba por dos causas:

- Facturación resolvía el autor leyendo solo `nombre`/`name` de
  `TBL_USUARIOS`, y la mayoría de personas tienen el nombre partido en
  `primerNombre`/`primerApellido`; así guardaba la cédula en `autorNombre`.
  Ahora los tres puntos (comentario nuevo, detalle de establecimiento y
  planilla) y el buscador de responsable del establecimiento usan
  `UserDirectory`.
- `UserDirectory._fromUsuario` tomaba `nombres ?? primerNombre`: un
  `nombres: ''` presente pero vacío tapaba a `primerNombre`. Ahora toma el
  primer campo NO vacío y arma nombre + segundo nombre + apellidos. Se
  expone `fromUsuario()` para quien ya tiene el doc en mano.

Las observaciones antiguas que guardaron la cédula en `autorNombre` se
resuelven al abrir la hoja (`_idDe`: `autorId` o, si venía vacío, la cédula
de `autorNombre`). Prueba nueva: `test/core/user_directory_nombre_test.dart`.

## Interventoría en Gerencia + hora de subida del acta (17 sep 2026)

**Histórico de actas (Interventoría).** Debajo de la fecha de la visita,
cada tarjeta muestra en letra pequeña "Subida el dd/MM/yyyy HH:mm": es
`fechaRegistro`, que se fija en el primer guardado y no cambia con
correcciones ni revisiones, así que es la hora real en que el registrador
subió el acta.

**Pestaña "Interventoría" en Gerencia** (`lib/gerencia/gerencia_interventoria_tab.dart`).
Consulta gerencial de `TBL_INTERVENTORIA_HALLAZGOS`, solo lectura:

- Buscador por palabra clave (establecimiento, numeral, descripción, área,
  responsable, observaciones, plan de mejora, seguimientos); ignora tildes,
  espacios y mayúsculas.
- Filtro de fecha a fecha sobre la fecha del hallazgo, con accesos rápidos
  de 30/60 días o todo el histórico; filtro por estado (tarjetas KPI) y por
  área (catálogo vía `AreaCatalogo`, nunca ids crudos).
- Gráfica de barras agrupada por establecimiento, área, numeral o acta,
  cada barra partida por estado (activo / por aprobar / subsanado). Clic en
  una barra abre el detalle con la lista de esos hallazgos, paginada de a
  20; clic en un hallazgo abre el mismo panel del módulo
  (`mostrarPanelHallazgo`) con `canWrite: false`.
- Respeta la empresa elegida en Gerencia; con "Todas las empresas" consulta
  hasta 10 con `whereIn` (`InterventoriaService.streamHallazgosEmpresas`).
- La pestaña se pinta aunque la empresa no tenga tareas: va antes del
  "Aún no hay tareas para analizar".

Pendiente de definición: las actas no tienen número consecutivo, así que la
agrupación "Acta" las identifica por establecimiento + fecha de visita.

## Maestro de subsanaciones: quién lo ve y copia entre empresas (17 sep 2026)

**Acceso.** La pestaña "Maestro" de Interventoría sale única y exclusivamente
para Directivo, Gerente y Administrador del módulo (`kInterventoriaRolesMaestro`),
además del usuario desarrollador. Calidad, que lo consultaba desde el 11 sep,
queda fuera. Editar la regla sigue siendo solo de administración y gerencia;
Directivo entra en solo lectura.

**Copiar a otras empresas.** Botón en la cabecera del maestro (solo para quien
puede editar y cuando la empresa tiene reglas propias). Abre un diálogo con:

- Qué copiar: solo el acta que se está viendo o todas las actas. Las reglas
  viejas (clave sin familia) solo viajan con la regular, igual que al leerlas.
- Reemplazar o completar: con "reemplazar" apagado se conservan los numerales
  que el destino ya tenía.
- Empresas destino: todas las del usuario, pero solo se pueden marcar aquellas
  donde es `admin_interventoria` (o desarrollador), que es lo único que
  `firestore.rules` deja escribir en `TBL_INTERVENTORIA_CONFIG`. Cada empresa
  muestra cuántas reglas tiene, cuántas se pisan y **qué cargos de las reglas
  no existen en su TBL_CARGOS**: las reglas van por nombre de cargo y una regla
  con un cargo inexistente deja el hallazgo sin responsable.

Cada destino se escribe en su propia transacción; las reglas copiadas quedan
con `copiadoDe: <empresa origen>`, `actualizadoPor` y `actualizadoEn`.

Pendiente conocido (no tocado): `puedeEditarMaestroSubsanaciones` deja editar a
Gerente, pero `firestore.rules` solo permite escribir la config al rol
`admin_interventoria`; un gerente que edite o copie recibe permiso denegado.

## Interventoría: el registrador corrige el acta en vez de pedir que la borren (17 sep 2026)

Los administradores de establecimiento (registradores) se equivocaban en un
dato, pedían la eliminación del acta y luego tenían que subir todo otra vez.
El mecanismo de corrección en sitio ya existía (calidad "devuelve" el acta,
queda en `faseActa: 'devuelta'`, botón "Corregir", al guardar vuelve a
"Por revisar" conservando PDF, puntajes e historial), pero solo lo podía
disparar calidad/gerencia. Ahora:

- **Acta propia sin revisar (Fase 1, `puntajes`)** → botón "Corregir acta"
  en el histórico. Pide el motivo (mismo mínimo que una devolución), deja el
  acta en `devuelta` a nombre del propio registrador —sin tarea— y abre el
  formulario de una vez. `puedeCorregirActaPropia` /
  `InterventoriaService.abrirCorreccionPropia` (transacción: si calidad la
  revisó entre el clic y el guardado, se rechaza). En `devoluciones` queda
  con `autocorreccion: true` para no contarla como devolución de calidad.
- **Acta ya revisada (o de otra persona)** → botón "Solicitar corrección"
  (reemplaza a "Solicitar eliminación" para quien no puede borrar). Va por
  la misma función y colección que la eliminación con `accion: 'correccion'`
  (`solicitarCorreccionActa`). Al aprobarla, el backend
  (`returnVisitaForCorrection` en `interventoria_deletion.ts`) deja el acta
  en `devuelta` con `correccionResponsableId` = solicitante y le notifica
  (`interventoria_acta_devuelta`, abre el histórico); no borra nada.
- La pestaña "Permisos de borrado" pasa a llamarse **"Solicitudes"** y
  distingue las dos: icono, texto y botón "Aprobar corrección" /
  "Aprobar eliminación". Las solicitudes viejas sin `accion` siguen siendo
  eliminaciones.
- Los roles aprobadores conservan "Eliminar acta" directo para duplicados;
  el diálogo del registrador le dice que si el acta está repetida lo indique
  en el motivo.

Pruebas: `test/interventoria/interventoria_models_test.dart` (grupo
"corrección por quien registró el acta") y
`functions/test/interventoria_deletion.test.js` (`requestAction`).

**Requiere desplegar functions** (`interventoriaSolicitarEliminacion` y
`interventoriaResolverEliminacion`). Hasta entonces "Solicitar corrección"
crea la solicitud sin `accion` y se trataría como eliminación: el botón
"Corregir acta" de Fase 1 sí funciona sin deploy porque es solo cliente.

## Correspondencia: cerrar con motivo, justificación y soporte (17 sep 2026)

Pedido de la operación: a veces al abogado le llega algo que **no se va a
responder** (un correo de otra EPS que no nos corresponde, una circular
informativa, un duplicado) y no había manera de terminar la asignación
dejando dicho por qué. "Terminar proceso" cerraba en silencio, y después
nadie sabía si se atendió o se descartó.

**Dónde vive.** En el mismo botón **Terminar proceso** del detalle del
expediente (no en la mesa de colaboración: esa sigue siendo para discutir
entre varios; el cierre es una decisión de quien lo tiene asignado o del
administrador del módulo, con los mismos permisos de antes).

**Qué pide el diálogo.**
- **Motivo** del catálogo `GdMotivoCierre` (mismo catálogo en
  `functions/src/gd_cierre_policy.ts`): gestión completa · no corresponde a
  la entidad · no requiere respuesta · duplicado · otro.
- **Justificación**: obligatoria (mínimo 10 caracteres) siempre que el motivo
  no sea "gestión completa" **y** siempre que el expediente se cierre sin
  respuesta registrada, aunque el motivo sea "gestión completa". El backend
  lo vuelve a exigir (`validateGdCierre`), así que no depende del cliente.
- **Soporte** opcional: PNG/JPG/PDF hasta 10 MB (el correo donde otra entidad
  asumió el caso, por ejemplo). Sube a
  `gestion_documental/correspondencia/{empresaId}/{expedienteId}/soportes-cierre/{userId}/`,
  hermano de `soportes-contestado/` que ya funciona; `storage.rules` no está
  en el repo, conviene confirmar la regla en la primera carga.
- Si no hay respuesta registrada, el diálogo lo avisa y preselecciona "No
  corresponde a la entidad" (se puede cambiar).

**Qué queda guardado** en `TBL_GD_EXPEDIENTES`: `cierreMotivo`,
`cierreJustificacion`, `cierreSinRespuesta` (lo fija el backend mirando si
había respuesta al cerrar), `cierreSoportes[]`, además de `terminadoPor` y
`terminadoAt` que ya existían. En `TBL_GD_EXPEDIENTES_EVENTOS` el evento es
`proceso_terminado` o `proceso_terminado_sin_respuesta`, con el motivo, la
justificación y el nombre del soporte en el detalle. La tarea vinculada
sigue pasando a `por_aprobar` (mismo contrato de siempre) pero `lastEventText`
y `solicitud_finalizacion_motivo/_justificacion` llevan el motivo, así que el
aprobador lo ve en "Tareas por aprobar" sin abrir el expediente.

**Dónde se ve.**
- Detalle → "Cierre del proceso": motivo, "cerrado sin respuesta" cuando
  aplica, quién (con `UserAvatar`/`UserNameText`), cuándo, la justificación y
  el soporte descargable.
- Lista maestra y tabla de control: los cierres sin respuesta van en ámbar
  con la etiqueta "Cerrado sin respuesta" (los terminados con respuesta
  siguen en verde) y una línea "Cierre: {motivo}".
- Excel: tres columnas nuevas al final (Motivo de cierre, Justificación del
  cierre, Cerrado sin respuesta).

Los cierres anteriores a esta versión no tienen motivo: se muestran como
antes y, si no tenían respuesta, se leen como "cerrado sin respuesta"
(`cerradoSinRespuesta` mira la marca del backend **o** la ausencia de
respuesta).

Pruebas: `functions/test/gd_cierre_policy.test.js` y
`test/gestion_documental/gd_cierre_expediente_test.dart`. Falta desplegar
`gdTerminarExpediente` (`npm run deploy` en `functions/`); mientras no se
despliegue, el cliente manda los campos nuevos y la función vieja los ignora
(cierra sin motivo, como antes).

## Gerencia → Interventoría: responsable con jefe inmediato; Análisis muestra el tipo de acta (18 sep 2026)

**Informe de Gerencia** (`gerencia_interventoria_tab.dart`):
- Filtro **Responsable** (quienes tienen hallazgos en el conjunto cargado,
  por nombre) y agrupaciones nuevas de la gráfica: **por responsable**,
  **por administrador de establecimiento** y **por director de área**.
- En el detalle de cada hallazgo, además de "Responsable: X", salen
  "Administrador del establecimiento: Y" y "Director del área: Z", que es a
  quien Gerencia escala. Se decidió NO usar el "jefe directo" de Talento
  Humano (`jefeId` de la ficha): es un dato de la persona, no de quién
  responde por el hallazgo.
  - Administrador: `resolverPrimerCargoQueResuelva(['Administrador'],
    centroCostoId, personal)`, solo si es del centro — mismo criterio que la
    devolución de actas.
  - Director: `resolverDirectorDeArea` (extraído de `getDirectorDeArea`): la
    persona de mayor cargo dentro del área, comparando el área por
    `AreaCatalogo.contiene` y no por id. Prueba nueva:
    `test/interventoria/interventoria_director_area_test.dart`.
  - El personal por empresa se carga una vez por conjunto de empresas con
    `listarUsuariosAsignables` (área puenteada por cargo); los resolvedores
    se cachean por centro y por área.
- La palabra clave también encuentra por nombre del responsable, del
  administrador y del director.

**Análisis (Interventoría)**: el punto del comparativo
(`InterventoriaComparativoActa.tipoActa`) lleva el tipo del acta, y los dos
diálogos de detalle —clic en la barra y clic en una celda de la tabla— lo
muestran junto a la fecha ("Última acta: 12/09/2026 · Seguimiento").

## Interventoría: el subcentro ya no es obligatorio al registrar el acta (18 sep 2026)

En un establecimiento dividido el formulario exigía elegir subcentro y no
dejaba guardar sin él. Los establecimientos tienen su propia acta,
independiente de la de cada subcentro, así que ahora el desplegable es
opcional: "Acta del establecimiento (sin subcentro)" es la primera opción y
solo se elige un subcentro cuando el acta es de esa división. Se quitó la
validación de `_save` y se actualizó el texto de ayuda del maestro de
subcentros en Admin.

**Comparativo de Análisis**: el acta sin subcentro de un establecimiento
dividido ya es una barra propia ("Cómbita" junto a "Cómbita Alta" y
"Cómbita Media"). Antes se ocultaba —decisión "dos barras, no tres" de la
reunión con Oscar, cuando esa acta se entendía como anterior a la
división—; confirmado el 18 sep 2026 que el establecimiento tiene su propia
acta, se quitó ese filtro en `compararUltimaActaPorEstablecimiento` y se
actualizó la prueba en `interventoria_visita_items_test.dart`.

## Reunión 18 sep 2026 + reportes de TH, Bodega y Gerencia (21 sep 2026)

Origen: notas de Gemini de la reunión con Oscar del 18 sep 2026 y los
reportes del 20-21 sep (Talento Humano, Bodega y Gerencia).

**Bugs**

- **Talento Humano inactivaba a alguien y "volvía a aparecer activo".**
  `PersonnelStatusService.changeStatus` escribía el bloque de
  `TBL_ESTRUCTURA_ORGANIZACIONAL` con `set(merge: true)` y claves con punto
  (`empresasDetalle.X.estado`). `set()` NO interpreta los puntos como ruta:
  creaba un campo literal con ese nombre y el bloque anidado seguía en
  `activo`; al reabrir el organigrama, `_syncAllTH` copiaba ese `activo` a la
  raíz y la persona "revivía". Ahora va por `update()` (que sí entiende las
  rutas) y borra el campo literal que dejó la versión anterior. Además
  `_syncAllTH` repara sola a quienes ya quedaron con el campo literal: lo
  pasa al bloque real y lo elimina. Mismo patrón corregido en el registro
  de tokens FCM (`home_screen`, `notification_service`) y en la auditoría
  de login (`session_audit_service`): mapas anidados en vez de claves con
  punto.
- **Bodega: recepción "Finalizada" sin haber hecho nada.** Una recepción
  guardada sin ningún documento (permitido: la ficha no puede frenar la
  recepción física) caía en `historico` y quedaba bloqueada como
  "Finalizada" sin botón de completar. `estadoRecepcionCompras`: sin
  soportes = `pendiente`. Prueba en `compras_recepcion_logic_test.dart`.
- **Bodega: "Dart exception thrown from converted Future…" al enviar
  correcciones.** En Flutter web el manejador de `runTransaction` se
  convierte en una promesa de JavaScript y cualquier `StateError` lanzado
  adentro (las validaciones de `reenviarRecepcionCorregida`: "Debes
  corregir todos los documentos rechazados…", "Solo se pueden reemplazar
  documentos rechazados…") salía afuera con ese texto genérico. Las cinco
  transacciones de `ComprasService` pasan ahora por `_transaccion`, que
  guarda el error de adentro y lo relanza tal cual; la pantalla muestra el
  mensaje sin el prefijo "Bad state:".
- **Bodega/Compras pueden borrar lo propio mientras Calidad no lo revise:**
  la recepción pendiente que ellos mismos registraron y la ficha técnica sin
  versión aprobada (`comprasRolPuedeEliminarPropiasPendientes`,
  `fichaTecnicaEliminablePorAutor`). Admin sigue borrando todo.
- **Móvil: no se podía desplazar el panel de la tarea para llegar a
  "Aprobar".** Los paneles de Mis tareas y Tareas creadas eran un `Wrap`
  sin scroll dentro del bottom sheet; con finalización pendiente + novedades
  se salían de la pantalla. Van en `SingleChildScrollView` acotado al 92 %
  del alto.

- **Calendario del inicio mezclaba empresas.** Citas, abastecimiento y
  visitas ya filtraban por empresa, pero las tareas entraban con
  `allowLegacyWithoutEmpresa: true`: cualquier tarea sin `empresaId` salía
  en el calendario y en "Pendientes de hoy" de todas las UT. Ahora es
  estricto, igual que "Mis tareas".

**Compras (reunión)**

- Se quita el botón "Nueva Recepción": toda recepción nace de una entrega
  programada en Abastecimiento. La pantalla queda para completar, corregir,
  eliminar y ver cuánto lleva Calidad sin revisar. Los cancelados se
  conservan (Oscar: "ahí se ve la gestión").

**Gerencia → Interventoría (reunión)**

- **Numerales al abrir un establecimiento**: en el detalle salen chips por
  sección del acta (1..11) con su conteo; un clic deja solo esa sección. La
  lista se ordena por numeral. `gerencia_hallazgos_export.dart`
  (`seccionDelHallazgo`, `conteoPorSeccion`, `compararPorNumeral`) con
  pruebas en `test/gerencia/`.
- **Exportar según el nivel del filtro**: Excel de todo lo filtrado (botón en
  la gráfica) o del grupo / sección abierta (botones en el detalle). PDF solo
  del detalle, como se acordó ("la de PDF solamente sería esta"). El archivo
  lleva el alcance y los filtros en la cabecera.
- **Paginación arriba y tarjetas del mismo alto**: en escritorio, gráfica y
  detalle miden lo mismo (640 px) con scroll interno y la barra de páginas
  encima, que era lo que pidió Oscar. `PagedListSection` acepta
  `barraArriba` para el mismo caso en otras pantallas.
- **Subcentros separados**: cada subcentro es una fila propia con su nombre
  como título y "Subcentro de X" debajo; la clave se normaliza con
  `claveSubcentro` para que "Alta" y "Cómbita Alta" caigan juntas. Los
  hallazgos de observaciones generales y conclusiones ahora llevan el
  subcentro del acta.
- **WhatsApp de nueva acta**: "Centro de costo: Planta externa (Estación
  Soacha)" (`etiquetaCentroConSubcentro` en
  `workflow_whatsapp_notifications.ts`). Falta desplegar functions.

**Interventoría**

- La solicitud de eliminación/corrección de acta ya solo notificaba a los
  roles que pueden aprobarla; ahora además excluye a quien ya está retirado
  de la empresa (`userIsActiveInEmpresa` en `interventoria_deletion.ts`).
  Falta desplegar functions.
- El diálogo "Copiar a otras empresas" del maestro lleva también la
  configuración del módulo (programas, actas habilitadas, plazos de
  subsanación, semáforo, OCR) con `copiarConfiguracionInterventoria`. Roles
  y actas no se copian: son personas y datos de cada empresa.

**Visitas (reunión)**

- Pestaña **"Registro de visita"** para el profesional: al llegar toca
  "Estoy en el establecimiento", la app toma el GPS, busca dentro de qué
  radio del maestro está y "jala" la visita programada ahí (Iniciar /
  Continuar). Sin visita programada en ese sitio no puede iniciar nada: lo
  corrige el jefe. Lógica pura en `resolverRegistroVisita`
  (`visitas_models.dart`) con pruebas en `test/visitas/visitas_registro_test.dart`.
- Reprogramar queda solo para el jefe (`visitasPuedeReprogramar`): el 17 sep
  se había dejado que el profesional moviera la suya; el 18 sep Oscar cerró
  que el cronograma lo arma y corrige únicamente la dirección.
- Pendiente de la sesión anterior: desplegar `firestore.rules` (sin eso
  reprogramar/tablas/firmas dan permission-denied en producción; es la causa
  probable del "no me quiere cargar" de la reunión).

- **Cronograma como calendario de verdad** (pedido del 21 sep: "un
  calendario, no algo tan cuadriculado"): `TableCalendar` con un punto por
  visita del color de su estado (rojo = vencida), se toca un día y abajo (o
  al lado, en escritorio) salen sus visitas; "Programar" ya trae ese día
  elegido. El filtro por estado se conserva.
- **Los roles de Visitas se asignan desde Admin → Roles y permisos**, como
  Rutas o Interventoría (matriz central, `TBL_VISITAS_ROLES` con el mismo
  docId `{empresaId}_{userId}` que exigen las reglas). Se quitó la pestaña
  "Roles" del módulo.
- **El "no me quiere cargar" de la reunión era la regla, no el deploy.**
  Se reprodujo el 21 sep en web: `permission-denied` al cargar el formato
  SST aun con las reglas desplegadas. `cargarFormatoSst` (y `getRolUsuario`,
  `ubicacionPara`) hacen `get()` por id de un documento que puede no existir;
  con `resource == null`, `participaEnVisitas(resource.data.empresaId)`
  revienta y niega. Las cuatro colecciones de Visitas separan ahora `get`
  (`resource == null || …`) de `list`, igual que Interventoría desde el 11
  sep. Prueba nueva en `functions/test/visitas_profesionales.rules.js`
  (20/20 en el emulador). **Hay que volver a desplegar las reglas.**

**Inicio por mapa de procesos (reunión)**

- `ProcesoMapa` en `core/app_catalog.dart`: cada módulo declara su franja
  (estratégico / misional / apoyo). En web el inicio pinta tres columnas con
  cabecera, y las tres conservan su lugar aunque la persona solo tenga
  módulos en una; en pantallas angostas van una debajo de otra y en el
  teléfono la franja horizontal respeta el mismo orden. Cuadro
  definitivo de Oscar (21 sep): **Gerencial** = Gerencia; **Misional** =
  Nutrición, Interventoría, Facturación, Rutas, Visitas; **Apoyo** = Talento
  Humano, Correspondencia, Planillas, Compras, Correo, Tokens; **Maestros** =
  Biblioteca documental (y Administración, que él no listó). Mover un módulo
  es cambiar `proceso:` en el catálogo.

**Web: descargar la app (reunión)**

- `core/app_stores.dart` + `widgets/app_store_links.dart`: botones "Descargar
  en Google Play / App Store" **solo en el login** (se quitaron del menú
  lateral el 21 sep: "que no salga tanto ahí como en el home"), solo en web. El de Google Play ya apunta al `applicationId`; el de App Store queda
  vacío (no se pinta) hasta tener el id numérico de la ficha.

**Biblioteca**

- **Vista previa de Word/Excel/PowerPoint** con el visor en línea de
  Microsoft (y el de Google como alternativa) dentro de un iframe en web;
  en el teléfono se abre el visor en el navegador
  (`widgets/office_preview/`). Los PDF siguen igual.
- **"Copiar a otra empresa"** (Oscar: "trasladar toda la documentación de
  una UT a otra"): `GdService.copiarBibliotecaAEmpresa` lleva cada documento
  con su versión vigente como v1 y duplica el archivo en Storage bajo la
  empresa destino; salta los códigos que ya existen, así que se puede
  repetir. Botón en la cabecera de Biblioteca para Admin Documental /
  Desarrollo, con barra de progreso.

**Facturación**

- Obligaciones por establecimiento: cada obligación del maestro dice si
  aplica a todos o a una lista de establecimientos (`establecimientos` en
  `TBL_FAC_OBLIGACIONES`, vacío = todos). Para los que quedan por fuera se
  lee como "no aplica" (`ignoradosEfectivos`), aplicado en
  `streamEstablecimientos`/`getEstablecimiento` para que todas las pantallas
  lo vean igual, sin pisar lo marcado a mano. Pruebas en
  `facturacion_models_test.dart`.

**Correspondencia**

- Al radicar un correo, el diálogo muestra "Así quedará la tarea": título
  (`Responder GD-2026-······: asunto`), descripción, responsable, prioridad,
  vencimiento y aprobación, con el mismo molde que arma el backend.

**Queda por fuera / pendiente de datos**

- Centros de costo: la planta y cada estación como centro independiente es
  configuración en Admin (25 estaciones), no código.
- Usuario ficticio "administrador de bodega" para pruebas: se crea desde
  Talento Humano / Admin.
- Equipo nuevo, accesos al servidor y tokens de Servir: fuera de la app.

## Gerencia: el área sale del responsable, barras por área y PDF con la empresa (25 sep 2026)

Primer módulo de la ronda de correcciones "módulo por módulo".

**El área no conectaba con los filtros.** Los hallazgos que se asignan a una
persona por la matriz de numerales nunca guardan `areaId` ni `dptoEncargado`
(solo los llena la asignación por área, que ya casi no se usa), y la tarea que
nace de un hallazgo hereda ese `areaId` vacío. En Gerencia casi todo caía en
"Sin área" y elegir un área en el filtro no traía nada. Ahora el área se
resuelve en lectura (`lib/gerencia/gerencia_areas.dart`), en este orden:

1. la del **responsable ya asignado** (ficha de la empresa y, si no la trae,
   el área de su cargo en `TBL_CARGOS`);
2. si esa no se conoce, la asignada a mano al hallazgo;
3. si no está asignado, la del responsable que **asigna la matriz** (mismo
   `sugerirResponsable` del tablero, con las reglas guardadas de la empresa).

No se escribe nada en Firestore: Gerencia es de solo lectura y así el informe
sigue a la persona si cambia de área o se reasigna el hallazgo. Un hallazgo sin
asignar muestra "Responsable sugerido por la matriz: X", y el filtro y la
agrupación por responsable lo cuentan con ese responsable. El director de área
se resuelve con el área nueva.

El filtro de área guarda el nombre normalizado (`areaClave`) y ofrece el
catálogo más las áreas que aparecen en los datos: toda área que sale en una
barra se puede elegir. El tablero de tareas de Gerencia usa la misma regla
(área del asignado; si no, la de la tarea) y deja de mostrar ids crudos
(`?? id`) y de filtrar con `areaId ==`.

**Barras por área, no por fecha.** La tarjeta "Visitas realizadas" por semana
pasa a "Hallazgos por área · hallazgos (visitas)": una barra por área, partida
por estado, que responde a todos los filtros; un clic en el área la deja como
filtro. La nota de la tarjeta conserva el total de actas del período (incluidas
las que no dejaron hallazgos). El Excel de visitas suma la hoja "Por área" y el
PDF la tabla por área.

**"12 (3)".** Todo conteo de hallazgos lleva al lado, entre paréntesis, las
visitas en que salieron (visitas distintas: `visitaId`, o sede + fecha en los
manuales): KPI, barras de la gráfica, cabecera del detalle y PDF. Los chips de
sección del detalle dicen "3 (5)" y no "3 · 5", que se leía como el numeral
3.5. Los numerales del acta siguen como "3.5".

**PDF con la empresa.** Los PDF de hallazgos y de visitas llevan en el
encabezado de cada página el logo (`TBL_EMPRESAS.logoUrl`) y el nombre de la
empresa (o los nombres, si el informe mezcla varias; el logo es el de la
empresa activa). Sin logo propio sale sin logo: el de la app no representa a la
empresa (`CompanyBrandingService.loadLogoBytes(fallbackAsset: null)`). Un logo
en un formato que el PDF no lee (SVG) no impide generar el archivo.

Pruebas: `test/gerencia/gerencia_areas_test.dart` y grupos nuevos en
`test/gerencia/gerencia_hallazgos_export_test.dart`.

**Pendiente**: escribir el área del responsable en el hallazgo al asignarlo
(Interventoría) dejaría el dato guardado para otros módulos, pero cambia cómo el
tablero y el panel distinguen "asignado por área"; se deja para cuando se
revise Interventoría.

## Visitas: equipo como maestro, varias fechas, ejecución por secciones y firma desde el módulo del establecimiento (25 sep 2026)

Segundo módulo de la ronda de correcciones.

**Cronograma.** La tarjeta del calendario quedó solo con el calendario y, debajo,
el botón **Agregar visita** (se quitó el botón flotante). El conteo del mes y el
filtro por estado van fuera de la tarjeta.

**No salían los profesionales ni el director.** Tres causas: las tarjetas de área
de Formatos solo contaban a quien ya tenía rol; comparaban el área al pie de la
letra; y Administración no dejaba asignar el rol a quien tenía el área solo en
el cargo ("Asigna primero el área…"), que es la mayoría. Arreglo:

- Pestaña nueva **Equipo** (jefe y Desarrollo), maestro con dos partes:
  - *Personal*: todos los que tienen el módulo Visitas en sus accesos o ya
    tienen rol, con foto, cargo y área (de la ficha o del cargo, vía
    `TBL_CARGOS`). Tarjeta por área con director, profesionales y cuántos
    quedan sin grupo. Cada persona se edita: rol, área y grupo. El jefe da o
    quita el rol Profesional en su área; director (jefe), consulta y firmante
    los asigna Desarrollo o Administración, igual que exigen las reglas.
  - *Grupos y establecimientos*: `TBL_VISITAS_GRUPOS` (nombre, área, centros de
    costo, profesionales). Un profesional queda en un solo grupo de su área.
- `VisitasService.areaParaRol`: el área del rol sale de la ficha o del cargo y
  se lleva al id del catálogo (`TBL_AREAS`), que es el que usan los formatos y
  comparan las reglas. Admin > Roles y permisos lo usa; firmante y consulta ya
  no piden área.
- `areasDeEmpresa` usa `areasUnicas`: nunca un id crudo como nombre.

**Agregar varias visitas de una vez** (`visitas_programar.dart`). Se elige el
profesional y el formato una sola vez, se marcan los días en el calendario y a
cada día se le pone el establecimiento (con "mismo establecimiento para todos").
Los establecimientos del grupo del profesional salen primero (★). En móvil el
diálogo ocupa la pantalla. `programarVarias` valida una vez, escribe en un lote
y manda un solo aviso con las fechas. Probado en el emulador un lote de 12
visitas: no pasa el tope de lecturas de las reglas.

**Formatos por área y cargo.** `VisitaFormato.cargos` (vacío = todo el área).
La lista va agrupada por área con filtro por área y por cargo, 20 por página;
el editor tiene "Cargos a los que aplica". Al programar se propone el formato
que nombra el cargo del profesional, luego el predeterminado
(`formatoPropuesto`).

**Ejecución de la visita.**
- Por secciones (`pasosDeFormato`): una página por sección del acta (máximo 20
  preguntas; una sección más larga se parte) y cada tabla en su página, más la
  página de cierre. Tira de secciones arriba: rojo con cuántas faltan, verde con
  chulo si está completa. Anterior / Guardar avance / Siguiente abajo.
- Bordes: pregunta o fila de tabla con algo pendiente (sin responder, "no
  cumple" sin observación o sin la foto exigida) en **rojo**; completa en
  **negro**. Los campos obligatorios igual.
- **Guardar avance**: guarda el campo a medio escribir, el encabezado y la
  observación general; también al salir de la pantalla. Las respuestas ya se
  guardaban una a una. Se sigue después desde Mis visitas.
- **Plan de acción** de un "no cumple": qué hacer, **área** y **responsable**
  (buscador del personal, primero los del área); el establecimiento es el de la
  visita. Al cerrar, la tarea va a ese responsable con esa área; sin plan, al
  jefe que programó, como antes. El PDF lo pone en "Responsable".
- El responsable del establecimiento se puede **elegir de la lista** del
  personal (primero los del establecimiento).

**Firma desde el módulo del establecimiento.** Rol nuevo **Firmante del
establecimiento** (el administrador que recibe la visita). El profesional, con
el formato completo, toca "Enviar para que firme desde su módulo": queda
`firmanteEstablecimientoId` y le llega el aviso. El firmante tiene la pestaña
**Por firmar**, revisa el resultado y los hallazgos y firma con su firma
guardada o dibujándola; el profesional recibe aviso y cierra. Sigue existiendo
"Firmar aquí" en el equipo del profesional. Cada firma guarda desde qué equipo
se hizo (`dispositivo`) y con qué cuenta (`firmadoPorId`); la tarjeta y el PDF
lo muestran ("Firmó desde su propio módulo" / "en el equipo del profesional").

**Reglas (`firestore.rules`) — hay que desplegarlas**
- `TBL_VISITAS`: el firmante designado lee su visita (y la lista filtrada por
  él) y solo puede estampar `firmaEstablecimiento` con la visita en curso y sin
  firma previa. El profesional puede poner `firmanteEstablecimientoId` y, con
  el contenido ya firmado, cambiar a quién se le pide la firma mientras falte
  la del establecimiento; el contenido sigue congelado.
- `TBL_VISITAS_ROLES` acepta `firmante`; `participaEnVisitas` lo incluye.
- `TBL_VISITAS_GRUPOS`: lee quien participa; escribe el jefe de su área (o
  Desarrollo); el área de un grupo no cambia. Fuera del comodín general.
- Pruebas: `functions/test/visitas_profesionales.rules.js` (7 casos, verdes en
  el emulador; todas las de reglas 35/35).

Pruebas Dart: `test/visitas/visitas_equipo_lote_test.dart`.

**Pendiente / para decidir**
- Un rol de profesional guardado con otra variante del área no lo puede
  corregir el jefe (las reglas solo le dejan su área exacta): se corrige
  volviendo a asignarlo en Admin > Roles y permisos.
- El módulo no da el acceso a la app: si a alguien se le da rol sin tener
  Visitas en sus accesos, el maestro lo avisa y se le da en Admin > Usuarios.

## Compras: Excel de productos separado por marca y proveedor (25 sep 2026)

Consultas > Productos > Exportar traía cada producto en una sola fila con todas
las marcas y todos los proveedores pegados en una celda ("PALMARIUM,
SOLYSOYA…", "LUHOMAR / SAN MIGUEL…"), y para hacer las cartas a proveedores
había que separarlo a mano. El archivo ahora trae dos hojas:

- **Por proveedor** (primera): una fila por producto, marca y proveedor, con
  las columnas de la plantilla de Compras: Nombre, Categoría, Marca,
  Proveedor, Ficha técnica por marca, Registro sanitario, Ficha técnica por
  proveedor. El proveedor sale de las fichas técnicas cargadas para ese
  producto y esa marca (`TBL_COMPRAS_FICHAS_TECNICAS`), que es la única
  relación producto–marca–proveedor que guarda la app. Una marca sin ningún
  proveedor con ficha sale igual, con "Sin proveedor con ficha": es justo lo
  que hay que pedir. El producto sin marca muestra la ficha del proveedor con
  "Sin marca". Los estados son los mismos de la pantalla (Completo, Pendiente,
  Falta, Vencido…) y el registro sanitario lleva su vencimiento.
- **Resumen por producto**: el archivo de antes, un producto por fila.

Las hojas salen con encabezado azul, ancho por contenido, fila de encabezado
fija y filtro en cada columna (`construirExcelHojas`; el paquete `excel` no
sabe poner filtros, así que se escriben en el XML del libro). Lógica en
`filasProductoMarcaProveedor` (`compras_catalog_logic.dart`); pruebas en
`test/compras/compras_productos_por_proveedor_test.dart`.

## 2026-09-23 — Biblioteca documental caía por índice faltante

- `GdService.streamDocumentos` y `streamDocumentosVigentes` ya no usan
  `orderBy('updatedAt')`: esa combinación con el filtro por empresa pedía un
  índice compuesto en `TBL_DOCUMENTOS` que no existe, y la pantalla mostraba
  el error `failed-precondition` en vez de la lista. Ahora se ordena en el
  cliente (más reciente primero; los que no tienen `updatedAt` van al final,
  antes el servidor los ocultaba). No requiere desplegar índices.

## 2026-10-02 — WhatsApp Meta: entrega y avisos automáticos (Codex)

- La WABA activa de la captura está disponible y tiene método de pago. La
  WABA antigua bloqueada no corresponde al número emisor de producción; se
  corrigió `WHATSAPP_WABA_ID` en el `.env` local ignorado por Git. El HTTP 200
  con `wamid` solo acredita aceptación inicial, no entrega.
- La prueba controlada de Admin y Correo envía `hello_world/en_US`, aprobada
  en la WABA activa, para probar fuera de la ventana de conversación de 24 h.
  Los avisos con `templateKey` reconocido usan siempre una plantilla Meta;
  si Meta no la encuentra, queda un error explícito en la auditoría. Las cinco
  plantillas operativas están aprobadas en la WABA activa; Planillas y
  Facturación usan allí el idioma `en`.
- Se añadió webhook de estados firmado con HMAC, conciliación por `wamid`,
  trazabilidad de entregado/leído/fallido por empresa y reglas que reservan
  la auditoría a Admin de su empresa y al servidor. Se añadió el índice para
  ordenar la trazabilidad. La UI distingue aceptación de entrega.
- Validación local: compilación TypeScript, pruebas enfocadas de plantillas y
  webhook, `flutter test test/whatsapp` y análisis estático del panel Admin.
  Las pruebas de reglas quedaron escritas, pero el emulador Firestore no
  arrancó en este equipo por un error de conexión local de Java.
- **Pendiente para producción:** desplegar Functions, reglas, índice y Web;
  sincronizar plantillas de cada empresa en Admin con la WABA activa;
  configurar `WHATSAPP_META_APP_SECRET` y el token de verificación en Functions;
  registrar el callback `whatsappMetaWebhook` y el campo `messages` en Meta
  Developers; suscribir la WABA activa; hacer una nueva prueba y comprobar el
  estado final. No se pueden recuperar estados anteriores sin webhook.
  La prueba visual en Web a 390/768/1024/1366 y con texto ampliado, y las
  pruebas Android/iOS, no se hicieron en este equipo. La citación disciplinaria
  carece de plantilla y su módulo no está habilitado en el servicio central;
  requiere una configuración y aprobación de plantilla aparte.
