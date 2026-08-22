import 'package:flutter/material.dart';

import '../../widgets/user_avatar.dart';
import 'gd_correspondencia_models.dart';
import 'gd_correspondencia_service.dart';
import 'gd_permisos.dart';

const _navy = Color(0xFF17324D);
const _teal = Color(0xFF157A8A);
const _background = Color(0xFFF4F7FA);
const _border = Color(0xFFDCE5EC);
const _muted = Color(0xFF64748B);

/// Roles de Correspondencia de la empresa activa.
///
/// Antes de esta pantalla `TBL_CORREO_ROLES` solo se podía tocar a mano en
/// Firestore, así que en la práctica cualquiera que entrara al módulo podía
/// clasificar y asignar. De ahí salió el requisito: "solo hay unos usuarios,
/// ponle ahí clasificadores y asignadores, y nosotros los definimos".
class GdRolesScreen extends StatefulWidget {
  final String userId;
  final String empresaId;
  final String empresaNombre;

  const GdRolesScreen({
    super.key,
    required this.userId,
    required this.empresaId,
    this.empresaNombre = '',
  });

  @override
  State<GdRolesScreen> createState() => _GdRolesScreenState();
}

class _GdRolesScreenState extends State<GdRolesScreen> {
  final _service = GdCorrespondenciaService();
  final _permisosService = GdPermisosService();
  final _search = TextEditingController();

  List<GdResponsable> _usuarios = const [];
  Map<String, GdRolCorrespondencia> _asignados = const {};
  String _query = '';
  bool _loading = true;
  bool _busy = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final usuarios = await _service.listarResponsables(widget.empresaId);
      final asignados = await _permisosService.rolesAsignados(widget.empresaId);
      if (!mounted) return;
      setState(() {
        _usuarios = usuarios;
        _asignados = asignados;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'No fue posible cargar los usuarios: $error';
        _loading = false;
      });
    }
  }

  void _message(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? const Color(0xFFB91C1C) : _teal,
      ),
    );
  }

  /// Rol efectivo que se muestra. Quien no tiene rol explícito aparece con el
  /// rol por defecto, no en blanco: en blanco daría a entender que no tiene
  /// acceso, y sí lo tiene para lo que se le asigne.
  GdRolCorrespondencia _rolDe(String userId) =>
      _asignados[userId] ?? GdPermisosService.rolPorDefecto;

  bool _esExplicito(String userId) => _asignados.containsKey(userId);

  Future<void> _cambiar(GdResponsable usuario, GdRolCorrespondencia rol) async {
    if (_busy) return;
    final actual = _rolDe(usuario.id);
    if (actual == rol && _esExplicito(usuario.id)) return;

    // Quitar el permiso de clasificar a alguien puede dejar sin clasificadores
    // a la empresa; y quitárselo a sí mismo deja al administrador fuera de la
    // función que acaba de usar. Las dos cosas se confirman.
    final quitaClasificar =
        GdPermisos(actual).puedeClasificar && !GdPermisos(rol).puedeClasificar;
    final esYoMismo = usuario.id == widget.userId;
    if (quitaClasificar || esYoMismo) {
      final ok = await _confirmar(usuario, rol, esYoMismo: esYoMismo);
      if (ok != true) return;
    }

    setState(() => _busy = true);
    try {
      await _permisosService.asignarRol(
        empresaId: widget.empresaId,
        userId: usuario.id,
        rol: rol,
        asignadoPor: widget.userId,
      );
      if (!mounted) return;
      setState(() {
        _asignados = {..._asignados, usuario.id: rol};
        _busy = false;
      });
      _message('${usuario.nombre}: ${rol.etiqueta}.');
    } catch (error) {
      if (mounted) setState(() => _busy = false);
      _message('No fue posible guardar el rol: $error', error: true);
    }
  }

  Future<bool?> _confirmar(
    GdResponsable usuario,
    GdRolCorrespondencia rol, {
    required bool esYoMismo,
  }) => showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Confirmar cambio de rol'),
      content: Text(
        esYoMismo
            ? 'Estás cambiando tu propio rol a "${rol.etiqueta}". '
                  'Si dejas de ser administrador no podrás volver a entrar aquí '
                  'a corregirlo.'
            : '${usuario.nombre} dejará de poder clasificar y asignar '
                  'correspondencia. Seguirá trabajando los expedientes que se '
                  'le asignen.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Cambiar rol'),
        ),
      ],
    ),
  );

  Future<void> _volverAlDefecto(GdResponsable usuario) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _permisosService.quitarRol(
        empresaId: widget.empresaId,
        userId: usuario.id,
      );
      if (!mounted) return;
      final restantes = {..._asignados}..remove(usuario.id);
      setState(() {
        _asignados = restantes;
        _busy = false;
      });
      _message(
        '${usuario.nombre} vuelve al rol por defecto '
        '(${GdPermisosService.rolPorDefecto.etiqueta}).',
      );
    } catch (error) {
      if (mounted) setState(() => _busy = false);
      _message('No fue posible quitar el rol: $error', error: true);
    }
  }

  List<GdResponsable> get _visibles {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return _usuarios;
    return _usuarios
        .where(
          (u) => '${u.nombre} ${u.id} ${u.areaNombre} ${u.cargo}'
              .toLowerCase()
              .contains(query),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final clasificadores = _usuarios
        .where((u) => GdPermisos(_rolDe(u.id)).puedeClasificar)
        .length;

    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _navy,
        surfaceTintColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Roles de Correspondencia',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
            Text(
              widget.empresaNombre.isEmpty
                  ? 'TBL_CORREO_ROLES'
                  : 'TBL_CORREO_ROLES · ${widget.empresaNombre}',
              style: const TextStyle(fontWeight: FontWeight.w400, fontSize: 11),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _loading ? null : _cargar,
            tooltip: 'Recargar',
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _cargar,
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: EdgeInsets.all(wide ? 24 : 14),
              children: [
                _Explicacion(clasificadores: clasificadores),
                const SizedBox(height: 16),
                TextField(
                  controller: _search,
                  onChanged: (value) => setState(() => _query = value),
                  decoration: InputDecoration(
                    hintText: 'Buscar por nombre, cédula, área o cargo',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: _border),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                if (_visibles.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 36),
                    child: Center(
                      child: Text(
                        'Ningún usuario coincide con la búsqueda.',
                        style: TextStyle(color: _muted),
                      ),
                    ),
                  )
                else
                  ..._visibles.map(
                    (usuario) => _UsuarioRolTile(
                      usuario: usuario,
                      rol: _rolDe(usuario.id),
                      explicito: _esExplicito(usuario.id),
                      habilitado: !_busy,
                      onRol: (rol) => _cambiar(usuario, rol),
                      onDefecto: () => _volverAlDefecto(usuario),
                    ),
                  ),
                const SizedBox(height: 40),
              ],
            ),
    );
  }
}

class _Explicacion extends StatelessWidget {
  final int clasificadores;
  const _Explicacion({required this.clasificadores});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quién puede clasificar y asignar',
          style: TextStyle(fontWeight: FontWeight.w900, color: _navy),
        ),
        const SizedBox(height: 8),
        const Text(
          'Clasificar define qué es el documento, quién responde y para cuándo. '
          'Es la decisión de fondo del proceso, así que solo la toma quien tenga '
          'el rol. El resto entra al tablero, consulta y trabaja lo que se le '
          'asigne.',
          style: TextStyle(height: 1.4, color: _muted, fontSize: 13),
        ),
        const SizedBox(height: 12),
        ...GdRolCorrespondencia.values.reversed.map(
          (rol) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: _teal,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${rol.etiqueta}: ',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: _navy,
                            fontSize: 12.5,
                          ),
                        ),
                        TextSpan(
                          text: rol.descripcion,
                          style: const TextStyle(
                            color: _muted,
                            fontSize: 12.5,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 20),
        Row(
          children: [
            Icon(
              clasificadores == 0
                  ? Icons.warning_amber_rounded
                  : Icons.verified_user_outlined,
              size: 18,
              color: clasificadores == 0 ? const Color(0xFFB45309) : _teal,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                clasificadores == 0
                    ? 'Ningún usuario puede clasificar en esta empresa. La '
                          'correspondencia que entre quedará sin asignar.'
                    : '$clasificadores '
                          '${clasificadores == 1 ? "usuario puede" : "usuarios pueden"} '
                          'clasificar y asignar en esta empresa.',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: clasificadores == 0
                      ? const Color(0xFF9A3412)
                      : _navy,
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _UsuarioRolTile extends StatelessWidget {
  final GdResponsable usuario;
  final GdRolCorrespondencia rol;
  final bool explicito;
  final bool habilitado;
  final ValueChanged<GdRolCorrespondencia> onRol;
  final VoidCallback onDefecto;

  const _UsuarioRolTile({
    required this.usuario,
    required this.rol,
    required this.explicito,
    required this.habilitado,
    required this.onRol,
    required this.onDefecto,
  });

  Widget _identidad() => Row(
    children: [
      UserAvatar(userId: usuario.id, nameHint: usuario.nombre, radius: 18),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              usuario.nombre,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: _navy,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              [
                if (usuario.cargo.isNotEmpty) usuario.cargo,
                if (usuario.areaNombre.isNotEmpty) usuario.areaNombre,
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: _muted),
            ),
            if (!explicito)
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Text(
                  'Rol por defecto (sin asignar)',
                  style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                ),
              ),
          ],
        ),
      ),
    ],
  );

  Widget _selector() => Row(
    children: [
      Expanded(
        child: DropdownButtonFormField<GdRolCorrespondencia>(
          initialValue: rol,
          isExpanded: true,
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          ),
          items: GdRolCorrespondencia.values
              .map(
                (value) => DropdownMenuItem(
                  value: value,
                  child: Text(
                    value.etiqueta,
                    style: const TextStyle(fontSize: 12.5),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: habilitado
              ? (value) {
                  if (value != null) onRol(value);
                }
              : null,
        ),
      ),
      IconButton(
        onPressed: habilitado && explicito ? onDefecto : null,
        tooltip: 'Quitar el rol asignado y volver al defecto',
        icon: const Icon(Icons.settings_backup_restore, size: 20),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final puedeClasificar = GdPermisos(rol).puedeClasificar;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: puedeClasificar ? _teal.withValues(alpha: .35) : _border,
        ),
      ),
      // En móvil el selector no cabe al lado del nombre: los nombres largos y
      // "Clasificador y asignador" juntos desbordan la fila. Debajo, a lo ancho.
      child: LayoutBuilder(
        builder: (context, constraints) => constraints.maxWidth < 560
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _identidad(),
                  const SizedBox(height: 10),
                  _selector(),
                ],
              )
            : Row(
                children: [
                  Expanded(child: _identidad()),
                  const SizedBox(width: 12),
                  SizedBox(width: 258, child: _selector()),
                ],
              ),
      ),
    );
  }
}
