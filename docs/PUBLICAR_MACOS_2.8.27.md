# To-Do Gestión para Mac 2.8.27 (81)

Desde un Mac con Xcode 26.2 o posterior, Flutter y CocoaPods, abre la copia del repositorio
en `main`. Comprueba que Xcode tiene activa la cuenta del equipo Apple
`29TDC266FJ`.

```sh
git pull origin main
xcodebuild -version
flutter doctor -v
flutter pub get --enforce-lockfile
flutter build macos --release --build-name=2.8.27 --build-number=81
```

La compilación genera
`build/macos/Build/Products/Release/capital_uspec.app`. Ábrela en el Mac y
comprueba el inicio de sesión, la empresa activa y Visitas › Ubicaciones.

Para publicar en el Mac App Store, agrega la plataforma macOS al registro
existente de To-Do Gestión en App Store Connect. El destino de escritorio
usa `com.capitaluspec.gestionapp` y el registro Apple activo de Firebase.

```sh
open macos/Runner.xcworkspace
```

En Xcode, selecciona el destino Runner y verifica el equipo, la firma
automática, el identificador de la app y Keychain Sharing en **Signing &
Capabilities**. Define la categoría de la app en **General** y genera el
archivo con **Product → Archive**. En Organizer, selecciona **Validate App**
y luego **Distribute App**. Completa la ficha de macOS en App Store Connect
y envía la compilación 81 a revisión.

- [Compilar y publicar para macOS con Flutter](https://docs.flutter.dev/deployment/macos)
- [Agregar macOS a un registro en App Store Connect](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-platforms/)
