// Modo sin conexión de Visitas (15 oct 2026).
//
// En cárceles y otros centros no dejan entrar equipos con internet. La visita
// se diligencia igual:
//  - Las respuestas, tablas, firmas y el inicio se escriben en Firestore, que
//    en Android e iOS guarda en el equipo lo que no puede enviar y lo sube solo
//    cuando vuelve la conexión (`VisitasService._local` evita que la pantalla
//    se quede esperando la confirmación del servidor).
//  - Storage no hace eso: las fotos se guardan aquí, en el equipo, con la marca
//    de agua ya puesta (hora y lugar del momento), y se suben al tocar
//    «Cargar visita» cuando hay internet.
//  - Cerrar la visita exige conexión y que no queden fotos pendientes.
//
// Requisito: abrir la visita una vez con internet antes de entrar al centro,
// para que Firestore tenga en el equipo la visita, el formato y la ubicación.
// En web no hay modo sin conexión.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Dónde va la foto cuando se carga: la respuesta de un ítem, la fila de una
/// tabla o las evidencias adicionales de la visita.
const String kFotoDestinoItem = 'item';
const String kFotoDestinoFila = 'fila';
const String kFotoDestinoAdicional = 'adicional';

class FotoPendiente {
  final String id;
  final String visitaId;
  final String empresaId;
  final String destino;

  /// Ítem (destino `item`) o `tabla_fila` para el nombre de carpeta en Storage.
  final String itemId;
  final String tablaId;
  final String filaId;
  final String nombre;
  final String descripcion;
  final bool conMarca;
  final int creadaMs;

  /// Archivo con los bytes de la foto, ya con marca de agua.
  final String archivo;

  const FotoPendiente({
    required this.id,
    required this.visitaId,
    required this.empresaId,
    required this.destino,
    required this.nombre,
    required this.archivo,
    required this.creadaMs,
    this.itemId = '',
    this.tablaId = '',
    this.filaId = '',
    this.descripcion = '',
    this.conMarca = false,
  });

  /// Carpeta de Storage: la misma que usa la subida en línea.
  String get carpeta => switch (destino) {
    kFotoDestinoFila => '${tablaId}_$filaId',
    kFotoDestinoAdicional => 'adicionales',
    _ => itemId,
  };

  Map<String, dynamic> toMap() => {
    'id': id,
    'visitaId': visitaId,
    'empresaId': empresaId,
    'destino': destino,
    'itemId': itemId,
    'tablaId': tablaId,
    'filaId': filaId,
    'nombre': nombre,
    'descripcion': descripcion,
    'conMarca': conMarca,
    'creadaMs': creadaMs,
    'archivo': archivo,
  };

  factory FotoPendiente.fromMap(Map<String, dynamic> d) => FotoPendiente(
    id: (d['id'] ?? '').toString(),
    visitaId: (d['visitaId'] ?? '').toString(),
    empresaId: (d['empresaId'] ?? '').toString(),
    destino: (d['destino'] ?? kFotoDestinoItem).toString(),
    itemId: (d['itemId'] ?? '').toString(),
    tablaId: (d['tablaId'] ?? '').toString(),
    filaId: (d['filaId'] ?? '').toString(),
    nombre: (d['nombre'] ?? 'foto.jpg').toString(),
    descripcion: (d['descripcion'] ?? '').toString(),
    conMarca: d['conMarca'] == true,
    creadaMs: (d['creadaMs'] as num?)?.toInt() ?? 0,
    archivo: (d['archivo'] ?? '').toString(),
  );
}

/// Estado de conexión y cola de fotos pendientes. Una sola instancia: la
/// pantalla de la visita y el servicio comparten lo mismo.
class VisitasOffline extends ChangeNotifier {
  VisitasOffline._();
  static final VisitasOffline instance = VisitasOffline._();

  static const _clave = 'visitas_fotos_pendientes_v1';

  /// En web no se guarda nada en el equipo: sin conexión no se trabaja.
  static bool get disponible => !kIsWeb;

  bool _conectado = true;
  bool get conectado => _conectado;

  List<FotoPendiente> _pendientes = const [];
  List<FotoPendiente> get pendientes => _pendientes;
  List<FotoPendiente> de(String visitaId) => [
    for (final p in _pendientes)
      if (p.visitaId == visitaId) p,
  ];

  Timer? _timer;
  int _observadores = 0;
  bool _cargada = false;

  /// Empieza a vigilar la conexión mientras haya una pantalla de visita
  /// abierta. Se llama en `initState` y se cierra con [dejarDeVigilar].
  Future<void> vigilar() async {
    _observadores++;
    await cargar();
    await comprobar();
    if (_observadores == 0) return;
    _timer ??= Timer.periodic(const Duration(seconds: 12), (_) => comprobar());
  }

  void dejarDeVigilar() {
    if (_observadores > 0) _observadores--;
    if (_observadores == 0) {
      _timer?.cancel();
      _timer = null;
    }
  }

  /// ¿Hay internet ahora? Resuelve el dominio de Firebase Storage: si no
  /// resuelve, no se puede cargar nada. Actualiza [conectado].
  Future<bool> hayConexion() => comprobar();

  Future<bool> comprobar() async {
    var ok = true;
    if (disponible) {
      try {
        final r = await InternetAddress.lookup(
          'firebasestorage.googleapis.com',
        ).timeout(const Duration(seconds: 4));
        ok = r.isNotEmpty && r.first.rawAddress.isNotEmpty;
      } catch (_) {
        ok = false;
      }
    }
    if (ok != _conectado) {
      _conectado = ok;
      notifyListeners();
    }
    return ok;
  }

  Future<void> cargar() async {
    if (_cargada || !disponible) return;
    _cargada = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_clave);
      if (raw == null || raw.isEmpty) return;
      final lista = jsonDecode(raw) as List;
      _pendientes = [
        for (final m in lista)
          if (m is Map) FotoPendiente.fromMap(Map<String, dynamic>.from(m)),
      ];
      notifyListeners();
    } catch (_) {
      // Un registro dañado no debe impedir abrir la visita.
    }
  }

  Future<void> _persistir() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _clave,
      jsonEncode([for (final p in _pendientes) p.toMap()]),
    );
  }

  /// Guarda la foto en el equipo hasta que haya internet.
  Future<FotoPendiente> guardar({
    required String visitaId,
    required String empresaId,
    required String destino,
    required Uint8List bytes,
    required String nombre,
    String itemId = '',
    String tablaId = '',
    String filaId = '',
    String descripcion = '',
    bool conMarca = false,
  }) async {
    await cargar();
    final dir = await getApplicationDocumentsDirectory();
    final carpeta = Directory('${dir.path}/visitas_pendientes');
    if (!await carpeta.exists()) await carpeta.create(recursive: true);
    final ms = DateTime.now().millisecondsSinceEpoch;
    final id = '${visitaId}_$ms';
    final archivo = File('${carpeta.path}/$id.jpg');
    await archivo.writeAsBytes(bytes, flush: true);
    final p = FotoPendiente(
      id: id,
      visitaId: visitaId,
      empresaId: empresaId,
      destino: destino,
      itemId: itemId,
      tablaId: tablaId,
      filaId: filaId,
      nombre: nombre,
      descripcion: descripcion,
      conMarca: conMarca,
      creadaMs: ms,
      archivo: archivo.path,
    );
    _pendientes = [..._pendientes, p];
    await _persistir();
    notifyListeners();
    return p;
  }

  Future<Uint8List?> bytesDe(FotoPendiente p) async {
    try {
      return await File(p.archivo).readAsBytes();
    } catch (_) {
      return null;
    }
  }

  /// Quita la foto de la cola (ya se subió) y borra el archivo.
  Future<void> quitar(FotoPendiente p) async {
    _pendientes = [
      for (final x in _pendientes)
        if (x.id != p.id) x,
    ];
    await _persistir();
    try {
      final f = File(p.archivo);
      if (await f.exists()) await f.delete();
    } catch (_) {}
    notifyListeners();
  }

  /// ¿El error de red es de falta de conexión (y no de permisos)?
  static bool esErrorDeRed(Object e) {
    final m = e.toString().toLowerCase();
    return e is SocketException ||
        m.contains('network') ||
        m.contains('unavailable') ||
        m.contains('retry-limit') ||
        m.contains('socketexception') ||
        m.contains('failed host lookup');
  }
}
