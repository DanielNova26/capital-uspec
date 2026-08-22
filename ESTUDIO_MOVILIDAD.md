# Estudio de Movilidad — Documentación técnica

Submódulo del módulo **Rutas** que mide automáticamente los tiempos de
desplazamiento desde el **Centro de Operaciones (Cra. 69 #79-11, Bogotá — lat
4.6862937, lng -74.082623)** hacia todos los establecimientos/puntos de
entrega, en distintos días y franjas horarias (hora pico, hora valle, medio
día y fin de semana), para generar evidencia técnica verificable del estudio
de condiciones equivalentes de operación.

Pantalla: **Rutas → Administración → pestaña "Estudio movilidad"** (perfiles
admin, admin+calidad y desarrollador). Vistas: Resumen · Mediciones · Mapa ·
Programación.

---

## 1. Fuentes de información

El estudio combina fuentes **oficiales del Distrito** (con acto
administrativo) y fuentes **comerciales de tráfico en tiempo real**. Cada una
aporta algo que las otras no pueden.

| Dato | Fuente | Endpoint | Naturaleza |
|---|---|---|---|
| Tiempos con tráfico | **Google Routes API** | `routes.googleapis.com/directions/v2:computeRoutes` | Comercial, tiempo real |
| Tiempos (contraste) | **TomTom Routing API** | `api.tomtom.com/routing/1/calculateRoute` | Comercial, tiempo real |
| Incidentes viales | **TomTom Traffic Incidents** | `api.tomtom.com/traffic/services/5/incidentDetails` | Comercial, tiempo real |
| **Obras y cierres autorizados** | **PMT — Secretaría Distrital de Movilidad (SIMUR)** | `sig.simur.gov.co/arcgis/rest/services/PMT/Publicacion_Vigentes_Provisional/MapServer` | **Oficial, con radicado SDM** |
| Ubicación de los puntos | Archivo KML/CSV del estudio | — | Verificado contra fuentes oficiales |
| Ejecución y registro | Cloud Functions (America/Bogota) | — | Servidor, sin intervención humana |

### Obras autorizadas: el PMT de la Secretaría de Movilidad

Es la fuente **más fuerte para defender el estudio**, porque cada obra tiene
respaldo administrativo. El servicio es público y no requiere llave.

- Capas usadas: comités de obra de infraestructura y de servicios públicos
  (punto y tramo vial), eventos y desvíos. Se omiten parques y carga
  extradimensional por no ser pertinentes.
- Filtro de **vigencia**: solo entran las obras activas en la fecha de la
  medición (`FINI <= CURRENT_TIMESTAMP AND FFIN >= CURRENT_TIMESTAMP`).
- Se cruzan con **la geometría de cada ruta** y se deduplican por radicado
  (una misma obra aparece en varios tramos).
- Campos conservados: tramo intervenido, **tipo de afectación** (p. ej.
  "CIERRE DE UN CARRIL"), contratista, localidad, horario de trabajo,
  vigencia y **radicado SDM**.
- Verificado 2026-08-07: **6.096 registros vigentes** (4.046 tramos viales,
  1.780 comités de infraestructura, 238 de servicios públicos, 32 puntos).
  Ejemplo real: *AV Batallón Caldas (AK 50), Puente Aranda, cierre de un
  carril, Metro Línea 1 S.A.S., 22/08/2025 a 20/08/2026, radicado SDM
  202561202472312*.
- Si el servicio distrital falla, la corrida continúa con las demás fuentes.

> **Por qué se conservan las dos fuentes de obras:** el PMT sabe qué obra
> está autorizada y hasta cuándo, pero no sabe que hubo un accidente esta
> mañana ni que hay un trancón. TomTom ve lo imprevisto pero no el acto
> administrativo. Juntas cubren lo programado y lo no programado.

### Fuente evaluada y descartada por ahora

**Malla Vial Integral / Red de infraestructura vial** (Datos Abiertos
Bogotá — SDP, `services2.arcgis.com/NEwhEo9GGSHXcRXV/.../Malla_Vial_Integral_Bogota_D_C`).
Aporta **estado de la vía** (B/R/M/SD), número de carriles, ancho de calzada
y código CIV oficial, y permitiría caracterizar cada ruta por la condición
del pavimento. Se descartó de la integración automática porque el campo de
**velocidad de operación viene vacío** y el de carriles está solo
parcialmente diligenciado, además de ser un dato estático (última
actualización mayo 2026). Queda como fuente de consulta manual para el
anexo del estudio.

## 2. API utilizada

- **Por defecto: Google Routes API** (`routes.googleapis.com` —
  `directions/v2:computeRoutes`), con `travelMode=DRIVE`,
  `routingPreference=TRAFFIC_AWARE_OPTIMAL`, `computeAlternativeRoutes=true`,
  `departureTime=ahora` y `languageCode=es-419`. Entrega: distancia vial,
  **duración con tráfico en tiempo real** (`duration`), **duración sin
  tráfico** (`staticDuration`), descripción de la ruta principal y una alterna.
- **Alternativa configurable: TomTom Routing API**
  (`api.tomtom.com/routing/1/calculateRoute` con `traffic=true` y
  `computeTravelTimeFor=all`), que entrega `travelTimeInSeconds`,
  `noTrafficTravelTimeInSeconds` y `trafficDelayInSeconds`.
- La fuente se elige por empresa en **Programación → Fuente de medición**.
  La API key sale de (en orden): campo `apiKey` de `TBL_RUTAS_MOV_CONFIG` →
  variable de entorno del backend (`functions/.env`:
  `MOVILIDAD_GOOGLE_API_KEY` / `MOVILIDAD_TOMTOM_API_KEY`).

> ✅ Verificado 2026-08-07: la **Routes API ya está habilitada** en el
> proyecto `integra360-94704` y la key configurada en `.env` responde
> (prueba real centro → Engativá: 3,36 km, 735 s con tráfico). Para
> producción se recomienda una key dedicada — ver sección 9.
> Volumen estimado: 26 puntos × 5 horarios × 4 días = **520 llamadas/semana
> (~2.250/mes)**, dentro del nivel gratuito actual de Routes API Essentials.

## 2. Método de cálculo y clasificación

Por cada par origen→destino la medición guarda distancia vial (km), tiempo
con tráfico, tiempo sin tráfico y demora = con tráfico − sin tráfico.

- **Riesgo** (regla del estudio, sobre el tiempo con tráfico):
  0–60 min **bajo** · 61–90 **medio** · 91–120 **alto controlado** · >120
  **crítico**.
- **Estado del tráfico** (demora relativa vs tiempo sin tráfico):
  ≤10 % bajo · ≤25 % medio · ≤50 % alto · >50 % crítico.
- **Alerta**: si el tiempo con tráfico ≥ umbral configurable
  (`umbralAlertaMin`, por defecto **105 min**, "se acerca a las 2 horas"), la
  medición queda marcada, se agrega la observación automática sobre
  conservación segura de alimentos y se **notifica** a las cédulas
  configuradas vía `TBL_NOTIFICACIONES/{cedula}/notifications`.
- **Escenarios**: `pico_manana`, `valle`, `medio_dia`, `pico_tarde`,
  `fin_semana`. Las corridas programadas usan el escenario del horario; las
  manuales lo deducen de la hora Bogotá.

### Los dos tiempos: ACTUAL vs ESPERADO

El estudio no compara "con tráfico" contra "vía vacía", sino **lo que pasa
de verdad ahora** contra **lo que el modelo calcula que debería pasar**. Por
eso las columnas se llaman así en toda la app y en los exportes:

| Columna | Campo de la API | Qué es |
|---|---|---|
| **Actual** | `duration` | Predicción con tráfico **en vivo** del momento de la consulta |
| **Esperado** | `staticDuration` | Tiempo calculado con las **velocidades nominales** de cada tramo, sin mirar el tráfico |
| **Diferencia** | (calculada) | Actual − esperado, **con signo** |

La **diferencia con signo** es el indicador útil: positiva significa que el
trayecto va peor que lo calculado (hay congestión real); negativa, que la
vía fluyó mejor que el modelo. En la app se muestra en naranja o verde según
el caso. La columna formal "Demora por tráfico" del requerimiento se
conserva aparte, nunca negativa.

**Ojo con "Esperado": no es "la vía vacía".** Es un modelo estático de
velocidades por defecto que en las arterias de Bogotá resulta conservador.
Por eso es **normal** que el tiempo actual salga MENOR que el esperado en
festivos, madrugadas y domingos — no es un error de captura.
Comprobación real del 2026-08-07 al centro → USME, con las tres alternativas
que devolvió la API:

| Ruta | Actual | Esperado (nominal) |
|---|---|---|
| Av. 68 (elegida) | 3.240 s (54 min) | 3.526 s (59 min) |
| Cra. 72 y Av. Boyacá | 3.525 s | 3.589 s |
| Av. Cdad. de Quito/NQS | 3.567 s | 3.571 s |

La inversión aparece en **todas** las alternativas, así que no es un
artefacto de la selección de ruta. En esos casos "Demora por tráfico" se
guarda como 0 (no existe demora negativa) y el estado de tráfico queda
"Bajo" — ambas cosas son correctas.

### Condiciones de la vía: obras, cierres y congestión

Cada medición registra **qué estaba pasando en la vía en ese momento**, para
poder explicar por qué una ruta concreta tardó lo que tardó.

- Fuente: **TomTom Traffic Incidents API** (Google no expone incidentes).
  Se consulta **una sola vez por corrida** sobre el recuadro que cubre el
  origen y todos los destinos, y el resultado se cruza con **la geometría de
  cada ruta**: se conservan los incidentes a menos de **150 m del trayecto
  medido**, no los de toda la ciudad.
- La geometría sale de la propia respuesta de ruta: `legs[].points` en
  TomTom y `polyline.encodedPolyline` (decodificada) en Google, así que el
  cruce funciona con ambas fuentes.
- Categorías registradas: **obras en la vía**, vía cerrada, carril cerrado,
  congestión, accidente, vehículo averiado, inundación, clima adverso y
  condiciones peligrosas.
- Por medición se guardan los conteos (`obras`, `cierres`, `congestiones`,
  `accidentes`, `total`, `demoraIncidentesSeg`) y el detalle de hasta 15
  incidentes con descripción, calles de inicio y fin, longitud y demora.
- Si una ruta tiene obras, la **observación automática** de esa medición lo
  dice explícitamente.
- Dónde se ve: columna **"Estado de la vía"** en la tabla (con ícono de
  obras), sección **"Condiciones de la vía sobre esta ruta"** en el detalle,
  cuatro columnas en el Excel y el apartado **"Condiciones de la vía durante
  las mediciones"** en el PDF consolidado.
- Costo: 1 llamada extra por corrida (no por punto), dentro del plan
  gratuito de TomTom. Sin key de TomTom la función se omite y no rompe nada.

> Verificado el 2026-08-07: en ese momento había **30 obras**, 166 vías
> cerradas y 81 congestiones vigentes en Bogotá, con calles y demoras.

### Reintentos ante fallos transitorios

En la primera corrida real fallaron 6 de 26 llamadas a TomTom (~23 %) por
límite de peticiones del plan gratuito. Ahora ambas APIs se llaman con
**hasta 3 intentos y espera creciente** (400 ms → 1,2 s) ante HTTP 429/403
(cuota), 5xx y errores de red. Los errores no recuperables (por ejemplo una
key inválida) fallan de inmediato, sin gastar reintentos.

### Comparativo entre dos proveedores

Para no depender de un solo modelo, el estudio puede medir **cada punto con
las dos APIs en la misma corrida**: Google y TomTom. Se activa en
Programación → **"Medir con las dos APIs (comparativo)"** (requiere la key
de ambas; ver sección 9).

- Se guarda **una medición por fuente**, cada una con su propio JSON crudo.
  El campo `fuentePrincipal` marca cuál alimenta los indicadores.
- **Las alertas y los KPIs salen solo de la fuente principal**, para no
  duplicar conteos ni notificaciones.
- Aparece la sección **"Comparativo entre proveedores"** en Resumen, una
  hoja *Comparativo fuentes* en el Excel y un bloque en el PDF: por punto,
  el promedio de cada API, la diferencia absoluta y porcentual, y el
  promedio de ambas.
- **Valor probatorio:** que dos proveedores independientes coincidan en el
  orden de magnitud es el argumento más fuerte frente a un revisor que
  cuestione los tiempos. Si difieren mucho en un punto, esa ruta merece
  verificación manual.
- **Costo:** duplica las llamadas (26 puntos × 2 = 52 por franja). Sigue
  dentro de los planes gratuitos de ambos proveedores para este volumen.

> TomTom aporta además un *free-flow* real (`noTrafficTravelTimeInSeconds`)
> y un `trafficDelayInSeconds` explícito, así que su columna de demora sí
> tiene valor propio calculado por el proveedor.

## 3. Frecuencia de medición

- Cron **`rutasMovilidadTick`**: corre **cada 5 minutos** en zona
  `America/Bogota` y dispara los horarios activos del día dentro de una
  ventana de 10 minutos, con **candado anti-duplicado** (doc determinístico
  `{empresaId}_{yyyyMMdd}_{HHmm}` en `TBL_RUTAS_MOV_RUNS` creado por
  transacción). **No depende del celular**: todo ocurre en Cloud Functions.
- Horarios sugeridos (botón "Crear sugeridos", editables): **sábado, domingo,
  lunes y martes** a las **06:00, 07:00, 09:30, 12:00 y 17:00**.
- Interruptor maestro por empresa: `TBL_RUTAS_MOV_CONFIG.activo`.

## 4. Estructura de base de datos (Firestore)

Equivalencia con el requerimiento: `route_measurements` →
`TBL_RUTAS_MOV_MEDICIONES`; `measurement_schedules` →
`TBL_RUTAS_MOV_HORARIOS`. Todas las colecciones llevan `empresaId`.

- **`TBL_RUTAS_MOV_CONFIG`** (docId = empresaId): `activo`, `origenNombre`,
  `origenDireccion`, `origenLat`, `origenLng`, `umbralAlertaMin`,
  `alertaCedulas[]`, `fuente` (google|tomtom), `apiKey`, `updatedAt`.
- **`TBL_RUTAS_MOV_HORARIOS`**: `empresaId`, `weekday` (1=lunes…7=domingo),
  `hora` ("HH:mm"), `escenario`, `activo`, `createdAt`, `updatedAt`.
- **`TBL_RUTAS_MOV_MEDICIONES`** (solo las escribe el backend): `empresaId`,
  `runId`, `tipo` (programada|manual), `ok`, `errorMsg`, `fecha`, `hora`,
  `fechaHora` (Timestamp), `weekday`, `weekdayNombre`, `escenario`,
  `origenNombre/Direccion/Lat/Lng`, `puntoId`,
  `puntoNombre/Direccion/Lat/Lng`, `distanciaKm`, `duracionTraficoMin`,
  `duracionSinTraficoMin`, `demoraTraficoMin`, `rutaPrincipal`,
  `rutaAlterna`, `estadoTrafico`, `riesgo`, `alerta`, `fuente`,
  `requestParams` (map con los parámetros enviados), **`apiRawResponse`
  (JSON crudo de la API, evidencia verificable/reproducible)**, `creadoPor`,
  `observaciones`, `createdAt`. Las mediciones fallidas también se guardan
  (`ok=false`) como constancia del intento.
- **`TBL_RUTAS_MOV_RUNS`**: bitácora/candado de corridas: `estado`
  (pendiente|ejecutando|ok|parcial|error|omitida), `totalPuntos`, `exitosos`,
  `fallidos`, `alertas`, `disparadoPor`, `duracionMs`, `inicioAt`, `finAt`.
- **Destinos**: se leen del maestro existente `TBL_RUTAS_ESTABLECIMIENTOS`
  (`activo=true` y con lat/lng). El botón **"Sincronizar puntos del
  KML/CSV"** (Programación) actualiza las coordenadas corregidas del estudio
  (match por nombre) y crea los que falten; el Centro de Operaciones no se
  crea como establecimiento (es el origen y vive en la configuración).

Índices compuestos añadidos a `firestore.indexes.json`:
`(empresaId, fechaHora desc)` y `(empresaId, puntoId, fechaHora desc)` en
mediciones, `(empresaId, createdAt desc)` en runs.

## 5. Cómo ejecutar mediciones manuales

Botón **"Medir ahora"** (barra superior de la pestaña): llama la Cloud
Function `rutasMovilidadMedirAhora` (callable, us-central1) con
`{empresaId, cedula}` y mide todos los puntos activos; también acepta
`puntoId` para un solo destino. La corrida queda como `tipo=manual` con la
cédula de quien la disparó, y aparece de inmediato en Resumen/Mediciones.

## 6. Cómo consultar mediciones históricas

- **Resumen**: última medición, próxima programada, puntos medidos, alertas,
  pico vs valle, promedio por día/escenario/hora, top rutas más lentas,
  rutas críticas y últimas corridas.
- **Mediciones**: tabla paginada filtrable por **punto, día, hora, escenario
  y riesgo** + selector de periodo. Clic en una fila abre el detalle
  completo: fecha/hora exacta, parámetros enviados a la API, resultado,
  clasificación, rutas sugeridas y **JSON crudo** (copiable).
- **Mapa**: origen en violeta y cada punto coloreado por el riesgo de su
  última medición del periodo (verde/amarillo/naranja/rojo).

## 7. Cómo exportar reportes

Menú **Exportar** (vista Mediciones, respeta los filtros activos):

- **Excel** (3 hojas: Mediciones completas · Resumen por punto · Promedios
  por día/escenario/hora + pico vs valle) — incluye las columnas mínimas del
  requerimiento (punto, dirección, fecha, hora, escenario, km, tiempos,
  demora, rutas, riesgo, fuente, observaciones).
- **CSV** (UTF-8 con BOM).
- **PDF**: Resumen ejecutivo · Reporte por punto · Reporte por día ·
  **Consolidado para anexar al estudio técnico** (incluye metodología).

## 8. Despliegue

**Estado: DESPLEGADO el 2026-08-07** — verificado en producción:

| Componente | Estado |
|---|---|
| `rutasMovilidadTick` | v1 · scheduled · us-central1 · 512 MB · nodejs20 |
| `rutasMovilidadMedirAhora` | v1 · callable · us-central1 · 512 MB · nodejs20 |
| Índices Firestore | aplicados (3 nuevos) |
| Hosting web | <https://to-do-gestion.web.app> sirviendo el build con el módulo |
| Routes API | habilitada y respondiendo con la key de `.env` |

El cron ya corre cada 5 minutos; queda inerte hasta que la empresa tenga
configuración y horarios activos (ver sección 10).

Para redesplegar tras cualquier cambio futuro:

```bash
cd functions && npm run build && npx firebase-tools deploy --only "functions:rutasMovilidadTick,functions:rutasMovilidadMedirAhora"
```

```bash
npx firebase-tools deploy --only firestore:indexes
```

Si el cambio es de la app (Flutter), reconstruir y subir hosting:

```bash
flutter build web --no-tree-shake-icons --no-wasm-dry-run && npx firebase-tools deploy --only hosting
```

Las reglas de Firestore están abiertas en desarrollo (las gestiona el
usuario; las colecciones nuevas siguen el mismo patrón `empresaId` de todo
el módulo Rutas).

## 9. API key: cómo se configura y cómo cambiarla (paso a paso)

### Dónde vive la key

Orden de prioridad con que el backend la busca:

Las keys viven **solo en el servidor**, en `functions/.env`:

```
MOVILIDAD_GOOGLE_API_KEY="AIza..."
MOVILIDAD_TOMTOM_API_KEY="..."
```

**No se piden en la app** a propósito: cualquier valor que viaje al
navegador queda expuesto en el bundle. (El modelo de datos todavía admite
`apiKeyGoogle`/`apiKeyTomtom` por empresa en `TBL_RUTAS_MOV_CONFIG` como
mecanismo de emergencia, pero la UI ya no los escribe.)

> ⚠ **El `.env` se empaqueta al desplegar.** Después de cambiar una key hay
> que redesplegar las functions (sección 8) o el servidor sigue con la key
> anterior.

Formato exacto en `functions/.env` (entre comillas, sin espacios alrededor
del `=`):

```
MOVILIDAD_GOOGLE_API_KEY="AIzaSyD8posdo50hmD8PLPD9kR6IebNYfi6PkPs"
MOVILIDAD_TOMTOM_API_KEY=""
```

> ⚠ Los cambios en `.env` **solo aplican al redesplegar** las functions
> (comando de la sección 8). Si necesitas cambiar la key sin redeploy, usa
> el campo de la app (opción 1).

### Estado actual

La key que quedó en `.env` es la misma key de Google Maps del app, y la
**Routes API ya está habilitada y verificada** en el proyecto: no hay que
hacer nada más para que el estudio funcione.

### (Recomendado para producción) Crear una key dedicada solo para Routes API

1. Abrir <https://console.cloud.google.com/apis/credentials?project=integra360-94704>
   (iniciar sesión con la cuenta dueña del proyecto Firebase).
2. Clic en **"+ Crear credenciales" → "Clave de API"**. Copiar la key que
   aparece.
3. Clic en la key recién creada para editarla:
   - **Nombre**: `movilidad-backend` (para identificarla).
   - **Restricciones de aplicación**: "Ninguna" (la usa el backend de Cloud
     Functions, no un navegador ni un APK).
   - **Restricciones de API**: "Restringir clave" → marcar únicamente
     **Routes API** → Guardar.
4. Pegarla en `functions/.env`:
   `MOVILIDAD_GOOGLE_API_KEY="AIza...nueva..."`.
5. Redesplegar (sección 8), o pegarla en la app (Programación → API key
   propia) si se quiere aplicar sin redeploy.
6. Probar con **"Medir ahora"** sobre un punto. Si algo falla, el detalle de
   la medición fallida guarda el error exacto de Google (p. ej. "Routes API
   has not been used…" incluye el link directo para habilitarla).

Si alguna vez la Routes API apareciera deshabilitada:
<https://console.cloud.google.com/apis/library/routes.googleapis.com?project=integra360-94704>
→ botón **Habilitar** (requiere facturación activa, que el proyecto ya
tiene por usar Maps).

### TomTom: segunda fuente para el comparativo

Necesaria si se quiere el contraste entre dos proveedores (sección 2).

1. Crear cuenta gratuita en <https://developer.tomtom.com> — **2.500
   peticiones/día gratis y no pide tarjeta**.
2. Confirmar el correo, entrar al **Dashboard → Keys** y copiar la key por
   defecto (viene con Routing API habilitada). Es una cadena larga
   alfanumérica, sin prefijo.
3. Ponerla en `functions/.env` → `MOVILIDAD_TOMTOM_API_KEY="..."` y
   **redesplegar las functions**.
4. Activar el switch **"Medir con las dos APIs (comparativo)"**. Si falta la
   key en el servidor, la corrida sigue midiendo solo con la principal y lo
   deja anotado en los logs.
5. Probar con **"Medir ahora"**: deben salir 52 mediciones (26 puntos × 2) y
   aparecer la sección "Comparativo entre proveedores" en Resumen.

Verificado el 2026-08-07 con la key en `.env` (centro → USME): 25,87 km,
48,9 min con tráfico, 43,8 min free-flow. Google daba 54 min para el mismo
trayecto: dos proveedores independientes dentro de ~5 min, justo el tipo de
corroboración que busca el estudio.

Para usar TomTom como fuente **principal** en lugar de Google: Programación
→ Fuente de medición → TomTom.

---

## 10. Puesta en marcha en la app (una sola vez por empresa)

Entrar a <https://to-do-gestion.web.app> → seleccionar la empresa →
**Rutas → Administración → pestaña "Estudio movilidad" → Programación**.

1. **"Crear sugeridos"** — crea los 20 horarios del estudio (sábado,
   domingo, lunes y martes × 06:00, 07:00, 09:30, 12:00 y 17:00) **y el
   documento de configuración de la empresa**. Sin este documento el cron
   omite la empresa, así que este paso es obligatorio.
2. **"Sincronizar puntos del KML/CSV"** — hace upsert de los 26 destinos con
   las coordenadas corregidas del estudio sobre
   `TBL_RUTAS_ESTABLECIMIENTOS` (actualiza los existentes por nombre, crea
   los que falten). Después debe leerse "26 de 26 establecimientos activos
   tienen coordenadas".
2b. **"Sincronizar rutas del estudio"** — crea en `TBL_RUTAS` las 10 rutas
   con su secuencia de paradas. **Sin rutas el estudio no puede medir**,
   porque la medición es tramo a tramo sobre ellas. Revisar el resultado en
   la pestaña **Rutas**.
3. Revisar que **"Mediciones automáticas activas"** esté encendido y que el
   origen diga *Centro de Operaciones — Cra. 69 #79-11* con lat `4.6862937`
   y lng `-74.082623`.
4. (Opcional) Agregar en **"Cédulas que reciben las alertas"** a quien deba
   enterarse cuando una ruta llegue al umbral (105 min por defecto).
5. **"Medir ahora"** (botón verde arriba a la derecha) — primera corrida
   manual sobre los 26 puntos. Tarda ~30-60 s. Al terminar muestra
   "X/26 mediciones exitosas".
6. Verificar en **Resumen** que aparezcan los KPIs y en **Mediciones** las
   26 filas; abrir una fila para confirmar que trae el JSON crudo de la API.

Desde ese momento las corridas automáticas quedan solas: el próximo sábado a
las 06:00 (hora Bogotá) empieza la serie histórica sin intervención.

> ⚠ **Las corridas de prueba no son evidencia del estudio.** Una medición
> manual en día no hábil del estudio (o en festivo) muestra tiempos
> atípicamente buenos. Antes de dar por iniciada la serie oficial, conviene
> hacer el reset de la sección 11 para que el histórico arranque limpio.

## 11. Reset de mediciones (borrado profundo)

**Programación → Zona de riesgo → "Borrar todas las mediciones"**.

Borra todo el histórico de `TBL_RUTAS_MOV_MEDICIONES` y la bitácora
`TBL_RUTAS_MOV_RUNS` **de la empresa activa**. Sirve para dejar el estudio
en cero tras las pruebas, sin tener que reconfigurar nada.

- **NO borra**: la configuración (`TBL_RUTAS_MOV_CONFIG`), los horarios
  (`TBL_RUTAS_MOV_HORARIOS`) ni el maestro de establecimientos. Al terminar,
  el estudio queda listo para volver a medir de inmediato.
- **Es irreversible**: una medición no se puede reconstruir después, porque
  depende del tráfico que había en ese instante exacto.
- Por eso el diálogo **exige escribir `BORRAR`** para habilitar el botón.
- Borra por lotes paginados de 400 documentos, así que soporta históricos
  grandes sin exceder los límites de Firestore.
- Está scoped por `empresaId`: no toca los datos de otras empresas.
