# Task 58 - Notifications UI Redesign

## Qué estaba mal visualmente

- **Jerarquía débil**: La lista de notificaciones era una simple repetición de cards básicas sin agrupación clara.
- **Escaneo difícil**: No había diferenciación visual por tipo de notificación (todas usaban el mismo ícono genérico).
- **Experiencia Web pobre**: La pantalla se estiraba horizontalmente sin límites, desperdiciando espacio y dificultando la lectura.
- **Estados vacíos básicos**: Se usaban íconos y textos simples en lugar de componentes de estado vacío diseñados.
- **Indicador de "No leído" sutil**: La diferencia entre leída y no leída era apenas un cambio leve de color de fondo.
- **Falta de acciones globales**: No había forma de marcar todas las notificaciones como leídas de un solo toque.

## Archivos revisados

- `lib/home/notifications_screen.dart`
- `lib/home/home_screen.dart`
- `lib/home/widgets/home_shared_widgets.dart`
- `lib/widgets/empty_state_widget.dart`
- `GEMINI.md` (lineamientos de diseño)

## Archivos modificados

- `lib/home/notifications_screen.dart`: Rediseño total de la pantalla de lista y lógica de agrupación.
- `lib/home/home_screen.dart`: Mejora visual de la campana y el badge de notificaciones.

## Mejoras Implementadas

### Pantalla de Notificaciones
1. **Agrupación Temporal**: Las notificaciones ahora se agrupan por "Hoy", "Ayer" y fechas anteriores, permitiendo un escaneo mucho más rápido.
2. **Iconografía por Tipo**: Se asignaron íconos y colores específicos según el tipo de notificación:
   - `task_assigned`: Ícono de asignación (Azul)
   - `task_avance`: Ícono de tendencia/progreso (Verde)
   - `task_novedad`: Ícono de alerta/error (Naranja)
   - `doc_rechazado`: Ícono de documento (Rojo)
3. **Indicador de Lectura Premium**: Las notificaciones no leídas ahora tienen una barra de acento lateral y un fondo sutil del color primario, además de tipografía en negrita.
4. **Acción "Marcar Todo"**: Se añadió un botón en el AppBar para marcar todas las notificaciones como leídas mediante un `WriteBatch` de Firestore.
5. **Estados Vacíos**: Integración con `EmptyStateWidget` para mostrar mensajes claros y visuales cuando no hay notificaciones.

### Campana / Badge
- **Animación de Cambio**: La campana ahora tiene una pequeña animación de escala al cambiar de estado (de vacío a con notificaciones).
- **Estilo M3**: El badge utiliza colores de error del esquema de colores oficial para mayor visibilidad.

### Adaptación Web
- **Ancho Contenido**: Se limitó el ancho máximo de la lista a 800px y se centró en pantalla para evitar el efecto de "app estirada".
- **Density**: Se ajustaron los paddings y alineaciones del TabBar para aprovechar mejor el espacio horizontal en Web.

### Adaptación Móvil
- **Foco y Claridad**: Se mantuvo una navegación limpia con acceso rápido al detalle de la tarea.
- **Gestos**: Área de tap optimizada para abrir el destino correspondiente.

## Riesgos pendientes

- **Rendimiento con muchas notificaciones**: Si un usuario tiene miles de notificaciones sin leer, el batch de "Marcar todas" podría exceder el límite de 500 documentos de Firestore. (Poco probable en uso normal, pero a considerar para el futuro con paginación).
- **Consistencia de tipos**: Si se agregan nuevos tipos de notificaciones en el backend, usarán el ícono por defecto hasta que se mapeen explícitamente en el front.

## Pruebas mínimas a correr

1. **Visualización**: Verificar que las notificaciones se agrupen correctamente por fecha.
2. **Lectura**: Hacer clic en una notificación y verificar que pase de "No leída" a "Leída" visualmente y que el badge de la campana disminuya.
3. **Marcar todas**: Usar el botón de la doble marca en el AppBar y verificar que todas desaparezcan de la pestaña "Nuevas".
4. **Navegación**: Verificar que al tocar "Ver detalle" se abra la pantalla correcta (Tareas Asignadas o Historial) según el tipo de notificación.
5. **Responsividad**: Abrir la pantalla en Web y verificar que el contenido esté centrado y no estirado al 100% del ancho.
