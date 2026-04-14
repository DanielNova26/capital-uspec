# AGENTS - ToDo

## Regla general de plataforma
Web y móvil comparten lógica de negocio, empresa activa, roles y permisos.
Pero no deben compartir exactamente la misma experiencia visual ni el mismo flujo de navegación.

La Web debe aprovechar:
- espacio horizontal
- paneles laterales
- tablas
- filtros persistentes
- vistas maestro-detalle
- mayor densidad de información

El Móvil debe priorizar:
- foco por tarea
- menos elementos por pantalla
- navegación compacta
- acciones rápidas
- menor carga visual
- jerarquía clara

No quiero:
- una web que parezca una app móvil estirada
- un móvil que parezca una web comprimida

## Gemini
Responsable de:
- front visual
- layouts
- componentes
- SVG
- GIF
- animaciones
- consistencia visual
- experiencia premium
- diferenciación real entre Web y Móvil desde UX y diseño

No hace Git.

## Claude
Responsable de:
- Firestore
- reglas
- arquitectura
- repositorios
- validaciones
- integraciones
- estabilidad
- soporte técnico para diferencias reales entre Web y Móvil sin duplicar innecesariamente la lógica

No hace Git.

## Codex
Responsable de:
- flujo funcional
- jerarquía de acceso
- navegación por rol
- permisos por usuario
- pruebas funcionales
- integración entre front y back
- consolidación final
- Git y GitHub
- definir qué parte del flujo debe compartirse y qué parte debe diferenciarse entre Web y Móvil

Solo Codex hace:
- git add
- git commit
- git push
