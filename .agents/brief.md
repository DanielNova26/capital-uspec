# ToDo - Brief del proyecto

## Nombre
ToDo

## Naturaleza
Aplicación multiempresa.

## Plataformas
- Android
- Web
- iOS

## Funcionalidad inicial principal
- asignación de tareas
- seguimientos
- notificaciones
- flujo por usuario
- trabajo por empresa activa
- acceso por roles y módulos

## Objetivo
Llevar la aplicación a un nivel muy alto en:
- diseño visual
- experiencia de usuario
- arquitectura técnica
- flujo funcional
- jerarquía de acceso
- estabilidad
- escalabilidad

## Reparto de trabajo
- Gemini: front, UI, SVG, GIF, animaciones, UX
- Claude: Firestore, lógica, arquitectura, validaciones, backend
- Codex: flujo, jerarquía de acceso, roles, QA, integración, Git

## Regla crítica
Cada usuario debe ver solo lo que le corresponde según:
- empresa activa
- rol
- módulo asignado
- permisos reales

## Regla crítica de diseño multiplataforma
ToDo existe en Android, Web e iOS.

La experiencia Web y la experiencia Móvil deben diferenciarse de forma real.

No se debe tratar la Web como una app móvil estirada.
No se debe tratar el Móvil como una web comprimida.

Se espera:

### En Web
- mayor densidad de información
- uso de paneles laterales
- tablas y filtros visibles
- vistas maestro-detalle
- mejor aprovechamiento del espacio horizontal
- contexto persistente

### En Móvil
- foco por tarea
- menos elementos por pantalla
- navegación más simple
- acciones rápidas
- jerarquía visual más marcada
- menor carga cognitiva

La lógica, roles, permisos y empresa activa deben ser coherentes entre plataformas, pero la experiencia de uso debe adaptarse a cada una.

## Nota temporal
Las reglas abiertas en Firestore son temporales por etapa de prueba.
Aun así, la arquitectura futura debe prever seguridad real por empresa y rol.
