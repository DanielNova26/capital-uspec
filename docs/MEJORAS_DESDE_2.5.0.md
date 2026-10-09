# Mejoras de ToDo desde la 2.5.0 (12) hasta la 2.6.25 (39)

La 2.5.0 (12) es la última versión de iPhone que muestra la App Store (11 sep 2026).
La 2.6.25 (39) es la versión actual (9 oct 2026). Este resumen sale de la
bitácora `MEJORAS.md` y está escrito por módulo, sin detalles técnicos.

## Interventoría
- El registrador corrige el acta en vez de pedir que la borren: Calidad la
  devuelve, aparece el botón Corregir y al guardar vuelve a Por revisar con
  PDF, puntajes e historial intactos.
- Devolver un acta con errores también funciona en la Fase 1, antes de revisarla.
- Cada acta del histórico muestra la hora real en que se subió.
- El subcentro ya no es obligatorio al registrar el acta.
- Asignación de hallazgos con resumen verificable y reparación de los que
  nunca le llegaron a nadie. Las devoluciones dejan una tarea obligatoria.
- Se puede asignar un aprobador a mano cuando el numeral no tiene regla.
- Concepto sanitario automático: al elegir el establecimiento se llena con el
  último concepto cargado. No suma al porcentaje total del acta.
- Informe de Gerencia con filtro y agrupación por responsable, administrador
  de establecimiento y director de área. Gerencia ve Interventoría con el
  responsable y su jefe inmediato.
- Análisis muestra el tipo de acta.
- Notificaciones de Interventoría y calendario corregidos: ya no llegan a
  todo el mundo ni muestran hallazgos que reciben los aprobadores.

## Planes de mejora (K2)
- Fechas con calendario (notificación, máximas, ejecución y seguimiento).
- Filtros combinables por establecimiento, grupo, responsable, numeral y fechas.
- Estados propios del plan: Recibido, En gestión, Enviado y Mesa de descuentos.
- Responsable de K2 seleccionable y historial de cambios.
- Fuentes y responsables precargados desde las tareas finalizadas y aprobadas.
- Descarga de soportes en partes y copia reducida a 5 MB (JPG/PNG y PDF).
- Soportes adjuntos con cantidad, procedencia y descarga.
- Agenda de Inicio con los dos vencimientos y alertas diarias a las 08:00,
  desde tres días antes.
- Expediente y descuentos: descarga ZIP con un PDF por hallazgo, anexos,
  índice, plazos, revisiones, constancias de presentación e historial.

## Visitas
- Formato SST oficial (inspección, extintor y botiquín), con ubicación
  obligatoria, firma del profesional y del responsable, y calendario.
- Búsqueda de lugares con Google Maps y subcentros como establecimiento.
- Formatos como Google Forms o Excel, acta fija, anexos y consolidado por fechas.
- Rol Gerencia por cargo, sin tener que asignarlo.
- Equipo como maestro, varias fechas por visita y ejecución por secciones.
- Número de visita (Visita No 00001) y establecimientos propios de Visitas en Admin.
- Nuevo rol Coordinador (solo consulta): ve en el Cronograma las visitas de
  los profesionales de sus grupos.
- Grupos de Visitas separados de los grupos de la empresa.
- Cronograma móvil mejorado.

## Tareas
- Completar tareas con comentario, también desde Interventoría.
- Al enviar una novedad, la app pregunta si en realidad es una finalización.
- Historial de novedades y finalizaciones, y reasignación a otras áreas.
- Número consecutivo interno por empresa para cada tarea (incluye las existentes).
- Documento de mejoras de octubre: Reportar avance, Por aprobar, Mi equipo
  y dictado en la creación.

## Compras y Abastecimiento
- Plantilla oficial de abastecimiento generada desde la app. El período de
  consumo se elige al cargar y aplica a toda la carga.
- Modelo Excel con listas desplegables (proveedores, categorías, grupos, estado).
- Período configurable y orden de compra (OC) como identidad.
- Indicadores según el período elegido.
- Presentaciones por unidad de medida y corrección de recepciones por Bodega.
- Bodega puede quitar el archivo rechazado. Cronómetro de Calidad.
- Registro sanitario solo del producto, no de la marca.
- Excel de productos separado por marca y proveedor.

## Planillas de Pago
- Archivo plano de pagos tomado de la planilla firmada.
- Maestro de beneficiarios de pago (no de nómina) con pantalla propia y
  modelo Excel.
- Descarga del plano desde Planillas.
- Avisos por WhatsApp al cambiar la firma.
- Corrección: Planillas de Pago ya no aparece y desaparece en el Home del gerente.

## Talento Humano y personal
- Cobertura de operación: las sedes donde la persona puede atender visitas,
  distinta del centro de costos.
- Subcentros de costo y accesos en bloque por cargo.
- Carnet imprimible con QR.
- Informe de avance de reclutamiento y borrado de novedades del historial.
- Proceso disciplinario en cuatro pasos, con doce resultados según el
  reglamento y aviso al citado por la app y por WhatsApp.
- Jefe directo en Ver personal: ya trae nombres y no la cédula.

## Biblioteca y Gestión Documental
- Carpetas temáticas, alias o código externo, normograma único y check de Calidad.
- Plantilla Word del formato institucional, además del Excel, con el
  encabezado del modelo del jefe.
- Corrección de caída por índice faltante.

## Correspondencia y Facturación
- Correspondencia: "Contestado" con quién y qué contestó, y cierre con
  motivo, justificación y soporte.
- Facturación: las observaciones de una devolución ya se ven. Corregido el
  autor que salía como cédula y el mes que se pintaba.

## Notificaciones y WhatsApp
- WhatsApp Meta para entrega y avisos automáticos.
- Corregido el aviso de nueva acta, que no salía nunca.
- Maestro de notificaciones (Admin › Maestros por módulo › Tareas y
  notificaciones): tabla tipo × canal (campana, push, WhatsApp) por empresa.
  Los avisos críticos no se apagan.
- Preferencias personales de avisos y avisos de planillas a Tesorería.
- Logo de la empresa en marcas de agua e informes, nunca el de la app.
- Quien está inhabilitado no recibe push de ningún módulo.

## Admin y multiempresa
- Gestión interna unificada: catálogos y bodegas, grupos, membresía y multiempresa.
- Un solo editor de grupos de la empresa (`Admin › Gestión interna › Grupos`).
- Maestros por módulo con "Copiar a otras empresas": agrega lo que falta y
  nunca pisa lo existente.
- Roles configurables para Talento Humano, Nutrición y Tokens DIAN.
- Clave inicial 123456 para personas nuevas y registro de accesos.
- Limpieza por módulo (cerrar lo real sin borrar y borrar lo de prueba).
- Crear una empresa pidiendo solo el nombre.
- Migraciones y Logs revisados.

## Estabilidad y plataforma
- Reglas de Firestore reforzadas para roles configurables, planes, grupos,
  avisos y preferencias, verificadas por pruebas de reglas.
- Web: la publicación se detiene si la compilación no coincide con la versión.
- Textos de interfaz probados a escala 1,6× y en anchos de 390, 768, 1024
  y 1366.
- Corrección de las notificaciones que no llegaban en iPhone.
- Barra de scroll horizontal solo donde hay puntero (no en móvil).

## Pendiente
- Pruebas autenticadas de producción y en Android e iPhone físicos de los
  flujos nuevos (cámara, teclado, selector de archivos, descarga nativa).
- Firma y publicación de iOS 2.6.25 (requiere Mac) y subida del `.aab` de
  Android.
- Revisión controlada de grupos de Visitas creados antes de la separación.
