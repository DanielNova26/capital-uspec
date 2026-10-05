// lib/admin/visitas_establecimientos_panel.dart
//
// Admin › Maestros por módulo › Visitas › Configuración (5 oct 2026).
//
// Pedido del usuario: "agregarle al módulo de visitas ciertos
// establecimientos que no son necesariamente iguales a los de Interventoría,
// pero sí hacen falta para el tema de visitas. Lo podemos poner en el admin".
//
// Son los lugares que se visitan y no son centros de costo de la empresa
// (`TBL_VISITAS_ESTABLECIMIENTOS`). En Visitas salen junto con los centros:
// se programan, se ponen en los grupos y se les carga la ubicación en
// Visitas › Ubicaciones. Interventoría y Facturación no los ven. No se
// borran (las visitas y los grupos los nombran por su id): se inactivan.
//
// Web ancha: tabla con filtro. Móvil: tarjetas. Mismo servicio y permisos;
// las reglas de Firestore dejan escribir a Desarrollo, Admin de la empresa y
// Gerencia de Visitas.

import 'package:flutter/material.dart';

import '../visitas/visitas_models.dart';
import '../visitas/visitas_service.dart';
import '../widgets/paged_list.dart';

const String _kFont = 'Arial';
const Color _kColor = Color(0xFF9D174D);

class VisitasEstablecimientosPanel extends StatefulWidget {
  final String userId;
  final String empresaId;
  final VisitasService? svc;

  const VisitasEstablecimientosPanel({
    super.key,
    required this.userId,
    required this.empresaId,
    this.svc,
  });

  @override
  State<VisitasEstablecimientosPanel> createState() =>
      _VisitasEstablecimientosPanelState();
}

class _VisitasEstablecimientosPanelState
    extends State<VisitasEstablecimientosPanel> {
  late final VisitasService _svc = widget.svc ?? VisitasService();
  late final Stream<List<VisitaEstablecimientoPropio>> _stream = _svc
      .streamEstablecimientosPropios(widget.empresaId);
  String _filtro = '';
  bool _verInactivos = false;

  /// El aviso nuevo reemplaza al anterior: un error no espera en cola
  /// detrás del "agregado".
  void _snack(String m, {bool error = false}) =>
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(m),
            backgroundColor: error ? const Color(0xFFB91C1C) : null,
          ),
        );

  Future<void> _editar([VisitaEstablecimientoPropio? actual]) async {
    final e = await showDialog<VisitaEstablecimientoPropio>(
      context: context,
      builder: (_) =>
          _EstablecimientoDialog(empresaId: widget.empresaId, actual: actual),
    );
    if (e == null || !mounted) return;
    try {
      await _svc.guardarEstablecimientoPropio(e, actorId: widget.userId);
      if (mounted) {
        _snack(
          actual == null
              ? '${e.nombre.trim()} agregado. Cárgale la ubicación en '
                    'Visitas › Ubicaciones.'
              : '${e.nombre.trim()} actualizado.',
        );
      }
    } on VisitasException catch (err) {
      if (mounted) _snack(err.mensaje, error: true);
    } catch (err) {
      if (mounted) _snack('No se pudo guardar: $err', error: true);
    }
  }

  Future<void> _activar(VisitaEstablecimientoPropio e, bool activo) async {
    try {
      await _svc.activarEstablecimientoPropio(
        e.id,
        activo: activo,
        actorId: widget.userId,
      );
    } catch (err) {
      if (mounted) _snack('No se pudo cambiar: $err', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<VisitaEstablecimientoPropio>>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'No se pudieron leer los establecimientos: ${snap.error}',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final todos = snap.data!;
        final inactivos = todos.where((e) => !e.activo).length;
        final q = _filtro.trim().toLowerCase();
        final visibles = [
          for (final e in todos)
            if ((_verInactivos || e.activo) &&
                (q.isEmpty ||
                    e.nombre.toLowerCase().contains(q) ||
                    e.ciudad.toLowerCase().contains(q)))
              e,
        ];
        return LayoutBuilder(
          builder: (context, c) {
            final ancho = c.maxWidth >= 720;
            final pad = ancho ? 16.0 : 12.0;
            return ListView(
              padding: EdgeInsets.fromLTRB(pad, 8, pad, 24),
              children: [
                _encabezado(ancho),
                const SizedBox(height: 12),
                _barra(ancho, inactivos),
                const SizedBox(height: 8),
                if (todos.isEmpty)
                  _vacio(
                    'Todavía no hay establecimientos propios de Visitas. Los '
                    'centros de costo de la empresa ya se pueden visitar; '
                    'agrega aquí solo los que no lo son.',
                  )
                else if (visibles.isEmpty)
                  _vacio('Ningún establecimiento coincide.')
                else if (ancho)
                  _tabla(visibles)
                else
                  PagedListSection<VisitaEstablecimientoPropio>(
                    items: visibles,
                    etiqueta: 'establecimientos',
                    itemBuilder: (context, e, _) => _tarjeta(e),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _encabezado(bool ancho) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Establecimientos de Visitas',
        style: TextStyle(
          fontFamily: _kFont,
          fontSize: ancho ? 18 : 16,
          fontWeight: FontWeight.w900,
        ),
      ),
      const SizedBox(height: 4),
      const Text(
        'Lugares que se visitan y no son centros de costo de la empresa. '
        'En Visitas salen junto con los centros: se programan, se ponen en '
        'los grupos y se les carga la ubicación en Visitas › Ubicaciones. '
        'Interventoría no los ve. No se borran: se inactivan.',
        style: TextStyle(fontFamily: _kFont, color: Colors.black54),
      ),
    ],
  );

  Widget _barra(bool ancho, int inactivos) {
    final buscar = TextField(
      decoration: const InputDecoration(
        isDense: true,
        prefixIcon: Icon(Icons.search, size: 20),
        hintText: 'Buscar por nombre o ciudad',
        border: OutlineInputBorder(),
      ),
      onChanged: (v) => setState(() => _filtro = v),
    );
    final agregar = FilledButton.icon(
      style: FilledButton.styleFrom(backgroundColor: _kColor),
      onPressed: () => _editar(),
      icon: const Icon(Icons.add_business_outlined),
      label: const Text('Agregar establecimiento'),
    );
    final inactivosChip = inactivos == 0
        ? null
        : FilterChip(
            label: Text('Ver inactivos ($inactivos)'),
            selected: _verInactivos,
            onSelected: (v) => setState(() => _verInactivos = v),
          );
    if (ancho) {
      return Row(
        children: [
          Expanded(child: buscar),
          if (inactivosChip != null) ...[
            const SizedBox(width: 12),
            inactivosChip,
          ],
          const SizedBox(width: 12),
          agregar,
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        agregar,
        const SizedBox(height: 8),
        buscar,
        if (inactivosChip != null) ...[
          const SizedBox(height: 4),
          Align(alignment: Alignment.centerLeft, child: inactivosChip),
        ],
      ],
    );
  }

  Widget _vacio(String texto) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Text(
      texto,
      textAlign: TextAlign.center,
      style: const TextStyle(fontFamily: _kFont, color: Colors.black54),
    ),
  );

  Widget _estado(VisitaEstablecimientoPropio e) => Text(
    e.activo ? 'Activo' : 'Inactivo',
    style: TextStyle(
      fontFamily: _kFont,
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: e.activo ? const Color(0xFF15803D) : const Color(0xFFB91C1C),
    ),
  );

  Widget _tabla(List<VisitaEstablecimientoPropio> items) => Card(
    clipBehavior: Clip.antiAlias,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: PagedDataTable(
        etiqueta: 'establecimientos',
        tabla: DataTable(
          columns: const [
            DataColumn(label: Text('Establecimiento')),
            DataColumn(label: Text('Ciudad')),
            DataColumn(label: Text('Estado')),
            DataColumn(label: Text('')),
          ],
          rows: [
            for (final e in items)
              DataRow(
                cells: [
                  DataCell(Text(e.nombre)),
                  DataCell(Text(e.ciudad.isEmpty ? '-' : e.ciudad)),
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(
                          value: e.activo,
                          activeThumbColor: _kColor,
                          onChanged: (v) => _activar(e, v),
                        ),
                        const SizedBox(width: 6),
                        _estado(e),
                      ],
                    ),
                  ),
                  DataCell(
                    IconButton(
                      tooltip: 'Editar',
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      onPressed: () => _editar(e),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    ),
  );

  Widget _tarjeta(VisitaEstablecimientoPropio e) => Card(
    margin: const EdgeInsets.only(bottom: 8),
    child: ListTile(
      onTap: () => _editar(e),
      leading: Icon(
        Icons.storefront_outlined,
        color: e.activo ? _kColor : Colors.black38,
      ),
      title: Text(
        e.nombre,
        style: const TextStyle(fontFamily: _kFont, fontWeight: FontWeight.w700),
      ),
      subtitle: Row(
        children: [
          if (e.ciudad.isNotEmpty)
            Flexible(
              child: Text(
                '${e.ciudad} · ',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontFamily: _kFont, fontSize: 12),
              ),
            ),
          _estado(e),
        ],
      ),
      trailing: Switch(
        value: e.activo,
        activeThumbColor: _kColor,
        onChanged: (v) => _activar(e, v),
      ),
    ),
  );
}

/// Nombre y ciudad. Al editar, también si está activo. Devuelve el
/// establecimiento listo para guardar (sin id si es nuevo).
class _EstablecimientoDialog extends StatefulWidget {
  final String empresaId;
  final VisitaEstablecimientoPropio? actual;
  const _EstablecimientoDialog({required this.empresaId, this.actual});

  @override
  State<_EstablecimientoDialog> createState() => _EstablecimientoDialogState();
}

class _EstablecimientoDialogState extends State<_EstablecimientoDialog> {
  late final _nombre = TextEditingController(text: widget.actual?.nombre);
  late final _ciudad = TextEditingController(text: widget.actual?.ciudad);
  late bool _activo = widget.actual?.activo ?? true;
  String? _error;

  @override
  void dispose() {
    _nombre.dispose();
    _ciudad.dispose();
    super.dispose();
  }

  void _guardar() {
    final e = VisitaEstablecimientoPropio(
      id: widget.actual?.id ?? '',
      empresaId: widget.empresaId,
      nombre: _nombre.text.trim(),
      ciudad: _ciudad.text.trim(),
      activo: _activo,
    );
    // Lo que se puede revisar sin leer la empresa; los nombres repetidos
    // los revisa el servicio al guardar.
    final errores = validarEstablecimientoPropio(e);
    if (errores.isNotEmpty) {
      setState(() => _error = errores.join('\n'));
      return;
    }
    Navigator.pop(context, e);
  }

  @override
  Widget build(BuildContext context) {
    final nuevo = widget.actual == null;
    return AlertDialog(
      title: Text(nuevo ? 'Nuevo establecimiento' : 'Editar establecimiento'),
      scrollable: true,
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nombre,
              autofocus: nuevo,
              maxLength: 120,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Nombre del establecimiento *',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _ciudad,
              maxLength: 80,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _guardar(),
              decoration: const InputDecoration(
                labelText: 'Ciudad (opcional)',
                border: OutlineInputBorder(),
              ),
            ),
            if (!nuevo)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _activo,
                activeThumbColor: _kColor,
                title: const Text('Activo'),
                subtitle: const Text(
                  'Inactivo no sale para programar ni en los grupos; sus '
                  'visitas se conservan.',
                  style: TextStyle(fontSize: 12),
                ),
                onChanged: (v) => setState(() => _activo = v),
              ),
            if (nuevo)
              const Text(
                'Después cárgale la ubicación en Visitas › Ubicaciones: sin '
                'ella no se le puede iniciar visita.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 12),
              ),
            ],
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
          onPressed: _guardar,
          child: Text(nuevo ? 'Agregar' : 'Guardar'),
        ),
      ],
    );
  }
}
