import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'interventoria_models.dart';
import 'interventoria_service.dart';
import 'interventoria_tablero_asignacion.dart';

const _ink = Color(0xFF0F172A);
const _muted = Color(0xFF64748B);
const _accent = Color(0xFF0F766E);
const _danger = Color(0xFFDC2626);
const _warn = Color(0xFFB45309);
const _ok = Color(0xFF16A34A);
const _borde = Color(0xFFE2E8F0);

/// Abre el detalle de un hallazgo.
///
/// En pantalla ancha va centrado como diálogo y en angosta como hoja: una hoja
/// que ocupa media pantalla en un monitor se ve desencajada, y un diálogo
/// pequeño en un celular no deja escribir.
Future<void> mostrarPanelHallazgo(
  BuildContext context, {
  required InterventoriaHallazgo hallazgo,
  required InterventoriaService service,
  required String userId,
  required String empresaId,
  required bool canWrite,
}) {
  final ancho = MediaQuery.sizeOf(context).width >= 760;
  final contenido = InterventoriaHallazgoPanel(
    hallazgo: hallazgo,
    service: service,
    userId: userId,
    empresaId: empresaId,
    canWrite: canWrite,
  );
  if (ancho) {
    return showDialog(
      context: context,
      builder: (_) => Dialog(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 720),
          child: contenido,
        ),
      ),
    );
  }
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: .92,
      minChildSize: .5,
      builder: (_, _) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: contenido,
      ),
    ),
  );
}

/// Detalle de un hallazgo: quién responde, qué se ha publicado en su tarea y
/// el seguimiento del acta. Todo lo que hace falta para saber cómo va y para
/// corregir la asignación si se eligió mal.
class InterventoriaHallazgoPanel extends StatefulWidget {
  final InterventoriaHallazgo hallazgo;
  final InterventoriaService service;
  final String userId;
  final String empresaId;
  final bool canWrite;

  const InterventoriaHallazgoPanel({
    super.key,
    required this.hallazgo,
    required this.service,
    required this.userId,
    required this.empresaId,
    required this.canWrite,
  });

  @override
  State<InterventoriaHallazgoPanel> createState() =>
      _InterventoriaHallazgoPanelState();
}

class _InterventoriaHallazgoPanelState
    extends State<InterventoriaHallazgoPanel> {
  late final TextEditingController _seguCtrl;
  late InterventoriaHallazgo _h;
  DateTime? _fechaSub;
  bool _guardando = false;
  bool _asignando = false;
  List<InterventoriaUsuario> _usuarios = const [];

  @override
  void initState() {
    super.initState();
    _h = widget.hallazgo;
    _seguCtrl = TextEditingController(text: _h.seguimiento);
    _fechaSub = _h.fechaSubsanacion?.toDate();
    _cargarUsuarios();
  }

  @override
  void dispose() {
    _seguCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarUsuarios() async {
    try {
      final rows = await widget.service.listarUsuariosAsignables(
        widget.empresaId,
      );
      if (mounted) setState(() => _usuarios = rows);
    } catch (_) {
      // Sin la lista no se puede sugerir, pero el resto del panel sirve igual.
    }
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _cabecera(),
          Flexible(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              children: [
                _bloqueResponsable(),
                const SizedBox(height: 18),
                if (_h.tareaId.trim().isNotEmpty) ...[
                  _tituloBloque('Avance publicado en la tarea'),
                  const SizedBox(height: 8),
                  _AvanceDeTarea(tareaId: _h.tareaId),
                  const SizedBox(height: 18),
                ],
                _tituloBloque('Seguimiento del hallazgo'),
                const SizedBox(height: 10),
                if (_h.observaciones.trim().isNotEmpty) ...[
                  _recuadro(
                    titulo: 'Observación del acta',
                    texto: _h.observaciones,
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: _seguCtrl,
                  maxLines: 4,
                  enabled: widget.canWrite,
                  decoration: const InputDecoration(
                    labelText: 'Seguimiento',
                    hintText:
                        'Compromisos, acciones tomadas o razón del retraso…',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: widget.canWrite ? _pickFecha : null,
                  borderRadius: BorderRadius.circular(8),
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Fecha de subsanación',
                      border: const OutlineInputBorder(),
                      suffixIcon: _fechaSub == null
                          ? const Icon(Icons.event_outlined)
                          : IconButton(
                              tooltip: 'Quitar fecha',
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: widget.canWrite
                                  ? () => setState(() => _fechaSub = null)
                                  : null,
                            ),
                    ),
                    child: Text(
                      _fechaSub == null
                          ? 'Sin subsanar'
                          : DateFormat('dd/MM/yyyy').format(_fechaSub!),
                      style: TextStyle(
                        color: _fechaSub == null ? _muted : _ink,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (widget.canWrite) _piePagina(),
        ],
      ),
    );
  }

  Widget _cabecera() {
    final numeral = _h.numeralParaMatriz;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 12, 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _borde)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(
              numeral.isNotEmpty ? numeral : _h.numeroHallazgo,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                color: _accent,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _h.centroCostoNombre,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _h.descripcion,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, height: 1.35),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Cerrar',
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }

  Widget _tituloBloque(String texto) => Text(
    texto.toUpperCase(),
    style: const TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w800,
      color: _muted,
      letterSpacing: .5,
    ),
  );

  Widget _recuadro({required String titulo, required String texto}) =>
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _borde),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              titulo,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: _muted,
              ),
            ),
            const SizedBox(height: 4),
            Text(texto, style: const TextStyle(fontSize: 13, height: 1.35)),
          ],
        ),
      );

  Widget _bloqueResponsable() {
    final porArea =
        _h.responsableNombre.trim().isEmpty &&
        _h.dptoEncargado.trim().isNotEmpty;
    final asignado = _h.responsableNombre.trim().isNotEmpty || porArea;
    final limite = _h.fechaLimite?.toDate();
    final vencido =
        !_h.isSubsanado && limite != null && limite.isBefore(DateTime.now());
    final sugerido = _usuarios.isEmpty
        ? null
        : widget.service.sugerirResponsable(_h, _usuarios);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: asignado ? _accent.withValues(alpha: .05) : const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: asignado ? _accent.withValues(alpha: .25) : _warn.withValues(alpha: .3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                asignado ? Icons.assignment_ind_outlined : Icons.person_off_outlined,
                size: 17,
                color: asignado ? _accent : _warn,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  porArea
                      ? 'Asignado a un área'
                      : asignado
                      ? 'Responsable'
                      : 'Sin responsable',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: asignado ? _accent : _warn,
                  ),
                ),
              ),
              if (limite != null)
                Text(
                  'Vence ${DateFormat('dd/MM/yy').format(limite)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: vencido ? _danger : _muted,
                    fontWeight: vencido ? FontWeight.w800 : FontWeight.normal,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (porArea)
            Text(
              '${_h.dptoEncargado} · la tarea quedó con el director del área. '
              'Puedes apuntarla a una persona concreta.',
              style: const TextStyle(fontSize: 13, height: 1.3),
            )
          else if (asignado)
            Text(
              _h.cargoResponsable.trim().isEmpty
                  ? _h.responsableNombre
                  : '${_h.responsableNombre} · ${_h.cargoResponsable}',
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
            )
          else if (sugerido != null)
            Text(
              'El acta lo asigna a ${sugerido.cargoMatriz}: ${sugerido.nombre}',
              style: const TextStyle(fontSize: 13),
            )
          else
            Text(
              _h.numeralParaMatriz.isEmpty
                  ? 'No se pudo identificar el numeral del acta. Elige tú el responsable.'
                  : 'Nadie tiene el cargo que responde por ${_h.numeralParaMatriz}.',
              style: const TextStyle(fontSize: 13),
            ),
          if (_h.aprobadorNombre.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Aprueba: ${_h.aprobadorNombre}'
              '${_h.cargoAprobador.isEmpty ? '' : ' · ${_h.cargoAprobador}'}',
              style: const TextStyle(fontSize: 12, color: _muted),
            ),
          ],
          if (widget.canWrite) ...[
            const SizedBox(height: 12),
            if (_asignando)
              const LinearProgressIndicator(minHeight: 3)
            else
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (!asignado && sugerido != null)
                    FilledButton.icon(
                      onPressed: () => _asignar(sugerido),
                      style: FilledButton.styleFrom(
                        backgroundColor: _accent,
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Icons.check_rounded, size: 16),
                      label: const Text(
                        'Asignar según el acta',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  OutlinedButton.icon(
                    onPressed: _elegirPersona,
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: Icon(
                      asignado
                          ? Icons.swap_horiz_rounded
                          : Icons.person_search_outlined,
                      size: 16,
                    ),
                    label: Text(
                      asignado ? 'Cambiar responsable' : 'Elegir persona',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  if (asignado)
                    TextButton.icon(
                      onPressed: _quitarAsignacion,
                      style: TextButton.styleFrom(
                        foregroundColor: _danger,
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Icons.person_remove_outlined, size: 16),
                      label: const Text(
                        'Quitar asignación',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                ],
              ),
          ],
        ],
      ),
    );
  }

  Widget _piePagina() => Container(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: _borde)),
    ),
    child: Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: _guardando ? null : _guardarSeguimiento,
            style: FilledButton.styleFrom(backgroundColor: _accent),
            icon: _guardando
                ? const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save_rounded, size: 18),
            label: const Text('Guardar seguimiento'),
          ),
        ),
      ],
    ),
  );

  Future<void> _pickFecha() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fechaSub ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) setState(() => _fechaSub = picked);
  }

  Future<void> _guardarSeguimiento() async {
    if (_h.id.isEmpty) {
      _aviso('Asigna primero un responsable para poder registrar seguimiento.');
      return;
    }
    setState(() => _guardando = true);
    try {
      await widget.service.actualizarSeguimientoHallazgo(
        hallazgoId: _h.id,
        seguimiento: _seguCtrl.text.trim(),
        fechaSubsanacion: _fechaSub == null
            ? null
            : Timestamp.fromDate(_fechaSub!),
      );
      if (mounted) Navigator.of(context).maybePop();
    } catch (e) {
      _aviso('No se pudo guardar: $e', error: true);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _elegirPersona() async {
    final sugerido = widget.service.sugerirResponsable(_h, _usuarios);
    final elegido = await showModalBottomSheet<InterventoriaUsuario>(
      context: context,
      isScrollControlled: true,
      builder: (_) => InterventoriaSelectorPersona(
        usuarios: _usuarios,
        sugeridoId: sugerido?.id ?? '',
        centroCostoId: _h.centroCostoId,
      ),
    );
    if (elegido == null) return;
    await _asignar(
      InterventoriaPersona(
        id: elegido.id,
        nombre: elegido.nombre,
        cargo: elegido.cargo,
        cargoMatriz: sugerido?.cargoMatriz ?? '',
        delCentro: elegido.centroId == _h.centroCostoId,
      ),
      forzado: true,
    );
  }

  Future<void> _asignar(
    InterventoriaPersona persona, {
    bool forzado = false,
  }) async {
    setState(() => _asignando = true);
    try {
      var hallazgo = _h;
      if (hallazgo.id.isEmpty) {
        final id = await widget.service.guardarHallazgo(hallazgo);
        hallazgo = hallazgo.copyWithId(id);
      }
      await widget.service.crearTareaYNotificarHallazgo(
        hallazgo: hallazgo,
        creadorId: widget.userId,
        creadorNombre: widget.userId,
        responsableForzado: forzado ? persona : null,
      );
      if (!mounted) return;
      // El panel no vive del stream, así que refleja el cambio de una vez.
      setState(() {
        _h = hallazgo.copyWith(
          responsableId: persona.id,
          responsableNombre: persona.nombre,
          cargoResponsable: forzado ? persona.cargo : persona.cargoMatriz,
        );
      });
      _aviso('Asignado a ${persona.nombre}');
    } catch (e) {
      _aviso('No se pudo asignar: $e', error: true);
    } finally {
      if (mounted) setState(() => _asignando = false);
    }
  }

  Future<void> _quitarAsignacion() async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Quitar asignación'),
        content: Text(
          'Se eliminará la tarea de '
          '${_h.responsableNombre.trim().isEmpty ? _h.dptoEncargado : _h.responsableNombre}'
          ' y el hallazgo volverá a "Sin asignar". El seguimiento y las '
          'observaciones se conservan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _danger),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Sí, quitar'),
          ),
        ],
      ),
    );
    if (confirmado != true) return;
    setState(() => _asignando = true);
    try {
      await widget.service.quitarAsignacionHallazgo(
        hallazgoId: _h.id,
        tareaId: _h.tareaId,
      );
      if (!mounted) return;
      setState(() {
        _h = _h.copyWith(
          tareaId: '',
          responsableId: '',
          responsableNombre: '',
          cargoResponsable: '',
          aprobadorId: '',
          aprobadorNombre: '',
          cargoAprobador: '',
          dptoEncargado: '',
          areaId: '',
        );
      });
      _aviso('Asignación retirada');
    } catch (e) {
      _aviso('No se pudo quitar: $e', error: true);
    } finally {
      if (mounted) setState(() => _asignando = false);
    }
  }

  void _aviso(String texto, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texto),
        backgroundColor: error ? _danger : _ok,
      ),
    );
  }
}

/// Lo que el responsable ha publicado en la tarea: estado, avances y
/// evidencias. Es la respuesta a "¿cómo va esto?" sin salir del hallazgo.
class _AvanceDeTarea extends StatelessWidget {
  final String tareaId;
  const _AvanceDeTarea({required this.tareaId});

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borde),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: db.collection('TBL_TAREAS').doc(tareaId).snapshots(),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Text(
                  'Cargando tarea…',
                  style: TextStyle(fontSize: 12, color: _muted),
                );
              }
              if (!snap.data!.exists) {
                return const Text(
                  'La tarea ya no existe.',
                  style: TextStyle(fontSize: 12, color: _warn),
                );
              }
              final data = snap.data!.data() ?? const <String, dynamic>{};
              final estado = (data['estado'] ?? data['status'] ?? '')
                  .toString();
              final adjuntos = (data['adjuntos'] as List? ?? const []).length;
              return Row(
                children: [
                  _chipEstadoTarea(estado),
                  const SizedBox(width: 8),
                  if (adjuntos > 0) ...[
                    const Icon(Icons.attach_file, size: 13, color: _muted),
                    Text(
                      '$adjuntos',
                      style: const TextStyle(fontSize: 12, color: _muted),
                    ),
                  ],
                  const Spacer(),
                  Text(
                    (data['asignado_nombre'] ?? '').toString(),
                    style: const TextStyle(fontSize: 11, color: _muted),
                  ),
                ],
              );
            },
          ),
          const Divider(height: 18),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: db
                .collection('TBL_TAREAS')
                .doc(tareaId)
                .collection('avances')
                .snapshots(),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Text(
                  'Cargando avances…',
                  style: TextStyle(fontSize: 12, color: _muted),
                );
              }
              final docs = snap.data!.docs.toList()
                ..sort((a, b) {
                  final ta = a.data()['createdAt'];
                  final tb = b.data()['createdAt'];
                  if (ta is Timestamp && tb is Timestamp) {
                    return tb.compareTo(ta);
                  }
                  return 0;
                });
              if (docs.isEmpty) {
                return const Text(
                  'El responsable aún no ha publicado avances.',
                  style: TextStyle(fontSize: 12.5, color: _muted),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: docs.take(6).map((doc) {
                  final d = doc.data();
                  final fecha = d['createdAt'];
                  final adjuntos =
                      (d['attachments'] as List? ?? const []).length;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.trending_up_rounded,
                              size: 13,
                              color: _accent,
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                (d['byName'] ?? d['by'] ?? '').toString(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (adjuntos > 0) ...[
                              const Icon(
                                Icons.attach_file,
                                size: 12,
                                color: _muted,
                              ),
                              Text(
                                '$adjuntos',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: _muted,
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
                            if (fecha is Timestamp)
                              Text(
                                DateFormat('dd/MM/yy').format(fecha.toDate()),
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: _muted,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          (d['message'] ?? '').toString(),
                          style: const TextStyle(fontSize: 12.5, height: 1.3),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _chipEstadoTarea(String estado) {
    final (texto, color) = switch (estado.toLowerCase()) {
      'finalizado' => ('Finalizada', _ok),
      'por_aprobar' => ('Por aprobar', _warn),
      'en_progreso' => ('En progreso', _accent),
      'pendiente' => ('Pendiente', _muted),
      _ => (estado.isEmpty ? 'Sin estado' : estado, _muted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        texto,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}
