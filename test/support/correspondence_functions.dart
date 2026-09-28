import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';

/// Callable controlado: ninguna prueba alcanza una cuenta ni función real.
class CorrespondenceFunctions extends Fake implements FirebaseFunctions {
  Map<dynamic, dynamic>? response;
  String? deniedCode;
  int calls = 0;
  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) =>
      _Callable(this);
}

class _Callable extends Fake implements HttpsCallable {
  _Callable(this.functions);
  final CorrespondenceFunctions functions;
  @override
  Future<HttpsCallableResult<T>> call<T>([dynamic parameters]) async {
    functions.calls++;
    if (functions.deniedCode != null) {
      throw FirebaseFunctionsException(
        code: functions.deniedCode!,
        message: 'Denegado',
      );
    }
    if (functions.response == null) {
      throw FirebaseFunctionsException(
        code: 'not-found',
        message: 'Callable no disponible',
      );
    }
    return _Result(functions.response as T);
  }
}

class _Result<T> extends Fake implements HttpsCallableResult<T> {
  _Result(this.data);
  @override
  final T data;
}
