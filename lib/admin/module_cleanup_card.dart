// "Borrar datos de prueba" de un módulo: elegir periodo, ver cuánto se
// borraría por colección y confirmar escribiendo BORRAR. Todo en la empresa
// activa; el servidor lo vuelve a comprobar y lo deja en Logs.
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_typography.dart';
import 'module_cleanup_service.dart';

/// Confirmación fuerte: muestra qué se borra y exige escribir BORRAR.
Future<bool> confirmarBorrado(
  BuildContext context, {
  required String titulo,
  required String detalle,
  required String boton,
}) async {
  var escrito = '';
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: Text(
          titulo,
          style: const TextStyle(
            fontFamily: kArial,
            fontWeight: FontWeight.w900,
          ),
        ),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(detalle, style: const TextStyle(fontFamily: kArial)),
                const SizedBox(height: 12),
                const Text(
                  'No se puede deshacer. Escribe BORRAR para confirmar:',
                  style: TextStyle(
                    fontFamily: kArial,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  autofocus: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (v) => setLocal(() => escrito = v),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB91C1C),
            ),
            onPressed: escrito.trim().toUpperCase() == 'BORRAR'
                ? () => Navigator.pop(ctx, true)
                : null,
            icon: const Icon(Icons.delete_forever),
            label: Text(boton),
          ),
        ],
      ),
    ),
  );
  return ok == true;
}

class ModuleTestDataCleanupCard extends StatefulWidget {
  const ModuleTestDataCleanupCard({
    super.key,
    required this.empresaId,
    required this.modulo,
    this.service,
    this.onBorrado,
  });

  final String empresaId;
  final ModuloLimpiezaInfo modulo;
  final ModuleCleanupService? service;
  final Future<void> Function()? onBorrado;

  @override
  State<ModuleTestDataCleanupCard> createState() =>
      _ModuleTestDataCleanupCardState();
}

class _ModuleTestDataCleanupCardState extends State<ModuleTestDataCleanupCard> {
  late final ModuleCleanupService _service =
      widget.service ?? ModuleCleanupService();
  final _fmt = DateFormat('dd/MM/yyyy');
  ModoPeriodo _modo = ModoPeriodo.todo;
  DateTime? _desde;
  DateTime? _hasta;
  bool _incluirMaestros = false;
  bool _ocupado = false;
  VistaLimpieza? _vista;

  PeriodoLimpieza get _periodo =>
      PeriodoLimpieza(_modo, desde: _desde, hasta: _hasta);

  void _cambio(VoidCallback f) => setState(() {
    f();
    _vista = null;
  });

  Future<void> _elegirFecha({required bool inicio}) async {
    final actual = (inicio ? _desde : _hasta) ?? DateTime.now();
    final elegida = await showDatePicker(
      context: context,
      initialDate: actual,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (elegida == null) return;
    _cambio(() => inicio ? _desde = elegida : _hasta = elegida);
  }

  void _mensaje(String texto, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texto),
        backgroundColor: error ? const Color(0xFFB91C1C) : null,
      ),
    );
  }

  Future<void> _previsualizar() async {
    if (!_periodo.completo) {
      _mensaje('Elige las fechas del periodo.', error: true);
      return;
    }
    setState(() => _ocupado = true);
    try {
      final vista = await _service.previsualizar(
        empresaId: widget.empresaId,
        modulo: widget.modulo.id,
        periodo: _periodo,
        incluirMaestros: _incluirMaestros,
      );
      if (mounted) setState(() => _vista = vista);
    } on FirebaseFunctionsException catch (e) {
      if (mounted) _mensaje(e.message ?? 'No se pudo calcular.', error: true);
    } catch (e) {
      if (mounted) _mensaje('No se pudo calcular: $e', error: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _borrar() async {
    final vista = _vista;
    if (vista == null || vista.total == 0) return;
    final partes = [
      for (final c in vista.colecciones)
        if (c.total > 0) '• ${c.nombre}: ${c.total}',
      if (vista.tareas > 0) '• Tareas: ${vista.tareas}',
      if (vista.notificaciones > 0) '• Notificaciones: ${vista.notificaciones}',
    ].join('\n');
    final ok = await confirmarBorrado(
      context,
      titulo: 'Borrar datos de ${widget.modulo.nombre}',
      detalle:
          'Empresa activa, periodo: ${_periodo.descripcion(_fmt.format)}.\n\n'
          '$partes\n\nLos archivos adjuntos (fotos, PDF) no se borran.',
      boton: 'Borrar ${vista.total}',
    );
    if (!ok || !mounted) return;
    setState(() => _ocupado = true);
    try {
      final resultado = await _service.borrar(
        empresaId: widget.empresaId,
        modulo: widget.modulo.id,
        periodo: _periodo,
        incluirMaestros: _incluirMaestros,
      );
      if (!mounted) return;
      setState(() => _vista = null);
      _mensaje(
        resultado.fallidos == 0
            ? '${widget.modulo.nombre}: ${resultado.total} registro(s) '
                  'borrados. Quedó en Logs.'
            : '${widget.modulo.nombre}: ${resultado.total - resultado.fallidos} '
                  'borrados; ${resultado.fallidos} no se pudieron. Repite la '
                  'limpieza.',
        error: resultado.fallidos > 0,
      );
      await widget.onBorrado?.call();
    } on FirebaseFunctionsException catch (e) {
      if (mounted) _mensaje(e.message ?? 'No se pudo borrar.', error: true);
    } catch (e) {
      if (mounted) _mensaje('No se pudo borrar: $e', error: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vista = _vista;
    return Card(
      color: const Color(0xFFFEF2F2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFFECACA)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.delete_sweep_outlined,
                  color: Color(0xFFB91C1C),
                  size: 28,
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Borrar datos de prueba',
                    style: TextStyle(
                      fontFamily: kArial,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF7F1D1D),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${widget.modulo.descripcion} Solo de la empresa activa; '
              'primero muestra cuánto se borraría.',
              style: const TextStyle(fontFamily: kArial, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 240,
                  child: DropdownButtonFormField<ModoPeriodo>(
                    initialValue: _modo,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Periodo',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      for (final m in ModoPeriodo.values)
                        DropdownMenuItem(value: m, child: Text(m.etiqueta)),
                    ],
                    onChanged: _ocupado
                        ? null
                        : (m) => _cambio(() => _modo = m ?? ModoPeriodo.todo),
                  ),
                ),
                if (_modo != ModoPeriodo.todo)
                  OutlinedButton.icon(
                    onPressed: _ocupado
                        ? null
                        : () => _elegirFecha(inicio: true),
                    icon: const Icon(Icons.calendar_month_rounded),
                    label: Text(
                      _desde == null
                          ? (_modo == ModoPeriodo.entre
                                ? 'Desde…'
                                : 'Elegir fecha')
                          : _fmt.format(_desde!),
                    ),
                  ),
                if (_modo == ModoPeriodo.entre)
                  OutlinedButton.icon(
                    onPressed: _ocupado
                        ? null
                        : () => _elegirFecha(inicio: false),
                    icon: const Icon(Icons.calendar_month_rounded),
                    label: Text(
                      _hasta == null ? 'Hasta…' : _fmt.format(_hasta!),
                    ),
                  ),
              ],
            ),
            if (widget.modulo.maestros) ...[
              const SizedBox(height: 6),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _incluirMaestros,
                onChanged: _ocupado
                    ? null
                    : (v) => _cambio(() => _incluirMaestros = v),
                title: const Text('Incluir maestros y configuración'),
                subtitle: const Text(
                  'Solo si también fueron de prueba: el módulo los usa para '
                  'trabajar.',
                ),
              ),
            ],
            if (vista != null) ...[const SizedBox(height: 8), _resumen(vista)],
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: _ocupado ? null : _previsualizar,
                  icon: _ocupado
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.manage_search_rounded),
                  label: const Text('Ver qué se borraría'),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFB91C1C),
                  ),
                  onPressed: _ocupado || vista == null || vista.total == 0
                      ? null
                      : _borrar,
                  icon: const Icon(Icons.delete_forever),
                  label: Text(
                    vista == null ? 'Borrar' : 'Borrar ${vista.total}',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _resumen(VistaLimpieza vista) {
    Widget fila(
      String nombre,
      int total, {
      String? nota,
      bool maestro = false,
    }) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$nombre${maestro ? ' (maestro)' : ''}',
              style: const TextStyle(fontFamily: kArial),
            ),
          ),
          if (nota != null)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Text(
                nota,
                style: const TextStyle(
                  fontFamily: kArial,
                  fontSize: 11,
                  color: Color(0xFF64748B),
                ),
              ),
            ),
          Text(
            '$total',
            style: const TextStyle(
              fontFamily: kArial,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final c in vista.colecciones)
            fila(
              c.nombre,
              c.total,
              maestro: c.maestro,
              nota: c.sinFecha > 0 ? '${c.sinFecha} sin fecha' : null,
            ),
          if (vista.colecciones.isEmpty || vista.tareas > 0)
            fila(
              'Tareas del módulo',
              vista.tareas,
              nota: vista.tareasSinFecha > 0
                  ? '${vista.tareasSinFecha} sin fecha'
                  : null,
            ),
          fila('Notificaciones del módulo', vista.notificaciones),
          const Divider(),
          Text(
            vista.total == 0
                ? 'No hay nada que borrar en este periodo.'
                : 'Se borrarían ${vista.total} registro(s).',
            style: const TextStyle(
              fontFamily: kArial,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (vista.sinFecha > 0 && _modo != ModoPeriodo.todo)
            Text(
              '${vista.sinFecha} registro(s) no tienen fecha: con un periodo no '
              'se borran. Para incluirlos, elige "Todo lo de esta empresa".',
              style: const TextStyle(
                fontFamily: kArial,
                fontSize: 12,
                color: Color(0xFF64748B),
              ),
            ),
        ],
      ),
    );
  }
}
