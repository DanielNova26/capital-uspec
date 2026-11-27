# iPhone 2.8.46 (100): App Check y actualización de Pods

Desde la raíz de `capital-uspec` en el Mac, ejecutar en orden. Si un paso
falla, detenerse y conservar el error completo antes de abrir un archivo anterior.

```bash
git pull origin main
flutter pub get --enforce-lockfile
cd ios
pod update --repo-update
cd ..
```

Después de que CocoaPods termine correctamente:

```bash
flutter build ipa --release --no-pub --build-name=2.8.46 --build-number=100
```

Cuando se genere el archivo nuevo:

```bash
open build/ios/archive/Runner.xcarchive
```

Seleccionar **2.8.46 (100)** en Organizer y seguir
**Distribute App → App Store Connect → Upload**. Se conservan el equipo Apple
`29TDC266FJ`, el Bundle ID `com.capitaluspec.gestionapp` y el mínimo iOS 15.5.

## Motivo del ajuste

`firebase_core 4.15.2` selecciona Firebase Apple SDK 12.19.3. El plugin
`firebase_app_check 0.4.7` pedía directamente `FirebaseAppCheck ~> 12.19.3`,
pero el pod independiente se publica como 12.19.0 (iOS mínimo 15.0).
`firebase_app_check 0.4.9` pide `Firebase/AppCheck ~> 12.19.3`; ese subspec
oficial selecciona `FirebaseAppCheck ~> 12.19.0`. El mínimo del proyecto
ya cubre ambos requisitos. Se actualizó solo ese paquete en `pubspec.lock`.

El lock nativo de iOS del repositorio aún fija FlutterFire 3.x y Firebase
11.13.0. `pod update --repo-update` debe resolver los Pods para los plugins
fijados actualmente en Dart y generar el lock correcto en macOS. Ese lock debe
revisarse y sincronizarse después de una compilación correcta; no se editó a
mano desde Windows.

Validado en Windows: dependencias resueltas con un único cambio, podspec
oficial compatible y análisis de `lib/main.dart` sin incidencias. La fase de
enlaces de plugins de `flutter pub upgrade` terminó con el requisito de
Developer Mode para symlinks en Windows; no se cambió esa configuración.
No se ejecutaron CocoaPods/Xcode ni se generó un IPA desde este equipo.

Fuentes: [plugin App Check 0.4.9](https://github.com/firebase/flutterfire/blob/firebase_app_check-v0.4.9/packages/firebase_app_check/firebase_app_check/ios/firebase_app_check.podspec),
[subspec Firebase 12.19.3](https://github.com/firebase/firebase-ios-sdk/blob/12.19.3/Firebase.podspec),
[pod App Check](https://github.com/firebase/firebase-ios-sdk/blob/12.19.3/FirebaseAppCheck.podspec),
[CocoaPods: install y update](https://guides.cocoapods.org/using/pod-install-vs-update.html).
