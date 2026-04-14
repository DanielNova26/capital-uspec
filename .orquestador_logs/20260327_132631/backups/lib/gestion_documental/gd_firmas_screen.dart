// lib/gestion_documental/gd_firmas_screen.dart

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:signature/signature.dart';
import 'package:image_picker/image_picker.dart';
import 'gd_models.dart';
import 'gd_service.dart';
import 'widgets/gd_ui_widgets.dart';

class GdFirmasScreen extends StatefulWidget {
  final String empresaId;
  final String userId;

  const GdFirmasScreen({
    super.key,
    required this.empresaId,
    required this.userId,
  });

  @override
  State<GdFirmasScreen> createState() => _GdFirmasScreenState();
}

class _GdFirmasScreenState extends State<GdFirmasScreen> {
  final _service = GdService();
  final _picker = ImagePicker();
  final _nameController = TextEditingController();
  final _cargoController = TextEditingController();
  
  final _signatureController = SignatureController(
    penStrokeWidth: 3,
    penColor: Colors.black,
    exportBackgroundColor: Colors.white,
  );

  bool _loading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _cargoController.dispose();
    _signatureController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWeb = width >= 900;

    return Scaffold(
      backgroundColor: GdPalette.background,
      appBar: AppBar(
        title: const Text('Mi Identidad Digital', 
          style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.w900, fontSize: 18)),
        backgroundColor: GdPalette.primary,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<FirmaUsuarioDoc?>(
        stream: _service.streamFirmaUsuario(empresaId: widget.empresaId, userId: widget.userId),
        builder: (context, snapshot) {
          final firma = snapshot.data;
          
          // Inicializar controladores con datos existentes si están vacíos
          if (firma != null && _nameController.text.isEmpty) {
            _nameController.text = firma.nombre;
            _cargoController.text = firma.cargo ?? '';
          }

          return SingleChildScrollView(
            padding: EdgeInsets.all(isWeb ? 32 : 16),
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 800),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildIdentitySection(isWeb),
                    const SizedBox(height: 24),
                    _buildSignatureCaptureSection(isWeb),
                    const SizedBox(height: 24),
                    _buildPreviewSection(firma),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildIdentitySection(bool isWeb) {
    return GdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const GdSectionHeader(
            title: 'Datos de Identidad',
            subtitle: 'Esta información aparecerá bajo tu firma en los documentos aprobados.',
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Nombre Completo',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.person_outline),
            ),
            style: const TextStyle(fontFamily: kArial),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _cargoController,
            decoration: const InputDecoration(
              labelText: 'Cargo / Posición',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.badge_outlined),
            ),
            style: const TextStyle(fontFamily: kArial),
          ),
        ],
      ),
    );
  }

  Widget _buildSignatureCaptureSection(bool isWeb) {
    return GdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const GdSectionHeader(
            title: 'Captura de Firma',
            subtitle: 'Dibuja tu firma en el recuadro o sube una imagen PNG transparente.',
          ),
          const SizedBox(height: 8),
          Container(
            height: 250,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: GdPalette.border),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Signature(
                controller: _signatureController,
                backgroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _buildActionBtn(
                label: 'Limpiar',
                icon: Icons.refresh,
                onTap: () => _signatureController.clear(),
              ),
              _buildActionBtn(
                label: 'Subir PNG',
                icon: Icons.upload_file,
                onTap: _pickAndUpload,
              ),
              ElevatedButton.icon(
                onPressed: _loading ? null : _saveSignature,
                icon: const Icon(Icons.save_alt),
                label: const Text('GUARDAR IDENTIDAD', style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.w900)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: GdPalette.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewSection(FirmaUsuarioDoc? firma) {
    return GdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const GdSectionHeader(title: 'Firma Registrada Actual'),
          const SizedBox(height: 8),
          Container(
            height: 150,
            width: double.infinity,
            decoration: BoxDecoration(
              color: GdPalette.background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: GdPalette.border),
            ),
            child: firma?.urlFirma == null
              ? const Center(child: Text('Sin firma registrada', style: TextStyle(fontFamily: kArial, color: GdPalette.muted)))
              : Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Image.network(firma!.urlFirma!, fit: BoxFit.contain),
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionBtn({required String label, required IconData icon, required VoidCallback onTap}) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label.toUpperCase(), style: const TextStyle(fontFamily: kArial, fontWeight: FontWeight.w800, fontSize: 11)),
      style: OutlinedButton.styleFrom(
        foregroundColor: GdPalette.primary,
        side: const BorderSide(color: GdPalette.border),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Future<void> _pickAndUpload() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    
    final bytes = await picked.readAsBytes();
    _saveData(firmaBytes: bytes);
  }

  Future<void> _saveSignature() async {
    Uint8List? bytes;
    if (!_signatureController.isEmpty) {
      bytes = await _signatureController.toPngBytes();
    }
    _saveData(firmaBytes: bytes);
  }

  Future<void> _saveData({Uint8List? firmaBytes}) async {
    final nombre = _nameController.text.trim();
    final cargo = _cargoController.text.trim();

    if (nombre.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('El nombre es obligatorio.')));
      return;
    }

    setState(() => _loading = true);
    try {
      await _service.guardarFirmaUsuario(
        empresaId: widget.empresaId,
        userId: widget.userId,
        nombre: nombre,
        cargo: cargo,
        firmaBytes: firmaBytes,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Identidad digital actualizada correctamente.')));
        _signatureController.clear();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}
