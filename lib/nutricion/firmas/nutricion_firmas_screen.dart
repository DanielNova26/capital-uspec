// lib/nutricion/firmas/nutricion_firmas_screen.dart

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:signature/signature.dart';
import 'package:todo/theme/app_typography.dart';

import '../../services/nutricion_service.dart';
import '../widgets/nutrition_shared_widgets.dart';

class NutricionFirmasScreen extends StatefulWidget {
  final String empresaId;
  final String userId;
  final bool showAppBar;

  const NutricionFirmasScreen({
    super.key,
    required this.empresaId,
    required this.userId,
    this.showAppBar = true,
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
    final bool isWide = MediaQuery.of(context).size.width >= 900;

    final content = SingleChildScrollView(
      padding: EdgeInsets.all(isWide ? 32 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!widget.showAppBar) _buildWebHeaderContext(),
          
          Text('Identidad Profesional', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: NutritionPalette.textMain, fontFamily: kArial)),
          const SizedBox(height: 8),
          Text(
            'Gestiona tu firma digital y sello profesional para la validación de reportes clínicos.',
            style: TextStyle(color: NutritionPalette.textMuted, fontSize: 14),
          ),
          const SizedBox(height: 24),

          // Preview de firma y sello guardados
          StreamBuilder<Map<String, dynamic>?>(
            stream: _service.streamFirma(empresaId: widget.empresaId, userId: widget.userId),
            builder: (context, snapshot) {
              final data = snapshot.data;
              return Row(
                children: [
                  _buildPreviewCard('Firma Registrada', data?['urlFirma']?.toString(), Icons.draw_outlined),
                  const SizedBox(width: 16),
                  _buildPreviewCard('Sello Registrado', data?['urlSello']?.toString(), Icons.verified_outlined),
                ],
              );
            },
          ),
          const SizedBox(height: 24),

          // Card para dibujar firma
          NutritionCard(
            title: 'CAPTURA DE FIRMA DIGITAL',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 200,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: NutritionPalette.border),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Signature(controller: _firmaController, backgroundColor: Colors.white),
                  ),
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _SignatureActionBtn(label: 'Limpiar', icon: Icons.refresh, onTap: _firmaController.clear),
                    _SignatureActionBtn(label: 'Guardar Trazo', icon: Icons.save_alt, onTap: _saveDrawnSignature, primary: true),
                    _SignatureActionBtn(label: 'Subir Firma', icon: Icons.upload_file, onTap: () => _pickAndUpload(isFirma: true)),
                    _SignatureActionBtn(label: 'Subir Sello', icon: Icons.verified, onTap: () => _pickAndUpload(isFirma: false)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (!widget.showAppBar) return content;

    return Scaffold(
      backgroundColor: NutritionPalette.background,
      appBar: AppBar(
        title: const Text('Firmas y Sellos', style: TextStyle(fontFamily: kArial, fontWeight: FontWeight.bold)),
        backgroundColor: NutritionPalette.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: content,
    );
  }

  Widget _buildWebHeaderContext() {
    return const Padding(
      padding: EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'VALIDACIÓN TÉCNICA',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: NutritionPalette.accent, fontFamily: kArial),
          ),
          SizedBox(height: 8),
          Text(
            'Gestión de Firmas y Consentimientos',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: NutritionPalette.textMain, fontFamily: kArial),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewCard(String title, String? url, IconData icon) {
    return Expanded(
      child: NutritionCard(
        title: title,
        padding: const EdgeInsets.all(12),
        child: Container(
          height: 140,
          width: double.infinity,
          decoration: BoxDecoration(
            color: NutritionPalette.background,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: NutritionPalette.border.withOpacity(0.5)),
          ),
          child: url == null || url.isEmpty
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(icon, color: NutritionPalette.textMuted, size: 24), const SizedBox(height: 8), const Text('Sin registro', style: TextStyle(fontSize: 11, color: NutritionPalette.textMuted))]))
              : Image.network(url, fit: BoxFit.contain),
        ),
      ),
    );
  }

  Future<void> _pickAndUpload({required bool isFirma}) async {
    final p = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (p != null) {
      final b = await p.readAsBytes();
      await _upload(b, isFirma: isFirma);
    }
  }

  Future<void> _saveDrawnSignature() async {
    if (_firmaController.isEmpty) return;
    final b = await _firmaController.toPngBytes(height: 300, width: 900);
    if (b != null) { await _upload(b, isFirma: true); _firmaController.clear(); }
  }

  Future<void> _upload(Uint8List b, {required bool isFirma}) async {
    try {
      await _service.guardarFirma(empresaId: widget.empresaId, userId: widget.userId, firmaBytes: isFirma ? b : null, selloBytes: isFirma ? null : b);
      _snack(isFirma ? 'Firma actualizada' : 'Sello actualizado');
    } catch (_) {}
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), backgroundColor: NutritionPalette.primary, behavior: SnackBarBehavior.floating));
  }
}

class _SignatureActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool primary;
  const _SignatureActionBtn({required this.label, required this.icon, required this.onTap, this.primary = false});
  @override
  Widget build(BuildContext context) {
    return primary 
      ? FilledButton.icon(onPressed: onTap, icon: Icon(icon, size: 18), label: Text(label.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)), style: FilledButton.styleFrom(backgroundColor: NutritionPalette.accent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))))
      : OutlinedButton.icon(onPressed: onTap, icon: Icon(icon, size: 18), label: Text(label.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)), style: OutlinedButton.styleFrom(foregroundColor: NutritionPalette.textMain, side: const BorderSide(color: NutritionPalette.border), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))));
  }
}
