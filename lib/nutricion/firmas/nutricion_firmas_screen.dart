import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

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

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Firmas y sellos', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          StreamBuilder<Map<String, dynamic>?>(
            stream: _service.streamFirma(empresaId: widget.empresaId, userId: widget.userId),
            builder: (context, snapshot) {
              final data = snapshot.data;
              return Row(
                children: [
                  _buildImageCard('Firma', data?['urlFirma']),
                  const SizedBox(width: 16),
                  _buildImageCard('Sello', data?['urlSello']),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            children: [
              OutlinedButton.icon(
                onPressed: () => _pickAndUpload(isFirma: true),
                icon: const Icon(Icons.draw),
                label: const Text('Subir firma'),
              ),
              OutlinedButton.icon(
                onPressed: () => _pickAndUpload(isFirma: false),
                icon: const Icon(Icons.verified),
                label: const Text('Subir sello'),
              ),
            ],
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
                child: url == null
                    ? const Center(child: Text('Sin imagen'))
                    : Image.network(url, fit: BoxFit.contain),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickAndUpload({required bool isFirma}) async {
    final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    await _upload(bytes, isFirma: isFirma);
  }

  Future<void> _upload(Uint8List bytes, {required bool isFirma}) async {
    try {
      await _service.guardarFirma(
        empresaId: widget.empresaId,
        userId: widget.userId,
        firmaBytes: isFirma ? bytes : null,
        selloBytes: isFirma ? null : bytes,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Imagen cargada correctamente.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al cargar: $e')),
      );
    }
  }
}