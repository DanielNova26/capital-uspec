// lib/nutricion/nutricion_dashboard_screen.dart

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import 'catalogos/nutricion_catalogos_screen.dart';
import 'firmas/nutricion_firmas_screen.dart';
import 'ingredientes/nutricion_ingredientes_screen.dart';
import 'menus/nutricion_menus_screen.dart';
import 'reportes/nutricion_reportes_screen.dart';

import '../services/diagnosticos_service.dart';
import '../services/nutricion_service.dart';
import '../services/nutricion_pdf_service.dart';
import '../services/citas_nutricion_service.dart';
import '../widgets/evaluacion_nutricional_widget.dart';
import '../widgets/empty_state_widget.dart';
import '../core/guarded_module_page.dart';
import '../home/widgets/home_shared_widgets.dart' show CompanyNameWidget;
import '../theme/app_typography.dart';
import '../widgets/internal_module_layout.dart';
import 'widgets/nutrition_shared_widgets.dart';

import 'package:todo/widgets/selector_diagnosticos_widget.dart';
import 'atencion/diagnostico_models.dart';

// ── Catálogo de dietas clínicas estándar ─────────────────────────────────────
// Usado para seed de TBL_DIETAS y para construir las sugerencias en el plan.
const List<Map<String, String>> kDietasCatalogo = [
  {'codigo': 'normal',          'nombre': 'Dieta normal',              'descripcion': 'Alimentación equilibrada estándar.'},
  {'codigo': 'liquida_clara',   'nombre': 'Líquida clara',             'descripcion': 'Solo líquidos transparentes. Post-cirugía o pre-procedimientos.'},
  {'codigo': 'liquida_completa','nombre': 'Líquida completa',          'descripcion': 'Líquidos con mayor valor nutricional. Transición hacia dieta blanda.'},
  {'codigo': 'blanda',          'nombre': 'Blanda',                    'descripcion': 'Alimentos de textura suave, fácil digestión. Post-quirúrgica o GI.'},
  {'codigo': 'hipocalorica',    'nombre': 'Hipocalórica',              'descripcion': 'Reducida en calorías. Control de sobrepeso u obesidad.'},
  {'codigo': 'hipograsa',       'nombre': 'Hipograsa',                 'descripcion': 'Baja en grasas. Afecciones hepáticas, biliares o cardiovasculares.'},
  {'codigo': 'hipercalorica',   'nombre': 'Hipercalórica',             'descripcion': 'Alto valor energético. Desnutrición, caquexia, recuperación.'},
  {'codigo': 'hiperproteica',   'nombre': 'Hiperproteica',             'descripcion': 'Alta en proteínas. Recuperación muscular, heridas, cirugías.'},
  {'codigo': 'alta_fibra',      'nombre': 'Alta en fibra',             'descripcion': 'Rica en fibra dietética. Estreñimiento, síndrome metabólico.'},
  {'codigo': 'renal',           'nombre': 'Renal',                     'descripcion': 'Restricción de Na, K, P y líquidos. Insuficiencia renal.'},
  {'codigo': 'hipopurinica',    'nombre': 'Hipopurínica',              'descripcion': 'Baja en purinas. Gota e hiperuricemia.'},
  {'codigo': 'sin_irritantes',  'nombre': 'Sin irritantes gástricos',  'descripcion': 'Excluye condimentos, cafeína y ácidos. Gastritis, úlcera.'},
  {'codigo': 'libre_lactosa',   'nombre': 'Libre de lactosa',          'descripcion': 'Exclusión de lactosa. Intolerancia a la lactosa.'},
  {'codigo': 'reflujo',         'nombre': 'Reflujo esofágico',         'descripcion': 'Fraccionada, baja en grasa y acidez. ERGE.'},
  {'codigo': 'vegetariana',     'nombre': 'Vegetariana',               'descripcion': 'Sin carnes. Por elección, creencias o indicación médica.'},
];

/// Abre NutricionDashboardScreen desde una notificación de cita.
/// Carga la cita de TBL_CITAS_NUTRICION por [citaId], extrae [empresaId]
/// y navega al módulo. Usado por las rutas de notificaciones (home, lista y FCM).
Future<void> abrirNutricionDesdeCita(
  BuildContext context, {
  required String userId,
  required String citaId,
}) async {
  Map<String, dynamic>? citaData;
  try {
    final snap = await FirebaseFirestore.instance
        .collection('TBL_CITAS_NUTRICION')
        .doc(citaId)
        .get();
    if (snap.exists) citaData = snap.data();
  } catch (_) {}

  if (!context.mounted) return;

  final empresaId = (citaData?['empresaId'] as String?)?.trim() ?? '';
  if (empresaId.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('No se pudo abrir el módulo de Nutrición.'),
      ),
    );
    return;
  }

  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => NutricionDashboardScreen(
        userId: userId,
        empresaId: empresaId,
      ),
    ),
  );
}

class NutricionDashboardScreen extends StatefulWidget {
  final String userId;
  final String empresaId;

  const NutricionDashboardScreen({
    super.key,
    required this.userId,
    required this.empresaId,
  });

  @override
  State<NutricionDashboardScreen> createState() =>
      _NutricionDashboardScreenState();
}

class _NutricionDashboardScreenState extends State<NutricionDashboardScreen>
    with AutomaticKeepAliveClientMixin {
  static const List<InternalModuleTabItem> _moduleTabs = [
    InternalModuleTabItem(
      label: 'Atención',
      icon: Icons.health_and_safety_outlined,
    ),
    InternalModuleTabItem(
      label: 'Menú',
      icon: Icons.restaurant_menu_outlined,
    ),
    InternalModuleTabItem(
      label: 'Items',
      icon: Icons.inventory_2_outlined,
    ),
    InternalModuleTabItem(
      label: 'Pacientes',
      icon: Icons.badge_outlined,
    ),
    InternalModuleTabItem(
      label: 'Firmas',
      icon: Icons.draw_outlined,
    ),
    InternalModuleTabItem(
      label: 'Reportes',
      icon: Icons.bar_chart_outlined,
    ),
  ];

  final List<String> _establecimientos = const ['Establecimiento principal'];
  late final Stream<List<_PacienteInfo>> _pacientesStream;
  List<_PacienteInfo>? _cachedPacientes;

  late String _selectedEstablecimiento;
  DateTime _weekStart = _mondayOf(DateTime.now());
  _PacienteInfo? _selectedPaciente;
  bool _agendandoCita = false;
  int _pasoActual = 0;
  int _navigationIndex = 0;
  final GlobalKey _diagnosticosSectionKey = GlobalKey();

  // Paso 0 – Admisión
  final TextEditingController _nombreCompletoCtrl = TextEditingController();
  final TextEditingController _documentoCtrl = TextEditingController();
  final TextEditingController _regimenCtrl = TextEditingController();
  // Paso 1 – Evaluación
  final TextEditingController _diagnosticoMedicoCtrl = TextEditingController();
  final TextEditingController _diagnosticoNutriCtrl = TextEditingController();
  List<DiagnosticoMedico> _diagnosticosMedicosSeleccionados = [];
  List<DiagnosticoNutricional> _diagnosticosNutricionalesSeleccionados = [];
  // Paso 2 – Plan
  final TextEditingController _tipoDietaCtrl = TextEditingController();
  final TextEditingController _observacionesPlanCtrl = TextEditingController();
  String? _dietaSeleccionadaId;
  String? _periodoSeleccionado;
  DateTime? _proximoControl;

  // ── Dietas sugeridas por los diagnósticos seleccionados ──────────────────
  Set<String> get _dietasSugeridaLabels {
    final ids = <String>{};
    for (final d in _diagnosticosMedicosSeleccionados) {
      ids.addAll(d.dietasSugeridas);
    }
    for (final d in _diagnosticosNutricionalesSeleccionados) {
      if (d.tipoDietaSugerida != null && d.tipoDietaSugerida!.isNotEmpty) {
        ids.add(d.tipoDietaSugerida!);
      }
    }
    return ids;
  }

  @override
  void initState() {
    super.initState();
    _selectedEstablecimiento = _establecimientos.first;
    _initPacientesStream();
    _seedTablas();
  }

  Future<void> _seedTablas() async {
    final svc = NutricionService();
    try {
      await svc.seedIngredientesSiNoExisten(
        empresaId: widget.empresaId,
        userId: widget.userId,
        ingredientes: kIngredientesBase,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[Nutricion] seed ingredientes: $e');
    }
    try {
      await svc.seedPlantillasMenusSiNoExisten(
        empresaId: widget.empresaId,
        establecimiento: _establecimientos.first,
        userId: widget.userId,
        defaults: kDietasDefault,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[Nutricion] seed plantillas: $e');
    }
    try {
      await svc.seedDietasSiNoExisten(
        empresaId: widget.empresaId,
        userId: widget.userId,
        dietas: kDietasCatalogo,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[Nutricion] seed dietas: $e');
    }
  }

  void _initPacientesStream() {
    final service = NutricionService();
    _pacientesStream =
        service.streamDirectorioNutricion(empresaId: widget.empresaId).map(
      (list) {
        final pacientes = list.map((data) {
          return _PacienteInfo(
            id: data['id']?.toString() ?? '',
            nombre:
                (data['nombreCompleto'] ?? data['nombre'] ?? '').toString(),
            documento: (data['documento'] ?? '').toString(),
            eps: (data['eps'] ?? '').toString(),
            genero: (data['genero'] ?? '').toString(),
            fechaNacimiento: data['fechaNacimiento'] is Timestamp
                ? (data['fechaNacimiento'] as Timestamp).toDate()
                : null,
            establecimiento: (data['establecimiento'] ?? '').toString(),
            pabellon: (data['pabellon'] ?? '').toString(),
            diagnosticoMedico:
                (data['diagnosticoMedico'] ?? '').toString(),
            diagnosticoNutricional:
                (data['diagnosticoNutricional'] ?? '').toString(),
            regimenAfiliacion:
                (data['regimenAfiliacion'] ?? '').toString(),
            tipoDietaSugerida:
                (data['tipoDietaSugerida'] ?? '').toString(),
            pesoKg: (data['ultimaMedicion']?['pesoKg'] as num?)?.toDouble(),
            tallaCm:
                (data['ultimaMedicion']?['tallaCm'] as num?)?.toDouble(),
            imc: (data['ultimaMedicion']?['imc'] as num?)?.toDouble(),
            diagnosticosMedicos: (data['diagnosticosMedicosData'] as List?)
                    ?.map((e) => DiagnosticoMedico.fromMap(e))
                    .toList() ??
                [],
            diagnosticosNutricionales:
                (data['diagnosticosNutricionalesData'] as List?)
                        ?.map((e) => DiagnosticoNutricional.fromMap(e))
                        .toList() ??
                    [],
          );
        }).toList();
        _cachedPacientes = pacientes;
        return pacientes;
      },
    );
  }

  @override
  void dispose() {
    _nombreCompletoCtrl.dispose();
    _documentoCtrl.dispose();
    _regimenCtrl.dispose();
    _diagnosticoMedicoCtrl.dispose();
    _diagnosticoNutriCtrl.dispose();
    _tipoDietaCtrl.dispose();
    _observacionesPlanCtrl.dispose();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  static DateTime _mondayOf(DateTime date) {
    final n = DateTime(date.year, date.month, date.day);
    return n.subtract(Duration(days: n.weekday - 1));
  }

  String _weekLabel(DateTime start) {
    final end = start.add(const Duration(days: 6));
    return '${DateFormat('dd MMM').format(start)} - ${DateFormat('dd MMM').format(end)}';
  }

  Future<void> _pickWeek() async {
    final p = await showDatePicker(
      context: context,
      initialDate: _weekStart,
      firstDate: DateTime(2024),
      lastDate: DateTime(2100),
    );
    if (p != null) setState(() => _weekStart = _mondayOf(p));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final width = MediaQuery.of(context).size.width;
    final isWeb = width >= 900;

    const titles = [
      'Atención Nutricional',
      'Planificación de Menús',
      'Catálogo de Ingredientes',
      'Directorio de Pacientes',
      'Firmas y Consentimientos',
      'Reportes Operativos'
    ];
    const subs = [
      'Registro clínico y seguimiento de pacientes.',
      'Gestión de minutas y tiempos de comida.',
      'Configuración técnica de alimentos y gramajes.',
      'Expedientes históricos del sistema.',
      'Validación de firmas digitales y sellos.',
      'Generación de documentos técnicos en Excel.',
    ];

    return GuardedModulePage(
      userIdentity: widget.userId,
      appId: 'nutriciondashboard',
      pageTitle: 'Nutrición Clínica',
      fallbackEmpresaId: widget.empresaId,
      child: InternalModuleLayout(
        userId: widget.userId,
        empresaId: widget.empresaId,
        title: titles[_navigationIndex],
        subtitle: subs[_navigationIndex],
        accentColor: NutritionPalette.accent,
        headerActions: [
          CompanyNameWidget(
            empresaId: widget.empresaId,
            style: TextStyle(
              color: isWeb ? NutritionPalette.accent : Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: isWeb ? 14 : 12,
            ),
          ),
        ],
        child: isWeb ? _buildWebBody() : _buildMobileBody(),
      ),
    );
  }

  Widget _buildWebBody() {
    return _buildModuleShell(isWeb: true);
  }

  Widget _buildMobileBody() {
    return _buildModuleShell(isWeb: false);
  }

  Widget _buildModuleShell({required bool isWeb}) {
    return Column(
      children: [
        InternalModuleTabs(
          items: _moduleTabs,
          selectedIndex: _navigationIndex,
          onSelected: (i) => setState(() => _navigationIndex = i),
          accentColor: NutritionPalette.accent,
          compact: !isWeb,
        ),
        Expanded(
          child: InternalModuleViewport(
            maxWidth: isWeb && _navigationIndex == 0 ? 1360 : 1280,
            padding: EdgeInsets.all(isWeb ? 28 : 16),
            child: _buildViews(isWeb: isWeb),
          ),
        ),
      ],
    );
  }

  Widget _buildViews({required bool isWeb}) {
    return IndexedStack(
      index: _navigationIndex,
      children: [
        _buildAtencionView(isWeb: isWeb),
        NutricionMenusScreen(
          userId: widget.userId,
          empresaId: widget.empresaId,
          establecimiento: _selectedEstablecimiento,
          semana: _weekStart,
          showAppBar: false,
        ),
        NutricionIngredientesScreen(
          userId: widget.userId,
          empresaId: widget.empresaId,
          showAppBar: false,
        ),
        NutricionCatalogosScreen(
          empresaId: widget.empresaId,
          userId: widget.userId,
          showAppBar: false,
        ),
        NutricionFirmasScreen(
          empresaId: widget.empresaId,
          userId: widget.userId,
          showAppBar: false,
        ),
        NutricionReportesScreen(
          empresaId: widget.empresaId,
          showAppBar: false,
        ),
      ],
    );
  }

  // ── Vista de Atención ───────────────────────────────────────────────────────

  Widget _buildAtencionView({required bool isWeb}) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _buildFilters(isCompact: !isWeb),
        const SizedBox(height: 24),
        if (isWeb)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: _buildAtencionWorkflow()),
              const SizedBox(width: 32),
              Expanded(flex: 2, child: _buildPacienteStatusSidebar()),
            ],
          )
        else
          Column(
            children: [
              _buildAtencionWorkflow(),
              const SizedBox(height: 24),
              _buildSummaryGrid(isCompact: true),
            ],
          ),
      ],
    );
  }

  Widget _buildAtencionWorkflow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NutritionStepIndicator(
          currentStep: _pasoActual,
          steps: const ['Admisión', 'Clínica', 'Prescripción', 'Cierre'],
          icons: const [
            Icons.person_add_outlined,
            Icons.medical_information_outlined,
            Icons.restaurant_menu_outlined,
            Icons.verified_outlined
          ],
          onStepTap: (i) {
            if (i < _pasoActual) setState(() => _pasoActual = i);
          },
        ),
        const SizedBox(height: 12),
        NutritionCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 480, maxHeight: 800),
                child: IndexedStack(
                  index: _pasoActual,
                  children: [
                    _buildPacienteTabContent(),
                    _buildEvaluacionTabContent(),
                    _buildPlanTabContent(),
                    _buildEvidenciasTabContent(),
                  ],
                ),
              ),
              _buildStepNavigationButtons(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStepNavigationButtons() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
          color: NutritionPalette.background,
          borderRadius:
              BorderRadius.vertical(bottom: Radius.circular(8))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (_pasoActual > 0)
            OutlinedButton.icon(
                onPressed: _irAlPasoAnterior,
                icon: const Icon(Icons.arrow_back),
                label: const Text('Anterior'))
          else
            const SizedBox(),
          FilledButton.icon(
            onPressed: _pasoActual < 3
                ? _irAlSiguientePaso
                : (_agendandoCita ? null : _guardarYAgendarCita),
            icon: Icon(
                _pasoActual < 3 ? Icons.arrow_forward : Icons.check_circle),
            label: Text(_pasoActual < 3
                ? 'Siguiente'
                : (_agendandoCita ? 'Guardando...' : 'Finalizar Proceso')),
            style: FilledButton.styleFrom(
                backgroundColor: _pasoActual < 3
                    ? NutritionPalette.accent
                    : Colors.green[800]),
          ),
        ],
      ),
    );
  }

  Widget _buildPacienteStatusSidebar() {
    return Column(
      children: [
        _buildPacienteFichaCard(),
        const SizedBox(height: 24),
        _buildSummaryGrid(isCompact: false),
      ],
    );
  }

  Widget _buildPacienteFichaCard() {
    if (_selectedPaciente == null) {
      return const EmptyStateWidget(
          icon: Icons.person_search,
          title: 'Paciente no seleccionado',
          message: 'Inicia el flujo seleccionando un paciente.',
          compact: true);
    }
    return NutritionCard(
      title: 'Paciente Seleccionado',
      child: Column(
        children: [
          const CircleAvatar(
              radius: 36,
              backgroundColor: NutritionPalette.background,
              child: Icon(Icons.person,
                  size: 36, color: NutritionPalette.accent)),
          const SizedBox(height: 16),
          Text(_selectedPaciente!.nombre,
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  fontFamily: kArial,
                  color: NutritionPalette.textMain)),
          Text(_selectedPaciente!.documento,
              style: const TextStyle(
                  color: NutritionPalette.textMuted, fontSize: 12)),
          const Divider(height: 32),
          _buildFichaRow(Icons.badge_outlined, 'Régimen',
              _regimenCtrl.text.isEmpty ? 'Pendiente' : _regimenCtrl.text),
          if (_selectedPaciente!.eps.isNotEmpty)
            _buildFichaRow(Icons.local_hospital_outlined, 'EPS',
                _selectedPaciente!.eps),
          if (_selectedPaciente!.imc != null)
            _buildFichaRow(Icons.monitor_weight_outlined, 'IMC',
                '${_selectedPaciente!.imc!.toStringAsFixed(1)} · ${_imcClasificacion(_selectedPaciente!.imc!)}'),
          _buildFichaRow(Icons.restaurant_outlined, 'Dieta',
              _tipoDietaCtrl.text.isEmpty ? 'No definida' : _tipoDietaCtrl.text),
          if (_proximoControl != null)
            _buildFichaRow(Icons.event_outlined, 'Próx. control',
                DateFormat('dd/MM/yyyy').format(_proximoControl!)),
        ],
      ),
    );
  }

  String _imcClasificacion(double imc) {
    if (imc < 18.5) return 'Bajo peso';
    if (imc < 25) return 'Normal';
    if (imc < 30) return 'Sobrepeso';
    return 'Obesidad';
  }

  Widget _buildFichaRow(IconData icon, String label, String val) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Icon(icon, size: 14, color: NutritionPalette.textMuted),
        const SizedBox(width: 8),
        Text('$label: ',
            style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: NutritionPalette.textMain)),
        Expanded(
            child: Text(val,
                style: const TextStyle(
                    fontSize: 12, color: NutritionPalette.textMain),
                overflow: TextOverflow.ellipsis))
      ]),
    );
  }

  Widget _buildFilters({required bool isCompact}) {
    final content = isCompact
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildEstablecimientoDropdown(),
              const SizedBox(height: 12),
              _buildSemanaButton(),
            ],
          )
        : Row(
            children: [
              SizedBox(width: 320, child: _buildEstablecimientoDropdown()),
              const SizedBox(width: 16),
              _buildSemanaButton(),
            ],
          );

    return ModuleCard(
      padding: EdgeInsets.all(isCompact ? 16 : 20),
      child: content,
    );
  }

  Widget _buildEstablecimientoDropdown() {
    return DropdownButtonFormField<String>(
      value: _selectedEstablecimiento,
      items: _establecimientos
          .map((e) => DropdownMenuItem(value: e, child: Text(e)))
          .toList(),
      onChanged: (v) {
        if (v != null) setState(() => _selectedEstablecimiento = v);
      },
      decoration: const InputDecoration(
        labelText: 'Sede / Establecimiento',
        filled: true,
        fillColor: NutritionPalette.surface,
        border: OutlineInputBorder(),
      ),
    );
  }

  Widget _buildSemanaButton() {
    return OutlinedButton.icon(
      onPressed: _pickWeek,
      icon: const Icon(Icons.calendar_view_week),
      label: Text(_weekLabel(_weekStart)),
    );
  }

  void _irAlSiguientePaso() {
    final err = _validarPaso(_pasoActual);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(err),
          backgroundColor: Colors.red[800],
          behavior: SnackBarBehavior.floating));
      return;
    }
    if (_pasoActual < 3) setState(() => _pasoActual++);
  }

  void _irAlPasoAnterior() {
    if (_pasoActual > 0) setState(() => _pasoActual--);
  }

  String? _validarPaso(int p) {
    if (p == 0 && _nombreCompletoCtrl.text.trim().isEmpty) {
      return 'Falta nombre del paciente';
    }
    if (p == 1 && _diagnosticoMedicoCtrl.text.trim().isEmpty) {
      return 'Falta diagnóstico médico';
    }
    return null;
  }

  // ── Paso 0: Admisión ────────────────────────────────────────────────────────

  Widget _buildPacienteTabContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: NutritionPalette.accent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.person_search, color: NutritionPalette.accent, size: 24),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Admisión de Paciente',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: NutritionPalette.textMain, fontFamily: kArial),
                    ),
                    Text(
                      'Busca un paciente existente o registra un nuevo ingreso clínico.',
                      style: TextStyle(color: NutritionPalette.textMuted, fontSize: 13, fontFamily: kArial),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          StreamBuilder<List<_PacienteInfo>>(
            stream: _pacientesStream,
            initialData: _cachedPacientes,
            builder: (context, snapshot) {
              final pacientes = snapshot.data ?? [];
              return Column(
                children: [
                  DropdownButtonFormField<_PacienteInfo>(
                    value: _selectedPaciente,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Buscar paciente por nombre o documento',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      filled: true,
                      fillColor: NutritionPalette.background,
                    ),
                    items: pacientes
                        .map((p) => DropdownMenuItem(
                            value: p,
                            child: Text('${p.nombre} · ${p.documento}')))
                        .toList(),
                    onChanged: (v) {
                      setState(() {
                        _selectedPaciente = v;
                        if (v != null) {
                          _nombreCompletoCtrl.text = v.nombre;
                          _documentoCtrl.text = v.documento;
                          _regimenCtrl.text = v.regimenAfiliacion;
                          _diagnosticoMedicoCtrl.text = v.diagnosticoMedico;
                          _diagnosticoNutriCtrl.text = v.diagnosticoNutricional;
                          _tipoDietaCtrl.text = v.tipoDietaSugerida;
                          _diagnosticosMedicosSeleccionados = List.from(v.diagnosticosMedicos);
                          _diagnosticosNutricionalesSeleccionados = List.from(v.diagnosticosNutricionales);
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _registrarNuevoPaciente,
                      icon: const Icon(Icons.person_add_outlined),
                      label: const Text('REGISTRAR NUEVO PACIENTE', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          if (_selectedPaciente != null) ...[
            const SizedBox(height: 32),
            const Text(
              'EXPEDIENTE SELECCIONADO',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: NutritionPalette.accent, fontFamily: kArial),
            ),
            const SizedBox(height: 12),
            _buildPacienteSummaryCard(),
          ],
        ],
      ),
    );
  }

  Widget _buildPacienteSummaryCard() {
    if (_selectedPaciente == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: NutritionPalette.accent.withOpacity(0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NutritionPalette.accent.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: NutritionPalette.accent,
                child: const Icon(Icons.person, color: Colors.white, size: 30),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _selectedPaciente!.nombre,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: NutritionPalette.textMain, fontFamily: kArial),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        ClinicalTag(label: _selectedPaciente!.documento, color: NutritionPalette.secondary, isCompact: true),
                        const SizedBox(width: 8),
                        if (_selectedPaciente!.eps.isNotEmpty)
                          ClinicalTag(label: _selectedPaciente!.eps, color: NutritionPalette.info, isCompact: true),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 40),
          Row(
            children: [
              _buildSummaryItem(Icons.category_outlined, 'Régimen', _selectedPaciente!.regimenAfiliacion),
              _buildSummaryItem(Icons.location_on_outlined, 'Ubicación', _selectedPaciente!.pabellon.isNotEmpty ? _selectedPaciente!.pabellon : 'No asignado'),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildSummaryItem(Icons.monitor_weight_outlined, 'Último IMC', _selectedPaciente!.imc != null ? '${_selectedPaciente!.imc!.toStringAsFixed(1)}' : 'Sin registro'),
              _buildSummaryItem(Icons.history_outlined, 'Estado', 'Activo en atención'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(IconData icon, String label, String value) {
    return Expanded(
      child: Row(
        children: [
          Icon(icon, size: 16, color: NutritionPalette.textMuted),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 10, color: NutritionPalette.textMuted, fontWeight: FontWeight.bold)),
              Text(value.isEmpty ? '—' : value, style: const TextStyle(fontSize: 13, color: NutritionPalette.textMain, fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }

  // ── Paso 1: Evaluación ──────────────────────────────────────────────────────

  Widget _buildEvaluacionTabContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: NutritionPalette.accent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.medical_information, color: NutritionPalette.accent, size: 24),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Evaluación Clínica y Diagnóstico',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: NutritionPalette.textMain, fontFamily: kArial),
                    ),
                    Text(
                      'Registra las mediciones del paciente y asigna los diagnósticos correspondientes.',
                      style: TextStyle(color: NutritionPalette.textMuted, fontSize: 13, fontFamily: kArial),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          EvaluacionNutricionalWidget(
            pacienteId: _selectedPaciente?.id,
            onGuardarMedicion: (m) async {
              if (_selectedPaciente == null) return;
              try {
                await NutricionService().registrarMedicion(
                  empresaId: widget.empresaId,
                  pacienteId: _selectedPaciente!.id,
                  pesoKg: (m['pesoKg'] as num).toDouble(),
                  tallaCm: (m['tallaCm'] as num).toDouble(),
                  notas: m['notas']?.toString(),
                  fecha: m['fecha'] as DateTime?,
                );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Medición clínica guardada exitosamente'), backgroundColor: NutritionPalette.success));
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('Error al guardar medición: $e'),
                      backgroundColor: NutritionPalette.danger));
                }
              }
            },
            onRegistrarDiagnostico: () {
              final ctx = _diagnosticosSectionKey.currentContext;
              if (ctx != null) Scrollable.ensureVisible(ctx);
            },
            onRegistrarHistoria: _abrirRemision,
          ),
          const SizedBox(height: 32),
          const Text(
            'DIAGNÓSTICOS CLÍNICOS',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: NutritionPalette.accent, fontFamily: kArial),
          ),
          const SizedBox(height: 12),
          SelectorDiagnosticosWidget(
            key: _diagnosticosSectionKey,
            empresaId: widget.empresaId,
            onDiagnosticosChanged: _onDiagnosticosChanged,
            initialMedicos: _diagnosticosMedicosSeleccionados,
            initialNutricionales: _diagnosticosNutricionalesSeleccionados,
          ),
        ],
      ),
    );
  }

  // ── Paso 2: Plan Alimentario ────────────────────────────────────────────────

  Widget _buildPlanTabContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: NutritionPalette.accent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.assignment_outlined, color: NutritionPalette.accent, size: 24),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Prescripción Nutricional',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: NutritionPalette.textMain, fontFamily: kArial),
                    ),
                    Text(
                      'Define la dieta, el período de tratamiento y el próximo seguimiento.',
                      style: TextStyle(color: NutritionPalette.textMuted, fontSize: 13, fontFamily: kArial),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),

          // Dietas sugeridas por diagnóstico
          if (_dietasSugeridaLabels.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: NutritionPalette.info.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: NutritionPalette.info.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.lightbulb_outline, size: 16, color: NutritionPalette.info),
                      SizedBox(width: 8),
                      Text(
                        'DIETAS SUGERIDAS SEGÚN DIAGNÓSTICO',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 0.5, color: NutritionPalette.info),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _dietasSugeridaLabels.map((label) {
                      final selected = _tipoDietaCtrl.text.toLowerCase() == label.toLowerCase();
                      return ChoiceChip(
                        label: Text(label),
                        selected: selected,
                        onSelected: (bool selected) {
                          if (selected) {
                            setState(() {
                              _tipoDietaCtrl.text = label;
                              final match = kDietasCatalogo.where((d) => d['nombre']!.toLowerCase() == label.toLowerCase());
                              _dietaSeleccionadaId = match.isNotEmpty ? match.first['codigo'] : null;
                            });
                          }
                        },
                        selectedColor: NutritionPalette.info.withOpacity(0.2),
                        labelStyle: TextStyle(
                          color: selected ? NutritionPalette.info : NutritionPalette.textMain,
                          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                          fontSize: 12,
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Selector de dieta y período en Fila (para Web) o Columna (para Móvil)
          LayoutBuilder(builder: (context, constraints) {
            final isWide = constraints.maxWidth > 500;
            return Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: isWide ? 2 : 1,
                      child: StreamBuilder<List<Map<String, dynamic>>>(
                        stream: NutricionService().streamDietas(widget.empresaId),
                        builder: (context, snap) {
                          final dietas = snap.data ?? kDietasCatalogo.map((d) => <String, dynamic>{'id': d['codigo'], 'nombre': d['nombre']}).toList();
                          String? currentVal = _dietaSeleccionadaId;
                          final ids = dietas.map((d) => d['id']?.toString()).toSet();
                          if (currentVal != null && !ids.contains(currentVal)) currentVal = null;

                          return DropdownButtonFormField<String>(
                            value: currentVal,
                            decoration: const InputDecoration(
                              labelText: 'Dieta Principal',
                              prefixIcon: Icon(Icons.restaurant_menu),
                              border: OutlineInputBorder(),
                            ),
                            items: dietas.map((d) => DropdownMenuItem<String>(
                              value: d['id']?.toString(),
                              child: Text(d['nombre']?.toString() ?? ''),
                            )).toList(),
                            onChanged: (v) {
                              setState(() {
                                _dietaSeleccionadaId = v;
                                final found = dietas.firstWhere((d) => d['id']?.toString() == v, orElse: () => {});
                                _tipoDietaCtrl.text = found['nombre']?.toString() ?? v ?? '';
                              });
                            },
                          );
                        },
                      ),
                    ),
                    if (isWide) const SizedBox(width: 16),
                    if (isWide)
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _periodoSeleccionado,
                          decoration: const InputDecoration(
                            labelText: 'Período',
                            prefixIcon: Icon(Icons.calendar_month_outlined),
                            border: OutlineInputBorder(),
                          ),
                          items: ['7 días', '15 días', '30 días', '60 días', '90 días', 'Permanente']
                              .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                              .toList(),
                          onChanged: (v) => setState(() => _periodoSeleccionado = v),
                        ),
                      ),
                  ],
                ),
                if (!isWide) ...[
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _periodoSeleccionado,
                    decoration: const InputDecoration(
                      labelText: 'Período',
                      prefixIcon: Icon(Icons.calendar_month_outlined),
                      border: OutlineInputBorder(),
                    ),
                    items: ['7 días', '15 días', '30 días', '60 días', '90 días', 'Permanente']
                        .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                        .toList(),
                    onChanged: (v) => setState(() => _periodoSeleccionado = v),
                  ),
                ],
              ],
            );
          }),

          const SizedBox(height: 32),

          // Próximo Control (Destacado)
          const Text(
            'SEGUIMIENTO CLÍNICO',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: NutritionPalette.accent, fontFamily: kArial),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: _pickProximoControl,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: NutritionPalette.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _proximoControl != null ? NutritionPalette.accent : NutritionPalette.border, width: 2),
              ),
              child: Row(
                children: [
                  Icon(Icons.event_available, color: _proximoControl != null ? NutritionPalette.accent : NutritionPalette.textMuted, size: 28),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Fecha de Próximo Control', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, fontFamily: kArial)),
                        Text(
                          _proximoControl != null 
                            ? DateFormat('EEEE, dd MMMM yyyy', 'es_CO').format(_proximoControl!)
                            : 'Selecciona la fecha para la reevaluación',
                          style: TextStyle(color: _proximoControl != null ? NutritionPalette.accent : NutritionPalette.textMuted, fontSize: 13, fontFamily: kArial),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.calendar_today_outlined, size: 18, color: NutritionPalette.textMuted),
                ],
              ),
            ),
          ),

          const SizedBox(height: 32),

          // Observaciones
          TextFormField(
            controller: _observacionesPlanCtrl,
            decoration: const InputDecoration(
              labelText: 'Indicaciones y Observaciones del Plan',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
              hintText: 'Ej: Restricción de sodio, fraccionar comidas en 5 tiempos...',
            ),
            maxLines: 4,
          ),
        ],
      ),
    );
  }

  // ── Paso 3: Cierre / Evidencias ─────────────────────────────────────────────

  Widget _buildEvidenciasTabContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(40),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: NutritionPalette.success.withOpacity(0.05),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.verified_user, color: NutritionPalette.success, size: 64),
          ),
          const SizedBox(height: 24),
          const Text(
            'Sesión Clínica Finalizada',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: NutritionPalette.textMain, fontFamily: kArial),
          ),
          const SizedBox(height: 8),
          const Text(
            'El proceso ha sido registrado. Puedes generar el soporte documental técnico ahora.',
            textAlign: TextAlign.center,
            style: TextStyle(color: NutritionPalette.textMuted, fontSize: 14, fontFamily: kArial),
          ),
          const SizedBox(height: 48),
          
          NutritionCard(
            title: 'Soporte Documental Técnico',
            subtitle: 'Generación de reporte en formato PDF clínico',
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                _buildCheckItem(Icons.check_circle, 'Historia y Antecedentes integrados'),
                _buildCheckItem(Icons.check_circle, 'Evaluación antropométrica registrada'),
                _buildCheckItem(Icons.check_circle, 'Diagnóstico y Plan Nutricional definido'),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton.icon(
                    onPressed: _selectedPaciente == null ? null : _generarPDF,
                    icon: const Icon(Icons.picture_as_pdf, size: 24),
                    label: const Text('GENERAR Y DESCARGAR REPORTE PDF', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                    style: FilledButton.styleFrom(
                      backgroundColor: NutritionPalette.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckItem(IconData icon, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: NutritionPalette.success, size: 20),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(fontSize: 13, color: NutritionPalette.textMain, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  // ── Callbacks y acciones ────────────────────────────────────────────────────

  void _onDiagnosticosChanged(
      List<DiagnosticoMedico> m, List<DiagnosticoNutricional> n) {
    setState(() {
      _diagnosticosMedicosSeleccionados = m;
      _diagnosticosNutricionalesSeleccionados = n;
      _diagnosticoMedicoCtrl.text = m.isNotEmpty ? m.first.nombre : '';
      _diagnosticoNutriCtrl.text = n.isNotEmpty ? n.first.nombre : '';
    });
    // Enriquecer TBL_DIAGNOSTICOS_MEDICOS con datos ICD-11 WHO.
    // enriquecerEnCatalogo() es idempotente (merge:true) y absorbe errores internamente.
    // Solo escribe cuando dx.source == 'who_icd11'; diagnósticos locales son ignorados.
    final svc = DiagnosticosService();
    for (final dx in m) {
      svc.enriquecerEnCatalogo(
        dx: dx,
        empresaId: widget.empresaId,
        userId: widget.userId,
      );
    }
  }

  Future<void> _pickProximoControl() async {
    final d = await showDatePicker(
      context: context,
      initialDate:
          _proximoControl ?? DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (d != null) setState(() => _proximoControl = d);
  }

  /// Abre dialog de remisión/historia clínica para el paciente seleccionado.
  Future<void> _abrirRemision() async {
    if (_selectedPaciente == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Selecciona un paciente primero.')));
      return;
    }
    await showDialog(
      context: context,
      builder: (_) => _DialogRemision(
        pacienteId: _selectedPaciente!.id,
        pacienteNombre: _selectedPaciente!.nombre,
        empresaId: widget.empresaId,
        userId: widget.userId,
      ),
    );
  }

  /// Abre el diálogo de registro de nuevo paciente.
  Future<void> _registrarNuevoPaciente() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _DialogNuevoPaciente(
        empresaId: widget.empresaId,
        userId: widget.userId,
        establecimientos: _establecimientos,
      ),
    );
    if (result != null && mounted) {
      // Paciente creado; se actualiza automáticamente vía stream.
      // Si el resultado tiene el ID guardado, podemos preseleccionar.
      setState(() {
        _nombreCompletoCtrl.text =
            result['nombreCompleto']?.toString() ?? '';
        _documentoCtrl.text = result['documento']?.toString() ?? '';
        _regimenCtrl.text = result['regimenAfiliacion']?.toString() ?? '';
      });
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Paciente registrado correctamente.')));
    }
  }

  /// Finaliza el proceso: guarda expediente, asigna dieta y agenda cita.
  Future<void> _guardarYAgendarCita() async {
    if (_selectedPaciente == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Selecciona un paciente antes de finalizar.'),
          backgroundColor: Colors.orange));
      return;
    }
    if (_proximoControl == null) {
      // Pedir fecha de próximo control si no fue seleccionada
      await _pickProximoControl();
      if (_proximoControl == null) return;
    }

    setState(() => _agendandoCita = true);
    try {
      final svc = NutricionService();
      final citasSvc = CitasNutricionService();

      // 1. Guardar asignación de dieta si hay una seleccionada
      if (_dietaSeleccionadaId != null && _dietaSeleccionadaId!.isNotEmpty) {
        await svc.guardarAsignacionDieta(
          empresaId: widget.empresaId,
          pacienteId: _selectedPaciente!.id,
          dietaId: _dietaSeleccionadaId!,
          fechaInicio: DateTime.now(),
          fechaFin: _proximoControl,
          permanente: _periodoSeleccionado == 'Permanente',
          motivo: _observacionesPlanCtrl.text.trim().isNotEmpty
              ? _observacionesPlanCtrl.text.trim()
              : null,
        );
      }

      // 2. Actualizar el expediente del paciente con los datos de esta atención
      await svc.guardarDirectorioNutricion(
        empresaId: widget.empresaId,
        userId: widget.userId,
        id: _selectedPaciente!.id,
        data: {
          'nombreCompleto': _selectedPaciente!.nombre,
          'documento': _selectedPaciente!.documento,
          'regimenAfiliacion': _regimenCtrl.text.trim(),
          'diagnosticoMedico': _diagnosticoMedicoCtrl.text.trim(),
          'diagnosticoNutricional': _diagnosticoNutriCtrl.text.trim(),
          'tipoDietaSugerida': _tipoDietaCtrl.text.trim(),
          'diagnosticosMedicosData': _diagnosticosMedicosSeleccionados
              .map((d) => d.toMap())
              .toList(),
          'diagnosticosNutricionalesData':
              _diagnosticosNutricionalesSeleccionados
                  .map((d) => d.toMap())
                  .toList(),
          if (_observacionesPlanCtrl.text.trim().isNotEmpty)
            'observacionesPlan': _observacionesPlanCtrl.text.trim(),
        },
      );

      // 3. Guardar entrada en historial
      await svc.guardarHistorialPaciente(
        empresaId: widget.empresaId,
        pacienteId: _selectedPaciente!.id,
        userId: widget.userId,
        datos: {
          'tipo': 'atencion',
          'diagnosticoMedico': _diagnosticoMedicoCtrl.text.trim(),
          'diagnosticoNutricional': _diagnosticoNutriCtrl.text.trim(),
          'dietaAsignada': _tipoDietaCtrl.text.trim(),
          'periodo': _periodoSeleccionado,
          'observaciones': _observacionesPlanCtrl.text.trim(),
          'proximoControl':
              _proximoControl != null ? Timestamp.fromDate(_proximoControl!) : null,
        },
      );

      // 4. Agendar reevaluación + notificación
      await citasSvc.agendarReevaluacion(
        empresaId: widget.empresaId,
        pacienteId: _selectedPaciente!.id,
        pacienteNombre: _selectedPaciente!.nombre,
        pacienteDocumento: _selectedPaciente!.documento,
        userId: widget.userId,
        userNombre: widget.userId,
        fechaReevaluacion: _proximoControl!,
        fechaInicioDieta: DateTime.now(),
        tipoDieta: _tipoDietaCtrl.text.trim().isNotEmpty
            ? _tipoDietaCtrl.text.trim()
            : null,
        diagnosticoMedico: _diagnosticoMedicoCtrl.text.trim().isNotEmpty
            ? _diagnosticoMedicoCtrl.text.trim()
            : null,
        diagnosticoNutricional:
            _diagnosticoNutriCtrl.text.trim().isNotEmpty
                ? _diagnosticoNutriCtrl.text.trim()
                : null,
        observaciones: _observacionesPlanCtrl.text.trim().isNotEmpty
            ? _observacionesPlanCtrl.text.trim()
            : null,
        periodoSeleccionado: _periodoSeleccionado,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Atención finalizada. Próximo control: ${DateFormat('dd/MM/yyyy').format(_proximoControl!)}'),
          backgroundColor: Colors.green[800],
        ));
        // Avanzar a cierre y limpiar selección para próxima atención
        setState(() {
          _pasoActual = 3; // Mostrar paso Cierre
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error al finalizar: $e'),
            backgroundColor: Colors.red[800]));
      }
    } finally {
      if (mounted) setState(() => _agendandoCita = false);
    }
  }

  /// Genera y descarga el PDF técnico del paciente.
  Future<void> _generarPDF() async {
    if (_selectedPaciente == null) return;
    try {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Generando PDF...')));

      // Fetch firma/sello del profesional
      final firmaSnap = await FirebaseFirestore.instance
          .collection('TBL_FIRMAS')
          .doc('${widget.empresaId}-${widget.userId}')
          .get();
      final firmaUrl =
          firmaSnap.data()?['urlFirma']?.toString() ?? '';
      final selloUrl =
          firmaSnap.data()?['urlSello']?.toString() ?? '';

      final pacienteData = <String, dynamic>{
        'nombre': _selectedPaciente!.nombre,
        'documento': _selectedPaciente!.documento,
        'eps': _selectedPaciente!.eps,
        'genero': _selectedPaciente!.genero,
        'regimen': _regimenCtrl.text.trim(),
        'diagnosticoMedico': _diagnosticoMedicoCtrl.text.trim(),
        'diagnosticoNutricional': _diagnosticoNutriCtrl.text.trim(),
        'dieta': _tipoDietaCtrl.text.trim(),
        'periodo': _periodoSeleccionado ?? '',
        'proximoControl': _proximoControl != null
            ? DateFormat('dd/MM/yyyy').format(_proximoControl!)
            : '',
        'pesoKg': _selectedPaciente!.pesoKg?.toString() ?? '',
        'tallaCm': _selectedPaciente!.tallaCm?.toString() ?? '',
        'imc': _selectedPaciente!.imc != null
            ? '${_selectedPaciente!.imc!.toStringAsFixed(1)} (${_imcClasificacion(_selectedPaciente!.imc!)})'
            : '',
        'observaciones': _observacionesPlanCtrl.text.trim(),
      };

      final bytes = await NutricionPdfService().generarReportePDF(
        userId: widget.userId,
        pacienteData: pacienteData,
        firmaUrl: firmaUrl,
        selloUrl: selloUrl,
      );

      if (!mounted) return;

      final fileName =
          'reporte_${_selectedPaciente!.documento}_${DateTime.now().millisecondsSinceEpoch}.pdf';

      if (kIsWeb) {
        await FileSaver.instance.saveFile(
          name: fileName.replaceAll('.pdf', ''),
          bytes: bytes,
          fileExtension: 'pdf',
          mimeType: MimeType.pdf,
        );
      } else {
        final dir = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/$fileName');
        await file.writeAsBytes(bytes);
        await OpenFilex.open(file.path);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('PDF generado con éxito'),
                backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error generando PDF: $e'),
            backgroundColor: Colors.red[800]));
      }
    }
  }

  // ── Widgets auxiliares ──────────────────────────────────────────────────────

  Widget _buildSummaryGrid({required bool isCompact}) {
    return Wrap(spacing: 12, runSpacing: 12, children: [
      const NutritionInfoCard(
          title: 'Sesiones hoy',
          value: '—',
          icon: Icons.person_outline,
          color: NutritionPalette.accent),
      const NutritionInfoCard(
          title: 'Pacientes Activos',
          value: '—',
          icon: Icons.group_outlined,
          color: NutritionPalette.info),
    ]);
  }

  Widget _buildChecklistTile(String t, String s,
      {IconData? icon, VoidCallback? onTap}) {
    return ListTile(
        title:
            Text(t, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(s),
        leading: Icon(icon, color: NutritionPalette.accent),
        onTap: onTap,
        trailing: const Icon(Icons.chevron_right));
  }
}

// ── Modelo de datos del paciente para la UI ────────────────────────────────────

class _PacienteInfo {
  final String id;
  final String nombre;
  final String documento;
  final String eps;
  final String genero;
  final DateTime? fechaNacimiento;
  final String establecimiento;
  final String pabellon;
  final String diagnosticoMedico;
  final String diagnosticoNutricional;
  final String regimenAfiliacion;
  final String tipoDietaSugerida;
  final double? pesoKg;
  final double? tallaCm;
  final double? imc;
  final List<DiagnosticoMedico> diagnosticosMedicos;
  final List<DiagnosticoNutricional> diagnosticosNutricionales;

  const _PacienteInfo({
    required this.id,
    required this.nombre,
    required this.documento,
    this.eps = '',
    this.genero = '',
    this.fechaNacimiento,
    this.establecimiento = '',
    this.pabellon = '',
    this.diagnosticoMedico = '',
    this.diagnosticoNutricional = '',
    this.regimenAfiliacion = '',
    this.tipoDietaSugerida = '',
    this.pesoKg,
    this.tallaCm,
    this.imc,
    this.diagnosticosMedicos = const [],
    this.diagnosticosNutricionales = const [],
  });
}

// ── Dialog: Registro de Nuevo Paciente ─────────────────────────────────────────

class _DialogNuevoPaciente extends StatefulWidget {
  final String empresaId;
  final String userId;
  final List<String> establecimientos;

  const _DialogNuevoPaciente({
    required this.empresaId,
    required this.userId,
    required this.establecimientos,
  });

  @override
  State<_DialogNuevoPaciente> createState() =>
      _DialogNuevoPacienteState();
}

class _DialogNuevoPacienteState extends State<_DialogNuevoPaciente> {
  final _formKey = GlobalKey<FormState>();
  final _nombreCtrl = TextEditingController();
  final _documentoCtrl = TextEditingController();
  final _epsCtrl = TextEditingController();
  final _pabellonCtrl = TextEditingController();
  final _diagnosticoCtrl = TextEditingController();
  final _observacionesCtrl = TextEditingController();
  final _pesoCtrl = TextEditingController();
  final _tallaCtrl = TextEditingController();
  final _dietaIndicadaCtrl = TextEditingController();
  final _vigenciaCtrl = TextEditingController();

  String? _regimen;
  String? _genero;
  String? _establecimientoSeleccionado;
  DateTime? _fechaNacimiento;
  double? _imcCalculado;
  bool _guardando = false;
  XFile? _foto;

  static const _regimenes = ['Contributivo', 'Subsidiado', 'Especial', 'Vinculado'];
  static const _generos = ['Masculino', 'Femenino', 'Otro'];

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _documentoCtrl.dispose();
    _epsCtrl.dispose();
    _pabellonCtrl.dispose();
    _diagnosticoCtrl.dispose();
    _observacionesCtrl.dispose();
    _pesoCtrl.dispose();
    _tallaCtrl.dispose();
    _dietaIndicadaCtrl.dispose();
    _vigenciaCtrl.dispose();
    super.dispose();
  }

  void _calcularIMC() {
    final peso = double.tryParse(_pesoCtrl.text);
    final talla = double.tryParse(_tallaCtrl.text);
    if (peso != null && talla != null && talla > 0) {
      final tallaM = talla / 100;
      setState(() => _imcCalculado = peso / (tallaM * tallaM));
    } else {
      setState(() => _imcCalculado = null);
    }
  }

  Future<void> _pickFecha() async {
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime(1990),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (d != null) setState(() => _fechaNacimiento = d);
  }

  Future<void> _pickFoto() async {
    if (kIsWeb) return; // Web: foto no requerida ni disponible aquí
    final picker = ImagePicker();
    final picked =
        await picker.pickImage(source: ImageSource.camera, imageQuality: 80);
    if (picked != null) setState(() => _foto = picked);
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _guardando = true);
    try {
      final svc = NutricionService();
      String? fotoUrl;

      // Subir foto si fue tomada (solo móvil)
      if (_foto != null && !kIsWeb) {
        final bytes = await _foto!.readAsBytes();
        fotoUrl = await svc.subirFotoPaciente(
          empresaId: widget.empresaId,
          documento: _documentoCtrl.text.trim(),
          bytes: bytes,
        );
      }

      final data = <String, dynamic>{
        'nombreCompleto': _nombreCtrl.text.trim(),
        'nombre': _nombreCtrl.text.trim(),
        'documento': _documentoCtrl.text.trim(),
        'eps': _epsCtrl.text.trim(),
        'regimenAfiliacion': _regimen ?? '',
        'genero': _genero ?? '',
        if (_fechaNacimiento != null)
          'fechaNacimiento': Timestamp.fromDate(_fechaNacimiento!),
        'establecimiento': _establecimientoSeleccionado ?? '',
        'pabellon': _pabellonCtrl.text.trim(),
        'diagnosticoMedico': _diagnosticoCtrl.text.trim(),
        'observaciones': _observacionesCtrl.text.trim(),
        if (_pesoCtrl.text.isNotEmpty)
          'pesoRemision': double.tryParse(_pesoCtrl.text),
        if (_tallaCtrl.text.isNotEmpty)
          'tallaRemision': double.tryParse(_tallaCtrl.text),
        if (_imcCalculado != null)
          'imcRemision': double.parse(_imcCalculado!.toStringAsFixed(2)),
        'tipoDietaSugerida': _dietaIndicadaCtrl.text.trim(),
        'vigenciaDieta': _vigenciaCtrl.text.trim(),
        if (fotoUrl != null) 'fotoUrl': fotoUrl,
      };

      await svc.guardarDirectorioNutricion(
        empresaId: widget.empresaId,
        userId: widget.userId,
        data: data,
      );

      if (mounted) Navigator.of(context).pop(data);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error al guardar: $e'),
            backgroundColor: Colors.red[800]));
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700, maxHeight: 800),
        child: Scaffold(
          backgroundColor: NutritionPalette.background,
          appBar: AppBar(
            title: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Nuevo Registro Clínico', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, fontFamily: kArial)),
                Text('Admisión de paciente al sistema de nutrición', style: TextStyle(fontSize: 11, fontWeight: FontWeight.normal)),
              ],
            ),
            backgroundColor: NutritionPalette.primary,
            foregroundColor: Colors.white,
            automaticallyImplyLeading: false,
            actions: [
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
              const SizedBox(width: 8),
            ],
          ),
          body: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(32),
              children: [
                // ── Foto (Móvil) ────────────────────────────────────
                if (!kIsWeb) ...[
                  Center(child: _buildPhotoSelector()),
                  const SizedBox(height: 32),
                ],

                // ── Datos de identificación ──────────────────────────────
                _buildFormSection(
                  title: 'IDENTIFICACIÓN DEL PACIENTE',
                  icon: Icons.badge_outlined,
                  children: [
                    TextFormField(
                      controller: _nombreCtrl,
                      decoration: const InputDecoration(labelText: 'Nombre Completo *', border: OutlineInputBorder(), prefixIcon: Icon(Icons.person_outline)),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: _documentoCtrl,
                            decoration: const InputDecoration(labelText: 'Documento / ID *', border: OutlineInputBorder(), prefixIcon: Icon(Icons.perm_identity)),
                            keyboardType: TextInputType.number,
                            validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _genero,
                            decoration: const InputDecoration(labelText: 'Género', border: OutlineInputBorder()),
                            items: _generos.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                            onChanged: (v) => setState(() => _genero = v),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _pickFecha,
                      icon: const Icon(Icons.cake_outlined),
                      label: Text(_fechaNacimiento != null ? 'Nacido el: ${DateFormat('dd/MM/yyyy').format(_fechaNacimiento!)}' : 'Seleccionar Fecha de Nacimiento'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.all(16),
                        alignment: Alignment.centerLeft,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 32),

                // ── Salud y Régimen ────────────────────────────────────────
                _buildFormSection(
                  title: 'DATOS DE SALUD Y COBERTURA',
                  icon: Icons.health_and_safety_outlined,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _epsCtrl,
                            decoration: const InputDecoration(labelText: 'EPS / Entidad', border: OutlineInputBorder(), prefixIcon: Icon(Icons.local_hospital_outlined)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _regimen,
                            decoration: const InputDecoration(labelText: 'Régimen', border: OutlineInputBorder()),
                            items: _regimenes.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                            onChanged: (v) => setState(() => _regimen = v),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 32),

                // ── Establecimiento y Ubicación ───────────────────────────
                _buildFormSection(
                  title: 'UBICACIÓN Y PROCEDENCIA',
                  icon: Icons.location_on_outlined,
                  children: [
                    DropdownButtonFormField<String>(
                      value: _establecimientoSeleccionado,
                      decoration: const InputDecoration(labelText: 'Sede / Establecimiento', border: OutlineInputBorder(), prefixIcon: Icon(Icons.business_outlined)),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('Sin establecimiento específico')),
                        ...widget.establecimientos.map((e) => DropdownMenuItem(value: e, child: Text(e))),
                      ],
                      onChanged: (v) => setState(() => _establecimientoSeleccionado = v),
                    ),
                    if (_establecimientoSeleccionado != null) ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _pabellonCtrl,
                        decoration: const InputDecoration(labelText: 'Pabellón / Pabellón / Celda / Ubicación', border: OutlineInputBorder(), prefixIcon: Icon(Icons.meeting_room_outlined)),
                      ),
                    ],
                  ],
                ),

                const SizedBox(height: 32),

                // ── Datos Clínicos Iniciales ───────────────────────────
                _buildFormSection(
                  title: 'ANTECEDENTES CLÍNICOS (OPCIONAL)',
                  icon: Icons.medical_services_outlined,
                  children: [
                    TextFormField(
                      controller: _diagnosticoCtrl,
                      decoration: const InputDecoration(labelText: 'Diagnóstico Médico de Remisión', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _pesoCtrl,
                            decoration: const InputDecoration(labelText: 'Peso (kg)', border: OutlineInputBorder()),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            onChanged: (_) => _calcularIMC(),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _tallaCtrl,
                            decoration: const InputDecoration(labelText: 'Talla (cm)', border: OutlineInputBorder()),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            onChanged: (_) => _calcularIMC(),
                          ),
                        ),
                        if (_imcCalculado != null) ...[
                          const SizedBox(width: 16),
                          _buildImcIndicator(),
                        ],
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _dietaIndicadaCtrl,
                      decoration: const InputDecoration(labelText: 'Dieta Inicial Sugerida', border: OutlineInputBorder()),
                    ),
                  ],
                ),

                const SizedBox(height: 48),

                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton(
                    onPressed: _guardando ? null : _guardar,
                    style: FilledButton.styleFrom(backgroundColor: NutritionPalette.accent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                    child: _guardando
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('FINALIZAR REGISTRO E INGRESAR', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoSelector() {
    return Column(
      children: [
        Stack(
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: NutritionPalette.surface,
                shape: BoxShape.circle,
                border: Border.all(color: NutritionPalette.border, width: 4),
                image: _foto != null 
                  ? DecorationImage(image: FileImage(File(_foto!.path)), fit: BoxFit.cover)
                  : null,
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
                ],
              ),
              child: _foto == null 
                ? const Icon(Icons.person_outline, size: 60, color: NutritionPalette.textMuted)
                : null,
            ),
            Positioned(
              bottom: 0,
              right: 0,
              child: FloatingActionButton.small(
                onPressed: _pickFoto,
                backgroundColor: NutritionPalette.accent,
                foregroundColor: Colors.white,
                child: const Icon(Icons.camera_alt),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text('Foto de identificación', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: NutritionPalette.textMuted)),
      ],
    );
  }

  Widget _buildFormSection({required String title, required IconData icon, required List<Widget> children}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: NutritionPalette.accent),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 1.0, color: NutritionPalette.accent, fontFamily: kArial),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ...children,
      ],
    );
  }

  Widget _buildImcIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: NutritionPalette.accent.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: NutritionPalette.accent.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          const Text('IMC', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: NutritionPalette.textMuted)),
          Text(_imcCalculado!.toStringAsFixed(1), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: NutritionPalette.accent)),
        ],
      ),
    );
  }
}

// ── Dialog: Remisión / Historia clínica ────────────────────────────────────────

class _DialogRemision extends StatefulWidget {
  final String pacienteId;
  final String pacienteNombre;
  final String empresaId;
  final String userId;

  const _DialogRemision({
    required this.pacienteId,
    required this.pacienteNombre,
    required this.empresaId,
    required this.userId,
  });

  @override
  State<_DialogRemision> createState() => _DialogRemisionState();
}

class _DialogRemisionState extends State<_DialogRemision> {
  final _diagnosticoCtrl = TextEditingController();
  final _observacionesCtrl = TextEditingController();
  final _pesoCtrl = TextEditingController();
  final _tallaCtrl = TextEditingController();
  final _dietaCtrl = TextEditingController();
  double? _imcCalc;
  bool _guardando = false;
  XFile? _archivoRemision;

  @override
  void dispose() {
    _diagnosticoCtrl.dispose();
    _observacionesCtrl.dispose();
    _pesoCtrl.dispose();
    _tallaCtrl.dispose();
    _dietaCtrl.dispose();
    super.dispose();
  }

  void _calcImc() {
    final p = double.tryParse(_pesoCtrl.text);
    final t = double.tryParse(_tallaCtrl.text);
    if (p != null && t != null && t > 0) {
      setState(() => _imcCalc = p / ((t / 100) * (t / 100)));
    }
  }

  Future<void> _pickArchivo() async {
    if (kIsWeb) return;
    final picker = ImagePicker();
    final picked = await picker.pickImage(
        source: ImageSource.gallery, imageQuality: 80);
    if (picked != null) setState(() => _archivoRemision = picked);
  }

  Future<void> _guardar() async {
    setState(() => _guardando = true);
    try {
      final svc = NutricionService();
      await svc.guardarHistorialPaciente(
        empresaId: widget.empresaId,
        pacienteId: widget.pacienteId,
        userId: widget.userId,
        datos: {
          'tipo': 'remision',
          'diagnostico': _diagnosticoCtrl.text.trim(),
          'observaciones': _observacionesCtrl.text.trim(),
          'pesoRemision': double.tryParse(_pesoCtrl.text),
          'tallaRemision': double.tryParse(_tallaCtrl.text),
          'imcRemision': _imcCalc,
          'dietaIndicada': _dietaCtrl.text.trim(),
        },
      );
      // Si hay foto/archivo, subir como evidencia
      if (_archivoRemision != null && !kIsWeb) {
        final bytes = await _archivoRemision!.readAsBytes();
        await svc.guardarEvidenciaProceso(
          empresaId: widget.empresaId,
          userId: widget.userId,
          bytes: bytes,
          tipo: 'remision_${widget.pacienteId}',
        );
      }
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Remisión guardada en expediente.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error: $e'), backgroundColor: Colors.red[800]));
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 650),
        child: Scaffold(
          backgroundColor: NutritionPalette.background,
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Remisión Médica', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, fontFamily: kArial)),
                Text(widget.pacienteNombre, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.normal)),
              ],
            ),
            backgroundColor: NutritionPalette.primary,
            foregroundColor: Colors.white,
            automaticallyImplyLeading: false,
            actions: [
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
              const SizedBox(width: 8),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(32),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: NutritionPalette.accent.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: NutritionPalette.accent.withOpacity(0.1)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: NutritionPalette.accent, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Registra los datos de la remisión externa para integrarlos al expediente clínico del paciente.',
                        style: TextStyle(fontSize: 12, color: NutritionPalette.textMain, fontFamily: kArial),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              
              const _SectionHeader('INFORMACIÓN CLÍNICA DE REFERENCIA'),
              TextFormField(
                controller: _diagnosticoCtrl,
                decoration: const InputDecoration(labelText: 'Diagnóstico Médico Principal', border: OutlineInputBorder(), prefixIcon: Icon(Icons.medication_outlined)),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _pesoCtrl,
                      decoration: const InputDecoration(labelText: 'Peso Remisión (kg)', border: OutlineInputBorder()),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => _calcImc(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _tallaCtrl,
                      decoration: const InputDecoration(labelText: 'Talla Remisión (cm)', border: OutlineInputBorder()),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => _calcImc(),
                    ),
                  ),
                  if (_imcCalc != null) ...[
                    const SizedBox(width: 16),
                    Column(
                      children: [
                        const Text('IMC', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: NutritionPalette.textMuted)),
                        Text(_imcCalc!.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: NutritionPalette.accent)),
                      ],
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _dietaCtrl,
                decoration: const InputDecoration(labelText: 'Dieta Prescrita en Remisión', border: OutlineInputBorder(), prefixIcon: Icon(Icons.restaurant_outlined)),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _observacionesCtrl,
                decoration: const InputDecoration(labelText: 'Observaciones Médicas / Motivo', border: OutlineInputBorder(), alignLabelWithHint: true),
                maxLines: 3,
              ),
              
              if (!kIsWeb) ...[
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: _pickArchivo,
                  icon: const Icon(Icons.attach_file),
                  label: Text(_archivoRemision != null ? 'DOCUMENTO ADJUNTO ✓' : 'ADJUNTAR SOPORTE DE REMISIÓN'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                    foregroundColor: _archivoRemision != null ? NutritionPalette.success : NutritionPalette.accent,
                    side: BorderSide(color: _archivoRemision != null ? NutritionPalette.success : NutritionPalette.accent),
                  ),
                ),
              ],
              
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  onPressed: _guardando ? null : _guardar,
                  style: FilledButton.styleFrom(backgroundColor: NutritionPalette.accent),
                  child: _guardando
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('INTEGRAR REMISIÓN AL EXPEDIENTE', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Widget auxiliar: encabezado de sección ──────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(title,
          style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: NutritionPalette.accent,
              letterSpacing: 0.5)),
    );
  }
}
