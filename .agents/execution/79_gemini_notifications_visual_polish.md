# Task 79 – Notifications Visual Polish

**Ejecutado por:** Gemini (Interactive CLI)
**Fecha:** 2026-03-25
**Tipo:** Mejora de UX/UI — Pulido visual de notificaciones y campana
**Referencia:** `.agents/execution/78_claude_notifications_by_company_and_home_calendar_fix.md`

---

## Qué estaba mal visualmente

1. **Header simple**: La cabecera de la pantalla de notificaciones era un `AppBar` estándar sin mucha personalidad.
2. **Jerarquía de tarjetas**: Aunque agrupadas, las tarjetas de notificación carecían de profundidad visual y el indicador de "no leído" era un poco tosco.
3. **Escaneo de fecha**: Los encabezados de grupo eran simples y se perdían un poco en la lista.
4. **Campana/Badge**: Funcional pero con un diseño básico de Material 3 que no se sentía "premium".
5. **Diferenciación Web**: Web se sentía como una versión estirada de móvil a pesar del límite de ancho.

---

## Archivos revisados

| Archivo | Propósito |
|---------|-----------|
| `lib/home/notifications_screen.dart` | Pantalla principal de notificaciones |
| `lib/home/home_screen.dart` | Campana de notificaciones y badge |
| `lib/home/widgets/home_shared_widgets.dart` | Widgets compartidos de Home |
| `GEMINI.md` | Lineamientos de diseño |

---

## Archivos modificados

| Archivo | Tipo de cambio |
|---------|---------------|
| `lib/home/notifications_screen.dart` | Rediseño visual de header, tarjetas y agrupación |
| `lib/home/home_screen.dart` | Refinamiento visual de la campana y el badge |

---

## Cambios realizados

### 1. Pantalla de Notificaciones (Refinamiento Visual)
- **Header Premium**: Rediseño del área de título y TabBar para una apariencia más limpia y moderna.
- **Tarjetas de Notificación**:
  - Uso de bordes suaves y sombras sutiles.
  - Indicador de "no leído" mediante un punto de acento y fondo sutil en lugar de una barra lateral pesada.
  - Mejora en la tipografía para destacar el título y suavizar la descripción.
  - Etiquetas de "Asignado por" más elegantes y discretas.
- **Agrupación Temporal**: Encabezados de fecha con estilo "pill" o tipografía destacada para mejorar el escaneo.

### 2. Campana y Badge (Home)
- **Animación y Estilo**: Refinamiento de la campana con micro-animaciones y un badge más integrado estéticamente.
- **Estados**: Diferenciación más clara entre "sin notificaciones" y "con novedades".

### 3. Adaptación Web vs Móvil
- **Web**:
  - Mayor densidad visual en las tarjetas.
  - Layout centrado y contenido estructurado.
- **Móvil**:
  - Diseño más "aireado" y limpio.
  - Foco en la legibilidad y facilidad de toque.

---

## Diferenciación Visual por Tipo

| Tipo | Ícono | Color | Visualización |
|------|-------|-------|---------------|
| Tarea Asignada | `assignment_ind` | Blue | Foco en quién asignó. |
| Avance | `trending_up` | Green | Foco en el progreso. |
| Novedad | `warning` | Orange | Foco en la alerta. |
| Error/Rechazo | `error` | Red | Foco en la acción correctiva. |

---

## Riesgos pendientes

- **Consistencia**: Asegurar que los nuevos estilos no choquen con otras pantallas del Home que aún no se han pulido al mismo nivel.
- **Legibilidad**: Mantener el contraste adecuado para accesibilidad.

---

## Pruebas mínimas sugeridas

1. **Visualización de Lista**: Verificar que los grupos de fechas se vean claros y profesionales.
2. **Estados de Lectura**: Confirmar que la distinción entre leída y no leída sea intuitiva pero no intrusiva.
3. **Campana en Home**: Verificar que el badge no tape el ícono de forma tosca.
4. **Navegación**: Asegurar que al tocar una notificación se mantenga la funcionalidad de ir al destino correcto.
5. **Responsividad**: Revisar que en Web el contenido no se "rompa" ni se vea fuera de lugar.
