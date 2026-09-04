# Bitácora de Mejoras — Capital USPEC

Registro de cambios ejecutados por sesión de mejora. Objetivo: app nivel
"SAP" — consistencia visual Web/Móvil, módulos conectados, usuarios siempre
con nombre y foto (nunca cédula cruda ni letra suelta).

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
