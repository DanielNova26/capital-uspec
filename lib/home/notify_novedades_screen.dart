// lib/home/notify_novedades_screen.dart

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:mime/mime.dart';

const Color kMarronOscuro = Color(0xffc28942);
const String kArial = 'Arial';

class NotifyNovedadesScreen extends StatefulWidget {
  final String taskId;
  final String currentUserId;

  const NotifyNovedadesScreen({
    Key? key,
    required this.taskId,
    required this.currentUserId,
  }) : super(key: key);

  @override
  State<NotifyNovedadesScreen> createState() => _NotifyNovedadesScreenState();
}

class _NotifyNovedadesScreenState extends State<NotifyNovedadesScreen> {
  // --- UI ---
  final _descCtrl = TextEditingController();
  bool _busy = false;
  String? _error;
  bool _takingPhoto = false;

  // --- Task data ---
  Map<String, dynamic>? _task;
  String? _taskTitle;
  String? _creatorId;
  String? _bossId;

  // --- Files / evidence ---
  final _picker = ImagePicker();
  final List<PlatformFile> _picked = [];

  // --- Geo ---
  Position? _pos;
  String? _coordsStr; // "lat, lng"

  // Config de carga
  static const int _maxFileBytes = 25 * 1024 * 1024; // 25MB por archivo
  static const int _maxDescLen = 3000;

  @override
  void initState() {
    super.initState();
    _loadTask();
    _ensureLocation();
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
  }

  // =========================================================
  // DATA
  // =========================================================

  Future<void> _loadTask() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('TBL_TAREAS')
          .doc(widget.taskId)
          .get();

      final m = snap.data() ?? {};
      setState(() {
        _task = m;
        _taskTitle = (m['titulo'] ?? m['title'] ?? 'Tarea').toString();
        _creatorId = (m['creador_id'] ?? m['creatorId'] ?? '').toString().trim();
        _bossId = (m['jefe_uid'] ?? m['jefeId'] ?? m['delegatedTo'] ?? '').toString().trim();
      });
    } catch (_) {
      // sin romper UI
    }
  }

  Future<void> _ensureLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        await Geolocator.openLocationSettings();
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ubicación deshabilitada. Se enviará sin geolocalización.'),
            ),
          );
        }
        return;
      }
      _pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      _coordsStr = '${_pos!.latitude.toStringAsFixed(5)}, ${_pos!.longitude.toStringAsFixed(5)}';
      if (mounted) setState(() {});
    } catch (_) {
      // seguimos sin coords
    }
  }

  String _fmtDueDate(dynamic ts) {
    if (ts is Timestamp) {
      return DateFormat('dd/MM/yyyy HH:mm').format(ts.toDate());
    }
    return '—';
  }

  // =========================================================
  // UTILS
  // =========================================================

  String _safeName(String name) {
    final base = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return base.isEmpty ? 'archivo' : base;
  }

  // =========================================================
  // PICKERS
  // =========================================================

  Future<void> _pickFiles() async {
    final res = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.custom,
      allowedExtensions: const [
        'pdf','doc','docx','xls','xlsx','ppt','pptx','zip','jpg','jpeg','png',
      ],
    );
    if (res != null && res.files.isNotEmpty) {
      final tooBig = <String>[];
      final accepted = <PlatformFile>[];
      final existing = _picked.map((e) => e.name).toSet();

      for (final f in res.files) {
        if (existing.contains(f.name)) continue; // evita duplicados por nombre
        final size = f.size;
        if (size > _maxFileBytes) {
          tooBig.add('${f.name} (${(size / 1024 / 1024).toStringAsFixed(1)} MB)');
          continue;
        }
        accepted.add(f);
      }
      setState(() => _picked.addAll(accepted));
      if (tooBig.isNotEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Se omitieron por tamaño: ${tooBig.join(', ')}')),
        );
      }
    }
  }

  Future<void> _takePhoto() async {
    if (_takingPhoto) return;
    setState(() => _takingPhoto = true);
    try {
      final x = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 88,
      );
      if (x == null) return;

      final raw = await File(x.path).readAsBytes();
      final img = await _decodeUiImage(raw);

      final wm = await _buildWatermarkedBytes(
        base: img,
        logoAsset: 'assets/logo.png',
        header: 'Novedad',
        title: _taskTitle ?? 'Tarea',
        who: (_task?['asignado_nombre'] ?? '—').toString(),
        coords: _coordsStr,
        deadline: _task?['fecha_limite'],
      );
      if (wm == null) return;

      final name = 'nvd_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File('${Directory.systemTemp.path}/$name')..writeAsBytesSync(wm);
      setState(() {
        _picked.add(PlatformFile(
          name: name,
          path: file.path,
          size: file.lengthSync(),
          bytes: wm,
        ));
      });
    } finally {
      if (mounted) setState(() => _takingPhoto = false);
    }
  }

  Future<ui.Image> _decodeUiImage(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  /// Crea overlay inferior con datos + (opcional) mapa estático.
  Future<Uint8List?> _buildWatermarkedBytes({
    required ui.Image base,
    required String logoAsset,
    required String header, // “Novedad”
    required String title, // Tarea
    required String who, // Asignado
    String? coords,
    dynamic deadline, // Timestamp?
  }) async {
    // Logo
    ui.Image? logo;
    try {
      final lb = await rootBundle.load(logoAsset);
      final lc = await ui.instantiateImageCodec(lb.buffer.asUint8List());
      logo = (await lc.getNextFrame()).image;
    } catch (_) {}

    // Mapa estático (si quieres usar Static Maps, pon una API KEY)
    ui.Image? staticMap;
    try {
      if (coords != null && coords.contains(',')) {
        const mapsKey = ''; // <- agrega tu key si quieres mostrar mapa
        if (mapsKey.isNotEmpty) {
          final parts = coords.split(',');
          final lat = parts[0].trim(), lng = parts[1].trim();
          final url = Uri.parse(
            'https://maps.googleapis.com/maps/api/staticmap'
                '?center=$lat,$lng&zoom=16&size=320x200&scale=2&maptype=roadmap'
                '&markers=color:red|$lat,$lng&key=$mapsKey',
          );
          final r = await http.get(url).timeout(const Duration(seconds: 7));
          if (r.statusCode == 200) {
            final c = await ui.instantiateImageCodec(r.bodyBytes);
            staticMap = (await c.getNextFrame()).image;
          }
        }
      }
    } catch (_) {}

    final rec = ui.PictureRecorder();
    final c = Canvas(rec, Rect.fromLTWH(0, 0, base.width.toDouble(), base.height.toDouble()));

    // Base
    c.drawImage(
      base,
      Offset.zero,
      Paint()..filterQuality = ui.FilterQuality.medium,
    );

    // Overlay
    final overlayH = (base.height * 0.24).clamp(150.0, 300.0);
    final overlay = Rect.fromLTWH(0, base.height - overlayH, base.width.toDouble(), overlayH);
    c.drawRect(overlay, Paint()..color = const Color(0xCC000000));

    const pad = 16.0;
    final col1W = base.width * 0.18;
    final col2W = base.width * 0.52;
    final col3W = base.width * 0.30;

    final rLogo = Rect.fromLTWH(
      overlay.left + pad,
      overlay.top + pad,
      col1W - pad * 2,
      overlay.height - pad * 2,
    );
    final rText = Rect.fromLTWH(
      overlay.left + col1W,
      overlay.top + pad,
      col2W - pad * 2,
      overlay.height - pad * 2,
    );
    final rMap = Rect.fromLTWH(
      overlay.left + col1W + col2W,
      overlay.top + pad,
      col3W - pad * 2,
      overlay.height - pad * 2,
    );

    // Logo
    if (logo != null && rLogo.width > 0) {
      final s = math.min(rLogo.width / logo.width, rLogo.height / logo.height);
      final w = logo.width * s, h = logo.height * s;
      final dst = Rect.fromLTWH(
        rLogo.left + (rLogo.width - w) / 2,
        rLogo.top + (rLogo.height - h) / 2,
        w,
        h,
      );
      c.drawImageRect(
        logo,
        Rect.fromLTWH(0, 0, logo.width.toDouble(), logo.height.toDouble()),
        dst,
        Paint()..colorFilter = const ui.ColorFilter.mode(Colors.white, ui.BlendMode.modulate),
      );
    }

    // Texto
    final lines = <String>[
      '$header • ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}',
      'Tarea: $title',
      'Reporta: $who',
      if (deadline is Timestamp)
        'Límite: ${DateFormat('dd/MM/yyyy HH:mm').format(deadline.toDate())}',
      if (coords != null) 'Ubicación: $coords',
    ];
    final pb = ui.ParagraphBuilder(ui.ParagraphStyle(maxLines: 8, ellipsis: '…'))
      ..pushStyle(ui.TextStyle(color: Colors.white.withOpacity(0.96), fontSize: 24));
    pb.addText(lines.join('\n'));
    final p = pb.build()..layout(ui.ParagraphConstraints(width: rText.width));
    c.drawParagraph(p, Offset(rText.left, rText.top));

    // Mapa
    if (staticMap != null && rMap.width > 0) {
      final rr = RRect.fromRectAndRadius(rMap, const Radius.circular(12));
      final path = Path()..addRRect(rr);
      c.save();
      c.clipPath(path);
      c.drawImageRect(
        staticMap,
        Rect.fromLTWH(0, 0, staticMap.width.toDouble(), staticMap.height.toDouble()),
        rMap,
        Paint()..filterQuality = ui.FilterQuality.high,
      );
      c.restore();
      c.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = Colors.white.withOpacity(0.9),
      );
    }

    final picture = rec.endRecording();
    final out = await picture.toImage(base.width, base.height);
    final png = await out.toByteData(format: ui.ImageByteFormat.png);
    return png?.buffer.asUint8List();
  }

  // =========================================================
  // SUBMIT
  // =========================================================

  bool get _canSend {
    final txt = _descCtrl.text.trim();
    return txt.isNotEmpty && txt.length <= _maxDescLen;
  }

  Future<void> _submit() async {
    if (!_canSend) {
      setState(() => _error = _descCtrl.text.trim().isEmpty
          ? 'Describe la novedad'
          : 'La descripción supera el límite de ${_maxDescLen} caracteres');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      // 1) Subir adjuntos
      final now = DateTime.now();
      final y = DateFormat('yyyy').format(now);
      final m = DateFormat('MM').format(now);
      final d = DateFormat('dd').format(now);

      final List<Map<String, dynamic>> adjuntos = [];
      for (final f in _picked) {
        final name = _safeName(f.name);
        final bytes = f.bytes ?? (f.path != null ? await File(f.path!).readAsBytes() : null);
        if (bytes == null) continue;

        if (bytes.length > _maxFileBytes) {
          // extra guard por si llega por path (no filtrado en _pickFiles)
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Se omitió por tamaño: $name')),
            );
          }
          continue;
        }

        final mime = lookupMimeType(name) ?? 'application/octet-stream';
        final path = 'tareas/$y/$m/$d/nvd_${DateTime.now().millisecondsSinceEpoch}_$name';

        final ref = FirebaseStorage.instance.ref(path);
        await ref.putData(bytes, SettableMetadata(contentType: mime));
        final url = await ref.getDownloadURL();

        // 👇 Nada de serverTimestamp dentro de arrays
        adjuntos.add({
          'name': name,
          'path': path,
          'url': url,
          'mime': mime,
          'size': bytes.length,
          'uploadedAt': Timestamp.now(),
        });
      }

      // 2) Guardar subdoc en /novedades
      final col = FirebaseFirestore.instance
          .collection('TBL_TAREAS')
          .doc(widget.taskId)
          .collection('novedades');
      final doc = col.doc();

      // Carga task si no estaba lista (red lenta)
      if (_taskTitle == null) {
        await _loadTask();
      }

      await doc.set({
        'id': doc.id,
        'by': widget.currentUserId,
        'message': _descCtrl.text.trim(),
        'attachments': adjuntos, // array limpio
        'createdAt': FieldValue.serverTimestamp(), // top-level OK
        if (_pos != null) 'geoloc': {'lat': _pos!.latitude, 'lng': _pos!.longitude},
      });

      // 3) Marcar actualización en la tarea (espejo de campos)
      await FirebaseFirestore.instance
          .collection('TBL_TAREAS')
          .doc(widget.taskId)
          .update({
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizada_en': FieldValue.serverTimestamp(),
      });

      // 4) Notificar (callable → guarda campana + push) sin romper UX si falla
      try {
        final fn = FirebaseFunctions.instance.httpsCallable('notifyTaskNews');
        await fn.call(<String, dynamic>{
          'taskId': widget.taskId,
          'creatorId': _creatorId ?? '',
          'bossId': _bossId ?? '',
          'title': 'Novedad en tarea',
          'body': _descCtrl.text.trim(),
        });
      } catch (e) {
        debugPrint('[notifyTaskNews] fallo opcional: $e');
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Novedad enviada')),
      );
      _descCtrl.clear();
      setState(() => _picked.clear());
    } catch (e) {
      setState(() => _error = 'Error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // =========================================================
  // BUILD
  // =========================================================

  @override
  Widget build(BuildContext context) {
    final estado = (_task?['estado'] ?? '').toString();
    final due = _task?['fecha_limite'];

    return Scaffold(
      backgroundColor: const Color(0xFFF7FBF7),
      appBar: AppBar(
        backgroundColor: kMarronOscuro,
        title: const Text('Notificar novedades', style: TextStyle(fontFamily: kArial)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Header tarjeta
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4)),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      const Icon(Icons.report_problem_outlined, size: 28, color: Colors.black87),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _taskTitle ?? 'Tarea',
                              style: const TextStyle(
                                fontFamily: kArial,
                                fontWeight: FontWeight.w700,
                                fontSize: 18,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                Chip(
                                  label: Text(
                                    estado.isEmpty ? 'pendiente' : estado,
                                    style: const TextStyle(color: Colors.white, fontFamily: kArial),
                                  ),
                                  backgroundColor: estado == 'completada'
                                      ? Colors.green.shade600
                                      : estado == 'pendiente'
                                      ? Colors.orange.shade700
                                      : Colors.blueGrey.shade700,
                                ),
                                Chip(
                                  label: Text(
                                    'Vence: ${_fmtDueDate(due)}',
                                    style: const TextStyle(color: Colors.white, fontFamily: kArial),
                                  ),
                                  backgroundColor: Colors.blue.shade600,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Descripción
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: TextField(
                controller: _descCtrl,
                minLines: 3,
                maxLines: 6,
                maxLength: _maxDescLen,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  labelText: 'Descripción de la novedad',
                  hintText: '¿Qué ocurrió?',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),

            // Acciones
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.attach_file,
                      label: 'Adjuntar\narchivos',
                      onTap: _busy ? null : _pickFiles,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ActionButton(
                      icon: _takingPhoto ? Icons.hourglass_top : Icons.camera_alt,
                      label: _takingPhoto ? 'Procesando...' : 'Tomar foto',
                      onTap: _busy || _takingPhoto ? null : _takePhoto,
                    ),
                  ),
                ],
              ),
            ),

            // Lista de adjuntos
            if (_picked.isNotEmpty)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: ListView.separated(
                    itemCount: _picked.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final f = _picked[i];
                      final isImg = f.name.toLowerCase().endsWith('.png') ||
                          f.name.toLowerCase().endsWith('.jpg') ||
                          f.name.toLowerCase().endsWith('.jpeg');
                      return Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: ListTile(
                          leading: Icon(isImg ? Icons.image : Icons.insert_drive_file_outlined, color: Colors.black87),
                          title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text('${(f.size / 1024).toStringAsFixed(1)} KB'),
                          trailing: IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: _busy ? null : () => setState(() => _picked.removeAt(i)),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              )
            else
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Puedes adjuntar fotos o documentos como evidencia.',
                  style: TextStyle(fontFamily: kArial, color: Colors.black54),
                ),
              ),

            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),

            // CTA
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _busy || !_canSend ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kMarronOscuro,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    elevation: 4,
                  ),
                  child: _busy
                      ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Enviar novedad', style: TextStyle(fontFamily: kArial)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _ActionButton({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: enabled ? kMarronOscuro : Colors.grey.shade400,
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white),
              const SizedBox(width: 8),
              Text(label, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontFamily: kArial)),
            ],
          ),
        ),
      ),
    );
  }
}
