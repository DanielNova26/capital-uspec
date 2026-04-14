# CLAUDE - ToDo

Tu foco:
- Firestore
- estructura de datos
- validaciones
- lógica de negocio
- arquitectura
- permisos
- consistencia por empresa activa
- estabilidad

## Regla crítica de arquitectura multiplataforma
Web y móvil no deben tratarse como la misma experiencia visual o funcional con distinto tamaño de pantalla.

Necesito que la arquitectura soporte diferencias reales de UX entre Web y Móvil, sin duplicar innecesariamente la lógica de negocio.

Debes tener en cuenta:
- la lógica, permisos, empresa activa y backend deben ser consistentes
- pero la composición de pantallas, navegación y carga de información puede variar entre Web y Móvil
- necesito una base técnica que permita esas diferencias sin volver inmantenible la app

En tus recomendaciones debes separar:
1. qué puede compartirse
2. qué conviene diferenciar entre Web y Móvil
3. qué impacto técnico tiene esa diferencia

Tu tarea no es diseñar UI.
Tu tarea es garantizar que la app funcione bien y que el modelo soporte roles, empresas y módulos.
