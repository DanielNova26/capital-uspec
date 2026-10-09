# Publicar ToDo 2.6.26 (40) — Web, Android e iOS

Versión en `pubspec.yaml`: `2.6.26+40`. Lleva los ajustes de visualización en
el teléfono de las siete pasadas (Gerencia, Talento Humano, Interventoría,
Admin, Compras, Visitas, Nutrición, Facturación, Rutas, Gestión Documental,
Correo, Tokens DIAN, Login y Home). El detalle está en `MEJORAS.md`.

## 1. Traer las ramas a `main`

Ramas:

- `claude/friendly-heisenberg-68uaqw`: ajustes de visualización en el teléfono
  y versión 2.6.26+40. **Verde**: 1.633 pruebas Flutter aprobadas.
- `claude/wonderful-johnson-ewjir5`: Planes K2 (tres commits, con cambios en
  Functions). **Roja** al probarla sola: 21 pruebas de Planes K2 fallan
  (`interventoria_planes_test.dart`, `interventoria_planes_mejoras_test.dart`)
  y hay un desborde de 56 px a 390 px con texto 1,6× en
  `interventoria_planes_screen.dart:1536`. `main` pasa esas mismas pruebas.
  Las dos ramas se fusionan sin conflictos.

Desde la carpeta del repositorio, con el trabajo local guardado:

```bash
git fetch origin
git switch main
git pull --ff-only origin main

# A) Recomendado: solo los ajustes del teléfono
git merge --no-ff origin/claude/friendly-heisenberg-68uaqw -m "merge: ajustes de visualización en el teléfono y versión 2.6.26+40"

# B) Solo si ya corrigieron las pruebas rojas de Planes K2:
git merge --no-ff origin/claude/wonderful-johnson-ewjir5 -m "merge: Planes K2"

flutter pub get
flutter analyze lib
flutter test
git push origin main
```

Si se incluye B, publicar también las Functions de Planes K2:

```bash
npm --prefix functions run build
npx firebase-tools deploy --only functions:interventoriaPlanes
```

## 2. Web

```bash
flutter build web --release --no-tree-shake-icons --no-wasm-dry-run
npx firebase-tools deploy --only hosting
```

El `predeploy` (`tool/verificar_build_web.js`) detiene la publicación si
`build/web/version.json` no coincide con `pubspec.yaml`.

## 3. Android (Windows, Flutter 3.44.9, JDK 21)

Requiere `android/key.properties` y el keystore con huella SHA1
`2D:4D:0F:FB:1A:15:48:27:D5:79:F7:55:0A:50:1F:85:A6:99:31:1D`.

```powershell
flutter clean
flutter pub get
flutter build appbundle --release --no-tree-shake-icons --build-name=2.6.26 --build-number=40
```

Subir `build\app\outputs\bundle\release\app-release.aab` a Play Console. Las
notas de versión admiten 500 caracteres por idioma.

## 4. iOS (Mac con Xcode y la cuenta Apple Developer)

```bash
git status --short
git switch main
git pull --ff-only origin main
flutter pub get
flutter build ipa --release --no-tree-shake-icons --build-name=2.6.26 --build-number=40
open build/ios/ipa
```

Subir el `.ipa` con Transporter, o abrir `build/ios/archive/Runner.xcarchive`
y elegir Distribute App → App Store Connect → Upload. Bundle ID
`com.capitaluspec.gestionapp`, equipo `29TDC266FJ`. Después del
procesamiento, elegir la compilación 40 en la versión 2.6.26 y enviar a
revisión.

## Pendiente antes de publicar

- Verificar en un celular real (Android e iPhone) con letra grande los
  cambios de visualización: la revisión fue de código y pruebas, no de
  pantallas renderizadas en un dispositivo.
- iOS no se compila en Windows: requiere Mac.
