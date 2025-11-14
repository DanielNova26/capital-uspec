# ToDo – Plataforma de gestión corporativa

Aplicación Flutter para administrar tareas, talento humano y procesos
corporativos de la organización.

## Dataset demo para revisión de tiendas

Si necesitas compartir la app con Apple o Google en modo revisión,consulta la guía [docs/app-review-demo-account.md](docs/app-review-demo-account.md). 
Allí se explica cómo generar el usuario demo (`demo.reviewer` / `Review2025!`) desde el panel de semillas y qué información enviar al equipo de App Store Review.

## Desarrollo local

1. Instala las dependencias con `flutter pub get`.
2. Configura Firebase ejecutando `flutterfire configure` o copiando el
   `firebase_options.dart` correspondiente.
3. Corre `flutter run` y selecciona el dispositivo deseado.

Para pruebas específicas de la capa de datos existen herramientas de siembra en
el panel administrador (triple tap sobre el logo → PIN `2468`).
