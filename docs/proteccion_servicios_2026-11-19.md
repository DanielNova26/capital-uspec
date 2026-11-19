# Protección de servicios y consumo — 19 de noviembre de 2026

Estado comprobado en producción el 19/nov/2026. Continúa la contención de Maps
y la [revisión del 18 de noviembre](seguridad_integraciones_2026-11-18.md).
Daniel aprobó 250 intentos diarios entre todas las empresas, confirmó que no
hay otros servidores o scripts externos dependientes y aplazó las
verificaciones personales de Meta y del teléfono TECNO.

## WhatsApp: límite publicado y avisos pendientes

- Máximo **250 intentos de envío por día de Bogotá**, global entre empresas.
  Se reserva cada intento en una transacción antes del POST a Meta. Incluye
  intentos fallidos: una respuesta perdida puede ocultar un envío aceptado.
- Al alcanzar **150**, se crea una notificación dentro de la app para Desarrollo
  global habilitado. El identificador diario evita duplicarla; no utiliza
  WhatsApp para avisar de su propio consumo.
- Al agotarse el cupo, los avisos operativos quedan cifrados en una cola
  privada. Se revisan cada 15 minutos; caducan como máximo a las 48 horas o en
  el vencimiento original si es anterior. Las pruebas manuales con cupo
  agotado se rechazan, sin programarlas para otro día.
- Antes de enviar un pendiente se comprueban nuevamente empresa, módulo,
  configuración, lista/ruta y habilitación del destinatario cuando está
  vinculado a una persona. Facturación comprueba estado y versión; Correo,
  vigencia y respuesta. Una retirada de empresa impide recibir el pendiente.
- Los eventos con identidad estable no vuelven a enviar un POST ya aceptado.
  Un resultado incierto o un envío en curso no se reintenta automáticamente;
  requiere revisión. Esto evita duplicar cargos ante una respuesta perdida.
- Las reglas niegan a todos los clientes, incluido Desarrollo, lectura y
  escritura directa de `TBL_WHATSAPP_COLA` y `TBL_WHATSAPP_CONSUMO`. Admin
  devuelve pendientes solo de la empresa autorizada; el contador global se
  entrega únicamente a Desarrollo global.
- Estado real a **07:48 Bogotá**: **3 intentos** en el día; programador ENABLED,
  última ejecución 07:45, resultado correcto. La consulta completa de registros
  desde 01:00 Bogotá encontró 27 ejecuciones terminadas correctamente y cero
  errores. Son operaciones normales, no mensajes de prueba enviados por esta
  revisión. El día se inicializó con cero intentos históricos al activar el
  control, antes de esos tres intentos.

El límite controla mensajes enviados por este backend, no una suma fija en
pesos. No impide llamadas directas de alguien que disponga del token. El
precio depende de Meta y falta rotar el token; no hay garantía de riesgo cero.
Los estados aceptado, pendiente e incierto no equivalen a entrega confirmada.

## Credenciales y permisos en Google Cloud

- Los dos alias del token Meta están en Secret Manager, vinculados
  explícitamente a **22 funciones** que usan la identidad dedicada
  `whatsapp-runtime@integra360-94704.iam.gserviceaccount.com`, con máximo de
  tres instancias (una para la cola). Sus valores **no se rotaron**.
- Auditoría real: **123 funciones**, cero copias de esos tokens en variables
  de entorno compartidas. Diez paquetes de código actualmente desplegados,
  revisados en memoria: cero archivos privados `.env`/`.secret` y cero
  coincidencias de los tokens Meta actuales. No se auditó todo el historial
  de versiones retiradas ni se afirma que haya sido purgado.
- El predeploy exige identidad, secretos e instancias de las 22 funciones,
  impide reintroducir tokens WhatsApp en `.env` y excluye archivos privados
  del paquete. `.secret.local` también queda ignorado por Git.
- La identidad dedicada tiene acceso a Firestore, objetos del bucket operativo
  y los dos secretos Meta. No administra usuarios Auth ni puede firmar como
  otras cuentas. No tiene claves privadas descargadas.
- La cuenta de ejecución predeterminada perdió Editor y la capacidad global
  de firmar como otras cuentas. Conserva Datastore User, Firebase Auth Admin,
  Firebase Cloud Messaging Admin y Service Usage Consumer; acceso a objetos
  solo del bucket operativo y firma únicamente como sí misma. Auth Admin sigue
  siendo un permiso amplio necesario para la gestión actual de usuarios.
- La cuenta Firebase Admin SDK perdió Token Creator global. Sus **tres claves
  privadas de 2025 quedaron desactivadas**, sin borrarlas. El usuario confirmó
  que no existen otros consumidores externos que las necesiten.
- Las cuentas de infraestructura Compute y Cloud Services conservan Editor;
  no son el runtime de las funciones. Los builds actuales usan Compute.
- No quedaron permisos temporales de suplantación concedidos al propietario
  para las comprobaciones. No existen copias cifradas obsoletas del token en
  `TBL_WHATSAPP_CONFIG`; el modo forzado por servidor impide volver a guardarlas.

Otras seis variables privadas del entorno local siguen fuera de este traslado
a Secret Manager. El aislamiento realizado cubre WhatsApp; no se afirma que
todas las credenciales de los otros proveedores estén aisladas o rotadas.

Publicación comprobada ACTIVE: 21 consumidores con hash
`f3c06629f25cea7a6004693b619e859bed964db3`; la cola, con la comprobación final
de destinatarios, usa `07ee28b9b1137733d361858e2b76e328bfa217ab`.
Reglas de Firestore y programador publicados.

## Meta y cuentas personales

- Doble factor empresarial obligatorio para **Todos**; el panel muestra cero
  personas pendientes entre la única persona administradora. Sin socios
  registrados. No se publicó la app Meta ni se modificó su identidad comercial.
- Evidencia local:
  `outputs/security/meta-doble-factor-todos-2026-11-19.jpg`.
- **Pendiente por decisión del usuario:** introducir personalmente la
  contraseña de Meta para acceder al App Secret. Falta activar la verificación
  criptográfica del webhook, conciliar entrega por mensaje y completar la
  rotación de credenciales. No compartir contraseñas ni códigos por chat.
- **Pendiente por decisión del usuario:** verificación de Google para cerrar
  la sesión antigua TECNO KM4. La doble verificación de Google ya estaba activa.

## Maps y reclamación económica

Se mantienen las restricciones y cuotas documentadas en el
[incidente de Maps](incidente_maps_2026-11-18.md). La auditoría real de claves,
servicios y cuotas volvió a pasar. Geocoding permanece deshabilitado, con
cuotas v3/v4 en cero. Continúa pendiente distribuir Android e iOS; las
versiones antiguas de iPhone pierden mapas hasta actualizar, según autorización.

El último estado confirmado del caso Google **77760956** es su traslado a
Facturación para evaluar un ajuste de cortesía. No consta aprobación de
crédito ni suspensión de cobro. Las correcciones no eliminan el cargo ya
generado. La búsqueda en el buzón conectado no devolvió mensajes del caso;
eso no verifica el estado actual del expediente ni descarta una respuesta
por otro canal.

## Validación y reproducción

- TypeScript compilado; 346 pruebas unitarias aprobadas, cero fallos y una
  omitida por requerir emulador. Lint: cero errores y 49 advertencias existentes.
- Emulador: 11 comprobaciones aprobadas, incluyendo dos empresas concurrentes
  compitiendo por los últimos cupos, siguiente día, deduplicación, respuesta
  perdida, caducidad, contador corrupto y denegación de acceso directo.
- Once verificaciones de permisos en producción: el runtime conserva
  Firestore, Storage, consulta de Auth, validación FCM y firma propia; no puede
  leer el secreto Meta ni firmar como WhatsApp. WhatsApp conserva datos,
  archivos y secreto, pero Auth rechaza su administración con
  `INSUFFICIENT_PERMISSION` (HTTP 400 en ese endpoint).
- No se enviaron WhatsApp ni notificaciones push reales de prueba. FCM se
  comprobó con `validate_only`. No cambió la interfaz ni se creó un módulo;
  no se verificaron sesiones autenticadas ni dispositivos Web/Android/iOS
  físicos en esta etapa.

Comandos de auditoría de solo lectura:

```text
node tool/verificar_seguridad_whatsapp.cjs
node tool/auditar_aislamiento_whatsapp.cjs --packages
node tool/verificar_claves_maps.cjs --cloud --build
node tool/medir_whatsapp.cjs
```

Usan la cuenta previamente autorizada de Firebase CLI. El medidor consulta
Secret Manager en memoria si no existe un token local y solo guarda agregados.
Las evidencias privadas permanecen ignoradas en `outputs/security/`:
`aislamiento-whatsapp-verificado-2026-11-19.json`,
`validacion-identidades-2026-11-19.json` y
`cola-verificada-2026-11-19.json`. No contienen valores de credenciales.
