# 91 - Ejecución UI/UX: Módulo de Gestión Documental

## Fecha
2026-03-26

## Archivos revisados
- `lib/home/document_management_screen.dart` (Original mock)
- `lib/gestion_documental/gd_models.dart`
- `lib/gestion_documental/gd_service.dart`
- `lib/home/home_screen.dart`

## Archivos creados / modificados
- **Creados:**
  - `lib/gestion_documental/widgets/gd_ui_widgets.dart`: Componentes base (Paleta, Badges, Cards, Timeline).
  - `lib/gestion_documental/gd_dashboard_screen.dart`: Biblioteca documental con filtros y creación.
  - `lib/gestion_documental/gd_detail_screen.dart`: Mesa de revisión con visor, flujo y trazabilidad.
  - `lib/gestion_documental/gd_firmas_screen.dart`: Gestión de identidad y firma digital.
- **Modificados:**
  - `lib/home/document_management_screen.dart`: Convertido en puente hacia el nuevo módulo real.
  - `lib/home/home_screen.dart`: Actualizado para pasar `empresaId` al módulo.
  - `lib/gestion_documental/gd_models.dart`: Agregado helper `deString` a `GdAccion`.

## Resultado Visual

### 1. Dashboard Documental
- **Web:** Vista tipo consola con tabla de alta densidad, filtros rápidos y encabezado corporativo.
- **Móvil:** Lista de tarjetas optimizada con indicadores de estado claros.
- **Creación:** Diálogo profesional para subir el primer PDF y definir metadatos.

### 2. Biblioteca de Documentos
- Organizada por Empresa Activa.
- Estados visuales diferenciados por colores Slate/Blue (Premium).
- Distinción inmediata de la versión vigente.

### 3. Detalle (Mesa de Revisión)
- **Visor:** Área central para el documento con **Watermark Visual** dinámico (ej: "BORRADOR", "EN REVISIÓN") rotado 45°.
- **Panel Lateral (Web) / Inferior (Móvil):**
  - **Acciones:** Botones contextuales según el estado (Aprobar, Observar, Firmar, etc.).
  - **Versiones:** Listado de todas las iteraciones del documento.
  - **Historial:** Timeline vertical con iconos y colores según la acción realizada.

### 4. Perfil de Firma
- Lienzo de captura de firma manuscrita.
- Opción de carga de PNG.
- Campos de nombre y cargo para el sello institucional.

## Diferenciación Web vs Móvil
- **Web:** Aprovechamiento total del ancho con layouts de 2 columnas en detalle y tablas en dashboard.
- **Móvil:** Navegación por pestañas (Tabs) e iconos para reducir la carga visual, manteniendo la funcionalidad completa.

## Riesgos pendientes
- **Visor PDF Real:** Actualmente se usa un placeholder profesional. Se recomienda integrar `syncfusion_flutter_pdfviewer` o `printing` (PdfPreview) en el siguiente sprint para ver el PDF real dentro de la app.
- **Roles:** Se está usando `GdRoles.adminDoc` como valor por defecto en las transiciones de la UI. Se debe conectar con el sistema de permisos real del usuario.

## Pruebas mínimas recomendadas
1. Crear un documento nuevo con PDF y verificar que aparece en el dashboard.
2. Entrar al detalle y enviar a revisión. Verificar que el estado cambia y el historial se actualiza.
3. Observar un documento, verificar el banner de comentario y el cambio de estado.
4. Configurar la firma en "Mi Identidad Digital" y verificar la previsualización.
5. Cambiar de empresa y verificar que la biblioteca se filtra correctamente.
