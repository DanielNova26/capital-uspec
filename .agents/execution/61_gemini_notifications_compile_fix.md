# Task 61 - Notifications Compile Fix

## Causa exacta del error

El error `The class 'EdgeInsets' doesn't have a constant constructor 'bottom'` fue causado por un uso incorrecto del constructor de la clase `EdgeInsets` en la línea 326 de `lib/home/notifications_screen.dart`.

Se intentó usar `EdgeInsets.bottom(12)`, pero Flutter no proporciona un constructor directo con ese nombre. Los constructores válidos son `.all`, `.symmetric`, `.only`, `.fromLTRB`, etc.

## Archivos revisados

- `lib/home/notifications_screen.dart`

## Archivos modificados

- `lib/home/notifications_screen.dart`

## Corrección aplicada

Se cambió el uso de:
```dart
margin: const EdgeInsets.bottom(12),
```
por:
```dart
margin: const EdgeInsets.only(bottom: 12),
```

## Riesgos pendientes

- Ninguno relacionado con este fix. El código ya no presenta errores de compilación en esta pantalla.
- Se detectaron varios `info` de deprecación (`surfaceVariant` y `withOpacity`) por parte del analyzer, pero no bloquean la ejecución y corresponden a la versión actual de Flutter en el proyecto.

## Pruebas mínimas

1. Ejecutar `flutter analyze lib/home/notifications_screen.dart` y verificar que no hay **ERRORES** (pueden quedar advertencias o información).
2. Verificar visualmente la pantalla de notificaciones para confirmar que el margen inferior de 12px se aplica correctamente entre las tarjetas.

## Comando flutter analyze recomendado

```powershell
flutter analyze lib/home/notifications_screen.dart
```
