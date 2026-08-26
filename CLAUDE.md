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

## Reglas transversales de interfaz (aplican a TODOS los módulos)

Estas no son sugerencias de diseño: son contratos de la app. Si una pantalla
nueva no los cumple, está mal hecha.

### 1. Listados extensos: 20 por página
Ningún listado se pinta completo. Se usa `lib/widgets/paged_list.dart`:
- `PagedDataTable(tabla: DataTable(...))` para cualquier `DataTable`.
- `PagedListSection` para listas de tarjetas dentro de una columna con scroll.
- `pageOf()` + `PagerBar` cuando la pantalla arma sus propias filas o rejillas.

`kPageSize = 20` es el tamaño único; no se define otro por pantalla. La barra
de páginas solo aparece cuando hay más de una página.

### 2. Todo scroll horizontal lleva barra visible
Lo resuelve `AppScrollBehavior` (`lib/theme/app_scroll_behavior.dart`),
registrado en el `MaterialApp`. No hay que envolver tablas en `Scrollbar` a
mano: ya viene, y además el mouse puede arrastrar la tabla.

### 3. Áreas: nunca un id crudo ni repetidas
Toda lista de áreas pasa por `lib/core/area_directory.dart`
(`areasUnicas`, `AreaCatalogo`, `areaNombreLegible`). Prohibido resolver el
nombre con `?? doc.id`, y prohibido filtrar comparando `areaId ==`: se usa
`contiene()`, porque la misma área existe con varias variantes de id.

### 4. Personas: nombre y foto, nunca la cédula suelta
`UserAvatar` y `UserNameText` (`lib/widgets/user_avatar.dart`) en cualquier
lugar donde se muestre una persona.

### 5. Módulos y accesos
El catálogo de módulos es `lib/core/app_catalog.dart`. Notificaciones y
calendario NO son módulos: los tiene todo el personal y nadie los puede quitar.

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
