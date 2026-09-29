import 'package:flutter_test/flutter_test.dart';
import 'package:todo/services/device_descriptor.dart';

void main() {
  group('navegador (user agent)', () {
    test('Chrome en Android con modelo', () {
      final d = dispositivoDesdeUserAgent(
        'Mozilla/5.0 (Linux; Android 14; SM-S918B) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
      );
      expect(d.tipo, TipoDispositivo.celular);
      expect(d.marca, 'Samsung');
      expect(d.modelo, 'SM-S918B');
      expect(d.sistema, 'Android 14');
      expect(d.navegador, 'Chrome');
      expect(d.app, isFalse);
      expect(d.descripcion, 'Celular Samsung SM-S918B · Android 14 · Chrome');
    });

    test('Chrome recortado ("K") usa las client hints', () {
      const ua =
          'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, '
          'like Gecko) Chrome/125.0.0.0 Mobile Safari/537.36';
      final sinPistas = dispositivoDesdeUserAgent(ua);
      expect(sinPistas.modelo, '');
      expect(sinPistas.descripcion, 'Celular · Android 10 · Chrome');
      final conPistas = dispositivoDesdeUserAgent(
        ua,
        modeloPista: '23021RAAEG',
        versionPista: '13.0.0',
      );
      expect(conPistas.marca, 'Xiaomi');
      expect(conPistas.modelo, '23021RAAEG');
      expect(conPistas.sistema, 'Android 13');
    });

    test('Samsung Internet y tablet Android', () {
      final d = dispositivoDesdeUserAgent(
        'Mozilla/5.0 (Linux; Android 13; SM-X200) AppleWebKit/537.36 '
        '(KHTML, like Gecko) SamsungBrowser/23.0 Chrome/115.0 Safari/537.36',
      );
      expect(d.tipo, TipoDispositivo.tablet);
      expect(d.navegador, 'Samsung Internet');
    });

    test('Safari en iPhone y en iPad', () {
      final iphone = dispositivoDesdeUserAgent(
        'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5_1 like Mac OS X) '
        'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 '
        'Mobile/15E148 Safari/604.1',
      );
      expect(iphone.tipo, TipoDispositivo.celular);
      expect(iphone.marca, 'Apple');
      expect(iphone.sistema, 'iOS 17.5');
      expect(iphone.navegador, 'Safari');
      expect(iphone.descripcion, 'Celular Apple iPhone · iOS 17.5 · Safari');
      final ipad = dispositivoDesdeUserAgent(
        'Mozilla/5.0 (iPad; CPU OS 16_6 like Mac OS X) AppleWebKit/605.1.15 '
        '(KHTML, like Gecko) CriOS/120.0 Mobile/15E148 Safari/604.1',
      );
      expect(ipad.tipo, TipoDispositivo.tablet);
      expect(ipad.navegador, 'Chrome');
    });

    test('computadores: Windows 10/11, macOS, Edge y Firefox', () {
      const windows =
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 Edg/120.0';
      final edge = dispositivoDesdeUserAgent(windows);
      expect(edge.tipo, TipoDispositivo.computador);
      expect(edge.sistema, 'Windows');
      expect(edge.navegador, 'Edge');
      expect(
        dispositivoDesdeUserAgent(windows, versionPista: '15.0.0').sistema,
        'Windows 11',
      );
      expect(
        dispositivoDesdeUserAgent(windows, versionPista: '10.0.0').sistema,
        'Windows 10',
      );
      final mac = dispositivoDesdeUserAgent(
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:121.0) '
        'Gecko/20100101 Firefox/121.0',
      );
      expect(mac.sistema, 'macOS');
      expect(mac.navegador, 'Firefox');
      expect(mac.descripcion, 'Computador · macOS · Firefox');
    });

    test('sin user agent: navegador sin detalle', () {
      final d = dispositivoDesdeUserAgent('');
      expect(d.tipo, TipoDispositivo.desconocido);
      expect(d.navegador, 'Navegador');
    });
  });

  group('app instalada', () {
    test('Android: marca del fabricante y sin repetirla en el modelo', () {
      final d = dispositivoAndroid(
        fabricante: 'samsung',
        modelo: 'SM-A515F',
        version: '13',
      );
      expect(d.descripcion, 'Celular Samsung SM-A515F · Android 13 · App');
      final moto = dispositivoAndroid(
        fabricante: 'motorola',
        modelo: 'motorola edge 40',
        version: '14',
        tablet: true,
      );
      expect(moto.modelo, 'edge 40');
      expect(moto.tipo, TipoDispositivo.tablet);
    });

    test('iPhone con nombre comercial', () {
      final d = dispositivoIos(modelo: 'iPhone 15 Pro', version: '17.4.1');
      expect(d.descripcion, 'Celular Apple iPhone 15 Pro · iOS 17.4 · App');
      expect(
        dispositivoIos(modelo: 'iPad Air', version: '17').tipo,
        TipoDispositivo.tablet,
      );
    });

    test('escritorio', () {
      expect(
        dispositivoEscritorio('Windows').descripcion,
        'Computador · Windows · App',
      );
    });
  });

  test('marca por modelo', () {
    expect(marcaDeModelo('SM-A155M'), 'Samsung');
    expect(marcaDeModelo('Pixel 8'), 'Google');
    expect(marcaDeModelo('moto g84 5G'), 'Motorola');
    expect(marcaDeModelo('Redmi Note 13'), 'Xiaomi');
    expect(marcaDeModelo('CPH2591'), 'OPPO');
    expect(marcaDeModelo('RMX3710'), 'realme');
    expect(marcaDeModelo('MAR-LX3A'), 'Huawei');
    expect(marcaDeModelo('TECNO KI5k'), 'TECNO');
    expect(marcaDeModelo('ZZ-123'), '');
  });

  test('se guarda y se lee igual', () {
    final d = dispositivoAndroid(
      fabricante: 'Xiaomi',
      modelo: 'Redmi Note 12',
      version: '13',
    );
    final map = d.toMap();
    expect(map['descripcion'], d.descripcion);
    final leido = DispositivoIngreso.fromMap(map);
    expect(leido.tipo, TipoDispositivo.celular);
    expect(leido.descripcion, d.descripcion);
    expect(DispositivoIngreso.fromMap(null).tipo, TipoDispositivo.desconocido);
    expect(
      DispositivoIngreso.fromMap({'tipo': 'nave'}).tipo,
      TipoDispositivo.desconocido,
    );
  });
}
