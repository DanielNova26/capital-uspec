// lib/home/notify_avances_screen.dart
// Pantalla para reportar AVANCES con foto marcada, adjuntos y próxima fecha.
// Notifica al creador y al jefe via callable `notifyTaskNews`.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

const Color kMarronOscuro = Color(0xFF145DA0);
const String kArial = 'Arial';

class NotifyAvancesScreen extends StatefulWidget {
  final String taskId;
  final String currentUserId;
  const NotifyAvancesScreen({
    Key? key,
    required this.taskId,
    required this.currentUserId,
  }) : super(key: key);

  @override
  State<NotifyAvancesScreen> createState() => _NotifyAvancesScreenState();
}

class _NotifyAvancesScreenState extends State<NotifyAvancesScreen> {
  final _descCtrl = TextEditingController();
  DateTime? _nextDate;

  bool _loading = false;
  String? _error, _success;

  final _picker = ImagePicker();
  List<PlatformFile> _files = [];
  final List<Map<String, dynamic>> _photoMeta = [];

  @override
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
  }

  /* ---------------- Helpers ---------------- */

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
      withData: true, // por si no tienes path (p.ej. web)
      type: FileType.custom,
      allowedExtensions: const [
        'pdf','doc','docx','xls','xlsx','ppt','pptx','zip','jpg','jpeg','png'
      ],
    );
    if (res != null && res.files.isNotEmpty) {
      setState(() => _files.addAll(res.files));
    }
  }

  String _guessMime(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    switch (ext) {
      case 'pdf': return 'application/pdf';
      case 'doc': return 'application/msword';
      case 'docx': return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls': return 'application/vnd.ms-excel';
      case 'xlsx': return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'ppt': return 'application/vnd.ms-powerpoint';
      case 'pptx': return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      case 'zip': return 'application/zip';
      case 'jpg':
      case 'jpeg': return 'image/jpeg';
      case 'png': return 'image/png';
      default: return 'application/octet-stream';
    }
  }

  Future<void> _takePhoto() async {
    if (!await _ensureLocationPerm()) return;

    final x = await _picker.pickImage(source: ImageSource.camera, imageQuality: 90);
    if (x == null) return;

    final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    final tarea = await FirebaseFirestore.instance.collection('TBL_TAREAS').doc(widget.taskId).get();
    final photographer = (tarea.data()?['asignado_nombre'] ??
        tarea.data()?['assignedToName'] ??
        'Desconocido').toString();

    final now = DateTime.now();
    final lines = [
      DateFormat('dd/MM/yyyy HH:mm').format(now),
      '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}',
      'Foto por: $photographer',
    ];

    // base
    final raw = await File(x.path).readAsBytes();
    final codec = await ui.instantiateImageCodec(raw);
    final frame = await codec.getNextFrame();
    final img = frame.image;

    // logo
    ui.Image? logo;
    try {
      final ld = await rootBundle.load('assets/logo.png');
      final lc = await ui.instantiateImageCodec(ld.buffer.asUint8List());
      final lf = await lc.getNextFrame();
      logo = lf.image;
    } catch (_) {}

    // dibujar marca
    const p = 16.0;
    final blockH = lines.length * 30.0 + p * 2;
    final blockW = img.width * 0.60;

    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()));
    canvas.drawImage(img, Offset.zero, Paint());

    final rect = Rect.fromLTWH(
      img.width - blockW - p,
      img.height - blockH - p,
      blockW + p,
      blockH + p,
    );
    canvas.drawRect(rect, Paint()..color = Colors.white.withOpacity(0.9));

    if (logo != null) {
      final logoW = blockW * 0.15;
      final logoH = logoW * logo.height / logo.width;
      canvas.drawImageRect(
        logo,
        Rect.fromLTWH(0, 0, logo.width.toDouble(), logo.height.toDouble()),
        Rect.fromLTWH(rect.left + p, rect.top + (rect.height - logoH) / 2, logoW, logoH),
        Paint(),
      );

      final style = const TextStyle(
        color: Colors.black87,
        fontSize: 28,
        fontFamily: kArial,
        fontWeight: FontWeight.bold,
      );
      for (var i = 0; i < lines.length; i++) {
        final tp = TextPainter(
          text: TextSpan(text: lines[i], style: style),
          textDirection: ui.TextDirection.ltr,
        );
        tp.layout(maxWidth: rect.width - logoW - p * 3);
        tp.paint(canvas, Offset(rect.left + logoW + p * 2, rect.top + p + i * 30));
      }
    }

    final picture = rec.endRecording();
    final finalImg = await picture.toImage(img.width, img.height);
    final bd = await finalImg.toByteData(format: ui.ImageByteFormat.png);
    final png = bd!.buffer.asUint8List();

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${now.millisecondsSinceEpoch}.png');
    await file.writeAsBytes(png);

    setState(() {
      _files.add(PlatformFile(
        name: file.path.split('/').last,
        path: file.path,
        size: file.lengthSync(),
        bytes: png,
      ));
      _photoMeta.add({
        'path': file.path,
        'lat': pos.latitude,
        'lng': pos.longitude,
        'when': now.toIso8601String(),
        'by': photographer,
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
    if (_descCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Describe el avance');
      return;
    }
    if (_nextDate == null) {
      setState(() => _error = 'Selecciona la próxima fecha');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _success = null;
    });

    try {
      final tareaDoc = await FirebaseFirestore.instance
          .collection('TBL_TAREAS')
          .doc(widget.taskId)
          .get();
      final t = tareaDoc.data() ?? {};

      // Destinatarios (robusto con varios nombres de campo)
      final creatorId = (t['creador_id'] ?? t['creatorId'])?.toString();
      final bossId = (t['jefe_uid'] ?? t['bossId'] ?? t['delegatedTo'])?.toString();
      final assignedName = (t['asignado_nombre'] ?? t['assignedToName'] ?? '').toString();

      // Subida de adjuntos con metadatos
      final List<Map<String, dynamic>> uploaded = [];
      for (final f in _files) {
        final name = f.name;
        final mime = _guessMime(name);
        final bytes = f.bytes ?? (f.path != null ? await File(f.path!).readAsBytes() : null);
        if (bytes == null) continue;

        final now = DateTime.now();
        final y = DateFormat('yyyy').format(now);
        final m = DateFormat('MM').format(now);
        final d = DateFormat('dd').format(now);
        final storagePath = 'tareas/$y/$m/$d/avc_${now.millisecondsSinceEpoch}_$name';

        final ref = FirebaseStorage.instance.ref(storagePath);
        await ref.putData(bytes, SettableMetadata(contentType: mime));
        String url = await ref.getDownloadURL();

        uploaded.add({
          'name': name,
          'url': url,
          'mime': mime,
          'size': f.size,
          'uploadedAt': Timestamp.now(),
        });
      }

      // Guardar avance (subcolección)
      final col = FirebaseFirestore.instance
          .collection('TBL_TAREAS')
          .doc(widget.taskId)
          .collection('avances');

      await col.add({
        'description': _descCtrl.text.trim(),
        'nextDate': Timestamp.fromDate(_nextDate!),
        'attachments': uploaded,      // mapas con name/url/mime/size
        'photoMeta': _photoMeta,      // info de fotos con marca
        'createdAt': Timestamp.now(), // evita serverTimestamp en paths problemáticos
        'by': widget.currentUserId,
      });

      // Notificación: usa callable (y no rompe si falla)
      try {
        final fn = FirebaseFunctions.instance.httpsCallable('notifyTaskNews');
        await fn.call({
          'taskId': widget.taskId,
          'creatorId': creatorId ?? '',
          'bossId': bossId ?? '',
          'title': 'Avance en tarea',
          'body': _descCtrl.text.trim(),
        });
      } catch (e) {
        debugPrint('[notifyTaskNews] fallo opcional: $e');
      }

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
    final tarea = (await FirebaseFirestore.instance
        .collection('TBL_TAREAS')
        .doc(widget.taskId)
        .get()).data()!;
    final creatorId = (tarea['creador_id'] ?? tarea['creatorId'])?.toString();
    final bossId    = (tarea['jefe_uid']   ?? tarea['delegatedTo'])?.toString();

// …después de guardar el avance:
    final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
    await functions.httpsCallable('notifyTaskNews').call({
      'taskId': widget.taskId,
      'title': 'Avance en tarea',
      'body': _descCtrl.text.trim() +
          (_nextDate != null ? ' · Próxima: ${DateFormat('dd/MM/yyyy').format(_nextDate!)}' : ''),
      'creatorId': creatorId ?? '',
      'bossId': bossId ?? '',
    });
  }

  /* ---------------- UI ---------------- */

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notificar avances', style: TextStyle(fontFamily: kArial)),
        backgroundColor: kMarronOscuro,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            children: [
              if (_error != null)
                _BannerMsg(msg: _error!, color: Colors.red.shade50, textColor: Colors.red.shade700, icon: Icons.error_outline),
              if (_success != null)
                _BannerMsg(msg: _success!, color: Colors.green.shade50, textColor: Colors.green.shade800, icon: Icons.check_circle),

              // Card principal
              Card(
                elevation: 1.5,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Detalle del avance', style: textTheme.titleMedium?.copyWith(fontFamily: kArial, fontWeight: FontWeight.w600)),
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
                              ? 'Fecha próxima actividad'
                              : 'Próxima: ${DateFormat('dd/MM/yyyy').format(_nextDate!)}',
                          style: const TextStyle(fontFamily: kArial),
                        ),
                        trailing: FilledButton.icon(
                          onPressed: _pickNextDate,
                          icon: const Icon(Icons.calendar_today),
                          label: const Text('Elegir'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Card de evidencia
              Card(
                elevation: 1.5,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Evidencia (opcional)', style: textTheme.titleMedium?.copyWith(fontFamily: kArial, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Text(
                        'Puedes tomar una foto (se agrega marca de agua con datos) o adjuntar archivos (PDF, Office, imágenes, ZIP).',
                        style: textTheme.bodySmall?.copyWith(color: Colors.black54),
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
                          separatorBuilder: (_, __) => const Divider(height: 8),
                          itemBuilder: (_, i) {
                            final f = _files[i];
                            return Row(
                              children: [
                                const Icon(Icons.insert_drive_file_outlined, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(f.name, overflow: TextOverflow.ellipsis, maxLines: 1),
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () => setState(() => _files.removeAt(i)),
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
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send),
                  label: Text(_loading ? 'Enviando…' : 'Enviar avance'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ------- Widgets auxiliares ------- */

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
        border: Border.all(color: textColor.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: textColor),
          const SizedBox(width: 8),
          Expanded(child: Text(msg, style: TextStyle(color: textColor))),
        ],
      ),
    );
  }
}
