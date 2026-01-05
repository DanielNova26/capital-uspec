// lib/home/create_task_screen.dart
// ignore_for_file: use_build_context_synchronously

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:geocoding/geocoding.dart' as gcode;
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng; // (solo por tipo)
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:todo/state/empresa_scope.dart';

/// ===================== CONFIG =====================
/// Tu API KEY (debes tener habilitado Static Maps y billing activo)
const String kGoogleMapsApiKey = 'AIzaSyD8posdo50hmD8PLPD9kR6IebNYfi6PkPs';

/// Colecciones
const String kCollUsuarios = 'TBL_USUARIOS';
const String kCollAreas = 'TBL_AREAS';
const String kCollCentros = 'TBL_CENTROS_COSTOS';
const String kCollTareas = 'TBL_TAREAS';

/// Claves posibles para token FCM en el doc de usuario
const List<String> kTokenKeys = [
  'fcmToken',
  'fcm_token',
  'pushToken',
  'notificationToken',
  'token',
  'token_noti',
];

/// ==================================================

/// Color principal de la app
const Color kMarronOscuro = Color(0xFF145DA0);

class CreateTaskScreen extends StatefulWidget {
  /// Puedes pasar el usuario actual si lo tienes (cedula/username/docId).
  final String? currentUserId;

  const CreateTaskScreen({super.key, this.currentUserId});

  @override
  State<CreateTaskScreen> createState() => _CreateTaskScreenState();
}

class _CreateTaskScreenState extends State<CreateTaskScreen> {
  String _firstNonEmpty(Map<String, dynamic> data, List<String> keys) {
    for (final k in keys) {
      final v = data[k];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  String _empresaDe(Map<String, dynamic> data) =>
      _firstNonEmpty(data, const ['empresaId', 'empresa_id', 'empresa']);

  String _areaDe(Map<String, dynamic> data) => _firstNonEmpty(data,
      const ['areaId', 'area_id', 'area', 'departamentoId', 'departamento_id', 'departamento']);

  /// ==================== TOKEN HELPERS PROFUNDOS ====================
  /// Devuelve true si encuentra al menos un token en String / List / Map.
  bool _hasAnyToken(Map<String, dynamic>? userData) {
    if (userData == null) return false;

    bool anyToken(dynamic v) {
      if (v == null) return false;
      if (v is String) return v.trim().isNotEmpty;
      if (v is List) return v.any(anyToken);
      if (v is Map) return v.values.any(anyToken);
      return false;
    }

    // Claves típicas
    const keys = [
      'fcmTokens',
      'fcmToken',
      'tokens',
      'deviceTokens',
      'pushToken',
      'notificationToken',
      'token'
    ];
    for (final k in keys) {
      if (anyToken(userData[k])) return true;
    }

    // Fallback: cualquier clave que contenga "token"
    for (final e in userData.entries) {
      if (e.key.toLowerCase().contains('token') && anyToken(e.value)) {
        return true;
      }
    }
    return false;
  }

  /// Obtiene el primer token que encuentre (útil si lo necesitas).
  String _firstToken(Map<String, dynamic>? userData) {
    if (userData == null) return '';

    String pick(dynamic v) {
      if (v == null) return '';
      if (v is String) return v.trim();
      if (v is List) {
        for (final x in v) {
          final s = pick(x);
          if (s.isNotEmpty) return s;
        }
        return '';
      }
      if (v is Map) {
        for (final x in v.values) {
          final s = pick(x);
          if (s.isNotEmpty) return s;
        }
        return '';
      }
      return '';
    }

    const keys = [
      'fcmTokens',
      'fcmToken',
      'tokens',
      'deviceTokens',
      'pushToken',
      'notificationToken',
      'token'
    ];
    for (final k in keys) {
      final s = pick(userData[k]);
      if (s.isNotEmpty) return s;
    }
    for (final e in userData.entries) {
      if (e.key.toLowerCase().contains('token')) {
        final s = pick(e.value);
        if (s.isNotEmpty) return s;
      }
    }
    return '';
  }

  /// Extractor simple (lo dejamos por compatibilidad puntual si te sirve en otro lado)
  String _extractToken(Map<String, dynamic>? userData) {
    if (userData == null) return '';
    for (final k in kTokenKeys) {
      final v = userData[k];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  // ====== UI / Form ======
  final _formKey = GlobalKey<FormState>();
  final _titleCtl = TextEditingController();
  final _descCtl = TextEditingController();
  String _priority = 'media';
  DateTime? _deadline;

  // ====== Selecciones ======
  String? _centroId;
  String? _areaId;
  String _cargoFiltro = 'todos';
  String? _asignadoUid;
  String? _asignadoNombre;
  String? _jefeUid;
  String? _jefeNombre;
  String? _empresaId;
  String? _miAreaId;
  String? _currentUid;

  // Estructura organizacional (por uid)
  final Map<String, Map<String, dynamic>> _estructura = {};

  // ====== Datos cargados ======
  List<Map<String, String>> _areas = []; // [{id,nombre}]
  List<Map<String, String>> _centros = []; // [{id,nombre}]
  List<String> _cargos = ['todos'];
  List<Map<String, String>> get _areasFiltradas {
    final lista = [..._areas];
    lista.sort((a, b) => (a['nombre'] ?? '').compareTo(b['nombre'] ?? ''));
    return lista;
  }
  // Usuarios activos, mapa para lookup rápido por uid
  final Map<String, Map<String, dynamic>> _usuarios = {};
  List<Map<String, String>> get _empleadosFiltrados {
    // Filtra por área si hay selección
    final all = _usuarios.entries
        .where((e) => (e.value['estado'] ?? '').toString().toLowerCase() == 'activo')
        .where((e) => _currentUid == null || e.key != _currentUid)
        .map((e) => {
      'uid': e.key,
      'nombre': _nombreDeUsuario(e.value),
      'areaId': _areaDe(e.value),
      'cargo': (e.value['cargo'] ?? '').toString(),
      'jefeId': (e.value['jefeId'] ?? '').toString(),
      'jefeNombre': (e.value['jefeNombre'] ?? '').toString(),
    })
        .toList();
    if (_areaId == null || _areaId!.isEmpty) {
      all.sort((a, b) => (a['nombre'] ?? '').compareTo(b['nombre'] ?? ''));
      return _cargoFiltro == 'todos'
          ? all
          : all
          .where((m) => (m['cargo'] ?? '').toLowerCase() == _cargoFiltro.toLowerCase())
          .toList();
    }
    final filtered = all.where((m) => (m['areaId'] ?? '') == _areaId).toList()
      ..sort((a, b) => (a['nombre'] ?? '').compareTo(b['nombre'] ?? ''));
    final cargoFiltered = (_cargoFiltro == 'todos')
        ? filtered
        : filtered
        .where((m) => (m['cargo'] ?? '').toLowerCase() == _cargoFiltro.toLowerCase())
        .toList();
    return cargoFiltered.isEmpty ? filtered.isEmpty ? all : filtered : cargoFiltered;
  }

  // ====== Adjuntos / Foto ======
  final ImagePicker _picker = ImagePicker();
  File? _photo;
  final List<PlatformFile> _pickedFiles = [];

  // ====== Ubicación ======
  Position? _myPos;
  String? _myAddress;

  bool _saving = false;
  bool _bootstrapped = false;
  EmpresaState? _empresaState;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = EmpresaScope.of(context);
    if (_empresaState != scope) {
      _empresaState?.removeListener(_onEmpresaChanged);
      _empresaState = scope..addListener(_onEmpresaChanged);
    }
    final selected = scope.selectedEmpresaId?.trim();
    if (!_bootstrapped) {
      _bootstrapped = true;
      if ((selected ?? '').isNotEmpty) {
        _empresaId = selected;
      }
      _bootstrap();
    } else
    if (selected != null && selected.isNotEmpty && selected != _empresaId) {
      _empresaId = selected;
      _bootstrap();
    }
  }
  @override
  void dispose() {
    _titleCtl.dispose();
    _descCtl.dispose();
    super.dispose();
    _empresaState?.removeListener(_onEmpresaChanged);
  }

  void _onEmpresaChanged() {
    final selected = _empresaState?.selectedEmpresaId?.trim();
    if (selected != null && selected.isNotEmpty && selected != _empresaId) {
      _empresaId = selected;
      _bootstrap();
    }
  }

  Future<void> _bootstrap() async {
    await _ensurePermissions();
    await _loadCurrentUser();
    await _loadEstructura();
    await Future.wait([
      _getMyPosition(),
      _loadAreas(),
      _loadUsuarios(),
      _loadCentros(),
    ]);
    _ensureAreaSeleccionada();
    setState(() {});
  }

  Future<void> _loadCurrentUser() async {
    final uid = widget.currentUserId ?? FirebaseAuth.instance.currentUser?.uid;
    _currentUid = uid;
    if (uid == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection(kCollUsuarios)
          .doc(uid)
          .get();
      if (!doc.exists) return;

      final data = doc.data() ?? {};
      _empresaId = _empresaDe(data);
      _miAreaId = _areaDe(data);

    } catch (_) {}
  }

  Future<void> _loadEstructura() async {
    try {
      Query<Map<String, dynamic>> ref =
      FirebaseFirestore.instance.collection('TBL_ESTRUCTURA_ORGANIZACIONAL');
      if (_empresaId != null && _empresaId!.isNotEmpty) {
        ref = ref.where('empresaId', isEqualTo: _empresaId);
      }

      final qs = await ref.get();
      _estructura
        ..clear()
        ..addEntries(qs.docs.map((d) => MapEntry(d.id, d.data())));

      if ((_miAreaId ?? '').isEmpty && _currentUid != null) {
        final me = _estructura[_currentUid!];
        if (me != null) {
          _miAreaId = _areaDe(me);
        }
      }
    } catch (_) {
      _estructura.clear();
    }
  }

  Future<void> _ensurePermissions() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      // no forzamos, pero invitamos
      await Geolocator.openLocationSettings();
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.deniedForever) {
      await Geolocator.openAppSettings();
    }
  }

  Future<void> _getMyPosition() async {
    try {
      _myPos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      _myAddress = await _reverseGeocode(_myPos!.latitude, _myPos!.longitude);
    } catch (_) {
      _myPos = null;
      _myAddress = null;
    }
  }

  Future<String?> _reverseGeocode(double lat, double lng) async {
    try {
      final places = await gcode.placemarkFromCoordinates(lat, lng);
      if (places.isNotEmpty) {
        final p = places.first;
        final street = [
          p.street,
          p.subLocality,
        ].where((e) => (e ?? '').isNotEmpty).join(', ');
        final city = [
          p.locality,
          p.administrativeArea,
        ].where((e) => (e ?? '').isNotEmpty).join(' - ');
        return [street, city].where((e) => e.isNotEmpty).join(' | ');
      }
    } catch (_) {}
    return null;
  }

  Future<QuerySnapshot<Map<String, dynamic>>> _queryByEmpresa(
      String collection, {
        int limit = 2000,
      }) async {
    final col = FirebaseFirestore.instance.collection(collection);
    if (_empresaId == null || _empresaId!.isEmpty) {
      return col.limit(limit).get();
    }

    const keys = ['empresaId', 'empresa_id', 'empresa'];
    for (final k in keys) {
      try {
        final snap = await col.where(k, isEqualTo: _empresaId).limit(limit).get();
        if (snap.docs.isNotEmpty) return snap;
      } catch (_) {}
    }
    return col.limit(limit).get();
  }

  bool _empresaCoincide(Map<String, dynamic> data) {
    if (_empresaId == null || _empresaId!.isEmpty) return true;
    final emp = _empresaDe(data);
    if (emp.isEmpty) return true;
    return emp == _empresaId;
  }

  Future<void> _loadCentros() async {
    try {
      final qs = await _queryByEmpresa(kCollCentros, limit: 1000);
      _centros = qs.docs
          .map((d) {
        final m = d.data();
        if (!_empresaCoincide(m)) return null;
        final id = (m['centroId'] ?? d.id).toString();
        final nombre = (m['nombre'] ?? id).toString();
        return {'id': id, 'nombre': nombre};
      })
          .whereType<Map<String, String>>()
          .where((m) => (m['id'] ?? '').toString().isNotEmpty)
          .toList()
        ..sort((a, b) => (a['nombre'] ?? '').compareTo(b['nombre'] ?? ''));

      // Si el centro previamente elegido ya no existe, limpiamos selección.
      final selectedExists = _centros.any((c) => c['id'] == _centroId);
      if (!selectedExists) {
        _centroId = null;
        _areaId = null;
        _alElegirAsignado(null);
      }
    } catch (_) {
      _centroId = null;
    }
  }

  Future<void> _loadAreas() async {
    final qs = await _queryByEmpresa(kCollAreas, limit: 1000);

    _areas = qs.docs
        .map((d) {
      final m = d.data();
      if (!_empresaCoincide(m)) return null;
      final id = _areaDe(m).isEmpty ? d.id : _areaDe(m);
      final nombre = (m['nombre'] ?? '—').toString();
      final centroId = (m['centroId'] ?? m['centro_id'] ?? m['centro'] ?? '').toString();
      return {'id': id, 'nombre': nombre, 'centroId': centroId};
    })
        .whereType<Map<String, String>>()
        .where((m) => (m['id'] ?? '').toString().isNotEmpty)
        .toList()
      ..sort((a, b) => (a['nombre'] ?? '').compareTo(b['nombre'] ?? ''));


    // Fallback: áreas desde estructura organizacional si no están en TBL_AREAS
    final existingIds = _areas.map((a) => a['id']).whereType<String>().toSet();
    for (final entry in _estructura.entries) {
      final estr = entry.value;
      final id = (estr['areaId'] ?? '').toString();
      if (id.isEmpty || existingIds.contains(id)) continue;
      final nombre = (estr['area'] ?? id).toString();
      final centroId = (estr['centroId'] ?? estr['centro'] ?? '').toString();
      _areas.add({'id': id, 'nombre': nombre, 'centroId': centroId});
      existingIds.add(id);
    }

    _areas.sort((a, b) => (a['nombre'] ?? '').compareTo(b['nombre'] ?? ''));
    _ensureAreaSeleccionada();
  }

  Future<void> _loadUsuarios() async {
    final qs = await _queryByEmpresa(kCollUsuarios, limit: 2000);
    final cargos = <String>{};
    for (final d in qs.docs) {
      final data = Map<String, dynamic>.from(d.data());
      final estr = _estructura[d.id];
      if (estr != null) {
        bool _isEmpty(String key) =>
            (data[key] == null || data[key].toString().trim().isEmpty);
        void _fill(String key, dynamic value) {
          if (_isEmpty(key) && value != null && value.toString().trim().isNotEmpty) {
            data[key] = value;
          }
        }

        _fill('areaId', estr['areaId']);
        _fill('area', estr['area']);
        _fill('centroId', estr['centroId'] ?? estr['centro']);
        _fill('centroCostos', estr['centroCostos']);
        _fill('jefeId', estr['jefeId']);
        _fill('jefeNombre', estr['jefeNombre']);
      }
      if (!_empresaCoincide(data)) continue;
      final cargo = (data['cargo'] ?? '').toString().trim();
      if (cargo.isNotEmpty) cargos.add(cargo);
      _usuarios[d.id] = data;
    }
    _cargos = ['todos', ...cargos.toList()..sort()];
    _ensureAreaSeleccionada();
  }

  String _nombreDeUsuario(Map<String, dynamic> u) {
    final n = (u['nombres'] ?? '').toString().trim();
    final a = (u['apellidos'] ?? '').toString().trim();
    final altN = (u['primerNombre'] ?? '').toString().trim();
    final altA = (u['primerApellido'] ?? '').toString().trim();
    final full = '$n $a'.trim();
    if (full.isNotEmpty) return full;
    final alt = '$altN $altA'.trim();
    if (alt.isNotEmpty) return alt;
    return (u['nombre'] ?? '').toString().trim().isEmpty
        ? (u['cedula'] ?? '—').toString()
        : (u['nombre'] ?? '').toString();
  }

  Future<Map<String, dynamic>?> _fetchUser(String uid) async {
    try {
      final d = await FirebaseFirestore.instance.collection(kCollUsuarios).doc(uid).get();
      return d.data();
    } catch (_) {
      return null;
    }
  }

  void _ensureAreaSeleccionada() {
    final lista = _areasFiltradas;
    final selectedExists = lista.any((a) => a['id'] == _areaId);
    if (!selectedExists) {
      _areaId = null;

      if (_asignadoUid != null) {
        _alElegirAsignado(null);
      }
    }
  }

  // ==================== IMAGEN + MAPA ====================

  Future<void> _takePhoto() async {
    try {
      final x = await _picker.pickImage(source: ImageSource.camera, imageQuality: 85);
      if (x != null) setState(() => _photo = File(x.path));
    } catch (_) {}
  }

  void _openPhotoFull() {
    if (_photo == null) return;
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: InteractiveViewer(child: Image.file(_photo!, fit: BoxFit.contain)),
        ),
      ),
    );
  }

  Future<ui.Image> _decodeUiImage(Uint8List bytes) {
    final c = Completer<ui.Image>();
    ui.decodeImageFromList(bytes, (img) => c.complete(img));
    return c.future;
  }

  /// Mapa estático. Si la API no está habilitada o falla, devuelve null.
  Future<ui.Image?> _getStaticMap({
    required double width,
    required double height,
  }) async {
    if (_myPos == null) return null;
    try {
      // Asegura tamaño mínimo para evitar artefactos de 4x4 px.
      final effW = math.max(128, math.min(640, width.round()));
      final effH = math.max(128, math.min(640, height.round()));

      // Zoom simple, suficientemente cerca
      const zoom = 16;
      final center = '${_myPos!.latitude},${_myPos!.longitude}';
      final staticUrl = Uri.parse(
        'https://maps.googleapis.com/maps/api/staticmap'
            '?center=$center'
            '&zoom=$zoom'
            '&size=${effW}x${effH}'
            '&scale=2'
            '&maptype=roadmap'
            '&language=es'
            '&markers=color:red|label:U|$center'
            '&key=$kGoogleMapsApiKey',
      );

      final resp = await http.get(staticUrl).timeout(const Duration(seconds: 7));
      if (resp.statusCode == 200) {
        return _decodeUiImage(resp.bodyBytes);
      }
    } catch (_) {}
    return null;
  }

  Future<Uint8List?> _buildWatermarkedBytes(ui.Image base) async {
    final nowStr = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());

    // Creador: del usuario actual si vino como parámetro; si no, intenta con FirebaseAuth
    String creadorNombre = '—';
    if (widget.currentUserId != null && _usuarios.containsKey(widget.currentUserId)) {
      creadorNombre = _nombreDeUsuario(_usuarios[widget.currentUserId]!);
    } else {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null && _usuarios.containsKey(uid)) {
        creadorNombre = _nombreDeUsuario(_usuarios[uid]!);
      }
    }

    final origenCoords = _myPos == null
        ? '—'
        : '${_myPos!.latitude.toStringAsFixed(5)}, ${_myPos!.longitude.toStringAsFixed(5)}';
    final origenLinea =
        'Ubicación: $origenCoords${_myAddress == null ? '' : ' · ${_myAddress!}'}';

    final infoTexto = [
      'Tarea • $nowStr',
      'Creador: $creadorNombre',
      if (_asignadoNombre != null) 'Asignado: $_asignadoNombre',
      if (_jefeNombre != null) 'Jefe: $_jefeNombre',
      if (_deadline != null) 'Límite: ${DateFormat('dd/MM/yyyy HH:mm').format(_deadline!)}',
      'Prioridad: ${_priority.toUpperCase()}',
      origenLinea,
    ].join('\n');

    final recorder = ui.PictureRecorder();
    final canvas =
    ui.Canvas(recorder, ui.Rect.fromLTWH(0, 0, base.width.toDouble(), base.height.toDouble()));

    // Foto base
    canvas.drawImage(
      base,
      ui.Offset.zero,
      ui.Paint()..filterQuality = ui.FilterQuality.medium,
    );

    // Logo (opcional)
    ui.Image? logo;
    try {
      final lb = await rootBundle.load('assets/logo.png');
      logo = await _decodeUiImage(lb.buffer.asUint8List());
    } catch (_) {}

    // Overlay inferior ~20%
    final overlayH = (base.height * 0.20).toDouble().clamp(120.0, 260.0);
    final overlayRect =
    ui.Rect.fromLTWH(0, base.height - overlayH, base.width.toDouble(), overlayH);
    canvas.drawRect(
      overlayRect,
      ui.Paint()..color = const Color(0xCC000000), // negro con alpha
    );

    const double pad = 18.0;
    final logoW = base.width * 0.18;
    final textW = base.width * 0.54;
    final mapW = base.width * 0.28;

    final logoRect = ui.Rect.fromLTWH(
      overlayRect.left + pad,
      overlayRect.top + pad,
      math.max(0, logoW - 2 * pad),
      math.max(0, overlayH - 2 * pad),
    );
    final textRect = ui.Rect.fromLTWH(
      overlayRect.left + logoW + pad,
      overlayRect.top + pad,
      math.max(0, textW - 2 * pad),
      math.max(0, overlayH - 2 * pad),
    );
    final mapRect = ui.Rect.fromLTWH(
      overlayRect.left + logoW + textW + pad,
      overlayRect.top + pad,
      math.max(128, mapW - 2 * pad),
      math.max(128, overlayH - 2 * pad),
    );

    // Dibuja logo centrado en blanco
    if (logo != null && logoRect.width > 0 && logoRect.height > 0) {
      final scale = math.min(logoRect.width / logo.width, logoRect.height / logo.height);
      final w = logo.width * scale;
      final h = logo.height * scale;
      final dst = ui.Rect.fromLTWH(
        logoRect.left + (logoRect.width - w) / 2,
        logoRect.top + (logoRect.height - h) / 2,
        w,
        h,
      );
      canvas.drawImageRect(
        logo,
        ui.Rect.fromLTWH(0, 0, logo.width.toDouble(), logo.height.toDouble()),
        dst,
        ui.Paint()..colorFilter = const ui.ColorFilter.mode(Colors.white, ui.BlendMode.modulate),
      );
    }

    // Texto con ajuste binario de tamaño
    Future<ui.Paragraph> buildPara({
      required String txt,
      required double maxW,
      required double maxH,
      double minFont = 18,
      double maxFont = 48,
      int maxLines = 10,
      Color color = const Color(0xFFEFEFEF),
      ui.TextAlign align = ui.TextAlign.left,
    }) async {
      double lo = minFont, hi = maxFont;
      ui.Paragraph? best;
      for (int i = 0; i < 20; i++) {
        final mid = (lo + hi) / 2;
        final pb = ui.ParagraphBuilder(
          ui.ParagraphStyle(textAlign: align, maxLines: maxLines, ellipsis: '…'),
        )
          ..pushStyle(ui.TextStyle(color: color, fontSize: mid))
          ..addText(txt);
        final p = pb.build()..layout(ui.ParagraphConstraints(width: maxW));
        if (p.height <= maxH) {
          best = p;
          lo = mid + 0.5;
        } else {
          hi = mid - 0.5;
        }
      }
      best ??=
      (ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: align, maxLines: maxLines, ellipsis: '…'))
        ..pushStyle(ui.TextStyle(color: color, fontSize: lo))
        ..addText(txt))
          .build()
        ..layout(ui.ParagraphConstraints(width: maxW));
      return best;
    }

    final para = await buildPara(txt: infoTexto, maxW: textRect.width, maxH: textRect.height);
    final textOffsetY = textRect.top + (textRect.height - para.height) / 2;
    canvas.drawParagraph(para, ui.Offset(textRect.left, textOffsetY));

    // Mapa
    ui.Image? mapImg = await _getStaticMap(width: mapRect.width, height: mapRect.height);
    if (mapImg != null) {
      // marco con bordes redondeados
      final rrect = ui.RRect.fromRectAndRadius(mapRect, const ui.Radius.circular(12));
      final clipPath = ui.Path()..addRRect(rrect);
      canvas.save();
      canvas.clipPath(clipPath);
      canvas.drawImageRect(
        mapImg,
        ui.Rect.fromLTWH(0, 0, mapImg.width.toDouble(), mapImg.height.toDouble()),
        mapRect,
        ui.Paint()..filterQuality = ui.FilterQuality.high,
      );
      canvas.restore();
      final border = ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white.withOpacity(0.9);
      canvas.drawRRect(rrect, border);
    } else {
      final p = ui.Paint()..color = Colors.white.withOpacity(0.15);
      final rrect = ui.RRect.fromRectAndRadius(mapRect, const ui.Radius.circular(12));
      canvas.drawRRect(rrect, p);
      final pb = ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: ui.TextAlign.center))
        ..pushStyle(ui.TextStyle(color: Colors.white70, fontSize: 18))
        ..addText('MAPA (habilita Static Maps API)');
      final ph = pb.build()..layout(ui.ParagraphConstraints(width: mapRect.width));
      canvas.drawParagraph(ph, ui.Offset(mapRect.left, mapRect.top + (mapRect.height - ph.height) / 2));
    }

    final picture = recorder.endRecording();
    final out = await picture.toImage(base.width, base.height);
    final png = await out.toByteData(format: ui.ImageByteFormat.png);
    return png?.buffer.asUint8List();
  }

  // ==================== PICKER / UPLOAD ====================

  Future<void> _pickFiles() async {
    final res = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true, // importante para putData en Web/Android
      type: FileType.custom,
      allowedExtensions: const [
        'pdf',
        'doc',
        'docx',
        'xls',
        'xlsx',
        'ppt',
        'pptx',
        'zip',
        'jpg',
        'jpeg',
        'png',
      ],
    );
    if (res != null && res.files.isNotEmpty) {
      setState(() {
        _pickedFiles.addAll(res.files);
      });
    }
  }

  String _guessMimeFromExtension(String extLower) {
    switch (extLower) {
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'ppt':
        return 'application/vnd.ms-powerpoint';
      case 'pptx':
        return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      case 'zip':
        return 'application/zip';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      default:
        return 'application/octet-stream';
    }
  }

  Future<({String path, String? url})> _uploadBytes(Uint8List bytes, String storagePath,
      {String? mime}) async {
    final ref = FirebaseStorage.instance.ref(storagePath);
    await ref.putData(bytes, SettableMetadata(contentType: mime));
    String? url;
    try {
      url = await ref.getDownloadURL();
    } catch (_) {}
    return (path: storagePath, url: url);
  }

  Future<({String storagePath, String? downloadURL})> _uploadEvidence(Uint8List bytes) async {
    final now = DateTime.now();
    final y = DateFormat('yyyy').format(now);
    final m = DateFormat('MM').format(now);
    final d = DateFormat('dd').format(now);
    final fileName = 'evid_${now.millisecondsSinceEpoch}.png';
    final storagePath = 'tareas/$y/$m/$d/$fileName';
    final up = await _uploadBytes(bytes, storagePath, mime: 'image/png');
    return (storagePath: up.path, downloadURL: up.url);
  }

  // ==================== GUARDAR ====================

  /// Lectura fresca para validar token antes de crear (estricto).
  Future<bool> _docHasTokenFresh(String uid) async {
    try {
      final snap = await FirebaseFirestore.instance.collection(kCollUsuarios).doc(uid).get();
      final data = snap.data();
      return _hasAnyToken(data);
    } catch (_) {
      return false;
    }
  }

  Future<void> _saveTask() async {
    if (!_formKey.currentState!.validate()) return;
    if (_centroId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona el centro de costos.')),
      );
      return;
    }
    if (_asignadoUid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona la persona asignada.')),
      );
      return;
    }
    if (_currentUid != null && _asignadoUid == _currentUid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No puedes asignarte una tarea a ti mismo.')),
      );
      return;
    }

    if (_areaId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona el departamento (área).')),
      );
      return;
    }

    // ====== VALIDACIÓN DE TOKENS (asignado y jefe directo) ======
    // Relee el asignado desde Firestore para asegurar datos frescos y nombre
    final asignadoDoc = await _fetchUser(_asignadoUid!);
    if (asignadoDoc == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo leer la información del asignado.')),
      );
      return;
    }

    // Determina jefe (preferimos el ya calculado; si no, desde el doc del asignado)
    String? jefeUid = _jefeUid ?? (asignadoDoc['jefeId']?.toString().trim());
    Map<String, dynamic>? jefeDoc;
    if (jefeUid != null && jefeUid.isNotEmpty) {
      jefeDoc = await _fetchUser(jefeUid);
    }

    setState(() => _saving = true);

    // === validación estricta antes de crear (lectura directa) ===
    if (!await _docHasTokenFresh(_asignadoUid!)) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La persona asignada no ha iniciado sesión (no tiene token).')),
      );
      return;
    }
    if (jefeUid != null && jefeUid.isNotEmpty && !await _docHasTokenFresh(jefeUid)) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El jefe directo no ha iniciado sesión (no tiene token).')),
      );
      return;
    }

    try {
      // ===== Evidencia (foto) con marca de agua =====
      String? evidenceUrl;
      String? evidencePath;
      if (_photo != null) {
        final raw = await _photo!.readAsBytes();
        final base = await _decodeUiImage(raw);
        final wm = await _buildWatermarkedBytes(base);
        if (wm != null) {
          final up = await _uploadEvidence(wm);
          evidenceUrl = up.downloadURL;
          evidencePath = up.storagePath;
        }
      }

      // ===== Adjuntos =====
      final now = DateTime.now();
      final y = DateFormat('yyyy').format(now);
      final m = DateFormat('MM').format(now);
      final d = DateFormat('dd').format(now);
      final List<Map<String, dynamic>> adjuntos = [];
      for (final f in _pickedFiles) {
        final name = f.name;
        final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
        final mime = _guessMimeFromExtension(ext);
        final fileBytes = f.bytes ?? (f.path != null ? await File(f.path!).readAsBytes() : null);
        if (fileBytes == null) continue;

        final storagePath = 'tareas/$y/$m/$d/adj_${DateTime.now().millisecondsSinceEpoch}_$name';
        final up = await _uploadBytes(fileBytes, storagePath, mime: mime);
        adjuntos.add({
          'name': name,
          'path': up.path,
          'url': up.url,
          'mime': mime,
          'size': f.size,
        });
      }

      // ===== Datos de creador =====
      String? creadorId = widget.currentUserId;
      String? creadorNombre;
      if (creadorId != null && _usuarios.containsKey(creadorId)) {
        creadorNombre = _nombreDeUsuario(_usuarios[creadorId]!);
      } else {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null) {
          creadorId = uid;
          if (_usuarios.containsKey(uid)) {
            creadorNombre = _nombreDeUsuario(_usuarios[uid]!);
          }
        }
      }

      // ===== Crear documento =====
      final resolvedEmpresaId = () {
        final current = (_empresaId ?? '').trim();
        if (current.isNotEmpty) return current;
        final empFromAsignado = _empresaDe(asignadoDoc);
        if (empFromAsignado.isNotEmpty) return empFromAsignado;
        return '';
      }();

      final payload = <String, dynamic>{
        'titulo': _titleCtl.text.trim(),
        'descripcion': _descCtl.text.trim(),
        'prioridad': _priority,
        'fecha_creacion': FieldValue.serverTimestamp(),
        'fecha_limite': _deadline == null ? null : Timestamp.fromDate(_deadline!),
        'estado': 'pendiente',
        'centroId': _centroId,
        'areaId': _areaId,
        // 👇 fuerza string, sin espacios
        'asignado_uid': (_asignadoUid ?? '').toString().trim(),
        'asignado_nombre': _asignadoNombre ??
            _nombreDeUsuario(asignadoDoc), // por si aún no estaba seteado el nombre
        'jefe_uid': jefeUid,
        'jefe_nombre': _jefeNombre ?? (jefeDoc == null ? null : _nombreDeUsuario(jefeDoc)),
        'creador_id': creadorId,
        'creador_nombre': creadorNombre,
        'ubicacion': _myPos == null
            ? null
            : {
          'lat': _myPos!.latitude,
          'lng': _myPos!.longitude,
          'texto': _myAddress,
        },
        'evidencias': evidenceUrl == null ? [] : [evidenceUrl],
        'evidencias_paths': evidencePath == null ? [] : [evidencePath],
        'adjuntos': adjuntos,
        'notify': true,
      };

      if (resolvedEmpresaId.isNotEmpty) {
        payload['empresaId'] = resolvedEmpresaId;
      }

      final ref = await FirebaseFirestore.instance.collection(kCollTareas).add(payload);

      _photo = null;
      _pickedFiles.clear();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Tarea creada (ID: ${ref.id}).')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al crear tarea: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ==================== UI HELPERS ====================

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (d == null) return;
    final t = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 17, minute: 0),
    );
    if (t == null) return;
    setState(() => _deadline = DateTime(d.year, d.month, d.day, t.hour, t.minute));
  }

  /// Lectura fresca de un usuario (para refrescar cache al elegir asignado/jefe)
  Future<Map<String, dynamic>?> _fetchUserFresh(String uid) async {
    try {
      final snap =
      await FirebaseFirestore.instance.collection(kCollUsuarios).doc(uid).get();
      return snap.data();
    } catch (_) {
      return null;
    }
  }

  void _alElegirAsignado(String? uid) async {
    if (uid != null && _currentUid != null && uid == _currentUid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No puedes asignarte una tarea a ti mismo.')),
      );
      setState(() {});
      return;
    }

    _asignadoUid = uid;

    if (uid == null) {
      _asignadoNombre = null;
      _jefeUid = null;
      _jefeNombre = null;
      setState(() {});
      return;
    }

    // 1) asignado fresco
    final fresh = await _fetchUserFresh(uid);
    if (fresh != null) _usuarios[uid] = fresh;

    final u = _usuarios[uid];
    if (u != null) {
      _asignadoNombre = _nombreDeUsuario(u);
      final jefeId = (u['jefeId'] ?? '').toString().trim();
      _jefeUid = jefeId.isEmpty ? null : jefeId;
      _jefeNombre = (u['jefeNombre'] ?? '').toString().trim().isEmpty
          ? null
          : (u['jefeNombre'] ?? '').toString();
    }

    // 2) jefe fresco (si aplica)
    if (_jefeUid != null && _jefeUid!.isNotEmpty) {
      final jefeFresh = await _fetchUserFresh(_jefeUid!);
      if (jefeFresh != null) {
        _usuarios[_jefeUid!] = jefeFresh;
        _jefeNombre ??= _nombreDeUsuario(jefeFresh);
      }
    }

    setState(() {});
  }

  // ==================== BUILD ====================

  @override
  Widget build(BuildContext context) {
    final styleLabel = Theme.of(context).textTheme.labelMedium;
    final styleHint = Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54);

    // Chequeo rápido (cache actualizada) para mostrar aviso visual;
    // el bloqueo real ocurre en _saveTask con _docHasTokenFresh().
    final bool hasAssigneeToken =
    _asignadoUid == null ? true : _hasAnyToken(_usuarios[_asignadoUid!]);
    final bool hasBossToken =
    _jefeUid == null ? true : _hasAnyToken(_usuarios[_jefeUid!]);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Crear tarea'),
        backgroundColor: kMarronOscuro,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // -------- Datos principales --------
              Card(
                elevation: 1,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _titleCtl,
                          decoration: const InputDecoration(
                            labelText: 'Título',
                            hintText: 'Ej. Entregar informe de stock',
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Ingresa un título' : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _descCtl,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            labelText: 'Descripción',
                            hintText: 'Detalles, criterios de aceptación, etc.',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),

                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                isExpanded: true,
                                value: _priority,
                                decoration: const InputDecoration(
                                  labelText: 'Prioridad',
                                  border: OutlineInputBorder(),
                                ),
                                items: const [
                                  DropdownMenuItem(value: 'alta', child: Text('Alta')),
                                  DropdownMenuItem(value: 'media', child: Text('Media')),
                                  DropdownMenuItem(value: 'baja', child: Text('Baja')),
                                ],
                                onChanged: (v) => setState(() => _priority = v ?? 'media'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: InkWell(
                                onTap: _pickDeadline,
                                child: InputDecorator(
                                  decoration: const InputDecoration(
                                    labelText: 'Fecha límite',
                                    border: OutlineInputBorder(),
                                  ),
                                  child: Text(
                                    _deadline == null
                                        ? 'Sin definir'
                                        : DateFormat('dd/MM/yyyy HH:mm').format(_deadline!),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Centro de costos
                        DropdownButtonFormField<String>(
                          isExpanded: true,
                          value: _centroId,
                          decoration: const InputDecoration(
                            labelText: 'Centro de costos',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            ..._centros.map(
                                  (c) => DropdownMenuItem(
                                    value: c['id'],
                                child: Text(
                                  c['nombre'] ?? c['id'] ?? '—',
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ),
                            ),
                          ],
                          onChanged: (v) => setState(() {
                            _centroId = v;
                          }),
                        ),

                        const SizedBox(height: 12),

                        // Área
                        DropdownButtonFormField<String>(
                          isExpanded: true,
                          value: _areaId,
                          decoration: const InputDecoration(
                            labelText: 'Departamento (Área)',
                            border: OutlineInputBorder(),
                          ),
                          items: _areasFiltradas
                              .map(
                                (a) => DropdownMenuItem(
                              value: a['id'],
                              child: Text(
                                a['nombre'] ?? '—',
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          )
                              .toList(),
                          onChanged: (v) {
                            _areaId = v;
                            // Si la persona asignada no pertenece al área, limpiala
                            if (_asignadoUid != null) {
                              final e = _usuarios[_asignadoUid!];
                              final areaDelAsignado = e == null ? '' : _areaDe(e);
                              if (v == null || areaDelAsignado != v) {
                                _alElegirAsignado(null);
                              }
                            } else if (v == null) {
                              _alElegirAsignado(null);
                            }
                            setState(() {});
                          },
                          validator: (v) => v == null ? 'Selecciona el área' : null,
                        ),
                        const SizedBox(height: 12),

                        // Cargo
                        DropdownButtonFormField<String>(
                          isExpanded: true,
                          value: _cargoFiltro,
                          decoration: const InputDecoration(
                            labelText: 'Cargo',
                            border: OutlineInputBorder(),
                          ),
                          items: _cargos
                              .map((c) => DropdownMenuItem(
                            value: c,
                            child: Text(c == 'todos' ? 'Todos los cargos' : c,
                                overflow: TextOverflow.ellipsis),
                          ))
                              .toList(),
                          onChanged: (v) {
                            setState(() {
                              _cargoFiltro = v ?? 'todos';
                              if (_asignadoUid != null) {
                                final cargoAsignado =
                                (_usuarios[_asignadoUid!]?['cargo'] ?? '').toString().toLowerCase();
                                if (_cargoFiltro != 'todos' && cargoAsignado != _cargoFiltro.toLowerCase()) {
                                  _alElegirAsignado(null);
                                }
                              }
                            });
                          },
                        ),
                        const SizedBox(height: 12),

                        // Persona asignada
                        DropdownButtonFormField<String>(
                          isExpanded: true,
                          value: _asignadoUid,
                          decoration: const InputDecoration(
                            labelText: 'Persona asignada',
                            border: OutlineInputBorder(),
                          ),
                          items: _empleadosFiltrados.map((e) {
                            final nombre = e['nombre'] ?? '—';
                            return DropdownMenuItem(
                              value: e['uid'],
                              child: Text(nombre, overflow: TextOverflow.ellipsis, maxLines: 1),
                            );
                          }).toList(),
                          onChanged: _alElegirAsignado,
                          validator: (v) => v == null ? 'Selecciona la persona' : null,
                        ),

                        // Avisos rápidos (cache) de tokens usando extractor profundo
                        if (_asignadoUid != null && !hasAssigneeToken) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: const [
                              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 18),
                              SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'La persona asignada aún no ha iniciado sesión (sin token).',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (_jefeUid != null && !hasBossToken) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: const [
                              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 18),
                              SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'El jefe directo aún no ha iniciado sesión (sin token).',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ],

                        if (_jefeNombre != null) ...[
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Jefe directo: $_jefeNombre',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // -------- Evidencia y adjuntos --------
              Card(
                elevation: 1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Evidencia y adjuntos (opcionales)', style: styleLabel),
                      const SizedBox(height: 8),
                      Text(
                        'Puedes tomar una foto; se generará una marca de agua con datos y un mapa. '
                            'También puedes adjuntar archivos (PDF, Word, Excel, PowerPoint, ZIP, imágenes).',
                        style: styleHint,
                      ),
                      const SizedBox(height: 12),

                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          ElevatedButton.icon(
                            onPressed: _takePhoto,
                            icon: const Icon(Icons.photo_camera_outlined),
                            label: const Text('Tomar foto'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kMarronOscuro,
                              foregroundColor: Colors.white,
                            ),
                          ),
                          if (_photo != null)
                            OutlinedButton.icon(
                              onPressed: _openPhotoFull,
                              icon: const Icon(Icons.zoom_in),
                              label: const Text('Ver'),
                            ),
                          FilledButton.icon(
                            onPressed: _pickFiles,
                            icon: const Icon(Icons.attach_file),
                            label: const Text('Adjuntar archivos'),
                            style: FilledButton.styleFrom(
                              backgroundColor: kMarronOscuro,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      if (_photo != null)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.file(
                              _photo!,
                              height: 120,
                              width: 90,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),

                      if (_pickedFiles.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _pickedFiles.length,
                          separatorBuilder: (_, __) => const Divider(height: 8),
                          itemBuilder: (_, i) {
                            final f = _pickedFiles[i];
                            return Row(
                              children: [
                                const Icon(Icons.insert_drive_file_outlined, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    f.name,
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () => setState(() => _pickedFiles.removeAt(i)),
                                  icon: const Icon(Icons.close),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _saveTask,
                  icon: _saving
                      ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                      : const Icon(Icons.check),
                  label: Text(_saving ? 'Creando…' : 'Crear tarea'),
                  style: FilledButton.styleFrom(
                    backgroundColor: kMarronOscuro,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
