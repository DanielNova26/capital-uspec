# Relevo técnico y funcional — Módulo de Compras

Fecha de actualización: 30 de julio de 2026  
Proyecto Firebase: `integra360-94704`  
Aplicación publicada: <https://to-do-gestion.web.app/>  
Repositorio local: `C:\Desarrollo\capital-uspec`

## Objetivo de este documento

Este archivo conserva las decisiones tomadas con el usuario, lo que ya fue
implementado y desplegado, las validaciones ejecutadas y el trabajo pendiente.
Debe servir para que Claude continúe apoyando la arquitectura, Firestore,
reglas, repositorios, validaciones e integraciones sin perder el contexto.

## Reglas de colaboración del proyecto

Según `AGENTS.md`:

- Web y móvil comparten negocio, empresa activa, roles y permisos, pero no
  deben tener exactamente la misma experiencia visual.
- Gemini se encarga principalmente de diseño, layouts y experiencia visual.
- Claude se encarga de Firestore, reglas, arquitectura, repositorios,
  validaciones, integraciones y estabilidad.
- Codex se encarga de flujo funcional, navegación por rol, permisos, pruebas,
  integración final y Git/GitHub.
- Solo Codex debe ejecutar `git add`, `git commit` y `git push`.

El árbol de trabajo contiene muchos cambios previos sin confirmar. No se deben
revertir, sobrescribir ni limpiar cambios ajenos.

## Decisiones funcionales definitivas

### Documentos del proveedor

Los documentos propios del proveedor que actualmente se muestran son:

- RUT.
- Cámara de Comercio.
- Acta IVC de planta de producción.
- Acta IVC del vehículo transportador.
- Examen médico ocupacional.
- Curso o certificado de manipulación de alimentos.
- Autorización sanitaria.

Los siguientes documentos son exclusivos del producto o de su marca y no deben
solicitarse ni validarse como documentos del proveedor:

- Ficha técnica.
- Registro sanitario.
- Soporte de registro sanitario INVIMA.
- Ficha técnica con registro sanitario y dosificaciones.

Los documentos exclusivos del producto se administran desde los documentos
asociados a la marca. Se conserva información histórica que haya quedado
guardada anteriormente en proveedores, pero se oculta y no bloquea el flujo.

### Lista definitiva de documentos con vigencia

Solo estos documentos deben pedir `Vigente hasta`, aparecer en el centro de
vigencias y generar alertas:

- `rut`
- `camaraComercio`
- `actaIvcPlanta`
- `actaIvcVehiculo`
- `examenMedico`
- `cursoManipulacion`
- `autorizacionSanitaria`

No deben pedir vigencia:

- Fichas técnicas.
- Registros sanitarios del producto.
- Vistos buenos sanitarios.
- Permisos zoosanitarios.
- Certificaciones sanitarias de importación.
- Otros documentos de recepción.

Las fechas históricas de estos últimos documentos no se borran, pero se ignoran
en el centro de vigencias y en las alertas.

### Guardado progresivo

El proveedor puede guardarse aunque:

- falte uno o varios documentos;
- falte una fecha de vigencia;
- exista un documento rechazado pendiente de corrección.

Los documentos continúan siendo pendientes para completar el expediente, pero
no bloquean el guardado del avance. Solamente NIT y razón social siguen siendo
obligatorios para guardar el proveedor.

El formulario informa que se puede guardar por avances. Al guardar un
expediente incompleto muestra una confirmación naranja; cuando está completo
muestra la confirmación normal en verde.

### Guardado automático de vigencias

En proveedores existentes, seleccionar o cambiar `Vigente hasta` actualiza
inmediatamente el documento en Firestore. No es necesario volver a cargar el
archivo ni pulsar el botón general `Guardar`.

Para proveedores nuevos todavía sin ID, la fecha permanece en el formulario y
se persiste al crear el proveedor.

Las fechas elegidas en versiones antiguas que nunca pudieron guardarse por una
validación bloqueante deben seleccionarse nuevamente una sola vez.

### Alertas de vigencias

La función desplegada es:

`comprasNotificarVigenciasDocumentales`

Configuración:

- Región: `us-central1`.
- Programación: todos los días a las `08:00`.
- Zona horaria: `America/Bogota`.
- Estado verificado: activo.
- Versión verificada al cerrar este relevo: `3`.

Comportamiento:

- Empieza a notificar desde siete días antes del vencimiento.
- Continúa diariamente si el documento ya venció.
- Se detiene cuando el archivo se reemplaza o se registra una nueva vigencia
  superior al periodo de alerta.
- Envía la alerta al usuario guardado en `subidoPor`.
- Para documentos antiguos sin `subidoPor`, usa el creador del registro cuando
  está disponible.
- Crea máximo una alerta por documento, usuario y día.
- Las alertas aparecen en la campana global de la aplicación.
- Al pulsarlas abre el proveedor o la recepción correspondiente.
- Solo procesa las siete llaves de la lista definitiva.

### Productos, marcas y fichas

- Cada producto debe asociarse al menos a una marca.
- Ficha técnica y registro sanitario se administran como documentos asociados
  a la marca, no como documentos principales del proveedor.
- La ficha técnica y el registro sanitario ya no exigen fecha de vigencia.
- Se conserva compatibilidad con estructuras históricas del producto.

### WhatsApp y notificaciones de nuevos proveedores

- WhatsApp se usa para proveedores nuevos.
- La configuración y los listados de destinatarios se centralizaron en el
  panel administrativo.
- Cada listado se asocia al módulo correspondiente.
- El alta manual de un proveedor dispara la función:
  `comprasNotificarNuevoProveedorWhatsApp`.
- La campana global notifica al creador y a Calidad.
- Se eliminó el bloque interno duplicado denominado “Notificaciones de
  calidad”; cada notificación debe estar en su lugar correspondiente.

Advertencia funcional pendiente de confirmación: actualmente un proveedor nuevo
puede guardarse con documentación incompleta y eso puede disparar la
notificación de nuevo proveedor. Confirmar con el usuario si WhatsApp debe
enviarse al crear el registro inicial o únicamente al completar el expediente.

### Recepción de mercancía

El flujo acordado busca que:

- al guardar, la recepción quede cerrada;
- no se agregue documentación posteriormente de forma libre;
- si Calidad rechaza un documento, se habilite únicamente la corrección de los
  documentos rechazados;
- al reemplazar todos los rechazados, la recepción vuelva a revisión;
- una recepción cerrada y sin rechazos no admita correcciones.

Existen pruebas funcionales para cierre, clasificación documental, rechazados,
pendientes e histórico.

### Consultas de Compras

Se trabajó en:

- visual adaptable para escritorio y tableta;
- evitar que la tarjeta superior bloquee el contenido inferior;
- filtros y semáforos coherentes con el resto del módulo;
- exportación Excel;
- consultas de proveedores, productos, marcas y recepciones.

Las pruebas del exportador XLSX están pasando, pero todavía conviene hacer una
prueba manual autenticada de cada botón de descarga en producción.

## Archivos clave modificados

- `lib/compras/compras_dashboard_screen.dart`
  - Formulario de proveedores.
  - Guardado progresivo.
  - Autoguardado de fechas.
  - Centro de vigencias.
  - Productos, marcas, fichas, recepción y consultas.
- `lib/compras/compras_models.dart`
  - Etiquetas y llaves documentales.
  - Modelos de proveedor, producto, marca, recepción y adjuntos.
- `lib/compras/compras_validation.dart`
  - Lista definitiva de documentos con vigencia.
  - Validación de documentos.
  - Resumen no bloqueante de pendientes.
- `lib/compras/compras_service.dart`
  - Persistencia en Firestore y operaciones documentales.
- `functions/src/compras_expiration_notifications.ts`
  - Proceso diario de alertas de vigencia.
- `functions/src/compras_notifications.ts`
  - Notificación WhatsApp para proveedores nuevos.
- `lib/home/notifications_screen.dart`
  - Navegación desde la campana global.
- `lib/services/notification_service.dart`
  - Enrutamiento de notificaciones recibidas.
- `lib/admin/whatsapp_admin_panel.dart`
  - Administración centralizada de WhatsApp.
- `lib/admin/whatsapp_admin_service.dart`
  - Persistencia de configuración y listados.
- `test/compras/compras_validation_test.dart`
  - Vigencias, separación proveedor/producto y guardado progresivo.
- `test/compras/compras_recepcion_logic_test.dart`
  - Flujo funcional de recepción.
- `test/compras/compras_excel_export_test.dart`
  - Generación de archivos XLSX.

## Estado de validación y despliegue

Última ejecución completa:

- `flutter test`: 91 pruebas aprobadas.
- `flutter build web --release`: compilación correcta.
- Hosting publicado correctamente.
- Respuesta de producción verificada: HTTP `200`.
- Función de alertas verificada como activa.

Último despliegue de interfaz:

```powershell
firebase deploy --only "hosting:to-do-gestion"
```

Despliegue de interfaz y función de vigencias:

```powershell
firebase deploy --only "functions:comprasNotificarVigenciasDocumentales,hosting:to-do-gestion"
```

Advertencias técnicas conocidas:

- Node.js 20 está marcado como obsoleto y será retirado el 30 de octubre de
  2026. Se debe planear la actualización del runtime.
- El paquete `firebase-functions` reporta una versión desactualizada. La
  actualización puede contener cambios incompatibles y debe hacerse con
  pruebas.
- El proyecto tiene avisos informativos de Flutter por APIs visuales obsoletas,
  pero no se detectaron errores de compilación relacionados con estos cambios.

## Trabajo recomendado para Claude

### Prioridad alta

1. Revisar en Firestore `TBL_COMPRAS_REQ_DOCUMENTOS` si debe crearse una regla
   para `autorizacionSanitaria`.
2. Confirmar con negocio si la autorización sanitaria es obligatoria para todos
   los proveedores o solo para categorías/orígenes específicos. El usuario solo
   confirmó que tiene vigencia; no confirmó que siempre sea obligatoria.
3. Verificar que reglas de Firestore permitan actualizar:
   `documentos.<docKey>.fechaVencimiento`, sin ampliar permisos indebidos.
4. Revisar datos históricos de proveedores con:
   `soporteRegistroInvima`, `fichaTecnicaDosificacion` o
   `fichaTecnicaProv`. No eliminarlos ni migrarlos sin poder asociarlos con
   certeza a un producto y una marca.
5. Proponer una migración segura únicamente si existe una relación inequívoca
   proveedor-producto-marca.
6. Revisar si un proveedor incompleto debe disparar WhatsApp inmediatamente o
   si la notificación debe esperar un estado `documentacionCompleta`.

### Prioridad media

1. Añadir un estado documental persistido, por ejemplo:
   `documentacionCompleta`, `pendientesDocumentales` y `updatedAt`, si se
   necesita filtrar expedientes incompletos desde consultas.
2. Evaluar consultas e índices de Firestore para el centro de vigencias si el
   volumen crece. La función programada actualmente recorre las colecciones.
3. Preparar la actualización del runtime de Functions y de
   `firebase-functions`.
4. Revisar reglas e índices para los listados centralizados de WhatsApp.
5. Confirmar que el usuario `subidoPor` siempre corresponda con la llave usada
   en `TBL_NOTIFICACIONES/{userId}`.

## Tareas pendientes del usuario / validación funcional

1. Actualizar la aplicación con `Ctrl + F5`.
2. Abrir un proveedor existente y comprobar:
   - cambiar la fecha del RUT;
   - observar el mensaje de guardado automático;
   - salir y volver a entrar para confirmar persistencia.
3. Guardar un proveedor sin Cámara de Comercio o sin alguna vigencia:
   - debe permitir guardar;
   - debe mostrar “avance documental guardado”;
   - los pendientes deben continuar visibles.
4. Abrir `Vigencias documentales` y comprobar que solo aparezcan:
   RUT, Cámara de Comercio, Actas IVC, exámenes médicos ocupacionales, cursos de
   manipulación y autorización sanitaria.
5. Crear un proveedor de prueba y validar:
   - notificación en la campana;
   - mensaje de WhatsApp al listado de Compras;
   - destinatarios correctos.
6. Probar las descargas Excel de cada consulta.
7. Probar una recepción:
   - guardarla y confirmar el cierre;
   - rechazar un documento desde Calidad;
   - comprobar que solo el rechazado pueda reemplazarse;
   - verificar el retorno a revisión.
8. Confirmar si WhatsApp debe enviarse cuando se crea un proveedor incompleto o
   solamente cuando se complete su documentación.
9. Confirmar si `Autorización sanitaria` aplica a todos los proveedores o a
   categorías específicas.

## Criterios para no perder el rumbo

- No volver a poner fichas técnicas o registros sanitarios dentro del
  proveedor.
- No volver a bloquear el guardado por documentación pendiente.
- No borrar datos históricos sin una migración trazable.
- Mantener una sola campana global de notificaciones.
- Mantener listas de destinatarios centralizadas y asociadas por módulo.
- Las vigencias y alertas deben usar únicamente el listado definitivo.
- Toda modificación de backend debe conservar empresa activa, roles y permisos.
- Antes de desplegar, ejecutar pruebas específicas, suite completa y compilación
  web.
- No hacer Git desde Claude; el cierre de Git corresponde a Codex.

