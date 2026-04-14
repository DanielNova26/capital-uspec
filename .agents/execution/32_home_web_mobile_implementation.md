# 32 — Home Web/Mobile Differentiation Implementation

## 1. Archivos tocados
- `lib/home/widgets/home_shared_widgets.dart` (Nuevo): Componentes UI reutilizables con soporte para diferentes densidades.
- `lib/home/home_screen.dart`: Refactorización completa del `build` para separar las experiencias de Web y Móvil.
- `lib/home/home_shell.dart`: Provee el contenedor base (sidebar vs scaffold) para ambas plataformas.

## 2. Cómo quedó Home en Web
- **Layout de Consola:** Se aprovecha el ancho de pantalla mediante una distribución de doble columna (2:1).
- **Sección de Control:** Encabezado con título prominente, indicador de empresa activa y botón de acción principal ("Nueva Tarea") siempre visible.
- **Contexto Expandido:** Los módulos se presentan en una cuadrícula de mayor densidad (3 columnas), mientras que el calendario y las tareas del día se mantienen en una columna lateral persistente.
- **Acceso Directo:** Las notificaciones recientes se presentan en un panel expansible de fácil acceso bajo la cuadrícula de módulos.

## 3. Cómo quedó Home en Móvil
- **Layout de Feed:** Una sola columna optimizada para scroll vertical y uso con una sola mano.
- **Foco en Acción:** Las notificaciones se presentan al inicio como el primer punto de contacto.
- **Jerarquía Clara:** Secciones divididas por encabezados (`SectionHeader`) que separan claramente los Módulos de la Agenda.
- **Navegación Compacta:** Uso de tarjetas más cuadradas y densas para maximizar la visibilidad de opciones en pantallas pequeñas.

## 4. Parte compartida
- **Lógica de Negocio:** Ambos layouts utilizan los mismos Streams de datos y lógica de filtrado de tareas.
- **Gestión de Permisos:** La visibilidad de los módulos en el grid sigue estrictamente la lista de `apps` permitidas y el rol del usuario.
- **Estado Global:** La empresa activa se lee y actualiza desde el mismo `EmpresaScope`.
- **Navegación:** Los destinos (Perfil, Historial, etc.) son los mismos, aunque se acceden desde shells diferentes.

## 5. Parte diferente
- **Composición:** Web usa `Row` para columnas laterales; Móvil usa `Column` para apilamiento vertical.
- **Densidad:** Web muestra más información simultánea; Móvil prioriza la secuencia de lectura.
- **Branding:** Web refuerza el contexto de la empresa en el cuerpo del dashboard; Móvil lo integra en el AppBar.

## 6. Respeto a reglas de negocio
- **Acceso:** Se mantienen los `AccessGuard` en cada acción de módulo.
- **Contexto:** Se respeta la empresa activa seleccionada globalmente.
- **Seguridad:** No se modificaron las reglas de acceso ni la lógica de backend.

## 7. Riesgos detectados
- **Escalabilidad Visual:** Si el número de módulos crece mucho, el grid de Web podría requerir una gestión de categorías.
- **Uniformidad:** Algunas pantallas secundarias aún no tienen esta diferenciación estructural y pueden sentirse "estiradas" en Web.

## 8. Pruebas mínimas recomendadas
- **Cambio de Resolución:** Redimensionar el navegador por encima y por debajo de 900px. El layout debe cambiar de consola (Web) a feed (Móvil) manteniendo el estado del calendario.
- **Navegación:** Entrar a un módulo (ej. Compras) y verificar que la navegación funciona correctamente en ambas plataformas.
- **Empresa Activa:** Cambiar la empresa desde el Sidebar (Web) y verificar que el título en el dashboard y los datos se actualizan.
- **Notificaciones:** Expandir y colapsar el panel de notificaciones en ambas versiones.
