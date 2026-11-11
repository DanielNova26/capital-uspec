# To-Do Gestión 2.8.28 (82) para iPhone

En el Mac, abre Terminal en la copia de `capital-uspec`. Usa Xcode 26 o
posterior con el SDK de iOS 26 o posterior y la cuenta Apple Developer de
To-Do Gestión. El proyecto tiene un destino mínimo de iOS 15.5.

```bash
git switch main
git pull --ff-only origin main
xcodebuild -version
xcrun --sdk iphoneos --show-sdk-version
flutter pub get --enforce-lockfile
open ios/Runner.xcworkspace
```

En Xcode, revisa **Runner → Signing & Capabilities** para la configuración
Release. El equipo de Apple es `29TDC266FJ` y el identificador de la app
existente es `com.capitaluspec.gestionapp`.

```bash
flutter build ipa --release --no-pub --no-tree-shake-icons --build-name=2.8.28 --build-number=82
open build/ios/archive/Runner.xcarchive
```

1. En Organizer, selecciona el archivo **2.8.28 (82)**. Pulsa **Validate App**
   y luego **Distribute App → App Store Connect → Upload**.
2. Cuando Apple procese la compilación, revisa la **82** en TestFlight.
   Prueba el inicio de sesión, la agenda y la campana en un iPhone.
3. En App Store Connect, abre la app existente **To-Do Gestión**, selecciona
   la versión de iOS **2.8.28** y elige la compilación **82**. Completa los
   datos de la versión y usa **Add for Review → Submit for Review**.

[Requisitos de Apple](https://developer.apple.com/news/upcoming-requirements/)
· [Compilación iOS con Flutter](https://docs.flutter.dev/deployment/ios)
· [Envío a revisión](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app)
