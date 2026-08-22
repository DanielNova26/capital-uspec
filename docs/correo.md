# Módulo Correo

## Alcance

`Correo` conecta varios buzones personales Gmail por empresa, clasifica los
mensajes con reglas de palabras clave y crea alertas de WhatsApp mediante un
proveedor desacoplado. La clasificación descarga únicamente metadatos de Gmail
(remitente, asunto y fecha): no lee ni almacena el cuerpo o los adjuntos.

Las reglas admiten tres tipos de filtro:

- simple por palabra, evaluada exclusivamente en el asunto;
- simple por remitente;
- combinado, que exige a la vez palabra en el asunto y remitente.

El módulo también presenta un consolidado diario por categoría y remitente.

## Configuración inicial

1. En Administración, active `Correo` (`correodashboard`) para el usuario con
   el interruptor de visibilidad de la matriz de accesos — eso solo controla
   si ve el ícono del módulo.

   El rol dentro del módulo (que también gobierna Clasificar y asignar en
   Correspondencia — son la misma colección, `TBL_CORREO_ROLES`) se asigna
   aparte, en **"Roles de Correspondencia"** (botón en Catálogos y en el panel
   de Correo). Los roles, de menor a mayor alcance:
   - `visor`: consulta el resumen y la bandeja.
   - `operador`: además trabaja lo que le asignan (responde, reporta avances,
     termina lo suyo). Es el rol por defecto de quien no tiene uno explícito.
   - `clasificador` ("Clasificador y asignador"): además decide qué es cada
     documento, a quién se asigna y para cuándo. Sin este rol, el botón
     "Clasificar y asignar" no aparece ni en Correo ni en Correspondencia.
   - `administrador`: además administra filtros, buzones, el maestro de tipos
     documentales y puede cerrar cualquier expediente, no solo el propio.

   Un usuario sin rol explícito en `TBL_CORREO_ROLES` cae en `operador`: puede
   trabajar lo que se le asigne, no clasificar ni asignar.
2. Copie `functions/.env.example` a su archivo de variables seguro y configure
   los valores descritos allí. No suba esas variables a Git.
3. Despliegue las Functions. El cron `correoProcesarProgramado` se ejecuta cada
   cinco minutos y el endpoint manual queda publicado mediante `POST /correo/procesar`.

## Gmail personal

En el mismo proyecto de Google Cloud de Firebase:

1. Habilite **Gmail API**.
2. Configure la pantalla de consentimiento OAuth.
3. Cree una credencial OAuth de tipo **Aplicación web**.
4. Registre exactamente el valor de `GMAIL_OAUTH_REDIRECT_URI` como URI de
   redirección autorizado.
5. Configure `GMAIL_OAUTH_CLIENT_ID`, `GMAIL_OAUTH_CLIENT_SECRET` y
   `CORREO_TOKEN_ENCRYPTION_KEY` en Functions.

Desde **Administración > Correo**, cree un buzón y pulse **Conectar Gmail**. Cada persona autoriza
su propia cuenta `@gmail.com`; no se usa delegación de dominio. Por defecto, la
primera revisión registra los mensajes que ya estaban en la bandeja sin alertar
para evitar una avalancha inicial. Se puede activar `Procesar correos existentes`
al crear el buzón si se desea el comportamiento contrario.

## Microsoft 365 multiempresa

La aplicación **Integra360 Correo** de Microsoft Entra debe configurarse con el
tipo de cuenta **Cuentas de cualquier directorio organizacional
(multiinquilino)**. El backend usa la autoridad OAuth `/organizations`, por lo
que cada buzón se autentica en su tenant de origen y no necesita agregarse como
usuario invitado al tenant de Capital USPEC. No se admiten cuentas personales
de Microsoft.

El mismo `MICROSOFT_OAUTH_CLIENT_ID`, secreto y URI de redirección sirven para
los buzones empresariales autorizados. Si el tenant externo restringe el
consentimiento de aplicaciones, su administrador deberá aprobar los permisos
delegados `User.Read`, `Mail.ReadWrite`, `Mail.Send` y `offline_access`.

## Separación operativa

- **Correo** contiene únicamente el resumen diario, la bandeja y los filtros.
- **Administración > Correo** centraliza buzones, OAuth, estado técnico y
  procesamiento manual.
- **Administración > WhatsApp** centraliza la conexión, las listas, los números
  destinatarios, los módulos autorizados y la trazabilidad de los envíos.
- Cada filtro de Correo selecciona una lista habilitada para el módulo; los
  contactos y teléfonos de esa lista sólo se editan en Administración.

## OpenWA

OpenWA se configura como proveedor inicial:

```env
WHATSAPP_PROVIDER=openwa
WHATSAPP_API_BASE_URL=https://openwa.midominio.com/api
WHATSAPP_API_KEY=<api-key-con-permiso-de-envío>
WHATSAPP_SESSION_ID=<id-de-la-sesión>
WHATSAPP_DEFAULT_COUNTRY_CODE=57
```

El adaptador invoca:

```http
POST {WHATSAPP_API_BASE_URL}/sessions/{WHATSAPP_SESSION_ID}/messages/send-text
X-API-Key: {WHATSAPP_API_KEY}
Content-Type: application/json

{"chatId":"573001234567@c.us","text":"..."}
```

Use una API key dedicada y con el mínimo privilegio posible. Con las variables
actuales todas las empresas comparten una sesión WhatsApp. Si cada empresa debe
usar su propio número emisor, el siguiente paso es añadir una configuración de
sesión por empresa protegida por secretos de backend.

`WHATSAPP_PROVIDER=openclaw` activa el adaptador HTTP genérico con payload
estándar. `whatsapp_cloud` está declarado como punto de extensión, pero se deja
sin implementar a propósito hasta definir sus credenciales y plantilla oficial.

## Directorio y mensajes de WhatsApp

**Administración > WhatsApp** permite construir listas desde el directorio de
la empresa activa. El directorio combina el usuario y su hoja de vida, busca de
forma inmediata por nombre, cédula, correo o celular y nunca devuelve personas
de otra empresa. Un número que no exista también puede agregarse manualmente.
Los destinatarios elegidos desde Talento Humano conservan su `personaId` y el
origen `directorio` para distinguirlos de los registros manuales.

El editor de mensajes administra por empresa:

- la visibilidad del emoji empresarial;
- la visibilidad del nombre de la empresa;
- la plantilla de alertas filtradas de Correo;
- la plantilla de Compras para proveedores nuevos.

El emoji del encabezado se escribe directamente en este editor y se guarda en
`TBL_EMPRESAS.notificacionEmoji`. Es el mismo valor de `Editar empresa`, por lo
que ambos editores quedan sincronizados. Al cambiarlo o borrarlo, la vista
previa y los mensajes nuevos usan exactamente el valor guardado.

Las variables como `{asunto}`, `{remitente}`, `{proveedor}` o `{nit}` se
resuelven exclusivamente en el backend. Si una plantilla se desactiva, se usa
el mensaje estándar del módulo. La trazabilidad conserva el texto final que se
entregó al proveedor de WhatsApp.

## Trazabilidad e idempotencia

- `TBL_CORREO_MENSAJES`: cada Gmail message ID se procesa una única vez por buzón.
- `TBL_CORREO_ALERTAS`: cada mensaje, regla y teléfono tiene una reserva única
  antes de llamar a OpenWA.
- `TBL_CORREO_EJECUCIONES`: conserva el resumen de cada ejecución.

Las alertas fallidas por desconexiones temporales de OpenWA se reintentan de
forma automática con espera progresiva. Una alerta que queda en `enviando` por
una interrupción también se recupera; la clave única impide duplicar envíos.

Los refresh tokens de Gmail se cifran con AES-256-GCM antes de escribirse en
`TBL_CORREO_CREDENCIALES`. Antes de producción se deben endurecer las reglas
globales de Firestore: las actuales permiten acceso a cualquier usuario
autenticado y no deben ser la política final para un módulo con credenciales.
