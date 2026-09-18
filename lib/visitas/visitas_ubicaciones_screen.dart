// lib/visitas/visitas_ubicaciones_screen.dart
//
// Maestro de ubicaciones de los establecimientos (17 sep 2026).
//
// Lo pidió el usuario tal cual: "traer los establecimientos y cargar las
// ubicaciones", con un radio corto, y que solo Desarrollo lo toque. Por eso
// esta pestaña aparece únicamente para el desarrollador y las reglas de
// Firestore solo le dejan escribir a él.
//
// Trae los centros de costo de la empresa (con sus subcentros) y a cada
// uno le deja poner lat/lng, radio y ciudad. Un subcentro sin ubicación
// propia hereda la del centro. Sin ubicación, la visita a ese
// establecimiento no se puede iniciar: la lista lo marca en rojo para que
// se vea de una qué falta.
//
// Web y móvil: la pantalla es la misma. "Usar mi ubicación" sirve en las
// dos (en web el navegador pide permiso); "Buscar dirección" solo en
// móvil, porque el plugin de geocodificación no corre en web.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart' as geocoding;

import '../widgets/paged_list.dart';
import 'visitas_models.dart';
import 'visitas_service.dart';

const String _kFont = 'Arial';
const Color _kColor = Color(0xFF7C3AED);

class VisitasUbicacionesTab extends StatefulWidget {
  final VisitasService svc;
  final String empresaId;
  final String userId;
  const VisitasUbicacionesTab({
    super.key,
    required this.svc,
    required this.empresaId,
    required this.userId,
  });

  @override
  State<VisitasUbicacionesTab> createState() => _VisitasUbicacionesTabState();
}

class _VisitasUbicacionesTabState extends State<VisitasUbicacionesTab> {
  late final Stream<List<VisitaCentro>> _centros;
  late final Stream<List<VisitaUbicacion>> _ubicaciones;
  String _filtro = '';

  @override
  void initState() {
    super.initState();
    _centros = widget.svc.streamCentros(widget.empresaId);
    _ubicaciones = widget.svc.streamUbicaciones(widget.empresaId);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<VisitaCentro>>(
      stream: _centros,
      builder: (context, cs) {
        return StreamBuilder<List<VisitaUbicacion>>(
          stream: _ubicaciones,
          builder: (context, us) {
            if (cs.hasError) return Center(child: Text('Error: ${cs.error}'));
            if (us.hasError) return Center(child: Text('Error: ${us.error}'));
            if (!cs.hasData || !us.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final porId = {for (final u in us.data!) u.id: u};
            final filas = <_Fila>[];
            for (final c in cs.data!) {
              filas.add(
                _Fila(
                  centro: c,
                  ubicacion:
                      porId[VisitaUbicacion.docId(widget.empresaId, c.id, '')],
                ),
              );
              for (final s in c.subcentrosActivos) {
                filas.add(
                  _Fila(
                    centro: c,
                    subcentroId: s.id,
                    subcentroNombre: s.nombre,
                    ubicacion: porId[VisitaUbicacion.docId(
                      widget.empresaId,
                      c.id,
                      s.id,
                    )],
                  ),
                );
              }
            }
            final f = _filtro.trim().toLowerCase();
            final visibles = f.isEmpty
                ? filas
                : filas
                      .where((r) => r.nombre.toLowerCase().contains(f))
                      .toList();
            final sinUbicacion = filas
                .where((r) => r.subcentroId.isEmpty && r.ubicacion == null)
                .length;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: sinUbicacion == 0
                        ? const Color(0xFFDCFCE7)
                        : const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    sinUbicacion == 0
                        ? 'Todos los establecimientos tienen ubicación. '
                              'Radio por defecto: ${kVisitasRadioDefectoMetros.round()} m.'
                        : '$sinUbicacion establecimiento(s) sin ubicación: a esos '
                              'no se les puede iniciar visita hasta cargarla.',
                    style: TextStyle(
                      fontFamily: _kFont,
                      fontSize: 12,
                      color: sinUbicacion == 0
                          ? const Color(0xFF166534)
                          : const Color(0xFF991B1B),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Buscar establecimiento',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => setState(() => _filtro = v),
                ),
                const SizedBox(height: 8),
                PagedListSection<_Fila>(
                  items: visibles,
                  etiqueta: 'establecimientos',
                  itemBuilder: (context, r, _) => _FilaCard(
                    fila: r,
                    onEditar: () => _editar(r),
                    onQuitar: r.ubicacion == null
                        ? null
                        : () => _quitar(r.ubicacion!),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _editar(_Fila r) async {
    final u = await showDialog<VisitaUbicacion>(
      context: context,
      builder: (_) => _UbicacionDialog(
        svc: widget.svc,
        empresaId: widget.empresaId,
        fila: r,
        userId: widget.userId,
      ),
    );
    if (u == null) return;
    try {
      await widget.svc.guardarUbicacion(u);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ubicación de ${r.nombre} guardada.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo guardar: $e'),
            backgroundColor: const Color(0xFFB91C1C),
          ),
        );
      }
    }
  }

  Future<void> _quitar(VisitaUbicacion u) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Quitar ubicación'),
        content: const Text(
          'El establecimiento quedará sin referencia y no se le podrán '
          'iniciar visitas hasta volver a cargarla.',
          style: TextStyle(fontFamily: _kFont),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Volver'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB91C1C),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Quitar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.svc.eliminarUbicacion(u.id);
  }
}

class _Fila {
  final VisitaCentro centro;
  final String subcentroId;
  final String subcentroNombre;
  final VisitaUbicacion? ubicacion;
  const _Fila({
    required this.centro,
    this.subcentroId = '',
    this.subcentroNombre = '',
    required this.ubicacion,
  });
  bool get esSubcentro => subcentroId.isNotEmpty;
  String get nombre =>
      esSubcentro ? '${centro.nombre} · $subcentroNombre' : centro.nombre;
}

class _FilaCard extends StatelessWidget {
  final _Fila fila;
  final VoidCallback onEditar;
  final VoidCallback? onQuitar;
  const _FilaCard({
    required this.fila,
    required this.onEditar,
    this.onQuitar,
  });

  @override
  Widget build(BuildContext context) {
    final u = fila.ubicacion;
    final falta = u == null && !fila.esSubcentro;
    return Card(
      margin: EdgeInsets.only(bottom: 8, left: fila.esSubcentro ? 24 : 0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: falta ? const Color(0xFFDC2626) : Colors.transparent,
          width: falta ? 1.2 : 0,
        ),
      ),
      child: ListTile(
        onTap: onEditar,
        leading: Icon(
          fila.esSubcentro ? Icons.subdirectory_arrow_right : Icons.store,
          color: u == null ? Colors.black38 : _kColor,
        ),
        title: Text(
          fila.esSubcentro ? fila.subcentroNombre : fila.centro.nombre,
          style: const TextStyle(
            fontFamily: _kFont,
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          u == null
              ? (fila.esSubcentro
                    ? 'Hereda la ubicación del centro'
                    : 'Sin ubicación')
              : '${u.lat.toStringAsFixed(5)}, ${u.lng.toStringAsFixed(5)} · '
                    'radio ${u.radioMetros.round()} m'
                    '${u.ciudad.isEmpty ? '' : ' · ${u.ciudad}'}',
          style: TextStyle(
            fontFamily: _kFont,
            fontSize: 12,
            color: falta ? const Color(0xFFB91C1C) : Colors.black54,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onQuitar != null)
              IconButton(
                tooltip: 'Quitar',
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: onQuitar,
              ),
            const Icon(Icons.edit_location_alt_outlined, size: 20),
          ],
        ),
      ),
    );
  }
}

class _UbicacionDialog extends StatefulWidget {
  final VisitasService svc;
  final String empresaId;
  final _Fila fila;
  final String userId;
  const _UbicacionDialog({
    required this.svc,
    required this.empresaId,
    required this.fila,
    required this.userId,
  });

  @override
  State<_UbicacionDialog> createState() => _UbicacionDialogState();
}

class _UbicacionDialogState extends State<_UbicacionDialog> {
  late final TextEditingController _lat;
  late final TextEditingController _lng;
  late final TextEditingController _radio;
  late final TextEditingController _ciudad;
  late final TextEditingController _direccion;
  bool _ocupado = false;

  @override
  void initState() {
    super.initState();
    final u = widget.fila.ubicacion;
    _lat = TextEditingController(text: u == null ? '' : u.lat.toString());
    _lng = TextEditingController(text: u == null ? '' : u.lng.toString());
    _radio = TextEditingController(
      text: (u?.radioMetros ?? kVisitasRadioDefectoMetros).round().toString(),
    );
    _ciudad = TextEditingController(text: u?.ciudad ?? '');
    _direccion = TextEditingController(text: u?.direccion ?? '');
  }

  @override
  void dispose() {
    _lat.dispose();
    _lng.dispose();
    _radio.dispose();
    _ciudad.dispose();
    _direccion.dispose();
    super.dispose();
  }

  void _aviso(String m, {bool error = false}) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(m),
        backgroundColor: error ? const Color(0xFFB91C1C) : null,
      ),
    );
  }

  Future<void> _miUbicacion() async {
    setState(() => _ocupado = true);
    try {
      final p = await widget.svc.posicionActual();
      if (p == null) {
        _aviso('No se pudo leer el GPS. Revisa permisos.', error: true);
        return;
      }
      _lat.text = p.latitude.toStringAsFixed(6);
      _lng.text = p.longitude.toStringAsFixed(6);
      _aviso('Coordenadas tomadas (±${p.accuracy.round()} m).');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _buscarDireccion() async {
    final dir = _direccion.text.trim();
    if (dir.isEmpty) {
      _aviso('Escribe la dirección primero.');
      return;
    }
    if (kIsWeb) {
      _aviso(
        'Buscar por dirección no está disponible en web: usa "Mi ubicación" '
        'desde el sitio o escribe las coordenadas.',
      );
      return;
    }
    setState(() => _ocupado = true);
    try {
      final ciudad = _ciudad.text.trim();
      final q = ciudad.isEmpty ? '$dir, Colombia' : '$dir, $ciudad, Colombia';
      final res = await geocoding.locationFromAddress(q);
      if (res.isEmpty) {
        _aviso('Sin resultados para esa dirección.');
        return;
      }
      _lat.text = res.first.latitude.toStringAsFixed(6);
      _lng.text = res.first.longitude.toStringAsFixed(6);
    } catch (e) {
      _aviso('No se pudo buscar: $e', error: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  void _guardar() {
    final lat = double.tryParse(_lat.text.trim().replaceAll(',', '.'));
    final lng = double.tryParse(_lng.text.trim().replaceAll(',', '.'));
    final radio = double.tryParse(_radio.text.trim());
    if (lat == null || lng == null || lat.abs() > 90 || lng.abs() > 180) {
      _aviso('Latitud y longitud no son válidas.', error: true);
      return;
    }
    if (radio == null || radio < 20 || radio > 2000) {
      _aviso('El radio debe estar entre 20 y 2000 metros.', error: true);
      return;
    }
    Navigator.pop(
      context,
      VisitaUbicacion(
        empresaId: widget.empresaId,
        centroId: widget.fila.centro.id,
        centroNombre: widget.fila.centro.nombre,
        subcentroId: widget.fila.subcentroId,
        subcentroNombre: widget.fila.subcentroNombre,
        lat: lat,
        lng: lng,
        radioMetros: radio,
        ciudad: _ciudad.text.trim(),
        direccion: _direccion.text.trim(),
        actualizadoPor: widget.userId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.fila.nombre,
        style: const TextStyle(fontFamily: _kFont, fontSize: 16),
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _direccion,
                decoration: InputDecoration(
                  labelText: 'Dirección (referencia)',
                  isDense: true,
                  suffixIcon: IconButton(
                    tooltip: 'Buscar coordenadas por dirección',
                    icon: const Icon(Icons.travel_explore_outlined),
                    onPressed: _ocupado ? null : _buscarDireccion,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _ciudad,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Ciudad (va en el encabezado del acta)',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _lat,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Latitud',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _lng,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Longitud',
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _radio,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Radio permitido (metros)',
                  helperText:
                      'Corto a propósito: el acta se hace adentro. 150 m por defecto.',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _ocupado ? null : _miUbicacion,
                icon: const Icon(Icons.my_location),
                label: Text(
                  _ocupado ? 'Ubicando…' : 'Usar mi ubicación actual',
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Lo más exacto es tomarla parado en la puerta del establecimiento.',
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
          onPressed: _ocupado ? null : _guardar,
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
