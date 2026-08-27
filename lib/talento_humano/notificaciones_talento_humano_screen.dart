// lib/talento_humano/notificaciones_talento_humano_screen.dart

import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import '../widgets/internal_module_layout.dart';
import '../widgets/user_avatar.dart';

// ── Widget de imagen que carga via SDK de Firebase (evita CORS en web) ────────
class _StorageImage extends StatefulWidget {
  final String url;
  final double height;
  final double? width;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;

  const _StorageImage({
    required this.url,
    this.height = 140,
    this.width,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
  });

  @override
  State<_StorageImage> createState() => _StorageImageState();
}

class _StorageImageState extends State<_StorageImage> {
  Uint8List? _bytes;
  bool _loading = true;
  String _errorMsg = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final ref = FirebaseStorage.instance.refFromURL(widget.url);
      final downloadUrl = await ref.getDownloadURL();
      final response = await http.get(Uri.parse(downloadUrl));
      if (response.statusCode == 200) {
        if (mounted) {
          setState(() {
            _bytes = response.bodyBytes;
            _loading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _loading = false;
            _errorMsg = 'HTTP ${response.statusCode}';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _errorMsg = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return widget.placeholder ??
          Container(
            height: widget.height,
            width: widget.width ?? double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
    }
    if (_errorMsg.isNotEmpty || _bytes == null) {
      return Container(
        width: widget.width ?? double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7ED),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFFED7AA)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.broken_image_outlined,
                  color: Color(0xFFC28942),
                  size: 16,
                ),
                SizedBox(width: 6),
                Text(
                  'Error al cargar imagen:',
                  style: TextStyle(
                    fontFamily: 'Arial',
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFC28942),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // Muestra el error real para poder diagnosticarlo
            SelectableText(
              _errorMsg.isEmpty ? 'bytes nulos sin excepción' : _errorMsg,
              style: const TextStyle(
                fontFamily: 'Arial',
                fontSize: 10,
                color: Color(0xFF92400E),
              ),
            ),
          ],
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.memory(
        _bytes!,
        width: widget.width ?? double.infinity,
        // Sin height fijo: la imagen respeta su proporción real
        fit: BoxFit.fitWidth,
      ),
    );
  }
}

// ── Constantes ────────────────────────────────────────────────────────────────

const Color _khPrimary = Color(0xFFC28942);
const String _kFont = 'Arial';
const String _notifsRoot = 'TBL_NOTIFICACIONES';
const String _bannersRoot = 'TBL_BANNERS_TH';
const String _usuariosCol = 'TBL_USUARIOS';

// ── Modelo de tipo de celebración ─────────────────────────────────────────────

class _TipoOpcion {
  final String key;
  final String label;
  final IconData icon;
  final Color color;
  final String defaultTitle;

  const _TipoOpcion({
    required this.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.defaultTitle,
  });
}

const _tipos = [
  _TipoOpcion(
    key: 'cumpleanos',
    label: 'Cumpleaños',
    icon: Icons.cake_outlined,
    color: Color(0xFFF59E0B),
    defaultTitle: '¡Feliz Cumpleaños!',
  ),
  _TipoOpcion(
    key: 'celebracion',
    label: 'Felicitación',
    icon: Icons.celebration_outlined,
    color: Color(0xFF7C3AED),
    defaultTitle: '¡Felicitaciones!',
  ),
  _TipoOpcion(
    key: 'general_th',
    label: 'General',
    icon: Icons.campaign_outlined,
    color: Color(0xFFC28942),
    defaultTitle: 'Comunicado',
  ),
  _TipoOpcion(
    key: 'motivacion',
    label: 'Motivación',
    icon: Icons.fitness_center_outlined,
    color: Color(0xFF059669),
    defaultTitle: '¡Ánimo al equipo!',
  ),
  _TipoOpcion(
    key: 'beneficios',
    label: 'Beneficios/Caja',
    icon: Icons.card_giftcard_outlined,
    color: Color(0xFF0284C7),
    defaultTitle: 'Oferta / Beneficio',
  ),
];

// ── Screen principal ──────────────────────────────────────────────────────────

class NotificacionesTalentoHumanoScreen extends StatefulWidget {
  final String userId;
  final String empresaId;

  const NotificacionesTalentoHumanoScreen({
    super.key,
    required this.userId,
    required this.empresaId,
  });

  @override
  State<NotificacionesTalentoHumanoScreen> createState() =>
      _NotificacionesTalentoHumanoScreenState();
}

class _NotificacionesTalentoHumanoScreenState
    extends State<NotificacionesTalentoHumanoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _tituloCtrl = TextEditingController();
  final _mensajeCtrl = TextEditingController();
  final _empleadoCtrl = TextEditingController();

  _TipoOpcion _tipoSeleccionado = _tipos[0];
  bool _paraTodos = true;
  String? _empleadoCedula;
  String? _empleadoNombre;

  Uint8List? _imageBytes;
  String _imageExtension = 'jpg';
  bool _enviando = false;
  String? _senderName;

  @override
  void initState() {
    super.initState();
    _tituloCtrl.text = _tipoSeleccionado.defaultTitle;
    _loadSenderName();
  }

  @override
  void dispose() {
    _tituloCtrl.dispose();
    _mensajeCtrl.dispose();
    _empleadoCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSenderName() async {
    final snap = await FirebaseFirestore.instance
        .collection(_usuariosCol)
        .doc(widget.userId)
        .get();
    if (!snap.exists) return;
    final d = snap.data()!;
    final nombre = [
      d['primerNombre'],
      d['primerApellido'],
    ].whereType<String>().where((s) => s.isNotEmpty).join(' ');
    if (mounted) {
      setState(() => _senderName = nombre.isNotEmpty ? nombre : null);
    }
  }

  // ── Búsqueda de empleados ──────────────────────────────────────────────────

  Future<List<Map<String, String>>> _fetchEmpleados(String pattern) async {
    final fs = FirebaseFirestore.instance;
    // Consultar las dos variantes de campo de empresa
    final r1 = await fs
        .collection(_usuariosCol)
        .where('empresas', arrayContains: widget.empresaId)
        .get();
    final r2 = await fs
        .collection(_usuariosCol)
        .where('empresaId', isEqualTo: widget.empresaId)
        .get();

    // Deduplicar por doc.id
    final seen = <String>{};
    final all = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final d in [...r1.docs, ...r2.docs]) {
      if (seen.add(d.id)) all.add(d);
    }

    final term = pattern.toLowerCase();
    return all
        .where((d) {
          final data = d.data();
          final nombre = _buildNombre(data).toLowerCase();
          final cedula = (data['cedula'] as String? ?? d.id).toLowerCase();
          return term.isEmpty || nombre.contains(term) || cedula.contains(term);
        })
        .map((d) {
          final data = d.data();
          final cedula = ((data['cedula'] as String?)?.trim() ?? '').isNotEmpty
              ? (data['cedula'] as String).trim()
              : d.id;
          final nombre = _buildNombre(data);
          // Si no hay nombre, mostrar la cédula para que no quede en blanco
          return {
            'cedula': cedula,
            'nombre': nombre.isNotEmpty ? nombre : cedula,
          };
        })
        .toList();
  }

  String _buildNombre(Map<String, dynamic> data) {
    // Intentar por partes del nombre
    final parts = [
      data['primerNombre'],
      data['segundoNombre'],
      data['primerApellido'],
      data['segundoApellido'],
    ].whereType<String>().where((s) => s.trim().isNotEmpty).toList();
    if (parts.isNotEmpty) return parts.join(' ');
    // nombreCompleto
    final completo = (data['nombreCompleto'] as String?)?.trim() ?? '';
    if (completo.isNotEmpty) return completo;
    // nombres + apellidos
    final n = (data['nombres'] as String?)?.trim() ?? '';
    final a = (data['apellidos'] as String?)?.trim() ?? '';
    if (n.isNotEmpty || a.isNotEmpty) return '$n $a'.trim();
    // nombre simple
    return (data['nombre'] as String?)?.trim() ?? '';
  }

  // ── Imagen ─────────────────────────────────────────────────────────────────

  Future<void> _pickImage() async {
    if (kIsWeb) {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      if (file.bytes == null) return;
      final ext = (file.extension ?? 'jpg').toLowerCase();
      setState(() {
        _imageBytes = file.bytes;
        _imageExtension = ext;
      });
    } else {
      final source = await _showImageSourceSheet();
      if (source == null) return;
      final picked = await ImagePicker().pickImage(
        source: source,
        imageQuality: 85,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      final ext = picked.path.split('.').last.toLowerCase();
      setState(() {
        _imageBytes = bytes;
        _imageExtension = ext;
      });
    }
  }

  Future<ImageSource?> _showImageSourceSheet() async {
    return showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Cámara'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Galería'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _uploadImage() async {
    if (_imageBytes == null) return null;
    final ts = DateTime.now().millisecondsSinceEpoch;
    final ext = _imageExtension.toLowerCase();
    final mime = ext == 'png'
        ? 'image/png'
        : ext == 'gif'
        ? 'image/gif'
        : ext == 'webp'
        ? 'image/webp'
        : 'image/jpeg';
    final ref = FirebaseStorage.instance.ref(
      'banners_th/${widget.empresaId}/$ts.$ext',
    );
    await ref.putData(_imageBytes!, SettableMetadata(contentType: mime));
    return ref.getDownloadURL();
  }

  // ── Envío ──────────────────────────────────────────────────────────────────

  Future<void> _enviar() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_paraTodos && (_empleadoCedula == null || _empleadoCedula!.isEmpty)) {
      _snack('Selecciona un empleado o elige "Todos".');
      return;
    }

    setState(() => _enviando = true);
    try {
      // 1. Subir imagen si hay
      final imageUrl = await _uploadImage();

      // 2. Obtener destinatarios
      List<String> cedulas;
      if (_paraTodos) {
        final snap = await FirebaseFirestore.instance
            .collection(_usuariosCol)
            .where('empresas', arrayContains: widget.empresaId)
            .get();
        cedulas = snap.docs.map((d) {
          final data = d.data();
          final ced = (data['cedula'] as String?)?.trim();
          return (ced?.isNotEmpty == true) ? ced! : d.id;
        }).toList();
      } else {
        cedulas = [_empleadoCedula!];
      }

      // 3. Pre-generar referencia del banner para obtener su ID antes de crear notificaciones
      final db = FirebaseFirestore.instance;
      final bannerRef = db
          .collection(_bannersRoot)
          .doc(widget.empresaId)
          .collection('enviados')
          .doc();
      final bannerId = bannerRef.id;

      // 4. Crear notificaciones en batch (máx 500 por batch de Firestore)
      var batch = db.batch();
      int count = 0;
      final List<String> filteredCedulas = [];

      for (final cedula in cedulas) {
        if (cedula.isEmpty) continue;
        filteredCedulas.add(cedula);
        final ref = db
            .collection(_notifsRoot)
            .doc(cedula)
            .collection('notifications')
            .doc();
        final notifPayload = <String, dynamic>{
          'id': ref.id,
          'title': _tituloCtrl.text.trim(),
          'description': _mensajeCtrl.text.trim(),
          'type': _tipoSeleccionado.key,
          'fromId': widget.userId,
          'fromName': _senderName ?? 'Talento Humano',
          'createdAt': Timestamp.now(),
          'read': false,
          'empresaId': widget.empresaId,
          'bannerId': bannerId,
        };
        if (imageUrl != null) notifPayload['imageUrl'] = imageUrl;
        batch.set(ref, notifPayload);
        count++;
        if (count % 490 == 0) {
          await batch.commit();
          batch = db.batch();
        }
      }
      if (count % 490 != 0 || count == 0) await batch.commit();

      // 5. Guardar en historial TH con su ID pre-generado y lista de cédulas
      await bannerRef.set({
        'tipo': _tipoSeleccionado.key,
        'tipoLabel': _tipoSeleccionado.label,
        'titulo': _tituloCtrl.text.trim(),
        'mensaje': _mensajeCtrl.text.trim(),
        'imageUrl': imageUrl ?? '',
        'paraTodos': _paraTodos,
        'destinatarioCedula': _paraTodos ? '' : _empleadoCedula,
        'destinatarioNombre': _paraTodos ? 'Todos' : _empleadoNombre,
        'enviadoPor': widget.userId,
        'enviadoPorNombre': _senderName ?? 'Talento Humano',
        'totalDestinatarios': filteredCedulas.length,
        'cedulas': filteredCedulas,
        'enviadoAt': FieldValue.serverTimestamp(),
      });

      // 5. Reset formulario
      _tituloCtrl.text = _tipoSeleccionado.defaultTitle;
      _mensajeCtrl.clear();
      _empleadoCtrl.clear();
      setState(() {
        _imageBytes = null;
        _empleadoCedula = null;
        _empleadoNombre = null;
        _paraTodos = true;
      });
      _snack(
        '✅ Enviado a ${filteredCedulas.length} empleado${filteredCedulas.length != 1 ? "s" : ""}.',
      );
    } catch (e) {
      _snack('Error al enviar: $e');
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.of(context).size.width < 520;
    return InternalModuleLayout(
      userId: widget.userId,
      empresaId: widget.empresaId,
      title: 'Notificaciones TH',
      subtitle: 'Envía banners de celebración y comunicados al equipo',
      accentColor: _khPrimary,
      child: SingleChildScrollView(
        padding: EdgeInsets.all(isCompact ? 16 : 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildComposeCard(),
                const SizedBox(height: 32),
                _buildHistorialSection(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Card de composición ────────────────────────────────────────────────────

  Widget _buildComposeCard() {
    final isCompact = MediaQuery.of(context).size.width < 520;
    return ModuleCard(
      padding: EdgeInsets.all(isCompact ? 16 : 24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionLabel('TIPO DE MENSAJE'),
            const SizedBox(height: 12),
            _buildTipoChips(),
            const SizedBox(height: 20),
            _sectionLabel('DESTINATARIOS'),
            const SizedBox(height: 12),
            _buildDestinatarioToggle(),
            if (!_paraTodos) ...[
              const SizedBox(height: 12),
              _buildEmpleadoSearch(),
            ],
            const SizedBox(height: 20),
            _sectionLabel('MENSAJE'),
            const SizedBox(height: 12),
            TextFormField(
              controller: _tituloCtrl,
              decoration: const InputDecoration(
                labelText: 'Título',
                border: OutlineInputBorder(),
              ),
              style: const TextStyle(
                fontFamily: _kFont,
                fontWeight: FontWeight.bold,
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'El título es obligatorio'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _mensajeCtrl,
              decoration: const InputDecoration(
                labelText: 'Mensaje',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              style: const TextStyle(fontFamily: _kFont),
              maxLines: 4,
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'El mensaje es obligatorio'
                  : null,
            ),
            const SizedBox(height: 20),
            _sectionLabel('IMAGEN BANNER (opcional)'),
            const SizedBox(height: 12),
            _buildImagePicker(),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _khPrimary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _enviando ? null : _enviar,
                icon: _enviando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(
                        _paraTodos
                            ? Icons.send_rounded
                            : Icons.person_search_rounded,
                      ),
                label: Text(
                  _enviando
                      ? 'Enviando…'
                      : _paraTodos
                      ? 'Enviar a todos los empleados'
                      : 'Enviar a empleado seleccionado',
                  style: const TextStyle(
                    fontFamily: _kFont,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTipoChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _tipos.map((tipo) {
        final selected = _tipoSeleccionado.key == tipo.key;
        return FilterChip(
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                tipo.icon,
                size: 16,
                color: selected ? Colors.white : tipo.color,
              ),
              const SizedBox(width: 6),
              Text(
                tipo.label,
                style: TextStyle(
                  fontFamily: _kFont,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : const Color(0xFF1E293B),
                ),
              ),
            ],
          ),
          selected: selected,
          onSelected: (_) {
            setState(() {
              _tipoSeleccionado = tipo;
              _tituloCtrl.text = tipo.defaultTitle;
            });
          },
          selectedColor: tipo.color,
          backgroundColor: tipo.color.withValues(alpha: 0.08),
          checkmarkColor: Colors.white,
          showCheckmark: false,
          side: BorderSide(
            color: selected ? tipo.color : tipo.color.withValues(alpha: 0.3),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDestinatarioToggle() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 380;
        final allButton = _ToggleButton(
          label: 'Todos los empleados',
          icon: Icons.groups_rounded,
          selected: _paraTodos,
          color: _khPrimary,
          onTap: () => setState(() {
            _paraTodos = true;
            _empleadoCedula = null;
            _empleadoNombre = null;
            _empleadoCtrl.clear();
          }),
        );
        final singleButton = _ToggleButton(
          label: 'Empleado específico',
          icon: Icons.person_rounded,
          selected: !_paraTodos,
          color: _khPrimary,
          onTap: () => setState(() => _paraTodos = false),
        );

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [allButton, const SizedBox(height: 10), singleButton],
          );
        }

        return Row(
          children: [
            Expanded(child: allButton),
            const SizedBox(width: 12),
            Expanded(child: singleButton),
          ],
        );
      },
    );
  }

  Widget _buildEmpleadoSearch() {
    return TypeAheadField<Map<String, String>>(
      textFieldConfiguration: TextFieldConfiguration(
        controller: _empleadoCtrl,
        decoration: InputDecoration(
          labelText: 'Buscar empleado',
          hintText: 'Nombre o cédula…',
          border: const OutlineInputBorder(),
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _empleadoCedula != null
              ? const Icon(Icons.check_circle, color: Color(0xFF059669))
              : null,
        ),
      ),
      suggestionsCallback: _fetchEmpleados,
      itemBuilder: (_, m) => ListTile(
        leading: UserAvatar(
          userId: m['cedula'],
          nameHint: m['nombre'],
          radius: 18,
          foregroundColor: _khPrimary,
        ),
        title: UserNameText(
          m['cedula'] ?? '',
          fallbackName: m['nombre'],
          style: const TextStyle(fontFamily: _kFont),
        ),
        subtitle: Text(
          'CC: ${m['cedula']}',
          style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
        ),
      ),
      onSuggestionSelected: (m) {
        setState(() {
          _empleadoCedula = m['cedula'];
          _empleadoNombre = m['nombre'];
          _empleadoCtrl.text = m['nombre']!;
        });
      },
      minCharsForSuggestions: 0,
      noItemsFoundBuilder: (_) => const ListTile(title: Text('Sin resultados')),
    );
  }

  Widget _buildImagePicker() {
    if (_imageBytes != null) {
      return Column(
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(
                  _imageBytes!,
                  width: double.infinity,
                  height: 180,
                  fit: BoxFit.cover,
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: GestureDetector(
                  onTap: () => setState(() => _imageBytes = null),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _pickImage,
            icon: const Icon(Icons.swap_horiz_rounded, size: 18),
            label: const Text(
              'Cambiar imagen',
              style: TextStyle(fontFamily: _kFont),
            ),
          ),
        ],
      );
    }

    return GestureDetector(
      onTap: _pickImage,
      child: Container(
        width: double.infinity,
        height: 120,
        decoration: BoxDecoration(
          border: Border.all(
            color: const Color(0xFFCBD5E1),
            style: BorderStyle.solid,
          ),
          borderRadius: BorderRadius.circular(12),
          color: const Color(0xFFF8FAFC),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.add_photo_alternate_outlined,
              size: 36,
              color: _khPrimary.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 8),
            const Text(
              'Toca para agregar una imagen banner',
              style: TextStyle(
                fontFamily: _kFont,
                fontSize: 13,
                color: Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Historial ──────────────────────────────────────────────────────────────

  Widget _buildHistorialSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('HISTORIAL DE ENVÍOS'),
        const SizedBox(height: 16),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection(_bannersRoot)
              .doc(widget.empresaId)
              .collection('enviados')
              .orderBy('enviadoAt', descending: true)
              .limit(20)
              .snapshots(),
          builder: (ctx, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final docs = snap.data?.docs ?? [];
            if (docs.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    'Aún no se han enviado banners.',
                    style: TextStyle(
                      fontFamily: _kFont,
                      color: Color(0xFF94A3B8),
                      fontSize: 14,
                    ),
                  ),
                ),
              );
            }
            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: docs.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (_, i) =>
                  _HistorialTile(doc: docs[i], empresaId: widget.empresaId),
            );
          },
        ),
      ],
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontFamily: _kFont,
        fontWeight: FontWeight.w900,
        fontSize: 11,
        color: Color(0xFF64748B),
        letterSpacing: 1.5,
      ),
    );
  }
}

// ── Toggle Button ─────────────────────────────────────────────────────────────

class _ToggleButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _ToggleButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? color : Colors.transparent,
          border: Border.all(
            color: selected ? color : const Color(0xFFCBD5E1),
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? Colors.white : const Color(0xFF64748B),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: _kFont,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : const Color(0xFF1E293B),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Tile de historial ─────────────────────────────────────────────────────────

class _HistorialTile extends StatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final String empresaId;
  const _HistorialTile({required this.doc, required this.empresaId});

  @override
  State<_HistorialTile> createState() => _HistorialTileState();
}

class _HistorialTileState extends State<_HistorialTile> {
  bool _deleting = false;

  _TipoOpcion _tipoFor(String key) =>
      _tipos.firstWhere((t) => t.key == key, orElse: () => _tipos[2]);

  String _formatTs(dynamic ts) {
    if (ts == null) return '—';
    final dt = ts is Timestamp ? ts.toDate() : DateTime.now();
    return DateFormat('dd MMM yyyy · hh:mm a', 'es').format(dt);
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Eliminar notificación',
          style: TextStyle(fontFamily: _kFont, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Se eliminará del historial y de las bandejas de todos los destinatarios. Esta acción no se puede deshacer.',
          style: TextStyle(fontFamily: _kFont, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar', style: TextStyle(fontFamily: _kFont)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar', style: TextStyle(fontFamily: _kFont)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _deleting = true);
    try {
      final db = FirebaseFirestore.instance;
      final bannerId = widget.doc.id;
      final data = widget.doc.data();
      final titulo = (data['titulo'] as String?) ?? '';
      final tipo = (data['tipo'] as String?) ?? '';

      // Obtener lista de cédulas. Si el banner es antiguo (sin 'cedulas'),
      // obtenemos todos los usuarios de la empresa como fallback.
      List<String> cedulas = List<String>.from(
        (data['cedulas'] as List<dynamic>?) ?? [],
      );
      if (cedulas.isEmpty) {
        try {
          final snap = await db
              .collection(_usuariosCol)
              .where('empresas', arrayContains: widget.empresaId)
              .get();
          cedulas = snap.docs.map((d) {
            final ced = (d.data()['cedula'] as String?)?.trim();
            return (ced?.isNotEmpty == true) ? ced! : d.id;
          }).toList();
        } catch (_) {}
      }

      // Eliminar notificaciones individuales de cada destinatario.
      // Primero intenta por bannerId (formato nuevo); si no encuentra,
      // hace fallback por title+type (formato antiguo sin bannerId).
      for (final cedula in cedulas) {
        if (cedula.isEmpty) continue;
        var q = await db
            .collection(_notifsRoot)
            .doc(cedula)
            .collection('notifications')
            .where('bannerId', isEqualTo: bannerId)
            .get();
        if (q.docs.isEmpty && titulo.isNotEmpty) {
          q = await db
              .collection(_notifsRoot)
              .doc(cedula)
              .collection('notifications')
              .where('title', isEqualTo: titulo)
              .where('type', isEqualTo: tipo)
              .get();
        }
        if (q.docs.isEmpty) continue;
        final b = db.batch();
        for (final d in q.docs) {
          b.delete(d.reference);
        }
        await b.commit();
      }

      // Eliminar el banner del historial
      await widget.doc.reference.delete();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al eliminar: $e')));
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.doc.data();
    final tipo = _tipoFor(data['tipo'] as String? ?? '');
    final imageUrl = (data['imageUrl'] as String?) ?? '';
    final titulo = data['titulo'] as String? ?? '';
    final mensaje = data['mensaje'] as String? ?? '';
    final dest = data['destinatarioNombre'] as String? ?? 'Todos';
    final total = data['totalDestinatarios'] as int? ?? 0;
    final sender = data['enviadoPorNombre'] as String? ?? '';
    final ts = _formatTs(data['enviadoAt']);

    return ModuleCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: tipo.color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(tipo.icon, color: tipo.color, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: _kFont,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    Text(
                      ts,
                      style: const TextStyle(
                        fontFamily: _kFont,
                        fontSize: 11,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                constraints: const BoxConstraints(maxWidth: 120),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: tipo.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  tipo.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: _kFont,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: tipo.color,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _deleting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.red,
                      ),
                    )
                  : IconButton(
                      icon: const Icon(
                        Icons.delete_outline,
                        color: Colors.redAccent,
                        size: 20,
                      ),
                      tooltip: 'Eliminar notificación',
                      onPressed: _delete,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                    ),
            ],
          ),
          if (mensaje.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              mensaje,
              style: const TextStyle(
                fontFamily: _kFont,
                fontSize: 13,
                color: Color(0xFF475569),
                height: 1.4,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (imageUrl.isNotEmpty) ...[
            const SizedBox(height: 10),
            _StorageImage(url: imageUrl),
          ],
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              _MetaLine(
                icon: Icons.people_outline_rounded,
                text: dest == 'Todos' ? 'Todos ($total)' : dest,
              ),
              if (sender.isNotEmpty)
                _MetaLine(icon: Icons.person_outline_rounded, text: sender),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  final IconData icon;
  final String text;

  const _MetaLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF94A3B8)),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: _kFont,
                fontSize: 12,
                color: Color(0xFF64748B),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
