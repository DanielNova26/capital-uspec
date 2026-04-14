# 33 — Home UX Corrections Implementation

## 1. Archivos tocados
- `lib/home/widgets/home_shared_widgets.dart`: Implementación de `CompanyNameWidget` y `QuickActionChip`.
- `lib/home/home_shell.dart`: Uso de `CompanyNameWidget` en el sidebar web.
- `lib/home/home_screen.dart`: Refactorización de encabezados, franja de acciones rápidas, campana de notificaciones y marcadores de calendario.

## 2. Nombre visible de empresa
Se sustituyó el ID técnico (ej. EMPRESA_001) por el nombre legible mediante el widget `CompanyNameWidget`.
- Realiza una consulta a `TBL_EMPRESAS` para obtener el campo `nombre` o similares.
- Mantiene el ID como fallback si no se encuentra el documento.
- Aplicado en Sidebar (Web), AppBar (Móvil) y Título de Dashboard (Web).

## 3. Marcadores del calendario
Se habilitaron los marcadores visuales (dots) en `TableCalendar`.
- Se usa la fuente de datos `_events` ya cargada en el Home.
- Los puntos naranjas aparecen automáticamente en días con tareas asignadas.
- Límite visual de 3 marcadores por día para evitar saturación.

## 4. Bienvenida y Notificaciones
- **Bienvenida:** Se añadió el saludo "Hola, [Nombre]" basado en el perfil del usuario.
- **Campana:** Se integró un botón de notificaciones con un `Badge` rojo que muestra el conteo de no leídas en tiempo real.
- **Ubicación:**
  - Web: Al lado del botón "Nueva Tarea".
  - Móvil: Como acción en el `AppBar`.

## 5. Franja deslizable superior
Recuperada la sección horizontal de acceso rápido (`_buildQuickActionsRow`).
- Chips interactivos para: *Mis Tareas*, *Crear Tarea*, *Mi Equipo* e *Historial*.
- En Móvil es scrollable horizontalmente; en Web aparece sobre el contenido principal.

## 6. Diferenciación Web vs Móvil
- **Web:** Prioriza el contexto amplio, mostrando saludo y empresa en un encabezado grande.
- **Móvil:** Prioriza el espacio, moviendo el nombre de la empresa al AppBar y dejando el cuerpo para el saludo y las acciones rápidas.

## 7. Pruebas mínimas recomendadas
1.  **Calendario:** Validar que los días con tareas tengan puntos naranjas.
2.  **Branding:** Confirmar que en el Sidebar Web aparece el nombre de la empresa y no solo el ID.
3.  **Acciones:** Verificar que los chips de la franja superior navegan correctamente.
4.  **Notificaciones:** Validar que la campana muestra el número correcto de pendientes.
5.  **Multiplataforma:** Redimensionar ventana para asegurar que el saludo y la franja se adaptan bien.
