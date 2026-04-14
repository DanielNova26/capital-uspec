# 88 - Estrategia Visual: Gestión Documental Premium

## 1. Evaluación de la UI Necesaria
El módulo de Gestión Documental requiere una interfaz que inspire **confianza, orden y rigor corporativo**. A diferencia de otros módulos más operativos, este debe sentirse como una herramienta de auditoría y control de calidad.

### Problemas a evitar:
- Uso de colores brillantes que restan seriedad.
- Falta de claridad en la jerarquía de versiones (¿cuál es la vigente?).
- Trazabilidad oculta o difícil de consultar.
- Estados que se confunden visualmente.

---

## 2. Estructura Visual Recomendada

### Paleta de Colores Corporativa
- **Fondo:** `#F8FAFC` (Slate 50) - Limpio y profesional.
- **Primario:** `#0F172A` (Slate 900) - Texto y encabezados fuertes.
- **Acento:** `#3B82F6` (Blue 500) - Acciones y selección.
- **Bordes:** `#E2E8F0` (Slate 200) - Definición sutil de contenedores.

### Tipografía
- Uso estricto de **Arial** (fuente del proyecto) con pesos diferenciados:
  - `FontWeight.w900` para títulos de sección.
  - `FontWeight.w400` para descripciones largas.
  - `FontWeight.w700` para etiquetas de estado.

---

## 3. Pantallas y Componentes

### A. Dashboard Documental (Vista Maestra)
- **Web:** Tabla de alta densidad con filtros persistentes por Categoría, Área y Estado. Panel lateral derecho para previsualización rápida.
- **Móvil:** Cards compactas con indicadores visuales de estado y botón flotante de subida rápida.

### B. Lista de Documentos
Cada ítem en la lista debe mostrar:
- Código (ej. `SOP-RH-001`) en negrita.
- Título y versión actual.
- **Badge de Estado** con colores semánticos sobrios.
- Miniatura del documento (o icono de PDF con color de estado).

### C. Detalle del Documento (Vista de Control)
Esta es la pantalla más importante. Se divide en tres zonas:
1.  **Cabecera de Contexto:** Título, Código, Versión Vigente y Estado Actual.
2.  **Visor de Documento:** Previsualización con watermark.
3.  **Panel de Control:** Acciones (Aprobar, Rechazar, Observar) y Trazabilidad (Timeline vertical).

---

## 4. Representación Visual de Estados

Los estados se distinguirán mediante **Badges con estilo de "Sello"** y colores de baja saturación:

| Estado | Color de Badge (Fondo / Texto) | Icono |
| :--- | :--- | :--- |
| **Borrador** | `#F1F5F9` / `#475569` | `Icons.edit_note` |
| **En Revisión** | `#DBEAFE` / `#1E40AF` | `Icons.visibility` |
| **Observado** | `#FEF3C7` / `#92400E` | `Icons.rule` |
| **Rechazado** | `#FEE2E2` / `#991B1B` | `Icons.cancel` |
| **Apro./Firmado** | `#D1FAE5` / `#065F46` | `Icons.verified` |
| **Publicado** | `#0F172A` / `#FFFFFF` | `Icons.public` |
| **Obsoleto** | `#F1F5F9` / `#94A3B8` | `Icons.history` |

---

## 5. Firma Interna y Perfil de Identidad
- **Componente:** Card de "Identidad Digital".
- **Visual:** Muestra la firma manuscrita sobre un fondo blanco limpio con un borde sutil.
- **Acción:** Botón de "Configurar Firma" que abre un lienzo de captura a pantalla completa (estilo premium).
- **Seguridad Visual:** La firma en el documento final se acompaña de un sello digital con nombre, cargo y timestamp.

---

## 6. Vista Previa con Watermark
- **Técnica:** Overlay visual mediante un `Stack` de Flutter.
- **Diseño del Watermark:** 
  - Texto diagonal semi-transparente (Opacity 0.1).
  - Repetido en patrón de rejilla sobre el documento.
  - El texto coincide exactamente con el **Estado Actual**.
  - En documentos **Publicados**, el watermark desaparece o se convierte en un sello de "COPIA CONTROLADA" en el pie de página.

---

## 7. Diferencias Web / Móvil

### Experiencia Web (Desktop First)
- **Vista Maestro-Detalle:** El usuario selecciona un documento a la izquierda y lo previsualiza/gestiona a la derecha sin cambiar de pantalla.
- **Timeline Detallado:** Trazabilidad siempre visible en una columna lateral.
- **Acciones Rápidas:** Barra de herramientas superior estilo editor de documentos.

### Experiencia Móvil (Focus First)
- **Flujo Lineal:** Dashboard -> Lista -> Detalle (pantalla completa).
- **Acciones en Bottom Sheet:** Los botones de "Aprobar/Rechazar" aparecen en una hoja inferior para facilitar el uso con una mano.
- **Visor Optimizado:** Zoom de pellizco para el documento y watermark simplificado.

---

## 8. Riesgos Visuales
- **Sobrecarga de Información:** Demasiados metadatos pueden oscurecer el documento. Solución: Usar pestañas (Tabs) en el detalle para separar el archivo de la trazabilidad.
- **Legibilidad del Watermark:** Si es muy fuerte, no se lee el texto; si es muy débil, no cumple su función. Solución: Permitir ajustar la opacidad en configuración de admin.

---

## 9. Orden de Implementación Visual

1.  **Fase 1 (Cimientos):** Creación de la paleta de colores y componentes de `Badges` y `Cards` específicos de GD.
2.  **Fase 2 (Navegación):** Implementación del `Dashboard` y la `Lista de Documentos` (Responsive).
3.  **Fase 3 (El Corazón):** Pantalla de `Detalle del Documento` con el visor de PDF y Watermark overlay.
4.  **Fase 4 (Identidad):** Pantalla de gestión de `Firma Interna` del usuario.
5.  **Fase 5 (Detalles):** Timeline de trazabilidad animado y pulido de transiciones.

---

## Primera Pantalla a Construir: `GD_Dashboard_Screen`
Esta pantalla servirá como el ancla de la experiencia. Mostrará un resumen de documentos "Bajo mi responsabilidad" (para revisar o corregir) y el acceso general a la biblioteca documental.

## Diseño de la Pantalla de Detalle:
Se sentirá como una **Mesa de Revisión**. El documento estará al centro, rodeado de metadatos contextuales. Si el estado es "Observado", las observaciones aparecerán en un banner persistente en la parte superior del visor del documento para que no se pierdan de vista durante la lectura.
