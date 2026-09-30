import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/compras_productos_excel_parser.dart';
import '../services/compras_proveedores_excel_parser.dart';
import 'compras_models.dart';
import 'compras_service.dart';

/// Cargas operativas del catálogo. Las ejecuta el equipo de Compras desde su
/// módulo; Admin conserva únicamente la configuración y la copia entre empresas.
class ComprasCatalogImportScreen extends StatefulWidget {
  const ComprasCatalogImportScreen({
    super.key,
    required this.empresaId,
    required this.userId,
    this.service,
  });

  final String empresaId;
  final String userId;
  final ComprasService? service;

  @override
  State<ComprasCatalogImportScreen> createState() =>
      _ComprasCatalogImportScreenState();
}

class _ComprasCatalogImportScreenState
    extends State<ComprasCatalogImportScreen> {
  late final ComprasService _service =
      widget.service ?? ComprasService(actorId: widget.userId);
  Uint8List? _proveedoresBytes;
  Uint8List? _productosBytes;
  String? _proveedoresNombre;
  String? _productosNombre;
  bool _ocupado = false;
  String? _resultadoProveedores;
  String? _resultadoProductos;

  Future<void> _elegir({required bool proveedores}) async {
    final picked = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xlsm', 'xls'],
    );
    if (picked == null || picked.files.isEmpty || !mounted) return;
    final file = picked.files.first;
    setState(() {
      if (proveedores) {
        _proveedoresBytes = file.bytes;
        _proveedoresNombre = file.name;
        _resultadoProveedores = null;
      } else {
        _productosBytes = file.bytes;
        _productosNombre = file.name;
        _resultadoProductos = null;
      }
    });
  }

  Future<void> _importar({required bool proveedores}) async {
    final bytes = proveedores ? _proveedoresBytes : _productosBytes;
    if (bytes == null) return;
    final tipo = proveedores ? 'proveedores' : 'productos';
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Importar $tipo'),
        content: Text(
          'Se agregarán a la empresa activa los $tipo válidos del Excel. '
          'Los registros existentes se omitirán.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Importar'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;

    setState(() => _ocupado = true);
    try {
      late final Map<String, int> result;
      late final int invalidas;
      if (proveedores) {
        final parsed = ComprasProveedoresExcelParser().parse(
          bytes: bytes,
          empresaId: widget.empresaId,
        );
        if (parsed.proveedores.isEmpty) {
          throw const FormatException(
            'El archivo no contiene proveedores válidos.',
          );
        }
        result = await _service.importarProveedores(
          widget.empresaId,
          parsed.proveedores,
        );
        invalidas = parsed.skippedRows;
      } else {
        final parsed = ComprasProductosExcelParser().parse(
          bytes: bytes,
          empresaId: widget.empresaId,
          categoriasValidas: kCategoriasCompras,
          unidadesValidas: kUnidadesMedida,
        );
        if (parsed.productos.isEmpty) {
          throw const FormatException(
            'El archivo no contiene productos válidos.',
          );
        }
        result = await _service.importarProductos(
          widget.empresaId,
          parsed.productos,
        );
        invalidas = parsed.skippedRows;
      }
      if (!mounted) return;
      final message =
          '${result['importados'] ?? 0} $tipo importados; '
          '${(result['omitidos'] ?? 0) + invalidas} omitidos.';
      setState(() {
        if (proveedores) {
          _resultadoProveedores = message;
        } else {
          _resultadoProductos = message;
        }
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudieron importar $tipo: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Widget _carga({
    required String titulo,
    required String detalle,
    required bool proveedores,
  }) {
    final nombre = proveedores ? _proveedoresNombre : _productosNombre;
    final resultado = proveedores ? _resultadoProveedores : _resultadoProductos;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(detalle),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _ocupado
                      ? null
                      : () => _elegir(proveedores: proveedores),
                  icon: const Icon(Icons.attach_file),
                  label: Text(nombre ?? 'Seleccionar Excel'),
                ),
                FilledButton.icon(
                  onPressed: _ocupado || nombre == null
                      ? null
                      : () => _importar(proveedores: proveedores),
                  icon: const Icon(Icons.file_upload_outlined),
                  label: const Text('Importar'),
                ),
              ],
            ),
            if (resultado != null) ...[
              const SizedBox(height: 8),
              Text(resultado),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Cargar catálogo de Compras')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Estas cargas son del equipo de Compras en la empresa activa. '
              'Las marcas se crean y editan en la sección Marcas.',
            ),
            const SizedBox(height: 12),
            _carga(
              titulo: 'Proveedores',
              detalle:
                  'Columnas requeridas: NIT y RAZON SOCIAL. Se omite un '
                  'NIT ya registrado en esta empresa.',
              proveedores: true,
            ),
            _carga(
              titulo: 'Productos',
              detalle:
                  'Columnas requeridas: NOMBRE_PRODUCTO, CATEGORIA y '
                  'UNIDAD_MEDIDA. Se omite un código o nombre ya registrado.',
              proveedores: false,
            ),
          ],
        ),
      ),
    ),
  );
}
