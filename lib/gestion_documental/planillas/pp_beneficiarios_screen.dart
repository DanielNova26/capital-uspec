import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../widgets/paged_list.dart';
import 'pp_beneficiarios_service.dart';
import 'pp_archivo_plano.dart';
import 'pp_cuentas_excel_parser.dart';
import 'pp_cuentas_models.dart';

/// Maestro de beneficiarios de pago.
///
/// Proveedores y, más adelante, personal. Lo que se guarda aquí es lo que el
/// banco necesita para pagarle a alguien; el archivo plano lo toma de aquí
/// cuando la planilla no lo trae.
class PpBeneficiariosScreen extends StatefulWidget {
  final String empresaId;
  final String userId;

  const PpBeneficiariosScreen({
    super.key,
    required this.empresaId,
    required this.userId,
  });

  @override
  State<PpBeneficiariosScreen> createState() => _PpBeneficiariosScreenState();
}

class _PpBeneficiariosScreenState extends State<PpBeneficiariosScreen> {
  final _svc = PpBeneficiariosService();
  final _buscarCtrl = TextEditingController();
  String _busqueda = '';
  bool _importando = false;

  @override
  void dispose() {
    _buscarCtrl.dispose();
    super.dispose();
  }

  /// Filtra por nombre, identificación o banco.
  ///
  /// El banco entra en la búsqueda porque "sácame los de Davivienda" es una
  /// pregunta que Tesorería hace de verdad, y se busca por su **nombre**, no
  /// por el código: nadie recuerda que Davivienda es 0051.
  List<CuentaBancaria> _filtrar(List<CuentaBancaria> todas) {
    final q = _busqueda.trim().toLowerCase();
    if (q.isEmpty) return todas;
    return todas.where((c) {
      return c.nombre.toLowerCase().contains(q) ||
          c.cedula.toLowerCase().contains(q) ||
          nombreBanco(c.bancoCodigo).toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Beneficiarios de pago'),
        actions: [
          IconButton(
            tooltip: 'Importar desde Excel',
            onPressed: _importando ? null : _importar,
            icon: _importando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.upload_file_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editar(null),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Nuevo'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _buscarCtrl,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Buscar por nombre, identificación o banco',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _busqueda = v),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<CuentaBancaria>>(
              stream: _svc.stream(widget.empresaId),
              builder: (context, snap) {
                if (snap.hasError) {
                  // Casi siempre es falta de permiso, no una caída.
                  return const _Aviso(
                    icono: Icons.lock_outline,
                    texto:
                        'No tienes permiso para ver el maestro de '
                        'beneficiarios. Es de Tesorería.',
                  );
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final lista = _filtrar(snap.data!);
                if (lista.isEmpty) {
                  return _Aviso(
                    icono: Icons.account_balance_outlined,
                    texto: snap.data!.isEmpty
                        ? 'Todavía no hay beneficiarios. Créalos uno a uno o '
                              'importa el Excel de Tesorería.'
                        : 'Ningún beneficiario coincide con la búsqueda.',
                  );
                }
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
                  child: PagedListSection<CuentaBancaria>(
                    items: lista,
                    etiqueta: 'beneficiarios',
                    itemBuilder: (_, c, _) => _fila(c),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _fila(CuentaBancaria c) => Card(
    margin: const EdgeInsets.only(bottom: 8),
    child: ListTile(
      title: Text(
        c.nombre.isEmpty ? c.cedula : c.nombre,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        '${c.cedula} · ${nombreBanco(c.bancoCodigo)} · '
        '${c.tipoCuenta.trim() == '1' ? 'Corriente' : 'Ahorros'}',
      ),
      trailing: IconButton(
        icon: const Icon(Icons.edit_outlined),
        onPressed: () => _editar(c),
      ),
      onTap: () => _editar(c),
    ),
  );

  /// Abre la ficha. Pide el número aparte, solo al abrir.
  Future<void> _editar(CuentaBancaria? existente) async {
    // El número no viene en el listado: se pide aquí, para una sola persona.
    // Traerlos todos para pintar la lista sería exponer de más.
    final numero = existente == null
        ? ''
        : await _svc.numeroDe(widget.empresaId, existente.cedula);
    if (!mounted) return;

    final idCtrl = TextEditingController(text: existente?.cedula ?? '');
    final nombreCtrl = TextEditingController(text: existente?.nombre ?? '');
    final cuentaCtrl = TextEditingController(text: numero);
    var banco = normalizarCodigoBanco(existente?.bancoCodigo ?? '0013');
    var tipoCuenta = (existente?.tipoCuenta ?? '2').trim();
    var intento = false;

    final guardar = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(
            existente == null ? 'Nuevo beneficiario' : 'Beneficiario',
          ),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: idCtrl,
                    // La identificación es el id del documento: cambiarla en
                    // uno que ya existe crearía otro y dejaría el viejo suelto.
                    enabled: existente == null,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Cédula o NIT (sin puntos)',
                      border: const OutlineInputBorder(),
                      errorText: intento && idCtrl.text.trim().isEmpty
                          ? 'Obligatorio'
                          : null,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: nombreCtrl,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      labelText: 'Nombre o razón social',
                      helperText:
                          'El banco admite $kPlanoMaxNombre caracteres.',
                      border: const OutlineInputBorder(),
                      errorText:
                          intento &&
                              nombreCtrl.text.trim().length > kPlanoMaxNombre
                          ? 'Son ${nombreCtrl.text.trim().length}'
                          : null,
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Se elige el banco por su nombre. El código es un dato del
                  // banco, no algo que nadie deba recordar, y un dígito mal
                  // escrito manda el dinero a otra entidad.
                  DropdownButtonFormField<String>(
                    initialValue: kBancosAch.containsKey(banco) ? banco : null,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Banco',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final e in kBancosAch.entries)
                        DropdownMenuItem(
                          value: e.key,
                          child: Text(
                            '${e.value} · ${e.key}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (v) => setLocal(() => banco = v ?? banco),
                  ),
                  if (!kBancosAch.containsKey(banco)) ...[
                    const SizedBox(height: 4),
                    Text(
                      // Pasa de verdad: hay gente cobrando en códigos que el
                      // catálogo del Excel no tiene. Se conserva el que hay.
                      'Código actual $banco, que no está en el catálogo. '
                      'Se conserva si no eliges otro.',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.orange,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: tipoCuenta == '1' ? '1' : '2',
                    decoration: const InputDecoration(
                      labelText: 'Tipo de cuenta',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: '1', child: Text('Corriente')),
                      DropdownMenuItem(value: '2', child: Text('Ahorros')),
                    ],
                    onChanged: (v) => setLocal(() => tipoCuenta = v ?? '2'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: cuentaCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Número de cuenta',
                      helperText: numero.isEmpty && existente != null
                          ? 'Vacío: o no está registrado, o no tienes permiso '
                                'para verlo.'
                          : 'Solo dígitos.',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            if (existente != null)
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              )
            else
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
            FilledButton(
              onPressed: () {
                if (idCtrl.text.trim().isEmpty ||
                    nombreCtrl.text.trim().length > kPlanoMaxNombre) {
                  setLocal(() => intento = true);
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );

    final cuenta = CuentaBancaria(
      cedula: idCtrl.text.trim(),
      empresaId: widget.empresaId,
      nombre: nombreCtrl.text.trim(),
      bancoCodigo: banco,
      numeroCuenta: cuentaCtrl.text.trim(),
      tipoCuenta: tipoCuenta,
      tipoId: idCtrl.text.trim().length > 10 ? '2' : '1',
    );
    idCtrl.dispose();
    nombreCtrl.dispose();
    cuentaCtrl.dispose();
    if (guardar != true || !mounted) return;

    try {
      await _svc.guardar(cuenta, actorId: widget.userId);
      if (mounted) _aviso('Beneficiario guardado.');
    } catch (e) {
      if (mounted) _aviso('No se pudo guardar: $e', error: true);
    }
  }

  /// Importa el Excel de Tesorería.
  Future<void> _importar() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
      withData: true,
    );
    final bytes = res?.files.single.bytes;
    if (bytes == null || !mounted) return;

    setState(() => _importando = true);
    try {
      final leidas = PpCuentasExcelParser().parse(
        bytes: bytes,
        empresaId: widget.empresaId,
      );
      final analisis = analizarImportacionCuentas(
        leidas,
        codigosBancoConocidos: kBancosAch.keys.toSet(),
      );
      if (!mounted) return;

      // Se enseña lo encontrado ANTES de escribir. Importar a ciegas un maestro
      // de cuentas bancarias y revisarlo después es al revés.
      final seguir = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('${leidas.length} fila(s) leídas'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Se van a guardar ${analisis.listas.length}.'),
                  if (analisis.bloqueos.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      '${analisis.bloqueos.length} no entran:',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    for (final b in analisis.bloqueos.take(10))
                      Text('· $b', style: const TextStyle(fontSize: 12)),
                  ],
                  if (analisis.avisos.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      '${analisis.avisos.length} entran con aviso:',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    for (final a in analisis.avisos.take(10))
                      Text('· $a', style: const TextStyle(fontSize: 12)),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: analisis.listas.isEmpty
                  ? null
                  : () => Navigator.pop(ctx, true),
              child: const Text('Importar'),
            ),
          ],
        ),
      );
      if (seguir != true || !mounted) return;

      final n = await _svc.importar(analisis.listas, actorId: widget.userId);
      if (mounted) _aviso('$n beneficiario(s) importados.');
    } catch (e) {
      if (mounted) _aviso('No se pudo importar: $e', error: true);
    } finally {
      if (mounted) setState(() => _importando = false);
    }
  }

  void _aviso(String texto, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texto),
        backgroundColor: error ? Colors.red.shade600 : null,
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  final IconData icono;
  final String texto;

  const _Aviso({required this.icono, required this.texto});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 44, color: Colors.black26),
          const SizedBox(height: 12),
          Text(
            texto,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black54),
          ),
        ],
      ),
    ),
  );
}
