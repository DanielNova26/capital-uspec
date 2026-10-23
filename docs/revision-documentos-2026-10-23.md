# Revisión de documentos de Interventoría Tareas y Visitas

Revisión del código de `main` frente a los cinco archivos entregados el 23 de octubre de 2026. Los PDF y Word se usaron como referencias de requisitos. Las instrucciones de enviar capturas, responder encuestas, entregar hardware o contactar personas no se ejecutaron como órdenes del usuario.

## Fuentes revisadas

1. La reunión se inició a las 2026_10_22 10_01 GMT-05_00 - Notas de Gemini.pdf
2. NUEVO SUBMODULO_INTERVENTORIA (3).pdf
3. Visitas  - octubre 03 (2).docx
4. TAREAS - SEPTIEMBRE 16 DE 2026.docx
5. Interventoria - octubre 01.docx

Los documentos 2 y 5 repiten gran parte del mismo pedido. Se consolidaron los requisitos para no crear dos soluciones ni duplicar maestros. Se conservaron las decisiones posteriores documentadas en MEJORAS.md: fotos iniciales opcionales, permisos canónicos de Calidad/Gerencia/Desarrollo, número de acta obligatorio para vincular y calendarios para fechas.

## Contraste e implementación

| Pedido | Qué había | Resultado de esta revisión |
| --- | --- | --- |
| Observaciones al solicitar reasignación de tareas | Selector de persona/área, sin observaciones | Campo opcional de hasta 2000 caracteres; guardado transaccional, visible para quien decide e incluido en el aviso y el último evento. Reglas validan tipo y longitud. Interventoría conserva su reasignación directa y no abre solicitudes que sustituyan al aprobador del maestro. |
| Análisis por tipo de acta | Filtros de establecimiento, categoría y fechas | Filtro de tipo de acta aplicado a gráficos, matriz y Excel. |
| Calidad consulta respuestas y archivos antes de aprobar | El servidor devolvía listas vacías | Vista previa de texto, PDF e imágenes. Se mantiene la comprobación de empresa, rol y vínculos tarea/hallazgo/visita. Los otros usuarios conservan las restricciones de consulta. |
| Botones inhabilitados mientras se aprueba | Existía excepción que dejaba enviar respuestas propias de Calidad | Consulta permitida; incorporar, adjuntar, retirar y enviar respuestas exige tarea aprobada también para Calidad. Revisión y presentación siguen bloqueadas. Cambia expresamente la excepción del 15 de octubre. |
| Cargo de quien aprueba | Nombre del aprobador | Se muestra también su cargo en la empresa activa; no se usa el cargo de otra empresa. |
| Número real del hallazgo | El tablero reconocía numeral real; tabla y Excel usaban el ordinal interno | Número visible compartido en tablero, tabla y Excel. Un ordinal de acta sin numeral confirmado se identifica como «Sin numeral identificado». No se inventan numerales ni se modifica el histórico. |
| ID de visita de Interventoría | Guardado en el acta como idVisitaK2 | Visible en tarjetas y tabla; columna ID de visita en Excel, conservando ceros iniciales. Se distingue del ID interno de Firestore. |
| Estado y número de tarea en fichas | Tarjeta con asignación y fecha, sin número de tarea | Número y estado actual desde la tarea vinculada. Comprobación de empresa/módulo/hallazgo antes de mostrar o exportar sus datos. |
| Excel coherente con la pantalla | Exportaba filtros, pero omitía ID de visita y número de tarea y podía mostrar ordinales | Se conservan filtros y orden; se corrige numeral y se agregan ID de visita, número y estado de tarea. La tarea no se resuelve desde una referencia de otra empresa o de otro hallazgo. |
| Planes de mejora para Calidad | Ya implementado, con Gerencia de Interventoría y Desarrollo autorizados | Se conserva el catálogo y la jerarquía actuales; no se amplía a todos los administradores. |
| Crear plan con proceso, CSC, notificación, plazos y responsable | Ya implementado | Se conserva. Fechas por calendario y responsable de gestión vigente. |
| Vincular varias actas y hallazgos por establecimiento | Ya implementado, hasta 40 hallazgos por operación | Se conserva sin duplicar hallazgos ni cambiar asignaciones. |
| Satisfactorio, devolución y PDF por hallazgo | Ya implementado, con versiones y aprobación de la tarea | Se conserva; consultar antes de aprobar no habilita exportar una entrega como aprobada. |
| Reactivar una tarea por respuesta insuficiente | Reapertura de entregas; no devolvía la misma tarea desde Planes | Acción de Calidad con motivo y nueva fecha. Conserva ID, número, responsable, aprobador e historial de la tarea; la deja devuelta, reabre el hallazgo e invalida revisiones/presentaciones en todos los planes activos de la tarea dentro de la empresa. Se conserva auditoría de lo presentado. Reintentos o versiones antiguas no duplican la devolución. |
| Compromiso, ejecución, seguimiento y copiar | Ya implementado | Se conserva; copiar/incorporar contenido pendiente sigue deshabilitado hasta aprobación. |
| Evidencia fotográfica inicial | Acta original como contexto; sin campo separado por hallazgo del plan | Fotografía inicial opcional JPG/PNG en el hallazgo del plan, administrada por gestores autorizados. Cifrada, consultable y auditada; se incluye por separado en el expediente y no cuenta como evidencia de subsanación. No se exige al registrador/administrador al crear el acta. |
| Alertar a responsables | Avisos internos de entrega, corrección, vencimiento y recordatorios ya existentes | Se conserva; reactivación avisa al responsable vigente. No se envían mensajes reales durante las pruebas con emuladores. |
| Filtrar por fecha del acta | Ya implementado en subsanaciones y planes | Se conserva. |
| Descuento directo en una entrega y cinco días | Plazos de cinco días, pero dos envíos | Formulario y envío conjuntos. El servidor guarda ambas versiones en una transacción y exige compromiso, fechas, respuesta y soportes válidos. Clientes antiguos reciben indicación de actualizar cuando intentan separarlos. |
| Guardar ID de Visitas propias | Numeración de visita ya persistida y mostrada en cronograma, detalle e informe | Se conserva; no se confunde con el ID de visita asignado por Interventoría. |
| Consultar todas las visitas del mes por profesional | Filtro profesional, pero detalle del calendario por día | Botón «Ver visitas del mes» que respeta profesional, establecimiento, estado y departamento. En teléfono abre una lista en panel; en escritorio conserva calendario y lista simultáneos. |
| Filtros de establecimiento y profesional en reportes | Consolidado por periodo y departamento | Se agregan ambos filtros, incluyendo distinción de subcentros. Resumen y PDF usan el mismo conjunto. Al cambiar de empresa/usuario se renuevan fuentes y filtros. |
| Informe individual de cada visita | Ya implementado desde el detalle | Se conserva y reutiliza; no se crea otro generador. |
| Detalles, fotos y anexos del consolidado | Existían como opciones; se descartaban fotos después de la 80 de una visita | Consolidado completo con actas/fotos activadas de entrada, conservando las opciones de resumen. Se elimina el recorte silencioso de fotos; una imagen que no se puede descargar conserva su referencia en el informe. |
| Marcas de agua en fotografías | Ya implementadas al capturar | Se conservan. |
| Biométrico dentro de Talento Humano y ortografía | Módulo independiente, rótulo «Biométrico» correcto | Acceso dentro de Talento Humano con comprobación independiente de biometricodashboard. Se mantiene la entrada directa para quien solo tiene Biométrico; mover la navegación no concede permisos de asistencia ni de TH. |

## Propuestas y tareas externas

- El seguimiento de correos CRF-K2 aparece expresamente como **idea** en los documentos de septiembre/octubre, no como integración acordada en la reunión del 22. No se conectó un buzón ni se concedió acceso a mensajes. Para convertirla en integración faltan el buzón autorizado por empresa, ejemplos reales y los campos que se pueden extraer con certeza. Los planes se siguen creando con el formulario existente.
- Carcasa, pruebas físicas del lector, instalar diseños de Arduino y enviar capturas son trabajos externos. La solicitud actual no autorizó contactar personas ni enviar archivos; no se ejecutaron esas instrucciones del acta.
- Las vacantes de cargos y la cobertura/grupos que se citan en la reunión se corrigen con datos de Talento Humano/Admin. No se asignaron personas ni se migraron datos productivos a partir de nombres incluidos en los documentos.

## Entrega y límites

No hay nuevas apps, roles, maestros ni colecciones: se amplían flujos existentes con sus permisos y empresa activa. Las fotografías iniciales son documentos del expediente operativo, no maestros copiables entre empresas.

Para activar estos cambios se requiere publicar Web, la función `interventoriaPlanes` y las reglas de Firestore, además de compilar/publicar las apps móviles. No se publican automáticamente ni se modifican datos de producción en esta revisión. Las apps antiguas no pueden realizar la entrega conjunta de descuento directo una vez actualizado el servidor.

Validación y plataformas verificadas: consultar la entrada del 23 de octubre de 2026 en MEJORAS.md. Las pruebas de widgets con temas Android/iOS no sustituyen ensayos en dispositivos físicos, cámara, teclado, descarga de archivos o firma/publicación de iOS.
