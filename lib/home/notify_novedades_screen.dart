// lib/home/notify_novedades_screen.dart
//
// Unificado con TaskService:
// - No sube archivos directo aquí
// - No usa callable notifyTaskNews
// - Notifica vía TaskService (subcolección notifications)
//
// Requiere: file_picker, image_picker, geolocator, permission_handler, intl

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:todo/utils/task_status.dart';

import '../services/task_service.dart';

const Color kMarronOscuro = Color(0xFF145DA0);
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
  final _taskService = TaskService();

  final _descCtrl = TextEditingController();
  bool _busy = false;
  String? _error;
  bool _takingPhoto = false;

  final _picker = ImagePicker();
  final List<PlatformFile> _picked = [];
  final List<Map<String, dynamic>> _photoMeta = [];

  Position? _pos;
  String? _coordsStr;

  Map<String, dynamic>? _task;
  String? _taskTitle;

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

  Future<void> _loadTask() async {
    try {
      final snap = await _taskService.getTask(widget.taskId);
      final m = snap.data() ?? {};
      setState(() {
        _task = m;
        _taskTitle = (m['titulo'] ?? m['title'] ?? 'Tarea').toString();
      });
    } catch (_) {}
  }

  Future<void> _ensureLocation() async {
    try {
      final s = await Permission.locationWhenInUse.status;
      if (!s.isGranted) {
        await Permission.locationWhenInUse.request();
      }
      if (!await Geolocator.isLocationServiceEnabled()) {
        await Geolocator.openLocationSettings();
      }
      _pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      _coordsStr = '${_pos!.latitude.toStringAsFixed(5)}, ${_pos!.longitude.toStringAsFixed(5)}';
      if (mounted) setState(() {});
    } catch (_) {}
  }

  String _guessMime(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    switch (ext) {
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'ppt':
        return 'application/vnd.ms-powerpoint';
      case 'pptx':
        return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      case 'zip':
        return 'application/zip';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      default:
        return 'application/octet-stream';
    }
  }

  Future<void> _pickFiles() async {
    final res = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.custom,
      allowedExtensions: const [
        'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'zip', 'jpg', 'jpeg', 'png',
      ],
    );
    if (res != null && res.files.isNotEmpty) {
      setState(() => _picked.addAll(res.files));
    }
  }

  Future<ui.Image> _decodeUiImage(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  Future<Uint8List?> _buildWatermarkedBytes({
    required ui.Image base,
    required String logoAsset,
    required String header,
    required String title,
    required String who,
    String? coords,
  }) async {
    ui.Image? logo;
    try {
      final lb = await rootBundle.load(logoAsset);
      final lc = await ui.instantiateImageCodec(lb.buffer.asUint8List());
      logo = (await lc.getNextFrame()).image;
    } catch (_) {}

    final rec = ui.PictureRecorder();
    final c = Canvas(rec, Rect.fromLTWH(0, 0, base.width.toDouble(), base.height.toDouble()));

    c.drawImage(base, Offset.zero, Paint()..filterQuality = ui.FilterQuality.medium);

    final overlayH = (base.height * 0.24).clamp(150.0, 280.0);
    final overlay = Rect.fromLTWH(0, base.height - overlayH, base.width.toDouble(), overlayH);
    c.drawRect(overlay, Paint()..color = const Color(0xCC000000));

    const pad = 16.0;
    final col1W = base.width * 0.18;
    final col2W = base.width * 0.82;

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

    final lines = <String>[
      '$header • ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}',
      'Tarea: $title',
      'Reporta: $who',
      if (coords != null) 'Ubicación: $coords',
    ];

    final pb = ui.ParagraphBuilder(ui.ParagraphStyle(maxLines: 8, ellipsis: '…'))
      ..pushStyle(ui.TextStyle(color: Colors.white.withOpacity(0.96), fontSize: 24));
    pb.addText(lines.join('\n'));
    final p = pb.build()..layout(ui.ParagraphConstraints(width: rText.width));
    c.drawParagraph(p, Offset(rText.left, rText.top));

    final picture = rec.endRecording();
    final out = await picture.toImage(base.width, base.height);
    final png = await out.toByteData(format: ui.ImageByteFormat.png);
    return png?.buffer.asUint8List();
  }

  Future<void> _takePhoto() async {
    if (_takingPhoto) return;
    setState(() => _takingPhoto = true);
    try {
      final x = await _picker.pickImage(source: ImageSource.camera, imageQuality: 88);
      if (x == null) return;

      final raw = await x.readAsBytes();
      final img = await _decodeUiImage(raw);

      final wm = await _buildWatermarkedBytes(
        base: img,
        logoAsset: 'assets/logo.png',
        header: 'Novedad',
        title: _taskTitle ?? 'Tarea',
        who: widget.currentUserId,
        coords: _coordsStr,
      );
      if (wm == null) return;

      final name = 'nvd_${DateTime.now().millisecondsSinceEpoch}.png';
      setState(() {
        _picked.add(PlatformFile(name: name, bytes: wm, size: wm.length));
        _photoMeta.add({
          'coords': _coordsStr ?? '',
          'when': DateTime.now().toIso8601String(),
        });
      });
    } finally {
      if (mounted) setState(() => _takingPhoto = false);
    }
  }

  bool get _canSend {
    final txt = _descCtrl.text.trim();
    return txt.isNotEmpty && txt.length <= _maxDescLen;
  }

  Future<void> _submit() async {
    if (!_canSend) {
      setState(() => _error = _descCtrl.text.trim().isEmpty
          ? 'Describe la novedad'
          : 'La descripción supera el límite de $_maxDescLen caracteres');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final atts = <TaskAttachment>[];
      for (final f in _picked) {
        final bytes = f.bytes ?? (f.path != null ? await File(f.path!).readAsBytes() : null);
        if (bytes == null) continue;
        atts.add(TaskAttachment(
          filename: f.name,
          bytes: bytes,
          contentType: _guessMime(f.name),
        ));
      }

      final geoloc = (_pos == null) ? null : {'lat': _pos!.latitude, 'lng': _pos!.longitude};

      await _taskService.addNovedad(
        taskId: widget.taskId,
        byUserId: widget.currentUserId,
        byUserName: '', // si tienes nombre en sesión, ponlo aquí
        message: _descCtrl.text.trim(),
        geoloc: geoloc,
        attachments: atts,
        photoMeta: _photoMeta,
      );

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

  @override
  Widget build(BuildContext context) {
    final estado = _task == null ? '' : resolveTaskStatus(_task!);
    final due = _task?['fecha_limite'];

    String fmtDue(dynamic ts) {
      if (ts is Timestamp) return DateFormat('dd/MM/yyyy HH:mm').format(ts.toDate());
      return '—';
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF7FBF7),
      appBar: AppBar(
        backgroundColor: kMarronOscuro,
        title: const Text('Notificar novedades', style: TextStyle(fontFamily: kArial)),
      ),
      body: SafeArea(
    child: GestureDetector(
    behavior: HitTestBehavior.translucent,
    onTap: () => FocusScope.of(context).unfocus(),
    child: Column(
    children: [
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
                                    estado.isEmpty ? 'en_progreso' : estado,
                                    style: const TextStyle(color: Colors.white, fontFamily: kArial),
                                  ),
                                ),
                                Chip(
                                  label: Text(
                                    'Vence: ${fmtDue(due)}',
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

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: TextField(
                controller: _descCtrl,
                minLines: 3,
                maxLines: 6,
                maxLength: _maxDescLen,
                decoration: InputDecoration(
                  labelText: 'Descripción de la novedad',
                  hintText: '¿Qué ocurrió?',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),

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
                          leading: Icon(isImg ? Icons.image : Icons.insert_drive_file_outlined),
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
    ? const SizedBox(
    height: 22,
    width: 22,
    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
    )
        : const Text('Enviar novedad', style: TextStyle(fontFamily: kArial)),
    ),
    ),
    ),
    ],
    ),
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
