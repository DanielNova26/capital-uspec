import 'package:flutter/material.dart';

import 'gd_correspondencia_models.dart';
import 'gd_correspondencia_service.dart';

const _navy = Color(0xFF17324D);
const _teal = Color(0xFF157A8A);
const _background = Color(0xFFF4F7FA);
const _border = Color(0xFFDCE5EC);
const _muted = Color(0xFF64748B);

/// Maestro de tipos documentales de una empresa.
///
/// El código de cada tipo es la raíz del código interno del expediente
/// (`TUT100826-001`), así que la pantalla insiste en dos cosas: que el código
/// sea corto y reconocible, y que no se repita. Lo segundo lo garantiza el
/// servicio por docId; aquí solo se muestra el mensaje.
class GdTiposDocumentalesScreen extends StatefulWidget {
  final String userId;
  final String empresaId;
  final String empresaNombre;

  const GdTiposDocumentalesScreen({
    super.key,
    required this.userId,
    required this.empresaId,
    this.empresaNombre = '',
  });

  @override
  State<GdTiposDocumentalesScreen> createState() =>
      _GdTiposDocumentalesScreenState();
}

class _GdTiposDocumentalesScreenState extends State<GdTiposDocumentalesScreen> {
  final _service = GdCorrespondenciaService();

  /// La stream se memoriza: recrearla en cada build reabre el listener de
  /// Firestore y en web termina en "INTERNAL ASSERTION FAILED".
  late Stream<List<GdTipoDocumental>> _tipos;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _tipos = _service.streamTiposDocumentales(widget.empresaId);
  }

  @override
  void didUpdateWidget(GdTiposDocumentalesScreen old) {
    super.didUpdateWidget(old);
    if (old.empresaId != widget.empresaId) {
      _tipos = _service.streamTiposDocumentales(widget.empresaId);
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

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on GdTipoDocumentalError catch (error) {
      _message(error.mensaje, error: true);
    } catch (error) {
      _message('No fue posible completar la operación: $error', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sembrar() => _run(() async {
    final creados = await _service.sembrarTiposBase(
      empresaId: widget.empresaId,
      userId: widget.userId,
    );
    _message(
      creados == 0
          ? 'Los tipos base ya estaban creados.'
          : 'Se crearon $creados tipos documentales base.',
    );
  });

  Future<void> _codificarHistoricos() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Codificar expedientes históricos'),
        content: const Text(
          'Se asignará el código de tres letras, fecha original y consecutivo '
          'a los expedientes que todavía no lo tengan. Los códigos existentes '
          'no se modificarán y la operación puede repetirse con seguridad.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.tag),
            label: const Text('Generar códigos'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(() async {
      final result = await _service.codificarExpedientesHistoricos(
        empresaId: widget.empresaId,
        userId: widget.userId,
      );
      final updated = (result['actualizados'] as num?)?.toInt() ?? 0;
      final already = (result['yaCodificados'] as num?)?.toInt() ?? 0;
      final withoutType = (result['sinTipo'] as num?)?.toInt() ?? 0;
      final withoutDate = (result['sinFecha'] as num?)?.toInt() ?? 0;
      final errors = (result['errores'] as num?)?.toInt() ?? 0;
      _message(
        'Históricos: $updated codificados, $already ya tenían código, '
        '${withoutType + withoutDate} pendientes de datos, $errors errores.',
        error: errors > 0,
      );
    });
  }

  Future<void> _editar({GdTipoDocumental? existente}) async {
    final nombre = TextEditingController(text: existente?.nombre ?? '');
    final codigo = TextEditingController(text: existente?.codigo ?? '');
    final alias = TextEditingController(text: existente?.alias ?? '');
    // Con el tipo ya creado el código no se toca: los expedientes codificados
    // con esa raíz quedarían sin referencia.
    final codigoFijo = existente != null;
    var codigoTocado = codigoFijo;

    final guardar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setDialogState) => AlertDialog(
          title: Text(
            existente == null ? 'Nuevo tipo documental' : 'Editar tipo',
          ),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nombre,
                    autofocus: true,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Nombre del tipo',
                      hintText: 'Tutela, Derecho de petición, SST…',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      // Se propone la raíz mientras nadie la haya escrito a
                      // mano; en cuanto el usuario la edita, se respeta.
                      if (codigoTocado) return;
                      setDialogState(() {
                        codigo.text = GdTipoDocumental.codigoSugerido(value);
                      });
                    },
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: codigo,
                    enabled: !codigoFijo,
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 3,
                    decoration: InputDecoration(
                      labelText: 'Código',
                      helperText: codigoFijo
                          ? 'El código no se puede cambiar después de crear el tipo.'
                          : 'Raíz obligatoria de exactamente tres caracteres.',
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      codigoTocado = true;
                      final limpio = GdTipoDocumental.normalizarCodigo(value);
                      if (limpio == value) {
                        setDialogState(() {});
                        return;
                      }
                      setDialogState(() {
                        codigo.value = TextEditingValue(
                          text: limpio,
                          selection: TextSelection.collapsed(
                            offset: limpio.length,
                          ),
                        );
                      });
                    },
                  ),
                  const SizedBox(height: 6),
                  _EjemploCodigo(codigo: codigo.text),
                  const SizedBox(height: 14),
                  TextField(
                    controller: alias,
                    decoration: const InputDecoration(
                      labelText: 'Alias (opcional)',
                      helperText:
                          'Otros nombres con los que la gente busca este tipo.',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );

    final valores = (
      codigo: codigo.text,
      nombre: nombre.text,
      alias: alias.text,
    );
    nombre.dispose();
    codigo.dispose();
    alias.dispose();
    if (guardar != true) return;
    await _run(
      () => _service.guardarTipoDocumental(
        empresaId: widget.empresaId,
        userId: widget.userId,
        codigo: valores.codigo,
        nombre: valores.nombre,
        alias: valores.alias,
        activo: existente?.activo ?? true,
        idExistente: existente?.id,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
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
              'Tipos documentales',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
            Text(
              widget.empresaNombre.isEmpty
                  ? 'TBL_GD_TIPOS_DOCUMENTALES'
                  : 'TBL_GD_TIPOS_DOCUMENTALES · ${widget.empresaNombre}',
              style: const TextStyle(fontWeight: FontWeight.w400, fontSize: 11),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : () => _editar(),
        backgroundColor: _teal,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo tipo'),
      ),
      body: StreamBuilder<List<GdTipoDocumental>>(
        stream: _tipos,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No fue posible cargar el maestro: ${snapshot.error}',
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snapshot.data!;
          return ListView(
            padding: EdgeInsets.all(wide ? 24 : 14),
            children: [
              const _Explicacion(),
              const SizedBox(height: 18),
              if (rows.isEmpty)
                _VacioMaestro(onSembrar: _busy ? null : _sembrar)
              else ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${rows.length} tipos · '
                        '${rows.where((e) => e.activo).length} activos',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: _navy,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _busy ? null : _sembrar,
                      icon: const Icon(Icons.playlist_add, size: 18),
                      label: const Text('Agregar los base que falten'),
                    ),
                  ],
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _codificarHistoricos,
                    icon: const Icon(Icons.history_toggle_off, size: 18),
                    label: const Text('Codificar expedientes históricos'),
                  ),
                ),
                const SizedBox(height: 10),
                ...rows.map(
                  (tipo) => _TipoTile(
                    tipo: tipo,
                    onEdit: _busy ? null : () => _editar(existente: tipo),
                    onToggle: _busy
                        ? null
                        : (value) => _run(
                            () => _service.cambiarEstadoTipoDocumental(
                              id: tipo.id,
                              userId: widget.userId,
                              activo: value,
                            ),
                          ),
                  ),
                ),
              ],
              const SizedBox(height: 80),
            ],
          );
        },
      ),
    );
  }
}

class _Explicacion extends StatelessWidget {
  const _Explicacion();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _border),
    ),
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'De aquí sale el código interno del expediente',
          style: TextStyle(fontWeight: FontWeight.w900, color: _navy),
        ),
        SizedBox(height: 8),
        Text(
          'Al clasificar, el expediente recibe un código formado por el código '
          'del tipo, la fecha y el consecutivo del día: TUT100826-001. Con solo '
          'verlo se sabe qué tipo de documento es y de cuándo, sin abrirlo.',
          style: TextStyle(height: 1.4, color: _muted, fontSize: 13),
        ),
        SizedBox(height: 8),
        Text(
          'Todos los códigos tienen exactamente tres caracteres y no se '
          'repiten dentro de la empresa. Si "Calidad" usa CAL, otro tipo debe '
          'usar una abreviatura distinta de tres caracteres, por ejemplo CAI.',
          style: TextStyle(height: 1.4, color: _muted, fontSize: 13),
        ),
      ],
    ),
  );
}

class _EjemploCodigo extends StatelessWidget {
  final String codigo;
  const _EjemploCodigo({required this.codigo});

  @override
  Widget build(BuildContext context) {
    final limpio = GdTipoDocumental.normalizarCodigo(codigo);
    if (limpio.length != 3) return const SizedBox.shrink();
    final now = DateTime.now();
    final dd = now.day.toString().padLeft(2, '0');
    final mm = now.month.toString().padLeft(2, '0');
    final yy = (now.year % 100).toString().padLeft(2, '0');
    return Text(
      'Los expedientes de hoy quedarían como $limpio$dd$mm$yy-001',
      style: const TextStyle(fontSize: 12, color: _teal),
    );
  }
}

class _VacioMaestro extends StatelessWidget {
  final VoidCallback? onSembrar;
  const _VacioMaestro({required this.onSembrar});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _border),
    ),
    child: Column(
      children: [
        const Icon(Icons.sell_outlined, size: 40, color: Color(0xFFCBD5E1)),
        const SizedBox(height: 10),
        const Text(
          'Esta empresa todavía no tiene tipos documentales',
          style: TextStyle(fontWeight: FontWeight.w800, color: _navy),
        ),
        const SizedBox(height: 6),
        const Text(
          'Mientras el maestro esté vacío, al clasificar se ofrece la lista '
          'antigua y el expediente no recibe código interno.',
          textAlign: TextAlign.center,
          style: TextStyle(color: _muted, fontSize: 13, height: 1.4),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: onSembrar,
          icon: const Icon(Icons.playlist_add),
          label: const Text('Crear los tipos base'),
          style: FilledButton.styleFrom(backgroundColor: _teal),
        ),
      ],
    ),
  );
}

class _TipoTile extends StatelessWidget {
  final GdTipoDocumental tipo;
  final VoidCallback? onEdit;
  final ValueChanged<bool>? onToggle;

  const _TipoTile({
    required this.tipo,
    required this.onEdit,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _border),
    ),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: (tipo.activo ? _teal : _muted).withValues(alpha: .10),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(
            tipo.codigo,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: tipo.activo ? _teal : _muted,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tipo.nombre,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: _navy,
                ),
              ),
              if (tipo.alias.trim().isNotEmpty)
                Text(
                  tipo.alias,
                  style: const TextStyle(fontSize: 12, color: _muted),
                ),
            ],
          ),
        ),
        IconButton(
          onPressed: onEdit,
          tooltip: 'Editar nombre y alias',
          icon: const Icon(Icons.edit_outlined, size: 20),
        ),
        Switch(value: tipo.activo, onChanged: onToggle),
      ],
    ),
  );
}
