// lib/talento_humano/talento_humano_dashboard_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/guarded_module_page.dart';
import '../home/widgets/home_shared_widgets.dart'
    show CompanyLogoAvatar, CompanyNameWidget;
import '../widgets/internal_module_layout.dart';
import 'areas_management_screen.dart';
import 'cargos_management_screen.dart';
import 'centros_costos_management_screen.dart';
import 'disciplinary_management_screen.dart';
import 'hoja_de_vida_management_screen.dart';
import 'hv_dashboard_screen.dart';
import 'notificaciones_talento_humano_screen.dart';
import 'organizational_structure_screen.dart';
import 'personnel_access_screen.dart';
import 'personnel_import_screen.dart';
import 'personnel_requisition_screen.dart';
import 'resume_management_report.dart';
import 'talento_humano_dashboard_service.dart';

const Color _khPrimary = Color(0xFFC28942);
const Color _khInk = Color(0xFF111827);
const Color _khMuted = Color(0xFF64748B);
const Color _khBorder = Color(0xFFE2E8F0);
const String _kFont = 'Arial';

class TalentoHumanoDashboardScreen extends StatefulWidget {
  final String userId;
  final String empresaId;

  const TalentoHumanoDashboardScreen({
    super.key,
    required this.userId,
    required this.empresaId,
  });

  @override
  State<TalentoHumanoDashboardScreen> createState() =>
      _TalentoHumanoDashboardScreenState();
}

class _TalentoHumanoDashboardScreenState
    extends State<TalentoHumanoDashboardScreen> {
  final _dashboardService = TalentoHumanoDashboardService();
  late Future<TalentoHumanoDashboardData> _dashboardFuture;
  bool _exportingResumeReport = false;

  String get userId => widget.userId;
  String get empresaId => widget.empresaId;

  @override
  void initState() {
    super.initState();
    _dashboardFuture = _dashboardService.load(empresaId);
  }

  @override
  void didUpdateWidget(covariant TalentoHumanoDashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.empresaId != empresaId) _refreshDashboard();
  }

  void _refreshDashboard() {
    setState(() => _dashboardFuture = _dashboardService.load(empresaId));
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 900;

    return GuardedModulePage(
      userIdentity: userId,
      appId: 'talentohumanodashboard',
      pageTitle: 'Talento Humano',
      fallbackEmpresaId: empresaId,
      child: InternalModuleLayout(
        userId: userId,
        empresaId: empresaId,
        title: 'Talento Humano',
        subtitle:
            'Gestión de colaboradores, cargos y estructura organizacional',
        accentColor: _khPrimary,
        headerActions: [
          CompanyLogoAvatar(
            empresaId: empresaId,
            radius: isDesktop ? 18 : 15,
            backgroundColor: isDesktop ? null : Colors.white,
            foregroundColor: isDesktop ? null : _khPrimary,
          ),
          if (isDesktop)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 280),
              child: CompanyNameWidget(
                empresaId: empresaId,
                style: const TextStyle(
                  color: _khPrimary,
                  fontFamily: _kFont,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ),
        ],
        child: isDesktop
            ? _buildDesktopDashboard(context)
            : _buildMobileDashboard(context),
      ),
    );
  }

  Widget _buildDesktopDashboard(BuildContext context) {
    final actions = _moduleActions(
      context,
    ).where((action) => action.title != 'Gestión de personal').toList();

    return SingleChildScrollView(
      child: InternalModuleViewport(
        maxWidth: 1060,
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildControlDashboard(context, compact: false),
            const SizedBox(height: 24),
            _PeopleHero(
              onViewPeople: () => _openPeople(context),
              onImport: () => _openImport(context),
            ),
            const SizedBox(height: 28),
            const _SectionHeader(
              title: 'Herramientas del área',
              subtitle: 'Documentación, estructura, reportes y comunicación',
            ),
            const SizedBox(height: 14),
            ModuleCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < actions.length; i++) ...[
                    _CompactActionRow(item: actions[i]),
                    if (i < actions.length - 1)
                      const Divider(height: 1, indent: 76, color: _khBorder),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileDashboard(BuildContext context) {
    final actions = _moduleActions(
      context,
    ).where((action) => action.title != 'Gestión de personal').toList();

    return SingleChildScrollView(
      child: InternalModuleViewport(
        maxWidth: 680,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildControlDashboard(context, compact: true),
            const SizedBox(height: 16),
            _MobilePeopleCard(
              onViewPeople: () => _openPeople(context),
              onImport: () => _openImport(context),
            ),
            const SizedBox(height: 22),
            const _SectionHeader(
              title: 'Más herramientas',
              subtitle: 'Elige la tarea que necesitas resolver ahora',
              compact: true,
            ),
            const SizedBox(height: 10),
            for (var i = 0; i < actions.length; i++) ...[
              _CompactActionRow(item: actions[i], mobile: true),
              if (i < actions.length - 1) const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildControlDashboard(BuildContext context, {required bool compact}) {
    return FutureBuilder<TalentoHumanoDashboardData>(
      future: _dashboardFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _DashboardLoading(compact: compact);
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return _DashboardError(compact: compact, onRetry: _refreshDashboard);
        }
        return _HumanTalentControlDashboard(
          data: snapshot.data!,
          compact: compact,
          onRefresh: _refreshDashboard,
          onPeople: () => _openPeople(context),
          onResumes: () => _openResumes(context),
          onCostCenters: () => _openCostCenters(context),
          onDisciplinary: () => _openDisciplinary(context),
          onRequisitions: () => _openRequisitions(context),
          exportingResumeReport: _exportingResumeReport,
          onExportResumeReport: () => _exportResumeReport(snapshot.data!),
        );
      },
    );
  }

  void _openPeople(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            OrganizationalStructureScreen(userId: userId, empresaId: empresaId),
      ),
    );
  }

  Future<void> _exportResumeReport(TalentoHumanoDashboardData data) async {
    if (_exportingResumeReport) return;
    setState(() => _exportingResumeReport = true);
    try {
      var companyName = empresaId;
      try {
        final company = await FirebaseFirestore.instance
            .collection('TBL_EMPRESAS')
            .doc(empresaId)
            .get();
        final resolvedName = (company.data()?['nombre'] ?? '')
            .toString()
            .trim();
        if (resolvedName.isNotEmpty) companyName = resolvedName;
      } catch (_) {
        // El informe sigue siendo útil con el identificador de la empresa.
      }
      final bytes = buildResumeManagementReport(
        rows: data.pendingResumePeople,
        empresaId: empresaId,
        empresaNombre: companyName,
      );
      await FileSaver.instance.saveFile(
        name:
            'gestion_hojas_de_vida_${empresaId}_${DateFormat('yyyyMMdd').format(DateTime.now())}',
        bytes: bytes,
        fileExtension: 'xlsx',
        mimeType: MimeType.microsoftExcel,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            data.pendingResumePeople.isEmpty
                ? 'Informe generado: no hay hojas de vida pendientes.'
                : 'Informe generado con ${data.pendingResumePeople.length} persona(s) por gestionar.',
          ),
          backgroundColor: const Color(0xFF176B45),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No fue posible generar el informe: $error'),
          backgroundColor: const Color(0xFFB42318),
        ),
      );
    } finally {
      if (mounted) setState(() => _exportingResumeReport = false);
    }
  }

  void _openRequisitions(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            PersonnelRequisitionScreen(userId: userId, empresaId: empresaId),
      ),
    ).then((_) => _refreshDashboard());
  }

  void _openImport(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            PersonnelImportScreen(userId: userId, empresaId: empresaId),
      ),
    );
  }

  void _openResumes(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            HojaDeVidaManagementScreen(userId: userId, empresaId: empresaId),
      ),
    ).then((_) => _refreshDashboard());
  }

  void _openCostCenters(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            CentrosCostosManagementScreen(userId: userId, empresaId: empresaId),
      ),
    ).then((_) => _refreshDashboard());
  }

  void _openDisciplinary(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            DisciplinaryManagementScreen(userId: userId, empresaId: empresaId),
      ),
    ).then((_) => _refreshDashboard());
  }

  List<_HumanTalentAction> _moduleActions(BuildContext context) {
    return [
      _HumanTalentAction(
        section: 'Selección',
        title: 'Requerimientos de personal',
        description:
            'Vacantes por empresa, tiempos de respuesta y proceso de contratación.',
        icon: Icons.person_search_rounded,
        color: const Color(0xFF16805B),
        metric: 'Seguimiento de vacantes',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PersonnelRequisitionScreen(
              userId: userId,
              empresaId: empresaId,
            ),
          ),
        ),
      ),
      _HumanTalentAction(
        section: 'Documentación',
        title: 'Hojas de Vida',
        description: 'Revisión, aprobación y correcciones de perfiles.',
        icon: Icons.assignment_ind_rounded,
        color: const Color(0xFF2563EB),
        metric: 'Control documental',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => HojaDeVidaManagementScreen(
              userId: userId,
              empresaId: empresaId,
            ),
          ),
        ),
      ),
      _HumanTalentAction(
        section: 'Documentación',
        title: 'Dashboard HV',
        description:
            'Estadísticas de registro, perfiles y datos sociodemográficos.',
        icon: Icons.insert_chart_outlined_rounded,
        color: _khPrimary,
        metric: 'Analítica de personas',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => HvDashboardScreen(empresaId: empresaId),
          ),
        ),
      ),
      _HumanTalentAction(
        section: 'Organización',
        title: 'Centros de costo',
        description: 'Configura el catálogo operativo de la empresa activa.',
        icon: Icons.account_tree_outlined,
        color: const Color(0xFF0369A1),
        metric: 'Catálogo empresarial',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CentrosCostosManagementScreen(
              userId: userId,
              empresaId: empresaId,
            ),
          ),
        ),
      ),
      _HumanTalentAction(
        section: 'Organización',
        title: 'Gestionar Áreas',
        description: 'Administra las unidades base de la estructura.',
        icon: Icons.apartment_rounded,
        color: const Color(0xFF0F766E),
        metric: 'Mapa de áreas',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                AreasManagementScreen(userId: userId, empresaId: empresaId),
          ),
        ),
      ),
      _HumanTalentAction(
        section: 'Organización',
        title: 'Gestionar Cargos',
        description: 'Define cargos, jerarquías y responsabilidades.',
        icon: Icons.badge_rounded,
        color: const Color(0xFF7C3AED),
        metric: 'Perfiles laborales',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                CargosManagementScreen(userId: userId, empresaId: empresaId),
          ),
        ),
      ),
      _HumanTalentAction(
        section: 'Personas',
        title: 'Gestión de personal',
        description:
            'Administra vinculaciones, retiros, estructura e historial sin borrar personas.',
        icon: Icons.groups_2_rounded,
        color: const Color(0xFFEA580C),
        metric: 'Activos e inactivos',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => OrganizationalStructureScreen(
              userId: userId,
              empresaId: empresaId,
            ),
          ),
        ),
      ),
      _HumanTalentAction(
        section: 'Personas',
        title: 'Accesos del personal',
        description:
            'Define qué módulos usa cada persona dentro de la app. '
            'Notificaciones y calendario los tiene todo el personal.',
        icon: Icons.app_registration_rounded,
        color: const Color(0xFF2563EB),
        metric: 'Sin lenguaje técnico',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                PersonnelAccessScreen(userId: userId, empresaId: empresaId),
          ),
        ),
      ),
      _HumanTalentAction(
        section: 'Relaciones laborales',
        title: 'Proceso disciplinario',
        description:
            'Carpetas disciplinarias, respuestas, descargos y seguimiento.',
        icon: Icons.record_voice_over_rounded,
        color: const Color(0xFF9A5B32),
        metric: 'Historial por persona',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DisciplinaryManagementScreen(
              userId: userId,
              empresaId: empresaId,
            ),
          ),
        ),
      ),
      _HumanTalentAction(
        section: 'Comunicación',
        title: 'Notificaciones TH',
        description: 'Envía comunicados a colaboradores y equipos.',
        icon: Icons.campaign_rounded,
        color: const Color(0xFF0891B2),
        metric: 'Comunicados',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => NotificacionesTalentoHumanoScreen(
              userId: userId,
              empresaId: empresaId,
            ),
          ),
        ),
      ),
    ];
  }
}

class _HumanTalentControlDashboard extends StatelessWidget {
  final TalentoHumanoDashboardData data;
  final bool compact;
  final VoidCallback onRefresh;
  final VoidCallback onPeople;
  final VoidCallback onResumes;
  final VoidCallback onCostCenters;
  final VoidCallback onDisciplinary;
  final VoidCallback onRequisitions;
  final VoidCallback onExportResumeReport;
  final bool exportingResumeReport;

  const _HumanTalentControlDashboard({
    required this.data,
    required this.compact,
    required this.onRefresh,
    required this.onPeople,
    required this.onResumes,
    required this.onCostCenters,
    required this.onDisciplinary,
    required this.onRequisitions,
    required this.onExportResumeReport,
    required this.exportingResumeReport,
  });

  @override
  Widget build(BuildContext context) {
    final metrics = [
      _ControlMetric(
        label: 'Personal activo',
        value: '${data.activePeople}',
        detail:
            '${data.inactivePeople} inactivo(s) · ${data.totalPeople} total',
        icon: Icons.people_alt_rounded,
        color: const Color(0xFF15803D),
        onTap: onPeople,
      ),
      _ControlMetric(
        label: 'Hojas de vida pendientes',
        value: '${data.pendingResumes}',
        detail: '${data.approvedResumes} aprobada(s)',
        icon: Icons.fact_check_outlined,
        color: const Color(0xFF2563EB),
        onTap: onResumes,
      ),
      _ControlMetric(
        label: 'Sin centro de costo',
        value: '${data.peopleWithoutCostCenter}',
        detail: '${(data.costCenterCoverage * 100).round()}% con asignación',
        icon: Icons.account_tree_outlined,
        color: const Color(0xFFB45309),
        onTap: onCostCenters,
      ),
      _ControlMetric(
        label: 'Solicitudes de personal',
        value: '${data.openPersonnelRequests}',
        detail:
            '${data.pendingPersonnelVacancies} vacante(s) · ${data.priorityPersonnelRequests} prioritaria(s)',
        icon: Icons.person_search_rounded,
        color: const Color(0xFF7C3AED),
        onTap: onRequisitions,
      ),
      _ControlMetric(
        label: 'Procesos abiertos',
        value: '${data.openDisciplinaryCases}',
        detail: '${data.highSeverityCases} de prioridad alta',
        icon: Icons.gavel_rounded,
        color: const Color(0xFFB91C1C),
        onTap: onDisciplinary,
      ),
    ];

    return Container(
      padding: EdgeInsets.all(compact ? 16 : 22),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border.all(color: _khBorder),
        borderRadius: BorderRadius.circular(compact ? 18 : 22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: compact ? 42 : 48,
                height: compact ? 42 : 48,
                decoration: BoxDecoration(
                  color: _khPrimary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.space_dashboard_rounded,
                  color: _khPrimary,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      compact
                          ? 'Control de Talento Humano'
                          : 'Centro de control diario',
                      style: TextStyle(
                        fontFamily: _kFont,
                        color: _khInk,
                        fontSize: compact ? 18 : 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Revisa lo pendiente y entra directamente a resolverlo.',
                      style: TextStyle(
                        fontFamily: _kFont,
                        color: _khMuted,
                        fontSize: compact ? 12 : 13,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              if (compact)
                IconButton(
                  onPressed: exportingResumeReport
                      ? null
                      : onExportResumeReport,
                  tooltip: 'Excel de hojas de vida pendientes',
                  icon: exportingResumeReport
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download_rounded),
                )
              else
                OutlinedButton.icon(
                  onPressed: exportingResumeReport
                      ? null
                      : onExportResumeReport,
                  icon: exportingResumeReport
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download_rounded),
                  label: const Text('Excel pendientes HV'),
                ),
              IconButton(
                onPressed: onRefresh,
                tooltip: 'Actualizar indicadores',
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          if (data.isPartial) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFED7AA)),
              ),
              child: Text(
                'Vista parcial: no fue posible consultar ${data.unavailableSources.join(', ')}.',
                style: const TextStyle(
                  fontFamily: _kFont,
                  color: Color(0xFF9A3412),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
          SizedBox(height: compact ? 14 : 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = compact ? 2 : 5;
              final spacing = compact ? 9.0 : 12.0;
              final width =
                  (constraints.maxWidth - (spacing * (columns - 1))) / columns;
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: metrics
                    .map(
                      (metric) => SizedBox(
                        width: width,
                        child: _ControlMetricCard(
                          metric: metric,
                          compact: compact,
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
          SizedBox(height: compact ? 14 : 18),
          if (compact) ...[
            _PriorityWorkCard(
              data: data,
              compact: true,
              onPeople: onPeople,
              onResumes: onResumes,
              onCostCenters: onCostCenters,
              onDisciplinary: onDisciplinary,
              onRequisitions: onRequisitions,
            ),
            const SizedBox(height: 12),
            _PeopleDistributionCard(data: data, compact: true),
          ] else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 11,
                  child: _PriorityWorkCard(
                    data: data,
                    compact: false,
                    onPeople: onPeople,
                    onResumes: onResumes,
                    onCostCenters: onCostCenters,
                    onDisciplinary: onDisciplinary,
                    onRequisitions: onRequisitions,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  flex: 9,
                  child: _PeopleDistributionCard(data: data, compact: false),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _ControlMetric {
  final String label;
  final String value;
  final String detail;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ControlMetric({
    required this.label,
    required this.value,
    required this.detail,
    required this.icon,
    required this.color,
    required this.onTap,
  });
}

class _ControlMetricCard extends StatelessWidget {
  final _ControlMetric metric;
  final bool compact;

  const _ControlMetricCard({required this.metric, required this.compact});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: metric.onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          constraints: BoxConstraints(minHeight: compact ? 126 : 132),
          padding: EdgeInsets.all(compact ? 12 : 15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _khBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(metric.icon, color: metric.color, size: compact ? 21 : 23),
              const Spacer(),
              Text(
                metric.value,
                style: TextStyle(
                  fontFamily: _kFont,
                  color: _khInk,
                  fontSize: compact ? 25 : 29,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                metric.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: _kFont,
                  color: _khInk,
                  fontSize: compact ? 11 : 12,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                metric.detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: _kFont,
                  color: _khMuted,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PriorityWorkCard extends StatelessWidget {
  final TalentoHumanoDashboardData data;
  final bool compact;
  final VoidCallback onPeople;
  final VoidCallback onResumes;
  final VoidCallback onCostCenters;
  final VoidCallback onDisciplinary;
  final VoidCallback onRequisitions;

  const _PriorityWorkCard({
    required this.data,
    required this.compact,
    required this.onPeople,
    required this.onResumes,
    required this.onCostCenters,
    required this.onDisciplinary,
    required this.onRequisitions,
  });

  @override
  Widget build(BuildContext context) {
    final tasks = <_PriorityTask>[];
    if (data.priorityPersonnelRequests > 0) {
      tasks.add(
        _PriorityTask(
          title:
              '${data.priorityPersonnelRequests} solicitud(es) de personal prioritarias',
          subtitle:
              '${data.pendingPersonnelVacancies} vacante(s) siguen pendientes de contratación.',
          icon: Icons.person_search_rounded,
          color: const Color(0xFFDC2626),
          onTap: onRequisitions,
        ),
      );
    }
    if (data.resumesWithChanges > 0) {
      tasks.add(
        _PriorityTask(
          title: '${data.resumesWithChanges} hoja(s) de vida con correcciones',
          subtitle: 'Revisa qué debe ajustar cada colaborador.',
          icon: Icons.edit_note_rounded,
          color: const Color(0xFFDC2626),
          onTap: onResumes,
        ),
      );
    }
    if (data.resumesInReview > 0 || data.resumesNotSent > 0) {
      tasks.add(
        _PriorityTask(
          title:
              '${data.resumesInReview} en revisión · ${data.resumesNotSent} sin enviar',
          subtitle: 'Completa el control documental del personal.',
          icon: Icons.assignment_late_outlined,
          color: const Color(0xFFD97706),
          onTap: onResumes,
        ),
      );
    }
    if (data.peopleWithoutCostCenter > 0 || data.peopleWithoutArea > 0) {
      tasks.add(
        _PriorityTask(
          title:
              '${data.peopleWithoutCostCenter} sin centro · ${data.peopleWithoutArea} sin área',
          subtitle: 'Ubica al personal dentro de la estructura de la empresa.',
          icon: Icons.account_tree_outlined,
          color: const Color(0xFF0369A1),
          onTap: data.peopleWithoutCostCenter > 0 ? onCostCenters : onPeople,
        ),
      );
    }
    if (data.openDisciplinaryCases > 0) {
      tasks.add(
        _PriorityTask(
          title: '${data.openDisciplinaryCases} proceso(s) por atender',
          subtitle:
              '${data.highSeverityCases} de prioridad alta requieren seguimiento.',
          icon: Icons.record_voice_over_rounded,
          color: const Color(0xFF9A3412),
          onTap: onDisciplinary,
        ),
      );
    }

    return Container(
      padding: EdgeInsets.all(compact ? 14 : 17),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _khBorder),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Qué requiere atención',
            style: TextStyle(
              fontFamily: _kFont,
              color: _khInk,
              fontWeight: FontWeight.w900,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 3),
          const Text(
            'Toca una fila para resolverla en su módulo.',
            style: TextStyle(fontFamily: _kFont, color: _khMuted, fontSize: 11),
          ),
          const SizedBox(height: 11),
          if (tasks.isEmpty)
            const _AllClearState()
          else
            for (var i = 0; i < tasks.length; i++) ...[
              _PriorityTaskRow(task: tasks[i]),
              if (i < tasks.length - 1)
                const Divider(height: 14, color: _khBorder),
            ],
        ],
      ),
    );
  }
}

class _PriorityTask {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _PriorityTask({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });
}

class _PriorityTaskRow extends StatelessWidget {
  final _PriorityTask task;

  const _PriorityTaskRow({required this.task});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: task.onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: task.color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(task.icon, color: task.color, size: 20),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    style: const TextStyle(
                      fontFamily: _kFont,
                      color: _khInk,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    task.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: _kFont,
                      color: _khMuted,
                      fontSize: 10,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: _khMuted),
          ],
        ),
      ),
    );
  }
}

class _AllClearState extends StatelessWidget {
  const _AllClearState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        children: [
          Icon(Icons.check_circle_rounded, color: Color(0xFF15803D)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'No hay pendientes críticos en este momento.',
              style: TextStyle(
                fontFamily: _kFont,
                color: Color(0xFF166534),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PeopleDistributionCard extends StatelessWidget {
  final TalentoHumanoDashboardData data;
  final bool compact;

  const _PeopleDistributionCard({required this.data, required this.compact});

  @override
  Widget build(BuildContext context) {
    final activeRatio = data.totalPeople == 0
        ? 0.0
        : data.activePeople / data.totalPeople;
    final maxCenter = data.costCenterDistribution.isEmpty
        ? 1
        : data.costCenterDistribution.first.value;
    return Container(
      padding: EdgeInsets.all(compact ? 14 : 17),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _khBorder),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Distribución del personal',
            style: TextStyle(
              fontFamily: _kFont,
              color: _khInk,
              fontWeight: FontWeight.w900,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 13),
          Row(
            children: [
              SizedBox(
                width: 70,
                height: 70,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: activeRatio,
                      strokeWidth: 9,
                      backgroundColor: const Color(0xFFE2E8F0),
                      color: const Color(0xFF16A34A),
                    ),
                    Text(
                      '${data.totalPeople}',
                      style: const TextStyle(
                        fontFamily: _kFont,
                        color: _khInk,
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _LegendLine(
                      color: const Color(0xFF16A34A),
                      label: 'Activos',
                      value: data.activePeople,
                    ),
                    const SizedBox(height: 8),
                    _LegendLine(
                      color: const Color(0xFFCBD5E1),
                      label: 'Inactivos',
                      value: data.inactivePeople,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${data.activeAreas} áreas · ${data.activeCostCenters} centros activos',
                      style: const TextStyle(
                        fontFamily: _kFont,
                        color: _khMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (data.costCenterDistribution.isNotEmpty) ...[
            const Divider(height: 25, color: _khBorder),
            const Text(
              'Centros con más personal',
              style: TextStyle(
                fontFamily: _kFont,
                color: _khInk,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 9),
            for (final item in data.costCenterDistribution.take(
              compact ? 4 : 3,
            ))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _DistributionBar(item: item, maxValue: maxCenter),
              ),
          ],
        ],
      ),
    );
  }
}

class _LegendLine extends StatelessWidget {
  final Color color;
  final String label;
  final int value;

  const _LegendLine({
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: _kFont,
              color: _khMuted,
              fontSize: 11,
            ),
          ),
        ),
        Text(
          '$value',
          style: const TextStyle(
            fontFamily: _kFont,
            color: _khInk,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _DistributionBar extends StatelessWidget {
  final TalentoHumanoDistributionItem item;
  final int maxValue;

  const _DistributionBar({required this.item, required this.maxValue});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: _kFont,
                  color: _khMuted,
                  fontSize: 10,
                ),
              ),
            ),
            Text(
              '${item.value}',
              style: const TextStyle(
                fontFamily: _kFont,
                color: _khInk,
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            minHeight: 6,
            value: maxValue == 0 ? 0 : item.value / maxValue,
            backgroundColor: const Color(0xFFEFF3F7),
            color: _khPrimary,
          ),
        ),
      ],
    );
  }
}

class _DashboardLoading extends StatelessWidget {
  final bool compact;

  const _DashboardLoading({required this.compact});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: compact ? 390 : 430,
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border.all(color: _khBorder),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: _khPrimary),
            SizedBox(height: 13),
            Text(
              'Organizando la información de Talento Humano…',
              style: TextStyle(
                fontFamily: _kFont,
                color: _khMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardError extends StatelessWidget {
  final bool compact;
  final VoidCallback onRetry;

  const _DashboardError({required this.compact, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 18 : 24),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        border: Border.all(color: const Color(0xFFFED7AA)),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          const Icon(Icons.cloud_off_rounded, color: Color(0xFFC2410C)),
          const SizedBox(height: 8),
          const Text(
            'No fue posible cargar el centro de control.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: _kFont,
              color: Color(0xFF9A3412),
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Intentar nuevamente'),
          ),
        ],
      ),
    );
  }
}

class _PeopleHero extends StatelessWidget {
  final VoidCallback onViewPeople;
  final VoidCallback onImport;

  const _PeopleHero({required this.onViewPeople, required this.onImport});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF173B5E), Color(0xFF275C7F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F173B5E),
            blurRadius: 22,
            offset: Offset(0, 9),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Icon(
              Icons.groups_2_rounded,
              color: Colors.white,
              size: 36,
            ),
          ),
          const SizedBox(width: 24),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Gestión de personal',
                  style: TextStyle(
                    fontFamily: _kFont,
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 24,
                  ),
                ),
                SizedBox(height: 7),
                Text(
                  'Consulta activos e inactivos, conserva el historial y carga nuevos colaboradores desde Excel.',
                  style: TextStyle(
                    fontFamily: _kFont,
                    color: Color(0xFFDCEAF3),
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          OutlinedButton.icon(
            onPressed: onViewPeople,
            icon: const Icon(Icons.people_alt_rounded),
            label: const Text('Ver personal'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Color(0x99FFFFFF)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: onImport,
            icon: const Icon(Icons.upload_file_rounded),
            label: const Text('Cargar desde Excel'),
            style: FilledButton.styleFrom(
              backgroundColor: _khPrimary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
            ),
          ),
        ],
      ),
    );
  }
}

class _MobilePeopleCard extends StatelessWidget {
  final VoidCallback onViewPeople;
  final VoidCallback onImport;

  const _MobilePeopleCard({required this.onViewPeople, required this.onImport});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF173B5E), Color(0xFF275C7F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.groups_2_rounded, color: Colors.white, size: 28),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Gestionar personal',
                  style: TextStyle(
                    fontFamily: _kFont,
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          const Text(
            'Registra, importa y consulta colaboradores sin perder su historial.',
            style: TextStyle(
              fontFamily: _kFont,
              color: Color(0xFFDCEAF3),
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onImport,
            icon: const Icon(Icons.upload_file_rounded),
            label: const Text('Cargar personal desde Excel'),
            style: FilledButton.styleFrom(
              backgroundColor: _khPrimary,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: onViewPeople,
            icon: const Icon(Icons.people_alt_rounded),
            label: const Text('Ver personal registrado'),
            style: TextButton.styleFrom(foregroundColor: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _CompactActionRow extends StatelessWidget {
  final _HumanTalentAction item;
  final bool mobile;

  const _CompactActionRow({required this.item, this.mobile = false});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: mobile ? Colors.white : Colors.transparent,
      borderRadius: BorderRadius.circular(mobile ? 15 : 0),
      child: InkWell(
        onTap: item.onTap,
        borderRadius: BorderRadius.circular(mobile ? 15 : 0),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: mobile ? 15 : 20,
            vertical: mobile ? 13 : 15,
          ),
          decoration: mobile
              ? BoxDecoration(
                  border: Border.all(color: _khBorder),
                  borderRadius: BorderRadius.circular(15),
                )
              : null,
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: item.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(item.icon, color: item.color, size: 21),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: const TextStyle(
                        fontFamily: _kFont,
                        color: _khInk,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.description,
                      maxLines: mobile ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: _kFont,
                        color: _khMuted,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              if (!mobile) ...[
                const SizedBox(width: 14),
                Text(
                  item.metric,
                  style: const TextStyle(
                    fontFamily: _kFont,
                    color: _khMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(width: 10),
              Icon(Icons.chevron_right_rounded, color: item.color),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool compact;

  const _SectionHeader({
    required this.title,
    required this.subtitle,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontFamily: _kFont,
            color: _khInk,
            fontSize: compact ? 17 : 20,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(
            fontFamily: _kFont,
            color: _khMuted,
            fontSize: compact ? 12 : 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _HumanTalentAction {
  final String section;
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final String metric;
  final VoidCallback onTap;

  const _HumanTalentAction({
    required this.section,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.metric,
    required this.onTap,
  });
}
