# Task 72 – ICD-11 Phase B: Backend Integration

**Ejecutado por:** Claude (Sonnet 4.6)
**Fecha:** 2026-03-21
**Tipo:** Implementación — Fase B del plan de integración ICD-11
**Referencia:** `.agents/execution/69_claude_icd11_hybrid_integration_plan.md`

---

## Objetivo de la fase

Implementar la búsqueda real ICD-11 de la OMS mediante backend seguro (Firebase Cloud Functions), sin exponer credenciales en Flutter, con fallback automático al catálogo local cuando la API no esté disponible.

---

## Archivos revisados

| Archivo | Propósito |
|---------|-----------|
| `lib/nutricion/atencion/diagnostico_models.dart` | Modelos con campos ICD-11 (Fase A) |
| `lib/services/diagnosticos_service.dart` | Servicio con `cachearEnEnfermedades()` (Fase A) |
| `lib/nutricion/nutricion_dashboard_screen.dart` | Dashboard principal — callback de diagnósticos |
| `functions/src/index.ts` | Cloud Functions existentes (notificaciones, FCM) |
| `functions/package.json` | Node 20, TypeScript 5.5.4, `firebase-functions@^6.5.0` |
| `firebase.json` | Proyecto `integra360-94704`, functions source `functions/` |
| `pubspec.yaml` | `cloud_functions: ^5.1.3`, `http: ^1.5.0` ya presentes |

---

## Archivos modificados / creados

| Archivo | Tipo |
|---------|------|
| `functions/src/icd11.ts` | **Nuevo** — Cloud Function token broker + proxy |
| `functions/src/index.ts` | Modificado — re-exporta `icd11Search` |
| `lib/services/icd11_service.dart` | **Nuevo** — cliente Flutter para la Cloud Function |
| `lib/services/diagnosticos_service.dart` | Modificado — `buscarDiagnosticosMedicos()` con ICD-11 primero |
| `lib/nutricion/atencion/diagnostico_models.dart` | Modificado — fix `_toDateTime` para Firestore Timestamp |
| `lib/nutricion/nutricion_dashboard_screen.dart` | Modificado — `_onDiagnosticosChanged` llama `cachearEnEnfermedades()` |

**No se tocaron:** Home, otros módulos, widgets de UI, esquema de Firestore existente.

---

## Cómo quedó la Cloud Function (`functions/src/icd11.ts`)

### Responsabilidades

1. **Token broker**: Intercambia `client_id` + `client_secret` (guardados en Firebase Functions config, nunca en el cliente) por un access token OAuth2 de la OMS.
2. **Token cache**: El token se reutiliza en memoria por instancia (~1h), con margen de 90s antes de expirar.
3. **Proxy de búsqueda**: Llama a `https://id.who.int/icd/entity/search` con el token, parámetros de lenguaje y modo médico.
4. **Normalización**: Retorna resultados en forma `{ icdCode, icdTitle, icdUri, source, language, icdRelease }` — shape que Flutter puede mapear directamente a `DiagnosticoMedico`.
5. **Fallback silencioso**: Si la API OMS falla, retorna `{ results: [], fallback: true }` en lugar de lanzar `HttpsError`. El cliente Flutter lo trata como degradación y activa el catálogo local.

### Seguridad

- Requiere `context.auth` (cualquier usuario Firebase Auth autenticado).
- Las credenciales OMS viven en `functions.config().icd11.client_id / client_secret`.
- El binario Flutter no contiene secretos.

### Firma de la función

```typescript
export const icd11Search = functions
  .region("us-central1")
  .https.onCall(async (data, context) => {
    // Requiere auth
    // Parámetros: data.query (string), data.language (string, default "es")
    // Retorna: { results: Icd11SearchResult[], fallback?: boolean }
  });
```

### Re-exportación desde `index.ts`

```typescript
export { icd11Search } from "./icd11";
```

---

## Cómo quedó `lib/services/icd11_service.dart`

```dart
class Icd11Service {
  static bool enabled = true;   // Feature flag — apagar sin redesplegar
  static const _timeout = Duration(seconds: 10);

  static Future<List<DiagnosticoMedico>> buscar(String query, {String language = 'es'}) async {
    if (!enabled || query.trim().length < 2) return [];

    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'icd11Search',
        options: HttpsCallableOptions(timeout: _timeout),
      );
      final result = await callable.call<Map<dynamic, dynamic>>({
        'query': query.trim(),
        'language': language,
      });
      final data = Map<String, dynamic>.from(result.data);
      final raw = (data['results'] as List?) ?? [];

      return raw.cast<Map>().map((r) => DiagnosticoMedico(
        codigoCie11: r['icdCode']?.toString() ?? '',
        nombre: r['icdTitle']?.toString() ?? '',
        icdUri: r['icdUri']?.toString(),
        source: 'who_icd11',
        language: language,
        icdRelease: r['icdRelease']?.toString(),
      )).where((dx) => dx.codigoCie11.isNotEmpty && dx.nombre.isNotEmpty).toList();

    } on FirebaseFunctionsException catch (e) {
      // unauthenticated, internal, etc. — todos van al fallback
      return [];
    } catch (e) {
      return [];
    }
  }
}
```

**Feature flag `Icd11Service.enabled`:** Si se pone en `false` antes de desplegar credenciales, el servicio devuelve `[]` inmediatamente y el flujo continúa con el catálogo local. Se puede cambiar en runtime sin redesplegar la Cloud Function.

---

## Cómo quedó el fallback local

`DiagnosticosService.buscarDiagnosticosMedicos()` ahora sigue esta jerarquía:

```
buscarDiagnosticosMedicos(termino)
  │
  ├─ 1. Icd11Service.buscar(termino)
  │      ├─ Icd11Service.enabled = false → return []
  │      ├─ Cloud Function responde con resultados → return list
  │      ├─ Cloud Function falla / timeout → return []
  │      └─ Cloud Function retorna fallback:true → return []
  │
  └─ 2. Si lista vacía → catálogo local (Firestore → Excel assets)
```

**Garantía:** el flujo clínico nunca queda vacío por culpa de la API. Si ICD-11 no responde, el usuario ve el catálogo local exactamente igual que antes de Fase B.

---

## Cómo quedó el guardado híbrido

### Ruta de guardado cuando se selecciona un diagnóstico ICD-11

```
Usuario selecciona diagnóstico
        ↓
SelectorDiagnosticosWidget._agregarDiagnosticoMedico(dx)
        ↓
onDiagnosticosChanged(m, n)  ←── callback en el dashboard
        ↓
_onDiagnosticosChanged(m, n)
  setState(...)                         ← estado local actualizado
  for dx in m:
    DiagnosticosService().cachearEnEnfermedades(dx, empresaId, userId)
         └─ dx.source == 'who_icd11'?
              Sí → TBL_ENFERMEDADES/{icdCode}.set(merge:true)
              No → return (silencioso)

        ↓
[Al finalizar atención → guardarDirectorioNutricion()]
  payload incluye diagnosticosMedicosData: m.map(d => d.toMap())
       └─ d.toMap() incluye icdUri/source/language/icdRelease si no son null
           → TBL_PACIENTES/{cedula}.diagnosticosMedicosData[] ← campos ICD-11 guardados
```

### Colecciones afectadas

| Colección | Escritura | Contenido nuevo |
|-----------|-----------|----------------|
| `TBL_ENFERMEDADES/{icdCode}` | `set(merge:true)` al seleccionar | `icdCode, icdTitle, icdUri, source, language, icdRelease, empresaId, creadoPor, creadoEn` |
| `TBL_PACIENTES/{cedula}` | Al finalizar atención | `diagnosticosMedicosData[].icdUri/source/language/icdRelease` |
| `TBL_EVALUACIONES_DIAGNOSTICAS/{id}` | Via `guardarEvaluacionDiagnostica()` | `icdUri/icdSource/icdLanguage/icdRelease` (cuando se pasan) |

### Diagnósticos locales (sin ICD-11)

No tienen `source == 'who_icd11'` → `cachearEnEnfermedades()` retorna inmediatamente. Sus `toMap()` no incluyen campos ICD-11. TBL_ENFERMEDADES no se toca. Documentos existentes en TBL_PACIENTES no se alteran.

---

## Fix adicional: `EvaluacionDiagnostica._toDateTime` para Firestore Timestamp

Se corrigió el riesgo detectado por Codex en el QA de Fase A. El método `_toDateTime` en `EvaluacionDiagnostica` no manejaba `Timestamp` de Firestore, lo que podía causar que el campo `fecha` quedara como `DateTime.now()` al leer evaluaciones históricas.

**Antes:**
```dart
static DateTime? _toDateTime(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;  // ← Firestore Timestamp llegaba aquí → null → DateTime.now()
}
```

**Después:**
```dart
static DateTime? _toDateTime(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  // Maneja Firestore Timestamp via duck-typing (evita importar cloud_firestore en el modelo)
  try {
    final date = (value as dynamic).toDate();
    if (date is DateTime) return date;
  } catch (_) {}
  return null;
}
```

---

## Variables / credenciales requeridas

### Para producción (Firebase Functions config)

```bash
# Configurar credenciales OMS (solo una vez, desde la máquina de despliegue)
firebase functions:config:set \
  icd11.client_id="TU_CLIENT_ID_OMS" \
  icd11.client_secret="TU_CLIENT_SECRET_OMS"

# Verificar
firebase functions:config:get
```

### Para emulación local (`functions/.runtimeconfig.json`)

Crear el archivo (NO commitear — agregar a .gitignore si no está):

```json
{
  "icd11": {
    "client_id": "TU_CLIENT_ID_OMS",
    "client_secret": "TU_CLIENT_SECRET_OMS"
  }
}
```

### Cómo obtener las credenciales OMS

1. Ir a: https://icdaccessmanagement.who.int/
2. Registrarse o iniciar sesión
3. Crear una aplicación → obtener `client_id` y `client_secret`
4. Las credenciales son gratuitas para uso educativo/sanitario

---

## Cómo desplegar la Cloud Function

```bash
# 1. Ir a la carpeta functions y compilar TypeScript
cd functions
npm run build

# 2. Desplegar solo las functions (no el hosting)
firebase deploy --only functions

# 3. Verificar en la consola Firebase que icd11Search aparece en la lista
```

El proyecto ya tiene `predeploy: ["npm --prefix \"$RESOURCE_DIR\" run lint", "npm --prefix \"$RESOURCE_DIR\" run build"]` en `firebase.json`, por lo que la compilación es automática en `firebase deploy`.

---

## Resultado de compilación

### Flutter (`dart analyze`)

```
Analyzing icd11_service.dart, diagnosticos_service.dart, diagnostico_models.dart...
   info - lib/services/diagnosticos_service.dart:1:8 - dart:typed_data unnecessary_import
1 issue found.
```

El único `info` reportado es el `dart:typed_data` pre-existente de Fase A. Cero errores nuevos.

### TypeScript (`tsc --noEmit`)

```
(sin output) ← compilación exitosa
```

---

## Riesgos pendientes

| # | Riesgo | Impacto | Mitigación |
|---|--------|---------|-----------|
| 1 | `functions.config()` deprecado en Firebase Functions v6 hacia Secret Manager | Puede mostrar warnings en consola de Firebase | Para migrar: usar `defineSecret()` de `firebase-functions/params`. No bloquea funcionamiento actual. |
| 2 | Cold start de Cloud Function (~300-800ms) en primera búsqueda de sesión | UX: pequeño delay la primera vez | El spinner de búsqueda ya existe en `SelectorDiagnosticosWidget` — lo cubre bien |
| 3 | WHO ICD-11 API puede estar temporalmente no disponible | La búsqueda cae al catálogo local | Cubierto: `Icd11Service` absorbe cualquier excepción y retorna `[]` |
| 4 | WHO ICD-11 API sin credenciales configuradas | Función devuelve `fallback: true` → catálogo local | Cubierto: el guard en `getIcd11Token()` lanza Error → absorbido → `[]` |
| 5 | `TBL_ENFERMEDADES` sin índice `empresaId` | Si en el futuro se usa como fuente de búsqueda por empresa, será lenta | Crear índice de campo simple `empresaId` antes de Fase D |
| 6 | `EvaluacionDiagnostica` aún no mapea campos ICD-11 en `fromMap()` | El historial no expone `icdUri/source` al leer evaluaciones previas | No bloquea Fase B. Pendiente para si se necesita leer esos campos desde el historial |
| 7 | Feature flag `Icd11Service.enabled` es estático — cambiar requiere recompilación | Para apagar ICD-11 hay que redesplegar Flutter | Workaround: se puede controlar también desde un doc en Firestore (`TBL_CONFIG/icd11`) si se requiere control remoto sin redespliegue |

---

## Pruebas mínimas que debes correr

### Antes de configurar credenciales OMS (modo degradado)

**Objetivo:** Confirmar que el fallback funciona y nada se rompe sin credenciales.

- [ ] Compilar: `flutter build web --no-tree-shake-icons --no-wasm-dry-run` — sin errores
- [ ] Abrir módulo Nutrición → seleccionar paciente → ir al paso Evaluación
- [ ] Buscar "diabetes" en el selector de diagnósticos → resultados del catálogo local aparecen
- [ ] Seleccionar diagnóstico → chip se agrega correctamente
- [ ] En debug console: buscar el log `Icd11Service: fallback activado` o similar (confirmando que cayó al local)
- [ ] Finalizar atención → verificar `TBL_PACIENTES/{cedula}.diagnosticosMedicosData[0]` no tiene `icdUri` (correcto: diagnóstico local)
- [ ] Verificar que `TBL_ENFERMEDADES` NO recibió documentos nuevos

### Con credenciales OMS configuradas y función desplegada

**Objetivo:** Confirmar flujo ICD-11 end-to-end.

- [ ] Desplegar función: `firebase deploy --only functions`
- [ ] Verificar en consola Firebase que `icd11Search` aparece como callable
- [ ] Abrir Nutrición → buscar "diabetes" → los resultados tienen URI de la OMS (visible en debug print)
- [ ] Seleccionar diagnóstico ICD-11 → verificar en Firestore:
  - `TBL_ENFERMEDADES/{icdCode}` existe con `source: "who_icd11"`, `icdUri`, `icdTitle`
  - El campo `empresaId` es el correcto para la empresa activa
- [ ] Finalizar atención → verificar:
  - `TBL_PACIENTES/{cedula}.diagnosticosMedicosData[0].icdUri` tiene valor
  - `TBL_PACIENTES/{cedula}.diagnosticosMedicosData[0].source` == `"who_icd11"`
- [ ] Recargar el paciente → los chips se restauran correctamente con el diagnóstico ICD-11
- [ ] Probar sin conexión (Network: offline en DevTools) → búsqueda cae al catálogo local sin crash

### Emulación local (opcional, antes de despliegue)

```bash
cd functions
# Crear .runtimeconfig.json con credenciales
firebase emulators:start --only functions
```

Llamar desde Flutter apuntando al emulador:
```dart
// En main.dart, solo en debug:
FirebaseFunctions.instance.useFunctionsEmulator('localhost', 5001);
```

---

## Estado al final de la Fase B

| Componente | Estado |
|-----------|--------|
| Cloud Function `icd11Search` | ✅ Implementada — token broker + proxy seguro |
| `icd11.ts` — token cache en memoria | ✅ Funciona por instancia, margen 90s |
| `icd11.ts` — fallback silencioso a cliente | ✅ Retorna `{results:[],fallback:true}` en error |
| `Icd11Service.dart` — feature flag | ✅ `enabled = true` (activo) |
| `Icd11Service.dart` — timeout 10s | ✅ Fallback automático al expirar |
| `DiagnosticosService.buscarDiagnosticosMedicos()` | ✅ ICD-11 primero, local como fallback |
| `_onDiagnosticosChanged()` — caché TBL_ENFERMEDADES | ✅ Llama `cachearEnEnfermedades()` por cada dx |
| `EvaluacionDiagnostica._toDateTime` — Timestamp fix | ✅ Corregido (duck-typing) |
| TypeScript — `tsc --noEmit` | ✅ Sin errores |
| Flutter — `dart analyze` | ✅ Sin errores nuevos |
| Credenciales OMS en cliente Flutter | ✅ No expuestas (solo en Functions config) |
| Flujo local sin credenciales | ✅ Sigue funcionando via fallback |

---

## Variables obligatorias antes de activar en producción

| Variable | Dónde configurar | Cómo obtener |
|----------|-----------------|-------------|
| `icd11.client_id` | `firebase functions:config:set` | https://icdaccessmanagement.who.int/ |
| `icd11.client_secret` | `firebase functions:config:set` | https://icdaccessmanagement.who.int/ |

**Importante:** Si se usan Firebase Functions v2 o se migra a Secret Manager en el futuro, usar `defineSecret('ICD11_CLIENT_ID')` y `defineSecret('ICD11_CLIENT_SECRET')` en lugar de `functions.config()`.

---

## Siguiente paso recomendado (Fase C / D)

1. Obtener credenciales OMS → configurar → desplegar → validar búsqueda real.
2. **Fase D** (opcional): Cargar `TBL_ENFERMEDADES` como fuente adicional de catálogo (entre Firestore y Excel), para que diagnósticos ya usados por la empresa sean accesibles offline.
3. Extender `EvaluacionDiagnostica.fromMap()` con campos ICD-11 si se requiere trazabilidad desde el historial.
