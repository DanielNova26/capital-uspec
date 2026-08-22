// lib/home/notify_avances_screen.dart
//
// Unificado con TaskService:
// - No hace uploads directos aquí
// - No usa callable notifyTaskNews
// - NO doble notificación
// - Próxima fecha: OPCIONAL
//
// Requiere: file_picker, image_picker, geolocator, permission_handler, intl

import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'package:todo/utils/task_status.dart';
import 'package:todo/widgets/task_action_context_card.dart';

import '../services/task_service.dart';

const Color kMarronOscuro = Color(0xFF145DA0);
const String kArial = 'Arial';

class NotifyAvancesScreen extends StatefulWidget {
  final String taskId;
  final String currentUserId;

  const NotifyAvancesScreen({
    super.key,
    required this.taskId,
    required this.currentUserId,
  });

  @override
  State<NotifyAvancesScreen> createState() => _NotifyAvancesScreenState();
}

class _NotifyAvancesScreenState extends State<NotifyAvancesScreen> {
  final _taskService = TaskService();

  final _descCtrl = TextEditingController();
  DateTime? _nextDate; // ✅ opcional

  bool _loading = false;
  String? _error, _success;

  final _picker = ImagePicker();
  final List<PlatformFile> _files = [];
  final List<Map<String, dynamic>> _photoMeta = [];

  Map<String, dynamic>? _task;
  String? _taskTitle;
  String? _currentUserName;

  @override
  void initState() {
    super.initState();
    _loadContext();
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
  }

  String _displayUserName(Map<String, dynamic> user) {
    final nombres = (user['nombres'] ?? '').toString().trim();
    final apellidos = (user['apellidos'] ?? '').toString().trim();
    final full = '$nombres $apellidos'.trim();
    if (full.isNotEmpty) return full;
    final alt =
        [
              user['primerNombre'],
              user['segundoNombre'],
              user['primerApellido'],
              user['segundoApellido'],
            ]
            .map((e) => (e ?? '').toString().trim())
            .where((e) => e.isNotEmpty)
            .join(' ');
    if (alt.isNotEmpty) return alt;
    return (user['nombre'] ?? user['usuario'] ?? widget.currentUserId)
        .toString()
        .trim();
  }

  Future<void> _loadContext() async {
    try {
      final results = await Future.wait([
        _taskService.getTask(widget.taskId),
        FirebaseFirestore.instance
            .collection('TBL_USUARIOS')
            .doc(widget.currentUserId)
            .get(),
      ]);
      final taskSnap = results[0];
      final userSnap = results[1];
      if (!mounted) return;
      final task = taskSnap.data() ?? {};
      final user = userSnap.data() ?? {};
      setState(() {
        _task = task;
        _taskTitle = (task['titulo'] ?? task['title'] ?? 'Tarea').toString();
        _currentUserName = _displayUserName(user);
      });
    } catch (_) {}
  }

  DateTime? _taskDueDate() {
    final raw = _task?['fecha_limite'] ?? _task?['dueDate'];
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  Future<bool> _ensureLocationPerm() async {
    final s = await Permission.locationWhenInUse.status;
    if (!s.isGranted) {
      final r = await Permission.locationWhenInUse.request();
      if (!r.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Permiso de ubicación necesario')),
          );
        }
        return false;
      }
    }
    return true;
  }

  Future<void> _pickFiles() async {
    final res = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.custom,
      allowedExtensions: const [
        'pdf',
        'doc',
        'docx',
        'xls',
        'xlsx',
        'ppt',
        'pptx',
        'zip',
        'jpg',
        'jpeg',
        'png',
      ],
    );
    if (res != null && res.files.isNotEmpty) {
      setState(() => _files.addAll(res.files));
    }
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

  Future<void> _takePhoto() async {
    if (!await _ensureLocationPerm()) return;

    final x = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
    );
    if (x == null) return;

    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );

    final now = DateTime.now();
    final lines = [
      DateFormat('dd/MM/yyyy HH:mm').format(now),
      '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}',
      'Foto por: ${widget.currentUserId}',
    ];

    // base
    final raw = await x.readAsBytes();
    final codec = await ui.instantiateImageCodec(raw);
    final frame = await codec.getNextFrame();
    final img = frame.image;

    // logo
    ui.Image? logo;
    try {
      final ld = await rootBundle.load('assets/logo.png');
      final lc = await ui.instantiateImageCodec(ld.buffer.asUint8List());
      logo = (await lc.getNextFrame()).image;
    } catch (_) {}

    // dibujar marca
    const p = 16.0;
    final blockH = lines.length * 30.0 + p * 2;
    final blockW = img.width * 0.60;

    final rec = ui.PictureRecorder();
    final canvas = Canvas(
      rec,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
    );
    canvas.drawImage(img, Offset.zero, Paint());

    final rect = Rect.fromLTWH(
      img.width - blockW - p,
      img.height - blockH - p,
      blockW + p,
      blockH + p,
    );
    canvas.drawRect(rect, Paint()..color = Colors.white.withValues(alpha: 0.9));

    if (logo != null) {
      final logoW = blockW * 0.15;
      final logoH = logoW * logo.height / logo.width;
      canvas.drawImageRect(
        logo,
        Rect.fromLTWH(0, 0, logo.width.toDouble(), logo.height.toDouble()),
        Rect.fromLTWH(
          rect.left + p,
          rect.top + (rect.height - logoH) / 2,
          logoW,
          logoH,
        ),
        Paint(),
      );
    }

    final style = const TextStyle(
      color: Colors.black87,
      fontSize: 28,
      fontFamily: kArial,
      fontWeight: FontWeight.bold,
    );

    final startX = rect.left + p * 2 + (logo != null ? (blockW * 0.15) : 0);
    for (var i = 0; i < lines.length; i++) {
      final tp = TextPainter(
        text: TextSpan(text: lines[i], style: style),
        textDirection: ui.TextDirection.ltr,
      );
      tp.layout(maxWidth: rect.width - p * 3);
      tp.paint(canvas, Offset(startX, rect.top + p + i * 30));
    }

    final picture = rec.endRecording();
    final finalImg = await picture.toImage(img.width, img.height);
    final bd = await finalImg.toByteData(format: ui.ImageByteFormat.png);
    final png = bd!.buffer.asUint8List();

    setState(() {
      _files.add(
        PlatformFile(
          name: 'foto_${now.millisecondsSinceEpoch}.png',
          bytes: png,
          size: png.length,
        ),
      );
      _photoMeta.add({
        'lat': pos.latitude,
        'lng': pos.longitude,
        'when': now.toIso8601String(),
      });
    });
  }

  Future<void> _pickNextDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (d != null) setState(() => _nextDate = d);
  }

  Future<void> _submit() async {
    final msg = _descCtrl.text.trim();
    if (msg.isEmpty) {
      setState(() => _error = 'Describe el avance');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _success = null;
    });

    try {
      final atts = <TaskAttachment>[];
      for (final f in _files) {
        final bytes =
            f.bytes ??
            (f.path != null ? await File(f.path!).readAsBytes() : null);
        if (bytes == null) continue;
        atts.add(
          TaskAttachment(
            filename: f.name,
            bytes: bytes,
            contentType: _guessMime(f.name),
          ),
        );
      }

      await _taskService.addAvance(
        taskId: widget.taskId,
        byUserId: widget.currentUserId,
        byUserName: _currentUserName ?? widget.currentUserId,
        message: msg,
        nextDate: _nextDate, // ✅ opcional
        attachments: atts,
        photoMeta: _photoMeta,
      );

      setState(() {
        _success = 'Avance enviado';
        _descCtrl.clear();
        _nextDate = null;
        _files.clear();
        _photoMeta.clear();
      });
    } catch (e) {
      setState(() => _error = 'Error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final status = _task == null ? '' : resolveTaskStatus(_task!);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
          tooltip: 'Volver',
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'Reportar avance',
              maxLines: 1,
              style: TextStyle(
                fontFamily: kArial,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
            Text(
              'Notifica el progreso realizado',
              maxLines: 1,
              style: TextStyle(
                fontFamily: kArial,
                fontSize: 11,
                fontWeight: FontWeight.w400,
                color: Color(0xCCFFFFFF),
              ),
            ),
          ],
        ),
        backgroundColor: kMarronOscuro,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusScope.of(context).unfocus(),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: Column(
              children: [
                if (_error != null)
                  _BannerMsg(
                    msg: _error!,
                    color: Colors.red.shade50,
                    textColor: Colors.red.shade700,
                    icon: Icons.error_outline,
                  ),
                if (_success != null)
                  _BannerMsg(
                    msg: _success!,
                    color: Colors.green.shade50,
                    textColor: Colors.green.shade800,
                    icon: Icons.check_circle,
                  ),

                TaskActionContextCard(
                  title: _taskTitle ?? 'Cargando tarea...',
                  status: status,
                  dueDate: _taskDueDate(),
                  icon: Icons.trending_up_rounded,
                  accentColor: kMarronOscuro,
                  subtitle: _currentUserName == null
                      ? null
                      : 'Reporta: $_currentUserName',
                ),
                const SizedBox(height: 12),

                Card(
                  elevation: 1.5,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Detalle del avance',
                          style: textTheme.titleMedium?.copyWith(
                            fontFamily: kArial,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _descCtrl,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            labelText: 'Descripción',
                            hintText: '¿Qué hiciste? ¿Qué sigue?',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.event_available),
                          title: Text(
                            _nextDate == null
                                ? 'Fecha próxima actividad (opcional)'
                                : 'Próxima: ${DateFormat('dd/MM/yyyy').format(_nextDate!)}',
                            style: const TextStyle(fontFamily: kArial),
                          ),
                          trailing: Wrap(
                            spacing: 8,
                            children: [
                              if (_nextDate != null)
                                IconButton(
                                  tooltip: 'Quitar fecha',
                                  onPressed: () =>
                                      setState(() => _nextDate = null),
                                  icon: const Icon(Icons.clear),
                                ),
                              FilledButton.icon(
                                onPressed: _pickNextDate,
                                icon: const Icon(Icons.calendar_today),
                                label: const Text('Elegir'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                Card(
                  elevation: 1.5,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Evidencia (opcional)',
                          style: textTheme.titleMedium?.copyWith(
                            fontFamily: kArial,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Puedes tomar una foto con marca de agua o adjuntar archivos.',
                          style: textTheme.bodySmall?.copyWith(
                            color: Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            ElevatedButton.icon(
                              onPressed: _takePhoto,
                              icon: const Icon(Icons.photo_camera_outlined),
                              label: const Text('Tomar foto'),
                            ),
                            FilledButton.icon(
                              onPressed: _pickFiles,
                              icon: const Icon(Icons.attach_file),
                              label: const Text('Adjuntar archivos'),
                            ),
                          ],
                        ),
                        if (_files.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _files.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 8),
                            itemBuilder: (_, i) {
                              final f = _files[i];
                              return Row(
                                children: [
                                  const Icon(
                                    Icons.insert_drive_file_outlined,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      f.name,
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  ),
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () =>
                                        setState(() => _files.removeAt(i)),
                                    icon: const Icon(Icons.close),
                                  ),
                                ],
                              );
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 18),

                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: kMarronOscuro,
                    ),
                    onPressed: _loading ? null : _submit,
                    icon: _loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send),
                    label: Text(_loading ? 'Enviando…' : 'Enviar avance'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BannerMsg extends StatelessWidget {
  final String msg;
  final Color color;
  final Color textColor;
  final IconData icon;

  const _BannerMsg({
    required this.msg,
    required this.color,
    required this.textColor,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: textColor.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: textColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(msg, style: TextStyle(color: textColor)),
          ),
        ],
      ),
    );
  }
}
