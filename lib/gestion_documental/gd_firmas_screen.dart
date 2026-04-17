// lib/gestion_documental/gd_firmas_screen.dart

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:signature/signature.dart';
import 'package:file_picker/file_picker.dart';
import '../widgets/internal_module_layout.dart';
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
  final _nameController = TextEditingController();
  final _cargoController = TextEditingController();
  
  final _signatureController = SignatureController(
    penStrokeWidth: 3,
    penColor: const Color(0xFF0F172A),
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

    return InternalModuleLayout(
      userId: widget.userId,
      empresaId: widget.empresaId,
      title: 'Identidad Digital',
      subtitle: 'Configuración de firma y datos para documentos oficiales',
      accentColor: GdPalette.accent,
      child: StreamBuilder<FirmaUsuarioDoc?>(
        stream: _service.streamFirmaUsuario(empresaId: widget.empresaId, userId: widget.userId),
        builder: (context, snapshot) {
          final firma = snapshot.data;
          
          if (firma != null && _nameController.text.isEmpty) {
            _nameController.text = firma.nombre;
            _cargoController.text = firma.cargo ?? '';
          }

          return isWeb ? _buildWebLayout(firma) : _buildMobileLayout(firma);
        },
      ),
    );
  }

  Widget _buildWebLayout(FirmaUsuarioDoc? firma) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(40),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 4,
                child: Column(
                  children: [
                    _buildIdentitySection(),
                    const SizedBox(height: 24),
                    _buildPreviewSection(firma),
                  ],
                ),
              ),
              const SizedBox(width: 32),
              Expanded(
                flex: 6,
                child: _buildSignatureCaptureSection(isWeb: true),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobileLayout(FirmaUsuarioDoc? firma) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildIdentitySection(),
          const SizedBox(height: 20),
          _buildSignatureCaptureSection(isWeb: false),
          const SizedBox(height: 20),
          _buildPreviewSection(firma),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildIdentitySection() {
    return ModuleCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'DATOS DE IDENTIDAD',
            style: TextStyle(
              fontFamily: kArial,
              fontWeight: FontWeight.w900,
              fontSize: 12,
              color: Color(0xFF94A3B8),
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            readOnly: true,
            decoration: InputDecoration(
              labelText: 'Nombre Completo',
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              prefixIcon: const Icon(Icons.person_outline, color: Color(0xFF64748B)),
            ),
            style: const TextStyle(fontFamily: kArial, fontSize: 14),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _cargoController,
            readOnly: true,
            decoration: InputDecoration(
              labelText: 'Cargo / Posición',
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              prefixIcon: const Icon(Icons.badge_outlined, color: Color(0xFF64748B)),
            ),
            style: const TextStyle(fontFamily: kArial, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildSignatureCaptureSection({required bool isWeb}) {
    return ModuleCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'CAPTURA DE FIRMA',
            style: TextStyle(
              fontFamily: kArial,
              fontWeight: FontWeight.w900,
              fontSize: 12,
              color: Color(0xFF94A3B8),
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 16),
          Stack(
            children: [
              Container(
                height: isWeb ? 400 : 250,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: const Color(0xFFE2E8F0)),
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
              Positioned(
                bottom: 60,
                left: 40,
                right: 40,
                child: IgnorePointer(
                  child: Column(
                    children: [
                      Container(height: 1, color: const Color(0xFFE2E8F0)),
                      const SizedBox(height: 4),
                      Text('FIRMAR AQUÍ', 
                        style: TextStyle(fontFamily: kArial, fontSize: 10, color: const Color(0xFF94A3B8).withOpacity(0.5), fontWeight: FontWeight.bold, letterSpacing: 2)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              _buildActionBtn(
                label: 'Limpiar',
                icon: Icons.refresh,
                onTap: () => _signatureController.clear(),
              ),
              const SizedBox(width: 12),
              _buildActionBtn(
                label: 'Subir PNG',
                icon: Icons.upload_file,
                onTap: _pickAndUpload,
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _loading ? null : _saveSignature,
                icon: const Icon(Icons.save_alt, size: 20),
                label: const Text('GUARDAR IDENTIDAD', 
                  style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: GdPalette.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  elevation: 0,
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
    return ModuleCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'FIRMA REGISTRADA',
            style: TextStyle(
              fontFamily: kArial,
              fontWeight: FontWeight.w900,
              fontSize: 12,
              color: Color(0xFF94A3B8),
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            height: 120,
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: firma?.urlFirma == null
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.info_outline, color: const Color(0xFF94A3B8).withOpacity(0.5)),
                    const SizedBox(height: 8),
                    const Text('Sin firma registrada', 
                      style: TextStyle(fontFamily: kArial, color: Color(0xFF64748B), fontSize: 12)),
                  ],
                )
              : Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Image.network(
                    firma!.urlFirma!, 
                    fit: BoxFit.contain,
                    errorBuilder: (c, e, s) => const Center(child: Icon(Icons.broken_image, color: Colors.redAccent)),
                  ),
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
        foregroundColor: const Color(0xFF0F172A),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Future<void> _pickAndUpload() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['png'],
        withData: true,
      );

      if (result != null && result.files.single.bytes != null) {
        final bytes = result.files.single.bytes!;
        _saveData(firmaBytes: bytes);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al seleccionar archivo: $e')));
      }
    }
  }

  Future<void> _saveSignature() async {
    Uint8List? bytes;
    if (!_signatureController.isEmpty) {
      bytes = await _signatureController.toPngBytes();
    }

    if (bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, dibuja tu firma o sube una imagen PNG.'))
      );
      return;
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
        firmaBytes: firmaBytes,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Identidad digital actualizada correctamente'),
            backgroundColor: Color(0xFF10B981),
          )
        );
        _signatureController.clear();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent)
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}
