# Geocoding: contención del consumo del 18 de noviembre de 2026

Proyecto: `integra360-94704` (379551786878).

## Evidencia

- Cloud Billing registra COP 474.615,40 de Geocoding API para el 1–18 de noviembre; el gráfico concentra el cargo el 15 de noviembre. Es consumo registrado, no el pronóstico ni una confirmación de débito bancario.
- Google Maps Metrics registra 40.002 solicitudes en los siete días anteriores a la revisión, asociadas a «Clave de API 1», mediante Web Service.
- Esa clave coincidía con la que estaba en el HTML público y en Android/iOS. Permitía 31 APIs, sin restricción de aplicaciones. Las tres funciones de Rutas y Lugares también la utilizaban.
- La exposición permitía uso externo. No se ha confirmado quién originó las consultas; no afirmar que hubo un ataque sin evidencia adicional.

## Cambios aplicados en Google Cloud

- Geocoding deshabilitado. Las cuotas diarias de v3 y de los cuatro métodos v4 quedaron en cero, incluso si alguien vuelve a habilitar el servicio.
- Se deshabilitaron además Elevation, Geolocation, Embed, Maps Platform Datasets, Places antigua, Roads, Static Maps, Street View Publish y Time Zone: no se usan en los flujos actuales revisados.
- Web: clave nueva, restringida a los dominios de Hosting del proyecto, los dominios propios y localhost; permite únicamente Maps JavaScript y Directions.
- Android: clave nueva, solo Maps SDK for Android, restringida a `com.todogestion.app` y las tres huellas obtenidas de Google Play, la firma local de distribución y la firma debug.
- iOS: clave nueva, solo Maps SDK for iOS, restringida a `com.capitaluspec.gestionapp`.
- Servidor: `movilidad-backend`, solo Routes y Places (New). `rutasMovilidadMedirAhora`, `rutasMovilidadTick` y `visitasBuscarLugar` se actualizaron y están activas con esa clave privada. Los documentos de configuración por empresa revisados no contenían claves de Google.
- La clave antigua quedó **solo para SDK Android/iOS**, como compatibilidad para las versiones ya instaladas. No permite JavaScript, Directions, Routes, Places ni Geocoding. No se eliminó porque rompería mapas en móviles instalados. Su retirada definitiva depende de sustituir esas versiones.
- Configuración privada conservada en `functions/.env`, ignorada por Git; no imprimir ni versionar su contenido.

## Cuotas diarias del proyecto

| Servicio y operación | Límite |
| --- | ---: |
| Geocoding, todos los métodos | 0 |
| Maps JavaScript, Map loads | 250 |
| Directions, Requests | 100 |
| Routes, ComputeRoutes | 100 |
| Places (New), SearchText | 20 |
| Resto de operaciones con cuota diaria de esos servicios | 0 |

Las cuotas se comparten entre empresas y se restablecen según el horario de Google. Al agotarlas, la operación de mapas correspondiente puede dejar de responder durante el resto del día. No aumentar límites sin revisar el consumo real y la tarifa del SKU. Estas cuotas contienen Maps; no sustituyen el control de otros servicios de Firebase/Cloud. No borran los cargos previos.

## Verificación y prevención

`node tool/verificar_claves_maps.cjs --cloud --build` consulta las restricciones reales, contrasta las claves de las fuentes, revisa las tres funciones, comprueba la deshabilitación de servicios y los límites diarios. Es de solo lectura y no imprime claves. El predeploy de Hosting ejecuta esta auditoría para impedir publicar una configuración que se haya abierto de nuevo.

Web 2.8.38+92 publicada. HTML y versión coinciden por SHA-256 en `to-do-gestion.web.app` y `to-do-gestion.com`; la pantalla de acceso carga. La revisión no inició sesión ni ejecutó cálculos operativos. No se verificaron mapas en Android/iOS físicos; iOS necesita compilación y publicación desde macOS. Las versiones móviles instaladas conservan el SDK con la clave histórica limitada.

Android 2.8.38+92 compilado en `outputs/android/to-do-gestion-2.8.38-92.aab`. Bundletool valida el paquete y Jarsigner confirma la firma; el certificado coincide con la firma local de distribución. El manifiesto del AAB contiene la nueva clave restringida de Android. SHA-256: `bee234e596aaf7766188432d3c7c88a4f6511a15db182a344b946de299c3bca8`. El archivo está listo; no se subió a Play Console ni se alteró la versión 91 que ya estaba pendiente de publicar.

## Solicitud de revisión del cargo: borrador, no enviado

Enviar mediante Asistencia de facturación de Google Cloud, cuenta «Pago de Firebase». No adjuntar claves ni archivos `.env`.

> Solicito revisar un cargo inesperado de COP 474.615,40 en Geocoding API del proyecto integra360-94704, concentrado el 15 de noviembre de 2026. La revisión del 18 de noviembre encontró 40.002 solicitudes durante los últimos siete días y una clave pública sin restricción de aplicaciones que permitía Geocoding. No hemos podido confirmar el origen del tráfico. Hemos deshabilitado Geocoding, fijado en cero sus cuotas diarias, retirado las APIs de pago de la clave expuesta, separado y restringido las claves de las plataformas, migrado el servidor a una clave privada y limitado las APIs necesarias. Solicitamos investigar el tráfico y evaluar un ajuste o crédito excepcional por este incidente. Podemos aportar el informe de facturación y las métricas, sin revelar credenciales.

El ajuste depende de Google. No hay caso enviado ni devolución aprobada.
