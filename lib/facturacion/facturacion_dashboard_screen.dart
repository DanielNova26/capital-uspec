// lib/facturacion/facturacion_dashboard_screen.dart

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cross_file/cross_file.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/guarded_module_page.dart';
import '../utils/doc_preview.dart';
import '../widgets/internal_module_layout.dart';
import '../widgets/user_avatar.dart';
import 'facturacion_models.dart';
import 'facturacion_obligaciones_screen.dart';
import 'facturacion_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Paleta del módulo
// ─────────────────────────────────────────────────────────────────────────────

const Color _kPrimary = Color(0xFF0369A1); // Sky 700
const Color _kAccent = Color(0xFF38BDF8); // Sky 400
const Color _kGreen = Color(0xFF16A34A);
const Color _kRed = Color(0xFFDC2626);
const Color _kGrey = Color(0xFF94A3B8);
const Color _kBg = Color(0xFFF0F9FF); // Sky 50
const String _kFont = 'Arial';

int _facWebGridColumns(double width) {
  if (width >= 1680) return 5;
  if (width >= 1280) return 4;
  if (width >= 900) return 3;
  return 2;
}

// ─────────────────────────────────────────────────────────────────────────────
// Pantalla raíz del módulo
// ─────────────────────────────────────────────────────────────────────────────

class FacturacionDashboardScreen extends StatefulWidget {
  final String userId;
  final String empresaId;
  final bool developerOverride;

  const FacturacionDashboardScreen({
    super.key,
    required this.userId,
    required this.empresaId,
    this.developerOverride = false,
  });

  @override
  State<FacturacionDashboardScreen> createState() =>
      _FacturacionDashboardScreenState();
}

/// Destino operativo de una tarea de Facturación. Abre únicamente el
/// documento solicitado y conserva el período original de la observación.
class FacturacionDocumentUploadScreen extends StatelessWidget {
  final String userId;
  final String empresaId;
  final String establecimientoId;
  final String docTipo;
  final String mes;
  final String taskId;
  final DateTime? fechaLimite;

  const FacturacionDocumentUploadScreen({
    super.key,
    required this.userId,
    required this.empresaId,
    required this.establecimientoId,
    required this.docTipo,
    required this.mes,
    required this.taskId,
    this.fechaLimite,
  });

  @override
  Widget build(BuildContext context) => _EstablecimientoView(
    userId: userId,
    empresaId: empresaId,
    estId: establecimientoId,
    svc: FacturacionService(),
    initialDocTipo: docTipo,
    targetMes: mes,
    linkedTaskId: taskId,
    linkedDeadline: fechaLimite,
  );
}

class _FacturacionDashboardScreenState
    extends State<FacturacionDashboardScreen> {
  final FacturacionService _svc = FacturacionService();

  FacUserInfo? _userInfo;
  bool _loaded = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }

  Future<void> _loadUserInfo() async {
    if (mounted) {
      setState(() {
        _loaded = false;
        _loadError = null;
      });
    }
    try {
      final info = await _svc.getRolFac(widget.empresaId, widget.userId);
      if (mounted) {
        setState(() {
          _userInfo = info;
          _loaded = true;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _loadError = error.toString();
          _loaded = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GuardedModulePage(
      userIdentity: widget.userId,
      appId: kFacAppId,
      pageTitle: 'Facturación',
      fallbackEmpresaId: widget.empresaId,
      child: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
          ? _FacturacionAccessState(
              userId: widget.userId,
              empresaId: widget.empresaId,
              icon: Icons.cloud_off_outlined,
              title: 'No fue posible validar tu acceso',
              message:
                  'No se pudo consultar la configuración de Facturación. Intenta nuevamente para evitar abrir una vista incorrecta.',
              actionLabel: 'Reintentar',
              onAction: _loadUserInfo,
            )
          : _buildBody(),
    );
  }

  Widget _buildBody() {
    final info = _userInfo!;
    final mode = resolveFacAccessMode(
      info,
      developerOverride: widget.developerOverride,
    );

    if (mode == FacAccessMode.establishment) {
      return _EstablecimientoView(
        userId: widget.userId,
        empresaId: widget.empresaId,
        estId: info.establecimientoId!,
        svc: _svc,
      );
    }

    if (mode == FacAccessMode.missingEstablishment) {
      return _FacturacionAccessState(
        userId: widget.userId,
        empresaId: widget.empresaId,
        icon: Icons.location_off_outlined,
        title: 'Falta asignar el establecimiento',
        message:
            'Tu rol permite cargar documentos únicamente para un establecimiento, pero todavía no tienes un centro de costo asignado en esta empresa. Solicita la asignación al administrador.',
      );
    }

    if (mode == FacAccessMode.invalidRole) {
      return _FacturacionAccessState(
        userId: widget.userId,
        empresaId: widget.empresaId,
        icon: Icons.manage_accounts_outlined,
        title: 'Rol de Facturación no reconocido',
        message:
            'El rol "${info.rol}" no corresponde a Gestión, Establecimiento o Visor. El administrador debe corregir la asignación antes de continuar.',
      );
    }

    // Tener el módulo asignado sin un rol especializado concede consulta.
    return _FacturacionView(
      userId: widget.userId,
      empresaId: widget.empresaId,
      canManage: mode == FacAccessMode.manager,
      svc: _svc,
    );
  }
}

class _FacturacionAccessState extends StatelessWidget {
  final String userId;
  final String empresaId;
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _FacturacionAccessState({
    required this.userId,
    required this.empresaId,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return InternalModuleLayout(
      title: 'Facturación',
      accentColor: _kPrimary,
      userId: userId,
      empresaId: empresaId,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Card(
            margin: const EdgeInsets.all(20),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 52, color: _kPrimary),
                  const SizedBox(height: 14),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: _kFont,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: _kFont,
                      fontSize: 13,
                      height: 1.45,
                      color: Colors.black54,
                    ),
                  ),
                  if (onAction != null && actionLabel != null) ...[
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: onAction,
                      icon: const Icon(Icons.refresh),
                      label: Text(actionLabel!),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Vista de Facturación (rol facturacion / visor)
// ─────────────────────────────────────────────────────────────────────────────

class _FacturacionView extends StatefulWidget {
  final String userId;
  final String empresaId;
  final bool canManage;
  final FacturacionService svc;

  const _FacturacionView({
    required this.userId,
    required this.empresaId,
    required this.canManage,
    required this.svc,
  });

  @override
  State<_FacturacionView> createState() => _FacturacionViewState();
}

class _FacturacionViewState extends State<_FacturacionView>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  final TextEditingController _buscarEstCtrl = TextEditingController();

  // Filtros del dashboard
  String? _filtroMes;
  String? _filtroDoc;
  String? _filtroEstado; // 'subido' | 'faltante' | 'ignorado'
  String _filtroEstablecimiento = '';
  bool _loadingProgreso = false;
  List<FacProgresoEst> _progreso = [];
  List<FacEstablecimiento> _ests = [];
  List<FacObligacion> _obligaciones = [];

  // Meses ofrecidos en el filtro. Son la unión de dos fuentes: el catálogo que
  // Facturación va asignando (histórico, no se pierde al reasignar) y el mes
  // vigente de cada establecimiento (respaldo para empresas sin catálogo aún).
  List<String> _meses = [];
  List<String> _mesesCatalogo = [];
  List<String> _mesesEst = [];

  StreamSubscription<List<FacEstablecimiento>>? _estSub;
  StreamSubscription<List<FacObligacion>>? _obligacionSub;
  StreamSubscription<List<String>>? _mesesSub;

  List<String> get _documentos => _obligaciones
      .where((item) => item.enabled)
      .map((item) => item.nombre)
      .toList();

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: widget.canManage ? 5 : 2, vsync: this);
    _obligacionSub = widget.svc.streamObligaciones(widget.empresaId).listen((
      items,
    ) {
      if (!mounted) return;
      setState(() {
        _obligaciones = items;
        if (_filtroDoc != null && !_documentos.contains(_filtroDoc)) {
          _filtroDoc = null;
          _filtroEstado = null;
        }
      });
      _recargarProgreso();
    });
    _estSub = widget.svc
        .streamEstablecimientos(widget.empresaId)
        .listen(_onEstsChanged);
    _mesesSub = widget.svc.streamMesesAsignados(widget.empresaId).listen((
      meses,
    ) {
      if (!mounted) return;
      _mesesCatalogo = meses;
      _recomputarMeses();
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    _buscarEstCtrl.dispose();
    _estSub?.cancel();
    _obligacionSub?.cancel();
    _mesesSub?.cancel();
    super.dispose();
  }

  void _onEstsChanged(List<FacEstablecimiento> ests) {
    final mesesSet = <String>{};
    for (final e in ests) {
      if (e.mes.isNotEmpty && e.mes != 'Sin asignar') {
        mesesSet.add(normalizeFacMesKey(e.mes));
      }
    }
    _ests = ests;
    _mesesEst = mesesSet.toList()..sort(compareFacMesDesc);
    _recomputarMeses();
    _sembrarCatalogoMeses();
  }

  /// Une catálogo y meses vigentes, y reencuadra el filtro si el mes elegido
  /// dejó de existir. No dispara escrituras: solo recalcula la lista visible.
  void _recomputarMeses() {
    final meses = normalizeFacMesKeys([..._mesesCatalogo, ..._mesesEst]);
    if (!mounted) return;
    setState(() {
      _meses = meses;
      if (meses.isEmpty) {
        _filtroMes = null;
      } else if (_filtroMes == null || !meses.contains(_filtroMes)) {
        _filtroMes = meses.first;
      }
    });
    _recargarProgreso();
  }

  /// Empresas que ya venían operando no tienen catálogo todavía. La primera
  /// carga lo siembra con los meses vigentes para no arrancar con la lista
  /// vacía; después el catálogo manda y sobrevive a las reasignaciones.
  void _sembrarCatalogoMeses() {
    if (!widget.canManage) return;
    final faltantes = _mesesEst
        .where((m) => !_mesesCatalogo.contains(m))
        .toList();
    if (faltantes.isEmpty) return;
    widget.svc
        .registrarMesesAsignados(widget.empresaId, faltantes)
        .catchError((_) {});
  }

  Future<void> _recargarProgreso() async {
    if (_ests.isEmpty || _filtroMes == null) {
      if (mounted) {
        setState(() {
          _progreso = [];
          _loadingProgreso = false;
        });
      }
      return;
    }
    setState(() => _loadingProgreso = true);
    final prog = await widget.svc.calcularProgreso(
      widget.empresaId,
      _ests,
      _filtroMes!,
      documentos: _documentos,
    );
    if (mounted) {
      setState(() {
        _progreso = prog;
        _loadingProgreso = false;
      });
    }
  }

  List<FacProgresoEst> get _progresoFiltrado {
    var list = _progreso;
    final texto = _filtroEstablecimiento.trim().toLowerCase();
    if (texto.isNotEmpty) {
      list = list
          .where(
            (p) =>
                p.establecimiento.nombre.toLowerCase().contains(texto) ||
                p.establecimiento.id.toLowerCase().contains(texto),
          )
          .toList();
    }
    if (_filtroDoc != null && _filtroEstado != null) {
      list = list.where((p) {
        final isIgnored = p.establecimiento.ignoredDocs[_filtroDoc!] ?? false;
        final isUploaded = p.docSubido[_filtroDoc!] ?? false;
        if (_filtroEstado == 'ignorado') return isIgnored;
        if (_filtroEstado == 'subido') return !isIgnored && isUploaded;
        if (_filtroEstado == 'faltante') return !isIgnored && !isUploaded;
        return true;
      }).toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [
      const InternalModuleTabItem(
        label: 'Establecimientos',
        icon: Icons.apartment_rounded,
      ),
      if (widget.canManage)
        const InternalModuleTabItem(
          label: 'Cargar',
          icon: Icons.cloud_upload_outlined,
        ),
      const InternalModuleTabItem(
        label: 'Autorizaciones',
        icon: Icons.check_circle_outline_rounded,
      ),
      if (widget.canManage)
        const InternalModuleTabItem(
          label: 'Gestión',
          icon: Icons.settings_rounded,
        ),
      if (widget.canManage)
        const InternalModuleTabItem(
          label: 'Obligaciones',
          icon: Icons.fact_check_outlined,
        ),
    ];

    return InternalModuleLayout(
      title: 'Facturación',
      accentColor: _kPrimary,
      userId: widget.userId,
      empresaId: widget.empresaId,
      child: Column(
        children: [
          _buildTabBar(tabs),
          if (!widget.canManage)
            Container(
              width: double.infinity,
              color: const Color(0xFFE0F2FE),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: const Row(
                children: [
                  Icon(Icons.visibility_outlined, size: 17, color: _kPrimary),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Modo consulta: puedes revisar el avance y las autorizaciones, sin modificar la configuración ni borrar archivos.',
                      style: TextStyle(
                        fontFamily: _kFont,
                        fontSize: 12,
                        color: Color(0xFF075985),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _buildDashboardTab(),
                if (widget.canManage)
                  _CargaTab(
                    userId: widget.userId,
                    empresaId: widget.empresaId,
                    ests: _ests,
                    meses: _meses,
                    svc: widget.svc,
                  ),
                _AutorizacionesTab(
                  empresaId: widget.empresaId,
                  svc: widget.svc,
                  canManage: widget.canManage,
                ),
                if (widget.canManage)
                  _GestionTab(
                    userId: widget.userId,
                    empresaId: widget.empresaId,
                    ests: _ests,
                    documentos: _documentos,
                    svc: widget.svc,
                  ),
                if (widget.canManage)
                  FacturacionObligacionesScreen(
                    empresaId: widget.empresaId,
                    service: widget.svc,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar(List<InternalModuleTabItem> tabs) {
    return Container(
      color: _kPrimary,
      child: TabBar(
        controller: _tab,
        indicatorColor: _kAccent,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white70,
        labelStyle: const TextStyle(
          fontFamily: _kFont,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
        tabs: tabs
            .map((t) => Tab(icon: Icon(t.icon, size: 18), text: t.label))
            .toList(),
      ),
    );
  }

  // ── Tab 1: Dashboard ───────────────────────────────────────────────────────

  Widget _buildDashboardTab() {
    final filtrados = _progresoFiltrado;
    return Column(
      children: [
        _buildFiltros(),
        if (!_loadingProgreso && _progreso.isNotEmpty) _buildResumen(filtrados),
        if (!_loadingProgreso && _progreso.isNotEmpty)
          _buildAvanceObligaciones(filtrados),
        Expanded(
          child: _loadingProgreso
              ? const Center(child: CircularProgressIndicator(color: _kPrimary))
              : filtrados.isEmpty
              ? _emptyState('Sin establecimientos para mostrar.')
              : RefreshIndicator(
                  onRefresh: _recargarProgreso,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: filtrados.length,
                    itemBuilder: (ctx, i) => _EstCard(
                      prog: filtrados[i],
                      onTap: () => _abrirDetalle(filtrados[i]),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildFiltros() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 230,
            child: TextField(
              controller: _buscarEstCtrl,
              decoration: _inputDeco('Buscar establecimiento').copyWith(
                prefixIcon: const Icon(Icons.search, size: 18),
                hintText: 'Nombre o código',
              ),
              style: const TextStyle(fontFamily: _kFont, fontSize: 13),
              onChanged: (value) =>
                  setState(() => _filtroEstablecimiento = value),
            ),
          ),
          // Mes
          SizedBox(
            width: 180,
            child: DropdownButtonFormField<String>(
              initialValue: _filtroMes,
              isExpanded: true,
              decoration: _inputDeco('Mes'),
              items: _meses
                  .map(
                    (m) => DropdownMenuItem(
                      value: m,
                      child: Text(
                        facMesLabel(m),
                        style: const TextStyle(
                          fontFamily: _kFont,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                setState(() => _filtroMes = v);
                _recargarProgreso();
              },
            ),
          ),
          // Documento
          SizedBox(
            width: 200,
            child: DropdownButtonFormField<String>(
              initialValue: _filtroDoc,
              isExpanded: true,
              decoration: _inputDeco('Documento'),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text(
                    'Todos',
                    style: TextStyle(fontFamily: _kFont, fontSize: 13),
                  ),
                ),
                ..._documentos.map(
                  (d) => DropdownMenuItem(
                    value: d,
                    child: Text(
                      d,
                      style: const TextStyle(fontFamily: _kFont, fontSize: 13),
                    ),
                  ),
                ),
              ],
              onChanged: (v) => setState(() {
                _filtroDoc = v;
                if (v == null) _filtroEstado = null;
              }),
            ),
          ),
          // Estado
          SizedBox(
            width: 140,
            child: DropdownButtonFormField<String>(
              initialValue: _filtroEstado,
              isExpanded: true,
              decoration: _inputDeco('Estado'),
              items: const [
                DropdownMenuItem(
                  value: null,
                  child: Text(
                    'Todos',
                    style: TextStyle(fontFamily: _kFont, fontSize: 13),
                  ),
                ),
                DropdownMenuItem(
                  value: 'subido',
                  child: Text(
                    'Subido',
                    style: TextStyle(fontFamily: _kFont, fontSize: 13),
                  ),
                ),
                DropdownMenuItem(
                  value: 'faltante',
                  child: Text(
                    'Faltante',
                    style: TextStyle(fontFamily: _kFont, fontSize: 13),
                  ),
                ),
                DropdownMenuItem(
                  value: 'ignorado',
                  child: Text(
                    'Ignorado',
                    style: TextStyle(fontFamily: _kFont, fontSize: 13),
                  ),
                ),
              ],
              onChanged: _filtroDoc == null
                  ? null
                  : (v) => setState(() => _filtroEstado = v),
            ),
          ),
          if (_filtroEstablecimiento.isNotEmpty ||
              _filtroDoc != null ||
              _filtroEstado != null)
            TextButton.icon(
              onPressed: () => setState(() {
                _buscarEstCtrl.clear();
                _filtroEstablecimiento = '';
                _filtroDoc = null;
                _filtroEstado = null;
              }),
              icon: const Icon(Icons.clear, size: 16),
              label: const Text(
                'Limpiar',
                style: TextStyle(fontFamily: _kFont),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildResumen(List<FacProgresoEst> filtrados) {
    final completos = filtrados.where((item) => item.completo).length;
    final pendientes = filtrados.length - completos;
    final promedio = filtrados.isEmpty
        ? 0
        : (filtrados.fold<double>(0, (total, item) => total + item.progreso) /
                  filtrados.length *
                  100)
              .round();

    return Container(
      width: double.infinity,
      color: const Color(0xFFF8FAFC),
      padding: const EdgeInsets.fromLTRB(16, 7, 16, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          _FacSummaryChip(
            icon: Icons.apartment_outlined,
            label: '${filtrados.length} visibles',
            color: _kPrimary,
          ),
          _FacSummaryChip(
            icon: Icons.check_circle_outline,
            label: '$completos completos',
            color: _kGreen,
          ),
          _FacSummaryChip(
            icon: Icons.pending_actions_outlined,
            label: '$pendientes pendientes',
            color: pendientes == 0 ? _kGreen : Colors.orange.shade800,
          ),
          _FacSummaryChip(
            icon: Icons.donut_large_outlined,
            label: '$promedio% promedio',
            color: _kPrimary,
          ),
        ],
      ),
    );
  }

  Widget _buildAvanceObligaciones(List<FacProgresoEst> establecimientos) {
    final avances = calcularAvanceObligaciones(_obligaciones, establecimientos);
    if (avances.isEmpty) return const SizedBox.shrink();
    return Container(
      height: 146,
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Cumplimiento por obligación · selecciona una para ver faltantes',
            style: TextStyle(
              fontFamily: _kFont,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 7),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: avances.length,
              separatorBuilder: (_, _) => const SizedBox(width: 9),
              itemBuilder: (context, index) {
                final item = avances[index];
                return InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => setState(() {
                    _filtroDoc = item.obligacion.nombre;
                    _filtroEstado = 'faltante';
                  }),
                  child: Container(
                    width: 238,
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFBAE6FD)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.obligacion.nombre,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: _kFont,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${item.cargados} de ${item.meta} cargados · ${item.faltantes} faltantes',
                          style: const TextStyle(
                            fontFamily: _kFont,
                            fontSize: 11,
                            color: Color(0xFF475569),
                          ),
                        ),
                        const SizedBox(height: 7),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: LinearProgressIndicator(
                            value: item.progreso,
                            minHeight: 9,
                            backgroundColor: const Color(0xFFE2E8F0),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              item.faltantes == 0 ? _kGreen : _kPrimary,
                            ),
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

  void _abrirDetalle(FacProgresoEst prog) {
    final estId = prog.establecimiento.id.startsWith('${widget.empresaId}_')
        ? prog.establecimiento.id.substring(widget.empresaId.length + 1)
        : prog.establecimiento.id;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _DetalleEstablecimientoScreen(
          userId: widget.userId,
          empresaId: widget.empresaId,
          estId: estId,
          estNombre: prog.establecimiento.nombre,
          mes: prog.establecimiento.mes,
          documentos: _documentos,
          canEdit: widget.canManage,
          svc: widget.svc,
        ),
      ),
    );
  }
}

class _FacSummaryChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _FacSummaryChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color.withValues(alpha: 0.22)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontFamily: _kFont,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Card de establecimiento en el dashboard
// ─────────────────────────────────────────────────────────────────────────────

class _EstCard extends StatelessWidget {
  final FacProgresoEst prog;
  final VoidCallback onTap;

  const _EstCard({required this.prog, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final e = prog.establecimiento;
    final pct = (prog.progreso * 100).round();
    final color = prog.completo ? _kGreen : (pct > 50 ? Colors.orange : _kRed);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withValues(alpha: 0.3)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      e.nombre,
                      style: const TextStyle(
                        fontFamily: _kFont,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  _StatusChip(pct: pct, color: color),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const SizedBox(width: 16),
                  Text(
                    '${prog.subidos} de ${prog.requeridos} docs · Mes: ${facMesLabel(e.mes)}',
                    style: const TextStyle(
                      fontFamily: _kFont,
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                  if (prog.ignorados > 0) ...[
                    const SizedBox(width: 8),
                    Text(
                      '· ${prog.ignorados} ignorados',
                      style: const TextStyle(
                        fontFamily: _kFont,
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: prog.progreso,
                  minHeight: 6,
                  backgroundColor: Colors.red.shade100,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
              if (e.fechaLimite != null) ...[
                const SizedBox(height: 6),
                _CountdownBadge(fechaLimite: e.fechaLimite!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final int pct;
  final Color color;
  const _StatusChip({required this.pct, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.4)),
    ),
    child: Text(
      '$pct%',
      style: TextStyle(
        fontFamily: _kFont,
        color: color,
        fontWeight: FontWeight.w700,
        fontSize: 12,
      ),
    ),
  );
}

class _CountdownBadge extends StatefulWidget {
  final DateTime fechaLimite;
  const _CountdownBadge({required this.fechaLimite});

  @override
  State<_CountdownBadge> createState() => _CountdownBadgeState();
}

class _CountdownBadgeState extends State<_CountdownBadge> {
  late Timer _timer;
  String _texto = '';
  Color _color = _kGreen;

  @override
  void initState() {
    super.initState();
    _update();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) _update();
    });
  }

  void _update() {
    final diff = widget.fechaLimite.difference(DateTime.now());
    if (diff.isNegative) {
      setState(() {
        _texto = 'Vencido';
        _color = _kRed;
      });
      _timer.cancel();
      return;
    }
    final d = diff.inDays;
    final h = diff.inHours % 24;
    final m = diff.inMinutes % 60;
    final s = diff.inSeconds % 60;
    setState(() {
      _texto =
          '$d d ${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
      _color = d >= 3 ? _kGreen : (d >= 1 ? Colors.orange : _kRed);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(Icons.timer_outlined, size: 13, color: _color),
      const SizedBox(width: 4),
      Text(
        _texto,
        style: TextStyle(fontFamily: _kFont, fontSize: 11, color: _color),
      ),
    ],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab Autorizaciones
// ─────────────────────────────────────────────────────────────────────────────

class _AutorizacionesTab extends StatelessWidget {
  final String empresaId;
  final FacturacionService svc;
  final bool canManage;

  const _AutorizacionesTab({
    required this.empresaId,
    required this.svc,
    required this.canManage,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FacAutorizacion>>(
      stream: svc.streamAutorizacionesPendientes(empresaId),
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: _kPrimary),
          );
        }
        final aut = snap.data ?? [];
        if (aut.isEmpty) {
          return _emptyState('No hay solicitudes pendientes.');
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: aut.length,
          itemBuilder: (_, i) => _AutCard(
            aut: aut[i],
            canManage: canManage,
            onAprobar: () => _aprobar(ctx, aut[i]),
            onDenegar: () => _denegar(ctx, aut[i]),
          ),
        );
      },
    );
  }

  Future<void> _aprobar(BuildContext ctx, FacAutorizacion a) async {
    final ok = await _confirm(
      ctx,
      '¿Aprobar cambio de mes de ${a.establecimientoNombre}?\n${facMesLabel(a.currentMes)} → ${facMesLabel(a.nextMes)}',
    );
    if (!ok) return;
    await svc.aprobarAutorizacion(a);
    if (ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(
          content: Text('Mes actualizado correctamente.'),
          backgroundColor: _kGreen,
        ),
      );
    }
  }

  Future<void> _denegar(BuildContext ctx, FacAutorizacion a) async {
    final ok = await _confirm(
      ctx,
      '¿Denegar la solicitud de ${a.establecimientoNombre}?',
    );
    if (!ok) return;
    await svc.denegarAutorizacion(a);
    if (ctx.mounted) {
      ScaffoldMessenger.of(
        ctx,
      ).showSnackBar(const SnackBar(content: Text('Solicitud denegada.')));
    }
  }
}

class _AutCard extends StatelessWidget {
  final FacAutorizacion aut;
  final bool canManage;
  final VoidCallback onAprobar;
  final VoidCallback onDenegar;

  const _AutCard({
    required this.aut,
    required this.canManage,
    required this.onAprobar,
    required this.onDenegar,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.apartment_rounded, size: 20, color: _kPrimary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    aut.establecimientoNombre,
                    style: const TextStyle(
                      fontFamily: _kFont,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
                Text(
                  DateFormat('dd/MM/yyyy HH:mm', 'es').format(aut.fecha),
                  style: const TextStyle(
                    fontFamily: _kFont,
                    fontSize: 11,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Solicita: ${facMesLabel(aut.currentMes)} → ${facMesLabel(aut.nextMes)}',
              style: const TextStyle(fontFamily: _kFont, fontSize: 13),
            ),
            if (aut.solicitanteNombre.isNotEmpty)
              Text(
                'Por: ${aut.solicitanteNombre}',
                style: const TextStyle(
                  fontFamily: _kFont,
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
            if (canManage) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onDenegar,
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text(
                        'Denegar',
                        style: TextStyle(fontFamily: _kFont),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _kRed,
                        side: const BorderSide(color: _kRed),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onAprobar,
                      icon: const Icon(Icons.check, size: 16),
                      label: const Text(
                        'Aprobar',
                        style: TextStyle(fontFamily: _kFont),
                      ),
                      style: FilledButton.styleFrom(backgroundColor: _kGreen),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab Gestión (solo facturación)
// ─────────────────────────────────────────────────────────────────────────────

class _GestionTab extends StatefulWidget {
  final String userId;
  final String empresaId;
  final List<FacEstablecimiento> ests;
  final List<String> documentos;
  final FacturacionService svc;

  const _GestionTab({
    required this.userId,
    required this.empresaId,
    required this.ests,
    required this.documentos,
    required this.svc,
  });

  @override
  State<_GestionTab> createState() => _GestionTabState();
}

class _GestionTabState extends State<_GestionTab> {
  // ── Asignar Mes ──────────────────────────────────────────────
  String? _mesEstId;
  String? _mesSel;
  String? _anioSel;

  // ── Fecha Límite por documento ────────────────────────────────
  String? _fechaEstId;
  String? _fechaDocTipo; // null = todos los documentos del establecimiento
  DateTime? _fechaSel;
  bool _guardandoFecha = false;

  // ── Observación por documento ─────────────────────────────────
  String? _obsEstId;
  String? _obsDocTipo; // null = general
  DateTime? _obsFechaLimite;
  final _obsCtrl = TextEditingController();
  bool _enviandoObs = false;

  @override
  void initState() {
    super.initState();
    _mesSel = kMeses[DateTime.now().month - 1];
    _anioSel = DateTime.now().year.toString();
  }

  @override
  void dispose() {
    _obsCtrl.dispose();
    super.dispose();
  }

  String _estIdOf(FacEstablecimiento e) =>
      e.id.startsWith('${widget.empresaId}_')
      ? e.id.substring(widget.empresaId.length + 1)
      : e.id;

  List<DropdownMenuItem<String>> get _estItemsTodos => [
    const DropdownMenuItem(
      value: 'todos',
      child: Text(
        'Todos los establecimientos',
        style: TextStyle(fontFamily: _kFont, fontSize: 13),
      ),
    ),
    ...widget.ests.map(
      (e) => DropdownMenuItem(
        value: _estIdOf(e),
        child: Text(
          e.nombre,
          style: const TextStyle(fontFamily: _kFont, fontSize: 13),
        ),
      ),
    ),
  ];

  List<DropdownMenuItem<String>> get _estItemsSolo => widget.ests
      .map(
        (e) => DropdownMenuItem(
          value: _estIdOf(e),
          child: Text(
            e.nombre,
            style: const TextStyle(fontFamily: _kFont, fontSize: 13),
          ),
        ),
      )
      .toList();

  List<DropdownMenuItem<String?>> get _docItems => [
    const DropdownMenuItem<String?>(
      value: null,
      child: Text(
        'Todos los documentos',
        style: TextStyle(fontFamily: _kFont, fontSize: 13),
      ),
    ),
    ...widget.documentos.map(
      (d) => DropdownMenuItem<String?>(
        value: d,
        child: Text(
          d,
          style: const TextStyle(fontFamily: _kFont, fontSize: 13),
        ),
      ),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 700;
    return SingleChildScrollView(
      padding: EdgeInsets.all(isWide ? 20 : 12),
      child: Column(
        children: [
          _card(
            color: _kPrimary,
            icon: Icons.calendar_month_rounded,
            titulo: 'Asignar Mes',
            child: _buildAsignarMes(isWide),
          ),
          const SizedBox(height: 14),
          _card(
            color: Colors.orange.shade700,
            icon: Icons.timer_rounded,
            titulo: 'Fecha Límite por Documento',
            subtitle: 'Define hasta cuándo puede subirse cada documento',
            child: _buildAsignarFecha(isWide),
          ),
          const SizedBox(height: 14),
          _card(
            color: _kGreen,
            icon: Icons.comment_rounded,
            titulo: 'Observación por Documento',
            subtitle: 'Se envía notificación al establecimiento',
            child: _buildObservacion(isWide),
          ),
        ],
      ),
    );
  }

  Widget _card({
    required Color color,
    required IconData icon,
    required String titulo,
    String? subtitle,
    required Widget child,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(14),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 18, color: color),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        style: TextStyle(
                          fontFamily: _kFont,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: color,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle,
                          style: const TextStyle(
                            fontFamily: _kFont,
                            fontSize: 11,
                            color: Colors.black54,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(padding: const EdgeInsets.all(16), child: child),
        ],
      ),
    );
  }

  // ─── Asignar Mes ──────────────────────────────────────────────────────────

  Widget _buildAsignarMes(bool isWide) {
    final anos = List.generate(
      6,
      (i) => (DateTime.now().year - 1 + i).toString(),
    );
    return Column(
      children: [
        DropdownButtonFormField<String>(
          initialValue: _mesEstId,
          decoration: _inputDeco('Establecimiento'),
          items: _estItemsTodos,
          onChanged: (v) => setState(() => _mesEstId = v),
        ),
        const SizedBox(height: 10),
        if (isWide)
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _mesSel,
                  decoration: _inputDeco('Mes'),
                  items: kMeses
                      .map(
                        (m) => DropdownMenuItem(
                          value: m,
                          child: Text(
                            m,
                            style: const TextStyle(
                              fontFamily: _kFont,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _mesSel = v),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _anioSel,
                  decoration: _inputDeco('Año'),
                  items: anos
                      .map(
                        (a) => DropdownMenuItem(
                          value: a,
                          child: Text(
                            a,
                            style: const TextStyle(
                              fontFamily: _kFont,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _anioSel = v),
                ),
              ),
            ],
          )
        else ...[
          DropdownButtonFormField<String>(
            initialValue: _mesSel,
            decoration: _inputDeco('Mes'),
            items: kMeses
                .map(
                  (m) => DropdownMenuItem(
                    value: m,
                    child: Text(
                      m,
                      style: const TextStyle(fontFamily: _kFont, fontSize: 13),
                    ),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => _mesSel = v),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _anioSel,
            decoration: _inputDeco('Año'),
            items: anos
                .map(
                  (a) => DropdownMenuItem(
                    value: a,
                    child: Text(
                      a,
                      style: const TextStyle(fontFamily: _kFont, fontSize: 13),
                    ),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => _anioSel = v),
          ),
        ],
        const SizedBox(height: 12),
        _actionBtn(
          'Asignar Mes',
          Icons.check_rounded,
          _kPrimary,
          _onAsignarMes,
        ),
      ],
    );
  }

  Future<void> _onAsignarMes() async {
    if (_mesSel == null || _anioSel == null) return;
    final mes = '${_mesSel}_$_anioSel';
    final ids = (_mesEstId == null || _mesEstId == 'todos')
        ? widget.ests.map(_estIdOf).toList()
        : [_mesEstId!];
    if (ids.isEmpty) return;
    await widget.svc.setMes(widget.empresaId, ids, mes);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Mes ${facMesLabel(mes)} asignado.'),
          backgroundColor: _kGreen,
        ),
      );
    }
  }

  // ─── Fecha Límite por documento ───────────────────────────────────────────

  Widget _buildAsignarFecha(bool isWide) {
    return Column(
      children: [
        if (isWide)
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _fechaEstId,
                  decoration: _inputDeco('Establecimiento'),
                  items: _estItemsTodos,
                  onChanged: (v) => setState(() => _fechaEstId = v),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String?>(
                  initialValue: _fechaDocTipo,
                  decoration: _inputDeco('Documento'),
                  items: _docItems,
                  onChanged: (v) => setState(() => _fechaDocTipo = v),
                ),
              ),
            ],
          )
        else ...[
          DropdownButtonFormField<String>(
            initialValue: _fechaEstId,
            decoration: _inputDeco('Establecimiento'),
            items: _estItemsTodos,
            onChanged: (v) => setState(() => _fechaEstId = v),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String?>(
            initialValue: _fechaDocTipo,
            decoration: _inputDeco('Documento'),
            items: _docItems,
            onChanged: (v) => setState(() => _fechaDocTipo = v),
          ),
        ],
        const SizedBox(height: 10),
        InkWell(
          onTap: _pickFechaHora,
          borderRadius: BorderRadius.circular(8),
          child: InputDecorator(
            decoration: _inputDeco('Fecha y hora límite'),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _fechaSel == null
                        ? 'Seleccionar fecha y hora'
                        : DateFormat(
                            'dd/MM/yyyy HH:mm',
                            'es',
                          ).format(_fechaSel!),
                    style: TextStyle(
                      fontFamily: _kFont,
                      fontSize: 13,
                      color: _fechaSel == null ? Colors.grey : Colors.black87,
                    ),
                  ),
                ),
                Icon(
                  Icons.calendar_today_rounded,
                  size: 16,
                  color: _fechaSel == null
                      ? Colors.grey
                      : Colors.orange.shade700,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _actionBtn(
          _guardandoFecha ? 'Guardando…' : 'Asignar Fecha Límite',
          Icons.check_rounded,
          Colors.orange.shade700,
          _guardandoFecha ? null : _onAsignarFecha,
        ),
      ],
    );
  }

  Future<void> _pickFechaHora() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _fechaSel ?? now,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: DateTime(now.year + 5),
      builder: (ctx, child) => Theme(
        data: ThemeData(
          colorScheme: ColorScheme.light(primary: Colors.orange.shade700),
        ),
        child: child!,
      ),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_fechaSel ?? now),
    );
    if (time == null || !mounted) return;
    setState(() {
      _fechaSel = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _onAsignarFecha() async {
    if (_fechaSel == null) {
      _snackError('Selecciona fecha y hora.');
      return;
    }
    setState(() => _guardandoFecha = true);
    final ids = (_fechaEstId == null || _fechaEstId == 'todos')
        ? widget.ests.map(_estIdOf).toList()
        : [_fechaEstId!];
    if (ids.isEmpty) {
      setState(() => _guardandoFecha = false);
      return;
    }

    if (_fechaDocTipo == null) {
      // Fecha límite general del establecimiento
      await widget.svc.setFechaLimite(widget.empresaId, ids, _fechaSel!);
    } else {
      // Fecha límite por documento específico
      for (final estId in ids) {
        await widget.svc.setDeadlineDoc(
          widget.empresaId,
          estId,
          _fechaDocTipo!,
          _fechaSel,
        );
      }
    }

    if (mounted) {
      setState(() => _guardandoFecha = false);
      final docLabel = _fechaDocTipo == null
          ? 'establecimiento'
          : '"$_fechaDocTipo"';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Fecha límite para $docLabel: ${DateFormat('dd/MM/yyyy HH:mm', 'es').format(_fechaSel!)}',
          ),
          backgroundColor: _kGreen,
        ),
      );
    }
  }

  // ─── Observación por documento ────────────────────────────────────────────

  Widget _buildObservacion(bool isWide) {
    return Column(
      children: [
        if (isWide)
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _obsEstId,
                  decoration: _inputDeco('Establecimiento'),
                  items: _estItemsSolo,
                  onChanged: (v) => setState(() => _obsEstId = v),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String?>(
                  initialValue: _obsDocTipo,
                  decoration: _inputDeco('Documento'),
                  items: _docItems,
                  onChanged: (v) => setState(() => _obsDocTipo = v),
                ),
              ),
            ],
          )
        else ...[
          DropdownButtonFormField<String>(
            initialValue: _obsEstId,
            decoration: _inputDeco('Establecimiento'),
            items: _estItemsSolo,
            onChanged: (v) => setState(() => _obsEstId = v),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String?>(
            initialValue: _obsDocTipo,
            decoration: _inputDeco('Documento'),
            items: _docItems,
            onChanged: (v) => setState(() => _obsDocTipo = v),
          ),
        ],
        const SizedBox(height: 10),
        // Preview del tag de documento
        if (_obsDocTipo != null)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _kGreen.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _kGreen.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.insert_drive_file_outlined,
                  size: 13,
                  color: _kGreen,
                ),
                const SizedBox(width: 6),
                Text(
                  'Documento: $_obsDocTipo',
                  style: const TextStyle(
                    fontFamily: _kFont,
                    fontSize: 12,
                    color: _kGreen,
                  ),
                ),
              ],
            ),
          ),
        if (_obsDocTipo != null) ...[
          InkWell(
            onTap: _pickObsFechaHora,
            borderRadius: BorderRadius.circular(8),
            child: InputDecorator(
              decoration: _inputDeco('Fecha y hora límite de la tarea'),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _obsFechaLimite == null
                          ? 'Seleccionar vencimiento'
                          : DateFormat(
                              'dd/MM/yyyy HH:mm',
                              'es',
                            ).format(_obsFechaLimite!),
                      style: TextStyle(
                        fontFamily: _kFont,
                        fontSize: 13,
                        color: _obsFechaLimite == null
                            ? Colors.grey
                            : Colors.black87,
                      ),
                    ),
                  ),
                  const Icon(Icons.event_outlined, size: 17, color: _kPrimary),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        TextField(
          controller: _obsCtrl,
          maxLines: 4,
          style: const TextStyle(fontFamily: _kFont, fontSize: 13),
          decoration: _inputDeco('Escribe la observación aquí…').copyWith(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 12),
        _actionBtn(
          _enviandoObs ? 'Enviando…' : 'Enviar Observación',
          Icons.send_rounded,
          _kGreen,
          _enviandoObs ? null : _onEnviarObs,
        ),
      ],
    );
  }

  Future<void> _onEnviarObs() async {
    final texto = _obsCtrl.text.trim();
    if (texto.isEmpty) {
      _snackError('Escribe una observación.');
      return;
    }
    if (_obsEstId == null) {
      _snackError('Selecciona un establecimiento.');
      return;
    }
    if (_obsDocTipo != null && _obsFechaLimite == null) {
      _snackError('Selecciona la fecha límite de la tarea.');
      return;
    }

    setState(() => _enviandoObs = true);

    final est = widget.ests.firstWhere(
      (e) => _estIdOf(e) == _obsEstId,
      orElse: () => widget.ests.first,
    );

    // Nombre del autor
    String autorNombre = widget.userId;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('TBL_USUARIOS')
          .doc(widget.userId)
          .get();
      if (snap.exists) {
        final d = snap.data()!;
        autorNombre = (d['nombre'] ?? d['name'] ?? widget.userId).toString();
      }
    } catch (_) {}

    try {
      final recipient = await widget.svc.findEstablishmentRecipient(
        widget.empresaId,
        _obsEstId!,
      );
      if (recipient == null) {
        throw StateError(
          'No hay un usuario con rol Establecimiento asignado a ${est.nombre}.',
        );
      }

      if (_obsDocTipo != null) {
        await widget.svc.addDocumentRequirement(
          empresaId: widget.empresaId,
          estId: _obsEstId!,
          establecimientoNombre: est.nombre,
          texto: texto,
          mes: est.mes,
          autorId: widget.userId,
          autorNombre: autorNombre,
          destinatario: recipient,
          docTipo: _obsDocTipo!,
          fechaLimite: _obsFechaLimite!,
        );
      } else {
        await widget.svc.addObservacion(
          empresaId: widget.empresaId,
          estId: _obsEstId!,
          establecimientoNombre: est.nombre,
          texto: texto,
          mes: est.mes,
          autorId: widget.userId,
          autorNombre: autorNombre,
          destinatarioId: recipient.userId,
        );
      }

      _obsCtrl.clear();
      if (mounted) {
        setState(() {
          _enviandoObs = false;
          _obsFechaLimite = null;
        });
        final docLabel = _obsDocTipo == null ? '' : ' sobre "$_obsDocTipo"';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _obsDocTipo == null
                  ? 'Observación general enviada con notificación.'
                  : 'Observación$docLabel enviada como tarea.',
            ),
            backgroundColor: _kGreen,
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _enviandoObs = false);
      _snackError(
        error is StateError
            ? error.message
            : 'No se pudo enviar la observación.',
      );
    }
  }

  Future<void> _pickObsFechaHora() async {
    final now = DateTime.now();
    final initial = _obsFechaLimite ?? now.add(const Duration(days: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 5),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;
    final selected = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    if (!selected.isAfter(now)) {
      _snackError('La fecha límite debe ser futura.');
      return;
    }
    setState(() => _obsFechaLimite = selected);
  }

  Widget _actionBtn(
    String label,
    IconData icon,
    Color color,
    VoidCallback? onPressed,
  ) => SizedBox(
    width: double.infinity,
    height: 42,
    child: FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(
        label,
        style: const TextStyle(fontFamily: _kFont, fontWeight: FontWeight.w600),
      ),
      style: FilledButton.styleFrom(
        backgroundColor: color,
        disabledBackgroundColor: color.withValues(alpha: 0.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
  );

  void _snackError(String msg) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: _kRed));
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab: Cargar documentos (perfil Facturación)
// Reutiliza la vista del establecimiento en modo embebido para no duplicar la
// lógica de subida, que ya está probada por el rol establecimiento.
// ─────────────────────────────────────────────────────────────────────────────

class _CargaTab extends StatefulWidget {
  final String userId;
  final String empresaId;
  final List<FacEstablecimiento> ests;
  final List<String> meses;
  final FacturacionService svc;

  const _CargaTab({
    required this.userId,
    required this.empresaId,
    required this.ests,
    required this.meses,
    required this.svc,
  });

  @override
  State<_CargaTab> createState() => _CargaTabState();
}

class _CargaTabState extends State<_CargaTab> {
  String? _estId;
  String? _mes;

  /// Los docs de establecimiento vienen con el id compuesto `empresa_centro`,
  /// pero Storage y el servicio trabajan con el id pelado.
  String _plainId(String id) => id.startsWith('${widget.empresaId}_')
      ? id.substring(widget.empresaId.length + 1)
      : id;

  @override
  void didUpdateWidget(covariant _CargaTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Si lo elegido desaparece del catálogo, se limpia: un DropdownButton con
    // un value que no está entre sus items revienta en tiempo de ejecución.
    if (_estId != null && !widget.ests.any((e) => _plainId(e.id) == _estId)) {
      _estId = null;
    }
    if (_mes != null && !widget.meses.contains(_mes)) _mes = null;
  }

  void _elegirEst(String? id) {
    if (id == null) return;
    setState(() {
      _estId = id;
      // Arranca en el mes vigente del establecimiento cuando está en el
      // catálogo; si no, deja que el usuario lo escoja.
      final est = widget.ests.firstWhere(
        (e) => _plainId(e.id) == id,
        orElse: () => widget.ests.first,
      );
      final propio = normalizeFacMesKey(est.mes);
      if (_mes == null && widget.meses.contains(propio)) _mes = propio;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 900;
    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: isWide ? 320 : double.infinity,
                child: DropdownButtonFormField<String>(
                  initialValue: _estId,
                  isExpanded: true,
                  decoration: _inputDeco('Establecimiento'),
                  items: widget.ests
                      .map(
                        (e) => DropdownMenuItem(
                          value: _plainId(e.id),
                          child: Text(
                            e.nombre,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: _kFont,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _elegirEst,
                ),
              ),
              SizedBox(
                width: isWide ? 200 : double.infinity,
                child: DropdownButtonFormField<String>(
                  initialValue: _mes,
                  isExpanded: true,
                  decoration: _inputDeco('Mes'),
                  items: widget.meses
                      .map(
                        (m) => DropdownMenuItem(
                          value: m,
                          child: Text(
                            facMesLabel(m),
                            style: const TextStyle(
                              fontFamily: _kFont,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _mes = v),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(child: _buildCuerpo()),
      ],
    );
  }

  Widget _buildCuerpo() {
    if (widget.meses.isEmpty) {
      return _aviso(
        Icons.event_busy_outlined,
        'Todavía no hay meses asignados',
        'Asigna un mes desde la pestaña Gestión para poder cargar documentos.',
      );
    }
    if (_estId == null || _mes == null) {
      return _aviso(
        Icons.cloud_upload_outlined,
        'Elige establecimiento y mes',
        'Al seleccionarlos aparecerán los documentos del período para cargarlos.',
      );
    }
    return _EstablecimientoView(
      // Remonta la vista al cambiar de establecimiento o de mes: su estado
      // (archivos, revisiones, observaciones) se carga en initState.
      key: ValueKey('$_estId|$_mes'),
      userId: widget.userId,
      empresaId: widget.empresaId,
      estId: _estId!,
      svc: widget.svc,
      targetMes: _mes,
      embedded: true,
      asFacturacion: true,
    );
  }

  Widget _aviso(IconData icon, String titulo, String detalle) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 46, color: Colors.black26),
          const SizedBox(height: 12),
          Text(
            titulo,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: _kFont,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            detalle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: _kFont,
              fontSize: 13,
              height: 1.4,
              color: Colors.black54,
            ),
          ),
        ],
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Pantalla detalle de un establecimiento (usada tanto por facturación como
// por el rol establecimiento)
// ─────────────────────────────────────────────────────────────────────────────

class _DetalleEstablecimientoScreen extends StatefulWidget {
  final String userId;
  final String empresaId;
  final String estId;
  final String estNombre;
  final String mes;
  final List<String> documentos;
  final bool canEdit; // facturación puede borrar; establecimiento puede subir
  final FacturacionService svc;

  const _DetalleEstablecimientoScreen({
    required this.userId,
    required this.empresaId,
    required this.estId,
    required this.estNombre,
    required this.mes,
    required this.documentos,
    required this.canEdit,
    required this.svc,
  });

  @override
  State<_DetalleEstablecimientoScreen> createState() =>
      _DetalleEstablecimientoScreenState();
}

class _DetalleEstablecimientoScreenState
    extends State<_DetalleEstablecimientoScreen> {
  Map<String, List<FacArchivo>> _archivos = {};
  FacEstablecimiento? _est;
  bool _loading = true;
  String? _selectedMes;
  List<String> _mesesDisponibles = [];
  List<FacObservacion> _observaciones = [];
  Map<String, FacRevision> _revisiones = {};
  StreamSubscription<List<FacObservacion>>? _obsSub;
  StreamSubscription<Map<String, FacRevision>>? _revisionSub;
  String _autorNombre = '';

  @override
  void initState() {
    super.initState();
    _selectedMes = widget.mes;
    _cargar();
    _listenRevisiones();
    _obsSub = widget.svc
        .streamObservaciones(widget.empresaId, widget.estId)
        .listen((obs) {
          if (mounted) setState(() => _observaciones = obs);
        });
    _loadAutor();
  }

  Future<void> _loadAutor() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('TBL_USUARIOS')
          .doc(widget.userId)
          .get();
      if (snap.exists && mounted) {
        final d = snap.data()!;
        setState(
          () => _autorNombre = (d['nombre'] ?? d['name'] ?? widget.userId)
              .toString(),
        );
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _obsSub?.cancel();
    _revisionSub?.cancel();
    super.dispose();
  }

  void _listenRevisiones() {
    _revisionSub?.cancel();
    _revisionSub = widget.svc
        .streamRevisiones(
          widget.empresaId,
          widget.estId,
          _selectedMes ?? widget.mes,
        )
        .listen((items) {
          if (mounted) setState(() => _revisiones = items);
        });
  }

  Future<void> _addObs(String doc, String texto, DateTime? fechaLimite) async {
    if (fechaLimite == null) {
      throw ArgumentError('Selecciona una fecha límite.');
    }
    final recipient = await widget.svc.findEstablishmentRecipient(
      widget.empresaId,
      widget.estId,
    );
    if (recipient == null) {
      throw StateError(
        'No hay un usuario con rol Establecimiento asignado a ${widget.estNombre}.',
      );
    }
    await widget.svc.addDocumentRequirement(
      empresaId: widget.empresaId,
      estId: widget.estId,
      establecimientoNombre: widget.estNombre,
      texto: texto,
      mes: _selectedMes ?? widget.mes,
      autorId: widget.userId,
      autorNombre: _autorNombre.isNotEmpty ? _autorNombre : widget.userId,
      docTipo: doc,
      destinatario: recipient,
      fechaLimite: fechaLimite,
    );
  }

  Future<void> _cargar() async {
    setState(() => _loading = true);
    final est = await widget.svc.getEstablecimiento(
      widget.empresaId,
      widget.estId,
    );
    // Cargar meses disponibles en Storage para este establecimiento
    final meses = await widget.svc.listMesesDisponibles(
      widget.empresaId,
      widget.estId,
    );
    final mesFinal = normalizeFacMesKey(_selectedMes ?? widget.mes);
    final archivos = await widget.svc.listArchivos(
      widget.empresaId,
      widget.estId,
      mesFinal,
      documentos: widget.documentos,
    );
    if (mounted) {
      setState(() {
        _est = est;
        _archivos = archivos;
        _selectedMes = mesFinal;
        // Firestore suele usar `Junio_2026` y Storage devuelve
        // `junio_2026`; ambas variantes representan el mismo período.
        _mesesDisponibles = normalizeFacMesKeys([
          if (est != null) est.mes,
          ...meses,
        ]);
        _loading = false;
      });
    }
  }

  Future<void> _cambiarMes(String? mes) async {
    if (mes == null) return;
    final normalizedMes = normalizeFacMesKey(mes);
    if (normalizedMes == normalizeFacMesKey(_selectedMes ?? '')) return;
    setState(() {
      _selectedMes = normalizedMes;
      _loading = true;
      _revisiones = {};
    });
    _listenRevisiones();
    final archivos = await widget.svc.listArchivos(
      widget.empresaId,
      widget.estId,
      normalizedMes,
      documentos: widget.documentos,
    );
    if (mounted) {
      setState(() {
        _archivos = archivos;
        _loading = false;
      });
    }
  }

  bool get _todoCompleto => widget.documentos.every((doc) {
    if (_est?.ignoredDocs[doc] == true) return true;
    return _archivos[doc]?.isNotEmpty ?? false;
  });

  int get _completados => widget.documentos.where((doc) {
    if (_est?.ignoredDocs[doc] == true) return true;
    return _archivos[doc]?.isNotEmpty ?? false;
  }).length;

  @override
  Widget build(BuildContext context) {
    final isWeb = MediaQuery.of(context).size.width >= 900;
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.estNombre,
              style: const TextStyle(
                fontFamily: _kFont,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
            Text(
              'Mes: ${facMesLabel(_selectedMes ?? widget.mes)}',
              style: const TextStyle(
                fontFamily: _kFont,
                fontSize: 11,
                color: Colors.white70,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.message_outlined),
            tooltip: 'Observaciones',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => _ObservacionesScreen(
                  userId: widget.userId,
                  empresaId: widget.empresaId,
                  estId: widget.estId,
                  estNombre: widget.estNombre,
                  svc: widget.svc,
                ),
              ),
            ),
          ),
          if (!_loading && _todoCompleto)
            IconButton(
              icon: const Icon(Icons.download_rounded),
              tooltip: 'Descargar ZIP del mes',
              onPressed: _descargarZip,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kPrimary))
          : Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _cargar,
                    child: isWeb ? _buildWebGrid() : _buildMobileGrid(),
                  ),
                ),
              ],
            ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildHeader() {
    final total = widget.documentos.length;
    final pct = total > 0 ? _completados / total : 1.0;
    final color = _todoCompleto ? _kGreen : (pct > 0.5 ? Colors.orange : _kRed);
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$_completados de $total documentos completados',
                style: const TextStyle(
                  fontFamily: _kFont,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (_est?.fechaLimite != null)
                _CountdownBadge(fechaLimite: _est!.fechaLimite!),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 8,
              backgroundColor: Colors.red.shade100,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWebGrid() {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final cols = _facWebGridColumns(constraints.maxWidth);
        return GridView.builder(
          padding: const EdgeInsets.all(10),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            mainAxisExtent: 310,
          ),
          itemCount: widget.documentos.length,
          itemBuilder: (_, i) => _docCardDetalle(widget.documentos[i]),
        );
      },
    );
  }

  Widget _buildMobileGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(10),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.55,
      ),
      itemCount: widget.documentos.length,
      itemBuilder: (_, i) => _docCardDetalle(widget.documentos[i]),
    );
  }

  Widget _docCardDetalle(String doc) => _DocCard(
    doc: doc,
    archivos: _archivos[doc] ?? [],
    isIgnored: _est?.ignoredDocs[doc] ?? false,
    deadline: _est?.deadlines[doc],
    canUpload: false,
    canDelete: widget.canEdit,
    onToggleIgnore: widget.canEdit ? () => _toggleIgnore(doc) : null,
    onView: _viewFile,
    onDelete: (archivo) => _deleteFile(doc, archivo),
    onUpload: null,
    observaciones: _observaciones.where((o) => o.docTipo == doc).toList(),
    onAddObservacion: widget.canEdit
        ? (texto, fechaLimite) => _addObs(doc, texto, fechaLimite)
        : null,
    observationCreatesTask: widget.canEdit,
    revision: _revisiones[doc],
    canReview: widget.canEdit,
    onApprove: widget.canEdit ? () => _approveDocument(doc) : null,
    onReject: widget.canEdit
        ? (motivo, fecha) => _rejectDocument(doc, motivo, fecha)
        : null,
  );

  Future<void> _approveDocument(String doc) async {
    final ok = await _confirm(context, '¿Aprobar definitivamente "$doc"?');
    if (!ok) return;
    try {
      await widget.svc.aprobarDocumento(
        empresaId: widget.empresaId,
        estId: widget.estId,
        establecimientoNombre: widget.estNombre,
        mes: _selectedMes ?? widget.mes,
        docTipo: doc,
        revisorId: widget.userId,
        revisorNombre: _autorNombre.isNotEmpty ? _autorNombre : widget.userId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$doc aprobado.'), backgroundColor: _kGreen),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No fue posible aprobar: $error'),
            backgroundColor: _kRed,
          ),
        );
      }
    }
  }

  Future<void> _rejectDocument(
    String doc,
    String motivo,
    DateTime fechaLimite,
  ) async {
    try {
      await widget.svc.rechazarDocumento(
        empresaId: widget.empresaId,
        estId: widget.estId,
        establecimientoNombre: widget.estNombre,
        mes: _selectedMes ?? widget.mes,
        docTipo: doc,
        motivo: motivo,
        fechaLimite: fechaLimite,
        revisorId: widget.userId,
        revisorNombre: _autorNombre.isNotEmpty ? _autorNombre : widget.userId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Documento rechazado. Se creó la corrección y el aviso automático.',
            ),
            backgroundColor: _kRed,
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No fue posible rechazar: $error'),
            backgroundColor: _kRed,
          ),
        );
      }
    }
  }

  Widget _buildBottomBar() {
    final mesActual = _selectedMes ?? widget.mes;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          if (_mesesDisponibles.length > 1) ...[
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _mesesDisponibles.contains(mesActual) ? mesActual : null,
                isDense: true,
                decoration: _inputDeco('Mes'),
                items: _mesesDisponibles
                    .map(
                      (m) => DropdownMenuItem(
                        value: m,
                        child: Text(
                          facMesLabel(m),
                          style: const TextStyle(
                            fontFamily: _kFont,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: _cambiarMes,
              ),
            ),
          ] else ...[
            Text(
              'Mes: ${facMesLabel(mesActual)}',
              style: const TextStyle(
                fontFamily: _kFont,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
          ],
          if (_todoCompleto) ...[
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: _descargarZip,
              icon: const Icon(Icons.download_rounded, size: 16),
              label: const Text('ZIP', style: TextStyle(fontFamily: _kFont)),
              style: FilledButton.styleFrom(backgroundColor: _kPrimary),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _toggleIgnore(String doc) async {
    final actual = _est?.ignoredDocs[doc] ?? false;
    await widget.svc.setIgnoredDoc(
      widget.empresaId,
      widget.estId,
      doc,
      !actual,
    );
    await _cargar();
  }

  Future<void> _viewFile(FacArchivo archivo) async {
    final uri = Uri.parse(archivo.downloadUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _deleteFile(String doc, FacArchivo archivo) async {
    final ok = await _confirm(context, '¿Borrar "${archivo.nombre}"?');
    if (!ok) return;
    await widget.svc.deleteArchivo(
      archivo.fullPath,
      empresaId: widget.empresaId,
      estId: widget.estId,
      mes: _selectedMes ?? widget.mes,
      docTipo: doc,
      actorId: widget.userId,
      actorNombre: _autorNombre,
    );
    await _cargar();
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Archivo borrado.')));
    }
  }

  Future<void> _descargarZip() async {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Generando ZIP…')));
    try {
      final bytes = await widget.svc.generarZip(
        widget.empresaId,
        widget.estId,
        _selectedMes ?? widget.mes,
      );
      final zipName =
          '${widget.estId}_${(_selectedMes ?? widget.mes).toLowerCase()}.zip';

      if (kIsWeb) {
        await FileSaver.instance.saveFile(
          name: zipName.replaceAll('.zip', ''),
          bytes: bytes,
          fileExtension: 'zip',
          mimeType: MimeType.zip,
        );
      } else {
        final dir = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/$zipName');
        await file.writeAsBytes(bytes);
        await OpenFilex.open(file.path);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ZIP descargado: $zipName'),
            backgroundColor: _kGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error generando ZIP: $e'),
            backgroundColor: _kRed,
          ),
        );
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Vista de rol Establecimiento (puede subir documentos)
// ─────────────────────────────────────────────────────────────────────────────

class _EstablecimientoView extends StatefulWidget {
  final String userId;
  final String empresaId;
  final String estId;
  final FacturacionService svc;
  final String? initialDocTipo;
  final String? targetMes;
  final String? linkedTaskId;
  final DateTime? linkedDeadline;

  /// Se monta dentro de otra pantalla (la pestaña Cargar de Facturación), así
  /// que no debe dibujar su propio InternalModuleLayout: quedarían dos.
  final bool embedded;

  /// Lo opera Facturación en nombre del establecimiento. Oculta "Solicitar
  /// siguiente mes", que es un trámite del establecimiento hacia Facturación
  /// y no tiene sentido cuando ese mismo perfil asigna el mes en Gestión.
  final bool asFacturacion;

  const _EstablecimientoView({
    super.key,
    required this.userId,
    required this.empresaId,
    required this.estId,
    required this.svc,
    this.initialDocTipo,
    this.targetMes,
    this.linkedTaskId,
    this.linkedDeadline,
    this.embedded = false,
    this.asFacturacion = false,
  });

  @override
  State<_EstablecimientoView> createState() => _EstablecimientoViewState();
}

class _EstablecimientoViewState extends State<_EstablecimientoView> {
  Map<String, List<FacArchivo>> _archivos = {};
  Map<String, FacRevision> _revisiones = {};
  List<String> _documentos = [];
  FacEstablecimiento? _est;
  bool _loading = true;
  bool _solicitando = false;
  List<FacObservacion> _observaciones = [];
  StreamSubscription<List<FacObservacion>>? _obsSub;
  StreamSubscription<Map<String, FacRevision>>? _revisionSub;
  String _autorNombre = '';

  bool get _isTaskFlow => (widget.linkedTaskId ?? '').trim().isNotEmpty;

  List<String> get _visibleDocs {
    final focus = (widget.initialDocTipo ?? '').trim();
    return focus.isNotEmpty ? <String>[focus] : _documentos;
  }

  String get _activeMes {
    final requested = (widget.targetMes ?? '').trim();
    return normalizeFacMesKey(
      requested.isNotEmpty ? requested : _est?.mes ?? '',
    );
  }

  @override
  void initState() {
    super.initState();
    _cargar();
    _obsSub = widget.svc
        .streamObservaciones(widget.empresaId, widget.estId)
        .listen((obs) {
          if (mounted) setState(() => _observaciones = obs);
        });
    _loadAutorNombre();
  }

  Future<void> _loadAutorNombre() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('TBL_USUARIOS')
          .doc(widget.userId)
          .get();
      if (snap.exists && mounted) {
        final d = snap.data()!;
        setState(
          () => _autorNombre = (d['nombre'] ?? d['name'] ?? widget.userId)
              .toString(),
        );
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _obsSub?.cancel();
    _revisionSub?.cancel();
    super.dispose();
  }

  void _listenRevisiones(String mes) {
    _revisionSub?.cancel();
    _revisionSub = widget.svc
        .streamRevisiones(widget.empresaId, widget.estId, mes)
        .listen((items) {
          if (mounted) setState(() => _revisiones = items);
        });
  }

  Future<void> _addObs(String doc, String texto) async {
    await widget.svc.addObservacion(
      empresaId: widget.empresaId,
      estId: widget.estId,
      establecimientoNombre: _est?.nombre ?? widget.estId,
      texto: texto,
      mes: _activeMes,
      autorId: widget.userId,
      autorNombre: _autorNombre.isNotEmpty ? _autorNombre : widget.userId,
      destinatarioId:
          '', // establecimiento responde, se notificará a facturación si se desea
      docTipo: doc,
    );
  }

  Future<void> _cargar() async {
    setState(() => _loading = true);
    final est = await widget.svc.getEstablecimiento(
      widget.empresaId,
      widget.estId,
    );
    final requestedMes = (widget.targetMes ?? '').trim();
    final mes = normalizeFacMesKey(
      requestedMes.isNotEmpty ? requestedMes : est?.mes ?? '',
    );
    List<String> documentos;
    try {
      documentos = (await widget.svc.getObligacionesActivas(
        widget.empresaId,
      )).map((item) => item.nombre).toList();
    } catch (_) {
      documentos = List<String>.from(kFacDocumentos);
    }
    final archivos = mes.isNotEmpty
        ? await widget.svc.listArchivos(
            widget.empresaId,
            widget.estId,
            mes,
            documentos: [
              ...documentos,
              if ((widget.initialDocTipo ?? '').trim().isNotEmpty &&
                  !documentos.contains(widget.initialDocTipo!.trim()))
                widget.initialDocTipo!.trim(),
            ],
          )
        : {};
    if (mounted) {
      setState(() {
        _est = est;
        _documentos = documentos;
        _archivos = Map<String, List<FacArchivo>>.from(archivos);
        _loading = false;
      });
      if (mes.isNotEmpty) _listenRevisiones(mes);
    }
  }

  bool get _todoCompleto => _visibleDocs.every((doc) {
    if (_est?.ignoredDocs[doc] == true) return true;
    return _archivos[doc]?.isNotEmpty ?? false;
  });

  int get _completados => _visibleDocs.where((doc) {
    if (_est?.ignoredDocs[doc] == true) return true;
    return _archivos[doc]?.isNotEmpty ?? false;
  }).length;

  @override
  Widget build(BuildContext context) {
    final isWeb = MediaQuery.of(context).size.width >= 900;

    final contenido = _loading
        ? const Center(child: CircularProgressIndicator(color: _kPrimary))
        : Column(
            children: [
              _buildHeader(),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _cargar,
                  child: isWeb ? _buildWebGrid() : _buildMobileGrid(),
                ),
              ),
              _buildBottomBar(),
            ],
          );

    if (widget.embedded) return contenido;

    return InternalModuleLayout(
      title: 'Facturación — ${_est?.nombre ?? widget.estId}',
      subtitle: _isTaskFlow
          ? 'Requerimiento: ${widget.initialDocTipo} · Mes: ${facMesLabel(_activeMes)}'
          : 'Mes: ${facMesLabel(_est?.mes ?? '…')}',
      accentColor: _kPrimary,
      userId: widget.userId,
      empresaId: widget.empresaId,
      child: contenido,
    );
  }

  Widget _buildHeader() {
    final total = _visibleDocs.length;
    final pct = total > 0 ? _completados / total : 1.0;
    final color = _todoCompleto ? _kGreen : (pct > 0.5 ? Colors.orange : _kRed);
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$_completados de $total documentos',
                style: const TextStyle(
                  fontFamily: _kFont,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if ((widget.linkedDeadline ?? _est?.fechaLimite) != null)
                _CountdownBadge(
                  fechaLimite: widget.linkedDeadline ?? _est!.fechaLimite!,
                ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 8,
              backgroundColor: Colors.red.shade100,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWebGrid() {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final cols = _facWebGridColumns(constraints.maxWidth);
        return GridView.builder(
          padding: const EdgeInsets.all(10),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            mainAxisExtent: 285,
          ),
          itemCount: _visibleDocs.length,
          itemBuilder: (_, i) => _buildDocCard(_visibleDocs[i]),
        );
      },
    );
  }

  Widget _buildMobileGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(10),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.6,
      ),
      itemCount: _visibleDocs.length,
      itemBuilder: (_, i) => _buildDocCard(_visibleDocs[i]),
    );
  }

  Widget _buildDocCard(String doc) => _DocCard(
    doc: doc,
    archivos: _archivos[doc] ?? [],
    isIgnored: _est?.ignoredDocs[doc] ?? false,
    deadline: _isTaskFlow ? widget.linkedDeadline : _est?.deadlines[doc],
    canUpload: true,
    canDelete: true,
    onToggleIgnore: null,
    onView: _viewFile,
    onDelete: _deleteFile,
    onUpload: () => _subirArchivo(doc),
    onDropped: (files) => _subirArchivosDropped(doc, files),
    observaciones: _observaciones.where((o) => o.docTipo == doc).toList(),
    onAddObservacion: (texto, _) => _addObs(doc, texto),
    revision: _revisiones[doc],
  );

  Future<void> _subirArchivosDropped(String doc, List<XFile> files) async {
    const allowed = {'pdf', 'jpg', 'jpeg', 'png', 'xls', 'xlsx', 'doc', 'docx'};
    final valid = files
        .where((f) => allowed.contains(f.name.split('.').last.toLowerCase()))
        .toList();
    if (valid.isEmpty) return;
    final uploadedPaths = <String>[];
    for (final file in valid) {
      final ext = file.name.split('.').last.toLowerCase();
      final bytes = await file.readAsBytes();
      final uploaded = await widget.svc.uploadArchivo(
        empresaId: widget.empresaId,
        estId: widget.estId,
        mes: _activeMes,
        doc: doc,
        bytes: bytes,
        extension: ext,
        uploaderId: widget.userId,
        uploaderNombre: _autorNombre,
      );
      uploadedPaths.add(uploaded.fullPath);
    }
    await _cargar();
    if (_isTaskFlow) {
      await widget.svc.submitDocumentTaskForReview(
        taskId: widget.linkedTaskId!,
        byUserId: widget.userId,
        byName: _autorNombre.isNotEmpty ? _autorNombre : widget.userId,
        docTipo: doc,
        storagePaths: uploadedPaths,
      );
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isTaskFlow
                ? '${valid.length} archivo(s) subidos y enviados a revisión.'
                : '${valid.length} archivo(s) subidos para "$doc".',
          ),
          backgroundColor: _kGreen,
        ),
      );
    }
  }

  Widget _buildBottomBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          // Botón de observaciones con badge
          StreamBuilder<List<FacObservacion>>(
            stream: widget.svc.streamObservaciones(
              widget.empresaId,
              widget.estId,
            ),
            builder: (ctx, snap) {
              final count = snap.data?.length ?? 0;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    icon: const Icon(Icons.message_outlined, color: _kPrimary),
                    tooltip: 'Observaciones',
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => _ObservacionesScreen(
                          userId: widget.userId,
                          empresaId: widget.empresaId,
                          estId: widget.estId,
                          estNombre: _est?.nombre ?? widget.estId,
                          svc: widget.svc,
                        ),
                      ),
                    ),
                  ),
                  if (count > 0)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          color: _kRed,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          count > 9 ? '9+' : '$count',
                          style: const TextStyle(
                            fontFamily: _kFont,
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(width: 4),
          Text(
            'Mes: ${facMesLabel(_activeMes)}',
            style: const TextStyle(
              fontFamily: _kFont,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const Spacer(),
          if (_isTaskFlow)
            const Text(
              'La carga enviará la tarea a revisión',
              style: TextStyle(
                fontFamily: _kFont,
                color: _kPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            )
          else if (_todoCompleto && widget.asFacturacion)
            const Text(
              'Mes completo',
              style: TextStyle(
                fontFamily: _kFont,
                color: _kPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            )
          else if (_todoCompleto)
            FilledButton.icon(
              onPressed: _solicitando ? null : _solicitarSiguienteMes,
              icon: const Icon(Icons.arrow_forward, size: 16),
              label: Text(
                _solicitando ? 'Enviando…' : 'Solicitar siguiente mes',
                style: const TextStyle(fontFamily: _kFont, fontSize: 13),
              ),
              style: FilledButton.styleFrom(backgroundColor: _kPrimary),
            )
          else
            Text(
              'Faltan documentos',
              style: const TextStyle(
                fontFamily: _kFont,
                color: _kRed,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _subirArchivo(String doc) async {
    FilePickerResult? result;
    if (kIsWeb) {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'pdf',
          'jpg',
          'jpeg',
          'png',
          'xls',
          'xlsx',
          'doc',
          'docx',
        ],
        allowMultiple: true,
      );
    } else {
      result = await FilePicker.platform.pickFiles(allowMultiple: true);
    }
    if (result == null || result.files.isEmpty) return;

    final allowed = {'pdf', 'jpg', 'jpeg', 'png', 'xls', 'xlsx', 'doc', 'docx'};
    final files = result.files
        .where((f) => allowed.contains(f.extension?.toLowerCase()))
        .toList();
    if (files.isEmpty) return;

    final uploadedPaths = <String>[];
    for (final file in files) {
      final ext = file.extension?.toLowerCase() ?? 'pdf';
      Uint8List bytes;
      if (kIsWeb) {
        bytes = file.bytes!;
      } else {
        bytes = await File(file.path!).readAsBytes();
      }
      final uploaded = await widget.svc.uploadArchivo(
        empresaId: widget.empresaId,
        estId: widget.estId,
        mes: _activeMes,
        doc: doc,
        bytes: bytes,
        extension: ext,
        uploaderId: widget.userId,
        uploaderNombre: _autorNombre,
      );
      uploadedPaths.add(uploaded.fullPath);
    }
    await _cargar();
    if (_isTaskFlow) {
      await widget.svc.submitDocumentTaskForReview(
        taskId: widget.linkedTaskId!,
        byUserId: widget.userId,
        byName: _autorNombre.isNotEmpty ? _autorNombre : widget.userId,
        docTipo: doc,
        storagePaths: uploadedPaths,
      );
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isTaskFlow
                ? '${files.length} archivo(s) subidos y enviados a revisión.'
                : '${files.length} archivo(s) subidos para "$doc".',
          ),
          backgroundColor: _kGreen,
        ),
      );
    }
  }

  Future<void> _viewFile(FacArchivo archivo) async {
    final uri = Uri.parse(archivo.downloadUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _deleteFile(FacArchivo archivo) async {
    final ok = await _confirm(context, '¿Borrar "${archivo.nombre}"?');
    if (!ok) return;
    final doc = _visibleDocs.firstWhere(
      (item) => (_archivos[item] ?? const <FacArchivo>[]).any(
        (candidate) => candidate.fullPath == archivo.fullPath,
      ),
      orElse: () => '',
    );
    await widget.svc.deleteArchivo(
      archivo.fullPath,
      empresaId: widget.empresaId,
      estId: widget.estId,
      mes: _activeMes,
      docTipo: doc.isEmpty ? null : doc,
      actorId: widget.userId,
      actorNombre: _autorNombre,
    );
    await _cargar();
  }

  Future<void> _solicitarSiguienteMes() async {
    setState(() => _solicitando = true);
    String nombre = widget.userId;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('TBL_USUARIOS')
          .doc(widget.userId)
          .get();
      if (snap.exists) {
        nombre = (snap.data()!['nombre'] ?? widget.userId).toString();
      }
    } catch (_) {}
    await widget.svc.solicitarSiguienteMes(
      empresaId: widget.empresaId,
      estId: widget.estId,
      establecimientoNombre: _est?.nombre ?? widget.estId,
      currentMes: _est?.mes ?? '',
      solicitanteId: widget.userId,
      solicitanteNombre: nombre,
    );
    if (mounted) {
      setState(() => _solicitando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Solicitud enviada a Facturación.'),
          backgroundColor: _kGreen,
        ),
      );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tarjeta de documento — preview + drag-drop + comentarios inline
// ─────────────────────────────────────────────────────────────────────────────

class _DocCard extends StatefulWidget {
  final String doc;
  final List<FacArchivo> archivos;
  final bool isIgnored;
  final DateTime? deadline;
  final bool canUpload;
  final bool canDelete;
  final VoidCallback? onToggleIgnore;
  final Future<void> Function(FacArchivo)? onView;
  final Future<void> Function(FacArchivo)? onDelete;
  final VoidCallback? onUpload;
  final Future<void> Function(List<XFile>)? onDropped;
  final List<FacObservacion> observaciones;
  final Future<void> Function(String texto, DateTime? fechaLimite)?
  onAddObservacion;
  final bool observationCreatesTask;
  final FacRevision? revision;
  final bool canReview;
  final Future<void> Function()? onApprove;
  final Future<void> Function(String motivo, DateTime fechaLimite)? onReject;

  const _DocCard({
    required this.doc,
    required this.archivos,
    required this.isIgnored,
    required this.deadline,
    required this.canUpload,
    required this.canDelete,
    required this.onToggleIgnore,
    required this.onView,
    required this.onDelete,
    required this.onUpload,
    this.onDropped,
    this.observaciones = const [],
    this.onAddObservacion,
    this.observationCreatesTask = false,
    this.revision,
    this.canReview = false,
    this.onApprove,
    this.onReject,
  });

  @override
  State<_DocCard> createState() => _DocCardState();
}

class _DocCardState extends State<_DocCard> {
  bool _isDragging = false;

  Color get _statusColor {
    if (widget.isIgnored) return _kGrey;
    if (widget.archivos.isNotEmpty) {
      return switch (widget.revision?.estado ?? FacEstadoRevision.pendiente) {
        FacEstadoRevision.pendiente => Colors.orange.shade700,
        FacEstadoRevision.aprobado => _kGreen,
        FacEstadoRevision.rechazado => _kRed,
      };
    }
    return _kRed;
  }

  IconData get _statusIcon {
    if (widget.isIgnored) return Icons.do_not_disturb_alt_rounded;
    if (widget.archivos.isNotEmpty) {
      return switch (widget.revision?.estado ?? FacEstadoRevision.pendiente) {
        FacEstadoRevision.pendiente => Icons.hourglass_top_rounded,
        FacEstadoRevision.aprobado => Icons.verified_rounded,
        FacEstadoRevision.rechazado => Icons.cancel_rounded,
      };
    }
    return Icons.radio_button_unchecked_rounded;
  }

  @override
  Widget build(BuildContext context) {
    Widget card = _buildCard(context);
    if (widget.canUpload && widget.onDropped != null && !kIsWeb) {
      card = DropTarget(
        onDragEntered: (_) => setState(() => _isDragging = true),
        onDragExited: (_) => setState(() => _isDragging = false),
        onDragDone: (d) {
          setState(() => _isDragging = false);
          widget.onDropped!(d.files);
        },
        child: card,
      );
    }
    return card;
  }

  Widget _buildCard(BuildContext context) {
    final color = _statusColor;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        color: _isDragging ? _kPrimary.withValues(alpha: 0.04) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _isDragging ? _kPrimary : color.withValues(alpha: 0.3),
          width: _isDragging ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header ──────────────────────────────
          _buildHeader(color),
          // ── Preview ─────────────────────────────
          Expanded(child: _buildPreview(context)),
          // ── Deadline ────────────────────────────
          if (widget.deadline != null && !widget.isIgnored)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: _DeadlineRow(deadline: widget.deadline!),
            ),
          if (widget.archivos.isNotEmpty &&
              widget.revision?.estado == FacEstadoRevision.rechazado &&
              widget.revision!.motivo.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(9, 2, 9, 3),
              child: Text(
                widget.revision!.motivo,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: _kFont,
                  fontSize: 9,
                  color: _kRed,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          // ── Footer ──────────────────────────────
          _buildFooter(context),
        ],
      ),
    );
  }

  // ─── Header ───────────────────────────────────────────────────────────────

  Widget _buildHeader(Color color) => Container(
    padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(_statusIcon, size: 14, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                widget.doc,
                style: TextStyle(
                  fontFamily: _kFont,
                  fontWeight: FontWeight.w700,
                  fontSize: 11.5,
                  color: color,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        if (widget.archivos.isNotEmpty && !widget.isIgnored) ...[
          const SizedBox(height: 5),
          Text(
            facEstadoRevisionLabel(
              widget.revision?.estado ?? FacEstadoRevision.pendiente,
            ),
            style: TextStyle(
              fontFamily: _kFont,
              fontSize: 9,
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    ),
  );

  // ─── Preview ──────────────────────────────────────────────────────────────

  Widget _buildPreview(BuildContext context) {
    if (_isDragging) return _buildDragOverlay();
    if (widget.isIgnored) return _buildIgnoredBody();
    if (widget.archivos.isEmpty) return _buildEmptyBody();

    final archivo = widget.archivos.first;
    final ext = archivo.nombre.split('.').last.toLowerCase();
    final isImage = ['jpg', 'jpeg', 'png', 'webp'].contains(ext);
    final isPdf = ext == 'pdf';

    Widget preview;
    VoidCallback onTap;

    if (isImage) {
      preview = Image.network(
        archivo.downloadUrl,
        width: double.infinity,
        fit: BoxFit.cover,
        loadingBuilder: (_, child, progress) => progress == null
            ? child
            : const Center(
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: _kPrimary,
                ),
              ),
        errorBuilder: (_, _, _) => _fileIcon(ext),
      );
      onTap = () => previewImage(context, archivo.downloadUrl);
    } else if (isPdf) {
      preview = _pdfPlaceholder(archivo);
      onTap = () =>
          previewDocument(context, archivo.downloadUrl, archivo.nombre);
    } else {
      preview = _fileIcon(ext);
      onTap = () => widget.onView?.call(archivo);
    }

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.all(Radius.zero),
            child: preview,
          ),
          // Hint "Toca para ver"
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 3),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black.withValues(alpha: 0.45), Colors.transparent],
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.visibility_outlined,
                    size: 10,
                    color: Colors.white70,
                  ),
                  SizedBox(width: 3),
                  Text(
                    'Vista previa',
                    style: TextStyle(
                      fontFamily: _kFont,
                      fontSize: 9,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Badge +N archivos
          if (widget.archivos.length > 1)
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '+${widget.archivos.length - 1} más',
                  style: const TextStyle(color: Colors.white, fontSize: 9),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _pdfPlaceholder(FacArchivo archivo) => Container(
    color: Colors.red.shade50,
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(
          Icons.picture_as_pdf_rounded,
          color: Colors.redAccent,
          size: 36,
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            archivo.nombre,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: _kFont,
              fontSize: 9,
              color: Colors.red.shade700,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _fileIcon(String ext) {
    final map = {
      'xls': (Icons.table_chart_rounded, Colors.green.shade700),
      'xlsx': (Icons.table_chart_rounded, Colors.green.shade700),
      'doc': (Icons.description_rounded, Colors.blue.shade700),
      'docx': (Icons.description_rounded, Colors.blue.shade700),
    };
    final (icon, color) =
        map[ext] ?? (Icons.insert_drive_file_outlined, _kGrey);
    return Container(
      color: Colors.grey.shade50,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 32, color: color),
          const SizedBox(height: 4),
          Text(
            ext.toUpperCase(),
            style: TextStyle(
              fontFamily: _kFont,
              fontSize: 10,
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDragOverlay() => Container(
    color: _kPrimary.withValues(alpha: 0.06),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.file_download_outlined, size: 32, color: _kPrimary),
        const SizedBox(height: 6),
        const Text(
          'Soltar aquí',
          style: TextStyle(
            fontFamily: _kFont,
            fontSize: 11,
            color: _kPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );

  Widget _buildIgnoredBody() => Container(
    color: Colors.grey.shade50,
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.block_rounded, size: 28, color: _kGrey.withValues(alpha: 0.4)),
        const SizedBox(height: 6),
        Text(
          'No requerido',
          style: TextStyle(
            fontFamily: _kFont,
            fontSize: 10,
            color: _kGrey,
            fontStyle: FontStyle.italic,
          ),
        ),
        if (widget.onToggleIgnore != null) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _tinyBtn(
              'Reactivar',
              Icons.undo_rounded,
              Colors.blueGrey,
              widget.onToggleIgnore!,
            ),
          ),
        ],
      ],
    ),
  );

  Widget _buildEmptyBody() => Container(
    color: Colors.red.shade50.withValues(alpha: 0.5),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.cloud_upload_outlined,
          size: 30,
          color: _kRed.withValues(alpha: 0.4),
        ),
        const SizedBox(height: 6),
        Text(
          kIsWeb ? 'Clic para subir' : 'Arrastra o sube',
          style: TextStyle(
            fontFamily: _kFont,
            fontSize: 10,
            color: _kRed.withValues(alpha: 0.55),
          ),
        ),
      ],
    ),
  );

  // ─── Footer ───────────────────────────────────────────────────────────────

  Widget _buildFooter(BuildContext context) {
    final hasFiles = widget.archivos.isNotEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Column(
        children: [
          // Fila de acciones principales
          Row(
            children: [
              if (hasFiles) ...[
                Expanded(
                  child: _tinyBtn(
                    'Ver',
                    Icons.open_in_new_rounded,
                    _kPrimary,
                    () => _seleccionar(context, widget.onView),
                  ),
                ),
                if (widget.canDelete) ...[
                  const SizedBox(width: 4),
                  Expanded(
                    child: _tinyBtn(
                      'Borrar',
                      Icons.delete_outline_rounded,
                      _kRed,
                      () => _seleccionar(context, widget.onDelete),
                    ),
                  ),
                ],
              ] else if (widget.canUpload)
                Expanded(child: _uploadBtn()),
              // Botón comentarios
              if (widget.observaciones.isNotEmpty ||
                  widget.onAddObservacion != null) ...[
                const SizedBox(width: 4),
                _commentsBtn(context),
              ],
            ],
          ),
          // Agregar más archivos
          if (hasFiles && widget.canUpload) ...[
            const SizedBox(height: 4),
            _tinyBtn(
              '+ Agregar',
              Icons.add_rounded,
              _kPrimary,
              widget.onUpload!,
            ),
          ],
          if (hasFiles && widget.canReview && !widget.isIgnored) ...[
            const SizedBox(height: 5),
            Row(
              children: [
                Expanded(
                  child: _tinyBtn(
                    'Aprobar',
                    Icons.check_rounded,
                    _kGreen,
                    widget.onApprove ?? () {},
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _tinyBtn(
                    'Rechazar',
                    Icons.close_rounded,
                    _kRed,
                    () => _requestReject(context),
                  ),
                ),
              ],
            ),
          ],
          // Ignorar
          if (widget.onToggleIgnore != null && !widget.isIgnored) ...[
            const SizedBox(height: 4),
            _tinyBtn(
              'No aplica',
              Icons.block_rounded,
              Colors.orange.shade600,
              widget.onToggleIgnore!,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _requestReject(BuildContext context) async {
    final callback = widget.onReject;
    if (callback == null) return;
    final reason = TextEditingController(text: widget.revision?.motivo ?? '');
    var deadline = DateTime.now().add(const Duration(days: 8));
    final result = await showDialog<(String, DateTime)>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            'Rechazar ${widget.doc}',
            style: const TextStyle(fontFamily: _kFont),
          ),
          content: SizedBox(
            width: 430,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: reason,
                  autofocus: true,
                  minLines: 3,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Motivo y corrección requerida',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_rounded, color: _kPrimary),
                  title: const Text('Fecha límite'),
                  subtitle: Text(DateFormat('dd/MM/yyyy').format(deadline)),
                  trailing: const Icon(Icons.edit_calendar_outlined),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: dialogContext,
                      initialDate: deadline,
                      firstDate: DateTime.now().add(const Duration(days: 1)),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) {
                      setDialogState(
                        () => deadline = DateTime(
                          picked.year,
                          picked.month,
                          picked.day,
                          23,
                          59,
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _kRed),
              onPressed: () {
                final value = reason.text.trim();
                if (value.isEmpty) return;
                Navigator.pop(dialogContext, (value, deadline));
              },
              child: const Text('Rechazar y crear corrección'),
            ),
          ],
        ),
      ),
    );
    reason.dispose();
    if (result != null) await callback(result.$1, result.$2);
  }

  Widget _uploadBtn() => SizedBox(
    height: 28,
    child: FilledButton.icon(
      onPressed: widget.onUpload,
      icon: const Icon(Icons.upload_rounded, size: 12),
      label: const Text(
        'Subir',
        style: TextStyle(fontFamily: _kFont, fontSize: 10),
      ),
      style: FilledButton.styleFrom(
        backgroundColor: _kRed.withValues(alpha: 0.85),
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
      ),
    ),
  );

  Widget _commentsBtn(BuildContext context) {
    final count = widget.observaciones.length;
    return GestureDetector(
      onTap: () => _openComments(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
        decoration: BoxDecoration(
          color: count > 0 ? _kPrimary.withValues(alpha: 0.1) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: count > 0
                ? _kPrimary.withValues(alpha: 0.3)
                : Colors.grey.shade300,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              count > 0
                  ? Icons.chat_bubble_rounded
                  : Icons.chat_bubble_outline_rounded,
              size: 12,
              color: count > 0 ? _kPrimary : Colors.grey,
            ),
            if (count > 0) ...[
              const SizedBox(width: 3),
              Text(
                '$count',
                style: const TextStyle(
                  fontFamily: _kFont,
                  fontSize: 10,
                  color: _kPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _tinyBtn(
    String label,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) => SizedBox(
    width: double.infinity,
    height: 26,
    child: OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: 0.4)),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        textStyle: const TextStyle(fontFamily: _kFont, fontSize: 10),
        minimumSize: Size.zero,
      ),
      icon: Icon(icon, size: 11),
      label: Text(label),
    ),
  );

  void _seleccionar(
    BuildContext context,
    Future<void> Function(FacArchivo)? onAction,
  ) {
    if (onAction == null) return;
    if (widget.archivos.length == 1) {
      onAction(widget.archivos.first);
      return;
    }
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Archivos — ${widget.doc}',
              style: const TextStyle(
                fontFamily: _kFont,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          ...widget.archivos.map(
            (a) => ListTile(
              dense: true,
              leading: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: _kPrimary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(
                  Icons.insert_drive_file_outlined,
                  size: 16,
                  color: _kPrimary,
                ),
              ),
              title: Text(
                a.nombre,
                style: const TextStyle(fontFamily: _kFont, fontSize: 13),
              ),
              onTap: () {
                Navigator.pop(context);
                onAction(a);
              },
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  // ─── Panel de comentarios ─────────────────────────────────────────────────

  void _openComments(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        maxChildSize: 0.92,
        minChildSize: 0.35,
        builder: (_, scroll) => _CommentsSheet(
          doc: widget.doc,
          observaciones: widget.observaciones,
          onAdd: widget.onAddObservacion,
          requiresDeadline: widget.observationCreatesTask,
          scrollController: scroll,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Panel de comentarios deslizable
// ─────────────────────────────────────────────────────────────────────────────

class _CommentsSheet extends StatefulWidget {
  final String doc;
  final List<FacObservacion> observaciones;
  final Future<void> Function(String texto, DateTime? fechaLimite)? onAdd;
  final bool requiresDeadline;
  final ScrollController scrollController;

  const _CommentsSheet({
    required this.doc,
    required this.observaciones,
    required this.onAdd,
    required this.requiresDeadline,
    required this.scrollController,
  });

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  final _ctrl = TextEditingController();
  bool _sending = false;
  DateTime? _fechaLimite;
  // Cache cédula → nombre (para autores cuyo autorNombre quedó como cédula)
  final Map<String, String> _nombres = {};

  @override
  void initState() {
    super.initState();
    _resolveNames();
  }

  Future<void> _resolveNames() async {
    // Buscar autores cuyo autorNombre parece una cédula (solo dígitos)
    final cedulas = widget.observaciones
        .map((o) => o.autorNombre.trim())
        .where((n) => RegExp(r'^\d{6,12}$').hasMatch(n))
        .toSet();
    if (cedulas.isEmpty) return;
    try {
      for (final ced in cedulas) {
        final snap = await FirebaseFirestore.instance
            .collection('TBL_USUARIOS')
            .doc(ced)
            .get();
        if (snap.exists && mounted) {
          final d = snap.data()!;
          final nombre = (d['nombre'] ?? d['name'] ?? ced).toString().trim();
          if (nombre.isNotEmpty && nombre != ced) {
            setState(() => _nombres[ced] = nombre);
          }
        }
      }
    } catch (_) {}
  }

  String _displayName(String autorNombre) =>
      _nombres[autorNombre.trim()] ?? autorNombre;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final texto = _ctrl.text.trim();
    if (texto.isEmpty || widget.onAdd == null) return;
    if (widget.requiresDeadline && _fechaLimite == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecciona la fecha límite de la tarea.'),
        ),
      );
      return;
    }
    setState(() => _sending = true);
    try {
      await widget.onAdd!(texto, _fechaLimite);
      _ctrl.clear();
      if (mounted) {
        setState(() {
          _sending = false;
          _fechaLimite = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.requiresDeadline
                  ? 'Observación enviada como tarea con fecha límite.'
                  : 'Observación enviada.',
            ),
            backgroundColor: _kGreen,
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _sending = false);
      final message = error is StateError
          ? error.message
          : error is ArgumentError
          ? error.message?.toString() ?? 'Datos de la tarea inválidos.'
          : 'No se pudo enviar la observación.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message), backgroundColor: _kRed));
    }
  }

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final initial = _fechaLimite ?? now.add(const Duration(days: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 5),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;
    final selected = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    if (!selected.isAfter(now)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La fecha límite debe ser futura.')),
      );
      return;
    }
    setState(() => _fechaLimite = selected);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle + header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Column(
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: _kPrimary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.chat_bubble_rounded,
                        size: 16,
                        color: _kPrimary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Observaciones',
                            style: TextStyle(
                              fontFamily: _kFont,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          Text(
                            widget.doc,
                            style: const TextStyle(
                              fontFamily: _kFont,
                              fontSize: 11,
                              color: Colors.black54,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const Divider(height: 14),
              ],
            ),
          ),
          // Lista de observaciones
          Expanded(
            child: widget.observaciones.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline_rounded,
                          size: 36,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Sin observaciones para este documento',
                          style: TextStyle(
                            fontFamily: _kFont,
                            color: Colors.grey.shade500,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    controller: widget.scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    itemCount: widget.observaciones.length,
                    separatorBuilder: (_, _) => const Divider(height: 12),
                    itemBuilder: (_, i) {
                      final o = widget.observaciones[i];
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          UserAvatar(
                            userId: o.autorId,
                            nameHint: _displayName(o.autorNombre),
                            radius: 16,
                            backgroundColor: _kPrimary.withValues(alpha: 0.12),
                            foregroundColor: _kPrimary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    UserNameText(
                                      o.autorId,
                                      fallbackName: _displayName(o.autorNombre),
                                      style: const TextStyle(
                                        fontFamily: _kFont,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      DateFormat(
                                        'dd/MM HH:mm',
                                        'es',
                                      ).format(o.fecha),
                                      style: const TextStyle(
                                        fontFamily: _kFont,
                                        fontSize: 10,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade50,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: Colors.grey.shade200,
                                    ),
                                  ),
                                  child: Text(
                                    o.texto,
                                    style: const TextStyle(
                                      fontFamily: _kFont,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                if (o.fechaLimite != null) ...[
                                  const SizedBox(height: 5),
                                  Text(
                                    'Tarea · vence ${DateFormat('dd/MM/yyyy HH:mm', 'es').format(o.fechaLimite!)}',
                                    style: TextStyle(
                                      fontFamily: _kFont,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: o.tareaEstado == 'por_aprobar'
                                          ? Colors.orange.shade700
                                          : _kPrimary,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
          // Input para agregar
          if (widget.onAdd != null)
            Container(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 8,
                bottom: MediaQuery.of(context).viewInsets.bottom + 12,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.requiresDeadline) ...[
                    InkWell(
                      onTap: _sending ? null : _pickDeadline,
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: _kPrimary.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _fechaLimite == null
                                ? Colors.grey.shade300
                                : _kPrimary.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.event_outlined,
                              size: 17,
                              color: _kPrimary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _fechaLimite == null
                                    ? 'Asignar fecha y hora límite'
                                    : 'Vence ${DateFormat('dd/MM/yyyy HH:mm', 'es').format(_fechaLimite!)}',
                                style: const TextStyle(
                                  fontFamily: _kFont,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const Text(
                              'CREARÁ TAREA',
                              style: TextStyle(
                                fontFamily: _kFont,
                                fontSize: 9,
                                color: _kPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _ctrl,
                          maxLines: 3,
                          minLines: 1,
                          style: const TextStyle(
                            fontFamily: _kFont,
                            fontSize: 13,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Escribe una observación…',
                            hintStyle: TextStyle(
                              fontFamily: _kFont,
                              fontSize: 13,
                              color: Colors.grey.shade400,
                            ),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(
                                color: Colors.grey.shade300,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: _kPrimary),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _sending ? null : _send,
                        style: FilledButton.styleFrom(
                          backgroundColor: _kPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.all(12),
                        ),
                        child: _sending
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(
                                Icons.send_rounded,
                                size: 18,
                                color: Colors.white,
                              ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widget de deadline por documento
// ─────────────────────────────────────────────────────────────────────────────

class _DeadlineRow extends StatelessWidget {
  final DateTime deadline;
  const _DeadlineRow({required this.deadline});

  @override
  Widget build(BuildContext context) {
    final diff = deadline.difference(DateTime.now());
    final color = diff.isNegative
        ? _kRed
        : (diff.inDays < 2 ? Colors.orange : _kGreen);
    return Row(
      children: [
        Icon(Icons.timer_outlined, size: 11, color: color),
        const SizedBox(width: 3),
        Expanded(
          child: Text(
            diff.isNegative
                ? 'Vencido'
                : DateFormat('dd/MM HH:mm').format(deadline),
            style: TextStyle(fontFamily: _kFont, fontSize: 10, color: color),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pantalla de observaciones
// ─────────────────────────────────────────────────────────────────────────────

class _ObservacionesScreen extends StatelessWidget {
  final String userId;
  final String empresaId;
  final String estId;
  final String estNombre;
  final FacturacionService svc;

  const _ObservacionesScreen({
    required this.userId,
    required this.empresaId,
    required this.estId,
    required this.estNombre,
    required this.svc,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
        title: Text(
          'Observaciones — $estNombre',
          style: const TextStyle(
            fontFamily: _kFont,
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
      ),
      body: StreamBuilder<List<FacObservacion>>(
        stream: svc.streamObservaciones(empresaId, estId),
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: _kPrimary),
            );
          }
          final obs = snap.data ?? [];
          if (obs.isEmpty) return _emptyState('Sin observaciones.');
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: obs.length,
            itemBuilder: (_, i) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.person_outline,
                          size: 14,
                          color: Colors.grey,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          obs[i].autorNombre,
                          style: const TextStyle(
                            fontFamily: _kFont,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          DateFormat(
                            'dd/MM/yyyy HH:mm',
                            'es',
                          ).format(obs[i].fecha),
                          style: const TextStyle(
                            fontFamily: _kFont,
                            fontSize: 10,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                    // Tag de documento si aplica
                    if (obs[i].docTipo != null) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: _kPrimary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: _kPrimary.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.insert_drive_file_outlined,
                              size: 11,
                              color: _kPrimary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              obs[i].docTipo!,
                              style: const TextStyle(
                                fontFamily: _kFont,
                                fontSize: 11,
                                color: _kPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      obs[i].texto,
                      style: const TextStyle(fontFamily: _kFont, fontSize: 13),
                    ),
                    if (obs[i].mes.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Mes: ${facMesLabel(obs[i].mes)}',
                          style: const TextStyle(
                            fontFamily: _kFont,
                            fontSize: 11,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers compartidos
// ─────────────────────────────────────────────────────────────────────────────

InputDecoration _inputDeco(String label) => InputDecoration(
  labelText: label,
  labelStyle: const TextStyle(fontFamily: _kFont, fontSize: 13),
  isDense: true,
  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
);

Widget _emptyState(String msg) => Center(
  child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.inbox_rounded, size: 48, color: Colors.grey.shade400),
      const SizedBox(height: 8),
      Text(
        msg,
        style: TextStyle(fontFamily: _kFont, color: Colors.grey.shade600),
      ),
    ],
  ),
);

Future<bool> _confirm(BuildContext ctx, String msg) async {
  return await showDialog<bool>(
        context: ctx,
        builder: (_) => AlertDialog(
          title: const Text('Confirmar', style: TextStyle(fontFamily: _kFont)),
          content: Text(msg, style: const TextStyle(fontFamily: _kFont)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text(
                'Cancelar',
                style: TextStyle(fontFamily: _kFont),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: _kPrimary),
              child: const Text(
                'Confirmar',
                style: TextStyle(fontFamily: _kFont),
              ),
            ),
          ],
        ),
      ) ??
      false;
}
