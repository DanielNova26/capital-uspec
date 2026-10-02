import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../core/user_directory.dart';
import '../widgets/internal_module_layout.dart';
import '../widgets/memo_stream_builder.dart';
import '../widgets/paged_list.dart';
import '../widgets/user_avatar.dart';
import 'interventoria_models.dart';
import 'interventoria_service.dart';

const Color _kAccent = Color(0xFF0F766E);
const Color _kOk = Color(0xFF16A34A);
const Color _kWarn = Color(0xFFB45309);
const Color _kDanger = Color(0xFFDC2626);
const Color _kMuted = Color(0xFF64748B);
const String _kFont = 'Arial';

Color _colorConcepto(String concepto) => switch (concepto) {
  kConceptoFavorable => _kOk,
  kConceptoFavorableRequerimientos => _kWarn,
  kConceptoDesfavorable => _kDanger,
  _ => _kMuted,
};

/// Sección "Concepto sanitario" de Interventoría (28 sep 2026).
///
/// Guarda el acta de concepto higiénico sanitario que emite la autoridad de
/// salud: establecimiento, fecha, puntaje y concepto, y el archivo si se
/// tiene. No genera hallazgos ni tareas: es el registro del concepto vigente.
///
/// Web muestra una tabla con filtros; móvil, tarjetas. La lógica, los
/// permisos y el servicio son los mismos.
class InterventoriaConceptosSanitariosTab extends StatefulWidget {
  final InterventoriaService service;
  final String empresaId;
  final String userId;

  /// Registrar y corregir: los roles con escritura del módulo.
  final bool canEdit;

  /// Borrar: administración, gerencia y Desarrollo (las reglas lo exigen).
  final bool canDelete;

  /// El registrador queda fijo a su establecimiento.
  final String? centroFijoId;

  const InterventoriaConceptosSanitariosTab({
    super.key,
    required this.service,
    required this.empresaId,
    required this.userId,
    required this.canEdit,
    required this.canDelete,
    this.centroFijoId,
  });

  @override
  State<InterventoriaConceptosSanitariosTab> createState() =>
      _InterventoriaConceptosSanitariosTabState();
}

class _InterventoriaConceptosSanitariosTabState
    extends State<InterventoriaConceptosSanitariosTab> {
  String _centroFiltro = '';
  String _conceptoFiltro = '';
  bool _soloVigentes = false;

  String? get _centroFijo {
    final id = widget.centroFijoId?.trim() ?? '';
    return id.isEmpty ? null : id;
  }

  Future<void> _abrirFormulario({
    InterventoriaConceptoSanitario? editar,
  }) async {
    final ancho = MediaQuery.sizeOf(context).width >= 760;
    final form = _ConceptoSanitarioForm(
      service: widget.service,
      empresaId: widget.empresaId,
      userId: widget.userId,
      centroFijoId: _centroFijo,
      editar: editar,
    );
    final guardado = ancho
        ? await showDialog<bool>(
            context: context,
            builder: (_) => Dialog(
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: form,
              ),
            ),
          )
        : await showModalBottomSheet<bool>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            builder: (_) => Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: form,
            ),
          );
    if (guardado == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: _kOk,
          content: Text('Concepto sanitario guardado'),
        ),
      );
    }
  }

  Future<void> _eliminar(InterventoriaConceptoSanitario c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar concepto sanitario'),
        content: Text(
          'Se eliminará el concepto de ${c.centroCostoNombre} del '
          '${DateFormat('dd/MM/yyyy').format(c.fecha)} y su archivo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _kDanger),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await widget.service.eliminarConceptoSanitario(c);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: _kDanger,
          content: Text('No se pudo eliminar: $e'),
        ),
      );
    }
  }

  void _abrirActa(InterventoriaConceptoSanitario c) {
    final url = c.acta?.url ?? '';
    if (url.isEmpty) return;
    launchUrlString(url, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return MemoStreamBuilder<List<InterventoriaConceptoSanitario>>(
      memoKey: (widget.empresaId, _centroFijo),
      create: () => widget.service.streamConceptosSanitarios(
        widget.empresaId,
        centroId: _centroFijo,
      ),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'No se pudieron cargar los conceptos sanitarios: ${snap.error}',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final todos = snap.data!;
        final vigentes = conceptoVigentePorEstablecimiento(todos);
        final centros = <String, String>{
          for (final c in todos) c.centroCostoId: c.centroCostoNombre,
        };
        final filtrados = todos.where((c) {
          if (_centroFiltro.isNotEmpty && c.centroCostoId != _centroFiltro) {
            return false;
          }
          if (_conceptoFiltro.isNotEmpty && c.concepto != _conceptoFiltro) {
            return false;
          }
          if (_soloVigentes && vigentes[c.centroCostoId]?.id != c.id) {
            return false;
          }
          return true;
        }).toList();

        return InternalModuleViewport(
          maxWidth: 1400,
          padding: EdgeInsets.zero,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final esMovil = constraints.maxWidth < 900;
              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _cabecera(esMovil),
                    const SizedBox(height: 12),
                    _filtros(esMovil, centros),
                    const SizedBox(height: 12),
                    if (filtrados.isEmpty)
                      _vacio(todos.isEmpty)
                    else if (esMovil)
                      PagedListSection<InterventoriaConceptoSanitario>(
                        items: filtrados,
                        etiqueta: 'conceptos',
                        separator: const SizedBox(height: 10),
                        itemBuilder: (context, c, _) => _tarjeta(
                          c,
                          vigente: vigentes[c.centroCostoId]?.id == c.id,
                        ),
                      )
                    else
                      _tabla(filtrados, vigentes),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _cabecera(bool esMovil) {
    final titulo = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Concepto higiénico sanitario',
          style: TextStyle(
            fontFamily: _kFont,
            fontWeight: FontWeight.w900,
            fontSize: esMovil ? 16 : 18,
          ),
        ),
        const SizedBox(height: 2),
        const Text(
          'Actas de la autoridad sanitaria: establecimiento, fecha, puntaje '
          'y concepto.',
          style: TextStyle(fontSize: 12, color: _kMuted),
        ),
      ],
    );
    final boton = widget.canEdit
        ? FilledButton.icon(
            onPressed: () => _abrirFormulario(),
            style: FilledButton.styleFrom(backgroundColor: _kAccent),
            icon: const Icon(Icons.upload_file_rounded, size: 18),
            label: const Text('Subir concepto'),
          )
        : null;
    if (esMovil) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          titulo,
          if (boton != null) ...[const SizedBox(height: 10), boton],
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: titulo),
        ?boton,
      ],
    );
  }

  Widget _filtros(bool esMovil, Map<String, String> centros) {
    final ordenados = centros.entries.toList()
      ..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));
    final porCentro = _centroFijo != null
        ? null
        : DropdownButtonFormField<String>(
            key: ValueKey('centro-$_centroFiltro-${centros.length}'),
            initialValue: centros.containsKey(_centroFiltro)
                ? _centroFiltro
                : '',
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Establecimiento',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              const DropdownMenuItem(value: '', child: Text('Todos')),
              for (final e in ordenados)
                DropdownMenuItem(
                  value: e.key,
                  child: Text(e.value, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) => setState(() => _centroFiltro = v ?? ''),
          );
    final porConcepto = DropdownButtonFormField<String>(
      key: ValueKey('concepto-$_conceptoFiltro'),
      initialValue: _conceptoFiltro,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Concepto',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      items: [
        const DropdownMenuItem(value: '', child: Text('Todos')),
        for (final c in kConceptosSanitarios)
          DropdownMenuItem(value: c, child: Text(etiquetaConceptoSanitario(c))),
      ],
      onChanged: (v) => setState(() => _conceptoFiltro = v ?? ''),
    );
    final vigentes = FilterChip(
      selected: _soloVigentes,
      label: const Text('Solo el vigente de cada sede'),
      onSelected: (v) => setState(() => _soloVigentes = v),
    );
    if (esMovil) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (porCentro != null) ...[porCentro, const SizedBox(height: 8)],
          porConcepto,
          const SizedBox(height: 6),
          Align(alignment: Alignment.centerLeft, child: vigentes),
        ],
      );
    }
    return Wrap(
      spacing: 12,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (porCentro != null) SizedBox(width: 280, child: porCentro),
        SizedBox(width: 260, child: porConcepto),
        vigentes,
      ],
    );
  }

  Widget _vacio(bool sinRegistros) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 48),
    child: Column(
      children: [
        const Icon(Icons.health_and_safety_outlined, size: 48, color: _kMuted),
        const SizedBox(height: 10),
        Text(
          sinRegistros
              ? 'Todavía no hay conceptos sanitarios registrados.'
              : 'Ningún concepto coincide con los filtros.',
          style: const TextStyle(color: _kMuted),
        ),
      ],
    ),
  );

  Widget _chipConcepto(String concepto) {
    final color = _colorConcepto(concepto);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        etiquetaConceptoSanitario(concepto),
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }

  Widget _puntaje(double puntaje) => Text(
    '${puntaje.toStringAsFixed(puntaje == puntaje.roundToDouble() ? 0 : 1)}%',
    style: TextStyle(
      fontWeight: FontWeight.w900,
      color: puntaje >= 90 ? _kOk : (puntaje >= 70 ? _kWarn : _kDanger),
    ),
  );

  Widget _acciones(InterventoriaConceptoSanitario c) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (c.acta != null)
        IconButton(
          tooltip: 'Ver acta',
          icon: const Icon(Icons.picture_as_pdf_outlined, size: 20),
          onPressed: () => _abrirActa(c),
        ),
      if (widget.canEdit)
        IconButton(
          tooltip: 'Corregir',
          icon: const Icon(Icons.edit_outlined, size: 20),
          onPressed: () => _abrirFormulario(editar: c),
        ),
      if (widget.canDelete)
        IconButton(
          tooltip: 'Eliminar',
          icon: const Icon(Icons.delete_outline, size: 20, color: _kDanger),
          onPressed: () => _eliminar(c),
        ),
    ],
  );

  Widget _tabla(
    List<InterventoriaConceptoSanitario> filas,
    Map<String, InterventoriaConceptoSanitario> vigentes,
  ) {
    final fmt = DateFormat('dd/MM/yyyy');
    return Card(
      margin: EdgeInsets.zero,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: PagedDataTable(
          etiqueta: 'conceptos',
          tabla: DataTable(
            headingRowColor: WidgetStateProperty.all(const Color(0xFFF1F5F9)),
            columns: const [
              DataColumn(label: Text('Establecimiento')),
              DataColumn(label: Text('Fecha')),
              DataColumn(label: Text('Puntaje'), numeric: true),
              DataColumn(label: Text('Concepto')),
              DataColumn(label: Text('Registró')),
              DataColumn(label: Text('')),
            ],
            rows: [
              for (final c in filas)
                DataRow(
                  cells: [
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            c.centroCostoNombre,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          if (vigentes[c.centroCostoId]?.id == c.id) ...[
                            const SizedBox(width: 6),
                            const Tooltip(
                              message: 'Concepto vigente de la sede',
                              child: Icon(
                                Icons.verified_rounded,
                                size: 16,
                                color: _kAccent,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    DataCell(Text(fmt.format(c.fecha))),
                    DataCell(_puntaje(c.puntaje)),
                    DataCell(_chipConcepto(c.concepto)),
                    DataCell(
                      c.registradoPor.isEmpty
                          ? const Text('—')
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                UserAvatar(
                                  userId: c.registradoPor,
                                  nameHint: c.registradoPorNombre,
                                  radius: 12,
                                ),
                                const SizedBox(width: 6),
                                UserNameText(
                                  c.registradoPor,
                                  fallbackName: c.registradoPorNombre,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                    ),
                    DataCell(_acciones(c)),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjeta(InterventoriaConceptoSanitario c, {required bool vigente}) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    c.centroCostoNombre,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ),
                _puntaje(c.puntaje),
                const SizedBox(width: 8),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _chipConcepto(c.concepto),
                Text(
                  DateFormat('dd/MM/yyyy').format(c.fecha),
                  style: const TextStyle(fontSize: 12, color: _kMuted),
                ),
                if (vigente)
                  const Text(
                    'Vigente',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: _kAccent,
                    ),
                  ),
              ],
            ),
            Align(alignment: Alignment.centerRight, child: _acciones(c)),
          ],
        ),
      ),
    );
  }
}

/// Formulario de carga: solo los cuatro datos del acta y el archivo.
class _ConceptoSanitarioForm extends StatefulWidget {
  final InterventoriaService service;
  final String empresaId;
  final String userId;
  final String? centroFijoId;
  final InterventoriaConceptoSanitario? editar;

  const _ConceptoSanitarioForm({
    required this.service,
    required this.empresaId,
    required this.userId,
    required this.centroFijoId,
    this.editar,
  });

  @override
  State<_ConceptoSanitarioForm> createState() => _ConceptoSanitarioFormState();
}

class _ConceptoSanitarioFormState extends State<_ConceptoSanitarioForm> {
  late String _centroId =
      widget.editar?.centroCostoId ?? widget.centroFijoId ?? '';
  late String _centroNombre = widget.editar?.centroCostoNombre ?? '';
  late DateTime? _fecha = widget.editar?.fecha;
  late final TextEditingController _puntajeCtrl = TextEditingController(
    text: widget.editar == null
        ? ''
        : widget.editar!.puntaje.toStringAsFixed(
            widget.editar!.puntaje == widget.editar!.puntaje.roundToDouble()
                ? 0
                : 1,
          ),
  );
  late String _concepto = widget.editar?.concepto ?? '';
  Uint8List? _archivo;
  String _archivoNombre = '';
  String _archivoTipo = '';
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _puntajeCtrl.dispose();
    super.dispose();
  }

  double? get _puntaje =>
      double.tryParse(_puntajeCtrl.text.trim().replaceAll(',', '.'));

  Future<void> _elegirFecha() async {
    final hoy = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _fecha ?? hoy,
      firstDate: DateTime(2020),
      lastDate: hoy,
    );
    if (picked != null) setState(() => _fecha = picked);
  }

  Future<void> _elegirArchivo() async {
    final res = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
    );
    final f = res?.files.firstOrNull;
    if (f == null || f.bytes == null) return;
    setState(() {
      _archivo = f.bytes;
      _archivoNombre = f.name;
      _archivoTipo = switch ((f.extension ?? '').toLowerCase()) {
        'pdf' => 'application/pdf',
        'png' => 'image/png',
        _ => 'image/jpeg',
      };
    });
  }

  Future<void> _guardar() async {
    final error = validarConceptoSanitario(
      centroCostoId: _centroId,
      fecha: _fecha,
      puntaje: _puntaje,
      concepto: _concepto,
      hoy: DateTime.now(),
    );
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      final editar = widget.editar;
      var registradoPor = editar?.registradoPor ?? '';
      var registradoPorNombre = editar?.registradoPorNombre ?? '';
      if (registradoPor.isEmpty) {
        registradoPor = widget.userId;
        registradoPorNombre =
            (await UserDirectory.instance.resolve(widget.userId)).nombre;
      }
      await widget.service.guardarConceptoSanitario(
        InterventoriaConceptoSanitario(
          id: editar?.id ?? '',
          empresaId: widget.empresaId,
          centroCostoId: _centroId,
          centroCostoNombre: _centroNombre,
          fecha: _fecha!,
          puntaje: _puntaje!,
          concepto: _concepto,
          acta: editar?.acta,
          registradoPor: registradoPor,
          registradoPorNombre: registradoPorNombre,
        ),
        archivo: _archivo,
        archivoNombre: _archivoNombre,
        archivoTipo: _archivoTipo,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _guardando = false;
          _error = 'No se pudo guardar: $e';
        });
      }
    }
  }

  Widget _selectorEstablecimiento() {
    return MemoStreamBuilder<List<CentroCostoRef>>(
      memoKey: widget.empresaId,
      create: () => widget.service.streamCentrosCosto(widget.empresaId),
      builder: (context, snap) {
        final centros = snap.data ?? const <CentroCostoRef>[];
        final porId = {for (final c in centros) c.centroId: c};
        // Una sede que se deshabilitó después conserva su registro.
        if (_centroId.isNotEmpty && !porId.containsKey(_centroId)) {
          porId[_centroId] = CentroCostoRef(
            centroId: _centroId,
            empresaId: widget.empresaId,
            codigo: '',
            nombre: _centroNombre.isEmpty ? 'Establecimiento' : _centroNombre,
          );
        }
        if (_centroNombre.isEmpty && porId[_centroId] != null) {
          _centroNombre = porId[_centroId]!.nombre;
        }
        final fijo = (widget.centroFijoId ?? '').isNotEmpty;
        return DropdownButtonFormField<String>(
          key: ValueKey('$_centroId-${porId.length}'),
          initialValue: _centroId.isEmpty ? null : _centroId,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Establecimiento',
            prefixIcon: Icon(Icons.store_mall_directory_outlined),
            border: OutlineInputBorder(),
          ),
          items: [
            for (final grupo in agruparCentrosCosto(porId.values)) ...[
              DropdownMenuItem<String>(
                enabled: false,
                child: Text(
                  grupo.label.toUpperCase(),
                  style: const TextStyle(
                    color: _kAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              for (final c in grupo.centros)
                DropdownMenuItem(
                  value: c.centroId,
                  child: Text(c.nombre, overflow: TextOverflow.ellipsis),
                ),
            ],
          ],
          onChanged: fijo || _guardando
              ? null
              : (v) => setState(() {
                  _centroId = v ?? '';
                  _centroNombre = porId[_centroId]?.nombre ?? '';
                }),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final editando = widget.editar != null;
    return Material(
      color: Colors.white,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    editando
                        ? 'Corregir concepto sanitario'
                        : 'Subir concepto sanitario',
                    style: const TextStyle(
                      fontFamily: _kFont,
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Cerrar',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: _guardando
                      ? null
                      : () => Navigator.of(context).pop(false),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _selectorEstablecimiento(),
            const SizedBox(height: 12),
            InkWell(
              onTap: _guardando ? null : _elegirFecha,
              borderRadius: BorderRadius.circular(4),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Fecha del acta',
                  prefixIcon: Icon(Icons.event_outlined),
                  border: OutlineInputBorder(),
                ),
                child: Text(
                  _fecha == null
                      ? 'Elegir fecha'
                      : DateFormat('dd/MM/yyyy').format(_fecha!),
                  style: TextStyle(color: _fecha == null ? _kMuted : null),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _puntajeCtrl,
              enabled: !_guardando,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              decoration: const InputDecoration(
                labelText: 'Puntaje',
                hintText: '0 a 100',
                suffixText: '%',
                prefixIcon: Icon(Icons.percent_rounded),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _concepto.isEmpty ? null : _concepto,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Concepto',
                prefixIcon: Icon(Icons.health_and_safety_outlined),
                border: OutlineInputBorder(),
              ),
              items: [
                for (final c in kConceptosSanitarios)
                  DropdownMenuItem(
                    value: c,
                    child: Text(etiquetaConceptoSanitario(c)),
                  ),
              ],
              onChanged: _guardando
                  ? null
                  : (v) => setState(() => _concepto = v ?? ''),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _guardando ? null : _elegirArchivo,
              icon: const Icon(Icons.attach_file_rounded, size: 18),
              label: Text(
                _archivoNombre.isNotEmpty
                    ? _archivoNombre
                    : (widget.editar?.acta != null
                          ? 'Reemplazar el acta (${widget.editar!.acta!.nombre})'
                          : 'Adjuntar el acta (PDF o imagen, opcional)'),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: _kDanger)),
            ],
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _guardando ? null : _guardar,
              style: FilledButton.styleFrom(
                backgroundColor: _kAccent,
                minimumSize: const Size.fromHeight(46),
              ),
              icon: _guardando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save_rounded, size: 18),
              label: Text(_guardando ? 'Guardando…' : 'Guardar'),
            ),
          ],
        ),
      ),
    );
  }
}
