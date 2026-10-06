# Interventoría: preparación de planes para K2

Fecha: 5 de octubre de 2026. Estado: **implementado y probado en código;
pendiente de despliegue y validación en dispositivos reales**. Esta versión
incorpora la corrección del usuario: el administrador puede adjuntar el PDF del
acta, sin exigir evidencia inicial de los hallazgos. Desarrollo también accede
a Planes de mejora, conservando el aislamiento por empresa y la cuenta activa.

## Objetivo solicitado

Preparar en ToDo la respuesta de cada responsable y sus soportes, coordinar
la revisión de Calidad y entregar textos para copiar y archivos para cargar
en K2. El usuario indica 5 días calendario para responder y 20 para soportes.
La entrega en K2 es una etapa independiente de completar el trabajo en ToDo.

## Evidencia revisada

- PDF `NUEVO SUBMODULO_INTERVENTORIA.pdf`, 10 páginas: propone Planes de
  mejora para Calidad, revisión satisfactoria de respuestas, devolución a
  responsables, agrupación de hallazgos, PDF por hallazgo, botones de copiar,
  evidencia inicial y mejoras de identificación/exportación de subsanaciones.
  Sus propuestas son insumos de diseño, no autorización para operar K2.
- Excel `k2_EstadoPlanMejoraOperador_2026-10-01.xlsx`, hoja
  `EstadoPlanMejoraOperador`: 14 columnas y 9 filas de datos. Incluye ID de
  visita, establecimiento, notificación, fecha de notificación, plazo de
  respuesta, ítem, hecho, compromiso, fecha de compromiso y seguimiento.
  No contiene número PM, plazo máximo de ejecución ni fecha propuesta de
  seguimiento como columnas separadas; no se pueden inferir sin otra fuente.
  El archivo declara dimensiones A1:A1 aunque contiene más datos: una futura
  importación debe recorrer los registros reales y validar las cabeceras.
- Consulta autenticada, solo lectura, de K2: Operador > Planes de Mejora >
  PM-4158 > visita 25133385. Se verificaron los campos obligatorios de fecha
  propuesta de ejecución, fecha propuesta para seguimiento y compromiso,
  acción de mejora u observación del operador. No se confirmó ni presentó nada.
- K2 muestra para PM-4158: notificación 27/09/2026, presentación 05/10/2026,
  ejecución máxima 27/10/2026. Esas fechas también aparecen en el PDF y el
  plazo de respuesta en el Excel. No equivalen a sumar 5 y 20 días calendario
  a la notificación; no se dedujo de ello una regla contractual.

## Flujo implementado

1. El administrador registra el **número de acta** y los porcentajes,
   conservando el contexto habitual de establecimiento, tipo y fecha de acta.
   Puede adjuntar el PDF desde el registro nuevo o una corrección. El PDF es
   opcional; no se exige evidencia inicial de los hallazgos. Los adjuntos
   históricos se conservan. El número mantiene la clave interna `idVisitaK2`
   por compatibilidad, sin migrar ni duplicar registros.
2. Se vinculan los hallazgos con sus tareas existentes. Cada responsable ve
   su respuesta pendiente y su entrega de soportes, con vencimientos distintos.
3. En la primera etapa se prepara el compromiso y sus fechas; no se exige
   evidencia de ejecución final para poder presentar el compromiso a tiempo.
4. Calidad revisa el texto y devuelve lo incompleto con motivo. La revisión
   para presentar el compromiso y la revisión de soportes son independientes.
5. Calidad construye el plan con número PM, CSC de notificación y fechas
   oficiales, agrupando hallazgos por establecimiento y visita. Un plan puede
   incluir varias visitas, como ocurre en el ejemplo real.
6. ToDo ofrece copiar compromiso, copiar fecha de ejecución y copiar fecha
   de seguimiento. Conserva además respuesta y referencias para el expediente.
7. Los responsables abren el plan desde su tarea existente y aportan evidencias
   de subsanación; también pueden reutilizar textos y archivos de la tarea.
   Calidad revisa una versión concreta; si cambia, se revisa nuevamente.
8. Cuando los soportes requeridos están satisfactorios, se genera un PDF por
   hallazgo y una descarga conjunta. Nombre propuesto sin colisiones:
   `PM_ESTABLECIMIENTO_IDVISITA_NUMERAL_IDHALLAZGO.pdf`.
9. Calidad registra por separado la presentación de respuesta y la carga de
   soportes en K2, con usuario, fecha, referencia/comprobante y versión enviada.
   Descargar o copiar no cambia esos estados. Presentado tampoco significa
   aceptado/cerrado por la interventoría.

El expediente conserva autores, fechas, versiones y procedencia de la evidencia
de subsanación. Las devoluciones y reaperturas quedan en historial del servidor;
no sustituyen la aprobación operativa que pertenece al aprobador de la tarea.

## Fechas comunes del plan

Al crear un plan se propone fecha de notificación +5 días para respuesta y
+20 días para soportes, sin excluir fines de semana ni festivos. Calidad
confirma o corrige ambas fechas máximas antes de guardar; todos los hallazgos
leen esas mismas fechas. El formulario explica este origen del cálculo y no
presenta los valores propuestos como fechas verificadas en K2. Registrar o
vincular después un hallazgo no reinicia los plazos. Cambiarlos requiere motivo
y conservar la compatibilidad con las fechas de compromiso ya registradas.

Los vencimientos se calculan por día civil en Colombia. Hay avisos de nueva
asignación, entrega, revisión y reapertura; el recordatorio diario empieza
tres días antes de cada máximo, a las 08:00 de Bogotá, y continúa si está
vencido. Una etapa aprobada pero sin presentación registrada sigue pendiente
para Calidad. El responsable actual y Calidad deben conservar acceso vigente.

## Encaje con ToDo y permisos

- Ampliar el módulo existente `interventoriadashboard`, sin duplicar tareas,
  responsables, empresas ni el catálogo de numerales.
- El modelo actual tiene un texto `planMejora` por hallazgo, no el expediente
  completo de plan PM/CSC con varios hallazgos y entregas externas.
- Ya existen roles de Calidad y seguimiento. La gestión de planes necesita
  capacidades explícitas de revisión, devolución, exportación y registro de
  presentación, aplicadas en interfaz y servidor. Los responsables solo
  aportan a sus tareas dentro de la empresa y cobertura que les corresponda.
- Se reutilizan el catálogo canónico de apps, el creador de roles de Admin y
  el nivel Calidad existentes. Servidor exige asignación canónica en la empresa;
  un rol histórico suelto no otorga permiso. Desarrollo mantiene el acceso
  técnico del guard del módulo sin necesitar asignarse el nivel Calidad.
  La pertenencia, habilitación y empresa se comprueban antes de ese acceso.
  No se agrega otro maestro ni una
  configuración duplicada: las fechas son datos operativos de cada plan.
  Los planes, respuestas y evidencias no se copian entre empresas.
- No almacenar las credenciales aportadas de K2 en código, documentos ni
  configuración cliente. Este flujo manual asistido no las necesita.
- Web: bandeja con filtros por establecimiento, fecha de acta, plan,
  responsable y vencimiento, y detalle lateral para revisar/copiar.
- Móvil: mis pendientes, respuesta, captura de evidencia y estado de revisión,
  con navegación compacta. Comparte reglas de negocio y permisos con Web.

## Correspondencia de identificadores e importación

Conservar por separado ID interno de visita, ID externo K2, ID del ítem K2,
numeral del acta, ordinal del hallazgo y número visible de tarea. El código
actual distingue `numeroHallazgo` de `numeralActa`: no son intercambiables.
La exportación de subsanaciones hoy usa `numeroHallazgo` y muestra solo
Sí/Sin tarea; requiere revisar el mapeo antes de alimentar un expediente K2.

La importación del Excel queda fuera de esta entrega. Como ampliación serviría
como entrada asistida, con vista previa y resolución explícita
de coincidencias. Buscar por empresa, notificación, visita y numeral; si hay
ambigüedad, no vincular automáticamente. Reimportar no debe duplicar planes
ni pisar respuestas. El filtro de correo CRF-K2 del PDF es una mejora posterior
para precargar borradores, con revisión humana y sin acceso entre empresas.

## Validación y límites

Se verificaron PDF completo, estructura del Excel, pantallas reales indicadas
de K2 y los puntos de integración del código. No se verificó una API oficial
de K2 ni los límites de carga de adjuntos. No se promete envío automático.

Validación: 252 pruebas Flutter de Interventoría y maestros; 25 de roles de
Admin; seis de política de fechas/revisión; diez de integración con Firestore
y Storage emulados. Incluyen empresa secundaria, rol histórico, revocación,
reactivación, reasignación, versiones, devoluciones, presentación y reapertura,
PDF real, protección de soportes y avisos idempotentes. Compilación TypeScript
y Web correctas. Se revisaron visualmente las capturas y la portada del PDF.

Pruebas de widgets: 390/768/1024/1366, escala de texto 1 y 1.6, temas Android e
iOS. No equivalen a pruebas en navegador autenticado ni dispositivos reales:
pendientes teclado, áreas seguras, cámara, selector y descarga en Android/iPhone.
También queda pendiente el despliegue coordinado de reglas, Functions y cliente.
Sin migraciones automáticas ni escrituras en K2.

Soportes admitidos: PDF/JPG/PNG, 5 MB por archivo y 12 archivos por hallazgo.
Se almacenan cifrados; solo el servicio autorizado devuelve el contenido.
La descarga conjunta genera ZIP con un PDF por hallazgo, hasta 100 MB de
fuentes; paquetes grandes se transfieren por partes con vigencia de una hora.
Estos límites pertenecen a ToDo, no se verificaron como límites de K2.
