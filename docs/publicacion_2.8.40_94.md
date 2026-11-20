# Publicación 2.8.40 (94) — 19 de noviembre de 2026

La versión incorpora los ajustes adicionales de Equipos y Mantenimiento:
rangos de fechas en inventario y consultas, columnas independientes en bajas
y movimientos, foto junto al resumen del equipo y reorganización de actas PDF.

## Web y servidor

- Publicado primero `mantenimientoInventario` y después el cliente Web.
  La función está `ACTIVE`, versión 4, actualizada el 19 de noviembre a las
  21:13 de Bogotá. La fuente compilada descargada del despliegue coincide con
  la local (SHA-256
  `b97c7c036f17c7b268d81fc31b44be7e349152a31fe09b8148bf0ffeda7b0ff5`).
- Una llamada sin sesión fue rechazada como `UNAUTHENTICATED`. No se alteraron
  maestros, asignaciones, permisos, reglas ni índices durante la publicación.
- Ambos dominios, `to-do-gestion.web.app` y `to-do-gestion.firebaseapp.com`,
  sirven la versión 2.8.40, build 94. Se compararon `index.html` y
  `main.dart.js` publicados con los archivos locales. SHA-256 del JavaScript:
  `9f4462eaa8bd847935189d7a53dd7863332e173cfd57cf1fca3cd16f7e8e15ea`.
- Aprobados los controles de publicación de Maps y de secretos/identidades de
  WhatsApp. Se conserva el aislamiento y las restricciones existentes.

## Android

- AAB release generado: `outputs/android/to-do-gestion-2.8.40-94.aab`.
- Paquete `com.todogestion.app`, versión 2.8.40, código 94, comprobados con
  Bundletool. Archivo de 155.093.114 bytes; integridad del bundle y firma del
  archivo aprobadas con Bundletool y Jarsigner.
- Certificado de distribución idéntico al de la versión 2.8.39 (93).
- SHA-256:
  `65ee23ee5313461249beb4cdf8cf4dc1a5247a68cade4469be6df586c0753306`.
  Se conserva también el archivo `.aab.sha256` junto al binario.
- Listo para cargar en Play Console. No se publicó en la tienda.

## iOS y Git

Por indicación del usuario, para iOS se sube el código y la versión a `main`
para sincronizarlos desde su Mac. No se realizó acceso remoto a la Mac, no se
generó IPA y no se subió una compilación a TestFlight o App Store Connect.
`Info.plist` toma nombre y número de versión de los marcadores de Flutter que
se generan desde `pubspec.yaml`.

## Validación y límites

Los cambios funcionales publicados se validaron con 58 pruebas Flutter,
11 pruebas de servidor/permisos en emuladores, análisis Flutter y TypeScript.
Se revisaron capturas con texto al 160 % en 390, 768, 1024 y 1366 píxeles,
perfiles Android/iOS separados y actas PDF compactas y extensas renderizadas.
La Web release se compiló para esta versión con las dependencias bloqueadas.

Queda la prueba de los ajustes con sesión real en navegador y dispositivos
Android/iPhone, incluidas fechas y descarga/compartir PDF. Generar el AAB no
publica la actualización en Google Play. No se anunciaron versiones móviles
disponibles en el control de actualización de la app.

Los archivos binarios, registros de compilación, verificaciones y respaldos se
conservan fuera de Git en `outputs/publicacion-2.8.40-94` y `outputs/android`.
