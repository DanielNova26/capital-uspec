# Biométrico — módulo independiente

Identificador de app: `biometricodashboard`. Consume los colaboradores habilitados de Talento Humano; no duplica personas. Los permisos, dispositivos, horarios, jornadas y decisiones pertenecen a la empresa activa.

## Puesta en marcha

1. En **Admin → Apps, roles y permisos → Biométrico**, crea los roles iniciales y asigna el nivel correspondiente. Consulta solo lee; Gestión de asistencia programa jornadas, corrige y aprueba/rechaza extras; Administrador también administra equipos, credenciales y vínculos de huellas. Tener Talento Humano no concede este nuevo módulo. Un acceso sin nivel empieza en Consulta.
2. En el inicio abre **Biométrico → Dispositivos → Nuevo dispositivo**. Escribe nombre y sede y descarga `config_local.h`. El token solo se muestra al crearlo o renovarlo. Renovar invalida inmediatamente el anterior.
3. Copia ese archivo junto a `firmware/ToDo_Bio/ToDo_Bio.ino`, completa `TODO_WIFI_SSID` y `TODO_WIFI_PASS`, abre el `.ino` en Arduino IDE y cárgalo tú mismo al ESP32. No publiques `config_local.h`.
4. Crea **Mi PIN** y registra la huella desde la pantalla del equipo con identificación del administrador, selección de persona, aceptación y tres capturas. Para una huella que ya existe físicamente usa **Huellas y personas → Vincular huella existente**. La misma posición en otro equipo corresponde a un vínculo distinto. La autorización firmada se conserva físicamente en TH; el registro táctil conserva además su aceptación en pantalla.
5. En **Horarios**, crea una plantilla, selecciona al colaborador y asigna fechas y días de semana (máximo 31 días por operación). El botón **Nocturno 21:00–06:00** propone el turno pedido. Configura el descanso real de la empresa; no se presume un descanso por defecto. Para días de descanso laboral asigna una plantilla **Día libre**.
6. En **Jornadas**, consulta hasta 31 días y revisa incidencias antes de decidir las horas extras. Puedes filtrar por colaborador y exportar CSV. Las correcciones manuales y anulaciones requieren motivo y conservan auditoría. Los registros originales no se borran.

## Arduino

Placa objetivo: **ESP32-S3 N16R8**, Arduino ESP32S3 Dev Module; flash 16 MB, PSRAM OPI. Monitor serie 115200. Bibliotecas: Adafruit GFX, Adafruit ST7735 and ST7789, Adafruit Fingerprint Sensor Library y ArduinoJson 7.

La pantalla ST7789 usa SPI de hardware (`TFT_SPI_HARDWARE 1`; valor 0 permite volver al software): CS10, DC9, MOSI11, CLK12, RST8; `init(240,320)`, rotación 1, inversión desactivada. Lector SFM-V1.7 en UART115200: RX17 recibe TX del sensor y TX18 va al RX del sensor. Se conserva el montaje probado por el usuario; no se cambia alimentación ni cableado.

**Registro en la pantalla táctil (firmware 2.4.0).** Requiere el táctil XPT2046 (T_CLK→GPIO4, T_DIN→GPIO5, T_DO→GPIO6, T_CS→GPIO7, T_IRQ→GPIO15) y la biblioteca XPT2046_Touchscreen. En el primer arranque pide tocar cuatro cruces y guarda la calibración (comando serie **T** para repetirla). Antes, cada administrador de Biométrico crea su PIN de 6 números en **Dispositivos → Crear mi PIN** (no se aceptan repetidos ni consecutivos; 5 fallos bloquean 15 minutos). En el equipo: **REGISTRAR HUELLA** → cédula y PIN del administrador → cédula de la persona → confirmar el nombre → la persona acepta el aviso (**Autorizo / No autorizo**) → tres toques del dedo (los dos primeros crean la plantilla y el tercero la verifica) → el servidor la vincula y guarda la aceptación en pantalla. Si el servidor rechaza el vínculo o la verificación falla, la plantilla se borra del sensor. La sesión del administrador dura 5 minutos. Al marcar, la pantalla saluda con el nombre (bienvenida en entrada y despedida en salida). Los botones ENTRADA/SALIDA también son táctiles.

Registro por el monitor serie (alternativa técnica, escribir y Enter): **N** guarda una huella nueva en la primera posición libre del sensor; **N5** la guarda en la posición 5 si está libre. La TFT guía tres pasos (apoyar, retirar, apoyar de nuevo). **B5** pide confirmar con **SI** en 15 segundos y borra esa posición del sensor. Registrar no autoriza marcar: la posición debe vincularse después en **Huellas y personas** con su soporte de autorización; sin vínculo el servidor rechaza la marcación (422). Si se borra una posición, retira también su vínculo en la app. No se envían imágenes ni plantillas.

Comandos de una letra: **E** entrada, **S** salida, **C** capacidad real, **I** estado, **W** reconectar WiFi, **H** ayuda, **Q** exportar al monitor serie eventos pendientes/rechazados, **R** reintentar rechazos después de corregir su causa. Los botones dibujados en la TFT son visuales: no hay táctil conectado. La lectura ocurre automáticamente al apoyar una huella enrolada; debe retirarse antes de repetirla.

La primera marcación tras reiniciar necesita sincronización NTP; sin reloj válido se informa que no se guardó. Tras sincronizar, la desconexión WiFi conserva hasta **32 eventos** en NVS, incluso si se reinicia. La captura indica “guardada local / pendiente”; solo una respuesta válida del servidor confirma recepción. Si se llena la cola o falla la escritura, se informa “NO se guardó”, sin sustituir eventos. Una tarea separada envía por HTTPS con verificación de certificados y hostname, sin bloquear la lectura del sensor. Reintenta con el mismo identificador y espera creciente hasta 60 segundos.

Los errores transitorios conservan la cola. Los rechazos 400/409/422 se conservan para conciliación y no detienen los demás eventos. **Q** permite recuperarlos; **R** conserva fecha e identificador originales. Un rechazo por reloj incorrecto, persona inactiva o vínculo posterior a la captura requiere revisar el caso y, si corresponde, registrar una corrección manual con motivo. No borrar NVS ni cambiar de empresa un equipo con eventos pendientes sin conciliarlos. Revocar/renovar el token no cambia el identificador del equipo ni borra la cola.

La capacidad y ocupación proceden de `getParameters()` y `getTemplateCount()`. `N/D` indica consulta fallida, no capacidad cero. El sensor conserva las plantillas; la API solo recibe el número de posición, nunca imágenes o plantillas biométricas.

## Cálculo de tiempo

- Zona operativa: Colombia, UTC−05:00. Jornada agrupada por fecha de entrada; un turno 21:00–06:00 dura 540 minutos antes de descontar descansos. Una nueva entrada durante la madrugada del mismo turno conserva la jornada anterior.
- Se emparejan entradas y salidas, incluidas varias parejas en una jornada. El descanso programado se descuenta únicamente cuando se superpone con tiempo marcado; no se descuenta otra vez cuando ya se registró salida y entrada para el descanso.
- Tiempo ordinario: tiempo marcado dentro del horario, descontado el descanso. Tiempo fuera del horario: propuesta de extras. En un día libre todo el tiempo trabajado se propone para revisión. Sin horario no se presume jornada ni se autorizan extras.
- Entradas duplicadas, falta de salida, salida sin entrada, duración mayor de 24 horas y ausencia de marcaciones quedan como incidencias. No admiten aprobación hasta resolverlas.
- Las aprobaciones identifican la versión calculada, autor, fecha y motivo. Si cambian marcaciones o jornada asignada, la decisión anterior queda no vigente y los minutos aprobados vuelven a cero hasta una nueva revisión.
- Editar una plantilla no modifica las asignaciones anteriores. Reasignar explícitamente un horario sí cambia esa jornada y exige revisar decisiones afectadas.
- Es un control operativo de duración y aprobación. **No calcula valores de nómina, recargos nocturnos/dominicales/festivos ni topes legales semanales**. El horario configurado no certifica cumplimiento legal ni convierte automáticamente todo exceso en una obligación de pago.

## API

URL: `https://us-central1-integra360-94704.cloudfunctions.net/biometricoDispositivo`

`POST`, `Content-Type: application/json`, `Authorization: Bearer <token exclusivo del equipo>`.

```json
{
  "accion": "marcacion",
  "deviceId": "ID_ENTREGADO_POR_BIOMETRICO",
  "eventoId": "identificador-unico-y-persistente",
  "slot": 1,
  "tipo": "ENTRADA",
  "capturadoMs": 1792101600000
}
```

El timestamp del ejemplo es ilustrativo; el equipo debe enviar la hora real de captura. El servidor determina empresa, sede y colaborador desde la credencial y el vínculo vigente. Rechaza campos adicionales, personas inactivas, eventos previos a la vinculación, fechas futuras mayores de un minuto y capturas de más de 31 días. No acepta el token `tdp_` de la antigua API de pruebas. Respuestas: 201 guardado; 200 repetido idéntico/heartbeat; 401 token; 403 módulo deshabilitado; 409 mismo id con otros datos; 422 vínculo/hora/persona; 429 límite; 503 reintentar conservando id. Máximo 60 solicitudes nuevas por minuto y dispositivo.

Heartbeat cada 15 segundos: `accion`, `deviceId`, `capacidad`, `usadas`, `firmware`; capacidad/ocupación pueden ser `null`. Las credenciales se guardan solo como hash en servidor. Las colecciones operativas y sus subcolecciones niegan acceso directo de clientes; la app usa `biometricoGestion`, con sesión segura, empresa, app y nivel verificados en servidor.

## Gobierno y validación

Los horarios se editan en Biométrico. **Admin → Maestros por módulo** permite copiar solo plantillas de horario agregando lo que falta; no copia personas, dispositivos, tokens, vínculos, marcaciones, asignaciones ni aprobaciones. La limpieza de Biométrico solo contempla el maestro de horarios: conserva asistencia y auditoría.

Índices: empresa/fecha de captura en eventos; empresa/día en jornadas y aprobaciones. Las consultas se acotan al periodo e incluyen margen para turnos nocturnos. Las pruebas de servidor usan exclusivamente emuladores y no crean asistencias ni personas en producción.

Pendiente de aceptación física: carga en el ESP32 del usuario, lectura real del lector y TFT juntos, latencia, reinicio con cola, corte WiFi durante un envío y conciliación posterior. Las pruebas de widgets Android/iOS no sustituyen la verificación en teléfonos físicos, permisos y descargas reales. En Windows no se compila iOS.

Referencias técnicas del transporte: [Preferences de Espressif](https://docs.espressif.com/projects/arduino-esp32/en/latest/api/preferences.html), [certificados raíz de Google Trust Services](https://pki.goog/repository/), [ArduinoJson 7](https://arduinojson.org/v7/api/json/deserializejson/).


## Eliminar una huella del módulo y del lector (2.7.2 / firmware 2.4.0)

En **Dispositivos → Huellas y personas**, busca a la persona y pulsa la papelera
**Eliminar huella**. Indica motivo y escribe `ELIMINAR`. Solo el administrador de
Biométrico de esa empresa puede hacerlo. También permite eliminar vínculos antiguos inactivos.

La solicitud bloquea inmediatamente nuevas marcaciones de esa huella y crea una
orden persistente bajo el dispositivo. La lista muestra **Borrado pendiente del lector**
y se actualiza cada cinco segundos. Si el equipo está desconectado o conserva un
firmware anterior, la orden sigue pendiente; no se declara un borrado físico inexistente.
Actualiza el firmware conservando su `config_local.h` y la memoria NVS.

El heartbeat entrega `comando: {id, tipo: "eliminarHuella", slot}`. El firmware lo
procesa en el bucle principal para no mezclar órdenes UART con capturas o registros.
Exige respuesta correcta de `deleteModel`, guarda el identificador confirmado en NVS
y envía `{accion: "confirmarBorrado", deviceId, comandoId}` por la misma API y token.
Solo entonces se elimina el documento de vínculo; no queda un perfil inactivo en la
lista. Se conserva la orden completada y la auditoría del borrado, así como las
marcaciones históricas. No se elimina la ficha del colaborador de Talento Humano.

La posición no puede volver a vincularse mientras exista borrado pendiente. Los
reintentos del ACK, incluso tras reasignar una posición, no eliminan un nuevo vínculo.
El firmware conserva el último identificador completado para no repetir un borrado
confirmado después de un reinicio. Mientras confirma la orden, pausa la interacción
con el lector. Un fallo del sensor se reintenta sin fingir confirmación.

Compilación verificada con ESP32 core 3.3.12, ESP32S3 Dev Module, flash 16 MB,
PSRAM OPI, CDC activado, XPT2046_Touchscreen 1.4.0 y ArduinoJson 7.4.3.
La prueba física de borrado, reinicio y desconexión WiFi corresponde al equipo real.
