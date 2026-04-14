# Scan funcional e integrador: Nutricion

## Flujo funcional actual

El modulo Nutricion existe hoy como un flujo real, no como maqueta aislada. El punto de entrada es `NutricionDashboardScreen`, abierto desde Home y protegido por `GuardedModulePage` con `appId: nutriciondashboard`. El dashboard recibe `userId` y `empresaId`, por lo que ya queda amarrado a empresa activa y a la semantica de acceso de Fase 1.

Flujo actual observado en codigo:

1. Entrada desde Home a `NutricionDashboardScreen`.
2. Seed inicial por empresa de ingredientes base y plantillas de menus si no existen.
3. Seleccion o carga de paciente desde directorio nutricional.
4. Evaluacion antropometrica con guardado de mediciones sobre el paciente.
5. Registro de historia clinica y habitos.
6. Seleccion de diagnosticos medicos y nutricionales desde catalogos CIE y catalogos nutricionales.
7. Sugerencia / seleccion de dietas.
8. Definicion de fechas de inicio y reevaluacion.
9. Guardado del expediente del paciente en directorio e historial.
10. Agendamiento de reevaluacion con reflejo en notificaciones.
11. Carga de evidencias.
12. Generacion de PDF del reporte nutricional.
13. Navegacion a submodulos: Menus, Pacientes, Firmas, Reportes.

## Entradas y salidas principales

Entradas principales:

- `userId`
- `empresaId`
- establecimiento y semana para menus
- datos del paciente: nombre, documento, regimen, diagnosticos, observaciones
- mediciones: peso, talla, perimetro, notas
- diagnosticos medicos y nutricionales
- dieta seleccionada, fechas de inicio y reevaluacion
- firma, sello y evidencias fotograficas

Salidas principales en datos:

- `TBL_PACIENTES`
- `TBL_DIRECTORIO_NUTRICION`
- `TBL_HISTORIAL_NUTRICION`
- `TBL_EVALUACIONES_DIAGNOSTICAS`
- `TBL_CITAS_NUTRICION`
- `TBL_NOTIFICACIONES`
- `TBL_INGREDIENTES`
- `TBL_PLANTILLAS_MENUS`
- `TBL_MENUS`
- `TBL_FIRMAS`
- `TBL_EVIDENCIAS_NUTRICION`
- exportacion Excel via `NutricionReportService`
- PDF via `NutricionPdfService`

## Dependencias entre pantallas

Dependencia principal:

- `Home` abre `NutricionDashboardScreen`.

Dependencias internas del dashboard:

- `NutricionDashboardScreen` usa `EvaluacionNutricionalWidget`.
- `NutricionDashboardScreen` usa `SelectorDiagnosticosWidget`.
- `NutricionDashboardScreen` llama `NutricionAtencionActions` para historia clinica.
- `NutricionDashboardScreen` usa `NutricionService`, `DiagnosticosService`, `CitasNutricionService` y `NutricionPdfService`.
- `NutricionDashboardScreen` abre `NutricionMenusScreen`.
- `NutricionDashboardScreen` abre `NutricionCatalogosScreen`.
- `NutricionDashboardScreen` abre `NutricionFirmasScreen`.
- `NutricionDashboardScreen` abre `NutricionReportesScreen`.

Dependencias secundarias:

- `NutricionMenusScreen` depende de `NutricionIngredientesScreen`.
- `NutricionReportesScreen` depende de `NutricionDashboardHelper` y este de `NutricionReportService`.
- `EntradaDiagnosticosScreen` depende de `DiagnosticosService`, pero no aparece hoy como ruta principal del dashboard; el dashboard usa mas bien `SelectorDiagnosticosWidget`.

## Permisos, acceso y navegacion

Acceso actual:

- El modulo esta protegido por `AccessGuard` en el dashboard principal con `nutriciondashboard`.
- La entrada desde Home tambien depende de visibilidad por apps/permisos del usuario.
- No observe guard fino por subpantalla dentro de Nutricion; hoy el control fuerte esta a nivel modulo.

Rutas y navegacion reales:

- Ruta principal desde `home_screen.dart` hacia `NutricionDashboardScreen(userId, empresaId)`.
- Navegacion interna del dashboard a tabs/paginas embebidas para Menus, Pacientes, Firmas y Reportes.
- Navegacion secundaria desde Menus a Ingredientes.
- No vi dependencia de named routes externas para el flujo principal.

## Incoherencias entre UI y logica

Hallazgos importantes:

- `NutricionReportesScreen` muestra exportacion funcional, pero `NutricionDashboardHelper.descargarReporte()` todavia no implementa descarga real por plataforma. Hoy el helper genera bytes y muestra exito, pero la descarga final esta marcada como `TODO`.
- En `NutricionReportesScreen`, la exportacion especifica por tipo (`menus`, `derivaciones`) sigue siendo placeholder con snackbar y `TODO`.
- El dashboard comunica un flujo muy amplio de atencion integral; para demo de manana conviene venderlo como flujo operativo base, no como modulo clinico 100 por ciento cerrado.
- `EntradaDiagnosticosScreen` existe y guarda evaluacion diagnostica, pero no es el camino principal del dashboard actual. La experiencia integrada hoy pasa por `SelectorDiagnosticosWidget`.
- Hay bastante logica de seed automatico de catalogos base. Eso ayuda para demo, pero tambien puede ocultar vacios de catalogacion real por empresa.

## Puntos de integracion

- Home / AccessGuard / empresa activa.
- Firestore para pacientes, directorio, historial, evaluaciones, citas, menus y firmas.
- Storage para firma, sello y evidencias.
- Home calendar / notificaciones via `TBL_NOTIFICACIONES` por citas de reevaluacion.
- Admin ya soporta carga de diagnosticos, lo cual impacta directamente la calidad del flujo de Nutricion.

## Gaps entre lo que existe y lo que se puede mostrar manana

Si se busca una demo defendible manana, estos son los gaps que no conviene sobredimensionar:

- Reportes Excel: hay generacion de bytes, pero no descarga final multi-plataforma cerrada en helper.
- Exportaciones parciales: no listas.
- El flujo clinico profundo existe por piezas, pero la historia integrada para demo debe enfocarse en paciente -> evaluacion -> diagnostico -> dieta -> agendamiento -> evidencia.
- No conviene prometer seguridad granular dentro del modulo mas alla del guard de acceso por modulo.
- No conviene prometer analitica o reporting avanzado; hoy lo mas defendible es reporte base y estructura de datos.

## Alcance funcional minimo entregable manana

Demo funcional minima recomendada:

1. Usuario con permiso entra a Nutricion desde Home con empresa activa correcta.
2. Ve dashboard y selecciona o registra paciente.
3. Guarda medicion antropometrica.
4. Selecciona diagnostico medico y/o nutricional.
5. Define dieta sugerida y fechas.
6. Guarda expediente del paciente y deja historial.
7. Agenda reevaluacion.
8. Sube una evidencia o muestra el bloque de evidencias funcionando.
9. Abre submodulo de Menus y muestra que existen planes/plantillas por empresa.
10. Abre Pacientes y muestra directorio filtrado por empresa.
11. Abre Firmas y muestra carga o preview de firma/sello.

Eso ya es suficiente para decir que el modulo tiene flujo operativo base entregable.

No recomiendo basar la demo de manana en:

- descarga real de Excel
- exportaciones parciales
- historias clinicas complejas como eje central
- derivaciones/carnets/alertas como historia principal

## Casos de uso minimos que se deben demostrar manana

- ingreso autorizado al modulo desde Home
- respeto de empresa activa al abrir Nutricion
- alta o actualizacion de paciente
- registro de medicion
- seleccion de diagnosticos
- guardado del expediente nutricional
- agendamiento de reevaluacion
- consulta de directorio de pacientes
- consulta y edicion basica de menus/ingredientes
- carga o visualizacion de firma profesional

## Checklist QA para manana

- Usuario con `nutriciondashboard` visible puede abrir el modulo desde Home.
- Usuario sin permiso no puede abrir Nutricion.
- Cambio de empresa activa y reapertura del modulo usa la nueva empresa.
- Directorio de pacientes muestra solo datos de la empresa activa.
- Crear o editar paciente persiste sin romper el listado.
- Guardar medicion actualiza paciente y no falla por `pacienteId`.
- Selector de diagnosticos devuelve resultados y mantiene seleccion al cambiar de paciente.
- Guardar expediente crea/actualiza directorio e historial.
- Agendar reevaluacion crea cita y notificacion asociada.
- Menus abre con establecimiento y semana, y permite ver/crear plan alimentario.
- Ingredientes abre desde Menus y queda filtrado por empresa.
- Firmas permite ver y guardar firma o sello.
- PDF no rompe el flujo cuando existen firma/sello/evidencias.
- Reportes no deben venderse como descarga final cerrada si la descarga no esta implementada por plataforma.

## Riesgos de integracion

- Riesgo de demo sobredimensionada: la UI sugiere un modulo mas completo de lo que hoy esta cerrado en exportacion y reporting.
- Riesgo de datos: si diagnosticos o catalogos no estan cargados, la parte clinica pierde fuerza.
- Riesgo de Storage: firmas y evidencias dependen de subida correcta a Storage.
- Riesgo de consistencia: el dashboard mezcla flujo integrado, directorio, menus y reportes; conviene una narrativa de demo corta y controlada.
- Riesgo de permisos: hoy el guard es de modulo, no de subfuncion.
- Riesgo de datos cross-empresa si se prueba con cuentas o datos mal sembrados, aunque el modulo ya recibe `empresaId`.

## Criterio de aceptacion para "entregado manana"

Nutricion puede declararse "entregado manana" si se cumplen todas estas condiciones:

1. El modulo abre desde Home solo para usuarios autorizados.
2. La empresa activa controla correctamente pacientes, menus y acciones.
3. Se puede ejecutar de punta a punta el flujo minimo: paciente -> medicion -> diagnostico -> dieta/fechas -> guardado -> agendamiento.
4. Al menos un submodulo auxiliar abre y funciona de forma consistente: Menus, Pacientes o Firmas.
5. No hay errores visibles bloqueantes en Web ni en movil para ese flujo minimo.
6. La demo no depende de reportes parciales ni de descarga final de Excel.

## Secuencia recomendada de ejecucion entre Claude, Gemini y Codex

Orden recomendado:

1. Claude
   - validar persistencia real del flujo minimo
   - revisar colecciones, queries, Storage y seeds
   - asegurar que empresa activa y permisos no se rompan en Nutricion
   - confirmar que citas/notificaciones y guardado de expediente queden estables

2. Gemini
   - ajustar solo presentacion y claridad visual del flujo minimo en dashboard y submodulos visibles de demo
   - mejorar legibilidad, estados vacios, jerarquia visual y coherencia Web vs movil
   - no ampliar flujo ni redisenar fuera del eje de demo

3. Codex
   - cerrar integracion funcional final
   - validar acceso desde Home
   - validar navegacion interna real
   - cortar alcance de demo a lo que ya funciona
   - preparar checklist QA y criterio final de salida

## Que NO tocar todavia

- No reabrir Fase 1 de Home, AccessGuard o shell salvo bug bloqueante directo de Nutricion.
- No retirar compatibilidades heredadas fuera del modulo.
- No meterse a redisenar reporteria completa.
- No prometer named routes nuevas o deep links de Nutricion si hoy no son parte del flujo real.
- No ampliar seguridad cliente como si reemplazara backend.
- No convertir `EntradaDiagnosticosScreen` en eje del modulo si el dashboard integrado actual usa otro camino.
- No mezclar con Fase 2, analitica avanzada o cierre de deuda tecnica global.

## Decision operativa

Nutricion tiene hoy flujo real suficiente para una demo funcional minima manana, pero la demo debe acotarse al circuito operativo base y no a reporteria/exportacion avanzada.

La historia recomendada para manana es:

- acceso correcto al modulo
- paciente
- evaluacion
- diagnostico
- dieta
- agendamiento
- evidencia
- apertura de uno o dos submodulos auxiliares

Con ese alcance, el modulo es demostrable y defendible.
