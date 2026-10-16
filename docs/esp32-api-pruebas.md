# API de pruebas de comunicación ESP32

Petición del usuario: entregar solo URL y token para probar su ESP32, antes
de implementar huella o decidir el módulo. Esta API guarda eventos manuales
de prueba aislados, sin registrar asistencia, identidad ni datos por empresa.

`POST https://us-central1-integra360-94704.cloudfunctions.net/marcacionesPrueba`

Cabeceras: `Content-Type: application/json`, `Authorization: Bearer <token>`.
El token aleatorio del equipo se entrega por separado y no se guarda en Git.

```json
{"tipo":"ENTRADA","dispositivo":"TO-DO-BIO-V1","accion_manual":true}
```

También admite `"SALIDA"`. Respuesta al guardar: HTTP 201 con
`{"ok":true,"modo":"prueba","id":"…","tipo":"ENTRADA","dispositivo":"TO-DO-BIO-V1","duplicada":false,"recibidoEn":"…"}`.
La hora es del servidor. No existe consulta de registros por esta API.

El campo opcional `eventoId` permite reintentar sin duplicar: conservar el
mismo identificador para el mismo evento y usar uno nuevo para cada marcación.
Sin ese campo, cada POST aceptado crea un evento (compatible con el sketch
original). Un reintento devuelve HTTP 200; reutilizarlo con otro tipo, 409.

Errores: 400 JSON inválido/campos adicionales, 401 token inválido o revocado,
403 otro dispositivo, 405 método distinto de POST, 413 más de 2048 bytes,
415 contenido distinto de JSON, 429 límite de 60 eventos/minuto, 503 fallo de
persistencia. Todos los errores controlados incluyen `ok:false`.

Servidor: `functions/src/marcaciones_prueba.ts`, función `marcacionesPrueba`.
La configuración vive en `TBL_MARCACIONES_PRUEBA_DISPOSITIVOS/<sha256(token)>`:
`activo:true`, `modo:"prueba"`, `dispositivo:"TO-DO-BIO-V1"`. Los eventos se
guardan en su subcolección `eventos`. Solo el servidor y operadores con IAM
pueden acceder; las reglas excluyen toda la colección del acceso de clientes.
Para revocar el token, cambiar `activo` a `false` mediante administración del
servidor. El token no caduca automáticamente. Rotarlo requiere crear otro hash
y desactivar el anterior; nunca reutilizar una credencial Firebase de usuario.

Pruebas: `functions/test/marcaciones_prueba.rules.js` ejecutado con emulador
Firestore. Incluye el JSON original, revocación, dispositivo incorrecto,
concurrencia, validación, límite y denegación de acceso directo a Firestore.
La prueba física en la ESP32 queda a cargo del equipo con su WiFi configurado.
