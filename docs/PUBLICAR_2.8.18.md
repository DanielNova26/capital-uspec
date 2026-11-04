# To-Do Gestión 2.8.18 (72) — 4 de noviembre de 2026

Publicación Web de las correcciones de numerales de Interventoría, selección
y copia de textos de Documentos pendientes, estado vacío de Vincular hallazgos
y exclusión de personal inactivo de listas operativas y permisos.

La versión común en `pubspec.yaml` es `2.8.18+72`. La Web se genera con
`flutter build web --release`; `tool/verificar_build_web.js` comprueba la
coincidencia de versión y compilación antes del Hosting.

Destino: [To-Do Gestión](https://to-do-gestion.web.app), proyecto Firebase
`integra360-94704`, sitio Hosting `to-do-gestion`.

Firebase confirmó la publicación del Hosting. La consulta pública a
`version.json` responde versión `2.8.18`, compilación `72`. Se comprobaron los
SHA-256 de los archivos servidos contra la compilación local:

- `main.dart.js`: `ca96980bdd4a40c72fe3c1f5a640d06fc08628a5c132493cb32e0605bba9a86f`.
- `flutter_bootstrap.js`: `02a3e36b4dda15adfd52935fc5484f556a803e1690ad34e4470de9e841dc1527`.

El backend incluye las reglas Firestore y las funciones que consumen los
auxiliares modificados de acceso y textos/sincronización de Interventoría.
El despliegue no ejecuta consolidaciones ni reparaciones de datos históricos.

Reglas publicadas y 78 funciones actualizadas. Se resolvieron los límites
temporales de cuota y los fallos de arranque mediante reintentos de los
destinos pendientes; Firebase confirmó el último despliegue completo.
La verificación final encontró las 78 funciones en estado `ACTIVE`, todas con
hash de código `4641f2868f9edb23860b2bf9468a32a8d6c1129a`.
La revisión de publicación pasó sin errores de lint; permanecen 38
advertencias anteriores. Se completaron los JSDoc exigidos por ese control.

Esta entrega corresponde a Web y backend. No genera ni publica un AAB/IPA ni
modifica las entregas Android/iOS de la versión anterior. Sigue pendiente la
validación funcional con sesión real y dispositivos Android/iOS.
