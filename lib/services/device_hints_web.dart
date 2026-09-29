// "Client hints" del navegador (Chrome, Edge, Samsung Internet): el modelo
// del celular y la versión real del sistema, que el user agent ya no trae.
// Safari y Firefox no las tienen: queda lo que diga el user agent.
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('navigator')
external JSObject get _navigator;

Future<({String modelo, String version})> pistasDelNavegador() async {
  try {
    final datos = _navigator.getProperty<JSObject?>('userAgentData'.toJS);
    if (datos == null) return (modelo: '', version: '');
    final promesa = datos.callMethod<JSPromise<JSObject>>(
      'getHighEntropyValues'.toJS,
      <JSString>['model'.toJS, 'platformVersion'.toJS].toJS,
    );
    final valores = await promesa.toDart.timeout(const Duration(seconds: 2));
    String leer(String clave) =>
        valores.getProperty<JSString?>(clave.toJS)?.toDart.trim() ?? '';
    return (modelo: leer('model'), version: leer('platformVersion'));
  } catch (_) {
    return (modelo: '', version: '');
  }
}
