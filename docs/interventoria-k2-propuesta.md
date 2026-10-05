# Interventoría: preparación de planes para K2

Fecha: 5 de octubre de 2026. Estado: propuesta funcional contrastada con K2,
los documentos aportados y el código local; **no implementada ni desplegada**.

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

## Flujo propuesto

1. El administrador registra el acta con su ID externo de visita y evidencia
   inicial. Se conservan la fecha de visita, de notificación y de registro.
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
7. Los responsables adjuntan evidencias de cumplimiento a sus tareas. Calidad
   revisa la versión concreta de texto y adjuntos; si cambia, se revisa de nuevo.
8. Cuando los soportes requeridos están satisfactorios, se genera un PDF por
   hallazgo y una descarga conjunta. Nombre propuesto sin colisiones:
   `PM_ESTABLECIMIENTO_IDVISITA_NUMERAL_IDHALLAZGO.pdf`.
9. Calidad registra por separado la presentación de respuesta y la carga de
   soportes en K2, con usuario, fecha, referencia/comprobante y versión enviada.
   Descargar o copiar no cambia esos estados. Presentado tampoco significa
   aceptado/cerrado por la interventoría.

El expediente conserva la evidencia inicial separada de la evidencia de
subsanación, sus autores, fechas y procedencia. La devolución de Calidad debe
mantener la historia y la asignación; no sustituye silenciosamente la aprobación
operativa que hoy pertenece al aprobador de la tarea.

## Plazos que falta precisar

- Fecha de inicio: notificación oficial, fecha del acta o registro en ToDo.
- Si los 20 días parten del mismo origen que los 5 o de presentar la respuesta.
- Si los plazos indicados son metas internas o vencimientos externos.

Propuesta: almacenar ambos plazos internos y las fechas oficiales de K2,
mostrar discrepancias y no reemplazar una fecha externa por un cálculo local.
Usar días calendario y zona America/Bogota, con convención explícita de día
inicial y hora de cierre. Cargar tarde un acta no debe reiniciar un plazo
oficial. Las alertas deben distinguir respuesta, soportes y carga externa,
con responsables y Calidad como destinatarios según su acceso vigente.

## Encaje con ToDo y permisos

- Ampliar el módulo existente `interventoriadashboard`, sin duplicar tareas,
  responsables, empresas ni el catálogo de numerales.
- El modelo actual tiene un texto `planMejora` por hallazgo, no el expediente
  completo de plan PM/CSC con varios hallazgos y entregas externas.
- Ya existen roles de Calidad y seguimiento. La gestión de planes necesita
  capacidades explícitas de revisión, devolución, exportación y registro de
  presentación, aplicadas en interfaz y servidor. Los responsables solo
  aportan a sus tareas dentro de la empresa y cobertura que les corresponda.
- Mantener coherencia con Admin, roles, revocación y reactivación; registrar
  los parámetros copiables en los catálogos de maestros cliente y servidor.
  Los planes, respuestas y evidencias operativos no se copian entre empresas.
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

El Excel sirve como entrada asistida, con vista previa y resolución explícita
de coincidencias. Buscar por empresa, notificación, visita y numeral; si hay
ambigüedad, no vincular automáticamente. Reimportar no debe duplicar planes
ni pisar respuestas. El filtro de correo CRF-K2 del PDF es una mejora posterior
para precargar borradores, con revisión humana y sin acceso entre empresas.

## Validación y límites

Se verificaron PDF completo, estructura del Excel, pantallas reales indicadas
de K2 y los puntos de integración del código. No se verificó una API oficial
de K2 ni los límites de carga de adjuntos. No se promete envío automático.

Antes de implementar/cerrar: resolver los plazos; probar asociación y
reimportación, numerales, versiones aprobadas, devoluciones, entregas
parciales, auditoría, empresa secundaria, permisos históricos, revocación y
reactivación, y alertas sin duplicados. Validar reglas/servicios y descargas.
Probar Web a 390/768/1024/1366 y texto ampliado; Android e iOS por separado,
con teclado, áreas seguras, cámara/archivos y permisos. Ninguna de estas
pruebas de la nueva funcionalidad se ha realizado: aún no existe implementación.
