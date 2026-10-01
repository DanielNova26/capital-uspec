import 'package:cloud_firestore/cloud_firestore.dart';

/// `runTransaction` que deja ver el error real.
///
/// En Flutter web el manejador de la transacción se convierte en una promesa
/// de JavaScript; cualquier excepción de adentro (un `StateError` de una
/// validación, un `permission-denied` de una lectura) sale como un envoltorio
/// genérico: "Dart exception thrown from converted Future. Use the properties
/// 'error'…". Bodega lo vio el 21 sep 2026 en Compras y Admin el 1 oct 2026 al
/// cambiar el rol de Interventoría: no había forma de saber qué faltaba.
///
/// Aquí se guarda el error de adentro y se relanza tal cual afuera. El
/// manejador sigue lanzando, así que la transacción se aborta igual y no
/// escribe nada.
extension TransaccionLegible on FirebaseFirestore {
  Future<T> runTransactionLegible<T>(
    TransactionHandler<T> handler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    Object? fallo;
    StackTrace? traza;
    try {
      return await runTransaction<T>(
        (transaction) async {
          // Cada intento empieza limpio: si uno anterior falló al confirmar
          // y este reintento falla afuera, no se reporta un error viejo.
          fallo = null;
          traza = null;
          try {
            return await handler(transaction);
          } catch (e, s) {
            fallo = e;
            traza = s;
            rethrow;
          }
        },
        timeout: timeout,
        maxAttempts: maxAttempts,
      );
    } catch (e, s) {
      final interno = fallo;
      if (interno != null) Error.throwWithStackTrace(interno, traza ?? s);
      rethrow;
    }
  }
}
