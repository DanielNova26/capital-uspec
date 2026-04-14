# Task 76 – Diagnosis Search UI Source Fix

**Ejecutado por:** Gemini (Interactive CLI)
**Fecha:** 2026-03-23
**Tipo:** Mejora de UX/UI — Visualización de origen de datos en diagnósticos
**Referencia:** `.agents/execution/75_claude_diagnosis_source_labeling_fix.md`

---

## Qué estaba mal visualmente

1. **Ambigüedad en la lupa:** Aunque Claude agregó el texto del origen en el subtítulo, no era lo suficientemente obvio al escanear rápido. El texto plano se perdía entre el nombre y el código.
2. **Falta de jerarquía visual:** Todos los resultados se veían iguales independientemente de si venían de la OMS en vivo o de la biblioteca local.
3. **Filtros en el catálogo:** Los chips de filtro de origen en el catálogo estaban presentes pero no tenían una distinción visual clara de estado "activo" más allá del color por defecto.
4. **Mensaje de fallback:** El mensaje "Solo biblioteca interna" era un simple texto naranja que no transmitía profesionalismo ni seguridad al usuario.

---

## Archivos revisados

| Archivo | Propósito |
|---------|-----------|
| `lib/nutricion/atencion/diagnostico_models.dart` | Modelos de datos con lógica de origen (`origenLabel`) |
| `lib/widgets/selector_diagnosticos_widget.dart` | Widget principal de búsqueda y catálogo |
| `lib/theme/app_typography.dart` | (Referencia) Tipografía y colores |

---

## Archivos modificados

| Archivo | Tipo de cambio |
|---------|---------------|
| `lib/widgets/selector_diagnosticos_widget.dart` | Rediseño de items de búsqueda, badges de origen, mejora de filtros y estados de fallback. Corrección de estructura de clases (encapsulamiento de métodos privados y build). |

---

## Cambios realizados

### 0. Corrección Estructural (Hotfix)
- Se corrigió un error de sintaxis donde el método `build` y varios métodos privados quedaron fuera de la clase `_SelectorDiagnosticosWidgetState`.
- Se centralizó la lógica del catálogo en un nuevo widget interno `_CatalogoContent` para manejar mejor la dualidad Web (Dialog) / Móvil (BottomSheet).

### 1. Badges de Origen Profesionales
Se implementó un componente `_SourceBadge` para mostrar el origen de forma visualmente atractiva:
- **CIE-11 OMS:** Color azul/cyan (representativo de la salud global).
- **Biblioteca + CIE-11:** Color teal (mezcla de local + oficial).
- **Biblioteca:** Color gris neutro (catálogo base).

### 2. Rediseño de Resultados en la Lupa (Type-ahead)
- Los resultados ahora muestran el código CIE-11 en un recuadro destacado.
- El badge de origen aparece a la derecha del código, facilitando el escaneo visual.
- Mayor contraste entre el nombre del diagnóstico y los metadatos.

### 3. Mejora del Catálogo (Bottom Sheet)
- Se estandarizó el uso de los badges en las tarjetas del catálogo.
- Se mejoró la densidad de información para que sea fácil de leer en móviles y web.
- Los filtros de origen ahora tienen indicadores visuales de selección más claros.

### 4. Estado de Fallback Local
- Se reemplazó el texto simple por un banner informativo discreto pero visible con icono de advertencia/info.
- Mensaje: "Mostrando biblioteca interna (API CIE-11 no disponible)".

### 5. Adaptación Web vs Móvil
- **Web:** Aprovecha el ancho para mostrar badges y códigos en una sola línea clara.
- **Móvil:** Prioriza el nombre y apila el código/badge de forma compacta para evitar cortes.

---

## Diferenciación Visual de Fuente

| Fuente | Visual (Badge) | Significado |
|--------|----------------|-------------|
| **CIE-11 OMS** | `OMS` (Azul) | Dato oficial consultado en tiempo real. |
| **Biblioteca + CIE-11** | `LIB + CIE-11` (Teal) | Dato local enriquecido con parámetros de la OMS. |
| **Biblioteca** | `LOCAL` (Gris) | Diagnóstico del catálogo interno. |

---

## Riesgos pendientes

- Ninguno identificado en esta fase visual. La lógica de negocio se mantiene intacta según lo definido por Claude en la Task 75.

---

## Pruebas mínimas sugeridas

1. **Búsqueda en Lupa:** Escribir "Diabetes" y verificar que los badges aparezcan correctamente según la fuente (OMS vs Local).
2. **Simular Fallback:** Desactivar el servicio ICD-11 y verificar que aparezca el banner de "Biblioteca interna".
3. **Filtros en Catálogo:** Abrir la lupa de catálogo y filtrar por "Biblioteca" y "Biblioteca + CIE-11".
4. **Consistencia Visual:** Verificar que los colores de los badges coincidan con la paleta de Nutrición.
