# Task 69 – ICD-11 Hybrid Integration Plan

**Ejecutado por:** Claude (Sonnet 4.6)
**Fecha:** 2026-03-21
**Tipo:** Plan de arquitectura + primer nivel funcional
**Alcance:** Módulo Nutrición – flujo de diagnósticos

---

## 1. Estado actual del sistema (auditoría)

### Cómo se guardan hoy los diagnósticos

| Capa | Archivo | Descripción |
|------|---------|-------------|
| Modelo | `lib/nutricion/atencion/diagnostico_models.dart` | `DiagnosticoMedico` (con `codigoCie11`), `DiagnosticoNutricional`, `EvaluacionDiagnostica` |
| Servicio | `lib/services/diagnosticos_service.dart` | Cache en memoria desde Excel (assets) o Firestore. Búsqueda local normalizada. |
| Widget | `lib/widgets/selector_diagnosticos_widget.dart` | UI con debounce, chips acumulables, catálogo unificado en bottom sheet |
| Pantalla dedicada | `lib/nutricion/atencion/entrada_diagnosticos_screen.dart` | Formulario completo con tabs médico + nutricional |
| Dashboard principal | `lib/nutricion/nutricion_dashboard_screen.dart` | Integra `SelectorDiagnosticosWidget`. Guarda en `TBL_PACIENTES` como `diagnosticosMedicosData[]` y `diagnosticosNutricionalesData[]` |
| Colección evaluaciones | `TBL_EVALUACIONES_DIAGNOSTICAS` | Historial formal de evaluaciones por paciente vía `guardarEvaluacionDiagnostica()` |

### Fuente de datos actual

```
Primaria:   TBL_DIAGNOSTICOS_MEDICOS / TBL_DIAGNOSTICOS_NUTRICIONALES (Firestore)
Fallback 1: assets/diagnosticos_template.xlsx (Excel local en assets)
Fallback 2: Lista vacía (si ambos fallan)
```

`DiagnosticoMedico.codigoCie11` ya existe como campo en el modelo. El campo no viene de la API oficial de la OMS, viene del Excel importado manualmente.

### TBL_ENFERMEDADES

- No existe ninguna referencia a `TBL_ENFERMEDADES` en el código Flutter.
- El usuario confirma que existe en Firebase (probablemente creada desde la consola o por script externo).
- Actualmente no se lee ni se escribe desde la app.
- **No se rompe, no se toca, se usa como caché de resultados ICD-11 seleccionados.**

---

## 2. Modelo híbrido ICD-11 + TBL_ENFERMEDADES

### Jerarquía de fuentes de búsqueda (orden de preferencia)

```
1. ICD-11 WHO API  →  online, código oficial, bilingüe
2. TBL_DIAGNOSTICOS_MEDICOS (Firestore)  →  caché por empresa, datos enriquecidos
3. assets/diagnosticos_template.xlsx  →  fallback offline
```

### TBL_ENFERMEDADES como caché de selecciones ICD-11

Cuando el usuario selecciona un diagnóstico que proviene de la API ICD-11 (no del catálogo local), se guarda en `TBL_ENFERMEDADES` para:
- Reutilización futura sin llamada a la API
- Disponibilidad offline en sesiones posteriores
- Registro auditable de diagnósticos usados en la empresa

Estructura del documento en `TBL_ENFERMEDADES`:
```json
{
  "icdCode": "XH9U21",
  "icdTitle": "Diabetes mellitus tipo 2",
  "icdUri": "http://id.who.int/icd/entity/1589022230",
  "source": "who_icd11",
  "language": "es",
  "icdRelease": "2024-01",
  "empresaId": "uspec",
  "creadoEn": <serverTimestamp>,
  "creadoPor": "userId"
}
```

Clave del documento: `{icdCode}` (evita duplicados por código).

---

## 3. Arquitectura segura: token broker + proxy

### Problema de seguridad

La API de ICD-11 de la OMS usa OAuth2 client credentials:
- `client_id` → puede estar en el cliente (no es secreto en sí)
- `client_secret` → **no puede estar en el cliente** (Flutter compila todo en el binario)

Si se expone el `client_secret` en el APK/bundle web, cualquiera puede extraerlo y hacer requests en nombre de la app.

### Solución recomendada: Firebase Cloud Functions como token broker + proxy

El proyecto ya usa Firebase. La solución más natural y sin infraestructura adicional es:

```
Flutter Client
    │
    ├─ onLine? ──► Firebase Cloud Function "icd11Search"
    │                      │
    │                      ├─ 1. getToken() → POST https://icdaccessmanagement.who.int/connect/token
    │                      │                  (con client_id + client_secret server-side)
    │                      ├─ 2. searchIcd11() → GET https://id.who.int/icd/entity/search
    │                      │                     (con Bearer token)
    │                      └─ 3. retorna resultados normalizados al cliente
    │
    └─ offline? ──► Firestore TBL_DIAGNOSTICOS_MEDICOS
                         │
                         └─ fallback → assets/diagnosticos_template.xlsx
```

### Estructura de la Cloud Function

**Archivo:** `functions/src/icd11.ts` (o `icd11.js`)

```typescript
// functions/src/icd11.ts

import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import fetch from 'node-fetch';

const ICD11_TOKEN_URL = 'https://icdaccessmanagement.who.int/connect/token';
const ICD11_SEARCH_URL = 'https://id.who.int/icd/entity/search';

// Token en caché en memoria de la función (válido ~1h)
let _cachedToken: string | null = null;
let _tokenExpiry: number = 0;

async function getIcd11Token(): Promise<string> {
  if (_cachedToken && Date.now() < _tokenExpiry - 60000) {
    return _cachedToken;
  }

  const clientId = functions.config().icd11.client_id;
  const clientSecret = functions.config().icd11.client_secret;

  const response = await fetch(ICD11_TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=client_credentials&client_id=${clientId}&client_secret=${clientSecret}&scope=icdapi_access`,
  });

  const data = await response.json();
  _cachedToken = data.access_token;
  _tokenExpiry = Date.now() + data.expires_in * 1000;
  return _cachedToken!;
}

export const icd11Search = functions.https.onCall(async (data, context) => {
  // Requiere usuario autenticado (cualquier usuario Firebase)
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Debe estar autenticado');
  }

  const { query, language = 'es', subtreeFilterUsage = 'includedChildrenAndChildren' } = data;

  if (!query || query.trim().length < 2) {
    return { results: [] };
  }

  try {
    const token = await getIcd11Token();

    const url = new URL(ICD11_SEARCH_URL);
    url.searchParams.set('q', query);
    url.searchParams.set('language', language);
    url.searchParams.set('subtreeFilterUsage', subtreeFilterUsage);
    url.searchParams.set('flatResults', 'true');
    url.searchParams.set('highlightingEnabled', 'false');
    url.searchParams.set('medicalCodingMode', 'true');

    const response = await fetch(url.toString(), {
      headers: {
        Authorization: `Bearer ${token}`,
        Accept: 'application/json',
        'Accept-Language': language,
        'API-Version': 'v2',
      },
    });

    const json = await response.json();

    // Normalizar resultados al formato DiagnosticoMedico
    const results = (json.destinationEntities || []).slice(0, 20).map((entity: any) => ({
      icdCode: entity.theCode || '',
      icdTitle: entity.title?.['@value'] || '',
      icdUri: entity.id || '',
      source: 'who_icd11',
      language,
      icdRelease: '2024-01',
    }));

    return { results };
  } catch (e) {
    throw new functions.https.HttpsError('internal', `Error ICD-11: ${e}`);
  }
});
```

**Configuración de secretos (no en código):**
```bash
firebase functions:config:set icd11.client_id="TU_CLIENT_ID" icd11.client_secret="TU_CLIENT_SECRET"
```

### Alternativa mínima (si no se quiere Cloud Functions aún)

Para una primera versión sin backend:
- Usar **solo el fallback local** (Excel/Firestore) con los campos `icdCode` del catálogo existente.
- Agregar los campos de metadata ICD-11 al modelo y al guardado.
- El campo `source` sería `"local_catalog"` en lugar de `"who_icd11"`.
- La búsqueda real contra la API se habilita cuando se despliegue la Cloud Function.

Este enfoque permite avanzar en el modelo de datos y el flujo de guardado sin bloquear en la infraestructura del backend.

---

## 4. Archivos revisados

| Archivo | Propósito |
|---------|-----------|
| `lib/nutricion/atencion/diagnostico_models.dart` | Modelos actuales: `DiagnosticoMedico`, `DiagnosticoNutricional`, `EvaluacionDiagnostica` |
| `lib/services/diagnosticos_service.dart` | Cache en memoria, búsqueda local, importación Excel, CRUD Firestore |
| `lib/widgets/selector_diagnosticos_widget.dart` | Widget de selección con debounce, chips, catálogo bottom sheet |
| `lib/nutricion/atencion/entrada_diagnosticos_screen.dart` | Pantalla completa de entrada de diagnósticos (tabs médico + nutricional) |
| `lib/nutricion/nutricion_dashboard_screen.dart` | Dashboard principal: integra selector, guarda en TBL_PACIENTES |
| `.agents/execution/63_claude_nutrition_clinical_flow_fix.md` | Contexto de la última refactorización clínica |

---

## 5. Archivos a modificar (implementación)

| Archivo | Tipo de cambio | Impacto |
|---------|---------------|---------|
| `lib/nutricion/atencion/diagnostico_models.dart` | Agregar campos ICD-11 al modelo `DiagnosticoMedico` | Bajo — backward compatible vía `fromMap` |
| `lib/services/diagnosticos_service.dart` | Agregar `buscarDiagnosticosMedicosIcd11()` y `cachearEnEnfermedades()` | Bajo — método nuevo, no modifica existentes |
| `lib/services/icd11_service.dart` | **Nuevo archivo** — cliente de la Cloud Function proxy | Nuevo — sin impacto en existente |
| `lib/widgets/selector_diagnosticos_widget.dart` | Agregar indicador de fuente (ICD-11 vs local) y fuente ICD-11 en búsqueda | Bajo — solo UI adicional |
| `functions/src/icd11.ts` | **Nuevo archivo** — Cloud Function token broker + proxy | Backend nuevo — sin impacto en Flutter hasta despliegue |

**No se tocan:**
- `nutricion_dashboard_screen.dart` — el guardado ya funciona con `d.toMap()`. Solo requiere que el modelo actualizado incluya los campos nuevos.
- `nutricion_menus_screen.dart`
- `nutricion_service.dart` — no interviene en el flujo de diagnósticos
- Módulos externos (home, compras, talento humano, admin)

---

## 6. Modelo de datos recomendado

### DiagnosticoMedico extendido

```dart
class DiagnosticoMedico {
  // Campos existentes (no se tocan)
  final String codigoCie11;
  final String nombre;
  final String? categoria;
  final String? subcategoria;
  final List<String> comorbilidades;
  final List<String> medicamentosRelacionados;
  final List<String> interaccionesFarmacoNutriente;
  final Map<String, dynamic>? rangosBioquimicos;
  final String? estadio;
  final String? gravedad;
  final List<String> dietasContraindicadas;
  final List<String> dietasSugeridas;
  final bool activo;

  // Campos nuevos — todos opcionales para compatibilidad hacia atrás
  final String? icdUri;         // URI canónica: "http://id.who.int/icd/entity/..."
  final String? source;         // "who_icd11" | "local_catalog" | "firestore_cache"
  final String? language;       // "es" | "en"
  final String? icdRelease;     // "2024-01"
}
```

**Serialización:**
- `toMap()` incluye los campos nuevos cuando no son null.
- `fromMap()` lee los campos nuevos de forma opcional (backward compatible).

### Documento en TBL_ENFERMEDADES

```
Colección: TBL_ENFERMEDADES
Documento ID: {icdCode}  (e.g., "XH9U21")

{
  "icdCode": "XH9U21",
  "icdTitle": "Diabetes mellitus tipo 2",
  "icdUri": "http://id.who.int/icd/entity/1589022230",
  "source": "who_icd11",
  "language": "es",
  "icdRelease": "2024-01",
  "empresaId": "uspec",
  "creadoEn": Timestamp,
  "creadoPor": "userId"
}
```

### EvaluacionDiagnostica extendida (TBL_EVALUACIONES_DIAGNOSTICAS)

Se agrega al documento guardado:
```json
{
  ...(campos existentes),
  "icdCode": "XH9U21",
  "icdTitle": "Diabetes mellitus tipo 2",
  "icdUri": "http://id.who.int/icd/entity/1589022230",
  "icdSource": "who_icd11",
  "icdLanguage": "es"
}
```

### TBL_PACIENTES — campo diagnosticosMedicosData[]

Cada elemento del array ya usa `DiagnosticoMedico.toMap()`. Con el modelo extendido, automáticamente incluirá los campos ICD-11 sin cambiar el código del dashboard.

---

## 7. Servicio ICD-11 cliente (Flutter)

**Nuevo archivo: `lib/services/icd11_service.dart`**

```dart
import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:todo/nutricion/atencion/diagnostico_models.dart';

class Icd11Service {
  static final _functions = FirebaseFunctions.instance;

  /// Busca diagnósticos en la API ICD-11 vía Cloud Function.
  /// Retorna lista vacía si falla (se activa el fallback en DiagnosticosService).
  static Future<List<DiagnosticoMedico>> buscar(String query, {String language = 'es'}) async {
    try {
      final callable = _functions.httpsCallable('icd11Search');
      final result = await callable.call<Map>({'query': query, 'language': language});
      final results = (result.data['results'] as List?) ?? [];

      return results.map((r) => DiagnosticoMedico(
        codigoCie11: r['icdCode'] ?? '',
        nombre: r['icdTitle'] ?? '',
        icdUri: r['icdUri'],
        source: 'who_icd11',
        language: language,
        icdRelease: r['icdRelease'],
      )).toList();
    } catch (e) {
      if (kDebugMode) debugPrint('Icd11Service: fallback activado ($e)');
      return [];
    }
  }
}
```

---

## 8. Extensión de DiagnosticosService

En `buscarDiagnosticosMedicos()`, agregar la siguiente lógica:

```dart
Future<List<DiagnosticoMedico>> buscarDiagnosticosMedicos(String termino) async {
  final terminoNorm = _normalizeForSearch(termino);
  if (terminoNorm.isEmpty) return [];

  // 1. Intentar ICD-11 online (si la Cloud Function está desplegada)
  if (!_icd11Disabled) {
    final icdResults = await Icd11Service.buscar(termino);
    if (icdResults.isNotEmpty) return icdResults;
  }

  // 2. Fallback: cache local (Firestore o Excel)
  await _ensureCacheLoaded();
  return (_cacheMedicos ?? []).where((dx) {
    final codigo = _normalizeForSearch(dx.codigoCie11);
    final nombre = _normalizeForSearch(dx.nombre);
    return codigo.contains(terminoNorm) || nombre.contains(terminoNorm);
  }).toList();
}
```

La variable `_icd11Disabled` puede ser un flag de feature (en `false` por defecto hasta que se despliegue la Cloud Function).

---

## 9. Guardado dual (TBL_ENFERMEDADES + TBL_EVALUACIONES_DIAGNOSTICAS)

Cuando el usuario selecciona un diagnóstico de fuente `who_icd11`, el servicio:

1. Guarda en `TBL_ENFERMEDADES/{icdCode}` (upsert — no duplica si ya existe).
2. Incluye `icdCode/icdTitle/icdUri/icdSource` en el payload de `guardarEvaluacionDiagnostica()`.
3. El `toMap()` extendido de `DiagnosticoMedico` se persiste automáticamente en `TBL_PACIENTES.diagnosticosMedicosData[]`.

**Método nuevo en `DiagnosticosService`:**

```dart
Future<void> cachearEnEnfermedades({
  required DiagnosticoMedico dx,
  required String empresaId,
  required String userId,
}) async {
  if (dx.icdUri == null || dx.source != 'who_icd11') return;

  await _db.collection('TBL_ENFERMEDADES').doc(dx.codigoCie11).set({
    'icdCode': dx.codigoCie11,
    'icdTitle': dx.nombre,
    'icdUri': dx.icdUri,
    'source': dx.source,
    'language': dx.language ?? 'es',
    'icdRelease': dx.icdRelease,
    'empresaId': empresaId,
    'creadoPor': userId,
    'creadoEn': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}
```

---

## 10. Diferencias Web vs Móvil

| Aspecto | Compartido | Web | Móvil |
|---------|-----------|-----|-------|
| Lógica de búsqueda ICD-11 | Sí — mismo `Icd11Service` | — | — |
| Token broker / Cloud Function | Sí — mismo endpoint | — | — |
| Fallback local | Sí — mismo `DiagnosticosService` | — | — |
| Guardado en Firestore | Sí — mismo `guardarEvaluacionDiagnostica()` | — | — |
| Componente web oficial OMS (ECT iframe) | No | Opción futura: widget `icd11ect.js` en `HtmlElementView` | No aplica |
| UX del selector | Diferenciable | Panel lateral o dialog amplio | Bottom sheet (ya implementado) |

**Nota sobre el ECT widget de la OMS:** La OMS provee un widget JS (`icd11ect.js`) que puede embeberse en web vía iframe. En Flutter Web puede usarse con `HtmlElementView`. Es una opción para una segunda fase, pero requiere gestión del token en el cliente (menos segura) o un iframe con sesión propia. No se recomienda para el primer nivel funcional.

---

## 11. Riesgos pendientes

| # | Riesgo | Impacto | Mitigación |
|---|--------|---------|-----------|
| 1 | Cloud Functions no está desplegada → ICD-11 no responde | Búsqueda cae al fallback local | Flag `_icd11Disabled = true` hasta despliegue. El flujo no se rompe. |
| 2 | Token ICD-11 expirado en la Cloud Function durante concurrencia alta | Error 401 en búsqueda | Cache de token con margen de 60s antes de expiración (ya contemplado en el código de la función) |
| 3 | `TBL_ENFERMEDADES` no tiene índice por `empresaId` | Lecturas lentas o fallidas | Crear índice: `empresaId` (single-field) antes de habilitar lectura |
| 4 | El modelo extendido `DiagnosticoMedico` con campos nullables puede causar NPE en `fromMap()` legacy | Diagnósticos existentes sin `icdUri` lanzarían error | `fromMap()` ya usa `?.toString()` para todos los campos — extender igual |
| 5 | Firebase Cloud Functions agrega latencia (~300-800ms) en cold start | UX perceptible en primera búsqueda | Mostrar indicador de carga en el campo de búsqueda (ya existe en `SelectorDiagnosticosWidget`) |
| 6 | ICD-11 API devuelve en inglés por defecto | Títulos en inglés si no se pasa `language=es` | Siempre pasar `language: 'es'` en `Icd11Service.buscar()` |
| 7 | `TBL_ENFERMEDADES` puede crecer sin límite si se cachean muchas búsquedas | Costo de Firestore | Upsert por `icdCode` evita duplicados. Crecimiento acotado al número de diagnósticos únicos usados. |

---

## 12. Pruebas mínimas a correr

### Pre-condición: Cloud Function NO desplegada (modo fallback)
- [ ] Buscar "diabetes" → retorna resultados del catálogo local
- [ ] Seleccionar un diagnóstico → aparece chip en el widget
- [ ] Guardar expediente → en `TBL_PACIENTES/{cedula}.diagnosticosMedicosData[]` existe el diagnóstico con `codigoCie11` correcto
- [ ] Recargar paciente → chips se restauran desde Firestore (via `initialMedicos` en `SelectorDiagnosticosWidget`)

### Con Cloud Function desplegada (modo ICD-11)
- [ ] Buscar "diabetes" → los primeros resultados provienen de la API ICD-11 (campo `source: "who_icd11"`)
- [ ] Seleccionar diagnóstico ICD-11 → chip muestra código + título en español
- [ ] Guardar → `TBL_ENFERMEDADES/{icdCode}` tiene el documento cacheado
- [ ] Guardar → `TBL_EVALUACIONES_DIAGNOSTICAS/{id}` tiene `icdCode`, `icdTitle`, `icdUri`, `icdSource`
- [ ] Sin conexión → fallback activa catálogo local sin error
- [ ] Diagnósticos existentes (sin campos ICD-11) → siguen funcionando sin crash

### Compatibilidad con diagnósticos previos
- [ ] Abrir expediente de paciente con diagnósticos guardados antes de la integración → no hay crash
- [ ] Los campos `icdUri/source/language` son `null` → `toMap()` los omite y `fromMap()` los lee como `null`

---

## 13. Pasos de implementación (orden recomendado)

### Fase A — Modelo (sin backend, riesgo cero)
1. Extender `DiagnosticoMedico` con campos nullables: `icdUri`, `source`, `language`, `icdRelease`
2. Actualizar `toMap()` y `fromMap()` (backward compatible)
3. Agregar `cachearEnEnfermedades()` en `DiagnosticosService`
4. Agregar `icdCode/icdTitle/icdUri/icdSource` a `guardarEvaluacionDiagnostica()` en el payload
5. Verificar `dart analyze` limpio

### Fase B — Servicio ICD-11 cliente (sin backend, feature flag en false)
6. Crear `lib/services/icd11_service.dart` con feature flag `_icd11Enabled = false`
7. Integrar `buscarDiagnosticosMedicosIcd11()` en `DiagnosticosService` (con flag apagado)
8. Agregar badge de fuente en `SelectorDiagnosticosWidget` (solo si `source == 'who_icd11'`)

### Fase C — Backend (requiere credenciales OMS)
9. Crear proyecto Firebase Functions si no existe
10. Crear `functions/src/icd11.ts` con token broker + search proxy
11. Configurar secretos: `firebase functions:config:set icd11.client_id=... icd11.client_secret=...`
12. Desplegar: `firebase deploy --only functions:icd11Search`
13. Activar feature flag en `Icd11Service`: `_icd11Enabled = true`
14. Correr pruebas de Fase C

### Fase D — Caché en TBL_ENFERMEDADES
15. Llamar `cachearEnEnfermedades()` al seleccionar diagnóstico de fuente ICD-11
16. Opcionalmente: cargar `TBL_ENFERMEDADES` como fuente adicional en `_ensureCacheLoaded()` (entre Firestore y Excel)

---

## 14. Siguiente paso mínimo recomendado

**El primer paso seguro es implementar la Fase A** — solo cambios al modelo y al servicio de guardado, sin backend, sin UI nueva, sin romper nada.

Esto habilita:
- Que cuando se agregue el backend, el modelo ya esté listo.
- Que `TBL_ENFERMEDADES` empiece a recibir datos desde el flujo clínico.
- Que `TBL_EVALUACIONES_DIAGNOSTICAS` tenga los campos ICD-11 listos para cuando la búsqueda real esté activa.

**Costo:** bajo. **Riesgo:** casi cero. **Reversión:** inmediata (los campos son nullables).

---

## Resumen ejecutivo

### Arquitectura propuesta

```
Flutter (cliente)
  └── DiagnosticosService
        ├── Icd11Service → Firebase Cloud Function (token broker + proxy WHO ICD-11)
        ├── TBL_DIAGNOSTICOS_MEDICOS (Firestore cache enriquecido)
        └── assets/diagnosticos_template.xlsx (fallback offline)

Guardado dual al seleccionar diagnóstico ICD-11:
  ├── TBL_ENFERMEDADES/{icdCode}  (caché reutilizable por empresa)
  ├── TBL_PACIENTES/{cedula}.diagnosticosMedicosData[]  (expediente del paciente)
  └── TBL_EVALUACIONES_DIAGNOSTICAS/{id}  (historial formal)
```

### ¿Recomiendo backend/proxy?

**Sí, Firebase Cloud Functions es el camino correcto.**
- No se puede poner `client_secret` en Flutter.
- El proyecto ya usa Firebase, por lo que no agrega infraestructura nueva.
- La Cloud Function también puede cachear el token en memoria, reduciendo llamadas a la API de la OMS.
- El costo es mínimo (pocas llamadas por sesión de búsqueda).

Si las credenciales OMS aún no están disponibles, la Fase A y B pueden implementarse sin backend, usando el catálogo local con los campos ICD-11 del Excel existente.

### Cómo quedaría el guardado híbrido

Al guardar un diagnóstico:
- Si `source == "who_icd11"`: se guarda también en `TBL_ENFERMEDADES` como caché.
- En todos los casos: `diagnosticosMedicosData[]` en `TBL_PACIENTES` incluye todos los campos del modelo (incluidos `icdUri`, `source`, `language` cuando aplique).
- Diagnósticos del catálogo local siguen funcionando exactamente igual, con `source = "local_catalog"` o `null`.

### Primer paso mínimo a probar

1. Extender `DiagnosticoMedico` con los campos nullables (`icdUri`, `source`, `language`, `icdRelease`).
2. Verificar que `dart analyze` sigue limpio.
3. Guardar un expediente y verificar en Firestore que el mapa del diagnóstico no se rompe.
4. Confirmar que pacientes con diagnósticos previos siguen cargando correctamente.

Esto valida el modelo sin riesgo y deja la puerta abierta para activar la búsqueda ICD-11 real cuando las credenciales estén disponibles.
