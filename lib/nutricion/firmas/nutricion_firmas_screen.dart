import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:signature/signature.dart';

import '../../services/nutricion_service.dart';

class NutricionFirmasScreen extends StatefulWidget {
  final String empresaId;
  final String userId;

  const NutricionFirmasScreen({
    super.key,
    required this.empresaId,
    required this.userId,
  });

  @override
  State<NutricionFirmasScreen> createState() => _NutricionFirmasScreenState();
}

class _NutricionFirmasScreenState extends State<NutricionFirmasScreen> {
  final _service = NutricionService();
  final _picker = ImagePicker();
  final _firmaController = SignatureController(
    penStrokeWidth: 2.4,
    penColor: Colors.black,
    exportBackgroundColor: Colors.white,
  );

  @override
  void dispose() {
    _firmaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Firmas nutricionales',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'Dibuja o sube tu firma y sello como nutricionista. '
            'Estos datos se usarán al generar el reporte oficial.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          // Preview de firma y sello guardados
          StreamBuilder<Map<String, dynamic>?>(
            stream: _service.streamFirma(
              empresaId: widget.empresaId,
              userId: widget.userId,
            ),
            builder: (context, snapshot) {
              final data = snapshot.data;
              return Row(
                children: [
                  _buildImageCard('Firma guardada', data?['urlFirma']?.toString()),
                  const SizedBox(width: 16),
                  _buildImageCard('Sello guardado', data?['urlSello']?.toString()),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          // Card para dibujar firma
          Card(
            elevation: 0,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Dibujar firma',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 180,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Signature(
                        controller: _firmaController,
                        backgroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _firmaController.clear,
                        icon: const Icon(Icons.cleaning_services_outlined),
                        label: const Text('Limpiar'),
                      ),
                      FilledButton.icon(
                        onPressed: _saveDrawnSignature,
                        icon: const Icon(Icons.save_alt_outlined),
                        label: const Text('Guardar firma dibujada'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _pickAndUploadFirmaSello(isFirma: true),
                        icon: const Icon(Icons.upload_file_outlined),
                        label: const Text('Subir firma (archivo)'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () =>
                            _pickAndUploadFirmaSello(isFirma: false),
                        icon: const Icon(Icons.verified_outlined),
                        label: const Text('Subir sello (imagen)'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageCard(String title, String? url) {
    return Expanded(
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Container(
                height: 160,
                width: double.infinity,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: url == null || url.isEmpty
                    ? const Center(child: Text('Sin imagen'))
                    : Image.network(url, fit: BoxFit.contain),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickAndUploadFirmaSello({required bool isFirma}) async {
    final picked =
        await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    await _uploadFirmaSello(bytes, isFirma: isFirma);
  }

  Future<void> _saveDrawnSignature() async {
    try {
      if (_firmaController.isEmpty) {
        _snack('Primero dibuja la firma.');
        return;
      }
      final bytes = await _firmaController.toPngBytes(height: 300, width: 900);
      if (bytes == null || bytes.isEmpty) {
        _snack('No se pudo convertir la firma. Intenta nuevamente.');
        return;
      }
      await _uploadFirmaSello(bytes, isFirma: true);
      _firmaController.clear();
    } catch (e) {
      _snack('Error guardando firma dibujada: $e');
    }
  }

  Future<void> _uploadFirmaSello(Uint8List bytes,
      {required bool isFirma}) async {
    try {
      await _service.guardarFirma(
        empresaId: widget.empresaId,
        userId: widget.userId,
        firmaBytes: isFirma ? bytes : null,
        selloBytes: isFirma ? null : bytes,
      );
      _snack(
        isFirma
            ? 'Firma guardada correctamente.'
            : 'Sello guardado correctamente.',
      );
    } catch (e) {
      _snack('Error al cargar: $e');
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}
