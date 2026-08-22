// lib/rutas/rutas_conductor_screen.dart
//
// Pantalla MÓVIL del conductor. Diseñada para usuarios poco técnicos:
//   - SIN mapa (los confunde).
//   - Ruta del día, establecimiento (por GPS) y comida (por hora) autodetectados.
//   - Un botón grande para tomar la foto → directo a la cámara.
//   - Galería de las fotos de hoy para previsualizar / repetir / ver estado.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:todo/services/company_branding_service.dart';

import 'rutas_image_analysis.dart';
import 'rutas_logic.dart';
import 'rutas_models.dart';
import 'rutas_service.dart';
import 'rutas_watermark.dart';

const Color _kRutasColor = Color(0xFF15803D);

Color _colorComida(String comida) {
  switch (comida) {
    case kComidaDesayuno:
      return const Color(0xFF16A34A);
    case kComidaAlmuerzo:
      return const Color(0xFFF59E0B);
    case kComidaCena:
      return const Color(0xFF2563EB);
    default:
      return _kRutasColor;
  }
}

class ConductorHomeScreen extends StatefulWidget {
  final String userId;
  final String empresaId;

  const ConductorHomeScreen({
    super.key,
    required this.userId,
    required this.empresaId,
  });

  @override
  State<ConductorHomeScreen> createState() => _ConductorHomeScreenState();
}

class _ConductorHomeScreenState extends State<ConductorHomeScreen>
    with WidgetsBindingObserver {
  final RutasService _service = RutasService();
  final ImagePicker _picker = ImagePicker();

  bool _loading = true;
  String? _error;

  RutaConfigDoc? _config;
  RutaAsignacionDoc? _asig;
  RutaDoc? _ruta;

  int _stopIndex = 0;
  String _meal = kComidaDesayuno;

  double? _lat;
  double? _lng;
  String _addr = '';

  Set<String> _comidasHechasPunto = {};
  bool _subiendo = false;
  bool _ubicando = false;
  StreamSubscription<Position>? _trackingSub;
  DateTime? _lastTrackingReportAt;
  bool _trackingActivo = false;
  Future<Uint8List?>? _logoEmpresaFuture;
  Uint8List? _logoEmpresaBytes;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _trackingSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_loading && _ruta != null) {
      _ubicar();
      _iniciarSeguimientoActivo();
    }
  }

  RutaStop? get _stop {
    final ruta = _ruta;
    if (ruta == null || ruta.stops.isEmpty) return null;
    if (_stopIndex < 0 || _stopIndex >= ruta.stops.length) return null;
    return ruta.stops[_stopIndex];
  }

  int get _menuNumero {
    final cfg = _config;
    if (cfg == null) return 0;
    return RutasLogic.menuNumeroParaFecha(
      DateTime.now(),
      cfg.cicloFechaBase.toDate(),
    );
  }

  Future<void> _init() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cfg = await _service.getConfig(widget.empresaId);
      final asig = await _service.asignacionVigenteDeConductor(
        widget.empresaId,
        widget.userId,
      );
      if (asig == null) {
        setState(() {
          _config = cfg;
          _loading = false;
          _error =
              'No tienes una ruta asignada para hoy.\nPide al administrador que '
              'te asigne una ruta.';
        });
        return;
      }
      final ruta = await _service.getRuta(asig.rutaId);
      if (ruta == null) {
        setState(() {
          _loading = false;
          _error = 'La ruta asignada ya no existe. Avisa al administrador.';
        });
        return;
      }
      _config = cfg;
      _asig = asig;
      _ruta = ruta;
      _meal = RutasLogic.comidaPorHora(DateTime.now(), cfg);
      setState(() => _loading = false);
      // El conductor no necesita pulsar ubicación: al entrar se obtiene una
      // posición fresca, se selecciona el establecimiento y se reporta al mapa.
      await _ubicar();
      await _iniciarSeguimientoActivo();
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'No se pudo cargar tu ruta: $e';
      });
    }
  }

  Future<void> _ubicar() async {
    final ruta = _ruta;
    if (ruta == null) return;
    setState(() => _ubicando = true);
    try {
      final pos = await _posicionActual();
      String addr = '';
      if (pos != null) {
        addr = await _direccionDe(pos.latitude, pos.longitude);
      }
      var idx = _stopIndex;
      if (pos != null) {
        final nearest = RutasLogic.indiceStopMasCercano(
          ruta.stops,
          pos.latitude,
          pos.longitude,
        );
        if (nearest >= 0) idx = nearest;
      }
      if (!mounted) return;
      setState(() {
        _lat = pos?.latitude;
        _lng = pos?.longitude;
        _addr = addr;
        _stopIndex = idx;
      });
      if (pos != null) {
        final reportStop = idx >= 0 && idx < ruta.stops.length
            ? ruta.stops[idx]
            : null;
        await _reportarUbicacion(pos, reportStop, addr);
      }
      await _recargarComidasPunto();
    } finally {
      if (mounted) setState(() => _ubicando = false);
    }
  }

  Future<Position?> _posicionActual() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        await Geolocator.openLocationSettings();
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return null;
      }
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _iniciarSeguimientoActivo() async {
    if (_trackingSub != null || _ruta == null) return;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }

      const settings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 80,
      );
      _trackingSub = Geolocator.getPositionStream(locationSettings: settings)
          .listen(
            (pos) async {
              final last = _lastTrackingReportAt;
              final now = DateTime.now();
              if (last != null && now.difference(last).inSeconds < 30) return;
              _lastTrackingReportAt = now;
              await _procesarUbicacionSeguimiento(pos);
            },
            onError: (_) {
              if (mounted) setState(() => _trackingActivo = false);
            },
          );
      if (mounted) setState(() => _trackingActivo = true);
    } catch (_) {
      if (mounted) setState(() => _trackingActivo = false);
    }
  }

  Future<void> _procesarUbicacionSeguimiento(Position pos) async {
    final ruta = _ruta;
    if (ruta == null) return;
    var idx = _stopIndex;
    final nearest = RutasLogic.indiceStopMasCercano(
      ruta.stops,
      pos.latitude,
      pos.longitude,
    );
    if (nearest >= 0) idx = nearest;
    final stop = idx >= 0 && idx < ruta.stops.length ? ruta.stops[idx] : null;
    if (mounted) {
      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
        _stopIndex = idx;
      });
    }
    await _reportarUbicacion(pos, stop, _addr);
  }

  Future<String> _direccionDe(double lat, double lng) async {
    try {
      final places = await geocoding.placemarkFromCoordinates(lat, lng);
      if (places.isEmpty) return '';
      final p = places.first;
      return [
        p.street,
        p.subLocality,
        p.locality,
      ].where((e) => (e ?? '').trim().isNotEmpty).join(', ');
    } catch (_) {
      return '';
    }
  }

  Future<void> _reportarUbicacion(
    Position pos,
    RutaStop? stop,
    String direccion,
  ) async {
    try {
      await _service.actualizarUbicacionConductor(
        empresaId: widget.empresaId,
        userId: widget.userId,
        lat: pos.latitude,
        lng: pos.longitude,
        precisionMetros: pos.accuracy,
        direccion: direccion,
        ruta: _ruta,
        asignacion: _asig,
        parada: stop,
      );
    } catch (_) {}
  }

  Future<bool> _recargarComidasPunto() async {
    final ruta = _ruta;
    final stop = _stop;
    if (ruta == null || stop == null) return false;
    try {
      final hechas = await _service.comidasNoRechazadasDelPunto(
        empresaId: widget.empresaId,
        rutaId: ruta.id,
        fecha: RutasLogic.fechaKey(DateTime.now()),
        paradaNombre: stop.nombre,
      );
      if (mounted) setState(() => _comidasHechasPunto = hechas);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _cambiarPunto() async {
    final ruta = _ruta;
    if (ruta == null) return;
    final idx = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                'Selecciona el establecimiento',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            for (var i = 0; i < ruta.stops.length; i++)
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: i == _stopIndex
                      ? _kRutasColor
                      : Colors.grey.shade300,
                  foregroundColor: i == _stopIndex
                      ? Colors.white
                      : Colors.black54,
                  child: Text('${i + 1}'),
                ),
                title: Text(
                  ruta.stops[i].nombre,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(ruta.stops[i].direccionVisible),
                onTap: () => Navigator.pop(ctx, i),
              ),
          ],
        ),
      ),
    );
    if (idx == null) return;
    setState(() => _stopIndex = idx);
    await _recargarComidasPunto();
  }

  Future<void> _tomarFoto({String? comidaForzada}) async {
    final ruta = _ruta;
    final stop = _stop;
    final cfg = _config;
    if (ruta == null || stop == null || cfg == null) return;

    final comida = comidaForzada ?? _meal;

    // Validación fresca: evita abrir la cámara para una comida ya pendiente o
    // aprobada cuando Calidad acaba de rechazar otra comida del mismo punto.
    if (!await _recargarComidasPunto()) {
      _snack('No se pudo validar las fotos existentes. Intenta nuevamente.');
      return;
    }
    if (!mounted) return;

    // Secuencia por establecimiento: desayuno → almuerzo → cena.
    if (!RutasLogic.puedeTomarComida(
      comida: comida,
      comidasNoRechazadasDelPunto: _comidasHechasPunto,
    )) {
      _snack(
        RutasLogic.motivoBloqueoComida(
          comida: comida,
          comidasNoRechazadasDelPunto: _comidasHechasPunto,
        ),
      );
      return;
    }

    // Posición fresca al momento de la foto (más confiable que al abrir).
    final pos = await _posicionActual();
    if (pos != null) {
      _lat = pos.latitude;
      _lng = pos.longitude;
      _addr = await _direccionDe(pos.latitude, pos.longitude);
      await _reportarUbicacion(pos, stop, _addr);
    }

    final XFile? shot;
    try {
      shot = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 86,
      );
    } catch (e) {
      _snack('No se pudo abrir la cámara: $e');
      return;
    }
    if (shot == null) return;

    final bytes = await shot.readAsBytes();
    if (!mounted) return;

    final turns = await _previewAntesDeSubir(bytes, comida);
    if (turns == null) return; // Repetir o cancelado

    await _generarYsubir(
      bytes: bytes,
      comida: comida,
      stop: stop,
      ruta: ruta,
      quarterTurns: turns,
    );
  }

  /// Vista previa antes de subir. Devuelve los quarterTurns con que se debe
  /// rotar la foto (para que quede HORIZONTAL) o null si el conductor cancela.
  /// La foto vertical arranca ya girada; el botón "Rotar" ajusta el sentido
  /// (incluye el caso "al revés" que la geometría no detecta sola). En paralelo
  /// analiza la calidad EN EL DISPOSITIVO (no agrega tiempo de subida) y avisa
  /// si se ve oscura/borrosa/tapada, sin bloquear.
  Future<int?> _previewAntesDeSubir(Uint8List bytes, String comida) async {
    var quarterTurns = await quarterTurnsParaHorizontal(bytes);
    if (!mounted) return null;
    final calidadFuture = compute(analizarCalidadFoto, bytes);
    return showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('$comida · ${_stop?.nombre ?? ''}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(ctx).size.height * 0.5,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: RotatedBox(
                      quarterTurns: quarterTurns,
                      child: Image.memory(bytes, fit: BoxFit.contain),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _calidadBanner(calidadFuture),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Expanded(child: Text('¿Se ve derecha y horizontal?')),
                    IconButton.filledTonal(
                      tooltip: 'Rotar',
                      onPressed: () =>
                          setLocal(() => quarterTurns = (quarterTurns + 1) % 4),
                      icon: const Icon(Icons.rotate_90_degrees_cw),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () => Navigator.pop(ctx, null),
              icon: const Icon(Icons.replay),
              label: const Text('Repetir'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: _kRutasColor),
              onPressed: () => Navigator.pop(ctx, quarterTurns),
              icon: const Icon(Icons.cloud_upload),
              label: const Text('Usar y subir'),
            ),
          ],
        ),
      ),
    );
  }

  /// Banner de calidad on-device: spinner mientras analiza, luego "se ve bien"
  /// o una advertencia (no bloquea la subida).
  Widget _calidadBanner(Future<List<String>> future) {
    return FutureBuilder<List<String>>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 8),
              Text('Analizando foto…'),
            ],
          );
        }
        final alertas = snap.data ?? const <String>[];
        if (alertas.isEmpty) {
          return const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 18),
              SizedBox(width: 8),
              Expanded(child: Text('La foto se ve bien.')),
            ],
          );
        }
        final msg = alertas.map(_calidadLabel).join(' · ');
        return Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.orange.shade200),
          ),
          child: Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: Colors.orange.shade800,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Revisa la foto: $msg',
                  style: TextStyle(color: Colors.orange.shade900),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _calidadLabel(String code) {
    switch (code) {
      case 'oscura':
        return 'muy oscura';
      case 'quemada':
        return 'muy clara';
      case 'plana':
        return 'tapada o sin detalle';
      case 'borrosa':
        return 'posiblemente borrosa';
      default:
        return code;
    }
  }

  Future<void> _generarYsubir({
    required Uint8List bytes,
    required String comida,
    required RutaStop stop,
    required RutaDoc ruta,
    int quarterTurns = 0,
  }) async {
    setState(() => _subiendo = true);
    try {
      final logo = await _cargarLogoEmpresa();

      final asig = _asig;
      final ahora = DateTime.now();
      final coords = (_lat == null || _lng == null)
          ? '—'
          : '${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}';

      final lineas = <String>[
        '${ruta.codigo} • ${DateFormat('dd/MM/yyyy HH:mm').format(ahora)}',
        'Establecimiento: ${stop.nombre}',
        'Comida: $comida · Menú $_menuNumero',
        if ((asig?.conductorNombre ?? '').isNotEmpty)
          'Conductor: ${asig!.conductorNombre}',
        if ((asig?.ayudanteNombre ?? '').isNotEmpty)
          'Ayudante: ${asig!.ayudanteNombre}',
        if ((asig?.ayudante2Nombre ?? '').isNotEmpty)
          'Segundo ayudante: ${asig!.ayudante2Nombre}',
        if ((asig?.vehiculo ?? '').isNotEmpty) 'Vehículo: ${asig!.vehiculo}',
        'GPS: $coords',
        if (_addr.isNotEmpty) _addr,
      ];

      final imagen = await generarEvidenciaConMarca(
        fotoBytes: bytes,
        lineas: lineas,
        logoBytes: logo,
        quarterTurns: quarterTurns,
      );

      await _service.subirEvidencia(
        empresaId: widget.empresaId,
        ruta: ruta,
        parada: stop,
        comida: comida,
        menuNumero: _menuNumero,
        asignacion: asig,
        capturaLat: _lat,
        capturaLng: _lng,
        capturaTexto: _addr,
        imagenBytes: imagen.full,
        thumbBytes: imagen.thumb,
        createdBy: widget.userId,
      );

      await _recargarComidasPunto();
      if (mounted) {
        _snack('✅ Evidencia subida: ${stop.nombre} · $comida');
      }
    } catch (e) {
      _snack('No se pudo subir la evidencia: $e');
    } finally {
      if (mounted) setState(() => _subiendo = false);
    }
  }

  Future<Uint8List?> _cargarLogoEmpresa() {
    final cached = _logoEmpresaBytes;
    if (cached != null && cached.isNotEmpty) return Future.value(cached);

    final active = _logoEmpresaFuture;
    if (active != null) return active;

    final future = CompanyBrandingService()
        .loadLogoBytes(widget.empresaId)
        .then((bytes) {
          if (bytes != null && bytes.isNotEmpty) {
            _logoEmpresaBytes = bytes;
          }
          _logoEmpresaFuture = null;
          return bytes;
        })
        .catchError((_) {
          _logoEmpresaFuture = null;
          return null;
        });
    _logoEmpresaFuture = future;
    return future;
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: _kRutasColor,
        foregroundColor: Colors.white,
        title: const Text('Mi ruta de hoy'),
        actions: [
          IconButton(
            tooltip: _trackingActivo
                ? 'Actualizar ubicación (seguimiento activo)'
                : 'Actualizar ubicación',
            onPressed: _ubicando ? null : _ubicar,
            icon: _ubicando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.my_location),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _ErrorState(mensaje: _error!, onRetry: _init)
          : _buildBody(),
    );
  }

  Widget _buildBody() {
    final ruta = _ruta!;
    final stop = _stop;
    final puedeTomarActual =
        stop != null &&
        RutasLogic.puedeTomarComida(
          comida: _meal,
          comidasNoRechazadasDelPunto: _comidasHechasPunto,
        );
    final comidaActualRegistrada = _comidasHechasPunto.contains(_meal);

    return RefreshIndicator(
      onRefresh: _ubicar,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Resumen
          Card(
            color: _kRutasColor.withOpacity(0.08),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ruta.codigo,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: _kRutasColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('Menú de hoy: $_menuNumero'),
                  if ((_asig?.vehiculo ?? '').isNotEmpty)
                    Text('Vehículo: ${_asig!.vehiculo}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Establecimiento actual (sin mapa)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ESTABLECIMIENTO',
                    style: TextStyle(
                      color: Colors.grey,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    stop?.nombre ?? 'Sin establecimientos',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (stop != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      stop.direccionVisible,
                      style: const TextStyle(color: Colors.black54),
                    ),
                  ],
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _cambiarPunto,
                      icon: const Icon(Icons.place),
                      label: const Text('Cambiar establecimiento'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Comida (autodetectada por hora) con secuencia
          const Text(
            'TIEMPO DE COMIDA',
            style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final comida in kComidasOrden) ...[
                Expanded(child: _mealButton(comida)),
                if (comida != kComidasOrden.last) const SizedBox(width: 8),
              ],
            ],
          ),
          const SizedBox(height: 20),

          // Botón grande de cámara
          SizedBox(
            height: 84,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: puedeTomarActual
                    ? _kRutasColor
                    : Colors.grey.shade500,
                textStyle: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              onPressed: (_subiendo || stop == null)
                  ? null
                  : puedeTomarActual
                  ? () => _tomarFoto()
                  : () => _snack(
                      RutasLogic.motivoBloqueoComida(
                        comida: _meal,
                        comidasNoRechazadasDelPunto: _comidasHechasPunto,
                      ),
                    ),
              icon: _subiendo
                  ? const SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.photo_camera, size: 30),
              label: Text(
                _subiendo
                    ? 'Subiendo…'
                    : comidaActualRegistrada
                    ? 'FOTO YA TOMADA'
                    : 'TOMAR FOTO',
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Galería de hoy
          const Text(
            'FOTOS DE HOY',
            style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          _galeriaHoy(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _mealButton(String comida) {
    final seleccionada = _meal == comida;
    final habilitada = RutasLogic.puedeTomarComida(
      comida: comida,
      comidasNoRechazadasDelPunto: _comidasHechasPunto,
    );
    final hecha = _comidasHechasPunto.contains(comida);

    return InkWell(
      onTap: habilitada
          ? () => setState(() => _meal = comida)
          : () => _snack(
              RutasLogic.motivoBloqueoComida(
                comida: comida,
                comidasNoRechazadasDelPunto: _comidasHechasPunto,
              ),
            ),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
        decoration: BoxDecoration(
          color: seleccionada ? _kRutasColor : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: seleccionada ? _kRutasColor : Colors.grey.shade300,
          ),
        ),
        child: Column(
          children: [
            Icon(
              habilitada
                  ? (hecha ? Icons.check_circle : Icons.restaurant)
                  : Icons.lock,
              color: seleccionada
                  ? Colors.white
                  : (habilitada ? Colors.black54 : Colors.grey),
            ),
            const SizedBox(height: 4),
            Text(
              comida == kComidaCena ? 'Cena' : comida,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: seleccionada ? Colors.white : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _galeriaHoy() {
    return StreamBuilder<List<RutaEvidenciaDoc>>(
      stream: _service.streamEvidencias(
        empresaId: widget.empresaId,
        fecha: RutasLogic.fechaKey(DateTime.now()),
        conductorCedula: widget.userId,
      ),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final evid = snap.data!;
        if (evid.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(20),
            alignment: Alignment.center,
            child: const Text(
              'Aún no has subido fotos hoy.',
              style: TextStyle(color: Colors.black45),
            ),
          );
        }
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.78,
          ),
          itemCount: evid.length,
          itemBuilder: (_, i) => _EvidenciaCard(
            evidencia: evid[i],
            onTap: () => _verEvidencia(evid[i]),
          ),
        );
      },
    );
  }

  Future<void> _verEvidencia(RutaEvidenciaDoc e) async {
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: InteractiveViewer(
                child: (e.downloadURL ?? '').isEmpty
                    ? const Center(child: Icon(Icons.broken_image, size: 64))
                    : Image.network(e.downloadURL!, fit: BoxFit.contain),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${e.paradaNombre} · ${e.comida}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  _EstadoChip(estado: e.estado),
                  if (e.rechazada && e.motivoRechazo.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Motivo: ${e.motivoRechazo}',
                      style: const TextStyle(color: Colors.red),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, 'close'),
                    child: const Text('Cerrar'),
                  ),
                  if (e.rechazada)
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: _kRutasColor,
                      ),
                      onPressed: () => Navigator.pop(ctx, 'repeat'),
                      icon: const Icon(Icons.replay),
                      label: const Text('Repetir foto'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (action != 'repeat') return;
    // Posiciona el establecimiento y la comida de esa evidencia y abre cámara.
    final ruta = _ruta;
    if (ruta != null) {
      final idx = ruta.stops.indexWhere((s) => s.nombre == e.paradaNombre);
      if (idx >= 0) {
        setState(() => _stopIndex = idx);
        await _recargarComidasPunto();
      }
    }
    await _tomarFoto(comidaForzada: e.comida);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Widgets auxiliares
// ══════════════════════════════════════════════════════════════════════════════

class _EvidenciaCard extends StatelessWidget {
  final RutaEvidenciaDoc evidencia;
  final VoidCallback onTap;

  const _EvidenciaCard({required this.evidencia, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final url = evidencia.thumbURL ?? evidencia.downloadURL ?? '';
    final comidaColor = _colorComida(evidencia.comida);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Card(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: comidaColor, width: 3),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: url.isEmpty
                  ? const ColoredBox(
                      color: Color(0x11000000),
                      child: Center(child: Icon(Icons.image_not_supported)),
                    )
                  : Image.network(
                      url,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const ColoredBox(
                        color: Color(0x11000000),
                        child: Center(child: Icon(Icons.broken_image)),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    evidencia.paradaNombre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    evidencia.comida == kComidaCena ? 'Cena' : evidencia.comida,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  const SizedBox(height: 4),
                  _EstadoChip(estado: evidencia.estado),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EstadoChip extends StatelessWidget {
  final String estado;

  const _EstadoChip({required this.estado});

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (estado) {
      case kEvidAprobada:
        color = Colors.green;
        break;
      case kEvidRechazada:
        color = Colors.red;
        break;
      default:
        color = Colors.orange;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        kEvidEstadoLabels[estado] ?? estado,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String mensaje;
  final VoidCallback onRetry;

  const _ErrorState({required this.mensaje, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.local_shipping_outlined,
              size: 64,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            Text(
              mensaje,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: _kRutasColor),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}
