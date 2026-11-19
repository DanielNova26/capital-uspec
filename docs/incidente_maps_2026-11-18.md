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
- La clave antigua quedó inicialmente solo para SDK Android/iOS. En la revisión del caso, Jason señaló que aún faltaba una restricción de aplicación. **Con autorización expresa de Daniel, se restringió a Android (`com.todogestion.app` y sus cinco firmas verificadas) y se retiró iOS**; nombre actual `maps-legacy-android-restringida`. Las versiones antiguas de iPhone dejan de cargar mapas hasta actualizar a una compilación con la clave iOS nueva. No se modificaron las claves de Firebase ni los permisos de negocio. Su retirada definitiva depende de sustituir las versiones Android antiguas.
- Configuración privada conservada en `functions/.env`, ignorada por Git; no imprimir ni versionar su contenido.

## Cuotas diarias del proyecto

| Servicio y operación | Límite |
| --- | ---: |
| Geocoding, todos los métodos | 0 |
| Maps JavaScript, Map loads | 250 |
| Directions, Requests | 100 |
| Routes, ComputeRoutes | 100 |
| Places (New), SearchText | 20 |
| SDK Android, cargas básicas de mapa | 1.000 |
| SDK iOS, cargas básicas de mapa | 1.000 |
| SDK Android/iOS, Street View y cargas de mapas de pago | 0 |
| Resto de operaciones con cuota diaria de esos servicios | 0 |

Las cuotas se comparten entre empresas y se restablecen según el horario de Google. Al agotarlas, la operación de mapas correspondiente puede dejar de responder durante el resto del día. No aumentar límites sin revisar el consumo real y la tarifa del SKU. Estas cuotas contienen Maps; no sustituyen el control de otros servicios de Firebase/Cloud. No borran los cargos previos.

## Verificación y prevención

`node tool/verificar_claves_maps.cjs --cloud --build` consulta las restricciones reales, contrasta las claves de las fuentes, revisa las tres funciones, comprueba la deshabilitación de servicios y los límites diarios. Es de solo lectura y no imprime claves. El predeploy de Hosting ejecuta esta auditoría para impedir publicar una configuración que se haya abierto de nuevo.

Web 2.8.38+92 publicada. HTML y versión coinciden por SHA-256 en `to-do-gestion.web.app` y `to-do-gestion.com`; la pantalla de acceso carga. La revisión no inició sesión ni ejecutó cálculos operativos. No se verificaron mapas en Android/iOS físicos; iOS necesita compilación y publicación desde macOS. Las versiones Android instaladas conservan el SDK con la clave histórica restringida; se autorizó bloquear mapas de las versiones iOS antiguas hasta actualizarlas.

Android 2.8.38+92 compilado en `outputs/android/to-do-gestion-2.8.38-92.aab`. Bundletool valida el paquete y Jarsigner confirma la firma; el certificado coincide con la firma local de distribución. El manifiesto del AAB contiene la nueva clave restringida de Android. SHA-256: `bee234e596aaf7766188432d3c7c88a4f6511a15db182a344b946de299c3bca8`. El archivo está listo; no se subió a Play Console ni se alteró la versión 91 que ya estaba pendiente de publicar.

## Solicitud de revisión del cargo: caso 77760956

Solicitud enviada el 18 de noviembre de 2026 por Asistencia de Google Maps Platform, como problema de facturación P3, por COP 474.615,40. [Caso 77760956](https://console.cloud.google.com/google/maps-apis/support/cases/detail/77760956?project=integra360-94704). El chat fue asignado a April; se pidió investigar el origen, un ajuste completo (crédito si está pendiente o devolución si ya se pagó) y revisar si se puede suspender la cobranza mientras investigan. No se enviaron claves ni archivos `.env`.

Se presentó en inglés una versión de este texto, con las medidas verificadas y el dato adicional del administrador de que el volumen del domingo no corresponde a su actividad normal:

> Solicito revisar un cargo inesperado de COP 474.615,40 en Geocoding API del proyecto integra360-94704, concentrado el 15 de noviembre de 2026. La revisión del 18 de noviembre encontró 40.002 solicitudes durante los últimos siete días y una clave pública sin restricción de aplicaciones que permitía Geocoding. No hemos podido confirmar el origen del tráfico. Hemos deshabilitado Geocoding, fijado en cero sus cuotas diarias, retirado las APIs de pago de la clave expuesta, separado y restringido las claves de las plataformas, migrado el servidor a una clave privada y limitado las APIs necesarias. Solicitamos investigar el tráfico y evaluar un ajuste o crédito excepcional por este incidente. Podemos aportar el informe de facturación y las métricas, sin revelar credenciales.

El ajuste depende de Google. El caso está enviado y en atención; todavía no hay devolución ni crédito aprobados, ni confirmación de suspensión del cobro.

El historial de transacciones de Google consultado durante el chat muestra un intento de cobro de umbral de COP 450.000 el 15 de noviembre rechazado, con importe de transacción COP 0; el saldo total pendiente mostrado es COP 498.178, que incluye otros servicios. Se informó al agente y se mantuvo la solicitud limitada al importe de Geocoding de COP 474.615,40. La agente April confirmó la fecha del consumo y transfirió el caso a Jason para investigar la actividad antes de devolver la solicitud de ajuste a Facturación.

También se comunicó a Jason la declaración del administrador de que llevaban varios meses utilizando mapas sin un cargo comparable y que el volumen del domingo no corresponde al número de usuarios ni al uso normal. Se pidió contrastar meses anteriores y documentar posibles indicadores de llamadas externas o automatizadas. Son declaraciones del administrador y una solicitud de investigación; todavía no existe una conclusión técnica sobre el origen.

Después se contrastó directamente el informe de Cloud Billing, con el mismo filtro de Geocoding API: del 1 de enero al 31 de octubre de 2026 muestra COP 0,00 y «No hay resultados para mostrar». Se comunicó al especialista como antecedente verificado, comparado con COP 474.615,40 de noviembre. Constancia local: `outputs/support/geocoding-enero-octubre-2026-cero.jpg`.

Jason comunicó que su investigación interna detectó un pico de **40.006 solicitudes**, origen **Filipinas** y **33 % de duplicación**. Daniel confirmó expresamente que no reconoce ningún uso autorizado desde Filipinas; se trasladó esa confirmación a Jason y se pidió documentar el hallazgo como posible uso no autorizado de la clave, devolver el caso a Facturación y recomendar el crédito completo. El dato de 40.006 corresponde al análisis interno del soporte; el primer dato de 40.002 corresponde a la ventana de métricas consultada inicialmente.

Tras cerrar la restricción de aplicación de la clave histórica con autorización de Daniel, Jason confirmó en el chat que verificó la configuración aplicada. Se respondieron las preguntas de Facturación sobre el propósito interno de la app, el uso de Maps y la exposición pública anterior de la clave. Se solicitó devolver el caso a Facturación para decidir el crédito completo, confirmar el plazo y responder sobre la suspensión de reintentos de cobro.

Jason indicó después que ya dispone de toda la información y que, al considerar el uso inesperado e involuntario, enviará el caso a Facturación para una revisión de ajuste de cortesía por única vez. Aclaró que cualquier ajuste requiere aprobación final de Facturación; aún no confirmó importe aprobado, aplicación del crédito ni suspensión de cobranza.

En esta revisión adicional se detectaron y bloquearon también las cuotas de Street View y cargas de mapas de pago de ambos SDK móviles. Las cargas básicas quedan limitadas a 1.000 por día y plataforma. La app revisada no utiliza Street View ni Cloud Map IDs. Esto cierra operaciones de pago que aún permitían las APIs de SDK en la clave histórica; no cambia el bloqueo de Geocoding ya aplicado. La auditoría exige ahora también el paquete y las firmas Android en la clave histórica, además de su única API permitida.
