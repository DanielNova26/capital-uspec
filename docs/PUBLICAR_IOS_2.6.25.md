# Publicar ToDo 2.6.25 (39) en iOS — 9 de octubre de 2026

La rama `claude/eloquent-goodall-mrk87j` está integrada en `main`.
Ejecutar desde la carpeta del repositorio en el Mac, con el trabajo local
guardado y confirmado antes de cambiar de rama. No hace falta volver a fusionar
la rama de Claude.

```bash
git status --short
git switch main
git pull --ff-only origin main
flutter --version
flutter pub get
flutter build ipa --release --no-tree-shake-icons --build-name=2.6.25 --build-number=39
open build/ios/ipa
```

La versión validada en este equipo es Flutter 3.44.9 / Dart 3.12.2.
La compilación iOS requiere macOS, Xcode y la cuenta Apple Developer con
certificados y perfiles de distribución de la aplicación.

- Bundle ID existente: `com.capitaluspec.gestionapp`.
- Equipo configurado: `29TDC266FJ`.
- Versión: `2.6.25`; compilación: `39`.
- `ios/Runner/Info.plist` toma ambos números de Flutter.

Subir el `.ipa` de `build/ios/ipa` con Transporter. También se puede abrir
el archivo de Xcode y elegir **Distribute App → App Store Connect → Upload**:

```bash
open build/ios/archive/Runner.xcarchive
```

Si Xcode requiere revisar la firma:

```bash
open ios/Runner.xcworkspace
```

En Runner → Signing & Capabilities, seleccionar el equipo que corresponde a
esta aplicación. Conservar su Bundle ID.

Después del procesamiento de Apple, seleccionar la compilación 39 en
TestFlight o en la versión 2.6.25 de App Store Connect y enviar a revisión
cuando estén completos los datos de esa versión. El envío del binario no
publica por sí solo la versión en la tienda.

La compilación y la firma iOS no se han ejecutado en este equipo Windows.

Referencias oficiales: [Flutter: publicar iOS](https://docs.flutter.dev/deployment/ios)
y [Apple: cargar compilaciones](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds).
