// "Copiar a otras empresas" de un módulo (Admin › Maestros por módulo):
// elegir empresas destino y maestros, ver qué se copiaría y copiar solo lo
// que falta. El servidor exige ser Administración en la empresa activa y
// en cada destino, y lo deja en Logs de ambas.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../theme/app_typography.dart';
import 'maestros_sync_service.dart';
import 'task_module_role.dart' show canManageModuleRoles;

/// Una empresa del grupo, para elegirla como destino.
typedef EmpresaDestino = ({String id, String nombre});

/// Empresas a las que se puede copiar: todas menos la activa, con las que
/// administra primero.
List<({EmpresaDestino empresa, bool administra})> destinosPosibles({
  required List<EmpresaDestino> empresas,
  required String empresaActiva,
  required Map<String, dynamic>? actor,
}) {
  final out = [
    for (final e in empresas)
      if (e.id.trim().isNotEmpty && e.id != empresaActiva)
        (
          empresa: e,
          administra: actor != null && canManageModuleRoles(actor, e.id),
        ),
  ];
  out.sort((a, b) {
    if (a.administra != b.administra) return a.administra ? -1 : 1;
    return a.empresa.nombre.toLowerCase().compareTo(
      b.empresa.nombre.toLowerCase(),
    );
  });
  return out;
}

class MaestrosSyncCard extends StatefulWidget {
  const MaestrosSyncCard({
    super.key,
    required this.userId,
    required this.empresaId,
    required this.modulo,
    required this.empresas,
    this.service,
    this.db,
  });

  final String userId;
  final String empresaId;
  final ModuloMaestrosInfo modulo;
  final List<EmpresaDestino> empresas;
  final MaestrosSyncService? service;
  final FirebaseFirestore? db;

  @override
  State<MaestrosSyncCard> createState() => _MaestrosSyncCardState();
}

class _MaestrosSyncCardState extends State<MaestrosSyncCard> {
  late final MaestrosSyncService _service =
      widget.service ?? MaestrosSyncService();
  Map<String, dynamic>? _actor;
  final Set<String> _destinos = {};
  late Set<String> _maestros = {for (final m in widget.modulo.maestros) m.id};
  bool _ocupado = false;
  VistaSincronizacion? _vista;

  @override
  void initState() {
    super.initState();
    _cargarActor();
  }

  Future<void> _cargarActor() async {
    try {
      final snap = await (widget.db ?? FirebaseFirestore.instance)
          .collection('TBL_USUARIOS')
          .doc(widget.userId)
          .get();
      if (mounted) setState(() => _actor = snap.data() ?? const {});
    } catch (_) {
      if (mounted) setState(() => _actor = const {});
    }
  }

  void _cambio(VoidCallback f) => setState(() {
    f();
    _vista = null;
  });

  void _mensaje(String texto, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texto),
        backgroundColor: error ? const Color(0xFFB91C1C) : null,
      ),
    );
  }

  List<String> get _maestrosElegidos => [
    for (final m in widget.modulo.maestros)
      if (_maestros.contains(m.id)) m.id,
  ];

  Future<void> _previsualizar() async {
    if (_destinos.isEmpty || _maestros.isEmpty) return;
    setState(() => _ocupado = true);
    try {
      final vista = await _service.previsualizar(
        empresaId: widget.empresaId,
        modulo: widget.modulo.id,
        destinos: _destinos.toList(),
        maestros: _maestrosElegidos,
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

  Future<void> _copiar() async {
    final vista = _vista;
    if (vista == null || vista.porCopiar == 0) return;
    final detalle = [
      for (final d in vista.destinos)
        if (d.porCopiar > 0) '• ${d.nombre}: ${d.porCopiar}',
    ].join('\n');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Copiar ${widget.modulo.nombre}',
          style: const TextStyle(
            fontFamily: kArial,
            fontWeight: FontWeight.w900,
          ),
        ),
        content: Text(
          'Se crea en cada empresa solo lo que le falta; lo que ya tiene no '
          'cambia.\n\n$detalle',
          style: const TextStyle(fontFamily: kArial),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.copy_all_rounded),
            label: const Text('Copiar lo que falta'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _ocupado = true);
    try {
      final resultado = await _service.copiar(
        empresaId: widget.empresaId,
        modulo: widget.modulo.id,
        destinos: vista.destinos.map((d) => d.empresaId).toList(),
        maestros: _maestrosElegidos,
      );
      if (!mounted) return;
      setState(() => _vista = resultado);
      _mensaje(
        resultado.fallidos == 0
            ? '${widget.modulo.nombre}: ${resultado.creados} copiado(s). '
                  'Quedó en Logs.'
            : '${widget.modulo.nombre}: ${resultado.creados} copiado(s); '
                  '${resultado.fallidos} no se pudieron. Vuelve a copiar.',
        error: resultado.fallidos > 0,
      );
    } on FirebaseFunctionsException catch (e) {
      if (mounted) _mensaje(e.message ?? 'No se pudo copiar.', error: true);
    } catch (e) {
      if (mounted) _mensaje('No se pudo copiar: $e', error: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final modulo = widget.modulo;
    final posibles = destinosPosibles(
      empresas: widget.empresas,
      empresaActiva: widget.empresaId,
      actor: _actor,
    );
    final vista = _vista;
    return Card(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: modulo.color.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.sync_alt_rounded, color: modulo.color, size: 26),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Copiar ${modulo.nombre} a otras empresas',
                    style: const TextStyle(
                      fontFamily: kArial,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Los maestros se crean y editan dentro del módulo, en cada '
              'empresa. Aquí se copian de la empresa activa a otras: solo se '
              'agrega lo que el destino no tiene (por código o nombre), nunca '
              'se cambia lo que ya existe y se puede repetir.',
              style: TextStyle(fontFamily: kArial, color: Colors.black54),
            ),
            const SizedBox(height: 14),
            const _Subtitulo('Empresas destino'),
            if (_actor == null)
              const Padding(
                padding: EdgeInsets.all(8),
                child: LinearProgressIndicator(),
              )
            else if (posibles.isEmpty)
              const Text(
                'No hay otras empresas.',
                style: TextStyle(fontFamily: kArial),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final p in posibles)
                    FilterChip(
                      label: Text(
                        p.administra
                            ? p.empresa.nombre
                            : '${p.empresa.nombre} (sin Administración)',
                      ),
                      tooltip: p.administra
                          ? null
                          : 'No eres Administración en esta empresa',
                      selected: _destinos.contains(p.empresa.id),
                      onSelected: !p.administra || _ocupado
                          ? null
                          : (v) => _cambio(
                              () => v
                                  ? _destinos.add(p.empresa.id)
                                  : _destinos.remove(p.empresa.id),
                            ),
                    ),
                ],
              ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Expanded(child: _Subtitulo('Qué copiar')),
                TextButton(
                  onPressed: _ocupado
                      ? null
                      : () => _cambio(
                          () => _maestros =
                              _maestros.length == modulo.maestros.length
                              ? <String>{}
                              : {for (final m in modulo.maestros) m.id},
                        ),
                  child: Text(
                    _maestros.length == modulo.maestros.length
                        ? 'Quitar todos'
                        : 'Todos',
                  ),
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in modulo.maestros)
                  FilterChip(
                    label: Text(m.nombre),
                    selected: _maestros.contains(m.id),
                    onSelected: _ocupado
                        ? null
                        : (v) => _cambio(
                            () => v
                                ? _maestros.add(m.id)
                                : _maestros.remove(m.id),
                          ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: _ocupado || _destinos.isEmpty || _maestros.isEmpty
                      ? null
                      : _previsualizar,
                  icon: _ocupado && vista == null
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.visibility_outlined),
                  label: const Text('Ver qué se copiaría'),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: modulo.color),
                  onPressed:
                      _ocupado ||
                          vista == null ||
                          vista.ejecutado ||
                          vista.porCopiar == 0
                      ? null
                      : _copiar,
                  icon: _ocupado && vista != null
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.copy_all_rounded),
                  label: const Text('Copiar lo que falta'),
                ),
              ],
            ),
            if (vista != null) ...[
              const SizedBox(height: 16),
              if (!vista.ejecutado && vista.porCopiar == 0)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Las empresas elegidas ya tienen todo: no hay nada que '
                    'copiar.',
                    style: TextStyle(
                      fontFamily: kArial,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              for (final d in vista.destinos) ...[
                _DestinoResultado(destino: d, ejecutado: vista.ejecutado),
                const SizedBox(height: 10),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _Subtitulo extends StatelessWidget {
  const _Subtitulo(this.texto);
  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      texto,
      style: const TextStyle(
        fontFamily: kArial,
        fontWeight: FontWeight.w800,
        color: Color(0xFF334155),
      ),
    ),
  );
}

class _DestinoResultado extends StatelessWidget {
  const _DestinoResultado({required this.destino, required this.ejecutado});

  final ResultadoDestino destino;
  final bool ejecutado;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            destino.nombre,
            style: const TextStyle(
              fontFamily: kArial,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          for (final m in destino.maestros)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    m.porCopiar == 0
                        ? Icons.check_circle_outline
                        : m.fallidos > 0
                        ? Icons.error_outline
                        : Icons.add_circle_outline,
                    size: 18,
                    color: m.porCopiar == 0
                        ? const Color(0xFF64748B)
                        : m.fallidos > 0
                        ? const Color(0xFFB91C1C)
                        : const Color(0xFF047857),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${m.nombre}: ${m.resumen(ejecutado: ejecutado)}',
                          style: const TextStyle(fontFamily: kArial),
                        ),
                        if (!ejecutado && !m.esConfig && m.ejemplos.isNotEmpty)
                          Text(
                            'Ej.: ${m.ejemplos.join(', ')}'
                            '${m.nuevos > m.ejemplos.length ? '…' : ''}',
                            style: const TextStyle(
                              fontFamily: kArial,
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (destino.sinEquivalente.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Lo copiado nombra cosas que ${destino.nombre} no tiene: '
                '${destino.sinEquivalente.join(', ')}. Envía las áreas, '
                'cargos y centros desde Usuarios › Multiempresa, y copia '
                'también los maestros que falten, para que queden enlazados.',
                style: const TextStyle(
                  fontFamily: kArial,
                  fontSize: 12,
                  color: Color(0xFF9A3412),
                ),
              ),
            ),
          ],
          if (destino.archivosSinCopiar > 0) ...[
            const SizedBox(height: 6),
            Text(
              '${destino.archivosSinCopiar} archivo(s) no se pudieron '
              'duplicar: quedaron con el enlace de la empresa activa.',
              style: const TextStyle(
                fontFamily: kArial,
                fontSize: 12,
                color: Color(0xFF9A3412),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
