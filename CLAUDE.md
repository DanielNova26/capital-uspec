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

Lee también `AGENTS.md` al iniciar cada conversación. Su contrato de módulo
nuevo (catálogo, Admin, niveles, revocación, backend, pruebas y Web/Móvil) es
obligatorio para cualquier módulo que crees o amplíes. Coordina hallazgos y
pendientes con Codex únicamente mediante `MEJORAS.md`.

Todo maestro nuevo debe quedar registrado por empresa en el catálogo común
para permitir su copia controlada. La edición operativa se hace en el módulo
que lo usa, según la regla 6; Admin concentra configuraciones técnicas y
administrativas ya centralizadas y la copia entre empresas. Los parámetros
reservados a Desarrollo deben protegerse en reglas o servidor además de la
interfaz. Compartir la fuente de datos, sin duplicarla ni cruzar empresas.
Ante datos históricos, preparar una incorporación revisable por empresa y
documentar la transición en `MEJORAS.md`.

La cobertura obligatoria es Web adaptable (incluidos portátiles de 10 y 14
pulgadas por ancho lógico disponible), Android e iOS para iPhone. Comprueba
anchos estrechos y amplios, escala de texto, teclado, áreas seguras y flujos
propios de cada plataforma. Comparte servicios y permisos; adapta la
composición y navegación. Registra en `MEJORAS.md` cada plataforma no
verificada.

Los perfiles generales de Admin son plantillas opcionales de apps y no
reemplazan roles internos. Los `roleKey`/`roleId` históricos que todavía
participan en autorización (Desarrollo, Gerencia y administradores históricos)
requieren una auditoría
explícita antes de cambiar o desactivar el perfil: su estado visual no es una
revocación efectiva.

## Git: siempre en `main`, nunca en ramas
En cada conversación trabaja sobre el checkout de `main`. No crees ni cambies
a ramas. **Claude no ejecuta Git**: no hagas pull, add, commit, push ni merges.
Codex es el único responsable de esas operaciones y de publicar los cambios
en `main`, conforme a `AGENTS.md`.

## Comunicación en cada conversación
Entrega al usuario solo el resultado final, la validación y los pendientes
reales. No muestres razonamiento interno, lista de comandos ni narración del
proceso. Si un bloqueo requiere una actualización intermedia, que sea breve.
Registra la coordinación técnica con Codex en `MEJORAS.md`.

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
- **Admin › Maestros por módulo** reúne configuraciones y datos de gobierno,
  especialmente los parámetros técnicos que solo Desarrollo puede editar,
  y **"Copiar a otras empresas"**. No duplica el editor operativo de cada
  módulo. Restringe cada parámetro técnico tanto en la interfaz como en
  reglas o servidor; no bloquees toda la pestaña sin clasificar sus opciones.
- Compras crea y carga proveedores, marcas y productos dentro del módulo, por
  su propio equipo. Admin conserva la configuración de requisitos
  documentales, el plazo de rechazados, bodegas y grupos, además de Correo,
  Tokens DIAN y WhatsApp. Autorizados y conexión del buzón DIAN y filtros de
  Correo son configuraciones. Cada opción conserva el permiso de edición que
  le corresponda; no quites al equipo de Compras sus cargas operativas.
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
