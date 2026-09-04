import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../theme/app_scroll_behavior.dart' show BarraHorizontal;
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:url_launcher/url_launcher_string.dart';

import '../core/guarded_module_page.dart';
import '../utils/mobile_ocr.dart';
import '../utils/pdf_extractor.dart';
import '../utils/user_company.dart';
import '../widgets/internal_module_layout.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import 'interventoria_hallazgo_panel.dart';
import 'interventoria_maestro_subsanaciones.dart';
import '../widgets/paged_list.dart';
import 'interventoria_actas_catalogo.dart';
import 'interventoria_models.dart';
import 'interventoria_service.dart';
import 'interventoria_tablero_asignacion.dart';
import 'web_pdf_view.dart';

const Color _kAccent = Color(0xFF0F766E);
const Color _kWarning = Color(0xFFEAB308);
const Color _kDanger = Color(0xFFDC2626);
const Color _kOk = Color(0xFF16A34A);
const String _kFont = 'Arial';

/// Tab "Hallazgos" oculto temporalmente a pedido del cliente.
/// Cambiar a `true` para volver a mostrarlo.
const bool kMostrarTabHallazgos = false;

Future<String?> _pedirMotivoEliminacion(
  BuildContext context, {
  required String entidad,
}) async {
  final controller = TextEditingController();
  final accepted = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Solicitar eliminación'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$entidad no se borrará inmediatamente. Una persona autorizada '
            'debe revisar y aprobar la solicitud.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Motivo de la eliminación',
              border: OutlineInputBorder(),
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
          icon: const Icon(Icons.outgoing_mail),
          label: const Text('Enviar solicitud'),
        ),
      ],
    ),
  );
  final reason = controller.text.trim();
  controller.dispose();
  if (accepted != true) return null;
  if (reason.length < 8) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Escribe un motivo de al menos 8 caracteres.'),
        ),
      );
    }
    return null;
  }
  return reason;
}

// ─────────────────────────────────────────────────────────────────────────────
// Root screen
// ─────────────────────────────────────────────────────────────────────────────

class InterventoriaDashboardScreen extends StatefulWidget {
  final String userId;
  final String empresaId;
  final String? rolInterventoria;

  const InterventoriaDashboardScreen({
    super.key,
    required this.userId,
    required this.empresaId,
    this.rolInterventoria,
  });

  @override
  State<InterventoriaDashboardScreen> createState() =>
      _InterventoriaDashboardScreenState();
}

class _InterventoriaDashboardScreenState
    extends State<InterventoriaDashboardScreen> {
  final InterventoriaService _svc = InterventoriaService();
  int _tab = 0;
  String _centroFiltro = '';
  String _estadoFiltro = ''; // '' | 'activo' | 'subsanado'
  String _dptoFiltro = '';

  /// Filtro por persona asignada en Subsanaciones. Vacio = todas.
  /// `_kSinAsignar` aisla los hallazgos que no tienen responsable, que son los
  /// que de verdad hay que perseguir: no le aparecen a nadie en su bandeja.
  String _asignadoFiltro = '';
  DateTime? _fechaDesde;
  DateTime? _fechaHasta;

  // Rol y restricción de centro para Registrador
  String _rol = '';
  bool _rolLoaded = false;

  /// true solo para el usuario con role: 'desarrollador' en TBL_USUARIOS.
  /// Permite reabrir/editar actas ya completadas, sin importar el rol de interventoría.
  bool _esAdminDesarrollo = false;

  /// Si el usuario es Registrador, este ID fija todos los streams a su centro.
  /// Vacío = sin restricción (admin/gerente/etc. ven todo).
  String _centroFijoId = '';

  @override
  void initState() {
    super.initState();
    _loadRolYCentro();
    _loadAdminDesarrollo();
  }

  Future<void> _loadAdminDesarrollo() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('TBL_USUARIOS')
          .doc(widget.userId)
          .get();
      final esDev = doc.exists && isDeveloperUser(doc.data() ?? const {});
      if (mounted) setState(() => _esAdminDesarrollo = esDev);
    } catch (_) {}
  }

  Future<void> _loadRolYCentro() async {
    final rolDoc = await _svc.getRolUsuario(widget.empresaId, widget.userId);
    final rol = widget.rolInterventoria ?? rolDoc?.rol ?? '';
    String centroFijo = '';
    if (rol == kRolInterventoriaRegistrador) {
      centroFijo = await _svc.getCentroCostoId(widget.empresaId, widget.userId);
    }
    if (mounted) {
      setState(() {
        _rol = rol;
        _centroFijoId = centroFijo;
        _rolLoaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GuardedModulePage(
      userIdentity: widget.userId,
      appId: kInterventoriaAppId,
      pageTitle: 'Interventoria',
      fallbackEmpresaId: widget.empresaId,
      child: !_rolLoaded
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final rol = _rol;
    final canWrite = kInterventoriaRolesEscritura.contains(rol);
    final canDirectivo = kInterventoriaRolesDirectivos.contains(rol);
    final canApproveDeletion = puedeAprobarEliminacionInterventoria(rol);
    // Solo el Admin puede registrar puntajes (Fase 1)
    final canFase1 = kInterventoriaRolesFase1.contains(rol);
    // Revisor/Gerente/Directivo/Admin pueden completar actas (Fase 2)
    final canFase2 = kInterventoriaRolesFase2.contains(rol);
    // Registrador heredado: fijo a su centro
    final esRegistrador = rol == kRolInterventoriaRegistrador;
    // El admin de interventoría (badge "ADMINISTRADOR") o el usuario con
    // role:'desarrollador' global pueden reabrir actas ya completadas.
    final esAdminDesarrollo =
        _esAdminDesarrollo || rol == kRolInterventoriaAdmin;

    final centroEfectivo = esRegistrador
        ? _centroFijoId
        : (_centroFiltro.isEmpty ? null : _centroFiltro);

    final tabs = <InternalModuleTabItem>[
      const InternalModuleTabItem(
        label: 'Historico de actas',
        icon: Icons.assignment_rounded,
      ),
      if (canFase2)
        const InternalModuleTabItem(
          label: 'Por revisar',
          icon: Icons.rate_review_rounded,
        ),
      // Hallazgos oculto temporalmente (kMostrarTabHallazgos = false)
      if (kMostrarTabHallazgos)
        const InternalModuleTabItem(
          label: 'Hallazgos',
          icon: Icons.report_problem_rounded,
        ),
      const InternalModuleTabItem(
        label: 'Subsanaciones',
        icon: Icons.grid_on_rounded,
      ),
      if (esAdminDesarrollo)
        const InternalModuleTabItem(
          label: 'Maestro',
          icon: Icons.local_library_outlined,
        ),
      if (canApproveDeletion)
        const InternalModuleTabItem(
          label: 'Permisos de borrado',
          icon: Icons.approval_outlined,
        ),
      if (canDirectivo)
        const InternalModuleTabItem(
          label: 'Analisis',
          icon: Icons.stacked_line_chart_rounded,
        ),
    ];
    if (_tab >= tabs.length) _tab = 0;

    return InternalModuleLayout(
      title: 'Interventoria',
      subtitle: 'Puntajes, hallazgos y seguimiento por centro de costos',
      badge: rol.isEmpty
          ? 'Solo consulta'
          : (kInterventoriaRoleLabels[rol] ?? rol),
      accentColor: _kAccent,
      userId: widget.userId,
      empresaId: widget.empresaId,
      headerActions: [
        if (canFase1)
          FilledButton.icon(
            onPressed: () => _abrirRegistrarActa(context),
            icon: const Icon(Icons.document_scanner_rounded),
            label: const Text('Registrar acta'),
          ),
      ],
      child: Column(
        children: [
          InternalModuleTabs(
            items: tabs,
            selectedIndex: _tab,
            onSelected: (i) => setState(() => _tab = i),
            accentColor: _kAccent,
            compact: MediaQuery.of(context).size.width < 900,
          ),
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: [
                // Tab: Historico de actas (antes "Visitas")
                _VisitasTab(
                  empresaId: widget.empresaId,
                  userId: widget.userId,
                  canWrite: canWrite,
                  service: _svc,
                  centroFijoId: centroEfectivo,
                  onRegistrar: () => _abrirRegistrarActa(context),
                  esAdminDesarrollo: esAdminDesarrollo,
                ),
                // Tab: Por revisar (solo Fase 2) — índice coincide con tabs list
                if (canFase2)
                  _PorRevisarTab(
                    empresaId: widget.empresaId,
                    service: _svc,
                    userId: widget.userId,
                    rol: rol,
                  ),
                // Tab: Hallazgos — oculto temporalmente (kMostrarTabHallazgos)
                if (kMostrarTabHallazgos)
                  StreamBuilder<List<InterventoriaVisita>>(
                    stream: _svc.streamVisitas(
                      widget.empresaId,
                      centroId: centroEfectivo,
                    ),
                    builder: (context, visitasSnap) {
                      return StreamBuilder<List<InterventoriaHallazgo>>(
                        stream: _svc.streamHallazgos(
                          widget.empresaId,
                          centroId:
                              centroEfectivo ??
                              (_centroFiltro.isEmpty ? null : _centroFiltro),
                          estado: _estadoFiltro.isEmpty ? null : _estadoFiltro,
                        ),
                        builder: (context, snap) {
                          final todos = _mergeHallazgosConVisitas(
                            snap.data ?? const [],
                            visitasSnap.data ?? const [],
                          );
                          final filtrados = _aplicarFiltros(todos);
                          return _HallazgosTab(
                            hallazgos: filtrados,
                            todosHallazgos: todos,
                            canWrite: canWrite,
                            centroFiltro: _centroFiltro,
                            estadoFiltro: _estadoFiltro,
                            dptoFiltro: _dptoFiltro,
                            fechaDesde: _fechaDesde,
                            fechaHasta: _fechaHasta,
                            ocultarFiltroCentro: esRegistrador,
                            onCentroChanged: esRegistrador
                                ? null
                                : (v) => setState(() => _centroFiltro = v),
                            onEstadoChanged: (v) =>
                                setState(() => _estadoFiltro = v),
                            onDptoChanged: (v) =>
                                setState(() => _dptoFiltro = v),
                            onFechaDesdeChanged: (v) =>
                                setState(() => _fechaDesde = v),
                            onFechaHastaChanged: (v) =>
                                setState(() => _fechaHasta = v),
                            onRegistrar: () => _abrirRegistrarActa(context),
                            service: _svc,
                            userId: widget.userId,
                            empresaId: widget.empresaId,
                            rol: rol,
                          );
                        },
                      );
                    },
                  ),
                // Tab: Subsanaciones (antes "Seguimiento")
                StreamBuilder<List<InterventoriaVisita>>(
                  stream: _svc.streamVisitas(
                    widget.empresaId,
                    centroId: centroEfectivo,
                  ),
                  builder: (context, visitasSnap) {
                    return StreamBuilder<List<InterventoriaHallazgo>>(
                      stream: _svc.streamHallazgos(
                        widget.empresaId,
                        centroId: centroEfectivo,
                      ),
                      builder: (context, snap) {
                        final combinados = _mergeHallazgosConVisitas(
                          snap.data ?? const [],
                          visitasSnap.data ?? const [],
                        );
                        final filtrados = _aplicarFiltros(combinados);
                        return _SeguimientoMatriz(
                          hallazgos: filtrados,
                          visitas: visitasSnap.data ?? const [],
                          // Las opciones salen de `combinados`, la lista sin
                          // filtrar, para que elegir a alguien no vacie el
                          // desplegable.
                          asignados: {
                            for (final h in combinados)
                              if (h.responsableId.trim().isNotEmpty)
                                h.responsableId: h.responsableNombre,
                          },
                          asignadoFiltro: _asignadoFiltro,
                          onAsignadoChanged: (v) =>
                              setState(() => _asignadoFiltro = v),
                          centroFiltro: _centroFiltro,
                          fechaDesde: _fechaDesde,
                          fechaHasta: _fechaHasta,
                          ocultarFiltroCentro: esRegistrador,
                          onCentroChanged: esRegistrador
                              ? null
                              : (v) => setState(() => _centroFiltro = v),
                          onFechaDesdeChanged: (v) =>
                              setState(() => _fechaDesde = v),
                          onFechaHastaChanged: (v) =>
                              setState(() => _fechaHasta = v),
                          hayFiltros:
                              _centroFiltro.isNotEmpty ||
                              _estadoFiltro.isNotEmpty ||
                              _dptoFiltro.isNotEmpty ||
                              _asignadoFiltro.isNotEmpty ||
                              _fechaDesde != null ||
                              _fechaHasta != null,
                          onLimpiarFiltros: () => setState(() {
                            _centroFiltro = '';
                            _estadoFiltro = '';
                            _dptoFiltro = '';
                            _asignadoFiltro = '';
                            _fechaDesde = null;
                            _fechaHasta = null;
                          }),
                          service: _svc,
                          userId: widget.userId,
                          empresaId: widget.empresaId,
                          rol: rol,
                          // El registrador solo documenta hallazgos; asignar
                          // responsables es de los demás roles.
                          canWrite:
                              canWrite && rol != kRolInterventoriaRegistrador,
                        );
                      },
                    );
                  },
                ),
                // Tab: Maestro — biblioteca de los 141 numerales y su regla
                // de asignación. Solo la consulta el administrador del módulo.
                if (esAdminDesarrollo)
                  InterventoriaMaestroSubsanaciones(
                    service: _svc,
                    empresaId: widget.empresaId,
                    userId: widget.userId,
                    canEdit: esAdminDesarrollo,
                  ),
                if (canApproveDeletion)
                  _SolicitudesEliminacionTab(
                    empresaId: widget.empresaId,
                    userId: widget.userId,
                    service: _svc,
                  ),
                // Último tab: Análisis (solo directivos) — índice coincide con tabs list
                if (canDirectivo)
                  _AnalisisDirectivo(
                    empresaId: widget.empresaId,
                    service: _svc,
                    centroFiltro: _centroFiltro,
                    fechaDesde: _fechaDesde,
                    fechaHasta: _fechaHasta,
                    onCentroChanged: (v) => setState(() => _centroFiltro = v),
                    onFechaDesdeChanged: (v) => setState(() => _fechaDesde = v),
                    onFechaHastaChanged: (v) => setState(() => _fechaHasta = v),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<InterventoriaHallazgo> _aplicarFiltros(
    List<InterventoriaHallazgo> lista,
  ) {
    var r = lista;
    if (_centroFiltro.isNotEmpty) {
      r = r.where((h) => h.centroCostoId == _centroFiltro).toList();
    }
    if (_estadoFiltro.isNotEmpty) {
      r = r.where((h) => h.estado == _estadoFiltro).toList();
    }
    if (_dptoFiltro.isNotEmpty) {
      r = r.where((h) => h.dptoEncargado == _dptoFiltro).toList();
    }
    if (_asignadoFiltro.isNotEmpty) {
      r = _asignadoFiltro == _kSinAsignar
          ? r.where((h) => h.responsableId.trim().isEmpty).toList()
          : r.where((h) => h.responsableId == _asignadoFiltro).toList();
    }
    if (_fechaDesde != null) {
      final desde = DateTime(
        _fechaDesde!.year,
        _fechaDesde!.month,
        _fechaDesde!.day,
      );
      r = r.where((h) => !h.fechaHallazgo.toDate().isBefore(desde)).toList();
    }
    if (_fechaHasta != null) {
      final hasta = DateTime(
        _fechaHasta!.year,
        _fechaHasta!.month,
        _fechaHasta!.day,
        23,
        59,
        59,
      );
      r = r.where((h) => !h.fechaHallazgo.toDate().isAfter(hasta)).toList();
    }
    return r;
  }

  List<InterventoriaHallazgo> _mergeHallazgosConVisitas(
    List<InterventoriaHallazgo> hallazgos,
    List<InterventoriaVisita> visitas,
  ) {
    final visitasConHallazgos = hallazgos
        .map((h) => h.visitaId)
        .where((id) => id.isNotEmpty)
        .toSet();
    final derivados = <InterventoriaHallazgo>[];
    for (final visita in visitas) {
      if (visitasConHallazgos.contains(visita.id)) continue;
      derivados.addAll(_hallazgosDesdeVisita(visita));
    }
    final all = [...hallazgos, ...derivados];
    all.sort((a, b) {
      final byFecha = b.fechaHallazgo.compareTo(a.fechaHallazgo);
      return byFecha != 0
          ? byFecha
          : a.numeroHallazgo.compareTo(b.numeroHallazgo);
    });
    return all;
  }

  List<InterventoriaHallazgo> _hallazgosDesdeVisita(
    InterventoriaVisita visita,
  ) {
    final hallazgos = <InterventoriaHallazgo>[];
    for (
      var categoryIndex = 0;
      categoryIndex < kInterventoriaCategorias.length;
      categoryIndex++
    ) {
      final cat = kInterventoriaCategorias[categoryIndex];
      final item = visita.items[cat.key];
      if (item == null) continue;
      final notes = item.observaciones
          .where(
            (note) =>
                note.texto.trim().isNotEmpty || note.aspecto.trim().isNotEmpty,
          )
          .toList();
      for (var noteIndex = 0; noteIndex < notes.length; noteIndex++) {
        final note = notes[noteIndex];
        hallazgos.add(
          InterventoriaHallazgo(
            empresaId: visita.empresaId,
            visitaId: visita.id,
            centroCostoId: visita.centroCostoId,
            centroCostoNombre: visita.centroCostoNombre,
            tipoActa: visita.tipoActa,
            numeroHallazgo: '${categoryIndex + 1}.${noteIndex + 1}',
            // Aquí sí se conoce la categoría y el aspecto, así que el numeral
            // real del acta se puede reconstruir sin ambigüedad. Sin esto, los
            // hallazgos derivados de un acta llegan al tablero como
            // "no se pudo identificar el numeral".
            numeralActa: numeralActaDesdeAspecto(cat.key, note.aspecto),
            descripcion: note.aspecto.trim().isEmpty ? cat.label : note.aspecto,
            fechaHallazgo: visita.fechaVisita,
            observaciones: note.texto.trim(),
            fuente: note.fuente,
            createdAt: visita.createdAt,
          ),
        );
      }
    }

    final observacionesGenerales =
        visita.ocrDatosDetectados['observacionesGenerales']
            ?.toString()
            .trim() ??
        '';
    final conclusiones =
        visita.ocrDatosDetectados['conclusiones']?.toString().trim() ?? '';
    if (observacionesGenerales.isNotEmpty) {
      hallazgos.add(
        InterventoriaHallazgo(
          empresaId: visita.empresaId,
          visitaId: visita.id,
          centroCostoId: visita.centroCostoId,
          centroCostoNombre: visita.centroCostoNombre,
          tipoActa: visita.tipoActa,
          numeroHallazgo: '90.1',
          descripcion: 'Observaciones generales',
          fechaHallazgo: visita.fechaVisita,
          observaciones: observacionesGenerales,
          fuente: 'manual',
          createdAt: visita.createdAt,
        ),
      );
    }
    if (conclusiones.isNotEmpty) {
      hallazgos.add(
        InterventoriaHallazgo(
          empresaId: visita.empresaId,
          visitaId: visita.id,
          centroCostoId: visita.centroCostoId,
          centroCostoNombre: visita.centroCostoNombre,
          tipoActa: visita.tipoActa,
          numeroHallazgo: '90.2',
          descripcion: 'Conclusiones',
          fechaHallazgo: visita.fechaVisita,
          observaciones: conclusiones,
          fuente: 'manual',
          createdAt: visita.createdAt,
        ),
      );
    }
    return hallazgos;
  }

  Future<void> _abrirRegistrarActa(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => _RegistrarActaSheet(
        empresaId: widget.empresaId,
        userId: widget.userId,
        service: _svc,
        centroFijoId: _centroFijoId.isNotEmpty ? _centroFijoId : null,
      ),
    );
  }
}

class _SolicitudesEliminacionTab extends StatelessWidget {
  final String empresaId;
  final String userId;
  final InterventoriaService service;

  const _SolicitudesEliminacionTab({
    required this.empresaId,
    required this.userId,
    required this.service,
  });

  Future<String?> _commentDialog(
    BuildContext context, {
    required bool approve,
  }) async {
    final controller = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(approve ? 'Aprobar eliminación' : 'Rechazar eliminación'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 5,
          decoration: InputDecoration(
            labelText: approve ? 'Comentario (opcional)' : 'Motivo del rechazo',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: approve ? _kDanger : const Color(0xFF475569),
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(approve ? 'Aprobar y eliminar' : 'Rechazar'),
          ),
        ],
      ),
    );
    final comment = controller.text.trim();
    controller.dispose();
    if (accepted != true) return null;
    if (!approve && comment.length < 5) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Explica brevemente el rechazo.')),
        );
      }
      return null;
    }
    return comment;
  }

  Future<void> _resolve(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> request, {
    required bool approve,
  }) async {
    final comment = await _commentDialog(context, approve: approve);
    if (comment == null) return;
    try {
      await service.resolverSolicitudEliminacion(
        empresaId: empresaId,
        solicitudId: request.id,
        aprobar: approve,
        comentario: comment,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              approve
                  ? 'Eliminación aprobada y ejecutada.'
                  : 'Solicitud rechazada.',
            ),
          ),
        );
      }
    } on FirebaseFunctionsException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message ?? 'No se pudo resolver.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
      stream: service.streamSolicitudesEliminacion(empresaId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text('No se pudieron cargar: ${snapshot.error}'),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final requests = snapshot.data!;
        if (requests.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.verified_outlined, size: 46, color: _kOk),
                SizedBox(height: 10),
                Text('No hay solicitudes de eliminación pendientes.'),
              ],
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: requests.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final request = requests[index];
            final data = request.data();
            final requesterId = (data['solicitadoPorId'] ?? '').toString();
            final ownRequest = requesterId == userId;
            final createdAt = data['createdAt'] as Timestamp?;
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.delete_sweep_outlined,
                          color: _kDanger,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            (data['entidadNombre'] ?? data['tipo'] ?? '')
                                .toString(),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        if (createdAt != null)
                          Text(
                            DateFormat(
                              'dd/MM/yyyy HH:mm',
                            ).format(createdAt.toDate()),
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF64748B),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Solicita: ${data['solicitadoPorNombre'] ?? requesterId}',
                    ),
                    const SizedBox(height: 4),
                    Text('Motivo: ${data['motivo'] ?? ''}'),
                    const SizedBox(height: 12),
                    if (ownRequest)
                      const Text(
                        'Otra persona autorizada debe resolver esta solicitud.',
                        style: TextStyle(color: Color(0xFFB45309)),
                      )
                    else
                      Wrap(
                        spacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () =>
                                _resolve(context, request, approve: false),
                            icon: const Icon(Icons.close),
                            label: const Text('Rechazar'),
                          ),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: _kDanger,
                            ),
                            onPressed: () =>
                                _resolve(context, request, approve: true),
                            icon: const Icon(Icons.delete_forever),
                            label: const Text('Aprobar eliminación'),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab Hallazgos
// ─────────────────────────────────────────────────────────────────────────────

class _HallazgosTab extends StatelessWidget {
  final List<InterventoriaHallazgo> hallazgos;
  final List<InterventoriaHallazgo> todosHallazgos;
  final bool canWrite;
  final String centroFiltro;
  final String estadoFiltro;
  final String dptoFiltro;
  final DateTime? fechaDesde;
  final DateTime? fechaHasta;

  /// Cuando true (rol Registrador) oculta el selector de establecimiento.
  final bool ocultarFiltroCentro;
  final ValueChanged<String>? onCentroChanged;
  final ValueChanged<String> onEstadoChanged;
  final ValueChanged<String> onDptoChanged;
  final ValueChanged<DateTime?> onFechaDesdeChanged;
  final ValueChanged<DateTime?> onFechaHastaChanged;
  final VoidCallback onRegistrar;
  final InterventoriaService service;
  final String userId;
  final String empresaId;
  final String rol;

  const _HallazgosTab({
    required this.hallazgos,
    required this.todosHallazgos,
    required this.canWrite,
    required this.centroFiltro,
    required this.estadoFiltro,
    required this.dptoFiltro,
    this.fechaDesde,
    this.fechaHasta,
    this.ocultarFiltroCentro = false,
    this.onCentroChanged,
    required this.onEstadoChanged,
    required this.onDptoChanged,
    required this.onFechaDesdeChanged,
    required this.onFechaHastaChanged,
    required this.onRegistrar,
    required this.service,
    required this.userId,
    required this.empresaId,
    this.rol = '',
  });

  @override
  Widget build(BuildContext context) {
    final isWeb = MediaQuery.of(context).size.width >= 900;
    final centros = {
      for (final h in todosHallazgos) h.centroCostoId: h.centroCostoNombre,
    };
    final total = hallazgos.length;
    final activos = hallazgos.where((h) => !h.isSubsanado).length;
    final subsanados = hallazgos.where((h) => h.isSubsanado).length;
    final score = calcularScoreHallazgos(hallazgos);

    return InternalModuleViewport(
      padding: EdgeInsets.all(isWeb ? 24 : 14),
      maxWidth: 1400,
      child: Column(
        children: [
          // Resumen — 4 tarjetas: fila única en web, 2×2 en móvil
          if (isWeb)
            Row(
              children: [
                Expanded(
                  child: _MetricCard(
                    label: 'Total',
                    value: '$total',
                    color: const Color(0xFF475569),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MetricCard(
                    label: 'Activos',
                    value: '$activos',
                    color: _kDanger,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MetricCard(
                    label: 'Subsanados',
                    value: '$subsanados',
                    color: _kOk,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MetricCard(
                    label: 'Score subsanación',
                    value: '${score.toStringAsFixed(1)}%',
                    color: _percentColor(score),
                  ),
                ),
              ],
            )
          else
            Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _MetricCard(
                        label: 'Total hallazgos',
                        value: '$total',
                        color: const Color(0xFF475569),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _MetricCard(
                        label: 'Activos',
                        value: '$activos',
                        color: _kDanger,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _MetricCard(
                        label: 'Subsanados',
                        value: '$subsanados',
                        color: _kOk,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _MetricCard(
                        label: 'Score',
                        value: '${score.toStringAsFixed(1)}%',
                        color: _percentColor(score),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          const SizedBox(height: 14),
          // Filtros
          _FiltrosHallazgos(
            centros: centros,
            service: service,
            empresaId: empresaId,
            dptos: {
              for (final h in todosHallazgos)
                if (h.dptoEncargado.isNotEmpty)
                  h.dptoEncargado: h.dptoEncargado,
            },
            centroFiltro: centroFiltro,
            estadoFiltro: estadoFiltro,
            dptoFiltro: dptoFiltro,
            fechaDesde: fechaDesde,
            fechaHasta: fechaHasta,
            ocultarFiltroCentro: ocultarFiltroCentro,
            onCentroChanged: onCentroChanged,
            onEstadoChanged: onEstadoChanged,
            onDptoChanged: onDptoChanged,
            onFechaDesdeChanged: onFechaDesdeChanged,
            onFechaHastaChanged: onFechaHastaChanged,
          ),
          const SizedBox(height: 14),
          // Lista
          Expanded(
            child: hallazgos.isEmpty
                ? _EmptyHallazgos(canWrite: canWrite, onTap: onRegistrar)
                : isWeb
                ? _HallazgosTable(
                    hallazgos: hallazgos,
                    canWrite: canWrite,
                    service: service,
                    userId: userId,
                    empresaId: empresaId,
                    rol: rol,
                  )
                : ListView.separated(
                    itemCount: hallazgos.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (ctx, i) => _HallazgoCard(
                      hallazgo: hallazgos[i],
                      canWrite: canWrite,
                      service: service,
                      userId: userId,
                      empresaId: empresaId,
                      rol: rol,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tabla de hallazgos (web)
// ─────────────────────────────────────────────────────────────────────────────

class _HallazgosTable extends StatefulWidget {
  final List<InterventoriaHallazgo> hallazgos;
  final bool canWrite;
  final InterventoriaService service;
  final String userId;
  final String empresaId;
  final String rol;

  const _HallazgosTable({
    required this.hallazgos,
    required this.canWrite,
    required this.service,
    required this.userId,
    required this.empresaId,
    this.rol = '',
  });

  @override
  State<_HallazgosTable> createState() => _HallazgosTableState();
}

class _HallazgosTableState extends State<_HallazgosTable> {
  List<Area> _areas = [];
  bool _areasLoaded = false;
  // Track which row is saving (by hallazgo id)
  final Set<String> _saving = {};

  /// Página visible de la tabla (20 filas por página).
  int _pagina = 0;

  @override
  void initState() {
    super.initState();
    _loadAreas();
  }

  @override
  void didUpdateWidget(_HallazgosTable old) {
    super.didUpdateWidget(old);
    if (old.empresaId != widget.empresaId) _loadAreas();
  }

  Future<void> _loadAreas() async {
    final areas = await widget.service.getAreas(widget.empresaId);
    if (mounted) {
      setState(() {
        _areas = areas;
        _areasLoaded = true;
      });
    }
  }

  Future<void> _asignarArea(InterventoriaHallazgo h, Area area) async {
    if (_saving.contains(h.id)) return;
    setState(() => _saving.add(h.id));
    try {
      final updated = h.copyWith(dptoEncargado: area.nombre, areaId: area.id);
      await widget.service.guardarHallazgo(updated);
      await widget.service.crearTareaYNotificarHallazgo(
        hallazgo: updated,
        creadorId: widget.userId,
        creadorNombre: widget.userId,
        // Elección explícita del usuario: manda sobre la matriz del acta.
        preferirAreaManual: true,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Área "${area.nombre}" asignada · tarea creada con fecha límite',
            ),
            backgroundColor: Colors.teal,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving.remove(h.id));
    }
  }

  Widget _dptoCell(InterventoriaHallazgo h) {
    // Registrador: solo lectura, no puede asignar departamento
    final puedeAsignar =
        widget.canWrite && widget.rol != kRolInterventoriaRegistrador;
    if (!puedeAsignar) {
      return Text(
        h.dptoEncargado.isEmpty ? '—' : h.dptoEncargado,
        style: const TextStyle(fontSize: 12),
      );
    }
    if (_saving.contains(h.id)) {
      return const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    final hasArea = h.dptoEncargado.isNotEmpty;
    // Find current area id to set as selected value
    String? currentValue = h.areaId.isNotEmpty ? h.areaId : null;

    if (!_areasLoaded) {
      return Text(
        hasArea ? h.dptoEncargado : '—',
        style: const TextStyle(fontSize: 12),
      );
    }

    return DropdownButton<String>(
      value: (_areas.any((a) => a.id == currentValue)) ? currentValue : null,
      hint: Text(
        hasArea ? h.dptoEncargado : '— Asignar —',
        style: TextStyle(
          fontSize: 12,
          color: hasArea ? Colors.black87 : const Color(0xFFB45309),
          fontWeight: hasArea ? FontWeight.normal : FontWeight.w600,
        ),
      ),
      underline: Container(
        height: 1,
        color: hasArea ? const Color(0xFF94A3B8) : const Color(0xFFB45309),
      ),
      isDense: true,
      icon: Icon(
        Icons.arrow_drop_down,
        size: 18,
        color: hasArea ? const Color(0xFF64748B) : const Color(0xFFB45309),
      ),
      items: _areas
          .map(
            (a) => DropdownMenuItem(
              value: a.id,
              child: Text(a.nombre, style: const TextStyle(fontSize: 12)),
            ),
          )
          .toList(),
      onChanged: (val) {
        if (val == null) return;
        final area = _areas.firstWhere((a) => a.id == val);
        _asignarArea(h, area);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Tabla larga: de a 20 filas con paginador debajo.
    final maxPagina = pageCountOf(widget.hallazgos.length) - 1;
    final pagina = _pagina.clamp(0, maxPagina < 0 ? 0 : maxPagina);
    final visibles = pageOf(widget.hallazgos, pagina);

    return Card(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DataTable(
              headingRowColor: WidgetStateProperty.all(const Color(0xFFF1F5F9)),
              columns: const [
                DataColumn(label: Text('N°')),
                DataColumn(label: Text('Establecimiento')),
                DataColumn(label: Text('Hallazgo')),
                DataColumn(label: Text('Fecha del acta')),
                DataColumn(label: Text('Responsable')),
                DataColumn(label: Text('Fecha límite')),
                DataColumn(label: Text('Dpto')),
                DataColumn(label: Text('Estado')),
                DataColumn(label: Text('')),
              ],
              rows: visibles.map((h) {
                return DataRow(
                  cells: [
                    DataCell(
                      Text(
                        h.numeroHallazgo,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    DataCell(Text(h.centroCostoNombre)),
                    DataCell(
                      SizedBox(
                        width: 320,
                        child: Text(
                          h.descripcion,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    DataCell(
                      Text(
                        DateFormat('dd/MM/yy').format(h.fechaHallazgo.toDate()),
                      ),
                    ),
                    DataCell(_ResponsableHallazgoCell(hallazgo: h)),
                    DataCell(_VenceHallazgoCell(hallazgo: h)),
                    DataCell(_dptoCell(h)),
                    DataCell(
                      _EstadoChip(
                        isSubsanado: h.isSubsanado,
                        isPendiente: h.isPendienteAprobacion,
                      ),
                    ),
                    DataCell(
                      widget.canWrite && h.id.isNotEmpty
                          ? _AccionesHallazgo(
                              hallazgo: h,
                              service: widget.service,
                              userId: widget.userId,
                              empresaId: widget.empresaId,
                              rol: widget.rol,
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                );
              }).toList(),
            ),
            if (widget.hallazgos.length > kPageSize)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: PagerBar(
                  total: widget.hallazgos.length,
                  page: pagina,
                  etiqueta: 'hallazgos',
                  onPageChanged: (p) => setState(() => _pagina = p),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tarjeta de hallazgo (móvil)
// ─────────────────────────────────────────────────────────────────────────────

class _HallazgoCard extends StatelessWidget {
  final InterventoriaHallazgo hallazgo;
  final bool canWrite;
  final InterventoriaService service;
  final String userId;
  final String empresaId;
  final String rol;

  const _HallazgoCard({
    required this.hallazgo,
    required this.canWrite,
    required this.service,
    required this.userId,
    required this.empresaId,
    this.rol = '',
  });

  @override
  Widget build(BuildContext context) {
    final h = hallazgo;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: _kAccent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    h.numeroHallazgo,
                    style: TextStyle(
                      color: _kAccent,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    h.centroCostoNombre,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                _EstadoChip(
                  isSubsanado: h.isSubsanado,
                  isPendiente: h.isPendienteAprobacion,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              h.descripcion,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(
                  Icons.calendar_today_rounded,
                  size: 11,
                  color: Color(0xFF94A3B8),
                ),
                const SizedBox(width: 4),
                Text(
                  'Acta ${DateFormat('dd/MM/yyyy').format(h.fechaHallazgo.toDate())}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
                  ),
                ),
                const SizedBox(width: 12),
                // Indicador de área asignada
                if (h.dptoEncargado.isNotEmpty) ...[
                  const Icon(
                    Icons.corporate_fare_rounded,
                    size: 11,
                    color: Color(0xFF0F766E),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      h.dptoEncargado,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF0F766E),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ] else if (canWrite) ...[
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: 11,
                    color: Color(0xFFD97706),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'Sin área asignada',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFFD97706),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
            // Responsable y fecha límite: en móvil van en una línea propia
            // porque los nombres largos no caben junto a la fecha.
            if (h.responsableNombre.isNotEmpty || h.fechaLimite != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  if (h.responsableNombre.isNotEmpty) ...[
                    const Icon(
                      Icons.person_outline,
                      size: 11,
                      color: Color(0xFF64748B),
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        h.cargoResponsable.isEmpty
                            ? h.responsableNombre
                            : '${h.responsableNombre} · ${h.cargoResponsable}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ),
                  ],
                  if (h.fechaLimite != null) ...[
                    const SizedBox(width: 10),
                    const Text(
                      'Límite ',
                      style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                    ),
                    _VenceHallazgoCell(hallazgo: h),
                  ],
                ],
              ),
            ],
            // Estado de la tarea vinculada + adjuntos/evidencias
            if (h.tareaId.isNotEmpty)
              _AdjuntosDeTarea(
                tareaId: h.tareaId,
                hallazgoId: h.id,
                hallazgoEstado: h.estado,
                service: service,
              ),
            if (canWrite && h.id.isNotEmpty) ...[
              const SizedBox(height: 10),
              _AccionesHallazgo(
                hallazgo: h,
                service: service,
                userId: userId,
                empresaId: empresaId,
                rol: rol,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Acciones inline de un hallazgo
// ─────────────────────────────────────────────────────────────────────────────

class _AccionesHallazgo extends StatelessWidget {
  final InterventoriaHallazgo hallazgo;
  final InterventoriaService service;
  final String userId;
  final String empresaId;
  final String rol;

  const _AccionesHallazgo({
    required this.hallazgo,
    required this.service,
    required this.userId,
    required this.empresaId,
    this.rol = '',
  });

  @override
  Widget build(BuildContext context) {
    final h = hallazgo;
    final esRegistrador = rol == kRolInterventoriaRegistrador;
    final puedeAprobar = puedeAprobarHallazgo(h, userId);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Estado pendiente: solo roles superiores ven Aprobar/Rechazar ──
        if (h.isPendienteAprobacion && puedeAprobar) ...[
          IconButton(
            tooltip: 'Aprobar subsanación',
            icon: const Icon(Icons.verified_rounded, color: _kOk),
            onPressed: () => _aprobarSubsanacion(context),
          ),
          IconButton(
            tooltip: 'Rechazar subsanación',
            icon: Icon(Icons.cancel_outlined, color: Colors.red.shade400),
            onPressed: () => _rechazarSubsanacion(context),
          ),
        ] else if (h.isPendienteAprobacion) ...[
          Tooltip(
            message: h.aprobadorNombre.isEmpty
                ? 'Pendiente: la regla no tiene aprobador asignado'
                : 'Pendiente de ${h.aprobadorNombre}',
            child: Icon(
              Icons.hourglass_top_rounded,
              color: Colors.amber.shade700,
              size: 20,
            ),
          ),
        ] else if (h.isSubsanado) ...[
          if (!esRegistrador)
            IconButton(
              tooltip: 'Reabrir hallazgo',
              icon: const Icon(Icons.refresh_rounded, color: _kWarning),
              onPressed: () => service.reabrirHallazgo(
                h.id,
                reabiertoPorId: userId,
                reabiertoPorNombre: userId,
              ),
            ),
        ] else ...[
          // Activo → Registrador propone, otros confirman directamente
          IconButton(
            tooltip: esRegistrador
                ? 'Proponer subsanación'
                : 'Marcar subsanado',
            icon: const Icon(Icons.check_circle_outline, color: _kOk),
            onPressed: () => _confirmarSubsanar(context),
          ),
        ],

        // Editar — siempre visible
        if (!h.isPendienteAprobacion || !esRegistrador)
          IconButton(
            tooltip: esRegistrador ? 'Agregar observación' : 'Editar',
            icon: const Icon(Icons.edit_outlined, color: _kAccent),
            onPressed: () => _abrirEditar(context),
          ),

        // Nadie borra directamente: se crea una solicitud auditada.
        if (!h.isPendienteAprobacion)
          IconButton(
            tooltip: 'Solicitar eliminación',
            icon: Icon(Icons.delete_outline, color: Colors.red.shade400),
            onPressed: () => _confirmarEliminar(context),
          ),
      ],
    );
  }

  Future<void> _aprobarSubsanacion(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Aprobar subsanación'),
        content: Text(
          '¿Confirmar que el hallazgo ${hallazgo.numeroHallazgo} fue correctamente subsanado?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _kOk),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Aprobar'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await service.aprobarSubsanacion(hallazgo.id, actorId: userId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Subsanación aprobada ✓'),
            backgroundColor: _kOk,
          ),
        );
      }
    }
  }

  Future<void> _rechazarSubsanacion(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Rechazar subsanación'),
        content: Text(
          '¿Rechazar la propuesta de subsanación del hallazgo ${hallazgo.numeroHallazgo}? Volverá a estado Activo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _kDanger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Rechazar'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await service.rechazarSubsanacion(hallazgo.id, actorId: userId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Subsanación rechazada — hallazgo ${hallazgo.numeroHallazgo} vuelve a Activo',
            ),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  Future<void> _confirmarSubsanar(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) =>
          _SubsanarSheet(hallazgo: hallazgo, service: service, rol: rol),
    );
  }

  Future<void> _abrirEditar(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _HallazgoForm(
        hallazgo: hallazgo,
        service: service,
        userId: userId,
        empresaId: empresaId,
        rol: rol,
      ),
    );
  }

  Future<void> _confirmarEliminar(BuildContext context) async {
    final reason = await _pedirMotivoEliminacion(
      context,
      entidad: 'El hallazgo ${hallazgo.numeroHallazgo}',
    );
    if (reason == null) return;
    try {
      await service.solicitarEliminacion(
        empresaId: empresaId,
        tipo: 'hallazgo',
        entidadId: hallazgo.id,
        motivo: reason,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Solicitud enviada para aprobación.')),
        );
      }
    } on FirebaseFunctionsException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message ?? 'No se pudo enviar.')),
        );
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sheet: marcar subsanado
// ─────────────────────────────────────────────────────────────────────────────

class _SubsanarSheet extends StatefulWidget {
  final InterventoriaHallazgo hallazgo;
  final InterventoriaService service;
  final String rol;

  const _SubsanarSheet({
    required this.hallazgo,
    required this.service,
    this.rol = '',
  });

  @override
  State<_SubsanarSheet> createState() => _SubsanarSheetState();
}

class _SubsanarSheetState extends State<_SubsanarSheet> {
  DateTime _fecha = DateTime.now();
  final _seguCtrl = TextEditingController();
  bool _saving = false;
  final List<PlatformFile> _adjuntos = [];

  @override
  void dispose() {
    _seguCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAdjuntos() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'zip', 'doc', 'docx'],
    );
    if (result != null && mounted) {
      setState(() => _adjuntos.addAll(result.files));
    }
  }

  void _removeAdjunto(int index) => setState(() => _adjuntos.removeAt(index));

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        builder: (_, ctrl) => ListView(
          controller: ctrl,
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Proponer subsanación ${widget.hallazgo.numeroHallazgo}',
              style: const TextStyle(
                fontFamily: _kFont,
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
            Container(
              margin: const EdgeInsets.only(top: 6, bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade300),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 14,
                    color: Colors.amber.shade800,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      widget.hallazgo.aprobadorNombre.isEmpty
                          ? 'La propuesta quedará pendiente. Antes de aprobar, asigne un aprobador en la biblioteca.'
                          : 'La propuesta quedará pendiente de ${widget.hallazgo.aprobadorNombre}.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.amber.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              leading: const Icon(Icons.event_available_rounded),
              title: const Text('Fecha de subsanación'),
              subtitle: Text(DateFormat('dd/MM/yyyy').format(_fecha)),
              trailing: const Icon(Icons.edit_calendar_rounded),
              onTap: _pickFecha,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _seguCtrl,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Seguimiento / acción correctiva',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            // Adjuntos
            OutlinedButton.icon(
              onPressed: _picking ? null : _pickAdjuntos,
              icon: const Icon(Icons.attach_file_rounded, size: 18),
              label: const Text('Adjuntar evidencia (imagen, PDF, ZIP…)'),
            ),
            if (_adjuntos.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...List.generate(_adjuntos.length, (i) {
                final f = _adjuntos[i];
                final icon = _iconForFile(f.extension ?? '');
                return Card(
                  margin: const EdgeInsets.only(bottom: 4),
                  child: ListTile(
                    dense: true,
                    leading: Icon(icon, size: 18, color: _kAccent),
                    title: Text(
                      f.name,
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      f.size > 0
                          ? '${(f.size / 1024).toStringAsFixed(1)} KB'
                          : '',
                      style: const TextStyle(fontSize: 11),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.close_rounded, size: 16),
                      onPressed: () => _removeAdjunto(i),
                    ),
                  ),
                );
              }),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: _kOk),
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check_circle_rounded),
                label: Text(
                  widget.rol == kRolInterventoriaRegistrador
                      ? 'Enviar para aprobación'
                      : 'Confirmar subsanación',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool get _picking => false;

  IconData _iconForFile(String ext) {
    switch (ext.toLowerCase()) {
      case 'pdf':
        return Icons.picture_as_pdf_rounded;
      case 'jpg':
      case 'jpeg':
      case 'png':
        return Icons.image_rounded;
      case 'zip':
        return Icons.folder_zip_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  Future<void> _pickFecha() async {
    final p = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (p != null) setState(() => _fecha = p);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      // Subir adjuntos si los hay
      final adjuntosGuardados = <InterventoriaAdjunto>[];
      for (final file in _adjuntos) {
        final bytes = file.bytes != null
            ? Uint8List.fromList(file.bytes!)
            : (file.path != null && !kIsWeb
                  ? await File(file.path!).readAsBytes()
                  : null);
        if (bytes == null) continue;
        final adj = await widget.service.subirActaBytes(
          bytes: bytes,
          empresaId: widget.hallazgo.empresaId,
          visitaId: widget.hallazgo.visitaId,
          nombre: file.name,
          contentType: _contentTypeForExt(file.extension ?? ''),
          origen: 'subsanacion',
        );
        adjuntosGuardados.add(adj);
      }

      await widget.service.marcarSubsanado(
        hallazgoId: widget.hallazgo.id,
        fechaSubsanacion: _fecha,
        seguimiento: _seguCtrl.text.trim(),
        adjuntos: adjuntosGuardados,
        aprobarDirecto: false,
      );
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _contentTypeForExt(String ext) {
    switch (ext.toLowerCase()) {
      case 'pdf':
        return 'application/pdf';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'zip':
        return 'application/zip';
      default:
        return 'application/octet-stream';
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sheet: editar hallazgo
// ─────────────────────────────────────────────────────────────────────────────

class _HallazgoForm extends StatefulWidget {
  final InterventoriaHallazgo hallazgo;
  final InterventoriaService service;
  final String userId;
  final String empresaId;
  final String rol;

  const _HallazgoForm({
    required this.hallazgo,
    required this.service,
    required this.userId,
    required this.empresaId,
    this.rol = '',
  });

  @override
  State<_HallazgoForm> createState() => _HallazgoFormState();
}

class _HallazgoFormState extends State<_HallazgoForm> {
  late final TextEditingController _descCtrl;
  late final TextEditingController _obsCtrl;
  late final TextEditingController _planCtrl;
  late final TextEditingController _seguCtrl;
  late final TextEditingController _notaRegistradorCtrl;
  late String _dpto;
  late String _areaId;
  late bool _persiste;
  bool _saving = false;
  List<Area> _areas = [];

  @override
  void initState() {
    super.initState();
    final h = widget.hallazgo;
    _descCtrl = TextEditingController(text: h.descripcion);
    _obsCtrl = TextEditingController(text: h.observaciones);
    _planCtrl = TextEditingController(text: h.planMejora);
    _seguCtrl = TextEditingController(text: h.seguimiento);
    _notaRegistradorCtrl = TextEditingController(text: h.notaRegistrador);
    _dpto = h.dptoEncargado;
    _areaId = h.areaId;
    _persiste = h.persiste;
    _loadAreas();
  }

  Future<void> _loadAreas() async {
    final areas = await widget.service.getAreas(widget.empresaId);
    areas.sort((a, b) => a.nombre.compareTo(b.nombre));
    if (mounted) setState(() => _areas = areas);
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _obsCtrl.dispose();
    _planCtrl.dispose();
    _seguCtrl.dispose();
    _notaRegistradorCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final esRegistrador = widget.rol == kRolInterventoriaRegistrador;
    final h = widget.hallazgo;

    // Badge de puntaje de sección
    Widget? puntajeBadge;
    if (h.puntajeSeccion != null) {
      final p = h.puntajeSeccion!;
      final isNA = p >= 100;
      puntajeBadge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isNA
              ? const Color(0xFFE0F2FE)
              : (p >= 80 ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2)),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isNA
                ? Colors.blue.shade300
                : (p >= 80 ? Colors.green.shade300 : Colors.red.shade300),
          ),
        ),
        child: Text(
          isNA ? 'Puntaje: N/A' : 'Puntaje sección: ${p.toStringAsFixed(0)}%',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isNA
                ? Colors.blue.shade700
                : (p >= 80 ? Colors.green.shade700 : Colors.red.shade700),
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: esRegistrador ? 0.65 : 0.88,
        maxChildSize: 0.96,
        minChildSize: 0.4,
        builder: (_, ctrl) => Material(
          color: const Color(0xFFF8FAFC),
          child: ListView(
            controller: ctrl,
            padding: const EdgeInsets.all(18),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hallazgo ${h.numeroHallazgo}',
                          style: const TextStyle(
                            fontFamily: _kFont,
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                          ),
                        ),
                        if (esRegistrador)
                          const Text(
                            'Solo puedes agregar observaciones',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF64748B),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (puntajeBadge != null) puntajeBadge,
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // ── Descripción ─────────────────────────────────────────────
              if (esRegistrador) ...[
                // ── Bloque 1: Observación del acta (solo lectura) ────────
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.assignment_rounded,
                            size: 13,
                            color: Color(0xFF64748B),
                          ),
                          const SizedBox(width: 5),
                          const Text(
                            'Observación registrada en acta',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        h.descripcion,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (h.observaciones.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          h.observaciones,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF475569),
                          ),
                        ),
                      ],
                      if (h.dptoEncargado.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(
                              Icons.domain_rounded,
                              size: 13,
                              color: _kAccent,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              h.dptoEncargado,
                              style: const TextStyle(
                                fontSize: 12,
                                color: _kAccent,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // ── Bloque 2: Nota del registrador (editable) ───────────
                const Row(
                  children: [
                    Icon(
                      Icons.rate_review_rounded,
                      size: 14,
                      color: Color(0xFF0F766E),
                    ),
                    SizedBox(width: 5),
                    Text(
                      'Tu nota — ¿por qué ocurrió? / contexto',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F766E),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _notaRegistradorCtrl,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    hintText:
                        'Describe la causa, el contexto o lo que ocurrió…',
                    border: OutlineInputBorder(),
                  ),
                ),
              ] else ...[
                // Formulario completo para roles con más permisos
                TextField(
                  controller: _descCtrl,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'Descripción del hallazgo',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                // Departamento — solo si puede asignar (no Registrador)
                if (_areas.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 10),
                        Text(
                          'Cargando áreas…',
                          style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  DropdownButtonFormField<String>(
                    key: ValueKey(_areaId),
                    initialValue: _areaId.isEmpty ? null : _areaId,
                    decoration: const InputDecoration(
                      labelText: 'Departamento encargado',
                      border: OutlineInputBorder(),
                    ),
                    items: _areas
                        .map(
                          (a) => DropdownMenuItem(
                            value: a.id,
                            child: Text(a.nombre),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      final area = _areas.firstWhere(
                        (a) => a.id == v,
                        orElse: () => Area(id: v, nombre: v),
                      );
                      setState(() {
                        _areaId = v;
                        _dpto = area.nombre;
                      });
                    },
                  ),
                const SizedBox(height: 12),
                SwitchListTile(
                  tileColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  value: _persiste,
                  title: const Text('Persiste en siguiente visita'),
                  onChanged: (v) => setState(() => _persiste = v),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _obsCtrl,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Observaciones',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _planCtrl,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Plan de mejora',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _seguCtrl,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Seguimiento',
                    border: OutlineInputBorder(),
                  ),
                ),
                // ── Nota del registrador (solo lectura para roles superiores) ──
                if (h.notaRegistrador.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF86EFAC)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.rate_review_rounded,
                              size: 13,
                              color: Color(0xFF0F766E),
                            ),
                            SizedBox(width: 5),
                            Text(
                              'Nota del registrador — contexto / causa',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0F766E),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          h.notaRegistrador,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF065F46),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],

              // Evidencias subidas en la tarea + estado — visible para todos
              if (widget.hallazgo.tareaId.isNotEmpty) ...[
                const SizedBox(height: 14),
                _AdjuntosDeTarea(
                  tareaId: widget.hallazgo.tareaId,
                  hallazgoId: widget.hallazgo.id,
                  hallazgoEstado: widget.hallazgo.estado,
                  service: widget.service,
                ),
              ],

              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_rounded),
                label: Text(
                  esRegistrador ? 'Guardar observación' : 'Guardar cambios',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final esRegistrador = widget.rol == kRolInterventoriaRegistrador;
    try {
      final areaChanged =
          !esRegistrador &&
          _areaId.isNotEmpty &&
          _areaId != widget.hallazgo.areaId;

      final updated = esRegistrador
          // Registrador: solo actualiza su nota explicativa (no toca el texto del acta)
          ? widget.hallazgo.copyWith(
              notaRegistrador: _notaRegistradorCtrl.text.trim(),
            )
          // Otros roles: actualización completa
          : widget.hallazgo.copyWith(
              descripcion: _descCtrl.text.trim(),
              dptoEncargado: _dpto,
              areaId: _areaId,
              persiste: _persiste,
              observaciones: _obsCtrl.text.trim(),
              planMejora: _planCtrl.text.trim(),
              seguimiento: _seguCtrl.text.trim(),
            );
      await widget.service.guardarHallazgo(
        updated,
        notificarNota:
            esRegistrador && _notaRegistradorCtrl.text.trim().isNotEmpty,
        guardadoPorId: widget.userId,
        guardadoPorNombre: widget.userId,
      );

      // Si se asignó (o cambió) el área, crear tarea y notificar al director
      if (areaChanged && mounted) {
        final taskId = await widget.service.crearTareaYNotificarHallazgo(
          hallazgo: updated,
          creadorId: widget.userId,
          creadorNombre: widget.userId,
          // Elección explícita del usuario: manda sobre la matriz del acta.
          preferirAreaManual: true,
        );
        if (mounted && taskId != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: _kOk,
              content: const Text(
                'Tarea creada con fecha límite y responsable notificado ✓',
              ),
            ),
          );
        }
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al guardar: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab Seguimiento — matriz estilo Excel
// ─────────────────────────────────────────────────────────────────────────────

/// Desplegable de persona asignada para Subsanaciones.
///
/// Ademas de las personas ofrece "Sin asignar", que es la opcion que de
/// verdad se usa: un hallazgo sin responsable no le figura a nadie y solo se
/// descubre revisando la lista completa.
class _AsignadoFilterDropdown extends StatelessWidget {
  final Map<String, String> asignados;
  final String value;
  final ValueChanged<String> onChanged;

  const _AsignadoFilterDropdown({
    required this.asignados,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final ordenados = asignados.entries.toList()
      ..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));
    // Una persona que ya no figura en la lista visible no puede desaparecer del
    // selector estando seleccionada: dejaria el filtro activo sin manera de
    // quitarlo salvo "Limpiar".
    final valorValido =
        value.isEmpty || value == _kSinAsignar || asignados.containsKey(value);

    return DropdownButtonFormField<String>(
      initialValue: valorValido ? value : '',
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Asignado a',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      items: [
        const DropdownMenuItem(value: '', child: Text('Todos')),
        const DropdownMenuItem(value: _kSinAsignar, child: Text('Sin asignar')),
        for (final e in ordenados)
          DropdownMenuItem(
            value: e.key,
            child: Text(e.value, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (v) => onChanged(v ?? ''),
    );
  }
}

/// Valor reservado del filtro de asignado: los hallazgos sin responsable.
/// No puede colisionar con un id real de usuario, que es siempre una cedula.
const String _kSinAsignar = '__sin_asignar__';

class _SeguimientoMatriz extends StatefulWidget {
  final List<InterventoriaHallazgo> hallazgos;
  final List<InterventoriaVisita> visitas;
  final String centroFiltro;
  final DateTime? fechaDesde;
  final DateTime? fechaHasta;
  final bool ocultarFiltroCentro;
  final ValueChanged<String>? onCentroChanged;
  final ValueChanged<DateTime?> onFechaDesdeChanged;
  final ValueChanged<DateTime?> onFechaHastaChanged;

  /// Personas que aparecen como responsables. Se calcula sobre la lista SIN
  /// filtrar: si saliera de la lista ya filtrada, elegir a alguien vaciaria el
  /// desplegable y no habria forma de volver.
  final Map<String, String> asignados;
  final String asignadoFiltro;
  final ValueChanged<String> onAsignadoChanged;
  final bool hayFiltros;
  final VoidCallback onLimpiarFiltros;
  final InterventoriaService service;
  final String userId;
  final String empresaId;
  final String rol;
  final bool canWrite;

  const _SeguimientoMatriz({
    required this.hallazgos,
    required this.visitas,
    required this.centroFiltro,
    this.fechaDesde,
    this.fechaHasta,
    this.ocultarFiltroCentro = false,
    this.onCentroChanged,
    required this.onFechaDesdeChanged,
    required this.onFechaHastaChanged,
    this.asignados = const {},
    this.asignadoFiltro = '',
    required this.onAsignadoChanged,
    required this.hayFiltros,
    required this.onLimpiarFiltros,
    required this.service,
    this.userId = '',
    this.empresaId = '',
    this.rol = '',
    this.canWrite = false,
  });

  @override
  State<_SeguimientoMatriz> createState() => _SeguimientoMatrizState();
}

class _SeguimientoMatrizState extends State<_SeguimientoMatriz> {
  /// El tablero es la vista por defecto: la tabla obliga a desplazarse en
  /// horizontal para lo esencial y no deja asignar. La tabla se conserva para
  /// revisar todas las columnas de una vez.
  bool _tablero = true;

  @override
  Widget build(BuildContext context) {
    final hallazgos = widget.hallazgos;
    final visitas = widget.visitas;
    final centroFiltro = widget.centroFiltro;
    final fechaDesde = widget.fechaDesde;
    final fechaHasta = widget.fechaHasta;
    final ocultarFiltroCentro = widget.ocultarFiltroCentro;
    final onCentroChanged = widget.onCentroChanged;
    final onFechaDesdeChanged = widget.onFechaDesdeChanged;
    final onFechaHastaChanged = widget.onFechaHastaChanged;
    final service = widget.service;
    final fmt = DateFormat('dd/MM/yy');
    final centros = {
      for (final h in hallazgos) h.centroCostoId: h.centroCostoNombre,
    };
    // Orden: fecha DESC, luego establecimiento alfa
    final sorted = hallazgos.toList()
      ..sort((a, b) {
        final byFecha = b.fechaHallazgo.compareTo(a.fechaHallazgo);
        return byFecha != 0
            ? byFecha
            : a.centroCostoNombre.compareTo(b.centroCostoNombre);
      });

    // ── widgets reutilizables ─────────────────────────────────────────────
    final filtrosWrap = Wrap(
      spacing: 12,
      runSpacing: 10,
      children: [
        if (!ocultarFiltroCentro)
          SizedBox(
            width: 220,
            child: _CentroCostoFilterDropdown(
              service: service,
              empresaId: widget.empresaId,
              fallbackCentros: centros,
              value: centroFiltro,
              onChanged: onCentroChanged,
            ),
          ),
        SizedBox(
          width: 230,
          child: _AsignadoFilterDropdown(
            asignados: widget.asignados,
            value: widget.asignadoFiltro,
            onChanged: widget.onAsignadoChanged,
          ),
        ),
        _FechaTile(
          label: 'Desde',
          fecha: fechaDesde,
          onChanged: onFechaDesdeChanged,
        ),
        _FechaTile(
          label: 'Hasta',
          fecha: fechaHasta,
          onChanged: onFechaHastaChanged,
        ),
        if (widget.hayFiltros)
          TextButton.icon(
            onPressed: widget.onLimpiarFiltros,
            icon: const Icon(Icons.clear_rounded, size: 16),
            label: const Text('Limpiar filtros'),
          ),
        SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
              value: true,
              icon: Icon(Icons.dashboard_outlined, size: 16),
              label: Text('Tablero'),
            ),
            ButtonSegment(
              value: false,
              icon: Icon(Icons.table_rows_outlined, size: 16),
              label: Text('Tabla'),
            ),
          ],
          selected: {_tablero},
          onSelectionChanged: (v) => setState(() => _tablero = v.first),
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
        ),
      ],
    );

    InterventoriaTableroAsignacion tablero({required bool dentroDeScroll}) =>
        InterventoriaTableroAsignacion(
          hallazgos: sorted,
          service: service,
          userId: widget.userId,
          empresaId: widget.empresaId,
          canWrite: widget.canWrite,
          dentroDeScroll: dentroDeScroll,
          onAbrirSeguimiento: (h) =>
              _abrirEdicionSeguimiento(context, h, service),
        );

    final emptyEstado = Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_rounded, size: 56, color: Colors.green.shade400),
          const SizedBox(height: 12),
          Text(
            visitas.isNotEmpty
                ? '¡Sin hallazgos! Las visitas registradas\nestán en condiciones óptimas ✓'
                : 'Sin hallazgos para mostrar',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              color: visitas.isNotEmpty
                  ? Colors.green.shade700
                  : const Color(0xFF94A3B8),
              fontWeight: visitas.isNotEmpty
                  ? FontWeight.w600
                  : FontWeight.normal,
            ),
          ),
          if (visitas.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '${visitas.length} visita${visitas.length > 1 ? 's' : ''} sin hallazgos registrados',
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
          ],
        ],
      ),
    );

    final dataTableCard = Card(
      child: BarraHorizontal(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SingleChildScrollView(
            child: PagedDataTable(
              etiqueta: 'hallazgos',
              tabla: DataTable(
                headingRowColor: WidgetStateProperty.all(
                  const Color(0xFFF1F5F9),
                ),
                columns: const [
                  DataColumn(label: Text('Departamento')),
                  DataColumn(label: Text('Responsable')),
                  DataColumn(label: Text('Fecha límite')),
                  DataColumn(label: Text('Establecimiento')),
                  DataColumn(label: Text('Estado')),
                  DataColumn(label: Text('Tipo acta')),
                  DataColumn(label: Text('N° Hallazgo')),
                  DataColumn(label: Text('Hallazgo')),
                  DataColumn(label: Text('Fecha del acta')),
                  DataColumn(label: Text('Observaciones')),
                  DataColumn(label: Text('Seguimiento')),
                  DataColumn(label: Text('F. Subsanación')),
                  DataColumn(label: Text('Tarea vinculada')),
                ],
                rows: sorted.map((h) {
                  return DataRow(
                    color: WidgetStateProperty.resolveWith(
                      (_) => h.isSubsanado
                          ? _kOk.withValues(alpha: 0.08)
                          : _kDanger.withValues(alpha: 0.04),
                    ),
                    // Tap en la fila → abrir panel de edición de seguimiento
                    onSelectChanged: h.id.isEmpty
                        ? null
                        : (_) => _abrirEdicionSeguimiento(context, h, service),
                    cells: [
                      DataCell(
                        Text(
                          h.dptoEncargado.trim().isEmpty
                              ? '—'
                              : h.dptoEncargado,
                          style: TextStyle(
                            fontWeight: h.dptoEncargado.trim().isEmpty
                                ? FontWeight.normal
                                : FontWeight.w600,
                            color: h.dptoEncargado.trim().isEmpty
                                ? const Color(0xFF94A3B8)
                                : _kAccent,
                          ),
                        ),
                      ),
                      DataCell(_ResponsableHallazgoCell(hallazgo: h)),
                      DataCell(_VenceHallazgoCell(hallazgo: h)),
                      DataCell(Text(h.centroCostoNombre)),
                      DataCell(
                        _EstadoChip(
                          isSubsanado: h.isSubsanado,
                          isPendiente: h.isPendienteAprobacion,
                        ),
                      ),
                      DataCell(Text(h.tipoActa ?? '')),
                      DataCell(
                        Text(
                          h.numeroHallazgo,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 260,
                          child: Text(
                            h.descripcion,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      DataCell(Text(fmt.format(h.fechaHallazgo.toDate()))),
                      // Observaciones: lo que el revisor escribió en el acta
                      DataCell(
                        SizedBox(
                          width: 200,
                          child: Text(
                            h.observaciones.trim().isEmpty
                                ? '—'
                                : h.observaciones,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: h.observaciones.trim().isEmpty
                                  ? Colors.grey.shade400
                                  : null,
                            ),
                          ),
                        ),
                      ),
                      // Seguimiento: notas de seguimiento posteriores
                      DataCell(
                        SizedBox(
                          width: 200,
                          child: Text(
                            h.seguimiento.trim().isEmpty
                                ? 'Toca para agregar…'
                                : h.seguimiento,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: h.seguimiento.trim().isEmpty
                                  ? Colors.grey.shade400
                                  : null,
                              fontStyle: h.seguimiento.trim().isEmpty
                                  ? FontStyle.italic
                                  : null,
                            ),
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          h.fechaSubsanacion != null
                              ? fmt.format(h.fechaSubsanacion!.toDate())
                              : '',
                          style: TextStyle(
                            color: h.fechaSubsanacion == null
                                ? Colors.grey.shade400
                                : null,
                          ),
                        ),
                      ),
                      // Columna: Tarea vinculada
                      DataCell(
                        h.tareaId.isEmpty
                            ? Text(
                                '—',
                                style: TextStyle(color: Colors.grey.shade400),
                              )
                            : _TareaEstadoMini(
                                tareaId: h.tareaId,
                                hallazgoId: h.id,
                                hallazgoEstado: h.estado,
                                service: service,
                              ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ), // DataTable
          ), // inner SingleChildScrollView
        ), // outer SingleChildScrollView (Axis.horizontal)
      ), // Scrollbar
    ); // dataTableCard = Card(...)

    return InternalModuleViewport(
      maxWidth: 1800,
      padding: const EdgeInsets.all(18),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final esMovil = constraints.maxWidth < 900;

          if (esMovil) {
            // Móvil: scroll continuo — gráficas + tabla fluyen juntas
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  filtrosWrap,
                  if (ocultarFiltroCentro && hallazgos.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    _SeguimientoGraficas(
                      hallazgos: hallazgos,
                      visitas: visitas,
                    ),
                  ],
                  const SizedBox(height: 14),
                  if (_tablero)
                    tablero(dentroDeScroll: true)
                  else
                    sorted.isEmpty
                        ? SizedBox(height: 220, child: emptyEstado)
                        : dataTableCard,
                  const SizedBox(height: 16),
                ],
              ),
            );
          }

          // Web / tablet: layout con Expanded para que la tabla llene el espacio
          return Column(
            children: [
              filtrosWrap,
              const SizedBox(height: 14),
              if (ocultarFiltroCentro && hallazgos.isNotEmpty) ...[
                _SeguimientoGraficas(hallazgos: hallazgos, visitas: visitas),
                const SizedBox(height: 16),
              ],
              Expanded(
                child: _tablero
                    ? tablero(dentroDeScroll: false)
                    : sorted.isEmpty
                    ? emptyEstado
                    : dataTableCard,
              ),
            ],
          );
        },
      ),
    );
  }

  /// Abre un panel lateral/diálogo para editar los campos de seguimiento
  /// de un hallazgo: Observaciones, Plan de mejora, F. Subsanación, Seguimiento.
  void _abrirEdicionSeguimiento(
    BuildContext context,
    InterventoriaHallazgo h,
    InterventoriaService svc,
  ) {
    mostrarPanelHallazgo(
      context,
      hallazgo: h,
      service: svc,
      userId: widget.userId,
      empresaId: widget.empresaId,
      canWrite: widget.canWrite,
      rol: widget.rol,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Chip compacto de estado de la tarea para la columna "Tarea vinculada"
// ─────────────────────────────────────────────────────────────────────────────

class _TareaEstadoMini extends StatefulWidget {
  final String tareaId;
  final String hallazgoId;
  final String hallazgoEstado;
  final InterventoriaService service;
  const _TareaEstadoMini({
    required this.tareaId,
    required this.hallazgoId,
    required this.hallazgoEstado,
    required this.service,
  });

  @override
  State<_TareaEstadoMini> createState() => _TareaEstadoMiniState();
}

class _TareaEstadoMiniState extends State<_TareaEstadoMini> {
  String _lastSync = '';

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('TBL_TAREAS')
          .doc(widget.tareaId)
          .snapshots(),
      builder: (ctx, snap) {
        if (!snap.hasData || !snap.data!.exists) {
          return Text(
            'Sin datos',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
          );
        }
        final data = snap.data!.data()!;
        final tareaEstado = (data['estado'] ?? data['status'] ?? '')
            .toString()
            .toLowerCase();
        final solEstado = (data['solicitud_finalizacion_estado'] ?? '')
            .toString();
        final adj = (data['adjuntos'] as List? ?? []).length;

        // Auto-sync estado
        final syncKey = '$tareaEstado|$solEstado';
        if (syncKey != _lastSync) {
          _lastSync = syncKey;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              widget.service.sincronizarEstadoDesdeTask(
                hallazgoId: widget.hallazgoId,
                tareaEstado: tareaEstado,
                solicitudFinalizacionEstado: solEstado,
              );
            }
          });
        }

        // Visual
        String label;
        Color color;
        IconData icon;
        if (tareaEstado == 'finalizado' && solEstado == 'aprobado') {
          label = 'Aprobada';
          color = const Color(0xFF0F766E);
          icon = Icons.verified_rounded;
        } else if (tareaEstado == 'por_aprobar' || solEstado == 'pendiente') {
          label = 'Por aprobar';
          color = const Color(0xFFD97706);
          icon = Icons.hourglass_top_rounded;
        } else if (tareaEstado == 'finalizado') {
          label = 'Finalizada';
          color = const Color(0xFF0F766E);
          icon = Icons.task_alt_rounded;
        } else if (tareaEstado == 'en_progreso') {
          label = 'En progreso';
          color = const Color(0xFF3B82F6);
          icon = Icons.autorenew_rounded;
        } else {
          label = 'Pendiente';
          color = const Color(0xFF94A3B8);
          icon = Icons.schedule_rounded;
        }

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: color.withValues(alpha: 0.35)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 11, color: color),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
            if (adj > 0) ...[
              const SizedBox(width: 4),
              Tooltip(
                message: '$adj adjunto${adj > 1 ? 's' : ''}',
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF64748B).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.attach_file_rounded,
                        size: 10,
                        color: Color(0xFF64748B),
                      ),
                      Text(
                        '$adj',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widget: Panel de gráficas para Registrador en tab Seguimiento
// ─────────────────────────────────────────────────────────────────────────────

class _SeguimientoGraficas extends StatefulWidget {
  final List<InterventoriaHallazgo> hallazgos;
  final List<InterventoriaVisita> visitas;
  const _SeguimientoGraficas({required this.hallazgos, required this.visitas});

  @override
  State<_SeguimientoGraficas> createState() => _SeguimientoGraficasState();
}

class _SeguimientoGraficasState extends State<_SeguimientoGraficas> {
  String _categoriaKey = '';
  // modo: 'puntajes' | 'hallazgos'
  String _modo = 'puntajes';

  static const _cActivo = Color(0xFFEF4444); // rojo
  static const _cPendiente = Color(0xFFF59E0B); // ámbar
  static const _cSubsanado = Color(0xFF22C55E); // verde

  // Construye puntos del timeline a partir de las visitas
  List<_TimelinePoint> _buildTimeline() {
    final sorted = widget.visitas.toList()
      ..sort((a, b) => a.fechaVisita.compareTo(b.fechaVisita));
    return sorted
        .map((v) {
          double value;
          if (_categoriaKey.isEmpty) {
            value = v.porcentajeGeneral;
          } else {
            final item = v.items[_categoriaKey];
            if (item == null || item.noEvaluado || item.valor == null) {
              return null;
            }
            value = item.valor!.clamp(0, 100).toDouble();
          }
          return _TimelinePoint(
            label: DateFormat('dd/MM/yy').format(v.fechaVisita.toDate()),
            value: value,
            caption: v.centroCostoNombre,
          );
        })
        .whereType<_TimelinePoint>()
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final hallazgos = widget.hallazgos;
    final total = hallazgos.length;
    final activos = hallazgos.where((h) => h.estado == 'activo').length;
    final pendientes = hallazgos.where((h) => h.isPendienteAprobacion).length;
    final subsanados = hallazgos.where((h) => h.isSubsanado).length;

    // Puntaje promedio por sección (solo los que tienen puntajeSeccion)
    final conPuntaje = hallazgos
        .where((h) => h.puntajeSeccion != null)
        .toList();
    final puntajePromedio = conPuntaje.isEmpty
        ? null
        : conPuntaje.map((h) => h.puntajeSeccion!).reduce((a, b) => a + b) /
              conPuntaje.length;

    // Agrupar por departamento de asignación
    final Map<String, _GrupoStats> grupos = {};
    for (final h in hallazgos) {
      final dpto = h.dptoEncargado.trim().isEmpty
          ? 'Sin asignar'
          : h.dptoEncargado.trim();
      final g = grupos.putIfAbsent(dpto, () => _GrupoStats(dpto));
      if (h.isSubsanado) {
        g.subsanados++;
      } else if (h.isPendienteAprobacion) {
        g.pendientes++;
      } else {
        g.activos++;
      }
    }
    final gruposSorted = grupos.values.toList()
      ..sort((a, b) {
        // "Sin asignar" siempre al final
        if (a.nombre == 'Sin asignar') return 1;
        if (b.nombre == 'Sin asignar') return -1;
        return a.nombre.compareTo(b.nombre);
      });

    // Timeline
    final timelinePoints = _buildTimeline();
    final categoriaLabel = _categoriaKey.isEmpty
        ? 'Total general'
        : kInterventoriaCategorias
                  .cast<InterventoriaCategoria?>()
                  .firstWhere(
                    (c) => c?.key == _categoriaKey,
                    orElse: () => null,
                  )
                  ?.label ??
              _categoriaKey;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── KPI Cards ────────────────────────────────────────────────────
        Wrap(
          spacing: 12,
          runSpacing: 10,
          children: [
            _KpiCard(
              label: 'Total hallazgos',
              value: '$total',
              icon: Icons.list_alt_rounded,
              color: const Color(0xFF64748B),
            ),
            _KpiCard(
              label: 'Activos',
              value: '$activos',
              icon: Icons.warning_amber_rounded,
              color: _cActivo,
            ),
            _KpiCard(
              label: 'Pend. aprobación',
              value: '$pendientes',
              icon: Icons.hourglass_top_rounded,
              color: _cPendiente,
            ),
            _KpiCard(
              label: 'Subsanados',
              value: '$subsanados',
              icon: Icons.check_circle_rounded,
              color: _cSubsanado,
            ),
            if (puntajePromedio != null)
              _KpiCard(
                label: 'Puntaje promedio',
                value: puntajePromedio >= 100
                    ? 'N/A'
                    : '${puntajePromedio.toStringAsFixed(1)}%',
                icon: Icons.bar_chart_rounded,
                color: puntajePromedio >= 80
                    ? _cSubsanado
                    : puntajePromedio >= 60
                    ? _cPendiente
                    : _cActivo,
              ),
          ],
        ),
        const SizedBox(height: 16),
        // ── Donut + barra de estado ───────────────────────────────────────
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Donut
            SizedBox(
              width: 160,
              height: 160,
              child: total == 0
                  ? const SizedBox()
                  : CustomPaint(
                      painter: _DonutPainter(
                        values: [
                          activos.toDouble(),
                          pendientes.toDouble(),
                          subsanados.toDouble(),
                        ],
                        colors: [_cActivo, _cPendiente, _cSubsanado],
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '$total',
                              style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF1E293B),
                              ),
                            ),
                            const Text(
                              'total',
                              style: TextStyle(
                                fontSize: 11,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: 20),
            // Leyenda + barra de estado
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Estado de hallazgos',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF334155),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _BarraEstado(
                    activos: activos,
                    pendientes: pendientes,
                    subsanados: subsanados,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 16,
                    runSpacing: 6,
                    children: [
                      _LegendaDot(color: _cActivo, label: 'Activos ($activos)'),
                      _LegendaDot(
                        color: _cPendiente,
                        label: 'Pend. ($pendientes)',
                      ),
                      _LegendaDot(
                        color: _cSubsanado,
                        label: 'Subsanados ($subsanados)',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        // ── Barras por grupo/sección ──────────────────────────────────────
        if (gruposSorted.isNotEmpty) ...[
          const SizedBox(height: 18),
          const Text(
            'Hallazgos por departamento',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 10),
          ...gruposSorted.map((g) => _GrupoBarRow(grupo: g, total: total)),
        ],
        // ── Histórico de puntajes ─────────────────────────────────────────
        if (widget.visitas.isNotEmpty) ...[
          const SizedBox(height: 22),
          const Divider(),
          const SizedBox(height: 10),
          // ── Cabecera del histórico — responsive ──────────────────────
          LayoutBuilder(
            builder: (context, hc) {
              final esMovil = hc.maxWidth < 560;
              final segBtn = SegmentedButton<String>(
                style: SegmentedButton.styleFrom(
                  textStyle: const TextStyle(fontSize: 12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                segments: const [
                  ButtonSegment(
                    value: 'puntajes',
                    label: Text('Puntajes'),
                    icon: Icon(Icons.show_chart_rounded, size: 16),
                  ),
                  ButtonSegment(
                    value: 'hallazgos',
                    label: Text('Hallazgos'),
                    icon: Icon(Icons.bar_chart_rounded, size: 16),
                  ),
                ],
                selected: {_modo},
                onSelectionChanged: (s) => setState(() => _modo = s.first),
              );
              final dropCat = _modo == 'puntajes'
                  ? DropdownButtonFormField<String>(
                      initialValue: _categoriaKey,
                      decoration: const InputDecoration(
                        labelText: 'Filtrar por',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: '',
                          child: Text('Total general'),
                        ),
                        ...kInterventoriaCategorias.map(
                          (cat) => DropdownMenuItem(
                            value: cat.key,
                            child: Text(cat.label),
                          ),
                        ),
                      ],
                      onChanged: (v) => setState(() => _categoriaKey = v ?? ''),
                    )
                  : null;

              if (esMovil) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Histórico',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF334155),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(width: double.infinity, child: segBtn),
                    if (dropCat != null) ...[
                      const SizedBox(height: 8),
                      dropCat,
                    ],
                  ],
                );
              }

              // Escritorio: original en Row
              return Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Histórico',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF334155),
                      ),
                    ),
                  ),
                  segBtn,
                  if (dropCat != null) ...[
                    const SizedBox(width: 10),
                    SizedBox(width: 210, child: dropCat),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          // ── Modo Puntajes: línea de tiempo ────────────────────────────
          if (_modo == 'puntajes')
            _TimelineChartCard(
              title: 'Evolución del puntaje — $categoriaLabel',
              subtitle: '${widget.visitas.length} visita(s) registradas',
              points: timelinePoints,
            )
          // ── Modo Hallazgos: barras apiladas por fecha ─────────────────
          else
            _HallazgosTimeline(hallazgos: widget.hallazgos),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Barras de hallazgos agrupadas por fecha de acta
// ─────────────────────────────────────────────────────────────────────────────
class _HallazgosTimeline extends StatelessWidget {
  final List<InterventoriaHallazgo> hallazgos;
  const _HallazgosTimeline({required this.hallazgos});

  @override
  Widget build(BuildContext context) {
    if (hallazgos.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(
          child: Text(
            'Sin hallazgos para mostrar',
            style: TextStyle(color: Color(0xFF94A3B8)),
          ),
        ),
      );
    }

    // Agrupar por fecha (día) de fechaHallazgo
    final fmt = DateFormat('dd/MM/yy');
    final Map<String, _FechaStats> porFecha = {};
    for (final h in hallazgos) {
      final key = fmt.format(h.fechaHallazgo.toDate());
      final s = porFecha.putIfAbsent(key, () => _FechaStats(key));
      if (h.isSubsanado) {
        s.subsanados++;
      } else if (h.isPendienteAprobacion) {
        s.pendientes++;
      } else {
        s.activos++;
      }
    }
    final fechas = porFecha.values.toList()
      ..sort((a, b) => a.label.compareTo(b.label));
    final maxTotal = fechas.map((f) => f.total).reduce((a, b) => a > b ? a : b);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Hallazgos por fecha de acta',
              style: TextStyle(
                fontFamily: _kFont,
                fontWeight: FontWeight.w900,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Activos · Pendientes · Subsanados',
              style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 16),
            ...fechas.map((f) {
              final pct = maxTotal == 0 ? 0.0 : f.total / maxTotal;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 68,
                      child: Text(
                        f.label,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF334155),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, c) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(5),
                                child: SizedBox(
                                  height: 20,
                                  width: c.maxWidth * pct,
                                  child: Row(
                                    children: [
                                      if (f.activos > 0)
                                        Flexible(
                                          flex: f.activos,
                                          child: Container(
                                            color: const Color(0xFFEF4444),
                                          ),
                                        ),
                                      if (f.pendientes > 0)
                                        Flexible(
                                          flex: f.pendientes,
                                          child: Container(
                                            color: const Color(0xFFF59E0B),
                                          ),
                                        ),
                                      if (f.subsanados > 0)
                                        Flexible(
                                          flex: f.subsanados,
                                          child: Container(
                                            color: const Color(0xFF22C55E),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 3),
                              Wrap(
                                spacing: 8,
                                children: [
                                  if (f.activos > 0)
                                    Text(
                                      '${f.activos} activo${f.activos > 1 ? 's' : ''}',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Color(0xFFEF4444),
                                      ),
                                    ),
                                  if (f.pendientes > 0)
                                    Text(
                                      '${f.pendientes} pendiente${f.pendientes > 1 ? 's' : ''}',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Color(0xFFF59E0B),
                                      ),
                                    ),
                                  if (f.subsanados > 0)
                                    Text(
                                      '${f.subsanados} subsanado${f.subsanados > 1 ? 's' : ''}',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Color(0xFF22C55E),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${f.total}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 4),
            // Leyenda
            Wrap(
              spacing: 16,
              children: const [
                _LegendaDot(color: Color(0xFFEF4444), label: 'Activos'),
                _LegendaDot(
                  color: Color(0xFFF59E0B),
                  label: 'Pend. aprobación',
                ),
                _LegendaDot(color: Color(0xFF22C55E), label: 'Subsanados'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FechaStats {
  final String label;
  int activos = 0, pendientes = 0, subsanados = 0;
  _FechaStats(this.label);
  int get total => activos + pendientes + subsanados;
}

class _GrupoStats {
  final String nombre;
  int activos = 0, pendientes = 0, subsanados = 0;
  _GrupoStats(this.nombre);
  int get total => activos + pendientes + subsanados;
}

class _KpiCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        // En pantallas pequeñas los KPI cards se estiran con Wrap;
        // usamos un ancho mínimo en lugar de uno fijo.
        return ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 120, maxWidth: 180),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withValues(alpha: 0.35)),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF64748B),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BarraEstado extends StatelessWidget {
  final int activos, pendientes, subsanados;
  const _BarraEstado({
    required this.activos,
    required this.pendientes,
    required this.subsanados,
  });

  @override
  Widget build(BuildContext context) {
    final total = activos + pendientes + subsanados;
    if (total == 0) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        height: 14,
        child: Row(
          children: [
            if (activos > 0)
              Flexible(
                flex: activos,
                child: Container(color: const Color(0xFFEF4444)),
              ),
            if (pendientes > 0)
              Flexible(
                flex: pendientes,
                child: Container(color: const Color(0xFFF59E0B)),
              ),
            if (subsanados > 0)
              Flexible(
                flex: subsanados,
                child: Container(color: const Color(0xFF22C55E)),
              ),
          ],
        ),
      ),
    );
  }
}

class _LegendaDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendaDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
        ),
      ],
    );
  }
}

class _GrupoBarRow extends StatelessWidget {
  final _GrupoStats grupo;
  final int total;
  const _GrupoBarRow({required this.grupo, required this.total});

  @override
  Widget build(BuildContext context) {
    final pct = total == 0 ? 0.0 : grupo.total / total;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              grupo.nombre,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF334155),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                return Stack(
                  children: [
                    Container(
                      height: 18,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: SizedBox(
                        height: 18,
                        width: c.maxWidth * pct,
                        child: Row(
                          children: [
                            if (grupo.activos > 0)
                              Flexible(
                                flex: grupo.activos,
                                child: Container(
                                  color: const Color(0xFFEF4444),
                                ),
                              ),
                            if (grupo.pendientes > 0)
                              Flexible(
                                flex: grupo.pendientes,
                                child: Container(
                                  color: const Color(0xFFF59E0B),
                                ),
                              ),
                            if (grupo.subsanados > 0)
                              Flexible(
                                flex: grupo.subsanados,
                                child: Container(
                                  color: const Color(0xFF22C55E),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${grupo.total}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF334155),
            ),
          ),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  final List<double> values;
  final List<Color> colors;
  const _DonutPainter({required this.values, required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold(0.0, (a, b) => a + b);
    if (total == 0) return;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2;
    const strokeWidth = 22.0;
    final rect = Rect.fromCircle(
      center: center,
      radius: radius - strokeWidth / 2,
    );
    var startAngle = -1.5707963267948966; // -π/2 (top)
    for (var i = 0; i < values.length; i++) {
      if (values[i] == 0) continue;
      final sweep = (values[i] / total) * 6.283185307179586; // 2π
      final paint = Paint()
        ..color = colors[i]
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(rect, startAngle, sweep - 0.04, false, paint);
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.values != values || old.colors != colors;
}

// ─────────────────────────────────────────────────────────────────────────────
// Widget: fila de puntaje por sección en el formulario de registro
// ─────────────────────────────────────────────────────────────────────────────

class _ItemPuntajeRow extends StatefulWidget {
  final InterventoriaItem item;
  final String ocrText;
  final Future<List<String>> Function() onPickOcrSnippets;
  final ValueChanged<InterventoriaItem> onChanged;

  /// false en Fase 1 (solo puntaje). true en Fase 2 (puntaje + observaciones).
  final bool showObservaciones;

  /// Acta a la que pertenece el ítem. Decide qué aspectos ofrece el catálogo:
  /// sin esto siempre se ofrecían los del acta regular.
  final String? tipoActa;

  const _ItemPuntajeRow({
    required this.item,
    required this.ocrText,
    required this.onPickOcrSnippets,
    required this.onChanged,
    this.showObservaciones = true,
    this.tipoActa,
  });

  @override
  State<_ItemPuntajeRow> createState() => _ItemPuntajeRowState();
}

class _ItemPuntajeRowState extends State<_ItemPuntajeRow> {
  InterventoriaItem get item => widget.item;
  late final TextEditingController _puntajeCtrl;
  final _puntajeFocus = FocusNode();

  String _formatPuntaje(double? v) =>
      v == null ? '' : v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1);

  @override
  void initState() {
    super.initState();
    _puntajeCtrl = TextEditingController(text: _formatPuntaje(item.valor));
    _puntajeFocus.addListener(() {
      // Al perder el foco, refleja en el texto el valor ya validado
      // (p. ej. si se escribió "8958" el modelo quedó en 0 — el texto
      // debe mostrar "0", no dejar el número fuera de rango visible).
      if (!_puntajeFocus.hasFocus) {
        final next = _formatPuntaje(item.valor);
        if (_puntajeCtrl.text != next) _puntajeCtrl.text = next;
      }
    });
  }

  @override
  void didUpdateWidget(covariant _ItemPuntajeRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_puntajeFocus.hasFocus) return;
    final next = _formatPuntaje(item.valor);
    if (_puntajeCtrl.text != next) _puntajeCtrl.text = next;
  }

  @override
  void dispose() {
    _puntajeCtrl.dispose();
    _puntajeFocus.dispose();
    super.dispose();
  }

  List<InterventoriaNota> get _notes {
    if (item.observaciones.isNotEmpty) return item.observaciones;
    if (item.observacion.trim().isEmpty) return const [];
    return [
      InterventoriaNota(texto: item.observacion.trim(), fuente: item.fuente),
    ];
  }

  void _setNotes(List<InterventoriaNota> notes) {
    widget.onChanged(
      item.copyWith(
        observaciones: notes,
        observacion: notes.map((n) => n.texto.trim()).join('\n'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = item.noEvaluado
        ? const Color(0xFF94A3B8)
        : _percentColor(item.valor ?? 0);
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Fila 1: dot + label (ocupa todo el ancho) ────────────
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.label,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                    // sin overflow — el label tiene todo el ancho disponible
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // ── Fila 2: NE toggle + input % (alineados a la derecha) ─
            Row(
              children: [
                const Spacer(),
                // Toggle NE
                GestureDetector(
                  onTap: () => widget.onChanged(
                    item.copyWith(
                      noEvaluado: !item.noEvaluado,
                      clearValor: !item.noEvaluado,
                    ),
                  ),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: item.noEvaluado
                          ? const Color(0xFF64748B)
                          : Colors.transparent,
                      border: Border.all(
                        color: item.noEvaluado
                            ? const Color(0xFF64748B)
                            : const Color(0xFFCBD5E1),
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'NE',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: item.noEvaluado
                            ? Colors.white
                            : const Color(0xFFB0BEC5),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // Input porcentaje
                SizedBox(
                  width: 86,
                  child: TextFormField(
                    enabled: !item.noEvaluado,
                    controller: _puntajeCtrl,
                    focusNode: _puntajeFocus,
                    textAlign: TextAlign.center,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: item.noEvaluado ? const Color(0xFF94A3B8) : color,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: '—',
                      suffixText: '%',
                      border: const OutlineInputBorder(),
                      filled: true,
                      fillColor: item.noEvaluado
                          ? const Color(0xFFF1F5F9)
                          : color.withValues(alpha: 0.08),
                    ),
                    onChanged: (v) => _aplicarCorreccionPuntaje(
                      v,
                      _puntajeCtrl,
                      (valido) =>
                          widget.onChanged(item.copyWith(valor: valido)),
                    ),
                  ),
                ),
              ],
            ),
            // ── Fila 3: Observaciones múltiples (solo Fase 2) ─────────
            if (widget.showObservaciones) ...[
              const SizedBox(height: 8),
              _NotasInlineEditor(
                notes: _notes,
                compact: true,
                emptyText: 'Sin observaciones',
                catalogItems: aspectosDeActa(widget.tipoActa, item.key),
                catalogAsAspect: true,
                allowManual: false,
                allowOcrBulk: false,
                onPickOcrSnippets: widget.onPickOcrSnippets,
                onChanged: _setNotes,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab Visitas
// ─────────────────────────────────────────────────────────────────────────────

class _VisitasTab extends StatefulWidget {
  final String empresaId;
  final String userId;
  final bool canWrite;
  final InterventoriaService service;
  final VoidCallback onRegistrar;
  final bool esAdminDesarrollo;

  /// Si no es null, filtra visitas solo para este centro (rol Registrador).
  final String? centroFijoId;

  const _VisitasTab({
    required this.empresaId,
    required this.userId,
    required this.canWrite,
    required this.service,
    required this.onRegistrar,
    this.centroFijoId,
    this.esAdminDesarrollo = false,
  });

  @override
  State<_VisitasTab> createState() => _VisitasTabState();
}

class _VisitasTabState extends State<_VisitasTab> {
  DateTime? _fechaDesde;
  DateTime? _fechaHasta;
  int? _periodoRapidoDias = 60;
  // 'fecha_desc' | 'fecha_asc' | 'alfabetico'
  String _orden = 'fecha_desc';

  @override
  void initState() {
    super.initState();
    _aplicarPeriodoRapido(60, notify: false);
  }

  void _aplicarPeriodoRapido(int? dias, {bool notify = true}) {
    void apply() {
      _periodoRapidoDias = dias;
      _fechaHasta = null;
      _fechaDesde = dias == null
          ? null
          : DateTime.now().subtract(Duration(days: dias));
    }

    if (notify) {
      setState(apply);
    } else {
      apply();
    }
  }

  Future<void> _seleccionarFecha(bool esDesde) async {
    final actual = esDesde ? _fechaDesde : _fechaHasta;
    final picked = await showDatePicker(
      context: context,
      initialDate: actual ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      _periodoRapidoDias = null;
      if (esDesde) {
        _fechaDesde = picked;
      } else {
        _fechaHasta = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<InterventoriaVisita>>(
      stream: widget.service.streamVisitas(
        widget.empresaId,
        centroId: widget.centroFijoId,
      ),
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        var visitas = snap.data ?? [];
        if (visitas.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.assignment_outlined,
                  size: 52,
                  color: Color(0xFF94A3B8),
                ),
                const SizedBox(height: 12),
                const Text('Sin actas registradas'),
                if (widget.canWrite) ...[
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: widget.onRegistrar,
                    icon: const Icon(Icons.document_scanner_rounded),
                    label: const Text('Registrar primera acta'),
                  ),
                ],
              ],
            ),
          );
        }

        if (_fechaDesde != null) {
          visitas = visitas
              .where((v) => !v.fechaVisita.toDate().isBefore(_fechaDesde!))
              .toList();
        }
        if (_fechaHasta != null) {
          final hasta = _fechaHasta!.add(
            const Duration(hours: 23, minutes: 59, seconds: 59),
          );
          visitas = visitas
              .where((v) => !v.fechaVisita.toDate().isAfter(hasta))
              .toList();
        }
        visitas = visitas.toList();
        switch (_orden) {
          case 'fecha_asc':
            visitas.sort((a, b) => a.fechaVisita.compareTo(b.fechaVisita));
            break;
          case 'alfabetico':
            visitas.sort(
              (a, b) => a.centroCostoNombre.toLowerCase().compareTo(
                b.centroCostoNombre.toLowerCase(),
              ),
            );
            break;
          default: // fecha_desc
            visitas.sort((a, b) => b.fechaVisita.compareTo(a.fechaVisita));
        }

        final isWeb = MediaQuery.of(ctx).size.width >= 900;
        final fmt = DateFormat('dd/MM/yy');
        return InternalModuleViewport(
          maxWidth: 1300,
          padding: EdgeInsets.all(isWeb ? 22 : 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ChoiceChip(
                    label: const Text('Últimos 30 días'),
                    selected: _periodoRapidoDias == 30,
                    onSelected: (_) => _aplicarPeriodoRapido(30),
                  ),
                  ChoiceChip(
                    label: const Text('Últimos 60 días'),
                    selected: _periodoRapidoDias == 60,
                    onSelected: (_) => _aplicarPeriodoRapido(60),
                  ),
                  ChoiceChip(
                    label: const Text('Todo el histórico'),
                    selected:
                        _periodoRapidoDias == null &&
                        _fechaDesde == null &&
                        _fechaHasta == null,
                    onSelected: (_) => _aplicarPeriodoRapido(null),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _seleccionarFecha(true),
                    icon: const Icon(Icons.event_rounded, size: 16),
                    label: Text(
                      _fechaDesde == null ? 'Desde' : fmt.format(_fechaDesde!),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _seleccionarFecha(false),
                    icon: const Icon(Icons.event_rounded, size: 16),
                    label: Text(
                      _fechaHasta == null ? 'Hasta' : fmt.format(_fechaHasta!),
                    ),
                  ),
                  if (_fechaDesde != null || _fechaHasta != null)
                    IconButton(
                      tooltip: 'Quitar filtro de fechas',
                      icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
                      onPressed: () => setState(() {
                        _periodoRapidoDias = null;
                        _fechaDesde = null;
                        _fechaHasta = null;
                      }),
                    ),
                  const SizedBox(width: 4),
                  DropdownButton<String>(
                    value: _orden,
                    underline: const SizedBox.shrink(),
                    items: const [
                      DropdownMenuItem(
                        value: 'fecha_desc',
                        child: Text('Fecha (recientes primero)'),
                      ),
                      DropdownMenuItem(
                        value: 'fecha_asc',
                        child: Text('Fecha (antiguas primero)'),
                      ),
                      DropdownMenuItem(
                        value: 'alfabetico',
                        child: Text('Alfabético'),
                      ),
                    ],
                    onChanged: (v) =>
                        setState(() => _orden = v ?? 'fecha_desc'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: visitas.isEmpty
                    ? const Center(
                        child: Text('Sin actas para el filtro aplicado'),
                      )
                    : ListView.separated(
                        itemCount: visitas.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => _VisitaCard(
                          visita: visitas[i],
                          canWrite: widget.canWrite,
                          service: widget.service,
                          esAdminDesarrollo: widget.esAdminDesarrollo,
                          userId: widget.userId,
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _VisitaCard extends StatefulWidget {
  final InterventoriaVisita visita;
  final bool canWrite;
  final InterventoriaService service;
  final bool esAdminDesarrollo;
  final String userId;

  const _VisitaCard({
    required this.visita,
    required this.canWrite,
    required this.service,
    this.esAdminDesarrollo = false,
    this.userId = '',
  });

  @override
  State<_VisitaCard> createState() => _VisitaCardState();
}

class _VisitaCardState extends State<_VisitaCard> {
  bool _expanded = false;

  String _buildSubtitle(InterventoriaVisita visita) {
    final parts = <String>[
      DateFormat('dd/MM/yyyy').format(visita.fechaVisita.toDate()),
    ];
    if ((visita.tipoActa ?? '').isNotEmpty) {
      parts.add(visita.tipoActa!);
    }
    if ((visita.tiempoComida ?? '').isNotEmpty) {
      parts.add(visita.tiempoComida!);
    }
    return parts.join('  ·  ');
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.visita;
    final pct = v.porcentajeGeneral;
    final color = _percentColor(pct);

    return Card(
      child: Column(
        children: [
          // Cabecera
          ListTile(
            leading: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  '${pct.toStringAsFixed(0)}%',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
            title: Text(
              v.centroCostoNombre,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(_buildSubtitle(v)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.esAdminDesarrollo && v.faseActa == 'completa')
                  IconButton(
                    tooltip: 'Reabrir para revisión (admin)',
                    icon: Icon(Icons.edit_rounded, color: _kAccent),
                    onPressed: () => _reabrirParaRevision(context, v),
                  ),
                if (widget.canWrite)
                  IconButton(
                    tooltip: 'Solicitar eliminación',
                    icon: Icon(
                      Icons.delete_outline,
                      color: Colors.red.shade400,
                    ),
                    onPressed: () => _confirmarEliminar(context),
                  ),
                IconButton(
                  icon: Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                  ),
                  onPressed: () => setState(() => _expanded = !_expanded),
                ),
              ],
            ),
          ),
          // Detalle expandido
          if (_expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if ((v.tipoActa ?? '').isNotEmpty)
                        _DetailChip(
                          icon: Icons.description_outlined,
                          label: v.tipoActa!,
                        ),
                      if ((v.tiempoComida ?? '').isNotEmpty)
                        _DetailChip(
                          icon: Icons.restaurant_outlined,
                          label: v.tiempoComida!,
                        ),
                    ],
                  ),
                  if (v.ocrDatosDetectados['observacionesGenerales']
                          ?.toString()
                          .trim()
                          .isNotEmpty ==
                      true) ...[
                    const SizedBox(height: 10),
                    _VisitTextBlock(
                      title: 'Observaciones generales',
                      text: v.ocrDatosDetectados['observacionesGenerales']
                          .toString(),
                    ),
                  ],
                  if (v.ocrDatosDetectados['conclusiones']
                          ?.toString()
                          .trim()
                          .isNotEmpty ==
                      true) ...[
                    const SizedBox(height: 10),
                    _VisitTextBlock(
                      title: 'Conclusiones',
                      text: v.ocrDatosDetectados['conclusiones'].toString(),
                    ),
                  ],
                  const SizedBox(height: 10),
                  ...kInterventoriaCategorias.map((cat) {
                    final item =
                        v.items[cat.key] ?? InterventoriaItem.empty(cat);
                    return _VisitaItemRow(item: item);
                  }),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmarEliminar(BuildContext context) async {
    final reason = await _pedirMotivoEliminacion(
      context,
      entidad:
          'El acta de ${widget.visita.centroCostoNombre} '
          '(${DateFormat('dd/MM/yyyy').format(widget.visita.fechaVisita.toDate())})',
    );
    if (reason == null) return;
    try {
      await widget.service.solicitarEliminacion(
        empresaId: widget.visita.empresaId,
        tipo: 'visita',
        entidadId: widget.visita.id,
        motivo: reason,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Solicitud enviada para aprobación.')),
        );
      }
    } on FirebaseFunctionsException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message ?? 'No se pudo enviar.')),
        );
      }
    }
  }

  Future<void> _reabrirParaRevision(
    BuildContext context,
    InterventoriaVisita visita,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reabrir acta para revisión'),
        content: Text(
          'El acta de ${visita.centroCostoNombre} '
          '(${DateFormat('dd/MM/yyyy').format(visita.fechaVisita.toDate())}) '
          'volverá a aparecer en "Por revisar" para que la persona encargada '
          'pueda editar las observaciones. Los puntajes ya guardados no se '
          'modifican.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reabrir'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.service.reabrirActaParaRevision(visita.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: _kOk,
          content: Text('Acta reabierta — disponible en "Por revisar"'),
        ),
      );
    }
  }
}

class _DetailChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _DetailChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF475569)),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF334155),
            ),
          ),
        ],
      ),
    );
  }
}

class _VisitTextBlock extends StatelessWidget {
  final String title;
  final String text;

  const _VisitTextBlock({required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            text,
            style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
          ),
        ],
      ),
    );
  }
}

class _VisitaItemRow extends StatelessWidget {
  final InterventoriaItem item;

  const _VisitaItemRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final isNe = item.noEvaluado;
    final pct = item.valor;
    final color = isNe ? const Color(0xFF94A3B8) : _percentColor(pct ?? 0);
    final notes = item.observaciones
        .where((note) => note.texto.trim().isNotEmpty)
        .toList();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
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
                  child: Text(item.label, style: const TextStyle(fontSize: 12)),
                ),
                if (isNe)
                  const Text(
                    'NE',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF94A3B8),
                      fontWeight: FontWeight.w700,
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${pct?.toStringAsFixed(1) ?? '–'}%',
                      style: TextStyle(
                        fontSize: 12,
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
            if (notes.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...notes.map(
                (note) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (note.aspecto.trim().isNotEmpty)
                          Text(
                            note.aspecto,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF334155),
                            ),
                          ),
                        if (note.aspecto.trim().isNotEmpty)
                          const SizedBox(height: 4),
                        Text(
                          note.texto,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF475569),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ] else if (item.observacion.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  item.observacion,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF475569),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab Análisis (directivos)
// ─────────────────────────────────────────────────────────────────────────────

class _AnalisisDirectivo extends StatefulWidget {
  final String empresaId;
  final InterventoriaService service;
  // Filtros compartidos con el resto de tabs
  final String centroFiltro;
  final DateTime? fechaDesde;
  final DateTime? fechaHasta;
  final ValueChanged<String>? onCentroChanged;
  final ValueChanged<DateTime?>? onFechaDesdeChanged;
  final ValueChanged<DateTime?>? onFechaHastaChanged;

  const _AnalisisDirectivo({
    required this.empresaId,
    required this.service,
    this.centroFiltro = '',
    this.fechaDesde,
    this.fechaHasta,
    this.onCentroChanged,
    this.onFechaDesdeChanged,
    this.onFechaHastaChanged,
  });

  @override
  State<_AnalisisDirectivo> createState() => _AnalisisDirectivoState();
}

class _AnalisisDirectivoState extends State<_AnalisisDirectivo> {
  // _centroId eliminado: usa widget.centroFiltro (compartido entre tabs)
  String _categoriaKey = '';

  Future<void> _seleccionarFecha(bool esDesde) async {
    final actual = esDesde ? widget.fechaDesde : widget.fechaHasta;
    final picked = await showDatePicker(
      context: context,
      initialDate: actual ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    if (esDesde) {
      widget.onFechaDesdeChanged?.call(picked);
    } else {
      widget.onFechaHastaChanged?.call(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<InterventoriaVisita>>(
      stream: widget.service.streamVisitas(widget.empresaId),
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final visitas = snap.data ?? [];
        final centrosMap = {
          for (final v in visitas) v.centroCostoId: v.centroCostoNombre,
        };

        // Aplicar filtros compartidos con los demás tabs
        var visitasFiltradas = widget.centroFiltro.isEmpty
            ? visitas
            : visitas
                  .where((v) => v.centroCostoId == widget.centroFiltro)
                  .toList();
        if (widget.fechaDesde != null) {
          visitasFiltradas = visitasFiltradas
              .where(
                (v) => !v.fechaVisita.toDate().isBefore(widget.fechaDesde!),
              )
              .toList();
        }
        if (widget.fechaHasta != null) {
          final hasta = widget.fechaHasta!.add(
            const Duration(hours: 23, minutes: 59, seconds: 59),
          );
          visitasFiltradas = visitasFiltradas
              .where((v) => !v.fechaVisita.toDate().isAfter(hasta))
              .toList();
        }

        // TODAS las visitas como columnas, ordenadas por fecha DESC
        final visitasParaTabla = visitasFiltradas.toList()
          ..sort((a, b) => b.fechaVisita.compareTo(a.fechaVisita));

        return InternalModuleViewport(
          maxWidth: 1800,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // ── Cabecera responsive ─────────────────────────────────────
              LayoutBuilder(
                builder: (context, constraints) {
                  final esMovil = constraints.maxWidth < 600;
                  final dropEstablecimiento = _CentroCostoFilterDropdown(
                    service: widget.service,
                    empresaId: widget.empresaId,
                    fallbackCentros: centrosMap,
                    value: widget.centroFiltro,
                    onChanged: widget.onCentroChanged,
                  );
                  final dropCategoria = DropdownButtonFormField<String>(
                    initialValue: _categoriaKey,
                    decoration: const InputDecoration(
                      labelText: 'Categoría del gráfico',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('Total general'),
                      ),
                      ...kInterventoriaCategorias.map(
                        (cat) => DropdownMenuItem(
                          value: cat.key,
                          child: Text(cat.label),
                        ),
                      ),
                    ],
                    onChanged: (v) => setState(() => _categoriaKey = v ?? ''),
                  );
                  final btnExportar = OutlinedButton.icon(
                    onPressed: visitas.isEmpty
                        ? null
                        : () => _exportarExcel(ctx, visitasFiltradas),
                    icon: const Icon(Icons.download_rounded, size: 16),
                    label: Text(esMovil ? 'Excel' : 'Exportar Excel'),
                  );
                  final fmtFecha = DateFormat('dd/MM/yy');
                  final btnDesde = OutlinedButton.icon(
                    onPressed: () => _seleccionarFecha(true),
                    icon: const Icon(Icons.event_rounded, size: 16),
                    label: Text(
                      widget.fechaDesde == null
                          ? 'Desde'
                          : fmtFecha.format(widget.fechaDesde!),
                    ),
                  );
                  final btnHasta = OutlinedButton.icon(
                    onPressed: () => _seleccionarFecha(false),
                    icon: const Icon(Icons.event_rounded, size: 16),
                    label: Text(
                      widget.fechaHasta == null
                          ? 'Hasta'
                          : fmtFecha.format(widget.fechaHasta!),
                    ),
                  );
                  final btnLimpiarFechas =
                      (widget.fechaDesde != null || widget.fechaHasta != null)
                      ? IconButton(
                          tooltip: 'Quitar filtro de fechas',
                          icon: const Icon(
                            Icons.filter_alt_off_rounded,
                            size: 18,
                          ),
                          onPressed: () {
                            widget.onFechaDesdeChanged?.call(null);
                            widget.onFechaHastaChanged?.call(null);
                          },
                        )
                      : const SizedBox.shrink();

                  if (esMovil) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Análisis de puntajes',
                          style: TextStyle(
                            fontFamily: _kFont,
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 10),
                        dropEstablecimiento,
                        const SizedBox(height: 8),
                        dropCategoria,
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [btnDesde, btnHasta, btnLimpiarFechas],
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: btnExportar,
                        ),
                      ],
                    );
                  }

                  // Web / tablet
                  return Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text(
                        'Análisis de puntajes por establecimiento',
                        style: TextStyle(
                          fontFamily: _kFont,
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                      ),
                      SizedBox(width: 220, child: dropEstablecimiento),
                      SizedBox(width: 240, child: dropCategoria),
                      btnDesde,
                      btnHasta,
                      btnLimpiarFechas,
                      btnExportar,
                    ],
                  );
                },
              ),
              const SizedBox(height: 14),
              // ── DataTable + Chart — responsive ──────────────────────────
              Expanded(
                child: LayoutBuilder(
                  builder: (context, lc) {
                    final esMovil = lc.maxWidth < 900;

                    final comparandoEstablecimientos =
                        widget.centroFiltro.isEmpty;
                    final chartCard = comparandoEstablecimientos
                        ? _ComparativoUltimaActaCard(
                            title: _categoriaKey.isEmpty
                                ? 'Última acta por establecimiento'
                                : 'Última acta por establecimiento · categoría',
                            subtitle: _buildComparativoSubtitle(
                              visitasFiltradas.length,
                            ),
                            points: compararUltimaActaPorEstablecimiento(
                              visitasFiltradas,
                              categoriaKey: _categoriaKey,
                            ),
                            onSelected: (centroId) =>
                                widget.onCentroChanged?.call(centroId),
                          )
                        : _TimelineChartCard(
                            title: _categoriaKey.isEmpty
                                ? 'Línea de tiempo del puntaje general'
                                : 'Línea de tiempo por categoría',
                            subtitle: _buildTimelineSubtitle(
                              centrosMap,
                              visitasFiltradas.length,
                            ),
                            points: _buildTimelinePoints(visitasFiltradas),
                          );

                    final fmt = DateFormat('dd/MM/yy');
                    final matrizCard = visitasParaTabla.isEmpty
                        ? const Center(child: Text('Sin visitas registradas'))
                        : Card(
                            child: BarraHorizontal(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: SingleChildScrollView(
                                  child: PagedDataTable(
                                    etiqueta: 'hallazgos',
                                    tabla: DataTable(
                                      headingRowColor: WidgetStateProperty.all(
                                        const Color(0xFFF1F5F9),
                                      ),
                                      columnSpacing: 16,
                                      columns: [
                                        const DataColumn(
                                          label: Text(
                                            'SECCIÓN',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w900,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ),
                                        // Una columna por VISITA (histórico completo)
                                        ...visitasParaTabla.map((v) {
                                          final pdfAdj = v.adjuntos
                                              .where(
                                                (a) =>
                                                    a.contentType.contains(
                                                      'pdf',
                                                    ) ||
                                                    a.nombre
                                                        .toLowerCase()
                                                        .endsWith('.pdf'),
                                              )
                                              .toList();
                                          return DataColumn(
                                            label: SizedBox(
                                              width: 100,
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    v
                                                            .centroCostoNombre
                                                            .isNotEmpty
                                                        ? v.centroCostoNombre
                                                        : v.centroCostoCodigo,
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w900,
                                                      fontSize: 11,
                                                    ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                  Text(
                                                    fmt.format(
                                                      v.fechaVisita.toDate(),
                                                    ),
                                                    style: const TextStyle(
                                                      fontSize: 10,
                                                      color: Color(0xFF64748B),
                                                    ),
                                                  ),
                                                  // Icono PDF si la visita tiene adjuntos PDF
                                                  if (pdfAdj.isNotEmpty)
                                                    InkWell(
                                                      onTap: () =>
                                                          _abrirPdfVisita(
                                                            ctx,
                                                            pdfAdj.first.url,
                                                            v.centroCostoNombre,
                                                            fmt.format(
                                                              v.fechaVisita
                                                                  .toDate(),
                                                            ),
                                                            fechaVisita: v
                                                                .fechaVisita
                                                                .toDate(),
                                                          ),
                                                      child: Row(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          Icon(
                                                            Icons
                                                                .picture_as_pdf_rounded,
                                                            size: 12,
                                                            color: Colors
                                                                .red
                                                                .shade500,
                                                          ),
                                                          const SizedBox(
                                                            width: 2,
                                                          ),
                                                          Text(
                                                            'Ver PDF',
                                                            style: TextStyle(
                                                              fontSize: 9,
                                                              color: Colors
                                                                  .red
                                                                  .shade500,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                          );
                                        }),
                                      ],
                                      rows: [
                                        ...kInterventoriaCategorias.map((cat) {
                                          return DataRow(
                                            cells: [
                                              DataCell(
                                                SizedBox(
                                                  width: 200,
                                                  child: Text(
                                                    cat.label,
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              ...visitasParaTabla.map((v) {
                                                final item = v.items[cat.key];
                                                return DataCell(
                                                  _CeldaPuntaje(
                                                    item: item,
                                                    onTap:
                                                        item != null &&
                                                            !item.noEvaluado
                                                        ? () =>
                                                              _mostrarDetalleCelda(
                                                                ctx,
                                                                cat.label,
                                                                v,
                                                                cat.key,
                                                              )
                                                        : null,
                                                  ),
                                                );
                                              }),
                                            ],
                                          );
                                        }),
                                        // Fila de total
                                        DataRow(
                                          color: WidgetStateProperty.all(
                                            const Color(0xFFF8FAFC),
                                          ),
                                          cells: [
                                            const DataCell(
                                              Text(
                                                'Total condiciones del servicio',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w900,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                            ...visitasParaTabla.map((v) {
                                              final pct = v.porcentajeGeneral;
                                              final color = _percentColor(pct);
                                              return DataCell(
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 3,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: color.withValues(
                                                      alpha: 0.15,
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          4,
                                                        ),
                                                  ),
                                                  child: Text(
                                                    '${pct.toStringAsFixed(1)}%',
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.w900,
                                                      fontSize: 12,
                                                      color: color,
                                                    ),
                                                  ),
                                                ),
                                              );
                                            }),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );

                    if (esMovil) {
                      // Móvil: scroll continuo — chart + tabla fluyen juntos
                      return SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            chartCard,
                            const SizedBox(height: 14),
                            matrizCard,
                            const SizedBox(height: 16),
                          ],
                        ),
                      );
                    }

                    // Web / tablet: chart arriba, tabla abajo con Expanded
                    return Column(
                      children: [
                        chartCard,
                        const SizedBox(height: 14),
                        Expanded(child: matrizCard),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _buildTimelineSubtitle(Map<String, String> centros, int totalVisitas) {
    final categoriaMatch = kInterventoriaCategorias
        .cast<InterventoriaCategoria?>()
        .firstWhere((cat) => cat?.key == _categoriaKey, orElse: () => null);
    final categoria = _categoriaKey.isEmpty
        ? 'Total general'
        : (categoriaMatch?.label ?? _categoriaKey);
    final centro = widget.centroFiltro.isEmpty
        ? 'Todos los establecimientos'
        : centros[widget.centroFiltro] ?? '';
    final rangoParts = <String>[];
    if (widget.fechaDesde != null) {
      rangoParts.add(
        'desde ${DateFormat('dd/MM/yy').format(widget.fechaDesde!)}',
      );
    }
    if (widget.fechaHasta != null) {
      rangoParts.add(
        'hasta ${DateFormat('dd/MM/yy').format(widget.fechaHasta!)}',
      );
    }
    final rango = rangoParts.isEmpty ? '' : ' · ${rangoParts.join(' ')}';
    return '$categoria · $centro · $totalVisitas visita(s)$rango';
  }

  String _buildComparativoSubtitle(int totalVisitas) {
    final categoriaMatch = kInterventoriaCategorias
        .cast<InterventoriaCategoria?>()
        .firstWhere((cat) => cat?.key == _categoriaKey, orElse: () => null);
    final categoria = _categoriaKey.isEmpty
        ? 'Total general'
        : (categoriaMatch?.label ?? _categoriaKey);
    final rangoParts = <String>[];
    if (widget.fechaDesde != null) {
      rangoParts.add(
        'desde ${DateFormat('dd/MM/yy').format(widget.fechaDesde!)}',
      );
    }
    if (widget.fechaHasta != null) {
      rangoParts.add(
        'hasta ${DateFormat('dd/MM/yy').format(widget.fechaHasta!)}',
      );
    }
    final rango = rangoParts.isEmpty ? '' : ' · ${rangoParts.join(' ')}';
    return '$categoria · última acta disponible · '
        '$totalVisitas visita(s) analizadas$rango';
  }

  double _valueForVisit(InterventoriaVisita visita) {
    if (_categoriaKey.isEmpty) return visita.porcentajeGeneral;
    final item = visita.items[_categoriaKey];
    if (item == null || item.noEvaluado || item.valor == null) return -1;
    return item.valor!.clamp(0, 100).toDouble();
  }

  List<_TimelinePoint> _buildTimelinePoints(List<InterventoriaVisita> visitas) {
    if (visitas.isEmpty) return const [];
    // Siempre mostrar cada visita como punto individual (no promediar)
    final sorted = visitas.toList()
      ..sort((a, b) => a.fechaVisita.compareTo(b.fechaVisita));
    return sorted
        .map((visita) {
          final value = _valueForVisit(visita);
          if (value < 0) return null;
          return _TimelinePoint(
            label: DateFormat('dd/MM').format(visita.fechaVisita.toDate()),
            value: value,
            caption: visita.centroCostoNombre,
          );
        })
        .whereType<_TimelinePoint>()
        .toList();
  }

  void _abrirPdfVisita(
    BuildContext context,
    String url,
    String centro,
    String fecha, {
    DateTime? fechaVisita,
  }) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: SizedBox(
          width: 900,
          height: 680,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
                child: Row(
                  children: [
                    const Icon(Icons.picture_as_pdf_rounded, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Acta PDF — $centro · $fecha',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    // Descarga propia: el botón del visor del navegador no
                    // sirve porque el PDF se muestra desde un blob URL y el
                    // archivo sale con el UUID del blob por nombre.
                    IconButton(
                      icon: const Icon(Icons.download_rounded),
                      tooltip: 'Descargar acta',
                      onPressed: () => _descargarActaPdf(
                        context,
                        url: url,
                        centro: centro,
                        fechaVisita: fechaVisita,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.open_in_new_rounded),
                      tooltip: 'Abrir en pestaña nueva',
                      onPressed: () => launchUrlString(
                        url,
                        mode: LaunchMode.externalApplication,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(child: WebPdfView(url: url)),
            ],
          ),
        ),
      ),
    );
  }

  /// Descarga el acta y la abre. En web el visor muestra el PDF desde un blob
  /// URL, así que el "guardar" del navegador produce un archivo con el UUID
  /// del blob por nombre; aquí se rearma con centro y fecha para que el
  /// archivo sea reconocible fuera de la app.
  Future<void> _descargarActaPdf(
    BuildContext context, {
    required String url,
    required String centro,
    DateTime? fechaVisita,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final centroSlug = (centro.trim().isEmpty ? 'acta' : centro)
        .replaceAll(RegExp(r'[^\wáéíóúÁÉÍÓÚñÑ ]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '_');
    final fechaSlug = DateFormat(
      'yyyyMMdd',
    ).format(fechaVisita ?? DateTime.now());
    final nombre = 'Acta_${centroSlug}_$fechaSlug';
    try {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode != 200) {
        throw Exception('HTTP ${res.statusCode}');
      }
      if (kIsWeb) {
        await FileSaver.instance.saveFile(
          name: nombre,
          bytes: res.bodyBytes,
          fileExtension: 'pdf',
          mimeType: MimeType.pdf,
        );
      } else {
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/$nombre.pdf');
        await file.writeAsBytes(res.bodyBytes);
        await OpenFilex.open(file.path);
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: _kDanger,
          content: Text('No se pudo descargar el acta: $e'),
        ),
      );
    }
  }

  void _mostrarDetalleCelda(
    BuildContext context,
    String seccionLabel,
    InterventoriaVisita visita,
    String catKey,
  ) {
    final item = visita.items[catKey];
    if (item == null) return;

    final obs = item.observaciones.isNotEmpty
        ? item.observaciones
        : item.observacion.trim().isNotEmpty
        ? [
            InterventoriaNota(
              texto: item.observacion.trim(),
              fuente: item.fuente,
            ),
          ]
        : <InterventoriaNota>[];
    final obsFiltradas = obs.where((n) => n.texto.trim().isNotEmpty).toList();

    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Encabezado
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(12),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.search_rounded, color: Color(0xFF1E3A8A)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            seccionLabel,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            '${visita.centroCostoNombre} · ${DateFormat('dd/MM/yyyy').format(visita.fechaVisita.toDate())}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Puntaje
                    if (item.valor != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _percentColor(
                            item.valor!,
                          ).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${item.valor!.toStringAsFixed(1)}%',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: _percentColor(item.valor!),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Observaciones (causa del puntaje bajo)
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: obsFiltradas.isEmpty
                      ? const Text(
                          'No hay observaciones registradas para esta sección.',
                          style: TextStyle(color: Color(0xFF64748B)),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Observaciones registradas',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ...obsFiltradas.asMap().entries.map((e) {
                              final n = e.value;
                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEF2F2),
                                  border: Border.all(
                                    color: const Color(0xFFFECACA),
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (n.aspecto.trim().isNotEmpty)
                                      Text(
                                        n.aspecto,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 12,
                                          color: Color(0xFF991B1B),
                                        ),
                                      ),
                                    if (n.texto.trim().isNotEmpty)
                                      Padding(
                                        padding: EdgeInsets.only(
                                          top: n.aspecto.trim().isNotEmpty
                                              ? 4
                                              : 0,
                                        ),
                                        child: Text(
                                          n.texto,
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _exportarExcel(
    BuildContext context,
    List<InterventoriaVisita> visitas,
  ) async {
    try {
      final bytes = widget.service.exportarVisitasExcel(visitas);
      final nombre =
          'Analisis_Interventoria_${DateFormat('yyyyMMdd').format(DateTime.now())}';
      if (kIsWeb) {
        await FileSaver.instance.saveFile(
          name: nombre,
          bytes: bytes,
          fileExtension: 'xlsx',
          mimeType: MimeType.microsoftExcel,
        );
      } else {
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/$nombre.xlsx');
        await file.writeAsBytes(bytes);
        await OpenFilex.open(file.path);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al exportar: $e')));
      }
    }
  }
}

class _ComparativoUltimaActaCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<InterventoriaComparativoActa> points;
  final ValueChanged<String>? onSelected;

  const _ComparativoUltimaActaCard({
    required this.title,
    required this.subtitle,
    required this.points,
    this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontFamily: _kFont,
                fontWeight: FontWeight.w900,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 6),
            const Text(
              'Selecciona una barra para abrir el histórico del establecimiento.',
              style: TextStyle(fontSize: 11, color: Color(0xFF0F766E)),
            ),
            const SizedBox(height: 10),
            if (points.isEmpty)
              const SizedBox(
                height: 220,
                child: Center(child: Text('Sin actas para comparar')),
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final requiredWidth = 56.0 + (points.length * 118.0);
                  final chartWidth = requiredWidth > constraints.maxWidth
                      ? requiredWidth
                      : constraints.maxWidth;
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: chartWidth,
                      height: 270,
                      child: MouseRegion(
                        cursor: onSelected == null
                            ? SystemMouseCursors.basic
                            : SystemMouseCursors.click,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapDown: onSelected == null
                              ? null
                              : (details) {
                                  const left = 46.0;
                                  final plotWidth = chartWidth - left - 18;
                                  if (details.localPosition.dx < left ||
                                      plotWidth <= 0) {
                                    return;
                                  }
                                  final slot = plotWidth / points.length;
                                  final index =
                                      ((details.localPosition.dx - left) / slot)
                                          .floor();
                                  if (index >= 0 && index < points.length) {
                                    onSelected?.call(
                                      points[index].centroCostoId,
                                    );
                                  }
                                },
                          child: CustomPaint(
                            painter: _ComparativoUltimaActaPainter(points),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _ComparativoUltimaActaPainter extends CustomPainter {
  final List<InterventoriaComparativoActa> points;

  const _ComparativoUltimaActaPainter(this.points);

  void _text(
    Canvas canvas,
    String value,
    Offset offset, {
    double fontSize = 10,
    Color color = const Color(0xFF64748B),
    FontWeight fontWeight = FontWeight.w400,
    double? maxWidth,
    TextAlign textAlign = TextAlign.left,
    int maxLines = 1,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          fontFamily: _kFont,
          fontSize: fontSize,
          color: color,
          fontWeight: fontWeight,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
      textAlign: textAlign,
      maxLines: maxLines,
      ellipsis: maxLines == 1 ? '…' : null,
    )..layout(maxWidth: maxWidth ?? double.infinity);
    painter.paint(canvas, offset);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    const left = 46.0;
    const right = 18.0;
    const top = 24.0;
    const bottom = 72.0;
    final plotWidth = size.width - left - right;
    final plotHeight = size.height - top - bottom;
    if (plotWidth <= 0 || plotHeight <= 0) return;

    final gridPaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..strokeWidth = 1;
    for (var value = 0; value <= 100; value += 25) {
      final y = top + plotHeight - (value / 100 * plotHeight);
      canvas.drawLine(
        Offset(left, y),
        Offset(size.width - right, y),
        gridPaint,
      );
      _text(
        canvas,
        '$value%',
        Offset(2, y - 6),
        fontSize: 9,
        color: const Color(0xFF94A3B8),
      );
    }

    final slot = plotWidth / points.length;
    final candidateWidth = slot * .52;
    final barWidth = candidateWidth > 50 ? 50.0 : candidateWidth;
    final fmt = DateFormat('dd/MM/yy');
    for (var index = 0; index < points.length; index++) {
      final point = points[index];
      final centerX = left + (slot * index) + (slot / 2);
      final value = point.valor;
      final color = value == null
          ? const Color(0xFFCBD5E1)
          : _percentColor(value);
      final height = value == null ? 6.0 : (value / 100 * plotHeight);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          centerX - (barWidth / 2),
          top + plotHeight - height,
          barWidth,
          height,
        ),
        const Radius.circular(5),
      );
      canvas.drawRRect(rect, Paint()..color = color);

      final valueLabel = value == null
          ? 'Sin dato'
          : '${value.toStringAsFixed(1)}%';
      final valuePainter = TextPainter(
        text: TextSpan(
          text: valueLabel,
          style: TextStyle(
            fontFamily: _kFont,
            fontSize: 10,
            color: value == null ? const Color(0xFF64748B) : color,
            fontWeight: FontWeight.w800,
          ),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout(maxWidth: slot - 4);
      valuePainter.paint(
        canvas,
        Offset(
          centerX - (valuePainter.width / 2),
          top + plotHeight - height - 16,
        ),
      );

      final name = point.centroCostoNombre.trim().isEmpty
          ? point.centroCostoCodigo
          : point.centroCostoNombre;
      final namePainter = TextPainter(
        text: TextSpan(
          text: name,
          style: const TextStyle(
            fontFamily: _kFont,
            fontSize: 10,
            color: Color(0xFF334155),
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: ui.TextDirection.ltr,
        textAlign: TextAlign.center,
        maxLines: 2,
        ellipsis: '…',
      )..layout(maxWidth: slot - 8);
      namePainter.paint(
        canvas,
        Offset(centerX - (namePainter.width / 2), top + plotHeight + 8),
      );
      final datePainter = TextPainter(
        text: TextSpan(
          text: fmt.format(point.fecha),
          style: const TextStyle(
            fontFamily: _kFont,
            fontSize: 9,
            color: Color(0xFF64748B),
          ),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      datePainter.paint(
        canvas,
        Offset(centerX - (datePainter.width / 2), top + plotHeight + 39),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ComparativoUltimaActaPainter oldDelegate) =>
      oldDelegate.points != points;
}

class _TimelinePoint {
  final String label;
  final double value;
  final String caption;

  const _TimelinePoint({
    required this.label,
    required this.value,
    required this.caption,
  });
}

class _TimelineChartCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<_TimelinePoint> points;

  const _TimelineChartCard({
    required this.title,
    required this.subtitle,
    required this.points,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontFamily: _kFont,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 260,
              width: double.infinity,
              child: points.isEmpty
                  ? const Center(
                      child: Text(
                        'No hay suficientes puntajes para graficar',
                        style: TextStyle(color: Color(0xFF94A3B8)),
                      ),
                    )
                  : CustomPaint(painter: _TimelineChartPainter(points)),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimelineChartPainter extends CustomPainter {
  final List<_TimelinePoint> points;

  const _TimelineChartPainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    const left = 42.0;
    const right = 12.0;
    const top = 16.0;
    const bottom = 32.0;
    final chartWidth = size.width - left - right;
    final chartHeight = size.height - top - bottom;
    if (chartWidth <= 0 || chartHeight <= 0 || points.isEmpty) return;

    final axisPaint = Paint()
      ..color = const Color(0xFFCBD5E1)
      ..strokeWidth = 1;
    final gridPaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..strokeWidth = 1;
    final linePaint = Paint()
      ..color = _kAccent
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    final pointPaint = Paint()..color = _kAccent;

    final textStyle = const TextStyle(fontSize: 11, color: Color(0xFF64748B));
    const gridValues = [0.0, 50.0, 100.0];

    for (final value in gridValues) {
      final y = top + chartHeight - (value / 100 * chartHeight);
      canvas.drawLine(
        Offset(left, y),
        Offset(size.width - right, y),
        gridPaint,
      );
      final painter = TextPainter(
        text: TextSpan(text: '${value.toInt()}%', style: textStyle),
        textDirection: ui.TextDirection.ltr,
      )..layout(maxWidth: left - 6);
      painter.paint(canvas, Offset(0, y - painter.height / 2));
    }

    canvas.drawLine(
      Offset(left, top),
      Offset(left, size.height - bottom),
      axisPaint,
    );
    canvas.drawLine(
      Offset(left, size.height - bottom),
      Offset(size.width - right, size.height - bottom),
      axisPaint,
    );

    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final point = points[i];
      final dx = points.length == 1
          ? left + chartWidth / 2
          : left + (chartWidth / (points.length - 1)) * i;
      final dy = top + chartHeight - (point.value / 100 * chartHeight);
      if (i == 0) {
        path.moveTo(dx, dy);
      } else {
        path.lineTo(dx, dy);
      }
    }
    canvas.drawPath(path, linePaint);

    for (var i = 0; i < points.length; i++) {
      final point = points[i];
      final dx = points.length == 1
          ? left + chartWidth / 2
          : left + (chartWidth / (points.length - 1)) * i;
      final dy = top + chartHeight - (point.value / 100 * chartHeight);
      canvas.drawCircle(Offset(dx, dy), 4, pointPaint);

      final valuePainter = TextPainter(
        text: TextSpan(
          text: '${point.value.toStringAsFixed(1)}%',
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0F172A),
          ),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout(maxWidth: 60);
      valuePainter.paint(canvas, Offset(dx - valuePainter.width / 2, dy - 20));

      final labelPainter = TextPainter(
        text: TextSpan(text: point.label, style: textStyle),
        textDirection: ui.TextDirection.ltr,
      )..layout(maxWidth: 56);
      labelPainter.paint(
        canvas,
        Offset(dx - labelPainter.width / 2, size.height - bottom + 8),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TimelineChartPainter oldDelegate) {
    if (oldDelegate.points.length != points.length) return true;
    for (var i = 0; i < points.length; i++) {
      if (oldDelegate.points[i].label != points[i].label ||
          oldDelegate.points[i].value != points[i].value) {
        return true;
      }
    }
    return false;
  }
}

// Celda de la matriz con color semafórico
class _CeldaPuntaje extends StatelessWidget {
  final InterventoriaItem? item;
  final VoidCallback? onTap;

  const _CeldaPuntaje({this.item, this.onTap});

  @override
  Widget build(BuildContext context) {
    if (item == null || item!.noEvaluado || item!.valor == null) {
      return const Text(
        'NE',
        style: TextStyle(
          fontSize: 11,
          color: Color(0xFF94A3B8),
          fontWeight: FontWeight.w600,
        ),
      );
    }
    final pct = item!.valor!;
    final color = _percentColor(pct);
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '${pct.toStringAsFixed(1)}%',
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    if (onTap == null) return badge;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          badge,
          const SizedBox(width: 2),
          Icon(
            Icons.search_rounded,
            size: 13,
            color: color.withValues(alpha: 0.7),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sheet: registrar acta (scanner + OCR)
// ─────────────────────────────────────────────────────────────────────────────

class _RegistrarActaSheet extends StatefulWidget {
  final String empresaId;
  final String userId;
  final InterventoriaService service;

  /// Si no es null, el Registrador solo puede registrar este centro.
  final String? centroFijoId;

  const _RegistrarActaSheet({
    required this.empresaId,
    required this.userId,
    required this.service,
    this.centroFijoId,
  });

  @override
  State<_RegistrarActaSheet> createState() => _RegistrarActaSheetState();
}

class _RegistrarActaSheetState extends State<_RegistrarActaSheet> {
  CentroCostoRef? _centro;
  DateTime _fecha = DateTime.now();
  String? _tipoActa;
  String? _tiempoComida;
  // Puntajes por sección
  /// Categorías del acta seleccionada. Cada acta tiene las suyas: la regular
  /// sus doce, infraestructura una sola, policía cinco.
  List<InterventoriaCategoria> get _categorias => categoriasDeActa(_tipoActa);

  Map<String, InterventoriaItem> _itemsVacios() => {
    for (final cat in _categorias) cat.key: InterventoriaItem.empty(cat),
  };

  Map<String, GlobalKey> _clavesDeItems() => {
    for (final cat in _categorias) cat.key: GlobalKey(),
  };

  late Map<String, InterventoriaItem> _items = _itemsVacios();
  final _ocrCtrl = TextEditingController();
  final List<_PickedActa> _files = [];
  bool _saving = false;
  bool _extracting = false;

  final _scrollCtrl = ScrollController();
  late Map<String, GlobalKey> _itemKeys = _clavesDeItems();

  void _irAlItem(String key) {
    final ctx = _itemKeys[key]?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      alignment: 0.05,
    );
  }

  @override
  void initState() {
    super.initState();
    if (widget.centroFijoId != null && widget.centroFijoId!.isNotEmpty) {
      _precargarCentroFijo();
    }
  }

  Future<void> _precargarCentroFijo() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('TBL_CENTROS_COSTOS')
          .doc(widget.centroFijoId)
          .get();
      if (doc.exists && mounted) {
        setState(() {
          _centro = CentroCostoRef.fromMap(doc.id, doc.data()!);
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _ocrCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isWeb = MediaQuery.of(context).size.width >= 900;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: isWeb ? 0.9 : 0.97,
        maxChildSize: 0.99,
        minChildSize: 0.5,
        builder: (_, _) => Material(
          color: const Color(0xFFF8FAFC),
          child: Column(
            children: [
              // ── Drag handle ───────────────────────────────────────────
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // ── Header fijo ───────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 10, 6),
                child: Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Registrar acta de interventoría',
                            style: TextStyle(
                              fontFamily: _kFont,
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                            ),
                          ),
                          Text(
                            'Solo puntajes — las observaciones se completan en revisión',
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),

              // ── Contenido (solo puntajes, sin tab de observaciones) ───
              Expanded(child: _buildPuntajesTab(isWeb)),

              // ── Botón guardar (fijo al fondo) ─────────────────────────
              // Deshabilitado (no solo validado al click) si falta el
              // establecimiento, el acta PDF o algún ítem sin puntaje/NE.
              Builder(
                builder: (_) {
                  final faltantes = _itemsIncompletos();
                  final faltaActa = !puedeGenerarActaPdf(
                    _files.map((file) => file.contentType),
                  );
                  final puedeGuardar =
                      !_saving &&
                      !_extracting &&
                      _centro != null &&
                      !faltaActa &&
                      faltantes.isEmpty;
                  return SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                      child: SizedBox(
                        width: double.infinity,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!puedeGuardar && !_saving && _centro != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Text(
                                  _extracting
                                      ? 'Espera a que termine de procesarse el acta'
                                      : faltaActa
                                      ? 'Adjunta el acta PDF obligatoria'
                                      : 'Faltan ${faltantes.length} sección(es) sin puntaje ni NE',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: _kDanger,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: _kAccent,
                              ),
                              onPressed: puedeGuardar ? _save : null,
                              icon: _saving
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.save_rounded),
                              label: Text(
                                _saving ? 'Guardando...' : 'Guardar acta',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCommonHeader(bool isWeb) {
    return Column(
      children: [
        // Si hay centro fijo (Registrador), mostrar solo ese centro como texto
        if (widget.centroFijoId != null && widget.centroFijoId!.isNotEmpty)
          InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Establecimiento / centro de costos',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            child: _centro == null
                ? const SizedBox(
                    height: 18,
                    child: Center(
                      child: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                : Row(
                    children: [
                      const Icon(
                        Icons.location_on_rounded,
                        size: 14,
                        color: _kAccent,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _centro!.nombre,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
          )
        else
          StreamBuilder<List<CentroCostoRef>>(
            stream: widget.service.streamCentrosCosto(widget.empresaId),
            builder: (_, snap) {
              final centros = snap.data ?? [];
              return DropdownButtonFormField<CentroCostoRef>(
                initialValue: _centro,
                decoration: const InputDecoration(
                  labelText: 'Establecimiento / centro de costos',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: _centrosCostoDropdownItems(centros),
                onChanged: (v) => setState(() => _centro = v),
              );
            },
          ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            InkWell(
              onTap: _pickFecha,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFCBD5E1)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.event_rounded,
                      size: 16,
                      color: Color(0xFF64748B),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      DateFormat('dd/MM/yyyy').format(_fecha),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: isWeb ? 180 : double.infinity,
              child: DropdownButtonFormField<String>(
                initialValue: _tipoActa,
                decoration: const InputDecoration(
                  labelText: 'Tipo de acta',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Sin tipo')),
                  ...kTiposActaInterventoria.map(
                    (t) => DropdownMenuItem(
                      value: t,
                      child: Text(etiquetaTipoActa(t)),
                    ),
                  ),
                ],
                onChanged: _onTipoActaChanged,
              ),
            ),
            SizedBox(
              width: isWeb ? 180 : double.infinity,
              child: DropdownButtonFormField<String>(
                initialValue: _tiempoComida,
                decoration: const InputDecoration(
                  labelText: 'Tiempo de comida',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('Sin definir'),
                  ),
                  ...kTiemposComidaInterventoria.map(
                    (t) => DropdownMenuItem(value: t, child: Text(t)),
                  ),
                ],
                onChanged: (v) => setState(() => _tiempoComida = v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _ActaGeneralCard(
          files: _files,
          extracting: _extracting,
          onPickArchivo: _pickArchivo,
          onPickCamera: _pickCamera,
          onPickGallery: _pickGallery,
          onPreview: _showActaPreview,
          onRemove: (file) => setState(() => _files.remove(file)),
        ),
      ],
    );
  }

  // ── Tab: Puntajes por sección ─────────────────────────────────────────────
  Widget _buildPuntajesTab(bool isWeb) {
    return Scrollbar(
      controller: _scrollCtrl,
      thumbVisibility: isWeb,
      trackVisibility: isWeb,
      child: ListView(
        controller: _scrollCtrl,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(14, 12, 22, 120),
        children: [
          _buildCommonHeader(isWeb),
          const SizedBox(height: 12),
          if (_tipoActa == 'INFRAESTRUCTURA')
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _kWarning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _kWarning.withValues(alpha: 0.5)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: _kWarning, size: 16),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'INFRAESTRUCTURA: solo aplica sección 2. '
                      'Las demás secciones márquelas como NE.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          // ── Índice navegable: salta directo al numeral sin scroll largo ──
          SizedBox(
            height: 64,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _categorias.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (_, i) {
                final cat = _categorias[i];
                final item = _items[cat.key] ?? InterventoriaItem.empty(cat);
                final color = item.noEvaluado
                    ? const Color(0xFF94A3B8)
                    : item.valor != null
                    ? _percentColor(item.valor!)
                    : const Color(0xFFCBD5E1);
                return InkWell(
                  onTap: () => _irAlItem(cat.key),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 78,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      border: Border.all(color: color.withValues(alpha: 0.6)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${i + 1}',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                            color: color,
                          ),
                        ),
                        Text(
                          cat.label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 9,
                            color: color,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          ..._categorias.map((cat) {
            final item = _items[cat.key] ?? InterventoriaItem.empty(cat);
            Widget card;
            if (cat.key == 'conceptoSanitario') {
              card = _buildConceptoSanitarioCard(item);
            } else if (cat.key == 'horario') {
              card = _buildHorarioCard(item);
            } else {
              card = _ItemPuntajeRow(
                item: item,
                tipoActa: _tipoActa,
                ocrText: _ocrCtrl.text,
                onPickOcrSnippets: () => _pickOcrSnippets(
                  title: 'Agregar observaciones a ${cat.label}',
                ),
                onChanged: (updated) =>
                    setState(() => _items[cat.key] = updated),
                showObservaciones: false, // Fase 1: solo puntaje
              );
            }
            return KeyedSubtree(key: _itemKeys[cat.key], child: card);
          }),
        ],
      ),
    );
  }

  void _updateItem(String itemKey, InterventoriaItem updated) {
    setState(() => _items[itemKey] = updated);
  }

  Widget _buildConceptoSanitarioCard(InterventoriaItem item) {
    final fechaConcepto = item.meta['fechaConceptoSanitario'] as Timestamp?;
    final conceptoEmitido = item.meta['conceptoEmitido']?.toString();
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Concepto Sanitario',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, cc) {
                final esMovil = cc.maxWidth < 520;
                final fechaPicker = InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: fechaConcepto?.toDate() ?? _fecha,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2035),
                    );
                    if (picked == null) return;
                    _updateItem(
                      item.key,
                      item.copyWith(
                        meta: {
                          ...item.meta,
                          'fechaConceptoSanitario': Timestamp.fromDate(picked),
                        },
                      ),
                    );
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Fecha del concepto sanitario',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    child: Text(
                      fechaConcepto == null
                          ? 'Seleccionar fecha'
                          : DateFormat(
                              'dd/MM/yyyy',
                            ).format(fechaConcepto.toDate()),
                    ),
                  ),
                );
                final conceptoDrop = DropdownButtonFormField<String>(
                  initialValue: conceptoEmitido,
                  decoration: const InputDecoration(
                    labelText: 'Concepto emitido',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'favorable',
                      child: Text('Favorable'),
                    ),
                    DropdownMenuItem(
                      value: 'favorable_con_requerimientos',
                      child: Text('Favorable con requerimientos'),
                    ),
                    DropdownMenuItem(
                      value: 'desfavorable',
                      child: Text('Desfavorable'),
                    ),
                  ],
                  onChanged: (value) => _updateItem(
                    item.key,
                    item.copyWith(
                      meta: {...item.meta, 'conceptoEmitido': value ?? ''},
                    ),
                  ),
                );

                if (esMovil) {
                  return Column(
                    children: [
                      fechaPicker,
                      const SizedBox(height: 10),
                      conceptoDrop,
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: fechaPicker),
                    const SizedBox(width: 10),
                    Expanded(child: conceptoDrop),
                  ],
                );
              },
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                GestureDetector(
                  onTap: () => _updateItem(
                    item.key,
                    item.copyWith(
                      noEvaluado: !item.noEvaluado,
                      clearValor: !item.noEvaluado,
                    ),
                  ),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: item.noEvaluado
                          ? const Color(0xFF64748B)
                          : Colors.transparent,
                      border: Border.all(
                        color: item.noEvaluado
                            ? const Color(0xFF64748B)
                            : const Color(0xFFCBD5E1),
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'NE',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: item.noEvaluado
                            ? Colors.white
                            : const Color(0xFF94A3B8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _PorcentajeInput(
                    enabled: !item.noEvaluado,
                    value: item.valor,
                    color: item.noEvaluado
                        ? const Color(0xFF94A3B8)
                        : _percentColor(item.valor ?? 0),
                    onChanged: (parsed) =>
                        _updateItem(item.key, item.copyWith(valor: parsed)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHorarioCard(InterventoriaItem item) {
    final horaEntrega = item.meta['horaEntregaServicio']?.toString() ?? '';
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '1. Horario',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, hc) {
                final esMovil = hc.maxWidth < 520;
                final tiempoField = InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Tiempo de comida',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  child: Text(_tiempoComida ?? 'Sin definir'),
                );
                final horaPicker = InkWell(
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: _parseTimeOfDay(horaEntrega),
                    );
                    if (picked == null) return;
                    final hh = picked.hour.toString().padLeft(2, '0');
                    final mm = picked.minute.toString().padLeft(2, '0');
                    _updateItem(
                      item.key,
                      item.copyWith(
                        meta: {
                          ...item.meta,
                          'horaEntregaServicio': '$hh:$mm',
                          'tiempoComida': _tiempoComida ?? '',
                        },
                      ),
                    );
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Hora de entrega del servicio',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    child: Text(
                      horaEntrega.isEmpty ? 'Seleccionar hora' : horaEntrega,
                    ),
                  ),
                );

                if (esMovil) {
                  return Column(
                    children: [
                      tiempoField,
                      const SizedBox(height: 10),
                      horaPicker,
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: tiempoField),
                    const SizedBox(width: 10),
                    Expanded(child: horaPicker),
                  ],
                );
              },
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('100% Cumple'),
                  selected: item.valor == 100 && !item.noEvaluado,
                  onSelected: (_) => _updateItem(
                    item.key,
                    item.copyWith(valor: 100, noEvaluado: false),
                  ),
                ),
                ChoiceChip(
                  label: const Text('0% No cumple'),
                  selected: item.valor == 0 && !item.noEvaluado,
                  onSelected: (_) => _updateItem(
                    item.key,
                    item.copyWith(valor: 0, noEvaluado: false),
                  ),
                ),
                ChoiceChip(
                  label: const Text('NE'),
                  selected: item.noEvaluado,
                  onSelected: (_) => _updateItem(
                    item.key,
                    item.copyWith(
                      noEvaluado: !item.noEvaluado,
                      clearValor: !item.noEvaluado,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  TimeOfDay _parseTimeOfDay(String value) {
    final parts = value.split(':');
    if (parts.length != 2) return TimeOfDay.fromDateTime(DateTime.now());
    final hour = int.tryParse(parts[0]) ?? DateTime.now().hour;
    final minute = int.tryParse(parts[1]) ?? DateTime.now().minute;
    return TimeOfDay(hour: hour, minute: minute);
  }

  /// Al cambiar tipo de acta, auto-marca NE según las reglas:
  /// INFRAESTRUCTURA → todas las secciones como NE, excepto la 2.
  /// Cualquier otro tipo → deshace el NE forzado.
  /// Importante: nunca se borra un puntaje ya escrito (`clearValor`) al
  /// alternar el tipo — eso dejaba secciones vacías para siempre e
  /// impedía guardar el acta al volver de Infraestructura a Regular.
  /// Cambiar de acta cambia QUÉ se evalúa, no solo cómo se ve.
  ///
  /// Antes, INFRAESTRUCTURA se resolvía marcando como "no evaluado" todo lo que
  /// no fuera instalaciones físicas del acta regular. Eso hacía que quien
  /// registraba un acta de infraestructura calificara los 17 aspectos de la
  /// regular en vez de los 28 suyos. Ahora cada acta trae sus propias
  /// secciones y las tarjetas se rehacen.
  void _onTipoActaChanged(String? newTipo) {
    final antes = _categorias.map((c) => c.key).join('|');
    setState(() {
      _tipoActa = newTipo;
      final ahora = _categorias.map((c) => c.key).join('|');
      if (antes != ahora) {
        // Los puntajes de la otra acta no corresponden a nada aquí; dejarlos
        // pegados a claves que ya no existen los guardaría en silencio.
        _items = _itemsVacios();
        _itemKeys = _clavesDeItems();
      }
    });
  }

  /// Nombre de archivo con el formato {centro}_{fecha}_interventoria.{ext}
  String _nombreActa(String ext) {
    final centro = (_centro?.nombre ?? 'acta')
        .replaceAll(RegExp(r'[^\wáéíóúÁÉÍÓÚñÑ ]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '_');
    final fechaStr = DateFormat('yyyyMMdd').format(_fecha);
    return '${centro}_${fechaStr}_interventoria.$ext';
  }

  Future<void> _pickFecha() async {
    final p = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (p != null) setState(() => _fecha = p);
  }

  Future<void> _pickArchivo() async {
    final r = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg'],
    );
    if (r == null) return;

    final nuevos = <_PickedActa>[];
    final pdfBytes = <Uint8List>[]; // collect PDFs for text extraction

    for (var i = 0; i < r.files.length; i++) {
      final f = r.files[i];
      if (f.bytes == null) continue;
      final ext = (f.extension ?? 'pdf').toLowerCase();
      final base = _nombreActa(ext);
      final sufijo = (_files.length + i) > 0 ? '_${_files.length + i + 1}' : '';
      final nombre = base.replaceAll(RegExp(r'(\.\w+)$'), '$sufijo.$ext');
      // Copiar bytes inmediatamente: en web el ArrayBuffer de JS puede
      // quedar detached entre awaits si se guarda la referencia original.
      final safeBytes = Uint8List.fromList(f.bytes!);
      final safeBase64 = base64Encode(safeBytes);
      nuevos.add(
        _PickedActa(
          bytes: safeBytes,
          base64Data: safeBase64,
          nombre: nombre,
          contentType: ext == 'pdf'
              ? 'application/pdf'
              : ext == 'png'
              ? 'image/png'
              : 'image/jpeg',
          origen: 'web_upload',
        ),
      );
      if (ext == 'pdf') pdfBytes.add(safeBytes);
    }
    setState(() {
      _files.addAll(nuevos);
      if (pdfBytes.isNotEmpty) _extracting = true;
    });

    // Auto-extract text from PDFs
    if (pdfBytes.isNotEmpty) {
      final buffer = StringBuffer();
      for (final bytes in pdfBytes) {
        final text = await extractPdfTextFromBytes(bytes);
        if (text.isNotEmpty) buffer.writeln(text);
      }
      final extracted = buffer.toString().trim();
      if (mounted) {
        setState(() {
          _extracting = false;
          if (extracted.isNotEmpty) {
            // Append to existing text (user may have typed something)
            if (_ocrCtrl.text.isNotEmpty) {
              _ocrCtrl.text = '${_ocrCtrl.text}\n\n$extracted';
            } else {
              _ocrCtrl.text = extracted;
            }
          }
        });
        if (extracted.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'No se pudo extraer texto del PDF (puede ser escaneado). '
                'Pega el texto manualmente en el campo de abajo.',
              ),
              duration: Duration(seconds: 5),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Texto extraído del PDF (${extracted.length} caracteres). '
                'Ya puedes usarlo en puntajes, observaciones o conclusiones.',
              ),
              backgroundColor: _kOk,
            ),
          );
        }
      }
    }
  }

  /// Escaneo multi-página tipo CamScanner: cámara → OCR → ¿otra página? → acumular.
  Future<void> _pickCamera() async {
    final buffer = StringBuffer();
    if (_ocrCtrl.text.trim().isNotEmpty) buffer.write(_ocrCtrl.text.trim());
    int pageCount = 0;

    while (true) {
      final img = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 92,
      );
      if (img == null) break;

      // Guardar archivo para adjunto
      final bytes = await img.readAsBytes();
      final idx = _files.length + pageCount;
      final sufijo = idx > 0 ? '_${idx + 1}' : '';
      final nombre = _nombreActa(
        'jpg',
      ).replaceAll(RegExp(r'(\.\w+)$'), '$sufijo.jpg');
      setState(() {
        _files.add(
          _PickedActa(
            bytes: bytes,
            nombre: nombre,
            contentType: 'image/jpeg',
            origen: 'mobile_camera',
          ),
        );
        _extracting = true;
      });

      // OCR con ML Kit
      final text = await recognizeTextFromXFile(img);
      pageCount++;
      if (text.isNotEmpty) {
        if (buffer.isNotEmpty) buffer.write('\n\n');
        buffer.write(text);
      }
      if (mounted) {
        setState(() {
          _extracting = false;
          _ocrCtrl.text = buffer.toString();
        });
      }
      if (!mounted) break;

      // Preguntar si hay más páginas
      final more = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: Text('Página $pageCount escaneada'),
          content: Text(
            text.isEmpty
                ? 'No se detectó texto en esta imagen.\n¿Desea escanear otra página?'
                : '✓ ${text.length} caracteres detectados.\n¿Agregar otra página?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Listo'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Otra página'),
            ),
          ],
        ),
      );
      if (more != true) break;
    }

    if (pageCount > 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$pageCount página(s) escaneada(s). '
            'Ya puedes usar el texto extraído en el formulario.',
          ),
          backgroundColor: _kOk,
        ),
      );
    }
  }

  /// Galería: selecciona imagen → OCR → agrega al texto existente.
  Future<void> _pickGallery() async {
    final img = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 92,
    );
    if (img == null) return;
    final bytes = await img.readAsBytes();
    final nombre = _nombreActa('jpg');
    setState(() {
      _files.add(
        _PickedActa(
          bytes: bytes,
          nombre: nombre,
          contentType: 'image/jpeg',
          origen: 'mobile_gallery',
        ),
      );
      _extracting = true;
    });
    final text = await recognizeTextFromXFile(img);
    if (mounted) {
      setState(() {
        _extracting = false;
        if (text.isNotEmpty) {
          _ocrCtrl.text = _ocrCtrl.text.isEmpty
              ? text
              : '${_ocrCtrl.text}\n\n$text';
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            text.isEmpty
                ? 'No se detectó texto en la imagen'
                : '✓ ${text.length} caracteres detectados.',
          ),
          backgroundColor: text.isEmpty ? null : _kOk,
        ),
      );
    }
  }

  bool _isImageActa(_PickedActa file) =>
      file.contentType == 'image/jpeg' || file.contentType == 'image/png';

  Future<_PickedActa?> _buildGeneralActaPdf() async {
    final imageFiles = _files.where(_isImageActa).toList();
    if (imageFiles.isEmpty) return null;

    final pdf = pw.Document();
    for (final file in imageFiles) {
      final image = pw.MemoryImage(file.bytes);
      pdf.addPage(
        pw.Page(
          build: (_) =>
              pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
        ),
      );
    }

    final bytes = await pdf.save();
    final baseName = _nombreActa(
      'pdf',
    ).replaceFirst('_interventoria.pdf', '_interventoria_general.pdf');
    return _PickedActa(
      bytes: Uint8List.fromList(bytes),
      nombre: baseName,
      contentType: 'application/pdf',
      origen: 'generated_pdf',
    );
  }

  Map<String, InterventoriaItem> _itemsParaGuardar() {
    // Fase 1: solo puntajes, sin observaciones (se completan en Fase 2)
    final seeded = Map<String, InterventoriaItem>.from(_items);
    return seeded.map((key, item) {
      final filteredNotes = item.observaciones.where((note) {
        final hasText = note.texto.trim().isNotEmpty;
        final hasAspect = note.aspecto.trim().isNotEmpty;
        return hasText || !hasAspect;
      }).toList();
      return MapEntry(
        key,
        item.copyWith(
          observaciones: filteredNotes,
          observacion: filteredNotes
              .map((n) {
                final aspecto = n.aspecto.trim();
                final texto = n.texto.trim();
                if (aspecto.isEmpty) return texto;
                if (texto.isEmpty) return '';
                return '$aspecto\n$texto';
              })
              .where((t) => t.trim().isNotEmpty)
              .join('\n\n'),
        ),
      );
    });
  }

  List<InterventoriaHallazgo> _buildHallazgosDesdeComentarios(
    String visitaId,
    Map<String, InterventoriaItem> items,
  ) {
    if (_centro == null) return const [];
    final hallazgos = <InterventoriaHallazgo>[];
    for (
      var categoryIndex = 0;
      categoryIndex < _categorias.length;
      categoryIndex++
    ) {
      final cat = _categorias[categoryIndex];
      final item = items[cat.key];
      if (item == null) continue;
      final notes = item.observaciones
          .where(
            (note) =>
                note.texto.trim().isNotEmpty || note.aspecto.trim().isNotEmpty,
          )
          .toList();
      for (var noteIndex = 0; noteIndex < notes.length; noteIndex++) {
        final note = notes[noteIndex];
        final aspecto = note.aspecto.trim();
        final texto = note.texto.trim();
        if (texto.isEmpty && aspecto.isEmpty) continue;
        hallazgos.add(
          InterventoriaHallazgo(
            empresaId: widget.empresaId,
            visitaId: visitaId,
            centroCostoId: _centro!.centroId,
            centroCostoNombre: _centro!.nombre,
            tipoActa: _tipoActa,
            numeroHallazgo: '${categoryIndex + 1}.${noteIndex + 1}',
            descripcion: aspecto.isEmpty ? cat.label : aspecto,
            fechaHallazgo: Timestamp.fromDate(_fecha),
            observaciones: texto,
            puntajeSeccion: item.noEvaluado
                ? 100.0
                : (item.valor ?? 0).toDouble(),
            fuente: note.fuente,
            createdAt: Timestamp.now(),
          ),
        );
      }
    }

    // Fase 1: no hay obs. generales ni conclusiones — se agregan en Fase 2
    return hallazgos;
  }

  Future<void> _showActaPreview(_PickedActa file) async {
    await showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 760),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        file.nombre,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontFamily: _kFont,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: _isImageActa(file)
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: InteractiveViewer(
                            child: Image.memory(
                              file.bytes,
                              fit: BoxFit.contain,
                              gaplessPlayback: true,
                            ),
                          ),
                        )
                      : Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(28),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.picture_as_pdf_rounded,
                                size: 54,
                                color: _kAccent,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                '${(file.bytes.length / 1024).toStringAsFixed(1)} KB',
                                style: const TextStyle(
                                  color: Color(0xFF64748B),
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Vista previa de PDF disponible al abrirlo despues de guardar.',
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<String> _ocrCandidateLines() {
    final seen = <String>{};
    return _ocrCtrl.text
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.trim())
        .where((line) => line.length >= 8)
        .where((line) => seen.add(line.toLowerCase()))
        .take(80)
        .toList();
  }

  Future<List<String>> _pickOcrSnippets({required String title}) async {
    final candidates = _ocrCandidateLines();
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay texto OCR disponible para seleccionar.'),
        ),
      );
      return const [];
    }

    final selected = <String>{};
    final result = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      // PointerInterceptor evita que el iframe del PDF robe los clicks del sheet
      builder: (ctx) => PointerInterceptor(
        child: StatefulBuilder(
          builder: (ctx, setSheetState) {
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.82,
              maxChildSize: 0.94,
              minChildSize: 0.4,
              builder: (_, controller) => Material(
                color: const Color(0xFFF8FAFC),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: const TextStyle(
                                fontFamily: _kFont,
                                fontWeight: FontWeight.w900,
                                fontSize: 17,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () =>
                                Navigator.pop(ctx, const <String>[]),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        controller: controller,
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        itemCount: candidates.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 6),
                        itemBuilder: (_, i) {
                          final text = candidates[i];
                          final checked = selected.contains(text);
                          return CheckboxListTile(
                            value: checked,
                            dense: true,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: Text(text),
                            tileColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: const BorderSide(color: Color(0xFFE2E8F0)),
                            ),
                            onChanged: (value) {
                              setSheetState(() {
                                if (value == true) {
                                  selected.add(text);
                                } else {
                                  selected.remove(text);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: selected.isEmpty
                                ? null
                                : () => Navigator.pop(ctx, selected.toList()),
                            icon: const Icon(Icons.add_rounded),
                            label: Text(
                              selected.isEmpty
                                  ? 'Selecciona una o varias'
                                  : 'Agregar ${selected.length}',
                            ),
                          ),
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
    );
    return result ?? const [];
  }

  List<String> _itemsIncompletos() {
    final faltantes = <String>[];
    for (final cat in _categorias) {
      final item = _items[cat.key] ?? InterventoriaItem.empty(cat);
      if (!item.noEvaluado && item.valor == null) {
        faltantes.add(item.label);
      }
    }
    return faltantes;
  }

  Future<void> _save() async {
    if (_centro == null) return;
    if (_extracting) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Espera a que termine de procesarse el acta.'),
        ),
      );
      return;
    }
    if (!puedeGenerarActaPdf(_files.map((file) => file.contentType))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFB91C1C),
          content: Text('Debes adjuntar el acta PDF antes de guardar.'),
        ),
      );
      return;
    }
    final faltantes = _itemsIncompletos();
    if (faltantes.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFB91C1C),
          content: Text(
            'Faltan por llenar o marcar NE: ${faltantes.join(', ')}',
          ),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      // 1. Preparar el PDF obligatorio. Las imágenes escaneadas se convierten
      // en un PDF general antes de que exista la visita en Firestore.
      final itemsParaGuardar = _itemsParaGuardar();
      final pctGeneral = calcularPorcentajeGeneral(itemsParaGuardar);
      final filesToUpload = <_PickedActa>[];
      final generatedPdf = await _buildGeneralActaPdf();
      if (generatedPdf != null) filesToUpload.add(generatedPdf);
      filesToUpload.addAll(_files);
      if (!filesToUpload.any(
        (file) => file.contentType.toLowerCase() == 'application/pdf',
      )) {
        throw StateError('No fue posible generar el acta PDF obligatoria.');
      }

      // 2. Reservar el id y subir los archivos. Si la carga falla, no queda
      // una visita registrada sin el PDF que la respalda.
      final visitaId = widget.service.nuevoVisitaId();
      final adjuntos = <InterventoriaAdjunto>[];
      for (final f in filesToUpload) {
        adjuntos.add(
          f.base64Data != null
              ? await widget.service.subirActaBase64(
                  base64Data: f.base64Data!,
                  empresaId: widget.empresaId,
                  visitaId: visitaId,
                  nombre: f.nombre,
                  contentType: f.contentType,
                  origen: f.origen,
                )
              : await widget.service.subirActaBytes(
                  bytes: f.bytes,
                  empresaId: widget.empresaId,
                  visitaId: visitaId,
                  nombre: f.nombre,
                  contentType: f.contentType,
                  origen: f.origen,
                ),
        );
      }
      final actaPdf = adjuntos.firstWhere(
        (adjunto) => adjunto.contentType.toLowerCase() == 'application/pdf',
      );

      // 3. Persistir la visita únicamente cuando el PDF ya existe.
      final visita = InterventoriaVisita(
        id: visitaId,
        empresaId: widget.empresaId,
        centroCostoId: _centro!.centroId,
        centroCostoCodigo: _centro!.codigo,
        centroCostoNombre: _centro!.nombre,
        fechaVisita: Timestamp.fromDate(_fecha),
        fechaRegistro: Timestamp.now(),
        creadoPor: widget.userId,
        tipoActa: _tipoActa,
        tiempoComida: _tiempoComida,
        porcentajeGeneral: pctGeneral,
        items: itemsParaGuardar,
        adjuntos: adjuntos,
        actaOriginalUrl: actaPdf.url,
        observaciones: '', // se completa en Fase 2
        ocrTextoExtraido: _ocrCtrl.text.trim(),
        ocrDatosDetectados: const {},
        ocrRevisado: false,
        faseActa: 'puntajes', // Fase 1 completa — pendiente de revisión
        createdAt: Timestamp.now(),
      );
      await widget.service.guardarVisita(visita);

      final hallazgos = _buildHallazgosDesdeComentarios(
        visitaId,
        itemsParaGuardar,
      );
      if (hallazgos.isNotEmpty) {
        await widget.service.guardarHallazgos(hallazgos);
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: _kOk,
            content: Text(
              'Acta guardada — ${pctGeneral.toStringAsFixed(1)}%'
              '${hallazgos.isNotEmpty ? ' · ${hallazgos.length} comentarios enlazados' : ''}',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al guardar: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

List<DropdownMenuItem<CentroCostoRef>> _centrosCostoDropdownItems(
  Iterable<CentroCostoRef> centros,
) => [
  for (final grupo in agruparCentrosCosto(centros)) ...[
    DropdownMenuItem<CentroCostoRef>(
      enabled: false,
      child: Text(
        grupo.label.toUpperCase(),
        style: const TextStyle(
          color: Color(0xFF0F766E),
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        ),
      ),
    ),
    ...grupo.centros.map(
      (centro) => DropdownMenuItem<CentroCostoRef>(
        value: centro,
        child: Text(centro.nombre, overflow: TextOverflow.ellipsis),
      ),
    ),
  ],
];

/// Selector compartido por Hallazgos, Subsanaciones y Análisis. Toma la
/// clasificación G1/G9 del catálogo y conserva establecimientos históricos
/// que ya no aparezcan allí bajo "Sin grupo".
class _CentroCostoFilterDropdown extends StatelessWidget {
  final InterventoriaService service;
  final String empresaId;
  final Map<String, String> fallbackCentros;
  final String value;
  final ValueChanged<String>? onChanged;

  const _CentroCostoFilterDropdown({
    required this.service,
    required this.empresaId,
    required this.fallbackCentros,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<CentroCostoRef>>(
      stream: service.streamCentrosCosto(empresaId),
      builder: (context, snapshot) {
        final centrosPorId = <String, CentroCostoRef>{
          for (final centro in snapshot.data ?? const <CentroCostoRef>[])
            centro.centroId: centro,
        };
        // Un establecimiento deshabilitado no vuelve a llenar el selector por
        // el solo hecho de existir en el histórico. Se conserva únicamente si
        // ya estaba seleccionado para que el formulario no quede inválido.
        if (value.isNotEmpty &&
            !centrosPorId.containsKey(value) &&
            fallbackCentros.containsKey(value)) {
          centrosPorId[value] = CentroCostoRef(
            centroId: value,
            empresaId: empresaId,
            codigo: '',
            nombre: fallbackCentros[value]!,
          );
        }
        final grupos = agruparCentrosCosto(centrosPorId.values);
        return DropdownButtonFormField<String>(
          key: ValueKey('$value-${centrosPorId.length}'),
          initialValue: value,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Establecimiento',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: [
            const DropdownMenuItem(value: '', child: Text('Todos')),
            for (final grupo in grupos) ...[
              DropdownMenuItem<String>(
                enabled: false,
                child: Text(
                  grupo.label.toUpperCase(),
                  style: const TextStyle(
                    color: Color(0xFF0F766E),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              ...grupo.centros.map(
                (centro) => DropdownMenuItem<String>(
                  value: centro.centroId,
                  child: Text(centro.nombre, overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
          ],
          onChanged: onChanged == null
              ? null
              : (selected) => onChanged!(selected ?? ''),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Filtros de hallazgos
// ─────────────────────────────────────────────────────────────────────────────

class _FiltrosHallazgos extends StatelessWidget {
  final Map<String, String> centros;
  final InterventoriaService service;
  final String empresaId;

  /// dptos: map de nombre→nombre, derivado de hallazgos reales de la empresa.
  final Map<String, String> dptos;
  final String centroFiltro;
  final String estadoFiltro;
  final String dptoFiltro;
  final DateTime? fechaDesde;
  final DateTime? fechaHasta;

  /// Si true, oculta el selector de establecimiento (Registrador ve solo el suyo).
  final bool ocultarFiltroCentro;
  final ValueChanged<String>? onCentroChanged;
  final ValueChanged<String> onEstadoChanged;
  final ValueChanged<String> onDptoChanged;
  final ValueChanged<DateTime?> onFechaDesdeChanged;
  final ValueChanged<DateTime?> onFechaHastaChanged;

  const _FiltrosHallazgos({
    required this.centros,
    required this.service,
    required this.empresaId,
    required this.dptos,
    required this.centroFiltro,
    required this.estadoFiltro,
    required this.dptoFiltro,
    this.fechaDesde,
    this.fechaHasta,
    this.ocultarFiltroCentro = false,
    this.onCentroChanged,
    required this.onEstadoChanged,
    required this.onDptoChanged,
    required this.onFechaDesdeChanged,
    required this.onFechaHastaChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isWeb = MediaQuery.of(context).size.width >= 900;
    final dateRow = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _FechaTile(
          label: 'Desde',
          fecha: fechaDesde,
          onChanged: onFechaDesdeChanged,
        ),
        _FechaTile(
          label: 'Hasta',
          fecha: fechaHasta,
          onChanged: onFechaHastaChanged,
        ),
        if (fechaDesde != null || fechaHasta != null)
          TextButton.icon(
            onPressed: () {
              onFechaDesdeChanged(null);
              onFechaHastaChanged(null);
            },
            icon: const Icon(Icons.clear_rounded, size: 15),
            label: const Text('Limpiar fechas', style: TextStyle(fontSize: 13)),
          ),
      ],
    );

    if (isWeb) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (!ocultarFiltroCentro) ...[
                Expanded(child: _centroDropdown()),
                const SizedBox(width: 12),
              ],
              Expanded(child: _estadoDropdown()),
              const SizedBox(width: 12),
              Expanded(child: _dptoDropdown()),
            ],
          ),
          const SizedBox(height: 10),
          dateRow,
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!ocultarFiltroCentro) ...[
          _centroDropdown(),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            Expanded(child: _estadoDropdown()),
            const SizedBox(width: 8),
            Expanded(child: _dptoDropdown()),
          ],
        ),
        const SizedBox(height: 8),
        dateRow,
      ],
    );
  }

  Widget _centroDropdown() => _CentroCostoFilterDropdown(
    service: service,
    empresaId: empresaId,
    fallbackCentros: centros,
    value: centroFiltro,
    onChanged: onCentroChanged,
  );

  Widget _estadoDropdown() => DropdownButtonFormField<String>(
    key: ValueKey(estadoFiltro),
    initialValue: estadoFiltro,
    decoration: const InputDecoration(
      labelText: 'Estado',
      border: OutlineInputBorder(),
      isDense: true,
    ),
    items: const [
      DropdownMenuItem(value: '', child: Text('Todos')),
      DropdownMenuItem(value: 'activo', child: Text('Activo')),
      DropdownMenuItem(value: 'subsanado', child: Text('Subsanado')),
    ],
    onChanged: (v) => onEstadoChanged(v ?? ''),
  );

  Widget _dptoDropdown() {
    final sorted = dptos.keys.toList()..sort();
    return DropdownButtonFormField<String>(
      key: ValueKey(dptoFiltro),
      initialValue: dptos.containsKey(dptoFiltro) || dptoFiltro.isEmpty
          ? dptoFiltro
          : null,
      decoration: const InputDecoration(
        labelText: 'Departamento',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      items: [
        const DropdownMenuItem(value: '', child: Text('Todos')),
        ...sorted.map((d) => DropdownMenuItem(value: d, child: Text(d))),
      ],
      onChanged: (v) => onDptoChanged(v ?? ''),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers / widgets pequeños
// ─────────────────────────────────────────────────────────────────────────────

/// Quién debe subsanar el hallazgo, según la matriz de numerales del acta.
///
/// Cuando no hay nombre distingue dos casos que se resuelven distinto:
/// el numeral no se pudo identificar (toca asignar a mano) o sí se identificó
/// pero la empresa no tiene a nadie con ese cargo (toca crear/corregir el
/// cargo en Talento Humano).
class _ResponsableHallazgoCell extends StatelessWidget {
  final InterventoriaHallazgo hallazgo;
  const _ResponsableHallazgoCell({required this.hallazgo});

  @override
  Widget build(BuildContext context) {
    if (hallazgo.responsableNombre.isEmpty &&
        hallazgo.dptoEncargado.trim().isNotEmpty) {
      // Asignado con el flujo anterior: responde un área, no una persona.
      return Text(
        'Área: ${hallazgo.dptoEncargado}',
        style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
      );
    }
    if (hallazgo.responsableNombre.isEmpty) {
      final sinNumeral = hallazgo.numeralParaMatriz.isEmpty;
      return Tooltip(
        message: sinNumeral
            ? 'No se pudo determinar el numeral del acta: asígnalo a mano.'
            : 'Numeral ${hallazgo.numeralParaMatriz}: nadie en la empresa '
                  'tiene el cargo que responde por él.',
        child: Text(
          sinNumeral ? 'Asignación manual' : 'Sin titular',
          style: const TextStyle(fontSize: 11, color: Color(0xFFB45309)),
        ),
      );
    }
    return SizedBox(
      width: 150,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            hallazgo.responsableNombre,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          if (hallazgo.cargoResponsable.isNotEmpty)
            Text(
              hallazgo.cargoResponsable,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
            ),
        ],
      ),
    );
  }
}

/// Fecha límite de subsanación, en rojo cuando ya venció y sigue sin subsanar.
class _VenceHallazgoCell extends StatelessWidget {
  final InterventoriaHallazgo hallazgo;
  const _VenceHallazgoCell({required this.hallazgo});

  @override
  Widget build(BuildContext context) {
    final limite = hallazgo.fechaLimite?.toDate();
    if (limite == null) {
      return const Text('—', style: TextStyle(fontSize: 12));
    }
    final vencido = !hallazgo.isSubsanado && limite.isBefore(DateTime.now());
    return Text(
      DateFormat('dd/MM/yy').format(limite),
      style: TextStyle(
        fontSize: 12,
        color: vencido ? const Color(0xFFDC2626) : null,
        fontWeight: vencido ? FontWeight.w800 : FontWeight.normal,
      ),
    );
  }
}

class _EstadoChip extends StatelessWidget {
  final bool isSubsanado;
  final bool isPendiente;

  const _EstadoChip({required this.isSubsanado, this.isPendiente = false});

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String label;
    if (isPendiente) {
      color = Colors.amber.shade700;
      label = 'Pend. aprobación';
    } else if (isSubsanado) {
      color = _kOk;
      label = 'Subsanado';
    } else {
      color = _kDanger;
      label = 'Activo';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Adjuntos subidos en la tarea asociada — se muestran en el hallazgo
// ─────────────────────────────────────────────────────────────────────────────
/// Muestra el estado actual de la tarea vinculada y sus adjuntos/evidencias.
/// Además, auto-sincroniza el estado del hallazgo cuando la tarea es aprobada.
class _AdjuntosDeTarea extends StatefulWidget {
  final String tareaId;
  final String hallazgoId;
  final String hallazgoEstado;
  final InterventoriaService? service;

  const _AdjuntosDeTarea({
    required this.tareaId,
    this.hallazgoId = '',
    this.hallazgoEstado = '',
    this.service,
  });

  @override
  State<_AdjuntosDeTarea> createState() => _AdjuntosDeTareaState();
}

class _AdjuntosDeTareaState extends State<_AdjuntosDeTarea> {
  // Estado de la tarea que vimos por última vez → evita escrituras duplicadas
  String _lastSyncedEstado = '';

  static IconData _iconForMime(String mime) {
    if (mime.startsWith('image/')) return Icons.image_rounded;
    if (mime.contains('pdf')) return Icons.picture_as_pdf_rounded;
    if (mime.contains('zip') || mime.contains('rar')) {
      return Icons.folder_zip_rounded;
    }
    if (mime.contains('word') || mime.contains('document')) {
      return Icons.description_rounded;
    }
    return Icons.attach_file_rounded;
  }

  static Color _colorForMime(String mime) {
    if (mime.startsWith('image/')) return const Color(0xFF0EA5E9);
    if (mime.contains('pdf')) return const Color(0xFFEF4444);
    if (mime.contains('zip')) return const Color(0xFFF59E0B);
    if (mime.contains('word') || mime.contains('document')) {
      return const Color(0xFF3B82F6);
    }
    return const Color(0xFF64748B);
  }

  void _maybeSyncEstado(Map<String, dynamic> tareaData) {
    final svc = widget.service;
    if (svc == null || widget.hallazgoId.isEmpty) return;
    if (widget.hallazgoEstado != 'activo') {
      return; // solo si el hallazgo está activo
    }

    final tareaEstado = (tareaData['estado'] ?? tareaData['status'] ?? '')
        .toString()
        .toLowerCase();
    final solEstado = (tareaData['solicitud_finalizacion_estado'] ?? '')
        .toString();

    // Clave de sincronización para evitar llamadas repetidas
    final syncKey = '$tareaEstado|$solEstado';
    if (_lastSyncedEstado == syncKey) return;
    _lastSyncedEstado = syncKey;

    // Solo sincronizar si hay condición de aprobación
    final debeSync =
        tareaEstado == 'por_aprobar' ||
        (tareaEstado == 'finalizado' && solEstado == 'aprobado');
    if (!debeSync) return;

    svc.sincronizarEstadoDesdeTask(
      hallazgoId: widget.hallazgoId,
      tareaEstado: tareaEstado,
      solicitudFinalizacionEstado: solEstado,
    );
  }

  /// Devuelve un chip con el estado legible de la tarea
  Widget _tareaEstadoChip(String estado, String solEstado) {
    String label;
    Color color;
    IconData icon;

    if (estado == 'finalizado' && solEstado == 'aprobado') {
      label = 'Tarea finalizada y aprobada';
      color = const Color(0xFF0F766E);
      icon = Icons.verified_rounded;
    } else if (estado == 'por_aprobar' || solEstado == 'pendiente') {
      label = 'Pendiente de aprobación';
      color = const Color(0xFFD97706);
      icon = Icons.hourglass_top_rounded;
    } else if (estado == 'finalizado') {
      label = 'Tarea finalizada';
      color = const Color(0xFF0F766E);
      icon = Icons.task_alt_rounded;
    } else if (estado == 'en_progreso') {
      label = 'En progreso';
      color = const Color(0xFF3B82F6);
      icon = Icons.autorenew_rounded;
    } else if (estado == 'pendiente') {
      label = 'Tarea pendiente';
      color = const Color(0xFF94A3B8);
      icon = Icons.schedule_rounded;
    } else {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.tareaId.isEmpty) return const SizedBox.shrink();
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('TBL_TAREAS')
          .doc(widget.tareaId)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData || !snap.data!.exists) return const SizedBox.shrink();
        final data = snap.data!.data()!;

        // Auto-sincronizar estado del hallazgo cuando la tarea es aprobada
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _maybeSyncEstado(data);
        });

        final tareaEstado = (data['estado'] ?? data['status'] ?? '')
            .toString()
            .toLowerCase();
        final solEstado = (data['solicitud_finalizacion_estado'] ?? '')
            .toString();

        // Adjuntos de la tarea (campo adjuntos) + evidencias de finalización
        final adjuntos = (data['adjuntos'] as List? ?? [])
            .cast<Map<String, dynamic>>();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),
            // ── Estado de la tarea ─────────────────────────────────────────
            Row(
              children: [
                const Icon(
                  Icons.link_rounded,
                  size: 13,
                  color: Color(0xFF64748B),
                ),
                const SizedBox(width: 5),
                const Text(
                  'Tarea asignada · ',
                  style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                ),
                _tareaEstadoChip(tareaEstado, solEstado),
              ],
            ),
            // ── Adjuntos / evidencias ──────────────────────────────────────
            if (adjuntos.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(
                    Icons.attach_file_rounded,
                    size: 13,
                    color: Color(0xFF0F766E),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'Evidencias (${adjuntos.length})',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F766E),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: adjuntos.map((adj) {
                  final nombre = (adj['name'] ?? adj['storedName'] ?? 'Archivo')
                      .toString();
                  final url = (adj['url'] ?? '').toString();
                  final mime = (adj['mime'] ?? '').toString();
                  return InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: url.isNotEmpty
                        ? () => launchUrlString(
                            url,
                            mode: LaunchMode.externalApplication,
                          )
                        : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: _colorForMime(mime).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: _colorForMime(mime).withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _iconForMime(mime),
                            size: 14,
                            color: _colorForMime(mime),
                          ),
                          const SizedBox(width: 5),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 180),
                            child: Text(
                              nombre,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: _colorForMime(mime),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.open_in_new_rounded,
                            size: 11,
                            color: _colorForMime(mime).withValues(alpha: 0.7),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ] else ...[
              const SizedBox(height: 6),
              Text(
                'Sin evidencias adjuntas aún.',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade500,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                fontFamily: _kFont,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyHallazgos extends StatelessWidget {
  final bool canWrite;
  final VoidCallback onTap;

  const _EmptyHallazgos({required this.canWrite, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.assignment_late_outlined,
            size: 52,
            color: Color(0xFF94A3B8),
          ),
          const SizedBox(height: 12),
          const Text('Sin hallazgos registrados'),
          if (canWrite) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onTap,
              icon: const Icon(Icons.document_scanner_rounded),
              label: const Text('Registrar primer acta'),
            ),
          ],
        ],
      ),
    );
  }
}

class _ActaGeneralCard extends StatelessWidget {
  final List<_PickedActa> files;
  final bool extracting;
  final VoidCallback onPickArchivo;
  final VoidCallback onPickCamera;
  final VoidCallback onPickGallery;
  final ValueChanged<_PickedActa> onPreview;
  final ValueChanged<_PickedActa> onRemove;

  const _ActaGeneralCard({
    required this.files,
    required this.extracting,
    required this.onPickArchivo,
    required this.onPickCamera,
    required this.onPickGallery,
    required this.onPreview,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final imageCount = files
        .where(
          (f) => f.contentType == 'image/jpeg' || f.contentType == 'image/png',
        )
        .length;
    final pdfCount = files
        .where((f) => f.contentType == 'application/pdf')
        .length;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Acta general (PDF) *',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                  ),
                ),
                if (files.isNotEmpty)
                  Text(
                    imageCount > 0
                        ? '$imageCount imagen(es) -> PDF'
                        : '$pdfCount PDF',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              files.isEmpty
                  ? 'Obligatorio. Adjunta el PDF o escanea sus páginas para generarlo.'
                  : 'Las imágenes escaneadas se convierten en el PDF general al guardar.',
              style: TextStyle(
                fontSize: 11,
                color: files.isEmpty ? _kDanger : const Color(0xFF64748B),
                fontWeight: files.isEmpty ? FontWeight.w700 : FontWeight.normal,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                // Subir archivo va en TODAS las plataformas. Antes estaba tras
                // un `if (kIsWeb)`, así que en el celular solo aparecían
                // Escanear y Galería y no había forma de adjuntar un acta que
                // ya viniera en PDF: había que fotografiar la pantalla.
                // FilePicker con withData funciona igual en Android e iOS.
                OutlinedButton.icon(
                  onPressed: onPickArchivo,
                  icon: const Icon(Icons.upload_file_rounded, size: 16),
                  label: const Text('Subir PDF/imagen'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                // Cámara y galería solo en móvil: en escritorio no aportan
                // nada que no cubra el selector de archivos.
                if (!kIsWeb) ...[
                  OutlinedButton.icon(
                    onPressed: onPickCamera,
                    icon: const Icon(Icons.document_scanner_rounded, size: 16),
                    label: const Text('Escanear'),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: onPickGallery,
                    icon: const Icon(Icons.photo_library_rounded, size: 16),
                    label: const Text('Galeria'),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
                if (extracting)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
              ],
            ),
            if (files.isNotEmpty) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 82,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: files.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final file = files[i];
                    final isImage =
                        file.contentType == 'image/jpeg' ||
                        file.contentType == 'image/png';
                    return InkWell(
                      onTap: () => onPreview(file),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: 118,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: isImage
                                    ? Image.memory(
                                        file.bytes,
                                        fit: BoxFit.cover,
                                        gaplessPlayback: true,
                                      )
                                    : const Center(
                                        child: Icon(
                                          Icons.picture_as_pdf_rounded,
                                          color: _kAccent,
                                          size: 34,
                                        ),
                                      ),
                              ),
                            ),
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.58),
                                  borderRadius: const BorderRadius.vertical(
                                    bottom: Radius.circular(8),
                                  ),
                                ),
                                child: Text(
                                  file.nombre,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              top: 2,
                              right: 2,
                              child: Material(
                                color: Colors.black.withValues(alpha: 0.48),
                                shape: const CircleBorder(),
                                child: InkWell(
                                  customBorder: const CircleBorder(),
                                  onTap: () => onRemove(file),
                                  child: const Padding(
                                    padding: EdgeInsets.all(4),
                                    child: Icon(
                                      Icons.close_rounded,
                                      color: Colors.white,
                                      size: 15,
                                    ),
                                  ),
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
          ],
        ),
      ),
    );
  }
}

class _PorcentajeInput extends StatefulWidget {
  final bool enabled;
  final double? value;
  final Color color;
  final ValueChanged<double> onChanged;

  const _PorcentajeInput({
    required this.enabled,
    required this.value,
    required this.color,
    required this.onChanged,
  });

  @override
  State<_PorcentajeInput> createState() => _PorcentajeInputState();
}

class _PorcentajeInputState extends State<_PorcentajeInput> {
  late final TextEditingController _ctrl;
  final _focusNode = FocusNode();

  String _formatValue(double? value) {
    if (value == null) return '';
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(1);
  }

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _formatValue(widget.value));
  }

  @override
  void didUpdateWidget(covariant _PorcentajeInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    // No resincronizar el texto mientras el usuario está escribiendo en este
    // campo: si lo hacemos, el valor clamped reemplaza lo que está tecleando
    // a mitad de escritura (p. ej. al escribir "850" salta a "100" antes de
    // terminar). Solo se sincroniza cuando el cambio viene de fuera
    // (carga inicial, NE, u otro campo).
    if (_focusNode.hasFocus) return;
    final nextText = _formatValue(widget.value);
    if (nextText != _ctrl.text && widget.value != oldWidget.value) {
      _ctrl.text = nextText;
    }
    if (!widget.enabled && _ctrl.text.isNotEmpty && widget.value == null) {
      _ctrl.text = '';
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      focusNode: _focusNode,
      enabled: widget.enabled,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
      style: TextStyle(
        fontWeight: FontWeight.w700,
        color: widget.enabled ? widget.color : const Color(0xFF94A3B8),
      ),
      decoration: InputDecoration(
        labelText: 'Puntaje',
        hintText: '—',
        suffixText: '%',
        border: const OutlineInputBorder(),
        isDense: true,
        filled: true,
        fillColor: widget.enabled
            ? widget.color.withValues(alpha: 0.08)
            : const Color(0xFFF1F5F9),
      ),
      onChanged: (value) =>
          _aplicarCorreccionPuntaje(value, _ctrl, widget.onChanged),
      onEditingComplete: () {
        final parsed = double.tryParse(_ctrl.text.replaceAll(',', '.'));
        final valido = parsed == null || parsed < 0 || parsed > 100
            ? 0.0
            : parsed;
        _ctrl.text = _formatValue(valido);
        widget.onChanged(valido);
      },
    );
  }
}

class _NotasInlineEditor extends StatelessWidget {
  final List<InterventoriaNota> notes;
  final String emptyText;
  final bool compact;
  final List<String> catalogItems;
  final bool catalogAsAspect;
  final bool allowManual;
  final bool allowOcrBulk;
  final Future<List<String>> Function() onPickOcrSnippets;
  final ValueChanged<List<InterventoriaNota>> onChanged;
  final VoidCallback? onGuardarRapido;

  const _NotasInlineEditor({
    required this.notes,
    required this.emptyText,
    required this.compact,
    required this.catalogItems,
    this.catalogAsAspect = false,
    this.allowManual = true,
    this.allowOcrBulk = true,
    required this.onPickOcrSnippets,
    required this.onChanged,
    this.onGuardarRapido,
  });

  void _addNote(InterventoriaNota note) {
    final text = note.texto.trim();
    if (text.isEmpty) return;
    onChanged([...notes, note.copyWith(texto: text)]);
  }

  void _updateNote(int index, InterventoriaNota note) {
    final next = [...notes];
    next[index] = note;
    onChanged(next);
  }

  void _deleteNote(int index) {
    final next = [...notes]..removeAt(index);
    onChanged(next);
  }

  Future<void> _addFromOcr(BuildContext context) async {
    final snippets = await onPickOcrSnippets();
    if (snippets.isEmpty) return;
    onChanged([
      ...notes,
      ...snippets.map((s) => InterventoriaNota(texto: s, fuente: 'ocr')),
    ]);
  }

  Future<void> _addFromCatalog(BuildContext context) async {
    final snippets = await _pickCatalogItems(context);
    if (snippets.isEmpty) return;
    onChanged([
      ...notes,
      ...snippets.map(
        (s) => catalogAsAspect
            ? InterventoriaNota(aspecto: s, texto: '', fuente: 'lista_acta')
            : InterventoriaNota(texto: s, fuente: 'lista_acta'),
      ),
    ]);
  }

  Future<List<String>> _pickCatalogItems(BuildContext context) async {
    if (catalogItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay ítems configurados para esta sección.'),
        ),
      );
      return const [];
    }
    // Extrae el numeral real del acta embebido al inicio del texto (p. ej.
    // "2. Existen fichas..." → "2"), para que el índice nunca contradiga
    // el número oficial que aparece en el cuerpo del ítem.
    String numeroDe(int i) {
      final m = RegExp(r'^(\d+)\.').firstMatch(catalogItems[i]);
      return m?.group(1) ?? '${i + 1}';
    }

    final selected = <String>{};
    var pagina = 0;
    final total = catalogItems.length;
    final result = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 560),
      // PointerInterceptor evita que el iframe del PDF robe los clicks del sheet
      builder: (ctx) => PointerInterceptor(
        child: StatefulBuilder(
          builder: (ctx, setSheetState) {
            final text = catalogItems[pagina];
            final checked = selected.contains(text);
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.45,
              maxChildSize: 0.7,
              minChildSize: 0.3,
              builder: (_, controller) => Material(
                color: const Color(0xFFF8FAFC),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Seleccionar ítems del acta',
                                  style: TextStyle(
                                    fontFamily: _kFont,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 17,
                                  ),
                                ),
                                Text(
                                  'Ítem ${numeroDe(pagina)} (${pagina + 1} de $total)'
                                  '${selected.isEmpty ? '' : ' · ${selected.length} seleccionados'}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () =>
                                Navigator.pop(ctx, const <String>[]),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                    ),
                    // ── Índice numerado: salto directo a cualquier ítem ────
                    SizedBox(
                      height: 44,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: total,
                        separatorBuilder: (_, _) => const SizedBox(width: 6),
                        itemBuilder: (_, i) {
                          final esActual = i == pagina;
                          final yaSeleccionado = selected.contains(
                            catalogItems[i],
                          );
                          return InkWell(
                            onTap: () => setSheetState(() => pagina = i),
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              width: 32,
                              height: 32,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: esActual
                                    ? _kAccent
                                    : yaSeleccionado
                                    ? _kOk.withValues(alpha: 0.15)
                                    : Colors.white,
                                border: Border.all(
                                  color: esActual
                                      ? _kAccent
                                      : yaSeleccionado
                                      ? _kOk
                                      : const Color(0xFFCBD5E1),
                                ),
                              ),
                              child: Text(
                                numeroDe(i),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: esActual
                                      ? Colors.white
                                      : yaSeleccionado
                                      ? _kOk
                                      : const Color(0xFF64748B),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    // ── Ítem actual (uno a la vez = paginado) ──────────────
                    Expanded(
                      child: SingleChildScrollView(
                        controller: controller,
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: CheckboxListTile(
                          value: checked,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text(
                            text,
                            style: const TextStyle(fontSize: 14),
                          ),
                          tileColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: const BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                          onChanged: (value) {
                            setSheetState(() {
                              if (value == true) {
                                selected.add(text);
                              } else {
                                selected.remove(text);
                              }
                            });
                          },
                        ),
                      ),
                    ),
                    // ── Navegación anterior/siguiente ──────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: pagina > 0
                                ? () => setSheetState(() => pagina--)
                                : null,
                            icon: const Icon(Icons.chevron_left_rounded),
                            label: const Text('Anterior'),
                          ),
                          const Spacer(),
                          OutlinedButton.icon(
                            onPressed: pagina < total - 1
                                ? () => setSheetState(() => pagina++)
                                : null,
                            icon: const Icon(Icons.chevron_right_rounded),
                            label: const Text('Siguiente'),
                          ),
                        ],
                      ),
                    ),
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: selected.isEmpty
                                ? null
                                : () => Navigator.pop(ctx, selected.toList()),
                            icon: const Icon(Icons.add_rounded),
                            label: Text(
                              selected.isEmpty
                                  ? 'Selecciona uno o varios'
                                  : 'Agregar ${selected.length}',
                            ),
                          ),
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
    );
    return result ?? const [];
  }

  Future<void> _addFromVoice(BuildContext context) async {
    final text = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PointerInterceptor(child: const _VoiceDictationDialog()),
    );
    if (text == null || text.trim().isEmpty) return;
    _addNote(InterventoriaNota(texto: text.trim(), fuente: 'voz'));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            // "Manual" solo aparece si no hay ítems de catálogo disponibles
            if (allowManual && catalogItems.isEmpty)
              OutlinedButton.icon(
                onPressed: () => onChanged([
                  ...notes,
                  const InterventoriaNota(texto: '', fuente: 'manual'),
                ]),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Manual'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            // "Agregar ítem" solo aparece si hay ítems de catálogo disponibles
            if (catalogItems.isNotEmpty)
              OutlinedButton.icon(
                onPressed: () => _addFromCatalog(context),
                icon: const Icon(Icons.list_alt_rounded, size: 16),
                label: Text(catalogAsAspect ? 'Agregar ítem' : 'Lista acta'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            if (allowOcrBulk)
              OutlinedButton.icon(
                onPressed: () => _addFromOcr(context),
                icon: const Icon(Icons.playlist_add_check_rounded, size: 16),
                label: const Text('Desde OCR'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            if (!catalogAsAspect)
              OutlinedButton.icon(
                onPressed: () => _addFromVoice(context),
                icon: const Icon(Icons.mic_rounded, size: 16),
                label: const Text('Voz'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
          ],
        ),
        if (notes.isEmpty) ...[
          const SizedBox(height: 8),
          Text(
            emptyText,
            style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
          ),
        ] else ...[
          const SizedBox(height: 8),
          ...notes.asMap().entries.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _NotaEditorTile(
                key: ValueKey('nota_${entry.key}_${entry.value.aspecto}'),
                note: entry.value,
                compact: compact,
                onPickOcrSnippets: onPickOcrSnippets,
                onChanged: (note) => _updateNote(entry.key, note),
                onDelete: () => _deleteNote(entry.key),
                onGuardarRapido: onGuardarRapido,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _NotaEditorTile extends StatefulWidget {
  final InterventoriaNota note;
  final bool compact;
  final Future<List<String>> Function()? onPickOcrSnippets;
  final ValueChanged<InterventoriaNota> onChanged;
  final VoidCallback onDelete;
  final VoidCallback? onGuardarRapido;

  const _NotaEditorTile({
    super.key,
    required this.note,
    required this.compact,
    this.onPickOcrSnippets,
    required this.onChanged,
    required this.onDelete,
    this.onGuardarRapido,
  });

  @override
  State<_NotaEditorTile> createState() => _NotaEditorTileState();
}

class _NotaEditorTileState extends State<_NotaEditorTile> {
  late final TextEditingController _ctrl;
  bool _scanning = false;
  bool _collapsed = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.note.texto);
  }

  @override
  void didUpdateWidget(_NotaEditorTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.note.texto != oldWidget.note.texto &&
        widget.note.texto != _ctrl.text) {
      _ctrl.text = widget.note.texto;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    if (kIsWeb) {
      final snippets = await widget.onPickOcrSnippets?.call() ?? const [];
      if (snippets.isEmpty) return;
      final text = snippets.join('\n');
      _ctrl.text = text;
      widget.onChanged(widget.note.copyWith(texto: text, fuente: 'ocr'));
      return;
    }
    final img = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 92,
    );
    if (img == null) return;
    setState(() => _scanning = true);
    final text = await recognizeTextFromXFile(img);
    if (!mounted) return;
    setState(() => _scanning = false);
    if (text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se detectó texto en la imagen')),
      );
      return;
    }
    _ctrl.text = text.trim();
    widget.onChanged(widget.note.copyWith(texto: text.trim(), fuente: 'ocr'));
  }

  Future<void> _dictate() async {
    final text = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PointerInterceptor(
        child: _VoiceDictationDialog(initialText: _ctrl.text),
      ),
    );
    if (text == null || text.trim().isEmpty) return;
    _ctrl.text = text.trim();
    widget.onChanged(widget.note.copyWith(texto: text.trim(), fuente: 'voz'));
  }

  @override
  Widget build(BuildContext context) {
    final hasAspect = widget.note.aspecto.trim().isNotEmpty;

    // ── Versión colapsada: muestra lo que se escribió + lápiz para reabrir ──
    if (_collapsed) {
      final textoEscrito = widget.note.texto.trim();
      return DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFF0FDF4),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFBBF7D0)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(Icons.check_circle_rounded, size: 16, color: _kOk),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (hasAspect)
                      Text(
                        widget.note.aspecto,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF166534),
                        ),
                      ),
                    Text(
                      textoEscrito.isEmpty
                          ? 'Sin observación escrita'
                          : textoEscrito,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontStyle: textoEscrito.isEmpty
                            ? FontStyle.italic
                            : FontStyle.normal,
                        color: textoEscrito.isEmpty
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF15803D),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Editar',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.edit_rounded, size: 18),
                onPressed: () => setState(() => _collapsed = false),
              ),
            ],
          ),
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: EdgeInsets.all(widget.compact ? 8 : 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _FuenteNotaChip(fuente: widget.note.fuente),
                const Spacer(),
                IconButton(
                  tooltip: 'OCR',
                  visualDensity: VisualDensity.compact,
                  onPressed: _scanning ? null : _scan,
                  icon: _scanning
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.document_scanner_rounded, size: 18),
                ),
                IconButton(
                  tooltip: 'Dictar',
                  visualDensity: VisualDensity.compact,
                  onPressed: _dictate,
                  icon: const Icon(Icons.mic_rounded, size: 18),
                ),
                IconButton(
                  tooltip: 'Eliminar',
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.onDelete,
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    size: 18,
                    color: Colors.red.shade400,
                  ),
                ),
                IconButton(
                  tooltip: 'Marcar como listo y guardar',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.check_circle_rounded, size: 20),
                  color: _kOk,
                  onPressed: () {
                    setState(() => _collapsed = true);
                    widget.onGuardarRapido?.call();
                  },
                ),
              ],
            ),
            if (hasAspect) ...[
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Text(
                  widget.note.aspecto,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF334155),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 6),
            TextField(
              controller: _ctrl,
              minLines: 1,
              maxLines: widget.compact ? 4 : 7,
              decoration: InputDecoration(
                hintText: hasAspect
                    ? 'Observación, hallazgo o acción correctiva'
                    : 'Escribe, escanea o dicta la observación',
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              onChanged: (text) =>
                  widget.onChanged(widget.note.copyWith(texto: text)),
            ),
          ],
        ),
      ),
    );
  }
}

class _FuenteNotaChip extends StatelessWidget {
  final String fuente;

  const _FuenteNotaChip({required this.fuente});

  @override
  Widget build(BuildContext context) {
    final label = switch (fuente) {
      'ocr' => 'OCR',
      'voz' => 'Voz',
      'lista_acta' => 'Acta',
      _ => 'Manual',
    };
    final color = switch (fuente) {
      'ocr' => _kAccent,
      'voz' => Colors.indigo,
      'lista_acta' => Colors.deepPurple,
      _ => const Color(0xFF64748B),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _VoiceDictationDialog extends StatefulWidget {
  final String initialText;

  const _VoiceDictationDialog({this.initialText = ''});

  @override
  State<_VoiceDictationDialog> createState() => _VoiceDictationDialogState();
}

class _VoiceDictationDialogState extends State<_VoiceDictationDialog> {
  final stt.SpeechToText _speech = stt.SpeechToText();
  late String _text;
  bool _available = false;
  bool _listening = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _text = widget.initialText;
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    final available = await _speech.initialize(
      onStatus: (status) {
        if (mounted) setState(() => _listening = status == 'listening');
      },
      onError: (error) {
        if (mounted) setState(() => _error = error.errorMsg);
      },
    );
    if (!mounted) return;
    setState(() => _available = available);
    if (available) _listen();
  }

  Future<void> _listen() async {
    if (!_available) return;
    setState(() {
      _listening = true;
      _error = null;
    });
    await _speech.listen(
      localeId: 'es_CO',
      listenOptions: stt.SpeechListenOptions(
        listenMode: stt.ListenMode.dictation,
        partialResults: true,
      ),
      onResult: (result) {
        if (!mounted) return;
        setState(() {
          _text = result.recognizedWords.trim().isEmpty
              ? _text
              : result.recognizedWords.trim();
        });
      },
    );
  }

  Future<void> _stop() async {
    await _speech.stop();
    if (mounted) setState(() => _listening = false);
  }

  @override
  void dispose() {
    _speech.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // En pantallas anchas (revisión split-screen) el diálogo se ancla
    // al lado derecho para no cubrir el PDF del panel izquierdo.
    final isWide = MediaQuery.sizeOf(context).width > 720;
    return Dialog(
      alignment: isWide ? Alignment.centerRight : Alignment.center,
      insetPadding: isWide
          ? const EdgeInsets.only(right: 24, top: 40, bottom: 40)
          : const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Título ──────────────────────────────────────────────
              Row(
                children: [
                  const Icon(Icons.mic_rounded, size: 20, color: _kAccent),
                  const SizedBox(width: 8),
                  const Text(
                    'Dictado de voz',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      fontFamily: _kFont,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    tooltip: 'Cancelar',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // ── Estado ──────────────────────────────────────────────
              if (_error != null)
                Text(
                  'No se pudo escuchar: $_error',
                  style: TextStyle(fontSize: 12, color: Colors.red.shade700),
                )
              else
                Text(
                  _available
                      ? (_listening ? 'Escuchando…' : 'Dictado en pausa')
                      : 'El dictado no está disponible en este dispositivo.',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
                  ),
                ),
              const SizedBox(height: 10),
              // ── Texto transcrito ─────────────────────────────────────
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(
                  minHeight: 90,
                  maxHeight: 160,
                ),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    _text.isEmpty ? '…' : _text,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              // ── Acciones ─────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: _available
                        ? (_listening ? _stop : _listen)
                        : null,
                    icon: Icon(
                      _listening ? Icons.stop_rounded : Icons.mic_rounded,
                      size: 16,
                    ),
                    label: Text(_listening ? 'Pausar' : 'Escuchar'),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _text.trim().isEmpty
                        ? null
                        : () => Navigator.pop(context, _text.trim()),
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('Usar texto'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PickedActa {
  final Uint8List bytes;
  final String? base64Data;
  final String nombre;
  final String contentType;
  final String origen;

  const _PickedActa({
    required this.bytes,
    this.base64Data,
    required this.nombre,
    required this.contentType,
    required this.origen,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Selector de fecha tipo tile — reutilizable en filtros y seguimiento
// ─────────────────────────────────────────────────────────────────────────────

class _FechaTile extends StatelessWidget {
  final String label;
  final DateTime? fecha;
  final ValueChanged<DateTime?> onChanged;

  const _FechaTile({
    required this.label,
    required this.fecha,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd/MM/yy');
    final active = fecha != null;
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: fecha ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime(2035),
        );
        if (picked != null) onChanged(picked);
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          border: Border.all(
            color: active ? _kAccent : const Color(0xFFCBD5E1),
          ),
          borderRadius: BorderRadius.circular(8),
          color: active ? _kAccent.withValues(alpha: 0.07) : Colors.white,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.calendar_today_rounded,
              size: 15,
              color: active ? _kAccent : const Color(0xFF94A3B8),
            ),
            const SizedBox(width: 6),
            Text(
              active ? '$label: ${fmt.format(fecha!)}' : label,
              style: TextStyle(
                fontSize: 13,
                color: active ? _kAccent : const Color(0xFF64748B),
                fontWeight: active ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            if (active) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () => onChanged(null),
                child: const Icon(
                  Icons.close_rounded,
                  size: 14,
                  color: Color(0xFF94A3B8),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

Color _percentColor(double value) {
  if (value >= 90) return Colors.green.shade700;
  if (value >= 70) return _kWarning;
  return _kDanger;
}

/// Corrige en vivo lo que se escribe en un campo de puntaje (0-100):
/// quita ceros a la izquierda ("078" → "78", "0000" → "0") y, si el
/// valor queda fuera de rango, lo deja en 0 — todo de inmediato, sin
/// esperar a que el usuario termine de escribir o salga del campo.
void _aplicarCorreccionPuntaje(
  String texto,
  TextEditingController ctrl,
  void Function(double valor) onValido,
) {
  final sinCeros = texto.replaceFirst(RegExp(r'^0+(?=\d)'), '');
  final p = double.tryParse(sinCeros.replaceAll(',', '.'));
  if (p == null) {
    if (sinCeros != texto) {
      ctrl.value = TextEditingValue(
        text: sinCeros,
        selection: TextSelection.collapsed(offset: sinCeros.length),
      );
    }
    return;
  }
  final valido = (p < 0 || p > 100) ? 0.0 : p;
  onValido(valido);
  final fueraDeRango = valido != p;
  final textoFinal = fueraDeRango
      ? (valido == valido.roundToDouble()
            ? valido.toStringAsFixed(0)
            : valido.toStringAsFixed(1))
      : sinCeros;
  if (textoFinal != texto) {
    ctrl.value = TextEditingValue(
      text: textoFinal,
      selection: TextSelection.collapsed(offset: textoFinal.length),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab "Por revisar" — Fase 2
// ─────────────────────────────────────────────────────────────────────────────

class _PorRevisarTab extends StatelessWidget {
  final String empresaId;
  final InterventoriaService service;
  final String userId;
  final String rol;

  const _PorRevisarTab({
    required this.empresaId,
    required this.service,
    required this.userId,
    required this.rol,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<InterventoriaVisita>>(
      stream: service.streamActasPendientesRevision(empresaId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final actas = snap.data ?? const [];
        if (actas.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.check_circle_outline_rounded,
                  size: 56,
                  color: Colors.green.shade400,
                ),
                const SizedBox(height: 12),
                const Text(
                  'No hay actas pendientes de revisión',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF475569),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Cuando el Administrador registre puntajes\naparecerán aquí para completar.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                ),
              ],
            ),
          );
        }
        return InternalModuleViewport(
          maxWidth: 1000,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Actas pendientes de revisión',
                      style: TextStyle(
                        fontFamily: _kFont,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _kWarning.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${actas.length} pendiente${actas.length == 1 ? '' : 's'}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _kWarning,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Abre cada acta para ver el PDF del interventor y completar observaciones.',
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.separated(
                  itemCount: actas.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final acta = actas[i];
                    final fecha = DateFormat(
                      'dd/MM/yyyy',
                    ).format(acta.fechaVisita.toDate());
                    final pct = acta.porcentajeGeneral;
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: _percentColor(
                            pct,
                          ).withValues(alpha: 0.15),
                          child: Text(
                            '${pct.toStringAsFixed(0)}%',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: _percentColor(pct),
                            ),
                          ),
                        ),
                        title: Text(
                          acta.centroCostoNombre,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          '$fecha${acta.tipoActa != null ? ' · ${acta.tipoActa}' : ''}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: _kAccent,
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: () => _abrirRevision(context, acta),
                          icon: const Icon(Icons.rate_review_rounded, size: 16),
                          label: const Text('Revisar'),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _abrirRevision(BuildContext context, InterventoriaVisita acta) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _RevisionActaScreen(
          visita: acta,
          service: service,
          userId: userId,
          rol: rol,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pantalla de revisión — Fase 2 (split PDF + formulario)
// ─────────────────────────────────────────────────────────────────────────────

class _RevisionActaScreen extends StatefulWidget {
  final InterventoriaVisita visita;
  final InterventoriaService service;
  final String userId;
  final String rol;

  const _RevisionActaScreen({
    required this.visita,
    required this.service,
    required this.userId,
    required this.rol,
  });

  @override
  State<_RevisionActaScreen> createState() => _RevisionActaScreenState();
}

class _RevisionActaScreenState extends State<_RevisionActaScreen> {
  late Map<String, InterventoriaItem> _items;
  final _obsGeneralesCtrl = TextEditingController();
  final _conclusionesCtrl = TextEditingController();
  bool _saving = false;
  bool _mostrarActaEnEscritorio = true;
  bool _mostrarActaEnTablet = false;

  @override
  void initState() {
    super.initState();
    _items = Map.from(widget.visita.items);
    // Pre-cargar valores existentes si los hay
    final ocrData = widget.visita.ocrDatosDetectados;
    _obsGeneralesCtrl.text = (ocrData['observacionesGenerales'] ?? '')
        .toString();
    _conclusionesCtrl.text = (ocrData['conclusiones'] ?? '').toString();
  }

  @override
  void dispose() {
    _obsGeneralesCtrl.dispose();
    _conclusionesCtrl.dispose();
    super.dispose();
  }

  /// Autosave silencioso al marcar el check de un item — sin snackbar ni spinner.
  Future<void> _guardarRapidoSilencioso() async {
    try {
      await widget.service.guardarBorradorRevision(
        visita: widget.visita,
        items: _items,
        obsGenerales: _obsGeneralesCtrl.text.trim(),
        conclusiones: _conclusionesCtrl.text.trim(),
      );
    } catch (_) {}
  }

  Future<void> _completar() async {
    // Nota: el puntaje ya quedó validado/fijado en "Registrar acta" (Fase 1).
    // Revisar solo agrega observaciones — no se vuelve a exigir puntaje aquí.
    setState(() => _saving = true);
    try {
      await widget.service.completarActa(
        visita: widget.visita,
        items: _items,
        obsGenerales: _obsGeneralesCtrl.text.trim(),
        conclusiones: _conclusionesCtrl.text.trim(),
      );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFF16A34A),
            content: Text('Acta completada correctamente'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al completar: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final esEscritorio = width >= 1180;
    final appBarCompacta = width < 640;
    final fecha = DateFormat(
      'dd/MM/yyyy',
    ).format(widget.visita.fechaVisita.toDate());

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: _kAccent,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.visita.centroCostoNombre,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
            Text(
              'Revisión de acta · $fecha',
              style: const TextStyle(fontSize: 11),
            ),
          ],
        ),
        actions: [
          if (esEscritorio)
            IconButton(
              tooltip: _mostrarActaEnEscritorio
                  ? 'Ocultar acta original'
                  : 'Mostrar acta original',
              onPressed: () => setState(
                () => _mostrarActaEnEscritorio = !_mostrarActaEnEscritorio,
              ),
              icon: Icon(
                _mostrarActaEnEscritorio
                    ? Icons.visibility_off_outlined
                    : Icons.picture_as_pdf_outlined,
              ),
            ),
          // Guardar progreso eliminado: el check de cada observación
          // ya autoguarda (ver onGuardarRapido en _NotaEditorTile).
          // ── Completar acta (final) ─────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: _kAccent,
              ),
              onPressed: _saving ? null : _completar,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_circle_rounded),
              label: Text(
                _saving
                    ? 'Guardando...'
                    : (appBarCompacta ? 'Completar' : 'Completar acta'),
              ),
            ),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 1180) return _buildWebLayout();
          if (constraints.maxWidth >= 700) return _buildTabletLayout();
          return _buildMobileLayout();
        },
      ),
    );
  }

  Widget _buildWebLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Panel izquierdo: visor PDF ────────────────────────────────
        if (_mostrarActaEnEscritorio) ...[
          Expanded(
            flex: 5,
            child: _PdfPanel(
              url: widget.visita.actaOriginalUrl,
              adjuntos: widget.visita.adjuntos,
              onHide: () => setState(() => _mostrarActaEnEscritorio = false),
            ),
          ),
          const VerticalDivider(width: 1, thickness: 1),
        ],
        // ── Panel derecho: formulario de revisión ─────────────────────
        Expanded(
          flex: _mostrarActaEnEscritorio ? 5 : 10,
          child: _FormularioRevision(
            visita: widget.visita,
            items: _items,
            obsGeneralesCtrl: _obsGeneralesCtrl,
            conclusionesCtrl: _conclusionesCtrl,
            onItemChanged: (key, item) => setState(() => _items[key] = item),
            onGuardarRapido: _guardarRapidoSilencioso,
          ),
        ),
      ],
    );
  }

  Widget _buildTabletLayout() {
    return Column(
      children: [
        Material(
          color: Colors.white,
          elevation: 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _mostrarActaEnTablet
                        ? 'Consultando el acta original'
                        : 'Trabajando en observaciones',
                    style: const TextStyle(
                      color: Color(0xFF475569),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => setState(() => _mostrarActaEnTablet = true),
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                  label: const Text('Acta'),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: _mostrarActaEnTablet
                        ? const Color(0xFFCCFBF1)
                        : null,
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () => setState(() => _mostrarActaEnTablet = false),
                  icon: const Icon(Icons.edit_note_rounded, size: 18),
                  label: const Text('Observaciones'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _mostrarActaEnTablet
                        ? const Color(0xFF64748B)
                        : _kAccent,
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: _mostrarActaEnTablet
              ? _PdfPanel(
                  url: widget.visita.actaOriginalUrl,
                  adjuntos: widget.visita.adjuntos,
                  onHide: () => setState(() => _mostrarActaEnTablet = false),
                )
              : _FormularioRevision(
                  visita: widget.visita,
                  items: _items,
                  obsGeneralesCtrl: _obsGeneralesCtrl,
                  conclusionesCtrl: _conclusionesCtrl,
                  onItemChanged: (key, item) =>
                      setState(() => _items[key] = item),
                  onGuardarRapido: _guardarRapidoSilencioso,
                ),
        ),
      ],
    );
  }

  Widget _buildMobileLayout() {
    return DefaultTabController(
      length: 2,
      initialIndex: 1,
      child: Column(
        children: [
          TabBar(
            labelColor: _kAccent,
            unselectedLabelColor: const Color(0xFF64748B),
            indicatorColor: _kAccent,
            tabs: const [
              Tab(icon: Icon(Icons.picture_as_pdf_rounded), text: 'PDF'),
              Tab(icon: Icon(Icons.edit_note_rounded), text: 'Formulario'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _PdfPanel(
                  url: widget.visita.actaOriginalUrl,
                  adjuntos: widget.visita.adjuntos,
                ),
                _FormularioRevision(
                  visita: widget.visita,
                  items: _items,
                  obsGeneralesCtrl: _obsGeneralesCtrl,
                  conclusionesCtrl: _conclusionesCtrl,
                  onItemChanged: (key, item) =>
                      setState(() => _items[key] = item),
                  onGuardarRapido: _guardarRapidoSilencioso,
                ),
              ],
            ),
          ),
          // ── Botón completar fijo al fondo en móvil ────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: _kAccent),
                  onPressed: _saving ? null : _completar,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_circle_rounded),
                  label: Text(_saving ? 'Guardando...' : 'Completar acta'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Panel visor de PDF
// ─────────────────────────────────────────────────────────────────────────────

class _PdfPanel extends StatelessWidget {
  final String url;
  final List<InterventoriaAdjunto> adjuntos;
  final VoidCallback? onHide;

  const _PdfPanel({required this.url, required this.adjuntos, this.onHide});

  String get _pdfUrl {
    if (url.isNotEmpty) return url;
    // Fallback: primer adjunto PDF en la lista
    try {
      return adjuntos.firstWhere((a) => a.contentType == 'application/pdf').url;
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final pdfUrl = _pdfUrl;
    if (pdfUrl.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.picture_as_pdf_rounded,
              size: 56,
              color: Colors.red.shade300,
            ),
            const SizedBox(height: 12),
            const Text(
              'Sin PDF adjunto',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            const Text(
              'El administrador no subió ningún PDF en esta acta.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
            ),
          ],
        ),
      );
    }

    // Abrir PDF en navegador externo + mostrar botón para abrir
    return Column(
      children: [
        Container(
          color: const Color(0xFF1E293B),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              const Icon(
                Icons.picture_as_pdf_rounded,
                color: Colors.white70,
                size: 18,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Acta original del interventor',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white54),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => launchUrlString(
                  pdfUrl,
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.open_in_new_rounded, size: 14),
                label: const Text('Abrir', style: TextStyle(fontSize: 12)),
              ),
              if (onHide != null) ...[
                const SizedBox(width: 6),
                IconButton(
                  tooltip: 'Ocultar acta y ampliar observaciones',
                  visualDensity: VisualDensity.compact,
                  onPressed: onHide,
                  icon: const Icon(
                    Icons.visibility_off_outlined,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ],
            ],
          ),
        ),
        Expanded(child: WebPdfView(url: pdfUrl)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Formulario de revisión (Fase 2)
// ─────────────────────────────────────────────────────────────────────────────

class _FormularioRevision extends StatefulWidget {
  final InterventoriaVisita visita;
  final Map<String, InterventoriaItem> items;
  final TextEditingController obsGeneralesCtrl;
  final TextEditingController conclusionesCtrl;
  final void Function(String key, InterventoriaItem item) onItemChanged;
  final VoidCallback? onGuardarRapido;

  const _FormularioRevision({
    required this.visita,
    required this.items,
    required this.obsGeneralesCtrl,
    required this.conclusionesCtrl,
    required this.onItemChanged,
    this.onGuardarRapido,
  });

  @override
  State<_FormularioRevision> createState() => _FormularioRevisionState();
}

class _FormularioRevisionState extends State<_FormularioRevision> {
  final _scrollCtrl = ScrollController();
  late final List<InterventoriaCategoria> _categorias = categoriasDeActa(
    widget.visita.tipoActa,
  );
  late final Map<String, GlobalKey> _itemKeys = {
    for (final cat in _categorias) cat.key: GlobalKey(),
  };

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _irAlItem(String key) {
    final ctx = _itemKeys[key]?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      alignment: 0.05,
    );
  }

  @override
  Widget build(BuildContext context) {
    final visita = widget.visita;
    final items = widget.items;
    final fecha = DateFormat('dd/MM/yyyy').format(visita.fechaVisita.toDate());
    return ListView(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 100),
      children: [
        // ── Info resumen del acta ──────────────────────────────────────
        Card(
          color: _kAccent.withValues(alpha: 0.06),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                _InfoChip(label: 'Centro', value: visita.centroCostoNombre),
                _InfoChip(label: 'Fecha', value: fecha),
                if (visita.tipoActa != null)
                  _InfoChip(label: 'Tipo', value: visita.tipoActa!),
                if (visita.tiempoComida != null)
                  _InfoChip(label: 'Comida', value: visita.tiempoComida!),
                _InfoChip(
                  label: 'Puntaje general',
                  value: '${visita.porcentajeGeneral.toStringAsFixed(1)}%',
                  valueColor: _percentColor(visita.porcentajeGeneral),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'Observaciones por sección',
          style: TextStyle(
            fontFamily: _kFont,
            fontWeight: FontWeight.w900,
            fontSize: 15,
            color: Color(0xFF1E293B),
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'El puntaje ya fue registrado. Agrega las observaciones de cada ítem.',
          style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 10),
        // ── Índice navegable: salta directo al numeral sin scroll largo ──
        SizedBox(
          height: 64,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: kInterventoriaCategorias.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (_, i) {
              final cat = kInterventoriaCategorias[i];
              final item = items[cat.key] ?? InterventoriaItem.empty(cat);
              final color = item.noEvaluado
                  ? const Color(0xFF94A3B8)
                  : item.valor != null
                  ? _percentColor(item.valor!)
                  : const Color(0xFFCBD5E1);
              return InkWell(
                onTap: () => _irAlItem(cat.key),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 78,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    border: Border.all(color: color.withValues(alpha: 0.6)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${i + 1}',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          color: color,
                        ),
                      ),
                      Text(
                        cat.label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 9,
                          color: color,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        // ── Items con puntaje (solo lectura) + observaciones ──────────
        ..._categorias.asMap().entries.map((entry) {
          final i = entry.key;
          final cat = entry.value;
          final item = items[cat.key] ?? InterventoriaItem.empty(cat);
          return KeyedSubtree(
            key: _itemKeys[cat.key],
            child: _ItemRevisionRow(
              // Sección REAL del acta, no la posición en la lista: horario y
              // concepto sanitario son ambos sección 1, así que numerarlos
              // 1..12 corría todas las demás secciones un lugar.
              numero: seccionDeActa(widget.visita.tipoActa, cat.key) ?? i + 1,
              item: item,
              tipoActa: widget.visita.tipoActa,
              onChanged: (updated) => widget.onItemChanged(cat.key, updated),
              onGuardarRapido: widget.onGuardarRapido,
            ),
          );
        }),
        const SizedBox(height: 14),
        const Divider(),
        const SizedBox(height: 10),
        // ── Observaciones generales ───────────────────────────────────
        const Text(
          'Observaciones generales',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: widget.obsGeneralesCtrl,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Escribe las observaciones generales del acta...',
            border: OutlineInputBorder(),
            filled: true,
            fillColor: Colors.white,
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'Conclusiones',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: widget.conclusionesCtrl,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Escribe las conclusiones del acta...',
            border: OutlineInputBorder(),
            filled: true,
            fillColor: Colors.white,
          ),
        ),
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const _InfoChip({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: valueColor ?? const Color(0xFF1E293B),
          ),
        ),
      ],
    );
  }
}

// Item de revisión: puntaje (solo lectura) + campo de observación editable
/// Item de revisión (Fase 2): puntaje en solo lectura + observaciones completas
/// con catálogo, voz y edición manual — igual que _ItemPuntajeRow pero sin
/// permitir cambiar el puntaje.
class _ItemRevisionRow extends StatefulWidget {
  final int numero;
  final InterventoriaItem item;
  final ValueChanged<InterventoriaItem> onChanged;
  final VoidCallback? onGuardarRapido;

  /// Acta a la que pertenece el ítem: decide el catálogo de aspectos.
  final String? tipoActa;

  const _ItemRevisionRow({
    required this.numero,
    required this.item,
    required this.onChanged,
    this.onGuardarRapido,
    this.tipoActa,
  });

  @override
  State<_ItemRevisionRow> createState() => _ItemRevisionRowState();
}

class _ItemRevisionRowState extends State<_ItemRevisionRow> {
  List<InterventoriaNota> get _notes {
    final item = widget.item;
    if (item.observaciones.isNotEmpty) return item.observaciones;
    if (item.observacion.trim().isEmpty) return const [];
    return [
      InterventoriaNota(texto: item.observacion.trim(), fuente: item.fuente),
    ];
  }

  void _setNotes(List<InterventoriaNota> notes) {
    widget.onChanged(
      widget.item.copyWith(
        observaciones: notes,
        observacion: notes.map((n) => n.texto.trim()).join('\n'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final color = item.noEvaluado
        ? const Color(0xFF94A3B8)
        : _percentColor(item.valor ?? 0);
    final puntajeLabel = item.noEvaluado
        ? 'NE'
        : item.valor != null
        ? '${item.valor!.toStringAsFixed(1)}%'
        : '—';

    // ── Cabecera: solo numeral + título + puntaje (solo lectura) ──────
    // El check/colapso vive en cada ítem agregado (_NotaEditorTile),
    // no en toda la sección.
    final cabecera = Row(
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Text(
            '${widget.numero}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            item.label,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            puntajeLabel,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ),
      ],
    );

    return Card(
      key: ValueKey('item_revision_${item.key}'),
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            cabecera,
            const SizedBox(height: 8),
            // ── Observaciones con catálogo + voz ──────────────────────
            // Cada ítem agregado tiene su propio check/colapso/lápiz.
            _NotasInlineEditor(
              notes: _notes,
              compact: true,
              emptyText: 'Sin observaciones',
              catalogItems: aspectosDeActa(widget.tipoActa, item.key),
              catalogAsAspect: true,
              allowManual: true,
              allowOcrBulk: false,
              onPickOcrSnippets: () async => const [],
              onChanged: _setNotes,
              onGuardarRapido: widget.onGuardarRapido,
            ),
          ],
        ),
      ),
    );
  }
}
