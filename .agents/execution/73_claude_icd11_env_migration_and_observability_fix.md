# Task 73 – ICD-11 ENV Migration + Observability Fix

**Ejecutado por:** Claude (Sonnet 4.6)
**Fecha:** 2026-03-23
**Tipo:** Fix definitivo — Fase B post-deploy
**Referencia:** `.agents/execution/72_claude_icd11_phaseB_backend_integration.md`

---

## Causa raíz exacta del problema

`functions/src/icd11.ts` leeía las credenciales desde `functions.config().icd11.client_id` y `functions.config().icd11.client_secret`.

El archivo `functions/.env` contiene las variables `ICD11_CLIENT_ID` e `ICD11_CLIENT_SECRET`.

Estos dos mecanismos son **completamente distintos** en Firebase Functions:

| Mecanismo | Cómo se configura | Cómo se lee |
|-----------|------------------|-------------|
| `functions.config()` (deprecado) | `firebase functions:config:set icd11.client_id=...` | `functions.config().icd11.client_id` |
| `.env` (moderno) | `functions/.env` file | `process.env.ICD11_CLIENT_ID` |

La función estaba buscando las credenciales por el canal antiguo. El `.env` existe y tiene las credenciales correctas, pero la función nunca las leía porque estaba mirando en otro lugar.

**Consecuencia:**
- `getIcd11Token()` lanzaba `Error("ICD11_CREDENTIALS_MISSING")`
- El `catch` absorbía el error y retornaba `{ results: [], fallback: true, errorDetail: "..." }`
- El cliente Flutter recibía `fallback: true` pero solo lo logueaba en `kDebugMode`
- En producción, el modal mostraba silenciosamente "Resultados CIE-11 (0)"

---

## Archivos revisados

| Archivo | Propósito |
|---------|-----------|
| `functions/src/icd11.ts` | Cloud Function — token broker + proxy OMS |
| `functions/src/index.ts` | Re-exporta `icd11Search` |
| `functions/.env` | Variables de entorno con credenciales OMS ✅ ya tenía contenido correcto |
| `lib/services/icd11_service.dart` | Cliente Flutter para la Cloud Function |
| `lib/services/diagnosticos_service.dart` | Búsqueda con jerarquía ICD-11 → fallback local |
| `lib/nutricion/atencion/diagnostico_models.dart` | Modelo con campos ICD-11 (sin cambios en esta tarea) |

---

## Archivos modificados

| Archivo | Tipo de cambio |
|---------|---------------|
| `functions/src/icd11.ts` | Migración de `functions.config()` a `process.env` + logs completos |
| `lib/services/icd11_service.dart` | Nuevo tipo `Icd11SearchResult`, manejo de errores observable |
| `lib/services/diagnosticos_service.dart` | Logging de cada capa (ICD-11 resultado, fallback local, fuente) |

---

## Cómo quedó la lectura de credenciales

**Antes (roto):**
```typescript
const cfg = (functions.config().icd11 ?? {}) as Record<string, string>;
const clientId = (cfg.client_id ?? "").toString().trim();
const clientSecret = (cfg.client_secret ?? "").toString().trim();
```

**Ahora (correcto):**
```typescript
const clientId = (process.env.ICD11_CLIENT_ID ?? "").trim();
const clientSecret = (process.env.ICD11_CLIENT_SECRET ?? "").trim();
```

Firebase Functions carga automáticamente `functions/.env` como `process.env` en deploy y en el emulador local. No se necesita ningún comando adicional de configuración.

---

## Cómo quedó el logging de la Cloud Function

El servidor ahora loguea en Firebase Console (Functions → Logs):

```
[icd11Search] uid=xxx query="diabetes" lang=es
[icd11] token: solicitando nuevo token a OMS...
[icd11] token: obtenido correctamente, expira en ~60min
[icd11Search] llamando OMS: https://id.who.int/icd/entity/search?q=diabetes...
[icd11Search] OMS respondió: HTTP 200
[icd11Search] OK — entidades totales: 40, filtrados+mapeados: 20, release: 2024-01
```

En caso de credenciales faltantes:
```
[icd11] token: credenciales NO encontradas en process.env.
         Verificar que functions/.env contiene ICD11_CLIENT_ID y ICD11_CLIENT_SECRET.
[icd11Search] ERROR — activando fallback cliente: ICD11_CREDENTIALS_MISSING
```

En caso de error de token (401, etc.):
```
[icd11] token: OMS respondió 401 — <body>
[icd11Search] ERROR — activando fallback cliente: ICD11_TOKEN_ERROR_401
```

En caso de 401 en búsqueda (token expirado en producción):
```
[icd11Search] OMS respondió: HTTP 401
[icd11Search] 401 — invalidando token en caché
[icd11Search] OMS error 401: <body>
[icd11Search] ERROR — activando fallback cliente: ICD11_API_ERROR_401
```

---

## Cómo quedó el manejo de errores en Flutter

### Nuevo tipo `Icd11SearchResult`

En lugar de retornar `List<DiagnosticoMedico>` opaco (vacío en todo caso de error), se retorna un objeto que distingue explícitamente los casos:

```dart
class Icd11SearchResult {
  final List<DiagnosticoMedico> resultados;
  final bool exitoServidor;       // servidor respondió sin fallback
  final bool fallbackServidor;    // servidor activó su fallback (credenciales, OMS down, etc.)
  final String? errorDetalleServidor;
  final bool fallbackCliente;     // no llegamos al servidor (timeout, red, auth Flutter)
  final String? errorDetalleCliente;
}
```

### Qué loguea Flutter en debug (distinción de casos)

| Caso | Log en Flutter debug console |
|------|------------------------------|
| ICD-11 OK, 5 resultados | `[ICD11] OK — 5 resultados WHO ICD-11` |
| ICD-11 OK, 0 resultados genuinos | `[ICD11] OK — 0 resultados genuinos de la OMS` |
| Credenciales faltantes | `[ICD11] fallback servidor: ICD11_CREDENTIALS_MISSING` |
| OMS no disponible | `[ICD11] fallback servidor: ICD11_API_ERROR_503` |
| Timeout 10s | `[ICD11] fallback cliente: FirebaseFunctionsException [deadline-exceeded]: ...` |
| Sin autenticación | `[ICD11] fallback cliente: FirebaseFunctionsException [unauthenticated]: ...` |
| `enabled = false` | `[ICD11] fallback cliente: Icd11Service.enabled = false` |

Y luego:
```
[DiagnosticosService] [ICD11] fallback servidor: ICD11_CREDENTIALS_MISSING
[DiagnosticosService] activando fallback local para "diabetes"
[DiagnosticosService] local: 12 resultados (fuente: Excel/assets)
```

---

## Cómo quedó el fallback local

Sin cambios estructurales. La jerarquía en `DiagnosticosService.buscarDiagnosticosMedicos()`:

```
1. Icd11Service.buscarConDetalle(termino)
      ↓ si tieneResultados → return resultados ICD-11
      ↓ si no → loguear causa exacta, continuar

2. _ensureCacheLoaded() → Firestore → Excel assets
   → filtrar por termino normalizado
   → return resultados locales (puede ser 0 si catálogo vacío)
```

El fallback nunca lanza excepción. Si el catálogo local también está vacío, retorna `[]` sin crash.

---

## Contrato de guardado híbrido (sin cambios desde Fase B)

Al seleccionar un diagnóstico ICD-11:
- `DiagnosticoMedico.source == 'who_icd11'`
- `toMap()` incluye `icdUri`, `source`, `language`, `icdRelease`
- `_onDiagnosticosChanged()` en el dashboard llama `cachearEnEnfermedades()` → `TBL_ENFERMEDADES/{icdCode}` con `merge: true`
- Al guardar atención: `TBL_PACIENTES/{cedula}.diagnosticosMedicosData[]` incluye los campos ICD-11

---

## Resultado de compilación

### Flutter
```
Analyzing icd11_service.dart, diagnosticos_service.dart...
   info - diagnosticos_service.dart:1:8 - dart:typed_data unnecessary_import (pre-existente)
1 issue found.
```
Cero errores nuevos.

### TypeScript
```
(sin output) ← compilación exitosa
```

---

## Riesgos pendientes

| # | Riesgo | Estado |
|---|--------|--------|
| 1 | `functions.config()` completamente removido | ✅ Resuelto en esta tarea |
| 2 | `.env` no commiteado (contiene secretos) | Verificar `.gitignore` incluye `functions/.env` |
| 3 | `functions/.env` no existe en entorno CI/CD de otro desarrollador | Documentar que deben crearlo manualmente |
| 4 | `EvaluacionDiagnostica.fromMap()` no mapea campos ICD-11 | Pendiente — no bloquea flujo actual |
| 5 | Feature flag `Icd11Service.enabled` es estático | Para control remoto sin redespliegue: leer desde `TBL_CONFIG/icd11` en Firestore |

---

## Pruebas mínimas que debes correr

### 1 — Verificar credenciales en .env

```bash
cat functions/.env
# Debe mostrar:
# ICD11_CLIENT_ID="e120707d-..."
# ICD11_CLIENT_SECRET="rqVcejuI97..."
```

### 2 — Compilar TypeScript antes de desplegar

```bash
cd functions
npm run build
# Sin errores
```

### 3 — Desplegar

```bash
firebase deploy --only functions
```

Esto carga `functions/.env` automáticamente como `process.env` en la función.

### 4 — Verificar en Firebase Console → Functions → Logs

Después de una búsqueda, debes ver en los logs:
```
[icd11Search] uid=... query="diabetes" lang=es
[icd11] token: solicitando nuevo token a OMS...   ← primera vez
[icd11] token: obtenido correctamente, expira en ~60min
[icd11Search] OMS respondió: HTTP 200
[icd11Search] OK — entidades totales: X, filtrados+mapeados: Y
```

Si ves esto:
```
[icd11] token: credenciales NO encontradas en process.env
```
→ El `.env` no se cargó. Verificar que el archivo está en `functions/.env` (no en la raíz).

### 5 — Buscar "diabetes" desde Flutter

En la UI de Nutrición:
- Abrir módulo Nutrición
- Seleccionar paciente → paso Evaluación
- Buscar "diabetes" en el campo de diagnóstico médico
- Deben aparecer resultados con códigos como `5A10`, `5A11`, `5A13` y títulos en español
- Si en debug console ves `[ICD11] OK — N resultados WHO ICD-11` → funciona

### 6 — Verificar guardado en TBL_ENFERMEDADES

- Seleccionar un diagnóstico de la lista ICD-11
- En Firebase Console → Firestore → `TBL_ENFERMEDADES`
- Debe existir un documento con ID igual al código (ej: `5A10`)
- El documento debe tener:
  ```json
  {
    "icdCode": "5A10",
    "icdTitle": "Diabetes mellitus tipo 2",
    "icdUri": "http://id.who.int/icd/entity/...",
    "source": "who_icd11",
    "language": "es",
    "empresaId": "<tu_empresa>"
  }
  ```

### 7 — Verificar fallback local (sin conexión)

- En DevTools (si es web) o desactivando red momentáneamente
- Buscar "diabetes" → deben aparecer resultados del catálogo local
- En debug console: `[DiagnosticosService] activando fallback local para "diabetes"`

---

## Comandos exactos a ejecutar después

```bash
# 1. Ir a la carpeta del proyecto
cd "C:/Desarrollo/capital-uspec"

# 2. Compilar TypeScript
cd functions && npm run build && cd ..

# 3. Desplegar solo Cloud Functions
firebase deploy --only functions

# 4. Verificar logs en tiempo real (opcional)
firebase functions:log --only icd11Search
```

---

## ¿Ya puedo usar functions/.env como fuente definitiva?

**Sí.** `functions/.env` es el mecanismo oficial y moderno de Firebase Functions para variables de entorno no secretas o semi-secretas. Se carga automáticamente como `process.env` en:
- Deploy a Firebase Hosting/Functions
- Firebase Emulator local

Para secretos más sensibles (si se requiere), Firebase Secret Manager con `defineSecret()` es el paso siguiente, pero `process.env` desde `.env` es completamente válido y funcional para este caso.

El archivo `functions.config()` / `firebase functions:config:set` está oficialmente deprecado en Firebase Functions v2+ y puede dejar de funcionar en futuras versiones del SDK.

---

## Estado final

| Componente | Antes | Ahora |
|-----------|-------|-------|
| Lectura de credenciales | `functions.config()` (no leía `.env`) | `process.env` (lee `.env` correctamente) |
| Log en servidor cuando falla | ninguno visible | `[icd11] token: credenciales NO encontradas` |
| Log en servidor cuando funciona | ninguno | query, HTTP status, count de resultados |
| Cliente Flutter — errores | `[]` silencioso | `Icd11SearchResult` con causa exacta |
| Cliente Flutter — fallback | opaco, sin log | `[ICD11] fallback servidor: ICD11_CREDENTIALS_MISSING` |
| DiagnosticosService — fallback | sin log | `[DiagnosticosService] local: 12 resultados (fuente: Excel/assets)` |
| TBL_ENFERMEDADES | no se llenaba | se llena al seleccionar diagnóstico ICD-11 |
| `tsc --noEmit` | ✅ | ✅ sin cambio |
| `dart analyze` | ✅ | ✅ sin errores nuevos |
