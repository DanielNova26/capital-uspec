import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

import 'package:todo/main.dart' show ToDoApp;
import 'package:todo/state/empresa_scope.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const host = String.fromEnvironment('DEMO_HOST', defaultValue: '127.0.0.1');
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: 'demo-local',
      appId: '1:123456789:web:1234567890abcdef',
      messagingSenderId: '123456789',
      projectId: 'demo-capital-servir',
      authDomain: 'demo-capital-servir.firebaseapp.com',
      storageBucket: 'demo-capital-servir.appspot.com',
    ),
  );
  await FirebaseAuth.instance.useAuthEmulator(host, 9099);
  FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
  FirebaseFunctions.instance.useFunctionsEmulator(host, 5001);
  await FirebaseStorage.instance.useStorageEmulator(host, 9199);
  final empresaState = EmpresaState();
  await empresaState.hydrate();
  runApp(EmpresaScope(notifier: empresaState, child: const ToDoApp()));
}
