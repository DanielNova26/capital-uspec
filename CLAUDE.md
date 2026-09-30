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

## Git: siempre en `main`, nunca en ramas
Regla del usuario (28 sep 2026), para no enredarnos entre Claude y Codex:
todo el trabajo va directo a `main`. No se crean ramas ni se trabaja en la
rama que proponga la sesión.

- Antes de empezar: `git pull origin main`.
- Al terminar: commit y `git push origin main`.
- Si el push se rechaza porque `main` avanzó: `git pull --no-rebase origin main`,
  resolver, volver a correr las pruebas y subir. Nunca push forzado.

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

### 2. Scroll horizontal con barra solo donde hay puntero
Lo resuelve `AppScrollBehavior` (`lib/theme/app_scroll_behavior.dart`),
registrado en el `MaterialApp`. No hay que envolver tablas en `Scrollbar` a
mano: ya viene, y además el mouse puede arrastrar la tabla.

La barra **horizontal** solo se pinta en plataformas de puntero (Windows,
macOS, Linux, y Flutter web sobre escritorio). En Android e iOS el dedo ya
desliza la fila, la barra no informa nada y queda pintada encima de las
tarjetas. Se decide con `usaBarraHorizontal(context)`, que resuelve por
`Theme.of(context).platform` y no por `kIsWeb`: así el navegador de un
teléfono se comporta como la app nativa. La barra vertical no cambia.

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

### 6. Maestros por módulo (decisión del usuario, 30 sep 2026)
- Cada módulo crea y edita sus maestros **en su módulo**, en su propia
  empresa. En Compras, proveedores, productos, marcas y fichas técnicas los
  crea y edita el equipo de Compras uno a uno: es así a propósito y **no es
  un pendiente de Admin**.
- **Admin › Maestros por módulo** tiene dos cosas: la configuración que es
  de Administración (en Compras: las cargas por Excel de proveedores,
  productos y requisitos documentales, y el plazo de rechazados; además
  Correo, Tokens DIAN y WhatsApp) y **"Copiar a otras empresas"**. Bodegas y
  grupos de Compras también se crean en Admin.
- Ningún módulo muestra otras empresas: nada de "copiar a otra empresa"
  dentro de un módulo. Lo que mueve datos entre empresas va en Admin
  (Maestros por módulo, o Usuarios › Multiempresa para personas, áreas,
  cargos y centros).
- La copia (`adminSincronizarMaestros`, `functions/src/maestros.ts`) solo
  agrega lo que el destino no tiene y nunca pisa. Un maestro nuevo se agrega
  al catálogo del servidor y a `kModulosMaestros`
  (`lib/admin/maestros_sync_service.dart`); `test/admin/maestros_sync_test.dart`
  falla si no coinciden.

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
