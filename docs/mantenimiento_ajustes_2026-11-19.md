# Correcciones de Mantenimiento y Equipos del 19 de noviembre de 2026

## Ampliación: documento de noviembre 19 (2)

Aplicados los ajustes de `AJUSTES MODULO EQUIPOS Y MANTENIMIENTO - noviembre 19 (2).docx`, incluidos sus cuatro ejemplos visuales. El documento original no se modificó.

| Solicitud | Resultado adicional |
| --- | --- |
| Inventario: desde y hasta | Dos límites visibles para fecha de ingreso, independientes e inclusivos. Un filtro activo excluye las fichas sin fecha. Se puede quitar el rango. |
| Foto al trasladar | Foto y resumen del equipo juntos en cabecera; debajo, movimiento y recepción/observaciones. Se conserva la imagen completa y se elimina la columna extensa dedicada solo a la foto. Composición compacta en móvil y ventanas estrechas. |
| Bajas: cada campo en su columna | Fecha, Acta, Rótulo, Equipo, Movimiento, Und y Consulta. Las tarjetas compactas identifican cada campo por separado. |
| Movimientos: columnas indicadas | Mismas siete columnas; origen y destino se muestran en Movimiento. La tabla cambia a tarjetas si el espacio y la escala de texto no permiten leerla correctamente. |
| Bajas y Movimientos: fecha inicial y final | Dos selectores visibles. El servidor filtra antes de paginar, desde medianoche de Bogotá hasta antes de la medianoche posterior al día final; ambos días quedan incluidos. Conserva el índice existente. |
| Actas en general | Membrete con acta y fecha, movimiento, equipo y foto alineados, cantidades y saldos juntos, entrega/recepción en paralelo y observaciones completas. Los textos extensos pueden continuar en otra página con la identificación del acta repetida. |

El período de la consulta pertenece a cada carga y a su cursor. Al cambiar fechas se descartan registros y cursor anteriores; una respuesta tardía no reemplaza el resultado vigente. La búsqueda textual y los selectores de origen/destino siguen actuando sobre los movimientos ya cargados, con aviso visible y carga de páginas adicionales. Las fechas consultan todo el histórico del período de la empresa activa. La autorización de la función se comprueba antes de consultar.

Validación de esta ampliación: 58 pruebas Flutter y 11 pruebas de servidor/permisos en Firestore/Storage locales, incluido un rango de más de cien movimientos con extremos exactos, fecha final completa, empresas separadas y cursor fuera del rango. TypeScript y lint aprobados; análisis Flutter sin incidencias. Web compilada. Se revisaron capturas en 390, 768, 1024 y 1366 píxeles con texto al 160 %, perfiles Android/iOS y actas PDF de traslado/baja compactas y extensas renderizadas con Poppler. Las evidencias son de prueba y permanecen en `build/mantenimiento_revision`.

Estos ajustes adicionales no se publicaron. Requieren desplegar `mantenimientoInventario` antes de los clientes; no requieren nuevas reglas, maestros, asignaciones ni índices. Queda probar la sesión real y los selectores/archivos en Android e iPhone físicos. No se compilaron binarios nativos; iOS requiere macOS. La publicación anterior 2.8.39+93 se registra en `MEJORAS.md` y no incluye estos cambios posteriores.

## Cambios anteriores: documentos de noviembre 18

Se aplicaron las observaciones de `AJUSTES MODULO EQUIPOS Y MANTENIMIENTO - noviembre 18.docx` y su complemento `noviembre 18 V2.docx`. La V2 reorganiza el panel; conserva las solicitudes funcionales del primer documento. No se modificaron los archivos originales ni datos de producción.

| Solicitud | Resultado |
| --- | --- |
| Nombre y panel | Mantenimiento y Equipos en Inicio, catálogo y Admin. Identificador canónico `mantenimientodashboard` conservado. Equipos reúne Inventario, Hoja de vida, Bajas, Movimientos y Equipos por sede. Mantenimiento reúne Pendientes, Órdenes e Informes. |
| Web y móvil | Panel lateral en Web amplia, navegación agrupada en anchos intermedios y menú en ventanas estrechas. Móvil mantiene navegación compacta y formularios por tarea. Se decide la composición por el espacio lógico disponible. |
| Rótulo | Generado por servidor para altas nuevas, estable ante reintentos y visible en inventario. El alta deja de pedir Referencia. Se conservan las referencias históricas en la consulta. |
| Proveedor y factura | Solo proveedores activos de la categoría Equipos de Compras, en la empresa activa. Una factura exige precio de compra positivo con hasta dos decimales; comprobado también en servidor. |
| Clasificaciones | Maestro operativo en Inventario → Clasificaciones: código, nombre, método de depreciación, edición e inactivación. Columna en inventario con el nombre vigente del maestro; las etiquetas históricas siguen disponibles como respaldo. |
| Gobierno y copia | Clasificaciones registradas en ambos catálogos de maestros, antes de las fichas para traducir sus referencias. Admin copia únicamente registros ausentes. La copia de fichas omite saldos, precio, proveedor, archivos y asociaciones locales por sede. Escritura directa de clasificaciones bloqueada en Firestore. |
| Mínimos por sede | Configuración fuera del alta. El tipo se asocia por establecimiento con existencias; ni el alta ni la bodega temporal permiten asignarlo. Los tipos locales se limitan al maestro de la sede. Las asociaciones históricas se conservan como respaldo fuera de temporal hasta que se indique una asociación específica. |
| Campos obligatorios y adjuntos | Marca `*`, precio condicionado por factura y leyenda de ficha técnica PDF de hasta 5 MB. Baja exige motivo y al menos una evidencia fotográfica o de video. |
| Traslado y baja | Datos del equipo y ubicación ordenados, foto del equipo y saldo restante visible. El servidor comprueba el saldo dentro de la transacción. |
| Personas del traslado | Entrega la persona autenticada. Recepción usa el selector común, muestra nombre, cargo y departamento y excluye al remitente. El servidor rechaza suplantación, autorrecepción, texto libre como receptor y personas ajenas o inactivas. |
| Actas | PDF de traslado y de baja con membrete, código estable, foto cuando existe, cantidades, saldos, responsables y observaciones. Archivo identificable por clase de acta, código y nombre del equipo. Los movimientos nuevos conservan una instantánea de la foto y de las personas. |
| Consulta de movimientos | Consulta paginada de traslados con origen, destino, fecha y búsqueda por equipo, rótulo o acta. Los filtros se aplican a los registros cargados y la interfaz permite cargar los anteriores. Consulta individual de movimientos antiguos sin depender de los últimos cien de la ficha. |
| Bajas e inventario | Bajas muestra movimientos de baja y actas, exclusivamente para consulta. Un equipo con inventario registrado y saldo total cero desaparece del inventario. Una baja parcial conserva las unidades disponibles; las fichas base sin ingreso siguen accesibles para registrar su entrada. |

Los métodos disponibles son línea recta, saldo decreciente, unidades de producción y no deprecia. Este cambio registra el método; no introduce un cálculo contable de depreciación.

## Validación y publicación

Pruebas reproducibles:

- `flutter analyze --no-pub lib/mantenimiento lib/admin/maestros_sync_service.dart lib/core/app_catalog.dart test/mantenimiento/mantenimiento_test.dart`
- `flutter test --no-pub test/mantenimiento/mantenimiento_test.dart test/admin/maestros_sync_test.dart`
- `npm --prefix functions run build`
- Desde `functions`, `npx eslint src/mantenimiento_inventario.ts src/mantenimiento_ordenes.ts src/maestros.ts` y `node --test test/*.test.js`.
- `firebase emulators:exec --only firestore,storage --project demo-mantenimiento --config firebase.planes-test.json "node --test functions/test/mantenimiento.rules.js"`
- `flutter build web --no-pub`

Los widgets cubren Web a 390, 768, 1024 y 1366 píxeles lógicos con texto al 160 %, perfiles de Android e iOS, áreas seguras y teclado simulado en el alta. Se revisaron capturas y los PDF de actas renderizados. Los archivos de comprobación quedan en `build/mantenimiento_revision`; no son documentos operativos.

No se publicó esta modificación. Antes de publicar los clientes deben estar disponibles el índice de grupo `movimientos`, las reglas y las funciones `mantenimientoInventario`, `mantenimientoOrden` y `adminSincronizarMaestros`. Está pendiente repetir los flujos con sesión real en navegador y en Android e iPhone físicos, incluidas cámara, selector de archivos, teclado, descarga y compartir PDF; la compilación iOS requiere macOS. No se reescribieron asignaciones ni movimientos históricos automáticamente.
