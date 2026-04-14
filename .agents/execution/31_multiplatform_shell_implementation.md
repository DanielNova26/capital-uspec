# 31 — Multiplatform Shell Implementation

## 1. Archivos tocados
- `lib/home/home_shell.dart` (Nuevo): Shell de navegación diferenciado por plataforma.
- `lib/home/app_drawer.dart`: Adaptado para funcionar como Sidebar persistente en Web.
- `lib/home/home_screen.dart`: Refactorizado para usar `HomeShell` y actuar como el cuerpo del dashboard.

## 2. Cómo se separó Web y Móvil
Se implementó una lógica de `LayoutBuilder` y `kIsWeb` para decidir el Shell a renderizar:

- **WebShell (Desktop):**
  - Breakpoint de 900px de ancho.
  - Sidebar lateral persistente (280px).
  - Estructura de `Row` para el layout principal.
  - El AppBar del sistema es opcional y se maneja dentro del contenido principal.

- **MobileShell (Android/iOS/Web Mobile):**
  - Estructura clásica de `Scaffold` con `Drawer`.
  - Navegación oculta tras el menú hamburguesa.
  - Foco en el contenido central.

## 3. Parte compartida
- **Lógica de Acceso:** Sigue residiendo en `HomeScreen` y los guards existentes.
- **Estado Global:** Ambas plataformas consumen el mismo `EmpresaScope`.
- **Navegación:** Se reutiliza el widget `AppDrawer` para mantener las mismas opciones en ambas plataformas, evitando duplicar la lógica de rutas.
- **Módulos:** El grid de módulos se renderiza en ambas, ajustando solo el número de columnas.

## 4. Parte diferenciada
- **Composición del Layout:** Web usa paneles laterales persistentes; Móvil usa drawers.
- **Densidad Visual:** Web incrementa el número de columnas en el Grid de módulos (4 columnas) frente a Móvil (2 columnas).
- **Indicador de Empresa:** Web lo muestra en el encabezado del Sidebar; Móvil lo integra en el título del AppBar.
- **Encabezados:** Web usa `headlineMedium` directo en el body; Móvil usa el `title` del AppBar.

## 5. Visualización de Empresa Activa
- **En Web:** Se creó un componente en la parte superior del Sidebar que muestra el ID de la empresa con un avatar circular y etiqueta clara ("Empresa Activa"). Es visible en todo momento.
- **En Móvil:** Se incluye dinámicamente en el título del AppBar ("Panel Principal - EMPRESA_001").

## 6. Riesgos detectados
- **Escalabilidad del Sidebar:** Si el número de opciones en el `AppDrawer` crece mucho, el sidebar web podría requerir un scroll interno independiente (ya cubierto por `ListView` en `AppDrawer`).
- **Navegación Interna:** Las pantallas secundarias (Perfil, Historial, etc.) siguen siendo `MaterialPageRoute` que cubren toda la pantalla. Para una experiencia Web "Premium" futura, estas deberían abrirse en el panel central manteniendo el Sidebar visible.

## 7. Pruebas mínimas recomendadas
- **Prueba Web:** Abrir en navegador, redimensionar la ventana por encima y por debajo de los 900px. El sidebar debe aparecer y desaparecer (cambiando a drawer) correctamente.
- **Prueba Móvil:** Verificar que el AppBar sigue mostrando el nombre de la empresa y que el Drawer funciona normalmente.
- **Cambio de Empresa:** Abrir el diálogo de cambio de empresa desde el Sidebar (Web) y verificar que el encabezado del Sidebar se actualiza instantáneamente.
- **Navegación:** Clicar en cualquier módulo (ej. Compras) y verificar que los guards de acceso siguen funcionando igual en ambas plataformas.
