// lib/services/device_descriptor.dart
//
// Desde qué equipo entró una persona (29 sep 2026): computador, celular o
// tablet, la marca y el modelo del celular, el sistema y, si fue por
// navegador, cuál. Lo guarda la app en cada ingreso (TBL_LOGIN_SESIONES y la
// ficha) y lo muestra Admin › Seguridad.
//
// Aquí solo va la lógica pura (leer el user agent, deducir la marca, armar
// la descripción) para probarla sin dispositivo. La lectura del equipo real
// está en `device_info_reader.dart`.

enum TipoDispositivo {
  computador('Computador'),
  celular('Celular'),
  tablet('Tablet'),
  desconocido('Sin detalle');

  const TipoDispositivo(this.etiqueta);
  final String etiqueta;

  static TipoDispositivo desde(Object? value) => TipoDispositivo.values
      .firstWhere((t) => t.name == value, orElse: () => desconocido);
}

class DispositivoIngreso {
  const DispositivoIngreso({
    required this.tipo,
    this.marca = '',
    this.modelo = '',
    this.sistema = '',
    this.navegador = '',
    this.app = false,
  });

  const DispositivoIngreso.desconocido()
    : tipo = TipoDispositivo.desconocido,
      marca = '',
      modelo = '',
      sistema = '',
      navegador = '',
      app = false;

  final TipoDispositivo tipo;
  final String marca;
  final String modelo;
  final String sistema;

  /// Vacío si entró por la app instalada.
  final String navegador;

  /// App instalada (Android, iOS, escritorio) y no un navegador.
  final bool app;

  bool get esMovil =>
      tipo == TipoDispositivo.celular || tipo == TipoDispositivo.tablet;

  /// "Celular Samsung SM-A515F · Android 14 · App",
  /// "Computador · Windows 11 · Chrome".
  String get descripcion {
    final equipo = <String>[
      tipo.etiqueta,
      if (marca.isNotEmpty) marca,
      if (modelo.isNotEmpty && modelo.toLowerCase() != marca.toLowerCase())
        modelo,
    ].join(' ');
    return [
      equipo,
      if (sistema.isNotEmpty) sistema,
      if (app) 'App' else if (navegador.isNotEmpty) navegador,
    ].join(' · ');
  }

  Map<String, dynamic> toMap() => {
    'tipo': tipo.name,
    'marca': marca,
    'modelo': modelo,
    'sistema': sistema,
    'navegador': navegador,
    'app': app,
    'descripcion': descripcion,
  };

  factory DispositivoIngreso.fromMap(Map<String, dynamic>? data) {
    if (data == null) return const DispositivoIngreso.desconocido();
    String t(String k) => (data[k] ?? '').toString().trim();
    return DispositivoIngreso(
      tipo: TipoDispositivo.desde(data['tipo']),
      marca: t('marca'),
      modelo: t('modelo'),
      sistema: t('sistema'),
      navegador: t('navegador'),
      app: data['app'] == true,
    );
  }
}

String _mayuscula(String value) {
  final v = value.trim();
  if (v.isEmpty) return v;
  return v[0].toUpperCase() + v.substring(1).toLowerCase();
}

/// Marca de un celular por su modelo ("SM-A515F" → Samsung). Vacío si no
/// se reconoce: se muestra el modelo solo.
String marcaDeModelo(String modelo) {
  final m = modelo.trim();
  if (m.isEmpty) return '';
  final reglas = <(RegExp, String)>[
    (RegExp(r'^(iphone|ipad|ipod)', caseSensitive: false), 'Apple'),
    (RegExp(r'^(sm-|gt-|galaxy)', caseSensitive: false), 'Samsung'),
    (RegExp(r'^pixel', caseSensitive: false), 'Google'),
    (
      RegExp(
        r'(redmi|poco|^mi\s|^m2\d{3}|^2\d{3}[0-9a-z]{4,}|xiaomi)',
        caseSensitive: false,
      ),
      'Xiaomi',
    ),
    (RegExp(r'^(moto|xt\d{4})', caseSensitive: false), 'Motorola'),
    (RegExp(r'^cph\d', caseSensitive: false), 'OPPO'),
    (RegExp(r'^rmx\d', caseSensitive: false), 'realme'),
    (RegExp(r'^(v2\d{3}|vivo)', caseSensitive: false), 'vivo'),
    (RegExp(r'^honor', caseSensitive: false), 'Honor'),
    (
      RegExp(r'^(huawei|[a-z]{3}-(l|lx|al|tl)\d)', caseSensitive: false),
      'Huawei',
    ),
    (RegExp(r'^tecno', caseSensitive: false), 'TECNO'),
    (RegExp(r'^infinix', caseSensitive: false), 'Infinix'),
    (RegExp(r'^lm-', caseSensitive: false), 'LG'),
    (RegExp(r'^nokia', caseSensitive: false), 'Nokia'),
    (RegExp(r'^(zte|blade)', caseSensitive: false), 'ZTE'),
    (RegExp(r'^(lenovo|tb-)', caseSensitive: false), 'Lenovo'),
  ];
  for (final (patron, marca) in reglas) {
    if (patron.hasMatch(m)) return marca;
  }
  return '';
}

String _navegadorDe(String ua) {
  if (RegExp(r'Edg(A|iOS)?/').hasMatch(ua)) return 'Edge';
  if (ua.contains('OPR/') || ua.contains('Opera')) return 'Opera';
  if (ua.contains('SamsungBrowser/')) return 'Samsung Internet';
  if (ua.contains('Firefox/') || ua.contains('FxiOS/')) return 'Firefox';
  if (ua.contains('CriOS/') || ua.contains('Chrome/')) return 'Chrome';
  if (ua.contains('Safari/')) return 'Safari';
  return 'Navegador';
}

String _version(String raw) {
  final partes = raw.replaceAll('_', '.').split('.');
  // "17.5.1" → "17.5"; "14.0.0" → "14"
  final limpias = partes.where((p) => p.isNotEmpty).toList();
  if (limpias.isEmpty) return '';
  if (limpias.length == 1 || limpias[1] == '0') return limpias.first;
  return '${limpias[0]}.${limpias[1]}';
}

/// Lee el user agent de un navegador. [modeloPista] y [versionPista] son
/// las "client hints" de Chrome: el user agent de Chrome en Android ya no
/// trae el modelo ("Android 10; K") y la versión del sistema es fija.
DispositivoIngreso dispositivoDesdeUserAgent(
  String userAgent, {
  String modeloPista = '',
  String versionPista = '',
}) {
  final ua = userAgent.trim();
  final navegador = ua.isEmpty ? 'Navegador' : _navegadorDe(ua);
  final pista = modeloPista.trim();

  final ios = RegExp(r'(iPhone|iPad|iPod)[^)]*?OS ([\d_]+)').firstMatch(ua);
  if (ios != null) {
    final equipo = ios.group(1)!;
    return DispositivoIngreso(
      tipo: equipo == 'iPad' ? TipoDispositivo.tablet : TipoDispositivo.celular,
      marca: 'Apple',
      modelo: equipo,
      sistema: 'iOS ${_version(ios.group(2)!)}',
      navegador: navegador,
    );
  }

  final android = RegExp(
    r'Android\s*([\d.]*)\s*;\s*([^;)]*?)(?:\s+Build/[^;)]*)?[;)]',
  ).firstMatch(ua);
  if (ua.contains('Android')) {
    var modelo = android?.group(2)?.trim() ?? '';
    // Chrome recortado: "K" o nada no es un modelo.
    if (modelo.length <= 1 || modelo.toLowerCase() == 'wv') modelo = '';
    if (pista.isNotEmpty) modelo = pista;
    final version = versionPista.isNotEmpty
        ? _version(versionPista)
        : _version(android?.group(1) ?? '');
    return DispositivoIngreso(
      tipo: ua.contains('Mobile')
          ? TipoDispositivo.celular
          : TipoDispositivo.tablet,
      marca: marcaDeModelo(modelo),
      modelo: modelo,
      sistema: version.isEmpty ? 'Android' : 'Android $version',
      navegador: navegador,
    );
  }

  String sistema;
  if (ua.contains('Windows')) {
    // Las client hints distinguen 11 (13 o más) de 10.
    final mayor = int.tryParse(versionPista.split('.').first) ?? 0;
    sistema = versionPista.isEmpty
        ? 'Windows'
        : mayor >= 13
        ? 'Windows 11'
        : 'Windows 10';
  } else if (ua.contains('CrOS')) {
    sistema = 'ChromeOS';
  } else if (ua.contains('Macintosh') || ua.contains('Mac OS X')) {
    sistema = 'macOS';
  } else if (ua.contains('Linux')) {
    sistema = 'Linux';
  } else {
    sistema = '';
  }
  if (ua.isEmpty) {
    return const DispositivoIngreso(
      tipo: TipoDispositivo.desconocido,
      navegador: 'Navegador',
    );
  }
  return DispositivoIngreso(
    tipo: ua.contains('Mobi')
        ? TipoDispositivo.celular
        : TipoDispositivo.computador,
    sistema: sistema,
    navegador: navegador,
  );
}

/// App instalada en Android. [tablet]: pantalla de 600 dp o más.
DispositivoIngreso dispositivoAndroid({
  required String fabricante,
  required String modelo,
  required String version,
  bool tablet = false,
}) {
  final marca = _mayuscula(fabricante);
  var m = modelo.trim();
  // "samsung SM-A515F" trae la marca repetida en algunos equipos.
  if (marca.isNotEmpty && m.toLowerCase().startsWith(marca.toLowerCase())) {
    m = m.substring(marca.length).trim();
  }
  return DispositivoIngreso(
    tipo: tablet ? TipoDispositivo.tablet : TipoDispositivo.celular,
    marca: marca.isNotEmpty ? marca : marcaDeModelo(m),
    modelo: m,
    sistema: version.trim().isEmpty
        ? 'Android'
        : 'Android ${_version(version)}',
    app: true,
  );
}

/// App instalada en iPhone o iPad. [modelo]: "iPhone 15 Pro" o "iPhone".
DispositivoIngreso dispositivoIos({
  required String modelo,
  required String version,
}) {
  final m = modelo.trim().isEmpty ? 'iPhone' : modelo.trim();
  return DispositivoIngreso(
    tipo: m.toLowerCase().startsWith('ipad')
        ? TipoDispositivo.tablet
        : TipoDispositivo.celular,
    marca: 'Apple',
    modelo: m,
    sistema: version.trim().isEmpty ? 'iOS' : 'iOS ${_version(version)}',
    app: true,
  );
}

/// App de escritorio (Windows, macOS, Linux).
DispositivoIngreso dispositivoEscritorio(
  String sistema, {
  String modelo = '',
}) => DispositivoIngreso(
  tipo: TipoDispositivo.computador,
  modelo: modelo.trim(),
  sistema: sistema,
  app: true,
);
