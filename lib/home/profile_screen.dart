// lib/home/profile_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../talento_humano/hoja_de_vida_screen.dart';

const Color _profilePrimary = Color(0xFF3F6696);
const String _kFont = 'Arial';

class ProfileScreen extends StatefulWidget {
  final String userId;
  final String? empresaId;

  const ProfileScreen({super.key, required this.userId, this.empresaId});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String? _empresaId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _resolveEmpresa();
  }

  Future<void> _resolveEmpresa() async {
    final providedEmpresaId = widget.empresaId?.trim() ?? '';
    if (providedEmpresaId.isNotEmpty) {
      if (!mounted) return;
      setState(() {
        _empresaId = providedEmpresaId;
        _loading = false;
      });
      return;
    }

    // Busca el empresaId activo del usuario
    String? eid;
    try {
      final db = FirebaseFirestore.instance;
      var snap = await db.collection('TBL_USUARIOS').doc(widget.userId).get();
      if (!snap.exists) {
        final q = await db
            .collection('TBL_USUARIOS')
            .where('cedula', isEqualTo: widget.userId)
            .limit(1)
            .get();
        if (q.docs.isNotEmpty) snap = q.docs.first;
      }

      if (snap.exists) {
        final data = snap.data()!;
        eid = (data['empresaId'] as String?)?.trim();
        if (eid == null || eid.isEmpty) {
          final empresas = data['empresas'] as List<dynamic>?;
          if (empresas != null && empresas.isNotEmpty) {
            eid = empresas.first.toString();
          }
        }
      }
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _empresaId = eid ?? '';
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final isDesktop = MediaQuery.of(context).size.width >= 900;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi hoja de vida'),
        backgroundColor: _profilePrimary,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(isDesktop ? 32 : 18),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              child: Padding(
                padding: EdgeInsets.all(isDesktop ? 28 : 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            color: _profilePrimary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(
                            Icons.assignment_ind_rounded,
                            color: _profilePrimary,
                            size: 30,
                          ),
                        ),
                        const SizedBox(width: 16),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Carga o actualiza tu hoja de vida',
                                style: TextStyle(
                                  fontFamily: _kFont,
                                  fontSize: 21,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF111827),
                                ),
                              ),
                              SizedBox(height: 6),
                              Text(
                                'Desde aquí puedes completar tus datos, agregar la foto y subir los soportes en PDF. Si aún no has cargado nada, empieza con el botón de abajo.',
                                style: TextStyle(
                                  fontFamily: _kFont,
                                  color: Color(0xFF64748B),
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: const [
                        _ProfileFeatureChip(
                          icon: Icons.add_a_photo_rounded,
                          label: 'Foto / imagen de perfil',
                        ),
                        _ProfileFeatureChip(
                          icon: Icons.diversity_3_rounded,
                          label: 'Perfil demográfico',
                        ),
                        _ProfileFeatureChip(
                          icon: Icons.picture_as_pdf_rounded,
                          label: 'Soportes PDF',
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.picture_as_pdf_rounded,
                            color: _profilePrimary,
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Los documentos de soporte se cargan únicamente en formato PDF.',
                              style: TextStyle(
                                fontFamily: _kFont,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF334155),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    FilledButton.icon(
                      onPressed: _openHojaDeVidaForm,
                      icon: const Icon(Icons.edit_document),
                      label: const Text('Completar / subir hoja de vida'),
                      style: FilledButton.styleFrom(
                        backgroundColor: _profilePrimary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                        textStyle: const TextStyle(
                          fontFamily: _kFont,
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openHojaDeVidaForm() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => HojaDeVidaScreen(
          userId: widget.userId,
          empresaId: _empresaId ?? '',
          mode: HvMode.perfil,
        ),
      ),
    );
  }
}

class _ProfileFeatureChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _ProfileFeatureChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: _profilePrimary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _profilePrimary.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: _profilePrimary),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              fontFamily: _kFont,
              color: _profilePrimary,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
