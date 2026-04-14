# 18 — Revisión de arquitectura multiplatforma (Claude)
**Fecha:** 2026-03-17
**Referencias:** `10_master_implementation_plan.md`, `16_multiplatform_strategy.md`, `CLAUDE.md`, análisis de codebase
**Nota:** `13_phase0_decisions.md` no existe aún. Este documento asume las decisiones de Fase 0 pendientes detalladas en `07_claude_review_of_codex_plan.md`.
**Rol:** Backend / Firestore / arquitectura / validaciones

---

## Premisa de backend

La estrategia de `16_multiplatform_strategy.md` es correcta en su principio rector: una sola lógica de negocio, una sola política de acceso, dos experiencias de uso. Desde backend, eso se traduce en una regla más precisa:

> **Firestore, las reglas de seguridad, los modelos de datos y los servicios no saben ni deben saber en qué plataforma está corriendo el cliente. La plataforma es irrelevante para el backend.**

Todo lo que sigue deriva de esa premisa.

---

## 1. Qué lógica puede compartirse entre Web y Móvil

### Comparte sin ninguna modificación

**Capa de datos (Firestore)**
- Todos los documentos y colecciones son los mismos en ambas plataformas.
- Las queries son idénticas: mismo `empresaId`, mismo filtro de rol, mismas condiciones.
- Las Firestore Security Rules aplican igual independientemente del cliente.
- Los índices compuestos son globales; no hay índice "para web" ni "para móvil".

**Modelos de datos (`*_models.dart`)**
- `ProductoDoc`, `ProveedorDoc`, `RecepcionDoc`, `DocAdjunto`, etc.
- `fromMap()` / `toMap()` son agnósticos a plataforma.
- Los enums de estado (`estadoCalidad`, roles de módulo) son los mismos.

**Servicios (`*_service.dart`)**
- Todas las operaciones CRUD: `streamProductos()`, `guardarRecepcion()`, `aprobarDocRecepcion()`, etc.
- La lógica de generación de códigos secuenciales (transacciones Firestore).
- El motor de requisitos documentales (`cargarReqEngine()`).
- La lógica de batch import (`importarProductos()`, `importarProveedores()`).

**Estado de sesión y empresa activa**
- `EmpresaScope` — el concepto y su lógica de validación son los mismos.
- La revalidación de `selectedEmpresaId` contra `TBL_USUARIOS.empresas[]`.
- El helper de resolución de cargo/área por empresa activa (cuando se implemente).

**Lógica de autorización**
- El `AccessGuard` (a implementar): la decisión de si un usuario puede entrar a un módulo es la misma en Web y Móvil. Solo cambia cómo se manifiesta el rechazo (redirigir a home móvil vs. mostrar panel vacío en web).
- La lectura de `TBL_COMPRAS_ROLES` para determinar `rolCompras` activo.
- La verificación de `TBL_APPS` para modulos habilitados por empresa.

**Notificaciones funcionales**
- La lógica de qué notificación corresponde a qué usuario/empresa es común.
- Lo que difiere es el canal de entrega (FCM en móvil, in-app en web — ver sección 7).

---

## 2. Qué conviene separar

### Separar estrictamente

**Persistencia de estado de sesión**
- En móvil: `SharedPreferences` funciona bien para `selectedEmpresaId`.
- En web: `SharedPreferences` persiste en `localStorage`. Es funcional pero tiene implicaciones distintas de seguridad (accesible desde JavaScript en la misma página, puede ser leído por extensiones del navegador).
- La separación no es en la lógica de validación sino en el mecanismo de escritura/lectura. El valor lógico (`selectedEmpresaId`) es el mismo; la librería de persistencia puede divergir.

**Manejo de archivos y uploads**
- En móvil: `image_picker`, `file_picker`, `File(path).readAsBytes()`.
- En web: `XFile.readAsBytes()` directamente, sin acceso a filesystem nativo. Los temp files no existen.
- Ya hay fixes aplicados (`kIsWeb` guards en `complete_task_screen.dart`, etc.), pero hay que mantener esta separación consistente en cualquier nuevo flujo que involucre archivos.

**Descarga de documentos (PDFs)**
- En móvil: `OpenFilex` abre el archivo en el visor del SO.
- En web: `FileSaver` o url_launcher con data URI.
- Ya implementado en `nutricion_dashboard_screen.dart`. El patrón debe replicarse en Compras cuando se implemente descarga de fichas técnicas o informes.

**Notificaciones push**
- En móvil: FCM (Firebase Cloud Messaging) vía `NotificationsService`.
- En web: FCM web funciona pero requiere Service Worker, VAPID key y configuración adicional. En la práctica, muchas apps web corporativas reemplazan esto con notificaciones in-app (badges, banners dentro de la UI).
- El `main.dart` ya tiene `if (!kIsWeb)` para `NotificationsService.init()`. Esta separación debe mantenerse y formalizarse.

**App Check**
- En móvil: `DeviceCheckProvider` (iOS) / `PlayIntegrityProvider` (Android).
- En web: `ReCaptchaV3Provider(siteKey)` — aún en placeholder según el análisis del codebase.
- Esta separación es obligatoria por la API de Firebase; no hay forma de unificarla.

**Platform checks (`Platform.isAndroid`, `Platform.isIOS`)**
- Toda lógica que use `dart:io Platform` debe estar protegida con `if (!kIsWeb)` o reemplazada por `defaultTargetPlatform`.
- Ya hay fixes aplicados pero deben auditarse en cualquier código nuevo.

---

## 3. Impacto técnico de esa separación

### Impacto en la capa de servicios

Los servicios (`*_service.dart`) deben mantenerse 100% agnósticos a plataforma. Esto implica una regla concreta:

**Ningún `_service.dart` puede importar `dart:io`, `image_picker`, `file_picker`, ni `platform_file_saver`.**

Los servicios reciben bytes (`Uint8List`) o rutas de Storage, nunca objetos `File` de dart:io. La transformación de `XFile` / `File` a `Uint8List` ocurre en la capa de pantalla, antes de llamar al servicio. Hoy `compras_service.dart` recibe `Uint8List` en `subirBytes()` — ese patrón es correcto y debe mantenerse.

**Impacto concreto si se rompe esta regla:**
- Un servicio que importe `dart:io` compilará en móvil pero fallará en web con error de compilación.
- Detección tardía porque el error solo aparece al hacer `flutter build web`.

### Impacto en la capa de estado (`EmpresaScope`, `AccessGuard`)

El estado de sesión necesita una abstracción de persistencia:

```
abstract class SessionStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

// Implementación móvil: SharedPreferences
// Implementación web: SharedPreferences (mismo paquete, diferente storage subyacente)
// Implementación futura segura: flutter_secure_storage donde aplique
```

Hoy `EmpresaScope` llama directamente a `SharedPreferences`. Mientras el paquete funcione igual en web, no hay impacto técnico inmediato. Pero si en algún momento se quiere usar `flutter_secure_storage` en móvil (que no funciona en web), se necesita esa abstracción.

### Impacto en la capa de UI / navegación

**Este es el punto de mayor divergencia técnica.** El plan `16_multiplatform_strategy.md` propone:
- Web: `NavigationRail` o sidebar permanente.
- Móvil: `Navigator.push` imperativo con `AppDrawer`.

El problema concreto con el código actual:

La navegación hoy es 100% imperativa (`Navigator.push`). Cambiar a `NavigationRail` en web implica un estado de "ruta activa" persistente que el modelo `push` no provee. Para web, el índice del `NavigationRail` debe vivir en el estado del widget padre (el shell del layout web), y los módulos se cargan como hijos en el panel derecho sin apilarse en el stack de navegación.

Esto no rompe ningún servicio ni modelo de datos, pero sí cambia la estructura de `HomeScreen`: en web, ya no es una pantalla que navega a otras pantallas — es un shell que contiene sub-vistas. Son dos arquitecturas de shell distintas para la misma lógica de negocio.

**Impacto en `EmpresaScope` por este cambio:**
Si en web el módulo vive como hijo del shell y no como pantalla independiente en el stack, el `EmpresaScope` debe estar por encima del shell (no del módulo). Hoy `EmpresaScope` ya vive arriba del árbol de widgets, por lo que este cambio no rompe el acceso al contexto de empresa. Pero los guards de `initState()` de cada dashboard deben revisarse: en web, si el usuario no navega sino que cambia el índice del rail, el `initState()` puede no re-ejecutarse si el widget no se destruye. El guard debería estar en `didChangeDependencies()` o escuchar cambios de `EmpresaScope` directamente.

---

## 4. Riesgos de arquitectura

### Riesgo A — Guards de `initState()` no disparan en navegación web con shell persistente
**Probabilidad:** Alta si se implementa `NavigationRail`.
**Impacto:** El guard de acceso al módulo no se re-evalúa al cambiar de módulo en web, solo al primer montaje del widget.
**Mitigación:** Los guards deben escuchar `EmpresaScope` vía `didChangeDependencies()` o reactivamente. No depender solo de `initState()`.

### Riesgo B — `dart:io` infiltrado en servicios al agregar nuevas features
**Probabilidad:** Media. Es fácil cometer este error al agregar una feature nueva sin probar en web.
**Impacto:** Compilación rota en web sin error obvio en móvil.
**Mitigación:** Regla de arquitectura explícita: los servicios no importan `dart:io`. Validable con un análisis estático o un grep en CI: `grep -r "dart:io" lib/*/`*`_service.dart` debe retornar vacío.

### Riesgo C — `SharedPreferences` en web expuesto a XSS
**Probabilidad:** Baja en una app corporativa de uso interno, pero existe.
**Impacto:** Un script inyectado en la página podría leer `selectedEmpresaId` de `localStorage`. No es crítico porque el dato no es un secreto (el serverside no confía en él), pero podría usarse para manipular la sesión percibida.
**Mitigación:** No almacenar tokens de autenticación ni datos sensibles en `SharedPreferences` en web. `selectedEmpresaId` es aceptable. Las credenciales de Firebase Auth usan su propio mecanismo seguro (IndexedDB con Firebase SDK).

### Riesgo D — App Check no está configurado en web — la producción web queda sin protección
**Probabilidad:** Certeza — el placeholder está en el código.
**Impacto:** En web, cualquier script puede hacer requests a Firestore impersonando la app si obtiene las credenciales de Firebase (que están en el código fuente del bundle web).
**Mitigación:** Completar la configuración de `ReCaptchaV3Provider` antes de abrir la versión web a usuarios reales. Es una tarea concreta y acotada.

### Riesgo E — Maestro-detalle en web comparte estado de selección con lógica que no lo prevé
**Probabilidad:** Media.
**Ejemplo concreto:** En Compras web, el panel izquierdo muestra la lista de recepciones y el derecho muestra el detalle de la recepción seleccionada. La lógica de `aprobarDocRecepcion()` en el servicio está diseñada para ser llamada desde una pantalla que tiene el contexto completo de la recepción. Si el panel derecho es un widget hijo con acceso parcial al estado, puede terminar llamando al servicio con un objeto `RecepcionDoc` stale (el seleccionado antes de que otra sesión lo modificara).
**Mitigación:** El panel de detalle en web debe suscribirse al stream de la recepción específica (`streamRecepcion(id)`), no trabajar sobre una copia del objeto pasado desde el panel izquierdo.

### Riesgo F — Notificaciones en web sin Service Worker configurado
**Probabilidad:** Certeza — aún no está implementado.
**Impacto:** Las notificaciones push no llegan en web. Los usuarios web nunca saben que tienen tareas nuevas o aprobaciones pendientes.
**Mitigación corto plazo:** In-app notifications como primera capa (badge en el módulo, banner en el home). FCM web como segunda capa en una fase posterior.

### Riesgo G — Divergencia de comportamiento de `LayoutBuilder` según breakpoint inconsistente
**Probabilidad:** Media.
**Impacto:** Si cada pantalla define su propio breakpoint para "comportamiento web" (ej. uno usa `> 600px`, otro `> 900px`), el cambio de modo entre pantallas se siente inconsistente para el usuario.
**Mitigación:** Definir un único conjunto de breakpoints en el design system. Ejemplo: `AppBreakpoints.tablet = 600`, `AppBreakpoints.desktop = 900`. Todos los `LayoutBuilder` usan esas constantes.

---

## 5. Cómo soportar Web y Móvil sin duplicar el backend

### Regla de oro: el backend no tiene plataforma

Firestore, sus reglas, sus índices, sus colecciones y sus documentos son los mismos. No existe un "Firestore para web" y un "Firestore para móvil". La separación ocurre únicamente en el cliente Flutter.

### Estructura de capas recomendada

```
┌─────────────────────────────────────────────────┐
│  CAPA DE PRESENTACIÓN                           │
│  (diverge por plataforma)                       │
│  - layouts web vs. móvil                        │
│  - navegación web vs. móvil                     │
│  - densidad y composición                       │
├─────────────────────────────────────────────────┤
│  CAPA DE COORDINACIÓN                           │
│  (compartida, con pequeñas adaptaciones)        │
│  - AccessGuard (lógica compartida,              │
│    manifestación adaptada)                      │
│  - EmpresaScope (lógica compartida,             │
│    persistencia puede abstraerse)               │
│  - helpers de resolución empresa/rol            │
├─────────────────────────────────────────────────┤
│  CAPA DE SERVICIOS                              │
│  (100% compartida, 0% plataforma)               │
│  - *_service.dart                               │
│  - solo recibe/devuelve tipos agnósticos        │
│  - Uint8List para archivos, nunca File          │
├─────────────────────────────────────────────────┤
│  CAPA DE MODELOS                                │
│  (100% compartida, sin excepción)               │
│  - *_models.dart                                │
│  - fromMap / toMap                              │
├─────────────────────────────────────────────────┤
│  FIRESTORE / FIREBASE                           │
│  (completamente agnóstico a plataforma)         │
│  - colecciones, documentos, rules, indexes      │
└─────────────────────────────────────────────────┘
```

### Lo que evita la duplicación de backend

1. **Los servicios reciben tipos primitivos o modelos propios** — nunca `File`, `PlatformFile`, ni `XFile`. La transformación ocurre en la UI antes de llamar al servicio.

2. **`EmpresaScope` es un `InheritedWidget` / `ChangeNotifier`** que vive por encima de la decisión de layout web o móvil. El shell de web y la pantalla de móvil son distintos, pero ambos acceden al mismo `EmpresaScope.of(context)`.

3. **`AccessGuard` es una función pura de lógica** (`Future<bool>`). No sabe si está en web o móvil. Lo que sí es distinto es la *respuesta al rechazo*: en móvil, `Navigator.pushReplacement(HomeScreen)`; en web, cambiar el índice del rail o mostrar un panel de acceso denegado. Esa lógica de respuesta vive en la capa de presentación, no en el guard.

4. **Las Firestore Rules no cambian** por plataforma. El mismo documento, la misma regla, el mismo resultado.

---

## 6. Qué capas deben mantenerse comunes (sin excepción)

| Capa | Por qué no puede divergir |
|------|--------------------------|
| Firestore collections, documents, fields | Son la fuente de verdad única. Divergirlos implica dos fuentes de verdad. |
| Firestore Security Rules | Una regla que aplica solo en web o solo en móvil es insegura por definición. |
| Firestore indexes (`firestore.indexes.json`) | Los índices son del proyecto, no del cliente. |
| `*_models.dart` — fromMap/toMap | Si divergen, las queries retornan tipos distintos. Bug garantizado. |
| `*_service.dart` — toda la lógica CRUD | Un servicio distinto por plataforma duplica la superficie de bugs y las migraciones. |
| `EmpresaScope` — semántica y lógica de validación | La empresa activa debe significar exactamente lo mismo en ambas plataformas. |
| `AccessGuard` — la decisión booleana de acceso | Los permisos no pueden depender de la plataforma (regla explícita en `16_multiplatform_strategy.md`). |
| Lógica de roles de módulo (`TBL_COMPRAS_ROLES`, etc.) | El rol de un usuario en Compras es el mismo en web y móvil. |
| Modelos de estado crítico (`estadoCalidad`, estados de tarea) | Estados distintos por plataforma = inconsistencia de datos. |

---

## 7. Qué capas pueden tener comportamiento distinto por plataforma

| Capa | Comportamiento web | Comportamiento móvil | Riesgo si divergen |
|------|-------------------|---------------------|-------------------|
| Persistencia de sesión | `SharedPreferences` (localStorage) | `SharedPreferences` (NSUserDefaults / SharedPrefs Android) | Bajo — mismo paquete, distinto storage subyacente |
| Shell de navegación | `NavigationRail` / sidebar permanente | `Navigator.push` + `AppDrawer` | Medio — los guards deben adaptarse (ver Riesgo A) |
| Presentación de empresa activa | Indicador persistente en sidebar/topbar | Indicador compacto en AppBar o Drawer | Bajo — cosmético |
| Respuesta al rechazo de `AccessGuard` | Panel de acceso denegado o cambio de índice del rail | `Navigator.pushReplacement` al Home | Bajo — lógica de UI, no de negocio |
| Manejo de archivos (entrada) | `XFile.readAsBytes()` sin File nativo | `XFile.readAsBytes()` o `File(path).readAsBytes()` según widget | Medio — los `kIsWeb` guards deben estar en pantallas, nunca en servicios |
| Descarga de archivos (salida) | `FileSaver` / data URI | `OpenFilex` / temp file | Bajo — patrón ya establecido en Nutrición |
| Notificaciones push | In-app en primera fase; FCM web después | FCM via `NotificationsService` | Alto si web queda sin notificaciones — el usuario pierde alertas críticas |
| App Check | `ReCaptchaV3Provider` | `DeviceCheckProvider` / `PlayIntegrityProvider` | Alto si se omite en web — producción sin protección |
| Layout y densidad de información | Tablas, maestro-detalle, filtros persistentes | Listas, bottom sheets, foco por tarea | Bajo — cosmético y de UX |
| Breakpoints de `LayoutBuilder` | `> kDesktopBreakpoint` | `<= kDesktopBreakpoint` | Medio si no hay constantes compartidas (ver Riesgo G) |
| Comportamiento de `initState()` en guards | Debe moverse a `didChangeDependencies()` o listener reactivo | `initState()` funciona correctamente con push navigation | Medio — ver Riesgo A |

---

## Síntesis de decisiones técnicas requeridas antes de implementar

Estas decisiones deben tomarse antes de escribir código de separación plataforma/móvil. Algunas dependen aún de Fase 0 (`13_phase0_decisions.md` pendiente):

| # | Decisión | Quién decide | Impacto si se pospone |
|---|----------|-------------|----------------------|
| 1 | ¿Shell web con `NavigationRail` o `NavigationDrawer` permanente? | Gemini + Codex | Define si los guards necesitan adaptarse para no depender de `initState()` |
| 2 | ¿Breakpoints compartidos como constantes en design system? | Gemini | Riesgo G: inconsistencia visual entre pantallas |
| 3 | ¿Notificaciones web en fase 1 (in-app) o se espera FCM web? | Codex + producto | Riesgo F: usuarios web sin alertas |
| 4 | ¿App Check en web activado antes del primer usuario real? | Claude + DevOps | Riesgo D: producción web sin protección |
| 5 | ¿`flutter_secure_storage` en móvil o `SharedPreferences` es suficiente? | Claude | Define si se necesita abstracción de persistencia |
| 6 | ¿Los paneles de detalle en web consumen stream propio o reciben objeto del padre? | Codex | Riesgo E: datos stale en maestro-detalle |
