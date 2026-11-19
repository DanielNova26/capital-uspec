# Publicación 2.8.39 (93) — 19 de noviembre de 2026

La web general incorpora las correcciones de Mantenimiento y Equipos y el nuevo
flujo de Planeación conectado con Compras. La empresa Demo existente permite
trabajar online con los perfiles y registros de la copia local guardada.

## Datos de la Demo

- Origen: exportación local guardada el 14 de noviembre. No se encontraron
  registros operativos locales posteriores a esa copia.
- Destino: empresa `DEMO_EMPRESA_APP_REVIEW` del proyecto de producción existente.
- 43 cuentas, 14 áreas, cargos, jefaturas y asignaciones de módulos. Conservada
  la contraseña del acceso de Gerencia habilitado previamente online.
- 141 tareas y sus 141 hallazgos; un acta, historiales y notificaciones guardadas.
  Tres archivos conservados: acta PDF y dos evidencias. Los enlaces apuntan al
  almacenamiento online.
- Conservados los registros online existentes; solo se completaron los campos
  ausentes. Las escrituras usan precondiciones para evitar sobrescribir cambios
  concurrentes. Los respaldos y los datos de acceso quedan fuera de Git.
- No se transfirieron sesiones, colas de entrega, eventos de ejecución de
  WhatsApp ni la marca de inicialización del emulador. Se evita reproducir avisos
  históricos y los usuarios inician una sesión propia online.
- Planeación habilitada en la Demo: Gerencia y director de Planeación como
  administradores; coordinador y analista de Planeación como planificadores;
  coordinador y analista de Logística como bodega. Los otros módulos conservan
  los niveles locales. No se habilita Planeación automáticamente en otras empresas.
- Sin correos registrados en estas cuentas. El Excel de entrega indica
  «Sin registrar»; contiene usuarios numéricos, contraseñas y 148 asignaciones.
  No se incluyen contraseñas ni datos de acceso en el repositorio.

## Publicación y validación

- Web 2.8.39+93 en el hosting general. Publicadas `planeacionOperar`,
  `mantenimientoInventario`, `mantenimientoOrden`, `adminSincronizarMaestros` y
  `adminLimpiezaModulo`; índices publicados sin eliminar índices existentes.
- Reglas Firestore activadas y comparadas con la fuente compactada.
  Los tres auxiliares exclusivos de equipos se movieron dentro de su `match`,
  conservando sus condiciones y reduciendo los ámbitos que hereda el compilador.
  Se verificó la activación aun cuando la API respondió 503 durante un intento.
  [Referencia del compilador](https://firebase.google.com/docs/rules/rules-language#expression_complexity_and_compiler_limits).
- TypeScript y lint de los archivos afectados aprobados; 33 pruebas unitarias
  de backend y 77 de Flutter aprobadas. Reglas: 14 aprobadas, cero fallos y dos
  omitidas por su configuración. Guardas de WhatsApp y auditoría de Maps aprobadas.
- Ingreso online comprobado para las 43 cuentas. Libro Excel exportado y ambas
  hojas revisadas visualmente.
- Comprobación posterior a la carga: los 822 documentos de la fuente existen
  online. Verificados los tres adjuntos por descarga y SHA-256, y la versión,
  `index.html` y `main.dart.js` en ambos dominios de producción. Con tokens de
  cliente reales se probaron la lectura de ficha, los niveles de Planeación de
  Gerencia/director, catálogos y tareas de Mantenimiento y consulta de actas del
  registrador. Durante el arranque hubo respuestas temporales de falta de
  instancia; las comprobaciones finales terminaron correctamente.
- Android firmado y validado con Bundletool y Jarsigner; versión 2.8.39,
  código 93 y mismo certificado de distribución que la versión 92.
- Archivo: `outputs/android/to-do-gestion-2.8.39-93.aab`.
  SHA-256: `bf85205191766c5c047fbe0df398e2cb03d46c882a43f65ce2c0eeb8285b0f1c`.
- El AAB queda listo para cargar en Play Console. Generarlo no lo publica en la
  tienda. No se generó una compilación iOS ni se verificaron dispositivos físicos.

Los reportes técnicos, respaldos y credenciales se conservan en `outputs/`,
excluido del control de versiones. Los datos locales originales se conservan.
