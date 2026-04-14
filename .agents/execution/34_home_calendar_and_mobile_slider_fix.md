# 34 — Home Calendar Markers and Mobile Module Slider Fix

## 1. Archivos tocados
- `lib/home/widgets/home_shared_widgets.dart`: Ajustado `ModuleCard` para soportar anchos fijos en sliders.
- `lib/home/home_screen.dart`: 
  - Implementado `_buildMobileModuleSlider` para módulos horizontales en Móvil.
  - Corregida la lógica de marcadores en `TableCalendar` usando `calendarBuilders`.
  - Movido el detalle de tareas seleccionadas debajo del calendario.
  - Eliminado el bloque de notificaciones del cuerpo principal en favor de la campana.
  - Eliminada la franja de accesos rápidos tipo chips.

## 2. Cómo quedó Móvil
- **AppBar Estándar:** No deslizable, con el nombre de la empresa resuelto mediante `CompanyNameWidget` y acceso a la campana de notificaciones.
- **Módulos Deslizables:** Los accesos a Administración, Compras, etc., ahora se presentan en una fila horizontal deslizable que ahorra espacio vertical.
- **Enfoque en Agenda:** El calendario ocupa el bloque central, y justo debajo aparecen las tarjetas de tareas para el día seleccionado.

## 3. Cómo quedó Web
- **Consola Multicolumna:** Mantiene la cuadrícula de módulos en el panel principal (ahora más limpio sin notificaciones).
- **Calendario con Marcadores:** Los días con tareas ahora muestran un círculo naranja con el número de actividades pendientes.
- **Detalle Dinámico:** Al hacer clic en un día del calendario, la lista de tareas de la columna derecha se actualiza automáticamente.

## 4. Resolución de Puntos del Calendario
Se implementó un `markerBuilder` personalizado en `TableCalendar`.
- Detecta si hay eventos en la fecha mediante el mapa `_events`.
- Dibuja un círculo naranja con el conteo de tareas, lo que lo hace mucho más visible que los puntos estándar de Material.

## 5. Acceso a Notificaciones
- Se eliminó `_buildNotificationsCard` del cuerpo del Home tanto en Web como en Móvil.
- Ahora el usuario accede a sus notificaciones exclusivamente desde el icono de campana en el `AppBar` (Móvil) o encabezado (Web).
- El icono mantiene un `Badge` dinámico con el conteo de no leídas.

## 6. Riesgos o Pendientes
- **Rendimiento:** El mapa de `_events` se limpia y repuebla en cada reconstrucción del StreamBuilder. Aunque es eficiente para pocos registros, para miles de tareas históricas se debería filtrar por rango de fecha visible.

## 7. Pruebas mínimas recomendadas
1.  **Deslizamiento:** En un dispositivo móvil o simulador, verificar que la fila de módulos se desplace suavemente.
2.  **Marcadores:** Asegurar que los días con tareas tengan un círculo naranja con un número.
3.  **Selección:** Tocar un día en el calendario y verificar que las tareas de abajo cambien.
4.  **Campana:** Pulsar la campana y verificar que abre la pantalla de notificaciones completa.
