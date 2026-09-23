// lib/visitas/visitas_firma.dart
//
// Firmas de la visita (17 sep 2026): la de quien inspecciona y la del
// responsable del establecimiento. Las dos se pueden dibujar en pantalla;
// la del profesional además puede salir de la firma guardada en su perfil
// (la misma que usan Gestión Documental y Planillas de Pago). El
// responsable del establecimiento no es usuario de la app, así que la
// suya siempre se dibuja ahí mismo, en la tablet, delante de él.
//
// También vive aquí el diálogo de reprogramar: es corto y lo usan el jefe
// (desde el detalle) y el profesional (desde la pantalla de inicio).

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:signature/signature.dart';

import 'visitas_models.dart';

const String _kFont = 'Arial';
const Color _kColor = Color(0xFF7C3AED);

/// Lo que devuelve el diálogo de firma.
class FirmaCapturada {
  final Uint8List png;
  final String nombre;
  final String cargo;
  final String modo;
  const FirmaCapturada({
    required this.png,
    required this.nombre,
    required this.cargo,
    required this.modo,
  });
}

/// Abre el diálogo de firma. [firmaGuardada] solo aplica al profesional:
/// si viene, se ofrece "usar mi firma guardada" además del trazo.
Future<FirmaCapturada?> pedirFirma(
  BuildContext context, {
  required String titulo,
  required String nombreInicial,
  required String cargoInicial,
  Uint8List? firmaGuardada,
  bool nombreEditable = true,
  bool cargoEditable = true,
}) => showDialog<FirmaCapturada>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _FirmaDialog(
    titulo: titulo,
    nombreInicial: nombreInicial,
    cargoInicial: cargoInicial,
    firmaGuardada: firmaGuardada,
    nombreEditable: nombreEditable,
    cargoEditable: cargoEditable,
  ),
);

class _FirmaDialog extends StatefulWidget {
  final String titulo;
  final String nombreInicial;
  final String cargoInicial;
  final Uint8List? firmaGuardada;
  final bool nombreEditable;
  final bool cargoEditable;
  const _FirmaDialog({
    required this.titulo,
    required this.nombreInicial,
    required this.cargoInicial,
    required this.firmaGuardada,
    required this.nombreEditable,
    required this.cargoEditable,
  });

  @override
  State<_FirmaDialog> createState() => _FirmaDialogState();
}

class _FirmaDialogState extends State<_FirmaDialog> {
  late final TextEditingController _nombre;
  late final TextEditingController _cargo;
  final _ctrl = SignatureController(
    penStrokeWidth: 3,
    penColor: const Color(0xFF0F172A),
    exportBackgroundColor: Colors.white,
  );
  bool _usarGuardada = false;
  bool _ocupado = false;

  @override
  void initState() {
    super.initState();
    _nombre = TextEditingController(text: widget.nombreInicial);
    _cargo = TextEditingController(text: widget.cargoInicial);
    _usarGuardada = widget.firmaGuardada != null;
  }

  @override
  void dispose() {
    _nombre.dispose();
    _cargo.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _aceptar() async {
    final nombre = _nombre.text.trim();
    if (nombre.isEmpty) {
      _aviso('Escribe el nombre de quien firma.');
      return;
    }
    Uint8List? png;
    String modo;
    if (_usarGuardada && widget.firmaGuardada != null) {
      png = widget.firmaGuardada;
      modo = kFirmaModoGuardada;
    } else {
      if (_ctrl.isEmpty) {
        _aviso('Dibuja la firma en el recuadro.');
        return;
      }
      setState(() => _ocupado = true);
      png = await _ctrl.toPngBytes(height: 240, width: 640);
      modo = kFirmaModoDibujada;
      if (png == null) {
        if (mounted) setState(() => _ocupado = false);
        _aviso('No se pudo capturar la firma. Intenta de nuevo.');
        return;
      }
    }
    if (!mounted) return;
    Navigator.pop(
      context,
      FirmaCapturada(
        png: png!,
        nombre: nombre,
        cargo: _cargo.text.trim(),
        modo: modo,
      ),
    );
  }

  void _aviso(String m) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    final ancho = MediaQuery.of(context).size.width;
    return AlertDialog(
      title: Text(widget.titulo, style: const TextStyle(fontFamily: _kFont)),
      content: SizedBox(
        width: ancho < 600 ? ancho : 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _nombre,
                enabled: widget.nombreEditable,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nombre',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _cargo,
                enabled: widget.cargoEditable,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Cargo',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              if (widget.firmaGuardada != null) ...[
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: true,
                      icon: Icon(Icons.verified_outlined, size: 18),
                      label: Text('Mi firma guardada'),
                    ),
                    ButtonSegment(
                      value: false,
                      icon: Icon(Icons.draw_outlined, size: 18),
                      label: Text('Dibujar ahora'),
                    ),
                  ],
                  selected: {_usarGuardada},
                  onSelectionChanged: (s) =>
                      setState(() => _usarGuardada = s.first),
                ),
                const SizedBox(height: 10),
              ],
              if (_usarGuardada && widget.firmaGuardada != null)
                Container(
                  height: 160,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.black26),
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.white,
                  ),
                  child: Image.memory(
                    widget.firmaGuardada!,
                    fit: BoxFit.contain,
                  ),
                )
              else ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    height: 180,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.black26),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Signature(
                      controller: _ctrl,
                      backgroundColor: Colors.white,
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => _ctrl.clear(),
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Limpiar'),
                  ),
                ),
              ],
              const Text(
                'La firma queda estampada en el acta de esta visita junto con la '
                'fecha y hora del dispositivo.',
                style: TextStyle(
                  fontFamily: _kFont,
                  fontSize: 11,
                  color: Colors.black54,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _ocupado ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: _kColor),
          onPressed: _ocupado ? null : _aceptar,
          child: Text(_ocupado ? 'Guardando…' : 'Firmar'),
        ),
      ],
    );
  }
}

/// Tarjeta de firma en la pantalla de ejecución y en el detalle.
class FirmaTile extends StatelessWidget {
  final String titulo;
  final VisitaFirma? firma;
  final VoidCallback? onFirmar;
  const FirmaTile({
    super.key,
    required this.titulo,
    required this.firma,
    this.onFirmar,
  });

  @override
  Widget build(BuildContext context) {
    final f = firma;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 120,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.black12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: f == null
                  ? const Icon(Icons.draw_outlined, color: Colors.black26)
                  : f.blob != null
                  ? Image.memory(f.blob!, fit: BoxFit.contain)
                  : f.url.isNotEmpty
                  ? Image.network(f.url, fit: BoxFit.contain)
                  : const Icon(Icons.check, color: Colors.black26),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    style: const TextStyle(
                      fontFamily: _kFont,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    f == null
                        ? 'Sin firmar'
                        : '${f.nombre}${f.cargo.isEmpty ? '' : ' · ${f.cargo}'}',
                    style: const TextStyle(fontFamily: _kFont, fontSize: 12),
                  ),
                  if (f != null)
                    Text(
                      f.modo == kFirmaModoGuardada
                          ? 'Firma guardada del perfil'
                          : 'Dibujada en el sitio',
                      style: const TextStyle(
                        fontFamily: _kFont,
                        fontSize: 11,
                        color: Colors.black54,
                      ),
                    ),
                ],
              ),
            ),
            if (onFirmar != null)
              OutlinedButton(
                onPressed: onFirmar,
                child: Text(f == null ? 'Firmar' : 'Repetir'),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Reprogramar ─────────────────────────────────────────────────────────────

class Reprogramacion {
  final DateTime fecha;
  final String motivo;
  const Reprogramacion(this.fecha, this.motivo);
}

Future<Reprogramacion?> pedirReprogramacion(
  BuildContext context, {
  required DateTime fechaActual,
}) => showDialog<Reprogramacion>(
  context: context,
  builder: (_) => _ReprogramarDialog(fechaActual: fechaActual),
);

class _ReprogramarDialog extends StatefulWidget {
  final DateTime fechaActual;
  const _ReprogramarDialog({required this.fechaActual});
  @override
  State<_ReprogramarDialog> createState() => _ReprogramarDialogState();
}

class _ReprogramarDialogState extends State<_ReprogramarDialog> {
  late DateTime _fecha;
  final _motivo = TextEditingController();

  @override
  void initState() {
    super.initState();
    final hoy = DateTime.now();
    final hoyDia = DateTime(hoy.year, hoy.month, hoy.day);
    _fecha = widget.fechaActual.isBefore(hoyDia) ? hoyDia : widget.fechaActual;
  }

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  String _dd(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text(
      'Reprogramar visita',
      style: TextStyle(fontFamily: _kFont),
    ),
    content: SizedBox(
      width: 380,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event),
            title: Text(
              'Nueva fecha: ${_dd(_fecha)}',
              style: const TextStyle(fontFamily: _kFont),
            ),
            subtitle: Text(
              'Antes: ${_dd(widget.fechaActual)}',
              style: const TextStyle(fontFamily: _kFont, fontSize: 12),
            ),
            trailing: const Icon(Icons.edit_calendar_outlined),
            onTap: () async {
              final hoy = DateTime.now();
              final d = await showDatePicker(
                context: context,
                initialDate: _fecha,
                firstDate: DateTime(hoy.year, hoy.month, hoy.day),
                lastDate: hoy.add(const Duration(days: 365)),
              );
              if (d != null) setState(() => _fecha = d);
            },
          ),
          TextField(
            controller: _motivo,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Motivo',
              hintText: 'Por qué se mueve (queda en el historial)',
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Volver'),
      ),
      FilledButton(
        style: FilledButton.styleFrom(backgroundColor: _kColor),
        onPressed: () {
          final m = _motivo.text.trim();
          if (m.isEmpty) {
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              const SnackBar(content: Text('Escribe el motivo.')),
            );
            return;
          }
          final mismaFecha =
              _fecha.year == widget.fechaActual.year &&
              _fecha.month == widget.fechaActual.month &&
              _fecha.day == widget.fechaActual.day;
          if (mismaFecha) {
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              const SnackBar(content: Text('Escoge una fecha distinta.')),
            );
            return;
          }
          Navigator.pop(context, Reprogramacion(_fecha, m));
        },
        child: const Text('Reprogramar'),
      ),
    ],
  );
}
