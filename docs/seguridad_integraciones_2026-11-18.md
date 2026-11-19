# Seguridad de integraciones y consumo — 18 de noviembre de 2026

La revisión amplía la contención del incidente de Maps a WhatsApp/Meta y a los
accesos de Google. El ajuste de COP 474.615,40 sigue pendiente de Facturación
en el caso 77760956; estas correcciones no cancelan un cargo ya generado.

## Correcciones publicadas

- Los nueve callables de administración de WhatsApp resuelven la persona a
  partir de `userDocId` firmado por Auth v2 y verifican su vínculo con el UID.
  Se eliminó la búsqueda de un administrador mediante `userId` o cédula
  suministrados en el payload, que permitía suplantación desde Auth anónimo.
- Se comprueban la pertenencia, la habilitación global/laboral y los permisos
  de la empresa solicitada. Un administrador de la empresa principal no
  hereda ese rol en una secundaria. Se conservan los roles históricos de
  autoridad en su ámbito; un rol de Desarrollo local no da autoridad global.
- Los envíos, cargas de PDF y operaciones de plantillas de Meta validan HTTPS,
  dominio exacto `graph.facebook.com` y la ruta versionada de mensajes antes
  de adjuntar el token. Se rechazan credenciales en la URL, parámetros,
  fragmentos y redirecciones. Todas esas solicitudes tienen tiempo máximo.
- Publicadas y verificadas ACTIVE las 20 funciones consumidoras, con hash
  `a53d1448dace5ec440e7419c05757f6b2d9383a0`. Alcance: los nueve Admin;
  los cuatro avisos de Planillas/Interventoría/Facturación;
  `comprasNotificarNuevoProveedorWhatsApp`, `thNotificarCitacionDescargos`,
  `mantenimientoOrden`, `correoProcesar`, `correoProcesarHttp`,
  `correoProcesarProgramado` y `correoProbarWhatsApp`.
- El predeploy exigió corregir una declaración de función dentro de un bloque
  en Mantenimiento; ahora es una expresión local equivalente. El autofix del
  lint corrigió únicamente sangría en Interventoría.

## Volumen y coste medidos, sin enviar mensajes

Ventana consultada: 20/oct/2026 04:15:46 UTC a 19/nov/2026 04:15:46 UTC
(19/oct 23:15:46 a 18/nov 23:15:46, Bogotá). La auditoría se recorrió completa
con paginación; se leyeron 2.015 registros, sin teléfonos ni contenidos.

| Medición | Resultado |
| --- | ---: |
| Envíos Cloud aceptados registrados por la app | 2.009 |
| Empresa 001 / Empresa 002 | 1.060 / 949 |
| Máximo diario observado en la app | 167 |
| Mensajes enviados / entregados según Meta | 1.992 / 1.992 |
| Máximo diario según Meta | 165 |
| Coste aproximado de `pricing_analytics` | COP 5.867,44 |

Meta devolvió 29 puntos diarios, desde 20/oct 05:00 UTC hasta 19/nov 05:00 UTC,
y confirmó que la moneda de la cuenta es COP. El último día puede seguir
actualizándose. La diferencia de 17 entre los registros aceptados y la
analítica no está conciliada: no hay confirmaciones por mensaje en la app.
Los importes analíticos deben conciliarse con la factura; un envío aceptado no
prueba entrega ni facturación. Esta consulta no identifica por sí sola el
origen autorizado de cada uso externo del token.

La medición puede repetirse con `node tool/medir_whatsapp.cjs`. Usa la sesión
local de Firebase CLI y el token del servidor en el `.env` ignorado. Solo hace
lecturas y guarda agregados sin credenciales en
`outputs/security/volumen-whatsapp-30-dias.json`. Si alcanza su límite de
20.000 registros declara la lectura incompleta.

## Propuesta de límite, pendiente de decisión

Daniel pidió medir primero y proponer, por lo que **no se activó un tope**.
Se propone un máximo global inicial de **250 intentos diarios de envío por
Meta**, entre todas las empresas, según el día de Bogotá, con alerta a los
**150**. El máximo de la app, 167, deja alrededor de 50 % de margen.

Para aplicarlo sin perder avisos hace falta un contador transaccional antes
de cada salida y una cola persistente de pendientes, con aviso visible al
administrador y tratamiento explícito de reintentos/tiempos de espera.
Los duplicados de un mismo evento requieren una reserva idempotente propia.
Estos mecanismos aún no están implementados globalmente. Un máximo de
mensajes no garantiza un máximo monetario: cambia el precio por categoría y
mercado, y una credencial robada usada fuera del backend evita el contador.

## Cuentas y credenciales: comprobado y pendiente

| Hallazgo | Estado y siguiente acción |
| --- | --- |
| Google, cuenta propietaria | Doble verificación activa desde 9/oct/2025; Authenticator configurado. Un único propietario humano en IAM del proyecto. |
| Sesiones Google | Cinco sesiones mostradas, todas en Colombia: tres Windows y dos Android. Un TECNO KM4 figura inactivo desde 4/sep. Daniel lo reconoce y autorizó cerrar su sesión; Google solicitó una verificación personal antes de permitir continuar. Cierre pendiente de esa verificación. La ubicación mostrada no demuestra quién controló una sesión. |
| Recuperación Google | El correo de recuperación aparece pendiente de verificar. Debe confirmarlo personalmente el propietario; no se solicitó ni copió ningún código. |
| Acceso público IAM | No se encontraron miembros `allUsers` ni `allAuthenticatedUsers` en la política del proyecto. Esto no audita todas las políticas de cada recurso. |
| Cuentas de servicio | Tres cuentas tienen Editor; Appspot y Firebase Admin SDK tienen Token Creator en el proyecto. Revisar dependencias y sustituir por permisos mínimos antes de retirar autoridad. |
| Claves privadas de servicio | Firebase Admin SDK tiene tres claves administradas por el usuario, activas desde abril/mayo de 2025, sin caducidad operativa. Identificar consumidores, reemplazar por identidad administrada y revocar las antiguas de forma controlada. No hay prueba aquí de que esas claves se hayan filtrado. |
| Token de Meta | La auditoría inicial encontró el token en 97 de 122 funciones. El despliegue con el `.env` común deja 98; el empaquetado actual distribuye credenciales globalmente. Hace falta migrar a Secret Manager con vinculación explícita y cuentas de ejecución de mínimo privilegio, y retirar las copias sobrantes. El token no se devuelve al cliente ni se versiona. |
| Permisos del token | `business_management`, `whatsapp_business_management`, `whatsapp_business_messaging` y `public_profile` concedidos. Separar las tareas de administración/analítica de las de envío y revisar permisos al reemplazarlo. No se rotó el token en esta revisión. |
| Webhook Meta | Función ACTIVE, pero faltan App Secret y Verify Token. Falla cerrada; no acepta notificaciones sin firma. Configurar el secreto real desde Meta y completar la suscripción para conciliar entregas. No enviar secretos por chat. |
| Panel empresarial Meta | Sin sesión iniciada en este perfil de Chrome. No se pudieron verificar personas, socios, usuarios de sistema, doble factor, sesiones ni límites de gasto del proveedor. Requiere que el administrador inicie sesión. |
| Lectura parcial de accesos Meta por API | La cuenta empresarial figura `pending_submission` en verificación. La API permite ver tres usuarios de sistema, con roles ADMIN, EMPLOYEE y EMPLOYEE; no devolvió la política de doble factor ni personas. Esa visibilidad no demuestra que no haya personas/otros accesos. El administrador debe identificar los consumidores antes de reducir o revocar el usuario de sistema ADMIN. No se modificó la cuenta empresarial. |
| Escalado de funciones | La lectura inicial encontró 87 funciones sin `maxInstances`. Definir límites por carga y función; un límite de instancias tampoco es un tope de gasto. |

Los presupuestos y avisos de facturación no se deben tratar como cortes
automáticos del consumo. La protección combina restricciones del proveedor,
credenciales aisladas, permisos del servidor, límites efectivos y revisión de
facturación. No se puede garantizar riesgo cero.

## Validación

- TypeScript compilado; lint sin errores, con 50 advertencias existentes de
  estilo/código sin uso. Suite: 345 pruebas aprobadas, cero fallos y una
  omitida porque requiere Firestore Emulator (`talento_personal_import`).
- Regresiones específicas: identidad firmada y UID, rechazo de suplantación en
  los nueve Admin, empresa secundaria, asignación/revocación, inhabilitación
  y destinos maliciosos; `fetch` simulado, sin mensajes reales.
- Los nueve Admin publicados respondieron 401 `UNAUTHENTICATED` sin sesión.
  Esta comprobación no sustituye las pruebas de identidad/permisos ni prueba
  un flujo autenticado real de un administrador.
- La auditoría real de Maps volvió a verificar las restricciones de las
  claves, la clave histórica Android, las tres funciones del servidor,
  Geocoding deshabilitado y las cuotas establecidas.
- Se buscaron los ocho secretos/tokens actuales de integraciones cargados en
  el entorno del servidor dentro de los 32.195 archivos versionados
  disponibles: cero coincidencias. No se imprimieron sus valores. Esta
  comprobación no revisa versiones anteriores del historial de Git.
- No cambian pantallas, catálogos ni roles de módulos. No se probaron sesiones
  administrativas reales ni dispositivos físicos Web/Android/iOS para este
  cambio de backend. No se enviaron WhatsApp reales de prueba.
- Evidencias sanitizadas locales: `outputs/security/auditoria-integraciones-2026-11-18.json`,
  `volumen-whatsapp-30-dias.json` y
  `verificacion-publicacion-integraciones-2026-11-18.json`, además de la lectura
  parcial `auditoria-meta-accesos-2026-11-18.json`. No se versionan
  `.env`, tokens, claves privadas ni registros con teléfonos/contenidos.

Referencias oficiales: [analítica de WhatsApp](https://developers.facebook.com/docs/graph-api/reference/waba-analytics/),
[analítica de precios](https://developers.facebook.com/docs/graph-api/reference/whats-app-business-account/pricing_analytics/),
[protección de claves de cuentas de servicio](https://docs.cloud.google.com/iam/docs/best-practices-for-managing-service-account-keys).
