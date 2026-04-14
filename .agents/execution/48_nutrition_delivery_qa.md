# 48 - Nutricion - QA final de entrega

## Estado

Vertical slice de Nutricion revisado para entrega de manana.

Decision actual: **listo con alcance controlado**.

No se detecto un bloqueo funcional nuevo que obligue a tocar codigo en esta pasada. La recomendacion es demo centrada en flujo operativo base, no en reporteria avanzada.

## Archivos revisados

- `.agents/reviews/43_claude_nutrition_scan.md`
- `.agents/reviews/44_gemini_nutrition_ui_scan.md`
- `.agents/reviews/45_codex_nutrition_flow_scan.md`
- `.agents/execution/46_claude_nutrition_execution.md`
- `.agents/execution/47_gemini_nutrition_ui_execution.md`
- `lib/nutricion/nutricion_dashboard_screen.dart`
- `lib/nutricion/widgets/nutrition_shared_widgets.dart`
- `lib/nutricion/catalogos/nutricion_catalogos_screen.dart`
- `lib/nutricion/menus/nutricion_menus_screen.dart`
- `lib/nutricion/firmas/nutricion_firmas_screen.dart`
- `lib/nutricion/reportes/nutricion_reportes_screen.dart`
- `lib/nutricion/ingredientes/nutricion_ingredientes_screen.dart`
- `lib/helpers/nutricion_dashboard_helper.dart`
- `lib/services/nutricion_service.dart`
- `lib/services/diagnosticos_service.dart`
- `lib/services/citas_nutricion_service.dart`
- `lib/services/nutricion_pdf_service.dart`
- `lib/services/nutricion_report_service.dart`
- `lib/home/home_screen.dart`
- `lib/core/guarded_module_page.dart`
- `lib/core/access_guard.dart`

## Archivos modificados

Ninguno en esta tarea.

## Flujo validado

Flujo validado como demostrable:

1. Home muestra Nutricion segun permisos del usuario.
2. Navegacion a `NutricionDashboardScreen` con `userId` y `empresaId`.
3. Guard del modulo aplicado con `appId: nutriciondashboard`.
4. Dashboard usa empresa activa para pacientes, menus, ingredientes, firmas, citas e historial.
5. Flujo de atencion operativo:
   - seleccionar o registrar paciente
   - guardar medicion
   - seleccionar diagnosticos
   - definir dieta y fechas
   - guardar expediente e historial
   - agendar reevaluacion
   - cargar evidencias
   - generar PDF
6. Submodulos accesibles desde la shell nueva:
   - Menus
   - Pacientes
   - Firmas
   - Reportes
7. Web y movil usan la misma logica y empresa activa, con navegacion visual distinta.

## Regresiones detectadas o descartadas

Descartadas:

- No se ve bypass nuevo del guard del modulo desde Home.
- No se ve perdida de `empresaId` al entrar al dashboard.
- La diferenciacion Web vs movil del dashboard existe de forma real.
- `DiagnosticosService` ya no deja `print()` sueltos y ya filtra evaluaciones por empresa en el stream.
- El helper de reportes ya no queda en exito falso total; al menos ejecuta guardado por plataforma.

Detectadas como riesgo, no como bloqueo de manana:

- `NutricionReportesScreen` sigue mostrando botones de exportacion parcial con placeholder.
- La narrativa visual del modulo sugiere mas cobertura de la que conviene prometer en demo.
- El analisis automatico no se pudo cerrar en este entorno por timeout, asi que la validacion final de compilacion te queda local.

## Checklist de demo de manana

- Login con usuario que tenga `nutriciondashboard`.
- Confirmar que Home muestre Nutricion solo cuando corresponde.
- Entrar a Nutricion con empresa activa correcta.
- Mostrar shell Web con `NavigationRail`.
- Mostrar shell movil con `BottomNavigationBar`.
- Seleccionar o crear paciente.
- Guardar una medicion antropometrica.
- Seleccionar diagnostico medico y/o nutricional.
- Confirmar que aparecen dietas sugeridas o seleccionables.
- Guardar expediente del paciente.
- Agendar reevaluacion.
- Mostrar que Menus abre con establecimiento y semana.
- Mostrar directorio de pacientes.
- Mostrar carga o preview de firma/sello.
- Mostrar PDF o al menos que su generacion no rompa el flujo.

## Riesgos

- No conviene basar la demo en exportacion parcial de reportes.
- Si faltan catalogos/diagnosticos sembrados en datos reales, la parte clinica pierde fuerza.
- Firmas, evidencias y PDF dependen de Storage operativo.
- `flutter analyze` y prueba local real siguen pendientes por timeout en este entorno.
- Si el dataset de demo esta sucio entre empresas, puede contaminar la percepcion aunque el modulo ya reciba `empresaId`.

## QA funcional recomendado

- Usuario sin permiso: Nutricion no debe abrir.
- Usuario con permiso: Nutricion abre desde Home.
- Cambio de empresa activa y reapertura del modulo: debe reflejar nueva empresa.
- Crear o editar paciente: listado actualizado sin mezclar empresas.
- Guardar medicion: persiste sobre el paciente seleccionado.
- Diagnosticos: busqueda y seleccion funcionan sin perder estado.
- Guardar expediente: crea o actualiza directorio e historial.
- Agendar reevaluacion: persiste cita y notificacion.
- Menus: abre, lista y permite crear/editar un plan.
- Ingredientes: abre desde Menus y mantiene filtro por empresa.
- Firmas: permite guardar y mostrar firma o sello.
- Reporte completo: probar solo como extra, no como eje de demo.

## Ejecucion automatica intentada

Intentado:

- `flutter analyze` sobre archivos de Nutricion y servicios relacionados

Resultado:

- timeout en este entorno, sin salida confiable para declarar analyze completo aqui

## Decision final

**Listo** para entrega de manana, con estas condiciones:

- la demo debe centrarse en el flujo operativo base
- no vender exportaciones parciales como cerradas
- ejecutar validacion manual local antes de presentar

No lo marcaria como "no listo". Lo marcaria como **listo con demo controlada y QA manual obligatoria**.
