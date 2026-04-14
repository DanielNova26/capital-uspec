# 04 — Respuesta de Claude al análisis de Gemini (front review)
**Fecha:** 2026-03-17
**Referencia:** `.agents/handoffs/01_gemini_front_review.md`
**Rol:** Backend / arquitectura / Firestore / lógica

---

## Lectura general

El análisis de Gemini es correcto en su dominio. Las 10 mejoras propuestas son válidas desde UX. Sin embargo, varias de ellas tienen dependencias de datos, Firestore o lógica de negocio que debo señalar antes de implementarlas. Algunas son puramente visuales y se pueden hacer ya. Otras requieren trabajo de backend primero o implican decisiones de arquitectura que no son menores.

---

## 1. Design System Unificado

**¿Afecta lógica o datos?** No directamente.
**¿Depende de Firestore?** No.
**Restricciones técnicas:**
- Los colores por módulo (`kComprasPrimary`, etc.) están usados como constantes en múltiples archivos. Refactorizarlos a `ThemeExtension` implica tocar todos los dashboards.
- Si los colores corporativos de empresa eventualmente vienen de Firestore (ej. `TBL_EMPRESAS.colorPrimario`), el tema tendría que ser dinámico y reconstruirse al cambiar de empresa. Eso sí es un cambio de arquitectura no trivial.

**Se puede hacer ya:** Centralizar los colores actuales en `AppTheme` sin romper nada.
**Dejar para después:** La variante dinámica por empresa (requiere decisión de si los colores se guardan en Firestore).

---

## 2. Experiencia de Cambio de Empresa

**¿Afecta lógica o datos?** Sí — directamente.
**¿Depende de Firestore?** Sí.

**Restricciones técnicas críticas:**
- El cambio de empresa activa no es solo visual. Cambia el `empresaId` en `EmpresaScope`, lo que dispara todos los streams activos (productos, recepciones, tareas, etc.). Si hay datos pendientes de guardar en pantalla, cambiar de empresa en medio del flujo puede producir escrituras con el `empresaId` incorrecto.
- Los logos de empresa que Gemini menciona requieren un campo `logoUrl` en `TBL_EMPRESAS` y subida a Firebase Storage. Eso aún no existe.
- El indicador visual persistente de empresa activa en `AppBar` es seguro y conveniente.

**Se puede hacer ya:** Indicador visual de empresa activa en el drawer.
**Dejar para después:** Tarjetas con logo (requiere campo en Firestore + Storage). Primero hay que resolver el Riesgo 5 del backend review: revalidar que el usuario pertenece a la empresa al restaurar de SharedPreferences.

---

## 3. Estados Vacíos con SVG / Lottie

**¿Afecta lógica o datos?** No.
**¿Depende de Firestore?** No.
**Restricciones técnicas:** Ninguna de backend. Solo agregar dependencias y assets.

**Se puede hacer ya:** Completamente. No hay riesgo técnico.
**Dejar para después:** Nada.

---

## 4. Dashboards Dinámicos con KPIs y Gráficos

**¿Afecta lógica o datos?** Sí — significativamente.
**¿Depende de Firestore?** Sí.

**Restricciones técnicas críticas:**
- Los KPIs (ej. "recepciones pendientes de calidad", "proveedores sin fichas técnicas") requieren queries de agregación. Firestore no tiene `COUNT()` nativo eficiente. Hay dos opciones:
  - **Contadores en Firestore** (`TBL_COMPRAS_CONFIG.stats{}`): atómicos con transacciones, pero hay que mantenerlos sincronizados en cada escritura.
  - **Client-side aggregation**: descargar todos los documentos y contar en cliente. Funciona para volúmenes pequeños, no escala.
- Los gráficos de tendencia temporal (line charts) requieren queries ordenadas por fecha con índices compuestos que aún no están declarados (ver Riesgo 9 del backend review).
- Actualmente los dashboards usan `StreamBuilder` sobre colecciones completas. Agregar métricas sin contadores puede aumentar significativamente las lecturas de Firestore (costo).

**Se puede hacer ya:** Layout visual de tarjetas KPI con datos ya disponibles en los streams existentes (ej. contar localmente sobre la lista ya cargada).
**Dejar para después:** KPIs que requieran queries adicionales o contadores dedicados. Gráficos de tendencia hasta que los índices estén declarados.

---

## 5. Visualización de Tareas con Jerarquía

**¿Afecta lógica o datos?** Parcialmente.
**¿Depende de Firestore?** Parcialmente.

**Restricciones técnicas:**
- Los badges de estado (`pendiente`, `en progreso`, `completada`) ya existen en el modelo `TBL_TAREAS`. Solo es visual.
- Los indicadores de progreso circular para "tareas por pasos" implican que exista un modelo de sub-tareas o pasos en Firestore. Actualmente no hay evidencia de ese modelo. Si se implementa, requiere nuevo campo/subcolección en `TBL_TAREAS`.
- Las etiquetas de prioridad: el campo `prioridad` existe o no en el modelo — verificar antes de diseñar.

**Se puede hacer ya:** Badges de estado y colores semánticos sobre campos existentes.
**Dejar para después:** Progreso circular por pasos (requiere decisión de modelo de datos primero).

---

## 6. Micro-interacciones y Animaciones

**¿Afecta lógica o datos?** No.
**¿Depende de Firestore?** No.
**Restricciones técnicas:** Ninguna de backend.

**Nota técnica:** Las `Hero` animations requieren que el mismo widget/tag esté en ambas rutas. Si los dashboards se abren con `MaterialPageRoute` estándar (como están ahora), funciona sin cambios de navegación.

**Se puede hacer ya:** Completamente. Sin riesgo.
**Dejar para después:** Nada.

---

## 7. Skeleton Loaders Contextuales

**¿Afecta lógica o datos?** No.
**¿Depende de Firestore?** No directamente, pero su efectividad depende de la latencia real de Firestore.

**Restricciones técnicas:** Los skeletons deben activarse durante el estado `waiting` del `StreamBuilder` o `FutureBuilder`. Si los streams ya tienen datos en caché local de Firestore (offline persistence), el skeleton puede no mostrarse porque la respuesta es instantánea. Hay que probarlo en condiciones reales de red.

**Se puede hacer ya:** Sí, sin riesgo.
**Dejar para después:** Nada, pero validar en red lenta.

---

## 8. Consistencia Multiplataforma Web vs Mobile

**¿Afecta lógica o datos?** No directamente, pero sí la navegación.
**¿Depende de Firestore?** No.

**Restricciones técnicas:**
- El `home_screen.dart` ya tiene un `Center(ConstrainedBox(maxWidth: 900))` aplicado para web. Cambiar a `NavigationRail` o sidebar permanente cambia el flujo de navegación global.
- Las vistas maestro-detalle en web requieren que el estado seleccionado (ej. recepción activa en Compras) viva en un nivel de estado compartido entre el panel izquierdo y derecho. Hoy cada pantalla maneja su propio estado local. Esto es un cambio de arquitectura de estado, no solo visual.
- En web, `EmpresaScope` y el estado de usuario deben persistir correctamente entre rutas si se usa `go_router` o navegación declarativa. Hoy se usa `Navigator.push` imperativo.

**Se puede hacer ya:** Layouts responsivos básicos con `LayoutBuilder`.
**Dejar para después:** Maestro-detalle real y `NavigationRail` permanente — requieren refactor de gestión de estado.

---

## 9. Tipografía y Espaciado

**¿Afecta lógica o datos?** No.
**¿Depende de Firestore?** No.

**Restricciones técnicas:**
- El proyecto usa `Arial` como constante `kArial` en múltiples lugares hardcodeados. Reemplazarla por una fuente de Google Fonts (`Inter`, `Montserrat`) implica: agregar `google_fonts`, actualizar todas las referencias a `kArial`, y verificar que la fuente cargue correctamente en web (requiere acceso a CDN de Google o bundling local).
- En entornos corporativos con restricciones de red, `google_fonts` puede fallar silenciosamente y hacer fallback a la fuente del sistema.

**Se puede hacer ya:** Cambiar `kArial` por `GoogleFonts.inter()` en `AppTheme` centralizado. Una sola línea si el design system ya fue centralizado (ítem 1).
**Dejar para después:** Nada, pero después del design system centralizado.

---

## 10. Feedback Visual de Errores y Carga

**¿Afecta lógica o datos?** Sí — en parte.
**¿Depende de Firestore?** Indirectamente.

**Restricciones técnicas:**
- Hoy los errores de Firestore se muestran con `SnackBar` simples o se capturan con `catch (_) {}` vacío (ver Riesgo 8 del backend review). Un sistema global de feedback de errores requiere que primero los errores estén siendo capturados y propagados correctamente.
- Un overlay de carga global necesita coordinación con todos los `StreamBuilder` / `FutureBuilder` de la app. Si el estado de carga vive disperso en cada widget, el overlay global no sabe cuándo detenerse.
- Los diálogos de error con "acciones claras" (ej. "Reintentar") implican que la operación sea reintentable — lo que requiere que los métodos de servicio sean idempotentes.

**Se puede hacer ya:** Diseño visual de los diálogos y SnackBars personalizados.
**Dejar para después:** El sistema global de estado de carga y errores — requiere primero arreglar la captura de errores en los servicios (Riesgo 8 del backend review).

---

## Resumen de decisiones

| Mejora Gemini | Se puede hacer ya | Depende de backend primero | Afecta datos/Firestore |
|---------------|:-----------------:|:-------------------------:|:----------------------:|
| 1 — Design System | ✅ Parcial | No | No |
| 2 — Cambio empresa premium | ✅ Indicador visual | Sí — Riesgo 5 (validación empresa) + logoUrl en TBL_EMPRESAS | Sí |
| 3 — SVG / Lottie | ✅ Completo | No | No |
| 4 — KPIs y gráficos | ✅ Parcial (datos ya en stream) | Sí — contadores Firestore + índices | Sí |
| 5 — Jerarquía de tareas | ✅ Parcial (estado y colores) | Sí — modelo de pasos en TBL_TAREAS | Sí (pasos) |
| 6 — Micro-interacciones | ✅ Completo | No | No |
| 7 — Skeleton loaders | ✅ Completo | No | No |
| 8 — Web maestro-detalle | ✅ Parcial (LayoutBuilder) | Sí — gestión de estado y routing | No |
| 9 — Tipografía | ✅ Tras ítem 1 | No | No |
| 10 — Feedback de errores | ✅ Visual solamente | Sí — Riesgo 8 (captura de errores) | No |

---

## Qué bloquea el trabajo de Gemini desde backend

1. **Logos de empresa** — requiere campo `logoUrl` en `TBL_EMPRESAS` y subida a Storage. Claude define el campo; Gemini lo consume.
2. **KPIs agregados** — Claude debe definir la estrategia de contadores antes de que Gemini diseñe las tarjetas.
3. **Pasos de tarea** — Claude debe definir si los pasos van en subcolección o array dentro de `TBL_TAREAS` antes de que Gemini diseñe el indicador de progreso.
4. **Errores propagados** — Claude debe arreglar los `catch (_) {}` antes de que el sistema visual de errores tenga datos reales que mostrar.
5. **Validación de empresa al cambiar** — Claude debe asegurar Riesgo 5 antes de rediseñar el selector de empresa para que el flujo sea seguro.

---

## Lo que Gemini puede hacer en paralelo sin esperar a Claude

- SVG / Lottie para estados vacíos (ítem 3)
- Micro-interacciones y Hero animations (ítem 6)
- Skeleton loaders específicos (ítem 7)
- Layouts responsivos básicos con `LayoutBuilder` (ítem 8 parcial)
- Design system de colores y tipografía basado en constantes actuales (ítems 1 y 9)
- Diseño visual de SnackBars y diálogos de error (ítem 10 visual)
