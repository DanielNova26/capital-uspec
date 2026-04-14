# 13 Phase 0 Decisions

## Propósito
Este documento deja cerradas las decisiones de Fase 0 que deben gobernar la implementación posterior de flujo, backend, seguridad y estrategia multiplataforma.

La intención es eliminar ambigüedad antes de ejecutar Fase 1.

## 1. Estrategia de identidad

### Decisión
- La identidad técnica final será `Firebase Auth UID`.
- Durante la transición, `TBL_USUARIOS` mantiene su estructura actual.
- Se agregará el campo `uid` a `TBL_USUARIOS`.
- El lookup transitorio será:
  1. `uid`
  2. `cedula`
  3. `docId` legacy si hace falta
- No se cambia todavía el `docId` de la colección.

### Justificación
- El modelo actual funciona para pruebas, pero no es suficiente para una arquitectura de seguridad real.
- `Firebase Auth UID` es la base correcta para reglas Firestore, claims y control robusto de acceso.
- Mantener el `docId` actual evita una migración brusca y reduce riesgo operativo.
- El lookup transitorio permite convivir con datos legacy mientras se llena el nuevo campo `uid`.

### Impacto técnico
- `TBL_USUARIOS` debe extenderse con `uid`.
- Los servicios y helpers deberán soportar resolución híbrida durante la transición.
- Las reglas de producción futuras podrán usar `request.auth.uid`.
- No habrá migración masiva inmediata de `docId`, solo compatibilidad progresiva.

### Impacto funcional
- En pruebas, el flujo actual puede seguir funcionando.
- En fases siguientes, la sesión y los permisos podrán alinearse mejor con identidad real.
- El usuario no debería percibir un cambio brusco en esta fase.

### Impacto en Web
- La versión web podrá usar la misma identidad técnica final sin lógica específica por plataforma.
- La futura seguridad de Firestore será consistente con el cliente web.

### Impacto en Móvil
- Android e iOS podrán usar el mismo modelo final de identidad.
- No obliga todavía a reescribir completamente el flujo actual de acceso móvil.

## 2. Catálogos

### Decisión
- `TBL_ROLES` será catálogo global.
- `TBL_AREAS` será por empresa.
- `TBL_ESTRUCTURA_ORGANIZACIONAL` será por empresa.

### Justificación
- Los roles deben poder definirse de forma central y reutilizable.
- Las áreas y la estructura organizacional dependen de la empresa activa y no deben mezclarse entre empresas.
- Esta separación reduce ambigüedad entre catálogo global y estructura operativa por empresa.

### Impacto técnico
- `TBL_ROLES` no debe modelarse como dato operativo por empresa salvo que exista una tabla adicional de asignación.
- `TBL_AREAS` siempre debe consultarse con `empresaId`.
- `TBL_ESTRUCTURA_ORGANIZACIONAL` debe tratarse como dataset segmentado por empresa, aunque la colección sea común.
- Los servicios y pantallas que hoy lean globalmente estas colecciones deben corregirse en fases siguientes.

### Impacto funcional
- La empresa activa definirá correctamente qué áreas y qué estructura se muestran.
- Se evita que usuarios vean o usen organigramas ajenos.
- Se aclara la diferencia entre rol general y estructura organizacional operativa.

### Impacto en Web
- Web podrá mostrar tablas, filtros y paneles más densos, pero siempre sobre áreas y estructura de la empresa activa.
- Maestro-detalle en escritorio deberá usar el contexto correcto por empresa.

### Impacto en Móvil
- Móvil podrá resumir áreas y jerarquía sin perder consistencia.
- El foco por tarea seguirá dependiendo de estructura válida por empresa.

## 3. Política de borrado

### Decisión
- Soft delete para registros operativos.
- No hard-delete para recepciones ni fichas técnicas en operación normal.
- Usar como base:
  - `isDeleted`
  - `deletedAt`
  - `deletedBy`
- Hard-delete solo para limpieza administrativa controlada.

### Justificación
- Recepciones y fichas técnicas tienen trazabilidad operativa.
- El hard-delete normal rompe auditoría, recuperación y diagnóstico de errores.
- Soft delete protege el flujo funcional y permite limpieza posterior controlada.

### Impacto técnico
- Los modelos operativos deberán contemplar campos de borrado lógico.
- Las queries funcionales deberán excluir registros borrados.
- Los procesos administrativos podrán tener herramientas separadas para hard-delete controlado.
- El backend futuro podrá auditar mejor quién eliminó y cuándo.

### Impacto funcional
- El usuario normal no elimina definitivamente información operativa sensible.
- Se reduce el riesgo de pérdida irreversible de datos.
- La operación diaria gana trazabilidad y capacidad de recuperación.

### Impacto en Web
- Web podrá mostrar estados de archivo, papelera o filtros administrativos con mayor contexto.
- Las tablas podrán incluir filtros de “activos / eliminados” cuando aplique para perfiles autorizados.

### Impacto en Móvil
- Móvil debe ocultar complejidad innecesaria y privilegiar acciones seguras.
- En móvil, la eliminación debe sentirse como desactivación o envío a papelera, no como destrucción permanente.

## 4. Regla crítica multiplataforma

### Decisión
- Web y móvil comparten lógica, empresa activa, roles y permisos.
- Web y móvil NO comparten exactamente la misma experiencia visual ni la misma navegación.
- Web debe aprovechar paneles laterales, tablas, filtros persistentes, vistas maestro-detalle y mayor densidad de información.
- Móvil debe priorizar foco por tarea, menos elementos por pantalla, navegación compacta, acciones rápidas y menor carga visual.

### Justificación
- Una sola lógica de negocio evita duplicación e inconsistencias.
- Dos experiencias de uso distintas aprovechan mejor la naturaleza de cada plataforma.
- La Web no debe parecer una app móvil estirada.
- El Móvil no debe parecer una web comprimida.

### Impacto técnico
- La capa de servicios, permisos, empresa activa y modelos debe seguir siendo compartida.
- La capa de presentación y shell de navegación debe poder divergir por plataforma.
- Los guards de acceso y la semántica de empresa activa deben comportarse igual en ambas plataformas.
- Se requerirá una estrategia clara de shell Web vs shell Móvil.

### Impacto funcional
- El usuario tendrá las mismas capacidades según empresa, rol y permisos, sin importar la plataforma.
- La forma de navegar y consumir información sí cambiará según contexto de uso.
- La app será más usable tanto en escritorio como en móvil.

### Impacto en Web
- La Web debe comportarse como herramienta de control y operación con contexto persistente.
- Se favorecerán paneles laterales, listados densos, filtros visibles y maestro-detalle.
- La navegación debe minimizar cambios de pantalla innecesarios.

### Impacto en Móvil
- El Móvil debe comportarse como herramienta de ejecución rápida y seguimiento puntual.
- Se favorecerán pantallas más enfocadas, menos elementos simultáneos, acciones directas y navegación compacta.
- La experiencia debe reducir carga cognitiva y priorizar lo inmediato.

## Cierre de Fase 0
Quedan cerradas para implementación posterior las siguientes bases:
- identidad técnica futura con `uid`
- coexistencia transitoria con estructura actual
- catálogo global de roles
- áreas y estructura organizacional por empresa
- soft delete como política operativa por defecto
- diferencia real Web/Móvil sobre lógica compartida

Estas decisiones deben considerarse contrato de implementación para Fase 1 y fases posteriores.
