# PROMPT MAESTRO — Manual de Usuario v5 + Presentación v5 de ToDo

> **Cómo usar este archivo:** copia todo lo que está debajo de la línea
> `===== INICIO DEL PROMPT =====` y pégalo en una sesión nueva de Claude Code
> abierta en `C:\Desarrollo\capital-uspec`. El prompt está escrito para que el
> modelo verifique contra el código real y no invente funciones.
>
> Auditoría que originó este prompt: el manual v4 (27 páginas) y la
> presentación (12 diapositivas) documentan **7 módulos**; el catálogo real
> `lib/core/app_catalog.dart` tiene **13**. Falta aproximadamente el 40 % del
> producto.

---

===== INICIO DEL PROMPT =====

## 0. Rol y encargo

Eres redactor técnico y diseñador de documentación de producto. Trabajas dentro
del repositorio de **ToDo — Plataforma de Gestión Empresarial** (Flutter + Firebase,
paquete `todo`, proyecto Firebase `integra360-94704`), ubicado en
`C:\Desarrollo\capital-uspec`.

Tu encargo es producir **dos entregables nuevos y completos**:

1. **Manual de Usuario v5** — reemplaza a `Manual_de_Usuario_ToDo_4.pdf`.
2. **Presentación v5** — reemplaza a `Presentacion_ToDo.pptx`.

Ambos deben cubrir **el 100 % de los módulos y funciones que hoy existen en el
código**, no solo los que alcanzó a documentar la versión 4.

**Regla número uno: no inventes.** Cada función que describas debe existir en
el código. Si no la encuentras, no la escribas. Si la encuentras pero no
entiendes el flujo de negocio, márcala en una lista de "pendientes de
confirmar con el equipo" al final de tu entrega, en vez de rellenar con
suposiciones.

---

## 1. Datos duros del producto (verificados, úsalos tal cual)

| Dato | Valor |
|---|---|
| Nombre comercial | ToDo — Plataforma de Gestión Empresarial |
| Versión de la app | **2.4.0 (build 5)** — está en `pubspec.yaml` |
| Plataformas | Web (Flutter Web), Android, iOS |
| Bundle iOS | `com.capitaluspec.gestionapp` |
| Package Android | `com.todogestion.app` |
| Modelo | Multiempresa, multi-rol, multi-módulo |
| Módulos en el catálogo | **13** (`lib/core/app_catalog.dart`) |
| Servicios siempre activos | Notificaciones y Calendario (no son módulos, no se quitan) |
| Tamaño de página en listados | 20 registros (`kPageSize` en `lib/widgets/paged_list.dart`) |

> **Corrección obligatoria:** el manual v4 dice "Versión de la app: 1.0.0".
> Es falso. La versión real es **2.4.0+5** y el linaje en App Store ya pasó por
> 1.1 y 2.1. Corrígelo en la portada.

---

## 2. Qué documenta hoy el manual v4 (y hay que conservar, corregido)

El manual v4 tiene 14 secciones y está **bien escrito**: mantén su tono
(usted, frases cortas, tablas de "Situación → Qué hacer", cajas de advertencia,
etiquetas `TODOS` / `JEFE-LÍDER` / `MÓDULO`). Su estructura actual:

1. Introducción, conceptos clave y novedades
2. Primera vez en ToDo (activación)
3. Acceso y uso diario
4. Gestión de Tareas
5. Talento Humano · 6. Gerencia · 7. Gestión Documental · 8. Nutrición
9. Compras · 10. Interventoría · 11. Facturación
12. Roles internos por módulo
13. ¿Por qué no veo mis tareas?
14. Preguntas frecuentes y soporte

**Conserva esa columna vertebral.** Lo que hay que hacer es *ampliarla*, no
reescribirla desde cero.

---

## 3. LA BRECHA — esto es lo que falta y es el motivo de la v5

Todo lo de esta sección está verificado contra el código. Es tu lista de trabajo.

### 3.1 Módulos completos que NO aparecen en el manual ni en la presentación

#### A) **Rutas** (`rutasdashboard`, `lib/rutas/`, ~18.000 líneas)
Logística de distribución de alimentos con evidencia georreferenciada.
Es el módulo más grande que falta por completo. Contiene:

- **Consola de Administración** con 7 pestañas:
  `Establecimientos` · `Rutas` · `Asignaciones` · `Uso app` · `Centro control` ·
  `Estudio movilidad` · `Configuración inicial`.
- **App del conductor (móvil)**: "Mi ruta de hoy", selección de establecimiento,
  tiempo de comida, toma de foto con **marca de agua** (establecimiento, comida,
  número de menú, conductor, ayudantes, vehículo, coordenadas GPS), análisis
  automático de calidad de la foto, y galería "Fotos de hoy" con motivo de
  rechazo visible.
- **Consola de Calidad** con pestañas `Evidencias` y `Asignaciones`, e informes
  **diario** y **semanal**.
- **Roles internos**: `conductor`, `calidad`, `admin`, `admin_calidad`,
  `desarrollador`.
- **Reglas de negocio a documentar**: tiempos de comida
  (`Desayuno`, `Almuerzo`, `Cena + Refrigerio`), **ciclo de 21 menús** con fecha
  base, **radio de validación de ubicación de 150 m** (configurable), origen de
  distribución (centro de operaciones), flota de vehículos por placa, relevo de
  personal, combinar rutas, histórico por ruta, y estados de evidencia
  (`pendiente` / `aprobada` / `rechazada`).
- **Estudio de Movilidad** (submódulo, `lib/rutas/movilidad/`): mediciones
  automáticas de tiempo de recorrido con tráfico, pestañas `Resumen` /
  `Mediciones` / `Programación`, comparación **hora pico vs hora valle**,
  umbral de alerta en minutos, corrida manual ("Medir ahora") y corridas
  programadas. Ver también `ESTUDIO_MOVILIDAD.md` en la raíz del repo.
- **Backend**: `rutasGenerarInforme`, `rutasGenerarZip`,
  `rutasMovilidadMedirAhora`, `rutasMovilidadTick`.

#### B) **Correo y Correspondencia** (`correodashboard`, `lib/correo/`)
Buzón corporativo monitoreado que radica correspondencia automáticamente.

- Pestañas: `Resumen` · `Bandeja` · `Filtros`.
- **Conexión de buzones** Gmail y Microsoft por OAuth
  (`correoGmailAuthorize/Callback`, `correoMicrosoftAuthorize/Callback`),
  con estado `conectado` y marca de "última revisión".
- **Consolidado del día**: recibidos, clasificados, sin coincidencia, con
  novedad de envío; desgloses **por categoría** y **por remitente**.
- **Reglas de clasificación** (`CorreoRegla`) con opción de **probar la regla**
  antes de activarla.
- **Radicar un correo** como expediente de Gestión de Correspondencia, con
  responsable de la respuesta, generando radicado y tarea asociada.
- **Procesamiento programado** (`correoProcesarProgramado`) además del manual.
- Documentación de apoyo ya existente en el repo: `docs/correo.md`.

#### C) **Tokens DIAN** (`tokensdiandashboard`, `lib/tokens_dian/`)
Consulta de tokens y correos de facturación electrónica de la DIAN.
Buzón propio Yahoo/IMAP, **independiente del módulo Correo**.
Funciones: conectar/desconectar buzón, sincronizar, estado, listar tokens,
abrir token, cambiar estado, y registro de accesos (quién abrió qué token).
Backend: `dianBuzonConectar/Desconectar/Estado/Sincronizar/Programado`,
`dianToken*`.
Marcado `soloAdmin: true` en el catálogo → va en el **Manual Interno de
Administración**, pero debe al menos aparecer nombrado en la lista de módulos.

#### D) **Planillas de Pago** como módulo propio (`planillaspagodashboard`)
El manual v4 lo enterró como sección 7.4 de Gestión Documental. **Es un módulo
independiente** con su propio `appId` y su propio flujo de firmas.

- **Estados** (9): `Cargada` → `Pendiente validación` → `En revisión auditoría`
  → (`Observada` ↔ vuelve a revisión) → `Aprobada por auditoría` →
  `Pendiente firma gerencia` → `Firmada`. Ramas: `Rechazada`, `Anulada`.
  Las transiciones válidas están en `kPpTransicionesValidas`; el manual debe
  incluir el diagrama de flujo.
- **Roles y qué puede cada uno** (`PpRoles.permisosAccion`):
  `tesoreria` (confirmar carga, enviar a auditoría, reenviar, editar nombre),
  `auditoria` (observar, aprobar, rechazar, enviar a gerencia),
  `gerencia` (firmar, rechazar), `admin_doc` (todo + anular + eliminar).
- **Carga por lote** desde Excel (`pp_generar_desde_excel_screen`,
  `pp_lote_upload_screen`), subida de PDF suelto, y **estampado de PDF**
  (`ppStampDirectPdf`).
- **Notificaciones programadas** 08:00 / 12:00 / 16:00 y aviso por WhatsApp al
  cambiar de etapa de firma.

#### E) **Gestión de Correspondencia / Expedientes** (dentro de `gestiondocumentaldashboard`)
El manual v4 solo describe la **Biblioteca**. Falta todo el subsistema de
expedientes, que es lo que más se usa:

- **Expedientes** con estados `Recibido` → `Asignado` → `Terminado`, con
  contadores por pestaña.
- **Radicado + código interno del expediente**: conviven dos identificadores;
  la raíz del código sale del **maestro de tipos documentales** y **no es
  editable**. Explícalo, porque genera confusión.
- **Maestro de tipos documentales** (`gd_tipos_documentales_screen`).
- **Roles internos de Correspondencia** (`GdRolCorrespondencia`, 4 niveles
  jerárquicos):
  | Rol | Nivel | Qué puede |
  |---|---|---|
  | Visor | 1 | Solo consulta el tablero y el histórico |
  | **Operador** *(por defecto)* | 2 | Trabaja los expedientes que le asignan; no clasifica ni asigna |
  | Clasificador y asignador | 3 | Clasifica, asigna responsables y define fechas límite |
  | Administrador del módulo | 4 | Todo lo anterior + tipos documentales, filtros y cierre de cualquier expediente |
  > Dato importante para el manual: quien entra sin rol asignado entra como
  > **Operador**; un rol escrito con un texto no reconocido **no** otorga permisos.
- **Panel de colaboración** por expediente, **tablero de control**
  (`gd_control_dashboard_screen`), **métricas** y **exportación**.
- Backend: `gdAsignarExpediente`, `gdRevisarRespuesta`, `gdTerminarExpediente`.

---

### 3.2 Funciones que faltan DENTRO de módulos ya documentados

#### Talento Humano — el manual v4 solo cuenta 4 de 10 herramientas
El menú real (`talento_humano_dashboard_screen.dart`) tiene:

| Herramienta | ¿Está en el manual v4? |
|---|---|
| Hojas de Vida | Sí (5.1) |
| Gestionar Áreas | Sí (5.2) |
| Gestionar Cargos | Sí (5.2) |
| Notificaciones TH | Sí (5.4) |
| **Requerimientos de personal** (requisición + PDF) | **NO** |
| **Dashboard HV** (pestaña Sociodemográfico) | **NO** |
| **Centros de costo** | **NO** |
| **Gestión de personal** (alta e importación masiva desde Excel) | **NO** |
| **Accesos del personal** (asignar módulos desde TH, en lenguaje de negocio) | **NO** |
| **Proceso disciplinario** | **NO** |
| **Exportación Zeus** (nómina) | **NO** |
| Estructura Organizacional | Sí (5.3) |

Además faltan los **indicadores del tablero de TH**: Personal activo · Hojas de
vida pendientes · Sin centro de costo · Solicitudes de personal · Procesos
abiertos; el botón **"Excel pendientes HV"**; y el filtro Activos / Inactivos.

Regla de negocio que debe quedar explícita en el manual: **el retiro de una
persona es por empresa** (vive en `estadoLaboral` del bloque de la empresa); el
estado raíz del usuario solo controla si puede iniciar sesión.

#### Compras — falta un submódulo entero y toda la capa de vigencias
- **Abastecimiento** (`abastecimiento_screen.dart`): entregas programadas contra
  consumo, "Nueva entrega", estados `Pendientes` / `Entregados` / `Atrasadas` /
  `Cancelados`, filtros por proveedor / producto / grupo / período de consumo,
  carga y actualización desde Excel, **sincronización con Recepción** y
  **reportes de abastecimiento** (programado a las 17:00,
  `comprasReporteAbastecimiento1700`).
- **Marcas** y documentos de marca (el manual v4 ni las menciona).
- **Estados documentales reales**, que el manual reduce a "aprobar/rechazar":
  `Completo` · `Pendiente` · `Falta` · `Sin cargar` · `Rechazado` · `Vencido` ·
  `Sin vigencia` · `Aprobado con requerimientos`.
- **Vigencias documentales**: vencidos, "vencen en 30 días", sin fecha
  registrada, con notificación automática (`comprasNotificarVigenciasDocumentales`).
- **Reversión de aprobaciones dadas por error** (existe desde la sesión del
  2026-07-30 y no está documentada).
- Pestañas reales del módulo: `Resumen` · `Pendientes` · `Aprobados` ·
  `Rechazados` · `Recepción` · `Histórico`; y consultas de
  `Proveedores` · `Productos` · `Marcas` · `Recepciones` · `Fichas técnicas`.
- **Aviso por WhatsApp** al registrar un proveedor nuevo.

#### Facturación — el manual describe 3 de 5 pestañas
Pestañas reales: `Establecimientos` · `Cargar` · `Autorizaciones` · `Gestión` ·
**`Obligaciones`**.
Falta documentar el **maestro de obligaciones contractuales**: crear una
obligación (ej. "Servicio de acueducto"), activarla o inactivarla conservando su
histórico, y **reordenarla** (subir/bajar posición).
Falta también el aviso por WhatsApp cuando se **deniega** un documento.

#### Interventoría — pestañas y roles desactualizados
- Pestañas reales: `Histórico de actas` · `Por revisar` · `Subsanaciones` ·
  `Análisis`. (La pestaña `Hallazgos` está **oculta** hoy por bandera
  `kMostrarTabHallazgos = false` — no la documentes como visible.)
- **Roles internos reales** (los del manual v4 están con el nombre corto):
  `admin_interventoria`, `registrador_interventoria`, `revisor_interventoria`,
  `gerente_interventoria`, `directivo_interventoria`.
  `consulta_interventoria` **está deshabilitado** — sácalo de la tabla de roles.
- Falta: **tablero de asignación** con asignación por numeral y **fecha límite**,
  el **catálogo de numerales**, y el trabajo **por centro de costos**.
- **Aviso por WhatsApp** al crear un acta nueva.

#### Nutrición — el manual describe la mitad
Pestañas reales del módulo: `Atención` · `Menú` · `Items` · `Pacientes` ·
`Firmas` · `Reportes`.
Falta documentar: la pestaña **Menú** (armado de minutas), **Items**,
**Firmas** (firma del profesional), **Reportes**, el buscador de diagnósticos
**ICD-11** (`icd11Search`, servicio en línea), y los **recordatorios automáticos
de citas a las 08:00** (`citasNutricionRecordatorios0800`).

#### Gerencia
Tiene dos pestañas: `Dashboard` y **`Puntos`** (ranking). El manual mezcla ambas
en una sola lista de indicadores. Sepáralas. Documenta también el filtro
**"todas mis empresas"**.

---

### 3.3 Acceso y sesión — funciones nuevas que el manual no conoce

El manual v4 solo describe el login con cédula y contraseña. Faltan las
**conveniencias de inicio de sesión** (`lib/services/auth_prefs.dart`,
`lib/login/auth_gate.dart`):

- **Recordar usuario** (guarda la cédula, nunca la contraseña).
- **Mantener la sesión iniciada** (`AuthGate` reanuda al abrir la app).
- **Ingreso con huella / Face ID**, cuando el dispositivo lo soporta.
- **Advertencia de seguridad obligatoria en el manual:** la app **nunca guarda
  la contraseña**. La biometría desbloquea una sesión previamente guardada; no
  es un segundo factor.
- **Elección de empresa en el login**: si el usuario elige empresa
  explícitamente al entrar, esa elección manda sobre la última empresa guardada.
- **Clave temporal `123456`**: toda alta de personal la deja; en el primer
  ingreso el backend la borra y marca la cuenta como migrada. Debe cambiarse de
  inmediato.
- **Preguntas de seguridad** para recuperar el acceso
  (`authPrepararRecuperacion`, `authCompletarRecuperacion`).

---

### 3.4 Reglas transversales de la app que el usuario debe conocer

Están en `CLAUDE.md` y son **contratos del producto**, no detalles de diseño:

1. **Listados de 20 en 20.** Ningún listado se pinta completo; siempre hay barra
   de páginas cuando hay más de una página.
2. **Barra de scroll horizontal solo en escritorio.** En Android e iOS se
   desliza con el dedo y la barra no se pinta. El navegador de un teléfono se
   comporta como la app nativa.
3. **Áreas sin ids crudos ni repetidas.** El usuario nunca debe ver un
   identificador técnico donde debería ir el nombre de un área.
4. **Personas siempre con nombre y foto**, nunca la cédula suelta.
5. **Notificaciones y Calendario no son módulos**: los tiene todo el personal y
   nadie se los puede quitar. Tareas **sí** se puede apagar, y apagarlo vacía el
   Home, no solo el menú.

Y el **centro de notificaciones único**: todos los módulos escriben al mismo
buzón; el push llega al dispositivo y al tocarlo abre el elemento relacionado
respetando los permisos.

Añade además una explicación del **canal WhatsApp** como vía de aviso
complementaria (Compras, Facturación, Interventoría, Planillas y Correo lo usan),
aclarando que **se configura por empresa** y que su disponibilidad depende de
esa configuración.

---

### 3.5 Módulo Administración (manual aparte, pero hay que nombrarlo bien)

No lo desarrolles en el manual de usuario final, pero sí **enumera sus 15
pestañas** en una página de una sola línea cada una, para que quien pida un
permiso sepa a dónde va su solicitud:
`Usuarios` · `Apps` · `Membresía` · `Catálogos` · `Migraciones` · `Logs` ·
`Seguridad` · `Limpieza` · `Diagnósticos` · `Compras` · `Correo` ·
`Tokens DIAN` · `WhatsApp` · `Salud usuarios` · `Salud cargos`.

---

## 4. Estructura obligatoria del MANUAL v5

Objetivo de extensión: **48–60 páginas** (la v4 tiene 27).

```
Portada — versión 2.4.0 · edición del manual con mes y año
Tabla de contenido (2 niveles)

SECCIÓN 1  Introducción, conceptos clave y novedades
           1.1 Qué es ToDo · 1.2 Los tres conceptos (empresa activa, rol, módulos)
           1.3 Mapa de los 13 módulos (una rejilla, con a quién sirve cada uno)
           1.4 Reglas transversales (§3.4 de este prompt)
           1.5 Novedades de la versión 2.4

SECCIÓN 2  Primera vez en ToDo (activación)   [conservar v4 + corregir]
SECCIÓN 3  Acceso y uso diario
           3.1 Ingreso normal
           3.2 NUEVO — Recordar usuario, mantener sesión y huella/Face ID
           3.3 NUEVO — Recuperar el acceso (preguntas de seguridad)
           3.4 Pantalla de inicio (Home) y calendario
           3.5 Web vs Móvil
           3.6 Menú lateral
           3.7 Cambiar de empresa sin cerrar sesión
           3.8 Notificaciones (campana, push y WhatsApp)
           3.9 Mi hoja de vida y Mi equipo

SECCIÓN 4  Gestión de Tareas (flujo completo)   [conservar v4]

--- MÓDULOS: una sección por módulo, en este orden ---
SECCIÓN 5   Talento Humano        (ampliar de 4 a 10 herramientas)
SECCIÓN 6   Gerencia              (separar Dashboard y Puntos)
SECCIÓN 7   Gestión Documental — Biblioteca
SECCIÓN 8   NUEVA — Gestión de Correspondencia (expedientes y radicados)
SECCIÓN 9   NUEVA — Correo (buzones monitoreados y radicación automática)
SECCIÓN 10  NUEVA — Planillas de Pago (módulo propio, flujo de 9 estados)
SECCIÓN 11  Nutrición             (6 pestañas, no 5 apartados)
SECCIÓN 12  Compras               (+ Abastecimiento, marcas y vigencias)
SECCIÓN 13  NUEVA — Rutas         (admin + conductor + calidad + movilidad)
SECCIÓN 14  Interventoría         (pestañas y roles corregidos)
SECCIÓN 15  Facturación           (+ Obligaciones)
SECCIÓN 16  Administración        (solo el índice de pestañas; manual aparte)

SECCIÓN 17  Roles internos por módulo   [tabla maestra, corregida y completa]
SECCIÓN 18  ¿Por qué no veo…?           [ampliar: tareas, módulos, expedientes,
                                          evidencias, planillas, notificaciones]
SECCIÓN 19  Preguntas frecuentes y soporte
ANEXO A     Glosario (radicado, expediente, numeral, subsanación, centro de
            costo, ficha técnica, vigencia documental, menú del ciclo, evidencia
            georreferenciada, lote de planillas…)
ANEXO B     Índice alfabético de funciones → sección donde se explica
```

### Plantilla obligatoria para cada sección de módulo

Cada módulo se documenta **siempre** con esta misma estructura, para que el
manual sea predecible:

1. **Para qué sirve** — 2 o 3 frases en lenguaje de negocio.
2. **Quién lo usa** — perfiles reales, no roles técnicos.
3. **Mapa del módulo** — sus pestañas o secciones, en el orden en que aparecen
   en pantalla, con una línea cada una.
4. **Flujos de trabajo** — numerados, en pasos accionables ("Toque…",
   "Seleccione…"), uno por cada cosa que la gente hace de verdad.
5. **Estados y qué significan** — tabla, cuando el módulo tenga estados.
6. **Roles internos del módulo** — tabla de rol → qué ve y qué puede hacer.
7. **Avisos que genera** — qué notifica, a quién y por qué canal (campana, push,
   WhatsApp, correo).
8. **Archivos que produce** — PDF, Excel, ZIP, y desde dónde se descargan.
9. **Errores frecuentes** — caja de "Si pasa esto → haga esto".

---

## 5. Estructura obligatoria de la PRESENTACIÓN v5

Objetivo: **22–26 diapositivas** (la actual tiene 12). Misma identidad visual
que la presentación actual: portada oscura, tarjetas con inicial del módulo en
un cuadro de color, tipografía Arial, subtítulo explicativo bajo cada título.

```
 1  Portada — ToDo 2.4.0
 2  ¿Qué es ToDo? (cifras: 3 plataformas · 13 módulos · multiempresa)
 3  Tres conceptos clave (empresa activa · rol · módulos)
 4  Mapa completo de los 13 módulos  ← REEMPLAZA la lámina de 8 de hoy
 5  Primera vez: activación de la cuenta
 6  NUEVA — Acceso diario: recordar usuario, mantener sesión, huella/Face ID
 7  Gestión de Tareas: flujo y estados
 8  Talento Humano (10 herramientas)
 9  Gerencia
10  Gestión Documental — Biblioteca
11  NUEVA — Gestión de Correspondencia (expedientes y radicados)
12  NUEVA — Correo (buzones monitoreados → radicación automática)
13  NUEVA — Planillas de Pago (flujo de firma: tesorería → auditoría → gerencia)
14  Nutrición
15  Compras (+ Abastecimiento)
16  NUEVA — Rutas (parte 1: administración y programación)
17  NUEVA — Rutas (parte 2: conductor en terreno y evidencia georreferenciada)
18  NUEVA — Estudio de Movilidad
19  Interventoría
20  Facturación
21  Roles internos: quién puede qué (tabla resumen)
22  Notificaciones: campana, push y WhatsApp
23  Novedades de la versión 2.4
24  Web vs Móvil
25  Recomendaciones importantes (permisos, ubicación, primer ingreso en celular)
26  Cierre
```

Regla de densidad: **máximo 6 viñetas por lámina y máximo 12 palabras por
viñeta**. Lo que no quepa se va al manual, no a la diapositiva.

---

## 6. Cómo verificar cada afirmación contra el código

No documentes de memoria. Para cada módulo:

| Qué necesitas | Dónde está |
|---|---|
| Lista y descripción oficial de módulos | `lib/core/app_catalog.dart` |
| Pestañas de un módulo | busca `InternalModuleTabItem(` o `Tab(` en su `*_dashboard_screen.dart` |
| Estados y transiciones | los `enum` de `*_models.dart` (ej. `PpEstado`, `GdEstadoExpediente`) |
| Roles internos y permisos | constantes `kRol*` y mapas `permisosAccion` en `*_models.dart` / `*_permisos.dart` |
| Avisos automáticos y programados | `functions/src/*.ts` y los `export const` de `functions/src/index.ts` |
| Reglas de interfaz transversales | `CLAUDE.md` |
| Historia de cada cambio y su porqué | `MEJORAS.md` (bitácora por sesión) |
| Matriz de accesos | `docs/access-matrix.md` |
| Módulo Correo | `docs/correo.md` |
| Estudio de Movilidad | `ESTUDIO_MOVILIDAD.md` |
| Versión | `pubspec.yaml` |

Comandos útiles:

```bash
grep -rn "InternalModuleTabItem(" lib --include=*.dart
```

```bash
grep -rn "^enum \|^const String kRol" lib --include=*_models.dart
```

---

## 7. Reglas de estilo (no negociables)

- **Español de Colombia, tratamiento de "usted".** Frases cortas. Voz activa.
- **Cero jerga técnica en el manual de usuario.** Nunca escribas `empresaId`,
  `TBL_USUARIOS`, `appId`, `Firestore`, `snapshot` ni nombres de archivo. Se
  dice "empresa activa", "el listado de personal", "el módulo".
- **Nombra los botones exactamente como aparecen en pantalla**, entre comillas y
  con sus mayúsculas reales ("Crear tarea", "TOMAR FOTO", "Enviar a revisión").
- **Etiquetas de audiencia** en cada apartado, como en la v4:
  `TODOS` · `JEFE / LÍDER` · `MÓDULO` · y añade `ROL INTERNO` para lo que
  dependa del rol dentro del módulo.
- **Cajas de advertencia** para lo que rompe el flujo si se ignora (permiso de
  ubicación, primer ingreso en el celular, fecha límite, clave temporal).
- **Tablas** para estados, roles y "Situación → Qué hacer". Nunca párrafos
  largos para eso.
- Numera las figuras de forma continua (`Figura 1`, `Figura 2`…) y **referencia
  cada figura desde el texto**.
- No prometas funciones que estén detrás de una bandera apagada
  (ej. la pestaña `Hallazgos` de Interventoría).

---

## 8. Figuras y capturas

La v4 trae 13 figuras. La v5 necesita **al menos 30**. Entrega una **lista
numerada de capturas por tomar**, indicando para cada una: pantalla exacta, ruta
de navegación para llegar, plataforma (Web o Móvil) y rol con el que hay que
entrar para que se vea.

Capturas nuevas indispensables:

- Login con "Recordar usuario" y el botón de huella.
- Consola de Rutas: cada una de las 7 pestañas.
- App del conductor: "Mi ruta de hoy" y una foto con marca de agua y mapa.
- Rutas – Calidad: revisión de evidencias con un rechazo y su motivo.
- Estudio de Movilidad: Resumen con hora pico vs hora valle.
- Correo: Resumen del día y la bandeja con un correo ya radicado.
- Correspondencia: tablero `Recibidos / Asignados / Terminados` y el detalle de
  un expediente con su radicado.
- Planillas: el detalle de una planilla en cada etapa del flujo de firma.
- Talento Humano: menú completo de herramientas y el Dashboard HV.
- Compras: Abastecimiento y el panel de vigencias documentales.
- Facturación: pestaña Obligaciones.
- Interventoría: tablero de asignación por numeral.
- Nutrición: pestañas Menú, Items, Firmas y Reportes.

Si una captura no está disponible, deja un marcador
`[FIGURA PENDIENTE — descripción]` bien visible; **no** describas de memoria
una pantalla que no viste.

---

## 9. Entregables

1. `Manual_de_Usuario_ToDo_5.pdf` — el manual completo, maquetado.
2. El **fuente** del manual (HTML+CSS o Markdown, según cómo lo generes), para
   que la v6 no haya que rehacerla desde cero.
3. `Presentacion_ToDo_v5.pptx`.
4. `LISTA_DE_CAPTURAS_v5.md` — las capturas por tomar (§8).
5. `PENDIENTES_DE_CONFIRMAR.md` — todo lo que encontraste en el código pero cuyo
   flujo de negocio no pudiste deducir con certeza, con la pregunta concreta
   que hay que hacerle al equipo.

---

## 10. Criterios de aceptación — revísalos antes de entregar

- [ ] Los **13 módulos** del catálogo aparecen nombrados en el manual y en la
      presentación.
- [ ] Rutas, Correo, Correspondencia y Planillas de Pago tienen **sección propia**.
- [ ] La portada dice **2.4.0**, no 1.0.0.
- [ ] Cada sección de módulo sigue la **plantilla de 9 puntos** del §4.
- [ ] La tabla de roles internos incluye: Compras (5), Facturación (3),
      Interventoría (5 activos, sin `consulta`), Planillas (4 + desarrollador),
      Correspondencia (4), Rutas (5).
- [ ] Los estados de Planillas son **9** y su diagrama de transiciones es
      correcto.
- [ ] Están documentadas las conveniencias de inicio de sesión, **con la
      advertencia de que la contraseña nunca se guarda**.
- [ ] Están las 5 reglas transversales del §3.4.
- [ ] Está explicado el canal WhatsApp y que se configura por empresa.
- [ ] No aparece ni un solo identificador técnico en el texto del manual.
- [ ] Ninguna función descrita carece de respaldo en el código.
- [ ] La presentación tiene entre 22 y 26 láminas y ninguna pasa de 6 viñetas.

===== FIN DEL PROMPT =====

---

## Anexo del auditor — evidencia de la brecha

Recuento de lo hallado el 28 de agosto de 2026 al comparar los dos documentos
con el árbol de `lib/`:

| Módulo (`appId`) | ¿En el manual v4? | ¿En la presentación? |
|---|---|---|
| `tareasdashboard` | Sí | Sí |
| `talentohumanodashboard` | Parcial (4 de 10 herramientas) | Parcial |
| `gerenciadashboard` | Parcial (falta pestaña Puntos) | Sí |
| `gestiondocumentaldashboard` | Solo la Biblioteca | Solo la Biblioteca |
| `nutriciondashboard` | Parcial (falta Menú, Items, Firmas, Reportes) | Parcial |
| `comprasdashboard` | Parcial (falta Abastecimiento, marcas, vigencias) | Parcial |
| `interventoriadashboard` | Pestañas y roles desactualizados | Parcial |
| `facturaciondashboard` | Falta Obligaciones | Parcial |
| `planillaspagodashboard` | Enterrado como 7.4 | No |
| **`rutasdashboard`** | **No** | **No** |
| **`correodashboard`** | **No** | **No** |
| **`tokensdiandashboard`** | **No** | **No** |
| `admindashboard` | Excluido a propósito | Nombrado |

Tamaño relativo de lo no documentado: `lib/rutas/` son ~18.240 líneas y
`lib/correo/` + `lib/gestion_documental/correspondencia/` + `lib/tokens_dian/`
suman varios miles más. Es la carencia más grande del manual actual.
