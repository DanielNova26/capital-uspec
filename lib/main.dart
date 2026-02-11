// lib/main.dart
// Arranque de la app + Firebase + App Check + FCM + notificaciones locales.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'firebase_options.dart';
import 'state/empresa_scope.dart';
import 'login/login_screen.dart';
import 'services/notification_service.dart';

/// Clave global de navegación para deep-linking desde notificaciones.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// ===== Handler de mensajes en segundo plano (Android) =====
/// ¡NO lo muevas dentro de una clase!
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Aquí podrías registrar logs o preprocesar 'message.data'
}

Future<void> _initFirebaseAndPushCore() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase base
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // App Check
  // - En debug usa el proveedor "debug" para evitar errores de atestación
  //   al desarrollar en simuladores o sin App Attest configurado.
  // - En release fuerza los proveedores reales (Play Integrity / App Attest)
  //   con fallback a DeviceCheck en iOS para evitar 403 de "attestation failed".
  await FirebaseAppCheck.instance.activate(
    androidProvider:
        kReleaseMode ? AndroidProvider.playIntegrity : AndroidProvider.debug,
    appleProvider: kReleaseMode
        ? AppleProvider.appAttestWithDeviceCheckFallback
        : AppleProvider.debug,
  );

  // NotificationsService maneja: notificaciones locales, FCM foreground,
  // onMessageOpenedApp, getInitialMessage y deep-linking con navigatorKey.
  await NotificationsService.init(navigatorKey: navigatorKey);
}

Future<void> main() async {
  await _initFirebaseAndPushCore();
  final empresaState = EmpresaState();
  await empresaState.hydrate();
  runApp(EmpresaScope(
    notifier: empresaState,
    child: const ToDoApp(),
  ));
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
      title: 'ToDo',
      debugShowCheckedModeBanner: false,

      // 👇 Localización en español
      locale: const Locale('es', 'CO'), // o solo: const Locale('es')
      supportedLocales: const [
        Locale('es', 'CO'),
        Locale('es'),     // fallback
        Locale('en'),     // opcional
      ],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,

      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorSchemeSeed: const Color(0xFF0078D7), // azul del logo
        scaffoldBackgroundColor: const Color(0xFFFFFFFF), // fondo blanco
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0078D7),
          foregroundColor: Colors.white,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ButtonStyle(
            padding: const MaterialStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            ),
            shape: MaterialStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            textStyle: const MaterialStatePropertyAll(
              TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            elevation: const MaterialStatePropertyAll(4),
            shadowColor: MaterialStatePropertyAll(Colors.black.withOpacity(0.25)),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: ButtonStyle(
            padding: const MaterialStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            ),
            shape: MaterialStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            textStyle: const MaterialStatePropertyAll(
              TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: ButtonStyle(
            padding: const MaterialStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            ),
            shape: MaterialStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            side: MaterialStateProperty.resolveWith(
                  (states) => BorderSide(
                color: states.contains(MaterialState.pressed)
                    ? const Color(0xFF005A9E)
                    : const Color(0xFF0078D7),
              ),
            ),
            textStyle: const MaterialStatePropertyAll(
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

      home: const LoginScreen(),
    );
  }
}

/// Alias para tests viejos que referencian `MyApp`
class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => const ToDoApp();
}