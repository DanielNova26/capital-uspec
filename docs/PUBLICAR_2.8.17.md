# Publicar To-Do Gestión 2.8.17 (71) — 4 de noviembre de 2026

Incluye las correcciones de reasignación de tareas de Interventoría y la
recuperación selectiva de descargas ilegibles de Visitas. La versión común en
`pubspec.yaml` es `2.8.17+71`.

## Android / Google Play

Archivo de entrega: `outputs/android/to-do-gestion-2.8.17-71.aab`.
Su suma de comprobación está en el archivo contiguo `.aab.sha256`.

En Play Console, abrir la app existente `com.todogestion.app`, crear una
versión en el canal deseado y cargar este AAB. Revisar el código 71, completar
las notas y continuar la revisión/publicación desde la consola. No crear otra app.

No se ha consultado el último código usado en Play Console. El 71 es el siguiente
al último AAB local (70); si la consola ya lo utilizó, hay que aumentar el número
y generar un nuevo AAB, sin reutilizar el anterior.

## iPhone / App Store Connect

El IPA se genera en el Mac del usuario, con Xcode y Apple Developer ya
configurados. No se ha compilado ni firmado un IPA desde este equipo Windows.
El Mac también necesita Flutter y CocoaPods instalados.

Identidad existente del proyecto:

- Bundle ID: `com.capitaluspec.gestionapp`.
- Equipo Apple: `29TDC266FJ`.
- Versión: `2.8.17`; compilación: `71`.
- iOS mínimo del proyecto: `15.5`.
- Release usa `RunnerProfile.entitlements`, con APNs de producción.
- `Info.plist` obtiene versión/build de Flutter; no editarlos a mano.

Usar una versión estable de Xcode compatible con el Mac y con SDK de iOS 26 o
posterior: Apple lo exige para las subidas desde el 28 de abril de 2026.

Desde la carpeta de este repositorio en el Mac, con el trabajo local guardado y
`git status --short` vacío:

```bash
git status --short
git switch main
git pull --ff-only origin main
flutter --version
pod --version
flutter pub get
(cd ios && pod update --repo-update)
flutter build ipa --release --build-name=2.8.17 --build-number=71
open build/ios/ipa
```

Detenerse si falla algún comando. No continuar con un IPA de una compilación
anterior. No es necesario desinstalar la app ni borrar sus datos del iPhone.
El entorno usado para Android/Web fue Flutter 3.44.9 y Dart 3.12.2; conviene
usar la misma versión de Flutter en el Mac.

`pod update --repo-update` es necesario en esta entrega porque el
`ios/Podfile.lock` versionado aún recoge FlutterFire antiguo (por ejemplo,
firebase_core 3.14.0) y no incluye el nuevo plugin `gal`; las dependencias Dart
actuales son más recientes. Se actualizan los Pods nativos en el Mac sin borrar
el lock ni el código. Si cambia `ios/Podfile.lock`, revisar y conservar el cambio
para sincronizarlo tras la compilación correcta, sin incluir trabajo ajeno.

Si falta configurar la firma, abrir:

```bash
open ios/Runner.xcworkspace
```

En Runner → Signing & Capabilities, seleccionar el equipo de esta aplicación y
revisar la firma automática. Conservar el Bundle ID existente. Volver a ejecutar
la compilación después de resolver certificados/perfiles o errores de Pods.

Subir el `.ipa` recién generado con **Transporter**. Como alternativa, abrir el
archivo de Xcode y usar **Distribute App → App Store Connect → Upload**:

```bash
open build/ios/archive/Runner.xcarchive
```

Tras el procesamiento de Apple, comprobar versión `2.8.17` y build `71`, probar
en TestFlight y seleccionar la compilación en la versión correspondiente de
App Store Connect para enviar a revisión. Comprobar que el build no esté ya
usado en esa versión. Subir el binario no publica por sí solo la actualización.

## Notas para ambas tiendas

> Corregimos la búsqueda de personal por área y cargo al reasignar tareas de
> Interventoría. Agregamos la recuperación selectiva de descargas dañadas de
> Visitas, conservando sus archivos originales y las visitas pendientes de envío.
> Mejoramos los mensajes cuando no es posible conectar con el servidor.

Antes de distribuir, validar en dispositivos reales la segunda reasignación,
descarga/recuperación, biometría, fotos, firmas, teclado y envío de visitas. Una
descarga nueva no recupera respuestas de archivos ilegibles. Las visitas legibles
pendientes de enviar deben sincronizarse, no descartarse.

Referencias oficiales: [publicar iOS con Flutter](https://docs.flutter.dev/deployment/ios),
[requisitos de SDK de Apple](https://developer.apple.com/news/?id=ueeok6yw) y
[cargar builds en App Store Connect](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/).
