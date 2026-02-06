import 'dart:async';

// lib/home/create_task_screen.dart
// ignore_for_file: use_build_context_synchronously
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
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng; // solo por tipo
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
const String kCollTareas = 'TBL_TAREAS';
const String kCollCargos = 'TBL_CARGOS';

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
  // ===================== HELPERS BASE =====================
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

  String _areaDe(Map<String, dynamic> data) => _firstNonEmpty(
    data,
    const [
      'areaId',
      'area_id',
      'area',
      'departamentoId',
      'departamento_id',
      'departamento',
    ],
  );

  /// Returns the cargoId for the user. First consults the empresaDetalle block
  /// for the current empresaId (multi-empresa support), falling back to the
  /// top-level keys when not available. This ensures that users assigned to
  /// multiple companies get the correct cargo for the selected company.
  String _cargoIdDe(Map<String, dynamic> data) {
    if (_empresaId != null && _empresaId!.trim().isNotEmpty) {
      final detalle = data['empresasDetalle'];
      if (detalle is Map && detalle[_empresaId] is Map) {
        final det = Map<String, dynamic>.from(detalle[_empresaId] as Map);
        final cid = _firstNonEmpty(det, const ['cargoId', 'cargo_id']);
        if (cid.isNotEmpty) return cid;
      }
    }
    return _firstNonEmpty(data, const ['cargoId', 'cargo_id']);
  }

  /// Returns the cargo name for the user. This reads the cargo name from the
  /// empresaDetalle block for the current empresaId before falling back to
  /// top-level keys. Without this, a user belonging to multiple companies
  /// would always display the cargo from the primary company.
  String _cargoNombreDe(Map<String, dynamic> data) {
    if (_empresaId != null && _empresaId!.trim().isNotEmpty) {
      final detalle = data['empresasDetalle'];
      if (detalle is Map && detalle[_empresaId] is Map) {
        final det = Map<String, dynamic>.from(detalle[_empresaId] as Map);
        final cname = _firstNonEmpty(det, const [
          'cargo',
          'cargoNombre',
          'cargo_nombre',
          'puesto',
          'descripcion',
        ]);
        if (cname.isNotEmpty) return cname;
      }
    }
    return _firstNonEmpty(
      data,
      const [
        'cargo',
        'cargoNombre',
        'cargo_nombre',
        'puesto',
        'descripcion',
      ],
    );
  }

  List<String> _empresasDeUsuario(Map<String, dynamic> data) {
    final out = <String>{};
    final primary = _empresaDe(data).trim();
    if (primary.isNotEmpty) out.add(primary);

    final list = data['empresas'] as List<dynamic>? ?? const [];
    for (final e in list) {
      final id = (e ?? '').toString().trim();
      if (id.isNotEmpty) out.add(id);
    }

    final detalle = data['empresasDetalle'] as Map<String, dynamic>?;
    if (detalle != null) {
      out.addAll(detalle.keys.map((k) => k.trim()).where((k) => k.isNotEmpty));
    }
    return out.toList();
  }

  String _cedulaDe(Map<String, dynamic> data) => _firstNonEmpty(
    data,
    const [
      'cedula',
      'cédula',
      'documento',
      'documentoId',
      'docId',
      'idNumber',
    ],
  );

  String _norm(String s) => s.trim().toLowerCase();

  /// Attempts to resolve the areaId of the given user for the current empresa.
  /// This method first looks into `empresasDetalle[_empresaId]` for an
  /// `areaId` or area name. If not found, it falls back to the existing
  /// logic (using top-level areaId/areaName fields). This ensures that
  /// employees belonging to multiple companies are correctly mapped.
  String? _resolveAreaIdFromUser(Map<String, dynamic> u) {
    // 0) Busca en empresasDetalle para la empresa actual
    if (_empresaId != null && _empresaId!.trim().isNotEmpty) {
      final detalle = u['empresasDetalle'] as Map<String, dynamic>?;
      final det = detalle?[_empresaId] as Map<String, dynamic>?;
      if (det != null) {
        final directDet = _firstNonEmpty(det, const [
          'areaId',
          'area_id',
          'departamentoId',
          'departamento_id',
        ]);
        if (directDet.isNotEmpty && _areas.any((a) => a['id'] == directDet)) {
          return directDet;
        }
        final nombreDet = _firstNonEmpty(det, const [
          'areaNombre',
          'area_nombre',
          'area',
          'departamento',
          'departamentoNombre',
        ]);
        if (nombreDet.isNotEmpty) {
          final hit = _areas.firstWhere(
                (a) => _norm(a['nombre'] ?? '') == _norm(nombreDet),
            orElse: () => {},
          );
          final id = (hit['id'] ?? '').toString().trim();
          if (id.isNotEmpty) return id;
        }
      }
    }

    // 1) si ya viene areaId real
    final direct = _firstNonEmpty(u, const [
      'areaId',
      'area_id',
      'departamentoId',
      'departamento_id',
    ]);
    if (direct.isNotEmpty && _areas.any((a) => a['id'] == direct)) return direct;

    // 2) si viene por nombre: area / areaNombre / departamento
    final nombre = _firstNonEmpty(u, const [
      'areaNombre',
      'area_nombre',
      'area',
      'departamento',
      'departamentoNombre',
    ]);

    if (nombre.isNotEmpty) {
      final hit = _areas.firstWhere(
            (a) => _norm(a['nombre'] ?? '') == _norm(nombre),
        orElse: () => {},
      );
      if ((hit['id'] ?? '').toString().trim().isNotEmpty) return hit['id']!.trim();
    }

    return null;
  }

  String? _nombreAreaPorId(String? id) {
    if (id == null || id.trim().isEmpty) return null;
    final hit = _areas.firstWhere((a) => a['id'] == id.trim(), orElse: () => {});
    final n = (hit['nombre'] ?? '').toString().trim();
    return n.isEmpty ? null : n;
  }

  String? _nombreCargoPorId(String? id) {
    if (id == null || id.trim().isEmpty) return null;
    final hit = _cargosFiltrados.firstWhere((c) => c['id'] == id.trim(), orElse: () => {});
    final n = (hit['nombre'] ?? '').toString().trim();
    return n.isEmpty ? null : n;
  }

  // ==================== TOKEN HELPERS PROFUNDOS ====================
  bool _hasAnyToken(Map<String, dynamic>? userData) {
    if (userData == null) return false;

    bool anyToken(dynamic v) {
      if (v == null) return false;
      if (v is String) return v.trim().isNotEmpty;
      if (v is List) return v.any(anyToken);
      if (v is Map) return v.values.any(anyToken);
      return false;
    }

    const keys = [
      'fcmDevices',
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

    for (final e in userData.entries) {
      if (e.key.toLowerCase().contains('token') && anyToken(e.value)) {
        return true;
      }
      if (e.key.toLowerCase().contains('fcm') && anyToken(e.value)) {
        return true;
      }
    }
    return false;
  }

  // ==================== UI / Form ====================
  final _formKey = GlobalKey<FormState>();
  final _titleCtl = TextEditingController();
  final _descCtl = TextEditingController();
  String _priority = 'media';
  DateTime? _deadline;
  bool _requiresAttachment = true;

  // ==================== Selecciones ====================
  String? _areaId;
  String _cargoFiltro = 'todos';
  String? _asignadoUid;
  String? _asignadoNombre;
  String? _jefeUid;
  String? _jefeNombre;
  String? _empresaId;
  String? _currentUid;

  // Estructura organizacional (por uid)
  final Map<String, Map<String, dynamic>> _estructura = {};

  // ==================== Datos cargados ====================
  List<Map<String, String>> _areas = []; // [{id,nombre,centroId?}]
  List<Map<String, dynamic>> _cargos = []; // [{id,nombre,areaId?,enabled?,cedulas?,empresaId?}]
  final Set<String> _empresasUsuario = {};
  // Usuarios activos, mapa para lookup rápido por uid
  final Map<String, Map<String, dynamic>> _usuarios = {};

  // ==================== Adjuntos / Foto ====================
  final ImagePicker _picker = ImagePicker();
  File? _photo;
  final List<PlatformFile> _pickedFiles = [];

  // ==================== Ubicación ====================
  Position? _myPos;
  String? _myAddress;

  bool _saving = false;
  bool _bootstrapped = false;
  EmpresaState? _empresaState;

  // ==================== GETTERS DE FILTROS ====================
  List<Map<String, String>> get _areasFiltradas {
    final all = [..._areas]
      ..sort((a, b) => (a['nombre'] ?? '').compareTo(b['nombre'] ?? ''));
    return all;
  }

  List<Map<String, String>> get _cargosFiltrados {
    if (_areaId == null || _areaId!.trim().isEmpty) {
      return const [{'id': 'todos', 'nombre': 'Selecciona un cargo'}];
    }
    final cargos = <String, String>{};
    for (final estr in _estructura.values) {
      final areaId = (estr['areaId'] ?? '').toString().trim();
      if (areaId.isEmpty || areaId != _areaId!.trim()) continue;
      final cargoId = _cargoIdDe(estr);
      final cargoNombre = _cargoNombreDe(estr);
      final key = (cargoId.isNotEmpty ? cargoId : cargoNombre).trim();
      if (key.isEmpty) continue;
      cargos[key] = cargoNombre.isNotEmpty ? cargoNombre : key;
    }
    if (cargos.isEmpty) {
      for (final cargo in _cargos) {
        if (!_cargoCoincideEmpresa(cargo)) continue;
        final enabled = (cargo['enabled'] ?? 'true').toString().toLowerCase() != 'false';
        if (!enabled) continue;
        final areaId = (cargo['areaId'] ?? '').toString().trim();
        final nombre = (cargo['nombre'] ?? '').toString().trim();
        if (areaId.isNotEmpty && areaId != _areaId!.trim()) continue;
        final rawId = (cargo['id'] ?? '').toString().trim();
        final key = rawId.isEmpty ? nombre : rawId;
        if (key.isNotEmpty) cargos[key] = nombre.isNotEmpty ? nombre : key;
      }
    }
    final lista = cargos.entries.toList()
      ..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));
    return [
      const {'id': 'todos', 'nombre': 'Selecciona un cargo'},
      ...lista.map((e) => {'id': e.key, 'nombre': e.value}),
    ];
  }

  List<Map<String, String>> get _empleadosFiltrados {
    final list = <Map<String, String>>[];
    final areaActiva = _areaId?.trim() ?? '';
    final cedulasPermitidas = <String>{};
    final cargoActivoId = _cargoFiltro.trim();
    final cargoActivoNombre =
    (_nombreCargoPorId(_cargoFiltro) ?? '').trim().toLowerCase();
    if (areaActiva.isNotEmpty) {
      cedulasPermitidas.addAll(_cedulasDesdeCargos(
        areaId: areaActiva,
        cargoId: cargoActivoId,
        cargoNombreLower: cargoActivoNombre,
      ));
      for (final estr in _estructura.values) {
        final areaId = (estr['areaId'] ?? '').toString().trim();
        if (areaId.isEmpty || areaId != areaActiva) continue;
        final cargoId = _cargoIdDe(estr);
        final cargoNombre = _cargoNombreDe(estr).trim().toLowerCase();
        if (cargoActivoId != 'todos' && cargoActivoId.isNotEmpty) {
          if (cargoId.isNotEmpty) {
            if (cargoId != cargoActivoId) continue;
          } else if (cargoActivoNombre.isNotEmpty) {
            if (cargoNombre != cargoActivoNombre) continue;
          }
        }
        final cedula = _cedulaDe(estr).trim();
        if (cedula.isNotEmpty) cedulasPermitidas.add(cedula);
      }
    }

    for (final entry in _usuarios.entries) {
      final uid = entry.key;
      final u = entry.value;

      final estado = (u['estado'] ?? '').toString().toLowerCase();
      if (estado != 'activo') continue;
      if (_currentUid != null && uid == _currentUid) continue;

      // 1) filtra por área / estructura
      final areaId = (_resolveAreaIdFromUser(u) ?? _areaDe(u)).trim();
      final cargoId = _cargoIdDe(u).trim();
      final cargo = _cargoNombreDe(u).trim();
      final cedula = _cedulaDe(u).trim();

      if (areaActiva.isNotEmpty) {
        if (cedulasPermitidas.isNotEmpty) {
          if (cedula.isEmpty || !cedulasPermitidas.contains(cedula)) continue;
        } else if (areaId != areaActiva) {
          continue;
        }
      }

      // 2) filtra por cargo (si aún aplica)
      if (_cargoFiltro != 'todos' && _cargoFiltro.trim().isNotEmpty) {
        if (cargoId.isNotEmpty) {
          if (cargoId != _cargoFiltro.trim()) continue;
        } else if (cargo.isNotEmpty) {
          if (cargo.toLowerCase() != cargoActivoNombre) continue;
        } else {
          continue;
        }
      }

      list.add({
        'uid': uid,
        'nombre': _nombreDeUsuario(u),
        'areaId': areaId,
        'cargo': cargo,
        'jefeId': (u['jefeId'] ?? u['jefe_uid'] ?? '').toString(),
        'jefeNombre': (u['jefeNombre'] ?? u['jefe_nombre'] ?? '').toString(),
      });
    }

    list.sort((a, b) => (a['nombre'] ?? '').compareTo(b['nombre'] ?? ''));
    return list;
  }

  bool _cargoCoincideEmpresa(Map<String, dynamic> cargo) {
    if (_empresaId == null || _empresaId!.trim().isEmpty) return true;
    final emp = (cargo['empresaId'] ?? '').toString().trim();
    if (emp.isEmpty) return true;
    return emp == _empresaId!.trim();
  }

  Set<String> _cedulasDesdeCargos({
    required String areaId,
    required String cargoId,
    required String cargoNombreLower,
  }) {
    final out = <String>{};
    for (final cargo in _cargos) {
      if (!_cargoCoincideEmpresa(cargo)) continue;
      final area = (cargo['areaId'] ?? '').toString().trim();
      if (area.isEmpty || area != areaId) continue;

      final id = (cargo['id'] ?? '').toString().trim();
      final nombre = (cargo['nombre'] ?? '').toString().trim().toLowerCase();
      if (cargoId != 'todos' && cargoId.isNotEmpty) {
        if (id.isNotEmpty) {
          if (id != cargoId) continue;
        } else if (cargoNombreLower.isNotEmpty) {
          if (nombre != cargoNombreLower) continue;
        }
      }

      final cedulas = cargo['cedulas'];
      if (cedulas is List) {
        for (final c in cedulas) {
          final cedula = (c ?? '').toString().trim();
          if (cedula.isNotEmpty) out.add(cedula);
        }
      }
    }
    return out;
  }

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
    } else if (selected != null && selected.isNotEmpty && selected != _empresaId) {
      _empresaId = selected;
      _bootstrap();
    }
  }

  @override
  void dispose() {
    _titleCtl.dispose();
    _descCtl.dispose();
    _empresaState?.removeListener(_onEmpresaChanged);
    super.dispose();
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

    // IMPORTANT: primero catálogos, luego usuarios (para poder resolver ids por nombre/código)
    await Future.wait([
      _getMyPosition(),
      _loadAreas(),
      _loadCargos(),
    ]);
    await _loadUsuarios();

    if (mounted) setState(() {});
  }

  Future<void> _loadCurrentUser() async {
    final uid = widget.currentUserId ?? FirebaseAuth.instance.currentUser?.uid;
    _currentUid = uid;
    if (uid == null) return;

    try {
      final doc = await FirebaseFirestore.instance.collection(kCollUsuarios).doc(uid).get();
      if (!doc.exists) return;

      final data = doc.data() ?? {};
      _empresasUsuario
        ..clear()
        ..addAll(_empresasDeUsuario(data));
      // empresa del usuario (puede venir y sobrescribir lo de scope si no estaba)
      final emp = _empresaDe(data);
      if (emp.trim().isNotEmpty) _empresaId = emp.trim();

    } catch (_) {}
  }

  Future<void> _loadEstructura() async {
    try {
      final baseRef =
      FirebaseFirestore.instance.collection('TBL_ESTRUCTURA_ORGANIZACIONAL');
      QuerySnapshot<Map<String, dynamic>> qs;
      if (_empresaId != null && _empresaId!.isNotEmpty) {
        try {
          qs = await baseRef.where('empresas', arrayContains: _empresaId).get();
          if (qs.docs.isEmpty) {
            qs = await baseRef.where('empresaId', isEqualTo: _empresaId).get();
          }
        } catch (_) {
          qs = await baseRef.where('empresaId', isEqualTo: _empresaId).get();
        }
      } else {
        qs = await baseRef.get();
      }

      _estructura.clear();
      for (final d in qs.docs) {
        final data = Map<String, dynamic>.from(d.data());
        if ((data['cedula'] ?? '').toString().trim().isEmpty) {
          data['cedula'] = d.id;
        }
        if (_empresaId != null && _empresaId!.isNotEmpty) {
          final detalle = data['empresasDetalle'];
          if (detalle is Map && detalle[_empresaId] is Map) {
            final det = Map<String, dynamic>.from(detalle[_empresaId] as Map);
            data.addAll(det);
            data['empresaId'] = _empresaId;
          } else {
            final rootEmpresa = _empresaDe(data).trim();
            if (rootEmpresa.isNotEmpty && rootEmpresa != _empresaId) {
              continue;
            }
          }
        }
        _estructura[d.id] = data;
      }

    } catch (_) {
      _estructura.clear();
    }
  }

  Future<void> _ensurePermissions() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
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
      _myPos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
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
        final street = [p.street, p.subLocality].where((e) => (e ?? '').isNotEmpty).join(', ');
        final city =
        [p.locality, p.administrativeArea].where((e) => (e ?? '').isNotEmpty).join(' - ');
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

    try {
      final snap = await col.where('empresas', arrayContains: _empresaId).limit(limit).get();
      if (snap.docs.isNotEmpty) return snap;
    } catch (_) {}

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
    final emp = _empresaDe(data).trim();
    if (emp.isNotEmpty && emp == _empresaId) return true;

    final empresas = data['empresas'] as List<dynamic>?;
    if (empresas != null) {
      for (final e in empresas) {
        if ((e ?? '').toString().trim() == _empresaId) return true;
      }
    }

    final detalle = data['empresasDetalle'];
    if (detalle is Map && detalle[_empresaId] != null) return true;

    return emp.isEmpty;
  }

  // ==================== CARGA DE CATÁLOGOS ====================
  Future<void> _loadAreas() async {
    final qs = await _queryByEmpresa(kCollAreas, limit: 1000);

    _areas = qs.docs
        .map((d) {
      final m = d.data();
      if (!_empresaCoincide(m)) return null;
      final id = (_firstNonEmpty(m, const ['areaId', 'area_id']).trim().isEmpty)
          ? d.id
          : _firstNonEmpty(m, const ['areaId', 'area_id']).trim();
      final nombre = (m['nombre'] ?? '—').toString().trim();
      final centroId = (m['centroId'] ?? m['centro_id'] ?? m['centro'] ?? '').toString().trim();
      return {'id': id, 'nombre': nombre.isEmpty ? '—' : nombre, 'centroId': centroId};
    })
        .whereType<Map<String, String>>()
        .where((m) => (m['id'] ?? '').toString().trim().isNotEmpty)
        .toList()
      ..sort((a, b) => (a['nombre'] ?? '').compareTo(b['nombre'] ?? ''));

    // Fallback: solo si TBL_AREAS está vacío
    if (_areas.isEmpty) {
      final existingIds = _areas.map((a) => a['id']).whereType<String>().toSet();
      for (final entry in _estructura.entries) {
        final estr = entry.value;
        final id = (estr['areaId'] ?? '').toString().trim();
        if (id.isEmpty || existingIds.contains(id)) continue;
        final nombre = (estr['area'] ?? estr['areaNombre'] ?? id).toString().trim();
        final centroId = (estr['centroId'] ?? estr['centro'] ?? '').toString().trim();
        _areas.add({'id': id, 'nombre': nombre.isEmpty ? id : nombre, 'centroId': centroId});
        existingIds.add(id);
      }
    }

    _areas.sort((a, b) => (a['nombre'] ?? '').compareTo(b['nombre'] ?? ''));
  }

  Future<void> _loadCargos() async {
    try {
      final col = FirebaseFirestore.instance.collection(kCollCargos);
      final empresas = _empresasUsuario.isNotEmpty
          ? _empresasUsuario.toList()
          : ((_empresaId ?? '').trim().isNotEmpty ? <String>[_empresaId!.trim()] : <String>[]);
      final docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];

      if (empresas.isEmpty) {
        final qs = await col.limit(1000).get();
        docs.addAll(qs.docs);
      } else {
        for (var i = 0; i < empresas.length; i += 10) {
          final chunk = empresas.sublist(i, i + 10 > empresas.length ? empresas.length : i + 10);
          final snap = await col.where('empresaId', whereIn: chunk).limit(1000).get();
          docs.addAll(snap.docs);
        }
        for (final empresa in empresas) {
          try {
            final snap = await col.where('empresas', arrayContains: empresa).limit(1000).get();
            docs.addAll(snap.docs);
          } catch (_) {}
        }
      }

      final merged = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
      for (final d in docs) {
        merged[d.id] = d;
      }

      _cargos = merged.values
          .map((d) {
        final m = d.data();
        final id = (_firstNonEmpty(m, const ['cargoId', 'cargo_id']).trim().isEmpty)
            ? d.id
            : _firstNonEmpty(m, const ['cargoId', 'cargo_id']).trim();
        final nombre = (m['nombre'] ?? '—').toString().trim();
        final areaId = (m['areaId'] ?? m['area_id'] ?? '').toString().trim();
        final empresaId = _empresaDe(m).trim();
        final enabled = (m['enabled'] as bool?) ?? true;
        final cedulasRaw = m['cedulas'] as List<dynamic>? ?? const [];
        final cedulas = cedulasRaw
            .map((e) => (e ?? '').toString().trim())
            .where((e) => e.isNotEmpty)
            .toList();
        return {
          'id': id,
          'nombre': nombre.isEmpty ? '—' : nombre,
          'areaId': areaId,
          'empresaId': empresaId,
          'enabled': enabled.toString(),
          'cedulas': cedulas,
        };
      })
          .whereType<Map<String, dynamic>>()
          .where((m) => (m['id'] ?? '').toString().trim().isNotEmpty)
          .toList()
        ..sort((a, b) => (a['nombre'] ?? '').toString().compareTo((b['nombre'] ?? '').toString()));
    } catch (_) {
      _cargos = [];
    }
  }

  Future<void> _loadUsuarios() async {
    try {
      _usuarios.clear();
      final cedulasDesdeCargos = <String>{};
      for (final cargo in _cargos) {
        if (!_cargoCoincideEmpresa(cargo)) continue;
        final cedulas = cargo['cedulas'];
        if (cedulas is List) {
          for (final c in cedulas) {
            final cedula = (c ?? '').toString().trim();
            if (cedula.isNotEmpty) cedulasDesdeCargos.add(cedula);
          }
        }
      }

      final docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      final qs = await _queryByEmpresa(kCollUsuarios, limit: 2500);
      docs.addAll(qs.docs);

      if (cedulasDesdeCargos.isNotEmpty) {
        final cedulasList = cedulasDesdeCargos.toList();
        for (var i = 0; i < cedulasList.length; i += 10) {
          final chunk = cedulasList.sublist(
            i,
            i + 10 > cedulasList.length ? cedulasList.length : i + 10,
          );
          final extra = await FirebaseFirestore.instance
              .collection(kCollUsuarios)
              .where(FieldPath.documentId, whereIn: chunk)
              .get();
          docs.addAll(extra.docs);
        }
      }

      final merged = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
      for (final d in docs) {
        merged[d.id] = d;
      }

      for (final d in merged.values) {
        final data = Map<String, dynamic>.from(d.data());
        final estr = _estructura[d.id];

        if ((data['cedula'] ?? '').toString().trim().isEmpty) {
          data['cedula'] = d.id;
        }

        if (estr != null) {
          bool _isEmpty(String key) =>
              (data[key] == null || data[key].toString().trim().isEmpty);
          void _fill(String key, dynamic value) {
            if (_isEmpty(key) && value != null && value.toString().trim().isNotEmpty) {
              data[key] = value;
            }
          }

          // Completar desde estructura (si falta)
          _fill('areaId', estr['areaId']);
          _fill('area', estr['area'] ?? estr['areaNombre']);
          _fill('cargoId', estr['cargoId']);
          _fill('centroId', estr['centroId'] ?? estr['centro']);
          _fill('centro_costos', estr['centro_costos'] ?? estr['centroCostos']);
          _fill('centroCostos', estr['centroCostos']);
          _fill('cargo', estr['cargo']);
          _fill('cedula', estr['cedula']);
          _fill('jefeId', estr['jefeId'] ?? estr['jefe_uid']);
          _fill('jefeNombre', estr['jefeNombre'] ?? estr['jefe_nombre']);
        }

        // Si existe detalle específico por empresa, sobrescribe campos top-level
        if (_empresaId != null && _empresaId!.trim().isNotEmpty) {
          final detalleEmpresas = data['empresasDetalle'] as Map<String, dynamic>?;
          final det = detalleEmpresas?[_empresaId] as Map<String, dynamic>?;
          if (det != null) {
            void applyDetail(String key, dynamic value) {
              if (value != null && value.toString().trim().isNotEmpty) {
                data[key] = value;
              }
            }
            applyDetail('areaId', det['areaId'] ?? det['area_id']);
            applyDetail('area', det['areaNombre'] ?? det['area_nombre'] ?? det['area']);
            applyDetail('cargoId', det['cargoId'] ?? det['cargo_id']);
            applyDetail('cargo', det['cargo'] ?? det['cargoNombre'] ?? det['cargo_nombre'] ?? det['puesto'] ?? det['descripcion']);
            applyDetail('centroId', det['centroId'] ?? det['centro_id']);
            applyDetail('centroCostos', det['centroCostos'] ?? det['centro_costos'] ?? det['centro']);
            applyDetail('jefeId', det['jefeId'] ?? det['jefe_id']);
            applyDetail('jefeNombre', det['jefeNombre'] ?? det['jefe_nombre']);
            applyDetail('cargoJefe', det['cargoJefe']);
          }
        }

        final cargoId = (data['cargoId'] ?? '').toString().trim();
        if ((data['cargo'] ?? '').toString().trim().isEmpty && cargoId.isNotEmpty) {
          final nombreCargo = _nombreCargoPorId(cargoId);
          if (nombreCargo != null && nombreCargo.trim().isNotEmpty) {
            data['cargo'] = nombreCargo.trim();
          }
        }

        final cedula = _cedulaDe(data).trim();
        final inCedulasDesdeCargo = cedulasDesdeCargos.contains(cedula);
        if (!_empresaCoincide(data) && !inCedulasDesdeCargo) continue;
        _usuarios[d.id] = data;
      }
    } catch (_) {
      _usuarios.clear();
    }
  }

  // ==================== NORMALIZACIÓN DE CASCADA ====================
  void _ensureAreaDisponible() {
    if (_areaId != null && _areaId!.trim().isNotEmpty) {
      final list = _areasFiltradas;
      if (!list.any((a) => a['id'] == _areaId)) {
        _areaId = null;
        _alElegirAsignado(null);
      }
    }

    if (_cargoFiltro != 'todos') {
      final cargos = _cargosFiltrados;
      if (!cargos.any((c) => c['id'] == _cargoFiltro)) {
        _cargoFiltro = 'todos';
        _alElegirAsignado(null);
      }
    }

    // Si el asignado ya no aparece en el filtro, limpiar
    if (_asignadoUid != null) {
      final ok = _empleadosFiltrados.any((e) => e['uid'] == _asignadoUid);
      if (!ok) _alElegirAsignado(null);
    }
  }

  // ==================== NOMBRE USUARIO ====================
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

  Future<ui.Image?> _getStaticMap({
    required double width,
    required double height,
  }) async {
    if (_myPos == null) return null;
    try {
      final effW = math.max(128, math.min(640, width.round()));
      final effH = math.max(128, math.min(640, height.round()));

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

    String creadorNombre = '—';
    final uid = widget.currentUserId ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && _usuarios.containsKey(uid)) {
      creadorNombre = _nombreDeUsuario(_usuarios[uid]!);
    }

    final origenCoords = _myPos == null
        ? '—'
        : '${_myPos!.latitude.toStringAsFixed(5)}, ${_myPos!.longitude.toStringAsFixed(5)}';
    final origenLinea = 'Ubicación: $origenCoords${_myAddress == null ? '' : ' · ${_myAddress!}'}';

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
    final canvas = ui.Canvas(
      recorder,
      ui.Rect.fromLTWH(0, 0, base.width.toDouble(), base.height.toDouble()),
    );

    canvas.drawImage(base, ui.Offset.zero, ui.Paint()..filterQuality = ui.FilterQuality.medium);

    ui.Image? logo;
    try {
      final lb = await rootBundle.load('assets/logo.png');
      logo = await _decodeUiImage(lb.buffer.asUint8List());
    } catch (_) {}

    final overlayH = (base.height * 0.20).toDouble().clamp(120.0, 260.0);
    final overlayRect = ui.Rect.fromLTWH(0, base.height - overlayH, base.width.toDouble(), overlayH);
    canvas.drawRect(overlayRect, ui.Paint()..color = const Color(0xCC000000));

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
      best ??= (ui.ParagraphBuilder(ui.ParagraphStyle(
        textAlign: align,
        maxLines: maxLines,
        ellipsis: '…',
      ))
        ..pushStyle(ui.TextStyle(color: color, fontSize: lo))
        ..addText(txt))
          .build()
        ..layout(ui.ParagraphConstraints(width: maxW));
      return best;
    }

    final para = await buildPara(txt: infoTexto, maxW: textRect.width, maxH: textRect.height);
    final textOffsetY = textRect.top + (textRect.height - para.height) / 2;
    canvas.drawParagraph(para, ui.Offset(textRect.left, textOffsetY));

    ui.Image? mapImg = await _getStaticMap(width: mapRect.width, height: mapRect.height);
    if (mapImg != null) {
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
      canvas.drawParagraph(
        ph,
        ui.Offset(mapRect.left, mapRect.top + (mapRect.height - ph.height) / 2),
      );
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
      withData: true,
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
      setState(() => _pickedFiles.addAll(res.files));
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

  Future<({String path, String? url})> _uploadBytes(
      Uint8List bytes,
      String storagePath, {
        String? mime,
      }) async {
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

  // ==================== VALIDACIÓN TOKEN (FRESCA) ====================
  Future<bool> _docHasTokenFresh(String uid) async {
    try {
      final snap = await FirebaseFirestore.instance.collection(kCollUsuarios).doc(uid).get();
      final data = snap.data();
      return _hasAnyToken(data);
    } catch (_) {
      return false;
    }
  }

  // ==================== DEADLINE ====================
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

  // ==================== REFRESH USER ====================
  Future<Map<String, dynamic>?> _fetchUserFresh(String uid) async {
    try {
      final snap = await FirebaseFirestore.instance.collection(kCollUsuarios).doc(uid).get();
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
      final jefeId = (u['jefeId'] ?? u['jefe_uid'] ?? '').toString().trim();
      _jefeUid = jefeId.isEmpty ? null : jefeId;
      final jefeNom = (u['jefeNombre'] ?? u['jefe_nombre'] ?? '').toString().trim();
      _jefeNombre = jefeNom.isEmpty ? null : jefeNom;
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

  // ==================== GUARDAR ====================
  Future<void> _saveTask() async {
    _ensureAreaDisponible();

    if (!_formKey.currentState!.validate()) return;
    if (_areaId == null || _areaId!.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona el área.')),
      );
      return;
    }
    if (_deadline == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona la fecha límite.')),
      );
      return;
    }
    if (_cargoFiltro == 'todos') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona el cargo.')),
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

    // Relee asignado
    final asignadoDoc = await _fetchUser(_asignadoUid!);
    if (asignadoDoc == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo leer la información del asignado.')),
      );
      return;
    }

    // Jefe
    String? jefeUid = _jefeUid ??
        (asignadoDoc['jefeId']?.toString().trim()) ??
        (asignadoDoc['jefe_uid']?.toString().trim());
    Map<String, dynamic>? jefeDoc;
    if (jefeUid != null && jefeUid.isNotEmpty) {
      jefeDoc = await _fetchUser(jefeUid);
    }

    setState(() => _saving = true);

    // Validación estricta tokens (asignado + jefe si existe)
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
      // Evidencia (foto) con marca de agua
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

      // Adjuntos
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

      // Datos creador
      String? creadorId = widget.currentUserId ?? FirebaseAuth.instance.currentUser?.uid;
      String? creadorNombre;
      if (creadorId != null && _usuarios.containsKey(creadorId)) {
        creadorNombre = _nombreDeUsuario(_usuarios[creadorId]!);
      }

      // Empresa (preferimos la seleccionada)
      final resolvedEmpresaId = () {
        final current = (_empresaId ?? '').trim();
        if (current.isNotEmpty) return current;
        final empFromAsignado = _empresaDe(asignadoDoc).trim();
        if (empFromAsignado.isNotEmpty) return empFromAsignado;
        return '';
      }();

      final payload = <String, dynamic>{
        'titulo': _titleCtl.text.trim(),
        'descripcion': _descCtl.text.trim(),
        'prioridad': _priority,
        'fecha_creacion': FieldValue.serverTimestamp(),
        'fecha_limite': _deadline == null ? null : Timestamp.fromDate(_deadline!),
        'estado': 'en_progreso',
        'visto': false,
        'reasignado': false,
        'requiere_adjunto': _requiresAttachment,

        // ✅ IDs consistentes para filtros
        'areaId': _areaId!.trim(),
        'areaNombre': _nombreAreaPorId(_areaId),
        'cargoFiltro': _cargoFiltro,

        // asignación
        'asignado_uid': (_asignadoUid ?? '').toString().trim(),
        'asignado_nombre': _asignadoNombre ?? _nombreDeUsuario(asignadoDoc),
        'jefe_uid': (jefeUid == null || jefeUid.trim().isEmpty) ? null : jefeUid.trim(),
        'jefe_nombre': _jefeNombre ?? (jefeDoc == null ? null : _nombreDeUsuario(jefeDoc)),
        'creador_id': creadorId,
        'creador_nombre': creadorNombre,

        // ubicación
        'ubicacion': _myPos == null
            ? null
            : {
          'lat': _myPos!.latitude,
          'lng': _myPos!.longitude,
          'texto': _myAddress,
        },

        // evidencias
        'evidencias': evidenceUrl == null ? [] : [evidenceUrl],
        'evidencias_paths': evidencePath == null ? [] : [evidencePath],

        // adjuntos
        'adjuntos': adjuntos,
        'notify': true,
      };

      if (resolvedEmpresaId.isNotEmpty) {
        payload['empresaId'] = resolvedEmpresaId;
      }

      final empresasAsignado = _empresasDeUsuario(asignadoDoc);
      if (empresasAsignado.isNotEmpty) {
        if (resolvedEmpresaId.isNotEmpty && !empresasAsignado.contains(resolvedEmpresaId)) {
          empresasAsignado.add(resolvedEmpresaId);
        }
        payload['empresas'] = empresasAsignado;
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

  // ==================== UI: CHIP RESUMEN ====================
  Widget _chipInfo(IconData icon, String text, {Color? color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: (color ?? Colors.black).withOpacity(0.07),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: (color ?? Colors.black).withOpacity(0.10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: (color ?? Colors.black).withOpacity(0.75)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: (color ?? Colors.black).withOpacity(0.85), fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== BUILD ====================
  @override
  Widget build(BuildContext context) {
    // Avisos rápidos tokens (cache)
    final bool hasAssigneeToken =
    _asignadoUid == null ? true : _hasAnyToken(_usuarios[_asignadoUid!]);
    final bool hasBossToken = _jefeUid == null ? true : _hasAnyToken(_usuarios[_jefeUid!]);
    final bool areaSeleccionada = _areaId != null && _areaId!.trim().isNotEmpty;

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // Mantén cascada limpia en cada build (por si cambió data)
    _ensureAreaDisponible();

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
              // Encabezado “resumen” más visual
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _chipInfo(Icons.account_tree_outlined, _nombreAreaPorId(_areaId) ?? 'Área: —',
                      color: scheme.secondary),
                  _chipInfo(
                    Icons.flag_outlined,
                    'Prioridad: ${_priority.toUpperCase()}',
                    color: _priority == 'alta'
                        ? Colors.red
                        : _priority == 'media'
                        ? Colors.orange
                        : Colors.green,
                  ),
                  _chipInfo(
                    Icons.event_outlined,
                    _deadline == null
                        ? 'Límite: —'
                        : 'Límite: ${DateFormat('dd/MM HH:mm').format(_deadline!)}',
                    color: scheme.tertiary,
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // -------- Datos principales --------
              Card(
                elevation: 1,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
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
                            prefixIcon: Icon(Icons.title),
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
                            prefixIcon: Icon(Icons.subject),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Ingresa una descripción'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        SwitchListTile.adaptive(
                          value: _requiresAttachment,
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Requiere adjunto para completar/finalizar'),
                          subtitle: const Text(
                            'Si está activado, se solicitarán evidencias al completar o finalizar.',
                            style: TextStyle(fontSize: 12),
                          ),
                          onChanged: (v) => setState(() => _requiresAttachment = v),
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
                                  prefixIcon: Icon(Icons.flag_outlined),
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
                                    prefixIcon: Icon(Icons.event_outlined),
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

                        // Área (primer filtro)
                        DropdownButtonFormField<String>(
                          isExpanded: true,
                          value: _areaId,
                          decoration: const InputDecoration(
                            labelText: 'Área',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.account_tree_outlined),
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
                            setState(() {
                              _areaId = v?.trim();
                              _cargoFiltro = 'todos';
                              _alElegirAsignado(null);
                            });
                          },
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Selecciona el área' : null,
                        ),

                        const SizedBox(height: 12),

                        // Cargo (segundo filtro)
                        DropdownButtonFormField<String>(
                          isExpanded: true,
                          value: _cargoFiltro,
                          decoration: const InputDecoration(
                            labelText: 'Cargo',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.badge_outlined),
                          ),
                          items: _cargosFiltrados
                              .map(
                                (c) => DropdownMenuItem(
                              value: c['id'],
                              child: Text(
                                c['nombre'] ?? 'Selecciona un cargo',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                              .toList(),
                          onChanged: areaSeleccionada
                              ? (v) {
                            setState(() {
                              _cargoFiltro = (v ?? 'todos').trim().isEmpty ? 'todos' : (v ?? 'todos');
                              _alElegirAsignado(null);
                              _ensureAreaDisponible();
                            });
                          }
                              : null,
                          validator: (v) {
                            if (!areaSeleccionada) return null;
                            return (v == null || v == 'todos') ? 'Selecciona el cargo' : null;
                          },
                        ),

                        const SizedBox(height: 12),

                        // Persona asignada (resultado del filtro)
                        DropdownButtonFormField<String>(
                          isExpanded: true,
                          value: _asignadoUid,
                          decoration: const InputDecoration(
                            labelText: 'Persona asignada',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                          items: _empleadosFiltrados.map((e) {
                            final nombre = e['nombre'] ?? '—';
                            final cargo = (e['cargo'] ?? '').trim();
                            return DropdownMenuItem(
                              value: e['uid'],
                              child: Text(
                                cargo.isEmpty ? nombre : '$nombre  •  $cargo',
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            );
                          }).toList(),
                          onChanged: _alElegirAsignado,
                          validator: (v) => v == null ? 'Selecciona la persona' : null,
                        ),

                        // Avisos tokens
                        if (_asignadoUid != null && !hasAssigneeToken) ...[
                          const SizedBox(height: 8),
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
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Jefe directo: $_jefeNombre',
                              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Evidencia y adjuntos (opcionales)',
                          style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      Text(
                        'Puedes tomar una foto; se generará una marca de agua con datos y un mapa. '
                            'También puedes adjuntar archivos (PDF, Word, Excel, PowerPoint, ZIP, imágenes).',
                        style: theme.textTheme.bodySmall?.copyWith(color: Colors.black54),
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
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(
                              _photo!,
                              height: 120,
                              width: 90,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),

                      if (_pickedFiles.isNotEmpty) ...[
                        const SizedBox(height: 10),
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
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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