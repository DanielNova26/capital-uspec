// lib/talento_humano/organizational_structure_screen.dart

import 'dart:math' show min, max;
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:excel/excel.dart';
import 'package:file_saver/file_saver.dart';
import '../core/hierarchy_order.dart';
import '../widgets/internal_module_layout.dart';
import 'personnel_access_picker.dart';
import 'personnel_requisition_service.dart'
    show
        personnelAccessCredentials,
        personnelNeedsTemporaryPassword,
        personnelTemporaryPassword;
import 'personnel_access_service.dart';
import '../widgets/user_avatar.dart';
import '../utils/user_company.dart';
import 'disciplinary_management_screen.dart';
import 'personnel_status_service.dart';

// ─── Org-chart tree node ─────────────────────────────────────────────────────
class _OrgChartNode {
  final String cedula;
  final String nombre;
  final String cargo;
  final String area;
  final List<_OrgChartNode> children = [];
  double x = 0; // layout x (flutter coords, left)
  double y = 0; // layout y (flutter coords, top)
  _OrgChartNode({
    required this.cedula,
    required this.nombre,
    required this.cargo,
    required this.area,
  });
}

// Layout constants (in logical pts before scaling)
const double _cnW = 140.0; // node width
const double _cnH = 48.0; // node height
const double _chGap = 14.0; // horizontal gap between siblings
const double _cvGap = 38.0; // vertical gap between parent bottom & child top

const String _areasCollection = 'TBL_AREAS';
const String _cargosCollection = 'TBL_CARGOS';
const String _orgCollection = 'TBL_ESTRUCTURA_ORGANIZACIONAL';
const String _usuariosCol = 'TBL_USUARIOS';
const String _ccCollection = 'TBL_CENTROS_COSTOS';
const Color _kPrimaryColor = Color(0xffc28942);
const String _kFontFamily = 'Arial';

// ─── Modelo ligero para la caché de usuarios ─────────────────────────────────
class _UserInfo {
  final String nombre;
  final String foto;
  final String email; // campo 'email' (login)
  final String correo; // campo 'correo' (laboral)
  final String telefono;
  final String nivelEducativo;
  // Org data almacenada en TBL_USUARIOS
  final String cargoJefe;
  final String jefeNombre;
  final String jefeId;
  final String centroCostos;
  final String centroCodigo;
  final String centroId;

  const _UserInfo({
    this.nombre = '',
    this.foto = '',
    this.email = '',
    this.correo = '',
    this.telefono = '',
    this.nivelEducativo = '',
    this.cargoJefe = '',
    this.jefeNombre = '',
    this.jefeId = '',
    this.centroCostos = '',
    this.centroCodigo = '',
    this.centroId = '',
  });

  /// Mejor correo disponible: laboral primero, luego login
  String get bestEmail => correo.isNotEmpty ? correo : email;
}

// ─── Screen ──────────────────────────────────────────────────────────────────
class OrganizationalStructureScreen extends StatefulWidget {
  final String userId;
  final String empresaId;
  const OrganizationalStructureScreen({
    Key? key,
    required this.userId,
    required this.empresaId,
  }) : super(key: key);

  @override
  State<OrganizationalStructureScreen> createState() =>
      _OrganizationalStructureScreenState();
}

class _OrganizationalStructureScreenState
    extends State<OrganizationalStructureScreen> {
  final _personnelStatus = PersonnelStatusService();
  final _searchCtrl = TextEditingController();
  final _areaFilterCtrl = TextEditingController();
  final _cargoFilterCtrl = TextEditingController();

  String? _filterArea;
  String? _filterCargo;
  String _statusFilter = PersonnelStatusService.active;

  /// Accesos a módulos: misma fuente de verdad que la matriz de Admin.
  final PersonnelAccessService _accessService = PersonnelAccessService();

  /// Caché de datos de TBL_USUARIOS, keyed por cédula.
  Map<String, _UserInfo> _userCache = {};
  CargoHierarchyIndex _hierarchy = CargoHierarchyIndex.empty();

  /// Docs actuales del stream (para export).
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _currentDocs = [];

  bool _exporting = false;
  bool _syncing = false;
  bool _generatingPdf = false;

  String _statusOf(Map<String, dynamic> data) =>
      PersonnelStatusService.normalizeStatus(data['estado']);

  String _formatTimestamp(dynamic value) {
    if (value is! Timestamp) return '';
    final date = value.toDate().toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year} '
        '${two(date.hour)}:${two(date.minute)}';
  }

  @override
  void initState() {
    super.initState();
    _bootstrapCompanyStructure();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _areaFilterCtrl.dispose();
    _cargoFilterCtrl.dispose();
    super.dispose();
  }

  // ── Caché de usuarios ──────────────────────────────────────────────────────

  Future<void> _bootstrapCompanyStructure() async {
    await Future.wait([_loadUserCache(), _loadHierarchy()]);
    try {
      await _syncAllTH();
      await Future.wait([_loadUserCache(), _loadHierarchy()]);
    } catch (e) {
      debugPrint(
        '[OrganizationalStructure] sincronización inicial falló '
        'empresa=${widget.empresaId}: $e',
      );
    }
    if (mounted) setState(() {});
  }

  Future<void> _loadHierarchy() async {
    final snap = await FirebaseFirestore.instance
        .collection(_cargosCollection)
        .where('empresaId', isEqualTo: widget.empresaId)
        .get();
    _hierarchy = CargoHierarchyIndex.fromCargos(
      snap.docs.map((d) => <String, dynamic>{'id': d.id, ...d.data()}),
    );
  }

  String _orgCedula(DocumentSnapshot<Map<String, dynamic>> doc) {
    final cedula = (doc.data()?['cedula'] ?? '').toString().trim();
    return cedula.isNotEmpty ? cedula : doc.id;
  }

  Map<String, dynamic> _orgDataForCompany(Map<String, dynamic> raw) {
    return mergeCompanyScopedData(raw, widget.empresaId);
  }

  bool _orgBelongsToCompany(Map<String, dynamic> raw) {
    return matchesEmpresaScope(
      raw,
      widget.empresaId,
      allowLegacyWithoutEmpresa: false,
    );
  }

  Future<void> _loadUserCache() async {
    final fs = FirebaseFirestore.instance;

    // Intentamos las dos variantes de campo de empresa
    final res1 = await fs
        .collection(_usuariosCol)
        .where('empresas', arrayContains: widget.empresaId)
        .get();
    final res2 = await fs
        .collection(_usuariosCol)
        .where('empresaId', isEqualTo: widget.empresaId)
        .get();

    // Deduplicar por doc.id
    final seen = <String>{};
    final allDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final d in [...res1.docs, ...res2.docs]) {
      if (seen.add(d.id)) allDocs.add(d);
    }

    final cache = <String, _UserInfo>{};
    for (final doc in allDocs) {
      final data = doc.data();

      // Datos específicos de la empresa desde empresasDetalle (prioridad)
      final detalle =
          ((data['empresasDetalle'] as Map<String, dynamic>?)?[widget.empresaId]
              as Map<String, dynamic>?) ??
          {};

      // Helper: lee campo de detalle primero, luego raíz
      String _r(String key) {
        final d = (detalle[key] as String?)?.trim() ?? '';
        if (d.isNotEmpty) return d;
        return (data[key] as String?)?.trim() ?? '';
      }

      final nombre = _buildNombre(data);
      final foto = (data['fotoUrl'] as String?)?.trim() ?? '';
      final email = (data['email'] as String?)?.trim() ?? '';
      final correo = (data['correo'] as String?)?.trim() ?? '';
      final telefono = (data['telefono'] as String?)?.trim() ?? '';

      // Nivel educativo más alto registrado en la hoja de vida
      String nivelEd = '';
      if (data['hasMaestria'] == true)
        nivelEd = 'Maestría';
      else if (data['hasEspecializacion'] == true)
        nivelEd = 'Especialización';
      else if (data['hasUniversity'] == true)
        nivelEd = 'Universitario';
      else if (data['bachFecha'] != null ||
          (data['bachInst'] as String? ?? '').isNotEmpty)
        nivelEd = 'Bachiller';

      final info = _UserInfo(
        nombre: nombre,
        foto: foto,
        email: email,
        correo: correo,
        telefono: telefono,
        nivelEducativo: nivelEd,
        cargoJefe: _r('cargoJefe'),
        jefeNombre: _r('jefeNombre'),
        jefeId: _r('jefeId'),
        centroCostos: _r('centroCostos'),
        centroCodigo: _r('centroCodigo'),
        centroId: _r('centroId'),
      );

      // Guardar bajo doc.id Y campo cedula (si difiere)
      cache[doc.id] = info;
      final cedula = (data['cedula'] as String?)?.trim() ?? '';
      if (cedula.isNotEmpty && cedula != doc.id) cache[cedula] = info;
    }

    if (mounted) setState(() => _userCache = cache);
  }

  // ── Helpers de nombre ─────────────────────────────────────────────────────

  String _buildNombre(Map<String, dynamic> data) {
    final parts = [
      data['primerNombre'],
      data['segundoNombre'],
      data['primerApellido'],
      data['segundoApellido'],
    ].whereType<String>().where((s) => s.trim().isNotEmpty).toList();
    if (parts.isNotEmpty) return parts.join(' ');
    final completo = (data['nombreCompleto'] as String?)?.trim() ?? '';
    if (completo.isNotEmpty) return completo;
    final n = (data['nombres'] as String?)?.trim() ?? '';
    final a = (data['apellidos'] as String?)?.trim() ?? '';
    if (n.isNotEmpty || a.isNotEmpty) return '$n $a'.trim();
    return (data['nombre'] as String?)?.trim() ?? '';
  }

  String _superiorLabel(Map<String, dynamic> m) {
    for (final k in [
      'jefe_cargo_desc',
      'cargoJefe',
      'jefe_directo',
      'jefeNombre',
    ]) {
      final v = (m[k] as String?)?.trim() ?? '';
      if (v.isNotEmpty) return v;
    }
    return '—';
  }

  String _centroLabel(Map<String, dynamic> m) {
    for (final k in ['centro_nombre', 'centroCostos']) {
      final v = (m[k] as String?)?.trim() ?? '';
      if (v.isNotEmpty) return v;
    }
    return '—';
  }

  // ── Sugerencias de formulario ──────────────────────────────────────────────

  /// Áreas de TBL_AREAS con nombre y descripción
  Future<List<Map<String, String>>> _fetchAreas(String pattern) async {
    final snap = await FirebaseFirestore.instance
        .collection(_areasCollection)
        .where('empresaId', isEqualTo: widget.empresaId)
        .get();
    return snap.docs
        .where((d) {
          final nombre = (d.data()['nombre'] as String?) ?? '';
          return nombre.toLowerCase().contains(pattern.toLowerCase());
        })
        .map((d) {
          final data = d.data();
          return {
            'nombre': (data['nombre'] as String?)?.trim() ?? '',
            'descripcion': (data['descripcion'] as String?)?.trim() ?? '',
          };
        })
        .toList();
  }

  /// Todos los cargos de TBL_CARGOS
  Future<List<Map<String, String>>> _fetchCargos(String pattern) async {
    final snap = await FirebaseFirestore.instance
        .collection(_cargosCollection)
        .where('empresaId', isEqualTo: widget.empresaId)
        .get();
    return snap.docs
        .map(_cargoSuggestion)
        .where((m) => _matchesCargoSuggestion(m, pattern))
        .toList();
  }

  /// Cargos filtrados por área desde TBL_CARGOS, incluso si aún no tienen
  /// empleados asignados en TBL_ESTRUCTURA.
  Future<List<Map<String, String>>> _fetchCargosForArea(
    String pattern,
    String area,
  ) async {
    if (area.isEmpty) return _fetchCargos(pattern);

    final cargosSnap = await FirebaseFirestore.instance
        .collection(_cargosCollection)
        .where('empresaId', isEqualTo: widget.empresaId)
        .get();

    final areaKey = area.toLowerCase().trim();
    final areaMatches = cargosSnap.docs
        .map(_cargoSuggestion)
        .where((m) {
          final cargoArea = (m['area'] ?? '').toLowerCase().trim();
          final cargoAreaNombre = (m['areaNombre'] ?? '').toLowerCase().trim();
          return cargoArea == areaKey || cargoAreaNombre == areaKey;
        })
        .where((m) => _matchesCargoSuggestion(m, pattern))
        .toList();

    // Si hay datos antiguos con el área cruzada, permitir encontrarlos por
    // búsqueda para poder corregirlos desde el módulo de cargos.
    if (areaMatches.isNotEmpty || pattern.trim().isEmpty) return areaMatches;
    return _fetchCargos(pattern);
  }

  Map<String, String> _cargoSuggestion(
    QueryDocumentSnapshot<Map<String, dynamic>> d,
  ) {
    final data = d.data();
    final n = (data['nombre'] as String?)?.trim() ?? '';
    final desc = n.isNotEmpty
        ? n
        : (data['descripcion'] as String?)?.trim() ?? '';
    final area = (data['area'] as String?)?.trim() ?? '';
    final areaNombre = (data['areaNombre'] as String?)?.trim() ?? '';
    final code = ((data['cargoId'] as String?)?.trim().isNotEmpty == true)
        ? (data['cargoId'] as String).trim()
        : d.id;
    final description = (data['descripcion'] as String?)?.trim() ?? '';
    return {
      'code': d.id,
      'cargoId': code,
      'desc': desc.isNotEmpty ? desc : d.id,
      'area': area,
      'areaNombre': areaNombre,
      'description': description,
      'search': '$code ${d.id} $desc $description $area $areaNombre',
    };
  }

  bool _matchesCargoSuggestion(Map<String, String> m, String pattern) {
    final term = pattern.toLowerCase().trim();
    if (term.isEmpty) return true;
    return (m['search'] ?? '').toLowerCase().contains(term);
  }

  Future<List<Map<String, String>>> _fetchCostCenters(String pattern) async {
    final snap = await FirebaseFirestore.instance
        .collection(_ccCollection)
        .get();
    return snap.docs
        .map((d) {
          final data = d.data();
          return {'code': d.id, 'nombre': data['nombre'] as String? ?? ''};
        })
        .where(
          (m) => m['nombre']!.toLowerCase().contains(pattern.toLowerCase()),
        )
        .toList();
  }

  Future<List<Map<String, String>>> _fetchEmpleados(String pattern) async {
    final snap = await FirebaseFirestore.instance
        .collection(_usuariosCol)
        .where('empresas', arrayContains: widget.empresaId)
        .get();
    final term = pattern.toLowerCase();
    return snap.docs
        .where((d) {
          final data = d.data();
          final nombre = _buildNombre(data).toLowerCase();
          final cedula = d.id.toLowerCase();
          return term.isEmpty || nombre.contains(term) || cedula.contains(term);
        })
        .map((d) {
          final data = d.data();
          return {
            'cedula': d.id,
            'nombre': _buildNombre(data),
            'correo': (data['email'] as String?) ?? '',
          };
        })
        .toList();
  }

  // ── Organigrama PDF ───────────────────────────────────────────────────────

  // ---- árbol ---------------------------------------------------------------

  List<_OrgChartNode> _buildOrgTree() {
    final nodeMap = <String, _OrgChartNode>{};
    for (final doc in _currentDocs) {
      final m = _orgDataForCompany(doc.data());
      final cedula = _orgCedula(doc);
      final ui = _userCache[cedula];
      final nombre = (ui?.nombre.isNotEmpty == true)
          ? ui!.nombre
          : (m['nombre'] as String? ?? cedula);
      nodeMap[cedula] = _OrgChartNode(
        cedula: cedula,
        nombre: nombre,
        cargo: m['cargo'] as String? ?? '',
        area: m['area'] as String? ?? '',
      );
    }
    final hasParent = <String>{};
    for (final doc in _currentDocs) {
      final m = _orgDataForCompany(doc.data());
      final cedula = _orgCedula(doc);
      String jefeId = '';
      for (final k in ['jefe_directo_id', 'jefeId']) {
        final v = (m[k] as String?)?.trim() ?? '';
        if (v.isNotEmpty) {
          jefeId = v;
          break;
        }
      }
      if (jefeId.isNotEmpty && nodeMap.containsKey(jefeId)) {
        nodeMap[jefeId]!.children.add(nodeMap[cedula]!);
        hasParent.add(cedula);
      }
    }
    final roots = nodeMap.values
        .where((n) => !hasParent.contains(n.cedula))
        .toList();
    // Fallback: si no hay raíces (referencias circulares), mostrar todos sin jerarquía
    if (roots.isEmpty) return nodeMap.values.toList();
    return roots;
  }

  double _subtreeW(_OrgChartNode n) {
    if (n.children.isEmpty) return _cnW;
    final w =
        n.children.fold(0.0, (s, c) => s + _subtreeW(c) + _chGap) - _chGap;
    return max(_cnW, w);
  }

  void _assignLayout(_OrgChartNode n, double cx, double y) {
    n.x = cx - _cnW / 2;
    n.y = y;
    if (n.children.isEmpty) return;
    final total =
        n.children.fold(0.0, (s, c) => s + _subtreeW(c) + _chGap) - _chGap;
    var childCx = cx - total / 2;
    for (final c in n.children) {
      final w = _subtreeW(c);
      _assignLayout(c, childCx + w / 2, y + _cnH + _cvGap);
      childCx += w + _chGap;
    }
  }

  void _collectNodes(_OrgChartNode n, List<_OrgChartNode> list) {
    list.add(n);
    for (final c in n.children) _collectNodes(c, list);
  }

  // ---- colores por área (determinístico) -----------------------------------

  static const _areaFills = [
    PdfColor(0.99, 0.95, 0.85),
    PdfColor(0.87, 0.93, 0.99),
    PdfColor(0.88, 0.97, 0.90),
    PdfColor(0.97, 0.88, 0.97),
    PdfColor(0.99, 0.88, 0.88),
    PdfColor(0.88, 0.97, 0.97),
    PdfColor(0.97, 0.97, 0.88),
    PdfColor(0.88, 0.90, 0.99),
  ];
  static const _areaBorders = [
    PdfColor(0.76, 0.54, 0.26),
    PdfColor(0.18, 0.44, 0.78),
    PdfColor(0.12, 0.53, 0.25),
    PdfColor(0.49, 0.13, 0.60),
    PdfColor(0.71, 0.18, 0.18),
    PdfColor(0.00, 0.47, 0.47),
    PdfColor(0.55, 0.55, 0.00),
    PdfColor(0.18, 0.22, 0.65),
  ];

  // ---- generación del PDF (multipágina por área) --------------------------

  Future<void> _generateOrgChartPdf() async {
    if (_currentDocs.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No hay datos cargados. Espera a que cargue la lista.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }
    setState(() => _generatingPdf = true);
    try {
      // ── Fuente Arial (soporta español: tildes, ñ, etc.) ─────────────────
      final fontBytes = await rootBundle.load('assets/arial.ttf');
      final font = pw.Font.ttf(fontBytes);

      // ── Estilos ──────────────────────────────────────────────────────────
      pw.TextStyle ts(double sz, {PdfColor? color, bool bold = false}) =>
          pw.TextStyle(
            font: font,
            fontSize: sz,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: color,
          );

      const thColor = PdfColor(0.76, 0.54, 0.26); // ámbar corporativo
      const bgStripe = PdfColor(0.97, 0.97, 0.97);
      const bgHeader = PdfColor(0.94, 0.94, 0.94);

      // Paleta de colores por área (determinística)
      const areaPalette = <PdfColor>[
        PdfColor(0.76, 0.54, 0.26),
        PdfColor(0.18, 0.44, 0.78),
        PdfColor(0.12, 0.53, 0.25),
        PdfColor(0.49, 0.13, 0.60),
        PdfColor(0.71, 0.18, 0.18),
        PdfColor(0.00, 0.47, 0.47),
        PdfColor(0.55, 0.45, 0.00),
        PdfColor(0.18, 0.22, 0.65),
      ];

      // ── Agrupar por Establecimiento → Área → Cargo ───────────────────────
      // Establecimiento = centro_nombre (Centro de Costos)
      final byEst = <String, Map<String, List<_PdfRow>>>{};
      for (final doc in _currentDocs) {
        final m = _orgDataForCompany(doc.data());
        final cedula = _orgCedula(doc);
        final ui = _userCache[cedula];
        final nombre = (ui?.nombre.isNotEmpty == true)
            ? ui!.nombre
            : (m['nombre'] as String? ?? '—');
        final area = (m['area'] as String?)?.trim().isNotEmpty == true
            ? (m['area'] as String).trim()
            : 'Sin Área';
        final cargo = (m['cargo'] as String?)?.trim().isNotEmpty == true
            ? (m['cargo'] as String).trim()
            : 'Sin Cargo';
        final superior = _superiorLabel(m);
        final centroRaw = _centroLabel(m);
        final est = (centroRaw == '—' || centroRaw.isEmpty)
            ? 'Sin Establecimiento'
            : centroRaw;
        final correo = (ui?.email.isNotEmpty == true)
            ? ui!.email
            : (m['correo'] as String? ?? '');
        final jefeId = (m['jefe_directo_id'] as String?)?.trim() ?? '';

        byEst.putIfAbsent(est, () => {});
        byEst[est]!.putIfAbsent(area, () => []);
        byEst[est]![area]!.add(
          _PdfRow(
            cedula: cedula,
            nombre: nombre,
            cargo: cargo,
            superior: superior,
            centro: est,
            correo: correo,
            jefeId: jefeId,
          ),
        );
      }

      // Ordenar establecimientos y áreas; mover "Sin …" al final
      final sortedEst = byEst.keys.toList()..sort();
      if (sortedEst.remove('Sin Establecimiento')) {
        sortedEst.add('Sin Establecimiento');
      }
      // Dentro de cada área: ordenar por cargo, luego por nombre
      for (final est in sortedEst) {
        for (final area in byEst[est]!.keys) {
          byEst[est]![area]!.sort((a, b) {
            final c = a.cargo.compareTo(b.cargo);
            return c != 0 ? c : a.nombre.compareTo(b.nombre);
          });
        }
      }

      final totalEmpleados = _currentDocs.length;
      final totalAreas = byEst.values.fold(0, (s, m) => s + m.length);

      // ── Fecha ─────────────────────────────────────────────────────────────
      final now = DateTime.now();
      final fecha =
          '${now.day.toString().padLeft(2, '0')}/'
          '${now.month.toString().padLeft(2, '0')}/${now.year}';

      // ── Documento PDF ─────────────────────────────────────────────────────
      final pdf = pw.Document();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.fromLTRB(28, 24, 28, 24),

          // ── Encabezado de cada página ──────────────────────────────────────
          header: (ctx) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'Estructura Organizacional',
                    style: ts(16, color: thColor, bold: true),
                  ),
                  pw.Text(
                    '$totalEmpleados colaboradores  ·  '
                    '$totalAreas áreas  ·  $fecha',
                    style: ts(8, color: PdfColors.grey600),
                  ),
                ],
              ),
              pw.SizedBox(height: 5),
              pw.Divider(color: thColor, thickness: 0.7),
              pw.SizedBox(height: 6),
            ],
          ),

          // ── Pie de página ─────────────────────────────────────────────────
          footer: (ctx) => pw.Padding(
            padding: const pw.EdgeInsets.only(top: 4),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  widget.empresaId,
                  style: ts(7, color: PdfColors.grey500),
                ),
                pw.Text(
                  'Página ${ctx.pageNumber} de ${ctx.pagesCount}',
                  style: ts(7, color: PdfColors.grey500),
                ),
              ],
            ),
          ),

          // ── Contenido: Establecimiento → Área → Cargo ─────────────────────
          build: (ctx) {
            final widgets = <pw.Widget>[];
            var estIdx = 0;

            for (final est in sortedEst) {
              final areasMap = byEst[est]!;
              final estColor = areaPalette[estIdx % areaPalette.length];
              estIdx++;

              // ── Encabezado de Establecimiento ─────────────────────────────
              widgets.add(
                pw.Container(
                  color: estColor,
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  child: pw.Row(
                    children: [
                      pw.Expanded(
                        child: pw.Text(
                          '▪ $est',
                          style: ts(11, color: PdfColors.white, bold: true),
                        ),
                      ),
                      pw.Text(() {
                        final total = areasMap.values.fold(
                          0,
                          (s, l) => s + l.length,
                        );
                        return '$total colaborador${total == 1 ? '' : 'es'}';
                      }(), style: ts(8, color: PdfColors.white)),
                    ],
                  ),
                ),
              );

              // Ordenar áreas de este establecimiento
              final sortedAreas = areasMap.keys.toList()..sort();
              if (sortedAreas.remove('Sin Área')) sortedAreas.add('Sin Área');

              for (final area in sortedAreas) {
                final rows = areasMap[area]!;

                // Color de subencabezado de área (versión clara del color del est)
                final areaColor = PdfColor(
                  estColor.red * 0.5 + 0.5,
                  estColor.green * 0.5 + 0.5,
                  estColor.blue * 0.5 + 0.5,
                );

                // ── Subencabezado de Área ──────────────────────────────────
                widgets.add(
                  pw.Container(
                    color: areaColor,
                    padding: const pw.EdgeInsets.fromLTRB(20, 4, 10, 4),
                    child: pw.Row(
                      children: [
                        pw.Expanded(
                          child: pw.Text(
                            '  $area',
                            style: ts(9, color: PdfColors.white, bold: true),
                          ),
                        ),
                        pw.Text(
                          '${rows.length} colaborador${rows.length == 1 ? '' : 'es'}',
                          style: ts(7.5, color: PdfColors.white),
                        ),
                      ],
                    ),
                  ),
                );

                // ── Cabecera de columnas ───────────────────────────────────
                widgets.add(
                  pw.Container(
                    color: bgHeader,
                    padding: const pw.EdgeInsets.fromLTRB(30, 3, 10, 3),
                    child: pw.Row(
                      children: [
                        pw.Expanded(
                          flex: 26,
                          child: pw.Text('Nombre', style: ts(7.5, bold: true)),
                        ),
                        pw.Expanded(
                          flex: 12,
                          child: pw.Text('Cédula', style: ts(7.5, bold: true)),
                        ),
                        pw.Expanded(
                          flex: 20,
                          child: pw.Text('Cargo', style: ts(7.5, bold: true)),
                        ),
                        pw.Expanded(
                          flex: 22,
                          child: pw.Text(
                            'Jefe directo',
                            style: ts(7.5, bold: true),
                          ),
                        ),
                      ],
                    ),
                  ),
                );

                // ── Filas de empleados, agrupadas por cargo ────────────────
                String? lastCargo;
                for (var ri = 0; ri < rows.length; ri++) {
                  final row = rows[ri];

                  // Separador de Cargo (sin caja, solo guión + nombre)
                  if (row.cargo != lastCargo) {
                    lastCargo = row.cargo;
                    widgets.add(
                      pw.Padding(
                        padding: const pw.EdgeInsets.fromLTRB(34, 5, 10, 1),
                        child: pw.Row(
                          children: [
                            pw.Text(
                              '— ',
                              style: ts(7, color: PdfColors.grey500),
                            ),
                            pw.Text(
                              row.cargo,
                              style: ts(
                                7.5,
                                color: PdfColors.grey600,
                                bold: true,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  widgets.add(
                    pw.Container(
                      color: ri.isEven ? PdfColors.white : bgStripe,
                      padding: const pw.EdgeInsets.fromLTRB(40, 3, 10, 3),
                      child: pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Expanded(
                            flex: 26,
                            child: pw.Text(row.nombre, style: ts(8)),
                          ),
                          pw.Expanded(
                            flex: 12,
                            child: pw.Text(
                              row.cedula,
                              style: ts(7.5, color: PdfColors.grey700),
                            ),
                          ),
                          pw.Expanded(
                            flex: 20,
                            child: pw.Text(
                              row.cargo,
                              style: ts(7.5, color: PdfColors.grey600),
                            ),
                          ),
                          pw.Expanded(
                            flex: 22,
                            child: pw.Text(
                              row.superior,
                              style: ts(7.5, color: PdfColors.grey700),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                widgets.add(pw.SizedBox(height: 8));
              }
              widgets.add(pw.SizedBox(height: 16));
            }

            return widgets;
          },
        ),
      );

      final bytes = await pdf.save();
      await FileSaver.instance.saveFile(
        name:
            'organigrama_${widget.empresaId}_${DateTime.now().millisecondsSinceEpoch}',
        bytes: Uint8List.fromList(bytes),
        fileExtension: 'pdf',
        mimeType: MimeType.pdf,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al generar PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _generatingPdf = false);
    }
  }

  // ── Sincronización total TH ───────────────────────────────────────────────
  /// Mantiene consistentes TBL_ESTRUCTURA_ORGANIZACIONAL, TBL_CARGOS y TBL_AREAS:
  ///  0. Crea docs en TBL_ESTRUCTURA para usuarios de TBL_USUARIOS sin doc
  ///  1. Actualiza jefeNombre / jefe_cargo_desc de cada empleado usando el jefeId
  ///  2. Recalcula el array `cedulas` de cada cargo (empleados con ese cargo)
  ///  3. Recalcula el array `cedulas` de cada área (empleados en esa área)
  Future<int> _syncAllTH() async {
    final fs = FirebaseFirestore.instance;

    // ── Cargar datos base ───────────────────────────────────────────────────
    // La cédula es global y el mismo usuario puede pertenecer a varias
    // empresas. Se cargan todos los documentos para recuperar también los
    // legacy cuyo empresaId top-level apunta a otra empresa.
    final orgFut = fs.collection(_orgCollection).get();
    final usr1Fut = fs
        .collection(_usuariosCol)
        .where('empresas', arrayContains: widget.empresaId)
        .get();
    final usr2Fut = fs
        .collection(_usuariosCol)
        .where('empresaId', isEqualTo: widget.empresaId)
        .get();
    final cargosFut = fs
        .collection(_cargosCollection)
        .where('empresaId', isEqualTo: widget.empresaId)
        .get();
    final areasFut = fs
        .collection(_areasCollection)
        .where('empresaId', isEqualTo: widget.empresaId)
        .get();

    final results = await Future.wait([
      orgFut,
      usr1Fut,
      usr2Fut,
      cargosFut,
      areasFut,
    ]);
    final orgSnap = results[0];
    final usrSnap1 = results[1];
    final usrSnap2 = results[2];
    final cargosSnap = results[3];
    final areasSnap = results[4];

    // ── Mapas auxiliares ────────────────────────────────────────────────────
    // cédula → datos TBL_USUARIOS  (deduplicado por doc.id)
    final userMap = <String, Map<String, dynamic>>{};
    final userDocIds = <String>{}; // solo IDs canónicos de documento
    for (final d in [...usrSnap1.docs, ...usrSnap2.docs]) {
      if (userDocIds.add(d.id)) {
        userMap[d.id] = d.data();
        final ced = (d.data()['cedula'] as String?)?.trim() ?? '';
        if (ced.isNotEmpty && ced != d.id) userMap[ced] = d.data();
      }
    }

    // cédula → documento global de estructura. La información efectiva de la
    // empresa activa se construye más abajo desde empresasDetalle[empresaId].
    final orgRawMap = <String, Map<String, dynamic>>{};
    final orgRefs = <String, DocumentReference<Map<String, dynamic>>>{};
    for (final d in orgSnap.docs) {
      final cedula = _orgCedula(d);
      orgRawMap[cedula] = d.data();
      orgRefs[cedula] = d.reference;
    }
    final orgMap = <String, Map<String, dynamic>>{};

    // Helper: obtiene un campo de TBL_USUARIOS respetando empresasDetalle
    String _usrField(Map<String, dynamic> data, String key) {
      final detalle =
          ((data['empresasDetalle'] as Map<String, dynamic>?)?[widget.empresaId]
              as Map<String, dynamic>?) ??
          {};
      final d = (detalle[key] as String?)?.trim() ?? '';
      if (d.isNotEmpty) return d;
      return (data[key] as String?)?.trim() ?? '';
    }

    // ── Calcular actualizaciones ────────────────────────────────────────────
    final updates =
        <DocumentReference<Map<String, dynamic>>, Map<String, dynamic>>{};
    // Refs que deben hacerse con set() en lugar de update()
    final newRefs = <DocumentReference<Map<String, dynamic>>>{};

    void queueUpdate(
      DocumentReference<Map<String, dynamic>> ref,
      Map<String, dynamic> patch,
    ) {
      if (patch.isEmpty) return;
      if (updates.containsKey(ref)) {
        updates[ref]!.addAll(patch);
      } else {
        updates[ref] = patch;
      }
    }

    List<String> sortedUnique(Iterable<String> values) {
      final out =
          values
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toSet()
              .toList()
            ..sort();
      return out;
    }

    bool listChanged(List<dynamic> existing, List<String> next) {
      final a = existing
          .map((e) => e.toString())
          .where((e) => e.isNotEmpty)
          .toSet();
      final b = next.toSet();
      return a.length != b.length || !a.containsAll(b);
    }

    String textField(Map<String, dynamic> data, List<String> keys) {
      for (final key in keys) {
        final value = (data[key] as String?)?.trim() ?? '';
        if (value.isNotEmpty) return value;
      }
      return '';
    }

    Map<String, dynamic> userScope(Map<String, dynamic> data) {
      String area = _usrField(data, 'areaNombre');
      if (area.isEmpty) area = _usrField(data, 'area');
      final correo = _usrField(data, 'correo').isNotEmpty
          ? _usrField(data, 'correo')
          : (data['email'] ?? '').toString().trim();
      final centroCodigo = _usrField(data, 'centroCodigo').isNotEmpty
          ? _usrField(data, 'centroCodigo')
          : _usrField(data, 'centroId');
      return <String, dynamic>{
        'nombre': _buildNombre(data),
        'area': area,
        'areaNombre': area,
        'areaId': _usrField(data, 'areaId'),
        'cargo': _usrField(data, 'cargo'),
        'cargoId': _usrField(data, 'cargoId'),
        'correo': correo,
        'jefe_directo_id': _usrField(data, 'jefeId'),
        'jefeId': _usrField(data, 'jefeId'),
        'jefe_directo': _usrField(data, 'jefeNombre'),
        'jefeNombre': _usrField(data, 'jefeNombre'),
        'jefe_cargo_desc': _usrField(data, 'cargoJefe'),
        'cargoJefe': _usrField(data, 'cargoJefe'),
        'centro_nombre': _usrField(data, 'centroCostos'),
        'centroCostos': _usrField(data, 'centroCostos'),
        'centro_codigo': centroCodigo,
        'centroId': _usrField(data, 'centroId'),
      };
    }

    // 0) Asegurar un único documento global por cédula con un bloque
    // empresasDetalle por cada empresa. Nunca se reemplaza la estructura de
    // otra empresa al sincronizar la empresa activa.
    for (final docId in userDocIds) {
      final userData = userMap[docId]!;
      final raw = orgRawMap[docId];
      final fromUser = userScope(userData);
      final existingScope = raw == null
          ? <String, dynamic>{}
          : (getUserCompanyDetail(raw, widget.empresaId) ??
                (((raw['empresaId'] ?? '').toString().trim() ==
                        widget.empresaId)
                    ? Map<String, dynamic>.from(raw)
                    : <String, dynamic>{}));
      final effective = <String, dynamic>{...existingScope};
      for (final entry in fromUser.entries) {
        final value = entry.value;
        if (value != null && value.toString().trim().isNotEmpty) {
          effective[entry.key] = value;
        }
      }
      orgMap[docId] = effective;

      final ref = orgRefs[docId] ?? fs.collection(_orgCollection).doc(docId);
      orgRefs[docId] = ref;
      if (raw == null) {
        final newDoc = <String, dynamic>{
          'cedula': docId,
          'empresaId': widget.empresaId,
          'empresas': [widget.empresaId],
          ...effective,
          'empresasDetalle': {widget.empresaId: effective},
          'createdBySyncAt': FieldValue.serverTimestamp(),
        };
        queueUpdate(ref, newDoc);
        newRefs.add(ref);
        orgRawMap[docId] = newDoc;
        continue;
      }

      final patch = <String, dynamic>{};
      final empresas = (raw['empresas'] as List<dynamic>? ?? const [])
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toSet();
      if (!empresas.contains(widget.empresaId)) {
        patch['empresas'] = FieldValue.arrayUnion([widget.empresaId]);
      }
      if ((raw['cedula'] ?? '').toString().trim().isEmpty) {
        patch['cedula'] = docId;
      }

      for (final entry in effective.entries) {
        final current = existingScope[entry.key];
        if (current != entry.value) {
          patch['empresasDetalle.${widget.empresaId}.${entry.key}'] =
              entry.value;
        }
      }

      // Compatibilidad con lectores legacy: solo se actualiza top-level si
      // este documento ya tenía como principal la empresa activa.
      if ((raw['empresaId'] ?? '').toString().trim() == widget.empresaId) {
        for (final entry in effective.entries) {
          if (raw[entry.key] != entry.value) patch[entry.key] = entry.value;
        }
      }
      queueUpdate(ref, patch);
    }

    // 1) Propagar nombre/cargo del jefe dentro del scope de empresa activo.
    for (final entry in orgMap.entries) {
      final cedula = entry.key;
      final data = entry.value;
      // Buscar el jefeId: campo propio del form o importado de Excel
      final jefeId = (() {
        for (final k in ['jefe_directo_id', 'jefeId']) {
          final v = (data[k] as String?)?.trim() ?? '';
          if (v.isNotEmpty) return v;
        }
        // fallback: buscar por jefeNombre en userMap
        return '';
      })();
      if (jefeId.isEmpty) continue;

      // Nombre actual del jefe (de TBL_USUARIOS o TBL_ESTRUCTURA)
      String jefeNombre = '';
      final juData = userMap[jefeId];
      if (juData != null) jefeNombre = _buildNombre(juData);
      if (jefeNombre.isEmpty) {
        jefeNombre = (orgMap[jefeId]?['nombre'] as String?)?.trim() ?? '';
      }

      // Cargo actual del jefe (desde su propio doc en TBL_ESTRUCTURA)
      String jefeCargo = (orgMap[jefeId]?['cargo'] as String?)?.trim() ?? '';
      if (jefeCargo.isEmpty) {
        jefeCargo = (userMap[jefeId]?['cargo'] as String?)?.trim() ?? '';
      }

      final patch = <String, dynamic>{};
      if (jefeNombre.isNotEmpty && data['jefe_directo'] != jefeNombre) {
        patch['jefe_directo'] = jefeNombre;
      }
      if (jefeCargo.isNotEmpty && data['jefe_cargo_desc'] != jefeCargo) {
        patch['jefe_cargo_desc'] = jefeCargo;
      }
      if (patch.isNotEmpty) {
        final raw = orgRawMap[cedula] ?? const <String, dynamic>{};
        final scopedPatch = <String, dynamic>{};
        for (final change in patch.entries) {
          scopedPatch['empresasDetalle.${widget.empresaId}.${change.key}'] =
              change.value;
          if ((raw['empresaId'] ?? '').toString().trim() == widget.empresaId) {
            scopedPatch[change.key] = change.value;
          }
        }
        final ref =
            orgRefs[cedula] ?? fs.collection(_orgCollection).doc(cedula);
        queueUpdate(ref, scopedPatch);
        orgMap[cedula] = {...data, ...patch};
      }
    }

    // 2) Recalcular cargos: cedulas, ocupantes, subordinados y cargo padre.
    final cargoById = <String, DocumentSnapshot<Map<String, dynamic>>>{};
    final cargoByName = <String, DocumentSnapshot<Map<String, dynamic>>>{};
    for (final cargoDoc in cargosSnap.docs) {
      final data = cargoDoc.data();
      cargoById[cargoDoc.id] = cargoDoc;
      final nombre = textField(data, ['nombre', 'descripcion']);
      if (nombre.isNotEmpty) cargoByName[nombre.toLowerCase()] = cargoDoc;
    }

    final cargoCedulasById = <String, Set<String>>{};
    final cargoNamesById = <String, Set<String>>{};
    final cargoByOccupant = <String, String>{};
    for (final entry in orgMap.entries) {
      final cedula = entry.key.trim();
      final data = entry.value;
      if (cedula.isEmpty) continue;
      final cargoId = textField(data, ['cargoId']);
      final cargoName = textField(data, ['cargo']);
      final cargoDoc =
          cargoById[cargoId] ?? cargoByName[cargoName.toLowerCase()];
      if (cargoDoc == null) continue;

      cargoCedulasById.putIfAbsent(cargoDoc.id, () => <String>{}).add(cedula);
      final nombre = textField(data, ['nombre']);
      cargoNamesById
          .putIfAbsent(cargoDoc.id, () => <String>{})
          .add(nombre.isNotEmpty ? nombre : cedula);
      cargoByOccupant[cedula] = cargoDoc.id;
    }

    final subIdsByCargoId = <String, Set<String>>{};
    final subNamesByCargoId = <String, Set<String>>{};
    for (final entry in orgMap.entries) {
      final cedula = entry.key.trim();
      final data = entry.value;
      if (cedula.isEmpty) continue;

      final jefeId = textField(data, ['jefe_directo_id', 'jefeId']);
      var jefeCargoId = cargoByOccupant[jefeId];
      if (jefeCargoId == null) {
        final jefeCargo = textField(data, ['jefe_cargo_desc', 'cargoJefe']);
        jefeCargoId = cargoByName[jefeCargo.toLowerCase()]?.id;
      }
      if (jefeCargoId == null) continue;

      subIdsByCargoId.putIfAbsent(jefeCargoId, () => <String>{}).add(cedula);
      final nombre = textField(data, ['nombre']);
      subNamesByCargoId
          .putIfAbsent(jefeCargoId, () => <String>{})
          .add(nombre.isNotEmpty ? nombre : cedula);
    }

    for (final cargoDoc in cargosSnap.docs) {
      final data = cargoDoc.data();
      final cedulas = sortedUnique(cargoCedulasById[cargoDoc.id] ?? <String>{});
      final assignedNames = sortedUnique(
        cargoNamesById[cargoDoc.id] ?? <String>{},
      );
      final subordinateIds = sortedUnique(
        subIdsByCargoId[cargoDoc.id] ?? <String>{},
      );
      final subordinateNames = sortedUnique(
        subNamesByCargoId[cargoDoc.id] ?? <String>{},
      );

      final patch = <String, dynamic>{};
      if (listChanged(data['cedulas'] as List<dynamic>? ?? const [], cedulas)) {
        patch['cedulas'] = cedulas;
      }
      if (listChanged(
        data['assigned_users_ids'] as List<dynamic>? ?? const [],
        cedulas,
      )) {
        patch['assigned_users_ids'] = cedulas;
      }
      if (listChanged(
        data['assigned_users_names'] as List<dynamic>? ?? const [],
        assignedNames,
      )) {
        patch['assigned_users_names'] = assignedNames;
      }
      if (listChanged(
        data['subordinates_ids'] as List<dynamic>? ?? const [],
        subordinateIds,
      )) {
        patch['subordinates_ids'] = subordinateIds;
      }
      if (listChanged(
        data['subordinates_names'] as List<dynamic>? ?? const [],
        subordinateNames,
      )) {
        patch['subordinates_names'] = subordinateNames;
      }

      String parentCargoId = '';
      String parentCargoName = '';
      for (final cedula in cedulas) {
        final person = orgMap[cedula];
        if (person == null) continue;
        final parentName = textField(person, ['jefe_cargo_desc', 'cargoJefe']);
        final parentDoc = cargoByName[parentName.toLowerCase()];
        if (parentDoc == null || parentDoc.id == cargoDoc.id) continue;
        parentCargoId = parentDoc.id;
        parentCargoName = textField(parentDoc.data() ?? {}, [
          'nombre',
          'descripcion',
        ]);
        break;
      }
      if (parentCargoId.isNotEmpty && data['parent_cargo'] != parentCargoId) {
        patch['parent_cargo'] = parentCargoId;
      }
      if (parentCargoName.isNotEmpty &&
          data['parent_desc'] != parentCargoName) {
        patch['parent_desc'] = parentCargoName;
      }

      queueUpdate(cargoDoc.reference, patch);
    }

    // 3) Recalcular cedulas[] en TBL_AREAS desde el mapa efectivo de estructura.
    final areaCedulas = <String, Set<String>>{};
    for (final entry in orgMap.entries) {
      final area = textField(entry.value, ['area']);
      if (area.isNotEmpty) {
        areaCedulas.putIfAbsent(area, () => <String>{}).add(entry.key);
      }
    }
    for (final areaDoc in areasSnap.docs) {
      final nombre = (areaDoc.data()['nombre'] as String?)?.trim() ?? '';
      final cedulas = sortedUnique(areaCedulas[nombre] ?? <String>{});
      final existing = areaDoc.data()['cedulas'] as List<dynamic>? ?? const [];
      if (listChanged(existing, cedulas)) {
        queueUpdate(areaDoc.reference, {'cedulas': cedulas});
      }
    }

    // ── Ejecutar en lotes de 490 ────────────────────────────────────────────
    if (updates.isEmpty) return 0;
    final entries = updates.entries.toList();
    for (var i = 0; i < entries.length; i += 490) {
      final batch = fs.batch();
      final chunk = entries.sublist(i, min(i + 490, entries.length));
      for (final e in chunk) {
        if (newRefs.contains(e.key)) {
          // Doc nuevo: usar set para crearlo
          batch.set(e.key, e.value);
        } else {
          // Doc existente: usar update para no borrar campos no tocados
          batch.update(e.key, e.value);
        }
      }
      await batch.commit();
    }
    return updates.length;
  }

  // ── Exportar a Excel ───────────────────────────────────────────────────────

  Future<void> _exportExcel() async {
    if (_currentDocs.isEmpty) return;
    setState(() => _exporting = true);
    try {
      final ex = Excel.createExcel();
      final sheetName = 'Estructura';
      final sheet = ex[sheetName];
      // eliminar hoja por defecto
      ex.delete('Sheet1');

      // Estilo de encabezado
      final headerStyle = CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.fromHexString('#C28942'),
        fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
        horizontalAlign: HorizontalAlign.Center,
      );

      final headers = [
        'Cédula',
        'Nombre Completo',
        'Estado laboral',
        'Cargo',
        'Área',
        'Correo',
        'Teléfono',
        'Nivel Educativo',
        'Superior / Jefe',
        'Centro de Costos',
        'Rol',
        'Último cambio de estado',
        'Motivo del estado',
      ];
      for (var c = 0; c < headers.length; c++) {
        final cell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0),
        );
        cell.value = TextCellValue(headers[c]);
        cell.cellStyle = headerStyle;
        sheet.setColumnWidth(c, 24);
      }

      // Filas de datos
      var rowIdx = 1;
      for (final d in _currentDocs) {
        final m = _orgDataForCompany(d.data());
        final cedula = _orgCedula(d);
        final ui = _userCache[cedula];

        final nombre = (ui?.nombre.isNotEmpty == true)
            ? ui!.nombre
            : (m['nombre'] as String? ?? '');
        final cargo = m['cargo'] as String? ?? '';
        final area = m['area'] as String? ?? '';
        final email = (ui?.email.isNotEmpty == true)
            ? ui!.email
            : (m['correo'] as String? ?? '');
        final tel = ui?.telefono ?? '';
        final nivelEd = ui?.nivelEducativo ?? '';
        final superior = _superiorLabel(m);
        final centro = _centroLabel(m);
        final rol = m['rol'] as String? ?? '';
        final estado = _statusOf(m);
        final estadoActualizado = _formatTimestamp(m['estadoActualizadoAt']);
        final motivoEstado = (m['motivoEstado'] ?? '').toString();

        final row = [
          cedula,
          nombre,
          estado == PersonnelStatusService.active ? 'Activo' : 'Inactivo',
          cargo,
          area,
          email,
          tel,
          nivelEd,
          superior,
          centro,
          rol,
          estadoActualizado,
          motivoEstado,
        ];
        for (var c = 0; c < row.length; c++) {
          sheet
              .cell(
                CellIndex.indexByColumnRow(columnIndex: c, rowIndex: rowIdx),
              )
              .value = TextCellValue(
            row[c],
          );
        }
        rowIdx++;
      }

      final bytes = ex.encode();
      if (bytes == null) return;
      await FileSaver.instance.saveFile(
        name:
            'personal_${widget.empresaId}_${DateTime.now().millisecondsSinceEpoch}',
        bytes: Uint8List.fromList(bytes),
        fileExtension: 'xlsx',
        mimeType: MimeType.microsoftExcel,
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  // ── Formulario de alta/edición ─────────────────────────────────────────────

  Future<void> _openForm({DocumentSnapshot<Map<String, dynamic>>? doc}) async {
    final isNew = doc == null;
    final data = doc == null
        ? <String, dynamic>{}
        : _orgDataForCompany(doc.data() ?? const <String, dynamic>{});

    final initialId = doc == null ? '' : _orgCedula(doc);

    // Fusionar datos de TBL_ESTRUCTURA_ORGANIZACIONAL con caché de TBL_USUARIOS
    final ui = _userCache[initialId];

    final initialName = (() {
      final orgNombre = (data['nombre'] as String?)?.trim() ?? '';
      if (orgNombre.isNotEmpty) return orgNombre;
      return ui?.nombre ?? '';
    })();

    final initialArea = data['area'] as String? ?? '';
    final initialCargo = data['cargo'] as String? ?? '';

    final initialBossCode = data['jefe_cargo'] as String? ?? '';

    // Cargo del jefe: org doc → caché TBL_USUARIOS → lookup TBL_CARGOS
    String initialBossDesc = '';
    for (final k in ['jefe_cargo_desc', 'cargoJefe']) {
      final v = (data[k] as String?)?.trim() ?? '';
      if (v.isNotEmpty) {
        initialBossDesc = v;
        break;
      }
    }
    if (initialBossDesc.isEmpty) initialBossDesc = ui?.cargoJefe ?? '';
    if (initialBossDesc.isEmpty && initialBossCode.isNotEmpty) {
      final bSnap = await FirebaseFirestore.instance
          .collection(_cargosCollection)
          .doc(initialBossCode)
          .get();
      final bd = bSnap.data();
      if (bd != null) {
        final n = (bd['nombre'] as String?)?.trim() ?? '';
        initialBossDesc = n.isNotEmpty
            ? n
            : (bd['descripcion'] as String?)?.trim() ?? '';
      }
    }

    // Nombre del jefe: org doc → caché TBL_USUARIOS
    String initialBossName = '';
    for (final k in ['jefe_directo', 'jefeNombre']) {
      final v = (data[k] as String?)?.trim() ?? '';
      if (v.isNotEmpty) {
        initialBossName = v;
        break;
      }
    }
    if (initialBossName.isEmpty) initialBossName = ui?.jefeNombre ?? '';

    // ID del jefe
    String initialBossDirectId = data['jefe_directo_id'] as String? ?? '';
    if (initialBossDirectId.isEmpty) initialBossDirectId = ui?.jefeId ?? '';

    // Correo: org doc → correo laboral caché → email caché
    final initialMail = (() {
      for (final k in ['correo', 'email']) {
        final v = (data[k] as String?)?.trim() ?? '';
        if (v.isNotEmpty) return v;
      }
      return ui?.bestEmail ?? '';
    })();

    // Centro de costos: org doc → caché TBL_USUARIOS
    String initialCentroCode = data['centro_codigo'] as String? ?? '';
    String initialCentroName = data['centro_nombre'] as String? ?? '';
    if (initialCentroName.isEmpty && ui != null && ui.centroCostos.isNotEmpty) {
      initialCentroName = ui.centroCostos;
      initialCentroCode = ui.centroCodigo.isNotEmpty
          ? ui.centroCodigo
          : ui.centroId;
    }

    final ctrId = TextEditingController(text: initialId);
    final ctrName = TextEditingController(text: initialName);
    final ctrArea = TextEditingController(text: initialArea);
    final ctrCargo = TextEditingController(text: initialCargo);
    final ctrBossCargo = TextEditingController(text: initialBossDesc);
    final ctrBossName = TextEditingController(text: initialBossName);
    final ctrMail = TextEditingController(text: initialMail);
    final ctrCentro = TextEditingController(text: initialCentroName);

    String selectedArea = initialArea;
    String selectedBossCode = initialBossCode;
    String selectedBossDirectId = initialBossDirectId;
    String? selectedCentroCode = initialCentroCode.isEmpty
        ? null
        : initialCentroCode;

    // ── Accesos a módulos ──────────────────────────────────────────────────
    // Se resuelve antes de abrir el formulario para que Talento Humano decida
    // en el mismo acto qué va a usar la persona. Los módulos apagados para la
    // empresa y los de Admin no se ofrecen aquí (ver PersonnelAccessService).
    final modulosDisponibles = _accessService.modulosDisponibles(
      await _accessService.disabledAppIds(widget.empresaId),
    );
    var appsActuales = isNew
        ? <String>{}
        : await _accessService.loadApps(
            userId: initialId,
            empresaId: widget.empresaId,
          );
    var appsNoAdministradas = PersonnelAccessService.noAdministrados(
      actuales: appsActuales,
      administrables: modulosDisponibles,
    );
    // Cédula cuyos accesos reales están cargados en el selector. Si al guardar
    // no coincide con la que quedó escrita (alguien la digitó a mano y ya
    // existía), no se pisa lo que la persona tenía: solo se suma.
    var appsCargadasPara = isNew ? '' : initialId;
    var appsSeleccionadas = isNew
        ? modulosDisponibles
              .where(
                (m) => kDefaultPersonnelApps.any(
                  (id) => appIdsEquivalent(id, m.appId),
                ),
              )
              .map((m) => m.appId)
              .toSet()
        : appsActuales
              .where(
                (app) => modulosDisponibles.any(
                  (m) => appIdsEquivalent(m.appId, app),
                ),
              )
              .toSet();
    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: Text(
            isNew ? 'Agregar colaborador' : 'Editar colaborador',
            style: const TextStyle(
              fontFamily: _kFontFamily,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              children: [
                // ID / empleado
                if (isNew)
                  TypeAheadField<Map<String, String>>(
                    textFieldConfiguration: TextFieldConfiguration(
                      controller: ctrId,
                      decoration: const InputDecoration(
                        labelText: 'Identificación',
                        hintText: 'Buscar por nombre o cédula…',
                      ),
                    ),
                    suggestionsCallback: _fetchEmpleados,
                    itemBuilder: (_, m) => ListTile(
                      title: Text(m['nombre']!),
                      subtitle: Text('CC: ${m['cedula']}'),
                    ),
                    onSuggestionSelected: (m) {
                      setStateDialog(() {
                        ctrId.text = m['cedula']!;
                        ctrName.text = m['nombre']!;
                        ctrMail.text = m['correo']!;
                      });
                      // La persona puede existir ya en TBL_USUARIOS: se
                      // muestran sus accesos reales para no reemplazarlos a
                      // ciegas con los de una persona nueva.
                      final cedulaElegida = m['cedula']!;
                      _accessService
                          .loadApps(
                            userId: cedulaElegida,
                            empresaId: widget.empresaId,
                          )
                          .then((reales) {
                            // Pudo cerrarse el diálogo o elegirse a otra
                            // persona mientras se resolvía la consulta.
                            if (!ctx.mounted || ctrId.text != cedulaElegida) {
                              return;
                            }
                            setStateDialog(() {
                              appsActuales = reales;
                              appsCargadasPara = cedulaElegida;
                              appsNoAdministradas =
                                  PersonnelAccessService.noAdministrados(
                                    actuales: reales,
                                    administrables: modulosDisponibles,
                                  );
                              // Si la persona aún no existe se conserva la
                              // preselección por defecto.
                              if (reales.isNotEmpty) {
                                appsSeleccionadas = reales
                                    .where(
                                      (app) => modulosDisponibles.any(
                                        (mod) =>
                                            appIdsEquivalent(mod.appId, app),
                                      ),
                                    )
                                    .toSet();
                              }
                            });
                          })
                          .catchError((_) {});
                    },
                    minCharsForSuggestions: 0,
                    noItemsFoundBuilder: (_) =>
                        const ListTile(title: Text('Sin resultados')),
                  )
                else
                  TextField(
                    controller: ctrId,
                    decoration: const InputDecoration(
                      labelText: 'Identificación',
                    ),
                    readOnly: true,
                  ),
                const SizedBox(height: 8),
                TextField(
                  controller: ctrName,
                  decoration: const InputDecoration(
                    labelText: 'Nombre completo',
                  ),
                ),
                const SizedBox(height: 8),
                // ── Área: solo TBL_AREAS, con descripción ──────────────────────
                TypeAheadField<Map<String, String>>(
                  textFieldConfiguration: TextFieldConfiguration(
                    controller: ctrArea,
                    decoration: const InputDecoration(labelText: 'Área'),
                  ),
                  suggestionsCallback: _fetchAreas,
                  itemBuilder: (_, a) => ListTile(
                    title: Text(a['nombre']!),
                    subtitle: a['descripcion']!.isNotEmpty
                        ? Text(
                            a['descripcion']!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF64748B),
                            ),
                          )
                        : null,
                  ),
                  onSuggestionSelected: (a) {
                    setStateDialog(() {
                      ctrArea.text = a['nombre']!;
                      selectedArea = a['nombre']!;
                      // Al cambiar área, limpiar cargo y jefe (son dependientes)
                      ctrCargo.clear();
                      ctrBossCargo.clear();
                      ctrBossName.clear();
                      selectedBossCode = '';
                      selectedBossDirectId = '';
                    });
                  },
                  minCharsForSuggestions: 0,
                ),
                const SizedBox(height: 8),
                // ── Cargo: solo TBL_CARGOS del área seleccionada ───────────────
                TypeAheadField<Map<String, String>>(
                  textFieldConfiguration: TextFieldConfiguration(
                    controller: ctrCargo,
                    decoration: const InputDecoration(
                      labelText: 'Cargo',
                      hintText: 'Selecciona primero un área…',
                    ),
                  ),
                  suggestionsCallback: (p) =>
                      _fetchCargosForArea(p, selectedArea),
                  itemBuilder: (_, m) => ListTile(
                    title: Text(m['desc']!),
                    subtitle: Text(
                      [
                        if ((m['area'] ?? '').isNotEmpty) 'Área: ${m['area']}',
                        if ((m['cargoId'] ?? '').isNotEmpty) m['cargoId']!,
                      ].join(' · '),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  onSuggestionSelected: (m) {
                    setStateDialog(() {
                      ctrCargo.text = m['desc']!;
                      selectedBossCode = m['code']!;
                      // Al cambiar cargo también limpiar jefe
                      ctrBossCargo.clear();
                      ctrBossName.clear();
                      selectedBossDirectId = '';
                    });
                  },
                  minCharsForSuggestions: 0,
                ),
                const SizedBox(height: 8),
                TypeAheadField<Map<String, String>>(
                  textFieldConfiguration: TextFieldConfiguration(
                    controller: ctrBossCargo,
                    decoration: const InputDecoration(
                      labelText: 'Cargo del jefe directo',
                    ),
                  ),
                  suggestionsCallback: _fetchCargos,
                  itemBuilder: (_, m) => ListTile(title: Text(m['desc']!)),
                  onSuggestionSelected: (m) async {
                    final code = m['code']!;
                    final snap = await FirebaseFirestore.instance
                        .collection(_cargosCollection)
                        .doc(code)
                        .get();
                    final bd = snap.data();
                    final n = (bd?['nombre'] as String?)?.trim() ?? '';
                    final desc = n.isNotEmpty
                        ? n
                        : (bd?['descripcion'] as String?)?.trim() ?? m['desc']!;
                    setStateDialog(() {
                      ctrBossCargo.text = desc;
                      ctrBossName.clear();
                      selectedBossCode = code;
                      selectedBossDirectId = '';
                    });
                  },
                  minCharsForSuggestions: 0,
                ),
                const SizedBox(height: 8),
                // ── Jefe directo: personas con el cargo seleccionado ──────────
                TypeAheadField<Map<String, String>>(
                  textFieldConfiguration: TextFieldConfiguration(
                    controller: ctrBossName,
                    decoration: const InputDecoration(
                      labelText: 'Jefe directo',
                      hintText: 'Selecciona primero el cargo del jefe…',
                    ),
                  ),
                  suggestionsCallback: (pattern) async {
                    final bossCargoName = ctrBossCargo.text.trim();
                    if (bossCargoName.isEmpty) return [];
                    return _currentDocs
                        .map((d) {
                          final scoped = _orgDataForCompany(d.data());
                          final nombre =
                              (scoped['nombre'] as String?)?.trim() ?? '';
                          final cedula = _orgCedula(d);
                          final display = nombre.isNotEmpty ? nombre : cedula;
                          return {
                            'id': cedula,
                            'nombre': display,
                            'cargo': (scoped['cargo'] ?? '').toString(),
                          };
                        })
                        .where(
                          (m) =>
                              m['cargo'] == bossCargoName &&
                              (pattern.isEmpty ||
                                  m['nombre']!.toLowerCase().contains(
                                    pattern.toLowerCase(),
                                  )),
                        )
                        .toList();
                  },
                  itemBuilder: (_, m) => ListTile(
                    title: Text(m['nombre']!),
                    subtitle: Text(
                      'Cédula: ${m['id']!}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  onSuggestionSelected: (m) {
                    setStateDialog(() {
                      ctrBossName.text = m['nombre']!;
                      selectedBossDirectId = m['id']!;
                    });
                  },
                  minCharsForSuggestions: 0,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: ctrMail,
                  decoration: const InputDecoration(
                    labelText: 'Correo electrónico',
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 8),
                TypeAheadField<Map<String, String>>(
                  textFieldConfiguration: TextFieldConfiguration(
                    controller: ctrCentro,
                    decoration: const InputDecoration(
                      labelText: 'Centro de costos',
                    ),
                  ),
                  suggestionsCallback: _fetchCostCenters,
                  itemBuilder: (_, m) => ListTile(title: Text(m['nombre']!)),
                  onSuggestionSelected: (m) {
                    setStateDialog(() {
                      ctrCentro.text = m['nombre']!;
                      selectedCentroCode = m['code']!;
                    });
                  },
                  minCharsForSuggestions: 0,
                ),
                const SizedBox(height: 16),
                const Divider(),
                Theme(
                  data: Theme.of(
                    ctx,
                  ).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    initiallyExpanded: isNew,
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: const EdgeInsets.only(bottom: 8),
                    leading: const Icon(
                      Icons.apps_rounded,
                      color: _kPrimaryColor,
                    ),
                    title: const Text(
                      'Qué va a usar en la app',
                      style: TextStyle(
                        fontFamily: _kFontFamily,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    subtitle: Text(
                      appsSeleccionadas.isEmpty
                          ? 'Notificaciones y calendario'
                          : '${appsSeleccionadas.length} módulo(s) + '
                                'notificaciones y calendario',
                      style: const TextStyle(fontSize: 12),
                    ),
                    children: [
                      PersonnelAccessPicker(
                        densa: true,
                        seleccion: appsSeleccionadas,
                        modulos: modulosDisponibles,
                        gestionadosPorAdmin: appsNoAdministradas,
                        onChanged: (next) =>
                            setStateDialog(() => appsSeleccionadas = next),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Cancelar',
                style: TextStyle(fontFamily: _kFontFamily),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _kPrimaryColor),
              onPressed: () async {
                final id = ctrId.text.trim();
                if (id.isEmpty) return;
                final docRef = FirebaseFirestore.instance
                    .collection(_orgCollection)
                    .doc(id);
                final payload = <String, dynamic>{
                  'nombre': ctrName.text.trim(),
                  'area': ctrArea.text.trim(),
                  'areaNombre': ctrArea.text.trim(),
                  'cargo': ctrCargo.text.trim(),
                  'jefe_cargo': selectedBossCode,
                  'jefe_cargo_desc': ctrBossCargo.text.trim(),
                  'cargoJefe': ctrBossCargo.text.trim(),
                  'jefe_directo': ctrBossName.text.trim(),
                  'jefe_directo_id': selectedBossDirectId,
                  'jefeNombre': ctrBossName.text.trim(),
                  'jefeId': selectedBossDirectId,
                  'correo': ctrMail.text.trim(),
                  'centro_codigo': selectedCentroCode ?? '',
                  'centro_nombre': ctrCentro.text.trim(),
                  'centroId': selectedCentroCode ?? '',
                  'centroCostos': ctrCentro.text.trim(),
                  'estado': _statusOf(data),
                  'updatedAt': FieldValue.serverTimestamp(),
                };
                final orgSnap = await docRef.get();
                final userRef = FirebaseFirestore.instance
                    .collection(_usuariosCol)
                    .doc(id);
                final userSnap = await userRef.get();
                final batch = FirebaseFirestore.instance.batch();

                if (!orgSnap.exists) {
                  batch.set(docRef, {
                    'cedula': id,
                    'empresaId': widget.empresaId,
                    'empresas': [widget.empresaId],
                    ...payload,
                    'empresasDetalle': {widget.empresaId: payload},
                    'createdAt': FieldValue.serverTimestamp(),
                  });
                } else {
                  final raw = orgSnap.data() ?? const <String, dynamic>{};
                  final update = <String, dynamic>{
                    'cedula': id,
                    'empresas': FieldValue.arrayUnion([widget.empresaId]),
                  };
                  for (final entry in payload.entries) {
                    update['empresasDetalle.${widget.empresaId}.${entry.key}'] =
                        entry.value;
                    if ((raw['empresaId'] ?? '').toString().trim() ==
                        widget.empresaId) {
                      update[entry.key] = entry.value;
                    }
                  }
                  batch.update(docRef, update);
                }

                // TBL_USUARIOS se mantiene SIEMPRE en sincronía: sin doc de
                // usuario (o sin la empresa en `empresas`) la persona no
                // aparece en Rutas, Crear tarea ni en los directorios.
                const scopedKeys = [
                  'area',
                  'areaNombre',
                  'cargo',
                  'correo',
                  'jefeId',
                  'jefeNombre',
                  'cargoJefe',
                  'centroId',
                  'centroCostos',
                  'estadoLaboral',
                ];
                final userData = userSnap.data() ?? const <String, dynamic>{};
                final asignaClaveTemporal =
                    !userSnap.exists ||
                    personnelNeedsTemporaryPassword(userData);
                final detalle = <String, dynamic>{
                  for (final key in scopedKeys)
                    key: payload[key == 'estadoLaboral' ? 'estado' : key] ?? '',
                };
                // Al crear el doc esta empresa queda como la primaria.
                final esPrimaria =
                    !userSnap.exists ||
                    (userData['empresaId'] ?? '').toString().trim() ==
                        widget.empresaId;

                if (userSnap.exists) {
                  // update() admite rutas con punto: no pisa otras empresas.
                  final userUpdate = <String, dynamic>{
                    'cedula': id,
                    'empresas': FieldValue.arrayUnion([widget.empresaId]),
                    'updatedAt': FieldValue.serverTimestamp(),
                  };
                  detalle.forEach((key, value) {
                    userUpdate['empresasDetalle.${widget.empresaId}.$key'] =
                        value;
                    if (esPrimaria && key != 'estadoLaboral') {
                      userUpdate[key] = value;
                    }
                  });
                  // Cuentas creadas antes, que quedaron sin forma de entrar:
                  // se les asigna la temporal. A quien ya ingresó alguna vez
                  // no se le toca la clave (ver personnelNeedsTemporaryPassword).
                  if (personnelNeedsTemporaryPassword(userData)) {
                    userUpdate.addAll(
                      personnelAccessCredentials(const <String, dynamic>{}),
                    );
                  }
                  batch.update(userRef, userUpdate);
                } else {
                  // set() NO interpreta los puntos, así que va anidado.
                  final nombreCompleto = ctrName.text.trim();
                  batch.set(userRef, {
                    'usuario': id,
                    'cedula': id,
                    'tipo_documento': 'CC',
                    'nombre': nombreCompleto,
                    'nombres': nombreCompleto,
                    'apellidos': '',
                    'empresaId': widget.empresaId,
                    'empresas': [widget.empresaId],
                    'empresasDetalle': {widget.empresaId: detalle},
                    for (final entry in detalle.entries)
                      if (entry.key != 'estadoLaboral') entry.key: entry.value,
                    // `estado` global controla el login.
                    'estado': 'activo',
                    'createdAt': FieldValue.serverTimestamp(),
                    'updatedAt': FieldValue.serverTimestamp(),
                    // Contraseña temporal para que la persona pueda entrar
                    // el mismo día, igual que al registrar una contratación.
                    // La cambia en su primer ingreso.
                    ...personnelAccessCredentials(const <String, dynamic>{}),
                  }, SetOptions(merge: true));
                }
                batch.set(
                  FirebaseFirestore.instance
                      .collection('TBL_EMPLEADOS')
                      .doc('${widget.empresaId}_$id'),
                  {
                    'empresaId': widget.empresaId,
                    'cedula': id,
                    'nombres': ctrName.text.trim(),
                    'correo': ctrMail.text.trim(),
                    'areaNombre': ctrArea.text.trim(),
                    'cargoNombre': ctrCargo.text.trim(),
                    'centroId': selectedCentroCode ?? '',
                    'centroCostos': ctrCentro.text.trim(),
                    'jefeId': selectedBossDirectId,
                    'jefeNombre': ctrBossName.text.trim(),
                    'cargoJefe': ctrBossCargo.text.trim(),
                    'estado': _statusOf(data),
                    'updatedAt': FieldValue.serverTimestamp(),
                    if (isNew) 'createdAt': FieldValue.serverTimestamp(),
                  },
                  SetOptions(merge: true),
                );
                await batch.commit();

                // Los accesos se escriben después del batch porque
                // `saveApps` necesita leer el documento ya creado para no
                // pisar los módulos de la persona en otras empresas.
                try {
                  final enBd = await _accessService.loadApps(
                    userId: id,
                    empresaId: widget.empresaId,
                  );
                  final apps = appsCargadasPara == id
                      ? PersonnelAccessService.combinarConNoAdministrados(
                          actuales: enBd.isEmpty ? appsActuales : enBd,
                          seleccion: appsSeleccionadas,
                          administrables: modulosDisponibles,
                        )
                      // Nunca se mostraron los accesos de esta cédula, así
                      // que marcar aquí no puede quitarle nada.
                      : {...enBd, ...appsSeleccionadas};
                  await _accessService.saveApps(
                    userId: id,
                    empresaId: widget.empresaId,
                    apps: apps,
                    actorId: widget.userId,
                  );
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'La persona se guardó, pero no se pudieron '
                          'actualizar sus accesos: $e',
                        ),
                      ),
                    );
                  }
                }
                if (!mounted) return;
                if (asignaClaveTemporal) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      duration: const Duration(seconds: 8),
                      content: Text(
                        'Colaborador guardado. Usuario: $id · '
                        'Contraseña temporal: $personnelTemporaryPassword. '
                        'Debe cambiarla al ingresar.',
                      ),
                    ),
                  );
                }
                Navigator.pop(context);
              },
              child: Text(
                isNew ? 'Crear' : 'Guardar',
                style: const TextStyle(fontFamily: _kFontFamily),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _changeEmployeeStatus({
    required String cedula,
    required String nombre,
    required Map<String, dynamic> data,
    required bool activate,
  }) async {
    final reasonCtrl = TextEditingController();
    final verb = activate ? 'reactivar' : 'inactivar';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          activate ? 'Reactivar colaborador' : 'Inactivar colaborador',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Se va a $verb a ${nombre.isNotEmpty ? nombre : cedula}. '
              'El registro, los documentos y su historial se conservarán.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: reasonCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: activate
                    ? 'Motivo de reactivación (opcional)'
                    : 'Motivo de retiro o inactivación',
                hintText: activate
                    ? 'Ej. Reingreso a la compañía'
                    : 'Ej. Terminación de contrato',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: Icon(activate ? Icons.person_add_alt_1 : Icons.person_off),
            label: Text(activate ? 'Reactivar' : 'Inactivar'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      reasonCtrl.dispose();
      return;
    }

    try {
      await _personnelStatus.changeStatus(
        empresaId: widget.empresaId,
        cedula: cedula,
        status: activate
            ? PersonnelStatusService.active
            : PersonnelStatusService.inactive,
        changedBy: widget.userId,
        personName: nombre,
        reason: reasonCtrl.text,
        snapshot: data,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            activate
                ? 'Colaborador reactivado. El historial fue actualizado.'
                : 'Colaborador inactivado sin eliminar su información.',
          ),
          backgroundColor: activate
              ? const Color(0xFF15803D)
              : const Color(0xFFB45309),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No fue posible cambiar el estado: $error')),
      );
    } finally {
      reasonCtrl.dispose();
    }
  }

  Future<void> _showHistory(String cedula, String nombre) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.72,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Historial laboral',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      nombre.isNotEmpty ? '$nombre · CC $cedula' : 'CC $cedula',
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _personnelStatus.watchHistory(
                    empresaId: widget.empresaId,
                    cedula: cedula,
                  ),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final events = [...snapshot.data!.docs]
                      ..sort((a, b) {
                        final ad = a.data()['fecha'] as Timestamp?;
                        final bd = b.data()['fecha'] as Timestamp?;
                        return (bd?.millisecondsSinceEpoch ?? 0).compareTo(
                          ad?.millisecondsSinceEpoch ?? 0,
                        );
                      });
                    if (events.isEmpty) {
                      return const Center(
                        child: Text('Aún no hay movimientos registrados.'),
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: events.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, index) {
                        final event = events[index].data();
                        final active =
                            event['estado'] == PersonnelStatusService.active;
                        return ModuleCard(
                          padding: const EdgeInsets.all(14),
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              backgroundColor: (active
                                  ? const Color(0xFFDCFCE7)
                                  : const Color(0xFFFFEDD5)),
                              child: Icon(
                                active
                                    ? Icons.person_add_alt_1
                                    : Icons.person_off,
                                color: active
                                    ? const Color(0xFF15803D)
                                    : const Color(0xFFB45309),
                              ),
                            ),
                            title: Text(
                              active ? 'Reactivación' : 'Inactivación',
                            ),
                            subtitle: Text(
                              [
                                _formatTimestamp(event['fecha']),
                                if ((event['motivo'] ?? '')
                                    .toString()
                                    .isNotEmpty)
                                  event['motivo'].toString(),
                              ].join('\n'),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return InternalModuleLayout(
      userId: widget.userId,
      empresaId: widget.empresaId,
      title: 'Gestión de personal',
      subtitle:
          'Vinculación, estructura, estado laboral e historial por empresa',
      accentColor: _kPrimaryColor,
      headerActions: [
        // Generar organigrama PDF
        _generatingPdf
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _kPrimaryColor,
                  ),
                ),
              )
            : IconButton(
                icon: const Icon(
                  Icons.picture_as_pdf_outlined,
                  color: Color(0xFF64748B),
                ),
                tooltip: 'Generar organigrama en PDF',
                onPressed: _generateOrgChartPdf,
              ),
        // Sincronizar jerarquía TH
        _syncing
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _kPrimaryColor,
                  ),
                ),
              )
            : IconButton(
                icon: const Icon(
                  Icons.account_tree_outlined,
                  color: Color(0xFF64748B),
                ),
                tooltip: 'Sincronizar jerarquía (jefes · cargos · áreas)',
                onPressed: () async {
                  setState(() => _syncing = true);
                  try {
                    final n = await _syncAllTH();
                    await _loadUserCache();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            n == 0
                                ? 'Todo ya estaba sincronizado ✓'
                                : '$n registros actualizados correctamente ✓',
                          ),
                          backgroundColor: _kPrimaryColor,
                        ),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Error al sincronizar: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  } finally {
                    if (mounted) setState(() => _syncing = false);
                  }
                },
              ),
        // Exportar Excel
        _exporting
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _kPrimaryColor,
                  ),
                ),
              )
            : IconButton(
                icon: const Icon(
                  Icons.table_chart_outlined,
                  color: Color(0xFF64748B),
                ),
                tooltip: 'Exportar a Excel',
                onPressed: _exportExcel,
              ),
        IconButton(
          icon: const Icon(Icons.refresh_rounded, color: Color(0xFF64748B)),
          tooltip: 'Recargar fotos y datos',
          onPressed: () {
            _userCache = {};
            setState(() {});
            _loadUserCache();
          },
        ),
        IconButton(
          icon: const Icon(
            Icons.add_circle_outline_rounded,
            size: 28,
            color: _kPrimaryColor,
          ),
          onPressed: () => _openForm(),
          tooltip: 'Agregar Colaborador',
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Activos'),
                    avatar: const Icon(Icons.check_circle_outline, size: 17),
                    selected: _statusFilter == PersonnelStatusService.active,
                    onSelected: (_) => setState(
                      () => _statusFilter = PersonnelStatusService.active,
                    ),
                  ),
                  ChoiceChip(
                    label: const Text('Inactivos'),
                    avatar: const Icon(Icons.person_off_outlined, size: 17),
                    selected: _statusFilter == PersonnelStatusService.inactive,
                    onSelected: (_) => setState(
                      () => _statusFilter = PersonnelStatusService.inactive,
                    ),
                  ),
                  ChoiceChip(
                    label: const Text('Todos'),
                    avatar: const Icon(Icons.groups_outlined, size: 17),
                    selected: _statusFilter.isEmpty,
                    onSelected: (_) => setState(() => _statusFilter = ''),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final vertical = constraints.maxWidth < 720;
                final areaField = TypeAheadField<Map<String, String>>(
                  textFieldConfiguration: TextFieldConfiguration(
                    controller: _areaFilterCtrl,
                    decoration: InputDecoration(
                      labelText: 'Filtrar por Área',
                      suffixIcon: _filterArea == null
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear, size: 16),
                              onPressed: () => setState(() {
                                _filterArea = null;
                                _areaFilterCtrl.clear();
                              }),
                            ),
                    ),
                  ),
                  suggestionsCallback: _fetchAreas,
                  itemBuilder: (_, a) => ListTile(
                    title: Text(a['nombre']!),
                    subtitle: a['descripcion']!.isNotEmpty
                        ? Text(
                            a['descripcion']!,
                            style: const TextStyle(fontSize: 12),
                          )
                        : null,
                  ),
                  onSuggestionSelected: (a) => setState(() {
                    _filterArea = a['nombre'];
                    _areaFilterCtrl.text = a['nombre']!;
                    _filterCargo = null;
                    _cargoFilterCtrl.clear();
                  }),
                  minCharsForSuggestions: 0,
                );
                final cargoField = TypeAheadField<String>(
                  textFieldConfiguration: TextFieldConfiguration(
                    controller: _cargoFilterCtrl,
                    decoration: InputDecoration(
                      labelText: 'Filtrar por Cargo',
                      suffixIcon: _filterCargo == null
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear, size: 16),
                              onPressed: () => setState(() {
                                _filterCargo = null;
                                _cargoFilterCtrl.clear();
                              }),
                            ),
                    ),
                  ),
                  suggestionsCallback: (p) async =>
                      (await _fetchCargos(p)).map((m) => m['desc']!).toList(),
                  itemBuilder: (_, d) => ListTile(title: Text(d)),
                  onSuggestionSelected: (d) => setState(() {
                    _filterCargo = d;
                    _cargoFilterCtrl.text = d;
                  }),
                  minCharsForSuggestions: 0,
                );
                if (vertical) {
                  return Column(
                    children: [
                      areaField,
                      const SizedBox(height: 10),
                      cargoField,
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: areaField),
                    const SizedBox(width: 12),
                    Expanded(child: cargoField),
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                labelText: 'Buscar por nombre o ID',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),

            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection(_orgCollection)
                    .snapshots(),
                builder: (ctx, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final term = _searchCtrl.text.trim().toLowerCase();
                  final docs =
                      snap.data!.docs.where((d) {
                        final raw = d.data();
                        if (!_orgBelongsToCompany(raw)) return false;
                        final m = _orgDataForCompany(raw);
                        if (_statusFilter.isNotEmpty &&
                            _statusOf(m) != _statusFilter) {
                          return false;
                        }
                        if (_filterArea != null && m['area'] != _filterArea)
                          return false;
                        if (_filterCargo != null && m['cargo'] != _filterCargo)
                          return false;
                        if (term.isNotEmpty) {
                          final cedula = _orgCedula(d).toLowerCase();
                          final n =
                              (_userCache[_orgCedula(d)]?.nombre ??
                                      m['nombre'] as String? ??
                                      '')
                                  .toLowerCase();
                          return n.contains(term) || cedula.contains(term);
                        }
                        return true;
                      }).toList()..sort((a, b) {
                        final ma = <String, dynamic>{
                          ..._orgDataForCompany(a.data()),
                          'nombre': _userCache[_orgCedula(a)]?.nombre ?? '',
                        };
                        final mb = <String, dynamic>{
                          ..._orgDataForCompany(b.data()),
                          'nombre': _userCache[_orgCedula(b)]?.nombre ?? '',
                        };
                        return _hierarchy.comparePersonnel(ma, mb);
                      });

                  // Guardar docs para exportar (sin setState, no afecta UI)
                  _currentDocs = docs;

                  if (docs.isEmpty) {
                    return const Center(
                      child: Text('No se encontraron registros.'),
                    );
                  }

                  return ListView.separated(
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (c, i) => _buildCard(docs[i]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = _orgDataForCompany(d.data());
    final cedula = _orgCedula(d);
    final ui = _userCache[cedula];

    // Nombre: primero del caché de usuarios, luego del campo en org
    final nombre = (ui?.nombre.isNotEmpty == true)
        ? ui!.nombre
        : (m['nombre'] as String? ?? '');
    final cargo = m['cargo'] as String? ?? '—';
    final area = m['area'] as String? ?? '—';
    final email = (ui?.email.isNotEmpty == true)
        ? ui!.email
        : (m['correo'] as String? ?? '');
    final tel = ui?.telefono ?? '';
    final nivelEd = ui?.nivelEducativo ?? '';
    final superior = _superiorLabel(m);
    final centro = _centroLabel(m);

    final photoUrl = ui?.foto ?? '';
    final status = _statusOf(m);
    final active = status == PersonnelStatusService.active;

    return ModuleCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar (foto → iniciales → ícono; resuelve por cédula si falta)
          UserAvatar(
            userId: cedula,
            nameHint: nombre,
            fotoUrlHint: photoUrl,
            radius: 28,
            backgroundColor: _kPrimaryColor,
            foregroundColor: Colors.white,
          ),
          const SizedBox(width: 14),

          // Info central
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Nombre (resuelve por cédula si el campo viene vacío)
                UserNameText(
                  cedula,
                  fallbackName: nombre,
                  maxLines: 2,
                  style: const TextStyle(
                    fontFamily: _kFontFamily,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 5),

                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: active
                        ? const Color(0xFFDCFCE7)
                        : const Color(0xFFFFEDD5),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    active ? 'ACTIVO' : 'INACTIVO',
                    style: TextStyle(
                      fontFamily: _kFontFamily,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: active
                          ? const Color(0xFF15803D)
                          : const Color(0xFFB45309),
                    ),
                  ),
                ),
                const SizedBox(height: 5),

                // Cargo · Área
                Text(
                  '$cargo  ·  $area',
                  style: const TextStyle(
                    fontFamily: _kFontFamily,
                    fontSize: 12,
                    color: Color(0xFF64748B),
                  ),
                ),

                // Cédula (si ya mostró el nombre arriba)
                if (nombre.isNotEmpty)
                  Text(
                    'CC: $cedula',
                    style: const TextStyle(
                      fontFamily: _kFontFamily,
                      fontSize: 11,
                      color: Color(0xFF94A3B8),
                    ),
                  ),

                const SizedBox(height: 6),

                // Chips de datos de contacto y educación
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (email.isNotEmpty)
                      _InfoChip(icon: Icons.email_outlined, label: email),
                    if (tel.isNotEmpty)
                      _InfoChip(icon: Icons.phone_outlined, label: tel),
                    if (nivelEd.isNotEmpty)
                      _InfoChip(icon: Icons.school_outlined, label: nivelEd),
                  ],
                ),

                const SizedBox(height: 6),

                // Superior / Centro
                Text(
                  'Superior: $superior',
                  style: const TextStyle(
                    fontFamily: _kFontFamily,
                    fontSize: 11,
                    color: Color(0xFF94A3B8),
                  ),
                ),
                Text(
                  'Centro: $centro',
                  style: const TextStyle(
                    fontFamily: _kFontFamily,
                    fontSize: 11,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ),

          // Acciones
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(
                  Icons.edit_note_rounded,
                  color: _kPrimaryColor,
                ),
                onPressed: () => _openForm(doc: d),
                tooltip: 'Editar',
              ),
              IconButton(
                icon: Icon(
                  Icons.history_rounded,
                  color: active ? const Color(0xFF64748B) : _kPrimaryColor,
                ),
                onPressed: () => _showHistory(cedula, nombre),
                tooltip: 'Ver historial',
              ),
              IconButton(
                icon: const Icon(
                  Icons.folder_shared_outlined,
                  color: Color(0xFF9A5B32),
                ),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DisciplinaryManagementScreen(
                      userId: widget.userId,
                      empresaId: widget.empresaId,
                      initialCedula: cedula,
                      initialName: nombre,
                      initialArea: area,
                      initialRole: cargo,
                      initialCostCenter: centro,
                      initialPhotoUrl: photoUrl,
                      initialActive: active,
                    ),
                  ),
                ),
                tooltip: 'Carpeta de procesos disciplinarios',
              ),
              IconButton(
                icon: Icon(
                  active
                      ? Icons.person_off_outlined
                      : Icons.person_add_alt_1_outlined,
                  color: active
                      ? const Color(0xFFB45309)
                      : const Color(0xFF15803D),
                ),
                onPressed: () => _changeEmployeeStatus(
                  cedula: cedula,
                  nombre: nombre,
                  data: m,
                  activate: !active,
                ),
                tooltip: active ? 'Inactivar sin eliminar' : 'Reactivar',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Modelo interno para filas del PDF ────────────────────────────────────────
class _PdfRow {
  final String cedula, nombre, cargo, superior, centro, correo, jefeId;
  const _PdfRow({
    required this.cedula,
    required this.nombre,
    required this.cargo,
    required this.superior,
    required this.centro,
    required this.correo,
    required this.jefeId,
  });
}

// ── Widgets auxiliares ────────────────────────────────────────────────────────

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: const Color(0xFF64748B)),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontFamily: _kFontFamily,
              fontSize: 11,
              color: Color(0xFF475569),
            ),
          ),
        ],
      ),
    );
  }
}
