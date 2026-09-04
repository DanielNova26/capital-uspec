import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:todo/services/diagnosticos_service.dart';
import 'package:todo/services/compras_req_excel_parser.dart';
import 'package:todo/services/compras_proveedores_excel_parser.dart';
import 'package:todo/services/compras_productos_excel_parser.dart';
import 'package:todo/services/company_branding_service.dart';
import 'package:todo/state/empresa_scope.dart';
import '../core/guarded_module_page.dart';
import '../core/task_permissions.dart';
import '../home/widgets/home_shared_widgets.dart';
import '../widgets/internal_module_layout.dart';
import '../compras/compras_req_seed.dart';
import '../compras/compras_service.dart';
import '../compras/compras_models.dart';
import '../interventoria/interventoria_models.dart';
import '../interventoria/interventoria_service.dart';
import '../facturacion/facturacion_models.dart';
import '../rutas/rutas_models.dart';
import '../rutas/rutas_service.dart';
import '../gestion_documental/correspondencia/gd_roles_screen.dart';
import '../gestion_documental/correspondencia/gd_permisos.dart';
import '../gestion_documental/correspondencia/gd_tipos_documentales_screen.dart';
import '../gestion_documental/planillas/pp_module_screen.dart';
import '../services/session_audit_service.dart';

import 'admin_repository.dart';
import 'admin_module_closeout_service.dart';
import '../core/area_directory.dart';
import '../widgets/paged_list.dart';
import 'admin_access_filter.dart';
import 'admin_name_normalizer.dart';
import 'company_transition_service.dart';
import 'compras_document_control_panel.dart';
import 'correo_admin_panel.dart';
import 'dian_tokens_admin_panel.dart';
import 'security_admin_panel.dart';
import 'whatsapp_admin_panel.dart';
import 'migrations/admin_migration_service.dart';
import '../utils/user_company.dart';
import '../widgets/user_avatar.dart';
import '../core/user_directory.dart';

const String kArial = 'Arial';

// ======= Paleta Admin (moderna) =======
const Color kAdminBg = Color(0xFFF8FAFC); // Slate 50
const Color kAdminPrimary = Color(0xFF0F172A); // Slate 900
const Color kAdminAccent = Color(0xFF3B82F6); // Blue 500
const Color kAdminCard = Colors.white;
const Color kAdminBorder = Color(0xFFE2E8F0); // Slate 200
const Color kAdminMuted = Color(0xFF64748B); // Slate 500
const Color kAdminSuccess = Color(0xFF10B981); // Emerald 500
const Color kAdminError = Color(0xFFEF4444); // Red 500

const Map<String, Color> kNotificationCompanyColors = <String, Color>{
  '#2563EB': Color(0xFF2563EB),
  '#16A34A': Color(0xFF16A34A),
  '#EA580C': Color(0xFFEA580C),
  '#DC2626': Color(0xFFDC2626),
  '#CA8A04': Color(0xFFCA8A04),
  '#9333EA': Color(0xFF9333EA),
  '#0891B2': Color(0xFF0891B2),
  '#475569': Color(0xFF475569),
};

const List<String> kDocumentalRoles = <String>[
  'redactor',
  'revisor',
  'aprobador',
  'firmante',
  'admin_doc',
];

const Map<String, String> kDocumentalRoleLabels = <String, String>{
  'redactor': 'Redactor',
  'revisor': 'Revisor',
  'aprobador': 'Aprobador',
  'firmante': 'Firmante',
  'admin_doc': 'Administrador documental',
};

// Roles del subflujo Planillas de Pago (campo: rolPlanillas en empresasDetalle).
const List<String> kPlanillasRoles = <String>[
  'tesoreria',
  'auditoria',
  'gerencia',
  'admin_doc',
];

const Map<String, String> kPlanillasRoleLabels = <String, String>{
  'tesoreria': 'Tesorería',
  'auditoria': 'Auditoría',
  'gerencia': 'Gerencia',
  'admin_doc': 'Administrador Documental',
};

const List<InternalModuleTabItem> _kAdminModuleTabs = [
  InternalModuleTabItem(label: 'Usuarios', icon: Icons.people_alt),
  InternalModuleTabItem(label: 'Apps', icon: Icons.apps),
  InternalModuleTabItem(
    label: 'Roles y permisos',
    icon: Icons.admin_panel_settings_outlined,
  ),
  InternalModuleTabItem(label: 'Catálogos', icon: Icons.account_tree),
  InternalModuleTabItem(label: 'Migraciones', icon: Icons.construction),
  InternalModuleTabItem(label: 'Logs', icon: Icons.history),
  InternalModuleTabItem(label: 'Seguridad', icon: Icons.security_rounded),
  InternalModuleTabItem(label: 'Limpieza', icon: Icons.cleaning_services),
  InternalModuleTabItem(label: 'Diagnósticos', icon: Icons.medical_information),
  InternalModuleTabItem(label: 'Compras', icon: Icons.shopping_bag_outlined),
  InternalModuleTabItem(label: 'Correo', icon: Icons.alternate_email),
  InternalModuleTabItem(label: 'Tokens DIAN', icon: Icons.vpn_key_outlined),
  InternalModuleTabItem(label: 'WhatsApp', icon: Icons.chat_outlined),
  InternalModuleTabItem(label: 'Salud usuarios', icon: Icons.health_and_safety),
  InternalModuleTabItem(label: 'Salud cargos', icon: Icons.badge),
  InternalModuleTabItem(label: 'Membresía', icon: Icons.apartment),
];

class AdminDashboardScreen extends StatefulWidget {
  final String userId; // admin id
  final String empresaId;
  const AdminDashboardScreen({
    super.key,
    required this.userId,
    required this.empresaId,
  });

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AccessMatrixModule {
  final String key;
  final String label;
  final String appId;
  final IconData icon;
  final Color color;
  final Map<String, String> roles;
  final bool hasPlanillasRole;

  const _AccessMatrixModule({
    required this.key,
    required this.label,
    required this.appId,
    required this.icon,
    required this.color,
    this.roles = const {},
    this.hasPlanillasRole = false,
  });
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen>
    with SingleTickerProviderStateMixin {
  final _repo = AdminRepository(db: FirebaseFirestore.instance);
  final _mig = AdminMigrationService(db: FirebaseFirestore.instance);
  final _companyTransition = CompanyTransitionService(
    db: FirebaseFirestore.instance,
  );

  late TabController _tabController;
  bool _loading = true;

  // Empresa
  List<EmpresaItem> _empresas = [];
  String? _empresaId;

  // Apps / Usuarios
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _users = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _appsAdmin = [];
  Map<String, Set<String>> _userApps = {};
  List<AccessRoleItem> _accessRoles = [];
  String _accessRoleUserSearch = '';
  String? _accessRoleAreaFilter;
  // La matriz abre un solo módulo por vez. Renderizar todos los usuarios por
  // todos los módulos hacía lenta y difícil de leer esta pantalla.
  String? _accessRoleAppFilter;
  AdminAccessFilter _accessRoleStatusFilter = AdminAccessFilter.all;
  bool _accessRolesRefreshing = false;
  int _accessReloadVersion = 0;
  int _loadAllVersion = 0;
  Set<String> _selectedAccessUserIds = <String>{};
  int _accessRolePage = 0;
  static const int _accessRolePageSize = 20;
  Map<String, String> _comprasRoleByUser = {};
  Map<String, String> _interventoriaRoleByUser = {};
  Map<String, String> _rutasRoleByUser = {};
  Map<String, String> _correoRoleByUser = {};

  // Catálogos
  List<CentroCostoItem> _centros = [];
  List<AreaItem> _areas = [];
  List<CargoItem> _cargos = [];
  List<BodegaItem> _bodegas = [];

  // UI — filtros de personal
  String _userSearch = '';
  String? _userAreaFilter;
  String _sessionSearch = '';

  // Roles Compras: filtros
  String _comprasRolesSearch = '';
  String? _comprasRolesAreaFilter;

  // Roles Interventoría: filtros
  String _rolesSearch = '';
  bool _rolesSoloDirectivos = false;
  String? _rolesAreaFilter;

  // Roles Facturación: filtros
  String _facRolesSearch = '';
  String? _facRolesAreaFilter;

  // Roles Rutas: filtros
  String _rutasRolesSearch = '';

  // Migración: selección de usuarios
  Set<String> _selectedMigrationUsers = {};

  // Diagnósticos: carga de Excel
  final DiagnosticosService _diagnosticosService = DiagnosticosService();
  String? _diagnosticosFileName;
  Uint8List? _diagnosticosBytes;
  Map<String, int>? _diagnosticosImportResult;
  bool _importandoReqCompras = false;
  final ComprasReqExcelParser _comprasReqParser = ComprasReqExcelParser();
  String? _reqComprasFileName;
  Uint8List? _reqComprasBytes;
  Map<String, int>? _reqComprasImportResult;

  // Proveedores: carga masiva desde Excel
  final ComprasProveedoresExcelParser _proveedoresParser =
      ComprasProveedoresExcelParser();
  String? _proveedoresFileName;
  Uint8List? _proveedoresBytes;
  Map<String, int>? _proveedoresImportResult;
  bool _importandoProveedores = false;

  // Productos: carga masiva desde Excel
  final ComprasProductosExcelParser _productosParser =
      ComprasProductosExcelParser();
  String? _productosFileName;
  Uint8List? _productosBytes;
  Map<String, int>? _productosImportResult;
  bool _importandoProductos = false;
  String? _lastScopedEmpresaId;

  // Limpieza: usuario seleccionado para limpiar notificaciones individualmente
  String? _notifCleanUserId;

  // Cierre no destructivo por módulo y fecha.
  final AdminModuleCloseoutService _moduleCloseoutService =
      AdminModuleCloseoutService();
  DateTime _moduleCloseoutCutoff = DateTime(DateTime.now().year, 9, 1);
  AdminCloseoutRange _moduleCloseoutRange = AdminCloseoutRange.before;
  Set<String> _moduleCloseoutModules = {'interventoria', 'facturacion'};
  AdminModuleCloseoutPreview? _moduleCloseoutPreview;
  bool _moduleCloseoutBusy = false;

  // Salud de usuarios: diagnóstico read-only (Etapa 1).
  // Escanea TODO TBL_USUARIOS (no solo la empresa activa) porque la cédula es
  // identidad global y una membresía rota puede dejar al usuario fuera del
  // filtro por empresa.
  bool _saludLoading = false;
  _UserHealthReport? _saludReport;

  // Salud de cargos: diagnóstico read-only del catálogo TBL_CARGOS de la
  // empresa activa. Detecta cargos sin `areaId` (que se filtran en todas las
  // áreas del módulo de tareas) y referencias de área inexistentes.
  bool _cargoSaludLoading = false;
  _CargoHealthReport? _cargoSaludReport;

  /// Áreas de la empresa activa, cargadas en el escaneo para poder asignar el
  /// área a mano a un cargo que el diagnóstico no puede reparar solo.
  List<AreaOpcion> _cargoSaludAreas = const <AreaOpcion>[];

  // Membresía multi-empresa (Etapa 3). Carga global de TBL_USUARIOS bajo
  // demanda para poder agregar/quitar a cualquier usuario de cualquier empresa.
  String _membresiaSearch = '';
  bool _membresiaLoading = false;
  bool _membresiaLoaded = false;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _membresiaUsers = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _membresiaGrupos = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: _kAdminModuleTabs.length,
      vsync: this,
    );
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scopedEmpresaId = EmpresaScope.of(context).selectedEmpresaId?.trim();
    if (scopedEmpresaId != null &&
        scopedEmpresaId.isNotEmpty &&
        scopedEmpresaId != _lastScopedEmpresaId) {
      _lastScopedEmpresaId = scopedEmpresaId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _loadAll(forceEmpresaId: scopedEmpresaId);
      });
    }
  }

  Future<void> _loadAll({String? forceEmpresaId}) async {
    final loadVersion = ++_loadAllVersion;
    setState(() => _loading = true);

    final empresas = await _repo.loadEmpresas();
    String? selected = forceEmpresaId;

    // intenta empresa del admin
    if (selected == null || selected.isEmpty) {
      try {
        final adminDoc = await FirebaseFirestore.instance
            .collection('TBL_USUARIOS')
            .doc(widget.userId)
            .get();
        selected = (adminDoc.data()?['empresaId'] ?? '').toString().trim();
      } catch (_) {}
    }
    selected ??= empresas.isNotEmpty ? empresas.first.empresaId : null;

    if (selected == null || selected.isEmpty) {
      if (!mounted || loadVersion != _loadAllVersion) return;
      setState(() {
        _empresas = empresas;
        _empresaId = null;
        _moduleCloseoutPreview = null;
        _loading = false;
      });
      return;
    }

    // Estas lecturas no dependen entre sí. Ejecutarlas en paralelo reduce de
    // forma importante el tiempo de entrada al panel administrativo.
    final results = await Future.wait<dynamic>([
      _repo.loadUsersByEmpresa(selected),
      _repo.loadAppsByEmpresa(selected),
      _repo.loadAccessRoles(selected),
      _loadModuleRoleMap('TBL_COMPRAS_ROLES', selected),
      _loadModuleRoleMap('TBL_INTERVENTORIA_ROLES', selected),
      _loadModuleRoleMap('TBL_RUTAS_ROLES', selected),
      _loadModuleRoleMap('TBL_CORREO_ROLES', selected),
      _repo.loadCentros(selected),
      _repo.loadAreas(selected),
      _repo.loadCargos(selected),
      _repo.loadBodegas(selected),
    ]);
    final users =
        results[0] as List<QueryDocumentSnapshot<Map<String, dynamic>>>;
    final appsAdmin =
        results[1] as List<QueryDocumentSnapshot<Map<String, dynamic>>>;
    final accessRoles = results[2] as List<AccessRoleItem>;
    final comprasRoleByUser = results[3] as Map<String, String>;
    final interventoriaRoleByUser = results[4] as Map<String, String>;
    final rutasRoleByUser = results[5] as Map<String, String>;
    final correoRoleByUser = results[6] as Map<String, String>;
    final centros = results[7] as List<CentroCostoItem>;
    final areas = results[8] as List<AreaItem>;
    final cargos = results[9] as List<CargoItem>;
    final bodegas = results[10] as List<BodegaItem>;

    // Si el usuario cambió de empresa mientras cargaban las consultas, no
    // permitimos que la respuesta anterior vuelva a dejar Servir sobre Capital
    // (o viceversa).
    if (!mounted || loadVersion != _loadAllVersion) return;

    setState(() {
      _empresas = empresas;
      _empresaId = selected;
      _moduleCloseoutPreview = null;

      _users = users;
      _appsAdmin = appsAdmin;
      _accessRoles = accessRoles;
      _comprasRoleByUser = comprasRoleByUser;
      _interventoriaRoleByUser = interventoriaRoleByUser;
      _rutasRoleByUser = rutasRoleByUser;
      _correoRoleByUser = correoRoleByUser;

      _centros = centros;
      _areas = areas;
      _cargos = cargos;
      _bodegas = bodegas;

      // extractUserApps lee tanto apps globales como las del scope de empresa.
      _userApps = {
        for (final u in users)
          u.id: extractUserApps(u.data(), empresaId: selected).toSet(),
      };

      // Si cambias de empresa, limpiamos selección de migración
      _selectedMigrationUsers = {};
      _selectedAccessUserIds = <String>{};
      _accessRoleAppFilter = null;

      _loading = false;
    });
  }

  /// Recarga solamente los datos usados por la matriz de accesos.
  ///
  /// Antes, cada cambio de un permiso volvía a consultar empresas, apps,
  /// catálogos, centros, áreas, cargos y bodegas. Además de ser costoso, eso
  /// bloqueaba todo el panel. Esta recarga conserva la pantalla y los filtros.
  Future<void> _reloadAccessMatrix() async {
    final empresaId = (_empresaId ?? '').trim();
    if (empresaId.isEmpty) return;
    final reloadVersion = ++_accessReloadVersion;
    if (!_accessRolesRefreshing) {
      setState(() => _accessRolesRefreshing = true);
    }
    try {
      final results = await Future.wait<dynamic>([
        _repo.loadUsersByEmpresa(empresaId),
        _loadModuleRoleMap('TBL_COMPRAS_ROLES', empresaId),
        _loadModuleRoleMap('TBL_INTERVENTORIA_ROLES', empresaId),
        _loadModuleRoleMap('TBL_RUTAS_ROLES', empresaId),
        _loadModuleRoleMap('TBL_CORREO_ROLES', empresaId),
      ]);
      if (!mounted ||
          _empresaId != empresaId ||
          reloadVersion != _accessReloadVersion) {
        return;
      }
      final users =
          results[0] as List<QueryDocumentSnapshot<Map<String, dynamic>>>;
      setState(() {
        _users = users;
        _comprasRoleByUser = results[1] as Map<String, String>;
        _interventoriaRoleByUser = results[2] as Map<String, String>;
        _rutasRoleByUser = results[3] as Map<String, String>;
        _correoRoleByUser = results[4] as Map<String, String>;
        _userApps = {
          for (final user in users)
            user.id: extractUserApps(user.data(), empresaId: empresaId).toSet(),
        };
      });
    } catch (error) {
      _snack('No se pudo actualizar la matriz de accesos: $error');
    } finally {
      if (mounted && reloadVersion == _accessReloadVersion) {
        setState(() => _accessRolesRefreshing = false);
      }
    }
  }

  // ---------------- HELPERS ----------------
  String _safe(dynamic v) => v == null ? '' : v.toString().trim();

  String _userName(Map<String, dynamic> d, String fallback) {
    final n = _safe(d['nombres']).isNotEmpty
        ? _safe(d['nombres'])
        : _safe(d['primerNombre']);
    final a = _safe(d['apellidos']).isNotEmpty
        ? _safe(d['apellidos'])
        : _safe(d['primerApellido']);
    final full = ('$n $a').trim();
    return full.isEmpty ? fallback : full;
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontFamily: kArial)),
      ),
    );
  }

  Future<Map<String, String>> _loadModuleRoleMap(
    String collection,
    String empresaId,
  ) async {
    final snap = await FirebaseFirestore.instance
        .collection(collection)
        .where('empresaId', isEqualTo: empresaId)
        .get();
    final out = <String, String>{};
    for (final doc in snap.docs) {
      final data = doc.data();
      final role = _safe(data['rol']);
      if (role.isEmpty) continue;
      final userId = _safe(data['userId']).isNotEmpty
          ? _safe(data['userId'])
          : _safe(data['usuarioId']);
      final cedula = _safe(data['cedula']);
      if (userId.isNotEmpty) out[userId] = role;
      if (cedula.isNotEmpty) out[cedula] = role;
    }
    return out;
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    String confirmText = 'Confirmar',
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          title,
          style: const TextStyle(
            fontFamily: kArial,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(message, style: const TextStyle(fontFamily: kArial)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar', style: TextStyle(fontFamily: kArial)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kAdminPrimary),
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              confirmText,
              style: const TextStyle(fontFamily: kArial),
            ),
          ),
        ],
      ),
    );
    return ok == true;
  }

  // ---------------- USUARIOS: editar módulos ----------------
  /// Editor autoritativo de módulos por empresa. Muestra CADA empresa a la que
  /// pertenece el usuario y permite marcar/desmarcar cualquier módulo. Al
  /// guardar, lo marcado ES exactamente lo que queda: así puedes quitar un
  /// módulo que se quedó "pegado" en una empresa que no es la activa, y asignar
  /// a voluntad. El campo global `apps` se fija a la intersección para que
  /// extractUserApps (top-level ∪ scope) dé por empresa justo lo marcado, sin
  /// filtrar módulos de una empresa a otra.
  Future<void> _editUserApps(
    QueryDocumentSnapshot<Map<String, dynamic>> userDoc,
  ) async {
    final data = userDoc.data();
    final nombre = _userName(data, userDoc.id);

    var empresas = extractUserEmpresaIds(data);
    if (empresas.isEmpty && (_empresaId ?? '').isNotEmpty) {
      empresas = [_empresaId!];
    }
    if (empresas.isEmpty) {
      _snack('El usuario no pertenece a ninguna empresa.');
      return;
    }

    // Estado local por empresa: set de appIds efectivos. Se conservan los ids
    // no canónicos (si los hubiera) para no perderlos; solo se togglean los
    // módulos conocidos de _kAllModules.
    final chosen = <String, Set<String>>{
      for (final e in empresas) e: extractUserApps(data, empresaId: e).toSet(),
    };

    final guardar = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: kAdminBg,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 8,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              ),
              child: SizedBox(
                height: MediaQuery.of(ctx).size.height * 0.88,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Módulos del usuario',
                      style: TextStyle(
                        fontFamily: kArial,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                        color: kAdminPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      nombre,
                      style: const TextStyle(
                        fontFamily: kArial,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Marca los módulos que tendrá en cada empresa. Se guarda '
                      'exactamente lo marcado.',
                      style: TextStyle(
                        fontFamily: kArial,
                        fontSize: 12,
                        color: kAdminMuted,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView(
                        children: [
                          for (final e in empresas) ...[
                            Padding(
                              padding: const EdgeInsets.only(top: 4, bottom: 6),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.business,
                                    size: 18,
                                    color: kAdminAccent,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _empresaNombre(e),
                                      style: const TextStyle(
                                        fontFamily: kArial,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Card(
                              color: kAdminCard,
                              margin: const EdgeInsets.only(bottom: 12),
                              child: Column(
                                children: [
                                  for (final m in _kAllModules)
                                    CheckboxListTile(
                                      dense: true,
                                      value: chosen[e]!.contains(m.id),
                                      activeColor: kAdminPrimary,
                                      controlAffinity:
                                          ListTileControlAffinity.leading,
                                      title: Text(
                                        m.label,
                                        style: const TextStyle(
                                          fontFamily: kArial,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      subtitle: Text(
                                        m.id,
                                        style: const TextStyle(
                                          fontFamily: kArial,
                                          fontSize: 11,
                                          color: Colors.black54,
                                        ),
                                      ),
                                      onChanged: (v) => setSheet(() {
                                        if (v == true) {
                                          chosen[e]!.add(m.id);
                                        } else {
                                          chosen[e]!.remove(m.id);
                                        }
                                      }),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.save),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kAdminPrimary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: () => Navigator.pop(ctx, true),
                        label: const Text(
                          'Guardar',
                          style: TextStyle(
                            fontFamily: kArial,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (guardar != true) return;

    try {
      // Mapa anidado real (mismo formato que el seeder). set(merge:true) hace
      // deep-merge: reemplaza solo `apps` de cada empresa tocada y conserva sus
      // otros campos (área/cargo/roles) y las empresas no tocadas.
      final detalleUpdate = <String, dynamic>{};
      Set<String>? interseccion;
      for (final e in empresas) {
        final ids = normalizeAppIdList(chosen[e]!.toList()).ids;
        detalleUpdate[e] = {'apps': ids};
        interseccion = interseccion == null
            ? {...ids}
            : interseccion.intersection({...ids});
      }
      final update = <String, dynamic>{
        'empresasDetalle': detalleUpdate,
        // El global `apps` = intersección: evita que un módulo asignado en una
        // empresa "se filtre" a las demás (extractUserApps une top-level ∪ scope).
        'apps': (interseccion?.toList() ?? <String>[])..sort(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      await userDoc.reference.set(update, SetOptions(merge: true));

      _snack('Módulos actualizados.');
      if (!mounted) return;
      await _loadAll(forceEmpresaId: _empresaId);
    } catch (e) {
      _snack('Error al guardar módulos: $e');
    }
  }

  // ---------------- USUARIOS: editar org ----------------
  Future<void> _editUserOrg(
    QueryDocumentSnapshot<Map<String, dynamic>> userDoc,
  ) async {
    final empresaId = _empresaId ?? '';
    if (empresaId.isEmpty) return;

    final d = userDoc.data();
    final scoped = getUserCompanyDetail(d, empresaId);
    final nombre = _userName(d, userDoc.id);

    String? centroId = _safe(scoped?['centroId']).isEmpty
        ? (_safe(d['centroId']).isEmpty ? null : _safe(d['centroId']))
        : _safe(scoped?['centroId']);
    String? areaId = _safe(scoped?['areaId']).isEmpty
        ? (_safe(d['areaId']).isEmpty ? null : _safe(d['areaId']))
        : _safe(scoped?['areaId']);
    String cargoNombre = _safe(scoped?['cargo']).isNotEmpty
        ? _safe(scoped?['cargo'])
        : _safe(d['cargo']);
    String rolDocumental = _safe(scoped?['rolDocumental']).isNotEmpty
        ? _safe(scoped?['rolDocumental']).toLowerCase()
        : (_safe(d['rolDocumental']).isEmpty
              ? ''
              : _safe(d['rolDocumental']).toLowerCase());
    String rolPlanillas = _safe(scoped?['rolPlanillas']).isNotEmpty
        ? _safe(scoped?['rolPlanillas']).toLowerCase()
        : (_safe(d['rolPlanillas']).isEmpty
              ? ''
              : _safe(d['rolPlanillas']).toLowerCase());

    CentroCostoItem? centroSel = _centros
        .where((c) => c.centroId == centroId)
        .cast<CentroCostoItem?>()
        .firstWhere((x) => x != null, orElse: () => null);
    AreaItem? areaSel = _areas
        .where((a) => a.areaId == areaId)
        .cast<AreaItem?>()
        .firstWhere((x) => x != null, orElse: () => null);

    await showDialog(
      context: context,
      builder: (_) {
        final centrosEnabled = _centros.where((c) => c.enabled).toList();
        final areasEnabled = _areas.where((a) => a.enabled).toList();

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                'Organización',
                style: TextStyle(
                  fontFamily: kArial,
                  fontWeight: FontWeight.w900,
                  color: kAdminPrimary,
                ),
              ),
              content: SizedBox(
                width: 560,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        nombre,
                        style: const TextStyle(
                          fontFamily: kArial,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    DropdownButtonFormField<CentroCostoItem>(
                      initialValue: centroSel,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Centro de costos',
                        border: OutlineInputBorder(),
                      ),
                      items: centrosEnabled
                          .map(
                            (c) => DropdownMenuItem(
                              value: c,
                              child: Text(
                                c.nombre,
                                style: const TextStyle(fontFamily: kArial),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setDialogState(() => centroSel = v),
                    ),
                    const SizedBox(height: 12),

                    DropdownButtonFormField<AreaItem>(
                      initialValue: areaSel,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Área / Departamento',
                        border: OutlineInputBorder(),
                      ),
                      items: areasEnabled
                          .map(
                            (a) => DropdownMenuItem(
                              value: a,
                              child: Text(
                                a.nombre,
                                style: const TextStyle(fontFamily: kArial),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setDialogState(() => areaSel = v),
                    ),
                    const SizedBox(height: 12),

                    TextFormField(
                      initialValue: cargoNombre,
                      decoration: const InputDecoration(
                        labelText: 'Cargo (texto)',
                        border: OutlineInputBorder(),
                      ),
                      style: const TextStyle(fontFamily: kArial),
                      onChanged: (v) => cargoNombre = v.trim(),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: rolDocumental,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        // Este rol es del flujo documental (redactar/revisar/
                        // aprobar/firmar), no del rol Clasificador y asignador
                        // de Correspondencia — por eso dice "Biblioteca" y no
                        // el nombre del módulo.
                        labelText: 'Rol de biblioteca (submódulo)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(
                          Icons.description_outlined,
                          color: kAdminAccent,
                        ),
                        helperText:
                            'Habilita acciones específicas (redactar, revisar, firmar).',
                        helperStyle: TextStyle(
                          fontFamily: kArial,
                          fontSize: 10,
                          color: kAdminAccent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      items: [
                        const DropdownMenuItem<String>(
                          value: '',
                          child: Text(
                            'Sin rol documental (Solo lectura)',
                            style: TextStyle(fontFamily: kArial),
                          ),
                        ),
                        ...kDocumentalRoles.map(
                          (rol) => DropdownMenuItem<String>(
                            value: rol,
                            child: Text(
                              kDocumentalRoleLabels[rol] ?? rol,
                              style: const TextStyle(
                                fontFamily: kArial,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                      onChanged: (v) =>
                          setDialogState(() => rolDocumental = v ?? ''),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: rolPlanillas,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Rol en Planillas de Pago',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(
                          Icons.receipt_long_outlined,
                          color: kAdminAccent,
                        ),
                        helperText:
                            'Define quién puede cargar, auditar o firmar planillas.',
                        helperStyle: TextStyle(
                          fontFamily: kArial,
                          fontSize: 10,
                          color: kAdminAccent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      items: [
                        const DropdownMenuItem<String>(
                          value: '',
                          child: Text(
                            'Sin rol en planillas',
                            style: TextStyle(fontFamily: kArial),
                          ),
                        ),
                        ...kPlanillasRoles.map(
                          (rol) => DropdownMenuItem<String>(
                            value: rol,
                            child: Text(
                              kPlanillasRoleLabels[rol] ?? rol,
                              style: const TextStyle(
                                fontFamily: kArial,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                      onChanged: (v) =>
                          setDialogState(() => rolPlanillas = v ?? ''),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Cancelar',
                    style: TextStyle(fontFamily: kArial),
                  ),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.save),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kAdminPrimary,
                  ),
                  onPressed: () async {
                    final cargoMatch = _cargos.where((c) {
                      if (!c.enabled) return false;
                      if (areaSel != null &&
                          (c.areaId ?? '').isNotEmpty &&
                          c.areaId != areaSel!.areaId) {
                        return false;
                      }
                      return c.nombre.trim().toLowerCase() ==
                          cargoNombre.trim().toLowerCase();
                    }).toList();
                    await _repo.updateUserOrg(
                      userId: userDoc.id,
                      empresaId: empresaId,
                      centroId: centroSel?.centroId,
                      centroCodigo: centroSel?.codigo,
                      centroNombre: centroSel?.nombre,
                      areaId: areaSel?.areaId,
                      areaNombre: areaSel?.nombre,
                      cargoId: cargoMatch.length == 1
                          ? cargoMatch.single.cargoId
                          : null,
                      cargo: cargoNombre.isEmpty ? null : cargoNombre,
                      rolDocumental: rolDocumental,
                      rolPlanillas: rolPlanillas,
                    );
                    if (!mounted || !context.mounted) return;
                    Navigator.pop(context);
                    _snack('Usuario actualizado');
                    await _loadAll(forceEmpresaId: _empresaId);
                  },
                  label: const Text(
                    'Guardar',
                    style: TextStyle(
                      fontFamily: kArial,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ---------------- MIGRACIONES: seleccionar usuarios ----------------
  Future<void> _pickMigrationUsers() async {
    final selected = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: kAdminBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        final local = {..._selectedMigrationUsers};
        String q = '';

        List<QueryDocumentSnapshot<Map<String, dynamic>>> filtered() {
          if (q.trim().isEmpty) return _users;
          final s = q.toLowerCase().trim();
          return _users.where((u) {
            final d = u.data();
            final name = _userName(d, u.id).toLowerCase();
            final ced = _safe(d['cedula']).toLowerCase();
            final cargo = _safe(d['cargo']).toLowerCase();
            return name.contains(s) ||
                ced.contains(s) ||
                u.id.toLowerCase().contains(s) ||
                cargo.contains(s);
          }).toList();
        }

        return StatefulBuilder(
          builder: (ctx2, setLocal) {
            final list = filtered();

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 10,
                  bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
                ),
                child: SizedBox(
                  height: MediaQuery.of(ctx).size.height * 0.9,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Seleccionar usuarios para migración',
                        style: TextStyle(
                          fontFamily: kArial,
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                          color: kAdminPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Seleccionados: ${local.length}',
                        style: const TextStyle(
                          fontFamily: kArial,
                          color: Colors.black54,
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Buscar
                      TextField(
                        decoration: InputDecoration(
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.search),
                          labelText: 'Buscar (nombre, cédula, cargo)',
                          isDense: true,
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        style: const TextStyle(fontFamily: kArial),
                        onChanged: (v) => setLocal(() => q = v),
                      ),

                      const SizedBox(height: 10),

                      // ✅ BOTONES RESPONSIVE (evita overflow)
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final w = constraints.maxWidth;
                          final half = (w - 10) / 2;

                          return Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              SizedBox(
                                width: half,
                                child: OutlinedButton.icon(
                                  onPressed: () => setLocal(() {
                                    local.addAll(_users.map((e) => e.id));
                                  }),
                                  icon: const Icon(Icons.select_all),
                                  label: const Text(
                                    'Seleccionar todos',
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontFamily: kArial,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: half,
                                child: OutlinedButton.icon(
                                  onPressed: () =>
                                      setLocal(() => local.clear()),
                                  icon: const Icon(Icons.clear),
                                  label: const Text(
                                    'Limpiar',
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontFamily: kArial,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: w,
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: kAdminPrimary,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  onPressed: () => Navigator.pop(ctx, local),
                                  icon: const Icon(Icons.check),
                                  label: const Text(
                                    'Aplicar selección',
                                    style: TextStyle(
                                      fontFamily: kArial,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),

                      const SizedBox(height: 10),

                      // Lista
                      Expanded(
                        child: Card(
                          color: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(color: Colors.grey.shade300),
                          ),
                          child: ListView.separated(
                            itemCount: list.length,
                            separatorBuilder: (_, _) =>
                                Divider(height: 0, color: Colors.grey.shade200),
                            itemBuilder: (_, i) {
                              final u = list[i];
                              final d = u.data();
                              final name = _userName(d, u.id);
                              final ced = _safe(d['cedula']).isNotEmpty
                                  ? _safe(d['cedula'])
                                  : u.id;
                              final cargo = _safe(d['cargo']);
                              final checked = local.contains(u.id);

                              return CheckboxListTile(
                                value: checked,
                                activeColor: kAdminPrimary,
                                controlAffinity:
                                    ListTileControlAffinity.trailing,
                                dense: true,
                                visualDensity: VisualDensity.compact,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                title: Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontFamily: kArial,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                subtitle: Text(
                                  'ID: ${u.id} • Cédula: $ced${cargo.isNotEmpty ? " • $cargo" : ""}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontFamily: kArial,
                                    color: Colors.black54,
                                  ),
                                ),
                                onChanged: (v) => setLocal(() {
                                  if (v == true) {
                                    local.add(u.id);
                                  } else {
                                    local.remove(u.id);
                                  }
                                }),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (selected == null) return;
    setState(() => _selectedMigrationUsers = selected);
  }

  // ---------------- MIGRACIONES: CENTRO SOLO USUARIOS SELECCIONADOS ----------------
  Future<void> _runNormalizeCentroSelectedUsers({required bool dryRun}) async {
    final empresaId = _empresaId ?? '';
    if (empresaId.isEmpty) return;

    if (_selectedMigrationUsers.isEmpty) {
      _snack('Selecciona usuarios para migrar');
      return;
    }

    final enabledCentros = _centros.where((c) => c.enabled).toList();
    if (enabledCentros.isEmpty) {
      _snack('No hay centros habilitados en catálogo');
      return;
    }

    CentroCostoItem centroCanonical = enabledCentros.first;

    // selector centro canónico
    await showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text(
            'Centro canónico',
            style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.w900),
          ),
          content: DropdownButtonFormField<CentroCostoItem>(
            initialValue: centroCanonical,
            isExpanded: true,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            items: enabledCentros
                .map(
                  (c) => DropdownMenuItem(
                    value: c,
                    child: Text(
                      c.nombre,
                      style: const TextStyle(fontFamily: kArial),
                    ),
                  ),
                )
                .toList(),
            onChanged: (v) {
              if (v != null) centroCanonical = v;
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Cancelar',
                style: TextStyle(fontFamily: kArial),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: kAdminPrimary),
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Continuar',
                style: TextStyle(
                  fontFamily: kArial,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (!dryRun) {
      final ok = await _confirm(
        title: 'Ejecutar migración de Centro',
        message:
            'Usuarios seleccionados: ${_selectedMigrationUsers.length}\n'
            'Centro canónico: ${centroCanonical.nombre}\n\n'
            'Esto SOLO actualizará TBL_USUARIOS (no tareas/cargos/estructura).\n¿Continuar?',
        confirmText: 'Ejecutar',
      );
      if (!ok) return;
    }

    setState(() => _loading = true);

    final result = await _mig.normalizeCentroForUsers(
      empresaId: empresaId,
      userIds: _selectedMigrationUsers,
      canonicalCentroId: centroCanonical.centroId,
      canonicalCentroCodigo: centroCanonical.codigo,
      canonicalCentroNombre: centroCanonical.nombre,
      dryRun: dryRun,
    );

    await _mig.logMigration(
      adminUserId: widget.userId,
      empresaId: empresaId,
      action: 'normalizeCentroForUsers',
      scanned: result.scanned,
      updated: result.updated,
      dryRun: dryRun,
      extra: {
        'selectedUsersCount': _selectedMigrationUsers.length,
        'canonicalCentroId': centroCanonical.centroId,
        'canonicalCentroCodigo': centroCanonical.codigo,
        'canonicalCentroNombre': centroCanonical.nombre,
        'sample': result.sampleUpdatedIds,
      },
    );

    _snack(
      dryRun
          ? 'SIMULACIÓN Centro: escaneados ${result.scanned}, a cambiar ${result.updated}'
          : 'Centro ejecutado: escaneados ${result.scanned}, cambiados ${result.updated}',
    );

    await _loadAll(forceEmpresaId: empresaId);
  }

  // ---------------- MIGRACIONES: TOKENS SOLO USUARIOS SELECCIONADOS ----------------
  Future<void> _runNormalizeTokensSelectedUsers({required bool dryRun}) async {
    final empresaId = _empresaId ?? '';
    if (empresaId.isEmpty) return;

    if (_selectedMigrationUsers.isEmpty) {
      _snack('Selecciona usuarios para migrar');
      return;
    }

    if (!dryRun) {
      final ok = await _confirm(
        title: 'Ejecutar normalización de Tokens',
        message:
            'Usuarios seleccionados: ${_selectedMigrationUsers.length}\n\n'
            'Se copiará token/fcm_token a fcmToken si aplica.\n¿Continuar?',
        confirmText: 'Ejecutar',
      );
      if (!ok) return;
    }

    setState(() => _loading = true);

    final result = await _mig.normalizeUserTokensForUsers(
      empresaId: empresaId,
      userIds: _selectedMigrationUsers,
      dryRun: dryRun,
    );

    await _mig.logMigration(
      adminUserId: widget.userId,
      empresaId: empresaId,
      action: 'normalizeUserTokensForUsers',
      scanned: result.scanned,
      updated: result.updated,
      dryRun: dryRun,
      extra: {
        'selectedUsersCount': _selectedMigrationUsers.length,
        'sample': result.sampleUpdatedIds,
      },
    );

    _snack(
      dryRun
          ? 'SIMULACIÓN Tokens: escaneados ${result.scanned}, a cambiar ${result.updated}'
          : 'Tokens ejecutado: escaneados ${result.scanned}, cambiados ${result.updated}',
    );

    await _loadAll(forceEmpresaId: empresaId);
  }

  // ---------------- MIGRACIONES: APP IDs SOLO USUARIOS SELECCIONADOS ----------------
  Future<void> _runNormalizeAppIdsSelectedUsers({required bool dryRun}) async {
    final empresaId = _empresaId ?? '';
    if (empresaId.isEmpty) return;

    if (_selectedMigrationUsers.isEmpty) {
      _snack('Selecciona usuarios para migrar');
      return;
    }

    if (!dryRun) {
      final ok = await _confirm(
        title: 'Ejecutar normalización de App IDs',
        message:
            'Usuarios seleccionados: ${_selectedMigrationUsers.length}\n\n'
            'Se reemplazarán IDs cortos (compras, admin…) por IDs completos '
            '(comprasdashboard, admindashboard…) en el campo "apps".\n¿Continuar?',
        confirmText: 'Ejecutar',
      );
      if (!ok) return;
    }

    setState(() => _loading = true);

    final result = await _mig.normalizeAppIdsForUsers(
      empresaId: empresaId,
      userIds: _selectedMigrationUsers,
      dryRun: dryRun,
    );

    await _mig.logMigration(
      adminUserId: widget.userId,
      empresaId: empresaId,
      action: 'normalizeAppIdsForUsers',
      scanned: result.scanned,
      updated: result.updated,
      dryRun: dryRun,
      extra: {
        'selectedUsersCount': _selectedMigrationUsers.length,
        'sample': result.sampleUpdatedIds,
      },
    );

    _snack(
      dryRun
          ? 'SIMULACIÓN App IDs: escaneados ${result.scanned}, a cambiar ${result.updated}'
          : 'App IDs ejecutado: escaneados ${result.scanned}, cambiados ${result.updated}',
    );

    await _loadAll(forceEmpresaId: empresaId);
  }

  // ---------------- MIGRACIONES: ELIMINAR TODAS LAS TAREAS (EMPRESA ACTIVA) ----------------
  Future<bool> _confirmDeleteAllTasks(String empresaId) async {
    final controller = TextEditingController();
    String typed = '';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx2, setLocal) {
            final enabled = typed.trim().toUpperCase() == 'BORRAR';

            return AlertDialog(
              title: const Text(
                'Eliminar todas las tareas',
                style: TextStyle(
                  fontFamily: kArial,
                  fontWeight: FontWeight.w900,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Empresa activa: $empresaId',
                    style: const TextStyle(
                      fontFamily: kArial,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Esta acción eliminará TODAS las tareas de la empresa activa en TBL_TAREAS. '
                    'No se puede deshacer.',
                    style: TextStyle(fontFamily: kArial),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Escribe BORRAR para confirmar:',
                    style: TextStyle(fontFamily: kArial),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: controller,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                    style: const TextStyle(fontFamily: kArial),
                    onChanged: (v) => setLocal(() => typed = v),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text(
                    'Cancelar',
                    style: TextStyle(fontFamily: kArial),
                  ),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kAdminPrimary,
                  ),
                  onPressed: enabled ? () => Navigator.pop(ctx, true) : null,
                  icon: const Icon(Icons.delete_forever),
                  label: const Text(
                    'Eliminar',
                    style: TextStyle(
                      fontFamily: kArial,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
    return ok == true;
  }

  Future<void> _deleteAllTasksForEmpresa() async {
    final empresaId = _empresaId ?? '';
    if (empresaId.isEmpty) return;

    final ok = await _confirmDeleteAllTasks(empresaId);
    if (!ok) return;

    setState(() => _loading = true);

    const int batchLimit = 400;
    int deleted = 0;

    try {
      while (true) {
        final snap = await FirebaseFirestore.instance
            .collection('TBL_TAREAS')
            .where('empresaId', isEqualTo: empresaId)
            .limit(batchLimit)
            .get();
        if (snap.docs.isEmpty) break;

        final batch = FirebaseFirestore.instance.batch();
        for (final doc in snap.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
        deleted += snap.docs.length;
      }

      await _mig.logMigration(
        adminUserId: widget.userId,
        empresaId: empresaId,
        action: 'deleteAllTasksForEmpresa',
        scanned: deleted,
        updated: deleted,
        dryRun: false,
        extra: {'empresaId': empresaId},
      );

      _snack('Tareas eliminadas: $deleted');
    } finally {
      await _loadAll(forceEmpresaId: empresaId);
    }
  }

  // ---------------- LOGS ----------------
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _loadLogs() async {
    final empresaId = _empresaId ?? '';
    if (empresaId.isEmpty) return [];
    try {
      final snap = await FirebaseFirestore.instance
          .collection('TBL_MIGRATIONS_LOGS')
          .where('empresaId', isEqualTo: empresaId)
          .limit(200)
          .get();
      final docs = [...snap.docs];
      docs.sort((a, b) {
        final aTs = (a.data()['createdAt'] as Timestamp?) ?? Timestamp(0, 0);
        final bTs = (b.data()['createdAt'] as Timestamp?) ?? Timestamp(0, 0);
        return bTs.compareTo(aTs);
      });
      return docs.take(50).toList();
    } catch (e) {
      _snack('No fue posible cargar logs: $e');
      return [];
    }
  }

  // ---------------- LIMPIEZA: RESETEAR DATOS DE USUARIOS ----------------
  Future<void> _resetUsersData() async {
    final empresaId = _empresaId ?? '';
    if (empresaId.isEmpty) return;

    final ok = await _confirm(
      title: '⚠ RESETEAR DATOS DE USUARIOS',
      message:
          'Se borrarán Áreas, Cargos, Centros y Jefes solo para la empresa $empresaId en ${_users.length} usuarios.\n\n'
          'NO se borrarán las cuentas de acceso, ni permisos de otras empresas.\n'
          'Los usuarios quedarán listos para recibir una carga limpia desde Excel.',
      confirmText: 'SÍ, RESETEAR DATOS',
    );
    if (!ok) return;

    setState(() => _loading = true);

    int count = 0;
    WriteBatch batch = FirebaseFirestore.instance.batch();
    bool hasWrites = false;

    Future<void> commitBatch() async {
      if (!hasWrites) return;
      await batch.commit();
      batch = FirebaseFirestore.instance.batch();
      hasWrites = false;
    }

    for (final u in _users) {
      final ref = u.reference;
      final data = u.data();
      final updates = _buildScopedUserReset(data, empresaId);

      batch.update(ref, updates);
      count++;
      hasWrites = true;

      if (count % 400 == 0) {
        await commitBatch();
      }
    }

    await commitBatch();

    await _mig.logMigration(
      adminUserId: widget.userId,
      empresaId: empresaId,
      action: 'RESET_USERS_DATA',
      scanned: count,
      updated: count,
      dryRun: false,
    );

    setState(() => _loading = false);
    _snack('Se resetearon los datos de $count usuarios.');
    await _loadAll(forceEmpresaId: empresaId);
  }

  Map<String, dynamic> _buildScopedUserReset(
    Map<String, dynamic> data,
    String empresaId,
  ) {
    final rawEmpresas = data['empresas'] as List<dynamic>? ?? const [];
    final empresas = rawEmpresas
        .map((e) => _safe(e))
        .where((e) => e.isNotEmpty && e != empresaId)
        .toList();

    final rawDetalle = data['empresasDetalle'];
    final detalle = rawDetalle is Map<String, dynamic>
        ? Map<String, dynamic>.from(rawDetalle)
        : <String, dynamic>{};
    detalle.remove(empresaId);

    for (final id in detalle.keys) {
      if (!empresas.contains(id)) empresas.add(id);
    }

    final updates = <String, dynamic>{
      'empresasDetalle.$empresaId': FieldValue.delete(),
      'empresas': empresas,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    final currentEmpresaId = _safe(data['empresaId']);
    final shouldClearTopLevel =
        currentEmpresaId.isEmpty || currentEmpresaId == empresaId;
    if (!shouldClearTopLevel) return updates;

    Map<String, dynamic>? nextDetail;
    String nextEmpresaId = '';
    for (final id in empresas) {
      final value = detalle[id];
      if (value is Map<String, dynamic>) {
        nextDetail = value;
        nextEmpresaId = id;
        break;
      }
    }

    if (nextDetail != null && nextEmpresaId.isNotEmpty) {
      updates.addAll({
        'empresaId': nextEmpresaId,
        'empresaNombre': _safe(nextDetail['empresaNombre']).isNotEmpty
            ? _safe(nextDetail['empresaNombre'])
            : nextEmpresaId,
        'apps': nextDetail['apps'] ?? <String>[],
        'area': nextDetail['area'],
        'areaNombre': nextDetail['areaNombre'] ?? nextDetail['area'],
        'areaId': nextDetail['areaId'],
        'cargo': nextDetail['cargo'],
        'cargoNombre': nextDetail['cargoNombre'] ?? nextDetail['cargo'],
        'cargoId': nextDetail['cargoId'],
        'cargoJefe': nextDetail['cargoJefe'],
        'centroId': nextDetail['centroId'],
        'centroCostos': nextDetail['centroCostos'],
        'centroCodigo': nextDetail['centroCodigo'],
        'jefeId': nextDetail['jefeId'],
        'jefeNombre': nextDetail['jefeNombre'],
      });
    } else {
      updates.addAll({
        'apps': FieldValue.delete(),
        'empresaId': FieldValue.delete(),
        'empresaNombre': FieldValue.delete(),
        'areaId': FieldValue.delete(),
        'areaNombre': FieldValue.delete(),
        'area': FieldValue.delete(),
        'cargoId': FieldValue.delete(),
        'cargo': FieldValue.delete(),
        'cargoNombre': FieldValue.delete(),
        'cargoJefe': FieldValue.delete(),
        'centroId': FieldValue.delete(),
        'centroCostos': FieldValue.delete(),
        'centro_costos': FieldValue.delete(),
        'centroCodigo': FieldValue.delete(),
        'jefeId': FieldValue.delete(),
        'jefeNombre': FieldValue.delete(),
      });
    }

    return updates;
  }

  Future<void> _normalizeAppsCatalog() async {
    final empresaId = _empresaId ?? '';
    if (empresaId.isEmpty) return;

    final ok = await _confirm(
      title: 'Normalizar apps',
      message:
          'Se conservará una sola app por módulo en $empresaId usando el ID canónico.\n'
          'Ejemplo: TalentoHumanoDashboard quedará como talentohumanodashboard.',
      confirmText: 'NORMALIZAR',
    );
    if (!ok) return;

    setState(() => _loading = true);
    try {
      final changed = await _repo.normalizeAppCatalog(empresaId);
      _snack('Apps normalizadas. Cambios aplicados: $changed');
      await _loadAll(forceEmpresaId: empresaId);
    } catch (e) {
      _snack('No fue posible normalizar apps: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ---------------- LIMPIEZA: BORRAR CATÁLOGOS ----------------
  Future<void> _purgeCatalogs() async {
    final empresaId = _empresaId ?? '';
    if (empresaId.isEmpty) return;

    final ok = await _confirm(
      title: '⚠ BORRAR TODOS LOS CATÁLOGOS',
      message:
          'Se eliminarán TODAS las Áreas, Cargos y Centros de Costo de la empresa $empresaId.\n\n'
          'Haz esto solo si vas a volver a subir el archivo Excel completo.\n'
          '¿Estás seguro?',
      confirmText: 'BORRAR TODO',
    );
    if (!ok) return;

    setState(() => _loading = true);
    int deletedCount = 0;

    Future<void> deleteCollection(String collName) async {
      final snap = await FirebaseFirestore.instance
          .collection(collName)
          .where('empresaId', isEqualTo: empresaId)
          .get();
      for (final doc in snap.docs) {
        await doc.reference.delete();
        deletedCount++;
      }
    }

    await deleteCollection('TBL_AREAS');
    await deleteCollection('TBL_CARGOS');
    await deleteCollection('TBL_CENTROS_COSTOS');

    setState(() => _loading = false);
    _snack('Catálogos eliminados. Total documentos borrados: $deletedCount');
    await _loadAll(forceEmpresaId: empresaId);
  }

  // ---------------- LIMPIEZA: BORRAR ESTRUCTURA ORGANIZACIONAL ----------------
  Future<void> _purgeOrganizationalStructure() async {
    final ok = await _confirm(
      title: '⚠ BORRAR ESTRUCTURA ORGANIZACIONAL',
      message:
          'Se eliminarán TODOS los documentos en TBL_ESTRUCTURA_ORGANIZACIONAL.\n\n'
          'Úsalo solo si vas a volver a subir la estructura completa.\n'
          '¿Estás seguro?',
      confirmText: 'BORRAR ESTRUCTURA',
    );
    if (!ok) return;

    setState(() => _loading = true);

    int deletedCount = 0;
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection('TBL_ESTRUCTURA_ORGANIZACIONAL')
        .limit(400);

    while (true) {
      final snap = await query.get();
      if (snap.docs.isEmpty) break;

      WriteBatch batch = FirebaseFirestore.instance.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
        deletedCount++;
      }
      await batch.commit();

      final lastDoc = snap.docs.last;
      query = FirebaseFirestore.instance
          .collection('TBL_ESTRUCTURA_ORGANIZACIONAL')
          .startAfterDocument(lastDoc)
          .limit(400);
    }

    setState(() => _loading = false);
    _snack(
      'Estructura organizacional eliminada. Total documentos borrados: $deletedCount',
    );
    await _loadAll(forceEmpresaId: _empresaId ?? '');
  }

  Future<void> _pickDiagnosticosExcel() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xlsm', 'xls'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) return;

    final file = result.files.single;
    if (file.bytes == null || file.bytes!.isEmpty) {
      _snack('No se pudo leer el archivo seleccionado.');
      return;
    }

    setState(() {
      _diagnosticosFileName = file.name;
      _diagnosticosBytes = file.bytes;
      _diagnosticosImportResult = null;
    });
  }

  Future<void> _importarDiagnosticosExcel() async {
    final empresaId = _empresaId ?? '';
    final bytes = _diagnosticosBytes;

    if (empresaId.isEmpty) {
      _snack('Selecciona una empresa antes de importar diagnósticos.');
      return;
    }
    if (bytes == null || bytes.isEmpty) {
      _snack('Primero selecciona un archivo Excel.');
      return;
    }

    setState(() => _loading = true);
    try {
      final result = await _diagnosticosService.importarDiagnosticosDesdeExcel(
        bytes: bytes,
        empresaId: empresaId,
        sobrescribir: true,
      );
      if (!mounted) return;
      setState(() {
        _diagnosticosImportResult = result;
      });
      _snack(
        'Diagnósticos importados. Médicos: ${result['diagnosticosMedicos'] ?? 0} | Nutricionales: ${result['diagnosticosNutricionales'] ?? 0}',
      );
    } catch (e) {
      _snack('Error importando diagnósticos: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _pickProveedoresExcel() async {
    final picked = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xlsm', 'xls'],
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.first;
    setState(() {
      _proveedoresFileName = file.name;
      _proveedoresBytes = file.bytes;
      _proveedoresImportResult = null;
    });
  }

  Future<void> _importarProveedoresExcel() async {
    final empresaId = _empresaId ?? '';
    final bytes = _proveedoresBytes;
    if (empresaId.isEmpty) {
      _snack('Selecciona una empresa primero.');
      return;
    }
    if (bytes == null) {
      _snack('Primero selecciona un archivo Excel de proveedores.');
      return;
    }

    final ok = await _confirm(
      title: 'Importar proveedores desde Excel',
      message:
          'Se agregarán los proveedores del archivo a la empresa seleccionada. '
          'Los proveedores con NIT ya existente serán omitidos.',
      confirmText: 'Importar',
    );
    if (!ok) return;

    setState(() => _importandoProveedores = true);
    try {
      final parsed = _proveedoresParser.parse(
        bytes: bytes,
        empresaId: empresaId,
      );
      if (parsed.proveedores.isEmpty) {
        _snack('No se detectaron filas válidas en el archivo.');
        return;
      }

      final result = await ComprasService().importarProveedores(
        empresaId,
        parsed.proveedores,
      );
      if (!mounted) return;
      setState(() {
        _proveedoresImportResult = {
          'importados': result['importados'] ?? 0,
          'omitidos': (result['omitidos'] ?? 0) + parsed.skippedRows,
        };
      });
      _snack(
        'Proveedores importados: ${result['importados'] ?? 0} '
        '(omitidos: ${(result['omitidos'] ?? 0) + parsed.skippedRows}).',
      );
    } catch (e) {
      _snack('Error al importar proveedores: $e');
    } finally {
      if (mounted) setState(() => _importandoProveedores = false);
    }
  }

  Future<void> _pickProductosExcel() async {
    final picked = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xlsm', 'xls'],
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.first;
    setState(() {
      _productosFileName = file.name;
      _productosBytes = file.bytes;
      _productosImportResult = null;
    });
  }

  Future<void> _importarProductosExcel() async {
    final empresaId = _empresaId ?? '';
    final bytes = _productosBytes;
    if (empresaId.isEmpty) {
      _snack('Selecciona una empresa primero.');
      return;
    }
    if (bytes == null) {
      _snack('Primero selecciona un archivo Excel de productos.');
      return;
    }

    final ok = await _confirm(
      title: 'Importar productos desde Excel',
      message:
          'Se agregarán los productos del archivo a la empresa seleccionada. '
          'Los productos con código o nombre ya existente serán omitidos.',
      confirmText: 'Importar',
    );
    if (!ok) return;

    setState(() => _importandoProductos = true);
    try {
      final parsed = _productosParser.parse(
        bytes: bytes,
        empresaId: empresaId,
        categoriasValidas: kCategoriasCompras,
        unidadesValidas: kUnidadesMedida,
      );
      if (parsed.productos.isEmpty) {
        _snack('No se detectaron filas válidas en el archivo.');
        return;
      }

      final result = await ComprasService().importarProductos(
        empresaId,
        parsed.productos,
      );
      if (!mounted) return;
      setState(() {
        _productosImportResult = {
          'importados': result['importados'] ?? 0,
          'omitidos': (result['omitidos'] ?? 0) + parsed.skippedRows,
        };
      });
      _snack(
        'Productos importados: ${result['importados'] ?? 0} '
        '(omitidos: ${(result['omitidos'] ?? 0) + parsed.skippedRows}).',
      );
    } catch (e) {
      _snack('Error al importar productos: $e');
    } finally {
      if (mounted) setState(() => _importandoProductos = false);
    }
  }

  Future<void> _sembrarReqComprasBase() async {
    if (_empresaId == null || _empresaId!.isEmpty) {
      _snack('Selecciona una empresa primero.');
      return;
    }
    final ok = await _confirm(
      title: 'Cargar requisitos de Compras',
      message:
          'Esto reemplazará los requisitos documentales de Compras de la empresa seleccionada con la parametrización base (incluye proteína, abarrotes y aseo).',
      confirmText: 'Cargar',
    );
    if (!ok) return;

    setState(() => _importandoReqCompras = true);
    try {
      await sembrarReqDocumentos(_empresaId!, ComprasService());
      _snack('Requisitos de Compras cargados correctamente.');
    } catch (e) {
      _snack('Error al cargar requisitos de Compras: $e');
    } finally {
      if (mounted) setState(() => _importandoReqCompras = false);
    }
  }

  Future<void> _pickReqComprasExcel() async {
    final picked = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xlsm', 'xls'],
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.first;
    setState(() {
      _reqComprasFileName = file.name;
      _reqComprasBytes = file.bytes;
      _reqComprasImportResult = null;
    });
  }

  Future<void> _importarReqComprasExcel() async {
    final empresaId = _empresaId ?? '';
    final bytes = _reqComprasBytes;
    if (empresaId.isEmpty) {
      _snack('Selecciona una empresa primero.');
      return;
    }
    if (bytes == null) {
      _snack('Primero selecciona un archivo Excel.');
      return;
    }

    final ok = await _confirm(
      title: 'Importar REQ_DOCUMENTOS desde Excel',
      message:
          'Se reemplazarán los requisitos actuales de Compras para la empresa activa con lo cargado en el Excel.',
      confirmText: 'Importar',
    );
    if (!ok) return;

    setState(() => _importandoReqCompras = true);
    try {
      final parsed = _comprasReqParser.parse(
        bytes: bytes,
        empresaId: empresaId,
      );
      if (parsed.docs.isEmpty) {
        _snack('No se detectaron filas válidas en la hoja REQ_DOCUMENTOS.');
        return;
      }

      await ComprasService().importarReqDocumentos(empresaId, parsed.docs);
      if (!mounted) return;
      setState(() {
        _reqComprasImportResult = {
          'importados': parsed.docs.length,
          'omitidos': parsed.skippedRows,
        };
      });
      _snack(
        'Requisitos de Compras importados: ${parsed.docs.length} (omitidos: ${parsed.skippedRows}).',
      );
    } catch (e) {
      _snack('Error al importar requisitos de Compras: $e');
    } finally {
      if (mounted) setState(() => _importandoReqCompras = false);
    }
  }

  Widget _tabReqCompras() {
    final result = _reqComprasImportResult;
    final provResult = _proveedoresImportResult;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        AdminComprasDocumentControlPanel(
          userId: widget.userId,
          companyId: _empresaId ?? widget.empresaId,
        ),
        const SizedBox(height: 12),
        Card(
          color: kAdminCard,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.rule_folder, color: kAdminPrimary),
                    SizedBox(width: 8),
                    Text(
                      'Requisitos documentales de Compras',
                      style: TextStyle(
                        fontFamily: kArial,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  'Esta sección prepara la aplicación para exigir documentación desde la creación/recepción de productos según categoría (incluyendo proteína).',
                  style: TextStyle(fontFamily: kArial, height: 1.4),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.blue.shade100),
                  ),
                  child: const Text(
                    'Opciones disponibles:\n1) Cargar base REQ_DOCUMENTOS (v3).\n2) Subir tu Excel desde este panel para reemplazar la parametrización.',
                    style: TextStyle(fontFamily: kArial),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _importandoReqCompras
                      ? null
                      : _pickReqComprasExcel,
                  icon: const Icon(Icons.attach_file),
                  label: Text(
                    _reqComprasFileName == null
                        ? 'Seleccionar Excel REQ_DOCUMENTOS'
                        : _reqComprasFileName!,
                    style: const TextStyle(fontFamily: kArial),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F766E),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: _importandoReqCompras
                        ? null
                        : _importarReqComprasExcel,
                    icon: const Icon(Icons.file_upload_outlined),
                    label: const Text(
                      'Importar Excel de requisitos',
                      style: TextStyle(
                        fontFamily: kArial,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kAdminPrimary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: _importandoReqCompras
                        ? null
                        : _sembrarReqComprasBase,
                    icon: _importandoReqCompras
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.upload_file),
                    label: Text(
                      _importandoReqCompras
                          ? 'Cargando...'
                          : 'Cargar requisitos base de Compras',
                      style: const TextStyle(
                        fontFamily: kArial,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                if (result != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      border: Border.all(color: Colors.green.shade200),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Última importación: ${result['importados'] ?? 0} filas cargadas • ${result['omitidos'] ?? 0} omitidas.',
                      style: const TextStyle(fontFamily: kArial),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // ── Carga masiva de proveedores ──────────────────────────────────
        Card(
          color: kAdminCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.amber.shade200),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.store_outlined,
                      color: Color(0xFFB45309),
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Carga masiva de proveedores',
                      style: TextStyle(
                        fontFamily: kArial,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  'Sube un Excel con el maestro inicial de proveedores de la empresa. '
                  'Columnas requeridas: NIT, RAZON SOCIAL. '
                  'Opcionales: DIRECCION, TELEFONO, CORREO, DEPARTAMENTO, CIUDAD, PROV. LOCAL (SI/NO).\n'
                  'Los proveedores con NIT ya registrado serán omitidos.',
                  style: TextStyle(fontFamily: kArial, height: 1.4),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _importandoProveedores
                      ? null
                      : _pickProveedoresExcel,
                  icon: const Icon(Icons.attach_file),
                  label: Text(
                    _proveedoresFileName == null
                        ? 'Seleccionar Excel de proveedores'
                        : _proveedoresFileName!,
                    style: const TextStyle(fontFamily: kArial),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFB45309),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: _importandoProveedores
                        ? null
                        : _importarProveedoresExcel,
                    icon: _importandoProveedores
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.file_upload_outlined),
                    label: Text(
                      _importandoProveedores
                          ? 'Importando...'
                          : 'Importar proveedores desde Excel',
                      style: const TextStyle(
                        fontFamily: kArial,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                if (provResult != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      border: Border.all(color: Colors.amber.shade300),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Última importación: ${provResult['importados'] ?? 0} proveedores cargados • ${provResult['omitidos'] ?? 0} omitidos (NIT duplicado o fila inválida).',
                      style: const TextStyle(fontFamily: kArial),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // ── Carga masiva de productos ──────────────────────────────────
        Builder(
          builder: (_) {
            final prodResult = _productosImportResult;
            return Card(
              color: kAdminCard,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.green.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.inventory_2_outlined,
                          color: Colors.green.shade700,
                          size: 24,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Carga masiva de productos',
                          style: TextStyle(
                            fontFamily: kArial,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Sube un Excel con el maestro inicial de productos de la empresa. '
                      'Columnas requeridas: NOMBRE_PRODUCTO, CATEGORIA, UNIDAD_MEDIDA. '
                      'Opcionales: CODIGO_PRODUCTO, ORIGEN (NACIONAL/IMPORTADO), PERECEDERO (SI/NO).\n'
                      'Los productos con código o nombre ya registrado serán omitidos.',
                      style: TextStyle(fontFamily: kArial, height: 1.4),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _importandoProductos
                          ? null
                          : _pickProductosExcel,
                      icon: const Icon(Icons.attach_file),
                      label: Text(
                        _productosFileName == null
                            ? 'Seleccionar Excel de productos'
                            : _productosFileName!,
                        style: const TextStyle(fontFamily: kArial),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: _importandoProductos
                            ? null
                            : _importarProductosExcel,
                        icon: _importandoProductos
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.file_upload_outlined),
                        label: Text(
                          _importandoProductos
                              ? 'Importando...'
                              : 'Importar productos desde Excel',
                          style: const TextStyle(
                            fontFamily: kArial,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    if (prodResult != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          border: Border.all(color: Colors.green.shade300),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'Última importación: ${prodResult['importados'] ?? 0} productos cargados • ${prodResult['omitidos'] ?? 0} omitidos (duplicado o fila inválida).',
                          style: const TextStyle(fontFamily: kArial),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _tabDiagnosticos() {
    final result = _diagnosticosImportResult;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: Colors.teal.shade50,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.teal.shade200),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.upload_file,
                      color: Colors.teal.shade900,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Actualizar diagnósticos',
                        style: TextStyle(
                          fontFamily: kArial,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: Colors.teal.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Sube un Excel con diagnósticos para actualizar el catálogo '
                  'de diagnósticos en Firestore.\n'
                  'Después de importar, el buscador de diagnóstico clínico leerá primero desde Firestore.',
                  style: TextStyle(fontFamily: kArial, height: 1.4),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _pickDiagnosticosExcel,
                  icon: const Icon(Icons.description_outlined),
                  label: const Text(
                    'Seleccionar archivo Excel',
                    style: TextStyle(
                      fontFamily: kArial,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _diagnosticosFileName == null
                      ? 'Sin archivo seleccionado.'
                      : 'Archivo: $_diagnosticosFileName',
                  style: const TextStyle(fontFamily: kArial),
                ),
                if (result != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Última carga → Médicos: ${result['diagnosticosMedicos'] ?? 0} | Nutricionales: ${result['diagnosticosNutricionales'] ?? 0}',
                    style: const TextStyle(
                      fontFamily: kArial,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: _importarDiagnosticosExcel,
                    icon: const Icon(Icons.cloud_upload),
                    label: const Text(
                      'IMPORTAR DIAGNÓSTICOS',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ---------------- LIMPIEZA: NOTIFICACIONES ----------------

  /// Cuenta notificaciones de un usuario.
  /// Si [empresaId] se provee, filtra client-side por coincidencia exacta.
  Future<int> _countUserNotifs({
    required String userId,
    String? empresaId,
    required bool soloNoLeidas,
  }) async {
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('TBL_NOTIFICACIONES')
        .doc(userId)
        .collection('notifications');
    if (soloNoLeidas) q = q.where('read', isEqualTo: false);
    final snap = await q.get();
    if (empresaId != null && empresaId.isNotEmpty) {
      return snap.docs.where((d) {
        final eid = (d.data()['empresaId'] ?? '').toString().trim();
        return eid == empresaId;
      }).length;
    }
    return snap.docs.length;
  }

  /// Elimina notificaciones de un usuario. Retorna la cantidad borrada.
  /// Procesa en batches de 400 para respetar el límite de Firestore.
  Future<int> _deleteUserNotifs({
    required String userId,
    String? empresaId,
    required bool soloNoLeidas,
  }) async {
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('TBL_NOTIFICACIONES')
        .doc(userId)
        .collection('notifications');
    if (soloNoLeidas) q = q.where('read', isEqualTo: false);
    final snap = await q.get();

    final toDelete = (empresaId != null && empresaId.isNotEmpty)
        ? snap.docs.where((d) {
            final eid = (d.data()['empresaId'] ?? '').toString().trim();
            return eid == empresaId;
          }).toList()
        : snap.docs.toList();

    if (toDelete.isEmpty) return 0;

    int deleted = 0;
    for (var i = 0; i < toDelete.length; i += 400) {
      final end = (i + 400 < toDelete.length) ? i + 400 : toDelete.length;
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in toDelete.sublist(i, end)) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      deleted += end - i;
    }
    return deleted;
  }

  /// Limpia notificaciones de todos los usuarios de la empresa activa.
  /// Muestra preview de cuántas hay antes de confirmar.
  Future<void> _cleanNotificacionesEmpresa({required bool soloNoLeidas}) async {
    final empresaId = _empresaId;
    if (empresaId == null || empresaId.isEmpty) {
      _snack('Selecciona una empresa primero.');
      return;
    }
    if (_users.isEmpty) {
      _snack('No hay usuarios cargados para esta empresa.');
      return;
    }

    setState(() => _loading = true);
    int totalCount = 0;
    try {
      for (final u in _users) {
        totalCount += await _countUserNotifs(
          userId: u.id,
          empresaId: empresaId,
          soloNoLeidas: soloNoLeidas,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _snack('Error al contar: $e');
      }
      return;
    }
    if (mounted) setState(() => _loading = false);
    if (!mounted) return;

    if (totalCount == 0) {
      _snack(
        'No hay ${soloNoLeidas ? "notificaciones no leídas" : "notificaciones"} en $empresaId.',
      );
      return;
    }

    final tipo = soloNoLeidas ? 'no leídas' : '(leídas y no leídas)';
    final ok = await _confirm(
      title: '⚠ Limpiar notificaciones — empresa',
      message:
          'Se eliminarán $totalCount notificaciones $tipo de la empresa "$empresaId"\n'
          '(${_users.length} usuario${_users.length == 1 ? "" : "s"} revisados).\n\n'
          'Notificaciones sin empresaId (legacy) también se incluyen.\n\n'
          'Esta acción es irreversible. ¿Continuar?',
      confirmText: 'BORRAR $totalCount',
    );
    if (!ok || !mounted) return;

    setState(() => _loading = true);
    try {
      int deleted = 0;
      for (final u in _users) {
        deleted += await _deleteUserNotifs(
          userId: u.id,
          empresaId: empresaId,
          soloNoLeidas: soloNoLeidas,
        );
      }
      if (mounted) {
        _snack('✅ $deleted notificaciones eliminadas de "$empresaId".');
      }
    } catch (e) {
      if (mounted) _snack('Error al borrar: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Limpia notificaciones de un usuario específico.
  Future<void> _cleanNotificacionesUsuario({
    required String userId,
    required bool soloNoLeidas,
  }) async {
    if (userId.isEmpty) {
      _snack('Selecciona un usuario.');
      return;
    }
    final empresaId = _empresaId;

    setState(() => _loading = true);
    int totalCount = 0;
    try {
      totalCount = await _countUserNotifs(
        userId: userId,
        empresaId: empresaId,
        soloNoLeidas: soloNoLeidas,
      );
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _snack('Error al contar: $e');
      }
      return;
    }
    if (mounted) setState(() => _loading = false);
    if (!mounted) return;

    if (totalCount == 0) {
      _snack(
        'No hay ${soloNoLeidas ? "notificaciones no leídas" : "notificaciones"} para $userId.',
      );
      return;
    }

    final tipo = soloNoLeidas ? 'no leídas' : '(leídas y no leídas)';
    final empresaLabel = (empresaId != null && empresaId.isNotEmpty)
        ? ' — empresa "$empresaId"'
        : ' — todas las empresas';
    final ok = await _confirm(
      title: '⚠ Limpiar notificaciones — usuario',
      message:
          'Se eliminarán $totalCount notificaciones $tipo\n'
          'del usuario: $userId$empresaLabel.\n\n'
          'Esta acción es irreversible. ¿Continuar?',
      confirmText: 'BORRAR $totalCount',
    );
    if (!ok || !mounted) return;

    setState(() => _loading = true);
    try {
      final deleted = await _deleteUserNotifs(
        userId: userId,
        empresaId: empresaId,
        soloNoLeidas: soloNoLeidas,
      );
      if (mounted) _snack('✅ $deleted notificaciones eliminadas de "$userId".');
    } catch (e) {
      if (mounted) _snack('Error al borrar: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  AdminModuleCloseoutRequest? _moduleCloseoutRequest() {
    final empresaId = (_empresaId ?? '').trim();
    if (empresaId.isEmpty || _moduleCloseoutModules.isEmpty) return null;
    return AdminModuleCloseoutRequest(
      empresaId: empresaId,
      userIds: _users.map((user) => user.id).toList(growable: false),
      cutoff: _moduleCloseoutCutoff,
      range: _moduleCloseoutRange,
      modules: Set.unmodifiable(_moduleCloseoutModules),
    );
  }

  Future<void> _pickModuleCloseoutCutoff() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _moduleCloseoutCutoff,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'Selecciona la fecha de corte',
    );
    if (selected == null || !mounted) return;
    setState(() {
      _moduleCloseoutCutoff = selected;
      _moduleCloseoutPreview = null;
    });
  }

  Future<void> _previewModuleCloseout() async {
    final request = _moduleCloseoutRequest();
    if (request == null) {
      _snack('Selecciona empresa y al menos un módulo.');
      return;
    }
    setState(() {
      _moduleCloseoutBusy = true;
      _moduleCloseoutPreview = null;
    });
    try {
      final preview = await _moduleCloseoutService.preview(request);
      if (!mounted) return;
      setState(() => _moduleCloseoutPreview = preview);
      if (!preview.hayAlgo) {
        _snack(
          'No hay tareas abiertas ni notificaciones pendientes en ese corte.',
        );
      }
    } catch (error) {
      if (mounted) _snack('No fue posible calcular la vista previa: $error');
    } finally {
      if (mounted) setState(() => _moduleCloseoutBusy = false);
    }
  }

  Future<void> _applyModuleCloseout() async {
    final request = _moduleCloseoutRequest();
    final preview = _moduleCloseoutPreview;
    if (request == null || preview == null) return;
    final date = DateFormat('dd/MM/yyyy').format(request.cutoff);
    final modules = request.modules
        .map(
          (module) =>
              module == 'interventoria' ? 'Interventoría' : 'Facturación',
        )
        .join(' y ');
    final confirmed = await _confirm(
      title: 'Confirmar cierre administrativo',
      message:
          'Empresa: ${request.empresaId}\n'
          'Módulos: $modules\n'
          'Corte: ${request.range.label.toLowerCase()} $date\n\n'
          'Se finalizarán ${preview.tasks} tarea(s) abierta(s), se marcarán '
          'como leídas ${preview.notifications} notificación(es) y se darán '
          'por subsanados ${preview.hallazgosSinAsignar} hallazgo(s) de '
          'interventoría que nunca se asignaron.\n\n'
          'No se borrarán tareas, avances, adjuntos, actas, documentos ni '
          'notificaciones. La operación quedará auditada.',
      confirmText: 'CERRAR Y MARCAR LEÍDAS',
    );
    if (!confirmed || !mounted) return;

    setState(() => _moduleCloseoutBusy = true);
    try {
      final result = await _moduleCloseoutService.apply(
        request: request,
        adminUserId: widget.userId,
      );
      await _mig.logMigration(
        adminUserId: widget.userId,
        empresaId: request.empresaId,
        action: 'adminModuleCloseout',
        scanned: result.tasksClosed + result.notificationsRead,
        updated: result.tasksClosed + result.notificationsRead,
        dryRun: false,
        extra: {
          'cutoff': request.cutoff.toIso8601String(),
          'range': request.range.auditValue,
          'modules': request.modules.toList(),
          'tasksClosed': result.tasksClosed,
          'notificationsRead': result.notificationsRead,
          'hallazgosClosed': result.hallazgosClosed,
          'facturacionItemsClosed': result.facturacionItemsClosed,
        },
      );
      if (!mounted) return;
      setState(() => _moduleCloseoutPreview = null);
      _snack(
        'Cierre listo: ${result.tasksClosed} tareas finalizadas y '
        '${result.notificationsRead} notificaciones marcadas como leídas.',
      );
    } catch (error) {
      if (mounted) _snack('No fue posible completar el cierre: $error');
    } finally {
      if (mounted) setState(() => _moduleCloseoutBusy = false);
    }
  }

  Widget _moduleCloseoutCard() {
    final preview = _moduleCloseoutPreview;
    final canApply =
        !_moduleCloseoutBusy &&
        preview != null &&
        preview.hayAlgo;
    return Card(
      color: const Color(0xFFEFF6FF),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFF93C5FD)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.task_alt_rounded,
                  color: Color(0xFF1D4ED8),
                  size: 28,
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Cierre por módulo y fecha',
                    style: TextStyle(
                      fontFamily: kArial,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF1E3A8A),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Finaliza tareas abiertas y marca sus notificaciones como leídas. '
              'Conserva avances, archivos y trazabilidad; no elimina información.',
              style: TextStyle(fontFamily: kArial, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 720;
                final dateField = OutlinedButton.icon(
                  onPressed: _moduleCloseoutBusy
                      ? null
                      : _pickModuleCloseoutCutoff,
                  icon: const Icon(Icons.calendar_month_rounded),
                  label: Text(
                    'Fecha de corte: ${DateFormat('dd/MM/yyyy').format(_moduleCloseoutCutoff)}',
                  ),
                );
                final rangeField = DropdownButtonFormField<AdminCloseoutRange>(
                  initialValue: _moduleCloseoutRange,
                  decoration: const InputDecoration(
                    labelText: 'Periodo que se cerrará',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: AdminCloseoutRange.values
                      .map(
                        (range) => DropdownMenuItem(
                          value: range,
                          child: Text(range.label),
                        ),
                      )
                      .toList(),
                  onChanged: _moduleCloseoutBusy
                      ? null
                      : (range) {
                          if (range == null) return;
                          setState(() {
                            _moduleCloseoutRange = range;
                            _moduleCloseoutPreview = null;
                          });
                        },
                );
                if (compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      dateField,
                      const SizedBox(height: 10),
                      rangeField,
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: dateField),
                    const SizedBox(width: 12),
                    Expanded(child: rangeField),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            const Text(
              'Módulos incluidos',
              style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in const {
                  'interventoria': 'Interventoría',
                  'facturacion': 'Facturación',
                }.entries)
                  FilterChip(
                    label: Text(entry.value),
                    selected: _moduleCloseoutModules.contains(entry.key),
                    onSelected: _moduleCloseoutBusy
                        ? null
                        : (selected) {
                            setState(() {
                              final modules = Set<String>.from(
                                _moduleCloseoutModules,
                              );
                              selected
                                  ? modules.add(entry.key)
                                  : modules.remove(entry.key);
                              _moduleCloseoutModules = modules;
                              _moduleCloseoutPreview = null;
                            });
                          },
                  ),
              ],
            ),
            if (preview != null) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFBFDBFE)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 20,
                      runSpacing: 8,
                      children: [
                        Text(
                          '${preview.tasks} tareas abiertas',
                          style: const TextStyle(
                            fontFamily: kArial,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          '${preview.notifications} notificaciones no leídas',
                          style: const TextStyle(
                            fontFamily: kArial,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          '${preview.hallazgosSinAsignar} hallazgos sin asignar',
                          style: const TextStyle(
                            fontFamily: kArial,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Interventoría: ${preview.tasksByModule['interventoria'] ?? 0} tareas · '
                      '${preview.notificationsByModule['interventoria'] ?? 0} avisos  |  '
                      'Facturación: ${preview.tasksByModule['facturacion'] ?? 0} tareas · '
                      '${preview.notificationsByModule['facturacion'] ?? 0} avisos',
                      style: const TextStyle(
                        fontFamily: kArial,
                        fontSize: 12,
                        color: Color(0xFF475569),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed:
                      _moduleCloseoutBusy || _moduleCloseoutModules.isEmpty
                      ? null
                      : _previewModuleCloseout,
                  icon: _moduleCloseoutBusy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.manage_search_rounded),
                  label: const Text('Ver impacto'),
                ),
                FilledButton.icon(
                  onPressed: canApply ? _applyModuleCloseout : null,
                  icon: const Icon(Icons.done_all_rounded),
                  label: const Text('Finalizar y marcar leídas'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabCleanup() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _moduleCloseoutCard(),
        const SizedBox(height: 24),
        Card(
          color: Colors.orange.shade50,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.orange.shade200),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.person_remove_outlined,
                      color: Colors.orange.shade900,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Resetear datos de Usuarios',
                        style: TextStyle(
                          fontFamily: kArial,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: Colors.orange.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Esta opción NO borra al usuario ni su contraseña. Limpia cargos, áreas, centros y jefes solo en la empresa activa.\n'
                  'Úsalo antes de subir un Excel actualizado.',
                  style: TextStyle(fontFamily: kArial, height: 1.4),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange.shade800,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: _resetUsersData,
                    icon: const Icon(Icons.cleaning_services),
                    label: const Text(
                      'LIMPIAR DATOS DE USUARIOS',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Card(
          color: Colors.red.shade50,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.red.shade200),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.account_tree_outlined,
                      color: Colors.red.shade900,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Purgar Estructura Organizacional',
                        style: TextStyle(
                          fontFamily: kArial,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: Colors.red.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Elimina TODOS los documentos de TBL_ESTRUCTURA_ORGANIZACIONAL para esta empresa.',
                  style: TextStyle(fontFamily: kArial, height: 1.4),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade800,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: _purgeOrganizationalStructure,
                    icon: const Icon(Icons.delete_forever),
                    label: const Text(
                      'BORRAR ESTRUCTURA',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Card(
          color: Colors.red.shade50,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.red.shade200),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.folder_delete_outlined,
                      color: Colors.red.shade900,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Purgar Catálogos (Áreas/Cargos)',
                        style: TextStyle(
                          fontFamily: kArial,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: Colors.red.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Elimina TODAS las Áreas, Cargos y Centros de esta empresa. Úsalo si vas a re-subir la estructura completa.',
                  style: TextStyle(fontFamily: kArial, height: 1.4),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade800,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: _purgeCatalogs,
                    icon: const Icon(Icons.delete_sweep),
                    label: const Text(
                      'BORRAR TODOS LOS CATÁLOGOS',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        // ---- Notificaciones ----
        Card(
          color: Colors.teal.shade50,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.teal.shade200),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.notifications_off_outlined,
                      color: Colors.teal.shade900,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Limpiar Notificaciones',
                        style: TextStyle(
                          fontFamily: kArial,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: Colors.teal.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Elimina entradas de TBL_NOTIFICACIONES para pruebas limpias. '
                  'No afecta tareas, usuarios ni otras tablas. '
                  'Muestra cuántas hay antes de confirmar.',
                  style: TextStyle(
                    fontFamily: kArial,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),

                // --- Por empresa activa ---
                const Divider(height: 28),
                Text(
                  'Por empresa activa${_empresaId != null ? " (${_empresaId!})" : ""}',
                  style: TextStyle(
                    fontFamily: kArial,
                    fontWeight: FontWeight.w700,
                    color: Colors.teal.shade800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_users.length} usuario${_users.length == 1 ? "" : "s"} cargados.',
                  style: TextStyle(
                    fontFamily: kArial,
                    fontSize: 12,
                    color: Colors.teal.shade700,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.teal.shade800,
                          side: BorderSide(color: Colors.teal.shade400),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        onPressed: (_empresaId == null || _users.isEmpty)
                            ? null
                            : () => _cleanNotificacionesEmpresa(
                                soloNoLeidas: true,
                              ),
                        icon: const Icon(
                          Icons.mark_email_unread_outlined,
                          size: 18,
                        ),
                        label: const Text(
                          'Solo no leídas',
                          style: TextStyle(fontFamily: kArial, fontSize: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        onPressed: (_empresaId == null || _users.isEmpty)
                            ? null
                            : () => _cleanNotificacionesEmpresa(
                                soloNoLeidas: false,
                              ),
                        icon: const Icon(Icons.delete_sweep, size: 18),
                        label: const Text(
                          'Todas',
                          style: TextStyle(fontFamily: kArial, fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ),

                // --- Por usuario ---
                const Divider(height: 28),
                Text(
                  'Por usuario específico',
                  style: TextStyle(
                    fontFamily: kArial,
                    fontWeight: FontWeight.w700,
                    color: Colors.teal.shade800,
                  ),
                ),
                const SizedBox(height: 10),
                if (_users.isEmpty)
                  const Text(
                    'Selecciona una empresa primero para cargar usuarios.',
                    style: TextStyle(
                      fontFamily: kArial,
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  )
                else
                  DropdownButtonFormField<String>(
                    initialValue: _notifCleanUserId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Usuario (cédula)',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      labelStyle: TextStyle(fontFamily: kArial),
                    ),
                    items: _users.map((u) {
                      final data = u.data();
                      final nombre = _userName(data, u.id);
                      return DropdownMenuItem<String>(
                        value: u.id,
                        child: Text(
                          '$nombre  (${u.id})',
                          style: const TextStyle(
                            fontFamily: kArial,
                            fontSize: 13,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (v) => setState(() => _notifCleanUserId = v),
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.teal.shade800,
                          side: BorderSide(color: Colors.teal.shade400),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        onPressed: _notifCleanUserId == null
                            ? null
                            : () => _cleanNotificacionesUsuario(
                                userId: _notifCleanUserId!,
                                soloNoLeidas: true,
                              ),
                        icon: const Icon(
                          Icons.mark_email_unread_outlined,
                          size: 18,
                        ),
                        label: const Text(
                          'Solo no leídas',
                          style: TextStyle(fontFamily: kArial, fontSize: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        onPressed: _notifCleanUserId == null
                            ? null
                            : () => _cleanNotificacionesUsuario(
                                userId: _notifCleanUserId!,
                                soloNoLeidas: false,
                              ),
                        icon: const Icon(Icons.delete_sweep, size: 18),
                        label: const Text(
                          'Todas',
                          style: TextStyle(fontFamily: kArial, fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWeb = width >= 900;

    return GuardedModulePage(
      userIdentity: widget.userId,
      appId: 'admindashboard',
      pageTitle: 'Admin Dashboard',
      fallbackEmpresaId: widget.empresaId,
      child: InternalModuleLayout(
        userId: widget.userId,
        empresaId: widget.empresaId,
        title: 'Panel de Administración',
        subtitle: 'Configuración global de usuarios, empresas y catálogos',
        accentColor: kAdminAccent,
        headerActions: [
          CompanyNameWidget(
            empresaId: widget.empresaId,
            style: TextStyle(
              color: isWeb ? kAdminAccent : Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: isWeb ? 14 : 12,
            ),
          ),
        ],
        child: _buildModuleBody(isWeb: isWeb),
      ),
    );
  }

  Widget _buildModuleBody({required bool isWeb}) {
    return Column(
      children: [
        if (isWeb)
          InternalModuleTabs(
            items: _kAdminModuleTabs,
            selectedIndex: _tabController.index,
            onSelected: (index) {
              _tabController.animateTo(index);
            },
            accentColor: kAdminAccent,
            compact: true,
          )
        else
          _buildMobileAdminSectionPicker(),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(
                  controller: _tabController,
                  physics: const NeverScrollableScrollPhysics(),
                  children: _allTabs(),
                ),
        ),
      ],
    );
  }

  Widget _buildMobileAdminSectionPicker() {
    final selectedIndex = _tabController.index < _kAdminModuleTabs.length
        ? _tabController.index
        : 0;
    final selectedItem = _kAdminModuleTabs[selectedIndex];

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: kAdminBorder)),
      ),
      child: DropdownButtonFormField<int>(
        initialValue: selectedIndex,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: 'Sección del panel',
          prefixIcon: Icon(selectedItem.icon, color: kAdminAccent, size: 20),
          filled: true,
          fillColor: kAdminBg,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kAdminBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kAdminBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kAdminAccent, width: 1.4),
          ),
        ),
        style: const TextStyle(
          fontFamily: kArial,
          fontSize: 14,
          fontWeight: FontWeight.w800,
          color: kAdminPrimary,
        ),
        items: List.generate(_kAdminModuleTabs.length, (index) {
          final item = _kAdminModuleTabs[index];
          return DropdownMenuItem<int>(
            value: index,
            child: Row(
              children: [
                Icon(item.icon, size: 18, color: kAdminMuted),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item.label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: kArial,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
        onChanged: (index) {
          if (index == null) return;
          _tabController.animateTo(index);
        },
      ),
    );
  }

  List<Tab> _allTabItems() {
    return const [
      Tab(icon: Icon(Icons.people_alt, size: 20), text: 'Usuarios'),
      Tab(icon: Icon(Icons.apps, size: 20), text: 'Apps'),
      Tab(
        icon: Icon(Icons.admin_panel_settings_outlined, size: 20),
        text: 'Roles y permisos',
      ),
      Tab(icon: Icon(Icons.account_tree, size: 20), text: 'Catálogos'),
      Tab(icon: Icon(Icons.construction, size: 20), text: 'Migraciones'),
      Tab(icon: Icon(Icons.history, size: 20), text: 'Logs'),
      Tab(icon: Icon(Icons.security_rounded, size: 20), text: 'Seguridad'),
      Tab(icon: Icon(Icons.cleaning_services, size: 20), text: 'Limpieza'),
      Tab(
        icon: Icon(Icons.medical_information, size: 20),
        text: 'Diagnósticos',
      ),
      Tab(icon: Icon(Icons.shopping_bag_outlined, size: 20), text: 'Compras'),
      Tab(icon: Icon(Icons.alternate_email, size: 20), text: 'Correo'),
      Tab(icon: Icon(Icons.vpn_key_outlined, size: 20), text: 'Tokens DIAN'),
      Tab(icon: Icon(Icons.chat_outlined, size: 20), text: 'WhatsApp'),
      Tab(
        icon: Icon(Icons.health_and_safety, size: 20),
        text: 'Salud usuarios',
      ),
      Tab(icon: Icon(Icons.badge, size: 20), text: 'Salud cargos'),
      Tab(icon: Icon(Icons.apartment, size: 20), text: 'Membresía'),
    ];
  }

  List<Widget> _allTabs() {
    return [
      _tabUsuarios(),
      _tabApps(),
      _tabAccessRoles(),
      _tabCatalogos(),
      _tabMigraciones(),
      _tabLogs(),
      SecurityAdminPanel(empresaId: _empresaId ?? widget.empresaId),
      _tabCleanup(),
      _tabDiagnosticos(),
      _tabReqCompras(),
      AdminCorreoPanel(
        userId: widget.userId,
        empresaId: _empresaId ?? widget.empresaId,
      ),
      AdminDianTokensPanel(
        userId: widget.userId,
        empresaId: _empresaId ?? widget.empresaId,
      ),
      AdminWhatsAppPanel(
        userId: widget.userId,
        empresaId: _empresaId ?? widget.empresaId,
      ),
      _tabSaludUsuarios(),
      _tabSaludCargos(),
      _tabMembresia(),
    ];
  }

  // Layout legado del admin anterior; se conserva mientras toda la navegación
  // usa InternalModuleLayout.
  // ignore: unused_element
  Widget _buildSidebar() {
    final items = [
      {'icon': Icons.people_alt, 'label': 'Usuarios'},
      {'icon': Icons.apps, 'label': 'Apps'},
      {
        'icon': Icons.admin_panel_settings_outlined,
        'label': 'Roles y permisos',
      },
      {'icon': Icons.account_tree, 'label': 'Catálogos'},
      {'icon': Icons.construction, 'label': 'Migraciones'},
      {'icon': Icons.history, 'label': 'Logs de Sistema'},
      {'icon': Icons.cleaning_services, 'label': 'Limpieza'},
      {'icon': Icons.medical_information, 'label': 'Diagnósticos'},
      {'icon': Icons.shopping_bag_outlined, 'label': 'Compras'},
    ];

    return Container(
      width: 260,
      color: kAdminPrimary,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            alignment: Alignment.centerLeft,
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TODO',
                  style: TextStyle(
                    color: kAdminAccent,
                    fontFamily: kArial,
                    fontWeight: FontWeight.w900,
                    fontSize: 24,
                  ),
                ),
                Text(
                  'ADMIN CONSOLE',
                  style: TextStyle(
                    color: Colors.white54,
                    fontFamily: kArial,
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white10, height: 1),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, index) {
                final isSelected = _tabController.index == index;
                final item = items[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 2,
                  ),
                  child: ListTile(
                    onTap: () => setState(() => _tabController.index = index),
                    selected: isSelected,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    selectedTileColor: Colors.white.withValues(alpha: 0.1),
                    leading: Icon(
                      item['icon'] as IconData,
                      color: isSelected ? kAdminAccent : Colors.white60,
                      size: 20,
                    ),
                    title: Text(
                      item['label'] as String,
                      style: TextStyle(
                        fontFamily: kArial,
                        fontSize: 14,
                        fontWeight: isSelected
                            ? FontWeight.w800
                            : FontWeight.w500,
                        color: isSelected ? Colors.white : Colors.white60,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const Divider(color: Colors.white10, height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'v1.2.0-admin',
              style: TextStyle(
                color: Colors.white24,
                fontFamily: kArial,
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Layout legado del admin anterior; se conserva mientras toda la navegación
  // usa InternalModuleLayout.
  // ignore: unused_element
  Widget _buildWebHeader() {
    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: kAdminBorder)),
      ),
      child: Row(
        children: [
          Text(
            _allTabItems()[_tabController.index].text!,
            style: const TextStyle(
              fontFamily: kArial,
              fontWeight: FontWeight.w900,
              fontSize: 20,
              color: kAdminPrimary,
            ),
          ),
          const Spacer(),
          _buildEmpresaSelectorWeb(),
        ],
      ),
    );
  }

  Widget _buildEmpresaSelectorWeb() {
    return Container(
      width: 350,
      decoration: BoxDecoration(
        color: kAdminBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kAdminBorder),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _empresaId,
          isExpanded: true,
          icon: const Icon(Icons.business, color: kAdminPrimary, size: 20),
          items: _empresas
              .map(
                (e) => DropdownMenuItem(
                  value: e.empresaId,
                  child: _empresaDropdownLabel(e),
                ),
              )
              .toList(),
          onChanged: (v) async {
            if (v == null || v.isEmpty) return;
            await _loadAll(forceEmpresaId: v);
          },
        ),
      ),
    );
  }

  // Layout legado del admin anterior; se conserva mientras toda la navegación
  // usa InternalModuleLayout.
  // ignore: unused_element
  Widget _buildEmpresaHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'EMPRESA ACTUAL',
            style: TextStyle(
              fontFamily: kArial,
              fontWeight: FontWeight.w900,
              fontSize: 10,
              color: kAdminMuted,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: kAdminBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: kAdminBorder),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _empresaId,
                isExpanded: true,
                icon: const Icon(
                  Icons.business,
                  color: kAdminPrimary,
                  size: 20,
                ),
                items: _empresas
                    .map(
                      (e) => DropdownMenuItem(
                        value: e.empresaId,
                        child: _empresaDropdownLabel(e),
                      ),
                    )
                    .toList(),
                onChanged: (v) async {
                  if (v == null || v.isEmpty) return;
                  await _loadAll(forceEmpresaId: v);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- TAB: USUARIOS ----------------
  Widget _tabUsuarios() {
    final filtered = _applyPersonnelFilter(
      _users,
      search: _userSearch,
      areaId: _userAreaFilter,
    );

    final activeAreas = _areas.where((a) => a.enabled).toList();
    final isMobile = MediaQuery.of(context).size.width < 700;

    return Padding(
      padding: EdgeInsets.all(isMobile ? 12 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildUsersHeader(activeAreas, isMobile),
          SizedBox(height: isMobile ? 16 : 24),
          Expanded(
            child: ListView.separated(
              itemCount: filtered.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (_, i) {
                final uDoc = filtered[i];
                final d = uDoc.data();
                final nombre = _userName(d, uDoc.id);
                final cedula = _safe(d['cedula']).isNotEmpty
                    ? _safe(d['cedula'])
                    : uDoc.id;
                final scoped = getUserCompanyDetail(d, _empresaId);
                final cargo = _safe(scoped?['cargo']).isNotEmpty
                    ? _safe(scoped?['cargo'])
                    : _safe(d['cargo']);
                final centro = _safe(scoped?['centroCostos']).isNotEmpty
                    ? _safe(scoped?['centroCostos'])
                    : _safe(d['centroCostos']);
                final area = _safe(scoped?['areaNombre']).isNotEmpty
                    ? _safe(scoped?['areaNombre'])
                    : _safe(d['areaNombre']);
                final rolDocumental = _safe(scoped?['rolDocumental']).isNotEmpty
                    ? _safe(scoped?['rolDocumental'])
                    : _safe(d['rolDocumental']);
                final rolPlanillas = _safe(scoped?['rolPlanillas']).isNotEmpty
                    ? _safe(scoped?['rolPlanillas'])
                    : _safe(d['rolPlanillas']);
                final apps = (_userApps[uDoc.id] ?? {}).toList()..sort();

                return Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: kAdminBorder),
                  ),
                  color: Colors.white,
                  child: Padding(
                    padding: EdgeInsets.all(isMobile ? 12 : 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            UserAvatar(
                              userId: uDoc.id,
                              nameHint: nombre,
                              radius: 22,
                              backgroundColor: kAdminPrimary.withValues(
                                alpha: 0.05,
                              ),
                              foregroundColor: kAdminPrimary,
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  UserNameText(
                                    uDoc.id,
                                    fallbackName: nombre,
                                    style: const TextStyle(
                                      fontFamily: kArial,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Cédula: $cedula • ID: ${uDoc.id}',
                                    maxLines: isMobile ? 2 : 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontFamily: kArial,
                                      fontSize: 12,
                                      color: kAdminMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            PopupMenuButton<String>(
                              icon: const Icon(
                                Icons.more_vert,
                                color: kAdminMuted,
                              ),
                              onSelected: (v) async {
                                if (v == 'apps') await _editUserApps(uDoc);
                                if (v == 'org') await _editUserOrg(uDoc);
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'org',
                                  child: Row(
                                    children: [
                                      Icon(Icons.business, size: 18),
                                      SizedBox(width: 8),
                                      Text(
                                        'Organización',
                                        style: TextStyle(fontFamily: kArial),
                                      ),
                                    ],
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'apps',
                                  child: Row(
                                    children: [
                                      Icon(Icons.apps, size: 18),
                                      SizedBox(width: 8),
                                      Text(
                                        'Asignar módulos',
                                        style: TextStyle(fontFamily: kArial),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (isMobile)
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _infoPill(
                                Icons.badge_outlined,
                                cargo.isNotEmpty ? cargo : 'Sin cargo',
                              ),
                              _infoPill(
                                Icons.location_on_outlined,
                                centro.isNotEmpty ? centro : 'Sin centro',
                              ),
                              _infoPill(
                                Icons.corporate_fare_outlined,
                                area.isNotEmpty ? area : 'Sin área',
                              ),
                            ],
                          )
                        else
                          Row(
                            children: [
                              _infoItem(
                                Icons.badge_outlined,
                                cargo.isNotEmpty ? cargo : 'Sin cargo',
                              ),
                              const SizedBox(width: 16),
                              _infoItem(
                                Icons.location_on_outlined,
                                centro.isNotEmpty ? centro : 'Sin centro',
                              ),
                              const SizedBox(width: 16),
                              _infoItem(
                                Icons.corporate_fare_outlined,
                                area.isNotEmpty ? area : 'Sin área',
                              ),
                            ],
                          ),
                        const SizedBox(height: 10),
                        if (isMobile)
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _infoPill(
                                Icons.description_outlined,
                                rolDocumental.isNotEmpty
                                    ? 'GD: ${kDocumentalRoleLabels[rolDocumental.toLowerCase()] ?? rolDocumental}'
                                    : 'GD: Sin rol documental',
                              ),
                              _infoPill(
                                Icons.receipt_long_outlined,
                                rolPlanillas.isNotEmpty
                                    ? 'PP: ${kPlanillasRoleLabels[rolPlanillas.toLowerCase()] ?? rolPlanillas}'
                                    : 'PP: Sin rol planillas',
                              ),
                            ],
                          )
                        else
                          Row(
                            children: [
                              _infoItem(
                                Icons.description_outlined,
                                rolDocumental.isNotEmpty
                                    ? 'GD: ${kDocumentalRoleLabels[rolDocumental.toLowerCase()] ?? rolDocumental}'
                                    : 'GD: Sin rol documental',
                              ),
                              const SizedBox(width: 16),
                              _infoItem(
                                Icons.receipt_long_outlined,
                                rolPlanillas.isNotEmpty
                                    ? 'PP: ${kPlanillasRoleLabels[rolPlanillas.toLowerCase()] ?? rolPlanillas}'
                                    : 'PP: Sin rol planillas',
                              ),
                            ],
                          ),
                        const SizedBox(height: 16),
                        if (apps.isNotEmpty)
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: apps
                                .map(
                                  (a) => Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: kAdminAccent.withValues(
                                        alpha: 0.1,
                                      ),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      a,
                                      style: const TextStyle(
                                        fontFamily: kArial,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: kAdminAccent,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                          )
                        else
                          const Text(
                            'Sin aplicaciones asignadas',
                            style: TextStyle(
                              fontFamily: kArial,
                              fontSize: 11,
                              fontStyle: FontStyle.italic,
                              color: kAdminMuted,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUsersHeader(List<AreaItem> activeAreas, bool isMobile) {
    const titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Gestión de Usuarios',
          style: TextStyle(
            fontFamily: kArial,
            fontWeight: FontWeight.w900,
            fontSize: 20,
          ),
        ),
        Text(
          'Administra accesos y organización de personal',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: kArial,
            fontSize: 13,
            color: kAdminMuted,
          ),
        ),
      ],
    );

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          titleBlock,
          const SizedBox(height: 12),
          _buildUsersFilterControls(activeAreas, isMobile: true),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        titleBlock,
        const Spacer(),
        _buildUsersFilterControls(activeAreas, isMobile: false),
      ],
    );
  }

  Widget _buildUsersFilterControls(
    List<AreaItem> activeAreas, {
    required bool isMobile,
  }) {
    final areaFilter = activeAreas.isEmpty
        ? null
        : SizedBox(
            width: isMobile ? double.infinity : 200,
            child: DropdownButtonFormField<String?>(
              initialValue: _userAreaFilter,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Área',
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                filled: true,
                fillColor: Colors.white,
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text(
                    'Todas las áreas',
                    style: TextStyle(fontFamily: kArial, fontSize: 12),
                  ),
                ),
                ...activeAreas.map(
                  (a) => DropdownMenuItem<String?>(
                    value: a.areaId,
                    child: Text(
                      a.nombre,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontFamily: kArial, fontSize: 12),
                    ),
                  ),
                ),
              ],
              onChanged: (v) => setState(() => _userAreaFilter = v),
            ),
          );

    final searchField = Container(
      width: isMobile ? double.infinity : 260,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kAdminBorder),
      ),
      child: TextField(
        decoration: const InputDecoration(
          hintText: 'Nombre, cédula, cargo, área...',
          prefixIcon: Icon(Icons.search, size: 20),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(vertical: 12),
        ),
        style: const TextStyle(fontFamily: kArial, fontSize: 14),
        onChanged: (v) => setState(() => _userSearch = v.trim()),
      ),
    );

    if (isMobile) {
      return Column(
        children: [
          if (areaFilter != null) ...[areaFilter, const SizedBox(height: 8)],
          searchField,
        ],
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [if (areaFilter != null) areaFilter, searchField],
    );
  }

  Widget _infoPill(IconData icon, String text) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 170),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: kAdminBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: kAdminBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: kAdminMuted),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: kArial,
                fontSize: 11,
                color: kAdminMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _empresaDropdownLabel(EmpresaItem empresa) {
    return Row(
      children: [
        _empresaLogoBox(empresa.logoUrl, size: 28),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            empresa.nombre,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: kArial,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }

  Widget _infoItem(IconData icon, String text) {
    return Expanded(
      child: Row(
        children: [
          Icon(icon, size: 14, color: kAdminMuted),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: kArial,
                fontSize: 12,
                color: kAdminMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- HELPERS: FILTRO DE PERSONAL ----------------

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _applyPersonnelFilter(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> users, {
    required String search,
    String? areaId,
  }) {
    return users.where((u) {
      final d = u.data();
      final scoped = getUserCompanyDetail(d, _empresaId);
      final uAreaId = _safe(scoped?['areaId']).isNotEmpty
          ? _safe(scoped?['areaId'])
          : _safe(d['areaId']);

      if (areaId != null && areaId.isNotEmpty && uAreaId != areaId) {
        return false;
      }

      if (search.isEmpty) return true;
      final q = search.toLowerCase();
      final name = _userName(d, u.id).toLowerCase();
      final ced = _safe(d['cedula']).toLowerCase();
      final cargo =
          (_safe(scoped?['cargo']).isNotEmpty
                  ? _safe(scoped?['cargo'])
                  : _safe(d['cargo']))
              .toLowerCase();
      final areaNombre =
          (_safe(scoped?['areaNombre']).isNotEmpty
                  ? _safe(scoped?['areaNombre'])
                  : _safe(d['areaNombre']))
              .toLowerCase();
      return name.contains(q) ||
          ced.contains(q) ||
          u.id.toLowerCase().contains(q) ||
          cargo.contains(q) ||
          areaNombre.contains(q);
    }).toList();
  }

  Widget _buildPersonnelFilterBar({
    required String searchHint,
    required String searchValue,
    required ValueChanged<String> onSearchChanged,
    required String? selectedAreaId,
    required ValueChanged<String?> onAreaChanged,
  }) {
    final areas = _areas.where((a) => a.enabled).toList();
    final isMobile = MediaQuery.of(context).size.width < 700;
    final searchField = SizedBox(
      width: isMobile ? double.infinity : 260,
      child: TextField(
        decoration: InputDecoration(
          labelText: searchHint,
          prefixIcon: const Icon(Icons.search, size: 18),
          border: const OutlineInputBorder(),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 8,
          ),
        ),
        style: const TextStyle(fontFamily: kArial, fontSize: 13),
        onChanged: onSearchChanged,
      ),
    );
    final areaField = areas.isEmpty
        ? null
        : SizedBox(
            width: isMobile ? double.infinity : 220,
            child: DropdownButtonFormField<String?>(
              initialValue: selectedAreaId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Área',
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text(
                    'Todas las áreas',
                    style: TextStyle(fontFamily: kArial, fontSize: 12),
                  ),
                ),
                ...areas.map(
                  (a) => DropdownMenuItem<String?>(
                    value: a.areaId,
                    child: Text(
                      a.nombre,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontFamily: kArial, fontSize: 12),
                    ),
                  ),
                ),
              ],
              onChanged: onAreaChanged,
            ),
          );

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: isMobile
          ? Column(
              children: [
                searchField,
                if (areaField != null) ...[
                  const SizedBox(height: 8),
                  areaField,
                ],
              ],
            )
          : Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [searchField, if (areaField != null) areaField],
            ),
    );
  }

  // ---------------- TAB: ROLES Y PERMISOS ----------------
  AccessRoleItem? _accessRoleForUser(Map<String, dynamic> data) {
    final empresaId = _empresaId ?? '';
    final detail = getUserCompanyDetail(data, empresaId);
    final roleId = _safe(detail?['roleId']).isNotEmpty
        ? _safe(detail?['roleId'])
        : _safe(data['roleId']);
    final roleKey = resolveScopedRoleKey(data, empresaId: empresaId);
    for (final role in _accessRoles) {
      if (role.roleId == roleId || role.roleKey == roleKey) return role;
    }
    return null;
  }

  String _appDisplayName(QueryDocumentSnapshot<Map<String, dynamic>> app) {
    final data = app.data();
    return _safe(data['nombre']).isNotEmpty
        ? _safe(data['nombre'])
        : _safe(data['appId']).isNotEmpty
        ? _safe(data['appId'])
        : app.id;
  }

  String _appIdOf(QueryDocumentSnapshot<Map<String, dynamic>> app) {
    final raw = _safe(app.data()['appId']).isNotEmpty
        ? _safe(app.data()['appId'])
        : app.id;
    return normalizeAppId(raw) ?? raw.toLowerCase();
  }

  IconData _accessRoleIcon(AccessRoleItem role) {
    if (role.roleKey == 'desarrollador' || role.roleKey == 'developer') {
      return Icons.code_rounded;
    }
    switch (role.moduleId.toLowerCase()) {
      case 'compras':
        return Icons.shopping_cart_checkout;
      case 'interventoria':
        return Icons.document_scanner_outlined;
      case 'facturacion':
        return Icons.receipt_long_outlined;
      case 'rutas':
        return Icons.local_shipping_outlined;
      default:
        return Icons.admin_panel_settings_outlined;
    }
  }

  String _appNameForId(String appId) {
    for (final app in _appsAdmin) {
      if (appIdsEquivalent(_appIdOf(app), appId)) {
        return _appDisplayName(app);
      }
    }
    return normalizeAppId(appId) ?? appId;
  }

  String _roleAppsSummary(AccessRoleItem role) {
    if (role.roleKey == 'desarrollador' || role.roleKey == 'developer') {
      return 'Todos los módulos';
    }
    if (role.appIds.isEmpty) return 'No agrega módulos';
    return role.appIds.map(_appNameForId).join(', ');
  }

  String _userOrgSummary(Map<String, dynamic> data, String empresaId) {
    final cargo = _userCargoText(data, empresaId);
    final area = _userAreaText(data, empresaId);
    final parts = [cargo, area].where((e) => e.trim().isNotEmpty).toList();
    return parts.isEmpty ? 'Sin cargo/área' : parts.join(' · ');
  }

  String _userCargoText(Map<String, dynamic> data, String empresaId) {
    final scoped = getUserCompanyDetail(data, empresaId);
    final cargo = _safe(scoped?['cargoNombre']).isNotEmpty
        ? _safe(scoped?['cargoNombre'])
        : _safe(scoped?['cargo']).isNotEmpty
        ? _safe(scoped?['cargo'])
        : _safe(data['cargoNombre']).isNotEmpty
        ? _safe(data['cargoNombre'])
        : _safe(data['cargo']);
    return cargo.isEmpty ? 'Sin cargo' : cargo;
  }

  String _userAreaText(Map<String, dynamic> data, String empresaId) {
    final scoped = getUserCompanyDetail(data, empresaId);
    final area = _safe(scoped?['areaNombre']).isNotEmpty
        ? _safe(scoped?['areaNombre'])
        : (_safe(scoped?['area']).isNotEmpty
              ? _safe(scoped?['area'])
              : (_safe(data['areaNombre']).isNotEmpty
                    ? _safe(data['areaNombre'])
                    : _safe(data['area'])));
    return area.isEmpty ? 'Sin área' : area;
  }

  String _visibleAppsSummary(Map<String, dynamic> data, String empresaId) {
    final apps = extractUserApps(data, empresaId: empresaId);
    if (apps.isEmpty) return 'Sin módulos';
    final names = apps.map(_appNameForId).toList()..sort();
    if (names.length <= 3) return names.join(', ');
    return '${names.take(3).join(', ')} +${names.length - 3}';
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _sortAccessRoleUsers(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> users,
    String empresaId,
  ) {
    final sorted = [...users];
    sorted.sort((a, b) {
      final ad = a.data();
      final bd = b.data();
      final areaCompare = _userOrgSummary(
        ad,
        empresaId,
      ).toLowerCase().compareTo(_userOrgSummary(bd, empresaId).toLowerCase());
      if (areaCompare != 0) return areaCompare;
      return _userName(
        ad,
        a.id,
      ).toLowerCase().compareTo(_userName(bd, b.id).toLowerCase());
    });
    return sorted;
  }

  Widget _accessRoleDropdown({
    required QueryDocumentSnapshot<Map<String, dynamic>> userDoc,
    required String empresaId,
    required AccessRoleItem? currentRole,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: currentRole?.roleId,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Perfil general',
        helperText: 'No reemplaza Apps ni roles internos.',
        isDense: true,
      ),
      hint: const Text('Sin perfil'),
      items: _accessRoles
          .map(
            (role) => DropdownMenuItem<String>(
              value: role.roleId,
              enabled: role.enabled,
              child: Text(
                role.enabled ? role.nombre : '${role.nombre} (inactivo)',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: (roleId) async {
        if (roleId == null) return;
        final selected = _accessRoles.firstWhere(
          (role) => role.roleId == roleId,
        );
        await _repo.assignAccessRole(
          userId: userDoc.id,
          empresaId: empresaId,
          role: selected,
        );
        _snack('${selected.nombre} asignado sin quitar módulos existentes');
        await _reloadAccessMatrix();
      },
    );
  }

  List<_AccessMatrixModule> _accessMatrixModules() => [
    const _AccessMatrixModule(
      key: 'admin',
      label: 'Admin',
      appId: 'admindashboard',
      icon: Icons.admin_panel_settings_rounded,
      color: Color(0xFF475569),
    ),
    const _AccessMatrixModule(
      key: 'tareas',
      label: 'Tareas',
      appId: 'tareasdashboard',
      icon: Icons.task_alt_rounded,
      color: Color(0xFF2563EB),
    ),
    const _AccessMatrixModule(
      key: 'talento',
      label: 'Talento',
      appId: 'talentohumanodashboard',
      icon: Icons.groups_rounded,
      color: Color(0xFF4F46E5),
    ),
    const _AccessMatrixModule(
      key: 'gerencia',
      label: 'Gerencia',
      appId: 'gerenciadashboard',
      icon: Icons.query_stats_rounded,
      color: Color(0xFF7C3AED),
    ),
    // Etiqueta "Biblioteca" (no "Correspondencia") a propósito: el dropdown de
    // esta fila escribe `rolDocumental` (redactor/revisor/aprobador/firmante),
    // que gobierna la Biblioteca documental, no el rol Clasificador y
    // asignador de Correspondencia — ese vive aparte, ver `_correoRoleCallout`.
    const _AccessMatrixModule(
      key: 'gestion_documental',
      label: 'Gestión de Correspondencia',
      appId: 'gestiondocumentaldashboard',
      icon: Icons.auto_stories_rounded,
      color: Color(0xFF0D9488),
      roles: kDocumentalRoleLabels,
    ),
    const _AccessMatrixModule(
      key: 'planillas_pago',
      label: 'Planillas',
      appId: kPlanillasPagoAppId,
      icon: Icons.request_quote_rounded,
      color: Color(0xFFB45309),
      hasPlanillasRole: true,
    ),
    const _AccessMatrixModule(
      key: 'nutricion',
      label: 'Nutrición',
      appId: 'nutriciondashboard',
      icon: Icons.restaurant_menu_rounded,
      color: Color(0xFFEA580C),
    ),
    const _AccessMatrixModule(
      key: 'compras',
      label: 'Compras',
      appId: 'comprasdashboard',
      icon: Icons.shopping_bag_rounded,
      color: Color(0xFF2563EB),
      roles: {
        kRolAdmin: 'Admin Documental',
        kRolCalidad: 'Director de Calidad',
        kRolCompras: 'Compras',
        kRolBodega: 'Bodega',
        kRolConsultas: 'Consultas',
      },
    ),
    _AccessMatrixModule(
      key: 'correo',
      label: 'Correo y Correspondencia',
      appId: 'correodashboard',
      icon: Icons.mark_email_unread_rounded,
      color: const Color(0xFF0F766E),
      roles: {
        for (final role in GdRolCorrespondencia.values)
          role.valor: role.etiqueta,
      },
    ),
    const _AccessMatrixModule(
      key: 'tokens_dian',
      label: 'Tokens DIAN',
      appId: 'tokensdiandashboard',
      icon: Icons.vpn_key_rounded,
      color: Color(0xFF0E7490),
    ),
    _AccessMatrixModule(
      key: 'interventoria',
      label: 'Interventoría',
      appId: kInterventoriaAppId,
      icon: Icons.document_scanner_rounded,
      color: const Color(0xFF0F766E),
      roles: {
        for (final role in kInterventoriaRoles)
          role: kInterventoriaRoleLabels[role] ?? role,
      },
    ),
    const _AccessMatrixModule(
      key: 'facturacion',
      label: 'Facturación',
      appId: kFacAppId,
      icon: Icons.receipt_long_rounded,
      color: Color(0xFF0369A1),
      roles: kFacRoleLabels,
    ),
    const _AccessMatrixModule(
      key: 'rutas',
      label: 'Rutas',
      appId: kRutasAppId,
      icon: Icons.local_shipping_rounded,
      color: Color(0xFF15803D),
      roles: kRutasRolLabels,
    ),
  ];

  List<_AccessMatrixModule> _filteredAccessMatrixModules() {
    final modules = _accessMatrixModules();
    final filter = (_accessRoleAppFilter ?? '').trim();
    if (filter.isEmpty) return const <_AccessMatrixModule>[];
    final filtered = modules
        .where((module) => appIdsEquivalent(module.appId, filter))
        .toList();
    return filtered;
  }

  String _matrixModulesLabel(List<_AccessMatrixModule> modules) {
    final allCount = _accessMatrixModules().length;
    if (modules.length == allCount) return 'todos los módulos';
    if (modules.isEmpty) return 'ningún módulo';
    return modules.map((m) => m.label).join(', ');
  }

  String _matrixModulePermissionHint(_AccessMatrixModule module) {
    switch (module.key) {
      case 'tareas':
        return 'Acceso, áreas y vista del equipo';
      case 'compras':
      case 'interventoria':
      case 'rutas':
      case 'facturacion':
      case 'correo':
      case 'gestion_documental':
        return 'Acceso y rol operativo';
      case 'planillas_pago':
        return 'Acceso y etapa de firma';
      case 'tokens_dian':
        return 'Personal autorizado';
      case 'admin':
        return 'Acceso al panel administrativo';
      default:
        return 'Activa u oculta el módulo';
    }
  }

  Map<String, String> _matrixModuleRoleOptions(_AccessMatrixModule module) {
    if (module.hasPlanillasRole) return kPlanillasRoleLabels;
    return module.roles;
  }

  String _matrixModuleRoleDescription(
    _AccessMatrixModule module,
    String roleKey,
  ) {
    switch (module.key) {
      case 'correo':
        return GdRolCorrespondencia.desdeTexto(roleKey)?.descripcion ??
            'Define las acciones disponibles dentro de Correspondencia.';
      case 'gestion_documental':
        switch (roleKey) {
          case 'redactor':
            return 'Crea documentos, prepara contenido y mantiene borradores.';
          case 'revisor':
            return 'Revisa documentos y solicita los ajustes necesarios.';
          case 'aprobador':
            return 'Aprueba o rechaza los documentos que llegan a su etapa.';
          case 'firmante':
            return 'Firma los documentos que ya completaron la aprobación.';
          case 'admin_doc':
            return 'Administra todo el flujo documental, sus etapas y permisos.';
        }
      case 'planillas_pago':
        switch (roleKey) {
          case 'tesoreria':
            return 'Realiza la primera revisión y firma de la planilla.';
          case 'auditoria':
            return 'Revisa y firma después de la aprobación de Tesorería.';
          case 'gerencia':
            return 'Realiza la aprobación y firma final del flujo.';
          case 'admin_doc':
            return 'Controla la configuración y todas las etapas de Planillas.';
        }
      case 'compras':
        switch (roleKey) {
          case kRolAdmin:
            return 'Control completo de proveedores, documentos, recepciones y configuración.';
          case kRolCalidad:
            return 'Revisa documentos y puede aprobar, rechazar o aceptar con requerimientos.';
          case kRolCompras:
            return 'Gestiona proveedores, productos y el flujo operativo de compras.';
          case kRolBodega:
            return 'Gestiona recepciones de mercancía y sus evidencias.';
          case kRolConsultas:
            return 'Consulta información, reportes y exportaciones sin modificar el flujo.';
        }
      case 'interventoria':
        switch (roleKey) {
          case kRolInterventoriaAdmin:
            return 'Control completo del módulo, actas, configuración y seguimiento.';
          case kRolInterventoriaRegistrador:
            return 'Carga actas, archivos PDF y registra los puntajes iniciales.';
          case kRolInterventoriaRevisor:
            return 'Completa y revisa las actas dentro de la segunda fase.';
          case kRolInterventoriaGerente:
            return 'Revisa la gestión y participa en la validación de las actas.';
          case kRolInterventoriaDirectivo:
            return 'Realiza seguimiento ejecutivo y revisión de la segunda fase.';
        }
      case 'facturacion':
        switch (roleKey) {
          case kRolFacturacion:
            return 'Gestiona el flujo de facturación, estados, soportes y seguimiento.';
          case kRolEstablecimiento:
            return 'Trabaja únicamente la facturación del establecimiento asignado.';
          case kRolFacVisor:
            return 'Consulta la información de facturación sin modificarla.';
        }
      case 'rutas':
        switch (roleKey) {
          case kRutasRolConductor:
            return 'Toma y carga la evidencia de su propia ruta del día.';
          case kRutasRolCalidad:
            return 'Revisa, aprueba o rechaza evidencias y genera informes.';
          case kRutasRolAdmin:
            return 'Administra rutas, direcciones, personal, ventanas y ciclos.';
          case kRutasRolAdminCalidad:
            return 'Combina la administración de rutas con la revisión de Calidad.';
          case kRutasRolDesarrollador:
            return 'Perfil de prueba con acceso a todos los flujos de Rutas.';
        }
    }
    return 'Define las acciones que la persona puede realizar en este módulo.';
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _matrixCompanyUsers(
    String empresaId,
  ) {
    if (empresaId.trim().isEmpty) {
      return const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    }
    return _users
        .where(
          (user) => matchesEmpresaScope(
            user.data(),
            empresaId,
            allowLegacyWithoutEmpresa: false,
          ),
        )
        .toList();
  }

  Widget _matrixModuleSelector({
    required List<_AccessMatrixModule> allModules,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> users,
    required String empresaId,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: kAdminBorder),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Selecciona el módulo que quieres administrar',
              style: TextStyle(
                fontFamily: kArial,
                fontWeight: FontWeight.w900,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Cada botón abre sus accesos y permisos propios, sin cargar una tabla general.',
              style: TextStyle(color: kAdminMuted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: allModules.map((module) {
                final selected = appIdsEquivalent(
                  module.appId,
                  _accessRoleAppFilter,
                );
                final accessCount = users
                    .where(
                      (user) =>
                          _matrixUserHasApp(user, module.appId, empresaId),
                    )
                    .length;
                return SizedBox(
                  width: 230,
                  child: Material(
                    color: selected
                        ? module.color.withValues(alpha: 0.10)
                        : const Color(0xFFF8FAFC),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(
                        color: selected ? module.color : kAdminBorder,
                        width: selected ? 1.5 : 1,
                      ),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => setState(() {
                        _accessRoleAppFilter = module.appId;
                        _accessRoleStatusFilter = AdminAccessFilter.all;
                        _accessRoleUserSearch = '';
                        _accessRoleAreaFilter = null;
                        _selectedAccessUserIds = <String>{};
                        _accessRolePage = 0;
                      }),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: module.color.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(11),
                              ),
                              child: Icon(
                                module.icon,
                                color: module.color,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    module.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                  Text(
                                    '$accessCount con acceso',
                                    style: TextStyle(
                                      color: module.color,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 11,
                                    ),
                                  ),
                                  Text(
                                    _matrixModulePermissionHint(module),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: kAdminMuted,
                                      fontSize: 10.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              selected
                                  ? Icons.check_circle_rounded
                                  : Icons.chevron_right_rounded,
                              size: 19,
                              color: selected ? module.color : kAdminMuted,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  bool _matrixModuleHasRoles(_AccessMatrixModule module) =>
      module.hasPlanillasRole || module.roles.isNotEmpty;

  List<QueryDocumentSnapshot<Map<String, dynamic>>>
  _filterAccessRoleUsersByStatus({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> users,
    required List<_AccessMatrixModule> modules,
    required String empresaId,
  }) {
    if (_accessRoleStatusFilter == AdminAccessFilter.all ||
        modules.length != 1) {
      return users;
    }
    final module = modules.single;
    final supportsRoles = _matrixModuleHasRoles(module);
    return users.where((userDoc) {
      final hasAccess = _matrixUserHasApp(userDoc, module.appId, empresaId);
      final role = module.hasPlanillasRole
          ? _matrixPlanillasRoleForUser(userDoc, empresaId)
          : _matrixRoleForUser(userDoc, module, empresaId);
      return matchesAdminAccessFilter(
        filter: _accessRoleStatusFilter,
        hasAccess: hasAccess,
        hasRole: supportsRoles && (role ?? '').trim().isNotEmpty,
      );
    }).toList();
  }

  Widget _matrixAccessStatusFilter({
    required List<_AccessMatrixModule> modules,
    required bool isMobile,
  }) {
    final supportsRoles =
        modules.length == 1 && _matrixModuleHasRoles(modules.single);
    final available = <AdminAccessFilter>[
      AdminAccessFilter.all,
      AdminAccessFilter.enabled,
      AdminAccessFilter.disabled,
      if (supportsRoles) AdminAccessFilter.enabledWithRole,
      if (supportsRoles) AdminAccessFilter.enabledWithoutRole,
    ];
    final selected = available.contains(_accessRoleStatusFilter)
        ? _accessRoleStatusFilter
        : AdminAccessFilter.all;
    String label(AdminAccessFilter filter) {
      switch (filter) {
        case AdminAccessFilter.all:
          return 'Todos los usuarios';
        case AdminAccessFilter.enabled:
          return 'Con acceso';
        case AdminAccessFilter.disabled:
          return 'Sin acceso';
        case AdminAccessFilter.enabledWithRole:
          return 'Con acceso y rol';
        case AdminAccessFilter.enabledWithoutRole:
          return 'Con acceso, sin rol';
      }
    }

    return SizedBox(
      width: isMobile ? double.infinity : 220,
      child: DropdownButtonFormField<AdminAccessFilter>(
        initialValue: selected,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Estado de acceso',
          border: OutlineInputBorder(),
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
        items: available
            .map(
              (filter) => DropdownMenuItem<AdminAccessFilter>(
                value: filter,
                child: Text(
                  label(filter),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: kArial, fontSize: 12),
                ),
              ),
            )
            .toList(),
        onChanged: (value) => setState(() {
          _accessRoleStatusFilter = value ?? AdminAccessFilter.all;
          _selectedAccessUserIds = <String>{};
          _accessRolePage = 0;
        }),
      ),
    );
  }

  bool _matrixUserHasApp(
    QueryDocumentSnapshot<Map<String, dynamic>> userDoc,
    String appId,
    String empresaId,
  ) {
    if (appIdsEquivalent(appId, kPlanillasPagoAppId) &&
        userHasApp(userDoc.data(), kPlanillasPagoAppId, empresaId: empresaId)) {
      return true;
    }
    final apps =
        _userApps[userDoc.id] ??
        extractUserApps(userDoc.data(), empresaId: empresaId).toSet();
    return apps.any((app) => appIdsEquivalent(app, appId));
  }

  String? _matrixRoleForUser(
    QueryDocumentSnapshot<Map<String, dynamic>> userDoc,
    _AccessMatrixModule module,
    String empresaId,
  ) {
    final data = userDoc.data();
    final cedula = _safe(data['cedula']).isNotEmpty
        ? _safe(data['cedula'])
        : userDoc.id;
    switch (module.key) {
      case 'compras':
        return _comprasRoleByUser[userDoc.id] ?? _comprasRoleByUser[cedula];
      case 'interventoria':
        return _interventoriaRoleByUser[userDoc.id] ??
            _interventoriaRoleByUser[cedula];
      case 'rutas':
        return _rutasRoleByUser[userDoc.id] ?? _rutasRoleByUser[cedula];
      case 'correo':
        final explicit =
            _correoRoleByUser[userDoc.id] ?? _correoRoleByUser[cedula];
        if ((explicit ?? '').isNotEmpty) return explicit;
        if (data['desarrollador'] == true || data['developer'] == true) {
          return GdRolCorrespondencia.administrador.valor;
        }
        final detail = getUserCompanyDetail(data, empresaId);
        final scoped = GdRolCorrespondencia.desdeTexto(
          _safe(detail?['rolCorreo']).isNotEmpty
              ? _safe(detail?['rolCorreo'])
              : _safe(data['rolCorreo']),
        );
        if (scoped != null) return scoped.valor;
        final global = GdRolCorrespondencia.desdeTexto(
          _safe(data['role']).isNotEmpty
              ? _safe(data['role'])
              : (_safe(data['rol']).isNotEmpty
                    ? _safe(data['rol'])
                    : _safe(data['tipoUsuario'])),
        );
        if (global == GdRolCorrespondencia.administrador) {
          return GdRolCorrespondencia.administrador.valor;
        }
        // El backend aplica Operador por defecto a quien sí puede abrir el
        // módulo. Mostrarlo evita que la matriz diga "sin rol" cuando en la
        // práctica la persona sí puede gestionar lo que le asignen.
        return _matrixUserHasApp(userDoc, module.appId, empresaId)
            ? GdRolCorrespondencia.operador.valor
            : null;
      case 'facturacion':
        final detail = getUserCompanyDetail(data, empresaId);
        final rawRole = detail != null
            ? _safe(detail['rolFac'])
            : _safe(data['rolFac']);
        final role = normalizeFacRole(rawRole);
        return role.isEmpty ? null : role;
      case 'gestion_documental':
        final detail = getUserCompanyDetail(data, empresaId);
        return _safe(detail?['rolDocumental']).isNotEmpty
            ? _safe(detail?['rolDocumental'])
            : (_safe(data['rolDocumental']).isEmpty
                  ? null
                  : _safe(data['rolDocumental']));
    }
    return null;
  }

  String? _matrixPlanillasRoleForUser(
    QueryDocumentSnapshot<Map<String, dynamic>> userDoc,
    String empresaId,
  ) {
    final data = userDoc.data();
    final detail = getUserCompanyDetail(data, empresaId);
    return _safe(detail?['rolPlanillas']).isNotEmpty
        ? _safe(detail?['rolPlanillas'])
        : (_safe(data['rolPlanillas']).isEmpty
              ? null
              : _safe(data['rolPlanillas']));
  }

  Future<void> _setMatrixModuleVisible({
    required QueryDocumentSnapshot<Map<String, dynamic>> userDoc,
    required _AccessMatrixModule module,
    required bool visible,
  }) async {
    final empresaId = _empresaId ?? '';
    if (empresaId.isEmpty) return;
    final apps = {...(_userApps[userDoc.id] ?? <String>{})};
    apps.removeWhere((app) => appIdsEquivalent(app, module.appId));
    if (visible) apps.add(module.appId);
    await _repo.updateUserApps(userDoc.id, apps, empresaId: empresaId);
    if (!visible && appIdsEquivalent(module.appId, kPlanillasPagoAppId)) {
      await _setScopedUserRoleField(
        userDoc: userDoc,
        empresaId: empresaId,
        field: 'rolPlanillas',
        value: null,
      );
    }
    _snack(
      '${module.label}: ${visible ? 'módulo activado' : 'módulo ocultado'}',
    );
    await _reloadAccessMatrix();
  }

  Future<void> _setMatrixUsersModules({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> users,
    required bool visible,
    required List<_AccessMatrixModule> modules,
  }) async {
    final empresaId = _empresaId ?? '';
    if (empresaId.isEmpty || users.isEmpty || modules.isEmpty) return;
    final scope = _matrixModulesLabel(modules);
    final ok = await _confirm(
      title: visible ? 'Dar acceso al módulo' : 'Quitar acceso al módulo',
      message:
          '${visible ? 'Se activarán' : 'Se ocultarán'} $scope '
          'para ${users.length} usuario(s).\n\n'
          'Esto cambia el acceso al módulo. Los roles operativos se conservan, '
          'excepto la etapa de firma de Planillas cuando se retira su acceso.',
      confirmText: visible ? 'Dar acceso' : 'Quitar acceso',
    );
    if (!ok) return;

    final moduleIds = modules.map((m) => m.appId).toList();
    // Procesa grupos pequeños en paralelo para que una selección grande no
    // tarde un ciclo de red completo por cada persona ni sature Firestore.
    const chunkSize = 12;
    for (var start = 0; start < users.length; start += chunkSize) {
      final candidateEnd = start + chunkSize;
      final end = candidateEnd < users.length ? candidateEnd : users.length;
      await Future.wait(
        users.sublist(start, end).map((userDoc) async {
          final apps =
              _userApps[userDoc.id] ??
              extractUserApps(userDoc.data(), empresaId: empresaId).toSet();
          final nextApps = {...apps}
            ..removeWhere(
              (app) => moduleIds.any((id) => appIdsEquivalent(app, id)),
            );
          if (visible) nextApps.addAll(moduleIds);
          await _repo.updateUserApps(
            userDoc.id,
            nextApps,
            empresaId: empresaId,
          );
          if (!visible &&
              moduleIds.any(
                (id) => appIdsEquivalent(id, kPlanillasPagoAppId),
              )) {
            await _setScopedUserRoleField(
              userDoc: userDoc,
              empresaId: empresaId,
              field: 'rolPlanillas',
              value: null,
            );
          }
        }),
      );
    }
    _snack(
      visible
          ? '$scope activados para ${users.length} usuario(s)'
          : '$scope ocultados para ${users.length} usuario(s)',
    );
    if (mounted) setState(() => _selectedAccessUserIds = <String>{});
    await _reloadAccessMatrix();
  }

  String? _inferFacturacionEstablecimientoId(
    Map<String, dynamic> data,
    String empresaId,
  ) {
    final detail = getUserCompanyDetail(data, empresaId);
    final raw =
        (detail?['establecimientoFacId'] ??
                detail?['centroId'] ??
                detail?['centroCostos'] ??
                data['establecimientoFacId'] ??
                data['centroId'] ??
                data['centroCostos'] ??
                '')
            .toString()
            .trim();
    if (raw.isEmpty) return null;
    for (final centro in _centros) {
      if (centro.centroId.toLowerCase() == raw.toLowerCase() ||
          centro.nombre.toLowerCase() == raw.toLowerCase() ||
          centro.codigo.toLowerCase() == raw.toLowerCase()) {
        return centro.centroId;
      }
    }
    return raw;
  }

  Future<void> _setScopedUserRoleField({
    required QueryDocumentSnapshot<Map<String, dynamic>> userDoc,
    required String empresaId,
    required String field,
    required String? value,
    Map<String, dynamic> extraScoped = const {},
    Iterable<String> deleteScopedFields = const [],
  }) async {
    final data = userDoc.data();
    final update = <String, dynamic>{'updatedAt': FieldValue.serverTimestamp()};
    update['empresasDetalle.$empresaId.$field'] = value == null || value.isEmpty
        ? FieldValue.delete()
        : value;
    if (_safe(data['empresaId']) == empresaId) {
      update[field] = value == null || value.isEmpty
          ? FieldValue.delete()
          : value;
    }
    for (final entry in extraScoped.entries) {
      update['empresasDetalle.$empresaId.${entry.key}'] = entry.value;
      if (_safe(data['empresaId']) == empresaId) {
        update[entry.key] = entry.value;
      }
    }
    for (final key in deleteScopedFields) {
      update['empresasDetalle.$empresaId.$key'] = FieldValue.delete();
      if (_safe(data['empresaId']) == empresaId) {
        update[key] = FieldValue.delete();
      }
    }
    // `update` interpreta las claves con puntos como rutas anidadas. Con `set`
    // esas mismas claves podían terminar como campos literales y el módulo no
    // encontraba el rol dentro de empresasDetalle.
    await userDoc.reference.update(update);
  }

  Future<void> _setMatrixTaskPermission({
    required QueryDocumentSnapshot<Map<String, dynamic>> userDoc,
    required String field,
    required bool value,
    required String label,
  }) async {
    final empresaId = (_empresaId ?? '').trim();
    if (empresaId.isEmpty) return;
    try {
      final data = userDoc.data();
      final update = <String, dynamic>{
        'empresasDetalle.$empresaId.$field': value,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (_safe(data['empresaId']) == empresaId) update[field] = value;
      await userDoc.reference.update(update);
      _snack('Tareas: $label ${value ? 'habilitado' : 'deshabilitado'}');
      await _reloadAccessMatrix();
    } catch (error) {
      _snack('No se pudo actualizar el permiso de Tareas: $error');
    }
  }

  Future<void> _setMatrixInternalRole({
    required QueryDocumentSnapshot<Map<String, dynamic>> userDoc,
    required _AccessMatrixModule module,
    required String? role,
    bool planillas = false,
  }) async {
    try {
      await _setMatrixInternalRoleUnchecked(
        userDoc: userDoc,
        module: module,
        role: role,
        planillas: planillas,
      );
    } catch (error) {
      _snack('No se pudo cambiar el rol de ${module.label}: $error');
    }
  }

  Future<void> _setMatrixInternalRoleUnchecked({
    required QueryDocumentSnapshot<Map<String, dynamic>> userDoc,
    required _AccessMatrixModule module,
    required String? role,
    bool planillas = false,
  }) async {
    final empresaId = _empresaId ?? '';
    if (empresaId.isEmpty) return;
    final cleanRole = (role ?? '').trim();
    final hasRole = cleanRole.isNotEmpty;
    if (hasRole) {
      await _repo.grantUserApps(
        userId: userDoc.id,
        empresaId: empresaId,
        appIds: [module.appId],
      );
    }

    if (planillas) {
      await _setScopedUserRoleField(
        userDoc: userDoc,
        empresaId: empresaId,
        field: 'rolPlanillas',
        value: hasRole ? cleanRole : null,
      );
    } else {
      final data = userDoc.data();
      final cedula = _safe(data['cedula']).isNotEmpty
          ? _safe(data['cedula'])
          : userDoc.id;
      final nombre = _userName(data, userDoc.id);
      final payload = <String, dynamic>{
        'empresaId': empresaId,
        'userId': userDoc.id,
        'cedula': cedula,
        'nombre': nombre,
        'rol': cleanRole,
        'createdAt': Timestamp.now(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      switch (module.key) {
        case 'compras':
          final ref = FirebaseFirestore.instance
              .collection('TBL_COMPRAS_ROLES')
              .doc('${empresaId}_${userDoc.id}');
          hasRole
              ? await ref.set(payload, SetOptions(merge: true))
              : await ref.delete();
          break;
        case 'interventoria':
          final ref = FirebaseFirestore.instance
              .collection('TBL_INTERVENTORIA_ROLES')
              .doc('${empresaId}_${userDoc.id}');
          hasRole
              ? await ref.set(payload, SetOptions(merge: true))
              : await ref.delete();
          break;
        case 'rutas':
          final ref = FirebaseFirestore.instance
              .collection('TBL_RUTAS_ROLES')
              .doc('${empresaId}_${userDoc.id}');
          hasRole
              ? await ref.set(payload, SetOptions(merge: true))
              : await ref.delete();
          break;
        case 'correo':
          final ref = FirebaseFirestore.instance
              .collection('TBL_CORREO_ROLES')
              .doc('${empresaId}_${userDoc.id}');
          final correoPayload = <String, dynamic>{
            'empresaId': empresaId,
            'usuarioId': userDoc.id,
            'rol': cleanRole,
            'actualizadoPor': widget.userId,
            'actualizadoAt': FieldValue.serverTimestamp(),
          };
          hasRole
              ? await ref.set(correoPayload, SetOptions(merge: true))
              : await ref.delete();
          break;
        case 'facturacion':
          final extra = <String, dynamic>{};
          final deleteFields = <String>[];
          if (hasRole && cleanRole == kRolEstablecimiento) {
            final estId = _inferFacturacionEstablecimientoId(data, empresaId);
            if (estId != null && estId.isNotEmpty) {
              extra['establecimientoFacId'] = estId;
            }
          } else {
            deleteFields.add('establecimientoFacId');
          }
          await _setScopedUserRoleField(
            userDoc: userDoc,
            empresaId: empresaId,
            field: 'rolFac',
            value: hasRole ? cleanRole : null,
            extraScoped: extra,
            deleteScopedFields: deleteFields,
          );
          break;
        case 'gestion_documental':
          await _setScopedUserRoleField(
            userDoc: userDoc,
            empresaId: empresaId,
            field: 'rolDocumental',
            value: hasRole ? cleanRole : null,
          );
          break;
      }
    }

    _snack(
      hasRole
          ? '${module.label}: rol asignado'
          : '${module.label}: rol interno retirado',
    );
    await _reloadAccessMatrix();
  }

  Future<void> _setMatrixFacturacionEstablecimiento({
    required QueryDocumentSnapshot<Map<String, dynamic>> userDoc,
    required String? establecimientoId,
  }) async {
    final empresaId = _empresaId ?? '';
    if (empresaId.isEmpty) return;
    try {
      await _setScopedUserRoleField(
        userDoc: userDoc,
        empresaId: empresaId,
        field: 'establecimientoFacId',
        value: establecimientoId,
      );
      _snack(
        (establecimientoId ?? '').isEmpty
            ? 'Establecimiento de Facturación retirado'
            : 'Establecimiento de Facturación actualizado',
      );
      await _reloadAccessMatrix();
    } catch (error) {
      _snack('No se pudo cambiar el establecimiento: $error');
    }
  }

  List<DropdownMenuItem<String>> _roleDropdownItems(
    Map<String, String> labels,
    String? current,
  ) {
    final merged = <String, String>{...labels};
    if (current != null && current.isNotEmpty && !merged.containsKey(current)) {
      merged[current] = current;
    }
    return [
      const DropdownMenuItem<String>(value: '', child: Text('Sin rol')),
      ...merged.entries.map(
        (entry) => DropdownMenuItem<String>(
          value: entry.key,
          child: Text(entry.value, overflow: TextOverflow.ellipsis),
        ),
      ),
    ];
  }

  Widget _matrixCompactButton({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
    bool danger = false,
  }) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 15),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: danger ? kAdminError : kAdminPrimary,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        textStyle: const TextStyle(
          fontFamily: kArial,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _matrixTaskPermissionToggle({
    required String label,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 11, color: kAdminMuted),
            ),
          ),
          Transform.scale(
            scale: 0.8,
            child: Switch.adaptive(value: value, onChanged: onChanged),
          ),
        ],
      ),
    );
  }

  Widget _matrixFilteredBulkActions({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> users,
    required List<_AccessMatrixModule> modules,
  }) {
    final scope = _matrixModulesLabel(modules);
    final selectedUsers = users
        .where((user) => _selectedAccessUserIds.contains(user.id))
        .toList();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: kAdminBorder),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 10,
          runSpacing: 8,
          children: [
            Text(
              '${users.length} usuario(s) · ${selectedUsers.length} seleccionado(s) · $scope',
              style: const TextStyle(
                fontFamily: kArial,
                fontWeight: FontWeight.w900,
              ),
            ),
            _matrixCompactButton(
              label: 'Seleccionar filtrados',
              icon: Icons.select_all_rounded,
              onPressed: users.isEmpty || modules.isEmpty
                  ? null
                  : () => setState(() {
                      _selectedAccessUserIds = users
                          .map((user) => user.id)
                          .toSet();
                    }),
            ),
            _matrixCompactButton(
              label: 'Limpiar selección',
              icon: Icons.deselect_rounded,
              onPressed: selectedUsers.isEmpty
                  ? null
                  : () => setState(() => _selectedAccessUserIds = <String>{}),
            ),
            _matrixCompactButton(
              label: 'Activar seleccionados',
              icon: Icons.visibility_rounded,
              onPressed: selectedUsers.isEmpty || modules.isEmpty
                  ? null
                  : () => _setMatrixUsersModules(
                      users: selectedUsers,
                      visible: true,
                      modules: modules,
                    ),
            ),
            _matrixCompactButton(
              label: 'Desactivar seleccionados',
              icon: Icons.visibility_off_rounded,
              danger: true,
              onPressed: selectedUsers.isEmpty || modules.isEmpty
                  ? null
                  : () => _setMatrixUsersModules(
                      users: selectedUsers,
                      visible: false,
                      modules: modules,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _accessMatrixCell({
    required QueryDocumentSnapshot<Map<String, dynamic>> userDoc,
    required _AccessMatrixModule module,
    required String empresaId,
    required bool isMobile,
  }) {
    final visible = _matrixUserHasApp(userDoc, module.appId, empresaId);
    final currentRole = _matrixRoleForUser(userDoc, module, empresaId);
    final userData = userDoc.data();
    final canCreateAcrossAreas = module.key == 'tareas'
        ? canCreateTasksAcrossAreas(
            userData,
            cargoNombre: _userCargoText(userData, empresaId),
            empresaId: empresaId,
          )
        : false;
    final canViewTeam = module.key == 'tareas'
        ? canViewTaskTeam(userData, empresaId: empresaId)
        : false;
    final currentPlanillas = module.hasPlanillasRole
        ? _matrixPlanillasRoleForUser(userDoc, empresaId)
        : null;
    final currentFacturacionEstId =
        module.key == 'facturacion' && currentRole == kRolEstablecimiento
        ? _inferFacturacionEstablecimientoId(userDoc.data(), empresaId)
        : null;
    final facturacionCentros = _centros
        .where(
          (centro) =>
              (centro.enabled && centro.enabledFacturacion) ||
              centro.centroId == currentFacturacionEstId,
        )
        .toList();
    final hasKnownFacturacionCentro = facturacionCentros.any(
      (centro) => centro.centroId == currentFacturacionEstId,
    );

    return SizedBox(
      width: isMobile ? double.infinity : 190,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: visible ? module.color.withValues(alpha: 0.05) : Colors.white,
          border: Border.all(color: kAdminBorder),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(module.icon, size: 18, color: module.color),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      module.label,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  Switch.adaptive(
                    value: visible,
                    onChanged: (value) => _setMatrixModuleVisible(
                      userDoc: userDoc,
                      module: module,
                      visible: value,
                    ),
                  ),
                ],
              ),
              if (module.roles.isNotEmpty) ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: currentRole ?? '',
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Rol interno',
                    isDense: true,
                  ),
                  items: _roleDropdownItems(module.roles, currentRole),
                  onChanged: (value) => _setMatrixInternalRole(
                    userDoc: userDoc,
                    module: module,
                    role: value,
                  ),
                ),
              ] else if (module.key == 'tareas') ...[
                _matrixTaskPermissionToggle(
                  label: 'Crear en todas las áreas',
                  value: canCreateAcrossAreas,
                  onChanged: visible
                      ? (value) => _setMatrixTaskPermission(
                          userDoc: userDoc,
                          field: 'crearTareasTodasAreas',
                          value: value,
                          label: 'creación en todas las áreas',
                        )
                      : null,
                ),
                _matrixTaskPermissionToggle(
                  label: 'Ver tareas del equipo',
                  value: canViewTeam,
                  onChanged: visible
                      ? (value) => _setMatrixTaskPermission(
                          userDoc: userDoc,
                          field: 'puedeVerEquipo',
                          value: value,
                          label: 'vista del equipo',
                        )
                      : null,
                ),
              ] else if (!module.hasPlanillasRole)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    'Acceso básico al módulo',
                    style: TextStyle(color: kAdminMuted, fontSize: 11),
                  ),
                ),
              if (module.key == 'facturacion' &&
                  currentRole == kRolEstablecimiento) ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: currentFacturacionEstId ?? '',
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Establecimiento',
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      value: '',
                      child: Text('Sin asignar'),
                    ),
                    if ((currentFacturacionEstId ?? '').isNotEmpty &&
                        !hasKnownFacturacionCentro)
                      DropdownMenuItem<String>(
                        value: currentFacturacionEstId,
                        child: Text(
                          currentFacturacionEstId!,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ...facturacionCentros.map(
                      (centro) => DropdownMenuItem<String>(
                        value: centro.centroId,
                        child: Text(
                          centro.nombre,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: (value) => _setMatrixFacturacionEstablecimiento(
                    userDoc: userDoc,
                    establecimientoId: (value ?? '').isEmpty ? null : value,
                  ),
                ),
              ],
              if (module.hasPlanillasRole) ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: currentPlanillas ?? '',
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Rol planillas',
                    isDense: true,
                  ),
                  items: _roleDropdownItems(
                    kPlanillasRoleLabels,
                    currentPlanillas,
                  ),
                  onChanged: (value) => _setMatrixInternalRole(
                    userDoc: userDoc,
                    module: module,
                    role: value,
                    planillas: true,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _accessMatrixSection({
    required String empresaId,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> users,
    required List<_AccessMatrixModule> modules,
  }) {
    if (modules.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Row(
            children: [
              Icon(Icons.touch_app_outlined, color: kAdminAccent),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Selecciona un módulo para consultar y editar sus accesos.',
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (users.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: Text('No se encontraron usuarios')),
      );
    }

    Widget userCard(QueryDocumentSnapshot<Map<String, dynamic>> userDoc) {
      final data = userDoc.data();
      final cedula = _safe(data['cedula']).isNotEmpty
          ? _safe(data['cedula'])
          : userDoc.id;
      final selected = _selectedAccessUserIds.contains(userDoc.id);
      final module = modules.single;

      Widget identity() => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: selected,
            onChanged: (value) => setState(() {
              final next = {..._selectedAccessUserIds};
              value == true ? next.add(userDoc.id) : next.remove(userDoc.id);
              _selectedAccessUserIds = next;
            }),
          ),
          UserAvatar(
            userId: userDoc.id,
            nameHint: _userName(data, userDoc.id),
            radius: 19,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _userName(data, userDoc.id),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'C.C. $cedula',
                  style: const TextStyle(color: kAdminMuted, fontSize: 11),
                ),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _matrixInfoPill(
                      Icons.badge_outlined,
                      _userCargoText(data, empresaId),
                    ),
                    _matrixInfoPill(
                      Icons.apartment_rounded,
                      _userAreaText(data, empresaId),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      );

      Widget moduleControls() => _accessMatrixCell(
        userDoc: userDoc,
        module: module,
        empresaId: empresaId,
        isMobile: true,
      );

      return Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: selected ? kAdminAccent : kAdminBorder,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: LayoutBuilder(
            builder: (context, constraints) => constraints.maxWidth < 780
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      identity(),
                      const SizedBox(height: 12),
                      moduleControls(),
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(flex: 5, child: identity()),
                      const SizedBox(width: 20),
                      Expanded(flex: 4, child: moduleControls()),
                    ],
                  ),
          ),
        ),
      );
    }

    return Column(
      children: users
          .map(
            (user) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: userCard(user),
            ),
          )
          .toList(),
    );
  }

  Widget _matrixInfoPill(IconData icon, String label) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 230),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: kAdminMuted),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10.5, color: kAdminMuted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _permissionMapSection({required bool isMobile}) {
    final rows =
        <({String modulo, String visible, String permisos, String donde})>[
          (
            modulo: 'Módulos visibles',
            visible: 'Campo apps del usuario',
            permisos: 'Solo decide si aparece en el Home',
            donde: 'Matriz central / Admin > Apps',
          ),
          (
            modulo: 'Tareas',
            visible: 'tareasdashboard',
            permisos:
                'Área propia/todas las áreas y vista del equipo por empresa',
            donde: 'Matriz central > Tareas',
          ),
          (
            modulo: 'Correo y Correspondencia',
            visible: 'correodashboard',
            permisos: 'TBL_CORREO_ROLES',
            donde: 'Matriz central / Vista detallada de Correspondencia',
          ),
          (
            modulo: 'Tokens DIAN',
            visible: 'tokensdiandashboard',
            permisos: 'Lista de personal autorizado',
            donde: 'Matriz central / Admin > Tokens DIAN',
          ),
          (
            modulo: 'Rutas',
            visible: 'rutasdashboard',
            permisos: 'TBL_RUTAS_ROLES',
            donde: 'Matriz central',
          ),
          (
            modulo: 'Compras',
            visible: 'comprasdashboard',
            permisos: 'TBL_COMPRAS_ROLES',
            donde: 'Matriz central',
          ),
          (
            modulo: 'Interventoría',
            visible: 'interventoriadashboard',
            permisos: 'TBL_INTERVENTORIA_ROLES',
            donde: 'Matriz central',
          ),
          (
            modulo: 'Facturación',
            visible: 'facturaciondashboard',
            permisos: 'rolFac',
            donde: 'Matriz central',
          ),
          (
            modulo: 'Gestión de Correspondencia',
            visible: 'gestiondocumentaldashboard',
            permisos: 'rolDocumental / rolPlanillas',
            donde: 'Matriz central',
          ),
        ];

    if (isMobile) {
      return Column(
        children: rows
            .map(
              (row) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(
                    row.modulo,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: Text(
                    'Visible: ${row.visible}\nPermisos: ${row.permisos}\nEditar: ${row.donde}',
                  ),
                  isThreeLine: true,
                ),
              ),
            )
            .toList(),
      );
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: PagedDataTable(
          etiqueta: 'registros',
          tabla: DataTable(
            headingRowColor: WidgetStateProperty.all(kAdminBg),
            columns: const [
              DataColumn(label: Text('Capa / módulo')),
              DataColumn(label: Text('Se muestra por')),
              DataColumn(label: Text('Permisos internos')),
              DataColumn(label: Text('Dónde se edita')),
            ],
            rows: rows
                .map(
                  (row) => DataRow(
                    cells: [
                      DataCell(
                        Text(
                          row.modulo,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      DataCell(Text(row.visible)),
                      DataCell(Text(row.permisos)),
                      DataCell(Text(row.donde)),
                    ],
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }

  Widget _accessRoleCatalogSection({required bool isMobile}) {
    final roles = [
      ..._accessRoles,
    ]..sort((a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));

    if (roles.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: kAdminBorder),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Text(
          'Aún no hay perfiles generales. Importa los actuales o crea uno nuevo.',
          textAlign: TextAlign.center,
        ),
      );
    }

    if (isMobile) {
      return Column(
        children: roles.map((role) {
          final isDeveloper =
              role.roleKey == 'desarrollador' || role.roleKey == 'developer';
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: role.enabled
                    ? kAdminAccent.withValues(alpha: 0.12)
                    : kAdminBorder,
                child: Icon(
                  isDeveloper ? Icons.code_rounded : Icons.badge_outlined,
                  color: role.enabled ? kAdminAccent : kAdminMuted,
                ),
              ),
              title: Text(
                role.nombre,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: Text('${role.roleKey}\n${_roleAppsSummary(role)}'),
              isThreeLine: true,
              trailing: IconButton(
                tooltip: 'Editar',
                onPressed: () => _dialogAccessRole(role: role),
                icon: const Icon(Icons.edit_outlined),
              ),
            ),
          );
        }).toList(),
      );
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: PagedDataTable(
          etiqueta: 'registros',
          tabla: DataTable(
            headingRowColor: WidgetStateProperty.all(kAdminBg),
            columns: const [
              DataColumn(label: Text('Perfil')),
              DataColumn(label: Text('Código interno')),
              DataColumn(label: Text('Estado')),
              DataColumn(label: Text('Módulos que agrega')),
              DataColumn(label: Text('Acción')),
            ],
            rows: roles.map((role) {
              return DataRow(
                cells: [
                  DataCell(
                    Row(
                      children: [
                        Icon(
                          _accessRoleIcon(role),
                          size: 18,
                          color: kAdminMuted,
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 180,
                          child: Text(
                            role.nombre,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                  ),
                  DataCell(Text(role.roleKey)),
                  DataCell(
                    Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text(role.enabled ? 'Activo' : 'Inactivo'),
                      backgroundColor: role.enabled
                          ? const Color(0xFFEFFDF5)
                          : const Color(0xFFFEF2F2),
                      labelStyle: TextStyle(
                        color: role.enabled ? kAdminSuccess : kAdminError,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  DataCell(
                    SizedBox(
                      width: 260,
                      child: Text(
                        _roleAppsSummary(role),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  DataCell(
                    OutlinedButton.icon(
                      onPressed: () => _dialogAccessRole(role: role),
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text('Editar'),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  // Respaldos internos: se conserva por si hay que reactivar la vista simple
  // de perfiles, pero la operación principal quedó centralizada en la matriz.
  // ignore: unused_element
  Widget _accessRoleUsersSection({
    required bool isMobile,
    required String empresaId,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> users,
  }) {
    if (users.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: Text('No se encontraron usuarios')),
      );
    }

    if (isMobile) {
      return Column(
        children: users.map((userDoc) {
          final data = userDoc.data();
          final currentRole = _accessRoleForUser(data);
          final legacyName = resolveScopedRoleName(data, empresaId: empresaId);
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: UserAvatar(
                      userId: userDoc.id,
                      nameHint: _userName(data, userDoc.id),
                    ),
                    title: Text(_userName(data, userDoc.id)),
                    subtitle: Text(
                      '${_userOrgSummary(data, empresaId)}\nMódulos: ${_visibleAppsSummary(data, empresaId)}\nPerfil: ${currentRole?.nombre ?? (legacyName.isEmpty ? 'Sin perfil' : legacyName)}',
                    ),
                    isThreeLine: true,
                  ),
                  _accessRoleDropdown(
                    userDoc: userDoc,
                    empresaId: empresaId,
                    currentRole: currentRole,
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      );
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: PagedDataTable(
          etiqueta: 'registros',
          tabla: DataTable(
            headingRowColor: WidgetStateProperty.all(kAdminBg),
            dataRowMinHeight: 64,
            dataRowMaxHeight: 82,
            columns: const [
              DataColumn(label: Text('Usuario')),
              DataColumn(label: Text('Cargo / área')),
              DataColumn(label: Text('Módulos visibles')),
              DataColumn(label: Text('Perfil general')),
            ],
            rows: users.map((userDoc) {
              final data = userDoc.data();
              final currentRole = _accessRoleForUser(data);
              return DataRow(
                cells: [
                  DataCell(
                    Row(
                      children: [
                        UserAvatar(
                          userId: userDoc.id,
                          nameHint: _userName(data, userDoc.id),
                          radius: 16,
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 190,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _userName(data, userDoc.id),
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                _safe(data['cedula']).isNotEmpty
                                    ? _safe(data['cedula'])
                                    : userDoc.id,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: kAdminMuted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  DataCell(
                    SizedBox(
                      width: 220,
                      child: Text(
                        _userOrgSummary(data, empresaId),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  DataCell(
                    SizedBox(
                      width: 230,
                      child: Text(
                        _visibleAppsSummary(data, empresaId),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  DataCell(
                    SizedBox(
                      width: 280,
                      child: _accessRoleDropdown(
                        userDoc: userDoc,
                        empresaId: empresaId,
                        currentRole: currentRole,
                      ),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Future<void> _importLegacyAccessRoles() async {
    final empresaId = _empresaId;
    if (empresaId == null || empresaId.isEmpty) return;
    final ok = await _confirm(
      title: 'Importar roles actuales',
      message:
          'Se crearán definiciones para los nombres de rol general que ya '
          'tienen los usuarios. No se cambiarán ni se borrarán sus módulos '
          'asignados.',
      confirmText: 'Importar',
    );
    if (!ok) return;
    final count = await _repo.importLegacyAccessRoles(
      empresaId: empresaId,
      users: _users,
    );
    _snack(
      count == 0
          ? 'No se encontraron roles nuevos para importar'
          : 'Se importaron $count roles',
    );
    await _loadAll(forceEmpresaId: empresaId);
  }

  Future<void> _dialogAccessRole({AccessRoleItem? role}) async {
    final empresaId = _empresaId;
    if (empresaId == null || empresaId.isEmpty) return;
    final nameCtrl = TextEditingController(text: role?.nombre ?? '');
    final descriptionCtrl = TextEditingController(
      text: role?.descripcion ?? '',
    );
    final selectedApps = <String>{...?role?.appIds};
    var enabled = role?.enabled ?? true;
    var saving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final roleKey = role?.roleKey ?? normalizeRoleKey(nameCtrl.text);
          final isDeveloper =
              roleKey == 'desarrollador' || roleKey == 'developer';
          final width = (MediaQuery.of(dialogContext).size.width - 48)
              .clamp(320.0, 680.0)
              .toDouble();
          return AlertDialog(
            title: Text(role == null ? 'Crear rol' : 'Editar rol'),
            content: SizedBox(
              width: width,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      enabled: !saving,
                      decoration: const InputDecoration(
                        labelText: 'Nombre visible del rol',
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: kAdminBg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: kAdminBorder),
                      ),
                      child: Text(
                        role == null
                            ? 'Código interno: ${roleKey.isEmpty ? 'se genera con el nombre' : roleKey}'
                            : 'Código interno: ${role.roleKey} · no cambia al renombrar',
                        style: const TextStyle(
                          fontFamily: kArial,
                          color: kAdminMuted,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    if (role?.isFunctionalModuleRole == true) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF7ED),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFFED7AA)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              _accessRoleIcon(role!),
                              color: const Color(0xFFC2410C),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Traído desde ${role.moduleName}: ${role.moduleRoleLabel.isEmpty ? role.moduleRole : role.moduleRoleLabel}. '
                                'Al asignarlo también se actualiza el rol interno de ese módulo.',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF7C2D12),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: descriptionCtrl,
                      enabled: !saving,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Descripción (opcional)',
                        prefixIcon: Icon(Icons.description_outlined),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Rol activo'),
                      subtitle: const Text(
                        'Al desactivarlo se retiran sus módulos a los usuarios asignados.',
                      ),
                      value: isDeveloper ? true : enabled,
                      onChanged: saving || isDeveloper
                          ? null
                          : (value) => setDialogState(() => enabled = value),
                    ),
                    if (isDeveloper)
                      Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEEF2FF),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.code_rounded, color: Color(0xFF4F46E5)),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'El rol interno desarrollador conserva acceso técnico total. '
                                'Puedes cambiar su nombre visible sin romper ese acceso.',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const Text(
                      'Módulos autorizados',
                      style: TextStyle(
                        fontFamily: kArial,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 300),
                      decoration: BoxDecoration(
                        border: Border.all(color: kAdminBorder),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: _appsAdmin.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(16),
                              child: Text('No hay módulos configurados.'),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: _appsAdmin.length,
                              itemBuilder: (_, index) {
                                final app = _appsAdmin[index];
                                final appId = _appIdOf(app);
                                final checked = selectedApps.any(
                                  (id) => appIdsEquivalent(id, appId),
                                );
                                return CheckboxListTile(
                                  dense: true,
                                  value: isDeveloper ? true : checked,
                                  onChanged: saving || isDeveloper
                                      ? null
                                      : (value) => setDialogState(() {
                                          selectedApps.removeWhere(
                                            (id) => appIdsEquivalent(id, appId),
                                          );
                                          if (value == true) {
                                            selectedApps.add(appId);
                                          }
                                        }),
                                  title: Text(_appDisplayName(app)),
                                  subtitle: Text(appId),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(dialogContext),
                child: const Text('Cancelar'),
              ),
              ElevatedButton.icon(
                onPressed: saving
                    ? null
                    : () async {
                        final nombre = nameCtrl.text.trim();
                        final newKey = normalizeRoleKey(nombre);
                        if (nombre.isEmpty || newKey.isEmpty) {
                          _snack('Escribe un nombre válido para el rol');
                          return;
                        }
                        if (role == null &&
                            _accessRoles.any(
                              (item) => item.roleKey == newKey,
                            )) {
                          _snack('Ya existe un rol con ese código interno');
                          return;
                        }
                        setDialogState(() => saving = true);
                        try {
                          final apps = isDeveloper
                              ? _appsAdmin.map(_appIdOf)
                              : selectedApps;
                          await _repo.saveAccessRole(
                            empresaId: empresaId,
                            nombre: nombre,
                            descripcion: descriptionCtrl.text,
                            appIds: apps,
                            existingRoleId: role?.roleId,
                            existingRoleKey: role?.roleKey,
                            enabled: enabled,
                            moduleId: role?.moduleId ?? '',
                            moduleName: role?.moduleName ?? '',
                            moduleRole: role?.moduleRole ?? '',
                            moduleRoleLabel: role?.moduleRoleLabel ?? '',
                          );
                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext);
                          }
                          _snack('Rol y permisos guardados');
                          await _loadAll(forceEmpresaId: empresaId);
                        } catch (e) {
                          _snack('No se pudo guardar el rol: $e');
                          if (dialogContext.mounted) {
                            setDialogState(() => saving = false);
                          }
                        }
                      },
                icon: saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: const Text('Guardar y aplicar'),
              ),
            ],
          );
        },
      ),
    );
    nameCtrl.dispose();
    descriptionCtrl.dispose();
  }

  /// Explica las tres capas sin exponer nombres de colecciones o campos.
  Widget _correoRoleCallout() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFECFDF5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFA7F3D0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.mark_email_unread_rounded, color: Color(0xFF0F766E)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Un solo centro para saber quién puede hacer qué',
                  style: TextStyle(
                    fontFamily: kArial,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF065F46),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  '1) Acceso determina si la persona puede abrir el módulo. '
                  '2) Rol interno determina qué acciones puede realizar. '
                  '3) Perfil general es una plantilla opcional para asignar '
                  'varios módulos. Abre el botón de un módulo para administrar '
                  'únicamente a las personas de la empresa activa.',
                  style: TextStyle(
                    fontFamily: kArial,
                    fontSize: 12.5,
                    height: 1.4,
                    color: Color(0xFF065F46),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabAccessRoles() {
    final empresaId = _empresaId ?? '';
    final isMobile = MediaQuery.of(context).size.width < 760;
    final allModules = _accessMatrixModules();
    final matrixModules = _filteredAccessMatrixModules();
    final companyUsers = _matrixCompanyUsers(empresaId);

    if (matrixModules.length == 1) {
      return _moduleAccessDetailTab(
        module: matrixModules.single,
        empresaId: empresaId,
        companyUsers: companyUsers,
        isMobile: isMobile,
      );
    }

    return ListView(
      padding: EdgeInsets.all(isMobile ? 12 : 24),
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 12,
          children: [
            const SizedBox(
              width: 520,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Centro de accesos por módulo',
                    style: TextStyle(
                      fontFamily: kArial,
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                    ),
                  ),
                  Text(
                    'Selecciona un módulo para abrir su vista detallada. El personal no se carga en esta pantalla general.',
                    style: TextStyle(color: kAdminMuted, fontSize: 13),
                  ),
                ],
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _importLegacyAccessRoles,
                  icon: const Icon(Icons.download_for_offline_outlined),
                  label: const Text('Importar actuales'),
                ),
                ElevatedButton.icon(
                  onPressed: () => _dialogAccessRole(),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Nuevo perfil'),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 18),
        _correoRoleCallout(),
        const SizedBox(height: 18),
        _matrixModuleSelector(
          allModules: allModules,
          users: companyUsers,
          empresaId: empresaId,
        ),
        const SizedBox(height: 24),
        Card(
          clipBehavior: Clip.antiAlias,
          child: ExpansionTile(
            title: const Text('Mapa de permisos'),
            subtitle: const Text(
              'Consulta qué controla cada módulo sin abrir la lista de usuarios.',
            ),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: _permissionMapSection(isMobile: isMobile),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Card(
          clipBehavior: Clip.antiAlias,
          child: ExpansionTile(
            title: const Text('Perfiles generales (opcional)'),
            subtitle: Text('${_accessRoles.length} perfil(es) configurado(s)'),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: _accessRoleCatalogSection(isMobile: isMobile),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _moduleAccessDetailTab({
    required _AccessMatrixModule module,
    required String empresaId,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> companyUsers,
    required bool isMobile,
  }) {
    final matrixModules = <_AccessMatrixModule>[module];
    final personnelUsers = _sortAccessRoleUsers(
      _applyPersonnelFilter(
        companyUsers,
        search: _accessRoleUserSearch,
        areaId: _accessRoleAreaFilter,
      ),
      empresaId,
    );
    final filteredUsers = _filterAccessRoleUsersByStatus(
      users: personnelUsers,
      modules: matrixModules,
      empresaId: empresaId,
    );
    final pageCount = filteredUsers.isEmpty
        ? 1
        : (filteredUsers.length / _accessRolePageSize).ceil();
    final safePage = _accessRolePage.clamp(0, pageCount - 1).toInt();
    final visibleUsers = filteredUsers
        .skip(safePage * _accessRolePageSize)
        .take(_accessRolePageSize)
        .toList();
    final empresaNombre = _empresaActual?.nombre ?? empresaId;
    final accessCount = companyUsers
        .where((user) => _matrixUserHasApp(user, module.appId, empresaId))
        .length;
    final roleOptions = _matrixModuleRoleOptions(module);

    return ListView(
      padding: EdgeInsets.all(isMobile ? 12 : 24),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: kAdminBorder),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Volver a módulos',
                onPressed: () => setState(() {
                  _accessRoleAppFilter = null;
                  _accessRoleUserSearch = '';
                  _accessRoleAreaFilter = null;
                  _selectedAccessUserIds = <String>{};
                  _accessRolePage = 0;
                }),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: module.color.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(module.icon, color: module.color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Roles y accesos de ${module.label}',
                      style: const TextStyle(
                        fontFamily: kArial,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                    Text(
                      '$empresaNombre · $accessCount de ${companyUsers.length} personas con acceso',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: kAdminMuted,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Actualizar',
                onPressed: _accessRolesRefreshing
                    ? null
                    : () => _reloadAccessMatrix(),
                icon: _accessRolesRefreshing
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: kAdminBorder),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Qué controla ${module.label}',
                style: const TextStyle(
                  fontFamily: kArial,
                  fontWeight: FontWeight.w900,
                  color: kAdminPrimary,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                _matrixModulePermissionHint(module),
                style: const TextStyle(color: kAdminMuted, fontSize: 12.5),
              ),
              if (roleOptions.isNotEmpty) ...[
                const SizedBox(height: 14),
                const Text(
                  'Qué puede hacer cada rol',
                  style: TextStyle(
                    fontFamily: kArial,
                    fontWeight: FontWeight.w800,
                    color: kAdminPrimary,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 8),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final oneColumn = constraints.maxWidth < 760;
                    final cardWidth = oneColumn
                        ? constraints.maxWidth
                        : (constraints.maxWidth - 10) / 2;
                    return Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: roleOptions.entries
                          .map(
                            (entry) => SizedBox(
                              width: cardWidth,
                              child: Container(
                                padding: const EdgeInsets.all(11),
                                decoration: BoxDecoration(
                                  color: module.color.withValues(alpha: .055),
                                  border: Border.all(
                                    color: module.color.withValues(alpha: .18),
                                  ),
                                  borderRadius: BorderRadius.circular(11),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 30,
                                      height: 30,
                                      decoration: BoxDecoration(
                                        color: module.color.withValues(
                                          alpha: .12,
                                        ),
                                        borderRadius: BorderRadius.circular(9),
                                      ),
                                      child: Icon(
                                        Icons.verified_user_outlined,
                                        size: 17,
                                        color: module.color,
                                      ),
                                    ),
                                    const SizedBox(width: 9),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            entry.value,
                                            style: const TextStyle(
                                              fontFamily: kArial,
                                              fontWeight: FontWeight.w800,
                                              color: kAdminPrimary,
                                              fontSize: 12.5,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            _matrixModuleRoleDescription(
                                              module,
                                              entry.key,
                                            ),
                                            style: const TextStyle(
                                              color: kAdminMuted,
                                              fontSize: 11.5,
                                              height: 1.3,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    );
                  },
                ),
              ],
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 12),
              const Text(
                'Acceso general al módulo',
                style: TextStyle(
                  fontFamily: kArial,
                  fontWeight: FontWeight.w800,
                  color: kAdminPrimary,
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'Aplica a las ${companyUsers.length} personas de $empresaNombre. '
                'El rol operativo se asigna individualmente.',
                style: const TextStyle(color: kAdminMuted, fontSize: 11.5),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 9,
                runSpacing: 9,
                children: [
                  FilledButton.icon(
                    onPressed:
                        _accessRolesRefreshing ||
                            companyUsers.isEmpty ||
                            accessCount == companyUsers.length
                        ? null
                        : () => _setMatrixUsersModules(
                            users: companyUsers,
                            visible: true,
                            modules: matrixModules,
                          ),
                    icon: const Icon(Icons.group_add_outlined, size: 18),
                    label: const Text('Dar acceso a todos'),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: kAdminError,
                      side: const BorderSide(color: kAdminError),
                    ),
                    onPressed:
                        _accessRolesRefreshing ||
                            companyUsers.isEmpty ||
                            accessCount == 0
                        ? null
                        : () => _setMatrixUsersModules(
                            users: companyUsers,
                            visible: false,
                            modules: matrixModules,
                          ),
                    icon: const Icon(Icons.group_off_outlined, size: 18),
                    label: const Text('Quitar acceso a todos'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _buildPersonnelFilterBar(
          searchHint: 'Buscar por nombre, cédula, área o cargo',
          searchValue: _accessRoleUserSearch,
          onSearchChanged: (value) => setState(() {
            _accessRoleUserSearch = value.trim().toLowerCase();
            _selectedAccessUserIds = <String>{};
            _accessRolePage = 0;
          }),
          selectedAreaId: _accessRoleAreaFilter,
          onAreaChanged: (value) => setState(() {
            _accessRoleAreaFilter = value;
            _selectedAccessUserIds = <String>{};
            _accessRolePage = 0;
          }),
        ),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _matrixAccessStatusFilter(
              modules: matrixModules,
              isMobile: isMobile,
            ),
            OutlinedButton.icon(
              onPressed: _accessRolesRefreshing
                  ? null
                  : () => _reloadAccessMatrix(),
              icon: _accessRolesRefreshing
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded, size: 18),
              label: Text(
                _accessRolesRefreshing ? 'Actualizando' : 'Actualizar accesos',
              ),
            ),
          ],
        ),
        if (_accessRolesRefreshing) ...[
          const SizedBox(height: 8),
          const LinearProgressIndicator(minHeight: 2),
        ],
        const SizedBox(height: 10),
        _matrixFilteredBulkActions(
          users: filteredUsers,
          modules: matrixModules,
        ),
        const SizedBox(height: 12),
        _accessMatrixSection(
          empresaId: empresaId,
          users: visibleUsers,
          modules: matrixModules,
        ),
        if (filteredUsers.length > _accessRolePageSize) ...[
          const SizedBox(height: 10),
          _accessRolePager(
            page: safePage,
            pageCount: pageCount,
            total: filteredUsers.length,
          ),
        ],
        const SizedBox(height: 30),
      ],
    );
  }

  Widget _accessRolePager({
    required int page,
    required int pageCount,
    required int total,
  }) {
    final first = total == 0 ? 0 : page * _accessRolePageSize + 1;
    final last = ((page + 1) * _accessRolePageSize).clamp(0, total);
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          '$first–$last de $total',
          style: const TextStyle(color: kAdminMuted),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Página anterior',
          onPressed: page <= 0
              ? null
              : () => setState(() => _accessRolePage = page - 1),
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Text('${page + 1} / $pageCount'),
        IconButton(
          tooltip: 'Página siguiente',
          onPressed: page >= pageCount - 1
              ? null
              : () => setState(() => _accessRolePage = page + 1),
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
  }

  // ---------------- TAB: APPS ----------------
  Widget _tabApps() {
    final width = MediaQuery.of(context).size.width;
    final isWeb = width >= 900;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Gestión de Aplicaciones',
                  style: TextStyle(
                    fontFamily: kArial,
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                  ),
                ),
                Text(
                  'Habilita o deshabilita módulos para la empresa activa',
                  style: TextStyle(
                    fontFamily: kArial,
                    fontSize: 13,
                    color: kAdminMuted,
                  ),
                ),
              ],
            ),
            const Spacer(),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: kAdminPrimary,
                side: const BorderSide(color: kAdminBorder),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: _normalizeAppsCatalog,
              icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
              label: const Text(
                'Normalizar',
                style: TextStyle(
                  fontFamily: kArial,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: kAdminPrimary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () => _dialogApp(),
              icon: const Icon(Icons.add, size: 20),
              label: const Text(
                'Nueva App',
                style: TextStyle(
                  fontFamily: kArial,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (_appsAdmin.isEmpty)
          Container(
            height: 200,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: kAdminBorder),
            ),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.apps_outage, size: 48, color: kAdminMuted),
                SizedBox(height: 12),
                Text(
                  'No hay apps registradas en esta empresa',
                  style: TextStyle(fontFamily: kArial, color: kAdminMuted),
                ),
              ],
            ),
          )
        else
          isWeb
              ? GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 450,
                    mainAxisExtent: 140,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: _appsAdmin.length,
                  itemBuilder: (context, index) =>
                      _appGridItem(_appsAdmin[index]),
                )
              : Column(
                  children: _appsAdmin.map((a) => _appListItem(a)).toList(),
                ),
      ],
    );
  }

  Widget _appGridItem(QueryDocumentSnapshot<Map<String, dynamic>> aDoc) {
    final a = aDoc.data();
    final appId = _safe(a['appId']).isNotEmpty ? _safe(a['appId']) : aDoc.id;
    final nombre = _safe(a['nombre']).isNotEmpty ? _safe(a['nombre']) : appId;
    final descripcion = _safe(a['descripcion']);
    final enabled = (a['enabled'] as bool?) ?? true;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: enabled ? kAdminBorder : kAdminError.withValues(alpha: 0.2),
        ),
      ),
      color: enabled ? Colors.white : kAdminError.withValues(alpha: 0.02),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: (enabled ? kAdminAccent : kAdminMuted).withValues(
                      alpha: 0.1,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.apps,
                    color: enabled ? kAdminAccent : kAdminMuted,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nombre,
                        style: const TextStyle(
                          fontFamily: kArial,
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        appId,
                        style: const TextStyle(
                          fontFamily: kArial,
                          fontSize: 11,
                          color: kAdminMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                _statusBadge(enabled),
              ],
            ),
            const Spacer(),
            // Contador de usuarios con acceso
            GestureDetector(
              onTap: () => _showAppUsersSheet(context, appId, nombre),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: kAdminAccent.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: kAdminAccent.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.people_alt_rounded,
                      size: 13,
                      color: kAdminAccent.withValues(alpha: 0.8),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '${_countUsersWithApp(appId)} usuarios',
                      style: TextStyle(
                        fontFamily: kArial,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: kAdminAccent.withValues(alpha: 0.85),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.open_in_new_rounded,
                      size: 11,
                      color: kAdminAccent.withValues(alpha: 0.6),
                    ),
                  ],
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    descripcion.isNotEmpty ? descripcion : 'Sin descripción',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: kArial,
                      fontSize: 12,
                      color: kAdminMuted,
                    ),
                  ),
                ),
                Switch(
                  value: enabled,
                  activeThumbColor: kAdminSuccess,
                  onChanged: (v) async {
                    await _repo.setAppEnabled(aDoc.id, v);
                    _snack('App ${v ? "habilitada" : "deshabilitada"}');
                    await _loadAll(forceEmpresaId: _empresaId);
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.settings_outlined, size: 20),
                  onPressed: () => _dialogApp(existing: aDoc),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _appListItem(QueryDocumentSnapshot<Map<String, dynamic>> aDoc) {
    final a = aDoc.data();
    final appId = _safe(a['appId']).isNotEmpty ? _safe(a['appId']) : aDoc.id;
    final nombre = _safe(a['nombre']).isNotEmpty ? _safe(a['nombre']) : appId;
    final descripcion = _safe(a['descripcion']);
    final enabled = (a['enabled'] as bool?) ?? true;

    final userCount = _countUsersWithApp(appId);
    return _catalogTile(
      title: nombre,
      subtitle: appId,
      enabled: enabled,
      trailing2: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (descripcion.isNotEmpty)
            Text(
              descripcion,
              style: const TextStyle(
                fontFamily: kArial,
                fontSize: 11,
                color: kAdminMuted,
              ),
            ),
          const SizedBox(height: 4),
          GestureDetector(
            onTap: () => _showAppUsersSheet(context, appId, nombre),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: kAdminAccent.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kAdminAccent.withValues(alpha: 0.2)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.people_alt_rounded,
                    size: 12,
                    color: kAdminAccent.withValues(alpha: 0.8),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$userCount usuarios · Gestionar',
                    style: TextStyle(
                      fontFamily: kArial,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: kAdminAccent.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      onEdit: () => _dialogApp(existing: aDoc),
      onToggle: (v) async {
        await _repo.setAppEnabled(aDoc.id, v);
        _snack('App ${v ? "habilitada" : "deshabilitada"}');
        await _loadAll(forceEmpresaId: _empresaId);
      },
    );
  }

  // ---------------- APP: PANEL DE USUARIOS ----------------

  /// Cuenta cuántos usuarios tienen asignado [appId] (normalizado).
  int _countUsersWithApp(String appId) {
    return _users.where((u) {
      return (_userApps[u.id] ?? {}).any((a) => appIdsEquivalent(a, appId));
    }).length;
  }

  void _showAppUsersSheet(
    BuildContext context,
    String appId,
    String appNombre,
  ) {
    final normId = normalizeAppId(appId) ?? appId;
    final isWeb = MediaQuery.of(context).size.width >= 900;

    // Estado inicial: snapshot de asignaciones actuales
    final Map<String, bool> initial = {
      for (final u in _users)
        u.id: (_userApps[u.id] ?? {}).any((a) => appIdsEquivalent(a, normId)),
    };

    // ── helper: nombre legible de un doc de usuario ──────────────────────────
    String _userName(Map<String, dynamic> d) {
      final n = [
        (d['nombres'] ?? d['primerNombre'] ?? '').toString().trim(),
        (d['apellidos'] ?? d['primerApellido'] ?? '').toString().trim(),
      ].where((s) => s.isNotEmpty).join(' ');
      return n.isNotEmpty ? n : '(sin nombre)';
    }

    final content = StatefulBuilder(
      builder: (ctx, setSS) {
        // Filtros locales
        String search = '';
        String areaFilter = '';
        String cargoFilter = '';
        final selection = Map<String, bool>.from(initial);

        return StatefulBuilder(
          builder: (ctx2, setSS2) {
            // Usuarios visibles según filtros
            final visible = _users.where((u) {
              final d = u.data();
              final nombre = _userName(d).toLowerCase();
              final uAreaId = (d['areaId'] ?? '').toString().trim();
              final uCargoId = (d['cargoId'] ?? '').toString().trim();
              if (search.isNotEmpty && !nombre.contains(search.toLowerCase())) {
                return false;
              }
              if (areaFilter.isNotEmpty && uAreaId != areaFilter) return false;
              if (cargoFilter.isNotEmpty && uCargoId != cargoFilter) {
                return false;
              }
              return true;
            }).toList();

            final editableVisible = visible
                .where((user) => _accessRoleForUser(user.data()) == null)
                .toList();
            final allSelected =
                editableVisible.isNotEmpty &&
                editableVisible.every((u) => selection[u.id] == true);

            // ── UI ──────────────────────────────────────────────────────────────
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Cabecera
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: kAdminAccent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.apps,
                          color: kAdminAccent,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              appNombre,
                              style: const TextStyle(
                                fontFamily: kArial,
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              'Gestión de acceso · ${visible.length} usuarios visibles',
                              style: const TextStyle(
                                fontFamily: kArial,
                                fontSize: 12,
                                color: kAdminMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(ctx2),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 12),

                // Filtros
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      // Búsqueda
                      SizedBox(
                        width: isWeb ? 260 : double.infinity,
                        child: TextField(
                          decoration: InputDecoration(
                            hintText: 'Buscar por nombre…',
                            prefixIcon: const Icon(
                              Icons.search_rounded,
                              size: 18,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: kAdminBorder),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            isDense: true,
                          ),
                          onChanged: (v) => setSS2(() => search = v.trim()),
                        ),
                      ),
                      // Área
                      SizedBox(
                        width: isWeb ? 200 : double.infinity,
                        child: DropdownButtonFormField<String>(
                          initialValue: areaFilter.isEmpty ? null : areaFilter,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: 'Área',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            isDense: true,
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: '',
                              child: Text('Todas'),
                            ),
                            ..._areas
                                .where((a) => a.enabled)
                                .map(
                                  (a) => DropdownMenuItem(
                                    value: a.areaId,
                                    child: Text(
                                      a.nombre,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                          ],
                          onChanged: (v) => setSS2(() => areaFilter = v ?? ''),
                        ),
                      ),
                      // Cargo
                      SizedBox(
                        width: isWeb ? 200 : double.infinity,
                        child: DropdownButtonFormField<String>(
                          initialValue: cargoFilter.isEmpty
                              ? null
                              : cargoFilter,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: 'Cargo',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            isDense: true,
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: '',
                              child: Text('Todos'),
                            ),
                            ..._cargos
                                .where((c) {
                                  if (areaFilter.isEmpty) return true;
                                  return (c.areaId ?? '') == areaFilter;
                                })
                                .map(
                                  (c) => DropdownMenuItem(
                                    value: c.cargoId,
                                    child: Text(
                                      c.nombre,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                          ],
                          onChanged: (v) => setSS2(() => cargoFilter = v ?? ''),
                        ),
                      ),
                    ],
                  ),
                ),

                // Seleccionar / deseleccionar todos
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                  child: Row(
                    children: [
                      Text(
                        '${selection.values.where((v) => v).length} de ${_users.length} seleccionados',
                        style: const TextStyle(
                          fontFamily: kArial,
                          fontSize: 12,
                          color: kAdminMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        icon: Icon(
                          allSelected
                              ? Icons.deselect_rounded
                              : Icons.select_all_rounded,
                          size: 16,
                        ),
                        label: Text(
                          allSelected
                              ? 'Deseleccionar todos'
                              : 'Seleccionar todos',
                          style: const TextStyle(
                            fontFamily: kArial,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        onPressed: editableVisible.isEmpty
                            ? null
                            : () => setSS2(() {
                                for (final u in editableVisible) {
                                  selection[u.id] = !allSelected;
                                }
                              }),
                      ),
                    ],
                  ),
                ),

                const Divider(height: 1),

                // Lista de usuarios
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: isWeb
                        ? 420
                        : MediaQuery.of(ctx2).size.height * 0.45,
                  ),
                  child: visible.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(
                            child: Text(
                              'Ningún usuario coincide con los filtros',
                              style: TextStyle(
                                fontFamily: kArial,
                                color: kAdminMuted,
                              ),
                            ),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: visible.length,
                          itemBuilder: (_, i) {
                            final u = visible[i];
                            final d = u.data();
                            final nombre = _userName(d);
                            final areaId = (d['areaId'] ?? '')
                                .toString()
                                .trim();
                            final cargoId = (d['cargoId'] ?? '')
                                .toString()
                                .trim();
                            final areaNombre =
                                _areas
                                    .where((a) => a.areaId == areaId)
                                    .map((a) => a.nombre)
                                    .firstOrNull ??
                                areaId;
                            final cargoNombre =
                                _cargos
                                    .where((c) => c.cargoId == cargoId)
                                    .map((c) => c.nombre)
                                    .firstOrNull ??
                                (d['cargo'] ?? '').toString().trim();
                            final checked = selection[u.id] == true;
                            final managedRole = _accessRoleForUser(d);

                            return CheckboxListTile(
                              dense: true,
                              value: checked,
                              activeColor: kAdminAccent,
                              title: Text(
                                nombre,
                                style: const TextStyle(
                                  fontFamily: kArial,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                              subtitle: managedRole != null
                                  ? Text(
                                      'Administrado por el rol ${managedRole.nombre}',
                                      style: const TextStyle(
                                        fontFamily: kArial,
                                        fontSize: 11,
                                        color: kAdminAccent,
                                      ),
                                    )
                                  : areaNombre.isNotEmpty ||
                                        cargoNombre.isNotEmpty
                                  ? Text(
                                      [
                                        if (areaNombre.isNotEmpty) areaNombre,
                                        if (cargoNombre.isNotEmpty) cargoNombre,
                                      ].join(' · '),
                                      style: const TextStyle(
                                        fontFamily: kArial,
                                        fontSize: 11,
                                        color: kAdminMuted,
                                      ),
                                    )
                                  : null,
                              onChanged: managedRole == null
                                  ? (v) => setSS2(
                                      () => selection[u.id] = v ?? false,
                                    )
                                  : null,
                            );
                          },
                        ),
                ),

                const Divider(height: 1),

                // Botones
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton(
                        onPressed: () => Navigator.pop(ctx2),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: kAdminBorder),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text(
                          'Cancelar',
                          style: TextStyle(fontFamily: kArial),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kAdminPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                        ),
                        icon: const Icon(Icons.save_rounded, size: 18),
                        label: const Text(
                          'Guardar cambios',
                          style: TextStyle(
                            fontFamily: kArial,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        onPressed: () async {
                          // Solo actualiza usuarios cuyo estado cambió
                          final changed = _users.where((u) {
                            if (_accessRoleForUser(u.data()) != null) {
                              return false;
                            }
                            return (selection[u.id] ?? false) !=
                                (initial[u.id] ?? false);
                          }).toList();

                          if (changed.isEmpty) {
                            Navigator.pop(ctx2);
                            return;
                          }

                          int saved = 0;
                          for (final u in changed) {
                            final currentApps = Set<String>.from(
                              _userApps[u.id] ?? {},
                            );
                            if (selection[u.id] == true) {
                              currentApps.add(normId);
                            } else {
                              currentApps.removeWhere(
                                (a) => appIdsEquivalent(a, normId),
                              );
                            }
                            await _repo.updateUserApps(
                              u.id,
                              currentApps,
                              empresaId: _empresaId,
                            );
                            saved++;
                          }

                          if (!mounted || !ctx2.mounted) return;
                          Navigator.pop(ctx2);
                          _snack('$saved usuario(s) actualizados');
                          await _loadAll(forceEmpresaId: _empresaId);
                        },
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    if (isWeb) {
      showDialog(
        context: context,
        builder: (_) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: SizedBox(
            width: 720,
            child: SingleChildScrollView(child: content),
          ),
        ),
      );
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: content,
        ),
      );
    }
  }

  // ---------------- TAB: CATALOGOS ----------------
  Widget _tabCatalogos() {
    final centros = _centros.toList();
    final areas = _areas.toList();
    final cargos = _cargos.toList();
    final empresa = _empresaActual;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        if (empresa != null) ...[
          _empresaProfileCard(empresa),
          const SizedBox(height: 28),
        ],
        _bodegasAdminSection(),
        const SizedBox(height: 32),
        _tiposDocumentalesAdminSection(),
        const SizedBox(height: 32),
        _sectionHeader(
          title: 'Centros de Costos',
          subtitle: 'TBL_CENTROS_COSTOS',
          onAdd: () => _dialogCentro(),
        ),
        const SizedBox(height: 16),
        ...centros.map(
          (c) => _catalogTile(
            title: c.nombre,
            subtitle: '',
            enabled: c.enabled,
            trailing2: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilterChip(
                  label: const Text('Facturación'),
                  selected: c.enabledFacturacion,
                  onSelected: c.enabled
                      ? (value) async {
                          await _repo.setCentroModuleEnabled(
                            centroId: c.centroId,
                            module: 'facturacion',
                            enabled: value,
                          );
                          _snack(
                            '${c.nombre}: ${value ? "visible" : "oculto"} en Facturación',
                          );
                          await _loadAll(forceEmpresaId: _empresaId);
                        }
                      : null,
                ),
                FilterChip(
                  label: const Text('Interventoría'),
                  selected: c.enabledInterventoria,
                  onSelected: c.enabled
                      ? (value) async {
                          await _repo.setCentroModuleEnabled(
                            centroId: c.centroId,
                            module: 'interventoria',
                            enabled: value,
                          );
                          _snack(
                            '${c.nombre}: ${value ? "visible" : "oculto"} en Interventoría',
                          );
                          await _loadAll(forceEmpresaId: _empresaId);
                        }
                      : null,
                ),
              ],
            ),
            onEdit: () => _dialogCentro(existing: c),
            onToggle: (v) async {
              await _repo.setCentroEnabled(c.centroId, v);
              _snack('Centro ${v ? "habilitado" : "deshabilitado"}');
              await _loadAll(forceEmpresaId: _empresaId);
            },
          ),
        ),
        const SizedBox(height: 32),
        _sectionHeader(
          title: 'Áreas',
          subtitle: 'TBL_AREAS',
          onAdd: () => _dialogArea(),
        ),
        const SizedBox(height: 16),
        ...areas.map(
          (a) => _catalogTile(
            title: a.nombre,
            subtitle: '',
            enabled: a.enabled,
            onEdit: () => _dialogArea(existing: a),
            onToggle: (v) async {
              await _repo.setAreaEnabled(a.areaId, v);
              _snack('Área ${v ? "habilitada" : "deshabilitada"}');
              await _loadAll(forceEmpresaId: _empresaId);
            },
          ),
        ),
        const SizedBox(height: 32),
        _sectionHeader(
          title: 'Cargos',
          subtitle: 'TBL_CARGOS',
          onAdd: () => _dialogCargo(),
        ),
        const SizedBox(height: 16),
        ...cargos.map(
          (c) => _catalogTile(
            title: c.nombre,
            subtitle: '',
            enabled: c.enabled,
            trailing2: Text(
              [
                if (c.centroId != null) 'Centro:${c.centroId}',
                if (c.areaId != null) 'Área:${c.areaId}',
              ].join('  •  '),
              style: const TextStyle(
                fontFamily: kArial,
                fontSize: 11,
                color: kAdminMuted,
              ),
            ),
            onEdit: () => _dialogCargo(existing: c),
            onToggle: (v) async {
              await _repo.setCargoEnabled(c.cargoId, v);
              _snack('Cargo ${v ? "habilitado" : "deshabilitado"}');
              await _loadAll(forceEmpresaId: _empresaId);
            },
          ),
        ),
      ],
    );
  }

  EmpresaItem? get _empresaActual {
    final eid = (_empresaId ?? '').trim();
    if (eid.isEmpty) return null;
    for (final empresa in _empresas) {
      if (empresa.empresaId == eid) return empresa;
    }
    return null;
  }

  /// Acceso al maestro de tipos documentales de Gestión de Correspondencia.
  ///
  /// Vive en su propia pantalla (`gd_tipos_documentales_screen.dart`) y no
  /// embebido aquí: el CRUD necesita validar el código contra los expedientes
  /// ya codificados, y esa lógica pertenece al módulo, no al panel de Admin.
  Widget _tiposDocumentalesAdminSection() {
    final empresa = _empresaActual;
    if (empresa == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Correspondencia: maestros y roles',
          style: const TextStyle(
            fontFamily: kArial,
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: kAdminPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'TBL_GD_TIPOS_DOCUMENTALES · TBL_CORREO_ROLES · ${empresa.nombre}',
          style: const TextStyle(
            fontFamily: kArial,
            fontSize: 11,
            color: kAdminMuted,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: kAdminBorder),
          ),
          child: Row(
            children: [
              const Icon(Icons.sell_outlined, color: kAdminMuted),
              const SizedBox(width: 14),
              const Expanded(
                child: Text(
                  'Códigos, nombres y alias con los que se clasifica la '
                  'correspondencia. De su código sale el código interno del '
                  'expediente (TUT100826-001).',
                  style: TextStyle(
                    fontFamily: kArial,
                    fontSize: 13,
                    height: 1.4,
                    color: kAdminMuted,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              OutlinedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => GdTiposDocumentalesScreen(
                      userId: widget.userId,
                      empresaId: empresa.empresaId,
                      empresaNombre: empresa.nombre,
                    ),
                  ),
                ),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text(
                  'Administrar',
                  style: TextStyle(
                    fontFamily: kArial,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: kAdminBorder),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.admin_panel_settings_outlined,
                color: kAdminMuted,
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Text(
                  'Roles de Correspondencia: quién puede clasificar y asignar. '
                  'Sin rol asignado, el usuario solo trabaja lo que se le '
                  'asigne.',
                  style: TextStyle(
                    fontFamily: kArial,
                    fontSize: 13,
                    height: 1.4,
                    color: kAdminMuted,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              OutlinedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => GdRolesScreen(
                      userId: widget.userId,
                      empresaId: empresa.empresaId,
                      empresaNombre: empresa.nombre,
                    ),
                  ),
                ),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text(
                  'Administrar',
                  style: TextStyle(
                    fontFamily: kArial,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _bodegasAdminSection() {
    final empresa = _empresaActual;
    if (empresa == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          title: 'Bodegas de la empresa',
          subtitle: 'TBL_COMPRAS_BODEGAS · ${empresa.nombre}',
          onAdd: () => _dialogBodega(),
        ),
        const SizedBox(height: 12),
        if (_bodegas.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kAdminBorder),
            ),
            child: const Row(
              children: [
                Icon(Icons.warehouse_outlined, color: kAdminMuted),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Esta empresa todavía no tiene bodegas configuradas.',
                    style: TextStyle(fontFamily: kArial, color: kAdminMuted),
                  ),
                ),
              ],
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 760) {
                return Column(
                  children: [
                    for (final bodega in _bodegas) ...[
                      _catalogTile(
                        title: bodega.nombre,
                        subtitle: bodega.direccion,
                        enabled: bodega.enabled,
                        onEdit: () => _dialogBodega(existing: bodega),
                        onToggle: (enabled) => _toggleBodega(bodega, enabled),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
                );
              }

              return Card(
                elevation: 0,
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: kAdminBorder),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: PagedDataTable(
                    etiqueta: 'registros',
                    tabla: DataTable(
                      columns: const [
                        DataColumn(label: Text('Bodega')),
                        DataColumn(label: Text('Dirección')),
                        DataColumn(label: Text('Estado')),
                        DataColumn(label: Text('Acciones')),
                      ],
                      rows: _bodegas
                          .map(
                            (bodega) => DataRow(
                              cells: [
                                DataCell(
                                  Text(
                                    bodega.nombre,
                                    style: const TextStyle(
                                      fontFamily: kArial,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    bodega.direccion.isEmpty
                                        ? 'Sin dirección'
                                        : bodega.direccion,
                                    style: const TextStyle(fontFamily: kArial),
                                  ),
                                ),
                                DataCell(
                                  Switch(
                                    value: bodega.enabled,
                                    onChanged: (enabled) =>
                                        _toggleBodega(bodega, enabled),
                                  ),
                                ),
                                DataCell(
                                  IconButton(
                                    tooltip: 'Editar bodega',
                                    onPressed: () =>
                                        _dialogBodega(existing: bodega),
                                    icon: const Icon(Icons.edit_outlined),
                                  ),
                                ),
                              ],
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Future<void> _toggleBodega(BodegaItem bodega, bool enabled) async {
    try {
      await _repo.setBodegaEnabled(bodega.bodegaId, enabled);
      _snack('Bodega ${enabled ? 'habilitada' : 'deshabilitada'}');
      await _loadAll(forceEmpresaId: bodega.empresaId);
    } catch (e) {
      _snack('No se pudo actualizar la bodega: $e');
    }
  }

  Future<void> _dialogBodega({BodegaItem? existing}) async {
    final empresaId = (_empresaId ?? '').trim();
    if (empresaId.isEmpty) return;
    String nombre = existing?.nombre ?? '';
    String direccion = existing?.direccion ?? '';
    bool enabled = existing?.enabled ?? true;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'Nueva bodega' : 'Editar bodega'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  initialValue: nombre,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Nombre de la bodega *',
                    prefixIcon: Icon(Icons.warehouse_outlined),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) => nombre = value.trim(),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: direccion,
                  decoration: const InputDecoration(
                    labelText: 'Dirección (opcional)',
                    prefixIcon: Icon(Icons.location_on_outlined),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) => direccion = value.trim(),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: enabled,
                  title: const Text('Bodega activa'),
                  subtitle: const Text(
                    'Solo las bodegas activas aparecen al crear una recepción.',
                  ),
                  onChanged: (value) => setDialogState(() => enabled = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: () async {
                if (nombre.trim().isEmpty) {
                  _snack('El nombre de la bodega es obligatorio');
                  return;
                }
                final duplicate = _bodegas.any(
                  (bodega) =>
                      bodega.bodegaId != existing?.bodegaId &&
                      bodega.nombre.trim().toLowerCase() ==
                          nombre.trim().toLowerCase(),
                );
                if (duplicate) {
                  _snack('Ya existe una bodega con ese nombre');
                  return;
                }
                try {
                  await _repo.saveBodega(
                    bodegaId: existing?.bodegaId,
                    empresaId: empresaId,
                    nombre: nombre,
                    direccion: direccion,
                    enabled: enabled,
                  );
                  if (!mounted || !dialogContext.mounted) return;
                  Navigator.pop(dialogContext);
                  _snack(
                    existing == null
                        ? 'Bodega creada correctamente'
                        : 'Bodega actualizada',
                  );
                  await _loadAll(forceEmpresaId: empresaId);
                } catch (e) {
                  _snack('No se pudo guardar la bodega: $e');
                }
              },
              icon: const Icon(Icons.save_outlined),
              label: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _empresaProfileCard(EmpresaItem empresa) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: kAdminBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _empresaLogoBox(empresa.logoUrl, size: 72),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Datos de la empresa',
                    style: TextStyle(
                      fontFamily: kArial,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    empresa.nombre,
                    style: const TextStyle(
                      fontFamily: kArial,
                      fontWeight: FontWeight.w700,
                      color: kAdminPrimary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _empresaInfoChip(
                        Icons.badge_outlined,
                        empresa.nit,
                        'Sin NIT',
                      ),
                      _empresaInfoChip(
                        Icons.location_on_outlined,
                        empresa.direccion,
                        'Sin dirección',
                      ),
                      _empresaInfoChip(
                        Icons.call_outlined,
                        empresa.telefono,
                        'Sin teléfono',
                      ),
                      _empresaInfoChip(
                        Icons.mail_outline,
                        empresa.correo,
                        'Sin correo',
                      ),
                      _empresaInfoChip(
                        Icons.person_outline,
                        empresa.representante,
                        'Sin representante',
                      ),
                      _empresaNotificationChip(empresa),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: () => _dialogEmpresaPerfil(empresa),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text(
                'Editar',
                style: TextStyle(
                  fontFamily: kArial,
                  fontWeight: FontWeight.w900,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: kAdminPrimary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _empresaInfoChip(IconData icon, String value, String fallback) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: kAdminBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: kAdminBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: kAdminMuted),
          const SizedBox(width: 6),
          Text(
            value.trim().isEmpty ? fallback : value.trim(),
            style: const TextStyle(
              fontFamily: kArial,
              fontSize: 12,
              color: kAdminMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _empresaNotificationChip(EmpresaItem empresa) {
    final colorHex =
        kNotificationCompanyColors.containsKey(
          empresa.notificacionColor.toUpperCase(),
        )
        ? empresa.notificacionColor.toUpperCase()
        : '#2563EB';
    final color = kNotificationCompanyColors[colorHex]!;
    final shortName = empresa.notificacionNombreCorto.trim().isEmpty
        ? empresa.nombre
        : empresa.notificacionNombreCorto.trim();
    final emoji = empresa.notificacionEmoji.trim();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            [emoji, shortName].where((item) => item.isNotEmpty).join(' '),
            style: TextStyle(
              fontFamily: kArial,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _empresaLogoBox(String logoUrl, {double size = 72, Uint8List? bytes}) {
    final hasBytes = bytes != null && bytes.isNotEmpty;
    final hasUrl = logoUrl.trim().isNotEmpty;
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: kAdminBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kAdminBorder),
      ),
      child: hasBytes
          ? Image.memory(bytes, fit: BoxFit.contain)
          : hasUrl
          ? Image.network(
              logoUrl,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) =>
                  const Icon(Icons.business, color: kAdminMuted),
            )
          : const Icon(Icons.business, color: kAdminMuted),
    );
  }

  Future<void> _dialogEmpresaPerfil(EmpresaItem empresa) async {
    String nombre = empresa.nombre;
    String nit = empresa.nit;
    String direccion = empresa.direccion;
    String telefono = empresa.telefono;
    String correo = empresa.correo;
    String representante = empresa.representante;
    String notificacionNombreCorto = empresa.notificacionNombreCorto.trim();
    String notificacionEmoji = empresa.notificacionEmoji.trim();
    String notificacionColor =
        kNotificationCompanyColors.containsKey(
          empresa.notificacionColor.toUpperCase(),
        )
        ? empresa.notificacionColor.toUpperCase()
        : '#2563EB';
    Uint8List? logoBytes;
    String? logoFileName;
    String? logoContentType;

    await showDialog(
      context: context,
      builder: (_) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: const Text(
                'Editar empresa',
                style: TextStyle(
                  fontFamily: kArial,
                  fontWeight: FontWeight.w900,
                  color: kAdminPrimary,
                ),
              ),
              content: SizedBox(
                width: 620,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _empresaLogoBox(
                            empresa.logoUrl,
                            size: 92,
                            bytes: logoBytes,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () async {
                                    final picked = await FilePicker.platform
                                        .pickFiles(
                                          type: FileType.custom,
                                          allowedExtensions: const [
                                            'png',
                                            'jpg',
                                            'jpeg',
                                            'webp',
                                          ],
                                          withData: true,
                                        );
                                    if (picked == null ||
                                        picked.files.isEmpty) {
                                      return;
                                    }
                                    final file = picked.files.first;
                                    if (file.bytes == null ||
                                        file.bytes!.isEmpty) {
                                      _snack('No se pudo leer el logo.');
                                      return;
                                    }
                                    setLocal(() {
                                      logoBytes = file.bytes;
                                      logoFileName = file.name;
                                      logoContentType = _imageContentType(
                                        file.extension,
                                      );
                                    });
                                  },
                                  icon: const Icon(Icons.upload_file),
                                  label: const Text(
                                    'Cargar logo',
                                    style: TextStyle(fontFamily: kArial),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  logoFileName ?? 'PNG, JPG o WEBP',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontFamily: kArial,
                                    fontSize: 12,
                                    color: kAdminMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        initialValue: nombre,
                        decoration: const InputDecoration(
                          labelText: 'Nombre / razón social',
                          border: OutlineInputBorder(),
                        ),
                        style: const TextStyle(fontFamily: kArial),
                        onChanged: (v) => nombre = v.trim(),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              initialValue: nit,
                              decoration: const InputDecoration(
                                labelText: 'NIT',
                                border: OutlineInputBorder(),
                              ),
                              style: const TextStyle(fontFamily: kArial),
                              onChanged: (v) => nit = v.trim(),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              initialValue: telefono,
                              decoration: const InputDecoration(
                                labelText: 'Teléfono',
                                border: OutlineInputBorder(),
                              ),
                              style: const TextStyle(fontFamily: kArial),
                              onChanged: (v) => telefono = v.trim(),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        initialValue: direccion,
                        decoration: const InputDecoration(
                          labelText: 'Dirección',
                          border: OutlineInputBorder(),
                        ),
                        style: const TextStyle(fontFamily: kArial),
                        onChanged: (v) => direccion = v.trim(),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        initialValue: correo,
                        decoration: const InputDecoration(
                          labelText: 'Correo corporativo',
                          border: OutlineInputBorder(),
                        ),
                        style: const TextStyle(fontFamily: kArial),
                        onChanged: (v) => correo = v.trim(),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        initialValue: representante,
                        decoration: const InputDecoration(
                          labelText: 'Representante legal',
                          border: OutlineInputBorder(),
                        ),
                        style: const TextStyle(fontFamily: kArial),
                        onChanged: (v) => representante = v.trim(),
                      ),
                      const SizedBox(height: 18),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Identidad general de mensajes',
                          style: TextStyle(
                            fontFamily: kArial,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: kAdminPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'El emoji identificará todos los mensajes de WhatsApp, '
                          'sin mostrar el nombre de la empresa. El nombre corto '
                          'y el color se conservarán solo para alertas internas. '
                          'Este mismo emoji aparece en Admin > WhatsApp.',
                          style: TextStyle(
                            fontFamily: kArial,
                            fontSize: 12,
                            color: kAdminMuted,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextFormField(
                              initialValue: notificacionNombreCorto,
                              decoration: const InputDecoration(
                                labelText: 'Nombre corto para alertas internas',
                                hintText: 'Ej. Capital USPEC',
                                border: OutlineInputBorder(),
                              ),
                              style: const TextStyle(fontFamily: kArial),
                              onChanged: (value) => setLocal(
                                () => notificacionNombreCorto = value.trim(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              initialValue: notificacionEmoji,
                              decoration: const InputDecoration(
                                labelText: 'Emoji',
                                hintText: '🏢',
                                border: OutlineInputBorder(),
                              ),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontFamily: kArial,
                                fontSize: 22,
                              ),
                              onChanged: (value) => setLocal(
                                () => notificacionEmoji = value.trim(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: kNotificationCompanyColors.entries.map((
                            entry,
                          ) {
                            final selected = entry.key == notificacionColor;
                            return Tooltip(
                              message: entry.key,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(24),
                                onTap: () => setLocal(
                                  () => notificacionColor = entry.key,
                                ),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 160),
                                  width: 38,
                                  height: 38,
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: selected
                                          ? kAdminPrimary
                                          : Colors.transparent,
                                      width: 2,
                                    ),
                                  ),
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: entry.value,
                                      shape: BoxShape.circle,
                                    ),
                                    child: selected
                                        ? const Icon(
                                            Icons.check,
                                            color: Colors.white,
                                            size: 18,
                                          )
                                        : null,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: kNotificationCompanyColors[notificacionColor]!
                              .withValues(alpha: 0.09),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color:
                                kNotificationCompanyColors[notificacionColor]!
                                    .withValues(alpha: 0.35),
                          ),
                        ),
                        child: Text(
                          notificacionEmoji.isEmpty
                              ? 'Mensaje de WhatsApp · sin emoji'
                              : '$notificacionEmoji Mensaje de WhatsApp',
                          style: TextStyle(
                            fontFamily: kArial,
                            fontWeight: FontWeight.w800,
                            color:
                                kNotificationCompanyColors[notificacionColor],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text(
                    'Cancelar',
                    style: TextStyle(fontFamily: kArial),
                  ),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.save),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kAdminPrimary,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    if (nombre.trim().isEmpty) {
                      _snack('El nombre de la empresa es obligatorio');
                      return;
                    }
                    await _repo.updateEmpresaPerfil(
                      empresaId: empresa.empresaId,
                      nombre: nombre,
                      nit: nit,
                      direccion: direccion,
                      telefono: telefono,
                      correo: correo,
                      representante: representante,
                      notificacionNombreCorto: notificacionNombreCorto,
                      notificacionEmoji: notificacionEmoji,
                      notificacionColor: notificacionColor,
                      logoBytes: logoBytes,
                      logoFileName: logoFileName,
                      logoContentType: logoContentType,
                    );
                    CompanyBrandingService.clearLogoCache(empresa.empresaId);
                    if (!mounted || !ctx.mounted) return;
                    Navigator.pop(ctx);
                    _snack('Empresa actualizada');
                    await _loadAll(forceEmpresaId: empresa.empresaId);
                  },
                  label: const Text(
                    'Guardar',
                    style: TextStyle(
                      fontFamily: kArial,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _imageContentType(String? extension) {
    switch ((extension ?? '').toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'webp':
        return 'image/webp';
      default:
        return 'image/png';
    }
  }

  Future<void> _dialogApp({
    QueryDocumentSnapshot<Map<String, dynamic>>? existing,
  }) async {
    final empresaId = _empresaId ?? '';
    if (empresaId.isEmpty) return;

    final data = existing?.data() ?? <String, dynamic>{};
    final existingAppId = _safe(data['appId']).isNotEmpty
        ? _safe(data['appId'])
        : existing?.id ?? '';
    String appId = existingAppId;
    String nombre = _safe(data['nombre']);
    String descripcion = _safe(data['descripcion']);
    bool enabled = (data['enabled'] as bool?) ?? true;
    final isNew = existing == null;

    await showDialog(
      context: context,
      builder: (_) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: Text(
                isNew ? 'Agregar app' : 'Editar app',
                style: const TextStyle(
                  fontFamily: kArial,
                  fontWeight: FontWeight.w900,
                  color: kAdminPrimary,
                ),
              ),
              content: SizedBox(
                width: 560,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      initialValue: appId,
                      readOnly: !isNew,
                      decoration: const InputDecoration(
                        labelText: 'appId (Ej: NutricionDashboard)',
                        border: OutlineInputBorder(),
                      ),
                      style: const TextStyle(fontFamily: kArial),
                      onChanged: (v) => appId = v.trim(),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      initialValue: nombre,
                      decoration: const InputDecoration(
                        labelText: 'Nombre visible',
                        border: OutlineInputBorder(),
                      ),
                      style: const TextStyle(fontFamily: kArial),
                      onChanged: (v) => nombre = v.trim(),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      initialValue: descripcion,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Descripción',
                        border: OutlineInputBorder(),
                      ),
                      style: const TextStyle(fontFamily: kArial),
                      onChanged: (v) => descripcion = v.trim(),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      value: enabled,
                      activeThumbColor: kAdminAccent,
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Habilitada',
                        style: TextStyle(fontFamily: kArial),
                      ),
                      onChanged: (v) => setLocal(() => enabled = v),
                    ),
                    if (isNew)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          'Se guardará con docId: empresaId_appId',
                          style: TextStyle(
                            fontFamily: kArial,
                            fontSize: 11,
                            color: Colors.black54,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text(
                    'Cancelar',
                    style: TextStyle(fontFamily: kArial),
                  ),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.save),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kAdminPrimary,
                  ),
                  onPressed: () async {
                    if (appId.trim().isEmpty || nombre.trim().isEmpty) {
                      _snack('appId y nombre son obligatorios');
                      return;
                    }
                    await _repo.upsertApp(
                      empresaId: empresaId,
                      appId: appId.trim(),
                      nombre: nombre.trim(),
                      descripcion: descripcion.trim().isEmpty
                          ? null
                          : descripcion.trim(),
                      enabled: enabled,
                      isNew: isNew,
                    );
                    if (!mounted || !ctx.mounted) return;
                    Navigator.pop(ctx);
                    _snack(isNew ? 'App creada' : 'App actualizada');
                    await _loadAll(forceEmpresaId: _empresaId);
                  },
                  label: const Text(
                    'Guardar',
                    style: TextStyle(
                      fontFamily: kArial,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _sectionHeader({
    required String title,
    required String subtitle,
    required VoidCallback onAdd,
  }) {
    return Row(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontFamily: kArial,
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
            Text(
              subtitle,
              style: const TextStyle(
                fontFamily: kArial,
                fontSize: 11,
                color: kAdminMuted,
              ),
            ),
          ],
        ),
        const Spacer(),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: kAdminPrimary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onPressed: onAdd,
          icon: const Icon(Icons.add, size: 18),
          label: const Text(
            'Agregar',
            style: TextStyle(
              fontFamily: kArial,
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }

  Widget _catalogTile({
    required String title,
    required String subtitle,
    required bool enabled,
    required VoidCallback onEdit,
    required ValueChanged<bool> onToggle,
    Widget? trailing2,
  }) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: enabled ? kAdminBorder : kAdminError.withValues(alpha: 0.2),
        ),
      ),
      color: enabled ? Colors.white : kAdminError.withValues(alpha: 0.02),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: (enabled ? kAdminAccent : kAdminMuted).withValues(
                  alpha: 0.1,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                enabled ? Icons.check_circle_outline : Icons.block_flipped,
                color: enabled ? kAdminAccent : kAdminMuted,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontFamily: kArial,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _statusBadge(enabled),
                    ],
                  ),
                  if (subtitle.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontFamily: kArial,
                        fontSize: 12,
                        color: kAdminMuted,
                      ),
                    ),
                  ],
                  if (trailing2 != null) ...[
                    const SizedBox(height: 6),
                    trailing2,
                  ],
                ],
              ),
            ),
            Switch(
              value: enabled,
              activeThumbColor: kAdminSuccess,
              inactiveThumbColor: kAdminMuted,
              onChanged: onToggle,
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.edit_outlined, color: kAdminPrimary),
              onPressed: onEdit,
              style: IconButton.styleFrom(
                backgroundColor: kAdminBg,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusBadge(bool enabled) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: (enabled ? kAdminSuccess : kAdminError).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: (enabled ? kAdminSuccess : kAdminError).withValues(alpha: 0.2),
        ),
      ),
      child: Text(
        enabled ? 'ACTIVO' : 'INACTIVO',
        style: TextStyle(
          fontFamily: kArial,
          fontSize: 9,
          fontWeight: FontWeight.w900,
          color: enabled ? kAdminSuccess : kAdminError,
        ),
      ),
    );
  }

  // ---------------- TAB: MIGRACIONES (solo usuarios seleccionados) ----------------
  Widget _tabMigraciones() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          color: kAdminCard,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Migraciones por usuario (no global)',
                  style: TextStyle(
                    fontFamily: kArial,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    color: kAdminPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Primero selecciona usuarios. Luego puedes simular o ejecutar.',
                  style: TextStyle(
                    fontFamily: kArial,
                    fontSize: 12,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickMigrationUsers,
                        icon: const Icon(Icons.people_alt),
                        label: Text(
                          _selectedMigrationUsers.isEmpty
                              ? 'Seleccionar usuarios'
                              : 'Usuarios seleccionados: ${_selectedMigrationUsers.length}',
                          style: const TextStyle(
                            fontFamily: kArial,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (_selectedMigrationUsers.isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: () =>
                            setState(() => _selectedMigrationUsers.clear()),
                        icon: const Icon(Icons.clear),
                        label: const Text(
                          'Limpiar',
                          style: TextStyle(fontFamily: kArial),
                        ),
                      ),
                  ],
                ),

                if (_selectedMigrationUsers.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: _selectedMigrationUsers
                        .take(12)
                        .map(
                          (id) => Chip(
                            backgroundColor: const Color(0xFFE8FBFF),
                            label: Text(
                              id,
                              style: const TextStyle(
                                fontFamily: kArial,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  if (_selectedMigrationUsers.length > 12)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'y ${_selectedMigrationUsers.length - 12} más...',
                        style: const TextStyle(
                          fontFamily: kArial,
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        Card(
          color: kAdminCard,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Centro de costos → SOLO usuarios seleccionados',
                  style: TextStyle(
                    fontFamily: kArial,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            _runNormalizeCentroSelectedUsers(dryRun: true),
                        icon: const Icon(Icons.visibility),
                        label: const Text(
                          'Simular',
                          style: TextStyle(fontFamily: kArial),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kAdminPrimary,
                        ),
                        onPressed: () =>
                            _runNormalizeCentroSelectedUsers(dryRun: false),
                        icon: const Icon(Icons.play_arrow),
                        label: const Text(
                          'Ejecutar',
                          style: TextStyle(
                            fontFamily: kArial,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        Card(
          color: kAdminCard,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Tokens (fcmToken) → SOLO usuarios seleccionados',
                  style: TextStyle(
                    fontFamily: kArial,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            _runNormalizeTokensSelectedUsers(dryRun: true),
                        icon: const Icon(Icons.visibility),
                        label: const Text(
                          'Simular',
                          style: TextStyle(fontFamily: kArial),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kAdminPrimary,
                        ),
                        onPressed: () =>
                            _runNormalizeTokensSelectedUsers(dryRun: false),
                        icon: const Icon(Icons.play_arrow),
                        label: const Text(
                          'Ejecutar',
                          style: TextStyle(
                            fontFamily: kArial,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        Card(
          color: kAdminCard,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'App IDs (formato canónico) → SOLO usuarios seleccionados',
                  style: TextStyle(
                    fontFamily: kArial,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Convierte IDs cortos (compras, admin…) a IDs completos (comprasdashboard, admindashboard…).',
                  style: TextStyle(
                    fontFamily: kArial,
                    fontSize: 12,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            _runNormalizeAppIdsSelectedUsers(dryRun: true),
                        icon: const Icon(Icons.visibility),
                        label: const Text(
                          'Simular',
                          style: TextStyle(fontFamily: kArial),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kAdminPrimary,
                        ),
                        onPressed: () =>
                            _runNormalizeAppIdsSelectedUsers(dryRun: false),
                        icon: const Icon(Icons.play_arrow),
                        label: const Text(
                          'Ejecutar',
                          style: TextStyle(
                            fontFamily: kArial,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        Card(
          color: kAdminCard,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Eliminar todas las tareas (empresa activa)',
                  style: TextStyle(
                    fontFamily: kArial,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Útil para reiniciar el entorno en periodo de prueba.',
                  style: TextStyle(
                    fontFamily: kArial,
                    fontSize: 12,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade700,
                    ),
                    onPressed: _deleteAllTasksForEmpresa,
                    icon: const Icon(Icons.delete_forever),
                    label: const Text(
                      'Eliminar todas las tareas',
                      style: TextStyle(
                        fontFamily: kArial,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ---------------- TAB: LOGS ----------------
  Widget _tabLogs() {
    return FutureBuilder(
      future: _loadLogs(),
      builder:
          (
            context,
            AsyncSnapshot<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
            snap,
          ) {
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final docs = snap.data ?? [];
            if (docs.isEmpty) {
              return const Center(
                child: Text('Sin logs', style: TextStyle(fontFamily: kArial)),
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: docs.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final d = docs[i].data();
                final action = (d['action'] ?? '').toString();
                final scanned = (d['scanned'] ?? 0).toString();
                final updated = (d['updated'] ?? 0).toString();
                final dryRun = (d['dryRun'] as bool?) ?? false;

                return Card(
                  color: kAdminCard,
                  child: ListTile(
                    leading: const Icon(Icons.bolt, color: kAdminAccent),
                    title: Text(
                      action,
                      style: const TextStyle(
                        fontFamily: kArial,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    subtitle: Text(
                      'Scanned: $scanned • Updated: $updated • ${dryRun ? "SIMULACIÓN" : "EJECUTADO"}',
                      style: const TextStyle(fontFamily: kArial),
                    ),
                  ),
                );
              },
            );
          },
    );
  }

  Widget _tabSesionesUsuarios() {
    final empresaId = _empresaId ?? '';
    if (empresaId.isEmpty) {
      return const Center(
        child: Text(
          'Selecciona una empresa',
          style: TextStyle(fontFamily: kArial),
        ),
      );
    }

    return StreamBuilder<List<LoginSessionDoc>>(
      stream: SessionAuditService().streamEmpresaSessions(empresaId),
      builder: (context, snap) {
        final sessions = snap.data ?? const <LoginSessionDoc>[];
        final latestByUser = _latestSessionByUser(sessions);
        final query = _sessionSearch.trim().toLowerCase();
        final users = _users.where((doc) {
          if (query.isEmpty) return true;
          final data = doc.data();
          final nombre = _userName(data, doc.id).toLowerCase();
          final cedula = _safe(data['cedula']).toLowerCase();
          final cargo = _userCargoText(data, empresaId).toLowerCase();
          return nombre.contains(query) ||
              cedula.contains(query) ||
              doc.id.toLowerCase().contains(query) ||
              cargo.contains(query);
        }).toList();
        final loggedUsers = _users
            .where((userDoc) => _latestForUser(userDoc, latestByUser) != null)
            .length;
        final neverLogged = _users.length - loggedUsers;
        final todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
        final todayCount = sessions
            .where(
              (s) =>
                  DateFormat('yyyy-MM-dd').format(s.loginAt.toDate()) ==
                  todayKey,
            )
            .length;
        final isMobile = MediaQuery.of(context).size.width < 760;

        return Padding(
          padding: EdgeInsets.all(isMobile ? 12 : 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    'Control de inicios de sesión',
                    style: TextStyle(
                      fontFamily: kArial,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Chip(
                    avatar: const Icon(Icons.people_alt, size: 18),
                    label: Text('${_users.length} usuarios'),
                  ),
                  Chip(
                    avatar: const Icon(Icons.login_rounded, size: 18),
                    label: Text('$todayCount ingresos hoy'),
                  ),
                  Chip(
                    avatar: const Icon(Icons.verified_user, size: 18),
                    label: Text('$loggedUsers con registro'),
                  ),
                  Chip(
                    avatar: const Icon(Icons.person_off, size: 18),
                    label: Text('$neverLogged sin ingreso registrado'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Buscar por nombre, cédula o cargo',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) => setState(() => _sessionSearch = value),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: snap.hasError
                    ? Center(child: Text('Error: ${snap.error}'))
                    : !snap.hasData
                    ? const Center(child: CircularProgressIndicator())
                    : isMobile
                    ? _sessionUsersCards(users, latestByUser)
                    : Row(
                        children: [
                          Expanded(
                            flex: 7,
                            child: _sessionUsersTable(users, latestByUser),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 380,
                            child: _recentSessionsPanel(sessions),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Map<String, LoginSessionDoc> _latestSessionByUser(
    List<LoginSessionDoc> sessions,
  ) {
    final out = <String, LoginSessionDoc>{};
    for (final session in sessions) {
      for (final key in [
        session.userId.trim(),
        session.cedula.trim(),
      ].where((v) => v.isNotEmpty)) {
        final current = out[key];
        if (current == null ||
            session.loginAt.toDate().isAfter(current.loginAt.toDate())) {
          out[key] = session;
        }
      }
    }
    return out;
  }

  LoginSessionDoc? _latestForUser(
    QueryDocumentSnapshot<Map<String, dynamic>> userDoc,
    Map<String, LoginSessionDoc> latestByUser,
  ) {
    final cedula = _safe(userDoc.data()['cedula']);
    return latestByUser[userDoc.id] ?? latestByUser[cedula];
  }

  Widget _sessionUsersTable(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> users,
    Map<String, LoginSessionDoc> latestByUser,
  ) {
    if (users.isEmpty) {
      return const Center(child: Text('No se encontraron usuarios.'));
    }
    final empresaId = _empresaId ?? '';
    return Card(
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: PagedDataTable(
            etiqueta: 'registros',
            tabla: DataTable(
              headingRowColor: WidgetStateProperty.all(kAdminBg),
              columns: const [
                DataColumn(label: Text('Usuario')),
                DataColumn(label: Text('Cargo')),
                DataColumn(label: Text('Último ingreso')),
                DataColumn(label: Text('Plataforma')),
                DataColumn(label: Text('Tipo')),
              ],
              rows: [
                for (final userDoc in users)
                  _sessionUserRow(userDoc, latestByUser, empresaId),
              ],
            ),
          ),
        ),
      ),
    );
  }

  DataRow _sessionUserRow(
    QueryDocumentSnapshot<Map<String, dynamic>> userDoc,
    Map<String, LoginSessionDoc> latestByUser,
    String empresaId,
  ) {
    final data = userDoc.data();
    final nombre = _userName(data, userDoc.id);
    final cedula = _safe(data['cedula']).isEmpty
        ? userDoc.id
        : _safe(data['cedula']);
    final latest = _latestForUser(userDoc, latestByUser);
    return DataRow(
      cells: [
        DataCell(
          SizedBox(
            width: 260,
            child: Row(
              children: [
                UserAvatar(userId: userDoc.id, nameHint: nombre, radius: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nombre,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        cedula,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: kAdminMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        DataCell(
          SizedBox(
            width: 210,
            child: Text(
              _userCargoText(data, empresaId),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        DataCell(
          Text(latest == null ? 'Sin registro' : _fmtLoginAt(latest.loginAt)),
        ),
        DataCell(Text(latest?.platform ?? '-')),
        DataCell(Text(latest == null ? '-' : _sourceLabel(latest.source))),
      ],
    );
  }

  Widget _sessionUsersCards(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> users,
    Map<String, LoginSessionDoc> latestByUser,
  ) {
    if (users.isEmpty) {
      return const Center(child: Text('No se encontraron usuarios.'));
    }
    final empresaId = _empresaId ?? '';
    return ListView.separated(
      itemCount: users.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final doc = users[i];
        final data = doc.data();
        final nombre = _userName(data, doc.id);
        final cedula = _safe(data['cedula']).isEmpty
            ? doc.id
            : _safe(data['cedula']);
        final latest = _latestForUser(doc, latestByUser);
        return Card(
          child: ListTile(
            leading: UserAvatar(userId: doc.id, nameHint: nombre),
            title: Text(nombre, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              '$cedula\n'
              '${_userCargoText(data, empresaId)}\n'
              'Último ingreso: ${latest == null ? 'Sin registro' : _fmtLoginAt(latest.loginAt)}',
            ),
            isThreeLine: true,
            trailing: latest == null
                ? const Icon(Icons.person_off_outlined, color: kAdminMuted)
                : const Icon(Icons.check_circle, color: kAdminSuccess),
          ),
        );
      },
    );
  }

  Widget _recentSessionsPanel(List<LoginSessionDoc> sessions) {
    final recent = sessions.take(40).toList();
    return Card(
      child: Column(
        children: [
          const ListTile(
            leading: Icon(Icons.history, color: kAdminAccent),
            title: Text(
              'Historial reciente',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            subtitle: Text('Últimos ingresos registrados'),
          ),
          const Divider(height: 1),
          Expanded(
            child: recent.isEmpty
                ? const Center(child: Text('Sin ingresos registrados.'))
                : ListView.separated(
                    itemCount: recent.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final s = recent[i];
                      return ListTile(
                        dense: true,
                        leading: UserAvatar(
                          userId: s.userId,
                          nameHint: s.nombre,
                          radius: 16,
                        ),
                        title: Text(
                          s.nombre.isEmpty ? s.userId : s.nombre,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${_fmtLoginAt(s.loginAt)} · ${s.platform} · ${_sourceLabel(s.source)}',
                          maxLines: 2,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String _fmtLoginAt(Timestamp ts) =>
      DateFormat('dd/MM/yyyy HH:mm').format(ts.toDate());

  String _sourceLabel(String source) {
    switch (source) {
      case 'password':
        return 'Contraseña';
      case 'biometria':
        return 'Biometría';
      case 'sesion_guardada':
        return 'Sesión guardada';
      default:
        return source.isEmpty ? '-' : source;
    }
  }

  // ======= Dialogs Catálogos (reutiliza los de tu versión anterior) =======
  Future<void> _dialogCentro({CentroCostoItem? existing}) async {
    final empresaId = _empresaId ?? '';
    if (empresaId.isEmpty) return;

    final idCtrl = TextEditingController(text: existing?.centroId ?? '');
    final codCtrl = TextEditingController(text: existing?.codigo ?? '');
    final nomCtrl = TextEditingController(text: existing?.nombre ?? '');
    bool enabled = existing?.enabled ?? true;

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          existing == null ? 'Nuevo centro' : 'Editar centro',
          style: const TextStyle(
            fontFamily: kArial,
            fontWeight: FontWeight.w900,
          ),
        ),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: idCtrl,
                enabled: existing == null,
                decoration: const InputDecoration(
                  labelText: 'centroId (docId)',
                  border: OutlineInputBorder(),
                ),
                style: const TextStyle(fontFamily: kArial),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: codCtrl,
                decoration: const InputDecoration(
                  labelText: 'Código interno (opcional)',
                  border: OutlineInputBorder(),
                ),
                style: const TextStyle(fontFamily: kArial),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: nomCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nombre',
                  border: OutlineInputBorder(),
                ),
                style: const TextStyle(fontFamily: kArial),
              ),
              const SizedBox(height: 10),
              SwitchListTile(
                value: enabled,
                activeThumbColor: kAdminAccent,
                onChanged: (v) => setState(() => enabled = v),
                title: const Text(
                  'Habilitado',
                  style: TextStyle(fontFamily: kArial),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar', style: TextStyle(fontFamily: kArial)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kAdminPrimary),
            onPressed: () async {
              final centroId = idCtrl.text.trim();
              final codigo = codCtrl.text.trim();
              final nombre = nomCtrl.text.trim();

              if (centroId.isEmpty || nombre.isEmpty) {
                _snack('Completa centroId y nombre');
                return;
              }

              await _repo.upsertCentro(
                empresaId: empresaId,
                centroId: centroId,
                codigo: codigo.isEmpty ? centroId : codigo,
                nombre: nombre,
                enabled: enabled,
              );
              if (!mounted) return;
              Navigator.pop(context);
              _snack('Centro guardado');
              await _loadAll(forceEmpresaId: _empresaId);
            },
            child: const Text(
              'Guardar',
              style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _dialogArea({AreaItem? existing}) async {
    final empresaId = _empresaId ?? '';
    if (empresaId.isEmpty) return;

    final idCtrl = TextEditingController(text: existing?.areaId ?? '');
    final nomCtrl = TextEditingController(text: existing?.nombre ?? '');
    bool enabled = existing?.enabled ?? true;

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          existing == null ? 'Nueva área' : 'Editar área',
          style: const TextStyle(
            fontFamily: kArial,
            fontWeight: FontWeight.w900,
          ),
        ),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: idCtrl,
                enabled: existing == null,
                decoration: const InputDecoration(
                  labelText: 'areaId (docId)',
                  border: OutlineInputBorder(),
                ),
                style: const TextStyle(fontFamily: kArial),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: nomCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nombre',
                  border: OutlineInputBorder(),
                ),
                style: const TextStyle(fontFamily: kArial),
              ),
              const SizedBox(height: 10),
              SwitchListTile(
                value: enabled,
                activeThumbColor: kAdminAccent,
                onChanged: (v) => setState(() => enabled = v),
                title: const Text(
                  'Habilitado',
                  style: TextStyle(fontFamily: kArial),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar', style: TextStyle(fontFamily: kArial)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kAdminPrimary),
            onPressed: () async {
              final areaId = idCtrl.text.trim();
              final nombre = nomCtrl.text.trim();
              if (areaId.isEmpty || nombre.isEmpty) {
                _snack('Completa areaId y nombre');
                return;
              }
              await _repo.upsertArea(
                empresaId: empresaId,
                areaId: areaId,
                nombre: nombre,
                enabled: enabled,
              );
              if (!mounted) return;
              Navigator.pop(context);
              _snack('Área guardada');
              await _loadAll(forceEmpresaId: _empresaId);
            },
            child: const Text(
              'Guardar',
              style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _dialogCargo({CargoItem? existing}) async {
    final empresaId = _empresaId ?? '';
    if (empresaId.isEmpty) return;

    final idCtrl = TextEditingController(text: existing?.cargoId ?? '');
    final nomCtrl = TextEditingController(text: existing?.nombre ?? '');
    bool enabled = existing?.enabled ?? true;

    CentroCostoItem? centroSel = existing?.centroId == null
        ? null
        : _centros
              .where((c) => c.centroId == existing!.centroId)
              .cast<CentroCostoItem?>()
              .firstWhere((x) => x != null, orElse: () => null);
    AreaItem? areaSel = existing?.areaId == null
        ? null
        : _areas
              .where((a) => a.areaId == existing!.areaId)
              .cast<AreaItem?>()
              .firstWhere((x) => x != null, orElse: () => null);

    final centrosEnabled = _centros.where((c) => c.enabled).toList();
    final areasEnabled = _areas.where((a) => a.enabled).toList();

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          existing == null ? 'Nuevo cargo' : 'Editar cargo',
          style: const TextStyle(
            fontFamily: kArial,
            fontWeight: FontWeight.w900,
          ),
        ),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: idCtrl,
                enabled: existing == null,
                decoration: const InputDecoration(
                  labelText: 'cargoId (docId)',
                  border: OutlineInputBorder(),
                ),
                style: const TextStyle(fontFamily: kArial),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: nomCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nombre',
                  border: OutlineInputBorder(),
                ),
                style: const TextStyle(fontFamily: kArial),
              ),
              const SizedBox(height: 10),

              DropdownButtonFormField<CentroCostoItem>(
                initialValue: centroSel,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Centro (opcional)',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<CentroCostoItem>(
                    value: null,
                    child: Text('—', style: TextStyle(fontFamily: kArial)),
                  ),
                  ...centrosEnabled.map(
                    (c) => DropdownMenuItem(
                      value: c,
                      child: Text(
                        c.nombre,
                        style: const TextStyle(fontFamily: kArial),
                      ),
                    ),
                  ),
                ],
                onChanged: (v) => centroSel = v,
              ),
              const SizedBox(height: 10),

              DropdownButtonFormField<AreaItem>(
                initialValue: areaSel,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Área (opcional)',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<AreaItem>(
                    value: null,
                    child: Text('—', style: TextStyle(fontFamily: kArial)),
                  ),
                  ...areasEnabled.map(
                    (a) => DropdownMenuItem(
                      value: a,
                      child: Text(
                        a.nombre,
                        style: const TextStyle(fontFamily: kArial),
                      ),
                    ),
                  ),
                ],
                onChanged: (v) => areaSel = v,
              ),

              const SizedBox(height: 10),
              SwitchListTile(
                value: enabled,
                activeThumbColor: kAdminAccent,
                onChanged: (v) => setState(() => enabled = v),
                title: const Text(
                  'Habilitado',
                  style: TextStyle(fontFamily: kArial),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar', style: TextStyle(fontFamily: kArial)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kAdminPrimary),
            onPressed: () async {
              final cargoId = idCtrl.text.trim();
              final nombre = nomCtrl.text.trim();
              if (cargoId.isEmpty || nombre.isEmpty) {
                _snack('Completa cargoId y nombre');
                return;
              }
              await _repo.upsertCargo(
                empresaId: empresaId,
                cargoId: cargoId,
                nombre: nombre,
                centroId: centroSel?.centroId,
                areaId: areaSel?.areaId,
                enabled: enabled,
              );
              if (!mounted) return;
              Navigator.pop(context);
              _snack('Cargo guardado');
              await _loadAll(forceEmpresaId: _empresaId);
            },
            child: const Text(
              'Guardar',
              style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  // ── Tab Roles Compras ─────────────────────────────────────────────────────

  // Respaldos internos: la asignación principal ahora vive en la matriz central.
  // ignore: unused_element
  Widget _tabRolesCompras() {
    final empresaId = _empresaId ?? '';
    if (empresaId.isEmpty) {
      return const Center(
        child: Text(
          'Selecciona una empresa',
          style: TextStyle(fontFamily: kArial),
        ),
      );
    }
    final svc = ComprasService();
    final roles = [
      kRolAdmin,
      kRolCalidad,
      kRolCompras,
      kRolBodega,
      kRolConsultas,
    ];
    final rolesLabels = {
      kRolAdmin: 'Admin Documental',
      kRolCalidad: 'Director de Calidad',
      kRolCompras: 'Compras',
      kRolBodega: 'Bodega',
      kRolConsultas: 'Consultas',
    };
    final rolesIcons = {
      kRolAdmin: Icons.admin_panel_settings,
      kRolCalidad: Icons.verified_user,
      kRolCompras: Icons.shopping_cart,
      kRolBodega: Icons.warehouse,
      kRolConsultas: Icons.search,
    };
    final rolesColors = {
      kRolAdmin: const Color(0xFF7B1FA2),
      kRolCalidad: Colors.green.shade700,
      kRolCompras: kAdminPrimary,
      kRolBodega: Colors.blue.shade700,
      kRolConsultas: const Color(0xFF283593),
    };

    return StreamBuilder<List<ComprasRolDoc>>(
      stream: svc.streamComprasRoles(empresaId),
      builder: (ctx, snapRoles) {
        final rolesActuales = snapRoles.data ?? [];
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Card(
              color: kAdminCard,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.verified_user, color: kAdminPrimary),
                        SizedBox(width: 8),
                        Text(
                          'Roles en Compras & Bodega',
                          style: TextStyle(
                            fontFamily: kArial,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Asigna a cada usuario su rol en el módulo de Compras. '
                      'Admin Documental: acceso total + puede eliminar recepciones, fichas y marcas. '
                      'Director de Calidad: revisa, aprueba o rechaza documentos. Compras: gestiona proveedores/productos. '
                      'Bodega: recepción de mercancía + consultas. '
                      'Consultas: solo lectura de la pestaña de consultas.',
                      style: TextStyle(
                        fontFamily: kArial,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Roles actuales
            if (rolesActuales.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  'Roles asignados',
                  style: TextStyle(
                    fontFamily: kArial,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              ...rolesActuales.map(
                (r) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: UserAvatar(
                      userId: r.cedula,
                      nameHint: r.nombre,
                      backgroundColor: (rolesColors[r.rol] ?? kAdminPrimary)
                          .withValues(alpha: 0.15),
                      foregroundColor: rolesColors[r.rol] ?? kAdminPrimary,
                    ),
                    title: UserNameText(
                      r.cedula,
                      fallbackName: r.nombre,
                      style: const TextStyle(
                        fontFamily: kArial,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      '${rolesLabels[r.rol] ?? r.rol} · ${r.cedula}',
                      style: const TextStyle(fontFamily: kArial, fontSize: 12),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      tooltip: 'Quitar rol',
                      onPressed: () async {
                        final ok = await _confirm(
                          title: 'Quitar rol',
                          message:
                              '¿Quitar el rol de ${rolesLabels[r.rol]} a ${r.nombre}?',
                          confirmText: 'Quitar',
                        );
                        if (ok) {
                          await svc.eliminarComprasRol(r.id);
                          _snack('Rol eliminado');
                        }
                      },
                    ),
                  ),
                ),
              ),
              const Divider(height: 24),
            ],
            // Barra de filtros
            _buildPersonnelFilterBar(
              searchHint: 'Nombre, cédula, cargo, área…',
              searchValue: _comprasRolesSearch,
              onSearchChanged: (v) =>
                  setState(() => _comprasRolesSearch = v.trim().toLowerCase()),
              selectedAreaId: _comprasRolesAreaFilter,
              onAreaChanged: (v) => setState(() => _comprasRolesAreaFilter = v),
            ),
            // Asignar nuevo rol
            const Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: Text(
                'Asignar rol a usuario',
                style: TextStyle(
                  fontFamily: kArial,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
            ..._applyPersonnelFilter(
              _users,
              search: _comprasRolesSearch,
              areaId: _comprasRolesAreaFilter,
            ).map((userDoc) {
              final data = userDoc.data();
              final nombre = _userName(data, userDoc.id);
              final cedula = _safe(data['cedula']);
              final userId = userDoc.id;
              // Rol actual del usuario
              ComprasRolDoc? rolActual;
              try {
                rolActual = rolesActuales.firstWhere(
                  (r) => r.userId == userId || r.cedula == cedula,
                );
              } catch (_) {}

              return Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              nombre,
                              style: const TextStyle(
                                fontFamily: kArial,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              cedula,
                              style: const TextStyle(
                                fontFamily: kArial,
                                fontSize: 11,
                                color: Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      DropdownButton<String>(
                        value: rolActual?.rol,
                        hint: const Text(
                          'Sin rol',
                          style: TextStyle(fontFamily: kArial, fontSize: 12),
                        ),
                        items: [
                          const DropdownMenuItem<String>(
                            value: null,
                            child: Text(
                              'Sin rol',
                              style: TextStyle(
                                fontFamily: kArial,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          ...roles.map(
                            (r) => DropdownMenuItem<String>(
                              value: r,
                              child: Row(
                                children: [
                                  Icon(
                                    rolesIcons[r],
                                    size: 14,
                                    color: rolesColors[r],
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    rolesLabels[r] ?? r,
                                    style: const TextStyle(
                                      fontFamily: kArial,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                        onChanged: (nuevoRol) async {
                          try {
                            if (nuevoRol == null) {
                              // Quitar rol si existe
                              if (rolActual != null) {
                                await svc.eliminarComprasRol(rolActual.id);
                                _snack('Rol eliminado de $nombre');
                              }
                              return;
                            }
                            final doc = ComprasRolDoc(
                              id: rolActual?.id ?? '',
                              empresaId: empresaId,
                              userId: userId,
                              cedula: cedula,
                              nombre: nombre,
                              rol: nuevoRol,
                              createdAt: Timestamp.now(),
                            );
                            await svc.guardarComprasRol(
                              doc,
                              isNew: rolActual == null,
                            );
                            await _repo.grantUserApps(
                              userId: userId,
                              empresaId: empresaId,
                              appIds: const ['comprasdashboard'],
                            );
                            _snack(
                              'Rol ${rolesLabels[nuevoRol]} asignado a $nombre',
                            );
                          } catch (e) {
                            _snack('Error al guardar rol: $e');
                          }
                        },
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }

  // Respaldos internos: la asignación principal ahora vive en la matriz central.
  // ignore: unused_element
  Widget _tabRolesInterventoria() {
    final empresaId = _empresaId ?? '';
    if (empresaId.isEmpty) {
      return const Center(
        child: Text(
          'Selecciona una empresa',
          style: TextStyle(fontFamily: kArial),
        ),
      );
    }
    final svc = InterventoriaService();
    final rolesIcons = {
      kRolInterventoriaAdmin: Icons.admin_panel_settings,
      kRolInterventoriaRegistrador: Icons.edit_document,
      kRolInterventoriaRevisor: Icons.fact_check,
      kRolInterventoriaGerente: Icons.query_stats,
      kRolInterventoriaDirectivo: Icons.leaderboard,
      kRolInterventoriaConsulta: Icons.search,
    };
    final rolesColors = {
      kRolInterventoriaAdmin: const Color(0xFF7B1FA2),
      kRolInterventoriaRegistrador: const Color(0xFF0F766E),
      kRolInterventoriaRevisor: Colors.blue.shade700,
      kRolInterventoriaGerente: Colors.indigo.shade700,
      kRolInterventoriaDirectivo: Colors.orange.shade800,
      kRolInterventoriaConsulta: const Color(0xFF475569),
    };

    return StreamBuilder<List<InterventoriaRolDoc>>(
      stream: svc.streamRoles(empresaId),
      builder: (ctx, snapRoles) {
        final rolesActuales = snapRoles.data ?? [];
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Card(
              color: kAdminCard,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.document_scanner, color: kAdminPrimary),
                        SizedBox(width: 8),
                        Text(
                          'Roles en Interventoria',
                          style: TextStyle(
                            fontFamily: kArial,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Configura quien registra visitas, revisa OCR y accede al analisis directivo. '
                      'Los centros de costos se toman desde TBL_CENTROS_COSTOS y el modulo respeta empresa activa.',
                      style: TextStyle(
                        fontFamily: kArial,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () async {
                        await _repo.upsertApp(
                          empresaId: empresaId,
                          appId: kInterventoriaAppId,
                          nombre: 'Interventoria',
                          descripcion:
                              'Control de visitas, actas escaneadas, OCR editable e indicadores.',
                          enabled: true,
                          isNew: true,
                        );
                        await svc.asegurarConfigBase(empresaId);
                        _snack(
                          'Modulo Interventoria habilitado y configuracion base creada.',
                        );
                        await _loadAll(forceEmpresaId: empresaId);
                      },
                      icon: const Icon(Icons.add_circle_outline),
                      label: const Text('Habilitar modulo y config base'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            // ── Gap 1: Alerta centros con hallazgos activos >30 días ────────
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('TBL_INTERVENTORIA_HALLAZGOS')
                  .where('empresaId', isEqualTo: empresaId)
                  .where('estado', isEqualTo: 'activo')
                  .snapshots(),
              builder: (ctx, snapH) {
                if (!snapH.hasData) return const SizedBox.shrink();
                final ahora = DateTime.now();
                final limite30 = ahora.subtract(const Duration(days: 30));
                // Agrupar por centro
                final Map<String, int> centrosVencidos = {};
                for (final doc in snapH.data!.docs) {
                  final data = doc.data()! as Map<String, dynamic>;
                  final ts = data['fechaHallazgo'];
                  if (ts == null) continue;
                  final fecha = (ts as Timestamp).toDate();
                  if (fecha.isBefore(limite30)) {
                    final centro = (data['centroCostoNombre'] ?? 'Sin nombre')
                        .toString();
                    centrosVencidos[centro] =
                        (centrosVencidos[centro] ?? 0) + 1;
                  }
                }
                if (centrosVencidos.isEmpty) return const SizedBox.shrink();
                return Card(
                  color: const Color(0xFFFEF2F2),
                  margin: const EdgeInsets.only(bottom: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: const BorderSide(color: Color(0xFFFCA5A5)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.warning_amber_rounded,
                              color: Color(0xFFDC2626),
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${centrosVencidos.length} centro${centrosVencidos.length > 1 ? 's' : ''} con hallazgos activos > 30 días',
                              style: const TextStyle(
                                fontFamily: kArial,
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                color: Color(0xFFDC2626),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ...centrosVencidos.entries.map(
                          (e) => Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.circle,
                                  size: 6,
                                  color: Color(0xFFDC2626),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    '${e.key} — ${e.value} hallazgo${e.value > 1 ? 's' : ''} sin subsanar',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF7F1D1D),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            if (rolesActuales.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  'Roles asignados',
                  style: TextStyle(
                    fontFamily: kArial,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              ...rolesActuales.map(
                (r) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: UserAvatar(
                      userId: r.cedula,
                      nameHint: r.nombre,
                      backgroundColor: (rolesColors[r.rol] ?? kAdminPrimary)
                          .withValues(alpha: 0.15),
                      foregroundColor: rolesColors[r.rol] ?? kAdminPrimary,
                    ),
                    title: UserNameText(
                      r.cedula,
                      fallbackName: r.nombre,
                      style: const TextStyle(
                        fontFamily: kArial,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      '${kInterventoriaRoleLabels[r.rol] ?? r.rol} · ${r.cedula}',
                      style: const TextStyle(fontFamily: kArial, fontSize: 12),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      tooltip: 'Quitar rol',
                      onPressed: () async {
                        final ok = await _confirm(
                          title: 'Quitar rol',
                          message:
                              '¿Quitar el rol de ${kInterventoriaRoleLabels[r.rol] ?? r.rol} a ${r.nombre}?',
                          confirmText: 'Quitar',
                        );
                        if (ok) {
                          await svc.eliminarRol(r.id);
                          _snack('Rol eliminado');
                        }
                      },
                    ),
                  ),
                ),
              ),
              const Divider(height: 24),
            ],
            // ── Buscador y filtros ────────────────────────────────────────
            _buildPersonnelFilterBar(
              searchHint: 'Nombre, cédula, cargo, área…',
              searchValue: _rolesSearch,
              onSearchChanged: (v) =>
                  setState(() => _rolesSearch = v.trim().toLowerCase()),
              selectedAreaId: _rolesAreaFilter,
              onAreaChanged: (v) => setState(() => _rolesAreaFilter = v),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Wrap(
                spacing: 8,
                children: [
                  FilterChip(
                    label: const Text(
                      'Solo directivos / admins',
                      style: TextStyle(fontFamily: kArial, fontSize: 12),
                    ),
                    selected: _rolesSoloDirectivos,
                    onSelected: (v) => setState(() => _rolesSoloDirectivos = v),
                    avatar: const Icon(Icons.admin_panel_settings, size: 14),
                  ),
                  FilterChip(
                    label: Text(
                      'Sin rol asignado (${_users.where((u) {
                        final ced = _safe(u.data()['cedula']);
                        return !rolesActuales.any((r) => r.userId == u.id || r.cedula == ced);
                      }).length})',
                      style: const TextStyle(fontFamily: kArial, fontSize: 12),
                    ),
                    selected: false,
                    onSelected: null,
                    backgroundColor: Colors.orange.shade50,
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: Text(
                'Asignar rol a usuario',
                style: TextStyle(
                  fontFamily: kArial,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
            ...() {
              // Palabras clave de cargo directivo
              const kDirectivoCargos = [
                'director',
                'administrador',
                'coordinador',
                'gerente',
                'jefe',
                'supervisor',
                'subdirector',
              ];

              var filtered = _applyPersonnelFilter(
                _users,
                search: _rolesSearch,
                areaId: _rolesAreaFilter,
              );

              if (_rolesSoloDirectivos) {
                filtered = filtered.where((userDoc) {
                  final cargo = _safe(userDoc.data()['cargo']).toLowerCase();
                  return kDirectivoCargos.any((k) => cargo.contains(k));
                }).toList();
              }

              if (filtered.isEmpty) {
                return [
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        'No se encontraron usuarios con ese criterio',
                        style: TextStyle(
                          fontFamily: kArial,
                          color: Colors.black45,
                        ),
                      ),
                    ),
                  ),
                ];
              }

              return filtered.map((userDoc) {
                final data = userDoc.data();
                final nombre = _userName(data, userDoc.id);
                final cedula = _safe(data['cedula']);
                final cargo = _safe(data['cargo']);
                final userId = userDoc.id;
                InterventoriaRolDoc? rolActual;
                try {
                  rolActual = rolesActuales.firstWhere(
                    (r) => r.userId == userId || r.cedula == cedula,
                  );
                } catch (_) {}

                // Detectar si es directivo por cargo
                const kDirectivoCargos = [
                  'director',
                  'administrador',
                  'coordinador',
                  'gerente',
                  'jefe',
                  'supervisor',
                  'subdirector',
                ];
                final esDirectivo = kDirectivoCargos.any(
                  (k) => cargo.toLowerCase().contains(k),
                );

                return Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  color: esDirectivo ? const Color(0xFFF0FDF4) : null,
                  shape: esDirectivo
                      ? RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(
                            color: Colors.green.shade200,
                            width: 1,
                          ),
                        )
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        if (esDirectivo)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Icon(
                              Icons.star_rounded,
                              size: 14,
                              color: Colors.green.shade600,
                            ),
                          ),
                        UserAvatar(
                          userId: cedula,
                          nameHint: nombre,
                          radius: 14,
                          backgroundColor: kAdminPrimary.withValues(
                            alpha: 0.08,
                          ),
                          foregroundColor: kAdminPrimary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              UserNameText(
                                cedula,
                                fallbackName: nombre,
                                style: const TextStyle(
                                  fontFamily: kArial,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                              Text(
                                cargo.isNotEmpty ? '$cedula · $cargo' : cedula,
                                style: TextStyle(
                                  fontFamily: kArial,
                                  fontSize: 11,
                                  color: esDirectivo
                                      ? Colors.green.shade700
                                      : Colors.black54,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        DropdownButton<String>(
                          value: rolActual?.rol,
                          hint: const Text(
                            'Sin rol',
                            style: TextStyle(fontFamily: kArial, fontSize: 12),
                          ),
                          items: [
                            const DropdownMenuItem<String>(
                              value: null,
                              child: Text(
                                'Sin rol',
                                style: TextStyle(
                                  fontFamily: kArial,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            ...kInterventoriaRoles.map(
                              (r) => DropdownMenuItem<String>(
                                value: r,
                                child: Row(
                                  children: [
                                    Icon(
                                      rolesIcons[r],
                                      size: 14,
                                      color: rolesColors[r],
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      kInterventoriaRoleLabels[r] ?? r,
                                      style: const TextStyle(
                                        fontFamily: kArial,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                          onChanged: (nuevoRol) async {
                            try {
                              if (nuevoRol == null) {
                                if (rolActual != null) {
                                  await svc.eliminarRol(rolActual.id);
                                  _snack('Rol eliminado de $nombre');
                                }
                                return;
                              }
                              final doc = InterventoriaRolDoc(
                                id: rolActual?.id ?? '',
                                empresaId: empresaId,
                                userId: userId,
                                cedula: cedula,
                                nombre: nombre,
                                rol: nuevoRol,
                                createdAt: Timestamp.now(),
                              );
                              await svc.guardarRol(
                                doc,
                                isNew: rolActual == null,
                              );
                              await _repo.grantUserApps(
                                userId: userId,
                                empresaId: empresaId,
                                appIds: const [kInterventoriaAppId],
                              );
                              _snack(
                                'Rol ${kInterventoriaRoleLabels[nuevoRol]} asignado a $nombre',
                              );
                            } catch (e) {
                              _snack('Error al guardar rol: $e');
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                );
              }).toList();
            }(),
          ],
        );
      },
    );
  }

  // ── Tab Roles Rutas ────────────────────────────────────────────────────────

  // Respaldos internos: la asignación principal ahora vive en la matriz central.
  // ignore: unused_element
  Widget _tabRolesRutas() {
    final empresaId = _empresaId ?? '';
    if (empresaId.isEmpty) {
      return const Center(
        child: Text(
          'Selecciona una empresa',
          style: TextStyle(fontFamily: kArial),
        ),
      );
    }
    final svc = RutasService();
    final rolesIcons = <String, IconData>{
      kRutasRolAdmin: Icons.admin_panel_settings,
      kRutasRolCalidad: Icons.verified,
      kRutasRolAdminCalidad: Icons.fact_check,
      kRutasRolConductor: Icons.local_shipping,
      kRutasRolDesarrollador: Icons.code,
    };
    final rolesColors = <String, Color>{
      kRutasRolAdmin: Colors.indigo,
      kRutasRolCalidad: Colors.teal,
      kRutasRolAdminCalidad: Colors.blueGrey,
      kRutasRolConductor: Colors.green,
      kRutasRolDesarrollador: Colors.deepPurple,
    };

    return StreamBuilder<List<RutaRolDoc>>(
      stream: svc.streamRoles(empresaId),
      builder: (ctx, snapRoles) {
        final rolesActuales = snapRoles.data ?? [];
        final search = _rutasRolesSearch.trim().toLowerCase();
        final filtered = _users.where((u) {
          if (search.isEmpty) return true;
          final data = u.data();
          final nombre = _userName(data, u.id).toLowerCase();
          final cedula = _safe(data['cedula']).toLowerCase();
          return nombre.contains(search) ||
              cedula.contains(search) ||
              u.id.toLowerCase().contains(search);
        }).toList();

        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Card(
              color: kAdminCard,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.local_shipping, color: Color(0xFF15803D)),
                        SizedBox(width: 8),
                        Text(
                          'Roles en Rutas',
                          style: TextStyle(
                            fontFamily: kArial,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Conductor (móvil, toma la evidencia) · Calidad (revisa y aprueba) · '
                      'Administrador (rutas y personal) · Desarrollador (prueba los 3 perfiles). '
                      'El rol se guarda en TBL_RUTAS_ROLES.',
                      style: TextStyle(
                        fontFamily: kArial,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () async {
                        await _repo.upsertApp(
                          empresaId: empresaId,
                          appId: kRutasAppId,
                          nombre: 'Rutas',
                          descripcion:
                              'Gestion de rutas, asignaciones y evidencias fotograficas georreferenciadas.',
                          enabled: true,
                          isNew: true,
                        );
                        await svc.asegurarConfigBase(empresaId);
                        _snack(
                          'Modulo Rutas habilitado y configuracion base creada.',
                        );
                        await _loadAll(forceEmpresaId: empresaId);
                      },
                      icon: const Icon(Icons.add_circle_outline),
                      label: const Text('Habilitar modulo Rutas'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search),
                hintText: 'Buscar usuario por nombre o cédula',
                border: OutlineInputBorder(),
              ),
              style: const TextStyle(fontFamily: kArial),
              onChanged: (v) => setState(() => _rutasRolesSearch = v),
            ),
            const SizedBox(height: 10),
            if (filtered.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    'No se encontraron usuarios',
                    style: TextStyle(fontFamily: kArial, color: Colors.black45),
                  ),
                ),
              )
            else
              ...filtered.map((userDoc) {
                final data = userDoc.data();
                final nombre = _userName(data, userDoc.id);
                final cedula = _safe(data['cedula']);
                final cargo = _safe(data['cargo']);
                final userId = userDoc.id;
                RutaRolDoc? rolActual;
                try {
                  rolActual = rolesActuales.firstWhere(
                    (r) => r.userId == userId || r.cedula == cedula,
                  );
                } catch (_) {}

                return Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        UserAvatar(
                          userId: cedula,
                          nameHint: nombre,
                          radius: 14,
                          backgroundColor: kAdminPrimary.withValues(
                            alpha: 0.08,
                          ),
                          foregroundColor: kAdminPrimary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              UserNameText(
                                cedula,
                                fallbackName: nombre,
                                style: const TextStyle(
                                  fontFamily: kArial,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                              Text(
                                cargo.isNotEmpty ? '$cedula · $cargo' : cedula,
                                style: const TextStyle(
                                  fontFamily: kArial,
                                  fontSize: 11,
                                  color: Colors.black54,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        DropdownButton<String>(
                          value: rolActual?.rol,
                          hint: const Text(
                            'Sin rol',
                            style: TextStyle(fontFamily: kArial, fontSize: 12),
                          ),
                          items: [
                            const DropdownMenuItem<String>(
                              value: null,
                              child: Text(
                                'Sin rol',
                                style: TextStyle(
                                  fontFamily: kArial,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            ...kRutasRoles.map(
                              (r) => DropdownMenuItem<String>(
                                value: r,
                                child: Row(
                                  children: [
                                    Icon(
                                      rolesIcons[r],
                                      size: 14,
                                      color: rolesColors[r],
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      kRutasRolLabels[r] ?? r,
                                      style: const TextStyle(
                                        fontFamily: kArial,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                          onChanged: (nuevoRol) async {
                            try {
                              if (nuevoRol == null) {
                                if (rolActual != null) {
                                  await svc.eliminarRol(rolActual.id);
                                  _snack('Rol eliminado de $nombre');
                                }
                                return;
                              }
                              final doc = RutaRolDoc(
                                id: rolActual?.id ?? '',
                                empresaId: empresaId,
                                userId: userId,
                                cedula: cedula,
                                nombre: nombre,
                                rol: nuevoRol,
                                createdAt: Timestamp.now(),
                              );
                              await svc.guardarRol(
                                doc,
                                isNew: rolActual == null,
                              );
                              await _repo.grantUserApps(
                                userId: userId,
                                empresaId: empresaId,
                                appIds: const [kRutasAppId],
                              );
                              _snack(
                                'Rol ${kRutasRolLabels[nuevoRol]} asignado a $nombre',
                              );
                            } catch (e) {
                              _snack('Error al guardar rol: $e');
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                );
              }),
          ],
        );
      },
    );
  }

  // ── Tab Roles Facturación ──────────────────────────────────────────────────

  // Respaldos internos: la asignación principal ahora vive en la matriz central.
  // ignore: unused_element
  Widget _tabRolesFacturacion() {
    final empresaId = _empresaId ?? '';
    final isMobile = MediaQuery.of(context).size.width < 700;
    if (empresaId.isEmpty) {
      return const Center(
        child: Text(
          'Selecciona una empresa',
          style: TextStyle(fontFamily: kArial),
        ),
      );
    }

    // Cargar establecimientos de facturación para el dropdown
    return FutureBuilder<List<Map<String, String>>>(
      future: _loadFacEstablecimientos(empresaId),
      builder: (ctx, snapEst) {
        final ests = snapEst.data ?? [];

        return ListView(
          padding: EdgeInsets.all(isMobile ? 10 : 12),
          children: [
            // ── Cabecera informativa ──────────────────────────────────────
            Card(
              color: kAdminCard,
              child: Padding(
                padding: EdgeInsets.all(isMobile ? 14 : 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.receipt_long, color: Color(0xFF0369A1)),
                        SizedBox(width: 8),
                        Text(
                          'Roles en Facturación',
                          style: TextStyle(
                            fontFamily: kArial,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Asigna quién puede gestionar facturación y qué establecimiento '
                      'controla cada usuario. El rol se guarda en TBL_USUARIOS → empresasDetalle.',
                      style: TextStyle(
                        fontFamily: kArial,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (ests.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 16,
                              color: Colors.orange,
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'No hay centros de costo (TBL_CENTROS_COSTOS) configurados para esta empresa. '
                                'Agrégalos desde el panel de Catálogos.',
                                style: TextStyle(
                                  fontFamily: kArial,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            // ── Resumen roles asignados ───────────────────────────────────
            ..._users
                .where((u) {
                  final det = u.data()['empresasDetalle'];
                  if (det is! Map) return false;
                  final emp = det[empresaId];
                  if (emp is! Map) return false;
                  return (emp['rolFac'] ?? '').toString().isNotEmpty;
                })
                .map((u) {
                  final data = u.data();
                  final nombre = _userName(data, u.id);
                  final det = data['empresasDetalle'] as Map;
                  final emp = det[empresaId] as Map;
                  final rol = (emp['rolFac'] ?? '').toString();
                  final estId = (emp['establecimientoFacId'] ?? '').toString();
                  final estNombre =
                      ests.firstWhere(
                        (e) => e['id'] == estId,
                        orElse: () => {'nombre': estId},
                      )['nombre'] ??
                      estId;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    color: const Color(0xFFF0F9FF),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: const BorderSide(color: Color(0xFF7DD3FC)),
                    ),
                    child: ListTile(
                      leading: const Icon(
                        Icons.receipt_long,
                        color: Color(0xFF0369A1),
                        size: 20,
                      ),
                      title: Text(
                        nombre,
                        style: const TextStyle(
                          fontFamily: kArial,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        '${kFacRoleLabels[rol] ?? rol}${estId.isNotEmpty ? ' · $estNombre' : ''}',
                        style: const TextStyle(
                          fontFamily: kArial,
                          fontSize: 12,
                        ),
                      ),
                      trailing: IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.red,
                          size: 20,
                        ),
                        tooltip: 'Quitar rol',
                        onPressed: () async {
                          final ok = await _confirm(
                            title: 'Quitar rol',
                            message: '¿Quitar acceso a Facturación de $nombre?',
                            confirmText: 'Quitar',
                          );
                          if (!ok) return;
                          await FirebaseFirestore.instance
                              .collection('TBL_USUARIOS')
                              .doc(u.id)
                              .update({
                                'empresasDetalle.$empresaId.rolFac':
                                    FieldValue.delete(),
                                'empresasDetalle.$empresaId.establecimientoFacId':
                                    FieldValue.delete(),
                              });
                          _snack('Rol eliminado de $nombre');
                          await _loadAll(forceEmpresaId: empresaId);
                        },
                      ),
                    ),
                  );
                }),
            const Divider(height: 24),
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'Asignar rol a usuario',
                style: TextStyle(
                  fontFamily: kArial,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
            // ── Filtros ──────────────────────────────────────────────────
            _buildPersonnelFilterBar(
              searchHint: 'Nombre, cédula, cargo, área…',
              searchValue: _facRolesSearch,
              onSearchChanged: (v) =>
                  setState(() => _facRolesSearch = v.trim().toLowerCase()),
              selectedAreaId: _facRolesAreaFilter,
              onAreaChanged: (v) => setState(() => _facRolesAreaFilter = v),
            ),
            // ── Lista de usuarios ────────────────────────────────────────
            ..._applyPersonnelFilter(
              _users,
              search: _facRolesSearch,
              areaId: _facRolesAreaFilter,
            ).map((userDoc) {
              final data = userDoc.data();
              final nombre = _userName(data, userDoc.id);
              final cedula = _safe(data['cedula']);
              final cargo = _safe(data['cargo']);
              final det = data['empresasDetalle'];
              final empDet = det is Map
                  ? (det[empresaId] is Map ? det[empresaId] as Map : null)
                  : null;
              final rolActual = empDet != null
                  ? (empDet['rolFac'] ?? '').toString()
                  : '';
              // establecimientoFacId: primero el valor explícito, luego se infiere
              // del centroCostos ya asignado al usuario (por nombre → centroId).
              String estActual = empDet != null
                  ? (empDet['establecimientoFacId'] ?? '').toString()
                  : '';
              if (estActual.isEmpty) {
                final ccNombre =
                    ((empDet?['centroCostos'] ?? data['centroCostos']) ?? '')
                        .toString()
                        .trim();
                if (ccNombre.isNotEmpty) {
                  final match = ests.firstWhere(
                    (e) =>
                        (e['nombre'] ?? '').toLowerCase() ==
                        ccNombre.toLowerCase(),
                    orElse: () => <String, String>{},
                  );
                  estActual = match['id'] ?? '';
                }
              }
              final roleDropdown = DropdownButton<String>(
                value: rolActual.isEmpty ? null : rolActual,
                isExpanded: isMobile,
                hint: const Text(
                  'Sin rol',
                  style: TextStyle(fontFamily: kArial, fontSize: 12),
                ),
                items: [
                  const DropdownMenuItem<String>(
                    value: null,
                    child: Text(
                      'Sin rol',
                      style: TextStyle(fontFamily: kArial, fontSize: 12),
                    ),
                  ),
                  ...kFacRoles.map(
                    (r) => DropdownMenuItem<String>(
                      value: r,
                      child: Text(
                        kFacRoleLabels[r] ?? r,
                        style: const TextStyle(
                          fontFamily: kArial,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ],
                onChanged: (nuevoRol) async {
                  try {
                    if (nuevoRol == null) {
                      await FirebaseFirestore.instance
                          .collection('TBL_USUARIOS')
                          .doc(userDoc.id)
                          .update({
                            'empresasDetalle.$empresaId.rolFac':
                                FieldValue.delete(),
                            'empresasDetalle.$empresaId.establecimientoFacId':
                                FieldValue.delete(),
                          });
                      _snack('Rol eliminado de $nombre');
                      await _loadAll(forceEmpresaId: empresaId);
                    } else {
                      // Auto-detectar el establecimientoFacId desde
                      // el centroCostos ya asignado al usuario.
                      String? autoEstId;
                      if (nuevoRol == kRolEstablecimiento) {
                        final ccNombre =
                            ((empDet?['centroCostos'] ??
                                        data['centroCostos']) ??
                                    '')
                                .toString()
                                .trim();
                        if (ccNombre.isNotEmpty) {
                          final match = ests.firstWhere(
                            (e) =>
                                (e['nombre'] ?? '').toLowerCase() ==
                                ccNombre.toLowerCase(),
                            orElse: () => <String, String>{},
                          );
                          autoEstId = match['id'];
                        }
                      }
                      await FirebaseFirestore.instance
                          .collection('TBL_USUARIOS')
                          .doc(userDoc.id)
                          .set({
                            'empresasDetalle': {
                              empresaId: {
                                'rolFac': nuevoRol,
                                if (autoEstId != null && autoEstId.isNotEmpty)
                                  'establecimientoFacId': autoEstId,
                              },
                            },
                          }, SetOptions(merge: true));
                      await _repo.grantUserApps(
                        userId: userDoc.id,
                        empresaId: empresaId,
                        appIds: const [kFacAppId],
                      );
                      final estLabel = autoEstId != null && autoEstId.isNotEmpty
                          ? ' · Establecimiento auto-asignado'
                          : '';
                      _snack(
                        '${kFacRoleLabels[nuevoRol]} asignado a $nombre$estLabel',
                      );
                      await _loadAll(forceEmpresaId: empresaId);
                    }
                  } catch (e) {
                    _snack('Error: $e');
                  }
                },
              );

              return Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          UserAvatar(
                            userId: cedula,
                            nameHint: nombre,
                            radius: 14,
                            backgroundColor: kAdminPrimary.withValues(
                              alpha: 0.08,
                            ),
                            foregroundColor: kAdminPrimary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                UserNameText(
                                  cedula,
                                  fallbackName: nombre,
                                  style: const TextStyle(
                                    fontFamily: kArial,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  cargo.isNotEmpty
                                      ? '$cedula · $cargo'
                                      : cedula,
                                  style: const TextStyle(
                                    fontFamily: kArial,
                                    fontSize: 11,
                                    color: Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (!isMobile) roleDropdown,
                        ],
                      ),
                      if (isMobile) ...[
                        const SizedBox(height: 8),
                        SizedBox(width: double.infinity, child: roleDropdown),
                      ],
                      // Dropdown establecimiento (solo si rol == establecimiento)
                      if (rolActual == kRolEstablecimiento &&
                          ests.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(
                              Icons.apartment_rounded,
                              size: 14,
                              color: Colors.grey,
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              'Establecimiento:',
                              style: TextStyle(
                                fontFamily: kArial,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: DropdownButton<String>(
                                isExpanded: true,
                                value: estActual.isEmpty ? null : estActual,
                                hint: const Text(
                                  'Seleccionar establecimiento',
                                  style: TextStyle(
                                    fontFamily: kArial,
                                    fontSize: 12,
                                  ),
                                ),
                                items: ests
                                    .map(
                                      (e) => DropdownMenuItem<String>(
                                        value: e['id'],
                                        child: Text(
                                          e['nombre'] ?? e['id']!,
                                          style: const TextStyle(
                                            fontFamily: kArial,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (estId) async {
                                  if (estId == null) return;
                                  try {
                                    await FirebaseFirestore.instance
                                        .collection('TBL_USUARIOS')
                                        .doc(userDoc.id)
                                        .set({
                                          'empresasDetalle': {
                                            empresaId: {
                                              'establecimientoFacId': estId,
                                            },
                                          },
                                        }, SetOptions(merge: true));
                                    _snack(
                                      'Establecimiento asignado a $nombre',
                                    );
                                    await _loadAll(forceEmpresaId: empresaId);
                                  } catch (e) {
                                    _snack('Error: $e');
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }

  // ================= SALUD DE USUARIOS (diagnóstico read-only) =============

  /// Normaliza un nombre para comparar duplicados (sin tildes, minúsculas,
  /// espacios colapsados).
  String _normName(String s) {
    const src = 'áéíóúÁÉÍÓÚäëïöüÄËÏÖÜñÑ';
    const dst = 'aeiouAEIOUaeiouAEIOUnN';
    var out = s;
    for (int i = 0; i < src.length; i++) {
      out = out.replaceAll(src[i], dst[i]);
    }
    return out.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  String _empresaNombre(String id) {
    for (final e in _empresas) {
      if (e.empresaId == id) return e.nombre;
    }
    return id;
  }

  /// Escanea TODO TBL_USUARIOS y calcula el reporte de salud. Solo lectura.
  Future<void> _runUserHealthScan() async {
    setState(() => _saludLoading = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('TBL_USUARIOS')
          .get();
      final docs = snap.docs;

      final byName = <String, List<String>>{}; // nameKey -> [docId,...]
      final tmp = <_UserHealthEntry>[];

      for (final d in docs) {
        final data = d.data();
        final docId = d.id.trim();
        final cedField = _safe(data['cedula']);
        final nombre = _userName(data, docId);
        final empresas = ((data['empresas'] as List?) ?? const [])
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList();
        final det = data['empresasDetalle'];
        final detKeys = det is Map
            ? det.keys.map((k) => k.toString().trim()).toSet()
            : <String>{};
        final topEmpresa = _safe(data['empresaId']);

        final issues = <String>{};

        // Cédula no numérica (el ID debería ser solo dígitos).
        final digitsId = docId.replaceAll(RegExp(r'[^0-9]'), '');
        if (docId.isEmpty || digitsId != docId) issues.add('no_numerica');

        // El campo 'cedula' no coincide con el ID del documento.
        if (cedField.isNotEmpty && cedField != docId) issues.add('mismatch_id');

        // Longitud sospechosa (cédulas/NIT colombianos: 6–10 dígitos).
        final len = digitsId.length;
        if (digitsId.isNotEmpty && (len < 6 || len > 10)) {
          issues.add('longitud');
        }

        // Posible redondeo: termina en 3+ ceros (firma del bug double.toString()).
        if (digitsId.length >= 6 && RegExp(r'0{3,}$').hasMatch(digitsId)) {
          issues.add('ceros_cola');
        }

        // Sin empresa asignada.
        if (empresas.isEmpty) issues.add('sin_empresa');

        // Inconsistencia entre empresas / empresasDetalle / empresaId.
        final empresasSet = empresas.toSet();
        final inconsistente =
            detKeys.any((k) => !empresasSet.contains(k)) ||
            (det is Map && empresasSet.any((e) => !detKeys.contains(e))) ||
            (topEmpresa.isNotEmpty && !empresasSet.contains(topEmpresa));
        if ((empresas.isNotEmpty || detKeys.isNotEmpty) && inconsistente) {
          issues.add('inconsistencia');
        }

        final nk = _normName(nombre);
        if (nk.isNotEmpty) byName.putIfAbsent(nk, () => []).add(docId);

        tmp.add(
          _UserHealthEntry(
            docId: docId,
            cedulaField: cedField,
            nombre: nombre,
            empresas: empresas,
            nameKey: nk,
            issues: issues,
          ),
        );
      }

      // Segunda pasada: marcar posibles duplicados por nombre.
      final dupNames = byName.entries
          .where((e) => e.value.length > 1)
          .map((e) => e.key)
          .toSet();
      for (final e in tmp) {
        if (e.nameKey.isNotEmpty && dupNames.contains(e.nameKey)) {
          e.issues.add('duplicado');
        }
      }

      final flagged = tmp.where((e) => e.issues.isNotEmpty).toList()
        ..sort((a, b) {
          final c = b.issues.length.compareTo(a.issues.length);
          return c != 0 ? c : a.docId.compareTo(b.docId);
        });

      final counts = <String, int>{};
      for (final e in flagged) {
        for (final code in e.issues) {
          counts[code] = (counts[code] ?? 0) + 1;
        }
      }

      if (!mounted) return;
      setState(() {
        _saludReport = _UserHealthReport(
          total: docs.length,
          entries: flagged,
          counts: counts,
          scannedAt: DateTime.now(),
        );
        _saludLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _saludLoading = false);
      _snack('Error al escanear usuarios: $e');
    }
  }

  Widget _tabSaludUsuarios() {
    final report = _saludReport;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Cabecera informativa ──────────────────────────────────────────
        Card(
          color: const Color(0xFFEFF6FF),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFFBFDBFE)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.health_and_safety,
                      color: kAdminAccent,
                      size: 26,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Salud de usuarios',
                        style: TextStyle(
                          fontFamily: kArial,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  'Diagnóstico de solo lectura sobre TODOS los usuarios '
                  '(no solo la empresa activa). Detecta cédulas mal formadas, '
                  'posibles truncamientos por Excel, duplicados e '
                  'inconsistencias de membresía. No modifica ningún dato.',
                  style: TextStyle(
                    fontFamily: kArial,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: kAdminPrimary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _saludLoading ? null : _runUserHealthScan,
            icon: _saludLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.search),
            label: Text(
              _saludLoading
                  ? 'Escaneando…'
                  : (report == null
                        ? 'Ejecutar diagnóstico'
                        : 'Volver a escanear'),
              style: const TextStyle(
                fontFamily: kArial,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
        if (report != null) ...[
          const SizedBox(height: 16),
          _saludResumen(report),
          const SizedBox(height: 12),
          if (report.entries.isEmpty)
            Card(
              color: const Color(0xFFF0FDF4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Color(0xFFBBF7D0)),
              ),
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: kAdminSuccess),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'No se detectaron problemas. Todos los usuarios pasaron '
                        'las validaciones.',
                        style: TextStyle(fontFamily: kArial, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ..._saludCategorias
                .where((c) => (report.counts[c.code] ?? 0) > 0)
                .map((c) => _saludCategoriaCard(c, report)),
        ],
      ],
    );
  }

  Widget _saludResumen(_UserHealthReport report) {
    final sano = report.total - report.entries.length;
    final hora =
        '${report.scannedAt.hour.toString().padLeft(2, '0')}:'
        '${report.scannedAt.minute.toString().padLeft(2, '0')}:'
        '${report.scannedAt.second.toString().padLeft(2, '0')}';
    return Card(
      color: kAdminCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: kAdminBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Escaneados: ${report.total}  ·  con problemas: '
              '${report.entries.length}  ·  sin problemas: $sano',
              style: const TextStyle(
                fontFamily: kArial,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Último escaneo: $hora',
              style: const TextStyle(
                fontFamily: kArial,
                fontSize: 11,
                color: kAdminMuted,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _saludCategorias
                  .where((c) => (report.counts[c.code] ?? 0) > 0)
                  .map((c) {
                    final n = report.counts[c.code] ?? 0;
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: c.color.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: c.color.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(c.icon, size: 16, color: c.color),
                          const SizedBox(width: 6),
                          Text(
                            '$n',
                            style: TextStyle(
                              fontFamily: kArial,
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              color: c.color,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            c.label,
                            style: const TextStyle(
                              fontFamily: kArial,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    );
                  })
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _saludCategoriaCard(_SaludCat cat, _UserHealthReport report) {
    final entries = report.entries
        .where((e) => e.issues.contains(cat.code))
        .toList();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: kAdminCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: kAdminBorder),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: Icon(cat.icon, color: cat.color),
          title: Text(
            '${cat.label}  (${entries.length})',
            style: const TextStyle(
              fontFamily: kArial,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          subtitle: Text(
            cat.desc,
            style: const TextStyle(
              fontFamily: kArial,
              fontSize: 11,
              color: kAdminMuted,
            ),
          ),
          childrenPadding: EdgeInsets.zero,
          // Listado largo: de a 20 con paginador, no todo de golpe.
          children: [
            PagedListSection<_UserHealthEntry>(
              items: entries,
              etiqueta: 'usuarios',
              itemBuilder: (_, e, _) => _saludEntryTile(e),
            ),
          ],
        ),
      ),
    );
  }

  Widget _saludEntryTile(_UserHealthEntry e) {
    final empresasTxt = e.empresas.isEmpty
        ? '—'
        : e.empresas.map(_empresaNombre).join(', ');
    final mismatch = e.cedulaField.isNotEmpty && e.cedulaField != e.docId;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: kAdminBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            e.nombre.isEmpty ? '(sin nombre)' : e.nombre,
            style: const TextStyle(
              fontFamily: kArial,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'ID: ${e.docId}'
            '${mismatch ? '   ·   campo cédula: ${e.cedulaField}' : ''}',
            style: const TextStyle(
              fontFamily: kArial,
              fontSize: 11,
              color: kAdminMuted,
            ),
          ),
          Text(
            'Empresas: $empresasTxt',
            style: const TextStyle(
              fontFamily: kArial,
              fontSize: 11,
              color: kAdminMuted,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: e.issues.map((code) {
              final c = _saludCategorias.firstWhere(
                (x) => x.code == code,
                orElse: () => _saludCategorias.first,
              );
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: c.color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  c.label,
                  style: TextStyle(
                    fontFamily: kArial,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: c.color,
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => _promptRekeyCedula(e),
                icon: const Icon(Icons.edit, size: 16),
                label: const Text(
                  'Corregir cédula',
                  style: TextStyle(fontFamily: kArial, fontSize: 12),
                ),
              ),
              const SizedBox(width: 4),
              TextButton.icon(
                onPressed: () => _promptFormatUser(e),
                style: TextButton.styleFrom(foregroundColor: kAdminError),
                icon: const Icon(Icons.delete_forever, size: 16),
                label: const Text(
                  'Formatear',
                  style: TextStyle(fontFamily: kArial, fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ================= CORRECCIÓN DE IDENTIDAD (Etapa 4) =====================
  // La cédula es el ID de documento en varias colecciones, así que corregirla
  // es una migración. Aquí cubrimos dos caminos confirmados con el usuario:
  //  - Re-llaveo SEGURO: solo si el usuario NO tiene tareas ni notificaciones.
  //  - Formatear (wipe TOTAL): borra usuario + identidad + tareas + notifs.

  /// Devuelve las referencias (sin duplicar) de tareas que apuntan a una cédula,
  /// ya sea como asignado o como creador (incluye campos legacy).
  Future<List<DocumentReference<Map<String, dynamic>>>> _userTaskRefs(
    String cedula,
  ) async {
    final tareas = FirebaseFirestore.instance.collection('TBL_TAREAS');
    const fields = ['asignado_uid', 'creador_id', 'assignedTo', 'creatorId'];
    final refs = <String, DocumentReference<Map<String, dynamic>>>{};
    for (final f in fields) {
      final snap = await tareas.where(f, isEqualTo: cedula).get();
      for (final d in snap.docs) {
        refs[d.id] = d.reference;
      }
    }
    return refs.values.toList();
  }

  Future<int> _userNotifCount(String cedula) =>
      _countUserNotifs(userId: cedula, empresaId: null, soloNoLeidas: false);

  /// Diálogo para corregir (re-llavear) la cédula de un usuario sin actividad.
  Future<void> _promptRekeyCedula(_UserHealthEntry e) async {
    final ctrl = TextEditingController(text: e.docId);
    final nueva = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Corregir cédula',
          style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.w800),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Usuario: ${e.nombre}\nCédula actual: ${e.docId}',
              style: const TextStyle(fontFamily: kArial),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Cédula correcta',
                border: OutlineInputBorder(),
              ),
              style: const TextStyle(fontFamily: kArial),
            ),
            const SizedBox(height: 8),
            const Text(
              'Solo se permite si el usuario NO tiene tareas ni notificaciones. '
              'Si las tiene, usa "Formatear".',
              style: TextStyle(
                fontFamily: kArial,
                fontSize: 12,
                color: kAdminMuted,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(fontFamily: kArial)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text(
              'Continuar',
              style: TextStyle(fontFamily: kArial),
            ),
          ),
        ],
      ),
    );
    if (nueva == null) return;
    await _rekeyUser(e, nueva);
  }

  /// Mueve un usuario sin actividad a la cédula correcta y borra el viejo.
  Future<void> _rekeyUser(_UserHealthEntry e, String nuevaRaw) async {
    final old = e.docId;
    final nueva = nuevaRaw.replaceAll(RegExp(r'[^0-9]'), '');
    if (nueva.isEmpty || nueva.length < 6 || nueva.length > 10) {
      _snack('La cédula correcta debe tener entre 6 y 10 dígitos.');
      return;
    }
    if (nueva == old) {
      _snack('La cédula nueva es igual a la actual.');
      return;
    }

    setState(() => _saludLoading = true);
    try {
      final db = FirebaseFirestore.instance;

      // Colisión: el destino no debe existir (evita pisar a otra persona).
      final destino = await db.collection('TBL_USUARIOS').doc(nueva).get();
      if (destino.exists) {
        _snack(
          'Ya existe un usuario con la cédula $nueva. '
          'Usa la pestaña Membresía para resolverlo manualmente.',
        );
        return;
      }

      // Actividad: el re-llaveo solo es seguro sin tareas ni notificaciones.
      final tasks = await _userTaskRefs(old);
      final notifs = await _userNotifCount(old);
      if (tasks.isNotEmpty || notifs > 0) {
        _snack(
          'No se puede re-llavear: tiene ${tasks.length} tarea(s) y '
          '$notifs notificación(es). Usa "Formatear".',
        );
        return;
      }

      if (!mounted) return;
      setState(() => _saludLoading = false);
      final ok = await _confirm(
        title: 'Confirmar corrección',
        message:
            'Se moverá $old → $nueva en TBL_USUARIOS, ESTRUCTURA, CEDULAS y '
            'EMPLEADOS. El registro viejo se elimina. ¿Continuar?',
        confirmText: 'CORREGIR',
      );
      if (!ok) return;
      if (!mounted) return;
      setState(() => _saludLoading = true);

      final userDoc = await db.collection('TBL_USUARIOS').doc(old).get();
      final userData = userDoc.data() ?? <String, dynamic>{};
      final empresas = ((userData['empresas'] as List?) ?? const [])
          .map((x) => x.toString().trim())
          .where((x) => x.isNotEmpty)
          .toList();

      final estructura = await db
          .collection('TBL_ESTRUCTURA_ORGANIZACIONAL')
          .doc(old)
          .get();
      final cedulaDoc = await db.collection('TBL_CEDULAS').doc(old).get();

      final batch = db.batch();
      if (userDoc.exists) {
        batch.set(db.collection('TBL_USUARIOS').doc(nueva), {
          ...userData,
          'cedula': nueva,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        batch.delete(db.collection('TBL_USUARIOS').doc(old));
      }
      if (estructura.exists) {
        batch.set(db.collection('TBL_ESTRUCTURA_ORGANIZACIONAL').doc(nueva), {
          ...estructura.data()!,
          'cedula': nueva,
        });
        batch.delete(db.collection('TBL_ESTRUCTURA_ORGANIZACIONAL').doc(old));
      }
      if (cedulaDoc.exists) {
        batch.set(db.collection('TBL_CEDULAS').doc(nueva), {
          ...cedulaDoc.data()!,
          'cedula': nueva,
        });
        batch.delete(db.collection('TBL_CEDULAS').doc(old));
      }
      for (final emp in empresas) {
        final oldRef = db.collection('TBL_EMPLEADOS').doc('${emp}_$old');
        final snap = await oldRef.get();
        if (snap.exists) {
          batch.set(db.collection('TBL_EMPLEADOS').doc('${emp}_$nueva'), {
            ...snap.data()!,
            'cedula': nueva,
          });
          batch.delete(oldRef);
        }
      }
      await batch.commit();
      _snack('Usuario corregido: $old → $nueva.');
      await _runUserHealthScan();
    } catch (err) {
      _snack('Error al corregir: $err');
    } finally {
      if (mounted) setState(() => _saludLoading = false);
    }
  }

  /// Cuenta la actividad y pide confirmación antes del wipe total.
  Future<void> _promptFormatUser(_UserHealthEntry e) async {
    setState(() => _saludLoading = true);
    int taskCount;
    int notifCount;
    try {
      taskCount = (await _userTaskRefs(e.docId)).length;
      notifCount = await _userNotifCount(e.docId);
    } catch (err) {
      if (mounted) setState(() => _saludLoading = false);
      _snack('Error al contar actividad: $err');
      return;
    }
    if (!mounted) return;
    setState(() => _saludLoading = false);

    final ok = await _confirm(
      title: '⚠ Formatear usuario',
      message:
          'Se ELIMINARÁ por completo a ${e.nombre} (cédula ${e.docId}):\n'
          '• Usuario, estructura, cédula y empleados\n'
          '• $taskCount tarea(s)\n'
          '• $notifCount notificación(es)\n\n'
          'Esta acción es IRREVERSIBLE. ¿Continuar?',
      confirmText: 'FORMATEAR',
    );
    if (!ok) return;
    await _formatUser(e);
  }

  /// Wipe total: borra identidad + tareas + notificaciones de la cédula.
  Future<void> _formatUser(_UserHealthEntry e) async {
    final cedula = e.docId;
    setState(() => _saludLoading = true);
    try {
      final db = FirebaseFirestore.instance;

      // 1) Notificaciones (subcolección) + doc padre.
      await _deleteUserNotifs(
        userId: cedula,
        empresaId: null,
        soloNoLeidas: false,
      );
      await db.collection('TBL_NOTIFICACIONES').doc(cedula).delete();

      // 2) Tareas (asignadas o creadas), en lotes de 400.
      final taskRefs = await _userTaskRefs(cedula);
      for (var i = 0; i < taskRefs.length; i += 400) {
        final end = (i + 400 < taskRefs.length) ? i + 400 : taskRefs.length;
        final b = db.batch();
        for (final r in taskRefs.sublist(i, end)) {
          b.delete(r);
        }
        await b.commit();
      }

      // 3) Identidad (usuario, estructura, cédula, empleados por empresa).
      final userSnap = await db.collection('TBL_USUARIOS').doc(cedula).get();
      final empresas = ((userSnap.data()?['empresas'] as List?) ?? const [])
          .map((x) => x.toString().trim())
          .where((x) => x.isNotEmpty)
          .toList();
      final idBatch = db.batch();
      idBatch.delete(db.collection('TBL_USUARIOS').doc(cedula));
      idBatch.delete(
        db.collection('TBL_ESTRUCTURA_ORGANIZACIONAL').doc(cedula),
      );
      idBatch.delete(db.collection('TBL_CEDULAS').doc(cedula));
      for (final emp in empresas) {
        idBatch.delete(db.collection('TBL_EMPLEADOS').doc('${emp}_$cedula'));
      }
      await idBatch.commit();

      _snack('Usuario $cedula formateado (eliminado por completo).');
      await _runUserHealthScan();
    } catch (err) {
      _snack('Error al formatear: $err');
    } finally {
      if (mounted) setState(() => _saludLoading = false);
    }
  }

  // ================= MEMBRESÍA MULTI-EMPRESA (Etapa 3) =====================

  /// Carga TODO TBL_USUARIOS (bajo demanda) para poder editar membresías de
  /// cualquier usuario, no solo los de la empresa activa.
  Future<void> _loadMembresiaUsers() async {
    setState(() => _membresiaLoading = true);
    try {
      final empresaId = _empresaId ?? '';
      final results = await Future.wait([
        FirebaseFirestore.instance.collection('TBL_USUARIOS').get(),
        if (empresaId.isNotEmpty)
          FirebaseFirestore.instance
              .collection('TBL_COMPRAS_GRUPOS')
              .where('empresaId', isEqualTo: empresaId)
              .get(),
      ]);
      final snap = results.first;
      final docs = snap.docs.toList()
        ..sort(
          (a, b) => _userName(
            a.data(),
            a.id,
          ).toLowerCase().compareTo(_userName(b.data(), b.id).toLowerCase()),
        );
      final grupos = results.length > 1
          ? results[1].docs
                .where((doc) => doc.data()['activo'] != false)
                .toList()
          : <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      grupos.sort(
        (a, b) => _safe(
          a.data()['nombre'],
        ).toLowerCase().compareTo(_safe(b.data()['nombre']).toLowerCase()),
      );
      if (!mounted) return;
      setState(() {
        _membresiaUsers = docs;
        _membresiaGrupos = grupos;
        _membresiaLoaded = true;
        _membresiaLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _membresiaLoading = false);
      _snack('Error al cargar usuarios: $e');
    }
  }

  Future<void> _crearGrupoCompras() async {
    final empresaId = _empresaId ?? '';
    if (empresaId.isEmpty) {
      _snack('Selecciona una empresa antes de crear el grupo.');
      return;
    }
    final controller = TextEditingController();
    final guardar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(
          'Nuevo grupo de Compras',
          style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.w800),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nombre del grupo',
            hintText: 'Ej. Grupo 6, Planta Bogotá…',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => Navigator.pop(dialogContext, true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Crear grupo'),
          ),
        ],
      ),
    );
    final nombre = controller.text.trim();
    controller.dispose();
    if (guardar != true || nombre.isEmpty) return;
    final repetido = _membresiaGrupos.any(
      (doc) =>
          _safe(doc.data()['nombre']).trim().toLowerCase() ==
          nombre.toLowerCase(),
    );
    if (repetido) {
      _snack('Ya existe un grupo con ese nombre.');
      return;
    }
    try {
      await FirebaseFirestore.instance.collection('TBL_COMPRAS_GRUPOS').add({
        'empresaId': empresaId,
        'nombre': nombre,
        'activo': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      _snack('Grupo "$nombre" creado.');
      await _loadMembresiaUsers();
    } catch (e) {
      _snack('No se pudo crear el grupo: $e');
    }
  }

  Future<void> _setComprasGroup({
    required QueryDocumentSnapshot<Map<String, dynamic>> userDoc,
    required String groupId,
    required bool add,
  }) async {
    final empresaId = _empresaId ?? '';
    if (empresaId.isEmpty) return;
    final data = userDoc.data();
    final porEmpresa = data['gruposComprasPorEmpresa'];
    final raw = porEmpresa is Map ? porEmpresa[empresaId] : null;
    final asignados = raw is Iterable
        ? raw.map((value) => value.toString()).toSet()
        : <String>{};
    if (add) {
      asignados.add(groupId);
    } else {
      asignados.remove(groupId);
    }
    try {
      await userDoc.reference.update({
        'gruposComprasPorEmpresa.$empresaId': asignados.toList()..sort(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await _loadMembresiaUsers();
    } catch (e) {
      _snack('No se pudo actualizar el grupo: $e');
    }
  }

  Future<void> _normalizarNombresEmpresa() async {
    final empresaId = _empresaId ?? '';
    if (empresaId.isEmpty || _membresiaLoading) return;
    setState(() => _membresiaLoading = true);
    try {
      final preview = await _mig.normalizePersonNames(
        empresaId: empresaId,
        dryRun: true,
      );
      if (!mounted) return;
      setState(() => _membresiaLoading = false);
      if (preview.updated == 0) {
        _snack('Los ${preview.scanned} nombres ya están normalizados.');
        return;
      }
      final ok = await _confirm(
        title: 'Normalizar nombres',
        message:
            'Se corregirá la presentación de ${preview.updated} de '
            '${preview.scanned} personas de ${_empresaNombre(empresaId)}.\n\n'
            'Ejemplo: “MARÍA DE LA CRUZ” → “María de la Cruz”.\n'
            'No se modificarán cédulas, correos, cargos ni permisos.',
        confirmText: 'Normalizar',
      );
      if (!ok) return;
      if (mounted) setState(() => _membresiaLoading = true);
      final result = await _mig.normalizePersonNames(
        empresaId: empresaId,
        dryRun: false,
      );
      await _mig.logMigration(
        adminUserId: widget.userId,
        empresaId: empresaId,
        action: 'normalizePersonNames',
        scanned: result.scanned,
        updated: result.updated,
        dryRun: false,
      );
      UserDirectory.instance.clear();
      _snack('${result.updated} nombre(s) normalizados.');
      await _loadMembresiaUsers();
    } catch (e) {
      _snack('No se pudieron normalizar los nombres: $e');
    } finally {
      if (mounted) setState(() => _membresiaLoading = false);
    }
  }

  Future<void> _crearEmpresaPorTransicion() async {
    final source = _empresaActual;
    if (source == null || _membresiaLoading) return;
    final idCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    var makePrimary = true;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Nueva empresa por transición'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Se conservará ${source.nombre} y toda su información. '
                    'Las personas recibirán una membresía adicional en la nueva empresa.',
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: idCtrl,
                    decoration: const InputDecoration(
                      labelText: 'ID de la nueva empresa',
                      hintText: 'Ej. NUEVA_EMPRESA_2026',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nombre o razón social nueva',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: makePrimary,
                    title: const Text('Dejar la empresa nueva como principal'),
                    subtitle: const Text(
                      'La empresa anterior seguirá disponible como historial.',
                    ),
                    onChanged: (value) =>
                        setDialogState(() => makePrimary = value),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Revisar y crear'),
            ),
          ],
        ),
      ),
    );
    final targetId = idCtrl.text.trim();
    final targetName = nameCtrl.text.trim();
    idCtrl.dispose();
    nameCtrl.dispose();
    if (accepted != true) return;
    if (!RegExp(r'^[A-Za-z0-9_-]{3,80}$').hasMatch(targetId) ||
        targetName.isEmpty) {
      _snack(
        'Usa un ID de 3–80 caracteres, sin espacios, y escribe el nombre.',
      );
      return;
    }
    final confirmed = await _confirm(
      title: 'Confirmar transición empresarial',
      message:
          'Origen conservado: ${source.nombre} (${source.empresaId})\n'
          'Nueva empresa: $targetName ($targetId)\n\n'
          'Se copiará el perfil corporativo y se agregarán todos los empleados. '
          'También se copiarán centros, áreas, cargos y roles internos. '
          'No se moverán ni borrarán actas, tareas, facturas o documentos históricos.',
      confirmText: 'Crear y trasladar',
    );
    if (!confirmed) return;
    setState(() => _membresiaLoading = true);
    try {
      final result = await _companyTransition.createCompanyAndTransferEmployees(
        sourceEmpresaId: source.empresaId,
        targetEmpresaId: targetId,
        targetCompanyName: targetName,
        actorId: widget.userId,
        makeTargetPrimary: makePrimary,
      );
      _snack(
        'Empresa creada: ${result.usersTransferred} persona(s) trasladadas y '
        '${result.employeeMirrorsCreated} ficha(s), '
        '${result.catalogsCopied} catálogo(s) y '
        '${result.moduleRolesCopied} rol(es) copiados.',
      );
      await _loadAll(forceEmpresaId: targetId);
      await _loadMembresiaUsers();
    } catch (e) {
      _snack('No se pudo completar la transición: $e');
    } finally {
      if (mounted) setState(() => _membresiaLoading = false);
    }
  }

  /// Agrega o quita a un usuario de una empresa.
  /// - Agregar: arrayUnion + crea `empresasDetalle[empresaId]` mínimo (evita
  ///   inconsistencias que detecta el panel de Salud).
  /// - Quitar: reusa `_buildScopedUserReset` (maneja re-apuntar la empresa
  ///   primaria si era esta).
  Future<void> _setMembership({
    required QueryDocumentSnapshot<Map<String, dynamic>> userDoc,
    required String empresaId,
    required bool add,
  }) async {
    final data = userDoc.data();
    final nombre = _userName(data, userDoc.id);

    if (!add) {
      final empresas = ((data['empresas'] as List?) ?? const [])
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toSet();
      if (empresas.difference({empresaId}).isEmpty) {
        final ok = await _confirm(
          title: 'Quitar última empresa',
          message: '$nombre quedará sin ninguna empresa asignada. ¿Continuar?',
          confirmText: 'Quitar',
        );
        if (!ok) return;
      }
    }

    try {
      final ref = userDoc.reference;
      if (add) {
        await ref.set({
          'empresas': FieldValue.arrayUnion([empresaId]),
          'empresasDetalle': {
            empresaId: {'empresaNombre': _empresaNombre(empresaId)},
          },
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } else {
        await ref.update(_buildScopedUserReset(data, empresaId));
      }
      _snack(
        add
            ? '$nombre agregado a ${_empresaNombre(empresaId)}'
            : '$nombre quitado de ${_empresaNombre(empresaId)}',
      );
      await _loadMembresiaUsers();
    } catch (e) {
      _snack('Error: $e');
    }
  }

  Widget _tabMembresia() {
    final empresa = _empresaActual;
    final search = _membresiaSearch.trim().toLowerCase();
    final all = _membresiaUsers;
    final filtered = search.isEmpty
        ? all
        : all.where((u) {
            final d = u.data();
            final name = _userName(d, u.id).toLowerCase();
            final ced = _safe(d['cedula']).toLowerCase();
            return name.contains(search) ||
                ced.contains(search) ||
                u.id.toLowerCase().contains(search);
          }).toList();
    const cap = 60;
    final shown = filtered.take(cap).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: const Color(0xFFF5F3FF),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFFDDD6FE)),
          ),
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.apartment, color: Color(0xFF7C3AED), size: 26),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Membresía por empresa',
                        style: TextStyle(
                          fontFamily: kArial,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 10),
                Text(
                  'Controla a qué empresas pertenece cada usuario. Toca los chips '
                  'para agregar o quitar al usuario de una empresa (1, 2 o las que '
                  'necesite). Los cambios se aplican de inmediato.',
                  style: TextStyle(
                    fontFamily: kArial,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (empresa != null) ...[
          _empresaProfileCard(empresa),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: _membresiaLoading
                      ? null
                      : _crearEmpresaPorTransicion,
                  icon: const Icon(Icons.move_up_rounded),
                  label: const Text('Crear empresa y trasladar empleados'),
                ),
                OutlinedButton.icon(
                  onPressed: _membresiaLoading
                      ? null
                      : _normalizarNombresEmpresa,
                  icon: const Icon(Icons.spellcheck_rounded),
                  label: const Text('Normalizar nombres de personas'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: kAdminBorder),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.groups_2_outlined, color: kAdminAccent),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Grupos de Compras',
                              style: TextStyle(
                                fontFamily: kArial,
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              'Cada persona puede pertenecer a uno o varios grupos. Se usarán para organizar y filtrar recepciones.',
                              style: TextStyle(
                                fontFamily: kArial,
                                fontSize: 11,
                                color: kAdminMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _crearGrupoCompras,
                        icon: const Icon(Icons.add, size: 17),
                        label: const Text('Agregar grupo'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_membresiaGrupos.isEmpty)
                    const Text(
                      'Aún no hay grupos creados para esta empresa.',
                      style: TextStyle(
                        fontFamily: kArial,
                        fontSize: 12,
                        color: kAdminMuted,
                      ),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _membresiaGrupos
                          .map(
                            (grupo) => Chip(
                              avatar: const Icon(
                                Icons.group_work_outlined,
                                size: 16,
                              ),
                              label: Text(
                                _safe(grupo.data()['nombre']),
                                style: const TextStyle(fontFamily: kArial),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        TextField(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            labelText: 'Buscar usuario (nombre o cédula)',
            border: OutlineInputBorder(),
            isDense: true,
            filled: true,
            fillColor: Colors.white,
          ),
          style: const TextStyle(fontFamily: kArial),
          onChanged: (v) => setState(() => _membresiaSearch = v),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: kAdminPrimary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _membresiaLoading ? null : _loadMembresiaUsers,
            icon: _membresiaLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.refresh),
            label: Text(
              _membresiaLoading
                  ? 'Cargando…'
                  : (_membresiaLoaded
                        ? 'Actualizar usuarios'
                        : 'Cargar usuarios'),
              style: const TextStyle(
                fontFamily: kArial,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
        if (_membresiaLoaded) ...[
          const SizedBox(height: 12),
          if (_empresas.isEmpty)
            const Text(
              'No hay empresas cargadas para asignar.',
              style: TextStyle(fontFamily: kArial, color: kAdminMuted),
            )
          else ...[
            Text(
              '${filtered.length} usuario(s)'
              '${filtered.length > cap ? '  ·  mostrando $cap, refina la búsqueda' : ''}',
              style: const TextStyle(
                fontFamily: kArial,
                fontSize: 12,
                color: kAdminMuted,
              ),
            ),
            const SizedBox(height: 8),
            ...shown.map(_membresiaUserCard),
          ],
        ],
      ],
    );
  }

  Widget _membresiaUserCard(QueryDocumentSnapshot<Map<String, dynamic>> u) {
    final d = u.data();
    final nombre = _userName(d, u.id);
    final cedula = _safe(d['cedula']).isNotEmpty ? _safe(d['cedula']) : u.id;
    final empresas = ((d['empresas'] as List?) ?? const [])
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toSet();
    final empresaId = _empresaId ?? '';
    final gruposPorEmpresa = d['gruposComprasPorEmpresa'];
    final gruposRaw = gruposPorEmpresa is Map
        ? gruposPorEmpresa[empresaId]
        : null;
    final gruposAsignados = gruposRaw is Iterable
        ? gruposRaw.map((value) => value.toString()).toSet()
        : <String>{};
    final perteneceEmpresa =
        empresaId.isNotEmpty && empresas.contains(empresaId);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: kAdminBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                UserAvatar(
                  userId: cedula,
                  nameHint: nombre,
                  radius: 16,
                  backgroundColor: kAdminAccent.withValues(alpha: 0.08),
                  foregroundColor: kAdminAccent,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nombre.isEmpty ? '(sin nombre)' : nombre,
                        style: const TextStyle(
                          fontFamily: kArial,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Cédula: $cedula  ·  ${empresas.length} empresa(s)',
                        style: const TextStyle(
                          fontFamily: kArial,
                          fontSize: 11,
                          color: kAdminMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit, size: 18),
                  tooltip: 'Editar datos',
                  color: kAdminAccent,
                  onPressed: () => _promptEditUser(u),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _empresas.map((emp) {
                final belongs = empresas.contains(emp.empresaId);
                return FilterChip(
                  label: Text(
                    emp.nombre,
                    style: const TextStyle(fontFamily: kArial, fontSize: 12),
                  ),
                  selected: belongs,
                  showCheckmark: true,
                  selectedColor: kAdminAccent.withValues(alpha: 0.15),
                  checkmarkColor: kAdminAccent,
                  side: BorderSide(
                    color: belongs ? kAdminAccent : kAdminBorder,
                  ),
                  onSelected: (val) => _setMembership(
                    userDoc: u,
                    empresaId: emp.empresaId,
                    add: val,
                  ),
                );
              }).toList(),
            ),
            if (perteneceEmpresa && _membresiaGrupos.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 10),
              const Text(
                'Grupos de Compras en la empresa activa',
                style: TextStyle(
                  fontFamily: kArial,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: kAdminMuted,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _membresiaGrupos.map((grupo) {
                  final selected = gruposAsignados.contains(grupo.id);
                  return FilterChip(
                    label: Text(
                      _safe(grupo.data()['nombre']),
                      style: const TextStyle(fontFamily: kArial, fontSize: 12),
                    ),
                    selected: selected,
                    showCheckmark: true,
                    selectedColor: kAdminAccent.withValues(alpha: 0.15),
                    checkmarkColor: kAdminAccent,
                    side: BorderSide(
                      color: selected ? kAdminAccent : kAdminBorder,
                    ),
                    onSelected: (value) => _setComprasGroup(
                      userDoc: u,
                      groupId: grupo.id,
                      add: value,
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Edita los datos descriptivos de un usuario (nombre/apellidos/correo/cargo).
  /// Pensado para corregir registros con datos "trucados" en el Excel, sin
  /// tocar la cédula (la identidad) ni la membresía.
  Future<void> _promptEditUser(
    QueryDocumentSnapshot<Map<String, dynamic>> userDoc,
  ) async {
    final d = userDoc.data();
    final cedula = _safe(d['cedula']).isNotEmpty
        ? _safe(d['cedula'])
        : userDoc.id;
    final nombresCtrl = TextEditingController(
      text: _safe(d['nombres']).isNotEmpty
          ? _safe(d['nombres'])
          : _safe(d['primerNombre']),
    );
    final apellidosCtrl = TextEditingController(
      text: _safe(d['apellidos']).isNotEmpty
          ? _safe(d['apellidos'])
          : _safe(d['primerApellido']),
    );
    final correoCtrl = TextEditingController(text: _safe(d['correo']));
    final cargoCtrl = TextEditingController(text: _safe(d['cargo']));

    InputDecoration deco(String label) => InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
      isDense: true,
    );

    final guardar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Editar datos del usuario',
          style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.w800),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Cédula: $cedula (no se modifica aquí)',
                style: const TextStyle(
                  fontFamily: kArial,
                  fontSize: 12,
                  color: kAdminMuted,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nombresCtrl,
                decoration: deco('Nombres'),
                style: const TextStyle(fontFamily: kArial),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: apellidosCtrl,
                decoration: deco('Apellidos'),
                style: const TextStyle(fontFamily: kArial),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: correoCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: deco('Correo'),
                style: const TextStyle(fontFamily: kArial),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: cargoCtrl,
                decoration: deco('Cargo'),
                style: const TextStyle(fontFamily: kArial),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar', style: TextStyle(fontFamily: kArial)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: kAdminPrimary,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Guardar', style: TextStyle(fontFamily: kArial)),
          ),
        ],
      ),
    );

    final nombres = normalizePersonName(nombresCtrl.text);
    final apellidos = normalizePersonName(apellidosCtrl.text);
    final correo = correoCtrl.text.trim();
    final cargo = cargoCtrl.text.trim();
    nombresCtrl.dispose();
    apellidosCtrl.dispose();
    correoCtrl.dispose();
    cargoCtrl.dispose();
    if (guardar != true) return;

    final full = '$nombres $apellidos'.trim();
    try {
      final db = FirebaseFirestore.instance;
      final updates = <String, dynamic>{
        'nombres': nombres,
        'apellidos': apellidos,
        'primerNombre': nombres,
        'primerApellido': apellidos,
        'correo': correo,
        'cargo': cargo,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (full.isNotEmpty) {
        updates['nombre'] = full;
        updates['nombreCompleto'] = full;
      }
      await userDoc.reference.update(updates);

      // Espejo en la estructura (fuente de fallback de nombre/cargo del directorio).
      if (full.isNotEmpty || cargo.isNotEmpty) {
        await db
            .collection('TBL_ESTRUCTURA_ORGANIZACIONAL')
            .doc(userDoc.id)
            .set({
              if (full.isNotEmpty) 'nombre': full,
              if (cargo.isNotEmpty) 'cargo': cargo,
            }, SetOptions(merge: true));
      }

      // Invalida la caché para que el nombre corregido se vea de inmediato.
      UserDirectory.instance.invalidate(userDoc.id);
      _snack('Datos actualizados.');
      await _loadMembresiaUsers();
    } catch (e) {
      _snack('Error al guardar: $e');
    }
  }

  /// Carga los centros de costo habilitados de TBL_CENTROS_COSTOS.
  /// Son la fuente canónica de establecimientos para el módulo de Facturación.
  Future<List<Map<String, String>>> _loadFacEstablecimientos(
    String empresaId,
  ) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('TBL_CENTROS_COSTOS')
          .where('empresaId', isEqualTo: empresaId)
          .get();
      return snap.docs
          .where(
            (d) =>
                (d.data()['enabled'] as bool?) != false &&
                (d.data()['enabledFacturacion'] as bool?) != false,
          )
          .map((d) {
            final centroId = (d.data()['centroId'] ?? d.id).toString().trim();
            final nombre = (d.data()['nombre'] ?? centroId).toString().trim();
            return {
              'id': centroId,
              'nombre': nombre.isEmpty ? centroId : nombre,
            };
          })
          .toList()
        ..sort((a, b) => (a['nombre'] ?? '').compareTo(b['nombre'] ?? ''));
    } catch (_) {
      return [];
    }
  }

  // ===================== Salud de cargos =====================================

  /// Clave de rol para detectar cargos casi-duplicados. Normaliza, quita
  /// conectores y unifica variantes de título (dirección↔director,
  /// coordinación↔coordinador, jefatura↔jefe, gerencia↔gerente,
  /// supervisión↔supervisor, subdirección↔subdirector). Así
  /// "Dirección De Talento Humano" y "Director Talento Humano" comparten clave.
  String _cargoRoleKey(String nombre) {
    final norm = _normName(nombre);
    if (norm.isEmpty) return '';
    const conectores = {
      'de',
      'del',
      'la',
      'las',
      'el',
      'los',
      'en',
      'y',
      'e',
      'para',
    };
    const variantes = {
      'direccion': 'director',
      'coordinacion': 'coordinador',
      'jefatura': 'jefe',
      'gerencia': 'gerente',
      'supervision': 'supervisor',
      'subdireccion': 'subdirector',
    };
    final tokens =
        norm
            .split(' ')
            .where((t) => t.isNotEmpty && !conectores.contains(t))
            .map((t) => variantes[t] ?? t)
            .toList()
          ..sort();
    return tokens.join(' ');
  }

  /// Escanea TBL_CARGOS de la empresa activa: valida la referencia de área y
  /// detecta cargos casi-duplicados. Solo lectura. Carga TBL_AREAS para
  /// resolver nombres ↔ ids.
  Future<void> _runCargoHealthScan() async {
    setState(() => _cargoSaludLoading = true);
    try {
      final db = FirebaseFirestore.instance;
      final empresaId = widget.empresaId.trim();

      final areasSnap = await db
          .collection('TBL_AREAS')
          .where('empresaId', isEqualTo: empresaId)
          .get();
      // Índices de áreas: id->nombre y nombreNormalizado->id.
      final areaNameById = <String, String>{};
      final areaIdByName = <String, String>{};
      for (final a in areasSnap.docs) {
        final data = a.data();
        final areaId = _safe(data['areaId']).isNotEmpty
            ? _safe(data['areaId'])
            : a.id;
        final nombre = _safe(data['nombre']);
        if (areaId.isEmpty) continue;
        areaNameById[areaId] = nombre;
        final nk = _normName(nombre);
        if (nk.isNotEmpty) areaIdByName[nk] = areaId;
      }

      final cargosSnap = await db
          .collection('TBL_CARGOS')
          .where('empresaId', isEqualTo: empresaId)
          .get();

      // Pase 1: problemas de área + ocupantes + clave de rol.
      final all = <_CargoHealthEntry>[];
      final byRoleKey = <String, List<_CargoHealthEntry>>{};
      for (final c in cargosSnap.docs) {
        final data = c.data();
        final cargoId = _safe(data['cargoId']).isNotEmpty
            ? _safe(data['cargoId'])
            : c.id;
        final nombre = _safe(data['nombre']).isNotEmpty
            ? _safe(data['nombre'])
            : _safe(data['descripcion']);
        final areaId = _safe(data['areaId']);
        final areaNombre = _safe(data['areaNombre']).isNotEmpty
            ? _safe(data['areaNombre'])
            : _safe(data['area']);
        final habilitado =
            (data['enabled'] ?? true).toString().toLowerCase() != 'false';
        final ocupantes = ((data['cedulas'] as List?) ?? const [])
            .where((e) => e != null && e.toString().trim().isNotEmpty)
            .length;

        final issues = <String>{};
        // ¿El nombre de área resuelve a un área real?
        final resolvedId = areaIdByName[_normName(areaNombre)];

        if (areaId.isEmpty && areaNombre.isEmpty) {
          // Ni id ni nombre: imposible ubicarlo.
          issues.add('sin_area');
        } else if (areaId.isEmpty) {
          // Solo nombre (cargos creados desde Gestión de Cargos antes del fix).
          issues.add('sin_area_id');
          if (resolvedId == null) issues.add('area_inexistente');
        } else {
          // Tiene areaId: validar que exista y que concuerde con el nombre.
          if (!areaNameById.containsKey(areaId)) {
            issues.add('area_inexistente');
          } else if (resolvedId != null && resolvedId != areaId) {
            issues.add('desfase_area');
          }
        }

        // ¿Reparable? Solo si podemos resolver el areaId correcto por nombre.
        final repairId = resolvedId;
        final rk = _cargoRoleKey(nombre);
        final entry = _CargoHealthEntry(
          docId: c.id,
          cargoId: cargoId,
          nombre: nombre,
          areaId: areaId,
          areaNombre: areaNombre,
          habilitado: habilitado,
          ocupantes: ocupantes,
          issues: issues,
          repairableAreaId: repairId,
          repairableAreaNombre: repairId == null
              ? ''
              : (areaNameById[repairId] ?? areaNombre),
          duplicados: <String>[],
          roleKey: rk,
        );
        all.add(entry);
        if (rk.isNotEmpty) byRoleKey.putIfAbsent(rk, () => []).add(entry);
      }

      // Pase 2: cargos casi-duplicados (mismo rol, nombre distinto).
      for (final group in byRoleKey.values) {
        if (group.length < 2) continue;
        for (final e in group) {
          e.issues.add('duplicado');
          e.duplicados.addAll(
            group
                .where((x) => x.docId != e.docId)
                .map((x) => '${x.nombre} · ${x.ocupantes} ocupante(s)'),
          );
        }
      }

      final flagged = all.where((e) => e.issues.isNotEmpty).toList()
        ..sort((a, b) {
          final c = b.issues.length.compareTo(a.issues.length);
          return c != 0 ? c : a.nombre.compareTo(b.nombre);
        });

      final counts = <String, int>{};
      for (final e in flagged) {
        for (final code in e.issues) {
          counts[code] = (counts[code] ?? 0) + 1;
        }
      }

      if (!mounted) return;
      setState(() {
        _cargoSaludAreas = areasUnicas(
          areasSnap.docs.map(
            (a) => (
              id: _safe(a.data()['areaId']).isNotEmpty
                  ? _safe(a.data()['areaId'])
                  : a.id,
              nombre: a.data()['nombre']?.toString(),
            ),
          ),
          empresaId: empresaId,
        );
        _cargoSaludReport = _CargoHealthReport(
          total: cargosSnap.docs.length,
          entries: flagged,
          counts: counts,
          repairable: flagged.where(_needsAreaRepair).length,
          scannedAt: DateTime.now(),
        );
        _cargoSaludLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _cargoSaludLoading = false);
      _snack('Error al escanear cargos: $e');
    }
  }

  /// True si el cargo tiene un problema de ÁREA reparable automáticamente:
  /// se puede resolver el areaId por nombre y difiere del actual. Excluye los
  /// cargos marcados solo como duplicados (su área ya es correcta).
  bool _needsAreaRepair(_CargoHealthEntry e) {
    if (e.repairableAreaId == null) return false;
    if (e.repairableAreaId == e.areaId) return false;
    return e.issues.contains('sin_area_id') ||
        e.issues.contains('area_inexistente') ||
        e.issues.contains('desfase_area');
  }

  /// Rellena `areaId`/`areaNombre` en un cargo cuyo área sí resuelve por nombre.
  Future<void> _repairCargoArea(_CargoHealthEntry e) async {
    final newAreaId = e.repairableAreaId;
    if (newAreaId == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('TBL_CARGOS')
          .doc(e.docId)
          .update({
            'areaId': newAreaId,
            'areaNombre': e.repairableAreaNombre,
            'area': e.repairableAreaNombre,
            'updatedAt': FieldValue.serverTimestamp(),
          });
      _snack('Cargo "${e.nombre}" reparado (area: ${e.repairableAreaNombre}).');
      await _runCargoHealthScan();
    } catch (err) {
      _snack('Error al reparar: $err');
    }
  }

  /// Asigna el área a mano cuando el diagnóstico no puede deducirla.
  ///
  /// Es el caso de los cargos "Sin área": no tienen `areaId` ni nombre de
  /// área, así que no hay nada que resolver automáticamente. Antes el panel
  /// solo decía que fueras a Catálogos; ahora se elige aquí mismo.
  Future<void> _asignarAreaCargoManual(_CargoHealthEntry e) async {
    if (_cargoSaludAreas.isEmpty) {
      _snack(
        'La empresa no tiene áreas en TBL_AREAS. Créalas en Catálogos › Áreas.',
      );
      return;
    }
    var seleccion = _cargoSaludAreas
        .where((a) => a.contiene(e.areaId) || a.contiene(e.areaNombre))
        .firstOrNull
        ?.id;

    final elegido = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(
            'Área de "${e.nombre}"',
            style: const TextStyle(
              fontFamily: kArial,
              fontWeight: FontWeight.w800,
            ),
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'El cargo se ubicará en esta área y dejará de aparecer en '
                  'todas las áreas del desplegable de "Crear tarea".',
                  style: TextStyle(
                    fontFamily: kArial,
                    fontSize: 12,
                    color: kAdminMuted,
                  ),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: seleccion,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Área',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: _cargoSaludAreas
                      .map(
                        (a) => DropdownMenuItem(
                          value: a.id,
                          child: Text(
                            a.nombre,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontFamily: kArial),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setDialogState(() => seleccion = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: seleccion == null
                  ? null
                  : () => Navigator.pop(ctx, seleccion),
              child: const Text('Guardar área'),
            ),
          ],
        ),
      ),
    );
    if (elegido == null) return;

    final area = _cargoSaludAreas.firstWhere((a) => a.id == elegido);
    try {
      await FirebaseFirestore.instance
          .collection('TBL_CARGOS')
          .doc(e.docId)
          .update({
            'areaId': area.id,
            'areaNombre': area.nombre,
            'area': area.nombre,
            'updatedAt': FieldValue.serverTimestamp(),
          });
      _snack('Cargo "${e.nombre}" quedó en el área ${area.nombre}.');
      await _runCargoHealthScan();
    } catch (err) {
      _snack('Error al guardar el área: $err');
    }
  }

  /// Repara en lote todos los cargos cuya área resuelve por nombre.
  Future<void> _repairAllCargoAreas() async {
    final report = _cargoSaludReport;
    if (report == null) return;
    final targets = report.entries.where(_needsAreaRepair).toList();
    if (targets.isEmpty) {
      _snack('No hay cargos reparables automáticamente.');
      return;
    }
    final ok = await _confirm(
      title: 'Reparar areaId de cargos',
      message:
          'Se asignará el areaId correcto a ${targets.length} cargo(s) cuyo '
          'nombre de área coincide con un área existente. Es seguro y no '
          'borra datos.',
    );
    if (!ok) return;

    setState(() => _cargoSaludLoading = true);
    try {
      final db = FirebaseFirestore.instance;
      WriteBatch batch = db.batch();
      var writes = 0;
      for (final e in targets) {
        batch.update(db.collection('TBL_CARGOS').doc(e.docId), {
          'areaId': e.repairableAreaId,
          'areaNombre': e.repairableAreaNombre,
          'area': e.repairableAreaNombre,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        writes++;
        if (writes >= 450) {
          await batch.commit();
          batch = db.batch();
          writes = 0;
        }
      }
      if (writes > 0) await batch.commit();
      _snack('${targets.length} cargo(s) reparados.');
      await _runCargoHealthScan();
    } catch (err) {
      if (mounted) setState(() => _cargoSaludLoading = false);
      _snack('Error al reparar en lote: $err');
    }
  }

  /// Abre el selector para unificar un grupo de cargos duplicados: el usuario
  /// elige cuál se CONSERVA; el resto se elimina y sus ocupantes se reasignan.
  Future<void> _openMergeDuplicateDialog(_CargoHealthEntry entry) async {
    final report = _cargoSaludReport;
    if (report == null) return;
    final group = report.entries
        .where((e) => e.roleKey.isNotEmpty && e.roleKey == entry.roleKey)
        .toList();
    if (group.length < 2) {
      _snack('No se encontró el grupo de duplicados.');
      return;
    }
    // Sugerencia por defecto: el que tiene más ocupantes.
    group.sort((a, b) => b.ocupantes.compareTo(a.ocupantes));
    var survivorId = group.first.docId;

    final chosen = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text(
            'Unificar cargos duplicados',
            style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Elige el cargo que se CONSERVA. Los demás se eliminan y sus '
                  'ocupantes se reasignan al elegido. Recomendado: conservar el '
                  'que ya tiene ocupantes.',
                  style: TextStyle(fontFamily: kArial, fontSize: 12),
                ),
                const SizedBox(height: 12),
                ...group.map(
                  (e) => RadioListTile<String>(
                    value: e.docId,
                    groupValue: survivorId,
                    onChanged: (v) => setLocal(() => survivorId = v!),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      e.nombre,
                      style: const TextStyle(
                        fontFamily: kArial,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      '${e.ocupantes} ocupante(s)  ·  ${e.docId}',
                      style: const TextStyle(
                        fontFamily: kArial,
                        fontSize: 11,
                        color: kAdminMuted,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                'Cancelar',
                style: TextStyle(fontFamily: kArial),
              ),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: kAdminPrimary,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(ctx, survivorId),
              icon: const Icon(Icons.merge_type, size: 18),
              label: const Text(
                'Unificar',
                style: TextStyle(
                  fontFamily: kArial,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (chosen == null) return;
    final survivor = group.firstWhere((e) => e.docId == chosen);
    final losers = group.where((e) => e.docId != chosen).toList();
    final totalMove = losers.fold<int>(0, (s, e) => s + e.ocupantes);

    final ok = await _confirm(
      title: 'Confirmar unificación',
      message:
          'Se conservará "${survivor.nombre}".\n'
          'Se eliminarán ${losers.length} cargo(s) duplicado(s) y se '
          'reasignarán $totalMove ocupante(s) a "${survivor.nombre}".\n\n'
          'Esto modifica TBL_CARGOS, TBL_ESTRUCTURA_ORGANIZACIONAL y '
          'TBL_USUARIOS.',
    );
    if (!ok) return;
    await _mergeCargos(survivor: survivor, losers: losers);
  }

  /// Unifica cargos duplicados: mueve los ocupantes de [losers] al [survivor],
  /// repunta los cargos hijos y elimina los duplicados. Operación de escritura.
  Future<void> _mergeCargos({
    required _CargoHealthEntry survivor,
    required List<_CargoHealthEntry> losers,
  }) async {
    if (losers.isEmpty) return;
    final db = FirebaseFirestore.instance;
    final empresaId = widget.empresaId.trim();

    setState(() => _cargoSaludLoading = true);
    try {
      // 1) Reunir ocupantes de cada loser: array `cedulas` del cargo + docs de
      //    estructura cuyo `cargoId` apunte al loser (defensivo si está sin
      //    sincronizar).
      final cedulasByLoser = <String, Set<String>>{};
      for (final l in losers) {
        final ced = <String>{};
        final cargoSnap = await db.collection('TBL_CARGOS').doc(l.docId).get();
        for (final c in (cargoSnap.data()?['cedulas'] as List?) ?? const []) {
          final s = c?.toString().trim() ?? '';
          if (s.isNotEmpty) ced.add(s);
        }
        final estSnap = await db
            .collection('TBL_ESTRUCTURA_ORGANIZACIONAL')
            .where('cargoId', isEqualTo: l.docId)
            .get();
        for (final d in estSnap.docs) {
          final emp = _safe(d.data()['empresaId']);
          if (emp.isNotEmpty && emp != empresaId) continue;
          ced.add(d.id);
        }
        cedulasByLoser[l.docId] = ced;
      }

      WriteBatch batch = db.batch();
      var writes = 0;
      Future<void> flush() async {
        if (writes == 0) return;
        await batch.commit();
        batch = db.batch();
        writes = 0;
      }

      final touched = <String>{};
      for (final l in losers) {
        final cedulas = cedulasByLoser[l.docId] ?? <String>{};
        for (final cedula in cedulas) {
          // Construye el parche reasignando el cargo a `survivor`. El nivel
          // superior solo se toca si ya apuntaba al cargo eliminado, para no
          // pisar el cargo de otra empresa en usuarios multi-empresa; el
          // detalle de ESTA empresa siempre se actualiza.
          Map<String, dynamic> buildPatch(String currentTopCargoId) {
            final patch = <String, dynamic>{
              'empresasDetalle': {
                empresaId: {
                  'cargoId': survivor.docId,
                  'cargo': survivor.nombre,
                  'cargoNombre': survivor.nombre,
                },
              },
              'updatedAt': FieldValue.serverTimestamp(),
            };
            final top = currentTopCargoId.trim();
            if (top.isEmpty || top == l.docId) {
              patch['cargoId'] = survivor.docId;
              patch['cargo'] = survivor.nombre;
              patch['cargoNombre'] = survivor.nombre;
            }
            return patch;
          }

          final estRef = db
              .collection('TBL_ESTRUCTURA_ORGANIZACIONAL')
              .doc(cedula);
          final usrRef = db.collection('TBL_USUARIOS').doc(cedula);
          final estDoc = await estRef.get();
          final usrDoc = await usrRef.get();
          batch.set(
            estRef,
            buildPatch(_safe(estDoc.data()?['cargoId'])),
            SetOptions(merge: true),
          );
          writes++;
          batch.set(
            usrRef,
            buildPatch(_safe(usrDoc.data()?['cargoId'])),
            SetOptions(merge: true),
          );
          writes++;
          touched.add(cedula);
          if (writes >= 400) await flush();
        }

        // Repuntar cargos hijos que reportaban al loser.
        final childrenSnap = await db
            .collection('TBL_CARGOS')
            .where('parent_cargo', isEqualTo: l.docId)
            .get();
        for (final ch in childrenSnap.docs) {
          batch.update(ch.reference, {
            'parent_cargo': survivor.docId,
            'parent_desc': survivor.nombre,
          });
          writes++;
          if (writes >= 400) await flush();
        }

        // Mover cédulas al survivor y eliminar el loser.
        if (cedulas.isNotEmpty) {
          batch.set(
            db.collection('TBL_CARGOS').doc(survivor.docId),
            {'cedulas': FieldValue.arrayUnion(cedulas.toList())},
            SetOptions(merge: true),
          );
          writes++;
        }
        batch.delete(db.collection('TBL_CARGOS').doc(l.docId));
        writes++;
        if (writes >= 400) await flush();
      }
      await flush();

      for (final c in touched) {
        UserDirectory.instance.invalidate(c);
      }

      _snack(
        'Unificación lista: ${losers.length} cargo(s) eliminado(s), '
        '${touched.length} persona(s) reasignada(s) a "${survivor.nombre}".',
      );
      await _runCargoHealthScan();
    } catch (err) {
      if (mounted) setState(() => _cargoSaludLoading = false);
      _snack('Error al unificar: $err');
    }
  }

  Widget _tabSaludCargos() {
    final report = _cargoSaludReport;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: const Color(0xFFEFF6FF),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFFBFDBFE)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.badge, color: kAdminAccent, size: 26),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Salud de cargos',
                        style: TextStyle(
                          fontFamily: kArial,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Diagnóstico de solo lectura del catálogo TBL_CARGOS de la '
                  'empresa activa (${_empresaNombre(widget.empresaId)}). '
                  'Un cargo sin "areaId" se cuela en TODAS las áreas del '
                  'desplegable de "Crear tarea". Puedes reparar los que tengan '
                  'un nombre de área válido con un clic.',
                  style: const TextStyle(
                    fontFamily: kArial,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: kAdminPrimary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _cargoSaludLoading ? null : _runCargoHealthScan,
            icon: _cargoSaludLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.search),
            label: Text(
              _cargoSaludLoading
                  ? 'Escaneando…'
                  : (report == null
                        ? 'Ejecutar diagnóstico'
                        : 'Volver a escanear'),
              style: const TextStyle(
                fontFamily: kArial,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
        if (report != null) ...[
          const SizedBox(height: 16),
          _cargoSaludResumen(report),
          const SizedBox(height: 12),
          if (report.repairable > 0) ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: kAdminSuccess,
                  side: const BorderSide(color: kAdminSuccess),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: _cargoSaludLoading ? null : _repairAllCargoAreas,
                icon: const Icon(Icons.auto_fix_high),
                label: Text(
                  'Reparar areaId de ${report.repairable} cargo(s)',
                  style: const TextStyle(
                    fontFamily: kArial,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (report.entries.isEmpty)
            Card(
              color: const Color(0xFFF0FDF4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Color(0xFFBBF7D0)),
              ),
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: kAdminSuccess),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Sin problemas. Todos los cargos tienen un área válida.',
                        style: TextStyle(fontFamily: kArial, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ..._cargoSaludCategorias
                .where((c) => (report.counts[c.code] ?? 0) > 0)
                .map((c) => _cargoSaludCategoriaCard(c, report)),
        ],
      ],
    );
  }

  Widget _cargoSaludResumen(_CargoHealthReport report) {
    final sano = report.total - report.entries.length;
    final hora =
        '${report.scannedAt.hour.toString().padLeft(2, '0')}:'
        '${report.scannedAt.minute.toString().padLeft(2, '0')}:'
        '${report.scannedAt.second.toString().padLeft(2, '0')}';
    return Card(
      color: kAdminCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: kAdminBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Cargos: ${report.total}  ·  con problemas: '
              '${report.entries.length}  ·  sin problemas: $sano',
              style: const TextStyle(
                fontFamily: kArial,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Reparables automáticamente: ${report.repairable}  ·  '
              'Último escaneo: $hora',
              style: const TextStyle(
                fontFamily: kArial,
                fontSize: 11,
                color: kAdminMuted,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _cargoSaludCategorias
                  .where((c) => (report.counts[c.code] ?? 0) > 0)
                  .map((c) {
                    final n = report.counts[c.code] ?? 0;
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: c.color.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: c.color.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(c.icon, size: 16, color: c.color),
                          const SizedBox(width: 6),
                          Text(
                            '$n',
                            style: TextStyle(
                              fontFamily: kArial,
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              color: c.color,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            c.label,
                            style: const TextStyle(
                              fontFamily: kArial,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    );
                  })
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cargoSaludCategoriaCard(_SaludCat cat, _CargoHealthReport report) {
    final entries = report.entries
        .where((e) => e.issues.contains(cat.code))
        .toList();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: kAdminCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: kAdminBorder),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: Icon(cat.icon, color: cat.color),
          title: Text(
            '${cat.label}  (${entries.length})',
            style: const TextStyle(
              fontFamily: kArial,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          subtitle: Text(
            cat.desc,
            style: const TextStyle(
              fontFamily: kArial,
              fontSize: 11,
              color: kAdminMuted,
            ),
          ),
          childrenPadding: EdgeInsets.zero,
          // Listado largo: de a 20 con paginador, no todo de golpe.
          children: [
            PagedListSection<_CargoHealthEntry>(
              items: entries,
              etiqueta: 'cargos',
              itemBuilder: (_, e, _) => _cargoSaludEntryTile(e),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cargoSaludEntryTile(_CargoHealthEntry e) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: kAdminBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            e.nombre.isEmpty ? '(sin nombre)' : e.nombre,
            style: const TextStyle(
              fontFamily: kArial,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'ID: ${e.docId}',
            style: const TextStyle(
              fontFamily: kArial,
              fontSize: 11,
              color: kAdminMuted,
            ),
          ),
          Text(
            'areaId: ${e.areaId.isEmpty ? '—' : e.areaId}   ·   '
            'área (nombre): ${e.areaNombre.isEmpty ? '—' : e.areaNombre}',
            style: const TextStyle(
              fontFamily: kArial,
              fontSize: 11,
              color: kAdminMuted,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: e.issues.map((code) {
              final c = _cargoSaludCategorias.firstWhere(
                (x) => x.code == code,
                orElse: () => _cargoSaludCategorias.first,
              );
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: c.color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  c.label,
                  style: TextStyle(
                    fontFamily: kArial,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: c.color,
                  ),
                ),
              );
            }).toList(),
          ),
          if (e.duplicados.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Mismo rol que: ${e.duplicados.join('  ·  ')}  '
              '(este tiene ${e.ocupantes} ocupante(s)).',
              style: const TextStyle(
                fontFamily: kArial,
                fontSize: 11,
                color: Color(0xFF0369A1),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              if (_needsAreaRepair(e))
                TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => _repairCargoArea(e),
                  icon: const Icon(Icons.auto_fix_high, size: 16),
                  label: Text(
                    'Asignar areaId → ${e.repairableAreaNombre}',
                    style: const TextStyle(fontFamily: kArial, fontSize: 12),
                  ),
                ),
              // Elegir el área a mano: el único camino cuando el cargo no
              // trae ni id ni nombre de área y no hay nada que deducir.
              if (e.issues.contains('sin_area') ||
                  e.issues.contains('area_inexistente') ||
                  e.issues.contains('sin_area_id'))
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF7C3AED),
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => _asignarAreaCargoManual(e),
                  icon: const Icon(Icons.edit_location_alt_outlined, size: 16),
                  label: const Text(
                    'Elegir área…',
                    style: TextStyle(fontFamily: kArial, fontSize: 12),
                  ),
                ),
              if (e.issues.contains('duplicado'))
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF0EA5E9),
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => _openMergeDuplicateDialog(e),
                  icon: const Icon(Icons.merge_type, size: 16),
                  label: const Text(
                    'Unificar duplicados…',
                    style: TextStyle(fontFamily: kArial, fontSize: 12),
                  ),
                ),
            ],
          ),
          if (!_needsAreaRepair(e) &&
              (e.issues.contains('area_inexistente') ||
                  e.issues.contains('sin_area')))
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Text(
                'No hay un área que deducir: elígela arriba, o créala primero '
                'en Catálogos › Áreas si todavía no existe.',
                style: TextStyle(
                  fontFamily: kArial,
                  fontSize: 11,
                  color: kAdminMuted,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// Lista canónica de módulos asignables (appId → etiqueta). Fuente única para
// el editor "Asignar módulos". Si se agrega un módulo nuevo, va aquí.
const List<({String id, String label})> _kAllModules = [
  (id: 'admindashboard', label: 'Administración'),
  (id: 'talentohumanodashboard', label: 'Talento Humano'),
  (id: 'gerenciadashboard', label: 'Gerencia'),
  (id: 'gestiondocumentaldashboard', label: 'Gestión de Correspondencia'),
  (id: kPlanillasPagoAppId, label: 'Planillas de Pago'),
  (id: 'nutriciondashboard', label: 'Nutrición'),
  (id: 'comprasdashboard', label: 'Compras'),
  (id: 'correodashboard', label: 'Correo'),
  (id: 'interventoriadashboard', label: 'Interventoría'),
  (id: 'facturaciondashboard', label: 'Facturación'),
  (id: 'rutasdashboard', label: 'Rutas'),
];

// ===================== Salud de usuarios: modelos =========================

/// Una categoría de problema detectable en el diagnóstico de usuarios.
class _SaludCat {
  final String code;
  final String label;
  final String desc;
  final IconData icon;
  final Color color;
  const _SaludCat(this.code, this.label, this.desc, this.icon, this.color);
}

const List<_SaludCat> _saludCategorias = [
  _SaludCat(
    'no_numerica',
    'Cédula no numérica',
    'El ID del documento contiene caracteres no numéricos (espacios, letras o puntos).',
    Icons.abc,
    Color(0xFFEF4444),
  ),
  _SaludCat(
    'mismatch_id',
    'Cédula ≠ ID del documento',
    'El campo "cedula" no coincide con el ID del documento del usuario.',
    Icons.compare_arrows,
    Color(0xFFF97316),
  ),
  _SaludCat(
    'longitud',
    'Longitud sospechosa',
    'La cédula tiene menos de 6 o más de 10 dígitos.',
    Icons.straighten,
    Color(0xFFF59E0B),
  ),
  _SaludCat(
    'ceros_cola',
    'Posible truncamiento (ceros al final)',
    'Termina en 3 o más ceros: firma típica de cédulas leídas como número en Excel (bug .0 / notación científica).',
    Icons.exposure_zero,
    Color(0xFFD97706),
  ),
  _SaludCat(
    'sin_empresa',
    'Sin empresa asignada',
    'El array "empresas" está vacío: el usuario no pertenece a ninguna empresa.',
    Icons.domain_disabled,
    Color(0xFF64748B),
  ),
  _SaludCat(
    'inconsistencia',
    'Inconsistencia de membresía',
    'Desfase entre "empresas", "empresasDetalle" y/o "empresaId".',
    Icons.rule,
    Color(0xFF8B5CF6),
  ),
  _SaludCat(
    'duplicado',
    'Posible duplicado (mismo nombre)',
    'El mismo nombre completo aparece en cédulas distintas.',
    Icons.content_copy,
    Color(0xFF0EA5E9),
  ),
];

/// Un usuario marcado por el diagnóstico, con la lista de problemas hallados.
class _UserHealthEntry {
  final String docId;
  final String cedulaField;
  final String nombre;
  final List<String> empresas;
  final String nameKey;
  final Set<String> issues;
  _UserHealthEntry({
    required this.docId,
    required this.cedulaField,
    required this.nombre,
    required this.empresas,
    required this.nameKey,
    required this.issues,
  });
}

/// Resultado completo de un escaneo de salud de usuarios.
class _UserHealthReport {
  final int total;
  final List<_UserHealthEntry> entries;
  final Map<String, int> counts;
  final DateTime scannedAt;
  const _UserHealthReport({
    required this.total,
    required this.entries,
    required this.counts,
    required this.scannedAt,
  });
}

// ===================== Salud de cargos: modelos ===========================

/// Categorías de problema detectables en el catálogo de cargos. Reusa
/// [_SaludCat] (mismo contrato visual que la salud de usuarios).
const List<_SaludCat> _cargoSaludCategorias = [
  _SaludCat(
    'sin_area_id',
    'Sin areaId (se filtra en todas las áreas)',
    'El cargo solo guarda el nombre del área, no su "areaId". El módulo de '
        'tareas lo muestra en TODAS las áreas. Reparable si el nombre coincide '
        'con un área existente.',
    Icons.link_off,
    Color(0xFFF97316),
  ),
  _SaludCat(
    'area_inexistente',
    'Área inexistente',
    'El cargo referencia un área (por id o nombre) que no existe en TBL_AREAS '
        'para esta empresa.',
    Icons.wrong_location,
    Color(0xFFEF4444),
  ),
  _SaludCat(
    'desfase_area',
    'areaId no coincide con el nombre',
    'El "areaId" del cargo apunta a un área distinta de la que indica su '
        'nombre de área.',
    Icons.compare_arrows,
    Color(0xFF8B5CF6),
  ),
  _SaludCat(
    'sin_area',
    'Sin área',
    'El cargo no tiene ni "areaId" ni nombre de área: imposible ubicarlo.',
    Icons.help_outline,
    Color(0xFF64748B),
  ),
  _SaludCat(
    'duplicado',
    'Cargo duplicado (mismo rol, nombre distinto)',
    'Hay más de un cargo para el mismo rol con nombres casi iguales '
        '(p. ej. "Dirección…" y "Director…", o "Coordinación…" y '
        '"Coordinador…"). Se repiten en el desplegable de tareas. Unifícalos '
        'en Gestión de Cargos: deja el que tiene ocupantes y borra el otro.',
    Icons.content_copy,
    Color(0xFF0EA5E9),
  ),
];

/// Un cargo marcado por el diagnóstico, con los problemas hallados y la
/// resolución de reparación cuando es posible.
class _CargoHealthEntry {
  final String docId;
  final String cargoId;
  final String nombre;
  final String areaId;
  final String areaNombre;
  final bool habilitado;

  /// Nº de cédulas asignadas a este cargo (ayuda a decidir cuál duplicado
  /// conservar: normalmente el que tiene ocupantes).
  final int ocupantes;
  final Set<String> issues;

  /// areaId resuelto por nombre de área (null si no se puede reparar solo).
  final String? repairableAreaId;
  final String repairableAreaNombre;

  /// Otros cargos con el mismo rol (nombre casi idéntico) en el catálogo.
  final List<String> duplicados;

  /// Clave normalizada de rol; agrupa los duplicados entre sí.
  final String roleKey;

  _CargoHealthEntry({
    required this.docId,
    required this.cargoId,
    required this.nombre,
    required this.areaId,
    required this.areaNombre,
    required this.habilitado,
    required this.ocupantes,
    required this.issues,
    required this.repairableAreaId,
    required this.repairableAreaNombre,
    required this.duplicados,
    required this.roleKey,
  });
}

/// Resultado completo de un escaneo de salud de cargos.
class _CargoHealthReport {
  final int total;
  final List<_CargoHealthEntry> entries;
  final Map<String, int> counts;
  final int repairable;
  final DateTime scannedAt;
  const _CargoHealthReport({
    required this.total,
    required this.entries,
    required this.counts,
    required this.repairable,
    required this.scannedAt,
  });
}
