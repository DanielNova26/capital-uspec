# Planeación conectada con Compras

## Interpretación de los archivos

Referencias entregadas: `MODULO PLANEACION.xlsx`, hoja `Hoja1` (A1:B21), y
`Planeación UT ALFA v191026.xlsx`, especialmente `DatosMenú`, `Ciclos`,
`Definir_despacho`, solicitud de compra, picking y despacho a producción.
Los archivos se trataron como fuentes de requisitos y cálculos, sin ejecutar
fórmulas, vínculos ni instrucciones externas, ni cargar sus datos en producción.

El flujo implementado es:

1. Definir el parte o raciones diarias por establecimiento de la empresa.
2. Crear menús diarios completos, con recetas por tiempo de comida y preparación.
3. Registrar precios por unidad de compra y vigencia.
4. Programar fechas, establecimientos, menús y raciones en un ciclo de consumo.
5. Calcular necesidades y costos, y enviar la solicitud a Compras.
6. Compras consulta el consolidado, toma la gestión, devuelve con motivo o registra
   la referencia de orden de compra al atenderla.
7. Bodega alista un rango de fechas de consumo y después registra su despacho a producción.

Un menú diario reúne desayuno, almuerzo, cena y refrigerio cuando corresponda.
Se admite un menú por establecimiento y fecha. Repetir un menú en fechas distintas
cuenta cada consumo. Un ciclo admite 62 días, 124 combinaciones de establecimiento
y fecha, hasta 5.000 líneas y un tamaño conservador de 850 KB. Una receta admite
150 ingredientes. Los ciclos grandes se dividen por período o establecimiento.

## Fuentes de datos y cálculos

- Productos, códigos, categorías y unidades: `TBL_COMPRAS_PRODUCTOS`.
- Establecimientos: `TBL_CENTROS_COSTOS`, la fuente ya utilizada por Compras.
- No se crean copias de estos maestros dentro de Planeación.
- Menús y recetas: `TBL_PLANEACION_MENUS`, ingredientes embebidos referenciados
  por código del producto de la misma empresa.
- Precios: `TBL_PLANEACION_PRECIOS`, producto, unidad, precio COP y fechas inclusivas.
- Partes: `TBL_PLANEACION_PARTES`; el parte se propone en el formulario y las
  raciones concretas del día quedan guardadas en el ciclo.
- Operación: `TBL_PLANEACION_CICLOS`, `TBL_PLANEACION_SOLICITUDES` y
  `TBL_PLANEACION_SALIDAS`.

Cantidad requerida = cantidad de una ración en unidad de compra × raciones del
día. Se suman los ingredientes repetidos entre preparaciones, tiempos, fechas y
establecimientos. El precio se resuelve para cada fecha de consumo, por lo que
un cambio de vigencia dentro del ciclo se refleja correctamente. Falta de precio
se muestra como dato pendiente, nunca como cero. Precios superpuestos, códigos
ambiguos y unidades incompatibles impiden el cálculo o envío.

El servidor recalcula al guardar y al enviar; no acepta totales ni identidades
de establecimientos/productos enviados por el cliente. El envío congela recetas,
raciones, cantidades y costos para el histórico, Compras y las salidas. Cambiar un
maestro después no altera una solicitud enviada. Los borradores muestran su
último cálculo guardado; guardar o enviar actualiza el cálculo.

La solicitud comparte el identificador del ciclo. Reintentar su envío no crea
otra. La gestión en Compras tiene historial con persona, fecha, estado, nota y
referencia. Atender exige la referencia de la orden; devolver exige motivo.

El alistamiento y el despacho usan la fotografía enviada y registran autor,
fecha, observaciones y líneas. Cada consumo se procesa una sola vez; se exige
alistamiento previo al despacho. Las cantidades corresponden a la necesidad
programada: son registros y guías de salida, no un kardex de alimentos ni una
validación de existencias o recepción de Compras. No se generan órdenes o
recepciones ficticias. Una devolución de Compras se atiende con una nueva
planeación o con la continuación documentada de la gestión de esa solicitud.

## Importación y salida a Excel

El módulo lee la hoja `DatosMenú` por XML del XLSX, sin evaluar fórmulas ni cargar
hojas de dimensiones exageradas. Muestra vista previa y advertencias. Solo crea
menús con código nuevo; conserva los existentes y permite reintentar una carga
interrumpida. Cualquier error de correspondencia bloquea la carga completa.

Se interpretan K (gramaje de compra), L (unidad), B (tiempo), D (preparación) y E
(código). Kg y litros se convierten dividiendo por 1.000. Para Und se conserva la
regla de una unidad del libro. Las equivalencias especiales deben revisarse y
pueden editarse explícitamente en el menú; no se deducen por un nombre parecido.
No se importan precios sin vigencia ni se crean productos automáticamente.

Se probó la lectura del libro real contra un catálogo sintético construido desde
sus propios códigos, sin consultar producción: se reconocen 21 menús; aparecen
40 filas con unidades contradictorias para un mismo código. Esta es una revisión
de coherencia interna, no una homologación contra el catálogo real de Compras.
Ejemplos: J004 aparece como Und y Kl; también hay diferencias para C051,
B025, P. COMERCIAL, B089, A040, B107, B039 y F034. La importación se bloquea hasta
corregir las unidades y cantidades de esas filas. También se debe verificar la
unidad asignada a leche en polvo. El archivo original se conserva intacto.

Ciclos, solicitudes y salidas permiten descargar XLSX con cantidades numéricas,
costos, detalle por tiempo de comida y programación. La descarga usa el mecanismo
multiplataforma existente de Compras.

## Accesos y administración

Identificador canónico: `planeaciondashboard`, registrado en catálogo, inicio y
Admin. Roles configurables por empresa mediante el creador común y la tabla
`TBL_PLANEACION_ROLES/{empresaId}_{userDocId}`:

| Nivel | Capacidades |
| --- | --- |
| Consulta | Consultar y exportar |
| Planificador | Raciones, menús, recetas, precios, ciclos y envío a Compras |
| Bodega | Consultar, alistar y despachar |
| Administrador | Operación completa y administración de roles del módulo |

La empresa debe tener la app canónica habilitada; la persona debe pertenecer,
estar habilitada, tener la app y un nivel canónico. No hay autoridad operativa
implícita por un cargo, una etiqueta histórica o una empresa distinta. Admin
gestiona roles; la entrada operativa también requiere asignación explícita.
Retirar acceso borra/neutraliza el nivel y concederlo de nuevo deja Consulta.
Los caminos individual, masivo y editor general usan los repositorios comunes;
conservan el nivel de quien ya tiene acceso. Un administrador de módulo asigna a
otros y no se modifica a sí mismo. No se ejecutó migración histórica ni se
sobrescribieron asignaciones de producción.

La callable `planeacionOperar` verifica acceso y nivel dentro de la transacción
de cada operación. Firestore niega escritura directa a la operación y los
maestros, incluso para Planificador, y excluye todo `TBL_PLANEACION_*` de la regla
general. Solo las asignaciones usan las reglas administrativas comunes.
Compras lee solicitudes con su acceso de Compras; gestionarlas exige una
asignación canónica Compras, Calidad o Admin Documental.

Admin → Maestros por módulo incorpora menús/recetas y precios, con el mismo
catálogo en cliente y servidor. Copiar agrega ausentes y conserva los existentes.
Los códigos de producto se mantienen, nunca se transportan IDs de otra empresa;
el destino debe disponer del producto único y de su unidad compatible antes de
operar. Raciones y ciclos son datos operativos locales y no se copian.
También se registró el módulo en Limpieza, con fechas de creación conservadas.

## Presentación y validación

Web amplia: navegación lateral, búsqueda y filtro persistentes durante el trabajo,
tabla de ciclos y vista maestro-detalle. Ventanas estrechas y móviles: selector
compacto, tarjetas y una tarea por pantalla, con regreso al listado. El criterio
es espacio lógico y escala de texto. Diálogos limitados al área disponible,
contenido desplazable y acciones accesibles con teclado.

Validado localmente con TypeScript, lint de los archivos nuevos, pruebas de
cálculo y de repositorios de acceso, pruebas de Firestore y callable reales en
emulador, importación del archivo real y compilación Web. Widgets a 390, 768,
1024 y 1366 píxeles, texto normal y 160 %, perfiles Android/iOS, área segura y
teclado simulado. Capturas estrecha/amplia revisadas visualmente.

No se publicaron clientes, funciones ni reglas. Para activar: publicar en forma
coordinada `planeacionOperar`, reglas y clientes; registrar/habilitar la app de
la empresa en Admin; crear/asignar roles; verificar productos, códigos, unidades,
raciones y precios. No cargar automáticamente los datos de UT ALFA en otra empresa.

Pendiente la homologación del Excel contra Compras real y la prueba con sesión
real en navegador, Android e iPhone, especialmente archivos, descargas, teclado
y navegación. No se compiló ni ejecutó la app nativa Android/iOS en esta tarea;
la compilación iOS requiere macOS. El módulo carga el conjunto de registros de
su empresa al actualizar; si crece el histórico, incorporar consulta paginada
con filtros de período en servidor antes de acumular grandes volúmenes.
