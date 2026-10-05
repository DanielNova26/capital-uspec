// lib/visitas/visitas_ubicaciones_screen.dart
//
// Maestro de ubicaciones de los establecimientos (17 sep 2026).
//
// Lo pidió el usuario tal cual: "traer los establecimientos y cargar las
// ubicaciones", con un radio corto. Lo cargan Desarrollo y Gerencia (26 sep
// 2026); las reglas de Firestore solo les dejan escribir a ellos.
//
// Trae los centros de costo de la empresa (con sus subcentros) y a cada
// uno le deja poner lat/lng, radio y ciudad. Un subcentro sin ubicación
// propia hereda la del centro. Sin ubicación, la visita a ese
// establecimiento no se puede iniciar: la lista lo marca en rojo para que
// se vea de una qué falta.
//
// 28 sep 2026: "buscar los lugares con Google Maps, porque se le da buscar y
// no encuentra la dirección o el establecimiento. Si busco Buen Pastor, que
// me muestre cuál sale en Google Maps, se selecciona y traiga los datos".
// El buscador del teléfono solo entendía direcciones y en web no corría.
// Ahora se busca en Google Places desde el backend (`visitasBuscarLugar`),
// igual en web y en móvil: salen los lugares con su dirección, se elige uno
// y quedan las coordenadas, la dirección, la ciudad y el lugar de Google;
// el mapa lo muestra con el radio y se puede afinar tocando el punto exacto.
// También se agregan subcentros desde aquí, para visitarlos como
// establecimiento propio.
//
// 5 oct 2026: salen también los establecimientos propios de Visitas (los que
// no son centros de costo), que se crean en Admin › Maestros por módulo ›
// Visitas. Aquí se les carga la ubicación como a cualquier otro; no tienen
// subcentros.

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/paged_list.dart';
import 'visitas_models.dart';
import 'visitas_service.dart';

const String _kFont = 'Arial';
const Color _kColor = Color(0xFF7C3AED);

void _snack(BuildContext context, String m, {bool error = false}) {
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(
      content: Text(m),
      backgroundColor: error ? const Color(0xFFB91C1C) : null,
    ),
  );
}

class VisitasUbicacionesTab extends StatefulWidget {
  final VisitasService svc;
  final String empresaId;
  final String userId;

  /// El mapa de Google en el diálogo. Las pruebas no tienen mapa.
  final bool mostrarMapa;

  const VisitasUbicacionesTab({
    super.key,
    required this.svc,
    required this.empresaId,
    required this.userId,
    this.mostrarMapa = true,
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
              final delCentro =
                  porId[VisitaUbicacion.docId(widget.empresaId, c.id, '')];
              filas.add(_Fila(centro: c, ubicacion: delCentro));
              for (final s in c.subcentrosActivos) {
                filas.add(
                  _Fila(
                    centro: c,
                    subcentroId: s.id,
                    subcentroNombre: s.nombre,
                    ubicacion:
                        porId[VisitaUbicacion.docId(
                          widget.empresaId,
                          c.id,
                          s.id,
                        )],
                    ubicacionCentro: delCentro,
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
            // Para orientar la búsqueda de Google hacia donde ya hay sitios.
            final alguna = us.data!.isEmpty ? null : us.data!.first;
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
                              'no se les puede iniciar visita hasta cargarla. '
                              'Tócalo y búscalo en Google Maps.',
                    style: TextStyle(
                      fontFamily: _kFont,
                      fontSize: 12,
                      color: sinUbicacion == 0
                          ? const Color(0xFF166534)
                          : const Color(0xFF991B1B),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  '¿Falta un establecimiento que no es centro de costo? Se '
                  'agrega en Admin › Maestros por módulo › Visitas y aparece '
                  'aquí para cargarle la ubicación.',
                  style: TextStyle(
                    fontFamily: _kFont,
                    fontSize: 12,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Filtrar establecimientos de la lista',
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
                    onEditar: () =>
                        _editar(r, cerca: r.ubicacionCentro ?? alguna),
                    onQuitar: r.ubicacion == null
                        ? null
                        : () => _quitar(r.ubicacion!),
                    onAgregarSubcentro: r.esSubcentro || r.centro.propio
                        ? null
                        : () => _agregarSubcentro(
                            r,
                            cerca: r.ubicacion ?? alguna,
                          ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _editar(_Fila r, {VisitaUbicacion? cerca}) async {
    final u = await showDialog<VisitaUbicacion>(
      context: context,
      builder: (_) => _UbicacionDialog(
        svc: widget.svc,
        empresaId: widget.empresaId,
        fila: r,
        userId: widget.userId,
        cerca: cerca,
        mostrarMapa: widget.mostrarMapa,
      ),
    );
    if (u == null) return;
    try {
      await widget.svc.guardarUbicacion(u);
      if (mounted) _snack(context, 'Ubicación de ${r.nombre} guardada.');
    } catch (e) {
      if (mounted) _snack(context, 'No se pudo guardar: $e', error: true);
    }
  }

  /// Un subcentro nuevo del centro (Cómbita Alta, Picota ERE 2): queda en el
  /// maestro de centros de costo y enseguida se le busca la ubicación.
  Future<void> _agregarSubcentro(_Fila r, {VisitaUbicacion? cerca}) async {
    final nombre = await showDialog<String>(
      context: context,
      builder: (_) => _NombreSubcentroDialog(centro: r.centro.nombre),
    );
    if (nombre == null || nombre.isEmpty || !mounted) return;
    try {
      final sub = await widget.svc.agregarSubcentro(r.centro, nombre);
      if (!mounted) return;
      _snack(
        context,
        'Subcentro ${sub.nombre} agregado. Búscale la ubicación.',
      );
      await _editar(
        _Fila(
          centro: r.centro,
          subcentroId: sub.id,
          subcentroNombre: sub.nombre,
          ubicacion: null,
          ubicacionCentro: r.ubicacion,
        ),
        cerca: cerca,
      );
    } on VisitasException catch (e) {
      if (mounted) _snack(context, e.mensaje, error: true);
    } catch (e) {
      if (mounted) _snack(context, 'No se pudo agregar: $e', error: true);
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

/// Nombre del subcentro nuevo. Es un widget propio para que el campo viva
/// lo mismo que el diálogo (se cierra con animación).
class _NombreSubcentroDialog extends StatefulWidget {
  final String centro;
  const _NombreSubcentroDialog({required this.centro});

  @override
  State<_NombreSubcentroDialog> createState() => _NombreSubcentroDialogState();
}

class _NombreSubcentroDialogState extends State<_NombreSubcentroDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Nuevo subcentro de ${widget.centro}'),
    content: SizedBox(
      width: 400,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Nombre del subcentro',
              hintText: 'Alta, ERE 2, Patio 3…',
            ),
            onSubmitted: (v) => Navigator.pop(context, v.trim()),
          ),
          const SizedBox(height: 8),
          const Text(
            'Se visita como un establecimiento propio y se puede poner '
            'en los grupos. Es el mismo subcentro que ve Administración '
            'en el maestro de centros de costo.',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        style: FilledButton.styleFrom(backgroundColor: _kColor),
        onPressed: () => Navigator.pop(context, _ctrl.text.trim()),
        child: const Text('Agregar'),
      ),
    ],
  );
}

class _Fila {
  final VisitaCentro centro;
  final String subcentroId;
  final String subcentroNombre;
  final VisitaUbicacion? ubicacion;

  /// La del centro, que hereda un subcentro sin ubicación propia.
  final VisitaUbicacion? ubicacionCentro;
  const _Fila({
    required this.centro,
    this.subcentroId = '',
    this.subcentroNombre = '',
    required this.ubicacion,
    this.ubicacionCentro,
  });
  bool get esSubcentro => subcentroId.isNotEmpty;
  String get nombre =>
      esSubcentro ? '${centro.nombre} · $subcentroNombre' : centro.nombre;
}

class _FilaCard extends StatelessWidget {
  final _Fila fila;
  final VoidCallback onEditar;
  final VoidCallback? onQuitar;
  final VoidCallback? onAgregarSubcentro;
  const _FilaCard({
    required this.fila,
    required this.onEditar,
    this.onQuitar,
    this.onAgregarSubcentro,
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
          [
            // No es centro de costo: se creó en Admin solo para Visitas.
            if (fila.centro.propio) 'Solo Visitas',
            u == null
                ? (fila.esSubcentro
                      ? 'Hereda la ubicación del centro'
                      : 'Sin ubicación: tócalo para buscarlo en Google Maps')
                : [
                    if (u.direccion.isNotEmpty) u.direccion,
                    'radio ${u.radioMetros.round()} m',
                    if (u.ciudad.isNotEmpty) u.ciudad,
                  ].join(' · '),
          ].join(' · '),
          style: TextStyle(
            fontFamily: _kFont,
            fontSize: 12,
            color: falta ? const Color(0xFFB91C1C) : Colors.black54,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onAgregarSubcentro != null)
              IconButton(
                tooltip: 'Agregar subcentro',
                icon: const Icon(Icons.add_home_work_outlined, size: 20),
                onPressed: onAgregarSubcentro,
              ),
            if (onQuitar != null)
              IconButton(
                tooltip: 'Quitar ubicación',
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

  /// Hacia dónde orientar la búsqueda (el centro, u otro establecimiento).
  final VisitaUbicacion? cerca;
  final bool mostrarMapa;
  const _UbicacionDialog({
    required this.svc,
    required this.empresaId,
    required this.fila,
    required this.userId,
    required this.cerca,
    required this.mostrarMapa,
  });

  @override
  State<_UbicacionDialog> createState() => _UbicacionDialogState();
}

class _UbicacionDialogState extends State<_UbicacionDialog> {
  late final TextEditingController _buscar;
  late final TextEditingController _lat;
  late final TextEditingController _lng;
  late final TextEditingController _radio;
  late final TextEditingController _ciudad;
  late final TextEditingController _direccion;
  String _placeId = '';
  String _nombreGoogle = '';
  bool _ocupado = false;
  bool _buscando = false;
  List<LugarGoogle>? _resultados;
  String? _errorBusqueda;
  GoogleMapController? _mapa;

  @override
  void initState() {
    super.initState();
    final u = widget.fila.ubicacion;
    _lat = TextEditingController(text: u == null ? '' : u.lat.toString());
    _lng = TextEditingController(text: u == null ? '' : u.lng.toString());
    _radio = TextEditingController(
      text: (u?.radioMetros ?? kVisitasRadioDefectoMetros).round().toString(),
    );
    final ciudad = u?.ciudad ?? widget.fila.ubicacionCentro?.ciudad ?? '';
    _ciudad = TextEditingController(text: ciudad);
    _direccion = TextEditingController(text: u?.direccion ?? '');
    _placeId = u?.placeId ?? '';
    _nombreGoogle = u?.nombreGoogle ?? '';
    _buscar = TextEditingController(
      text: textoBusquedaLugar(widget.fila.nombre, ciudad: ciudad),
    );
  }

  @override
  void dispose() {
    for (final c in [_buscar, _lat, _lng, _radio, _ciudad, _direccion]) {
      c.dispose();
    }
    super.dispose();
  }

  double? get _latV => double.tryParse(_lat.text.trim().replaceAll(',', '.'));
  double? get _lngV => double.tryParse(_lng.text.trim().replaceAll(',', '.'));
  double get _radioV =>
      double.tryParse(_radio.text.trim()) ?? kVisitasRadioDefectoMetros;

  LatLng? get _punto {
    final lat = _latV, lng = _lngV;
    if (lat == null || lng == null || lat.abs() > 90 || lng.abs() > 180) {
      return null;
    }
    return LatLng(lat, lng);
  }

  void _ponerPunto(double lat, double lng, {bool mover = true}) {
    setState(() {
      _lat.text = lat.toStringAsFixed(6);
      _lng.text = lng.toStringAsFixed(6);
    });
    if (mover) {
      _mapa?.animateCamera(CameraUpdate.newLatLngZoom(LatLng(lat, lng), 17));
    }
  }

  Future<void> _buscarEnGoogle() async {
    final q = _buscar.text.trim();
    if (q.length < 3) {
      _snack(context, 'Escribe al menos 3 letras para buscar.');
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _buscando = true;
      _errorBusqueda = null;
    });
    try {
      final r = await widget.svc.buscarLugares(
        empresaId: widget.empresaId,
        texto: q,
        cerca: widget.cerca,
      );
      if (mounted) setState(() => _resultados = r);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _resultados = null;
        _errorBusqueda = e is VisitasException ? e.mensaje : _mensajeDeError(e);
      });
    } finally {
      if (mounted) setState(() => _buscando = false);
    }
  }

  /// El error del callable dice qué configurar; se muestra tal cual.
  String _mensajeDeError(Object e) {
    final t = e.toString();
    final i = t.indexOf(']');
    return i >= 0 && i < t.length - 1 ? t.substring(i + 1).trim() : t;
  }

  void _elegir(LugarGoogle l) {
    setState(() {
      _placeId = l.placeId;
      _nombreGoogle = l.nombre;
      if (l.direccion.isNotEmpty) _direccion.text = l.direccion;
      if (l.ciudad.isNotEmpty) _ciudad.text = l.ciudad;
      _resultados = null;
    });
    _ponerPunto(l.lat, l.lng);
  }

  Future<void> _miUbicacion() async {
    setState(() => _ocupado = true);
    try {
      final p = await widget.svc.posicionActual();
      if (!mounted) return;
      if (p == null) {
        _snack(
          context,
          'No se pudo leer el GPS. Revisa permisos.',
          error: true,
        );
        return;
      }
      // Un punto tomado a mano ya no es el lugar de Google.
      _placeId = '';
      _nombreGoogle = '';
      _ponerPunto(p.latitude, p.longitude);
      _snack(context, 'Coordenadas tomadas (±${p.accuracy.round()} m).');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _abrirEnMaps() async {
    final p = _punto;
    if (p == null) return;
    final u = VisitaUbicacion(
      empresaId: widget.empresaId,
      centroId: widget.fila.centro.id,
      centroNombre: widget.fila.centro.nombre,
      lat: p.latitude,
      lng: p.longitude,
      placeId: _placeId,
    );
    await launchUrl(Uri.parse(u.mapsUrl), mode: LaunchMode.externalApplication);
  }

  void _guardar() {
    final lat = _latV;
    final lng = _lngV;
    final radio = double.tryParse(_radio.text.trim());
    if (lat == null || lng == null || lat.abs() > 90 || lng.abs() > 180) {
      _snack(
        context,
        'Busca el lugar en Google Maps o escribe latitud y longitud.',
        error: true,
      );
      return;
    }
    if (radio == null || radio < 20 || radio > 2000) {
      _snack(
        context,
        'El radio debe estar entre 20 y 2000 metros.',
        error: true,
      );
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
        placeId: _placeId,
        nombreGoogle: _nombreGoogle,
      ),
    );
  }

  Widget _buscador() {
    final r = _resultados;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Buscar en Google Maps',
          style: TextStyle(fontFamily: _kFont, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _buscar,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _buscarEnGoogle(),
          decoration: InputDecoration(
            isDense: true,
            border: const OutlineInputBorder(),
            hintText: 'Nombre del establecimiento o dirección',
            prefixIcon: const Icon(Icons.travel_explore_outlined),
            suffixIcon: _buscando
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    tooltip: 'Buscar',
                    icon: const Icon(Icons.search),
                    onPressed: _buscarEnGoogle,
                  ),
          ),
        ),
        if (_errorBusqueda != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _errorBusqueda!,
              style: const TextStyle(fontSize: 12, color: Color(0xFFB91C1C)),
            ),
          ),
        if (r != null) ...[
          const SizedBox(height: 6),
          if (r.isEmpty)
            const Text(
              'Google no encontró ese lugar. Prueba con el nombre y la '
              'ciudad, o con la dirección.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            )
          else
            Container(
              constraints: const BoxConstraints(maxHeight: 240),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.black12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final l in r)
                    ListTile(
                      dense: true,
                      leading: const Icon(
                        Icons.place,
                        color: Color(0xFFDC2626),
                      ),
                      title: Text(
                        l.nombre.isEmpty ? l.direccion : l.nombre,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        l.direccion,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => _elegir(l),
                    ),
                ],
              ),
            ),
        ],
      ],
    );
  }

  Widget _vistaMapa() {
    final p = _punto;
    if (!widget.mostrarMapa) return const SizedBox.shrink();
    if (p == null) {
      return Container(
        height: 90,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFF5F3FF),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text(
          'Busca el lugar o usa tu ubicación para verlo en el mapa.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 240,
            child: GoogleMap(
              initialCameraPosition: CameraPosition(target: p, zoom: 17),
              onMapCreated: (c) => _mapa = c,
              // Dentro del diálogo con scroll, el mapa se arrastra igual.
              gestureRecognizers: {
                Factory<OneSequenceGestureRecognizer>(
                  () => EagerGestureRecognizer(),
                ),
              },
              markers: {
                Marker(
                  markerId: const MarkerId('sitio'),
                  position: p,
                  draggable: true,
                  infoWindow: InfoWindow(
                    title: _nombreGoogle.isEmpty
                        ? widget.fila.nombre
                        : _nombreGoogle,
                  ),
                  onDragEnd: (x) =>
                      _ponerPunto(x.latitude, x.longitude, mover: false),
                ),
              },
              circles: {
                Circle(
                  circleId: const CircleId('radio'),
                  center: p,
                  radius: _radioV,
                  strokeWidth: 2,
                  strokeColor: _kColor,
                  fillColor: _kColor.withValues(alpha: .12),
                ),
              },
              onTap: (x) => _ponerPunto(x.latitude, x.longitude, mover: false),
              myLocationButtonEnabled: false,
              mapToolbarEnabled: false,
              zoomControlsEnabled: true,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            const Expanded(
              child: Text(
                'El círculo es el radio permitido. Toca el mapa o arrastra el '
                'marcador para poner la puerta exacta.',
                style: TextStyle(fontSize: 11, color: Colors.black54),
              ),
            ),
            TextButton.icon(
              onPressed: _abrirEnMaps,
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('Abrir en Google Maps'),
            ),
          ],
        ),
      ],
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
        width: 540,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buscador(),
              const SizedBox(height: 12),
              _vistaMapa(),
              if (_nombreGoogle.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Lugar de Google: $_nombreGoogle',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              TextField(
                controller: _direccion,
                decoration: const InputDecoration(
                  labelText: 'Dirección',
                  isDense: true,
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
                      onChanged: (_) => setState(() {}),
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
                      onChanged: (_) => setState(() {}),
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
                onChanged: (_) => setState(() {}),
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
                'Si estás parado en la puerta del establecimiento, tu ubicación '
                'es lo más exacto.',
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
