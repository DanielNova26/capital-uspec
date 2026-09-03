// lib/main.dart
// Arranque de la app + Firebase + App Check + FCM + notificaciones locales.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'firebase_options.dart';
import 'state/empresa_scope.dart';
import 'login/auth_gate.dart';
import 'services/notification_service.dart';
import 'theme/app_scroll_behavior.dart';

/// Clave global de navegación para deep-linking desde notificaciones.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// ===== Handler de mensajes en segundo plano (Android) =====
/// ¡NO lo muevas dentro de una clase!
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Aquí podrías registrar logs o preprocesar 'message.data'
}

/// Arranque de servicios. Nada de lo que hay aquí puede impedir que la app
/// pinte su primer frame.
///
/// Antes `main()` hacía `await` de todo esto sin protección y llamaba a
/// `runApp()` al final: cualquier fallo dejaba la pantalla en blanco para
/// siempre, sin mensaje ni forma de salir. Eso fue exactamente lo que pasó en
/// la 2.4.0 de App Store: el entitlement de APNs decía `development` en un
/// build de producción, `FirebaseMessaging.getToken()` se quedó esperando un
/// token que nunca iba a llegar, y la app nunca arrancó.
///
/// Ahora cada pieza se aísla y las notificaciones se inicializan DESPUÉS de
/// `runApp()`: si algo falla, se pierde esa función concreta, no la app.
Future<void> _initFirebaseAndPushCore() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Android 15+ dibuja edge-to-edge de forma obligatoria cuando targetSdk es
  // 35 o superior. Se declara también desde Flutter para que el mismo contrato
  // se pruebe en versiones anteriores de Android y MediaQuery exponga siempre
  // los insets correctos a Scaffold/SafeArea.
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  // Firebase base
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // App Check
  // - En debug usa el proveedor "debug" para evitar errores de atestación
  //   al desarrollar en simuladores o sin App Attest configurado.
  // - En release fuerza los proveedores reales (Play Integrity / App Attest)
  //   con fallback a DeviceCheck en iOS para evitar 403 de "attestation failed".
  // En web se omite App Check (requiere reCAPTCHA site key en producción).
  if (!kIsWeb) {
    await FirebaseAppCheck.instance.activate(
      providerAndroid: kReleaseMode
          ? const AndroidPlayIntegrityProvider()
          : const AndroidDebugProvider(),
      providerApple: kReleaseMode
          ? const AppleAppAttestWithDeviceCheckFallbackProvider()
          : const AppleDebugProvider(),
    );
  }
}

Future<void> main() async {
  // Firebase es imprescindible, pero ni siquiera él puede dejar la pantalla en
  // blanco: si falla, la app abre igual y el usuario ve el error al intentar
  // entrar, que es información mucho más útil que un rectángulo vacío.
  try {
    await _initFirebaseAndPushCore();
  } catch (e, s) {
    debugPrint('[main] fallo al inicializar Firebase/App Check: $e\n$s');
  }

  final empresaState = EmpresaState();
  try {
    await empresaState.hydrate();
  } catch (e) {
    debugPrint('[main] fallo al hidratar la empresa activa: $e');
  }

  runApp(EmpresaScope(notifier: empresaState, child: const ToDoApp()));

  // Notificaciones DESPUÉS de runApp y sin await: piden permisos al sistema y
  // esperan el token de APNs, dos cosas que pueden tardar o no llegar nunca.
  // Ninguna justifica retrasar el arranque.
  if (!kIsWeb) {
    unawaited(
      NotificationsService.init(navigatorKey: navigatorKey).catchError((
        Object e,
      ) {
        debugPrint('[main] fallo al inicializar notificaciones: $e');
      }),
    );
  }
}

class _FadePageTransitionsBuilder extends PageTransitionsBuilder {
  const _FadePageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      child: child,
    );
  }
}

class ToDoApp extends StatelessWidget {
  const ToDoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'To-Do',
      debugShowCheckedModeBanner: false,

      // Barra de scroll en las tablas horizontales y arrastre con el mouse.
      scrollBehavior: const AppScrollBehavior(),

      // 👇 Localización en español
      locale: const Locale('es', 'CO'), // o solo: const Locale('es')
      supportedLocales: const [
        Locale('es', 'CO'),
        Locale('es'), // fallback
        Locale('en'), // opcional
      ],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,

      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scrollbarTheme: kAppScrollbarTheme,
        colorSchemeSeed: const Color(0xFF0078D7), // azul del logo
        scaffoldBackgroundColor: const Color(0xFFFFFFFF), // fondo blanco
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0078D7),
          foregroundColor: Colors.white,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ButtonStyle(
            padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            ),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            textStyle: const WidgetStatePropertyAll(
              TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            elevation: const WidgetStatePropertyAll(4),
            shadowColor: WidgetStatePropertyAll(
              Colors.black.withValues(alpha: 0.25),
            ),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: ButtonStyle(
            padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            ),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            textStyle: const WidgetStatePropertyAll(
              TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: ButtonStyle(
            padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            ),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            side: WidgetStateProperty.resolveWith(
              (states) => BorderSide(
                color: states.contains(WidgetState.pressed)
                    ? const Color(0xFF005A9E)
                    : const Color(0xFF0078D7),
              ),
            ),
            textStyle: const WidgetStatePropertyAll(
              TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
          ),
        ),
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: _FadePageTransitionsBuilder(),
            TargetPlatform.iOS: _FadePageTransitionsBuilder(),
            TargetPlatform.macOS: _FadePageTransitionsBuilder(),
            TargetPlatform.windows: _FadePageTransitionsBuilder(),
            TargetPlatform.linux: _FadePageTransitionsBuilder(),
          },
        ),
      ),

      // (Opcional) darkTheme si quieres que se adapte al sistema

      // darkTheme: ThemeData(
      //   useMaterial3: true,
      //   brightness: Brightness.dark,
      //   colorSchemeSeed: const Color(0xFF0078D7),
      // ),
      home: const AuthGate(),
    );
  }
}

/// Alias para tests viejos que referencian `MyApp`
class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => const ToDoApp();
}
